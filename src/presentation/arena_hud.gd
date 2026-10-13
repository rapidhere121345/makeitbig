extends Control
## Formal arena HUD. Every number, lock and disabled state below comes from the
## authoritative snapshot that src/game/main.gd already publishes; the art only
## supplies the four approved 32x32 icons, drawn at an integer 2x (64 display
## pixels) with no baked state, no glow and no invented resource.
##
## Information hierarchy (concept 05 COMBAT in 10_ui_screens.png, hierarchy only):
##  * default strip = three separated cards for hero life, the one important target,
##    and low-frequency controls. TopBar stays as a transparent compatibility carrier.
##  * short input notices (blank-click hints, unavailable-skill reasons, assisted
##    out-of-range cues) are the one transient strip, docked left of the action bar
##    so they can never cover the four action icons or the opening-room banner.
##    Routine attack/count feedback stays collapsed into the TAB summary.
##  * the strip numbers the concept makes prominent are the cells that already
##    existed: HeroHealthLabel above the hero bar and BossHpLabel above the target
##    bar. Raw scientific totals, cumulative damage, layout metadata and the
##    mode/proxy explanation are not deleted, they sit in the summary panel that
##    the TAB key or the 摘要 button opens (ART_BIBLE 12: "大公式、长词条、代理
##    流水线进入可打开详情").
##  * a cell hidden with the summary is moved into that panel instead of staying at
##    a stale offset, so no invisible control can pass a containment check.

signal skill_one_requested
signal skill_two_requested
signal skill_three_requested
signal dodge_requested
signal return_requested

const PaletteScript = preload("res://src/presentation/combat_palette.gd")
const SkillIconsScript = preload("res://src/presentation/combat_skill_icons.gd")
const ShellThemeScript = preload("res://src/presentation/shell_theme.gd")
const EarlySkillRegistryScript = preload("res://src/content/early_skill_registry.gd")
const PlayerReadableBuildScript = preload("res://src/presentation/player_readable_build.gd")

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
## Combat HUD text uses the bundled sans face used for numbers and controls. The
## serif face remains appropriate for story and town copy, but its high contrast
## strokes become visually uneven at the compact 18-20px combat scale.
const HUD_TEXT_OUTLINE: Color = Color("10161c")
const HUD_TEXT_OUTLINE_SIZE := 1

const SKILL_ICON_DISPLAY: float = 40.0
const SKILL_CELL_MINIMUM := Vector2(104.0, 100.0)
const SKILL_STATE_SIZE := Vector2(96.0, 24.0)
const SKILL_STATE_FONT_SIZE: int = 18
const SKILL_KEY_FONT_SIZE: int = 18
const SKILL_NAME_FONT_SIZE: int = 18
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
## Mode chips. The mode is locked for the whole active battle, for Manual exactly as for
## AUTO, because a contract's instruction stream cannot be switched mid-fight; only AUTO
## also disables the manual skill keys. The concept writes the mode plainly and adds a
## lock mark, so neither state leans on colour alone (ART_BIBLE 12.2).
const MODE_MANUAL: String = "MANUAL"
const MODE_MANUAL_LOCKED: String = "MANUAL · 模式锁定"
const MODE_AUTO_LOCKED: String = "AUTO [锁] · 模式锁定"
const SKILL_SLOTS: Array[Dictionary] = [
	{"node_name": "Skill1Button", "slot_id": "piercing_arrow", "title": "穿刺"},
	{"node_name": "Skill2Button", "slot_id": "hunter_mark", "title": "印记"},
	{"node_name": "Skill3Button", "slot_id": "dash", "title": "突袭"},
	{"node_name": "DodgeButton", "slot_id": "basic_dodge", "title": "闪避"},
]
const SLOT_PRIMARY_KEYS := {
	"Skill1Button": "空格",
	"Skill2Button": "Q",
	"Skill3Button": "E",
	"DodgeButton": "Shift",
}

var icons = SkillIconsScript.new()
var icon_pending_reason: String = ""
var ui_font: FontFile
var _skill_registry = EarlySkillRegistryScript.new()
var _player_readable = PlayerReadableBuildScript.new()

var _hero_health_label: Label
var _hero_health_bar: ProgressBar
var _hero_status_label: Label
var _resource_label: Label
var _boss_name_label: Label
var _boss_hp_label: Label
var _boss_state_label: Label
var _boss_value_label: Label
var _boss_health_bar: ProgressBar
var _boss_ratio_label: Label
var _boss_damage_label: Label
var _encounter_heading: Label
var _room_start_label: Label
var _elite_mechanic_frame: PanelContainer
var _elite_mechanic_label: Label
var _mode_label: Label
var _mode_state_label: Label
var _proxy_label: Label
var _feedback_label: Label
var _input_feedback_label: Label
var _input_feedback_card: PanelContainer
var _summary_panel: PanelContainer
var _summary_toggle_button: Button
var _summary_body: Control
var _summary_stack: VBoxContainer
var _summary_stack_note: Label
var _summary_parameters_label: Label
var _summary_growth_label: Label
var _summary_block_label: Label
var _summary_encounter_label: Label
var _summary_proxy_label: Label
var _return_button: Button
var _action_bar: PanelContainer
var _hero_frame: PanelContainer
var _boss_frame: PanelContainer
var _utility_frame: PanelContainer
var _action_edge_occluded := false
var _cell_buttons: Dictionary = {}
var _cell_icons: Dictionary = {}
var _cell_states: Dictionary = {}
var _cell_progress: Dictionary = {}
var _cell_cooldown_remaining: Dictionary = {}
var _cell_details: Dictionary = {}
var _skill_overrides: Dictionary = {}
## Routine feedback copy: authoritative, but only readable in the TAB summary or a
## cell tooltip. The old always-on strip slot is retired to keep the default screen
## low-clutter; short input notices use the dedicated transient strip instead.
var _feedback_text: String = ""
## Last authoritative line the authority sent for the optional resource warning. The
## HUD never invents one; the default strip shows any authoritative non-empty value.
var _resource_state_text: String = ""


