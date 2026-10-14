class_name SimulationWorld
extends RefCounted

## Fixed-tick authority and command/event boundary.
##
## The simulation owns the only presentation-to-tick accumulator for a room.
## A caller supplies the room-specific tick executor, but it never increments
## the clock itself. This keeps rendering, input polling, and room lifecycle
## code from accidentally creating a second authority clock.

const FixedTickClockScript := preload("res://src/core/fixed_tick_clock.gd")

const DEFAULT_TICK_RATE := 30

var tick_rate: int = DEFAULT_TICK_RATE
var tick := 0
var room_instance_id := ""
var world_revision := 0
var clock
var _pending_commands: Array[Dictionary] = []
var _events: Array[Dictionary] = []


func _init() -> void:
	clock = FixedTickClockScript.new(DEFAULT_TICK_RATE)


func configure(new_tick_rate: int, instance_id: String, revision: int = 0) -> Dictionary:
	if new_tick_rate <= 0 or instance_id.strip_edges().is_empty() or revision < 0:
		return {"ok": false, "error": "invalid_simulation_configuration"}
	tick_rate = new_tick_rate
	room_instance_id = instance_id
	world_revision = revision
	tick = 0
	if clock == null or int(clock.ticks_per_second) != tick_rate:
		clock = FixedTickClockScript.new(tick_rate)
	else:
		clock.reset()
	_pending_commands.clear()
	_events.clear()
	return {"ok": true, "error": ""}


func reset_clock() -> void:
	if clock != null:
		clock.reset()


## Converts one presentation frame into whole authority ticks. The room owns
## the gameplay phases that follow each returned tick, but it cannot create a
## second accumulator or advance the authoritative tick directly.
func ticks_for_frame(frame_delta: float) -> int:
	if clock == null:
		return 0
	return int(clock.consume_frame(frame_delta))


## Moves the authoritative clock to a serialized/replay fixture tick. Runtime
## progression still goes through step(); this method exists so state restore and
## deterministic test fixtures do not mutate a second clock on a presentation
## object.
func set_tick(new_tick: int) -> Dictionary:
	if new_tick < 0:
		return {"ok": false, "error": "invalid_tick"}
	tick = new_tick
	return {"ok": true, "error": "", "tick": tick}


func queue_command(command: Dictionary) -> Dictionary:
	if not command.has("kind") or String(command.get("kind", "")).strip_edges().is_empty():
		return {"ok": false, "error": "invalid_command"}
	if command.has("room_instance_id") and String(command.get("room_instance_id", "")) != room_instance_id:
		return {"ok": false, "error": "stale_room_command"}
	if command.has("world_revision") and int(command.get("world_revision", -1)) != world_revision:
		return {"ok": false, "error": "stale_world_command"}
	var versioned := command.duplicate(true)
	versioned["room_instance_id"] = room_instance_id
	versioned["world_revision"] = world_revision
	_pending_commands.append(versioned)
	return {"ok": true, "error": ""}


## Commits one tick. The room runs its fixed phase sequence immediately after
## this method returns, so every gameplay event is stamped with the committed
## tick that the room reads through its SimulationWorld reference.
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
		"clock_phase": float(clock.phase) if clock != null else 0.0,
		"pending_commands": _pending_commands.duplicate(true),
		"events": _events.duplicate(true),
	}
