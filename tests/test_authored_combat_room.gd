extends SceneTree

const ContractPlan := preload("res://src/game/contract_plan.gd")
const Items := preload("res://src/content/early_item_registry.gd")
const Resolver := preload("res://src/systems/build_resolver.gd")
const RoomRuntime := preload("res://src/game/combat_room_runtime.gd")

var _failures: Array[String] = []
var _completed: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var seed := 101
	var planned := ContractPlan.build({
		"contract_id": "side_targeted_equipment", "seed": seed, "mode": "Manual",
	})
	_expect(bool(planned.get("ok", false)), "authored room: side plan was rejected")
	if not bool(planned.get("ok", false)):
		_finish()
		return
	var rooms: Array = planned.plan.rooms
	_expect(rooms.size() == 3, "authored room: side plan did not retain three rooms")
	var room: Dictionary = rooms[0] if not rooms.is_empty() else {}
	_expect(room.get("loot_slots", []) is Array and (room.get("loot_slots", []) as Array).size() == 1, "authored room: room 0 lost its loot slot")
	_expect(room.get("combat_stats", {}) is Dictionary and float((room.get("combat_stats", {}) as Dictionary).get("move_speed", 0.0)) == 220.0, "authored room: room 0 lost its combat sheet")
	_expect(String(room.get("objective_id", "")) == "hunt_elite", "authored room: room 0 did not retain its elite objective")
	_expect("summon_reinforcements" in (room.get("elite_rule_ids", []) as Array), "authored room: room 0 did not retain its summon rule")
	_expect(not (rooms[1] as Dictionary).has("loot_slots") and not (rooms[1] as Dictionary).has("combat_stats"), "authored room: override leaked into the next room")

	var items := Items.new()
	_expect(items.load_all().is_empty(), "authored room: item registry failed to load")
	var resolved: Dictionary = Resolver.new(items).resolve_fixture("calibration_convergent")
	_expect(bool(resolved.get("ok", false)), "authored room: build resolver rejected the mounted build")
	if _failures.size() > 0:
		_finish()
		return

	var runtime := RoomRuntime.new()
	root.add_child(runtime)
	var started := runtime.start_session({
		"mode": "Manual", "presentation_enabled": false, "seed": seed,
		"room_index": 0, "room_count": 3, "room": room,
		"framework_context": {
			"active_build": {"skills": ["piercing_arrow"]},
			"resolved_build": resolved,
			"resolved_proxy_build": {},
		},
	})
	_expect(bool(started.get("ok", false)), "authored room: mounted room failed to start: %s" % String(started.get("error", "")))
	if not bool(started.get("ok", false)):
		runtime.free()
		_finish()
		return
	runtime.set_process(false)
	var arena: Node = runtime.room_instance
	arena.set_process(false)
	var player: Dictionary = arena.player_combat_state.snapshot(arena.sim_tick)
	var stats: Dictionary = player.get("combat_stats", {})
	_expect(bool(arena.room_loot_enabled), "authored room: room loot facade was not enabled")
	_expect(float(stats.get("move_speed", 0.0)) == 220.0 and int(stats.get("attack_cooldown_ticks", 0)) == 11, "authored room: mounted player did not consume the room combat sheet")

	var enemies: Array = arena.enemies
	_expect(enemies.size() == 1, "authored room: side room did not keep its one-enemy encounter")
	if enemies.is_empty():
		runtime.free()
		_finish()
		return
	var enemy = enemies[0]
	var enemy_position: Vector2 = enemy.position
	_expect(arena.actor_registry.is_position_clear(enemy_position, arena._arena_rect(), 16.0), "authored room: authored enemy spawn is not clear")
	var player_placement := _find_valid_attack_position(arena, enemy_position)
	_expect(bool(player_placement.get("ok", false)), "authored room: no valid player position near authored enemy spawn")
	if not bool(player_placement.get("ok", false)):
		runtime.free()
		_finish()
		return
	_expect(bool(arena.teleport_actor("ranger", player_placement.position).get("ok", false)), "authored room: player placement failed")
	enemy.health = 1.0
	enemy.maximum_health = 1.0
	var cast: Dictionary = arena.request_player_cast("piercing_arrow", enemy.entity_id, enemy_position - player_placement.position)
	_expect(bool(cast.get("accepted", false)), "authored room: real arrow request was rejected")
	var first_removed := _advance_until(arena, func() -> bool:
		return arena._enemy_by_entity_id(enemy.entity_id) == null and not arena.enemies.is_empty()
	, 120)
	_expect(first_removed, "authored room: elite did not die and summon a replacement")
	var loot: Dictionary = arena.room_loot_snapshot
	var entities: Array = loot.get("entities", [])
	_expect(entities.size() == 1, "authored room: enemy death did not create its authored loot entity")
	if not entities.is_empty():
		_expect(String(entities[0].get("state", "")) == "available", "authored room: elite death did not leave an available drop")
		_expect(String(entities[0].get("slot_id", "")) == "targeted_equipment_drop", "authored room: wrong loot slot settled")
	if not first_removed or arena.enemies.is_empty():
		runtime.free()
		_finish()
		return
	var reinforcement = arena.enemies[0]
	reinforcement.health = 1.0
	var ready := _advance_until(arena, func() -> bool:
		return int(arena.player_combat_state.snapshot(arena.sim_tick).attack_cooldown_ticks) == 0
	, 120)
	_expect(ready, "authored room: authored attack cooldown never became ready after summon")
	if not ready:
		runtime.free()
		_finish()
		return
	var reinforcement_position: Vector2 = reinforcement.position
	var reinforcement_player := _find_valid_attack_position(arena, reinforcement_position)
	_expect(bool(reinforcement_player.get("ok", false)), "authored room: no valid player position near summoned enemy")
	if not bool(reinforcement_player.get("ok", false)):
		runtime.free()
		_finish()
		return
	_expect(bool(arena.teleport_actor("ranger", reinforcement_player.position).get("ok", false)), "authored room: summoned enemy placement failed")
	var second_cast: Dictionary = arena.request_player_cast("piercing_arrow", reinforcement.entity_id, reinforcement_position - reinforcement_player.position)
	_expect(bool(second_cast.get("accepted", false)), "authored room: real arrow request for summon was rejected")
	var ended := _advance_until(arena, func() -> bool: return bool(arena.battle_over), 120)
	_expect(ended and bool(arena.battle_victory), "authored room: summoned enemy did not produce victory")
	loot = arena.room_loot_snapshot
	entities = loot.get("entities", [])
	if not entities.is_empty():
		_expect(String(entities[0].get("state", "")) == "left_in_room", "authored room: terminal settlement did not preserve the unpicked drop")
	runtime.completed.connect(func(result: Dictionary) -> void: _completed.append(result.duplicate(true)))
	runtime.request_abandon()
	_expect(_completed.size() == 1, "authored room: mounted result was not emitted once")
	if _completed.size() == 1:
		var result: Dictionary = _completed[0]
		var settlement: Dictionary = result.get("room_loot_settlement", {})
		_expect(String(result.get("outcome", "")) == "victory", "authored room: result outcome changed")
		_expect((settlement.get("items", []) as Array).is_empty(), "authored room: an unpicked item entered settlement")
	runtime.free()
	_finish()


func _advance_until(arena: Node, predicate: Callable, limit: int) -> bool:
	for _index in limit:
		if bool(predicate.call()):
			return true
		arena.call("_simulate_tick")
	return bool(predicate.call())


func _find_valid_attack_position(arena: Node, target_position: Vector2) -> Dictionary:
	var targeting_distance := float(arena.player_combat_state.targeting_distance())
	var distances: Array[float] = [80.0, 100.0, 120.0, 140.0, 160.0, 180.0, 200.0]
	for distance: float in distances:
		if distance >= targeting_distance:
			continue
		for angle_index in 32:
			var candidate := target_position + Vector2.RIGHT.rotated(TAU * float(angle_index) / 32.0) * distance
			if arena.actor_registry.is_position_clear(candidate, arena._arena_rect(), 14.0):
				return {"ok": true, "position": candidate}
	return {"ok": false, "position": Vector2.ZERO}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	for failure: String in _failures:
		printerr("- %s" % failure)
	print("PASS test_authored_combat_room.gd" if _failures.is_empty() else "FAIL test_authored_combat_room.gd")
	quit(0 if _failures.is_empty() else 1)
