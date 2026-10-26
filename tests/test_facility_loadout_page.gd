extends "res://tests/test_facility_screen.gd"


func _run() -> void:
	var failures: Array[String] = []
	var screen = FacilityScreenScript.new()
	var icon_fixture := _progression_icon_fixture()
	icon_fixture.load_icons()
	root.add_child(screen)
	await process_frame
	screen.set_progression_icons(icon_fixture)
	var actions: Array[Dictionary] = []
	screen.action_requested.connect(func(facility_id: String, action_id: String, payload: Dictionary) -> void:
		actions.append({"facility": facility_id, "action": action_id, "payload": payload.duplicate(true)})
	)
	var text: String = ""
	# The review-flow checks below index the accumulated action log (select,
	# equip, unequip), so replay the selection flow the original single _run
	# had already run before this section: the base snapshot presents and the
	# SelectBuild press, without repeating the head's assertions.
	var snapshot := _snapshot(false)
	screen.present("loadout", {}, {}, "", snapshot)
	screen.present("loadout", {}, {}, "candidate_not_selected", snapshot)
	screen.present("loadout", {}, {}, "", snapshot)
	var select_button: Button = screen.get_action_button("SelectBuild_exponential")
	if select_button != null:
		select_button.pressed.emit()
	var real_snapshot := _real_loadout_snapshot()
	screen.present("loadout", {}, {}, "", real_snapshot)
	var hidden_detail: Control = screen.backpack_detail()
	_expect(screen.find_child("EquipmentBackpack", true, false) != null
		and screen.backpack_cell("loot:bow/2") != null
		and hidden_detail != null and not hidden_detail.visible,
		"facility: compact backpack names or initial hidden-detail contract changed", failures)
	var hover_button := screen.find_child("BackpackItem_loot_bow_2", true, false) as Button
	if hover_button != null:
		hover_button.mouse_entered.emit()
		_expect(screen.backpack_detail().visible, "facility: mouse hover did not show shared equipment detail", failures)
		hover_button.mouse_exited.emit()
		await process_frame
		_expect(not screen.backpack_detail().visible, "facility: mouse exit did not hide shared equipment detail", failures)
		hover_button.focus_entered.emit()
		hover_button.mouse_exited.emit()
		await process_frame
		_expect(screen.backpack_detail().visible, "facility: keyboard/controller focus did not keep equipment detail visible", failures)
		hover_button.focus_exited.emit()
		await process_frame
		_expect(not screen.backpack_detail().visible, "facility: detail remained after both hover and focus ended", failures)
	else:
		failures.append("facility: stable BackpackItem_loot_bow_2 focus target is missing")
	text = screen.get_visible_text()
	_expect(not text.contains("Base: Ash Longbow") and not text.contains("Base: Swiftstring Recurve"),
		"facility: equipment long copy was instantiated on the initial backpack surface", failures)
	_focus_backpack_item(screen, "equipped_main")
	text = screen.get_visible_text()
	# The card surface is the player's own summary: the English slot, the base item and
	# the real modifiers in words. The raw slot id, instance id and internal modifiers
	# are one press away behind the card's own disclosure.
	_expect(text.contains("Main Hand · Base Ash Longbow") and text.contains("Carrier Damage: ×1.12")
		and text.contains("Piercing Arrow Continuation Chance Tier II") and text.contains("Rune Breeding Split") and text.contains("Law Pack Hunt Mark"),
		"facility: the current card lost its English slot, base item, readable modifiers, or rune and law", failures)
	_expect(not text.contains("instance_id: equipped_main") and not text.contains("Base modifiers: damage multiply 1.12"),
		"facility: raw item fields were pushed onto the current card's surface", failures)
	var current_summary: Label = screen.find_child("CurrentItemSummary_main_hand", true, false) as Label
	_expect(current_summary != null and current_summary.visible and current_summary.text.contains("Carrier Damage: ×1.12"),
		"facility: the current item's readable summary node is missing or wrong", failures)
	var current_full: Button = screen.get_action_button("FullItemDetails_equipped_main")
	_expect(current_full != null, "facility: equipped item has no complete player-readable detail action", failures)
	if current_full != null:
		current_full.grab_focus()
		current_full.pressed.emit()
		await _settle_frames()
		var current_dialog: AcceptDialog = screen.find_child("ItemDetailDialog", true, false) as AcceptDialog
		var current_dialog_text: Label = screen.find_child("ItemDetailText", true, false) as Label
		_expect(current_dialog != null and current_dialog.visible and current_dialog_text != null
			and current_dialog_text.text.contains("Ash Longbow") and current_dialog_text.text.contains("Carrier Damage: ×1.12")
			and not current_dialog_text.text.contains("instance_id") and not current_dialog_text.text.contains("family_id")
			and not current_dialog_text.text.contains("main_hand") and not current_dialog_text.text.contains("breeding_split"),
			"facility: equipped complete detail is missing readable facts or leaked internal fields", failures)
		if current_dialog != null:
			current_dialog.get_ok_button().pressed.emit()
			await _settle_frames()
			var owner := screen.get_viewport().gui_get_focus_owner()
			_expect(owner != null and owner.name == current_full.name,
				"facility: closing equipped complete detail did not restore its opener focus", failures)
	_expect(screen.get_action_button("CurrentItemFieldsToggle_main_hand") == null
		and screen.find_child("CurrentItemDetail_main_hand", true, false) == null,
		"facility: current-item internal fields escaped the test console", failures)
	text = screen.get_visible_text()
	# The page shows the current ranger himself beside the comparison: one published
	# action frame, drawn at an integer multiple of the 48px cell, named in words, and
	# stated to be the hero body rather than a paper doll.
	var portrait: Control = screen.find_child("LoadoutCharacterPortrait", true, false)
	_expect(portrait != null, "facility: the loadout page has no ranger preview", failures)
	var portrait_report: Dictionary = screen.character_preview_report()
	_expect(bool(portrait_report.get("present", false)) and bool(portrait_report.get("drawing", false)),
		"facility: the ranger preview drew nothing: %s" % str(portrait_report.get("notes", [])), failures)
	var portrait_cell: Array = portrait_report.get("cell", [])
	var portrait_anchor: Array = portrait_report.get("anchor", [])
	var portrait_scale := int(portrait_report.get("display_scale", 0))
	_expect(portrait_cell == [48, 48] and portrait_anchor == [24, 44],
		"facility: the ranger preview left the published 48x48 cell or its (24,44) foot anchor: %s / %s" % [str(portrait_cell), str(portrait_anchor)], failures)
	_expect(portrait_scale >= 3 and portrait_report.get("display_pixels") == [48 * portrait_scale, 48 * portrait_scale],
		"facility: the ranger preview is not an integer multiple of the published cell: %s" % str(portrait_report.get("display_pixels")), failures)
	_expect(String(portrait_report.get("clip", "")) == "ranger.east.idle" and int(portrait_report.get("frame", -1)) == 0,
		"facility: the ranger preview is not the published idle frame: %s" % String(portrait_report.get("clip", "")), failures)
	_expect(String(portrait_report.get("atlas_path", "")).contains("ranger_actions_v01"),
		"facility: the ranger preview did not read the published action atlas", failures)
	if portrait != null:
		_expect(portrait.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST,
			"facility: the ranger preview is not nearest-neighbour", failures)
		_expect(portrait.custom_minimum_size == Vector2(48 * portrait_scale, 48 * portrait_scale),
			"facility: the ranger preview box is not the integer multiple it reports", failures)
	const CHARACTER_COPY := "Current Ranger · White Hood · Longbow and Backpack; equipment changes stats, not the current appearance."
	_expect(not text.contains("48px Cells"),
		"facility: the loadout page lost its published ranger identity copy or exposed production specifications", failures)
	# The identity stays under the open equipment slots. The portrait column keeps its
	# authored art cell and its caption remains intentionally hidden.
	var slot_region: Control = screen.find_child("LoadoutSlotsRegion", true, false)
	var character_note: Label = screen.find_child("LoadoutCharacterDescription", true, false) as Label
	var character_caption: Control = screen.find_child("LoadoutCharacterCaption", true, false) as Control
	_expect(slot_region != null and character_note != null and character_note.is_visible_in_tree()
		and character_note.text == "Select a slot to compare and replace equipment in your backpack" and slot_region.is_ancestor_of(character_note),
		"facility: the ranger identity copy is not visible in the open-slot region", failures)
	_expect(character_caption == null or not character_caption.is_visible_in_tree(),
		"facility: the hidden character-column caption became visible", failures)
	if portrait != null:
		_expect(portrait.tooltip_text.contains("Current Ranger · White Hood · Longbow and Backpack")
			and portrait.tooltip_text.contains("Equipment changes stats, not the current appearance."),
			"facility: the hero portrait tooltip lost the appearance caption", failures)
	_expect(text.contains("Carrier Damage: ×1.12") and text.contains("Piercing Arrow Continuation Chance Tier II"),
		"facility: the real base modifier or affix tier was not readable on the card", failures)
	_focus_backpack_item(screen, "loot:bow/2")
	text = screen.get_visible_text()
	_expect(text.contains("Swiftstring Recurve") and text.contains("Projectile Speed: ×1.1")
		and screen.backpack_detail().visible,
		"facility: focused backpack item did not expose its one shared detail", failures)
	# The four open slots are the first thing on the page and the comparison sits
	# right under them; the resolved reference detail only appears once its own
	# toggle is pressed, so the first screen stays the decision.
	_expect(not text.contains("Final Stats"), "facility: reference detail pushed the working area past the first screen", failures)
	var off_hand_focus: Button = screen.get_action_button("SlotFocus_off_hand")
	_expect(off_hand_focus != null and not off_hand_focus.disabled, "facility: the per-slot focus control is missing", failures)
	if off_hand_focus != null:
		off_hand_focus.pressed.emit()
	_expect(screen.get_visible_text().contains("Off Hand\nUnequipped"),
		"facility: focusing an empty open slot did not show its exact unequipped detail", failures)
	var main_focus: Button = screen.get_action_button("SlotFocus_main_hand")
	if main_focus != null:
		main_focus.pressed.emit()
	_focus_backpack_item(screen, "loot:bow/2")
	text = screen.get_visible_text()
	_expect(screen.backpack_cell("equipped_main") != null and screen.backpack_cell("loot:bow/2") != null
		and text.contains("Swiftstring Recurve") and screen.get_action_button("Equip_loot_bow_2") != null,
		"facility: switching back to the first slot lost its current or candidate backpack cell", failures)
	# The eight unavailable slots live in the existing reference dialog; they do
	# not occupy inventory cells or expose equip actions on the decision surface.
	var slot_reference: Button = screen.get_action_button("ClosedSlotReferenceToggle")
	_expect(slot_reference != null and slot_reference.text == "Slot Details"
		and text.contains("Backpack and Progression") and screen.find_child("ClosedSlotRow", true, false) == null,
		"facility: closed slots did not move into the slot reference", failures)
	for slot: String in ["head", "chest", "pants", "leg_armor", "bracers", "belt", "ring_2", "necklace"]:
		_expect(screen.get_action_button("SlotFocus_" + slot) == null,
			"facility: unavailable slot offered a focus/equip action: " + slot, failures)
	if slot_reference != null:
		slot_reference.grab_focus()
		slot_reference.pressed.emit()
		await _settle_frames()
		var slot_dialog := screen.find_child("ItemDetailDialog", true, false) as AcceptDialog
		var slot_text := screen.find_child("ItemDetailText", true, false) as Label
		_expect(slot_dialog != null and slot_dialog.visible and slot_dialog.title == "All Slot Details"
			and slot_text != null and slot_text.text.contains("All 12 Slot States")
			and slot_text.text.count(": Available") == 4 and slot_text.text.count(": Unavailable") == 8,
			"facility: slot reference lost the complete open/closed state", failures)
		if slot_text != null:
			for name: String in ["Main Hand", "Off Hand", "Gloves", "Ring"]:
				_expect(slot_text.text.contains(name + ": Available"), "facility: open slot missing from reference: " + name, failures)
			for name: String in ["Head", "Chest", "Legs", "Feet", "Wrists", "Belt", "Ring", "Necklace"]:
				_expect(slot_text.text.contains(name + ": Unavailable"), "facility: locked slot missing from reference: " + name, failures)
		if slot_dialog != null:
			slot_dialog.get_ok_button().pressed.emit()
			await _settle_frames()
			_expect(screen.get_viewport().gui_get_focus_owner() == slot_reference,
				"facility: slot reference close did not restore opener focus", failures)
	var details_toggle: Button = screen.get_action_button("LoadoutDetailsToggle")
	_expect(details_toggle != null, "facility: the resolved detail toggle is missing", failures)
	if details_toggle != null:
		details_toggle.pressed.emit()
	_focus_backpack_item(screen, "loot:bow/2")
	text = screen.get_visible_text()
	_expect(text.contains("Piercing Arrow Continuation Chance: 61%") and text.contains("Shared Lineage Lifetime: 34 s")
		and text.contains("Projectile Speed: 682 units/s") and text.contains("Carrier Damage: 160") and text.contains("Maximum Health: 112"), "facility: resolved parameters were incomplete", failures)
	_expect(text.contains("Connected Interfaces: Breedable Child Arrows, Branch Target History") and text.contains("Missing Interfaces: Lineage Lifetime Pause")
		and not text.contains("breedable_event") and not text.contains("branch_target_history") and not text.contains("lineage_lifetime_pause"),
		"facility: resolved interface facts leaked raw ids or omitted their English names", failures)
	_expect(not text.contains("Build Fingerprint") and not text.contains("0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"),
		"facility: build fingerprint escaped the test console", failures)
	_expect(text.contains("Growth Classification: Unverified") and not text.contains("exponential") and not text.contains("Exponential"),
		"facility: unverified resolved Build leaked its growth classification", failures)
	_expect(not text.contains("Overall Power") and not text.contains("TTK") and not text.contains("Full Formula"), "facility: forbidden derived guidance leaked into loadout", failures)
	_expect(screen.get_action_button("SelectBuild_exponential") == null, "facility: real loadout still exposed a calibration preset button", failures)
	_expect(screen.get_action_button("Equip_equipped_main") == null, "facility: equipped item was offered as an equip action", failures)
	var equip_button: Button = screen.get_action_button("Equip_loot_bow_2")
	_expect(equip_button != null, "facility: candidate action node name is not stable or legal", failures)
	# The action stays visible as a short button; the visible decision block directly
	# above it names all numbers as future equipped-build changes.
	_expect(equip_button != null and equip_button.text == "Equip"
		and equip_button.tooltip_text == "Equip and Apply · Swiftstring Recurve",
		"facility: candidate equip action lost its player-facing label: %s" % ("none" if equip_button == null else "%s / %s" % [equip_button.text, equip_button.tooltip_text]), failures)
	var candidate_name: Label = screen.find_child("CandidateName_loot_bow_2", true, false) as Label
	_expect(candidate_name != null and candidate_name.visible and candidate_name.text == "Swiftstring Recurve"
		and not candidate_name.clip_text and candidate_name.autowrap_mode != TextServer.AUTOWRAP_OFF,
		"facility: the candidate's own name is not readable in full on its card", failures)
	_focus_backpack_item(screen, "equipped_main")
	var unequip_button: Button = screen.get_action_button("Unequip_main_hand")
	_expect(unequip_button != null and screen.get_action_button("Equip_loot_bow_2") == null,
		"facility: current-item detail did not replace candidate actions with stable unload action", failures)
	var unverified_preview_snapshot := _real_loadout_snapshot()
	var candidate_fingerprint := "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789"
	(unverified_preview_snapshot["equip_previews"] as Dictionary)["loot:bow/2"]["build_fingerprint"] = candidate_fingerprint
	(unverified_preview_snapshot["equip_previews"] as Dictionary)["loot:bow/2"]["growth_classification"] = "exponential"
	screen.present("loadout", {}, {}, "", unverified_preview_snapshot)
	_focus_backpack_item(screen, "loot:bow/2")
	var preview_summary: Label = screen.find_child("CandidatePreviewStateSummary_loot_bow_2", true, false) as Label
	var preview_state: Label = screen.find_child("CandidatePreviewStateDetail_loot_bow_2", true, false) as Label
	var preview_headline: Control = screen.find_child("CandidateHeadline_loot_bow_2", true, false) as Control
	var preview_actions: Control = screen.find_child("BackpackActions", true, false) as Control
	_expect(preview_summary != null and preview_summary.visible and preview_summary.text == "Unverified"
		and preview_headline != null and preview_actions != null and preview_summary.get_parent() == preview_headline
		and preview_headline.get_parent().get_index() < preview_actions.get_index(),
		"facility: unverified candidate lost its first-screen preview state", failures)
	_expect(preview_state == null and not preview_summary.tooltip_text.contains("Fingerprint")
		and preview_summary.tooltip_text.contains("has not passed Training; unknown does not mean failure"),
		"facility: compact unverified preview lost its reason or restored the old long surface", failures)
	var unverified_decision := screen.find_child("CandidateDecision_loot_bow_2", true, false) as GridContainer
	_expect(unverified_decision != null and unverified_decision.columns == 4
		and _comparison_text(unverified_decision).begins_with("Build Stats\nCurrent\nWhen Equipped\n"),
		"facility: comparison did not separate the current and replacement build columns", failures)
	_expect_comparison_row(unverified_decision, "Continuation Chance", "61%", "↓ 54%", ShellThemeScript.WARNING, failures)
	_expect_comparison_row(unverified_decision, "Arrow Speed", "682", "↑ 750.2", ShellThemeScript.PROXY, failures)
	var verified_preview_snapshot := unverified_preview_snapshot.duplicate(true)
	var candidate_reports := {}
	candidate_reports[candidate_fingerprint] = _training_report(candidate_fingerprint)
	(verified_preview_snapshot["training"] as Dictionary)["reports_by_fingerprint"] = candidate_reports
	screen.present("loadout", {}, {}, "", verified_preview_snapshot)
	_focus_backpack_item(screen, "loot:bow/2")
	preview_summary = screen.find_child("CandidatePreviewStateSummary_loot_bow_2", true, false) as Label
	preview_state = screen.find_child("CandidatePreviewStateDetail_loot_bow_2", true, false) as Label
	preview_headline = screen.find_child("CandidateHeadline_loot_bow_2", true, false) as Control
	preview_actions = screen.find_child("BackpackActions", true, false) as Control
	_expect(preview_summary != null and preview_summary.visible and preview_summary.text == "Verified"
		and preview_headline != null and preview_actions != null and preview_summary.get_parent() == preview_headline
		and preview_headline.get_parent().get_index() < preview_actions.get_index(),
		"facility: verified candidate lost its first-screen preview state", failures)
	_expect(preview_state == null and preview_summary.tooltip_text.contains("Sacred Law Preview: Verified")
		and preview_summary.tooltip_text.contains("Growth classification Exponential")
		and not preview_summary.tooltip_text.contains("Fingerprint") and not preview_summary.tooltip_text.contains("exponential"),
		"facility: compact verified preview lost its readable classification", failures)
	equip_button = screen.get_action_button("Equip_loot_bow_2")
	if equip_button != null:
		equip_button.pressed.emit()
	_expect(actions.size() == 2 and actions[1] == {"facility": "loadout", "action": "equip_item", "payload": {"instance_id": "loot:bow/2"}}, "facility: equip emitted the wrong action payload", failures)
	# The fixed surface keeps a compact decision. The complete authoritative preview
	# is available through the explicit detail dialog and remains player-readable.
	var candidate_preview: Label = screen.find_child("CandidatePreview_loot_bow_2", true, false) as Label
	_expect(candidate_preview == null, "facility: the retired long candidate preview returned to the fixed surface", failures)
	var preview_full: Button = screen.get_action_button("FullItemDetails_loot_bow_2")
	_expect(preview_full != null, "facility: the candidate's complete preview action is missing", failures)
	if preview_full != null:
		var candidate_actions := screen.find_child("BackpackActions", true, false)
		var candidate_facts := screen.find_child("CandidateSummary_loot_bow_2", true, false)
		var candidate_decision := screen.find_child("CandidateDecision_loot_bow_2", true, false) as GridContainer
		var candidate_facts_row := screen.find_child("CandidateFactsRow_loot_bow_2", true, false) as ScrollContainer
		_expect_comparison_row(candidate_decision, "Continuation Chance", "61%", "↓ 54%", ShellThemeScript.WARNING, failures)
		_expect(candidate_actions != null and candidate_facts_row != null and candidate_facts != null and candidate_decision != null
			and candidate_actions.get_index() < candidate_facts_row.get_index()
			and candidate_facts_row.is_ancestor_of(candidate_decision) and candidate_facts_row.is_ancestor_of(candidate_facts)
			and candidate_facts_row.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED,
			"facility: primary equip/detail actions must precede the locally scrolling comparison and item facts", failures)
		_expect(candidate_actions != null and candidate_actions.get_child_count() == 2
			and candidate_actions.find_child("Salvage_*", true, false) == null,
			"facility: the primary row must contain only equip and complete detail", failures)
		preview_full.pressed.emit()
		await _settle_frames()
		var preview_copy := (screen.find_child("ItemDetailText", true, false) as Label).text
		_expect(preview_copy.contains("Piercing Arrow Continuation Chance: 61% → 54%") and preview_copy.contains("Projectile Speed: 682 units/s → 750.2 units/s"),
			"facility: complete equip preview did not render changed parameters with signs", failures)
		_expect(preview_copy.contains("Interfaces Gained: Unknown Interface (quick_draw)") and preview_copy.contains("Interfaces Lost: Breedable Child Arrows, Branch Target History"),
			"facility: equip preview did not render gained or lost interfaces", failures)
		_expect(preview_copy.contains("Tags Gained: 1 items") and preview_copy.contains("Tags Lost: 1 items"),
			"facility: equip preview did not render gained or lost tags", failures)
		for term: String in ["Power", "TTK", "Range", "Recommended", "Formula"]:
			_expect(not preview_copy.contains(term), "facility: equip preview leaked forbidden copy '%s'" % term, failures)
		var preview_dialog := screen.find_child("ItemDetailDialog", true, false) as AcceptDialog
		if preview_dialog != null:
			preview_dialog.get_ok_button().pressed.emit()
			await _settle_frames()
	# Candidate cards keep only player-readable data; raw ids and modifier records
	# belong to the F10 test console.
	var candidate_fields: Label = screen.find_child("CandidateDetail_loot_bow_2", true, false) as Label
	_expect(candidate_fields == null,
		"facility: candidate internal fields escaped the test console", failures)
	var candidate_summary: Label = screen.find_child("CandidateSummary_loot_bow_2", true, false) as Label
	_expect(candidate_summary != null and candidate_summary.visible and candidate_summary.text.contains("Projectile Speed: ×1.1")
		and not candidate_summary.text.contains("instance_id"),
		"facility: the candidate lost its readable summary or leaked a raw id onto the surface", failures)
	var short_candidate_toggle: Button = screen.get_action_button("CandidateFieldsToggle_loot_bow_2")
	_expect(short_candidate_toggle == null,
		"facility: candidate raw-detail disclosure remained on the player page", failures)
	_focus_backpack_item(screen, "equipped_main")
	unequip_button = screen.get_action_button("Unequip_main_hand")
	if unequip_button != null:
		unequip_button.pressed.emit()
	_expect(actions.size() == 3 and actions[2] == {"facility": "loadout", "action": "unequip_item", "payload": {"slot": "main_hand"}}, "facility: unequip emitted the wrong action payload", failures)
	var previews_before: Dictionary = real_snapshot.equip_previews.duplicate(true)
	screen.present("loadout", {}, {}, "", real_snapshot)
	_focus_backpack_item(screen, "loot:bow/2")
	_expect(real_snapshot.equip_previews == previews_before, "facility: presenting a loadout mutated the caller's equip_previews", failures)
	var review_snapshot: Dictionary = _real_loadout_snapshot()
	review_snapshot["initial_focus"] = {
		"review_instance_id": "loot:bow/2",
		"focus_slot": "main_hand",
		"return_route": "result",
	}
	review_snapshot["return_route"] = "result"
	screen.present("loadout", {}, {}, "Drop located; compare it and decide whether to equip it.", review_snapshot)
	var review_back := screen.find_child("ReturnToBaseButton", true, false) as Button
	_expect(String(screen.get("_focus_slot")) == "main_hand"
		and screen.find_child("ReviewedDrop_loot_bow_2", true, false) != null
		and screen.backpack_cell("loot:bow/2") != null and screen.backpack_detail().visible
		and review_back != null and review_back.text == "Results" and review_back.tooltip_text == "Return to Results"
		and screen.get_visible_text().contains("This Run's Drop · Located"),
		"facility: result review context did not locate the exact candidate or preserve the return decision", failures)
	var review_refresh: Dictionary = _real_loadout_snapshot()
	review_refresh["return_route"] = "result"
	screen.present("loadout", {}, {}, "Equipped: This Run's Drop", review_refresh)
	review_back = screen.find_child("ReturnToBaseButton", true, false) as Button
	_expect(screen.find_child("ReviewedDrop_loot_bow_2", true, false) != null
		and review_back != null and review_back.text == "Results" and review_back.tooltip_text == "Return to Results",
		"facility: a domain refresh lost the active result-review destination", failures)
	screen.present("loadout", {}, {}, "", real_snapshot)
	review_back = screen.find_child("ReturnToBaseButton", true, false) as Button
	_expect(screen.find_child("ReviewedDrop_loot_bow_2", true, false) == null and review_back != null and review_back.text == "Hub" and review_back.tooltip_text == "Return to Hub",
		"facility: ordinary loadout retained stale result-review presentation state", failures)
	var fallback_snapshot: Dictionary = _real_loadout_snapshot()
	fallback_snapshot.erase("equip_previews")
	screen.present("loadout", {}, {}, "", fallback_snapshot)
	_focus_backpack_item(screen, "loot:bow/2")
	text = screen.get_visible_text()
	var fallback_summary := screen.find_child("CandidateSummary_loot_bow_2", true, false) as Label
	var fallback_decision := screen.find_child("CandidateDecision_loot_bow_2", true, false) as GridContainer
	_expect(fallback_summary != null and fallback_summary.text.contains("Projectile Speed: ×1.1")
		and fallback_decision != null and not _comparison_text(fallback_decision).contains("Stat Changes")
		and not _comparison_text(fallback_decision).contains("Interfaces Gained") and not _comparison_text(fallback_decision).contains("Interfaces Lost")
		and screen.find_child("CandidatePreview_loot_bow_2", true, false) == null,
		"facility: candidate without a preview must keep its readable summary with no preview copy", failures)
	_expect(_comparison_text(fallback_decision) == "No comparison available",
		"facility: missing comparison must be unknown, not unchanged or failed", failures)
	var unchanged_snapshot := _real_loadout_snapshot()
	unchanged_snapshot.equip_previews["loot:bow/2"] = {
		"ok": true, "final_parameters": unchanged_snapshot.resolved_build.final_parameters.duplicate(true),
	}
	screen.present("loadout", {}, {}, "", unchanged_snapshot)
	_focus_backpack_item(screen, "loot:bow/2")
	_expect(screen.get_visible_text().contains("Identical stat values"),
		"facility: an authoritative unchanged comparison must say so", failures)
	unchanged_snapshot.equip_previews["loot:bow/2"] = {"ok": true}
	screen.present("loadout", {}, {}, "", unchanged_snapshot)
	_focus_backpack_item(screen, "loot:bow/2")
	_expect(screen.get_visible_text().contains("No comparison available") and not screen.get_visible_text().contains("Identical stat values"),
		"facility: incomplete comparison must never claim unchanged", failures)
	# Nonempty dictionaries with no shared numeric attribute are still unknown.
	unchanged_snapshot.equip_previews["loot:bow/2"] = {"ok": true, "final_parameters": {"critical_chance": 0.08}}
	screen.present("loadout", {}, {}, "", unchanged_snapshot)
	_focus_backpack_item(screen, "loot:bow/2")
	_expect(screen.get_visible_text().contains("No comparison available") and not screen.get_visible_text().contains("Identical stat values"),
		"facility: disjoint parameter sets must not claim identical values", failures)

	# Reverse movement in an ordinary parameter and in turn time have opposite
	# benefit semantics; both must retain exact before/after values.
	var reverse_snapshot := _real_loadout_snapshot()
	reverse_snapshot.equip_previews["loot:bow/2"].final_parameters["v"] = 640.0
	reverse_snapshot.equip_previews["loot:bow/2"].final_parameters["turn"] = 0.12
	screen.present("loadout", {}, {}, "", reverse_snapshot)
	_focus_backpack_item(screen, "loot:bow/2")
	var reverse_grid := screen.find_child("CandidateDecision_loot_bow_2", true, false) as GridContainer
	_expect_comparison_row(reverse_grid, "Arrow Speed", "682", "↓ 640", ShellThemeScript.WARNING, failures)
	_expect_comparison_row(reverse_grid, "Turn Time", "0.16s", "↓ 0.12s", ShellThemeScript.PROXY, failures)
	reverse_snapshot.equip_previews["loot:bow/2"].final_parameters["turn"] = 0.20
	screen.present("loadout", {}, {}, "", reverse_snapshot)
	_focus_backpack_item(screen, "loot:bow/2")
	reverse_grid = screen.find_child("CandidateDecision_loot_bow_2", true, false) as GridContainer
	_expect_comparison_row(reverse_grid, "Turn Time", "0.16s", "↑ 0.2s", ShellThemeScript.WARNING, failures)
	var disabled_snapshot: Dictionary = _real_loadout_snapshot()
	disabled_snapshot.equip_previews = {
		"loot:bow/2": {"ok": false, "final_parameters": {"p": 0.01, "T": 1.0, "v": 1.0, "d": 1.0, "turn": 1.0, "damage": 1.0, "max_health": 1.0}},
	}
	screen.present("loadout", {}, {}, "", disabled_snapshot)
	_focus_backpack_item(screen, "loot:bow/2")
	text = screen.get_visible_text()
	_expect(text.contains("Projectile Speed: ×1.1")
		and _comparison_text(screen.find_child("CandidateDecision_loot_bow_2", true, false) as GridContainer) == "No comparison available",
		"facility: explicitly disabled equip preview leaked derived copy", failures)

	# A slot with nothing to compare against says so in one line and builds no empty
	# scroll region: an empty candidate list would push the comparison's own content out
	# of the frame for no content at all.
	var no_candidates: Dictionary = _real_loadout_snapshot()
	(no_candidates["inventory_equipment"] as Array).remove_at(1)
	screen.present("loadout", {}, {}, "", no_candidates)
	_focus_backpack_item(screen, "equipped_main")
	text = screen.get_visible_text()
	_expect(text.contains("No replacement candidates for this slot") and screen.find_child("EquipmentBackpack", true, false) != null,
		"facility: a slot without candidates built an empty scroll region or lost its no-candidate line", failures)
	_expect(screen.get_action_button("Unequip_main_hand") != null and screen.get_action_button("Equip_loot_bow_2") == null,
		"facility: a slot without candidates lost the current item's action or invented a candidate action", failures)

	# Candidate filters are presentation state shared by slot comparisons. A family
	# that does not exist in the next slot must clear, while the player's other filter
	# choices survive; a family that does exist must remain visible in both toggle
	# states rather than silently narrowing the list.
	var filter_snapshot := _real_loadout_snapshot()
	(filter_snapshot["affix_families"] as Dictionary)["maximum_health"] = {
		"id": "maximum_health", "name": "Maximum Health", "parameter": "max_health", "operation": "add", "tiers": [{"tier": 2, "value": 10.0}],
	}
	var filter_inventory := (filter_snapshot["inventory_equipment"] as Array)
	filter_inventory.append({"instance_id": "loot:bow/3", "base_item_id": "swift_recurve_bow", "slot": "main_hand", "affixes": [{"family_id": "piercing_continuation", "tier": 3}], "rune_id": "", "law_id": ""})
	filter_inventory.append({"instance_id": "loot:gloves/2", "base_item_id": "turnfeather_gloves", "slot": "gloves", "affixes": [{"family_id": "maximum_health", "tier": 2}], "rune_id": "", "law_id": ""})
	filter_inventory.append({"instance_id": "loot:ring/2", "base_item_id": "vitality_ring", "slot": "ring_1", "affixes": [{"family_id": "piercing_continuation", "tier": 2}], "rune_id": "", "law_id": ""})
	screen._focus_slot = "main_hand"
	screen._candidate_query.keyword = "Keep Keyword"
	screen._candidate_query.min_tier = 2
	screen.present("loadout", {}, {}, "", filter_snapshot)
	var family_filter: OptionButton = screen.find_child("CandidateFamilyFilter", true, false) as OptionButton
	var piercing_index := -1
	if family_filter != null:
		for index in family_filter.item_count:
			if String(family_filter.get_item_metadata(index)) == "piercing_continuation":
				piercing_index = index
				break
	if family_filter != null and piercing_index >= 0:
		family_filter.item_selected.emit(piercing_index)
	_expect(screen._candidate_query.family == "piercing_continuation", "facility: the family filter did not select a present family", failures)
	var gloves_focus := screen.get_action_button("SlotFocus_gloves")
	if gloves_focus != null:
		gloves_focus.pressed.emit()
	_expect(screen._candidate_query.family.is_empty() and screen._candidate_query.keyword == "Keep Keyword" and screen._candidate_query.min_tier == 2,
		"facility: switching to a slot without the filtered family did not clear only that family filter", failures)
	var cleared_filter_toggle := screen.get_action_button("CandidateFiltersToggle")
	_expect(cleared_filter_toggle != null and not cleared_filter_toggle.tooltip_text.contains("Piercing Arrow Continuation Chance"),
		"facility: the open filter toggle still named the cleared family", failures)
	screen._candidate_query.family = "piercing_continuation"
	screen._candidate_query.keyword = "Vitality"
	screen._candidate_query.min_tier = 2
	var ring_focus := screen.get_action_button("SlotFocus_ring_1")
	if ring_focus != null:
		ring_focus.pressed.emit()
	_expect(screen._candidate_query.family == "piercing_continuation" and screen._candidate_query.keyword == "Vitality" and screen._candidate_query.min_tier == 2,
		"facility: switching to a slot with the filtered family lost an active filter", failures)
	var retained_filter_toggle := screen.get_action_button("CandidateFiltersToggle")
	_expect(retained_filter_toggle != null and retained_filter_toggle.text.contains("Filter")
		and retained_filter_toggle.tooltip_text.contains("Affix family: Piercing Arrow Continuation Chance"),
		"facility: the open filter toggle hid the active family name", failures)
	if retained_filter_toggle != null:
		retained_filter_toggle.pressed.emit()
	retained_filter_toggle = screen.get_action_button("CandidateFiltersToggle")
	_expect(retained_filter_toggle != null and retained_filter_toggle.text.contains("Filter")
		and retained_filter_toggle.tooltip_text.contains("Affix family: Piercing Arrow Continuation Chance"),
		"facility: the collapsed filter toggle hid the active family name", failures)
	screen._candidate_query.family = ""
	screen._candidate_query.keyword = "Vitality"
	screen._candidate_query.min_tier = 2
	screen._candidate_query.requires_rune = true
	screen._candidate_query.requires_law = true
	screen._candidate_query.requires_salvage = true
	screen._candidate_query.sort = "highest_tier"
	screen.present("loadout", {}, {}, "", filter_snapshot)
	var complete_filter_toggle := screen.get_action_button("CandidateFiltersToggle")
	_expect(complete_filter_toggle != null and complete_filter_toggle.tooltip_text.contains("Keyword: Vitality")
		and complete_filter_toggle.tooltip_text.contains("Minimum tier: Tier II")
		and complete_filter_toggle.tooltip_text.contains("With Rune") and complete_filter_toggle.tooltip_text.contains("With Law")
		and complete_filter_toggle.tooltip_text.contains("Salvageable") and complete_filter_toggle.tooltip_text.contains("sort: Highest Affix Tier"),
		"facility: the collapsed filter toggle omitted an active filter or sort", failures)
	_expect(screen.get_visible_text().contains("Click Reset to view all"),
		"facility: an empty filtered candidate list did not point back to folded filters", failures)
	screen._candidate_query.family = ""
	screen._candidate_query.keyword = ""
	screen._candidate_query.min_tier = 0
	screen._candidate_query.requires_rune = false
	screen._candidate_query.requires_law = false
	screen._candidate_query.requires_salvage = false
	screen._candidate_query.sort = "name"
	screen._focus_slot = "main_hand"
	screen.present("loadout", {}, {}, "", _real_loadout_snapshot())

	# Long identifiers never return to the player page; readable names and actions
	# stay available while the full record is reserved for the test console.
	actions.clear()
	var long_id_snapshot := _real_loadout_snapshot()
	var long_id := "stress_drop_00_" + "0123456789abcdef".repeat(3)
	var long_item: Dictionary = (long_id_snapshot["inventory_equipment"] as Array)[0]
	long_item["instance_id"] = long_id
	long_item["affixes"] = [
		{"family_id": "piercing_continuation", "tier": 2},
		{"family_id": "piercing_continuation", "tier": 3},
	]
	(long_id_snapshot["active_build"]["equipped_item_ids"] as Dictionary)["main_hand"] = long_id
	screen.present("loadout", {}, {}, "", long_id_snapshot)
	_focus_backpack_item(screen, long_id)
	text = screen.get_visible_text()
	_expect(text.contains("Ash Longbow") and text.contains("Piercing Arrow Continuation Chance Tier II") and text.contains("Piercing Arrow Continuation Chance Tier III"),
		"facility: a long block lost the published English base name or affix names", failures)
	_expect(not text.contains(long_id) and not text.contains("Base modifiers: damage multiply 1.12"),
		"facility: a long internal record was pushed onto the player page", failures)
	var fields_toggle: Button = screen.get_action_button("CurrentItemFieldsToggle_main_hand")
	_expect(fields_toggle == null and screen.get_action_button("Unequip_main_hand") != null,
		"facility: a long internal record exposed a disclosure or lost the real action", failures)

	# A candidate with many internal entries follows the same boundary.
	var wide_snapshot := _real_loadout_snapshot()
	(wide_snapshot["base_items"] as Dictionary)["stress_wide_bow"] = {
		"id": "stress_wide_bow",
		"name": "Long-Inscribed Bow",
		"slot": "main_hand",
		"modifiers": [
			{"parameter": "damage", "operation": "multiply", "value": 1.2},
			{"parameter": "v", "operation": "multiply", "value": 1.1},
			{"parameter": "T", "operation": "add", "value": 2.0},
		],
	}
	(wide_snapshot["inventory_equipment"] as Array)[1]["base_item_id"] = "stress_wide_bow"
	(wide_snapshot["inventory_equipment"] as Array)[1]["affixes"] = [
		{"family_id": "piercing_continuation", "tier": 3},
		{"family_id": "piercing_continuation", "tier": 4},
	]
	screen.present("loadout", {}, {}, "", wide_snapshot)
	_focus_backpack_item(screen, "loot:bow/2")
	text = screen.get_visible_text()
	_expect(text.contains("Long-Inscribed Bow") and text.contains("Piercing Arrow Continuation Chance Tier III") and text.contains("Piercing Arrow Continuation Chance Tier IV")
		and text.contains("Build Stats") and text.contains("When Equipped"),
		"facility: a wide candidate block did not keep its compact Chinese facts or decision", failures)
	_expect(not text.contains("damage multiply 1.2") and not text.contains("instance_id: "),
		"facility: the compact candidate surface exposed internal fields", failures)
	_expect(not text.contains("instance_id: loot:bow/2") and not text.contains("instance_id: equipped_main")
		and screen.get_action_button("Equip_loot_bow_2") != null,
		"facility: a candidate pushed its raw id onto the surface, or lost its own action", failures)
	var candidate_toggle: Button = screen.get_action_button("CandidateFieldsToggle_loot_bow_2")
	_expect(candidate_toggle == null and not text.contains("instance_id: loot:bow/2")
		and not text.contains("damage multiply 1.2"),
		"facility: a wide candidate leaked internal fields or a raw disclosure", failures)
	var candidate_full: Button = screen.get_action_button("FullItemDetails_loot_bow_2")
	_expect(candidate_full != null, "facility: candidate has no complete player-readable detail action", failures)
	if candidate_full != null:
		candidate_full.grab_focus()
		candidate_full.pressed.emit()
		await _settle_frames()
		var candidate_dialog_text: Label = screen.find_child("ItemDetailText", true, false) as Label
		_expect(candidate_dialog_text != null and candidate_dialog_text.text.contains("Long-Inscribed Bow")
			and candidate_dialog_text.text.contains("Piercing Arrow Continuation Chance Tier III")
			and candidate_dialog_text.text.contains("Piercing Arrow Continuation Chance: 61% → 54%")
			and not candidate_dialog_text.text.contains("instance_id") and not candidate_dialog_text.text.contains("family_id")
			and not candidate_dialog_text.text.contains("main_hand") and not candidate_dialog_text.text.contains("piercing_continuation"),
			"facility: candidate complete detail is incomplete or leaked internal fields", failures)
		var item_dialog := screen.find_child("ItemDetailDialog", true, false) as AcceptDialog
		if item_dialog != null:
			item_dialog.get_ok_button().pressed.emit()
			await _settle_frames()
			var owner := screen.get_viewport().gui_get_focus_owner()
			_expect(owner != null and owner.name == candidate_full.name,
				"facility: closing candidate complete detail did not restore its opener focus", failures)
	var real_fingerprint := String(real_snapshot.resolved_build.build_fingerprint)
	var real_reports := {}
	real_reports[real_fingerprint] = _training_report(real_fingerprint)
	real_snapshot.training.reports_by_fingerprint = real_reports
	screen.present("loadout", {}, {}, "", real_snapshot)
	_expect(screen.get_visible_text().contains("Growth Classification: Exponential"),
		"facility: trained resolved Build did not reveal its growth classification", failures)

	actions.clear()
	var salvage_snapshot: Dictionary = _salvage_snapshot()
	screen.present("loadout", {}, {}, "", salvage_snapshot)
	_focus_backpack_item(screen, "loot:bow/2")
	text = screen.get_visible_text()
	var salvage_add_button: Button = screen.get_action_button("Salvage_loot_bow_2")
	_focus_backpack_item(screen, "loot:bow/3")
	var salvage_rewrite_button: Button = screen.get_action_button("Salvage_loot_bow_3")
	_focus_backpack_item(screen, "loot:bow/4")
	var salvage_refine_button: Button = screen.get_action_button("Salvage_loot_bow_4")
	_expect(salvage_add_button != null and salvage_add_button.text == "Salvage ×1" and salvage_add_button.tooltip_text == "Salvage into Inscribe Law Tokens x1"
		and salvage_rewrite_button != null and salvage_rewrite_button.text == "Salvage ×2" and salvage_rewrite_button.tooltip_text == "Salvage into Rewrite Law Tokens x2"
		and salvage_refine_button != null and salvage_refine_button.text == "Salvage ×1" and salvage_refine_button.tooltip_text == "Salvage into Refine Law Tokens x1",
		"facility: salvage buttons lost a track label, amount, or stable node name", failures)
	_focus_backpack_item(screen, "equipped_main")
	_expect(screen.get_action_button("Salvage_equipped_main") != null,
		"facility: equipped starter item did not expose safeSalvage in its focused detail", failures)
	_focus_backpack_item(screen, "loot:bow/2")
	salvage_add_button = screen.get_action_button("Salvage_loot_bow_2")
	_expect(not text.contains("RecommendedSalvage") and not text.contains("Power"),
		"facility: salvage leaked recommendation or power copy", failures)
	var salvage_dialog: ConfirmationDialog = screen.find_child("SalvageConfirmation", true, false) as ConfirmationDialog
	_expect(salvage_dialog != null, "facility: salvage confirmation dialog has no stable node name", failures)
	if salvage_add_button != null:
		salvage_add_button.pressed.emit()
	_expect(actions.is_empty(), "facility: opening the salvage confirmation emitted an action before confirm", failures)
	if salvage_dialog != null:
		_expect(salvage_dialog.visible and salvage_dialog.dialog_text.contains("Salvaging: Swiftstring Recurve")
			and salvage_dialog.dialog_text.contains("Main Hand · No Affixes")
			and salvage_dialog.dialog_text.contains("Inscribe Law Tokens x1") and salvage_dialog.dialog_text.contains("irreversible")
			and not salvage_dialog.dialog_text.contains("instance_id") and not salvage_dialog.dialog_text.contains("loot:bow/2"),
			"facility: salvage confirmation lost its readable identity, return, irreversibility, or exposed an internal id", failures)
		salvage_dialog.canceled.emit()
	_expect(actions.is_empty(), "facility: cancelling the salvage confirmation emitted an action", failures)
	if salvage_add_button != null:
		salvage_add_button.pressed.emit()
	if salvage_dialog != null:
		salvage_dialog.confirmed.emit()
	_expect(actions.size() == 1 and actions[0] == {"facility": "loadout", "action": "salvage_item", "payload": {"instance_id": "loot:bow/2"}},
		"facility: confirmed salvage emitted the wrong action payload", failures)
	if salvage_dialog != null:
		salvage_dialog.confirmed.emit()
	_expect(actions.size() == 1, "facility: a repeated confirmation emitted the salvage action twice", failures)
	if salvage_add_button != null:
		salvage_add_button.pressed.emit()
	screen.present("loadout", {}, {}, "", salvage_snapshot)
	_focus_backpack_item(screen, "loot:bow/2")
	if salvage_dialog != null:
		_expect(not salvage_dialog.visible, "facility: presenting kept the salvage dialog open", failures)
		salvage_dialog.confirmed.emit()
	_expect(actions.size() == 1, "facility: a pending salvage survived present/rebuild", failures)

	var invalid_salvage: Dictionary = _salvage_snapshot()
	invalid_salvage["salvage_previews"] = {
		"loot:bow/2": {"ok": false, "operation": "inscribe", "amount": 1},
		"loot:bow/3": {"ok": true, "operation": "burn", "amount": 1},
		"loot:bow/4": {"ok": true, "operation": "inscribe", "amount": 0},
		"loot:bow/5": {"ok": true, "operation": "inscribe", "amount": 1},
	}
	(invalid_salvage["inventory_equipment"] as Array).append(
		{"instance_id": "loot:bow/5", "base_item_id": "swift_recurve_bow", "slot": "main_hand", "affixes": [], "rune_id": "", "law_id": "", "protected": true}
	)
	screen.present("loadout", {}, {}, "", invalid_salvage)
	var invalid_salvage_actions := true
	for invalid_id in ["loot:bow/2", "loot:bow/3", "loot:bow/4", "loot:bow/5"]:
		_focus_backpack_item(screen, invalid_id)
		invalid_salvage_actions = invalid_salvage_actions and screen.get_action_button("Salvage_%s" % invalid_id.replace(":", "_").replace("/", "_")) == null
	_expect(invalid_salvage_actions,
		"facility: ok:false, bad track, bad amount, or protected candidates exposed a salvage button", failures)
	_focus_backpack_item(screen, "loot:bow/5")
	_expect(screen.get_action_button("Equip_loot_bow_5") != null,
		"facility: a protected candidate lost its ordinary equip action", failures)

	var fallback_salvage: Dictionary = _salvage_snapshot()
	fallback_salvage.erase("salvage_previews")
	screen.present("loadout", {}, {}, "", fallback_salvage)
	_focus_backpack_item(screen, "loot:bow/2")
	text = screen.get_visible_text()
	_expect(not text.contains("Salvage into") and screen.get_action_button("Salvage_loot_bow_2") == null,
		"facility: a snapshot without salvage_previews still exposed salvage actions", failures)

	var isolation_salvage: Dictionary = _salvage_snapshot()
	var salvage_isolation_before: Dictionary = isolation_salvage.duplicate(true)
	screen.present("loadout", {}, {}, "", isolation_salvage)
	_focus_backpack_item(screen, "loot:bow/2")
	_expect(isolation_salvage == salvage_isolation_before, "facility: presenting a loadout mutated the caller's salvage snapshot", failures)
	root.remove_child(screen)
	screen.free()
	for child in root.get_children():
		child.free()
	await process_frame
	await process_frame
	_finish(failures, "test_facility_loadout_page.gd")
