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

	# Subwindows and their text resources leave the tree on the next idle pass.
	# Let cleanup settle so an otherwise passing UI probe does not report engine
	# RID/ObjectDB leaks after the new bounded item-detail dialog was exercised.
	for child in root.get_children():
		child.free()
	await process_frame
	await process_frame
	_finish(failures)


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


func _finish(failures: Array[String], script_name: String = "test_facility_screen.gd") -> void:
	if failures.is_empty():
		print("PASS  %s" % script_name)
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
