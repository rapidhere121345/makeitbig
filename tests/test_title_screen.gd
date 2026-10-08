extends SceneTree
## Regression for the real title entry: the two actions and their stable node
## names, the class list, the save-state behaviour of present(), the Chinese copy
## band, and the backdrop contract.
##
## The backdrop is checked in whichever mode the repository is actually in: the
## produced plate when it is published, otherwise the provisional layered crop.
## Both modes must draw real production pixels at nearest integer 2x, must never
## read the early placeholder art, and must never animate a still image.

const TitleScreenScript = preload("res://src/presentation/title_screen.gd")
const TitleArtHelperScript = preload("res://src/presentation/title_art_helper.gd")

const TITLE_SOURCE_PATH := "res://src/presentation/title_screen.gd"
const BACKDROP_SOURCE_PATH := "res://src/presentation/title_art_helper.gd"
## The early placeholder directory the title used to read. It stays on disk for
## history; the title must not read from it again.
const EARLY_PLACEHOLDER_MARKER := "art/early/"
const EXPECTED_PLATE_SUFFIX := "art/production/p1/title_concept_v02/background.png"
const EXPECTED_TOWER_RECT := Rect2(320.0, 88.0, 320.0, 224.0)
## The approved Chinese UI band, plus the one approved wordmark exception.
const CHINESE_BODY_MIN := 18
const CHINESE_BODY_MAX := 22


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	root.size = Vector2i(1280, 720)
	var screen = TitleScreenScript.new()
	root.add_child(screen)
	await process_frame
	await process_frame
	var identity := screen.find_child("RangerIdentity", true, false) as Label
	_expect(identity != null and "游侠" in identity.text and screen.get_selected_class() == "ranger", "title: static ranger identity missing", failures)
	_expect(screen.find_child("ClassPicker", true, false) == null, "title: one-class dropdown still shown", failures)
	var requested: Array[String] = []
	screen.new_game_requested.connect(func(class_id: String) -> void: requested.append(class_id))
	var button := screen.find_child("NewGameButton", true, false) as Button
	_expect(button != null, "title: new-game action has no stable node", failures)
	if button != null:
		button.pressed.emit()
	_expect(requested == ["ranger"], "title: new game did not emit the only playable ranger class", failures)
	await _test_save_state_and_focus(screen, failures)
	_test_copy_band(failures)
	_test_menu_clearance(screen, failures)
	await _test_footer_hint(screen, failures)
	_test_backdrop(screen, failures)
	_test_unpublished_assets(screen, failures)
	root.remove_child(screen)
	screen.free()
	if failures.is_empty():
		print("PASS  test_title_screen.gd")
		quit(0)
		return
	for failure in failures:
		printerr("- %s" % failure)
	quit(1)


func _test_save_state_and_focus(screen, failures: Array[String]) -> void:
	## present() is the shell's only input: it carries the profile state and the
	## status prose, and it must keep driving the continue action and nothing else.
	var continue_button := screen.find_child("ContinueButton", true, false) as Button
	var status := screen.find_child("StatusLabel", true, false) as Label
	var new_game := screen.find_child("NewGameButton", true, false) as Button
	_expect(continue_button != null and status != null, "title: continue action or status line lost its node", failures)
	if continue_button == null or status == null or new_game == null:
		return
	_expect(continue_button.disabled, "title: continue was selectable before any profile was reported", failures)
	var events: Array[String] = []
	screen.continue_requested.connect(func() -> void: events.append("continue"))
	_click(continue_button)
	_expect(events.is_empty(), "title: a disabled continue action still emitted continue_requested", failures)
	screen.present(true, "Recovered profile generation 3.")
	_expect(not continue_button.disabled, "title: an available profile did not enable continue", failures)
	_expect(status.visible and status.text == "Recovered profile generation 3.", "title: the status line did not carry the shell message", failures)
	_click(continue_button)
	_expect(events == ["continue"], "title: continue did not emit continue_requested exactly once", failures)
	screen.present(false, "")
	_expect(continue_button.disabled, "title: dropping the profile did not disable continue again", failures)
	_expect(not status.visible and status.text.is_empty(), "title: an empty status message stayed on screen", failures)
	## Keyboard reachability without changing the focus policy: the actions stay
	## focusable and the focus ring is the theme's own.
	_expect(new_game.focus_mode != Control.FOCUS_NONE, "title: the new-game action is not focusable", failures)
	_expect(continue_button.focus_mode != Control.FOCUS_NONE, "title: the continue action is not focusable", failures)
	new_game.grab_focus()
	_expect(new_game.has_focus(), "title: the new-game action could not take focus", failures)


