class_name EarlyItemRegistry
extends RefCounted

## Read-only loader and strict validator for the early-game equipment domain.
## The JSON remains inert data: no script, callable, or method fields are accepted.

const CONTENT_PATH := "res://content/early_items.json"
const EXPECTED_SCHEMA_VERSION := 1
const EQUIPMENT_SLOTS: Array[String] = [
	"head", "chest", "pants", "leg_armor", "gloves", "bracers",
	"belt", "main_hand", "off_hand", "ring_1", "ring_2", "necklace",
]
const PROTOTYPE_OPEN_SLOTS: Array[String] = ["main_hand", "off_hand", "gloves", "ring_1"]
const PARAMETERS: Array[String] = ["p", "T", "v", "d", "turn", "damage", "critical_chance", "max_health"]
const OPERATIONS: Array[String] = ["add", "multiply", "multiply_bonus", "reduce_percent"]
const FORBIDDEN_DATA_KEYS: Array[String] = ["script", "script_path", "code", "source_code", "callable", "method"]
const ITEM_FIELDS: Array[String] = [
	"instance_id", "base_item_id", "slot", "affixes", "rune_id", "law_id", "source", "law_seed",
]

var equipment_slots: Array[String] = []
var prototype_open_slots: Array[String] = []
var base_items: Dictionary = {}
var affix_families: Dictionary = {}
var runes: Dictionary = {}
var laws: Dictionary = {}
var item_instances: Dictionary = {}
var build_fixtures: Dictionary = {}
var fixed_starting_loadout_id := ""
var calibration_fixture_ids: Array[String] = []


func load_all(path: String = CONTENT_PATH) -> Array[String]:
	var read_result: Dictionary = _read_json(path)
	if not bool(read_result.get("ok", false)):
		return [String(read_result.get("error", "registry: unknown read error"))]
	var data: Dictionary = read_result.data
	var failures := validate_content(data)
	if failures.is_empty():
		_clear()
		_ingest(data)
	return failures


func validate_content(data: Dictionary) -> Array[String]:
	var failures: Array[String] = []
	_check_exact_keys(data, [
		"schema_version", "equipment_slots", "prototype_open_slots", "base_items",
		"affix_families", "runes", "laws", "item_instances", "build_fixtures",
		"fixed_starting_loadout_id", "calibration_fixture_ids",
	], "content", failures)
	_check_forbidden_keys(data, "content", failures)
	if data.get("schema_version", null) != EXPECTED_SCHEMA_VERSION:
		failures.append("content: schema_version must be %d" % EXPECTED_SCHEMA_VERSION)
	_validate_string_array(data.get("equipment_slots", null), "content.equipment_slots", failures, false)
	_validate_string_array(data.get("prototype_open_slots", null), "content.prototype_open_slots", failures, false)
	var slots := _string_array(data.get("equipment_slots", []))
	var open_slots := _string_array(data.get("prototype_open_slots", []))
	if slots != EQUIPMENT_SLOTS:
		failures.append("content: equipment_slots must reserve the formal 12-slot schema")
	if open_slots != PROTOTYPE_OPEN_SLOTS:
		failures.append("content: prototype_open_slots must be main_hand/off_hand/gloves/ring_1")

	var bases_value: Variant = data.get("base_items", null)
	var affixes_value: Variant = data.get("affix_families", null)
	var runes_value: Variant = data.get("runes", null)
	var laws_value: Variant = data.get("laws", null)
	var instances_value: Variant = data.get("item_instances", null)
	var fixtures_value: Variant = data.get("build_fixtures", null)
	if not bases_value is Array:
		failures.append("content: base_items must be an array")
	if not affixes_value is Array:
		failures.append("content: affix_families must be an array")
	if not runes_value is Array:
		failures.append("content: runes must be an array")
	if not laws_value is Array:
		failures.append("content: laws must be an array")
	if not instances_value is Array:
		failures.append("content: item_instances must be an array")
	if not fixtures_value is Array:
		failures.append("content: build_fixtures must be an array")
	if not (bases_value is Array and affixes_value is Array and runes_value is Array and laws_value is Array and instances_value is Array and fixtures_value is Array):
		return failures

	var seen_ids: Dictionary = {}
	_validate_base_items(bases_value, open_slots, seen_ids, failures)
	_validate_affixes(affixes_value, open_slots, seen_ids, failures)
	_validate_runes(runes_value, seen_ids, failures)
	_validate_laws(laws_value, seen_ids, failures)
	var staged_bases := _index_definitions(bases_value)
	var staged_affixes := _index_definitions(affixes_value)
	var staged_runes := _index_definitions(runes_value)
	var staged_laws := _index_definitions(laws_value)
	var staged_instances: Dictionary = {}
	for raw_instance in instances_value:
		if not raw_instance is Dictionary:
			failures.append("content: item instance must be an object")
			continue
		var instance: Dictionary = raw_instance
		var instance_id := _definition_id(instance, "item instance", seen_ids, failures, "instance_id")
		_validate_item_instance_against(instance, staged_bases, staged_affixes, staged_runes, staged_laws, failures)
		if instance_id != "":
			staged_instances[instance_id] = instance
	_validate_build_fixtures(fixtures_value, staged_instances, seen_ids, failures)
	_validate_fixture_contract(data, fixtures_value, failures)
	return failures


