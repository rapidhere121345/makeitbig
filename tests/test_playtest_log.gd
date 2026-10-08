extends SceneTree

const PlaytestLogScript = preload("res://src/game/playtest_log.gd")
const TEST_DIRECTORY := "user://makeitbig-playtest-log-tests"
const TEST_SESSION_ID := "deterministic-test-session"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	_cleanup()
	var logger = PlaytestLogScript.new(TEST_DIRECTORY)
	var context := {"profile_id": "local", "content_version": 1, "build": "debug"}
	var started: Dictionary = logger.start_session(context, TEST_SESSION_ID)
	_expect(bool(started.get("ok", false)) and logger.is_active(), "playtest log: session did not start", failures)
	context["profile_id"] = "tampered"
	var route_payload := {"from": "title", "to": "tutorial"}
	var route_event: Dictionary = logger.record("route_changed", route_payload)
	route_payload["to"] = "tampered"
	var contract_event: Dictionary = logger.record("contract_finished", {
		"contract_id": "mainline_01_first_hunt",
		"outcome": "victory",
		"seed": 52969,
	})
	var finished: Dictionary = logger.finish({"reason": "test_complete"})
	_expect(bool(route_event.get("ok", false)) and bool(contract_event.get("ok", false)) and bool(finished.get("ok", false)), "playtest log: valid events were rejected", failures)
	_expect(not logger.is_active() and String(logger.record("late_event").get("error", "")) == "session_not_started", "playtest log: closed session accepted another event", failures)

	var absolute_path := ProjectSettings.globalize_path(String(started.get("path", "")))
	var lines := _read_lines(absolute_path)
	_expect(lines.size() == 4, "playtest log: expected four append-only events", failures)
	var expected_ids := ["session_started", "route_changed", "contract_finished", "session_finished"]
	for index in lines.size():
		var parsed: Variant = JSON.parse_string(lines[index])
		_expect(parsed is Dictionary, "playtest log: line %d is not valid JSON" % index, failures)
		if not parsed is Dictionary:
			continue
		var event: Dictionary = parsed
		_expect(int(event.get("schema_version", 0)) == 1 and int(event.get("sequence", -1)) == index, "playtest log: schema or sequence drifted at line %d" % index, failures)
		_expect(String(event.get("session_id", "")) == TEST_SESSION_ID and String(event.get("event_id", "")) == expected_ids[index], "playtest log: session or event id drifted at line %d" % index, failures)
		_expect(String((event.get("context", {}) as Dictionary).get("profile_id", "")) == "local", "playtest log: caller mutated stored context", failures)
	_expect(lines.size() < 2 or String(((JSON.parse_string(lines[1]) as Dictionary).payload as Dictionary).get("to", "")) == "tutorial", "playtest log: caller mutated stored payload", failures)

	var invalid = PlaytestLogScript.new(TEST_DIRECTORY)
	_expect(bool(invalid.start_session({}, "bad/session").get("ok", false)), "playtest log: invalid requested id should fall back to a generated safe id", failures)
	_expect(String(invalid.record("Bad Event!").get("error", "")) == "invalid_event_id", "playtest log: invalid event id was accepted", failures)
	invalid.finish()
	_cleanup()
	_finish(failures)


func _read_lines(path: String) -> Array[String]:
	var result: Array[String] = []
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return result
	while not file.eof_reached():
		var line := file.get_line()
		if not line.is_empty():
			result.append(line)
	file.close()
	return result


func _cleanup() -> void:
	var absolute_directory := ProjectSettings.globalize_path(TEST_DIRECTORY)
	if not DirAccess.dir_exists_absolute(absolute_directory):
		return
	var directory := DirAccess.open(absolute_directory)
	if directory == null:
		return
	for file_name in directory.get_files():
		if file_name.begins_with("session-") and file_name.ends_with(".jsonl"):
			DirAccess.remove_absolute(absolute_directory.path_join(file_name))
	DirAccess.remove_absolute(absolute_directory)


func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print("PASS  test_playtest_log.gd")
		quit(0)
		return
	for failure in failures:
		printerr("- %s" % failure)
	quit(1)


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
