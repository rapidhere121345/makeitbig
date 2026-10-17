class_name BossHitRecord
extends RefCounted

const DamageValueScript := preload("res://src/runtime/combat/boss_damage_value.gd")
const QueryScript := preload("res://src/runtime/combat/boss_attack_query.gd")
const ContactScript := preload("res://src/runtime/combat/boss_hit_contact.gd")

## Typed hit fact written by the multipart spatial query and consumed by the
## Boss branch of DamageResolution.

var tick := -1
var attack_instance_id := ""
var source_key := ""
var target_key := ""
var part_id := ""
var damage_group_id := ""
var damage_type := "physical"
var toi := 0.0
var contact_point := Vector2.ZERO
var priority := 0
var penetration_index := 0
var damage: BossDamageValue = null


static func from_query(query: BossAttackQuery, contact: BossHitContact, at_tick: int, source: String) -> BossHitRecord:
	var result := BossHitRecord.new()
	result.tick = at_tick
	result.attack_instance_id = query.attack_instance_id
	result.source_key = source
	result.target_key = contact.target_key
	result.part_id = contact.part_id
	result.damage_group_id = contact.damage_group_id
	result.damage_type = query.damage_type
	result.toi = contact.toi
	result.contact_point = contact.contact_point
	result.priority = query.priority
	result.penetration_index = query.penetration_index
	result.damage = query.damage.duplicate_value()
	return result


func validate() -> String:
	for value: String in [attack_instance_id, source_key, target_key, part_id, damage_group_id, damage_type]:
		if not _valid_id(value):
			return "invalid_boss_hit_identity"
	if not is_finite(toi) or toi < 0.0 or toi > 1.0 or not contact_point.is_finite():
		return "invalid_boss_hit_geometry"
	if priority < 0 or penetration_index < 0:
		return "invalid_boss_hit_order"
	if damage == null or not damage.validate().is_empty():
		return "invalid_boss_hit_damage"
	return ""


func dedupe_key() -> String:
	return "%s|%s|%s" % [attack_instance_id, target_key, damage_group_id]


func sort_key() -> String:
	return "%09.6f|%09d|%s|%s|%s|%s|%s" % [toi, priority, attack_instance_id, target_key, part_id, damage_group_id, penetration_index]


func duplicate_value() -> BossHitRecord:
	var result := BossHitRecord.new()
	result.tick = tick
	result.attack_instance_id = attack_instance_id
	result.source_key = source_key
	result.target_key = target_key
	result.part_id = part_id
	result.damage_group_id = damage_group_id
	result.damage_type = damage_type
	result.toi = toi
	result.contact_point = contact_point
	result.priority = priority
	result.penetration_index = penetration_index
	result.damage = damage.duplicate_value()
	return result


func snapshot() -> Dictionary:
	return {
		"tick": tick,
		"attack_instance_id": attack_instance_id,
		"source_key": source_key,
		"target_key": target_key,
		"part_id": part_id,
		"damage_group_id": damage_group_id,
		"damage_type": damage_type,
		"toi": toi,
		"contact_point": contact_point,
		"priority": priority,
		"penetration_index": penetration_index,
		"damage": damage.snapshot() if damage != null else {},
	}


static func ordered(values: Array) -> Array:
	var result := values.duplicate()
	result.sort_custom(func(left: BossHitRecord, right: BossHitRecord) -> bool:
		return left.sort_key() < right.sort_key()
	)
	return result


static func _valid_id(value: String) -> bool:
	return not value.is_empty() and value == value.strip_edges() and not value.contains(" ")
