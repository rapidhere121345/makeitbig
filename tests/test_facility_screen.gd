extends SceneTree

const FacilityScreenScript = preload("res://src/presentation/facility_screen.gd")
const FacilityLayoutScript = preload("res://src/presentation/facility_layout.gd")
const BaseHubScreenTest = preload("res://tests/test_base_hub_screen.gd")
const LawForgeScript = preload("res://src/systems/law_forge.gd")
const ShellThemeScript = preload("res://src/presentation/shell_theme.gd")
const ProgressionIconsScript = preload("res://src/presentation/progression_icons.gd")


class ProgressionIconFixture extends "res://src/presentation/progression_icons.gd":
	var atlas: Dictionary
	var textures: Dictionary


	func _parse_atlas(path: String) -> Dictionary:
		if path != ATLAS_PATH:
			return super._parse_atlas(path)
		var parsed: Dictionary = atlas.duplicate(true)
		var by_id := {}
		for raw_entry in (parsed.get("sprites", []) as Array):
			var entry: Dictionary = raw_entry
			by_id[String(entry.get("id", ""))] = entry
		parsed["sprites"] = by_id
		return parsed


	func _load_texture(path: String) -> Texture2D:
		var texture: Texture2D = textures.get(path, null)
		if texture != null:
			return texture
		pending_reason = "ASSETS PENDING: missing %s" % path
		return null


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	for failure in BaseHubScreenTest.new().run():
		failures.append(failure)
	var screen = FacilityScreenScript.new()
	var icon_fixture := _progression_icon_fixture()
	icon_fixture.load_icons()
	root.add_child(screen)
	await process_frame
	screen.set_progression_icons(icon_fixture)
	var snapshot := _snapshot(false)
	screen.present("loadout", {}, {}, "", snapshot)
	var text: String = screen.get_visible_text()
	screen.present("loadout", {}, {}, "candidate_not_selected", snapshot)
	var status_label: Label = screen.get("_status_label")
	_expect(status_label != null and status_label.text.contains("Select")
		and not status_label.text.contains("candidate_not_selected"),
		"facility: internal status code reached the rendered footer", failures)
	screen.present("loadout", {}, {}, "", snapshot)
	text = screen.get_visible_text()
	_expect(text.contains("Preset A") and not text.contains("Exponential") and not text.contains("EXPONENTIAL"), "facility: unverified build title leaked its growth conclusion", failures)
	_expect(text.contains("Continuation Chance: 0.61") and text.contains("Growth Conclusion: Unverified"), "facility: unverified build did not expose the readable continuation chance while withholding the conclusion", failures)
	_expect(text.contains("Skill: Piercing Arrow") and text.contains("Rune: Breeding Split") and text.contains("Law: Pack Hunt Mark"), "facility: ranger component names were not rendered", failures)
	_expect(screen._compact_skill_text({"name":"Roll", "key_bindings":["Space"], "cooldown_ticks":13}, 1) == "Roll\nSpace 0.43s"
		and screen._compact_skill_text({"name":"Dodge", "key_bindings":["Shift"], "cooldown_ticks":35}, 1) == "Dodge\nShift 1.17s",
		"facility: compact skill text no longer keeps complete key words on its second line", failures)
	var actions: Array[Dictionary] = []
	screen.action_requested.connect(func(facility_id: String, action_id: String, payload: Dictionary) -> void:
		actions.append({"facility": facility_id, "action": action_id, "payload": payload.duplicate(true)})
	)
	var select_button: Button = screen.get_action_button("SelectBuild_exponential")
	_expect(select_button != null, "facility: build selection button has no stable node name", failures)
	if select_button != null:
		select_button.pressed.emit()
	_expect(actions.size() == 1 and actions[0] == {"facility": "loadout", "action": "select_ranger_build", "payload": {"preset_id": "exponential"}}, "facility: loadout selection emitted the wrong action payload", failures)

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

	actions.clear()
	var locked_forge := _forge_snapshot(false)
	_expect(screen._forge_candidate_result_item_view({"result_item": {"base_name": "Compatibility Fallback"}}).get("base_name", "") == "Compatibility Fallback",
		"facility: forge candidates without a presentation view no longer fall back to result_item", failures)
	screen.present("forge", {}, {}, "", locked_forge)
	text = screen.get_visible_text()
	_expect(text.contains("Law Token Forge Locked") and text.contains("Complete Main Quest 04")
		and screen.get_action_button("ForgeReveal") == null and not text.contains("Candidate "),
		"facility: locked forge leaked candidates or omitted its unlock reason", failures)
	screen.present("loadout", {}, {}, "", snapshot)
	actions.clear()
	var forge_snapshot := _forge_snapshot(true)
	screen.present("forge", {}, {}, "", forge_snapshot)
	var forge_item_button := screen.find_child("BackpackItem_loot_bow_2", true, false) as Button
	_expect(screen.backpack_detail() != null and not screen.backpack_detail().visible,
		"facility: forge backpack detail is visible before hover/focus", failures)
	if forge_item_button != null:
		forge_item_button.mouse_entered.emit()
		_expect(screen.backpack_detail().visible and screen.get_action_button("SelectForgeItem_loot_bow_2") != null,
			"facility: forge hover did not show target details and nearby action", failures)
		forge_item_button.mouse_exited.emit()
		await process_frame
		_expect(not screen.backpack_detail().visible, "facility: forge mouse exit did not hide target detail", failures)
		forge_item_button.focus_entered.emit()
		forge_item_button.mouse_exited.emit()
		await process_frame
		_expect(screen.backpack_detail().visible, "facility: forge focus did not keep target detail visible", failures)
		forge_item_button.focus_exited.emit()
		await process_frame
	text = screen.get_visible_text()
	_expect(screen.get_action_button("ForgeReveal") != null
		and screen.get_action_button("ForgeReveal").text == "Forecast with Inscribe Law Tokens · No Tokens Spent Yet"
		and String(screen.get_action_button("ForgeOperation_inscribe").text).replace("\n", " ").begins_with("Inscribe ×")
		and String(screen.get_action_button("ForgeOperation_rewrite").text).replace("\n", " ").begins_with("Rewrite ×")
		and String(screen.get_action_button("ForgeOperation_refine").text).replace("\n", " ").begins_with("Refine ×")
		and text.contains("No future has been forecast") and not text.contains("Candidate "),
		"facility: unrevealed forge did not keep the two-stage zero-spend foresight state", failures)
	_expect(not text.contains("Destiny Dice") and not text.contains("ADD") and not text.contains("REROLL") and not text.contains("REFINE"),
		"facility: forge leaked retired dice or operation terminology", failures)
	var operation_icons: Array[Button] = []
	for operation: String in ["inscribe", "rewrite", "refine"]:
		var operation_button := screen.get_action_button("ForgeOperation_%s" % operation)
		_expect(operation_button != null and operation_button.icon is AtlasTexture
			and (operation_button.icon as AtlasTexture).atlas is Texture2D,
			"facility: law-token icon is not backed by the real atlas: %s" % operation, failures)
		if operation_button != null and operation_button.icon is AtlasTexture:
			operation_icons.append(operation_button)
	_expect(operation_icons.size() == 3,
		"facility: the three forge operations did not all receive law-token icons", failures)
	_expect(actions.is_empty() and not screen.get_action_button("ForgeReveal").disabled
		and screen.get_action_button("ForgePreviousAffix") == null and screen.get_action_button("ForgeNextAffix") == null
		and not text.contains("Affix Slot"),
		"facility: first present emitted an action or retained affix-slot selection", failures)
	screen.present("forge", {}, {}, "", forge_snapshot)
	_expect(actions.is_empty(), "facility: repeated present emitted a domain action", failures)
	actions.clear()
	var rewrite_operation := screen.get_action_button("ForgeOperation_rewrite")
	if rewrite_operation != null:
		rewrite_operation.pressed.emit()
	_expect(actions == [{"facility": "forge", "action": "select_forge_operation", "payload": {"operation": "rewrite", "revision": 1}}],
		"facility: operation button emitted more than its explicit intent", failures)
	forge_snapshot["operation"] = "rewrite"
	screen.present("forge", {}, {}, "", forge_snapshot)
	actions.clear()
	var inscribe_operation := screen.get_action_button("ForgeOperation_inscribe")
	if inscribe_operation != null:
		inscribe_operation.pressed.emit()
	_expect(actions == [{"facility": "forge", "action": "select_forge_operation", "payload": {"operation": "inscribe", "revision": 1}}],
		"facility: reverse operation switch emitted more than one intent", failures)
	actions.clear()
	var reveal := screen.get_action_button("ForgeReveal")
	_expect(reveal != null and not reveal.disabled, "facility: legal rewrite has no free reveal action", failures)
	if reveal != null:
		reveal.pressed.emit()
	_expect(actions == [{"facility": "forge", "action": "forge_reveal", "payload": {"revision": 1}}],
		"facility: forge reveal carried mirrored context or emitted more than once", failures)
	actions.clear()
	var capped_forge := _forge_snapshot(true)
	var capped_affixes: Array = []
	for _index in 4:
		capped_affixes.append({"family_id": "piercing_continuation", "family_name": "Piercing Arrow Continuation Chance", "tier": 2})
	(capped_forge["target_item"] as Dictionary)["affixes"] = capped_affixes.duplicate(true)
	capped_forge["affixes"] = capped_affixes.duplicate(true)
	capped_forge["blocked"] = true
	capped_forge["blocked_reason"] = "affix_limit_reached"
	screen.present("loadout", {}, {}, "", snapshot)
	screen.present("forge", {}, {}, "", capped_forge)
	inscribe_operation = screen.get_action_button("ForgeOperation_inscribe")
	if inscribe_operation != null:
		inscribe_operation.pressed.emit()
	var capped_reveal := screen.get_action_button("ForgeReveal")
	_expect(actions.is_empty() and capped_reveal != null and capped_reveal.disabled
		and screen.get_visible_text().contains("Affixes full (maximum 4); cannot inscribe."),
		"facility: four-affix inscribe exposed a fake append slot or an unusable instruction", failures)
	var max_refine_forge := _forge_snapshot(true)
	(max_refine_forge["target_item"] as Dictionary)["affixes"][0]["tier"] = LawForgeScript.MAX_TIER
	(max_refine_forge["affixes"] as Array)[0]["tier"] = LawForgeScript.MAX_TIER
	max_refine_forge["operation"] = "refine"
	max_refine_forge["blocked"] = true
	max_refine_forge["blocked_reason"] = "max_tier"
	screen.present("forge", {}, {}, "", max_refine_forge)
	var refine_operation := screen.get_action_button("ForgeOperation_refine")
	var max_refine_reveal := screen.get_action_button("ForgeReveal")
	_expect(max_refine_reveal != null and max_refine_reveal.disabled
		and screen.get_visible_text().contains("All existing affixes are at their highest tier and cannot be refined."),
		"facility: max-tier refine still offered a reveal the forge authority rejects", failures)
	if max_refine_reveal != null:
		max_refine_reveal.pressed.emit()
	_expect(actions.is_empty(), "facility: max-tier refine emitted a reveal action", failures)
	var revealed_forge := _forge_snapshot(true, true)
	screen.present("forge", {}, {}, "", revealed_forge)
	text = screen.get_visible_text()
	_expect(text.contains("Candidate 1 / 2") and text.contains("Automatic Rewrite: Piercing Arrow Continuation Chance Tier II → Maximum Health Tier III")
		and text.contains("Current Build Changes After Commit") and text.contains("Gained: Breedable Child Arrows")
		and screen.find_child("ForgeBuildComparison", true, false) != null,
		"facility: revealed forge lost its cost, item change, interface or immediate build comparison", failures)
	var result_detail := screen.get_action_button("ForgeFullResultDetail")
	_expect(result_detail != null, "facility: forge lost the complete result detail entry", failures)
	if result_detail != null:
		result_detail.pressed.emit()
		var complete_text := (screen.find_child("ItemDetailText", true, false) as Label).text
		_expect(complete_text.contains("Forecast Outcome") and complete_text.contains("Base Stats")
			and complete_text.contains("Affixes") and complete_text.contains("Rune") and complete_text.contains("Law")
			and complete_text.contains("Critical Chance") and complete_text.contains("Turn Time (Lower Is Better)")
			and complete_text.contains("Ash Longbow") and complete_text.contains("Interfaces Gained: Breedable Child Arrows")
			and not complete_text.contains("ashwood_longbow") and not complete_text.contains("maximum_health"),
			"facility: forge detail lost the complete readable item and build comparison", failures)
		(screen.find_child("ItemDetailDialog", true, false) as AcceptDialog).hide()
	var inventory_target_forge := _forge_snapshot(true, true)
	(inventory_target_forge["target_item"] as Dictionary)["instance_id"] = "loot:bow/6"
	inventory_target_forge["target_instance_id"] = "loot:bow/6"
	(inventory_target_forge["session"] as Dictionary)["target_instance_id"] = "loot:bow/6"
	for raw_candidate in (inventory_target_forge.session.candidates as Array):
		var inventory_candidate: Dictionary = raw_candidate
		inventory_candidate["target_is_equipped"] = false
		inventory_candidate["preview_impact"] = "equip_after_commit"
	screen.present("forge", {}, {}, "", inventory_target_forge)
	text = screen.get_visible_text()
	_expect(text.contains("Commit leaves current build unchanged; expected changes when equipped")
		and text.contains("Gained: Breedable Child Arrows")
		and not text.contains("loot:bow/6") and not text.contains("ashwood_longbow"),
		"facility: inventory forge target did not render the no-auto-equip semantic or leaked internal ids", failures)
	var next_candidate := screen.get_action_button("ForgeNextCandidate")
	if next_candidate != null:
		next_candidate.pressed.emit()
	_expect(actions.is_empty(), "facility: browsing a forge candidate emitted a domain action", failures)
	_expect(screen.get_visible_text().contains("Candidate 2 / 2 · Selecting costs 2 Rewrite Law Tokens")
		and screen.get_visible_text().contains("Viewing · Not Selected"),
		"facility: the nth candidate did not retain its nth-item cost", failures)
	var explicit_select := screen.get_action_button("ForgeSelectCandidate")
	_expect(explicit_select != null and screen.get_action_button("ForgeConfirmSelection") == null,
		"facility: an unselected browsed future did not expose exactly the select primary action", failures)
	if explicit_select != null:
		explicit_select.pressed.emit()
	_expect(actions == [{"facility": "forge", "action": "forge_select_candidate", "payload": {"session_id": "forge-session-1", "candidate_id": "candidate-2"}}],
		"facility: explicit forge selection emitted the wrong session and candidate id", failures)
	actions.clear()
	var selected_forge := _forge_snapshot(true, true, "candidate-2")
	screen.present("forge", {}, {}, "", selected_forge)
	var previous_candidate := screen.get_action_button("ForgePreviousCandidate")
	if previous_candidate != null:
		previous_candidate.pressed.emit()
	_expect(actions.is_empty(), "facility: browsing away from an authoritative selection emitted an action", failures)
	var browsing_state: Label = screen.find_child("ForgeBrowseSelectionState", true, false) as Label
	_expect(browsing_state != null and browsing_state.text.contains("Viewing a New Future · Candidate 2 Selected")
		and browsing_state.text.contains("Candidate 1 / 2") and browsing_state.text.contains("Maximum Health"),
		"facility: browsing another forge result did not identify the browsing candidate", failures)
	_expect(screen.get_action_button("ForgeSelectCandidate") != null
		and screen.get_action_button("ForgeConfirmSelection") == null
		and screen.find_child("ForgePreviewSelectionState", true, false) == null,
		"facility: browsing away duplicated the authoritative result or exposed both primary actions", failures)
	# An authoritative re-presentation restores the selected result as the single detail
	# surface, replacing Select with Confirm in the fixed dock.
	screen.present("forge", {}, {}, "", selected_forge)
	browsing_state = screen.find_child("ForgeBrowseSelectionState", true, false) as Label
	var confirm_armed := screen.get_action_button("ForgeConfirmSelection")
	_expect(confirm_armed != null and not confirm_armed.disabled
		and confirm_armed.text == "Confirm Commit · Spend 2 Rewrite Law Tokens"
		and screen.get_action_button("ForgeSelectCandidate") == null,
		"facility: authoritative selection did not expose only the explicit commit action", failures)
	_expect(browsing_state != null and browsing_state.text.contains("Current Future Selected · Ready to Commit")
		and browsing_state.text.contains("Projectile Lifetime Tier III"),
		"facility: authoritative selection did not stay on the single candidate detail surface", failures)
	if confirm_armed != null:
		confirm_armed.pressed.emit()
	_expect(actions == [{"facility": "forge", "action": "forge_commit", "payload": {"session_id": "forge-session-1"}}],
		"facility: forge commit payload must contain only session_id", failures)
	var blocked_repeat: Button = screen.get_action_button("ForgeConfirmSelection")
	if blocked_repeat != null:
		blocked_repeat.pressed.emit()
	_expect(actions.size() == 1, "facility: a repeated forge confirmation emitted twice", failures)
	# GameRoot re-presents the authoritative selected session after a failed save.
	# That explicit response must re-arm the exact choice for retry.
	screen.present("forge", {}, {}, "Save Failed", selected_forge)
	var retry_confirm: Button = screen.get_action_button("ForgeConfirmSelection")
	_expect(retry_confirm != null and not retry_confirm.disabled,
		"facility: a failed-save re-presentation did not re-arm the selected forge result", failures)
	actions.clear()
	if retry_confirm != null:
		retry_confirm.pressed.emit()
	_expect(actions == [{"facility": "forge", "action": "forge_commit", "payload": {"session_id": "forge-session-1"}}],
		"facility: retrying the same authoritative forge session emitted the wrong action", failures)
	actions.clear()
	var reveal_more := screen.get_action_button("ForgeRevealMore")
	if reveal_more != null:
		reveal_more.pressed.emit()
	_expect(actions == [{"facility": "forge", "action": "forge_reveal_more", "payload": {"session_id": "forge-session-1"}}],
		"facility: continue reveal payload is wrong", failures)
	actions.clear()
	var cancel_forge := screen.get_action_button("ForgeCancelSelection")
	if cancel_forge != null:
		cancel_forge.pressed.emit()
	_expect(actions == [{"facility": "forge", "action": "forge_cancel", "payload": {"session_id": "forge-session-1"}}],
		"facility: cancel did not preserve zero-spend session cancellation", failures)
	actions.clear()
	screen.present("forge", {}, {}, "", selected_forge)
	inscribe_operation = screen.get_action_button("ForgeOperation_inscribe")
	if inscribe_operation != null:
		inscribe_operation.pressed.emit()
	_expect(actions == [{"facility": "forge", "action": "select_forge_operation", "payload": {"operation": "inscribe", "revision": 1}}],
		"facility: changing operation emitted cancel/rebuild side effects instead of one intent", failures)
	actions.clear()
	screen.present("forge", {}, {}, "", selected_forge)
	_focus_backpack_item(screen, "loot:bow/2")
	var forge_full: Button = screen.get_action_button("FullItemDetails_loot_bow_2")
	_expect(forge_full != null, "facility: forge target picker has no complete detail action", failures)
	if forge_full != null:
		forge_full.grab_focus()
		forge_full.pressed.emit()
		await _settle_frames()
		var forge_detail_text: Label = screen.find_child("ItemDetailText", true, false) as Label
		_expect(forge_detail_text != null and forge_detail_text.text.contains("Swiftstring Recurve")
			and not forge_detail_text.text.contains("instance_id") and not forge_detail_text.text.contains("family_id")
			and not forge_detail_text.text.contains("main_hand") and not forge_detail_text.text.contains("loot:bow/2"),
			"facility: forge complete detail is incomplete or leaked internal fields", failures)
		var forge_dialog := screen.find_child("ItemDetailDialog", true, false) as AcceptDialog
		if forge_dialog != null:
			forge_dialog.get_ok_button().pressed.emit()
			await _settle_frames()
	var other_button := screen.get_action_button("SelectForgeItem_loot_bow_2")
	if other_button != null:
		other_button.pressed.emit()
	_expect(actions == [{"facility": "forge", "action": "select_forge_item", "payload": {"instance_id": "loot:bow/2", "revision": 1}}],
		"facility: switching targets emitted more than one explicit intent", failures)
	actions.clear()
	screen.present("forge", {}, {}, "", selected_forge)
	_expect(screen.get_action_button("ForgeConfirmSelection") != null and not screen.get_action_button("ForgeConfirmSelection").disabled
		and screen.get_visible_text().contains("Candidate 2 / 2"),
		"facility: present did not restore the domain forge session and selected candidate", failures)

	actions.clear()
	var training_fingerprint := "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
	var stale_fingerprint := "ffeeddccbbaa99887766554433221100ffeeddccbbaa99887766554433221100"
	var unverified_training := _training_snapshot(false, training_fingerprint, {})
	screen.present("training", {}, {}, "", unverified_training)
	text = screen.get_visible_text()
	_expect(text.contains("Current Build"), "facility: training view did not identify the current build", failures)
	# The first screen is the four readable cards. The parameter wall, the fingerprint
	# and the raw report are the reference layer and stay folded until they are asked for.
	_expect(text.contains("Growth Conclusion\nUnverified") and not text.contains("exponential") and not text.contains("Exponential"),
		"facility: unverified training view leaked its growth classification", failures)
	_expect(text.contains("Connected Interfaces\nBreedable Child Arrows, Branch Target History")
		and text.contains("Missing Interfaces\nLineage Lifetime Pause"),
		"facility: training view did not render the resolved interfaces as readable cards", failures)
	_expect(not text.contains("Final Stats") and not text.contains("p: 0.61") and not text.contains("Build Fingerprint"),
		"facility: the unverified training page opened with its raw parameter block", failures)
	_expect(text.contains("Current build not yet trained") and not text.contains("Training readings: ") and not text.contains("Total Events"),
		"facility: unverified training view leaked report numbers", failures)
	var unverified_identity: Label = screen.find_child("TrainingReportIdentity", true, false) as Label
	_expect(unverified_identity != null and unverified_identity.text.contains("Status: Not Yet Trained")
		and unverified_identity.text.contains("Next Step: Run Training Trial"),
		"facility: unverified training did not name the current build, status, and next action", failures)
	_expect_no_calibration_copy(text, failures)
	var unverified_toggle: Button = screen.get_action_button("TrainingDetailsToggle")
	_expect(unverified_toggle != null and unverified_toggle.text.contains("Show"),
		"facility: the training reference data is not folded by default", failures)
	if unverified_toggle != null:
		unverified_toggle.pressed.emit()
	text = screen.get_visible_text()
	_expect(text.contains("Piercing Arrow Continuation Chance: 61%") and text.contains("Shared Lineage Lifetime: 34 s")
		and text.contains("Projectile Speed: 682 units/s") and text.contains("Turn Time (Lower Is Better): 0.16 s")
		and text.contains("Carrier Damage: 160") and text.contains("Maximum Health: 112"),
		"facility: the training reference data did not restore the public parameters", failures)
	_expect(not text.contains("Build Fingerprint") and not text.contains(training_fingerprint),
		"facility: build fingerprint escaped the test console", failures)
	_expect(not text.contains("breedable_event") and not text.contains("branch_target_history")
		and not text.contains("lineage_lifetime_pause"),
		"facility: raw interface ids escaped the test console", failures)
	_expect(screen._training_interface_text(["future_interface"]) == "Unknown Interface (future_interface)",
		"facility: an unknown interface must stay readable while preserving its raw id", failures)
	_expect(screen._training_interface_text(["piercing_continuation"]) == "Piercing Continuation",
		"facility: the real ranger's base interface must have readable copy", failures)
	_expect(text.contains("Current build not yet trained") and not text.contains("Training readings: "),
		"facility: the unverified reference block did not keep its stand-in sentence", failures)
	_expect_no_calibration_copy(text, failures)
	var unverified_fold: Button = screen.get_action_button("TrainingDetailsToggle")
	_expect(unverified_fold != null and unverified_fold.text.contains("Hide"),
		"facility: the open training reference block lost its toggle", failures)
	if unverified_fold != null:
		unverified_fold.pressed.emit()
	text = screen.get_visible_text()
	_expect(not text.contains("p: 0.61") and not text.contains("Build Fingerprint"),
		"facility: folding the training reference data did not hide the raw fields again", failures)
	var training_button: Button = screen.get_action_button("RunTrainingTrial")
	_expect(training_button != null, "facility: training trial action is missing", failures)
	if training_button != null:
		training_button.pressed.emit()
	_expect(actions.size() == 1 and actions[0] == {"facility": "training", "action": "run_training_trial", "payload": {}},
		"facility: training trial emitted the wrong action", failures)

	var verified_training := _training_snapshot(true, training_fingerprint, _training_report(training_fingerprint))
	screen.present("training", {}, {}, "", verified_training)
	text = screen.get_visible_text()
	_expect(text.contains("Growth Conclusion\nExponential"), "facility: verified current Build did not reveal its growth classification", failures)
	_expect(text.contains("Training readings: R 1.22 · g 3 · Total Events 12") and not text.contains("summary: ")
		and not text.contains("Growth State") and not text.contains("Event Growth Curve"),
		"facility: the matching report's first-screen reading is wrong, or the main reading repeats the raw curve", failures)
	_expect(not text.contains("Current build not yet trained"), "facility: matching training report was replaced by the unverified copy", failures)
	_expect(text.contains("Next Step\nKeep forecasting with this build"), "facility: matching report did not render the action sentence as its own card", failures)
	# The trace draws exactly the matching report's generations, and names the value
	# axis it really used.
	var trace_report: Dictionary = screen.training_trace_report()
	_expect(bool(trace_report.get("present", false)) and bool(trace_report.get("drawing", false)),
		"facility: the verified training report drew no generational trace", failures)
	_expect(trace_report.get("generations") == [0, 20] and trace_report.get("events_display") == ["1", "12"],
		"facility: the trace did not draw exactly the matching report's generations: %s" % str(trace_report), failures)
	_expect(String(trace_report.get("mode", "")) == "log10" and String(trace_report.get("axis_caption", "")).contains("log10 scale"),
		"facility: a value axis was used without being named a log axis: %s" % String(trace_report.get("axis_caption", "")), failures)
	var trace_axis: Label = screen.find_child("TrainingGrowthTraceAxis", true, false) as Label
	_expect(trace_axis != null and trace_axis.visible and trace_axis.text.contains("log10 scale")
		and trace_axis.get_theme_font_size("font_size") >= 18,
		"facility: the drawn axis was not labeled in 18px page copy", failures)
	var trace_node: Control = screen.find_child("TrainingGrowthTrace", true, false)
	_expect(trace_node != null and trace_node.custom_minimum_size.y >= 100.0,
		"facility: the trace control has no room to draw its points", failures)
	_expect(text.contains("The curve retains every sample from this trial."),
		"facility: the trace did not say where its numbers and copy come from", failures)
	_expect_no_calibration_copy(text, failures)

	# Each fingerprint owns its report. Switching A to B and back to A restores A's
	# conclusion and reading without borrowing B's report or showing a contradiction.
	var fingerprint_b := "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
	var report_b := _training_report(fingerprint_b)
	report_b["state"] = "critical"
	report_b["R"] = 1.0
	report_b["event_count_display"] = "81"
	var switch_snapshot := verified_training.duplicate(true)
	(switch_snapshot.training.reports_by_fingerprint as Dictionary)[fingerprint_b] = report_b
	screen.present("training", {}, {}, "", switch_snapshot)
	_expect(screen.get_visible_text().contains("Growth Conclusion\nExponential") and screen.get_visible_text().contains("Total Events 12"),
		"facility: A report was not shown before A to B switch", failures)
	switch_snapshot.resolved_build.build_fingerprint = fingerprint_b
	screen.present("training", {}, {}, "", switch_snapshot)
	_expect(screen.get_visible_text().contains("Growth Conclusion\nCritical") and screen.get_visible_text().contains("Total Events 81")
		and not screen.get_visible_text().contains("Total Events 12"),
		"facility: B did not show only B's matching report", failures)
	switch_snapshot.resolved_build.build_fingerprint = training_fingerprint
	screen.present("training", {}, {}, "", switch_snapshot)
	text = screen.get_visible_text()
	_expect(text.contains("Growth Conclusion\nExponential") and text.contains("Total Events 12")
		and not text.contains("Total Events 81") and not text.contains("Current build not yet trained"),
		"facility: A to B to A did not restore A's report cleanly", failures)

	# The raw report is the reference layer, not the reading: the seed, the complete
	# generational string and the untranslated state word all come back when the
	# training page's own fold is opened, and folding it again leaves the page as it
	# started. The fold never changes what the page reads, only what it shows.
	var verified_toggle: Button = screen.get_action_button("TrainingDetailsToggle")
	_expect(verified_toggle != null and verified_toggle.text.contains("Show"),
		"facility: the verified training page did not start with its reference data folded", failures)
	if verified_toggle != null:
		verified_toggle.pressed.emit()
	text = screen.get_visible_text()
	_expect(not text.contains("Replay Seed") and not text.contains("42"),
		"facility: training seed escaped the test console", failures)
	_expect(text.contains("Event Growth Curve: G0:1 → G20:12"),
		"facility: the training reference data did not render the complete growth curve", failures)
	_expect(text.contains("Growth Classification: Exponential") and text.contains("Piercing Arrow Continuation Chance: 61%") and not text.contains("exponential"),
		"facility: the training reference data lost the readable classification or public parameters", failures)
	_expect_no_calibration_copy(text, failures)
	var verified_fold: Button = screen.get_action_button("TrainingDetailsToggle")
	_expect(verified_fold != null and verified_fold.text.contains("Hide"),
		"facility: the open training reference block lost its fold label", failures)
	if verified_fold != null:
		verified_fold.pressed.emit()
	text = screen.get_visible_text()
	_expect(not text.contains("Event Growth Curve") and not text.contains("Replay Seed"),
		"facility: folding the training reference data left the raw report on the page", failures)

	# Readings that are not comparable decimals drop the value axis instead of getting
	# an invented height, and every value string still comes from the report.
	var tower_report := _training_report(training_fingerprint)
	tower_report["growth_curve"] = [
		{"generation": 0, "events_display": "1"},
		{"generation": 5, "events_display": "10^^2(3.5)"},
		{"generation": 10, "events_display": "10^^3(1.25)"},
	]
	screen.present("training", {}, {}, "", _training_snapshot(true, training_fingerprint, tower_report))
	text = screen.get_visible_text()
	var tower_trace: Dictionary = screen.training_trace_report()
	_expect(String(tower_trace.get("mode", "")) == "order" and bool(tower_trace.get("drawing", false))
		and int(tower_trace.get("point_count", 0)) == 3,
		"facility: a tower reading was placed on a value axis instead of the order-only form", failures)
	_expect(String(tower_trace.get("axis_caption", "")).contains("not used"),
		"facility: the order-only trace did not say that no value axis was drawn", failures)
	var tower_toggle: Button = screen.get_action_button("TrainingDetailsToggle")
	_expect(tower_toggle != null and tower_toggle.text.contains("Show"),
		"facility: the tower reading did not start with its reference data folded", failures)
	if tower_toggle != null:
		tower_toggle.pressed.emit()
	text = screen.get_visible_text()
	_expect(text.contains("Event Growth Curve: G0:1 → G5:10^^2(3.5) → G10:10^^3(1.25)"),
		"facility: the order-only trace lost the report's own value strings", failures)
	_expect_no_calibration_copy(text, failures)
	var tower_fold: Button = screen.get_action_button("TrainingDetailsToggle")
	if tower_fold != null:
		tower_fold.pressed.emit()

	var stale_report := _training_report(stale_fingerprint)
	stale_report["p"] = 0.99
	stale_report["R"] = 9.99
	stale_report["event_count"] = 777.0
	stale_report["report"] = "stale sentinel"
	stale_report["training_seed"] = 999
	stale_report["growth_curve"] = [{"generation": 999, "events_display": "777"}]
	stale_report["action"] = "stale action sentinel"
	var stale_verified := _training_snapshot(true, training_fingerprint, stale_report)
	screen.present("training", {}, {}, "", stale_verified)
	text = screen.get_visible_text()
	_expect(text.contains("Growth Conclusion\nUnverified") and not text.contains("Growth Conclusion\nExponential"),
		"facility: stale-only report incorrectly verified the current Build", failures)
	_expect(text.contains("Current build not yet trained") and not text.contains("0.99") and not text.contains("9.99")
		and not text.contains("777") and not text.contains("stale sentinel")
		and not text.contains("Replay Seed") and not text.contains("G999")
		and not text.contains("stale action sentinel") and text.contains("Next Step: Run Training Trial"),
		"facility: a report from an old Build masqueraded as the current Build's report", failures)
	_expect(not bool(screen.training_trace_report().get("present", false))
		and screen.find_child("TrainingGrowthTrace", true, false) == null
		and not text.contains("Numeric Y-axis"),
		"facility: a stale report drew a trace, or the previous valid curve stood in for it", failures)
	_expect_no_calibration_copy(text, failures)
	# The fold is not a loophole: even the reference layer of a verified Build with a
	# stale report may not reprint one field of the old report.
	var stale_toggle: Button = screen.get_action_button("TrainingDetailsToggle")
	_expect(stale_toggle != null, "facility: the stale training page lost its reference toggle", failures)
	if stale_toggle != null:
		stale_toggle.pressed.emit()
	text = screen.get_visible_text()
	_expect(text.contains("Current build not yet trained") and not text.contains("0.99") and not text.contains("9.99")
		and not text.contains("777") and not text.contains("stale sentinel")
		and not text.contains("Replay Seed") and not text.contains("G999")
		and not text.contains("stale action sentinel") and text.contains("Next Step: Run Training Trial"),
		"facility: the training reference layer reprinted a stale report's fields", failures)
	_expect_no_calibration_copy(text, failures)
	var stale_fold: Button = screen.get_action_button("TrainingDetailsToggle")
	if stale_fold != null:
		stale_fold.pressed.emit()

	var unverified_stale := _training_snapshot(false, training_fingerprint, stale_report)
	screen.present("training", {}, {}, "", unverified_stale)
	text = screen.get_visible_text()
	_expect(text.contains("Growth Conclusion\nUnverified") and not text.contains("exponential") and not text.contains("Exponential"),
		"facility: unverified Build with a stale report leaked its classification", failures)
	_expect(text.contains("Current build not yet trained") and not text.contains("0.99") and not text.contains("9.99")
		and not text.contains("777") and not text.contains("stale sentinel")
		and not text.contains("Replay Seed") and not text.contains("G999") and text.contains("Next Step: Run Training Trial"),
		"facility: unverified Build displayed an old Build's report", failures)
	_expect_no_calibration_copy(text, failures)

	var unverified_match := _training_snapshot(false, training_fingerprint, _training_report(training_fingerprint))
	screen.present("training", {}, {}, "", unverified_match)
	text = screen.get_visible_text()
	_expect(text.contains("Current build not yet trained") and not text.contains("Replay Seed") and not text.contains("42")
		and not text.contains("Event Growth Curve") and text.contains("Next Step: Run Training Trial") and not text.contains("Keep forecasting with this build"),
		"facility: unverified Build leaked the new report fields despite a matching fingerprint", failures)
	_expect(not bool(screen.training_trace_report().get("present", false))
		and screen.find_child("TrainingGrowthTrace", true, false) == null,
		"facility: an unverified Build drew the matching report's trace anyway", failures)
	_expect_no_calibration_copy(text, failures)
	var match_toggle: Button = screen.get_action_button("TrainingDetailsToggle")
	_expect(match_toggle != null, "facility: the unverified training page lost its reference toggle", failures)
	if match_toggle != null:
		match_toggle.pressed.emit()
	text = screen.get_visible_text()
	_expect(text.contains("Current build not yet trained") and not text.contains("Replay Seed") and not text.contains("42")
		and not text.contains("Event Growth Curve") and text.contains("Next Step: Run Training Trial") and not text.contains("Keep forecasting with this build"),
		"facility: the unverified reference layer leaked the matching report's fields", failures)
	_expect_no_calibration_copy(text, failures)
	var match_fold: Button = screen.get_action_button("TrainingDetailsToggle")
	if match_fold != null:
		match_fold.pressed.emit()

	var legacy_report := {
		"preset_id": "exponential",
		"build_fingerprint": training_fingerprint,
		"p": 0.61,
		"R": 1.22,
		"g": 3,
		"event_count": 12.0,
		"state": "exponential",
		"report": "p=0.61, R=1.22, g=3, events=12: exponential",
	}
	screen.present("training", {}, {}, "", _training_snapshot(true, training_fingerprint, legacy_report))
	text = screen.get_visible_text()
	_expect(text.contains("Training readings: R 1.22 · g 3 · Total Events 12"),
		"facility: legacy report without the new fields was not rendered", failures)
	var legacy_toggle: Button = screen.get_action_button("TrainingDetailsToggle")
	_expect(legacy_toggle != null, "facility: the legacy training page lost its reference toggle", failures)
	if legacy_toggle != null:
		legacy_toggle.pressed.emit()
	text = screen.get_visible_text()
	_expect(text.contains("Growth Classification: Exponential") and not text.contains("exponential"),
		"facility: the legacy report lost its readable classification", failures)
	_expect(not text.contains("Replay Seed") and not text.contains("Event Growth Curve") and not text.contains("Next Step"),
		"facility: legacy report invented placeholder sections for missing fields", failures)
	_expect_no_calibration_copy(text, failures)
	var legacy_fold: Button = screen.get_action_button("TrainingDetailsToggle")
	if legacy_fold != null:
		legacy_fold.pressed.emit()

	var malformed_report := _training_report(training_fingerprint)
	malformed_report["training_seed"] = 7
	malformed_report["growth_curve"] = [
		{"generation": 20.0, "events_display": "20.0 sentinel"},
		{"generation": "30", "events_display": "30 sentinel"},
		{"events_display": "no generation sentinel"},
		{"generation": 5, "events_display": ""},
		{"generation": 6, "events_display": "   "},
		{"generation": 7, "events_display": 999},
		42, "junk", {},
		{"generation": 20, "events_display": "12"},
		{"generation": 0, "events_display": "1"},
	]
	malformed_report["action"] = ""
	screen.present("training", {}, {}, "", _training_snapshot(true, training_fingerprint, malformed_report))
	text = screen.get_visible_text()
	_expect(not text.contains("Replay Seed") and not text.contains("Event Growth Curve") and not text.contains("Next Step"),
		"facility: the first screen of the malformed report showed raw reference fields", failures)
	var malformed_toggle: Button = screen.get_action_button("TrainingDetailsToggle")
	_expect(malformed_toggle != null, "facility: the malformed training page lost its reference toggle", failures)
	if malformed_toggle != null:
		malformed_toggle.pressed.emit()
	text = screen.get_visible_text()
	_expect(not text.contains("Replay Seed") and text.contains("Event Growth Curve: G0:1 → G20:12"),
		"facility: malformed curve was not filtered down to its valid points", failures)
	_expect(not text.contains("G20.0") and not text.contains("G30") and not text.contains("G5") and not text.contains("G6")
		and not text.contains("G7") and not text.contains("sentinel") and not text.contains("junk") and not text.contains("Next Step"),
		"facility: malformed curve entries or an empty action leaked into the report", failures)
	_expect_no_calibration_copy(text, failures)
	var malformed_fold: Button = screen.get_action_button("TrainingDetailsToggle")
	if malformed_fold != null:
		malformed_fold.pressed.emit()

	var empty_curve_report := _training_report(training_fingerprint)
	empty_curve_report["training_seed"] = 99.0
	empty_curve_report["growth_curve"] = [{"generation": 1.0, "events_display": "x"}, "junk"]
	empty_curve_report["action"] = ""
	screen.present("training", {}, {}, "", _training_snapshot(true, training_fingerprint, empty_curve_report))
	text = screen.get_visible_text()
	_expect(not text.contains("Event Growth Curve") and not text.contains("Replay Seed") and not text.contains("Next Step"),
		"facility: a curve with no valid points or a non-int seed was still displayed", failures)
	_expect(not bool(screen.training_trace_report().get("present", false))
		and screen.find_child("TrainingGrowthTrace", true, false) == null,
		"facility: a curve with no valid points still produced a trace", failures)
	_expect_no_calibration_copy(text, failures)
	var empty_toggle: Button = screen.get_action_button("TrainingDetailsToggle")
	_expect(empty_toggle != null, "facility: the empty-curve training page lost its reference toggle", failures)
	if empty_toggle != null:
		empty_toggle.pressed.emit()
	text = screen.get_visible_text()
	_expect(text.contains("Training readings: R 1.22 · g 3 · Total Events 12") and not text.contains("Event Growth Curve")
		and not text.contains("Replay Seed") and not text.contains("Next Step"),
		"facility: the reference layer invented a curve or a seed the report does not carry", failures)
	_expect(not bool(screen.training_trace_report().get("present", false))
		and screen.find_child("TrainingGrowthTrace", true, false) == null,
		"facility: opening the reference layer drew a trace for a curve with no valid points", failures)
	_expect_no_calibration_copy(text, failures)
	var empty_fold: Button = screen.get_action_button("TrainingDetailsToggle")
	if empty_fold != null:
		empty_fold.pressed.emit()

	var missing_resolved := _training_snapshot(false, training_fingerprint, {})
	missing_resolved.erase("resolved_build")
	screen.present("training", {}, {}, "", missing_resolved)
	text = screen.get_visible_text()
	_expect(text.contains("Training Data Unavailable"), "facility: missing resolved Build was not reported as unavailable", failures)
	_expect(not text.contains("exponential") and not text.contains("Exponential"),
		"facility: missing resolved Build leaked growth copy", failures)
	_expect_no_calibration_copy(text, failures)
	_expect(screen.get_action_button("RunTrainingTrial") != null, "facility: unavailable training view dropped the trial action", failures)

	var bad_resolved := _training_snapshot(false, training_fingerprint, {})
	bad_resolved["resolved_build"] = {"ok": false, "error": "invalid_active_build", "growth_classification": "invalid", "final_parameters": {}}
	screen.present("training", {}, {}, "", bad_resolved)
	text = screen.get_visible_text()
	_expect(text.contains("Training Data Unavailable") and not text.contains("invalid") and not text.contains("Exponential"),
		"facility: bad resolved Build leaked an error or growth classification", failures)
	_expect_no_calibration_copy(text, failures)

	var isolation_snapshot := _training_snapshot(true, training_fingerprint, _training_report(training_fingerprint))
	var isolation_before := isolation_snapshot.duplicate(true)
	screen.present("training", {}, {}, "", isolation_snapshot)
	_expect(isolation_snapshot == isolation_before, "facility: presenting training mutated the caller's snapshot", failures)

	actions.clear()
	screen.present("proxy", {}, {}, "", _proxy_snapshot(false, false))
	text = screen.get_visible_text()
	_expect(text.contains("Proxy Bay · Core Assembly") and text.contains("Assemble four slots") and text.contains("freezes when the contract starts")
		and text.contains("Unlock requirement: defeat the Threshold Colossus in Manual") and text.contains("first-kill reward")
		and text.contains("Near-Enemy Sight") and text.contains("retreat at close range"),
		"facility: locked proxy copy or reward preview is incorrect", failures)
	_expect(screen.find_children("ProxyCoreCell_*", "PanelContainer", true, false).size() == 4
		and screen.find_children("ProxyEquip_*", "Button", true, false).is_empty()
		and screen.find_children("ProxyDistanceBand_*", "Button", true, false).is_empty(),
		"facility: locked proxy did not keep four preview cells and zero operations", failures)

	screen.present("proxy", {}, {}, "", _proxy_snapshot(false, true))
	text = screen.get_visible_text()
	_expect(text.contains("Current Assembly · Perception -> Action -> Execution -> Memory") and text.contains("Near-Enemy Sight · Perception")
		and text.contains("Direct-Approach Legs · Action") and text.count("Connected") == 4 and text.contains("Auto Available")
		and text.contains("Auto Wins: 2") and text.contains("Early Chapter Complete: Yes") and text.contains("Attachments Not Yet Available"),
		"facility: unlocked proxy state or dynamic slot strip was not rendered", failures)
	_expect(not text.contains("Semantic fingerprint") and not text.contains("0123456789abcdef"),
		"facility: proxy fingerprint escaped the test console", failures)
	_expect(text.contains("Core Inventory and Protocols") and text.contains("Mark Prism · Perception Slot · Not Owned")
		and text.contains("Range-Keeping Legs · Action Slot · In Storage")
		and text.contains("Protocol: Continuously maintain the player's near, medium, or far range band; bands follow Piercing Arrow's actual range and avoid oscillation at their edges"),
		"facility: proxy inventory lost ownership, slot, or full protocol copy", failures)
	_expect(screen.get_action_button("ProxyEquip_distance_keeping_gait") != null
		and screen.get_action_button("ProxyEquip_marking_prism") == null,
		"facility: owned and unowned proxy cores exposed the wrong install actions", failures)
	var equip_distance: Button = screen.get_action_button("ProxyEquip_distance_keeping_gait")
	if equip_distance != null:
		equip_distance.pressed.emit()
	_expect(actions == [{"facility": "proxy", "action": "equip_proxy_core", "payload": {"core_id": "distance_keeping_gait"}}],
		"facility: proxy core install emitted the wrong action payload", failures)
	_expect(screen.find_child("ProxyDistanceBand", true, false) == null and not text.contains("Distance Band"),
		"facility: direct gait rendered distance-band controls", failures)
	_expect(not text.contains("State Parser") and not text.contains("Circling Hunt Legs") and not text.contains("Danger Forewarning"),
		"facility: unimplemented proxy cores leaked onto the player surface", failures)

	actions.clear()
	screen.present("proxy", {}, {}, "", _proxy_snapshot(true, true))
	text = screen.get_visible_text()
	_expect(text.contains("Range-Keeping Legs · Action") and text.contains("Distance Band")
		and text.contains("follow Piercing Arrow's actual range") and not text.contains("targeting_distance") and not text.contains("absolute meters"),
		"facility: installed distance gait did not render relative-only distance controls", failures)
	var near_band: Button = screen.get_action_button("ProxyDistanceBand_near")
	var mid_band: Button = screen.get_action_button("ProxyDistanceBand_mid")
	var far_band: Button = screen.get_action_button("ProxyDistanceBand_far")
	_expect(near_band != null and mid_band != null and far_band != null and mid_band.disabled
		and mid_band.text.contains("Current") and not near_band.disabled and not far_band.disabled,
		"facility: distance-band current state or stable buttons are wrong", failures)
	if far_band != null:
		far_band.pressed.emit()
	_expect(actions == [{"facility": "proxy", "action": "configure_proxy_core", "payload": {"core_id": "distance_keeping_gait", "settings": {"distance_band": "far"}}}],
		"facility: distance-band selection emitted the wrong action payload", failures)

	root.remove_child(screen)
	screen.free()

	await _run_layout_checks(failures)
	# Subwindows and their text resources leave the tree on the next idle pass.
	# Let cleanup settle so an otherwise passing UI probe does not report engine
	# RID/ObjectDB leaks after the new bounded item-detail dialog was exercised.
	for child in root.get_children():
		child.free()
	await process_frame
	await process_frame
	_finish(failures)


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


