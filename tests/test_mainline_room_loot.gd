extends SceneTree

const ContractPlan := preload("res://src/game/contract_plan.gd")
const Items := preload("res://src/content/early_item_registry.gd")
const Resolver := preload("res://src/systems/build_resolver.gd")
const RoomRuntime := preload("res://src/game/combat_room_runtime.gd")
const ApplicationState := preload("res://src/game/application_state.gd")
const Controller := preload("res://src/game/contract_run_controller.gd")
const SaveStore := preload("res://src/persistence/save_store.gd")
const Assert := preload("res://tests/helpers/assert.gd")

var _failures: Array[String] = []
var _completed: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var planned := ContractPlan.build({
		"contract_id": "mainline_03_first_elite", "seed": 303, "mode": "Manual",
		"completed_node_ids": ["tutorial_ranger_basics", "mainline_01_first_hunt", "mainline_02_priority_under_pressure"],
	})
	_expect(bool(planned.get("ok", false)), "mainline loot: authored contract was rejected")
	if not bool(planned.get("ok", false)):
		_finish()
		return
	var rooms: Array = (planned.plan.get("rooms", []) as Array)
	_expect(rooms.size() == 2, "mainline loot: elite contract changed room count")
	var room: Dictionary = rooms[-1] if not rooms.is_empty() else {}
	var slots: Array = room.get("loot_slots", [])
	_expect(slots.size() == 1 and String((slots[0] as Dictionary).get("source", "")) == "enemy_death", "mainline loot: authored enemy-death slot was not carried into RoomPlan")
	if _failures.size() > 0:
		_finish()
		return

	var items := Items.new()
	_expect(items.load_all().is_empty(), "mainline loot: item registry failed to load")
	var resolved: Dictionary = Resolver.new(items).resolve_fixture("calibration_convergent")
	_expect(bool(resolved.get("ok", false)), "mainline loot: mounted build was rejected")
	if _failures.size() > 0:
		_finish()
		return

	var runtime := RoomRuntime.new()
	root.add_child(runtime)
	runtime.completed.connect(func(result: Dictionary) -> void: _completed.append(result.duplicate(true)))
	var started := runtime.start_session({
		"mode": "Manual", "presentation_enabled": false, "seed": 303,
		"room_index": 0, "room_count": 1, "room": room,
		"framework_context": {
			"active_build": {"skills": ["piercing_arrow", "hunter_mark", "dash"]},
			"resolved_build": resolved, "resolved_proxy_build": {},
		},
	})
	_expect(bool(started.get("ok", false)), "mainline loot: mounted room failed to start: %s" % String(started.get("error", "")))
	if not bool(started.get("ok", false)):
		runtime.free()
		_finish()
		return
	runtime.set_process(false)
	var arena: Node = runtime.room_instance
	arena.set_process(false)
	_expect(bool(arena.room_loot_enabled), "mainline loot: room facade was not enabled")
	var enemies: Array = arena.enemies
	_expect(enemies.size() == 2, "mainline loot: authored elite roster changed")
	if enemies.size() < 2:
		runtime.free()
		_finish()
		return

	# Periodic barrier is active at ticks 0..19. Reach the first legal window
	# through real ticks so the test exercises target blocking rather than bypassing it.
	while arena.sim_tick < 20:
		arena.call("_simulate_tick")
	var elite = enemies[0]
	var elite_position: Vector2 = elite.position
	var placement := _find_valid_attack_position(arena, elite_position)
	_expect(bool(placement.get("ok", false)), "mainline loot: no legal attack placement for elite")
	if not bool(placement.get("ok", false)):
		runtime.free()
		_finish()
		return
	_expect(bool(arena.teleport_actor("ranger", placement.position).get("ok", false)), "mainline loot: player placement failed")
	elite.health = 1.0
	elite.maximum_health = 1.0
	var cast: Dictionary = arena.request_player_cast("piercing_arrow", elite.entity_id, elite_position - placement.position)
	_expect(bool(cast.get("accepted", false)), "mainline loot: real elite arrow was rejected: %s" % str(cast))
	var elite_dead := _advance_until(arena, func() -> bool: return arena.enemy_by_entity_id(elite.entity_id) == null, 120)
	_expect(elite_dead, "mainline loot: elite did not die through the mounted projectile path")
	var loot: Dictionary = arena.room_loot_snapshot
	var entities: Array = loot.get("entities", [])
	_expect(entities.size() == 1, "mainline loot: elite death did not create one room entity")
	var loot_id := String((entities[0] as Dictionary).get("loot_entity_id", "")) if not entities.is_empty() else ""
	_expect(not loot_id.is_empty() and String((entities[0] as Dictionary).get("state", "")) == "available", "mainline loot: spawned entity was not available")
	var item: Dictionary = (entities[0] as Dictionary).get("item", {}) if not entities.is_empty() else {}
	_expect(String(item.get("source", {}).get("type", "")) == "campaign_drop" and not String(item.get("instance_id", "")).is_empty(), "mainline loot: spawned payload was not a validated ItemInstance")

	if not loot_id.is_empty():
		var loot_position: Vector2 = (entities[0] as Dictionary).get("position", elite_position)
		var rejected_pickup_event := InputEventKey.new()
		rejected_pickup_event.keycode = KEY_F
		rejected_pickup_event.physical_keycode = KEY_F
		rejected_pickup_event.pressed = true
		arena.input_adapter.capture_actions(rejected_pickup_event, arena.gameplay_snapshot())
		for _tick in 3:
			arena.call("_simulate_tick")
		var rejected_receipts: Array = arena.room_loot_snapshot.get("pickup_receipts", [])
		_expect(not rejected_receipts.is_empty() and String((rejected_receipts[rejected_receipts.size() - 1] as Dictionary).get("error", "")) == "loot_out_of_range", "mainline loot: room accepted an out-of-range F pickup")
		_expect(String((arena.room_loot_snapshot.get("entities", [])[0] as Dictionary).get("state", "")) == "available", "mainline loot: rejected pickup changed the room entity")
		_expect(bool(arena.teleport_actor("ranger", loot_position).get("ok", false)), "mainline loot: pickup placement failed")
		var pickup_event := InputEventKey.new()
		pickup_event.keycode = KEY_F
		pickup_event.physical_keycode = KEY_F
		pickup_event.pressed = true
		arena.input_adapter.capture_actions(pickup_event, arena.gameplay_snapshot())
		_expect(String(arena.input_adapter.view_state(arena.gameplay_snapshot()).get("loot_pickup_pending_id", "")) == loot_id, "mainline loot: F input did not queue the nearest room drop")
		for _tick in 3:
			arena.call("_simulate_tick")
			if String((arena.room_loot_snapshot.get("entities", [])[0] as Dictionary).get("state", "")) == "picked":
				break
		var picked: Array = arena.room_loot_snapshot.get("entities", [])
		_expect(picked.size() == 1 and String((picked[0] as Dictionary).get("state", "")) == "picked", "mainline loot: real next-tick pickup did not commit")
		_expect(String(arena.last_loot_pickup_command_receipt.get("status", "")) == "accepted" and bool(arena.last_loot_pickup_command_receipt.get("room_receipt", {}).get("accepted", false)), "mainline loot: typed pickup receipt did not reach room authority")

	_expect(bool(arena.battle_over) and bool(arena.battle_victory), "mainline loot: hunt-elite room did not resolve after elite death")
	var settlement: Dictionary = arena.room_loot_snapshot.get("settlement", {})
	_expect(settlement.is_empty(), "mainline loot: victory settled before the player left the loot window")
	runtime.request_abandon()
	_expect(_completed.size() == 1, "mainline loot: mounted result was not emitted once")
	if _completed.size() == 1:
		settlement = arena.room_loot_snapshot.get("settlement", {})
		_expect(String(settlement.get("outcome", "")) == "victory" and (settlement.get("items", []) as Array).size() == 1, "mainline loot: picked item was not settled on room exit")
		var result: Dictionary = _completed[0]
		var result_settlement: Dictionary = result.get("room_loot_settlement", {})
		_expect((result_settlement.get("items", []) as Array).size() == 1, "mainline loot: result lost picked ItemInstance")
		_check_persisted_elite_result(result, settlement, item)
	runtime.free()

	# Auto uses the same typed pickup protocol and room authority when a drop is
	# already within pickup range; it does not get a second ledger shortcut.
	var auto_runtime := RoomRuntime.new()
	root.add_child(auto_runtime)
	var auto_started := auto_runtime.start_session({
		"mode": "Manual", "presentation_enabled": false, "seed": 304,
		"room_index": 0, "room_count": 1, "room": room,
		"framework_context": {
			"active_build": {"skills": ["piercing_arrow", "hunter_mark", "dash"]},
			"resolved_build": resolved, "resolved_proxy_build": {},
		},
	})
	_expect(bool(auto_started.get("ok", false)), "mainline loot: Auto pickup fixture failed to mount")
	if bool(auto_started.get("ok", false)):
		auto_runtime.set_process(false)
		var auto_arena: Node = auto_runtime.room_instance
		auto_arena.set_process(false)
		auto_arena.selected_mode = "Auto"
		var auto_position: Vector2 = auto_arena.player_combat_state.snapshot(auto_arena.sim_tick).player_position
		var blocked_spawn: Dictionary = auto_arena.spawn_room_loot_for_source("enemy_death", 1000, auto_arena._arena_rect().position)
		_expect(not bool(blocked_spawn.get("ok", false)) and String(blocked_spawn.get("error", "")) == "loot_spawn_position_blocked", "mainline loot: production placement port accepted a blocked drop")
		var spawned: Dictionary = auto_arena.spawn_room_loot_for_source("enemy_death", 1001, auto_position)
		_expect(bool(spawned.get("ok", false)), "mainline loot: Auto pickup fixture did not spawn its room entity")
		auto_arena.call("_simulate_tick")
		_expect(String(auto_arena.last_loot_pickup_command_receipt.get("status", "")) == "accepted" and bool(auto_arena.last_loot_pickup_command_receipt.get("room_receipt", {}).get("accepted", false)), "mainline loot: Auto did not submit the shared pickup protocol")
		auto_arena.call("_simulate_tick")
		var auto_entities: Array = auto_arena.room_loot_snapshot.get("entities", [])
		_expect(not auto_entities.is_empty() and String((auto_entities[0] as Dictionary).get("state", "")) == "picked", "mainline loot: Auto shared pickup did not commit on the next tick")
	auto_runtime.request_abandon()
	auto_runtime.free()
	_finish()


