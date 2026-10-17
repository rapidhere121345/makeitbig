extends SceneTree

const EncounterDirectorScript := preload("res://src/game/encounter_director.gd")
const EncounterRoomPortScript := preload("res://src/game/encounter_room_port.gd")
const ArenaGeometryScript := preload("res://src/runtime/geometry/arena_geometry.gd")
const CombatEventStreamScript := preload("res://src/systems/combat_event_stream.gd")
const CombatEnemyStateScript := preload("res://src/runtime/world/combat_enemy_state.gd")
const RoomCatalogScript := preload("res://src/runtime/world/room_catalog.gd")
const EnemyProfileRegistryScript := preload("res://src/content/early_enemy_profile_registry.gd")

class PlayerPort:
	extends RefCounted
	var calls: Array[Dictionary] = []
	func apply_damage(tick: int, amount: float, source_id: String, source_position: Vector2) -> Dictionary:
		calls.append({"tick": tick, "amount": amount, "source_id": source_id, "source_position": source_position})
		return {"accepted": true}

class GarbageRulePort:
	extends RefCounted
	func apply_damage(_tick: int, _amount: float, _source_id: String, _source_position: Vector2) -> Variant:
		return null

class OutcomePort:
	extends RefCounted
	func outcome_snapshot() -> Dictionary:
		return {"boss_damage": BigValue.from_float(0.0), "boss_maximum": BigValue.from_power10(12.0)}

## Typed room dependency double. Failures are toggled per operation so the
## fail-closed gates exercise the director, not a broken fixture.
class RoomPort:
	extends EncounterRoomPortScript
	var moves: Array[int] = []
	var registered: Array[String] = []
	var collision_classes: Array[String] = []
	var fail_moves := false
	var fail_register := false
	var bad_geometry := false
	var bad_quantize := false
	var hazard_calls: Array[Dictionary] = []
	var hostile_calls: Array[Dictionary] = []

	func move_enemy(enemy: CombatEnemyState, displacement: Vector2) -> Dictionary:
		if fail_moves:
			return {"ok": false, "error": "fixture_move_rejected"}
		moves.append(enemy.entity_id)
		var before: Vector2 = enemy.position
		enemy.position += displacement
		return {"ok": true, "position": enemy.position, "displacement": enemy.position - before}

	func set_enemy_collision_class(enemy: CombatEnemyState, collision_class: StringName) -> bool:
		collision_classes.append("%s:%d" % [String(collision_class), enemy.entity_id])
		return true

	func register_enemy(enemy: CombatEnemyState) -> Dictionary:
		if fail_register:
			return {"ok": false, "error": "fixture_register_rejected"}
		registered.append("enemy/%d" % enemy.entity_id)
		return {"ok": true, "error": ""}

	func collision_geometry(padding: float) -> Dictionary:
		if bad_geometry:
			return {}
		return ArenaGeometryScript.from_layout("rectangle_arena", Rect2(0.0, 0.0, 600.0, 400.0), padding)

	func layout_spawn_offsets(_layout_id: String, count: int) -> Array[Vector2]:
		var result: Array[Vector2] = []
		for index in count:
			result.append(Vector2(float(index) * 20.0, 0.0))
		return result

	func clamp_to_arena(value: Vector2, padding: float) -> Vector2:
		return value.clamp(Vector2.ONE * padding, Vector2(600.0, 400.0) - Vector2.ONE * padding)

	func quantize_position(value: Vector2) -> Vector2:
		if bad_quantize:
			return Vector2(INF, INF)
		return Vector2(snappedf(value.x, 0.001), snappedf(value.y, 0.001))

	func queue_player_hazard_hit(tick: int, amount: float, source_id: String, source_position: Vector2) -> Dictionary:
		var call := {"tick": tick, "amount": amount, "source_id": source_id, "source_position": source_position}
		hazard_calls.append(call)
		if source_id.begins_with("enemy/") or source_id.begins_with("boss/"):
			hostile_calls.append(call)
		if player_rule_port is GarbageRulePort:
			return {"ok": false, "error": "fixture_player_contact_rejected"}
		return {"ok": true, "error": ""}


