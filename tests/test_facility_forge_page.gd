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
	var snapshot := _snapshot(false)
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
	root.remove_child(screen)
	screen.free()
	for child in root.get_children():
		child.free()
	await process_frame
	await process_frame
	_finish(failures, "test_facility_forge_page.gd")
