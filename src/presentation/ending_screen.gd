class_name EndingScreen
extends Control
## Early-game graduation ending: the calm warm frame and the honest summary.
##
## Layout: one compact
## Chinese header, a body that is the only scrolling region, and a pinned footer
## holding both return actions. Nothing here scales Chinese copy under the approved
## 18px floor.
##
## Dedicated 640x360 layered return scene follows story panel 02's door/bench/
## coupling composition. It does NOT show E03's final repair or shift handover:
## Mira remains at work, Leia records, the empty bench stays away from the cold
## door. Existing fire/steam frames loop; character layers are declared static.
##
## Content contract: the graduation title, the completion copy, the profile and
## result summaries and the sealed midgame notice keep their canonical wording and
## their author/title place. Signals, node names and the summary format are
## unchanged; get_presented_profile() / get_presented_result() expose the payloads
## this screen was handed.

signal base_requested
signal title_requested

const ShellThemeScript = preload("res://src/presentation/shell_theme.gd")
const HearthReturnScript = preload("res://src/presentation/hearth_return_view.gd")

## The shell's one UI resolution; the project's canvas_items stretch keeps the same
## layout at 1600x900 and 1024x576.
const DESIGN_SIZE := Vector2(1280.0, 720.0)
const SCREEN_MARGIN := 24
const BLOCK_SEPARATION := 14

const TITLE_TEXT := "Looking Back at the Hearth"
const KICKER_TEXT := "A Pause in the Journey"
const COMPLETION_TEXT := "You have defeated the Threshold Colossus and brought your assembled proxy home safely. The hearth still burns, and the next road lies open."
const SUMMARY_HEADING := "Journey Record"
const MIDGAME_TEXT := "Unsolved Sacred Laws and harsher wilds await.\nReturn to the hub to sort your equipment, or take on more side contracts."
const BASE_BUTTON_TEXT := "Return to Hub"
const TITLE_BUTTON_TEXT := "Return to Title"

## The approved illustration and the place it shows, named exactly as the base hub
## names it. Drawn at native size: any other scale would resample the pixel grid.
const ILLUSTRATION_PATH := "res://art/production/p1/hearth_return_v01/background.png"
const ILLUSTRATION_SIZE := Vector2(640.0, 360.0)
const ILLUSTRATION_CAPTION := "Hamlet · Hearthside"

const TITLE_FONT_SIZE := 28
const SMALL_FONT_SIZE := 18
## The summary sits beside the illustration on the shell's 1280px canvas, where the
## native 640px plate leaves room for the real numbers without a scroll; below this
## the two blocks stack and the body scrolls, so a small view never hides them.
const WIDE_MIN_WIDTH := 1080.0

## Known display names. A value outside these tables keeps its authoritative id: the
## screen translates what it can name and never invents a friendlier one.
const CLASS_LABELS := {"ranger": "Ranger", "alchemist": "Alchemist", "mage": "Mage"}
const CONTRACT_LABELS := {"auto_certification": "Early Graduation Contract", "threshold_colossus": "Threshold Colossus"}
const OUTCOME_LABELS := {"final_victory": "Final Victory", "victory": "Victory", "defeat": "Failure", "abandoned": "Aborted"}

var _built := false
var _profile: Dictionary = {}
var _last_result: Dictionary = {}
var _illustration: TextureRect
var _illustration_frame: PanelContainer
var _profile_label: Label
var _result_label: Label
var _body_row: BoxContainer


var _primary_action: Button


func _ready() -> void:
	_build_ui()
	_apply_presentation()


func present(profile: Dictionary, last_result: Dictionary = {}) -> void:
	_profile = profile.duplicate(true)
	_last_result = last_result.duplicate(true)
	if _built:
		_apply_presentation()


func _build_ui() -> void:
	if _built:
		return
	_built = true
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = ShellThemeScript.create()

	ShellThemeScript.add_backdrop(self, "ending_screen")

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, SCREEN_MARGIN)
	add_child(margin)

	var root := VBoxContainer.new()
	root.name = "EndingRoot"
	root.add_theme_constant_override("separation", BLOCK_SEPARATION)
	margin.add_child(root)

	_build_header(root)
	_build_body(root)
	_build_footer(root)


