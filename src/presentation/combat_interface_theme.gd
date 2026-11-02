extends RefCounted

## Theme shared by the combat HUD controls (Label and Button chrome in the
## combat palette). Combat rooms build it once and hand it to the HUD.

const PaletteScript := preload("res://src/presentation/combat_palette.gd")
const ShellThemeScript := preload("res://src/presentation/shell_theme.gd")
const UiKit := preload("res://src/presentation/ui_kit.gd")
const SharedPalette := preload("res://src/presentation/palette.gd")


static func create() -> Theme:
	var theme := Theme.new()
	var ui_font: FontFile = ShellThemeScript.ui_font()
	if ui_font != null:
		theme.default_font = ui_font
	theme.set_color("font_color", "Label", PaletteScript.BONE)
	theme.set_color("font_shadow_color", "Label", PaletteScript.INK)
	theme.set_constant("shadow_offset_x", "Label", 1)
	theme.set_constant("shadow_offset_y", "Label", 1)
	theme.set_color("font_color", "Button", PaletteScript.BONE)
	theme.set_color("font_hover_color", "Button", PaletteScript.BONE)
	theme.set_color("font_pressed_color", "Button", PaletteScript.BONE)
	theme.set_color("font_disabled_color", "Button", PaletteScript.SLATE_3)
	theme.set_color("font_focus_color", "Button", PaletteScript.BONE)
	theme.set_stylebox("normal", "Button", _button_style(SharedPalette.BUTTON_NORMAL, SharedPalette.BRONZE_EDGE, 0))
	theme.set_stylebox("hover", "Button", _button_style(SharedPalette.BUTTON_HOVER, PaletteScript.COPPER, 0))
	theme.set_stylebox("pressed", "Button", _button_style(SharedPalette.BUTTON_PRESSED, PaletteScript.COPPER, 0))
	theme.set_stylebox("disabled", "Button", _button_style(SharedPalette.BUTTON_DISABLED, SharedPalette.BRONZE_EDGE, 0))
	theme.set_stylebox("focus", "Button", _button_style(Color.TRANSPARENT, PaletteScript.COPPER, 2))
	return theme


static func _button_style(background: Color, border: Color, border_width: int) -> StyleBoxFlat:
	var style := UiKit.flat_style(background, border, border_width, 0, Vector4(10.0, 7.0, 10.0, 7.0))
	if border_width == 0:
		style.border_width_bottom = 1
	return style
