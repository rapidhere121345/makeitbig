extends SceneTree
## Layout gate for the contract settlement screen (src/presentation/result_screen.gd).
##
## Run it on its own:
##   godot --headless --path . --script res://tests/unit/test_result_layout.gd
##
## It measures the built screen after real process frames instead of trusting the
## code's own constants: the header and the two actions have to stay on the screen
## while the loot uses fixed pages, nothing may reach past the right edge, no Chinese copy
## may fall under the approved 18px floor, and a long drop list has to page rather
## than push the footer away. The 1024x576 and 1600x900 hosts stand in for the two
## window sizes the shell has to stay usable at.
##
## The payloads mirror the authoritative settlement fields (contract_run_controller
## _build_summary plus the fields application_state adds); nothing here writes
## gameplay state or needs a GPU.

const PixelStageScript = preload("res://src/presentation/pixel_stage.gd")
const ResultScreenScript = preload("res://src/presentation/result_screen.gd")

const RESOLUTIONS: Array[Vector2] = [Vector2(1280.0, 720.0), Vector2(1600.0, 900.0), Vector2(1920.0, 1080.0), Vector2(1024.0, 576.0)]
const BODY_FOOTER_EPSILON := 1.0
## The approved Chinese UI floor (VISUAL_BASELINE.md: 正文 18-22 显示像素).
const FONT_FLOOR := 18
const LONG_DROP_COUNT := 12
const LONG_INSTANCE_ID := "drop_0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
const EDGE_EPSILON := 0.5
const ICON_ATLAS_PATH := "res://art/production/p1/early_loop_v01/atlas.json"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for resolution in RESOLUTIONS:
		await _test_resolution(resolution)
	await _test_long_drop_list()
	await _test_mixed_rewards()
	await _test_outcome_actions()
	await _test_defeat_first_kill()
	await _test_detail_reveal()
	await _test_card_icon_roles()
	await _test_sparse_metrics()
	if failures.is_empty():
		print("PASS  tests/unit/test_result_layout.gd: settlement layout contract")
		quit(0)
		return
	printerr("%d check(s) failed:" % failures.size())
	for failure: String in failures:
		printerr("- %s" % failure)
	quit(1)


func _test_mixed_rewards() -> void:
	var host := _host(Vector2(1280, 720))
	var payload := _victory_payload(1)
	payload["outcome"] = "final_victory"
	payload["first_reward_tags"] = ["early_campaign_complete"]
	payload["proxy_component_drops"] = [{"id":"marking_prism", "name":"标记棱镜", "slot":"perception", "protocol":"区分标记、精英、Boss，并保留 2 个候选"}]
	payload.rewards.erase("add_dice_delta")
	var screen = _settle(host, payload)
	await _frames(5)
	var body: Control = screen.find_child("ResultContent",true,false)
	var footer: Control = screen.find_child("ResultFooter",true,false)
	_expect(body.get_global_rect().end.y <= footer.get_global_rect().position.y, "mixed rewards cover footer")
	var review: Button = screen.find_child("ReviewDrop_*",true,false)
	_expect(review != null and body.get_global_rect().encloses(review.get_global_rect()), "mixed equipment comparison is clipped")
	var title: Label = screen.find_child("ProxyComponentName",true,false)
	_expect(title.tooltip_text.contains("2 个候选") and title.tooltip_text.contains("当前代理构筑不变"), "compact component lost protocol/state")
	_expect((screen.find_child("ResultSubtitle",true,false) as Label).text.contains("前期旅程完成"), "first-clear guidance not visible")
	_close(host, screen)


