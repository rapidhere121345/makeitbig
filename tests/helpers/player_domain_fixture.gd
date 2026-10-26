extends RefCounted

const TalentFixture := preload("res://tests/helpers/talent_runtime_fixture.gd")
const RoomRuntime := preload("res://src/game/combat_room_runtime.gd")
const RoomEncounterScript := preload("res://src/runtime/encounter/room_encounter.gd")
const Protocol := preload("res://src/systems/combat_command_protocol.gd")
const PhasePort := preload("res://tests/helpers/callable_combat_phase_port.gd")

var talent := TalentFixture.new()
var _batches: Dictionary = {}
var _release_frames: Dictionary = {}


func build(overrides: Dictionary = {}) -> Dictionary:
	var parameters := {"p": 0.5, "T": 2.0, "v": 200.0, "d": 225.0, "turn": 0.1, "damage": 100.0, "max_health": 100.0}
	parameters.merge(overrides, true)
	var resolved: Dictionary = talent.resolver.resolve(parameters, {}, "piercing_arrow")
	assert(bool(resolved.get("ok", false)), "behavior fixture build failed: %s" % str(resolved))
	return resolved


func mount(room: Dictionary, resolved: Dictionary = {}, presentation_enabled: bool = false) -> Dictionary:
	var runtime := RoomRuntime.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(runtime)
	var started: Dictionary = runtime.start_session({
		"contract_id": "test.behavior-fixture", "mode": "Manual", "seed": 52969,
		"presentation_enabled": presentation_enabled, "room": room.duplicate(true),
		"framework_context": {
			"active_build": {"skills": ["piercing_arrow", "hunter_mark", "dash"]},
			"resolved_build": resolved if not resolved.is_empty() else build(),
		},
	})
	assert(bool(started.get("ok", false)), "behavior fixture mount failed: %s" % str(started))
	var arena = runtime.room_instance
	arena.set_process(false)
	runtime.set_process(false)
	return {"runtime": runtime, "arena": arena}


func free_session(session: Dictionary) -> void:
	var arena = session.arena
	_batches.erase(arena.get_instance_id())
	_release_frames.erase(arena.get_instance_id())
	(Engine.get_main_loop() as SceneTree).root.remove_child(session.runtime)
	session.runtime.free()


func player(arena) -> Dictionary:
	return arena.player_combat_state.snapshot(arena.sim_tick)


func reset(arena, room: Dictionary = {}, resolved: Dictionary = {}, skills: Array = ["piercing_arrow", "hunter_mark", "dash"]) -> void:
	arena.release_manual_controls()
	if not room.is_empty():
		arena.framework_room = room.duplicate(true)
		var encounter = RoomEncounterScript.new()
		var spawns: Array = []
		var roster: Array = (room.get("enemy_ids", []) as Array).duplicate()
		var boss_id := String(room.get("boss_id", "")).strip_edges()
		if not boss_id.is_empty():
			roster.append(boss_id)
		for index in roster.size():
			var archetype := String(roster[index])
			spawns.append({
				"spawn_id": "fixture.%02d.%s" % [index, archetype],
				"archetype_id": archetype,
				"socket_id": "combat/encounter-origin",
				"count": 1,
			})
		var configured: Dictionary = encounter.configure(String(room.get("room_id", "fixture.room")), [{
			"wave_id": "fixture.wave",
			"clear_policy": "all_dead",
			"spawns": spawns,
		}])
		assert(bool(configured.get("ok", false)), "behavior fixture encounter rebind failed: %s" % str(configured))
		var bound: Dictionary = arena.scene_runtime.bind_encounter(encounter, arena.encounter_spawn_port)
		assert(bool(bound.get("ok", false)), "behavior fixture encounter port rebind failed: %s" % str(bound))
	if not resolved.is_empty():
		arena.framework_resolved_build = resolved.duplicate(true)
	arena.framework_active_build = {"skills": skills.duplicate()}
	arena.selected_mode = "Manual"
	arena.start_room()
	assert(arena.in_arena and arena.sim_tick == 0, "behavior fixture reset failed: %s" % arena.last_save_message)
	_release_frames[arena.get_instance_id()] = {}


