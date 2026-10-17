class_name SpatialSweep
extends RefCounted

## Analytic continuous sweeps for circular bodies.
##
## Every function is pure and returns raw hit dictionaries with the fields
## toi, point, normal, feature, penetrating and initial.  toi is normalized to
## the requested displacement and clamped to [0, 1].  Normals are unit push-out
## vectors pointing from the contacted feature toward the sweeping body.
## Contact points lie on the contacted feature.  Callers classify blocking;
## this kernel only reports geometry.

const Shape := preload("res://src/runtime/geometry/spatial_shape.gd")


## Earliest contact between a moving circle and a point obstacle.
static func sweep_circle_point(
	start: Vector2,
	displacement: Vector2,
	radius: float,
	point: Vector2,
	feature: String
) -> Dictionary:
	return sweep_circle_circle(start, displacement, radius, point, 0.0, feature, false)


## Earliest entering contact between a moving circle approaching a circle
## obstacle from the outside.  Deep starts report a penetrating contact at
## time zero; exact touching reports an initial contact.
static func sweep_circle_circle(
	start: Vector2,
	displacement: Vector2,
	radius: float,
	center: Vector2,
	obstacle_radius: float,
	feature: String,
	normal_flip: bool
) -> Dictionary:
	var empty := {}
	if not (start.is_finite() and displacement.is_finite() and center.is_finite()):
		return empty
	if not is_finite(radius) or not is_finite(obstacle_radius) or radius < 0.0 or obstacle_radius < 0.0:
		return empty
	var combined := radius + obstacle_radius
	var offset := start - center
	var distance := offset.length()
	if distance < combined - Shape.DISTANCE_EPSILON:
		var normal := offset.normalized() if distance > Shape.MIN_SHAPE_SIZE else Vector2.ZERO
		if normal_flip:
			normal = -normal
		return {
			"toi": 0.0,
			"point": center + offset.normalized() * obstacle_radius if distance > Shape.MIN_SHAPE_SIZE else center,
			"normal": normal,
			"feature": feature,
			"penetrating": true,
			"initial": true,
		}
	if absf(distance - combined) <= Shape.DISTANCE_EPSILON:
		# A touching start only counts as a contact when the sweep is resting
		# against or entering the obstacle.  A positive radial derivative means
		# the circles are separating; reporting toi zero here would fabricate a
		# dynamic hit at the origin of a path that is moving away.
		if offset.dot(displacement) > Shape.DIRECTION_EPSILON:
			return empty
		var touch_normal := offset.normalized() if distance > Shape.MIN_SHAPE_SIZE else Vector2.ZERO
		if normal_flip:
			touch_normal = -touch_normal
		return {
			"toi": 0.0,
			"point": center + offset.normalized() * obstacle_radius if distance > Shape.MIN_SHAPE_SIZE else center,
			"normal": touch_normal,
			"feature": feature,
			"penetrating": false,
			"initial": true,
		}
	var a := displacement.dot(displacement)
	if a <= Shape.MIN_SHAPE_SIZE * Shape.MIN_SHAPE_SIZE:
		return empty
	var b := 2.0 * offset.dot(displacement)
	var c := offset.dot(offset) - combined * combined
	var discriminant := b * b - 4.0 * a * c
	if discriminant < -Shape.DISCRIMINANT_EPSILON:
		return empty
	var root := sqrt(maxf(0.0, discriminant))
	var toi := (-b - root) / (2.0 * a)
	# The smaller root is the entering contact. A negative root means the
	# sweep's path crossed the circle before its authored start and is now
	# separating; clamping it to zero would fabricate a hit at the origin.
	if toi < -Shape.TOI_EPSILON or toi > 1.0 + Shape.TOI_EPSILON:
		return empty
	toi = clampf(toi, 0.0, 1.0)
	var contact_position := start + displacement * toi
	var radial := contact_position - center
	var radial_length := radial.length()
	var normal := radial / radial_length if radial_length > Shape.MIN_SHAPE_SIZE else Vector2.ZERO
	if normal_flip:
		normal = -normal
	return {
		"toi": toi,
		"point": center + radial.normalized() * obstacle_radius if radial_length > Shape.MIN_SHAPE_SIZE else center,
		"normal": normal,
		"feature": feature,
		"penetrating": false,
		"initial": toi <= Shape.TOI_EPSILON,
	}


