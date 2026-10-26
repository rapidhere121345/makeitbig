class_name EnemyAiTicks
extends RefCounted

## Enemy AI tick entry points extracted from MainArena. Each method syncs the
## encounter context, delegates to EncounterDirector and mirrors its battle
## report. Encounter and room state stay owned by MainArena and are reached
## through the typed owner reference.

const CombatQueryScript = preload("res://src/runtime/geometry/combat_query.gd")

var _main: MainArena


func _init(main: MainArena) -> void:
	_main = main


func _update_enemies_tick() -> void:
	_main._encounter_context()
	var previous_report := String(_main.encounter_director.battle_report)
	_main.encounter_director.update_tick()
	_main._encounter_report(previous_report)


func _enemy_tactics_snapshot() -> Dictionary:
	_main._encounter_context()
	return _main.encounter_director.enemy_tactics_snapshot()


func _enemy_tactics_hazards() -> Array[Dictionary]:
	if _main._hazard_domain != null and _main._hazard_domain.is_configured():
		return _main._hazard_domain.active_geometry()
	_main._encounter_context()
	return _main.encounter_director.enemy_tactics_hazards()


func _maybe_summon_reinforcements(elite: CombatEnemyState) -> void:
	_main._encounter_context()
	var previous_report := String(_main.encounter_director.battle_report)
	_main.encounter_director._maybe_summon_reinforcements(elite)
	_main._encounter_report(previous_report)


func _update_enemy_tick(enemy: CombatEnemyState, intent: Dictionary = {}) -> void:
	_main._encounter_context()
	var previous_report := String(_main.encounter_director.battle_report)
	_main.encounter_director._update_enemy_tick(enemy, intent)
	_main._encounter_report(previous_report)


func _advance_action_state(enemy: CombatEnemyState, active_ticks: int, recovery_ticks: int) -> bool:
	_main._encounter_context()
	var previous_report := String(_main.encounter_director.battle_report)
	var result: bool = bool(_main.encounter_director._advance_action_state(enemy, active_ticks, recovery_ticks))
	_main._encounter_report(previous_report)
	return result


func _finish_enemy_recovery_if_due(enemy: CombatEnemyState) -> bool:
	_main._encounter_context()
	var previous_report := String(_main.encounter_director.battle_report)
	var result: bool = bool(_main.encounter_director._finish_enemy_recovery_if_due(enemy))
	_main._encounter_report(previous_report)
	return result


func _begin_action(enemy: CombatEnemyState, action_id: String, windup_ticks: int) -> void:
	_main._encounter_context()
	_main.encounter_director._begin_action(enemy, action_id, windup_ticks)


func _emit_enemy_action_accepted(enemy: CombatEnemyState) -> void:
	_main._encounter_context()
	_main.encounter_director._emit_enemy_action_accepted(enemy)


func _enemy_breath_ticks(kind_id: String) -> int:
	_main._encounter_context()
	return _main.encounter_director._enemy_breath_ticks(kind_id)


func _intent_for_enemy(enemy: CombatEnemyState) -> Dictionary:
	_main._encounter_context()
	return _main.encounter_director._intent_for_enemy(enemy)


func _update_melee_tick(enemy: CombatEnemyState, intent: Dictionary = {}) -> void:
	_main._encounter_context()
	var previous_report := String(_main.encounter_director.battle_report)
	_main.encounter_director._update_melee_tick(enemy, intent)
	_main._encounter_report(previous_report)


func _start_melee_action(enemy: CombatEnemyState, direction: Vector2 = Vector2.ZERO) -> void:
	_main._encounter_context()
	_main.encounter_director._start_melee_action(enemy, direction)


func _start_charger_action(enemy: CombatEnemyState, direction: Vector2, action_distance: float) -> bool:
	_main._encounter_context()
	var previous_report := String(_main.encounter_director.battle_report)
	var result: bool = bool(_main.encounter_director._start_charger_action(enemy, direction, action_distance))
	_main._encounter_report(previous_report)
	return result


func _update_charger_tick(enemy: CombatEnemyState, intent: Dictionary = {}) -> void:
	_main._encounter_context()
	var previous_report := String(_main.encounter_director.battle_report)
	_main.encounter_director._update_charger_tick(enemy, intent)
	_main._encounter_report(previous_report)


func _start_fan_action(enemy: CombatEnemyState, direction: Vector2 = Vector2.ZERO) -> void:
	_main._encounter_context()
	_main.encounter_director._start_fan_action(enemy, direction)


func _update_fan_tick(enemy: CombatEnemyState, intent: Dictionary = {}) -> void:
	_main._encounter_context()
	var previous_report := String(_main.encounter_director.battle_report)
	_main.encounter_director._update_fan_tick(enemy, intent)
	_main._encounter_report(previous_report)


func _commit_normal_enemy_intent(enemy: CombatEnemyState, intent: Dictionary) -> void:
	_main._encounter_context()
	var previous_report := String(_main.encounter_director.battle_report)
	_main.encounter_director._commit_normal_enemy_intent(enemy, intent)
	_main._encounter_report(previous_report)


func _resolve_hostile_attack(enemy: CombatEnemyState, amount: float, shape_hit: bool) -> void:
	_main._encounter_context()
	var previous_report := String(_main.encounter_director.battle_report)
	_main.encounter_director._resolve_hostile_attack(enemy, amount, shape_hit)
	_main._encounter_report(previous_report)


func _update_boss_tick(enemy: CombatEnemyState, intent: Dictionary = {}) -> void:
	_main._encounter_context()
	var previous_report := String(_main.encounter_director.battle_report)
	_main.encounter_director._update_boss_tick(enemy, intent)
	_main._encounter_report(previous_report)


func _start_boss_action(enemy: CombatEnemyState, action: String, planned_direction: Vector2 = Vector2.ZERO) -> void:
	_main._encounter_context()
	_main.encounter_director._start_boss_action(enemy, action, planned_direction)


func _update_boss_hands(enemy: CombatEnemyState) -> void:
	_main._encounter_context()
	_main.encounter_director._update_boss_hands(enemy)


func _boss_shape_contains(shape: Dictionary, point: Vector2) -> bool:
	return CombatQueryScript.shape_contains(shape, point)
