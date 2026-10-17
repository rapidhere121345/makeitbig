class_name PlayerCombatState
extends RefCounted

## Player gameplay storage. Only PlayerCombatRules mutates _values/_timeline.
## Position has no stored alias: every observation reads the room registry.
const Timeline := preload("res://src/systems/player_action_timeline.gd")
const Skill := preload("res://src/systems/ranger_skill_rules.gd")
const Big := preload("res://src/core/big_value.gd")
const CombatStats := preload("res://src/game/combat_stats_snapshot.gd")

var _registry
var _ranger_id := ""
var _room_instance_id := ""
var _world_revision := -1
var _build: Dictionary = {}
var _values: Dictionary = {}
var _timeline := Timeline.new()
var _last_tick := -1
var _combat_stats
var _combat_stats_enabled := false


func reset_for_room(locked_build: Dictionary, actor_registry, ranger_id: String, start_tick: int) -> Dictionary:
	if actor_registry == null or start_tick < 0 or not actor_registry.has_method("actor_snapshot") or actor_registry.actor_snapshot(ranger_id).is_empty():
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
	_combat_stats = null
	_combat_stats_enabled = false
	if locked_build.has("combat_stats"):
		var stats_result: Dictionary = CombatStats.from_resolved_build(locked_build)
		if not bool(stats_result.get("ok", false)):
			return {"ok": false, "error": "invalid_combat_stats:%s" % String(stats_result.get("error", "invalid"))}
		_combat_stats = stats_result.value
		_combat_stats_enabled = true
	_last_tick = start_tick
	_timeline.reset()
	_values = {
		"player_health": maximum, "player_maximum_health": maximum,
		"player_facing": Vector2.RIGHT, "player_last_displacement": Vector2.ZERO,
		"player_velocity": Vector2.ZERO,
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
	return _registry.actor_snapshot(_ranger_id).duplicate(true)


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
	if _combat_stats_enabled:
		slice["combat_stats"] = (_combat_stats as RefCounted).snapshot()
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


func combat_stats_enabled() -> bool:
	return _combat_stats_enabled


func combat_stats_snapshot() -> Dictionary:
	return (_combat_stats as RefCounted).snapshot() if _combat_stats_enabled else {}


func movement_model() -> String:
	return String(_combat_stats.movement_model) if _combat_stats_enabled else "direct"


func uses_accelerated_movement() -> bool:
	return _combat_stats_enabled and movement_model() == "accelerated"


func move_speed() -> float:
	return float(_combat_stats.move_speed) if _combat_stats_enabled else 245.0


func acceleration() -> float:
	return float(_combat_stats.acceleration) if _combat_stats_enabled else 0.0


func player_velocity() -> Vector2:
	var value: Variant = _values.get("player_velocity", Vector2.ZERO)
	return value if value is Vector2 and (value as Vector2).is_finite() else Vector2.ZERO


func dodge_distance() -> float:
	if _combat_stats_enabled:
		return float(_combat_stats.dodge_distance)
	return Skill.DODGE_SPEED * float(Skill.DODGE_DURATION_TICKS) / float(Skill.TICKS_PER_SECOND)


func dodge_duration_ticks() -> int:
	return int(_combat_stats.dodge_duration_ticks) if _combat_stats_enabled else Skill.DODGE_DURATION_TICKS


func attack_cooldown_ticks() -> int:
	return int(_combat_stats.attack_cooldown_ticks) if _combat_stats_enabled else Skill.PIERCING_ARROW_COOLDOWN_TICKS


func scaled_ticks(base: int, capability: String) -> int:
	return maxi(1, int(round(float(base) * (1.0 + clampf(float(_values.talent_capabilities.get(capability, 0.0)), -1.0, 10.0)))))


func dodge_cooldown() -> int:
	var base := int(_combat_stats.dodge_cooldown_ticks) if _combat_stats_enabled else Skill.DODGE_COOLDOWN_TICKS
	return maxi(1, int(round(float(base) * (1.0 - clampf(float(_values.talent_capabilities.get("dodge_cooldown_reduction", 0.0)), 0.0, 0.95)))))
