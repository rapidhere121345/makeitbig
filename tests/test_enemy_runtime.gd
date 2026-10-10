extends SceneTree

const MainScript := preload("res://src/game/main.gd")
const ApplicationStateScript := preload("res://src/game/application_state.gd")
const ContractPlanScript := preload("res://src/game/contract_plan.gd")


class FakeSaveStore:
	extends RefCounted

	var save_calls := 0

	func save(_payload: Variant) -> Dictionary:
		save_calls += 1
		return {"ok": true}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	root.size = Vector2i(1280, 720)
	var arena = MainScript.new()
	arena.embedded_session = true
	root.add_child(arena)
	await process_frame
	arena._spawn_wave()

	_test_spawn_roles(arena, failures)
	_test_damage_source_tracking(arena, failures)
	_test_charger_sequence(arena, failures)
	_test_fan_sequence(arena, failures)
	_test_fan_attack_radius_runtime(arena, failures)
	_test_same_role_action_lane_runtime(arena, failures)
	_test_recovery_end_has_same_tick_intent(arena, failures)
	_test_boss_runtime(arena, failures)
	_test_hash_role_sensitivity(arena, failures)
	_test_room_rosters_and_layouts(arena, failures)
	_test_public_proxy_geometry_snapshot(arena, failures)
	_test_authored_ring_runtime(arena, failures)
	_test_ring_charger_path_runtime(arena, failures)
	_test_charger_padding_edge_runtime(arena, failures)
	_test_invalid_charge_distance_runtime(arena, failures)
	_test_rectangle_runtime_does_not_detour(arena, failures)
	_test_room_completion_and_validation(arena, failures)
	_test_embedded_room_rewards(arena, failures)
	_test_hazards(arena, failures)
	_test_hazard_decision_boundaries(arena, failures)
	_test_elite_rules(arena, failures)
	_test_room_hash_sensitivity(arena, failures)
	_test_early_durability_and_first_hunt(arena, failures)

	root.remove_child(arena)
	arena.free()
	if failures.is_empty():
		print("PASS  test_enemy_runtime.gd")
		quit(0)
		return
	for failure in failures:
		printerr("- %s" % failure)
	quit(1)


func _test_spawn_roles(arena: Node, failures: Array[String]) -> void:
	var counts := {"melee_pursuer": 0, "charging_raider": 0, "fan_ranged": 0, "threshold_colossus": 0}
	var ids: Array[int] = []
	for enemy in arena.enemies:
		counts[enemy.kind_id] = int(counts.get(enemy.kind_id, 0)) + 1
		ids.append(enemy.entity_id)
	_expect(counts.melee_pursuer == 2 and counts.charging_raider == 2 and counts.fan_ranged == 2, "spawn: normal role distribution is not 2/2/2", failures)
	_expect(counts.threshold_colossus == 1 and arena.boss.kind_id == "threshold_colossus", "spawn: threshold colossus kind is missing", failures)
	_expect(ids == [1, 2, 3, 4, 5, 6, 7], "spawn: entity IDs are not stable and ordered", failures)


func _test_damage_source_tracking(arena: Node, failures: Array[String]) -> void:
	arena.sim_tick = 17
	arena.player_health = 100.0
	arena.last_damage_source_id = ""
	arena.last_damage_tick = -1
	arena.dodge_remaining_ticks = 0
	arena._damage_player(11.0, "enemy/charging_raider")
	_expect(String(arena.last_damage_source_id) == "enemy/charging_raider" and int(arena.last_damage_tick) == 17,
		"damage source: charging raider impact did not record a stable source", failures)

	arena.last_damage_source_id = "hazard/moving_fireline"
	arena.last_damage_tick = 999
	arena.dodge_remaining_ticks = 2
	arena._damage_player(9.0, "hazard/moving_fireline")
	_expect(String(arena.last_damage_source_id) == "hazard/moving_fireline" and int(arena.last_damage_tick) == 999,
		"damage source: avoided damage updated the last source", failures)

	arena.dodge_remaining_ticks = 0
	arena._damage_player(7.0, "hazard/exposed_ground_zone")
	arena._damage_player(1.2, "boss/slam")
	_expect(String(arena.last_damage_source_id) == "boss/slam", "damage source: boss action source was not authoritative", failures)
	arena.sim_tick = 18
	arena.player_health = 1.0
	arena._damage_player(5.0, "enemy/melee_pursuer")
	_expect(arena.player_health == 0.0
		and String(arena.last_damage_source_id) == "enemy/melee_pursuer"
		and int(arena.last_damage_tick) == 18,
		"damage source: fatal hit did not replace the prior source", failures)

	arena.last_damage_source_id = "enemy/melee_pursuer"
	arena.last_damage_tick = 123
	arena._spawn_wave()
	_expect(String(arena.last_damage_source_id).is_empty() and int(arena.last_damage_tick) == -1,
		"damage source: room entry did not reset death diagnostics", failures)


func _test_charger_sequence(arena: Node, failures: Array[String]) -> void:
	var charger = _enemy_of_kind(arena, "charging_raider")
	arena.sim_tick = 10
	arena.player_position = charger.position + Vector2(100.0, 0.0)
	arena.player_health = 100.0
	var contact_distance: float = charger.position.distance_to(arena.player_position)
	var accepted: bool = arena._start_charger_action(charger, charger.position.direction_to(arena.player_position), contact_distance)
	_expect(accepted and charger.action_state == "windup" and charger.impact_tick == 28, "charger: explicit-distance windup was not accepted", failures)
	_expect(is_equal_approx(charger.charge_length, 100.0), "charger: direct sequence did not freeze its explicit distance", failures)
	arena.sim_tick = charger.impact_tick
	var active_steps := 0
	while charger.action_state != "recovery" and arena.sim_tick <= charger.impact_tick + arena.CHARGE_ACTIVE_TICKS:
		var before: Vector2 = charger.position
		arena._update_charger_tick(charger)
		if charger.action_state == "active":
			active_steps += 1
			_expect(charger.position.distance_to(before) > 0.01, "charger: direct sequence swallowed an active body step", failures)
		if charger.action_state != "recovery":
			arena.sim_tick += 1
	var after_impact: float = arena.player_health
	_expect(active_steps == arena.CHARGE_ACTIVE_TICKS, "charger: direct sequence did not execute all active ticks", failures)
	_expect(charger.action_state == "recovery" and charger.impact_resolved and is_equal_approx(after_impact, 89.0), "charger: moving body did not complete with one contact hit", failures)
	arena.sim_tick += 1
	arena._update_charger_tick(charger)
	_expect(is_equal_approx(arena.player_health, after_impact), "charger: impact dealt damage more than once", failures)


