class_name RoomEncounter
extends RefCounted

const WaveScript := preload("res://src/runtime/encounter/wave_definition.gd")
const SpawnRequestScript := preload("res://src/runtime/encounter/encounter_spawn_request.gd")
const StepResultScript := preload("res://src/runtime/encounter/encounter_step_result.gd")
const TerminalObservationScript := preload("res://src/runtime/encounter/room_terminal_observation.gd")
const TerminalResultScript := preload("res://src/runtime/encounter/room_terminal_result.gd")
const CoreResult := preload("res://src/core/result.gd")

const PHASE_IDLE := "idle"
const PHASE_SPAWNING := "spawning"
const PHASE_ACTIVE := "active"
const PHASE_WAITING := "waiting_next_wave"
const PHASE_VICTORY := "victory"
const PHASE_DEFEAT := "defeat"

var room_id := ""
var phase := PHASE_IDLE
var current_wave_index := -1
var last_tick := -1
var terminal_reason := ""

var _waves: Array = []
var _wave_start_tick := -1
var _next_wave_tick := -1
var _spawn_records: Dictionary = {}
var _entity_to_spawn: Dictionary = {}
var _current_wave_keys: Array[String] = []


func configure(identifier: String, definitions: Array, initial_tick: int = -1) -> Dictionary:
	if not _valid_id(identifier) or initial_tick < -1:
		return CoreResult.failure("invalid_encounter_configuration")
	var parsed: Array = []
	var seen: Dictionary = {}
	for raw: Variant in definitions:
		var result := WaveScript.from_data(raw)
		if not bool(result.get("ok", false)):
			return result
		var wave: Variant = result["value"]
		if seen.has(wave.wave_id):
			return CoreResult.failure("duplicate_wave_id:%s" % wave.wave_id)
		seen[wave.wave_id] = true
		parsed.append(wave)
	if parsed.is_empty():
		return CoreResult.failure("missing_waves")
	room_id = identifier
	_waves = parsed
	last_tick = initial_tick
	phase = PHASE_IDLE
	current_wave_index = -1
	_wave_start_tick = -1
	_next_wave_tick = -1
	_spawn_records.clear()
	_entity_to_spawn.clear()
	_current_wave_keys.clear()
	terminal_reason = ""
	return {"ok": true, "error": "", "snapshot": snapshot()}


## Re-arms the same authored encounter for a new mounted room instance.  The
## wave definitions stay immutable and all per-run spawn/member state is
## discarded.  SceneRuntime owns the room revision; this domain only owns its
## fixed-tick encounter state.
func restart(initial_tick: int = -1) -> Dictionary:
	if _waves.is_empty() or initial_tick < -1:
		return CoreResult.failure("encounter_not_configured")
	last_tick = initial_tick
	phase = PHASE_IDLE
	current_wave_index = -1
	_wave_start_tick = -1
	_next_wave_tick = -1
	_spawn_records.clear()
	_entity_to_spawn.clear()
	_current_wave_keys.clear()
	terminal_reason = ""
	return {"ok": true, "error": "", "snapshot": snapshot()}


func start(tick: int) -> Dictionary:
	if _waves.is_empty():
		return CoreResult.failure("encounter_not_configured")
	if tick < 0 or tick < last_tick:
		return CoreResult.failure("stale_encounter_tick")
	if phase != PHASE_IDLE:
		return CoreResult.failure("encounter_already_started")
	last_tick = tick
	current_wave_index = 0
	_wave_start_tick = tick + _waves[0].start_delay_ticks
	_next_wave_tick = _wave_start_tick
	_current_wave_keys.clear()
	phase = PHASE_SPAWNING
	return {"ok": true, "error": "", "snapshot": snapshot()}


