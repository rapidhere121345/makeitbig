class_name EntityDefinition
extends RefCounted

## Static description of an entity. Runtime state never lives here.
## A prefab or scene may carry the visual hierarchy; this record only carries
## the gameplay bindings that other systems must agree on.

const SCHEMA_VERSION := 1
const REQUIRED_FIELDS: Array[String] = [
	"entity_id",
	"feet_anchor",
	"footprint",
	"sort_baseline",
	"parts",
]

var entity_id := ""
var feet_anchor := Vector2.ZERO
var footprint: Dictionary = {}
var sort_baseline := 0.0
var parts: Array[Dictionary] = []
var prefab_path := ""


static func from_dict(raw: Variant) -> Dictionary:
	if not raw is Dictionary:
		return _failure("invalid_entity_definition")
	var value: Dictionary = raw
	for field: String in REQUIRED_FIELDS:
		if not value.has(field):
			return _failure("missing_%s" % field)
	for key: Variant in value.keys():
		if String(key) not in REQUIRED_FIELDS + ["schema_version", "prefab_path"]:
			return _failure("unknown_field_%s" % String(key))
	var result := EntityDefinition.new()
	result.entity_id = String(value.get("entity_id", "")).strip_edges()
	if result.entity_id.is_empty():
		return _failure("invalid_entity_id")
	if not _vector_from(value.get("feet_anchor"), result, "feet_anchor"):
		return _failure("invalid_feet_anchor")
	if not value.get("footprint") is Dictionary:
		return _failure("invalid_footprint")
	result.footprint = (value.get("footprint") as Dictionary).duplicate(true)
	if String(result.footprint.get("kind", "")) != "circle":
		return _failure("unsupported_footprint")
	var radius: Variant = result.footprint.get("radius", null)
	if not _finite_positive(radius):
		return _failure("invalid_footprint_radius")
	result.sort_baseline = float(value.get("sort_baseline", 0.0))
	if not is_finite(result.sort_baseline):
		return _failure("invalid_sort_baseline")
	var raw_parts: Variant = value.get("parts")
	if not raw_parts is Array:
		return _failure("invalid_parts")
	for part_value: Variant in raw_parts as Array:
		if not part_value is Dictionary:
			return _failure("invalid_part")
		var part := (part_value as Dictionary).duplicate(true)
		var part_id := String(part.get("part_id", "")).strip_edges()
		if part_id.is_empty() or part_id in result.parts.map(func(item: Dictionary) -> String: return String(item.get("part_id", ""))):
			return _failure("invalid_part_id")
		part["part_id"] = part_id
		result.parts.append(part)
	result.prefab_path = String(value.get("prefab_path", ""))
	return {"ok": true, "error": "", "value": result}


func snapshot() -> Dictionary:
	var ordered_parts := parts.duplicate(true)
	ordered_parts.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return String(left.get("part_id", "")) < String(right.get("part_id", ""))
	)
	return {
		"schema_version": SCHEMA_VERSION,
		"entity_id": entity_id,
		"feet_anchor": feet_anchor,
		"footprint": footprint.duplicate(true),
		"sort_baseline": sort_baseline,
		"parts": ordered_parts,
		"prefab_path": prefab_path,
	}


static func _vector_from(value: Variant, target: EntityDefinition, field: String) -> bool:
	if not value is Vector2:
		return false
	if not is_finite((value as Vector2).x) or not is_finite((value as Vector2).y):
		return false
	target.set(field, value)
	return true


static func _finite_positive(value: Variant) -> bool:
	return (value is int or value is float) and not (value is bool) and is_finite(float(value)) and float(value) > 0.0


static func _failure(error: String) -> Dictionary:
	return {"ok": false, "error": error, "value": null}