func _init() -> void:
	_skill_registry.load_all()
	_build_interface()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func present(snapshot: Dictionary) -> void:
	var player_health := clampf(float(snapshot.get("player_health", 0.0)), 0.0, float(snapshot.get("player_health_max", 100.0)))
	var player_health_max := maxf(1.0, float(snapshot.get("player_health_max", 100.0)))
	_hero_health_label.text = "HP  %s / %s" % [_plain_number(player_health), _plain_number(player_health_max)]
	var mode := String(snapshot.get("selected_mode", "Manual")).to_upper()
	var is_auto := mode == "AUTO"
	var battle_over := bool(snapshot.get("battle_over", false))
	# The mode is locked for the whole active battle and is switchable again once it ends,
	# which is the invariant the previous strip already carried. Manual stays selectable
	# (its skills keep working) but is still named as mode-locked; only AUTO disables the
	# skill keys. No new snapshot field is invented for this: battle_over already says it.
	var mode_locked := not battle_over
	var mode_chip := (MODE_AUTO_LOCKED if is_auto else MODE_MANUAL_LOCKED) if mode_locked else mode
	var mode_detail := "%s · 战斗结束" % mode_chip if battle_over else ("%s · 键位已锁" % mode_chip if is_auto else "%s · 键位可用" % mode_chip)
	_hero_health_bar.max_value = player_health_max
	_hero_health_bar.value = player_health
	var key_status := String(snapshot.get("key_status", "稳定"))
	var hero_ratio := player_health / player_health_max
	_hero_status_label.text = ("⚠ 危急 · %s" % key_status) if hero_ratio <= 0.30 else ("◆ 关键状态  %s" % key_status)
	# No resource is fabricated: this line only appears when an authority sends it.
	# It remains with the hero status even when the optional details are folded.
	_resource_state_text = String(snapshot.get("resource_state", ""))
	_resource_label.text = _resource_state_text
	_hero_status_label.tooltip_text = _hero_status_label.text
	_apply_resource_visibility()

	var has_boss := bool(snapshot.get("has_boss", true))
	var objective_label := String(snapshot.get("objective_label", snapshot.get("objective_id", "clear")))
	_encounter_heading.text = "首领  阈门巨像" if has_boss else "目标  %s" % objective_label
	var has_room_progress := snapshot.has("room_count")
	var room_count := maxi(1, int(snapshot.get("room_count", 1)))
	var room_number := clampi(int(snapshot.get("room_index", 0)) + 1, 1, room_count)
	var room_display_name := String(snapshot.get("room_display_name", "")).strip_edges()
	var has_room_display_name := snapshot.has("room_display_name") and not room_display_name.is_empty()
	if room_display_name.is_empty():
		## Older diagnostic snapshots do not carry the authored room presentation
		## fields. Keep their objective wording intact while live sessions use the
		## content-authored scene name above.
		room_display_name = String(snapshot.get("layout_id", snapshot.get("objective_label", "战斗场")))
	var room_entry_hint := String(snapshot.get("room_entry_hint", "留意攻击预警"))
	var room_concept := String(snapshot.get("room_concept", ""))
	var room_landmark := String(snapshot.get("room_landmark", ""))
	var room_exit_hint := String(snapshot.get("room_exit_hint", ""))
	if has_room_progress:
		var room_title := "阈门巨像" if has_boss else room_display_name
		var room_objective := "首领" if has_boss else objective_label
		if not has_boss and not has_room_display_name:
			# Keep diagnostic snapshots and older callers on the compact contract;
			# live embedded rooms publish the authored scene name explicitly.
			_encounter_heading.text = "第 %d / %d 房 · %s" % [room_number, room_count, room_objective]
		else:
			_encounter_heading.text = "第 %d / %d 房 · %s · %s" % [room_number, room_count, room_title, room_objective]
	_encounter_heading.tooltip_text = _encounter_heading.text
	# A read-only entry cue uses the room's existing elapsed time and never delays input.
	_room_start_label.visible = has_room_progress and not has_boss and not battle_over and float(snapshot.get("room_elapsed_seconds", 99.0)) < 1.8
	_room_start_label.text = "进入第 %d 房 · %s" % [room_number, room_entry_hint]
	_room_start_label.tooltip_text = room_entry_hint
	_boss_state_label.visible = not _room_start_label.visible
	_boss_name_label.text = "阈门巨像" if has_boss else "当前目标"
	_boss_value_label.text = "%s / %s" % [String(snapshot.get("boss_remaining", "—")), String(snapshot.get("boss_maximum", "—"))] if has_boss else "目标 %s · 存活 %d" % [String(snapshot.get("objective_label", snapshot.get("objective_id", "clear"))), int(snapshot.get("living_targets", 0))]
	var ratio_known := bool(snapshot.get("boss_ratio_known", false))
	_boss_health_bar.value = clampf(float(snapshot.get("boss_ratio", 0.0)), 0.0, 1.0) * 100.0 if ratio_known else 0.0
	_boss_health_bar.visible = has_boss
	# The default strip shows the true ratio when the shared layer makes it comparable
	# and says so explicitly when it is not; the two totals behind it stay one Tab away.
	_boss_hp_label.text = "%.1f%%" % _boss_health_bar.value if ratio_known else "比例不可比"
	_boss_hp_label.visible = has_boss
	_boss_ratio_label.text = ("同层真实比例  %.1f%%" % _boss_health_bar.value if ratio_known else "结构层级不同 · 比例不可比") if has_boss else "留意敌人的攻击预警"
	_boss_damage_label.text = "对 Boss 伤害  %s" % String(snapshot.get("damage", "0")) if has_boss else "目标 %s · 存活 %d" % [String(snapshot.get("objective_label", "清理敌人")), int(snapshot.get("living_targets", 0))]
	_boss_state_label.text = ("真实比例已知" if ratio_known else "比例不可比") if has_boss else "剩余目标  %d" % int(snapshot.get("living_targets", 0))
	var hazards := String(snapshot.get("hazard_status", "无"))
	var elites := String(snapshot.get("elite_status", "无"))
	_summary_encounter_label.text = "场域：%s · %s\n%s\n危害：%s\n精英：%s" % [room_display_name, room_landmark, room_concept, _encounter_status_text(hazards), _encounter_status_text(elites)]
	if not room_exit_hint.is_empty():
		_summary_encounter_label.text += "\n出口：%s" % room_exit_hint
	# Mechanic windows come from authority, including their clearing on elite defeat.
	# Keep them on screen even during the entry cue, without replacing room or life.
	_elite_mechanic_label.text = "" if battle_over else _elite_mechanic_text(elites)
	_elite_mechanic_frame.visible = not _elite_mechanic_label.text.is_empty()
	_elite_mechanic_frame.offset_bottom = 96.0 + (72.0 if "\n" in _elite_mechanic_label.text else 42.0)
	_elite_mechanic_label.add_theme_color_override("font_color", COLOR_AMBER if "periodic_barrier:active" in elites else COLOR_BONE)

	_mode_label.text = mode_chip
	_mode_label.add_theme_color_override("font_color", COLOR_PROXY if is_auto else COLOR_AMBER)
	_mode_state_label.text = mode_detail
	if is_auto:
		var prediction := String(snapshot.get("proxy_prediction", "unknown")).to_upper()
		var refusal := _proxy_failure_text(snapshot.get("last_proxy_failure", {}))
		_proxy_label.text = "代理 %s · 手动指令流已停止" % prediction if refusal == "无" else "最近拒绝  %s" % refusal
	else:
		_proxy_label.text = "手动指令流 · 代理未运行"

	_feedback_text = String(snapshot.get("feedback", "等待首次命中"))
	_feedback_label.text = "战斗反馈  %s" % _compact_feedback(_feedback_text)
	_feedback_label.tooltip_text = _feedback_text
	var input_feedback := String(snapshot.get("input_feedback", ""))
	## The whole card shows and hides with the notice: no permanent blank
	## rectangle lingers over the battlefield.
	_input_feedback_card.visible = not input_feedback.is_empty()
	_input_feedback_label.text = input_feedback
	_input_feedback_label.tooltip_text = input_feedback
	_input_feedback_label.visible = not input_feedback.is_empty()
	_update_action_cells(snapshot, is_auto, battle_over)
	_apply_hero_health_state(hero_ratio)
	_update_summary(snapshot)
	_set_action_edge_occlusion(bool(snapshot.get("action_edge_occluded", false)))


func update_state(snapshot: Dictionary) -> void:
	present(snapshot)


func set_summary_visible(value: bool) -> void:
	_summary_panel.visible = value
	_summary_toggle_button.text = "战报 TAB ▲" if value else "战报 TAB ▼"
	_summary_stack_note.text = "战斗详情"


func toggle_summary() -> void:
	set_summary_visible(not _summary_panel.visible)


