class_name EncounterDirector
extends RefCounted

## Room-local encounter authority.
##
## This service owns enemy intent execution, enemy action state, Boss phases,
## hazard timing, and encounter rules. It has no scene-tree or input dependency.
## Cross-domain effects are explicit callbacks supplied by the room authority:
## movement, player damage, event publication, and actor registration.

const CombatQueryScript := preload("res://src/runtime/geometry/combat_query.gd")
const CombatEnemyStateScript := preload("res://src/runtime/world/combat_enemy_state.gd")
const EnemyTacticsScript := preload("res://src/systems/enemy_tactics.gd")
const ArenaGeometryScript := preload("res://src/runtime/geometry/arena_geometry.gd")

const VALID_OBJECTIVE_IDS: Array[String] = ["clear", "hunt_elite", "timed_break"]
const VALID_ENEMY_IDS: Array[String] = ["melee_pursuer", "charging_raider", "fan_ranged"]
const VALID_HAZARD_IDS: Array[String] = ["exposed_ground_zone", "moving_fireline"]
const VALID_ELITE_RULE_IDS: Array[String] = ["periodic_barrier", "summon_reinforcements"]
const REQUIRED_ENCOUNTER_FIELDS: Array[String] = [
	"layout_id", "objective_id", "hazard_ids", "enemy_ids", "elite_rule_ids", "boss_id", "drop_tags",
]
const REQUIRED_ROOM_FIELDS: Array[String] = [
	"room_id", "layout_id", "objective_id", "hazard_ids", "enemy_ids", "elite_rule_ids", "boss_id", "drop_tags",
]

const SIM_STEP_SECONDS: float = 1.0 / 30.0
const MELEE_MOVE_SPEED: float = 72.0
const CHARGER_MOVE_SPEED: float = 62.0
const FAN_MOVE_SPEED: float = 58.0
const MELEE_WINDUP_TICKS: int = 5
const MELEE_ACTIVE_TICKS: int = 1
const MELEE_RECOVERY_TICKS: int = 11
const CHARGE_WINDUP_TICKS: int = 18
const CHARGE_ACTIVE_TICKS: int = 10
const CHARGE_RECOVERY_TICKS: int = 22
const FAN_WINDUP_TICKS: int = 21
const FAN_ACTIVE_TICKS: int = 1
const FAN_RECOVERY_TICKS: int = 28
const BOSS_TRANSITION_TICKS: int = 30
const BOSS_WINDUP_TICKS: int = 24
const BOSS_ACTIVE_TICKS: int = 1
const BOSS_RECOVERY_TICKS: int = 24
const HAZARD_WARNING_TICKS: int = 30
const HAZARD_ACTIVE_TICKS: int = 15
const HAZARD_CYCLE_TICKS: int = 90
const ELITE_BARRIER_PERIOD_TICKS: int = 60
const ELITE_BARRIER_ACTIVE_TICKS: int = 20
const TIMED_BREAK_BONUS_TICKS: int = 900
const EARLY_NORMAL_HEALTH_BY_KIND := {
	"melee_pursuer": 720.0,
	"charging_raider": 420.0,
	"fan_ranged": 240.0,
}
const EARLY_ELITE_HEALTH_BY_KIND := {
	"melee_pursuer": 1600.0,
	"charging_raider": 1300.0,
	"fan_ranged": 1000.0,
}

var tick: int = 0
var player_position := Vector2.ZERO
var arena_rect := Rect2()
var room_id := ""
var layout_id := "rectangle_arena"
var objective_id := "clear"
var enemies: Array[CombatEnemyState] = []
var boss: CombatEnemyState
var hazard_states: Array[Dictionary] = []
var elite_rule_ids: Array[String] = []
var elite_entity_id: int = 0
var elite_barrier_active: bool = false
var reinforcements_summoned: bool = false
var timed_bonus_available: bool = true
var next_entity_id: int = 1
var next_enemy_action_instance_id: int = 1
var combat_outcome_port: RefCounted
var boss_damage: BigValue:
	get:
		return combat_outcome_port.outcome_snapshot().boss_damage
var boss_maximum: BigValue:
	get:
		return combat_outcome_port.outcome_snapshot().boss_maximum
var battle_report := ""
var combat_event_stream
var enemy_tactics = EnemyTacticsScript.new()

var move_enemy_callback: Callable
var player_rule_port: RefCounted
var register_enemy_callback: Callable
var walkable_geometry_callback: Callable
var collision_geometry_callback: Callable
var layout_spawn_offsets_callback: Callable
var clamp_to_arena_callback: Callable
var quantize_position_callback: Callable
var _configured := false


