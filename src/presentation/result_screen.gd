class_name ResultScreen
extends Control
## Contract settlement: what actually happened in the run that just ended.
##
## The header and actions stay pinned. The left lane scrolls complete reward
## and item text inside a bounded viewport, with pagination outside that viewport.
## Three-column combat metrics retain their existing layout and typography.
##
## Content: values come from the settlement payload; the only bar uses actual
## rooms_completed / room_count. No score or event tree is inferred. Missing data is
## left out instead of being drawn as a zero -- a reported zero is a reading and
## stays -- and a field outside the known table is listed raw in the collapsible
## 计算详情 block, together with the untruncated drop ids.
##
## Drop cards: the face of a card is what the run produced -- the published Chinese
## name of the base item, its slot and its affixes -- beside one full-size subject
## icon. The instance id, the base id, the raw affix families and the drop source
## never enter the player-facing face. They stay reachable through
## get_equipment_card_texts for the F10 evidence harness and get_detail_text.
##
## Names: read-only from the content table (EarlyItemRegistry over
## content/early_items.json). An explicit name field on the drop wins, then the
## published table, then the raw id -- an id neither source covers keeps its own
## text and is never guessed at.
##
## Art: drop icons are canonical cells of the published 24-icon batch, read through
## FacilityArt. An id the package does not publish resolves to null and the card
## keeps its text alone; no stand-in is drawn in its place.

signal base_requested
signal ending_requested
signal contract_requested
signal loadout_review_requested(instance_id: String, slot: String)

const ShellThemeScript = preload("res://src/presentation/shell_theme.gd")
const FacilityArtScript = preload("res://src/presentation/facility_art.gd")
const EarlyItemRegistryScript = preload("res://src/content/early_item_registry.gd")
const PlayerReadableBuildScript = preload("res://src/presentation/player_readable_build.gd")
const EquipmentPresentationModelScript = preload("res://src/presentation/models/equipment_presentation_model.gd")
const PlayerFacingStatusScript = preload("res://src/presentation/player_facing_status.gd")
const ReportEvidenceMarkScript = preload("res://src/presentation/report_evidence_mark.gd")
const SettlementRouteViewScript = preload("res://src/presentation/settlement_route_view.gd")
const PixelGridIconScript = preload("res://src/presentation/pixel_grid_icon.gd")
const ContractTitles = preload("res://src/presentation/contract_screen.gd").NODE_TITLES

## The shell's one UI resolution. Every rect below is expressed in these pixels.
const DESIGN_SIZE := Vector2(1280.0, 720.0)
const SCREEN_MARGIN := 24
const BLOCK_SEPARATION := 14

const TITLE_TEXT := "契约结算"
const KICKER_TEXT := "CONTRACT REPORT"
const SUBTITLE_TEXT := "先看收获，再比较构筑。"
const REPORT_HEADING := "战斗记录"
const DROP_HEADING := "本次掉落"
const DETAIL_HEADING := "计算详情"
const DETAIL_SHOW_TEXT := "展开计算详情"
const DETAIL_HIDE_TEXT := "收起计算详情"
const BASE_BUTTON_TEXT := "返回基地"
const ENDING_BUTTON_TEXT := "进入结尾"
const CONTRACT_BUTTON_TEXT := "再次出征"
const REVIEW_DROP_TEXT := "比较（尚未装备）"
const EQUIPMENT_DETAIL_TEXT := "详情"
const EQUIPMENT_DETAIL_CLOSE_TEXT := "关闭详情"
const PREVIOUS_PAGE_TEXT := "上一页"
const NEXT_PAGE_TEXT := "下一页"
const NO_PAGE_TEXT := "1 / 1"
const REPORT_DETAIL_TEXT := "战报详情"
const REPORT_HIDE_TEXT := "收起战报"
const NO_REWARD_TEXT := "本次结算没有掉落记录。"
const EMPTY_FACTS_TEXT := "本次结算没有报告字段；结果、用时与房间进度以上方指标为准。"

## Header and value steps of the approved UI band: 28px Chinese title, 18px
## neutral subtitle and small copy, 28px metric values (VISUAL_BASELINE.md).
const TITLE_FONT_SIZE := 28
const SUBTITLE_FONT_SIZE := 18
const METRIC_LABEL_FONT_SIZE := 18
const METRIC_VALUE_FONT_SIZE := 24
const METRIC_COLUMNS := 3
const SECONDARY_FONT_SIZE := 18

const CARD_NODE_NAME := "EquipmentCard"
const CARD_TEXT_NODE_NAME := "EquipmentCardText"
const CARD_NAME_NODE_NAME := "EquipmentCardName"
const BASE_ICON_NODE_NAME := "EquipmentBaseIcon"
const SLOT_BADGE_NODE_NAME := "EquipmentSlotBadge"
## The complete field line of one drop, kept on its card so
## get_equipment_card_texts can read it back whatever the card face shows.
const CARD_AUDIT_META := "audit_text"

## The metric row, in reading order. Each entry is one authoritative field of the
## settlement payload; a metric the payload does not carry is hidden, never shown
## as a zero, while a metric that really is 0 is drawn as the reading it is.
const METRICS: Array = [
	{"key": "outcome", "label": "结果"},
	{"key": "elapsed", "label": "实际用时"},
	{"key": "kills", "label": "击杀"},
	{"key": "casts", "label": "施放"},
	{"key": "rooms", "label": "房间进度"},
]

## The settlement's own run totals and one room's readings, in reading order: the
## metric key to read and the label the detail table prints it under. Both lists are
## built from fields the payload reports, so an entry that was never carried names
## itself unrecorded instead of appearing as a zero.
const TOTAL_FIELDS: Array = [
	{"key": "ticks", "label": "权威 Tick"},
	{"key": "elapsed", "label": "实际用时"},
	{"key": "casts", "label": "施放"},
	{"key": "kills", "label": "击杀"},
]
const ROOM_FIELDS: Array = [
	{"key": "kills", "label": "击杀"},
	{"key": "casts", "label": "施放"},
	{"key": "ticks", "label": "Tick"},
	{"key": "elapsed", "label": "用时"},
]

const OUTCOME_LABELS := {
	"victory": "胜利",
	"final_victory": "最终胜利",
	"defeat": "失败",
	"abandoned": "中止",
	"error": "错误",
}

const SLOT_LABELS := {
	"main_hand": "主手",
	"off_hand": "副手",
	"gloves": "手套",
	"ring_1": "戒指",
	"ring_2": "戒指",
	"necklace": "项链",
	"head": "头部",
	"chest": "胸甲",
	"pants": "裤甲",
	"leg_armor": "腿甲",
	"bracers": "护腕",
	"belt": "腰带",
}

## Reward fields this screen formats as player copy. Anything else in `rewards`
## is listed verbatim in the detail block instead of being dropped.
const REWARD_FIELD_LABELS := {
	"contract_wins_delta": "契约胜场",
	"repeatable_attempt_number": "重复支线次数",
}
const LAW_TALLY_LABELS := {
	"inscribe": "添铸律筹",
	"rewrite": "改写律筹",
	"refine": "精炼律筹",
}
## The timed-bonus pair is one line, and only when the run really had a bonus in
## play: the payload sets exactly one flag for a timed objective and leaves both
## false when there was nothing to lose, so a settled room never claims a loss it
## did not take.
const TIMED_BONUS_LABEL := "限时加成"

const FIRST_REWARD_LABELS := {
	"starter_loadout": "固定起步装备已装配",
	"hunter_mark_skill": "新技能：猎人印记（技能槽 2）",
	"dash_skill": "新技能：突袭（技能槽 3）",
	"equipment_compare_unlock": "装备比较已开放",
	"breeding_split_item": "孳生分裂装备已入库存",
	"law_forge_unlock": "律筹锻造台已解锁",
	"pack_hunt_mark_item": "群猎印记装备已入库存",
	"early_campaign_complete": "前期旅程完成：已掌握手动战斗与代理出征",
}

## The fixed four white cores, in the order the proxy bay grants them.
const PROXY_CORE_LABELS := {
	"near_enemy_horizon": "近敌视界",
	"nearest_enemy": "感知核心",
	"perception": "感知核心",
	"direct_gait": "直趋步足",
	"movement": "行动核心",
	"action": "行动核心",
	"single_key_execution": "单键执行",
	"execution": "执行核心",
	"short_trace_memory": "短痕记忆",
	"memory": "记忆核心",
}
const PROXY_CORE_FALLBACK: Array[String] = ["感知核心", "行动核心", "执行核心", "记忆核心"]
const FIXED_CORE_IDS: Array[String] = ["near_enemy_horizon", "direct_gait", "single_key_execution", "short_trace_memory"]

