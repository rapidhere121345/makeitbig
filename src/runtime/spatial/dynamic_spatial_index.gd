class_name DynamicSpatialIndex
extends RefCounted

## Mutable index over committed runtime entity bodies.
##
## Bodies are registered structurally and positions are committed from
## resolved simulation poses.  Every successful structural change or pose
## commit bumps the revision.  Queries only ever read committed data, and all
## listings are ordered by stable entity id so registration order never leaks
## into results.  A body contributes to a query only through the channels it
## declared; a hurtbox-only body is invisible to movement no matter what its
## collision class is.

const Shape := preload("res://src/runtime/geometry/spatial_shape.gd")
const Sweep := preload("res://src/runtime/geometry/spatial_sweep.gd")
const Channels := preload("res://src/runtime/spatial/spatial_channels.gd")
const Contact := preload("res://src/runtime/spatial/spatial_contact.gd")

const BODY_FIELDS: Array[String] = [
	"entity_id",
	"generation",
	"position",
	"radius",
	"channels",
	"collision_class",
	"faction",
]
const COLLISION_CLASSES: Array[StringName] = [&"solid", &"soft", &"ghost"]

var _bodies: Dictionary = {}
var _bodies_by_channel: Dictionary = {}
var _inactive_bodies: Dictionary = {}
var _revision := 0


func register_body(body: Variant) -> Dictionary:
	var errors := _validate_body(body)
	if not errors.is_empty():
		return {"ok": false, "errors": errors, "revision": _revision}
	var source: Dictionary = body
	var entity_id := String(source["entity_id"])
	# Structural fail-closed guard: an existing id can never be overwritten,
	# so a body's channel buckets can never go stale through re-registration.
	if _bodies.has(entity_id):
		return {"ok": false, "errors": ["body.entity_id:duplicate:%s" % entity_id], "revision": _revision}
	var stored := _normalize_body(source)
	_bodies[entity_id] = stored
	_inactive_bodies[entity_id] = false
	for channel: StringName in stored["channels"]:
		if not _bodies_by_channel.has(channel):
			_bodies_by_channel[channel] = {}
		(_bodies_by_channel[channel] as Dictionary)[entity_id] = stored
	_revision += 1
	return {"ok": true, "errors": [], "revision": _revision}


func unregister_body(entity_id: String) -> Dictionary:
	if not _bodies.has(entity_id):
		return {"ok": false, "errors": ["entity:unknown:%s" % entity_id], "revision": _revision}
	var stored: Dictionary = _bodies[entity_id]
	for channel: StringName in stored["channels"]:
		if _bodies_by_channel.has(channel):
			(_bodies_by_channel[channel] as Dictionary).erase(entity_id)
	_bodies.erase(entity_id)
	_inactive_bodies.erase(entity_id)
	_revision += 1
	return {"ok": true, "errors": [], "revision": _revision}


## Commits one resolved pose.  The movement resolver is the only caller that
## should produce these values.
func commit_pose(entity_id: String, position: Vector2) -> Dictionary:
	if not _bodies.has(entity_id):
		return {"ok": false, "errors": ["entity:unknown:%s" % entity_id], "revision": _revision}
	if not position.is_finite():
		return {"ok": false, "errors": ["entity:%s.position:non_finite" % entity_id], "revision": _revision}
	(_bodies[entity_id] as Dictionary)["position"] = position
	_revision += 1
	return {"ok": true, "errors": [], "revision": _revision}


func set_collision_class(entity_id: String, collision_class: StringName) -> Dictionary:
	if not _bodies.has(entity_id):
		return {"ok": false, "errors": ["entity:unknown:%s" % entity_id], "revision": _revision}
	if not COLLISION_CLASSES.has(collision_class):
		return {"ok": false, "errors": ["body.collision_class:unknown:%s" % String(collision_class)], "revision": _revision}
	(_bodies[entity_id] as Dictionary)["collision_class"] = collision_class
	_revision += 1
	return {"ok": true, "errors": [], "revision": _revision}


