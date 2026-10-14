class_name GeometryQuery
extends RefCounted

## Deterministic, data-only queries for static two-dimensional blockers.
##
## A blocker is one of:
##   {"id": String, "kind": "rect", "rect": Rect2}
##   {"id": String, "kind": "circle", "center": Vector2, "radius": float}
##   {"id": String, "kind": "polygon", "points": PackedVector2Array}
##
## Rectangles are stored with a counter-clockwise polygon representation as
## well.  That lets the circle sweep use rounded rectangle corners instead of
## a square expansion.  The query owns no Nodes and never consults instance
## ids, scene order, or rendering state.

const EPSILON := 0.000001
## Distance tolerance absorbs the sub-pixel rounding introduced when authored
## UV vertices are scaled into world pixels.  It classifies a contact only;
## it never moves an actor or widens a shape.
const DISTANCE_EPSILON := 0.0001
## TOI tolerance is expressed in normalized sweep time and is kept separate
## from geometric distance classification.
const TOI_EPSILON := 0.000001
## Discriminants are in squared-distance units.  This relative tolerance keeps
## near tangents stable for both short and long sweeps without changing the
## distance tolerance used by position queries.
const DISCRIMINANT_EPSILON := 0.0000001
## A projected tangent can retain a few representable ulps in its inward
## component.  This is a directional comparison tolerance, not a clearance.
const DIRECTION_EPSILON := 0.00001
## Compatibility names retained for existing consumers of the pure query API.
const CONTACT_EPSILON := DISTANCE_EPSILON
const TIME_EPSILON := TOI_EPSILON
const MIN_SHAPE_SIZE := 0.000001

var _blockers: Dictionary = {}


func _init(initial_blockers: Array = []) -> void:
	for value: Variant in initial_blockers:
		if value is Dictionary:
			register(value)


## Registers or replaces a blocker by its stable id.
##
## Both register({"id": ..., ...}) and register(id, {"kind": ..., ...}) are
## accepted so callers can keep authored ids separate from shape data.
func register(blocker_or_id: Variant, shape: Variant = null) -> bool:
	var raw: Dictionary = {}
	if blocker_or_id is Dictionary:
		raw = (blocker_or_id as Dictionary).duplicate(true)
	elif shape is Dictionary:
		raw = (shape as Dictionary).duplicate(true)
		raw["id"] = String(blocker_or_id).strip_edges()
	else:
		return false

	var normalized := _normalize_blocker(raw)
	if normalized.is_empty():
		return false
	_blockers[String(normalized["id"])] = normalized
	return true


func register_rect(blocker_id: String, rect: Variant) -> bool:
	return register({"id": blocker_id, "kind": "rect", "rect": rect})


func register_circle(blocker_id: String, center: Variant, radius: float) -> bool:
	return register({"id": blocker_id, "kind": "circle", "center": center, "radius": radius})


func register_polygon(blocker_id: String, points: Variant) -> bool:
	return register({"id": blocker_id, "kind": "polygon", "points": points})


func unregister(blocker_id: String) -> bool:
	if not _blockers.has(blocker_id):
		return false
	_blockers.erase(blocker_id)
	return true


func remove(blocker_id: String) -> bool:
	return unregister(blocker_id)


func clear() -> void:
	_blockers.clear()


func blocker_ids() -> Array[String]:
	var ids: Array[String] = []
	for key: Variant in _blockers.keys():
		ids.append(String(key))
	ids.sort()
	return ids


## Returns a deep copy in stable blocker-id order.
func snapshot() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for blocker_id: String in blocker_ids():
		result.append((_blockers[blocker_id] as Dictionary).duplicate(true))
	return result


func is_position_clear(position: Vector2, radius: float = 0.0) -> bool:
	if not _valid_vector(position) or not _valid_radius(radius):
		return false
	for blocker_id: String in blocker_ids():
		var state := _shape_state(position, _blockers[blocker_id] as Dictionary, radius)
		if bool(state.get("penetrating", false)):
			return false
	return true


## Returns the first contact(s) for each blocker in [0, 1].  A touching start
## is returned at time zero even when motion is leaving it; ActorMotor decides
## whether that contact blocks this particular motion.
func sweep(start: Vector2, displacement: Vector2, radius: float = 0.0) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not _valid_vector(start) or not _valid_vector(displacement) or not _valid_radius(radius):
		return result
	for blocker_id: String in blocker_ids():
		var blocker: Dictionary = _blockers[blocker_id]
		var candidates := _sweep_shape(start, displacement, blocker, radius)
		for candidate: Dictionary in candidates:
			result.append(candidate)
	_sort_hits(result)
	return result


