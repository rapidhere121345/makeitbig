extends SceneTree
const Game = preload("res://src/game/game_root.gd")
const Menu = preload("res://src/presentation/session_menu.gd")
const Locale = preload("res://src/localization/game_locale.gd")
const Stage = preload("res://src/presentation/pixel_stage.gd")
const Assert := preload("res://tests/helpers/assert.gd")
var errors: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	await _check_launcher_stage_bounds()
	await _check_quit_layout()
	var game := Game.new()
	game.save_directory_path = "user://session-menu-tests-no-player-save"
	game.playtest_logging_enabled = false
	game.initialize(PackedStringArray(["--game-flow-smoke"]))
	root.add_child(game)
	await process_frame
	_expect(game.start_new_game("ranger").ok, "new game")
	_expect(game.complete_tutorial().ok, "tutorial")
	_expect(game.open_contract().ok, "contract")
	_expect(game.launch_contract({"contract_id":"mainline_01_first_hunt", "mode":"Manual", "seed":52969, "room_count":1}).ok, "launch")
	var controller: Node = game.current_screen
	var arena: Node = controller.get("_current_runtime").get("room_instance")
	var menu = game.get_session_menu()
	var attack := InputEventKey.new()
	attack.physical_keycode = KEY_SPACE
	attack.pressed = true
	arena.input_adapter.capture_attack_event(attack, false, arena.gameplay_snapshot())
	menu.open_menu()
	var volume: HSlider = menu.find_child("EffectsVolume",true,false)
	volume.value = 23
	_expect(is_equal_approx(game.display_settings.effects_volume,0.23),"volume changes reach session host")
	if arena.presentation.feedback.combat_feedback_audio != null:
		_expect(is_equal_approx(arena.presentation.feedback.combat_feedback_audio.get_volume(),0.23),"volume reaches current arena")
	_expect(not bool(arena.input_adapter.manual_combat_input.snapshot().get("assisted_held",true)), "opening menu clears held attack source")
	var tick: int = arena.sim_tick
	var state: String = arena.state_hash("pause-test")
	for i in range(10): await process_frame
	_expect(arena.sim_tick == tick and arena.state_hash("pause-test") == state, "pause must freeze ticks and authority")
	_expect(not paused and Engine.time_scale == 1.0, "pause must not change global tree/time scale")
	_check_display_application(game, menu)
	menu.close_menu()
	_expect(not bool(arena.input_adapter.manual_combat_input.snapshot().get("assisted_held",true)), "resume does not resurrect held attack")
	for i in range(5): await process_frame
	_expect(controller.process_mode == Node.PROCESS_MODE_INHERIT, "resume restores process mode")
	menu.open_menu()
	var exits: Array = []
	game.exit_code_hook = func(code: int, reason: String): exits.append([code, reason])
	var active_before: Dictionary = game.application_state.active_session
	var quit_button: Button = menu.find_child("QuitButton", true, false)
	var cancel_quit: Button = menu.find_child("CancelQuitButton", true, false)
	quit_button.pressed.emit()
	_expect(exits.is_empty() and cancel_quit.visible and menu.is_open(), "active quit asks for confirmation")
	cancel_quit.pressed.emit()
	_expect(exits.is_empty() and not cancel_quit.visible and game.current_route == "arena"
		and game.application_state.active_session == active_before, "cancel quit preserves active contract")
	quit_button.pressed.emit()
	quit_button.pressed.emit()
	_expect(exits == [[0, "quit_to_desktop"]] and game.current_route == "arena", "confirmed quit delegates exit without settling")
	game.exit_code_hook = Callable()
	var abandon: Button = menu.find_child("AbandonButton", true, false)
	abandon.pressed.emit()
	_expect(game.current_route == "arena" and menu.is_open(), "first abandon press only confirms")
	abandon.pressed.emit()
	await process_frame
	_expect(game.current_route == "result" and not menu.is_open(), "confirmed abandonment settles and closes menu")
	_expect(String(game.application_state.last_result.get("outcome", "")) == "abandoned", "abandon result truthful")
	var inventory_before: Dictionary = game.application_state.profile.inventory.duplicate(true)
	game.current_screen.contract_requested.emit()
	_expect(game.current_route == "contract", "next expedition opens contract selection, not another battle")
	_expect(game.application_state.profile.inventory == inventory_before, "next expedition does not grant extra rewards")
	game.free()
	await process_frame
	for message in errors: printerr(message)
	print("SESSION_MENU ", "pass" if errors.is_empty() else "fail")
	quit(0 if errors.is_empty() else 1)