func _click(button: Button) -> void:
	## Real viewport input rather than a bare signal emit: the GUI path is what
	## decides whether a disabled action swallows the click.
	var centre := button.get_global_rect().get_center()
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = centre
		event.global_position = centre
		root.push_input(event)


func _test_copy_band(failures: Array[String]) -> void:
	## The approved Chinese band for the real entry, and its one exception.
	for size: int in [TitleScreenScript.KICKER_FONT_SIZE, TitleScreenScript.CONTROL_FONT_SIZE, TitleScreenScript.ACTION_FONT_SIZE, TitleScreenScript.BODY_FONT_SIZE]:
		_expect(size >= CHINESE_BODY_MIN and size <= CHINESE_BODY_MAX, "title: copy size %d left the approved 18-22px band" % size, failures)
	_expect(TitleScreenScript.TITLE_FONT_SIZE == 52, "title: the wordmark stopped being the approved 52px exception", failures)
	_expect(TitleScreenScript.PREMISE_TEXT.contains("旧路") and TitleScreenScript.PREMISE_TEXT.contains("炉边镇"), "title: opening lacks the road and town situation", failures)
	_expect(TitleScreenScript.CLASS_ID == "ranger", "title: the class entry stopped being ranger", failures)


func _test_menu_clearance(screen, failures: Array[String]) -> void:
	## The left menu must not reach into the half that carries the tower.
	var veil := screen.find_child("MenuVeil", true, false) as Control
	var rail := screen.find_child("CopperRail", true, false) as Control
	_expect(veil != null and rail != null, "title: the menu column lost its veil or its rail", failures)
	if veil == null or rail == null:
		return
	var menu_right := maxf(veil.position.x + veil.size.x, rail.position.x + rail.size.x)
	_expect(menu_right <= TitleScreenScript.DESIGN_SIZE.x * 0.5, "title: the menu column reaches %.0fpx, past the middle of the frame" % menu_right, failures)
	_expect(veil.color.a > 0.0 and veil.color.a < 1.0, "title: the veil is not a translucent scrim", failures)
	_expect(rail.color == TitleScreenScript.COPPER_DULL, "title: the rail left the dull-copper accent", failures)


func _test_footer_hint(screen, failures: Array[String]) -> void:
	var hint := screen.find_child("KeyboardHintLabel", true, false) as Label
	_expect(hint != null and hint.text == TitleScreenScript.FOOTER_TEXT, "title: keyboard hint missing", failures)
	var new_game := screen.find_child("NewGameButton", true, false) as Button
	for viewport_size in [Vector2i(1280, 720), Vector2i(1600, 900)]:
		root.size = viewport_size
		await process_frame
		await process_frame
		var area := Rect2(Vector2.ZERO, Vector2(viewport_size))
		for node_name in ["TitleColumn", "Premise", "RangerIdentity", "NewGameButton", "ContinueButton", "KeyboardHintLabel"]:
			var control := screen.find_child(node_name, true, false) as Control
			_expect(control != null and area.encloses(control.get_global_rect()), "title: control outside " + str(viewport_size) + ": " + node_name, failures)
		_expect(new_game.has_focus(), "title: new-game focus missing", failures)
	root.size = Vector2i(1280, 720)
	await process_frame


