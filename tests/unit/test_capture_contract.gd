extends SceneTree
## In-tree integration for the settlement capture harness: a real --auto-smoke
## replay with a fake arena proves the evidence frame is only ever taken after the
## Boss settlement, on the committed Result route, and that an environment which
## cannot draw a frame refuses instead of reporting a capture. No player save is
## touched and the auto-smoke runs under its own isolated test session.
const Game := preload("res://src/game/game_root.gd")
const TEST_DIRECTORY: String = "user://makeitbig-capture-contract-tests"

var failures: Array[String] = []


class FakeArena:
	extends Node

	signal completed(result: Dictionary)
	signal abandoned(result: Dictionary)

	var config: Dictionary = {}
	var started := false

	func start_session(value: Dictionary) -> Dictionary:
		if started:
			return {"ok": false, "error": "already_started"}
		started = true
		config = value.duplicate(true)
		return {"ok": true}

	func resolve(extra: Dictionary) -> void:
		var result := extra.duplicate(true)
		result["contract_id"] = String(config.get("contract_id", ""))
		result["mode"] = String(config.get("mode", ""))
		completed.emit(result)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var headless := DisplayServer.get_name().to_lower().contains("headless")
	var directory: String = ProjectSettings.globalize_path(TEST_DIRECTORY)
	var png_path: String = directory.path_join("boss-result.png")
	_remove(png_path)
	_remove(png_path + ".json")

	## A settlement capture refuses before it can draw anything.
	var probe := Game.new()
	probe.save_directory_path = TEST_DIRECTORY
	probe.playtest_logging_enabled = false
	probe.set("_capture_request", {
		"ok": true, "error": "", "detail": "",
		"capture_path": png_path, "capture_route": "", "capture_stage": "boss",
		"auto_smoke": true, "presentation_off": false,
	})
	var untimed: Dictionary = await probe._capture_settlement_stage("boss")
	_expect(not bool(untimed.get("ok", true)), "empty framework state was reported as a settled capture")
	_expect(String(untimed.get("error", "")) in ["headless_display", "route_mismatch"], "unsettled capture refused for the wrong reason: " + String(untimed.get("error", "")))
	_expect(not FileAccess.file_exists(png_path), "a refused capture still wrote a png")
	probe.free()

	var game := Game.new()
	game.save_directory_path = TEST_DIRECTORY
	game.playtest_logging_enabled = false
	game.arena_factory = func() -> Node: return FakeArena.new()
	var observed: Array[Dictionary] = []
	game.exit_code_hook = func(code: int, reason: String) -> void:
		observed.append({"code": code, "reason": reason, "route": game.current_route, "stage": game._auto_smoke_stage})
	var previous_time_scale := Engine.time_scale
	game.initialize(PackedStringArray(["--auto-smoke", "--capture-stage=boss", "--capture=" + png_path]))
	_expect(game.current_route == "arena", "the Boss contract was not launched: " + game.current_route)
	_expect(not FileAccess.file_exists(png_path), "a frame was captured before any settlement")
	root.add_child(game)
	var arena := game.current_screen as FakeArena
	_expect(arena != null and String(arena.config.get("contract_id", "")) == "threshold_colossus", "the mounted arena is not the Boss contract")
	if arena != null:
		arena.resolve({"outcome": "victory", "ticks": 1886, "rooms_completed": 1, "casts": 146, "defeated": 1})
	for _frame in 6:
		await process_frame
	Engine.time_scale = previous_time_scale

	if headless:
		_expect(not FileAccess.file_exists(png_path), "the headless refusal still wrote settlement evidence")
		var refusal: Dictionary = observed[0] if observed.size() == 1 else {}
		_expect(int(refusal.get("code", 0)) == 1, "the refused settlement capture did not exit non-zero")
		_expect(String(refusal.get("reason", "")).contains("headless_display"), "the headless refusal did not name the display: " + String(refusal.get("reason", "")))
		_expect(String(refusal.get("route", "")) == "result", "the capture gate fired outside Result: " + String(refusal.get("route", "")))
		_expect(String(refusal.get("stage", "")) == "boss", "the capture gate fired outside the Boss stage: " + String(refusal.get("stage", "")))
	else:
		_expect(FileAccess.file_exists(png_path), "the committed Result frame was not captured")
		_expect(FileAccess.file_exists(png_path + ".json"), "the settlement sidecar was not written next to the png")
		var evidence: Dictionary = _read_json(png_path + ".json")
		_expect(String(evidence.get("actual_route", "")) == "result" and String(evidence.get("actual_stage", "")) == "boss",
			"the sidecar lost its actual route or stage")
		_expect(String((evidence.get("settlement", {}) as Dictionary).get("contract_id", "")) == "threshold_colossus"
			and String((evidence.get("settlement", {}) as Dictionary).get("outcome", "")) == "victory",
			"the sidecar lost the settled Boss result")
		_expect(bool((evidence.get("progression", {}) as Dictionary).get("proxy_unlocked", false)),
			"the sidecar lost the progression the settlement produced")
		## The real Auto contract is deliberately left unresolved here: this suite
		## checks the Boss evidence gate, while the full replay hash stays with
		## scripts/test.sh.
	game.free()
	_remove(png_path)
	_remove(png_path + ".json")
	_cleanup_directory(directory)

	for failure: String in failures:
		printerr(failure)
	print("CAPTURE_CONTRACT ", "pass" if failures.is_empty() else "fail")
	quit(0 if failures.is_empty() else 1)


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}


func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _cleanup_directory(directory: String) -> void:
	_remove(directory.path_join("boss-result.png"))
	_remove(directory.path_join("boss-result.png.json"))
	if DirAccess.dir_exists_absolute(directory):
		DirAccess.remove_absolute(directory)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
