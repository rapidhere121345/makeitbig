class_name MainCombatCommandSourcePort
extends "res://src/systems/combat_command_source_port.gd"

## Production typed bridge between MainArena and the detached input source.
## The source receives this object instead of a string-keyed callback bag.

var owner: Node2D = null
var adapter: RefCounted = null


func bind(main_owner: Node2D, input_adapter: RefCounted) -> Dictionary:
	if main_owner == null or input_adapter == null:
		owner = null
		adapter = null
		return {"ok": false, "error": "invalid_main_command_source_owner"}
	owner = main_owner
	adapter = input_adapter
	return {"ok": true, "error": ""}


func make_move(direction: Vector2, speed_scale: float) -> Dictionary:
	return owner._move_command(direction, speed_scale) if owner != null else {}


func make_dodge(direction: Vector2) -> Dictionary:
	return owner._dodge_command(direction) if owner != null else {}


func make_cast(ability: String, target_entity_id: int, direction: Vector2) -> Dictionary:
	return owner._cast_command(ability, target_entity_id, direction) if owner != null else {}


func make_loot_pickup(loot_entity_id: String) -> Dictionary:
	return owner._loot_pickup_command(loot_entity_id) if owner != null else {}


func player_position() -> Vector2:
	return adapter.player_position() if adapter != null else Vector2.ZERO


func player_facing() -> Vector2:
	return adapter.player_facing() if adapter != null else Vector2.RIGHT


func locked_targeting_distance() -> float:
	return adapter.targeting_distance() if adapter != null else 0.0


func hunter_mark_range() -> float:
	return adapter.mark_range() if adapter != null else 0.0


func nearest_target(maximum_distance: float) -> Dictionary:
	return adapter.nearest_target(maximum_distance) if adapter != null else {}


func preferred_target() -> Dictionary:
	return adapter.preferred_target() if adapter != null else {}


func target_by_id(entity_id: int) -> Dictionary:
	return adapter.target_by_id(entity_id) if adapter != null else {}


func pointer_target_entity_id() -> int:
	return adapter.pointer_target_id() if adapter != null else 0


func refresh_pointer_lock() -> void:
	if adapter != null:
		adapter.refresh_pointer_lock()


func mark_pointer_lost() -> void:
	if adapter != null:
		adapter.mark_pointer_lost()


func mark_pointer_out_of_range() -> void:
	if adapter != null:
		adapter.mark_pointer_out_of_range()


func held_attack_window_open(target: Dictionary) -> bool:
	return adapter.held_attack_window_open(target) if adapter != null else false


func register_attack_source(sequence: int, source: String) -> void:
	if adapter != null:
		adapter.register_attack_source(sequence, source)


func clear_input_feedback() -> void:
	if adapter != null:
		adapter.clear_feedback()


func show_assisted_rejection_feedback() -> void:
	if adapter != null:
		adapter.show_assisted_rejection()