var _built := false
var _result: Dictionary = {}
var _contract: Dictionary = {}
## Live ownership/equipment is separate from the immutable settlement receipt.
var _current_profile: Dictionary = {}
var _loot_scroll: ScrollContainer
var _art = FacilityArtScript.new()
var _art_error := ""
## The read-only content table that names base items and affix families, or null
## when this package cannot read it -- every id then stays raw on the card.
var _item_registry: Variant = null
var _player_readable = PlayerReadableBuildScript.new()
var _equipment_model: EquipmentPresentationModelScript = null
var _detail_visible := false
var _equipment_drop_entries: Array = []
var _equipment_page := 0
var _equipment_page_size := 2
var _growth_label: Label
var _header_kicker: Label
var _title_label: Label
var _subtitle_label: Label
var _run_facts_label: Label
var _metric_values: Dictionary = {}
var _metric_tiles: Dictionary = {}
var _outcome_label: Label
var _details_label: Label
var _detail_instances_label: Label
var _detail_panel: PanelContainer
var _detail_button: Button
var _diagnosis_label: Label
var _report_label: Label
var _reward_label: Label
var _proxy_component_box: VBoxContainer
var _equipment_box: VBoxContainer
var _equipment_pagination: HBoxContainer
var _previous_page_button: Button
var _next_page_button: Button
var _page_label: Label
var _report_detail_button: Button
var _equipment_detail_overlay: Control
var _equipment_detail_title: Label
var _equipment_detail_body: Label
var _core_rewards: GridContainer
var _metrics_grid: GridContainer
var _content: Control
var _ending_button: Button
var _contract_button: Button
var _route_view: Control
var _route_context: Label
var _room_progress: ProgressBar
var _room_progress_label: Label
var _evidence_grid: GridContainer
var _evidence_bodies := {}
var _evidence_marks := {}


func _ready() -> void:
	_build_ui()
	_apply_presentation()


func present(result: Dictionary, contract: Dictionary = {}, current_profile: Dictionary = {}) -> void:
	_result = result.duplicate(true)
	_contract = contract.duplicate(true)
	_current_profile = current_profile.duplicate(true)
	_equipment_model = EquipmentPresentationModelScript.new(_player_readable, _registry_rows("base_items"), _registry_rows("affix_families"), {}, "未知装备")
	if _built:
		_apply_presentation()


func _build_ui() -> void:
	if _built:
		return
	_built = true
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = ShellThemeScript.create()
	_load_art()
	_load_item_names()

	ShellThemeScript.add_backdrop(self, "result_screen")

	var root := Control.new()
	root.name = "ResultRoot"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = SCREEN_MARGIN
	root.offset_top = SCREEN_MARGIN
	root.offset_right = -SCREEN_MARGIN
	root.offset_bottom = -SCREEN_MARGIN
	add_child(root)

	_build_header(root)
	_build_body(root)
	_build_footer(root)
	_place_section(root.get_node("ResultHeader"), 0.0, 0.0, 0.0, 107.0)
	_place_section(root.get_node("ResultContent"), 0.0, 1.0, 121.0, -32.0)
	_place_section(root.get_node("ResultFooter"), 1.0, 1.0, -44.0, 0.0)
	_layout_footer_against_body()
	resized.connect(_layout_footer_against_body)
	(root.get_node("ResultFooter") as Control).minimum_size_changed.connect(_layout_footer_against_body)
	resized.connect(_sync_metric_columns)
	resized.connect(_sync_equipment_page_size)
	_sync_metric_columns()
	_sync_equipment_page_size()


func _place_section(section: Control, top_anchor: float, bottom_anchor: float, top_offset: float, bottom_offset: float) -> void:
	section.set_anchor(SIDE_LEFT, 0.0)
	section.set_anchor(SIDE_RIGHT, 1.0)
	section.set_anchor(SIDE_TOP, top_anchor)
	section.set_anchor(SIDE_BOTTOM, bottom_anchor)
	section.offset_left = 0.0
	section.offset_right = 0.0
	section.offset_top = top_offset
	section.offset_bottom = bottom_offset


func _layout_footer_against_body() -> void:
	var body := get_node_or_null("ResultRoot/ResultContent") as Control
	var footer := get_node_or_null("ResultRoot/ResultFooter") as Control
	if body == null or footer == null:
		return
	footer.offset_top = -ceil(maxf(footer.get_minimum_size().y, footer.get_combined_minimum_size().y))
	body.offset_bottom = footer.offset_top - BLOCK_SEPARATION


func _build_header(root: Control) -> void:
	var header := VBoxContainer.new()
	header.name = "ResultHeader"
	header.add_theme_constant_override("separation", 6)
	root.add_child(header)

	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 16)
	header.add_child(title_row)
	_title_label = Label.new()
	_title_label.name = "ResultTitle"
	_title_label.text = TITLE_TEXT
	_title_label.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	_title_label.add_theme_color_override("font_color", ShellThemeScript.BONE)
	title_row.add_child(_title_label)
	_growth_label = Label.new()
	_growth_label.name = "CharacterGrowthSummary"
	_growth_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_growth_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_growth_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_growth_label.add_theme_font_size_override("font_size", 22)
	_growth_label.add_theme_color_override("font_color", ShellThemeScript.BONE)
	_growth_label.visible = false
	title_row.add_child(_growth_label)
	var kicker := Label.new()
	_header_kicker = kicker
	kicker.name = "ResultKicker"
	kicker.text = KICKER_TEXT
	kicker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	kicker.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	kicker.add_theme_font_size_override("font_size", SUBTITLE_FONT_SIZE)
	kicker.add_theme_color_override("font_color", ShellThemeScript.NEUTRAL)
	title_row.add_child(kicker)

	_subtitle_label = Label.new()
	_subtitle_label.name = "ResultSubtitle"
	_subtitle_label.text = SUBTITLE_TEXT
	_subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle_label.add_theme_font_size_override("font_size", SUBTITLE_FONT_SIZE)
	_subtitle_label.add_theme_color_override("font_color", ShellThemeScript.NEUTRAL)
	header.add_child(_subtitle_label)
	header.add_child(_rule())


func _build_body(root: Control) -> void:
	## The body is fixed to the shell. Equipment text scrolls locally while its
	## pager stays pinned; the report lane keeps compact decision cards, and
	## diagnostics stay behind the F10 provider.
	_content = PanelContainer.new()
	_content.name = "ResultContent"
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.clip_contents = true
	root.add_child(_content)

	var columns := HBoxContainer.new()
	columns.name = "ResultColumns"
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", BLOCK_SEPARATION)
	_content.add_child(columns)
	_build_drop_panel(columns)
	_build_report_panel(columns)

	_equipment_detail_overlay = Control.new()
	_equipment_detail_overlay.name = "EquipmentDetailOverlay"
	_equipment_detail_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_equipment_detail_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_equipment_detail_overlay.visible = false
	add_child(_equipment_detail_overlay)
	var detail_dim := ColorRect.new()
	detail_dim.color = Color(ShellThemeScript.INK, 0.86)
	detail_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	detail_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_equipment_detail_overlay.add_child(detail_dim)
	var detail_panel := PanelContainer.new()
	detail_panel.name = "EquipmentDetailPanel"
	detail_panel.set_anchors_preset(Control.PRESET_CENTER)
	detail_panel.set_offsets_preset(Control.PRESET_CENTER)
	detail_panel.size = Vector2.ZERO
	detail_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	detail_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	detail_panel.offset_left = -450.0
	detail_panel.offset_right = 450.0
	detail_panel.offset_top = -300.0
	detail_panel.offset_bottom = 300.0
	detail_panel.add_theme_stylebox_override("panel", _frame(ShellThemeScript.INK, ShellThemeScript.AMBER, 2))
	_equipment_detail_overlay.add_child(detail_panel)
	var detail_column := VBoxContainer.new()
	detail_column.add_theme_constant_override("separation", 10)
	detail_panel.add_child(detail_column)
	var detail_header := HBoxContainer.new()
	detail_header.add_theme_constant_override("separation", 12)
	detail_column.add_child(detail_header)
	_equipment_detail_title = Label.new()
	_equipment_detail_title.name = "EquipmentDetailTitle"
	_equipment_detail_title.text = EQUIPMENT_DETAIL_TEXT
	_equipment_detail_title.add_theme_font_size_override("font_size", METRIC_VALUE_FONT_SIZE)
	_equipment_detail_title.add_theme_color_override("font_color", ShellThemeScript.BONE)
	_equipment_detail_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_equipment_detail_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_header.add_child(_equipment_detail_title)
	var close_button := Button.new()
	close_button.name = "EquipmentDetailClose"
	close_button.text = EQUIPMENT_DETAIL_CLOSE_TEXT
	close_button.pressed.connect(_on_equipment_detail_closed)
	detail_header.add_child(close_button)
	_equipment_detail_body = Label.new()
	_equipment_detail_body.name = "EquipmentDetailBody"
	_equipment_detail_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_equipment_detail_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_equipment_detail_body.add_theme_font_size_override("font_size", ShellThemeScript.BODY_FONT_SIZE)
	_equipment_detail_body.add_theme_color_override("font_color", ShellThemeScript.BONE)
	var detail_scroll := ScrollContainer.new()
	detail_scroll.name = "EquipmentDetailScroll"
	detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail_column.add_child(detail_scroll)
	_equipment_detail_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.add_child(_equipment_detail_body)
func _build_metrics(parent: Control) -> void:
	var grid := GridContainer.new()
	_metrics_grid = grid
	grid.name = "ResultMetrics"
	grid.columns = METRIC_COLUMNS
	grid.add_theme_constant_override("h_separation", BLOCK_SEPARATION)
	grid.add_theme_constant_override("v_separation", BLOCK_SEPARATION)
	parent.add_child(grid)
	for metric_value in METRICS:
		var metric: Dictionary = metric_value
		var key := String(metric["key"])
		var tile := PanelContainer.new()
		tile.name = "MetricTile_%s" % key
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var metric_style := _frame(ShellThemeScript.DEEP_BLUE, ShellThemeScript.COPPER_DULL, 1)
		metric_style.content_margin_top = 6
		metric_style.content_margin_bottom = 6
		tile.add_theme_stylebox_override("panel", metric_style)
		grid.add_child(tile)
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 4)
		tile.add_child(column)
		var label := Label.new()
		label.text = String(metric["label"])
		label.add_theme_font_size_override("font_size", METRIC_LABEL_FONT_SIZE)
		label.add_theme_color_override("font_color", ShellThemeScript.NEUTRAL)
		column.add_child(label)
		var value := Label.new()
		value.name = "MetricValue_%s" % key
		value.text = "—"
		value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		value.add_theme_font_size_override("font_size", METRIC_VALUE_FONT_SIZE)
		value.add_theme_color_override("font_color", ShellThemeScript.BONE)
		column.add_child(value)
		_metric_tiles[key] = tile
		_metric_values[key] = value
	_outcome_label = _metric_values["outcome"]


