class_name TestConsoleHost
extends RefCounted

## Test and verification surface extracted from GameRoot. This collaborator owns
## the F10 test console, the in-game session menu and its pause, resume and
## abandon handlers, and the raw F10 snapshot builder. It owns that state and
## reaches the shell through GameRoot's public API.
const SceneRouterScript = preload("res://src/game/scene_router.gd")
const ApplicationStateScript = preload("res://src/game/application_state.gd")
const TestConsoleScript = preload("res://src/presentation/test_console.gd")
const SessionMenuScript = preload("res://src/presentation/session_menu.gd")
const DisplayPolicyScript = preload("res://src/presentation/display_policy.gd")

## The hidden F10 console, created once the root is in the tree.
var test_console: CanvasLayer
## The in-game session menu, created once the root is in the tree.
var session_menu: CanvasLayer

var _root: GameRoot
var _menu_paused_screen: Node
var _menu_previous_process_mode: int = Node.PROCESS_MODE_INHERIT


func _init(root: GameRoot) -> void:
	_root = root


## Test and verification metadata has one opt-in home. The console lives on the
## root viewport rather than inside a routed SubViewport, so changing routes or
## presentation policies cannot duplicate it. It is hidden and does not query a
## snapshot until the tester presses F10.
func ensure_test_console() -> void:
	if test_console != null or not _root.is_inside_tree():
		return
	test_console = TestConsoleScript.new()
	test_console.name = "TestConsole"
	test_console.layer = 100
	_root.add_child(test_console)
	test_console.call("configure", Callable(self, "_test_console_snapshot"))


## True while the session menu is open, which pauses the deferred route clock.
func is_session_menu_open() -> bool:
	return session_menu != null and session_menu.is_open()


## Opens the session menu when it exists, e.g. when the window loses focus.
func open_session_menu() -> void:
	if session_menu != null:
		session_menu.open_menu()


## Closes the session menu and tells it which route is now current.
func sync_route(route: String) -> void:
	if session_menu != null:
		session_menu.close_menu()
		session_menu.set_route(route)


func ensure_session_menu() -> void:
	if session_menu != null or not _root.is_inside_tree():
		return
	session_menu = SessionMenuScript.new()
	session_menu.name = "SessionMenu"
	# The console gets first refusal on Escape when it is open.
	_root.add_child(session_menu)
	_root.move_child(session_menu, test_console.get_index() if test_console != null else 0)
	session_menu.opened.connect(_pause_current_route)
	session_menu.resumed.connect(resume_current_route)
	session_menu.abandon_requested.connect(_abandon_from_menu)
	session_menu.quit_requested.connect(func() -> void: _root.request_exit(0, "quit_to_desktop"))
	session_menu.display_requested.connect(_root.display_settings.apply_display_settings)
	session_menu.effects_volume_changed.connect(_root.display_settings.set_effects_volume)
	session_menu.language_requested.connect(_root.display_settings.set_language)
	session_menu.menu_scale_requested.connect(_root.display_settings.set_menu_scale)
	session_menu.render_quality_requested.connect(_root.display_settings.set_render_quality)
	_root.display_settings.load_player_settings()
	session_menu.set_route(_root.current_route)
	session_menu.set_resolution_options(DisplayPolicyScript.menu_options(_root.display_settings.usable_display_size(), _root.display_settings.windowed_resolution), _root.display_settings.windowed_resolution)
	session_menu.sync_settings(_root.display_settings.windowed_resolution, _root.get_window().mode == Window.MODE_FULLSCREEN, _root.display_settings.effects_volume)
	session_menu.sync_accessibility(_root.display_settings.language_code, _root.display_settings.menu_scale, _root.display_settings.render_quality)
	_root.display_settings.apply_route_preferences()


func _pause_current_route() -> void:
	if _root.current_screen == null or not is_instance_valid(_root.current_screen):
		return
	_menu_paused_screen = _root.current_screen
	_menu_previous_process_mode = _root.current_screen.process_mode
	if _root.current_screen.has_method("release_manual_controls"):
		_root.current_screen.call("release_manual_controls")
	# This stops the fixed clock at the route boundary. Time spent paused is not
	# added to it, and other mounted roots/test fixtures keep their own lifetime.
	_root.current_screen.process_mode = Node.PROCESS_MODE_DISABLED
	if _root.get_pixel_stage() != null:
		_root.get_presentation_viewport().render_target_update_mode = SubViewport.UPDATE_ONCE


func resume_current_route() -> void:
	if _root.get_pixel_stage() != null:
		_root.get_presentation_viewport().render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	if is_instance_valid(_menu_paused_screen):
		if _menu_paused_screen.has_method("release_manual_controls"):
			_menu_paused_screen.call("release_manual_controls")
		_menu_paused_screen.process_mode = _menu_previous_process_mode
	_menu_paused_screen = null


