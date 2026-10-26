class_name RoomTerminal
extends RefCounted

## Battle-end and terminal observation extracted from MainArena: victory and
## defeat detection, the mounted-encounter terminal observation and the
## automation-smoke terminal handling. Room state stays owned by MainArena and
## is reached through the typed owner reference.

const RoomTerminalObservationScript := preload("res://src/runtime/encounter/room_terminal_observation.gd")

var _main: MainArena


func _init(main: MainArena) -> void:
	_main = main


func _check_battle_end() -> void:
	# Pickup is a committed post-movement phase. Requests are queued by the
	# public input boundary and can only mutate the room ledger here.
	_main._process_room_loot_pickups_tick()
	if _mounted_encounter_terminal_active():
		var terminal_result := _observe_mounted_encounter_terminal()
		if not bool(terminal_result.get("ok", false)):
			push_error("room_terminal_observation_failed:%s" % String(terminal_result.get("error", "unknown")))
			return
		var terminal_phase := String(terminal_result.get("phase", ""))
		if terminal_phase not in ["victory", "defeat"] or _main._terminal_projection_applied:
			return
		_main._terminal_projection_applied = true
		var victory := terminal_phase == "victory"
		_main.battle_report = "VICTORY — Room encounter cleared." if victory else "DEFEAT — The ranger fell. Refit at base."
		var projected := _main.room_rules.project_terminal(victory, _main.timed_bonus_available, _main.elapsed, _main.shots, _main.defeated)
		if not bool(projected.get("ok", false)):
			push_error("room_terminal_reward_projection_failed:%s" % String(projected.get("error", "unknown")))
			return
		if victory:
			_main._spawn_room_loot_for_source("wave_clear", 0, _main.player_position)
		else:
			_main._settle_room_loot("defeat")
		_handle_terminal_automation(victory)
		return
	var observed: Dictionary = _main.room_rules.observe(_main.player_combat_state.snapshot(_main.sim_tick), {
		"has_boss": _main.boss != null, "boss_health": _main.boss.health if _main.boss != null else 0.0,
		"enemy_count": _main.enemies.size(), "elite_entity_id": _main.elite_entity_id,
		"elite_alive": _main._enemy_by_entity_id(_main.elite_entity_id) != null,
		"elite_rule_ids": _main.elite_rule_ids, "timed_bonus_available": _main.timed_bonus_available,
		"elapsed": _main.elapsed, "shots": _main.shots, "defeated": _main.defeated,
	})
	if not bool(observed.changed):
		return
	_main.battle_report = String(observed.state.report)
	if _main.battle_victory:
		_main._spawn_room_loot_for_source("wave_clear", 0, _main.player_position)
	if not _main.battle_victory:
		_main._settle_room_loot("defeat")
	if _main.battle_victory:
		if _main.automation_smoke and not _automation_smoke_state_valid():
			_fail_automation_smoke("integrated room/proxy/reward state is invalid")
	elif _main.automation_smoke:
		_main.automation_smoke_failure = "defeat elapsed=%.2f casts=%d" % [_main.elapsed, _main.shots]


func _mounted_encounter_terminal_active() -> bool:
	return _main.room_encounter_port != null and _main.room_encounter_port.encounter != null and _main.room_encounter_port.encounter.has_method("observe_terminal")


func _observe_mounted_encounter_terminal() -> Dictionary:
	var observation := RoomTerminalObservationScript.new()
	observation.tick = _main.sim_tick
	observation.room_instance_id = String(_main.simulation_world.room_instance_id)
	observation.world_revision = int(_main.simulation_world.world_revision)
	var player := _main.player_combat_state.snapshot(_main.sim_tick)
	observation.player_alive = float(player.get("player_health", 0.0)) > 0.0
	var encounter_state: Dictionary = _main.room_encounter_port.encounter.snapshot()
	observation.current_wave_index = int(encounter_state.get("current_wave_index", -1))
	var waves: Array = encounter_state.get("waves", [])
	var wave_id := ""
	if observation.current_wave_index >= 0 and observation.current_wave_index < waves.size() and waves[observation.current_wave_index] is Dictionary:
		wave_id = String((waves[observation.current_wave_index] as Dictionary).get("wave_id", ""))
	for raw_record: Variant in encounter_state.get("spawn_records", []):
		if not raw_record is Dictionary or String((raw_record as Dictionary).get("wave_id", "")) != wave_id:
			continue
		observation.requested_member_count += 1
		var state := String((raw_record as Dictionary).get("state", ""))
		if state == "alive":
			observation.alive_member_count += 1
		if state in ["requested", "alive"]:
			observation.unresolved_member_count += 1
	var objective := String(_main.framework_room.get("objective_id", _main.objective_id))
	if objective == "hunt_elite" and _main.elite_entity_id > 0:
		var elite_alive := _main._enemy_by_entity_id(_main.elite_entity_id) != null
		var requires_full_clear := "summon_reinforcements" in _main.elite_rule_ids
		observation.objective_satisfied = not elite_alive and (not requires_full_clear or _main.enemies.is_empty())
	var result: RoomTerminalResult = _main.room_encounter_port.observe_terminal(observation)
	return result.snapshot()


func _handle_terminal_automation(victory: bool) -> void:
	if not _main.automation_smoke:
		return
	if not victory:
		_main.automation_smoke_failure = "defeat elapsed=%.2f casts=%d" % [_main.elapsed, _main.shots]
		return
	if not _automation_smoke_state_valid():
		_fail_automation_smoke("integrated room/proxy/reward state is invalid")


func _automation_smoke_state_valid() -> bool:
	return not _main.framework_room.is_empty() and _main.battle_victory and (_main.selected_mode != "Auto" or _main.proxy_prediction == "stable")


## The room reports a smoke failure to its host through automation_smoke_failure;
## the host decides whether the process exits.
func _fail_automation_smoke(reason: String) -> void:
	_main.automation_smoke_failure = reason
	_main.room_rules.fail(reason)
	_main.battle_report = String(_main.room_rules.snapshot().report)