## Typed between-tick activation state.  Inactive bodies retain their
## generational identity and pose but contribute to no spatial query until the
## owning encounter acknowledges their spawn.
func set_active(entity_id: String, active: bool) -> Dictionary:
	if not _bodies.has(entity_id):
		return {"ok": false, "errors": ["entity:unknown:%s" % entity_id], "revision": _revision}
	if not active is bool:
		return {"ok": false, "errors": ["entity.active:invalid_type"], "revision": _revision}
	var desired := bool(active)
	if is_active(entity_id) != desired:
		_inactive_bodies[entity_id] = not desired
		_revision += 1
	return {"ok": true, "errors": [], "revision": _revision}


func is_active(entity_id: String) -> bool:
	return _bodies.has(entity_id) and not bool(_inactive_bodies.get(entity_id, false))


## Atomic multi-body pose commit at a tick boundary.  Every entity must exist
## and every position must be finite before anything is applied.
func commit_poses(entries: Variant) -> Dictionary:
	if not entries is Array:
		return {"ok": false, "errors": ["poses:invalid_type"], "revision": _revision}
	var pending: Array[Dictionary] = []
	var errors: Array[String] = []
	var seen: Dictionary = {}
	for entry: Variant in entries:
		if not entry is Dictionary:
			errors.append("poses:invalid_entry")
			continue
		var source: Dictionary = entry
		var entity_id := String(source.get("entity_id", ""))
		var position: Variant = source.get("position", null)
		if entity_id.is_empty() or not _bodies.has(entity_id):
			errors.append("poses.entity:unknown:%s" % entity_id)
			continue
		if not position is Vector2 or not (position as Vector2).is_finite():
			errors.append("poses.entity:%s.position:invalid" % entity_id)
			continue
		if seen.has(entity_id):
			errors.append("poses.entity:duplicate:%s" % entity_id)
			continue
		seen[entity_id] = true
		pending.append({"entity_id": entity_id, "position": position})
	if not errors.is_empty():
		return {"ok": false, "errors": errors, "revision": _revision}
	for entry: Dictionary in pending:
		(_bodies[String(entry["entity_id"])] as Dictionary)["position"] = entry["position"]
	_revision += 1
	return {"ok": true, "errors": [], "revision": _revision}


func revision() -> int:
	return _revision


func entity_ids() -> Array[String]:
	var ids: Array[String] = []
	for key: Variant in _bodies.keys():
		ids.append(String(key))
	ids.sort()
	return ids


func body(entity_id: String) -> Dictionary:
	var result := (_bodies.get(entity_id, {}) as Dictionary).duplicate(true)
	if not result.is_empty():
		result["active"] = is_active(entity_id)
	return result


func bodies(channel: StringName) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not Channels.is_valid(channel) or not _bodies_by_channel.has(channel):
		return result
	var bucket: Dictionary = _bodies_by_channel[channel]
	var ids: Array[String] = []
	for key: Variant in bucket.keys():
		ids.append(String(key))
	ids.sort()
	for entity_id: String in ids:
		if not is_active(entity_id):
			continue
		result.append((bucket[entity_id] as Dictionary).duplicate(true))
	return result


func sweep(channel: StringName, start: Vector2, displacement: Vector2, radius: float) -> Array:
	var contacts: Array = []
	if not Channels.is_valid(channel) or not (start.is_finite() and displacement.is_finite()):
		return contacts
	if not is_finite(radius) or radius < 0.0:
		return contacts
	for body_entry: Dictionary in bodies(channel):
		var body_position: Vector2 = body_entry["position"]
		var raw := Sweep.sweep_circle_circle(
			start,
			displacement,
			radius,
			body_position,
			float(body_entry["radius"]),
			"body",
			false
		)
		if raw.is_empty():
			continue
		var contact := Contact.from_raw(
			raw,
			channel,
			Contact.KIND_DYNAMIC,
			String(body_entry["entity_id"]),
			int(body_entry["generation"])
		)
		contact.response = {
			"collision_class": String(body_entry["collision_class"]),
			"faction": String(body_entry["faction"]),
		}
		contacts.append(contact)
	return Contact.sort_contacts(contacts)


