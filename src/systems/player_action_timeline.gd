class_name PlayerActionTimeline
extends RefCounted

## Pure fixed-tick authority for the Ranger's Piercing Arrow action.

const RangerSkillRules := preload("res://src/systems/ranger_skill_rules.gd")

const SCHEMA: String = "makeitbig.player_action_timeline"
const SCHEMA_VERSION: int = 1
const PROTOCOL_VERSION: int = 1

const WINDUP_TICKS: int = RangerSkillRules.PIERCING_ARROW_WINDUP_TICKS
const RECOVERY_TICKS: int = RangerSkillRules.PIERCING_ARROW_RECOVERY_TICKS
const INPUT_BUFFER_TICKS: int = RangerSkillRules.ACTION_INPUT_BUFFER_TICKS

const PHASE_IDLE: String = "idle"
const PHASE_WINDUP: String = "windup"
const PHASE_RECOVERY: String = "recovery"

var _last_advanced_tick: int = -1
var _next_action_instance_id: int = 1
var _next_request_id: int = 1
var _active: Dictionary = {}
var _buffered: Dictionary = {}


func reset() -> void:
	_last_advanced_tick = -1
	_next_action_instance_id = 1
	_next_request_id = 1
	_active = {}
	_buffered = {}


func request_attack(
	tick: int,
	target_entity_id: int,
	aim_direction: Vector2,
	ready_tick: int = -1,
	windup_ticks: int = WINDUP_TICKS
) -> Dictionary:
	var request_id := _next_request_id
	_next_request_id += 1
	if ready_tick < 0:
		ready_tick = tick
	if tick < 0 or tick < _last_advanced_tick:
		return _receipt(false, "rejected", "stale_tick", request_id)
	if target_entity_id <= 0:
		return _receipt(false, "rejected", "invalid_target", request_id)
	var quantized_aim := _quantize_direction(aim_direction)
	if quantized_aim.is_empty():
		return _receipt(false, "rejected", "invalid_aim_direction", request_id)
	if windup_ticks < 1 or windup_ticks > WINDUP_TICKS:
		return _receipt(false, "rejected", "invalid_windup_ticks", request_id)

	var request := {
		"request_id": request_id,
		"request_tick": tick,
		"target_entity_id": target_entity_id,
		"aim_x_milli": int(quantized_aim["x"]),
		"aim_y_milli": int(quantized_aim["y"]),
		"ready_tick": ready_tick,
		"start_tick": tick,
		"windup_ticks": windup_ticks,
	}
	if _active.is_empty() and ready_tick <= tick:
		_begin_action(request, tick, false)
		var started := _receipt(true, "started", "", request_id)
		started["action_instance_id"] = int(_active["action_instance_id"])
		started["start_tick"] = tick
		return started.duplicate(true)

	var lock_clear_tick := tick
	if not _active.is_empty():
		lock_clear_tick = _action_end_tick(_active)
	var eligible_tick := maxi(tick, maxi(ready_tick, lock_clear_tick))
	if eligible_tick - tick > INPUT_BUFFER_TICKS:
		return _receipt(false, "rejected", "outside_buffer_window", request_id)

	request["start_tick"] = eligible_tick
	var replaced_request_id := 0
	var status := "buffered"
	if not _buffered.is_empty():
		replaced_request_id = int(_buffered["request_id"])
		status = "replaced"
	_buffered = request.duplicate(true)
	var buffered := _receipt(true, status, "", request_id)
	buffered["start_tick"] = eligible_tick
	if replaced_request_id > 0:
		buffered["replaced_request_id"] = replaced_request_id
	return buffered.duplicate(true)


func advance(tick: int) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if tick < 0 or tick < _last_advanced_tick:
		return events
	_collect_until(tick, events)
	_last_advanced_tick = tick
	return events.duplicate(true)


