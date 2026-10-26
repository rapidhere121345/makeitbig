class_name EnvironmentObjectDefinition
extends Resource

const PairedRevealScript := preload("res://src/presentation/occlusion/paired_reveal_controller.gd")

## Local author data only. Footprints describe contact; explicitly authored
## movement_envelopes become blockers without any additional inflation.
## Visual: part_id, full_path, canvas_offset:Vector2, sort_anchor:Vector2,
## sort_rank:int; optional revealed_path + mask_path, on the same canvas; or
## an explicit reveal_policy: "none" is a solid base that never enters the
## legacy silhouette fallback, "primitive_fade" carries occlusion_volumes —
## circles or convex polygons (rectangles as 4-point polygons) in LOCAL
## CANVAS coordinates, translated by the placement at bake time. A volume is
## presentation metadata only: it never becomes a footprint, a movement
## envelope or static collision geometry. "paired_reveal" is the whole-object
## generated-asset policy: one part carries full_path (opaque) plus
## revealed_path (baked transparent, same canvas/anchors/RGB) and one
## occlusion_rect in LOCAL CANVAS coordinates — the whole object's detection
## rectangle, conventionally the occupied AABB grown by
## PAIRED_REVEAL_DETECTION_GROW — placement-translated at bake time like the
## volumes. It must not carry mask_path or occlusion_volumes.
## Ground: part_id, full_path, canvas_offset, layer:Ground|GroundEffects.
## Shape: part_id, type:circle, center:Vector2, radius; or type:polygon,
## points:PackedVector2Array. Socket: part_id, position:Vector2, kind, id;
## optional label/radius/landmark_offset_y/order/locked/role are copied as metadata.
## Detection-rect enlargement shared with the paired reveal controller and
## the packing recipe: the authored occlusion_rect must contain the opaque
## texture's occupied AABB grown by this many pixels on every side.
const PAIRED_REVEAL_DETECTION_GROW := 8.0

@export var asset_id := ""
@export var canvas_size := Vector2i.ZERO
@export var visual_parts: Array[Dictionary] = []
@export var ground_parts: Array[Dictionary] = []
@export var footprints: Array[Dictionary] = []
@export var movement_envelopes: Array[Dictionary] = []
@export var sockets: Array[Dictionary] = []


func validate() -> Array[String]:
	var errors: Array[String] = []
	if asset_id.strip_edges().is_empty():
		errors.append("invalid_environment_asset_id")
	if canvas_size.x <= 0 or canvas_size.y <= 0:
		errors.append("invalid_environment_canvas")
	var ids := {}
	for collection: Array in [visual_parts, ground_parts, footprints, movement_envelopes, sockets]:
		for part: Dictionary in collection:
			var id := str(part.get("part_id", ""))
			if not part.get("part_id") is String or not valid_id(id) or ids.has(id):
				errors.append("invalid_or_duplicate_environment_part:" + id)
			ids[id] = true
	for part: Dictionary in visual_parts + ground_parts:
		var id := str(part.get("part_id", ""))
		_check_vector(part, "canvas_offset", errors)
		_check_art(part.get("full_path"), id + "/full", errors)
		if part in visual_parts:
			_check_vector(part, "sort_anchor", errors)
			if not part.get("sort_rank") is int or int(part.get("sort_rank", -1)) < 0:
				errors.append("invalid_environment_sort_rank:" + id)
			errors.append_array(_check_reveal_policy(part, id))
		elif part.get("layer", "Ground") not in ["Ground", "GroundEffects"]:
			errors.append("invalid_environment_ground_layer:" + id)
		var has_variant := part.has("revealed_path") or part.has("mask_path")
		if has_variant:
			if part not in visual_parts:
				errors.append("unsupported_environment_ground_reveal:" + id)
			_check_art(part.get("revealed_path"), id + "/revealed", errors)
			## The whole-object pair carries no mask; every other variant
			## still proves its mask art on the same canvas.
			if part.has("mask_path") or String(part.get("reveal_policy", "")) != "paired_reveal":
				_check_art(part.get("mask_path"), id + "/mask", errors)
	for shape: Dictionary in footprints + movement_envelopes:
		_check_shape(shape, errors)
	for socket: Dictionary in sockets:
		_check_vector(socket, "position", errors)
		if socket.get("kind", "") not in ["interaction", "resident", "spawn", "exit"]:
			errors.append("invalid_environment_socket_kind:" + str(socket.get("part_id", "")))
		if not socket.get("id") is String or String(socket.get("id", "")).is_empty():
			errors.append("invalid_environment_socket_id")
		for key: String in ["radius", "landmark_offset_y", "order"]:
			if socket.has(key) and (not _number(socket[key]) or (key == "radius" and float(socket[key]) <= 0.0)):
				errors.append("invalid_environment_socket_number:" + key)
		for key: String in ["label", "role"]:
			if socket.has(key) and not socket[key] is String:
				errors.append("invalid_environment_socket_text:" + key)
		if socket.has("locked") and not socket.locked is bool:
			errors.append("invalid_environment_socket_locked")
	return errors


static func valid_id(value: String) -> bool:
	if value.is_empty():
		return false
	for character: String in value:
		if not character in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.-":
			return false
	return true


