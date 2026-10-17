class_name SimStructuralChangeBuffer
extends RefCounted

## Ordered deferred structural changes, drained by the structural commit phase.
##
## Order contract: insertion order. Spawn records receive ascending stable keys
## exactly in the order changes were enqueued during the tick.

var _changes: Array[SimStructuralChange] = []


func enqueue(change: SimStructuralChange) -> void:
	if change != null:
		_changes.append(change)


func drain() -> Array[SimStructuralChange]:
	var drained := _changes
	_changes = []
	return drained


func pending_count() -> int:
	return _changes.size()


func clear() -> void:
	_changes.clear()
