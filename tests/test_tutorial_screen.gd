extends SceneTree
## Regression for the tutorial's production-art landing: the arena reads its hero,
## its single melee target and its floor from the published JSON atlases, places
## the cells by their published anchors at integer 2x, and reports ASSETS PENDING
## instead of faking a character whenever a source is missing. Every gameplay
## rule of the drill uses the same fixed-tick arrow timing as combat while its
## geometry, one target and completion contract remain isolated from persistence.

const TutorialScreenScript = preload("res://src/presentation/tutorial_screen.gd")
const TutorialArtScript = preload("res://src/presentation/tutorial_art.gd")
const RangerAnimationScript = preload("res://src/presentation/ranger_animation.gd")
const PlayerActionTimelineScript = preload("res://src/systems/player_action_timeline.gd")
const Assert := preload("res://tests/helpers/assert.gd")

const SCREEN_SOURCE_PATH := "res://src/presentation/tutorial_screen.gd"
const ART_SOURCE_PATH := "res://src/presentation/tutorial_art.gd"
## The early placeholder sheet and the pattern the tutorial used to crop from it.
const EARLY_PLACEHOLDER_MARKER := "art/early/"
const EARLY_ATLAS_MARKER := "actors_atlas"
const EXPECTED_ARENA_CROP := Rect2i(298, 200, 428, 240)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	var screen = TutorialScreenScript.new()
	root.add_child(screen)
	screen.present("ranger")

	_test_initial_lock(screen, failures)
	_test_action_copy(screen, failures)
	_test_layout_and_ranger_copy(screen, failures)
	_test_cast_range(screen, failures)
	_test_dodge(screen, failures)
	_expect(not screen.is_enter_enabled(), "tutorial: two completed actions unlocked enter before movement", failures)
	_test_delta_and_bounds(screen, failures)
	_test_completion_gate(screen, failures)
	_test_action_copy(screen, failures)
	await _test_required_sizes(screen, failures)
	_test_geometry_unchanged(failures)
	_test_training_art(screen, failures)
	_test_ranger_action_wiring(screen, failures)
	_test_actor_bounds_headroom(screen, failures)
	_test_sprite_placement_math(screen, failures)
	_test_pending_assets(screen, failures)
	_test_no_early_placeholder_art(failures)

	root.remove_child(screen)
	screen.free()
	if failures.is_empty():
		print("PASS  test_tutorial_screen.gd")
		quit(0)
		return
	for failure in failures:
		printerr("- %s" % failure)
	quit(1)


func _test_initial_lock(screen, failures: Array[String]) -> void:
	var snapshot: Dictionary = screen.get_checklist_snapshot()
	_expect(not snapshot.move and not snapshot.dodge and not snapshot.cast_hit, "tutorial: checklist did not start empty", failures)
	_expect(not screen.is_enter_enabled(), "tutorial: enter button was not initially locked", failures)
	var button := screen.find_child("EnterBaseButton", true, false) as Button
	_expect(button != null and button.disabled, "tutorial: locked enter button has no stable disabled control", failures)


func _test_layout_and_ranger_copy(screen, failures: Array[String]) -> void:
	var canvas := screen.find_child("TutorialDesignCanvas", true, false) as Control
	_expect(canvas != null and canvas.size.is_equal_approx(Vector2(1280.0, 720.0)), "tutorial: design canvas is not 1280x720", failures)
	if canvas != null:
		for child in canvas.get_children():
			if child is Control:
				var control := child as Control
				_expect(control.position.x >= 0.0 and control.position.y >= 0.0 and control.position.x + control.size.x <= 1280.0 and control.position.y + control.size.y <= 720.0, "tutorial: a top-level control overflows 1280x720", failures)
	screen.present("mage")
	var class_label := screen.find_child("ClassLabel", true, false) as Label
	_expect(class_label != null and class_label.text.contains("Ranger") and not class_label.text.to_lower().contains("mage"), "tutorial: non-Ranger class copy was exposed", failures)