func _test_fan_sequence(arena: Node, failures: Array[String]) -> void:
	var fan = _enemy_of_kind(arena, "fan_ranged")
	arena.sim_tick = 40
	arena.player_position = fan.position + Vector2(140.0, 0.0)
	arena.player_health = 100.0
	arena._start_fan_action(fan)
	_expect(fan.action_state == "windup" and fan.impact_tick == 61, "fan: windup or impact tick is wrong", failures)
	arena.sim_tick = fan.impact_tick
	arena._update_fan_tick(fan)
	var after_impact: float = arena.player_health
	_expect(fan.action_state == "active" and fan.impact_resolved, "fan: did not enter resolved active state", failures)
	_expect(is_equal_approx(after_impact, 92.0), "fan: authoritative cone did not deal expected impact damage", failures)
	arena._update_fan_tick(fan)
	_expect(is_equal_approx(arena.player_health, after_impact), "fan: impact dealt damage more than once", failures)
	arena.sim_tick = fan.state_ends_tick
	arena._update_fan_tick(fan)
	_expect(fan.action_state == "recovery", "fan: active did not advance to recovery", failures)


func _test_fan_attack_radius_runtime(arena: Node, failures: Array[String]) -> void:
	_configure_room(arena, "rectangle_arena", "clear", ["fan_ranged"])
	arena._spawn_wave()
	var fan = arena.enemies[0]
	arena.player_position = arena._arena_rect().get_center()
	arena.player_health = 100.0
	arena.dodge_remaining_ticks = 0

	## The old 228 planning band started a 175-radius cone here, which always
	## missed a stationary target. The runtime must now continue moving instead.
	fan.position = arena.player_position - Vector2.RIGHT * 200.0
	arena.sim_tick = 1
	var outside_before: Vector2 = fan.position
	arena._update_enemies_tick()
	_expect(fan.action_state == "none" and fan.motion_state == "moving" and fan.position != outside_before and String(fan.tactic_reason) == "fan_strafe_hold", "fan radius: target at 200 started an empty attack instead of moving", failures)

	## Exactly on the shared radius, the frozen target shape, impact resolver and
	## static player position must agree on one successful hit.
	fan.position = arena.player_position - Vector2.RIGHT * arena.EnemyTacticsScript.FAN_ATTACK_RADIUS
	arena.sim_tick = 40
	arena._update_enemies_tick()
	_expect(fan.action_state == "windup" and is_equal_approx(float(fan.target_shape.get("radius", 0.0)), arena.EnemyTacticsScript.FAN_ATTACK_RADIUS), "fan radius: legal start did not freeze the shared target shape", failures)
	arena.sim_tick = fan.impact_tick
	arena._update_enemies_tick()
	_expect(is_equal_approx(arena.player_health, 92.0), "fan radius: stationary target at the legal boundary was not hit", failures)
	arena.framework_room = {}
	arena._spawn_wave()


func _test_same_role_action_lane_runtime(arena: Node, failures: Array[String]) -> void:
	_configure_room(arena, "rectangle_arena", "clear", ["fan_ranged", "fan_ranged"])
	arena._spawn_wave()
	arena.combat_event_stream.reset()
	arena.player_health = 100.0
	arena.dodge_remaining_ticks = 0
	arena.player_position = arena._arena_rect().get_center()
	var first = arena.enemies[0]
	var waiting = arena.enemies[1]
	first.position = arena.player_position + Vector2(-150.0, 0.0)
	waiting.position = arena.player_position + Vector2(150.0, 0.0)
	arena.sim_tick = 1
	arena._update_enemies_tick()
	_expect(first.action_state == "windup" and first.impact_tick == 22, "action lane: lowest stable fan did not own the first windup", failures)
	_expect(waiting.action_state == "none" and waiting.motion_state == "moving" and String(waiting.tactic_reason).contains("action_lane_occupied"), "action lane: waiting fan neither yielded nor kept strafing", failures)

	for tick in range(2, 23):
		arena.sim_tick = tick
		arena._update_enemies_tick()
	var damage_events_at_first_impact := 0
	for event: Dictionary in arena.combat_event_stream.snapshot().events:
		if String(event.get("type", "")) == "damage_applied" and int(event.get("tick", -1)) == 22:
			damage_events_at_first_impact += 1
	_expect(is_equal_approx(arena.player_health, 92.0) and damage_events_at_first_impact == 1, "action lane: one telegraph still produced stacked same-tick fan damage", failures)
	_expect(waiting.action_state == "none", "action lane: waiting fan entered windup before the active lane released", failures)

	## Planning observes the first attacker as active at tick 23, then sees recovery
	## at tick 24 and must immediately hand the role lane to the waiting fan.
	arena.sim_tick = 23
	arena._update_enemies_tick()
	arena.sim_tick = 24
	arena._update_enemies_tick()
	_expect(first.action_state == "recovery" and waiting.action_state == "windup" and waiting.impact_tick == 45, "action lane: recovery did not release the role lane to its waiter", failures)
	arena.framework_room = {}
	arena._spawn_wave()


func _test_recovery_end_has_same_tick_intent(arena: Node, failures: Array[String]) -> void:
	_configure_room(arena, "rectangle_arena", "clear", ["melee_pursuer"])
	arena._spawn_wave()
	arena.player_position = arena._arena_rect().get_center()
	var enemy = arena.enemies[0]
	enemy.position = arena.player_position + Vector2(100.0, 0.0)
	enemy.action_state = "recovery"
	enemy.action_id = "contact"
	enemy.action_instance_id = 77
	enemy.state_ends_tick = 40
	enemy.motion_state = "idle"
	arena.sim_tick = 40
	var before: Vector2 = enemy.position
	arena._update_enemies_tick()
	_expect(enemy.action_state == "none" and enemy.motion_state == "moving" and enemy.position != before and String(enemy.tactic_reason) != "action_locked", "recovery boundary: ending tick discarded the newly available movement intent", failures)
	arena.framework_room = {}
	arena._spawn_wave()
	var boss = arena.boss
	boss.action_state = "recovery"
	boss.action_id = "slam"
	boss.action_instance_id = 78
	boss.state_ends_tick = 50
	arena.sim_tick = 50
	arena._update_enemies_tick()
	_expect(boss.action_state == "windup" and boss.state_started_tick == 50, "recovery boundary: boss ending tick discarded the next authoritative action", failures)
	arena._spawn_wave()


func _test_boss_runtime(arena: Node, failures: Array[String]) -> void:
	var boss = arena.boss
	arena.player_health = 77.0
	arena.boss_damage = arena.boss_maximum.multiply(BigValue.from_float(0.5))
	arena.sim_tick = 100
	arena._update_boss_tick(boss)
	_expect(boss.phase_id == "sealed" and boss.phase_state == "transition", "boss: 50% threshold did not start sealed transition", failures)
	_expect(is_equal_approx(arena.player_health, 77.0), "boss: phase transition dealt damage", failures)
	var transition_end: int = boss.state_ends_tick
	arena.sim_tick = transition_end
	arena._update_boss_tick(boss)
	_expect(boss.phase_id == "awakened" and boss.phase_state == "stable", "boss: transition did not finish awakened", failures)
	_expect(boss.core_open and boss.core_vulnerable, "boss: awakened core state is not exposed", failures)
	_expect(boss.left_hand_position - boss.position != -(boss.right_hand_position - boss.position), "boss: phase 2 hands are still symmetric", failures)
	_expect(is_equal_approx(arena.player_health, 77.0), "boss: transition completion dealt damage", failures)

	var actions: Array[String] = []
	for _index in 3:
		arena.sim_tick += 1
		arena._update_boss_tick(boss)
		actions.append(boss.action_id)
		arena.sim_tick = boss.impact_tick
		arena._update_boss_tick(boss)
		arena.sim_tick = boss.state_ends_tick
		arena._update_boss_tick(boss)
		arena.sim_tick = boss.state_ends_tick
		arena._update_boss_tick(boss)
	_expect(actions == ["slam", "sweep", "lane"], "boss: phase 2 move cycle is not slam/sweep/lane", failures)


