class_name SimEntitySlot
extends RefCounted

## One storage slot in a room-scoped entity store.
##
## The slot owns identity bookkeeping (generation + stable key) so records stay
## pure gameplay state. "tombstone" marks a despawned-or-dead entity whose
## storage is reclaimed only by the structural commit phase; "record" is null
## exactly while the slot is free.

var generation: int = 0
var stable_key: int = 0
var tombstone: bool = false
var record: Variant = null


func occupied() -> bool:
	return record != null


func is_live() -> bool:
	return occupied() and not tombstone