func _test_action_copy(screen, failures: Array[String]) -> void:
	var copy := _visible_copy(screen)
	_expect("tick" not in copy and "Buffered" not in copy and "Training Dummy" not in copy, "tutorial: technical timing or contradictory target copy exposed", failures)
	_expect("training target" in copy and "old road" in copy and "Hearthside" in copy, "tutorial: target identity or opening context missing", failures)
	if screen.is_enter_enabled():
		_expect("Practice complete" in copy and "Arrow hit" in copy and "Enter Hearthside" in copy, "tutorial: completed actions have no feedback or next step", failures)
	else:
		_expect(copy.count("WASD") == 1 and copy.count("Space") == 1 and copy.count("Shift") == 1, "tutorial: key instructions repeated", failures)


func _visible_copy(node: Node) -> String:
	var copy := ""
	if node is Label and node.visible:
		copy += node.text + "\n"
	if node is Button and node.visible:
		copy += node.text + "\n"
	for child in node.get_children():
		copy += _visible_copy(child)
	return copy


func _test_required_sizes(screen, failures: Array[String]) -> void:
	for viewport_size in [Vector2i(1280, 720), Vector2i(1600, 900)]:
		root.size = viewport_size
		await process_frame
		await process_frame
		var area := Rect2(Vector2.ZERO, Vector2(viewport_size))
		for node_name in ["TrainingArena", "TutorialIntro", "ActionGuide", "EnterBaseButton"]:
			var control := screen.find_child(node_name, true, false) as Control
			var rect := control.get_global_transform() * Rect2(Vector2.ZERO, control.size)
			_expect(area.encloses(rect), "tutorial: guide/action escaped " + str(viewport_size) + ": " + node_name, failures)
	root.size = Vector2i(1280, 720)
	await process_frame


func _test_delta_and_bounds(screen, failures: Array[String]) -> void:
	var origin := Vector2(400.0, 300.0)
	screen.set_player_position(origin)
	screen.simulate_move(Vector2.RIGHT, 0.1)
	var short_distance: float = screen.get_player_position().distance_to(origin)
	screen.set_player_position(origin)
	screen.simulate_move(Vector2.RIGHT, 0.2)
	var long_distance: float = screen.get_player_position().distance_to(origin)
	_expect(short_distance > 0.0 and is_equal_approx(long_distance, short_distance * 2.0), "tutorial: movement is not proportional to delta", failures)
	screen.set_player_position(TutorialScreenScript.PLAYABLE_BOUNDS.get_center())
	screen.simulate_move(Vector2(-1.0, -1.0), 100.0)
	_expect(screen.get_player_position().is_equal_approx(TutorialScreenScript.PLAYABLE_BOUNDS.position), "tutorial: movement did not clamp to arena bounds", failures)


