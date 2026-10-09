extends SceneTree
## Human-comfort regressions from the 2026-10-09 rendered play session.
const Game = preload("res://src/game/game_root.gd")
const Facility = preload("res://src/presentation/facility_screen.gd")
const FacilityFixture = preload("res://tests/test_facility_screen.gd")
const Result = preload("res://src/presentation/result_screen.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_town_guidance_and_tab()
	await _test_facility_escape_context()
	await _test_result_escape_context()
	if failures.is_empty():
		print("PASS  tests/test_playtest_comfort.gd")
		quit(0)
		return
	printerr("%d playtest comfort check(s) failed:" % failures.size())
	for failure in failures:
		printerr("- %s" % failure)
	quit(1)


func _test_town_guidance_and_tab() -> void:
	var game := Game.new()
	game.save_directory_path = "user://playtest-comfort-no-player-save"
	game.playtest_logging_enabled = false
	game.initialize(PackedStringArray(["--game-flow-smoke"]))
	root.add_child(game)
	await _frames(2)
	_expect(game.start_new_game("ranger").ok and game.complete_tutorial().ok, "fixture profile did not reach town")
	await _frames(2)
	var hub = game.current_screen
	var view = hub.get_hub_view()
	var guide: Dictionary = view.destination_guide_report()
	_expect(bool(guide.get("visible", false)), "off-screen destination has no local guide")
	var indicator := view.world_viewport.get_node_or_null("TownDestinationIndicator") as Polygon2D
	_expect(indicator != null and indicator.visible and indicator.get_child_count() == 0,
		"destination guide is not one visible local marker")
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(view.DEFAULT_LAYOUT_PATH))
	var routes: Dictionary = layout.get("routes_uv", {})
	var contract_route: Array = routes.get("contract", [])
	var first_uv: Array = contract_route[1]
	var first_road_point: Vector2 = Vector2(float(first_uv[0]), float(first_uv[1])) * view.world_size()
	_expect(Vector2(guide.get("guide", Vector2.INF)).distance_to(first_road_point) < 0.01,
		"destination guide ignored the authored first road waypoint")
	_expect(hub.find_child("TownWayfinder", true, false) == null,
		"a global wayfinding panel or facility menu returned")

	hub.set_hero_position(hub.get_world_feature_position("loadout"))
	await _frames(3)
	var focus_before_tab := root.gui_get_focus_owner()
	await _press_key(KEY_TAB)
	var focused_landmarks: Array[Button] = []
	for feature_id: String in ["contract", "loadout", "forge", "training", "proxy"]:
		var landmark: Button = hub.get_landmark(feature_id)
		if landmark != null and landmark.visible and landmark.has_focus():
			focused_landmarks.append(landmark)
	_expect(focus_before_tab == null and focused_landmarks.size() == 1,
		"one Tab did not move from no focus to exactly one visible landmark")
	await _press_key(KEY_ESCAPE)
	_expect(hub._navigation_has_focus() == false, "Escape did not leave landmark keyboard focus")

	hub.set_hero_position(hub.get_world_feature_position("contract"))
	await _frames(3)
	_expect(not view.destination_guide_report().get("visible", true), "arrived destination still showed an off-screen guide")
	game.queue_free()
	await _frames(2)


func _test_facility_escape_context() -> void:
	var fixture := FacilityFixture.new()
	var data: Dictionary = fixture._real_loadout_snapshot()
	fixture.free()
	var screen := Facility.new()
	root.add_child(screen)
	screen.present("loadout", {}, {}, "", data)
	await _frames(3)
	var requests: Array[int] = [0]
	screen.base_requested.connect(func(): requests[0] += 1)
	await _press_key(KEY_ESCAPE)
	_expect(requests[0] == 1, "one facility Escape did not request the pinned return action once")
	var keyword := screen.find_child("CandidateKeywordFilter", true, false) as LineEdit
	_expect(keyword != null, "loadout fixture lost its search field")
	if keyword != null:
		keyword.grab_focus()
		await _frames(1)
		await _press_key(KEY_ESCAPE)
		_expect(requests[0] == 1 and not keyword.has_focus(), "Escape in search editing left the field instead of returning")
	screen.queue_free()
	await _frames(2)


func _test_result_escape_context() -> void:
	var screen := Result.new()
	root.add_child(screen)
	var drop := {
		"instance_id": "comfort_drop",
		"base_item_id": "ashwood_longbow",
		"slot": "main_hand",
		"affixes": [],
	}
	screen.present({"outcome": "victory", "rewards": {"equipment_drops": [drop]}}, {}, {
		"inventory": {"equipment": [drop]},
		"active_build": {"equipped_item_ids": {}},
	})
	await _frames(3)
	var returns: Array[int] = [0]
	screen.base_requested.connect(func(): returns[0] += 1)
	await _press_key(KEY_ESCAPE)
	_expect(returns[0] == 1, "one settlement Escape did not request return to town once")
	var detail_button := screen.find_child("EquipmentDetailButton", true, false) as Button
	_expect(detail_button != null, "settlement fixture lost its equipment detail action")
	if detail_button != null:
		detail_button.grab_focus()
		await _press_key(KEY_ENTER)
		var overlay := screen.find_child("EquipmentDetailOverlay", true, false) as Control
		_expect(overlay != null and overlay.visible, "Enter did not open the settlement equipment detail")
		await _press_key(KEY_ESCAPE)
		_expect(overlay != null and not overlay.visible and returns[0] == 1,
			"Escape in equipment detail returned to town instead of closing the local overlay")
	screen.queue_free()
	await _frames(2)


func _press_key(code: int) -> void:
	var key := InputEventKey.new()
	key.keycode = code as Key
	key.physical_keycode = code as Key
	key.pressed = true
	Input.parse_input_event(key)
	Input.flush_buffered_events()
	await _frames(1)
	key = key.duplicate()
	key.pressed = false
	Input.parse_input_event(key)
	Input.flush_buffered_events()
	await _frames(2)


func _frames(count: int) -> void:
	for _index in count:
		await process_frame


func _expect(condition: bool, detail: String) -> void:
	if not condition:
		failures.append(detail)
