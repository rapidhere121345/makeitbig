class_name ContentRegistry
extends RefCounted

## Loads the v2 proxy-component and v1 ranger-preset content from plain JSON
## (docs/GAME_DESIGN_FINAL_v1.0.md chapter 14 and sections 4.1 / 19.1) and
## performs structural validation only. Content files are pure data: this
## registry never instantiates, compiles, or executes anything from them.

const PROXY_PATH := "res://content/proxy_components.json"
const PRESET_PATH := "res://content/ranger_presets.json"
const EarlyCampaignRegistryScript = preload("res://src/content/early_campaign_registry.gd")
const EarlyItemRegistryScript = preload("res://src/content/early_item_registry.gd")
const EarlySkillRegistryScript = preload("res://src/content/early_skill_registry.gd")

const CORE_SLOTS: Array[String] = ["perception", "movement", "execution", "memory"]
const ATTACHMENT_CATEGORIES: Array[String] = ["scavenging", "navigation", "tactics", "cycle_tempo", "stability"]
const FIRMWARE_COMPATIBLE_SLOTS: Array[String] = ["perception", "movement", "execution", "memory", "attachment"]
const EXPECTED_PROXY_SCHEMA_VERSION := 2
const EXPECTED_PRESET_SCHEMA_VERSION := 1
const EXPECTED_CORES_PER_SLOT := 4
const EXPECTED_ATTACHMENTS_PER_CATEGORY := 2
const EXPECTED_FIRMWARE_COUNT := 16
const EXPECTED_FIRMWARE_PER_SLOT := {
	"perception": 3,
	"movement": 3,
	"execution": 4,
	"memory": 3,
	"attachment": 3,
}
const EXPECTED_NUMERIC_SLOTS := 3
const ATTACHMENT_PRESET_SIZE := 3
const REQUIRED_RANGER_SKILL := "piercing_arrow"
const REQUIRED_RANGER_RUNE := "breeding_split"
const REQUIRED_RANGER_LAW := "pack_hunt_mark"

var cores := {}
var attachments := {}
var firmwares := {}
var preset_shared_parameters := {}
var preset_equipped_parameters := {}
var presets := {}
var preset_order: Array[String] = []
var early_campaign_registry: Variant
var early_item_registry: Variant
var early_skill_registry: Variant


func load_all() -> Array[String]:
	cores.clear()
	attachments.clear()
	firmwares.clear()
	preset_shared_parameters.clear()
	preset_equipped_parameters.clear()
	presets.clear()
	preset_order.clear()
	early_campaign_registry = EarlyCampaignRegistryScript.new()
	early_item_registry = EarlyItemRegistryScript.new()
	early_skill_registry = EarlySkillRegistryScript.new()
	var failures: Array[String] = []
	failures.append_array(early_campaign_registry.load_campaign())
	failures.append_array(early_item_registry.load_all())
	failures.append_array(early_skill_registry.load_all())
	var proxy_data := _read_json(PROXY_PATH)
	if proxy_data.is_empty():
		failures.append("registry: cannot read/parse %s" % PROXY_PATH)
	else:
		failures.append_array(validate_proxy_components(proxy_data))
		if failures.is_empty():
			_ingest_proxy(proxy_data)
	var preset_data := _read_json(PRESET_PATH)
	if preset_data.is_empty():
		failures.append("registry: cannot read/parse %s" % PRESET_PATH)
	else:
		failures.append_array(validate_ranger_presets(preset_data))
		if failures.is_empty():
			_ingest_presets(preset_data)
	return failures


