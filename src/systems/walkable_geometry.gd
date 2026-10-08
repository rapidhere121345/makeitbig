class_name WalkableGeometry
extends RefCounted

const SCHEMA_VERSION: int = 1
const _FIELDS: Array[String] = [
	"schema_version",
	"kind",
	"bounds",
	"center",
	"corridor_half_height",
	"inner_radius",
	"outer_radius",
]
const _KINDS: Array[String] = ["rectangle", "corridor", "ring"]
const _SWALLOWED_DISPLACEMENT: float = 0.01
const _MIN_PROGRESS_FRACTION: float = 0.05
const _RING_DIRECTION_EPSILON: float = 0.001
const _BOUNDARY_EPSILON: float = 0.0000001


static func from_layout(layout_id: String, arena_rect: Rect2, padding: float) -> Dictionary:
	var bounds := arena_rect.grow(-padding)
	var kind := "rectangle" if layout_id == "rectangle_arena" else layout_id
	var corridor_half_height := 0.0
	var inner_radius := 0.0
	var outer_radius := 0.0
	if kind == "corridor":
		corridor_half_height = minf(72.0, bounds.size.y * 0.25)
	elif kind == "ring":
		var radius_basis := minf(bounds.size.x, bounds.size.y)
		inner_radius = radius_basis * 0.20
		outer_radius = radius_basis * 0.43
	return {
		"schema_version": SCHEMA_VERSION,
		"kind": kind,
		"bounds": bounds,
		"center": bounds.get_center(),
		"corridor_half_height": corridor_half_height,
		"inner_radius": inner_radius,
		"outer_radius": outer_radius,
	}


static func normalize(value: Variant) -> Dictionary:
	if not (value is Dictionary):
		return _normalize_failure("invalid_geometry")
	var geometry: Dictionary = value
	if geometry.size() != _FIELDS.size():
		return _normalize_failure("invalid_fields")
	for field: String in _FIELDS:
		if not geometry.has(field):
			return _normalize_failure("invalid_fields")
	if not _valid_schema_version(geometry["schema_version"]):
		return _normalize_failure("invalid_schema_version")
	if not (geometry["kind"] is String or geometry["kind"] is StringName):
		return _normalize_failure("invalid_kind")
	var kind := String(geometry["kind"])
	if kind not in _KINDS:
		return _normalize_failure("invalid_kind")
	if not _valid_rect(geometry["bounds"]):
		return _normalize_failure("invalid_bounds")
	if not _valid_vector(geometry["center"]):
		return _normalize_failure("invalid_center")
	for field: String in ["corridor_half_height", "inner_radius", "outer_radius"]:
		if not _valid_number(geometry[field]):
			return _normalize_failure("invalid_%s" % field)

	var bounds: Rect2 = geometry["bounds"]
	var center: Vector2 = geometry["center"]
	if not center.is_equal_approx(bounds.get_center()):
		return _normalize_failure("invalid_center")
	var corridor_half_height := float(geometry["corridor_half_height"])
	var inner_radius := float(geometry["inner_radius"])
	var outer_radius := float(geometry["outer_radius"])
	match kind:
		"rectangle":
			if not is_zero_approx(corridor_half_height) or not is_zero_approx(inner_radius) or not is_zero_approx(outer_radius):
				return _normalize_failure("invalid_rectangle_parameters")
		"corridor":
			var expected_half_height := minf(72.0, bounds.size.y * 0.25)
			if not is_equal_approx(corridor_half_height, expected_half_height):
				return _normalize_failure("invalid_corridor_parameters")
			if not is_zero_approx(inner_radius) or not is_zero_approx(outer_radius):
				return _normalize_failure("invalid_corridor_parameters")
		"ring":
			var radius_basis := minf(bounds.size.x, bounds.size.y)
			if not is_equal_approx(inner_radius, radius_basis * 0.20) or not is_equal_approx(outer_radius, radius_basis * 0.43):
				return _normalize_failure("invalid_ring_parameters")
			if not is_zero_approx(corridor_half_height):
				return _normalize_failure("invalid_ring_parameters")

	return {
		"ok": true,
		"error": "",
		"value": {
			"schema_version": SCHEMA_VERSION,
			"kind": kind,
			"bounds": bounds,
			"center": Vector2(geometry["center"]),
			"corridor_half_height": corridor_half_height,
			"inner_radius": inner_radius,
			"outer_radius": outer_radius,
		},
	}


