class_name ResultReportPanel
extends RefCounted
## The pinned header and the right-hand report lane of the ResultScreen,
## extracted from it. This collaborator builds the title row, the metric tiles,
## the route/progress strip and the evidence cards, and writes the settlement
## copy into them, reaching the screen only through the untyped owner
## reference for its size and node lookups.

const ShellThemeScript = preload("res://src/presentation/shell_theme.gd")
const ReportEvidenceMarkScript = preload("res://src/presentation/report_evidence_mark.gd")
const SettlementRouteViewScript = preload("res://src/presentation/settlement_route_view.gd")
const ContractTitles = preload("res://src/presentation/contract_screen.gd").NODE_TITLES
const UiKit := preload("res://src/presentation/ui_kit.gd")
const ResultTextScript = preload("res://src/presentation/result/result_text.gd")
const ResultWidgetsScript = preload("res://src/presentation/result/result_widgets.gd")

const TITLE_TEXT := "Contract Results"
const KICKER_TEXT := "CONTRACT REPORT"
const SUBTITLE_TEXT := "Review your rewards, then compare your build."
const REPORT_DETAIL_TEXT := "Battle Report Details"
const REPORT_HIDE_TEXT := "Hide Battle Report"

var diagnosis_label: Label
var report_label: Label
var run_facts_label: Label

var _screen
var _growth_label: Label
var _header_kicker: Label
var _title_label: Label
var _subtitle_label: Label
var _metric_values: Dictionary = {}
var _metric_tiles: Dictionary = {}
var _report_detail_button: Button
var _metrics_grid: GridContainer
var _report_illustration: Control
var _next_step_label: Label
var _route_context: Label
var _route_view: Control
var _room_progress: ProgressBar
var _room_progress_label: Label
var _evidence_grid: GridContainer
var _evidence_bodies := {}
var _evidence_marks := {}


func _init(screen) -> void:
	_screen = screen


func build_header(root: Control) -> void:
	var scenery := TextureRect.new()
	scenery.name = "SettlementIllustration"
	scenery.texture = ShellThemeScript.illustration_texture("settlement_table")
	scenery.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	scenery.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	scenery.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scenery.modulate = Color(0.72, 0.72, 0.72, 1)
	root.add_child(scenery)
	ResultWidgetsScript.place_section(scenery, 0, 0, 0, 107)
	var shade := TextureRect.new()
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color("111820f5"), Color("111820c9"), Color("11182052")])
	gradient.offsets = PackedFloat32Array([0, 0.55, 1])
	var fade := GradientTexture2D.new()
	fade.gradient = gradient
	fade.fill_from = Vector2(0, 0.5)
	fade.fill_to = Vector2(1, 0.5)
	shade.texture = fade
	scenery.add_child(shade)
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
	_title_label.add_theme_font_size_override("font_size", ResultWidgetsScript.TITLE_FONT_SIZE)
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
	kicker.add_theme_font_size_override("font_size", ResultWidgetsScript.SUBTITLE_FONT_SIZE)
	kicker.add_theme_color_override("font_color", ShellThemeScript.NEUTRAL)
	title_row.add_child(kicker)

	_subtitle_label = Label.new()
	_subtitle_label.name = "ResultSubtitle"
	_subtitle_label.text = SUBTITLE_TEXT
	_subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle_label.add_theme_font_size_override("font_size", ResultWidgetsScript.SUBTITLE_FONT_SIZE)
	_subtitle_label.add_theme_color_override("font_color", ShellThemeScript.NEUTRAL)
	header.add_child(_subtitle_label)
	header.add_child(ResultWidgetsScript.rule())


