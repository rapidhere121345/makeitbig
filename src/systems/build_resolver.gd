class_name BuildResolver
extends RefCounted

const EarlyRegistry = preload("res://src/content/early_item_registry.gd")
const ArrowModel = preload("res://src/systems/piercing_arrow_model.gd")
const TalentBuildScript = preload("res://src/systems/talent_build.gd")
const RangerSkillRulesScript = preload("res://src/systems/ranger_skill_rules.gd")
const SaveStoreScript = preload("res://src/persistence/save_store.gd")

const REQUIRED_PARAMETERS: Array[String] = ["p", "T", "v", "d", "turn", "damage"]
const OPTIONAL_DEFAULTS := {"critical_chance": 0.0, "max_health": 1.0}
const PARAMETER_ALIASES := {
	"shared_lifetime": "T",
	"speed": "v",
	"distance": "d",
	"minimum_turn_time": "turn",
}

var registry
var registry_load_errors: Array[String] = []
var talent_build


func _init(content_registry = null) -> void:
	registry = content_registry
	if registry == null:
		registry = EarlyRegistry.new()
		registry_load_errors = registry.load_all()
	talent_build = TalentBuildScript.new()


func resolve_fixture(fixture_id: String) -> Dictionary:
	if registry == null or not registry.build_fixtures.has(fixture_id):
		return _error_result(["build: unknown build fixture '%s'" % fixture_id])
	var fixture: Dictionary = registry.build_fixtures[fixture_id]
	var equipment: Dictionary = registry.equipment_for_fixture(fixture_id)
	if equipment.size() != EarlyRegistry.PROTOTYPE_OPEN_SLOTS.size():
		return _error_result(["build: fixture '%s' has unresolved equipment references" % fixture_id])
	return resolve(
		(fixture.base_parameters as Dictionary).duplicate(true),
		equipment,
		String(fixture.skill_id)
	)


