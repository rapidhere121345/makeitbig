class_name ChargingRaiderBehavior
extends EnemyBehavior

## The charging raider's execution half (room session migration item 9). The
## bodies moved verbatim from EncounterDirector's charger methods, including
## the charge request validation and the "invalid_charge_execution" reason it
## writes when a planned charge cannot be executed. Stateless: every
## per-enemy field lives on CombatEnemyState. The hash-visible strings
## ("charging_raider", "charge") are unchanged.

const CombatQueryScript := preload("res://src/runtime/geometry/combat_query.gd")
const EnemyTacticsScript := preload("res://src/systems/enemy_tactics.gd")


func kind_id() -> String:
	return "charging_raider"


func action_ids() -> Array[String]:
	return ["charge"]


func update_tick(director: EncounterDirector, enemy: CombatEnemyState, intent: Dictionary) -> void:
	var previous_state := enemy.action_state
	var action := director.action_profile(enemy, "charge")
	director.advance_action_state(enemy, int(action.get("active_ticks", 0)), int(action.get("recovery_ticks", 0)))
	if enemy.action_state == "active":
		enemy.motion_state = "moving"
		var before := enemy.position
		var step := enemy.charge_length / float(maxi(1, int(action.get("active_ticks", 1))))
		var movement_result := director.move_enemy_actor(enemy, enemy.charge_direction * step)
		if not bool(movement_result.get("ok", false)):
			enemy.motion_state = "idle"
		if not enemy.impact_resolved:
			var contact := CombatQueryScript.distance_to_segment(director.player_position, before, enemy.position) <= EnemyTacticsScript.CHARGER_CONTACT_RADIUS
			if contact:
				enemy.impact_resolved = true
				director.resolve_hostile_attack(enemy, float(action.get("damage", 0.0)), true)
	elif previous_state == "active" and enemy.action_state == "recovery" and not enemy.impact_resolved:
		enemy.impact_resolved = true
		director.resolve_hostile_attack(enemy, float(action.get("damage", 0.0)), false)
	elif enemy.action_state == "none":
		director.commit_normal_enemy_intent(enemy, intent if not intent.is_empty() else director.intent_for_enemy(enemy))
	else:
		enemy.motion_state = "idle"


## The charge arm of EncounterDirector.commit_normal_enemy_intent: the same
## direction/distance validation and the same invalid_charge_execution
## fallback, evaluated in the same order.
func start_requested_action(director: EncounterDirector, enemy: CombatEnemyState, _action: String, intent: Dictionary) -> void:
	var action_direction_value: Variant = intent.get("action_direction", Vector2.ZERO)
	var action_direction := Vector2(action_direction_value) if action_direction_value is Vector2 else Vector2.ZERO
	var action_distance_value: Variant = intent.get("action_distance", null)
	var valid_direction := is_finite(action_direction.x) and is_finite(action_direction.y) and not action_direction.is_zero_approx()
	var valid_distance := (action_distance_value is int or action_distance_value is float) and not (action_distance_value is bool) and is_finite(float(action_distance_value)) and float(action_distance_value) > 0.0
	if not valid_direction or not valid_distance or not start_charger_action(director, enemy, action_direction, float(action_distance_value)):
		enemy.motion_state = "idle"
		enemy.tactic_reason = "invalid_charge_execution"


func start_charger_action(director: EncounterDirector, enemy: CombatEnemyState, direction: Vector2, action_distance: float) -> bool:
	if not is_finite(direction.x) or not is_finite(direction.y) or direction.is_zero_approx() or not is_finite(action_distance) or action_distance <= 0.0:
		return false
	var action := director.action_profile(enemy, "charge")
	if action.is_empty():
		return false
	director.begin_action(enemy, "charge", int(action.get("windup_ticks", 0)))
	director.set_enemy_collision_class(enemy, &"ghost")
	enemy.charge_origin = enemy.position
	enemy.charge_direction = direction.normalized()
	enemy.facing = enemy.charge_direction
	enemy.charge_length = action_distance
	enemy.charge_width = EnemyTacticsScript.CHARGER_CONTACT_RADIUS * 2.0
	enemy.target_shape = {"type": "lane", "origin": enemy.charge_origin, "direction": enemy.charge_direction, "length": enemy.charge_length, "width": enemy.charge_width}
	director.emit_enemy_action_accepted(enemy)
	return true
