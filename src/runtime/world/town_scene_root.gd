class_name TownSceneRoot
extends Node2D

## Native town author source. Geometry, sockets and routes live in this scene;
## its six-field manifest is a detached offline derivative checked before READY.
const SpatialManifestScript := preload("res://src/runtime/world/spatial_manifest.gd")
const EnvironmentBaker := preload("res://src/runtime/world/environment_object_baker.gd")
const EnvironmentDefinition := preload("res://src/runtime/world/environment_object_definition.gd")
const PrimitiveFadeScript := preload("res://src/presentation/occlusion/primitive_fade_controller.gd")
const PairedRevealScript := preload("res://src/presentation/occlusion/paired_reveal_controller.gd")
const TextureLoader := preload("res://src/presentation/art/texture_loader.gd")
const GROUPS: Array[String] = ["Ground", "GroundEffects", "SortRoot", "Foreground", "GeometrySources", "Sockets"]

@export var world_size := Vector2(1536, 960)
@export var view_size := Vector2(640, 360)
@export var hero_screen_anchor := Vector2(320, 222)
@export var hero_radius := 6.0
@export var scene_id := "town.hearthside"
@export var world_asset_id := "town/hearthside"
@export var gameplay_source := "hearthside.spatial.json"
@export var presentation_source := "town_presenter"
@export var modular_underplate_path := ""


func bind_native_art() -> Array[String]:
	var errors: Array[String] = []
	for group: String in _visual_groups():
		var parent := get_node_or_null(group)
		if parent == null:
			errors.append("missing_native_group:" + group)
			continue
		for node: Node in parent.get_children():
			if not node is Sprite2D:
				errors.append("invalid_native_visual:" + String(node.name))
				continue
			var path := String(node.get_meta("texture_path", ""))
			var texture: Texture2D = TextureLoader.load_imported_or_file(path)
			if texture == null:
				errors.append("missing_native_texture:" + path)
			else:
				(node as Sprite2D).texture = texture
				(node as Sprite2D).texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return errors


func validate_contract(expected: Dictionary = {}) -> Dictionary:
	var errors: Array[String] = []
	var expansion := EnvironmentBaker.expand(self)
	errors.append_array(expansion.errors)
	for group: String in GROUPS:
		if not get_node_or_null(group) is Node2D:
			errors.append("missing_native_group:" + group)
	errors.append_array(_spatial_source_errors())
	var primitive_scan: Dictionary = _primitive_fade_scan()
	errors.append_array(primitive_scan.errors)
	var paired_scan: Dictionary = _paired_reveal_scan()
	errors.append_array(paired_scan.errors)
	if not errors.is_empty():
		return {"ok": false, "errors": errors, "value": {}}
	if scene_id.is_empty() or world_asset_id.is_empty() or gameplay_source.is_empty() or presentation_source.is_empty():
		errors.append("invalid_town_identity")
	errors.append_array(_modular_layer_errors())
	errors.append_array(bind_native_art())
	if not errors.is_empty():
		return {"ok": false, "errors": errors, "value": {}}
	var spatial := derive_spatial_manifest()
	if spatial.get("ok", true) == false:
		return {"ok": false, "errors": spatial.errors, "value": {}}
	var manifest = SpatialManifestScript.new(spatial)
	errors.append_array(manifest.validate())
	var bindings := {}
	for group: String in GROUPS:
		_collect_bindings(get_node(group), bindings, errors)
	var contract := {
		"scene_id": scene_id, "world_asset_id": world_asset_id, "gameplay_source": gameplay_source,
		"presentation_source": presentation_source, "groups": GROUPS.duplicate(), "bindings": bindings,
		"movement_binding": "town/movement-boundary", "authored_bounds": Rect2(Vector2.ZERO, world_size),
		"spatial_manifest": manifest.snapshot(), "unknown_underplate": "opaque",
		"ground_source_path": modular_underplate_path,
		"supports_cutaway": true, "supports_fade": false,
		"primitive_fade_bindings": primitive_scan.bindings,
		"paired_reveal_bindings": paired_scan.bindings,
	}
	for key: String in expected:
		if contract.has(key) and contract[key] != expected[key]:
			errors.append("native_contract_mismatch:" + key)
	return {"ok": errors.is_empty(), "errors": errors, "value": contract}


