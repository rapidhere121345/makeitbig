extends SceneTree

## WP4-C: real deterministic acceptance gate for the threshold colossus kill.
## Drives the production embedded-session runtime and asserts the kill lands in
## [45, 120] simulated seconds.
##
## Honored contracts:
##  * no FakeArena, no victory injection, no boss health / boss_damage writes;
##  * input is the formal qualified exponential Build resolved through the
##    production BuildResolver from current content (the "exponential" ranger
##    preset = the calibration_exponential fixture: p=0.61, T=34, d=150, v=620,
##    turn=0.18, damage=160, breeding_split + pack_hunt_mark);
##  * a real Main instance is configured exactly like the production
##    LegacyArenaAdapter (embedded_session, framework_room with boss
##    threshold_colossus, framework_resolved_build, automation_smoke=false) and
##    entered via _enter_arena(), then advanced one authoritative
##    _simulate_tick() at a time — ticks are never skipped or rewound;
##  * the player is driven only through the public request flags that the real
##    HUD / keyboard handlers write (attack_requested = Skill 1 button / SPACE,
##    dodge_requested = SHIFT), casting exactly on the fixed cooldown;
##  * no wall clock is read anywhere in the assertions.

const MainScript := preload("res://src/game/main.gd")
const EarlyRegistryScript := preload("res://src/content/early_item_registry.gd")
const ResolverScript := preload("res://src/systems/build_resolver.gd")

const ACCEPTANCE_MIN_SECONDS: float = 45.0
const ACCEPTANCE_MAX_SECONDS: float = 120.0
## Fixed standoff used by the deterministic ranger driver. The colossus never
## moves, so holding a fixed in-range point is a valid range-control policy.
const RANGE_HOLD_DISTANCE: float = 100.0

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	# Pin the viewport so the arena rectangle and spawn geometry are stable
	# across machines and headless display drivers.
	root.size = Vector2i(1280, 720)

	var build := _resolve_qualified_build()
	if not bool(build.get("ok", false)):
		_finish(null)
		return

	var arena = MainScript.new()
	# Same embedded configuration order as the production LegacyArenaAdapter.
	arena.embedded_session = true
	arena.test_session = true
	arena.automation_smoke = false
	arena.selected_mode = "Manual"
	arena.selected_preset = "exponential"
	arena.framework_resolved_build = build.duplicate(true)
	arena.framework_active_build = {"skills": ["piercing_arrow", "hunter_mark", "dash"]}
	arena.framework_room = {
		"room_id": "acceptance.threshold_colossus",
		"layout_id": "rectangle_arena",
		"objective_id": "hunt_elite",
		"hazard_ids": ["moving_fireline"],
		"enemy_ids": [],
		"elite_rule_ids": [],
		"boss_id": "threshold_colossus",
		"drop_tags": ["proxy_core_fixed"],
	}
	root.add_child(arena)
	await process_frame

	arena._enter_arena()
	if not arena.in_arena:
		_expect(false, "arena deployment was blocked: %s" % String(arena.last_save_message))
		_finish(arena)
		return
	_expect(arena.boss != null and arena.boss.kind_id == "threshold_colossus" and arena.boss.entity_id == 1,
		"embedded room did not spawn the authoritative threshold colossus")
	_expect(is_equal_approx(arena.player_maximum_health, 112.0),
		"qualified build did not grant the 112 vitality pool")

	# Deterministic qualified-player placement: stand at a fixed in-range point
	# before the first tick. All motion afterwards flows through real tick
	# commands (dodge displacement) — this single write is deployment setup.
	arena.player_position = arena.boss.position + Vector2(-RANGE_HOLD_DISTANCE, 0.0)

	var tick_cap: int = int(ACCEPTANCE_MAX_SECONDS) * int(arena.SIM_TICKS_PER_SECOND)
	var transition_tick: int = -1
	var phase_two_tick: int = -1
	var damage_events: Array[String] = []
	while not arena.battle_over and arena.sim_tick < tick_cap:
		var pressed_action := ""
		if arena.boss != null and arena.boss.health > 0.0:
			if transition_tick < 0 and arena.boss.phase_state == "transition":
				transition_tick = arena.sim_tick
			if phase_two_tick < 0 and arena.boss.phase_id == "awakened":
				phase_two_tick = arena.sim_tick
			# Dodge one tick before each telegraphed impact, exactly like a
			# player reacting to the fixed windup telegraph (SHIFT handler).
			var boss_impact_next: bool = int(arena.boss.impact_tick) == int(arena.sim_tick) + 1
			var fireline_near_next: bool = _moving_fireline_near_next_tick(arena)
			if (boss_impact_next or fireline_near_next) and arena.dodge_cooldown_ticks == 0:
				pressed_action = _press_vertical_dodge(arena.player_position, arena.boss.position)
				arena.dodge_requested = true
		# Hold the Skill 1 request every tick; the fixed 13-tick cooldown in
		# _cast_skill_one() is the only gate, so this casts exactly on cooldown.
		arena.attack_requested = true
		var health_before: float = float(arena.player_health)
		arena._simulate_tick()
		if not pressed_action.is_empty():
			Input.action_release(pressed_action)
		if float(arena.player_health) < health_before:
			damage_events.append("tick=%d amount=%.1f boss=%s/%s dodge_cd=%d" % [
				arena.sim_tick, health_before - float(arena.player_health),
				String(arena.boss.action_id) if arena.boss != null else "none",
				String(arena.boss.action_state) if arena.boss != null else "none",
				arena.dodge_cooldown_ticks,
			])

	var elapsed: float = float(arena.sim_tick) / float(arena.SIM_TICKS_PER_SECOND)
	var phase_two_reached: bool = arena.boss != null and arena.boss.phase_id == "awakened" and arena.boss.core_open
	_expect(arena.battle_over and arena.battle_victory,
		"battle did not end in victory (over=%s victory=%s tick=%d report=%s)" % [arena.battle_over, arena.battle_victory, arena.sim_tick, arena.battle_report])
	_expect(elapsed >= ACCEPTANCE_MIN_SECONDS and elapsed <= ACCEPTANCE_MAX_SECONDS,
		"kill elapsed %.3fs is outside [%.0f, %.0f]" % [elapsed, ACCEPTANCE_MIN_SECONDS, ACCEPTANCE_MAX_SECONDS])
	_expect(phase_two_reached,
		"boss never reached phase 2 before death (phase_id=%s core_open=%s)" % [arena.boss.phase_id if arena.boss != null else "<null>", arena.boss.core_open if arena.boss != null else false])
	_expect(arena.boss_damage.compare(arena.boss_maximum) >= 0,
		"accumulated damage %s did not reach the 1e12 threshold" % arena.boss_damage.to_short_string(6))
	_expect(arena.player_health > 0.0,
		"qualified driver died before the kill (health=%.1f)" % arena.player_health)
	_expect(arena.shots >= 100, "qualified driver did not execute a sustained real Skill 1 rotation")
	print("BOSSDUR elapsed=%.3f ticks=%d casts=%d damage=%s health=%.1f distance=%.1f position=%s transition_tick=%d phase_two_tick=%d" % [
		elapsed, arena.sim_tick, arena.shots, arena.boss_damage.to_short_string(6),
		arena.player_health, arena.player_position.distance_to(arena.boss.position) if arena.boss != null else -1.0,
		str(arena.player_position), transition_tick, phase_two_tick,
	])
	if not arena.battle_victory:
		print("BOSSDUR_DAMAGE %s" % "; ".join(damage_events))
	_finish(arena)


