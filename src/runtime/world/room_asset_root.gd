class_name RoomAssetRoot
extends Node2D

## Native authoring contract for a room scene.
##
## The root scene still owns its presentation nodes and prefab children. This
## Geometry and sockets are authored here. SpatialManifest is derived from this
## scene-owned source contract; the component never owns simulation state.

const ArenaGeometryScript := preload("res://src/runtime/geometry/arena_geometry.gd")
const GEOMETRY_SOURCE := "arena.geometry.v1"
const COORDINATE_CONVENTION := {"units": "design_pixel", "up": "negative_y", "scale": 1.0}
const MOVEMENT_CHANNELS := {"movement": true, "navigation": true, "vision": true, "projectile": true, "occlusion": false}
## Authored static blockers follow the same generic `static_blocker` contract
## as the native sample rooms: convex polygons authored under
## GeometrySources/Static. A wall-shaped blocker also stops projectiles; a low
## pier only blocks movement. Occlusion stays presentation-side (art boxes).
const STATIC_SOURCE := "arena.static.convex.v1"
const BLOCKER_WALL_CHANNELS := {"movement": true, "navigation": false, "vision": false, "projectile": true, "occlusion": false}
const BLOCKER_LOW_CHANNELS := {"movement": true, "navigation": false, "vision": false, "projectile": false, "occlusion": false}
const BLOCKER_CHANNEL_SETS: Array[Dictionary] = [BLOCKER_WALL_CHANNELS, BLOCKER_LOW_CHANNELS]

const REQUIRED_GROUPS: Array[String] = [
	"Ground",
	"GroundEffects",
	"SortRoot",
	"Foreground",
	"GeometrySources",
	"Sockets",
]
const REQUIRED_BINDINGS := {
	"Ground/Surface": "ground.surface",
	"GeometrySources/MovementBoundary": "combat/movement-boundary",
	"Sockets/CombatSpawn": "combat/spawn",
	"Sockets/EncounterOrigin": "combat/encounter-origin",
}
const REQUIRED_NODE_TYPES := {
	"Ground/Surface": "Node2D",
	"GeometrySources/MovementBoundary": "Node2D",
	"Sockets/CombatSpawn": "Marker2D",
	"Sockets/EncounterOrigin": "Marker2D",
}

@export var scene_id: String = ""
@export var layout_id: String = ""
@export var gameplay_source: String = ""
@export var presentation_source: String = ""
@export var arena_rect: Rect2 = Rect2()
@export var traversal_radius: float = 0.0