func _build_metrics(parent: Control) -> void:
	var grid := GridContainer.new()
	_metrics_grid = grid
	grid.name = "ResultMetrics"
	grid.columns = ResultWidgetsScript.METRIC_COLUMNS
	grid.add_theme_constant_override("h_separation", ResultWidgetsScript.BLOCK_SEPARATION)
	grid.add_theme_constant_override("v_separation", ResultWidgetsScript.BLOCK_SEPARATION)
	parent.add_child(grid)
	for metric_value in ResultTextScript.METRICS:
		var metric: Dictionary = metric_value
		var key := String(metric["key"])
		var tile := PanelContainer.new()
		tile.name = "MetricTile_%s" % key
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var metric_style := ResultWidgetsScript.frame(ShellThemeScript.DEEP_BLUE, ShellThemeScript.COPPER_DULL, 1)
		metric_style.content_margin_top = 6
		metric_style.content_margin_bottom = 6
		tile.add_theme_stylebox_override("panel", metric_style)
		grid.add_child(tile)
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 4)
		tile.add_child(column)
		var label := Label.new()
		label.text = String(metric["label"])
		label.add_theme_font_size_override("font_size", ResultWidgetsScript.METRIC_LABEL_FONT_SIZE)
		label.add_theme_color_override("font_color", ShellThemeScript.NEUTRAL)
		column.add_child(label)
		var value := Label.new()
		value.name = "MetricValue_%s" % key
		value.theme_type_variation = "DataLabel"
		value.text = "—"
		value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		value.add_theme_font_size_override("font_size", ResultWidgetsScript.METRIC_VALUE_FONT_SIZE)
		value.add_theme_color_override("font_color", ShellThemeScript.BONE)
		column.add_child(value)
		_metric_tiles[key] = tile
		_metric_values[key] = value


func sync_metric_columns() -> void:
	if _metrics_grid != null:
		# On the approved shell canvas metrics occupy one quiet strip; keep
		# three columns on narrow logical views without shrinking Chinese text.
		_metrics_grid.columns = 3
	if _evidence_grid != null:
		_evidence_grid.columns = 4 if _screen.size.x >= 1200.0 else 2


func set_report_detail_visible(value: bool) -> void:
	if _metrics_grid == null or _evidence_grid == null:
		return
	_metrics_grid.visible = not value
	_evidence_grid.visible = value
	if _report_illustration != null: _report_illustration.visible = not value
	for body in _evidence_bodies.values():
		(body as Label).visible = value
	var scroll := _screen.find_child("CurrentRunScroll", true, false) as ScrollContainer
	if scroll != null:
		scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_report_detail_button.text = REPORT_HIDE_TEXT if value else REPORT_DETAIL_TEXT


func _on_report_detail_pressed() -> void:
	set_report_detail_visible(not _evidence_grid.visible)


func build(parent: Control) -> void:
	var panel := PanelContainer.new()
	panel.name = "ReportPanel"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.name = "CurrentRunScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	ShellThemeScript.hide_passive_scrollbar_chrome(scroll)
	panel.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.clip_contents = true
	column.add_theme_constant_override("separation", 6)
	scroll.add_child(column)
	column.add_child(ResultWidgetsScript.heading("Result and Next Steps"))
	_next_step_label = ResultWidgetsScript.report_note("")
	_next_step_label.name = "NextStepLabel"
	_next_step_label.add_theme_font_size_override("font_size", ShellThemeScript.BODY_FONT_SIZE)
	_next_step_label.add_theme_color_override("font_color", ShellThemeScript.AMBER)
	column.add_child(_next_step_label)
	_route_context = ResultWidgetsScript.report_note("")
	_route_context.name = "RunContext"
	column.add_child(_route_context)
	_route_view = SettlementRouteViewScript.new()
	_route_view.name = "SettlementRoute"
	column.add_child(_route_view)
	var progress_row := HBoxContainer.new()
	progress_row.add_theme_constant_override("separation",12)
	column.add_child(progress_row)
	_room_progress_label = ResultWidgetsScript.report_note("")
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
	diagnosis_label = Label.new()
	diagnosis_label.name = "BossDiagnosis"
	diagnosis_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	diagnosis_label.add_theme_color_override("font_color", ShellThemeScript.WARNING)
	diagnosis_label.visible = false
	report_label = Label.new()
	report_label.name = "BattleReport"
	report_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	report_label.visible = false
	run_facts_label = Label.new()
	run_facts_label.name = "RunFacts"
	run_facts_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	run_facts_label.visible = false
	for label in [diagnosis_label,report_label,run_facts_label]:
		column.add_child(label)
	_build_evidence_cards(column)
	_evidence_grid.visible = false
	_report_illustration = Control.new()
	_report_illustration.name = "HearthReturnIllustration"
	_report_illustration.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_report_illustration.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_report_illustration.clip_contents = true
	column.add_child(_report_illustration)
	var illustration := TextureRect.new()
	illustration.texture = ShellThemeScript.illustration_texture("settlement_table")
	illustration.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	illustration.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	illustration.mouse_filter = Control.MOUSE_FILTER_IGNORE
	illustration.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_report_illustration.add_child(illustration)
	# Extra artwork uses spare space only; dense reports keep their full reading area.
	_report_illustration.resized.connect(func(): illustration.visible = _report_illustration.size.y >= 80)


