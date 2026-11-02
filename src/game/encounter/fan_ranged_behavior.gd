class_name FanRangedBehavior
extends EnemyBehavior

## The fan ranged enemy's execution half (room session migration item 9). The
## bodies moved verbatim from EncounterDirector's fan methods. Stateless:
## every per-enemy field lives on CombatEnemyState (the compact fan mirrors
## fan_origin/fan_direction/fan_half_angle/fan_radius included). The
## hash-visible strings ("fan_ranged", "fan_attack", "fan") are unchanged.

const EnemyTacticsScript := preload("res://src/systems/enemy_tactics.gd")


func kind_id() -> String:
	return "fan_ranged"


func action_ids() -> Array[String]:
	return ["fan_attack"]


func update_tick(director: EncounterDirector, enemy: CombatEnemyState, intent: Dictionary) -> void:
	var previous_state := enemy.action_state
	var action := director.action_profile(enemy, "fan")
	director.advance_action_state(enemy, int(action.get("active_ticks", 0)), int(action.get("recovery_ticks", 0)))
	if enemy.action_state == "active" and not enemy.impact_resolved:
		enemy.impact_resolved = true
		director.resolve_hostile_attack(enemy, float(action.get("damage", 0.0)), EnemyTacticsScript.fan_attack_contains(enemy.target_shape, director.player_position))
	if previous_state == "active" and enemy.action_state == "recovery" and not enemy.impact_resolved:
		enemy.impact_resolved = true
		director.resolve_hostile_attack(enemy, float(action.get("damage", 0.0)), false)
	if enemy.action_state == "none":
		director.commit_normal_enemy_intent(enemy, intent if not intent.is_empty() else director.intent_for_enemy(enemy))
	else:
		enemy.motion_state = "idle"


func start_requested_action(director: EncounterDirector, enemy: CombatEnemyState, _action: String, intent: Dictionary) -> void:
	var action_direction_value: Variant = intent.get("action_direction", Vector2.ZERO)
	var action_direction := Vector2(action_direction_value) if action_direction_value is Vector2 else Vector2.ZERO
	start_fan_action(director, enemy, action_direction)


func start_fan_action(director: EncounterDirector, enemy: CombatEnemyState, direction: Vector2 = Vector2.ZERO) -> void:
	var action := director.action_profile(enemy, "fan")
	director.begin_action(enemy, "fan", int(action.get("windup_ticks", 0)))
	var fan_direction := direction.normalized() if direction != Vector2.ZERO else enemy.position.direction_to(director.player_position)
	if fan_direction == Vector2.ZERO:
		fan_direction = enemy.facing
	enemy.target_shape = EnemyTacticsScript.fan_attack_shape(enemy.position, fan_direction)
	## Keep the compact action-state mirrors available to existing diagnostics and
	## semantic hashing. Presentation and hit resolution below read target_shape.
	enemy.fan_origin = enemy.target_shape["origin"]
	enemy.fan_direction = enemy.target_shape["direction"]
	enemy.fan_half_angle = enemy.target_shape["half_angle"]
	enemy.fan_radius = enemy.target_shape["radius"]
	enemy.facing = enemy.fan_direction
	director.emit_enemy_action_accepted(enemy)
