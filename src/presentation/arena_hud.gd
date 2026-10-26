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
##    out-of-range cues) and the actionable room-loot cue share one strip, docked
##    left of the action bar so they can never cover the four action icons or the
##    opening-room banner. Specific authoritative receipts always take priority.
##    Routine attack/count feedback stays collapsed into the TAB summary.
##  * the strip numbers the concept makes prominent are the cells that already
##    existed: HeroHealthLabel above the hero bar and BossHpLabel above the target
##    bar. Raw scientific totals, cumulative damage, layout metadata and the
##    mode/proxy explanation are not deleted, they sit in the summary panel that
##    the TAB key or the Summary button opens (ART_BIBLE 12: "large formulas, long affixes, and proxy
##    pipelines go in expandable details").
##  * a cell hidden with the summary is moved into that panel instead of staying at
##    a stale offset, so no invisible control can pass a containment check.

signal skill_one_requested
signal skill_two_requested
signal skill_three_requested
signal dodge_requested
signal return_requested

const SkillIconsScript = preload("res://src/presentation/combat_skill_icons.gd")
const StyleScript = preload("res://src/presentation/arena_hud/hud_style.gd")
const TextScript = preload("res://src/presentation/arena_hud/hud_text.gd")
const InterfaceScript = preload("res://src/presentation/arena_hud/hud_interface.gd")
const SkillCellsScript = preload("res://src/presentation/arena_hud/hud_skill_cells.gd")

const COLOR_NEUTRAL: Color = StyleScript.COLOR_NEUTRAL
const COLOR_BONE: Color = StyleScript.COLOR_BONE
const COLOR_AMBER: Color = StyleScript.COLOR_AMBER
const COLOR_WARNING: Color = StyleScript.COLOR_WARNING
const COLOR_PROXY: Color = StyleScript.COLOR_PROXY

## Mode chips. The mode is locked for the whole active battle, for Manual exactly as for
## AUTO, because a contract's instruction stream cannot be switched mid-fight; only AUTO
## also disables the manual skill keys. The concept writes the mode plainly and adds a
## lock mark, so neither state leans on colour alone (ART_BIBLE 12.2).
const MODE_MANUAL_LOCKED: String = "MANUAL [Locked]"
const MODE_AUTO_LOCKED: String = "AUTO [Locked]"

var icons = SkillIconsScript.new()
var icon_pending_reason: String = ""
var ui_font: FontFile
## Node construction, the four action cells and the style/label factories live in
## collaborators under src/presentation/arena_hud/; they write the widgets below
## onto this control and re-emit the cell presses through the signals above.
var _style: StyleScript = StyleScript.new(self)
var _cells = SkillCellsScript.new(self, _style)
var _interface = InterfaceScript.new(self, _style)
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
var _return_button: Button
var _action_bar: PanelContainer
var _hero_frame: PanelContainer
var _boss_frame: PanelContainer
var _utility_frame: PanelContainer
var _action_edge_occluded := false
## Routine feedback copy: authoritative, but only readable in the TAB summary or a
## cell tooltip. The old always-on strip slot is retired to keep the default screen
## low-clutter; short input notices use the dedicated transient strip instead.
var _feedback_text: String = ""
## Last authoritative line the authority sent for the optional resource warning. The
## HUD never invents one; the default strip shows any authoritative non-empty value.
var _resource_state_text: String = ""


func _init() -> void:
	_cells.load_registry()
	_interface.build()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## One snapshot, applied in the order the strip reads: hero card, room heading,
## target card, encounter rules, mode chips, notices, then the action cells and
## the summary readout.
func present(snapshot: Dictionary) -> void:
	var mode := String(snapshot.get("selected_mode", "Manual")).to_upper()
	var is_auto := mode == "AUTO"
	var battle_over := bool(snapshot.get("battle_over", false))
	var has_boss := bool(snapshot.get("has_boss", true))
	var objective_label := String(snapshot.get("objective_label", snapshot.get("objective_id", "clear")))
	var hero_ratio := _present_hero(snapshot)
	_present_room_heading(snapshot, has_boss, objective_label, battle_over)
	_present_target_card(snapshot, has_boss, objective_label)
	_present_encounter_rules(snapshot, battle_over)
	_present_mode(snapshot, mode, is_auto, battle_over)
	_present_notices(snapshot)
	_cells.update(snapshot, is_auto, battle_over)
	_apply_hero_health_state(hero_ratio)
	_update_summary(snapshot)
	_set_action_edge_occlusion(bool(snapshot.get("action_edge_occluded", false)))


