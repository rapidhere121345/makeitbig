extends SceneTree

const CombatRoomRuntimeScript := preload("res://src/game/combat_room_runtime.gd")
const GameRootScript := preload("res://src/game/game_root.gd")
const EarlyItemRegistryScript := preload("res://src/content/early_item_registry.gd")
const BuildResolverScript := preload("res://src/systems/build_resolver.gd")
const ContentRegistryScript := preload("res://src/content/content_registry.gd")
const ProxyBuildScript := preload("res://src/systems/proxy_build.gd")
const ContractPlanScript := preload("res://src/game/contract_plan.gd")
const Assert := preload("res://tests/helpers/assert.gd")

const MAX_TICKS := 5400
const TICK_DELTA := 1.0 / 30.0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	_test_game_root_auto_contract(failures)
	var resolved_build := _resolved_build("calibration_exponential")
	var resolved_proxy_build := _resolved_proxy_build()
	_expect(not resolved_build.is_empty(), "auto flow: active Build did not resolve", failures)
	_expect(not resolved_proxy_build.is_empty(), "auto flow: proxy Build did not compile", failures)

	var plan_result := ContractPlanScript.build({
		"contract_id": "auto_certification",
		"mode": "Auto",
		"seed": 7301,
		"completed_node_ids": ["threshold_colossus"],
	})
	_expect(bool(plan_result.get("ok", false)), "auto flow: unlocked certification plan did not compile", failures)
	var plan: Dictionary = plan_result.get("plan", {}) if plan_result.get("plan", {}) is Dictionary else {}
	var rooms: Array = plan.get("rooms", []) if plan.get("rooms", []) is Array else []
	_expect(rooms.size() == 1 and String((rooms[0] as Dictionary).get("room_id", "")) == "auto_certification_clear",
		"auto flow: certification plan lost its authored room", failures)
	if rooms.is_empty():
		_finish(failures)
		return

	var runtime := CombatRoomRuntimeScript.new()
	var results: Array[Dictionary] = []
	runtime.completed.connect(func(result: Dictionary) -> void: results.append(result.duplicate(true)))
	root.add_child(runtime)
	var started := runtime.start_session({
		"contract_id": "auto_certification",
		"mode": "Auto",
		"seed": 7301,
		"room_index": 0,
		"room_count": 1,
		"presentation_enabled": false,
		"room": (rooms[0] as Dictionary).duplicate(true),
		"framework_context": {
			"contract_wins": 0,
			"active_build": {"preset_id": "exponential", "skills": ["piercing_arrow"]},
			"resolved_build": resolved_build,
			"resolved_proxy_build": resolved_proxy_build,
		},
	})
	_expect(bool(started.get("ok", false)), "auto flow: production room failed to start: %s" % str(started), failures)
	var arena_value: Variant = runtime.get("room_instance")
	if started.get("ok", false) and arena_value is Node:
		var arena := arena_value as Node
		runtime.set_process(false)
		arena.set_process(false)
		for _tick in MAX_TICKS:
			arena.call("_process", TICK_DELTA)
			runtime.call("_process", 0.0)
			if not results.is_empty():
				break
		_expect(String(arena.get("selected_mode")) == "Auto", "auto flow: mounted room changed the selected mode", failures)
		_expect(String(arena.get("proxy_prediction")) == "stable", "auto flow: resolved proxy prediction was not stable", failures)
		_expect(bool(arena.get("battle_over")), "auto flow: Auto did not reach a terminal room state", failures)
		_expect(bool(arena.get("battle_victory")), "auto flow: Auto room ended without victory", failures)
		_expect(results.size() == 1, "auto flow: production runtime did not emit one completed result", failures)
		if results.size() == 1:
			var result := results[0]
			_expect(String(result.get("outcome", "")) == "victory", "auto flow: room result was not victory", failures)
			_expect(int(result.get("defeated", 0)) >= 2, "auto flow: Auto victory did not account for both authored enemies", failures)
			_expect(int(result.get("casts", 0)) > 0 and int(result.get("arrow_hits", 0)) > 0,
				"auto flow: Auto victory did not produce authoritative combat activity", failures)
			_expect(String(result.get("mode", "")) == "Auto" and String(result.get("contract_id", "")) == "auto_certification",
				"auto flow: room result lost the Auto contract identity", failures)
			_expect(not result.has("room_loot_settlement") and not bool(arena.get("room_loot_enabled")),
				"auto flow: the authored certification content unexpectedly opened a loot window", failures)
	else:
		_expect(false, "auto flow: production room instance was unavailable", failures)

	if is_instance_valid(runtime):
		root.remove_child(runtime)
		runtime.free()
	_finish(failures)