func _test_resolution(window_resolution: Vector2) -> void:
	# Use the same logical canvas as GameRoot: a 1024px physical window fits
	# the 1280px fallback rather than laying out Chinese text at 1024px.
	var layout: Dictionary = PixelStageScript.adaptive_layout_for_window(Vector2i(window_resolution))
	var resolution := Vector2(layout.ui_logic_size)
	var host := _host(resolution)
	var screen = _settle(host, _victory_payload(2))
	await _frames(4)
	var tag := "%dx%d" % [int(resolution.x), int(resolution.y)]
	var bounds := Rect2(host.global_position, host.size)
	var header: Control = screen.find_child("ResultHeader", true, false)
	var footer: Control = screen.find_child("ResultFooter", true, false)
	var scroll: ScrollContainer = screen.find_child("CurrentRunScroll", true, false)
	var content: Control = screen.find_child("ResultContent", true, false)
	var metrics: GridContainer = screen.find_child("ResultMetrics", true, false)
	_expect(metrics.columns == 3,
		"%s: metrics must keep three readable columns" % tag)
	_expect(bounds.encloses(header.get_global_rect()), "%s: the header left the screen: %s in %s" % [tag, str(header.get_global_rect()), str(bounds)])
	_expect(bounds.encloses(footer.get_global_rect()), "%s: the action footer is not fully on the screen: %s in %s" % [tag, str(footer.get_global_rect()), str(bounds)])
	_expect(header.get_global_rect().position.y + header.get_global_rect().size.y <= scroll.get_global_rect().position.y + EDGE_EPSILON, "%s: the body does not start below the header" % tag)
	_expect(scroll.get_global_rect().position.y + scroll.get_global_rect().size.y <= footer.get_global_rect().position.y + BODY_FOOTER_EPSILON, "%s: the body does not end above the footer" % tag)
	_expect(content.size.x <= resolution.x + EDGE_EPSILON, "%s: the page content is wider than its viewport (%s > %s)" % [tag, str(content.size.x), str(resolution.x)])
	_expect(scroll.get_h_scroll_bar().max_value <= scroll.size.x + EDGE_EPSILON, "%s: the body can scroll sideways (%s > %s)" % [tag, str(scroll.get_h_scroll_bar().max_value), str(scroll.size.x)])
	_check_inside(screen, bounds, tag, scroll)
	_check_font_floor(screen, tag)
	_close(host, screen)


## Twelve drops: pagination keeps the footer fixed and every item accessible.
func _test_long_drop_list() -> void:
	var host := _host(Vector2(1280.0, 720.0))
	var screen = _settle(host, _victory_payload(LONG_DROP_COUNT))
	await _frames(4)
	var footer: Control = screen.find_child("ResultFooter", true, false)
	var scroll: ScrollContainer = screen.find_child("CurrentRunScroll", true, false)
	var bounds := Rect2(host.global_position, host.size)
	var pagination: Control = screen.find_child("EquipmentPagination", true, false)
	var previous: Button = screen.find_child("EquipmentPreviousPage", true, false)
	var next: Button = screen.find_child("EquipmentNextPage", true, false)
	var page_label: Label = screen.find_child("EquipmentPageLabel", true, false)
	_expect(screen.get_equipment_card_count() == 1, "long list: one readable card must be fixed on each 720px page")
	_expect(pagination != null and pagination.visible and previous != null and next != null and page_label != null,
		"long list: pagination controls are not visible")
	_expect(page_label != null and page_label.text == "1 / %d" % LONG_DROP_COUNT, "long list: wrong initial page label")
	_expect(previous != null and previous.disabled and next != null and not next.disabled, "long list: initial pager state is wrong")
	var loot_scroll := screen.find_child("ResultLootScroll", true, false) as ScrollContainer
	_expect(loot_scroll != null and bounds.encloses(loot_scroll.get_global_rect())
		and not loot_scroll.is_ancestor_of(pagination)
		and bounds.encloses(pagination.get_global_rect()),
		"long list: long loot text must scroll locally while the pager stays visible")
	if next != null:
		next.pressed.emit()
		await _frames(2)
	_expect(screen.get_equipment_card_count() == 1 and page_label != null and page_label.text == "2 / %d" % LONG_DROP_COUNT,
		"long list: pagination did not advance a fixed page")
	var review_nodes: Array[Node] = screen.find_children("ReviewDrop_*", "Button", true, false)
	var review_buttons: Array[Button] = []
	for node in review_nodes:
		if node is Button:
			review_buttons.append(node)
	_expect(not review_buttons.is_empty() and bounds.encloses(review_buttons[0].get_global_rect()),
		"long list: the primary compare action is not wholly visible")
	_expect(bounds.encloses(footer.get_global_rect()), "long list: the footer moved off the screen")
	_check_inside(screen, bounds, "long list", scroll)
	_check_font_floor(screen, "long list")
	_close(host, screen)