static func validate_room(room: Variant, room_catalog: Variant) -> String:
	if not room is Dictionary:
		return "invalid_room_fields"
	var room_data: Dictionary = (room as Dictionary).duplicate(true)
	if not room_data.has("room_id") and room_data.get("id", null) is String:
		room_data["room_id"] = String(room_data.get("id"))
	## Static validation is also used by isolated encounter tests and by room
	## planning before an instance identity has been assigned. Spawn assembly
	## remains stricter and requires room_id through _validate_spawn_room().
	for field: String in REQUIRED_ENCOUNTER_FIELDS:
		if not room_data.has(field):
			return "missing_room_field:%s" % field
	var type_error := _validate_field_types(room_data)
	if not type_error.is_empty():
		return type_error
	if room_data.has("room_id"):
		var room_id_value: Variant = room_data.get("room_id")
		if not room_id_value is String or String(room_id_value).strip_edges().is_empty():
			return "invalid_room_id"
	if room_catalog == null or not room_catalog.has_method("resolve"):
		return "room_catalog_unavailable"
	var resolved: Variant = room_catalog.resolve(room_data)
	if not resolved is Dictionary or not bool((resolved as Dictionary).get("ok", false)):
		return String((resolved as Dictionary).get("error", "unknown_layout_id")) if resolved is Dictionary else "unknown_layout_id"
	var objective := String(room_data.get("objective_id", room_data.get("objective", "")))
	if objective not in VALID_OBJECTIVE_IDS:
		return "unknown_objective_id"
	for field: String in ["enemy_ids", "hazard_ids", "elite_rule_ids", "drop_tags"]:
		if not room_data.get(field, null) is Array:
			return "invalid_room_fields"
	for value: Variant in room_data.get("enemy_ids", []):
		if String(value) not in VALID_ENEMY_IDS:
			return "unknown_enemy_id"
	var boss_id := String(room_data.get("boss_id", ""))
	if not boss_id.is_empty() and boss_id != "threshold_colossus":
		return "unknown_boss_id"
	for value: Variant in room_data.get("hazard_ids", []):
		if String(value) not in VALID_HAZARD_IDS:
			return "unknown_hazard_id"
	for value: Variant in room_data.get("elite_rule_ids", []):
		if String(value) not in VALID_ELITE_RULE_IDS:
			return "unknown_elite_rule_id"
	if (room_data.get("enemy_ids", []) as Array).is_empty() and String(room_data.get("boss_id", "")).is_empty():
		return "empty_encounter"
	return ""


func configure(callbacks: Dictionary) -> Dictionary:
	for key: String in ["move_enemy", "register_enemy", "walkable_geometry", "layout_spawn_offsets", "clamp_to_arena", "quantize_position"]:
		var callback_value: Variant = callbacks.get(key, Callable())
		if not callback_value is Callable or not (callback_value as Callable).is_valid():
			return {"ok": false, "error": "missing_callback:%s" % key}
	move_enemy_callback = callbacks.get("move_enemy", Callable())
	var port: Variant = callbacks.get("player_rule_port")
	if not port is RefCounted or not port.has_method("apply_damage"):
		return {"ok": false, "error": "player_rule_port_unavailable"}
	var outcome_port: Variant = callbacks.get("combat_outcome_port")
	if not outcome_port is RefCounted or not outcome_port.has_method("outcome_snapshot"):
		return {"ok": false, "error": "combat_outcome_port_unavailable"}
	player_rule_port = port
	combat_outcome_port = outcome_port
	register_enemy_callback = callbacks.get("register_enemy", Callable())
	walkable_geometry_callback = callbacks.get("walkable_geometry", Callable())
	if callbacks.has("collision_geometry"):
		var collision_geometry_value: Variant = callbacks.get("collision_geometry")
		if not collision_geometry_value is Callable or not (collision_geometry_value as Callable).is_valid():
			return {"ok": false, "error": "invalid_callback:collision_geometry"}
		collision_geometry_callback = collision_geometry_value as Callable
	else:
		collision_geometry_callback = Callable()
	layout_spawn_offsets_callback = callbacks.get("layout_spawn_offsets", Callable())
	clamp_to_arena_callback = callbacks.get("clamp_to_arena", Callable())
	quantize_position_callback = callbacks.get("quantize_position", Callable())
	_configured = true
	return {"ok": true, "error": ""}


func set_context(
	new_tick: int,
	new_player_position: Vector2,
	new_arena_rect: Rect2,
	event_stream,
	new_layout_id: String,
	new_objective_id: String
) -> void:
	tick = maxi(0, new_tick)
	player_position = new_player_position
	arena_rect = new_arena_rect
	combat_event_stream = event_stream
	layout_id = new_layout_id
	objective_id = new_objective_id