func step(tick: int) -> Variant:
	var result: Variant = StepResultScript.new()
	result.tick = tick
	result.phase = phase
	if tick < 0 or tick < last_tick:
		result.events.append({"type": "rejected", "reason": "stale_encounter_tick"})
		return result
	last_tick = tick
	if phase in [PHASE_IDLE, PHASE_VICTORY, PHASE_DEFEAT]:
		result.phase = phase
		result.victory = phase == PHASE_VICTORY
		result.defeat = phase == PHASE_DEFEAT
		return result
	if current_wave_index < 0 or current_wave_index >= _waves.size():
		result.events.append({"type": "rejected", "reason": "invalid_current_wave"})
		return result
	var wave: Variant = _waves[current_wave_index]
	if phase == PHASE_WAITING:
		if tick < _next_wave_tick:
			result.phase = phase
			return result
		current_wave_index += 1
		if current_wave_index >= _waves.size():
			phase = PHASE_VICTORY
			terminal_reason = "all_waves_cleared"
			result.changed = true
			result.victory = true
			result.phase = phase
			result.events.append({"type": "victory", "reason": terminal_reason})
			return result
		wave = _waves[current_wave_index]
		_wave_start_tick = tick + wave.start_delay_ticks
		_next_wave_tick = _wave_start_tick
		_current_wave_keys.clear()
		phase = PHASE_SPAWNING
		result.changed = true
		result.events.append({"type": "wave_started", "wave_id": wave.wave_id, "wave_index": current_wave_index})
	if phase == PHASE_SPAWNING and tick >= _wave_start_tick:
		var requests := _emit_due_requests(wave, tick)
		result.spawn_requests.append_array(requests)
		if _all_wave_requests_emitted(wave):
			phase = PHASE_ACTIVE
		result.changed = result.changed or not requests.is_empty()
	if phase == PHASE_ACTIVE and _wave_is_cleared(wave):
		if wave.clear_policy == "manual":
			result.phase = phase
		else:
			var transition: Dictionary = _advance_after_wave_clear(tick, wave)
			result.changed = bool(transition.get("changed", false))
			result.events.append_array(transition.get("events", []))
	result.phase = phase
	result.victory = phase == PHASE_VICTORY
	result.defeat = phase == PHASE_DEFEAT
	return result


func notify_spawned(spawn_key: String, entity_key: String, tick: int) -> Dictionary:
	if tick < 0 or tick < last_tick:
		return CoreResult.failure("stale_encounter_tick")
	var record: Dictionary = _spawn_records.get(spawn_key, {})
	if record.is_empty():
		return CoreResult.failure("unknown_spawn_key")
	if String(record.get("state", "")) != "requested":
		return CoreResult.failure("spawn_not_requested")
	if not _valid_id(entity_key):
		return CoreResult.failure("invalid_entity_key")
	if _entity_to_spawn.has(entity_key):
		return CoreResult.failure("entity_key_already_registered")
	record["state"] = "alive"
	record["entity_key"] = entity_key
	record["spawned_tick"] = tick
	_spawn_records[spawn_key] = record
	_entity_to_spawn[entity_key] = spawn_key
	last_tick = maxi(last_tick, tick)
	return {"ok": true, "error": "", "snapshot": snapshot()}


func notify_spawn_failed(spawn_key: String, tick: int, reason: String) -> Dictionary:
	if tick < 0 or tick < last_tick:
		return CoreResult.failure("stale_encounter_tick")
	if reason.strip_edges().is_empty():
		return CoreResult.failure("invalid_spawn_failure_reason")
	var record: Dictionary = _spawn_records.get(spawn_key, {})
	if record.is_empty():
		return CoreResult.failure("unknown_spawn_key")
	if String(record.get("state", "")) != "requested":
		return CoreResult.failure("spawn_not_requested")
	record["state"] = "failed"
	record["failure_reason"] = reason
	_spawn_records[spawn_key] = record
	last_tick = maxi(last_tick, tick)
	return {"ok": true, "error": "", "snapshot": snapshot()}


func notify_death(entity_key: String, tick: int) -> Dictionary:
	if tick < 0 or tick < last_tick:
		return CoreResult.failure("stale_encounter_tick")
	for spawn_key: String in _sorted_spawn_keys():
		var record: Dictionary = _spawn_records[spawn_key]
		if String(record.get("entity_key", "")) != entity_key:
			continue
		if String(record.get("state", "")) != "alive":
			return CoreResult.failure("entity_not_alive_in_encounter")
		record["state"] = "dead"
		record["dead_tick"] = tick
		_spawn_records[spawn_key] = record
		last_tick = maxi(last_tick, tick)
		return {"ok": true, "error": "", "snapshot": snapshot()}
	return CoreResult.failure("unknown_entity_key")


