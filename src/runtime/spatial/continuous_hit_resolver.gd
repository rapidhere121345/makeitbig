class_name ContinuousHitResolver
extends RefCounted

## Unified continuous query over static, overlay and dynamic geometry for
## projectile and attack paths.
##
## The resolver collects ordered candidates with toi, normal, channel and
## surface/entity identity, attaches response material, and reports where the
## path stops.  It never applies damage; hit consumption, penetration and
## multi-hit rules belong to the attack or projectile definition consuming the
## result.  An opaque world blocker wins a tie with a dynamic target at the
## same toi, so equal-toi targets behind the stopper are excluded.

const Shape := preload("res://src/runtime/geometry/spatial_shape.gd")
const Channels := preload("res://src/runtime/spatial/spatial_channels.gd")
const Contact := preload("res://src/runtime/spatial/spatial_contact.gd")
const StaticSpatialIndexScript := preload("res://src/runtime/spatial/static_spatial_index.gd")
const DynamicSpatialIndexScript := preload("res://src/runtime/spatial/dynamic_spatial_index.gd")
const SpatialOverlayScript := preload("res://src/runtime/spatial/spatial_overlay.gd")

const PATH_CHANNELS: Array[StringName] = [Channels.PROJECTILE, Channels.ATTACK]
const REQUEST_FIELDS: Array[String] = [
	"channel",
	"start",
	"displacement",
	"radius",
	"include_static",
	"include_dynamic",
	"dynamic_channels",
	"piercing",
]

var _static: StaticSpatialIndex
var _dynamic: DynamicSpatialIndex
var _overlay: SpatialOverlay


static func make(
	static_index: Variant,
	dynamic_index: Variant = null,
	overlay: Variant = null
) -> Dictionary:
	var errors: Array[String] = []
	if not static_index is StaticSpatialIndexScript:
		errors.append("resolver:static_index_required")
	if dynamic_index != null and not dynamic_index is DynamicSpatialIndexScript:
		errors.append("resolver:dynamic_index_invalid")
	if overlay != null and not overlay is SpatialOverlayScript:
		errors.append("resolver:overlay_invalid")
	if not errors.is_empty():
		return {"ok": false, "errors": errors, "value": null}
	var resolver: ContinuousHitResolver = load("res://src/runtime/spatial/continuous_hit_resolver.gd").new()
	resolver._static = static_index
	resolver._dynamic = dynamic_index
	resolver._overlay = overlay
	return {"ok": true, "errors": [], "value": resolver}


