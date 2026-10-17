class_name VisionResolver
extends RefCounted

## AI line-of-sight queries over the vision channel.
##
## Vision is a gameplay sense and is deliberately separate from the occlusion
## channel: a fence can block movement but not sight, smoke can block sight but
## not arrows, and neither statement implies the other.  Surfaces declare
## vision_mode opaque or attenuate; attenuating surfaces multiply a transparency
## factor instead of blocking.

const Shape := preload("res://src/runtime/geometry/spatial_shape.gd")
const Channels := preload("res://src/runtime/spatial/spatial_channels.gd")
const Contact := preload("res://src/runtime/spatial/spatial_contact.gd")
const StaticSpatialIndexScript := preload("res://src/runtime/spatial/static_spatial_index.gd")
const SpatialOverlayScript := preload("res://src/runtime/spatial/spatial_overlay.gd")
const DynamicSpatialIndexScript := preload("res://src/runtime/spatial/dynamic_spatial_index.gd")

const VISIBLE_TRANSPARENCY := 0.0001
const LOS_FIELDS: Array[String] = ["from", "to", "radius"]
const TARGET_FIELDS: Array[String] = [
	"from",
	"radius",
	"range",
	"half_angle",
	"facing",
	"dynamic_index",
	"target_channel",
]

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
	var resolver: VisionResolver = load("res://src/runtime/spatial/vision_resolver.gd").new()
	resolver._static = static_index
	resolver._overlay = overlay
	return {"ok": true, "errors": [], "value": resolver}


func line_of_sight(request: Variant) -> Dictionary:
	var errors := _validate_los(request)
	if not errors.is_empty():
		return {
			"ok": false,
			"errors": errors,
			"visible": false,
			"distance": 0.0,
			"transparency": 0.0,
			"blockers": [],
			"attenuators": [],
		}
	var source: Dictionary = request
	var from: Vector2 = source["from"]
	var to: Vector2 = source["to"]
	var radius := float(source.get("radius", 0.0))
	var result := _segment_contacts(from, to, radius)
	var contacts: Array = result["contacts"]
	var transparency := 1.0
	var blockers: Array = []
	var attenuators: Array = []
	for contact: Variant in contacts:
		var sight_contact := contact as SpatialContact
		var surface := {}
		if sight_contact.kind == Contact.KIND_STATIC_SURFACE:
			surface = _static.surface(sight_contact.source_id)
		elif _overlay != null and sight_contact.kind == Contact.KIND_OVERLAY_SURFACE:
			surface = _overlay.surface(sight_contact.source_id)
		var mode := String(surface.get("vision_mode", "opaque"))
		var attenuation := float(surface.get("attenuation", 0.0))
		if mode == "attenuate" and attenuation < 1.0 - Shape.DISTANCE_EPSILON:
			transparency *= 1.0 - attenuation
			sight_contact.response = {"action": "attenuate", "attenuation": attenuation}
			attenuators.append(sight_contact)
			continue
		sight_contact.response = {"action": "block", "attenuation": 1.0}
		blockers.append(sight_contact)
	return {
		"ok": true,
		"errors": [],
		"visible": blockers.is_empty() and transparency >= VISIBLE_TRANSPARENCY,
		"distance": from.distance_to(to),
		"transparency": transparency,
		"blockers": blockers,
		"attenuators": attenuators,
	}


