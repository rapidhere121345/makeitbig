extends SceneTree
## Interactive play companion: only device events and observation, no progress fixtures.
var directory := OS.get_environment("MIB_PLAY_SESSION_DIR")
var game: Node
var last_id := -1
var pointer := Vector2.ZERO

func _initialize() -> void:
	if directory.is_empty(): directory = "/tmp/makeitbig-play"
	call_deferred("_start")

func _start() -> void:
	DirAccess.make_dir_recursive_absolute(directory)
	# Reusing the evidence directory must not replay the previous session's
	# quit/button command. Commands arriving after startup still run normally.
	if FileAccess.file_exists(directory + "/command.json"):
		var previous: Variant = JSON.parse_string(FileAccess.get_file_as_string(directory + "/command.json"))
		if previous is Dictionary:
			last_id = int(previous.get("id", -1))
	game = load("res://src/game/game_root.tscn").instantiate()
	game.save_directory_path = directory + "/save"
	game.playtest_log_directory = directory + "/log"
	root.add_child(game)
	for i in 15: await process_frame
	DisplayServer.window_set_size(Vector2i(1280, 720))
	root.size = Vector2i(1280, 720)
	for i in 8: await process_frame
	game.process_mode = Node.PROCESS_MODE_DISABLED
	await _snapshot(0)
	while true:
		await process_frame
		if not FileAccess.file_exists(directory + "/command.json"): continue
		var command: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(directory + "/command.json"))
		var id := int(command.get("id", 0))
		if id <= last_id: continue
		last_id = id
		print("PLAY_COMMAND ", id)
		if command.get("quit", false):
			quit()
			return
		game.process_mode = Node.PROCESS_MODE_INHERIT
		await process_frame
		if command.has("size"):
			var requested := Vector2i(int(command.size[0]), int(command.size[1]))
			DisplayServer.window_set_size(requested)
			root.size = requested
		if command.has("click"):
			var xy: Array = command.click
			await _click(Vector2(float(xy[0]), float(xy[1])))
		if command.has("mouse_down"):
			var down_xy: Array = command.mouse_down
			await _mouse_button(Vector2(float(down_xy[0]), float(down_xy[1])), true)
		if command.has("mouse_up"):
			await _mouse_button(pointer, false)
		if command.has("node"):
			var control: Control = root.get_node(NodePath(command.node))
			await _click(_root_rect(control).get_center())
		if command.has("move"):
			var xy: Array = command.move
			pointer = Vector2(float(xy[0]), float(xy[1]))
			var event := InputEventMouseMotion.new()
			event.position = pointer
			event.global_position = event.position
			root.push_input(event, true)
		if command.has("wheel"):
			for step in absi(int(command.wheel)):
				var event := InputEventMouseButton.new()
				event.position = pointer
				event.button_index = MOUSE_BUTTON_WHEEL_DOWN if int(command.wheel) > 0 else MOUSE_BUTTON_WHEEL_UP
				event.pressed = true
				root.push_input(event, true)
				event = event.duplicate()
				event.pressed = false
				root.push_input(event, true)
				await process_frame
		var keys: Array = command.get("keys", [])
		for key in keys: _key(String(key), true)
		for i in int(command.get("frames", 1)): await process_frame
		print("PLAY_STEPPED ", id)
		for key in keys: _key(String(key), false)
		await process_frame
		game.process_mode = Node.PROCESS_MODE_DISABLED
		await _snapshot(id)

func _key(value: String, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = OS.find_keycode_from_string(value)
	event.keycode = event.physical_keycode
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _click(point: Vector2) -> void:
	pointer = point
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion, true)
	await process_frame
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		event.pressed = down
		root.push_input(event, true)
		await process_frame

## A held button across commands: mouse_down presses at the point, mouse_up
## releases at the remembered pointer. Lets a regression session exercise the
## real held-fire path instead of only full clicks.
func _mouse_button(point: Vector2, pressed: bool) -> void:
	pointer = point
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	root.push_input(event, true)
	await process_frame

func _root_rect(control: Control) -> Rect2:
	var rect: Rect2 = control.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, control.size)
	if control.get_viewport() == root: return rect
	var layout: Dictionary = game.find_child("PixelStage", true, false).layout_snapshot()
	return Rect2(Vector2(layout.origin) + rect.position * float(layout.ui_scale), rect.size * float(layout.ui_scale))

func _snapshot(id: int) -> void:
	game.process_mode = Node.PROCESS_MODE_INHERIT
	await process_frame
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(directory + "/screen.png")
	var controls: Array = []
	_scan(game.current_screen, controls)
	var result := {"id": id, "route": game.current_route, "controls": controls,
		"profile": game.application_state.profile, "window": str(root.size)}
	var focus_viewport: Viewport = game.current_screen.get_viewport() if game.current_screen != null else root
	var focus_owner: Control = focus_viewport.gui_get_focus_owner()
	result.focus = "" if focus_owner == null else str(focus_owner.get_path())
	if game.current_screen.has_method("get_checklist_snapshot"):
		result.tutorial = game.current_screen.get_checklist_snapshot()
		result.position = str(game.current_screen.get_player_position())
	if game.current_screen.has_method("get_town_runtime"):
		var town = game.current_screen.get_town_runtime()
		var presenter = game.current_screen.get_hub_view()
		result.town = presenter.life_report()
		result.position = str(town.hero_world_position())
		result.town_tick = town.simulation.tick if town.is_ready() else 0
		result.destination_guide = presenter.destination_guide_report()
		result.town_render = presenter.render_audit()
		result.town_load = game.current_screen.town_load_report
	var mains: Array = game.current_screen.find_children("*", "Node2D", true, false)
	if game.current_screen is Node2D: mains.push_front(game.current_screen)
	for node in mains:
		if node.get_script() != null and node.get_script().resource_path == "res://src/game/main.gd":
			result.combat = {"tick": node.sim_tick, "health": node.player_health, "position": str(node.player_position), "enemies": []}
			for enemy in node.enemies:
				result.combat.enemies.append({"id": enemy.entity_id, "health": enemy.health, "position": str(enemy.position), "kind": enemy.kind_id})
	var file := FileAccess.open(directory + "/state.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result))
	file.close()
	game.process_mode = Node.PROCESS_MODE_DISABLED
	print("PLAY_READY ", id, " ", game.current_route)

func _scan(node: Node, result: Array) -> void:
	if node is Control and not node.is_visible_in_tree(): return
	if node is Label or node is Button or node is RichTextLabel:
		var value := {"node": str(node.get_path()), "text": node.get_parsed_text() if node is RichTextLabel else node.text, "rect": str(_root_rect(node))}
		if node is BaseButton: value.disabled = node.disabled
		result.append(value)
	for child in node.get_children(): _scan(child, result)