func _sync_metric_columns() -> void:
	if _metrics_grid != null:
		# On the approved shell canvas metrics occupy one quiet strip; keep
		# three columns on narrow logical views without shrinking Chinese text.
		_metrics_grid.columns = 3
	if _evidence_grid != null:
		_evidence_grid.columns = 4 if size.x >= 1200.0 else 2


func _set_report_detail_visible(value: bool) -> void:
	if _metrics_grid == null or _evidence_grid == null:
		return
	_metrics_grid.visible = not value
	_evidence_grid.visible = value
	for body in _evidence_bodies.values():
		(body as Label).visible = value
	var scroll := find_child("CurrentRunScroll", true, false) as ScrollContainer
	if scroll != null:
		scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO if value else ScrollContainer.SCROLL_MODE_DISABLED
	_report_detail_button.text = REPORT_HIDE_TEXT if value else REPORT_DETAIL_TEXT


func _on_report_detail_pressed() -> void:
	_set_report_detail_visible(not _evidence_grid.visible)


func _sync_equipment_page_size() -> void:
	var page_size := 1
	if page_size == _equipment_page_size:
		return
	_equipment_page_size = page_size
	_equipment_page = 0
	if _built:
		_render_equipment_cards()


func _build_report_panel(parent: Control) -> void:
	var panel := PanelContainer.new()
	panel.name = "ReportPanel"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.name = "CurrentRunScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ShellThemeScript.hide_passive_scrollbar_chrome(scroll)
	panel.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.clip_contents = true
	column.add_theme_constant_override("separation", 6)
	scroll.add_child(column)
	column.add_child(_heading("本轮经过"))
	_route_context = _report_note("")
	_route_context.name = "RunContext"
	column.add_child(_route_context)
	_route_view = SettlementRouteViewScript.new()
	_route_view.name = "SettlementRoute"
	column.add_child(_route_view)
	var progress_row := HBoxContainer.new()
	progress_row.add_theme_constant_override("separation",12)
	column.add_child(progress_row)
	_room_progress_label = _report_note("")
	_room_progress_label.name = "RoomProgressReading"
	progress_row.add_child(_room_progress_label)
	_room_progress = ProgressBar.new()
	_room_progress.name = "RoomCompletionBar"
	_room_progress.custom_minimum_size = Vector2(64,10)
	_room_progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_room_progress.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_room_progress.show_percentage = false
	_room_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for layer in ["background", "fill"]:
		var style := StyleBoxFlat.new()
		style.bg_color = ShellThemeScript.GROUND if layer == "background" else ShellThemeScript.BONE
		_room_progress.add_theme_stylebox_override(layer,style)
	progress_row.add_child(_room_progress)
	_report_detail_button = Button.new()
	_report_detail_button.name = "ReportDetailButton"
	_report_detail_button.text = REPORT_DETAIL_TEXT
	_report_detail_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	_report_detail_button.pressed.connect(_on_report_detail_pressed)
	progress_row.add_child(_report_detail_button)
	_build_metrics(column)
	# Full original copy remains in the disclosure block; stable accessors keep
	# serving it without making the visible report a wall of raw fields.
	_diagnosis_label = Label.new()
	_diagnosis_label.name = "BossDiagnosis"
	_diagnosis_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_diagnosis_label.add_theme_color_override("font_color", ShellThemeScript.WARNING)
	_diagnosis_label.visible = false
	_report_label = Label.new()
	_report_label.name = "BattleReport"
	_report_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_report_label.visible = false
	_run_facts_label = Label.new()
	_run_facts_label.name = "RunFacts"
	_run_facts_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_run_facts_label.visible = false
	for label in [_diagnosis_label,_report_label,_run_facts_label]:
		column.add_child(label)
	_build_evidence_cards(column)
	_evidence_grid.visible = false


func _build_evidence_cards(parent: Control) -> void:
	_evidence_grid = GridContainer.new()
	_evidence_grid.name = "ReportEvidenceCards"
	_evidence_grid.columns = 4
	_evidence_grid.add_theme_constant_override("h_separation", 12)
	_evidence_grid.add_theme_constant_override("v_separation", 12)
	parent.add_child(_evidence_grid)
	for row in [["observed","本轮表现"],["unverified","构筑进展"],["bottleneck","危险提示"],["next","下一步"]]:
		var panel := PanelContainer.new()
		panel.name = "EvidenceCard_" + row[0]
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var card_style := _frame(ShellThemeScript.DEEP_BLUE,ShellThemeScript.COPPER_DULL,1)
		card_style.content_margin_top = 8
		card_style.content_margin_bottom = 8
		panel.add_theme_stylebox_override("panel",card_style)
		_evidence_grid.add_child(panel)
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 8)
		panel.add_child(column)
		var header := HBoxContainer.new()
		header.add_theme_constant_override("separation",8)
		column.add_child(header)
		var mark := ReportEvidenceMarkScript.new()
		mark.name = "EvidenceMark_" + row[0]
		mark.kind = row[0]
		header.add_child(mark)
		_evidence_marks[row[0]] = mark
		header.add_child(_heading(row[1]))
		var body := _report_note("")
		body.name = "EvidenceBody_" + row[0]
		body.visible = false
		column.add_child(body)
		_evidence_bodies[row[0]] = body


func _report_note(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size",18)
	return label


func _build_drop_panel(parent: Control) -> void:
	var panel := PanelContainer.new()
	panel.name = "DropPanel"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 4)
	panel.add_child(column)
	column.add_child(_heading(DROP_HEADING))
	_loot_scroll = ScrollContainer.new()
	_loot_scroll.name = "ResultLootScroll"
	_loot_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_loot_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_loot_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_loot_scroll.follow_focus = true
	column.add_child(_loot_scroll)
	var loot := VBoxContainer.new()
	loot.name = "LootContent"
	loot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	loot.add_theme_constant_override("separation", 8)
	_loot_scroll.add_child(loot)
	_reward_label = Label.new()
	_reward_label.name = "RewardSummary"
	_reward_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_reward_label.add_theme_color_override("font_color", ShellThemeScript.BONE)
	loot.add_child(_reward_label)
	_core_rewards = GridContainer.new()
	_core_rewards.name = "FirstKillCoreRewards"
	_core_rewards.columns = 2
	_core_rewards.add_theme_constant_override("h_separation", 8)
	_core_rewards.add_theme_constant_override("v_separation", 8)
	loot.add_child(_core_rewards)
	loot.move_child(_core_rewards, 0)
	_proxy_component_box = VBoxContainer.new()
	_proxy_component_box.name = "ProxyComponentDrops"
	_proxy_component_box.add_theme_constant_override("separation", 8)
	loot.add_child(_proxy_component_box)
	_equipment_box = VBoxContainer.new()
	_equipment_box.name = "EquipmentCards"
	_equipment_box.add_theme_constant_override("separation", 8)
	_equipment_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	loot.add_child(_equipment_box)
	_equipment_pagination = HBoxContainer.new()
	_equipment_pagination.name = "EquipmentPagination"
	_equipment_pagination.add_theme_constant_override("separation", 8)
	_equipment_pagination.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(_equipment_pagination)
	_previous_page_button = Button.new()
	_previous_page_button.name = "EquipmentPreviousPage"
	_previous_page_button.text = PREVIOUS_PAGE_TEXT
	_previous_page_button.pressed.connect(_on_previous_equipment_page)
	_equipment_pagination.add_child(_previous_page_button)
	_page_label = Label.new()
	_page_label.name = "EquipmentPageLabel"
	_page_label.add_theme_font_size_override("font_size", SECONDARY_FONT_SIZE)
	_page_label.add_theme_color_override("font_color", ShellThemeScript.NEUTRAL)
	_page_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_page_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_equipment_pagination.add_child(_page_label)
	_next_page_button = Button.new()
	_next_page_button.name = "EquipmentNextPage"
	_next_page_button.text = NEXT_PAGE_TEXT
	_previous_page_button.text = PREVIOUS_PAGE_TEXT
	_next_page_button.pressed.connect(_on_next_equipment_page)
	_equipment_pagination.add_child(_next_page_button)


