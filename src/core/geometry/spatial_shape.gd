class_name SpatialShape
extends RefCounted

## Authoritative geometry kernel for the spatial runtime.
##
## Numeric and coordinate contract (mirrored in every public snapshot):
## - Coordinates are Godot 2D world pixels: +x right, +y down.
## - Circle and polygon positions are centers; rect positions are min corners.
## - Polygons are strictly convex with positive shoelace area.  Outward edge
## - normals are the edge direction rotated by -PI/2.  Concave authored
## - geometry must arrive as multiple convex pieces.
## - All contact points lie on the contacted feature of the obstacle surface.
## - Ordering keys quantize numbers to KEY_DECIMALS so identical geometry
## - orders identically across processes.

const MIN_SHAPE_SIZE: float = 0.000001
const DISTANCE_EPSILON: float = 0.0001
const TOI_EPSILON: float = 0.000000001
const DIRECTION_EPSILON: float = 0.00005
const DISCRIMINANT_EPSILON: float = 0.0000001
const CONTACT_SKIN: float = 0.0001
const KEY_DECIMALS: int = 9
const KEY_FORMAT: String = "%+.9f"

const SHAPE_KINDS: Array[String] = ["rect", "circle", "polygon"]
const COLLINEAR_CROSS_EPSILON: float = 0.000000001


static func coordinate_contract() -> Dictionary:
	return {
		"axes": "+x right, +y down (Godot 2D)",
		"units": "world pixels",
		"positions": "circle/polygon centers; rect min corner",
		"toi": "normalized sweep fraction in [0, 1] of the requested displacement",
		"normals": "unit push-out vectors from the contacted feature toward the query body",
		"contact_points": "on the contacted surface feature",
		"contact_order": "toi, static_surface, overlay_surface, boundary, dynamic, source_id, generation, feature, normal",
		"environment_tie_rule": "an opaque world contact wins a tie with a dynamic target at equal toi",
		"epsilon": {
			"distance": DISTANCE_EPSILON,
			"toi": TOI_EPSILON,
			"direction": DIRECTION_EPSILON,
			"discriminant": DISCRIMINANT_EPSILON,
			"contact_skin": CONTACT_SKIN,
		},
		"determinism": "queries are pure; identical inputs and index state produce byte-identical snapshots",
	}


static func fmt(value: float) -> String:
	var normalized := 0.0 if value == 0.0 else value
	return KEY_FORMAT % [normalized]


static func vector_key(value: Vector2) -> String:
	return "%s|%s" % [fmt(value.x), fmt(value.y)]


static func _finite_number(value: Variant) -> bool:
	if value is float:
		return is_finite(value as float)
	if value is int:
		return true
	return false


static func _vector2_from(value: Variant) -> Vector2:
	if value is Vector2:
		return value
	return Vector2(INF, INF)


static func _points_from(value: Variant) -> PackedVector2Array:
	var result := PackedVector2Array()
	if value is PackedVector2Array:
		result = value
	elif value is Array:
		for entry: Variant in value:
			if entry is Vector2:
				result.append(entry)
	return result


