class_name MeleePursuerBehavior
extends EnemyBehavior

## The melee pursuer's execution half (room session migration item 9). The
## bodies moved verbatim from EncounterDirector's melee methods; the director
## keeps the encounter lifecycle, the tick order and the shared action
## helpers. Stateless: every per-enemy field this behavior reads or writes
## lives on CombatEnemyState, so the state hash sees it. The hash-visible
## strings ("melee_pursuer", "melee_attack", "contact") are unchanged.

const CombatQueryScript := preload("res://src/core/geometry/combat_query.gd")
const EnemyTacticsScript := preload("res://src/systems/enemy_tactics.gd")


func kind_id() -> String:
	return "melee_pursuer"


func action_ids() -> Array[String]:
	return ["melee_attack"]


func update_tick(director: EncounterDirector, enemy: CombatEnemyState, intent: Dictionary) -> void:
	var previous_state := enemy.action_state
	var action := director.action_profile(enemy, "contact")
	director.advance_action_state(enemy, int(action.get("active_ticks", 0)), int(action.get("recovery_ticks", 0)))
	if enemy.action_state == "active" and not enemy.impact_resolved:
		enemy.impact_resolved = true
		director.resolve_hostile_attack(enemy, float(action.get("damage", 0.0)), CombatQueryScript.shape_contains(enemy.target_shape, director.player_position))
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
	start_melee_action(director, enemy, action_direction)


func start_melee_action(director: EncounterDirector, enemy: CombatEnemyState, direction: Vector2 = Vector2.ZERO) -> void:
	var action := director.action_profile(enemy, "contact")
	director.begin_action(enemy, "contact", int(action.get("windup_ticks", 0)))
	enemy.facing = direction.normalized() if direction != Vector2.ZERO else enemy.position.direction_to(director.player_position)
	if enemy.facing == Vector2.ZERO:
		enemy.facing = Vector2.RIGHT
	enemy.target_shape = {"type": "circle", "origin": enemy.position, "radius": EnemyTacticsScript.MELEE_ATTACK_RANGE}
	director.emit_enemy_action_accepted(enemy)
