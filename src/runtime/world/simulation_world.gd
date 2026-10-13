class_name SimulationWorld
extends RefCounted

## Fixed-tick authority container. It deliberately does not know how a scene
## is drawn or how a room is selected.

const DEFAULT_TICK_RATE := 30

var tick_rate: int = DEFAULT_TICK_RATE
var tick := 0
var room_instance_id := ""
var world_revision := 0
var _pending_commands: Array[Dictionary] = []
var _events: Array[Dictionary] = []


func configure(new_tick_rate: int, instance_id: String, revision: int = 0) -> Dictionary:
	if new_tick_rate <= 0 or instance_id.strip_edges().is_empty() or revision < 0:
		return {"ok": false, "error": "invalid_simulation_configuration"}
	tick_rate = new_tick_rate
	room_instance_id = instance_id
	world_revision = revision
	tick = 0
	_pending_commands.clear()
	_events.clear()
	return {"ok": true, "error": ""}


func queue_command(command: Dictionary) -> Dictionary:
	if not command.has("kind") or String(command.get("kind", "")).strip_edges().is_empty():
		return {"ok": false, "error": "invalid_command"}
	_pending_commands.append(command.duplicate(true))
	return {"ok": true, "error": ""}


func step() -> Dictionary:
	var commands := _pending_commands.duplicate(true)
	_pending_commands.clear()
	commands.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_id := String(left.get("entity_id", ""))
		var right_id := String(right.get("entity_id", ""))
		if left_id != right_id:
			return left_id < right_id
		return String(left.get("kind", "")) < String(right.get("kind", ""))
	)
	tick += 1
	return {
		"tick": tick,
		"room_instance_id": room_instance_id,
		"world_revision": world_revision,
		"commands": commands,
		"events": _events.duplicate(true),
	}


func publish_event(event: Dictionary) -> Dictionary:
	if not event.has("kind"):
		return {"ok": false, "error": "invalid_event"}
	var enriched := event.duplicate(true)
	enriched["tick"] = tick
	enriched["room_instance_id"] = room_instance_id
	enriched["world_revision"] = world_revision
	_events.append(enriched)
	return {"ok": true, "error": ""}


func events_after(after_tick: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for event: Dictionary in _events:
		if int(event.get("tick", -1)) > after_tick:
			result.append(event.duplicate(true))
	return result


func snapshot() -> Dictionary:
	return {
		"tick_rate": tick_rate,
		"tick": tick,
		"room_instance_id": room_instance_id,
		"world_revision": world_revision,
		"pending_commands": _pending_commands.duplicate(true),
		"events": _events.duplicate(true),
	}
