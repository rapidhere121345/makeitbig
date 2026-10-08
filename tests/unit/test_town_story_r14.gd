extends SceneTree

const Game = preload("res://src/game/game_root.gd")
var errors: Array[String] = []

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	var game := Game.new()
	game.save_directory_path = "user://town-story-integration-%d" % Time.get_ticks_usec()
	game.playtest_logging_enabled = false
	game.initialize(PackedStringArray(["--game-flow-smoke"]))
	root.add_child(game)
	await _settle()
	_expect(game.start_new_game("ranger").ok and game.complete_tutorial().ok, "real new profile enters town")
	await _settle()
	var hub = game.current_screen
	var view = hub.get_hub_view()
	var approaches := _test_resident_approaches(view)
	var before: Dictionary = game.application_state.profile.duplicate(true)
	_expect(not hub.talk_to_resident("mira"), "distant dialogue cannot open")
	_expect(not hub.talk_to_resident("oren"), "future conversation cannot open")
	if not approaches.has("mira"):
		_finish(game)
		return
	hub.set_hero_position(approaches.mira * 2.0)
	await _settle()
	_expect(hub.nearby_resident_id() == "mira", "nearest resident becomes E target")
	if hub.nearby_resident_id() != "mira":
		_finish(game)
		return
	var location: Vector2 = hub.get_hero_position()
	var camera: Vector2 = view.camera_world_offset()
	await _key(KEY_E)
	if game.current_route != "base" or not is_instance_valid(hub):
		_expect(false, "engine E left base instead of opening the selected resident")
		_finish(game)
		return
	_expect(hub.is_dialogue_open(), "engine E opens in-town conversation")
	if not hub.is_dialogue_open():
		_finish(game)
		return
	var id := String(hub.dialogue_report().entry_id)
	hub.move_hero(Vector2.RIGHT, 1.0)
	_expect(hub.get_hero_position() == location and view.camera_world_offset() == camera, "dialogue freezes movement without resetting camera")
	_expect(not hub.activate_nearby_feature() and not hub.click_at_world_point(view.entry_for("contract").feet), "dialogue blocks facility action passthrough")
	await _key(KEY_J)
	await _key(KEY_C)
	_expect(game.current_route == "base" and hub.is_dialogue_open(), "dialogue blocks story and character shortcuts")
	await _key(KEY_ENTER)
	_expect(int(hub.dialogue_report().page) == 1, "Enter advances exactly one line")
	await _key(KEY_ESCAPE)
	_expect(not hub.is_dialogue_open(), "Escape leaves conversation")
	_expect(game.application_state.profile == before, "early close does not mark read or mutate gameplay")
	var reads: Array[String] = []
	hub.conversation_read.connect(func(entry_id: String): reads.append(entry_id))
	await _key(KEY_E)
	var pages := int(hub.dialogue_report().pages)
	for page in range(pages): await _key(KEY_E)
	_expect(not hub.is_dialogue_open() and reads == [id], "last line creates one read receipt")
	_expect(id in game.application_state.profile.story.read_entry_ids, "conversation read persisted using stable ID")
	var after: Dictionary = game.application_state.profile.duplicate(true)
	before.erase("story")
	after.erase("story")
	_expect(before == after, "reading changes no inventory/XP/discovery/unlock/combat state")
	_expect(hub.get_hero_position() == location and view.camera_world_offset() == camera, "finish keeps actual avatar and camera")
	var restored := Game.ApplicationStateScript.new()
	var payload: Dictionary = JSON.parse_string(JSON.stringify(game.application_state.persistent_payload()))
	_expect(restored.restore_persistent_payload(payload).ok, "schema10 save accepts newly read conversation")
	_expect(id in restored.profile.story.read_entry_ids, "conversation read survives serialization")
	var good: Dictionary = restored.profile.duplicate(true)
	payload.profile.story.read_entry_ids.append("talk_future_not_reached")
	_expect(not restored.restore_persistent_payload(payload).ok and restored.profile == good, "unknown future read ID rejected atomically")
	payload.profile.story.read_entry_ids.erase("talk_future_not_reached")
	payload.profile.story.read_entry_ids.append("talk_p09_mira_steady")
	_expect(not restored.restore_persistent_payload(payload).ok and restored.profile == good, "known but unavailable conversation read ID rejected atomically")
	_expect(not game.read_town_conversation("journal_p00_place_by_the_door").ok, "town callback accepts only conversation IDs")
	_expect(game.open_contract().ok, "reading is optional and departure remains available")
	_expect(not game.read_town_conversation(id).ok, "town read receipt rejected outside base")
	_finish(game)

func _finish(game: Node) -> void:
	game.queue_free()
	for error in errors: printerr(error)
	print("TOWN_STORY_R14 ", "PASS" if errors.is_empty() else "FAIL")
	quit(0 if errors.is_empty() else 1)

func _test_resident_approaches(view) -> Dictionary:
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://art/production/p1/hamlet_town/layout.json"))
	var size: Vector2 = view.world_size()
	var spawn := Vector2(layout.hero_start_uv[0], layout.hero_start_uv[1]) * size
	var approaches := {}
	var roles := {}
	for placement: Dictionary in layout.placements:
		if placement.get("layer", "") == "npc": roles[String(placement.id)] = String(placement.role)
	for resident: Dictionary in view.life_report().residents:
		var role := String(roles[String(resident.id)])
		var position := spawn
		for uv: Array in layout.routes_uv[role]:
			var target := Vector2(float(uv[0]), float(uv[1])) * size
			var reached: Vector2 = view._collision.move(position, target - position, view.world_bounds())
			_expect(reached.distance_to(target) < 0.05 and not view._collision.is_blocked(reached), String(resident.id) + " authored approach blocked at " + str(reached))
			position = reached
		var found := false
		for index in 32:
			var target: Vector2 = resident.feet + Vector2.from_angle(TAU * float(index) / 32.0) * 22.0
			if view._collision.is_blocked(target): continue
			var reached: Vector2 = view._collision.move(position, target - position, view.world_bounds())
			if reached.distance_to(target) >= 0.05: continue
			var closest := true
			for feature: String in ["contract", "loadout", "forge", "training", "proxy"]:
				if target.distance_to(view.entry_for(feature).feet) <= 22.0: closest = false
			if not closest: continue
			approaches[String(resident.id)] = target
			found = true
			break
		_expect(found, String(resident.id) + " has no reachable E approach that favours the NPC")
	return approaches

func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = false
	Input.parse_input_event(event)
	await _settle()

func _settle() -> void:
	for frame in range(3): await process_frame

func _expect(ok: bool, message: String) -> void:
	if not ok: errors.append(message)
