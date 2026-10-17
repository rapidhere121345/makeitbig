class_name CombatSystemRoomPort
extends RefCounted

## Typed room boundary for the legacy player-domain projectile coordinator.
##
## The combat system owns projectile and query state, while the mounted room
## owns target lookup, admission, player-domain bookkeeping and encounter
## reactions.  Production implementations override these methods directly;
## no callback dictionary or string-key ABI crosses this boundary.

func is_ready() -> bool:
	return false


func target_by_id(_entity_id: int) -> CombatEnemyState:
	return null


func aim_candidate(_target: CombatEnemyState) -> Dictionary:
	return {}


func current_model() -> Dictionary:
	return {}


func target_blocked(_target: CombatEnemyState) -> Dictionary:
	return {"ok": false, "error": "combat_room_port_unimplemented:target_blocked"}


func maybe_summon(_target: CombatEnemyState) -> void:
	pass


func remove_target(_target: CombatEnemyState) -> void:
	pass


func cancel_buffered_target(_entity_id: int) -> int:
	return 0


func update_mark() -> void:
	pass


func advance_sequence(_skill_id: String) -> void:
	pass


func reset_sequence() -> void:
	pass


func erase_attack_request(_request_id: int) -> void:
	pass


func consume_first_critical_bonus() -> int:
	return -1


func retain_missed_arrow(_aggregate: BigValue, _ordinary: float) -> bool:
	return false


func take_retained_arrow() -> Dictionary:
	return {"ok": false, "error": "combat_room_port_unimplemented:retained_arrow"}


func is_normal_kernel_projectile(_projectile: Variant) -> bool:
	return false


func is_boss_kernel_projectile(_projectile: Variant) -> bool:
	return false


func sync_kernel_target_record(_projectile: Variant) -> void:
	pass


func sync_boss_kernel_target(_projectile: Variant) -> Variant:
	return null
