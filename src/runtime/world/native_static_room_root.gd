class_name NativeStaticRoomRoot
extends Node2D

## Declarative native room source: one outer boundary, authored convex solids,
## and footprint-safe sockets. It owns no actor, motor, clock or runtime state.
const Arena := preload("res://src/runtime/geometry/arena_geometry.gd")
const Spatial := preload("res://src/runtime/world/spatial_manifest.gd")
const Query := preload("res://src/runtime/geometry/geometry_query.gd")
const GROUPS: Array[String] = ["Ground", "GroundEffects", "SortRoot", "Foreground", "GeometrySources", "Sockets"]
const CHANNELS := {"movement": true, "navigation": false, "vision": false, "projectile": false, "occlusion": false}

@export var scene_id := ""
@export var world_asset_id := ""
@export var gameplay_source := ""
@export var presentation_source := "native_scene"
@export var authored_bounds := Rect2()
@export var traversal_radius := 10.0


func validate_contract(expected: Dictionary = {}) -> Dictionary:
	var sources := _derive_sources()
	if not bool(sources.ok):
		return {"ok": false, "errors": sources.errors, "value": {}}
	var bindings := {}
	var errors: Array[String] = []
	_collect_bindings(self, bindings, errors)
	var contract := {
		"scene_id": scene_id, "world_asset_id": world_asset_id,
		"gameplay_source": gameplay_source, "presentation_source": presentation_source,
		"groups": GROUPS.duplicate(), "bindings": bindings,
		"movement_binding": String(get_node("GeometrySources/MovementBoundary").get_meta("binding_id")),
		"authored_bounds": authored_bounds, "spatial_manifest": sources.value,
	}
	for key: String in expected:
		if not contract.has(key) or contract[key] != expected[key]:
			errors.append("native_contract_mismatch:" + key)
	return {"ok": errors.is_empty(), "errors": errors, "value": contract if errors.is_empty() else {}}


func derive_spatial_manifest() -> Dictionary:
	var result := _derive_sources()
	return result.value if bool(result.ok) else {"ok": false, "errors": result.errors, "value": {}}


