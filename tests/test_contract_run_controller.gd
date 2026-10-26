extends SceneTree

const ControllerScript := preload("res://src/game/contract_run_controller.gd")
const ApplicationStateScript := preload("res://src/game/application_state.gd")
const ContractPlanScript := preload("res://src/game/contract_plan.gd")
const CommitPortScript := preload("res://tests/helpers/callable_contract_room_commit_port.gd")
const Assert := preload("res://tests/helpers/assert.gd")

class FakeArena:
	extends Node

	signal completed(result: Dictionary)
	signal abandoned(result: Dictionary)

	var config: Dictionary = {}
	var started := false
	var abandon_requests := 0
	var event_log: Array = []

	func start_session(value: Dictionary) -> Dictionary:
		if started:
			return {"ok": false, "error": "already_started"}
		started = true
		config = value.duplicate(true)
		event_log.append("start:%d" % int(value.get("room_index", -1)))
		return {"ok": true}

	func resolve(result: Dictionary) -> void:
		completed.emit(result)

	func request_abandon() -> void:
		abandon_requests += 1
		abandoned.emit({"outcome": "abandoned", "ticks": 2, "report": "left room"})

var _created: Array[FakeArena] = []
var _completed_events: Array[Dictionary] = []
var _abandoned_events: Array[Dictionary] = []
var _room_events: Array[Dictionary] = []
var _factory_fail_after := -1
var _event_log: Array = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var failures: Array[String] = []
	_test_three_victories(failures)
	_test_second_room_defeat(failures)
	_test_abandon(failures)
	_test_room_start_error(failures)
	_test_duplicate_signal_guard(failures)
	_test_invalid_plans(failures)
	_test_alias_isolation(failures)
	_test_commit_port_orders_framework_commit(failures)
	_test_commit_failure_blocks_next_room(failures)
	_test_real_held_attack_between_rooms(failures)
	if failures.is_empty():
		print("PASS  test_contract_run_controller.gd")
		quit(0)
		return
	for failure in failures:
		printerr("- %s" % failure)
	quit(1)


func _test_three_victories(failures: Array[String]) -> void:
	var controller = _create_controller()
	var config := _config(3)
	config["room_plan"] = {"rooms": [{"id": "a"}, {"id": "b"}, {"id": "c"}]}
	_expect(bool(controller.start_session(config).get("ok", false)), "three rooms: start failed", failures)
	_expect(_created.size() == 1 and int(_created[0].config.room_index) == 0, "three rooms: first room was not started", failures)
	_created[0].resolve(_result("victory", 10, 1.5, 2, 3, 1, 2, "drop.a", "Drop A", "first", 1, 0))
	_created[1].resolve(_result("victory", 20, 2.5, 4, 5, 1, 0, "", "", "second", 0, 2))
	_created[2].resolve(_result("victory", 30, 3.5, 6, 7, 1, 3, "drop.c", "Drop C", "third", 3, 4))
	_expect(_completed_events.size() == 1, "three rooms: completion count changed", failures)
	if _completed_events.size() == 1:
		var summary := _completed_events[0]
		_expect(summary.outcome == "victory" and int(summary.rooms_completed) == 3 and int(summary.room_count) == 3, "three rooms: completion metadata changed", failures)
		_expect(int(summary.ticks) == 60 and is_equal_approx(float(summary.elapsed_seconds), 7.5) and int(summary.casts) == 12 and int(summary.defeated) == 15, "three rooms: metrics were not accumulated", failures)
		_expect(int(summary.rewards.contract_wins_delta) == 1, "three rooms: contract victory was counted per room", failures)
		_expect(summary.rewards.law_tallies_delta == {"inscribe": 5, "rewrite": 4, "refine": 6}, "three rooms: Law Tally rewards were not accumulated", failures)
		_expect(summary.rewards.keys() == ["contract_wins_delta", "law_tallies_delta"] and summary.report == "third", "three rooms: legacy reward fields leaked into summary", failures)
		_expect(summary.room_results.size() == 3, "three rooms: room results missing", failures)
	_expect(_room_events.size() == 2 and int(_room_events[0].room_index) == 1 and int(_room_events[1].room_index) == 2 and _room_events[1].room.id == "c", "three rooms: room_changed sequence changed", failures)
	_destroy_controller(controller)


