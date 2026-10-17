class_name OcclusionResolver
extends RefCounted

## Presentation-only occlusion queries over the occlusion channel.
##
## Visual occlusion answers where foreground geometry covers the view ray; it
## never answers AI line of sight and never feeds back into movement, vision or
## combat.  Each occluder carries an authored occlusion_rank used by the
## presentation layer for cutaway ordering.

const Shape := preload("res://src/runtime/geometry/spatial_shape.gd")
const Channels := preload("res://src/runtime/spatial/spatial_channels.gd")
const Contact := preload("res://src/runtime/spatial/spatial_contact.gd")
const StaticSpatialIndexScript := preload("res://src/runtime/spatial/static_spatial_index.gd")
const SpatialOverlayScript := preload("res://src/runtime/spatial/spatial_overlay.gd")

const CAST_FIELDS: Array[String] = ["from", "direction", "length", "radius"]
const SEGMENT_FIELDS: Array[String] = ["from", "to", "radius"]

var _static: StaticSpatialIndex
var _overlay: SpatialOverlay


static func make(static_index: Variant, overlay: Variant = null) -> Dictionary:
	var errors: Array[String] = []
	if not static_index is StaticSpatialIndexScript:
		errors.append("resolver:static_index_required")
	if overlay != null and not overlay is SpatialOverlayScript:
		errors.append("resolver:overlay_invalid")
	if not errors.is_empty():
		return {"ok": false, "errors": errors, "value": null}
	var resolver: OcclusionResolver = load("res://src/runtime/spatial/occlusion_resolver.gd").new()
	resolver._static = static_index
	resolver._overlay = overlay
	return {"ok": true, "errors": [], "value": resolver}


func cast(request: Variant) -> Dictionary:
	var errors: Array[String] = []
	if not request is Dictionary:
		return _failure(["occlusion:invalid_type"])
	var source: Dictionary = request
	for field: String in ["from", "direction", "length"]:
		if not source.has(field):
			errors.append("occlusion:missing_field:%s" % field)
	for key: Variant in source.keys():
		if not CAST_FIELDS.has(String(key)):
			errors.append("occlusion:unknown_field:%s" % String(key))
	if not source.get("from", null) is Vector2 or not (source.get("from", null) as Vector2).is_finite():
		errors.append("occlusion.from:invalid")
	if not source.get("direction", null) is Vector2 or not (source.get("direction", null) as Vector2).is_finite() or (source.get("direction", null) as Vector2).length_squared() <= Shape.MIN_SHAPE_SIZE * Shape.MIN_SHAPE_SIZE:
		errors.append("occlusion.direction:invalid")
	var length_value: Variant = source.get("length", null)
	if length_value is float or length_value is int:
		var length := float(length_value)
		if not is_finite(length) or length <= 0.0:
			errors.append("occlusion.length:invalid")
	else:
		errors.append("occlusion.length:invalid_type")
	if not errors.is_empty():
		return _failure(errors)
	var direction: Vector2 = source["direction"]
	return _resolve(source["from"], direction.normalized() * float(source["length"]), float(source.get("radius", 0.0)))


func segment(request: Variant) -> Dictionary:
	var errors: Array[String] = []
	if not request is Dictionary:
		return _failure(["occlusion:invalid_type"])
	var source: Dictionary = request
	for field: String in ["from", "to"]:
		if not source.has(field):
			errors.append("occlusion:missing_field:%s" % field)
	for key: Variant in source.keys():
		if not SEGMENT_FIELDS.has(String(key)):
			errors.append("occlusion:unknown_field:%s" % String(key))
	if not source.get("from", null) is Vector2 or not (source.get("from", null) as Vector2).is_finite():
		errors.append("occlusion.from:invalid")
	if not source.get("to", null) is Vector2 or not (source.get("to", null) as Vector2).is_finite():
		errors.append("occlusion.to:invalid")
	if not errors.is_empty():
		return _failure(errors)
	return _resolve(source["from"], source["to"] - source["from"], float(source.get("radius", 0.0)))


func _resolve(from: Vector2, displacement: Vector2, radius: float) -> Dictionary:
	var candidates: Array = []
	for contact: Variant in _static.sweep(Channels.OCCLUSION, from, displacement, radius):
		var static_contact := contact as SpatialContact
		if _overlay != null and _overlay.is_suppressed(static_contact.source_id):
			continue
		candidates.append(static_contact)
	if _overlay != null:
		for contact: Variant in _overlay.sweep(Channels.OCCLUSION, from, displacement, radius):
			candidates.append(contact)
	var ordered := Contact.sort_contacts(candidates)
	var reported: Array[Dictionary] = []
	for contact: Variant in ordered:
		var occluder := contact as SpatialContact
		var surface := {}
		if occluder.kind == Contact.KIND_STATIC_SURFACE:
			surface = _static.surface(occluder.source_id)
		elif _overlay != null and occluder.kind == Contact.KIND_OVERLAY_SURFACE:
			surface = _overlay.surface(occluder.source_id)
		occluder.response = {"rank": int(surface.get("occlusion_rank", 0))}
		reported.append(occluder.to_dict())
	var first: Dictionary = reported[0] if not reported.is_empty() else {}
	return {
		"ok": true,
		"errors": [],
		"occluded": not reported.is_empty(),
		"contact": first,
		"candidates": reported,
	}


static func _failure(errors: Array[String]) -> Dictionary:
	return {"ok": false, "errors": errors, "occluded": false, "contact": {}, "candidates": []}
