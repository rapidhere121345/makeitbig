extends RefCounted
## Focused regression for the hamlet hub screen: movement, collision, proximity
## activation, landmark routing and marker copy plus the visual contract of the
## live renderer (feet-anchored sprite layers, split-row fade, snapped camera).

const BaseHubScreenScript = preload("res://src/presentation/base_hub_screen.gd")
const HamletConceptViewScript = preload("res://src/presentation/hamlet_concept_view.gd")
const ApplicationStateScript = preload("res://src/game/application_state.gd")

## The layout's five interaction routes. Immortality keeps its legacy API but has
## no placement, so it must never appear as an invisible hotspot.
const FEATURE_IDS: Array[String] = ["contract", "loadout", "forge", "training", "proxy"]


class MenuProbe extends Node:
	var opened := 0
	func open_menu() -> void:
		opened += 1


class MenuHost extends Node:
	var menu := MenuProbe.new()
	func get_session_menu() -> Node:
		return menu


func run() -> Array[String]:
	var failures: Array[String] = []
	var temporary_root := Node.new()
	var scene_tree := Engine.get_main_loop() as SceneTree
	scene_tree.root.add_child(temporary_root)
	var hub = BaseHubScreenScript.new()
	temporary_root.add_child(hub)
	hub._ready()

	_test_entry_table(hub, failures)
	var render_audit: Dictionary = hub.get_hub_view().render_audit()
	_expect(String(render_audit.get("ground_source_path", "")) == String(_town_layout().scene_texture), "base hub: live ground did not use the R13 environmental town surface", failures)
	var town_concept: Dictionary = render_audit.get("town_concept", {})
	_expect(bool(town_concept.get("ready", false)) and bool(town_concept.get("animated", false))
		and (town_concept.get("connected_features", []) as Array).size() >= 5,
		"base hub: town composition layer did not connect the published facilities", failures)
	_test_initial_position(hub, failures)
	_test_hub_info_keeps_world_visible(hub, failures)
	_test_concept_framing(hub, failures)
	_test_delta_movement(hub, failures)
	_test_diagonal_normalization(hub, failures)
	_test_configured_input_actions(hub, failures)
	_test_walk_to_external_stations(hub, failures)
	_test_bounded_live_camera(hub, failures)
	_test_feature_activation(hub, failures)
	_test_interaction_keys(hub, failures)
	_test_click_hotspot(hub, failures)
	_test_visible_station_pixels(hub, failures)
	_test_marker_copy(hub, failures)
	_test_dynamic_progression(hub, failures)
	_test_next_objective(hub, failures)
	_test_landmarks_follow_world(hub, failures)
	_test_nav_state_matches_cards(hub, failures)
	_test_nav_activation_routing(hub, failures)
	_test_goal_and_road_guide(hub, failures)
	_test_nav_locked_copy(hub, failures)
	_test_first_hunt_rack_availability(hub, failures)
	_test_nav_boss_crossing(hub, failures)
	_test_nav_long_status_and_bounds(hub, failures)
	_test_hub_prompt_stays_minimal(hub, failures)
	_test_hub_information_copy_and_details(hub, failures)
	_test_compact_ui_sizes(failures)
	_test_growth_story_and_settings(hub, failures)
	_test_resident_prompt(hub, failures)
	_test_nav_keyboard_access(hub, failures)
	_test_world_display_scale(hub, failures)
	_test_render_contract(hub, failures)
	_test_playable_bounds(hub, failures)
	_test_split_row_fade(hub, failures)
	_test_framing_contract(hub, failures)
	_test_unpublished_assets(hub, failures)

	scene_tree.root.remove_child(temporary_root)
	temporary_root.free()
	return failures


func _view_of(hub):
	return hub.get_hub_view()


func _design_of(hub, world_point: Vector2) -> Vector2:
	## The hub keeps the old design-space API: design pixels are twice the world
	## pixels, and the follow camera is taken back off when the click lands.
	return _view_of(hub).design_point_for_world(world_point, Vector2.ZERO, Vector2.ONE)


func _test_entry_table(hub, failures: Array[String]) -> void:
	## The published layout exposes exactly five prototype hub entries, each
	## with a usable interaction radius inside the world.
	var view = _view_of(hub)
	var world: Vector2 = view.world_size()
	for feature_id: String in FEATURE_IDS:
		var entry: Dictionary = view.entry_for(feature_id)
		_expect(not entry.is_empty(), "base hub: hub entry %s is missing from the world" % feature_id, failures)
		if entry.is_empty():
			continue
		var feet := entry.get("feet", Vector2.ZERO) as Vector2
		var radius := float(entry.get("radius", 0.0))
		_expect(radius >= 48.0, "base hub: %s interaction radius collapsed to %f" % [feature_id, radius], failures)
		_expect(feet.x >= 0.0 and feet.y >= 0.0 and feet.x <= world.x and feet.y <= world.y, "base hub: %s placement sits outside the world" % feature_id, failures)
	_expect(view.entry_for("immortality").is_empty(), "base hub: an unpublished facility appeared as an invisible hotspot", failures)
	_expect(hub.get_feature_marker_text("immortality").is_empty(), "base hub: an unpublished facility still drew a marker", failures)
	_expect(hub.get_world_feature_position("immortality").is_equal_approx(BaseHubScreenScript.LEGACY_FEATURE_POSITIONS["immortality"]), "base hub: the legacy facility lookup stopped answering in design space", failures)


func _test_initial_position(hub, failures: Array[String]) -> void:
	var view = _view_of(hub)
	var world_start: Vector2 = view.hero_world_position()
	_expect(hub.get_hero_position().is_equal_approx(world_start / 0.5), "base hub: hero position is not the live world position", failures)
	_expect(world_start.distance_to(_uv_world(_town_layout().hero_start_uv, view.world_size())) <= 0.01, "base hub: hero start drifted far away from the contract start", failures)
	_expect(hub.get_nearby_feature_id().is_empty(), "base hub: hero must start away from every station", failures)


func _test_delta_movement(hub, failures: Array[String]) -> void:
	var origin := _uv_world(_town_layout().hero_start_uv, _view_of(hub).world_size()) * 2.0
	hub.set_hero_position(origin)
	hub.move_hero(Vector2.RIGHT, 0.1)
	var short_move: Vector2 = hub.get_hero_position() - origin
	hub.set_hero_position(origin)
	hub.move_hero(Vector2.RIGHT, 0.2)
	var long_move: Vector2 = hub.get_hero_position() - origin
	_expect(short_move.x > 0.0 and is_zero_approx(short_move.y), "base hub: move_hero did not change position in the requested direction", failures)
	_expect(is_equal_approx(long_move.x, short_move.x * 2.0) and is_zero_approx(long_move.y), "base hub: movement is not proportional to delta", failures)


func _test_concept_framing(hub, failures: Array[String]) -> void:
	var view = _view_of(hub)
	var layout := _town_layout()
	var audit: Dictionary = view.render_audit()
	_expect(audit.view_size == Vector2(640, 360) and view.world_viewport.size == Vector2i(640, 360), "base hub: close follow camera is wrong", failures)
	_expect(view.hero_screen_anchor() == Vector2(layout.hero_screen_anchor[0], layout.hero_screen_anchor[1]), "base hub: formal camera anchor differs from the published layout", failures)
	_expect(view.world_size() == Vector2(1536, 960), "base hub: expanded town dimensions changed", failures)
	_expect(audit.view_size.x < view.world_size().x * 0.5 and audit.view_size.y < view.world_size().y * 0.5, "base hub: the whole town is visible without walking", failures)
	_expect(not view._collision.is_blocked(view.hero_world_position()), "base hub: published spawn intersects a footprint", failures)



func _test_diagonal_normalization(hub, failures: Array[String]) -> void:
	var origin := _uv_world(_town_layout().hero_start_uv, _view_of(hub).world_size()) * 2.0
	var delta := 0.1
	hub.set_hero_position(origin)
	hub.move_hero(Vector2.RIGHT, delta)
	var cardinal_distance: float = hub.get_hero_position().distance_to(origin)
	hub.set_hero_position(origin)
	hub.move_hero(Vector2(1.0, 1.0), delta)
	var diagonal_offset: Vector2 = hub.get_hero_position() - origin
	_expect(diagonal_offset.x > 0.0 and diagonal_offset.y > 0.0, "base hub: diagonal movement did not change both axes", failures)
	_expect(is_equal_approx(diagonal_offset.length(), cardinal_distance), "base hub: diagonal movement is faster than cardinal movement", failures)


func _test_configured_input_actions(hub, failures: Array[String]) -> void:
	var origin := _uv_world(_town_layout().hero_start_uv, _view_of(hub).world_size()) * 2.0
	hub.set_hero_position(origin)
	Input.action_press("move_right")
	hub._process(0.1)
	Input.action_release("move_right")
	_expect(hub.get_hero_position().x > origin.x, "base hub: configured movement action did not drive the hero", failures)


func _test_playable_bounds(hub, failures: Array[String]) -> void:
	## _test_render_contract installed the explicit obstacle-free fixture. Exact
	## boundary clamping remains required; live walls have their own travel checks.
	## Hub positions stay in the screen's design space, so the renderer's world
	## bounds are doubled here before they are compared.
	var bounds: Rect2 = _view_of(hub).world_bounds()
	bounds = Rect2(bounds.position * 2.0, bounds.size * 2.0)
	var center := bounds.get_center()
	var cases := [
		{"direction": Vector2.LEFT, "expected": Vector2(bounds.position.x, center.y), "side": "left"},
		{"direction": Vector2.RIGHT, "expected": Vector2(bounds.end.x, center.y), "side": "right"},
		{"direction": Vector2.UP, "expected": Vector2(center.x, bounds.position.y), "side": "top"},
		{"direction": Vector2.DOWN, "expected": Vector2(center.x, bounds.end.y), "side": "bottom"},
	]
	for test_case: Dictionary in cases:
		hub.set_hero_position(center)
		hub.move_hero(test_case.direction as Vector2, 100.0)
		_expect(hub.get_hero_position().is_equal_approx(test_case.expected as Vector2), "base hub: hero did not clamp to the %s bound" % String(test_case.side), failures)