func _test_second_room_defeat(failures: Array[String]) -> void:
	var controller = _create_controller()
	controller.start_session(_config(3))
	_created[0].resolve(_result("victory", 5, 1.0, 1, 1, 1, 0, "", "", "won"))
	var losing_room := _result("defeat", 7, 2.0, 2, 3, 0, 0, "", "", "lost")
	losing_room["failure_reason"] = "enemy/charging_raider"
	losing_room["death_tick"] = 37
	_created[1].resolve(losing_room)
	_expect(_created.size() == 2 and _completed_events.size() == 1, "defeat: controller did not stop at room two", failures)
	if _completed_events.size() == 1:
		var summary := _completed_events[0]
		_expect(summary.outcome == "defeat" and int(summary.rooms_completed) == 1 and int(summary.ticks) == 12, "defeat: summary changed", failures)
		_expect(String(summary.failure_reason) == "enemy/charging_raider", "defeat: final room reason was not promoted", failures)
		_expect(String(summary.room_results[1].failure_reason) == "enemy/charging_raider" and int(summary.room_results[1].death_tick) == 37,
			"defeat: per-room death diagnostics were not retained", failures)
		_expect(int(summary.rewards.contract_wins_delta) == 0, "defeat: partial room wins granted a contract victory", failures)
	_destroy_controller(controller)


func _test_abandon(failures: Array[String]) -> void:
	var controller = _create_controller()
	controller.start_session(_config(2))
	controller.request_abandon()
	controller.request_abandon()
	_expect(_created[0].abandon_requests == 1, "abandon: request was not delegated exactly once", failures)
	_expect(_abandoned_events.size() == 1 and _abandoned_events[0].outcome == "abandoned" and int(_abandoned_events[0].room_results.size()) == 1, "abandon: summary signal changed", failures)
	_expect(_completed_events.is_empty(), "abandon: completed was also emitted", failures)
	if _abandoned_events.size() == 1:
		_expect(int(_abandoned_events[0].rewards.contract_wins_delta) == 0, "abandon: granted a contract victory", failures)
	_destroy_controller(controller)


func _test_room_start_error(failures: Array[String]) -> void:
	var controller = _create_controller()
	_factory_fail_after = 1
	controller.start_session(_config(2))
	_created[0].resolve(_result("victory", 1, 1.0, 1, 1, 1, 1, "legacy.drop", "Legacy Drop", "won room"))
	_expect(_completed_events.size() == 1 and _completed_events[0].outcome == "error", "error: failed next room did not finalize as error", failures)
	if _completed_events.size() == 1:
		_expect(int(_completed_events[0].rewards.contract_wins_delta) == 0, "error: granted a contract victory", failures)
	_destroy_controller(controller)


func _test_duplicate_signal_guard(failures: Array[String]) -> void:
	var controller = _create_controller()
	controller.start_session(_config(2))
	var first := _created[0]
	first.resolve(_result("victory", 1, 1.0, 1, 1, 0, 0, "", "", ""))
	first.resolve(_result("victory", 100, 100.0, 100, 100, 0, 0, "", "", ""))
	_created[1].resolve(_result("victory", 2, 2.0, 2, 2, 0, 0, "", "", ""))
	_created[1].resolve(_result("defeat", 100, 100.0, 100, 100, 0, 0, "", "", ""))
	controller.request_abandon()
	_expect(_completed_events.size() == 1 and _abandoned_events.is_empty(), "duplicates: terminal signals were not guarded", failures)
	if _completed_events.size() == 1:
		_expect(int(_completed_events[0].ticks) == 3 and int(_completed_events[0].room_results.size()) == 2, "duplicates: stale result entered summary", failures)
	_destroy_controller(controller)


func _test_invalid_plans(failures: Array[String]) -> void:
	var bad_count = _create_controller()
	_expect(bad_count.start_session(_config(0)) == {"ok": false, "error": "invalid_room_count"}, "validation: room count error changed", failures)
	_expect(bad_count.start_session(_config(1)) == {"ok": false, "error": "already_started"}, "validation: start was not one-shot", failures)
	_destroy_controller(bad_count)

	var bad_length = _create_controller()
	var length_config := _config(2)
	length_config["room_plan"] = {"rooms": [{"id": "only"}]}
	_expect(bad_length.start_session(length_config) == {"ok": false, "error": "invalid_room_plan"}, "validation: plan length error changed", failures)
	_expect(_created.is_empty(), "validation: invalid plan created an runtime", failures)
	_destroy_controller(bad_length)

	var bad_type = _create_controller()
	var type_config := _config(1)
	type_config["room_plan"] = {"rooms": "not-an-array"}
	_expect(bad_type.start_session(type_config) == {"ok": false, "error": "invalid_room_plan"}, "validation: plan type error changed", failures)
	_destroy_controller(bad_type)


