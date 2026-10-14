class_name LayoutBlockerLoader
extends RefCounted

## Converts the authored JSON layout's collision section into the
## normalized static shapes consumed by ActorMotor.
##
## This is a content loading/build boundary, not a second movement solver.
## Concave source polygons are decomposed into stable convex pieces so the
## runtime query can stay small and deterministic. The source id is retained
## in every generated piece for diagnostics and manifest generation.

const ActorMotorScript := preload("res://src/runtime/geometry/actor_motor.gd")


static func populate_geometry(target: Variant, layout: Dictionary) -> Dictionary:
	if target == null or not target.has_method("clear_geometry") or not target.has_method("set_geometry_radius"):
		return {"ok": false, "error": "invalid_geometry_target", "errors": [], "registered": 0, "hero_radius": 6.0}
	target.clear_geometry()
	var collision_value: Variant = layout.get("collision", null)
	if not collision_value is Dictionary:
		return {"ok": true, "error": "", "errors": [], "registered": 0, "hero_radius": 6.0}
	var collision: Dictionary = collision_value
	var hero_radius := maxf(0.0, float(collision.get("hero_radius", 6.0)))
	if not bool(target.set_geometry_radius(hero_radius)):
		return {"ok": false, "error": "invalid_geometry_radius", "errors": [], "registered": 0, "hero_radius": hero_radius}
	var world_size := Vector2(1024.0, 640.0)
	if collision.has("world_uv") or _has_npc_feet(layout):
		world_size = _world_size(layout)
	var errors: Array[String] = []
	var registered := 0

	var placement_shapes: Variant = collision.get("placements", {})
	for raw_placement: Variant in layout.get("placements", []):
		if not raw_placement is Dictionary:
			continue
		var placement: Dictionary = raw_placement
		var placement_id := String(placement.get("id", ""))
		var feet := _array_point(placement.get("feet", [0.0, 0.0]))
		var declared: Variant = placement_shapes.get(placement_id, []) if placement_shapes is Dictionary else []
		for index in _array_entries(declared).size():
			var shape_value: Variant = _array_entries(declared)[index]
			if not shape_value is Dictionary:
				continue
			var result := _register_shape(target, "%s#placement_%02d" % [placement_id, index], shape_value as Dictionary, feet, Vector2.ONE, errors)
			registered += int(result)

	var world_shapes: Array = collision.get("world", []) if collision.get("world", []) is Array else []
	for index in world_shapes.size():
		var raw_shape: Variant = world_shapes[index]
		if not raw_shape is Dictionary:
			continue
		var shape_id := String((raw_shape as Dictionary).get("id", "")).strip_edges()
		if shape_id.is_empty():
			errors.append("missing_shape_id:world_%02d" % index)
			continue
		registered += _register_shape(target, shape_id, raw_shape as Dictionary, Vector2.ZERO, Vector2.ONE, errors)

	var world_uv_shapes: Array = collision.get("world_uv", []) if collision.get("world_uv", []) is Array else []
	for index in world_uv_shapes.size():
		var raw_shape: Variant = world_uv_shapes[index]
		if not raw_shape is Dictionary:
			continue
		var shape_id := String((raw_shape as Dictionary).get("id", "")).strip_edges()
		if shape_id.is_empty():
			errors.append("missing_shape_id:world_uv_%02d" % index)
			continue
		registered += _register_shape(target, shape_id, raw_shape as Dictionary, Vector2.ZERO, world_size, errors)

	for raw_placement: Variant in layout.get("placements", []):
		if not raw_placement is Dictionary:
			continue
		var placement: Dictionary = raw_placement
		if String(placement.get("layer", "")) != "npc" or not placement.has("feet_uv"):
			continue
		var feet_uv := _array_point(placement.get("feet_uv", [0.0, 0.0]))
		# NPC feet are authored in world pixels while their position is UV-based.
		# Normalize only the radius before applying the UV scale.
		var npc_radius := 7.0 / minf(world_size.x, world_size.y)
		var result := _register_shape(target, String(placement.get("id", "npc")), {"kind": "circle", "radius": npc_radius}, Vector2.ZERO, world_size, errors, feet_uv)
		registered += result

	return {
		"ok": errors.is_empty(),
		"error": "" if errors.is_empty() else "invalid_layout_collision",
		"errors": errors,
		"registered": registered,
		"hero_radius": hero_radius,
	}