func _test_backdrop(screen, failures: Array[String]) -> void:
	var backdrop = screen.get_backdrop()
	_expect(backdrop != null, "title: the title art backdrop is missing", failures)
	if backdrop == null:
		return
	_expect(backdrop.world_viewport.size == TitleArtHelperScript.NATIVE_VIEW, "title: the backdrop native view is no longer 640x360", failures)
	_expect(backdrop.world_display.size.is_equal_approx(Vector2(TitleArtHelperScript.NATIVE_VIEW)), "title: the backdrop display stopped being the native 640x360 cell", failures)
	_expect(backdrop.world_display.scale.is_equal_approx(Vector2(2.0, 2.0)), "title: the backdrop is not shown at exact integer 2x", failures)
	_expect(backdrop.world_display.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "title: the backdrop display left nearest filtering", failures)
	_expect(backdrop.world_display.global_position.is_equal_approx(Vector2.ZERO), "title: the backdrop is not aligned to the design origin", failures)
	_expect(backdrop.is_ready(), "title: no backdrop source could be drawn: %s" % str(backdrop.pending_reasons()), failures)
	_expect(backdrop.pending_reasons().is_empty(), "title: the active backdrop contract reported problems: %s" % str(backdrop.pending_reasons()), failures)
	_expect(String(TitleArtHelperScript.TITLE_PLATE_PATH).ends_with(EXPECTED_PLATE_SUFFIX), "title: the produced plate moved away from the agreed path", failures)
	_expect(TitleArtHelperScript.TITLE_PLATE_SIZE == Vector2i(640, 360), "title: the produced plate contract stopped being 640x360", failures)
	var source := String(backdrop.backdrop_source())
	if source == TitleArtHelperScript.BACKDROP_PLATE:
		_test_plate_backdrop(backdrop, failures)
	elif source == TitleArtHelperScript.BACKDROP_LAYERS:
		_test_layered_backdrop(backdrop, failures)
	else:
		_expect(false, "title: the backdrop fell through to no source at all", failures)
	_test_static_and_integral(backdrop, failures)
	_test_life_overlay(backdrop, failures)
	_test_no_placeholder_art(failures)
	_test_provisional_fallback(backdrop, failures)


func _test_plate_backdrop(backdrop, failures: Array[String]) -> void:
	## The produced plate is the whole title: one image, native size, drawn once.
	_expect(backdrop.plate_status() == TitleArtHelperScript.PLATE_STATUS_READY, "title: the plate is drawn but still reports pending", failures)
	_expect(String(backdrop.plate_reason()).is_empty(), "title: an accepted plate still carries a rejection reason: %s" % String(backdrop.plate_reason()), failures)
	_expect(String(TitleArtHelperScript.TITLE_PLATE_ATLAS_PATH).ends_with("title_concept_v02/atlas.json"), "title: the plate atlas moved away from the agreed path", failures)
	_expect(TitleArtHelperScript.TITLE_PLATE_SPRITE_ID == "title.background", "title: the plate sprite id is no longer title.background", failures)
	var plate := backdrop.field_layer.get_node_or_null(NodePath("TitlePlate")) as Sprite2D
	_expect(plate != null, "title: the plate is not drawn into the field layer", failures)
	if plate != null:
		var frame: Dictionary = backdrop.frame_report()
		var plate_rect := frame.plate_rect as Rect2
		var plate_anchor := frame.plate_anchor as Vector2i
		_expect(plate.region_rect.is_equal_approx(plate_rect), "title: the plate is cut differently from its published rect: %s" % str(plate.region_rect), failures)
		_expect(plate.position.is_equal_approx(Vector2(plate_anchor)) and plate.offset.is_equal_approx(-Vector2(plate_anchor)), "title: the plate is not placed by its published anchor", failures)
		_expect(plate.texture != null and plate.texture.get_size() == Vector2(TitleArtHelperScript.TITLE_PLATE_SIZE), "title: the plate texture is not the published 640x360 image", failures)
		_expect(plate_rect.position.is_equal_approx(Vector2.ZERO) and plate_rect.size.is_equal_approx(Vector2(TitleArtHelperScript.TITLE_PLATE_SIZE)), "title: the plate rect is no longer the full native frame: %s" % str(plate_rect), failures)
		_expect(plate_rect.encloses(Rect2(Vector2.ZERO, Vector2(TitleArtHelperScript.NATIVE_VIEW))), "title: the plate does not cover the native frame", failures)
	var audit: Dictionary = backdrop.render_audit()
	var layers := audit.get("layers", {}) as Dictionary
	_expect(int(layers.get("field", 0)) == 1, "title: the plate is not drawn exactly once", failures)
	_expect(int(layers.get("ground", 0)) == 0 and int(layers.get("object_lower", 0)) == 0 and int(layers.get("actors", 0)) == 0, "title: layer sprites were drawn on top of the produced plate: %s" % str(layers), failures)
	_expect(String(audit.get("wanderer", "")).is_empty(), "title: the provisional wanderer survived into plate mode", failures)