func _check_display_application(game: Node, menu: Node) -> void:
	var picker: OptionButton = menu.find_child("WindowResolution", true, false)
	var apply: Button = menu.find_child("ApplyDisplay", true, false)
	var fullscreen: CheckButton = menu.find_child("FullscreenToggle", true, false)
	var hint: Label = menu.find_child("DisplayHint", true, false)
	game.display_settings.usable_display_override = Vector2i(2560, 1440)
	game.display_settings.apply_display_settings(Vector2i(3840, 2160), false)
	_expect(game.display_settings.windowed_resolution == Vector2i(2560, 1440), "oversized request clamps to the usable screen, got %s" % str(game.display_settings.windowed_resolution))
	_expect(menu.selected_resolution() == Vector2i(2560, 1440), "menu selects the clamped size")
	var offered: Array[Vector2i] = []
	for i in picker.item_count:
		offered.append(_parse(picker.get_item_text(i)))
	_expect(Vector2i(3840, 2160) not in offered and Vector2i(2560, 1440) in offered, "menu offers only sizes the screen can hold, got %s" % str(offered))
	game.display_settings.usable_display_override = Vector2i.ZERO
	game.display_settings.apply_display_settings(Vector2i(1500, 800), false)
	_expect(game.display_settings.windowed_resolution == Vector2i(1500, 800) and menu.selected_resolution() == Vector2i(1500, 800), "a current non-preset size stays selectable and is not replaced by 1600x900")
	game.display_settings.apply_display_settings(Vector2i(0, 720), false)
	_expect(game.display_settings.windowed_resolution == Vector2i(1500, 800), "a degenerate request is ignored")
	game.display_settings.apply_display_settings(Vector2i(640, 360), false)
	_expect(game.display_settings.windowed_resolution == Vector2i(1024, 576), "a tiny request is raised to the 1024x576 minimum")
	for i in picker.item_count:
		if _parse(picker.get_item_text(i)) == Vector2i(3440, 1440):
			picker.select(i)
			picker.item_selected.emit(i)
	_expect(hint.text == "16:9 view; borders on ultrawide", "ultrawide choice explains borders, got '%s'" % hint.text)
	apply.pressed.emit()
	_expect(game.display_settings.windowed_resolution == Vector2i(3440, 1440), "Apply button routes the selection through the host")
	fullscreen.button_pressed = true
	_expect(hint.text == "Desktop resolution in fullscreen", "fullscreen hint, got '%s'" % hint.text)
	fullscreen.button_pressed = false
	game.display_settings.apply_display_settings(Vector2i(1920, 1080), false)
	_expect(hint.text == "", "a 16:9 window needs no hint")

func _parse(text: String) -> Vector2i:
	var parts := text.split("×")
	return Vector2i(int(parts[0].strip_edges()), int(parts[1].strip_edges())) if parts.size() == 2 else Vector2i.ZERO

func _expect(ok: bool, message: String) -> void: Assert.expect(ok, message, errors)

