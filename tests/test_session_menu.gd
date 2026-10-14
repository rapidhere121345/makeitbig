extends SceneTree
const Game = preload("res://src/game/game_root.gd")
var errors: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
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

func _expect(ok: bool, message: String) -> void:
	if not ok: errors.append(message)