## One line per control at or under `node`, with the rect the layout really gave it and
## whether it is visible: the loadout and forge compositions are absolute-positioned
## inside a plain Control, so a layout failure has to report global rects instead of
## relative sizes. Passing a null node reports that the node itself is missing.
func _frame_report(node: Node, depth: int = 0) -> String:
	if node == null:
		return "    (the node this report was asked for is missing)"
	var lines: Array[String] = []
	for child: Node in node.get_children():
		if not child is Control:
			continue
		var control := child as Control
		lines.append("%s%s  %s  %s  visible=%s" % [
			"    ".repeat(depth), control.name, str(control.get_global_rect()), str(control.size), str(control.is_visible_in_tree()),
		])
		lines.append(_frame_report(child, depth + 1))
	return "\n".join(lines)


## Read the three-column comparison as actual label values, not its tooltip.
func _comparison_text(grid: GridContainer) -> String:
	if grid == null:
		return ""
	var parts: Array[String] = []
	for child in grid.get_children():
		if child is Label:
			parts.append(child.text)
	return "\n".join(parts)


func _expect_comparison_row(grid: GridContainer, attribute: String, current: String, replacement: String, color: Color, failures: Array[String]) -> void:
	var cells: Array[Label] = []
	if grid != null and grid.columns == 4:
		for index in range(grid.columns, grid.get_child_count() - 2, grid.columns):
			if grid.get_child(index) is Label and grid.get_child(index).text == attribute:
				for offset in 3:
					cells.append(grid.get_child(index + offset) as Label)
				break
	_expect(cells.size() == 3 and cells[1] != null and cells[2] != null
		and cells[1].text == current and cells[2].text == replacement
		and cells[2].get_theme_color("font_color") == color,
		"facility comparison: %s expected current %s / replacement %s with correct benefit color; actual %s" % [attribute, current, replacement, _comparison_text(grid).replace("\n", " / ")], failures)


