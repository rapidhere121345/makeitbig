class_name ContractScreen
extends Control

signal start_requested(config: Dictionary)
signal cancel_requested

const ShellThemeScript = preload("res://src/presentation/shell_theme.gd")
const EarlyCampaignRegistryScript = preload("res://src/content/early_campaign_registry.gd")
const FacilityArtScript = preload("res://src/presentation/facility_art.gd")
const EarlySkillRegistryScript = preload("res://src/content/early_skill_registry.gd")
const PlayerReadableBuildScript = preload("res://src/presentation/player_readable_build.gd")
const PlayerFacingStatusScript = preload("res://src/presentation/player_facing_status.gd")
const MODES := ["Manual", "Auto"]
const NODE_TITLES := {
	"tutorial_ranger_basics": "序章 · 游侠基础",
	"mainline_01_first_hunt": "主线 01 · 初次狩猎",
	"mainline_02_priority_under_pressure": "主线 02 · 压力下的优先级",
	"mainline_03_first_elite": "主线 03 · 首个精英",
	"mainline_04_hazard_and_forge": "主线 04 · 危地与锻炉",
	"mainline_05_growth_gate": "主线 05 · 增长门槛",
	"threshold_colossus": "首领 · 阈门巨像",
	"auto_certification": "毕业考核 · AUTO",
	"side_targeted_equipment": "支线 · 定向装备",
	"side_affix_and_law_tallies": "支线 · 词条与律筹",
	"first_contract": "初次契约",
}
const TAG_LABELS := {
	"starter_fixed": "固定起步装",
	"equipment_general": "通用装备",
	"main_hand": "主手",
	"off_hand": "副手",
	"gloves": "手套",
	"ring": "戒指",
	"piercing_probability": "续行概率",
	"shared_lifetime": "共享寿命",
	"projectile_speed": "箭速",
	"targeting_distance": "寻敌距离",
	"turn_time": "转向时间",
	"damage": "伤害",
	"critical": "暴击",
	"survival": "生存",
	"inscribe_tally": "添铸律筹",
	"rewrite_tally": "改写律筹",
	"refine_tally": "精炼律筹",
	"proxy_core_fixed": "固定白色代理核心",
	"starter_loadout": "起步装备",
	"hunter_mark_skill": "猎人印记",
	"dash_skill": "突袭",
	"equipment_compare_unlock": "装备比较",
	"breeding_split_item": "孳生分裂装备（获得后需在备行架装备）",
	"pack_hunt_mark_item": "群猎印记装备（获得后需在备行架装备）",
	"law_forge_unlock": "律筹锻炉",
	"fixed_four_white_proxy_cores": "四枚白色代理核心",
	"early_campaign_complete": "前期毕业",
}
## Five values for deciding whether to leave town; the complete rules live in details.
const BUILD_PARAMETER_ORDER: Array[String] = ["damage", "max_health", "d", "p", "T"]
const ROAD_CONTEXT := {
	"mainline_01_first_hunt": "旧路外段 · 炉边镇门边已冷，外段仍需照看。清通旧路，带回能用的东西。",
	"mainline_02_priority_under_pressure": "旧路装卸区 · 沿旧货道深入，留意逼近与远处的威胁。",
	"mainline_03_first_elite": "回收区 · 寻找能改变手中装备的战利品，先应对精英的屏障。",
	"mainline_04_hazard_and_forge": "危地 · 在暴露地带与火线间找路，为镇里的锻炉带回律筹。",
	"mainline_05_growth_gate": "旧路深处 · 带上整理好的装备，检验它能否应对援军与危地。",
	"threshold_colossus": "阈门 · 巨像守在路前。准备好了，就去应战。",
	"auto_certification": "代行考核 · 让代理按你的整备行动，完成一次基础 Auto 契约。",
	"side_targeted_equipment": "旧路回收 · 按装备缺口寻找主副手、手套与戒指。",
	"side_affix_and_law_tallies": "旧路回收 · 寻找机制装备与律筹，带回镇里继续整备。",
}
const MAX_SAFE_SEED_TEXT := "9007199254740991"