func validate_item_instance(item: Variant) -> Array[String]:
	var failures: Array[String] = []
	if not item is Dictionary:
		return ["item: ItemInstance must be an object"]
	_validate_item_instance_against(item, base_items, affix_families, runes, laws, failures)
	return failures


func _validate_item_instance_against(item: Dictionary, bases: Dictionary, affixes: Dictionary, rune_table: Dictionary, law_table: Dictionary, failures: Array[String]) -> void:
	var value: Dictionary = item
	_check_exact_keys(value, ITEM_FIELDS, "item", failures)
	_check_forbidden_keys(value, "item", failures)
	var instance_id := _required_id(value, "instance_id", "item", failures)
	var base_id := _required_id(value, "base_item_id", "item %s" % instance_id, failures)
	var slot := _required_id(value, "slot", "item %s" % instance_id, failures)
	if slot not in PROTOTYPE_OPEN_SLOTS:
		failures.append("item %s: slot '%s' is not prototype-open" % [instance_id, slot])
	if not bases.has(base_id):
		failures.append("item %s: unknown base_item_id '%s'" % [instance_id, base_id])
	elif String((bases[base_id] as Dictionary).slot) != slot:
		failures.append("item %s: base item '%s' belongs to slot '%s', not '%s'" % [
			instance_id, base_id, String((bases[base_id] as Dictionary).slot), slot,
		])

	var affix_values: Variant = value.get("affixes", null)
	if not affix_values is Array:
		failures.append("item %s: affixes must be an array" % instance_id)
	else:
		if affix_values.size() > 4:
			failures.append("item %s: at most 4 affixes are allowed" % instance_id)
		var seen_families: Dictionary = {}
		for affix_value in affix_values:
			if not affix_value is Dictionary:
				failures.append("item %s: affix must be an object" % instance_id)
				continue
			var affix: Dictionary = affix_value
			_check_exact_keys(affix, ["family_id", "tier"], "item %s affix" % instance_id, failures)
			var family_id := _required_id(affix, "family_id", "item %s affix" % instance_id, failures)
			if seen_families.has(family_id):
				failures.append("item %s: duplicate affix family '%s'" % [instance_id, family_id])
			seen_families[family_id] = true
			if not affixes.has(family_id):
				failures.append("item %s: unknown affix family '%s'" % [instance_id, family_id])
				continue
			var tier_value: Variant = affix.get("tier", null)
			if not _is_exact_integer(tier_value):
				failures.append("item %s: affix '%s' tier must be an integer" % [instance_id, family_id])
			elif not _tier_exists(affixes[family_id], int(tier_value)):
				failures.append("item %s: affix '%s' has unsupported tier %s" % [instance_id, family_id, str(tier_value)])
			var compatible: Array = (affixes[family_id] as Dictionary).compatible_slots
			if slot != "" and slot not in compatible:
				failures.append("item %s: affix '%s' is not compatible with slot '%s'" % [instance_id, family_id, slot])

	_validate_optional_reference(value, "rune_id", rune_table, "rune", instance_id, failures)
	_validate_optional_reference(value, "law_id", law_table, "law", instance_id, failures)
	var source_value: Variant = value.get("source", null)
	if not source_value is Dictionary:
		failures.append("item %s: source must be an object" % instance_id)
	else:
		_check_exact_keys(source_value, ["type", "id"], "item %s source" % instance_id, failures)
		_required_id(source_value, "type", "item %s source" % instance_id, failures)
		_required_id(source_value, "id", "item %s source" % instance_id, failures)
	if not _is_exact_integer(value.get("law_seed", null)):
		failures.append("item %s: law_seed must be an integer" % instance_id)