func _test_walk_to_external_stations(hub, failures: Array[String]) -> void:
	var view = _view_of(hub)
	var layout := _town_layout()
	var events: Array[String] = []
	hub.contract_requested.connect(func(): events.append("contract"))
	hub.feature_requested.connect(func(id: String): events.append(id))
	for id: String in FEATURE_IDS:
		var route: Array = layout.routes_uv[id]
		hub.set_hero_position(_uv_world(route[0], view.world_size()) * 2.0)
		for uv: Array in route:
			var target := _uv_world(uv, view.world_size())
			var steps := 0
			while view.hero_world_position().distance_to(target) > 0.05 and steps < 900:
				var offset: Vector2 = target - view.hero_world_position()
				hub.move_hero(offset, minf(1.0 / 60.0, offset.length() / view.HERO_SPEED))
				steps += 1
			_expect(view.hero_world_position().distance_to(target) <= 0.05 and not view._collision.is_blocked(view.hero_world_position()), "base hub: published route blocked: %s / %s" % [id, target], failures)
		_expect(hub.get_nearby_feature_id() == id, "base hub: authored approach did not select " + id, failures)
		var before := events.size()
		var event := InputEventKey.new()
		event.physical_keycode = KEY_E
		event.pressed = true
		hub._unhandled_key_input(event)
		_expect(events.size() == before + 1 and events.back() == id, "base hub: authored E approach did not route once: " + id, failures)



func _test_bounded_live_camera(hub, failures: Array[String]) -> void:
	var view = _view_of(hub)
	var camera_limit: Vector2 = view.world_size() - Vector2(view.world_viewport.size)
	for point: Vector2 in [Vector2(20,20), Vector2(1004,620), Vector2(548,464), Vector2(870,615)]:
		view.teleport_hero(point)
		var camera: Vector2 = view.camera_world_offset()
		_expect(camera.x >= 0 and camera.y >= 0 and camera.x <= camera_limit.x and camera.y <= camera_limit.y, "base hub: camera exposes outside formal world", failures)
		var design: Vector2 = view.design_point_for_world(point, Vector2.ZERO, Vector2.ONE)
		_expect(view.world_point_at_design(design, Vector2.ZERO, Vector2.ONE).is_equal_approx(point), "base hub: camera input conversion is not reversible", failures)
	for id: String in FEATURE_IDS:
		var point: Vector2 = view.entry_for(id).feet
		view.teleport_hero(point)
		var screen: Vector2 = view.design_point_for_world(point, Vector2.ZERO, Vector2.ONE)
		_expect(screen.y > hub._header.get_global_rect().end.y and screen.y < 720.0, "base hub: authored approach is hidden by UI: " + id, failures)



func _test_feature_activation(hub, failures: Array[String]) -> void:
	var events := {"contract_count": 0, "feature_ids": []}
	hub.contract_requested.connect(func() -> void: events.contract_count += 1)
	hub.feature_requested.connect(func(feature_id: String) -> void: events.feature_ids.append(feature_id))

	for feature_id: String in FEATURE_IDS:
		hub.set_hero_position(hub.get_world_feature_position(feature_id))
		_expect(hub.get_nearby_feature_id() == feature_id, "base hub: standing on the %s station did not select it" % feature_id, failures)
		var contracts_before: int = events.contract_count
		var features_before: int = events.feature_ids.size()
		_expect(hub.activate_nearby_feature(), "base hub: %s station did not activate" % feature_id, failures)
		if feature_id == "contract":
			_expect(events.contract_count == contracts_before + 1, "base hub: contract activation did not emit contract_requested exactly once", failures)
			_expect(events.feature_ids.size() == features_before, "base hub: contract activation emitted feature_requested", failures)
		else:
			_expect(events.contract_count == contracts_before, "base hub: %s activation emitted contract_requested" % feature_id, failures)
			_expect(events.feature_ids.size() == features_before + 1 and String(events.feature_ids[-1]) == feature_id, "base hub: %s activation did not emit its exact feature_requested ID" % feature_id, failures)

	hub.set_hero_position(_view_of(hub).world_bounds().position)
	var contracts_before: int = events.contract_count
	var features_before: int = events.feature_ids.size()
	_expect(hub.get_nearby_feature_id().is_empty(), "base hub: away position unexpectedly selected a station", failures)
	_expect(not hub.activate_nearby_feature(), "base hub: activation away from hotspots must return false", failures)
	_expect(events.contract_count == contracts_before and events.feature_ids.size() == features_before, "base hub: activation away from hotspots emitted a signal", failures)


func _test_interaction_keys(hub, failures: Array[String]) -> void:
	var events: Array[String] = []
	hub.contract_requested.connect(func() -> void: events.append("contract"))
	hub.feature_requested.connect(func(feature_id: String) -> void: events.append(feature_id))

	hub.set_hero_position(hub.get_world_feature_position("forge"))
	var e_event := InputEventKey.new()
	e_event.physical_keycode = KEY_E
	e_event.pressed = true
	hub._unhandled_key_input(e_event)
	_expect(events == ["forge"], "base hub: E did not activate the nearby station exactly once", failures)

	hub.set_hero_position(hub.get_world_feature_position("contract"))
	var space_event := InputEventKey.new()
	space_event.physical_keycode = KEY_SPACE
	space_event.pressed = true
	hub._unhandled_key_input(space_event)
	_expect(events == ["forge", "contract"], "base hub: Space did not activate the nearby contract exactly once", failures)


func _test_click_hotspot(hub, failures: Array[String]) -> void:
	## Real pointer path: a screen point is converted through the design canvas and
	## the follow camera exactly like a mouse click, never by calling the
	## renderer's hit test directly.
	var events: Array[String] = []
	hub.feature_requested.connect(func(feature_id: String) -> void: events.append(feature_id))
	hub.contract_requested.connect(func() -> void: events.append("contract"))
	var view = _view_of(hub)
	var forge_world: Vector2 = view.entry_for("forge").get("feet", Vector2.ZERO)
	var forge_design: Vector2 = _design_of(hub, forge_world)
	_expect(hub.click_at_design_point(forge_design), "base hub: clicking the forge station did not select it", failures)
	_expect(events.is_empty() and hub.wayfinding_report().id == "forge", "base hub: a distant station opened instead of setting directions", failures)
	hub.set_hero_position(forge_world * 2.0)
	forge_design = _design_of(hub, forge_world)
	_expect(hub.click_at_design_point(forge_design), "base hub: clicking the nearby forge did not activate", failures)
	_expect(events == ["forge"], "base hub: clicking the forge station did not emit its feature_requested ID", failures)
	var far_point := forge_design + Vector2(4000.0, 4000.0)
	_expect(not hub.click_at_design_point(far_point), "base hub: a click on empty ground must not activate a station", failures)
	_expect(events.size() == 1, "base hub: a click on empty ground emitted a signal", failures)
	## And the same click into every other published station, through the camera.
	for feature_id: String in FEATURE_IDS:
		var before: int = events.size()
		var station_feet: Vector2 = view.entry_for(feature_id).get("feet", Vector2.ZERO)
		hub.set_hero_position(station_feet * 2.0)
		_expect(hub.click_at_design_point(_design_of(hub, station_feet)), "base hub: a click at the authored hero anchor did not select %s" % feature_id, failures)
		_expect(events.size() == before + 1, "base hub: a world-space click on %s emitted nothing" % feature_id, failures)
		_expect(events.size() == before + 1 and events.back() == feature_id,
			"base hub: click on %s was stolen by another station" % feature_id, failures)


func _test_visible_station_pixels(hub, failures: Array[String]) -> void:
	var view = _view_of(hub)
	var layout := _town_layout()
	var pixels: Image = load(String(layout.scene_texture)).get_image()
	for placement: Dictionary in layout.placements:
		if not FEATURE_IDS.has(String(placement.get("interaction", ""))): continue
		var uv: Array = placement.feet_uv
		var texel := Vector2i(int(float(uv[0]) * pixels.get_width()), int(float(uv[1]) * pixels.get_height()))
		_expect(pixels.get_pixelv(texel).a > 0.0, "base hub: facility anchor lacks published scene pixels: " + String(placement.id), failures)
		var world := _uv_world(uv, view.world_size())
		_expect(view.hit_test(world) == placement.interaction, "base hub: formal facility pixels select a different route: " + String(placement.id), failures)



func _test_marker_copy(hub, failures: Array[String]) -> void:
	## Station names now come from the main-owned layout; route prose stays out of
	## the live hub, so a layout label is the only expected change.
	var renderer = _view_of(hub)
	for feature_id: String in ["contract", "loadout", "forge", "proxy"]:
		var marker: String = hub.get_feature_marker_text(feature_id)
		var label := String(renderer.entry_for(feature_id).get("label", ""))
		_expect(not marker.is_empty(), "base hub: %s marker is empty" % feature_id, failures)
		if not label.is_empty():
			_expect(marker.contains(label), "base hub: %s marker lost the station name %s" % [feature_id, label], failures)
		_expect(not marker.contains("接取，") and not marker.contains("匿名委托") and not marker.contains("只读样例"), "base hub: %s marker leaked route prose into the hub" % feature_id, failures)


