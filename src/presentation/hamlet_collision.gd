class_name HamletCollision
extends RefCounted
## Base walking only. Authored footprints use world pixels relative to placement
## feet, never atlas cells, alpha, split rows, roofs or animation frames.
## Layouts without `collision` deliberately retain their old unobstructed travel.

const SKIN := 0.001
const MAX_SLIDES := 8
var hero_radius := 6.0
var _shapes: Array[Dictionary] = []


func configure(layout: Dictionary) -> void:
	_shapes.clear()
	hero_radius = 6.0
	var declared: Variant = layout.get("collision", null)
	if not declared is Dictionary:
		return
	var config := declared as Dictionary
	hero_radius = maxf(0.0, float(config.get("hero_radius", hero_radius)))
	var footprints: Dictionary = config.get("placements", {})
	for raw: Variant in layout.get("placements", []):
		if not raw is Dictionary:
			continue
		var placement := raw as Dictionary
		var id := String(placement.get("id", ""))
		if not footprints.has(id):
			continue
		var feet: Array = placement.get("feet", [0, 0])
		for shape: Dictionary in footprints.get(id, []):
			_add_shape(id, shape, Vector2(float(feet[0]), float(feet[1])))
	for shape: Dictionary in config.get("world", []):
		_add_shape(String(shape.get("id", "")), shape, Vector2.ZERO)
	# The full-scene layout traces the visible source in normalized coordinates.
	# Legacy placement footprints continue to use native world pixels above.
	var size: Array = layout.get("world", [1024, 640])
	var world_size := Vector2(float(size[0]), float(size[1]))
	for source: Dictionary in config.get("world_uv", []):
		var shape := source.duplicate(true)
		if String(shape.get("kind", "")) == "polygon":
			shape["points"] = []
			for point: Array in source.get("points", []):
				shape.points.append([float(point[0]) * world_size.x, float(point[1]) * world_size.y])
		elif String(shape.get("kind", "")) == "circle":
			var point: Array = source.get("center", [0, 0])
			shape["center"] = [float(point[0]) * world_size.x, float(point[1]) * world_size.y]
			shape["radius"] = float(source.get("radius", 0.0)) * world_size.x
		_add_shape(String(shape.get("id", "")), shape, Vector2.ZERO)
	for placement: Dictionary in layout.get("placements", []):
		if String(placement.get("layer", "")) != "npc" or not placement.has("feet_uv"):
			continue
		var feet: Array = placement.feet_uv
		_add_shape(String(placement.id), {"kind": "circle", "radius": 7.0}, Vector2(float(feet[0]), float(feet[1])) * world_size)


func _add_shape(id: String, source: Dictionary, origin: Vector2) -> void:
	match String(source.get("kind", "")):
		"circle":
			var center: Array = source.get("center", [0, 0])
			var radius := float(source.get("radius", 0.0))
			if radius > 0.0:
				_shapes.append({"id": id, "kind": "circle", "center": origin + Vector2(float(center[0]), float(center[1])), "radius": radius})
		"rect":
			var rect: Array = source.get("rect", [0, 0, 0, 0])
			if float(rect[2]) > 0.0 and float(rect[3]) > 0.0:
				_shapes.append({"id": id, "kind": "rect", "rect": Rect2(origin + Vector2(float(rect[0]), float(rect[1])), Vector2(float(rect[2]), float(rect[3])))})
		"polygon":
			var points := PackedVector2Array()
			for point: Array in source.get("points", []):
				points.append(origin + Vector2(float(point[0]), float(point[1])))
			if points.size() >= 3:
				_shapes.append({"id": id, "kind": "polygon", "points": points})


func footprints() -> Array[Dictionary]:
	return _shapes.duplicate(true)


func is_blocked(point: Vector2) -> bool:
	for shape: Dictionary in _shapes:
		if _overlaps(point, shape):
			return true
	return false


func _overlaps(point: Vector2, shape: Dictionary) -> bool:
	if shape.kind == "circle":
		return point.distance_to(shape.center) < float(shape.radius) + hero_radius - SKIN
	if shape.kind == "polygon":
		var points: PackedVector2Array = shape.points
		if Geometry2D.is_point_in_polygon(point, points):
			return true
		for index in points.size():
			var closest := Geometry2D.get_closest_point_to_segment(point, points[index], points[(index + 1) % points.size()])
			if point.distance_to(closest) < hero_radius - SKIN:
				return true
		return false
	var rect: Rect2 = shape.rect
	return rect.has_point(point) or point.distance_to(point.clamp(rect.position, rect.end)) < hero_radius - SKIN