## Contacts between a moving circle and a convex polygon (rects supply their
## canonical point ring).  A strictly-inside start reports one penetrating
## contact against the closest feature and no other contacts.
static func sweep_circle_polygon(
	start: Vector2,
	displacement: Vector2,
	radius: float,
	points: PackedVector2Array
) -> Array[Dictionary]:
	var hits: Array[Dictionary] = []
	if not (start.is_finite() and displacement.is_finite()):
		return hits
	if not is_finite(radius) or radius < 0.0 or points.size() < 3:
		return hits
	if Shape.is_point_inside_polygon(start, points, -Shape.DISTANCE_EPSILON):
		var nearest := Shape.closest_polygon_feature(start, points)
		hits.append({
			"toi": 0.0,
			"point": nearest["point"],
			"normal": nearest["normal"],
			"feature": String(nearest["feature"]),
			"penetrating": true,
			"initial": true,
		})
		return hits
	var count := points.size()
	for i: int in count:
		var a := points[i]
		var b := points[(i + 1) % count]
		var edge := b - a
		var edge_length := edge.length()
		if edge_length <= Shape.MIN_SHAPE_SIZE:
			continue
		var edge_dir := edge / edge_length
		var normal := edge_dir.rotated(-PI * 0.5)
		var start_distance := normal.dot(start - a)
		# A resting overlap must be measured against the edge segment, not the
		# edge plane: a body far outside the polygon sits behind the opposite
		# face's plane and would otherwise report a false penetration.
		var closest_start := Shape.closest_point_on_segment(start, a, b)
		if start.distance_to(closest_start) < radius - Shape.DISTANCE_EPSILON:
			var push_normal := (start - closest_start).normalized()
			hits.append({
				"toi": 0.0,
				"point": closest_start,
				"normal": push_normal,
				"feature": "edge:%d" % i,
				"penetrating": true,
				"initial": true,
			})
			continue
		var normal_speed := normal.dot(displacement)
		if normal_speed >= -Shape.DIRECTION_EPSILON or start_distance <= radius - Shape.DISTANCE_EPSILON:
			continue
		var toi := (radius - start_distance) / normal_speed
		if toi < 0.0:
			# Contact skin from an earlier face can put a corner start a few
			# representable units inside the adjacent face. Treat that as a
			# zero-time entering contact so the next slide resolves both faces;
			# a deeper start was already returned as penetrating above.
			if start_distance >= radius - Shape.DISTANCE_EPSILON:
				toi = 0.0
			else:
				continue
		if toi > 1.0 + Shape.TOI_EPSILON:
			continue
		toi = clampf(toi, 0.0, 1.0)
		var contact_position := start + displacement * toi
		var span := edge_dir.dot(contact_position - a)
		if span < -Shape.DISTANCE_EPSILON or span > edge_length + Shape.DISTANCE_EPSILON:
			continue
		hits.append({
			"toi": toi,
			"point": a + edge_dir * clampf(span, 0.0, edge_length),
			"normal": normal,
			"feature": "edge:%d" % i,
			"penetrating": false,
			"initial": toi <= Shape.TOI_EPSILON and start_distance <= radius + Shape.DISTANCE_EPSILON,
		})
	for i: int in count:
		var vertex_hit := sweep_circle_point(start, displacement, radius, points[i], "vertex:%d" % i)
		if not vertex_hit.is_empty():
			hits.append(vertex_hit)
	hits.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_key := "%s|%s" % [Shape.fmt(float(left["toi"])), String(left["feature"])]
		var right_key := "%s|%s" % [Shape.fmt(float(right["toi"])), String(right["feature"])]
		return left_key < right_key
	)
	return hits