func _test_cast_range(screen, failures: Array[String]) -> void:
	screen.set_player_position(TutorialScreenScript.PLAYABLE_BOUNDS.position)
	_expect(not screen.request_cast(), "tutorial: out-of-range cast unexpectedly hit the target", failures)
	_expect(not bool(screen.get_checklist_snapshot().cast_hit), "tutorial: out-of-range cast completed the checklist", failures)
	var target: Vector2 = screen.get_target_position()
	screen.set_player_position(target - Vector2(TutorialScreenScript.CAST_RANGE - 20.0, 0.0))
	var release_feet: Vector2 = screen.get_player_position()
	_expect(screen.request_cast(), "tutorial: in-range piercing arrow request was rejected", failures)
	_expect(not bool(screen.get_checklist_snapshot().cast_hit), "tutorial: cast completed before its windup impact", failures)
	_advance_action_ticks(screen, PlayerActionTimelineScript.WINDUP_TICKS)
	var released: Dictionary = screen.get_projectile_snapshot()
	var release_frame := RangerAnimationScript.shoot_frame_at_tick(PlayerActionTimelineScript.WINDUP_TICKS)
	var expected_origin := release_feet + RangerAnimationScript.arrow_attachment_offset(
		"east",
		release_frame,
		1.0 / float(TutorialArtScript.SCALE)
	)
	_expect(bool(released.get("active", false)), "tutorial: the fifth tick did not release a projectile", failures)
	_expect(not bool(screen.get_checklist_snapshot().cast_hit), "tutorial: release completed the checklist before contact", failures)
	_expect((released.get("origin", Vector2.ZERO) as Vector2).is_equal_approx(expected_origin), "tutorial: release origin left the authored east bow-hand socket: %s != %s" % [str(released.get("origin")), str(expected_origin)], failures)
	_expect((released.get("position", Vector2.ZERO) as Vector2).is_equal_approx(expected_origin), "tutorial: projectile moved during its release tick", failures)
	_expect((released.get("previous_position", Vector2.ZERO) as Vector2).is_equal_approx(expected_origin), "tutorial: release wake did not stay frozen at the socket", failures)
	_expect(is_zero_approx(float(released.get("distance_travelled", -1.0))), "tutorial: release tick already accumulated travel", failures)
	var caller_copy: Dictionary = screen.get_projectile_snapshot()
	caller_copy["position"] = Vector2.ZERO
	_expect((screen.get_projectile_snapshot().get("position", Vector2.ZERO) as Vector2).is_equal_approx(expected_origin), "tutorial: caller mutated the live projectile through its snapshot", failures)

	_advance_action_ticks(screen, 1)
	var travelling: Dictionary = screen.get_projectile_snapshot()
	_expect(bool(travelling.get("active", false)), "tutorial: projectile contacted too early to expose travel", failures)
	_expect((travelling.get("position", Vector2.ZERO) as Vector2).distance_to(expected_origin) > 0.0, "tutorial: projectile did not advance on the tick after release", failures)
	_expect(not bool(screen.get_checklist_snapshot().cast_hit), "tutorial: travelling projectile completed the checklist before contact", failures)

	var guard := 32
	while bool(screen.get_projectile_snapshot().get("active", false)) and guard > 0:
		_expect(not bool(screen.get_checklist_snapshot().cast_hit), "tutorial: active projectile marked the cast complete", failures)
		_advance_action_ticks(screen, 1)
		guard -= 1
	var contacted: Dictionary = screen.get_projectile_snapshot()
	_expect(guard > 0, "tutorial: projectile never contacted the stationary target", failures)
	_expect(contacted.has("contact_tick") and not contacted.has("miss_tick"), "tutorial: projectile ended without swept-circle contact: %s" % str(contacted), failures)
	_expect(bool(screen.get_checklist_snapshot().cast_hit), "tutorial: target contact did not complete cast checklist item", failures)


func _test_dodge(screen, failures: Array[String]) -> void:
	screen.set_player_position(Vector2(400.0, 300.0))
	var before: Vector2 = screen.get_player_position()
	_expect(screen.request_dodge(Vector2.DOWN), "tutorial: dodge request was rejected", failures)
	_expect(screen.get_player_position().distance_to(before) >= TutorialScreenScript.DODGE_DISTANCE - 0.01, "tutorial: dodge had no clear displacement", failures)
	_expect(bool(screen.get_checklist_snapshot().dodge), "tutorial: dodge did not complete checklist item", failures)


func _test_completion_gate(screen, failures: Array[String]) -> void:
	var snapshot: Dictionary = screen.get_checklist_snapshot()
	_expect(snapshot.move and snapshot.dodge and snapshot.cast_hit and snapshot.all_complete, "tutorial: three real actions did not complete checklist", failures)
	_expect(screen.is_enter_enabled(), "tutorial: completed checklist did not enable enter", failures)

	var events := {"completed_count": 0}
	screen.completed.connect(func() -> void: events.completed_count += 1)
	var button := screen.find_child("EnterBaseButton", true, false) as Button
	button.pressed.emit()
	button.pressed.emit()
	_expect(events.completed_count == 1, "tutorial: completed signal was not emitted exactly once", failures)