func _build_header(root: Control) -> void:
	var header := VBoxContainer.new()
	header.name = "EndingHeader"
	header.add_theme_constant_override("separation", 6)
	root.add_child(header)

	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 16)
	header.add_child(title_row)
	var title := Label.new()
	title.name = "EndingTitle"
	title.text = TITLE_TEXT
	title.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	title.add_theme_color_override("font_color", ShellThemeScript.BONE)
	title_row.add_child(title)
	var kicker := Label.new()
	kicker.name = "EndingKicker"
	kicker.text = KICKER_TEXT
	kicker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	kicker.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	kicker.add_theme_font_size_override("font_size", SMALL_FONT_SIZE)
	kicker.add_theme_color_override("font_color", ShellThemeScript.NEUTRAL)
	title_row.add_child(kicker)

	var ending_copy := Label.new()
	ending_copy.name = "EndingCopy"
	ending_copy.text = COMPLETION_TEXT
	ending_copy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.add_child(ending_copy)

	var rule := ColorRect.new()
	rule.name = "HeaderRule"
	rule.color = ShellThemeScript.COPPER_DULL
	rule.custom_minimum_size = Vector2(0.0, 2.0)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(rule)


func _build_body(root: Control) -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "EndingScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ShellThemeScript.hide_passive_scrollbar_chrome(scroll)
	root.add_child(scroll)

	var content := VBoxContainer.new()
	content.name = "EndingContent"
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", BLOCK_SEPARATION)
	scroll.add_child(content)

	## Illustration and summary share one row while the canvas is wide enough; the
	## single `vertical` switch stacks them on a smaller view instead of squeezing the
	## plate or pushing the numbers out of the first screenful.
	_body_row = BoxContainer.new()
	_body_row.name = "EndingBodyRow"
	_body_row.add_theme_constant_override("separation", BLOCK_SEPARATION)
	content.add_child(_body_row)
	_build_illustration(_body_row)

	var summary_column := VBoxContainer.new()
	summary_column.name = "EndingSummaryColumn"
	summary_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary_column.add_theme_constant_override("separation", BLOCK_SEPARATION)
	_body_row.add_child(summary_column)
	_build_summary(summary_column)
	_build_midgame_panel(summary_column)
	_sync_orientation()
	resized.connect(_sync_orientation)
## One explicit breakpoint, not an adaptive framework: side by side on the shell
## canvas, stacked when the view is too narrow for the native plate plus the numbers.
func _sync_orientation() -> void:
	if _body_row == null:
		return
	_body_row.vertical = size.x < WIDE_MIN_WIDTH


func _build_illustration(parent: Control) -> void:
	## One framed place illustration, built only when the approved plate loads.
	if not ResourceLoader.exists(ILLUSTRATION_PATH):
		return
	var resource: Variant = ResourceLoader.load(ILLUSTRATION_PATH)
	if not (resource is Texture2D):
		return
	_illustration_frame = PanelContainer.new()
	_illustration_frame.name = "EndingIllustrationFrame"
	## Bright copper on the cold ink: the warm edge of the ending, still one thin
	## hard border with no radius, gradient or glow.
	_illustration_frame.add_theme_stylebox_override("panel", _frame(ShellThemeScript.INK, ShellThemeScript.AMBER, 2))
	_illustration_frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	parent.add_child(_illustration_frame)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	_illustration_frame.add_child(column)
	_illustration = HearthReturnScript.new()
	_illustration.name = "EndingIllustration"
	_illustration.texture = resource as Texture2D
	_illustration.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_illustration.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_illustration.stretch_mode = TextureRect.STRETCH_SCALE
	_illustration.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_illustration.custom_minimum_size = ILLUSTRATION_SIZE
	_illustration.set_meta("source_path", ILLUSTRATION_PATH)
	column.add_child(_illustration)
	var caption := Label.new()
	caption.name = "EndingIllustrationCaption"
	caption.text = ILLUSTRATION_CAPTION
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size", SMALL_FONT_SIZE)
	caption.add_theme_color_override("font_color", ShellThemeScript.NEUTRAL)
	column.add_child(caption)
	var story_boundary := Label.new()
	story_boundary.name = "ReturnStoryBoundary"
	story_boundary.text = "The wind is still cold, and the connections need tending. Rest by the hearth for a while."
	story_boundary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	story_boundary.add_theme_font_size_override("font_size", SMALL_FONT_SIZE)
	story_boundary.add_theme_color_override("font_color", ShellThemeScript.NEUTRAL)
	column.add_child(story_boundary)


