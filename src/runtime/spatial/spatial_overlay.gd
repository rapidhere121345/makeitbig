class_name SpatialOverlay
extends RefCounted

## Runtime geometry overlay for gates, doors and destructibles.
##
## The overlay never mutates the baked static asset.  It owns added surfaces,
## plus suppression tombstones for baked surfaces (a destroyed pillar), and
## every successful mutation produces the next monotonic revision at a tick
## boundary.  Query services subtract suppressed ids from static results and
## add overlay surfaces of their own.

const Shape := preload("res://src/runtime/geometry/spatial_shape.gd")
const Sweep := preload("res://src/runtime/geometry/spatial_sweep.gd")
const Channels := preload("res://src/runtime/spatial/spatial_channels.gd")
const Contact := preload("res://src/runtime/spatial/spatial_contact.gd")
const StaticSpatialIndexScript := preload("res://src/runtime/spatial/static_spatial_index.gd")

const SURFACE_FIELDS: Array[String] = [
	"id",
	"shape",
	"channels",
	"opaque",
	"vision_mode",
	"attenuation",
	"occlusion_rank",
]

const OP_ADD_SURFACE: StringName = &"add_surface"
const OP_REMOVE_SURFACE: StringName = &"remove_surface"
const OP_SUPPRESS_STATIC: StringName = &"suppress_static"
const OP_RESTORE_STATIC: StringName = &"restore_static"

var _surfaces: Dictionary = {}
var _suppressed: Dictionary = {}
var _revision := 0
## Geometry changes are requests until the room's fixed movement boundary
## commits them.  A query can therefore only observe one complete overlay
## revision for the whole tick.
var _pending_operations: Array[Dictionary] = []
var _last_committed_tick := -1


func add_surface(surface: Variant) -> Dictionary:
	return queue_add_surface(surface)


## Queues a runtime surface for the next committed tick boundary.
func queue_add_surface(surface: Variant) -> Dictionary:
	var normalized := _normalize_surface(surface)
	if not bool(normalized["ok"]):
		return {"ok": false, "errors": normalized["errors"], "revision": _revision}
	var stored: Dictionary = normalized["value"]
	_pending_operations.append({
		"kind": OP_ADD_SURFACE,
		"surface": stored.duplicate(true),
	})
	return _queued_result()


func remove_surface(surface_id: String) -> Dictionary:
	return queue_remove_surface(surface_id)


## Queues removal for the next committed tick boundary.
func queue_remove_surface(surface_id: String) -> Dictionary:
	_pending_operations.append({
		"kind": OP_REMOVE_SURFACE,
		"surface_id": surface_id,
	})
	return _queued_result()


## Suppresses one baked static surface, for example a destroyed destructible.
func suppress_static(surface_id: String) -> Dictionary:
	return queue_suppress_static(surface_id)


## Queues suppression of a baked surface for the next committed tick boundary.
func queue_suppress_static(surface_id: String) -> Dictionary:
	_pending_operations.append({
		"kind": OP_SUPPRESS_STATIC,
		"surface_id": surface_id,
	})
	return _queued_result()


func restore_static(surface_id: String) -> Dictionary:
	return queue_restore_static(surface_id)


## Queues restoration of a suppressed baked surface for the next committed
## tick boundary.
func queue_restore_static(surface_id: String) -> Dictionary:
	_pending_operations.append({
		"kind": OP_RESTORE_STATIC,
		"surface_id": surface_id,
	})
	return _queued_result()


## Applies all queued geometry changes in submission order at one fixed tick
## boundary.  The tick stamp prevents a caller from mutating query state twice
## during one tick or from applying a late request in an already-read tick.
func commit_pending(at_tick: int) -> Dictionary:
	if at_tick < 0:
		return {
			"ok": false,
			"error": "overlay:invalid_tick",
			"errors": ["overlay:invalid_tick"],
			"revision": _revision,
			"tick": at_tick,
			"had_pending": not _pending_operations.is_empty(),
			"operations": [],
		}
	if at_tick <= _last_committed_tick:
		return {
			"ok": false,
			"error": "overlay:stale_tick",
			"errors": ["overlay:stale_tick"],
			"revision": _revision,
			"tick": at_tick,
			"had_pending": not _pending_operations.is_empty(),
			"operations": [],
		}
	var pending := _pending_operations
	_pending_operations = []
	_last_committed_tick = at_tick
	var operations: Array[Dictionary] = []
	var all_ok := true
	for operation: Dictionary in pending:
		var result := _apply_operation(operation)
		result["kind"] = operation.get("kind", &"")
		operations.append(result)
		if not bool(result.get("ok", false)):
			all_ok = false
	return {
		"ok": all_ok,
		"error": "" if all_ok else "overlay:operation_failed",
		"errors": _operation_errors(operations),
		"revision": _revision,
		"tick": at_tick,
		"had_pending": not pending.is_empty(),
		"operations": operations,
	}