func _test_geometry_unchanged(failures: Array[String]) -> void:
	## The drill's tuning is frozen: the art landing must not have moved the arena,
	## the playable bounds, the hero start, the single target or any timing.
	_expect(TutorialScreenScript.ARENA_SIZE == Vector2(856.0, 480.0), "tutorial: the arena size changed", failures)
	_expect(TutorialScreenScript.PLAYABLE_BOUNDS == Rect2(62.0, 76.0, 732.0, 344.0), "tutorial: the playable bounds changed", failures)
	_expect(TutorialScreenScript.HERO_START == Vector2(150.0, 270.0), "tutorial: the hero start changed", failures)
	_expect(TutorialScreenScript.TARGET_POSITION == Vector2(700.0, 240.0), "tutorial: the single melee target moved", failures)
	_expect(TutorialScreenScript.MOVE_SPEED == 240.0 and TutorialScreenScript.MOVE_REQUIRED_DISTANCE == 140.0, "tutorial: the movement tuning changed", failures)
	_expect(TutorialScreenScript.DODGE_DISTANCE == 92.0 and TutorialScreenScript.CAST_RANGE == 280.0, "tutorial: the dodge or arrow range changed", failures)
	_expect(TutorialScreenScript.TRACE_DURATION == 0.34, "tutorial: the hit-trace timing changed", failures)
	_expect(TutorialScreenScript.PROJECTILE_SPEED == 720.0 and TutorialScreenScript.PROJECTILE_RADIUS == 4.0 and TutorialScreenScript.TARGET_CONTACT_RADIUS == 34.0, "tutorial: fixed projectile travel/contact tuning changed", failures)
	_expect(PlayerActionTimelineScript.WINDUP_TICKS == 5 and PlayerActionTimelineScript.RECOVERY_TICKS == 5 and PlayerActionTimelineScript.INPUT_BUFFER_TICKS == 4, "tutorial: the shared arrow action timing changed", failures)


func _test_training_art(screen, failures: Array[String]) -> void:
	## The arena's three roles come from the agreed atlases, cells included.
	var art = screen.get_art()
	_expect(art != null, "tutorial: the arena has no art loader", failures)
	if art == null:
		return
	_expect(art.has_real_art(), "tutorial: the published tutorial art did not load: %s" % str(screen.art_pending_reasons()), failures)
	_expect(screen.art_pending_reasons().is_empty(), "tutorial: healthy art still reported problems: %s" % str(screen.art_pending_reasons()), failures)
	_expect(String(TutorialArtScript.RANGER_ATLAS_PATH).ends_with("actors_v02/scene_atlas.json"), "tutorial: the ranger moved away from the agreed atlas", failures)
	_expect(String(TutorialArtScript.TARGET_ATLAS_PATH).ends_with("actors_v02/legacy_atlas.json"), "tutorial: the target moved away from the agreed atlas", failures)
	_expect(String(TutorialArtScript.GROUND_ATLAS_PATH).ends_with("ground_refine_v01/atlas.json"), "tutorial: the floor moved away from the approved ground", failures)
	_expect(TutorialArtScript.SCALE == 2, "tutorial: the arena art is no longer shown at integer 2x", failures)

	var cells := {}
	for facing: String in ["east", "north", "south", "west"]:
		var sprite: Dictionary = art.sprite("ranger.%s.idle" % facing)
		_expect(not sprite.is_empty(), "tutorial: ranger.%s.idle is missing" % facing, failures)
		if sprite.is_empty():
			continue
		var cell: Rect2i = sprite["rect"]
		_expect(cell.size == Vector2i(32, 48), "tutorial: ranger.%s.idle is not a 32x48 cell: %s" % [facing, str(cell)], failures)
		_expect(Vector2i(sprite["anchor"]) == Vector2i(16, 44), "tutorial: ranger.%s.idle anchor is not (16,44)" % facing, failures)
		_expect(String(sprite["texture_path"]) == TutorialArtScript.RANGER_TEXTURE_PATH, "tutorial: ranger.%s.idle reads another sheet" % facing, failures)
		var texture: Texture2D = sprite.get("_texture")
		_expect(texture != null and texture.get_size() == Vector2(128.0, 48.0), "tutorial: the ranger sheet is not the published 128x48", failures)
		_expect(cell.size * TutorialArtScript.SCALE == Vector2i(64, 96), "tutorial: the ranger stopped being displayed at 64x96", failures)
		cells[cell] = true
	_expect(cells.size() == 4, "tutorial: the four facings do not read four distinct cells: %s" % str(cells.keys()), failures)

	var target: Dictionary = art.target_sprite()
	_expect(not target.is_empty(), "tutorial: the single melee target cell is missing", failures)
	if not target.is_empty():
		_expect((target["rect"] as Rect2i) == Rect2i(0, 0, 48, 48), "tutorial: the melee target is not the 48x48 melee cell", failures)
		_expect(Vector2i(target["anchor"]) == Vector2i(24, 44), "tutorial: the melee target anchor is not (24,44)", failures)
		_expect(String(target["texture_path"]) == TutorialArtScript.TARGET_TEXTURE_PATH, "tutorial: the melee target reads another sheet", failures)
		var target_texture: Texture2D = target.get("_texture")
		_expect(target_texture != null and target_texture.get_size() == Vector2(192.0, 144.0), "tutorial: the enemy sheet is not the published 192x144", failures)
		_expect((target["rect"] as Rect2i).size * TutorialArtScript.SCALE == Vector2i(96, 96), "tutorial: the melee target stopped being displayed at 96x96", failures)

	var ground: Dictionary = art.ground_sprite()
	_expect(not ground.is_empty(), "tutorial: the approved floor cell is missing", failures)
	if not ground.is_empty():
		_expect((ground["rect"] as Rect2i) == Rect2i(0, 0, 1024, 640), "tutorial: the floor is not the full published ground sheet", failures)
		var ground_texture: Texture2D = ground.get("_texture")
		_expect(ground_texture != null and ground_texture.get_size() == Vector2(1024.0, 640.0), "tutorial: the approved ground is not the published 1024x640", failures)

	## The floor fills the arena as an integer 2x window, not as a downscale.
	var arena_size := Vector2i(TutorialScreenScript.ARENA_SIZE)
	var crop: Rect2i = art.ground_crop_rect(arena_size)
	_expect(crop == EXPECTED_ARENA_CROP, "tutorial: the arena floor crop moved to %s" % str(crop), failures)
	_expect(crop.size * TutorialArtScript.SCALE == arena_size, "tutorial: the floor crop does not cover the arena at exact 2x: %s" % str(crop.size * TutorialArtScript.SCALE), failures)
	_expect(crop.size != Vector2i(1024, 640), "tutorial: the whole 1024px sheet is being squeezed into the arena", failures)
	_expect(TutorialArtScript.crop_rect_for(Vector2i(856, 480), Vector2i(1024, 640), 2) == EXPECTED_ARENA_CROP, "tutorial: the crop helper is not stable", failures)