## The resource warning is a real combat state, so it stays on the default screen in the
## hero column: visible exactly when the authority sent a line, also while the summary is
## collapsed. An absent field is never turned into a warning and never fakes an absence.
## The visible read for short input notices: the exact authoritative sentence,
## visible exactly while the authority sends one, independent of summary or
## occlusion state.
func input_feedback_text() -> String:
	return _input_feedback_label.text if _input_feedback_label != null else ""


func _apply_resource_visibility() -> void:
	if _resource_label == null:
		return
	_resource_label.visible = not _resource_state_text.is_empty()
	# The strip cell clips so it can never widen the hero column; the tooltip carries the
	# complete authoritative line when it does not fit.
	_resource_label.tooltip_text = _resource_state_text if _resource_label.visible else ""


func is_pointer_over_interface() -> bool:
	var viewport := get_viewport()
	if viewport == null:
		return false
	# Input's mouse-button state is global, even when a SubViewportContainer
	# correctly rejects a click in the letterbox. Exclude those pixels from the
	# held-fire path as well, using the same viewport-space pointer as the HUD.
	if not viewport.get_visible_rect().has_point(viewport.get_mouse_position()):
		return true
	var hovered := viewport.gui_get_hovered_control()
	return hovered != null and (hovered == self or is_ancestor_of(hovered))


## Full authoritative copy for one cell, including what the compact layout cannot
## fit. Never returns an invented value.
func skill_cell_detail(node_name: String) -> String:
	return String(_cell_details.get(node_name, ""))


func skill_icon(node_name: String) -> Texture2D:
	var icon: TextureRect = _cell_icons.get(node_name)
	return null if icon == null else icon.texture


## Read-only evidence for tests and scene inspection. Values remain snapped to
## actual control geometry; no ideal layout is reported.
func skill_cooldown_progress(node_name: String) -> float:
	var bar: ProgressBar = _cell_progress.get(node_name)
	return 0.0 if bar == null else bar.value


## Stable runtime evidence for combat-layout acceptance. The named carriers
## (TopBar, ActionBar and SummaryPanel) remain available for scene inspection;
## this report quantifies how much of the 1280x720 stage is covered right now.
## The summary only counts while it is intentionally open.
func combat_layout_report() -> Dictionary:
	var frame := Rect2(Vector2.ZERO, size)
	var top_bar := find_child("TopBar", true, false) as Control
	var top_rect := top_bar.get_global_rect() if top_bar != null and top_bar.visible else Rect2()
	var hero_rect := _visible_rect(_hero_frame)
	var boss_rect := _visible_rect(_boss_frame)
	var utility_rect := _visible_rect(_utility_frame)
	var action_rect := _action_bar.get_global_rect() if _action_bar != null and _action_bar.visible else Rect2()
	var summary_rect := _summary_panel.get_global_rect() if _summary_panel != null and _summary_panel.visible else Rect2()
	var top_pixels := roundi(hero_rect.get_area() + boss_rect.get_area() + utility_rect.get_area())
	var bottom_pixels := roundi(action_rect.get_area())
	var summary_pixels := roundi(summary_rect.get_area())
	var covered_pixels := top_pixels + bottom_pixels + summary_pixels
	return {
		"frame": [roundi(frame.size.x), roundi(frame.size.y)],
		"top_node": "TopBar",
		"bottom_node": "ActionBar",
		"summary_node": "SummaryPanel",
		"top_rect": _rect_array(top_rect),
		"top_panel_nodes": ["HeroFrame", "BossFrame", "UtilityFrame"],
		"hero_rect": _rect_array(hero_rect),
		"boss_rect": _rect_array(boss_rect),
		"utility_rect": _rect_array(utility_rect),
		"top_panel_rects": [_rect_array(hero_rect), _rect_array(boss_rect), _rect_array(utility_rect)],
		"top_panels_disjoint": not hero_rect.intersects(boss_rect) and not hero_rect.intersects(utility_rect) and not boss_rect.intersects(utility_rect),
		"bottom_rect": _rect_array(action_rect),
		"summary_rect": _rect_array(summary_rect),
		"top_occupied_pixels": top_pixels,
		"bottom_occupied_pixels": bottom_pixels,
		"summary_occupied_pixels": summary_pixels,
		"visible_hud_pixels": covered_pixels,
		"open_battle_pixels": maxi(0, roundi(frame.get_area()) - covered_pixels),
		"action_edge_occluded": _action_edge_occluded,
		"critical_visible": _hero_health_label != null and _hero_health_label.visible and _hero_health_bar != null and _hero_health_bar.visible and _hero_status_label != null and _hero_status_label.visible,
		"critical_health": _critical_health_visible(),
		"hero_health_warning": _hero_status_label != null and _hero_status_label.visible and _hero_status_label.text.begins_with("⚠ 危急"),
		"skill_controls_visible": _skill_controls_visible(),
	}


func _visible_rect(control: Control) -> Rect2:
	return control.get_global_rect() if control != null and control.visible else Rect2()


func _rect_array(rect: Rect2) -> Array[int]:
	return [roundi(rect.position.x), roundi(rect.position.y), roundi(rect.size.x), roundi(rect.size.y)]


func _skill_controls_visible() -> bool:
	for node_name: String in SLOT_PRIMARY_KEYS.keys():
		var button: Button = _cell_buttons.get(node_name)
		if button == null or not button.visible:
			return false
	return true


## Tab lives in _input, not _unhandled_input: a focused button eats Tab as GUI focus
## navigation before unhandled input sees it, which made the first press do nothing (or
## move focus) while the second appeared to work. Only Tab is consumed here, so focus
## navigation, the skill keys and the pause menu keep their normal routing.
func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_TAB:
		toggle_summary()
		get_viewport().set_input_as_handled()