func interrupt(tick: int, reason: String) -> Dictionary:
	if tick < 0 or tick < _last_advanced_tick:
		return {
			"accepted": false,
			"status": "rejected",
			"reason": "stale_tick",
			"tick": tick,
			"events": [],
		}.duplicate(true)
	var events: Array[Dictionary] = []
	_collect_until(tick, events)
	var interrupted_action_id := 0
	if not _active.is_empty():
		interrupted_action_id = int(_active["action_instance_id"])
		events.append({
			"type": "action_interrupted",
			"tick": tick,
			"action_instance_id": interrupted_action_id,
			"reason": reason,
		})
	var cleared_request_id := 0
	if not _buffered.is_empty():
		cleared_request_id = int(_buffered["request_id"])
	_active = {}
	_buffered = {}
	_last_advanced_tick = tick
	return {
		"accepted": interrupted_action_id > 0 or cleared_request_id > 0,
		"status": "interrupted" if interrupted_action_id > 0 or cleared_request_id > 0 else "idle",
		"reason": reason,
		"tick": tick,
		"action_instance_id": interrupted_action_id,
		"cleared_request_id": cleared_request_id,
		"events": events,
	}.duplicate(true)


## Removes only the queued follow-up for this exact entity. An action that has
## already started remains authoritative and is never changed by this cleanup.
func cancel_buffered_target(target_entity_id: int) -> int:
	if target_entity_id <= 0 or _buffered.is_empty():
		return 0
	if int(_buffered.get("target_entity_id", 0)) != target_entity_id:
		return 0
	var request_id := int(_buffered.get("request_id", 0))
	_buffered = {}
	return request_id


func phase_at(tick: int) -> String:
	if tick < 0:
		return PHASE_IDLE
	if not _active.is_empty():
		var active_start := int(_active["start_tick"])
		var active_end := _action_end_tick(_active)
		if tick >= active_start and tick < active_end:
			var impact_tick := active_start + _action_windup_ticks(_active)
			return PHASE_WINDUP if tick < impact_tick else PHASE_RECOVERY
		if tick < active_start:
			return PHASE_IDLE
	if not _buffered.is_empty():
		var buffered_start := int(_buffered["start_tick"])
		var buffered_windup := _action_windup_ticks(_buffered)
		if tick >= buffered_start and tick < buffered_start + buffered_windup:
			return PHASE_WINDUP
		if tick >= buffered_start + buffered_windup and tick < buffered_start + buffered_windup + RECOVERY_TICKS:
			return PHASE_RECOVERY
	return PHASE_IDLE


func snapshot() -> Dictionary:
	return {
		"schema": SCHEMA,
		"schema_version": SCHEMA_VERSION,
		"protocol_version": PROTOCOL_VERSION,
		"last_advanced_tick": _last_advanced_tick,
		"next_action_instance_id": _next_action_instance_id,
		"next_request_id": _next_request_id,
		"active": _active.duplicate(true),
		"buffered": _buffered.duplicate(true),
	}.duplicate(true)


func restore_exact(value: Dictionary) -> bool:
	if not _valid_snapshot(value):
		reset()
		return false
	_last_advanced_tick = int(value["last_advanced_tick"])
	_next_action_instance_id = int(value["next_action_instance_id"])
	_next_request_id = int(value["next_request_id"])
	_active = Dictionary(value["active"]).duplicate(true)
	_buffered = Dictionary(value["buffered"]).duplicate(true)
	return true


func _collect_until(tick: int, events: Array[Dictionary]) -> void:
	while true:
		if _active.is_empty():
			if not _buffered.is_empty() and int(_buffered["start_tick"]) <= tick:
				_start_buffered(events)
				continue
			return

		var start_tick := int(_active["start_tick"])
		var action_id := int(_active["action_instance_id"])
		if not bool(_active["started_emitted"]) and start_tick <= tick:
			events.append(_action_event("action_started", start_tick, _active))
			_active["started_emitted"] = true
		var impact_tick := start_tick + _action_windup_ticks(_active)
		if not bool(_active["impact_emitted"]) and impact_tick <= tick:
			events.append(_action_event("action_impact", impact_tick, _active))
			_active["impact_emitted"] = true
		var end_tick := impact_tick + RECOVERY_TICKS
		if end_tick > tick:
			return
		events.append({
			"type": "action_ended",
			"tick": end_tick,
			"action_instance_id": action_id,
		})
		_active = {}
		if not _buffered.is_empty() and int(_buffered["start_tick"]) <= tick:
			_start_buffered(events)
			continue
		return


