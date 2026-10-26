class_name ArenaHudSkillCells
extends RefCounted
## The four action cells of the combat HUD, extracted from ArenaHud. This
## collaborator builds the icon/key/state/cooldown buttons, derives each cell's
## state, tone and tooltip from the authoritative snapshot, and re-emits presses
## through the HUD's own signals, so the HUD keeps its public signal contract.

const EarlySkillRegistryScript = preload("res://src/content/early_skill_registry.gd")
const PlayerReadableBuildScript = preload("res://src/presentation/player_readable_build.gd")
const StyleScript = preload("res://src/presentation/arena_hud/hud_style.gd")
const TextScript = preload("res://src/presentation/arena_hud/hud_text.gd")

## Icons render at the authored 32px native size: crisp nearest-neighbour, and
## it leaves the cell room for the key/name/state rows to breathe.
const SKILL_ICON_DISPLAY: float = 32.0
const SKILL_CELL_MINIMUM := Vector2(104.0, 100.0)
const SKILL_STATE_SIZE := Vector2(96.0, 24.0)
const SKILL_STATE_FONT_SIZE: int = 18
const SKILL_KEY_FONT_SIZE: int = 18
const SKILL_NAME_FONT_SIZE: int = 18
const SKILL_SLOTS: Array[Dictionary] = [
	{"node_name": "Skill1Button", "slot_id": "piercing_arrow", "title": "Piercing"},
	{"node_name": "Skill2Button", "slot_id": "hunter_mark", "title": "Mark"},
	{"node_name": "Skill3Button", "slot_id": "dash", "title": "Dash"},
	{"node_name": "DodgeButton", "slot_id": "basic_dodge", "title": "Dodge"},
]
const SLOT_PRIMARY_KEYS := {
	"Skill1Button": "Space",
	"Skill2Button": "Q",
	"Skill3Button": "E",
	"DodgeButton": "Shift",
}

var _hud
var _style: StyleScript
var _skill_registry = EarlySkillRegistryScript.new()
var _player_readable = PlayerReadableBuildScript.new()
var _cell_buttons: Dictionary = {}
var _cell_icons: Dictionary = {}
var _cell_states: Dictionary = {}
var _cell_progress: Dictionary = {}
var _cell_details: Dictionary = {}
var _skill_overrides: Dictionary = {}


func _init(hud, style: StyleScript) -> void:
	_hud = hud
	_style = style


func load_registry() -> void:
	_skill_registry.load_all()


## Full authoritative copy for one cell, including what the compact layout cannot
## fit. Never returns an invented value.
func detail_for(node_name: String) -> String:
	return String(_cell_details.get(node_name, ""))


func icon_for(node_name: String) -> Texture2D:
	var icon: TextureRect = _cell_icons.get(node_name)
	return null if icon == null else icon.texture


## Read-only evidence for tests and scene inspection. Values remain snapped to
## actual control geometry; no ideal layout is reported.
func cooldown_progress_for(node_name: String) -> float:
	var bar: ProgressBar = _cell_progress.get(node_name)
	return 0.0 if bar == null else bar.value


func all_controls_visible() -> bool:
	for node_name: String in SLOT_PRIMARY_KEYS.keys():
		var button: Button = _cell_buttons.get(node_name)
		if button == null or not button.visible:
			return false
	return true


## One action cell: 40px approved icon, primary key, name and live state. The
## button stays the only interactive node, so the existing signal contract is unchanged.
func build_cell(slot: Dictionary) -> Button:
	var node_name := String(slot["node_name"])
	var button := Button.new()
	button.name = node_name
	button.text = ""
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = SKILL_CELL_MINIMUM
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.pressed.connect(func() -> void: _request_for(node_name))
	_cell_buttons[node_name] = button

	var icon := TextureRect.new()
	icon.name = "SkillIcon"
	icon.position = Vector2(8.0, 8.0)
	icon.size = Vector2(SKILL_ICON_DISPLAY, SKILL_ICON_DISPLAY)
	icon.custom_minimum_size = Vector2(SKILL_ICON_DISPLAY, SKILL_ICON_DISPLAY)
	icon.texture = _hud.icons.icon(String(slot["slot_id"]))
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(icon)
	_cell_icons[node_name] = icon

	var key_label := _style.named_label("PrimaryKey")
	key_label.text = String(SLOT_PRIMARY_KEYS[node_name])
	key_label.position = Vector2(52.0, 8.0)
	key_label.size = Vector2(46.0, 30.0)
	key_label.add_theme_font_size_override("font_size", SKILL_KEY_FONT_SIZE)
	key_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	key_label.add_theme_color_override("font_color", StyleScript.COLOR_AMBER)
	key_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(key_label)

	var state_label := _style.named_label("SkillState")
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
	StyleScript.style_progress(progress, StyleScript.COLOR_BONE)
	button.add_child(progress)
	_cell_progress[node_name] = progress

	var name_label := _style.named_label("SkillName")
	name_label.text = String(slot["title"])
	name_label.position = Vector2(6.0, 42.0)
	name_label.size = Vector2(92.0, 24.0)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", SKILL_NAME_FONT_SIZE)
	name_label.clip_text = true
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(name_label)
	return button