func _test_dynamic_progression(hub, failures: Array[String]) -> void:
	hub.present({"progression": {
		"threshold_colossus_defeated": false,
		"proxy_unlocked": false,
		"auto_contract_wins": 0,
		"early_game_complete": false,
	}})
	_expect(hub.get_feature_marker_text("proxy").contains("封印中"), "base hub: locked proxy marker was not shown", failures)
	_expect(hub.get_progress_text().contains("Build …") and hub.get_progress_text().contains("巨像 …") and hub.get_progress_text().contains("Auto …"), "base hub: incomplete early-game progress was not shown", failures)
	hub.present({
		"training": {"reports_by_fingerprint": {
			"exponential-fingerprint": {"build_fingerprint": "exponential-fingerprint", "state": "exponential"},
		}},
		"progression": {
			"threshold_colossus_defeated": false,
			"proxy_unlocked": false,
			"auto_contract_wins": 0,
			"early_game_complete": false,
		},
	})
	_expect(hub.get_progress_text().contains("Build ✓") and hub.get_progress_text().contains("巨像 …"), "base hub: verified exponential Build did not complete the training objective", failures)
	hub.present({
		"training": {"reports_by_fingerprint": {
			"exponential-fingerprint": {"build_fingerprint": "other-fingerprint", "state": "exponential"},
		}},
		"progression": {
			"threshold_colossus_defeated": false,
			"proxy_unlocked": false,
			"auto_contract_wins": 0,
			"early_game_complete": false,
		},
	})
	_expect(hub.get_progress_text().contains("Build …"), "base hub: mismatched report fingerprint impersonated a verified Build", failures)
	hub.present({"progression": {
		"build_training_complete": true,
		"threshold_colossus_defeated": true,
		"proxy_unlocked": true,
		"auto_contract_wins": 1,
		"early_game_complete": true,
	}})
	_expect(hub.get_feature_marker_text("proxy").contains("已解锁"), "base hub: unlocked proxy marker was not shown", failures)
	_expect(hub.get_progress_text().contains("Build ✓") and hub.get_progress_text().contains("巨像 ✓") and hub.get_progress_text().contains("Auto ✓"), "base hub: completed early-game progress was not shown", failures)


func _test_next_objective(hub, failures: Array[String]) -> void:
	hub.present({"initial_class": "ranger", "resources": {"law_tallies": {"inscribe": 2, "rewrite": 1, "refine": 3}}}, {}, "Tutorial complete", {})
	_expect(hub._profile_label.text.contains("游侠") and not hub._profile_label.text.contains("ranger"), "base hub: player-facing class name leaked internal id", failures)
	_expect(hub._profile_label.tooltip_text.contains("律筹：添铸 2 · 改写 1 · 精炼 3") and not hub._profile_label.tooltip_text.contains("骰"), "base hub: law tally inventory was not available with the canonical terminology", failures)
	_expect(hub._detail_status_label.text.contains("游侠基础教程已完成") and not hub._detail_status_label.text.contains("Tutorial complete"), "base hub: tutorial feedback was not localized", failures)
	_expect(not hub._detail_status_label.text.contains("Build"), "base hub: objective repeats debug-like progress abbreviations", failures)
	hub.present(
		{"progression": {"threshold_colossus_defeated": false, "proxy_unlocked": false, "auto_contract_wins": 0, "early_game_complete": false}},
		{},
		"",
		{"ok": true, "next_mainline_node_id": "mainline_03_first_elite", "earned_reward_tags": ["starter_loadout", "hunter_mark_skill", "equipment_compare_unlock", "dash_skill"], "early_game_complete": false}
	)
	_expect(hub.get_next_objective_text().contains("首个精英"), "base hub: campaign snapshot did not produce an actionable next objective", failures)
	_expect(hub.get_feature_marker_text("contract").contains("主线 03"), "base hub: contract marker did not reflect the next authored node", failures)
	_expect(hub.get_feature_marker_text("loadout").contains("比较已开放") and hub.get_feature_marker_text("forge").contains("封印中"), "base hub: post-first-hunt equipment availability disagreed with its authored reward", failures)
	hub.present(
		{"progression": {"threshold_colossus_defeated": true, "proxy_unlocked": true, "auto_contract_wins": 1, "early_game_complete": true}},
		{},
		"",
		{"ok": true, "next_mainline_node_id": "", "earned_reward_tags": ["equipment_compare_unlock", "law_forge_unlock", "early_campaign_complete"], "early_game_complete": true}
	)
	_expect(hub.get_next_objective_text().contains("前期毕业完成"), "base hub: completed campaign did not expose a stable follow-up objective", failures)
	_expect(hub.get_feature_marker_text("loadout").contains("比较已开放") and hub.get_feature_marker_text("forge").contains("已解锁"), "base hub: authored facility rewards did not update their world markers", failures)


func _test_render_contract(hub, failures: Array[String]) -> void:
	## Visual regression against the approved concept: feet-anchored sprite layers,
	## the world field at the origin, split-row bands in the right layers and a
	## camera that follows the snapped avatar. The fixture pair stands in for the
	## main-owned atlas and layout so the assertions never depend on publication.
	var view = _view_of(hub)
	_install_fixture(view)
	_expect(view.is_ready(), "base hub: a complete fixture atlas did not put the renderer in its ready state", failures)
	var audit: Dictionary = view.render_audit()
	var layers := audit.get("layers", {}) as Dictionary
	## Three unsplit stations, the split station's head and the avatar all share
	## the y-sorted layer; only the split station's lower band sits under it.
	_expect(int(layers.get("actors", 0)) == 6, "base hub: the y-sorted layer lost a station, the avatar or its shadow", failures)
	_expect(int(layers.get("ground_layer", 0)) == 1, "base hub: ground-layer placement was not drawn", failures)
	_expect(int(layers.get("object_lower", 0)) == 1, "base hub: the split station lower band is not drawn under the avatar layer", failures)
	var nodes := audit.get("sprite_nodes", []) as Array
	_expect("well" in nodes and "pebble" in nodes and "smithy.upper" in nodes and "smithy.lower" in nodes, "base hub: layout placements were not drawn under their own ids: %s" % str(nodes), failures)
	var forge_rect: Rect2 = view._drawn_rect(view.entry_for("forge"))
	_expect(forge_rect.size.is_equal_approx(Vector2(48.0, 64.0)), "base hub: forge cell size does not match its sprite rect", failures)
	_expect(forge_rect.position.is_equal_approx(Vector2(404.0, 442.0)), "base hub: the forge is not anchored by its own feet and anchor", failures)
	var pebble := view.ground_layer.get_node_or_null(NodePath("Ground_pebble")) as Sprite2D
	_expect(pebble != null, "base hub: the fixture decoration node is missing", failures)
	if pebble != null:
		_expect(pebble.region_rect.is_equal_approx(Rect2(64.0, 0.0, 32.0, 24.0)), "base hub: a placement no longer cuts its own atlas rect", failures)
		_expect(pebble.position.is_equal_approx(Vector2(120.0, 440.0)), "base hub: a placement no longer stands on its declared feet", failures)
	view.teleport_hero(Vector2(200.0, 200.0))
	view._process(0.016)
	_expect(view.camera_world_offset().is_equal_approx(Vector2(200.0, 200.0) - Vector2(HamletConceptViewScript.NATIVE_VIEW) * 0.5), "base hub: the camera no longer follows the snapped avatar", failures)
	_expect(view.actor_layer.y_sort_enabled, "base hub: the avatar layer lost its depth sorting", failures)


func _test_split_row_fade(hub, failures: Array[String]) -> void:
	## The half-tone rule: a stand's upper band fades while the avatar passes
	## behind it and stays solid once the avatar is below its feet.
	var view = _view_of(hub)
	_install_fixture(view)
	var audit: Dictionary = view.render_audit()
	var layers := audit.get("layers", {}) as Dictionary
	_expect(int(layers.get("object_lower", 0)) == 1 and int(layers.get("actors", 0)) == 6, "base hub: the split station did not divide across the y-sorted layers", failures)
	var lower := view.object_lower_layer.get_node_or_null(NodePath("Lower_smithy")) as Sprite2D
	var head := view.actor_layer.get_node_or_null(NodePath("Upper_smithy")) as Sprite2D
	_expect(lower != null and head != null, "base hub: the split station lost its head or foot band", failures)
	if lower == null or head == null:
		return
	## The station's own top rows are the standing band, drawn under the avatar
	## layer; the bottom rows are the foot, drawn with the avatar. Positions are
	## checked against the atlas rect so a moved cell still passes.
	var smithy: Dictionary = view._sprites["station.smithy"]
	var smithy_rect: Array = smithy.get("rect", [])
	var smithy_anchor: Array = smithy.get("anchor", [])
	_expect(is_equal_approx(head.region_rect.position.y, float(smithy_rect[1])) and is_equal_approx(head.region_rect.size.y, 40.0), "base hub: the standing band must be the source rows 0..split_row", failures)
	_expect(is_equal_approx(lower.region_rect.position.y, float(smithy_rect[1]) + 40.0) and is_equal_approx(lower.region_rect.size.y, 56.0), "base hub: the foot band must be the source rows split_row..end", failures)
	_expect(is_equal_approx(head.offset.y, -float(smithy_anchor[1])) and is_equal_approx(lower.offset.y, -float(smithy_anchor[1]) + 40.0), "base hub: the split bands are not placed on their own anchor", failures)
	view.teleport_hero(Vector2(420.0, 195.0))
	view._process(0.016)
	_expect(is_equal_approx(head.modulate.a, HamletConceptViewScript.SPLIT_FADE_ALPHA), "base hub: the standing band did not fade while the avatar passed behind it", failures)
	_expect(is_equal_approx(lower.modulate.a, 1.0), "base hub: the station foot must stay solid while the avatar stands in the opening", failures)
	view.teleport_hero(Vector2(420.0, 400.0))
	view._process(0.016)
	_expect(is_equal_approx(head.modulate.a, 1.0), "base hub: the standing band stayed faded once the avatar stood below the station", failures)
	view.teleport_hero(Vector2(420, 250))
	view._process(0.016)
	_expect(is_equal_approx(head.modulate.a, 1.0), "base hub: head overlap must not fade a building when hero feet are in front", failures)


