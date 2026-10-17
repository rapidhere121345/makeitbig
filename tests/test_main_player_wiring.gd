extends SceneTree

const CombatSystemRoomPortScript := preload("res://src/runtime/combat/combat_system_room_port.gd")
const MainCommandSourcePortScript := preload("res://src/game/main_combat_command_source_port.gd")
const RoomMovementPolicyPortScript := preload("res://src/runtime/world/room_movement_policy_port.gd")

const Main := preload("res://src/game/main.gd")
const Protocol := preload("res://src/systems/combat_command_protocol.gd")
const Items := preload("res://src/content/early_item_registry.gd")
const Resolver := preload("res://src/systems/build_resolver.gd")
const Rules := preload("res://src/systems/ranger_skill_rules.gd")
const ArrowOrigin := preload("res://src/game/ranger_arrow_origin.gd")
const Builder := preload("res://src/game/combat_state_snapshot_builder.gd")
const RoomRuntime := preload("res://src/game/combat_room_runtime.gd")

class DrivenMain:
	extends Main
	var supplied_commands: Array[Dictionary] = []
	func _simulation_collect_commands() -> Array[Dictionary]:
		var commands: Array[Dictionary] = supplied_commands.duplicate(true)
		supplied_commands.clear()
		return commands
	func _update_enemies_tick() -> void:
		# This fixture isolates player phase ordering against a stationary target.
		pass

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var items := Items.new()
	_expect(items.load_all().is_empty(), "item fixture failed")
	var resolved: Dictionary = Resolver.new(items).resolve_fixture("calibration_convergent")
	var initial_maximum: float = float(resolved.final_parameters.max_health)
	_expect(bool(resolved.get("ok", false)), "resolved fixture failed")
	var arena := DrivenMain.new()
	arena.embedded_session = true
	arena.presentation_enabled = false
	arena.framework_resolved_build = resolved.duplicate(true)
	arena.framework_active_build = {"skills": ["piercing_arrow", "hunter_mark", "dash"]}
	arena.framework_room = {
		"room_id": "test.main.player", "layout_id": "rectangle_arena", "objective_id": "clear",
		"enemy_ids": ["melee_pursuer"], "hazard_ids": [], "elite_rule_ids": [], "boss_id": "", "drop_tags": [],
	}
	root.add_child(arena)
	arena.set_process(false)
	arena.start_room()
	_expect(arena.in_arena, "Main start blocked: " + arena.last_save_message)
	if not arena.in_arena:
		_shutdown_arena(arena)
		_finish()
		return
	_expect(arena.command_source_port is MainCommandSourcePortScript, "Main did not install the typed command source port")
	_expect(arena.command_source != null and arena.command_source.port == arena.command_source_port, "command source retained a callback bag instead of the typed port")
	var combat_room_port: Variant = arena.combat_system.get("room_port")
	_expect(combat_room_port is CombatSystemRoomPortScript and bool(combat_room_port.is_ready()), "CombatSystem did not receive the mounted typed room port")
	_expect(arena.actor_registry.movement_policy_port is RoomMovementPolicyPortScript, "RoomActorAccess did not receive the typed movement policy port")
	_expect(arena.combat_simulation.get("_rules") == arena.player_combat_rules, "Simulation did not receive the same Rules")
	var player: Dictionary = arena.player_combat_state.snapshot(arena.sim_tick)
	_expect(player.equipped_skills == ["piercing_arrow", "hunter_mark", "dash"], "room assembly did not freeze skill slots")
	arena.framework_active_build.skills[1] = "dash"
	arena.framework_resolved_build.final_parameters.max_health = 1.0
	_expect(arena.player_combat_state.snapshot(0).equipped_skills[1] == "hunter_mark" and arena.player_health == initial_maximum, "mutable profile changed the frozen player")
	var position := arena._arena_rect().get_center()
	_expect(bool(arena.teleport_actor("ranger", position).get("ok", false)), "player teleport failed")
	var target = arena.enemies[0]
	target.health = 1.0e12
	target.maximum_health = target.health
	_expect(bool(arena.teleport_actor("enemy/%d" % target.entity_id, position + Vector2(120.0, 0.0)).get("ok", false)), "target teleport failed")
	var mark: Dictionary = arena.request_player_cast("hunter_mark", target.entity_id)
	_expect(bool(mark.get("accepted", false)), "Rules mark input was not routed")
	var expiry: int = arena.player_combat_state.snapshot(0).hunter_mark_expires_tick
	var impact_tick := expiry
	var cast_tick := impact_tick - Rules.PIERCING_ARROW_WINDUP_TICKS
	var expected_receipts: Array = []
	var release_feet := Vector2.ZERO
	for tick in range(1, impact_tick + 1):
		if tick == cast_tick:
			arena.supplied_commands = [Protocol.cast(tick, "ranger", 40, "piercing_arrow", target.entity_id, 1000, 0)]
			arena.presentation.feedback.register_command_source(40, "pointer")
		if tick == impact_tick:
			release_feet = arena.player_position
			arena.supplied_commands.append(Protocol.move(tick, "ranger", 41, 1000, 0, 1000))
			expected_receipts = Protocol.arbitrate(arena.supplied_commands, tick, arena.player_combat_state.equipped_ability_ids()).receipts
		arena._simulate_tick()
	_expect(arena.sim_tick == impact_tick and int(arena.actor_registry.actor("ranger").last_movement_tick) == impact_tick, "Main did not use the committed world tick")
	_expect(arena.last_command_receipts == expected_receipts, "Main saved gameplay receipts instead of protocol receipts")
	_expect(arena.shots == 1 and arena.projectiles.size() == 1, "action impact did not resolve through CombatSystem")
	if arena.projectiles.size() == 1:
		var arrow = arena.projectiles[0]
		_expect(arrow.origin.is_equal_approx(release_feet + ArrowOrigin.release_offset(Vector2.RIGHT)), "arrow release used post-motor position")
		_expect(not arrow.origin.is_equal_approx(arena.player_position + ArrowOrigin.release_offset(Vector2.RIGHT)), "release fixture did not bracket movement")
		var model: Dictionary = arena._current_model()
		var marked_damage := float(model.total_events_float) * arena.locked_payload * Rules.HUNTER_MARK_DAMAGE_MULTIPLIER
		_expect(is_equal_approx(arrow.ordinary_damage, marked_damage), "mark expiry was applied before the pre-command timeline release")
	_expect(arena.player_combat_state.snapshot(impact_tick).marked_entity_id == 0, "post-timeline player slice did not expire mark")
	var kinds: Array[String] = []
	for event: Dictionary in arena.combat_event_stream.snapshot().events:
		kinds.append(String(event.type))
	_expect(kinds.count("action_accepted") == 1 and kinds.count("projectile_spawned") == 1, "Main duplicated Rules action events")
	var before_health: float = arena.player_health
	_expect(arena.player_combat_rules.apply_damage(arena.sim_tick, 7.0, "enemy/%d" % target.entity_id, target.position).get("accepted", false), "damage did not reach Rules")
	_expect(is_equal_approx(arena.player_health, before_health - 7.0), "Main health observation did not read domain damage")
	var ledger: Dictionary = arena.combat_system.outcome_snapshot()
	_expect(arena.shots == ledger.shots and arena.arrow_hits == ledger.arrow_hits and arena.defeated == ledger.defeated, "Main count observations did not read the CombatSystem outcome")
	var maximum_before: BigValue = arena.boss_maximum
	maximum_before.magnitude = 7.0
	_expect(arena.boss_maximum.magnitude == 1.0e12 and arena.encounter_director.boss_maximum.magnitude == 1.0e12, "Main/Encounter exposed mutable outcome ledger values")
	arena._encounter_context()
	arena.encounter_director._resolve_hostile_attack(target, 3.0, true)
	# Hostile contacts are queued during the room phase and committed by the
	# next fixed tick through RoomCombatPort; direct invocation must not bypass
	# that boundary.
	arena._simulate_tick()
	var damage_slice: Dictionary = arena.player_combat_state.snapshot(arena.sim_tick)
	_expect(damage_slice.last_damage_source_id == "enemy/%d/%s" % [target.entity_id, target.kind_id] and damage_slice.last_damage_direction.is_equal_approx(target.position.direction_to(arena.player_position)), "hostile source position did not pass directly into Rules")
	var authoritative: Dictionary = Builder.build_runtime_state(arena, "wiring")
	_expect(int(authoritative.player_x_millipixels) == roundi(arena.player_position.x * 1000.0), "Builder did not consume State registry position")
	var published: Dictionary = arena.gameplay_snapshot()
	published.player_position = Vector2.ZERO
	published.player_health = 0.0
	_expect(arena.player_position != Vector2.ZERO and arena.player_health > 0.0, "presentation publication retained writable player authority")
	arena.refresh_presentation()
	_expect(arena.presentation.get("_snapshot").player_health == arena.player_health, "refresh did not publish current domain health")
	arena.start_room()
	ledger = arena.combat_system.outcome_snapshot()
	_expect(arena.shots == 0 and arena.arrow_hits == 0 and arena.defeated == 0 and ledger.boss_damage.magnitude == 0.0 and arena.projectiles.is_empty(), "room entry did not reset the authoritative CombatSystem outcome")
	_shutdown_arena(arena)
	_test_mounted_reset(resolved)
	_test_mark_hud(resolved)
	_finish()


