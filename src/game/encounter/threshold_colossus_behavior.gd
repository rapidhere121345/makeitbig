class_name ThresholdColossusBehavior
extends EnemyBehavior

## The Threshold Colossus's execution half (room session migration item 9).
## The bodies moved verbatim from EncounterDirector's boss methods. The
## colossus declares no planner request actions: its slam/sweep/lane actions
## are started inside its own update_tick exactly as before. Stateless: every
## per-enemy field lives on CombatEnemyState. The hash-visible strings
## ("threshold_colossus", "slam", "sweep", "lane", phase ids) are unchanged.

const CombatQueryScript := preload("res://src/runtime/geometry/combat_query.gd")


func kind_id() -> String:
	return "threshold_colossus"


func action_ids() -> Array[String]:
	return []


func update_tick(director: EncounterDirector, enemy: CombatEnemyState, intent: Dictionary) -> void:
	if enemy.phase_id == "sealed" and enemy.phase_state == "stable" and director.boss_damage.compare(director.boss_maximum.multiply(BigValue.from_float(0.5))) >= 0:
		if enemy.action_instance_id > 0:
			director.combat_event_stream.emit(director.tick, "action_interrupted", {
				"action_instance_id": enemy.action_instance_id, "actor_id": "enemy/%d" % enemy.entity_id,
				"action_id": enemy.action_id, "reason": "phase_transition",
			})
		enemy.phase_state = "transition"
		enemy.action_id = "none"
		enemy.action_instance_id = 0
		enemy.action_state = "none"
		enemy.state_started_tick = director.tick
		enemy.state_ends_tick = director.tick + director.BOSS_TRANSITION_TICKS
		enemy.impact_tick = -1
		enemy.impact_resolved = false
		enemy.target_shape = {}
	if enemy.phase_state == "transition":
		if director.tick >= enemy.state_ends_tick:
			enemy.phase_id = "awakened"
			enemy.phase_state = "stable"
			enemy.core_open = true
			enemy.core_vulnerable = true
			enemy.left_hand_position = enemy.position + Vector2(-43.0, -8.0)
			enemy.right_hand_position = enemy.position + Vector2(38.0, 12.0)
		return
	director._advance_action_state(enemy, director.BOSS_ACTIVE_TICKS, director.BOSS_RECOVERY_TICKS)
	if enemy.action_state == "none":
		var chosen := intent if not intent.is_empty() else director._intent_for_enemy(enemy)
		var requested := String(chosen.get("request_action", ""))
		if requested in ["slam", "sweep", "lane"]:
			start_boss_action(director, enemy, requested, chosen.get("action_direction", Vector2.ZERO))
			if enemy.phase_id == "awakened":
				enemy.next_action_index += 1
	if enemy.action_state == "active" and not enemy.impact_resolved:
		enemy.impact_resolved = true
		director._resolve_hostile_attack(enemy, 1.8 if enemy.phase_id == "awakened" else 1.2, CombatQueryScript.shape_contains(enemy.target_shape, director.player_position))
	update_boss_hands(enemy)


func start_boss_action(director: EncounterDirector, enemy: CombatEnemyState, action: String, planned_direction: Vector2 = Vector2.ZERO) -> void:
	director._begin_action(enemy, action, director.BOSS_WINDUP_TICKS)
	var direction := planned_direction.normalized() if planned_direction != Vector2.ZERO else enemy.position.direction_to(director.player_position)
	if direction == Vector2.ZERO:
		direction = Vector2.LEFT
	enemy.facing = direction
	match action:
		"sweep":
			enemy.target_shape = {"type": "fan", "origin": enemy.position, "direction": direction, "half_angle": deg_to_rad(48.0), "radius": 190.0}
		"lane":
			enemy.target_shape = {"type": "lane", "origin": enemy.position, "direction": direction, "length": 230.0, "width": 52.0}
		_:
			var target := director._clamp_to_arena(director.player_position, 28.0)
			enemy.target_shape = {"type": "rect", "rect": Rect2(target - Vector2(38.0, 30.0), Vector2(76.0, 60.0))}
	director._emit_enemy_action_accepted(enemy)


func update_boss_hands(enemy: CombatEnemyState) -> void:
	var left_base := enemy.position + Vector2(-43.0 if enemy.phase_id == "awakened" else -34.0, -8.0 if enemy.phase_id == "awakened" else 0.0)
	var right_base := enemy.position + Vector2(38.0 if enemy.phase_id == "awakened" else 34.0, 12.0 if enemy.phase_id == "awakened" else 0.0)
	enemy.left_hand_position = left_base
	enemy.right_hand_position = right_base
	if enemy.action_state in ["windup", "active"]:
		match enemy.action_id:
			"slam":
				enemy.left_hand_position += Vector2(0.0, -20.0 if enemy.action_state == "windup" else 18.0)
			"sweep":
				enemy.right_hand_position += enemy.facing.rotated(-PI * 0.5) * (18.0 if enemy.action_state == "windup" else -18.0)
			"lane":
				enemy.left_hand_position += Vector2(-8.0, 10.0)
				enemy.right_hand_position += Vector2(8.0, -10.0)
