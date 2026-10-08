extends SceneTree

const ContractScreenScript = preload("res://src/presentation/contract_screen.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	root.size = Vector2i(1280, 720)
	var screen = ContractScreenScript.new()
	# Validation cases run immediately on headless and visible displays alike;
	# the separate transition case below exercises the animated path.
	screen.set_presentation_enabled(false)
	root.add_child(screen)
	var starts: Array[Dictionary] = []
	screen.start_requested.connect(func(config: Dictionary) -> void: starts.append(config.duplicate(true)))

	screen.present(
		{"initial_class": "ranger"},
		{},
		"",
		_snapshot(false, "mainline_01_first_hunt")
	)
	var picker: OptionButton = screen.get("_contract_picker")
	var mode_picker: OptionButton = screen.get("_mode_picker")
	var info_label: Label = screen.get("_contract_info_label")
	_expect(picker != null and _selected_id(picker) == "mainline_01_first_hunt", "contract screen: next available mainline was not selected", failures)
	_expect(_is_disabled(picker, "tutorial_ranger_basics") and _is_disabled(picker, "mainline_02_priority_under_pressure"), "contract screen: completed or locked fixed nodes stayed clickable", failures)
	_expect(not _is_disabled(picker, "mainline_01_first_hunt") and not _is_disabled(picker, "side_targeted_equipment"), "contract screen: available mainline or repeatable side node was disabled", failures)
	_expect(mode_picker != null and mode_picker.selected == 0 and mode_picker.is_item_disabled(1), "contract screen: pre-Boss node did not lock to Manual", failures)
	_expect(info_label != null and "固定起步装" in info_label.text and "猎人印记" in info_label.text, "contract screen: authored drop/reward tags were not explained", failures)
	_expect(String(screen.call("_tag_summary", ["breeding_split_item", "pack_hunt_mark_item"])).contains("获得后需在备行架装备"),
		"contract screen: semantic item rewards omitted manual-equip guidance", failures)
	screen.call("_on_start_pressed")
	_expect(starts.size() == 1 and starts[0].contract_id == "mainline_01_first_hunt" and starts[0].mode == "Manual" and int(starts[0].room_count) == 1, "contract screen: mainline start payload did not use selected authored node", failures)

	screen.present(
		{"initial_class": "ranger"},
		{"contract_id": "auto_certification", "mode": "Auto", "seed": 77},
		"",
		_snapshot(true, "auto_certification")
	)
	picker = screen.get("_contract_picker")
	mode_picker = screen.get("_mode_picker")
	_expect(_selected_id(picker) == "auto_certification" and not _is_disabled(picker, "auto_certification"), "contract screen: unlocked Auto certification was not selectable", failures)
	_expect(mode_picker.selected == 1 and mode_picker.is_item_disabled(0) and not mode_picker.is_item_disabled(1), "contract screen: Auto certification did not enforce Auto mode", failures)
	screen.call("_on_start_pressed")
	_expect(starts.size() == 2 and starts[1].contract_id == "auto_certification" and starts[1].mode == "Auto" and int(starts[1].seed) == 77, "contract screen: Auto certification emitted the wrong payload", failures)

	picker = screen.get("_contract_picker")
	info_label = screen.get("_contract_info_label")
	var seed_edit: LineEdit = screen.get("_seed_edit")
	_expect(seed_edit != null and not seed_edit.visible,
		"contract screen: diagnostic seed control escaped the F10 console", failures)

	# Repeatable progress + suggested seed on first present, node switching, and pity copy.
	var pity_snapshot := _snapshot(true, "auto_certification")
	_set_node_fields(pity_snapshot, "side_targeted_equipment", {
		"completion_count": 2, "next_attempt_number": 3, "suggested_seed": 8123,
	})
	_set_node_fields(pity_snapshot, "side_affix_and_law_tallies", {
		"completion_count": 2, "next_attempt_number": 3, "suggested_seed": 9001,
	})
	screen.present({"initial_class": "ranger"}, {"contract_id": "side_targeted_equipment"}, "", pity_snapshot)
	_expect(_selected_id(picker) == "side_targeted_equipment", "contract screen: repeatable side node from previous config was not selected", failures)
	_expect(seed_edit != null and seed_edit.text == "8123", "contract screen: suggested_seed was not applied on first present", failures)
	_expect("已完成 2 次 / 本次第 3 次" in info_label.text, "contract screen: repeatable completion/attempt copy missing", failures)
	_expect("保底" not in info_label.text, "contract screen: non-pity side node showed pity copy", failures)
	_expect("推荐" not in info_label.text and "战力" not in info_label.text, "contract screen: contract summary leaked power/tier recommendation copy", failures)
	var fate_index := _index_of(picker, "side_affix_and_law_tallies")
	picker.select(fate_index)
	screen.call("_on_contract_selected", fate_index)
	_expect("每 3 次完成触发一次定向装备保底" in info_label.text and "本次触发保底" in info_label.text, "contract screen: third-attempt pity copy missing", failures)
	_expect(seed_edit.text == "9001", "contract screen: switching node did not apply its suggested_seed", failures)
	seed_edit.text = "4242"
	screen.call("_on_start_pressed")
	_expect(starts.size() == 3 and starts[2].contract_id == "side_affix_and_law_tallies" and int(starts[2].seed) == 4242, "contract screen: hand-edited seed was not used in start payload", failures)
	seed_edit.text = "9007199254740992"
	screen.call("_on_start_pressed")
	_expect(starts.size() == 3 and "契约准备数据无效" in String((screen.get("_status_label") as Label).text),
		"contract screen: an unsafe positive seed was emitted or exposed a technical error", failures)
	seed_edit.text = "-9007199254740992"
	screen.call("_on_start_pressed")
	_expect(starts.size() == 3, "contract screen: an unsafe negative seed was emitted", failures)

	# Non-multiple attempt shows remaining count instead of a trigger.
	var pity_snapshot_2 := _snapshot(true, "auto_certification")
	_set_node_fields(pity_snapshot_2, "side_affix_and_law_tallies", {
		"completion_count": 3, "next_attempt_number": 4, "suggested_seed": 9002,
	})
	screen.present({"initial_class": "ranger"}, {"contract_id": "side_affix_and_law_tallies"}, "", pity_snapshot_2)
	_expect("距保底还有 2 次" in info_label.text and "本次触发保底" not in info_label.text, "contract screen: off-cycle pity remaining-count copy wrong", failures)
	_expect("已完成 3 次 / 本次第 4 次" in info_label.text, "contract screen: repeated attempt copy after completion not shown", failures)

	# Legacy snapshot without the optional fields keeps previous_config seed / 52969 fallback.
	screen.present({"initial_class": "ranger"}, {}, "", _snapshot(false, "mainline_01_first_hunt"))
	_expect(seed_edit.text == "52969", "contract screen: legacy snapshot did not fall back to default seed", failures)
	_expect("已完成" not in info_label.text, "contract screen: legacy node showed repeatable progress copy", failures)
	var build_label: Label = screen.get("_build_label")
	_expect(build_label != null and "当前构筑数据不可用" in build_label.text, "contract screen: legacy snapshot without resolved build did not degrade gracefully", failures)
	_expect("方案" not in _all_text(screen), "contract screen: legacy snapshot leaked preset A/B/C naming", failures)
	_expect("穿刺箭" in build_label.text and "猎人印记" in build_label.text and "突袭" in build_label.text and "闪避" in build_label.text, "contract screen: skill Chinese mapping missing", failures)
	_expect("核心技能说明" not in build_label.text and "tick" not in build_label.text,
		"contract screen: full rules leaked into default view", failures)
	var details_button: Button = screen.find_child("BuildDetailsButton", true, false)
	_expect(details_button != null and screen.get("_details_dialog") == null, "contract screen: details must be available and created on demand", failures)
	details_button.pressed.emit()
	var details: AcceptDialog = screen.get("_details_dialog")
	var details_label: Label = screen.get("_details_label")
	_expect(details != null and details.visible and "核心技能说明" in details_label.text and "冷却：13 tick" in details_label.text and "持续免受伤害" in details_label.text,
		"contract screen: opening details lost the complete skill rules", failures)
	details.hide()
	details.canceled.emit()
	_expect(details_button.has_focus(), "contract screen: closing details did not restore focus", failures)

	# Bad-typed or negative optional fields fall back safely.
	var bad_snapshot := _snapshot(true, "auto_certification")
	_set_node_fields(bad_snapshot, "side_targeted_equipment", {
		"completion_count": -3, "next_attempt_number": "oops", "suggested_seed": "abc",
	})
	screen.present({"initial_class": "ranger"}, {"contract_id": "side_targeted_equipment", "seed": 606}, "", bad_snapshot)
	_expect(seed_edit.text == "606", "contract screen: invalid suggested_seed overrode previous_config seed", failures)
	_expect("已完成" not in info_label.text, "contract screen: invalid progress fields rendered progress copy", failures)
	var negative_seed_snapshot := _snapshot(true, "auto_certification")
	_set_node_fields(negative_seed_snapshot, "side_targeted_equipment", {
		"completion_count": 1, "next_attempt_number": 2, "suggested_seed": -404,
	})
	screen.present({"initial_class": "ranger"}, {"contract_id": "side_targeted_equipment", "seed": -405}, "", negative_seed_snapshot)
	_expect(seed_edit.text == "-404", "contract screen: valid negative suggested seed was rejected", failures)

	# Real resolved Build: player-facing names replace raw parameter/interface ids.
	var fingerprint := "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
	var unverified_snapshot := _snapshot(true, "auto_certification")
	unverified_snapshot["resolved_build"] = _resolved_build(fingerprint, "exponential", {
		"p": 0.49, "T": 34.0, "v": 750.2, "d": 18, "turn": 0.4, "damage": 12.5, "max_health": 100,
	}, ["breedable_event"], ["branch_target_history"])
	(unverified_snapshot["active_build"] as Dictionary)["runes"] = ["breeding_split"]
	(unverified_snapshot["active_build"] as Dictionary)["laws"] = ["pack_hunt_mark"]
	screen.present({"initial_class": "ranger"}, {"contract_id": "auto_certification"}, "", unverified_snapshot)
	_expect(build_label != null and "穿刺箭续行概率：49%" in build_label.text and "共享谱系寿命：34 秒" in build_label.text
		and "寻敌与穿刺箭射程：18" in build_label.text and "载体伤害：12.5" in build_label.text and "最大生命：100" in build_label.text,
		"contract screen: five decision parameters were not rendered", failures)
	_expect("投射物速度" not in build_label.text and "转向时间" not in build_label.text and "核心技能说明" not in build_label.text,
		"contract screen: complete rule receipt remained in default view", failures)
	details_button.pressed.emit()
	_expect("投射物速度：750.2" in details_label.text and "转向时间（数值越低越好）：0.4 秒（越低越好）" in details_label.text,
		"contract screen: details omitted remaining authoritative parameters", failures)
	_expect("breedable_event" not in build_label.text and "branch_target_history" not in build_label.text and "ffffffffffff" not in build_label.text,
		"contract screen: raw diagnostic ids leaked into the build summary", failures)
	_expect("增长结论：未验证" in details_label.text, "contract screen: unverified build did not show 未验证", failures)
	_expect("exponential" not in _all_text(screen), "contract screen: unverified build leaked growth classification", failures)
	_expect("方案" not in _all_text(screen), "contract screen: resolved summary leaked preset A/B/C naming", failures)
	_expect("符文：孳生分裂" in details_label.text and "法则：群猎印记" in details_label.text, "contract screen: rune/law Chinese mapping missing", failures)
	_expect("备行架" in _all_text(screen) and "切换" not in build_label.text, "contract screen: read-only guidance did not point at real equipment", failures)

	# Verified fingerprint unlocks the real growth classification.
	var verified_snapshot := _snapshot(true, "auto_certification")
	verified_snapshot["resolved_build"] = _resolved_build(fingerprint, "critical", {"p": 0.49}, [], [])
	(verified_snapshot["training"] as Dictionary)["reports_by_fingerprint"] = {
		fingerprint: {"build_fingerprint": fingerprint, "state": "exponential"},
	}
	screen.present({"initial_class": "ranger"}, {"contract_id": "auto_certification"}, "", verified_snapshot)
	details_button.pressed.emit()
	_expect("增长结论：指数" in details_label.text and "未验证" not in details_label.text and "临界" not in details_label.text,
		"contract screen: verified build did not use the report state as the readable classification", failures)
	_expect("方案" not in _all_text(screen), "contract screen: verified summary leaked preset A/B/C naming", failures)

	# A map key alone cannot verify a different report, nor can resolved state leak through it.
	var mismatched_snapshot := _snapshot(true, "auto_certification")
	mismatched_snapshot["resolved_build"] = _resolved_build(fingerprint, "exponential", {"p": 0.49}, [], [])
	(mismatched_snapshot["training"] as Dictionary)["reports_by_fingerprint"] = {
		fingerprint: {"build_fingerprint": "different-fingerprint", "state": "critical"},
	}
	screen.present({"initial_class": "ranger"}, {"contract_id": "auto_certification"}, "", mismatched_snapshot)
	details_button.pressed.emit()
	_expect("增长结论：未验证" in details_label.text and "指数" not in details_label.text and "临界" not in details_label.text,
		"contract screen: mismatched report fingerprint impersonated a verified build", failures)

	# Only parameters that exist are shown.
	var sparse_snapshot := _snapshot(true, "auto_certification")
	sparse_snapshot["resolved_build"] = _resolved_build(fingerprint, "convergent", {"p": 0.51}, [], [])
	screen.present({"initial_class": "ranger"}, {"contract_id": "auto_certification"}, "", sparse_snapshot)
	details_button.pressed.emit()
	_expect("穿刺箭续行概率：51%" in build_label.text, "contract screen: sparse resolved build missed its parameter", failures)
	_expect("共享谱系寿命：" not in build_label.text and "转向时间（数值越低越好）：" not in build_label.text and "最大生命：" not in build_label.text, "contract screen: absent parameters were rendered", failures)

	# Missing or ok:false resolved Build degrades without re-leaking presets.
	var broken_snapshot := _snapshot(true, "auto_certification")
	broken_snapshot["resolved_build"] = {"ok": false, "errors": ["boom"], "growth_classification": "exponential", "final_parameters": {"p": 0.9}}
	screen.present({"initial_class": "ranger"}, {"contract_id": "auto_certification"}, "", broken_snapshot)
	details_button.pressed.emit()
	details.hide()
	_expect("当前构筑数据不可用" in build_label.text, "contract screen: broken resolved build did not degrade gracefully", failures)
	_expect("p=" not in build_label.text and "exponential" not in _all_text(screen) and "方案" not in _all_text(screen), "contract screen: broken resolved build leaked parameters or classification", failures)

	# Workspace: content scrolls but commitment and exit stay pinned onscreen.
	await _wait_frames(2)
	var scroll: ScrollContainer = screen.find_child("ContractScroll", true, false)
	var panel: PanelContainer = screen.find_child("ContractPanel", true, false)
	var start_button: Button = screen.find_child("StartButton", true, false)
	_expect(scroll != null and scroll.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED, "contract screen: vertical ScrollContainer missing or disabled", failures)
	_expect(scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED, "contract screen: horizontal scrolling must stay disabled for the fixed panel width", failures)
	_expect(scroll.get_v_scroll_bar().get_theme_stylebox("scroll") is StyleBoxEmpty
		and scroll.get_v_scroll_bar().get_theme_stylebox("grabber") is StyleBoxEmpty,
		"contract screen: passive workspace scrollbar chrome should be hidden", failures)
	_expect(panel != null and panel.get_combined_minimum_size().y > 0.0, "contract screen: scroll content has no meaningful minimum height", failures)
	_expect(scroll.size.y > 0.0 and scroll.size.y <= 720.0, "contract screen: panel escaped the 720p viewport", failures)
	_expect(start_button != null and start_button == screen.get("_start_button") and not scroll.is_ancestor_of(start_button), "contract screen: StartButton must stay in the pinned footer", failures)
	scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
	await _wait_frames(2)
	var button_rect := start_button.get_global_rect()
	_expect(button_rect.position.y >= 0.0 and button_rect.end.y <= 720.0, "contract screen: StartButton outside viewport", failures)
	screen.size = Vector2(1280, 560)
	await _wait_frames(2)
	_expect(scroll.get_v_scroll_bar().max_value > 0.0, "contract screen: content is not scrollable in a shorter viewport", failures)
	for viewport_size in [Vector2(1024,576),Vector2(1280,720),Vector2(1600,900),Vector2(1920,1080)]:
		screen.size = viewport_size
		await _wait_frames(4)
		var area := Rect2(screen.global_position,viewport_size)
		_expect(area.encloses(start_button.get_global_rect()), "contract screen: pinned action escaped " + str(viewport_size), failures)
		_expect(area.encloses(scroll.get_global_rect()), "contract screen: selection pane escaped " + str(viewport_size), failures)
		var build_scroll: ScrollContainer = screen.find_child("ContractBuildScroll",true,false)
		_expect(build_scroll != null and area.encloses(build_scroll.get_global_rect()), "contract screen: build pane escaped " + str(viewport_size), failures)
		_expect(build_scroll != null and build_scroll.get_v_scroll_bar().get_theme_stylebox("grabber") is StyleBoxEmpty,
			"contract screen: build pane reintroduced passive scrollbar chrome", failures)
		var mark: TextureRect = screen.find_child("ContractMark",true,false)
		_expect(mark != null and mark.texture is AtlasTexture and mark.size == Vector2(64,64), "contract screen: published contract art at native size", failures)
		var source_heading: Label = screen.find_child("ContractSourceHeading",true,false)
		_expect(source_heading != null and source_heading.autowrap_mode != TextServer.AUTOWRAP_OFF
			and source_heading.size.x <= (source_heading.get_parent() as Control).size.x,
			"contract screen: source heading must wrap inside its allocated pane", failures)

	# Real fresh-save build and rewards, rather than fixture-only display data.
	var app = load("res://src/game/application_state.gd").new()
	app.start_new_profile("ranger")
	app.complete_tutorial()
	var real_snapshot: Dictionary = app.early_game_snapshot()
	real_snapshot["resolved_build"] = app.resolved_build_snapshot()
	var game = load("res://src/game/game_root.gd").new()
	game.application_state = app
	real_snapshot["campaign"] = game.call("_campaign_contract_snapshot")
	game.free()
	var experience: int = load("res://src/systems/character_progression.gd").contract_experience("mainline_01_first_hunt", true)
	screen.present(app.profile, {}, "", real_snapshot)
	var objective: Label = screen.find_child("CombatObjective", true, false)
	_expect("清除敌人" in objective.text and "旧路外段" in info_label.text and "炉边镇" in info_label.text and "猎人印记" in info_label.text and ("完成经验：%d" % experience) in info_label.text,
		"contract screen: fresh-save goal/reward not linked to town and road", failures)
	_expect("猎人印记" not in build_label.text and "穿刺箭" in build_label.text,
		"contract screen: first-clear skill reward impersonated an already equipped skill", failures)
	for viewport_size in [Vector2(1280,720), Vector2(1600,900)]:
		screen.size = viewport_size
		await _wait_frames(4)
		_expect(objective.get_global_rect().end.y <= (scroll.get_global_rect().end.y) and info_label.get_global_rect().end.y <= scroll.get_global_rect().end.y,
			"contract screen: fresh-save goals/rewards require scrolling at " + str(viewport_size), failures)
		_expect(build_label.get_global_rect().end.y <= (screen.get("_build_scroll") as Control).get_global_rect().end.y,
			"contract screen: decision build requires scrolling at " + str(viewport_size), failures)

	# A visible transition locks every commitment control and emits the exact
	# validated config once completion is forced through the public test hook.
	var transition_screen = ContractScreenScript.new()
	root.add_child(transition_screen)
	var transition_starts: Array[Dictionary] = []
	transition_screen.start_requested.connect(func(config: Dictionary) -> void: transition_starts.append(config.duplicate(true)))
	transition_screen.present(
		{"initial_class": "ranger"},
		{"contract_id": "mainline_01_first_hunt", "mode": "Manual", "seed": 4242},
		"",
		_snapshot(false, "mainline_01_first_hunt")
	)
	transition_screen.set_presentation_enabled(true)
	transition_screen.call("_on_start_pressed")
	var transition_picker: OptionButton = transition_screen.get("_contract_picker")
	var transition_mode: OptionButton = transition_screen.get("_mode_picker")
	var transition_seed: LineEdit = transition_screen.get("_seed_edit")
	var transition_start: Button = transition_screen.get("_start_button")
	var transition_cancel: Button = transition_screen.get("_cancel_button")
	_expect(transition_starts.is_empty() and bool(transition_screen.get("_start_transition_active")),
		"contract screen: visible start transition emitted before completion", failures)
	_expect(transition_picker.disabled and transition_mode.disabled and not transition_seed.editable
		and transition_start.disabled and transition_cancel.disabled,
		"contract screen: controls were not locked during start transition", failures)
	transition_screen.complete_start_transition()
	_expect(transition_starts.size() == 1 and transition_starts[0] == {
		"contract_id": "mainline_01_first_hunt",
		"mode": "Manual",
		"preset_id": "fixed_start",
		"seed": 4242,
		"room_count": 1,
	}, "contract screen: completed transition changed or duplicated start config", failures)
	_expect(not transition_picker.disabled and not transition_mode.disabled and transition_seed.editable
		and not transition_start.disabled and not transition_cancel.disabled,
		"contract screen: controls did not restore after start transition", failures)
	transition_screen.complete_start_transition()
	_expect(transition_starts.size() == 1, "contract screen: completion hook emitted start more than once", failures)
	transition_screen.call("_on_start_pressed")
	_expect(transition_starts.size() == 1, "contract screen: repeated start click emitted a second request", failures)
	root.remove_child(transition_screen)
	transition_screen.free()

	root.remove_child(screen)
	screen.free()
	_finish(failures)


func _snapshot(auto_unlocked: bool, next_id: String) -> Dictionary:
	var completed := ["tutorial_ranger_basics"]
	if auto_unlocked:
		completed = [
			"tutorial_ranger_basics", "mainline_01_first_hunt", "mainline_02_priority_under_pressure",
			"mainline_03_first_elite", "mainline_04_hazard_and_forge", "mainline_05_growth_gate",
			"threshold_colossus",
		]
	var available := ["mainline_01_first_hunt", "side_targeted_equipment"]
	if auto_unlocked:
		available = ["auto_certification", "side_targeted_equipment", "side_affix_and_law_tallies"]
	return {
		"ok": true,
		"active_build": {
			"preset_id": "fixed_start",
			"skills": ["piercing_arrow", "hunter_mark", "dash"],
			"runes": [],
			"laws": [],
		},
		"available_builds": [],
		"training": {"reports_by_fingerprint": {}},
		"auto_mode_unlocked": auto_unlocked,
		"campaign": {
			"ok": true,
			"completed_node_ids": completed,
			"available_node_ids": available,
			"next_mainline_node_id": next_id,
			"nodes": [
				_node("tutorial_ranger_basics", false, true, false, ["Manual"], ["starter_fixed"], ["starter_loadout"]),
				_node("mainline_01_first_hunt", "mainline_01_first_hunt" in available, "mainline_01_first_hunt" in completed, false, ["Manual"], ["starter_fixed"], ["hunter_mark_skill"]),
				_node("mainline_02_priority_under_pressure", false, "mainline_02_priority_under_pressure" in completed, false, ["Manual"], ["equipment_general"], ["dash_skill"]),
				_node("threshold_colossus", false, "threshold_colossus" in completed, false, ["Manual"], ["proxy_core_fixed"], ["fixed_four_white_proxy_cores"]),
				_node("auto_certification", "auto_certification" in available, false, false, ["Auto"], ["equipment_general"], ["early_campaign_complete"]),
				_node("side_targeted_equipment", true, false, true, ["Manual"], ["main_hand", "ring"], []),
				_node("side_affix_and_law_tallies", auto_unlocked, false, true, ["Manual"], ["add_dice"], []),
			],
		},
	}


func _node(id: String, available: bool, completed: bool, repeatable: bool, modes: Array, drops: Array, rewards: Array) -> Dictionary:
	return {
		"id": id,
		"kind": "side_template" if repeatable else "mainline",
		"available": available,
		"completed": completed,
		"repeatable": repeatable,
		"allowed_modes": modes.duplicate(),
		"room_count": 3 if repeatable else 1,
		"drop_tags": drops.duplicate(),
		"first_reward_tags": rewards.duplicate(),
		"unlock_prerequisites": [],
	}


func _set_node_fields(snapshot: Dictionary, node_id: String, fields: Dictionary) -> void:
	var campaign_value: Variant = snapshot.get("campaign", {})
	if not (campaign_value is Dictionary):
		return
	for node_value in (campaign_value as Dictionary).get("nodes", []):
		if node_value is Dictionary and String((node_value as Dictionary).get("id", "")) == node_id:
			for key: Variant in fields.keys():
				(node_value as Dictionary)[key] = fields[key]
			return


func _resolved_build(fingerprint: String, classification: String, parameters: Dictionary, connected: Array, missing: Array) -> Dictionary:
	return {
		"ok": true,
		"errors": [],
		"final_parameters": parameters.duplicate(true),
		"connected_interfaces": connected.duplicate(),
		"missing_interfaces": missing.duplicate(),
		"build_fingerprint": fingerprint,
		"growth_classification": classification,
	}


func _all_text(node: Node) -> String:
	var parts: Array[String] = []
	if node is Label:
		parts.append((node as Label).text)
	elif node is Button:
		parts.append((node as Button).text)
	elif node is LineEdit:
		parts.append((node as LineEdit).text)
	elif node is OptionButton:
		for index in (node as OptionButton).item_count:
			parts.append((node as OptionButton).get_item_text(index))
	for child in node.get_children():
		parts.append(_all_text(child))
	return "\n".join(parts)


func _wait_frames(count: int) -> void:
	for _index in count:
		await process_frame


func _index_of(picker: OptionButton, node_id: String) -> int:
	for index in picker.item_count:
		var metadata: Variant = picker.get_item_metadata(index)
		if metadata is Dictionary and String((metadata as Dictionary).get("id", "")) == node_id:
			return index
	return -1


func _selected_id(picker: OptionButton) -> String:
	if picker == null or picker.selected < 0:
		return ""
	var metadata: Variant = picker.get_item_metadata(picker.selected)
	return String((metadata as Dictionary).get("id", "")) if metadata is Dictionary else ""


func _is_disabled(picker: OptionButton, node_id: String) -> bool:
	if picker == null:
		return true
	for index in picker.item_count:
		var metadata: Variant = picker.get_item_metadata(index)
		if metadata is Dictionary and String((metadata as Dictionary).get("id", "")) == node_id:
			return picker.is_item_disabled(index)
	return true


func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print("PASS  test_contract_screen.gd")
		quit(0)
		return
	for failure in failures:
		printerr("- %s" % failure)
	quit(1)


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