func _test_world_display_scale(hub, failures: Array[String]) -> void:
	var view = _view_of(hub)
	for dimensions: Vector2 in [Vector2(1280,720), Vector2(1600,900)]:
		view.set_world_scale(2, dimensions)
		var native := Vector2(view.world_viewport.size)
		var expected := minf(dimensions.x / native.x, dimensions.y / native.y)
		_expect(view.world_display.scale.is_equal_approx(Vector2.ONE * expected), "base hub: formal town does not fit observation range", failures)
		_expect(Rect2(Vector2.ZERO, dimensions).encloses(view.world_display.get_global_rect()), "base hub: formal town left host bounds", failures)
		var hero: Vector2 = view.hero_world_position()
		var screen: Vector2 = view.design_point_for_world(hero, Vector2.ZERO, Vector2.ONE)
		_expect(view.world_point_at_design(screen, Vector2.ZERO, Vector2.ONE).is_equal_approx(hero), "base hub: resized actual avatar click lost camera offset", failures)
	view.set_world_scale(2, Vector2(1280,720))



func _test_unpublished_assets(hub, failures: Array[String]) -> void:
	## While the pair is missing the world must stay a plain floor: no sprite, no
	## placeholder building, and no unpublished world hotspot is invented.
	var view = _view_of(hub)
	view.configure({}, {})
	_expect(not view.is_ready(), "base hub: an empty atlas must not report ready assets", failures)
	var audit: Dictionary = view.render_audit()
	var layers := audit.get("layers", {}) as Dictionary
	_expect(int(layers.get("actors", 0)) == 0 and int(layers.get("ground_layer", 0)) == 0, "base hub: pending assets drew sprites anyway", failures)
	_expect(int(layers.get("skirt", 0)) == 0, "base hub: pending assets drew a ground field", failures)
	for feature_id: String in FEATURE_IDS:
		_expect(not view.entry_for(feature_id).is_empty(), "base hub: %s entry disappeared while assets are pending" % feature_id, failures)
	_expect(not view.pending_reasons().is_empty(), "base hub: missing assets were not reported as pending", failures)


func _test_framing_contract(hub, failures: Array[String]) -> void:
	var view = _view_of(hub)
	var layout := _fixture_layout()
	layout["hero_screen_anchor"] = [320, 260]
	view.configure(_fixture_atlas(), layout)
	view.set_world_scale(2, Vector2(1280, 720))
	for world_point: Vector2 in [Vector2(20, 20), Vector2(1004, 620), Vector2(501.75, 400.5)]:
		view.teleport_hero(world_point)
		var camera: Vector2 = view.camera_world_offset()
		_expect(camera == camera.floor(), "base hub: framing introduced a fractional camera", failures)
		_expect(camera == Vector2(view.hero_snapped_position()) - view.hero_screen_anchor(),
			"base hub: legacy layout lost its unrestricted follow camera at the world edge", failures)
		var screen: Vector2 = view.design_point_for_world(world_point, Vector2.ZERO, Vector2.ONE)
		var restored: Vector2 = view.world_point_at_design(screen, Vector2.ZERO, Vector2.ONE)
		_expect(restored.is_equal_approx(world_point), "base hub: framed mouse transform is not reversible", failures)
	view.configure(_fixture_atlas(), _fixture_layout())
	_expect(view.hero_screen_anchor() == Vector2(320, 180), "base hub: legacy layout must retain its centre anchor", failures)
	for invalid: Variant in [[320.5, 260], [-1, 260], [640, 260], [320, 360], "320,260"]:
		layout["hero_screen_anchor"] = invalid
		view.configure(_fixture_atlas(), layout)
		_expect(not view.is_ready() and view.hero_screen_anchor() == Vector2(320, 180),
			"base hub: malformed screen anchor must fail visibly and use the safe centre", failures)


func _hero_foot_design_point(hub) -> Vector2:
	## Where the entry foot point of the avatar actually lands on the 1280x720
	## design canvas with the live camera and world scale of this screen.
	var view = _view_of(hub)
	if view == null:
		return Vector2.ZERO
	return view.design_point_for_world(view.hero_world_position(), Vector2.ZERO, Vector2.ONE)


func _design_rect_of(hub, world_rect: Rect2) -> Rect2:
	return Rect2(_design_of(hub, world_rect.position), world_rect.size * 2.0)


func _visible_hits_in(hub, design_rect: Rect2, nodes: Array) -> int:
	## Opaque pixels of the given drawn nodes under a design-space rectangle, on the
	## same 4px sampling step the station test uses. The rectangle goes back through
	## the live camera, and every sample is mapped into the sprite's own region, so
	## split rows are measured where they are actually drawn.
	var view = _view_of(hub)
	var world := Rect2(design_rect.position * 0.5 + view.camera_world_offset(), design_rect.size * 0.5)
	var hits := 0
	for node: Sprite2D in nodes:
		if node == null or node.texture == null:
			continue
		var region: Rect2 = node.region_rect
		var drawn := Rect2(node.position + node.offset, region.size)
		var overlap := drawn.intersection(world)
		if overlap.size.x <= 0.0 or overlap.size.y <= 0.0:
			continue
		var pixels: Image = node.texture.get_image()
		for y in range(int(floorf(overlap.position.y)), int(ceilf(overlap.end.y)), 4):
			for x in range(int(floorf(overlap.position.x)), int(ceilf(overlap.end.x)), 4):
				var texel := Vector2i(int(region.position.x) + x - int(drawn.position.x), int(region.position.y) + y - int(drawn.position.y))
				if texel.x < 0 or texel.y < 0 or texel.x >= pixels.get_width() or texel.y >= pixels.get_height():
					continue
				if pixels.get_pixelv(texel).a > 0.0:
					hits += 1
	return hits


func _point_rect_distance(rect: Rect2, point: Vector2) -> float:
	if rect.has_point(point):
		return 0.0
	var clamped := Vector2(clampf(point.x, rect.position.x, rect.end.x), clampf(point.y, rect.position.y, rect.end.y))
	return point.distance_to(clamped)


## Fresh base, entry framing: the relocated information must not lay a band over
## the world it was written for. The stands the fresh base reaches, the avatar and
## the tower are measured from the live sprites' own alpha, so this keeps following
## the published art instead of a hand-copied rectangle table.
func _test_hub_info_keeps_world_visible(hub, failures: Array[String]) -> void:
	var header: Rect2 = hub._header.get_global_rect()
	var canvas := Rect2(hub._design_canvas.global_position, hub._design_canvas.size * hub._design_canvas.scale)
	_expect(canvas.encloses(header), "base hub: persistent UI left the town canvas", failures)
	_expect(hub._header.size.y <= 80,
		"base hub: the persistent header grew back into a narrative row", failures)
	_expect(hub._header.is_ancestor_of(hub._objective_label) and hub._objective_label.is_visible_in_tree(),
		"base hub: the current objective left the top band", failures)
	_expect(hub._objective_label.get_theme_font_size("font_size") == 22
		and hub._profile_label.get_theme_font_size("font_size") >= 18,
		"base hub: the compact header shrank its text", failures)
	for button_name: String in ["OpenCharacter", "OpenStory", "HubInformationToggle"]:
		var button := hub.find_child(button_name, true, false) as Button
		_expect(button != null and header.encloses(button.get_global_rect()) and button.is_visible_in_tree(),
			"base hub: a persistent top action is hidden or outside the header: " + button_name, failures)
	_expect(not hub._detail_panel.is_visible_in_tree()
		and not (hub.find_child("ReturnToTitle", true, false) as Button).is_visible_in_tree(),
		"base hub: narrative/return-to-title still occupies the default town frame", failures)
	_expect(hub.find_child("TownStoryCue", true, false) == null,
		"base hub: a remote resident/title is still selected for a persistent narrative strip", failures)
	var entry_foot := BaseHubScreenScript.HERO_ENTRY_FOOT_ANCHOR
	_expect(not BaseHubScreenScript.HEADER_RECT.has_point(entry_foot), "base hub: persistent UI covers the entry foot", failures)
	_expect(hub.get_prompt_rect() == Rect2() and not hub._nearby_panel.visible,
		"base hub: proximity prompt is visible before approaching a station", failures)


