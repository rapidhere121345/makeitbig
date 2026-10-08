extends SceneTree

const ResultScreenScript = preload("res://src/presentation/result_screen.gd")

## The approved Chinese UI floor (VISUAL_BASELINE.md: 正文 18-22 显示像素).
const FONT_FLOOR := 18
const EDGE_EPSILON := 0.5
const FULL_INSTANCE_ID := "drop_0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
const LONG_DROP_COUNT := 10
const ICON_ATLAS_PATH := "res://art/production/p1/early_loop_v01/atlas.json"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	var screen = ResultScreenScript.new()
	root.add_child(screen)
	var review_requests: Array[Dictionary] = []
	screen.loadout_review_requested.connect(func(instance_id: String, slot: String) -> void:
		review_requests.append({"instance_id": instance_id, "slot": slot})
	)
	screen.present({
		"outcome": "victory",
		"unlock": {
			"proxy_unlocked": true,
			"components": [
				{"id": "near_enemy_horizon", "name": "近敌视界"},
				{"id": "direct_gait", "name": "直趋步足"},
				{"id": "single_key_execution", "name": "单键执行"},
				{"id": "short_trace_memory", "name": "短痕记忆"},
			],
		},
		"rewards": {"drop_label": "白装核心箱"},
	})
	var text: String = screen.get_reward_text()
	_expect(text.contains("代理舱首次解锁") and text.contains("近敌视界、直趋步足、单键执行、短痕记忆"), "result: first proxy unlock did not list the four human-readable cores", failures)
	_expect(text.contains("前往代理舱，Auto 清房"), "result: first proxy unlock omitted the next step", failures)
	var core_rewards: GridContainer = screen.find_child("FirstKillCoreRewards", true, false)
	_expect(core_rewards != null and core_rewards.visible and core_rewards.get_child_count() == 4,
		"result: real first-unlock reward must render the four published core cards", failures)
	for core_id in ["near_enemy_horizon", "direct_gait", "single_key_execution", "short_trace_memory"]:
		_expect(screen.find_child("CoreReward_" + core_id, true, false) != null,
			"result: first-unlock core icon missing: " + core_id, failures)
	var compact_summary := screen.find_child("RewardSummary", true, false) as Label
	_expect(compact_summary != null and compact_summary.text.contains("代理核心 4 枚")
		and not compact_summary.text.contains("\n"),
		"result: first-unlock summary stayed a long text wall", failures)
	screen.present({"outcome": "victory", "unlock": {"proxy_unlocked": true,
		"components": [{"id": "near_enemy_horizon", "name": "近敌视界"}]}})
	_expect(core_rewards.get_child_count() == 1,
		"result: explicit partial reward was incorrectly padded to four granted cores", failures)
	screen.present({"outcome": "victory", "rewards": {"law_tallies_delta": {"inscribe": 1, "rewrite": 0, "refine": 0}, "drop_label": "普通长弓"}})
	text = screen.get_reward_text()
	_expect(text.contains("添铸律筹：1") and text.contains("普通长弓") and not text.contains("骰") and not text.contains("代理舱首次解锁"), "result: canonical ordinary reward was not rendered", failures)
	_expect(not core_rewards.visible and core_rewards.get_child_count() == 0,
		"result: ordinary reward retained first-kill core cards", failures)

	# --- proxy component drops: separate inventory semantics, no equipment action ---
	screen.present(_proxy_drop_payload())
	text = screen.get_reward_text()
	var proxy_cards: Array[String] = screen.get_proxy_component_card_texts()
	_expect(text.contains("代理组件已入库 · 尚未安装") and text.contains("当前代理构筑不变"),
		"result: proxy component settlement summary lost its uninstalled semantics", failures)
	_expect(proxy_cards.size() == 2 and proxy_cards[0].contains("标记棱镜 · 感知槽")
		and proxy_cards[0].contains("协议：区分标记、精英、Boss，并保留 2 个候选")
		and proxy_cards[1].contains("维距步足 · 行动槽")
		and proxy_cards[1].contains("距离带跟随穿刺箭的实际射程")
		and proxy_cards[0].contains("尚未安装，当前代理构筑不变"),
		"result: proxy component cards lost Chinese name, slot, full protocol, or unchanged-build copy", failures)
	var proxy_protocol := screen.find_child("ProxyComponentProtocol", true, false) as Label
	var proxy_detail := screen.find_child("ProxyComponentDetailButton", true, false) as Button
	_expect(proxy_protocol != null and not proxy_protocol.is_visible_in_tree()
		and proxy_detail != null and proxy_detail.text == "协议详情",
		"result: low-frequency proxy protocols were expanded into the main decision view", failures)
	_expect(screen.get_equipment_card_count() == 1
		and screen.find_child("ProxyComponentDrops", true, false) != screen.find_child("EquipmentCards", true, false)
		and screen.find_child("ReviewDrop_marking_prism", true, false) == null,
		"result: proxy component drops were mixed into equipment drops or actions", failures)
	screen.present({"outcome": "victory", "rewards": {}})
	_expect(screen.get_proxy_component_card_texts().is_empty()
		and not screen.get_reward_text().contains("代理组件已入库"),
		"result: repeated presentation retained stale proxy component drops", failures)

	# --- equipment drops: multiple pieces ---
	var drops: Array = [
		{
			"instance_id": "drop_0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
			"base_item_id": "oak_short_bow",
			"slot": "main_hand",
			"affixes": [{"family_id": "piercing_probability", "tier": 2}],
			"source": {"type": "campaign_drop", "id": "room_1"},
		},
		{
			"instance_id": "drop_fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210",
			"base_item_id": "leather_gloves",
			"slot": "gloves",
			"affixes": [{"family_id": "damage", "tier": 1}, {"family_id": "critical", "tier": 3}],
			"source": {"type": "campaign_drop", "id": "room_2"},
		},
		"not-a-dictionary",
		{"slot": "ring_1"},
	]
	screen.present({
		"outcome": "victory",
		"first_reward_tags": ["hunter_mark_skill", "equipment_compare_unlock", "breeding_split_item"],
		"rewards": {
			"drop_label": "旧掉落",
			"equipment_drops": drops,
			"equipment_drop_count": 2,
		},
	}, {}, {"inventory": {"equipment": drops}, "active_build": {"equipped_item_ids": {}}})
	text = screen.get_reward_text()
	var cards: Array[String] = _all_equipment_audits(screen)
	_expect(text.contains("本次获得装备 2 件"), "result: equipment header missing or wrong count", failures)
	_expect(text.contains("首通奖励") and text.contains("猎人印记") and text.contains("装备比较已开放")
		and text.contains("孳生分裂装备已入库存"),
		"result: first-clear acquisition facts disappeared when equipment also dropped", failures)
	_expect(cards.size() == 2, "result: expected exactly 2 equipment cards (bad entries skipped), got %d" % cards.size(), failures)
	if cards.size() == 2:
		_expect(cards[0].contains("主手") and cards[0].contains("oak_short_bow") and cards[0].contains("piercing_probability T2") and cards[0].contains("drop_01234567"), "result: first equipment card missing slot/base/affix/short id: " + cards[0], failures)
		_expect(cards[1].contains("手套") and cards[1].contains("damage T1") and cards[1].contains("critical T3"), "result: second equipment card missing multi-affix detail: " + cards[1], failures)
	var review_button := screen.find_child("ReviewDrop_drop_0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef", true, false) as Button
	var page_two := screen.find_child("EquipmentNextPage", true, false) as Button
	_expect(review_button != null and review_button.text == "比较（尚未装备）", "result: equipment drop has no direct loadout comparison action", failures)
	if review_button != null:
		var long_summary := review_button.get_parent().find_child("EquipmentCardText", false, false)
		_expect(long_summary != null and review_button.get_index() < long_summary.get_index(),
			"result: the direct comparison action is hidden below the long equipment description", failures)
		review_button.pressed.emit()
	_expect(review_requests == [{"instance_id": drops[0].instance_id, "slot": "main_hand"}],
		"result: loadout review action emitted the wrong drop identity or slot", failures)
	var face: Array[String] = screen.get_equipment_card_summaries()
	var first_detail := _open_equipment_detail_text(screen)
	_expect(first_detail.contains("未识别词条 II 阶") and not first_detail.contains("piercing_probability"),
		"result: unknown affix should be readable without raw IDs", failures)
	var next_face: Array[String] = []
	if page_two != null and not page_two.disabled:
		page_two.pressed.emit()
		next_face = screen.get_equipment_card_summaries()
	_expect(face.size() == 1 and next_face.size() == 1, "result: expected one card per page", failures)
	if face.size() == 1 and next_face.size() == 1:
		_expect(face[0].contains("已入库，尚未装备") and face[0].contains("未识别词条 II 阶"),
			"result: missing inventory state or readable affix: " + face[0], failures)
		_expect(face[0].contains("未知装备") and not face[0].contains("oak_short_bow") and not face[0].contains("piercing_probability"),
			"result: raw item IDs leaked onto card face", failures)
		_expect(not face[0].contains("drop_0123") and not next_face[0].contains("drop_fedc") and not face[0].contains("战力"),
			"result: internal identity or power recommendation leaked onto card face", failures)

	# --- repeated present must not accumulate cards ---
	screen.present({
		"outcome": "victory",
		"rewards": {"equipment_drops": drops, "equipment_drop_count": 2},
	})
	_expect(screen.get_equipment_card_count() == 1, "result: re-present accumulated equipment cards: %d" % screen.get_equipment_card_count(), failures)

	# --- count=0 falls back to legacy view, no phantom equipment ---
	screen.present({
		"outcome": "victory",
		"rewards": {"drop_id": "old_drop", "equipment_drops": drops, "equipment_drop_count": 0},
	})
	text = screen.get_reward_text()
	_expect(screen.get_equipment_card_count() == 0, "result: count=0 still rendered equipment cards", failures)
	_expect(screen.find_children("ReviewDrop_*", "Button", true, false).is_empty(), "result: a legacy-only reward exposed a phantom equipment review action", failures)
	_expect(not text.contains("本次获得装备"), "result: count=0 claimed equipment gains", failures)
	_expect(text.contains("old_drop"), "result: count=0 fallback lost legacy drop text: " + text, failures)

	# --- missing count field still shows drops; missing drops keeps legacy ---
	screen.present({"outcome": "victory", "rewards": {"equipment_drops": [drops[0]]}})
	_expect(screen.get_equipment_card_count() == 1 and screen.get_reward_text().contains("本次获得装备 1 件"), "result: drops without explicit count not displayed", failures)
	screen.present({"outcome": "victory", "first_reward_tags": ["dash_skill"], "rewards": {"equipment_drops": [drops[0]], "equipment_drop_count": "1"}})
	_expect(screen.get_equipment_card_count() == 1 and screen.get_reward_text().contains("突袭"), "result: numeric string count or first reward was not rendered", failures)
	screen.present({"outcome": "victory", "first_reward_tags": ["early_campaign_complete"], "rewards": {}})
	_expect(screen.get_reward_text().contains("前期旅程完成"), "result: Auto certification did not present the early-game graduation reward", failures)
	_expect(not (screen.get("_ending_button") as Button).visible, "result: ordinary victory exposed the ending action", failures)
	screen.present({"outcome": "final_victory", "first_reward_tags": ["early_campaign_complete"], "rewards": {}})
	_expect((screen.get("_ending_button") as Button).visible, "result: final victory did not expose the ending action", failures)

	# --- boss defeat: the first screen shows the single primary cause, its action,
	#     and the short report without losing rewards or equipment cards ---
	var defeat_drops: Array = [drops[0]]
	screen.present({
		"outcome": "defeat",
		"report": "DEFEAT — the ranger fell after 12.0s. Refit at base.",
		"primary_bottleneck": {
			"id": "growth_convergent",
			"title": "增长收敛，穿刺链未能成长",
			"action": "去定向支线获取增长概率词条，让穿刺链持续成长后再挑战",
			"destination": "mainline_05_growth_gate",
		},
		"first_reward_tags": ["hunter_mark_skill"],
		"rewards": {"equipment_drops": defeat_drops, "equipment_drop_count": 1},
	})
	var diagnosis: String = screen.get_diagnosis_text()
	_expect(diagnosis.contains("失败主因") and diagnosis.contains("增长收敛")
		and diagnosis.contains("行动建议") and diagnosis.contains("获取增长概率词条"),
		"result: defeat first screen did not show the single primary cause and action", failures)
	var report_text: String = screen.get_report_text()
	_expect(report_text.contains("战报") and report_text.contains("DEFEAT"),
		"result: defeat first screen did not show the short report", failures)
	_expect(screen.get_equipment_card_count() == 1
		and screen.get_reward_text().contains("本次获得装备 1 件")
		and screen.get_reward_text().contains("猎人印记"),
		"result: defeat diagnosis hid rewards or equipment cards", failures)

	# --- defeat without a bottleneck renders no phantom diagnosis; report still shows ---
	screen.present({"outcome": "defeat", "report": "short defeat note", "rewards": {}})
	_expect(screen.get_diagnosis_text().is_empty()
		and screen.get_report_text().contains("short defeat note"),
		"result: defeat without a bottleneck mis-rendered diagnosis or report", failures)

	# --- non-defeat outcomes never surface the defeat diagnosis ---
	screen.present({"outcome": "victory", "report": "won", "primary_bottleneck": {"id": "x", "title": "t", "action": "a"}})
	_expect(screen.get_diagnosis_text().is_empty() and screen.get_report_text().is_empty(),
		"result: victory surfaced the defeat diagnosis", failures)

	screen.present({"outcome": "victory", "rewards": {"drop_label": "白装核心箱"}})
	_expect(screen.get_equipment_card_count() == 0 and screen.get_reward_text().contains("白装核心箱"), "result: legacy-only result leaked equipment state", failures)

	# --- a settlement that never reported a reading must not draw a zero for it,
	#     while a reading that really is 0 is drawn as the number it is ---
	screen.present({"outcome": "victory", "rewards": {}})
	await _frames(2)
	for key in ["elapsed", "kills", "casts", "rooms"]:
		var hidden_tile: Control = screen.find_child("MetricTile_%s" % key, true, false)
		_expect(hidden_tile != null and not hidden_tile.visible,
			"result: %s was drawn for a field the settlement never reported" % key, failures)
	_expect(screen.find_child("MetricTile_ticks", true, false) == null,
		"result: internal tick count escaped the test console", failures)
	var sparse_detail: String = screen.get_detail_text()
	_expect(sparse_detail.contains("运行读数：未记录") and not sparse_detail.contains("0.00 秒") and not sparse_detail.contains("权威 Tick：0"),
		"result: the detail block fabricated readings the settlement never made: %s" % sparse_detail, failures)
	screen.present({
		"outcome": "victory",
		"elapsed_seconds": 0.0,
		"ticks": 0,
		"casts": 0,
		"defeated": 0,
		"rooms_completed": 0,
		"room_count": 1,
		"rewards": {},
	})
	await _frames(2)
	for key in ["elapsed", "kills", "casts", "rooms"]:
		var shown_tile: Control = screen.find_child("MetricTile_%s" % key, true, false)
		_expect(shown_tile != null and shown_tile.visible, "result: a reported %s was hidden" % key, failures)
	var zero_kills: Label = screen.find_child("MetricValue_kills", true, false)
	var zero_elapsed: Label = screen.find_child("MetricValue_elapsed", true, false)
	var zero_rooms: Label = screen.find_child("MetricValue_rooms", true, false)
	var drawn := [
		zero_kills.text if zero_kills != null else "<missing>",
		zero_elapsed.text if zero_elapsed != null else "<missing>",
		zero_rooms.text if zero_rooms != null else "<missing>",
	]
	_expect(zero_kills != null and zero_kills.text == "0" and zero_elapsed != null and zero_elapsed.text == "0.00 秒"
		and zero_rooms != null and zero_rooms.text == "0 / 1",
		"result: reported zeros were not drawn as the readings they are: %s" % str(drawn), failures)
	_expect(screen.get_detail_text().contains("权威 Tick：0") and screen.get_detail_text().contains("击杀：0"),
		"result: the detail table dropped a reported zero: %s" % screen.get_detail_text(), failures)

	# --- real card structure: one card per drop, the published Chinese name and
	#     affixes on the face, the complete field line still readable for audit ---
	screen.present({
		"outcome": "victory",
		"rewards": {
			"equipment_drops": [{
				"instance_id": FULL_INSTANCE_ID,
				"base_item_id": "ashwood_longbow",
				"slot": "main_hand",
				"affixes": [{"family_id": "piercing_probability", "tier": 2}],
			}],
			"equipment_drop_count": 1,
		},
	})
	await _frames(3)
	var card_nodes := _find_all(screen, "EquipmentCard")
	_expect(card_nodes.size() == 1, "result: the drop did not render exactly one named card", failures)
	var card_texts: Array[String] = screen.get_equipment_card_texts()
	_expect(card_texts.size() == 1 and card_texts[0].contains(FULL_INSTANCE_ID),
		"result: get_equipment_card_texts shortened the authoritative instance id: %s" % str(card_texts), failures)
	_expect(card_texts.size() == 1 and card_texts[0].contains("ashwood_longbow") and card_texts[0].contains("piercing_probability T2") and card_texts[0].contains("主手"),
		"result: the card lost a slot, base or affix name", failures)
	var published_face: Array[String] = screen.get_equipment_card_summaries()
	_expect(published_face.size() == 1 and published_face[0].contains("白蜡长弓") and published_face[0].contains("主手")
		and not published_face[0].contains("ashwood_longbow") and not published_face[0].contains(FULL_INSTANCE_ID),
		"result: the card face did not lead with the published item name and slot: %s" % str(published_face), failures)
	# The affix family the content table publishes is named; one it does not cover
	# keeps its raw id, which the earlier drop already exercised.
	screen.present({
		"outcome": "victory",
		"rewards": {
			"equipment_drops": [{
				"instance_id": FULL_INSTANCE_ID,
				"base_item_id": "ashwood_longbow",
				"slot": "main_hand",
				"affixes": [{"family_id": "piercing_continuation", "tier": 2}],
			}],
			"equipment_drop_count": 1,
		},
	})
	await _frames(2)
	var named_affix_face: Array[String] = [_open_equipment_detail_text(screen)]
	_expect(named_affix_face.size() == 1 and named_affix_face[0].contains("穿刺箭续行概率 II 阶")
		and named_affix_face[0].contains("+7 个百分点") and named_affix_face[0].contains("底材属性")
		and named_affix_face[0].contains("已收入装备库存")
		and not named_affix_face[0].contains("piercing_continuation"),
		"result: a published affix family was not shown under its Chinese name: %s" % str(named_affix_face), failures)
	# Full semantic payloads expose rune/law copy and optional current-to-equipped values.
	screen.present({
		"outcome": "victory",
		"rewards": {
			"equipment_drops": [{
				"instance_id": FULL_INSTANCE_ID,
				"base_item_id": "ashwood_longbow",
				"slot": "main_hand",
				"affixes": [{"family_id": "piercing_continuation", "tier": 2}],
				"rune_id": "breeding_split",
				"law_id": "pack_hunt_mark",
				"current_parameters": {"damage": 100.0, "turn": 0.4},
				"equipped_parameters": {"damage": 112.0, "turn": 0.36},
			}],
			"equipment_drop_count": 1,
		},
	})
	await _frames(2)
	var semantic_face: Array[String] = [_open_equipment_detail_text(screen)]
	_expect(semantic_face.size() == 1 and semantic_face[0].contains("孳生分裂") and semantic_face[0].contains("群猎印记")
		and semantic_face[0].contains("当前值 → 装备后值") and semantic_face[0].contains("转向时间（数值越低越好）"),
		"result: rune/law semantics or comparison copy missing: %s" % str(semantic_face), failures)
	screen.present({
		"outcome": "victory",
		"rewards": {
			"equipment_drops": [{
				"instance_id": FULL_INSTANCE_ID,
				"base_item_id": "ashwood_longbow",
				"slot": "main_hand",
				"affixes": [{"family_id": "piercing_probability", "tier": 2}],
			}],
			"equipment_drop_count": 1,
		},
	})
	await _frames(2)
	# The re-present swapped the cards, so the icon checks address the live nodes.
	card_nodes = _find_all(screen, "EquipmentCard")
	if FileAccess.file_exists(ICON_ATLAS_PATH) and card_nodes.size() == 1:
		var slot_badge := card_nodes[0].find_child("EquipmentSlotBadge", true, false) as TextureRect
		var subject_icon := card_nodes[0].find_child("EquipmentBaseIcon", true, false) as TextureRect
		_expect(slot_badge != null and subject_icon != null, "result: the published slot badge and the item icon were not both drawn", failures)
		if slot_badge != null and subject_icon != null:
			_expect(String(slot_badge.get_meta("canonical_id", "")) == "equipment_slot.main_hand"
				and String(subject_icon.get_meta("canonical_id", "")) == "equipment.ashwood_longbow",
				"result: the card icons are not addressed by canonical id", failures)
			_expect(subject_icon.custom_minimum_size == Vector2(64.0, 64.0) and slot_badge.custom_minimum_size == Vector2(32.0, 32.0),
				"result: the slot badge and the item icon must not be two same-size images: %s / %s" % [str(subject_icon.custom_minimum_size), str(slot_badge.custom_minimum_size)], failures)
		var full_size := 0
		for icon in _texture_rects(card_nodes[0]):
			if icon.custom_minimum_size.x >= 64.0:
				full_size += 1
		_expect(full_size == 1, "result: the card drew %d full-size icons instead of one subject" % full_size, failures)

	# --- raw authority fields remain available to the test console provider, but
	#     never create a second technical panel in the player result screen ---
	var settlement_payload := {
		"outcome": "defeat",
		"contract_id": "threshold_colossus",
		"mode": "Manual",
		"seed": 4242,
		"rooms_completed": 1,
		"room_count": 2,
		"ticks": 360,
		"elapsed_seconds": 12.0,
		"casts": 24,
		"defeated": 3,
		"failure_reason": "enemy/391/fan_ranged",
		"report": "DEFEAT — the ranger fell after 12.0s.",
		"room_results": [
			{"outcome": "victory", "ticks": 100, "casts": 9, "defeated": 3},
			{"outcome": "defeat", "ticks": 260, "casts": 15, "defeated": 0, "failure_reason": "enemy/391/fan_ranged"},
		],
		"future_authority_field": {"note": "kept"},
		"rewards": {"equipment_drops": [{"instance_id": FULL_INSTANCE_ID, "base_item_id": "ashwood_longbow", "slot": "main_hand", "affixes": []}], "equipment_drop_count": 1, "future_reward_field": 7},
	}
	screen.present(settlement_payload)
	await _frames(3)
	var detail_panel: Control = screen.find_child("ResultDetailPanel", true, false)
	var detail_toggle: Button = screen.find_child("DetailToggleButton", true, false)
	_expect(detail_panel == null and detail_toggle == null and not screen.is_detail_visible(),
		"result: raw result controls escaped the test console", failures)
	var detail: String = screen.get_detail_text()
	_expect(detail.contains(FULL_INSTANCE_ID), "result: the detail block dropped the untruncated instance id", failures)
	_expect(detail.contains("future_authority_field") and detail.contains("future_reward_field"),
		"result: metadata outside the known table was silently dropped: %s" % detail, failures)
	_expect(detail.contains("扇射游猎者") and detail.contains("房间 2"),
		"result: the per-room failure source was not presented as Chinese copy", failures)
	var bottleneck_tooltip := (screen.find_child("EvidenceBody_bottleneck", true, false) as Label).tooltip_text
	var visible_failure_copy := screen.get_run_facts_text() + "\n" + detail + "\n" + bottleneck_tooltip
	_expect(visible_failure_copy.contains("扇射游猎者") and not visible_failure_copy.contains("enemy/391/fan_ranged")
		and not visible_failure_copy.contains("fan_ranged") and not visible_failure_copy.contains("/391/"),
		"result: visible failure copy leaked a raw source id: %s" % visible_failure_copy, failures)
	_expect(screen.get_run_facts_text().contains("threshold_colossus") and screen.get_run_facts_text().contains("终止原因：扇射游猎者"),
		"result: the visible facts line lost the contract or the named loss: %s" % screen.get_run_facts_text(), failures)

	# --- the settlement payload is readable back for evidence capture ---
	_expect(String(screen.get_presented_result().get("contract_id", "")) == "threshold_colossus"
		and String(screen.get_presented_result().get("failure_reason", "")) == "enemy/391/fan_ranged"
		and String(settlement_payload.get("failure_reason", "")) == "enemy/391/fan_ranged",
		"result: the presented payload did not retain the raw failure reason", failures)

	# --- screen-bounded workspace: pinned header/footer, one scrolling middle,
	#     nothing past the sides, and no Chinese copy under 18px ---
	for logical_size in [Vector2i(1024, 576), Vector2i(1280, 720), Vector2i(1600, 900)]:
		var host := SubViewport.new()
		host.size = logical_size
		root.add_child(host)
		var sized_screen = ResultScreenScript.new()
		host.add_child(sized_screen)
		sized_screen.present(_proxy_drop_payload())
		await _frames(3)
		_expect(sized_screen.size == Vector2(logical_size),
			"result: proxy component layout did not adopt %dx%d: %s" % [logical_size.x, logical_size.y, str(sized_screen.size)], failures)
		for control in _visible_controls(sized_screen):
			var proxy_rect := control.get_global_rect()
			if proxy_rect.size.x <= 0.0 or proxy_rect.size.y <= 0.0:
				continue
			_expect(proxy_rect.position.x >= -EDGE_EPSILON and proxy_rect.end.x <= float(logical_size.x) + EDGE_EPSILON,
				"result: proxy component layout overflows horizontally at %dx%d: %s %s" % [logical_size.x, logical_size.y, control.name, str(proxy_rect)], failures)
		root.remove_child(host)
		host.free()
	screen.present(_long_drop_payload())
	await _frames(4)
	var bounds := Rect2(Vector2.ZERO, screen.size)
	var header: Control = screen.find_child("ResultHeader", true, false)
	var footer: Control = screen.find_child("ResultFooter", true, false)
	var scroll: ScrollContainer = screen.find_child("CurrentRunScroll", true, false)
	var content: Control = screen.find_child("ResultContent", true, false)
	_expect(screen.size == Vector2(1280.0, 720.0), "result: the screen did not take the 1280x720 shell canvas: %s" % str(screen.size), failures)
	_expect(bounds.encloses(header.get_global_rect()), "result: the header left the screen: %s" % str(header.get_global_rect()), failures)
	_expect(bounds.encloses(footer.get_global_rect()), "result: the action footer is not reachable on screen: %s" % str(footer.get_global_rect()), failures)
	_expect(scroll.get_v_scroll_bar().get_theme_stylebox("scroll") is StyleBoxEmpty
		and scroll.get_v_scroll_bar().get_theme_stylebox("grabber") is StyleBoxEmpty,
		"result: outer page scrollbar chrome should be hidden", failures)
	_expect(header.get_global_rect().position.y + header.get_global_rect().size.y <= scroll.get_global_rect().position.y + EDGE_EPSILON,
		"result: the body overlaps the header", failures)
	_expect(scroll.get_global_rect().position.y + scroll.get_global_rect().size.y <= footer.get_global_rect().position.y + EDGE_EPSILON,
		"result: the body overlaps the footer", failures)
	_expect(content.size.x <= screen.size.x + EDGE_EPSILON and scroll.get_h_scroll_bar().max_value <= scroll.size.x + EDGE_EPSILON,
		"result: the body can scroll sideways or is wider than the screen", failures)
	_expect(screen.find_child("ResultLootScroll", true, false) is ScrollContainer,
		"result: loot text needs a bounded scroll area independent of pagination", failures)
	var all_cards := _all_equipment_audits(screen)
	_expect(all_cards.size() == LONG_DROP_COUNT, "result: pagination lost equipment", failures)
	for index in all_cards.size():
		_expect(all_cards[index].contains("%s%d" % [FULL_INSTANCE_ID.substr(0, 40), index]),
			"result: pagination changed authoritative item identity/order at %d" % index, failures)
	_expect(screen.get_equipment_card_count() == 1, "result: paging accumulated cards", failures)

	for label in _visible_labels(screen):
		var font_size := label.get_theme_font_size("font_size")
		_expect(font_size >= FONT_FLOOR, "result: %s is drawn at %dpx, under the %dpx floor" % [label.name, font_size, FONT_FLOOR], failures)
	for control in _visible_controls(screen):
		var rect := control.get_global_rect()
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			continue
		_expect(rect.position.x >= -EDGE_EPSILON and rect.position.x + rect.size.x <= screen.size.x + EDGE_EPSILON,
			"result: %s reaches past the screen horizontally: %s" % [control.name, str(rect)], failures)
	for selector in ["ResultTitle", "ResultSubtitle", "ResultMetrics", "MetricValue_outcome", "ResultColumns", "ReportPanel", "DropPanel", "RewardSummary", "EquipmentCards", "ResultFooter", "ReturnToBaseButton", "EndingButton"]:
		_expect(screen.find_child(selector, true, false) != null, "result: the stable selector %s is missing" % selector, failures)
	_expect((screen.find_child("EndingButton", true, false) as Button).visible,
		"result: the long-drop payload was a final victory but the ending action stayed hidden", failures)

	await _check_first_victory_layout(drops.slice(0, 2), failures)
	root.remove_child(screen)
	screen.free()
	if failures.is_empty():
		print("PASS  test_result_screen.gd")
		quit(0)
		return
	for failure in failures:
		printerr("- %s" % failure)
	quit(1)


