class_name ProxyBuild
extends RefCounted

## Compiler and sole validator for machine-only resolved proxy builds.

const RESOLVED_SCHEMA_VERSION := 1
const SLOT_ORDER: Array[String] = ["perception", "movement", "execution", "memory"]
const SUPPORTED_BEHAVIORS: Array[String] = ["near_enemy_horizon", "marking_prism", "direct_gait", "distance_keeping_gait", "single_key_execution", "short_trace_memory"]
const REQUIRED_CORE_FIELDS: Array[String] = ["id", "name", "slot", "protocol", "numeric_slots", "behavior_id", "capabilities", "observation_channels", "state_fields", "command_kinds"]
const OPTIONAL_CORE_FIELDS: Array[String] = ["settings_schema", "default_settings"]
const RESOLVED_FIELDS: Array[String] = ["schema_version", "cores", "observation_contract", "state_contract", "command_contract", "semantic_fingerprint"]
const RESOLVED_CORE_FIELDS: Array[String] = ["slot", "core_id", "behavior_id", "capabilities", "observation_channels", "state_fields", "command_kinds", "settings"]


static func compile(raw_build: Variant, core_catalog: Variant) -> Dictionary:
	var raw_copy: Variant = raw_build.duplicate(true) if raw_build is Dictionary else raw_build
	var catalog_copy: Variant = core_catalog.duplicate(true) if core_catalog is Dictionary else core_catalog
	if not raw_copy is Dictionary:
		return _failure("invalid_raw_build")
	if not catalog_copy is Dictionary:
		return _failure("invalid_core_catalog")
	var raw: Dictionary = raw_copy
	var catalog: Dictionary = catalog_copy
	if not _has_exact_fields(raw, ["cores"], ["settings"]):
		return _failure("invalid_raw_build")
	var core_ids_value: Variant = raw.get("cores", null)
	if not core_ids_value is Array or (core_ids_value as Array).size() != SLOT_ORDER.size():
		return _failure("invalid_core_count")
	var settings_value: Variant = raw.get("settings", {})
	if not settings_value is Dictionary:
		return _failure("invalid_settings")
	var raw_settings: Dictionary = settings_value
	var selected := {}
	var selected_ids: Array[String] = []
	for id_value in (core_ids_value as Array):
		if not id_value is String or String(id_value).strip_edges().is_empty():
			return _failure("invalid_core_id")
		var core_id := String(id_value)
		if core_id in selected_ids:
			return _failure("duplicate_core_id:%s" % core_id)
		selected_ids.append(core_id)
		if not catalog.has(core_id) or not catalog[core_id] is Dictionary:
			return _failure("unknown_core:%s" % core_id)
		var core: Dictionary = catalog[core_id]
		var catalog_error := _validate_catalog_core(core_id, core)
		if not catalog_error.is_empty():
			return _failure(catalog_error)
		var slot := String(core.slot)
		if selected.has(slot):
			return _failure("duplicate_slot:%s" % slot)
		selected[slot] = core
	for slot in SLOT_ORDER:
		if not selected.has(slot):
			return _failure("missing_slot:%s" % slot)
	for settings_core_value in raw_settings.keys():
		if not settings_core_value is String:
			return _failure("invalid_settings_key")
		var settings_core_id := String(settings_core_value)
		if settings_core_id not in selected_ids:
			return _failure("settings_for_unselected_core:%s" % settings_core_id)

	var resolved_cores: Array[Dictionary] = []
	for slot in SLOT_ORDER:
		var core: Dictionary = selected[slot]
		var core_id := String(core.id)
		var behavior_id := String(core.behavior_id)
		if behavior_id not in SUPPORTED_BEHAVIORS:
			return _failure("unsupported_behavior:%s" % behavior_id)
		var settings_result := _resolve_settings(core_id, core, raw_settings)
		if not settings_result.ok:
			return _failure(String(settings_result.error))
		var state_fields := _sorted_strings(core.state_fields)
		if behavior_id == "marking_prism" and "candidate_entity_ids" not in state_fields:
			state_fields.append("candidate_entity_ids")
			state_fields.sort()
		resolved_cores.append({
			"slot": slot,
			"core_id": core_id,
			"behavior_id": behavior_id,
			"capabilities": _canonical_capabilities(core.capabilities, behavior_id),
			"observation_channels": _sorted_strings(core.observation_channels),
			"state_fields": state_fields,
			"command_kinds": _sorted_strings(core.command_kinds),
			"settings": settings_result.value,
		})
	var payload := _payload_from_cores(resolved_cores)
	var core_error := _validate_resolved_cores(payload.cores)
	if not core_error.is_empty():
		return _failure(core_error)
	return _seal_payload(payload)


