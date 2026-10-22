extends SceneTree

## Interaction state of the loadout workspace: slot focus, backpack pagination,
## hover/pinning, and complete build reference. The reference is a modal dialog;
## closing it must preserve the candidate page and return focus to its opener.
## Raw item fields remain confined to F10.
##
## RUN: godot --headless --path . --script res://tests/unit/test_facility_detail_state.gd

const FacilityScreenScript = preload("res://src/presentation/facility_screen.gd")
const FacilityFixture = preload("res://tests/test_facility_screen.gd")

## Enough same-slot candidates to exercise several real backpack pages.
const EXTRA_CANDIDATES := 30
## A second populated open slot, so switching the compared slot is a real switch
## between two candidate lists rather than to an empty one.
const OFF_HAND_CANDIDATES := 6
## A long internal instance id must stay outside player-facing details.
const LONG_ID := "stress_drop_00_0123456789abcdef0123456789abcdef0123456789abcdef"
## Where a page offsets its own workspace offset is only meaningful above the clamp; a
## request the clamp shortens before the rebuild is caught by the third test.
const PAGE_REQUEST := 600

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _check_new_forge_session_flow()
	await _check_forge_pagination_and_count_copy()
	await _check_backpack_hover_and_activation_persistence()
	await _check_equipment_comparison_state()
	await _check_readable_filters_and_skill_entry()
	await _check_candidate_region_survives_folding()
	await _check_page_offsets_survive_the_switches()
	await _check_focus_survives_the_switches()
	await _check_focus_survives_a_reorder()
	await _check_workspace_offset_restored_and_reset_by_switching()
	await _check_forge_semantic_focus()
	# Flush queued fixture and embedded-dialog deletion before SceneTree shutdown.
	for child in root.get_children():
		child.free()
	await process_frame
	await process_frame
	_finish()


func _check_backpack_hover_and_activation_persistence() -> void:
	var fixtures := FacilityFixture.new()
	var host := Control.new()
	host.size = Vector2(1280, 720)
	root.add_child(host)
	var screen = FacilityScreenScript.new()
	host.add_child(screen)
	screen.present("loadout", {}, {}, "", fixtures._real_loadout_snapshot())
	await _settle_frames()
	var button := screen.find_child("BackpackItem_loot_bow_2", true, false) as Button
	var detail := screen.backpack_detail() as Control
	_expect(button != null and detail != null and not detail.visible,
		"detail state: loadout detail was not quiet before hover/focus")
	if button != null and detail != null:
		button.mouse_entered.emit()
		await _settle_frames()
		_expect(detail.visible, "detail state: plain hover did not reveal the shared detail pane")
		detail.mouse_entered.emit()
		button.mouse_exited.emit()
		await _settle_frames()
		_expect(detail.visible and screen.get_action_button("FullItemDetails_loot_bow_2") != null,
			"detail state: crossing from an icon into its actions destroyed the hover detail")
		detail.mouse_exited.emit()
		await _settle_frames()
		_expect(not detail.visible, "detail state: unpinned hover detail did not hide after leaving both regions")
		button.pressed.emit()
		button.mouse_exited.emit()
		detail.mouse_exited.emit()
		await _settle_frames()
		_expect(detail.visible and screen.get_action_button("Equip_loot_bow_2") != null,
			"detail state: click/controller activation did not pin inspection and actions")
	fixtures.free()
	host.queue_free()
	await process_frame