func _test_ranger_action_wiring(screen, failures: Array[String]) -> void:
	## The arena reads the shared action reader on the drill's own presentation
	## clock. A cast starts at the preparation frame and reaches the release frame
	## on the fifth tick that releases the real tutorial projectile.
	_expect(screen.ranger_action_pending_reasons().is_empty(), "tutorial: the published action atlas is not readable: %s" % str(screen.ranger_action_pending_reasons()), failures)
	var state: Dictionary = screen.get_ranger_animation_state()
	for key: String in ["facing", "moving", "phase_ticks", "dodge_ticks", "shoot_ticks", "tick"]:
		_expect(state.has(key), "tutorial: the trigger state lost %s" % key, failures)
	var arena = screen.get_arena()
	_expect(not arena.hero_frame.is_empty(), "tutorial: the arena resolved no hero frame", failures)
	_expect(not bool(arena.hero_frame.get("fallback", true)), "tutorial: the arena hero frame is a fallback", failures)
	_expect((arena.hero_frame.get("rect", Rect2i()) as Rect2i).size == RangerAnimationScript.CELL, "tutorial: the arena hero frame is %s" % str(arena.hero_frame.get("rect", Rect2i())), failures)
	_expect((arena.hero_frame.get("anchor", Vector2i.ZERO) as Vector2i) == RangerAnimationScript.DEFAULT_ANCHOR, "tutorial: the arena hero anchor is %s" % str(arena.hero_frame.get("anchor", Vector2i.ZERO)), failures)
	## The wider action cell still fits the frozen playable band at every corner,
	## with the head inside the slate the arena paints above the top bound.
	var hero_size := Vector2(RangerAnimationScript.CELL) * float(TutorialArtScript.SCALE)
	var arena_origin := Vector2(32.0, 78.0)
	var bounds: Rect2 = TutorialScreenScript.PLAYABLE_BOUNDS
	for feet: Vector2 in [bounds.position, Vector2(bounds.end.x, bounds.position.y), Vector2(bounds.position.x, bounds.end.y), bounds.end]:
		var drawn := Rect2(arena_origin + TutorialArtScript.sprite_origin(feet, RangerAnimationScript.DEFAULT_ANCHOR, TutorialArtScript.SCALE), hero_size)
		_expect(drawn.position.x >= 0.0 and drawn.end.x <= TutorialScreenScript.DESIGN_SIZE.x, "tutorial: the action cell leaves the design frame sideways at %s" % str(feet), failures)
		_expect(drawn.position.y >= 0.0 and drawn.end.y <= TutorialScreenScript.DESIGN_SIZE.y, "tutorial: the action cell leaves the design frame at %s" % str(feet), failures)
		_expect(drawn.position.y >= arena_origin.y - TutorialScreenScript.HERO_HEADROOM - 0.01, "tutorial: the action cell head leaves the painted slate at %s" % str(feet), failures)

	## The drill's clock is what expires a one-shot action; earlier checks have
	## already advanced it beyond the first cast and dodge windows.
	screen._process(0.5)
	screen.set_player_position(screen.get_target_position() - Vector2(120.0, 0.0))
	_expect(screen.request_cast(), "tutorial: the piercing-arrow action failed in the live arming", failures)
	var reader: Dictionary = screen.get_ranger_animation_report().get("reader", {})
	_expect(String(reader.get("clip", "")) == "ranger.east.shoot", "tutorial: the cast did not select the shoot clip: %s" % String(reader.get("clip", "")), failures)
	_expect(int(reader.get("frame", -1)) == 0, "tutorial: the cast skipped its preparation frame", failures)
	_expect(int(reader.get("entry_frame", -1)) == 0, "tutorial: the shoot clip did not begin at its authored first frame", failures)
	_expect(reader.get("fallback", true) == false, "tutorial: the cast fell back to the static idle cell", failures)
	var cast_event: Dictionary = (reader.get("events", {}) as Dictionary).get(TutorialScreenScript.EVENT_CAST, {})
	var first_token := String(cast_event.get("token", ""))
	_expect(first_token.begins_with("ranger:cast:"), "tutorial: the cast was latched without a token: %s" % str(cast_event), failures)
	_expect(int(cast_event.get("age_ticks", -1)) == 0, "tutorial: the cast event started late: %s" % str(cast_event), failures)
	_advance_action_ticks(screen, PlayerActionTimelineScript.WINDUP_TICKS)
	reader = screen.get_ranger_animation_report().get("reader", {})
	_expect(int(reader.get("frame", -1)) == 2 and int((reader.get("events", {}) as Dictionary).get(TutorialScreenScript.EVENT_CAST, {}).get("age_ticks", -1)) >= PlayerActionTimelineScript.WINDUP_TICKS, "tutorial: the fifth tick did not draw the release frame", failures)
	## A second cast is a distinct token, and the arrival of a newer one is what the
	## report has to show rather than a clip that quietly restarts on a redraw.
	_advance_action_ticks(screen, PlayerActionTimelineScript.RECOVERY_TICKS + 1)
	_expect(screen.request_cast(), "tutorial: a new cast after recovery was rejected", failures)
	var again: Dictionary = (screen.get_ranger_animation_report().get("reader", {}).get("events", {}) as Dictionary).get(TutorialScreenScript.EVENT_CAST, {})
	_expect(String(again.get("token", "")) != first_token, "tutorial: the second cast reused a token: %s" % str(again), failures)