func _build_detail_panel(parent: Control) -> void:
	## Collapsed by default: the screen shows the actual result, and the raw field
	## table with the untruncated ids is one explicit step away.
	_detail_panel = PanelContainer.new()
	_detail_panel.name = "ResultDetailPanel"
	_detail_panel.visible = false
	parent.add_child(_detail_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	_detail_panel.add_child(column)
	column.add_child(_heading(DETAIL_HEADING))
	_details_label = Label.new()
	_details_label.name = "ResultDetailMeta"
	_details_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_details_label.add_theme_font_size_override("font_size", SUBTITLE_FONT_SIZE)
	column.add_child(_details_label)
	_detail_instances_label = Label.new()
	_detail_instances_label.name = "ResultDetailInstances"
	## Opaque ids carry no break points, so this block may break inside a word; the
	## full id is never shortened to fit.
	_detail_instances_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_detail_instances_label.add_theme_font_size_override("font_size", SUBTITLE_FONT_SIZE)
	_detail_instances_label.add_theme_color_override("font_color", ShellThemeScript.NEUTRAL)
	column.add_child(_detail_instances_label)


func _build_footer(root: Control) -> void:
	var footer := HBoxContainer.new()
	footer.name = "ResultFooter"
	footer.add_theme_constant_override("separation", 12)
	root.add_child(footer)
	_contract_button = Button.new()
	_contract_button.name = "ContractAgainButton"
	_contract_button.text = CONTRACT_BUTTON_TEXT
	_contract_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_contract_button.pressed.connect(_on_contract_pressed)
	footer.add_child(_contract_button)
	var base_button := Button.new()
	base_button.name = "ReturnToBaseButton"
	base_button.text = BASE_BUTTON_TEXT
	base_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	base_button.pressed.connect(_on_base_pressed)
	footer.add_child(base_button)
	_ending_button = Button.new()
	_ending_button.name = "EndingButton"
	_ending_button.text = ENDING_BUTTON_TEXT
	_ending_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ending_button.pressed.connect(_on_ending_pressed)
	footer.add_child(_ending_button)


func _apply_presentation() -> void:
	var outcome := String(_result.get("outcome", "unknown")).to_lower()
	var is_final_victory := outcome == "final_victory"
	var growth: Dictionary = _result.get("character_growth", {}) if _result.get("character_growth") is Dictionary else {}
	_growth_label.visible = int(growth.get("experience_delta",0)) > 0
	_header_kicker.visible = not _growth_label.visible
	if _growth_label.visible:
		var level := "Lv.%d" % int(growth.get("level_after",1))
		if int(growth.get("level_before",1)) < int(growth.get("level_after",1)):
			level = "Lv.%d → %d" % [int(growth.level_before),int(growth.level_after)]
		_growth_label.text = "经验 +%d   %s" % [int(growth.experience_delta),level]
		if int(growth.get("talent_points_delta",0)) > 0:
			_growth_label.text += "   天赋点 +%d" % int(growth.talent_points_delta)

	## One pass over the reading order: a metric the settlement reports -- 0
	## included -- is drawn as it stands, and one it never carried keeps its tile
	## hidden instead of appearing as a zero.
	for metric_value in METRICS:
		var metric: Dictionary = metric_value
		var key := String(metric["key"])
		var reading := _reading_text(key, _result)
		_set_metric(key, reading if not reading.is_empty() else "—", _metric_color(key, outcome), not reading.is_empty())
	_ending_button.visible = is_final_victory
	_contract_button.visible = not is_final_victory

	var diagnosis_text := _defeat_diagnosis_text()
	_diagnosis_label.text = diagnosis_text
	var report_text := _defeat_report_text()
	_report_label.text = report_text
	_run_facts_label.text = _run_facts_text()
	_apply_report_evidence()

	var rewards := _as_dictionary(_result.get("rewards", {}))
	_equipment_drop_entries = _equipment_entries(rewards)
	_equipment_page = 0
	_loot_scroll.scroll_vertical = 0
	_close_equipment_detail()
	var proxy_component_entries := _proxy_component_entries()
	_render_proxy_component_cards(proxy_component_entries)
	_render_equipment_cards()
	_reward_label.text = "\n".join(_reward_lines(rewards, _equipment_drop_entries, proxy_component_entries))
	_reward_label.tooltip_text = _reward_label.text
	_subtitle_label.text = SUBTITLE_TEXT
	if not _equipment_drop_entries.is_empty() and not proxy_component_entries.is_empty():
		# The component card already explains its inventory state. Keep that fact
		# once, reserve the header for first-clear guidance and keep items in reach.
		var concise: Array[String] = ["本次获得装备 %d 件" % _equipment_drop_entries.size()]
		concise.append_array(_reward_field_lines(rewards))
		var drop_line := _drop_line(rewards)
		if not drop_line.is_empty(): concise.append(drop_line)
		_reward_label.text = "\n".join(concise)
		var first_reward := _first_reward_text()
		if not first_reward.is_empty(): _subtitle_label.text = first_reward.replace("\n", " · ")
	_render_core_rewards(rewards)



func _apply_report_evidence() -> void:
	var mode := _first_text([_result.get("mode", ""),_contract.get("mode", "")])
	var contract_name := _first_text([_contract.get("name", ""),_contract.get("title", ""),_result.get("contract_id", ""),_contract.get("contract_id", "")])
	contract_name = String(ContractTitles.get(contract_name,contract_name))
	mode = {"Manual":"手动", "Auto":"自动"}.get(mode,mode)
	_route_context.text = " · ".join([contract_name,mode]) if not contract_name.is_empty() else mode
	_route_context.tooltip_text = "本次契约与出征方式"
	_route_view.present(_reported_route_steps())
	var total: Variant = _reported_number(_result,["room_count"])
	var completed: Variant = _reported_number(_result,["rooms_completed"])
	var valid := total != null and completed != null and is_finite(float(total)) and is_finite(float(completed))
	valid = valid and float(total) > 0 and float(completed) >= 0 and float(completed) <= float(total) and floorf(float(total)) == float(total) and floorf(float(completed)) == float(completed)
	_room_progress.visible = valid
	_room_progress_label.text = "房间完成 %s" % _rooms_text(_result) if valid else "房间完成进度未完整记录"
	if valid:
		_room_progress.max_value = float(total)
		_room_progress.value = float(completed)
		_room_progress.tooltip_text = "仅表示已完成房间 / 契约房间总数，不是构筑评分"
	var observed: Array[String] = []
	for pair in [["elapsed","用时"],["kills","击杀"],["casts","施放"]]:
		var reading := _reading_text(pair[0],_result)
		if not reading.is_empty(): observed.append("%s %s" % [pair[1],reading])
	_evidence_bodies.observed.text = "\n".join(observed) if not observed.is_empty() else "没有可用的战斗读数。缺失不记作零。"
	_evidence_bodies.observed.tooltip_text = "本轮实际记录的用时、击杀与施放。"
	_evidence_bodies.unverified.text = "本轮只结算战斗与掉落。\n构筑成长结论请回验律场查看。"
	var diagnosis := _defeat_diagnosis_text()
	var bottleneck := _as_dictionary(_result.get("primary_bottleneck", {})) if not diagnosis.is_empty() else {}
	var title := String(bottleneck.get("title", "")).strip_edges()
	var action := String(bottleneck.get("action", "")).strip_edges()
	var failure_reason := _first_text([_result.get("failure_reason", "")])
	var source := _failure_source_text(failure_reason) if not failure_reason.is_empty() else _first_text([_result.get("error", "")])
	_evidence_bodies.bottleneck.text = title if not title.is_empty() else "本轮未发现明确的战斗瓶颈。"
	if not source.is_empty() and title.is_empty():
		_evidence_bodies.bottleneck.text += "\n本轮在完成前终止。"
	_evidence_bodies.bottleneck.tooltip_text = diagnosis + "\n" + source + "\n" + _defeat_report_text()
	_evidence_marks.bottleneck.set_warning(not title.is_empty())
	if not action.is_empty():
		_evidence_bodies.next.text = action
	elif String(_result.get("outcome", "")) == "final_victory":
		_evidence_bodies.next.text = "这段旅程已经完成。\n可进入结尾回顾。"
	elif _is_first_proxy_unlock(_as_dictionary(_result.get("rewards", {}))):
		_evidence_bodies.next.text = "四枚白色核心已经获得。\n回镇装配后可让代理出征。"
	else:
		_evidence_bodies.next.text = "回炉边镇整理装备，\n或前往验律场继续研究构筑。"
	_sync_metric_columns()


## Only observed room results become nodes. Missing room records stay missing;
## a supplied room_count is a progress denominator, never permission to fabricate
## unvisited/failed rooms or projectile event branches.
func _reported_route_steps() -> Array:
	var steps: Array = []
	for index in _room_results().size():
		var raw: Variant = _room_results()[index]
		var room := _as_dictionary(raw)
		var outcome := String(room.get("outcome", "")).to_lower()
		var state := "unknown"
		if outcome in ["victory","final_victory"]: state = "completed"
		elif outcome in ["defeat","error"]: state = "failed"
		var title := "第 %d 间" % (index+1)
		var subtitle := _outcome_text(outcome) if not outcome.is_empty() else "未记录"
		steps.append({"title":title,"state":state,"subtitle":subtitle})
	return steps


func _render_core_rewards(rewards: Dictionary) -> void:
	_clear_children(_core_rewards)
	_core_rewards.visible = _is_first_proxy_unlock(rewards)
	if not _core_rewards.visible:
		return
	# Only the actual first-unlock record may display the fixed reward set.
	# Explicit future/partial payloads are not padded to four granted objects.
	var granted_names := _proxy_core_names(rewards)
	for core_id in FIXED_CORE_IDS:
		var core_name := String(PROXY_CORE_LABELS[core_id])
		if not core_name in granted_names:
			continue
		var texture: Texture2D = _art.icon("core." + core_id)
		if texture == null:
			continue
		var card := PanelContainer.new()
		card.name = "CoreReward_" + core_id
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_core_rewards.add_child(card)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		card.add_child(row)
		var icon := _icon_node(texture)
		icon.set_meta("canonical_id", "core." + core_id)
		row.add_child(icon)
		var label := Label.new()
		label.text = core_name
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_font_size_override("font_size", SUBTITLE_FONT_SIZE)
		row.add_child(label)


func _set_metric(key: String, text_value: String, color: Color, visible: bool = true) -> void:
	var value: Label = _metric_values.get(key, null)
	var tile: Control = _metric_tiles.get(key, null)
	if tile != null:
		tile.visible = visible
	if value == null:
		return
	value.text = text_value
	value.add_theme_color_override("font_color", color)


func _outcome_text(outcome: String) -> String:
	var normalized := outcome.to_lower()
	if normalized.is_empty():
		return "未记录"
	if OUTCOME_LABELS.has(normalized):
		return String(OUTCOME_LABELS[normalized])
	return normalized.to_upper()


func _outcome_color(outcome: String) -> Color:
	if outcome in ["victory", "final_victory"]:
		return ShellThemeScript.PROXY
	if outcome in ["defeat", "error"]:
		return ShellThemeScript.WARNING
	return ShellThemeScript.BONE


## The copy for one metric of METRICS, or empty when the source does not report
## that field at all. Nothing on this path is defaulted to zero.
func _reading_text(key: String, source: Dictionary) -> String:
	match key:
		"outcome":
			return _outcome_text(String(source.get("outcome", "unknown")).to_lower())
		"elapsed":
			return _elapsed_text(source)
		"kills":
			return _count_text(source, ["defeated", "kills"])
		"casts":
			return _count_text(source, ["casts", "shots"])
		"rooms":
			return _rooms_text(source)
		"ticks":
			return _count_text(source, ["ticks"])
	return ""


func _metric_color(key: String, outcome: String) -> Color:
	return _outcome_color(outcome) if key == "outcome" else ShellThemeScript.BONE


## The run time in seconds, or empty when the settlement reports none.
func _elapsed_text(source: Dictionary) -> String:
	var value: Variant = _reported_number(source, ["elapsed_seconds", "elapsed", "time"])
	return "%.2f 秒" % float(value) if value != null else ""


## One reported count as copy, or empty when the source reports none.
func _count_text(source: Dictionary, keys: Array) -> String:
	var value: Variant = _reported_number(source, keys)
	return str(int(value)) if value != null else ""


## The first of the keys a source really reports as a number, or null when it
## reports none of them. A field that is present but not numeric counts as not
## reported: a reading that was never made is not rounded into a 0.
func _reported_number(source: Dictionary, keys: Array) -> Variant:
	for raw_key in keys:
		var key := String(raw_key)
		if not source.has(key):
			continue
		var value: Variant = source.get(key)
		if value is int or value is float:
			return float(value)
		if value is String and String(value).is_valid_float():
			return float(String(value))
	return null


## "完成 / 总数" from the two authoritative fields, or empty when the payload does
## not carry them: no room count is claimed that was not reported.
func _rooms_text(source: Dictionary) -> String:
	var has_completed := source.has("rooms_completed")
	var has_total := source.has("room_count")
	if has_completed and has_total:
		return "%d / %d" % [_coerce_int(source.get("rooms_completed", 0)), _coerce_int(source.get("room_count", 0))]
	if has_completed:
		return "%d" % _coerce_int(source.get("rooms_completed", 0))
	return ""


func _room_results() -> Array:
	var value: Variant = _result.get("room_results", [])
	return value if value is Array else []


func _run_facts_text() -> String:
	var lines: Array[String] = []
	var contract_id := _first_text([_result.get("contract_id", ""), _contract.get("contract_id", "")])
	if not contract_id.is_empty():
		lines.append("契约：%s" % contract_id)
	var mode := _first_text([_result.get("mode", ""), _contract.get("mode", "")])
	if not mode.is_empty():
		lines.append("模式：%s" % mode)
	var rooms := _rooms_text(_result)
	if not rooms.is_empty():
		lines.append("房间：%s 完成" % rooms)
	var outcomes: Array[String] = []
	for entry in _room_results():
		if entry is Dictionary:
			outcomes.append(_outcome_text(String((entry as Dictionary).get("outcome", "")).to_lower()))
	if not outcomes.is_empty():
		lines.append("逐间结果：%s" % "、".join(outcomes))
	var failure_reason := _first_text([_result.get("failure_reason", "")])
	if not failure_reason.is_empty():
		lines.append("终止原因：%s" % _failure_source_text(failure_reason))
	var error_code := _first_text([_result.get("error", "")])
	if not error_code.is_empty():
		lines.append("错误码：%s" % error_code)
	if lines.is_empty():
		return EMPTY_FACTS_TEXT
	return "\n".join(lines)


func _reward_lines(rewards: Dictionary, equipment_entries: Array, proxy_component_entries: Array = []) -> Array[String]:
	var lines: Array[String] = []
	if _is_first_proxy_unlock(rewards):
		lines.append("代理舱首次解锁！")
		lines.append("获得固定四白核心：%s" % "、".join(_proxy_core_names(rewards)))
		lines.append("下一步：前往代理舱，Auto 清房")
	var first_reward_text := _first_reward_text()
	if not first_reward_text.is_empty():
		lines.append(first_reward_text)
	if not equipment_entries.is_empty():
		lines.append("本次获得装备 %d 件" % equipment_entries.size())
	if not proxy_component_entries.is_empty():
		lines.append("代理组件已入库 · 尚未安装")
		lines.append("当前代理构筑不变")
	lines.append_array(_reward_field_lines(rewards))
	var drop_line := _drop_line(rewards)
	if not drop_line.is_empty():
		lines.append(drop_line)
	if lines.is_empty():
		lines.append(NO_REWARD_TEXT)
	return lines


## Known reward fields written as Chinese player copy. A zero delta stays out (it is
## not a reward), and the boolean bonus pair reports a real loss as 未获得.
func _reward_field_lines(rewards: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	var bonus_earned := bool(rewards.get("bonus_earned", false))
	var bonus_lost := bool(rewards.get("bonus_lost", false))
	if bonus_earned != bonus_lost:
		lines.append("%s：%s" % [TIMED_BONUS_LABEL, "已获得" if bonus_earned else "未获得"])
	var tally_delta := _as_dictionary(rewards.get("law_tallies_delta", {}))
	for operation in ["inscribe", "rewrite", "refine"]:
		var tally_amount := _coerce_int(tally_delta.get(operation, 0))
		if tally_amount != 0:
			lines.append("%s：%d" % [String(LAW_TALLY_LABELS[operation]), tally_amount])
	for key in REWARD_FIELD_LABELS:
		var field := String(key)
		if not rewards.has(field):
			continue
		var amount := _coerce_int(rewards.get(field, 0))
		if amount == 0:
			continue
		lines.append("%s：%d" % [String(REWARD_FIELD_LABELS[field]), amount])
	return lines


func _drop_line(rewards: Dictionary) -> String:
	var text_value := _scalar_text(_drop_value(rewards)).strip_edges()
	if text_value.is_empty():
		return ""
	return "普通掉落：%s" % text_value


## The ordinary drop of this settlement: an explicit `drop` / `last_drop` field
## first, then the reward block's label or id. A compound value is not printable as
## player copy and is listed raw in 计算详情 instead of being dumped into a line.
func _drop_value(rewards: Dictionary) -> Variant:
	for key in ["drop", "last_drop"]:
		if _result.has(key):
			return _result.get(key)
	for key in ["drop_label", "drop_id"]:
		if rewards.has(key):
			return rewards.get(key)
	return null


func _first_reward_text() -> String:
	var value: Variant = _result.get("first_reward_tags", [])
	if not (value is Array):
		return ""
	var lines: Array[String] = []
	for tag_value in (value as Array):
		var tag := String(tag_value)
		if FIRST_REWARD_LABELS.has(tag):
			lines.append(String(FIRST_REWARD_LABELS[tag]))
	return "首通奖励\n%s" % "\n".join(lines) if not lines.is_empty() else ""


func _is_first_proxy_unlock(rewards: Dictionary) -> bool:
	for source in [_result, rewards]:
		if bool(source.get("first_proxy_unlock", source.get("proxy_unlocked", false))):
			return true
		for key in ["unlock", "unlocks", "proxy_unlock"]:
			var value: Variant = source.get(key, null)
			if value is Dictionary:
				var data: Dictionary = value
				if bool(data.get("proxy_unlocked", false)):
					return true
				if bool(data.get("first", data.get("first_time", false))) and bool(data.get("proxy", data.get("proxy_unlocked", data.get("unlocked", true)))):
					return true
				if String(data.get("id", data.get("type", ""))).to_lower() in ["proxy", "proxy_bay"] and bool(data.get("unlocked", true)):
					return true
			elif value is Array:
				for item in value:
					if String(item).to_lower() in ["proxy", "proxy_bay", "proxy_unlocked"]:
						return true
	return false


## The granted components as display names, in payload order. Never padded: an
## unlock block lists exactly what the settlement granted.
func _proxy_core_names(rewards: Dictionary) -> Array[String]:
	var values: Array = []
	for source in [_result, rewards]:
		for key in ["proxy_cores", "cores"]:
			if source.get(key, null) is Array:
				values = source.get(key)
				break
		if values.is_empty():
			var unlock := _as_dictionary(source.get("unlock", source.get("unlocks", {})))
			var components: Variant = unlock.get("cores", unlock.get("components", null))
			values = components if components is Array else []
		if not values.is_empty():
			break
	var names: Array[String] = []
	for value in values:
		var core_id := String((value as Dictionary).get("id", "")) if value is Dictionary else String(value)
		var core_name := String((value as Dictionary).get("name", "")) if value is Dictionary else ""
		if core_name.is_empty():
			core_name = String(PROXY_CORE_LABELS.get(core_id.to_lower(), core_id))
		if not core_name.is_empty():
			names.append(core_name)
	if names.is_empty():
		names = PROXY_CORE_FALLBACK.duplicate()
	return names


## The current fixed page. Every entry remains reachable through pagination and
## every evidence accessor still reports payload order.
func _render_equipment_cards() -> void:
	_clear_equipment_cards()
	var first := _equipment_page * _equipment_page_size
	var last := mini(first + _equipment_page_size, _equipment_drop_entries.size())
	for index in range(first, last):
		_equipment_box.add_child(_equipment_card(_equipment_drop_entries[index], index))
	_sync_equipment_pagination()


func _equipment_page_count() -> int:
	return maxi(1, ceili(float(_equipment_drop_entries.size()) / float(_equipment_page_size)))


func _sync_equipment_pagination() -> void:
	if _equipment_pagination == null:
		return
	var page_count := _equipment_page_count()
	_equipment_page = clampi(_equipment_page, 0, page_count - 1)
	_equipment_pagination.visible = page_count > 1
	_page_label.text = "%d / %d" % [_equipment_page + 1, page_count]
	_previous_page_button.disabled = _equipment_page == 0
	_next_page_button.disabled = _equipment_page >= page_count - 1


## Proxy components are settlement inventory records, not equipment. Their own
## section has no loadout-comparison action and states that the frozen build did
## not change when the drop entered inventory.
func _render_proxy_component_cards(entries: Array) -> void:
	_clear_children(_proxy_component_box)
	_proxy_component_box.visible = not entries.is_empty()
	if entries.is_empty():
		return
	var heading := Label.new()
	heading.name = "ProxyComponentDropHeading"
	heading.text = "代理组件已入库 · 尚未安装"
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	heading.add_theme_font_size_override("font_size", ShellThemeScript.BODY_FONT_SIZE)
	heading.add_theme_color_override("font_color", ShellThemeScript.PROXY)
	_proxy_component_box.add_child(heading)
	for entry_value in entries:
		var entry := entry_value as Dictionary
		var card := PanelContainer.new()
		card.name = "ProxyComponentDrop_%s" % _stable_node_token(String(entry.get("id", "")))
		card.add_theme_stylebox_override("panel", _frame(ShellThemeScript.INK, ShellThemeScript.COPPER_DULL, 1))
		_proxy_component_box.add_child(card)
		var body := VBoxContainer.new()
		body.add_theme_constant_override("separation", 4)
		card.add_child(body)
		var title := Label.new()
		title.name = "ProxyComponentName"
		title.text = "%s · %s" % [String(entry.get("name", entry.get("id", "未知核心"))), _proxy_slot_label(String(entry.get("slot", "")))]
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		title.add_theme_font_size_override("font_size", ShellThemeScript.BODY_FONT_SIZE)
		body.add_child(title)
		var protocol := Label.new()
		protocol.name = "ProxyComponentProtocol"
		protocol.text = "协议：%s\n尚未安装，当前代理构筑不变" % String(entry.get("protocol", "未记录"))
		protocol.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		protocol.add_theme_font_size_override("font_size", SUBTITLE_FONT_SIZE)
		protocol.add_theme_color_override("font_color", ShellThemeScript.NEUTRAL)
		body.add_child(protocol)
		if not _equipment_drop_entries.is_empty():
			# Full protocol remains inspectable on hover without pushing the
			# equipment comparison action below a small monitor's footer.
			protocol.visible = false
			card.tooltip_text = protocol.text
			title.tooltip_text = protocol.text
			card.mouse_filter = Control.MOUSE_FILTER_STOP


func _proxy_component_entries() -> Array:
	var value: Variant = _result.get("proxy_component_drops", null)
	if not value is Array:
		return []
	var entries: Array = []
	for item_value in value as Array:
		if not item_value is Dictionary:
			continue
		var item := item_value as Dictionary
		if String(item.get("id", "")).strip_edges().is_empty():
			continue
		entries.append(item.duplicate(true))
	return entries


func _proxy_slot_label(slot: String) -> String:
	return String({
		"perception": "感知槽",
		"movement": "行动槽",
		"execution": "执行槽",
		"memory": "记忆槽",
	}.get(slot, slot if not slot.is_empty() else "未知槽位"))


## One drop: the published subject icon, the Chinese name of the base item, its
## slot badge and the named affixes on the card face, with the complete field line
## kept on the card for get_equipment_card_texts. The face carries no instance id.
func _equipment_card(entry: Dictionary, entry_index: int = 0) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = CARD_NODE_NAME
	card.add_theme_stylebox_override("panel", _frame(ShellThemeScript.INK, ShellThemeScript.COPPER_DULL, 1))
	card.set_meta(CARD_AUDIT_META, _equipment_field_text(entry))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	card.add_child(row)
	## The card has one subject: the item the run actually produced, at the batch's
	## single allowed display step. A drop the batch does not publish keeps its text
	## alone -- no stand-in image is drawn in its place.
	var base_item_id := String(entry.get("base_item_id", "")).strip_edges()
	var subject_texture: Texture2D = null
	if not base_item_id.is_empty():
		subject_texture = _art.icon("equipment.%s" % base_item_id)
	if subject_texture != null:
		var subject := _icon_node(subject_texture)
		subject.name = BASE_ICON_NODE_NAME
		subject.set_meta("canonical_id", "equipment.%s" % base_item_id)
		row.add_child(subject)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 4)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(body)
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 8)
	body.add_child(title_row)
	var slot := String(entry.get("slot", "")).strip_edges()
	var slot_texture: Texture2D = null
	if not slot.is_empty():
		slot_texture = _art.icon("equipment_slot.%s" % slot)
	if slot_texture != null:
		## The slot is an identity badge at its native 32px cell, so it never reads
		## as a second image of the same size competing with the dropped item.
		var badge := _icon_node(slot_texture, false)
		badge.name = SLOT_BADGE_NODE_NAME
		badge.set_meta("canonical_id", "equipment_slot.%s" % slot)
		title_row.add_child(badge)
	var name_label := Label.new()
	name_label.name = CARD_NAME_NODE_NAME
	name_label.text = _item_display_name(entry)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", ShellThemeScript.BODY_FONT_SIZE)
	name_label.add_theme_color_override("font_color", ShellThemeScript.BONE)
	title_row.add_child(name_label)
	var detail_button := Button.new()
	detail_button.name = "EquipmentDetailButton"
	detail_button.text = EQUIPMENT_DETAIL_TEXT
	detail_button.tooltip_text = "展开这件装备的完整属性说明"
	detail_button.pressed.connect(_on_equipment_detail_pressed.bind(entry_index))
	title_row.add_child(detail_button)
	var instance_id := String(entry.get("instance_id", "")).strip_edges()
	if not instance_id.is_empty() and not slot.is_empty():
		# Keep the decision in the card's first screen. Equipment descriptions can be
		# long and scroll independently; hiding the only comparison entry below them
		# would make the settlement look informational rather than actionable.
		var review_button := Button.new()
		review_button.name = "ReviewDrop_%s" % _stable_node_token(instance_id)
		var equipment_state := _equipment_state(entry)
		review_button.text = String({
			"equipped": "查看（已装备）", "owned": REVIEW_DROP_TEXT,
			"missing": "已不在行囊中", "unknown": "到备行架比较",
		}.get(equipment_state, "到备行架比较"))
		review_button.disabled = equipment_state == "missing"
		review_button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		review_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		review_button.tooltip_text = "%s；打开备行架查看这件%s装备" % [_equipment_status_text(entry), _player_readable.slot_label(slot)]
		review_button.pressed.connect(_on_review_drop_pressed.bind(instance_id, slot))
		body.add_child(review_button)
	var summary := Label.new()
	summary.name = CARD_TEXT_NODE_NAME
	summary.text = _equipment_summary_text(entry)
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary.add_theme_font_size_override("font_size", SUBTITLE_FONT_SIZE)
	summary.add_theme_color_override("font_color", ShellThemeScript.NEUTRAL)
	body.add_child(summary)
	return card