func overlaps(channel: StringName, position: Vector2, radius: float) -> Array:
	var contacts: Array = []
	if not Channels.is_valid(channel) or not position.is_finite() or not is_finite(radius) or radius < 0.0:
		return contacts
	for body_entry: Dictionary in bodies(channel):
		var combined := radius + float(body_entry["radius"])
		var body_position: Vector2 = body_entry["position"]
		if position.distance_to(body_position) >= combined - Shape.DISTANCE_EPSILON:
			continue
		var contact := Contact.from_raw({
			"toi": 0.0,
			"point": body_position,
			"normal": (position - body_position).normalized() if position.distance_to(body_position) > Shape.MIN_SHAPE_SIZE else Vector2.ZERO,
			"feature": "body",
			"penetrating": true,
			"initial": true,
		}, channel, Contact.KIND_DYNAMIC, String(body_entry["entity_id"]), int(body_entry["generation"]))
		contact.response = {
			"collision_class": String(body_entry["collision_class"]),
			"faction": String(body_entry["faction"]),
		}
		contacts.append(contact)
	return Contact.sort_contacts(contacts)


func snapshot() -> Dictionary:
	var listed: Array[Dictionary] = []
	for entity_id: String in entity_ids():
		var stored: Dictionary = _bodies[entity_id]
		var position: Vector2 = stored["position"]
		listed.append({
			"entity_id": entity_id,
			"generation": int(stored["generation"]),
			"position": [position.x, position.y],
			"radius": float(stored["radius"]),
			"channels": (stored["channels"] as Array).duplicate(),
			"collision_class": String(stored["collision_class"]),
			"faction": String(stored["faction"]),
			"active": is_active(entity_id),
		})
	return {
		"revision": _revision,
		"contract": Shape.coordinate_contract(),
		"body_count": listed.size(),
		"bodies": listed,
	}


func _validate_body(body: Variant) -> Array[String]:
	var errors: Array[String] = []
	if not body is Dictionary:
		return ["body:invalid_type"]
	var source: Dictionary = body
	for field: String in BODY_FIELDS:
		if field == "faction":
			continue
		if not source.has(field):
			errors.append("body:missing_field:%s" % field)
	for key: Variant in source.keys():
		var key_text := str(key)
		if not BODY_FIELDS.has(key_text):
			errors.append("body:unknown_field:%s" % key_text)
	var entity_id := String(source.get("entity_id", ""))
	if entity_id.strip_edges().is_empty():
		errors.append("body.entity_id:invalid")
	elif _bodies.has(entity_id):
		errors.append("body.entity_id:duplicate:%s" % entity_id)
	if not source.get("generation", 0) is int or int(source.get("generation", 0)) < 1:
		errors.append("body.generation:invalid")
	if not source.get("position", null) is Vector2 or not (source.get("position", null) as Vector2).is_finite():
		errors.append("body.position:invalid")
	var radius_value: Variant = source.get("radius", null)
	if radius_value is float or radius_value is int:
		var radius := float(radius_value)
		if not is_finite(radius) or radius < Shape.MIN_SHAPE_SIZE:
			errors.append("body.radius:invalid")
	else:
		errors.append("body.radius:invalid_type")
	errors.append_array(Channels.validate_list(source.get("channels", null), "body.channels"))
	var collision_class := StringName(str(source.get("collision_class", "")))
	if not COLLISION_CLASSES.has(collision_class):
		errors.append("body.collision_class:unknown:%s" % String(collision_class))
	if source.has("faction") and not (source["faction"] is String or source["faction"] is StringName):
		errors.append("body.faction:invalid_type")
	return errors


static func _normalize_body(source: Dictionary) -> Dictionary:
	return {
		"entity_id": String(source["entity_id"]),
		"generation": int(source["generation"]),
		"position": source["position"],
		"radius": float(source["radius"]),
		"channels": Channels.sorted_copy(source["channels"]),
		"collision_class": StringName(str(source["collision_class"])),
		"faction": String(source.get("faction", "")),
	}