func spawn_wave(room: Dictionary, center: Vector2) -> Dictionary:
	if not _configured:
		return {"ok": false, "error": "encounter_not_configured"}
	if not center.is_finite():
		return {"ok": false, "error": "invalid_encounter_origin"}
	var type_error := _validate_field_types(room)
	if not type_error.is_empty():
		return {"ok": false, "error": type_error}
	enemies.clear()
	boss = null
	hazard_states.clear()
	elite_rule_ids.clear()
	elite_entity_id = 0
	elite_barrier_active = false
	reinforcements_summoned = false
	timed_bonus_available = true
	next_entity_id = 1
	next_enemy_action_instance_id = 1
	if room.is_empty():
		return {"ok": false, "error": "missing_room_definition"}
	room = room.duplicate(true)
	room_id = String(room.get("room_id", room.get("id", "")))
	if not room.has("room_id") and not room_id.is_empty():
		room["room_id"] = room_id
	layout_id = String(room.get("layout_id", room.get("layout", "")))
	objective_id = String(room.get("objective_id", room.get("objective", "")))
	var local_room_error := _validate_spawn_room(room)
	if not local_room_error.is_empty():
		return {"ok": false, "error": local_room_error}
	var roster_value: Variant = room.get("enemy_ids", [])
	var boss_id := String(room.get("boss_id", ""))
	if not roster_value is Array:
		return {"ok": false, "error": "invalid_enemy_roster"}
	var roster: Array = roster_value
	var required_offsets := roster.size() + (1 if not boss_id.is_empty() else 0)
	var room_offsets := _layout_spawn_offsets(layout_id, required_offsets)
	if not layout_spawn_offsets_callback.is_valid():
		return {"ok": false, "error": "spawn_socket_callback_unavailable"}
	if room_offsets.size() != required_offsets:
		return {"ok": false, "error": "insufficient_spawn_offsets"}
	for offset: Vector2 in room_offsets:
		if not offset.is_finite():
			return {"ok": false, "error": "invalid_spawn_socket"}
	for index in roster.size():
		var kind_id := String(roster[index])
		if not EARLY_NORMAL_HEALTH_BY_KIND.has(kind_id):
			return {"ok": false, "error": "unknown_enemy_id"}
		enemies.append(CombatEnemyStateScript.new(center + room_offsets[index], float(EARLY_NORMAL_HEALTH_BY_KIND[kind_id]), false, index + 1, kind_id))
	next_entity_id = roster.size() + 1
	if boss_id == "threshold_colossus":
		boss = CombatEnemyStateScript.new(center + room_offsets[roster.size()], 1200.0, true, next_entity_id, boss_id)
		next_entity_id += 1
		boss.core_vulnerable = true
		enemies.append(boss)
	elif not boss_id.is_empty():
		return {"ok": false, "error": "unknown_boss_id"}
	for value in room.get("elite_rule_ids", []):
		elite_rule_ids.append(String(value))
	if objective_id == "hunt_elite" and not enemies.is_empty() and not enemies[0].is_boss:
		elite_entity_id = enemies[0].entity_id
		if not EARLY_ELITE_HEALTH_BY_KIND.has(enemies[0].kind_id):
			return {"ok": false, "error": "unknown_elite_enemy_id"}
		var elite_health := float(EARLY_ELITE_HEALTH_BY_KIND[enemies[0].kind_id])
		enemies[0].health = elite_health
		enemies[0].maximum_health = elite_health
	for value in room.get("hazard_ids", []):
		hazard_states.append(new_hazard_state(String(value), center))
	update_room_rules_tick()
	return {
		"ok": true,
		"room_id": room_id,
		"layout_id": layout_id,
		"objective_id": objective_id,
		"enemies": enemies,
		"boss": boss,
		"hazard_states": hazard_states,
		"elite_rule_ids": elite_rule_ids,
	}


func _arena_rect() -> Rect2:
	return arena_rect


func _walkable_geometry(padding: float) -> Dictionary:
	if not walkable_geometry_callback.is_valid():
		return {}
	var result: Variant = walkable_geometry_callback.call(padding)
	return result if result is Dictionary else {}


func _collision_geometry(padding: float) -> Dictionary:
	if collision_geometry_callback.is_valid():
		var result: Variant = collision_geometry_callback.call(padding)
		return result if result is Dictionary else {}
	return _walkable_geometry(padding)


func _quantize_position(value: Vector2) -> Vector2:
	if quantize_position_callback.is_valid():
		return Vector2(quantize_position_callback.call(value))
	return Vector2(snappedf(value.x, 0.001), snappedf(value.y, 0.001))


func _clamp_to_arena(value: Vector2, padding: float) -> Vector2:
	if collision_geometry_callback.is_valid():
		var geometry := _collision_geometry(padding)
		var projected := ArenaGeometryScript.project(value, geometry)
		if bool(projected.get("ok", false)):
			return Vector2(projected["position"])
		return value
	if clamp_to_arena_callback.is_valid():
		return Vector2(clamp_to_arena_callback.call(value, padding))
	return value.clamp(arena_rect.position + Vector2.ONE * padding, arena_rect.end - Vector2.ONE * padding)


func _move_enemy_actor(enemy: CombatEnemyState, displacement: Vector2) -> Dictionary:
	if not move_enemy_callback.is_valid():
		return {"ok": false, "error": "move_callback_unavailable"}
	var result: Variant = move_enemy_callback.call(enemy, displacement)
	return result if result is Dictionary else {"ok": false, "error": "invalid_move_callback_result"}


func _damage_player(amount: float, source_id: String, source_position: Vector2) -> bool:
	var receipt: Dictionary = player_rule_port.apply_damage(tick, amount, source_id, source_position)
	return bool(receipt.get("accepted", false))


func is_target_blocked(target: CombatEnemyState) -> bool:
	return target != null and target.entity_id == elite_entity_id and elite_barrier_active


func is_targetable(target: CombatEnemyState) -> bool:
	return target != null and target.health > 0.0 and not is_target_blocked(target)


func _register_enemy_actor(enemy: CombatEnemyState) -> bool:
	if not register_enemy_callback.is_valid():
		return false
	return bool(register_enemy_callback.call(enemy))


func _layout_spawn_offsets(id: String, count: int) -> Array[Vector2]:
	if not layout_spawn_offsets_callback.is_valid():
		return []
	var value: Variant = layout_spawn_offsets_callback.call(id, count)
	var result: Array[Vector2] = []
	if value is Array:
		for point: Variant in value:
			if point is Vector2:
				result.append(point)
	return result