static func project(point: Variant, geometry: Variant) -> Dictionary:
	if not _valid_vector(point):
		return _project_failure("invalid_point")
	var normalized := normalize(geometry)
	if not bool(normalized["ok"]):
		return _project_failure(String(normalized["error"]))
	var valid: Dictionary = normalized["value"]
	var bounds: Rect2 = valid["bounds"]
	var position := Vector2(
		clampf((point as Vector2).x, bounds.position.x, bounds.end.x),
		clampf((point as Vector2).y, bounds.position.y, bounds.end.y)
	)
	var kind := String(valid["kind"])
	if kind == "corridor":
		var center: Vector2 = valid["center"]
		var half_height := float(valid["corridor_half_height"])
		position.y = clampf(position.y, center.y - half_height, center.y + half_height)
	elif kind == "ring":
		var center: Vector2 = valid["center"]
		var offset := position - center
		var distance := offset.length()
		var direction := offset.normalized() if distance > _RING_DIRECTION_EPSILON else Vector2.RIGHT
		position = center + direction * clampf(distance, float(valid["inner_radius"]), float(valid["outer_radius"]))
	return {"ok": true, "error": "", "position": position}


static func line_segment_walkable(from_point: Variant, to_point: Variant, geometry: Variant) -> Dictionary:
	if not _valid_vector(from_point):
		return _walkable_failure("invalid_from_point")
	if not _valid_vector(to_point):
		return _walkable_failure("invalid_to_point")
	var normalized := normalize(geometry)
	if not bool(normalized["ok"]):
		return _walkable_failure(String(normalized["error"]))
	var valid: Dictionary = normalized["value"]
	var start := from_point as Vector2
	var finish := to_point as Vector2
	if not _contains_canonical(start, valid) or not _contains_canonical(finish, valid):
		return _walkable_success(false)
	if String(valid["kind"]) != "ring":
		# Rectangle and corridor are convex canonical domains, so contained
		# endpoints imply that the complete segment is contained.
		return _walkable_success(true)

	var center: Vector2 = valid["center"]
	var segment := finish - start
	var length_squared := segment.length_squared()
	var closest := start
	if length_squared > 0.0:
		var parameter := clampf((center - start).dot(segment) / length_squared, 0.0, 1.0)
		closest = start + segment * parameter
	var inner_radius := float(valid["inner_radius"])
	var closest_radius := closest.distance_to(center)
	return _walkable_success(closest_radius + _BOUNDARY_EPSILON >= inner_radius)


static func candidate_directions(desired: Vector2, stable_sign: int) -> Array[Vector2]:
	var result: Array[Vector2] = []
	var base := desired.normalized() if _valid_vector(desired) and not desired.is_zero_approx() else Vector2.ZERO
	var sign := -1.0 if stable_sign < 0 else 1.0
	result.append(base)
	for magnitude: float in [PI / 8.0, PI / 4.0, PI * 3.0 / 8.0, PI / 2.0]:
		result.append(base.rotated(sign * magnitude))
		result.append(base.rotated(-sign * magnitude))
	return result


