class_name ArenaHudInterface
extends RefCounted
## The combat HUD's node tree, extracted from ArenaHud: the three top cards,
## the elite-mechanic cue, the openable summary panel, the action dock and the
## transient input-notice strip. The builder assigns every widget the HUD later
## writes to onto the HUD itself (untyped back-reference), so the HUD keeps its
## named nodes and fields.

const ShellThemeScript = preload("res://src/presentation/shell_theme.gd")
const StyleScript = preload("res://src/presentation/arena_hud/hud_style.gd")
const CellsScript = preload("res://src/presentation/arena_hud/hud_skill_cells.gd")

const TOP_BAR_HEIGHT: float = 86.0
const TOP_PANEL_HEIGHT: float = 76.0
const HERO_FRAME_RECT := Rect2(0.0, 0.0, 300.0, TOP_PANEL_HEIGHT)
const BOSS_FRAME_RECT := Rect2(392.0, 0.0, 480.0, TOP_PANEL_HEIGHT)
const UTILITY_FRAME_RECT := Rect2(1016.0, 0.0, 248.0, TOP_PANEL_HEIGHT)
const ACTION_BAR_WIDTH: float = 444.0
const ACTION_BAR_HEIGHT: float = 104.0
const ACTION_BAR_CONTENT_WIDTH: float = 436.0
## Expanded summary panel. It hangs below the 90px strip and stops 136 logical
## pixels above the frame bottom, so it never covers the action bar, the four skill
## inputs or the top strip at any UI scale.
const SUMMARY_PANEL_X: float = 904.0
const SUMMARY_PANEL_WIDTH: float = 368.0
const SUMMARY_PANEL_TOP: float = 96.0
const SUMMARY_PANEL_BOTTOM: float = 520.0

var _hud
var _style: StyleScript


func _init(hud, style: StyleScript) -> void:
	_hud = hud
	_style = style


