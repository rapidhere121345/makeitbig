class_name BaseHubScreen
extends Control
## Walkable town with a compact top band and facility labels attached to the
## world landmarks. Current objectives stay visible; narrative and settlement
## receipts open on demand. Routes, lock states, movement and conversations use
## the existing APIs.

signal contract_requested
signal character_requested
signal story_requested
signal conversation_read(entry_id: String)
signal title_requested
signal feature_requested(feature_id: String)

const ShellThemeScript = preload("res://src/presentation/shell_theme.gd")
const HamletConceptViewScript = preload("res://src/presentation/hamlet_concept_view.gd")
const PlayerFacingStatusScript = preload("res://src/presentation/player_facing_status.gd")
const TownDialogueScript = preload("res://src/presentation/town_dialogue.gd")
const TALK_RADIUS := 28.0
const DESIGN_SIZE := Vector2(1280.0, 720.0)
const DESIGN_TO_WORLD := 0.5
## Hub positions stay published in design space (1280x720); the live renderer
## works in the 640x360 logical world, so a world point is doubled back into one.
const WORLD_TO_DESIGN := 2.0
## The world viewport is always drawn at a whole-number multiple of its own
## 640x360 so a resized window never gives the pixel art uneven pixel sizes.
const WORLD_SCALE_BASE := 2
## Hamlet copy colours: bone for the lead text, cool grey for secondary, the
## existing old-copper accent for links. The shared shell theme already carries a
## 1px ink drop shadow, which is what keeps the copy off the ground art.
const TITLE_TEXT := "炉边镇"
const COOL_GREY := Color("B0B8BA")
const OLD_COPPER := ShellThemeScript.AMBER
const HERO_SPEED := 96.0
## The authored entry foot point of the published framing, in design-space
## screen coordinates: the hero walks in at the concept anchor (320, 260) of the
## 640x360 viewport, which is (640, 520) on the 1280x720 canvas. The navigation
## band below it must never cover this point.
const HERO_ENTRY_FOOT_ANCHOR := Vector2(640.0, 520.0)
const HEADER_RECT := Rect2(16.0, 12.0, 1248.0, 72.0)
const INFO_DETAIL_RECT := Rect2(24.0, 96.0, 740.0, 420.0)
const LANDMARK_FEATURE_IDS: Array[String] = ["contract", "loadout", "forge", "training", "proxy"]
const LANDMARK_SIZE := Vector2(280.0, 72.0)
const LANDMARK_GAP := 8.0
const LANDMARK_SAFE_RECT := Rect2(12.0, 92.0, 1256.0, 616.0)
## The proximity prompt is a minimal action badge beside the avatar. Facility
## identity and state live on its landmark, so the badge never repeats them.
const PROMPT_HEIGHT := 34.0
const PROMPT_MIN_WIDTH := 200.0
const PROMPT_MAX_WIDTH := 400.0
const PROMPT_GAP := 8.0
const PROMPT_MARGIN := 12.0
const PROMPT_CLEARANCE := 4.0
## The themed 18px floor of ShellTheme.MIN_FONT_SIZE holds for every relocated
## row; the live proximity badge keeps the 20px body step.
const PROMPT_FONT_SIZE := 22
const HELP_COPY_TEXT := "WASD / 方向键移动 · 目标箭头指路 · 靠近后 E 交互\nTab 选择可见地标 · 成长 C · 见闻 J · Esc 离开地标 · F1 设置"
const DETAIL_TITLE_TEXT := "镇中近况"
const DETAIL_STATUS_EMPTY_TEXT := "本屏暂无新的状态提示。"
## Legacy design-space anchors of the pre-hamlet hub, kept for the hub entries
## whose placement the layout has not published yet.
const LEGACY_FEATURE_POSITIONS := {
	"contract": Vector2(640.0, 205.0),
	"loadout": Vector2(392.0, 274.0),
	"forge": Vector2(888.0, 274.0),
	"training": Vector2(875.0, 491.0),
	"proxy": Vector2(405.0, 483.0),
	"immortality": Vector2(640.0, 566.0),
}
## Short player-facing names of the authored mainline nodes. Shared by the next
## objective line and the contract marker so the two can never disagree.
const _SHORT_NODE_LABELS := {
	"tutorial_ranger_basics": "教程",
	"mainline_01_first_hunt": "主线 01",
	"mainline_02_priority_under_pressure": "主线 02",
	"mainline_03_first_elite": "主线 03",
	"mainline_04_hazard_and_forge": "主线 04",
	"mainline_05_growth_gate": "主线 05",
	"threshold_colossus": "阈门巨像",
	"auto_certification": "AUTO 考核",
}
## The authored reward a locked page is waiting for. Both the card and the world
## marker read this table, so "locked" always names the one real gate.
const _UNLOCK_REASONS := {
	"forge": "锻造奖励后开放",
	"proxy": "首杀巨像后开放",
}
## Short, known English outcome/status tokens become Chinese copy; anything the
## tables do not name is passed through verbatim, so a new save state is never
## renamed by a guess. The hub and its read-back API share the same two tables.
const _KNOWN_OUTCOMES := {
	"victory": "胜利",
	"defeat": "失败",
	"final_victory": "最终胜利",
	"error": "出错",
	"aborted": "中止",
}
## The published non-colour state marks: the filled diamond the world markers
## already use for a route that is open and highlighted, and the hollow one for a
## station the player cannot open yet.
const FILLED_MARK := "\u25c6"
const LOCK_MARK := "\u25c7"

var _built := false
var _profile: Dictionary = {}
var _last_result: Dictionary = {}
var _campaign_snapshot: Dictionary = {}
var _status_message := ""
var _marker_notes: Dictionary = {}
var _character_snapshot: Dictionary = {}
var _story_snapshot: Dictionary = {}
var _character_button: Button
var _story_button: Button
var _profile_label: Label
var _objective_label: Label
var _info_toggle: Button
var _detail_panel: PanelContainer
var _detail_status_label: Label
var _detail_result_label: Label
var _detail_help_label: Label
var _nearby_panel: Panel
var _nearby_label: Label
var _prompt_rect := Rect2()
var _details_expanded := false
var _progress_label: Label
var _design_canvas: Control
var _view: HamletConceptViewScript
var _nav_states: Array = []
var _unlock_reasons: Dictionary = {}
var _dialogue: TownDialogueScript
var _resident_positions: Dictionary = {}
var _resident_conversations: Dictionary = {}
var _resident_markers: Dictionary = {}
var _detail_objective_label: Label
var _detail_story_label: Label
var _header: PanelContainer
var _destination_id := "contract"
var _landmarks: Dictionary = {}
var _landmark_styles: Dictionary = {}


class TownLandmark extends Button:
	var feature_id := ""


	func _init(landmark_feature_id: String) -> void:
		feature_id = landmark_feature_id
		name = "TownLandmark_" + feature_id


func _ready() -> void:
	_build_ui()
	_apply_presentation()