static func choose_feasible_direction(position: Vector2, desired: Vector2, lookahead: float, geometry: Variant, stable_sign: int) -> Dictionary:
	if not _valid_vector(position):
		return _choice_failure("invalid_position")
	if not _valid_vector(desired):
		return _choice_failure("invalid_desired")
	if not _valid_number(lookahead) or lookahead < 0.0:
		return _choice_failure("invalid_lookahead")
	var normalized := normalize(geometry)
	if not bool(normalized["ok"]):
		return _choice_failure(String(normalized["error"]))

	var directions := candidate_directions(desired, stable_sign)
	var direct_result := project(position + directions[0] * lookahead, normalized["value"])
	var direct_position: Vector2 = direct_result["position"]
	var direct_displacement := position.distance_to(direct_position)
	if _has_meaningful_progress(direct_displacement, lookahead):
		return _choice_success(directions[0], direct_position, direct_displacement, false)

	for index in range(1, directions.size()):
		var projected := project(position + directions[index] * lookahead, normalized["value"])
		var projected_position: Vector2 = projected["position"]
		var displacement := position.distance_to(projected_position)
		if _has_meaningful_progress(displacement, lookahead):
			return _choice_success(directions[index], projected_position, displacement, true)
	return _choice_success(directions[0], direct_position, direct_displacement, false)


static func _has_meaningful_progress(displacement: float, lookahead: float) -> bool:
	return displacement > maxf(_SWALLOWED_DISPLACEMENT, lookahead * _MIN_PROGRESS_FRACTION)


static func _normalize_failure(error: String) -> Dictionary:
	return {"ok": false, "error": error, "value": {}}


static func _project_failure(error: String) -> Dictionary:
	return {"ok": false, "error": error, "position": Vector2.ZERO}


static func _walkable_failure(error: String) -> Dictionary:
	return {"ok": false, "error": error, "walkable": false}


static func _walkable_success(walkable: bool) -> Dictionary:
	return {"ok": true, "error": "", "walkable": walkable}


static func _choice_failure(error: String) -> Dictionary:
	return {
		"ok": false,
		"error": error,
		"direction": Vector2.ZERO,
		"projected_position": Vector2.ZERO,
		"actual_displacement": 0.0,
		"detour": false,
	}


static func _choice_success(direction: Vector2, projected_position: Vector2, actual_displacement: float, detour: bool) -> Dictionary:
	return {
		"ok": true,
		"error": "",
		"direction": direction,
		"projected_position": projected_position,
		"actual_displacement": actual_displacement,
		"detour": detour,
	}


static func _valid_schema_version(value: Variant) -> bool:
	return value is int and not (value is bool) and int(value) == SCHEMA_VERSION


static func _valid_vector(value: Variant) -> bool:
	return value is Vector2 and is_finite((value as Vector2).x) and is_finite((value as Vector2).y)


static func _valid_rect(value: Variant) -> bool:
	return value is Rect2 and _valid_vector((value as Rect2).position) and _valid_vector((value as Rect2).size) and _valid_vector((value as Rect2).end) and (value as Rect2).size.x > 0.0 and (value as Rect2).size.y > 0.0


static func _valid_number(value: Variant) -> bool:
	return (value is int or value is float) and not (value is bool) and is_finite(float(value))


static func _contains_canonical(point: Vector2, geometry: Dictionary) -> bool:
	var bounds: Rect2 = geometry["bounds"]
	if point.x < bounds.position.x or point.x > bounds.end.x or point.y < bounds.position.y or point.y > bounds.end.y:
		return false
	match String(geometry["kind"]):
		"corridor":
			var center: Vector2 = geometry["center"]
			return absf(point.y - center.y) <= float(geometry["corridor_half_height"])
		"ring":
			var center: Vector2 = geometry["center"]
			var radius := point.distance_to(center)
			var inner_radius := float(geometry["inner_radius"])
			var outer_radius := float(geometry["outer_radius"])
			var inside_inner := radius + _BOUNDARY_EPSILON < inner_radius
			var outside_outer := radius - _BOUNDARY_EPSILON > outer_radius
			return not inside_inner and not outside_outer
	return true