func _check_first_victory_layout(drops: Array, failures: Array[String]) -> void:
	var receipt := {
		"outcome": "victory", "contract_id": "mainline_01_first_hunt", "mode": "Manual",
		"rooms_completed": 1, "room_count": 1, "ticks": 17, "casts": 1, "defeated": 1,
		"first_reward_tags": ["hunter_mark_skill", "equipment_compare_unlock", "breeding_split_item"],
		"rewards": {"equipment_drops": drops, "equipment_drop_count": 2},
	}
	var profile := {"inventory": {"equipment": drops}, "active_build": {"equipped_item_ids": {}}}
	for logical_size in [Vector2i(1280, 720), Vector2i(1600, 900)]:
		var host := SubViewport.new()
		host.size = logical_size
		root.add_child(host)
		var screen = ResultScreenScript.new()
		host.add_child(screen)
		screen.present(receipt, {}, profile)
		await _frames(4)
		var loot := screen.find_child("ResultLootScroll", true, false) as ScrollContainer
		var pager := screen.find_child("EquipmentPagination", true, false) as Control
		var footer := screen.find_child("ResultFooter", true, false) as Control
		var panel := screen.find_child("DropPanel", true, false) as Control
		var summary := screen.find_child("RewardSummary", true, false) as Label
		var reward_detail_button := screen.find_child("RewardDetailButton", true, false) as Button
		var reward_detail_text := screen.find_child("RewardDetailText", true, false) as Label
		var footer_rect := footer.get_global_rect()
		var pager_rect := pager.get_global_rect()
		_expect((screen.find_child("ResultMetrics", true, false) as GridContainer).columns == 3,
			"result: settlement metrics must retain three columns", failures)
		_expect(summary.get_line_count() <= 2 and summary.text.contains("新装备 2 件"),
			"result: first-clear summary remained a reading wall at %s" % logical_size, failures)
		_expect(reward_detail_button != null and reward_detail_text != null and not reward_detail_text.visible
			and reward_detail_button.text == "奖励明细",
			"result: full reward copy lacked a clear collapsed entry at %s" % logical_size, failures)
		_expect(pager.is_visible_in_tree() and not loot.is_ancestor_of(pager)
			and panel.get_global_rect().encloses(pager_rect)
			and Rect2(Vector2.ZERO, Vector2(logical_size)).encloses(pager_rect),
			"result: first-clear pagination is not pinned inside the left panel at %s" % logical_size, failures)
		_expect(loot.get_global_rect().end.y <= pager_rect.position.y + EDGE_EPSILON
			and pager_rect.end.y <= footer_rect.position.y - EDGE_EPSILON,
			"result: first-clear text/pagination overlaps the actions at %s" % logical_size, failures)
		for page in 2:
			for label_name in ["RewardSummary", "EquipmentCardText", "EquipmentCardName"]:
				var label := screen.find_child(label_name, true, false) as Label
				if label == null:
					_expect(false, "result: missing first-clear item label " + label_name, failures)
					continue
				loot.ensure_control_visible(label)
				await _frames(2)
				_expect(label.get_visible_line_count() == label.get_line_count()
					and label.get_theme_font_size("font_size") >= FONT_FLOOR
					and loot.get_global_rect().encloses(label.get_global_rect()),
					"result: item/summary text is clipped or unreachable at %s: %s" % [logical_size, label_name], failures)
			_expect(pager.get_global_rect() == pager_rect and footer.get_global_rect() == footer_rect,
				"result: scrolling moved the page/footer actions at %s" % logical_size, failures)
			var audit: Array[String] = screen.get_equipment_card_texts()
			_expect(audit.size() == 1 and audit[0].contains(String(drops[page].instance_id)),
				"result: pinned pagination did not reach the correct reward at %s" % logical_size, failures)
			if page == 0:
				(screen.find_child("EquipmentNextPage", true, false) as Button).pressed.emit()
				await _frames(3)
		if reward_detail_button != null:
			reward_detail_button.pressed.emit()
			await _frames(2)
		_expect(reward_detail_text != null and reward_detail_text.visible
			and reward_detail_text.text.contains("首通奖励")
			and reward_detail_text.get_theme_font_size("font_size") >= FONT_FLOOR,
			"result: reward detail entry did not reveal authoritative copy at %s" % logical_size, failures)
		screen.present(receipt, {}, profile)
		screen.focus_equipment(String(drops[1].instance_id))
		await _frames(3)
		_expect(screen.get_equipment_card_texts()[0].contains(String(drops[1].instance_id))
			and screen.get_presented_result() == receipt,
			"result: returning from item review did not restore that item's page", failures)
		# Missing profile data must not be guessed from the historical receipt.
		screen.present(receipt)
		_expect(screen.get_equipment_card_summaries()[0].contains("库存状态未读取")
			and not screen.get_equipment_card_summaries()[0].contains("当前构筑不变"),
			"result: unavailable current state was fabricated from reward facts", failures)
		screen.present(receipt, {}, {"inventory": {"equipment": []}, "active_build": {"equipped_item_ids": {}}})
		var missing := screen.find_children("ReviewDrop_*", "Button", true, false)[0] as Button
		_expect(missing.disabled and missing.text == "已不在行囊中"
			and screen.get_equipment_card_summaries()[0].contains("获得记录保留")
			and screen.get_presented_result() == receipt,
			"result: no-longer-owned reward lost its receipt or exposed an invalid action", failures)
		root.remove_child(host)
		host.free()


