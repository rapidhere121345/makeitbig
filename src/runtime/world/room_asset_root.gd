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
	if geometry_sources != null and geometry_sources.get_child_count() != 1:
		errors.append("unexpected_geometry_sources")
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
	return {
		"scene_id": scene_id.strip_edges(),
		"world_asset_id": "combat/%s" % layout_id.strip_edges(),
		"layout_id": layout_id.strip_edges(),
		"gameplay_source": gameplay_source.strip_edges(),
		"presentation_source": presentation_source.strip_edges(),
		"groups": REQUIRED_GROUPS.duplicate(),
		"bindings": REQUIRED_BINDINGS.duplicate(true),
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
	return {
		"coordinate_convention": COORDINATE_CONVENTION.duplicate(true),
		"stable_bindings": [{
			"binding_id": String(geometry_node.get_meta("binding_id", "")),
			"channels": geometry_node.get_meta("channels", {}).duplicate(true),
			"source": String(geometry_node.get_meta("source", "")),
			"geometry": _boundary_data(result["value"]),
		}],
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


func _boundary_data(boundary: Dictionary) -> Dictionary:
	var result := boundary.duplicate(true)
	if result.has("rect"):
		var rect: Rect2 = result["rect"]
		result["rect"] = [rect.position.x, rect.position.y, rect.size.x, rect.size.y]
	if result.has("center"):
		var center: Vector2 = result["center"]
		result["center"] = [center.x, center.y]
	return result