func derive_spatial_manifest() -> Dictionary:
	var expansion := EnvironmentBaker.expand(self)
	if not expansion.ok:
		return {"ok": false, "errors": expansion.errors, "value": {}}
	var errors := _spatial_source_errors()
	if errors.is_empty():
		errors.append_array(bind_native_art())
		errors.append_array(_modular_layer_errors())
	if not errors.is_empty():
		return {"ok": false, "errors": errors, "value": {}}
	var bindings: Array[Dictionary] = []
	var image_records := {}
	var boundary: Rect2 = get_node("GeometrySources/MovementBoundary").get_meta("rect", Rect2())
	bindings.append({"binding_id": "town/movement-boundary", "source": "town.native.v1", "geometry": {"type": "rect", "rect": _rect(boundary)},
		"channels": {"movement": true, "navigation": true, "vision": false, "projectile": false, "occlusion": false}})
	for group: String in _visual_groups():
		for node: Node2D in get_node(group).get_children():
			var binding := {"binding_id": String(node.get_meta("binding_id", "")), "kind": "native_visual", "channels": {"occlusion": group == "SortRoot"}}
			var fingerprint := _visual_fingerprint(node as Sprite2D, group, image_records)
			errors.append_array(fingerprint.errors)
			binding.source = "town.modular.visual.v1:" + String(fingerprint.value)
			bindings.append(binding)
	if not errors.is_empty():
		return {"ok": false, "errors": errors, "value": {}}
	var geometry: Array[Dictionary] = []
	for shape: Polygon2D in get_node("GeometrySources/Static").get_children():
		var id := String(shape.get_meta("binding_id", ""))
		bindings.append({"binding_id": id, "kind": "static_collision", "channels": {}})
		if shape.has_meta("radius"):
			geometry.append({"id": id, "kind": "circle", "center": _pair(shape.position), "radius": snappedf(float(shape.get_meta("radius")), 1.0 / 64.0)})
		else:
			var indices := Geometry2D.triangulate_polygon(shape.polygon)
			for index: int in range(0, indices.size(), 3):
				var a := _pair(shape.polygon[indices[index]] + shape.position)
				var b := _pair(shape.polygon[indices[index + 1]] + shape.position)
				var c := _pair(shape.polygon[indices[index + 2]] + shape.position)
				var cross := (Vector2(b[0], b[1]) - Vector2(a[0], a[1])).cross(Vector2(c[0], c[1]) - Vector2(a[0], a[1]))
				if absf(cross) <= 0.000001:
					continue
				geometry.append({"id": "%s/%03d" % [id, index / 3], "kind": "polygon", "points": [a, b, c]})

	var sockets: Array[Dictionary] = []
	var facilities: Array[Dictionary] = []
	var residents: Array[Dictionary] = []
	var gateways: Array[Dictionary] = []
	for node: Marker2D in get_node("Sockets").get_children():
		var kind := String(node.get_meta("kind", ""))
		var id := String(node.get_meta("id", ""))
		var position := _pair(node.position)
		var binding := String(node.get_meta("binding_id", ""))
		if kind != "resident":
			sockets.append({"socket_id": binding, "kind": kind, "position": position})
		if kind == "interaction":
			facilities.append({"id": id, "position": position, "label": String(node.get_meta("label", id)),
				"radius": float(node.get_meta("radius", 48)), "landmark_offset_y": float(node.get_meta("landmark_offset_y", -112)), "order": float(node.get_meta("order", 0)), "locked": bool(node.get_meta("locked", false))})
		elif kind == "resident":
			residents.append({"id": id, "position": position, "role": String(node.get_meta("role", "")), "radius": 7.0})
		elif kind == "exit" and node.has_meta("gateway_action"):
			gateways.append({"id": id, "position": position, "label": String(node.get_meta("label", id)),
				"radius": float(node.get_meta("radius", 48)), "action": String(node.get_meta("gateway_action")), "order": float(node.get_meta("order", 0))})
	var routes := {}
	for route: Node2D in get_node("GeometrySources/Routes").get_children():
		var points: Array = []
		for point: Marker2D in route.get_children():
			points.append(_pair(point.position))
		routes[String(route.name)] = points
	var manifest := {"coordinate_convention": {"units": "design_pixel", "up": "negative_y", "scale": 1.0},
		"stable_bindings": bindings, "traversal_profiles": [], "regions_and_portals": [], "spawn_interaction_exit_sockets": sockets,
		"gameplay_spatial_metadata": {"room_kind": "town", "geometry_source": "town.native.v1", "coordinate_precision": 1.0 / 64.0, "world_size": _pair(world_size),
			"view_size": _pair(view_size), "hero_screen_anchor": _pair(hero_screen_anchor), "hero_radius": hero_radius,
			"facilities": facilities, "residents": residents, "routes": routes, "static_geometry": geometry}}
	## Only present when the scene authors a gate, so gateless manifests keep their digest.
	if not gateways.is_empty():
		manifest["gameplay_spatial_metadata"]["gateways"] = gateways
	return manifest


