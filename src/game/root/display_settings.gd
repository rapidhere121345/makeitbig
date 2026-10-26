class_name DisplaySettings
extends RefCounted

## Display, audio and player-settings service extracted from GameRoot. This
## collaborator owns the language, render quality, menu scale and effects volume
## setters, the persisted display.cfg round trip, and the shared stage window
## lease, reaching owner state and presentation through the untyped owner
## reference.
const Locale = preload("res://src/localization/game_locale.gd")
const DisplayPolicyScript = preload("res://src/presentation/display_policy.gd")

var _root


func _init(root) -> void:
	_root = root


func _set_language(code: String) -> void:
	_root._language_code = Locale.select(code)
	if _root._pixel_stage != null and _root._session_menu != null and _root._session_menu.is_open():
		_root.get_presentation_viewport().render_target_update_mode = SubViewport.UPDATE_ONCE
	if _root._session_menu != null:
		_root._session_menu.sync_accessibility(_root._language_code, _root._menu_scale, _root._render_quality)
	_save_player_settings()


func _set_render_quality(value: String) -> void:
	_root._render_quality = value if value in ["native", "balanced", "fast"] else "balanced"
	if _root._pixel_stage != null:
		_root._pixel_stage.set_render_quality(_root._render_quality)
	if _root._session_menu != null:
		_root._session_menu.sync_accessibility(_root._language_code, _root._menu_scale, _root._render_quality)
	_save_player_settings()


func _set_menu_scale(value: float) -> void:
	_root._menu_scale = DisplayPolicyScript.parse_menu_scale(value)
	if _root._pixel_stage != null:
		_root._pixel_stage.set_menu_scale(_root._menu_scale)
	if _root._session_menu != null:
		_root._session_menu.sync_accessibility(_root._language_code, _root._menu_scale, _root._render_quality)
	_save_player_settings()


func _set_effects_volume(value: float) -> void:
	_root._effects_volume = clampf(value, 0.0, 1.0)
	_apply_route_preferences()
	_save_player_settings()


func _apply_route_preferences() -> void:
	if _root._current_screen != null and _root._current_screen.has_method("set_effects_volume"):
		_root._current_screen.call("set_effects_volume", _root._effects_volume)


## Usable size of the current screen, or ZERO (no upper bound) when it is unknown.
func _usable_display_size() -> Vector2i:
	if _root.usable_display_override != Vector2i.ZERO:
		return _root.usable_display_override
	if DisplayServer.get_name().to_lower().contains("headless"):
		return Vector2i.ZERO
	return DisplayServer.screen_get_usable_rect(_root.get_window().current_screen).size


func _apply_display_settings(resolution: Vector2i, fullscreen: bool) -> void:
	var usable := _usable_display_size()
	if resolution.x <= 0 or resolution.y <= 0:
		return
	resolution = DisplayPolicyScript.fit_window(resolution, usable)
	_root._windowed_resolution = resolution
	var window: Window = _root.get_window()
	if not DisplayServer.get_name().to_lower().contains("headless"):
		window.min_size = DisplayPolicyScript.MIN_WINDOW
		window.mode = Window.MODE_FULLSCREEN if fullscreen else Window.MODE_WINDOWED
		if not fullscreen:
			var origin := DisplayServer.screen_get_usable_rect(window.current_screen).position
			window.size = resolution
			window.position = origin + (usable - resolution) / 2
	if _root._session_menu != null:
		_root._session_menu.set_resolution_options(DisplayPolicyScript.menu_options(usable, resolution), resolution)
		_root._session_menu.sync_settings(resolution, fullscreen, _root._effects_volume)
	_save_player_settings(fullscreen)


func _load_player_settings() -> void:
	if _root._settings_loaded or _root._test_session:
		return
	_root._settings_loaded = true
	var config := ConfigFile.new()
	if config.load(_root.save_directory_path.path_join("display.cfg")) != OK:
		_apply_display_settings(_root._windowed_resolution, false)
		return
	var quality: Variant = config.get_value("display", "render_quality", "balanced")
	_root._render_quality = quality if quality in ["native", "balanced", "fast"] else "balanced"
	if _root._pixel_stage != null:
		_root._pixel_stage.set_render_quality(_root._render_quality)
	_root._language_code = Locale.select(config.get_value("interface", "language", "en"))
	_root._menu_scale = DisplayPolicyScript.parse_menu_scale(config.get_value("interface", "menu_scale", 1.0))
	if _root._pixel_stage != null:
		_root._pixel_stage.set_menu_scale(_root._menu_scale)
	var volume: Variant = config.get_value("audio", "effects", 0.45)
	if (volume is float or volume is int) and is_finite(float(volume)):
		_root._effects_volume = clampf(float(volume), 0.0, 1.0)
	_root._windowed_resolution = DisplayPolicyScript.parse_saved(
		config.get_value("display", "window", _root._windowed_resolution), _usable_display_size(), _root._windowed_resolution)
	var fullscreen: Variant = config.get_value("display", "fullscreen", false)
	_apply_display_settings(_root._windowed_resolution, fullscreen == true)


func _save_player_settings(fullscreen: Variant = null) -> void:
	if _root._test_session or not _root.is_inside_tree():
		return
	var config := ConfigFile.new()
	config.set_value("interface", "language", _root._language_code)
	config.set_value("interface", "menu_scale", _root._menu_scale)
	config.set_value("audio", "effects", _root._effects_volume)
	config.set_value("display", "window", _root._windowed_resolution)
	config.set_value("display", "render_quality", _root._render_quality)
	config.set_value("display", "fullscreen", _root.get_window().mode == Window.MODE_FULLSCREEN if fullscreen == null else fullscreen)
	var directory := ProjectSettings.globalize_path(_root.save_directory_path)
	if DirAccess.make_dir_recursive_absolute(directory) == OK:
		config.save(directory.path_join("display.cfg"))


func _acquire_stage_window() -> void:
	if _root._stage_window != null or DisplayServer.get_name().to_lower().contains("headless") or _root.get_viewport() != _root.get_window():
		return
	_root._stage_window = _root.get_window()
	var id: int = _root._stage_window.get_instance_id()
	if not _root._stage_window_leases.has(id):
		_root._stage_window_leases[id] = {"count": 0, "previous_mode": _root._stage_window.content_scale_mode}
	_root._stage_window_leases[id]["count"] += 1
	_root._stage_window.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED


func _release_stage_window() -> void:
	if _root._stage_window == null or not is_instance_valid(_root._stage_window):
		_root._stage_window = null
		return
	var id: int = _root._stage_window.get_instance_id()
	if _root._stage_window_leases.has(id):
		_root._stage_window_leases[id]["count"] -= 1
		if int(_root._stage_window_leases[id]["count"]) == 0:
			_root._stage_window.content_scale_mode = int(_root._stage_window_leases[id]["previous_mode"])
			_root._stage_window_leases.erase(id)
	_root._stage_window = null
