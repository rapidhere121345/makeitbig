extends RefCounted

const GameRootScript = preload("res://src/game/game_root.gd")
const SaveStoreScript = preload("res://src/persistence/save_store.gd")

const TEST_ROOT: String = "user://makeitbig-prototype-debug-runtime-tests"
const REJECTED_SAVE_DIRECTORY: String = "user://makeitbig-prototype-debug-rejected"
const WHITE_PROXY_CORES: Array[String] = [
	"near_enemy_horizon",
	"direct_gait",
	"single_key_execution",
	"short_trace_memory",
]
const MAINLINE_NODE_IDS: Array[String] = [
	"mainline_01_first_hunt",
	"mainline_02_priority_under_pressure",
	"mainline_03_first_elite",
	"mainline_04_hazard_and_forge",
	"mainline_05_growth_gate",
]


class FakeArena:
	extends Node

	signal completed(result: Dictionary)
	signal abandoned(result: Dictionary)

	var config: Dictionary = {}
	var started: bool = false

	func start_session(value: Dictionary) -> Dictionary:
		if started:
			return {"ok": false, "error": "already_started"}
		started = true
		config = value.duplicate(true)
		return {"ok": true}

	func resolve(result: Dictionary) -> void:
		completed.emit(result.duplicate(true))


class FakePlaytestLog:
	extends RefCounted

	var events: Array[Dictionary] = []
	var active := false

	func start_session(context: Dictionary, _requested_session_id: String = "") -> Dictionary:
		active = true
		events.append({"event_id": "session_started", "payload": {}, "context": context.duplicate(true)})
		return {"ok": true}

	func record(event_id: String, payload: Dictionary = {}) -> Dictionary:
		if not active:
			return {"ok": false, "error": "session_not_started"}
		events.append({"event_id": event_id, "payload": payload.duplicate(true)})
		return {"ok": true}

	func finish(payload: Dictionary = {}) -> Dictionary:
		var recorded := record("session_finished", payload)
		active = false
		return recorded

	func is_active() -> bool:
		return active


func run() -> Array[String]:
	var failures: Array[String] = []
	_cleanup_test_root()
	_test_static_assertions(failures)
	_test_stage_ladder(failures)
	_test_no_stage_preserves_existing_debug_profile(failures)
	_test_force_item_valid(failures)
	_test_force_item_unknown_rejected(failures)
	_test_force_family_unknown_rejected(failures)
	_test_force_family_one_shot_drop_hit(failures)
	_test_force_family_drop_gate(failures)
	_test_negative_seed_suggested_and_manual_override(failures)
	_test_wipe_touches_only_debug_store(failures)
	_test_no_persist_writes_nothing(failures)
	_cleanup_test_root()
	return failures


func _test_static_assertions(failures: Array[String]) -> void:
	var game_root_source := _read_text("res://src/game/game_root.gd")
	_expect(not game_root_source.contains("preload(\"res://tools/"), "prototype debug: GameRoot must not preload tools/", failures)
	var directives_source := _read_text("res://tools/prototype_debug_directives.gd")
	_expect(not _declares_class_name(directives_source), "prototype debug: directives parser must not declare class_name", failures)
	var runtime_source := _read_text("res://tools/prototype_debug_runtime.gd")
	_expect(not _declares_class_name(runtime_source), "prototype debug: runtime must not declare class_name", failures)


