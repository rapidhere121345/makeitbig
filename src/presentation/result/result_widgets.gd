class_name ResultWidgets
extends RefCounted
## Layout tokens and small widget builders shared by the ResultScreen and its
## header/report and loot collaborators. Everything here is static and holds
## no state.

const ShellThemeScript = preload("res://src/presentation/shell_theme.gd")
const FacilityArtScript = preload("res://src/presentation/facility_art.gd")
const UiKit := preload("res://src/presentation/ui_kit.gd")

const BLOCK_SEPARATION := 14

## Header and value steps of the approved UI band: 28px Chinese title, 18px
## neutral subtitle and small copy, 28px metric values.
const TITLE_FONT_SIZE := 28
const SUBTITLE_FONT_SIZE := 18
const METRIC_LABEL_FONT_SIZE := 18
const METRIC_VALUE_FONT_SIZE := 24
const METRIC_COLUMNS := 3
const SECONDARY_FONT_SIZE := 18


static func heading(text_value: String) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", ShellThemeScript.BODY_FONT_SIZE)
	label.add_theme_color_override("font_color", ShellThemeScript.BONE)
	return label


static func rule() -> ColorRect:
	var rule_rect := ColorRect.new()
	rule_rect.name = "HeaderRule"
	rule_rect.color = ShellThemeScript.COPPER_DULL
	rule_rect.custom_minimum_size = Vector2(0.0, 2.0)
	rule_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rule_rect


static func report_note(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 18)
	return label


static func frame(_fill: Color, _border: Color, width: int) -> StyleBox:
	var box := ShellThemeScript.panel_style("selected" if width > 1 else "panel")
	box.content_margin_left = 14.0
	box.content_margin_top = 10.0
	box.content_margin_right = 14.0
	box.content_margin_bottom = 10.0
	return box


static func place_section(section: Control, top_anchor: float, bottom_anchor: float, top_offset: float, bottom_offset: float) -> void:
	section.set_anchor(SIDE_LEFT, 0.0)
	section.set_anchor(SIDE_RIGHT, 1.0)
	section.set_anchor(SIDE_TOP, top_anchor)
	section.set_anchor(SIDE_BOTTOM, bottom_anchor)
	section.offset_left = 0.0
	section.offset_right = 0.0
	section.offset_top = top_offset
	section.offset_bottom = bottom_offset


static func set_button_primary(button: Button, primary: bool) -> void:
	if primary:
		button.add_theme_stylebox_override("normal", ShellThemeScript.panel_style("selected"))
	else:
		button.remove_theme_stylebox_override("normal")


## One published 32x32 cell. The default is the batch's single allowed display step
## (2x, so 64 pixels and no resampling); `native` keeps the cell at its own 32px
## size, which only the slot badge uses.
static func icon_node(texture: Texture2D, scaled: bool = true) -> TextureRect:
	var display_size := Vector2(FacilityArtScript.ICON_NATIVE_SIZE)
	if scaled:
		display_size *= FacilityArtScript.ICON_DISPLAY_SCALE
	return UiKit.icon_node(texture, display_size, scaled, TextureRect.STRETCH_SCALE)