## Ownership and equipment come from the current profile, independently of the
## immutable item record in the settlement receipt.
func _equipment_state(entry: Dictionary) -> String:
	if _current_profile.is_empty():
		return "unknown"
	var instance_id := String(entry.get("instance_id", ""))
	var active := _as_dictionary(_current_profile.get("active_build", {}))
	var equipped := _as_dictionary(active.get("equipped_item_ids", {}))
	if not instance_id.is_empty() and String(equipped.get(String(entry.get("slot", "")), "")) == instance_id:
		return "equipped"
	var inventory := _as_dictionary(_current_profile.get("inventory", {}))
	var items: Variant = inventory.get("equipment", [])
	if items is Array:
		for item: Variant in items:
			if item is Dictionary and String(item.get("instance_id", "")) == instance_id:
				return "owned"
	return "missing"


func _equipment_status_text(entry: Dictionary) -> String:
	match _equipment_state(entry):
		"equipped": return "当前已装备，正在使用"
		"owned": return "当前在行囊中，尚未装备"
		"missing": return "当前已不在行囊中，获得记录保留"
	return "当前装备状态未读取，可到备行架查看"


func _equipment_summary_text(entry: Dictionary) -> String:
	var affixes: Array[String] = _equipment_model.affix_labels(entry.get("affixes", []), true)
	return "%s · 获得时已收入装备库存\n%s\n词条：%s\n完整属性见详情" % [
		_player_readable.slot_label(String(entry.get("slot", ""))),
		_equipment_status_text(entry),
		"、".join(affixes) if not affixes.is_empty() else "无记录",
	]


