class_name BossDamageOutcome
extends RefCounted

const DamageValueScript := preload("res://src/runtime/combat/boss_damage_value.gd")
const BigValueScript := preload("res://src/core/big_value.gd")

var tick := -1
var attack_instance_id := ""
var source_key := ""
var target_key := ""
var part_id := ""
var damage_group_id := ""
var damage_type := "physical"
var requested_damage: BossDamageValue = null
var applied_damage: BossDamageValue = null
var remaining_health: BigValue = null
var lethal := false


func snapshot() -> Dictionary:
	return {
		"tick": tick,
		"attack_instance_id": attack_instance_id,
		"source_key": source_key,
		"target_key": target_key,
		"part_id": part_id,
		"damage_group_id": damage_group_id,
		"damage_type": damage_type,
		"requested_damage": requested_damage.snapshot() if requested_damage != null else {},
		"applied_damage": applied_damage.snapshot() if applied_damage != null else {},
		"remaining_health": {
			"layer": remaining_health.layer,
			"magnitude": remaining_health.magnitude,
		} if remaining_health != null else {},
		"lethal": lethal,
	}
