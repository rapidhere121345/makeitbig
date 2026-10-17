class_name SimCommandBuffer
extends RefCounted

## Ordered external command queue.
##
## Commands keep strict submission order (monotonic submit_sequence). The queue
## drains exactly once per tick during the action commit phase; validation of
## room/revision stamps happens at enqueue so stale senders fail closed early.

const SimOutcomeScript := preload("res://src/runtime/simulation/sim_outcome.gd")

var _commands: Array[SimCommand] = []
var _next_sequence: int = 1


func enqueue(command: SimCommand, room_instance_id: String, world_revision: int) -> SimOutcome:
	if command == null:
		return SimOutcome.failure(&"null_command")
	if command.kind not in [SimCommand.Kind.SPAWN, SimCommand.Kind.DESPAWN, SimCommand.Kind.CONTROL]:
		return SimOutcome.failure(&"unknown_command_kind")
	# Fresh commands carry empty stamps; only a non-empty mismatching stamp is
	# stale and must fail closed.
	if not command.room_instance_id.is_empty() and command.room_instance_id != room_instance_id:
		return SimOutcome.failure(&"stale_room_reference")
	if command.world_revision >= 0 and command.world_revision != world_revision:
		return SimOutcome.failure(&"stale_world_revision")
	command.room_instance_id = room_instance_id
	command.world_revision = world_revision
	command.submit_sequence = _next_sequence
	_next_sequence += 1
	_commands.append(command)
	return SimOutcome.success()


func drain() -> Array[SimCommand]:
	var drained := _commands
	_commands = []
	return drained


func pending_count() -> int:
	return _commands.size()


func clear() -> void:
	_commands.clear()