func _test_hash_role_sensitivity(arena: Node, failures: Array[String]) -> void:
	var charger = _enemy_of_kind(arena, "charging_raider")
	var original_kind: String = charger.kind_id
	var first_hash: String = arena._semantic_state_hash("test")
	charger.kind_id = "fan_ranged"
	var second_hash: String = arena._semantic_state_hash("test")
	charger.kind_id = original_kind
	_expect(not first_hash.is_empty() and first_hash != second_hash, "hash: enemy role difference is not semantic", failures)


func _test_room_rosters_and_layouts(arena: Node, failures: Array[String]) -> void:
	var positions := {}
	for layout in ["rectangle_arena", "corridor", "ring"]:
		_configure_room(arena, layout, "clear", ["melee_pursuer", "charging_raider", "fan_ranged"])
		arena._spawn_wave()
		var kinds: Array[String] = []
		var ids: Array[int] = []
		for enemy in arena.enemies:
			kinds.append(enemy.kind_id)
			ids.append(enemy.entity_id)
		_expect(kinds == ["melee_pursuer", "charging_raider", "fan_ranged"] and ids == [1, 2, 3], "room roster/order/entity IDs changed for %s" % layout, failures)
		_expect(arena.boss == null, "normal room unexpectedly spawned a Boss", failures)
		positions[layout] = arena.enemies[0].position
	_expect(positions.rectangle_arena != positions.corridor and positions.corridor != positions.ring and positions.rectangle_arena != positions.ring, "layouts do not produce distinct deterministic spawn geometry", failures)
	var center: Vector2 = arena._arena_rect().get_center()
	var ring_clamp: Vector2 = arena._clamp_to_arena(center, 14.0)
	## 2026-10-10 playtest fix: ring rooms fight across the whole map rectangle,
	## so the clamp must leave the exact center in place instead of pushing it
	## onto the retired annulus.
	_expect(Vector2(ring_clamp).is_equal_approx(center), "ring layout did not keep its whole-map center walkable", failures)


func _test_public_proxy_geometry_snapshot(arena: Node, failures: Array[String]) -> void:
	_configure_room(arena, "ring", "clear", ["melee_pursuer", "charging_raider", "fan_ranged"])
	arena._spawn_wave()
	var snapshot: Dictionary = arena._public_proxy_snapshot()
	var geometry: Dictionary = snapshot.get("walkable_geometry", {})
	_expect(int(snapshot.get("snapshot_version", -1)) == arena.ProxyDecisionScript.SNAPSHOT_VERSION, "public proxy snapshot did not use ProxyDecision's version constant", failures)
	_expect(not geometry.is_empty() and String(geometry.get("kind", "")) == "rectangle" and not geometry.has("layout_id"), "public proxy snapshot did not expose the sanitized whole-map rectangle", failures)
	_expect(not snapshot.has("layout_id") and not snapshot.has("room_id") and not snapshot.has("hazards") and not snapshot.has("telegraphs"), "public proxy snapshot exposed route, room, or future state", failures)
	for enemy: Dictionary in snapshot.get("visible_enemies", []):
		_expect(enemy.has("targetable")
			and not enemy.has("classification_tags")
			and not enemy.has("kind_id")
			and not enemy.has("action_id")
			and not enemy.has("action_state"),
			"public white proxy snapshot exposed classification or enemy kind/action state", failures)
	var normalized: Dictionary = arena.ProxyDecisionScript._normalize_snapshot(snapshot, [])
	_expect(bool(normalized.get("ok", false)), "ProxyDecision rejected Main's public walkable-geometry snapshot", failures)


func _test_authored_ring_runtime(arena: Node, failures: Array[String]) -> void:
	# Preserve the authored six-entity crowd-control fixture. Its player remains
	# at the center — open ground since ring rooms fight across the whole map
	# rectangle — for the fan/melee/stall controls only; charger launch authority
	# is covered by the open-chord test below.
	_configure_room(arena, "ring", "clear", ["charging_raider", "melee_pursuer", "melee_pursuer", "fan_ranged", "fan_ranged", "melee_pursuer"])
	arena._spawn_wave()
	arena.player_position = arena._arena_rect().get_center()
	var charger = arena.enemies[0]
	var fan = arena.enemies[3]
	var melee = arena.enemies[5]
	var center: Vector2 = arena.player_position
	_expect((charger.position - center).normalized().dot((fan.position - center).normalized()) < -0.999, "authored ring: charger/fan fixture is not antipodal", failures)

	var fan_entered_band := false
	var fan_started := false
	var fan_band_tick := -1
	var fan_start_tick := -1
	var melee_tangent_displacement := 0.0
	var stalled_runs := {}
	var maximum_stalled_run := 0
	for tick in range(1, 241):
		arena.sim_tick = tick
		var planned: Dictionary = arena.enemy_tactics.plan(arena._enemy_tactics_snapshot())
		var intents_by_id := {}
		for intent: Dictionary in planned.get("intents", []):
			intents_by_id[int(intent.get("entity_id", 0))] = intent
		var before := {}
		for enemy in arena.enemies:
			before[enemy.entity_id] = enemy.position
		arena._update_enemies_tick()

		var fan_distance: float = fan.position.distance_to(center)
		var fan_in_band: bool = fan_distance >= arena.EnemyTacticsScript.FAN_ATTACK_MIN_RANGE and fan_distance <= arena.EnemyTacticsScript.FAN_ATTACK_RADIUS
		if fan_in_band and not fan_entered_band:
			fan_band_tick = tick
		fan_entered_band = fan_entered_band or fan_in_band
		if fan.action_instance_id > 0 and not fan_started:
			fan_start_tick = tick
		fan_started = fan_started or fan.action_instance_id > 0
		if tick <= 60:
			var melee_before: Vector2 = before[melee.entity_id]
			var melee_step: Vector2 = melee.position - melee_before
			var radial: Vector2 = melee_before - center
			if not radial.is_zero_approx():
				melee_tangent_displacement += absf(melee_step.dot(radial.normalized().rotated(PI * 0.5)))

		for enemy in arena.enemies:
			var intent: Dictionary = intents_by_id.get(enemy.entity_id, {})
			var requested_move := (intent.get("move_direction", Vector2.ZERO) as Vector2).length_squared() > 0.000001 and float(intent.get("speed_scale", 0.0)) > 0.0
			var actual_distance: float = enemy.position.distance_to(before[enemy.entity_id])
			var run := int(stalled_runs.get(enemy.entity_id, 0))
			run = run + 1 if requested_move and actual_distance <= 0.01 else 0
			stalled_runs[enemy.entity_id] = run
			maximum_stalled_run = maxi(maximum_stalled_run, run)

	_expect(fan_entered_band and fan_started, "authored ring: fan did not enter its legal attack band and start by tick 240", failures)
	_expect(melee_tangent_displacement > 0.01, "authored ring: melee entity 6 had no tangential displacement in its first 60 ticks", failures)
	_expect(maximum_stalled_run <= 4, "authored ring: requested movement stalled for %d consecutive ticks" % maximum_stalled_run, failures)
	print("ENEMY_RUNTIME_AUTHORED_RING_METRICS fan_band_tick=%d fan_start_tick=%d melee6_tangent_60=%.3f max_stalled_run=%d" % [fan_band_tick, fan_start_tick, melee_tangent_displacement, maximum_stalled_run])