func equipment_for_fixture(fixture_id: String) -> Dictionary:
	if not build_fixtures.has(fixture_id):
		return {}
	var equipment: Dictionary = {}
	for slot in PROTOTYPE_OPEN_SLOTS:
		var instance_id := String((build_fixtures[fixture_id] as Dictionary).equipment.get(slot, ""))
		if not item_instances.has(instance_id):
			return {}
		equipment[slot] = (item_instances[instance_id] as Dictionary).duplicate(true)
	return equipment


func modifier_for_affix(family_id: String, tier: int) -> Dictionary:
	if not affix_families.has(family_id):
		return {}
	var family: Dictionary = affix_families[family_id]
	for tier_value in (family.tiers as Array):
		if int((tier_value as Dictionary).tier) == tier:
			return {
				"parameter": String(family.parameter),
				"operation": String(family.operation),
				"value": float((tier_value as Dictionary).value),
			}.duplicate(true)
	return {}


func _validate_base_items(values: Array, open_slots: Array[String], seen: Dictionary, failures: Array[String]) -> void:
	if values.size() != 8:
		failures.append("content: expected exactly 8 early base items")
	var per_slot: Dictionary = {}
	for slot in open_slots:
		per_slot[slot] = 0
	for raw in values:
		if not raw is Dictionary:
			failures.append("content: base item must be an object")
			continue
		var entry: Dictionary = raw
		_check_exact_keys(entry, ["id", "name", "slot", "modifiers"], "base item", failures)
		var id := _definition_id(entry, "base item", seen, failures)
		_required_text(entry, "name", "base item %s" % id, failures)
		var slot := _required_id(entry, "slot", "base item %s" % id, failures)
		if slot not in open_slots:
			failures.append("base item %s: slot '%s' is not prototype-open" % [id, slot])
		else:
			per_slot[slot] = int(per_slot.get(slot, 0)) + 1
		_validate_modifiers(entry.get("modifiers", null), "base item %s" % id, failures)
	for slot in open_slots:
		if int(per_slot.get(slot, 0)) != 2:
			failures.append("content: open slot %s must have exactly 2 base items" % slot)


func _validate_affixes(values: Array, open_slots: Array[String], seen: Dictionary, failures: Array[String]) -> void:
	if values.size() != 8:
		failures.append("content: expected exactly 8 T1 affix families")
	var seen_parameters: Dictionary = {}
	for raw in values:
		if not raw is Dictionary:
			failures.append("content: affix family must be an object")
			continue
		var entry: Dictionary = raw
		_check_exact_keys(entry, ["id", "name", "parameter", "operation", "compatible_slots", "tiers"], "affix family", failures)
		var id := _definition_id(entry, "affix family", seen, failures)
		_required_text(entry, "name", "affix %s" % id, failures)
		var parameter := _required_parameter(entry, "parameter", "affix %s" % id, failures)
		var operation := _required_id(entry, "operation", "affix %s" % id, failures)
		if parameter not in PARAMETERS:
			failures.append("affix %s: unknown parameter '%s'" % [id, parameter])
		elif seen_parameters.has(parameter):
			failures.append("affix %s: parameter '%s' already has a T1 family" % [id, parameter])
		else:
			seen_parameters[parameter] = true
		if operation not in OPERATIONS:
			failures.append("affix %s: unknown operation '%s'" % [id, operation])
		_validate_string_array(entry.get("compatible_slots", null), "affix %s compatible_slots" % id, failures, true)
		for slot in _string_array(entry.get("compatible_slots", [])):
			if slot not in open_slots:
				failures.append("affix %s: slot '%s' is not prototype-open" % [id, slot])
		var tiers_value: Variant = entry.get("tiers", null)
		if not tiers_value is Array or tiers_value.size() != 4:
			failures.append("affix %s: tiers must contain exactly I-IV" % id)
			continue
		var expected_tier := 1
		for raw_tier in tiers_value:
			if not raw_tier is Dictionary:
				failures.append("affix %s: tier must be an object" % id)
				continue
			var tier: Dictionary = raw_tier
			_check_exact_keys(tier, ["tier", "value"], "affix %s tier" % id, failures)
			if not _is_exact_integer(tier.get("tier", null)) or int(tier.tier) != expected_tier:
				failures.append("affix %s: tier order must be exactly 1,2,3,4" % id)
			if not _is_finite_number(tier.get("value", null)) or float(tier.value) <= 0.0:
				failures.append("affix %s tier %d: value must be a positive finite number" % [id, expected_tier])
			expected_tier += 1
	for parameter in PARAMETERS:
		if not seen_parameters.has(parameter):
			failures.append("content: missing T1 affix family for parameter '%s'" % parameter)