func _equipment_full_text(entry: Dictionary) -> String:
	var current := _as_dictionary(entry.get("current_parameters", {}))
	var replacement := _as_dictionary(entry.get("equipped_parameters", {}))
	var historical_preview := "\n获得时的换装预览：" if not current.is_empty() or not replacement.is_empty() else ""
	return "获得时：已收入装备库存\n%s%s\n%s" % [
		_equipment_status_text(entry), historical_preview, _player_readable.format_item(entry, current, replacement),
	]


## The complete field line of one drop, printed as it stands: slot, published name,
## base id, affixes by their raw family ids, the untruncated instance id and the
## rest of the item record. This is what get_equipment_card_texts reads back.
func _equipment_field_text(entry: Dictionary) -> String:
	return _equipment_model.result_audit(entry)


func _clear_equipment_cards() -> void:
	_clear_children(_equipment_box)


func _open_equipment_detail(entry_index: int) -> void:
	var bounded := clampi(entry_index, 0, maxi(_equipment_drop_entries.size() - 1, 0))
	if _equipment_drop_entries.is_empty():
		return
	var entry := _equipment_drop_entries[bounded] as Dictionary
	_equipment_detail_title.text = _item_display_name(entry)
	_equipment_detail_body.text = _equipment_full_text(entry)
	var panel := _equipment_detail_overlay.get_node("EquipmentDetailPanel") as Control
	var extent := Vector2(minf(900.0, size.x - 64.0), minf(600.0, size.y - 64.0))
	panel.offset_left = -extent.x / 2.0
	panel.offset_right = extent.x / 2.0
	panel.offset_top = -extent.y / 2.0
	panel.offset_bottom = extent.y / 2.0
	(_equipment_detail_overlay.find_child("EquipmentDetailScroll", true, false) as ScrollContainer).scroll_vertical = 0
	_equipment_detail_overlay.visible = true