func _test_hub_prompt_stays_minimal(hub, failures: Array[String]) -> void:
	var view = _view_of(hub)
	for feature_id: String in FEATURE_IDS:
		hub.set_hero_position(hub.get_world_feature_position(feature_id))
		_expect(hub.get_nearby_feature_id() == feature_id, "base hub: standing on %s did not select the stand for its prompt" % feature_id, failures)
		var prompt: Rect2 = hub.get_prompt_rect()
		_expect(prompt.size.x > 0.0 and prompt.size.y > 0.0, "base hub: %s has no proximity prompt" % feature_id, failures)
		if prompt.size.x <= 0.0 or prompt.size.y <= 0.0:
			continue
		_expect(hub._nearby_label.text == "[E / Space] 进入 %s" % hub._nav_title(feature_id), "base hub: the %s prompt no longer names the stand E opens" % feature_id, failures)
		_expect(prompt.position.x >= 0.0 and prompt.end.x <= 1280.0, "base hub: the %s prompt left the canvas horizontally" % feature_id, failures)
		_expect(prompt.end.y <= BaseHubScreenScript.DESIGN_SIZE.y, "base hub: the %s prompt left the canvas vertically" % feature_id, failures)
		_expect(prompt.size.x <= BaseHubScreenScript.PROMPT_MAX_WIDTH and prompt.size.y <= BaseHubScreenScript.PROMPT_HEIGHT, "base hub: the %s prompt grew past its published badge" % feature_id, failures)
		_expect(not prompt.has_point(BaseHubScreenScript.HERO_ENTRY_FOOT_ANCHOR), "base hub: the %s prompt covers the avatar foot point" % feature_id, failures)
		_expect(_point_rect_distance(prompt, _hero_foot_design_point(hub)) <= 48.0, "base hub: the %s prompt drifted away from the avatar" % feature_id, failures)
		_expect(not prompt.intersects(BaseHubScreenScript.HEADER_RECT), "base hub: the %s prompt overlaps the compact information row" % feature_id, failures)
		_expect(_visible_hits_in(hub, prompt, [view._hero_sprite]) == 0, "base hub: the %s prompt covers the avatar" % feature_id, failures)
		## The badge is a transient element attached to the avatar: it never covers the
		## avatar, never crosses into the navigation band and never leaves the canvas.
		## The world art under it is whatever the follow camera has scrolled in, so the
		## silhouette check belongs to the fresh entry frame, which the information test
		## above measures directly against the published alpha of the stands.
		_expect(prompt.position.y >= BaseHubScreenScript.HEADER_RECT.end.y and prompt.end.y <= BaseHubScreenScript.DESIGN_SIZE.y, "base hub: the %s prompt left the safe vertical band" % feature_id, failures)
	## Away from every stand the badge is gone again.
	hub.set_hero_position(_view_of(hub).world_bounds().position)
	_expect(hub.get_prompt_rect() == Rect2() and not hub._nearby_panel.visible, "base hub: the proximity prompt stayed on screen away from every stand", failures)


## Long status and state copy stay reachable: one clipped row plus a tooltip and an
## explicit toggle, with the critical objective untouched in the strip. Known short
## English tokens become Chinese, unknown values are passed through verbatim.
func _test_hub_information_copy_and_details(hub, failures: Array[String]) -> void:
	var long_status := "装备已更新：裂风长弓（稀有）· 已写入构筑三号槽位 · 本次掉落计入图鉴与收藏进度，下一目标不受影响"
	hub.present(_pre_boss_profile(), {"outcome": "victory", "rewards": {"equipment_drop_count": 2}}, long_status, {})
	_expect(hub._detail_status_label.text == long_status and hub._detail_status_label.autowrap_mode == TextServer.AUTOWRAP_WORD_SMART,
		"base hub: optional narrative lost or cropped the full status", failures)
	_expect(hub._detail_status_label.tooltip_text == long_status and hub._info_toggle.tooltip_text.contains(long_status),
		"base hub: full status is unavailable from the narrative entry", failures)
	_expect(not hub._detail_panel.visible and not hub.information_details_expanded(), "base hub: narrative opened without being requested", failures)
	var objective_rect: Rect2 = hub._objective_label.get_global_rect()
	(hub.find_child("HubInformationToggle", true, false) as Button).pressed.emit()
	_expect(hub._detail_panel.visible and hub.information_details_expanded(), "base hub: narrative entry did not open", failures)
	_expect(hub._detail_result_label.text.contains("胜利") and hub._detail_result_label.text.contains("装备 2 件"),
		"base hub: optional narrative lost the actual settlement reading", failures)
	_expect(hub._detail_help_label.text == BaseHubScreenScript.HELP_COPY_TEXT
		and hub._detail_help_label.text.contains("Tab") and hub._detail_help_label.text.contains("F1"),
		"base hub: complete keyboard guidance is unavailable", failures)
	_expect(hub._objective_label.get_global_rect() == objective_rect and hub._objective_label.is_visible_in_tree()
		and not hub._detail_panel.get_global_rect().intersects(objective_rect),
		"base hub: opening narrative moved/covered the current objective", failures)
	_expect(hub._detail_panel.mouse_filter == Control.MOUSE_FILTER_STOP
		and hub.find_child("HubInformationScroll", true, false) is ScrollContainer,
		"base hub: narrative is not bounded or lets clicks open the town underneath", failures)
	(hub.find_child("HubInformationClose", true, false) as Button).pressed.emit()
	_expect(not hub._detail_panel.visible and hub._info_toggle.text == "近况", "base hub: narrative close did not restore town view", failures)
	for pair: Array in [["Proxy pod calibration pending", "Proxy pod calibration pending"], ["Tutorial complete", "游侠基础教程已完成"], ["Tutorial complete (generation 7 / slot A).", "游侠基础教程已完成 （存档代 7／槽位 A）"]]:
		hub.present(_pre_boss_profile(), {"outcome": "mysterious_fate"}, pair[0], {})
		_expect(hub._detail_status_label.text == pair[1], "base hub: optional status changed canonical/unknown copy", failures)
		_expect(hub._detail_result_label.text.contains("mysterious_fate"), "base hub: optional receipt renamed an unknown outcome", failures)
	for label: Label in [hub._objective_label, hub._detail_status_label, hub._detail_result_label, hub._nearby_label]:
		_expect(label.get_theme_font_size("font_size") >= 22, "base hub: compact UI shrank body copy", failures)
	for label: Label in [hub._profile_label, hub._progress_label, hub._detail_help_label]:
		_expect(label.get_theme_font_size("font_size") >= 18, "base hub: compact UI shrank annotation copy", failures)


func _test_landmarks_follow_world(hub, failures: Array[String]) -> void:
	_expect(hub.get_navigation_bar() == null
		and hub.find_child("TownToolbar", true, false) == null
		and hub.find_child("BaseNavigation", true, false) == null
		and hub.find_child("TownWayfinder", true, false) == null,
		"base hub: an old bottom bar or global wayfinder remained in the tree", failures)
	var visible_count := 0
	for feature_id: String in FEATURE_IDS:
		var landmark: Button = hub.get_landmark(feature_id)
		var expected: Rect2 = hub._landmark_design_rect(feature_id)
		_expect(landmark != null and not _view_of(hub).entry_for(feature_id).is_empty(),
			"base hub: world landmark and published facility disagree: " + feature_id, failures)
		if landmark == null: continue
		if landmark.visible:
			visible_count += 1
			_expect(not landmark.get_global_rect().intersects(hub._header.get_global_rect()), "base hub: landmark overlaps top information", failures)
		_expect(landmark.name == "TownLandmark_" + feature_id
			and landmark.mouse_filter == Control.MOUSE_FILTER_STOP,
			"base hub: %s landmark is not a clickable world label" % feature_id, failures)
		_expect(landmark.size == BaseHubScreenScript.LANDMARK_SIZE
			and landmark.position == expected.position.floor(),
			"base hub: %s landmark was clamped instead of following its building" % feature_id, failures)
		_expect(landmark.visible == BaseHubScreenScript.LANDMARK_SAFE_RECT.encloses(expected),
			"base hub: %s landmark visibility disagrees with the live lens" % feature_id, failures)
		var title := landmark.get_node("Copy/Title") as Label
		var status := landmark.get_node("Copy/Status") as Label
		var state: Dictionary = hub.get_navigation_state(feature_id)
		_expect(title.get_theme_font_size("font_size") == 22
			and status.get_theme_font_size("font_size") == 18,
			"base hub: %s landmark changed its reading sizes" % feature_id, failures)
		_expect(title.text == String(state.get("title", "")) and status.text == String(state.get("status", "")),
			"base hub: %s landmark identity/status disagrees with the snapshot" % feature_id, failures)
		_expect(not status.text.contains("\n") and status.text.length() <= 18,
			"base hub: %s landmark grew a long status block" % feature_id, failures)
	_expect(visible_count < FEATURE_IDS.size(), "base hub: all five landmarks leaked outside the live lens", failures)
	for feature_id: String in FEATURE_IDS:
		hub.set_hero_position(hub.get_world_feature_position(feature_id))
		var landmark: Button = hub.get_landmark(feature_id)
		_expect(landmark != null and landmark.visible
			and Rect2(Vector2.ZERO, BaseHubScreenScript.DESIGN_SIZE).encloses(Rect2(landmark.position, landmark.size)),
			"base hub: arriving did not reveal the %s landmark" % feature_id, failures)