## Changed numbers belong to the candidate's local scroll; primary actions and
## backpack pagination remain usable while reading the last change and details.
func _check_equipment_comparison_state() -> void:
	var fixtures := FacilityFixture.new()
	var data: Dictionary = fixtures._real_loadout_snapshot()
	data.resolved_build.final_parameters["critical_chance"] = 0.05
	data.equip_previews["loot:bow/2"].final_parameters = {
		"p": 0.54, "damage": 140.0, "max_health": 120.0, "T": 40.0,
		"v": 750.2, "d": 180.0, "turn": 0.12, "critical_chance": 0.08,
	}
	var host := Control.new()
	root.add_child(host)
	var screen = FacilityScreenScript.new()
	host.add_child(screen)
	var actions: Array[Dictionary] = []
	screen.action_requested.connect(func(facility: String, action: String, payload: Dictionary) -> void:
		actions.append({"facility": facility, "action": action, "payload": payload.duplicate(true)})
	)
	for size: Vector2 in [Vector2(1280, 720), Vector2(1600, 900)]:
		host.size = size
		screen.present("loadout", {}, {}, "", data)
		await _settle_frames()
		var item := screen.find_child("BackpackItem_loot_bow_2", true, false) as Button
		_expect(item != null, "detail state: comparison candidate has no backpack focus target")
		if item == null:
			continue
		item.grab_focus()
		item.pressed.emit()
		await _settle_frames()
		var grid := screen.find_child("CandidateDecision_loot_bow_2", true, false) as GridContainer
		var local_scroll := screen.find_child("CandidateFactsRow_loot_bow_2", true, false) as ScrollContainer
		var equip: Button = screen.get_action_button("Equip_loot_bow_2")
		var full: Button = screen.get_action_button("FullItemDetails_loot_bow_2")
		var detail := screen.backpack_detail() as Control
		_expect(grid != null and grid.columns == 4 and fixtures._comparison_text(grid).begins_with("Build Stats\nCurrent\nWhen Equipped\n"),
			"detail state: comparison columns lost their current/replacement meaning")
		for row in [
			["Continuation Chance", "61%", "↓ 54%", FacilityScreenScript.ShellThemeScript.WARNING],
			["Damage", "160", "↓ 140", FacilityScreenScript.ShellThemeScript.WARNING],
			["Health", "112", "↑ 120", FacilityScreenScript.ShellThemeScript.PROXY],
			["Arrow Chain Lifetime", "34s", "↑ 40s", FacilityScreenScript.ShellThemeScript.PROXY],
			["Arrow Speed", "682", "↑ 750.2", FacilityScreenScript.ShellThemeScript.PROXY],
			["Range", "165", "↑ 180", FacilityScreenScript.ShellThemeScript.PROXY],
			["Turn Time", "0.16s", "↓ 0.12s", FacilityScreenScript.ShellThemeScript.PROXY],
			["Critical Chance", "5%", "↑ 8%", FacilityScreenScript.ShellThemeScript.PROXY],
		]:
			fixtures._expect_comparison_row(grid, row[0], row[1], row[2], row[3], failures)
		_expect(grid != null and grid.get_child_count() == 36,
			"detail state: comparison omitted one of the eight authoritative changes")
		_expect(local_scroll != null and local_scroll.is_ancestor_of(grid)
			and local_scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED,
			"detail state: all changes must stay in the local vertical scroll")
		for control: Control in [local_scroll, equip, full]:
			_expect(control != null and fixtures._inside_first_screen(control, size)
				and detail != null and detail.get_global_rect().encloses(control.get_global_rect()),
				"detail state: comparison viewport or primary action escaped " + str(size))
		if local_scroll != null and grid != null:
			var bar := local_scroll.get_v_scroll_bar()
			_expect(bar.max_value > bar.page, "detail state: eight changed attributes did not get a local reading scroll")
			var last := grid.get_child(grid.get_child_count() - 1) as Label
			local_scroll.ensure_control_visible(last)
			await _settle_frames()
			_expect(last != null and local_scroll.get_global_rect().encloses(last.get_global_rect()),
				"detail state: local scroll could not reach the last changed attribute")
			local_scroll.scroll_vertical = int(bar.max_value - bar.page)
			await _settle_frames()
			var tail := screen.find_child("InterfaceLost", true, false) as Label
			_expect(tail != null and tail.text.contains("Lost: Breedable Child Arrows, Branch Target History")
				and detail.get_global_rect().encloses(tail.get_global_rect())
				and tail.get_global_rect().end.y <= local_scroll.get_global_rect().position.y,
				"detail state: interface losses must remain visible above the scrolling numbers")
			_expect(equip != null and full != null and fixtures._inside_first_screen(equip, size) and fixtures._inside_first_screen(full, size),
				"detail state: reading the last change moved the primary actions")
		var backpack := screen.find_child("EquipmentBackpack", true, false)
		var page_before: int = backpack.page_index()
		if full != null:
			full.grab_focus()
			full.pressed.emit()
			await _settle_frames()
			var text := screen.find_child("ItemDetailText", true, false) as Label
			_expect(text != null and text.text.contains("Piercing Arrow Continuation Chance: 61% → 54%")
				and text.text.contains("Turn Time (Lower Is Better): 0.16 s → 0.12 s")
				and text.text.contains("Interfaces Gained: Unknown Interface (quick_draw)")
				and text.text.contains("Interfaces Lost: Breedable Child Arrows, Branch Target History"),
				"detail state: complete equipment details lost numeric or interface gains/losses")
			await _close_build_reference(screen)
			_expect(backpack.page_index() == page_before and _focus_owner_name(screen) == "FullItemDetails_loot_bow_2",
				"detail state: closing equipment details lost page or opener focus")
		_expect(actions.is_empty(), "detail state: inspection, scroll, or details emitted an equip action")
		if equip != null:
			equip.pressed.emit()
			_expect(actions == [{"facility": "loadout", "action": "equip_item", "payload": {"instance_id": "loot:bow/2"}}],
				"detail state: comparison changed the candidate equip intent")
			actions.clear()
			var equipped_data := data.duplicate(true)
			equipped_data.active_build.equipped_item_ids.main_hand = "loot:bow/2"
			screen.present("loadout", {}, {}, "Equipped", equipped_data)
			await _settle_frames()
			screen.call("_finish_loadout_backpack_exit")
			await _settle_frames()
			var equipped_name := screen.find_child("BackpackDetailName", true, false) as Label
			_expect(screen.backpack_detail().visible and equipped_name != null and equipped_name.text.begins_with("Equipped · "),
				"detail state: equipped item vanished when the authoritative snapshot refreshed")
			_expect(screen.get_action_button("Equip_loot_bow_2") == null and actions.is_empty(),
				"detail state: equipped result retained equip action or emitted another domain intent")
	fixtures.free()
	host.queue_free()
	await process_frame


