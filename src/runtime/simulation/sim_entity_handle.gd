class_name SimEntityHandle
extends RefCounted

## Generational entity handle.
##
## A handle is a stable *reference* to a slot in one room-scoped entity store.
## The slot index enables O(1) lookup; the generation invalidates the handle as
## soon as the slot is reclaimed and reused. Handles never encode gameplay
## meaning and never act as identity: identity is the StableEntityKey.

var index: int = -1
var generation: int = 0


static func make(slot_index: int, slot_generation: int) -> SimEntityHandle:
	var handle := SimEntityHandle.new()
	handle.index = slot_index
	handle.generation = slot_generation
	return handle


static func parse(text: String) -> SimEntityHandle:
	var parts := text.strip_edges().split(":")
	if parts.size() != 2:
		return SimEntityHandle.new()
	if not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return SimEntityHandle.new()
	return SimEntityHandle.make(int(parts[0]), int(parts[1]))


func is_valid() -> bool:
	return index >= 0 and generation >= 1


func matches(slot_index: int, slot_generation: int) -> bool:
	return is_valid() and index == slot_index and generation == slot_generation


func equals_handle(other: Variant) -> bool:
	if other is SimEntityHandle:
		return index == other.index and generation == other.generation
	return false


func encode() -> String:
	return "%d:%d" % [index, generation]