static func rect_points(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([
		rect.position,
		Vector2(rect.end.x, rect.position.y),
		rect.end,
		Vector2(rect.position.x, rect.end.y),
	])


static func polygon_signed_area(points: PackedVector2Array) -> float:
	var total := 0.0
	var count := points.size()
	for i: int in count:
		var a := points[i]
		var b := points[(i + 1) % count]
		total += a.x * b.y - b.x * a.y
	return total * 0.5


static func normalize(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {"ok": false, "errors": ["shape:invalid_type"], "value": {}}
	var source: Dictionary = value
	var kind := String(source.get("kind", "")).strip_edges().to_lower()
	match kind:
		"rect":
			return _normalize_rect(source)
		"circle":
			return _normalize_circle(source)
		"polygon", "convex_polygon":
			return _normalize_polygon(source)
		_:
			return {"ok": false, "errors": ["shape:unknown_kind:%s" % kind], "value": {}}


static func _normalize_rect(source: Dictionary) -> Dictionary:
	var rect_value: Variant = source.get("rect", null)
	if not rect_value is Rect2:
		return {"ok": false, "errors": ["shape.rect:invalid_type"], "value": {}}
	var rect: Rect2 = rect_value
	if not (rect.position.is_finite() and rect.size.is_finite()):
		return {"ok": false, "errors": ["shape.rect:non_finite"], "value": {}}
	if rect.size.x < MIN_SHAPE_SIZE or rect.size.y < MIN_SHAPE_SIZE:
		return {"ok": false, "errors": ["shape.rect:degenerate_size"], "value": {}}
	return {
		"ok": true,
		"errors": [],
		"value": {"kind": "rect", "rect": rect, "points": rect_points(rect)},
	}


static func _normalize_circle(source: Dictionary) -> Dictionary:
	var center := _vector2_from(source.get("center", null))
	if not center.is_finite():
		return {"ok": false, "errors": ["shape.circle.center:invalid"], "value": {}}
	if not _finite_number(source.get("radius", null)):
		return {"ok": false, "errors": ["shape.circle.radius:invalid"], "value": {}}
	var radius := float(source["radius"])
	if radius < MIN_SHAPE_SIZE:
		return {"ok": false, "errors": ["shape.circle.radius:degenerate"], "value": {}}
	return {
		"ok": true,
		"errors": [],
		"value": {"kind": "circle", "center": center, "radius": radius},
	}


static func _normalize_polygon(source: Dictionary) -> Dictionary:
	var points := _points_from(source.get("points", null))
	var errors := _polygon_errors(points)
	if not errors.is_empty():
		return {"ok": false, "errors": errors, "value": {}}
	if polygon_signed_area(points) < 0.0:
		points.reverse()
	return {"ok": true, "errors": [], "value": {"kind": "polygon", "points": points}}


static func _polygon_errors(points: PackedVector2Array) -> Array[String]:
	var count := points.size()
	if count < 3:
		return ["shape.polygon:too_few_points"]
	for i: int in count:
		if not points[i].is_finite():
			return ["shape.polygon:non_finite_point"]
		var next_point := points[(i + 1) % count]
		if points[i].distance_squared_to(next_point) < MIN_SHAPE_SIZE * MIN_SHAPE_SIZE:
			return ["shape.polygon:duplicate_vertex"]
	if absf(polygon_signed_area(points)) < MIN_SHAPE_SIZE:
		return ["shape.polygon:degenerate_area"]
	var positive := false
	var negative := false
	for i: int in count:
		var a := points[i]
		var b := points[(i + 1) % count]
		var c := points[(i + 2) % count]
		var cross := (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x)
		if absf(cross) <= COLLINEAR_CROSS_EPSILON:
			return ["shape.polygon:collinear_vertex"]
		if cross > 0.0:
			positive = true
		else:
			negative = true
		if positive and negative:
			return ["shape.polygon:non_convex"]
	return []


static func shape_key(shape: Dictionary) -> String:
	match String(shape.get("kind", "")):
		"rect":
			var rect: Rect2 = shape["rect"]
			return "rect|%s|%s|%s|%s" % [
				fmt(rect.position.x),
				fmt(rect.position.y),
				fmt(rect.size.x),
				fmt(rect.size.y),
			]
		"circle":
			var center: Vector2 = shape["center"]
			return "circle|%s|%s|%s" % [fmt(center.x), fmt(center.y), fmt(shape["radius"])]
		"polygon":
			var parts: PackedStringArray = []
			for point: Vector2 in shape["points"]:
				parts.append(vector_key(point))
			return "polygon|%s" % "|".join(parts)
	return "invalid"


## Outward normal of edge index i for a canonical positive-area polygon.
static func edge_outward_normal(points: PackedVector2Array, index: int) -> Vector2:
	var a := points[index]
	var b := points[(index + 1) % points.size()]
	var edge := b - a
	return edge.normalized().rotated(-PI * 0.5)


## A point is inside when it is at or behind every outward edge plane.
static func is_point_inside_polygon(point: Vector2, points: PackedVector2Array, epsilon: float) -> bool:
	var count := points.size()
	for i: int in count:
		var normal := edge_outward_normal(points, i)
		if normal.dot(point - points[i]) > epsilon:
			return false
	return true


static func closest_point_on_segment(point: Vector2, a: Vector2, b: Vector2) -> Vector2:
	var segment := b - a
	var length_squared := segment.length_squared()
	if length_squared <= MIN_SHAPE_SIZE * MIN_SHAPE_SIZE:
		return a
	var fraction := clampf((point - a).dot(segment) / length_squared, 0.0, 1.0)
	return a + segment * fraction


static func distance_to_segment(point: Vector2, a: Vector2, b: Vector2) -> float:
	return point.distance_to(closest_point_on_segment(point, a, b))


## Nearest polygon boundary feature: an edge interior or a vertex.
static func closest_polygon_feature(point: Vector2, points: PackedVector2Array) -> Dictionary:
	var best := {"feature": "", "point": Vector2.ZERO, "normal": Vector2.ZERO, "distance": INF}
	var count := points.size()
	for i: int in count:
		var a := points[i]
		var b := points[(i + 1) % count]
		var closest := closest_point_on_segment(point, a, b)
		var distance := point.distance_to(closest)
		if distance >= float(best["distance"]) - TOI_EPSILON:
			continue
		var normal: Vector2
		var feature := ""
		if closest.distance_squared_to(a) <= MIN_SHAPE_SIZE * MIN_SHAPE_SIZE:
			feature = "vertex:%d" % i
			normal = (point - a).normalized() if point.distance_to(a) > MIN_SHAPE_SIZE else Vector2.ZERO
		elif closest.distance_squared_to(b) <= MIN_SHAPE_SIZE * MIN_SHAPE_SIZE:
			feature = "vertex:%d" % ((i + 1) % count)
			normal = (point - b).normalized() if point.distance_to(b) > MIN_SHAPE_SIZE else Vector2.ZERO
		else:
			feature = "edge:%d" % i
			normal = edge_outward_normal(points, i)
		best = {"feature": feature, "point": closest, "normal": normal, "distance": distance}
	return best


## Circle-versus-shape overlap with push-out material.  Touching within the
## distance epsilon is classified as contact, not overlap.
static func circle_shape_overlap(position: Vector2, radius: float, shape: Dictionary) -> Dictionary:
	var empty := {"overlaps": false, "depth": 0.0, "feature": "", "point": Vector2.ZERO, "normal": Vector2.ZERO}
	if not position.is_finite() or not is_finite(radius) or radius < 0.0:
		return empty
	match String(shape.get("kind", "")):
		"circle":
			var center: Vector2 = shape["center"]
			var combined: float = radius + float(shape["radius"])
			var distance := position.distance_to(center)
			if distance >= combined - DISTANCE_EPSILON:
				return empty
			var normal := (position - center).normalized() if distance > MIN_SHAPE_SIZE else Vector2.ZERO
			return {
				"overlaps": true,
				"depth": combined - distance,
				"feature": "circle",
				"point": center + normal * float(shape["radius"]),
				"normal": normal,
			}
		"rect", "polygon":
			var points: PackedVector2Array = shape["points"]
			var nearest := closest_polygon_feature(position, points)
			var nearest_distance := float(nearest["distance"])
			if is_point_inside_polygon(position, points, DISTANCE_EPSILON):
				return {
					"overlaps": true,
					"depth": radius + nearest_distance,
					"feature": String(nearest["feature"]),
					"point": nearest["point"],
					"normal": nearest["normal"],
				}
			if nearest_distance >= radius - DISTANCE_EPSILON:
				return empty
			var normal := (position - (nearest["point"] as Vector2)).normalized()
			if not normal.is_finite() or normal.length_squared() < MIN_SHAPE_SIZE:
				normal = nearest["normal"]
			return {
				"overlaps": true,
				"depth": radius - nearest_distance,
				"feature": String(nearest["feature"]),
				"point": nearest["point"],
				"normal": normal,
			}
	return empty