func pending_operation_count() -> int:
	return _pending_operations.size()


func last_committed_tick() -> int:
	return _last_committed_tick


func revision() -> int:
	return _revision


func surface_ids() -> Array[String]:
	var ids: Array[String] = []
	for key: Variant in _surfaces.keys():
		ids.append(String(key))
	ids.sort()
	return ids


func suppressed_ids() -> Array[String]:
	var ids: Array[String] = []
	for key: Variant in _suppressed.keys():
		ids.append(String(key))
	ids.sort()
	return ids


func is_suppressed(surface_id: String) -> bool:
	return _suppressed.has(surface_id)


func surface(surface_id: String) -> Dictionary:
	return (_surfaces.get(surface_id, {}) as Dictionary).duplicate(true)


## Fail-closed room-assembly check: suppressed ids must exist in the baked
## asset and overlay ids must not collide with baked ids.
func validate_against(static_index: Variant) -> Array[String]:
	var errors: Array[String] = []
	if not static_index is StaticSpatialIndexScript:
		return ["overlay:invalid_static_index"]
	var index: StaticSpatialIndex = static_index
	for surface_id: String in suppressed_ids():
		if index.surface(surface_id).is_empty():
			errors.append("overlay.suppressed:unknown_static_surface:%s" % surface_id)
	for surface_id: String in surface_ids():
		if not index.surface(surface_id).is_empty():
			errors.append("overlay.surface:id_collides_with_static:%s" % surface_id)
	return errors


func sweep(channel: StringName, start: Vector2, displacement: Vector2, radius: float) -> Array:
	var contacts: Array = []
	if not Channels.is_valid(channel) or not (start.is_finite() and displacement.is_finite()):
		return contacts
	if not is_finite(radius) or radius < 0.0:
		return contacts
	for surface_id: String in surface_ids():
		var stored: Dictionary = _surfaces[surface_id]
		if not (stored["channels"] as Array).has(channel):
			continue
		var shape: Dictionary = stored["shape"]
		var raw := {}
		match String(shape["kind"]):
			"circle":
				raw = Sweep.sweep_circle_circle(start, displacement, radius, shape["center"], float(shape["radius"]), "circle", false)
			"rect", "polygon":
				var hits := Sweep.sweep_circle_polygon(start, displacement, radius, shape["points"])
				if not hits.is_empty():
					raw = hits[0]
		if raw.is_empty():
			continue
		contacts.append(Contact.from_raw(raw, channel, Contact.KIND_OVERLAY_SURFACE, surface_id, 0))
	return Contact.sort_contacts(contacts)


func overlaps(channel: StringName, position: Vector2, radius: float) -> Array:
	var contacts: Array = []
	if not Channels.is_valid(channel) or not position.is_finite() or not is_finite(radius) or radius < 0.0:
		return contacts
	for surface_id: String in surface_ids():
		var stored: Dictionary = _surfaces[surface_id]
		if not (stored["channels"] as Array).has(channel):
			continue
		var overlap := Shape.circle_shape_overlap(position, radius, stored["shape"])
		if not bool(overlap["overlaps"]):
			continue
		contacts.append(Contact.from_raw({
			"toi": 0.0,
			"point": overlap["point"],
			"normal": overlap["normal"],
			"feature": overlap["feature"],
			"penetrating": true,
			"initial": true,
		}, channel, Contact.KIND_OVERLAY_SURFACE, surface_id, 0))
	return Contact.sort_contacts(contacts)


func snapshot() -> Dictionary:
	var surfaces: Array[Dictionary] = []
	for surface_id: String in surface_ids():
		var stored: Dictionary = _surfaces[surface_id]
		surfaces.append({
			"id": surface_id,
			"shape": _shape_snapshot(stored["shape"]),
			"channels": (stored["channels"] as Array).duplicate(),
			"opaque": bool(stored["opaque"]),
			"vision_mode": String(stored["vision_mode"]),
			"attenuation": float(stored["attenuation"]),
			"occlusion_rank": int(stored["occlusion_rank"]),
		})
	return {
		"revision": _revision,
		"last_committed_tick": _last_committed_tick,
		"pending_operation_count": _pending_operations.size(),
		"surface_count": surfaces.size(),
		"surfaces": surfaces,
		"suppressed_static_ids": suppressed_ids(),
	}


