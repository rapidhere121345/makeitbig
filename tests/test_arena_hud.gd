extends SceneTree

## Contract for the concept-faithful combat HUD (docs/art-production/concepts/v0.9-p1-complete/
## ART_BIBLE.md section 12, panel 05 COMBAT of 10_ui_screens.png).
##
## Two states are asserted, not one:
##  * DEFAULT (summary collapsed) = hero life, the one live target, the mode chip,
##    the handover controls, and no raw science. Every strip control is visible and
##    inside the top strip; no detail control is on screen at all.
##  * EXPANDED (TAB or Summary) = the raw totals, cumulative damage, layout metadata and
##    mode/proxy explanation, all still present under their original cell names.

const ArenaHudScript := preload("res://src/presentation/arena_hud.gd")
const FrameBuilderScript := preload("res://src/presentation/combat_presentation_frame_builder.gd")
const DomainFixture := preload("res://tests/helpers/player_domain_fixture.gd")
const PresentationSnapshot := preload("res://src/presentation/combat_presentation_snapshot.gd")
const Encounter := preload("res://src/game/encounter_director.gd")
const CombatEnemyStateScript := preload("res://src/runtime/world/combat_enemy_state.gd")
const ShellThemeScript := preload("res://src/presentation/shell_theme.gd")
const SKILL_CELLS: Array[String] = ["Skill1Button", "Skill2Button", "Skill3Button", "DodgeButton"]
## Cells that carry the default strip. All of them must be visible, inside the top
## strip and disjoint, because the concept reads the strip as one band.
const DEFAULT_STRIP_CELLS: Array[String] = [
	"HeroHealthLabel",
	"HeroHealthBar",
	"HeroStatusLabel",
	# The optional resource warning: visible only when the authority sent a line, but
	# part of the default strip either way, never hidden behind the summary.
	"ResourceLabel",
	"EncounterHeading",
	"BossHpLabel",
	"BossHealthBar",
	"BossStateLabel",
	"ModeLabel",
	"ReturnButton",
	"SummaryToggleButton",
]
## Cells the default strip hands to the openable detail. They keep their names and
## their authoritative copy; only their carrier changes.
const SUMMARY_CELLS: Array[String] = [
	"BossNameLabel",
	"BossValueLabel",
	"BossRatioLabel",
	"BossDamageLabel",
	"EncounterRulesLabel",
	"ModeStateLabel",
	"ProxyLabel",
	"SummaryParametersLabel",
	"SummaryGrowthLabel",
	"SummaryBlockLabel",
]
## Longest authoritative copy a snapshot can publish, used to prove the expanded
## panel fits the space between the strip and the action bar.
const SUMMARY_MEASURE_SNAPSHOT := {
	"boss_remaining": "9.551e11",
	"boss_maximum": "1.0e12",
	"damage": "4.495e10",
	"layout_id": "rect-arena",
	"objective_id": "hunt_elite",
	"objective_label": "Hunt Elites",
	"hazard_status": "ground-zone:warning",
	"elite_status": "barrier:active",
	"selected_mode": "Auto",
	"growth_type": "exponential",
	"proxy_prediction": "stable",
	"last_proxy_failure": {"category": "cooldown", "reason": "skill is not ready"},
	"feedback": "Piercing Arrow Hit · Boss Damage 4.495e10 · Defeated 0",
	"resource_state": "Arrows 12 / 24",
}
## world_polish_v01 ships each icon as its own authored 32x32 PNG, so every
## cell's atlas region is the whole texture.
const SKILL_ICON_CELLS := {
	"Skill1Button": Rect2(0.0, 0.0, 32.0, 32.0),
	"Skill2Button": Rect2(0.0, 0.0, 32.0, 32.0),
	"Skill3Button": Rect2(0.0, 0.0, 32.0, 32.0),
	"DodgeButton": Rect2(0.0, 0.0, 32.0, 32.0),
}
const SKILL_NAMES := {
	"Skill1Button": "Piercing",
	"Skill2Button": "Mark",
	"Skill3Button": "Dash",
	"DodgeButton": "Dodge",
}
const SESSION_LAUNCHER_OCCUPIED_PIXELS: int = 122 * 38


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	var hud := ArenaHudScript.new()
	root.add_child(hud)
	await process_frame
	_test_room_progress(hud, failures)
	_test_input_feedback_strip(hud, failures)
	_test_loot_prompt(hud, failures)
	_test_compact_english_readouts(hud, failures)

	var required_nodes: Array[String] = [
		"HeroFrame",
		"BossFrame",
		"UtilityFrame",
		"HeroHealthBar",
		"BossHealthBar",
		"BossDamageLabel",
		"Skill1Button",
		"Skill2Button",
		"Skill3Button",
		"DodgeButton",
		"ModeLabel",
		"SummaryPanel",
		"SummaryToggleButton",
		"ReturnButton",
		"ActionRow",
	]
	for node_name in required_nodes:
		_expect(hud.find_child(node_name, true, false) != null, "missing stable node %s" % node_name, failures)
	await process_frame
	var top_bar := hud.find_child("TopBar", true, false) as PanelContainer
	var action_bar := hud.find_child("ActionBar", true, false) as PanelContainer
	var hero_frame := hud.find_child("HeroFrame", true, false) as PanelContainer
	var boss_frame := hud.find_child("BossFrame", true, false) as PanelContainer
	var utility_frame := hud.find_child("UtilityFrame", true, false) as PanelContainer
	_expect(top_bar != null, "missing TopBar strip", failures)
	_expect(action_bar != null, "missing ActionBar", failures)
	_expect(hero_frame != null and boss_frame != null and utility_frame != null, "top carrier lost one of its three visible panels", failures)
	if top_bar != null:
		_expect(top_bar.size.y <= 90.0, "top HUD strip must stay at or under 90px, is %.1f" % top_bar.size.y, failures)
		var carrier_style := top_bar.get_theme_stylebox("panel") as StyleBoxFlat
		_expect(carrier_style != null and is_zero_approx(carrier_style.bg_color.a), "TopBar compatibility carrier must stay transparent", failures)
	if action_bar != null:
		_expect(action_bar.size.y <= 104.5 and action_bar.size.x >= 440.0 and action_bar.size.x <= 448.0, "action dock must stay in its single-row lower-right envelope, is %s" % str(action_bar.size), failures)
	var frame := Rect2(Vector2.ZERO, Vector2(1280.0, 720.0))
	_expect(hud.size == frame.size, "HUD is not laid out on the 1280x720 frame: %s" % str(hud.size), failures)
	var top_panels: Array[PanelContainer] = [hero_frame, boss_frame, utility_frame]
	for panel in top_panels:
		if panel == null:
			continue
		_expect(panel.visible and frame.encloses(panel.get_global_rect()), "top panel %s is hidden or leaves the frame" % panel.name, failures)
		if top_bar != null:
			_expect(top_bar.get_global_rect().grow(1.0).encloses(panel.get_global_rect()), "top panel %s leaves TopBar" % panel.name, failures)
	for i in range(top_panels.size()):
		for j in range(i + 1, top_panels.size()):
			if top_panels[i] != null and top_panels[j] != null:
				_expect(not top_panels[i].get_global_rect().intersects(top_panels[j].get_global_rect()), "top panels %s and %s overlap" % [top_panels[i].name, top_panels[j].name], failures)
	if hero_frame != null:
		for node_name in ["HeroHealthLabel", "HeroHealthBar", "HeroStatusLabel", "ResourceLabel"]:
			_expect(hero_frame.is_ancestor_of(hud.find_child(node_name, true, false)), "HeroFrame does not own %s" % node_name, failures)
	if boss_frame != null:
		for node_name in ["EncounterHeading", "BossHpLabel", "BossHealthBar", "BossStateLabel"]:
			_expect(boss_frame.is_ancestor_of(hud.find_child(node_name, true, false)), "BossFrame does not own %s" % node_name, failures)
	if utility_frame != null:
		for node_name in ["ModeLabel", "ReturnButton", "SummaryToggleButton"]:
			_expect(utility_frame.is_ancestor_of(hud.find_child(node_name, true, false)), "UtilityFrame does not own %s" % node_name, failures)
	# --- default strip: the concept's sparse top band -----------------------------
	var summary_panel := hud.find_child("SummaryPanel", true, false) as PanelContainer
	_expect(summary_panel != null and not summary_panel.visible, "summary must be collapsed by default", failures)
	var strip_rects := {}
	for control_name in DEFAULT_STRIP_CELLS:
		var control := hud.find_child(control_name, true, false) as Control
		_expect(control != null, "default strip lost %s" % control_name, failures)
		if control == null:
			continue
		var control_rect := control.get_global_rect()
		strip_rects[control_name] = control_rect
		if control_name == "ResourceLabel":
			# Not a cell of its own: the optional warning rides in the hero column and is
			# hidden only because this snapshot carries no authoritative resource line.
			_expect(not control.visible and control.text.is_empty(), "HUD invented a resource warning", failures)
		else:
			_expect(control.visible, "default strip cell %s is not visible" % control_name, failures)
		_expect(frame.encloses(control_rect), "default strip control %s leaves the frame: %s" % [control_name, str(control_rect)], failures)
		if top_bar != null:
			_expect(top_bar.get_global_rect().grow(1.0).encloses(control_rect), "default strip control %s leaves the strip: %s" % [control_name, str(control_rect)], failures)
	var strip_names := strip_rects.keys()
	for i in range(strip_names.size()):
		for j in range(i + 1, strip_names.size()):
			var left := strip_names[i] as String
			var right := strip_names[j] as String
			# A ProgressBar reports a stylebox floor taller than its declared rect, so only
			# same-kind cells are compared for overlap; every other pair is covered by the
			# column containment above.
			if _same_kind(hud, left, right):
				_expect(not (strip_rects[left] as Rect2).intersects(strip_rects[right] as Rect2), "strip cells %s and %s overlap" % [left, right], failures)
	# The raw detail is nowhere on the default screen: not a label, and not even a
	# hidden control left behind at an old strip offset.
	var default_copy := _visible_copy(hud)
	for control_name in SUMMARY_CELLS:
		var detail := hud.find_child(control_name, true, false) as Control
		_expect(detail != null, "summary lost %s" % control_name, failures)
		if detail == null:
			continue
		_expect(not _on_screen(detail), "default HUD must not show the raw detail cell %s" % control_name, failures)
		if summary_panel != null:
			_expect(summary_panel.is_ancestor_of(detail), "hidden cell %s is not owned by the folded detail panel" % control_name, failures)
	for forbidden in ["9.551e11", "1.0e12", "4.495e10", "rectangle_arena", "hunt_elite"]:
		_expect(not (forbidden in default_copy), "default HUD still prints raw detail %s" % forbidden, failures)
	_expect("Boss Damage" not in default_copy, "default HUD still prints the cumulative damage line", failures)
	_expect("Manual Input" not in default_copy and "Proxy Inactive" not in default_copy, "default HUD still prints the proxy explanation", failures)
	if action_bar != null:
		var bar_rect := action_bar.get_global_rect()
		_expect(frame.encloses(bar_rect), "action bar leaves the frame: %s" % str(bar_rect), failures)
		var action_row := hud.find_child("ActionRow", true, false) as GridContainer
		_expect(action_row != null and action_row.columns == 4, "action dock must use one row with four columns", failures)
		var first_y := -1.0
		var action_rects: Array[Rect2] = []
		for cell_name in SKILL_CELLS:
			var cell := _cell(hud, cell_name)
			if cell == null:
				continue
			_expect(bar_rect.grow(1.0).encloses(cell.get_global_rect()), "action cell %s leaves the action bar: %s" % [cell_name, str(cell.get_global_rect())], failures)
			if first_y < 0.0:
				first_y = cell.get_global_rect().position.y
			_expect(is_equal_approx(cell.get_global_rect().position.y, first_y), "action cell %s is not in the single row" % cell_name, failures)
			action_rects.append(cell.get_global_rect())
		for i in range(action_rects.size()):
			for j in range(i + 1, action_rects.size()):
				_expect(not action_rects[i].intersects(action_rects[j]), "single-row action cells %d and %d overlap" % [i, j], failures)
	var hero_status := hud.find_child("HeroStatusLabel", true, false) as Label
	if hero_status != null:
		var hud_font: Font = hero_status.get_theme_font("font")
		_expect(hud_font != null and hud_font.has_char("R".unicode_at(0)), "HUD text is not drawn with the packaged SC font", failures)
		_expect(not (hud_font is SystemFont), "HUD must not fall back to a SystemFont", failures)
		_expect(hud_font == ShellThemeScript.data_font(), "combat HUD should use the medium sans data face", failures)
		_expect(hero_status.get_theme_constant("outline_size") == 1, "combat HUD text lost its crisp one-pixel outline", failures)
	_expect((hud.find_child("FeedbackLabel", true, false) as Label).get_theme_font_size("font_size") >= 18, "feedback text fell below the 18px floor", failures)
	for utility_name in ["ReturnButton", "SummaryToggleButton"]:
		var utility_button := hud.find_child(utility_name, true, false) as Button
		_expect(utility_button != null and utility_button.get_theme_font_size("font_size") >= 18, "%s text fell below the 18px floor" % utility_name, failures)
		if utility_button == null:
			continue
		## Collapsed-state containment: the theme-padded minimum must fit the
		## declared cell, and the global rect must stay inside UtilityFrame.
		var minimum := utility_button.get_combined_minimum_size()
		_expect(minimum.x <= utility_button.size.x + 0.5,
			"%s needs %s but only has %s wide" % [utility_name, str(minimum), str(utility_button.size)], failures)
		_expect(utility_frame != null and utility_frame.get_global_rect().encloses(utility_button.get_global_rect()),
			"%s escapes the utility frame at %s" % [utility_name, str(utility_button.get_global_rect())], failures)

	_expect(String(hud.icon_pending_reason).is_empty(), "approved skill icons did not load: %s" % hud.icon_pending_reason, failures)
	for node_name in SKILL_CELLS:
		var button := _cell(hud, node_name)
		_expect(button != null, "missing skill cell %s" % node_name, failures)
		if button == null:
			continue
		var icon := button.get_node_or_null("SkillIcon") as TextureRect
		var state_label := button.get_node_or_null("SkillState") as Label
		var name_label := button.get_node_or_null("SkillName") as Label
		var key_label := button.get_node_or_null("PrimaryKey") as Label
		_expect(icon != null and state_label != null and name_label != null and key_label != null, "cell %s lost its icon/key/state/name labels" % node_name, failures)
		if icon == null or state_label == null or name_label == null:
			continue
		_expect(icon.custom_minimum_size == Vector2(32.0, 32.0) and icon.size == Vector2(32.0, 32.0), "cell %s icon is not displayed at the authored 32px native size" % node_name, failures)
		_expect(icon.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "cell %s icon is not nearest-neighbour" % node_name, failures)
		_expect(icon.stretch_mode == TextureRect.STRETCH_SCALE and icon.expand_mode == TextureRect.EXPAND_IGNORE_SIZE, "cell %s icon does not scale from the native 32px cell" % node_name, failures)
		var atlas := hud.skill_icon(node_name) as AtlasTexture
		_expect(atlas != null, "cell %s has no approved atlas icon" % node_name, failures)
		if atlas != null:
			_expect(atlas.region == SKILL_ICON_CELLS[node_name], "cell %s uses atlas region %s instead of its approved 32x32 cell" % [node_name, str(atlas.region)], failures)
			_expect(atlas.atlas != null and atlas.atlas.get_width() == 32 and atlas.atlas.get_height() == 32, "cell %s atlas is not the authored 32x32 world_polish_v01 icon" % node_name, failures)
		_expect(name_label.text == SKILL_NAMES[node_name], "cell %s name copy is wrong" % node_name, failures)
		_expect(name_label.get_theme_font_size("font_size") >= 18, "cell %s name fell below the 18px readability floor" % node_name, failures)
		_expect(state_label.get_theme_font_size("font_size") >= 18, "cell %s state fell below the 18px readability floor" % node_name, failures)
		_expect(key_label != null and key_label.get_theme_font_size("font_size") >= 18, "cell %s key fell below the 18px readability floor" % node_name, failures)
		_expect(key_label != null and not key_label.text.is_empty(), "cell %s lost its real key label" % node_name, failures)
		_expect(String(button.text).is_empty(), "cell %s must not duplicate copy on the button itself" % node_name, failures)
		var name_font: Font = name_label.get_theme_font("font")
		_expect(name_font != null and name_font.has_char("P".unicode_at(0)), "cell %s name is not drawn with the packaged SC font" % node_name, failures)
		_expect_cell_text_layout(hud, node_name, failures)

	var manual := _snapshot()
	hud.present(manual)
	var layout_report: Dictionary = hud.combat_layout_report()
	_expect(String(layout_report.get("top_node", "")) == "TopBar" and String(layout_report.get("bottom_node", "")) == "ActionBar", "HUD layout report lost stable carrier names: %s" % str(layout_report), failures)
	_expect(layout_report.get("top_panel_nodes", []) == ["HeroFrame", "BossFrame", "UtilityFrame"], "layout report lost top-panel identities: %s" % str(layout_report), failures)
	_expect((layout_report.get("top_panel_rects", []) as Array).size() == 3 and bool(layout_report.get("top_panels_disjoint", false)), "layout report cannot verify three disjoint top panels: %s" % str(layout_report), failures)
	var reported_top_area := int(layout_report.get("top_occupied_pixels", 0))
	var expected_top_area := roundi(hero_frame.get_global_rect().get_area() + boss_frame.get_global_rect().get_area() + utility_frame.get_global_rect().get_area())
	_expect(reported_top_area == expected_top_area and reported_top_area < roundi(top_bar.get_global_rect().get_area()), "top occupied area must count only the three opaque panels: %s" % str(layout_report), failures)
	_expect(int(layout_report.get("bottom_occupied_pixels", 0)) <= 46208, "compact action dock still covers too much battle area: %s" % str(layout_report), failures)
	_expect((float(layout_report.get("visible_hud_pixels", 0)) + SESSION_LAUNCHER_OCCUPIED_PIXELS) / 921600.0 <= 0.14, "default HUD plus session launcher exceeds the 14 percent screen budget: %s" % str(layout_report), failures)
	_expect(int(layout_report.get("open_battle_pixels", 0)) >= 792000, "HUD did not leave the required open battle stage: %s" % str(layout_report), failures)
	var battle_center := Rect2(Vector2(320.0, 180.0), Vector2(640.0, 360.0))
	for occluder_name in ["HeroFrame", "BossFrame", "UtilityFrame", "ActionBar"]:
		var occluder := hud.find_child(occluder_name, true, false) as Control
		_expect(occluder == null or not occluder.get_global_rect().intersects(battle_center), "%s enters the central battle stage" % occluder_name, failures)
	_expect(bool(layout_report.get("critical_visible", false)), "layout report says critical HP/status became hidden", failures)
	_expect(bool(layout_report.get("skill_controls_visible", false)), "layout report says a skill control became hidden", failures)
	var hero_bar := hud.find_child("HeroHealthBar", true, false) as ProgressBar
	var boss_bar := hud.find_child("BossHealthBar", true, false) as ProgressBar
	var skill_one := _cell(hud, "Skill1Button")
	var skill_two := _cell(hud, "Skill2Button")
	var skill_three := _cell(hud, "Skill3Button")
	var dodge := _cell(hud, "DodgeButton")
	var mode_label := hud.find_child("ModeLabel", true, false) as Label
	var summary := hud.find_child("SummaryPanel", true, false) as PanelContainer
	var summary_toggle := hud.find_child("SummaryToggleButton", true, false) as Button
	_expect(is_equal_approx(hero_bar.value, 72.0), "manual snapshot did not update hero HP", failures)
	_expect(is_equal_approx(boss_bar.value, 25.0), "manual snapshot did not update true boss ratio", failures)
	var normal_health_report: Dictionary = hud.combat_layout_report()
	_expect(not bool(normal_health_report.get("critical_health", true)) and not bool(normal_health_report.get("hero_health_warning", true)), "healthy hero is mislabeled critical", failures)
	manual["player_health"] = 30.0
	hud.present(manual)
	var critical_health_report: Dictionary = hud.combat_layout_report()
	_expect(bool(critical_health_report.get("critical_health", false)) and bool(critical_health_report.get("hero_health_warning", false)), "30 percent hero HP did not enter the critical state", failures)
	_expect(_label_text(hud, "HeroStatusLabel").begins_with("⚠ Critical"), "critical hero state is not named with a warning shape", failures)
	manual["player_health"] = 31.0
	hud.present(manual)
	_expect(not bool(hud.combat_layout_report().get("critical_health", true)) and not _label_text(hud, "HeroStatusLabel").begins_with("⚠ Critical"), "critical hero state did not reset above the threshold", failures)
	manual["player_health"] = 72.0
	hud.present(manual)
	_expect(_state(hud, "Skill1Button") == "Ready" and not skill_one.disabled, "ready manual skill 1 state is wrong", failures)
	_expect(_icon_modulate(hud, "Skill1Button") == Color.WHITE, "ready icon must not be dimmed", failures)
	var ready_border := _button_border_color(skill_one)
	_expect(_state(hud, "Skill2Button") == "Empty" and skill_two.disabled, "skill slot 2 must be visibly unequipped and disabled", failures)
	_expect(_state(hud, "Skill3Button") == "Empty" and skill_three.disabled, "skill slot 3 must be visibly unequipped and disabled", failures)
	_expect(_state(hud, "DodgeButton") == "Ready" and not dodge.disabled, "manual dodge state is wrong", failures)
	_expect(_key(hud, "Skill1Button") == "Space" and _key(hud, "DodgeButton") == "Shift", "primary key labels are wrong", failures)
	manual["action_edge_occluded"] = true
	hud.present(manual)
	var occluded_report: Dictionary = hud.combat_layout_report()
	_expect(bool(occluded_report.get("action_edge_occluded", false)), "HUD did not expose its action-edge fade state", failures)
	_expect(bool(occluded_report.get("critical_visible", false)), "edge fade hid critical HP/status", failures)
	_expect(bool(occluded_report.get("skill_controls_visible", false)), "edge fade hid a skill control", failures)
	_expect(not skill_one.disabled and not dodge.disabled, "edge fade disabled a ready skill control", failures)
	manual.erase("action_edge_occluded")
	hud.present(manual)
	# The strip keeps the true ratio; the two totals behind it stay one Tab away.
	_expect(_label_text(hud, "HeroHealthLabel") == "HP  72 / 100", "hero strip copy is wrong: %s" % _label_text(hud, "HeroHealthLabel"), failures)
	_expect(_label_text(hud, "BossHpLabel") == "25.0%", "boss strip copy is wrong: %s" % _label_text(hud, "BossHpLabel"), failures)
	_expect("Actual Ratio Known" in _label_text(hud, "BossStateLabel"), "known-ratio state must be explicit", failures)
	# The selection is locked for as long as the battle runs, for Manual exactly as for
	# AUTO. That is the invariant the previous strip carried, and it needs no new field.
	_expect(mode_label.text == "MANUAL [Locked]", "concept mode chip must state the locked selection, is %s" % mode_label.text, failures)
	_expect("[Locked]" in _visible_copy(hud), "the mode lock is not on the default screen", failures)
	manual["battle_over"] = true
	hud.present(manual)
	_expect(mode_label.text == "MANUAL", "a finished battle must release the mode chip, is %s" % mode_label.text, failures)
	_expect("Combat Ended" in _label_text(hud, "ModeStateLabel"), "finished battle must not advertise usable combat keys", failures)
	manual["battle_over"] = false
	hud.present(manual)
	_expect(_label_text(hud, "FeedbackLabel") == "Combat Feedback  Target Hit", "strip feedback must stay the short meaning only: %s" % _label_text(hud, "FeedbackLabel"), failures)
	_expect("750K" not in _label_text(hud, "FeedbackLabel"), "strip feedback still carries the cumulative total", failures)
	_expect(not summary.visible, "summary must be hidden by default", failures)
	_expect("Unverified" in _all_copy(summary), "unverified growth state is missing", failures)
	summary_toggle.emit_signal("pressed")
	for layout_frame in range(4): await process_frame
	_expect(summary.visible, "summary toggle did not reveal panel", failures)
	_expect(summary_toggle.text.contains("▲"), "expanded summary toggle must show the open state", failures)
	_expect(summary_toggle.text.contains("Report"), "summary toggle lost its Report face", failures)
	_expect(summary_toggle.tooltip_text.contains("Battle Report") and summary_toggle.tooltip_text.contains("Tab"),
		"summary toggle lost the Battle Report Tab wording", failures)
	## Expanded-state containment: the toggle must stay inside UtilityFrame and
	## the window at both compact 1280 and 1600 frames.
	var expanded_minimum := summary_toggle.get_combined_minimum_size()
	_expect(expanded_minimum.x <= summary_toggle.size.x + 0.5,
		"expanded toggle needs %s but only has %s wide" % [str(expanded_minimum), str(summary_toggle.size)], failures)
	_expect((hud.find_child("UtilityFrame", true, false) as PanelContainer).get_global_rect().encloses(summary_toggle.get_global_rect()),
		"expanded toggle escapes the utility frame", failures)
	_expect(summary_toggle.get_global_rect().end.x <= hud.size.x + 0.5,
		"expanded toggle escapes the window right edge", failures)
	_check_expanded_panel(hud, summary, top_bar, frame, failures)
	var expanded_copy := _visible_copy(summary)
	for expected in ["Threshold Colossus", "250K / 1.00M", "Actual Same-Layer Ratio", "Boss Damage", "750K", "Hazard", "Elite", "Unverified", "Manual Mode"]:
		_expect(expected in expanded_copy, "expanded summary lost %s" % expected, failures)
	_expect("750K" in (hud.find_child("BossDamageLabel", true, false) as Label).text, "short boss damage is missing", failures)
	_expect("Unequipped" in (hud.find_child("Skill2Button", true, false) as Button).tooltip_text, "expanded panel must not change the action-cell contract", failures)
	# TAB is the second carrier of the same toggle, and the open panel must survive a
	# paused-snapshot refresh unchanged.
	var tab := InputEventKey.new()
	tab.keycode = KEY_TAB
	tab.pressed = true
	hud._input(tab)
	_expect(not summary.visible, "one Tab press must close the summary even with a focused control", failures)
	hud._input(tab)
	_expect(summary.visible, "the second Tab press must re-open the summary", failures)
	hud.present(manual)
	for layout_frame in range(4): await process_frame
	_expect(summary.visible and summary_toggle.text.contains("▲"), "a paused-snapshot refresh must not disturb the open summary", failures)
	_check_expanded_panel(hud, summary, top_bar, frame, failures)
	summary_toggle.emit_signal("pressed")
	_expect(not summary.visible and summary_toggle.text.contains("▼"), "summary toggle did not collapse the panel", failures)

	manual["growth_verified"] = true
	manual["growth_type"] = "exponential"
	manual["attack_cooldown_seconds"] = 0.7
	manual["dodge_cooldown_seconds"] = 1.2
	hud.present(manual)
	_expect("EXPONENTIAL".to_lower() in _all_copy(summary).to_lower(), "verified growth type is missing", failures)
	_expect(_state(hud, "Skill1Button") == "CD 0.7s" and skill_one.disabled, "skill cooldown state is wrong", failures)
	_expect(_state(hud, "DodgeButton") == "CD 1.2s" and dodge.disabled, "dodge cooldown state is wrong", failures)
	var skill_progress := skill_one.get_node_or_null("CooldownProgress") as ProgressBar
	var dodge_progress := dodge.get_node_or_null("CooldownProgress") as ProgressBar
	_expect(skill_progress != null and dodge_progress != null, "skill cells lost their cooldown progress carriers", failures)
	_expect(is_zero_approx(hud.skill_cooldown_progress("Skill1Button")) and not skill_progress.visible, "cooldown longer than the authoritative base cooldown must not invent a progress ratio", failures)
	_expect(is_zero_approx(hud.skill_cooldown_progress("DodgeButton")) and not dodge_progress.visible, "cooldown longer than the authoritative base cooldown must not invent a progress ratio", failures)
	manual["attack_cooldown_seconds"] = 0.2
	manual["dodge_cooldown_seconds"] = 0.6
	hud.present(manual)
	_expect(absf(hud.skill_cooldown_progress("Skill1Button") - (13.0 / 30.0 - 0.2) / (13.0 / 30.0)) <= 0.005, "piercing arrow cooldown progress is not truthful from registry cooldown: %.4f" % hud.skill_cooldown_progress("Skill1Button"), failures)
	_expect(absf(hud.skill_cooldown_progress("DodgeButton") - (35.0 / 30.0 - 0.6) / (35.0 / 30.0)) <= 0.005, "dodge cooldown progress is not truthful from registry cooldown: %.4f" % hud.skill_cooldown_progress("DodgeButton"), failures)
	_expect(_icon_modulate(hud, "Skill1Button") != Color.WHITE, "cooling icon must be dimmed without baked text", failures)
	_expect(_button_border_color(skill_one) != ready_border, "cooldown must change the action-cell border tone as well as text/icon brightness", failures)
	manual["attack_cooldown_seconds"] = 1.0 / 30.0
	hud.present(manual)
	_expect(_state(hud, "Skill1Button") == "CD <0.1s" and skill_one.disabled, "sub-tick cooldown must not be printed as an ambiguous 0.0s", failures)

	var action_snapshot := _snapshot()
	action_snapshot["attack_cooldown_seconds"] = 0.3
	action_snapshot["attack_phase_label"] = "Draw"
	action_snapshot["attack_request_open"] = false
	hud.present(action_snapshot)
	_expect(_state(hud, "Skill1Button") == "Draw" and skill_one.disabled and _icon_modulate(hud, "Skill1Button") == Color.WHITE, "active windup was hidden behind a cooldown state", failures)
	_expect(_button_border_color(skill_one) != ready_border, "active state must change the action-cell border tone", failures)
	_expect("Current State: Draw" in skill_one.tooltip_text, "manual single attack tooltip did not reuse the final state copy", failures)
	_expect_skill_state_fits(hud, "Skill1Button", failures)
	_expect(is_zero_approx(hud.skill_cooldown_progress("Skill1Button")), "active windup must not present a cooldown progress value", failures)
	action_snapshot["attack_held"] = true
	hud.present(action_snapshot)
	_expect(_state(hud, "Skill1Button") == "Repeating", "held manual attack did not name continuous fire control", failures)
	_expect("Current State: Draw\nHold to Repeat" in skill_one.tooltip_text, "held manual attack tooltip did not reuse the final state copy", failures)
	_expect_skill_state_fits(hud, "Skill1Button", failures)
	action_snapshot["attack_phase_label"] = "Recovery"
	action_snapshot["attack_buffered"] = true
	action_snapshot["attack_request_open"] = true
	hud.present(action_snapshot)
	_expect(_state(hud, "Skill1Button") == "Buffered" and not skill_one.disabled, "held recovery did not expose the continuous-fire buffer", failures)
	_expect("Current State: Recovery\nNext Shot Buffered" in skill_one.tooltip_text, "buffered held attack tooltip did not reuse the final state copy", failures)
	_expect_skill_state_fits(hud, "Skill1Button", failures)
	action_snapshot["attack_phase_label"] = ""
	hud.present(action_snapshot)
	_expect(_state(hud, "Skill1Button") == "Buffered", "phase-free buffered attack did not keep the continuous-fire buffer copy", failures)
	_expect_skill_state_fits(hud, "Skill1Button", failures)

	# Old snapshots remain byte-for-byte compatible, while assisted targeting keeps the
	# same continuous-fire copy even after the new target contract is present.
	var legacy_targeting := _snapshot()
	legacy_targeting["has_target"] = false
	hud.present(legacy_targeting)
	_expect(_state(hud, "Skill1Button") == "No Target" and skill_one.disabled, "legacy no-target fallback changed its copy or enabled state", failures)
	legacy_targeting["has_target"] = true
	legacy_targeting["target_in_range"] = false
	hud.present(legacy_targeting)
	_expect(_state(hud, "Skill1Button") == "Too Far" and skill_one.disabled, "legacy range fallback changed its copy or enabled state", failures)

	var assisted_targeting := _snapshot()
	assisted_targeting["attack_target_source"] = "assisted"
	assisted_targeting["attack_target_status"] = "locked"
	assisted_targeting["attack_target_entity_id"] = 17
	assisted_targeting["attack_has_target"] = true
	assisted_targeting["attack_target_in_range"] = true
	assisted_targeting["attack_phase_label"] = "Draw"
	assisted_targeting["attack_held"] = true
	hud.present(assisted_targeting)
	_expect(_state(hud, "Skill1Button") == "Repeating", "assisted targeting changed the established held copy", failures)
	assisted_targeting["attack_buffered"] = true
	hud.present(assisted_targeting)
	_expect(_state(hud, "Skill1Button") == "Buffered", "assisted targeting changed the established buffered copy", failures)

	var pointer_targeting := _snapshot()
	pointer_targeting["attack_target_source"] = "pointer"
	pointer_targeting["attack_target_status"] = "locked"
	pointer_targeting["attack_target_entity_id"] = 23
	pointer_targeting["attack_has_target"] = true
	pointer_targeting["attack_target_in_range"] = true
	pointer_targeting["attack_phase_label"] = "Draw"
	pointer_targeting["attack_held"] = true
	hud.present(pointer_targeting)
	_expect(_state(hud, "Skill1Button") == "Locked" and not skill_one.disabled, "active pointer attack did not expose its locked target", failures)
	_expect("Current State: Draw\nPointer Lock" in skill_one.tooltip_text, "pointer tooltip did not reuse the final locked copy", failures)
	_expect_skill_state_fits(hud, "Skill1Button", failures)
	pointer_targeting["attack_buffered"] = true
	hud.present(pointer_targeting)
	_expect(_state(hud, "Skill1Button") == "Buffered", "buffered pointer attack did not expose its locked buffer", failures)
	_expect("Current State: Draw\nTarget Lock Buffered" in skill_one.tooltip_text, "pointer tooltip did not reuse the final buffered copy", failures)
	_expect_skill_state_fits(hud, "Skill1Button", failures)
	pointer_targeting["attack_phase_label"] = ""
	hud.present(pointer_targeting)
	_expect(_state(hud, "Skill1Button") == "Buffered", "phase-free pointer buffer lost its locked-target meaning", failures)
	_expect_skill_state_fits(hud, "Skill1Button", failures)
	pointer_targeting["attack_buffered"] = false
	hud.present(pointer_targeting)
	_expect(_state(hud, "Skill1Button") == "Locked", "held pointer attack did not keep its explicit lock state", failures)
	_expect_skill_state_fits(hud, "Skill1Button", failures)

	var pointer_states := {
		"no_pointer_target": "No Locked Target",
		"lost": "Target Lock Expired",
		"out_of_range": "Locked Target Out of Range",
	}
	for status in pointer_states:
		pointer_targeting["attack_phase_label"] = ""
		pointer_targeting["attack_held"] = false
		pointer_targeting["attack_buffered"] = false
		pointer_targeting["attack_target_status"] = status
		pointer_targeting["attack_has_target"] = status == "out_of_range"
		pointer_targeting["attack_target_in_range"] = false
		hud.present(pointer_targeting)
		var full_pointer_state := String(pointer_states[status])
		var expected_pointer_state := String({"No Locked Target": "No Lock", "Target Lock Expired": "Lost Lock", "Locked Target Out of Range": "Too Far"}[full_pointer_state])
		_expect(_state(hud, "Skill1Button") == expected_pointer_state and skill_one.disabled, "pointer status %s did not render as a disabled %s" % [status, expected_pointer_state], failures)
		_expect("Current State: %s" % full_pointer_state in skill_one.tooltip_text, "pointer status %s tooltip did not reuse the final copy" % status, failures)
		_expect_skill_state_fits(hud, "Skill1Button", failures)

	# A nearby assisted candidate must not enable an empty, lost or out-of-range pointer
	# request. The attack-specific booleans are authoritative for this button.
	pointer_targeting["has_target"] = true
	pointer_targeting["target_in_range"] = true
	pointer_targeting["attack_target_status"] = "no_pointer_target"
	pointer_targeting["attack_has_target"] = false
	pointer_targeting["attack_target_in_range"] = false
	pointer_targeting["attack_held"] = true
	hud.present(pointer_targeting)
	_expect(skill_one.disabled and _state(hud, "Skill1Button") == "No Lock" and _icon_modulate(hud, "Skill1Button") != Color.WHITE, "nearby enemies incorrectly made an empty pointer request look available", failures)
	pointer_targeting["attack_held"] = false
	pointer_targeting["attack_target_status"] = "locked"
	pointer_targeting["attack_has_target"] = true
	pointer_targeting["attack_target_in_range"] = true
	hud.present(pointer_targeting)
	_expect(not skill_one.disabled and _state(hud, "Skill1Button") == "Locked", "a valid pointer lock did not enable the attack", failures)
	_expect_skill_state_fits(hud, "Skill1Button", failures)

	var equipped := _snapshot()
	equipped["hunter_mark_equipped"] = true
	equipped["dash_equipped"] = true
	equipped["mark_target_in_range"] = true
	hud.present(equipped)
	_expect(_state(hud, "Skill2Button") == "Ready" and not skill_two.disabled, "equipped hunter mark is not ready", failures)
	_expect(_state(hud, "Skill3Button") == "Ready" and not skill_three.disabled, "equipped dash is not ready", failures)
	equipped["hunter_mark_cooldown_seconds"] = 2.4
	equipped["dash_cooldown_seconds"] = 1.7
	hud.present(equipped)
	_expect(_state(hud, "Skill2Button") == "CD 2.4s" and skill_two.disabled, "hunter mark cooldown state is wrong", failures)
	_expect(_state(hud, "Skill3Button") == "CD 1.7s" and skill_three.disabled, "dash cooldown state is wrong", failures)
	equipped["marked_entity_id"] = 12
	equipped["marked_target_label"] = "Melee Pursuer"
	equipped["hunter_mark_remaining_seconds"] = 3.5
	hud.present(equipped)
	_expect(_state(hud, "Skill2Button") == "Mark 3.5s", "active mark state did not stay compact and human-readable", failures)
	_expect("Cooldown 2.4s" in hud.skill_cell_detail("Skill2Button"), "active mark cell lost its authoritative cooldown", failures)
	_expect("Remaining 3.5s" in hud.skill_cell_detail("Skill2Button") and "Melee Pursuer" in hud.skill_cell_detail("Skill2Button") and "#12" not in hud.skill_cell_detail("Skill2Button"), "active mark detail lost its public target label or exposed an internal id", failures)
	equipped["marked_entity_id"] = 0
	equipped["hunter_mark_remaining_seconds"] = 0.0
	equipped["hunter_mark_cooldown_seconds"] = 0.0
	equipped["has_target"] = false
	hud.present(equipped)
	_expect(_state(hud, "Skill2Button") == "No Target" and skill_two.disabled, "hunter mark no-target state is wrong", failures)
	equipped["has_target"] = true
	equipped["mark_target_in_range"] = false
	hud.present(equipped)
	_expect(_state(hud, "Skill2Button") == "Too Far" and skill_two.disabled, "hunter mark range state is wrong", failures)
	equipped["dash_active"] = true
	equipped["dash_cooldown_seconds"] = 3.0
	hud.present(equipped)
	_expect(_state(hud, "Skill3Button") == "Dash 3.0s" and skill_three.disabled, "active dash state is wrong", failures)

	var auto := _snapshot()
	auto["selected_mode"] = "Auto"
	auto["attack_target_source"] = "pointer"
	auto["attack_target_status"] = "locked"
	auto["attack_target_entity_id"] = 31
	auto["attack_has_target"] = true
	auto["attack_target_in_range"] = true
	auto["hunter_mark_equipped"] = true
	auto["dash_equipped"] = true
	auto["mark_target_in_range"] = true
	auto["proxy_prediction"] = "stable"
	auto["last_proxy_failure"] = {"category": "cooldown", "reason": "skill not ready"}
	hud.present(auto)
	_expect(mode_label.text.contains("AUTO") and mode_label.text.contains("Locked"), "auto chip is not explicit: %s" % mode_label.text, failures)
	_expect(skill_one.disabled and skill_two.disabled and skill_three.disabled and dodge.disabled, "auto mode must disable every operation button", failures)
	_expect(_state(hud, "Skill1Button") == "Proxy" and _state(hud, "DodgeButton") == "Proxy", "auto controls do not name proxy ownership", failures)
	_expect(_icon_modulate(hud, "Skill1Button") != Color.WHITE and _button_border_color(skill_one) != ready_border, "AUTO lock must use both icon brightness and border tone", failures)
	auto["attack_phase_label"] = "Release"
	hud.present(auto)
	_expect(_state(hud, "Skill1Button") == "Proxy", "active auto attack did not name proxy casting ownership", failures)
	_expect("Current State: Release\nProxy Cast" in skill_one.tooltip_text, "active auto tooltip did not reuse the final state copy", failures)
	_expect_skill_state_fits(hud, "Skill1Button", failures)
	auto["attack_phase_label"] = ""
	hud.present(auto)
	_expect(_state(hud, "Skill1Button") == "Proxy", "idle auto attack did not return to proxy control copy", failures)
	_expect(_state(hud, "Skill2Button") == "AUTO" and _state(hud, "Skill3Button") == "AUTO", "auto must visibly lock active skills 2/3", failures)
	_expect("Last Proxy Block" in _all_copy(summary) and "Skill Not Ready" in _all_copy(summary), "summary did not expose latest proxy refusal", failures)
	_expect("AUTO" in mode_label.text and "Locked" in mode_label.text, "auto chip must pair the mode with a lock glyph, not colour alone", failures)
	_expect("AUTO" in _visible_copy(hud) and "Manual Input" not in _visible_copy(hud) and "Proxy " not in _visible_copy(hud), "the proxy explanation belongs to the open detail, not the idle strip", failures)
	_expect("Input Locked" in _label_text(hud, "ModeStateLabel"), "auto detail must state the locked binding authority", failures)

	var resource_snapshot := _snapshot()
	hud.present(resource_snapshot)
	var resource_label := hud.find_child("ResourceLabel", true, false) as Label
	_expect(resource_label != null and not resource_label.visible, "HUD invented a resource line the authority never sent", failures)
	resource_snapshot["resource_state"] = "Arrows 12 / 24"
	hud.present(resource_snapshot)
	_expect(resource_label.visible and resource_label.text == "Arrows 12 / 24", "HUD dropped an authoritative resource line", failures)
	_expect(hero_frame.get_global_rect().grow(1.0).encloses(resource_label.get_global_rect()), "the resource warning left HeroFrame: frame=%s resource=%s" % [str(hero_frame.get_global_rect()), str(resource_label.get_global_rect())], failures)
	_expect(resource_label.tooltip_text == "Arrows 12 / 24", "a clipped resource warning must keep its complete text in the tooltip", failures)
	_expect((hud.find_child("HeroStatusLabel", true, false) as Label).tooltip_text.contains("Key Status"), "the key status cell must keep its complete text in the tooltip", failures)
	summary_toggle.emit_signal("pressed")
	_expect(resource_label.visible, "opening the summary must not hide a live resource warning", failures)
	var visible_copy := _visible_copy(hud)
	_expect("Energy" not in visible_copy and "Mana" not in visible_copy, "HUD displays a resource system the simulation does not have", failures)
	_expect("EN " not in visible_copy and "MP " not in visible_copy, "HUD displays fabricated resource numbers", failures)
	summary_toggle.emit_signal("pressed")
	_expect(resource_label.visible and resource_label.text == "Arrows 12 / 24", "the resource warning must survive a collapsed summary", failures)

	# --- short feedback: meaning in the strip, complete authority line in the summary --
	# The known cumulative totals are compacted away above the action bar and held in
	# full by the summary. An unknown sentence is never shortened: a refusal reason or a
	# warning the authority sends has to reach the player as it was written.
	var feedback_cases := [
		["Piercing Arrow Hit · Boss Damage 4.495e10 · Defeated 0", "Piercing Arrow Hit", ["Boss Damage", "Defeated", "4.495e10"]],
		["Piercing Arrow Hit · Defeated 3 · Remaining 2", "Piercing Arrow Hit · Remaining 2", ["Defeated"]],
		["Proxy Blocked · skill is not ready", "Proxy Blocked · skill is not ready", []],
		["Ranger Down · Return to Hub to Adjust Your Build", "Ranger Down · Return to Hub to Adjust Your Build", []],
		["Proxy Approaching First Target", "Proxy Approaching First Target", []],
		["Hazard · exposed_ground_zone:warning", "Hazard · exposed_ground_zone:warning", []],
	]
	for case in feedback_cases:
		var feedback_snapshot := _snapshot()
		feedback_snapshot["feedback"] = String(case[0])
		hud.present(feedback_snapshot)
		var strip_line := _label_text(hud, "FeedbackLabel")
		_expect(strip_line == "Combat Feedback  %s" % String(case[1]), "strip feedback for \"%s\" is wrong: %s" % [String(case[0]), strip_line], failures)
		for dropped in case[2] as Array:
			_expect(String(dropped) not in strip_line, "strip feedback still carries \"%s\"" % String(dropped), failures)
		var summary_line := _label_text(hud, "SummaryBlockLabel")
		_expect(String(case[0]) in summary_line, "summary dropped the complete feedback line \"%s\"" % String(case[0]), failures)

	var signal_counts := {"skill": 0, "skill_two": 0, "skill_three": 0, "dodge": 0, "return": 0}
	hud.skill_one_requested.connect(func() -> void: signal_counts.skill += 1)
	hud.skill_two_requested.connect(func() -> void: signal_counts.skill_two += 1)
	hud.skill_three_requested.connect(func() -> void: signal_counts.skill_three += 1)
	hud.dodge_requested.connect(func() -> void: signal_counts.dodge += 1)
	hud.return_requested.connect(func() -> void: signal_counts.return += 1)
	skill_one.emit_signal("pressed")
	skill_two.emit_signal("pressed")
	skill_three.emit_signal("pressed")
	dodge.emit_signal("pressed")
	(hud.find_child("ReturnButton", true, false) as Button).emit_signal("pressed")
	_expect(signal_counts.skill == 1 and signal_counts.skill_two == 1 and signal_counts.skill_three == 1 and signal_counts.dodge == 1 and signal_counts.return == 1, "button signals were not forwarded", failures)

	var copy := _all_copy(hud)
	_expect("TTK" not in copy and "ΣR^k" not in copy, "HUD exposes forbidden boss advice or full formula", failures)
	_expect("Space / Left Mouse Button" in skill_one.tooltip_text and "Piercing Arrow" in skill_one.tooltip_text, "cell tooltip lost the full binding copy", failures)
	_expect("Cooldown: 13 tick" in skill_one.tooltip_text and "carrier damage x this shot's arrow event count" in skill_one.tooltip_text and "1.25" in skill_one.tooltip_text,
		"piercing arrow tooltip lost its authoritative effect", failures)
	_expect("1.5x current targeting distance" in skill_two.tooltip_text and "6 s" in skill_two.tooltip_text and "240 tick" in skill_two.tooltip_text,
		"hunter mark tooltip lost range, duration or cooldown", failures)
	_expect("180" in skill_three.tooltip_text and "6 tick" in skill_three.tooltip_text and "does not grant damage immunity" in skill_three.tooltip_text,
		"dash tooltip lost displacement or no-invulnerability limit", failures)
	_expect("650" in dodge.tooltip_text and "5 tick" in dodge.tooltip_text and "immune to damage throughout" in dodge.tooltip_text,
		"dodge tooltip lost movement or invulnerability facts", failures)

	var normal := _snapshot()
	normal["has_boss"] = false
	normal["layout_id"] = "ring"
	normal["objective_id"] = "hunt_elite"
	normal["objective_label"] = "Hunt Elites"
	normal["living_targets"] = 2
	normal["hazard_status"] = "exposed_ground_zone:warning"
	normal["elite_status"] = "periodic_barrier:active"
	hud.present(normal)
	var normal_copy := _visible_copy(hud)
	_expect("BOSS" not in normal_copy and "Threshold Colossus" not in normal_copy, "normal room HUD still hardcodes Boss/threshold colossus", failures)
	_expect("Hunt Elites" in normal_copy and "Targets Remaining" in normal_copy, "normal room strip lost the live objective state", failures)
	_expect("ring" not in normal_copy and "hunt_elite" not in normal_copy, "raw layout ids belong to the open detail, not the strip", failures)
	_expect(not (hud.find_child("BossHpLabel", true, false) as Label).visible, "a room without a boss must not show a boss ratio", failures)
	summary_toggle.emit_signal("pressed")
	var normal_detail := _visible_copy(summary)
	for expected in ["Hunt Elites", "Hazard Zone", "Telegraphing", "Periodic Barrier", "Active", "Alive 2"]:
		_expect(expected in normal_detail, "normal room detail lost %s" % expected, failures)
	for internal_id in ["hunt_elite", "exposed_ground_zone", "periodic_barrier"]:
		_expect(internal_id not in normal_detail, "internal encounter id escaped test console", failures)
	summary_toggle.emit_signal("pressed")

	# Explicit long-data fixture: exceptional warnings must wrap and scroll inside
	# the fixed panel, not widen the HUD or disappear below the action bar.
	var long_details := manual.duplicate(true)
	long_details["feedback"] = "Public Block Reason: " + "Interface Requirements Not Met; ".repeat(120) + "Last Record"
	hud.present(long_details)
	hud.set_summary_visible(true)
	for layout_frame in range(4): await process_frame
	var detail_scroll := summary.find_child("SummaryBody", true, false) as ScrollContainer
	var detail_last := hud.find_child("SummaryBlockLabel", true, false) as Label
	_expect(detail_last.text.ends_with("Last Record"), "long authoritative warning was truncated from the summary data", failures)
	_expect(detail_scroll.get_v_scroll_bar().max_value > detail_scroll.size.y, "long warning has no usable vertical scroll", failures)
	_expect(detail_last.size.x <= detail_scroll.size.x, "long warning widens the panel", failures)
	detail_scroll.scroll_vertical = int(detail_scroll.get_v_scroll_bar().max_value)
	for layout_frame in range(4): await process_frame
	_expect(detail_last.get_global_rect().end.y <= detail_scroll.get_global_rect().end.y + 2.0, "last warning line cannot scroll into view", failures)
	_expect(_label_text(hud, "FeedbackLabel").contains("Public Block Reason"), "unrecognized warnings must keep their meaning on the strip", failures)
	_expect((hud.find_child("FeedbackLabel", true, false) as Label).tooltip_text == long_details["feedback"], "clipped strip warning loses its complete tooltip", failures)
	long_details["selected_mode"] = "Auto"
	long_details["battle_over"] = true
	hud.present(long_details)
	_expect(mode_label.text == "AUTO", "settled AUTO must not be mislabeled MANUAL", failures)
	_expect("Combat Ended" in _label_text(hud, "ModeStateLabel"), "settled AUTO still advertises live key state", failures)
	await _test_elite_feedback(hud, failures)

	root.remove_child(hud)
	hud.free()
	if failures.is_empty():
		print("PASS  test_arena_hud.gd")
		quit(0)
		return
	for failure in failures:
		printerr("- %s" % failure)
	quit(1)