func _test_mounted_reset(resolved: Dictionary) -> void:
	var runtime := RoomRuntime.new()
	root.add_child(runtime)
	# Presentation stays on for the mounted section: the mounted Main only
	# binds the room's native SimulationWorld/RoomActorAccess authorities on
	# the presentation-enabled path, and the HUD assertions below exercise it.
	var started: Dictionary = runtime.start_session({
		"mode": "Manual", "presentation_enabled": true,
		"room": {
			"room_id": "test.main.mounted", "layout_id": "corridor", "objective_id": "clear",
			"enemy_ids": ["melee_pursuer"], "hazard_ids": [], "elite_rule_ids": [], "boss_id": "", "drop_tags": [],
		},
		"framework_context": {
			"active_build": {"skills": ["piercing_arrow", "hunter_mark", "dash"]},
			"resolved_build": resolved,
		},
	})
	_expect(bool(started.get("ok", false)), "mounted Main start blocked: " + String(started.get("error", "")))
	if bool(started.get("ok", false)):
		runtime.set_process(false)
		var arena = runtime.room_instance
		arena.set_process(false)
		var scene = runtime.scene_runtime
		var spawn: Vector2 = arena._room_socket("combat/spawn")
		_expect(arena.actor_registry == scene.actor_registry and arena.simulation_world == scene.simulation, "mounted Main replaced native authorities")
		_expect(arena.player_position == spawn, "domain position did not read the authored native socket")
		_expect(arena.combat_simulation.get("_rules") == arena.player_combat_rules and arena.combat_system.get("room_port") != null, "mounted services did not share the typed room authority")
		var maximum: float = arena.player_health
		_expect(arena.player_combat_rules.apply_damage(arena.sim_tick, 7.0, "fixture", arena.player_position).get("accepted", false), "mounted damage did not reach Rules")
		arena.refresh_presentation()
		_expect(is_equal_approx(float(arena.presentation.get("_snapshot").player_health), arena.player_health) and is_equal_approx(arena.player_health, maximum - 7.0), "mounted refresh published stale player state: maximum=%s domain=%s presentation=%s" % [maximum, arena.player_health, arena.presentation.get("_snapshot").player_health])
		arena.start_room()
		_expect(arena.in_arena and arena.player_health == maximum and arena.player_position == spawn, "room restart failed to reset State against the native registry")
		_expect(arena.player_combat_state.snapshot(arena.sim_tick).attack_origins.is_empty(), "room reset retained attack origins")
		_test_mark_report(arena)
		var abandoned := [0]
		runtime.abandoned.connect(func(_result: Dictionary) -> void: abandoned[0] += 1)
		arena.presentation.hud.return_requested.emit()
		_expect(abandoned[0] == 1, "embedded HUD return did not reach Main's public signal")
	runtime.free()