func _test_layered_backdrop(backdrop, failures: Array[String]) -> void:
	## Provisional mode: the plate is unpublished and the view says so, while the
	## crop still comes from the published hamlet pair.
	_expect(backdrop.plate_status() == TitleArtHelperScript.PLATE_STATUS_PENDING, "title: the provisional crop claims a produced plate", failures)
	var reason := String(backdrop.plate_reason())
	_expect(reason.is_empty() or reason.contains("title_concept_v02/background.png"), "title: the pending plate reason does not name the agreed path: %s" % reason, failures)
	var frame: Dictionary = backdrop.frame_report()
	_expect(String(frame.focus_placement) == "hearth", "title: the crop is not pinned to the tower placement", failures)
	_expect(bool(frame.focus_from_layout), "title: the crop fell back instead of reading the published tower placement", failures)
	_expect(bool(frame.integer_offset), "title: the crop offset is not on the integer pixel grid", failures)
	_expect(bool(frame.crop_inside_field), "title: the crop left the published ground field", failures)
	_expect(bool(frame.tower_available) and bool(frame.tower_inside_view), "title: the tower is not fully inside the 640x360 frame", failures)
	_expect((frame.tower_rect_in_view as Rect2).is_equal_approx(EXPECTED_TOWER_RECT), "title: the tower cell moved to %s" % str(frame.tower_rect_in_view), failures)
	_expect((frame.focus_world_feet as Vector2).is_equal_approx(Vector2(584.0, 402.0)), "title: the tower feet are no longer the published ones", failures)
	_expect((frame.tower_rect_in_view as Rect2).position.x >= float(TitleArtHelperScript.NATIVE_VIEW.x) * 0.5, "title: the tower drifted out of the right half of the frame", failures)
	_expect((frame.wanderer_view_point as Vector2).x < (frame.tower_rect_in_view as Rect2).position.x, "title: the wanderer stands inside the tower cell", failures)
	var audit: Dictionary = backdrop.render_audit()
	var layers := audit.get("layers", {}) as Dictionary
	_expect(int(layers.get("field", 0)) == 1, "title: the ground field is not drawn exactly once", failures)
	_expect(int(layers.get("actors", 0)) >= 3, "title: the tower bands and the wanderer are not in the feet-sorted layer: %s" % str(audit), failures)
	var nodes := audit.get("sprite_nodes", []) as Array
	_expect("Upper_hearth" in nodes and "Lower_hearth" in nodes, "title: the tower lost its split banding: %s" % str(nodes), failures)
	_expect(String(audit.get("wanderer", "")) == "Wanderer", "title: the approved wanderer is not drawn", failures)
	_expect(String(frame.wanderer_sprite_id).ends_with(".idle"), "title: the wanderer is not a published static frame: %s" % String(frame.wanderer_sprite_id), failures)
	_expect(String(backdrop._sprites[String(frame.wanderer_sprite_id)].get("source", "")) == "scene", "title: the wanderer is not the approved scene_rework ranger", failures)