func _validate_runes(values: Array, seen: Dictionary, failures: Array[String]) -> void:
	if values.size() != 3:
		failures.append("content: expected exactly 3 ranger prototype runes")
	var has_breeding := false
	for raw in values:
		if not raw is Dictionary:
			failures.append("content: rune must be an object")
			continue
		var entry: Dictionary = raw
		_check_exact_keys(entry, ["id", "name", "skill_id", "provides_interface", "semantics"], "rune", failures)
		var id := _definition_id(entry, "rune", seen, failures)
		for field in ["name", "skill_id", "provides_interface", "semantics"]:
			_required_text(entry, field, "rune %s" % id, failures)
		has_breeding = has_breeding or id == "breeding_split"
	if not has_breeding:
		failures.append("content: runes must include 'breeding_split'")


func _validate_laws(values: Array, seen: Dictionary, failures: Array[String]) -> void:
	if values.size() != 1:
		failures.append("content: expected exactly 1 early route law")
	var has_pack_hunt := false
	for raw in values:
		if not raw is Dictionary:
			failures.append("content: law must be an object")
			continue
		var entry: Dictionary = raw
		_check_exact_keys(entry, ["id", "name", "requires_interfaces", "provides_interface", "semantics"], "law", failures)
		var id := _definition_id(entry, "law", seen, failures)
		for field in ["name", "provides_interface", "semantics"]:
			_required_text(entry, field, "law %s" % id, failures)
		_validate_string_array(entry.get("requires_interfaces", null), "law %s requires_interfaces" % id, failures, true)
		has_pack_hunt = has_pack_hunt or id == "pack_hunt_mark"
	if not has_pack_hunt:
		failures.append("content: laws must include 'pack_hunt_mark'")


func _validate_modifiers(value: Variant, context: String, failures: Array[String]) -> void:
	if not value is Array or value.is_empty():
		failures.append("%s: modifiers must be a non-empty array" % context)
		return
	for raw in value:
		if not raw is Dictionary:
			failures.append("%s: modifier must be an object" % context)
			continue
		var modifier: Dictionary = raw
		_check_exact_keys(modifier, ["parameter", "operation", "value"], "%s modifier" % context, failures)
		var parameter := _required_parameter(modifier, "parameter", "%s modifier" % context, failures)
		var operation := _required_id(modifier, "operation", "%s modifier" % context, failures)
		if parameter not in PARAMETERS:
			failures.append("%s: unknown modifier parameter '%s'" % [context, parameter])
		if operation not in OPERATIONS:
			failures.append("%s: unknown modifier operation '%s'" % [context, operation])
		if not _is_finite_number(modifier.get("value", null)):
			failures.append("%s: modifier value must be a finite number" % context)