func _test_mark_report(arena) -> void:
	const EXPECTED := "猎人印记锁定：近战追猎者。"
	var center: Vector2 = arena._arena_rect().get_center()
	var target = arena.enemies[0]
	_expect(arena.teleport_actor("ranger", center).get("ok", false) and arena.teleport_actor("enemy/%d" % target.entity_id, center + Vector2.RIGHT * 100.0).get("ok", false), "mounted mark report fixture placement failed")
	var before_event: int = arena.combat_event_stream.latest_event_id()
	var receipt: Dictionary = arena.request_player_cast("hunter_mark")
	_expect(receipt.get("accepted", false) and arena.player_combat_state.snapshot(arena.sim_tick).marked_entity_id == target.entity_id and arena.battle_report == EXPECTED, "direct hunter mark did not publish the accepted target's player label")
	_expect(arena.combat_event_stream.latest_event_id() == before_event, "mark report duplicated a gameplay event")
	# Diagnostic report values are intentionally stale; the following ticks run
	# real enemy/hazard/projectile callbacks and must not republish those values.
	arena.combat_system.battle_report = "stale combat report"
	arena.encounter_director.battle_report = "stale encounter report"
	for _tick in 2:
		arena._simulate_tick()
	_expect(arena.battle_report == EXPECTED, "an idle tick replaced the mark report with stale component output")
	arena.battle_report = "rejection sentinel"
	receipt = arena.request_player_cast("hunter_mark", target.entity_id)
	_expect(not receipt.get("accepted", false) and arena.battle_report == "rejection sentinel", "rejected mark fabricated a success report")
	arena.start_room()
	target = arena.enemies[0]
	arena.teleport_actor("ranger", center)
	arena.teleport_actor("enemy/%d" % target.entity_id, center + Vector2.RIGHT * 100.0)
	arena.battle_report = "invalid target sentinel"
	receipt = arena.request_player_cast("hunter_mark", 99999)
	_expect(not receipt.get("accepted", false) and arena.battle_report == "invalid target sentinel", "missing mark target fabricated a success report")
	arena.command_source.hunter_mark_requested = true
	before_event = arena.combat_event_stream.latest_event_id()
	arena._simulate_tick()
	_expect(arena.battle_report == EXPECTED and arena.player_combat_state.snapshot(arena.sim_tick).marked_entity_id == target.entity_id, "command hunter mark diverged from the direct public cast report")
	var receipts: Array[Dictionary] = []
	for event: Dictionary in arena.combat_event_stream.events_after(before_event):
		if event.type == "command_receipt":
			receipts.append(event)
	_expect(receipts.size() == 1 and receipts[0].get("status", "") == "accepted", "command mark produced duplicate receipts/events")
	var arrow: Dictionary = arena.request_player_cast("piercing_arrow", target.entity_id)
	_expect(arrow.get("accepted", false), "fresh arrow report setup failed")
	for _tick in Rules.PIERCING_ARROW_WINDUP_TICKS:
		arena._simulate_tick()
	_expect(arena.battle_report != EXPECTED and not arena.combat_system.battle_report.is_empty(), "fresh arrow output did not supersede the mark report")


