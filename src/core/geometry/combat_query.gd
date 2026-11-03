class_name CombatQuery
extends RefCounted

## Pure combat-space queries.
##
## These operations deliberately do not know about actors, damage, movement or
## navigation. Callers provide the already-resolved world shapes and consume
## the result in their own authority phase.


static func shape_contains(shape: Dictionary, point: Vector2) -> bool:
	if not point.is_finite() or shape.is_empty():
		return false
	match String(shape.get("type", "")):
		"circle":
			var origin: Variant = shape.get("origin", null)
			if not _valid_number(shape.get("radius", null)):
				return false
			var radius := float(shape["radius"])
			return origin is Vector2 and (origin as Vector2).is_finite() and is_finite(radius) and radius >= 0.0 \
				and point.distance_squared_to(origin as Vector2) <= radius * radius
		"rect":
			var rect: Variant = shape.get("rect", Rect2())
			return _valid_rect(rect) and (rect as Rect2).has_point(point)
		"fan":
			if not _valid_number(shape.get("half_angle", null)) or not _valid_number(shape.get("radius", null)):
				return false
			return fan_contains(point, shape.get("origin", null), shape.get("direction", null), float(shape["half_angle"]), float(shape["radius"]))
		"lane":
			if not _valid_number(shape.get("length", null)) or not _valid_number(shape.get("width", null)):
				return false
			return lane_contains(point, shape.get("origin", null), shape.get("direction", null), float(shape["length"]), float(shape["width"]))
	return false


static func lane_contains(point: Vector2, origin: Variant, direction: Variant, length: float, width: float) -> bool:
	if not point.is_finite() or not origin is Vector2 or not direction is Vector2:
		return false
	var start := origin as Vector2
	var axis := direction as Vector2
	if not start.is_finite() or not axis.is_finite() or axis.length_squared() <= 0.000001:
		return false
	if not is_finite(length) or not is_finite(width) or length < 0.0 or width < 0.0:
		return false
	axis = axis.normalized()
	var local := point - start
	var forward := local.dot(axis)
	return forward >= 0.0 and forward <= length and absf(local.dot(axis.rotated(PI * 0.5))) <= width * 0.5


static func fan_contains(point: Vector2, origin: Variant, direction: Variant, half_angle: float, radius: float) -> bool:
	if not point.is_finite() or not origin is Vector2 or not direction is Vector2:
		return false
	var start := origin as Vector2
	var axis := direction as Vector2
	if not start.is_finite() or not axis.is_finite() or axis.length_squared() <= 0.000001:
		return false
	if not is_finite(half_angle) or not is_finite(radius) or half_angle < 0.0 or half_angle > PI or radius < 0.0:
		return false
	var offset := point - start
	return offset.length() <= radius and (offset == Vector2.ZERO or absf(axis.normalized().angle_to(offset.normalized())) <= half_angle)


static func distance_to_segment(point: Vector2, start: Vector2, finish: Vector2) -> float:
	if not point.is_finite() or not start.is_finite() or not finish.is_finite():
		return INF
	var segment := finish - start
	if segment.length_squared() <= 0.000001:
		return point.distance_to(start)
	var fraction := clampf((point - start).dot(segment) / segment.length_squared(), 0.0, 1.0)
	return point.distance_to(start + segment * fraction)


## Returns the first contact point between a swept point segment and a circle.
## A zero-length segment still detects an initial overlap explicitly.
static func swept_circle_contact(start: Vector2, finish: Vector2, center: Vector2, radius: float) -> Variant:
	if not start.is_finite() or not finish.is_finite() or not center.is_finite() or not is_finite(radius) or radius < 0.0:
		return null
	var segment := finish - start
	var segment_length := segment.length()
	if segment_length <= 0.0:
		return start if start.distance_squared_to(center) <= radius * radius else null
	var axis := segment / segment_length
	var relative := center - start
	var projection := relative.dot(axis)
	var perpendicular_squared := relative.length_squared() - projection * projection
	var radius_squared := radius * radius
	if perpendicular_squared > radius_squared:
		return null
	var reach := sqrt(maxf(0.0, radius_squared - perpendicular_squared))
	var contact_distance := projection - reach
	var exit_distance := projection + reach
	if exit_distance < 0.0 or contact_distance > segment_length:
		return null
	return start + axis * clampf(contact_distance, 0.0, segment_length)


static func _valid_rect(value: Variant) -> bool:
	if not value is Rect2:
		return false
	var rect: Rect2 = value
	return rect.position.is_finite() and rect.size.is_finite() and rect.size.x >= 0.0 and rect.size.y >= 0.0


static func _valid_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))


## Pure incoming-hurtbox query. Validate the entire snapshot before publishing
## any candidates, including closed/broken parts. Unsupported shapes fail closed.
## Sort by first contact distance, then stable part ID for coincident contacts.
static func swept_parts(start: Vector2, finish: Vector2, target_entity_id: int, target_position: Vector2, parts: Array[Dictionary]) -> Dictionary:
	if target_entity_id <= 0 or not target_position.is_finite() or not start.is_finite() or not finish.is_finite():
		return {"ok": false, "error": "invalid_part_sweep", "candidates": []}
	if parts.is_empty():
		return {"ok": false, "error": "missing_hurtbox_parts", "candidates": []}
	var seen: Dictionary = {}
	for part: Dictionary in parts:
		var part_id := String(part.get("part_id", ""))
		var error := ""
		if part_id.is_empty() or seen.has(part_id) or String(part.get("damage_group_id", "")).is_empty():
			error = "invalid_part_identity"
		elif not part.get("pose") is Vector2 or not (part.pose as Vector2).is_finite():
			error = "invalid_part_pose"
		elif not part.get("active") is bool or not part.get("broken") is bool:
			error = "invalid_part_state"
		elif not part.get("hurtbox") is Dictionary or (part.hurtbox as Dictionary).is_empty():
			error = "missing_hurtbox_shape"
		else:
			var shape: Dictionary = part.hurtbox
			if String(shape.get("type", "")) != "circle":
				error = "unsupported_hurtbox_shape"
			elif not _valid_number(shape.get("radius")) or float(shape.radius) <= 0.0:
				error = "invalid_hurtbox_radius"
		if not error.is_empty():
			return {"ok": false, "error": error, "part_id": part_id, "candidates": []}
		seen[part_id] = true
	var candidates: Array[Dictionary] = []
	for part: Dictionary in parts:
		if not bool(part.active) or bool(part.broken):
			continue
		var contact: Variant = swept_circle_contact(start, finish, target_position + (part.pose as Vector2), float(part.hurtbox.radius))
		if contact == null:
			continue
		candidates.append({
			"target_entity_id": target_entity_id, "part_id": String(part.part_id),
			"damage_group_id": String(part.damage_group_id), "contact_point": contact,
			"distance_squared": start.distance_squared_to(contact as Vector2),
		})
	candidates.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		if float(left.distance_squared) != float(right.distance_squared):
			return float(left.distance_squared) < float(right.distance_squared)
		return String(left.part_id) < String(right.part_id)
	)
	return {"ok": true, "error": "", "candidates": candidates}