func _process(delta: float) -> void:
	if is_dialogue_open() or _details_expanded or _navigation_has_focus():
		return
	var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	move_hero(direction, delta)


func _navigation_has_focus() -> bool:
	var viewport := get_viewport()
	if viewport == null:
		return false
	var owner := viewport.gui_get_focus_owner()
	for landmark: Control in _landmarks.values():
		if owner != null and (owner == landmark or landmark.is_ancestor_of(owner)):
			return true
	return false


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	var key := key_event.physical_keycode if key_event.physical_keycode != KEY_NONE else key_event.keycode
	if is_dialogue_open():
		if key in [KEY_E, KEY_ENTER, KEY_SPACE]: _dialogue.advance()
		elif key == KEY_ESCAPE: _dialogue.close_dialogue()
		get_viewport().set_input_as_handled()
		return
	if _details_expanded and key in [KEY_ESCAPE, KEY_E, KEY_SPACE]:
		if key == KEY_ESCAPE: set_information_details_expanded(false)
		get_viewport().set_input_as_handled()
		return
	if key in [KEY_C, KEY_J]:
		get_viewport().set_input_as_handled()
		if key == KEY_C: character_requested.emit()
		else: story_requested.emit()
		return
	if key == KEY_TAB and _focus_visible_landmark(key_event.shift_pressed):
		get_viewport().set_input_as_handled()
		return
	if _navigation_has_focus():
		if key == KEY_ESCAPE:
			get_viewport().gui_get_focus_owner().release_focus()
		if key in [KEY_ESCAPE, KEY_E, KEY_SPACE]:
			get_viewport().set_input_as_handled()
		return
	if key == KEY_E or key == KEY_SPACE:
		if activate_nearby_interaction():
			var viewport := get_viewport()
			if viewport != null:
				viewport.set_input_as_handled()


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	var key := key_event.physical_keycode if key_event.physical_keycode != KEY_NONE else key_event.keycode
	if key != KEY_TAB or is_dialogue_open() or _details_expanded:
		return
	if _focus_visible_landmark(key_event.shift_pressed):
		get_viewport().set_input_as_handled()


func _focus_visible_landmark(reverse: bool) -> bool:
	var visible_ids: Array[String] = []
	for feature_id: String in LANDMARK_FEATURE_IDS:
		var landmark := get_landmark(feature_id)
		if landmark != null and landmark.is_visible_in_tree():
			visible_ids.append(feature_id)
	if visible_ids.is_empty():
		return false
	var current := -1
	var focus_owner := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	for index: int in visible_ids.size():
		var landmark := get_landmark(visible_ids[index])
		if landmark != null and focus_owner != null and (focus_owner == landmark or landmark.is_ancestor_of(focus_owner)):
			current = index
			break
	var target := 0
	if current >= 0:
		target = posmod(current + (-1 if reverse else 1), visible_ids.size())
	var focused := get_landmark(visible_ids[target])
	if focused == null:
		return false
	focused.grab_focus()
	return true


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mouse_event := event as InputEventMouseButton
	if not mouse_event.pressed or mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return
	# Only unhandled world clicks reach here; clicking empty ground also leaves
	# keyboard navigation so WASD movement can resume without opening a page.
	if _navigation_has_focus():
		get_viewport().gui_get_focus_owner().release_focus()
	if not click_at_design_point(mouse_event.position):
		return
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()


func present(profile: Dictionary, last_result: Dictionary = {}, status_message: String = "", campaign_snapshot: Dictionary = {}) -> void:
	_profile = profile.duplicate(true)
	_last_result = last_result.duplicate(true)
	_campaign_snapshot = campaign_snapshot.duplicate(true)
	_status_message = status_message
	_unlock_reasons = _derive_unlock_reasons()
	if _built:
		_apply_presentation()


func present_adventure(character: Dictionary, story: Dictionary) -> void:
	_character_snapshot = character.duplicate(true)
	_story_snapshot = story.duplicate(true)
	if _built: _apply_presentation()



func _derive_unlock_reasons() -> Dictionary:
	## Lock reasons are read back from the same snapshot the cards use: a page is
	## only ever "locked" while the authored reward that opens it is genuinely
	## absent, and the reason names that reward instead of the current picture.
	var earned_rewards := _as_array(_campaign_snapshot.get("earned_reward_tags", []))
	var progression := _as_dictionary(_profile.get("progression", {}))
	var reasons := _UNLOCK_REASONS.duplicate()
	if "law_forge_unlock" in earned_rewards:
		reasons.erase("forge")
	if bool(progression.get("proxy_unlocked", false)):
		reasons.erase("proxy")
	return reasons


func move_hero(direction: Vector2, delta: float) -> void:
	if not _built or delta <= 0.0 or is_dialogue_open():
		return
	var before := _view.hero_world_position()
	_view.move_hero(direction.limit_length(1.0), delta)
	if not before.is_equal_approx(_view.hero_world_position()): _update_nearby_feature()


func travel_snapshot() -> Dictionary:
	return _view.travel_snapshot() if _view != null else {}


func restore_travel(snapshot: Dictionary) -> void:
	_view.restore_travel(snapshot)
	_destination_id = String(snapshot.get("destination", "contract"))
	_update_nearby_feature()


func set_hero_position(position: Vector2) -> void:
	_view.teleport_hero(Vector2(position) * DESIGN_TO_WORLD)
	_update_nearby_feature()


func get_hero_position() -> Vector2:
	return _view.hero_world_position() / DESIGN_TO_WORLD


func get_nearby_feature_id() -> String:
	return _view.nearby_feature_id()


func activate_nearby_feature() -> bool:
	if is_dialogue_open(): return false
	var feature_id := _view.nearby_feature_id()
	if feature_id.is_empty():
		return false
	return navigation_card_activated(feature_id)


func activate_nearby_interaction() -> bool:
	var resident_id := nearby_resident_id()
	if not resident_id.is_empty(): return talk_to_resident(resident_id)
	return activate_nearby_feature()


func is_dialogue_open() -> bool:
	return _dialogue != null and _dialogue.is_open()


func dialogue_report() -> Dictionary:
	return _dialogue.dialogue_report() if _dialogue != null else {"open":false}


func nearby_resident_id() -> String:
	if _view == null or is_dialogue_open(): return ""
	var feet := _view.hero_world_position()
	var distance := TALK_RADIUS
	var closest := ""
	var feature := _view.entry_for(_view.nearby_feature_id())
	if not feature.is_empty():
		distance = minf(distance, feet.distance_to(feature.get("feet", Vector2(INF, INF))))
	for id: String in _resident_conversations:
		if not _resident_positions.has(id): continue
		var candidate := feet.distance_to(_resident_positions[id])
		if candidate < distance:
			distance = candidate
			closest = id
	return closest