## Wait for container sorting and the deferred minimum-size/scroll pass.
func _settle_frames() -> void:
	await process_frame
	await process_frame
	await process_frame


func _focus_backpack_item(screen: Node, instance_id: String) -> Button:
	var backpack := screen.find_child("EquipmentBackpack", true, false)
	if backpack != null:
		backpack.show_item(instance_id)
	var token := instance_id.replace(":", "_").replace("/", "_")
	var button := screen.find_child("BackpackItem_%s" % token, true, false) as Button
	if button != null:
		button.focus_entered.emit()
	return button


## No visible control may leave the logical viewport on the right, no text may
## drop below 18px, and text must wrap or pass its bounded compact-label check.
## The fixed page title stays on one line; its subtitle owns the wrapping.
func _check_logical_layout(screen: Node, viewport: Vector2, label: String, failures: Array[String]) -> void:
	var overflows: Array[String] = []
	var small_text: Array[String] = []
	var unwrapped: Array[String] = []
	for node: Node in screen.find_children("*", "Control", true, false):
		var control := node as Control
		if not control.is_visible_in_tree() or control.get_viewport() != screen.get_viewport():
			continue
		var rect := control.get_global_rect()
		if rect.position.x + rect.size.x > viewport.x + 1.0 and overflows.size() < 4:
			overflows.append("%s right=%0.1f" % [control.name, rect.position.x + rect.size.x])
		if node is Label or node is Button:
			var font_size := control.get_theme_font_size("font_size")
			if font_size < 18 and small_text.size() < 4:
				small_text.append("%s=%d" % [control.name, font_size])
			var autowrap := (node as Label).autowrap_mode if node is Label else (node as Button).autowrap_mode
			var empty_button := node is Button and (node as Button).text.is_empty()
			var fixed_two_line_button := false
			var comparison_cell := node is Label and node.get_parent() is GridContainer and String(node.get_parent().name).begins_with("CandidateDecision_")
			var comparison_fits := comparison_cell and control.get_combined_minimum_size().x <= control.size.x + 0.5 and control.get_combined_minimum_size().y <= control.size.y + 0.5
			var compact_action := String(control.name) in ["CandidateSort", "CandidateFiltersToggle", "CandidateFiltersReset",
				"BackpackPreviousPage", "BackpackNextPage", "ForgePreviousCandidate", "ForgeNextCandidate"] \
				and control.get_combined_minimum_size().x <= control.size.x + 0.5 and control.get_combined_minimum_size().y <= control.size.y + 0.5
			var filter_summary := String(control.name) == "CandidateFilterSummary" and node is Label \
				and (node as Label).text_overrun_behavior == TextServer.OVERRUN_TRIM_ELLIPSIS and not control.tooltip_text.is_empty()
			var tile_badge_fits := false
			if node is Label and String(node.get_parent().name).begins_with("BackpackStatus_"):
				var badge_label := node as Label
				var text_width := badge_label.get_theme_font("font").get_string_size(badge_label.text,
					HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
				tile_badge_fits = badge_label.get_line_count() == 1 and text_width <= badge_label.size.x \
					and (node.get_parent() as Control).get_global_rect().encloses(rect)
			if node is Button and (String(control.name).begins_with("SkillSummary_") or String(control.name).begins_with("ForgeOperation_")):
				var action := node as Button
				var minimum := action.get_combined_minimum_size()
				fixed_two_line_button = action.text.count("\n") == 1 \
					and minimum.x <= action.size.x + 0.5 and minimum.y <= action.size.y + 0.5
			if autowrap == TextServer.AUTOWRAP_OFF and not empty_button and not fixed_two_line_button and not comparison_fits and not compact_action and not filter_summary and not tile_badge_fits \
				and String(control.name) != "FacilityTitle" and unwrapped.size() < 4:
				unwrapped.append(String(control.name))
	_expect(overflows.is_empty(), "facility layout %s: controls leave the logical viewport: %s" % [label, str(overflows)], failures)
	_expect(small_text.is_empty(), "facility layout %s: text below the 18px floor: %s" % [label, str(small_text)], failures)
	_expect(unwrapped.is_empty(), "facility layout %s: text that cannot wrap: %s" % [label, str(unwrapped)], failures)


## Every TextureRect that carries a published canonical id has to be laid out
## inside the frame: this is the same contract the GPU art pass checks, measured
## here on the logical layout so a clipped cell is caught without a display.
func _check_icon_frame(screen: Node, viewport: Vector2, label: String, failures: Array[String]) -> void:
	var outside: Array[String] = []
	for node: Node in screen.find_children("*", "TextureRect", true, false):
		var icon := node as TextureRect
		if str(icon.get_meta("canonical_id", "")).is_empty():
			continue
		if not Rect2(Vector2.ZERO, viewport).encloses(icon.get_global_rect()) and outside.size() < 4:
			outside.append("%s at %s" % [icon.name, str(icon.get_global_rect())])
	_expect(outside.is_empty(), "facility layout %s: published art is laid out outside the frame: %s" % [label, str(outside)], failures)


func _layout_fingerprint() -> String:
	return "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"


func _proxy_unlocked_snapshot() -> Dictionary:
	return _proxy_snapshot(true, true)


func _proxy_snapshot(use_distance_gait: bool, unlocked: bool) -> Dictionary:
	var snapshot := _real_loadout_snapshot()
	var movement_id := "distance_keeping_gait" if use_distance_gait else "direct_gait"
	var catalog := {
		"near_enemy_horizon": {"id": "near_enemy_horizon", "name": "Near-Enemy Sight", "slot": "perception", "protocol": "Identify the nearest 1 visible valid enemy every 1 second"},
		"marking_prism": {"id": "marking_prism", "name": "Mark Prism", "slot": "perception", "protocol": "Distinguish marked targets, elites, and bosses; retain 2 candidates"},
		"direct_gait": {"id": "direct_gait", "name": "Direct-Approach Legs", "slot": "movement", "protocol": "Follow the shortest viable direction toward the current target to maintain skill slot 1's fixed safe band: approach when too far, retreat at point-blank range, and stop inside the band"},
		"distance_keeping_gait": {"id": "distance_keeping_gait", "name": "Range-Keeping Legs", "slot": "movement", "protocol": "Continuously maintain the player's near, medium, or far range band; bands follow Piercing Arrow's actual range and avoid oscillation at their edges", "settings_schema": {"type": "object"}, "default_settings": {"distance_band": "mid"}},
		"single_key_execution": {"id": "single_key_execution", "name": "Single-Key Executor", "slot": "execution", "protocol": "Cast skill slot 1 when target, resources, and cooldown permit"},
		"short_trace_memory": {"id": "short_trace_memory", "name": "Short-Trace Memory", "slot": "memory", "protocol": "Store the current target and last committed action"},
		"orbit_gait": {"id": "orbit_gait", "name": "Circling Hunt Legs", "slot": "movement", "protocol": "Should Not Display"},
		"state_parser": {"id": "state_parser", "name": "State Parser", "slot": "perception", "protocol": "Should Not Display"},
	}
	var inventory: Array = []
	for core_id in ["near_enemy_horizon", "direct_gait", "distance_keeping_gait", "single_key_execution", "short_trace_memory"]:
		var item: Dictionary = (catalog[core_id] as Dictionary).duplicate(true)
		item["rarity"] = "white"
		item["type"] = "proxy_core"
		item["source_contract"] = "threshold_colossus"
		inventory.append(item)
	snapshot["proxy"] = {
		"build": {
			"cores": ["near_enemy_horizon", movement_id, "single_key_execution", "short_trace_memory"],
			"settings": {"distance_keeping_gait": {"distance_band": "mid"}} if use_distance_gait else {},
			"attachments": ["", "", ""],
		},
		"unlocked": unlocked,
		"inventory": inventory,
		"catalog": catalog,
		"resolved_build": {"semantic_fingerprint": _layout_fingerprint()},
	}
	snapshot["progression"] = {
		"threshold_colossus_defeated": unlocked,
		"proxy_unlocked": unlocked,
		"auto_contract_wins": 2 if unlocked else 0,
		"early_game_complete": unlocked,
	}
	return snapshot


## The real loadout snapshot plus N extra main-hand items, optionally with one
## very long base name on the previewed candidate. Every extra item is a legal
## same-slot candidate, so the page lays out a real long list instead of a short
## curated one; no new action or state is introduced by the fixture.
func _large_inventory_snapshot(extra_count: int, long_name: String = "") -> Dictionary:
	var snapshot := _real_loadout_snapshot()
	var inventory: Array = (snapshot["inventory_equipment"] as Array).duplicate(true)
	if not long_name.is_empty():
		(snapshot["base_items"] as Dictionary)["long_name_bow"] = {
			"id": "long_name_bow",
			"name": long_name,
			"slot": "main_hand",
			"modifiers": [{"parameter": "damage", "operation": "multiply", "value": 1.0}],
		}
		inventory[1] = {
			"instance_id": "loot:bow/2",
			"base_item_id": "long_name_bow",
			"slot": "main_hand",
			"affixes": [],
			"rune_id": "",
			"law_id": "",
		}
	for index in extra_count:
		var use_long_name := not long_name.is_empty() and index % 2 == 0
		inventory.append({
			"instance_id": "loot:bow/bulk_%03d" % index,
			"base_item_id": "long_name_bow" if use_long_name else "swift_recurve_bow",
			"slot": "main_hand",
			"affixes": [{"family_id": "piercing_continuation", "tier": 2}],
			"rune_id": "",
			"law_id": "",
		})
	snapshot["inventory_equipment"] = inventory
	return snapshot


func _snapshot(verified: bool) -> Dictionary:
	return {
		"ok": true,
		"available_builds": [{
			"id": "exponential", "name": "Exponential", "p": 0.61, "selected": true, "verified": verified,
			"state": "EXPONENTIAL", "R": 1.22, "skill_id": "piercing_arrow",
			"rune": {"name": "Breeding Split"}, "law_id": "pack_hunt_mark",
			"equipment": {"calibration": "Growth Chance Calibration +0.12"},
		}],
		"active_build": {"id": "exponential", "name": "Exponential"},
		"training": {"reports_by_fingerprint": {}},
		"proxy": {"unlocked": false, "cores": ["nearest_enemy", "direct_gait", "single_key_execution", "short_trace_memory"]},
		"progression": {"threshold_colossus_defeated": false, "proxy_unlocked": false, "auto_contract_wins": 0, "early_game_complete": false},
	}


func _real_loadout_snapshot() -> Dictionary:
	var snapshot := _snapshot(false)
	snapshot["equipment_slots"] = ["head", "chest", "pants", "leg_armor", "gloves", "bracers", "belt", "main_hand", "off_hand", "ring_1", "ring_2", "necklace"]
	snapshot["prototype_open_slots"] = ["main_hand", "off_hand", "gloves", "ring_1"]
	snapshot["base_items"] = {
		"ashwood_longbow": {"id": "ashwood_longbow", "name": "Ash Longbow", "slot": "main_hand", "modifiers": [{"parameter": "damage", "operation": "multiply", "value": 1.12}]},
		"swift_recurve_bow": {"id": "swift_recurve_bow", "name": "Swiftstring Recurve", "slot": "main_hand", "modifiers": [{"parameter": "v", "operation": "multiply", "value": 1.1}]},
		"turnfeather_gloves": {"id": "turnfeather_gloves", "name": "Guiding Fletch Gloves", "slot": "gloves", "modifiers": [{"parameter": "turn", "operation": "multiply", "value": 0.94}]},
		"vitality_ring": {"id": "vitality_ring", "name": "Vitality Ring", "slot": "ring_1", "modifiers": [{"parameter": "max_health", "operation": "multiply", "value": 1.12}]},
	}
	snapshot["affix_families"] = {
		"piercing_continuation": {"id": "piercing_continuation", "name": "Piercing Arrow Continuation Chance", "parameter": "p", "operation": "add", "tiers": [{"tier": 2, "value": 0.07}]},
	}
	snapshot["inventory_equipment"] = [
		{"instance_id": "equipped_main", "base_item_id": "ashwood_longbow", "slot": "main_hand", "affixes": [{"family_id": "piercing_continuation", "tier": 2}], "rune_id": "breeding_split", "law_id": "pack_hunt_mark"},
		{"instance_id": "loot:bow/2", "base_item_id": "swift_recurve_bow", "slot": "main_hand", "affixes": [], "rune_id": "", "law_id": ""},
		{"instance_id": "equipped_gloves", "base_item_id": "turnfeather_gloves", "slot": "gloves", "affixes": [], "rune_id": "", "law_id": ""},
		{"instance_id": "equipped_ring", "base_item_id": "vitality_ring", "slot": "ring_1", "affixes": [], "rune_id": "", "law_id": ""},
	]
	var equipped := {
		"head": "", "chest": "", "pants": "", "leg_armor": "", "gloves": "equipped_gloves", "bracers": "",
		"belt": "", "main_hand": "equipped_main", "off_hand": "", "ring_1": "equipped_ring", "ring_2": "", "necklace": "",
	}
	snapshot["active_build"] = {"skills": ["piercing_arrow", "", ""], "equipped_item_ids": equipped, "runes": [], "laws": [], "preset_id": "exponential"}
	snapshot["resolved_build"] = {
		"ok": true,
		"final_parameters": {"p": 0.61, "T": 34.0, "v": 682.0, "d": 165.0, "turn": 0.16, "damage": 160.0, "max_health": 112.0},
		"parameter_sources": {"p": [{"source_kind": "character_base"}, {"source_kind": "affix"}]},
		"connected_interfaces": ["breedable_event", "branch_target_history"],
		"missing_interfaces": ["lineage_lifetime_pause"],
		"build_fingerprint": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
		"growth_classification": "exponential",
	}
	snapshot["equip_previews"] = {
		"loot:bow/2": {
			"ok": true,
			"final_parameters": {"p": 0.54, "T": 34.0, "v": 750.2, "d": 165.0, "turn": 0.16, "damage": 160.0, "max_health": 112.0},
			"interfaces_gained": ["quick_draw"],
			"interfaces_lost": ["breedable_event", "branch_target_history"],
			"tags_gained": ["swift"],
			"tags_lost": ["breed"],
		},
	}
	return snapshot


func _salvage_snapshot() -> Dictionary:
	var snapshot := _real_loadout_snapshot()
	var inventory: Array = (snapshot["inventory_equipment"] as Array).duplicate(true)
	inventory.append({"instance_id": "loot:bow/3", "base_item_id": "swift_recurve_bow", "slot": "main_hand", "affixes": [], "rune_id": "", "law_id": ""})
	inventory.append({"instance_id": "loot:bow/4", "base_item_id": "swift_recurve_bow", "slot": "main_hand", "affixes": [], "rune_id": "", "law_id": ""})
	snapshot["inventory_equipment"] = inventory
	snapshot["salvage_previews"] = {
		"equipped_main": {"ok": true, "operation": "inscribe", "amount": 1, "equipped_slot": "main_hand"},
		"loot:bow/2": {"ok": true, "operation": "inscribe", "amount": 1},
		"loot:bow/3": {"ok": true, "operation": "rewrite", "amount": 2},
		"loot:bow/4": {"ok": true, "operation": "refine", "amount": 1},
	}
	return snapshot


func _forge_snapshot(unlocked: bool, revealed := false, selected_candidate_id := "") -> Dictionary:
	var real := _real_loadout_snapshot()
	var target: Dictionary = (real.inventory_equipment as Array)[0].duplicate(true)
	target["base_name"] = "Ash Longbow"
	target.affixes[0]["family_name"] = "Piercing Arrow Continuation Chance"
	var other: Dictionary = (real.inventory_equipment as Array)[1].duplicate(true)
	other["base_name"] = "Swiftstring Recurve"
	# Two same-base twins of Ash Longbow that differ only by affix versus rune, to pin
	# the compact difference line on the forge inventory target buttons.
	var twin_affix: Dictionary = (real.inventory_equipment as Array)[0].duplicate(true)
	twin_affix["instance_id"] = "loot:bow/6"
	twin_affix["base_name"] = "Ash Longbow"
	twin_affix["affixes"] = [{"family_id": "maximum_health", "family_name": "Maximum Health", "tier": 3}]
	twin_affix["rune_id"] = ""
	twin_affix["law_id"] = ""
	var twin_rune: Dictionary = (real.inventory_equipment as Array)[0].duplicate(true)
	twin_rune["instance_id"] = "loot:bow/7"
	twin_rune["base_name"] = "Ash Longbow"
	twin_rune["affixes"] = []
	twin_rune["rune_id"] = "breeding_split"
	twin_rune["law_id"] = ""
	var result_one := target.duplicate(true)
	result_one.erase("base_name")
	result_one["affixes"] = [{"family_id": "maximum_health", "tier": 3}]
	var result_one_view := target.duplicate(true)
	result_one_view["affixes"] = [{"family_id": "maximum_health", "family_name": "Maximum Health", "tier": 3}]
	var result_two := target.duplicate(true)
	result_two.erase("base_name")
	result_two["affixes"] = [{"family_id": "projectile_lifetime", "tier": 3}]
	var result_two_view := target.duplicate(true)
	result_two_view["affixes"] = [{"family_id": "projectile_lifetime", "family_name": "Arrow Lifetime", "tier": 3}]
	var candidates := [
		{"candidate_id": "candidate-1", "sequence_number": 1, "cost": 1, "operation": "rewrite", "affected_affix_index": 0,
			"previous_family_name": "Piercing Arrow Continuation Chance", "previous_tier": 2, "family_id": "maximum_health", "family_name": "Maximum Health", "tier": 3, "result_item": result_one, "result_item_view": result_one_view,
			"target_is_equipped": true, "preview_impact": "current_build_immediate",
			"build_comparison": {"current_parameters": {"p": 0.61, "T": 34.0, "v": 682.0, "d": 165.0, "turn": 0.16, "damage": 160.0, "critical_chance": 0.05, "max_health": 112.0},
				"result_parameters": {"p": 0.54, "T": 34.0, "v": 682.0, "d": 165.0, "turn": 0.15, "damage": 160.0, "critical_chance": 0.08, "max_health": 140.0}, "interfaces_gained": ["breedable_event"], "interfaces_lost": []}},
		{"candidate_id": "candidate-2", "sequence_number": 2, "cost": 2, "operation": "rewrite", "affected_affix_index": 0,
			"previous_family_name": "Piercing Arrow Continuation Chance", "previous_tier": 2, "family_id": "projectile_lifetime", "family_name": "Arrow Lifetime", "tier": 3, "result_item": result_two, "result_item_view": result_two_view,
			"target_is_equipped": true, "preview_impact": "current_build_immediate",
			"build_comparison": {"current_parameters": {"p": 0.61, "T": 34.0, "v": 682.0, "d": 165.0, "turn": 0.16, "damage": 160.0, "critical_chance": 0.05, "max_health": 112.0},
				"result_parameters": {"p": 0.68, "T": 36.0, "v": 700.0, "d": 180.0, "turn": 0.14, "damage": 175.0, "critical_chance": 0.1, "max_health": 112.0}, "interfaces_gained": ["breedable_event"], "interfaces_lost": []}},
	]
	return {
		"unlocked": unlocked,
		"locked_reason": "Complete Main Quest 04 to unlock Law Token forging" if not unlocked else "",
		"inventory_items": [target.duplicate(true), other, twin_affix, twin_rune],
		"target_item": target,
		"target_instance_id": "equipped_main",
		"affixes": target.affixes.duplicate(true),
		"affix_families": real.affix_families.duplicate(true),
		"operation": "rewrite" if revealed else "inscribe",
		"blocked": false,
		"blocked_reason": "",
		"revision": 1,
		"law_tallies": {"inscribe": 3, "rewrite": 3, "refine": 2},
		"session": {
			"state": "selected" if not selected_candidate_id.is_empty() else "revealed",
			"session_id": "forge-session-1", "target_instance_id": "equipped_main",
			"operation": "rewrite", "candidates": candidates,
			"selected_candidate_id": selected_candidate_id, "revealed_count": 2,
			"affordable_count": 2, "has_more": true,
		} if revealed else {},
	}


func _progression_icon_fixture() -> ProgressionIconFixture:
	var fixture := ProgressionIconFixture.new()
	var talent_sheet := Image.create(480, 32, false, Image.FORMAT_RGBA8)
	var law_sheet := Image.create(96, 32, false, Image.FORMAT_RGBA8)
	talent_sheet.fill(Color(0.2, 0.4, 0.5, 1.0))
	law_sheet.fill(Color(0.5, 0.4, 0.2, 1.0))
	fixture.textures = {
		fixture.ATLAS_DIRECTORY.path_join("ranger_talents.png"): ImageTexture.create_from_image(talent_sheet),
		fixture.ATLAS_DIRECTORY.path_join("law_tokens.png"): ImageTexture.create_from_image(law_sheet),
	}
	var sprites: Array = []
	var talent_ids := [
		"ranger_steady_string", "ranger_long_breath", "ranger_keen_eye", "ranger_light_step", "ranger_recovery_pose",
		"ranger_close_turn", "ranger_continuation_calibration", "ranger_defocused_tracking", "ranger_wind_slice_stance", "ranger_lineage_sense",
		"ranger_last_generation_loading", "ranger_three_skill_rhythm", "ranger_wind_walker", "ranger_critical_hunter", "ranger_near_far_hunting",
	]
	for index in talent_ids.size():
		sprites.append({"id": "talent.%s" % talent_ids[index], "texture": "ranger_talents.png", "type": "ui_icon", "anchor": [16, 16], "rect": [32 * index, 0, 32, 32]})
	var operations: Array[String] = ["inscribe", "rewrite", "refine"]
	for index in operations.size():
		var operation: String = operations[index]
		sprites.append({"id": "law_token.%s" % operation, "texture": "law_tokens.png", "type": "ui_icon", "anchor": [16, 16], "rect": [32 * index, 0, 32, 32]})
	fixture.atlas = {"schema_version": 1, "sprites": sprites}
	return fixture


func _training_snapshot(verified: bool, fingerprint: String, last_report: Dictionary) -> Dictionary:
	var reports_by_fingerprint := {}
	if verified and not last_report.is_empty():
		var report_fingerprint := String(last_report.get("build_fingerprint", ""))
		if not report_fingerprint.is_empty():
			reports_by_fingerprint[report_fingerprint] = last_report.duplicate(true)
	return {
		"ok": true,
		"active_build": {"preset_id": "exponential", "skills": ["piercing_arrow", "", ""], "runes": [], "laws": []},
		"resolved_build": {
			"ok": true,
			"final_parameters": {"p": 0.61, "T": 34.0, "v": 682.0, "d": 165.0, "turn": 0.16, "damage": 160.0, "max_health": 112.0},
			"connected_interfaces": ["breedable_event", "branch_target_history"],
			"missing_interfaces": ["lineage_lifetime_pause"],
			"build_fingerprint": fingerprint,
			"growth_classification": "exponential",
		},
		"training": {
			"reports_by_fingerprint": reports_by_fingerprint,
		},
	}


func _training_report(fingerprint: String) -> Dictionary:
	return {
		"preset_id": "exponential",
		"build_fingerprint": fingerprint,
		"p": 0.61,
		"R": 1.22,
		"g": 3,
		"event_count": 12.0,
		"event_count_display": "12",
		"event_count_value": {"layer": 1, "magnitude": 12.0},
		"state": "exponential",
		"report": "p=0.61, R=1.22, g=3, events=12: exponential",
		"training_seed": 42,
		"growth_curve": [
			{"generation": 0, "events_display": "1"},
			{"generation": 20, "events_display": "12"},
		],
		"action": "Keep forecasting with this build",
	}


func _expect_no_calibration_copy(text: String, failures: Array[String]) -> void:
	for term: String in ["Three States", "Preset A", "Preset B", "Preset C", "Calibration Preset", "Power", "TTK", "Recommended", "Formula"]:
		_expect(not text.contains(term), "facility: training view leaked forbidden calibration copy '%s'" % term, failures)


func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print("PASS  test_facility_screen.gd")
		quit(0)
		return
	for failure in failures:
		printerr("- %s" % failure)
	quit(1)


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)


## Whether two rects describe the same box within one pixel: the layout rounds to
## integers, and a relation that moved by a whole pixel is a different composition.
func _same_rect(left: Rect2, right: Rect2) -> bool:
	return left.position.distance_to(right.position) <= 1.0 and left.size.distance_to(right.size) <= 1.0


## Whether two controls start on the same row: the concept's rows are shared edges,
## not merely nearby ones.
func _same_top(left: Control, right: Control) -> bool:
	return absf(left.get_global_rect().position.y - right.get_global_rect().position.y) <= 1.0


## Whether a control is fully inside the first screen AND inside every clipping
## ancestor between it and the page: a region that hides a required node behind its own
## scroll counts as clipped, not as visible.
func _inside_first_screen(node: Control, viewport: Vector2) -> bool:
	if not node.is_visible_in_tree():
		return false
	var rect := node.get_global_rect()
	if not Rect2(Vector2.ZERO, viewport).encloses(rect):
		return false
	var parent := node.get_parent()
	while parent is Control:
		var control := parent as Control
		if control.clip_contents and not control.get_global_rect().encloses(rect):
			return false
		parent = control.get_parent()
	return true