func _check_forge_pagination_and_count_copy() -> void:
	var fixtures := FacilityFixture.new()
	var host := Control.new()
	root.add_child(host)
	var screen := FacilityScreenScript.new()
	host.add_child(screen)
	for operation in ["inscribe", "rewrite", "refine"]:
		var title := String(FacilityScreenScript.FORGE_TRACK_TITLES[operation])
		_expect(screen._law_token_name(operation, 1) == title + " Law Token"
			and screen._law_token_name(operation, 2) == title + " Law Tokens",
			"counted Law Token copy lost its singular/plural form")
	for dimensions in [Vector2(1280, 720), Vector2(1600, 900)]:
		host.size = dimensions
		for cost in [1, 2]:
			screen.present("forge", {}, {}, "", fixtures._forge_snapshot(true, true, "candidate-%d" % cost))
			await _settle_frames()
			var token_name := "Rewrite Law Token" if cost == 1 else "Rewrite Law Tokens"
			var browse := screen.find_child("ForgeBrowseSelectionState", true, false) as Label
			var confirm: Button = screen.get_action_button("ForgeConfirmSelection")
			_expect(browse != null and browse.text.contains("Selecting costs %d %s\n" % [cost, token_name])
				and confirm != null and confirm.text == "Confirm Commit · Spend %d %s" % [cost, token_name],
				"forge browse and commit did not display the exact cost with natural counted-token grammar")
			for spec in [["ForgePreviousCandidate", "Prev", "Previous Candidate"], ["ForgeNextCandidate", "Next", "Next Candidate"]]:
				var button: Button = screen.get_action_button(spec[0])
				_expect(button != null and button.text == spec[1] and button.tooltip_text == spec[2]
					and button.autowrap_mode == TextServer.AUTOWRAP_OFF,
					"forge pager lost its concise single-line wording or full tooltip")
				if button != null:
					var width := button.get_theme_font("font").get_string_size(button.text,
						HORIZONTAL_ALIGNMENT_LEFT, -1, button.get_theme_font_size("font_size")).x
					var skin := button.get_theme_stylebox("disabled" if button.disabled else "normal")
					_expect(width <= button.size.x - skin.get_minimum_size().x
						and button.get_combined_minimum_size().y <= button.size.y
						and host.get_global_rect().encloses(button.get_global_rect()),
						"forge pager text or border does not fit at %s" % dimensions)
	host.free()
	fixtures.free()


func _check_new_forge_session_flow() -> void:
	var fixtures := FacilityFixture.new()
	var screen = FacilityScreenScript.new()
	root.add_child(screen)
	var actions: Array[Dictionary] = []
	screen.action_requested.connect(func(facility_id: String, action_id: String, payload: Dictionary) -> void:
		actions.append({"facility": facility_id, "action": action_id, "payload": payload.duplicate(true)})
	)
	screen.present("forge", {}, {}, "", fixtures._forge_snapshot(true))
	await _settle_frames()
	_expect(screen.get_visible_text().contains("No future has been forecast") and not screen.get_visible_text().contains("Candidate "),
		"forge session: unrevealed snapshot exposed candidates")
	_expect(actions.is_empty(), "forge session: first present emitted a domain action")
	screen.present("forge", {}, {}, "", fixtures._forge_snapshot(true))
	await _settle_frames()
	_expect(actions.is_empty(), "forge session: repeated present emitted a domain action")
	actions.clear()
	var rewrite: Button = screen.get_action_button("ForgeOperation_rewrite")
	if rewrite != null: rewrite.pressed.emit()
	_expect(actions == [{"facility": "forge", "action": "select_forge_operation", "payload": {"operation": "rewrite", "revision": 1}}],
		"forge session: operation switch emitted more than one intent")
	var rewrite_snapshot: Dictionary = fixtures._forge_snapshot(true)
	rewrite_snapshot["operation"] = "rewrite"
	_expect(not rewrite_snapshot.has("affix_index"),
		"forge session: operation snapshot retained affix_index")
	screen.present("forge", {}, {}, "", rewrite_snapshot)
	await _settle_frames()
	actions.clear()
	var reveal: Button = screen.get_action_button("ForgeReveal")
	if reveal != null: reveal.pressed.emit()
	_expect(actions == [{"facility": "forge", "action": "forge_reveal", "payload": {"revision": 1}}],
		"forge session: reveal carried duplicated context or emitted more than once")
	var empty_tallies: Dictionary = fixtures._forge_snapshot(true)
	empty_tallies["law_tallies"] = {"inscribe": 1, "rewrite": 0, "refine": 1}
	empty_tallies["operation"] = "rewrite"
	_expect(not empty_tallies.has("affix_index"),
		"forge session: blocked operation snapshot retained affix_index")
	screen.present("forge", {}, {}, "", empty_tallies)
	await _settle_frames()
	var no_rewrite: Button = screen.get_action_button("ForgeOperation_rewrite")
	await _settle_frames()
	var blocked_reveal: Button = screen.get_action_button("ForgeReveal")
	_expect(blocked_reveal != null and blocked_reveal.disabled and screen.get_visible_text().contains("No Rewrite Law Tokens"),
		"forge session: zero law tallies did not expose the insufficient-tallies boundary")
	actions.clear()
	var revealed: Dictionary = fixtures._forge_snapshot(true, true)
	screen.present("forge", {}, {}, "", revealed)
	await _settle_frames()
	var next: Button = screen.get_action_button("ForgeNextCandidate")
	if next != null: next.pressed.emit()
	_expect(actions.is_empty(),
		"forge session: browsing emitted a candidate-selection action")
	var select: Button = screen.get_action_button("ForgeSelectCandidate")
	_expect(select != null and screen.get_action_button("ForgeConfirmSelection") == null,
		"forge session: unselected browse did not expose only ForgeSelectCandidate")
	if select != null: select.pressed.emit()
	_expect(actions == [{"facility": "forge", "action": "forge_select_candidate", "payload": {"session_id": "forge-session-1", "candidate_id": "candidate-2"}}],
		"forge session: explicit selection did not send the full candidate id")
	actions.clear()
	screen.present("forge", {}, {}, "", fixtures._forge_snapshot(true, true, "candidate-2"))
	await _settle_frames()
	var text := screen.get_visible_text()
	_expect(text.contains("Candidate 2 / 2 · Selecting costs 2 Rewrite Law Tokens")
		and screen.find_child("ForgeBuildComparison", true, false) != null,
		"forge session: restored result lost its cost or compact build comparison")
	var full := screen.get_action_button("ForgeFullResultDetail")
	_expect(full != null, "forge session: complete result details are inaccessible")
	if full != null:
		full.pressed.emit()
		var full_text := (screen.find_child("ItemDetailText", true, false) as Label).text
		_expect(full_text.contains("Critical Chance") and full_text.contains("Turn Time (Lower Is Better)")
			and full_text.contains("Base Stats") and not full_text.contains("Destiny Dice") and not full_text.contains("REROLL"),
			"forge session: restored result details lost the complete readable comparison")
		(screen.find_child("ItemDetailDialog", true, false) as AcceptDialog).hide()
	var confirm: Button = screen.get_action_button("ForgeConfirmSelection")
	_expect(confirm != null and screen.get_action_button("ForgeSelectCandidate") == null,
		"forge session: authoritative selection did not replace Select with Confirm")
	if confirm != null: confirm.pressed.emit()
	_expect(actions == [{"facility": "forge", "action": "forge_commit", "payload": {"session_id": "forge-session-1"}}],
		"forge session: commit payload contains more than session_id")
	actions.clear()
	screen.present("forge", {}, {}, "", fixtures._forge_snapshot(true, true, "candidate-1"))
	await _settle_frames()
	var cancel: Button = screen.get_action_button("ForgeCancelSelection")
	if cancel != null: cancel.pressed.emit()
	_expect(actions == [{"facility": "forge", "action": "forge_cancel", "payload": {"session_id": "forge-session-1"}}]
		and screen.get_visible_text().contains("Current Future Selected · Ready to Commit"),
		"forge session: cancel did not emit once or mutated the view before an authoritative response")
	fixtures.free()
	await _end(screen)


