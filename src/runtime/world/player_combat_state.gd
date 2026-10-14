class_name PlayerCombatState
extends RefCounted

## Player gameplay storage. Only PlayerCombatRules mutates _values/_timeline.
## Position has no stored alias: every observation reads the room registry.
const Timeline := preload("res://src/systems/player_action_timeline.gd")
const Skill := preload("res://src/systems/ranger_skill_rules.gd")
const Big := preload("res://src/core/big_value.gd")

var _registry
var _ranger_id := ""
var _room_instance_id := ""
var _world_revision := -1
var _build: Dictionary = {}
var _values: Dictionary = {}
var _timeline := Timeline.new()
var _last_tick := -1


func reset_for_room(locked_build: Dictionary, actor_registry, ranger_id: String, start_tick: int) -> Dictionary:
	if actor_registry == null or start_tick < 0 or actor_registry.actor(ranger_id) == null:
		return {"ok": false, "error": "player_actor_unavailable"}
	var parameters: Dictionary = locked_build.get("final_parameters", {})
	var maximum := float(parameters.get("max_health", 100.0))
	if not is_finite(maximum) or maximum <= 0.0:
		return {"ok": false, "error": "invalid_player_health"}
	_registry = actor_registry
	_ranger_id = ranger_id
	_room_instance_id = actor_registry.room_instance_id
	_world_revision = actor_registry.world_revision
	_build = locked_build.duplicate(true)
	_last_tick = start_tick
	_timeline.reset()
	_values = {
		"player_health": maximum, "player_maximum_health": maximum,
		"player_facing": Vector2.RIGHT, "player_last_displacement": Vector2.ZERO,
		"attack_cooldown_ticks": 0, "dodge_cooldown_ticks": 0,
		"hunter_mark_cooldown_ticks": 0, "dash_cooldown_ticks": 0,
		"dodge_remaining_ticks": 0, "dash_remaining_ticks": 0,
		"dodge_direction": Vector2.RIGHT, "dash_direction": Vector2.RIGHT,
		"dodge_started_tick": -1, "dash_started_tick": -1,
		"mobility_input_buffer": {}, "attack_origins": {}, "marked_entity_id": 0,
		"hunter_mark_expires_tick": 0, "hunter_mark_candidate_entity_id": 0,
		"hunter_mark_candidate_expires_tick": 0,
		"talent_capabilities": (_build.get("talent_capabilities", {}) as Dictionary).duplicate(true),
		"first_critical_bonus_used": false, "three_skill_sequence_stage": 0,
		"three_skill_bonus_ready": false, "retained_arrow_damage": Big.from_float(0.0),
		"retained_arrow_ordinary_damage": 0.0,
		"last_damage_source_id": "", "last_damage_tick": -1000,
		"last_damage_amount": 0.0, "last_damage_direction": Vector2.ZERO,
	}
	return {"ok": true, "error": ""}


func actor_snapshot() -> Dictionary:
	if _registry == null or _registry.room_instance_id != _room_instance_id or _registry.world_revision != _world_revision:
		return {}
	var actor = _registry.actor(_ranger_id)
	return actor.snapshot().duplicate(true) if actor != null else {}


func position() -> Vector2:
	return actor_snapshot().get("feet_position", Vector2.ZERO)


func snapshot(tick: int) -> Dictionary:
	var slice := _values.duplicate(true)
	# Dictionary.duplicate(true) does not detach RefCounted values.
	if slice.has("retained_arrow_damage"):
		slice["retained_arrow_damage"] = (_values.retained_arrow_damage as Big).duplicate_value()
	slice["player_position"] = position()
	slice["sim_tick"] = tick
	slice["actor_id"] = _ranger_id
	slice["timeline"] = _timeline.snapshot()
	slice["has_timeline"] = true
	slice["action_phase"] = _timeline.phase_at(tick)
	slice["locked_build"] = _build.duplicate(true)
	slice["equipped_skills"] = (_build.get("skills", ["piercing_arrow"]) as Array).duplicate()
	return slice


func equipped_ability_ids() -> Array[String]:
	var result: Array[String] = ["piercing_arrow"]
	var skills: Array = _build.get("skills", [])
	if skills.size() > 1 and String(skills[1]) == "hunter_mark":
		result.append("hunter_mark")
	if skills.size() > 2 and String(skills[2]) == "dash":
		result.append("dash")
	return result


func targeting_distance() -> float:
	return float((_build.get("final_parameters", {}) as Dictionary).get("d", 225.0))


func scaled_ticks(base: int, capability: String) -> int:
	return maxi(1, int(round(float(base) * (1.0 + clampf(float(_values.talent_capabilities.get(capability, 0.0)), -1.0, 10.0)))))


func dodge_cooldown() -> int:
	return maxi(1, int(round(float(Skill.DODGE_COOLDOWN_TICKS) * (1.0 - clampf(float(_values.talent_capabilities.get("dodge_cooldown_reduction", 0.0)), 0.0, 0.95)))))