func _test_mark_hud(resolved: Dictionary) -> void:
	var runtime := RoomRuntime.new()
	root.add_child(runtime)
	# A configured high-health build keeps natural expiry ticks independent of
	# incoming enemy damage. Marks/actions still use real Rules and Simulation.
	var hud_build := resolved.duplicate(true)
	hud_build.final_parameters.max_health = 1.0e6
	var started: Dictionary = runtime.start_session({
		"mode": "Manual", "presentation_enabled": true,
		"room": {
			"room_id": "test.mark.hud", "layout_id": "rectangle_arena", "objective_id": "clear",
			"enemy_ids": ["charging_raider", "melee_pursuer"], "hazard_ids": [], "elite_rule_ids": [], "boss_id": "", "drop_tags": [],
		},
		"framework_context": {
			"active_build": {"skills": ["piercing_arrow", "hunter_mark", "dash"]},
			"resolved_build": hud_build,
		},
	})
	_expect(bool(started.get("ok", false)), "real HUD room failed: " + String(started.get("error", "")))
	if not bool(started.get("ok", false)):
		runtime.free()
		return
	runtime.set_process(false)
	var arena = runtime.room_instance
	arena.set_process(false)
	const EXPECTED := "猎人印记锁定：冲锋掠袭者。"
	for routed in [false, true]:
		arena.start_room()
		var target = _place_hud_targets(arena)
		if routed:
			var key := InputEventKey.new()
			key.keycode = KEY_Q
			key.physical_keycode = KEY_Q
			key.pressed = true
			arena.input_adapter.capture_actions(key, arena.gameplay_snapshot())
			arena._simulate_tick()
		else:
			_expect(arena.request_player_cast("hunter_mark", target.entity_id).get("accepted", false), "direct HUD mark was rejected")
		_expect("完整战斗反馈  " + EXPECTED in _hud_summary(arena), "accepted mark missing from real HUD summary (routed=%s)" % routed)
		arena.combat_system.battle_report = "stale combat report"
		arena.encounter_director.battle_report = "stale encounter report"
		for _tick in 3:
			arena._simulate_tick()
		_expect(EXPECTED in _hud_summary(arena), "idle ticks replaced the HUD mark (routed=%s)" % routed)
		var rejected: Dictionary = arena.request_player_cast("hunter_mark", arena.enemies[1].entity_id)
		_expect(not rejected.get("accepted", false) and EXPECTED in _hud_summary(arena) and "锁定：近战追猎者" not in _hud_summary(arena), "cooldown rejection fabricated a different successful HUD target")
		# The existing pointer warning outranks a live mark, in the real HUD.
		arena.presentation.commit(arena.gameplay_snapshot(), {"device": {"pointer_world_held": true}, "pointer_status": "no_pointer_target"})
		_expect("鼠标未锁定目标" in _summary_label(arena).text and EXPECTED not in _summary_label(arena).text, "live mark hid the pointer warning")
		_expect(arena.request_player_cast("piercing_arrow", target.entity_id).get("accepted", false), "HUD arrow replacement was rejected")
		_expect("穿刺箭拉弓" in _hud_summary(arena) and EXPECTED not in _hud_summary(arena), "new arrow windup did not replace HUD mark")
		for _tick in Rules.PIERCING_ARROW_WINDUP_TICKS + 30:
			arena._simulate_tick()
		_expect(not arena.last_attack_outcome.is_empty() and "穿刺箭" in _hud_summary(arena) and EXPECTED not in _hud_summary(arena), "fresh arrow result did not replace HUD mark")

	arena.start_room()
	var target = _place_hud_targets(arena)
	_expect(not arena.request_player_cast("hunter_mark", 99999).get("accepted", false) and "猎人印记锁定" not in _hud_summary(arena), "missing target produced a successful HUD mark")
	# A report alone is not evidence of an active mark, nor raw internal copy.
	arena.battle_report = EXPECTED
	_expect(EXPECTED not in _hud_summary(arena), "a stale success string fabricated a HUD mark without State")
	_expect(arena.request_player_cast("hunter_mark", target.entity_id).get("accepted", false), "expiry HUD setup failed")
	arena.battle_report = "internal report: target=1"
	_expect("internal report" not in _hud_summary(arena), "HUD leaked an internal English report")
	arena.battle_report = EXPECTED
	var expiry: int = arena.player_combat_state.snapshot(arena.sim_tick).hunter_mark_expires_tick
	while arena.sim_tick < expiry:
		arena._simulate_tick()
	arena.battle_report = EXPECTED
	_expect(arena.player_combat_state.snapshot(arena.sim_tick).marked_entity_id == 0 and EXPECTED not in _hud_summary(arena), "expired mark survived in the HUD")

	arena.start_room()
	target = _place_hud_targets(arena)
	# Low target health is authored fixture setup; its death uses the actual arrow.
	target.health = 1.0
	_expect(arena.request_player_cast("hunter_mark", target.entity_id).get("accepted", false), "death HUD mark setup failed")
	_expect(arena.request_player_cast("piercing_arrow", target.entity_id).get("accepted", false), "death HUD arrow setup failed")
	for _tick in 45:
		arena._simulate_tick()
		if target.health <= 0.0:
			break
	arena.battle_report = EXPECTED
	_expect(target.health <= 0.0 and EXPECTED not in _hud_summary(arena), "dead target retained a successful HUD mark")
	# No live target exists for the next mark request.
	for enemy in arena.enemies:
		enemy.health = 0.0
	_expect(not arena.request_player_cast("hunter_mark").get("accepted", false) and EXPECTED not in _hud_summary(arena), "no-target refusal fabricated a successful HUD mark")
	arena.start_room()
	_expect("猎人印记锁定" not in _hud_summary(arena), "room reset retained a successful HUD mark")
	runtime.free()


