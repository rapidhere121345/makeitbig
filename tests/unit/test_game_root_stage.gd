extends SceneTree
## In-tree integration: logical battle geometry, headless isolation, window lease
## lifetime. No normal save directory and no player data writes.
const Game := preload("res://src/game/game_root.gd")
const Stage := preload("res://src/presentation/pixel_stage.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _game() -> Node:
	var game := Game.new()
	game.save_directory_path = "user://game-root-stage-gate-no-player-save"
	game.playtest_logging_enabled = false
	game.initialize(PackedStringArray(["--game-flow-smoke"]))
	root.add_child(game)
	return game

func _run() -> void:
	var previous := root.content_scale_mode
	var graphical := not DisplayServer.get_name().to_lower().contains("headless")
	var active_mode := Window.CONTENT_SCALE_MODE_DISABLED if graphical else previous
	var first := _game()
	await process_frame
	var console: CanvasLayer = first.get_test_console()
	var console_root: Control = console.find_child("TestConsoleRoot", true, false) if console != null else null
	var console_body: TextEdit = console.find_child("SnapshotText", true, false) if console != null else null
	_expect(console != null and console.layer == 100, "one global test console is mounted above routed screens")
	_expect(console_root != null and not console_root.visible and console_body != null and console_body.text.is_empty(),
		"test console must start hidden without cached diagnostic data")
	if console != null:
		console.call("open_console")
		_expect(console_root.visible and console_body.text.contains("[路线]") and console_body.text.contains("[表现层布局]"),
			"F10 console provider did not expose route and layout diagnostics")
		console.call("close_console")
		_expect(not console_root.visible and console_body.text.is_empty(), "closing the test console retained raw diagnostic text")
	_expect(root.content_scale_mode == active_mode,"graphical lease / headless mode isolation")
	_expect(first.current_screen.get_parent() == first.get_presentation_viewport(),"prepared off-tree screen moves into stage")
	_expect(first.get_presentation_viewport().get_visible_rect() == Rect2(0,0,1280,720),"mounted logical viewport stays 1280x720")
	_expect(first.get_presentation_viewport().canvas_item_default_texture_filter == Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST,
		"nested presentation viewport must not silently inherit LINEAR for the world sprites")
	var second := _game()
	await process_frame
	root.remove_child(first)
	_expect(root.content_scale_mode == active_mode,"first exit cannot reset second live stage")
	second.free()
	_expect(root.content_scale_mode == previous,"last exit restores original stretch")
	root.add_child(first)
	await process_frame
	_expect(root.content_scale_mode == active_mode,"re-entry reacquires stage window")
	first.get_pixel_stage().apply_window_size(Vector2i(1600,900))
	_expect(first.get_pixel_stage().get_presentation_policy() == Stage.POLICY_FIXED_PIXEL
		and first.get_presentation_viewport().get_visible_rect() == Rect2(0,0,1280,720),
		"title keeps the fixed pixel canvas in a larger window")
	_expect(first.start_new_game("ranger").ok,"new ranger")
	_expect(first.get_pixel_stage().get_presentation_policy() == Stage.POLICY_FIXED_PIXEL,"tutorial keeps fixed pixel policy")
	_expect(first.complete_tutorial().ok,"tutorial to base")
	_expect(first.get_pixel_stage().get_presentation_policy() == Stage.POLICY_FIXED_PIXEL,"base keeps fixed pixel policy")
	_expect(first.open_contract().ok,"contract board")
	first.get_pixel_stage().apply_window_size(Vector2i(1600,900))
	_expect(first.get_pixel_stage().get_presentation_policy() == Stage.POLICY_ADAPTIVE_SHELL
		and first.get_presentation_viewport().get_visible_rect() == Rect2(0,0,1600,900),
		"contract uses the larger window as real logical layout space")
	_expect(first.launch_contract({"contract_id":"mainline_01_first_hunt","mode":"Manual","seed":52969,"room_count":1}).ok,"actual arena")
	first.get_pixel_stage().apply_window_size(Vector2i(1600,900))
	_expect(first.get_pixel_stage().get_presentation_policy() == Stage.POLICY_FIXED_PIXEL
		and first.get_presentation_viewport().get_visible_rect() == Rect2(0,0,1280,720),
		"arena returns to the fixed 1280x720 authority canvas")
	var runtime: Node = first.current_screen.get("_current_runtime")
	# ContractRunController exposes its active room runtime through children; no fake arena.
	if runtime == null:
		for child in first.current_screen.get_children():
			if child.get_script() != null and child.get_script().resource_path.ends_with("combat_room_runtime.gd"):
				runtime = child
	var arena: Node = runtime.get("room_instance") if runtime != null else null
	_expect(arena != null,"real CombatRoomRuntime mounted inside stage")
	if arena != null:
		arena.set_process(false)
		arena.set_physics_process(false)
		var rect: Rect2 = arena._arena_rect()
		var foot: Vector2 = arena.player_position
		for size: Vector2i in [Vector2i(1280,720),Vector2i(1920,1080),Vector2i(1024,576)]:
			first.get_pixel_stage().apply_window_size(size)
			await process_frame
			_expect(arena._arena_rect() == rect,"raster resize keeps arena geometry " + str(size))
			_expect(arena.player_position == foot,"raster resize cannot move player " + str(size))
			_expect(arena.get_viewport() == first.get_presentation_viewport(),"actual arena shares presentation viewport")
	first.free()
	await process_frame
	_expect(root.content_scale_mode == previous,"final exit restores window")
	for failure: String in failures: printerr(failure)
	print("GAME_ROOT_STAGE ","pass" if failures.is_empty() else "fail")
	quit(0 if failures.is_empty() else 1)

func _expect(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