func _test_outcome_actions() -> void:
	var host := _host(Vector2(1280.0, 720.0))
	var screen = _settle(host, {"outcome": "victory", "rewards": {}})
	await _frames(2)
	var ending: Button = screen.find_child("EndingButton", true, false)
	_expect(not ending.visible, "actions: an ordinary victory exposed the ending action")
	screen.present({"outcome": "final_victory", "rewards": {}})
	await _frames(2)
	_expect(ending.visible, "actions: the final victory did not expose the ending action")
	var base_button: Button = screen.find_child("ReturnToBaseButton", true, false)
	_expect(base_button.visible and base_button.text == "返回基地", "actions: the return-to-base action is missing")
	screen.present({"outcome": "defeat", "rewards": {}})
	await _frames(2)
	_expect(not ending.visible, "actions: a defeat exposed the ending action")
	_close(host, screen)


## First-kill defeat: the single primary cause and the short report stay on the
## left, the reward block and its cards stay on the right, and the outcome metric
## reports the real result.
func _test_defeat_first_kill() -> void:
	var host := _host(Vector2(1280.0, 720.0))
	var screen = _settle(host, {
		"outcome": "defeat",
		"contract_id": "threshold_colossus",
		"mode": "Manual",
		"ticks": 360,
		"elapsed_seconds": 12.0,
		"casts": 24,
		"defeated": 3,
		"failure_reason": "enemy/391/fan_ranged",
		"report": "DEFEAT — the ranger fell after 12.0s. Refit at base.",
		"primary_bottleneck": {"title": "增长收敛", "action": "去定向支线获取增长概率词条"},
		"first_reward_tags": ["hunter_mark_skill"],
		"rewards": {
			"contract_wins_delta": 0,
			"add_dice_delta": 0,
			"rewrite_dice_delta": 0,
			"refine_dice_delta": 0,
			"bonus_lost": true,
			"equipment_drops": [{"instance_id": LONG_INSTANCE_ID, "base_item_id": "ashwood_longbow", "slot": "main_hand", "affixes": []}],
			"equipment_drop_count": 1,
		},
	})
	await _frames(4)
	var outcome_value: Label = screen.find_child("MetricValue_outcome", true, false)
	_expect(outcome_value != null and outcome_value.text == "失败", "defeat: the outcome metric did not report 失败: %s" % (outcome_value.text if outcome_value != null else "<missing>"))
	var run_facts: Label = screen.find_child("RunFacts", true, false)
	_expect(run_facts != null and run_facts.text.contains("threshold_colossus") and run_facts.text.contains("终止原因：扇射游猎者") and not run_facts.text.contains("enemy/391/fan_ranged"), "defeat: the readable loss and the contract are not on the facts line: %s" % (run_facts.text if run_facts != null else "<missing>"))
	_expect(screen.get_reward_text().contains("限时加成：未获得"), "defeat: a lost timed bonus was not reported: %s" % screen.get_reward_text())
	_expect(screen.get_reward_text().contains("本次获得装备 1 件"), "defeat: the equipment count disappeared: %s" % screen.get_reward_text())
	_expect(screen.get_diagnosis_text().contains("失败主因"), "defeat: the diagnosis left the report column")
	_close(host, screen)


## The raw diagnostic formatter still preserves authority data for F10, while the
## normal result page never mounts a technical detail panel or toggle.
func _test_detail_reveal() -> void:
	var host := _host(Vector2(1280.0, 720.0))
	var screen = _settle(host, {
		"outcome": "victory",
		"contract_id": "mainline_03_first_elite",
		"mode": "Manual",
		"preset_id": "exponential",
		"seed": 4242,
		"rooms_completed": 2,
		"room_count": 3,
		"ticks": 900,
		"room_results": [
			{"outcome": "victory", "ticks": 400, "casts": 12, "defeated": 4},
			{"outcome": "defeat", "ticks": 500, "casts": 15, "defeated": 2, "failure_reason": "enemy/391/fan_ranged"},
		],
		"future_authority_field": {"note": "kept"},
		"rewards": {
			"equipment_drops": [{"instance_id": LONG_INSTANCE_ID, "base_item_id": "ashwood_longbow", "slot": "main_hand", "affixes": [{"family_id": "piercing_probability", "tier": 2}], "source": {"type": "campaign_drop", "id": "room_1"}}],
			"equipment_drop_count": 1,
			"future_reward_field": 7,
		},
	})
	await _frames(4)
	var detail_panel: Control = screen.find_child("ResultDetailPanel", true, false)
	var toggle: Button = screen.find_child("DetailToggleButton", true, false)
	_expect(detail_panel == null and toggle == null and not screen.is_detail_visible(), "detail: raw controls escaped the test console")
	var detail_text: String = screen.get_detail_text()
	_expect(detail_text.contains(LONG_INSTANCE_ID), "detail: the full instance id is not listed")
	_expect(detail_text.contains("future_authority_field") and detail_text.contains("future_reward_field"), "detail: metadata outside the known table was dropped: %s" % detail_text)
	_expect(detail_text.contains("房间 2") and detail_text.contains("扇射游猎者") and not detail_text.contains("enemy/391/fan_ranged"), "detail: the per-room result or its readable failure source is missing")
	_expect(screen.get_run_facts_text().contains("2 / 3"), "detail: the room progress line is not on the visible facts: %s" % screen.get_run_facts_text())
	var bounds := Rect2(host.global_position, host.size)
	var scroll: ScrollContainer = screen.find_child("ResultScroll", true, false)
	_check_inside(screen, bounds, "result without raw panel", scroll)
	_check_font_floor(screen, "result without raw panel")
	_close(host, screen)