func _test_static_and_integral(backdrop, failures: Array[String]) -> void:
	## Every drawn pixel stays a cut of a production texture on the native grid:
	## no atlas frame stepping, no fractional placement, no smoothing.
	var sprites: Array[Sprite2D] = []
	for layer in [backdrop.field_layer, backdrop.ground_layer, backdrop.object_lower_layer, backdrop.actor_layer]:
		for child in layer.get_children():
			if child is Sprite2D:
				sprites.append(child)
	_expect(not sprites.is_empty(), "title: the backdrop drew no sprite at all", failures)
	for sprite in sprites:
		_expect(sprite.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "title: %s lost nearest filtering" % sprite.name, failures)
		_expect(not sprite.has_meta("frame_index"), "title: %s looks like a stepped animation frame" % sprite.name, failures)
		_expect(sprite.position == Vector2(roundf(sprite.position.x), roundf(sprite.position.y)), "title: %s is not on a whole pixel: %s" % [sprite.name, str(sprite.position)], failures)
		_expect(sprite.offset == Vector2(roundf(sprite.offset.x), roundf(sprite.offset.y)), "title: %s has a fractional offset: %s" % [sprite.name, str(sprite.offset)], failures)
		_expect(sprite.region_enabled and sprite.texture is Texture2D and not (sprite.texture is AtlasTexture), "title: %s does not cut a production texture directly" % sprite.name, failures)
		_expect((sprite.region_rect.position as Vector2) == (sprite.region_rect.position as Vector2).floor(), "title: %s cuts a fractional source rect" % sprite.name, failures)
		_expect((sprite.region_rect.size as Vector2) == (sprite.region_rect.size as Vector2).floor(), "title: %s cuts a fractional source size" % sprite.name, failures)


func _test_life_overlay(backdrop, failures: Array[String]) -> void:
	## The produced life loop: real frames from the published atlas stepped by the
	## published fps, drawn in the same integer-scaled world layer. The frames are
	## checked against a deterministic clock so the expectation never depends on
	## wall time, and the two loops only meet again on the 2s common period.
	var life: Dictionary = backdrop.life_contract()
	_expect(String(life.get("atlas_path", "")).ends_with("title_life_v01/atlas.json"), "title: the life overlay moved away from the published atlas", failures)
	if backdrop.backdrop_source() != TitleArtHelperScript.BACKDROP_PLATE:
		## The overlay is authored against the plate's own pixels: on any other
		## backdrop it must stay off rather than land on anchors that do not apply.
		_expect(not bool(life.get("drawn", false)), "title: the life overlay was placed on a backdrop it was not authored for", failures)
		return
	_expect(backdrop.life_ready(), "title: the published life frames did not load: %s" % backdrop.life_reason(), failures)
	_expect(String(life.get("status", "")) == TitleArtHelperScript.LOOP_STATUS_READY, "title: the life overlay does not report its produced frames", failures)
	_expect(String(backdrop.life_reason()).is_empty(), "title: an accepted life package still carries a rejection reason: %s" % backdrop.life_reason(), failures)
	_expect(backdrop.loop_status() == TitleArtHelperScript.LOOP_STATUS_READY, "title: the title loop status did not follow the produced frames", failures)
	_expect(is_equal_approx(backdrop.life_period(), TitleArtHelperScript.LIFE_EXPECTED_PERIOD), "title: the life loops no longer share a 2s period: %f" % backdrop.life_period(), failures)
	_expect(bool(life.get("drawn", false)), "title: the produced life frames are not drawn on the plate", failures)
	_test_life_assets(backdrop, failures)
	_test_life_stepping(backdrop, failures)
	## Shared transform: the overlay lives inside the same 640x360 viewport the plate
	## is drawn in, so one integer 2x display scales both and nothing is re-derived.
	_expect(backdrop.life_overlay_layer != null and backdrop.life_overlay_layer.get_parent() == backdrop.world_root, "title: the life overlay is not in the same world layer as the plate", failures)
	_expect(backdrop.world_root != null and backdrop.world_root.get_parent() == backdrop.world_viewport, "title: the life overlay left the integer-scaled 640x360 viewport", failures)
	_expect(backdrop.world_display.scale.is_equal_approx(Vector2(2.0, 2.0)), "title: the shared 2x display changed once the loop existed", failures)