## Movement-domain sweeps against an authored boundary.  Boundaries keep the
## body center inside an inset region; every hit normal points back into the
## legal region.
static func sweep_boundary(
	start: Vector2,
	displacement: Vector2,
	radius: float,
	boundary: Dictionary
) -> Array[Dictionary]:
	var hits: Array[Dictionary] = []
	if boundary.is_empty():
		return hits
	if not (start.is_finite() and displacement.is_finite()) or not is_finite(radius) or radius < 0.0:
		hits.append(_boundary_failure("boundary:invalid_input"))
		return hits
	match String(boundary.get("kind", "")):
		"rect":
			return sweep_rect_boundary(start, displacement, radius, boundary["rect"])
		"ring":
			return sweep_ring_boundary(
				start,
				displacement,
				radius,
				boundary["center"],
				float(boundary["inner_radius"]),
				float(boundary["outer_radius"])
			)
		"corridor":
			return sweep_corridor_boundary(start, displacement, radius, boundary["rect"], float(boundary["half_height"]))
		_:
			hits.append(_boundary_failure("boundary:unknown_kind"))
			return hits


static func sweep_rect_boundary(
	start: Vector2,
	displacement: Vector2,
	radius: float,
	rect: Rect2
) -> Array[Dictionary]:
	var hits: Array[Dictionary] = []
	var inset := Rect2(rect.position + Vector2(radius, radius), rect.size - Vector2(radius * 2.0, radius * 2.0))
	if inset.size.x <= 0.0 or inset.size.y <= 0.0:
		hits.append(_boundary_failure("boundary:inset_degenerate"))
		return hits
	if start.x < inset.position.x - Shape.DISTANCE_EPSILON or start.x > inset.end.x + Shape.DISTANCE_EPSILON or start.y < inset.position.y - Shape.DISTANCE_EPSILON or start.y > inset.end.y + Shape.DISTANCE_EPSILON:
		hits.append(_boundary_outside(start, inset))
		return hits
	_append_axis_face(hits, start, displacement, true, inset.position.x, -1.0, "face:left")
	_append_axis_face(hits, start, displacement, true, inset.end.x, 1.0, "face:right")
	_append_axis_face(hits, start, displacement, false, inset.position.y, -1.0, "face:top")
	_append_axis_face(hits, start, displacement, false, inset.end.y, 1.0, "face:bottom")
	return hits


static func sweep_corridor_boundary(
	start: Vector2,
	displacement: Vector2,
	radius: float,
	rect: Rect2,
	half_height: float
) -> Array[Dictionary]:
	var hits: Array[Dictionary] = []
	var band := half_height - radius
	var center_line := rect.get_center().y
	if band <= 0.0 or rect.size.x <= radius * 2.0:
		hits.append(_boundary_failure("boundary:inset_degenerate"))
		return hits
	if start.x < rect.position.x + radius - Shape.DISTANCE_EPSILON or start.x > rect.end.x - radius + Shape.DISTANCE_EPSILON or absf(start.y - center_line) > band + Shape.DISTANCE_EPSILON:
		hits.append(_boundary_failure("boundary:outside"))
		return hits
	_append_axis_face(hits, start, displacement, true, rect.position.x + radius, -1.0, "face:left")
	_append_axis_face(hits, start, displacement, true, rect.end.x - radius, 1.0, "face:right")
	_append_axis_face(hits, start, displacement, false, center_line - band, -1.0, "face:top")
	_append_axis_face(hits, start, displacement, false, center_line + band, 1.0, "face:bottom")
	return hits


static func sweep_ring_boundary(
	start: Vector2,
	displacement: Vector2,
	radius: float,
	center: Vector2,
	inner_radius: float,
	outer_radius: float
) -> Array[Dictionary]:
	var hits: Array[Dictionary] = []
	var inner := inner_radius + radius
	var outer := outer_radius - radius
	if outer <= inner:
		hits.append(_boundary_failure("boundary:inset_degenerate"))
		return hits
	var offset := start - center
	var distance := offset.length()
	if distance > outer + Shape.DISTANCE_EPSILON or distance < inner - Shape.DISTANCE_EPSILON:
		hits.append(_boundary_failure("boundary:outside"))
		return hits
	var outer_hit := _sweep_shell(start, displacement, center, outer, outer_radius, true, "outer")
	if not outer_hit.is_empty():
		hits.append(outer_hit)
	var inner_hit := _sweep_shell(start, displacement, center, inner, inner_radius, false, "inner")
	if not inner_hit.is_empty():
		hits.append(inner_hit)
	return hits