func _build_interface() -> void:
	if not icons.load_icons():
		icon_pending_reason = String(icons.pending_reason)
	## Combat is a read-and-react surface: use the medium sans face for stable
	## Chinese glyph fill, numeric widths and key labels. Story screens keep the
	## serif shell font through ShellTheme.create().
	ui_font = ShellThemeScript.data_font()
	if ui_font != null:
		var own_theme := Theme.new()
		own_theme.default_font = ui_font
		own_theme.default_font_size = ShellThemeScript.MIN_FONT_SIZE
		own_theme.set_color("font_color", "Label", COLOR_BONE)
		own_theme.set_color("font_outline_color", "Label", HUD_TEXT_OUTLINE)
		own_theme.set_constant("outline_size", "Label", HUD_TEXT_OUTLINE_SIZE)
		own_theme.set_color("font_color", "Button", COLOR_BONE)
		own_theme.set_color("font_outline_color", "Button", HUD_TEXT_OUTLINE)
		own_theme.set_constant("outline_size", "Button", HUD_TEXT_OUTLINE_SIZE)
		theme = own_theme

	# TopBar remains the stable full-width carrier, but has no visible backing. The
	# three cards inside it are the only opaque top surfaces and leave world-visible gaps.
	var top_bar := _card("TopBar", Vector2(8.0, 6.0), Vector2(-8.0, 6.0 + TOP_BAR_HEIGHT), 0.0, 0.0, 1.0, 0.0, 0.0, 0.0)
	top_bar.add_theme_stylebox_override("panel", _transparent_panel_style())
	var top_layout := _layout("TopBarLayout", top_bar)
	_hero_frame = _panel_in("HeroFrame", top_layout, HERO_FRAME_RECT, 5.0, 0.90)
	_boss_frame = _panel_in("BossFrame", top_layout, BOSS_FRAME_RECT, 5.0, 0.90)
	_utility_frame = _panel_in("UtilityFrame", top_layout, UTILITY_FRAME_RECT, 5.0, 0.90)
	var hero_layout := _layout("HeroFrameLayout", _hero_frame)
	var boss_layout := _layout("BossFrameLayout", _boss_frame)
	var utility_layout := _layout("UtilityFrameLayout", _utility_frame)
	# A compact read-only cue sits below the target card, clear of the hero,
	# room heading, summary and skill dock at both supported viewport widths.
	_elite_mechanic_frame = _card("EliteMechanicFrame", Vector2(400.0, 96.0), Vector2(880.0, 138.0), 0.0, 0.0, -1.0, -1.0, 4.0, 0.90)
	_elite_mechanic_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_elite_mechanic_frame.visible = false
	_elite_mechanic_label = _named_label("EliteMechanicLabel")
	_elite_mechanic_label.add_theme_font_size_override("font_size", 18)
	_elite_mechanic_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_elite_mechanic_frame.add_child(_elite_mechanic_label)
	_hero_health_label = _named_label("HeroHealthLabel")
	_hero_health_label.add_theme_font_size_override("font_size", 20)
	_hero_health_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_place(hero_layout, _hero_health_label, Rect2(0.0, 0.0, 276.0, 21.0))
	_hero_health_bar = ProgressBar.new()
	_hero_health_bar.name = "HeroHealthBar"
	_hero_health_bar.show_percentage = false
	_style_progress(_hero_health_bar, COLOR_BONE)
	_place(hero_layout, _hero_health_bar, Rect2(0.0, 30.0, 276.0, 10.0))
	_hero_status_label = _named_label("HeroStatusLabel")
	_hero_status_label.add_theme_font_size_override("font_size", 18)
	_hero_status_label.clip_text = true
	_place(hero_layout, _hero_status_label, Rect2(0.0, 42.0, 140.0, 21.0))
	# A non-empty authoritative resource line is a real combat state, so it belongs to the
	# default screen beside the key status, not behind the summary toggle.
	_resource_label = _named_label("ResourceLabel")
	_resource_label.add_theme_font_size_override("font_size", 18)
	_resource_label.add_theme_color_override("font_color", COLOR_PROXY)
	_resource_label.clip_text = true
	_resource_label.visible = false
	_resource_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_resource_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_place(hero_layout, _resource_label, Rect2(142.0, 44.0, 130.0, 18.0))

	# Openable detail carrier (ART_BIBLE 12): the raw totals, the layout metadata and
	# the mode/proxy explanation that the sparse default strip deliberately drops live
	# here, so nothing the authority sent becomes unreachable. Anchored, not offset, so
	# it stays inside the 1280x720 stage at every UI scale.
	# The readout is opaque on purpose: it is the one surface that opens over live combat,
	# so world clutter must not show through the numbers the player is reading.
	_summary_panel = _card("SummaryPanel", Vector2(SUMMARY_PANEL_X, SUMMARY_PANEL_TOP), Vector2(-(1280.0 - SUMMARY_PANEL_X - SUMMARY_PANEL_WIDTH), SUMMARY_PANEL_BOTTOM), 0.0, 0.0, 1.0, 0.0, 9.0, 1.0)
	# Long authoritative identifiers wrap; exceptional detail height scrolls inside
	# this fixed panel and never grows over the skill inputs.
	_summary_body = ScrollContainer.new()
	_summary_body.name = "SummaryBody"
	_summary_body.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_summary_body.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_summary_body.mouse_filter = Control.MOUSE_FILTER_PASS
	_summary_panel.add_child(_summary_body)
	_summary_stack = VBoxContainer.new()
	_summary_stack.name = "SummaryStack"
	_summary_stack.add_theme_constant_override("separation", 6)
	_summary_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_summary_body.add_child(_summary_stack)
	_encounter_heading = _heading("首领  阈门巨像")
	_encounter_heading.name = "EncounterHeading"
	_encounter_heading.clip_text = true
	_place(boss_layout, _encounter_heading, Rect2(0.0, 0.0, 342.0, 21.0))
	_room_start_label = _named_label("RoomStartLabel")
	_room_start_label.add_theme_font_size_override("font_size", 18)
	_room_start_label.add_theme_color_override("font_color", COLOR_AMBER)
	_room_start_label.visible = false
	_place(boss_layout, _room_start_label, Rect2(0.0, 42.0, 456.0, 21.0))
	_boss_hp_label = _named_label("BossHpLabel")
	_boss_hp_label.add_theme_font_size_override("font_size", 20)
	_boss_hp_label.add_theme_color_override("font_color", COLOR_AMBER)
	_boss_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_boss_hp_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_place(boss_layout, _boss_hp_label, Rect2(346.0, 0.0, 110.0, 21.0))
	_boss_health_bar = ProgressBar.new()
	_boss_health_bar.name = "BossHealthBar"
	_boss_health_bar.max_value = 100.0
	_boss_health_bar.show_percentage = false
	_style_progress(_boss_health_bar, COLOR_WARNING)
	_place(boss_layout, _boss_health_bar, Rect2(0.0, 30.0, 456.0, 10.0))
	_boss_state_label = _muted_label("")
	_boss_state_label.name = "BossStateLabel"
	_boss_state_label.add_theme_font_size_override("font_size", 18)
	_boss_state_label.clip_text = true
	_place(boss_layout, _boss_state_label, Rect2(0.0, 42.0, 456.0, 21.0))
	_boss_name_label = _muted_label("阈门巨像")
	_boss_name_label.name = "BossNameLabel"
	_boss_name_label.clip_text = true
	_boss_value_label = _named_label("BossValueLabel")
	_boss_value_label.add_theme_font_size_override("font_size", 18)
	_boss_value_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_boss_ratio_label = _muted_label("")
	_boss_ratio_label.name = "BossRatioLabel"
	_boss_ratio_label.add_theme_font_size_override("font_size", 18)
	_boss_ratio_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_boss_damage_label = _named_label("BossDamageLabel")
	_boss_damage_label.add_theme_font_size_override("font_size", 18)
	_boss_damage_label.add_theme_color_override("font_color", COLOR_AMBER)
	_boss_damage_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_mode_state_label = _muted_label("")
	_mode_state_label.name = "ModeStateLabel"
	_mode_state_label.add_theme_font_size_override("font_size", 18)
	_mode_state_label.clip_text = true
	_mode_state_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY

	_mode_label = _heading("")
	_mode_label.name = "ModeLabel"
	_mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_mode_label.clip_text = true
	_place(utility_layout, _mode_label, Rect2(0.0, 0.0, 224.0, 21.0))
	_proxy_label = _muted_label("")
	_proxy_label.name = "ProxyLabel"
	_proxy_label.add_theme_font_size_override("font_size", 18)
	_proxy_label.clip_text = true
	_return_button = Button.new()
	_return_button.name = "ReturnButton"
	_return_button.text = "退出合同"
	_return_button.add_theme_font_size_override("font_size", 18)
	_return_button.pressed.connect(func() -> void: return_requested.emit())
	# Theme padding keeps these buttons readable at the 18px floor. Keep them high
	# enough in the utility card that their real minimum size remains contained.
	_place(utility_layout, _return_button, Rect2(0.0, 29.0, 104.0, 36.0), true)
	_summary_toggle_button = Button.new()
	_summary_toggle_button.name = "SummaryToggleButton"
	_summary_toggle_button.flat = true
	_summary_toggle_button.add_theme_font_size_override("font_size", 18)
	_summary_toggle_button.pressed.connect(toggle_summary)
	_place(utility_layout, _summary_toggle_button, Rect2(108.0, 29.0, 116.0, 36.0), true)

	# One row per authoritative fact inside the fixed readout; long data scrolls
	# without covering the action bar or widening the panel.
	_summary_stack_note = _muted_label("战斗详情")
	_summary_stack_note.name = "SummaryNoteLabel"
	_summary_stack_note.add_theme_font_size_override("font_size", 18)
	_summary_stack.add_child(_summary_row(_summary_stack_note))
	_summary_stack.add_child(_summary_row(_boss_name_label))
	_summary_stack.add_child(_summary_row(_boss_value_label))
	_summary_stack.add_child(_summary_row(_boss_ratio_label))
	_summary_stack.add_child(_summary_row(_boss_damage_label))
	_summary_encounter_label = _muted_label("")
	_summary_encounter_label.name = "EncounterRulesLabel"
	_summary_encounter_label.add_theme_font_size_override("font_size", 18)
	_summary_encounter_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary_stack.add_child(_summary_row(_summary_encounter_label))
	_summary_stack.add_child(_summary_row(_mode_state_label))
	_summary_stack.add_child(_summary_row(_proxy_label))
	_summary_parameters_label = _named_label("SummaryParametersLabel")
	_summary_parameters_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_summary_stack.add_child(_summary_row(_summary_parameters_label))
	_summary_growth_label = _named_label("SummaryGrowthLabel")
	_summary_growth_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_summary_stack.add_child(_summary_row(_summary_growth_label))
	_summary_block_label = _named_label("SummaryBlockLabel")
	_summary_block_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary_stack.add_child(_summary_row(_summary_block_label))
	_summary_panel.clip_contents = true
	_summary_panel.visible = false

	# Four immediate actions share one low single row at the lower-right edge.
	var action_card := _card("ActionBar", Vector2(-ACTION_BAR_WIDTH - 8.0, -ACTION_BAR_HEIGHT - 8.0), Vector2(-8.0, -8.0), 1.0, 1.0, 1.0, 1.0, 4.0, 0.78)
	_action_bar = action_card
	var action_layout := _layout("ActionBarLayout", action_card)
	_feedback_label = _named_label("FeedbackLabel")
	_feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_feedback_label.clip_text = true
	_feedback_label.add_theme_color_override("font_color", COLOR_AMBER)
	_feedback_label.add_theme_font_size_override("font_size", 18)
	_feedback_label.visible = false
	_feedback_label.clip_text = true
	_feedback_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(action_layout, _feedback_label, Rect2(0.0, 0.0, ACTION_BAR_CONTENT_WIDTH, 18.0))
	var action_row := GridContainer.new()
	action_row.name = "ActionRow"
	action_row.columns = 4
	action_row.add_theme_constant_override("h_separation", 2)
	action_row.add_theme_constant_override("v_separation", 0)
	_place(action_layout, action_row, Rect2(0.0, 0.0, ACTION_BAR_CONTENT_WIDTH, 100.0))
	for slot in SKILL_SLOTS:
		action_row.add_child(_build_skill_cell(slot))
	## The one transient strip on the default screen: anchored bottom-left of the
	## action dock, so an invalid-action hint is readable without ever covering
	## the icons, the pause button, or the opening-room banner. The label sizes
	## itself to the card's real inner box (512 outer minus 2x12 content margins).
	var input_feedback_card := _card("InputFeedbackCard", Vector2(300.0, -122.0), Vector2(812.0, -90.0), 0.0, 1.0, 0.0, 1.0, 4.0, 0.78)
	_input_feedback_card = input_feedback_card
	_input_feedback_card.visible = false
	var input_feedback_layout := _layout("InputFeedbackLayout", input_feedback_card)
	_input_feedback_label = _named_label("InputFeedbackLabel")
	_input_feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_input_feedback_label.clip_text = true
	_input_feedback_label.add_theme_color_override("font_color", COLOR_AMBER)
	_input_feedback_label.add_theme_font_size_override("font_size", 18)
	_input_feedback_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_input_feedback_label.visible = false
	_place(input_feedback_layout, _input_feedback_label, Rect2(0.0, 0.0, 488.0, 24.0))
	set_summary_visible(false)


