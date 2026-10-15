extends SceneTree

## Focused acceptance for the room-loot -> next-room build handoff slice:
## ApplicationState.commit_room_victory_and_resolve_next_build, the
## ContractRunController room_commit_port ordering, and the GameRoot wiring.

const ApplicationStateScript = preload("res://src/game/application_state.gd")
const ContractRunControllerScript = preload("res://src/game/contract_run_controller.gd")
const GameRootScript = preload("res://src/game/game_root.gd")


class FakeArena:
	extends Node

	signal completed(result: Dictionary)
	signal abandoned(result: Dictionary)

	var config: Dictionary = {}
	var started := false
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


var _arenas: Array = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	_test_boundary_commits_picked_loot_and_refreshes_build(failures)
	_test_boundary_rejections_stay_atomic(failures)
	_test_controller_orders_commit_before_next_room(failures)
	_test_controller_failed_commit_blocks_next_room(failures)
	_test_game_root_wires_port_to_application_state(failures)
	_test_full_two_room_run_settles_committed_loot_once(failures)
	if failures.is_empty():
		print("PASS  test_room_loot_build_handoff.gd")
		quit(0)
		return
	for failure in failures:
		printerr("- %s" % failure)
	quit(1)


func _test_boundary_commits_picked_loot_and_refreshes_build(failures: Array[String]) -> void:
	var state = _handoff_state()
	var inventory_size: int = (state.profile.inventory.equipment as Array).size()
	var active_before: Dictionary = state.profile.active_build
	var committed: Dictionary = state.commit_room_victory_and_resolve_next_build(
		0, _victory_result([_loot_instance(state, "handoff_loot_a")])
	)
	_expect(bool(committed.get("ok", false)), "boundary: room 0 commit failed: %s" % String(committed.get("error", "")), failures)
	_expect((committed.get("committed_items", []) as Array).size() == 1,
		"boundary: committed_items must carry the picked instance", failures)
	_expect((state.profile.inventory.equipment as Array).size() == inventory_size + 1,
		"boundary: inventory did not grow by exactly one", failures)
	_expect(state.profile.active_build == active_before, "boundary: commit must not auto-equip loot", failures)
	_expect(int(state.active_session.room_index) == 1, "boundary: session room_index did not advance", failures)
	var fingerprint := String((committed.get("resolved_build", {}) as Dictionary).get("build_fingerprint", ""))
	_expect(fingerprint.length() == 64
		and (state.active_session.resolved_build as Dictionary) == (committed.get("resolved_build", {}) as Dictionary),
		"boundary: session resolved_build did not adopt the refreshed build", failures)
	committed["resolved_build"] = {"build_fingerprint": "mutated"}
	_expect(String((state.active_session.resolved_build as Dictionary).get("build_fingerprint", "")) == fingerprint,
		"boundary: returned commit data aliases the session build", failures)


func _test_boundary_rejections_stay_atomic(failures: Array[String]) -> void:
	var fresh = ApplicationStateScript.new()
	fresh.start_new_profile("ranger")
	_expect(String(fresh.commit_room_victory_and_resolve_next_build(0, _victory_result([])).get("error", "")) == "active_session_required",
		"boundary: commit without an active session must fail", failures)
	var state = _handoff_state()
	_expect(bool(state.commit_room_victory_and_resolve_next_build(0, _victory_result([_loot_instance(state, "handoff_loot_a")])).get("ok", false)),
		"boundary: first room 0 commit must succeed", failures)
	var inventory_size: int = (state.profile.inventory.equipment as Array).size()
	var stale := _victory_result([_loot_instance(state, "handoff_loot_dup")])
	_expect(String(state.commit_room_victory_and_resolve_next_build(0, stale).get("error", "")) == "room_index_mismatch",
		"boundary: duplicate room 0 call must be rejected by the advanced cursor", failures)
	_expect(String(state.commit_room_victory_and_resolve_next_build(3, _victory_result([])).get("error", "")) == "room_index_mismatch",
		"boundary: wrong room index must be rejected", failures)
	_expect(String(state.commit_room_victory_and_resolve_next_build(1, {"outcome": "defeat"}).get("error", "")) == "room_victory_required",
		"boundary: non-victory room result must be rejected", failures)
	var failed_receipt := _victory_result([])
	(failed_receipt.room_loot_settlement as Dictionary)["ok"] = false
	_expect(String(state.commit_room_victory_and_resolve_next_build(1, failed_receipt).get("error", "")) == "invalid_room_loot_settlement",
		"boundary: failed settlement receipt must be rejected", failures)
	var unregistered := _victory_result([_loot_instance(state, "handoff_loot_bad")])
	((unregistered.room_loot_settlement as Dictionary).items as Array)[0].erase("affixes")
	_expect(String(state.commit_room_victory_and_resolve_next_build(1, unregistered).get("error", "")) == "invalid_room_loot_item",
		"boundary: loot failing registry validation must be rejected", failures)
	_expect((state.profile.inventory.equipment as Array).size() == inventory_size
		and int(state.active_session.room_index) == 1,
		"boundary: rejected commits must leave session and inventory untouched", failures)