func _validate_spawn_room(room: Dictionary) -> String:
	for field: String in REQUIRED_ROOM_FIELDS:
		if not room.has(field):
			return "missing_room_field:%s" % field
	if room_id.strip_edges().is_empty():
		return "invalid_room_id"
	if layout_id.strip_edges().is_empty():
		return "missing_layout_id"
	if ArenaGeometryScript.expected_native_kind_for_layout(layout_id).is_empty():
		return "unknown_layout_id"
	if objective_id not in VALID_OBJECTIVE_IDS:
		return "unknown_objective_id"
	for field: String in ["enemy_ids", "hazard_ids", "elite_rule_ids", "drop_tags"]:
		if not room.get(field, null) is Array:
			return "invalid_room_fields"
	for value: Variant in room.get("enemy_ids", []):
		if String(value) not in VALID_ENEMY_IDS:
			return "unknown_enemy_id"
	for value: Variant in room.get("hazard_ids", []):
		if String(value) not in VALID_HAZARD_IDS:
			return "unknown_hazard_id"
	for value: Variant in room.get("elite_rule_ids", []):
		if String(value) not in VALID_ELITE_RULE_IDS:
			return "unknown_elite_rule_id"
	var boss_id := String(room.get("boss_id", ""))
	if not boss_id.is_empty() and boss_id != "threshold_colossus":
		return "unknown_boss_id"
	if (room.get("enemy_ids", []) as Array).is_empty() and boss_id.is_empty():
		return "empty_encounter"
	return ""


static func _validate_field_types(room: Dictionary) -> String:
	for field: String in ["room_id", "id", "layout_id", "objective_id", "boss_id"]:
		if room.has(field) and not room[field] is String:
			return "invalid_room_field:%s" % field
	for field: String in ["enemy_ids", "hazard_ids", "elite_rule_ids", "drop_tags"]:
		if not room.has(field):
			continue
		if not room[field] is Array:
			return "invalid_room_fields"
		for value: Variant in room[field]:
			if not value is String or String(value).strip_edges().is_empty():
				return "invalid_room_field:%s" % field
	return ""


func update_tick() -> void:
	refresh_hazard_states_tick()
	var ordered: Array[CombatEnemyState] = enemies.duplicate()
	ordered.sort_custom(func(left: CombatEnemyState, right: CombatEnemyState) -> bool: return left.entity_id < right.entity_id)
	for enemy: CombatEnemyState in ordered:
		_finish_enemy_recovery_if_due(enemy)
	var planned: Dictionary = enemy_tactics.plan(enemy_tactics_snapshot())
	var intents := {}
	if bool(planned.get("ok", false)):
		for intent: Dictionary in planned.get("intents", []):
			intents[int(intent.get("entity_id", 0))] = intent
	else:
		battle_report = "敌人战术快照被拒绝：%s" % String(planned.get("error", "unknown"))
	for enemy: CombatEnemyState in ordered:
		_update_enemy_tick(enemy, intents.get(enemy.entity_id, {}))
	_maybe_summon_reinforcements(_enemy_by_entity_id(elite_entity_id))


func enemy_tactics_snapshot() -> Dictionary:
	var geometry := _collision_geometry(16.0)
	var actors: Array[Dictionary] = []
	for enemy: CombatEnemyState in enemies:
		var planning_state := enemy.action_state
		if planning_state == "none":
			planning_state = "range_hold" if enemy.kind_id == "fan_ranged" and enemy.tactic_state == "range_hold" else "idle"
		var actor := {
			"entity_id": enemy.entity_id,
			"kind_id": enemy.kind_id,
			"position": enemy.position,
			"action_state": planning_state,
			"health": enemy.health,
			"facing": enemy.facing if enemy.facing != Vector2.ZERO else Vector2.RIGHT,
			"next_action_ready_tick": enemy.next_action_ready_tick,
		}
		if enemy.is_boss:
			actor["phase"] = enemy.phase_id
			actor["next_action_index"] = enemy.next_action_index
		actors.append(actor)
	return {
		"snapshot_version": EnemyTacticsScript.SNAPSHOT_VERSION,
		"tick": tick,
		"player_position": player_position,
		"arena_rect": geometry.bounds,
		"walkable_geometry": geometry,
		"enemies": actors,
		"hazards": enemy_tactics_hazards(),
	}


func enemy_tactics_hazards() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for hazard: Dictionary in hazard_states:
		var phase := String(hazard.get("phase", ""))
		if phase not in ["warning", "active"]:
			continue
		var shape: Dictionary
		if String(hazard.get("id", "")) == "moving_fireline":
			var origin: Vector2 = hazard.get("origin", Vector2.ZERO)
			shape = {"shape": "rect", "rect": Rect2(origin - Vector2(float(hazard.get("width", 0.0)) * 0.5, 0.0), Vector2(float(hazard.get("width", 0.0)), float(hazard.get("length", 0.0))))}
		else:
			shape = {"shape": "circle", "center": hazard.get("origin", Vector2.ZERO), "radius": float(hazard.get("radius", 0.0))}
		result.append({("active_geometry" if phase == "active" else "warning_geometry"): shape})
	return result