func update(snapshot: Dictionary, is_auto: bool, battle_over: bool) -> void:
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
		marked_target_label = "Target"
	var mark_active := marked_id > 0 and mark_remaining > 0.0
	var dash_active := bool(snapshot.get("dash_active", false))
	var attack_phase_label := String(snapshot.get("attack_phase_label", ""))
	var attack_held := bool(snapshot.get("attack_held", false))
	var attack_buffered := bool(snapshot.get("attack_buffered", false))
	var attack_request_open := bool(snapshot.get("attack_request_open", attack_cooldown <= 0.0))

	var attack_state := TextScript.action_state(is_auto, battle_over, attack_cooldown, attack_has_target, attack_target_in_range)
	if is_auto:
		if not attack_phase_label.is_empty():
			attack_state = "%s\nProxy Cast" % attack_phase_label
	elif attack_target_source == "pointer":
		var pointer_state := TextScript.pointer_target_state(attack_target_status, attack_has_target, attack_target_in_range)
		if not attack_phase_label.is_empty():
			attack_state = attack_phase_label
			if attack_buffered and pointer_state == "Pointer Lock":
				attack_state += "\nTarget Lock Buffered"
			elif not pointer_state.is_empty():
				attack_state += "\n%s" % pointer_state
		elif attack_buffered and pointer_state == "Pointer Lock":
			attack_state = "Target Lock Buffered"
		elif attack_buffered:
			attack_state = "Target Lock Buffered"
		elif attack_held:
			attack_state = pointer_state if not pointer_state.is_empty() else "Pointer Lock"
		elif not battle_over and attack_cooldown <= 0.0 and not pointer_state.is_empty():
			attack_state = pointer_state
	elif not attack_phase_label.is_empty():
		attack_state = attack_phase_label
		if attack_buffered:
			attack_state += "\nNext Shot Buffered"
		elif attack_held:
			attack_state += "\nHold to Repeat"
	elif attack_buffered:
		attack_state = "Next Shot Buffered"
	elif attack_held:
		attack_state = "Hold to Repeat"
	var attack_active := not attack_phase_label.is_empty() or attack_buffered or (attack_held and not is_auto)
	if attack_target_source == "pointer" and (not attack_has_target or not attack_target_in_range) and attack_phase_label.is_empty():
		attack_active = false
	var attack_tone := "active" if attack_active else _tone_for(is_auto, battle_over, attack_cooldown > 0.0, attack_has_target and attack_target_in_range, true)
	var attack_disabled := is_auto or battle_over or not attack_request_open or not attack_has_target or not attack_target_in_range
	var attack_live_detail := TextScript.cooldown_text(attack_cooldown) if attack_cooldown > 0.0 else ""
	_apply_cell("Skill1Button", attack_state, attack_state, attack_tone, attack_disabled, attack_cooldown)

	var mark_state := "Unequipped"
	if mark_equipped:
		if is_auto:
			mark_state = "AUTO Locked"
		elif battle_over:
			mark_state = "Combat Ended"
		elif mark_active:
			mark_state = "%s\nRemaining %.1fs" % [marked_target_label, mark_remaining]
		elif mark_cooldown > 0.0:
			mark_state = TextScript.cooldown_text(mark_cooldown)
		elif not has_target:
			mark_state = "No Target"
		elif not mark_in_range:
			mark_state = "Out of Range"
		else:
			mark_state = "Ready"
	var mark_detail := "%s · Remaining %.1fs · Cooldown %.1fs" % [marked_target_label, mark_remaining, mark_cooldown] if mark_active else mark_state
	_apply_cell("Skill2Button", mark_state, mark_detail, _tone_for(is_auto, battle_over, mark_cooldown > 0.0, has_target and mark_in_range, mark_equipped), not mark_equipped or is_auto or battle_over or mark_cooldown > 0.0 or not has_target or not mark_in_range, mark_cooldown)

	var dash_state := "Unequipped"
	if dash_equipped:
		if is_auto:
			dash_state = "AUTO Locked"
		elif battle_over:
			dash_state = "Combat Ended"
		elif dash_active:
			dash_state = "Dashing\n%s" % TextScript.cooldown_text(dash_cooldown)
		elif dash_cooldown > 0.0:
			dash_state = TextScript.cooldown_text(dash_cooldown)
		else:
			dash_state = "Ready"
	_apply_cell("Skill3Button", dash_state, dash_state, _tone_for(is_auto, battle_over, dash_cooldown > 0.0, true, dash_equipped), not dash_equipped or is_auto or battle_over or dash_cooldown > 0.0 or dash_active, dash_cooldown)

	var dodge_state := "Proxy Control" if is_auto else ("Combat Ended" if battle_over else (TextScript.cooldown_text(dodge_cooldown) if dodge_cooldown > 0.0 else "Ready"))
	_apply_cell("DodgeButton", dodge_state, dodge_state, _tone_for(is_auto, battle_over, dodge_cooldown > 0.0, true, true), is_auto or battle_over or dodge_cooldown > 0.0, dodge_cooldown)

	_update_detail("Skill1Button", _skill_tooltip("piercing_arrow", attack_state, attack_live_detail))
	_update_detail("Skill2Button", _skill_tooltip("hunter_mark", mark_detail))
	_update_detail("Skill3Button", _skill_tooltip("dash", dash_state))
	_update_detail("DodgeButton", _skill_tooltip("basic_dodge", dodge_state))


