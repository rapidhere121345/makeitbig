class_name EarlySkillRegistry
extends RefCounted

## Read-only source of player-facing ranger skill facts. The JSON is deliberately
## strict so UI copy cannot silently drift away from the fixed-tick combat rules.

const CONTENT_PATH := "res://content/early_skills.json"
const EXPECTED_SCHEMA_VERSION := 1
const RangerSkillRulesScript = preload("res://src/systems/ranger_skill_rules.gd")
const JsonIO := preload("res://src/core/json_io.gd")
const EXPECTED_TICKS_PER_SECOND := RangerSkillRulesScript.TICKS_PER_SECOND
const SKILL_IDS: Array[String] = ["piercing_arrow", "hunter_mark", "dash", "basic_dodge"]
const SKILL_FIELDS: Array[String] = [
	"id", "name", "key_bindings", "type", "target_rule", "range_rule", "full_effect",
	"cooldown_ticks", "duration_ticks", "displacement_units", "speed_units_per_second",
	"equipment_parameters", "synergies", "limitations", "invulnerable",
]
const PARAMETERS: Array[String] = ["p", "T", "v", "d", "turn", "damage", "critical_chance", "max_health"]
const FORBIDDEN_DATA_KEYS: Array[String] = ["script", "script_path", "code", "source_code", "callable", "method"]

const REQUIRED_FACTS := RangerSkillRulesScript.CONTENT_FACTS

var ticks_per_second: int = 0
var skills: Dictionary = {}


func load_all(path: String = CONTENT_PATH) -> Array[String]:
	var read_result := JsonIO.read_result(path, "skill registry")
	if not bool(read_result.get("ok", false)):
		return [String(read_result.get("error", "skill registry: unknown read error"))]
	var value: Variant = read_result.get("data", null)
	if not value is Dictionary:
		return ["content: root must be an object"]
	var data: Dictionary = value
	var failures := validate_content(data)
	if failures.is_empty():
		var staged: Dictionary = {}
		for raw_skill in (data.skills as Array):
			var skill: Dictionary = raw_skill
			staged[String(skill.id)] = skill.duplicate(true)
		ticks_per_second = int(data.ticks_per_second)
		skills = staged
	return failures


func validate_content(data: Dictionary) -> Array[String]:
	var failures: Array[String] = []
	_check_exact_keys(data, ["schema_version", "ticks_per_second", "skills"], "content", failures)
	_check_forbidden_keys(data, "content", failures)
	if data.get("schema_version", null) != EXPECTED_SCHEMA_VERSION:
		failures.append("content: schema_version must be %d" % EXPECTED_SCHEMA_VERSION)
	if not _is_exact_integer(data.get("ticks_per_second", null)) or int(data.get("ticks_per_second", 0)) != EXPECTED_TICKS_PER_SECOND:
		failures.append("content: ticks_per_second must be 30")
	var skills_value: Variant = data.get("skills", null)
	if not skills_value is Array:
		failures.append("content: skills must be an array")
		return failures
	if skills_value.size() != SKILL_IDS.size():
		failures.append("content: expected exactly four early ranger skills")
	var seen: Dictionary = {}
	for raw_skill in skills_value:
		_validate_skill(raw_skill, seen, failures)
	for skill_id in SKILL_IDS:
		if not seen.has(skill_id):
			failures.append("content: missing required skill '%s'" % skill_id)
	return failures


func get_skill(skill_id: String) -> Dictionary:
	return (skills[skill_id] as Dictionary).duplicate(true) if skills.has(skill_id) else {}


func all_skills() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for skill_id in SKILL_IDS:
		if skills.has(skill_id):
			result.append((skills[skill_id] as Dictionary).duplicate(true))
	return result


func _validate_skill(value: Variant, seen: Dictionary, failures: Array[String]) -> void:
	if not value is Dictionary:
		failures.append("content: skill must be an object")
		return
	var skill: Dictionary = value
	_check_exact_keys(skill, SKILL_FIELDS, "skill", failures)
	var skill_id := _required_id(skill, "id", "skill", failures)
	if not skill_id.is_empty():
		if seen.has(skill_id):
			failures.append("content: duplicate skill id '%s'" % skill_id)
		else:
			seen[skill_id] = true
	for field in ["name", "type", "target_rule", "range_rule", "full_effect"]:
		_required_text(skill, field, "skill %s" % skill_id, failures)
	_validate_string_array(skill.get("key_bindings", null), "skill %s key_bindings" % skill_id, failures, true)
	_validate_string_array(skill.get("equipment_parameters", null), "skill %s equipment_parameters" % skill_id, failures, false)
	_validate_string_array(skill.get("synergies", null), "skill %s synergies" % skill_id, failures, true)
	_validate_string_array(skill.get("limitations", null), "skill %s limitations" % skill_id, failures, true)
	for parameter in _string_array(skill.get("equipment_parameters", [])):
		if parameter not in PARAMETERS:
			failures.append("skill %s: unknown equipment parameter '%s'" % [skill_id, parameter])
	for field in ["cooldown_ticks", "duration_ticks"]:
		if not _is_exact_integer(skill.get(field, null)) or int(skill.get(field, -1)) < 0:
			failures.append("skill %s: %s must be a non-negative integer" % [skill_id, field])
	for field in ["displacement_units", "speed_units_per_second"]:
		if not _is_finite_number(skill.get(field, null)) or float(skill.get(field, -1.0)) < 0.0:
			failures.append("skill %s: %s must be a non-negative finite number" % [skill_id, field])
	if not skill.get("invulnerable", null) is bool:
		failures.append("skill %s: invulnerable must be boolean" % skill_id)
	if REQUIRED_FACTS.has(skill_id):
		for field in (REQUIRED_FACTS[skill_id] as Dictionary):
			if skill.get(field, null) != (REQUIRED_FACTS[skill_id] as Dictionary)[field]:
				failures.append("skill %s: authoritative fact '%s' changed" % [skill_id, field])


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


func _is_exact_integer(value: Variant) -> bool:
	if value is bool:
		return false
	if value is int:
		return true
	return value is float and is_finite(float(value)) and float(value) == floorf(float(value))


func _is_finite_number(value: Variant) -> bool:
	return (value is int or value is float) and not (value is bool) and is_finite(float(value))