func _maybe_summon_reinforcements(elite: CombatEnemyState) -> void:
	if elite == null or elite.entity_id != elite_entity_id:
		return
	if "summon_reinforcements" not in elite_rule_ids or reinforcements_summoned:
		return
	if elite.health > elite.maximum_health * 0.5:
		return
	reinforcements_summoned = true
	var reinforcement_id := _allocate_entity_id()
	var reinforcement_offsets := _layout_spawn_offsets(layout_id, reinforcement_id)
	if reinforcement_offsets.size() < reinforcement_id:
		reinforcements_summoned = false
		battle_report = "reinforcement_spawn_sockets_missing:%d" % reinforcement_id
		return
	var spawn := reinforcement_offsets[reinforcement_id - 1]
	if not spawn.is_finite():
		reinforcements_summoned = false
		battle_report = "reinforcement_spawn_socket_invalid:%d" % reinforcement_id
		return
	var reinforcement := CombatEnemyStateScript.new(_arena_rect().get_center() + spawn, float(EARLY_NORMAL_HEALTH_BY_KIND["melee_pursuer"]), false, reinforcement_id, "melee_pursuer")
	enemies.append(reinforcement)
	if register_enemy_callback.is_valid() and not _register_enemy_actor(reinforcement):
		push_error("reinforcement_actor_registration_failed:%d" % reinforcement_id)


func update_room_rules_tick() -> void:
	elite_barrier_active = "periodic_barrier" in elite_rule_ids and elite_entity_id > 0 and tick % ELITE_BARRIER_PERIOD_TICKS < ELITE_BARRIER_ACTIVE_TICKS
	if objective_id == "timed_break" and tick > TIMED_BREAK_BONUS_TICKS:
		timed_bonus_available = false


func update_hazards_tick() -> void:
	refresh_hazard_states_tick()
	resolve_hazard_hits_tick()


func refresh_hazard_states_tick() -> void:
	for state in hazard_states:
		var cycle := tick / HAZARD_CYCLE_TICKS
		var cycle_tick := tick % HAZARD_CYCLE_TICKS
		state["cycle"] = cycle
		state["cycle_tick"] = cycle_tick
		state["phase"] = "warning" if cycle_tick < HAZARD_WARNING_TICKS else ("active" if cycle_tick < HAZARD_WARNING_TICKS + HAZARD_ACTIVE_TICKS else "recovery")
		if String(state.id) == "moving_fireline":
			var rect := _arena_rect()
			var progress := float(cycle_tick) / float(HAZARD_CYCLE_TICKS - 1)
			state["origin"] = _quantize_position(Vector2(lerpf(rect.position.x, rect.end.x, progress), rect.position.y))


func resolve_hazard_hits_tick() -> void:
	for state in hazard_states:
		var cycle := int(state.get("cycle", tick / HAZARD_CYCLE_TICKS))
		if state.phase == "active" and int(state.last_hit_cycle) != cycle and hazard_contains(state, player_position):
			state["last_hit_cycle"] = cycle
			var source_id := "hazard/%s" % String(state.id)
			var applied := _damage_player(9.0 if String(state.id) == "moving_fireline" else 7.0, source_id, state.origin)
			combat_event_stream.emit(tick, "attack_resolved", {
				"action_instance_id": 0,
				"source_id": source_id,
				"target_id": "ranger",
				"outcome": "damage" if applied else "avoided",
				"contact_point": player_position,
			})


func new_hazard_state(id: String, center: Vector2) -> Dictionary:
	if id == "moving_fireline":
		return {"id": id, "phase": "warning", "cycle": 0, "cycle_tick": 0, "last_hit_cycle": -1, "origin": _arena_rect().position, "direction": Vector2.DOWN, "length": _arena_rect().size.y, "width": 34.0, "radius": 0.0}
	return {"id": id, "phase": "warning", "cycle": 0, "cycle_tick": 0, "last_hit_cycle": -1, "origin": center + Vector2(70.0, 0.0), "direction": Vector2.ZERO, "length": 0.0, "width": 0.0, "radius": 82.0}


func hazard_contains(state: Dictionary, point: Vector2) -> bool:
	if String(state.id) == "moving_fireline":
		return CombatQueryScript.lane_contains(point, state.origin, state.direction, float(state.length), float(state.width))
	return point.distance_to(state.origin) <= float(state.radius)


func _enemy_by_entity_id(id: int) -> CombatEnemyState:
	for enemy: CombatEnemyState in enemies:
		if enemy.entity_id == id:
			return enemy
	return null


func _allocate_entity_id() -> int:
	var result := next_entity_id
	next_entity_id += 1
	return result


func _update_enemy_tick(enemy: CombatEnemyState, intent: Dictionary = {}) -> void:
	if enemy.health <= 0.0:
		return
	if enemy.is_boss:
		_update_boss_tick(enemy, intent)
		return
	match enemy.kind_id:
		"charging_raider":
			_update_charger_tick(enemy, intent)
		"fan_ranged":
			_update_fan_tick(enemy, intent)
		_:
			_update_melee_tick(enemy, intent)


func _advance_action_state(enemy: CombatEnemyState, active_ticks: int, recovery_ticks: int) -> bool:
	if enemy.action_state == "windup" and tick >= enemy.impact_tick:
		enemy.action_state = "active"
		enemy.state_started_tick = tick
		enemy.state_ends_tick = tick + active_ticks
		return true
	if enemy.action_state == "active" and tick >= enemy.state_ends_tick:
		enemy.action_state = "recovery"
		enemy.state_started_tick = tick
		enemy.state_ends_tick = tick + recovery_ticks
		return true
	if _finish_enemy_recovery_if_due(enemy):
		return true
	return false