func _all_equipment_audits(screen: Control) -> Array[String]:
	var all: Array[String] = []
	var previous := screen.find_child("EquipmentPreviousPage", true, false) as Button
	var next := screen.find_child("EquipmentNextPage", true, false) as Button
	for _page in 128:
		if previous == null or previous.disabled:
			break
		previous.pressed.emit()
	for _page in 128:
		all.append_array(screen.get_equipment_card_texts())
		if next == null or next.disabled:
			break
		next.pressed.emit()
	for _page in 128:
		if previous == null or previous.disabled:
			break
		previous.pressed.emit()
	return all


func _open_equipment_detail_text(screen: Control) -> String:
	var button := screen.find_child("EquipmentDetailButton", true, false) as Button
	if button == null:
		return ""
	button.pressed.emit()
	var body := screen.find_child("EquipmentDetailBody", true, false) as Label
	var text := body.text if body != null and body.is_visible_in_tree() else ""
	(screen.find_child("EquipmentDetailClose", true, false) as Button).pressed.emit()
	return text


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)


func _frames(count: int) -> void:
	for _index in count:
		await process_frame


## One real settlement payload with more drops than fit on the 720px canvas.
func _long_drop_payload() -> Dictionary:
	var drops: Array = []
	for index in LONG_DROP_COUNT:
		drops.append({
			"instance_id": "%s%d" % [FULL_INSTANCE_ID.substr(0, 40), index],
			"base_item_id": "ashwood_longbow" if index == 0 else "turnfeather_gloves",
			"slot": "main_hand" if index == 0 else "gloves",
			"affixes": [{"family_id": "damage", "tier": 1}],
		})
	return {
		"outcome": "final_victory",
		"contract_id": "auto_certification",
		"mode": "Auto",
		"rooms_completed": 1,
		"room_count": 1,
		"ticks": 14,
		"elapsed_seconds": 0.47,
		"casts": 4,
		"defeated": 1,
		"rewards": {"equipment_drops": drops, "equipment_drop_count": LONG_DROP_COUNT},
	}