func _check_readable_filters_and_skill_entry() -> void:
	var fixtures := FacilityFixture.new()
	var data: Dictionary = fixtures._real_loadout_snapshot()
	data["early_skill_registry"] = {"piercing_arrow": {
		"name": "Piercing Arrow", "key_bindings": ["Left Mouse Button"], "type": "Active Attack", "target_rule": "Toward the Pointer",
		"range_rule": "Affected by Targeting and Piercing Arrow Range", "full_effect": "Pierce the target and keep flying; retain the remaining pierces and record the target hit.Pierce the target and keep flying; retain the remaining pierces and record the target hit.Pierce the target and keep flying; retain the remaining pierces and record the target hit.Pierce the target and keep flying; retain the remaining pierces and record the target hit.Pierce the target and keep flying; retain the remaining pierces and record the target hit.Pierce the target and keep flying; retain the remaining pierces and record the target hit.Pierce the target and keep flying; retain the remaining pierces and record the target hit.Pierce the target and keep flying; retain the remaining pierces and record the target hit.", "cooldown_ticks": 12,
		"duration_ticks": 30, "equipment_parameters": ["p", "critical_chance"], "synergies": ["Breeding Split"], "limitations": ["Target Required"],
	}}
	(data["resolved_build"] as Dictionary)["final_parameters"]["critical_chance"] = 0.05
	(data["equip_previews"] as Dictionary)["loot:bow/2"]["final_parameters"]["critical_chance"] = 0.08
	(data["active_build"] as Dictionary)["skills"] = ["piercing_arrow", "hunter_mark", "dash"]
	var screen = FacilityScreenScript.new()
	root.add_child(screen)
	screen.present("loadout", {}, {}, "", data)
	await _settle_frames()
	var filters: Button = screen.get_action_button("CandidateFiltersToggle")
	var piercing: Button = screen.get_action_button("SkillSummary_piercing_arrow")
	var mark: Button = screen.get_action_button("SkillSummary_hunter_mark")
	var dash: Button = screen.get_action_button("SkillSummary_dash")
	var dodge: Button = screen.get_action_button("SkillSummary_basic_dodge")
	_expect(filters != null and piercing != null and mark != null and dash != null and dodge != null,
		"readable loadout: filters or the four first-screen action entries are missing")
	if piercing != null and mark != null and dash != null and dodge != null:
		_expect(piercing.text == "Piercing Arrow\nLeft-click 0.4s"
			and mark.text == "Hunter's Mark\nQ 8s"
			and dash.text == "Dash\nE 3s"
			and dodge.text == "Dodge\nShift 1.17s",
			"readable loadout: compact actions did not keep the name and key/cooldown on stable separate lines")
		_expect(not dodge.text.contains("Sh\nift")
			and screen._compact_skill_text({"name":"Roll", "key_bindings":["Space"], "cooldown_ticks":13}, 1) == "Roll\nSpace 0.43s",
			"readable loadout: a named binding can still split across lines")
		for action: Button in [piercing, mark, dash, dodge]:
			var minimum := action.get_combined_minimum_size()
			_expect(action.autowrap_mode == TextServer.AUTOWRAP_OFF and action.text.count("\n") == 1
				and minimum.x <= action.size.x + 0.5 and minimum.y <= action.size.y + 0.5,
				"readable loadout: %s needs more than two physical lines (%s minimum / %s actual)" % [
					action.name, str(minimum), str(action.size),
				])
		_expect(piercing.icon != null and mark.icon != null and dash.icon != null and dodge.icon != null,
			"readable loadout: a compact action lost its published icon")
	var skill_strip: Control = screen.find_child("LoadoutSkillStrip", true, false) as Control
	var locked_region: Control = screen.find_child("LoadoutLockedRegion", true, false) as Control
	_expect(skill_strip != null and locked_region != null and locked_region.get_global_rect().encloses(skill_strip.get_global_rect())
		and skill_strip is GridContainer and (skill_strip as GridContainer).columns == 2,
		"readable loadout: the action catalog is not the two-column start of the inventory/growth lane (%s vs %s)" % [
			"missing" if skill_strip == null else str(skill_strip.get_global_rect()),
			"missing" if locked_region == null else str(locked_region.get_global_rect()),
		])
	_expect(screen.get_action_button("LoadoutSkillDetailsToggle") == null,
		"readable loadout: the old all-skills disclosure still exists below the equipment decision")
	if filters != null: filters.pressed.emit()
	await _settle_frames()
	_expect(screen.find_child("CandidateKeywordFilter", true, false) != null
		and screen.find_child("CandidateFamilyFilter", true, false) != null
		and screen.find_child("CandidateMinimumTierFilter", true, false) != null
		and screen.find_child("CandidateRuneFilter", true, false) != null
		and screen.find_child("CandidateLawFilter", true, false) != null
		and screen.find_child("CandidateSalvageFilter", true, false) != null
		and screen.find_child("CandidateSort", true, false) != null,
		"readable loadout: required filters and sort controls are incomplete")
	var filter_dialog := screen.find_child("CandidateFilterDialog", true, false) as AcceptDialog
	if filter_dialog != null: filter_dialog.hide()
	var data_before: Dictionary = screen._facility_data.duplicate(true)
	piercing = screen.get_action_button("SkillSummary_piercing_arrow")
	mark = screen.get_action_button("SkillSummary_hunter_mark")
	if piercing != null: piercing.pressed.emit()
	await _settle_frames()
	var skill_dialog: AcceptDialog = screen.find_child("SkillDetailDialog", true, false) as AcceptDialog
	var skill_scroll: ScrollContainer = screen.find_child("SkillDetailScroll", true, false) as ScrollContainer
	var skill_text: Label = screen.find_child("SkillDetailText", true, false) as Label
	_expect(skill_dialog != null and skill_dialog.visible and skill_dialog.title.contains("Piercing Arrow")
		and skill_text != null and skill_text.text.contains("Piercing Arrow|Left Mouse Button") and skill_text.text.contains("Critical Chance")
		and skill_text.text.contains("Target Rule: ") and skill_text.text.contains("Full Effect: ")
		and skill_text.text.contains("Synergy: ") and skill_text.text.contains("Limits: ")
		and not skill_text.text.contains("Hunter's Mark|"),
		"readable loadout: one compact action did not open its complete single-skill description")
	var close_button: Button = null if skill_dialog == null else skill_dialog.get_ok_button()
	var dialog_rect := Rect2()
	if skill_dialog != null:
		dialog_rect = Rect2(Vector2(skill_dialog.position), Vector2(skill_dialog.size))
	_expect(skill_dialog != null and skill_scroll != null and skill_text != null
		and skill_dialog.size.x <= 760.0 and skill_dialog.size.y <= 500.0
		and screen.get_global_rect().encloses(dialog_rect)
		and close_button != null and close_button.is_visible_in_tree() and dialog_rect.encloses(close_button.get_global_rect())
		and skill_scroll.get_global_rect().encloses(skill_text.get_global_rect().intersection(skill_scroll.get_global_rect()))
		and skill_text.size.x <= skill_scroll.size.x
		and skill_text.text.contains("Limits: "),
		"readable loadout: skill dialog is not bounded with a visible close button and its complete copy in the named scroll region")
	if skill_scroll != null:
		var skill_bar := skill_scroll.get_v_scroll_bar()
		var scroll_end := maxf(0.0, skill_bar.max_value - skill_bar.page)
		_expect(scroll_end > 0.0, "readable loadout: complete skill copy did not overflow its internal scroll region (bar=%s text=%s)" % [str(skill_bar.max_value), str(null if skill_text == null else skill_text.size)])
		skill_scroll.scroll_vertical = int(scroll_end)
		await _settle_frames()
		_expect(skill_scroll.scroll_vertical >= int(scroll_end),
			"readable loadout: internal skill scroll could not reach the complete description's end")
	_expect(screen._facility_data == data_before,
		"readable loadout: opening or scrolling a skill description changed the page payload")
	if close_button != null:
		close_button.pressed.emit()
		await _settle_frames()
	_expect(skill_dialog == null or not skill_dialog.visible,
		"readable loadout: the fixed close button did not close the skill dialog")
	_expect(screen._facility_data == data_before,
		"readable loadout: closing a skill description changed the page payload")
	if mark != null: mark.pressed.emit()
	await _settle_frames()
	var mark_text: Label = null if skill_dialog == null else skill_dialog.find_child("SkillDetailText", true, false) as Label
	_expect(skill_dialog != null and skill_dialog.visible and skill_dialog.title.contains("Hunter's Mark")
		and mark_text != null and mark_text.text.contains("Hunter's Mark|Q") and not mark_text.text.contains("Piercing Arrow|"),
		"readable loadout: switching actions did not replace the dialog with only the selected skill")
	if skill_dialog != null: skill_dialog.hide()
	(data["active_build"] as Dictionary)["skills"] = ["piercing_arrow", "", ""]
	screen.present("loadout", {}, {}, "", data)
	await _settle_frames()
	var locked_skill: Button = screen.get_action_button("SkillSummary_empty_2")
	_expect(locked_skill != null and locked_skill.disabled and locked_skill.text == "Slot 2\nLocked"
		and locked_skill.tooltip_text.contains("unlocks through the main quest"),
		"readable loadout: a locked skill slot required hover to reveal its main-story unlock condition")
	fixtures.free()
	await _end(screen)