func _finish_enemy_recovery_if_due(enemy: CombatEnemyState) -> bool:
	if enemy.action_state != "recovery" or tick < enemy.state_ends_tick:
		return false
	var finished_action := enemy.action_id
	combat_event_stream.emit(tick, "action_ended", {
		"action_instance_id": enemy.action_instance_id,
		"actor_id": "enemy/%d" % enemy.entity_id,
		"action_id": finished_action,
	})
	enemy.action_state = "none"
	enemy.action_id = "none"
	enemy.action_instance_id = 0
	enemy.state_started_tick = tick
	enemy.state_ends_tick = tick
	enemy.impact_tick = -1
	enemy.impact_resolved = false
	enemy.target_shape = {}
	enemy.next_action_ready_tick = tick + _enemy_breath_ticks(enemy.kind_id)
	return true


func _begin_action(enemy: CombatEnemyState, action_id: String, windup_ticks: int) -> void:
	enemy.action_id = action_id
	enemy.action_instance_id = next_enemy_action_instance_id
	next_enemy_action_instance_id += 1
	enemy.action_state = "windup"
	enemy.motion_state = "idle"
	enemy.state_started_tick = tick
	enemy.impact_tick = tick + windup_ticks
	enemy.state_ends_tick = enemy.impact_tick
	enemy.impact_resolved = false


func _emit_enemy_action_accepted(enemy: CombatEnemyState) -> void:
	combat_event_stream.emit(tick, "action_accepted", {
		"action_instance_id": enemy.action_instance_id,
		"actor_id": "enemy/%d" % enemy.entity_id,
		"action_id": enemy.action_id,
		"locked_origin": enemy.position,
		"locked_direction": enemy.facing,
		"impact_tick": enemy.impact_tick,
		"target_shape": enemy.target_shape.duplicate(true),
	})


func _enemy_breath_ticks(kind_id: String) -> int:
	match kind_id:
		"melee_pursuer": return 4
		"charging_raider": return 8
		"fan_ranged": return 10
	return 0


func _intent_for_enemy(enemy: CombatEnemyState) -> Dictionary:
	var planned: Dictionary = enemy_tactics.plan(enemy_tactics_snapshot())
	if not bool(planned.get("ok", false)):
		return {}
	for intent: Dictionary in planned.get("intents", []):
		if int(intent.get("entity_id", 0)) == enemy.entity_id:
			return intent
	return {}


func _update_melee_tick(enemy: CombatEnemyState, intent: Dictionary = {}) -> void:
	var previous_state := enemy.action_state
	_advance_action_state(enemy, MELEE_ACTIVE_TICKS, MELEE_RECOVERY_TICKS)
	if enemy.action_state == "active" and not enemy.impact_resolved:
		enemy.impact_resolved = true
		_resolve_hostile_attack(enemy, 5.0, CombatQueryScript.shape_contains(enemy.target_shape, player_position))
	if previous_state == "active" and enemy.action_state == "recovery" and not enemy.impact_resolved:
		enemy.impact_resolved = true
		_resolve_hostile_attack(enemy, 5.0, false)
	if enemy.action_state == "none":
		_commit_normal_enemy_intent(enemy, intent if not intent.is_empty() else _intent_for_enemy(enemy))
	else:
		enemy.motion_state = "idle"


func _start_melee_action(enemy: CombatEnemyState, direction: Vector2 = Vector2.ZERO) -> void:
	_begin_action(enemy, "contact", MELEE_WINDUP_TICKS)
	enemy.facing = direction.normalized() if direction != Vector2.ZERO else enemy.position.direction_to(player_position)
	if enemy.facing == Vector2.ZERO:
		enemy.facing = Vector2.RIGHT
	enemy.target_shape = {"type": "circle", "origin": enemy.position, "radius": EnemyTacticsScript.MELEE_ATTACK_RANGE}
	_emit_enemy_action_accepted(enemy)


func _start_charger_action(enemy: CombatEnemyState, direction: Vector2, action_distance: float) -> bool:
	if not is_finite(direction.x) or not is_finite(direction.y) or direction.is_zero_approx() or not is_finite(action_distance) or action_distance <= 0.0:
		return false
	_begin_action(enemy, "charge", CHARGE_WINDUP_TICKS)
	enemy.charge_origin = enemy.position
	enemy.charge_direction = direction.normalized()
	enemy.facing = enemy.charge_direction
	enemy.charge_length = action_distance
	enemy.charge_width = EnemyTacticsScript.CHARGER_CONTACT_RADIUS * 2.0
	enemy.target_shape = {"type": "lane", "origin": enemy.charge_origin, "direction": enemy.charge_direction, "length": enemy.charge_length, "width": enemy.charge_width}
	_emit_enemy_action_accepted(enemy)
	return true