func _test_game_root_auto_contract(failures: Array[String]) -> void:
	var save_directory := "user://makeitbig-auto-contract-flow-tests"
	_cleanup_save_directory(save_directory)
	var game := GameRootScript.new()
	game.save_directory_path = save_directory
	game.playtest_logging_enabled = false
	game.initialize(PackedStringArray())
	root.add_child(game)
	game.set_process(false)
	var setup_ok := bool(game.start_new_game("ranger").get("ok", false)) and bool(game.complete_tutorial().get("ok", false))
	_expect(setup_ok and game.current_route == "base", "auto flow: first-chapter profile did not reach the base", failures)
	if setup_ok:
		var state = game.application_state
		for node_id: String in [
			"mainline_01_first_hunt",
			"mainline_02_priority_under_pressure",
			"mainline_03_first_elite",
			"mainline_04_hazard_and_forge",
			"mainline_05_growth_gate",
			"threshold_colossus",
		]:
			state.prepare_contract({"contract_id": node_id, "mode": "Manual", "seed": 7300, "room_count": 1})
			state.begin_session()
			var settled: Dictionary = state.complete_session({"outcome": "victory"})
			_expect(bool(settled.get("ok", false)), "auto flow: prerequisite %s did not settle" % node_id, failures)
		_expect(state.is_auto_mode_unlocked(), "auto flow: threshold Boss settlement did not unlock Auto", failures)
		_expect(bool(game.return_to_title().get("ok", false)) and game.current_route == "title",
			"auto flow: progressed profile could not return to the title for continuation", failures)
		if game.get_parent() == root:
			root.remove_child(game)
		game.free()
		var resumed := GameRootScript.new()
		resumed.save_directory_path = save_directory
		resumed.playtest_logging_enabled = false
		resumed.initialize(PackedStringArray())
		root.add_child(resumed)
		resumed.set_process(false)
		game = resumed
		_expect(game.current_route == "title" and game.application_state.has_profile(),
			"auto flow: fresh GameRoot did not restore the first-chapter save", failures)
		_expect(bool(game.continue_game().get("ok", false)) and game.current_route == "base",
			"auto flow: first-chapter save continuation did not restore the base", failures)
		_expect(bool(game.open_contract().get("ok", false)) and game.current_route == "contract",
			"auto flow: contract board did not open after continuation", failures)
		var launch := game.launch_contract({
			"contract_id": "auto_certification",
			"mode": "Auto",
			"seed": 7302,
			"room_count": 1,
		})
		_expect(bool(launch.get("ok", false)) and game.current_route == "arena",
			"auto flow: unlocked Auto contract did not launch: %s" % str(launch), failures)
		if bool(launch.get("ok", false)):
			var controller := game.current_screen
			var runtime: Node = controller.get("_current_runtime") if controller != null else null
			var arena: Node = runtime.get("room_instance") if runtime != null else null
			_expect(controller != null and runtime != null and arena != null,
				"auto flow: GameRoot did not mount the real controller/runtime/arena chain", failures)
			if arena != null and runtime != null:
				controller.set_process(false)
				runtime.set_process(false)
				arena.set_process(false)
				for _tick in MAX_TICKS:
					arena.call("_process", TICK_DELTA)
					runtime.call("_process", 0.0)
					if game.current_route == "result":
						break
				_expect(game.current_route == "result", "auto flow: real Auto contract did not reach the result route", failures)
				var result: Dictionary = game.application_state.last_result
				_expect(String(result.get("outcome", "")) == "final_victory"
					and String(result.get("contract_id", "")) == "auto_certification"
					and String(result.get("mode", "")) == "Auto",
					"auto flow: real Auto settlement did not produce the graduation result", failures)
				_expect(bool(game.application_state.profile.progression.early_game_complete)
					and "auto_certification" in (game.application_state.profile.progression.completed_node_ids as Array),
					"auto flow: real Auto settlement did not complete the first chapter", failures)
	if is_instance_valid(game):
		if game.get_parent() == root:
			root.remove_child(game)
		game.free()
	_cleanup_save_directory(save_directory)


func _resolved_build(fixture_id: String) -> Dictionary:
	var registry := EarlyItemRegistryScript.new()
	if not registry.load_all().is_empty():
		return {}
	return BuildResolverScript.new(registry).resolve_fixture(fixture_id)


func _resolved_proxy_build() -> Dictionary:
	var registry := ContentRegistryScript.new()
	if not registry.load_all().is_empty():
		return {}
	var compiled: Dictionary = ProxyBuildScript.compile({
		"cores": ["near_enemy_horizon", "direct_gait", "single_key_execution", "short_trace_memory"],
	}, registry.cores)
	return (compiled.get("value", {}) as Dictionary).duplicate(true) if bool(compiled.get("ok", false)) else {}


func _expect(condition: bool, message: String, failures: Array[String]) -> void: Assert.expect(condition, message, failures)


func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print("PASS  test_auto_contract_flow.gd")
		quit(0)
		return
	for failure in failures:
		printerr("- %s" % failure)
	quit(1)


func _cleanup_save_directory(save_directory: String) -> void:
	var absolute_directory := ProjectSettings.globalize_path(save_directory)
	for file_name: String in ["save_a.json", "save_b.json", "save_a.json.tmp", "save_b.json.tmp"]:
		var path := absolute_directory.path_join(file_name)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	if DirAccess.dir_exists_absolute(absolute_directory):
		DirAccess.remove_absolute(absolute_directory)