func _test_stage_ladder(failures: Array[String]) -> void:
	for stage in ["fresh", "base", "pre_boss", "post_boss", "graduated"]:
		var directory := _case_dir("stage_" + stage)
		var game = _make_debug_game(directory, ["--mib-stage=" + stage])
		match stage:
			"fresh":
				_expect(not game.application_state.has_profile(), "prototype debug %s: fresh did not stay profile-less" % stage, failures)
				_expect(game.current_route == "title", "prototype debug %s: fresh did not route title" % stage, failures)
			"base":
				_expect(game.application_state.has_profile() and bool(game.application_state.profile.get("tutorial_complete", false)), "prototype debug %s: base profile/tutorial missing" % stage, failures)
				_expect(game.current_route == "base", "prototype debug %s: base did not route base" % stage, failures)
				var base_completed: Array = (game.application_state.profile.get("progression", {}) as Dictionary).get("completed_node_ids", [])
				_expect(base_completed == ["tutorial_ranger_basics"], "prototype debug base: wrong completed nodes %s" % [base_completed], failures)
				_expect(not game.application_state.is_auto_mode_unlocked(), "prototype debug base: Auto unlocked early", failures)
			"pre_boss":
				var pre_progression: Dictionary = (game.application_state.profile.get("progression", {}) as Dictionary)
				var pre_completed: Array = pre_progression.get("completed_node_ids", [])
				for node_id in MAINLINE_NODE_IDS:
					_expect(node_id in pre_completed, "prototype debug pre_boss: missing %s" % node_id, failures)
				_expect("threshold_colossus" not in pre_completed and "auto_certification" not in pre_completed, "prototype debug pre_boss: overshot the ladder", failures)
				_expect(not game.application_state.is_auto_mode_unlocked(), "prototype debug pre_boss: Auto unlocked early", failures)
				_expect(String((game.application_state.active_build_snapshot().get("active_build", {}) as Dictionary).get("preset_id", "")) == "exponential", "prototype debug pre_boss: not on calibration_exponential", failures)
				var pre_resolved: Dictionary = game.application_state.resolved_build_snapshot()
				var pre_training: Dictionary = (game.application_state.early_game_snapshot().get("training", {}) as Dictionary)
				var pre_fingerprint := String(pre_resolved.get("build_fingerprint", ""))
				var pre_reports: Dictionary = pre_training.get("reports_by_fingerprint", {}) as Dictionary
				var pre_report: Dictionary = pre_reports.get(pre_fingerprint, {}) as Dictionary
				_expect(not pre_fingerprint.is_empty() and String(pre_report.get("build_fingerprint", "")) == pre_fingerprint,
					"prototype debug pre_boss: training trial did not store an exact fingerprint report", failures)
				_expect(game.current_route == "base", "prototype debug pre_boss: did not route base", failures)
			"post_boss":
				var post_progression: Dictionary = (game.application_state.profile.get("progression", {}) as Dictionary)
				var post_completed: Array = post_progression.get("completed_node_ids", [])
				_expect("threshold_colossus" in post_completed and "auto_certification" not in post_completed, "prototype debug post_boss: wrong boss progression", failures)
				_expect(game.application_state.is_auto_mode_unlocked(), "prototype debug post_boss: Auto not unlocked", failures)
				var post_cores: Array = (game.application_state.profile.get("proxy_build", {}) as Dictionary).get("cores", [])
				_expect(post_cores == WHITE_PROXY_CORES, "prototype debug post_boss: white cores missing %s" % [post_cores], failures)
				_expect(not bool(post_progression.get("early_game_complete", false)) and not bool(post_progression.get("ending_unlocked", false)), "prototype debug post_boss: early game completed before Auto", failures)
				_expect(game.current_route == "base", "prototype debug post_boss: did not route base", failures)
			"graduated":
				var grad_progression: Dictionary = (game.application_state.profile.get("progression", {}) as Dictionary)
				var grad_completed: Array = grad_progression.get("completed_node_ids", [])
				_expect("auto_certification" in grad_completed, "prototype debug graduated: Auto certification missing", failures)
				_expect(String(game.application_state.last_result.get("outcome", "")) == "final_victory", "prototype debug graduated: not final_victory", failures)
				_expect(bool(grad_progression.get("ending_unlocked", false)) and bool(grad_progression.get("early_game_complete", false)), "prototype debug graduated: ending/early-game flags missing", failures)
				_expect(int(grad_progression.get("auto_contract_wins", 0)) >= 1, "prototype debug graduated: auto_contract_wins missing", failures)
				_expect(game.current_route == "base", "prototype debug graduated: did not route base", failures)
		_expect(String(game.prototype_debug_summary.get("stage", "")) == stage, "prototype debug %s: summary stage mismatch" % stage, failures)
		_destroy_game(game)


