extends "res://src/runtime/combat/combat_system_room_port.gd"

## Typed combat-system composition owned by Main.  The production ranged
## coordinator receives this object once and never receives a callback bag.
## Player-domain retention/sequence state and encounter admission remain room
## owned, while the coordinator only invokes these typed operations.

var _owner: MainArena = null


func bind(owner: MainArena) -> Dictionary:
	if owner == null or not is_instance_valid(owner):
		return {"ok": false, "error": "combat_room_owner_unavailable"}
	if owner.player_combat_rules == null or owner.encounter_director == null:
		return {"ok": false, "error": "combat_room_dependencies_unavailable"}
	_owner = owner
	return {"ok": true, "error": ""}


func is_ready() -> bool:
	return _owner != null and is_instance_valid(_owner)


func target_by_id(entity_id: int) -> CombatEnemyState:
	return _owner._enemy_by_entity_id(entity_id)


func aim_candidate(target: CombatEnemyState) -> Dictionary:
	return _owner._manual_aim_candidate(target)


func current_model() -> Dictionary:
	return _owner._current_model()


func target_blocked(target: CombatEnemyState) -> Dictionary:
	if target == null or _owner.encounter_director == null:
		return {"ok": false, "error": "target_blocked_port_unavailable"}
	return {"ok": true, "error": "", "blocked": _owner.encounter_director.is_target_blocked(target)}


func maybe_summon(target: CombatEnemyState) -> void:
	_owner._maybe_summon_reinforcements(target)


func remove_target(target: CombatEnemyState) -> void:
	_owner._arrows._remove_combat_target(target)


func cancel_buffered_target(entity_id: int) -> int:
	return _owner._arrows._cancel_buffered_target(entity_id)


func update_mark() -> void:
	_owner._refresh_player_mark()


func advance_sequence(skill_id: String) -> void:
	_owner.player_combat_rules.advance_three_skill_sequence(skill_id)


func reset_sequence() -> void:
	_owner.player_combat_rules.reset_three_skill_sequence()


func erase_attack_request(request_id: int) -> void:
	_owner._arrows._erase_attack_request(request_id)


func consume_first_critical_bonus() -> int:
	return _owner.player_combat_rules.consume_first_critical_bonus()


func retain_missed_arrow(aggregate: BigValue, ordinary: float) -> bool:
	_owner.player_combat_rules.retain_missed_arrow(aggregate, ordinary)
	return true


func take_retained_arrow() -> Dictionary:
	return _owner.player_combat_rules.take_retained_arrow()


func is_normal_kernel_projectile(projectile) -> bool:
	return _owner._kernel_reconciler._is_normal_kernel_projectile(projectile)


func is_boss_kernel_projectile(projectile) -> bool:
	return _owner._kernel_reconciler._is_boss_kernel_projectile(projectile)


func sync_kernel_target_record(projectile) -> void:
	_owner._kernel_reconciler._sync_kernel_target_record(projectile)


func sync_boss_kernel_target(projectile) -> Variant:
	return _owner._kernel_reconciler._sync_boss_kernel_target(projectile)