var _built := false
var _profile: Dictionary = {}
var _previous_config: Dictionary = {}
var _build_snapshot: Dictionary = {}
var _skill_registry = EarlySkillRegistryScript.new()
var _player_readable = PlayerReadableBuildScript.new()
var _status_message := ""
var _objective_label: Label
var _details_button: Button
var _details_dialog: AcceptDialog
var _details_label: Label
var _campaign_registry = EarlyCampaignRegistryScript.new()
var _profile_label: Label
var _build_label: Label
var _contract_picker: OptionButton
var _contract_info_label: Label
var _mode_picker: OptionButton
var _auto_lock_label: Label
var _seed_edit: LineEdit
var _status_label: Label
var _start_button: Button
var _cancel_button: Button
var _campaign_nodes: Array[Dictionary] = []
var _workspace: HBoxContainer
var _contract_scroll: ScrollContainer
var _build_scroll: ScrollContainer
var _art = FacilityArtScript.new()
var _start_transition_active := false
var _start_emitted := false
var _pending_start_config: Dictionary = {}
var _transition_overlay: Control
var _transition_tween: Tween
var _transition_control_state: Dictionary = {}
var _presentation_enabled_override: Variant = null


func _ready() -> void:
	_skill_registry.load_all()
	_campaign_registry.load_campaign()
	_build_ui()
	_apply_presentation()
	_contract_picker.grab_focus()


func present(profile: Dictionary, previous_config: Dictionary = {}, status_message: String = "", build_snapshot: Dictionary = {}) -> void:
	_profile = profile.duplicate(true)
	_previous_config = previous_config.duplicate(true)
	_build_snapshot = build_snapshot.duplicate(true)
	_status_message = status_message
	_start_emitted = false
	if _built:
		_apply_presentation()


func _build_ui() -> void:
	if _built:
		return
	_built = true
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = ShellThemeScript.create()
	ShellThemeScript.add_backdrop(self, "contract_screen")
	var margins := MarginContainer.new()
	margins.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margins.add_theme_constant_override("margin_left", 28)
	margins.add_theme_constant_override("margin_top", 20)
	margins.add_theme_constant_override("margin_right", 28)
	margins.add_theme_constant_override("margin_bottom", 20)
	add_child(margins)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 12)
	margins.add_child(page)
	var title_header := HBoxContainer.new()
	page.add_child(title_header)
	var title := Label.new()
	title.text = "行路契台 · 从炉边镇出发"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", ShellThemeScript.BONE)
	title_header.add_child(title)
	_profile_label = Label.new()
	_profile_label.add_theme_font_size_override("font_size", 18)
	_profile_label.add_theme_color_override("font_color", ShellThemeScript.NEUTRAL)
	title_header.add_child(_profile_label)
	var subtitle := _field_label("看清这趟要做什么，带上准备好的弓。")
	subtitle.add_theme_font_size_override("font_size", 18)
	subtitle.add_theme_color_override("font_color", ShellThemeScript.NEUTRAL)
	page.add_child(subtitle)
	_workspace = HBoxContainer.new()
	_workspace.name = "ContractWorkspace"
	_workspace.add_theme_constant_override("separation", 12)
	_workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(_workspace)
	_contract_scroll = _workspace_scroll("ContractScroll")
	var content := _workspace_card(_contract_scroll, "ContractPanel")
	var board_heading := HBoxContainer.new()
	content.add_child(board_heading)
	if _art.load_art():
		var mark: Texture2D = _art.mark("contract")
		if mark != null:
			var icon := _create_station_icon(mark)
			icon.name = "ContractMark"
			icon.custom_minimum_size = Vector2(64, 64)
			board_heading.add_child(icon)
	var source_title := _field_label("这趟去哪里")
	source_title.name = "ContractSourceHeading"
	source_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	source_title.add_theme_font_size_override("font_size", 22)
	board_heading.add_child(source_title)
	_build_scroll = _workspace_scroll("ContractBuildScroll")
	var build_content := VBoxContainer.new()
	build_content.name = "ContractBuildContent"
	build_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	build_content.add_theme_constant_override("separation", 18)
	_build_scroll.add_child(build_content)
	var build_title := _field_label("随身整备")
	build_title.add_theme_font_size_override("font_size", 22)
	build_content.add_child(build_title)
	_build_label = Label.new()
	_build_label.name = "BuildLabel"
	_build_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_build_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	build_content.add_child(_build_label)
	var build_note := _field_label("需调整装备？返回镇里的备行架。")
	build_note.add_theme_font_size_override("font_size", 18)
	build_note.add_theme_color_override("font_color", ShellThemeScript.NEUTRAL)
	build_content.add_child(build_note)
	_details_button = Button.new()
	_details_button.name = "BuildDetailsButton"
	_details_button.text = "查看技能与构筑详情"
	_details_button.pressed.connect(_open_build_details)
	build_content.add_child(_details_button)

	_contract_picker = OptionButton.new()
	_contract_picker.name = "ContractPicker"
	_contract_picker.fit_to_longest_item = false
	_contract_picker.item_selected.connect(_on_contract_selected)
	content.add_child(_contract_picker)
	_objective_label = _field_label("")
	_objective_label.name = "CombatObjective"
	_objective_label.add_theme_font_size_override("font_size", 24)
	_objective_label.add_theme_color_override("font_color", ShellThemeScript.BONE)
	content.add_child(_objective_label)
	_contract_info_label = Label.new()
	_contract_info_label.name = "ContractInfoLabel"
	_contract_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_contract_info_label.add_theme_font_size_override("font_size", 18)
	content.add_child(_contract_info_label)

	content.add_child(_field_label("出征模式 · 出发后锁定"))
	_mode_picker = OptionButton.new()
	_mode_picker.name = "ModePicker"
	for mode: String in MODES:
		_mode_picker.add_item("手动 / Manual" if mode == "Manual" else "代行 / Auto")
	content.add_child(_mode_picker)
	_auto_lock_label = Label.new()
	_auto_lock_label.name = "AutoLockLabel"
	_auto_lock_label.text = "代行尚未解锁：先手动击败阈门巨像。"
	_auto_lock_label.add_theme_font_size_override("font_size", 18)
	_auto_lock_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_auto_lock_label.add_theme_color_override("font_color", ShellThemeScript.WARNING)
	content.add_child(_auto_lock_label)
	var seed_label := _field_label("契约种子")
	seed_label.visible = false
	content.add_child(seed_label)
	_seed_edit = LineEdit.new()
	_seed_edit.name = "ContractSeed"
	_seed_edit.placeholder_text = "例如：52969"
	_seed_edit.max_length = 20
	_seed_edit.visible = false
	content.add_child(_seed_edit)

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_color_override("font_color", ShellThemeScript.WARNING)
	page.add_child(_status_label)
	var actions := HBoxContainer.new()
	actions.name = "ContractActions"
	actions.add_theme_constant_override("separation", 12)
	page.add_child(actions)
	_cancel_button = Button.new()
	_cancel_button.name = "CancelContractButton"
	_cancel_button.text = "返回炉边镇"
	_cancel_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cancel_button.pressed.connect(_on_cancel_pressed)
	actions.add_child(_cancel_button)
	_start_button = Button.new()
	_start_button.name = "StartButton"
	_start_button.text = "接下契约 · 出发"
	_start_button.add_theme_stylebox_override("normal", ShellThemeScript.panel_style("selected"))
	_start_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_start_button.pressed.connect(_on_start_pressed)
	actions.add_child(_start_button)
