extends SceneTree

const Main := preload("res://src/game/main.gd")
const Protocol := preload("res://src/systems/combat_command_protocol.gd")
const Items := preload("res://src/content/early_item_registry.gd")
const Resolver := preload("res://src/systems/build_resolver.gd")
const Skill := preload("res://src/systems/ranger_skill_rules.gd")
const Assert := preload("res://tests/helpers/assert.gd")

class DrivenMain:
	extends Main
	var supplied_mobility := ""
	var supplied_direction := Vector2.ZERO
	var last_supplied_command: Dictionary = {}
	func _simulation_collect_commands() -> Array[Dictionary]:
		if supplied_mobility.is_empty():
			return []
		var command: Dictionary = _player_commands._dodge_command(supplied_direction) if supplied_mobility == "dodge" else _player_commands._cast_command("dash", 0, supplied_direction)
		supplied_mobility = ""
		last_supplied_command = command.duplicate(true)
		return [command]
	func _update_enemies_tick() -> void:
		pass

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var items := Items.new()
	_expect(items.load_all().is_empty(), "item fixture failed")
	var resolved: Dictionary = Resolver.new(items).resolve_fixture("calibration_convergent")
	_expect(bool(resolved.get("ok", false)), "resolved fixture failed")
	for initial in ["dodge", "dash"]:
		for release in [false, true]:
			_test_tail_buffer(resolved, initial, release)
	for failure: String in failures:
		printerr("FAIL: " + failure)
	if failures.is_empty():
		print("PASS test_main_input_release.gd (real Rules/Simulation, both mobility buffers and release controls)")
	quit(0 if failures.is_empty() else 1)


func _test_tail_buffer(resolved: Dictionary, initial: String, release: bool) -> void:
	var label := "%s release=%s: " % [initial, release]
	var arena := DrivenMain.new()
	arena.test_session = true
	arena.presentation_enabled = false
	arena.framework_resolved_build = resolved.duplicate(true)
	arena.framework_active_build = {"skills": ["piercing_arrow", "hunter_mark", "dash"]}
	arena.framework_room = {
		"room_id": "test.input.release", "layout_id": "rectangle_arena", "objective_id": "clear",
		"enemy_ids": ["melee_pursuer"], "hazard_ids": [], "elite_rule_ids": [], "boss_id": "", "drop_tags": [],
	}
	root.add_child(arena)
	arena.set_process(false)
	arena.start_room()
	_expect(arena.in_arena, label + "Main start blocked: " + arena.last_save_message)
	if not arena.in_arena:
		_shutdown_arena(arena)
		return
	_expect(bool(arena.teleport_actor("ranger", arena._arena_rect().get_center()).get("ok", false)), label + "player teleport failed")
	var buffered_kind := "dash" if initial == "dodge" else "dodge"
	var duration := Skill.DODGE_DURATION_TICKS if initial == "dodge" else Skill.DASH_DURATION_TICKS
	var buffer_tick := duration - 1
	var consume_tick := duration + 1
	var queued: Dictionary = {}
	for tick in range(1, buffer_tick + 1):
		# Factories run inside Simulation's collect phase, using its real tick and
		# Main's normal sequence allocation; the fixture never rewinds the world.
		if tick == 1:
			arena.supplied_mobility = initial
			arena.supplied_direction = Vector2.RIGHT
		elif tick == buffer_tick:
			arena.supplied_mobility = buffered_kind
			arena.supplied_direction = Vector2.UP
		arena._simulate_tick()
	queued = arena.last_supplied_command
	var before: Dictionary = arena.player_combat_state.snapshot(arena.sim_tick)
	_expect(not before.mobility_input_buffer.is_empty() and before.mobility_input_buffer.sequence == queued.sequence, label + "late conflict did not create real Rules buffer")
	_expect(before[initial + "_remaining_ticks"] == 2, label + "fixture missed mobility tail")
	var prior_tick := arena.sim_tick
	var prior_sequence := arena.command_sequence
	var prior_receipts: Array = arena.last_command_receipts.duplicate(true)
	var prior_stream: Dictionary = arena.combat_event_stream.snapshot()
	var prior_actor: Dictionary = arena.actor_registry.actor_snapshot("ranger")
	if release:
		arena.command_source.dodge_requested = true
		arena.command_source.dash_requested = true
		arena.release_manual_controls()
		arena.release_manual_controls()
		var after: Dictionary = arena.player_combat_state.snapshot(arena.sim_tick)
		_expect(after.mobility_input_buffer.is_empty(), label + "input release did not clear domain buffer")
		_expect(not arena.command_source.dodge_requested and not arena.command_source.dash_requested, label + "input release retained device edges")
		_expect(arena.sim_tick == prior_tick and arena.command_sequence == prior_sequence and arena.last_command_receipts == prior_receipts, label + "release fabricated tick/sequence/receipt")
		_expect(arena.combat_event_stream.snapshot() == prior_stream and arena.actor_registry.actor_snapshot("ranger") == prior_actor, label + "release advanced events or motor")
		for key: String in ["player_health", "player_facing", "player_last_displacement", "dodge_remaining_ticks", "dash_remaining_ticks", "dodge_cooldown_ticks", "dash_cooldown_ticks", "attack_cooldown_ticks", "timeline", "action_phase"]:
			_expect(after[key] == before[key], label + "release changed " + key)
	for tick in range(buffer_tick + 1, consume_tick + 1):
		arena._simulate_tick()
	var final: Dictionary = arena.player_combat_state.snapshot(arena.sim_tick)
	_expect(arena.sim_tick == consume_tick and arena.actor_registry.actor("ranger").last_movement_tick == consume_tick, label + "consume used a fabricated motor tick")
	_expect(arena.command_sequence == prior_sequence, label + "buffer consume allocated a new command sequence")
	_expect(final.mobility_input_buffer.is_empty(), label + "ready/released buffer remained queued")
	if release:
		_expect(final[buffered_kind + "_remaining_ticks"] == 0 and arena.last_command_receipts.is_empty(), label + "released buffer still started mobility or produced a receipt")
	else:
		_expect(final[buffered_kind + "_remaining_ticks"] > 0 and final[buffered_kind + "_direction"] == Vector2.UP, label + "unreleased buffer did not start its original mobility")
		var expected := queued.duplicate(true)
		expected.tick = consume_tick
		_expect(arena.last_command_receipts == Protocol.arbitrate([expected], consume_tick, arena.player_combat_state.equipped_ability_ids()).receipts, label + "unreleased buffer changed Protocol sequence/tick/receipt semantics")
	_shutdown_arena(arena)


func _shutdown_arena(arena: Node) -> void:
	if arena == null or not is_instance_valid(arena):
		return
	var runtime: Variant = arena.get("scene_runtime")
	if runtime != null and runtime.has_method("unmount"):
		runtime.unmount()
	if arena.get_parent() != null:
		arena.get_parent().remove_child(arena)
	arena.free()


func _expect(condition: bool, message: String) -> void: Assert.expect(condition, message, failures)
