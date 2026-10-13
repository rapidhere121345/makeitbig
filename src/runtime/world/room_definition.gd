class_name RoomDefinition
extends RefCounted

## Static room identity.  A RoomDefinition has no node, scene or run state.
##
## The dictionary constructor is intentionally strict at validation time.  It
## keeps invalid values long enough for callers to report all errors together,
## rather than throwing from a data loading path.

const FIELDS: Array[String] = [
	"room_id",
	"world_asset_id",
	"encounter_id",
	"ruleset_id",
	"tags",
]

var room_id: String = ""
var world_asset_id: String = ""
var encounter_id: String = ""
var ruleset_id: String = ""
var tags: Array[String] = []


func _init(
	room_id_value: Variant = "",
	world_asset_id_value: Variant = "",
	encounter_id_value: Variant = "",
	ruleset_id_value: Variant = "",
	tags_value: Variant = []
) -> void:
	if room_id_value is Dictionary:
		_assign_dictionary(room_id_value as Dictionary)
		return
	room_id = _text(room_id_value)
	world_asset_id = _text(world_asset_id_value)
	encounter_id = _text(encounter_id_value)
	ruleset_id = _text(ruleset_id_value)
	tags = _tags(tags_value)


static func from_dict(value: Variant) -> RefCounted:
	return _new_instance(value if value is Dictionary else {})


## Returns all errors in stable order.  Empty strings and whitespace-only
## identifiers are invalid; tags are required and each tag must be non-empty.
func validate() -> Array[String]:
	var errors: Array[String] = []
	if room_id.strip_edges().is_empty():
		errors.append("missing_or_empty:room_id")
	if world_asset_id.strip_edges().is_empty():
		errors.append("missing_or_empty:world_asset_id")
	if encounter_id.strip_edges().is_empty():
		errors.append("missing_or_empty:encounter_id")
	if ruleset_id.strip_edges().is_empty():
		errors.append("missing_or_empty:ruleset_id")
	if tags.is_empty():
		errors.append("missing_or_empty:tags")
	for index in tags.size():
		if tags[index].strip_edges().is_empty():
			errors.append("empty_tag:%d" % index)
	return errors


func is_valid() -> bool:
	return validate().is_empty()


func validation_result() -> Dictionary:
	var errors := validate()
	return {"ok": errors.is_empty(), "errors": errors, "value": snapshot()}


## A canonical, detached representation suitable for content registries and
## digest inputs.  Tags are semantic labels, so their order is normalized.
func snapshot() -> Dictionary:
	var sorted_tags: Array[String] = tags.duplicate()
	sorted_tags.sort()
	return {
		"room_id": room_id.strip_edges(),
		"world_asset_id": world_asset_id.strip_edges(),
		"encounter_id": encounter_id.strip_edges(),
		"ruleset_id": ruleset_id.strip_edges(),
		"tags": sorted_tags,
	}


func digest_input() -> Dictionary:
	return snapshot()


static func validate_data(value: Variant) -> Array[String]:
	if not value is Dictionary:
		return ["invalid_type:room_definition"]
	var data: Dictionary = value
	var errors: Array[String] = []
	for field: String in FIELDS:
		if not data.has(field):
			errors.append("missing_field:%s" % field)
	for key: Variant in data.keys():
		var text_key := str(key)
		if not FIELDS.has(text_key):
			errors.append("unknown_field:%s" % text_key)
	var definition = _new_instance(data)
	for error: String in definition.validate():
		if not errors.has(error):
			errors.append(error)
	return errors


static func normalize_data(value: Variant) -> Dictionary:
	var errors := validate_data(value)
	if not errors.is_empty():
		return {"ok": false, "errors": errors, "value": {}}
	var definition = _new_instance(value)
	return {"ok": true, "errors": [], "value": definition.snapshot()}


func _assign_dictionary(data: Dictionary) -> void:
	room_id = _text(data.get("room_id", ""))
	world_asset_id = _text(data.get("world_asset_id", ""))
	encounter_id = _text(data.get("encounter_id", ""))
	ruleset_id = _text(data.get("ruleset_id", ""))
	tags = _tags(data.get("tags", []))


static func _new_instance(value: Dictionary) -> RefCounted:
	return load("res://src/runtime/world/room_definition.gd").new(value)


static func _text(value: Variant) -> String:
	if value is String or value is StringName:
		return String(value)
	return ""


static func _tags(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for item: Variant in value:
			result.append(_text(item))
	elif value is PackedStringArray:
		for item: String in value:
			result.append(item)
	return result