func talk_to_resident(resident_id: String) -> bool:
	if _dialogue == null or is_dialogue_open() or not _resident_conversations.has(resident_id): return false
	if not _resident_positions.has(resident_id) or _view.hero_world_position().distance_to(_resident_positions[resident_id]) > TALK_RADIUS: return false
	var opened := _dialogue.open_conversation(_resident_conversations[resident_id])
	if opened:
		_nearby_panel.hide()
		_prompt_rect = Rect2()
		_update_resident_markers()
		_update_landmarks()
	return opened


func _click_resident(point: Vector2) -> bool:
	for id: String in _resident_conversations:
		if not _resident_positions.has(id): continue
		var feet: Vector2 = _resident_positions[id]
		if Rect2(feet - Vector2(14, 34), Vector2(28, 40)).has_point(point):
			return talk_to_resident(id)
	return false


func _build_town_dialogue() -> void:
	_dialogue = TownDialogueScript.new()
	_design_canvas.add_child(_dialogue)
	_dialogue.finished.connect(func(entry_id: String): conversation_read.emit(entry_id))
	_dialogue.dismissed.connect(func(): _update_nearby_feature())


func _refresh_town_conversations() -> void:
	if _view == null or _dialogue == null: return
	_resident_positions.clear()
	for resident: Dictionary in _view.life_report().get("residents", []):
		_resident_positions[String(resident.id)] = resident.feet
	_resident_conversations.clear()
	for entry: Dictionary in _story_snapshot.get("available_conversations", []):
		var id := String(entry.get("npc", ""))
		if not _resident_conversations.has(id) or int(entry.stage) >= int(_resident_conversations[id].stage):
			_resident_conversations[id] = entry.duplicate(true)
	for id: String in _resident_conversations:
		if _resident_markers.has(id): continue
		var marker := Label.new()
		marker.name = "ResidentTalkMarker_" + id
		marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
		marker.text = "…"
		marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		marker.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		marker.add_theme_font_size_override("font_size", 18)
		marker.add_theme_color_override("font_color", ShellThemeScript.BONE)
		var bubble := _hotspot_style(Color("111820ee"), ShellThemeScript.COPPER_DULL, 1)
		bubble.content_margin_left = 4
		bubble.content_margin_right = 4
		bubble.content_margin_top = 0
		bubble.content_margin_bottom = 0
		marker.add_theme_stylebox_override("normal", bubble)
		_design_canvas.add_child(marker)
		_design_canvas.move_child(marker, _dialogue.get_index())
		_resident_markers[id] = marker
	_update_nearby_feature()


func _update_resident_markers() -> void:
	for id: String in _resident_markers:
		var marker: Label = _resident_markers[id]
		marker.visible = false
		if _details_expanded or is_dialogue_open() or not _resident_positions.has(id) or not _resident_conversations.has(id): continue
		var global_point := _view.design_point_for_world(_resident_positions[id] - Vector2(0, 38), _design_canvas.position, _design_canvas.scale)
		var point := _design_canvas.get_global_transform_with_canvas().affine_inverse() * global_point
		marker.position = (point - Vector2(17, 28)).floor()
		marker.size = Vector2(34, 28)
		marker.visible = marker.position.y > HEADER_RECT.end.y and marker.position.y + 28 < DESIGN_SIZE.y and marker.position.x > 12 and marker.position.x + 34 < DESIGN_SIZE.x - 12
		marker.modulate.a = 0.55 if bool(_resident_conversations[id].get("is_read", false)) else 1.0


func click_at_design_point(point: Vector2) -> bool:
	if is_dialogue_open() or _details_expanded: return false
	## Distant stations become destinations. Only a nearby station opens a page.
	if _view == null:
		return false
	var world_point := _view.world_point_at_design(point, _design_canvas.position, _design_canvas.scale)
	if _click_resident(world_point): return true
	var feature_id := _view.hit_test(world_point)
	if feature_id.is_empty():
		return false
	return navigation_card_activated(feature_id)


func click_at_world_point(world_point: Vector2) -> bool:
	if is_dialogue_open() or _details_expanded: return false
	## Test and replay entry point: a click expressed in world coordinates goes
	## through the same camera conversion the real pointer uses.
	if _view == null:
		return false
	if _click_resident(world_point): return true
	var feature_id := _view.hit_test(world_point)
	if feature_id.is_empty():
		return false
	return navigation_card_activated(feature_id)


func get_feature_marker_text(feature_id: String) -> String:
	var entry := _feature_entry(feature_id)
	var label := String(entry.get("label", ""))
	if label.is_empty():
		return ""
	var note := String(_marker_notes.get(feature_id, ""))
	var highlighted := feature_id == "contract" or feature_id in ["loadout", "forge", "proxy"]
	var prefix := FILLED_MARK if highlighted else LOCK_MARK
	if bool(entry.get("locked", false)) and feature_id != "contract":
		prefix = LOCK_MARK
	if note.is_empty():
		return "%s %s" % [prefix, label]
	return "%s %s \u00b7 %s" % [prefix, label, note]


func get_progress_text() -> String:
	return _early_progress_text(_as_dictionary(_profile.get("progression", {})))


func get_next_objective_text() -> String:
	return _next_objective_text()


func get_hub_view() -> HamletConceptViewScript:
	## Test and main-thread access to the live renderer without going through UI.
	return _view


func get_world_feature_position(feature_id: String) -> Vector2:
	## Legacy hub API: hub positions stay in the 1280x720 design space, which is
	## twice the 640x360 logical world. The legacy table already holds those
	## design-space anchors, and a published placement's world feet are doubled
	## back into it here.
	var entry := _feature_entry(feature_id)
	if entry.is_empty():
		return LEGACY_FEATURE_POSITIONS.get(feature_id, Vector2.ZERO) as Vector2
	return Vector2(entry.get("feet", Vector2.ZERO)) * float(int(1.0 / DESIGN_TO_WORLD))


func _build_ui() -> void:
	if _built:
		return
	_built = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = ShellThemeScript.create()

	var background := ColorRect.new()
	background.color = ShellThemeScript.GROUND
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	_design_canvas = Control.new()
	_design_canvas.custom_minimum_size = DESIGN_SIZE
	_design_canvas.size = DESIGN_SIZE
	_design_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_design_canvas.clip_contents = true
	add_child(_design_canvas)
	resized.connect(_layout_design_canvas)
	_layout_design_canvas()

	## The world viewport is the one place the hamlet pair is consumed: 640x360
	## logical pixels scaled 2x with nearest scaling, exactly like the preview.
	_view = HamletConceptViewScript.new()
	_view.name = "HamletConceptView"
	add_child(_view)
	move_child(_view, 1)
	_view.load_default_assets()
	_layout_design_canvas()

	_build_header()
	_build_feedback()
	_build_landmarks()
	_build_town_dialogue()
	_unlock_reasons = _derive_unlock_reasons()
	_update_progress_markers(_as_dictionary(_profile.get("progression", {})))
	_update_nearby_feature()