static func _register_shape(
	motor: Variant,
	shape_id: String,
	shape: Dictionary,
	origin: Vector2,
	scale: Vector2,
	errors: Array[String],
	extra_origin: Vector2 = Vector2.ZERO
) -> int:
	var kind := String(shape.get("kind", "")).to_lower()
	var local_origin := origin + extra_origin * scale
	match kind:
		"circle":
			var center := _array_point(shape.get("center", [0.0, 0.0])) * scale + local_origin
			var radius := float(shape.get("radius", 0.0)) * minf(absf(scale.x), absf(scale.y))
			if radius <= 0.0 or not motor.register_circle(shape_id, center, radius):
				errors.append("invalid_circle:%s" % shape_id)
				return 0
			return 1
		"rect":
			var rect_values: Array = shape.get("rect", [0.0, 0.0, 0.0, 0.0])
			if rect_values.size() < 4:
				errors.append("invalid_rect:%s" % shape_id)
				return 0
			var rect := Rect2(local_origin + Vector2(float(rect_values[0]), float(rect_values[1])) * scale, Vector2(float(rect_values[2]), float(rect_values[3])) * scale)
			if not motor.register_rect(shape_id, rect):
				errors.append("invalid_rect:%s" % shape_id)
				return 0
			return 1
		"polygon":
			var source_points := PackedVector2Array()
			for raw_point: Variant in shape.get("points", []):
				var point := _array_point(raw_point) * scale + local_origin
				source_points.append(point)
			if source_points.size() < 3:
				errors.append("invalid_polygon:%s" % shape_id)
				return 0
			var pieces: Array[PackedVector2Array] = []
			if _is_convex(source_points):
				pieces.append(source_points)
			else:
				var indices: PackedInt32Array = Geometry2D.triangulate_polygon(source_points)
				if indices.is_empty() or indices.size() % 3 != 0:
					errors.append("non_decomposable_polygon:%s" % shape_id)
					return 0
				for index in range(0, indices.size(), 3):
					pieces.append(PackedVector2Array([
						source_points[indices[index]],
						source_points[indices[index + 1]],
						source_points[indices[index + 2]],
					]))
			var registered := 0
			for index in pieces.size():
				var piece: PackedVector2Array = pieces[index]
				if piece.size() < 3 or absf(_polygon_area(piece)) <= 0.000001:
					continue
				if motor.register_polygon("%s#convex_%02d" % [shape_id, index], piece):
					registered += 1
				else:
					errors.append("invalid_convex_piece:%s#%02d" % [shape_id, index])
			if registered == 0:
				errors.append("empty_convex_decomposition:%s" % shape_id)
			return registered
		_:
			errors.append("unknown_shape:%s" % shape_id)
	return 0


static func _is_convex(points: PackedVector2Array) -> bool:
	var orientation := 0.0
	for index in points.size():
		var edge := points[(index + 1) % points.size()] - points[index]
		var next_edge := points[(index + 2) % points.size()] - points[(index + 1) % points.size()]
		var cross := edge.cross(next_edge)
		if absf(cross) <= 0.000001:
			continue
		if orientation == 0.0:
			orientation = signf(cross)
		elif signf(cross) != signf(orientation):
			return false
	return orientation != 0.0


static func _polygon_area(points: PackedVector2Array) -> float:
	var area := 0.0
	for index in points.size():
		area += points[index].cross(points[(index + 1) % points.size()])
	return area * 0.5


static func _array_entries(value: Variant) -> Array:
	if value is Array:
		return value as Array
	return []


static func _array_point(value: Variant) -> Vector2:
	if value is Vector2:
		return value as Vector2
	if value is Array and (value as Array).size() >= 2:
		return Vector2(float((value as Array)[0]), float((value as Array)[1]))
	return Vector2.ZERO


static func _world_size(layout: Dictionary) -> Vector2:
	var value: Variant = layout.get("world", [1024.0, 640.0])
	if value is Array and (value as Array).size() >= 2:
		var values: Array = value as Array
		var width := 1024.0
		var height := 640.0
		if values[0] is int or values[0] is float:
			width = values[0]
		if values[1] is int or values[1] is float:
			height = values[1]
		return Vector2(width, height)
	return Vector2(1024.0, 640.0)


static func _has_npc_feet(layout: Dictionary) -> bool:
	for raw_placement: Variant in layout.get("placements", []):
		if raw_placement is Dictionary:
			var placement: Dictionary = raw_placement
			if String(placement.get("layer", "")) == "npc" and placement.has("feet_uv"):
				return true
	return false

