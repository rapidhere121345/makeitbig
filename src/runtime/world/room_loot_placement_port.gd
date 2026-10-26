class_name RoomLootPlacementPort
extends RefCounted

## Room-scoped placement authority for CombatRoomLoot.
##
## Loot asks this port before materializing an authored drop.  The port owns
## the room's movement/spatial truth; loot never reads SceneTree geometry or
## invents a second placement rule.


func is_position_clear(_position: Vector2, _radius: float) -> bool:
	# The base port fails closed.  A mounted room must bind a concrete adapter.
	return false


func resolve_drop_position(position: Vector2, radius: float) -> Variant:
	return position if is_position_clear(position, radius) else null
