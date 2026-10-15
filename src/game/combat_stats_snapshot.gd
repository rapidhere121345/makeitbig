class_name CombatStatsSnapshot
extends RefCounted

## Immutable-by-convention combat sheet resolved before a room starts.
## PlayerCombatRules may consume this value, but it never reads inventory or UI
## profile data during a fixed tick.

const SCHEMA_VERSION: int = 1
const RangerSkillRulesScript := preload("res://src/systems/ranger_skill_rules.gd")
const NUMERIC_FIELDS: Array[String] = [
	"maximum_health", "damage", "projectile_speed", "targeting_distance",
	"move_speed", "acceleration", "dodge_distance",
]
const INTEGER_FIELDS: Array[String] = [
	"attack_cooldown_ticks", "dodge_duration_ticks", "dodge_cooldown_ticks",
]
const REQUIRED_FIELDS: Array[String] = NUMERIC_FIELDS + INTEGER_FIELDS + ["resistances", "provenance"]
const ALL_FIELDS: Array[String] = ["schema_version"] + REQUIRED_FIELDS
const ROOM_OVERLAY_FIELDS: Array[String] = [
	"move_speed", "acceleration", "dodge_distance",
	"attack_cooldown_ticks", "dodge_duration_ticks", "dodge_cooldown_ticks", "resistances",
]

var maximum_health: float = 0.0
var damage: float = 0.0
var projectile_speed: float = 0.0
var targeting_distance: float = 0.0
var move_speed: float = 0.0
var acceleration: float = 0.0
var dodge_distance: float = 0.0
var attack_cooldown_ticks: int = 0
var dodge_duration_ticks: int = 0
var dodge_cooldown_ticks: int = 0
var resistances: Dictionary = {}
var provenance: Dictionary = {}