## Hero life, key status and the optional resource line. Returns the life ratio
## the critical-state styling is driven from.
func _present_hero(snapshot: Dictionary) -> float:
	var player_health := clampf(float(snapshot.get("player_health", 0.0)), 0.0, float(snapshot.get("player_health_max", 100.0)))
	var player_health_max := maxf(1.0, float(snapshot.get("player_health_max", 100.0)))
	_hero_health_label.text = "HP  %s / %s" % [TextScript.plain_number(player_health), TextScript.plain_number(player_health_max)]
	_hero_health_bar.max_value = player_health_max
	_hero_health_bar.value = player_health
	var key_status := String(snapshot.get("key_status", "Stable"))
	var hero_ratio := player_health / player_health_max
	_hero_status_label.text = "⚠ Critical" if hero_ratio <= 0.30 else key_status
	# No resource is fabricated: this line only appears when an authority sends it.
	# It remains with the hero status even when the optional details are folded.
	_resource_state_text = String(snapshot.get("resource_state", ""))
	_resource_label.text = _resource_state_text
	_hero_status_label.tooltip_text = ("⚠ Critical · Key Status  %s" % key_status) if hero_ratio <= 0.30 else ("Key Status  %s" % key_status)
	_apply_resource_visibility()
	return hero_ratio


## The authored room name, or the older diagnostic snapshots' layout/objective
## wording when they do not carry the authored room presentation fields.
func _room_display_name(snapshot: Dictionary) -> String:
	var room_display_name := String(snapshot.get("room_display_name", "")).strip_edges()
	if room_display_name.is_empty():
		room_display_name = String(snapshot.get("layout_id", snapshot.get("objective_label", "Arena")))
	return room_display_name


## The boss-card heading ("Room n / m · name · objective", measured-fit) and the
## opening-room entry cue that temporarily replaces the target state line.
func _present_room_heading(snapshot: Dictionary, has_boss: bool, objective_label: String, battle_over: bool) -> void:
	_encounter_heading.text = "Boss  Threshold Colossus" if has_boss else "Target  %s" % objective_label
	var has_room_progress := snapshot.has("room_count")
	var room_count := maxi(1, int(snapshot.get("room_count", 1)))
	var room_number := clampi(int(snapshot.get("room_index", 0)) + 1, 1, room_count)
	var room_display_name := _room_display_name(snapshot)
	var has_room_display_name := snapshot.has("room_display_name") and not String(snapshot.get("room_display_name", "")).strip_edges().is_empty()
	var room_entry_hint := String(snapshot.get("room_entry_hint", "Watch for attack telegraphs"))
	if has_room_progress:
		var room_title := "Threshold Colossus" if has_boss else room_display_name
		var room_objective := "Boss" if has_boss else objective_label
		if not has_boss and not has_room_display_name:
			# Keep diagnostic snapshots and older callers on the compact contract;
			# live embedded rooms publish the authored scene name explicitly.
			_encounter_heading.text = "Room %d / %d · %s" % [room_number, room_count, room_objective]
		else:
			_encounter_heading.text = "Room %d / %d · %s · %s" % [room_number, room_count, room_title, room_objective]
	_encounter_heading.tooltip_text = _encounter_heading.text
	## Full boss-layout width for both cases; then measured-fit so the authored
	## name is never clipped at the render width.
	_encounter_heading.size.x = 342.0 if has_boss else 456.0
	StyleScript.fit_heading(_encounter_heading)
	if has_room_progress and has_room_display_name and not has_boss:
		var compact_objective := String({
			"Clear All Targets": "Clear foes",
			"Clear Enemies": "Clear foes",
		}.get(objective_label, objective_label))
		_encounter_heading.text = "Room %d/%d · %s · %s" % [room_number, room_count, room_display_name, compact_objective]
		var heading_font := _encounter_heading.get_theme_font("font")
		if heading_font.get_string_size(_encounter_heading.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			_encounter_heading.get_theme_font_size("font_size")).x > _encounter_heading.size.x:
			_encounter_heading.text = "Room %d/%d · %s" % [room_number, room_count, compact_objective]
		StyleScript.fit_heading(_encounter_heading)
	# A read-only entry cue uses the room's existing elapsed time and never delays input.
	_room_start_label.visible = has_room_progress and not has_boss and not battle_over and float(snapshot.get("room_elapsed_seconds", 99.0)) < 1.8
	_room_start_label.text = "Entering Room %d · %s" % [room_number, room_entry_hint]
	_room_start_label.tooltip_text = room_entry_hint
	_boss_state_label.visible = not _room_start_label.visible