func _start_buffered(events: Array[Dictionary]) -> void:
	var request := _buffered.duplicate(true)
	_buffered = {}
	var start_tick := int(request["start_tick"])
	_begin_action(request, start_tick, true)
	events.append({
		"type": "buffered_started",
		"tick": start_tick,
		"request_id": int(request["request_id"]),
		"action_instance_id": int(_active["action_instance_id"]),
	})


func _begin_action(request: Dictionary, start_tick: int, from_buffer: bool) -> void:
	_active = {
		"request_id": int(request["request_id"]),
		"request_tick": int(request["request_tick"]),
		"target_entity_id": int(request["target_entity_id"]),
		"aim_x_milli": int(request["aim_x_milli"]),
		"aim_y_milli": int(request["aim_y_milli"]),
		"ready_tick": int(request["ready_tick"]),
		"start_tick": start_tick,
		"action_instance_id": _next_action_instance_id,
		"from_buffer": from_buffer,
		"windup_ticks": _action_windup_ticks(request),
		"started_emitted": false,
		"impact_emitted": false,
	}
	_next_action_instance_id += 1


func _action_event(event_type: String, tick: int, action: Dictionary) -> Dictionary:
	return {
		"type": event_type,
		"tick": tick,
		"action_instance_id": int(action["action_instance_id"]),
		"target_entity_id": int(action["target_entity_id"]),
		"windup_ticks": _action_windup_ticks(action),
		"aim_direction_milli": {
			"x": int(action["aim_x_milli"]),
			"y": int(action["aim_y_milli"]),
		},
	}.duplicate(true)


func _action_windup_ticks(action: Dictionary) -> int:
	var value := int(action.get("windup_ticks", WINDUP_TICKS))
	return clampi(value, 1, WINDUP_TICKS)


func _action_end_tick(action: Dictionary) -> int:
	return int(action.get("start_tick", 0)) + _action_windup_ticks(action) + RECOVERY_TICKS


func _receipt(accepted: bool, status: String, reason: String, request_id: int) -> Dictionary:
	return {
		"accepted": accepted,
		"status": status,
		"reason": reason,
		"request_id": request_id,
	}.duplicate(true)


func _quantize_direction(direction: Vector2) -> Dictionary:
	if not is_finite(direction.x) or not is_finite(direction.y) or direction.length_squared() <= 0.0:
		return {}
	var normalized := direction.normalized()
	var x := roundi(normalized.x * 1000.0)
	var y := roundi(normalized.y * 1000.0)
	if x == 0 and y == 0:
		return {}
	return {"x": x, "y": y}


func _valid_snapshot(value: Dictionary) -> bool:
	var keys := [
		"schema", "schema_version", "protocol_version", "last_advanced_tick",
		"next_action_instance_id", "next_request_id", "active", "buffered",
	]
	if not _has_exact_keys(value, keys):
		return false
	if typeof(value["schema"]) != TYPE_STRING or String(value["schema"]) != SCHEMA:
		return false
	if typeof(value["schema_version"]) != TYPE_INT or int(value["schema_version"]) != SCHEMA_VERSION:
		return false
	if typeof(value["protocol_version"]) != TYPE_INT or int(value["protocol_version"]) != PROTOCOL_VERSION:
		return false
	for key in ["last_advanced_tick", "next_action_instance_id", "next_request_id"]:
		if typeof(value[key]) != TYPE_INT:
			return false
	var last_tick := int(value["last_advanced_tick"])
	var next_action_id := int(value["next_action_instance_id"])
	var next_request_id := int(value["next_request_id"])
	if last_tick < -1 or next_action_id < 1 or next_request_id < 1:
		return false
	if typeof(value["active"]) != TYPE_DICTIONARY or typeof(value["buffered"]) != TYPE_DICTIONARY:
		return false
	var active := Dictionary(value["active"])
	var buffered := Dictionary(value["buffered"])
	if not active.is_empty() and not _valid_active(active, last_tick, next_action_id, next_request_id):
		return false
	if not buffered.is_empty() and not _valid_buffer(buffered, last_tick, next_request_id):
		return false
	if not active.is_empty() and not buffered.is_empty():
		var lock_clear := _action_end_tick(active)
		if int(buffered["start_tick"]) < lock_clear:
			return false
	return true