## One action cell: 40px approved icon, primary key, name and live state. The
## button stays the only interactive node, so the existing signal contract is unchanged.
func _build_skill_cell(slot: Dictionary) -> Button:
	var node_name := String(slot["node_name"])
	var button := Button.new()
	button.name = node_name
	button.text = ""
	button.custom_minimum_size = SKILL_CELL_MINIMUM
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.pressed.connect(func() -> void: _request_for(node_name))
	_cell_buttons[node_name] = button

	var icon := TextureRect.new()
	icon.name = "SkillIcon"
	icon.position = Vector2(6.0, 6.0)
	icon.size = Vector2(SKILL_ICON_DISPLAY, SKILL_ICON_DISPLAY)
	icon.custom_minimum_size = Vector2(SKILL_ICON_DISPLAY, SKILL_ICON_DISPLAY)
	icon.texture = icons.icon(String(slot["slot_id"]))
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_SCALE
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(icon)
	_cell_icons[node_name] = icon

	var key_label := _named_label("PrimaryKey")
	key_label.text = String(SLOT_PRIMARY_KEYS[node_name])
	key_label.position = Vector2(52.0, 8.0)
	key_label.size = Vector2(46.0, 34.0)
	key_label.add_theme_font_size_override("font_size", SKILL_KEY_FONT_SIZE)
	key_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	key_label.add_theme_color_override("font_color", COLOR_AMBER)
	key_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(key_label)

	var state_label := _named_label("SkillState")
	state_label.position = Vector2(6.0, 70.0)
	state_label.size = SKILL_STATE_SIZE
	state_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	state_label.add_theme_font_size_override("font_size", SKILL_STATE_FONT_SIZE)
	# The combat face is deliberately one line. Complete authoritative wording stays
	# in the cell tooltip/detail instead of growing the dock over the battlefield.
	state_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	state_label.clip_text = true
	state_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(state_label)
	_cell_states[node_name] = state_label

	var progress := ProgressBar.new()
	progress.name = "CooldownProgress"
	progress.show_percentage = false
	progress.min_value = 0.0
	progress.max_value = 1.0
	progress.value = 0.0
	progress.position = Vector2(6.0, 96.0)
	progress.size = Vector2(92.0, 5.0)
	progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style_progress(progress, COLOR_BONE)
	button.add_child(progress)
	_cell_progress[node_name] = progress

	var name_label := _named_label("SkillName")
	name_label.text = String(slot["title"])
	name_label.position = Vector2(6.0, 42.0)
	name_label.size = Vector2(92.0, 24.0)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", SKILL_NAME_FONT_SIZE)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(name_label)
	return button


