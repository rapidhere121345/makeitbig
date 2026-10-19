class_name MainLootPlacementPort
extends "res://src/runtime/world/room_loot_placement_port.gd"

## Composition adapter from the mounted room's spatial authority to the loot
## domain.  It exposes one typed capability and does not own placement state.

var _room: Variant = null


func configure(room: Variant) -> Dictionary:
	if room == null or not room.has_method("is_position_clear"):
		_room = null
		return {"ok": false, "error": "loot_placement_room_unavailable"}
	_room = room
	return {"ok": true, "error": ""}


func is_position_clear(position: Vector2, radius: float) -> bool:
	if _room == null or not position.is_finite() or not is_finite(radius) or radius <= 0.0:
		return false
	return bool(_room.is_position_clear(position, radius))