func _build_header() -> void:
	_header = PanelContainer.new()
	_header.name = "HubHeader"
	_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var header_style := ShellThemeScript.crafted_panel()
	header_style.content_margin_top = 6
	header_style.content_margin_bottom = 6
	_header.add_theme_stylebox_override("panel", header_style)
	_place_control(_header, HEADER_RECT)
	_design_canvas.add_child(_header)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 16)
	_header.add_child(row)
	var identity := VBoxContainer.new()
	identity.mouse_filter = Control.MOUSE_FILTER_IGNORE
	identity.custom_minimum_size.x = 132
	identity.add_theme_constant_override("separation", 0)
	row.add_child(identity)
	identity.add_child(_copy_label(TITLE_TEXT, "HubIdentity", 22))
	_profile_label = _copy_label("", "HubProfile", 18)
	identity.add_child(_profile_label)
	var objective := VBoxContainer.new()
	objective.mouse_filter = Control.MOUSE_FILTER_IGNORE
	objective.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	objective.add_theme_constant_override("separation", 0)
	row.add_child(objective)
	objective.add_child(_copy_label("当前目标", "HubObjectiveCaption", 18))
	_objective_label = _copy_label("", "HubObjective", 22)
	_objective_label.clip_text = true
	_objective_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	objective.add_child(_objective_label)
	_character_button = _compact_button("成长 C", "OpenCharacter")
	_character_button.pressed.connect(func(): character_requested.emit())
	row.add_child(_character_button)
	_story_button = _compact_button("见闻 J", "OpenStory")
	_story_button.pressed.connect(func(): story_requested.emit())
	row.add_child(_story_button)
	_info_toggle = _compact_button("近况", "HubInformationToggle")
	_info_toggle.pressed.connect(_on_information_toggle_pressed)
	row.add_child(_info_toggle)
	# The existing SessionMenu owns the F1 settings launcher at the top right.
	# Reserve its space instead of drawing a second launcher underneath it.
	var settings_space := Control.new()
	settings_space.name = "HubSettingsSpace"
	settings_space.custom_minimum_size.x = 122
	settings_space.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(settings_space)


