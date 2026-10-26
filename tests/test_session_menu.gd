extends SceneTree
const Game = preload("res://src/game/game_root.gd")
const Menu = preload("res://src/presentation/session_menu.gd")
const Stage = preload("res://src/presentation/pixel_stage.gd")
const Assert := preload("res://tests/helpers/assert.gd")
var errors: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	await _check_launcher_stage_bounds()
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
	_expect(is_equal_approx(game._effects_volume,0.23),"volume changes reach session host")
	if arena.presentation.feedback.combat_feedback_audio != null:
		_expect(is_equal_approx(arena.presentation.feedback.combat_feedback_audio.get_volume(),0.23),"volume reaches current arena")
	_expect(not bool(arena.input_adapter.manual_combat_input.snapshot().get("assisted_held",true)), "opening menu clears held attack source")
	var tick: int = arena.sim_tick
	var state: String = arena._semantic_state_hash("pause-test")
	for i in range(10): await process_frame
	_expect(arena.sim_tick == tick and arena._semantic_state_hash("pause-test") == state, "pause must freeze ticks and authority")
	_expect(not paused and Engine.time_scale == 1.0, "pause must not change global tree/time scale")
	_check_display_application(game, menu)
	menu.close_menu()
	_expect(not bool(arena.input_adapter.manual_combat_input.snapshot().get("assisted_held",true)), "resume does not resurrect held attack")
	for i in range(5): await process_frame
	_expect(controller.process_mode == Node.PROCESS_MODE_INHERIT, "resume restores process mode")
	menu.open_menu()
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
	game.usable_display_override = Vector2i(2560, 1440)
	game._apply_display_settings(Vector2i(3840, 2160), false)
	_expect(game._windowed_resolution == Vector2i(2560, 1440), "oversized request clamps to the usable screen, got %s" % str(game._windowed_resolution))
	_expect(menu.selected_resolution() == Vector2i(2560, 1440), "menu selects the clamped size")
	var offered: Array[Vector2i] = []
	for i in picker.item_count:
		offered.append(_parse(picker.get_item_text(i)))
	_expect(Vector2i(3840, 2160) not in offered and Vector2i(2560, 1440) in offered, "menu offers only sizes the screen can hold, got %s" % str(offered))
	game.usable_display_override = Vector2i.ZERO
	game._apply_display_settings(Vector2i(1500, 800), false)
	_expect(game._windowed_resolution == Vector2i(1500, 800) and menu.selected_resolution() == Vector2i(1500, 800), "a current non-preset size stays selectable and is not replaced by 1600x900")
	game._apply_display_settings(Vector2i(0, 720), false)
	_expect(game._windowed_resolution == Vector2i(1500, 800), "a degenerate request is ignored")
	game._apply_display_settings(Vector2i(640, 360), false)
	_expect(game._windowed_resolution == Vector2i(1024, 576), "a tiny request is raised to the 1024x576 minimum")
	for i in picker.item_count:
		if _parse(picker.get_item_text(i)) == Vector2i(3440, 1440):
			picker.select(i)
			picker.item_selected.emit(i)
	_expect(hint.text == "16:9 view; borders on ultrawide", "ultrawide choice explains borders, got '%s'" % hint.text)
	apply.pressed.emit()
	_expect(game._windowed_resolution == Vector2i(3440, 1440), "Apply button routes the selection through the host")
	fullscreen.button_pressed = true
	_expect(hint.text == "Desktop resolution in fullscreen", "fullscreen hint, got '%s'" % hint.text)
	fullscreen.button_pressed = false
	game._apply_display_settings(Vector2i(1920, 1080), false)
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
