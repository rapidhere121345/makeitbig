class_name RoomGeometry
extends RefCounted

## Arena geometry queries extracted from MainArena: arena rect, walkable and
## collision geometry, sockets, clamping and spawn projection. MainArena keeps
## thin forwarders for the queries that tests and Callable bindings address
## by name; room state stays owned by MainArena.

const ArenaGeometryScript = preload("res://src/runtime/geometry/arena_geometry.gd")

var _main: MainArena


func _init(main: MainArena) -> void:
	_main = main


func _arena_rect() -> Rect2:
	if _main.scene_runtime != null:
		var authored: Variant = _main.scene_runtime.get("authored_arena_rect")
		return authored as Rect2 if authored is Rect2 else Rect2()
	return Rect2(Vector2(MainArena.ARENA_MARGIN, 190.0), Vector2(
		MainArena.AUTHORITY_VIEWPORT_SIZE.x - MainArena.ARENA_MARGIN * 2.0,
		MainArena.AUTHORITY_VIEWPORT_SIZE.y - 190.0 - MainArena.ARENA_MARGIN))


func _walkable_geometry(padding: float) -> Dictionary:
	var geometry: Dictionary = {}
	if _main.scene_runtime != null:
		var native_boundary: Variant = _main.scene_runtime.get("movement_boundary")
		if native_boundary is Dictionary:
			geometry = ArenaGeometryScript.from_native_boundary(native_boundary, _arena_rect(), padding)
	else:
		geometry = ArenaGeometryScript.from_layout(_main.layout_id, _arena_rect(), padding)
	var normalized: Dictionary = ArenaGeometryScript.normalize(geometry)
	return (normalized.get("value", {}) as Dictionary).duplicate(true) if bool(normalized.get("ok", false)) else {}


func _presentation_geometry() -> Dictionary:
	var boundary: Dictionary = {}
	if _main.scene_runtime != null:
		var native_boundary: Variant = _main.scene_runtime.get("movement_boundary")
		if native_boundary is Dictionary:
			boundary = (native_boundary as Dictionary).duplicate(true)
	else:
		boundary = ArenaGeometryScript.movement_boundary(_main.layout_id, _arena_rect())
	if not boundary.is_empty():
		var native_geometry := ArenaGeometryScript.from_native_boundary(boundary, _arena_rect(), 0.0)
		if not native_geometry.is_empty():
			return native_geometry
	return ArenaGeometryScript.from_layout(_main.layout_id, _arena_rect(), 0.0)


func _collision_geometry(radius: float) -> Dictionary:
	if not is_finite(radius) or radius < 0.0:
		return {}
	var boundary: Dictionary = {}
	if _main.scene_runtime != null:
		var native_boundary: Variant = _main.scene_runtime.get("movement_boundary")
		if native_boundary is Dictionary:
			boundary = (native_boundary as Dictionary).duplicate(true)
	else:
		boundary = ArenaGeometryScript.movement_boundary(_main.layout_id, _arena_rect())
	return ArenaGeometryScript.from_native_boundary_for_footprint(boundary, _arena_rect(), radius)


## Bounding circles of the authored static blockers in the mounted room's
## movement channel. Standalone fixtures without a mounted registry have no
## authored blockers and steer on the boundary geometry alone.
func _static_blocker_bounds() -> Array[Dictionary]:
	if _main.actor_registry == null:
		return []
	return _main.actor_registry.static_blocker_bounds()


func _room_socket(binding: String) -> Variant:
	if _main.scene_runtime == null:
		return null
	var sockets: Variant = _main.scene_runtime.get("spawn_socket_bindings")
	if not sockets is Array:
		return null
	for socket: Dictionary in sockets:
		if String(socket.get("binding", "")) == binding:
			return socket.get("position")
	return null


func _clamp_to_arena(value: Vector2, padding: float) -> Vector2:
	var projected: Dictionary = ArenaGeometryScript.project(value, _walkable_geometry(padding))
	if not bool(projected.get("ok", false)) or not projected.get("position", null) is Vector2:
		var projection_error := "walkable_geometry_projection_failed: %s" % String(projected.get("error", "invalid_position"))
		push_error(projection_error)
		assert(false, projection_error)
		return value
	return projected.position


func _project_actor_spawn_position(value: Vector2, radius: float) -> Dictionary:
	## Initialization uses the same footprint-aware limits as ActorMotor. Once a
	## room is live, all further displacement is submitted through the registry.
	if not value.is_finite() or not is_finite(radius) or radius <= 0.0:
		return {"ok": false, "error": "invalid_spawn_footprint"}
	var geometry := _collision_geometry(radius)
	if geometry.is_empty():
		return {"ok": false, "error": "spawn_geometry_unavailable"}
	var projected: Dictionary = ArenaGeometryScript.project(value, geometry)
	if not bool(projected.get("ok", false)):
		return {"ok": false, "error": "spawn_projection_failed:%s" % String(projected.get("error", "invalid_geometry"))}
	var position := Vector2(projected["position"])
	if _main.actor_registry != null:
		var static_clear: Variant = _project_static_clear(position, radius)
		if static_clear == null:
			return {"ok": false, "error": "spawn_static_projection_failed"}
		position = static_clear
	return {"ok": true, "position": position}


## Authored static blockers and already registered actors own spawn clearance.
## Deterministic expanding-ring search around the boundary-projected point: the
## first clear candidate wins in a fixed ring/step order, so fixed-tick replays
## stay byte-stable. Returns null when no candidate inside the arena clears
## every static surface and live body, keeping the fail-closed contract.
func _project_static_clear(position: Vector2, radius: float) -> Variant:
	if _main.actor_registry.is_spawn_position_clear(position, radius):
		return position
	for ring: float in [16.0, 32.0, 48.0, 64.0, 96.0, 128.0, 160.0, 192.0, 224.0, 256.0]:
		for step: int in 16:
			var candidate := position + Vector2(ring, 0.0).rotated(TAU * float(step) / 16.0)
			if candidate.is_finite() and _main.actor_registry.is_spawn_position_clear(candidate, radius):
				return candidate
	return null


func _quantize_position(value: Vector2) -> Vector2:
	# Authority stores a 1/1000-pixel grid. Rendering may interpolate later, but
	# identical whole-tick commands always land on identical coordinates.
	return Vector2(snappedf(value.x, 0.001), snappedf(value.y, 0.001))


func _layout_spawn_offsets(id: String, count: int) -> Array[Vector2]:
	_main._ensure_room_catalog()
	var spawn_room_id := String(_main.encounter_director.room_id) if _main.encounter_director != null else _main.room_id
	if _main.room_catalog == null:
		return []
	return _main.room_catalog.spawn_offsets({"layout_id": id, "room_id": spawn_room_id}, count)
