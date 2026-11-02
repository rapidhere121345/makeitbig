class_name DiagnosticsPolicy
extends RefCounted
## Which player-visible diagnostics a session may start. Debug builds (the
## editor, tests and tooling) keep the F10 test console and playtest logging on
## by default. Release exports ship both but start them only on request:
## `--test-console` mounts the console and `--playtest-log` records a playtest
## log. `--no-playtest-log` and test sessions still turn logging off.

const TEST_CONSOLE_FLAG := "--test-console"
const PLAYTEST_LOG_FLAG := "--playtest-log"
const NO_PLAYTEST_LOG_FLAG := "--no-playtest-log"


static func test_console_enabled(arguments: PackedStringArray, debug_build: bool = OS.is_debug_build()) -> bool:
	return debug_build or arguments.has(TEST_CONSOLE_FLAG)


static func playtest_logging_enabled(arguments: PackedStringArray, test_session: bool, debug_build: bool = OS.is_debug_build()) -> bool:
	if test_session or arguments.has(NO_PLAYTEST_LOG_FLAG):
		return false
	return debug_build or arguments.has(PLAYTEST_LOG_FLAG)
