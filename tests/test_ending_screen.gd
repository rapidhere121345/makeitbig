extends SceneTree

const EndingScreenScript = preload("res://src/presentation/ending_screen.gd")

## The dedicated early-return illustration, and the floor
## no English copy may fall under (approved baseline: Text 18-22 display pixels).
const ILLUSTRATION_PATH := "res://art/production/p1/hearth_return_v01/background.png"
const ILLUSTRATION_SIZE := Vector2(640.0, 360.0)
const FONT_FLOOR := 18
const EDGE_EPSILON := 0.5


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	var screen = EndingScreenScript.new()
	root.add_child(screen)
	screen.present({
		"initial_class": "ranger",
		"progression": {"contract_wins": 7, "auto_contract_wins": 1},
	}, {
		"outcome": "final_victory",
		"contract_id": "auto_certification",
		"mode": "Auto",
		"ticks": 14,
		"elapsed_seconds": 0.47,
		"rewards": {"equipment_drop_count": 2},
	})
	var base_action := screen.find_child("ReturnToBaseButton", true, false) as Button
	var title_action := screen.find_child("ReturnToTitleButton", true, false) as Button
	_expect(base_action != null and root.gui_get_focus_owner() == base_action,
		"ending: initial keyboard focus did not land on the primary action", failures)
	if title_action != null:
		title_action.grab_focus()
		## An ordinary refresh must not steal focus — then restore the real
		## payload so every later assertion reads the actual ending data.
		screen.present({"initial_class": "ranger", "progression": {"contract_wins": 7}}, {"outcome": "final_victory"})
		_expect(root.gui_get_focus_owner() == title_action,
			"ending: ordinary refresh stole keyboard focus", failures)
		screen.present({
			"initial_class": "ranger",
			"progression": {"contract_wins": 7, "auto_contract_wins": 1},
		}, {
			"outcome": "final_victory",
			"contract_id": "auto_certification",
			"mode": "Auto",
			"ticks": 14,
			"elapsed_seconds": 0.47,
			"rewards": {"equipment_drop_count": 2},
		})
	var title: Label = screen.find_child("EndingTitle", true, false)
	var copy: Label = screen.find_child("EndingCopy", true, false)
	var preview: Label = screen.find_child("MidgamePreview", true, false)
	var profile_label: Label = screen.get("_profile_label")
	var result_label: Label = screen.get("_result_label")
	_expect(title != null and title.text == "Looking Back at the Hearth",
		"ending: title did not present the journey ending", failures)
	_expect(copy != null and "Threshold Colossus" in copy.text and "proxy home safely" in copy.text and "next road" in copy.text,
		"ending: completion copy did not close the journey in player language", failures)
	_expect(profile_label != null and "Class: Ranger" in profile_label.text and "Contract wins: 7" in profile_label.text and "Proxy wins: 1" in profile_label.text,
		"ending: profile summary lost the English class or the graduation progress", failures)
	_expect(result_label != null and "Early Graduation Contract" in result_label.text and "Final Victory" in result_label.text
		and "Proxy Expedition" in result_label.text and "Time: 0.47" in result_label.text and "Equipment gained: 2" in result_label.text
		and "Tick" not in result_label.text
		and "FINAL_VICTORY" not in result_label.text and "auto_certification" not in result_label.text,
		"ending: the English graduation summary lost a quantity or kept a raw enum: %s" % (result_label.text if result_label != null else "<missing>"), failures)
	var raw_record: Label = screen.find_child("EndingRawRecord", true, false)
	_expect(raw_record == null, "ending: raw contract record escaped the test console", failures)
	_expect(preview != null and "Unsolved Sacred Laws" in preview.text and "sort your equipment" in preview.text and "side contracts" in preview.text and "g1" not in preview.text,
		"ending: onward guidance is missing or contains an internal id", failures)

	# --- early-return staging is separate from the full-game E03 repair ---
	var illustration: TextureRect = screen.get_illustration()
	_expect(illustration != null and illustration.texture != null, "ending: the approved illustration was not drawn", failures)
	if illustration != null:
		_expect(screen.get_illustration_source_path() == ILLUSTRATION_PATH,
			"ending: the illustration does not name its approved source: %s" % screen.get_illustration_source_path(), failures)
		_expect(illustration.custom_minimum_size == ILLUSTRATION_SIZE,
			"ending: the illustration is not drawn at its native %s: %s" % [str(ILLUSTRATION_SIZE), str(illustration.custom_minimum_size)], failures)
		_expect(illustration.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST,
			"ending: the illustration left the single pixel grid", failures)
		_expect((illustration.texture as Texture2D).get_size() == ILLUSTRATION_SIZE,
			"ending: the loaded plate is not the published size", failures)
		var scene: Dictionary = illustration.scene_report()
		_expect(bool(scene.get("ready", false)) and scene.get("errors", []).is_empty(),
			"ending: dedicated return layers did not load: %s" % str(scene), failures)
		_expect(scene.get("story_state", "") == "early_return_unrepaired" and not bool(scene.get("final_e03_repair", true)),
			"ending: Auto graduation falsely implied the final repair", failures)
		_expect(scene.get("layers", []).size() == 2 and scene.get("effects", []).size() == 4,
			"ending: expected bench + ranger layers and Mira/Leia work loops plus two effects", failures)
		var feet := {}
		for layer: Dictionary in scene.get("layers", []):
			feet[layer.id] = layer.feet
		for effect: Dictionary in scene.get("effects", []):
			feet[String(effect.get("id", ""))] = effect.feet
		_expect(feet.get("return.mira") == Vector2i(296, 189)
			and feet.get("return.bench") == Vector2i(235, 225)
			and feet.get("return.leia") == Vector2i(237, 254)
			and feet.get("ranger.east.idle") == Vector2i(124, 293),
			"ending: the concept-derived staging or foot anchors drifted", failures)
		illustration.set_review_time(0.0)
		var first_effects: Array = illustration.scene_report().get("effects", [])
		illustration.set_review_time(0.5)
		_expect(first_effects != illustration.scene_report().get("effects", []),
			"ending: fire/steam did not advance", failures)
		illustration.set_review_time(2.0)
		_expect(first_effects == illustration.scene_report().get("effects", []),
			"ending: the shared two-second loop did not close", failures)
		_expect(illustration.load_scene() and illustration.scene_report().get("layers", []).size() == 2,
			"ending: repeated loading duplicated static layers", failures)
	var boundary: Label = screen.find_child("ReturnStoryBoundary", true, false)
	_expect(boundary != null and boundary.text.contains("wind is still cold") and boundary.text.contains("connections need tending"),
		"ending: the early-return caption falsely advanced the repair", failures)
	var caption: Label = screen.find_child("EndingIllustrationCaption", true, false)
	_expect(caption != null and caption.text == "Hamlet · Hearthside", "ending: the illustration lost its place caption", failures)

	# --- the summary is read back from the payload that was handed over ---
	_expect(String(screen.get_presented_result().get("contract_id", "")) == "auto_certification"
		and int((screen.get_presented_result().get("rewards", {}) as Dictionary).get("equipment_drop_count", 0)) == 2,
		"ending: the presented result is not readable from the screen", failures)
	_expect(int((screen.get_presented_profile().get("progression", {}) as Dictionary).get("contract_wins", 0)) == 7,
		"ending: the presented profile is not readable from the screen", failures)

	# --- pinned footer, one scrolling middle, nothing past the sides, no copy under
	#     the approved text floor ---
	await _frames(4)
	var bounds := Rect2(Vector2.ZERO, screen.size)
	var header: Control = screen.find_child("EndingHeader", true, false)
	var footer: Control = screen.find_child("EndingFooter", true, false)
	var scroll: ScrollContainer = screen.find_child("EndingScroll", true, false)
	_expect(screen.size == Vector2(1280.0, 720.0), "ending: the screen did not take the 1280x720 shell canvas: %s" % str(screen.size), failures)
	_expect(bounds.encloses(header.get_global_rect()), "ending: the header left the screen: %s" % str(header.get_global_rect()), failures)
	_expect(bounds.encloses(footer.get_global_rect()), "ending: the actions are not reachable on screen: %s" % str(footer.get_global_rect()), failures)
	_expect(bounds.encloses(scroll.get_global_rect()), "ending: the scrolling body left the screen", failures)
	_expect(header.get_global_rect().position.y + header.get_global_rect().size.y <= scroll.get_global_rect().position.y + EDGE_EPSILON,
		"ending: the body overlaps the header", failures)
	_expect(scroll.get_global_rect().position.y + scroll.get_global_rect().size.y <= footer.get_global_rect().position.y + EDGE_EPSILON,
		"ending: the body overlaps the footer", failures)
	_expect(scroll.get_h_scroll_bar().max_value <= scroll.size.x + EDGE_EPSILON, "ending: the body can scroll sideways", failures)
	for label in _visible_labels(screen):
		var font_size := label.get_theme_font_size("font_size")
		_expect(font_size >= FONT_FLOOR, "ending: %s is drawn at %dpx, under the %dpx floor" % [label.name, font_size, FONT_FLOOR], failures)
	for control in _visible_controls(screen):
		var rect := control.get_global_rect()
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			continue
		_expect(rect.position.x >= -EDGE_EPSILON and rect.position.x + rect.size.x <= screen.size.x + EDGE_EPSILON,
			"ending: %s reaches past the screen horizontally: %s" % [control.name, str(rect)], failures)
	for selector in ["EndingTitle", "EndingCopy", "EndingSummaryPanel", "EndingProfileSummary", "EndingResultSummary", "MidgamePanel", "MidgamePreview", "EndingIllustration", "EndingFooter", "ReturnToBaseButton", "ReturnToTitleButton"]:
		_expect(screen.find_child(selector, true, false) != null, "ending: the stable selector %s is missing" % selector, failures)
	_expect((screen.find_child("ReturnToBaseButton", true, false) as Button).visible
		and (screen.find_child("ReturnToTitleButton", true, false) as Button).visible,
		"ending: one of the two return actions is hidden", failures)

	# --- the plate stays a column of the page, not the page: the graduation numbers
	#     are beside it and visible without scrolling on the shell canvas ---
	var body_row: BoxContainer = screen.find_child("EndingBodyRow", true, false)
	var summary_panel: Control = screen.find_child("EndingSummaryPanel", true, false)
	_expect(scroll.get_v_scroll_bar().get_theme_stylebox("scroll") is StyleBoxEmpty
		and scroll.get_v_scroll_bar().get_theme_stylebox("grabber") is StyleBoxEmpty,
		"ending: passive page scrollbar chrome should be hidden", failures)
	_expect(body_row != null and not body_row.vertical, "ending: the summary did not sit beside the illustration at 1280px", failures)
	_expect(scroll.get_global_rect().encloses(summary_panel.get_global_rect()),
		"ending: the graduation numbers fell below the fold: %s in %s" % [str(summary_panel.get_global_rect()), str(scroll.get_global_rect())], failures)
	_expect(scroll.get_global_rect().encloses(illustration.get_global_rect()),
		"ending: the illustration is not fully visible on the shell canvas", failures)

	# --- a 1024px view stacks the two blocks and scrolls instead of squeezing them ---
	var host := Control.new()
	host.name = "EndingNarrowHost"
	host.size = Vector2(1024.0, 576.0)
	root.add_child(host)
	var narrow = EndingScreenScript.new()
	host.add_child(narrow)
	narrow.present({"initial_class": "ranger", "progression": {"contract_wins": 7, "auto_contract_wins": 1}}, {
		"outcome": "final_victory", "contract_id": "auto_certification", "mode": "Auto", "ticks": 14,
		"elapsed_seconds": 0.47, "rewards": {"equipment_drop_count": 2},
	})
	await _frames(4)
	var narrow_row: BoxContainer = narrow.find_child("EndingBodyRow", true, false)
	var narrow_scroll: ScrollContainer = narrow.find_child("EndingScroll", true, false)
	var narrow_footer: Control = narrow.find_child("EndingFooter", true, false)
	_expect(narrow_row != null and narrow_row.vertical, "ending: a 1024px view did not stack the plate and the summary", failures)
	_expect(narrow_scroll.get_global_rect().encloses(narrow_footer.get_global_rect()) == false
		and Rect2(host.global_position, host.size).encloses(narrow_footer.get_global_rect()),
		"ending: the actions left the small view: %s" % str(narrow_footer.get_global_rect()), failures)
	_expect(narrow_scroll.get_v_scroll_bar().max_value > narrow_scroll.size.y,
		"ending: the stacked small view is not scrollable (max %s page %s)" % [str(narrow_scroll.get_v_scroll_bar().max_value), str(narrow_scroll.size.y)], failures)
	host.remove_child(narrow)
	narrow.free()
	host.queue_free()

	root.remove_child(screen)
	screen.free()
	if failures.is_empty():
		print("PASS  test_ending_screen.gd")
		quit(0)
		return
	for failure in failures:
		printerr("- %s" % failure)
	quit(1)


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)


func _frames(count: int) -> void:
	for _index in count:
		await process_frame


func _visible_labels(node: Node) -> Array[Label]:
	var found: Array[Label] = []
	for child in node.get_children():
		if child is Label and (child as Control).visible and not (child as Label).text.strip_edges().is_empty():
			found.append(child)
		found.append_array(_visible_labels(child))
	return found


func _visible_controls(node: Node) -> Array[Control]:
	var found: Array[Control] = []
	for child in node.get_children():
		if child is Control and (child as Control).visible:
			found.append(child)
		found.append_array(_visible_controls(child))
	return found