func _test_life_assets(backdrop, failures: Array[String]) -> void:
	backdrop.set_life_time(0.0)
	var fire := backdrop.life_overlay_layer.get_node_or_null(NodePath("LifeFire")) as Sprite2D
	var steam := backdrop.life_overlay_layer.get_node_or_null(NodePath("LifeSteam")) as Sprite2D
	_expect(fire != null and steam != null, "title: the produced flame or steam overlay is missing", failures)
	if fire == null or steam == null:
		return
	## The anchors were read off the published plate: the flame sits on the brazier
	## rim and the steam leaves the pot mouth nine pixels above it.
	_expect(fire.position == Vector2(338, 237) and fire.offset == Vector2(-4, -9), "title: the flame anchor is not the verified (338, 237) with the published frame anchor", failures)
	_expect(steam.position == Vector2(338, 228) and steam.offset == Vector2(-6, -17), "title: the steam anchor is not the verified (338, 228) with the published frame anchor", failures)
	_expect(fire.region_rect.size == Vector2(8, 10), "title: the flame cell is not the published 8x10: %s" % str(fire.region_rect.size), failures)
	_expect(steam.region_rect.size == Vector2(12, 18), "title: the steam cell is not the published 12x18: %s" % str(steam.region_rect.size), failures)
	## The cuts come from the two published sheets, not from anything drawn here.
	_expect(fire.texture != null and fire.texture.get_size() == Vector2(32, 10), "title: the flame is not cut from the published 32x10 sheet", failures)
	_expect(steam.texture != null and steam.texture.get_size() == Vector2(48, 18), "title: the steam is not cut from the published 48x18 sheet", failures)
	for sprite: Sprite2D in [fire, steam]:
		_expect(sprite.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "title: %s left nearest filtering" % sprite.name, failures)
		_expect(sprite.region_enabled and not (sprite.texture is AtlasTexture), "title: %s does not cut its published sheet directly" % sprite.name, failures)
		_expect(sprite.position == Vector2(roundf(sprite.position.x), roundf(sprite.position.y)), "title: %s is not on the native pixel grid" % sprite.name, failures)


func _test_life_stepping(backdrop, failures: Array[String]) -> void:
	## fire 4@4fps and steam 4@2fps: at 0/0.5/1/2s they read 0/2/0/0 and 0/1/2/0, and
	## both are back on their first frame after the 2s common period.
	var expected := {
		"life.fire": [0, 2, 0, 0],
		"life.steam": [0, 1, 2, 0],
	}
	var samples: Array[float] = [0.0, 0.5, 1.0, 2.0]
	var fire := backdrop.life_overlay_layer.get_node_or_null(NodePath("LifeFire")) as Sprite2D
	for slot in range(samples.size()):
		var seconds := samples[slot]
		backdrop.set_life_time(seconds)
		var contract: Dictionary = backdrop.life_contract()
		for raw_overlay: Variant in contract.get("overlays", []) as Array:
			var overlay := raw_overlay as Dictionary
			var animation := String(overlay.animation)
			var index := int(overlay.frame_index)
			_expect(int((expected[animation] as Array)[slot]) == index, "title: %s shows frame %d at %.1fs" % [animation, index, seconds], failures)
			var frame_rect := overlay.frame_rect as Rect2
			_expect(frame_rect.position.x == float(index) * frame_rect.size.x, "title: %s cuts frame %d outside its published grid: %s" % [animation, index, str(frame_rect)], failures)
		if fire != null:
			_expect(fire.region_rect.position.x == float(int(fire.region_rect.position.x)), "title: the drawn flame frame is off the atlas grid", failures)
	backdrop.set_life_time(0.0)
	var at_zero := fire.region_rect if fire != null else Rect2()
	backdrop.set_life_time(2.0)
	_expect(fire != null and fire.region_rect == at_zero, "title: the flame did not return to its first frame after the 2s period", failures)
	backdrop.set_life_time(0.0)