func _test_no_stage_preserves_existing_debug_profile(failures: Array[String]) -> void:
	var directory := _case_dir("preserve")
	var first = _make_debug_game(directory, ["--mib-stage=pre_boss"])
	_destroy_game(first)
	var second = _make_debug_game(directory, [])
	_expect(second.application_state.has_profile(), "prototype debug preserve: existing debug profile was not restored", failures)
	var completed: Array = (second.application_state.profile.get("progression", {}) as Dictionary).get("completed_node_ids", [])
	for node_id in MAINLINE_NODE_IDS:
		_expect(node_id in completed, "prototype debug preserve: profile was rebuilt (missing %s)" % node_id, failures)
	_expect(String(second.prototype_debug_summary.get("stage", "")) == "keep", "prototype debug preserve: has_stage=false rebuilt the profile", failures)
	_destroy_game(second)


func _test_force_item_valid(failures: Array[String]) -> void:
	var directory := _case_dir("force_item_valid")
	var game = _make_debug_game(directory, ["--mib-stage=base", "--mib-force-item=swift_recurve_bow"])
	var equipment: Array = (game.application_state.profile.get("inventory", {}) as Dictionary).get("equipment", [])
	var granted: Dictionary = {}
	for item_value in equipment:
		if item_value is Dictionary and String((item_value as Dictionary).get("base_item_id", "")) == "swift_recurve_bow":
			granted = item_value
			break
	_expect(not granted.is_empty(), "prototype debug force-item: granted item missing", failures)
	if not granted.is_empty():
		_expect(String(granted.get("slot", "")) == "main_hand", "prototype debug force-item: wrong slot", failures)
		var affixes_value: Variant = granted.get("affixes", null)
		_expect(affixes_value is Array and (affixes_value as Array).is_empty(), "prototype debug force-item: item must be affix-free", failures)
		_expect(String((granted.get("source", {}) as Dictionary).get("type", "")) == "debug_grant", "prototype debug force-item: wrong source type", failures)
		var instance_id := String(granted.get("instance_id", ""))
		_expect(_is_64_hex(instance_id), "prototype debug force-item: instance id is not 64 hex", failures)
		_expect(typeof(granted.get("law_seed", null)) == TYPE_INT, "prototype debug force-item: law_seed must be an integer", failures)
		var equipped_id := String((game.application_state.profile.get("active_build", {}) as Dictionary).get("equipped_item_ids", {}).get("main_hand", ""))
		_expect(equipped_id != instance_id, "prototype debug force-item: granted item was auto-equipped", failures)
	var profile_copy: Dictionary = game.application_state.profile
	var equipment_copy: Array = (profile_copy.get("inventory", {}) as Dictionary).get("equipment", [])
	equipment_copy.clear()
	_expect(not ((game.application_state.profile.get("inventory", {}) as Dictionary).get("equipment", []) as Array).is_empty(), "prototype debug force-item: profile getter copy aliased state", failures)
	_destroy_game(game)

	# Stability: regranting on the persisted profile must not duplicate the item.
	var resumed = _make_debug_game(directory, ["--mib-force-item=swift_recurve_bow"])
	var grant_count := 0
	for item_value in ((resumed.application_state.profile.get("inventory", {}) as Dictionary).get("equipment", []) as Array):
		if item_value is Dictionary and String((item_value as Dictionary).get("base_item_id", "")) == "swift_recurve_bow" and String(((item_value as Dictionary).get("source", {}) as Dictionary).get("type", "")) == "debug_grant":
			grant_count += 1
	_expect(grant_count == 1, "prototype debug force-item: regrant duplicated the stable item (%d)" % grant_count, failures)
	_destroy_game(resumed)


func _test_force_item_unknown_rejected(failures: Array[String]) -> void:
	var directory := _case_dir("force_item_unknown")
	var game = _make_rejecting_game(directory, ["--mib-stage=base", "--mib-force-item=bogus_item"], failures)
	_destroy_game(game)


