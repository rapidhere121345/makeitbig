class_name BossHurtbox
extends RefCounted

## One authored hurtbox part of a multipart Boss target.

var target_key := ""
var part_id := ""
var damage_group_id := ""
var local_offset := Vector2.ZERO
var radius: float = 0.0
var active := true
var broken := false
var priority := 0


static func make(
	part: String,
	group: String,
	offset: Vector2,
	part_radius: float,
	part_active: bool = true,
	part_broken: bool = false,
	part_priority: int = 0
) -> BossHurtbox:
	var result := BossHurtbox.new()
	result.part_id = part
	result.damage_group_id = group
	result.local_offset = offset
	result.radius = part_radius
	result.active = part_active
	result.broken = part_broken
	result.priority = part_priority
	return result


func validate() -> String:
	if not _valid_id(part_id) or not _valid_id(damage_group_id):
		return "invalid_boss_hurtbox_identity"
	if not local_offset.is_finite() or not is_finite(radius) or radius <= 0.0:
		return "invalid_boss_hurtbox_geometry"
	if priority < 0:
		return "invalid_boss_hurtbox_priority"
	if not target_key.is_empty() and not _valid_id(target_key):
		return "invalid_boss_hurtbox_target"
	return ""


func is_hittable() -> bool:
	return active and not broken


func world_center(target_position: Vector2) -> Vector2:
	return target_position + local_offset


func duplicate_value() -> BossHurtbox:
	var result := BossHurtbox.make(part_id, damage_group_id, local_offset, radius, active, broken, priority)
	result.target_key = target_key
	return result


func sort_key() -> String:
	return "%09d|%s|%s" % [priority, part_id, damage_group_id]


func snapshot() -> Dictionary:
	return {
		"target_key": target_key,
		"part_id": part_id,
		"damage_group_id": damage_group_id,
		"local_offset": local_offset,
		"radius": radius,
		"active": active,
		"broken": broken,
		"priority": priority,
	}


static func _valid_id(value: String) -> bool:
	return not value.is_empty() and value == value.strip_edges() and not value.contains(" ")
