class_name CharacterScreen
extends Control
## Read-only growth presentation.  The profile authority owns every allocation;
## this tome only requests changes and waits for the next authoritative present().

signal closed
signal talent_requested(talent_id: String)
signal talent_refund_requested(talent_id: String)
signal reset_requested
signal stance_requested(stance: String)

const ShellThemeScript = preload("res://src/presentation/shell_theme.gd")
const TalentBoardScript = preload("res://src/presentation/ranger_talent_board.gd")
const ProgressionIconsScript = preload("res://src/presentation/progression_icons.gd")

const PAGE_MARGIN := 18
const GAP := 12
const DETAIL_WIDTH := 430.0
const TITLE_FONT_SIZE := 30
const BODY_FONT_SIZE := 22
const TIER_COUNT := 3
const NODES_PER_TIER := 5

var _built := false
var _snapshot: Dictionary = {}
var _status_message := ""
var _selected_talent_id := ""
var _action_pending := false

var _level_label: Label
var _experience_label: Label
var _experience_progress: ProgressBar
var _points_label: Label
var _tree_title: Label
var _tree_state_label: Label
var _detail_title: Label
var _detail_description: Label
var _detail_state: Label
var _allocate_button: Button
var _refund_button: Button
var _reset_button: Button
var _status_label: Label
var _stance_gate_label: Label
var _stance_row: HBoxContainer
var _talent_board: Control
var _talent_icons = ProgressionIconsScript.new()


func _ready() -> void:
	_build_ui()
	_apply_presentation()


## The caller supplies an authoritative profile snapshot after every accepted or
## rejected request.  A local press never changes allocation, points, or stance.
func present(snapshot: Dictionary, status_message: String = "") -> void:
	_snapshot = snapshot.duplicate(true)
	_status_message = status_message
	_action_pending = false
	if _built:
		_apply_presentation()


func _build_ui() -> void:
	if _built:
		return
	_built = true
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = ShellThemeScript.create()
	ShellThemeScript.add_backdrop(self, "sanctuary")
	var margins := MarginContainer.new()
	margins.name = "CharacterMargins"
	margins.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "top", "right", "bottom"]:
		margins.add_theme_constant_override("margin_%s" % side, PAGE_MARGIN)
	add_child(margins)
	var page := VBoxContainer.new()
	page.name = "CharacterPage"
	page.add_theme_constant_override("separation", 2)
	margins.add_child(page)
	_build_heading(page)
	_build_overview(page)
	_build_workspace(page)


func _build_heading(page: VBoxContainer) -> void:
	var heading_row := HBoxContainer.new()
	heading_row.name = "CharacterHeading"
	heading_row.add_theme_constant_override("separation", 10)
	page.add_child(heading_row)
	var title_column := VBoxContainer.new()
	title_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_column.add_theme_constant_override("separation", 0)
	heading_row.add_child(title_column)
	var title := _label("游侠成长册", TITLE_FONT_SIZE, ShellThemeScript.BONE)
	title.name = "CharacterTitle"
	title_column.add_child(title)
	var subtitle := _label("猎场学 · 冷石板上的三条追猎路线", BODY_FONT_SIZE, ShellThemeScript.NEUTRAL)
	subtitle.name = "CharacterSubtitle"
	title_column.add_child(subtitle)
	var class_tabs := HBoxContainer.new()
	class_tabs.name = "ClassTabs"
	class_tabs.add_theme_constant_override("separation", 6)
	heading_row.add_child(class_tabs)
	var ranger_tab := _button("游侠", "ClassTab_ranger")
	ranger_tab.disabled = true
	ranger_tab.tooltip_text = "本轮开放：游侠天赋。"
	class_tabs.add_child(ranger_tab)
	for class_copy: String in ["炼金 · 后续", "法师 · 后续"]:
		var future_tab := _button(class_copy, "FutureClassTab_%s" % class_tabs.get_child_count())
		future_tab.disabled = true
		future_tab.tooltip_text = "该职业天赋尚未实现，不能投入点数。"
		class_tabs.add_child(future_tab)
	var close_button := _button("返回 Esc", "CloseCharacterButton")
	## Same rationale as the dialogue close: the advertised Esc must fire even
	## while a control inside this screen owns focus.
	var close_shortcut := Shortcut.new()
	var close_key := InputEventKey.new()
	close_key.keycode = KEY_ESCAPE
	close_key.physical_keycode = KEY_ESCAPE
	close_shortcut.events = [close_key]
	close_button.shortcut = close_shortcut
	close_button.custom_minimum_size = Vector2(138, 48)
	close_button.pressed.connect(func() -> void: closed.emit())
	heading_row.add_child(close_button)