## The target card and its summary rows: boss or current-target name, value, the
## true same-layer ratio when comparable, damage, and the live target state line.
func _present_target_card(snapshot: Dictionary, has_boss: bool, objective_label: String) -> void:
	var attack_target_label := String(snapshot.get("attack_target_label", "")).strip_edges()
	var attack_target_health := maxf(0.0, float(snapshot.get("attack_target_health", 0.0)))
	var attack_target_maximum_health := maxf(0.0, float(snapshot.get("attack_target_maximum_health", 0.0)))
	var has_live_attack_target := not attack_target_label.is_empty() and attack_target_maximum_health > 0.0 and attack_target_health > 0.0
	var attack_target_in_range := bool(snapshot.get("attack_target_in_range", false))
	_boss_name_label.text = "Threshold Colossus" if has_boss else "Current Target"
	_boss_value_label.text = "%s / %s" % [String(snapshot.get("boss_remaining", "—")), String(snapshot.get("boss_maximum", "—"))] if has_boss else "Target %s · Alive %d" % [objective_label, int(snapshot.get("living_targets", 0))]
	var ratio_known := bool(snapshot.get("boss_ratio_known", false))
	_boss_health_bar.value = clampf(float(snapshot.get("boss_ratio", 0.0)), 0.0, 1.0) * 100.0 if ratio_known else 0.0
	_boss_health_bar.visible = has_boss
	# The default strip shows the true ratio when the shared layer makes it comparable
	# and says so explicitly when it is not; the two totals behind it stay one Tab away.
	_boss_hp_label.text = "%.1f%%" % _boss_health_bar.value if ratio_known else "Ratios Not Comparable"
	_boss_hp_label.visible = has_boss
	_boss_ratio_label.text = ("Actual Same-Layer Ratio  %.1f%%" % _boss_health_bar.value if ratio_known else "Different Structural Layers · Ratios Not Comparable") if has_boss else "Watch for enemy attack telegraphs"
	# Ordinary rooms already expose their objective and living count in
	# BossValueLabel.  The old fallback repeated that same line in the damage
	# slot, making the open battle report look like two separate facts. Keep the
	# damage row for the Boss contract where it has a distinct meaning, and fold
	# it out of the ordinary-room summary entirely.
	_boss_damage_label.visible = has_boss
	_boss_damage_label.text = "Boss Damage  %s" % String(snapshot.get("damage", "0")) if has_boss else ""
	if has_boss:
		_boss_state_label.text = "Actual Ratio Known" if ratio_known else "Ratios Not Comparable"
		_boss_state_label.add_theme_color_override("font_color", COLOR_NEUTRAL)
	elif has_live_attack_target:
		var target_range := "In Range" if attack_target_in_range else "Out of Range"
		_boss_state_label.text = "%s · %s/%s · %s" % [
			attack_target_label,
			TextScript.plain_number(attack_target_health),
			TextScript.plain_number(attack_target_maximum_health),
			target_range,
		]
		# The target line drives the immediate shooting decision. Use the light
		# body colour for a legal shot and the amber warning colour when the
		# selected target is outside the authoritative range.
		_boss_state_label.add_theme_color_override("font_color", COLOR_BONE if attack_target_in_range else COLOR_AMBER)
	else:
		_boss_state_label.text = "Targets Remaining  %d" % int(snapshot.get("living_targets", 0))
		_boss_state_label.add_theme_color_override("font_color", COLOR_NEUTRAL)
	_boss_state_label.tooltip_text = ("Current Target  " if not has_boss and has_live_attack_target else "") + _boss_state_label.text


## Arena rules in the summary and the elite mechanic cue.
func _present_encounter_rules(snapshot: Dictionary, battle_over: bool) -> void:
	var room_concept := String(snapshot.get("room_concept", ""))
	var room_landmark := String(snapshot.get("room_landmark", ""))
	var room_exit_hint := String(snapshot.get("room_exit_hint", ""))
	var hazards := String(snapshot.get("hazard_status", "None"))
	var elites := String(snapshot.get("elite_status", "None"))
	_summary_encounter_label.text = "Arena: %s · %s\n%s\nHazards: %s\nElites: %s" % [_room_display_name(snapshot), room_landmark, room_concept, TextScript.encounter_status_text(hazards), TextScript.encounter_status_text(elites)]
	if not room_exit_hint.is_empty():
		_summary_encounter_label.text += "\nExit: %s" % room_exit_hint
	# Mechanic windows come from authority, including their clearing on elite defeat.
	# Keep them on screen even during the entry cue, without replacing room or life.
	_elite_mechanic_label.text = "" if battle_over else TextScript.elite_mechanic_text(elites)
	_elite_mechanic_frame.visible = not _elite_mechanic_label.text.is_empty()
	_elite_mechanic_frame.offset_bottom = 96.0 + (72.0 if "\n" in _elite_mechanic_label.text else 42.0)
	_elite_mechanic_label.add_theme_color_override("font_color", COLOR_AMBER if "periodic_barrier:active" in elites else COLOR_BONE)


