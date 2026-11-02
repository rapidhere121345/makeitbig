extends SceneTree
## Release/debug gating of the F10 test console and playtest logging
## (src/game/root/diagnostics_policy.gd).
##   godot --headless --path . --script res://tests/unit/test_diagnostics_policy.gd

const Policy := preload("res://src/game/root/diagnostics_policy.gd")
const Assert := preload("res://tests/helpers/assert.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var none := PackedStringArray()
	var console := PackedStringArray(["--test-console"])
	var log_on := PackedStringArray(["--playtest-log"])
	var log_off := PackedStringArray(["--playtest-log", "--no-playtest-log"])

	Assert.expect(Policy.test_console_enabled(none, true), "debug builds mount the console by default", failures)
	Assert.expect(not Policy.test_console_enabled(none, false), "release builds hide the console by default", failures)
	Assert.expect(Policy.test_console_enabled(console, false), "--test-console enables it in release", failures)

	Assert.expect(Policy.playtest_logging_enabled(none, false, true), "debug builds log playtests by default", failures)
	Assert.expect(not Policy.playtest_logging_enabled(none, false, false), "release builds do not log by default", failures)
	Assert.expect(Policy.playtest_logging_enabled(log_on, false, false), "--playtest-log enables logging in release", failures)
	Assert.expect(not Policy.playtest_logging_enabled(log_off, false, true), "--no-playtest-log always wins", failures)
	Assert.expect(not Policy.playtest_logging_enabled(log_on, true, true), "test sessions never log", failures)

	for message in failures:
		printerr(message)
	print("DIAGNOSTICS_POLICY ", "pass" if failures.is_empty() else "fail", " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