func _update_action_cells(snapshot: Dictionary, is_auto: bool, battle_over: bool) -> void:
	_skill_overrides = (snapshot.get("talent_skill_overrides", {}) as Dictionary).duplicate(true)
	var attack_cooldown := maxf(0.0, float(snapshot.get("attack_cooldown_seconds", 0.0)))
	var mark_cooldown := maxf(0.0, float(snapshot.get("hunter_mark_cooldown_seconds", 0.0)))
	var dash_cooldown := maxf(0.0, float(snapshot.get("dash_cooldown_seconds", 0.0)))
	var dodge_cooldown := maxf(0.0, float(snapshot.get("dodge_cooldown_seconds", 0.0)))
	var has_target := bool(snapshot.get("has_target", false))
	var target_in_range := bool(snapshot.get("target_in_range", false))
	# Attack targeting can be narrower than the arena's nearby-target query. Keep the
	# legacy values as API defaults so snapshots from before the pointer contract retain
	# both their wording and their enabled state.
	var attack_has_target := bool(snapshot.get("attack_has_target", has_target))
	var attack_target_in_range := bool(snapshot.get("attack_target_in_range", target_in_range))
	var attack_target_source := String(snapshot.get("attack_target_source", ""))
	var attack_target_status := String(snapshot.get("attack_target_status", "none"))
	var mark_equipped := bool(snapshot.get("hunter_mark_equipped", false))
	var dash_equipped := bool(snapshot.get("dash_equipped", false))
	var mark_in_range := bool(snapshot.get("mark_target_in_range", false))
	var mark_remaining := maxf(0.0, float(snapshot.get("hunter_mark_remaining_seconds", 0.0)))
	var marked_id := int(snapshot.get("marked_entity_id", 0))
	var marked_target_label := String(snapshot.get("marked_target_label", "")).strip_edges()
	if marked_target_label.is_empty():
		marked_target_label = "目标"
	var mark_active := marked_id > 0 and mark_remaining > 0.0
	var dash_active := bool(snapshot.get("dash_active", false))
	var attack_phase_label := String(snapshot.get("attack_phase_label", ""))
	var attack_held := bool(snapshot.get("attack_held", false))
	var attack_buffered := bool(snapshot.get("attack_buffered", false))
	var attack_request_open := bool(snapshot.get("attack_request_open", attack_cooldown <= 0.0))

	var attack_state := _action_state(is_auto, battle_over, attack_cooldown, attack_has_target, attack_target_in_range)
	if is_auto:
		if not attack_phase_label.is_empty():
			attack_state = "%s\n代理施放" % attack_phase_label
	elif attack_target_source == "pointer":
		var pointer_state := _pointer_target_state(attack_target_status, attack_has_target, attack_target_in_range)
		if not attack_phase_label.is_empty():
			attack_state = attack_phase_label
			if attack_buffered and pointer_state == "指针锁定":
				attack_state += "\n锁定已缓冲"
			elif not pointer_state.is_empty():
				attack_state += "\n%s" % pointer_state
		elif attack_buffered and pointer_state == "指针锁定":
			attack_state = "锁定已缓冲"
		elif attack_buffered:
			attack_state = "锁定已缓冲"
		elif attack_held:
			attack_state = pointer_state if not pointer_state.is_empty() else "指针锁定"
		elif not battle_over and attack_cooldown <= 0.0 and not pointer_state.is_empty():
			attack_state = pointer_state
	elif not attack_phase_label.is_empty():
		attack_state = attack_phase_label
		if attack_buffered:
			attack_state += "\n续发已缓冲"
		elif attack_held:
			attack_state += "\n按住续发"
	elif attack_buffered:
		attack_state = "续发已缓冲"
	elif attack_held:
		attack_state = "按住续发"
	var attack_active := not attack_phase_label.is_empty() or attack_buffered or (attack_held and not is_auto)
	if attack_target_source == "pointer" and (not attack_has_target or not attack_target_in_range) and attack_phase_label.is_empty():
		attack_active = false
	var attack_tone := "active" if attack_active else _tone_for(is_auto, battle_over, attack_cooldown > 0.0, attack_has_target and attack_target_in_range, true)
	var attack_disabled := is_auto or battle_over or not attack_request_open or not attack_has_target or not attack_target_in_range
	var attack_live_detail := _cooldown_text(attack_cooldown) if attack_cooldown > 0.0 else ""
	_apply_cell("Skill1Button", attack_state, attack_state, attack_tone, attack_disabled, attack_cooldown)

	var mark_state := "未装配"
	if mark_equipped:
		if is_auto:
			mark_state = "AUTO 已锁定"
		elif battle_over:
			mark_state = "战斗结束"
		elif mark_active:
			mark_state = "%s\n剩余 %.1fs" % [marked_target_label, mark_remaining]
		elif mark_cooldown > 0.0:
			mark_state = _cooldown_text(mark_cooldown)
		elif not has_target:
			mark_state = "无目标"
		elif not mark_in_range:
			mark_state = "射程外"
		else:
			mark_state = "就绪"
	var mark_detail := "%s · 剩余 %.1fs · 冷却 %.1fs" % [marked_target_label, mark_remaining, mark_cooldown] if mark_active else mark_state
	_apply_cell("Skill2Button", mark_state, mark_detail, _tone_for(is_auto, battle_over, mark_cooldown > 0.0, has_target and mark_in_range, mark_equipped), not mark_equipped or is_auto or battle_over or mark_cooldown > 0.0 or not has_target or not mark_in_range, mark_cooldown)

	var dash_state := "未装配"
	if dash_equipped:
		if is_auto:
			dash_state = "AUTO 已锁定"
		elif battle_over:
			dash_state = "战斗结束"
		elif dash_active:
			dash_state = "突袭中\n%s" % _cooldown_text(dash_cooldown)
		elif dash_cooldown > 0.0:
			dash_state = _cooldown_text(dash_cooldown)
		else:
			dash_state = "就绪"
	_apply_cell("Skill3Button", dash_state, dash_state, _tone_for(is_auto, battle_over, dash_cooldown > 0.0, true, dash_equipped), not dash_equipped or is_auto or battle_over or dash_cooldown > 0.0 or dash_active, dash_cooldown)

	var dodge_state := "代理控制" if is_auto else ("战斗结束" if battle_over else (_cooldown_text(dodge_cooldown) if dodge_cooldown > 0.0 else "就绪"))
	_apply_cell("DodgeButton", dodge_state, dodge_state, _tone_for(is_auto, battle_over, dodge_cooldown > 0.0, true, true), is_auto or battle_over or dodge_cooldown > 0.0, dodge_cooldown)

	_update_detail("Skill1Button", _skill_tooltip("piercing_arrow", attack_state, attack_live_detail))
	_update_detail("Skill2Button", _skill_tooltip("hunter_mark", mark_detail))
	_update_detail("Skill3Button", _skill_tooltip("dash", dash_state))
	_update_detail("DodgeButton", _skill_tooltip("basic_dodge", dodge_state))


func _skill_tooltip(skill_id: String, current_state: String, live_detail: String = "") -> String:
	var detail := _player_readable.format_skill(_current_skill(skill_id))
	if skill_id == "piercing_arrow":
		detail += "\n场上铜色箭头：角色当前发射方向"
	if skill_id == "basic_dodge":
		detail += "\n操作键：SHIFT · CTRL · RMB"
	if not live_detail.is_empty():
		detail += "\n实时%s" % live_detail
	return "%s\n当前状态：%s" % [detail, current_state]


func _current_skill(skill_id: String) -> Dictionary:
	var skill: Dictionary = _skill_registry.get_skill(skill_id).duplicate(true)
	for key in (_skill_overrides.get(skill_id, {}) as Dictionary):
		skill[key] = _skill_overrides[skill_id][key]
	return skill


