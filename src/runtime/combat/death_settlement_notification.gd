class_name DeathSettlementNotification
extends RefCounted

## Typed structural fact emitted by DeathSettlement for RoomEncounter.
##
## The notification crosses the fixed-tick death boundary as a detached record.
## It carries no callback, node, store, or live domain reference.

var tick := -1
var room_id := ""
var world_revision := -1
var entity_key := ""
var spawn_key := ""


func is_valid() -> bool:
	return (
		tick >= 0
		and world_revision >= 0
		and _valid_id(room_id)
		and _valid_id(entity_key)
		and (spawn_key.is_empty() or _valid_id(spawn_key))
	)


func snapshot() -> Dictionary:
	return {
		"tick": tick,
		"room_id": room_id,
		"world_revision": world_revision,
		"entity_key": entity_key,
		"spawn_key": spawn_key,
	}


static func _valid_id(value: String) -> bool:
	return not value.is_empty() and value == value.strip_edges() and not value.contains(" ")
