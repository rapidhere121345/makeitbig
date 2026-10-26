extends SceneTree

const Items := preload("res://src/content/early_item_registry.gd")
const Resolver := preload("res://src/systems/build_resolver.gd")
const RoomRuntime := preload("res://src/game/combat_room_runtime.gd")
const Assert := preload("res://tests/helpers/assert.gd")

var _failures: Array[String] = []
var _completed: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var items := Items.new()
	_expect(items.load_all().is_empty(), "real room: item registry failed to load")
	if not _failures.is_empty():
		_finish()
		return
	var resolved: Dictionary = Resolver.new(items).resolve_fixture("calibration_convergent")
	_expect(bool(resolved.get("ok", false)), "real room: resolved combat build was rejected")
	if not _failures.is_empty():
		_finish()
		return

	var runtime := RoomRuntime.new()
	root.add_child(runtime)
	var started := runtime.start_session({
		"mode": "Manual",
		"presentation_enabled": false,
		"seed": 77123,
		"room": {
			"room_id": "test.real.combat.loot",
			"layout_id": "rectangle_arena",
			"objective_id": "clear",
			"hazard_ids": [],
			"enemy_ids": ["melee_pursuer", "melee_pursuer"],
			"elite_rule_ids": [],
			"boss_id": "",
			"drop_tags": [],
			"loot_slots": [{
				"slot_id": "enemy_death_drop",
				"source": "enemy_death",
				"tag": "equipment_general",
				"pickup_radius": 18.0,
			}],
		},
		"framework_context": {
			"active_build": {"skills": ["piercing_arrow", "hunter_mark", "dash"]},
			"resolved_build": resolved,
		},
	})
	_expect(bool(started.get("ok", false)), "real room: mounted runtime failed to start: %s" % String(started.get("error", "")))
	if not bool(started.get("ok", false)):
		runtime.free()
		_finish()
		return
	runtime.set_process(false)
	var arena: Node = runtime.room_instance
	arena.set_process(false)
	var enemies: Array = arena.enemies
	_expect(enemies.size() == 2, "real room: mounted room did not create two live enemies")
	if enemies.size() < 2:
		runtime.free()
		_finish()
		return

	# Keep the first projectile lane clear of the whole wall without changing range.
	var center: Vector2 = arena._arena_rect().get_center() + Vector2(0, -36)
	var first = enemies[0]
	var second = enemies[1]
	_expect(bool(arena.teleport_actor("ranger", center).get("ok", false)), "real room: ranger fixture placement failed")
	_expect(bool(arena.teleport_actor("enemy/%d" % first.entity_id, center + Vector2.RIGHT * 120.0).get("ok", false)), "real room: first target placement failed")
	_expect(bool(arena.teleport_actor("enemy/%d" % second.entity_id, _clear_near(arena, center + Vector2.DOWN * 120.0)).get("ok", false)), "real room: second target placement failed")
	first.health = 1.0
	first.maximum_health = 1.0
	second.health = 1.0
	second.maximum_health = 1.0

	var first_cast: Dictionary = arena.request_player_cast("piercing_arrow", first.entity_id)
	_expect(bool(first_cast.get("accepted", false)), "real room: first real arrow was rejected: %s" % str(first_cast))
	var first_dead := _advance_until(arena, func() -> bool:
		return arena._enemy_by_entity_id(first.entity_id) == null
	, 120)
	_expect(first_dead, "real room: first enemy did not die through the mounted projectile path")
	_expect(not bool(arena.battle_over), "real room: one enemy death ended a two-enemy room")
	var loot_snapshot: Dictionary = arena.room_loot_snapshot
	var loot_entities: Array = loot_snapshot.get("entities", [])
	_expect(loot_entities.size() == 1, "real room: enemy death did not spawn one room loot entity")
	var loot_id := String(loot_entities[0].get("loot_entity_id", "")) if not loot_entities.is_empty() else ""
	_expect(String(loot_entities[0].get("state", "")) == "available" if not loot_entities.is_empty() else false, "real room: spawned loot was not available")
	_expect(int(loot_entities[0].get("source_entity_id", 0)) == first.entity_id if not loot_entities.is_empty() else false, "real room: loot source entity was not the dead enemy")

	var pickup_position: Vector2 = loot_entities[0].get("position", center) if not loot_entities.is_empty() else center
	_expect(bool(arena.teleport_actor("ranger", pickup_position).get("ok", false)), "real room: pickup fixture placement failed")
	var pickup: Dictionary = arena.request_loot_pickup(loot_id)
	_expect(bool(pickup.get("accepted", false)), "real room: pickup request was not queued")
	var duplicate_pickup: Dictionary = arena.request_loot_pickup(loot_id)
	_expect(String(duplicate_pickup.get("error", "")) == "loot_pickup_already_queued", "real room: duplicate pickup request was accepted")
	var pickup_tick := int(arena.sim_tick) + 1
	_arena_step(arena)
	var after_pickup: Dictionary = arena.room_loot_snapshot
	var picked_entities: Array = after_pickup.get("entities", [])
	_expect(int(arena.sim_tick) == pickup_tick, "real room: pickup did not execute on the next committed tick")
	_expect(not picked_entities.is_empty() and String(picked_entities[0].get("state", "")) == "picked", "real room: next-tick pickup did not mark the entity picked")
	_expect((after_pickup.get("pickup_receipts", []) as Array).size() == 1 and bool((after_pickup.pickup_receipts[0] as Dictionary).get("ok", false)), "real room: pickup receipt was not recorded once")

	# Move within range of the second target, wait for the real attack cooldown,
	# and finish the room through the same projectile/terminal phases.
	var second_position: Vector2 = second.position
	var second_player_position := _valid_attack_position(arena, second_position)
	_expect(bool(second_player_position.get("ok", false)), "real room: no clear attack position near the second target")
	if not bool(second_player_position.get("ok", false)):
		arena.free()
		_finish()
		return
	_expect(bool(arena.teleport_actor("ranger", second_player_position.position).get("ok", false)), "real room: second attack fixture placement failed")
	var ready := _advance_until(arena, func() -> bool:
		return int(arena.player_combat_state.snapshot(arena.sim_tick).attack_cooldown_ticks) == 0
	, 120)
	_expect(ready, "real room: second real attack never became ready")
	## The second enemy walks during the cooldown wait; re-place the player on a
	## clear lane to its current position before casting.
	var second_lane := _valid_attack_position(arena, second.position)
	_expect(bool(second_lane.get("ok", false)), "real room: no clear attack lane to the second target")
	if bool(second_lane.get("ok", false)):
		_expect(bool(arena.teleport_actor("ranger", second_lane.position).get("ok", false)), "real room: second lane placement failed")
	var second_cast: Dictionary = arena.request_player_cast("piercing_arrow", second.entity_id)
	_expect(bool(second_cast.get("accepted", false)), "real room: second real arrow was rejected: %s" % str(second_cast))
	var second_dead := _advance_until(arena, func() -> bool:
		return bool(arena.battle_over)
	, 120)
	_expect(second_dead and bool(arena.battle_victory), "real room: second enemy did not produce mounted victory")
	var in_room_settlement: Dictionary = arena.room_loot_snapshot.get("settlement", {})
	_expect(in_room_settlement.is_empty(), "real room: victory settled loot before the player left the loot window")

	runtime.completed.connect(func(result: Dictionary) -> void: _completed.append(result.duplicate(true)))
	runtime.request_abandon()
	_expect(_completed.size() == 1, "real room: mounted completion was not emitted exactly once")
	if _completed.size() == 1:
		var result: Dictionary = _completed[0]
		var settlement: Dictionary = result.get("room_loot_settlement", {})
		in_room_settlement = arena.room_loot_snapshot.get("settlement", {})
		_expect(String(in_room_settlement.get("outcome", "")) == "victory" and (in_room_settlement.get("items", []) as Array).size() == 1, "real room: room exit did not create the one in-room loot settlement")
		_expect(String(result.get("outcome", "")) == "victory", "real room: mounted result did not report victory")
		_expect((settlement.get("items", []) as Array).size() == 1, "real room: picked ItemInstance was not carried into the result")
		_expect(String(settlement.get("outcome", "")) == "victory", "real room: result settlement outcome changed")
		_expect(String((settlement.get("entities", [])[0] as Dictionary).get("state", "")) == "picked", "real room: settled entity did not retain picked state")
	var second_completion := 0
	runtime.completed.connect(func(_result: Dictionary) -> void: second_completion += 1)
	runtime.request_abandon()
	_expect(second_completion == 0, "real room: repeated completion emitted a second settlement")

	runtime.free()
	_finish()