func _validate_build_fixtures(values: Array, instances: Dictionary, seen: Dictionary, failures: Array[String]) -> void:
	if values.size() != 4:
		failures.append("content: expected fixed_start plus exactly 3 calibration fixtures")
	for raw in values:
		if not raw is Dictionary:
			failures.append("content: build fixture must be an object")
			continue
		var fixture: Dictionary = raw
		_check_exact_keys(fixture, ["id", "skill_id", "base_parameters", "equipment", "expected_growth"], "build fixture", failures)
		var fixture_id := _definition_id(fixture, "build fixture", seen, failures)
		if String(fixture.get("skill_id", "")) != "piercing_arrow":
			failures.append("build fixture %s: skill_id must be piercing_arrow" % fixture_id)
		_validate_base_parameter_data(fixture.get("base_parameters", null), fixture_id, failures)
		var equipment_value: Variant = fixture.get("equipment", null)
		if not equipment_value is Dictionary:
			failures.append("build fixture %s: equipment must be an object" % fixture_id)
		else:
			_check_exact_keys(equipment_value, PROTOTYPE_OPEN_SLOTS, "build fixture %s equipment" % fixture_id, failures)
			for slot in PROTOTYPE_OPEN_SLOTS:
				var instance_id_value: Variant = equipment_value.get(slot, null)
				if not instance_id_value is String or String(instance_id_value).is_empty():
					failures.append("build fixture %s: slot %s must reference an item instance" % [fixture_id, slot])
					continue
				var instance_id := String(instance_id_value)
				if not instances.has(instance_id):
					failures.append("build fixture %s: unknown item instance '%s'" % [fixture_id, instance_id])
				elif String((instances[instance_id] as Dictionary).slot) != slot:
					failures.append("build fixture %s: item '%s' does not belong in slot '%s'" % [fixture_id, instance_id, slot])
		if String(fixture.get("expected_growth", "")) not in ["convergent", "critical", "exponential"]:
			failures.append("build fixture %s: invalid expected_growth" % fixture_id)


func _validate_fixture_contract(data: Dictionary, fixtures: Array, failures: Array[String]) -> void:
	var fixture_ids: Array[String] = []
	for raw in fixtures:
		if raw is Dictionary and raw.get("id", null) is String:
			fixture_ids.append(String(raw.id))
	var fixed_value: Variant = data.get("fixed_starting_loadout_id", null)
	if not fixed_value is String or String(fixed_value) != "fixed_start" or String(fixed_value) not in fixture_ids:
		failures.append("content: fixed_starting_loadout_id must reference 'fixed_start'")
	_validate_string_array(data.get("calibration_fixture_ids", null), "content.calibration_fixture_ids", failures, true)
	var calibration_ids := _string_array(data.get("calibration_fixture_ids", []))
	if calibration_ids != ["calibration_convergent", "calibration_critical", "calibration_exponential"]:
		failures.append("content: calibration_fixture_ids must be convergent/critical/exponential in order")
	for fixture_id in calibration_ids:
		if fixture_id not in fixture_ids:
			failures.append("content: calibration fixture '%s' is not defined" % fixture_id)


func _validate_base_parameter_data(value: Variant, fixture_id: String, failures: Array[String]) -> void:
	if not value is Dictionary:
		failures.append("build fixture %s: base_parameters must be an object" % fixture_id)
		return
	_check_exact_keys(value, PARAMETERS, "build fixture %s base_parameters" % fixture_id, failures)
	for parameter in PARAMETERS:
		if not _is_finite_number(value.get(parameter, null)):
			failures.append("build fixture %s: base parameter '%s' must be finite" % [fixture_id, parameter])


func _index_definitions(values: Array) -> Dictionary:
	var result: Dictionary = {}
	for raw in values:
		if raw is Dictionary and raw.get("id", null) is String:
			result[String(raw.id)] = raw
	return result


func _ingest(data: Dictionary) -> void:
	fixed_starting_loadout_id = String(data.fixed_starting_loadout_id)
	calibration_fixture_ids.assign(data.calibration_fixture_ids)
	equipment_slots.assign(data.equipment_slots)
	prototype_open_slots.assign(data.prototype_open_slots)
	for entry in (data.base_items as Array):
		base_items[String(entry.id)] = (entry as Dictionary).duplicate(true)
	for entry in (data.affix_families as Array):
		affix_families[String(entry.id)] = (entry as Dictionary).duplicate(true)
	for entry in (data.runes as Array):
		runes[String(entry.id)] = (entry as Dictionary).duplicate(true)
	for entry in (data.laws as Array):
		laws[String(entry.id)] = (entry as Dictionary).duplicate(true)
	for entry in (data.item_instances as Array):
		item_instances[String(entry.instance_id)] = (entry as Dictionary).duplicate(true)
	for entry in (data.build_fixtures as Array):
		build_fixtures[String(entry.id)] = (entry as Dictionary).duplicate(true)