## The mode chip, its detail row and the proxy line.
func _present_mode(snapshot: Dictionary, mode: String, is_auto: bool, battle_over: bool) -> void:
	# The mode is locked for the whole active battle and is switchable again once it ends,
	# which is the invariant the previous strip already carried. Manual stays selectable
	# (its skills keep working) but is still named as mode-locked; only AUTO disables the
	# skill keys. No new snapshot field is invented for this: battle_over already says it.
	var mode_locked := not battle_over
	var mode_chip := (MODE_AUTO_LOCKED if is_auto else MODE_MANUAL_LOCKED) if mode_locked else mode
	var mode_detail := "%s · Combat Ended" % mode_chip if battle_over else ("%s · Input Locked" % mode_chip if is_auto else "%s · Input Available" % mode_chip)
	_mode_label.text = mode_chip
	_mode_label.add_theme_color_override("font_color", COLOR_PROXY if is_auto else COLOR_AMBER)
	_mode_state_label.text = mode_detail
	if is_auto:
		var prediction := String(snapshot.get("proxy_prediction", "unknown")).to_upper()
		var refusal := TextScript.proxy_failure_text(snapshot.get("last_proxy_failure", {}))
		_proxy_label.text = "Proxy %s · Manual Input Stopped" % prediction if refusal == "None" else "Last Rejection  %s" % refusal
	else:
		_proxy_label.text = "Manual Input · Proxy Inactive"


## Routine combat feedback and the one transient input-notice strip.
func _present_notices(snapshot: Dictionary) -> void:
	_feedback_text = String(snapshot.get("feedback", "Waiting for First Hit"))
	_feedback_label.text = "Combat Feedback  %s" % TextScript.compact_feedback(_feedback_text)
	_feedback_label.tooltip_text = _feedback_text
	var input_feedback := String(snapshot.get("input_feedback", ""))
	## A range-rejection notice is a receipt for a past input, not the live
	## state: once the same target reads in range, showing "Out of Range" beside it
	## contradicts the strip (visual backlog). Live state wins immediately.
	if bool(snapshot.get("attack_target_in_range", false)) and input_feedback.to_lower().contains("out of range"):
		input_feedback = ""
	var loot_prompt_text := String(snapshot.get("loot_prompt_text", ""))
	var loot_prompt_state := String(snapshot.get("loot_prompt_state", "none"))
	var visible_input_feedback := input_feedback if not input_feedback.is_empty() else loot_prompt_text
	## The whole card shows and hides with the notice: no permanent blank
	## rectangle lingers over the battlefield.
	_input_feedback_card.visible = not visible_input_feedback.is_empty()
	_input_feedback_label.text = visible_input_feedback
	_input_feedback_label.tooltip_text = visible_input_feedback
	_input_feedback_label.visible = not visible_input_feedback.is_empty()
	_input_feedback_label.add_theme_color_override("font_color", COLOR_PROXY if input_feedback.is_empty() and loot_prompt_state == "near" else COLOR_AMBER)


func update_state(snapshot: Dictionary) -> void:
	present(snapshot)


func set_summary_visible(value: bool) -> void:
	_summary_panel.visible = value
	## Compact face: mouse users read the report purpose without hover; the
	## keyboard shortcut lives in the tooltip. ~95px min fits the 116px cell.
	_summary_toggle_button.text = "Report ▲" if value else "Report ▼"
	_summary_stack_note.text = "Combat Details"


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


## Full authoritative copy for one cell, including what the compact layout cannot
## fit. Never returns an invented value.
func skill_cell_detail(node_name: String) -> String:
	return _cells.detail_for(node_name)


func skill_icon(node_name: String) -> Texture2D:
	return _cells.icon_for(node_name)


## Read-only evidence for tests and scene inspection. Values remain snapped to
## actual control geometry; no ideal layout is reported.
func skill_cooldown_progress(node_name: String) -> float:
	return _cells.cooldown_progress_for(node_name)


func _apply_resource_visibility() -> void:
	if _resource_label == null:
		return
	_resource_label.visible = not _resource_state_text.is_empty()
	# The strip cell clips so it can never widen the hero column; the tooltip carries the
	# complete authoritative line when it does not fit.
	_resource_label.tooltip_text = _resource_state_text if _resource_label.visible else ""


