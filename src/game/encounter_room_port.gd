class_name EncounterRoomPort
extends RefCounted

## Typed room boundary for EncounterDirector dependencies.
##
## The mounted room owns this port. EncounterDirector never receives Callables,
## string-call adapters or a callback dictionary: movement, actor registration,
## collision-class updates, spawn sockets, spatial projection and the typed
## player/outcome rule ports all dispatch through typed virtual calls on one
## room-owned object. Every base method fails closed; a room that forgets to
## override an operation produces an explicit failure value, and the director
## rejects invalid results instead of substituting fallback geometry or a
## silently valid local computation.

## Typed player rule port: apply_damage(tick, amount, source_id,
## source_position) -> {accepted: bool}. Validated when the director binds.
var player_rule_port: RefCounted = null
## Typed combat outcome port: outcome_snapshot() -> {boss_damage, boss_maximum}.
## Validated when the director binds.
var combat_outcome_port: RefCounted = null


func move_enemy(_enemy: CombatEnemyState, _displacement: Vector2) -> Dictionary:
	return {"ok": false, "error": "encounter_room_port_unimplemented:move_enemy"}


func set_enemy_collision_class(_enemy: CombatEnemyState, _collision_class: StringName) -> bool:
	return false


func register_enemy(_enemy: CombatEnemyState) -> Dictionary:
	return {"ok": false, "error": "encounter_room_port_unimplemented:register_enemy"}


func collision_geometry(_padding: float) -> Dictionary:
	return {}


func layout_spawn_offsets(_layout_id: String, _count: int) -> Array[Vector2]:
	return []


func clamp_to_arena(_value: Vector2, _padding: float) -> Vector2:
	return Vector2(INF, INF)


func quantize_position(_value: Vector2) -> Vector2:
	return Vector2(INF, INF)


## Queue a player hazard contact for the next fixed DAMAGE_STATUS phase.
func queue_player_hazard_hit(
	_tick: int,
	_amount: float,
	_source_id: String,
	_source_position: Vector2
) -> Dictionary:
	return {"ok": false, "error": "encounter_room_port_unimplemented:queue_player_hazard_hit"}