## Pure deterministic evaluation over immutable input snapshots. No runtime or
## application state is read or written. Invalid input returns errors instead of
## asserting or throwing.
func resolve(
	base_parameters: Variant,
	equipped_items: Variant,
	skill: Variant = "piercing_arrow",
	talent_context: Variant = null
) -> Dictionary:
	var errors: Array[String] = []
	if registry == null or registry.base_items.is_empty():
		errors.append("build: early item registry is not loaded")
	for registry_error in registry_load_errors:
		errors.append("build: %s" % registry_error)
	var skill_id := _feature_id(skill, "skill", errors)
	if skill_id != "" and skill_id != "piercing_arrow":
		errors.append("build: unsupported prototype skill '%s'" % skill_id)
	var parameters := _normalize_base_parameters(base_parameters, errors)
	if not equipped_items is Dictionary:
		errors.append("build: equipped_items must be a slot-to-ItemInstance object")
		return _error_result(errors)
	if not errors.is_empty():
		return _error_result(errors)
	var normalized_base_parameters: Dictionary = parameters.duplicate(true)
	var talent_compiled := _compile_talents(talent_context, errors)

	var sources: Dictionary = {}
	for parameter in EarlyRegistry.PARAMETERS:
		sources[parameter] = [{
			"source_kind": "character_base",
			"source_id": "character_base",
			"operation": "set",
			"value": float(parameters[parameter]),
			"before": 0.0,
			"after": float(parameters[parameter]),
		}]

	# ItemInstance is the sole semantic source. Callers can only select owned
	# instances; rune/law arrays never enter the resolver as independent input.
	var semantic_runes: Array[String] = []
	var semantic_laws: Array[String] = []
	var equipped_instance_ids := _empty_equipped_instance_ids()
	var normalized_equipment: Dictionary = {}
	var slot_names: Array[String] = []
	for raw_slot in (equipped_items as Dictionary):
		if not raw_slot is String:
			errors.append("build: equipped_items slot keys must be strings")
			continue
		slot_names.append(String(raw_slot))
	slot_names.sort()
	var seen_instances: Dictionary = {}
	for slot in slot_names:
		var item_value: Variant = (equipped_items as Dictionary)[slot]
		var item_errors: Array[String] = registry.validate_item_instance(item_value)
		if not item_errors.is_empty():
			for item_error in item_errors:
				errors.append("build: %s" % item_error)
			continue
		var item: Dictionary = item_value
		if String(item.slot) != slot:
			errors.append("build: equipped slot '%s' does not match item slot '%s'" % [slot, String(item.slot)])
			continue
		var instance_id := String(item.instance_id)
		if seen_instances.has(instance_id):
			errors.append("build: duplicate equipped instance_id '%s'" % instance_id)
			continue
		seen_instances[instance_id] = true
		equipped_instance_ids[slot] = instance_id
		var base: Dictionary = registry.base_items[String(item.base_item_id)]
		for modifier in (base.modifiers as Array):
			_apply_modifier(parameters, sources, modifier, "base_item", String(base.id), errors)
		var affixes: Array = (item.affixes as Array).duplicate(true)
		affixes.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
			var left_key := "%s:%02d" % [String(left.family_id), int(left.tier)]
			var right_key := "%s:%02d" % [String(right.family_id), int(right.tier)]
			return left_key < right_key
		)
		var normalized_item: Dictionary = item.duplicate(true)
		normalized_item.affixes = affixes.duplicate(true)
		normalized_equipment[slot] = normalized_item
		for affix in affixes:
			var family_id := String((affix as Dictionary).family_id)
			var tier := int((affix as Dictionary).tier)
			var modifier: Dictionary = registry.modifier_for_affix(family_id, tier)
			_apply_modifier(parameters, sources, modifier, "affix", "%s:tier_%d" % [family_id, tier], errors)
		if not String(item.rune_id).is_empty():
			semantic_runes.append(String(item.rune_id))
		if not String(item.law_id).is_empty():
			semantic_laws.append(String(item.law_id))

	semantic_runes = _sorted_unique(semantic_runes)
	semantic_laws = _sorted_unique(semantic_laws)
	_validate_features(semantic_runes, semantic_laws, skill_id, errors)
	if not errors.is_empty():
		return _error_result(errors)
	_apply_talent_parameters(parameters, sources, talent_compiled)

	var raw_p := float(parameters.p)
	var overflow_p := maxf(0.0, raw_p - 1.0)
	parameters.p = clampf(raw_p, 0.0, 1.0)
	if raw_p != float(parameters.p):
		_append_source(sources, "p", "rule", "p_cap", "clamp", 1.0, raw_p, float(parameters.p))
	if overflow_p > 0.0:
		var damage_before := float(parameters.damage)
		var overflow_efficiency := RangerSkillRulesScript.P_OVERFLOW_DAMAGE_BASE_EFFICIENCY + float(talent_compiled.talent_capabilities.get("p_overflow_damage_efficiency_bonus", 0.0))
		var overflow_bonus := overflow_p * overflow_efficiency
		parameters.damage = damage_before * (1.0 + overflow_bonus)
		_append_source(sources, "damage", "rule", "p_overflow_damage", "multiply_bonus", overflow_bonus, damage_before, float(parameters.damage))
	parameters.critical_chance = clampf(float(parameters.critical_chance), 0.0, 1.0)

	var interfaces := _resolve_interfaces(skill_id, semantic_runes, semantic_laws)
	var has_split: bool = "breedable_event" in (interfaces.connected as Array)
	var has_pack_mark: bool = "branch_target_history" in (interfaces.connected as Array)
	var model: Dictionary = ArrowModel.evaluate(
		float(parameters.p), float(parameters.T), float(parameters.d),
		float(parameters.v), float(parameters.turn), has_split, has_pack_mark
	)
	var fingerprint_payload := {
		"base_parameters": normalized_base_parameters,
		"equipped_instance_ids": equipped_instance_ids,
		"equipped_items": normalized_equipment,
		"skill_id": skill_id,
		"rune_ids": semantic_runes,
		"law_ids": semantic_laws,
		"connected_interfaces": interfaces.connected,
		"missing_interfaces": interfaces.missing,
		"final_parameters": parameters,
	}
	if not (talent_compiled.get("talents", {}) as Dictionary).get("allocated_ids", []).is_empty():
		fingerprint_payload["talents"] = talent_compiled.talents
		fingerprint_payload["talent_capabilities"] = talent_compiled.talent_capabilities
	var build_fingerprint := _sha256(SaveStoreScript.canonical_json(fingerprint_payload))
	if build_fingerprint.is_empty():
		return _error_result(["build: could not calculate build fingerprint"])
	return {
		"ok": true,
		"errors": [],
		"final_parameters": parameters.duplicate(true),
		"parameter_sources": sources.duplicate(true),
		"connected_interfaces": interfaces.connected.duplicate(),
		"missing_interfaces": interfaces.missing.duplicate(),
		"skill_id": skill_id,
		"rune_ids": semantic_runes.duplicate(),
		"law_ids": semantic_laws.duplicate(),
		"build_fingerprint": build_fingerprint,
		"equipped_instance_ids": equipped_instance_ids.duplicate(true),
		"R": float(model.R),
		"growth_classification": String(model.state),
		"generation_count": int(model.g),
		"generation_time": float(model.generation_time),
		"total_events": {
			"layer": int(model.total_events.layer),
			"magnitude": float(model.total_events.magnitude),
		},
		"total_events_float": float(model.total_events_float),
		"talents": (talent_compiled.get("talents", {}) as Dictionary).duplicate(true),
		"talent_capabilities": (talent_compiled.get("talent_capabilities", {}) as Dictionary).duplicate(true),
		"talent_parameter_sources": (talent_compiled.get("talent_parameter_sources", []) as Array).duplicate(true),
	}


