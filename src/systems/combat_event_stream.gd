class_name CombatEventStream
extends RefCounted

## Bounded, deterministic authority-to-presentation event journal.
##
## The simulation owns this stream. Presentation readers receive duplicated
## events and may skip old cosmetic reactions, but they never reconstruct a hit
## from health deltas or write an event back into combat state.

const SCHEMA_VERSION := 1
const DEFAULT_CAPACITY := 192
const EVENT_TYPES: Array[String] = [
	"command_receipt",
	"action_accepted",
	"action_interrupted",
	"action_impact",
	"action_ended",
	"projectile_spawned",
	"attack_resolved",
	"damage_applied",
	"displacement_started",
	"displacement_ended",
	"death_applied",
]

var _capacity: int
var _next_event_id := 1
var _events: Array[Dictionary] = []


func _init(capacity: int = DEFAULT_CAPACITY) -> void:
	_capacity = maxi(1, capacity)


func reset() -> void:
	_next_event_id = 1
	_events.clear()


func emit(tick: int, event_type: String, fields: Dictionary = {}) -> Dictionary:
	if tick < 0 or event_type not in EVENT_TYPES:
		return {}
	var event := {
		"schema_version": SCHEMA_VERSION,
		"event_id": _next_event_id,
		"tick": tick,
		"type": event_type,
	}
	_next_event_id += 1
	for key: Variant in fields.keys():
		var text_key := String(key)
		if text_key in ["schema_version", "event_id", "tick", "type"]:
			continue
		event[text_key] = _copy_value(fields[key])
	_events.append(event)
	while _events.size() > _capacity:
		_events.pop_front()
	return event.duplicate(true)


func latest_event_id() -> int:
	return _next_event_id - 1


func latest(event_type: String = "") -> Dictionary:
	for index: int in range(_events.size() - 1, -1, -1):
		var event: Dictionary = _events[index]
		if event_type.is_empty() or String(event.get("type", "")) == event_type:
			return event.duplicate(true)
	return {}


func events_after(event_id: int, maximum: int = DEFAULT_CAPACITY) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if maximum <= 0:
		return result
	for event: Dictionary in _events:
		if int(event.get("event_id", 0)) <= event_id:
			continue
		result.append(event.duplicate(true))
		if result.size() >= maximum:
			break
	return result


func events_between(from_tick: int, to_tick: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if from_tick > to_tick:
		return result
	for event: Dictionary in _events:
		var tick := int(event.get("tick", -1))
		if tick >= from_tick and tick <= to_tick:
			result.append(event.duplicate(true))
	return result


func snapshot() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"capacity": _capacity,
		"next_event_id": _next_event_id,
		"events": _events.duplicate(true),
	}


func restore_exact(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var state: Dictionary = value
	if state.keys().size() != 4 or not state.has_all(["schema_version", "capacity", "next_event_id", "events"]):
		return false
	if state.get("schema_version", null) != SCHEMA_VERSION:
		return false
	if typeof(state.get("capacity")) != TYPE_INT or typeof(state.get("next_event_id")) != TYPE_INT:
		return false
	var capacity := int(state.capacity)
	var next_event_id := int(state.next_event_id)
	var raw_events: Variant = state.events
	if capacity <= 0 or next_event_id <= 0 or not raw_events is Array:
		return false
	var checked: Array[Dictionary] = []
	var previous_id := 0
	for raw_event: Variant in raw_events:
		if not raw_event is Dictionary:
			return false
		var event: Dictionary = raw_event
		if event.get("schema_version", null) != SCHEMA_VERSION:
			return false
		if typeof(event.get("event_id")) != TYPE_INT or typeof(event.get("tick")) != TYPE_INT:
			return false
		var event_id := int(event.event_id)
		if event_id <= previous_id or event_id >= next_event_id or int(event.tick) < 0:
			return false
		if String(event.get("type", "")) not in EVENT_TYPES:
			return false
		previous_id = event_id
		checked.append(event.duplicate(true))
	if checked.size() > capacity:
		return false
	_capacity = capacity
	_next_event_id = next_event_id
	_events = checked
	return true


static func _copy_value(value: Variant) -> Variant:
	return {"value": value}.duplicate(true)["value"]