## Explicit reveal policy on one visual part: absent keeps the legacy
## derivation (variant art if present, otherwise none), "none" is an
## explicit solid base and must not also carry variant art, "authored_variant"
## must carry its art pair, and "primitive_fade" must carry authored
## occlusion volumes — circles or convex polygons in local canvas
## coordinates — and must not also carry variant art: exactly one policy
## operates on a piece. Unknown policies and absent, malformed, non-finite
## or degenerate volumes fail closed.
static func _check_reveal_policy(part: Dictionary, id: String) -> Array[String]:
	var errors: Array[String] = []
	var policy: Variant = part.get("reveal_policy", "")
	if not policy is String:
		errors.append("invalid_environment_reveal_policy:" + id)
		return errors
	var variant := part.has("revealed_path") or part.has("mask_path")
	match String(policy):
		"":
			pass
		"none":
			if variant:
				errors.append("none_policy_conflict:" + id)
		"authored_variant":
			if not variant:
				errors.append("authored_variant_without_reveal:" + id)
		"primitive_fade":
			if variant:
				errors.append("primitive_fade_policy_conflict:" + id)
			var volumes: Variant = part.get("occlusion_volumes", [])
			if not volumes is Array or (volumes as Array).is_empty():
				errors.append("missing_environment_occlusion_volumes:" + id)
			else:
				for index in (volumes as Array).size():
					var volume: Variant = (volumes as Array)[index]
					if not volume is Dictionary:
						errors.append("invalid_environment_volume:" + id)
						continue
					var labeled: Dictionary = (volume as Dictionary).duplicate()
					labeled["part_id"] = id + "/volume" + str(index)
					_check_shape(labeled, errors)
					var data: Dictionary = volume
					if data.get("type") == "polygon" and data.get("points") is PackedVector2Array and _degenerate_volume(data.points):
						errors.append("invalid_environment_polygon:" + id + "/volume" + str(index))
		"paired_reveal":
			if part.has("mask_path"):
				errors.append("paired_reveal_mask_conflict:" + id)
			if part.has("occlusion_volumes"):
				errors.append("paired_reveal_volumes_conflict:" + id)
			if not part.has("revealed_path"):
				errors.append("paired_reveal_without_reveal:" + id)
			var rect: Variant = part.get("occlusion_rect", null)
			if not rect is Rect2 or not (rect as Rect2).position.is_finite() or not (rect as Rect2).size.is_finite() or (rect as Rect2).size.x <= 0.0 or (rect as Rect2).size.y <= 0.0:
				errors.append("invalid_paired_occlusion_rect:" + id)
			else:
				var texture := read_texture(String(part.get("full_path", "")))
				if texture != null:
					var occupied := PairedRevealScript.occupied_aabb(texture.get_image())
					if occupied.has_area() and not (rect as Rect2).encloses(occupied.grow(PAIRED_REVEAL_DETECTION_GROW)):
						errors.append("paired_occlusion_rect_too_small:" + id)
		_:
			errors.append("invalid_environment_reveal_policy:" + id)
	return errors


## A collinear "polygon" still triangulates in this engine build, so a volume
## also measures its own signed area: near-zero area is degenerate regardless.
static func _degenerate_volume(points: PackedVector2Array) -> bool:
	if Geometry2D.triangulate_polygon(points).is_empty():
		return true
	var area := 0.0
	for index in points.size():
		var a: Vector2 = points[index]
		var b: Vector2 = points[(index + 1) % points.size()]
		area += a.x * b.y - b.x * a.y
	return absf(area * 0.5) <= 0.000001


static func read_texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var texture := load(path) as Texture2D
		if texture != null:
			return texture
	if FileAccess.file_exists(path):
		var image := Image.new()
		if image.load(path) == OK:
			return ImageTexture.create_from_image(image)
	return null


func _check_art(value: Variant, label: String, errors: Array[String]) -> void:
	if not value is String or String(value).is_empty():
		errors.append("missing_environment_art:" + label)
		return
	var texture := read_texture(value)
	if texture == null:
		errors.append("missing_environment_art:" + label)
	elif texture.get_size() != Vector2(canvas_size):
		errors.append("environment_canvas_mismatch:" + label)


static func _check_vector(part: Dictionary, key: String, errors: Array[String]) -> void:
	if not part.get(key) is Vector2 or not (part[key] as Vector2).is_finite():
		errors.append("invalid_environment_vector:" + str(part.get("part_id", "")) + "/" + key)


static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func _check_shape(shape: Dictionary, errors: Array[String]) -> void:
	var id := str(shape.get("part_id", ""))
	if shape.get("type") == "circle":
		_check_vector(shape, "center", errors)
		if not _number(shape.get("radius")) or float(shape.get("radius", 0.0)) <= 0.0:
			errors.append("invalid_environment_circle:" + id)
	elif shape.get("type") == "polygon":
		if not shape.get("points") is PackedVector2Array:
			errors.append("invalid_environment_polygon:" + id)
			return
		var points: PackedVector2Array = shape.points
		var valid := points.size() >= 3
		for point: Vector2 in points:
			valid = valid and point.is_finite()
		if not valid or Geometry2D.triangulate_polygon(points).is_empty():
			errors.append("invalid_environment_polygon:" + id)
	else:
		errors.append("invalid_environment_shape:" + id)
