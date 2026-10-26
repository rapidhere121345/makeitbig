class_name TestConsoleHost
extends RefCounted

## Test and verification surface extracted from GameRoot. This collaborator owns
## the F10 test console, the in-game session menu and its pause, resume and
## abandon handlers, and the raw F10 snapshot builder, reaching owner state and
## presentation through the untyped owner reference.
const SceneRouterScript = preload("res://src/game/scene_router.gd")
const ApplicationStateScript = preload("res://src/game/application_state.gd")
const TestConsoleScript = preload("res://src/presentation/test_console.gd")
const SessionMenuScript = preload("res://src/presentation/session_menu.gd")
const DisplayPolicyScript = preload("res://src/presentation/display_policy.gd")

var _root


func _init(root) -> void:
	_root = root


## Test and verification metadata has one opt-in home. The console lives on the
## root viewport rather than inside a routed SubViewport, so changing routes or
## presentation policies cannot duplicate it. It is hidden and does not query a
## snapshot until the tester presses F10.
func _ensure_test_console() -> void:
	if _root._test_console != null or not _root.is_inside_tree():
		return
	_root._test_console = TestConsoleScript.new()
	_root._test_console.name = "TestConsole"
	_root._test_console.layer = 100
	_root.add_child(_root._test_console)
	_root._test_console.call("configure", Callable(self, "_test_console_snapshot"))


func get_test_console() -> CanvasLayer:
	return _root._test_console


func get_session_menu() -> CanvasLayer:
	return _root._session_menu


func _ensure_session_menu() -> void:
	if _root._session_menu != null or not _root.is_inside_tree():
		return
	_root._session_menu = SessionMenuScript.new()
	_root._session_menu.name = "SessionMenu"
	# The console gets first refusal on Escape when it is open.
	_root.add_child(_root._session_menu)
	_root.move_child(_root._session_menu, _root._test_console.get_index() if _root._test_console != null else 0)
	_root._session_menu.opened.connect(_pause_current_route)
	_root._session_menu.resumed.connect(_resume_current_route)
	_root._session_menu.abandon_requested.connect(_abandon_from_menu)
	_root._session_menu.display_requested.connect(_root._apply_display_settings)
	_root._session_menu.effects_volume_changed.connect(_root._set_effects_volume)
	_root._session_menu.language_requested.connect(_root._set_language)
	_root._session_menu.menu_scale_requested.connect(_root._set_menu_scale)
	_root._session_menu.render_quality_requested.connect(_root._set_render_quality)
	_root._display_settings()._load_player_settings()
	_root._session_menu.set_route(_root.current_route)
	_root._session_menu.set_resolution_options(DisplayPolicyScript.menu_options(_root._usable_display_size(), _root._windowed_resolution), _root._windowed_resolution)
	_root._session_menu.sync_settings(_root._windowed_resolution, _root.get_window().mode == Window.MODE_FULLSCREEN, _root._effects_volume)
	_root._session_menu.sync_accessibility(_root._language_code, _root._menu_scale, _root._render_quality)
	_root._apply_route_preferences()


func _pause_current_route() -> void:
	if _root._current_screen == null or not is_instance_valid(_root._current_screen):
		return
	_root._menu_paused_screen = _root._current_screen
	_root._menu_previous_process_mode = _root._current_screen.process_mode
	if _root._current_screen.has_method("release_manual_controls"):
		_root._current_screen.call("release_manual_controls")
	# This stops the fixed clock at the route boundary. Time spent paused is not
	# added to it, and other mounted roots/test fixtures keep their own lifetime.
	_root._current_screen.process_mode = Node.PROCESS_MODE_DISABLED
	if _root._pixel_stage != null:
		_root.get_presentation_viewport().render_target_update_mode = SubViewport.UPDATE_ONCE


func _resume_current_route() -> void:
	if _root._pixel_stage != null:
		_root.get_presentation_viewport().render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	if is_instance_valid(_root._menu_paused_screen):
		if _root._menu_paused_screen.has_method("release_manual_controls"):
			_root._menu_paused_screen.call("release_manual_controls")
		_root._menu_paused_screen.process_mode = _root._menu_previous_process_mode
	_root._menu_paused_screen = null


func _abandon_from_menu() -> void:
	if _root.current_route == SceneRouterScript.ROUTE_ARENA and _root._current_screen != null and _root._current_screen.has_method("request_abandon"):
		_root._current_screen.call("request_abandon")


func _refresh_test_console() -> void:
	if _root._test_console != null \
		and _root._test_console.has_method("is_console_open") \
		and bool(_root._test_console.call("is_console_open")):
		_root._test_console.call("refresh")


## Raw ids, fingerprints, deterministic seeds, protocol unions and settlement
## payloads are useful to testers but are not game copy. Screens keep the human
## reading; F10 exposes this exact snapshot when a reproduction needs it.
func _test_console_snapshot() -> Dictionary:
	var window_size := Vector2i.ZERO
	if _root.is_inside_tree() and _root.get_window() != null:
		window_size = _root.get_window().size
	var layout: Dictionary = _root._pixel_stage.call("layout_snapshot") if _root._pixel_stage != null else {}
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
			"test_session": _root._test_session,
			"auto_smoke": _root._auto_smoke_session,
			"capture": not _root._capture_request.is_empty(),
			"prototype_debug": not _root._prototype_debug_dto.is_empty(),
			"presentation_enabled": _root._presentation_enabled,
		},
		"log_path": _root.playtest_log.call("log_path") if _root.playtest_log != null and _root.playtest_log.has_method("log_path") else "",
		"sections": [
			{"title": "Full current contract data", "content": _root._last_contract.duplicate(true)},
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