func _arena_step(arena: Node) -> void:
	arena.call("_simulate_tick")


func _advance_until(arena: Node, predicate: Callable, limit: int) -> bool:
	for _index in limit:
		if bool(predicate.call()):
			return true
		_arena_step(arena)
	return bool(predicate.call())


func _expect(condition: bool, message: String) -> void: Assert.expect(condition, message, _failures)


## Authored static blockers own spawn clearance now, so fixed fixture offsets
## can land on a ruin. Deterministic nearest-clear search keeps the fixture
## semantics without pinning coordinates to the current blocker layout.
func _clear_near(arena: Node, desired: Vector2, radius: float = 16.0) -> Vector2:
	if arena.actor_registry.is_position_clear(desired, arena._arena_rect(), radius):
		return desired
	for ring: float in [16.0, 32.0, 48.0, 64.0, 96.0]:
		for step: int in 16:
			var candidate := desired + Vector2(ring, 0.0).rotated(TAU * float(step) / 16.0)
			if arena.actor_registry.is_position_clear(candidate, arena._arena_rect(), radius):
				return candidate
	return desired


## The player fixture needs a clear footprint, an unobstructed projectile
## lane, and an open movement lane. Arrows fly a straight fixed line, so the
## candidate keeps the original cardinal-offset semantics: a melee target
## walking straight at the player stays on the released line.
func _valid_attack_position(arena: Node, target: Vector2) -> Dictionary:
	var index: Variant = arena.actor_registry.static_index
	var offsets: Array[Vector2] = [Vector2(-100.0, 0.0), Vector2(100.0, 0.0), Vector2(0.0, -100.0), Vector2(0.0, 100.0)]
	for offset: Vector2 in offsets:
		var candidate := _clear_near(arena, target + offset, 14.0)
		if not arena.actor_registry.is_position_clear(candidate, arena._arena_rect(), 14.0):
			continue
		if index == null:
			return {"ok": true, "position": candidate}
		if not (index.sweep(&"projectile", candidate, target - candidate, 12.0) as Array).is_empty():
			continue
		if not (index.sweep(&"movement", target, candidate - target, 16.0) as Array).is_empty():
			continue
		return {"ok": true, "position": candidate}
	return {"ok": false, "position": Vector2.ZERO}


func _finish() -> void:
	for failure: String in _failures:
		printerr("- %s" % failure)
	print("PASS test_real_combat_room.gd" if _failures.is_empty() else "FAIL test_real_combat_room.gd")
	quit(0 if _failures.is_empty() else 1)