var player_port := PlayerPort.new()
var outcome_port := OutcomePort.new()


func _initialize() -> void:
	var failures: Array[String] = []
	var director = EncounterDirectorScript.new()
	var room_catalog = RoomCatalogScript.new()
	var enemy_profiles = EnemyProfileRegistryScript.new()
	var profile_errors: Array[String] = enemy_profiles.load_all()
	_expect(profile_errors.is_empty(), "director: enemy profile content failed to load: %s" % ";".join(profile_errors), failures)
	var profile_ready: Dictionary = director.set_enemy_profile_registry(enemy_profiles)
	_expect(bool(profile_ready.get("ok", false)), "director: enemy profile port was not configured", failures)
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

	# Typed room boundary: missing, untyped or half-configured dependencies
	# must fail closed before any encounter work starts.
	_expect(not bool(director.bind_room(null).get("ok", false)), "director: null room dependency was accepted", failures)
	_expect(not bool(director.bind_room(RefCounted.new()).get("ok", false)), "director: untyped room dependency was accepted", failures)
	_expect(director.bind_room(null).get("error", "") == "encounter_room_port_unavailable", "director: missing room dependency error was not typed", failures)
	var portless := RoomPort.new()
	portless.combat_outcome_port = outcome_port
	_expect(director.bind_room(portless).get("error", "") == "player_rule_port_unavailable", "director: room dependency without the player rule port was accepted", failures)
	portless.player_rule_port = player_port
	portless.combat_outcome_port = null
	_expect(director.bind_room(portless).get("error", "") == "combat_outcome_port_unavailable", "director: room dependency without the outcome port was accepted", failures)

	var room_port := RoomPort.new()
	room_port.player_rule_port = player_port
	room_port.combat_outcome_port = outcome_port
	var configured: Dictionary = director.bind_room(room_port)
	_expect(bool(configured.get("ok", false)), "director: typed room contract was rejected", failures)
	_expect(director.room_port == room_port, "director: bound room dependency was not retained as the typed port", failures)
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
	_expect(room_port.hazard_calls.size() == 1, "director: active hazard did not cross the typed hazard queue", failures)
	_expect(stream.snapshot().events.size() == 1, "director: hazard resolution bypassed the shared event stream", failures)

	_expect(room_port.hazard_calls[0].source_id == "hazard/exposed_ground_zone" and room_port.hazard_calls[0].source_position == director.hazard_states[0].origin and room_port.hazard_calls[0].tick == 30, "director: hazard did not supply its authored source position/tick", failures)
	director._resolve_hostile_attack(enemy, 11.0, true)
	_expect(player_port.calls.is_empty() and room_port.hostile_calls.size() == 1 and room_port.hostile_calls[0].source_position == enemy.position and room_port.hostile_calls[0].source_id == "enemy/1/melee_pursuer", "director: hostile attack bypassed the typed player contact queue", failures)
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
	var charger := CombatEnemyStateScript.new(Vector2(120.0, 200.0), 420.0, false, 3, "charging_raider")
	var accepted := director._start_charger_action(charger, Vector2.RIGHT, 80.0)
	_expect(accepted and charger.action_state == "windup", "director: charger action did not stay in encounter authority", failures)
	_expect(room_port.collision_classes.has("ghost:3"), "director: charger ghost admission bypassed the typed collision-class operation", failures)
	_expect(room_port.registered.is_empty(), "director: passive encounter update performed an unsolicited actor registration", failures)

	# Movement must fail closed through the typed port: a rejected receipt
	# leaves the actor idle instead of silently applying local motion.
	room_port.fail_moves = true
	var idle_before := enemy.position
	director._commit_normal_enemy_intent(enemy, {"reason": "fixture_move", "move_direction": Vector2.RIGHT, "speed_scale": 1.0})
	_expect(enemy.position == idle_before and enemy.motion_state == "idle", "director: rejected movement receipt still moved the actor", failures)
	room_port.fail_moves = false
	director._commit_normal_enemy_intent(enemy, {"reason": "fixture_move", "move_direction": Vector2.RIGHT, "speed_scale": 1.0})
	_expect(enemy.position.x > idle_before.x and enemy.motion_state == "moving", "director: typed movement operation did not commit displacement", failures)

	# Registration must fail closed: a rejected reinforcement never joins the
	# roster, and the consumed summon flag cannot re-summon through retries.
	enemy.health = enemy.maximum_health * 0.5
	director.elite_rule_ids.append("summon_reinforcements")
	room_port.fail_register = true
	director._maybe_summon_reinforcements(director._enemy_by_entity_id(enemy.entity_id))
	_expect(director.enemies.size() == 1, "director: rejected registration left a ghost reinforcement in the roster", failures)
	_expect(String(director.battle_report).begins_with("reinforcement_actor_registration_failed"), "director: rejected registration was not reported", failures)
	director._maybe_summon_reinforcements(director._enemy_by_entity_id(enemy.entity_id))
	_expect(director.enemies.size() == 1, "director: failed reinforcement summon was retried within the same encounter", failures)
	room_port.fail_register = false

	# Invalid quantization freezes the fireline origin instead of silently
	# re-deriving the authority grid locally.
	director.hazard_states.clear()
	director.hazard_states.append(director.new_hazard_state("moving_fireline", Vector2(300.0, 200.0)))
	director.tick = 45
	director.refresh_hazard_states_tick()
	var fireline_origin: Vector2 = director.hazard_states[0].origin
	room_port.bad_quantize = true
	director.tick = 60
	director.refresh_hazard_states_tick()
	_expect(director.hazard_states[0].origin == fireline_origin, "director: invalid quantization silently re-derived the hazard origin", failures)
	room_port.bad_quantize = false

	# Invalid collision geometry fails closed: AI planning yields no intents
	# rather than silently substituting other geometry.
	room_port.bad_geometry = true
	_expect(director._intent_for_enemy(enemy).is_empty(), "director: invalid collision geometry still produced enemy intents", failures)
	room_port.bad_geometry = false
	_expect(not director._intent_for_enemy(enemy).is_empty(), "director: valid collision geometry produced no enemy intents", failures)

	# A garbage damage receipt must fail closed without crashing the tick.
	var garbage_director = EncounterDirectorScript.new()
	garbage_director.set_enemy_profile_registry(enemy_profiles)
	var garbage_port := RoomPort.new()
	garbage_port.player_rule_port = GarbageRulePort.new()
	garbage_port.combat_outcome_port = outcome_port
	_expect(bool(garbage_director.bind_room(garbage_port).get("ok", false)), "director: garbage-receipt fixture failed to bind", failures)
	var garbage_stream = CombatEventStreamScript.new()
	garbage_director.set_context(30, Vector2(200.0, 200.0), Rect2(0.0, 0.0, 600.0, 400.0), garbage_stream, "rectangle_arena", "clear")
	var garbage_enemy := CombatEnemyStateScript.new(Vector2(100.0, 200.0), 720.0, false, 1, "melee_pursuer")
	garbage_director.enemies.append(garbage_enemy)
	garbage_director._resolve_hostile_attack(garbage_enemy, 5.0, true)
	_expect(garbage_stream.latest("attack_resolved").get("outcome", "") == "avoided", "director: rejected player contact was reported as damage", failures)

	# The director has one typed composition boundary. A missing/invalid room
	# port is rejected rather than routed through a compatibility adapter.
	var invalid_director := EncounterDirectorScript.new()
	_expect(invalid_director.bind_room(null).get("error", "") == "encounter_room_port_unavailable", "director: invalid room authority was accepted", failures)

	if failures.is_empty():
		print("PASS test_encounter_director.gd")
		quit(0)
		return
	for failure: String in failures:
		printerr("- %s" % failure)
	quit(1)
func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