## Public stable ordering helper used when a motor adds world-bound contacts.
static func sort_hits(hits: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = hits.duplicate(true)
	result.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return _stable_hit_less(left, right)
	)
	return result


static func _stable_hit_less(left: Dictionary, right: Dictionary) -> bool:
	var left_id := String(left.get("blocker_id", left.get("id", "")))
	var right_id := String(right.get("blocker_id", right.get("id", "")))
	if left_id != right_id:
		return left_id < right_id
	var left_time := float(left.get("time", 0.0))
	var right_time := float(right.get("time", 0.0))
	if left_time != right_time:
		return left_time < right_time
	var left_shape := String(left.get("shape_key", left.get("feature_key", "")))
	var right_shape := String(right.get("shape_key", right.get("feature_key", "")))
	if left_shape != right_shape:
		return left_shape < right_shape
	var left_normal := _normal_key(left.get("normal", Vector2.ZERO))
	var right_normal := _normal_key(right.get("normal", Vector2.ZERO))
	if left_normal != right_normal:
		return left_normal < right_normal
	return String(left.get("feature_key", "")) < String(right.get("feature_key", ""))


static func _normal_key(value: Variant) -> String:
	if not value is Vector2:
		return ""
	var normal: Vector2 = value
	return "%+.9f|%+.9f" % [normal.x, normal.y]


func _sort_hits(hits: Array[Dictionary]) -> void:
	hits.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return _stable_hit_less(left, right)
	)


func _normalize_blocker(source: Dictionary) -> Dictionary:
	var blocker_id := String(source.get("id", "")).strip_edges()
	if blocker_id.is_empty():
		return {}
	var kind := String(source.get("kind", "")).strip_edges().to_lower()
	match kind:
		"rect":
			var rect_value: Variant = source.get("rect", null)
			var rect := _rect_from(rect_value)
			if not rect.position.is_finite() or not rect.size.is_finite() or rect.size.x <= MIN_SHAPE_SIZE or rect.size.y <= MIN_SHAPE_SIZE:
				return {}
			var points := _rect_points(rect)
			return {
				"id": blocker_id,
				"kind": "rect",
				"rect": rect,
				"points": points,
				"shape_key": _rect_key(rect),
			}
		"circle":
			var center_value: Variant = source.get("center", null)
			var center := _vector_from(center_value)
			var radius_value: Variant = source.get("radius", null)
			if not _finite_number(radius_value):
				return {}
			var circle_radius := float(radius_value)
			if not center.is_finite() or circle_radius <= MIN_SHAPE_SIZE:
				return {}
			return {
				"id": blocker_id,
				"kind": "circle",
				"center": center,
				"radius": circle_radius,
				"shape_key": "circle|%s|%s|%s" % [_number_key(center.x), _number_key(center.y), _number_key(circle_radius)],
			}
		"polygon", "convex_polygon":
			var points := _points_from(source.get("points", null))
			if not _valid_convex_polygon(points):
				return {}
			if _polygon_area(points) < 0.0:
				points = _reversed_points(points)
			return {
				"id": blocker_id,
				"kind": "polygon",
				"points": points,
				"shape_key": _polygon_key(points),
			}
	return {}


func _rect_from(value: Variant) -> Rect2:
	if value is Rect2:
		return _normalized_rect(value)
	if value is Array:
		var values: Array = value
		if values.size() >= 4 and _finite_number(values[0]) and _finite_number(values[1]) and _finite_number(values[2]) and _finite_number(values[3]):
			return _normalized_rect(Rect2(float(values[0]), float(values[1]), float(values[2]), float(values[3])))
	return Rect2()


func _normalized_rect(value: Rect2) -> Rect2:
	var position := value.position
	var size := value.size
	if size.x < 0.0:
		position.x += size.x
		size.x = -size.x
	if size.y < 0.0:
		position.y += size.y
		size.y = -size.y
	return Rect2(position, size)