func _test_compact_ui_sizes(failures: Array[String]) -> void:
	var scene_tree := Engine.get_main_loop() as SceneTree
	for dimensions: Vector2i in [Vector2i(1280, 720), Vector2i(1600, 900)]:
		var host := SubViewport.new()
		host.size = dimensions
		scene_tree.root.add_child(host)
		var hub = BaseHubScreenScript.new()
		host.add_child(hub)
		hub.present({"initial_class": "ranger", "progression": {}}, {}, "一次更新。".repeat(50),
			{"next_mainline_node_id": "mainline_02_priority_under_pressure"})
		hub.present_adventure({"level": 12, "points_available": 24}, {
			"current_objective": {"text": "与Leia交谈，确认寒原失联的旧路。"},
			"journal_entries": [{"is_read": false}, {"is_read": false}],
			"town_changes": [{"text": "炉边镇近况。".repeat(30)}],
		})
		_sort_hub_ui(hub)
		var bounds := Rect2(Vector2.ZERO, Vector2(dimensions))
		_expect(hub.size == Vector2(dimensions), "base hub: host did not adopt " + str(dimensions), failures)
		_expect(bounds.encloses(hub._header.get_global_rect()), "base hub: compact header is offscreen at " + str(dimensions), failures)
		_expect(hub._profile_label.text == "Lv.12 · 游侠" and hub._character_button.text == "成长 C · 24点"
			and hub._story_button.text == "见闻 J · 2", "base hub: live level/growth/unread state is wrong", failures)
		var previous: Rect2 = hub._objective_label.get_global_rect()
		for control: Control in [hub._objective_label, hub._character_button, hub._story_button, hub._info_toggle,
			hub.find_child("HubSettingsSpace", true, false)]:
			_expect(hub._header.get_global_rect().encloses(control.get_global_rect()),
				"base hub: top control is clipped at %s: %s" % [dimensions, control.name], failures)
			if control != hub._objective_label:
				_expect(control.get_global_rect().position.x >= previous.end.x,
					"base hub: top actions overlap at " + str(dimensions), failures)
			previous = control.get_global_rect()
		_expect(hub._objective_label.get_visible_line_count() == hub._objective_label.get_line_count()
			and hub._objective_label.get_theme_font("font").get_string_size(hub._objective_label.text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x <= hub._objective_label.size.x,
			"base hub: actual current objective is cropped at " + str(dimensions), failures)
		_test_nav_long_status_and_bounds(hub, failures)
		hub.present(hub._profile, {}, "一次更新。".repeat(50), hub._campaign_snapshot)
		hub.set_information_details_expanded(true)
		_sort_hub_ui(hub)
		var scroll := hub.find_child("HubInformationScroll", true, false) as ScrollContainer
		_expect(bounds.encloses(hub._detail_panel.get_global_rect()) and scroll.size.y > 0
			and scroll.get_v_scroll_bar().max_value > scroll.size.y,
			"base hub: long narrative is not bounded/reachable at " + str(dimensions), failures)
		for label: Label in [hub._detail_status_label, hub._detail_story_label]:
			_expect(label.get_visible_line_count() == label.get_line_count() and label.size.y >= label.get_minimum_size().y
				and label.size.x <= scroll.size.x and label.get_theme_font_size("font_size") == 22,
				"base hub: long narrative text is cropped at %s: %s" % [dimensions, label.name], failures)
		for id: String in FEATURE_IDS:
			var landmark: Button = hub.get_landmark(id)
			_expect(landmark != null and not landmark.is_visible_in_tree(),
				"base hub: narrative did not hide the %s landmark at %s" % [id, str(dimensions)], failures)
		host.free()


func _sort_hub_ui(hub) -> void:
	for _pass in 4:
		hub._reflow_information_content()
		var areas: Array[Control] = [hub._header, hub._detail_panel]
		areas.append_array(hub._landmarks.values())
		for area: Control in areas:
			_sort_containers(area)


func _sort_containers(node: Node) -> void:
	if node is Container: node.notification(Container.NOTIFICATION_SORT_CHILDREN)
	for child: Node in node.get_children(): _sort_containers(child)


func _test_growth_story_and_settings(hub, failures: Array[String]) -> void:
	var events: Array[String] = []
	hub.character_requested.connect(func(): events.append("growth"))
	hub.story_requested.connect(func(): events.append("story"))
	hub.title_requested.connect(func(): events.append("title"))
	for key: Key in [KEY_C, KEY_J]:
		var event := InputEventKey.new()
		event.physical_keycode = key
		event.pressed = true
		hub._unhandled_key_input(event)
	hub._character_button.pressed.emit()
	hub._story_button.pressed.emit()
	_expect(events == ["growth", "story", "growth", "story"], "base hub: growth/story key and mouse actions changed", failures)
	var parent: Node = hub.get_parent()
	var host := MenuHost.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(host)
	host.add_child(host.menu)
	hub.reparent(host)
	hub.set_information_details_expanded(true)
	(hub.find_child("HubSettings", true, false) as Button).pressed.emit()
	_expect(host.menu.opened == 1 and not hub.information_details_expanded(),
		"base hub: settings did not open the existing public session menu API", failures)
	hub.set_information_details_expanded(true)
	(hub.find_child("ReturnToTitle", true, false) as Button).pressed.emit()
	_expect(events.back() == "title" and events.size() == 5, "base hub: optional title action did not route once", failures)
	var escape := InputEventKey.new()
	escape.physical_keycode = KEY_ESCAPE
	escape.pressed = true
	hub._unhandled_key_input(escape)
	_expect(not hub.information_details_expanded(), "base hub: Escape did not close optional narrative", failures)
	hub.reparent(parent)
	host.free()


func _test_resident_prompt(hub, failures: Array[String]) -> void:
	var residents: Array = hub.get_hub_view().life_report().get("residents", [])
	_expect(not residents.is_empty(), "base hub: public town life API has no resident for proximity validation", failures)
	if residents.is_empty(): return
	var resident: Dictionary = residents[0]
	var before_story: Dictionary = hub._story_snapshot.duplicate(true)
	hub.present_adventure({}, {"available_conversations": [{"npc": resident.id, "npc_name": "镇民", "stage": 1,
		"title": "寒原失联的旧路", "pages": ["炉边镇还在等消息。"], "id": "hub_prompt_test"}]})
	hub.set_hero_position(Vector2(20, 20))
	_expect(not hub._nearby_panel.visible and hub.find_child("TownStoryCue", true, false) == null,
		"base hub: remote conversation selected an always-visible E/title prompt", failures)
	hub.set_hero_position((resident.feet + Vector2(0, 10)) * 2.0)
	_expect(hub.nearby_resident_id() == resident.id and hub._nearby_panel.visible
		and hub._nearby_label.text == "[E] 与镇民交谈", "base hub: nearby resident has no explicit E prompt", failures)
	var stand: Dictionary = {}
	var stand_gap := INF
	for entry: Dictionary in hub.get_hub_view().feature_entries():
		var gap: float = Vector2(entry.feet).distance_to(Vector2(resident.feet))
		if gap < stand_gap:
			stand_gap = gap
			stand = entry
	if not stand.is_empty() and stand_gap <= hub.TALK_RADIUS:
		## Dialogue beats the facility badge only while the resident is no
		## farther than RESIDENT_PRIORITY_SLACK behind the facility feet, so the
		## shared-stand probe is the midpoint: both gaps are equal and the
		## resident legally keeps E without widening the runtime rule to the
		## whole TALK_RADIUS.
		var midpoint := (Vector2(resident.feet) + Vector2(stand.feet)) * 0.5
		hub.set_hero_position(midpoint * 2.0)
		_expect(hub.nearby_resident_id() == resident.id and String(hub._nearby_label.text).begins_with("[E] 与"),
			"base hub: resident lost the E prompt to the co-located facility", failures)
		_expect(hub.activate_nearby_interaction() and hub.is_dialogue_open(),
			"base hub: E at a shared stand opened the facility instead of the resident", failures)
		hub._dialogue.close_dialogue()
		var facility_nearby: bool = not hub.get_hub_view().entry_for(hub.get_hub_view().nearby_feature_id()).is_empty()
		if stand_gap > hub.RESIDENT_PRIORITY_SLACK and facility_nearby:
			## The facility feet stay the facility's when the resident is beyond
			## the slack; routing is decided by the empty resident id because
			## activating the facility here would navigate away from the hub.
			hub.set_hero_position(Vector2(stand.feet) * 2.0)
			_expect(hub.nearby_resident_id().is_empty(),
				"base hub: a beyond-slack resident stole the facility feet interaction", failures)
		hub.set_hero_position((resident.feet + Vector2(0, 10)) * 2.0)
	var event := InputEventKey.new()
	event.physical_keycode = KEY_E
	event.pressed = true
	hub._unhandled_key_input(event)
	_expect(hub.is_dialogue_open() and not hub._nearby_panel.visible, "base hub: E lost the real conversation entry", failures)
	hub._dialogue.close_dialogue()
	hub.get_hub_view().configure_life_for_test({}, {}, {})
	hub.present_adventure({}, {"available_conversations": [{"npc": resident.id, "npc_name": "镇民", "stage": 1,
		"title": "寒原失联的旧路", "pages": ["炉边镇还在等消息。"], "id": "hub_prompt_test"}]})
	_expect(hub._resident_positions.has(resident.id) and hub.nearby_resident_id() == resident.id,
		"base hub: static layout residents lost their talk position without life art", failures)
	var far_id := ""
	for id: String in hub._resident_positions:
		if id != resident.id:
			far_id = id
			break
	if not stand.is_empty() and not far_id.is_empty():
		## Iteration-order regression: with two residents inside the facility
		## slack window, the farther one iterated later must not overwrite the
		## nearer one (the old OR-branch let it win whenever a facility was in
		## range).
		hub.present_adventure({}, {"available_conversations": [
			{"npc": far_id, "npc_name": "远处居民", "stage": 1, "title": "远", "pages": ["远"], "id": "hub_prompt_far"},
			{"npc": resident.id, "npc_name": "镇民", "stage": 1,
				"title": "寒原失联的旧路", "pages": ["炉边镇还在等消息。"], "id": "hub_prompt_test"}]})
		hub.set_hero_position(Vector2(stand.feet) * 2.0)
		hub._resident_positions[far_id] = Vector2(stand.feet) + Vector2(7.0, 0.0)
		hub._resident_positions[resident.id] = Vector2(stand.feet) + Vector2(5.0, 0.0)
		_expect(hub.nearby_resident_id() == resident.id,
			"base hub: farther resident iterated later overwrote the nearer one", failures)
	hub.get_hub_view().life_animation.load_default_assets()
	hub.present_adventure({}, before_story)


## Every landmark draws the state the hub derived from the save, and the world marker
## of the same stand keeps the matching note. Neither one is allowed to invent a
## status the other does not have.
func _test_nav_state_matches_cards(hub, failures: Array[String]) -> void:
	var states: Array = hub.navigation_state()
	_expect(states.size() == FEATURE_IDS.size(), "base hub: navigation_state published %d entries" % states.size(), failures)
	var seen: Array[String] = []
	for state: Dictionary in states:
		var feature_id := String(state.get("id", ""))
		seen.append(feature_id)
		_expect(feature_id in FEATURE_IDS, "base hub: navigation_state published an unknown facility %s" % feature_id, failures)
		hub.set_hero_position(hub.get_world_feature_position(feature_id))
		var landmark: Button = hub.get_landmark(feature_id)
		if landmark == null:
			continue
		_expect(String(state.get("title", "")) == landmark.get_node("Copy/Title").text, "base hub: TownLandmark_%s title is not the state title" % feature_id, failures)
		_expect(String(state.get("status", "")) == landmark.get_node("Copy/Status").text, "base hub: TownLandmark_%s status is not the state status" % feature_id, failures)
		var lookup: Dictionary = hub.get_navigation_state(feature_id)
		_expect(lookup.get("id", "") == state.get("id", "") and lookup.get("title", "") == state.get("title", "")
			and lookup.get("status", "") == state.get("status", "") and lookup.get("detail", "") == state.get("detail", ""),
			"base hub: single-landmark lookup disagrees with the published list for %s" % feature_id, failures)
		_expect(hub.get_feature_marker_text(feature_id).contains(String(state.get("detail", ""))), "base hub: %s marker dropped the navigation note" % feature_id, failures)
	_expect(seen == FEATURE_IDS, "base hub: navigation_state order drifted from the published order", failures)
	## availability and the reason always agree: a locked card explains itself, an
	## open card never claims a lock.
	for state: Dictionary in states:
		var detail := String(state.get("detail", ""))
		if bool(state.get("locked", false)):
			_expect(not String(state.get("reason", "")).is_empty(), "base hub: %s is locked without a reason" % String(state.get("id", "")), failures)
			_expect(detail.contains("封印中") or detail.contains("固定起步装"), "base hub: locked %s does not explain its lock in the world note" % String(state.get("id", "")), failures)
		else:
			_expect(not detail.contains("封印中") and not detail.contains("固定起步装"), "base hub: open %s still reads as locked" % String(state.get("id", "")), failures)


## A click on a landmark must leave through exactly the same signal as walking up
## to the stand and pressing E, carrying its feature id and one signal
## per action: no extra state write is allowed to reach the game root.
func _test_nav_activation_routing(hub, failures: Array[String]) -> void:
	var events: Array[String] = []
	hub.contract_requested.connect(func() -> void: events.append("contract"))
	hub.feature_requested.connect(func(feature_id: String) -> void: events.append(feature_id))
	for feature_id: String in FEATURE_IDS:
		var before: int = events.size()
		hub.set_hero_position(hub.get_world_feature_position(feature_id))
		var landmark: Button = hub.get_landmark(feature_id)
		if landmark == null:
			continue
		landmark.emit_signal("pressed")
		_expect(events.size() == before + 1, "base hub: TownLandmark_%s emitted %d signals" % [feature_id, events.size() - before], failures)
		_expect(events.back() == feature_id, "base hub: TownLandmark_%s emitted %s" % [feature_id, events.back()], failures)
	_expect(events == ["contract", "loadout", "forge", "training", "proxy"], "base hub: landmark order no longer matches the signal order: %s" % str(events), failures)
	## The hub routes every landmark through the one existing entry point, so a sign
	## and its world stand can never disagree about which page opens.
	for feature_id: String in FEATURE_IDS:
		hub.set_hero_position(hub.get_world_feature_position(feature_id))
		var before: int = events.size()
		var activated: bool = hub.navigation_card_activated(feature_id)
		_expect(activated and events.size() == before + 1 and events.back() == feature_id, "base hub: the shared entry point did not route %s" % feature_id, failures)


## The first-hunt goal names the stand and the contract, and the local road guide
## follows only explicit direction requests or the recommended departure.
func _test_goal_and_road_guide(hub, failures: Array[String]) -> void:
	var state = ApplicationStateScript.new()
	state.start_new_profile("ranger")
	state.complete_tutorial()
	hub.present(state.profile, {}, "", state.campaign_progress_snapshot())
	hub.present_adventure({}, {"current_objective": {"text": "沿寒原旧路清通外段，带回能用的材料与装备"}})
	## The hub instance carries selections from earlier suites: start from the
	## recommended departure, exactly like a fresh town arrival.
	hub.restore_travel({"destination": "contract"})
	_expect(hub._objective_label.text.contains("行路契台") and hub._objective_label.text.contains("初次狩猎"),
		"base hub: the first-hunt goal does not name the contract stand and the first hunt", failures)
	_expect(hub._objective_label.tooltip_text.contains("沿寒原旧路"),
		"base hub: the story objective lost its tooltip context", failures)
	_expect(hub.wayfinding_report().get("id", "") == "contract", "base hub: the recommended departure is not the contract desk", failures)
	## Entering a stand within reach opens it and is not a destination choice.
	var feature_events: Array[String] = []
	hub.feature_requested.connect(func(feature_id: String) -> void: feature_events.append(feature_id))
	hub.set_hero_position(hub.get_world_feature_position("loadout"))
	_expect(hub.navigation_card_activated("loadout") and feature_events == ["loadout"],
		"base hub: the nearby entry did not open the stand", failures)
	_expect(hub.wayfinding_report().get("id", "") == "contract",
		"base hub: a nearby entry silently retargeted the road guide", failures)
	## A far landmark request is the explicit directions action.
	hub.set_hero_position(hub.get_world_feature_position("contract"))
	_expect(hub.navigation_card_activated("loadout") and hub.wayfinding_report().get("id", "") == "loadout",
		"base hub: an explicit far request did not move the road guide", failures)
	## Reaching an explicitly selected stand keeps it; the interaction prompt and
	## the hidden guide take over at the interaction radius.
	hub.set_hero_position(hub.get_world_feature_position("loadout"))
	var arrived_report: Dictionary = hub.wayfinding_report()
	_expect(String(arrived_report.get("id", "")) == "loadout" and bool(arrived_report.get("arrived", false)),
		"base hub: an explicit selection lost its arrived state at the stand", failures)


## Locked copy is a projection of the save, not of the current picture: the same
## snapshot that shows the lock must name the authored reward that opens it.
func _test_nav_locked_copy(hub, failures: Array[String]) -> void:
	hub.present(_pre_boss_profile(), {}, "", {})
	var proxy_state: Dictionary = hub.get_navigation_state("proxy")
	_expect(bool(proxy_state.get("locked", false)), "base hub: proxy reads as open before its unlock", failures)
	_expect(String(proxy_state.get("status", "")).contains(String(proxy_state.get("reason", ""))), "base hub: the locked proxy card does not show its lock reason", failures)
	## The proxy gate is the colossus first kill that grants the four white cores
	## (application_state._record_contract_result), never the later AUTO run.
	var proxy_reason := String(proxy_state.get("reason", ""))
	_expect(proxy_reason == String(BaseHubScreenScript._UNLOCK_REASONS["proxy"]) and proxy_reason.contains("首杀") and proxy_reason.contains("巨像"), "base hub: the proxy lock reason stopped naming the colossus first kill", failures)
	_expect(not proxy_reason.contains("AUTO") and not proxy_reason.contains("考核"), "base hub: the proxy lock reason drifted onto the later AUTO certification", failures)
	var forged: Dictionary = hub.get_navigation_state("forge")
	_expect(bool(forged.get("locked", false)) and String(forged.get("reason", "")) == String(BaseHubScreenScript._UNLOCK_REASONS["forge"]) and String(forged.get("reason", "")).contains("锻造"), "base hub: the forge lock reason stopped naming its authored reward", failures)
	var rack: Dictionary = hub.get_navigation_state("loadout")
	_expect(not bool(rack.get("locked", false)) and String(rack.get("reason", "")).is_empty()
		and String(rack.get("status", "")) == "起步装备可查看",
		"base hub: accessible starter rack did not show the first-victory comparison gate", failures)
	_expect(not bool(hub.get_navigation_state("contract").get("locked", false)) and not bool(hub.get_navigation_state("training").get("locked", false)), "base hub: an always-open page was reported as locked", failures)
	## A locked card carries the published non-colour mark and the real gate, never
	## a bare state word and never the wording of an open page.
	for locked_id: String in ["forge", "proxy"]:
		var locked_state: Dictionary = hub.get_navigation_state(locked_id)
		var locked_status := String(locked_state.get("status", ""))
		_expect(locked_status.begins_with(BaseHubScreenScript.LOCK_MARK), "base hub: the locked %s card lost its non-colour lock mark" % locked_id, failures)
		_expect(locked_status.contains(String(locked_state.get("reason", ""))), "base hub: the locked %s card does not show why it is locked" % locked_id, failures)
		_expect(String(locked_state.get("detail", "")).contains("封印中") or locked_id == "loadout", "base hub: the locked %s world note stopped saying it is sealed" % locked_id, failures)
	var contract_state: Dictionary = hub.get_navigation_state("contract")
	_expect(not String(contract_state.get("status", "")).is_empty() and String(contract_state.get("status", "")) == String(contract_state.get("detail", "")), "base hub: the open contract card lost its approach wording", failures)


## Pre-boss and post-boss are two different, save-derived readings of the same
## five cards; the boss defeat that opens the proxy must flip exactly that card.
func _test_first_hunt_rack_availability(hub, failures: Array[String]) -> void:
	var state = ApplicationStateScript.new()
	state.start_new_profile("ranger")
	for tutorial_done in [false, true]:
		if tutorial_done:
			state.complete_tutorial()
		hub.present(state.profile, {}, "", state.campaign_progress_snapshot())
		var rack: Dictionary = hub.get_navigation_state("loadout")
		_expect(not bool(rack.locked) and rack.reason == "" and rack.status == "起步装备可查看",
			"base hub: real starter profile's accessible rack was shown as sealed", failures)
	state.prepare_contract({"contract_id": "mainline_01_first_hunt", "mode": "Manual", "seed": 301, "room_count": 2})
	state.begin_session()
	state.complete_session({"outcome": "victory", "rooms_completed": 2})
	hub.present(state.profile, state.last_result, "", state.campaign_progress_snapshot())
	var rack: Dictionary = hub.get_navigation_state("loadout")
	_expect(not bool(rack.locked) and rack.reason == "" and rack.status == "比较已开放"
		and hub.get_feature_marker_text("loadout").contains("比较已开放")
		and hub.get_landmark("loadout").get_node("Copy/Status").text == rack.status,
		"base hub: real first-victory rack landmark and marker disagree with comparison availability", failures)


func _test_nav_boss_crossing(hub, failures: Array[String]) -> void:
	hub.present(_pre_boss_profile(), {}, "", {})
	var before: Dictionary = hub.get_navigation_state("proxy")
	_expect(bool(before.get("locked", false)), "base hub: proxy card was open before the boss", failures)
	var before_icon_state: Dictionary = {"locked": bool(before.get("locked", false)), "status": String(before.get("status", ""))}
	hub.present(_post_boss_profile(), {}, "", {
		"ok": true,
		"next_mainline_node_id": "",
		"earned_reward_tags": ["equipment_compare_unlock", "law_forge_unlock", "early_campaign_complete"],
		"early_game_complete": true,
	})
	var after: Dictionary = hub.get_navigation_state("proxy")
	_expect(not bool(after.get("locked", false)), "base hub: the boss defeat did not open the proxy card", failures)
	_expect(String(after.get("status", "")) != String(before_icon_state.get("status", "")), "base hub: the proxy card kept its pre-boss copy after the boss", failures)
	_expect(not String(after.get("status", "")).contains("封印中"), "base hub: the opened proxy card still reads as locked", failures)
	_expect(String(after.get("status", "")).contains("已解锁"), "base hub: the opened proxy card does not read as unlocked", failures)
	_expect(not bool(hub.get_navigation_state("forge").get("locked", false)) and not bool(hub.get_navigation_state("loadout").get("locked", false)), "base hub: the authored facility rewards did not open their cards", failures)
	_expect(String(hub.get_navigation_state("contract").get("status", "")).is_empty() == false, "base hub: the contract card lost its copy after graduation", failures)
	for feature_id: String in FEATURE_IDS:
		hub.set_hero_position(hub.get_world_feature_position(feature_id))
		var landmark: Button = hub.get_landmark(feature_id)
		_expect(landmark != null and landmark.get_node("Copy/Status").text == String(hub.get_navigation_state(feature_id).get("status", "")), "base hub: TownLandmark_%s did not repaint after the boss crossing" % feature_id, failures)


## The two landmark rows stay compact on the 1280 canvas. A long state clips to
## one readable line while its full derivation remains in the tooltip.
func _test_nav_long_status_and_bounds(hub, failures: Array[String]) -> void:
	hub.present(_pre_boss_profile(), {}, "", {
		"ok": true, "next_mainline_node_id": "mainline_02_priority_under_pressure",
		"earned_reward_tags": ["starter_loadout"], "early_game_complete": false,
	})
	for state: Dictionary in hub.navigation_state():
		var feature_id := String(state.id)
		hub.set_hero_position(hub.get_world_feature_position(feature_id))
		var landmark: Button = hub.get_landmark(feature_id)
		if landmark == null:
			continue
		var title := landmark.get_node("Copy/Title") as Label
		var status := landmark.get_node("Copy/Status") as Label
		_sort_containers(landmark)
		_expect(title.get_theme_font_size("font_size") == 22 and status.get_theme_font_size("font_size") == 18,
			"base hub: landmark changed its body/annotation reading sizes", failures)
		_expect(title.text == state.title and status.text == state.status and landmark.tooltip_text.contains(state.status),
			"base hub: landmark shortened/guessed a real facility state", failures)
		for label: Label in [title, status]:
			var measured := label.get_theme_font("font").get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size"))
			_expect(measured.x <= label.size.x + 0.5 and landmark.get_global_rect().encloses(label.get_global_rect()),
				"base hub: one-line landmark text spills: %s / %s" % [feature_id, label.text], failures)
		_expect(title.get_global_rect().end.y <= status.get_global_rect().position.y,
			"base hub: landmark title and state overlap", failures)


func _test_nav_keyboard_access(hub, failures: Array[String]) -> void:
	var events: Array[String] = []
	hub.contract_requested.connect(func() -> void: events.append("contract"))
	hub.feature_requested.connect(func(feature_id: String) -> void: events.append(feature_id))
	hub.set_hero_position(hub.get_world_feature_position("forge"))
	var focus_card: Button = hub.get_landmark("forge")
	hub.set_hero_position(hub.get_world_feature_position("forge"))
	if focus_card != null:
		## Focus can only be taken while the screen owns a live window; the headless
		## harness asserts the tab order and the key behaviour around it instead.
		if focus_card.is_inside_tree():
			focus_card.grab_focus()
		## The movement keys must not turn into a second world interaction while the
		## bar holds focus: the hero keeps its gate and only an explicit activation
		## opens the page.
		var before: int = events.size()
		for keycode: Key in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]:
			var move_event := InputEventKey.new()
			move_event.physical_keycode = keycode
			move_event.pressed = true
			hub._unhandled_key_input(move_event)
		_expect(events.size() == before, "base hub: a focused landmark turned a movement key into an entry", failures)
		_expect(hub.get_nearby_feature_id() == "forge", "base hub: keyboard focus changed the nearby stand", failures)
		## Enter and Space reach the card through the stock Button activation, which
		## needs a live viewport; the headless harness asserts the two gaps it could
		## otherwise hide: the card is the focus owner after grab_focus, and a
		## focused card never turns a movement key into a second world entry.
		var viewport_focus: Control = focus_card.get_viewport().gui_get_focus_owner() if focus_card.is_inside_tree() else null
		_expect(viewport_focus == null or viewport_focus == focus_card, "base hub: a landmark could not take focus", failures)
		_expect(viewport_focus == null or hub._navigation_has_focus(), "base hub: focused landmark did not suspend world movement", failures)
		_expect(not focus_card.focus_mode == Control.FOCUS_NONE, "base hub: a landmark turned focus off", failures)
		_expect(focus_card.focus_neighbor_right.is_empty() == false, "base hub: a visible landmark has no Tab neighbour", failures)
		var key_event := InputEventKey.new()
		key_event.physical_keycode = KEY_E
		key_event.pressed = true
		hub._on_landmark_gui_input(key_event, "forge")
		_expect(events.size() == before + 1 and events.back() == "forge", "base hub: focused E did not open exactly one facility", failures)
		if focus_card.is_inside_tree():
			focus_card.release_focus()
	## Every other landmark also needs an explicit activation to pass the shared gate.
	for feature_id: String in FEATURE_IDS:
		var landmark: Button = hub.get_landmark(feature_id)
		if landmark == null:
			continue
		var before: int = events.size()
		hub.set_hero_position(hub.get_world_feature_position(feature_id))
		landmark.emit_signal("pressed")
		_expect(events.size() == before + 1 and events.back() == feature_id, "base hub: explicit activation of TownLandmark_%s did not route once" % feature_id, failures)
	## The shared gate rejects anything the prototype does not have, so a stray id
	## can never open a sixth system.
	for rejected: String in ["immortality", "everlife", "", "contract "]:
		var before_rejected: int = events.size()
		_expect(not hub.navigation_card_activated(rejected), "base hub: the navigation gate accepted %s" % rejected, failures)
		_expect(events.size() == before_rejected, "base hub: the navigation gate opened %s" % rejected, failures)