func build() -> void:
	if not _hud.icons.load_icons():
		_hud.icon_pending_reason = String(_hud.icons.pending_reason)
	## Combat is a read-and-react surface: use the medium sans face for stable
	## Chinese glyph fill, numeric widths and key labels. Story screens keep the
	## serif shell font through ShellTheme.create().
	_hud.ui_font = ShellThemeScript.data_font()
	if _hud.ui_font != null:
		var own_theme := Theme.new()
		own_theme.default_font = _hud.ui_font
		own_theme.default_font_size = ShellThemeScript.MIN_FONT_SIZE
		own_theme.set_color("font_color", "Label", StyleScript.COLOR_BONE)
		own_theme.set_color("font_outline_color", "Label", StyleScript.HUD_TEXT_OUTLINE)
		own_theme.set_constant("outline_size", "Label", StyleScript.HUD_TEXT_OUTLINE_SIZE)
		own_theme.set_color("font_color", "Button", StyleScript.COLOR_BONE)
		own_theme.set_color("font_outline_color", "Button", StyleScript.HUD_TEXT_OUTLINE)
		own_theme.set_constant("outline_size", "Button", StyleScript.HUD_TEXT_OUTLINE_SIZE)
		_hud.theme = own_theme

	# TopBar remains the stable full-width carrier, but has no visible backing. The
	# three cards inside it are the only opaque top surfaces and leave world-visible gaps.
	var top_bar := _style.card("TopBar", Vector2(8.0, 6.0), Vector2(-8.0, 6.0 + TOP_BAR_HEIGHT), 0.0, 0.0, 1.0, 0.0, 0.0, 0.0)
	top_bar.add_theme_stylebox_override("panel", StyleScript.transparent_panel_style())
	var top_layout := StyleScript.layout("TopBarLayout", top_bar)
	_hud._hero_frame = _style.panel_in("HeroFrame", top_layout, HERO_FRAME_RECT, 5.0, 0.90)
	_hud._boss_frame = _style.panel_in("BossFrame", top_layout, BOSS_FRAME_RECT, 5.0, 0.90)
	_hud._utility_frame = _style.panel_in("UtilityFrame", top_layout, UTILITY_FRAME_RECT, 5.0, 0.90)
	var hero_layout := StyleScript.layout("HeroFrameLayout", _hud._hero_frame)
	var boss_layout := StyleScript.layout("BossFrameLayout", _hud._boss_frame)
	var utility_layout := StyleScript.layout("UtilityFrameLayout", _hud._utility_frame)
	# A compact read-only cue sits below the target card, clear of the hero,
	# room heading, summary and skill dock at both supported viewport widths.
	_hud._elite_mechanic_frame = _style.card("EliteMechanicFrame", Vector2(400.0, 96.0), Vector2(880.0, 138.0), 0.0, 0.0, -1.0, -1.0, 4.0, 0.90)
	_hud._elite_mechanic_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud._elite_mechanic_frame.visible = false
	_hud._elite_mechanic_label = _style.named_label("EliteMechanicLabel")
	_hud._elite_mechanic_label.add_theme_font_size_override("font_size", 18)
	_hud._elite_mechanic_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud._elite_mechanic_frame.add_child(_hud._elite_mechanic_label)
	_hud._hero_health_label = _style.named_label("HeroHealthLabel")
	_hud._hero_health_label.add_theme_font_size_override("font_size", 20)
	_hud._hero_health_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	StyleScript.place(hero_layout, _hud._hero_health_label, Rect2(0.0, 0.0, 276.0, 21.0))
	_hud._hero_health_bar = ProgressBar.new()
	_hud._hero_health_bar.name = "HeroHealthBar"
	_hud._hero_health_bar.show_percentage = false
	StyleScript.style_progress(_hud._hero_health_bar, StyleScript.COLOR_BONE)
	StyleScript.place(hero_layout, _hud._hero_health_bar, Rect2(0.0, 30.0, 276.0, 10.0))
	_hud._hero_status_label = _style.named_label("HeroStatusLabel")
	_hud._hero_status_label.add_theme_font_size_override("font_size", 18)
	_hud._hero_status_label.clip_text = true
	StyleScript.place(hero_layout, _hud._hero_status_label, Rect2(0.0, 42.0, 140.0, 21.0))
	_hud._hero_status_label.mouse_filter = Control.MOUSE_FILTER_PASS
	# A non-empty authoritative resource line is a real combat state, so it belongs to the
	# default screen beside the key status, not behind the summary toggle.
	_hud._resource_label = _style.named_label("ResourceLabel")
	_hud._resource_label.add_theme_font_size_override("font_size", 18)
	_hud._resource_label.add_theme_color_override("font_color", StyleScript.COLOR_PROXY)
	_hud._resource_label.clip_text = true
	_hud._resource_label.visible = false
	_hud._resource_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_hud._resource_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	StyleScript.place(hero_layout, _hud._resource_label, Rect2(142.0, 44.0, 130.0, 18.0))

	# Openable detail carrier (ART_BIBLE 12): the raw totals, the layout metadata and
	# the mode/proxy explanation that the sparse default strip deliberately drops live
	# here, so nothing the authority sent becomes unreachable. Anchored, not offset, so
	# it stays inside the 1280x720 stage at every UI scale.
	# The readout is opaque on purpose: it is the one surface that opens over live combat,
	# so world clutter must not show through the numbers the player is reading.
	_hud._summary_panel = _style.card("SummaryPanel", Vector2(SUMMARY_PANEL_X, SUMMARY_PANEL_TOP), Vector2(-(1280.0 - SUMMARY_PANEL_X - SUMMARY_PANEL_WIDTH), SUMMARY_PANEL_BOTTOM), 0.0, 0.0, 1.0, 0.0, 9.0, 1.0)
	# Long authoritative identifiers wrap; exceptional detail height scrolls inside
	# this fixed panel and never grows over the skill inputs.
	_hud._summary_body = ScrollContainer.new()
	_hud._summary_body.name = "SummaryBody"
	_hud._summary_body.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_hud._summary_body.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_hud._summary_body.mouse_filter = Control.MOUSE_FILTER_PASS
	_hud._summary_panel.add_child(_hud._summary_body)
	_hud._summary_stack = VBoxContainer.new()
	_hud._summary_stack.name = "SummaryStack"
	_hud._summary_stack.add_theme_constant_override("separation", 6)
	_hud._summary_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hud._summary_body.add_child(_hud._summary_stack)
	_hud._encounter_heading = _style.heading("Boss  Threshold Colossus")
	_hud._encounter_heading.name = "EncounterHeading"
	_hud._encounter_heading.clip_text = true
	StyleScript.place(boss_layout, _hud._encounter_heading, Rect2(0.0, 0.0, 342.0, 21.0))
	_hud._encounter_heading.mouse_filter = Control.MOUSE_FILTER_PASS
	_hud._room_start_label = _style.named_label("RoomStartLabel")
	_hud._room_start_label.add_theme_font_size_override("font_size", 18)
	_hud._room_start_label.add_theme_color_override("font_color", StyleScript.COLOR_AMBER)
	## The authored entry hints can exceed the strip: clip with an ellipsis
	## instead of running under the right-side mode/report panels.
	_hud._room_start_label.clip_text = true
	_hud._room_start_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_hud._room_start_label.visible = false
	StyleScript.place(boss_layout, _hud._room_start_label, Rect2(0.0, 42.0, 456.0, 21.0))
	_hud._boss_hp_label = _style.named_label("BossHpLabel")
	_hud._boss_hp_label.add_theme_font_size_override("font_size", 20)
	_hud._boss_hp_label.add_theme_color_override("font_color", StyleScript.COLOR_AMBER)
	_hud._boss_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hud._boss_hp_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	StyleScript.place(boss_layout, _hud._boss_hp_label, Rect2(346.0, 0.0, 110.0, 21.0))
	_hud._boss_health_bar = ProgressBar.new()
	_hud._boss_health_bar.name = "BossHealthBar"
	_hud._boss_health_bar.max_value = 100.0
	_hud._boss_health_bar.show_percentage = false
	StyleScript.style_progress(_hud._boss_health_bar, StyleScript.COLOR_WARNING)
	StyleScript.place(boss_layout, _hud._boss_health_bar, Rect2(0.0, 30.0, 456.0, 10.0))
	_hud._boss_state_label = _style.muted_label("")
	_hud._boss_state_label.name = "BossStateLabel"
	_hud._boss_state_label.add_theme_font_size_override("font_size", 18)
	_hud._boss_state_label.clip_text = true
	StyleScript.place(boss_layout, _hud._boss_state_label, Rect2(0.0, 42.0, 456.0, 21.0))
	_hud._boss_state_label.mouse_filter = Control.MOUSE_FILTER_PASS
	_hud._boss_name_label = _style.muted_label("Threshold Colossus")
	_hud._boss_name_label.name = "BossNameLabel"
	_hud._boss_name_label.clip_text = true
	_hud._boss_value_label = _style.named_label("BossValueLabel")
	_hud._boss_value_label.add_theme_font_size_override("font_size", 18)
	_hud._boss_value_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_hud._boss_ratio_label = _style.muted_label("")
	_hud._boss_ratio_label.name = "BossRatioLabel"
	_hud._boss_ratio_label.add_theme_font_size_override("font_size", 18)
	_hud._boss_ratio_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_hud._boss_damage_label = _style.named_label("BossDamageLabel")
	_hud._boss_damage_label.add_theme_font_size_override("font_size", 18)
	_hud._boss_damage_label.add_theme_color_override("font_color", StyleScript.COLOR_AMBER)
	_hud._boss_damage_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_hud._mode_state_label = _style.muted_label("")
	_hud._mode_state_label.name = "ModeStateLabel"
	_hud._mode_state_label.add_theme_font_size_override("font_size", 18)
	_hud._mode_state_label.clip_text = true
	_hud._mode_state_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY

	_hud._mode_label = _style.heading("")
	_hud._mode_label.name = "ModeLabel"
	_hud._mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hud._mode_label.clip_text = true
	StyleScript.place(utility_layout, _hud._mode_label, Rect2(0.0, 0.0, 224.0, 21.0))
	_hud._proxy_label = _style.muted_label("")
	_hud._proxy_label.name = "ProxyLabel"
	_hud._proxy_label.add_theme_font_size_override("font_size", 18)
	_hud._proxy_label.clip_text = true
	_hud._return_button = Button.new()
	_hud._return_button.name = "ReturnButton"
	_hud._return_button.text = "Leave"
	_hud._return_button.tooltip_text = "Leave Contract"
	# Combat shortcuts own keyboard input. A clicked utility button must not keep
	# focus and consume the next Space press as a GUI accept event.
	_hud._return_button.focus_mode = Control.FOCUS_NONE
	_hud._return_button.add_theme_font_size_override("font_size", 18)
	_hud._return_button.pressed.connect(func() -> void: _hud.return_requested.emit())
	# Theme padding keeps these buttons readable at the 18px floor. Keep them high
	# enough in the utility card that their real minimum size remains contained.
	StyleScript.place(utility_layout, _hud._return_button, Rect2(0.0, 29.0, 104.0, 36.0), true)
	_hud._summary_toggle_button = Button.new()
	_hud._summary_toggle_button.name = "SummaryToggleButton"
	_hud._summary_toggle_button.flat = true
	_hud._summary_toggle_button.focus_mode = Control.FOCUS_NONE
	_hud._summary_toggle_button.add_theme_font_size_override("font_size", 18)
	_hud._summary_toggle_button.tooltip_text = "Battle Report · Tab"
	_hud._summary_toggle_button.pressed.connect(_hud.toggle_summary)
	StyleScript.place(utility_layout, _hud._summary_toggle_button, Rect2(108.0, 29.0, 116.0, 36.0), true)

	# One row per authoritative fact inside the fixed readout; long data scrolls
	# without covering the action bar or widening the panel.
	_hud._summary_stack_note = _style.muted_label("Combat Details")
	_hud._summary_stack_note.name = "SummaryNoteLabel"
	_hud._summary_stack_note.add_theme_font_size_override("font_size", 18)
	_hud._summary_stack.add_child(StyleScript.summary_row(_hud._summary_stack_note))
	_hud._summary_stack.add_child(StyleScript.summary_row(_hud._boss_name_label))
	_hud._summary_stack.add_child(StyleScript.summary_row(_hud._boss_value_label))
	_hud._summary_stack.add_child(StyleScript.summary_row(_hud._boss_ratio_label))
	_hud._summary_stack.add_child(StyleScript.summary_row(_hud._boss_damage_label))
	_hud._summary_encounter_label = _style.muted_label("")
	_hud._summary_encounter_label.name = "EncounterRulesLabel"
	_hud._summary_encounter_label.add_theme_font_size_override("font_size", 18)
	_hud._summary_encounter_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hud._summary_stack.add_child(StyleScript.summary_row(_hud._summary_encounter_label))
	_hud._summary_stack.add_child(StyleScript.summary_row(_hud._mode_state_label))
	_hud._summary_stack.add_child(StyleScript.summary_row(_hud._proxy_label))
	_hud._summary_parameters_label = _style.named_label("SummaryParametersLabel")
	_hud._summary_parameters_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_hud._summary_stack.add_child(StyleScript.summary_row(_hud._summary_parameters_label))
	_hud._summary_growth_label = _style.named_label("SummaryGrowthLabel")
	_hud._summary_growth_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_hud._summary_stack.add_child(StyleScript.summary_row(_hud._summary_growth_label))
	_hud._summary_block_label = _style.named_label("SummaryBlockLabel")
	_hud._summary_block_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hud._summary_stack.add_child(StyleScript.summary_row(_hud._summary_block_label))
	## Trailing gutter: the last report row must never render flush against the
	## scroll clip edge (visual backlog: bottom line read as cut off).
	var bottom_gutter := Control.new()
	bottom_gutter.name = "SummaryBottomGutter"
	bottom_gutter.custom_minimum_size = Vector2(0.0, 8.0)
	bottom_gutter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud._summary_stack.add_child(bottom_gutter)
	_hud._summary_panel.clip_contents = true
	_hud._summary_panel.visible = false

	# Four immediate actions share one low single row at the lower-right edge.
	var action_card := _style.card("ActionBar", Vector2(-ACTION_BAR_WIDTH - 8.0, -ACTION_BAR_HEIGHT - 8.0), Vector2(-8.0, -8.0), 1.0, 1.0, 1.0, 1.0, 4.0, 0.78)
	_hud._action_bar = action_card
	var action_layout := StyleScript.layout("ActionBarLayout", action_card)
	_hud._feedback_label = _style.named_label("FeedbackLabel")
	_hud._feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud._feedback_label.clip_text = true
	_hud._feedback_label.add_theme_color_override("font_color", StyleScript.COLOR_AMBER)
	_hud._feedback_label.add_theme_font_size_override("font_size", 18)
	_hud._feedback_label.visible = false
	_hud._feedback_label.clip_text = true
	_hud._feedback_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	StyleScript.place(action_layout, _hud._feedback_label, Rect2(0.0, 0.0, ACTION_BAR_CONTENT_WIDTH, 18.0))
	var action_row := GridContainer.new()
	action_row.name = "ActionRow"
	action_row.columns = 4
	action_row.add_theme_constant_override("h_separation", 2)
	action_row.add_theme_constant_override("v_separation", 0)
	StyleScript.place(action_layout, action_row, Rect2(0.0, 0.0, ACTION_BAR_CONTENT_WIDTH, 100.0))
	for slot in CellsScript.SKILL_SLOTS:
		action_row.add_child(_hud._cells.build_cell(slot))
	## The one transient strip on the default screen: anchored bottom-left of the
	## action dock, so an invalid-action hint is readable without ever covering
	## the icons, the pause button, or the opening-room banner. The label sizes
	## itself to the card's real inner box (512 outer minus 2x12 content margins).
	var input_feedback_card := _style.card("InputFeedbackCard", Vector2(180.0, -122.0), Vector2(812.0, -90.0), 0.0, 1.0, 0.0, 1.0, 4.0, 0.78)
	_hud._input_feedback_card = input_feedback_card
	_hud._input_feedback_card.visible = false
	var input_feedback_layout := StyleScript.layout("InputFeedbackLayout", input_feedback_card)
	_hud._input_feedback_label = _style.named_label("InputFeedbackLabel")
	_hud._input_feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud._input_feedback_label.clip_text = true
	_hud._input_feedback_label.add_theme_color_override("font_color", StyleScript.COLOR_AMBER)
	_hud._input_feedback_label.add_theme_font_size_override("font_size", 18)
	_hud._input_feedback_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud._input_feedback_label.visible = false
	StyleScript.place(input_feedback_layout, _hud._input_feedback_label, Rect2(0.0, 0.0, 608.0, 24.0))
	_hud.set_summary_visible(false)