func _test_ring_charger_path_runtime(arena: Node, failures: Array[String]) -> void:
	_configure_room(arena, "ring", "clear", ["charging_raider"])
	arena._spawn_wave()
	var player_geometry: Dictionary = arena._walkable_geometry(14.0)
	var enemy_geometry: Dictionary = arena._walkable_geometry(16.0)
	## 2026-10-10 playtest fix: ring rooms resolve to the whole-map rectangle, so
	## the retired annulus radii stay zero and a direct chord across the open
	## center is legal. The fixture proves the charger may launch across it
	## immediately; the annulus geometry itself is still covered by
	## tests/test_walkable_geometry.gd at the module level.
	_expect(String(player_geometry.get("kind", "")) == "rectangle" and String(enemy_geometry.get("kind", "")) == "rectangle",
		"ring runtime: ring rooms did not resolve to the whole-map rectangle", failures)
	_expect(is_zero_approx(float(player_geometry.get("inner_radius", -1.0))) and is_zero_approx(float(player_geometry.get("outer_radius", -1.0))),
		"ring runtime: annulus radii leaked into the whole-map rectangle", failures)
	var center: Vector2 = enemy_geometry["center"]
	var fixture_standoff: float = clampf(120.0, arena.EnemyTacticsScript.CHARGER_LAUNCH_MIN_RANGE, arena.EnemyTacticsScript.CHARGER_LAUNCH_MAX_RANGE)

	var charger = arena.enemies[0]
	charger.position = center + Vector2.RIGHT * fixture_standoff
	arena.player_position = center
	arena.player_health = 100.0
	arena.dodge_remaining_ticks = 0
	var player_projection: Dictionary = arena.WalkableGeometryScript.project(arena.player_position, player_geometry)
	var charger_projection: Dictionary = arena.WalkableGeometryScript.project(charger.position, enemy_geometry)
	_expect(bool(player_projection.ok) and Vector2(player_projection.position).is_equal_approx(arena.player_position), "ring runtime: center player start is illegal under padding 14", failures)
	_expect(bool(charger_projection.ok) and Vector2(charger_projection.position).is_equal_approx(charger.position), "ring runtime: in-band charger start is illegal under padding 16", failures)
	var initial_distance: float = charger.position.distance_to(arena.player_position)
	_expect(initial_distance >= arena.EnemyTacticsScript.CHARGER_LAUNCH_MIN_RANGE and initial_distance <= arena.EnemyTacticsScript.CHARGER_LAUNCH_MAX_RANGE, "ring runtime: launch fixture is outside the charge band", failures)
	var direct_chord: Dictionary = arena.WalkableGeometryScript.line_segment_walkable(charger.position, arena.player_position, enemy_geometry)
	_expect(bool(direct_chord.ok) and bool(direct_chord.walkable), "ring runtime: the whole-map chord across the open center is not walkable", failures)
	var initial_plan: Dictionary = arena.enemy_tactics.plan(arena._enemy_tactics_snapshot())
	var initial_intent: Dictionary = initial_plan.intents[0]
	_expect(String(initial_intent.request_action) == "charge" and String(initial_intent.reason) == "charger_launch_band", "ring runtime: a legal open-field chord did not launch immediately", failures)

	var setup_displacement := 0.0
	var launch_tick := -1
	var launch_distance := 0.0
	var active_steps := 0
	var active_nonzero_steps := 0
	var active_swallowed_steps := 0
	var active_displacement := 0.0
	var hit := false
	var launch_count := 0
	var completed_cycles := 0
	var maximum_setup_stalled_run := 0
	var setup_stalled_run := 0
	var player_after_init_direct_moves := 0
	var initial_player_position: Vector2 = arena.player_position
	var charge_action_instance_ids: Array[int] = []
	var frozen_distance_sum := 0.0
	var health_before_first_action := -1.0
	for tick in range(1, 1201):
		arena.sim_tick = tick
		var planned: Dictionary = arena.enemy_tactics.plan(arena._enemy_tactics_snapshot())
		var intent: Dictionary = planned.intents[0]
		var before: Vector2 = charger.position
		var state_before: String = charger.action_state
		var requested_charge := String(intent.request_action) == "charge"
		if requested_charge:
			var execution_endpoint: Vector2 = charger.position + Vector2(intent.action_direction).normalized() * float(intent.action_distance)
			var launch_path: Dictionary = arena.WalkableGeometryScript.line_segment_walkable(charger.position, execution_endpoint, enemy_geometry)
			_expect(bool(launch_path.ok) and bool(launch_path.walkable), "ring runtime: Main accepted charge before the frozen line became walkable", failures)
			launch_count += 1
			if launch_count == 1:
				health_before_first_action = arena.player_health
			if launch_tick < 0:
				launch_tick = tick
				launch_distance = charger.position.distance_to(arena.player_position)
		arena._update_enemies_tick()
		if requested_charge:
			charge_action_instance_ids.append(charger.action_instance_id)
			frozen_distance_sum += charger.charge_length
			_expect(is_equal_approx(charger.charge_length, float(intent.action_distance)), "ring runtime: Main charge_length drifted from action_distance", failures)
		if not arena.player_position.is_equal_approx(initial_player_position):
			player_after_init_direct_moves += 1
		var actual_step: float = charger.position.distance_to(before)
		if launch_tick < 0:
			setup_displacement += actual_step
		var requested_setup_move := String(intent.request_action).is_empty() and Vector2(intent.move_direction).length_squared() > 0.000001 and float(intent.speed_scale) > 0.0
		setup_stalled_run = setup_stalled_run + 1 if requested_setup_move and actual_step <= 0.01 else 0
		maximum_setup_stalled_run = maxi(maximum_setup_stalled_run, setup_stalled_run)
		if charger.action_state == "active":
			active_steps += 1
			active_displacement += actual_step
			if actual_step > 0.01:
				active_nonzero_steps += 1
			else:
				active_swallowed_steps += 1
		if arena.player_health < 100.0:
			hit = true
		if state_before == "active" and charger.action_state == "recovery":
			completed_cycles += 1
		if completed_cycles >= 1:
			break

	var first_resolution: Dictionary = {}
	if charge_action_instance_ids.size() >= 1:
		var first_action_instance_id := charge_action_instance_ids[0]
		for event: Dictionary in arena.combat_event_stream.snapshot().events:
			if String(event.get("type", "")) == "attack_resolved" and int(event.get("action_instance_id", -1)) == first_action_instance_id:
				first_resolution = event
				break
	_expect(is_zero_approx(setup_displacement), "ring runtime: an open-field launch produced unexpected setup movement", failures)
	_expect(launch_tick >= 1 and launch_tick <= 600, "ring runtime: charger did not launch within 600 ticks", failures)
	_expect(player_after_init_direct_moves == 0, "ring runtime: test moved the player after fixture initialization", failures)
	_expect(launch_count == 1 and completed_cycles == 1 and charge_action_instance_ids.size() == 1, "ring runtime: first legal charge did not complete exactly one action cycle", failures)
	_expect(active_steps == arena.CHARGE_ACTIVE_TICKS and active_nonzero_steps == active_steps, "ring runtime: first legal charge did not move on every active tick", failures)
	_expect(active_swallowed_steps == 0, "ring runtime: charge active lost %d body steps to ring projection" % active_swallowed_steps, failures)
	_expect(absf(active_displacement - frozen_distance_sum) <= 0.05, "ring runtime: body displacement did not equal frozen action distances", failures)
	_expect(maximum_setup_stalled_run <= 4, "ring runtime: setup stalled for %d consecutive ticks" % maximum_setup_stalled_run, failures)
	_expect(not first_resolution.is_empty() and String(first_resolution.get("source_id", "")) == "enemy/%d/charging_raider" % charger.entity_id and String(first_resolution.get("target_id", "")) == "ranger" and String(first_resolution.get("outcome", "")) == "damage", "ring runtime: first legal charger action lacked authoritative damage resolution", failures)
	_expect(is_equal_approx(health_before_first_action - arena.player_health, 11.0), "ring runtime: first legal charger action did not apply exactly 11 HP damage", failures)
	print("ENEMY_RUNTIME_RING_CHARGE_METRICS standoff=%.3f initial_distance=%.3f launch_tick=%d launch_distance=%.3f launches=%d completed_cycles=%d first_action_instance=%d first_hp_delta=%.1f setup_displacement=%.3f max_setup_stalled=%d active_steps=%d active_nonzero=%d active_swallowed=%d frozen_distance_sum=%.3f active_displacement=%.3f hit=%s player_after_init_direct_moves=%d" % [fixture_standoff, initial_distance, launch_tick, launch_distance, launch_count, completed_cycles, charge_action_instance_ids[0] if charge_action_instance_ids.size() >= 1 else -1, health_before_first_action - arena.player_health, setup_displacement, maximum_setup_stalled_run, active_steps, active_nonzero_steps, active_swallowed_steps, frozen_distance_sum, active_displacement, str(hit), player_after_init_direct_moves])


