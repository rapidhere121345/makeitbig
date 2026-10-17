class_name BossAttackQuery
extends RefCounted

const Channels := preload("res://src/runtime/spatial/spatial_channels.gd")
const DamageValueScript := preload("res://src/runtime/combat/boss_damage_value.gd")

## Explicit one-tick attack query for a multipart Boss target.

var source: SimEntityHandle = null
var target_key := ""
var channel: StringName = &""
var start := Vector2.ZERO
var displacement := Vector2.ZERO
var radius: float = 0.0
var piercing := false
var attack_instance_id := ""
var damage: BossDamageValue = null
var damage_type := "physical"
var priority := 0
var penetration_index := 0


static func make(
	from_entity: SimEntityHandle,
	query_target_key: String,
	query_channel: StringName,
	path_start: Vector2,
	path_displacement: Vector2,
	path_radius: float,
	path_piercing: bool,
	attack_id: String,
	damage_value: BossDamageValue,
	query_damage_type: String = "physical",
	query_priority: int = 0,
	query_penetration_index: int = 0
) -> BossAttackQuery:
	var result := BossAttackQuery.new()
	result.source = from_entity
	result.target_key = query_target_key
	result.channel = query_channel
	result.start = path_start
	result.displacement = path_displacement
	result.radius = path_radius
	result.piercing = path_piercing
	result.attack_instance_id = attack_id
	result.damage = damage_value
	result.damage_type = query_damage_type
	result.priority = query_priority
	result.penetration_index = query_penetration_index
	return result


func validate() -> String:
	if source == null:
		return "invalid_boss_attack_source"
	if channel != Channels.PROJECTILE and channel != Channels.ATTACK:
		return "invalid_boss_attack_channel"
	if not start.is_finite() or not displacement.is_finite() or not is_finite(radius) or radius < 0.0:
		return "invalid_boss_attack_geometry"
	if not _valid_id(attack_instance_id) or not _valid_id(damage_type):
		return "invalid_boss_attack_identity"
	if not target_key.is_empty() and not _valid_id(target_key):
		return "invalid_boss_attack_target"
	if damage == null or not damage.validate().is_empty():
		return "invalid_boss_attack_damage"
	if priority < 0 or penetration_index < 0:
		return "invalid_boss_attack_order"
	return ""


func duplicate_value() -> BossAttackQuery:
	return make(source, target_key, channel, start, displacement, radius, piercing, attack_instance_id, damage.duplicate_value(), damage_type, priority, penetration_index)


static func _valid_id(value: String) -> bool:
	return not value.is_empty() and value == value.strip_edges() and not value.contains(" ")