func _workspace_scroll(node_name: String) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.name = node_name
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ShellThemeScript.hide_passive_scrollbar_chrome(scroll)
	_workspace.add_child(scroll)
	return scroll


func _workspace_card(scroll: ScrollContainer, node_name: String) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.name = node_name
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	panel.add_child(content)
	return content


func _field_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _create_station_icon(texture: Texture2D) -> TextureRect:
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(112, 112)
	icon.texture = texture
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon


func _apply_presentation() -> void:
	var class_id := str(_profile.get("initial_class", "未建立"))
	_profile_label.text = "当前档案：%s" % ("游侠" if class_id == "ranger" else class_id)
	var active_build := _active_build()
	_build_label.text = _build_summary(active_build)
	if _details_dialog != null:
		_details_dialog.hide()
	_campaign_nodes = _campaign_node_snapshot()
	_populate_contract_picker()
	_seed_edit.text = str(_previous_config.get("seed", 52969))
	_apply_selected_contract()
	_set_status(_status_message)


func _campaign_node_snapshot() -> Array[Dictionary]:
	var campaign_value: Variant = _build_snapshot.get("campaign", {})
	var campaign: Dictionary = campaign_value if campaign_value is Dictionary else {}
	var nodes_value: Variant = campaign.get("nodes", _build_snapshot.get("campaign_nodes", []))
	var nodes: Array[Dictionary] = []
	if nodes_value is Array:
		for entry_value in nodes_value:
			if entry_value is Dictionary:
				nodes.append((entry_value as Dictionary).duplicate(true))
	if not nodes.is_empty():
		return nodes
	return [{
		"id": "first_contract",
		"kind": "legacy",
		"available": true,
		"completed": false,
		"repeatable": true,
		"allowed_modes": MODES.duplicate(),
		"room_count": 1,
		"drop_tags": [],
		"first_reward_tags": [],
		"unlock_prerequisites": [],
	}]


