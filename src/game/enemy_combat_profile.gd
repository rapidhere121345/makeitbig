class_name EnemyCombatProfile
extends RefCounted

## Immutable definition resolved for one enemy kind.
##
## This is the first Flare-style boundary for enemy data: content describes a
## profile, while EncounterDirector owns the live CombatEnemyState instance.
## The profile contains no position, health or action progress from a room.

const SCHEMA_VERSION: int = 1
const PROFILE_FIELDS: Array[String] = [
	"schema_version", "profile_id", "role", "normal_health", "elite_health",
	"move_speed", "breath_ticks", "actions",
]
const ACTION_FIELDS: Array[String] = ["windup_ticks", "active_ticks", "recovery_ticks", "damage"]
const ROLES: Array[String] = ["melee_chase", "telegraphed_charge", "telegraphed_fan_ranged"]
const ACTION_IDS: Array[String] = ["contact", "charge", "fan"]

var profile_id: String = ""
var role: String = ""
var normal_health: float = 0.0
var elite_health: float = 0.0
var move_speed: float = 0.0
var breath_ticks: int = 0
var actions: Dictionary = {}


static func from_data(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return _failure("invalid_enemy_profile_type")
	var data: Dictionary = value
	var errors: Array[String] = []
	for field: String in PROFILE_FIELDS:
		if not data.has(field):
			errors.append("missing_field:%s" % field)
	for key: Variant in data.keys():
		if not key is String or String(key) not in PROFILE_FIELDS:
			errors.append("unknown_field:%s" % String(key))
	if data.get("schema_version", null) != SCHEMA_VERSION:
		errors.append("schema_version:%d" % SCHEMA_VERSION)
	if not _trimmed_string(data.get("profile_id", null)):
		errors.append("invalid_profile_id")
	if not (data.get("role", null) is String and String(data.get("role")) in ROLES):
		errors.append("invalid_role")
	for field: String in ["normal_health", "elite_health", "move_speed"]:
		if not _positive_number(data.get(field, null)):
			errors.append("invalid_positive:%s" % field)
	if not _non_negative_integer(data.get("breath_ticks", null)):
		errors.append("invalid_non_negative_integer:breath_ticks")
	var actions_value: Variant = data.get("actions", null)
	if not actions_value is Dictionary:
		errors.append("invalid_actions")
	else:
		var required_actions := _required_actions_for_role(String(data.get("role", "")))
		for action_id: Variant in (actions_value as Dictionary).keys():
			if not action_id is String or String(action_id) not in ACTION_IDS:
				errors.append("unknown_action:%s" % String(action_id))
			elif String(action_id) not in required_actions:
				errors.append("action_not_allowed_for_role:%s" % String(action_id))
		for action_id: String in required_actions:
			if not (actions_value as Dictionary).has(action_id):
				errors.append("missing_action:%s" % action_id)
		for action_id: Variant in (actions_value as Dictionary).keys():
			var action_value: Variant = (actions_value as Dictionary)[action_id]
			if not action_value is Dictionary:
				errors.append("invalid_action:%s" % String(action_id))
				continue
			var action: Dictionary = action_value
			for key: Variant in action.keys():
				if not key is String or String(key) not in ACTION_FIELDS:
					errors.append("unknown_action_field:%s.%s" % [String(action_id), String(key)])
			for field: String in ACTION_FIELDS:
				if not action.has(field):
					errors.append("missing_action_field:%s.%s" % [String(action_id), field])
			for field: String in ["windup_ticks", "active_ticks"]:
				if not _positive_integer(action.get(field, null)):
					errors.append("invalid_positive_action_ticks:%s.%s" % [String(action_id), field])
			if not _non_negative_integer(action.get("recovery_ticks", null)):
				errors.append("invalid_action_ticks:%s.recovery_ticks" % String(action_id))
			if not _finite_number(action.get("damage", null)) or float(action.get("damage", 0.0)) < 0.0:
				errors.append("invalid_action_damage:%s" % String(action_id))
	if not errors.is_empty():
		return {"ok": false, "error": ";".join(errors), "errors": errors, "value": {}}
	var result: RefCounted = load("res://src/game/enemy_combat_profile.gd").new()
	result._assign(data)
	return {"ok": true, "error": "", "errors": [], "value": result}


func action(action_id: String) -> Dictionary:
	var value: Variant = actions.get(action_id, null)
	return value.duplicate(true) if value is Dictionary else {}


func resolved_health(is_elite: bool) -> float:
	return elite_health if is_elite else normal_health


func snapshot() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"profile_id": profile_id,
		"role": role,
		"normal_health": normal_health,
		"elite_health": elite_health,
		"move_speed": move_speed,
		"breath_ticks": breath_ticks,
		"actions": actions.duplicate(true),
	}


func _assign(data: Dictionary) -> void:
	profile_id = String(data.profile_id)
	role = String(data.role)
	normal_health = float(data.normal_health)
	elite_health = float(data.elite_health)
	move_speed = float(data.move_speed)
	breath_ticks = int(data.breath_ticks)
	actions = (data.actions as Dictionary).duplicate(true)


static func _required_actions_for_role(value: String) -> Array[String]:
	match value:
		"melee_chase": return ["contact"]
		"telegraphed_charge": return ["charge"]
		"telegraphed_fan_ranged": return ["fan"]
	return []


static func _trimmed_string(value: Variant) -> bool:
	return value is String and not String(value).strip_edges().is_empty() and String(value) == String(value).strip_edges()


static func _positive_number(value: Variant) -> bool:
	return _finite_number(value) and float(value) > 0.0


static func _finite_number(value: Variant) -> bool:
	return (value is int or value is float) and not (value is bool) and is_finite(float(value))


static func _non_negative_integer(value: Variant) -> bool:
	return (value is int or value is float) and not (value is bool) and is_finite(float(value)) and float(value) == float(int(value)) and int(value) >= 0


static func _positive_integer(value: Variant) -> bool:
	return _non_negative_integer(value) and int(value) > 0


static func _failure(error: String) -> Dictionary:
	return {"ok": false, "error": error, "errors": [error], "value": {}}