func _build_evidence_cards(parent: Control) -> void:
	_evidence_grid = GridContainer.new()
	_evidence_grid.name = "ReportEvidenceCards"
	_evidence_grid.columns = 4
	_evidence_grid.add_theme_constant_override("h_separation", 12)
	_evidence_grid.add_theme_constant_override("v_separation", 12)
	parent.add_child(_evidence_grid)
	for row in [["observed","This Run's Performance"],["unverified","Build Progress"],["bottleneck","Hazard Notes"],["next","Next Step"]]:
		var panel := PanelContainer.new()
		panel.name = "EvidenceCard_" + row[0]
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var card_style := ResultWidgetsScript.frame(ShellThemeScript.DEEP_BLUE,ShellThemeScript.COPPER_DULL,1)
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
		header.add_child(ResultWidgetsScript.heading(row[1]))
		var body := ResultWidgetsScript.report_note("")
		body.name = "EvidenceBody_" + row[0]
		body.visible = false
		column.add_child(body)
		_evidence_bodies[row[0]] = body


func set_metric(key: String, text_value: String, color: Color, visible: bool = true) -> void:
	var value: Label = _metric_values.get(key, null)
	var tile: Control = _metric_tiles.get(key, null)
	if tile != null:
		tile.visible = visible
	if value == null:
		return
	value.text = text_value
	value.add_theme_color_override("font_color", color)