## Coordinates below are authored directly in root space. Only leaves may
## translate; containers, bases and top-level overrides cannot be represented
## by the current derivative. Reject them before producing any manifest data.
func _spatial_source_errors() -> Array[String]:
	var errors: Array[String] = []
	_check_source_transform(self, false, errors)
	for path: String in ["GeometrySources", "GeometrySources/MovementBoundary", "GeometrySources/Static", "GeometrySources/Routes", "Sockets"]:
		var source := get_node_or_null(path) as Node2D
		if source == null:
			errors.append("missing_native_source:" + path)
		else:
			_check_source_transform(source, false, errors)
	if not errors.is_empty():
		return errors
	for shape: Node in get_node("GeometrySources/Static").get_children():
		if not shape is Polygon2D:
			errors.append("invalid_native_static_source:" + String(shape.name))
			continue
		_check_source_transform(shape, true, errors)
		if (shape as Polygon2D).offset != Vector2.ZERO:
			errors.append("unsupported_native_polygon_offset:" + String(get_path_to(shape)))
	for socket: Node in get_node("Sockets").get_children():
		if not socket is Marker2D:
			errors.append("invalid_native_socket_source:" + String(socket.name))
		else:
			_check_source_transform(socket, true, errors)
	for route: Node in get_node("GeometrySources/Routes").get_children():
		if not route is Node2D:
			errors.append("invalid_native_route_source:" + String(route.name))
			continue
		_check_source_transform(route, false, errors)
		for point: Node in route.get_children():
			if not point is Marker2D:
				errors.append("invalid_native_route_point:" + String(point.name))
			else:
				_check_source_transform(point, true, errors)
	return errors


func _visual_groups() -> Array[String]:
	return ["Ground", "GroundEffects", "SortRoot"]