func _test_force_family_unknown_rejected(failures: Array[String]) -> void:
	var directory := _case_dir("force_family_unknown")
	var game = _make_rejecting_game(directory, ["--mib-stage=base", "--mib-force-family=bogus_family"], failures)
	_destroy_game(game)


func _make_rejecting_game(directory: String, extra: Array[String], failures: Array[String]) -> Node:
	var game = GameRootScript.new()
	game.save_directory_path = directory
	game.room_runtime_factory = Callable(self, "_make_fake_arena")
	game.playtest_logging_enabled = false
	var flow_errors: Array[Dictionary] = []
	game.flow_error.connect(func(code: String, detail: String): flow_errors.append({"code": code, "detail": detail}))
	game.initialize(_pack(_debug_args(directory, extra)))
	_expect(bool(game.get("_prototype_debug_rejected")), "prototype debug rejection: %s was not rejected" % [extra], failures)
	_expect(game.current_route == "title" and not game.application_state.has_profile(), "prototype debug rejection: did not stay on empty title", failures)
	_expect(String(game.save_directory_path) == REJECTED_SAVE_DIRECTORY, "prototype debug rejection: did not isolate to the rejected directory", failures)
	var codes: Array[String] = []
	for entry in flow_errors:
		codes.append(String(entry.get("code", "")))
	_expect(codes.has("prototype_debug_rejected"), "prototype debug rejection: flow_error was not emitted", failures)
	return game


func _test_force_family_one_shot_drop_hit(failures: Array[String]) -> void:
	var directory := _case_dir("force_family_hit")
	var game = _make_debug_game(directory, ["--mib-stage=pre_boss", "--mib-force-family=carrier_power"])
	_expect(String(game.get("_prototype_debug_force_family")) == "carrier_power", "prototype debug force-family: pending override missing", failures)
	_expect(bool(game.open_contract().get("ok", false)), "prototype debug force-family: contract board did not open", failures)
	var launched: Dictionary = game.launch_contract({"contract_id": "side_targeted_equipment", "mode": "Manual", "preset_id": "exponential", "seed": 7, "room_count": 3})
	_expect(bool(launched.get("ok", false)) and game.current_route == "arena", "prototype debug force-family: contract did not launch", failures)
	var arena := game.current_screen as FakeArena
	if arena != null:
		var rooms: Array = (arena.config.get("room_plan", {}) as Dictionary).get("rooms", [])
		if not rooms.is_empty():
			var first_room: Dictionary = rooms[0]
			_expect(String(first_room.get("guarantee_family", "")) == "carrier_power", "prototype debug force-family: room lost guarantee_family", failures)
			_expect("equipment_general" in (first_room.get("drop_tags", []) as Array), "prototype debug force-family: room lost equipment_general tag", failures)
	_expect(String(game.get("_prototype_debug_force_family")).is_empty(), "prototype debug force-family: override was not cleared after begin_session", failures)
	if arena != null:
		arena.resolve({"outcome": "victory", "rooms_completed": 3, "ticks": 30, "elapsed_seconds": 1.0, "casts": 3, "defeated": 3, "rewards": {"contract_wins_delta": 1}})
	_expect(game.current_route == "result", "prototype debug force-family: contract did not settle", failures)
	var drops: Array = (game.application_state.last_result.get("rewards", {}) as Dictionary).get("equipment_drops", [])
	_expect(not drops.is_empty(), "prototype debug force-family: forced drop did not materialize", failures)
	for drop_value in drops:
		if drop_value is Dictionary:
			var affixes: Array = (drop_value as Dictionary).get("affixes", [])
			_expect(not affixes.is_empty() and String((affixes[0] as Dictionary).get("family_id", "")) == "carrier_power", "prototype debug force-family: drop missed the forced family", failures)
	_expect(bool(game.leave_result().get("ok", false)), "prototype debug force-family: result did not return to base", failures)
	_expect(bool(game.open_contract().get("ok", false)), "prototype debug force-family: second contract board did not open", failures)
	_expect(bool(game.launch_contract({"contract_id": "side_affix_and_law_tallies", "mode": "Manual", "preset_id": "exponential", "seed": 8, "room_count": 3}).get("ok", false)), "prototype debug force-family: second contract did not launch", failures)
	var second_arena := game.current_screen as FakeArena
	if second_arena != null:
		var second_rooms: Array = (second_arena.config.get("room_plan", {}) as Dictionary).get("rooms", [])
		if not second_rooms.is_empty():
			_expect(not (second_rooms[0] as Dictionary).has("guarantee_family"), "prototype debug force-family: one-shot override leaked into the next contract", failures)
	_destroy_game(game)