## Every drop card carries exactly one full-size subject image and, where the batch
## publishes the slot, the small slot badge: two same-size icons would compete for
## the same space and hide which object the run actually produced.
func _test_card_icon_roles() -> void:
	if not FileAccess.file_exists(ICON_ATLAS_PATH):
		return
	var host := _host(Vector2(1280.0, 720.0))
	var screen = _settle(host, _victory_payload(3))
	await _frames(4)
	# The cards are siblings of one box, so the box's children are the real list:
	# Godot uniquifies duplicate sibling node names, which a name search would miss.
	var box: Control = screen.find_child("EquipmentCards", true, false)
	var cards := box.get_children() if box != null else []
	_expect(cards.size() == 1, "icons: expected one visible paged card, got %d" % cards.size())
	for card in cards:
		var subjects := 0
		var badges := 0
		for icon in _texture_rects(card):
			if icon.custom_minimum_size == Vector2(64.0, 64.0):
				subjects += 1
			elif icon.custom_minimum_size == Vector2(32.0, 32.0):
				badges += 1
		_expect(subjects == 1, "icons: a card drew %d 64px subject images instead of one" % subjects)
		_expect(badges == 1, "icons: a card drew %d slot badges instead of one" % badges)
	if not cards.is_empty():
		var subject := cards[0].find_child("EquipmentBaseIcon", true, false)
		var badge := cards[0].find_child("EquipmentSlotBadge", true, false)
		_expect(subject != null and String(subject.get_meta("canonical_id", "")) == "equipment.ashwood_longbow",
			"icons: the subject image of the card is not the dropped base item")
		_expect(badge != null and String(badge.get_meta("canonical_id", "")) == "equipment_slot.main_hand",
			"icons: the badge of the card is not the dropped slot")
	_close(host, screen)


## A sparse settlement: a metric the payload never carried keeps its tile hidden
## instead of being drawn as a zero, while a reported zero stays a real reading.
func _test_sparse_metrics() -> void:
	var host := _host(Vector2(1280.0, 720.0))
	var screen = _settle(host, {"outcome": "victory", "rewards": {}})
	await _frames(2)
	for key: String in ["elapsed", "kills", "casts", "rooms"]:
		var hidden_tile: Control = screen.find_child("MetricTile_%s" % key, true, false)
		_expect(hidden_tile != null and not hidden_tile.visible,
			"sparse: %s was drawn for a field the settlement never reported" % key)
	_expect(screen.find_child("MetricTile_ticks", true, false) == null, "sparse: internal tick tile escaped the test console")
	_expect(not screen.get_detail_text().contains("0.00 秒"), "sparse: the detail table invented an elapsed time")
	screen.present({
		"outcome": "victory",
		"elapsed_seconds": 0.0,
		"ticks": 0,
		"casts": 0,
		"defeated": 0,
		"rewards": {},
	})
	await _frames(2)
	var elapsed_value: Label = screen.find_child("MetricValue_elapsed", true, false)
	var kills_value: Label = screen.find_child("MetricValue_kills", true, false)
	_expect(elapsed_value != null and elapsed_value.text == "0.00 秒", "sparse: a reported zero run time was not drawn")
	_expect(kills_value != null and kills_value.text == "0", "sparse: a reported zero kill count was not drawn")
	_check_inside(screen, Rect2(host.global_position, host.size), "sparse", screen.find_child("CurrentRunScroll", true, false))
	_check_font_floor(screen, "sparse")
	_close(host, screen)