func validate_contract(expected: Dictionary = {}) -> Dictionary:
	var errors: Array[String] = []
	if scene_id.strip_edges().is_empty():
		errors.append("missing_scene_id")
	if layout_id.strip_edges().is_empty():
		errors.append("missing_layout_id")
	if gameplay_source.strip_edges().is_empty():
		errors.append("missing_gameplay_source")
	if presentation_source.strip_edges().is_empty():
		errors.append("missing_presentation_source")
	var native_kind := ArenaGeometryScript.expected_native_kind_for_layout(layout_id)
	if native_kind.is_empty():
		errors.append("unknown_layout_id")
	if scene_id.strip_edges() != "combat.%s" % layout_id.strip_edges():
		errors.append("scene_layout_identity_mismatch")
	if transform != Transform2D.IDENTITY:
		errors.append("unsupported_room_asset_transform")
	if not arena_rect.position.is_finite() or not arena_rect.size.is_finite() or arena_rect.size.x <= 0.0 or arena_rect.size.y <= 0.0:
		errors.append("invalid_authored_arena_rect")
	if not is_finite(traversal_radius) or traversal_radius <= 0.0:
		errors.append("invalid_traversal_radius")
	for group_name: String in REQUIRED_GROUPS:
		var group_node := get_node_or_null(group_name)
		if group_node == null:
			errors.append("missing_group:%s" % group_name)
		elif not group_node is Node2D:
			errors.append("invalid_group_type:%s" % group_name)
		elif group_name in ["GeometrySources", "Sockets"] and (group_node as Node2D).transform != Transform2D.IDENTITY:
			errors.append("unsupported_group_transform:%s" % group_name)
	var sort_root := get_node_or_null("SortRoot") as Node2D
	if sort_root != null and not sort_root.y_sort_enabled:
		errors.append("sort_root_not_y_sorted")
	for node_path: String in REQUIRED_BINDINGS:
		var binding_node := get_node_or_null(node_path)
		if binding_node == null:
			errors.append("missing_binding_node:%s" % node_path)
			continue
		var expected_type := String(REQUIRED_NODE_TYPES.get(node_path, "Node"))
		if not binding_node.is_class(expected_type):
			errors.append("invalid_binding_type:%s" % node_path)
		var binding_id := String(binding_node.get_meta("binding_id", ""))
		if binding_id != REQUIRED_BINDINGS[node_path]:
			errors.append("invalid_binding:%s" % node_path)
	var geometry_node := get_node_or_null("GeometrySources/MovementBoundary") as Node2D
	var boundary: Dictionary = {}
	if geometry_node != null:
		if geometry_node.transform != Transform2D.IDENTITY:
			errors.append("unsupported_geometry_transform")
		if geometry_node.get_meta("source", null) != GEOMETRY_SOURCE:
			errors.append("invalid_geometry_source")
		if geometry_node.get_meta("channels", null) != MOVEMENT_CHANNELS:
			errors.append("invalid_geometry_channels")
		var normalized := ArenaGeometryScript.normalize_native_boundary(geometry_node.get_meta("geometry", null))
		if not bool(normalized.get("ok", false)):
			errors.append("invalid_authored_geometry:%s" % String(normalized.get("error", "unknown")))
		else:
			boundary = normalized["value"]
			if String(boundary["type"]) != native_kind:
				errors.append("geometry_layout_mismatch")
			if ArenaGeometryScript.from_native_boundary(boundary, arena_rect, 0.0).is_empty():
				errors.append("geometry_arena_rect_mismatch")
	var geometry_sources := get_node_or_null("GeometrySources")
	if geometry_sources != null:
		var source_names: Array[String] = []
		for child: Node in geometry_sources.get_children():
			source_names.append(String(child.name))
		var allowed_sources: Array[String] = ["MovementBoundary"]
		if get_node_or_null("GeometrySources/Static") != null:
			allowed_sources.append("Static")
		for source_name: String in source_names:
			if not allowed_sources.has(source_name):
				errors.append("unexpected_geometry_sources:%s" % source_name)
	var blockers: Array[Dictionary] = _validated_static_blockers(errors)
	for socket_path: String in ["Sockets/CombatSpawn", "Sockets/EncounterOrigin"]:
		var socket := get_node_or_null(socket_path) as Marker2D
		if socket == null:
			continue
		for blocker: Dictionary in blockers:
			if not _point_clear_of_polygon(socket.position, blocker["points"], traversal_radius):
				errors.append("socket_footprint_blocked:%s:%s" % [socket_path, String(blocker["binding_id"])])
	var sockets := get_node_or_null("Sockets")
	if sockets != null and sockets.get_child_count() != 2:
		errors.append("unexpected_spawn_sockets")
	for socket_path: String in ["Sockets/CombatSpawn", "Sockets/EncounterOrigin"]:
		var socket := get_node_or_null(socket_path) as Marker2D
		if socket == null:
			continue
		if not socket.position.is_finite() or not is_zero_approx(socket.rotation) or socket.scale != Vector2.ONE or not is_zero_approx(socket.skew):
			errors.append("invalid_socket_transform:%s" % socket_path)
		if socket.get_meta("kind", null) != "spawn":
			errors.append("invalid_socket_kind:%s" % socket_path)
		if socket_path == "Sockets/CombatSpawn" and not ArenaGeometryScript.native_position_clear(socket.position, boundary, traversal_radius):
			errors.append("spawn_socket_outside_geometry")
		if socket_path == "Sockets/EncounterOrigin" and not arena_rect.has_point(socket.position):
			errors.append("encounter_origin_outside_arena")
	var expected_scene_id := String(expected.get("scene_id", "")).strip_edges()
	var expected_layout_id := String(expected.get("layout_id", "")).strip_edges()
	var expected_gameplay_source := String(expected.get("gameplay_source", "")).strip_edges()
	var expected_presentation_source := String(expected.get("presentation_source", "")).strip_edges()
	if not expected_scene_id.is_empty() and scene_id.strip_edges() != expected_scene_id:
		errors.append("scene_id_mismatch")
	if not expected_layout_id.is_empty() and layout_id.strip_edges() != expected_layout_id:
		errors.append("layout_id_mismatch")
	if not expected_gameplay_source.is_empty() and gameplay_source.strip_edges() != expected_gameplay_source:
		errors.append("gameplay_source_mismatch")
	if not expected_presentation_source.is_empty() and presentation_source.strip_edges() != expected_presentation_source:
		errors.append("presentation_source_mismatch")
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"value": snapshot() if errors.is_empty() else {},
	}