func _test_force_family_drop_gate(failures: Array[String]) -> void:
	var directory := _case_dir("force_family_gate")
	var game = _make_debug_game(directory, ["--mib-stage=base", "--mib-force-family=carrier_power"])
	_expect(bool(game.open_contract().get("ok", false)), "prototype debug force-family gate: contract board did not open", failures)
	_expect(bool(game.launch_contract({"contract_id": "mainline_01_first_hunt", "mode": "Manual", "preset_id": "convergent", "seed": 9, "room_count": 1}).get("ok", false)), "prototype debug force-family gate: contract did not launch", failures)
	var arena := game.current_screen as FakeArena
	if arena != null:
		arena.resolve({"outcome": "defeat", "rooms_completed": 1, "ticks": 10, "elapsed_seconds": 0.5, "casts": 2, "defeated": 2, "rewards": {"contract_wins_delta": 1}})
	_expect(game.current_route == "result", "prototype debug force-family gate: contract did not settle", failures)
	var drops: Array = (game.application_state.last_result.get("rewards", {}) as Dictionary).get("equipment_drops", [])
	_expect(drops.is_empty(), "prototype debug force-family gate: a forced family granted victory equipment on defeat", failures)
	_destroy_game(game)


func _test_negative_seed_suggested_and_manual_override(failures: Array[String]) -> void:
	var directory := _case_dir("negative_seed")
	var game = _make_debug_game(directory, ["--mib-stage=base", "--mib-seed=-42"])
	_expect(bool(game.get("_prototype_debug_has_seed")), "prototype debug seed: has_seed not recorded", failures)
	_expect(bool(game.open_contract().get("ok", false)), "prototype debug seed: contract board did not open", failures)
	var screen = game.current_screen
	screen.call("_build_ui")
	screen.call("_apply_presentation")
	var seed_edit = screen.get("_seed_edit")
	_expect(seed_edit != null and String(seed_edit.text) == "-42", "prototype debug seed: negative suggested seed did not reach ContractScreen", failures)
	if seed_edit != null:
		seed_edit.text = "777"
		screen.call("_on_start_pressed")
	_expect(game.current_route == "arena", "prototype debug seed: manual seed override did not launch", failures)
	var arena := game.current_screen as FakeArena
	_expect(arena != null and int(arena.config.get("seed", 0)) == 777, "prototype debug seed: manual seed override was ignored", failures)
	_destroy_game(game)


func _test_wipe_touches_only_debug_store(failures: Array[String]) -> void:
	var real_directory := _case_dir("wipe_real")
	var debug_directory := _case_dir("wipe_debug")
	var real_store = SaveStoreScript.new(real_directory)
	_expect(bool(real_store.save({"marker": "real"}).get("ok", false)), "prototype debug wipe: could not seed real-like store", failures)
	var debug_store = SaveStoreScript.new(debug_directory)
	_expect(bool(debug_store.save({"marker": "old-debug"}).get("ok", false)), "prototype debug wipe: could not seed debug store", failures)
	var real_path := ProjectSettings.globalize_path(real_directory).path_join("save_a.json")
	var real_before := _read_text(real_path)
	var game = _make_debug_game(debug_directory, ["--mib-wipe"])
	_expect(game.current_route == "title" and not game.application_state.has_profile(), "prototype debug wipe: did not boot empty after wipe", failures)
	_expect(not _has_save_files(debug_directory), "prototype debug wipe: debug store files remain", failures)
	_expect(FileAccess.file_exists(real_path) and _read_text(real_path) == real_before, "prototype debug wipe: real-like store was touched", failures)
	_destroy_game(game)