func _cell(hud: Control, node_name: String) -> Button:
	return hud.find_child(node_name, true, false) as Button


func _state(hud: Control, node_name: String) -> String:
	var button := _cell(hud, node_name)
	if button == null:
		return ""
	var label := button.get_node_or_null("SkillState") as Label
	return "" if label == null else label.text


func _key(hud: Control, node_name: String) -> String:
	var button := _cell(hud, node_name)
	if button == null:
		return ""
	var label := button.get_node_or_null("PrimaryKey") as Label
	return "" if label == null else label.text


func _icon_modulate(hud: Control, node_name: String) -> Color:
	var button := _cell(hud, node_name)
	if button == null:
		return Color.WHITE
	var icon := button.get_node_or_null("SkillIcon") as TextureRect
	return Color.WHITE if icon == null else icon.modulate


func _button_border_color(button: Button) -> Color:
	var style_name := "disabled" if button.disabled else "normal"
	var style := button.get_theme_stylebox(style_name) as StyleBoxFlat
	return Color.TRANSPARENT if style == null else style.border_color


func _test_compact_english_readouts(hud: Control, failures: Array[String]) -> void:
	var snapshot := _snapshot()
	snapshot.merge({
		"has_boss": false, "room_index": 0, "room_count": 2,
		"room_display_name": "Shattered Outpost", "room_elapsed_seconds": 3.0,
		"objective_label": "Clear All Targets", "key_status": "Stable",
		"attack_target_label": "Melee Pursuer", "attack_target_health": 720.0,
		"attack_target_maximum_health": 720.0, "attack_target_in_range": false,
		"hunter_mark_equipped": false, "dash_equipped": false,
	}, true)
	hud.present(snapshot)
	var heading := hud.find_child("EncounterHeading", true, false) as Label
	var hero := hud.find_child("HeroStatusLabel", true, false) as Label
	var target := hud.find_child("BossStateLabel", true, false) as Label
	_expect(hero.text == "Stable" and hero.tooltip_text.contains("Key Status"),
		"compact hero status lost its full meaning", failures)
	_expect(heading.text.contains("Clear foes") and not heading.text.contains("Cleared")
		and heading.tooltip_text.contains("Shattered Outpost") and heading.tooltip_text.contains("Clear All Targets"),
		"compact room objective changed clearing into a cleared state or lost its full title", failures)
	_expect(target.text.contains("Melee Pursuer") and target.text.contains("720/720")
		and target.text.contains("Out of Range") and target.tooltip_text.contains("Current Target"),
		"compact enemy target lost name, health, range, or full context", failures)
	for label: Label in [hero, heading, target]:
		_expect(label.mouse_filter != Control.MOUSE_FILTER_IGNORE and not label.tooltip_text.is_empty(),
			"%s full tooltip cannot receive hover" % label.name, failures)
		var width := label.get_theme_font("font").get_string_size(label.text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")).x
		_expect(width <= label.size.x, "%s compact English copy clips: %s" % [label.name, label.text], failures)
	for node_name in ["Skill2Button", "Skill3Button"]:
		_expect(_state(hud, node_name) == "Empty" and _cell(hud, node_name).tooltip_text.contains("Unequipped"),
			"empty combat skill was mistaken for a quest-locked skill", failures)
		_expect_skill_state_fits(hud, node_name, failures)
	snapshot["objective_label"] = "Room Cleared"
	hud.present(snapshot)
	_expect(heading.text.contains("Room Cleared") and not heading.text.contains("Clear foes"),
		"an explicitly completed room was relabeled as still clearing", failures)
	hud.present(_snapshot())


func _expect_skill_state_fits(hud: Control, node_name: String, failures: Array[String]) -> void:
	var button := _cell(hud, node_name)
	var label := button.get_node_or_null("SkillState") as Label if button != null else null
	_expect(label != null, "cell %s lost its state label" % node_name, failures)
	if label == null:
		return
	var lines := label.text.split("\n")
	_expect(label.size.x >= 79.0 and label.size.y >= 18.0, "cell %s state region became smaller than 79x18" % node_name, failures)
	_expect(lines.size() == 1, "cell %s state copy is not the required single line: %s" % [node_name, label.text], failures)
	_expect(label.get_visible_line_count() >= 1, "cell %s state line is not visible" % node_name, failures)
	var font := label.get_theme_font("font")
	var font_size := label.get_theme_font_size("font_size")
	var required_height := font.get_height(font_size) * lines.size()
	_expect(required_height <= label.size.y, "cell %s state lines need %.1fpx but only have %.1fpx" % [node_name, required_height, label.size.y], failures)
	for line in lines:
		var line_width := font.get_string_size(String(line), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		_expect(line_width <= label.size.x, "cell %s state line is wider than its compact region: %s" % [node_name, String(line)], failures)


func _expect_cell_text_layout(hud: Control, node_name: String, failures: Array[String]) -> void:
	var button := _cell(hud, node_name)
	if button == null:
		return
	var texts: Array[Control] = []
	for child_name in ["PrimaryKey", "SkillName", "SkillState"]:
		var child := button.get_node_or_null(child_name) as Control
		_expect(child != null, "cell %s lost %s" % [node_name, child_name], failures)
		if child == null:
			continue
		var minimum := child.get_combined_minimum_size()
		_expect(minimum.x <= child.size.x + 0.5 and minimum.y <= child.size.y + 0.5, "cell %s %s needs %s but only has %s" % [node_name, child_name, str(minimum), str(child.size)], failures)
		texts.append(child)
	for i in range(texts.size()):
		for j in range(i + 1, texts.size()):
			_expect(not texts[i].get_global_rect().intersects(texts[j].get_global_rect()), "cell %s text regions %s and %s overlap" % [node_name, texts[i].name, texts[j].name], failures)


func _label_text(hud: Control, node_name: String) -> String:
	var label := hud.find_child(node_name, true, false) as Label
	return "" if label == null else label.text


## The EXPANDED state is not just reachable, it is bounded: it hangs below the top
## strip, stops above the action bar (so it cannot cover a skill input), and its
## longest authoritative line still fits the panel's own content box.
func _check_expanded_panel(hud: Control, summary: PanelContainer, top_bar: PanelContainer, frame: Rect2, failures: Array[String]) -> void:
	var action_bar := hud.find_child("ActionBar", true, false) as PanelContainer
	if summary == null or action_bar == null:
		return
	var panel_rect := summary.get_global_rect()
	_expect(frame.encloses(panel_rect), "expanded summary leaves the 1280x720 frame: %s" % str(panel_rect), failures)
	if top_bar != null:
		_expect(not panel_rect.intersects(top_bar.get_global_rect()), "expanded summary covers the default strip", failures)
	_expect(not panel_rect.intersects(action_bar.get_global_rect()), "expanded summary covers the action bar", failures)
	# The panel must not be the thing that grows: a content-derived minimum size above
	# its own rect would silently stretch it over the action bar at runtime.
	_expect(summary.get_combined_minimum_size().y <= panel_rect.size.y, "expanded summary content (%.0f) does not fit its panel (%.0f)" % [summary.get_combined_minimum_size().y, panel_rect.size.y], failures)
	# ...and with the widest authority copy on screen, no line may leave the panel.
	var widest := 0.0
	for control_name in SUMMARY_CELLS:
		var detail := hud.find_child(control_name, true, false) as Control
		if detail == null or not _on_screen(detail):
			continue
		widest = maxf(widest, detail.size.x)
		_expect(detail.get_global_rect().position.x >= panel_rect.position.x and detail.get_global_rect().end.x <= panel_rect.end.x, "summary row %s escapes horizontally" % control_name, failures)
	# The panel keeps its own fixed frame; a long raw identifier must wrap inside it
	# rather than widen the VBox and clip every row after it.
	var inner_width := 396.0
	_expect(widest <= inner_width + 0.5, "expanded summary rows stretch to %.0f, past the %.0f inner width" % [widest, inner_width], failures)
	_expect(panel_rect.size.x <= 420.5, "expanded summary widened past its fixed frame: %s" % str(panel_rect), failures)
	var scroll := summary.find_child("SummaryBody", true, false) as ScrollContainer
	_expect(scroll != null and scroll.clip_contents and scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED,
		"long details must wrap in a real clipped vertical scroll, not silently overflow", failures)
	if scroll != null:
		var stack := summary.find_child("SummaryStack", true, false) as VBoxContainer
		_expect(stack.size.x <= scroll.size.x, "detail rows cannot widen the scroll", failures)
		var bar := scroll.get_v_scroll_bar()
		_expect(bar.max_value >= stack.size.y - 1.0, "all detail height must be reachable by scrollbar", failures)


## Godot's Control.visible is local: a child of a hidden panel still reports true.
## Screen presence is the property the default-strip contract talks about.
func _on_screen(control: Control) -> bool:
	var node := control
	while node != null:
		if node is CanvasItem and not (node as CanvasItem).visible:
			return false
		node = node.get_parent() as Control
	return true


func _same_kind(hud: Control, left: String, right: String) -> bool:
	var left_control := hud.find_child(left, true, false)
	var right_control := hud.find_child(right, true, false)
	if left_control == null or right_control == null:
		return false
	return left_control.get_class() == right_control.get_class()


## Only what the player can read right now, INCLUDING the current label text of cells
## that go on to be moved into the summary.
func _visible_copy(node: Node) -> String:
	var parts: Array[String] = []
	if node is Label:
		parts.append((node as Label).text)
	elif node is Button:
		parts.append((node as Button).text)
	for child in node.get_children():
		if child is Control and not _on_screen(child):
			continue
		parts.append(_visible_copy(child))
	return "\n".join(parts)


## The one transient strip: an authority notice shows on the real visible
## control, clears when the authority stops sending it, never overlaps the
## action dock, and coexists with the opening-room banner. Routine feedback
## stays collapsed; the hidden FeedbackLabel keeps its retired slot only.
func _test_input_feedback_strip(hud: Control, failures: Array[String]) -> void:
	var frame := Rect2(Vector2.ZERO, Vector2(1280.0, 720.0))
	var notice := hud.find_child("InputFeedbackLabel", true, false) as Label
	var card := hud.find_child("InputFeedbackCard", true, false) as PanelContainer
	var routine := hud.find_child("FeedbackLabel", true, false) as Label
	_expect(notice != null and card != null, "input notice strip lost its stable nodes", failures)
	if notice == null or card == null:
		return
	_expect(not notice.visible and notice.text.is_empty(), "input notice invented a notice without authority", failures)
	_expect(routine != null and not routine.visible, "routine feedback strip is no longer collapsed", failures)
	_expect(not card.visible, "the empty input notice card still drew a blank rectangle", failures)
	var snapshot := _snapshot()
	snapshot["input_feedback"] = "Click an enemy to shoot · Or hold Space for aim assist"
	hud.present(snapshot)
	_expect(notice.visible and notice.text == "Click an enemy to shoot · Or hold Space for aim assist",
		"input notice did not show the exact authoritative sentence", failures)
	_expect(card.visible and frame.encloses(card.get_global_rect()),
		"input notice card left the 1280x720 frame: %s" % str(card.get_global_rect()), failures)
	_expect(notice.get_theme_font_size("font_size") >= 18, "input notice fell below the 18px floor", failures)
	## The longest authoritative sentences must fit the real inner box without
	## clipping (the label clips text, so width is the only safe check).
	var longest := "Click an enemy to shoot · Or hold Space for aim assist"
	var skill_sentence := "Hunter's Mark is not equipped in this build · Cannot Cast Yet"
	if skill_sentence.length() > longest.length():
		longest = skill_sentence
	var notice_font: Font = notice.get_theme_font("font")
	var notice_width := float(notice_font.get_string_size(longest, HORIZONTAL_ALIGNMENT_LEFT, -1.0, float(notice.get_theme_font_size("font_size"))).x)
	_expect(notice_width <= notice.size.x, "longest input notice clips: %.0fpx > %.0fpx" % [notice_width, notice.size.x], failures)
	var action_bar := hud.find_child("ActionBar", true, false) as PanelContainer
	_expect(action_bar == null or not card.get_global_rect().intersects(action_bar.get_global_rect()),
		"input notice card overlaps the action dock", failures)
	snapshot["input_feedback"] = "Target out of range · Move closer to shoot"
	snapshot["room_count"] = 2
	snapshot["room_index"] = 0
	snapshot["room_elapsed_seconds"] = 0.5
	snapshot["has_boss"] = false
	snapshot["battle_over"] = false
	hud.present(snapshot)
	var banner := hud.find_child("RoomStartLabel", true, false) as Label
	_expect(banner != null and banner.visible, "room entry cue lost while an input notice showed", failures)
	_expect(notice.visible and notice.text == "Target out of range · Move closer to shoot",
		"input notice was hidden during the opening-room banner", failures)
	_expect(not card.get_global_rect().intersects(banner.get_global_rect()),
		"input notice card overlaps the room banner", failures)
	hud.present(_snapshot())
	_expect(not notice.visible and not card.visible, "input notice stayed visible after the authority cleared it", failures)


func _test_loot_prompt(hud: Control, failures: Array[String]) -> void:
	var builder := FrameBuilderScript.new()
	var room_loot := {
		"entities": [{"loot_entity_id": "loot/near", "state": "available", "position": Vector2(12.0, 0.0), "pickup_radius": 24.0}],
		"pending_pickup_requests": [],
	}
	var snapshot := {"in_arena": true, "player_position": Vector2.ZERO, "room_loot": room_loot, "battle_over": false, "battle_victory": false}
	var near_prompt: Dictionary = builder.loot_prompt(snapshot)
	_expect(String(near_prompt.get("state", "")) == "near" and bool(near_prompt.get("in_range", false))
		and String(near_prompt.get("text", "")) == "Loot Nearby · Press F to Pick Up",
		"loot prompt: an in-range drop did not expose the pickup action", failures)

	(room_loot["entities"] as Array)[0]["position"] = Vector2(60.0, 0.0)
	var far_prompt: Dictionary = builder.loot_prompt(snapshot)
	_expect(String(far_prompt.get("state", "")) == "far" and not bool(far_prompt.get("in_range", true))
		and String(far_prompt.get("text", "")) == "Loot on the Field · Move Closer and Press F to Pick Up",
		"loot prompt: an out-of-range drop did not explain the next step", failures)
	(room_loot["entities"] as Array).append({"loot_entity_id": "loot/second", "state": "available", "position": Vector2(12.0, 0.0), "pickup_radius": 24.0})
	var multi_prompt: Dictionary = builder.loot_prompt(snapshot)
	_expect(int(multi_prompt.get("available_count", 0)) == 2 and String(multi_prompt.get("text", "")) == "Loot Nearby ×2 · Press F to Pick Up",
		"loot prompt: multiple available drops did not disclose the pickup count", failures)

	room_loot["pending_pickup_requests"] = [{"loot_entity_id": "loot/near"}, {"loot_entity_id": "loot/second"}]
	var pending_prompt: Dictionary = builder.loot_prompt(snapshot)
	_expect(String(pending_prompt.get("state", "")) == "pending" and String(pending_prompt.get("text", "")) == "Picking Up Loot...",
		"loot prompt: a queued pickup did not expose its pending state", failures)

	room_loot["pending_pickup_requests"] = []
	snapshot["battle_over"] = true
	snapshot["battle_victory"] = true
	var victory_prompt: Dictionary = builder.loot_prompt(snapshot)
	_expect(String(victory_prompt.get("text", "")).begins_with("Combat Won · "),
		"loot prompt: the victory loot window did not explain that the room remains open", failures)

	var no_loot_snapshot := _snapshot()
	hud.present(no_loot_snapshot)
	var card := hud.find_child("InputFeedbackCard", true, false) as PanelContainer
	var notice := hud.find_child("InputFeedbackLabel", true, false) as Label
	_expect(card != null and notice != null and not card.visible and not notice.visible,
		"loot prompt: an empty room invented a pickup cue", failures)
	var prompt_snapshot := _snapshot()
	prompt_snapshot["loot_prompt_state"] = "near"
	prompt_snapshot["loot_prompt_text"] = "Loot Nearby · Press F to Pick Up"
	hud.present(prompt_snapshot)
	_expect(card.visible and notice.visible and notice.text == "Loot Nearby · Press F to Pick Up",
		"loot prompt: HUD did not surface the projected nearby action", failures)
	var action_bar := hud.find_child("ActionBar", true, false) as PanelContainer
	_expect(action_bar == null or not card.get_global_rect().intersects(action_bar.get_global_rect()),
		"loot prompt: pickup cue overlaps the action dock", failures)
	prompt_snapshot["input_feedback"] = "Loot out of reach · Move closer, then press F"
	hud.present(prompt_snapshot)
	_expect(notice.text == "Loot out of reach · Move closer, then press F",
		"loot prompt: an authoritative pickup receipt did not take priority over the generic cue", failures)
	prompt_snapshot["input_feedback"] = ""
	prompt_snapshot["loot_prompt_text"] = ""
	hud.present(prompt_snapshot)
	_expect(not card.visible and not notice.visible, "loot prompt: cleared loot state left a stale cue on screen", failures)


func _test_room_progress(hud: Control, failures: Array[String]) -> void:
	var snapshot := _snapshot()
	snapshot["has_boss"] = false
	snapshot["objective_label"] = "Clear All Targets"
	snapshot["room_id"] = "first_hunt_clear"
	snapshot["room_index"] = 0
	snapshot["room_count"] = 2
	snapshot["room_elapsed_seconds"] = 0.0
	hud.present(snapshot)
	var heading := hud.find_child("EncounterHeading", true, false) as Label
	var cue := hud.find_child("RoomStartLabel", true, false) as Label
	_expect(heading.visible and heading.text == "Room 1 / 2 · Clear All Targets",
		"room HUD: first-room progress and objective were not continuously visible", failures)
	_expect(cue.visible and cue.text.contains("Entering Room 1"), "room HUD: first-room entry cue missing", failures)
	_expect(heading.get_minimum_size().x <= heading.size.x and cue.get_minimum_size().x <= cue.size.x
		and not heading.get_global_rect().intersects(cue.get_global_rect())
		and not (hud.find_child("BossStateLabel", true, false) as Control).visible,
		"room HUD: progress or entry cue clipped or overlapped another strip row", failures)
	# Measure the actual shipped guidance, not a short synthetic placeholder.
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/rooms/combat/room_catalog.json"))
	var campaign: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/early_campaign.json"))
	for room in catalog["rooms"]:
		var hint := String(room["presentation"]["entry_hint"])
		snapshot["room_entry_hint"] = hint
		hud.present(snapshot)
		var text_width := cue.get_theme_font("font").get_string_size(cue.text, HORIZONTAL_ALIGNMENT_LEFT, -1, cue.get_theme_font_size("font_size")).x
		_expect(cue.visible and text_width <= cue.size.x, "room HUD: authored entry hint clips for %s (%.1f > %.1f)" % [room["layout_id"], text_width, cue.size.x], failures)
		for layout in campaign["layouts"]:
			if layout["id"] == room["layout_id"]:
				_expect(layout["entry_hint"] == hint, "room HUD: campaign and catalog entry guidance differ", failures)
	snapshot["room_elapsed_seconds"] = 2.0
	hud.present(snapshot)
	_expect(not cue.visible and heading.text.contains("Room 1 / 2"),
		"room HUD: expiring the entry cue removed persistent room progress", failures)
	# A same-layout room transition gets a distinct number immediately, without a click.
	snapshot["room_id"] = "first_hunt_followup"
	snapshot["room_index"] = 1
	snapshot["room_elapsed_seconds"] = 0.0
	hud.present(snapshot)
	_expect(heading.text == "Room 2 / 2 · Clear All Targets" and cue.visible and cue.text.contains("Entering Room 2"),
		"room HUD: second-room transition reused the first-room copy", failures)
	hud.present(snapshot)
	_expect(cue.visible and heading.text.contains("Room 2 / 2"), "room HUD: repeated snapshot disturbed the entry cue", failures)
	snapshot["battle_over"] = true
	hud.present(snapshot)
	_expect(not cue.visible and heading.text.contains("Room 2 / 2"),
		"room HUD: settled room still shows entry cue or loses its progress", failures)
	hud.present(_snapshot())
	_expect(not cue.visible, "room HUD: legacy snapshot invented a room entry", failures)


func _test_elite_feedback(hud: Control, failures: Array[String]) -> void:
	var fixture := DomainFixture.new()
	var session := fixture.mount({"room_id": "test.hud.elite", "layout_id": "rectangle_arena", "objective_id": "hunt_elite", "enemy_ids": ["melee_pursuer"], "hazard_ids": [], "elite_rule_ids": ["periodic_barrier", "summon_reinforcements"], "boss_id": "", "drop_tags": []})
	var arena = session.arena
	fixture.drive(arena)
	var phase_samples: Array[Dictionary] = []
	for tick in [0, Encounter.ELITE_BARRIER_ACTIVE_TICKS, Encounter.ELITE_BARRIER_PERIOD_TICKS]:
		fixture.advance_to(arena, tick)
		phase_samples.append(PresentationSnapshot.capture(arena.gameplay_snapshot()))
	var snapshot := _snapshot()
	snapshot.merge({"has_boss": false, "objective_label": "Hunt Elites", "room_count": 2,
		"room_index": 1, "room_elapsed_seconds": 0.0, "living_targets": 2}, true)
	var panel := hud.find_child("EliteMechanicFrame", true, false) as PanelContainer
	var label := hud.find_child("EliteMechanicLabel", true, false) as Label
	var original_scale_size := root.content_scale_size
	hud.set_summary_visible(false)
	for viewport_size in [Vector2i(1280, 720), Vector2i(1600, 900)]:
		# Measure the full logical width as well as the usual scaled 1280 canvas.
		root.content_scale_size = viewport_size
		root.size = viewport_size
		await process_frame
		for phase_sample: Dictionary in phase_samples:
			var tick: int = phase_sample.sim_tick
			snapshot["elite_status"] = arena.presentation.frame_builder.elite_status(phase_sample)
			hud.present(snapshot)
			await process_frame
			var expected := "Barrier Active · Circle Around and Wait for an Opening" if phase_sample.elite_barrier_active else "Barrier Down · Focus Your Attacks"
			_expect(panel.is_visible_in_tree() and expected in label.text and "Reinforcements Pending · Elite Calls at Half Health" in label.text,
				"elite HUD: authority phase or summon readiness missing at %s tick %d" % [viewport_size, tick], failures)
			_expect(_label_text(hud, "EncounterHeading") == "Room 2 / 2 · Hunt Elites"
				and (hud.find_child("RoomStartLabel", true, false) as Control).visible,
				"elite HUD: mechanic cue replaced room progress or entry cue", failures)
			_expect(hud.size == Vector2(viewport_size) and Rect2(Vector2.ZERO, hud.size).encloses(panel.get_global_rect())
				and panel.get_global_rect().encloses(label.get_global_rect())
				and label.get_minimum_size().x <= label.size.x and label.get_minimum_size().y <= label.size.y,
				"elite HUD: mechanic text clipped or left viewport at %s" % viewport_size, failures)
			for node_name in ["HeroFrame", "BossFrame", "UtilityFrame", "EncounterHeading", "RoomStartLabel", "ActionBar", "SummaryPanel"]:
				var control := hud.find_child(node_name, true, false) as Control
				_expect(not panel.get_global_rect().intersects(control.get_global_rect()),
					"elite HUD: cue overlaps %s at %s" % [node_name, viewport_size], failures)
			_expect(panel.mouse_filter == Control.MOUSE_FILTER_IGNORE and label.mouse_filter == Control.MOUSE_FILTER_IGNORE,
				"elite HUD: mechanism display captures combat pointer input", failures)
		var summoned := PresentationSnapshot.capture(phase_samples[-1])
		summoned.reinforcements_summoned = true
		snapshot["elite_status"] = arena.presentation.frame_builder.elite_status(summoned)
		hud.present(snapshot)
		_expect("Reinforcements Arrived · Watch for New Enemies" in label.text and "Pending" not in label.text,
			"elite HUD: authority summon transition left readiness text", failures)
	# The rule IDs and barrier phase can remain set after death: the display must
	# clear from the live elite lookup, even while ordinary targets remain alive.
	var display := PresentationSnapshot.capture(phase_samples[-1])
	var elite = display.enemies[0]
	elite.health = 0.0
	_expect(arena.presentation.frame_builder.elite_status(display) == "None", "elite HUD: dead elite still publishes a mechanic", failures)
	elite.health = elite.maximum_health
	display.enemies.clear()
	display.enemies.append(CombatEnemyStateScript.new(Vector2.ZERO, 720.0, false, 2))
	snapshot["elite_status"] = arena.presentation.frame_builder.elite_status(display)
	hud.present(snapshot)
	_expect(not panel.visible and label.text.is_empty() and "Barrier" not in _visible_copy(hud),
		"elite HUD: elite defeat left a cue over ordinary combat", failures)
	snapshot["elite_status"] = "summon_reinforcements:ready"
	hud.present(snapshot)
	_expect(panel.visible and label.text == "Reinforcements Pending · Elite Calls at Half Health", "elite HUD: summon-only room missing its cue", failures)
	await process_frame
	_expect(panel.size.y <= 42.0 and panel.get_global_rect().encloses(label.get_global_rect()),
		"elite HUD: one mechanism kept an oversized or clipped panel", failures)
	snapshot["battle_over"] = true
	hud.present(snapshot)
	_expect(not panel.visible and label.text.is_empty(), "elite HUD: settled combat retained a stale cue", failures)
	display = PresentationSnapshot.capture(phase_samples[-1])
	display.battle_over = true
	_expect(arena.presentation.frame_builder.elite_status(display) == "None", "elite HUD: settled arena publishes a mechanic", failures)
	hud.present(_snapshot())
	_expect(not panel.visible, "elite HUD: plain snapshot inherited elite feedback", failures)
	fixture.free_session(session)
	root.content_scale_size = original_scale_size
	root.size = Vector2i(1280, 720)
	await process_frame


func _snapshot() -> Dictionary:
	return {
		"player_health": 72.0,
		"player_health_max": 100.0,
		"key_status": "Stable",
		"boss_remaining": "250K",
		"boss_maximum": "1.00M",
		"boss_ratio_known": true,
		"boss_ratio": 0.25,
		"selected_mode": "Manual",
		"battle_over": false,
		"attack_cooldown_seconds": 0.0,
		"attack_held": false,
		"hunter_mark_equipped": false,
		"hunter_mark_cooldown_seconds": 0.0,
		"hunter_mark_remaining_seconds": 0.0,
		"marked_entity_id": 0,
		"marked_target_label": "",
		"mark_target_in_range": true,
		"dash_equipped": false,
		"dash_cooldown_seconds": 0.0,
		"dash_active": false,
		"dodge_cooldown_seconds": 0.0,
		"has_target": true,
		"target_in_range": true,
		"damage": "750K",
		"feedback": "Target Hit · Boss Damage 750K",
		"p": 0.61,
		"lifetime": 4.0,
		"distance": 320.0,
		"g": 80,
		"growth_verified": false,
		"growth_type": "exponential",
		"proxy_prediction": "manual",
		"last_proxy_failure": {},
	}


func _all_copy(node: Node) -> String:
	var parts: Array[String] = []
	if node is Label:
		parts.append((node as Label).text)
	elif node is Button:
		parts.append((node as Button).text)
	for child in node.get_children():
		parts.append(_all_copy(child))
	return "\n".join(parts)


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