func _test_alias_isolation(failures: Array[String]) -> void:
	var controller = _create_controller()
	var config := _config(2)
	config["nested"] = {"value": 1}
	config["room_plan"] = {"rooms": [
		{"id": "first", "nested": {"value": 2}},
		{"id": "second", "nested": {"value": 3}},
	]}
	controller.start_session(config)
	config.nested.value = 9
	config.room_plan.rooms[0].nested.value = 9
	var config_copy: Dictionary = controller.current_config
	config_copy.nested.value = 8
	_expect(int(controller.current_config.nested.value) == 1, "aliases: config getter/input leaked", failures)
	_expect(int(_created[0].config.room.nested.value) == 2, "aliases: room input leaked into runtime config", failures)
	_created[0].resolve(_result("victory", 1, 1.0, 1, 1, 0, 0, "", "", "first done"))
	_room_events[0].room.nested.value = 8
	_expect(int(_created[1].config.room.nested.value) == 3, "aliases: room_changed payload leaked into runtime config", failures)
	var room_result := _result("victory", 1, 1.0, 1, 1, 0, 0, "", "", "done")
	room_result["nested"] = {"value": 4}
	_created[1].resolve(room_result)
	room_result.nested.value = 9
	_expect(int(_completed_events[0].room_results[1].nested.value) == 4, "aliases: room result input leaked into summary", failures)
	_destroy_controller(controller)


func _test_commit_port_orders_framework_commit(failures: Array[String]) -> void:
	var state = ApplicationStateScript.new()
	state.start_new_profile("ranger")
	state.prepare_contract({
		"contract_id": "handoff.test", "mode": "Manual", "seed": 9001, "room_count": 2,
		"resolved_build": state.resolved_build_snapshot(),
		"room_plan": {"rooms": [{"room_id": "handoff-a"}, {"room_id": "handoff-b"}]},
	})
	state.begin_session()
	var controller = _create_controller()
	var commit_port := CommitPortScript.new()
	commit_port.commit_callback = func(room_index: int, room_result: Dictionary) -> Dictionary:
		_event_log.append("commit:%d" % room_index)
		return state.commit_room_victory_and_resolve_next_build(room_index, room_result)
	controller.room_commit_port = commit_port
	var config := _config(2)
	config["room_plan"] = {"rooms": [{"id": "a"}, {"id": "b"}]}
	config["framework_context"] = {"active_build": state.profile.active_build, "resolved_build": {"build_fingerprint": "stale"}}
	_expect(bool(controller.start_session(config).get("ok", false)), "commit port: start failed", failures)
	_created[0].resolve(_handoff_victory([_handoff_loot(state, "handoff_loot_a")]))
	_expect(_event_log == ["start:0", "commit:0", "start:1"],
		"commit port: framework commit must run before room two starts (log=%s)" % str(_event_log), failures)
	var room_config: Dictionary = _created[1].config
	var framework: Dictionary = room_config.get("framework_context", {})
	_expect((framework.get("resolved_build", {}) as Dictionary) == (state.active_session.resolved_build as Dictionary),
		"commit port: room two did not receive the refreshed resolved build", failures)
	_expect(String((framework.get("resolved_build", {}) as Dictionary).get("build_fingerprint", "")) != "stale",
		"commit port: stale build leaked into room two", failures)
	_expect((framework.get("active_build", {}) as Dictionary) == (state.profile.active_build as Dictionary),
		"commit port: room two did not receive the active build", failures)
	# The final room never goes through the port: one victory summary settles.
	_created[1].resolve(_handoff_victory([_handoff_loot(state, "handoff_loot_b")]))
	_expect(_event_log == ["start:0", "commit:0", "start:1"], "commit port: final room must not call the port", failures)
	_expect(_completed_events.size() == 1 and String(_completed_events[0].outcome) == "victory",
		"commit port: two-room run did not finish as one victory", failures)
	_destroy_controller(controller)


func _test_commit_failure_blocks_next_room(failures: Array[String]) -> void:
	var controller = _create_controller()
	var commit_port := CommitPortScript.new()
	commit_port.commit_callback = func(_room_index: int, _room_result: Dictionary) -> Dictionary:
		return {"ok": false, "error": "room_index_mismatch"}
	controller.room_commit_port = commit_port
	controller.start_session(_config(2))
	_created[0].resolve(_handoff_victory([]))
	_expect(_created.size() == 1, "commit failure: next room must not start", failures)
	_expect(_completed_events.size() == 1 and String(_completed_events[0].outcome) == "error",
		"commit failure: run must finalize as an explicit error", failures)
	if _completed_events.size() == 1:
		var summary: Dictionary = _completed_events[0]
		var room_error: Dictionary = summary.room_results[1]
		_expect(String(room_error.get("error", "")) == "room_commit_failed"
			and String(room_error.get("commit_error", "")) == "room_index_mismatch",
			"commit failure: error result lost the commit diagnostics", failures)
		_expect(int(summary.rooms_completed) == 1 and int(summary.rewards.contract_wins_delta) == 0,
			"commit failure: failed handoff must not grant the contract win", failures)
	_destroy_controller(controller)