func _build_feedback() -> void:
	_nearby_panel = Panel.new()
	_nearby_panel.name = "HubProximityPrompt"
	_nearby_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_nearby_panel.add_theme_stylebox_override("panel", _prompt_style())
	_place_control(_nearby_panel, Rect2(Vector2.ZERO, Vector2(PROMPT_MIN_WIDTH, PROMPT_HEIGHT)))
	_design_canvas.add_child(_nearby_panel)
	_nearby_label = _copy_label("", "HubNearby", PROMPT_FONT_SIZE)
	_nearby_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_nearby_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_nearby_panel.add_child(_nearby_label)
	_nearby_panel.hide()

	_detail_panel = PanelContainer.new()
	_detail_panel.name = "HubInformationDetail"
	_detail_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_detail_panel.add_theme_stylebox_override("panel", _hotspot_style(Color("111820f2"), OLD_COPPER, 1))
	_place_control(_detail_panel, INFO_DETAIL_RECT)
	_design_canvas.add_child(_detail_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	_detail_panel.add_child(column)
	var heading := HBoxContainer.new()
	column.add_child(heading)
	var title := _copy_label(DETAIL_TITLE_TEXT, "Title", 22)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	var close := _compact_button("收起", "HubInformationClose")
	close.pressed.connect(func(): set_information_details_expanded(false))
	heading.add_child(close)
	var scroll := ScrollContainer.new()
	scroll.name = "HubInformationScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.follow_focus = true
	column.add_child(scroll)
	var content := VBoxContainer.new()
	content.name = "HubInformationContent"
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	content.add_theme_constant_override("separation", 12)
	scroll.add_child(content)
	_detail_objective_label = _detail_copy(content, "Objective", 22)
	_detail_status_label = _detail_copy(content, "Status", 22)
	_detail_story_label = _detail_copy(content, "TownNarrative", 22)
	_detail_result_label = _detail_copy(content, "Settlement", 22)
	_progress_label = _detail_copy(content, "HubProgressSummary", 18)
	_detail_help_label = _detail_copy(content, "Help", 18)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	column.add_child(actions)
	var settings := _compact_button("画面与声音 F1", "HubSettings")
	settings.pressed.connect(_open_settings)
	actions.add_child(settings)
	var title_button := _compact_button("返回标题", "ReturnToTitle")
	title_button.pressed.connect(_on_title_pressed)
	actions.add_child(title_button)
	_detail_panel.hide()
	scroll.resized.connect(func(): _reflow_information_content.call_deferred())
	scroll.get_v_scroll_bar().visibility_changed.connect(func(): _reflow_information_content.call_deferred())
func _build_landmarks() -> void:
	for feature_id: String in LANDMARK_FEATURE_IDS:
		var landmark := TownLandmark.new(feature_id)
		landmark.toggle_mode = false
		landmark.focus_mode = Control.FOCUS_ALL
		landmark.mouse_filter = Control.MOUSE_FILTER_STOP
		landmark.clip_text = false
		landmark.pressed.connect(navigation_card_activated.bind(feature_id))
		landmark.gui_input.connect(_on_landmark_gui_input.bind(feature_id))
		landmark.add_theme_stylebox_override("normal", _landmark_style(false, false))
		landmark.add_theme_stylebox_override("hover", _landmark_style(true, false))
		landmark.add_theme_stylebox_override("pressed", _landmark_style(true, true))
		landmark.add_theme_stylebox_override("focus", _landmark_focus_style())
		_design_canvas.add_child(landmark)
		var copy := Control.new()
		copy.name = "Copy"
		copy.mouse_filter = Control.MOUSE_FILTER_IGNORE
		copy.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		copy.offset_left = 10.0
		copy.offset_top = 4.0
		copy.offset_right = -10.0
		copy.offset_bottom = -4.0
		landmark.add_child(copy)
		var title := _copy_label("", "Title", 22)
		title.clip_text = true
		title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		title.position = Vector2.ZERO
		title.size = Vector2(LANDMARK_SIZE.x - 20.0, 32.0)
		copy.add_child(title)
		var status := _copy_label("", "Status", 18)
		status.clip_text = true
		status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		status.position = Vector2(0.0, 36.0)
		status.size = Vector2(LANDMARK_SIZE.x - 20.0, 28.0)
		copy.add_child(status)
		_landmarks[feature_id] = landmark
	_view.set_destination(_destination_id)


func wayfinding_report() -> Dictionary:
	var entry := _view.entry_for(_destination_id) if _view != null else {}
	if entry.is_empty(): return {}
	var delta: Vector2 = entry.feet - _view.hero_world_position()
	var arrived := delta.length() <= float(entry.radius)
	var arrows := ["→", "↘", "↓", "↙", "←", "↖", "↑", "↗"]
	return {"id": _destination_id, "arrived": arrived, "distance": delta.length(),
		"direction": arrows[posmod(roundi(delta.angle() * 4.0 / PI), 8)]}


func _on_landmark_gui_input(event: InputEvent, feature_id: String) -> void:
	if not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	var key := key_event.physical_keycode if key_event.physical_keycode != KEY_NONE else key_event.keycode
	if key != KEY_E:
		return
	var landmark := get_landmark(feature_id)
	if landmark == null:
		return
	landmark.accept_event()
	navigation_card_activated(feature_id)


func _landmark_style(hovered: bool, nearby: bool) -> StyleBoxFlat:
	var key := "%s/%s" % [hovered, nearby]
	if _landmark_styles.has(key):
		return _landmark_styles[key]
	var style := StyleBoxFlat.new()
	style.bg_color = Color("111820d9" if nearby else "111820b8")
	var amber := ShellThemeScript.AMBER
	var grey := COOL_GREY
	if hovered or nearby:
		style.border_color = Color(amber.r, amber.g, amber.b, 0.95 if nearby else 0.72)
	else:
		style.border_color = Color(grey.r, grey.g, grey.b, 0.38)
	style.border_width_top = 1 if hovered or nearby else 0
	style.border_width_bottom = 1
	style.set_corner_radius_all(0)
	style.content_margin_left = 10.0
	style.content_margin_top = 5.0
	style.content_margin_right = 10.0
	style.content_margin_bottom = 5.0
	_landmark_styles[key] = style
	return style


func _landmark_focus_style() -> StyleBoxFlat:
	var style := _landmark_style(false, true).duplicate() as StyleBoxFlat
	var bone := ShellThemeScript.BONE
	style.border_color = Color(bone.r, bone.g, bone.b, 0.9)
	style.border_width_left = 1
	style.border_width_right = 1
	return style


func _landmark_world_rect(feature_id: String) -> Rect2:
	var entry := _feature_entry(feature_id)
	if entry.is_empty():
		return Rect2()
	var feet: Vector2 = entry.get("feet", Vector2.ZERO)
	var building := _view._drawn_rect(entry)
	var building_top := feet.y - 112.0
	if building.size != Vector2.ZERO:
		building_top = building.position.y
	var size := LANDMARK_SIZE * DESIGN_TO_WORLD
	var position := Vector2(feet.x - size.x * 0.5, building_top - LANDMARK_GAP * DESIGN_TO_WORLD - size.y)
	return Rect2(position, size)


func _landmark_design_rect(feature_id: String) -> Rect2:
	var world_rect := _landmark_world_rect(feature_id)
	if world_rect == Rect2() or _view == null or _design_canvas == null:
		return Rect2()
	var screen_point := _view.design_point_for_world(world_rect.position, _design_canvas.position, _design_canvas.scale)
	var canvas_point := _design_canvas.get_global_transform_with_canvas().affine_inverse() * screen_point
	return Rect2(canvas_point, LANDMARK_SIZE)


func get_landmark(feature_id: String) -> Button:
	return _landmarks.get(feature_id, null) as Button


func _update_landmarks() -> void:
	if _view == null or _design_canvas == null:
		return
	var camera := Rect2(_view.camera_world_offset(), Vector2(_view.world_viewport.size))
	var nearby_id := _view.nearby_feature_id()
	_nav_states = navigation_state()
	for state: Dictionary in _nav_states:
		var feature_id := String(state.id)
		var landmark := get_landmark(feature_id)
		if landmark == null:
			continue
		var world_rect := _landmark_world_rect(feature_id)
		var design_rect := _landmark_design_rect(feature_id)
		landmark.visible = camera.encloses(world_rect) and LANDMARK_SAFE_RECT.encloses(design_rect) and not is_dialogue_open() and not _details_expanded
		_place_control(landmark, Rect2(design_rect.position.floor(), LANDMARK_SIZE))
		var title := landmark.get_node("Copy/Title") as Label
		var status := landmark.get_node("Copy/Status") as Label
		var nearby := feature_id == nearby_id
		var selected := feature_id == _destination_id
		title.text = String(state.get("title", feature_id))
		status.text = String(state.get("status", ""))
		title.add_theme_color_override("font_color", ShellThemeScript.BONE if nearby or selected else COOL_GREY)
		status.add_theme_color_override("font_color", ShellThemeScript.AMBER if nearby or selected else COOL_GREY)
		landmark.tooltip_text = "%s\n%s\n%s\n点击指路；走近后点击或按 E 进入" % [
			title.text, status.text, String(state.get("detail", "")),
		]
		landmark.add_theme_stylebox_override("normal", _landmark_style(false, nearby))
		landmark.add_theme_stylebox_override("hover", _landmark_style(true, nearby))
		landmark.add_theme_stylebox_override("pressed", _landmark_style(true, nearby))
		if not landmark.visible:
			if landmark.has_focus():
				landmark.release_focus()
			continue
	_wire_landmark_focus_neighbours()


func _wire_landmark_focus_neighbours() -> void:
	var visible_ids: Array[String] = []
	for feature_id: String in LANDMARK_FEATURE_IDS:
		var landmark := get_landmark(feature_id)
		if landmark != null and landmark.is_visible():
			visible_ids.append(feature_id)
	for index in visible_ids.size():
		var landmark := get_landmark(visible_ids[index])
		landmark.focus_neighbor_right = NodePath("")
		landmark.focus_neighbor_left = NodePath("")
		landmark.focus_next = NodePath("")
		landmark.focus_previous = NodePath("")
		var right := get_landmark(visible_ids[posmod(index + 1, visible_ids.size())])
		var left := get_landmark(visible_ids[posmod(index - 1, visible_ids.size())])
		if landmark == null or right == null or left == null or visible_ids.size() < 2:
			continue
		landmark.focus_neighbor_right = landmark.get_path_to(right)
		landmark.focus_next = landmark.focus_neighbor_right
		landmark.focus_neighbor_left = landmark.get_path_to(left)
		landmark.focus_previous = landmark.focus_neighbor_left


func _copy_label(text: String, node_name: String, font_size: int) -> Label:
	var label := Label.new()
	label.name = node_name
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", ShellThemeScript.BONE if font_size >= 22 else COOL_GREY)
	return label


func _detail_copy(parent: Node, node_name: String, font_size: int) -> Label:
	var label := _copy_label("", node_name, font_size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	parent.add_child(label)
	return label


func _reflow_information_content() -> void:
	if _detail_panel == null or not _detail_panel.visible:
		return
	var scroll := _detail_panel.find_child("HubInformationScroll", true, false) as ScrollContainer
	var content := scroll.get_child(0) as VBoxContainer
	var bar := scroll.get_v_scroll_bar()
	var available := maxf(1.0, scroll.size.x - (bar.size.x if bar.visible else 0.0))
	content.size.x = available
	for child: Label in content.get_children():
		child.size.x = available
		var font_size := child.get_theme_font_size("font_size")
		var lines := maxi(1, child.get_line_count())
		# Reserve full font line boxes and the last line's edge, independently of
		# the scroll container's earlier minimum-size measurement at another width.
		child.custom_minimum_size.y = maxf(child.get_minimum_size().y, ceilf(child.get_theme_font("font").get_height(font_size)) * lines + child.get_theme_constant("line_spacing") * maxi(0, lines - 1)) + 2.0
	content.notification(Container.NOTIFICATION_SORT_CHILDREN)


func _compact_button(text: String, node_name: String) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.add_theme_font_size_override("font_size", 22)
	button.add_theme_stylebox_override("normal", _toggle_style("button"))
	button.add_theme_stylebox_override("hover", _toggle_style("hover"))
	button.add_theme_stylebox_override("pressed", _toggle_style("selected"))
	return button


func _open_settings() -> void:
	var ancestor := get_parent()
	while ancestor != null:
		if ancestor.has_method("get_session_menu"):
			var menu: Node = ancestor.call("get_session_menu")
			if menu != null:
				set_information_details_expanded(false)
				menu.call("open_menu")
			return
		ancestor = ancestor.get_parent()


func _apply_presentation() -> void:
	if not _built:
		return
	var resources := _as_dictionary(_profile.get("resources", {}))
	var law_tallies := _as_dictionary(resources.get("law_tallies", {}))
	var progression := _as_dictionary(_profile.get("progression", {}))
	var class_name_text := String({"ranger": "游侠", "alchemist": "炼金", "mage": "法师"}.get(String(_profile.get("initial_class", "未建立")), String(_profile.get("initial_class", "未建立"))))
	_profile_label.text = "Lv.%d · %s" % [int(_character_snapshot.get("level", 1)), class_name_text]
	_profile_label.tooltip_text = "经验 %d / %d\n律筹：添铸 %d · 改写 %d · 精炼 %d" % [
		int(_character_snapshot.get("level_experience", 0)), int(_character_snapshot.get("next_level_experience", 0)),
		int(law_tallies.get("inscribe", 0)), int(law_tallies.get("rewrite", 0)), int(law_tallies.get("refine", 0)),
	]
	var points := int(_character_snapshot.get("points_available", 0))
	_character_button.text = "成长 C · %d点" % points if points > 0 else "成长 C"
	_update_progress_markers(progression)
	_progress_label.text = _early_progress_text(progression).replace("Build", "构筑").replace("Auto", "代行")
	_objective_label.text = _next_objective_text()
	var story_objective: Dictionary = _story_snapshot.get("current_objective", {})
	if not story_objective.is_empty():
		_objective_label.text = String(story_objective.get("text", _objective_label.text))
	_objective_label.tooltip_text = _objective_label.text
	_detail_objective_label.text = "当前目标：" + _objective_label.text
	var message := _localized_status(_status_message)
	_detail_status_label.text = message if not message.is_empty() else DETAIL_STATUS_EMPTY_TEXT
	_detail_status_label.tooltip_text = _detail_status_label.text
	var narrative: Array[String] = []
	for change: Dictionary in _story_snapshot.get("town_changes", []):
		narrative.append(String(change.get("text", change.get("description", change.get("title", "")))))
	for entry: Dictionary in _story_snapshot.get("available_conversations", []):
		narrative.append("%s · %s" % [String(entry.get("npc_name", "")), String(entry.get("title", ""))])
	_detail_story_label.text = "\n\n".join(narrative)
	_detail_story_label.visible = not narrative.is_empty()
	_detail_result_label.text = _settlement_text()
	_detail_help_label.text = HELP_COPY_TEXT
	_reflow_information_content.call_deferred()
	_info_toggle.tooltip_text = "%s\n%s" % [DETAIL_TITLE_TEXT, _detail_status_label.text]
	var unread := 0
	for entry in _story_snapshot.get("journal_entries", []):
		if not bool(entry.get("is_read", false)): unread += 1
	_story_button.text = "见闻 J · %d" % unread if unread > 0 else "见闻 J"
	# Reflow labels after live growth/unread counts update the top band.
	_header.notification(Container.NOTIFICATION_SORT_CHILDREN)
	(_header.get_child(0) as Container).notification(Container.NOTIFICATION_SORT_CHILDREN)
	for child in _header.get_child(0).get_children():
		if child is Container: child.notification(Container.NOTIFICATION_SORT_CHILDREN)
	_refresh_town_conversations()
	_update_navigation_state()


func _layout_design_canvas() -> void:
	if _design_canvas == null:
		return
	var canvas_scale := minf(size.x / DESIGN_SIZE.x, size.y / DESIGN_SIZE.y)
	if canvas_scale <= 0.0:
		return
	_design_canvas.scale = Vector2.ONE * canvas_scale
	_design_canvas.position = (size - DESIGN_SIZE * canvas_scale) * 0.5
	if _view != null:
		_view.set_world_scale(maxi(1, int(floorf(canvas_scale * float(WORLD_SCALE_BASE)))), size)
		_update_nearby_feature()


func _update_nearby_feature() -> void:
	## The badge follows the live avatar cell: it is measured from its own copy and
	## placed beside the feet, never as a fixed band across the bottom of the frame.
	if _nearby_panel == null or _view == null:
		return
	_update_navigation_state()
	if _details_expanded or is_dialogue_open():
		_nearby_panel.hide()
		_prompt_rect = Rect2()
		return
	var feature_id := _view.nearby_feature_id()
	_update_resident_markers()
	var resident_id := nearby_resident_id()
	if feature_id.is_empty() and resident_id.is_empty():
		_nearby_panel.visible = false
		_prompt_rect = Rect2()
		return
	_nearby_label.text = "[E / Space] 打开"
	if not resident_id.is_empty():
		_nearby_label.text = "[E] 与%s交谈" % String(_resident_conversations[resident_id].get("npc_name", ""))
	_nearby_label.tooltip_text = _nearby_label.text
	_prompt_rect = _resolve_prompt_rect()
	_place_control(_nearby_panel, _prompt_rect)
	_place_control(_nearby_label, Rect2(Vector2.ZERO, _prompt_rect.size))
	_nearby_panel.visible = true


func get_prompt_rect() -> Rect2:
	## Design-space rectangle of the proximity badge while it is on screen, an empty
	## rectangle while the avatar stands away from every stand.
	if _nearby_panel == null or not _nearby_panel.visible:
		return Rect2()
	return _prompt_rect


func information_details_expanded() -> bool:
	return _details_expanded


func set_information_details_expanded(expanded: bool) -> void:
	## The explicit toggle: the complete status copy, the complete settlement line
	## and the controls copy are one click away, while the critical objective stays
	## untouched in the strip above the collapsible panel.
	_details_expanded = expanded
	if _detail_panel != null:
		_detail_panel.visible = expanded
	if _info_toggle != null:
		_info_toggle.text = "收起近况" if expanded else "近况"
	_update_resident_markers()
	_update_nearby_feature()
	_reflow_information_content.call_deferred()


func _on_information_toggle_pressed() -> void:
	set_information_details_expanded(not _details_expanded)


func _settlement_text() -> String:
	if _last_result.is_empty():
		return "最近结算：暂无契约记录"
	var rewards := _as_dictionary(_last_result.get("rewards", {}))
	var equipment_count := maxi(0, int(rewards.get("equipment_drop_count", 0)))
	var drop_summary := "装备 %d 件" % equipment_count if equipment_count > 0 else String(_last_result.get("drop", _last_result.get("last_drop", rewards.get("drop_label", rewards.get("drop_id", "无")))))
	return "最近：%s\n掉落：%s" % [_localized_outcome(String(_last_result.get("outcome", "未知"))), drop_summary]


func _localized_outcome(outcome: String) -> String:
	return String(_KNOWN_OUTCOMES.get(outcome, outcome))


func _localized_status(message: String) -> String:
	return PlayerFacingStatusScript.message(message)


func _hero_foot_design_point() -> Vector2:
	## Where the avatar's foot point lands on the 1280x720 canvas with the live
	## camera of this screen.
	if _view == null:
		return HERO_ENTRY_FOOT_ANCHOR
	var screen_point := _view.design_point_for_world(_view.hero_world_position(), _design_canvas.position, _design_canvas.scale)
	return _design_canvas.get_global_transform_with_canvas().affine_inverse() * screen_point


func _hero_cell_design_rect() -> Rect2:
	## The avatar's own drawn cell in design space, read from the metadata the
	## renderer draws from. The fallback is the published 48x48 action cell with
	## its (24,44) anchor, so the badge keeps its distances while art is pending.
	var cell := Vector2(48.0, 48.0)
	var anchor := Vector2(24.0, 44.0)
	var foot := Vector2.ZERO
	if _view != null:
		var metadata: Dictionary = _view._hero_sprite_metadata()
		var rect: Array = metadata.get("rect", [])
		var metadata_anchor: Array = metadata.get("anchor", [])
		if rect.size() == 4 and metadata_anchor.size() == 2:
			cell = Vector2(float(rect[2]), float(rect[3]))
			anchor = Vector2(float(metadata_anchor[0]), float(metadata_anchor[1]))
		foot = _view.hero_world_position()
	if _view == null:
		return Rect2((foot - anchor) * WORLD_TO_DESIGN, cell * WORLD_TO_DESIGN)
	var screen_to_canvas := _design_canvas.get_global_transform_with_canvas().affine_inverse()
	var top_left := screen_to_canvas * _view.design_point_for_world(foot - anchor, _design_canvas.position, _design_canvas.scale)
	var bottom_right := screen_to_canvas * _view.design_point_for_world(foot - anchor + cell, _design_canvas.position, _design_canvas.scale)
	return Rect2(top_left, bottom_right - top_left)


func _prompt_width() -> float:
	## Just the width the badge's own copy needs, clamped to its published bounds.
	var font: Font = _nearby_label.get_theme_font("font")
	var measured := PROMPT_MIN_WIDTH
	if font != null:
		measured = font.get_string_size(_nearby_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, PROMPT_FONT_SIZE).x + 24.0
	return clampf(measured, PROMPT_MIN_WIDTH, PROMPT_MAX_WIDTH)


func _resolve_prompt_rect() -> Rect2:
	## Under the feet while the world leaves room and above the head when it does
	## not: never over the avatar's own cell and never off the canvas.
	var foot := _hero_foot_design_point()
	var cell := _hero_cell_design_rect()
	var bottom_limit := DESIGN_SIZE.y - PROMPT_CLEARANCE
	var width := _prompt_width()
	var top := cell.end.y + PROMPT_GAP
	if top + PROMPT_HEIGHT > bottom_limit:
		var above := cell.position.y - PROMPT_GAP - PROMPT_HEIGHT
		top = above if above >= HEADER_RECT.end.y + PROMPT_CLEARANCE else bottom_limit - PROMPT_HEIGHT
	top = clampf(top, HEADER_RECT.end.y + PROMPT_CLEARANCE, bottom_limit - PROMPT_HEIGHT)
	var left := clampf(foot.x - width * 0.5, PROMPT_MARGIN, DESIGN_SIZE.x - PROMPT_MARGIN - width)
	## Snapped to the pixel grid like every other hub rectangle: the world is drawn
	## at whole-number scale, so a half-pixel badge would soften its own edge.
	return Rect2(floorf(left), floorf(top), ceilf(width), PROMPT_HEIGHT)


func navigation_state() -> Array:
	## One card state per facility, in the published order. The hub derives every
	## field from the save snapshot it was handed; the bar only draws the copy.
	var progression := _as_dictionary(_profile.get("progression", {}))
	var earned_rewards := _as_array(_campaign_snapshot.get("earned_reward_tags", []))
	var states: Array = []
	for feature_id: String in LANDMARK_FEATURE_IDS:
		states.append({
			"id": feature_id,
			"title": _nav_title(feature_id),
			"locked": _nav_locked(feature_id, progression, earned_rewards),
			"reason": String(_unlock_reasons.get(feature_id, "")),
			"status": _nav_status_text(feature_id),
			"detail": _nav_detail(feature_id, progression, earned_rewards),
			"current": feature_id == _view.nearby_feature_id() if _view != null else false,
		})
	return states


func get_navigation_state(feature_id: String) -> Dictionary:
	for state: Dictionary in navigation_state():
		if String(state.get("id", "")) == feature_id:
			return state
	return {}


func get_navigation_bar():
	## Legacy query method: the bottom bar was removed rather than hidden.
	return null


func navigation_card_activated(feature_id: String) -> bool:
	## A far click is a request for directions, not a remote facility opening.
	if is_dialogue_open() or _details_expanded or not LANDMARK_FEATURE_IDS.has(feature_id):
		return false
	_destination_id = feature_id
	_view.set_destination(feature_id)
	_update_landmarks()
	if _navigation_has_focus(): get_viewport().gui_get_focus_owner().release_focus()
	var entry := _view.entry_for(feature_id)
	if not entry.is_empty() and _view.hero_world_position().distance_to(entry.feet) <= float(entry.radius):
		_on_hub_entry_pressed(feature_id)
	return true


func _update_navigation_state() -> void:
	_update_landmarks()


func _update_progress_markers(progression: Dictionary) -> void:
	## The world markers stay the published placement labels plus one short player
	## note; the same derivation feeds the navigation cards, so a marker and its
	## card can never disagree about what is open.
	if _view == null:
		return
	var earned_rewards := _as_array(_campaign_snapshot.get("earned_reward_tags", []))
	_marker_notes["contract"] = _nav_detail("contract", progression, earned_rewards)
	_marker_notes["loadout"] = _nav_detail("loadout", progression, earned_rewards)
	_marker_notes["forge"] = _nav_detail("forge", progression, earned_rewards)
	_marker_notes["training"] = _nav_detail("training", progression, earned_rewards)
	_marker_notes["proxy"] = _nav_detail("proxy", progression, earned_rewards)
	_marker_notes["immortality"] = ""
	_update_navigation_state()


func _nav_title(feature_id: String) -> String:
	return String({
		"contract": "行路契台",
		"loadout": "备行架",
		"forge": "回火砧",
		"training": "验律场",
		"proxy": "代行舱",
	}.get(feature_id, feature_id))


func _nav_locked(feature_id: String, progression: Dictionary, earned_rewards: Array) -> bool:
	match feature_id:
		"loadout":
			return false # The rack already allows viewing the starter loadout.
		"forge":
			return not ("law_forge_unlock" in earned_rewards)
		"proxy":
			return not bool(progression.get("proxy_unlocked", false))
	return false


func _nav_status_text(feature_id: String) -> String:
	## The one line a player reads on a card. A locked page leads with the
	## published non-colour lock mark and then names the single authored gate that
	## opens it; an open page shows the same note its world marker carries.
	var progression := _as_dictionary(_profile.get("progression", {}))
	var earned_rewards := _as_array(_campaign_snapshot.get("earned_reward_tags", []))
	if _nav_locked(feature_id, progression, earned_rewards):
		var reason := String(_unlock_reasons.get(feature_id, ""))
		return LOCK_MARK if reason.is_empty() else "%s %s" % [LOCK_MARK, reason]
	return _nav_detail(feature_id, progression, earned_rewards)


func _nav_detail(feature_id: String, progression: Dictionary, earned_rewards: Array) -> String:
	## The short note the world marker shows. It carries the next objective for the
	## contract board and the exact reason for every page that is not open yet.
	match feature_id:
		"contract":
			return _player_nav_node_label()
		"loadout":
			return "比较已开放" if "equipment_compare_unlock" in earned_rewards else "起步装备可查看"
		"forge":
			return "已解锁" if "law_forge_unlock" in earned_rewards else "封印中"
		"training":
			return "已验证" if _profile_training_complete() else "未验证"
		"proxy":
			if bool(progression.get("proxy_unlocked", false)):
				return "已解锁"
			var proxy_reason := String(_unlock_reasons.get("proxy", ""))
			if proxy_reason.is_empty():
				return "封印中"
			return "封印中 · %s" % proxy_reason
	return ""


func _player_nav_node_label() -> String:
	## Only an authored objective reaches the player; an unauthored or side node
	## keeps the existing neutral wording instead of leaking an internal id.
	var next_id := String(_campaign_snapshot.get("next_mainline_node_id", ""))
	if _SHORT_NODE_LABELS.has(next_id):
		return String(_SHORT_NODE_LABELS[next_id])
	return "支线复测" if next_id.is_empty() else "可挑战"


func _feature_entry(feature_id: String) -> Dictionary:
	## Layout first: the published placement decides where a station stands and
	## what it is called. Only an unpublished entry falls back to the legacy
	## 1280x720 anchor table halved into the 640x360 world.
	if _view == null:
		return {}
	var entry := _view.entry_for(feature_id)
	if not entry.is_empty():
		if not bool(entry.get("from_layout", false)):
			var fallback: Variant = LEGACY_FEATURE_POSITIONS.get(feature_id, null)
			if fallback != null:
				entry["feet"] = (fallback as Vector2) * DESIGN_TO_WORLD
		return entry
	return {}


func _early_progress_text(progression: Dictionary) -> String:
	var colossus_done := bool(progression.get("threshold_colossus_defeated", false))
	var auto_wins := maxi(0, int(progression.get("auto_contract_wins", 0)))
	var complete := bool(progression.get("early_game_complete", false))
	var training_done := bool(progression.get(
		"build_training_complete",
		progression.get("training_complete", progression.get("all_builds_verified", _profile_training_complete() or colossus_done or auto_wins > 0 or complete))
	))
	return "Build %s · 巨像 %s · Auto %s" % [
		"✓" if training_done else "…",
		"✓" if colossus_done or auto_wins > 0 or complete else "…",
		"✓" if auto_wins > 0 or complete else "…",
	]


func _next_objective_text() -> String:
	var next_id := String(_campaign_snapshot.get("next_mainline_node_id", ""))
	match next_id:
		"tutorial_ranger_basics":
			return "完成游侠基础教程"
		"mainline_01_first_hunt":
			return "前往契约台，开始初次狩猎"
		"mainline_02_priority_under_pressure":
			return "前往契约台，应对冲锋与远程压力"
		"mainline_03_first_elite":
			return "挑战首个精英，取得孳生分裂装备"
		"mainline_04_hazard_and_forge":
			return "穿越危地，取得律筹锻造能力"
		"mainline_05_growth_gate":
			return "修正构筑瓶颈，通过增长门槛"
		"threshold_colossus":
			return "准备并挑战阈门巨像"
		"auto_certification":
			return "确认四白核心，完成一次 Auto 考核"
	if bool(_campaign_snapshot.get("early_game_complete", false)):
		return "前期毕业完成；可继续支线验证构筑"
	return "前往契约台查看当前可用节点"


func _short_node_label(node_id: String) -> String:
	return String(_SHORT_NODE_LABELS.get(node_id, "支线复测" if node_id.is_empty() else node_id))


func _profile_training_complete() -> bool:
	var training := _as_dictionary(_profile.get("training", {}))
	var reports_by_fingerprint := _as_dictionary(training.get("reports_by_fingerprint", {}))
	for fingerprint: Variant in reports_by_fingerprint:
		var report := _as_dictionary(reports_by_fingerprint.get(fingerprint, {}))
		if String(fingerprint).strip_edges().is_empty():
			continue
		if String(report.get("build_fingerprint", "")).strip_edges() != String(fingerprint).strip_edges():
			continue
		if String(report.get("state", "")).strip_edges().to_lower() == "exponential":
			return true
	return false


func _place_control(control: Control, rect: Rect2) -> void:
	control.position = rect.position
	control.size = rect.size
	control.custom_minimum_size = rect.size


func _hotspot_style(fill: Color, border: Color, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(0)
	style.content_margin_left = 10.0
	style.content_margin_top = 6.0
	style.content_margin_right = 10.0
	style.content_margin_bottom = 6.0
	return style


func _prompt_style() -> StyleBox:
	## The proximity badge keeps the amber edge of the old prompt but only the
	## width its own copy needs.
	var style := ShellThemeScript.panel_style()
	style.content_margin_left = 10.0
	style.content_margin_top = 2.0
	style.content_margin_right = 10.0
	style.content_margin_bottom = 2.0
	return style


func _toggle_style(kind: String) -> StyleBoxTexture:
	var style := ShellThemeScript.panel_style(kind)
	style.content_margin_left = 8.0
	style.content_margin_top = 1.0
	style.content_margin_right = 8.0
	style.content_margin_bottom = 1.0
	return style


func _as_dictionary(value: Variant) -> Dictionary:
	return value as Dictionary if value is Dictionary else {}


func _as_array(value: Variant) -> Array:
	return value as Array if value is Array else []


func _on_hub_entry_pressed(feature_id: String) -> void:
	if feature_id == "contract":
		contract_requested.emit()
	else:
		feature_requested.emit(feature_id)


func _on_title_pressed() -> void:
	title_requested.emit()
