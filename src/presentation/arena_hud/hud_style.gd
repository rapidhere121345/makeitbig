class_name ArenaHudStyle
extends RefCounted
## Palette, panel/progress/button styles and the label and card factories of
## the combat HUD, extracted from ArenaHud. The static functions are pure style
## builders; the instance methods create nodes that take the HUD's combat font
## from the host control (`ui_font`) and parent cards on it.

const PaletteScript = preload("res://src/presentation/combat_palette.gd")
const UiKit := preload("res://src/presentation/ui_kit.gd")

const COLOR_INK: Color = PaletteScript.INK
const COLOR_DEEP_BLUE: Color = PaletteScript.SLATE_0
const COLOR_GROUND: Color = PaletteScript.SLATE_1
const COLOR_NEUTRAL: Color = PaletteScript.SLATE_3
const COLOR_BONE: Color = PaletteScript.BONE
const COLOR_AMBER: Color = PaletteScript.COPPER
const COLOR_BLOOD: Color = PaletteScript.DANGER
const COLOR_WARNING: Color = PaletteScript.DANGER_BRIGHT
const COLOR_PROXY: Color = PaletteScript.COLD
## Combat HUD text uses the bundled sans face used for numbers and controls. The
## serif face remains appropriate for story and town copy, but its high contrast
## strokes become visually uneven at the compact 18-20px combat scale.
const HUD_TEXT_OUTLINE: Color = Color("10161c")
const HUD_TEXT_OUTLINE_SIZE := 1

var _host: Control


func _init(host: Control) -> void:
	_host = host


static func panel_style(vertical_margin: float = 9.0, opacity: float = 0.92) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(COLOR_DEEP_BLUE, opacity)
	style.border_color = Color("8e714a")
	style.set_border_width_all(1)
	style.border_width_top = 2
	style.set_corner_radius_all(0)
	style.shadow_color = Color(0.01,0.02,0.025,0.5)
	style.shadow_size = 3
	style.shadow_offset = Vector2(0,2)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = vertical_margin
	style.content_margin_bottom = vertical_margin
	return style


static func transparent_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	return style


static func style_progress(bar: ProgressBar, fill_color: Color) -> void:
	bar.add_theme_stylebox_override("background", UiKit.flat_style(COLOR_INK, COLOR_NEUTRAL, 1))
	bar.add_theme_stylebox_override("fill", UiKit.flat_style(fill_color, COLOR_BONE, 1))


static func style_action_button(button: Button, disabled: bool, tone: String) -> void:
	var accent := COLOR_WARNING if tone == "active" else (COLOR_AMBER if tone == "ready" else (COLOR_PROXY if tone == "locked" else (COLOR_BLOOD if tone == "cooldown" else PaletteScript.SLATE_2)))
	for state_name in ["normal", "hover", "pressed", "focus", "disabled"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(COLOR_GROUND, 0.94) if state_name == "normal" else (Color(PaletteScript.SLATE_2, 0.94) if state_name == "hover" else Color(COLOR_DEEP_BLUE, 0.96))
		if state_name == "pressed":
			style.bg_color = Color(accent, 0.32)
		if state_name == "disabled":
			style.bg_color = Color(PaletteScript.SLATE_0, 0.86)
		style.border_color = accent
		style.set_border_width_all(2 if tone in ["active", "ready", "locked", "cooldown"] else 1)
		style.set_corner_radius_all(3)
		button.add_theme_stylebox_override(state_name, style)


## Remove any previous rect before the ScrollContainer's VBox owns row layout.
static func summary_row(label: Label) -> Label:
	label.anchor_left = 0.0
	label.anchor_right = 0.0
	label.anchor_top = 0.0
	label.anchor_bottom = 0.0
	label.offset_left = 0.0
	label.offset_right = 0.0
	label.offset_top = 0.0
	label.offset_bottom = 0.0
	# Container width, not an unwrapped string's intrinsic minimum, owns the row.
	label.custom_minimum_size.x = 0.0
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.clip_text = false
	return label


static func place(parent: Control, control: Control, rect: Rect2, interactive: bool = false) -> void:
	control.anchor_left = 0.0
	control.anchor_right = 0.0
	control.anchor_top = 0.0
	control.anchor_bottom = 0.0
	# Explicit offsets on all four sides, because a container child that is re-parented
	# into the summary VBox must carry no stale minimum from its old strip rect.
	control.offset_left = rect.position.x
	control.offset_right = rect.position.x + rect.size.x
	control.offset_top = rect.position.y
	control.offset_bottom = rect.position.y + rect.size.y
	control.mouse_filter = Control.MOUSE_FILTER_STOP if interactive else Control.MOUSE_FILTER_IGNORE
	parent.add_child(control)


## Plain holder Control inside a panel: it carries no minimum size, so the panel
## height is exactly what the anchors/offsets say and never grows with content.
static func layout(node_name: String, panel: PanelContainer) -> Control:
	var holder := Control.new()
	holder.name = node_name
	holder.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.add_child(holder)
	return holder


## Measured fit: step the heading font down until the authored text fits its
## allotted width, so names never clip into unreadable fragments. 14px is the
## floor; clip_text stays as the last resort below that.
static func fit_heading(label: Label) -> void:
	var font := label.get_theme_font("font")
	var width := label.size.x
	var size := 18
	while size > 14 and font.get_string_size(label.text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width:
		size -= 2
	label.add_theme_font_size_override("font_size", size)


func card(node_name: String, top_left: Vector2, bottom_right: Vector2, anchor_x: float = 0.0, anchor_y: float = 0.0, anchor_x_end: float = -1.0, anchor_y_end: float = -1.0, vertical_margin: float = 9.0, opacity: float = 0.92) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = node_name
	card.anchor_left = anchor_x
	card.anchor_right = anchor_x if anchor_x_end < 0.0 else anchor_x_end
	card.anchor_top = anchor_y
	card.anchor_bottom = anchor_y if anchor_y_end < 0.0 else anchor_y_end
	card.offset_left = top_left.x
	card.offset_top = top_left.y
	card.offset_right = bottom_right.x
	card.offset_bottom = bottom_right.y
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	card.add_theme_stylebox_override("panel", panel_style(vertical_margin, opacity))
	_host.add_child(card)
	return card


func panel_in(node_name: String, parent: Control, rect: Rect2, vertical_margin: float, opacity: float) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = node_name
	panel.position = rect.position
	panel.size = rect.size
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.add_theme_stylebox_override("panel", panel_style(vertical_margin, opacity))
	parent.add_child(panel)
	return panel


func heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 18)
	apply_text_style(label, COLOR_BONE)
	return label


func muted_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	apply_text_style(label, COLOR_NEUTRAL)
	return label


func named_label(node_name: String) -> Label:
	var label := Label.new()
	label.name = node_name
	apply_text_style(label, COLOR_BONE)
	return label


func apply_text_style(label: Label, color: Color) -> void:
	## Keep fill, outline and face together so later labels cannot accidentally
	## inherit the serif shell font or a soft shadow that muddies small CJK glyphs.
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", HUD_TEXT_OUTLINE)
	label.add_theme_constant_override("outline_size", HUD_TEXT_OUTLINE_SIZE)
	label.add_theme_constant_override("shadow_offset_x", 0)
	label.add_theme_constant_override("shadow_offset_y", 0)
	if _host.ui_font != null:
		label.add_theme_font_override("font", _host.ui_font)