func _vector_from(value: Variant) -> Vector2:
	if value is Vector2:
		return value
	if value is Array:
		var values: Array = value
		if values.size() >= 2 and _finite_number(values[0]) and _finite_number(values[1]):
			return Vector2(float(values[0]), float(values[1]))
	return Vector2(INF, INF)


func _points_from(value: Variant) -> PackedVector2Array:
	var result := PackedVector2Array()
	if value is PackedVector2Array:
		return value
	if not value is Array:
		return result
	for point_value: Variant in value as Array:
		var point := _vector_from(point_value)
		if not point.is_finite():
			return PackedVector2Array()
		result.append(point)
	return result


func _valid_convex_polygon(points: PackedVector2Array) -> bool:
	if points.size() < 3:
		return false
	var orientation := 0.0
	var area := 0.0
	for index in points.size():
		if not points[index].is_finite():
			return false
		var edge := points[(index + 1) % points.size()] - points[index]
		if edge.length_squared() <= MIN_SHAPE_SIZE * MIN_SHAPE_SIZE:
			return false
		var next_edge := points[(index + 2) % points.size()] - points[(index + 1) % points.size()]
		var cross := edge.cross(next_edge)
		area += points[index].cross(points[(index + 1) % points.size()])
		if absf(cross) <= EPSILON:
			continue
		if orientation == 0.0:
			orientation = signf(cross)
		elif signf(cross) != signf(orientation):
			return false
	return orientation != 0.0 and absf(area) > EPSILON