func _check_forge_semantic_focus() -> void:
	var fixtures := FacilityFixture.new()
	var data: Dictionary = fixtures._forge_snapshot(true)
	fixtures.free()
	var screen = FacilityScreenScript.new()
	root.add_child(screen)
	screen.present("forge", {}, {}, "", data)
	await _settle_frames()
	var action_names: Array[String] = ["ForgeOperation_rewrite"]
	for node: Node in screen.find_children("SelectForgeItem_*", "Button", true, false):
		if not (node as Button).disabled:
			action_names.append(str(node.name))
			break
	for name in action_names:
		var button: Button = screen.get_action_button(name)
		_expect(button != null and not button.disabled, "forge semantic focus action exists " + name)
		if button == null: continue
		button.grab_focus()
		screen.present("forge", {}, {}, "", data)
		await _settle_frames()
		var owner: Control = screen.get_viewport().gui_get_focus_owner()
		_expect(owner != null and str(owner.name) == name, "forge rebuild restores same semantic action " + name)
	_expect(screen.get_action_button("ForgeNextAffix") == null and screen.get_action_button("ForgePreviousAffix") == null,
		"forge semantic focus: retired affix navigation controls returned")
	var confirm: Button = screen.get_action_button("ForgeConfirmSelection")
	_expect(screen._restorable_focus(confirm).is_empty(), "forge commit must never be auto-focused by rebuild")
	screen.free()