func visible_targets(request: Variant) -> Dictionary:
	var errors := _validate_targets(request)
	if not errors.is_empty():
		return {"ok": false, "errors": errors, "targets": []}
	var source: Dictionary = request
	var from: Vector2 = source["from"]
	var radius := float(source.get("radius", 0.0))
	var range := float(source["range"])
	var half_angle := float(source.get("half_angle", PI))
	var facing: Vector2 = source.get("facing", Vector2(1.0, 0.0))
	var target_channel: StringName = StringName(str(source.get("target_channel", Channels.HURTBOX)))
	var dynamic_index: DynamicSpatialIndex = source["dynamic_index"]
	if not is_finite(range) or range < 0.0:
		return {"ok": false, "errors": ["targets.range:invalid"], "targets": []}
	if not is_finite(half_angle) or half_angle <= 0.0 or half_angle > PI:
		return {"ok": false, "errors": ["targets.half_angle:invalid"], "targets": []}
	if not facing.is_finite() or facing.length_squared() <= Shape.MIN_SHAPE_SIZE * Shape.MIN_SHAPE_SIZE:
		return {"ok": false, "errors": ["targets.facing:invalid"], "targets": []}
	var facing_unit := facing.normalized()
	var cone_limited := half_angle < PI - Shape.DIRECTION_EPSILON
	var targets: Array[Dictionary] = []
	for body_entry: Dictionary in dynamic_index.bodies(target_channel):
		var position: Vector2 = body_entry["position"]
		var offset := position - from
		var distance := offset.length()
		if distance > range + Shape.DISTANCE_EPSILON:
			continue
		if cone_limited and distance > Shape.MIN_SHAPE_SIZE:
			if absf(facing_unit.angle_to(offset / distance)) > half_angle + Shape.DIRECTION_EPSILON:
				continue
		var sight := line_of_sight({"from": from, "to": position, "radius": radius})
		if not bool(sight["visible"]):
			continue
		targets.append({
			"entity_id": String(body_entry["entity_id"]),
			"generation": int(body_entry["generation"]),
			"position": [position.x, position.y],
			"distance": distance,
			"transparency": float(sight["transparency"]),
		})
	targets.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_key := "%s|%s" % [Shape.fmt(float(left["distance"])), String(left["entity_id"])]
		var right_key := "%s|%s" % [Shape.fmt(float(right["distance"])), String(right["entity_id"])]
		return left_key < right_key
	)
	return {"ok": true, "errors": [], "targets": targets}


func _segment_contacts(from: Vector2, to: Vector2, radius: float) -> Dictionary:
	var candidates: Array = []
	var displacement := to - from
	for contact: Variant in _static.sweep(Channels.VISION, from, displacement, radius):
		var static_contact := contact as SpatialContact
		if _overlay != null and _overlay.is_suppressed(static_contact.source_id):
			continue
		candidates.append(static_contact)
	if _overlay != null:
		for contact: Variant in _overlay.sweep(Channels.VISION, from, displacement, radius):
			candidates.append(contact)
	return {"contacts": Contact.sort_contacts(candidates)}


func _validate_los(request: Variant) -> Array[String]:
	var errors: Array[String] = []
	if not request is Dictionary:
		return ["sight:invalid_type"]
	var source: Dictionary = request
	for field: String in ["from", "to"]:
		if not source.has(field):
			errors.append("sight:missing_field:%s" % field)
	for key: Variant in source.keys():
		if not LOS_FIELDS.has(String(key)):
			errors.append("sight:unknown_field:%s" % String(key))
	if not source.get("from", null) is Vector2 or not (source.get("from", null) as Vector2).is_finite():
		errors.append("sight.from:invalid")
	if not source.get("to", null) is Vector2 or not (source.get("to", null) as Vector2).is_finite():
		errors.append("sight.to:invalid")
	return errors


func _validate_targets(request: Variant) -> Array[String]:
	var errors: Array[String] = []
	if not request is Dictionary:
		return ["targets:invalid_type"]
	var source: Dictionary = request
	for field: String in ["from", "range", "dynamic_index"]:
		if not source.has(field):
			errors.append("targets:missing_field:%s" % field)
	for key: Variant in source.keys():
		if not TARGET_FIELDS.has(String(key)):
			errors.append("targets:unknown_field:%s" % String(key))
	if not source.get("from", null) is Vector2 or not (source.get("from", null) as Vector2).is_finite():
		errors.append("targets.from:invalid")
	if not source.get("dynamic_index", null) is DynamicSpatialIndexScript:
		errors.append("targets.dynamic_index:invalid")
	return errors