func _test_actor_bounds_headroom(screen, failures: Array[String]) -> void:
	## The taller 2x hero may not be cropped: at every corner of the frozen playable
	## band the whole 64x96 cell has to stay inside the design frame and inside the
	## slate the arena actually paints, and the melee target has to stay whole too.
	var art = TutorialArtScript.new()
	if not art.has_real_art():
		_expect(false, "tutorial: the headroom check needs the published art", failures)
		return
	var arena: Control = screen.get_arena()
	_expect(arena != null and not arena.clip_contents, "tutorial: the arena started clipping its own actors", failures)
	var arena_origin := Vector2(32.0, 78.0)
	var arena_rect := Rect2(arena_origin, TutorialScreenScript.ARENA_SIZE)
	_expect(TutorialScreenScript.HERO_HEADROOM == 12.0, "tutorial: the hero headroom changed: %s" % str(TutorialScreenScript.HERO_HEADROOM), failures)
	var hero_cell: Rect2i = (art.sprite("ranger.south.idle").get("rect", Rect2i()) as Rect2i)
	var hero_anchor := Vector2i(art.sprite("ranger.south.idle").get("anchor", Vector2i.ZERO))
	var hero_size := Vector2(hero_cell.size) * float(TutorialArtScript.SCALE)
	var bounds := TutorialScreenScript.PLAYABLE_BOUNDS
	for feet: Vector2 in [bounds.position, Vector2(bounds.end.x, bounds.position.y), Vector2(bounds.position.x, bounds.end.y), bounds.end]:
		var drawn := Rect2(arena_origin + TutorialArtScript.sprite_origin(feet, hero_anchor, TutorialArtScript.SCALE), hero_size)
		_expect(drawn.position.x >= 0.0 and drawn.end.x <= TutorialScreenScript.DESIGN_SIZE.x, "tutorial: the hero cell leaves the design frame sideways at %s" % str(feet), failures)
		_expect(drawn.position.y >= 0.0 and drawn.end.y <= TutorialScreenScript.DESIGN_SIZE.y, "tutorial: the hero cell is cropped by the design frame at %s" % str(feet), failures)
		_expect(drawn.position.y >= arena_rect.position.y - TutorialScreenScript.HERO_HEADROOM - 0.01, "tutorial: the hero head leaves the painted slate at %s" % str(feet), failures)
	var target: Dictionary = art.target_sprite()
	var target_rect: Rect2i = target.get("rect", Rect2i()) as Rect2i
	var target_drawn := Rect2(
		arena_origin + TutorialArtScript.sprite_origin(screen.get_target_position(), target.get("anchor", Vector2i.ZERO) as Vector2i, TutorialArtScript.SCALE),
		Vector2(target_rect.size) * float(TutorialArtScript.SCALE)
	)
	_expect(target_drawn.size == Vector2(96.0, 96.0), "tutorial: the melee target is not drawn at its full 96x96", failures)
	_expect(arena_rect.encloses(target_drawn), "tutorial: the melee target is cut by the arena rect: %s" % str(target_drawn), failures)