func _compile_talents(value: Variant, errors: Array[String]) -> Dictionary:
	if value == null:
		return _empty_talent_compilation()
	if not value is Dictionary:
		errors.append("build: talent_context must be an object")
		return {}
	var context: Dictionary = value
	var normalized_context := context.duplicate(true)
	normalized_context.erase("talents")
	normalized_context.erase("talent_points")
	normalized_context.erase("unlocked_classes")
	if not normalized_context.is_empty():
		errors.append("build: talent_context may contain only talents, talent_points, and unlocked_classes")
	var talents_value: Variant = context.get("talents", null)
	if talents_value == null:
		errors.append("build: talent_context.talents is required")
		return _empty_talent_compilation()
	if not talents_value is Dictionary:
		errors.append("build: talent_context.talents must be an object")
		return _empty_talent_compilation()
	var points_value: Variant = context.get("talent_points", null)
	if typeof(points_value) != TYPE_INT:
		errors.append("build: talent_context.talent_points must be an integer")
		return _empty_talent_compilation()
	var classes_value: Variant = context.get("unlocked_classes", null)
	if not classes_value is Array:
		errors.append("build: talent_context.unlocked_classes must be an array")
		return _empty_talent_compilation()
	var compiled: Dictionary = talent_build.compile(talents_value, int(points_value), classes_value)
	if not bool(compiled.get("ok", false)):
		for error in compiled.errors:
			errors.append("build: %s" % error)
		return _empty_talent_compilation()
	return compiled


func _empty_talent_compilation() -> Dictionary:
	return {
		"ok": false,
		"errors": [],
		"talents": {},
		"talent_capabilities": {},
		"talent_parameter_sources": [],
	}


func _apply_talent_parameters(parameters: Dictionary, sources: Dictionary, compiled: Dictionary) -> void:
	var raw_sources: Variant = compiled.get("talent_parameter_sources", [])
	if not raw_sources is Array:
		return
	for raw_source in raw_sources:
		if not raw_source is Dictionary:
			continue
		var source: Dictionary = raw_source
		var parameter := String(source.get("parameter", ""))
		if not parameters.has(parameter):
			continue
		var before := float(parameters[parameter])
		var operation := String(source.get("operation", ""))
		var value := float(source.get("value", 0.0))
		var after := before
		if operation == "multiply_bonus":
			after = before * (1.0 + value)
		elif operation == "reduce_percent":
			after = before * (1.0 - value)
		parameters[parameter] = after
		_append_source(
			sources, parameter, "talent", String(source.get("talent_id", "")),
			operation, value, before, after
		)


func _normalize_base_parameters(value: Variant, errors: Array[String]) -> Dictionary:
	if not value is Dictionary:
		errors.append("build: base_parameters must be an object")
		return {}
	var normalized: Dictionary = {}
	for raw_key in value:
		var key := String(raw_key)
		var canonical := String(PARAMETER_ALIASES.get(key, key))
		if canonical not in EarlyRegistry.PARAMETERS:
			errors.append("build: unknown base parameter '%s'" % key)
			continue
		if normalized.has(canonical):
			errors.append("build: duplicate base parameter alias for '%s'" % canonical)
			continue
		var number: Variant = value[raw_key]
		if not _is_finite_number(number):
			errors.append("build: base parameter '%s' must be a finite number" % key)
			continue
		normalized[canonical] = float(number)
	for parameter in REQUIRED_PARAMETERS:
		if not normalized.has(parameter):
			errors.append("build: missing base parameter '%s'" % parameter)
	for parameter in OPTIONAL_DEFAULTS:
		if not normalized.has(parameter):
			normalized[parameter] = float(OPTIONAL_DEFAULTS[parameter])
	if normalized.has("p") and float(normalized.p) < 0.0:
		errors.append("build: base p must be non-negative")
	for parameter in ["T", "v", "d", "damage", "max_health"]:
		if normalized.has(parameter) and float(normalized[parameter]) <= 0.0:
			errors.append("build: base parameter '%s' must be positive" % parameter)
	if normalized.has("turn") and float(normalized.turn) < 0.0:
		errors.append("build: base parameter 'turn' must be non-negative")
	if normalized.has("critical_chance") and float(normalized.critical_chance) < 0.0:
		errors.append("build: base critical_chance must be non-negative")
	return normalized