func _proxy_drop_payload() -> Dictionary:
	return {
		"outcome": "victory",
		"proxy_component_drops": [
			{"id": "marking_prism", "name": "标记棱镜", "slot": "perception", "rarity": "white", "type": "proxy_core", "protocol": "区分标记、精英、Boss，并保留 2 个候选", "source_contract": "branch_marking"},
			{"id": "distance_keeping_gait", "name": "维距步足", "slot": "movement", "rarity": "white", "type": "proxy_core", "protocol": "按玩家预设的近、中、远距离带持续调整；距离带跟随穿刺箭的实际射程，并会避免在边界反复走动", "source_contract": "branch_distance"},
		],
		"rewards": {
			"equipment_drops": [{"instance_id": "equipment_alone", "base_item_id": "ashwood_longbow", "slot": "main_hand", "affixes": []}],
			"equipment_drop_count": 1,
		},
	}


func _find_all(node: Node, node_name: String) -> Array[Node]:
	var found: Array[Node] = []
	for child in node.get_children():
		if child.name == node_name:
			found.append(child)
		found.append_array(_find_all(child, node_name))
	return found


## Every TextureRect under a node, which is how this test counts how many published
## cells one card really draws and how large each of them is.
func _texture_rects(node: Node) -> Array[TextureRect]:
	var found: Array[TextureRect] = []
	for child in node.get_children():
		if child is TextureRect:
			found.append(child)
		found.append_array(_texture_rects(child))
	return found


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
