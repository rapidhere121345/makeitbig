extends SceneTree

const GAME_ROOT_SCENE = preload("res://src/game/game_root.tscn")
const TEST_DIRECTORY: String = "user://makeitbig-game-flow-smoke"

class FakeArena:
	extends Node

	signal completed(result: Dictionary)
	signal abandoned(result: Dictionary)

	var config: Dictionary = {}

	func start_session(value: Dictionary) -> Dictionary:
		config = value.duplicate(true)
		return {"ok": true}

	func resolve(outcome: String = "victory") -> void:
		completed.emit({
			"outcome": outcome,
			"ticks": 60,
			"elapsed_seconds": 2.0,
			"casts": 3,
			"defeated": 7,
			"report": "Framework smoke encounter resolved.",
			"rewards": {
				"contract_wins_delta": 1,
				"law_tallies_delta": {"inscribe": 1, "rewrite": 0, "refine": 0},
			},
		})


func _initialize() -> void:
	call_deferred("_run_smoke")


func _run_smoke() -> void:
	_cleanup_test_directory()
	var game = GAME_ROOT_SCENE.instantiate()
	game.save_directory_path = TEST_DIRECTORY
	game.room_runtime_factory = Callable(self, "_make_fake_arena")
	game.playtest_logging_enabled = false
	root.add_child(game)
	var failure := ""
	if game.current_route != "title":
		failure = "fresh boot did not reach title"
	elif not bool(game.start_new_game("ranger").get("ok", false)):
		failure = "new game failed"
	elif not bool(game.complete_tutorial().get("ok", false)):
		failure = "tutorial completion failed"
	elif not bool(game.open_facility("loadout").get("ok", false)):
		failure = "loadout launch failed"
	elif not bool(game.request_facility_action("loadout", "select_ranger_build", {"preset_id": "exponential"}).get("ok", false)):
		failure = "exponential Build selection failed"
	elif String(game.application_state.active_build_snapshot().active_build.preset_id) != "exponential":
		failure = "active Build snapshot did not retain exponential"
	elif not bool(game.leave_facility().get("ok", false)):
		failure = "loadout return failed"
	elif not bool(game.open_facility("training").get("ok", false)):
		failure = "training launch failed"
	elif not bool(game.request_facility_action("training", "run_training_trial").get("ok", false)):
		failure = "training trial failed"
	elif not bool(game.leave_facility().get("ok", false)):
		failure = "training return failed"
	elif not bool(game.open_contract().get("ok", false)):
		failure = "contract prep failed"
	elif String(game.launch_contract({"contract_id": "auto_certification", "mode": "Auto", "preset_id": "critical", "seed": 1, "room_count": 1}).get("error", "")) != "proxy_locked" or game.current_route != "contract":
		failure = "fresh profile bypassed Auto lock"
	elif not bool(game.launch_contract({"contract_id": "mainline_01_first_hunt", "mode": "Manual", "preset_id": "critical", "seed": 52969, "room_count": 1}).get("ok", false)):
		failure = "Manual arena launch failed"
	elif not (game.current_screen is FakeArena):
		failure = "Manual arena was not mounted"
	else:
		var manual_arena := game.current_screen as FakeArena
		var manual_context: Dictionary = manual_arena.config.framework_context
		if String(manual_arena.config.preset_id) != "exponential":
			failure = "caller overrode active Build preset"
		elif String((manual_context.active_build as Dictionary).preset_id) != "exponential":
			failure = "active Build snapshot was not injected"
		elif not (manual_context.get("resolved_proxy_build", null) is Dictionary) or not (manual_context.resolved_proxy_build as Dictionary).is_empty():
			failure = "Manual contract carried an invalid resolved proxy Build"
	if failure.is_empty():
		(game.current_screen as FakeArena).resolve()
		if game.current_route != "result":
			failure = "Manual result route failed"
		elif game.application_state.is_auto_mode_unlocked():
			failure = "ordinary Manual victory incorrectly unlocked Auto"
		elif not bool(game.leave_result().get("ok", false)) or game.current_route != "base":
			failure = "Manual result-to-base route failed"
	if failure.is_empty():
		var manual_nodes := [
			"mainline_02_priority_under_pressure",
			"mainline_03_first_elite",
			"mainline_04_hazard_and_forge",
			"mainline_05_growth_gate",
			"threshold_colossus",
		]
		for index in manual_nodes.size():
			var node_id: String = manual_nodes[index]
			if not bool(game.open_contract().get("ok", false)):
				failure = "could not open authored node %s" % node_id
				break
			var launched: Dictionary = game.launch_contract({"contract_id": node_id, "mode": "Manual", "preset_id": "convergent", "seed": 100 + index, "room_count": 1})
			if not bool(launched.get("ok", false)) or not (game.current_screen is FakeArena):
				failure = "authored node did not mount arena: %s" % node_id
				break
			(game.current_screen as FakeArena).resolve()
			if game.current_route != "result":
				failure = "authored node did not settle: %s" % node_id
				break
			if node_id != "threshold_colossus" and game.application_state.is_auto_mode_unlocked():
				failure = "pre-Boss node unlocked Auto: %s" % node_id
				break
			if not bool(game.leave_result().get("ok", false)) or game.current_route != "base":
				failure = "authored node did not return to base: %s" % node_id
				break
		if failure.is_empty() and not game.application_state.is_auto_mode_unlocked():
			failure = "threshold colossus victory did not unlock Auto"
	if failure.is_empty():
		game.open_contract()
		game.launch_contract({"contract_id": "auto_certification", "mode": "Auto", "preset_id": "convergent", "seed": 7, "room_count": 1})
		if not (game.current_screen is FakeArena):
			failure = "Auto encounter did not mount arena"
		elif String((game.current_screen as FakeArena).config.preset_id) != "exponential":
			failure = "Auto caller overrode active Build preset"
		else:
			(game.current_screen as FakeArena).resolve()
			if game.current_route != "result":
				failure = "Auto result route failed"
			elif not bool(game.application_state.profile.progression.early_game_complete):
				failure = "early-game completion did not settle"
			elif String(game.application_state.last_result.get("outcome", "")) != "final_victory":
				failure = "Auto graduation did not produce final_victory"
			elif not bool(game.open_ending().get("ok", false)) or game.current_route != "ending":
				failure = "Auto final victory did not open the ending"
			elif not bool(game.leave_ending_to_base().get("ok", false)) or game.current_route != "base":
				failure = "ending did not return to base"
	var routes: Array[String] = []
	for entry: Dictionary in game.scene_router.history:
		routes.append(String(entry.current_route))
	var expected := ["title", "tutorial", "base", "loadout", "base", "training", "base"]
	for _index in 6:
		expected.append_array(["contract", "arena", "result", "base"])
	expected.append_array(["contract", "arena", "result", "ending", "base"])
	if failure.is_empty() and routes != expected:
		failure = "route history mismatch: %s" % [routes]
	root.remove_child(game)
	game.free()
	if failure.is_empty():
		var resumed = GAME_ROOT_SCENE.instantiate()
		resumed.save_directory_path = TEST_DIRECTORY
		resumed.room_runtime_factory = Callable(self, "_make_fake_arena")
		resumed.playtest_logging_enabled = false
		root.add_child(resumed)
		var restored: Dictionary = resumed.application_state.early_game_snapshot()
		if resumed.current_route != "base":
			failure = "persisted safe route did not restore"
		elif String((restored.active_build as Dictionary).preset_id) != "exponential":
			failure = "persisted active Build did not restore"
		elif not _has_exact_training_report(restored, resumed.application_state.resolved_build_snapshot()):
			failure = "persisted training verification did not restore"
		elif not bool((restored.proxy as Dictionary).unlocked) or not bool((restored.progression as Dictionary).early_game_complete):
			failure = "persisted early-game completion did not restore"
		root.remove_child(resumed)
		resumed.free()
	_cleanup_test_directory()
	if not failure.is_empty():
		printerr("GAME_FLOW_SMOKE_FAIL %s" % failure)
		quit(1)
		return
	print("GAME_FLOW_SMOKE_PASS routes=%s" % [routes])
	quit(0)


func _make_fake_arena() -> Node:
	return FakeArena.new()


func _has_exact_training_report(snapshot: Dictionary, resolved: Dictionary) -> bool:
	var fingerprint := String(resolved.get("build_fingerprint", ""))
	var training: Dictionary = snapshot.get("training", {}) as Dictionary
	var reports: Dictionary = training.get("reports_by_fingerprint", {}) as Dictionary
	var report: Dictionary = reports.get(fingerprint, {}) as Dictionary
	return not fingerprint.is_empty() and String(report.get("build_fingerprint", "")) == fingerprint


func _cleanup_test_directory() -> void:
	var absolute_directory: String = ProjectSettings.globalize_path(TEST_DIRECTORY)
	for file_name in ["save_a.json", "save_b.json", "save_a.json.tmp", "save_b.json.tmp"]:
		var path: String = absolute_directory.path_join(file_name)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	if DirAccess.dir_exists_absolute(absolute_directory):
		DirAccess.remove_absolute(absolute_directory)