func _place_hud_targets(arena):
	var center: Vector2 = arena._arena_rect().get_center()
	_expect(arena.teleport_actor("ranger", center).get("ok", false), "HUD player placement failed")
	for index in arena.enemies.size():
		var enemy = arena.enemies[index]
		enemy.health = 1.0e12
		enemy.maximum_health = enemy.health
		_expect(arena.teleport_actor("enemy/%d" % enemy.entity_id, center + Vector2(100.0 + index * 90.0, 0.0)).get("ok", false), "HUD target placement failed")
	return arena.enemies[0]


func _summary_label(arena) -> Label:
	return arena.presentation.hud.find_child("SummaryBlockLabel", true, false) as Label


func _hud_summary(arena) -> String:
	var before: String = Builder.hash_runtime(arena, "hud")
	arena.refresh_presentation()
	arena.presentation.hud.set_summary_visible(true)
	var label := _summary_label(arena)
	_expect(label != null and label.is_visible_in_tree(), "real HUD summary label is not visible")
	_expect(Builder.hash_runtime(arena, "hud") == before, "HUD commit changed canonical gameplay hash")
	return label.text if label != null else ""


func _finish() -> void:
	for failure: String in failures:
		printerr("FAIL: " + failure)
	if failures.is_empty():
		print("PASS test_main_player_wiring.gd")
	quit(0 if failures.is_empty() else 1)


func _shutdown_arena(arena: Node) -> void:
	if arena == null or not is_instance_valid(arena):
		return
	var runtime: Variant = arena.get("scene_runtime")
	if runtime != null and runtime.has_method("unmount"):
		runtime.unmount()
	if arena.get_parent() != null:
		arena.get_parent().remove_child(arena)
	arena.free()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