func _pre_boss_profile() -> Dictionary:
	return {"progression": {
		"threshold_colossus_defeated": false,
		"proxy_unlocked": false,
		"auto_contract_wins": 0,
		"early_game_complete": false,
	}}


func _post_boss_profile() -> Dictionary:
	return {"progression": {
		"build_training_complete": true,
		"threshold_colossus_defeated": true,
		"proxy_unlocked": true,
		"auto_contract_wins": 1,
		"early_game_complete": true,
	}}


func _install_fixture(view) -> void:
	view.configure(_fixture_atlas(), _fixture_layout())
	view.replace_textures_for_test({"hamlet:fixture": ImageTexture.create_from_image(_fixture_image())})


func _fixture_atlas() -> Dictionary:
	return {
		"schema_version": 1,
		"native_view": [640, 360],
		"animations": {},
		"sprites": {
			"station.contract": {"rect": [0, 0, 48, 64], "anchor": [24, 58], "texture": "fixture"},
			"station.forge": {"rect": [48, 0, 48, 64], "anchor": [24, 58], "texture": "fixture"},
			"station.smithy": {"rect": [96, 0, 64, 96], "anchor": [32, 90], "texture": "fixture"},
			"decoration.pebble": {"rect": [64, 0, 32, 24], "anchor": [16, 20], "texture": "fixture"},
			"ranger.south.idle": {"rect": [160, 0, 32, 48], "anchor": [16, 44], "texture": "fixture"},
		},
		"textures": {"fixture": {"path": "res://fixture/magenta.png", "width": 192, "height": 96}},
	}


func _fixture_layout() -> Dictionary:
	return {
		"schema_version": 1,
		"world": [1024, 640],
		"hero_start": [200, 200],
		"placements": [
			{"id": "contract", "sprite": "station.contract", "feet": [200, 300], "layer": "object", "interaction": "contract"},
			{"id": "forge", "sprite": "station.forge", "feet": [428, 500], "layer": "object", "interaction": "forge"},
			{"id": "smithy", "sprite": "station.smithy", "feet": [420, 240], "layer": "object", "split_row": 40},
			{"id": "well", "sprite": "station.contract", "feet": [600, 320], "layer": "object"},
			{"id": "pebble", "sprite": "decoration.pebble", "feet": [120, 440], "layer": "ground"},
		],
	}


func _fixture_image() -> Image:
	var image := Image.create(192, 96, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.85, 0.2, 0.75, 1.0))
	return image


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)


func _town_layout() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://art/production/p1/hamlet_town/layout.json"))


func _uv_world(uv: Array, world: Vector2) -> Vector2:
	return Vector2(float(uv[0]), float(uv[1])) * world