func _test_controller_orders_commit_before_next_room(failures: Array[String]) -> void:
	var state = _handoff_state()
	var log: Array = []
	_arenas.clear()
	var controller = ContractRunControllerScript.new()
	controller.room_runtime_factory = func() -> Node:
		var arena := FakeArena.new()
		arena.event_log = log
		_arenas.append(arena)
		return arena
	controller.room_commit_port = func(room_index: int, room_result: Dictionary) -> Dictionary:
		log.append("commit:%d" % room_index)
		return state.commit_room_victory_and_resolve_next_build(room_index, room_result)
	var summary_events: Array[Dictionary] = []
	controller.completed.connect(func(result: Dictionary) -> void: summary_events.append(result.duplicate(true)))
	root.add_child(controller)
	var config := {
		"contract_id": "handoff.test", "mode": "Manual", "seed": 9001, "room_count": 2,
		"room_plan": {"rooms": [{"room_id": "handoff-a"}, {"room_id": "handoff-b"}]},
		"framework_context": {"active_build": state.profile.active_build, "resolved_build": state.active_session.resolved_build},
	}
	_expect(bool(controller.start_session(config).get("ok", false)), "controller: start failed", failures)
	_arenas[0].resolve(_victory_result([_loot_instance(state, "handoff_loot_a")]))
	_expect(log == ["start:0", "commit:0", "start:1"],
		"controller: framework commit must run before room two starts (log=%s)" % str(log), failures)
	var room_config: Dictionary = _arenas[1].config
	var framework: Dictionary = room_config.get("framework_context", {})
	_expect((framework.get("resolved_build", {}) as Dictionary) == (state.active_session.resolved_build as Dictionary),
		"controller: room two did not receive the refreshed resolved build", failures)
	_expect((framework.get("active_build", {}) as Dictionary) == (state.profile.active_build as Dictionary),
		"controller: room two did not receive the active build", failures)
	_arenas[1].resolve(_victory_result([_loot_instance(state, "handoff_loot_b")]))
	_expect(log == ["start:0", "commit:0", "start:1"], "controller: final room must not call the port", failures)
	_expect(summary_events.size() == 1 and String(summary_events[0].outcome) == "victory",
		"controller: two-room run did not finish as one victory", failures)
	_destroy(controller)


func _test_controller_failed_commit_blocks_next_room(failures: Array[String]) -> void:
	var state = _handoff_state()
	var log: Array = []
	_arenas.clear()
	var controller = ContractRunControllerScript.new()
	controller.room_runtime_factory = func() -> Node:
		var arena := FakeArena.new()
		arena.event_log = log
		_arenas.append(arena)
		return arena
	controller.room_commit_port = func(_room_index: int, _room_result: Dictionary) -> Dictionary:
		return {"ok": false, "error": "invalid_room_loot_settlement"}
	var summary_events: Array[Dictionary] = []
	controller.completed.connect(func(result: Dictionary) -> void: summary_events.append(result.duplicate(true)))
	root.add_child(controller)
	controller.start_session({
		"contract_id": "handoff.test", "mode": "Manual", "seed": 9001, "room_count": 2,
		"room_plan": {"rooms": [{"room_id": "handoff-a"}, {"room_id": "handoff-b"}]},
		"framework_context": {"active_build": state.profile.active_build, "resolved_build": state.active_session.resolved_build},
	})
	_arenas[0].resolve(_victory_result([]))
	_expect(_arenas.size() == 1, "controller: next room must not start after a failed commit", failures)
	_expect(summary_events.size() == 1 and String(summary_events[0].outcome) == "error",
		"controller: failed handoff must finalize an explicit error result", failures)
	if summary_events.size() == 1:
		var room_error: Dictionary = summary_events[0].room_results[1]
		_expect(String(room_error.get("error", "")) == "room_commit_failed",
			"controller: error result lost the room_commit_failed code", failures)
	_destroy(controller)


