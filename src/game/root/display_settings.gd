class_name DisplaySettings
extends RefCounted

## Display, audio and player-settings service extracted from GameRoot. This
## collaborator owns the language, render quality, menu scale and effects volume
## setters, the persisted display.cfg round trip, and the shared stage window
## lease. It owns that state and reaches the shell through GameRoot's public API.
const Locale = preload("res://src/localization/game_locale.gd")
const DisplayPolicyScript = preload("res://src/presentation/display_policy.gd")

## Multiple mounted roots occur in tests and tooling. Share the window lease so
## one exiting root cannot restore stretch underneath another live pixel stage.
static var _stage_window_leases: Dictionary = {}

var language_code := "en"
var menu_scale := 1.0
var render_quality := "balanced"
var effects_volume := 0.45
var windowed_resolution := Vector2i(1600, 900)
## Test hook: pretends the screen has this usable size. ZERO means ask the OS.
var usable_display_override := Vector2i.ZERO

var _root: GameRoot
var _settings_loaded := false
var _stage_window: Window


func _init(root: GameRoot) -> void:
	_root = root


func set_language(code: String) -> void:
	language_code = Locale.select(code)
	var menu := _root.get_session_menu()
	if _root.get_pixel_stage() != null and menu != null and menu.is_open():
		_root.get_presentation_viewport().render_target_update_mode = SubViewport.UPDATE_ONCE
	if menu != null:
		menu.sync_accessibility(language_code, menu_scale, render_quality)
	_save_player_settings()


func set_render_quality(value: String) -> void:
	render_quality = value if value in ["native", "balanced", "fast"] else "balanced"
	var stage := _root.get_pixel_stage()
	var menu := _root.get_session_menu()
	if stage != null:
		stage.set_render_quality(render_quality)
	if menu != null:
		menu.sync_accessibility(language_code, menu_scale, render_quality)
	_save_player_settings()


func set_menu_scale(value: float) -> void:
	menu_scale = DisplayPolicyScript.parse_menu_scale(value)
	var stage := _root.get_pixel_stage()
	var menu := _root.get_session_menu()
	if stage != null:
		stage.set_menu_scale(menu_scale)
	if menu != null:
		menu.sync_accessibility(language_code, menu_scale, render_quality)
	_save_player_settings()


func set_effects_volume(value: float) -> void:
	effects_volume = clampf(value, 0.0, 1.0)
	apply_route_preferences()
	_save_player_settings()


func apply_route_preferences() -> void:
	if _root.current_screen is ArenaRunNode:
		_root.current_screen.set_effects_volume(effects_volume)


## Usable size of the current screen, or ZERO (no upper bound) when it is unknown.
func usable_display_size() -> Vector2i:
	if usable_display_override != Vector2i.ZERO:
		return usable_display_override
	if DisplayServer.get_name().to_lower().contains("headless"):
		return Vector2i.ZERO
	return DisplayServer.screen_get_usable_rect(_root.get_window().current_screen).size


func apply_display_settings(resolution: Vector2i, fullscreen: bool) -> void:
	var usable := usable_display_size()
	if resolution.x <= 0 or resolution.y <= 0:
		return
	resolution = DisplayPolicyScript.fit_window(resolution, usable)
	windowed_resolution = resolution
	var window: Window = _root.get_window()
	if not DisplayServer.get_name().to_lower().contains("headless"):
		window.min_size = DisplayPolicyScript.MIN_WINDOW
		window.mode = Window.MODE_FULLSCREEN if fullscreen else Window.MODE_WINDOWED
		if not fullscreen:
			var origin := DisplayServer.screen_get_usable_rect(window.current_screen).position
			window.size = resolution
			window.position = origin + (usable - resolution) / 2
	var menu := _root.get_session_menu()
	if menu != null:
		menu.set_resolution_options(DisplayPolicyScript.menu_options(usable, resolution), resolution)
		menu.sync_settings(resolution, fullscreen, effects_volume)
	_save_player_settings(fullscreen)


func load_player_settings() -> void:
	if _settings_loaded or _root.is_test_session():
		return
	_settings_loaded = true
	var config := ConfigFile.new()
	if config.load(_root.save_directory_path.path_join("display.cfg")) != OK:
		apply_display_settings(windowed_resolution, false)
		return
	var quality: Variant = config.get_value("display", "render_quality", "balanced")
	render_quality = quality if quality in ["native", "balanced", "fast"] else "balanced"
	var stage := _root.get_pixel_stage()
	if stage != null:
		stage.set_render_quality(render_quality)
	language_code = Locale.select(config.get_value("interface", "language", "en"))
	menu_scale = DisplayPolicyScript.parse_menu_scale(config.get_value("interface", "menu_scale", 1.0))
	if stage != null:
		stage.set_menu_scale(menu_scale)
	var volume: Variant = config.get_value("audio", "effects", 0.45)
	if (volume is float or volume is int) and is_finite(float(volume)):
		effects_volume = clampf(float(volume), 0.0, 1.0)
	windowed_resolution = DisplayPolicyScript.parse_saved(
		config.get_value("display", "window", windowed_resolution), usable_display_size(), windowed_resolution)
	var fullscreen: Variant = config.get_value("display", "fullscreen", false)
	apply_display_settings(windowed_resolution, fullscreen == true)


func _save_player_settings(fullscreen: Variant = null) -> void:
	if _root.is_test_session() or not _root.is_inside_tree():
		return
	var config := ConfigFile.new()
	config.set_value("interface", "language", language_code)
	config.set_value("interface", "menu_scale", menu_scale)
	config.set_value("audio", "effects", effects_volume)
	config.set_value("display", "window", windowed_resolution)
	config.set_value("display", "render_quality", render_quality)
	config.set_value("display", "fullscreen", _root.get_window().mode == Window.MODE_FULLSCREEN if fullscreen == null else fullscreen)
	var directory := ProjectSettings.globalize_path(_root.save_directory_path)
	if DirAccess.make_dir_recursive_absolute(directory) == OK:
		config.save(directory.path_join("display.cfg"))


func acquire_stage_window() -> void:
	if _stage_window != null or DisplayServer.get_name().to_lower().contains("headless") or _root.get_viewport() != _root.get_window():
		return
	_stage_window = _root.get_window()
	var id: int = _stage_window.get_instance_id()
	if not _stage_window_leases.has(id):
		_stage_window_leases[id] = {"count": 0, "previous_mode": _stage_window.content_scale_mode}
	_stage_window_leases[id]["count"] += 1
	_stage_window.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED


func release_stage_window() -> void:
	if _stage_window == null or not is_instance_valid(_stage_window):
		_stage_window = null
		return
	var id: int = _stage_window.get_instance_id()
	if _stage_window_leases.has(id):
		_stage_window_leases[id]["count"] -= 1
		if int(_stage_window_leases[id]["count"]) == 0:
			_stage_window.content_scale_mode = int(_stage_window_leases[id]["previous_mode"])
			_stage_window_leases.erase(id)
	_stage_window = null