func validate_proxy_components(data: Dictionary) -> Array[String]:
	var failures: Array[String] = []
	_check_exact_fields(data, ["schema_version", "source", "note", "cores", "attachments", "firmwares"], [], "proxy", failures)
	if not _is_json_integer(data.get("schema_version", null)) or int(data.get("schema_version", -1)) != EXPECTED_PROXY_SCHEMA_VERSION:
		failures.append("proxy: schema_version must be integer %d" % EXPECTED_PROXY_SCHEMA_VERSION)
	_checked_text(data, "source", failures, "document", "proxy")
	_checked_text(data, "note", failures, "document", "proxy")
	var cores_value: Variant = data.get("cores", null)
	var attachments_value: Variant = data.get("attachments", null)
	var firmwares_value: Variant = data.get("firmwares", null)
	if not cores_value is Array:
		failures.append("proxy: cores must be an array")
	if not attachments_value is Array:
		failures.append("proxy: attachments must be an array")
	if not firmwares_value is Array:
		failures.append("proxy: firmwares must be an array")
	var cores_list: Array = cores_value if cores_value is Array else []
	var attachments_list: Array = attachments_value if attachments_value is Array else []
	var firmwares_list: Array = firmwares_value if firmwares_value is Array else []
	# No early exit on empty lists: the census checks below must still report
	# every missing slot, category, and firmware shortfall.
	var seen := {}
	var seen_behaviors := {}
	var per_slot := {}
	for slot in CORE_SLOTS:
		per_slot[slot] = 0
	var per_category := {}
	for category in ATTACHMENT_CATEGORIES:
		per_category[category] = 0
	for entry in cores_list:
		if not (entry is Dictionary):
			failures.append("proxy: core entry must be an object")
			continue
		var entry_dict: Dictionary = entry
		_check_exact_fields(entry_dict,
			["id", "name", "slot", "protocol", "numeric_slots", "behavior_id", "capabilities", "observation_channels", "state_fields", "command_kinds"],
			["settings_schema", "default_settings"], "core", failures)
		var id := _checked_id(entry_dict, seen, failures, "core")
		var slot := _checked_text(entry_dict, "slot", failures, id, "core")
		if slot != "" and slot not in CORE_SLOTS:
			failures.append("core %s: unknown slot '%s'" % [id, slot])
		elif slot != "":
			per_slot[slot] = int(per_slot[slot]) + 1
		_checked_name(entry_dict, id, failures, "core")
		_checked_text(entry_dict, "protocol", failures, id, "core")
		_checked_numeric_slots(entry_dict, id, failures, "core")
		var behavior_id := _checked_text(entry_dict, "behavior_id", failures, id, "core")
		if not behavior_id.is_empty() and seen_behaviors.has(behavior_id):
			failures.append("core %s: duplicate behavior_id '%s'" % [id, behavior_id])
		seen_behaviors[behavior_id] = true
		_checked_capabilities(entry_dict, failures, id)
		_checked_string_array(entry_dict, "observation_channels", failures, id, "core")
		_checked_string_array(entry_dict, "state_fields", failures, id, "core")
		_checked_string_array(entry_dict, "command_kinds", failures, id, "core")
		var has_schema := entry_dict.has("settings_schema")
		var has_defaults := entry_dict.has("default_settings")
		if has_schema != has_defaults:
			failures.append("core %s: settings_schema and default_settings must appear together" % id)
		elif has_schema:
			_validate_settings_contract(entry_dict.settings_schema, entry_dict.default_settings, id, failures)
	for entry in attachments_list:
		if not (entry is Dictionary):
			failures.append("proxy: attachment entry must be an object")
			continue
		var entry_dict: Dictionary = entry
		_check_exact_fields(entry_dict, ["id", "name", "category", "protocol", "numeric_slots"], [], "attachment", failures)
		var id := _checked_id(entry_dict, seen, failures, "attachment")
		var category := _checked_text(entry_dict, "category", failures, id, "attachment")
		if category != "" and category not in ATTACHMENT_CATEGORIES:
			failures.append("attachment %s: unknown category '%s'" % [id, category])
		elif category != "":
			per_category[category] = int(per_category[category]) + 1
		_checked_name(entry_dict, id, failures, "attachment")
		_checked_text(entry_dict, "protocol", failures, id, "attachment")
		_checked_numeric_slots(entry_dict, id, failures, "attachment")
	for slot in CORE_SLOTS:
		if int(per_slot[slot]) != EXPECTED_CORES_PER_SLOT:
			failures.append("proxy: core slot %s has %d entries, expected %d"
				% [slot, int(per_slot[slot]), EXPECTED_CORES_PER_SLOT])
	for category in ATTACHMENT_CATEGORIES:
		if int(per_category[category]) != EXPECTED_ATTACHMENTS_PER_CATEGORY:
			failures.append("proxy: attachment category %s has %d entries, expected %d"
				% [category, int(per_category[category]), EXPECTED_ATTACHMENTS_PER_CATEGORY])
	if firmwares_list.size() != EXPECTED_FIRMWARE_COUNT:
		failures.append("proxy: %d firmwares, expected %d"
			% [firmwares_list.size(), EXPECTED_FIRMWARE_COUNT])
	var firmware_per_slot := {}
	for slot in FIRMWARE_COMPATIBLE_SLOTS:
		firmware_per_slot[slot] = 0
	for entry in firmwares_list:
		if not (entry is Dictionary):
			failures.append("proxy: firmware entry must be an object")
			continue
		var entry_dict: Dictionary = entry
		_check_exact_fields(entry_dict, ["id", "name", "compatible_slot", "semantics"], [], "firmware", failures)
		var id := _checked_id(entry_dict, seen, failures, "firmware")
		var compatible := _checked_text(entry_dict, "compatible_slot", failures, id, "firmware")
		if compatible != "" and compatible not in FIRMWARE_COMPATIBLE_SLOTS:
			failures.append("firmware %s: unknown compatible_slot '%s'" % [id, compatible])
		elif compatible != "":
			firmware_per_slot[compatible] = int(firmware_per_slot[compatible]) + 1
		_checked_name(entry_dict, id, failures, "firmware")
		_checked_text(entry_dict, "semantics", failures, id, "firmware")
	for slot in FIRMWARE_COMPATIBLE_SLOTS:
		var expected: int = int(EXPECTED_FIRMWARE_PER_SLOT[slot])
		if int(firmware_per_slot[slot]) != expected:
			failures.append("proxy: firmware slot %s has %d entries, expected %d"
				% [slot, int(firmware_per_slot[slot]), expected])
	return failures