## A candidate's own action is pinned by its name, not by its place. The list is rebuilt
## with every item moved, and the action that keeps the keyboard focus is still the one
## the player was on — never whatever moved into its position. A candidate that is gone
## leaves no focus behind instead of handing it to a destructive neighbour.
func _check_focus_survives_a_reorder() -> void:
	var fixture := _long_candidate_snapshot()
	var inventory: Array = (fixture["inventory_equipment"] as Array).duplicate(true)
	var picked := "loot:extra/17"
	var picked_action := "BackpackItem_loot_extra_17"
	var neighbour_action := "BackpackItem_loot_extra_16"
	var screen = FacilityScreenScript.new()
	root.add_child(screen)
	screen.present("loadout", {}, {}, "", fixture)
	await _settle_frames()
	var reordered: Array = []
	for index in range(inventory.size() - 1, -1, -1):
		reordered.append(inventory[index])
	fixture["inventory_equipment"] = reordered
	_expect(reordered.size() == inventory.size(), "detail state: the reorder dropped a candidate")
	var backpack = screen.find_child("EquipmentBackpack", true, false)
	if backpack != null and backpack.has_method("show_item"):
		backpack.call("show_item", picked)
		await _settle_frames()
	var picked_button := screen.get_action_button(picked_action)
	if picked_button == null:
		_expect(false, "detail state: the picked candidate has no own action to focus")
	else:
		picked_button.grab_focus()
		_expect(_focus_owner_name(screen) == picked_action,
			"detail state: the candidate action could not take keyboard focus")
		screen.present("loadout", {}, {}, "", fixture)
		await _settle_frames()
		var after := screen.get_action_button(picked_action)
		_expect(after != null, "detail state: the picked candidate lost its action in the reorder")
		_expect(_focus_owner_name(screen) == picked_action,
			"detail state: a reordered list left focus at %s instead of the candidate the player was on"
			% _focus_owner_name(screen))
		_expect(_focus_owner_name(screen) != neighbour_action,
			"detail state: focus moved to the action now sitting in the old position")
	var without_picked: Array = []
	for raw_item in (fixture["inventory_equipment"] as Array):
		if String((raw_item as Dictionary).get("instance_id", "")) != picked:
			without_picked.append(raw_item)
	fixture["inventory_equipment"] = without_picked
	screen.present("loadout", {}, {}, "", fixture)
	await _settle_frames()
	_expect(screen.find_child(picked_action, true, false) == null,
		"detail state: the removed candidate still owns a backpack cell")
	_expect(screen.get_action_button("Salvage_loot_extra_17") == null,
		"detail state: the removed candidate still offers its destructive action")
	_expect(_focus_owner_name(screen) == "none",
		"detail state: removing the focused candidate handed focus to %s" % _focus_owner_name(screen))
	await _end(screen)


## The workspace offset is restored onto the region that really owns it. The workspace is
## the page's own scroll region — an ancestor of the body, not a node below the page root
## — so a restore that searched below the root would silently leave it at the top. The
## candidate list keeps its own offset across a same-page rebuild, and starts at its own
## first row when the compared slot changes, because that is a different list.
func _check_workspace_offset_restored_and_reset_by_switching() -> void:
	var screen = FacilityScreenScript.new()
	root.add_child(screen)
	screen.present("loadout", {}, {}, "", _long_candidate_snapshot())
	await _settle_frames()
	var workspace: ScrollContainer = screen.find_child("FacilityCardsScroll", true, false)
	var candidates = screen.find_child("EquipmentBackpack", true, false)
	if workspace == null or candidates == null:
		_expect(false, "detail state: the workspace or paged candidate region is missing")
		await _end(screen)
		return
	workspace.scroll_vertical = 300
	candidates.call("set_page", 2)
	await _settle_frames()
	var workspace_before := workspace.scroll_vertical
	var candidates_before := int(candidates.call("page_index"))
	_expect(workspace_before == 0, "detail state: compact loadout unexpectedly allows full-page scrolling")
	var details: Button = screen.get_action_button("LoadoutDetailsToggle")
	if details == null:
		_expect(false, "detail state: the resolved detail toggle is missing")
	else:
		details.pressed.emit()
		await _settle_frames()
		workspace = screen.find_child("FacilityCardsScroll", true, false)
		candidates = screen.find_child("EquipmentBackpack", true, false)
		_expect(workspace != null and workspace.scroll_vertical == workspace_before,
			"detail state: the workspace offset was not restored (%s vs %d)"
			% ["missing" if workspace == null else str(workspace.scroll_vertical), workspace_before])
		_expect(candidates != null and int(candidates.call("page_index")) == candidates_before,
			"detail state: the candidate page was not restored (%s vs %d)"
			% ["missing" if candidates == null else str(candidates.call("page_index")), candidates_before])
		await _close_build_reference(screen)
	var slot_focus: Button = screen.get_action_button("SlotFocus_off_hand")
	if slot_focus == null:
		_expect(false, "detail state: the second open slot has no focus control")
	else:
		# A keyboard player is on the slot control when the switch happens; the control
		# itself is what has to be focused again afterwards, by name.
		slot_focus.grab_focus()
		slot_focus.pressed.emit()
		await _settle_frames()
		workspace = screen.find_child("FacilityCardsScroll", true, false)
		candidates = screen.find_child("EquipmentBackpack", true, false)
		_expect(candidates != null and int(candidates.call("page_index")) == 0,
			"detail state: the switched slot's candidate list did not start at its own first page (%s)"
			% ["missing" if candidates == null else str(candidates.call("page_index"))])
		_expect(_focus_owner_name(screen) == "SlotFocus_off_hand",
			"detail state: the switched slot did not keep focus: %s" % _focus_owner_name(screen))
	await _end(screen)