func is_pointer_over_interface(point: Vector2 = Vector2(-INF, -INF)) -> bool:
	var viewport := get_viewport()
	if viewport == null:
		return false
	var has_event_point := not is_inf(point.x) and not is_inf(point.y)
	var pointer := point if has_event_point else viewport.get_mouse_position()
	# Input's mouse-button state is global, even when a SubViewportContainer
	# correctly rejects a click in the letterbox. Exclude those pixels from the
	# held-fire path as well, using the same viewport-space pointer as the HUD.
	if not viewport.get_visible_rect().has_point(pointer):
		return true
	if has_event_point:
		# Main receives the physical event before Control hover state is guaranteed
		# to be updated. Classify the event's own viewport coordinate so a click
		# injected by a window backend, replay, or accessibility device cannot
		# inherit the previous frame's HUD hover and suppress a world shot.
		return _point_hits_interactive_control(self, pointer)
	var hovered := viewport.gui_get_hovered_control()
	return hovered != null and (hovered == self or is_ancestor_of(hovered))


func _point_hits_interactive_control(node: Node, point: Vector2) -> bool:
	if node is Control:
		var control := node as Control
		if control != self and control.visible and control.mouse_filter != Control.MOUSE_FILTER_IGNORE and control.get_global_rect().has_point(point):
			return true
	for child: Node in node.get_children():
		if _point_hits_interactive_control(child, point):
			return true
	return false


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
		"hero_health_warning": _hero_status_label != null and _hero_status_label.visible and _hero_status_label.text.begins_with("⚠ Critical"),
		"skill_controls_visible": _cells.all_controls_visible(),
	}


func _visible_rect(control: Control) -> Rect2:
	return control.get_global_rect() if control != null and control.visible else Rect2()


func _rect_array(rect: Rect2) -> Array[int]:
	return [roundi(rect.position.x), roundi(rect.position.y), roundi(rect.size.x), roundi(rect.size.y)]


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


## Critical state is a composition change: warning words, the hero bar fill and
## the hero panel border all change together, so it does not rely on colour alone.
func _apply_hero_health_state(hero_ratio: float) -> void:
	var critical := hero_ratio <= 0.30
	StyleScript.style_progress(_hero_health_bar, COLOR_WARNING if critical else COLOR_BONE)
	var style := StyleScript.panel_style(5.0, 0.90)
	if critical:
		style.border_color = COLOR_WARNING
		style.set_border_width_all(3)
	_hero_frame.add_theme_stylebox_override("panel", style)


func _update_summary(snapshot: Dictionary) -> void:
	_summary_parameters_label.text = "Public Stats  p=%.2f  ·  Lifetime %.2fs  ·  Range %.0f" % [float(snapshot.get("p", 0.0)), float(snapshot.get("lifetime", 0.0)), float(snapshot.get("distance", 0.0))]
	var growth := TextScript.growth_label(String(snapshot.get("growth_type", ""))) if bool(snapshot.get("growth_verified", false)) else "Unverified"
	_summary_growth_label.text = "Growth Type  %s  ·  Iteration Length g=%d" % [growth, int(snapshot.get("g", 0))]
	if bool(snapshot.get("growth_snapshot_details", false)):
		var generation_time := float(snapshot.get("growth_generation_time", 0.0))
		var remainder := maxf(0.0, float(snapshot.get("lifetime", 0.0)) - float(snapshot.get("g", 0)) * generation_time)
		_summary_growth_label.text += "\nGeneration %.3fs · Remaining Lifetime %.3fs" % [generation_time, remainder]
	var block := "Last Proxy Block  %s" % TextScript.proxy_failure_text(snapshot.get("last_proxy_failure", {})) if String(snapshot.get("selected_mode", "Manual")).to_upper() == "AUTO" else "Proxy State  Manual Mode · Inactive"
	_summary_block_label.text = "%s\nFull Combat Feedback  %s" % [block, _feedback_text]


## The active playfield wins when an actor reaches the lower-right input pad.
## Preserve every actionable icon/state, while fading only its nonessential
## backing and collapsing the repeated feedback sentence.
func _set_action_edge_occlusion(occluded: bool) -> void:
	if _action_bar == null:
		return
	_action_edge_occluded = occluded
	_action_bar.add_theme_stylebox_override("panel", StyleScript.panel_style(5.0, 0.38 if occluded else 0.78))
	_feedback_label.visible = false


func _critical_health_visible() -> bool:
	if _hero_frame == null or not _hero_frame.visible or _hero_health_bar == null or not _hero_health_bar.visible:
		return false
	return _hero_health_bar.max_value > 0.0 and _hero_health_bar.value / _hero_health_bar.max_value <= 0.30