func validate_ranger_presets(data: Dictionary) -> Array[String]:
	var failures: Array[String] = []
	if data.get("schema_version", null) != EXPECTED_PRESET_SCHEMA_VERSION:
		failures.append("presets: schema_version must be %d" % EXPECTED_PRESET_SCHEMA_VERSION)
	var shared: Variant = data.get("shared_parameters", {})
	if not (shared is Dictionary) or (shared as Dictionary).is_empty():
		failures.append("presets: missing shared_parameters")
	else:
		failures.append_array(_validate_parameter_block(shared, "shared_parameters"))
	var equipped: Variant = data.get("prototype_equipped_parameters", {})
	if not (equipped is Dictionary) or (equipped as Dictionary).is_empty():
		failures.append("presets: missing prototype_equipped_parameters")
	else:
		failures.append_array(_validate_parameter_block(equipped, "prototype_equipped_parameters"))
	var preset_list: Variant = data.get("presets", [])
	if not (preset_list is Array) or (preset_list as Array).is_empty():
		failures.append("presets: missing presets list")
		return failures
	var seen := {}
	for entry in (preset_list as Array):
		if not (entry is Dictionary):
			failures.append("presets: preset entry must be an object")
			continue
		var entry_dict: Dictionary = entry
		var id := String(entry_dict.get("id", ""))
		if id == "":
			failures.append("presets: preset without an id")
			continue
		if seen.has(id):
			failures.append("presets: duplicate preset id '%s'" % id)
			continue
		seen[id] = true
		if String(entry_dict.get("name", "")) == "":
			failures.append("preset %s: missing name" % id)
		var p_value: Variant = entry_dict.get("p", null)
		if not _is_number(p_value):
			failures.append("preset %s: p must be a number" % id)
		elif _as_float(p_value) <= 0.0 or _as_float(p_value) > 1.0:
			failures.append("preset %s: p=%s out of range (0, 1]" % [id, str(p_value)])
		_validate_ranger_feature_list(entry_dict, "skills", REQUIRED_RANGER_SKILL, id, failures)
		_validate_ranger_feature_list(entry_dict, "runes", REQUIRED_RANGER_RUNE, id, failures, true)
		_validate_ranger_feature_list(entry_dict, "laws", REQUIRED_RANGER_LAW, id, failures, true)
		var equipment: Variant = entry_dict.get("equipment", null)
		if not (equipment is Dictionary):
			failures.append("preset %s: equipment must be an object" % id)
		else:
			for field in ["name", "description", "calibration", "parameter_source"]:
				_checked_text(equipment, field, failures, id, "preset equipment")
			if String((equipment as Dictionary).get("parameter_source", "")) != "prototype_equipped_parameters":
				failures.append("preset %s: equipment.parameter_source must be prototype_equipped_parameters" % id)
	return failures