func _valid_active(action: Dictionary, last_tick: int, next_action_id: int, next_request_id: int) -> bool:
	var keys := [
		"request_id", "request_tick", "target_entity_id", "aim_x_milli", "aim_y_milli",
		"ready_tick", "start_tick", "action_instance_id", "from_buffer",
		"windup_ticks",
		"started_emitted", "impact_emitted",
	]
	if not _has_exact_keys(action, keys):
		return false
	for key in ["request_id", "request_tick", "target_entity_id", "aim_x_milli", "aim_y_milli", "ready_tick", "start_tick", "action_instance_id"]:
		if typeof(action[key]) != TYPE_INT:
			return false
	if typeof(action.get("windup_ticks", WINDUP_TICKS)) != TYPE_INT:
		return false
	if int(action.get("windup_ticks", WINDUP_TICKS)) < 1 or int(action.get("windup_ticks", WINDUP_TICKS)) > WINDUP_TICKS:
		return false
	for key in ["from_buffer", "started_emitted", "impact_emitted"]:
		if typeof(action[key]) != TYPE_BOOL:
			return false
	if int(action["request_id"]) < 1 or int(action["request_id"]) >= next_request_id:
		return false
	if int(action["action_instance_id"]) < 1 or int(action["action_instance_id"]) >= next_action_id:
		return false
	if int(action["action_instance_id"]) != next_action_id - 1:
		return false
	if int(action["request_tick"]) < 0 or int(action["target_entity_id"]) <= 0:
		return false
	if int(action["start_tick"]) < int(action["request_tick"]):
		return false
	if int(action["ready_tick"]) > int(action["start_tick"]):
		return false
	if bool(action["from_buffer"]):
		if int(action["start_tick"]) - int(action["request_tick"]) > INPUT_BUFFER_TICKS:
			return false
	elif int(action["start_tick"]) != int(action["request_tick"]):
		return false
	if not _valid_milli_direction(int(action["aim_x_milli"]), int(action["aim_y_milli"])):
		return false
	if bool(action["impact_emitted"]) and not bool(action["started_emitted"]):
		return false
	var start_tick := int(action["start_tick"])
	if start_tick < last_tick and not bool(action["started_emitted"]):
		return false
	if start_tick + _action_windup_ticks(action) <= last_tick and not bool(action["impact_emitted"]):
		return false
	if start_tick + _action_windup_ticks(action) + RECOVERY_TICKS <= last_tick:
		return false
	return true


func _valid_buffer(buffered: Dictionary, last_tick: int, next_request_id: int) -> bool:
	var keys := [
		"request_id", "request_tick", "target_entity_id", "aim_x_milli", "aim_y_milli",
		"ready_tick", "start_tick",
		"windup_ticks",
	]
	if not _has_exact_keys(buffered, keys):
		return false
	for key in keys:
		if typeof(buffered[key]) != TYPE_INT:
			return false
	if int(buffered["request_id"]) < 1 or int(buffered["request_id"]) >= next_request_id:
		return false
	if int(buffered["request_tick"]) < 0 or int(buffered["target_entity_id"]) <= 0:
		return false
	if int(buffered["start_tick"]) < int(buffered["request_tick"]):
		return false
	if int(buffered["ready_tick"]) > int(buffered["start_tick"]):
		return false
	if int(buffered["start_tick"]) - int(buffered["request_tick"]) > INPUT_BUFFER_TICKS:
		return false
	if int(buffered["start_tick"]) < last_tick:
		return false
	return _valid_milli_direction(int(buffered["aim_x_milli"]), int(buffered["aim_y_milli"]))


func _valid_milli_direction(x: int, y: int) -> bool:
	if x == 0 and y == 0:
		return false
	return absi(x) <= 1000 and absi(y) <= 1000


func _has_exact_keys(value: Dictionary, keys: Array) -> bool:
	if value.size() != keys.size():
		return false
	for key in keys:
		if not value.has(key):
			return false
	return true
