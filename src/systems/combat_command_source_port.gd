class_name CombatCommandSourcePort
extends RefCounted

## Typed command factory and targeting boundary for CombatCommandSource.
##
## This is the only authority the detached input source may consult.  The
## production implementation is MainCombatCommandSourcePort; tests may use a
## dedicated typed test double.  A missing implementation fails closed by
## returning the same empty/default values as an unavailable room.

func make_move(_direction: Vector2, _speed_scale: float) -> Dictionary:
	return {}


func make_dodge(_direction: Vector2) -> Dictionary:
	return {}


func make_cast(_ability: String, _target_entity_id: int, _direction: Vector2) -> Dictionary:
	return {}


func make_loot_pickup(_loot_entity_id: String) -> Dictionary:
	return {}


func player_position() -> Vector2:
	return Vector2.ZERO


func player_facing() -> Vector2:
	return Vector2.RIGHT


func locked_targeting_distance() -> float:
	return 0.0


func hunter_mark_range() -> float:
	return 0.0


func nearest_target(_maximum_distance: float) -> Dictionary:
	return {}


func preferred_target() -> Dictionary:
	return {}


func target_by_id(_entity_id: int) -> Dictionary:
	return {}


func pointer_target_entity_id() -> int:
	return 0


func refresh_pointer_lock() -> void:
	pass


func mark_pointer_lost() -> void:
	pass


func mark_pointer_out_of_range() -> void:
	pass


func held_attack_window_open(_target: Dictionary) -> bool:
	return false


func register_attack_source(_sequence: int, _source: String) -> void:
	pass


func clear_input_feedback() -> void:
	pass


func show_assisted_rejection_feedback() -> void:
	pass
