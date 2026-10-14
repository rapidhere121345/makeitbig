class_name TownSceneRoot
extends Node2D

## Native town author source. Geometry, sockets and routes live in this scene;
## its six-field manifest is a detached offline derivative checked before READY.
const SpatialManifestScript := preload("res://src/runtime/world/spatial_manifest.gd")
const GROUPS: Array[String] = ["Ground", "GroundEffects", "SortRoot", "Foreground", "GeometrySources", "Sockets"]
const LAYERS_MANIFEST := "res://content/rooms/town/layers/manifest.json"

@export var world_size := Vector2(1536, 960)
@export var view_size := Vector2(640, 360)
@export var hero_screen_anchor := Vector2(320, 222)
@export var hero_radius := 6.0
@export var scene_id := "town.hearthside"
@export var world_asset_id := "town/hearthside"
@export var gameplay_source := "hearthside.spatial.json"
@export var presentation_source := "town_presenter"


func bind_native_art() -> Array[String]:
	var errors: Array[String] = []
	for group: String in ["Ground", "SortRoot"]:
		var parent := get_node_or_null(group)
		if parent == null:
			errors.append("missing_native_group:" + group)
			continue
		for node: Node in parent.get_children():
			if not node is Sprite2D:
				errors.append("invalid_native_visual:" + String(node.name))
				continue
			var path := String(node.get_meta("texture_path", ""))
			var texture: Texture2D
			if ResourceLoader.exists(path):
				texture = load(path) as Texture2D
			if texture == null and FileAccess.file_exists(path):
				var decoded := Image.new()
				if decoded.load(path) == OK:
					texture = ImageTexture.create_from_image(decoded)
			if texture == null:
				errors.append("missing_native_texture:" + path)
			else:
				(node as Sprite2D).texture = texture
				(node as Sprite2D).texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return errors


func validate_contract(expected: Dictionary = {}) -> Dictionary:
	var errors: Array[String] = []
	for group: String in GROUPS:
		if not get_node_or_null(group) is Node2D:
			errors.append("missing_native_group:" + group)
	errors.append_array(_spatial_source_errors())
	if not errors.is_empty():
		return {"ok": false, "errors": errors, "value": {}}
	if scene_id.is_empty() or world_asset_id.is_empty() or gameplay_source.is_empty() or presentation_source.is_empty():
		errors.append("invalid_town_identity")
	var layer_value: Variant = JSON.parse_string(FileAccess.get_file_as_string(LAYERS_MANIFEST)) if FileAccess.file_exists(LAYERS_MANIFEST) else null
	if not _has_static_layer_policy(layer_value):
		errors.append("invalid_town_layer_manifest")
	errors.append_array(bind_native_art())
	if not errors.is_empty():
		return {"ok": false, "errors": errors, "value": {}}
	var spatial := derive_spatial_manifest()
	var manifest = SpatialManifestScript.new(spatial)
	errors.append_array(manifest.validate())
	var bindings := {}
	for group: String in GROUPS:
		_collect_bindings(get_node(group), bindings, errors)
	var contract := {
		"scene_id": scene_id, "world_asset_id": world_asset_id, "gameplay_source": gameplay_source,
		"presentation_source": presentation_source, "groups": GROUPS.duplicate(), "bindings": bindings,
		"movement_binding": "town/movement-boundary", "authored_bounds": Rect2(Vector2.ZERO, world_size),
		"spatial_manifest": manifest.snapshot(), "unknown_underplate": "transparent", "supports_cutaway": false, "supports_fade": false,
	}
	for key: String in expected:
		if contract.has(key) and contract[key] != expected[key]:
			errors.append("native_contract_mismatch:" + key)
	return {"ok": errors.is_empty(), "errors": errors, "value": contract}


func derive_spatial_manifest() -> Dictionary:
	var errors := _spatial_source_errors()
	if not errors.is_empty():
		return {"ok": false, "errors": errors, "value": {}}
	var bindings: Array[Dictionary] = []
	var boundary: Rect2 = get_node("GeometrySources/MovementBoundary").get_meta("rect", Rect2())
	bindings.append({"binding_id": "town/movement-boundary", "source": "town.native.v1", "geometry": {"type": "rect", "rect": _rect(boundary)},
		"channels": {"movement": true, "navigation": true, "vision": false, "projectile": false, "occlusion": false}})
	for group: String in ["Ground", "SortRoot"]:
		for node: Node2D in get_node(group).get_children():
			bindings.append({"binding_id": String(node.get_meta("binding_id", "")), "kind": "native_visual", "channels": {"occlusion": group == "SortRoot"}})
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
	var routes := {}
	for route: Node2D in get_node("GeometrySources/Routes").get_children():
		var points: Array = []
		for point: Marker2D in route.get_children():
			points.append(_pair(point.position))
		routes[String(route.name)] = points
	return {"coordinate_convention": {"units": "design_pixel", "up": "negative_y", "scale": 1.0},
		"stable_bindings": bindings, "traversal_profiles": [], "regions_and_portals": [], "spawn_interaction_exit_sockets": sockets,
		"gameplay_spatial_metadata": {"room_kind": "town", "geometry_source": "town.native.v1", "coordinate_precision": 1.0 / 64.0, "world_size": _pair(world_size),
			"view_size": _pair(view_size), "hero_screen_anchor": _pair(hero_screen_anchor), "hero_radius": hero_radius,
			"facilities": facilities, "residents": residents, "routes": routes, "static_geometry": geometry}}


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


static func _has_static_layer_policy(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	return value.get("unknown_underplate", "") == "transparent" and value.get("supports_cutaway", null) is bool and value.supports_cutaway == false and value.get("supports_fade", null) is bool and value.supports_fade == false


## Only the native gameplay derivative is snapped. Registry actor feet keep
## their full per-tick precision; camera rounding belongs to presentation.
static func _pair(point: Vector2) -> Array:
	return [snappedf(point.x, 1.0 / 64.0), snappedf(point.y, 1.0 / 64.0)]


static func _rect(rect: Rect2) -> Array:
	return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]