func _close_equipment_detail() -> void:
	if _equipment_detail_overlay != null:
		_equipment_detail_overlay.visible = false


func _on_equipment_detail_pressed(entry_index: int) -> void:
	_open_equipment_detail(entry_index)


func _on_equipment_detail_closed() -> void:
	_close_equipment_detail()


func _on_previous_equipment_page() -> void:
	_set_equipment_page(_equipment_page - 1)


func focus_equipment(instance_id: String) -> void:
	for index in _equipment_drop_entries.size():
		if String(_equipment_drop_entries[index].get("instance_id", "")) == instance_id:
			_set_equipment_page(index / _equipment_page_size)
			return


func _on_next_equipment_page() -> void:
	_set_equipment_page(_equipment_page + 1)


func _set_equipment_page(page: int) -> void:
	_equipment_page = clampi(page, 0, _equipment_page_count() - 1)
	_close_equipment_detail()
	_loot_scroll.scroll_vertical = 0
	_render_equipment_cards()


func _clear_children(box: Node) -> void:
	if box == null:
		return
	for child in box.get_children():
		box.remove_child(child)
		child.free()


## The player-facing name of one dropped item: an explicit name field on the drop
## first, then the published base item of the content table. Unknown raw ids stay
## in the folded diagnostic text instead of leaking onto the player-facing card.
func _item_display_name(entry: Dictionary) -> String:
	return _equipment_model.display_name(entry)


## One affix per entry as "name Tn". With published names off, the raw family id is
## kept, which is the audit form. With them on, an explicit name field on the affix
## wins, then the published affix table, and an id neither covers stays raw. A drop
## that reports no tier states none instead of claiming T0.
func _affix_lines(value: Variant, published_names: bool) -> Array[String]:
	return _equipment_model.affix_labels(value, published_names)


## One published name out of the content table this screen reads read-only, or the
## id itself when the table does not cover it.
func _published_name(table: String, id: String) -> String:
	var row := _as_dictionary(_published_rows(table).get(id, null))
	var published := String(row.get("name", "")).strip_edges()
	return published if not published.is_empty() else id


func _published_rows(table: String) -> Dictionary:
	if _item_registry == null:
		return {}
	return _as_dictionary(_item_registry.base_items if table == "base_items" else _item_registry.affix_families)


## The authoritative instance id, whole. A display that shortens an id hides the one
## field that identifies which drop this actually is, so nothing is cut here; the
## audit line and 计算详情 print it in full, and the detail block may break inside it.
func _instance_id_text(value: Variant) -> String:
	return _equipment_model.instance_id_text(value)


func _registry_rows(table: String) -> Dictionary:
	if _item_registry == null:
		return {}
	return _as_dictionary(_item_registry.base_items if table == "base_items" else _item_registry.affix_families)


func _equipment_entries(rewards: Dictionary) -> Array:
	var drops_value: Variant = rewards.get("equipment_drops", _result.get("equipment_drops", null))
	if not (drops_value is Array):
		return []
	var count_value: Variant = rewards.get("equipment_drop_count", _result.get("equipment_drop_count", null))
	var declared_count := -1
	if count_value is int or count_value is float:
		declared_count = int(count_value)
		if declared_count <= 0:
			return []
	elif count_value is String and String(count_value).is_valid_int():
		declared_count = int(String(count_value))
		if declared_count <= 0:
			return []
	var entries: Array = []
	for item in drops_value:
		if not (item is Dictionary):
			continue
		var entry: Dictionary = item
		if not entry.has("slot") or not entry.has("base_item_id"):
			continue
		if not (entry.get("slot") is String) or not (entry.get("base_item_id") is String):
			continue
		entries.append(entry)
		if declared_count > 0 and entries.size() >= declared_count:
			break
	return entries


## The authoritative field table behind the summary: contract, mode, preset, seed,
## the run totals and one line per room. Values are printed as they stand.
func _detail_lines() -> Array[String]:
	var lines: Array[String] = []
	lines.append("契约 ID：%s" % _or_unrecorded(_first_text([_result.get("contract_id", "")])))
	lines.append("模式：%s" % _or_unrecorded(_first_text([_result.get("mode", ""), _contract.get("mode", "")])))
	lines.append("预设：%s" % _or_unrecorded(_first_text([_result.get("preset_id", "")])))
	lines.append("种子：%s" % _or_unrecorded(_first_text([_result.get("seed", "")])))
	lines.append("运行读数：%s" % _run_totals_text())
	var rooms := _rooms_text(_result)
	if not rooms.is_empty():
		lines.append("房间：%s 完成" % rooms)
	var results := _room_results()
	for index in results.size():
		var entry: Variant = results[index]
		if not (entry is Dictionary):
			continue
		var room: Dictionary = entry
		lines.append("房间 %d：%s" % [index + 1, _room_reading_text(room)])
		var room_report := _first_text([room.get("report", "")])
		if not room_report.is_empty():
			lines.append("房间 %d 报告：%s" % [index + 1, room_report])
		var room_failure := _first_text([room.get("failure_reason", "")])
		if not room_failure.is_empty():
			lines.append("房间 %d 终止原因：%s" % [index + 1, _failure_source_text(room_failure)])
	if not _art_error.is_empty():
		lines.append("图标资源：%s" % _art_error)
	return lines


## The settlement's own run totals, assembled only from the fields it reports. A
## field that was never carried makes the line say 未记录 instead of appearing as
## a zero; a field that really is 0 is printed as the reading it is.
func _run_totals_text() -> String:
	var totals := _fields_text(_result, TOTAL_FIELDS)
	return totals if not totals.is_empty() else "未记录"


## One room's own readings, printed as far as that room really reported them.
func _room_reading_text(room: Dictionary) -> String:
	var outcome := "结果 %s" % _outcome_text(String(room.get("outcome", "")).to_lower())
	var readings := _fields_text(room, ROOM_FIELDS)
	return outcome if readings.is_empty() else "%s    %s" % [outcome, readings]


## The listed readings a source really reports, as "label：value" pairs. Nothing
## is filled in for a field the source does not carry.
func _fields_text(source: Dictionary, fields: Array) -> String:
	var parts: Array[String] = []
	for field_value in fields:
		var field: Dictionary = field_value
		var reading := _reading_text(String(field["key"]), source)
		if not reading.is_empty():
			parts.append("%s：%s" % [String(field["label"]), reading])
	return "    ".join(parts)


## Raw disclosure: every dropped instance at full length, its source, and any field
## outside the known table, printed as it stands. This is where metadata the screen
## does not turn into player copy is surfaced instead of being dropped.
func _detail_raw_lines(rewards: Dictionary, entries: Array) -> Array[String]:
	var lines: Array[String] = []
	if not entries.is_empty():
		lines.append("掉落完整字段（未截断）：")
		for entry in entries:
			var item: Dictionary = entry
			lines.append("· %s" % _equipment_field_text(item))
	# Only in the explicit detail drawer: future fields remain inspectable
	# without inferring their units or maintaining another authority schema.
	lines.append("完整结算记录（包含附加字段，未做换算）：")
	lines.append(JSON.stringify(_presentation_payload(_result)))
	return lines


