class_name MainLootPlacementPort
extends "res://src/runtime/world/room_loot_placement_port.gd"

## Composition adapter from the mounted room's spatial authority to the loot
## domain. It queries the same spatial authority for nearby drop placement.

const COLLECTOR_RADIUS := 14.0
const MAX_DROP_SHIFT := 64

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


func resolve_drop_position(position: Vector2, radius: float) -> Variant:
	if not position.is_finite() or not is_finite(radius) or radius <= 0.0:
		return null
	if is_position_clear(position, radius):
		return position
	# A legal death beside a wall may lack the larger pickup clearance. Move
	# that drop slightly onto reachable floor; never rescue an invalid origin.
	if not is_position_clear(position, COLLECTOR_RADIUS):
		return null
	for distance in range(4, MAX_DROP_SHIFT + 1, 4):
		for direction in 16:
			var candidate := position + Vector2.RIGHT.rotated(TAU * float(direction) / 16.0) * float(distance)
			if not is_position_clear(candidate, radius):
				continue
			var connected := true
			# One unit of extra clearance bounds the gaps between 2-unit samples.
			# The first segment starts at the already validated death position.
			for step in range(1, distance / 2 + 1):
				var sample := position.lerp(candidate, float(step * 2) / float(distance))
				if not is_position_clear(sample, COLLECTOR_RADIUS + 1.0):
					connected = false
					break
			if connected:
				return candidate
	return null