## Every TextureRect under a node: how many published cells a card really draws,
## and at which size.
func _texture_rects(node: Node) -> Array[TextureRect]:
	var found: Array[TextureRect] = []
	for child in node.get_children():
		if child is TextureRect:
			found.append(child)
		found.append_array(_texture_rects(child))
	return found


func _victory_payload(drop_count: int) -> Dictionary:
	var drops: Array = []
	for index in drop_count:
		var slot := "main_hand" if index == 0 else "gloves"
		drops.append({
			"instance_id": "%s%d" % [LONG_INSTANCE_ID.substr(0, 40), index],
			"base_item_id": "ashwood_longbow" if index == 0 else "turnfeather_gloves",
			"slot": slot,
			"affixes": [{"family_id": "piercing_probability", "tier": 2}],
		})
	return {
		"outcome": "victory",
		"contract_id": "mainline_03_first_elite",
		"mode": "Manual",
		"rooms_completed": 1,
		"room_count": 1,
		"ticks": 300,
		"elapsed_seconds": 10.0,
		"casts": 18,
		"defeated": 5,
		"rewards": {"contract_wins_delta": 1, "add_dice_delta": 1, "equipment_drops": drops, "equipment_drop_count": drop_count},
	}


func _host(size: Vector2) -> Control:
	var host := Control.new()
	host.name = "LayoutHost"
	host.size = size
	root.add_child(host)
	return host


func _settle(host: Control, payload: Dictionary):
	var screen = ResultScreenScript.new()
	host.add_child(screen)
	screen.present(payload)
	return screen


func _frames(count: int) -> void:
	for _index in count:
		await process_frame


func _close(host: Control, screen) -> void:
	host.remove_child(screen)
	screen.free()
	host.queue_free()


## Every visible control stays inside the screen horizontally, and everything
## outside the scrolling body also stays inside it vertically. Content that lives
## in the body is allowed to extend past the bottom edge -- that is what scrolling
## means -- but never past the sides.
func _check_inside(node: Node, bounds: Rect2, tag: String, scroll: Control) -> void:
	for control in _visible_controls(node):
		var rect := control.get_global_rect()
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			continue
		_expect(rect.position.x >= bounds.position.x - EDGE_EPSILON and rect.position.x + rect.size.x <= bounds.position.x + bounds.size.x + EDGE_EPSILON,
			"%s: %s reaches past the screen horizontally: %s in %s" % [tag, control.name, str(rect), str(bounds)])
		if _is_descendant(control, scroll):
			continue
		_expect(rect.position.y >= bounds.position.y - EDGE_EPSILON and rect.position.y + rect.size.y <= bounds.position.y + bounds.size.y + EDGE_EPSILON,
			"%s: %s reaches past the screen vertically: %s in %s" % [tag, control.name, str(rect), str(bounds)])


func _is_descendant(node: Node, ancestor: Node) -> bool:
	var cursor := node.get_parent()
	while cursor != null:
		if cursor == ancestor:
			return true
		cursor = cursor.get_parent()
	return false


## No Chinese copy under the approved floor, at any resolution.
func _check_font_floor(node: Node, tag: String) -> void:
	for control in _visible_controls(node):
		if not (control is Label) or (control as Label).text.strip_edges().is_empty():
			continue
		var font_size := (control as Label).get_theme_font_size("font_size")
		_expect(font_size >= FONT_FLOOR, "%s: %s is drawn at %dpx, under the %dpx floor" % [tag, control.name, font_size, FONT_FLOOR])


func _visible_controls(node: Node) -> Array[Control]:
	var found: Array[Control] = []
	for child in node.get_children():
		if child is Control and (child as Control).is_visible_in_tree():
			found.append(child)
		found.append_array(_visible_controls(child))
	return found


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _collect_layout(node: Node, lines: Array[String]) -> void:
	for child in node.get_children():
		if child is Control:
			var control := child as Control
			if control.get_global_rect().size.x > 0 and control.get_global_rect().size.y > 0:
				lines.append("%s visible=%s rect=%s min=%s" % [control.name, str(control.visible), str(control.get_global_rect()), str(control.get_custom_minimum_size())])
		_collect_layout(child, lines)