func _test_charger_padding_edge_runtime(arena: Node, failures: Array[String]) -> void:
	_configure_room(arena, "rectangle_arena", "clear", ["charging_raider"])
	arena._spawn_wave()
	var player_geometry: Dictionary = arena._walkable_geometry(14.0)
	var enemy_geometry: Dictionary = arena._walkable_geometry(16.0)
	var player_start := Vector2(float(player_geometry.bounds.position.x), float(player_geometry.center.y))
	var charger = arena.enemies[0]
	arena.player_position = player_start
	charger.position = player_start + Vector2.RIGHT * 100.0
	arena.player_health = 100.0
	arena.dodge_remaining_ticks = 0
	var player_check: Dictionary = arena.WalkableGeometryScript.project(player_start, player_geometry)
	var contact: Dictionary = arena.WalkableGeometryScript.project(player_start, enemy_geometry)
	_expect(bool(player_check.ok) and Vector2(player_check.position).is_equal_approx(player_start), "padding runtime: player edge is illegal under padding 14", failures)
	_expect(bool(contact.ok) and is_equal_approx(player_start.distance_to(Vector2(contact.position)), 2.0), "padding runtime: enemy contact projection is not the expected 2px inset", failures)

	var start_tick := -1
	var frozen_charge_length := 0.0
	var active_steps := 0
	var active_nonzero_steps := 0
	var active_swallowed_steps := 0
	var active_displacement := 0.0
	var recovery_tick := -1
	var charge_action_instance_id := -1
	for tick in range(1, 81):
		arena.sim_tick = tick
		var before: Vector2 = charger.position
		arena._update_enemies_tick()
		if start_tick < 0 and charger.action_state == "windup":
			start_tick = tick
			frozen_charge_length = charger.charge_length
			charge_action_instance_id = charger.action_instance_id
			_expect(charger.charge_direction.is_equal_approx(charger.charge_origin.direction_to(Vector2(contact.position))), "padding runtime: Main did not freeze direction toward projected contact", failures)
		if charger.action_state == "active":
			var actual_step: float = charger.position.distance_to(before)
			active_steps += 1
			active_displacement += actual_step
			if actual_step > 0.01:
				active_nonzero_steps += 1
			else:
				active_swallowed_steps += 1
		if charger.action_state == "recovery":
			recovery_tick = tick
			break

	var authoritative_resolution := false
	for event: Dictionary in arena.combat_event_stream.snapshot().events:
		if String(event.get("type", "")) == "attack_resolved" and int(event.get("action_instance_id", -1)) == charge_action_instance_id and String(event.get("source_id", "")) == "enemy/%d/charging_raider" % charger.entity_id and String(event.get("target_id", "")) == "ranger":
			authoritative_resolution = String(event.get("outcome", "")) == "damage"
	_expect(start_tick > 0 and start_tick < 600, "padding runtime: legal edge target did not start charge", failures)
	_expect(is_equal_approx(frozen_charge_length, 98.0), "padding runtime: Main did not freeze the projected 98px distance", failures)
	_expect(active_steps == arena.CHARGE_ACTIVE_TICKS and active_nonzero_steps == arena.CHARGE_ACTIVE_TICKS and active_swallowed_steps == 0 and recovery_tick > start_tick, "padding runtime: charge did not move on all 10 active ticks", failures)
	_expect(absf(active_displacement - frozen_charge_length) <= 0.02, "padding runtime: body displacement did not equal frozen charge_length", failures)
	_expect(charger.impact_resolved and authoritative_resolution, "padding runtime: charge produced no authoritative hit/miss resolution", failures)
	_expect(is_equal_approx(arena.player_health, 89.0), "padding runtime: projected contact charge did not hit the static edge player", failures)
	_expect(arena.player_position.is_equal_approx(player_start), "padding runtime: player moved after fixture initialization", failures)
	print("ENEMY_RUNTIME_PADDING_EDGE_METRICS start_tick=%d recovery_tick=%d charge_length=%.3f active_steps=%d active_nonzero=%d active_swallowed=%d active_displacement=%.3f contact_offset=%.3f outcome_health=%.1f player_after_init_direct_moves=0" % [start_tick, recovery_tick, frozen_charge_length, active_steps, active_nonzero_steps, active_swallowed_steps, active_displacement, player_start.distance_to(Vector2(contact.position)), arena.player_health])