func _validate_ranger_feature_list(
	entry: Dictionary,
	field: String,
	required_id: String,
	preset_id: String,
	failures: Array[String],
	require_semantics: bool = false
) -> void:
	var value: Variant = entry.get(field, null)
	if not (value is Array) or (value as Array).is_empty():
		failures.append("preset %s: %s must be a non-empty array" % [preset_id, field])
		return
	var seen := {}
	var found_required := false
	for item_value in (value as Array):
		if not (item_value is Dictionary):
			failures.append("preset %s: %s entry must be an object" % [preset_id, field])
			continue
		var item: Dictionary = item_value
		var item_id := _checked_text(item, "id", failures, preset_id, "preset %s" % field)
		_checked_text(item, "name", failures, preset_id, "preset %s" % field)
		if require_semantics:
			_checked_text(item, "semantics", failures, preset_id, "preset %s" % field)
		if seen.has(item_id):
			failures.append("preset %s: duplicate %s id '%s'" % [preset_id, field, item_id])
		seen[item_id] = true
		found_required = found_required or item_id == required_id
	if not found_required:
		failures.append("preset %s: %s must include '%s'" % [preset_id, field, required_id])


## An attachment preset equips the three untyped attachment slots.
## Same-category duplicates are forbidden by the design (chapter 14.1).
func validate_attachment_preset(attachment_ids: Array) -> Array[String]:
	var failures: Array[String] = []
	if attachment_ids.size() != ATTACHMENT_PRESET_SIZE:
		failures.append("attachment preset must equip exactly %d attachments"
			% ATTACHMENT_PRESET_SIZE)
	var seen_ids := {}
	var seen_categories := {}
	for raw_id in attachment_ids:
		var id := String(raw_id)
		if not attachments.has(id):
			failures.append("attachment preset: unknown attachment id '%s'" % id)
			continue
		if seen_ids.has(id):
			failures.append("attachment preset: duplicate attachment '%s'" % id)
			continue
		seen_ids[id] = true
		var category := String((attachments[id] as Dictionary).get("category", ""))
		if seen_categories.has(category):
			failures.append("attachment preset: category '%s' repeated" % category)
			continue
		seen_categories[category] = true
	return failures


func core_ids() -> Array:
	return cores.keys()


func attachment_ids() -> Array:
	return attachments.keys()


func firmware_ids() -> Array:
	return firmwares.keys()


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		return parsed
	return {}


func _ingest_proxy(data: Dictionary) -> void:
	for entry in (data.get("cores", []) as Array):
		cores[String(entry["id"])] = entry
	for entry in (data.get("attachments", []) as Array):
		attachments[String(entry["id"])] = entry
	for entry in (data.get("firmwares", []) as Array):
		firmwares[String(entry["id"])] = entry


func _ingest_presets(data: Dictionary) -> void:
	preset_shared_parameters = data.get("shared_parameters", {})
	preset_equipped_parameters = data.get("prototype_equipped_parameters", {})
	for entry in (data.get("presets", []) as Array):
		var id := String(entry["id"])
		presets[id] = entry
		preset_order.append(id)


func _validate_parameter_block(block: Dictionary, block_name: String) -> Array[String]:
	var failures: Array[String] = []
	for key in ["shared_lifetime", "distance", "speed", "minimum_turn_time"]:
		var value: Variant = block.get(key, null)
		if not _is_number(value):
			failures.append("presets: %s.%s must be a number" % [block_name, key])
		elif _as_float(value) <= 0.0:
			failures.append("presets: %s.%s must be positive" % [block_name, key])
	return failures


func _checked_id(entry: Dictionary, seen: Dictionary, failures: Array[String], kind: String) -> String:
	var raw_id: Variant = entry.get("id", null)
	if not raw_id is String or String(raw_id).strip_edges().is_empty():
		failures.append("%s entry without an id" % kind)
		return kind + "??"
	var id := String(raw_id)
	if seen.has(id):
		failures.append("duplicate id '%s' across proxy components" % id)
		return id
	seen[id] = true
	return id