func _populate_contract_picker() -> void:
	_contract_picker.clear()
	for node in _campaign_nodes:
		var node_id := String(node.get("id", ""))
		var completed := bool(node.get("completed", false))
		var repeatable := bool(node.get("repeatable", false))
		var available := bool(node.get("available", false))
		var prefix := "[完成] " if completed and not repeatable else ("[锁定] " if not available else "")
		_contract_picker.add_item(prefix + String(NODE_TITLES.get(node_id, node_id)))
		var index := _contract_picker.item_count - 1
		_contract_picker.set_item_metadata(index, node.duplicate(true))
		_contract_picker.set_item_disabled(index, not available or (completed and not repeatable))

	var campaign_value: Variant = _build_snapshot.get("campaign", {})
	var campaign: Dictionary = campaign_value if campaign_value is Dictionary else {}
	var requested_id := String(_previous_config.get("contract_id", ""))
	if requested_id.is_empty() or _find_selectable_contract(requested_id) < 0:
		requested_id = String(campaign.get("next_mainline_node_id", ""))
	var selected := _find_selectable_contract(requested_id)
	if selected < 0:
		selected = _first_selectable_contract()
	if selected >= 0:
		_contract_picker.select(selected)
	_start_button.disabled = selected < 0


func _find_selectable_contract(node_id: String) -> int:
	for index in _contract_picker.item_count:
		var node_value: Variant = _contract_picker.get_item_metadata(index)
		if node_value is Dictionary and String((node_value as Dictionary).get("id", "")) == node_id and not _contract_picker.is_item_disabled(index):
			return index
	return -1


func _first_selectable_contract() -> int:
	for index in _contract_picker.item_count:
		if not _contract_picker.is_item_disabled(index):
			return index
	return -1


func _selected_contract() -> Dictionary:
	if _contract_picker == null or _contract_picker.selected < 0:
		return {}
	var value: Variant = _contract_picker.get_item_metadata(_contract_picker.selected)
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func _apply_selected_contract() -> void:
	var node := _selected_contract()
	if node.is_empty():
		_objective_label.text = "暂时没有可执行的契约"
		_contract_info_label.text = "先回镇里整备。"
		_start_button.disabled = true
		return
	var auto_unlocked := bool(_build_snapshot.get("auto_mode_unlocked", false))
	var allowed_modes_value: Variant = node.get("allowed_modes", ["Manual"])
	var allowed_modes: Array = allowed_modes_value if allowed_modes_value is Array else ["Manual"]
	for index in MODES.size():
		var mode := String(MODES[index])
		var disabled := mode not in allowed_modes or (mode == "Auto" and not auto_unlocked)
		_mode_picker.set_item_disabled(index, disabled)
		_mode_picker.set_item_tooltip(index, "请先击败阈门巨像。" if mode == "Auto" and not auto_unlocked else "")
	var requested_mode := String(_previous_config.get("mode", "Manual"))
	var requested_index := MODES.find(requested_mode)
	if requested_index < 0 or _mode_picker.is_item_disabled(requested_index):
		requested_index = -1
		for index in MODES.size():
			if not _mode_picker.is_item_disabled(index):
				requested_index = index
				break
	if requested_index >= 0:
		_mode_picker.select(requested_index)
	_auto_lock_label.visible = "Auto" in allowed_modes and not auto_unlocked
	_objective_label.text = _combat_objective(node)
	_contract_info_label.text = _contract_summary(node)
	_apply_suggested_seed(node)
	_start_button.disabled = requested_index < 0


## Reads authored combat objectives. Repeatable routes show their possible tasks,
## rather than pretending their rooms have already been rolled.
func _combat_objective(node: Dictionary) -> String:
	var definition: Dictionary = _campaign_registry.get_node(String(node.get("id", "")))
	var objectives: Array[String] = []
	var names := {"clear": "清除敌人", "hunt_elite": "击败精英", "timed_break": "限时突破（超时只失去加奖）"}
	var rooms: Array = definition.get("room_sequence", [])
	for value: Variant in rooms:
		if not value is Dictionary:
			continue
		var room: Dictionary = value
		var task := "击败阈门巨像" if String(room.get("boss_id", "")) == "threshold_colossus" else String(names.get(String(room.get("objective_id", "")), "完成房间目标"))
		if not task in objectives:
			objectives.append(task)
	if objectives.is_empty():
		var template: Dictionary = definition.get("room_template", {})
		for value: Variant in template.get("objective_ids", []):
			objectives.append(String(names.get(String(value), "完成房间目标")))
	var prefix := "可能目标" if bool(node.get("repeatable", false)) else "战斗目标"
	return "%s · %d 个房间\n%s" % [prefix, maxi(1, int(node.get("room_count", 1))), " / ".join(objectives) if not objectives.is_empty() else "完成房间内标示的目标"]