## Sole terminal decision boundary for a mounted room.  The observation is
## checked against this domain's current wave records before any transition;
## callers cannot invent a clear by sending a contradictory member count.
## Clear wins over player death on the same tick by deliberate ordering.
func observe_terminal(observation: RoomTerminalObservation) -> RoomTerminalResult:
	if observation == null or not observation.is_valid():
		return TerminalResultScript.failure("invalid_terminal_observation")
	if observation.tick < last_tick:
		return TerminalResultScript.failure("stale_encounter_tick")
	if phase in [PHASE_VICTORY, PHASE_DEFEAT]:
		last_tick = maxi(last_tick, observation.tick)
		return _terminal_result(observation, false, true, terminal_reason)
	if current_wave_index < 0 or current_wave_index >= _waves.size():
		return TerminalResultScript.failure("terminal_observation_without_wave")
	if observation.current_wave_index != current_wave_index:
		return TerminalResultScript.failure("terminal_wave_index_mismatch")
	var counts := _current_wave_member_counts()
	if observation.requested_member_count != counts.requested or observation.alive_member_count != counts.alive or observation.unresolved_member_count != counts.unresolved:
		return TerminalResultScript.failure("terminal_member_facts_mismatch")
	last_tick = observation.tick
	var wave: Variant = _waves[current_wave_index]
	var wave_clear: bool = phase == PHASE_ACTIVE and wave.clear_policy != "manual" and int(counts.requested) > 0 and int(counts.unresolved) == 0
	if phase == PHASE_ACTIVE and wave.objective_tag == "hunt_elite" and observation.objective_satisfied:
		wave_clear = true
	if wave_clear:
		var transition: Dictionary = _advance_after_wave_clear(observation.tick, wave)
		return _terminal_result(observation, bool(transition.get("changed", false)), false, terminal_reason)
	if not observation.player_alive:
		phase = PHASE_DEFEAT
		terminal_reason = "player_dead"
		return _terminal_result(observation, true, false, terminal_reason)
	return _terminal_result(observation, false, false, "")


func request_defeat(tick: int, reason: String) -> Dictionary:
	if tick < 0 or tick < last_tick:
		return CoreResult.failure("stale_encounter_tick")
	if reason.strip_edges().is_empty():
		return CoreResult.failure("invalid_defeat_reason")
	last_tick = tick
	if phase == PHASE_VICTORY:
		return {"ok": true, "error": "", "changed": false, "snapshot": snapshot()}
	if phase == PHASE_DEFEAT:
		return {"ok": true, "error": "", "changed": false, "snapshot": snapshot()}
	phase = PHASE_DEFEAT
	terminal_reason = reason.strip_edges()
	return {"ok": true, "error": "", "changed": true, "snapshot": snapshot()}


## Explicitly clears a manually governed wave.  Automatic all-dead waves use
## the same transition from step(); manual waves must opt into it through this
## typed domain method so a death receipt alone can never fabricate a clear.
func request_wave_clear(tick: int) -> Dictionary:
	if tick < 0 or tick < last_tick:
		return CoreResult.failure("stale_encounter_tick")
	if phase in [PHASE_VICTORY, PHASE_DEFEAT]:
		return {"ok": true, "error": "", "changed": false, "snapshot": snapshot()}
	if phase != PHASE_ACTIVE or current_wave_index < 0 or current_wave_index >= _waves.size():
		return CoreResult.failure("wave_not_active")
	var wave: Variant = _waves[current_wave_index]
	if wave.clear_policy != "manual":
		return CoreResult.failure("wave_clear_policy_not_manual")
	last_tick = tick
	return _advance_after_wave_clear(tick, wave)


func snapshot() -> Dictionary:
	var waves: Array[Dictionary] = []
	for wave: Variant in _waves:
		waves.append(wave.snapshot())
	var records: Array[Dictionary] = []
	for key: String in _sorted_spawn_keys():
		var record: Dictionary = _spawn_records[key].duplicate(true)
		record["spawn_key"] = key
		records.append(record)
	return {
		"room_id": room_id,
		"phase": phase,
		"current_wave_index": current_wave_index,
		"last_tick": last_tick,
		"wave_start_tick": _wave_start_tick,
		"next_wave_tick": _next_wave_tick,
		"terminal_reason": terminal_reason,
		"terminal": phase in [PHASE_VICTORY, PHASE_DEFEAT],
		"waves": waves,
		"spawn_records": records,
	}