## Strictly validates, canonicalizes, isolates, and freezes a resolved build.
static func normalize_resolved(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return _failure("invalid_resolved_build")
	var source: Dictionary = value.duplicate(true)
	if not _has_exact_fields(source, RESOLVED_FIELDS, []):
		return _failure("invalid_resolved_build")
	if not source.schema_version is int or int(source.schema_version) != RESOLVED_SCHEMA_VERSION:
		return _failure("wrong_resolved_schema_version")
	if not source.cores is Array:
		return _failure("invalid_resolved_build")
	var canonical_cores: Array[Dictionary] = []
	for core_value in source.cores:
		if not core_value is Dictionary:
			return _failure("invalid_resolved_core")
		var core: Dictionary = core_value
		if not _has_exact_fields(core, RESOLVED_CORE_FIELDS, []) or not core.capabilities is Dictionary or not core.settings is Dictionary:
			return _failure("invalid_resolved_core")
		for field in ["observation_channels", "state_fields", "command_kinds"]:
			if not _valid_string_set(core[field], false):
				return _failure("invalid_resolved_core_contract")
		canonical_cores.append({
			"slot": String(core.slot),
			"core_id": String(core.core_id),
			"behavior_id": String(core.behavior_id),
			"capabilities": _canonical_capabilities(core.capabilities, String(core.behavior_id)),
			"observation_channels": _sorted_strings(core.observation_channels),
			"state_fields": _sorted_strings(core.state_fields),
			"command_kinds": _sorted_strings(core.command_kinds),
			"settings": _canonical_dictionary(core.settings),
		})
	var core_error := _validate_resolved_cores(canonical_cores)
	if not core_error.is_empty():
		return _failure(core_error)
	var payload := _payload_from_cores(canonical_cores)
	for contract_field in ["observation_contract", "state_contract", "command_contract"]:
		if not _valid_string_set(source[contract_field], false) or _sorted_strings(source[contract_field]) != payload[contract_field]:
			return _failure("invalid_resolved_contract")
	if not source.semantic_fingerprint is String or not _is_hex_fingerprint(String(source.semantic_fingerprint)):
		return _failure("invalid_semantic_fingerprint")
	if String(source.semantic_fingerprint) != _semantic_fingerprint(payload):
		return _failure("semantic_fingerprint_mismatch")
	return _seal_payload(payload)


static func _validate_catalog_core(catalog_id: String, core: Dictionary) -> String:
	if not _has_exact_fields(core, REQUIRED_CORE_FIELDS, OPTIONAL_CORE_FIELDS):
		return "invalid_core_catalog:%s" % catalog_id
	if core.id != catalog_id or not core.name is String or String(core.name).strip_edges().is_empty():
		return "invalid_core_catalog:%s" % catalog_id
	if not core.protocol is String or String(core.protocol).strip_edges().is_empty():
		return "invalid_core_catalog:%s" % catalog_id
	if not _is_json_integer(core.numeric_slots) or int(core.numeric_slots) != 3:
		return "invalid_core_catalog:%s" % catalog_id
	if not core.slot is String or String(core.slot) not in SLOT_ORDER:
		return "invalid_core_catalog:%s" % catalog_id
	if not core.behavior_id is String or String(core.behavior_id).strip_edges().is_empty():
		return "invalid_core_catalog:%s" % catalog_id
	if not _valid_capabilities(core.get("capabilities", null)):
		return "invalid_core_catalog:%s" % catalog_id
	for field in ["observation_channels", "state_fields", "command_kinds"]:
		if not _valid_string_set(core.get(field, null), false):
			return "invalid_core_catalog:%s" % catalog_id
	if core.has("settings_schema") != core.has("default_settings"):
		return "invalid_core_catalog:%s" % catalog_id
	if core.has("settings_schema") and not _valid_settings_contract(core.settings_schema, core.default_settings):
		return "invalid_core_catalog:%s" % catalog_id
	return ""


static func _validate_resolved_cores(cores_value: Variant) -> String:
	if not cores_value is Array or (cores_value as Array).size() != SLOT_ORDER.size():
		return "invalid_resolved_cores"
	var seen_ids := {}
	for index in SLOT_ORDER.size():
		var core_value: Variant = (cores_value as Array)[index]
		if not core_value is Dictionary:
			return "invalid_resolved_core"
		var core: Dictionary = core_value
		if not _has_exact_fields(core, RESOLVED_CORE_FIELDS, []):
			return "invalid_resolved_core"
		var slot := SLOT_ORDER[index]
		if not core.slot is String or String(core.slot) != slot:
			return "invalid_resolved_slot_order"
		if not core.core_id is String or String(core.core_id).strip_edges().is_empty() or seen_ids.has(core.core_id):
			return "invalid_resolved_core"
		seen_ids[core.core_id] = true
		if not core.behavior_id is String or String(core.behavior_id) not in SUPPORTED_BEHAVIORS:
			return "unsupported_resolved_behavior"
		if not _behavior_matches_slot(String(core.behavior_id), slot):
			return "invalid_resolved_behavior_slot"
		if not _valid_capabilities(core.capabilities) or not _valid_behavior_contract(core):
			return "invalid_resolved_core_contract"
		for field in ["observation_channels", "state_fields", "command_kinds"]:
			if not _valid_string_set(core[field], false) or core[field] != _sorted_strings(core[field]):
				return "invalid_resolved_core_contract"
		if not core.settings is Dictionary or not _valid_resolved_settings(String(core.behavior_id), core.settings):
			return "invalid_resolved_settings"
	return ""


static func _valid_behavior_contract(core: Dictionary) -> bool:
	var behavior := String(core.behavior_id)
	var caps: Dictionary = core.capabilities
	match behavior:
		"near_enemy_horizon":
			return _exact_array(core.observation_channels, ["actor.position", "enemy.basic"]) and _exact_array(core.state_fields, ["next_perception_tick"]) and core.command_kinds.is_empty() and _exact_keys(caps, ["candidate_limit", "recognition", "refresh_period_ticks", "select", "target_count"]) and _positive_integer(caps.candidate_limit) and int(caps.candidate_limit) == 1 and _positive_number(caps.recognition) and _positive_integer(caps.refresh_period_ticks) and caps.select == "nearest_visible_legal_enemy" and _positive_integer(caps.target_count) and int(caps.target_count) == 1
		"marking_prism":
			return _exact_array(core.observation_channels, ["actor.position", "enemy.basic", "enemy.public_classification_tags"]) and _exact_array(core.state_fields, ["candidate_entity_ids", "next_perception_tick"]) and core.command_kinds.is_empty() and _exact_keys(caps, ["candidate_limit", "classification", "recognition", "refresh_period_ticks", "select", "target_count"]) and _positive_integer(caps.candidate_limit) and int(caps.candidate_limit) == 2 and _positive_number(caps.classification) and _positive_number(caps.recognition) and _positive_integer(caps.refresh_period_ticks) and caps.select == "marked_elite_boss" and _positive_integer(caps.target_count) and int(caps.target_count) == 2
		"direct_gait":
			return _movement_surface(core) and _exact_keys(caps, ["approach_enter_targeting_distance_milli", "approach_exit_targeting_distance_milli", "fixed_safety_band", "pathing", "range_control", "retreat_enter_targeting_distance_milli", "retreat_exit_targeting_distance_milli", "skill_range_source"]) and caps.skill_range_source == "skill_1_targeting_distance" and _valid_thresholds([caps.retreat_enter_targeting_distance_milli, caps.retreat_exit_targeting_distance_milli, caps.approach_exit_targeting_distance_milli, caps.approach_enter_targeting_distance_milli]) and _positive_number(caps.fixed_safety_band) and _positive_number(caps.pathing) and _positive_number(caps.range_control)
		"distance_keeping_gait":
			return _movement_surface(core) and _exact_keys(caps, ["distance_profiles", "far_band_milli", "mid_band_milli", "near_band_milli", "pathing", "range_control", "ratio_source", "threshold_order"]) and _positive_integer(caps.distance_profiles) and int(caps.distance_profiles) == 3 and caps.ratio_source == "skill_1_targeting_distance" and caps.threshold_order == ["retreat_enter", "retreat_exit", "approach_exit", "approach_enter"] and _valid_thresholds(caps.near_band_milli) and _valid_thresholds(caps.mid_band_milli) and _valid_thresholds(caps.far_band_milli) and _positive_number(caps.pathing) and _positive_number(caps.range_control)
		"single_key_execution":
			return _exact_array(core.observation_channels, ["actor.action_state", "enemy.basic", "skill_1.readiness", "skill_1.targeting_distance"]) and core.state_fields.is_empty() and _exact_array(core.command_kinds, ["piercing_arrow"]) and _exact_keys(caps, ["ability", "ability_id", "skill_count", "timing"]) and caps.ability == "skill_1" and caps.ability_id == "piercing_arrow" and _positive_integer(caps.skill_count) and int(caps.skill_count) == 1 and _positive_number(caps.timing)
		"short_trace_memory":
			return core.observation_channels.is_empty() and _exact_array(core.state_fields, ["last_committed_action", "target_entity_id"]) and core.command_kinds.is_empty() and _exact_keys(caps, ["remember", "rotation_steps", "target_memory"]) and caps.remember == ["last_committed_action", "target_entity_id"] and _positive_integer(caps.rotation_steps) and int(caps.rotation_steps) == 1 and _positive_integer(caps.target_memory) and int(caps.target_memory) == 1
	return false


static func _movement_surface(core: Dictionary) -> bool:
	return _exact_array(core.observation_channels, ["actor.facing", "actor.position", "enemy.basic", "skill_1.targeting_distance", "walkable_geometry"]) and _exact_array(core.state_fields, ["movement_band"]) and _exact_array(core.command_kinds, ["move", "stop_move"])


static func _behavior_matches_slot(behavior: String, slot: String) -> bool:
	return (slot == "perception" and behavior in ["near_enemy_horizon", "marking_prism"]) or (slot == "movement" and behavior in ["direct_gait", "distance_keeping_gait"]) or (slot == "execution" and behavior == "single_key_execution") or (slot == "memory" and behavior == "short_trace_memory")


static func _valid_resolved_settings(behavior: String, settings: Dictionary) -> bool:
	if behavior == "distance_keeping_gait":
		return _exact_keys(settings, ["distance_band"]) and settings.distance_band is String and String(settings.distance_band) in ["near", "mid", "far"]
	return settings.is_empty()


static func _payload_from_cores(cores: Array[Dictionary]) -> Dictionary:
	var observations: Array[String] = []
	var state_fields: Array[String] = []
	var commands: Array[String] = []
	for core in cores:
		_append_unique(observations, core.observation_channels)
		_append_unique(state_fields, core.state_fields)
		_append_unique(commands, core.command_kinds)
	observations.sort()
	state_fields.sort()
	commands.sort()
	return {"schema_version": RESOLVED_SCHEMA_VERSION, "cores": cores, "observation_contract": observations, "state_contract": state_fields, "command_contract": commands}


static func _seal_payload(payload: Dictionary) -> Dictionary:
	var resolved := payload.duplicate(true)
	resolved["semantic_fingerprint"] = _semantic_fingerprint(payload)
	_deep_make_read_only(resolved)
	var result := {"ok": true, "value": resolved}
	result.make_read_only()
	return result


static func _semantic_fingerprint(payload: Dictionary) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(JSON.stringify(payload).to_utf8_buffer())
	return context.finish().hex_encode()


static func _resolve_settings(core_id: String, core: Dictionary, raw_settings: Dictionary) -> Dictionary:
	if not core.has("settings_schema"):
		if raw_settings.has(core_id):
			return {"ok": false, "error": "unexpected_settings:%s" % core_id}
		return {"ok": true, "value": {}}
	var source: Variant = raw_settings[core_id] if raw_settings.has(core_id) else core.default_settings
	if not source is Dictionary or not _settings_match(source, core.settings_schema):
		return {"ok": false, "error": "invalid_settings:%s" % core_id}
	return {"ok": true, "value": _canonical_dictionary(source)}


static func _valid_settings_contract(schema_value: Variant, defaults_value: Variant) -> bool:
	if not schema_value is Dictionary or not defaults_value is Dictionary:
		return false
	var schema: Dictionary = schema_value
	if not _has_exact_fields(schema, ["type", "additional_properties", "properties", "required"], []):
		return false
	if schema.type != "object" or not schema.additional_properties is bool or bool(schema.additional_properties) or not schema.properties is Dictionary or not schema.required is Array:
		return false
	var properties: Dictionary = schema.properties
	if properties.is_empty() or schema.required.size() != properties.size():
		return false
	for field_value in properties.keys():
		if not field_value is String or field_value not in schema.required or not properties[field_value] is Dictionary or not _valid_setting_rule(properties[field_value]):
			return false
	for field_value in schema.required:
		if not field_value is String or not properties.has(field_value):
			return false
	return _settings_match(defaults_value, schema)


static func _valid_setting_rule(rule: Dictionary) -> bool:
	if not _has_exact_fields(rule, ["type"], ["enum", "minimum", "maximum"]):
		return false
	var setting_type := String(rule.type)
	if setting_type not in ["string", "integer", "number", "boolean"]:
		return false
	if rule.has("enum"):
		if not rule.enum is Array or rule.enum.is_empty():
			return false
		for value in rule.enum:
			if not _setting_type_matches(value, setting_type):
				return false
	for bound in ["minimum", "maximum"]:
		if rule.has(bound) and (setting_type not in ["integer", "number"] or not _is_number(rule[bound])):
			return false
	return not (rule.has("minimum") and rule.has("maximum") and float(rule.minimum) > float(rule.maximum))


static func _settings_match(settings_value: Variant, schema: Dictionary) -> bool:
	if not settings_value is Dictionary:
		return false
	var settings: Dictionary = settings_value
	var properties: Dictionary = schema.properties
	for field_value in schema.required:
		if not settings.has(field_value):
			return false
	for raw_key in settings.keys():
		if not raw_key is String or not properties.has(raw_key):
			return false
		var rule: Dictionary = properties[raw_key]
		var setting: Variant = settings[raw_key]
		if not _setting_type_matches(setting, String(rule.type)) or rule.has("enum") and setting not in rule.enum or rule.has("minimum") and float(setting) < float(rule.minimum) or rule.has("maximum") and float(setting) > float(rule.maximum):
			return false
	return true


static func _setting_type_matches(value: Variant, setting_type: String) -> bool:
	match setting_type:
		"string": return value is String
		"integer": return _is_json_integer(value)
		"number": return _is_number(value)
		"boolean": return value is bool
	return false


static func _valid_capabilities(value: Variant) -> bool:
	if not value is Dictionary or (value as Dictionary).is_empty():
		return false
	for raw_key in (value as Dictionary).keys():
		if not raw_key is String or String(raw_key).strip_edges().is_empty() or not _valid_capability_value((value as Dictionary)[raw_key]):
			return false
	return true


static func _valid_capability_value(value: Variant) -> bool:
	if value is String:
		return not String(value).strip_edges().is_empty()
	if value is bool:
		return true
	if _is_number(value):
		return is_finite(float(value))
	if value is Array:
		if value.is_empty():
			return false
		for item in value:
			if item is Array or item is Dictionary or not _valid_capability_value(item):
				return false
		return true
	return false


static func _valid_string_set(value: Variant, require_non_empty: bool) -> bool:
	if not value is Array or (require_non_empty and value.is_empty()):
		return false
	var seen := {}
	for item in value:
		if not item is String or String(item).strip_edges().is_empty() or seen.has(item):
			return false
		seen[item] = true
	return true


static func _canonical_capabilities(values: Dictionary, behavior: String) -> Dictionary:
	var result := _canonical_dictionary(values)
	if behavior == "short_trace_memory" and result.get("remember", null) is Array:
		var remember: Array = result.remember.duplicate(true)
		remember.sort()
		result.remember = remember
	return result


static func _canonical_dictionary(values: Dictionary) -> Dictionary:
	var result := {}
	var keys: Array = values.keys()
	keys.sort()
	for raw_key in keys:
		var value: Variant = values[raw_key]
		result[String(raw_key)] = value.duplicate(true) if value is Array or value is Dictionary else value
	return result


static func _has_exact_fields(value: Dictionary, required: Array, optional: Array) -> bool:
	for field in required:
		if not value.has(field):
			return false
	for raw_key in value.keys():
		if not raw_key is String or raw_key not in required and raw_key not in optional:
			return false
	return true


static func _exact_keys(value: Dictionary, expected: Array) -> bool:
	return _has_exact_fields(value, expected, []) and value.size() == expected.size()


static func _exact_array(value: Variant, expected: Array) -> bool:
	return value is Array and value == expected


static func _valid_thresholds(value: Variant) -> bool:
	if not value is Array or value.size() != 4:
		return false
	var prior := -1
	for item in value:
		if not _positive_integer(item) or int(item) <= prior:
			return false
		prior = int(item)
	return true


static func _positive_integer(value: Variant) -> bool:
	return _is_json_integer(value) and int(value) > 0


static func _positive_number(value: Variant) -> bool:
	return _is_number(value) and is_finite(float(value)) and float(value) > 0.0


static func _is_number(value: Variant) -> bool:
	return value is int or value is float


static func _is_json_integer(value: Variant) -> bool:
	return _is_number(value) and is_finite(float(value)) and float(value) == floor(float(value))


static func _sorted_strings(values: Array) -> Array[String]:
	var result: Array[String] = []
	for value in values:
		result.append(String(value))
	result.sort()
	return result


static func _append_unique(target: Array[String], values: Array) -> void:
	for value in values:
		if String(value) not in target:
			target.append(String(value))


static func _is_hex_fingerprint(value: String) -> bool:
	if value.length() != 64:
		return false
	for character in value:
		if character not in "0123456789abcdef":
			return false
	return true


static func _deep_make_read_only(value: Variant) -> void:
	if value is Dictionary:
		for key in value.keys():
			_deep_make_read_only(value[key])
		value.make_read_only()
	elif value is Array:
		for item in value:
			_deep_make_read_only(item)
		value.make_read_only()


static func _failure(error: String) -> Dictionary:
	var result := {"ok": false, "error": error}
	result.make_read_only()
	return result
