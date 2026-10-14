class_name CombatLabView
extends CanvasLayer

## Standalone diagnostic shell. Owns widgets/theme; emits intent signals and
## consumes catalog/status values. It never receives the Main node.
signal preset_requested(preset: String)
signal mode_requested(mode: String)
signal deploy_requested
signal forge_requested(choice: int)

const PaletteScript := preload("res://src/presentation/combat_palette.gd")
const ShellThemeScript := preload("res://src/presentation/shell_theme.gd")
const FATE_SEED := 52969
const COLOR_INK: Color = PaletteScript.INK
const COLOR_DEEP_BLUE: Color = PaletteScript.SLATE_0
const COLOR_GROUND: Color = PaletteScript.SLATE_1
const COLOR_NEUTRAL: Color = PaletteScript.SLATE_3
const COLOR_BONE: Color = PaletteScript.BONE
const COLOR_AMBER: Color = PaletteScript.COPPER
const COLOR_BLOOD: Color = PaletteScript.DANGER
const COLOR_WARNING: Color = PaletteScript.DANGER_BRIGHT
const COLOR_PROXY: Color = PaletteScript.COLD
const COLOR_ANOMALY: Color = PaletteScript.PURPLE
const FORGE_FAMILY_LABELS: Dictionary = {
	"growth_probability": "Growth Probability / 生长概率",
	"shared_lifetime": "Shared Lifetime / 共享寿命",
	"branch_count": "Branch Count / 分支数",
	"payload": "Payload / 载荷",
	"flight_speed": "Flight Speed / 飞行速度",
	"turn_time": "Turn Time / 转向时间",
}
const FORGE_FAMILY_SHORT: Dictionary = {
	"growth_probability": "Growth P",
	"shared_lifetime": "Lifetime",
	"branch_count": "Branches",
	"payload": "Payload",
	"flight_speed": "Speed",
	"turn_time": "Turn Time",
}

var interface_theme: Theme
var catalog: Dictionary = {}
var base_panel: VBoxContainer
var systems_panel: VBoxContainer
var content_status_label: Label
var progress_label: Label
var proxy_status_label: Label
var forge_status_label: Label
var preset_buttons: Dictionary = {}
var mode_buttons: Dictionary = {}
var forge_buttons: Array[Button] = []


func show_base(enabled: bool) -> void:
	base_panel.visible = enabled
	systems_panel.visible = enabled


func hide_base() -> void:
	show_base(false)


func select_build(preset: String, mode: String) -> void:
	for key: String in preset_buttons:
		(preset_buttons[key] as Button).button_pressed = key == preset
	for key: String in mode_buttons:
		(mode_buttons[key] as Button).button_pressed = key == mode


func _request_preset(preset: String) -> void:
	preset_requested.emit(preset)


func _request_mode(mode: String) -> void:
	mode_requested.emit(mode)


func _request_deploy() -> void:
	deploy_requested.emit()


func _request_forge(choice: int) -> void:
	forge_requested.emit(choice)


