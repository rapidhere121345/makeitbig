extends RefCounted

## Theme shared by the combat HUD controls (Label and Button chrome in the
## combat palette). Combat rooms build it once and hand it to the HUD.

const PaletteScript := preload("res://src/presentation/combat_palette.gd")
const ShellThemeScript := preload("res://src/presentation/shell_theme.gd")
const COLOR_INK: Color = PaletteScript.INK
const COLOR_DEEP_BLUE: Color = PaletteScript.SLATE_0
const COLOR_GROUND: Color = PaletteScript.SLATE_1
const COLOR_NEUTRAL: Color = PaletteScript.SLATE_3
const COLOR_BONE: Color = PaletteScript.BONE
const COLOR_AMBER: Color = PaletteScript.COPPER


static func create() -> Theme:
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


static func _button_style(background: Color, border: Color, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 7.0
	style.content_margin_bottom = 7.0
	return style