func move(start: Vector2, displacement: Vector2, bounds: Rect2) -> Vector2:
	var position := start.clamp(bounds.position, bounds.end)
	var remaining := displacement
	# Explicit teleport/occlusion fixtures may start inside a footprint. Let that
	# footprint be exited without relocating the fixture; normal walking cannot
	# enter it. The exemption lasts only while each call starts inside that shape.
	var exempt: Array[Dictionary] = []
	for shape: Dictionary in _shapes:
		if _overlaps(position, shape):
			exempt.append(shape)
	for iteration in MAX_SLIDES:
		if remaining.length_squared() < 0.00000001:
			break
		var hit := _sweep_bounds(position, remaining, bounds)
		for shape: Dictionary in _shapes:
			if exempt.has(shape):
				continue
			var candidate := _sweep_shape(position, remaining, shape)
			hit = _earlier(hit, candidate)
		if hit.is_empty():
			position += remaining
			break
		var time := float(hit.time)
		var normal: Vector2 = hit.normal
		# Stop before contact along the swept path so a simultaneous second wall
		# cannot be penetrated by an outward nudge. Retain the unused tangent motion
		# as well, avoiding a per-frame skin loss at high refresh rates.
		var travel_time := maxf(0.0, time - float(hit.get("skin", SKIN)) / maxf(SKIN, -remaining.dot(normal)))
		position += remaining * travel_time
		remaining *= 1.0 - travel_time
		remaining -= normal * minf(0.0, remaining.dot(normal))
	# If the slide budget is exhausted, discard remaining motion rather than
	# crossing a wall. World bounds retain the existing feet-centre semantics.
	return position.clamp(bounds.position, bounds.end)


func _earlier(a: Dictionary, b: Dictionary) -> Dictionary:
	return b if not b.is_empty() and (a.is_empty() or float(b.time) < float(a.time)) else a


func _sweep_circle(start: Vector2, motion: Vector2, center: Vector2, radius: float) -> Dictionary:
	var offset := start - center
	var approach := offset.dot(motion)
	if approach >= 0.0:
		return {}
	var length_squared := motion.length_squared()
	var discriminant := approach * approach - length_squared * (offset.length_squared() - radius * radius)
	if discriminant <= 0.0:
		return {}
	var time := (-approach - sqrt(discriminant)) / length_squared
	if time < -0.000001 or time > 1.0:
		return {}
	var normal := (start + motion * maxf(0.0, time) - center).normalized()
	if motion.dot(normal) >= -0.000001:
		return {}
	return {"time": maxf(0.0, time), "normal": normal}


func _sweep_shape(start: Vector2, motion: Vector2, shape: Dictionary) -> Dictionary:
	if shape.kind == "circle":
		return _sweep_circle(start, motion, shape.center, float(shape.radius) + hero_radius)
	if shape.kind == "polygon":
		var points: PackedVector2Array = shape.points
		var result := {}
		for index in points.size():
			result = _earlier(result, _sweep_segment(start, motion, points[index], points[(index + 1) % points.size()]))
		return result
	var rect: Rect2 = shape.rect
	var hit := {}
	# A swept foot disc against a rectangle is a rounded rectangle: four faces
	# and four corner circles. Square-expanded corners would close narrow gaps.
	for side: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		var horizontal: bool = side.x != 0.0
		var speed := motion.x if horizontal else motion.y
		var axis_normal := side.x if horizontal else side.y
		if speed * axis_normal >= 0.0:
			continue
		var edge := (rect.position.x if side.x < 0.0 else rect.end.x) if horizontal else (rect.position.y if side.y < 0.0 else rect.end.y)
		var time := (edge + axis_normal * hero_radius - (start.x if horizontal else start.y)) / speed
		if time < -0.000001 or time > 1.0:
			continue
		var contact := start + motion * time
		var across := contact.y if horizontal else contact.x
		var low := rect.position.y if horizontal else rect.position.x
		var high := rect.end.y if horizontal else rect.end.x
		if across >= low and across <= high:
			hit = _earlier(hit, {"time": maxf(0.0, time), "normal": side})
	for corner in [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]:
		hit = _earlier(hit, _sweep_circle(start, motion, corner, hero_radius))
	return hit


func _sweep_segment(start: Vector2, motion: Vector2, a: Vector2, b: Vector2) -> Dictionary:
	var hit := _earlier(_sweep_circle(start, motion, a, hero_radius), _sweep_circle(start, motion, b, hero_radius))
	var edge := b - a
	if edge.length_squared() < 0.000001:
		return hit
	var tangent := edge.normalized()
	var perpendicular := Vector2(-tangent.y, tangent.x)
	for normal: Vector2 in [perpendicular, -perpendicular]:
		var speed := motion.dot(normal)
		if speed >= -0.000001:
			continue
		var time := (hero_radius - (start - a).dot(normal)) / speed
		if time < -0.000001 or time > 1.0:
			continue
		var along := (start + motion * time - a).dot(tangent)
		if along >= 0.0 and along <= edge.length():
			hit = _earlier(hit, {"time": maxf(0.0, time), "normal": normal})
	return hit


func _sweep_bounds(start: Vector2, motion: Vector2, bounds: Rect2) -> Dictionary:
	var hit := {}
	for axis in 2:
		if is_zero_approx(motion[axis]):
			continue
		var edge: float = bounds.end[axis] if motion[axis] > 0.0 else bounds.position[axis]
		var time: float = (edge - start[axis]) / motion[axis]
		if time >= 0.0 and time < 1.0:
			var normal := Vector2.ZERO
			normal[axis] = -signf(motion[axis])
			hit = _earlier(hit, {"time": time, "normal": normal, "skin": 0.0})
	return hit