func _handoff_loot(state, instance_id: String) -> Dictionary:
	var item: Dictionary = (state.profile.inventory.equipment[0] as Dictionary).duplicate(true)
	item["instance_id"] = instance_id
	return item


func _handoff_victory(items: Array) -> Dictionary:
	return {
		"outcome": "victory",
		"ticks": 1,
		"elapsed_seconds": 0.1,
		"casts": 1,
		"defeated": 1,
		"report": "handoff",
		"rewards": {"contract_wins_delta": 1, "law_tallies_delta": {"inscribe": 0, "rewrite": 0, "refine": 0}},
		"room_loot_settlement": {
			"ok": true, "error": "", "outcome": "victory",
			"items": items.duplicate(true), "entities": [], "event_count": items.size(),
		},
	}


func _test_real_held_attack_between_rooms(failures: Array[String]) -> void:
	var state = ApplicationStateScript.new()
	state.start_new_profile("ranger")
	state.complete_tutorial()
	var plan: Dictionary = ContractPlanScript.build({"contract_id": "mainline_02_priority_under_pressure", "seed": 4242, "mode": "Manual"}).plan
	var config := {"contract_id": plan.contract_id, "mode": "Manual", "seed": 4242,
		"room_count": plan.room_count, "room_plan": plan,
		"framework_context": {"resolved_build": state.resolved_build_snapshot(), "active_build": state.profile.active_build}}
	for scenario: String in ["held", "released_before", "released_after", "paused", "pointer"]:
		var controller = ControllerScript.new() # Production runtime and Main, no FakeArena.
		var results: Array[Dictionary] = []
		controller.completed.connect(func(result: Dictionary) -> void: results.append(result.duplicate(true)))
		root.add_child(controller)
		var scenario_config := config.duplicate(true)
		if scenario == "pointer":
			# One real first-room target lets a continuously held explicit lock win the room.
			scenario_config.room_plan.rooms[0].enemy_ids = ["melee_pursuer"]
			# The authored priority_charge entry intentionally requires its full
			# charging_raider + melee roster. This input-routing fixture changes the
			# roster, so give it a distinct room identity and exercise the typed
			# roster-derived fallback instead of bypassing the authored mismatch gate.
			scenario_config.room_plan.rooms[0].room_id = "controller.pointer_fixture"
		elif scenario == "held":
			## 2026-10-10 whole-map fix: this scenario proves input continuity, so
			## room two keeps one real melee target. A fully stationary player can
			## no longer out-trade a ring-room fan_ranged that now holds its
			## preferred band steadily — the retired annulus perturbed enemy
			## locomotion — and survival balance must not leak into an input
			## routing assertion.
			scenario_config.room_plan.rooms[1].enemy_ids = ["melee_pursuer"]
		var started: Dictionary = controller.start_session(scenario_config)
		_expect(bool(started.get("ok", false)), "continuous input: real mainline02 deployment failed", failures)
		if not bool(started.get("ok", false)):
			controller.free()
			continue
		var runtime: Node = controller.get("_current_runtime")
		var first: Node = runtime.get("room_instance")
		first.set_process(false)
		if scenario == "pointer":
			first.presentation.world_view.begin_frame(Rect2(Vector2.ZERO, Vector2(1280, 720)), first.player_position, first._arena_rect())
			var point: Vector2 = first.presentation.world_view.gameplay_to_screen(first.enemies[0].position + Vector2(0.0, -22.0))
			_attack_pointer(point, true)
			_expect(first.input_adapter.manual_pointer_target_entity_id == 1, "continuous input: real pointer fixture did not lock enemy 1", failures)
		else:
			_attack_key(true) # One physical Space press; no repeated press events in either room.
		for tick in 1800:
			if first.battle_over:
				break
			first._simulate_tick()
		_expect(first.battle_victory and first.shots > 0, "continuous input: first real room did not clear", failures)
		if not first.battle_victory:
			_attack_key(false)
			controller.free()
			continue
		var first_casts: int = first.shots
		if scenario == "released_before":
			_attack_key(false) # A release after victory is ignored by old Main, but Input knows it.
		if scenario == "paused":
			controller.release_manual_controls() # Existing menu-open boundary.
			controller.process_mode = Node.PROCESS_MODE_DISABLED
			controller.release_manual_controls() # Existing menu-resume boundary; Space is still down.
			controller.process_mode = Node.PROCESS_MODE_INHERIT
		runtime._process(0.0) # Real completion signal creates the next production room.
		_expect(controller.current_room_index == 1, "continuous input: controller did not enter room two", failures)
		var second: Node = (controller.get("_current_runtime") as Node).get("room_instance")
		second.set_process(false)
		_expect(second.input_adapter.manual_pointer_target_entity_id == 0 and not second.input_adapter.manual_combat_input.snapshot().pointer_world_held,
			"continuous input: pointer lock or held mouse source crossed the room boundary", failures)
		if scenario == "released_after":
			_attack_key(false)
		if scenario == "held":
			for tick in 1800:
				if second.battle_over:
					break
				second._simulate_tick()
			(controller.get("_current_runtime") as Node)._process(0.0)
			_expect(second.battle_victory and second.shots > 0 and results.size() == 1
				and int(results[0].rooms_completed) == 2,
				"continuous input: held Space stopped firing across two real rooms", failures)
		else:
			for tick in 60:
				if second.battle_over:
					break
				second._simulate_tick()
			_expect(second.shots == 0 and not second.input_adapter.manual_combat_input.snapshot().assisted_held,
				"continuous input: %s left automatic fire in the next room" % scenario, failures)
		print("CONTINUOUS_ROOM_INPUT scenario=%s room1_casts=%d room2_casts=%d" % [scenario, first_casts, second.shots])
		if scenario == "paused":
			controller.request_abandon()
			var fresh = ControllerScript.new()
			root.add_child(fresh)
			var fresh_started: Dictionary = fresh.start_session(config)
			_expect(bool(fresh_started.get("ok", false)), "continuous input: fresh deployment after exit failed", failures)
			if bool(fresh_started.get("ok", false)):
				var fresh_main: Node = (fresh.get("_current_runtime") as Node).get("room_instance")
				fresh_main.set_process(false)
				for tick in 60:
					fresh_main._simulate_tick()
				_expect(fresh_main.shots == 0 and not fresh_main.input_adapter.manual_combat_input.snapshot().assisted_held,
					"continuous input: exit/new deployment restored still-held menu input", failures)
			fresh.free()
		_attack_key(false)
		_attack_pointer(Vector2(320.0, 240.0), false)
		controller.free()