func apply_evidence(result: Dictionary, contract: Dictionary) -> void:
	var mode := ResultTextScript.first_text([result.get("mode", ""),contract.get("mode", "")])
	var contract_name := ResultTextScript.first_text([contract.get("name", ""),contract.get("title", ""),result.get("contract_id", ""),contract.get("contract_id", "")])
	contract_name = String(ContractTitles.get(contract_name,contract_name))
	mode = {"Manual":"Manual", "Auto":"Auto"}.get(mode,mode)
	_route_context.text = " · ".join([contract_name,mode]) if not contract_name.is_empty() else mode
	_route_context.tooltip_text = "This Contract and Expedition Mode"
	_route_view.present(ResultTextScript.reported_route_steps(result))
	var total: Variant = ResultTextScript.reported_number(result,["room_count"])
	var completed: Variant = ResultTextScript.reported_number(result,["rooms_completed"])
	var valid := total != null and completed != null and is_finite(float(total)) and is_finite(float(completed))
	valid = valid and float(total) > 0 and float(completed) >= 0 and float(completed) <= float(total) and floorf(float(total)) == float(total) and floorf(float(completed)) == float(completed)
	_room_progress.visible = valid
	_room_progress_label.text = "Rooms Completed %s" % ResultTextScript.rooms_text(result) if valid else "Room completion progress was not fully recorded"
	if valid:
		_room_progress.max_value = float(total)
		_room_progress.value = float(completed)
		_room_progress.tooltip_text = "Completed rooms / total contract rooms only; not a build score"
	var observed: Array[String] = []
	for pair in [["elapsed","Time"],["kills","Kills"],["casts","Casts"]]:
		var reading := ResultTextScript.reading_text(pair[0],result)
		if not reading.is_empty(): observed.append("%s %s" % [pair[1],reading])
	_evidence_bodies.observed.text = "\n".join(observed) if not observed.is_empty() else "No combat readings available. Missing values are not counted as zero."
	_evidence_bodies.observed.tooltip_text = "Actual recorded time, kills, and casts for this run."
	_evidence_bodies.unverified.text = "This run settles combat and loot only.\nVisit Training for build growth conclusions."
	var diagnosis := ResultTextScript.defeat_diagnosis_text(result)
	var bottleneck := UiKit.as_dictionary(result.get("primary_bottleneck", {})) if not diagnosis.is_empty() else {}
	var title := String(bottleneck.get("title", "")).strip_edges()
	var action := String(bottleneck.get("action", "")).strip_edges()
	var failure_reason := ResultTextScript.first_text([result.get("failure_reason", "")])
	var source := ResultTextScript.failure_source_text(failure_reason) if not failure_reason.is_empty() else ResultTextScript.first_text([result.get("error", "")])
	_evidence_bodies.bottleneck.text = title if not title.is_empty() else "No clear combat bottleneck was found this run."
	if not source.is_empty() and title.is_empty():
		_evidence_bodies.bottleneck.text += "\nThis run ended before completion."
	_evidence_bodies.bottleneck.tooltip_text = diagnosis + "\n" + source + "\n" + ResultTextScript.defeat_report_text(result)
	_evidence_marks.bottleneck.set_warning(not title.is_empty())
	if not action.is_empty():
		_evidence_bodies.next.text = action
	elif String(result.get("outcome", "")) == "final_victory":
		_evidence_bodies.next.text = "This journey is complete.\nView the epilogue to look back."
	elif ResultTextScript.is_first_proxy_unlock(result, UiKit.as_dictionary(result.get("rewards", {}))):
		_evidence_bodies.next.text = "Four Common cores obtained.\nInstall them in town to send your proxy out."
	else:
		_evidence_bodies.next.text = "Return to Hearthside to sort equipment,\nor visit Training to keep studying your build."
	sync_metric_columns()

## The growth summary and the metric tiles. A metric the settlement reports -- 0
## included -- is drawn as it stands, and one it never carried keeps its tile
## hidden instead of appearing as a zero.
func apply_header(result: Dictionary, outcome: String) -> void:
	var growth: Dictionary = result.get("character_growth", {}) if result.get("character_growth") is Dictionary else {}
	_growth_label.visible = int(growth.get("experience_delta",0)) > 0
	_header_kicker.visible = not _growth_label.visible
	if _growth_label.visible:
		var level := "Lv.%d" % int(growth.get("level_after",1))
		if int(growth.get("level_before",1)) < int(growth.get("level_after",1)):
			level = "Lv.%d → %d" % [int(growth.level_before),int(growth.level_after)]
		_growth_label.text = "XP +%d   %s" % [int(growth.experience_delta),level]
		if int(growth.get("talent_points_delta",0)) > 0:
			_growth_label.text += "   Talent Points +%d" % int(growth.talent_points_delta)

	for metric_value in ResultTextScript.METRICS:
		var metric: Dictionary = metric_value
		var key := String(metric["key"])
		var reading := ResultTextScript.reading_text(key, result)
		set_metric(key, reading if not reading.is_empty() else "—", ResultTextScript.metric_color(key, outcome), not reading.is_empty())


## The folded battle copy behind the F10 accessors, then the visible evidence cards.
func apply_report(result: Dictionary, contract: Dictionary) -> void:
	diagnosis_label.text = ResultTextScript.defeat_diagnosis_text(result)
	report_label.text = ResultTextScript.defeat_report_text(result)
	run_facts_label.text = ResultTextScript.run_facts_text(result, contract)
	apply_evidence(result, contract)


func apply_headline(result: Dictionary, outcome: String, equipment_count: int, proxy_component_count: int) -> void:
	_subtitle_label.text = ResultTextScript.settlement_headline(result, outcome, equipment_count, proxy_component_count)
	_next_step_label.text = "Next Step · " + ResultTextScript.next_step_text(result, outcome, equipment_count, proxy_component_count)
