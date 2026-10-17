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

var _surfaces: Dictionary = {}
var _suppressed: Dictionary = {}
var _revision := 0


func add_surface(surface: Variant) -> Dictionary:
	var normalized := _normalize_surface(surface)
	if not bool(normalized["ok"]):
		return {"ok": false, "errors": normalized["errors"], "revision": _revision}
	var stored: Dictionary = normalized["value"]
	var surface_id := String(stored["id"])
	if _surfaces.has(surface_id):
		return {"ok": false, "errors": ["surface.id:duplicate:%s" % surface_id], "revision": _revision}
	_surfaces[surface_id] = stored
	_revision += 1
	return {"ok": true, "errors": [], "revision": _revision}


func remove_surface(surface_id: String) -> Dictionary:
	if not _surfaces.has(surface_id):
		return {"ok": false, "errors": ["surface.id:unknown:%s" % surface_id], "revision": _revision}
	_surfaces.erase(surface_id)
	_revision += 1
	return {"ok": true, "errors": [], "revision": _revision}


## Suppresses one baked static surface, for example a destroyed destructible.
func suppress_static(surface_id: String) -> Dictionary:
	if _suppressed.has(surface_id):
		return {"ok": false, "errors": ["suppressed:duplicate:%s" % surface_id], "revision": _revision}
	_suppressed[surface_id] = _revision + 1
	_revision += 1
	return {"ok": true, "errors": [], "revision": _revision}


func restore_static(surface_id: String) -> Dictionary:
	if not _suppressed.has(surface_id):
		return {"ok": false, "errors": ["suppressed:unknown:%s" % surface_id], "revision": _revision}
	_suppressed.erase(surface_id)
	_revision += 1
	return {"ok": true, "errors": [], "revision": _revision}


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
		"surface_count": surfaces.size(),
		"surfaces": surfaces,
		"suppressed_static_ids": suppressed_ids(),
	}


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
