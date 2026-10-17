class_name DamageOutcome
extends RefCounted

var tick := -1
var attack_instance_id := ""
var source_key := ""
var target_key := ""
var part_id := ""
var damage_type := ""
var requested_damage := 0.0
var applied_damage := 0.0
var remaining_health := 0.0
var lethal := false


func snapshot() -> Dictionary:
	return {
		"tick": tick,
		"attack_instance_id": attack_instance_id,
		"source_key": source_key,
		"target_key": target_key,
		"part_id": part_id,
		"damage_type": damage_type,
		"requested_damage": requested_damage,
		"applied_damage": applied_damage,
		"remaining_health": remaining_health,
		"lethal": lethal,
	}
