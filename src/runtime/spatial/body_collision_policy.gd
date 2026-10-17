class_name BodyCollisionPolicy
extends RefCounted

## How dynamic contacts affect movement resolution.
##
## solid: the body blocks and slides like static geometry.
## soft:  the body never blocks; the mover is separated after the sweep phase
##        and every separation displacement is re-validated against the static
##        movement channel.
## ghost: the body is recorded but has no positional effect at all.

const CLASS_SOLID := &"solid"
const CLASS_SOFT := &"soft"
const CLASS_GHOST := &"ghost"

const RESPONSE_BLOCK := &"block"
const RESPONSE_SEPARATE := &"separate"
const RESPONSE_IGNORE := &"ignore"

const CLASSES: Array[StringName] = [CLASS_SOLID, CLASS_SOFT, CLASS_GHOST]
const RESPONSES: Array[StringName] = [RESPONSE_BLOCK, RESPONSE_SEPARATE, RESPONSE_IGNORE]

var _solid := {"response": RESPONSE_BLOCK, "record": true}
var _soft := {"response": RESPONSE_SEPARATE, "record": true}
var _ghost := {"response": RESPONSE_IGNORE, "record": true}


static func make_default() -> BodyCollisionPolicy:
	var policy: BodyCollisionPolicy = load("res://src/runtime/spatial/body_collision_policy.gd").new()
	return policy


static func make(mapping: Variant) -> Dictionary:
	var errors: Array[String] = []
	if not mapping is Dictionary:
		return {"ok": false, "errors": ["policy:invalid_type"], "value": null}
	var source: Dictionary = mapping
	for key: Variant in source.keys():
		var key_text := str(key)
		if not CLASSES.has(StringName(key_text)):
			errors.append("policy:unknown_class:%s" % key_text)
	if not errors.is_empty():
		return {"ok": false, "errors": errors, "value": null}
	var policy := make_default()
	for class_key: StringName in CLASSES:
		if not source.has(String(class_key)):
			errors.append("policy:missing_class:%s" % String(class_key))
			continue
		var entry: Variant = source[String(class_key)]
		if not entry is Dictionary:
			errors.append("policy.%s:invalid_type" % String(class_key))
			continue
		var entry_dict: Dictionary = entry
		for field: Variant in entry_dict.keys():
			if not ["response", "record"].has(String(field)):
				errors.append("policy.%s:unknown_field:%s" % [String(class_key), String(field)])
		var response := StringName(str(entry_dict.get("response", "")))
		if not RESPONSES.has(response):
			errors.append("policy.%s.response:unknown:%s" % [String(class_key), String(response)])
			continue
		var record := bool(entry_dict.get("record", true))
		policy._set_entry(class_key, {"response": response, "record": record})
	if not errors.is_empty():
		return {"ok": false, "errors": errors, "value": null}
	return {"ok": true, "errors": [], "value": policy}


func response_for(collision_class: StringName) -> Dictionary:
	match collision_class:
		CLASS_SOLID:
			return _solid.duplicate()
		CLASS_SOFT:
			return _soft.duplicate()
		CLASS_GHOST:
			return _ghost.duplicate()
	return {"response": RESPONSE_IGNORE, "record": true}


func snapshot() -> Dictionary:
	return {
		"solid": _solid.duplicate(),
		"soft": _soft.duplicate(),
		"ghost": _ghost.duplicate(),
	}


func _set_entry(class_key: StringName, value: Dictionary) -> void:
	match class_key:
		CLASS_SOLID:
			_solid = value
		CLASS_SOFT:
			_soft = value
		CLASS_GHOST:
			_ghost = value