func _contract_summary(node: Dictionary) -> String:
	var lines: Array[String] = []
	var context := String(ROAD_CONTEXT.get(String(node.get("id", "")), "核对目标与整备，再决定是否出发。"))
	lines.append(context)
	lines.append("")
	lines.append("战利品方向：%s" % _tag_summary(node.get("drop_tags", [])))
	if not bool(node.get("completed", false)):
		lines.append("首通所得：%s" % _tag_summary(node.get("first_reward_tags", [])))
	if node.has("experience_reward"):
		lines.append("完成经验：%d%s" % [int(node.get("experience_reward", 0)), "（含首通）" if not bool(node.get("completed", false)) else ""])
	if not bool(node.get("available", false)):
		lines.append("解锁条件：%s" % _node_title_summary(node.get("unlock_prerequisites", [])))
	var progress := _repeatable_progress_text(node)
	if not progress.is_empty():
		lines.append(progress.trim_prefix("\n"))
	return "\n".join(lines)


func _apply_suggested_seed(node: Dictionary) -> void:
	var value: Variant = node.get("suggested_seed", null)
	if not _is_exact_int(value):
		return
	_seed_edit.text = str(int(value))


func _is_exact_int(value: Variant) -> bool:
	return value is int and not (value is bool)


func _is_non_negative_int(value: Variant) -> bool:
	return _is_exact_int(value) and int(value) >= 0


func _is_positive_int(value: Variant) -> bool:
	return _is_exact_int(value) and int(value) >= 1


func _repeatable_progress_text(node: Dictionary) -> String:
	if not bool(node.get("repeatable", false)):
		return ""
	var completion_value: Variant = node.get("completion_count", null)
	var attempt_value: Variant = node.get("next_attempt_number", null)
	var completion := int(completion_value) if _is_non_negative_int(completion_value) else -1
	var attempt := int(attempt_value) if _is_positive_int(attempt_value) else -1
	if attempt < 0 and completion >= 0:
		attempt = completion + 1
	elif completion < 0 and attempt >= 1:
		completion = attempt - 1
	if attempt < 1 or completion < 0:
		return ""
	var lines := "\n已完成 %d 次 / 本次第 %d 次" % [completion, attempt]
	if String(node.get("id", "")) == "side_affix_and_law_tallies":
		lines += "\n每 3 次完成触发一次定向装备保底"
		if attempt % 3 == 0:
			lines += "：本次触发保底"
		else:
			lines += "（距保底还有 %d 次）" % (3 - attempt % 3)
	return lines


func _tag_summary(value: Variant) -> String:
	if not (value is Array) or (value as Array).is_empty():
		return "无"
	var labels: Array[String] = []
	for tag_value in (value as Array):
		var tag := String(tag_value)
		labels.append(String(TAG_LABELS.get(tag, tag)))
	return "、".join(labels)


func _node_title_summary(value: Variant) -> String:
	if not (value is Array) or (value as Array).is_empty():
		return "无"
	var labels: Array[String] = []
	for node_id_value in (value as Array):
		var node_id := String(node_id_value)
		labels.append(String(NODE_TITLES.get(node_id, node_id)))
	return "、".join(labels)


func _set_status(message: String) -> void:
	_status_label.text = PlayerFacingStatusScript.message(message)
	_status_label.visible = not message.is_empty()


func _on_start_pressed() -> void:
	## In a visible run the route leaves as soon as the transition emits, so a
	## second click is blocked for the lifetime of this screen. Headless checks use
	## the immediate path and still need to exercise validation on later inputs.
	if _start_transition_active or (_start_emitted and _should_animate_start_transition()):
		return
	var seed_text := _seed_edit.text.strip_edges()
	var parsed_seed := _parse_seed_text(seed_text)
	if not bool(parsed_seed.get("ok", false)):
		_set_status("契约准备数据无效，请返回后重试。")
		return
	var active_build := _active_build()
	var preset_id := str(active_build.get("preset_id", "")).strip_edges()
	if preset_id.is_empty():
		preset_id = str(_resolved_build().get("growth_classification", "")).strip_edges()
	if preset_id.is_empty():
		_set_status("当前构筑缺少必要信息，无法开始契约。")
		return
	if _mode_picker.selected < 0 or _mode_picker.is_item_disabled(_mode_picker.selected):
		_set_status("该模式不可用，请选择已解锁的出征模式。")
		return
	var selected_contract := _selected_contract()
	if selected_contract.is_empty() or not bool(selected_contract.get("available", false)):
		_set_status("该节点尚未满足解锁条件。")
		return
	if bool(selected_contract.get("completed", false)) and not bool(selected_contract.get("repeatable", false)):
		_set_status("该主线节点已经完成。")
		return
	var config := {
		"contract_id": String(selected_contract.get("id", "")),
		"mode": MODES[_mode_picker.selected],
		"preset_id": preset_id,
		"seed": int(parsed_seed.get("value", 0)),
		"room_count": maxi(1, int(selected_contract.get("room_count", 1))),
	}
	_set_status("")
	_begin_start_transition(config)