func _abandon_from_menu() -> void:
	if _root.current_route == SceneRouterScript.ROUTE_ARENA and _root.current_screen != null and _root.current_screen.has_method("request_abandon"):
		_root.current_screen.call("request_abandon")


func refresh_test_console() -> void:
	if test_console != null \
		and test_console.has_method("is_console_open") \
		and bool(test_console.call("is_console_open")):
		test_console.call("refresh")


## Raw ids, fingerprints, deterministic seeds, protocol unions and settlement
## payloads are useful to testers but are not game copy. Screens keep the human
## reading; F10 exposes this exact snapshot when a reproduction needs it.
func _test_console_snapshot() -> Dictionary:
	var window_size := Vector2i.ZERO
	if _root.is_inside_tree() and _root.get_window() != null:
		window_size = _root.get_window().size
	var layout: Dictionary = _root.get_pixel_stage().call("layout_snapshot") if _root.get_pixel_stage() != null else {}
	var logical_size: Vector2i = layout.get("ui_logic_size", Vector2i(1280, 720))
	var snapshot := {
		"route": _root.current_route,
		"window_resolution": "%d × %d" % [window_size.x, window_size.y],
		"logical_resolution": "%d × %d · %s · %.3fx" % [
			logical_size.x,
			logical_size.y,
			String(layout.get("policy", "unmounted")),
			float(layout.get("ui_scale", 1.0)),
		],
		"build_id": "profile-schema-%d · Godot %s" % [
			ApplicationStateScript.SCHEMA_VERSION,
			String(Engine.get_version_info().get("string", "unknown")),
		],
		"test_flags": {
			"test_session": _root.is_test_session(),
			"auto_smoke": _root.auto_smoke.session,
			"capture": not _root.capture.request.is_empty(),
			"prototype_debug": not _root.prototype_debug.dto.is_empty(),
			"presentation_enabled": _root.presentation_enabled,
		},
		"log_path": _root.playtest_log.call("log_path") if _root.playtest_log != null and _root.playtest_log.has_method("log_path") else "",
		"sections": [
			{"title": "Full current contract data", "content": _root.last_contract},
			{"title": "Presentation layout", "content": layout.duplicate(true)},
		],
	}
	if _root.application_state == null or not _root.application_state.has_profile():
		snapshot["profile_id"] = "No profile created"
		snapshot["last_settlement_raw"] = {}
		return snapshot
	var profile_snapshot: Dictionary = _root.application_state.profile
	var progression: Dictionary = profile_snapshot.get("progression", {}) if profile_snapshot.get("progression", null) is Dictionary else {}
	snapshot["profile_id"] = "%s · wins=%d · auto=%d" % [
		String(profile_snapshot.get("initial_class", "unknown")),
		int(progression.get("contract_wins", 0)),
		int(progression.get("auto_contract_wins", 0)),
	]
	var resolved: Dictionary = _root.application_state.resolved_build_snapshot()
	var fingerprint := String(resolved.get("build_fingerprint", ""))
	var training: Dictionary = profile_snapshot.get("training", {}) if profile_snapshot.get("training", null) is Dictionary else {}
	var reports: Dictionary = training.get("reports_by_fingerprint", {}) if training.get("reports_by_fingerprint", null) is Dictionary else {}
	var matched_report: Dictionary = reports.get(fingerprint, {}) if reports.get(fingerprint, null) is Dictionary else {}
	snapshot["training_report"] = matched_report.duplicate(true)
	snapshot["raw_report"] = {
		"build_fingerprint": fingerprint,
		"matched_report": matched_report.duplicate(true),
		"reports_by_fingerprint": reports.duplicate(true),
	}
	var proxy_snapshot: Dictionary = _root.application_state.resolved_proxy_build_snapshot()
	var resolved_proxy: Dictionary = proxy_snapshot.get("resolved_proxy_build", {}) if proxy_snapshot.get("resolved_proxy_build", null) is Dictionary else {}
	snapshot["proxy_protocol"] = resolved_proxy.duplicate(true)
	snapshot["proxy_fingerprint"] = String(resolved_proxy.get("semantic_fingerprint", ""))
	snapshot["last_settlement_raw"] = _root.application_state.last_result.duplicate(true)
	(snapshot["sections"] as Array).append({"title": "Full current build data", "content": resolved.duplicate(true)})
	(snapshot["sections"] as Array).append({
		"title": "Raw profile equipment and proxy data",
		"content": {
			"active_build": (profile_snapshot.get("active_build", {}) as Dictionary).duplicate(true) if profile_snapshot.get("active_build", null) is Dictionary else {},
			"inventory": (profile_snapshot.get("inventory", {}) as Dictionary).duplicate(true) if profile_snapshot.get("inventory", null) is Dictionary else {},
			"proxy_build": (profile_snapshot.get("proxy_build", {}) as Dictionary).duplicate(true) if profile_snapshot.get("proxy_build", null) is Dictionary else {},
		},
	})
	return snapshot