func _attack_key(pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_SPACE
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _attack_pointer(point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = point
	event.global_position = point
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _create_controller():
	_created.clear()
	_completed_events.clear()
	_abandoned_events.clear()
	_room_events.clear()
	_factory_fail_after = -1
	_event_log.clear()
	var controller = ControllerScript.new()
	controller.room_runtime_factory = Callable(self, "_make_fake_arena")
	controller.completed.connect(_on_completed)
	controller.abandoned.connect(_on_abandoned)
	controller.room_changed.connect(_on_room_changed)
	root.add_child(controller)
	return controller


func _destroy_controller(controller: Node) -> void:
	if controller.get_parent() != null:
		controller.get_parent().remove_child(controller)
	controller.free()


func _make_fake_arena() -> Node:
	if _factory_fail_after >= 0 and _created.size() >= _factory_fail_after:
		return null
	var arena := FakeArena.new()
	arena.event_log = _event_log
	_created.append(arena)
	return arena


func _on_completed(result: Dictionary) -> void:
	_completed_events.append(result.duplicate(true))


func _on_abandoned(result: Dictionary) -> void:
	_abandoned_events.append(result.duplicate(true))


func _on_room_changed(room_index: int, count: int, room: Dictionary) -> void:
	_room_events.append({"room_index": room_index, "room_count": count, "room": room.duplicate(true)})


func _config(count: int) -> Dictionary:
	return {"contract_id": "contract.test", "mode": "Auto", "preset_id": "critical", "seed": 42, "room_count": count}


func _result(outcome: String, ticks: int, elapsed: float, casts: int, defeated: int, wins: int, inscribe: int, _drop_id: String, _drop_label: String, report: String, rewrite: int = 0, refine: int = 0) -> Dictionary:
	return {
		"outcome": outcome,
		"ticks": ticks,
		"elapsed_seconds": elapsed,
		"casts": casts,
		"defeated": defeated,
		"report": report,
		"rewards": {
			"contract_wins_delta": wins,
			"law_tallies_delta": {"inscribe": inscribe, "rewrite": rewrite, "refine": refine},
		},
	}


func _expect(condition: bool, message: String, failures: Array[String]) -> void: Assert.expect(condition, message, failures)