static func _sweep_shell(
	start: Vector2,
	displacement: Vector2,
	center: Vector2,
	shell_radius: float,
	surface_radius: float,
	from_inside: bool,
	feature: String
) -> Dictionary:
	var empty := {}
	var offset := start - center
	var distance := offset.length()
	if absf(distance - shell_radius) <= Shape.DISTANCE_EPSILON:
		var touch := offset / distance if distance > Shape.MIN_SHAPE_SIZE else Vector2.ZERO
		var touch_normal := -touch if from_inside else touch
		return {
			"toi": 0.0,
			"point": center + touch * surface_radius if distance > Shape.MIN_SHAPE_SIZE else center,
			"normal": touch_normal,
			"feature": feature,
			"penetrating": false,
			"initial": true,
		}
	var a := displacement.dot(displacement)
	if a <= Shape.MIN_SHAPE_SIZE * Shape.MIN_SHAPE_SIZE:
		return empty
	var b := 2.0 * offset.dot(displacement)
	var c := offset.dot(offset) - shell_radius * shell_radius
	var discriminant := b * b - 4.0 * a * c
	if discriminant < -Shape.DISCRIMINANT_EPSILON:
		return empty
	var root := sqrt(maxf(0.0, discriminant))
	var toi := (-b + root) / (2.0 * a) if from_inside else (-b - root) / (2.0 * a)
	if toi < -Shape.TOI_EPSILON or toi > 1.0 + Shape.TOI_EPSILON:
		return empty
	toi = clampf(toi, 0.0, 1.0)
	var contact_position := start + displacement * toi
	var radial := contact_position - center
	var radial_length := radial.length()
	if radial_length <= Shape.MIN_SHAPE_SIZE:
		return empty
	var radial_unit := radial / radial_length
	return {
		"toi": toi,
		"point": center + radial_unit * surface_radius,
		"normal": -radial_unit if from_inside else radial_unit,
		"feature": feature,
		"penetrating": false,
		"initial": toi <= Shape.TOI_EPSILON,
	}


static func _append_axis_face(
	hits: Array[Dictionary],
	start: Vector2,
	displacement: Vector2,
	axis_is_x: bool,
	plane: float,
	outward_sign: float,
	feature: String
) -> void:
	var start_coordinate := start.x if axis_is_x else start.y
	var speed := displacement.x if axis_is_x else displacement.y
	var outward_speed := speed * outward_sign
	if outward_speed <= Shape.DIRECTION_EPSILON:
		return
	var toi := (plane - start_coordinate) / speed
	if toi < -Shape.TOI_EPSILON or toi > 1.0 + Shape.TOI_EPSILON:
		return
	toi = clampf(toi, 0.0, 1.0)
	var contact_position := start + displacement * toi
	var normal := Vector2(-outward_sign, 0.0) if axis_is_x else Vector2(0.0, -outward_sign)
	var point := Vector2(plane, contact_position.y) if axis_is_x else Vector2(contact_position.x, plane)
	hits.append({
		"toi": toi,
		"point": point,
		"normal": normal,
		"feature": feature,
		"penetrating": false,
		"initial": toi <= Shape.TOI_EPSILON,
	})


static func _boundary_failure(feature: String) -> Dictionary:
	return {
		"toi": 0.0,
		"point": Vector2.ZERO,
		"normal": Vector2.ZERO,
		"feature": feature,
		"penetrating": true,
		"initial": true,
	}


static func _boundary_outside(start: Vector2, inset: Rect2) -> Dictionary:
	var dx_left := start.x - inset.position.x
	var dx_right := inset.end.x - start.x
	var dy_top := start.y - inset.position.y
	var dy_bottom := inset.end.y - start.y
	var minimum := minf(minf(dx_left, dx_right), minf(dy_top, dy_bottom))
	var normal := Vector2.ZERO
	if minimum == dx_left:
		normal = Vector2(1.0, 0.0)
	elif minimum == dx_right:
		normal = Vector2(-1.0, 0.0)
	elif minimum == dy_top:
		normal = Vector2(0.0, 1.0)
	else:
		normal = Vector2(0.0, -1.0)
	return {
		"toi": 0.0,
		"point": start,
		"normal": normal,
		"feature": "boundary:outside",
		"penetrating": true,
		"initial": true,
	}