func _test_sprite_placement_math(screen, failures: Array[String]) -> void:
	## Cells are placed by their published foot anchor, on the pixel grid, without
	## touching the simulation coordinates the drill is tuned around.
	_expect(TutorialArtScript.facing_key(Vector2.RIGHT) == "east", "tutorial: +x did not read as the east cell", failures)
	_expect(TutorialArtScript.facing_key(Vector2.LEFT) == "west", "tutorial: -x did not read as the west cell", failures)
	_expect(TutorialArtScript.facing_key(Vector2.UP) == "north", "tutorial: -y did not read as the north cell", failures)
	_expect(TutorialArtScript.facing_key(Vector2.DOWN) == "south", "tutorial: +y did not read as the south cell", failures)
	_expect(TutorialArtScript.facing_key(Vector2.ZERO) == "south", "tutorial: a standing-still ranger does not face the camera", failures)
	_expect(TutorialArtScript.facing_key(Vector2(-0.2, -3.0)) == "north", "tutorial: a mostly-upward heading read as a side cell", failures)
	var origin := TutorialArtScript.sprite_origin(Vector2(150.4, 270.6), Vector2i(16, 44), 2)
	_expect(origin == Vector2(118.0, 183.0), "tutorial: the foot-point origin is not snapped the expected way: %s" % str(origin), failures)
	_expect(origin.x == floor(origin.x) and origin.y == floor(origin.y), "tutorial: the drawn origin left the integer pixel grid", failures)
	_expect(TutorialArtScript.sprite_origin(Vector2(700.0, 240.0), Vector2i(24, 44), 2) == Vector2(652.0, 152.0), "tutorial: the melee target is no longer placed by its own anchor", failures)
	var fraction := Vector2(150.4, 270.6)
	screen.set_player_position(fraction)
	_expect(screen.get_player_position().is_equal_approx(fraction), "tutorial: pixel snapping moved the simulation coordinates", failures)
	screen.set_player_position(TutorialScreenScript.HERO_START)


