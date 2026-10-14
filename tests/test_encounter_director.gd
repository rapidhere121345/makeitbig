extends SceneTree

const EncounterDirectorScript := preload("res://src/game/encounter_director.gd")
const ArenaGeometryScript := preload("res://src/runtime/geometry/arena_geometry.gd")
const CombatEventStreamScript := preload("res://src/systems/combat_event_stream.gd")
const CombatEnemyStateScript := preload("res://src/runtime/world/combat_enemy_state.gd")
const RoomCatalogScript := preload("res://src/runtime/world/room_catalog.gd")

class PlayerPort:
	extends RefCounted
	var calls: Array[Dictionary] = []
	func apply_damage(tick: int, amount: float, source_id: String, source_position: Vector2) -> Dictionary:
		calls.append({"tick": tick, "amount": amount, "source_id": source_id, "source_position": source_position})
		return {"accepted": true}

class OutcomePort:
	extends RefCounted
	func outcome_snapshot() -> Dictionary:
		return {"boss_damage": BigValue.from_float(0.0), "boss_maximum": BigValue.from_power10(12.0)}

var player_port := PlayerPort.new()
var outcome_port := OutcomePort.new()
var registered_ids: Array[String] = []


func _initialize() -> void:
	var failures: Array[String] = []
	var director = EncounterDirectorScript.new()
	var room_catalog = RoomCatalogScript.new()
	var valid_room := {
		"layout_id": "corridor",
		"objective_id": "clear",
		"enemy_ids": ["melee_pursuer"],
		"hazard_ids": [],
		"elite_rule_ids": [],
		"drop_tags": [],
		"boss_id": "",
	}
	_expect(EncounterDirectorScript.validate_room(valid_room, room_catalog).is_empty(), "director: valid room was rejected by the encounter validator", failures)
	var invalid_room := valid_room.duplicate(true)
	invalid_room["hazard_ids"] = ["unknown_hazard"]
	_expect(EncounterDirectorScript.validate_room(invalid_room, room_catalog) == "unknown_hazard_id", "director: unknown hazard was not rejected by the encounter validator", failures)
	invalid_room = valid_room.duplicate(true)
	invalid_room["enemy_ids"] = [7]
	_expect(EncounterDirectorScript.validate_room(invalid_room, room_catalog) == "invalid_room_field:enemy_ids", "director: malformed roster values reached String coercion", failures)
	invalid_room = valid_room.duplicate(true)
	invalid_room["layout_id"] = false
	_expect(EncounterDirectorScript.validate_room(invalid_room, room_catalog) == "invalid_room_field:layout_id", "director: non-string layout was accepted", failures)
	_expect(director.spawn_wave(valid_room, Vector2.ZERO).get("error", "") == "encounter_not_configured", "director: unconfigured callbacks created a wave", failures)
	_expect(room_catalog.resolve({"layout_id": "", "layout": "ring"}).get("error", "") == "invalid_room_layout", "catalog: an empty canonical layout silently used an alias", failures)
	_expect(room_catalog.resolve({"layout_id": "ring", "layout": "corridor"}).get("error", "") == "room_layout_conflict", "catalog: contradictory layout identity was accepted", failures)
	var configured: Dictionary = director.configure({
		"move_enemy": Callable(self, "_move_enemy"),
		"player_rule_port": player_port,
		"combat_outcome_port": outcome_port,
		"register_enemy": Callable(self, "_register_enemy"),
		"walkable_geometry": Callable(self, "_walkable_geometry"),
		"layout_spawn_offsets": Callable(self, "_layout_spawn_offsets"),
		"clamp_to_arena": Callable(self, "_clamp_to_arena"),
		"quantize_position": Callable(self, "_quantize_position"),
	})
	_expect(bool(configured.get("ok", false)), "director: callback contract was rejected", failures)
	var missing_identity := director.spawn_wave(valid_room, Vector2.ZERO)
	_expect(missing_identity.get("error", "") == "missing_room_field:room_id", "director: spawn accepted an encounter without instance identity", failures)
	invalid_room = valid_room.duplicate(true)
	invalid_room["room_id"] = "director.bad-layout"
	invalid_room["layout_id"] = "missing_layout"
	_expect(director.spawn_wave(invalid_room, Vector2.ZERO).get("error", "") == "unknown_layout_id", "director: direct spawn accepted an unknown layout", failures)
	_expect(director.spawn_wave(invalid_room, Vector2(INF, 0)).get("error", "") == "invalid_encounter_origin", "director: non-finite origin created actors", failures)
	var stream = CombatEventStreamScript.new()
	director.set_context(0, Vector2(200.0, 200.0), Rect2(0.0, 0.0, 600.0, 400.0), stream, "rectangle_arena", "timed_break")
	director.elite_rule_ids.append("periodic_barrier")
	director.elite_entity_id = 1
	director.update_room_rules_tick()
	_expect(director.elite_barrier_active, "director: periodic barrier did not derive from fixed tick", failures)
	director.timed_bonus_available = true
	director.tick = 901
	director.update_room_rules_tick()
	_expect(not director.timed_bonus_available, "director: timed rule was not updated by encounter authority", failures)

	var enemy := CombatEnemyStateScript.new(Vector2(100.0, 200.0), 720.0, false, 1, "melee_pursuer")
	director.enemies.append(enemy)
	director.elite_entity_id = enemy.entity_id
	director.hazard_states.append(director.new_hazard_state("exposed_ground_zone", Vector2(200.0, 200.0)))
	director.tick = 30
	director.player_position = Vector2(200.0, 200.0)
	director.refresh_hazard_states_tick()
	director.resolve_hazard_hits_tick()
	_expect(player_port.calls.size() == 1, "director: active hazard did not cross the explicit damage callback", failures)
	_expect(stream.snapshot().events.size() == 1, "director: hazard resolution bypassed the shared event stream", failures)

	_expect(player_port.calls[0].source_id == "hazard/exposed_ground_zone" and player_port.calls[0].source_position == director.hazard_states[0].origin and player_port.calls[0].tick == 30, "director: hazard did not supply its authored source position/tick", failures)
	director._resolve_hostile_attack(enemy, 11.0, true)
	_expect(player_port.calls.size() == 2 and player_port.calls[1].source_position == enemy.position and player_port.calls[1].source_id == "enemy/1/melee_pursuer", "director: hostile attack inferred source position from its string id", failures)
	var other := CombatEnemyStateScript.new(Vector2(500.0, 200.0), 10.0, false, 2, "fan_ranged")
	for boundary_tick in [0, 19, 20, 59, 60]:
		director.tick = boundary_tick
		director.update_room_rules_tick()
		var blocked: bool = boundary_tick % 60 < 20
		_expect(director.is_target_blocked(enemy) == blocked and director.is_targetable(enemy) == not blocked, "director: shared barrier query changed on tick %d" % boundary_tick, failures)
		_expect(not director.is_target_blocked(other) and director.is_targetable(other), "director: elite barrier blocked an ordinary enemy", failures)
	other.health = 0.0
	_expect(not director.is_targetable(other) and not director.is_targetable(null), "director: dead/missing target was legal", failures)

	var snapshot: Dictionary = director.enemy_tactics_snapshot()
	_expect(int(snapshot.get("snapshot_version", -1)) == 2 and (snapshot.get("enemies", []) as Array).size() == 1,
		"director: tactics snapshot was not assembled from room-local state", failures)
	var accepted := director._start_charger_action(enemy, Vector2.RIGHT, 80.0)
	_expect(accepted and enemy.action_state == "windup", "director: charger action did not stay in encounter authority", failures)
	_expect(registered_ids.is_empty(), "director: passive encounter update performed an unsolicited actor registration", failures)

	if failures.is_empty():
		print("PASS test_encounter_director.gd")
		quit(0)
		return
	for failure: String in failures:
		printerr("- %s" % failure)
	quit(1)


func _move_enemy(enemy, displacement: Vector2) -> Dictionary:
	var before: Vector2 = enemy.position
	enemy.position += displacement
	return {"ok": true, "position": enemy.position, "displacement": enemy.position - before}


func _register_enemy(enemy) -> bool:
	registered_ids.append("enemy/%d" % enemy.entity_id)
	return true


func _walkable_geometry(padding: float) -> Dictionary:
	return ArenaGeometryScript.from_layout("rectangle_arena", Rect2(0.0, 0.0, 600.0, 400.0), padding)


func _layout_spawn_offsets(_layout_id: String, count: int) -> Array[Vector2]:
	var result: Array[Vector2] = []
	for index in count:
		result.append(Vector2(float(index) * 20.0, 0.0))
	return result


func _clamp_to_arena(value: Vector2, padding: float) -> Vector2:
	return value.clamp(Vector2.ONE * padding, Vector2(600.0, 400.0) - Vector2.ONE * padding)


func _quantize_position(value: Vector2) -> Vector2:
	return Vector2(snappedf(value.x, 0.001), snappedf(value.y, 0.001))


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