func _test_invalid_charge_distance_runtime(arena: Node, failures: Array[String]) -> void:
	var cases: Array = [null, 0.0, -1.0, INF]
	for index in cases.size():
		_configure_room(arena, "rectangle_arena", "clear", ["charging_raider"])
		arena._spawn_wave()
		var charger = arena.enemies[0]
		var intent := {
			"entity_id": charger.entity_id,
			"move_direction": Vector2.ZERO,
			"speed_scale": 0.0,
			"request_action": "charge",
			"action_direction": Vector2.LEFT,
			"action_distance": cases[index],
			"reason": "invalid_distance_probe",
		}
		arena._commit_normal_enemy_intent(charger, intent)
		_expect(charger.action_state == "none" and charger.action_instance_id == 0 and String(charger.tactic_reason) == "invalid_charge_execution", "invalid charge distance: case %d was not rejected" % index, failures)

	_configure_room(arena, "rectangle_arena", "clear", ["charging_raider"])
	arena._spawn_wave()
	var charger = arena.enemies[0]
	arena._commit_normal_enemy_intent(charger, {
		"entity_id": charger.entity_id,
		"move_direction": Vector2.ZERO,
		"speed_scale": 0.0,
		"request_action": "charge",
		"action_direction": Vector2.ZERO,
		"action_distance": 100.0,
		"reason": "invalid_direction_probe",
	})
	_expect(charger.action_state == "none" and charger.action_instance_id == 0 and String(charger.tactic_reason) == "invalid_charge_execution", "invalid charge direction: zero vector was not rejected", failures)


func _test_rectangle_runtime_does_not_detour(arena: Node, failures: Array[String]) -> void:
	_configure_room(arena, "rectangle_arena", "clear", ["charging_raider"])
	arena._spawn_wave()
	var center: Vector2 = arena._arena_rect().get_center()
	arena.player_position = center
	var charger = arena.enemies[0]
	charger.position = center + Vector2(250.0, 0.0)
	var before: Vector2 = charger.position
	arena.sim_tick = 1
	arena._update_enemies_tick()
	var displacement: Vector2 = charger.position - before
	_expect(displacement.x < -0.01 and absf(displacement.y) <= 0.01, "rectangle runtime: direct approach triggered a walkable-geometry detour", failures)
	print("ENEMY_RUNTIME_RECT_METRICS dx=%.3f dy=%.3f" % [displacement.x, displacement.y])


func _test_room_completion_and_validation(arena: Node, failures: Array[String]) -> void:
	_configure_room(arena, "rectangle_arena", "clear", ["melee_pursuer"])
	arena._spawn_wave()
	arena.enemies.clear()
	arena._check_battle_end()
	_expect(arena.battle_over and arena.battle_victory, "normal clear room did not win with no living targets", failures)
	_configure_room(arena, "rectangle_arena", "timed_break", ["melee_pursuer"])
	arena._spawn_wave()
	arena.sim_tick = 901
	arena._update_room_rules_tick()
	_expect(not arena.timed_bonus_available and not arena.battle_over, "timed_break timeout incorrectly failed the room", failures)
	_configure_room(arena, "rectangle_arena", "hunt_elite", ["melee_pursuer", "fan_ranged"])
	arena._spawn_wave()
	var elite = arena.enemies[0]
	arena.enemies.erase(elite)
	arena._check_battle_end()
	_expect(arena.battle_over and arena.battle_victory and arena.enemies.size() == 1, "hunt_elite did not use the first enemy as authoritative objective", failures)
	_configure_room(arena, "rectangle_arena", "hunt_elite", [], "threshold_colossus")
	arena._spawn_wave()
	_expect(arena.boss != null and arena.enemies.size() == 1 and arena.boss.entity_id == 1, "Boss room did not spawn authoritative threshold colossus", failures)
	arena.framework_room.enemy_ids = ["unknown_enemy"]
	_expect(arena._framework_room_error() == "unknown_enemy_id", "unknown enemy did not fail closed", failures)
	arena.framework_room.enemy_ids = []
	arena.framework_room.boss_id = "unknown_boss"
	_expect(arena._framework_room_error() == "unknown_boss_id", "unknown Boss did not fail closed", failures)


func _test_embedded_room_rewards(arena: Node, failures: Array[String]) -> void:
	_configure_room(arena, "rectangle_arena", "clear", ["melee_pursuer"], "", [], [], ["equipment_general", "damage", "add_dice", "rewrite_dice", "refine_dice"])
	arena._spawn_wave()
	arena.contract_wins = 11
	arena.last_drop_id = "legacy.sentinel"
	arena.last_drop = "Legacy Sentinel"
	var fake_store := FakeSaveStore.new()
	arena.save_store = fake_store
	var legacy_before: Dictionary = arena._legacy_reward_state()
	arena.enemies.clear()
	arena._check_battle_end()
	_expect(arena.battle_victory, "embedded rewards: clear room did not remain a victory", failures)
	_expect(arena.room_reward_snapshot == {
		"add_dice_delta": 1,
		"rewrite_dice_delta": 1,
		"refine_dice_delta": 1,
		"bonus_earned": false,
		"bonus_lost": false,
	}, "embedded rewards: room_drop_tags were not mapped exactly to three tracks", failures)
	_expect(arena._legacy_reward_state() == legacy_before and fake_store.save_calls == 0, "embedded rewards: legacy profile/drop/forge state was polluted", failures)

	_configure_room(arena, "rectangle_arena", "timed_break", ["melee_pursuer"], "", [], [], ["equipment_general"])
	arena._spawn_wave()
	arena.sim_tick = 901
	arena._update_room_rules_tick()
	arena.enemies.clear()
	arena._check_battle_end()
	_expect(arena.battle_victory and arena.room_reward_snapshot == {
		"add_dice_delta": 0,
		"rewrite_dice_delta": 0,
		"refine_dice_delta": 0,
		"bonus_earned": false,
		"bonus_lost": true,
	}, "embedded rewards: timed timeout was not bonus-only", failures)
	_expect(arena._legacy_reward_state() == legacy_before and fake_store.save_calls == 0, "embedded rewards: timed victory polluted legacy state", failures)


func _test_hazards(arena: Node, failures: Array[String]) -> void:
	for hazard_id in ["exposed_ground_zone", "moving_fireline"]:
		_configure_room(arena, "rectangle_arena", "clear", ["melee_pursuer"], "", [hazard_id])
		arena._spawn_wave()
		arena.player_health = 100.0
		arena.dodge_remaining_ticks = 0
		arena.player_position = Vector2(-10000.0, -10000.0)
		arena.sim_tick = 30
		arena._update_hazards_tick()
		var state: Dictionary = arena.hazard_states[0]
		arena.player_position = state.origin
		arena._update_hazards_tick()
		var after_hit: float = arena.player_health
		arena._update_hazards_tick()
		_expect(after_hit < 100.0 and is_equal_approx(arena.player_health, after_hit), "%s did not deal exactly one hit per cycle" % hazard_id, failures)
		arena.sim_tick = 120
		arena.dodge_remaining_ticks = 1
		arena.player_position = Vector2(-10000.0, -10000.0)
		arena._update_hazards_tick()
		state = arena.hazard_states[0]
		arena.player_position = state.origin
		var before_dodge: float = arena.player_health
		arena._update_hazards_tick()
		_expect(is_equal_approx(arena.player_health, before_dodge), "%s ignored dodge immunity" % hazard_id, failures)