func _request_for(node_name: String) -> void:
	match node_name:
		"Skill1Button":
			skill_one_requested.emit()
		"Skill2Button":
			skill_two_requested.emit()
		"Skill3Button":
			skill_three_requested.emit()
		"DodgeButton":
			dodge_requested.emit()


func _apply_cell(node_name: String, text: String, detail: String, tone: String, disabled: bool, cooldown_remaining: float) -> void:
	var button: Button = _cell_buttons.get(node_name)
	var icon: TextureRect = _cell_icons.get(node_name)
	var state_label: Label = _cell_states.get(node_name)
	var progress: ProgressBar = _cell_progress.get(node_name)
	if button == null or icon == null or state_label == null or progress == null:
		return
	button.disabled = disabled
	state_label.text = _compact_cell_state(node_name, text)
	state_label.add_theme_font_size_override("font_size", SKILL_STATE_FONT_SIZE)
	state_label.add_theme_color_override("font_color", COLOR_AMBER if tone in ["ready", "active"] else (COLOR_PROXY if tone == "locked" else (COLOR_NEUTRAL if tone in ["unequipped", "blocked"] else COLOR_BONE)))
	icon.modulate = Color.WHITE if not disabled or tone == "active" else Color(0.55, 0.55, 0.58, 0.85)
	_style_action_button(button, disabled, tone)
	_apply_cooldown_progress(node_name, cooldown_remaining, tone)
	_update_detail(node_name, detail)


## The bar is elapsed cooldown, not elapsed availability: it fills as the skill
## approaches ready. The remaining seconds always come from the authoritative
## snapshot; only the denominator is read from the already-loaded skill registry.
## If registry data is unavailable the bar stays empty rather than inventing a
## denominator or a percentage.
func _apply_cooldown_progress(node_name: String, cooldown_remaining: float, tone: String) -> void:
	var progress: ProgressBar = _cell_progress.get(node_name)
	if progress == null:
		return
	if progress.value > 0.0 and tone != "cooldown":
		progress.value = 0.0
	if progress.visible and tone != "cooldown":
		progress.visible = false
	if tone == "cooldown":
		var seconds := maxf(0.0, cooldown_remaining)
		var slot := {}
		for candidate in SKILL_SLOTS:
			if String(candidate["node_name"]) == node_name:
				slot = candidate
				break
		var skill := _current_skill(String(slot.get("slot_id", "")))
		var maximum := float(int(skill.get("cooldown_ticks", 0))) / float(maxi(1, _skill_registry.ticks_per_second))
		progress.visible = seconds > 0.0 and maximum >= seconds
		if seconds > 0.0 and maximum >= seconds:
			progress.value = clampf((maximum - seconds) / maximum, 0.0, 1.0)
		elif progress.value > 0.0:
			progress.value = 0.0


## Critical state is a composition change: warning words, the hero bar fill and
## the hero panel border all change together, so it does not rely on colour alone.
func _apply_hero_health_state(hero_ratio: float) -> void:
	var critical := hero_ratio <= 0.30
	_style_progress(_hero_health_bar, COLOR_WARNING if critical else COLOR_BONE)
	var style := _panel_style(5.0, 0.90)
	if critical:
		style.border_color = COLOR_WARNING
		style.set_border_width_all(3)
	_hero_frame.add_theme_stylebox_override("panel", style)


func _compact_cell_state(node_name: String, text: String) -> String:
	if not text.contains("\n"):
		return _short_cell_phrase(text)
	var lines := text.split("\n", false, 1)
	var first := String(lines[0]).strip_edges()
	var second := String(lines[1]).strip_edges() if lines.size() > 1 else ""
	match second:
		"按住续发":
			return "%s·续发" % first
		"续发已缓冲", "锁定已缓冲":
			return "缓冲" if first.is_empty() else "%s·缓冲" % first
		"指针锁定":
			return "%s·锁定" % first
		"代理施放":
			return "%s·代理" % first
	if second.begins_with("剩余 "):
		return "标记 %s" % second.trim_prefix("剩余 ")
	if node_name == "Skill3Button" and second.begins_with("冷却 "):
		return "突袭 %s" % second.trim_prefix("冷却 ")
	return first


## The combat face uses short established phrases and a separate numeric line.
## This is copy compression only; the complete authoritative state remains in the
## public skill_cell_detail value and the cell tooltip.
func _short_cell_phrase(value: String) -> String:
	if value.begins_with("冷却 "):
		var suffix := value.trim_prefix("冷却 ")
		if suffix.begins_with("<"):
			return "冷 <0.1s"
		return "冷 %s" % suffix
	return String({
		"就绪": "就绪",
		"无目标": "无目标",
		"射程外": "射程外",
		"未装配": "未装",
		"战斗结束": "结束",
		"代理控制": "代理",
		"AUTO 已锁定": "AUTO",
		"未锁定目标": "未锁",
		"锁定射程外": "锁距外",
		"锁定已失效": "锁失效",
		"指针锁定": "锁定",
		"续发已缓冲": "缓冲",
		"锁定已缓冲": "缓冲",
	}.get(value, value))


func _update_detail(node_name: String, detail: String) -> void:
	_cell_details[node_name] = detail
	var button: Button = _cell_buttons.get(node_name)
	if button == null:
		return
	button.tooltip_text = detail if icon_pending_reason.is_empty() else "%s\n%s" % [detail, icon_pending_reason]


func _tone_for(is_auto: bool, battle_over: bool, on_cooldown: bool, in_reach: bool, equipped: bool) -> String:
	if not equipped:
		return "unequipped"
	if is_auto:
		return "locked"
	if battle_over:
		return "ended"
	if on_cooldown:
		return "cooldown"
	if not in_reach:
		return "blocked"
	return "ready"


func _style_action_button(button: Button, disabled: bool, tone: String) -> void:
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


func _elite_mechanic_text(raw: String) -> String:
	var parts: Array[String] = []
	for entry in raw.split(","):
		match entry.strip_edges():
			"periodic_barrier:active": parts.append("屏障开启·绕行等空隙")
			"periodic_barrier:open": parts.append("屏障消退·集中攻击")
			"summon_reinforcements:ready": parts.append("召援待触发·精英半血召援")
			"summon_reinforcements:used": parts.append("援军已出现·留意新增敌人")
	return "\n".join(parts)


func _encounter_status_text(raw: String) -> String:
	var names := {"moving_fireline":"移动火线", "exposed_ground_zone":"危险地带", "ground-zone":"危险地带", "periodic_barrier":"周期屏障", "summon_reinforcements":"召集援军"}
	var phases := {"warning":"预警中", "windup":"预警中", "active":"生效中", "inactive":"未激活", "cooldown":"间歇", "idle":"间歇", "open":"可攻击", "used":"已召集", "ready":"待触发"}
	if raw in ["", "无"]: return "无"
	var parts: Array[String] = []
	for entry in raw.split(","):
		var pair := entry.strip_edges().split(":")
		var title := String(names.get(pair[0], "特殊效果"))
		parts.append(title + (" · " + String(phases.get(pair[1], "")) if pair.size() > 1 and phases.has(pair[1]) else ""))
	return "、".join(parts)