func _skill_tooltip(skill_id: String, current_state: String, live_detail: String = "") -> String:
	var detail := _player_readable.format_skill(_current_skill(skill_id))
	if skill_id == "piercing_arrow":
		detail += "\nCopper arrow on the field: current firing direction"
	if skill_id == "basic_dodge":
		detail += "\nControls: SHIFT · CTRL · RMB"
	if not live_detail.is_empty():
		detail += "\nLive %s" % live_detail
	return "%s\nCurrent State: %s" % [detail, current_state]


func _current_skill(skill_id: String) -> Dictionary:
	var skill: Dictionary = _skill_registry.get_skill(skill_id).duplicate(true)
	for key in (_skill_overrides.get(skill_id, {}) as Dictionary):
		skill[key] = _skill_overrides[skill_id][key]
	return skill


func _request_for(node_name: String) -> void:
	match node_name:
		"Skill1Button":
			_hud.skill_one_requested.emit()
		"Skill2Button":
			_hud.skill_two_requested.emit()
		"Skill3Button":
			_hud.skill_three_requested.emit()
		"DodgeButton":
			_hud.dodge_requested.emit()


func _apply_cell(node_name: String, text: String, detail: String, tone: String, disabled: bool, cooldown_remaining: float) -> void:
	var button: Button = _cell_buttons.get(node_name)
	var icon: TextureRect = _cell_icons.get(node_name)
	var state_label: Label = _cell_states.get(node_name)
	var progress: ProgressBar = _cell_progress.get(node_name)
	if button == null or icon == null or state_label == null or progress == null:
		return
	button.disabled = disabled
	state_label.text = TextScript.compact_cell_state(node_name, text)
	state_label.add_theme_font_size_override("font_size", SKILL_STATE_FONT_SIZE)
	state_label.add_theme_color_override("font_color", StyleScript.COLOR_AMBER if tone in ["ready", "active"] else (StyleScript.COLOR_PROXY if tone == "locked" else (StyleScript.COLOR_NEUTRAL if tone in ["unequipped", "blocked"] else StyleScript.COLOR_BONE)))
	icon.modulate = Color.WHITE if not disabled or tone == "active" else Color(0.55, 0.55, 0.58, 0.85)
	StyleScript.style_action_button(button, disabled, tone)
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


func _update_detail(node_name: String, detail: String) -> void:
	_cell_details[node_name] = detail
	var button: Button = _cell_buttons.get(node_name)
	if button == null:
		return
	button.tooltip_text = detail if _hud.icon_pending_reason.is_empty() else "%s\n%s" % [detail, _hud.icon_pending_reason]


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