func _checked_name(entry: Dictionary, id: String, failures: Array[String], kind: String) -> void:
	_checked_text(entry, "name", failures, id, kind)


func _checked_text(entry: Dictionary, key: String, failures: Array[String], id: String, kind: String) -> String:
	var raw_value: Variant = entry.get(key, null)
	var value: String = raw_value.strip_edges() if raw_value is String else ""
	if value.is_empty():
		failures.append("%s %s: missing %s" % [kind, id, key])
	return value


func _checked_numeric_slots(entry: Dictionary, id: String, failures: Array[String], kind: String) -> void:
	var value: Variant = entry.get("numeric_slots", null)
	if not _is_json_integer(value) or int(value) != EXPECTED_NUMERIC_SLOTS:
		failures.append("%s %s: numeric_slots must be %d (integer)" % [kind, id, EXPECTED_NUMERIC_SLOTS])


func _check_exact_fields(
	entry: Dictionary,
	required: Array,
	optional: Array,
	context: String,
	failures: Array[String]
) -> void:
	for field_value in required:
		var field := String(field_value)
		if not entry.has(field):
			failures.append("%s: missing field '%s'" % [context, field])
	for raw_key in entry.keys():
		if not raw_key is String:
			failures.append("%s: field names must be strings" % context)
			continue
		var key := String(raw_key)
		if key not in required and key not in optional:
			failures.append("%s: unknown field '%s'" % [context, key])


func _checked_string_array(
	entry: Dictionary,
	key: String,
	failures: Array[String],
	id: String,
	kind: String,
	require_non_empty: bool = false
) -> void:
	var value: Variant = entry.get(key, null)
	if not value is Array:
		failures.append("%s %s: %s must be an array" % [kind, id, key])
		return
	if require_non_empty and (value as Array).is_empty():
		failures.append("%s %s: %s must not be empty" % [kind, id, key])
	var seen_values := {}
	for item in (value as Array):
		if not item is String or String(item).strip_edges().is_empty():
			failures.append("%s %s: %s entries must be non-empty strings" % [kind, id, key])
			continue
		if seen_values.has(item):
			failures.append("%s %s: duplicate %s '%s'" % [kind, id, key, item])
		seen_values[item] = true


func _checked_capabilities(entry: Dictionary, failures: Array[String], id: String) -> void:
	var value: Variant = entry.get("capabilities", null)
	if not value is Dictionary or (value as Dictionary).is_empty():
		failures.append("core %s: capabilities must be a non-empty object" % id)
		return
	for raw_key in (value as Dictionary).keys():
		if not raw_key is String or String(raw_key).strip_edges().is_empty():
			failures.append("core %s: capability names must be non-empty strings" % id)
			continue
		if not _is_valid_capability_value((value as Dictionary)[raw_key]):
			failures.append("core %s: capability '%s' has an invalid value" % [id, String(raw_key)])


func _is_valid_capability_value(value: Variant) -> bool:
	if value is String:
		return not String(value).strip_edges().is_empty()
	if value is bool:
		return true
	if _is_number(value):
		return is_finite(float(value))
	if value is Array:
		if (value as Array).is_empty():
			return false
		for item in (value as Array):
			if not _is_valid_capability_value(item) or item is Array:
				return false
		return true
	return false