func _test_no_persist_writes_nothing(failures: Array[String]) -> void:
	var directory := _case_dir("no_persist")
	var logger := FakePlaytestLog.new()
	var game = GameRootScript.new()
	game.save_directory_path = directory
	game.room_runtime_factory = Callable(self, "_make_fake_arena")
	game.playtest_log = logger
	game.playtest_logging_enabled = true
	game.initialize(_pack(_debug_args(directory, ["--mib-stage=base", "--mib-no-persist"])))
	_expect(bool(game.get("_prototype_debug_no_persist")), "prototype debug no-persist: flag not recorded", failures)
	_expect(game.application_state.has_profile() and game.current_route == "base", "prototype debug no-persist: stage was not applied in memory", failures)
	_expect(not _has_save_files(directory), "prototype debug no-persist: save file was written", failures)
	_expect(logger.events.is_empty(), "prototype debug no-persist: playtest events were written", failures)
	_expect(bool(game.return_to_title().get("ok", false)), "prototype debug no-persist: return to title failed", failures)
	_expect(not _has_save_files(directory), "prototype debug no-persist: gameplay persisted a save", failures)
	_destroy_game(game)


func _make_debug_game(directory: String, extra: Array[String]):
	var game = GameRootScript.new()
	game.save_directory_path = directory
	game.room_runtime_factory = Callable(self, "_make_fake_arena")
	game.playtest_logging_enabled = false
	game.initialize(_pack(_debug_args(directory, extra)))
	return game


func _make_fake_arena() -> Node:
	return FakeArena.new()


func _debug_args(directory: String, extra: Array[String]) -> Array[String]:
	var arguments: Array[String] = ["--mib-debug", "--mib-save-dir=" + directory]
	arguments.append_array(extra)
	return arguments


func _case_dir(case_id: String) -> String:
	return TEST_ROOT.path_join(case_id)


func _pack(items: Array[String]) -> PackedStringArray:
	return PackedStringArray(items)


func _destroy_game(game: Node) -> void:
	game.free()


func _is_64_hex(value: String) -> bool:
	if value.length() != 64:
		return false
	for index in value.length():
		if value[index] not in "0123456789abcdef":
			return false
	return true


func _declares_class_name(source: String) -> bool:
	for line in source.split("\n"):
		var trimmed := line.strip_edges()
		if trimmed == "class_name" or trimmed.begins_with("class_name "):
			return true
	return false


func _has_save_files(directory: String) -> bool:
	var absolute_directory := ProjectSettings.globalize_path(directory)
	for file_name in ["save_a.json", "save_b.json", "save_a.json.tmp", "save_b.json.tmp"]:
		if FileAccess.file_exists(absolute_directory.path_join(file_name)):
			return true
	return false


func _read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	return file.get_as_text() if file != null else ""


func _cleanup_test_root() -> void:
	_remove_directory_tree(ProjectSettings.globalize_path(TEST_ROOT))


func _remove_directory_tree(absolute_path: String) -> void:
	var user_root := ProjectSettings.globalize_path("user://")
	if absolute_path.is_empty() or absolute_path == "/" or not absolute_path.begins_with(user_root):
		return
	if not DirAccess.dir_exists_absolute(absolute_path):
		return
	var directory := DirAccess.open(absolute_path)
	if directory == null:
		return
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
			var child := absolute_path.path_join(entry)
			if directory.current_is_dir():
				_remove_directory_tree(child)
			else:
				DirAccess.remove_absolute(child)
		entry = directory.get_next()
	directory.list_dir_end()
	DirAccess.remove_absolute(absolute_path)


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