func _apply_modifier(parameters: Dictionary, sources: Dictionary, modifier: Dictionary, kind: String, source_id: String, errors: Array[String]) -> void:
	if modifier.is_empty():
		errors.append("build: source '%s' has no valid modifier" % source_id)
		return
	var parameter := String(modifier.get("parameter", ""))
	var operation := String(modifier.get("operation", ""))
	var value := float(modifier.get("value", 0.0))
	if not parameters.has(parameter):
		errors.append("build: source '%s' targets unknown parameter '%s'" % [source_id, parameter])
		return
	var before := float(parameters[parameter])
	var after := before
	match operation:
		"add":
			after = before + value
		"multiply":
			after = before * value
		"multiply_bonus":
			after = before * (1.0 + value)
		"reduce_percent":
			after = before * (1.0 - value)
		_:
			errors.append("build: source '%s' uses unknown operation '%s'" % [source_id, operation])
			return
	if not is_finite(after) or after < 0.0:
		errors.append("build: source '%s' produced invalid parameter '%s'" % [source_id, parameter])
		return
	parameters[parameter] = after
	_append_source(sources, parameter, kind, source_id, operation, value, before, after)


func _append_source(sources: Dictionary, parameter: String, kind: String, source_id: String, operation: String, value: float, before: float, after: float) -> void:
	(sources[parameter] as Array).append({
		"source_kind": kind,
		"source_id": source_id,
		"operation": operation,
		"value": value,
		"before": before,
		"after": after,
	})


func _feature_id(value: Variant, kind: String, errors: Array[String]) -> String:
	if value is String and not String(value).strip_edges().is_empty():
		return String(value)
	if value is Dictionary and value.get("id", null) is String and not String(value.id).strip_edges().is_empty():
		return String(value.id)
	errors.append("build: %s must be a non-empty id or object with id" % kind)
	return ""


func _validate_features(rune_ids: Array[String], law_ids: Array[String], skill_id: String, errors: Array[String]) -> void:
	for rune_id in rune_ids:
		if not registry.runes.has(rune_id):
			errors.append("build: unknown rune id '%s'" % rune_id)
		elif String((registry.runes[rune_id] as Dictionary).skill_id) != skill_id:
			errors.append("build: rune '%s' is not compatible with skill '%s'" % [rune_id, skill_id])
	for law_id in law_ids:
		if not registry.laws.has(law_id):
			errors.append("build: unknown law id '%s'" % law_id)


func _resolve_interfaces(skill_id: String, rune_ids: Array[String], law_ids: Array[String]) -> Dictionary:
	var connected: Array[String] = []
	var missing: Array[String] = []
	if skill_id == "piercing_arrow":
		connected.append("piercing_continuation")
	for rune_id in rune_ids:
		if registry.runes.has(rune_id):
			connected.append(String((registry.runes[rune_id] as Dictionary).provides_interface))
	if "breeding_split" not in rune_ids:
		missing.append("breedable_event")
	for law_id in law_ids:
		if not registry.laws.has(law_id):
			continue
		var law: Dictionary = registry.laws[law_id]
		var requirements_met := true
		for requirement in (law.requires_interfaces as Array):
			if String(requirement) not in connected:
				requirements_met = false
				if String(requirement) not in missing:
					missing.append(String(requirement))
		if requirements_met:
			connected.append(String(law.provides_interface))
	if "pack_hunt_mark" not in law_ids or "branch_target_history" not in connected:
		missing.append("branch_target_history")
	connected = _sorted_unique(connected)
	missing = _sorted_unique(missing)
	return {"connected": connected, "missing": missing}


func _sorted_unique(values: Array[String]) -> Array[String]:
	var seen: Dictionary = {}
	var result: Array[String] = []
	for value in values:
		if not seen.has(value):
			seen[value] = true
			result.append(value)
	result.sort()
	return result


func _empty_equipped_instance_ids() -> Dictionary:
	var result: Dictionary = {}
	for slot in EarlyRegistry.EQUIPMENT_SLOTS:
		result[slot] = ""
	return result


func _sha256(value: String) -> String:
	if value.is_empty():
		return ""
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	if context.update(value.to_utf8_buffer()) != OK:
		return ""
	return context.finish().hex_encode()


func _error_result(errors: Array[String]) -> Dictionary:
	return {
		"ok": false,
		"errors": errors.duplicate(),
		"final_parameters": {},
		"parameter_sources": {},
		"connected_interfaces": [],
		"missing_interfaces": [],
		"build_fingerprint": "",
		"equipped_instance_ids": {},
		"R": 0.0,
		"growth_classification": "invalid",
	}


func _is_finite_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))