func _update_charger_tick(enemy: CombatEnemyState, intent: Dictionary = {}) -> void:
	var previous_state := enemy.action_state
	_advance_action_state(enemy, CHARGE_ACTIVE_TICKS, CHARGE_RECOVERY_TICKS)
	if enemy.action_state == "active":
		enemy.motion_state = "moving"
		var before := enemy.position
		var step := enemy.charge_length / float(CHARGE_ACTIVE_TICKS)
		var movement_result := _move_enemy_actor(enemy, enemy.charge_direction * step)
		if not bool(movement_result.get("ok", false)):
			enemy.motion_state = "idle"
		if not enemy.impact_resolved:
			var contact := CombatQueryScript.distance_to_segment(player_position, before, enemy.position) <= EnemyTacticsScript.CHARGER_CONTACT_RADIUS
			if contact:
				enemy.impact_resolved = true
				_resolve_hostile_attack(enemy, 11.0, true)
	elif previous_state == "active" and enemy.action_state == "recovery" and not enemy.impact_resolved:
		enemy.impact_resolved = true
		_resolve_hostile_attack(enemy, 11.0, false)
	elif enemy.action_state == "none":
		_commit_normal_enemy_intent(enemy, intent if not intent.is_empty() else _intent_for_enemy(enemy))
	else:
		enemy.motion_state = "idle"


func _start_fan_action(enemy: CombatEnemyState, direction: Vector2 = Vector2.ZERO) -> void:
	_begin_action(enemy, "fan", FAN_WINDUP_TICKS)
	var fan_direction := direction.normalized() if direction != Vector2.ZERO else enemy.position.direction_to(player_position)
	if fan_direction == Vector2.ZERO:
		fan_direction = enemy.facing
	enemy.target_shape = EnemyTacticsScript.fan_attack_shape(enemy.position, fan_direction)
	## Keep the compact action-state mirrors available to existing diagnostics and
	## semantic hashing. Presentation and hit resolution below read target_shape.
	enemy.fan_origin = enemy.target_shape["origin"]
	enemy.fan_direction = enemy.target_shape["direction"]
	enemy.fan_half_angle = enemy.target_shape["half_angle"]
	enemy.fan_radius = enemy.target_shape["radius"]
	enemy.facing = enemy.fan_direction
	_emit_enemy_action_accepted(enemy)


func _update_fan_tick(enemy: CombatEnemyState, intent: Dictionary = {}) -> void:
	var previous_state := enemy.action_state
	_advance_action_state(enemy, FAN_ACTIVE_TICKS, FAN_RECOVERY_TICKS)
	if enemy.action_state == "active" and not enemy.impact_resolved:
		enemy.impact_resolved = true
		_resolve_hostile_attack(enemy, 8.0, EnemyTacticsScript.fan_attack_contains(enemy.target_shape, player_position))
	if previous_state == "active" and enemy.action_state == "recovery" and not enemy.impact_resolved:
		enemy.impact_resolved = true
		_resolve_hostile_attack(enemy, 8.0, false)
	if enemy.action_state == "none":
		_commit_normal_enemy_intent(enemy, intent if not intent.is_empty() else _intent_for_enemy(enemy))
	else:
		enemy.motion_state = "idle"


func _commit_normal_enemy_intent(enemy: CombatEnemyState, intent: Dictionary) -> void:
	if intent.is_empty():
		enemy.motion_state = "idle"
		enemy.tactic_reason = "no_intent"
		return
	enemy.tactic_reason = String(intent.get("reason", "unknown"))
	var action := String(intent.get("request_action", ""))
	var action_direction_value: Variant = intent.get("action_direction", Vector2.ZERO)
	var action_direction := Vector2(action_direction_value) if action_direction_value is Vector2 else Vector2.ZERO
	match action:
		"melee_attack":
			_start_melee_action(enemy, action_direction)
			return
		"charge":
			var action_distance_value: Variant = intent.get("action_distance", null)
			var valid_direction := is_finite(action_direction.x) and is_finite(action_direction.y) and not action_direction.is_zero_approx()
			var valid_distance := (action_distance_value is int or action_distance_value is float) and not (action_distance_value is bool) and is_finite(float(action_distance_value)) and float(action_distance_value) > 0.0
			if not valid_direction or not valid_distance or not _start_charger_action(enemy, action_direction, float(action_distance_value)):
				enemy.motion_state = "idle"
				enemy.tactic_reason = "invalid_charge_execution"
			return
		"fan_attack":
			_start_fan_action(enemy, action_direction)
			return
	var direction: Vector2 = intent.get("move_direction", Vector2.ZERO)
	var speed_scale := clampf(float(intent.get("speed_scale", 0.0)), 0.0, 1.0)
	if direction == Vector2.ZERO or speed_scale <= 0.0:
		enemy.motion_state = "idle"
		return
	direction = direction.normalized()
	var base_speed := MELEE_MOVE_SPEED
	if enemy.kind_id == "charging_raider":
		base_speed = CHARGER_MOVE_SPEED
	elif enemy.kind_id == "fan_ranged":
		base_speed = FAN_MOVE_SPEED
	var before := enemy.position
	var movement_result := _move_enemy_actor(enemy, direction * base_speed * speed_scale * SIM_STEP_SECONDS)
	if not bool(movement_result.get("ok", false)):
		enemy.motion_state = "idle"
		return
	enemy.motion_state = "moving" if enemy.position != before else "idle"
	if enemy.kind_id == "fan_ranged":
		enemy.tactic_state = "range_hold" if enemy.tactic_reason in ["fan_strafe_hold", "fan_legal_band"] else "locomotion"
		enemy.facing = enemy.position.direction_to(player_position) if enemy.position != player_position else enemy.facing
	else:
		enemy.facing = direction


