class_name CombatPresentationSnapshot
extends RefCounted

## Value boundary from gameplay into presentation. No live actor, projectile,
## registry, node, RNG or simulation object survives capture. Entity/action ids
## remain the stable gameplay ids. Typed records below are detached draw data.

const Enemy := preload("res://src/runtime/world/combat_enemy_state.gd")
const Projectile := preload("res://src/runtime/world/combat_arrow_projectile.gd")
const ENEMY_FIELDS := ["entity_id", "kind_id", "position", "health", "maximum_health", "is_boss", "facing", "motion_state", "action_state", "state_started_tick", "state_ends_tick", "impact_tick", "impact_resolved", "hit_flash_until_tick", "death_started_tick", "charge_origin", "charge_direction", "charge_length", "charge_width", "fan_origin", "fan_direction", "fan_half_angle", "fan_radius", "phase_id", "phase_state", "action_id", "action_instance_id", "core_open", "core_vulnerable", "left_hand_position", "right_hand_position", "target_shape", "parts", "next_action_index", "tactic_state", "tactic_reason", "next_action_ready_tick"]
const PROJECTILE_FIELDS := ["action_instance_id", "target_entity_id", "spawned_tick", "origin", "direction", "position", "previous_position", "maximum_range", "speed", "distance_travelled", "aggregate_damage", "ordinary_damage", "event_count", "payload"]


static func capture(values: Dictionary) -> Dictionary:
	var snapshot: Dictionary = values.duplicate(true)
	var copied_enemies: Array[CombatEnemyState] = []
	var copied_boss: CombatEnemyState = null
	for source: CombatEnemyState in values.get("enemies", []):
		var copy := enemy_record(source)
		copied_enemies.append(copy)
		if source == values.get("boss"):
			copied_boss = copy
	snapshot["enemies"] = copied_enemies
	snapshot["boss"] = copied_boss
	var copied_projectiles: Array[CombatArrowProjectile] = []
	for source: CombatArrowProjectile in values.get("projectiles", []):
		var copy := Projectile.new(source.action_instance_id, source.target_entity_id,
			source.spawned_tick, source.origin, source.direction, source.maximum_range,
			source.speed, source.aggregate_damage.duplicate_value(), source.ordinary_damage,
			source.event_count.duplicate_value(), source.payload)
		for field: String in PROJECTILE_FIELDS:
			copy.set(field, _copy_value(source.get(field)))
		copied_projectiles.append(copy)
	snapshot["projectiles"] = copied_projectiles
	for field in ["boss_damage", "boss_maximum"]:
		if values.get(field) is BigValue:
			snapshot[field] = values[field].duplicate_value()
	return snapshot


static func enemy_record(source: CombatEnemyState) -> CombatEnemyState:
	var copy := Enemy.new(source.position, source.health, source.is_boss, source.entity_id, source.kind_id)
	for field: String in ENEMY_FIELDS:
		copy.set(field, _copy_value(source.get(field)))
	return copy


static func _copy_value(value: Variant) -> Variant:
	if value is BigValue:
		return value.duplicate_value()
	if value is Dictionary or value is Array:
		return value.duplicate(true)
	return value