## Raw item fields live in F10. Opening and closing complete build details must
## keep a long candidate list on the page the player left.
func _check_candidate_region_survives_folding() -> void:
	var screen = FacilityScreenScript.new()
	root.add_child(screen)
	screen.present("loadout", {}, {}, "", _long_candidate_snapshot())
	await _settle_frames()
	var candidates = screen.find_child("EquipmentBackpack", true, false)
	if candidates == null:
		_expect(false, "detail state: a long candidate list built no paged region at all")
		_end(screen)
		return
	var page_count := int(candidates.call("page_count"))
	_expect(page_count > 3,
		"detail state: the candidate fixture is not long enough to test kept pagination (%d pages)" % page_count)
	candidates.call("set_page", 2)
	await _settle_frames()
	var before := int(candidates.call("page_index"))
	_expect(before == 2, "detail state: the candidate region could not change pages")
	_expect(_total_label_count(screen, "instance_id: %s" % LONG_ID) == 0,
		"detail state: the long raw instance id escaped the test console")
	var candidate_toggle: Button = screen.get_action_button("CandidateFieldsToggle_%s" % LONG_ID)
	_expect(candidate_toggle == null, "detail state: the retired candidate raw-field toggle returned")
	var details: Button = screen.get_action_button("LoadoutDetailsToggle")
	if details == null:
		_expect(false, "detail state: the resolved build detail toggle is missing")
	else:
		details.pressed.emit()
		await _settle_frames()
		candidates = screen.find_child("EquipmentBackpack", true, false)
		if candidates == null:
			_expect(false, "detail state: opening build details dropped the candidate page region")
		else:
			_expect(int(candidates.call("page_index")) == before,
				"detail state: opening build details moved the candidate list from page %d to %d"
				% [before, int(candidates.call("page_index"))])
		await _close_build_reference(screen)
	candidates = screen.find_child("EquipmentBackpack", true, false)
	if candidates != null:
		_expect(int(candidates.call("page_index")) == before,
			"detail state: closing build details moved the candidate list from page %d to %d"
			% [before, int(candidates.call("page_index"))])
	_expect(_total_label_count(screen, "instance_id: %s" % LONG_ID) == 0,
		"detail state: rebuilding restored a raw instance id outside F10")
	await _end(screen)


## The workspace offset across the two switches the player page offers: the slot
## focus control and the resolved-build detail toggle.
## The offset may clamp, but it may never be pulled back to the top by a rebuild.
func _check_page_offsets_survive_the_switches() -> void:
	var screen = FacilityScreenScript.new()
	root.add_child(screen)
	screen.present("loadout", {}, {}, "", _long_candidate_snapshot())
	await _settle_frames()
	var workspace: ScrollContainer = screen.find_child("FacilityCardsScroll", true, false)
	if workspace == null:
		_expect(false, "detail state: the workspace scroll region is missing")
		_end(screen)
		return
	_expect(workspace.get_v_scroll_bar().max_value <= workspace.size.y + 1.0,
		"detail state: compact loadout still requires full-page scrolling")
	workspace.scroll_vertical = PAGE_REQUEST
	await _settle_frames()
	var before := workspace.scroll_vertical
	_expect(before == 0,
		"detail state: the workspace accepted a forbidden full-page offset (%d)" % before)
	var focus_slot: Button = screen.get_action_button("SlotFocus_off_hand")
	if focus_slot == null:
		_expect(false, "detail state: the second open slot has no focus control")
	else:
		focus_slot.pressed.emit()
		await _settle_frames()
		workspace = screen.find_child("FacilityCardsScroll", true, false)
		_expect(workspace != null and workspace.scroll_vertical == before,
			"detail state: switching the compared slot moved the workspace from %d to %s"
			% [before, "missing" if workspace == null else str(workspace.scroll_vertical)])
	var details: Button = screen.get_action_button("LoadoutDetailsToggle")
	if details == null:
		_expect(false, "detail state: the resolved detail toggle is missing")
	else:
		details.pressed.emit()
		await _settle_frames()
		workspace = screen.find_child("FacilityCardsScroll", true, false)
		_expect(workspace != null and workspace.scroll_vertical == before,
			"detail state: opening the resolved detail block moved the workspace from %d to %s"
			% [before, "missing" if workspace == null else str(workspace.scroll_vertical)])
	var reference := screen.find_child("ItemDetailText", true, false) as Label
	_expect(reference != null and reference.is_visible_in_tree() and reference.text.contains("Final Stats")
		and reference.text.contains("Piercing Arrow Continuation Chance: 61%") and reference.text.contains("Carrier Damage: 160"),
		"detail state: the opened resolved detail block shows no final parameters")
	await _close_build_reference(screen)
	var main_hand_focus: Button = screen.get_action_button("SlotFocus_main_hand")
	if main_hand_focus != null:
		main_hand_focus.pressed.emit()
		await _settle_frames()
	var fields: Button = screen.get_action_button("CurrentItemFieldsToggle_main_hand")
	_expect(fields == null, "detail state: the retired current-item raw-field toggle returned")
	workspace = screen.find_child("FacilityCardsScroll", true, false)
	_expect(workspace != null and workspace.scroll_vertical == before,
		"detail state: returning to main hand moved the workspace from %d to %s"
		% [before, "missing" if workspace == null else str(workspace.scroll_vertical)])
	await _end(screen)


