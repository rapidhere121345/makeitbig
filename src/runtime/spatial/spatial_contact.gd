class_name SpatialContact
extends RefCounted

## Typed deterministic contact record.
##
## Ordering contract: toi (quantized), then environment kinds before dynamic
## targets (static_surface, overlay_surface, boundary, dynamic), then
## source_id, generation, feature and normal.  The environment-first rule
## implements the target contract that an opaque world blocker wins a tie with
## a target at the same toi.

const Shape := preload("res://src/runtime/geometry/spatial_shape.gd")

const KIND_STATIC_SURFACE := &"static_surface"
const KIND_OVERLAY_SURFACE := &"overlay_surface"
const KIND_BOUNDARY := &"boundary"
const KIND_DYNAMIC := &"dynamic"

const _KIND_RANK: Dictionary = {
	"static_surface": 0,
	"overlay_surface": 1,
	"boundary": 2,
	"dynamic": 3,
}

var channel: StringName = &""
var kind: StringName = &""
var source_id: String = ""
var generation: int = 0
var toi: float = 0.0
var point: Vector2 = Vector2.ZERO
var normal: Vector2 = Vector2.ZERO
var feature: String = ""
var penetrating: bool = false
var initial: bool = false
var response: Dictionary = {}


func _init(data: Dictionary = {}) -> void:
	if data.is_empty():
		return
	channel = StringName(str(data.get("channel", &"")))
	kind = StringName(str(data.get("kind", &"")))
	source_id = String(data.get("source_id", ""))
	generation = int(data.get("generation", 0))
	toi = float(data.get("toi", 0.0))
	point = data.get("point", Vector2.ZERO)
	normal = data.get("normal", Vector2.ZERO)
	feature = String(data.get("feature", ""))
	penetrating = bool(data.get("penetrating", false))
	initial = bool(data.get("initial", false))
	response = (data.get("response", {}) as Dictionary).duplicate(true)


static func from_raw(
	raw: Dictionary,
	channel_value: StringName,
	kind_value: StringName,
	source_id_value: String,
	generation_value: int,
	response_value: Dictionary = {}
) -> SpatialContact:
	return SpatialContact.new({
		"channel": channel_value,
		"kind": kind_value,
		"source_id": source_id_value,
		"generation": generation_value,
		"toi": raw.get("toi", 0.0),
		"point": raw.get("point", Vector2.ZERO),
		"normal": raw.get("normal", Vector2.ZERO),
		"feature": raw.get("feature", ""),
		"penetrating": raw.get("penetrating", false),
		"initial": raw.get("initial", false),
		"response": response_value,
	})


func order_key() -> String:
	return "%s|%d|%s|%d|%s|%s" % [
		Shape.fmt(toi),
		int(_KIND_RANK.get(String(kind), 99)),
		source_id,
		generation,
		feature,
		Shape.vector_key(normal),
	]


func dedupe_key() -> String:
	return "%s|%s|%d|%s|%s|%s" % [
		String(kind),
		source_id,
		generation,
		feature,
		Shape.fmt(toi),
		Shape.vector_key(normal),
	]


func to_dict() -> Dictionary:
	return {
		"channel": String(channel),
		"kind": String(kind),
		"source_id": source_id,
		"generation": generation,
		"toi": toi,
		"point": [point.x, point.y],
		"normal": [normal.x, normal.y],
		"feature": feature,
		"penetrating": penetrating,
		"initial": initial,
		"response": response.duplicate(true),
	}


static func sort_contacts(contacts: Array) -> Array:
	var result := contacts.duplicate()
	result.sort_custom(func(left, right) -> bool:
		return (left as SpatialContact).order_key() < (right as SpatialContact).order_key()
	)
	return result


static func encode(contacts: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for contact: Variant in contacts:
		result.append((contact as SpatialContact).to_dict())
	return result