func _build_overview(page: VBoxContainer) -> void:
	var overview := HBoxContainer.new()
	overview.name = "GrowthOverview"
	overview.add_theme_constant_override("separation", 10)
	page.add_child(overview)
	var level_card := _metric_card("角色等级", "LevelLabel")
	_level_label = level_card["value"] as Label
	overview.add_child(level_card["panel"] as PanelContainer)
	var experience_card := _metric_card("经验", "ExperienceLabel")
	_experience_label = experience_card["value"] as Label
	(experience_card["panel"] as PanelContainer).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	overview.add_child(experience_card["panel"] as PanelContainer)
	var points_card := _metric_card("未用天赋点", "PointsLabel")
	_points_label = points_card["value"] as Label
	overview.add_child(points_card["panel"] as PanelContainer)
	_experience_progress = ProgressBar.new()
	_experience_progress.name = "ExperienceProgress"
	_experience_progress.show_percentage = false
	_experience_progress.custom_minimum_size = Vector2(280, 9)
	_experience_progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var track := StyleBoxFlat.new()
	track.bg_color = Color("16202a")
	track.border_color = Color("524c3e")
	track.set_border_width_all(1)
	track.set_corner_radius_all(0)
	_experience_progress.add_theme_stylebox_override("background", track)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("8b6e42")
	fill.border_color = Color("c4a76a")
	fill.set_border_width_all(1)
	fill.set_corner_radius_all(0)
	_experience_progress.add_theme_stylebox_override("fill", fill)
	(experience_card["content"] as VBoxContainer).add_child(_experience_progress)
	_status_label = _label("", BODY_FONT_SIZE, ShellThemeScript.NEUTRAL)
	_status_label.name = "CharacterStatus"
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.visible = false
	page.add_child(_status_label)


func _build_workspace(page: VBoxContainer) -> void:
	var workspace := HBoxContainer.new()
	workspace.name = "CharacterWorkspace"
	workspace.add_theme_constant_override("separation", GAP)
	workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(workspace)
	var tree_panel := PanelContainer.new()
	tree_panel.name = "TalentTreePanel"
	tree_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tree_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree_panel.add_theme_stylebox_override("panel", ShellThemeScript.panel_style("panel"))
	workspace.add_child(tree_panel)
	var tree_margin := MarginContainer.new()
	tree_margin.name = "TreeContent"
	tree_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side: String in ["left", "top", "right", "bottom"]:
		tree_margin.add_theme_constant_override("margin_%s" % side, 8)
	tree_panel.add_child(tree_margin)
	var tree_column := VBoxContainer.new()
	tree_column.add_theme_constant_override("separation", 4)
	tree_margin.add_child(tree_column)
	var board_header := HBoxContainer.new()
	board_header.add_theme_constant_override("separation", 10)
	tree_column.add_child(board_header)
	_tree_title = _label("猎场学 · 三层天赋", BODY_FONT_SIZE, ShellThemeScript.BONE)
	_tree_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board_header.add_child(_tree_title)
	_tree_state_label = _label("", BODY_FONT_SIZE, ShellThemeScript.WARNING)
	_tree_state_label.name = "TreeStateLabel"
	_tree_state_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	board_header.add_child(_tree_state_label)
	_talent_board = TalentBoardScript.new()
	_talent_board.name = "RangerTalentBoard"
	_talent_board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_talent_board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_talent_board.talent_selected.connect(_on_talent_selected)
	_talent_icons.load_icons()
	_talent_board.set_progression_icons(_talent_icons)
	tree_column.add_child(_talent_board)
	var detail_panel := PanelContainer.new()
	detail_panel.name = "TalentDetailPanel"
	detail_panel.custom_minimum_size = Vector2(DETAIL_WIDTH, 0)
	detail_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_panel.add_theme_stylebox_override("panel", ShellThemeScript.panel_style("paper"))
	workspace.add_child(detail_panel)
	var detail := VBoxContainer.new()
	detail.name = "DetailContent"
	detail.add_theme_constant_override("separation", 8)
	detail_panel.add_child(detail)
	_detail_title = _label("选择一项天赋", BODY_FONT_SIZE, Color("d7a46b"))
	_detail_title.name = "SelectedTalentName"
	_detail_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(_detail_title)
	_detail_description = _label("从左侧追猎路线选择节点，查看完整说明。", BODY_FONT_SIZE, ShellThemeScript.BONE)
	_detail_description.name = "SelectedTalentDescription"
	_detail_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_description.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail.add_child(_detail_description)
	_detail_state = _label("", BODY_FONT_SIZE, Color("cfc4a8"))
	_detail_state.name = "SelectedTalentState"
	_detail_state.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(_detail_state)
	_allocate_button = _button("投入1点", "AllocateTalentButton")
	_allocate_button.pressed.connect(_on_allocate_pressed)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	detail.add_child(actions)
	_allocate_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(_allocate_button)
	_refund_button = _button("退还1点", "RefundTalentButton")
	_refund_button.pressed.connect(_on_refund_pressed)
	_refund_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(_refund_button)
	_reset_button = _button("免费重置", "ResetTalentsButton")
	_reset_button.pressed.connect(_on_reset_pressed)
	_reset_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(_reset_button)
	_stance_gate_label = _label("姿态：分配相关关键天赋后开放。", BODY_FONT_SIZE, Color("cfc4a8"))
	_stance_gate_label.name = "StanceGateLabel"
	_stance_gate_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(_stance_gate_label)
	_stance_row = HBoxContainer.new()
	_stance_row.name = "StanceRow"
	_stance_row.add_theme_constant_override("separation", 6)
	for stance: String in ["near", "mid", "far"]:
		var stance_button := _button(_stance_name(stance), "Stance_%s" % stance)
		stance_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stance_button.pressed.connect(_on_stance_pressed.bind(stance))
		_stance_row.add_child(stance_button)
	detail.add_child(_stance_row)


