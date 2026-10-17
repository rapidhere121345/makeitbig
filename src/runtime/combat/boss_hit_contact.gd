class_name BossHitContact
extends RefCounted

## Geometry-only contact against one Boss hurtbox part.

var target_key := ""
var part_id := ""
var damage_group_id := ""
var toi := 0.0
var contact_point := Vector2.ZERO
var priority := 0


func sort_key() -> String:
	return "%09.6f|%09d|%s|%s|%s" % [toi, priority, target_key, part_id, damage_group_id]


func snapshot() -> Dictionary:
	return {
		"target_key": target_key,
		"part_id": part_id,
		"damage_group_id": damage_group_id,
		"toi": toi,
		"contact_point": contact_point,
		"priority": priority,
	}


static func ordered(values: Array) -> Array:
	var result := values.duplicate()
	result.sort_custom(func(left: BossHitContact, right: BossHitContact) -> bool:
		return left.sort_key() < right.sort_key()
	)
	return result