func _build_summary(parent: Control) -> void:
	var panel := PanelContainer.new()
	panel.name = "EndingSummaryPanel"
	parent.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)
	var heading := Label.new()
	heading.name = "EndingSummaryHeading"
	heading.text = SUMMARY_HEADING
	heading.add_theme_font_size_override("font_size", ShellThemeScript.BODY_FONT_SIZE)
	column.add_child(heading)
	_profile_label = Label.new()
	_profile_label.name = "EndingProfileSummary"
	_profile_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_profile_label)
	_result_label = Label.new()
	_result_label.name = "EndingResultSummary"
	_result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result_label.add_theme_color_override("font_color", ShellThemeScript.PROXY)
	column.add_child(_result_label)


func _build_midgame_panel(parent: Control) -> void:
	## The sealed midgame notice keeps its own framed block: deferred systems stay
	## named as deferred instead of becoming promises.
	var panel := PanelContainer.new()
	panel.name = "MidgamePanel"
	parent.add_child(panel)
	var preview := Label.new()
	preview.name = "MidgamePreview"
	preview.text = MIDGAME_TEXT
	preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(preview)


func _build_footer(root: Control) -> void:
	var footer := HBoxContainer.new()
	footer.name = "EndingFooter"
	footer.add_theme_constant_override("separation", 12)
	root.add_child(footer)
	var base_button := Button.new()
	base_button.name = "ReturnToBaseButton"
	base_button.text = BASE_BUTTON_TEXT
	base_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	base_button.pressed.connect(_on_base_pressed)
	footer.add_child(base_button)
	_primary_action = base_button
	var title_button := Button.new()
	title_button.name = "ReturnToTitleButton"
	title_button.text = TITLE_BUTTON_TEXT
	title_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_button.pressed.connect(_on_title_pressed)
	footer.add_child(title_button)


## Keyboard entry: the primary ending action owns initial focus when the screen
## first has none. Ordinary present() refreshes never steal focus the player
## already navigated elsewhere.
func _seed_initial_focus() -> void:
	if not is_inside_tree() or get_viewport().gui_get_focus_owner() != null:
		return
	if _primary_action != null and _primary_action.is_visible_in_tree():
		_primary_action.grab_focus()

func _apply_presentation() -> void:
	var progression := _as_dictionary(_profile.get("progression", {}))
	var initial_class := String(_profile.get("initial_class", "Not Created"))
	_profile_label.text = "Class: %s    Contract wins: %d    Proxy wins: %d" % [
		String(CLASS_LABELS.get(initial_class.to_lower(), initial_class)),
		int(progression.get("contract_wins", 0)),
		int(progression.get("auto_contract_wins", 0)),
	]
	_seed_initial_focus()
	var outcome := String(_last_result.get("outcome", "final_victory"))
	var contract_id := String(_last_result.get("contract_id", "auto_certification"))
	var mode := String(_last_result.get("mode", "Auto"))
	var elapsed := float(_last_result.get("elapsed_seconds", _last_result.get("time", 0.0)))
	var rewards := _as_dictionary(_last_result.get("rewards", {}))
	var equipment_count := int(rewards.get("equipment_drop_count", 0))
	_result_label.text = "Contract: %s (%s)    Result: %s\nTime: %.2f s    Equipment gained: %d" % [
		String(CONTRACT_LABELS.get(contract_id, contract_id)),
		"Proxy Expedition" if mode == "Auto" else "Manual Expedition",
		String(OUTCOME_LABELS.get(outcome.to_lower(), outcome.to_upper())),
		elapsed,
		equipment_count,
	]


func _as_dictionary(value: Variant) -> Dictionary:
	return value as Dictionary if value is Dictionary else {}


func _frame(fill: Color, border: Color, width: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(width)
	box.set_corner_radius_all(0)
	box.content_margin_left = 12.0
	box.content_margin_top = 12.0
	box.content_margin_right = 12.0
	box.content_margin_bottom = 12.0
	return box


## ---- public surface used by the router, the harness and the tests ----


## The framed illustration currently drawn, or null when the approved plate could
## not be read and the ending therefore keeps its text alone.
func get_illustration() -> TextureRect:
	return _illustration


func get_illustration_source_path() -> String:
	return String(_illustration.get_meta("source_path", "")) if _illustration != null else ""


func get_presented_profile() -> Dictionary:
	return _profile.duplicate(true)


func get_presented_result() -> Dictionary:
	return _last_result.duplicate(true)


func _on_base_pressed() -> void:
	base_requested.emit()


func _on_title_pressed() -> void:
	title_requested.emit()
