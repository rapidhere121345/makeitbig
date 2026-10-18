class_name SimEntityHandle
extends RefCounted

## Generational entity handle.
##
## A handle is a stable *reference* to a slot in one room-scoped entity store.
## The slot index enables O(1) lookup; the generation invalidates the handle as
## soon as the slot is reclaimed and reused. Store, room and revision scope are
## part of the handle so a handle copied across a room restart cannot resolve a
## coincidentally matching slot and generation. Handles never encode gameplay
## meaning and never act as identity: identity is the StableEntityKey.

var index: int = -1
var generation: int = 0
var store_id: StringName = &""
var room_instance_id: String = ""
var world_revision: int = -1


static func make(
	slot_index: int,
	slot_generation: int,
	assigned_store_id: StringName = &"",
	assigned_room_instance_id: String = "",
	assigned_world_revision: int = -1
) -> SimEntityHandle:
	var handle := SimEntityHandle.new()
	handle.index = slot_index
	handle.generation = slot_generation
	handle.store_id = assigned_store_id
	handle.room_instance_id = assigned_room_instance_id
	handle.world_revision = assigned_world_revision
	return handle


static func parse(text: String) -> SimEntityHandle:
	var parts := text.strip_edges().split(":")
	if parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int():
		# Legacy diagnostic strings are intentionally unscoped and therefore
		# cannot resolve against a live store. Keep parsing them for callers that
		# only need to display an inert/stale reference.
		return SimEntityHandle.make(int(parts[0]), int(parts[1]))
	if parts.size() != 5:
		return SimEntityHandle.new()
	if not parts[1].is_valid_int() or not parts[2].is_valid_int() or not parts[4].is_valid_int():
		return SimEntityHandle.new()
	return SimEntityHandle.make(
		int(parts[1]),
		int(parts[2]),
		StringName(parts[0]),
		parts[3],
		int(parts[4])
	)


func is_valid() -> bool:
	return index >= 0 and generation >= 1 and has_scope()


func has_scope() -> bool:
	return store_id != &"" and not room_instance_id.strip_edges().is_empty() and world_revision >= 0


func matches_scope(expected_store_id: StringName, expected_room_instance_id: String, expected_world_revision: int) -> bool:
	return (
		has_scope()
		and store_id == expected_store_id
		and room_instance_id == expected_room_instance_id
		and world_revision == expected_world_revision
	)


func matches(slot_index: int, slot_generation: int) -> bool:
	return is_valid() and index == slot_index and generation == slot_generation


func equals_handle(other: Variant) -> bool:
	if other is SimEntityHandle:
		return (
			index == other.index
			and generation == other.generation
			and store_id == other.store_id
			and room_instance_id == other.room_instance_id
			and world_revision == other.world_revision
		)
	return false


func encode() -> String:
	return "%s:%d:%d:%s:%d" % [String(store_id), index, generation, room_instance_id, world_revision]