func snapshot() -> Dictionary:
	var bindings := REQUIRED_BINDINGS.duplicate(true)
	var static_container := get_node_or_null("GeometrySources/Static") as Node2D
	if static_container != null:
		for child: Node in static_container.get_children():
			var blocker_id := String(child.get_meta("binding_id", ""))
			if not blocker_id.is_empty():
				bindings["GeometrySources/Static/%s" % String(child.name)] = blocker_id
	return {
		"scene_id": scene_id.strip_edges(),
		"world_asset_id": "combat/%s" % layout_id.strip_edges(),
		"layout_id": layout_id.strip_edges(),
		"gameplay_source": gameplay_source.strip_edges(),
		"presentation_source": presentation_source.strip_edges(),
		"groups": REQUIRED_GROUPS.duplicate(),
		"bindings": bindings,
		"movement_binding": "combat/movement-boundary",
		"authored_bounds": arena_rect,
		"spatial_manifest": derive_spatial_manifest(),
	}


## Deterministic JSON-safe build contract. Call validate_contract() before using
## this output; no manifest is loaded or patched into the native authoring data.
func derive_spatial_manifest() -> Dictionary:
	var geometry_node := get_node_or_null("GeometrySources/MovementBoundary") as Node2D
	var player_socket := get_node_or_null("Sockets/CombatSpawn") as Marker2D
	var encounter_socket := get_node_or_null("Sockets/EncounterOrigin") as Marker2D
	if geometry_node == null or player_socket == null or encounter_socket == null:
		return {}
	var result := ArenaGeometryScript.normalize_native_boundary(geometry_node.get_meta("geometry", null))
	if not bool(result.get("ok", false)):
		return {}
	var bindings: Array[Dictionary] = [{
		"binding_id": String(geometry_node.get_meta("binding_id", "")),
		"channels": geometry_node.get_meta("channels", {}).duplicate(true),
		"source": String(geometry_node.get_meta("source", "")),
		"geometry": _boundary_data(result["value"]),
	}]
	for blocker: Dictionary in _authored_static_blockers():
		bindings.append({
			"binding_id": String(blocker["binding_id"]),
			"kind": "static_blocker",
			"source": STATIC_SOURCE,
			"channels": (blocker["channels"] as Dictionary).duplicate(true),
			"geometry": {"type": "polygon", "points": (blocker["points"] as Array).duplicate(true)},
		})
	return {
		"coordinate_convention": COORDINATE_CONVENTION.duplicate(true),
		"stable_bindings": bindings,
		"traversal_profiles": [{"profile_id": "standard", "radius": traversal_radius}],
		"regions_and_portals": [{"region_id": "combat", "portals": []}],
		"spawn_interaction_exit_sockets": [
			_socket_data(encounter_socket),
			_socket_data(player_socket),
		],
		"gameplay_spatial_metadata": {
			"room_kind": "combat",
			"layout_id": layout_id.strip_edges(),
			"geometry_source": GEOMETRY_SOURCE,
			"authored_arena_rect": [arena_rect.position.x, arena_rect.position.y, arena_rect.size.x, arena_rect.size.y],
		},
	}


func _socket_data(socket: Marker2D) -> Dictionary:
	return {"socket_id": String(socket.get_meta("binding_id", "")), "kind": String(socket.get_meta("kind", "")), "position": [socket.position.x, socket.position.y]}