func _derive_sources() -> Dictionary:
	var errors: Array[String] = []
	if scene_id.is_empty() or world_asset_id.is_empty() or gameplay_source.is_empty() or presentation_source.is_empty():
		errors.append("invalid_native_identity")
	if not authored_bounds.position.is_finite() or not authored_bounds.size.is_finite() or authored_bounds.size.x <= 0 or authored_bounds.size.y <= 0:
		errors.append("invalid_authored_bounds")
	if not is_finite(traversal_radius) or traversal_radius <= 0:
		errors.append("invalid_traversal_radius")
	_check_transform(self, false, errors)
	for path: String in GROUPS + ["GeometrySources/MovementBoundary", "GeometrySources/Static"]:
		var node := get_node_or_null(path) as Node2D
		if node == null:
			errors.append("missing_native_group:" + path)
		else:
			_check_transform(node, false, errors)
	if not get_node_or_null("Ground/Surface") is Polygon2D:
		errors.append("missing_native_surface")
	var sort_root := get_node_or_null("SortRoot") as Node2D
	if sort_root != null and not sort_root.y_sort_enabled:
		errors.append("sort_root_not_y_sorted")
	if not errors.is_empty():
		return _failure(errors)
	if get_node("GeometrySources").get_child_count() != 2:
		errors.append("unexpected_geometry_source")
	var boundary_node := get_node("GeometrySources/MovementBoundary")
	var boundary := Arena.normalize_native_boundary(boundary_node.get_meta("geometry", null))
	if not bool(boundary.ok) or Arena.from_native_boundary(boundary.get("value", {}), authored_bounds, 0.0).is_empty():
		errors.append("invalid_native_boundary")
	if boundary_node.get_meta("channels", null) != CHANNELS:
		errors.append("invalid_boundary_channels")
	var movement_id := String(boundary_node.get_meta("binding_id", ""))
	var entries: Array[Dictionary] = [{"binding_id": movement_id, "source": "native.boundary.v1", "channels": CHANNELS.duplicate(true), "geometry": boundary_node.get_meta("geometry", {}).duplicate(true)}]
	var query := Query.new()
	for child: Node in get_node("GeometrySources/Static").get_children():
		if not child is Polygon2D:
			errors.append("invalid_native_static_source:" + String(child.name))
			continue
		var polygon := child as Polygon2D
		_check_transform(polygon, true, errors)
		if polygon.offset != Vector2.ZERO or polygon.get_child_count() != 0:
			errors.append("unsupported_static_source:" + String(polygon.name))
		if polygon.get_meta("channels", null) != CHANNELS:
			errors.append("invalid_static_channels:" + String(polygon.name))
		var points: Array = []
		for point: Vector2 in polygon.polygon:
			points.append(_pair(point + polygon.position))
		var geometry := {"type": "polygon", "points": points}
		var solid := Arena.normalize_native_static_geometry(geometry)
		var id := String(polygon.get_meta("binding_id", ""))
		if not bool(solid.ok) or not query.register_polygon(id, solid.get("value", {}).get("points", PackedVector2Array())):
			errors.append("invalid_static_polygon:" + String(polygon.name))
		entries.append({"binding_id": id, "kind": "static_blocker", "source": "native.static.convex.v1", "channels": CHANNELS.duplicate(true), "geometry": geometry})
	var sockets: Array[Dictionary] = []
	var spawns := 0
	for child: Node in get_node("Sockets").get_children():
		if not child is Marker2D:
			errors.append("invalid_native_socket_source:" + String(child.name))
			continue
		var socket := child as Marker2D
		_check_transform(socket, true, errors)
		if socket.get_child_count() != 0:
			errors.append("unexpected_socket_child:" + String(socket.name))
		var kind := String(socket.get_meta("kind", ""))
		if kind not in Spatial.SOCKET_KINDS:
			errors.append("invalid_socket_kind:" + String(socket.name))
		if kind == "spawn":
			spawns += 1
		if not bool(boundary.ok) or not Arena.native_position_clear(socket.position, boundary.get("value", {}), traversal_radius) or not query.is_position_clear(socket.position, traversal_radius):
			errors.append("socket_footprint_blocked:" + String(socket.name))
		sockets.append({"socket_id": String(socket.get_meta("binding_id", "")), "kind": kind, "position": _pair(socket.position)})
	if spawns == 0:
		errors.append("missing_spawn_socket")
	var payload := {
		"coordinate_convention": {"units": "design_pixel", "up": "negative_y", "scale": 1.0},
		"stable_bindings": entries, "traversal_profiles": [{"profile_id": "standard", "radius": traversal_radius}],
		"regions_and_portals": [], "spawn_interaction_exit_sockets": sockets,
		"gameplay_spatial_metadata": {"geometry_source": "native.static.convex.v1"},
	}
	errors.append_array(Spatial.validate_data(payload))
	return {"ok": errors.is_empty(), "errors": errors, "value": payload if errors.is_empty() else {}}


func _check_transform(node: Node2D, permits_position: bool, errors: Array[String]) -> void:
	var value := node.transform
	if node.is_set_as_top_level() or value.x != Vector2.RIGHT or value.y != Vector2.DOWN or not value.origin.is_finite() or (not permits_position and value.origin != Vector2.ZERO):
		errors.append("unsupported_native_transform:" + String(get_path_to(node)))


func _collect_bindings(node: Node, bindings: Dictionary, errors: Array[String]) -> void:
	if node.has_meta("binding_id"):
		var id := String(node.get_meta("binding_id"))
		if id.is_empty() or id in bindings.values():
			errors.append("invalid_or_duplicate_native_binding:" + id)
		bindings[String(get_path_to(node))] = id
	for child: Node in node.get_children():
		_collect_bindings(child, bindings, errors)


static func _pair(point: Vector2) -> Array:
	return [point.x, point.y]


static func _failure(errors: Array[String]) -> Dictionary:
	return {"ok": false, "errors": errors, "value": {}}