func _test_hazard_decision_boundaries(arena: Node, failures: Array[String]) -> void:
	for hazard_id in ["exposed_ground_zone", "moving_fireline"]:
		_configure_room(arena, "rectangle_arena", "clear", ["melee_pursuer"], "", [hazard_id])
		arena._spawn_wave()
		arena.sim_tick = arena.HAZARD_WARNING_TICKS - 1
		arena._update_hazards_tick()
		arena.sim_tick = arena.HAZARD_WARNING_TICKS
		arena._update_enemies_tick()
		var state: Dictionary = arena.hazard_states[0]
		_expect(int(state.cycle_tick) == arena.HAZARD_WARNING_TICKS and String(state.phase) == "active", "%s decision boundary: enemy planning retained the previous tick hazard phase" % hazard_id, failures)

	_configure_room(arena, "rectangle_arena", "clear", ["melee_pursuer"], "", ["moving_fireline"])
	arena._spawn_wave()
	arena.sim_tick = arena.HAZARD_WARNING_TICKS + arena.HAZARD_ACTIVE_TICKS - 1
	arena._update_hazards_tick()
	var fireline: Dictionary = arena.hazard_states[0]
	arena.player_position = fireline.origin + Vector2(0.0, fireline.length * 0.5)
	arena.dodge_cooldown_ticks = 0
	_expect(arena._automation_smoke_dodge_required(), "moving_fireline decision boundary: player logic ignored the final active tick", failures)


func _test_elite_rules(arena: Node, failures: Array[String]) -> void:
	_configure_room(arena, "rectangle_arena", "hunt_elite", ["melee_pursuer", "fan_ranged"], "", [], ["periodic_barrier"])
	arena._spawn_wave()
	var elite = arena.enemies[0]
	arena.player_position = elite.position
	arena.sim_tick = 0
	arena._update_room_rules_tick()
	var health_before: float = elite.health
	arena.attack_cooldown_ticks = 0
	_cast_and_resolve_arrow(arena)
	_expect(arena.elite_barrier_active and is_equal_approx(elite.health, health_before), "periodic barrier did not truly block damage", failures)
	arena.sim_tick = 20
	arena._update_room_rules_tick()
	arena.attack_cooldown_ticks = 0
	_cast_and_resolve_arrow(arena)
	_expect(not arena.elite_barrier_active and elite.health < health_before, "periodic barrier did not open at fixed tick", failures)

	_configure_room(arena, "ring", "hunt_elite", ["melee_pursuer"], "", [], ["summon_reinforcements"])
	arena._spawn_wave()
	elite = arena.enemies[0]
	elite.health = elite.maximum_health * 0.5
	arena._update_enemies_tick()
	var count_after_summon: int = arena.enemies.size()
	arena._update_enemies_tick()
	_expect(arena.reinforcements_summoned and count_after_summon == 2 and arena.enemies.size() == 2 and arena.enemies[1].entity_id == 2
		and arena.enemies[1].health == 720.0 and arena.enemies[1].maximum_health == 720.0,
		"reinforcement rule did not summon exactly once with stable ID and normal melee durability", failures)

	_configure_room(arena, "ring", "hunt_elite", ["melee_pursuer"], "", [], ["summon_reinforcements"])
	arena._spawn_wave()
	elite = arena.enemies[0]
	arena.player_position = elite.position
	elite.health = 1.0
	arena.attack_cooldown_ticks = 0
	_cast_and_resolve_arrow(arena)
	arena._check_battle_end()
	_expect(arena.reinforcements_summoned and arena.enemies.size() == 1 and arena.enemies[0].entity_id == 2, "lethal threshold crossing skipped the reinforcement", failures)
	_expect(not arena.battle_over, "hunt elite ended before summoned reinforcement was cleared", failures)
	arena.enemies.clear()
	arena._check_battle_end()
	_expect(arena.battle_over and arena.battle_victory, "hunt elite did not finish after summoned reinforcement was cleared", failures)


func _test_room_hash_sensitivity(arena: Node, failures: Array[String]) -> void:
	_configure_room(arena, "corridor", "timed_break", ["melee_pursuer"], "", ["moving_fireline"], ["periodic_barrier"])
	arena._spawn_wave()
	var first: String = arena._semantic_state_hash("test")
	arena.layout_id = "ring"
	var layout_hash: String = arena._semantic_state_hash("test")
	arena.layout_id = "corridor"
	arena.hazard_states[0].origin += Vector2(1.0, 0.0)
	var hazard_hash: String = arena._semantic_state_hash("test")
	arena.hazard_states[0].origin -= Vector2(1.0, 0.0)
	arena.room_id = "hash.changed"
	var room_hash: String = arena._semantic_state_hash("test")
	arena.room_id = "test.corridor.timed_break"
	arena.room_drop_tags.append("damage")
	var drop_hash: String = arena._semantic_state_hash("test")
	arena.room_drop_tags.pop_back()
	arena.elite_barrier_active = not arena.elite_barrier_active
	var elite_hash: String = arena._semantic_state_hash("test")
	arena.elite_barrier_active = not arena.elite_barrier_active
	arena.timed_bonus_available = false
	var objective_hash: String = arena._semantic_state_hash("test")
	arena.room_reward_snapshot["bonus_lost"] = true
	var reward_hash: String = arena._semantic_state_hash("test")
	_expect(not first.is_empty() and first != layout_hash and first != hazard_hash and first != room_hash and first != drop_hash and first != elite_hash and first != objective_hash and objective_hash != reward_hash, "walkable layout or authoritative room state lost hash sensitivity", failures)