## Hash decoded pixels rather than source PNG bytes: imported textures also
## work after export, where their source images need not exist.
func _visual_fingerprint(sprite: Sprite2D, group: String, images: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var full_path := String(sprite.get_meta("texture_path", ""))
	var policy := String(sprite.get_meta("reveal_policy", ""))
	var record := {
		"asset_id": String(sprite.get_meta("environment_asset_id", "")), "group": group,
		"position": [sprite.position.x, sprite.position.y], "offset": [sprite.offset.x, sprite.offset.y],
		"rank": int(sprite.get_meta("sort_rank", 0)), "stable_id": String(sprite.get_meta("sort_stable_id", sprite.get_meta("binding_id", ""))),
		"centered": sprite.centered, "policy": policy, "full": {},
	}
	if policy == PrimitiveFadeScript.POLICY:
		record["volumes"] = PrimitiveFadeScript.volumes_payload(sprite.get_meta("occlusion_volumes", []))
	elif policy == PairedRevealScript.POLICY:
		var rect: Rect2 = sprite.get_meta("occlusion_rect", Rect2())
		record["occlusion_rect"] = [rect.position.x, rect.position.y, rect.size.x, rect.size.y]
	var roles: Array[String] = ["full"]
	if policy == "authored_variant":
		roles = ["full", "variant", "mask"]
	elif policy == PairedRevealScript.POLICY:
		roles = ["full", "variant"]
	for role: String in roles:
		var path := full_path if role == "full" else String(sprite.get_meta("reveal_" + role + "_path", ""))
		if role == "full" and policy in ["authored_variant", PairedRevealScript.POLICY] and String(sprite.get_meta("reveal_full_path", "")) != full_path:
			errors.append("invalid_modular_full_reference:" + String(sprite.name))
		if not images.has(path):
			images[path] = _image_fingerprint(path, sprite.texture if role == "full" else null)
		var image_record: Dictionary = images[path]
		if image_record.is_empty():
			errors.append("invalid_modular_presentation_image:" + path)
		elif role != "full" and image_record["size"] != [int(sprite.texture.get_width()), int(sprite.texture.get_height())]:
			errors.append("modular_variant_canvas_mismatch:" + path)
		record[role] = image_record
	return {"errors": errors, "value": SpatialManifestScript.digest_payload_sha256(record)}


static func _image_fingerprint(path: String, supplied: Texture2D = null) -> Dictionary:
	var texture := supplied if supplied != null else EnvironmentDefinition.read_texture(path)
	if texture == null:
		return {}
	var image := texture.get_image()
	if image == null or image.is_empty():
		return {}
	if image.is_compressed() and image.decompress() != OK:
		return {}
	image.convert(Image.FORMAT_RGBA8)
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(image.get_data())
	return {"path": path, "size": [image.get_width(), image.get_height()], "rgba8_sha256": context.finish().hex_encode()}


## Fail-closed meta checks shared by the modular layer scan and the paired
## binding scan. A paired piece must carry both
## texture paths and a finite, non-degenerate WORLD detection rect, and must
## not carry the other policies' metas.
func _paired_piece_errors(sprite: Sprite2D, id: String) -> Array[String]:
	var errors: Array[String] = []
	if sprite == null:
		return ["invalid_paired_reveal_piece:" + id]
	if sprite.has_meta("reveal_mask_path") or sprite.has_meta("occlusion_volumes"):
		errors.append("paired_reveal_policy_conflict:" + id)
	if String(sprite.get_meta("reveal_full_path", "")).is_empty() or String(sprite.get_meta("reveal_variant_path", "")).is_empty():
		errors.append("missing_paired_reveal_paths:" + id)
	elif String(sprite.get_meta("reveal_full_path", "")) != String(sprite.get_meta("texture_path", "")):
		errors.append("invalid_paired_full_reference:" + id)
	var rect_error := PairedRevealScript.detection_rect_error(sprite.get_meta("occlusion_rect", null), null)
	if not rect_error.is_empty():
		errors.append(rect_error + ":" + id)
	return errors


## Pieces may opt into paired_reveal individually — the environment baker
## stamps the metas this scan reads. List the opted-in bindings for the honest
## whole-object contract and fail closed on any malformed piece.
func _paired_reveal_scan() -> Dictionary:
	var errors: Array[String] = []
	var bindings: Array[String] = []
	for group: String in _visual_groups():
		var parent := get_node_or_null(group)
		if parent == null:
			continue
		for node: Node in parent.get_children():
			if String(node.get_meta("reveal_policy", "")) != PairedRevealScript.POLICY:
				continue
			var id := String(node.get_meta("binding_id", String(node.name)))
			var piece_errors := _paired_piece_errors(node as Sprite2D, id)
			errors.append_array(piece_errors)
			if piece_errors.is_empty():
				bindings.append(id)
	bindings.sort()
	return {"errors": errors, "bindings": bindings}


## Modular reveal requires a real, fully opaque world-sized lower layer.
## This checks delivery data, not whether the image is artistically complete.
func _modular_layer_errors() -> Array[String]:
	var errors: Array[String] = []
	var texture := EnvironmentDefinition.read_texture(modular_underplate_path) if not modular_underplate_path.is_empty() else null
	if texture == null or texture.get_size() != world_size:
		return ["invalid_modular_underplate"]
	var image := texture.get_image()
	if image == null or image.is_empty():
		return ["invalid_modular_underplate"]
	if image.is_compressed() and image.decompress() != OK:
		return ["invalid_modular_underplate"]
	for y: int in image.get_height():
		for x: int in image.get_width():
			if image.get_pixel(x, y).a < 1.0:
				return ["incomplete_modular_underplate"]
	var found := false
	var ground := get_node("Ground") as Node2D
	if not ground.visible or ground.modulate != Color.WHITE or ground.self_modulate != Color.WHITE or ground.material != null:
		errors.append("invalid_modular_underplate_group")
	for node: Node in get_node("Ground").get_children():
		if node is Sprite2D and String(node.get_meta("texture_path", "")) == modular_underplate_path:
			found = true
			var sprite := node as Sprite2D
			if sprite.position != Vector2.ZERO or sprite.centered or sprite.offset != Vector2.ZERO or sprite.transform != Transform2D.IDENTITY or not sprite.visible or sprite.modulate != Color.WHITE or sprite.self_modulate != Color.WHITE or sprite.material != null or sprite.region_enabled or sprite.get_meta("reveal_policy", "") != "none":
				errors.append("invalid_modular_underplate_visual")
	if not found:
		errors.append("missing_modular_underplate_visual")
	for group: String in _visual_groups():
		for node: Node in get_node(group).get_children():
			if node is Sprite2D:
				_check_source_transform(node, true, errors)
				if not node.offset.is_finite() or node.region_enabled or node.hframes != 1 or node.vframes != 1 or node.flip_h or node.flip_v:
					errors.append("unsupported_modular_visual_canvas:" + String(node.name))
				# These overrides have no author field/fingerprint and can
				# bypass the shared sort domain or alter full-state pixels.
				if node.z_index != 0 or not node.z_as_relative or not node.visible or node.modulate != Color.WHITE or node.self_modulate != Color.WHITE or node.material != null:
					errors.append("unsupported_modular_visual_override:" + String(node.name))
				var policy := String(node.get_meta("reveal_policy", ""))
				if policy not in ["none", "authored_variant", PrimitiveFadeScript.POLICY, PairedRevealScript.POLICY]:
					errors.append("missing_modular_reveal_policy:" + String(node.name))
				elif policy == PrimitiveFadeScript.POLICY:
					var volumes: Variant = node.get_meta("occlusion_volumes", [])
					if not volumes is Array or (volumes as Array).is_empty():
						errors.append("missing_modular_occlusion_volumes:" + String(node.name))
					if node.has_meta("reveal_variant_path") or node.has_meta("reveal_full_path"):
						errors.append("primitive_fade_policy_conflict:" + String(node.name))
				elif policy == PairedRevealScript.POLICY:
					errors.append_array(_paired_piece_errors(node as Sprite2D, String(node.name)))
	return errors


## Pieces may opt into primitive_fade individually — the environment baker
## stamps the metas this scan reads. List the opted-in bindings for the honest
## regional contract and fail closed on absent volumes or variant conflicts.
func _primitive_fade_scan() -> Dictionary:
	var errors: Array[String] = []
	var bindings: Array[String] = []
	for group: String in _visual_groups():
		var parent := get_node_or_null(group)
		if parent == null:
			continue
		for node: Node in parent.get_children():
			if String(node.get_meta("reveal_policy", "")) != PrimitiveFadeScript.POLICY:
				continue
			var id := String(node.get_meta("binding_id", String(node.name)))
			var volumes: Variant = node.get_meta("occlusion_volumes", [])
			if not volumes is Array or (volumes as Array).is_empty():
				errors.append("missing_modular_occlusion_volumes:" + id)
				continue
			if node.has_meta("reveal_variant_path") or node.has_meta("reveal_full_path"):
				errors.append("primitive_fade_policy_conflict:" + id)
				continue
			var malformed := false
			for volume: Variant in volumes:
				var invalid := PrimitiveFadeScript._validate_volume(volume)
				if not invalid.is_empty():
					errors.append(invalid + ":" + id)
					malformed = true
			if malformed:
				continue
			bindings.append(id)
	bindings.sort()
	return {"errors": errors, "bindings": bindings}


func _check_source_transform(source: Node2D, allows_position: bool, errors: Array[String]) -> void:
	var value := source.transform
	if source.is_set_as_top_level() or value.x != Vector2.RIGHT or value.y != Vector2.DOWN or not value.origin.is_finite() or (not allows_position and value.origin != Vector2.ZERO):
		errors.append("unsupported_native_transform:" + String(get_path_to(source)))


func _collect_bindings(node: Node, bindings: Dictionary, errors: Array[String]) -> void:
	if node.has_meta("binding_id"):
		var binding := String(node.get_meta("binding_id"))
		if binding.is_empty() or binding in bindings.values():
			errors.append("invalid_or_duplicate_native_binding:" + binding)
		bindings[String(get_path_to(node))] = binding
	for child: Node in node.get_children():
		_collect_bindings(child, bindings, errors)


## Only the native gameplay derivative is snapped. Registry actor feet keep
## their full per-tick precision; camera rounding belongs to presentation.
static func _pair(point: Vector2) -> Array:
	return [snappedf(point.x, 1.0 / 64.0), snappedf(point.y, 1.0 / 64.0)]


static func _rect(rect: Rect2) -> Array:
	return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]