func _update_summary(snapshot: Dictionary) -> void:
	_summary_parameters_label.text = "公开参数  p=%.2f  ·  寿命 %.2fs  ·  距离 %.0f" % [float(snapshot.get("p", 0.0)), float(snapshot.get("lifetime", 0.0)), float(snapshot.get("distance", 0.0))]
	var growth := _growth_label(String(snapshot.get("growth_type", ""))) if bool(snapshot.get("growth_verified", false)) else "未验证"
	_summary_growth_label.text = "增长类型  %s  ·  迭代长度 g=%d" % [growth, int(snapshot.get("g", 0))]
	if bool(snapshot.get("growth_snapshot_details", false)):
		var generation_time := float(snapshot.get("growth_generation_time", 0.0))
		var remainder := maxf(0.0, float(snapshot.get("lifetime", 0.0)) - float(snapshot.get("g", 0)) * generation_time)
		_summary_growth_label.text += "\n每代 %.3fs · 剩余寿命 %.3fs" % [generation_time, remainder]
	var block := "最近代理阻断  %s" % _proxy_failure_text(snapshot.get("last_proxy_failure", {})) if String(snapshot.get("selected_mode", "Manual")).to_upper() == "AUTO" else "代理状态  手动模式 · 未运行"
	_summary_block_label.text = "%s\n完整战斗反馈  %s" % [block, _feedback_text]


## The active playfield wins when an actor reaches the lower-right input pad.
## Preserve every actionable icon/state, while fading only its nonessential
## backing and collapsing the repeated feedback sentence.
func _set_action_edge_occlusion(occluded: bool) -> void:
	if _action_bar == null:
		return
	_action_edge_occluded = occluded
	_action_bar.add_theme_stylebox_override("panel", _panel_style(5.0, 0.38 if occluded else 0.78))
	_feedback_label.visible = false


## The strip keeps the meaning of the line and drops the two cumulative totals that the
## summary already carries: the running boss damage and the defeated counter. Only those
## two known keys are removed. A warning, a refusal reason or any other sentence the
## authority sends is passed through whole, so nothing is hidden behind a short label.
func _compact_feedback(value: String) -> String:
	var kept: Array[String] = []
	for part in value.split(" · "):
		var segment := part.strip_edges()
		if segment.is_empty() or segment.begins_with("对 Boss 伤害") or segment.begins_with("已击败"):
			continue
		kept.append(segment)
	return value.strip_edges() if kept.is_empty() else " · ".join(kept)


func _action_state(is_auto: bool, battle_over: bool, cooldown: float, has_target: bool, in_range: bool) -> String:
	if is_auto:
		return "代理控制"
	if battle_over:
		return "战斗结束"
	if cooldown > 0.0:
		return _cooldown_text(cooldown)
	if not has_target:
		return "无目标"
	if not in_range:
		return "射程外"
	return "就绪"


func _pointer_target_state(status: String, has_target: bool, in_range: bool) -> String:
	match status:
		"locked":
			return "指针锁定"
		"out_of_range":
			return "锁定射程外"
		"lost":
			return "锁定已失效"
		"no_pointer_target":
			return "未锁定目标"
	if not has_target:
		return "未锁定目标"
	if not in_range:
		return "锁定射程外"
	return "指针锁定"


## One simulated tick is 33ms, so a single remaining tick must not be printed as
## the ambiguous "0.0s"; the cell either shows the real seconds or is explicit
## that less than a tenth of a second remains.
func _cooldown_text(seconds: float) -> String:
	return "冷却 <0.1s" if seconds < 0.05 else "冷却 %.1fs" % seconds


func _proxy_failure_text(value: Variant) -> String:
	if not value is Dictionary or (value as Dictionary).is_empty():
		return "无"
	var failure := value as Dictionary
	var category := String(failure.get("category", "unknown"))
	var reason := String(failure.get("reason", "unknown"))
	var localized_category: String = String({
		"cooldown": "冷却",
		"timing": "时机",
		"range": "射程",
		"target": "目标",
	}.get(category, category))
	var localized_reason := "技能尚未就绪" if reason in ["skill is not ready", "skill not ready"] else reason
	return "[%s] %s" % [localized_category, localized_reason]


func _growth_label(value: String) -> String:
	return {
		"convergent": "收敛 / CONVERGENT",
		"critical": "临界 / CRITICAL",
		"exponential": "指数 / EXPONENTIAL",
	}.get(value.to_lower(), value.to_upper())


func _plain_number(value: float) -> String:
	return String.num(value, 0) if is_equal_approx(value, roundf(value)) else String.num(value, 1)


func _card(node_name: String, top_left: Vector2, bottom_right: Vector2, anchor_x: float = 0.0, anchor_y: float = 0.0, anchor_x_end: float = -1.0, anchor_y_end: float = -1.0, vertical_margin: float = 9.0, opacity: float = 0.92) -> PanelContainer:
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
	card.add_theme_stylebox_override("panel", _panel_style(vertical_margin, opacity))
	add_child(card)
	return card


func _panel_in(node_name: String, parent: Control, rect: Rect2, vertical_margin: float, opacity: float) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = node_name
	panel.position = rect.position
	panel.size = rect.size
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.add_theme_stylebox_override("panel", _panel_style(vertical_margin, opacity))
	parent.add_child(panel)
	return panel


## Plain holder Control inside a panel: it carries no minimum size, so the panel
## height is exactly what the anchors/offsets say and never grows with content.
func _layout(node_name: String, panel: PanelContainer) -> Control:
	var holder := Control.new()
	holder.name = node_name
	holder.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.add_child(holder)
	return holder


## Remove any previous rect before the ScrollContainer's VBox owns row layout.
func _summary_row(label: Label) -> Label:
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


func _place(parent: Control, control: Control, rect: Rect2, interactive: bool = false) -> void:
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


func _panel_style(vertical_margin: float = 9.0, opacity: float = 0.92) -> StyleBoxFlat:
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


func _critical_health_visible() -> bool:
	if _hero_frame == null or not _hero_frame.visible or _hero_health_bar == null or not _hero_health_bar.visible:
		return false
	return _hero_health_bar.max_value > 0.0 and _hero_health_bar.value / _hero_health_bar.max_value <= 0.30


func _transparent_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	return style


func _style_progress(bar: ProgressBar, fill_color: Color) -> void:
	var background := StyleBoxFlat.new()
	background.bg_color = COLOR_INK
	background.border_color = COLOR_NEUTRAL
	background.set_border_width_all(1)
	var fill := StyleBoxFlat.new()
	fill.bg_color = fill_color
	fill.border_color = COLOR_BONE
	fill.set_border_width_all(1)
	bar.add_theme_stylebox_override("background", background)
	bar.add_theme_stylebox_override("fill", fill)


func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 18)
	_apply_text_style(label, COLOR_BONE)
	return label


func _muted_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	_apply_text_style(label, COLOR_NEUTRAL)
	return label


func _named_label(node_name: String) -> Label:
	var label := Label.new()
	label.name = node_name
	_apply_text_style(label, COLOR_BONE)
	return label


func _apply_text_style(label: Label, color: Color) -> void:
	## Keep fill, outline and face together so later labels cannot accidentally
	## inherit the serif shell font or a soft shadow that muddies small CJK glyphs.
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", HUD_TEXT_OUTLINE)
	label.add_theme_constant_override("outline_size", HUD_TEXT_OUTLINE_SIZE)
	label.add_theme_constant_override("shadow_offset_x", 0)
	label.add_theme_constant_override("shadow_offset_y", 0)
	if ui_font != null:
		label.add_theme_font_override("font", ui_font)