func resolve_path(request: Variant) -> Dictionary:
	var errors := _validate_request(request)
	if not errors.is_empty():
		return _failure(errors)
	var source: Dictionary = request
	var channel: StringName = source["channel"]
	var start: Vector2 = source["start"]
	var displacement: Vector2 = source["displacement"]
	var radius := float(source["radius"])
	var include_static := bool(source.get("include_static", true))
	var include_dynamic := bool(source.get("include_dynamic", true)) and _dynamic != null
	var piercing := bool(source.get("piercing", false))
	var dynamic_channels: Array[StringName] = []
	for entry: Variant in source.get("dynamic_channels", [Channels.HURTBOX]):
		var entry_channel := StringName(str(entry))
		if Channels.is_valid(entry_channel) and not dynamic_channels.has(entry_channel):
			dynamic_channels.append(entry_channel)
	dynamic_channels.sort()

	var candidates: Array = []
	if include_static:
		for contact: Variant in _static.sweep(channel, start, displacement, radius):
			var static_contact := contact as SpatialContact
			if _overlay != null and _overlay.is_suppressed(static_contact.source_id):
				continue
			candidates.append(static_contact)
	if _overlay != null:
		for contact: Variant in _overlay.sweep(channel, start, displacement, radius):
			candidates.append(contact)
	var seen_entities: Dictionary = {}
	if include_dynamic:
		for dynamic_channel: StringName in dynamic_channels:
			for contact: Variant in _dynamic.sweep(dynamic_channel, start, displacement, radius):
				var dynamic_contact := contact as SpatialContact
				var entity_key := "%s|%d" % [dynamic_contact.source_id, dynamic_contact.generation]
				if seen_entities.has(entity_key):
					continue
				seen_entities[entity_key] = true
				candidates.append(dynamic_contact)
	var ordered := Contact.sort_contacts(candidates)

	var stop_index := -1
	for index: int in ordered.size():
		var contact := ordered[index] as SpatialContact
		if contact.kind == Contact.KIND_DYNAMIC:
			if piercing:
				contact.response["action"] = "hit"
				contact.response["hit"] = true
				contact.response["pierce"] = true
				continue
			contact.response["action"] = "hit"
			contact.response["hit"] = true
			contact.response["pierce"] = false
			stop_index = index
			break
		var opaque := _surface_opaque(contact)
		if opaque:
			contact.response["action"] = "stop"
			contact.response["hit"] = false
			contact.response["reason"] = "environment_opaque"
			stop_index = index
			break
		contact.response["action"] = "pass"
		contact.response["hit"] = false
		contact.response["reason"] = "environment_transparent"
	var reported: Array = ordered.slice(0, stop_index + 1) if stop_index >= 0 else ordered
	var stop_toi := 1.0
	if stop_index >= 0:
		stop_toi = (ordered[stop_index] as SpatialContact).toi
	return {
		"ok": true,
		"errors": [],
		"channel": String(channel),
		"contacts": reported,
		"stop_index": stop_index,
		"stop_toi": stop_toi,
		"clipped": stop_index >= 0,
		"end_point": start + displacement * stop_toi,
		"length": displacement.length(),
		"piercing": piercing,
		"dynamic_revision": _dynamic.revision() if _dynamic != null else 0,
	}


func _surface_opaque(contact: SpatialContact) -> bool:
	var surface := {}
	if contact.kind == Contact.KIND_STATIC_SURFACE:
		surface = _static.surface(contact.source_id)
	elif contact.kind == Contact.KIND_OVERLAY_SURFACE and _overlay != null:
		surface = _overlay.surface(contact.source_id)
	if surface.is_empty():
		return true
	if StringName(String(surface.get("vision_mode", "opaque"))) == &"attenuate":
		return false
	return bool(surface.get("opaque", true))


func _validate_request(request: Variant) -> Array[String]:
	var errors: Array[String] = []
	if not request is Dictionary:
		return ["path:invalid_type"]
	var source: Dictionary = request
	for field: String in ["channel", "start", "displacement", "radius"]:
		if not source.has(field):
			errors.append("path:missing_field:%s" % field)
	for key: Variant in source.keys():
		if not REQUEST_FIELDS.has(String(key)):
			errors.append("path:unknown_field:%s" % String(key))
	var channel := StringName(str(source.get("channel", "")))
	if not PATH_CHANNELS.has(channel):
		errors.append("path.channel:invalid:%s" % String(channel))
	if not source.get("start", null) is Vector2 or not (source.get("start", null) as Vector2).is_finite():
		errors.append("path.start:invalid")
	if not source.get("displacement", null) is Vector2 or not (source.get("displacement", null) as Vector2).is_finite():
		errors.append("path.displacement:invalid")
	var radius_value: Variant = source.get("radius", null)
	if radius_value is float or radius_value is int:
		var radius := float(radius_value)
		if not is_finite(radius) or radius < 0.0:
			errors.append("path.radius:invalid")
	else:
		errors.append("path.radius:invalid_type")
	if source.has("dynamic_channels") and not source["dynamic_channels"] is Array:
		errors.append("path.dynamic_channels:invalid_type")
	return errors


static func _failure(errors: Array[String]) -> Dictionary:
	return {
		"ok": false,
		"errors": errors,
		"channel": "",
		"contacts": [],
		"stop_index": -1,
		"stop_toi": 0.0,
		"clipped": false,
		"end_point": Vector2.ZERO,
		"length": 0.0,
		"piercing": false,
		"dynamic_revision": 0,
	}