func _test_early_durability_and_first_hunt(arena: Node, failures: Array[String]) -> void:
	for kind_id: String in ["melee_pursuer", "charging_raider", "fan_ranged"]:
		_configure_room(arena, "rectangle_arena", "clear", [kind_id])
		arena._spawn_wave()
		var normal_health: float = arena.enemies[0].health
		_expect(normal_health == float(arena.EARLY_NORMAL_HEALTH_BY_KIND[kind_id]),
			"early durability: normal %s did not use its role's base health" % kind_id, failures)
		_configure_room(arena, "rectangle_arena", "hunt_elite", [kind_id])
		arena._spawn_wave()
		_expect(arena.enemies[0].health >= 1000.0 and arena.enemies[0].health > normal_health * 2.0,
			"early durability: elite %s lost its distinct health pool" % kind_id, failures)
	var state = ApplicationStateScript.new()
	state.start_new_profile("ranger")
	state.complete_tutorial()
	var built := ContractPlanScript.build({"contract_id": "mainline_01_first_hunt", "seed": 301,
		"mode": "Manual", "completed_node_ids": state.profile.progression.completed_node_ids})
	_expect(bool(built.get("ok", false)), "first hunt runtime: real RoomPlan failed", failures)
	if not bool(built.get("ok", false)):
		return
	arena.test_session = true
	arena.automation_smoke = false
	arena.selected_mode = "Manual"
	arena.framework_resolved_build = state.resolved_build_snapshot()
	arena.framework_active_build = state.profile.active_build
	arena.set_process(false)
	var stationary := _first_hunt_input_run(arena, built.plan.rooms, false, failures)
	var reactive := _first_hunt_input_run(arena, built.plan.rooms, true, failures)
	for metrics: Dictionary in [stationary, reactive]:
		_expect(float(metrics.seconds) >= 15.0 and float(metrics.seconds) <= 25.0,
			"first hunt runtime: real two-room input run escaped 15–25 seconds: %s" % str(metrics), failures)
		_expect(int(metrics.warnings) > 0 and int(metrics.defeated) == 6,
			"first hunt runtime: missing telegraphs or six real kills", failures)
	_expect(float(stationary.damage) > 0.0 and float(stationary.damage) <= 112.0,
		"first hunt runtime: stationary play had no consequence or exceeded the opening damage budget", failures)
	_expect(float(reactive.damage) < float(stationary.damage) and int(reactive.dodges) > 0
		and int(reactive.move_ticks) > 0,
		"first hunt runtime: real movement/dodge input gave no damage reduction", failures)


func _first_hunt_input_run(arena: Node, rooms: Array, react: bool, failures: Array[String]) -> Dictionary:
	var metrics := {"seconds": 0.0, "damage": 0.0, "warnings": 0, "dodges": 0, "move_ticks": 0, "defeated": 0}
	for room: Dictionary in rooms:
		arena.framework_room = room.duplicate(true)
		arena.framework_room["room_index"] = int(room.index)
		arena.framework_room["room_count"] = rooms.size()
		arena._enter_arena()
		_expect(arena.enemies.size() == 3 and arena.enemies[0].health == 720.0
			and arena.enemies[0].entity_id == 1 and arena.enemies[2].entity_id == 3,
			"first hunt runtime: roster did not spawn three durable entities", failures)
		var start := arena.player_position as Vector2
		for enemy in arena.enemies:
			_expect(absf(start.distance_to(enemy.position) - 350.0) < 0.01,
				"first hunt runtime: opening approach distances are not synchronized", failures)
		var initial_health: float = arena.player_health
		var warning_count := 0
		var dodge_count := 0
		var move_ticks := 0
		var last_event_id := 0
		var first_hit_observed := false
		_early_key_input(KEY_SPACE, true)
		while not arena.battle_over and arena.sim_tick < arena.SIM_TICKS_PER_SECOND * 60:
			var react_now := false
			for enemy in arena.enemies:
				if enemy.action_state == "windup" and enemy.impact_tick == arena.sim_tick + 2:
					react_now = true
			if react and react_now:
				_early_key_input(KEY_A, true)
				if arena.dodge_cooldown_ticks == 0:
					_early_dodge_input(true)
					_early_dodge_input(false)
			elif arena.dodge_remaining_ticks == 0:
				_early_key_input(KEY_A, false)
			var position_before: Vector2 = arena.player_position
			arena._simulate_tick()
			if arena.player_position != position_before:
				move_ticks += 1
			for event: Dictionary in arena.combat_event_stream.events_after(last_event_id):
				last_event_id = int(event.event_id)
				if event.type == "action_accepted" and String(event.get("actor_id", "")).begins_with("enemy/"):
					warning_count += 1
				if event.type == "displacement_started" and event.get("kind", "") == "dodge":
					dodge_count += 1
			if not first_hit_observed and arena.arrow_hits > 0:
				first_hit_observed = true
				_expect(arena.enemies.size() == 3,
					"first hunt runtime: fresh starter arrow killed a full-health melee enemy", failures)
		_early_key_input(KEY_SPACE, false)
		_early_key_input(KEY_A, false)
		var damage: float = initial_health - arena.player_health
		print("FIRST_HUNT_INPUT mode=%s room=%s victory=%s seconds=%.2f casts=%d damage=%.1f warnings=%d dodges=%d move_ticks=%d" % [
			"reactive" if react else "stationary", room.room_id, str(arena.battle_victory), arena.elapsed,
			arena.shots, damage, warning_count, dodge_count, move_ticks])
		_expect(first_hit_observed and arena.battle_victory and damage <= initial_health * 0.5,
			"first hunt runtime: real input did not clear a room within the opening damage budget", failures)
		metrics.seconds += arena.elapsed
		metrics.damage += damage
		metrics.warnings += warning_count
		metrics.dodges += dodge_count
		metrics.move_ticks += move_ticks
		metrics.defeated += arena.defeated
	return metrics


func _early_key_input(code: int, pressed: bool) -> void:
	# Real device events flow through InputMap, GUI dispatch and Main's input handlers.
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _early_dodge_input(pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = pressed
	event.position = Vector2(320.0, 240.0) # Open playfield, outside the HUD.
	event.global_position = event.position
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _configure_room(arena: Node, layout: String, objective: String, enemy_ids: Array, boss_id: String = "", hazards: Array = [], elite_rules: Array = [], drop_tags: Array = ["equipment_general"]) -> void:
	arena.embedded_session = true
	arena.framework_room = {
		"room_id": "test.%s.%s" % [layout, objective],
		"layout_id": layout,
		"layout": layout,
		"objective_id": objective,
		"objective": objective,
		"hazard_ids": hazards.duplicate(),
		"enemy_ids": enemy_ids.duplicate(),
		"elite_rule_ids": elite_rules.duplicate(),
		"boss_id": boss_id,
		"drop_tags": drop_tags.duplicate(),
	}
	arena.battle_over = false
	arena.battle_victory = false
	arena.sim_tick = 0


func _enemy_of_kind(arena: Node, kind_id: String) -> Variant:
	for enemy in arena.enemies:
		if enemy.kind_id == kind_id:
			return enemy
	return null


func _cast_and_resolve_arrow(arena: Node) -> bool:
	## Tests drive the same fixed-tick action authority as live play: request at T,
	## emit the start event at T, release at T+windup, then advance the real
	## projectile until swept contact or frozen range resolves it.
	arena._process_player_action_events(arena.player_action_timeline.advance(arena.sim_tick))
	var accepted: bool = arena._cast_skill_one()
	arena._process_player_action_events(arena.player_action_timeline.advance(arena.sim_tick))
	if not accepted:
		return false
	arena.sim_tick += arena.PlayerActionTimelineScript.WINDUP_TICKS
	arena._process_player_action_events(arena.player_action_timeline.advance(arena.sim_tick))
	var guard := 0
	while not arena.projectiles.is_empty() and guard < 120:
		arena._advance_piercing_projectiles_tick()
		guard += 1
		if not arena.projectiles.is_empty():
			arena.sim_tick += 1
	return true


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
