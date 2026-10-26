extends "res://tests/test_facility_screen.gd"


func _run() -> void:
	var failures: Array[String] = []
	await _run_layout_checks(failures)
	# Subwindows and their text resources leave the tree on the next idle pass.
	# Let cleanup settle so an otherwise passing UI probe does not report engine
	# RID/ObjectDB leaks after the new bounded item-detail dialog was exercised.
	for child in root.get_children():
		child.free()
	await process_frame
	await process_frame
	_finish(failures, "test_facility_layout.gd")


## Layout checks. Every state is presented into a real logical viewport and then
## allowed to settle for a few frames before anything is measured, because
## containment, wrapping and scrollbar state only exist after a container sort.
## Nothing here drives gameplay: the only interaction is the salvage confirmation
## dialog, which is the thing under test.
func _run_layout_checks(failures: Array[String]) -> void:
	var host := Control.new()
	host.name = "LogicalViewport"
	# The logical frame under test is this host's rect, so the host has to be the frame:
	# a child that overflows it is clipped exactly as it would be in the game, and the
	# containment check measures against the same rect the page laid itself out for.
	host.clip_contents = true
	root.add_child(host)
	var screen = FacilityScreenScript.new()
	host.add_child(screen)
	var sizes: Array[Vector2] = [
		Vector2(1024, 576),
		Vector2(1280, 720),
		Vector2(1366, 768),
		Vector2(1600, 900),
		Vector2(1920, 1080),
		Vector2(1600, 1000),
	]
	var large := _large_inventory_snapshot(60)
	for size in sizes:
		host.size = size
		screen.present("loadout", {}, {}, "", large)
		await _settle_frames()
		var label := "loadout 60 items @%dx%d" % [int(size.x), int(size.y)]
		_check_logical_layout(screen, size, label, failures)
		var scroll: ScrollContainer = screen.find_child("FacilityCardsScroll", true, false)
		_expect(scroll != null, "facility layout %s: the workspace scroll region is missing" % label, failures)
		if scroll != null:
			_expect(scroll.get_h_scroll_bar().max_value <= scroll.size.x + 1.0,
				"facility layout %s: the workspace scrolls horizontally (%s vs %s)" % [label, scroll.get_h_scroll_bar().max_value, scroll.size.x], failures)
		var backpack = screen.find_child("EquipmentBackpack", true, false)
		var detail_region: Control = screen.find_child("BackpackDetail", true, false) as Control
		_expect(backpack != null and detail_region != null,
			"facility layout %s: compact backpack or shared detail region is missing" % label, failures)
		if backpack != null:
			_expect(backpack.has_method("page_count") and int(backpack.call("page_count")) > 1
				and backpack.find_child("EquipmentBackpackScroll", true, false) == null
				and backpack.find_child("BackpackPreviousPage", true, false) != null
				and backpack.find_child("BackpackNextPage", true, false) != null,
				"facility layout %s: a 60-item icon backpack is not reachable through fixed paging" % label, failures)
		_expect(detail_region != null and not detail_region.visible,
			"facility layout %s: equipment detail was visible before hover/focus" % label, failures)
		_focus_backpack_item(screen, "loot:bow/2")
		await _settle_frames()
		var report := screen.layout_report()
		var backpack_rect: Rect2 = report.get("backpack_rect", Rect2())
		var detail_rect: Rect2 = report.get("detail_rect", Rect2())
		var action_rect: Rect2 = report.get("action_rect", Rect2())
		_expect(detail_region != null and detail_region.visible
			and screen.get_action_button("Equip_loot_bow_2") != null
			and backpack_rect.has_area() and detail_rect.has_area() and action_rect.has_area(),
			"facility layout %s: focused detail, action, or reported rectangles are missing" % label, failures)
		if size in [Vector2(1280, 720), Vector2(1600, 900)] and detail_region != null:
			var readable_name := screen.find_child("CandidateName_loot_bow_2", true, false) as Label
			var readable_change := screen.find_child("CandidateDecision_loot_bow_2", true, false) as GridContainer
			var readable_facts := screen.find_child("CandidateSummary_loot_bow_2", true, false) as Label
			var complete_action := screen.get_action_button("FullItemDetails_loot_bow_2")
			_expect(readable_name != null and readable_name.text == "Swiftstring Recurve"
				and readable_change != null and _comparison_text(readable_change).begins_with("Build Stats\nCurrent\nWhen Equipped\n")
				and readable_facts != null and readable_facts.text.contains("Base Stats: ")
				and readable_facts.text.contains("Affixes")
				and complete_action != null and complete_action.text == "Details",
				"facility layout %s: focused pane facts name=%s change=%s facts=%s action=%s" % [label,
					"missing" if readable_name == null else readable_name.text,
					"missing" if readable_change == null else _comparison_text(readable_change),
					"missing" if readable_facts == null else readable_facts.text,
					"missing" if complete_action == null else complete_action.text], failures)
			var comparison_scroll := screen.find_child("CandidateFactsRow_loot_bow_2", true, false) as ScrollContainer
			_expect(comparison_scroll != null and comparison_scroll.is_ancestor_of(readable_change)
				and comparison_scroll.is_ancestor_of(readable_facts),
				"facility layout %s: comparison/facts left their local scroll" % label, failures)
			for required: Control in [readable_name, comparison_scroll, complete_action, screen.get_action_button("Equip_loot_bow_2")]:
				_expect(required != null and _inside_first_screen(required, size) and detail_rect.encloses(required.get_global_rect()),
					"facility layout %s: primary action or comparison viewport is clipped (%s, rect=%s, pane=%s)" % [label, "missing" if required == null else required.name, Rect2() if required == null else required.get_global_rect(), detail_rect], failures)
			var backpack_grid := backpack.find_child("EquipmentBackpackCells", true, false) as GridContainer
			_expect(backpack_grid != null and backpack_grid.columns == (2 if size.x == 1280 else 3),
				"facility layout %s: backpack did not reserve space with two/three columns" % label, failures)
			if comparison_scroll != null and readable_facts != null:
				comparison_scroll.ensure_control_visible(readable_facts)
				await _settle_frames()
				_expect(comparison_scroll.get_global_rect().intersects(readable_facts.get_global_rect())
					and _inside_first_screen(complete_action, size),
					"facility layout %s: local scroll lost facts or moved the primary action" % label, failures)

		if size == Vector2(1280, 720) and scroll != null:
			_expect(scroll.get_v_scroll_bar().max_value <= scroll.size.y + 1.0,
				"facility layout: 1280x720 loadout requires full-page vertical scrolling", failures)

	# The equipped pane keeps the two primary actions side by side and destructive
	# salvage on its own row. Every action remains inside the fixed detail surface.
	for size: Vector2 in [Vector2(1280, 720), Vector2(1600, 900)]:
		host.size = size
		screen.present("loadout", {}, {}, "", _salvage_snapshot())
		_focus_backpack_item(screen, "loot:bow/2")
		await _settle_frames()
		var candidate_detail := screen.backpack_detail() as Control
		var candidate_rect := candidate_detail.get_global_rect() if candidate_detail != null else Rect2()
		for action_name: String in ["Equip_loot_bow_2", "FullItemDetails_loot_bow_2", "Salvage_loot_bow_2"]:
			var candidate_action := screen.get_action_button(action_name)
			_expect(candidate_action != null and candidate_rect.encloses(candidate_action.get_global_rect()),
				"facility layout @%dx%d: candidate action %s is clipped (%s in %s)" % [int(size.x), int(size.y), action_name,
					"missing" if candidate_action == null else str(candidate_action.get_global_rect()), str(candidate_rect)], failures)
		_focus_backpack_item(screen, "equipped_main")
		await _settle_frames()
		var equipped_detail := screen.backpack_detail() as Control
		var equipped_rect := equipped_detail.get_global_rect() if equipped_detail != null else Rect2()
		for action_name: String in ["Unequip_main_hand", "FullItemDetails_equipped_main", "Salvage_equipped_main"]:
			var equipped_action := screen.get_action_button(action_name)
			_expect(equipped_action != null and equipped_rect.encloses(equipped_action.get_global_rect()),
				"facility layout @%dx%d: equipped action %s is clipped (%s in %s)" % [int(size.x), int(size.y), action_name,
					"missing" if equipped_action == null else str(equipped_action.get_global_rect()), str(equipped_rect)], failures)

	# Complete item data uses a readable adaptive modal. The page remains fixed;
	# overflow, when present, belongs only to the modal's named vertical scroll area.
	host.size = Vector2(1280, 720)
	screen.present("loadout", {}, {}, "", _salvage_snapshot())
	_focus_backpack_item(screen, "equipped_main")
	await _settle_frames()
	var full_equipped := screen.get_action_button("FullItemDetails_equipped_main")
	if full_equipped != null:
		full_equipped.pressed.emit()
	await _settle_frames()
	var item_dialog := screen.find_child("ItemDetailDialog", true, false) as AcceptDialog
	var item_scroll := screen.find_child("ItemDetailScroll", true, false) as ScrollContainer
	var item_copy := screen.find_child("ItemDetailText", true, false) as Label
	var modal_rect := Rect2(Vector2(item_dialog.position), Vector2(item_dialog.size)) if item_dialog != null else Rect2()
	_expect(item_dialog != null and item_dialog.visible and Rect2(Vector2.ZERO, host.size).encloses(modal_rect)
		and item_copy != null and item_copy.get_theme_font_size("font_size") >= 20
		and item_scroll != null and item_scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED
		and item_scroll.is_ancestor_of(item_copy)
		and item_copy.text.contains("Ash Longbow") and item_copy.text.contains("Slot: Main Hand")
		and item_copy.text.contains("Base Stats") and item_copy.text.contains("Piercing Arrow Continuation Chance Tier II")
		and item_copy.text.contains("Rune: Breeding Split") and item_copy.text.contains("Law: Pack Hunt Mark"),
		"facility layout: complete item modal is unbounded, undersized, externally scroll-backed, or missing item facts", failures)
	if item_dialog != null:
		item_dialog.get_ok_button().pressed.emit()
	await _settle_frames()
	var long_modal_snapshot := _salvage_snapshot()
	var long_modal_item := (long_modal_snapshot["inventory_equipment"] as Array)[0] as Dictionary
	var long_affixes: Array = []
	for _index in 12:
		long_affixes.append({"family_id": "piercing_continuation", "tier": 2})
	long_modal_item["affixes"] = long_affixes
	screen.present("loadout", {}, {}, "", long_modal_snapshot)
	_focus_backpack_item(screen, "equipped_main")
	await _settle_frames()
	full_equipped = screen.get_action_button("FullItemDetails_equipped_main")
	if full_equipped != null:
		full_equipped.pressed.emit()
	await _settle_frames()
	item_dialog = screen.find_child("ItemDetailDialog", true, false) as AcceptDialog
	item_scroll = screen.find_child("ItemDetailScroll", true, false) as ScrollContainer
	item_copy = screen.find_child("ItemDetailText", true, false) as Label
	var page_scroll := screen.find_child("FacilityCardsScroll", true, false) as ScrollContainer
	_expect(item_dialog != null and item_dialog.visible and item_scroll != null
		and item_scroll.get_v_scroll_bar().max_value > item_scroll.size.y + 1.0
		and item_copy != null and item_copy.text.count("Piercing Arrow Continuation Chance Tier II") == 12
		and page_scroll != null and page_scroll.get_v_scroll_bar().max_value <= page_scroll.size.y + 1.0,
		"facility layout: genuinely long complete details did not scroll only inside the modal or lost an affix", failures)
	if item_dialog != null:
		item_dialog.get_ok_button().pressed.emit()
	await _settle_frames()

	# Long names: the item name must survive whole on its own action button, and the
	# page must stay inside the viewport instead of widening.
	host.size = Vector2(1024, 576)
	var long_name := "White Ash Longbow · Experimental Workshop Edition · An Exceptionally Long Base Name for Testing Wrapping Boundaries"
	screen.present("loadout", {}, {}, "", _large_inventory_snapshot(4, long_name))
	_focus_backpack_item(screen, "loot:bow/2")
	await _settle_frames()
	_check_logical_layout(screen, host.size, "loadout long names @1024x576", failures)
	var long_equip: Button = screen.get_action_button("Equip_loot_bow_2")
	# The action button stays short; the item's own name is never shortened, it stays a
	# readable Label on the card that wraps instead of clipping.
	_expect(long_equip != null and long_equip.text == "Equip"
		and long_equip.tooltip_text == "Equip and Apply · %s" % long_name,
		"facility layout: a long item name was shortened on its action button (%s)" % ("none" if long_equip == null else "%s / %s" % [long_equip.text, long_equip.tooltip_text]), failures)
	var long_name_label: Label = screen.find_child("CandidateName_loot_bow_2", true, false) as Label
	_expect(long_name_label != null and long_name_label.visible and long_name_label.text == long_name
		and not long_name_label.clip_text and long_name_label.autowrap_mode != TextServer.AUTOWRAP_OFF,
		"facility layout: a long item name was shortened on the candidate's own label", failures)

	# A tall logical canvas mirrors the GPU art pass: every published cell the page
	# draws has to sit inside the frame at once, so no cell can hide behind a scroll.
	host.size = Vector2(1280, 2400)
	var tall_states: Array = [
		["loadout", _real_loadout_snapshot()],
		["forge", _forge_snapshot(true)],
		["training", _training_snapshot(true, _layout_fingerprint(), _training_report(_layout_fingerprint()))],
		["proxy", _proxy_unlocked_snapshot()],
	]
	for entry: Array in tall_states:
		screen.present(String(entry[0]), {}, {}, "", entry[1])
		await _settle_frames()
		var state := "%s tall frame" % String(entry[0])
		_check_logical_layout(screen, host.size, state, failures)
		_check_icon_frame(screen, host.size, state, failures)

	# Locked, unrevealed and revealed forge states at the smallest logical size.
	host.size = Vector2(1024, 576)
	screen.present("forge", {}, {}, "", _forge_snapshot(false))
	await _settle_frames()
	var text: String = screen.get_visible_text()
	_expect(text.contains("Law Token Forge Locked") and screen.get_action_button("ForgeReveal") == null,
		"facility layout: a locked forge listed commit candidates or lost its reason", failures)
	screen.present("forge", {}, {}, "", _forge_snapshot(true))
	await _settle_frames()
	text = screen.get_visible_text()
	var forge_reveal: Button = screen.get_action_button("ForgeReveal")
	_expect(forge_reveal != null and forge_reveal.text == "Forecast with Inscribe Law Tokens · No Tokens Spent Yet"
		and text.contains("No future has been forecast") and text.contains("Law Tokens"),
		"facility layout: the forge page lost its zero-spend foresight warning or law-token state", failures)
	_expect(screen.get_action_button("ForgePreviousAffix") == null and screen.get_action_button("ForgeNextAffix") == null
		and screen.find_child("ForgeStage1Title", true, false).text == "Step 1 · Choose"
		and screen.find_child("ForgeStage2Title", true, false).text == "Step 2 · Forecast and Commit",
		"facility layout: simplified target-and-operation step retained affix controls", failures)
	_check_logical_layout(screen, host.size, "forge unlocked @1024x576", failures)
	var short_law := _forge_snapshot(true, true, "candidate-2")
	short_law["law_tallies"] = {"inscribe": 2, "rewrite": 1, "refine": 2}
	(short_law["session"] as Dictionary)["affordable_count"] = 1
	screen.present("forge", {}, {}, "", short_law)
	await _settle_frames()
	var unaffordable: Button = screen.get_action_button("ForgeConfirmSelection")
	_expect(unaffordable != null and unaffordable.disabled and unaffordable.text.contains("Not Enough Law Tokens")
		and unaffordable.text.contains("Need 2") and unaffordable.text.contains("Have 1"),
		"facility layout: an unaffordable selected candidate did not show its needed and held law tallies", failures)
	_check_logical_layout(screen, host.size, "forge short law tally @1024x576", failures)

	screen.present("proxy", {}, {}, "", _proxy_unlocked_snapshot())
	await _settle_frames()
	_check_logical_layout(screen, host.size, "proxy unlocked @1024x576", failures)
	for proxy_size in [Vector2(1280, 720), Vector2(1366, 768), Vector2(1600, 900), Vector2(1920, 1080), Vector2(1600, 1000)]:
		host.size = proxy_size
		screen.present("proxy", {}, {}, "", _proxy_unlocked_snapshot())
		await _settle_frames()
		_check_logical_layout(screen, host.size, "proxy unlocked @%dx%d" % [int(proxy_size.x), int(proxy_size.y)], failures)

	# At the shipped resolution the whole decision is on the first screen in the
	# approved composition: one work row, the formal twelve-slot table and the hero in
	# its left column, the current item and its same-slot candidates in the right one,
	# and nothing leaving the frame sideways.
	host.size = Vector2(1280, 720)
	screen.present("loadout", {}, {}, "", _real_loadout_snapshot())
	_focus_backpack_item(screen, "loot:bow/2")
	await _settle_frames()
	_check_logical_layout(screen, host.size, "loadout decision @1280x720", failures)
	var work_row: Control = screen.find_child("LoadoutConceptRoot", true, false)
	var slots_region: Control = screen.find_child("LoadoutSlotsRegion", true, false)
	var hero_region: Control = screen.find_child("LoadoutHeroRegion", true, false)
	var locked_region: Control = screen.find_child("LoadoutLockedRegion", true, false)
	var compare_region: Control = screen.find_child("LoadoutCompareRegion", true, false)
	var strip: Control = screen.find_child("OpenSlotStrip", true, false)
	var closed: Control = screen.find_child("ClosedEquipmentSlots", true, false)
	var skill_strip: GridContainer = screen.find_child("LoadoutSkillStrip", true, false) as GridContainer
	var comparison: Control = screen.find_child("SlotCompareSection", true, false)
	var hero_panel: Control = screen.find_child("LoadoutCharacterPanel", true, false)
	var portrait: Control = screen.find_child("LoadoutCharacterPortrait", true, false)
	_expect(work_row != null and slots_region != null and hero_region != null and locked_region != null
		and compare_region != null and strip != null and closed != null and comparison != null
		and skill_strip != null and hero_panel != null and portrait != null,
		"facility layout: the concept regions, slot strip, skill strip, growth summary, comparison or hero is missing", failures)
	if slots_region != null and hero_region != null and locked_region != null and compare_region != null \
		and strip != null and closed != null and skill_strip != null and comparison != null and hero_panel != null and portrait != null:
		if strip.size.y > 150.0:
			printerr("STRIP DIAGNOSTIC @1280x720:\n%s" % _frame_report(work_row))
		# The loadout report is the page's own reading of the frame: the four regions it
		# names are the four regions the page laid out, in the shipped 1216x570 frame.
		var report: Dictionary = screen.layout_report()
		var frame_reading: Array = report.get("frame", [])
		_expect(frame_reading.size() == 2 and frame_reading[0] == 1216.0 and frame_reading[1] == 570.0,
			"facility layout: the loadout report does not name the shipped 1216x570 frame (%s)" % str(frame_reading), failures)
		var regions: Dictionary = report.get("regions", {})
		var origin := slots_region.get_global_rect().position
		for key: String in ["slots", "hero", "locked", "compare"]:
			var region_node: Control = {"slots": slots_region, "hero": hero_region, "locked": locked_region, "compare": compare_region}[key]
			var measured := Rect2(region_node.get_global_rect().position - origin, region_node.get_global_rect().size)
			_expect(_same_rect(measured, regions.get(key, Rect2())),
				"facility layout: the %s region is not the reported one (%s vs %s)" % [key, str(measured), str(regions.get(key, Rect2()))], failures)
		# Concept 10/03: the hero is right of the four slots on the same top edge. The
		# lower left starts with the two-column skill strip; closed equipment follows in
		# that lane while the comparison begins alongside the skills.
		_expect(hero_region.get_global_rect().position.x >= slots_region.get_global_rect().end.x and _same_top(hero_region, slots_region),
			"facility layout: the hero region is not right of the four slots on the same top edge (%s vs %s)" % [str(hero_region.get_global_rect()), str(slots_region.get_global_rect())], failures)
		_expect(portrait.get_global_rect().position.x >= strip.get_global_rect().end.x and _same_top(portrait, strip),
			"facility layout: the hero is not right of the four open slots on the same top edge (%s vs %s)" % [str(portrait.get_global_rect()), str(strip.get_global_rect())], failures)
		_expect(skill_strip.columns == 2 and _same_top(skill_strip, comparison)
			and closed.get_global_rect().position.y >= skill_strip.get_global_rect().end.y,
			"facility layout: skills are not the two-column start of the lower-left lane before locked slots (%s / %s / %s)" % [str(skill_strip.get_global_rect()), str(closed.get_global_rect()), str(comparison.get_global_rect())], failures)
	# Only the four usable slot cells belong on the surface. The complete twelve
	# slot state is checked in the existing reference dialog above.
	var slot_cells: Array[Node] = screen.find_children("LoadoutSlotCell_*", "PanelContainer", true, false)
	_expect(slot_cells.size() == 4, "facility layout: unavailable slot cells returned to the decision surface", failures)
	var open_row: GridContainer = screen.find_child("OpenSlotRow", true, false) as GridContainer
	_expect(open_row != null and open_row.get_child_count() == 4,
		"facility layout: usable slot strip lost one of the four open slots", failures)
	_expect(screen.find_child("ClosedSlotRow", true, false) == null,
		"facility layout: the retired eight-slot lock grid returned", failures)
	if open_row != null and open_row.get_child_count() > 0 and strip != null:
		var first_row_y: float = (open_row.get_child(0) as Control).get_global_rect().position.y
		for raw_cell: Node in open_row.get_children():
			var cell_rect: Rect2 = (raw_cell as Control).get_global_rect()
			if absf(cell_rect.position.y - first_row_y) > 1.0:
				failures.append("facility layout: the four open slots did not stay on one row (%s)" % str(cell_rect))
				break
			if not strip.get_global_rect().encloses(cell_rect):
				printerr("OPEN SLOT DIAGNOSTIC @1280x720:\n%s" % _frame_report(work_row))
				failures.append("facility layout: an open slot cell is outside the strip that shows it (%s)" % str(cell_rect))
				break
	# The return button is laid out in the header row: it has to keep its own text
	# width and one line of height, not collapse into an empty wrapped box.
	var base_button: Button = screen.get_action_button("ReturnToBaseButton")
	_expect(base_button != null and base_button.size.x >= 100.0 and base_button.size.y <= 64.0,
		"facility layout: the return-to-base button collapsed to %s" % ("none" if base_button == null else str(base_button.size)), failures)
	# The first screen keeps the fixed icon pages and one fixed summary/action pane.
	# Long item copy opens only in the explicit complete-detail dialog.
	var backpack: Control = screen.find_child("EquipmentBackpack", true, false)
	var backpack_detail: Control = screen.find_child("BackpackDetail", true, false)
	var current_cell: Control = screen.backpack_cell("equipped_main")
	var first_candidate_name: Control = screen.find_child("CandidateName_loot_bow_2", true, false)
	var first_candidate_cell: Control = screen.backpack_cell("loot:bow/2")
	var equip_in_frame: Button = screen.get_action_button("Equip_loot_bow_2")
	_expect(first_candidate_cell != null and backpack_detail != null and backpack_detail.is_ancestor_of(equip_in_frame),
		"facility layout: focused candidate action is not in the shared detail pane", failures)
	var first_screen_skills: Array[Control] = []
	for skill_node: Node in screen.find_children("SkillSummary_*", "Button", true, false):
		var skill_button := skill_node as Control
		if skill_button != null:
			first_screen_skills.append(skill_button)
	_expect(first_screen_skills.size() == 4,
		"facility layout: the loadout did not render four first-screen skill actions (%d)" % first_screen_skills.size(), failures)
	for skill_button: Control in first_screen_skills:
		var action := skill_button as Button
		var minimum := action.get_combined_minimum_size()
		_expect(action.autowrap_mode == TextServer.AUTOWRAP_OFF and action.text.count("\n") == 1
			and minimum.x <= action.size.x + 0.5 and minimum.y <= action.size.y + 0.5,
			"facility layout: %s cannot render its authored two lines inside the real button (%s minimum / %s actual / %s)" % [
				action.name, str(minimum), str(action.size), action.text.replace("\n", " / "),
			], failures)
	for node: Control in [strip, portrait, hero_panel, backpack, backpack_detail, current_cell, first_candidate_cell, first_candidate_name, equip_in_frame] + first_screen_skills:
		if node == null:
			failures.append("facility layout: the first-screen decision lost a required node")
		elif not _inside_first_screen(node, host.size):
			printerr("FIRST SCREEN DIAGNOSTIC @1280x720:\n%s" % _frame_report(work_row))
			failures.append("facility layout: %s is not inside the first screen and its own regions (%s)" % [node.name, str(node.get_global_rect())])
	if closed != null and locked_region != null:
		var locked_scroll := locked_region as ScrollContainer
		_expect(locked_scroll != null and locked_scroll.is_ancestor_of(closed),
			"facility layout: closed equipment is not available through the lower-left local scroll region", failures)
		if locked_scroll != null:
			locked_scroll.ensure_control_visible(closed)
			await _settle_frames()
			_expect(locked_scroll.get_global_rect().intersects(closed.get_global_rect()),
				"facility layout: local scrolling cannot reach the closed equipment section", failures)

	# The training page has to answer on the first screen: the four readable cards
	# first, then the matching report's numbers and its trace inside the same frame.
	screen.present("training", {}, {}, "", _training_snapshot(true, _layout_fingerprint(), _training_report(_layout_fingerprint())))
	await _settle_frames()
	var training_cards: Array[Control] = []
	for card_name: String in ["TrainingConclusionCard", "TrainingConnectedCard", "TrainingMissingCard", "TrainingNextStepCard"]:
		var card: Control = screen.find_child(card_name, true, false)
		_expect(card != null, "facility layout: the training page lost its %s" % card_name, failures)
		if card != null:
			training_cards.append(card)
	var training_trace_node: Control = screen.find_child("TrainingGrowthTrace", true, false)
	var training_reading: Label = screen.find_child("TrainingReading", true, false)
	var training_active: Control = screen.find_child("TrainingActiveBuild", true, false)
	var training_report_panel: Control = screen.find_child("TrainingLastReport", true, false)
	_expect(training_cards.size() == 4 and training_trace_node != null and training_reading != null
		and training_active != null and training_report_panel != null,
		"facility layout: the training first screen is incomplete", failures)
	if training_cards.size() == 4 and training_trace_node != null and training_reading != null:
		_expect(training_active.get_global_rect().position.x < training_report_panel.get_global_rect().position.x,
			"facility layout: the training report column moved in front of the build column", failures)
		_expect(training_cards[0].get_global_rect().position.y < training_cards[1].get_global_rect().position.y
			and training_cards[1].get_global_rect().position.y < training_cards[2].get_global_rect().position.y,
			"facility layout: the three build cards are not stacked in reading order", failures)
		_expect(training_reading.get_global_rect().position.y < training_trace_node.get_global_rect().position.y,
			"facility layout: the matching report's numbers are not above its trace", failures)
		for block: Control in [training_cards[0], training_cards[1], training_cards[2], training_cards[3], training_trace_node]:
			_expect(block.get_global_rect().end.y <= 720.0,
				"facility layout: %s ends at y=%0.1f, below the training first screen" % [block.name, block.get_global_rect().end.y], failures)
	_check_logical_layout(screen, host.size, "training @1280x720", failures)

	# At the smallest logical size the page scrolls vertically and never sideways.
	host.size = Vector2(1024, 576)
	screen.present("training", {}, {}, "", _training_snapshot(true, _layout_fingerprint(), _training_report(_layout_fingerprint())))
	await _settle_frames()
	_check_logical_layout(screen, host.size, "training @1024x576", failures)
	var training_scroll: ScrollContainer = screen.find_child("FacilityCardsScroll", true, false)
	if training_scroll != null:
		_expect(training_scroll.get_h_scroll_bar().max_value <= training_scroll.size.x + 1.0,
			"facility layout: the training page scrolls horizontally at 1024x576 (%s vs %s)" % [training_scroll.get_h_scroll_bar().max_value, training_scroll.size.x], failures)
	# The forge work row is the approved two columns: selection on the left and one
	# combined foresight/commit surface on the right. The footer keeps exactly one
	# primary action for the currently browsed authoritative state.
	host.size = Vector2(1280, 720)
	screen.present("forge", {}, {}, "", _forge_snapshot(true))
	await _settle_frames()
	var forge_workspace: ScrollContainer = screen.find_child("FacilityCardsScroll", true, false)
	if forge_workspace != null:
		forge_workspace.scroll_vertical = 0
	await _settle_frames()
	_check_logical_layout(screen, host.size, "forge @1280x720", failures)
	var operation_row: Control = screen.find_child("ForgeOperationRow", true, false)
	var operation_buttons: Array[Button] = []
	for operation: String in ["inscribe", "rewrite", "refine"]:
		operation_buttons.append(screen.get_action_button("ForgeOperation_%s" % operation))
	_expect(operation_row != null and operation_buttons.size() == 3,
		"facility layout: the three forge operation buttons are missing", failures)
	for operation_button in operation_buttons:
		if operation_button == null:
			continue
		_expect(operation_button.icon != null and operation_button.get_theme_font_size("font_size") >= 18
			and Rect2(Vector2.ZERO, host.size).encloses(operation_button.get_global_rect()),
			"facility layout: a law-token button lost its icon, readable text, or 1280x720 fit: %s (%s)" % [operation_button.name, str(operation_button.get_global_rect())], failures)
		_expect(operation_row.get_global_rect().encloses(operation_button.get_global_rect()),
			"facility layout: %s left the fixed three-column operation row: %s" % [operation_button.name, str(operation_button.get_global_rect())], failures)
		_expect(operation_button.autowrap_mode == TextServer.AUTOWRAP_OFF
			and operation_button.vertical_icon_alignment == VERTICAL_ALIGNMENT_TOP
			and operation_button.get_combined_minimum_size().x <= operation_button.size.x
			and operation_button.get_combined_minimum_size().y <= operation_button.size.y,
			"facility layout: the full operation name, count, and icon do not fit without splitting a word", failures)
	var forge_row: Control = screen.find_child("ForgeConceptRoot", true, false)
	var input_column: Control = screen.find_child("ForgeConceptRootColumn0", true, false)
	var decision_column: Control = screen.find_child("ForgeConceptRootColumn1", true, false)
	var retired_preview_column: Control = screen.find_child("ForgeConceptRootColumn2", true, false)
	var stage_one_title: Label = screen.find_child("ForgeStage1Title", true, false) as Label
	var stage_two_title: Label = screen.find_child("ForgeStage2Title", true, false) as Label
	var retired_stage_three_title: Label = screen.find_child("ForgeStage3Title", true, false) as Label
	var tracks: Control = screen.find_child("ForgeSetupPanel", true, false)
	var stock: Control = screen.find_child("ForgeInventorySection", true, false)
	var reveal_panel: Control = screen.find_child("ForgeRevealPanel", true, false)
	var browse_panel: Control = screen.find_child("ForgeBrowsePanel", true, false)
	_expect(input_column != null and decision_column != null and retired_preview_column == null,
		"facility layout: the forge is not the approved two-column work row", failures)
	_expect(tracks != null and stock != null and reveal_panel != null and browse_panel != null,
		"facility layout: a forge stage body is missing", failures)
	_expect(stage_one_title != null and stage_two_title != null and retired_stage_three_title == null,
		"facility layout: the forge stage titles are missing", failures)
	if stage_one_title != null and stage_two_title != null:
		var first_screen := Rect2(Vector2.ZERO, host.size)
		_expect(stage_one_title.text == "Step 1 · Choose" and stage_two_title.text == "Step 2 · Forecast and Commit",
			"facility layout: forge stages lost their two-stage terminology", failures)
		_expect(stage_one_title.is_visible_in_tree() and stage_two_title.is_visible_in_tree()
			and first_screen.encloses(stage_one_title.get_global_rect())
			and first_screen.encloses(stage_two_title.get_global_rect()),
			"facility layout: both forge stage titles are not visible without scrolling (%s / %s)" % [str(stage_one_title.get_global_rect()), str(stage_two_title.get_global_rect())], failures)
		_expect(stage_one_title.get_global_rect().position.x < stage_two_title.get_global_rect().position.x,
			"facility layout: forge stage titles are not in 1 / 2 reading order", failures)
	if input_column != null and decision_column != null and tracks != null and stock != null and reveal_panel != null and browse_panel != null:
		_expect(input_column.get_global_rect().end.x <= decision_column.get_global_rect().position.x,
			"facility layout: the forge columns are not selection then foresight/commit (%s / %s)" % [str(input_column.get_global_rect()), str(decision_column.get_global_rect())], failures)
		_expect(input_column.is_ancestor_of(stock) and input_column.is_ancestor_of(tracks)
			and decision_column.is_ancestor_of(reveal_panel) and decision_column.is_ancestor_of(browse_panel),
			"facility layout: selection and combined foresight/commit content are not in their own stages", failures)
		_expect(decision_column.get_global_rect().position.y <= 400.0 and input_column.get_global_rect().position.y <= 400.0,
			"facility layout: the forge work bench starts below the first screen (input y=%0.1f, decision y=%0.1f)" % [input_column.get_global_rect().position.y, decision_column.get_global_rect().position.y], failures)
	screen.present("forge", {}, {}, "", _forge_snapshot(true, true, "candidate-1"))
	await _settle_frames()
	var confirm_button: Button = screen.get_action_button("ForgeConfirmSelection")
	var cancel_button: Button = screen.get_action_button("ForgeCancelSelection")
	_expect(confirm_button != null and cancel_button != null
		and confirm_button.is_visible_in_tree() and cancel_button.is_visible_in_tree()
		and Rect2(Vector2.ZERO, host.size).encloses(confirm_button.get_global_rect())
		and Rect2(Vector2.ZERO, host.size).encloses(cancel_button.get_global_rect()),
		"facility layout: the forge's own confirm and cancel are not visible in the fixed footer (%s / %s)" % ["none" if confirm_button == null else str(confirm_button.get_global_rect()), "none" if cancel_button == null else str(cancel_button.get_global_rect())], failures)

	# A 1920x1080 window uses the full adaptive forge height while keeping the reading
	# lanes bounded to the 1600-class content width. Its report, composition and pinned
	# decision dock must all agree without horizontal scrolling.
	host.size = Vector2(1920, 1080)
	screen.present("forge", {}, {}, "", _forge_snapshot(true, true))
	await _settle_frames()
	var hd_report: Dictionary = screen.layout_report()
	var hd_rects: Array = hd_report.get("column_rects", [])
	var hd_workspace: ScrollContainer = screen.find_child("FacilityCardsScroll", true, false) as ScrollContainer
	var hd_body: Control = screen.find_child("FacilityBody", true, false) as Control
	_expect(hd_report.get("frame", []) == [1536.0, 900.0] and hd_rects.size() == 2,
		"facility layout: 1920x1080 forge did not report the bounded 1536x900 two-column frame", failures)
	if hd_body != null:
		var left_gutter := hd_body.get_global_rect().position.x
		var right_gutter := host.size.x - hd_body.get_global_rect().end.x
		_expect(hd_body.size.x <= FacilityLayoutScript.MAX_CONTENT_WIDTH
			and absf(left_gutter - right_gutter) <= FacilityScreenScript.SCROLLBAR_RESERVE,
			"facility layout: 1920x1080 body is not centred at the bounded reading width (%s; gutters %.1f / %.1f)" % [str(hd_body.get_global_rect()), left_gutter, right_gutter], failures)
	else:
		failures.append("facility layout: 1920x1080 body is missing")
	if hd_rects.size() == 2:
		var hd_left: Rect2 = hd_rects[0]
		var hd_right: Rect2 = hd_rects[1]
		_expect(not hd_left.intersects(hd_right) and hd_left.end.x <= hd_right.position.x,
			"facility layout: 1920x1080 forge columns overlap (%s / %s)" % [str(hd_left), str(hd_right)], failures)
	_expect(hd_workspace != null and hd_workspace.get_h_scroll_bar().max_value <= hd_workspace.size.x + 1.0,
		"facility layout: 1920x1080 forge gained horizontal scrolling", failures)
	var hd_viewport := Rect2(Vector2.ZERO, host.size)
	for action_name in ["ForgePreviousCandidate", "ForgeNextCandidate", "ForgeSelectCandidate", "ForgeCancelSelection"]:
		var hd_action: Button = screen.get_action_button(action_name)
		_expect(hd_action != null and hd_action.is_visible_in_tree() and hd_viewport.encloses(hd_action.get_global_rect()),
			"facility layout: 1920x1080 primary decision control %s left the visible viewport" % action_name, failures)
	screen.present("forge", {}, {}, "", _forge_snapshot(true, true, "candidate-1"))
	await _settle_frames()
	var hd_confirm: Button = screen.get_action_button("ForgeConfirmSelection")
	_expect(hd_confirm != null and screen.get_action_button("ForgeSelectCandidate") == null
		and hd_confirm.is_visible_in_tree() and hd_viewport.encloses(hd_confirm.get_global_rect()),
		"facility layout: 1920x1080 authoritative selection did not keep Confirm inside the visible viewport", failures)
	# The stock list is a fixed-height page. At the shipped resolution it sits inside
	# the logical frame; the smallest frame may move its owning lane, but the page never
	# gains its own ScrollContainer or leaves the frame sideways.
	for size: Vector2 in [Vector2(1024, 576), Vector2(1280, 720)]:
		host.size = size
		screen.present("forge", {}, {}, "", _forge_snapshot(true))
		await _settle_frames()
		var stock_page: Control = screen.find_child("EquipmentBackpack", true, false) as Control
		_expect(stock_page != null and stock_page.find_child("EquipmentBackpackScroll", true, false) == null,
			"facility layout: the forge stock fixed page is missing or still scroll-backed", failures)
		if stock_page != null:
			var stock_rect := stock_page.get_global_rect()
			if not stock_rect.position.x + stock_rect.size.x <= size.x + 1.0 or stock_rect.position.x < -1.0:
				printerr("FORGE SIDE DIAGNOSTIC at %dx%d:\n%s" % [int(size.x), int(size.y), _frame_report(screen.find_child("ForgeConceptRoot", true, false))])
				failures.append("facility layout: EquipmentBackpack leaves the frame sideways at %dx%d (%s)" % [int(size.x), int(size.y), str(stock_rect)])
			# The workbench columns are fixed-size lanes: a long target panel scrolls inside
			# its own column instead of growing the page, so sitting below the column's first
			# view is not an escape - but the region has to be reachable in the lane that owns
			# it, and one scroll to the bottom of that lane has to show it whole.
			var owner_column: ScrollContainer = screen.find_child("ForgeConceptRootColumn0BodyScroll", true, false) as ScrollContainer
			if owner_column != null and not owner_column.get_global_rect().encloses(stock_rect):
				var desired_scroll := owner_column.scroll_vertical + int(stock_rect.position.y - owner_column.get_global_rect().position.y)
				owner_column.scroll_vertical = clampi(desired_scroll, 0, int(owner_column.get_v_scroll_bar().max_value))
				await _settle_frames()
				stock_rect = stock_page.get_global_rect()
				var revealed := stock_page.get_global_rect().intersection(owner_column.get_global_rect())
				if revealed.size.y < stock_page.size.y - 1.0:
					printerr("FORGE REACH DIAGNOSTIC at %dx%d:\n%s" % [int(size.x), int(size.y), _frame_report(screen.find_child("ForgeConceptRoot", true, false))])
					failures.append("facility layout: the forge stock page cannot be brought fully into view inside its own column at %dx%d (%s vs %s)" % [int(size.x), int(size.y), str(stock_page.get_global_rect()), str(owner_column.get_global_rect())])
				owner_column.scroll_vertical = 0
				await _settle_frames()

	# Salvage confirmation: the dialog has to fit the logical viewport, identify the
	# clicked item in player terms, name the return, and emit nothing until confirmed.
	var actions: Array[Dictionary] = []
	screen.action_requested.connect(func(facility_id: String, action_id: String, payload: Dictionary) -> void:
		actions.append({"facility": facility_id, "action": action_id, "payload": payload.duplicate(true)})
	)
	screen.present("loadout", {}, {}, "", _salvage_snapshot())
	_focus_backpack_item(screen, "loot:bow/2")
	await _settle_frames()
	var salvage_button: Button = screen.get_action_button("Salvage_loot_bow_2")
	_expect(salvage_button != null, "facility layout: the salvage action is missing at 1024x576", failures)
	if salvage_button != null:
		salvage_button.pressed.emit()
	await _settle_frames()
	var dialog: ConfirmationDialog = screen.find_child("SalvageConfirmation", true, false)
	_expect(dialog != null and dialog.visible, "facility layout: the salvage confirmation did not open", failures)
	if dialog != null:
		_expect(dialog.dialog_text.contains("Salvaging: Swiftstring Recurve") and dialog.dialog_text.contains("Main Hand · No Affixes")
			and dialog.dialog_text.contains("Inscribe Law Tokens x1") and dialog.dialog_text.contains("irreversible")
			and not dialog.dialog_text.contains("instance_id") and not dialog.dialog_text.contains("loot:bow/2"),
			"facility layout: the salvage confirmation lost its readable identity, return or irreversibility, or exposed an internal id", failures)
		if dialog.visible and dialog.size.x > 0.0:
			_expect(dialog.size.x <= host.size.x,
				"facility layout: the salvage confirmation is wider than the logical viewport", failures)
		dialog.canceled.emit()
	await _settle_frames()
	_expect(actions.is_empty(), "facility layout: cancelling the salvage confirmation emitted an action", failures)
	root.remove_child(host)
	host.free()