## The authority payload itself stays untouched in `_result`. Only this copy for
## the visible disclosure replaces failure source ids, including nested rooms.
func _presentation_payload(value: Variant) -> Variant:
	if value is Dictionary:
		var displayed: Dictionary = {}
		for raw_key in (value as Dictionary):
			var key := String(raw_key)
			var raw_value: Variant = (value as Dictionary)[raw_key]
			displayed[raw_key] = _failure_source_text(String(raw_value)) if key == "failure_reason" else _presentation_payload(raw_value)
		return displayed
	if value is Array:
		var displayed_items: Array = []
		for item in (value as Array):
			displayed_items.append(_presentation_payload(item))
		return displayed_items
	return value


## A scalar as copy, or empty when the value is not one (compounds belong to the raw
## detail block, never to a player-facing line).
func _scalar_text(value: Variant) -> String:
	if value == null:
		return ""
	if value is bool or value is int or value is float or value is String:
		return str(value)
	return ""


## Any value as raw text for the disclosure block.
func _raw_text(value: Variant) -> String:
	if value == null:
		return ""
	if value is bool or value is int or value is float or value is String:
		return str(value)
	return JSON.stringify(value)


func _sync_detail_visibility() -> void:
	if _detail_panel == null:
		return
	_detail_panel.visible = _detail_visible
	_detail_button.text = DETAIL_HIDE_TEXT if _detail_visible else DETAIL_SHOW_TEXT


func _first_text(values: Array) -> String:
	for value in values:
		if value is String:
			var text_value := String(value).strip_edges()
			if not text_value.is_empty():
				return text_value
		elif value is int or value is float:
			return str(value)
	return ""


func _or_unrecorded(text_value: String) -> String:
	return text_value if not text_value.is_empty() else "未记录"


func _failure_source_text(value: String) -> String:
	return PlayerFacingStatusScript.failure_source_label(value)


func _defeat_diagnosis_text() -> String:
	if String(_result.get("outcome", "unknown")).to_lower() != "defeat":
		return ""
	var bottleneck_value: Variant = _result.get("primary_bottleneck", null)
	if not (bottleneck_value is Dictionary):
		return ""
	var bottleneck: Dictionary = bottleneck_value
	var title := String(bottleneck.get("title", "")).strip_edges()
	var action := String(bottleneck.get("action", "")).strip_edges()
	if title.is_empty() and action.is_empty():
		return ""
	var lines: Array[String] = []
	if not title.is_empty():
		lines.append("失败主因：%s" % title)
	if not action.is_empty():
		lines.append("行动建议：%s" % action)
	return "\n".join(lines)


func _defeat_report_text() -> String:
	if String(_result.get("outcome", "unknown")).to_lower() != "defeat":
		return ""
	var report_value: Variant = _result.get("report", "")
	if not (report_value is String):
		return ""
	var report := String(report_value).strip_edges()
	if report.is_empty():
		return ""
	return "战报：%s" % report


func _coerce_int(value: Variant) -> int:
	if value is int:
		return int(value)
	if value is float:
		return int(value)
	if value is bool:
		return 1 if bool(value) else 0
	if value is String and String(value).is_valid_int():
		return int(String(value))
	return 0


func _as_dictionary(value: Variant) -> Dictionary:
	return value as Dictionary if value is Dictionary else {}


func _heading(text_value: String) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", ShellThemeScript.BODY_FONT_SIZE)
	label.add_theme_color_override("font_color", ShellThemeScript.BONE)
	return label


func _rule() -> ColorRect:
	var rule := ColorRect.new()
	rule.name = "HeaderRule"
	rule.color = ShellThemeScript.COPPER_DULL
	rule.custom_minimum_size = Vector2(0.0, 2.0)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rule


func _frame(_fill: Color, _border: Color, width: int) -> StyleBox:
	var box := ShellThemeScript.panel_style("selected" if width > 1 else "panel")
	box.content_margin_left = 14.0
	box.content_margin_top = 10.0
	box.content_margin_right = 14.0
	box.content_margin_bottom = 10.0
	return box


## One published 32x32 cell. The default is the batch's single allowed display step
## (2x, so 64 pixels and no resampling); `native` keeps the cell at its own 32px
## size, which only the slot badge uses.
func _icon_node(texture: Texture2D, scaled: bool = true) -> TextureRect:
	var icon: TextureRect = PixelGridIconScript.new() if scaled else TextureRect.new()
	icon.texture = texture
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_SCALE
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var display_size := Vector2(FacilityArtScript.ICON_NATIVE_SIZE)
	if scaled:
		display_size *= FacilityArtScript.ICON_DISPLAY_SCALE
	icon.custom_minimum_size = display_size
	return icon


## Read-only load of the published icon batch. A package that cannot be read leaves
## the reason for the detail block; every card keeps its text either way.
func _load_art() -> void:
	_art_error = ""
	if _art.load_art():
		return
	_art_error = String(_art.pending_reason)


## Read-only load of the content table that names base items and affix families. A
## package whose table cannot be read keeps both lookups empty, and every id then
## stays raw on the card instead of borrowing a name it was never given.
func _load_item_names() -> void:
	var registry = EarlyItemRegistryScript.new()
	if not registry.load_all().is_empty():
		return
	_item_registry = registry
	_player_readable = PlayerReadableBuildScript.new(registry)
	_equipment_model = EquipmentPresentationModelScript.new(_player_readable, _registry_rows("base_items"), _registry_rows("affix_families"), {}, "未知装备")


## ---- public surface used by the router, the harness and the tests ----


func get_reward_text() -> String:
	return _reward_label.tooltip_text if _reward_label != null else ""


func get_diagnosis_text() -> String:
	return _diagnosis_label.text if _diagnosis_label != null else ""


func get_report_text() -> String:
	return _report_label.text if _report_label != null else ""


## The authoritative run facts beside the report: contract, mode, room progress,
## per-room outcomes and the named failure reason.
func get_run_facts_text() -> String:
	return _run_facts_label.text if _run_facts_label != null else ""


## The settlement payload as this screen received it, for evidence capture: the
## copy on screen can be read back against the authority that produced it.
func get_presented_result() -> Dictionary:
	return _result.duplicate(true)


func get_presented_contract() -> Dictionary:
	return _contract.duplicate(true)


func get_detail_text() -> String:
	var rewards := _as_dictionary(_result.get("rewards", {}))
	return "\n".join(_detail_lines() + _detail_raw_lines(rewards, _equipment_entries(rewards)))


func set_detail_visible(value: bool) -> void:
	_detail_visible = value
	_sync_detail_visibility()


func is_detail_visible() -> bool:
	return _detail_panel != null and _detail_panel.visible


func get_equipment_card_count() -> int:
	return _equipment_box.get_child_count() if _equipment_box != null else 0


func get_proxy_component_card_texts() -> Array[String]:
	var texts: Array[String] = []
	if _proxy_component_box == null:
		return texts
	for card in _proxy_component_box.get_children():
		var name_label := card.find_child("ProxyComponentName", true, false) as Label
		var protocol_label := card.find_child("ProxyComponentProtocol", true, false) as Label
		if name_label != null and protocol_label != null:
			texts.append("%s\n%s" % [name_label.text, protocol_label.text])
	return texts


## The complete field set of every card, in card order: slot, published name, base
## id, raw affix families, the untruncated instance id and the rest of the item
## record. The card face shows the name, the slot and the affixes; this accessor is
## what the evidence harness reads back, so a shortened id cannot pass unnoticed.
func get_equipment_card_texts() -> Array[String]:
	var texts: Array[String] = []
	if _equipment_box == null:
		return texts
	for child in _equipment_box.get_children():
		var text_value := _card_audit_text(child)
		if not text_value.is_empty():
			texts.append(text_value)
	return texts


## What each card really shows, read from its visible labels rather than from a
## cached string, so a drift between the card and this accessor cannot pass.
func get_equipment_card_summaries() -> Array[String]:
	var texts: Array[String] = []
	if _equipment_box == null:
		return texts
	for child in _equipment_box.get_children():
		var parts: Array[String] = []
		for node_name in [CARD_NAME_NODE_NAME, CARD_TEXT_NODE_NAME]:
			var label := child.find_child(node_name, true, false) as Label
			if label != null and not label.text.strip_edges().is_empty():
				parts.append(label.text)
		if not parts.is_empty():
			texts.append(" · ".join(parts))
	return texts


## A card's own complete field line, wherever the card structure puts it.
func _card_audit_text(card: Node) -> String:
	var stored := String(card.get_meta(CARD_AUDIT_META, ""))
	if not stored.is_empty():
		return stored
	if card is Label:
		return (card as Label).text
	var label := card.find_child(CARD_TEXT_NODE_NAME, true, false) as Label
	return label.text if label != null else ""


func _stable_node_token(value: String) -> String:
	var token := ""
	for index in value.length():
		var character := value.substr(index, 1)
		var code := character.unicode_at(0)
		var legal := code >= 48 and code <= 57 or code >= 65 and code <= 90 or code >= 97 and code <= 122 or character in ["_", "-"]
		token += character if legal else "_"
	return token


func _on_detail_pressed() -> void:
	_detail_visible = not _detail_visible
	_sync_detail_visibility()


func _on_base_pressed() -> void:
	base_requested.emit()


func _on_contract_pressed() -> void:
	contract_requested.emit()


func _on_review_drop_pressed(instance_id: String, slot: String) -> void:
	loadout_review_requested.emit(instance_id, slot)


func _on_ending_pressed() -> void:
	ending_requested.emit()
