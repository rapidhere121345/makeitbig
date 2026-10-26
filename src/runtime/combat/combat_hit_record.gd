class_name CombatHitRecord
extends RefCounted

const SCHEMA_VERSION := 1
const SelfScript := preload("res://src/runtime/combat/combat_hit_record.gd")
const CoreResult := preload("res://src/core/result.gd")

var tick := -1
var attack_instance_id := ""
var source_key := ""
var target_key := ""
var part_id := ""
var damage_group_id := ""
var damage_type := "physical"
var contact_kind := "attack"
var toi := 0.0
var base_damage := 0.0
var priority := 0
var penetration_index := 0
var contact_point := Vector2.ZERO
var allow_repeat_target := false


static func from_data(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return CoreResult.failure("hit_not_dictionary")
	var source: Dictionary = value
	var result: Variant = SelfScript.new()
	result.tick = int(source.get("tick", -1))
	result.attack_instance_id = String(source.get("attack_instance_id", ""))
	result.source_key = String(source.get("source_key", ""))
	result.target_key = String(source.get("target_key", ""))
	result.part_id = String(source.get("part_id", "body"))
	result.damage_group_id = String(source.get("damage_group_id", ""))
	result.damage_type = String(source.get("damage_type", "physical"))
	result.contact_kind = String(source.get("contact_kind", "attack"))
	result.toi = float(source.get("toi", 0.0))
	result.base_damage = float(source.get("base_damage", 0.0))
	result.priority = int(source.get("priority", 0))
	result.penetration_index = int(source.get("penetration_index", 0))
	result.contact_point = source.get("contact_point", Vector2.ZERO) if source.get("contact_point", Vector2.ZERO) is Vector2 else Vector2.ZERO
	result.allow_repeat_target = bool(source.get("allow_repeat_target", false))
	var error: String = result.validate()
	if not error.is_empty():
		return CoreResult.failure(error)
	return {"ok": true, "error": "", "value": result}


func validate() -> String:
	if tick < 0:
		return "invalid_hit_tick"
	for value: String in [attack_instance_id, source_key, target_key, part_id, damage_group_id, damage_type, contact_kind]:
		if not _valid_id(value):
			return "invalid_hit_identity"
	if not is_finite(toi) or toi < 0.0 or toi > 1.0:
		return "invalid_hit_toi"
	if not is_finite(base_damage) or base_damage < 0.0:
		return "invalid_hit_damage"
	if priority < 0 or penetration_index < 0 or not contact_point.is_finite():
		return "invalid_hit_contact"
	return ""


func dedupe_key() -> String:
	return "%s|%s|%s" % [attack_instance_id, target_key, damage_group_id]


func sort_key() -> String:
	return "%09d|%+.9f|%09d|%s|%s|%s|%s" % [tick, toi, priority, attack_instance_id, target_key, part_id, damage_group_id]


func snapshot() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"tick": tick,
		"attack_instance_id": attack_instance_id,
		"source_key": source_key,
		"target_key": target_key,
		"part_id": part_id,
		"damage_group_id": damage_group_id,
		"damage_type": damage_type,
		"contact_kind": contact_kind,
		"toi": toi,
		"base_damage": base_damage,
		"priority": priority,
		"penetration_index": penetration_index,
		"contact_point": contact_point,
		"allow_repeat_target": allow_repeat_target,
	}


static func ordered(values: Array) -> Array:
	var result: Array = values.duplicate()
	result.sort_custom(func(left: Variant, right: Variant) -> bool:
		return left.sort_key() < right.sort_key()
	)
	return result


static func _valid_id(value: String) -> bool:
	return not value.is_empty() and value == value.strip_edges() and not value.contains(" ")