func build(catalog_value: Dictionary) -> void:
	catalog = catalog_value.duplicate(true)
	var layer: CanvasLayer = self
	interface_theme = _build_interface_theme()
	base_panel = VBoxContainer.new()
	base_panel.theme = interface_theme
	base_panel.position = Vector2(64.0, 54.0)
	base_panel.custom_minimum_size = Vector2(510.0, 0.0)
	layer.add_child(base_panel)
	var title := Label.new()
	title.text = "RANGER // PIERCING ARROW LAB"
	title.add_theme_font_size_override("font_size", 28)
	base_panel.add_child(title)
	var intro := Label.new()
	var preset_values: Array[String] = []
	for preset_id in catalog.preset_order:
		preset_values.append("%.2f" % float(catalog.presets[preset_id].p))
	intro.text = "Base p=.25. Diagnostic IVs come from validated content:\n%s; equipped parameters yield g=80.\nChoose a growth preset and pilot; configuration locks on deployment." % " / ".join(preset_values)
	base_panel.add_child(intro)
	base_panel.add_child(_section_label("GROWTH PRESET"))
	var preset_row := HBoxContainer.new()
	base_panel.add_child(preset_row)
	for preset: String in catalog.preset_order:
		var button := Button.new()
		var preset_data: Dictionary = catalog.presets[preset]
		var p_value := float(preset_data.p)
		var iv_note: String = "R<1" if p_value < 0.5 else ("R=1" if is_equal_approx(p_value, 0.5) else "R>1")
		button.text = "%s / %s\np=%.2f • %s" % [preset.capitalize(), String(preset_data.name), p_value, iv_note]
		button.tooltip_text = "Loaded from ranger_presets.json"
		button.toggle_mode = true
		button.pressed.connect(_request_preset.bind(preset))
		preset_row.add_child(button)
		preset_buttons[preset] = button
	base_panel.add_child(_section_label("PILOT"))
	var mode_row := HBoxContainer.new()
	base_panel.add_child(mode_row)
	for mode: String in ["Manual", "Auto"]:
		var button := Button.new()
		button.text = mode
		button.toggle_mode = true
		button.pressed.connect(_request_mode.bind(mode))
		mode_row.add_child(button)
		mode_buttons[mode] = button
	var controls := Label.new()
	controls.text = "Manual: WASD move • Space / LMB Skill 1 • Q Hunter Mark • E Dash • Shift / Ctrl / RMB dodge\nAuto: nearest target • approach range • Skill 1 only"
	base_panel.add_child(controls)
	var start_button := Button.new()
	start_button.text = "DEPLOY"
	start_button.custom_minimum_size = Vector2(0.0, 48.0)
	start_button.pressed.connect(_request_deploy)
	base_panel.add_child(start_button)

	systems_panel = VBoxContainer.new()
	systems_panel.theme = interface_theme
	systems_panel.position = Vector2(650.0, 54.0)
	systems_panel.custom_minimum_size = Vector2(580.0, 0.0)
	layer.add_child(systems_panel)
	var systems_title := Label.new()
	systems_title.text = "CONTRACT SYSTEMS // LIVE"
	systems_title.add_theme_font_size_override("font_size", 24)
	systems_panel.add_child(systems_title)
	content_status_label = Label.new()
	content_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content_status_label.custom_minimum_size = Vector2(570.0, 0.0)
	systems_panel.add_child(content_status_label)
	systems_panel.add_child(_section_label("WHITE PROXY LOADOUT"))
	proxy_status_label = Label.new()
	proxy_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	proxy_status_label.custom_minimum_size = Vector2(570.0, 0.0)
	systems_panel.add_child(proxy_status_label)
	systems_panel.add_child(_section_label("LAW FORGE // INSCRIPTION TRACK"))
	forge_status_label = Label.new()
	forge_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	forge_status_label.custom_minimum_size = Vector2(570.0, 0.0)
	systems_panel.add_child(forge_status_label)
	var forge_row := HBoxContainer.new()
	systems_panel.add_child(forge_row)
	for choice_number in range(1, 4):
		var forge_button := Button.new()
		forge_button.custom_minimum_size = Vector2(185.0, 58.0)
		forge_button.pressed.connect(_request_forge.bind(choice_number))
		forge_row.add_child(forge_button)
		forge_buttons.append(forge_button)
	systems_panel.add_child(_section_label("PERSISTENT CONTRACT RECORD"))
	progress_label = Label.new()
	progress_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	progress_label.custom_minimum_size = Vector2(570.0, 0.0)
	systems_panel.add_child(progress_label)
	var reward_note := Label.new()
	reward_note.text = "Manual Hunter Cache: deterministic 35% chance for +1 extra Inscription Tally.\nAuto and Manual never run simultaneously. Closing the game grants nothing."
	reward_note.add_theme_color_override("font_color", COLOR_ANOMALY)
	systems_panel.add_child(reward_note)