func _check_persisted_elite_result(room_result: Dictionary, runtime_settlement: Dictionary, item: Dictionary) -> void:
	var state := ApplicationState.new()
	state.start_new_profile("ranger")
	var config := {"contract_id": "mainline_03_first_elite", "mode": "Manual", "seed": 303, "room_count": 1}
	_expect(bool(state.prepare_contract(config).get("ok", false)) and bool(state.begin_session().get("ok", false)), "mainline loot: persistence session setup failed")
	var controller := Controller.new()
	controller._current_config = config
	controller._rooms = [{}]
	controller._rooms_completed = 1
	controller._room_results = [room_result]
	var summary: Dictionary = controller._build_summary("victory")
	controller.free()
	var probe_registry := Items.new()
	probe_registry.load_all()
	_expect(probe_registry.validate_item_instance(item).is_empty(), "item validity: %s" % str(probe_registry.validate_item_instance(item)))
	var completed: Dictionary = state.complete_session(summary)
	_expect(bool(completed.get("ok", false)), "mainline loot: application settlement failed")
	var wins: int = int(state.profile.progression.contract_wins)
	var path := "user://elite-loot-persistence-%d" % Time.get_ticks_usec()
	var store := SaveStore.new(path)
	var saved: Dictionary = store.save(state.persistent_payload("base"))
	_expect(bool(saved.get("ok", false)), "mainline loot: production victory save failed: %s" % str(saved))
	var loaded: Dictionary = store.load_latest()
	_expect(bool(loaded.get("ok", false)), "mainline loot: victory save could not load")
	if bool(loaded.get("ok", false)):
		var restored := ApplicationState.new()
		var restore: Dictionary = restored.restore_persistent_payload(loaded.payload)
		_expect(bool(restore.get("ok", false)) and int(restored.profile.progression.contract_wins) == wins and wins > 0,
			"mainline loot: restored profile lost the victory")
		var saved_settlement: Dictionary = restored.last_result.room_results[0].room_loot_settlement
		var saved_entity: Dictionary = saved_settlement.entities[0]
		var position: Vector2 = runtime_settlement.entities[0].position
		_expect(is_equal_approx(float(saved_entity.position.x), position.x) and is_equal_approx(float(saved_entity.position.y), position.y)
			and saved_entity.state == "picked" and saved_entity.item.instance_id == item.instance_id,
			"mainline loot: restored entity lost its coordinates, state or item: %s expected %s / %s" % [str(saved_entity), str(position), str(item.get("instance_id"))])
		var found_item := false
		for owned: Dictionary in restored.profile.inventory.equipment:
			found_item = found_item or String(owned.get("instance_id", "")) == String(item.get("instance_id", ""))
		_expect(found_item, "mainline loot: restored inventory lost the elite item")
		_expect(restored.last_result.room_loot_settlements[0] == saved_settlement,
			"mainline loot: summary and per-room receipts diverged")
	_expect(runtime_settlement.entities[0].position is Vector2, "mainline loot: runtime settlement lost Vector2 position")
	store.delete_all()


func _find_valid_attack_position(arena: Node, target_position: Vector2) -> Dictionary:
	var targeting_distance := float(arena.player_combat_state.targeting_distance())
	for distance: float in [80.0, 100.0, 120.0, 140.0, 160.0]:
		if distance >= targeting_distance:
			continue
		for angle_index in 32:
			var candidate := target_position + Vector2.RIGHT.rotated(TAU * float(angle_index) / 32.0) * distance
			if arena.actor_registry.is_position_clear(candidate, arena._arena_rect(), 14.0):
				return {"ok": true, "position": candidate}
	return {"ok": false, "position": Vector2.ZERO}


func _advance_until(arena: Node, predicate: Callable, limit: int) -> bool:
	for _index in limit:
		if bool(predicate.call()):
			return true
		arena.call("_simulate_tick")
	return bool(predicate.call())


func _expect(condition: bool, message: String) -> void: Assert.expect(condition, message, _failures)


func _finish() -> void:
	for failure: String in _failures:
		printerr("- %s" % failure)
	print("PASS test_mainline_room_loot.gd" if _failures.is_empty() else "FAIL test_mainline_room_loot.gd")
	quit(0 if _failures.is_empty() else 1)