func drive(arena, options: Dictionary = {}) -> void:
	# Isolate only the unrelated room/input boundaries. The real player rules,
	# registry motor, timeline, projectile contact and world clock always run.
	var arena_id: int = arena.get_instance_id()
	_batches[arena_id] = []
	_release_frames[arena_id] = {}
	var enemy_step: Callable = options.get("enemy_step", Callable(arena, "_update_enemies_tick") if bool(options.get("enemies", false)) else func() -> void: pass)
	var collect: Callable = Callable(arena, "_simulation_collect_commands") if bool(options.get("input", false)) else func() -> Array[Dictionary]: return _collect(arena_id)
	var callbacks := {
		"read_only_targets": Callable(arena, "_read_only_targets"),
		"set_elapsed": Callable(arena, "_simulation_set_elapsed"),
		"consume_player_events": Callable(arena, "_consume_player_events"),
		"update_room_rules": Callable(arena, "_update_room_rules_tick"),
		"refresh_hazard_states": Callable(arena, "_refresh_hazard_states_tick"),
		"collect_commands": collect, "route_commands": Callable(arena, "_route_commands"),
		"update_enemies": enemy_step,
		"advance_projectiles": func() -> void: _observe_release_and_advance(arena),
		"resolve_hazard_hits": Callable(arena, "_resolve_hazard_hits_tick"),
		"check_battle_end": Callable(arena, "_check_battle_end"),
		"check_timeout": Callable(arena, "_simulation_check_timeout"),
	}
	var phase_port = PhasePort.new()
	var port_result: Dictionary = phase_port.bind(callbacks)
	assert(bool(port_result.get("ok", false)), "behavior phase port bind failed: %s" % str(port_result))
	var configured: Dictionary = arena.combat_simulation.configure(arena.simulation_world, arena.player_combat_rules, phase_port)
	assert(bool(configured.get("ok", false)), "behavior tick driver failed: %s" % str(configured))


func _collect(arena_id: int) -> Array[Dictionary]:
	var commands: Array[Dictionary] = []
	commands.assign(_batches.get(arena_id, []))
	_batches[arena_id] = []
	return commands


func _observe_release_and_advance(arena) -> void:
	var frames: Dictionary = _release_frames.get(arena.get_instance_id(), {})
	for projectile in arena.projectiles:
		if projectile.spawned_tick != arena.sim_tick or frames.has(projectile.action_instance_id):
			continue
		frames[projectile.action_instance_id] = {
			"origin": projectile.origin, "position": projectile.position, "previous_position": projectile.previous_position,
			"player_position": player(arena).player_position, "player_facing": player(arena).player_facing,
		}
	_release_frames[arena.get_instance_id()] = frames
	arena._arrows._advance_piercing_projectiles_tick()


func release_frame(arena, action_id: int) -> Dictionary:
	return (_release_frames.get(arena.get_instance_id(), {}) as Dictionary).get(action_id, {}).duplicate(true)


func step(arena, commands: Array[Dictionary] = []) -> Dictionary:
	_batches[arena.get_instance_id()] = commands.duplicate(true)
	var result: Dictionary = arena.combat_simulation.step()
	assert(bool(result.get("ok", false)), "behavior simulation failed: %s" % str(result))
	return result


func advance_to(arena, tick: int) -> void:
	assert(tick >= int(arena.sim_tick), "behavior fixture cannot rewind the world")
	while int(arena.sim_tick) < tick:
		step(arena)


func command(arena, ability: String, target_id: int = 0, direction: Vector2 = Vector2.ZERO) -> Dictionary:
	var tick: int = arena.sim_tick + 1
	var sequence: int = arena.command_sequence
	arena.command_sequence += 1
	var aim := direction.normalized()
	if ability == "piercing_arrow" and aim == Vector2.ZERO:
		for target: Dictionary in arena._read_only_targets():
			if int(target.entity_id) == target_id:
				aim = (player(arena).player_position as Vector2).direction_to(target.position)
				break
	if ability == "move":
		return Protocol.move(tick, "ranger", sequence, roundi(aim.x * 1000.0), roundi(aim.y * 1000.0), 1000)
	if ability == "dodge":
		return Protocol.dodge(tick, "ranger", sequence, roundi(aim.x * 1000.0), roundi(aim.y * 1000.0))
	return Protocol.cast(tick, "ranger", sequence, ability, target_id, roundi(aim.x * 1000.0), roundi(aim.y * 1000.0)) if ability in ["dash", "piercing_arrow"] else Protocol.cast(tick, "ranger", sequence, ability, target_id)


func cast(arena, ability: String, target_id: int = 0, direction: Vector2 = Vector2.ZERO) -> Dictionary:
	var request := command(arena, ability, target_id, direction)
	var result := step(arena, [request])
	for receipt: Dictionary in result.player_step.receipts:
		if int(receipt.command.get("sequence", -1)) == int(request.sequence):
			return receipt
	return {"accepted": false, "reason": "receipt_missing"}


func wait_ready(arena, cooldown: String = "attack_cooldown_ticks") -> void:
	var guard := 0
	while guard < 360:
		var state := player(arena)
		if int(state[cooldown]) == 0 and int(state.dodge_remaining_ticks) == 0 and int(state.dash_remaining_ticks) == 0 and state.timeline.active.is_empty() and state.timeline.buffered.is_empty():
			return
		step(arena)
		guard += 1
	assert(false, "behavior fixture did not reach the real action window")


func resolve_projectiles(arena, maximum_ticks: int = 120) -> void:
	var guard := 0
	while not arena.projectiles.is_empty() and guard < maximum_ticks:
		step(arena)
		guard += 1
	assert(arena.projectiles.is_empty(), "behavior fixture projectile did not resolve")