func _queued_result() -> Dictionary:
	return {
		"ok": true,
		"errors": [],
		"revision": _revision,
		"pending": _pending_operations.size(),
	}


func _apply_operation(operation: Dictionary) -> Dictionary:
	var kind: StringName = operation.get("kind", &"")
	match kind:
		OP_ADD_SURFACE:
			var stored: Dictionary = operation.get("surface", {})
			var surface_id := String(stored.get("id", ""))
			if _surfaces.has(surface_id):
				return {"ok": false, "errors": ["surface.id:duplicate:%s" % surface_id], "revision": _revision}
			_surfaces[surface_id] = stored.duplicate(true)
			_revision += 1
			return {"ok": true, "errors": [], "revision": _revision}
		OP_REMOVE_SURFACE:
			var remove_id := String(operation.get("surface_id", ""))
			if not _surfaces.has(remove_id):
				return {"ok": false, "errors": ["surface.id:unknown:%s" % remove_id], "revision": _revision}
			_surfaces.erase(remove_id)
			_revision += 1
			return {"ok": true, "errors": [], "revision": _revision}
		OP_SUPPRESS_STATIC:
			var suppress_id := String(operation.get("surface_id", ""))
			if _suppressed.has(suppress_id):
				return {"ok": false, "errors": ["suppressed:duplicate:%s" % suppress_id], "revision": _revision}
			_suppressed[suppress_id] = _revision + 1
			_revision += 1
			return {"ok": true, "errors": [], "revision": _revision}
		OP_RESTORE_STATIC:
			var restore_id := String(operation.get("surface_id", ""))
			if not _suppressed.has(restore_id):
				return {"ok": false, "errors": ["suppressed:unknown:%s" % restore_id], "revision": _revision}
			_suppressed.erase(restore_id)
			_revision += 1
			return {"ok": true, "errors": [], "revision": _revision}
	return {"ok": false, "errors": ["overlay:unknown_operation"], "revision": _revision}


func _operation_errors(operations: Array[Dictionary]) -> Array[String]:
	var errors: Array[String] = []
	for operation: Dictionary in operations:
		for error: Variant in operation.get("errors", []):
			errors.append(String(error))
	return errors


static func _shape_snapshot(shape: Dictionary) -> Dictionary:
	match String(shape["kind"]):
		"rect":
			var rect: Rect2 = shape["rect"]
			return {
				"kind": "rect",
				"rect": {"position": [rect.position.x, rect.position.y], "size": [rect.size.x, rect.size.y]},
			}
		"circle":
			var center: Vector2 = shape["center"]
			return {"kind": "circle", "center": [center.x, center.y], "radius": float(shape["radius"])}
		"polygon":
			var points: Array = []
			for point: Vector2 in shape["points"]:
				points.append([point.x, point.y])
			return {"kind": "polygon", "points": points}
	return {"kind": "invalid"}


func _normalize_surface(surface: Variant) -> Dictionary:
	var errors: Array[String] = []
	if not surface is Dictionary:
		return {"ok": false, "errors": ["surface:invalid_type"], "value": {}}
	var source: Dictionary = surface
	for key: Variant in source.keys():
		var key_text := str(key)
		if not SURFACE_FIELDS.has(key_text):
			errors.append("surface.unknown_field:%s" % key_text)
	var surface_id := String(source.get("id", ""))
	if surface_id.strip_edges().is_empty():
		errors.append("surface.id:invalid")
	var shape_result := Shape.normalize(source.get("shape", null))
	if not bool(shape_result["ok"]):
		for error: String in shape_result["errors"]:
			errors.append("surface.%s" % error)
	errors.append_array(StaticSpatialIndexScript._surface_flag_errors(source, "surface"))
	if not errors.is_empty():
		return {"ok": false, "errors": errors, "value": {}}
	var shape: Dictionary = shape_result["value"]
	return {
		"ok": true,
		"errors": [],
		"value": {
			"id": surface_id,
			"shape": shape,
			"shape_key": Shape.shape_key(shape),
			"channels": Channels.sorted_copy(source["channels"]),
			"opaque": bool(source.get("opaque", true)),
			"vision_mode": StringName(String(source.get("vision_mode", "opaque"))),
			"attenuation": float(source.get("attenuation", 0.0)),
			"occlusion_rank": int(source.get("occlusion_rank", 0)),
		},
	}