func _clear() -> void:
	equipment_slots.clear()
	prototype_open_slots.clear()
	base_items.clear()
	affix_families.clear()
	runes.clear()
	laws.clear()
	item_instances.clear()
	build_fixtures.clear()
	fixed_starting_loadout_id = ""
	calibration_fixture_ids.clear()


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "registry: content file not found: %s" % path}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "registry: cannot open content file: %s" % path}
	var json := JSON.new()
	var parse_error := json.parse(file.get_as_text())
	if parse_error != OK:
		return {"ok": false, "error": "registry: invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()]}
	if not json.data is Dictionary:
		return {"ok": false, "error": "registry: JSON root must be an object"}
	return {"ok": true, "data": json.data}


func _definition_id(entry: Dictionary, kind: String, seen: Dictionary, failures: Array[String], field: String = "id") -> String:
	var id := _required_id(entry, field, kind, failures)
	if id != "" and seen.has(id):
		failures.append("content: duplicate id '%s' across definitions" % id)
	elif id != "":
		seen[id] = true
	return id


func _required_id(entry: Dictionary, field: String, context: String, failures: Array[String]) -> String:
	var value: Variant = entry.get(field, null)
	if not value is String or String(value).strip_edges().is_empty():
		failures.append("%s: %s must be a non-empty string id" % [context, field])
		return ""
	var id := String(value)
	for index in id.length():
		var code := id.unicode_at(index)
		if not (code >= 97 and code <= 122) and not (code >= 48 and code <= 57) and code != 95 and code != 45:
			failures.append("%s: %s '%s' must use stable lowercase ASCII id characters" % [context, field, id])
			break
	return id


func _required_text(entry: Dictionary, field: String, context: String, failures: Array[String]) -> void:
	var value: Variant = entry.get(field, null)
	if not value is String or String(value).strip_edges().is_empty():
		failures.append("%s: %s must be non-empty text" % [context, field])


func _required_parameter(entry: Dictionary, field: String, context: String, failures: Array[String]) -> String:
	var value: Variant = entry.get(field, null)
	if not value is String or String(value).strip_edges().is_empty():
		failures.append("%s: %s must be a non-empty parameter name" % [context, field])
		return ""
	return String(value)


func _validate_optional_reference(entry: Dictionary, field: String, table: Dictionary, kind: String, item_id: String, failures: Array[String]) -> void:
	var value: Variant = entry.get(field, null)
	if not value is String:
		failures.append("item %s: %s must be a string" % [item_id, field])
		return
	var id := String(value)
	if not id.is_empty() and not table.has(id):
		failures.append("item %s: unknown %s id '%s'" % [item_id, kind, id])


func _validate_string_array(value: Variant, context: String, failures: Array[String], require_non_empty: bool) -> void:
	if not value is Array:
		failures.append("%s must be an array" % context)
		return
	if require_non_empty and value.is_empty():
		failures.append("%s must not be empty" % context)
	var seen: Dictionary = {}
	for raw in value:
		if not raw is String or String(raw).strip_edges().is_empty():
			failures.append("%s entries must be non-empty strings" % context)
			continue
		var text := String(raw)
		if seen.has(text):
			failures.append("%s contains duplicate '%s'" % [context, text])
		seen[text] = true


func _string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for raw in value:
			if raw is String:
				result.append(String(raw))
	return result


func _check_exact_keys(value: Dictionary, expected: Array, context: String, failures: Array[String]) -> void:
	for key in expected:
		if not value.has(key):
			failures.append("%s: missing field '%s'" % [context, key])
	for key in value:
		if key not in expected:
			failures.append("%s: unknown field '%s'" % [context, String(key)])


func _check_forbidden_keys(value: Variant, path: String, failures: Array[String]) -> void:
	if value is Dictionary:
		for key in value:
			var key_text := String(key).to_lower()
			if key_text in FORBIDDEN_DATA_KEYS:
				failures.append("%s: executable field '%s' is forbidden in content data" % [path, String(key)])
			_check_forbidden_keys(value[key], "%s.%s" % [path, String(key)], failures)
	elif value is Array:
		for index in value.size():
			_check_forbidden_keys(value[index], "%s[%d]" % [path, index], failures)


func _tier_exists(family: Dictionary, tier: int) -> bool:
	for value in (family.get("tiers", []) as Array):
		if value is Dictionary and int(value.get("tier", -1)) == tier:
			return true
	return false


func _is_exact_integer(value: Variant) -> bool:
	if value is int:
		return true
	return value is float and is_finite(float(value)) and float(value) == floor(float(value))


func _is_finite_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))