func _test_pending_assets(screen, failures: Array[String]) -> void:
	## A missing source is reported, never faked: no stand-in body is drawn, and the
	## drill itself keeps running so the system stays testable.
	var broken = TutorialArtScript.new(true, {"ranger": "res://art/production/p1/does_not_exist/atlas.json"})
	_expect(not broken.has_real_art(), "tutorial: a missing ranger atlas still reported real art", failures)
	_expect(not broken.pending_reasons.is_empty(), "tutorial: a missing atlas was not reported as pending", failures)
	_expect(broken.pending_reason().contains("does_not_exist"), "tutorial: the pending reason does not name the missing atlas: %s" % broken.pending_reason(), failures)
	_expect(broken.ranger_sprite(Vector2.RIGHT).is_empty(), "tutorial: a broken ranger atlas still offered a body to draw", failures)
	_expect(broken.ground_texture() == null, "tutorial: a broken loader still handed out a floor texture", failures)
	screen.apply_art_for_test(broken)
	var note := screen.find_child("TutorialArtNote", true, false) as Label
	_expect(note != null, "tutorial: the pending-art note lost its stable node", failures)
	if note != null:
		_expect(note.visible and note.text.contains("ASSETS PENDING"), "tutorial: pending art was not reported on screen: %s" % note.text, failures)
	var arena: Control = screen.get_arena()
	_expect(arena != null and not arena.art_ready(), "tutorial: the arena claimed ready art while the atlas was missing", failures)
	_expect(not screen.art_pending_reasons().is_empty(), "tutorial: the screen lost the pending reason", failures)
	screen.set_player_position(TutorialScreenScript.TARGET_POSITION - Vector2(40.0, 0.0))
	_advance_action_ticks(screen, PlayerActionTimelineScript.WINDUP_TICKS + PlayerActionTimelineScript.RECOVERY_TICKS + 1)
	_expect(screen.request_cast(), "tutorial: pending art broke the piercing-arrow action", failures)
	_advance_action_ticks(screen, PlayerActionTimelineScript.WINDUP_TICKS)
	_expect(bool(screen.get_checklist_snapshot().cast_hit), "tutorial: pending art broke the checklist", failures)
	screen.apply_art_for_test(TutorialArtScript.new())
	if note != null:
		_expect(not note.visible and note.text.is_empty(), "tutorial: the pending note stayed on screen after the art came back", failures)
	_expect(screen.art_pending_reasons().is_empty(), "tutorial: restoring real art still reported problems: %s" % str(screen.art_pending_reasons()), failures)
	var restored: Control = screen.get_arena()
	_expect(restored != null and restored.art_ready(), "tutorial: the arena did not take the restored art", failures)


func _test_no_early_placeholder_art(failures: Array[String]) -> void:
	## Source level: the arena no longer reads the early placeholder sheet, and the
	## font stays the packaged ShellTheme's business rather than this screen's.
	for path: String in [SCREEN_SOURCE_PATH, ART_SOURCE_PATH]:
		var file := FileAccess.open(path, FileAccess.READ)
		_expect(file != null, "tutorial: %s is not readable" % path, failures)
		if file == null:
			continue
		var source := file.get_as_text()
		file.close()
		_expect(not source.contains(EARLY_PLACEHOLDER_MARKER), "tutorial: %s still reads %s" % [path, EARLY_PLACEHOLDER_MARKER], failures)
		_expect(not source.contains(EARLY_ATLAS_MARKER), "tutorial: %s still references the early actors atlas" % path, failures)
		_expect(not source.contains("SystemFont") and not source.contains(".ttf") and not source.contains(".otf"), "tutorial: %s started owning font assets" % path, failures)
		_expect(not source.contains("user://") and not source.contains("SaveStore"), "tutorial: %s started touching persistence" % path, failures)


func _expect(condition: bool, message: String, failures: Array[String]) -> void: Assert.expect(condition, message, failures)


func _advance_action_ticks(screen, ticks: int) -> void:
	## A small epsilon avoids a binary-float floor landing one tick short while the
	## shared authority still decides which events become due.
	screen._process(float(ticks) / float(RangerAnimationScript.SIM_TICKS_PER_SECOND) + 0.0001)