func _metric_card(title_text: String, value_name: String) -> Dictionary:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(198, 74)
	panel.add_theme_stylebox_override("panel", ShellThemeScript.panel_style("well"))
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 2)
	panel.add_child(content)
	content.add_child(_label(title_text, BODY_FONT_SIZE, ShellThemeScript.NEUTRAL))
	var value := _label("—", BODY_FONT_SIZE, ShellThemeScript.BONE)
	value.name = value_name
	content.add_child(value)
	return {"panel": panel, "content": content, "value": value}


func _label(text_value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _button(text_value: String, node_name: String) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text_value
	button.add_theme_font_size_override("font_size", BODY_FONT_SIZE)
	button.focus_mode = Control.FOCUS_ALL
	return button


func _apply_presentation() -> void:
	var level := int(_snapshot.get("level", 0))
	var max_level := int(_snapshot.get("max_level", 50))
	var experience := int(_snapshot.get("experience", 0))
	var level_experience := int(_snapshot.get("level_experience", 0))
	var next_level_experience := int(_snapshot.get("next_level_experience", 1))
	_level_label.text = "Lv.%d / %d" % [level, max_level]
	_experience_label.text = "本级 %d / %d · 累计 %d" % [level_experience, next_level_experience, experience]
	_points_label.text = "%d 点" % int(_snapshot.get("points_available", 0))
	if _experience_progress != null:
		_experience_progress.max_value = max(1, next_level_experience)
		_experience_progress.value = clamp(level_experience, 0, next_level_experience)
		_experience_progress.tooltip_text = "本级经验：%d / %d；累计经验：%d" % [level_experience, next_level_experience, experience]
	_render_tree()
	_render_detail()
	_render_stance()
	var status := _status_message
	if status.is_empty() and _action_pending:
		status = "请求已发送，等待角色档案更新。"
	if status.is_empty() and bool(_snapshot.get("locked", false)):
		status = "契约期间天赋锁定，可查看当前加点。"
	_status_label.text = status
	_status_label.visible = false
	if not status.is_empty():
		_detail_state.text = status


func _render_tree() -> void:
	var tree := _ranger_tree()
	var available := bool(tree.get("available", false))
	_tree_title.text = "%s · 三层追猎路线" % String(tree.get("name", "猎场学"))
	var icons_pending := not _talent_icons.is_ready()
	_tree_state_label.visible = not available or icons_pending
	var reason := "" if available and not icons_pending else "图标待补充" if available else "当前不可投入：%s" % ("契约期间已锁定" if bool(_snapshot.get("locked", false)) else "等待档案解锁")
	_tree_state_label.text = reason
	var nodes_by_tier := {1: [], 2: [], 3: []}
	for node_value in _nodes_of(tree):
		var node: Dictionary = node_value
		var tier := clampi(int(node.get("tier", 1)), 1, TIER_COUNT)
		(nodes_by_tier[tier] as Array).append(node)
	if _selected_talent_id.is_empty() or _find_node(_selected_talent_id).is_empty():
		_selected_talent_id = _first_selectable_or_allocated_id()
	# A valid selection survives an authoritative update, but its allocation,
	# tier gates and request-pending state still need to reach the board.
	_talent_board.present(nodes_by_tier, _selected_talent_id, available and not _action_pending)


func set_talent_icons_for_test(reader: RefCounted) -> void:
	_talent_icons = reader
	_talent_board.set_progression_icons(reader)




func _render_detail() -> void:
	var node := _find_node(_selected_talent_id)
	var locked := bool(_snapshot.get("locked", false))
	if node.is_empty():
		_detail_title.text = "选择一项天赋"
		_detail_description.text = "从左侧追猎路线选择节点，查看完整说明。"
		_detail_state.text = ""
		_allocate_button.disabled = true
		_refund_button.disabled = true
		_reset_button.disabled = locked or _action_pending
		return
	_detail_title.text = String(node.get("name", _selected_talent_id))
	var tier := int(node.get("tier", 1))
	_detail_description.text = String(node.get("description", "尚无说明。"))
	var allocated := bool(node.get("allocated", false))
	var can_allocate := bool(node.get("can_allocate", false))
	var lock_reason := String(node.get("lock_reason", ""))
	var tier_copy := "关键 · 第 %d 层" % tier if bool(node.get("keystone", false)) else "第 %d 层" % tier
	_detail_state.text = "%s · %s" % [tier_copy, "已投入" if allocated else ("可投入" if can_allocate and not locked else (lock_reason if not lock_reason.is_empty() else "当前不可投入"))]
	_allocate_button.disabled = locked or _action_pending or allocated or not can_allocate
	_refund_button.disabled = locked or _action_pending or not allocated
	_reset_button.disabled = locked or _action_pending


func _render_stance() -> void:
	var available := _stance_controls_available()
	_stance_gate_label.visible = not available
	_stance_row.visible = available
	if not available:
		return
	var selected_stance := String(_snapshot.get("stance", "near"))
	for child in _stance_row.get_children():
		var button := child as Button
		if button == null:
			continue
		var stance := button.name.trim_prefix("Stance_")
		button.text = "%s%s" % [_stance_name(stance), " · 当前" if stance == selected_stance else ""]
		button.disabled = _action_pending or bool(_snapshot.get("locked", false)) or stance == selected_stance


func _on_talent_selected(talent_id: String) -> void:
	if _find_node(talent_id).is_empty():
		return
	_selected_talent_id = talent_id
	_render_tree()
	_render_detail()


func _on_allocate_pressed() -> void:
	var node := _find_node(_selected_talent_id)
	if node.is_empty() or _allocate_button.disabled:
		return
	_action_pending = true
	talent_requested.emit(_selected_talent_id)
	_apply_presentation()


func _on_refund_pressed() -> void:
	var node := _find_node(_selected_talent_id)
	if node.is_empty() or _refund_button.disabled:
		return
	_action_pending = true
	talent_refund_requested.emit(_selected_talent_id)
	_apply_presentation()


func _on_reset_pressed() -> void:
	if _reset_button.disabled:
		return
	_action_pending = true
	reset_requested.emit()
	_apply_presentation()


func _on_stance_pressed(stance: String) -> void:
	if _action_pending or not _stance_controls_available() or bool(_snapshot.get("locked", false)) or stance == String(_snapshot.get("stance", "")):
		return
	_action_pending = true
	stance_requested.emit(stance)
	_apply_presentation()


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	var key := key_event.physical_keycode if key_event.physical_keycode != KEY_NONE else key_event.keycode
	if key == KEY_ESCAPE:
		closed.emit()
		get_viewport().set_input_as_handled()


func _ranger_tree() -> Dictionary:
	var trees_value: Variant = _snapshot.get("trees", [])
	if trees_value is Array:
		for value in trees_value:
			if value is Dictionary and String((value as Dictionary).get("id", "")) == "ranger":
				return (value as Dictionary).duplicate(true)
	return {"id": "ranger", "name": "猎场学", "available": false, "nodes": []}


func _nodes_of(tree: Dictionary) -> Array:
	var nodes_value: Variant = tree.get("nodes", [])
	var nodes: Array = []
	if nodes_value is Array:
		for value in nodes_value:
			if value is Dictionary:
				nodes.append((value as Dictionary).duplicate(true))
	return nodes


func _find_node(talent_id: String) -> Dictionary:
	for node in _nodes_of(_ranger_tree()):
		if String(node.get("id", "")) == talent_id:
			return node
	return {}


func _first_selectable_or_allocated_id() -> String:
	for node in _nodes_of(_ranger_tree()):
		if bool(node.get("allocated", false)) or bool(node.get("can_allocate", false)):
			return String(node.get("id", ""))
	return ""


func _stance_controls_available() -> bool:
	var value: Variant = _snapshot.get("stance_available", false)
	if value is bool:
		return value
	if value is Dictionary:
		return not (value as Dictionary).is_empty()
	if value is Array:
		return not (value as Array).is_empty()
	return false


func _stance_name(stance: String) -> String:
	match stance:
		"near": return "近"
		"mid": return "中"
		"far": return "远"
		_: return stance