func _validate_settings_contract(schema_value: Variant, defaults_value: Variant, core_id: String, failures: Array[String]) -> void:
	if not schema_value is Dictionary:
		failures.append("core %s: settings_schema must be an object" % core_id)
		return
	if not defaults_value is Dictionary:
		failures.append("core %s: default_settings must be an object" % core_id)
		return
	var schema: Dictionary = schema_value
	var defaults: Dictionary = defaults_value
	_check_exact_fields(schema, ["type", "additional_properties", "properties", "required"], [], "core %s settings_schema" % core_id, failures)
	if schema.get("type", null) != "object":
		failures.append("core %s: settings_schema.type must be 'object'" % core_id)
	if not schema.get("additional_properties", null) is bool or bool(schema.get("additional_properties", true)):
		failures.append("core %s: settings_schema.additional_properties must be false" % core_id)
	var properties_value: Variant = schema.get("properties", null)
	var required_value: Variant = schema.get("required", null)
	if not properties_value is Dictionary:
		failures.append("core %s: settings_schema.properties must be an object" % core_id)
		return
	if not required_value is Array:
		failures.append("core %s: settings_schema.required must be an array" % core_id)
		return
	var properties: Dictionary = properties_value
	var required: Array = required_value
	var required_seen := {}
	for field_value in required:
		if not field_value is String or String(field_value).is_empty():
			failures.append("core %s: settings_schema.required entries must be non-empty strings" % core_id)
			continue
		var field := String(field_value)
		if required_seen.has(field):
			failures.append("core %s: duplicate required setting '%s'" % [core_id, field])
		required_seen[field] = true
		if not properties.has(field):
			failures.append("core %s: required setting '%s' has no property schema" % [core_id, field])
	for field_value in properties.keys():
		if not field_value is String or String(field_value).is_empty():
			failures.append("core %s: setting names must be non-empty strings" % core_id)
			continue
		var field := String(field_value)
		_validate_setting_rule(properties[field], core_id, field, failures)
		if not defaults.has(field):
			failures.append("core %s: default_settings missing '%s'" % [core_id, field])
		elif not _setting_value_valid(defaults[field], properties[field]):
			failures.append("core %s: default_settings.%s does not match settings_schema" % [core_id, field])
	for raw_key in defaults.keys():
		if not raw_key is String or not properties.has(raw_key):
			failures.append("core %s: default_settings has unknown field '%s'" % [core_id, str(raw_key)])


func _validate_setting_rule(rule_value: Variant, core_id: String, field: String, failures: Array[String]) -> void:
	if not rule_value is Dictionary:
		failures.append("core %s: setting '%s' schema must be an object" % [core_id, field])
		return
	var rule: Dictionary = rule_value
	_check_exact_fields(rule, ["type"], ["enum", "minimum", "maximum"], "core %s setting %s" % [core_id, field], failures)
	var setting_type := String(rule.get("type", ""))
	if setting_type not in ["string", "integer", "number", "boolean"]:
		failures.append("core %s: setting '%s' has unsupported type '%s'" % [core_id, field, setting_type])
	if rule.has("enum"):
		var enum_value: Variant = rule.enum
		if not enum_value is Array or (enum_value as Array).is_empty():
			failures.append("core %s: setting '%s' enum must be a non-empty array" % [core_id, field])
		else:
			for value in (enum_value as Array):
				if not _setting_type_matches(value, setting_type):
					failures.append("core %s: setting '%s' enum value has the wrong type" % [core_id, field])
	for bound in ["minimum", "maximum"]:
		if rule.has(bound) and (setting_type not in ["integer", "number"] or not _is_number(rule[bound])):
			failures.append("core %s: setting '%s' %s must be numeric" % [core_id, field, bound])
	if rule.has("minimum") and rule.has("maximum") and float(rule.minimum) > float(rule.maximum):
		failures.append("core %s: setting '%s' minimum exceeds maximum" % [core_id, field])


func _setting_value_valid(value: Variant, rule_value: Variant) -> bool:
	if not rule_value is Dictionary:
		return false
	var rule: Dictionary = rule_value
	var setting_type := String(rule.get("type", ""))
	if not _setting_type_matches(value, setting_type):
		return false
	if rule.has("enum") and (not rule.enum is Array or value not in rule.enum):
		return false
	if rule.has("minimum") and float(value) < float(rule.minimum):
		return false
	if rule.has("maximum") and float(value) > float(rule.maximum):
		return false
	return true


func _setting_type_matches(value: Variant, setting_type: String) -> bool:
	match setting_type:
		"string":
			return value is String
		"integer":
			return _is_json_integer(value)
		"number":
			return value is int or value is float
		"boolean":
			return value is bool
	return false


func _is_number(value: Variant) -> bool:
	return value is int or value is float


func _is_json_integer(value: Variant) -> bool:
	return _is_number(value) and is_finite(float(value)) and float(value) == floor(float(value))


func _as_float(value: Variant) -> float:
	if value is int or value is float:
		return float(value)
	return -1.0