static func from_data(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return _failure("invalid_stats_type")
	var data: Dictionary = value
	var errors: Array[String] = []
	for field: String in REQUIRED_FIELDS:
		if not data.has(field):
			errors.append("missing_field:%s" % field)
	for key: Variant in data.keys():
		if not key is String or String(key) not in ALL_FIELDS:
			errors.append("unknown_field:%s" % String(key))
	if not data.has("schema_version") or data.get("schema_version") != SCHEMA_VERSION:
		errors.append("schema_version:%d" % SCHEMA_VERSION)
	for field: String in NUMERIC_FIELDS:
		if not _finite_positive(data.get(field, null)):
			errors.append("invalid_positive:%s" % field)
	for field: String in INTEGER_FIELDS:
		if not _non_negative_integer(data.get(field, null)):
			errors.append("invalid_non_negative_integer:%s" % field)
	var resistances_value: Variant = data.get("resistances", null)
	if not resistances_value is Dictionary:
		errors.append("invalid_resistances")
	else:
		for key: Variant in (resistances_value as Dictionary).keys():
			var resistance: Variant = (resistances_value as Dictionary)[key]
			if not key is String or not _finite_number(resistance) or float(resistance) < 0.0 or float(resistance) > 1.0:
				errors.append("invalid_resistance:%s" % String(key))
	var provenance_value: Variant = data.get("provenance", null)
	if not provenance_value is Dictionary:
		errors.append("invalid_provenance")
	else:
		for field: String in NUMERIC_FIELDS + INTEGER_FIELDS:
			var sources: Variant = (provenance_value as Dictionary).get(field, null)
			if not sources is Array or (sources as Array).is_empty():
				errors.append("missing_provenance:%s" % field)
				continue
			for source: Variant in sources:
				if not source is String or String(source).strip_edges().is_empty():
					errors.append("invalid_provenance:%s" % field)
	if not errors.is_empty():
		return {"ok": false, "error": ";".join(errors), "errors": errors, "value": {}}
	var result: RefCounted = load("res://src/game/combat_stats_snapshot.gd").new()
	result._assign(data)
	return {"ok": true, "error": "", "errors": [], "value": result}


static func from_resolved_build(build: Variant, provenance_prefix: String = "build") -> Dictionary:
	if not build is Dictionary:
		return _failure("invalid_resolved_build")
	var parameters_value: Variant = (build as Dictionary).get("final_parameters", null)
	if not parameters_value is Dictionary:
		return _failure("missing_final_parameters")
	var parameters: Dictionary = parameters_value
	var combat_value: Variant = (build as Dictionary).get("combat_stats", null)
	if not combat_value is Dictionary:
		return _failure("missing_combat_stats")
	var combat_stats: Dictionary = combat_value
	var stats_data := {
		"schema_version": SCHEMA_VERSION,
		"maximum_health": float(parameters.get("max_health", 100.0)),
		"damage": float(parameters.get("damage", 0.0)),
		"projectile_speed": float(parameters.get("v", 0.0)),
		"targeting_distance": float(parameters.get("d", 0.0)),
		"move_speed": combat_stats.get("move_speed", null),
		"acceleration": combat_stats.get("acceleration", null),
		"dodge_distance": combat_stats.get("dodge_distance", null),
		"attack_cooldown_ticks": combat_stats.get("attack_cooldown_ticks", null),
		"dodge_duration_ticks": combat_stats.get("dodge_duration_ticks", null),
		"dodge_cooldown_ticks": combat_stats.get("dodge_cooldown_ticks", null),
		"resistances": (combat_stats.get("resistances", {}) as Dictionary).duplicate(true) if combat_stats.get("resistances", {}) is Dictionary else combat_stats.get("resistances", null),
		"provenance": {},
	}
	for field: String in NUMERIC_FIELDS + INTEGER_FIELDS:
		(stats_data.provenance as Dictionary)[field] = ["%s:%s" % [provenance_prefix, field]]
	return from_data(stats_data)


static func from_room_overlay(build: Variant, overlay: Variant, room_id: String) -> Dictionary:
	## Room authored tuning may adjust movement/action values while base damage,
	## health, weapon speed and range remain owned by the resolved build.
	if not build is Dictionary or not overlay is Dictionary:
		return _failure("invalid_room_combat_stats")
	if room_id.strip_edges().is_empty():
		return _failure("missing_room_id")
	var parameters_value: Variant = (build as Dictionary).get("final_parameters", null)
	if not parameters_value is Dictionary:
		return _failure("missing_final_parameters")
	var parameters: Dictionary = parameters_value
	var values: Dictionary = {
		"move_speed": 245.0,
		"acceleration": 245.0,
		"dodge_distance": RangerSkillRulesScript.DODGE_SPEED * float(RangerSkillRulesScript.DODGE_DURATION_TICKS) / float(RangerSkillRulesScript.TICKS_PER_SECOND),
		"attack_cooldown_ticks": RangerSkillRulesScript.PIERCING_ARROW_COOLDOWN_TICKS,
		"dodge_duration_ticks": RangerSkillRulesScript.DODGE_DURATION_TICKS,
		"dodge_cooldown_ticks": RangerSkillRulesScript.DODGE_COOLDOWN_TICKS,
		"resistances": {"physical": 0.0},
	}
	for key: Variant in (overlay as Dictionary).keys():
		if not key is String or String(key) not in ROOM_OVERLAY_FIELDS:
			return _failure("unknown_room_combat_stats_field:%s" % String(key))
		values[String(key)] = (overlay as Dictionary)[key]
	for field: String in ["attack_cooldown_ticks", "dodge_duration_ticks", "dodge_cooldown_ticks"]:
		if values[field] is float and is_equal_approx(float(values[field]), roundf(float(values[field]))):
			values[field] = int(roundf(float(values[field])))
	var provenance: Dictionary = {}
	for field: String in NUMERIC_FIELDS + INTEGER_FIELDS:
		provenance[field] = ["build:%s" % field]
	for field: String in ["move_speed", "acceleration", "dodge_distance", "attack_cooldown_ticks", "dodge_duration_ticks", "dodge_cooldown_ticks"]:
		provenance[field] = ["room:%s:%s" % [room_id, field]]
	var stats_data := {
		"schema_version": SCHEMA_VERSION,
		"maximum_health": parameters.get("max_health", null),
		"damage": parameters.get("damage", null),
		"projectile_speed": parameters.get("v", null),
		"targeting_distance": parameters.get("d", null),
		"move_speed": values.move_speed,
		"acceleration": values.acceleration,
		"dodge_distance": values.dodge_distance,
		"attack_cooldown_ticks": values.attack_cooldown_ticks,
		"dodge_duration_ticks": values.dodge_duration_ticks,
		"dodge_cooldown_ticks": values.dodge_cooldown_ticks,
		"resistances": (values.resistances as Dictionary).duplicate(true) if values.resistances is Dictionary else values.resistances,
		"provenance": provenance,
	}
	return from_data(stats_data)


func snapshot() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"maximum_health": maximum_health,
		"damage": damage,
		"projectile_speed": projectile_speed,
		"targeting_distance": targeting_distance,
		"move_speed": move_speed,
		"acceleration": acceleration,
		"dodge_distance": dodge_distance,
		"attack_cooldown_ticks": attack_cooldown_ticks,
		"dodge_duration_ticks": dodge_duration_ticks,
		"dodge_cooldown_ticks": dodge_cooldown_ticks,
		"resistances": resistances.duplicate(true),
		"provenance": provenance.duplicate(true),
	}


func _assign(data: Dictionary) -> void:
	maximum_health = float(data.maximum_health)
	damage = float(data.damage)
	projectile_speed = float(data.projectile_speed)
	targeting_distance = float(data.targeting_distance)
	move_speed = float(data.move_speed)
	acceleration = float(data.acceleration)
	dodge_distance = float(data.dodge_distance)
	attack_cooldown_ticks = int(data.attack_cooldown_ticks)
	dodge_duration_ticks = int(data.dodge_duration_ticks)
	dodge_cooldown_ticks = int(data.dodge_cooldown_ticks)
	resistances = (data.resistances as Dictionary).duplicate(true)
	provenance = (data.provenance as Dictionary).duplicate(true)


static func _finite_positive(value: Variant) -> bool:
	return _finite_number(value) and float(value) > 0.0


static func _finite_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func _non_negative_integer(value: Variant) -> bool:
	return typeof(value) == TYPE_INT and int(value) >= 0


static func _failure(error: String) -> Dictionary:
	return {"ok": false, "error": error, "errors": [error], "value": {}}