## Reads the authored blocker children without validating them; pairing this
## with _validated_static_blockers() keeps authoring and validation on the same
## node contract.
func _authored_static_blockers() -> Array[Dictionary]:
	var blockers: Array[Dictionary] = []
	var static_container := get_node_or_null("GeometrySources/Static") as Node2D
	if static_container == null:
		return blockers
	for child: Node in static_container.get_children():
		var polygon := child as Polygon2D
		if polygon == null:
			continue
		var points: Array = []
		for point: Vector2 in polygon.polygon:
			var absolute := point + polygon.position
			points.append([absolute.x, absolute.y])
		blockers.append({
			"binding_id": String(polygon.get_meta("binding_id", "")),
			"channels": polygon.get_meta("channels", {}).duplicate(true),
			"points": points,
		})
	return blockers


## Validates every authored blocker and returns the normalized blockers. Each
## bad node appends to errors instead of returning early, so one authoring
## pass reports every mistake at once.
func _validated_static_blockers(errors: Array[String]) -> Array[Dictionary]:
	var blockers: Array[Dictionary] = []
	var static_container := get_node_or_null("GeometrySources/Static") as Node2D
	if static_container == null:
		return blockers
	if static_container.transform != Transform2D.IDENTITY:
		errors.append("unsupported_static_container_transform")
	var seen_ids: Dictionary = {}
	for child: Node in static_container.get_children():
		var polygon := child as Polygon2D
		if polygon == null:
			errors.append("invalid_static_source:%s" % String(child.name))
			continue
		var node_name := String(polygon.name)
		if polygon.is_set_as_top_level() or polygon.transform.x != Vector2.RIGHT or polygon.transform.y != Vector2.DOWN or not polygon.position.is_finite():
			errors.append("unsupported_static_transform:%s" % node_name)
		if polygon.offset != Vector2.ZERO or polygon.get_child_count() != 0:
			errors.append("unsupported_static_source:%s" % node_name)
		var binding_id := String(polygon.get_meta("binding_id", ""))
		if binding_id.is_empty() or seen_ids.has(binding_id):
			errors.append("invalid_static_binding_id:%s" % node_name)
		seen_ids[binding_id] = true
		if polygon.get_meta("source", null) != STATIC_SOURCE:
			errors.append("invalid_static_source_meta:%s" % node_name)
		var channels: Variant = polygon.get_meta("channels", null)
		if not BLOCKER_CHANNEL_SETS.has(channels):
			errors.append("invalid_static_channels:%s" % node_name)
		var points: Array = []
		for point: Vector2 in polygon.polygon:
			var absolute := point + polygon.position
			points.append([absolute.x, absolute.y])
		var normalized := ArenaGeometryScript.normalize_native_static_geometry({"type": "polygon", "points": points})
		if not bool(normalized.get("ok", false)):
			errors.append("invalid_static_polygon:%s" % node_name)
			continue
		blockers.append({
			"binding_id": binding_id,
			"channels": channels if channels is Dictionary else {},
			"points": points,
		})
	return blockers


## Footprint-aware clearance for a point against one convex polygon: inside the
## polygon or within radius of any edge counts as blocked.
func _point_clear_of_polygon(point: Vector2, points: Array, radius: float) -> bool:
	if points.size() < 3:
		return false
	var absolute := PackedVector2Array()
	for pair: Variant in points:
		absolute.append(Vector2(float((pair as Array)[0]), float((pair as Array)[1])))
	if Geometry2D.is_point_in_polygon(point, absolute):
		return false
	var count := absolute.size()
	for index: int in count:
		var edge_start := absolute[index]
		var edge_end := absolute[(index + 1) % count]
		if _distance_to_segment(point, edge_start, edge_end) < radius:
			return false
	return true


func _distance_to_segment(point: Vector2, start: Vector2, end: Vector2) -> float:
	var segment := end - start
	var length_squared := segment.length_squared()
	if length_squared <= 0.0:
		return point.distance_to(start)
	var t := clampf((point - start).dot(segment) / length_squared, 0.0, 1.0)
	return point.distance_to(start + segment * t)


func _boundary_data(boundary: Dictionary) -> Dictionary:
	var result := boundary.duplicate(true)
	if result.has("rect"):
		var rect: Rect2 = result["rect"]
		result["rect"] = [rect.position.x, rect.position.y, rect.size.x, rect.size.y]
	if result.has("center"):
		var center: Vector2 = result["center"]
		result["center"] = [center.x, center.y]
	return result