func _check_launcher_stage_bounds() -> void:
	for window_size in [Vector2i(1280,720), Vector2i(1920,1080), Vector2i(3440,1440), Vector2i(3840,2160), Vector2i(1600,1000)]:
		var viewport := SubViewport.new()
		viewport.size = window_size
		root.add_child(viewport)
		var menu := Menu.new()
		viewport.add_child(menu)
		menu.set_route("arena")
		await process_frame
		var button := menu.find_child("SessionMenuButton", true, false) as Button
		var layout := Stage.layout_for_window(window_size)
		var stage_rect := Rect2(Vector2(layout.origin), Vector2(layout.stage_size))
		var drawn_rect := Rect2(button.position, button.size * button.scale)
		_expect(stage_rect.encloses(drawn_rect), "pause launcher escapes actual stage at %s: %s" % [window_size, drawn_rect])
		_expect(is_equal_approx(button.scale.x, float(layout.ui_scale)), "pause launcher scale differs from HUD at %s" % window_size)
		_expect(is_equal_approx(drawn_rect.position.x - stage_rect.position.x, 12.0 * float(layout.ui_scale)), "pause launcher left inset at %s" % window_size)
		menu.set_route("base")
		_expect(is_equal_approx(button.scale.x, maxf(0.75, minf(window_size.x / 1600.0, window_size.y / 900.0))), "settings launcher follows desktop readability scale")
		viewport.free()
		await process_frame


func _check_quit_layout() -> void:
	var previous := Locale.current()
	for language in ["en", "zh_CN"]:
		Locale.select(language)
		for scenario in [["base", 1.0], ["arena", 1.0], ["arena", 1.25]]:
			var route: String = scenario[0]
			var viewport := SubViewport.new()
			viewport.size = Vector2i(1280, 720)
			root.add_child(viewport)
			var menu := Menu.new()
			viewport.add_child(menu)
			menu.set_route(route)
			menu.sync_accessibility(language, scenario[1])
			menu.open_menu()
			for frame in 4: await process_frame
			var button := menu.find_child("QuitButton", true, false) as Button
			var panel := menu.find_child("SessionMenuPanel", true, false) as Control
			var scroll := menu.find_child("SettingsScroll", true, false) as ScrollContainer
			_expect(button.is_visible_in_tree() and not scroll.is_ancestor_of(button)
				and panel.get_global_rect().encloses(button.get_global_rect())
				and Rect2(Vector2.ZERO, Vector2(viewport.size)).encloses(button.get_global_rect())
				and button.focus_mode == Control.FOCUS_ALL,
				"quit button reachable outside scroll at %s in %s" % [route, language])
			button.grab_focus()
			_expect(viewport.gui_get_focus_owner() == button, "quit button takes keyboard focus")
			var quit_events: Array = []
			menu.quit_requested.connect(func(): quit_events.append(true))
			if route == "base":
				button.pressed.emit()
				_expect(quit_events.size() == 1, "quit outside combat exits immediately")
			if route == "arena":
				scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
				for frame in 3: await process_frame
				_expect(scroll.scroll_vertical > 0, "settings scroll reaches lower controls")
				button.pressed.emit()
				for frame in 3: await process_frame
				_expect(quit_events.is_empty(), "active quit does not exit before confirmation")
				var cancel := menu.find_child("CancelQuitButton", true, false) as Button
				var warning := menu.find_child("QuitWarning", true, false) as Label
				var panel_rect: Rect2 = panel.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, panel.size)
				var cancel_rect: Rect2 = cancel.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, cancel.size)
				var warning_rect: Rect2 = warning.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, warning.size)
				_expect(Rect2(Vector2.ZERO, Vector2(viewport.size)).encloses(panel_rect),
					"confirmation panel exceeds viewport in %s: %s" % [language, panel_rect])
				_expect(panel_rect.encloses(cancel_rect) and panel_rect.encloses(warning_rect)
					and Rect2(Vector2.ZERO, Vector2(viewport.size)).encloses(cancel_rect)
					and Rect2(Vector2.ZERO, Vector2(viewport.size)).encloses(warning_rect)
					and warning.get_visible_line_count() == warning.get_line_count()
					and viewport.gui_get_focus_owner() == cancel,
					"quit confirmation fits and focuses cancel in %s" % language)
			viewport.free()
			await process_frame
	Locale.select(previous)