## Test and automation hook: it completes a visible start transition immediately.
## The same path is used automatically when no display is available.
func complete_start_transition() -> void:
	if not _start_transition_active:
		return
	if _transition_tween != null and _transition_tween.is_valid():
		_transition_tween.kill()
	_transition_tween = null
	if is_instance_valid(_transition_overlay):
		_transition_overlay.queue_free()
	_transition_overlay = null
	var config := _pending_start_config.duplicate(true)
	_pending_start_config.clear()
	_start_transition_active = false
	_start_emitted = true
	_restore_transition_controls()
	start_requested.emit(config)


func set_presentation_enabled(enabled: bool) -> void:
	_presentation_enabled_override = enabled


func _begin_start_transition(config: Dictionary) -> void:
	_start_transition_active = true
	_pending_start_config = config.duplicate(true)
	if _details_dialog != null:
		_details_dialog.hide()
	_lock_transition_controls()
	if not _should_animate_start_transition():
		complete_start_transition()
		return
	_transition_overlay = _create_start_transition_overlay()
	add_child(_transition_overlay)
	_transition_tween = create_tween()
	_transition_tween.set_parallel(true)
	_transition_tween.tween_property(_transition_overlay, "modulate:a", 1.0, 0.10)
	var card := _transition_overlay.get_node("Center/AcceptanceCard") as Control
	var rule := _transition_overlay.get_node("Center/AcceptanceCard/Content/Rule") as Control
	_transition_tween.tween_property(card, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_transition_tween.tween_property(rule, "custom_minimum_size:x", 320.0, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_transition_tween.chain().tween_interval(0.14)
	_transition_tween.chain().tween_property(_transition_overlay, "modulate:a", 0.0, 0.16)
	_transition_tween.finished.connect(complete_start_transition)


func _create_start_transition_overlay() -> Control:
	var overlay := Control.new()
	overlay.name = "ContractAcceptanceTransition"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 100
	overlay.modulate = Color(1.0, 1.0, 1.0, 0.0)
	var veil := ColorRect.new()
	veil.name = "Veil"
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.color = Color(ShellThemeScript.INK, 0.86)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(veil)
	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center)
	var card := PanelContainer.new()
	card.name = "AcceptanceCard"
	card.custom_minimum_size = Vector2(460, 184)
	card.pivot_offset = Vector2(230, 92)
	card.scale = Vector2(0.96, 0.96)
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(ShellThemeScript.DEEP_BLUE, 0.97)
	card_style.border_color = ShellThemeScript.COPPER_DULL
	card_style.set_border_width_all(1)
	card_style.set_corner_radius_all(2)
	card_style.content_margin_left = 28.0
	card_style.content_margin_top = 24.0
	card_style.content_margin_right = 28.0
	card_style.content_margin_bottom = 24.0
	card.add_theme_stylebox_override("panel", card_style)
	center.add_child(card)
	var content := VBoxContainer.new()
	content.name = "Content"
	content.add_theme_constant_override("separation", 8)
	card.add_child(content)
	var eyebrow := Label.new()
	eyebrow.text = "契约已锁定"
	eyebrow.add_theme_font_size_override("font_size", 18)
	eyebrow.add_theme_color_override("font_color", ShellThemeScript.NEUTRAL)
	content.add_child(eyebrow)
	var title := Label.new()
	title.text = "出征确认"
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", ShellThemeScript.BONE)
	content.add_child(title)
	var rule := ColorRect.new()
	rule.name = "Rule"
	rule.custom_minimum_size = Vector2(4, 2)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	rule.color = ShellThemeScript.COPPER_DULL
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(rule)
	var note := Label.new()
	note.text = "整备行路 · 即将进入契约"
	note.add_theme_font_size_override("font_size", 20)
	note.add_theme_color_override("font_color", ShellThemeScript.NEUTRAL)
	content.add_child(note)
	return overlay


func _lock_transition_controls() -> void:
	_transition_control_state = {
		"contract_disabled": _contract_picker.disabled,
		"mode_disabled": _mode_picker.disabled,
		"seed_editable": _seed_edit.editable,
		"start_disabled": _start_button.disabled,
		"cancel_disabled": _cancel_button.disabled,
	}
	_contract_picker.disabled = true
	_mode_picker.disabled = true
	_seed_edit.editable = false
	_start_button.disabled = true
	_cancel_button.disabled = true


func _restore_transition_controls() -> void:
	if _transition_control_state.is_empty():
		return
	_contract_picker.disabled = bool(_transition_control_state.get("contract_disabled", false))
	_mode_picker.disabled = bool(_transition_control_state.get("mode_disabled", false))
	_seed_edit.editable = bool(_transition_control_state.get("seed_editable", true))
	_start_button.disabled = bool(_transition_control_state.get("start_disabled", false))
	_cancel_button.disabled = bool(_transition_control_state.get("cancel_disabled", false))
	_transition_control_state.clear()


func _should_animate_start_transition() -> bool:
	if _presentation_enabled_override != null:
		return bool(_presentation_enabled_override)
	if OS.has_feature("headless"):
		return false
	var display_name := DisplayServer.get_name().to_lower()
	if display_name.is_empty() or display_name.contains("headless"):
		return false
	for raw_arg in OS.get_cmdline_user_args():
		var arg := String(raw_arg).to_lower()
		if arg == "--presentation-off" or arg.begins_with("--presentation-off=") or arg == "--auto-smoke" or arg == "--test":
			return false
	return true


func _parse_seed_text(text: String) -> Dictionary:
	var normalized := text.strip_edges()
	if normalized.is_empty():
		return {"ok": false}
	var negative := normalized.begins_with("-")
	var digits := normalized.substr(1) if negative or normalized.begins_with("+") else normalized
	if digits.is_empty():
		return {"ok": false}
	for index in digits.length():
		var codepoint := digits.unicode_at(index)
		if codepoint < 0x30 or codepoint > 0x39:
			return {"ok": false}
	while digits.length() > 1 and digits.begins_with("0"):
		digits = digits.substr(1)
	if (
		digits.length() > MAX_SAFE_SEED_TEXT.length()
		or (digits.length() == MAX_SAFE_SEED_TEXT.length() and digits > MAX_SAFE_SEED_TEXT)
	):
		return {"ok": false}
	var value := digits.to_int()
	return {"ok": true, "value": -value if negative else value}


func _on_cancel_pressed() -> void:
	if _start_transition_active:
		return
	cancel_requested.emit()


func _on_contract_selected(_index: int) -> void:
	if _start_transition_active:
		return
	_apply_selected_contract()
	_set_status("")


func _active_build() -> Dictionary:
	var nested: Variant = _build_snapshot.get("active_build", _build_snapshot)
	return nested as Dictionary if nested is Dictionary else {}


## The contract page only renders the authoritative resolved Build. It never
## consumes available_builds or legacy preset presentations, and it never
## recomputes a Build. Growth classification is gated behind verification.
func _build_summary(build: Dictionary) -> String:
	var resolved := _resolved_build()
	var skills: Array[String] = []
	for value: Variant in _component_values(build, resolved, "skills", "skill_id"):
		var skill := _skill_registry.get_skill(String(value))
		if not skill.is_empty():
			skills.append(String(skill.get("name", "技能")))
	var lines: Array[String] = ["已装技能：%s" % ("、".join(skills) if not skills.is_empty() else "无"), "基础动作：闪避", ""]
	if resolved.is_empty():
		lines.append("当前构筑数据不可用")
	else:
		var value: Variant = resolved.get("final_parameters", {})
		var parameters: Dictionary = value if value is Dictionary else {}
		for key: String in BUILD_PARAMETER_ORDER:
			if parameters.has(key):
				lines.append(_player_readable.format_parameter(key, parameters[key]))
	return "\n".join(lines)


func _open_build_details() -> void:
	if _start_transition_active:
		return
	if _details_dialog == null:
		_details_dialog = AcceptDialog.new()
		_details_dialog.name = "BuildDetailsDialog"
		_details_dialog.title = "技能与构筑详情"
		_details_dialog.ok_button_text = "返回契约"
		_details_dialog.theme = theme
		_details_dialog.confirmed.connect(_restore_details_focus)
		_details_dialog.canceled.connect(_restore_details_focus)
		add_child(_details_dialog)
		var scroll := ScrollContainer.new()
		scroll.name = "DetailsScroll"
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		scroll.offset_left = 20
		scroll.offset_top = 16
		scroll.offset_right = -20
		scroll.offset_bottom = -64
		_details_dialog.add_child(scroll)
		_details_label = _field_label("")
		_details_label.name = "FullBuildRules"
		_details_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(_details_label)
	var resolved := _resolved_build()
	var build := _active_build()
	_details_label.text = "%s\n\n%s\n\n增长结论：%s\n\n%s" % [_components_summary(build, resolved), _parameter_line(resolved), _growth_conclusion(resolved), _core_skill_summary(build, resolved)]
	var available := get_viewport_rect().size
	_details_dialog.popup_centered(Vector2i(minf(900, available.x - 80), minf(580, available.y - 80)))
	_details_dialog.get_ok_button().grab_focus()


func _restore_details_focus() -> void:
	_details_button.grab_focus()


func _resolved_build() -> Dictionary:
	var value: Variant = _build_snapshot.get("resolved_build", null)
	if not value is Dictionary:
		return {}
	var resolved: Dictionary = value
	if not bool(resolved.get("ok", true)):
		return {}
	return resolved


func _parameter_line(resolved: Dictionary) -> String:
	var parameters_value: Variant = resolved.get("final_parameters", {})
	var parameters: Dictionary = parameters_value if parameters_value is Dictionary else {}
	return _player_readable.format_parameters(parameters)


func _growth_conclusion(resolved: Dictionary) -> String:
	var training_value: Variant = _build_snapshot.get("training", {})
	var training: Dictionary = training_value if training_value is Dictionary else {}
	var fingerprint := str(resolved.get("build_fingerprint", "")).strip_edges()
	var report := _matched_training_report(training, fingerprint)
	if report.is_empty():
		return "未验证"
	var state := str(report.get("state", "")).strip_edges()
	return String({"convergent": "收敛", "critical": "临界", "exponential": "指数"}.get(state.to_lower(), "未验证"))


func _core_skill_summary(build: Dictionary, resolved: Dictionary) -> String:
	var skill_ids := _component_values(build, resolved, "skills", "skill_id")
	if not "basic_dodge" in skill_ids:
		skill_ids.append("basic_dodge")
	var details: Array[String] = []
	for raw_id in skill_ids:
		var skill := _skill_registry.get_skill(String(raw_id))
		if not skill.is_empty():
			details.append(_player_readable.format_skill(skill))
	return "核心技能说明：\n%s" % "\n\n".join(details) if not details.is_empty() else "核心技能说明暂不可用"


func _matched_training_report(training: Dictionary, fingerprint: String) -> Dictionary:
	if fingerprint.is_empty():
		return {}
	var reports_by_fingerprint_value: Variant = training.get("reports_by_fingerprint", {})
	if not reports_by_fingerprint_value is Dictionary:
		return {}
	var report_value: Variant = (reports_by_fingerprint_value as Dictionary).get(fingerprint, {})
	if not report_value is Dictionary:
		return {}
	var report: Dictionary = report_value
	if String(report.get("build_fingerprint", "")).strip_edges() != fingerprint:
		return {}
	return report.duplicate(true)


func _components_summary(build: Dictionary, resolved: Dictionary) -> String:
	var skills := _component_values(build, resolved, "skills", "skill_id")
	var runes := _component_values(build, resolved, "runes", "rune_ids")
	var laws := _component_values(build, resolved, "laws", "law_ids")
	if laws.is_empty():
		laws = _component_values(build, resolved, "rules", "law_ids")
	if laws.is_empty():
		laws = _component_values(build, resolved, "law", "law_ids")
	var skill_names: Array[String] = []
	for raw_skill in skills:
		var skill := _skill_registry.get_skill(String(raw_skill))
		if not skill.is_empty():
			skill_names.append(String(skill.get("name", "技能")))
	var rune_lines: Array[String] = []
	for raw_rune in runes:
		rune_lines.append(_player_readable.format_rune(String(raw_rune)).trim_prefix("符文："))
	var law_lines: Array[String] = []
	for raw_law in laws:
		law_lines.append(_player_readable.format_law(String(raw_law)).trim_prefix("法则："))
	return "技能：%s\n符文：%s\n法则：%s" % [
		"、".join(skill_names) if not skill_names.is_empty() else "无",
		"；".join(rune_lines) if not rune_lines.is_empty() else "无",
		"；".join(law_lines) if not law_lines.is_empty() else "无",
	]


func _component_values(build: Dictionary, resolved: Dictionary, list_key: String, singular_key: String) -> Array:
	var list_value: Variant = build.get(list_key, null)
	if list_value is Array and not (list_value as Array).is_empty():
		return (list_value as Array).duplicate()
	var resolved_value: Variant = resolved.get(singular_key, null)
	if resolved_value is Array and not (resolved_value as Array).is_empty():
		return (resolved_value as Array).duplicate()
	if resolved_value is String and not (resolved_value as String).strip_edges().is_empty():
		return [resolved_value]
	return []

