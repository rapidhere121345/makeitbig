class_name EnvironmentObjectDefinition
extends Resource

## Local author data only. Footprints describe contact; explicitly authored
## movement_envelopes become blockers without any additional inflation.
## Visual: part_id, full_path, canvas_offset:Vector2, sort_anchor:Vector2,
## sort_rank:int; optional revealed_path + mask_path, on the same canvas.
## Ground: part_id, full_path, canvas_offset, layer:Ground|GroundEffects.
## Shape: part_id, type:circle, center:Vector2, radius; or type:polygon,
## points:PackedVector2Array. Socket: part_id, position:Vector2, kind, id;
## optional label/radius/landmark_offset_y/order/locked/role are copied as metadata.
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
		elif part.get("layer", "Ground") not in ["Ground", "GroundEffects"]:
			errors.append("invalid_environment_ground_layer:" + id)
		var has_variant := part.has("revealed_path") or part.has("mask_path")
		if has_variant:
			if part not in visual_parts:
				errors.append("unsupported_environment_ground_reveal:" + id)
			_check_art(part.get("revealed_path"), id + "/revealed", errors)
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