func _build_interface_theme() -> Theme:
	var theme := Theme.new()
	var ui_font: FontFile = ShellThemeScript.ui_font()
	if ui_font != null:
		theme.default_font = ui_font
	theme.set_color("font_color", "Label", COLOR_BONE)
	theme.set_color("font_shadow_color", "Label", COLOR_INK)
	theme.set_constant("shadow_offset_x", "Label", 1)
	theme.set_constant("shadow_offset_y", "Label", 1)
	theme.set_color("font_color", "Button", COLOR_BONE)
	theme.set_color("font_hover_color", "Button", COLOR_BONE)
	theme.set_color("font_pressed_color", "Button", COLOR_INK)
	theme.set_color("font_disabled_color", "Button", COLOR_NEUTRAL)
	theme.set_color("font_focus_color", "Button", COLOR_BONE)
	theme.set_stylebox("normal", "Button", _button_style(COLOR_DEEP_BLUE, COLOR_NEUTRAL, 1))
	theme.set_stylebox("hover", "Button", _button_style(COLOR_GROUND, COLOR_BONE, 2))
	theme.set_stylebox("pressed", "Button", _button_style(COLOR_AMBER, COLOR_BONE, 2))
	theme.set_stylebox("disabled", "Button", _button_style(COLOR_GROUND, COLOR_NEUTRAL, 2))
	theme.set_stylebox("focus", "Button", _button_style(Color.TRANSPARENT, COLOR_AMBER, 2))
	return theme


func _button_style(background: Color, border: Color, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 7.0
	style.content_margin_bottom = 7.0
	return style


func _section_label(text: String) -> Label:
	var label := Label.new()
	label.text = "\n%s" % text
	label.add_theme_color_override("font_color", COLOR_PROXY)
	return label


func present_status(snapshot: Dictionary) -> void:
	if systems_panel == null:
		return
	if snapshot["startup_errors"].is_empty():
		content_status_label.text = "CONTENT OK  •  16 cores  •  10 attachments  •  16 firmware  •  schema v1"
		content_status_label.add_theme_color_override("font_color", COLOR_PROXY)
	else:
		content_status_label.text = "CONTENT BLOCKED: %s" % "; ".join(snapshot["startup_errors"])
		content_status_label.add_theme_color_override("font_color", COLOR_WARNING)
	var white_names: Array[String] = []
	for id in ["near_enemy_horizon", "direct_gait", "single_key_execution", "short_trace_memory"]:
		if catalog.cores.has(id):
			white_names.append(String(catalog.cores[id].name))
	proxy_status_label.text = "%s\nPrediction: %s. Auto may target nearest enemy and press Skill 1 only." % [" + ".join(white_names), snapshot["proxy_prediction"].to_upper()]
	var active_slot: int = int(snapshot["active_slot"])
	var dice: int = int(snapshot["dice"])
	var equipped: Array[String] = []
	for affix in snapshot["affixes"]:
		if affix.is_empty():
			equipped.append("—")
		else:
			equipped.append("%s T%d" % [_forge_family_name(String(affix.family)), int(affix.tier)])
	forge_status_label.text = "Sacred-law seed %d is fixed. Future #n costs n Inscription Tallies when confirmed.\nInscription Tallies: %d  •  slots: %s" % [FATE_SEED, dice, " | ".join(equipped)]
	var candidates: Array[Dictionary] = snapshot["candidates"]
	for index in forge_buttons.size():
		var button: Button = forge_buttons[index]
		if index < candidates.size():
			var candidate: Dictionary = candidates[index]
			button.text = "#%d / COST %d\n%s T%d" % [index + 1, int(candidate.cost), String(FORGE_FAMILY_SHORT.get(String(candidate.family), candidate.family)), int(candidate.tier)]
			button.disabled = snapshot["in_arena"] or not snapshot["startup_errors"].is_empty()
		else:
			button.text = "#%d\nLOCKED" % (index + 1)
			button.disabled = true
	progress_label.text = "Victories: %d  •  Last drop: %s\n%s" % [snapshot["contract_wins"], snapshot["last_drop"], snapshot["last_save_message"]]


func _forge_family_name(family: String) -> String:
	return String(FORGE_FAMILY_LABELS.get(family, family))