func _resolve_hostile_attack(enemy: CombatEnemyState, amount: float, shape_hit: bool) -> void:
	var actor_id := "enemy/%d" % enemy.entity_id
	var source_id := "boss/%s" % enemy.action_id if enemy.is_boss else "enemy/%d/%s" % [enemy.entity_id, enemy.kind_id]
	combat_event_stream.emit(tick, "action_impact", {
		"action_instance_id": enemy.action_instance_id,
		"actor_id": actor_id,
		"action_id": enemy.action_id,
		"contact_point": player_position,
	})
	var outcome := "miss"
	if shape_hit:
		outcome = "damage" if _damage_player(amount, source_id, enemy.position) else "avoided"
	combat_event_stream.emit(tick, "attack_resolved", {
		"action_instance_id": enemy.action_instance_id,
		"source_id": source_id,
		"target_id": "ranger",
		"outcome": outcome,
		"contact_point": player_position,
	})


func _update_boss_tick(enemy: CombatEnemyState, intent: Dictionary = {}) -> void:
	if enemy.phase_id == "sealed" and enemy.phase_state == "stable" and boss_damage.compare(boss_maximum.multiply(BigValue.from_float(0.5))) >= 0:
		if enemy.action_instance_id > 0:
			combat_event_stream.emit(tick, "action_interrupted", {
				"action_instance_id": enemy.action_instance_id, "actor_id": "enemy/%d" % enemy.entity_id,
				"action_id": enemy.action_id, "reason": "phase_transition",
			})
		enemy.phase_state = "transition"
		enemy.action_id = "none"
		enemy.action_instance_id = 0
		enemy.action_state = "none"
		enemy.state_started_tick = tick
		enemy.state_ends_tick = tick + BOSS_TRANSITION_TICKS
		enemy.impact_tick = -1
		enemy.impact_resolved = false
		enemy.target_shape = {}
	if enemy.phase_state == "transition":
		if tick >= enemy.state_ends_tick:
			enemy.phase_id = "awakened"
			enemy.phase_state = "stable"
			enemy.core_open = true
			enemy.core_vulnerable = true
			enemy.left_hand_position = enemy.position + Vector2(-43.0, -8.0)
			enemy.right_hand_position = enemy.position + Vector2(38.0, 12.0)
		return
	_advance_action_state(enemy, BOSS_ACTIVE_TICKS, BOSS_RECOVERY_TICKS)
	if enemy.action_state == "none":
		var chosen := intent if not intent.is_empty() else _intent_for_enemy(enemy)
		var requested := String(chosen.get("request_action", ""))
		if requested in ["slam", "sweep", "lane"]:
			_start_boss_action(enemy, requested, chosen.get("action_direction", Vector2.ZERO))
			if enemy.phase_id == "awakened":
				enemy.next_action_index += 1
	if enemy.action_state == "active" and not enemy.impact_resolved:
		enemy.impact_resolved = true
		_resolve_hostile_attack(enemy, 1.8 if enemy.phase_id == "awakened" else 1.2, CombatQueryScript.shape_contains(enemy.target_shape, player_position))
	_update_boss_hands(enemy)


func _start_boss_action(enemy: CombatEnemyState, action: String, planned_direction: Vector2 = Vector2.ZERO) -> void:
	_begin_action(enemy, action, BOSS_WINDUP_TICKS)
	var direction := planned_direction.normalized() if planned_direction != Vector2.ZERO else enemy.position.direction_to(player_position)
	if direction == Vector2.ZERO:
		direction = Vector2.LEFT
	enemy.facing = direction
	match action:
		"sweep":
			enemy.target_shape = {"type": "fan", "origin": enemy.position, "direction": direction, "half_angle": deg_to_rad(48.0), "radius": 190.0}
		"lane":
			enemy.target_shape = {"type": "lane", "origin": enemy.position, "direction": direction, "length": 230.0, "width": 52.0}
		_:
			var target := _clamp_to_arena(player_position, 28.0)
			enemy.target_shape = {"type": "rect", "rect": Rect2(target - Vector2(38.0, 30.0), Vector2(76.0, 60.0))}
	_emit_enemy_action_accepted(enemy)


func _update_boss_hands(enemy: CombatEnemyState) -> void:
	var left_base := enemy.position + Vector2(-43.0 if enemy.phase_id == "awakened" else -34.0, -8.0 if enemy.phase_id == "awakened" else 0.0)
	var right_base := enemy.position + Vector2(38.0 if enemy.phase_id == "awakened" else 34.0, 12.0 if enemy.phase_id == "awakened" else 0.0)
	enemy.left_hand_position = left_base
	enemy.right_hand_position = right_base
	if enemy.action_state in ["windup", "active"]:
		match enemy.action_id:
			"slam":
				enemy.left_hand_position += Vector2(0.0, -20.0 if enemy.action_state == "windup" else 18.0)
			"sweep":
				enemy.right_hand_position += enemy.facing.rotated(-PI * 0.5) * (18.0 if enemy.action_state == "windup" else -18.0)
			"lane":
				enemy.left_hand_position += Vector2(-8.0, 10.0)
				enemy.right_hand_position += Vector2(8.0, -10.0)