func _rect_points(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([
		rect.position,
		Vector2(rect.end.x, rect.position.y),
		rect.end,
		Vector2(rect.position.x, rect.end.y),
	])


func _polygon_area(points: PackedVector2Array) -> float:
	var area := 0.0
	for index in points.size():
		area += points[index].cross(points[(index + 1) % points.size()])
	return area * 0.5


func _reversed_points(points: PackedVector2Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for index in range(points.size() - 1, -1, -1):
		result.append(points[index])
	return result


func _shape_state(point: Vector2, blocker: Dictionary, footprint_radius: float) -> Dictionary:
	if String(blocker.get("kind", "")) == "circle":
		var center: Vector2 = blocker["center"]
		var distance := point.distance_to(center)
		var combined_radius := float(blocker["radius"]) + footprint_radius
		var normal := (point - center).normalized()
		if normal.length_squared() <= EPSILON * EPSILON:
			normal = Vector2.RIGHT
		var penetrating := distance < combined_radius - DISTANCE_EPSILON
		return {
			"distance": distance,
			"normal": normal,
			"inside": distance < combined_radius - DISTANCE_EPSILON,
			"boundary": absf(distance - combined_radius) <= DISTANCE_EPSILON,
			"penetrating": penetrating,
		}
	return _polygon_state(point, blocker["points"], footprint_radius)


func _polygon_state(point: Vector2, points: PackedVector2Array, footprint_radius: float) -> Dictionary:
	var inside := true
	var boundary := false
	var closest := points[0]
	var closest_edge := 0
	var closest_distance_squared := INF
	var closest_outward := Vector2.RIGHT
	var closest_along := 0.0
	for index in points.size():
		var a: Vector2 = points[index]
		var b: Vector2 = points[(index + 1) % points.size()]
		var edge := b - a
		var edge_length := edge.length()
		var outward := Vector2(edge.y, -edge.x) / edge_length
		var signed_side := (point - a).dot(outward)
		if signed_side > DISTANCE_EPSILON:
			inside = false
		if absf(signed_side) <= DISTANCE_EPSILON:
			boundary = true
		var along := clampf((point - a).dot(edge) / edge.length_squared(), 0.0, 1.0)
		var candidate := a + edge * along
		var distance_squared := point.distance_squared_to(candidate)
		if distance_squared < closest_distance_squared - EPSILON:
			closest_distance_squared = distance_squared
			closest = candidate
			closest_edge = index
			closest_outward = outward
			closest_along = along

	var distance := sqrt(maxf(0.0, closest_distance_squared))
	var normal := point - closest
	if closest_along > DISTANCE_EPSILON and closest_along < 1.0 - DISTANCE_EPSILON:
		# Face contacts use the exact authored edge normal.  Reconstructing it
		# from a nearly tangent point would accumulate a tiny sideways component
		# over many fixed ticks.
		normal = closest_outward
	elif normal.length_squared() > EPSILON * EPSILON:
		normal = normal.normalized()
	else:
		normal = closest_outward
	if inside:
		# For a point inside the polygon, the closest edge's outward normal is
		# the only stable direction available.  It is deliberately not used to
		# relocate the point.
		normal = closest_outward
	var penetrating := (inside and not boundary) or distance < footprint_radius - DISTANCE_EPSILON
	return {
		"distance": distance,
		"normal": normal,
		"inside": inside,
		"boundary": boundary,
		"edge": closest_edge,
		"closest": closest,
		"penetrating": penetrating,
	}


func _sweep_shape(start: Vector2, motion: Vector2, blocker: Dictionary, footprint_radius: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var state := _shape_state(start, blocker, footprint_radius)
	var distance := float(state.get("distance", INF))
	var normal: Vector2 = state.get("normal", Vector2.RIGHT)
	var is_initial := bool(state.get("inside", false)) or bool(state.get("penetrating", false))
	if String(blocker.get("kind", "")) == "polygon":
		is_initial = is_initial or distance <= footprint_radius + DISTANCE_EPSILON
	else:
		is_initial = is_initial or distance <= float(blocker.get("radius", 0.0)) + footprint_radius + DISTANCE_EPSILON
	var touching_start := is_initial and not bool(state.get("penetrating", false))
	if is_initial:
		result.append(_make_hit(blocker, start, 0.0, normal, true, bool(state.get("penetrating", false)), "start"))
		# A penetrating start has no trustworthy swept path.  A merely touching
		# start does: keep the t=0 contact for the motor, but also search the
		# rounded vertex/edge continuation.  Returning only the t=0 face contact
		# makes a tangent slide jump inside a polygon's Minkowski corner on the
		# next tick.
		if not touching_start:
			return result

	var candidates: Array[Dictionary] = []
	if String(blocker.get("kind", "")) == "circle":
		var circle_center: Vector2 = blocker["center"]
		var circle_radius := float(blocker["radius"]) + footprint_radius
		var circle_time := _sweep_point_circle(start, motion, circle_center, circle_radius)
		if not circle_time.is_empty():
			var contact: Vector2 = circle_time["position"]
			var circle_normal: Vector2 = (contact - circle_center).normalized()
			if circle_normal.length_squared() <= EPSILON * EPSILON:
				circle_normal = Vector2.RIGHT
			candidates.append(_make_hit(blocker, contact, float(circle_time["time"]), circle_normal, false, false, "circle"))
	else:
		var points: PackedVector2Array = blocker["points"]
		for index in points.size():
			var a: Vector2 = points[index]
			var b: Vector2 = points[(index + 1) % points.size()]
			var edge := b - a
			var edge_length := edge.length()
			var tangent := edge / edge_length
			var outward := Vector2(edge.y, -edge.x) / edge_length
			var speed := motion.dot(outward)
			if speed < -EPSILON:
				var signed_side := (start - a).dot(outward)
				var time := (footprint_radius - signed_side) / speed
				if time >= -TOI_EPSILON and time <= 1.0 + TOI_EPSILON:
					var clamped_time := clampf(time, 0.0, 1.0)
					var contact := start + motion * clamped_time
					var along := (contact - a).dot(tangent)
					if along >= -DISTANCE_EPSILON and along <= edge_length + DISTANCE_EPSILON:
						var contact_state := _polygon_state(contact, points, footprint_radius)
						if _is_boundary_contact(contact_state, footprint_radius):
							candidates.append(_make_hit(blocker, contact, clamped_time, contact_state["normal"], false, false, "edge_%04d" % index))

		for index in points.size():
			var vertex: Vector2 = points[index]
			var circle_time := _sweep_point_circle(start, motion, vertex, footprint_radius)
			if circle_time.is_empty():
				continue
			var contact_time := float(circle_time["time"])
			var contact: Vector2 = circle_time["position"]
			var contact_state := _polygon_state(contact, points, footprint_radius)
			if not _is_boundary_contact(contact_state, footprint_radius):
				# Vector2 stores the represented point in real_t precision.  At a
				# long, shallow sweep that representation can land just beyond the
				# distance tolerance even though the scalar root is valid.  Find the
				# latest time which the same position query accepts; this is a TOI
				# backoff derived from the query, never a normal nudge.
				contact_time = _validated_point_circle_time(start, motion, vertex, footprint_radius, contact_time)
				contact = start + motion * contact_time
				contact_state = _polygon_state(contact, points, footprint_radius)
			if not _is_boundary_contact(contact_state, footprint_radius):
				continue
			candidates.append(_make_hit(blocker, contact, contact_time, contact_state["normal"], false, false, "vertex_%04d" % index))

	if candidates.is_empty():
		return result
	_sort_hits(candidates)
	var first_time := float(candidates[0].get("time", 1.0))
	if touching_start:
		first_time = INF
		for candidate: Dictionary in candidates:
			var candidate_time := float(candidate.get("time", 1.0))
			if candidate_time > TOI_EPSILON:
				first_time = candidate_time
				break
		if is_inf(first_time):
			return result
	for candidate: Dictionary in candidates:
		if absf(float(candidate.get("time", 1.0)) - first_time) <= TOI_EPSILON:
			result.append(candidate)
	return result


func _sweep_point_circle(start: Vector2, motion: Vector2, center: Vector2, radius: float) -> Dictionary:
	var motion_x := float(motion.x)
	var motion_y := float(motion.y)
	var a := motion_x * motion_x + motion_y * motion_y
	if a <= EPSILON * EPSILON:
		return {}
	var offset_x := float(start.x) - float(center.x)
	var offset_y := float(start.y) - float(center.y)
	var b := offset_x * motion_x + offset_y * motion_y
	var c := offset_x * offset_x + offset_y * offset_y - radius * radius
	var discriminant := b * b - a * c
	var discriminant_scale := maxf(1.0, maxf(absf(b * b), absf(a * c)))
	var discriminant_tolerance := DISCRIMINANT_EPSILON * discriminant_scale
	if discriminant < -discriminant_tolerance:
		return {}
	var root := sqrt(maxf(0.0, discriminant))
	var time := (-b - root) / a
	if time < -TOI_EPSILON or time > 1.0 + TOI_EPSILON:
		return {}
	var clamped_time := clampf(time, 0.0, 1.0)
	return {"time": clamped_time, "position": start + motion * clamped_time}


func _validated_point_circle_time(start: Vector2, motion: Vector2, center: Vector2, radius: float, time: float) -> float:
	var candidate := start + motion * time
	if candidate.distance_to(center) >= radius - DISTANCE_EPSILON:
		return time
	var lower := 0.0
	var upper := time
	for _pass in 12:
		var middle := (lower + upper) * 0.5
		var point := start + motion * middle
		if point.distance_to(center) >= radius - DISTANCE_EPSILON:
			lower = middle
		else:
			upper = middle
	return lower


func _is_boundary_contact(state: Dictionary, radius: float) -> bool:
	if bool(state.get("inside", false)) and not bool(state.get("boundary", false)):
		return false
	return absf(float(state.get("distance", INF)) - radius) <= DISTANCE_EPSILON


func _make_hit(blocker: Dictionary, position: Vector2, time: float, normal: Vector2, initial: bool, penetrating: bool, feature_key: String) -> Dictionary:
	var safe_normal := normal.normalized()
	if safe_normal.length_squared() <= EPSILON * EPSILON:
		safe_normal = Vector2.RIGHT
	return {
		"id": String(blocker.get("id", "")),
		"blocker_id": String(blocker.get("id", "")),
		"kind": String(blocker.get("kind", "")),
		"time": clampf(time, 0.0, 1.0),
		"position": position,
		"normal": safe_normal,
		"initial": initial,
		"penetrating": penetrating,
		"shape_key": String(blocker.get("shape_key", "")),
		"feature_key": feature_key,
	}


func _rect_key(rect: Rect2) -> String:
	return "rect|%s|%s|%s|%s" % [_number_key(rect.position.x), _number_key(rect.position.y), _number_key(rect.size.x), _number_key(rect.size.y)]


func _polygon_key(points: PackedVector2Array) -> String:
	var values: Array[String] = []
	for point: Vector2 in points:
		values.append("%s,%s" % [_number_key(point.x), _number_key(point.y)])
	return "polygon|" + ";".join(values)


func _number_key(value: float) -> String:
	return String.num(value, 9)


func _valid_vector(value: Vector2) -> bool:
	return value.is_finite()


func _valid_radius(value: float) -> bool:
	return is_finite(value) and value >= 0.0


func _finite_number(value: Variant) -> bool:
	return (value is int or value is float) and not (value is bool) and is_finite(float(value))