func _emit_due_requests(wave: Variant, tick: int) -> Array:
	var requests: Array = []
	for spec: Variant in wave.spawn_specs:
		for ordinal in spec.count:
			var key: String = spec.spawn_key(wave.wave_id, ordinal)
			if _spawn_records.has(key):
				continue
			var requested_tick: int = spec.requested_tick(_wave_start_tick, ordinal)
			if requested_tick > tick:
				continue
			_spawn_records[key] = {"wave_id": wave.wave_id, "spawn_id": spec.spawn_id, "ordinal": ordinal, "state": "requested", "requested_tick": requested_tick, "entity_key": ""}
			_current_wave_keys.append(key)
			var request: Variant = SpawnRequestScript.new()
			request.request_id = "%s/request/%d" % [key, requested_tick]
			request.room_id = room_id
			request.wave_id = wave.wave_id
			request.spawn_key = key
			request.archetype_id = spec.archetype_id
			request.socket_id = spec.socket_id
			request.requested_tick = requested_tick
			request.ordinal = ordinal
			request.tags = spec.tags.duplicate()
			requests.append(request)
	requests.sort_custom(func(left: Variant, right: Variant) -> bool:
		if left.requested_tick != right.requested_tick:
			return left.requested_tick < right.requested_tick
		var left_wave_spawn := "%s/%s" % [left.wave_id, left.spawn_key.get_base_dir()]
		var right_wave_spawn := "%s/%s" % [right.wave_id, right.spawn_key.get_base_dir()]
		if left_wave_spawn != right_wave_spawn:
			return left_wave_spawn < right_wave_spawn
		if left.ordinal != right.ordinal:
			return left.ordinal < right.ordinal
		return left.spawn_key < right.spawn_key
	)
	return requests


func _all_wave_requests_emitted(wave: Variant) -> bool:
	for spec: Variant in wave.spawn_specs:
		for ordinal in spec.count:
			if not _spawn_records.has(spec.spawn_key(wave.wave_id, ordinal)):
				return false
	return true


func _wave_is_cleared(wave: Variant) -> bool:
	if not _all_wave_requests_emitted(wave):
		return false
	for key: String in _current_wave_keys:
		var state := String((_spawn_records.get(key, {}) as Dictionary).get("state", ""))
		if state in ["requested", "alive"]:
			return false
	return true


func _current_wave_member_counts() -> Dictionary:
	var requested := 0
	var alive := 0
	var unresolved := 0
	for key: String in _current_wave_keys:
		var state := String((_spawn_records.get(key, {}) as Dictionary).get("state", ""))
		if state.is_empty():
			continue
		requested += 1
		if state == "alive":
			alive += 1
		if state in ["requested", "alive"]:
			unresolved += 1
	return {"requested": requested, "alive": alive, "unresolved": unresolved}


func _terminal_result(observation: RoomTerminalObservation, changed: bool, duplicate: bool, reason: String) -> RoomTerminalResult:
	var result := TerminalResultScript.new()
	result.ok = true
	result.changed = changed
	result.duplicate = duplicate
	result.tick = observation.tick
	result.room_instance_id = observation.room_instance_id
	result.world_revision = observation.world_revision
	result.phase = phase
	result.reason = reason
	return result


func _advance_after_wave_clear(tick: int, wave: Variant) -> Dictionary:
	if current_wave_index == _waves.size() - 1:
		phase = PHASE_VICTORY
		terminal_reason = "all_waves_cleared"
		return {
			"ok": true,
			"error": "",
			"changed": true,
			"events": [{"type": "victory", "reason": terminal_reason}],
			"snapshot": snapshot(),
		}
	phase = PHASE_WAITING
	_next_wave_tick = tick + wave.next_wave_delay_ticks
	return {
		"ok": true,
		"error": "",
		"changed": true,
		"events": [{"type": "wave_cleared", "wave_id": wave.wave_id, "next_tick": _next_wave_tick}],
		"snapshot": snapshot(),
	}


func _sorted_spawn_keys() -> Array[String]:
	var keys: Array[String] = []
	for key: Variant in _spawn_records.keys():
		keys.append(String(key))
	keys.sort_custom(func(left: String, right: String) -> bool:
		var left_record: Dictionary = _spawn_records.get(left, {})
		var right_record: Dictionary = _spawn_records.get(right, {})
		var left_wave := String(left_record.get("wave_id", ""))
		var right_wave := String(right_record.get("wave_id", ""))
		if left_wave != right_wave:
			return left_wave < right_wave
		var left_spawn := String(left_record.get("spawn_id", ""))
		var right_spawn := String(right_record.get("spawn_id", ""))
		if left_spawn != right_spawn:
			return left_spawn < right_spawn
		var left_ordinal := int(left_record.get("ordinal", -1))
		var right_ordinal := int(right_record.get("ordinal", -1))
		if left_ordinal != right_ordinal:
			return left_ordinal < right_ordinal
		return left < right
	)
	return keys


func _valid_id(value: String) -> bool:
	return not value.is_empty() and value == value.strip_edges() and not value.contains(" ")
