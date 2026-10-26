extends "res://src/game/encounter_room_port.gd"

## Typed EncounterDirector composition owned by Main.  The director receives
## this object once at construction and never receives a callback dictionary;
## each operation dispatches directly to the room owner through a typed method.

var _owner: MainArena = null


func bind(owner: MainArena, rules: RefCounted, outcome: RefCounted) -> Dictionary:
	if owner == null or not is_instance_valid(owner):
		return {"ok": false, "error": "encounter_room_owner_unavailable"}
	if rules == null or not rules.has_method("apply_damage"):
		return {"ok": false, "error": "player_rule_port_unavailable"}
	if outcome == null or not outcome.has_method("outcome_snapshot"):
		return {"ok": false, "error": "combat_outcome_port_unavailable"}
	_owner = owner
	player_rule_port = rules
	combat_outcome_port = outcome
	return {"ok": true, "error": ""}


func move_enemy(enemy: CombatEnemyState, displacement: Vector2) -> Dictionary:
	if not _ready():
		return {"ok": false, "error": "encounter_room_owner_unavailable"}
	return _owner._move_enemy_actor(enemy, displacement)


func set_enemy_collision_class(enemy: CombatEnemyState, collision_class: StringName) -> bool:
	return _ready() and _owner._set_enemy_collision_class(enemy, collision_class)


func register_enemy(enemy: CombatEnemyState) -> Dictionary:
	if not _ready():
		return {"ok": false, "error": "encounter_room_owner_unavailable"}
	var accepted: bool = _owner._register_enemy_actor(enemy)
	return {"ok": accepted, "error": "" if accepted else "register_enemy_rejected"}


func collision_geometry(padding: float) -> Dictionary:
	if not _ready():
		return {}
	return _owner._collision_geometry(padding)


func static_blocker_bounds() -> Array[Dictionary]:
	if not _ready():
		return []
	return _owner._static_blocker_bounds()


func layout_spawn_offsets(layout_id: String, count: int) -> Array[Vector2]:
	if not _ready():
		return []
	return _owner._layout_spawn_offsets(layout_id, count)


func clamp_to_arena(value: Vector2, padding: float) -> Vector2:
	if not _ready():
		return Vector2(INF, INF)
	return _owner._clamp_to_arena(value, padding)


func quantize_position(value: Vector2) -> Vector2:
	if not _ready():
		return Vector2(INF, INF)
	return _owner._quantize_position(value)


func queue_player_hazard_hit(tick: int, amount: float, source_id: String, source_position: Vector2) -> Dictionary:
	if not _ready():
		return {"ok": false, "error": "encounter_room_owner_unavailable"}
	return _owner._queue_kernel_player_hit(tick, amount, source_id, source_position)


func _ready() -> bool:
	return _owner != null and is_instance_valid(_owner)
