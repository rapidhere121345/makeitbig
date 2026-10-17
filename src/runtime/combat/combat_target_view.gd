class_name CombatTargetView
extends RefCounted

const SelfScript := preload("res://src/runtime/combat/combat_target_view.gd")

var target_key := ""
var health := 0.0
var maximum_health := 0.0
var alive := true
var resistances: Dictionary = {}


static func from_data(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {"ok": false, "error": "target_view_not_dictionary"}
	var source: Dictionary = value
	var result: Variant = SelfScript.new()
	result.target_key = String(source.get("target_key", ""))
	result.health = float(source.get("health", -1.0))
	result.maximum_health = float(source.get("maximum_health", -1.0))
	result.alive = bool(source.get("alive", result.health > 0.0))
	var raw_resistances: Variant = source.get("resistances", {})
	if not raw_resistances is Dictionary:
		return {"ok": false, "error": "invalid_target_resistances"}
	for raw_key: Variant in raw_resistances.keys():
		var amount: Variant = raw_resistances[raw_key]
		if not amount is int and not amount is float or not is_finite(float(amount)):
			return {"ok": false, "error": "invalid_target_resistance_value"}
		result.resistances[String(raw_key)] = float(amount)
	if result.target_key.is_empty() or result.health < 0.0 or result.maximum_health <= 0.0 or result.health > result.maximum_health or not is_finite(result.health) or not is_finite(result.maximum_health):
		return {"ok": false, "error": "invalid_target_view"}
	return {"ok": true, "error": "", "value": result}


func resistance_for(damage_type: String) -> float:
	return clampf(float(resistances.get(damage_type, 0.0)), -1.0, 1.0)


func snapshot() -> Dictionary:
	return {
		"target_key": target_key,
		"health": health,
		"maximum_health": maximum_health,
		"alive": alive,
		"resistances": resistances.duplicate(true),
	}
