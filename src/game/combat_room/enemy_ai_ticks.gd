class_name EnemyAiTicks
extends RefCounted

## Enemy AI tick entry points extracted from MainArena. Each method syncs the
## encounter context, delegates to EncounterDirector (per-archetype execution
## routes to its EnemyBehavior registry) and mirrors its battle
## report. Encounter and room state stay owned by MainArena and are reached
## through the typed owner reference.

const CombatQueryScript = preload("res://src/runtime/geometry/combat_query.gd")

var _main: MainArena
## The room authority; read at use time, never cache its replaced members.
var _session: RoomSession


func _init(main: MainArena) -> void:
	_main = main
	_session = main.session


func _update_enemies_tick() -> void:
	_main.sync_encounter_context()
	var previous_report := String(_session.encounter_director.battle_report)
	_session.encounter_director.update_tick()
	_main.adopt_encounter_report(previous_report)


func _enemy_tactics_snapshot() -> Dictionary:
	_main.sync_encounter_context()
	return _session.encounter_director.enemy_tactics_snapshot()


func _enemy_tactics_hazards() -> Array[Dictionary]:
	var hazard_domain: RefCounted = _main.room_hazards.domain
	if hazard_domain != null and hazard_domain.is_configured():
		return hazard_domain.active_geometry()
	_main.sync_encounter_context()
	return _session.encounter_director.enemy_tactics_hazards()


func maybe_summon_reinforcements(elite: CombatEnemyState) -> void:
	_main.sync_encounter_context()
	var previous_report := String(_session.encounter_director.battle_report)
	_session.encounter_director._maybe_summon_reinforcements(elite)
	_main.adopt_encounter_report(previous_report)


func _update_enemy_tick(enemy: CombatEnemyState, intent: Dictionary = {}) -> void:
	_main.sync_encounter_context()
	var previous_report := String(_session.encounter_director.battle_report)
	_session.encounter_director._update_enemy_tick(enemy, intent)
	_main.adopt_encounter_report(previous_report)


func _advance_action_state(enemy: CombatEnemyState, active_ticks: int, recovery_ticks: int) -> bool:
	_main.sync_encounter_context()
	var previous_report := String(_session.encounter_director.battle_report)
	var result: bool = bool(_session.encounter_director.advance_action_state(enemy, active_ticks, recovery_ticks))
	_main.adopt_encounter_report(previous_report)
	return result


func _finish_enemy_recovery_if_due(enemy: CombatEnemyState) -> bool:
	_main.sync_encounter_context()
	var previous_report := String(_session.encounter_director.battle_report)
	var result: bool = bool(_session.encounter_director.finish_enemy_recovery_if_due(enemy))
	_main.adopt_encounter_report(previous_report)
	return result


func _begin_action(enemy: CombatEnemyState, action_id: String, windup_ticks: int) -> void:
	_main.sync_encounter_context()
	_session.encounter_director.begin_action(enemy, action_id, windup_ticks)


func _emit_enemy_action_accepted(enemy: CombatEnemyState) -> void:
	_main.sync_encounter_context()
	_session.encounter_director.emit_enemy_action_accepted(enemy)


func _enemy_breath_ticks(kind_id: String) -> int:
	_main.sync_encounter_context()
	return _session.encounter_director.enemy_breath_ticks(kind_id)


func _intent_for_enemy(enemy: CombatEnemyState) -> Dictionary:
	_main.sync_encounter_context()
	return _session.encounter_director.intent_for_enemy(enemy)


func _update_melee_tick(enemy: CombatEnemyState, intent: Dictionary = {}) -> void:
	_main.sync_encounter_context()
	var previous_report := String(_session.encounter_director.battle_report)
	_session.encounter_director.behavior_for_kind("melee_pursuer").update_tick(_session.encounter_director, enemy, intent)
	_main.adopt_encounter_report(previous_report)


func _start_melee_action(enemy: CombatEnemyState, direction: Vector2 = Vector2.ZERO) -> void:
	_main.sync_encounter_context()
	(_session.encounter_director.behavior_for_kind("melee_pursuer") as MeleePursuerBehavior).start_melee_action(_session.encounter_director, enemy, direction)


func _start_charger_action(enemy: CombatEnemyState, direction: Vector2, action_distance: float) -> bool:
	_main.sync_encounter_context()
	var previous_report := String(_session.encounter_director.battle_report)
	var result: bool = bool((_session.encounter_director.behavior_for_kind("charging_raider") as ChargingRaiderBehavior).start_charger_action(_session.encounter_director, enemy, direction, action_distance))
	_main.adopt_encounter_report(previous_report)
	return result


func _update_charger_tick(enemy: CombatEnemyState, intent: Dictionary = {}) -> void:
	_main.sync_encounter_context()
	var previous_report := String(_session.encounter_director.battle_report)
	_session.encounter_director.behavior_for_kind("charging_raider").update_tick(_session.encounter_director, enemy, intent)
	_main.adopt_encounter_report(previous_report)


func _start_fan_action(enemy: CombatEnemyState, direction: Vector2 = Vector2.ZERO) -> void:
	_main.sync_encounter_context()
	(_session.encounter_director.behavior_for_kind("fan_ranged") as FanRangedBehavior).start_fan_action(_session.encounter_director, enemy, direction)


func _update_fan_tick(enemy: CombatEnemyState, intent: Dictionary = {}) -> void:
	_main.sync_encounter_context()
	var previous_report := String(_session.encounter_director.battle_report)
	_session.encounter_director.behavior_for_kind("fan_ranged").update_tick(_session.encounter_director, enemy, intent)
	_main.adopt_encounter_report(previous_report)


func _commit_normal_enemy_intent(enemy: CombatEnemyState, intent: Dictionary) -> void:
	_main.sync_encounter_context()
	var previous_report := String(_session.encounter_director.battle_report)
	_session.encounter_director.commit_normal_enemy_intent(enemy, intent)
	_main.adopt_encounter_report(previous_report)


func _resolve_hostile_attack(enemy: CombatEnemyState, amount: float, shape_hit: bool) -> void:
	_main.sync_encounter_context()
	var previous_report := String(_session.encounter_director.battle_report)
	_session.encounter_director.resolve_hostile_attack(enemy, amount, shape_hit)
	_main.adopt_encounter_report(previous_report)


func _update_boss_tick(enemy: CombatEnemyState, intent: Dictionary = {}) -> void:
	_main.sync_encounter_context()
	var previous_report := String(_session.encounter_director.battle_report)
	_session.encounter_director.behavior_for_kind("threshold_colossus").update_tick(_session.encounter_director, enemy, intent)
	_main.adopt_encounter_report(previous_report)


func _start_boss_action(enemy: CombatEnemyState, action: String, planned_direction: Vector2 = Vector2.ZERO) -> void:
	_main.sync_encounter_context()
	(_session.encounter_director.behavior_for_kind("threshold_colossus") as ThresholdColossusBehavior).start_boss_action(_session.encounter_director, enemy, action, planned_direction)


func _update_boss_hands(enemy: CombatEnemyState) -> void:
	_main.sync_encounter_context()
	(_session.encounter_director.behavior_for_kind("threshold_colossus") as ThresholdColossusBehavior).update_boss_hands(enemy)


func _boss_shape_contains(shape: Dictionary, point: Vector2) -> bool:
	return CombatQueryScript.shape_contains(shape, point)