func _test_provisional_fallback(backdrop, failures: Array[String]) -> void:
	## The fallback has to stay alive as a real, tested path: the published hamlet
	## pair still renders a faithful crop if the plate is ever withdrawn, and the
	## view has to report that it is the provisional one.
	var atlas := _read_json("res://art/production/p1/hamlet_concept_v02/atlas.json")
	var layout := _read_json("res://art/production/p1/hamlet_concept_v02/layout.json")
	_expect(not atlas.is_empty() and not layout.is_empty(), "title: the hamlet pair is not readable for the fallback check", failures)
	if atlas.is_empty() or layout.is_empty():
		return
	var scene_atlas := _read_json("res://art/production/p1/scene_rework_v01/atlas.json")
	_expect(not scene_atlas.is_empty(), "title: the approved ranger atlas is not readable for the fallback check", failures)
	backdrop.configure_sources({"hamlet": atlas, "scene": scene_atlas}, layout)
	_expect(backdrop.backdrop_source() == TitleArtHelperScript.BACKDROP_LAYERS, "title: the fallback pair did not produce a layered crop, got %s" % backdrop.backdrop_source(), failures)
	_test_layered_backdrop(backdrop, failures)
	backdrop.load_default_assets()
	_expect(backdrop.backdrop_source() != TitleArtHelperScript.BACKDROP_NONE, "title: restoring the published assets left no backdrop source", failures)
	_expect(backdrop.is_ready(), "title: restoring the published assets left the backdrop pending: %s" % str(backdrop.pending_reasons()), failures)


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}


func _test_no_placeholder_art(failures: Array[String]) -> void:
	## Source level: the title no longer references the early placeholder images,
	## and the font stays the shared ShellTheme's business rather than this screen's.
	for path: String in [TITLE_SOURCE_PATH, BACKDROP_SOURCE_PATH]:
		var file := FileAccess.open(path, FileAccess.READ)
		_expect(file != null, "title: %s is not readable" % path, failures)
		if file == null:
			continue
		var source := file.get_as_text()
		file.close()
		_expect(not source.contains(EARLY_PLACEHOLDER_MARKER), "title: %s still reads %s" % [path, EARLY_PLACEHOLDER_MARKER], failures)
		_expect(not source.contains("title_fx_sheet"), "title: %s still wires the early FX sheet" % path, failures)
		_expect(not source.contains("SystemFont") and not source.contains(".ttf") and not source.contains(".otf"), "title: %s started owning font assets" % path, failures)
		_expect(not source.contains("user://") and not source.contains("SaveStore"), "title: %s started touching persistence" % path, failures)


func _test_unpublished_assets(screen, failures: Array[String]) -> void:
	## While nothing is published the title stays a plain slate field: no sprite, no
	## stand-in building, and the two actions keep working.
	var backdrop = screen.get_backdrop()
	if backdrop == null:
		return
	backdrop.configure({}, {})
	_expect(not backdrop.is_ready(), "title: an empty atlas must not report ready assets", failures)
	_expect(backdrop.backdrop_source() == TitleArtHelperScript.BACKDROP_NONE, "title: an empty atlas still claimed a backdrop source", failures)
	_expect(not backdrop.pending_reasons().is_empty(), "title: missing assets were not reported as pending", failures)
	var audit: Dictionary = backdrop.render_audit()
	var layers := audit.get("layers", {}) as Dictionary
	_expect(int(layers.get("field", 0)) == 0 and int(layers.get("actors", 0)) == 0, "title: pending assets drew sprites anyway", failures)
	_expect(String(audit.get("wanderer", "")).is_empty(), "title: pending assets still drew the wanderer", failures)
	_expect(String(audit.get("life_status", "")) == TitleArtHelperScript.LOOP_STATUS_UNPRODUCED, "title: a fixture backdrop still claimed produced life frames", failures)
	_expect(not bool(audit.get("life_drawn", false)), "title: a fixture backdrop drew the life overlay", failures)
	_expect((audit.get("life_nodes", []) as Array).is_empty(), "title: a fixture backdrop left life nodes behind", failures)
	_expect(backdrop.life_overlay_layer != null and backdrop.life_overlay_layer.get_child_count() == 0, "title: the life layer kept sprites after the assets went away", failures)
	var requested: Array[String] = []
	screen.new_game_requested.connect(func(class_id: String) -> void: requested.append(class_id))
	var button := screen.find_child("NewGameButton", true, false) as Button
	if button != null:
		button.pressed.emit()
	_expect(requested == ["ranger"], "title: pending assets broke the new-game action", failures)


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