func _test_game_root_wires_port_to_application_state(failures: Array[String]) -> void:
	var game_root = GameRootScript.new()
	var bare = ApplicationStateScript.new()
	bare.start_new_profile("ranger")
	game_root.set("application_state", bare)
	var screen: Node = game_root._make_arena_screen()
	_expect(screen != null and screen.get_script() == ContractRunControllerScript,
		"wiring: production arena screen is not the contract controller", failures)
	if screen != null:
		var port: Callable = screen.get("room_commit_port")
		_expect(port.is_valid() and port.get_object() == bare,
			"wiring: room_commit_port is not bound to GameRoot's ApplicationState", failures)
		if port.is_valid():
			var rejected: Dictionary = port.call(0, {"outcome": "victory"})
			_expect(String(rejected.get("error", "")) == "active_session_required",
				"wiring: port call did not reach ApplicationState", failures)
		root.add_child(screen)
		_destroy(screen)
	game_root.free()


func _test_full_two_room_run_settles_committed_loot_once(failures: Array[String]) -> void:
	var state = _handoff_state()
	var log: Array = []
	_arenas.clear()
	var controller = ContractRunControllerScript.new()
	controller.room_runtime_factory = func() -> Node:
		var arena := FakeArena.new()
		arena.event_log = log
		_arenas.append(arena)
		return arena
	controller.room_commit_port = Callable(state, "commit_room_victory_and_resolve_next_build")
	var summary_events: Array[Dictionary] = []
	controller.completed.connect(func(result: Dictionary) -> void: summary_events.append(result.duplicate(true)))
	root.add_child(controller)
	controller.start_session({
		"contract_id": "handoff.test", "mode": "Manual", "seed": 9001, "room_count": 2,
		"room_plan": {"rooms": [{"room_id": "handoff-a"}, {"room_id": "handoff-b"}]},
		"framework_context": {"active_build": state.profile.active_build, "resolved_build": state.active_session.resolved_build},
	})
	_arenas[0].resolve(_victory_result([_loot_instance(state, "handoff_loot_a")]))
	_arenas[1].resolve(_victory_result([_loot_instance(state, "handoff_loot_b")]))
	var equipment: Array = state.profile.inventory.equipment
	_expect(_instance_count(equipment, "handoff_loot_a") == 1 and _instance_count(equipment, "handoff_loot_b") == 0,
		"handoff run: room 0 loot commits mid-run; final room loot waits for the settlement", failures)
	_expect(summary_events.size() == 1 and String(summary_events[0].get("outcome", "")) == "victory",
		"handoff run: two-room run did not finish as one victory summary", failures)
	var settled: Dictionary = state.complete_session(summary_events[0])
	_expect(bool(settled.get("ok", false)), "handoff run: contract settlement failed", failures)
	equipment = state.profile.inventory.equipment
	_expect(_instance_count(equipment, "handoff_loot_a") == 1 and _instance_count(equipment, "handoff_loot_b") == 1,
		"handoff run: complete_session duplicated committed loot", failures)
	var drops: Array = (settled.result.rewards as Dictionary).get("equipment_drops", [])
	_expect(drops.size() == 1 and String((drops[0] as Dictionary).get("instance_id", "")) == "handoff_loot_b",
		"handoff run: final settlement must report only the not-yet-committed final room loot", failures)
	_destroy(controller)


func _handoff_state():
	var state = ApplicationStateScript.new()
	state.start_new_profile("ranger")
	state.prepare_contract({
		"contract_id": "handoff.test",
		"mode": "Manual",
		"seed": 9001,
		"room_count": 2,
		"resolved_build": state.resolved_build_snapshot(),
		"room_plan": {"rooms": [{"room_id": "handoff-a"}, {"room_id": "handoff-b"}]},
	})
	state.begin_session()
	return state


func _loot_instance(state, instance_id: String) -> Dictionary:
	var item: Dictionary = (state.profile.inventory.equipment[0] as Dictionary).duplicate(true)
	item["instance_id"] = instance_id
	return item


func _victory_result(items: Array) -> Dictionary:
	return {
		"outcome": "victory",
		"room_loot_settlement": {
			"ok": true,
			"error": "",
			"outcome": "victory",
			"items": items.duplicate(true),
			"entities": [],
			"event_count": items.size(),
		},
	}


func _instance_count(equipment: Array, instance_id: String) -> int:
	var count := 0
	for item in equipment:
		if item is Dictionary and String((item as Dictionary).get("instance_id", "")) == instance_id:
			count += 1
	return count


func _destroy(node: Node) -> void:
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	node.free()


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