func _moving_fireline_near_next_tick(arena: Node) -> bool:
	var next_tick := int(arena.sim_tick) + 1
	var cycle_tick := next_tick % int(arena.HAZARD_CYCLE_TICKS)
	if cycle_tick < int(arena.HAZARD_WARNING_TICKS) or cycle_tick >= int(arena.HAZARD_WARNING_TICKS + arena.HAZARD_ACTIVE_TICKS):
		return false
	var rect: Rect2 = arena._arena_rect()
	var progress := float(cycle_tick) / float(int(arena.HAZARD_CYCLE_TICKS) - 1)
	var line_x := lerpf(rect.position.x, rect.end.x, progress)
	var dodge_step := float(arena.DODGE_SPEED) * float(arena.SIM_STEP_SECONDS)
	return absf(float(arena.player_position.x) - line_x) <= 17.0 + dodge_step


func _press_vertical_dodge(from: Vector2, anchor: Vector2) -> String:
	var action := "move_down" if from.y < anchor.y else "move_up"
	Input.action_press(action)
	return action


func _resolve_qualified_build() -> Dictionary:
	var registry = EarlyRegistryScript.new()
	var registry_errors: Array = registry.load_all()
	_expect(registry_errors.is_empty(), "early item registry failed to load: %s" % str(registry_errors))
	var resolver = ResolverScript.new(registry)
	var result: Dictionary = resolver.resolve_fixture("calibration_exponential")
	_expect(bool(result.get("ok", false)),
		"calibration_exponential fixture did not resolve: %s" % str(result.get("errors", [])))
	if not bool(result.get("ok", false)):
		return result
	_expect(String(result.get("growth_classification", "")) == "exponential",
		"resolver did not return the exponential classification")
	var parameters: Dictionary = result.get("final_parameters", {})
	_expect(is_equal_approx(float(parameters.get("p", 0.0)), 0.61), "qualified build p != 0.61")
	_expect(is_equal_approx(float(parameters.get("T", 0.0)), 34.0), "qualified build T != 34")
	_expect(is_equal_approx(float(parameters.get("d", 0.0)), 150.0), "qualified build d != 150")
	_expect(is_equal_approx(float(parameters.get("v", 0.0)), 620.0), "qualified build v != 620")
	_expect(is_equal_approx(float(parameters.get("turn", 0.0)), 0.18), "qualified build turn != 0.18")
	_expect(is_equal_approx(float(parameters.get("damage", 0.0)), 160.0), "qualified build damage != 160")
	_expect(String(result.get("build_fingerprint", "")).length() == 64,
		"qualified build fingerprint is not a 64-char SHA-256")
	_expect((result.get("rune_ids", []) as Array) == ["breeding_split"] and (result.get("law_ids", []) as Array) == ["pack_hunt_mark"],
		"qualified build semantic runes/laws changed")
	return result


func _finish(arena: Node) -> void:
	if arena != null and is_instance_valid(arena):
		root.remove_child(arena)
		arena.free()
	if failures.is_empty():
		print("PASS  tests/test_boss_duration.gd")
		quit(0)
		return
	for failure in failures:
		printerr("- %s" % failure)
	quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
