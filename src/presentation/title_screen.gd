class_name TitleScreen
extends Control
## A fixed ranger identity and a first step into the cold, over the published town art.

signal new_game_requested(initial_class: String)
signal continue_requested

const ShellThemeScript = preload("res://src/presentation/shell_theme.gd")
const TitleArtHelperScript = preload("res://src/presentation/title_art_helper.gd")
const PlayerFacingStatusScript = preload("res://src/presentation/player_facing_status.gd")

## Layout follows the approved standalone title sample: a slate veil with
## a single copper rail, then one 416px column of copy and actions.
const DESIGN_SIZE := Vector2(1280.0, 720.0)
## The produced plate keeps its left 40% (native 256px, 512px at 2x) as quiet dark
## ground for exactly this column, so the veil stops on that boundary and ends
## before the shared-hearth canopy starts at native x=270.
const VEIL_WIDTH := 512.0
const RAIL_WIDTH := 4.0
## One flat scrim, no gradient and no glow. The plate's left is already dark, so
## this only buys contrast for the copy; the right 768px - the half that carries
## the ruined tower and its hearth canopy - is never dimmed at all.
const VEIL_ALPHA := 0.45
const COLUMN_POSITION := Vector2(56.0, 74.0)
const COLUMN_WIDTH := 416.0
const CLASS_ID := "ranger"
const IDENTITY_TEXT := "游侠 · 持弓的流浪者"
const TITLE_TEXT := "MAKE IT BIG"
const PREMISE_TEXT := "寒原的旧路断了联系。
炉边镇靠旧塔过冬，门边渐冷。

带上弓，去旧路外段看看。"
const NEW_GAME_TEXT := "新游戏 · 踏入寒原"
const CONTINUE_TEXT := "继续旅程"
const KICKER_TEXT := "圣律之下 · 寒原"
const FOOTER_TEXT := "↑↓ / Enter 选择 · F1 设置"
## Chinese body copy keeps the approved 18-22px UI band; the wordmark is the one
## approved exception at 52px.
const KICKER_FONT_SIZE := 18
const BODY_FONT_SIZE := 22
const CONTROL_FONT_SIZE := 18
const ACTION_FONT_SIZE := 20
const TITLE_FONT_SIZE := 52

## The shared theme owns the palette and the packaged font; the title only picks
## from it, so the launch screen cannot drift away from the shell it belongs to.
const COOL_GREY := ShellThemeScript.NEUTRAL
const COPPER := ShellThemeScript.AMBER
const COPPER_DULL := ShellThemeScript.COPPER_DULL
const SLATE_DEEP := ShellThemeScript.INK

var _built := false
var _can_continue := false
var _status_message := ""
var _backdrop
var _new_game_button: Button
var _continue_button: Button
var _status_label: Label


func _ready() -> void:
	_build_ui()
	_apply_presentation()


func present(can_continue: bool, status_message: String = "") -> void:
	_can_continue = can_continue
	_status_message = status_message
	if _built:
		_apply_presentation()


func _build_ui() -> void:
	if _built:
		return
	_built = true
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = ShellThemeScript.create()

	var background := ColorRect.new()
	background.name = "SlateBackground"
	background.color = SLATE_DEEP
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	_backdrop = TitleArtHelperScript.new()
	_backdrop.name = "TitleBackdrop"
	add_child(_backdrop)
	_backdrop.load_default_assets()

	_add_menu_column()


