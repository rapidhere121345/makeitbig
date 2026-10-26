extends SceneTree

const EncounterScript := preload("res://src/runtime/encounter/room_encounter.gd")
const PortScript := preload("res://src/runtime/world/room_encounter_port.gd")
const ObservationScript := preload("res://src/runtime/encounter/room_terminal_observation.gd")
const Assert := preload("res://tests/helpers/assert.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_victory_priority_and_idempotence()
	_test_objective_clear_with_live_member()
	_test_defeat_and_stale_context()
	for failure: String in failures:
		printerr("- " + failure)
	print("PASS test_room_terminal_authority.gd" if failures.is_empty() else "FAIL test_room_terminal_authority.gd")
	quit(0 if failures.is_empty() else 1)


func _test_victory_priority_and_idempotence() -> void:
	var encounter := EncounterScript.new()
	_expect(bool(encounter.configure("terminal.priority", [{
		"wave_id": "wave.01",
		"spawns": [{"spawn_id": "enemy", "archetype_id": "melee_pursuer", "socket_id": "socket/Spawn", "count": 1}],
	}]).get("ok", false)), "priority: configure failed")
	var port := PortScript.new()
	_expect(bool(port.bind(encounter, "room/priority", 4).get("ok", false)), "priority: port bind failed")
	_expect(bool(encounter.start(0).get("ok", false)), "priority: start failed")
	var step = encounter.step(0)
	_expect(step.spawn_requests.size() == 1, "priority: spawn request missing")
	var request = step.spawn_requests[0]
	_expect(bool(encounter.notify_spawned(request.spawn_key, "actor/1", 0).get("ok", false)), "priority: spawn acknowledgement failed")
	var death := encounter.notify_death("actor/1", 1)
	_expect(bool(death.get("ok", false)), "priority: death settlement failed")
	var observation := _observation(1, "room/priority", 4, true, 0, 1, 0, 0)
	var result: RoomTerminalResult = port.observe_terminal(observation)
	_expect(result.ok and result.changed and result.phase == EncounterScript.PHASE_VICTORY, "priority: wave clear did not beat same-tick player death")
	var duplicate: RoomTerminalResult = port.observe_terminal(observation)
	_expect(duplicate.ok and duplicate.duplicate and not duplicate.changed and duplicate.phase == EncounterScript.PHASE_VICTORY, "priority: duplicate terminal submission was not idempotent")
	_expect(encounter.snapshot().phase == EncounterScript.PHASE_VICTORY, "priority: encounter phase changed after terminal result")


func _test_defeat_and_stale_context() -> void:
	var encounter := EncounterScript.new()
	encounter.configure("terminal.defeat", [{
		"wave_id": "wave.01",
		"spawns": [{"spawn_id": "enemy", "archetype_id": "melee_pursuer", "socket_id": "socket/Spawn", "count": 1}],
	}])
	var port := PortScript.new()
	port.bind(encounter, "room/defeat", 9)
	encounter.start(0)
	var step = encounter.step(0)
	var request = step.spawn_requests[0]
	encounter.notify_spawned(request.spawn_key, "actor/1", 0)
	var stale := _observation(1, "room/defeat", 10, false, 0, 1, 1, 1)
	var stale_result: RoomTerminalResult = port.observe_terminal(stale)
	_expect(not stale_result.ok and stale_result.error == "stale_terminal_observation_context", "stale: revision mismatch was accepted")
	var defeat := _observation(1, "room/defeat", 9, false, 0, 1, 1, 1)
	var defeat_result: RoomTerminalResult = port.observe_terminal(defeat)
	_expect(defeat_result.ok and defeat_result.changed and defeat_result.phase == EncounterScript.PHASE_DEFEAT, "defeat: player death did not close the encounter")
	var old_tick := _observation(0, "room/defeat", 9, true, 0, 1, 1, 1)
	var old_result: RoomTerminalResult = port.observe_terminal(old_tick)
	_expect(not old_result.ok and old_result.error in ["stale_terminal_observation_tick", "stale_encounter_tick"], "stale: old terminal tick was accepted")


func _test_objective_clear_with_live_member() -> void:
	var encounter := EncounterScript.new()
	_expect(bool(encounter.configure("terminal.elite", [{
		"wave_id": "wave.01",
		"objective_tag": "hunt_elite",
		"spawns": [
			{"spawn_id": "elite", "archetype_id": "melee_pursuer", "socket_id": "socket/Spawn", "count": 1},
			{"spawn_id": "escort", "archetype_id": "fan_ranged", "socket_id": "socket/Spawn", "count": 1},
		],
	}]).get("ok", false)), "objective: configure failed")
	var port := PortScript.new()
	port.bind(encounter, "room/elite", 3)
	encounter.start(0)
	var step = encounter.step(0)
	for request in step.spawn_requests:
		encounter.notify_spawned(request.spawn_key, "actor/%s" % request.spawn_key, 0)
	var elite_death := encounter.notify_death("actor/wave.01/elite/0", 1)
	_expect(bool(elite_death.get("ok", false)), "objective: elite death settlement failed")
	var observation := _observation(1, "room/elite", 3, true, 0, 2, 1, 1)
	observation.objective_satisfied = true
	var result: RoomTerminalResult = port.observe_terminal(observation)
	_expect(result.ok and result.changed and result.phase == EncounterScript.PHASE_VICTORY, "objective: hunt-elite did not clear with escort alive")


func _observation(tick: int, room: String, revision: int, alive: bool, wave: int, requested: int, living: int, unresolved: int) -> RoomTerminalObservation:
	var result := ObservationScript.new()
	result.tick = tick
	result.room_instance_id = room
	result.world_revision = revision
	result.player_alive = alive
	result.current_wave_index = wave
	result.requested_member_count = requested
	result.alive_member_count = living
	result.unresolved_member_count = unresolved
	return result


func _expect(condition: bool, message: String) -> void: Assert.expect(condition, message, failures)
