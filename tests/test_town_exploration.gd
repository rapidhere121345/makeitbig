extends SceneTree
## Distance-gated navigation and session-local return positions in the real root.
const Game = preload("res://src/game/game_root.gd")
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var game := Game.new()
	game.save_directory_path = "user://town-exploration-no-player-save"
	game.playtest_logging_enabled = false
	game.initialize(PackedStringArray(["--game-flow-smoke"]))
	root.add_child(game)
	await process_frame
	_expect(game.start_new_game("ranger").ok and game.complete_tutorial().ok, "new profile reaches town")
	await process_frame
	var hub = game.current_screen
	var view = hub.get_hub_view()
	var spawn: Vector2 = view.hero_world_position()
	var camera_before: Vector2 = view.camera_world_offset()
	var profile_before: Dictionary = game.application_state.persistent_payload()
	# Selection never teleports the avatar or bypasses the actual facility.
	hub.navigation_card_activated("loadout")
	_expect(game.current_route == "base" and view.hero_world_position() == spawn,
		"distant landmark selection changed route or moved the player")
	_expect(hub.wayfinding_report().id == "loadout" and not hub.wayfinding_report().arrived,
		"distant selection did not show the selected direction")
	_expect(not hub.activate_nearby_feature() and game.current_route == "base", "E opened a distant destination")
	var town = hub.get_town_runtime()
	# Walk the authored road with live collision before any explicit camera tests.
	for target: Vector2 in town.route_points("loadout"):
		var steps := 0
		while view.hero_world_position().distance_to(target) > 0.05 and steps < 900:
			var delta: Vector2 = target - view.hero_world_position()
			hub.move_hero(delta / (town.HERO_SPEED / 30.0), 1.0 / 30.0)
			steps += 1
		_expect(view.hero_world_position().distance_to(target) < 0.05, "expanded road blocked before " + str(target))
	_expect(view.camera_world_offset().distance_to(camera_before) > 150, "camera failed to follow the long walk")
	_expect(hub.wayfinding_report().arrived, "arrival did not replace the direction with an interaction prompt")
	_expect(hub.get_landmark("loadout").visible and hub.get_prompt_rect() != Rect2(),
		"arrival did not reveal the loadout landmark and nearby action badge")
	var saved: Dictionary = hub.travel_snapshot()
	_expect(hub.activate_nearby_feature() and game.current_route == "loadout", "nearby E did not enter equipment")
	_expect(game.leave_facility().ok and game.current_screen.travel_snapshot() == saved,
		"leaving equipment lost position, facing or destination")
	_expect(game.open_story().ok and game.close_adventure_page().ok
		and game.current_screen.travel_snapshot() == saved, "reading journal reset the town walk")
	_expect(game.open_contract().ok and game.cancel_contract().ok
		and game.current_screen.travel_snapshot() == saved, "canceling a contract reset the town walk")
	_expect(game.application_state.persistent_payload() == profile_before,
		"walking or reviewing facilities changed persistent progression")
	hub = game.current_screen
	view = hub.get_hub_view()
	for size: Vector2i in [Vector2i(1280,720), Vector2i(1600,900)]:
		game.get_pixel_stage().apply_window_size(size)
		await process_frame
		_expect(view.world_viewport.size == Vector2i(640,360), "resizing exposed more town")
		var visible_fraction: float = Vector2(view.world_viewport.size).x * view.world_viewport.size.y / (view.world_size().x * view.world_size().y)
		_expect(visible_fraction < 0.2, "default view exposes the whole town")
		_expect(hub.find_child("TownWayfinder", true, false) == null, "global wayfinding panel returned")
		for feature_id: String in ["contract", "loadout", "forge", "training", "proxy"]:
			var landmark: Button = hub.get_landmark(feature_id)
			var expected: Rect2 = hub._landmark_design_rect(feature_id)
			_expect(landmark.position == expected.position.floor(), "%s landmark was clamped at %s" % [feature_id, str(size)])
			if landmark.visible:
				_expect(Rect2(Vector2(12,92), Vector2(1256,616)).encloses(landmark.get_rect()), "%s landmark escaped logical canvas" % feature_id)
		for point: Vector2 in [view.world_bounds().position, view.world_bounds().end, saved.position]:
			hub.get_town_runtime().place_hero(point)
			var camera: Vector2 = view.camera_world_offset()
			var limit: Vector2 = view.world_size() - Vector2(view.world_viewport.size)
			_expect(camera == camera.clamp(Vector2.ZERO, limit), "camera exposes outside the town")
			var design: Vector2 = view.design_point_for_world(point, Vector2.ZERO, Vector2.ONE)
			_expect(view.world_point_at_design(design, Vector2.ZERO, Vector2.ONE).distance_to(point) < 0.001,
				"close camera breaks pointer conversion")
	_expect(game.return_to_title().ok and game.start_new_game("ranger").ok and game.complete_tutorial().ok,
		"second new profile failed")
	_expect(game.current_screen.get_hub_view().hero_world_position() == spawn,
		"a new profile inherited the previous town position")
	game.free()
	await process_frame
	for failure in failures: printerr("- " + failure)
	print("TOWN_EXPLORATION ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)


func _expect(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