## The control that pressed a switch keeps the keyboard focus after the page body is
## rebuilt, so Tab continues from where the player was instead of starting over.
func _check_focus_survives_the_switches() -> void:
	var screen = FacilityScreenScript.new()
	root.add_child(screen)
	screen.present("loadout", {}, {}, "", _long_candidate_snapshot())
	await _settle_frames()
	var details: Button = screen.get_action_button("LoadoutDetailsToggle")
	if details == null:
		_expect(false, "detail state: the resolved detail toggle is missing")
		_end(screen)
		return
	details.grab_focus()
	_expect(_focus_owner_name(screen) == "LoadoutDetailsToggle",
		"detail state: the toggle could not take keyboard focus at all")
	details.pressed.emit()
	await _settle_frames()
	var dialog: AcceptDialog = screen.find_child("ItemDetailDialog", true, false) as AcceptDialog
	var reference_text: Label = screen.find_child("ItemDetailText", true, false) as Label
	_expect(dialog != null and dialog.visible and dialog.title == "Build Details"
		and reference_text != null and reference_text.text.contains("Final Stats"),
		"detail state: complete build reference did not open with real parameters")
	await _close_build_reference(screen)
	_expect(_focus_owner_name(screen) == "LoadoutDetailsToggle",
		"detail state: closing complete build details left keyboard focus at %s instead of its opener"
		% _focus_owner_name(screen))
	var fields: Button = screen.get_action_button("CurrentItemFieldsToggle_main_hand")
	_expect(fields == null, "detail state: the retired current-item raw-field toggle returned to focus order")
	var slot_focus: Button = screen.get_action_button("SlotFocus_off_hand")
	if slot_focus == null:
		_expect(false, "detail state: the second open slot has no focus control to focus")
	else:
		var slot_name := String(slot_focus.name)
		slot_focus.grab_focus()
		_expect(_focus_owner_name(screen) == slot_name,
			"detail state: the slot focus control could not take keyboard focus")
		slot_focus.pressed.emit()
		await _settle_frames()
		_expect(_focus_owner_name(screen) == slot_name,
			"detail state: switching the compared slot left keyboard focus at %s instead of the slot control"
			% _focus_owner_name(screen))
	await _end(screen)


func _close_build_reference(screen: Node) -> void:
	var dialog: AcceptDialog = screen.find_child("ItemDetailDialog", true, false) as AcceptDialog
	_expect(dialog != null and dialog.visible, "detail state: expected an open build reference before close")
	if dialog == null or not dialog.visible:
		return
	dialog.get_ok_button().pressed.emit()
	await _settle_frames()
	_expect(not dialog.visible, "detail state: reference close action did not dismiss the dialog")


func _end(screen: Node) -> void:
	screen.queue_free()
	await process_frame


func _focus_owner_name(screen: Node) -> String:
	var viewport := screen.get_viewport()
	if viewport == null:
		return "no-viewport"
	var owner := viewport.gui_get_focus_owner()
	return "none" if owner == null else String(owner.name)


## Three frames: the container sort, the deferred minimum-size pass that follows it,
## and one more so a scrollbar or focus value read afterwards is the settled one.
func _settle_frames() -> void:
	await process_frame
	await process_frame
	await process_frame


## Labels that exist in the tree, hidden or not: folding may hide a raw field line,
## but the value has to stay reachable under its own disclosure.
func _total_label_count(screen: Node, needle: String) -> int:
	var count := 0
	for node: Node in screen.find_children("*", "Label", true, false):
		if (node as Label).text.contains(needle):
			count += 1
	return count


## The real loadout snapshot plus N extra same-slot candidates, one very long raw
## instance id, and a second populated open slot.
func _long_candidate_snapshot() -> Dictionary:
	var snapshot := _real_loadout_snapshot()
	var inventory: Array = (snapshot["inventory_equipment"] as Array).duplicate(true)
	for index in EXTRA_CANDIDATES:
		inventory.append({
			"instance_id": "loot:extra/%02d" % index,
			"base_item_id": "swift_recurve_bow",
			"slot": "main_hand",
			"affixes": [],
			"rune_id": "",
			"law_id": "",
		})
	inventory.append({
		"instance_id": LONG_ID,
		"base_item_id": "swift_recurve_bow",
		"slot": "main_hand",
		"affixes": [],
		"rune_id": "",
		"law_id": "",
	})
	for index in OFF_HAND_CANDIDATES:
		inventory.append({
			"instance_id": "loot:offhand/%02d" % index,
			"base_item_id": "turnfeather_gloves",
			"slot": "off_hand",
			"affixes": [],
			"rune_id": "",
			"law_id": "",
		})
	snapshot["inventory_equipment"] = inventory
	return snapshot


func _real_loadout_snapshot() -> Dictionary:
	var fixtures := FacilityFixture.new()
	var snapshot: Dictionary = fixtures._real_loadout_snapshot()
	fixtures.free()
	return snapshot


func _finish() -> void:
	if failures.is_empty():
		print("PASS  test_facility_detail_state.gd")
		quit(0)
		return
	for failure in failures:
		printerr("- %s" % failure)
	quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