func _add_menu_column() -> void:
	## One flat veil, one copper rail, one column: the copy reads over the art the
	## same way the approved sample and the base hub read over the ground field.
	var veil := ColorRect.new()
	veil.name = "MenuVeil"
	veil.color = Color(SLATE_DEEP, VEIL_ALPHA)
	veil.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	veil.offset_right = VEIL_WIDTH
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(veil)

	var rail := ColorRect.new()
	rail.name = "CopperRail"
	rail.color = COPPER_DULL
	rail.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	rail.offset_left = VEIL_WIDTH
	rail.offset_right = VEIL_WIDTH + RAIL_WIDTH
	rail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rail)

	var column := VBoxContainer.new()
	column.name = "TitleColumn"
	column.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	column.offset_left = COLUMN_POSITION.x
	column.offset_right = COLUMN_POSITION.x + COLUMN_WIDTH
	column.offset_top = COLUMN_POSITION.y
	column.offset_bottom = -32.0
	column.add_theme_constant_override("separation", 14)
	add_child(column)

	column.add_child(_label(KICKER_TEXT, KICKER_FONT_SIZE, COOL_GREY))
	var wordmark := _label(TITLE_TEXT, TITLE_FONT_SIZE, ShellThemeScript.BONE)
	wordmark.name = "Wordmark"
	column.add_child(wordmark)
	column.add_child(_copper_rule())
	var premise := _label(PREMISE_TEXT, BODY_FONT_SIZE, COOL_GREY)
	premise.name = "Premise"
	premise.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	premise.custom_minimum_size = Vector2(COLUMN_WIDTH, 64.0)
	column.add_child(premise)
	column.add_child(_spacer(10.0))
	var identity := _label(IDENTITY_TEXT, CONTROL_FONT_SIZE, ShellThemeScript.BONE)
	identity.name = "RangerIdentity"
	column.add_child(identity)

	_new_game_button = Button.new()
	_new_game_button.name = "NewGameButton"
	_new_game_button.text = NEW_GAME_TEXT
	_new_game_button.custom_minimum_size = Vector2(COLUMN_WIDTH, 52.0)
	_new_game_button.add_theme_font_size_override("font_size", ACTION_FONT_SIZE)
	## Only the primary action is emphasised; hover, pressed, focus and disabled all
	## stay the shared theme's own states.
	_new_game_button.add_theme_stylebox_override("normal", ShellThemeScript.panel_style("selected"))
	_new_game_button.pressed.connect(_on_new_game_pressed)
	column.add_child(_new_game_button)

	_continue_button = Button.new()
	_continue_button.name = "ContinueButton"
	_continue_button.text = CONTINUE_TEXT
	_continue_button.custom_minimum_size = Vector2(COLUMN_WIDTH, 48.0)
	_continue_button.add_theme_font_size_override("font_size", ACTION_FONT_SIZE)
	_continue_button.pressed.connect(_on_continue_pressed)
	column.add_child(_continue_button)

	column.add_child(_spacer(4.0))
	_status_label = _label("", CONTROL_FONT_SIZE, ShellThemeScript.WARNING)
	_status_label.name = "StatusLabel"
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.custom_minimum_size = Vector2(COLUMN_WIDTH, 44.0)
	column.add_child(_status_label)
	column.add_child(_spacer(4.0))
	var hint := _label(FOOTER_TEXT, KICKER_FONT_SIZE, COOL_GREY)
	hint.name = "KeyboardHintLabel"
	column.add_child(hint)


func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _copper_rule() -> ColorRect:
	var rule := ColorRect.new()
	rule.name = "CopperRule"
	rule.color = COPPER
	rule.custom_minimum_size = Vector2(COLUMN_WIDTH, 2.0)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rule


func _spacer(height: float) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(COLUMN_WIDTH, height)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return spacer


func _apply_presentation() -> void:
	_continue_button.disabled = not _can_continue
	_status_label.text = PlayerFacingStatusScript.message(_status_message)
	_status_label.visible = not _status_message.is_empty()
	_new_game_button.grab_focus()


func _on_new_game_pressed() -> void:
	new_game_requested.emit(CLASS_ID)


func _on_continue_pressed() -> void:
	continue_requested.emit()


func get_backdrop():
	## Harness and test access to the live backdrop without going through nodes.
	return _backdrop


func get_selected_class() -> String:
	return CLASS_ID
