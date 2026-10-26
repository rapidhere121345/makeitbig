extends SceneTree

const TestConsoleScript = preload("res://src/presentation/test_console.gd")
const Assert := preload("res://tests/helpers/assert.gd")
const RAW_SENTINEL := "PRIVATE_RAW_SENTINEL"

var _provider_calls := 0
var _provider_revision := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	root.size = Vector2i(1280, 720)
	var console = TestConsoleScript.new()
	root.add_child(console)
	await process_frame
	await process_frame
	var console_root := console.find_child("TestConsoleRoot", true, false) as Control
	var panel := console.find_child("TestConsolePanel", true, false) as PanelContainer
	var body := console.find_child("SnapshotText", true, false) as TextEdit
	_expect(console_root != null and panel != null and body != null, "console: required panel nodes are missing", failures)
	if console_root == null or panel == null or body == null:
		_finish(console, failures)
		return

	console.configure(Callable(self, "_snapshot"))
	_test_hidden_default(console, console_root, body, failures)
	await _test_global_keys(console, console_root, body, failures)
	_test_refresh_and_provider(console, body, failures)
	_test_raw_data_stays_inside_open_panel(console, console_root, body, failures)
	_finish(console, failures)


func _test_hidden_default(console, console_root: Control, body: TextEdit, failures: Array[String]) -> void:
	_expect(not console.is_console_open(), "console: a new console is open by default", failures)
	_expect(not console_root.visible, "console: the hidden default still draws a root control", failures)
	_expect(console_root.mouse_filter == Control.MOUSE_FILTER_IGNORE, "console: the hidden default intercepts pointer input", failures)
	_expect(_provider_calls == 0, "console: the hidden default queried raw diagnostics", failures)
	_expect(body.text.is_empty(), "console: the hidden default retains diagnostic text", failures)


func _test_global_keys(console, console_root: Control, body: TextEdit, failures: Array[String]) -> void:
	root.push_input(_key(KEY_ESCAPE))
	await process_frame
	_expect(not console.is_console_open(), "console: Escape opened or changed a hidden console", failures)
	root.push_input(_key(KEY_F10))
	await process_frame
	_expect(console.is_console_open() and console_root.visible, "console: F10 did not open the console through global input", failures)
	_expect(console_root.mouse_filter == Control.MOUSE_FILTER_STOP, "console: the open surface does not own its input", failures)
	_expect(body.text.contains("PRIVATE_RAW_SENTINEL"), "console: opening did not render the provider snapshot", failures)
	root.push_input(_key(KEY_ESCAPE))
	await process_frame
	_expect(not console.is_console_open() and not console_root.visible, "console: Escape did not close an open console", failures)
	_expect(body.text.is_empty(), "console: closing left raw text in the hidden body", failures)


func _test_refresh_and_provider(console, body: TextEdit, failures: Array[String]) -> void:
	console.open_console()
	var calls_before_refresh := _provider_calls
	_provider_revision = 7
	console.refresh()
	_expect(_provider_calls == calls_before_refresh + 1, "console: refresh did not call the configured provider exactly once", failures)
	_expect(body.text.contains("revision-7"), "console: refresh did not replace the rendered snapshot", failures)
	for required_title: String in ["Route", "Window Resolution", "Logical Resolution", "Build ID", "Profile ID", "Training Report", "Raw Report", "Proxy Protocol", "Proxy Fingerprint", "Latest Settlement Raw Fields", "Test Flags", "Log Path", "Additional"]:
		_expect(body.text.contains(required_title), "console: required diagnostic category is absent: %s" % required_title, failures)
	_expect(body.get_theme_font_size("font_size") >= 18, "console: body text dropped below 18px", failures)
	_expect(body.wrap_mode == TextEdit.LINE_WRAPPING_BOUNDARY, "console: the snapshot body is not a readable wrapped region", failures)


func _test_raw_data_stays_inside_open_panel(console, console_root: Control, body: TextEdit, failures: Array[String]) -> void:
	_expect(_copy_outside_panel(console_root, panel_from(body)).find(RAW_SENTINEL) == -1, "console: raw diagnostic data escaped the open panel", failures)
	console.close_console()
	console.refresh()
	_expect(_copy_from_tree(console_root).find(RAW_SENTINEL) == -1, "console: raw diagnostic data remains outside the open panel", failures)


func _snapshot() -> Dictionary:
	_provider_calls += 1
	return {
		"route": "contract/arena",
		"window_resolution": Vector2i(1280, 720),
		"logical_resolution": Vector2i(640, 360),
		"build_id": "build-42",
		"profile_id": "profile-ranger",
		"training_report": {"tick": 120},
		"raw_report": RAW_SENTINEL,
		"proxy_protocol": "v2",
		"proxy_fingerprint": "fprint-7",
		"last_settlement_raw": {"reward": 12},
		"test_flags": ["headless"],
		"log_path": "user://playtest.log",
		"sections": [{"title": "Additional", "content": "revision-%d" % _provider_revision}],
	}


func _key(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	return event


func panel_from(body: TextEdit) -> Control:
	return body.get_parent().get_parent() as Control


func _copy_outside_panel(node: Node, panel: Control) -> String:
	if node == panel:
		return ""
	var copy := _node_copy(node)
	for child in node.get_children():
		copy += _copy_outside_panel(child, panel)
	return copy


func _copy_from_tree(node: Node) -> String:
	var copy := _node_copy(node)
	for child in node.get_children():
		copy += _copy_from_tree(child)
	return copy


func _node_copy(node: Node) -> String:
	if node is Label:
		return (node as Label).text
	if node is Button:
		return (node as Button).text
	if node is TextEdit:
		return (node as TextEdit).text
	return ""


func _finish(console, failures: Array[String]) -> void:
	root.remove_child(console)
	console.free()
	if failures.is_empty():
		print("PASS  test_test_console.gd")
		quit(0)
		return
	for failure: String in failures:
		printerr("- %s" % failure)
	quit(1)


func _expect(condition: bool, message: String, failures: Array[String]) -> void: Assert.expect(condition, message, failures)
