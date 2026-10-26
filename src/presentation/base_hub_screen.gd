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
const TownPresenterScript = preload("res://src/presentation/town_presenter.gd")
const TownRuntimeScript = preload("res://src/runtime/world/town_runtime.gd")
const TownControllerScript = preload("res://src/runtime/world/town_controller.gd")
const TownDialogueScript = preload("res://src/presentation/town_dialogue.gd")
const UiKit := preload("res://src/presentation/ui_kit.gd")
## Collaborators in src/presentation/base_hub/. Each holds a reference back to
## this screen and reads its snapshots, town runtime and presenter through it.
const HubInteractionScript := preload("res://src/presentation/base_hub/hub_interaction.gd")
const HubLandmarksScript := preload("res://src/presentation/base_hub/hub_landmarks.gd")
const HubObjectivesScript := preload("res://src/presentation/base_hub/hub_objectives.gd")
const HubResidentsScript := preload("res://src/presentation/base_hub/hub_residents.gd")
const HubStyles := preload("res://src/presentation/base_hub/hub_styles.gd")
## Copy tables owned by HubObjectives, re-exported for callers and tests.
const FIRST_HUNT_OBJECTIVE_TEXT := HubObjectivesScript.FIRST_HUNT_OBJECTIVE_TEXT
const _UNLOCK_REASONS := HubObjectivesScript._UNLOCK_REASONS
const FILLED_MARK := HubObjectivesScript.FILLED_MARK
const LOCK_MARK := HubObjectivesScript.LOCK_MARK
const TALK_RADIUS := 36.0
## A resident standing at its own stand keeps E even when the hero is a step
## closer to the facility feet: dialogue beats the facility badge up to this slack.
const RESIDENT_PRIORITY_SLACK := 8.0
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
const TITLE_TEXT := "Hearthside"
const COOL_GREY := Color("B0B8BA")
const OLD_COPPER := ShellThemeScript.AMBER
const HERO_SPEED := 96.0
## The authored entry foot point of the published framing, in design-space
## screen coordinates: the hero walks in at the concept anchor (320, 260) of the
## 640x360 viewport, which is (640, 520) on the 1280x720 canvas. The navigation
## band below it must never cover this point.
const HERO_ENTRY_FOOT_ANCHOR := Vector2(640.0, 520.0)
const HEADER_RECT := Rect2(16.0, 12.0, 1248.0, 80.0)
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
const HELP_COPY_TEXT := "WASD / Arrows Move · Follow the objective arrow · E Interact nearby\nTab Select visible landmark · C Progression · J Journal · Esc Leave landmark · F1 Settings"
const DETAIL_TITLE_TEXT := "Town News"
const DETAIL_STATUS_EMPTY_TEXT := "No new status updates on this screen."

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
var _view: TownPresenterScript
var _town_controller: TownControllerScript
var _town: TownRuntimeScript
var town_load_report: Dictionary = {}
var _nav_states: Array = []
var _unlock_reasons: Dictionary = {}
var _dialogue: TownDialogueScript
var _resident_conversations: Dictionary = {}
var _resident_markers: Dictionary = {}
var _detail_objective_label: Label
var _detail_story_label: Label
var _header: PanelContainer
var _landmarks: Dictionary = {}
var _interaction: HubInteractionScript
var _landmark_ui: HubLandmarksScript
var _objectives: HubObjectivesScript
var _residents: HubResidentsScript


class TownLandmark extends Button:
	var feature_id := ""


	func _init(landmark_feature_id: String) -> void:
		feature_id = landmark_feature_id
		name = "TownLandmark_" + feature_id


func _init() -> void:
	_interaction = HubInteractionScript.new(self)
	_landmark_ui = HubLandmarksScript.new(self)
	_objectives = HubObjectivesScript.new(self)
	_residents = HubResidentsScript.new(self)


func _ready() -> void:
	_build_ui()
	_apply_presentation()


func _process(delta: float) -> void:
	if is_dialogue_open() or _details_expanded or _navigation_has_focus():
		return
	var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	move_hero(direction, delta)
	_update_landmark_windows(delta)


func _update_landmark_windows(delta: float) -> void:
	_landmark_ui._update_landmark_windows(delta)


func _navigation_has_focus() -> bool:
	return _landmark_ui._navigation_has_focus()


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
	if key == KEY_TAB and _landmark_ui._focus_visible_landmark(key_event.shift_pressed):
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
	if _landmark_ui._focus_visible_landmark(key_event.shift_pressed):
		get_viewport().set_input_as_handled()


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
	_unlock_reasons = _objectives._derive_unlock_reasons()
	if _built:
		_apply_presentation()


func present_adventure(character: Dictionary, story: Dictionary) -> void:
	_character_snapshot = character.duplicate(true)
	_story_snapshot = story.duplicate(true)
	if _built: _apply_presentation()


func move_hero(direction: Vector2, delta: float) -> void:
	if not _built or not bool(town_load_report.get("ok", false)) or delta <= 0.0 or is_dialogue_open() or _details_expanded:
		return
	_town_controller.advance_frame(direction, delta)


func travel_snapshot() -> Dictionary:
	return _town.travel_snapshot() if _town != null and _town.is_ready() else {}


func restore_travel(snapshot: Dictionary) -> void:
	if _town != null:
		_town.restore_travel(snapshot)


func set_hero_position(position: Vector2) -> void:
	_town.place_hero(position * DESIGN_TO_WORLD)


func get_hero_position() -> Vector2:
	return _town.hero_world_position() / DESIGN_TO_WORLD


func get_nearby_feature_id() -> String:
	return _town.nearby_feature_id()


func get_town_runtime():
	return _town


func activate_nearby_feature() -> bool:
	return _interaction.activate_nearby_feature()


func activate_nearby_interaction() -> bool:
	return _interaction.activate_nearby_interaction()


func nearby_gateway_id() -> String:
	return _interaction.nearby_gateway_id()


## Exit gates open the same screens their facility counterpart does; they never
## start combat themselves. A far press, open dialogue or details does nothing.
func activate_nearby_gateway() -> bool:
	return _interaction.activate_nearby_gateway()


func is_dialogue_open() -> bool:
	return _dialogue != null and _dialogue.is_open()


func dialogue_report() -> Dictionary:
	return _dialogue.dialogue_report() if _dialogue != null else {"open":false}


func nearby_resident_id() -> String:
	return _residents.nearby_resident_id()


func talk_to_resident(resident_id: String) -> bool:
	return _residents.talk_to_resident(resident_id)


func click_at_design_point(point: Vector2) -> bool:
	return _interaction.click_at_design_point(point)


func click_at_world_point(world_point: Vector2) -> bool:
	return _interaction.click_at_world_point(world_point)


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
	return _objectives._early_progress_text(UiKit.as_dictionary(_profile.get("progression", {})))


func get_next_objective_text() -> String:
	return _objectives._next_objective_text()


func get_hub_view() -> TownPresenterScript:
	## Test and main-thread access to the live renderer without going through UI.
	return _view


func get_world_feature_position(feature_id: String) -> Vector2:
	## Hub positions stay in the 1280x720 design space, which is twice the
	## 640x360 logical world. A published placement's world feet are doubled
	## back into it here.
	var entry := _feature_entry(feature_id)
	if entry.is_empty():
		return Vector2.ZERO
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
	_view = TownPresenterScript.new()
	_view.name = "TownPresenter"
	add_child(_view)
	move_child(_view, 1)
	_view.ensure_viewport()
	_town_controller = TownControllerScript.new()
	_town_controller.name = "TownController"
	add_child(_town_controller)
	_town = _town_controller.town
	town_load_report = _view.load_character_assets()
	if bool(town_load_report.get("ok", false)):
		town_load_report = _town_controller.mount(_view.world_viewport)
	if bool(town_load_report.get("ok", false)):
		town_load_report = _view.attach(_town_controller.scene_runtime.presenter, _town.snapshot(), _town_controller.scene_runtime)
	if bool(town_load_report.get("ok", false)):
		_town.state_changed.connect(_on_town_state_changed)
	else:
		_town_controller.abort_loading(town_load_report)
		var failure := Label.new()
		failure.name = "TownLoadFailure"
		failure.text = "Town loading failed: %s" % String(town_load_report.get("error", "unknown"))
		failure.tooltip_text = str(town_load_report.get("errors", []))
		failure.position = Vector2(24, 100)
		_design_canvas.add_child(failure)
	_layout_design_canvas()

	_build_header()
	_build_feedback()
	_landmark_ui._build_landmarks()
	_residents._build_town_dialogue()
	_unlock_reasons = _objectives._derive_unlock_reasons()
	_landmark_ui._update_progress_markers(UiKit.as_dictionary(_profile.get("progression", {})))
	_update_nearby_feature()


func _build_header() -> void:
	_header = PanelContainer.new()
	_header.name = "HubHeader"
	_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	## Quiet slate strip with a copper bottom rule: the ornate frame was reading
	## as the loudest element on a strip that is supposed to stay chrome.
	var header_style := ShellThemeScript.slate_header()
	header_style.content_margin_top = 8
	header_style.content_margin_bottom = 8
	_header.add_theme_stylebox_override("panel", header_style)
	_place_control(_header, HEADER_RECT)
	_design_canvas.add_child(_header)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)
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
	## The objective stays fully readable in place: a compact two-line wrap at the
	## section step, never a clipped pointer that hides guidance in a tooltip.
	_objective_label = _copy_label("", "HubObjective", ShellThemeScript.SECTION_FONT_SIZE)
	_objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_objective_label.max_lines_visible = 2
	_objective_label.clip_text = true
	## Compressed spacing keeps a full two-line objective inside the 72px strip.
	_objective_label.add_theme_constant_override("line_spacing", -8)
	_objective_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_objective_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	objective.add_child(_objective_label)
	_character_button = _compact_button("Talents C", "OpenCharacter")
	_character_button.add_theme_font_size_override("font_size", 18)
	_character_button.pressed.connect(func(): character_requested.emit())
	row.add_child(_character_button)
	_story_button = _compact_button("Journal J", "OpenStory")
	_story_button.add_theme_font_size_override("font_size", 18)
	_story_button.pressed.connect(func(): story_requested.emit())
	row.add_child(_story_button)
	_info_toggle = _compact_button("News", "HubInformationToggle")
	_info_toggle.add_theme_font_size_override("font_size", 18)
	_info_toggle.custom_minimum_size.x = 90
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
	_nearby_panel.add_theme_stylebox_override("panel", HubStyles.prompt_style())
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
	_detail_panel.add_theme_stylebox_override("panel", HubStyles.hotspot_style(Color("1d2731f6"), OLD_COPPER, 1))
	_place_control(_detail_panel, INFO_DETAIL_RECT)
	_design_canvas.add_child(_detail_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	_detail_panel.add_child(column)
	var heading := HBoxContainer.new()
	column.add_child(heading)
	var title := _copy_label(DETAIL_TITLE_TEXT, "Title", ShellThemeScript.SECTION_FONT_SIZE)
	title.add_theme_color_override("font_color", ShellThemeScript.AMBER)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	var close := _compact_button("Collapse", "HubInformationClose")
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
	## Trailing gutter: the last copy line must never render flush against the
	## scroll clip edge (visual backlog: bottom row read as cut off).
	var bottom_gutter := Label.new()
	bottom_gutter.name = "HubInformationBottomGutter"
	bottom_gutter.custom_minimum_size = Vector2(0.0, 8.0)
	bottom_gutter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(bottom_gutter)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	column.add_child(actions)
	var settings := _compact_button("Display and Sound F1", "HubSettings")
	settings.pressed.connect(_open_settings)
	actions.add_child(settings)
	var title_button := _compact_button("Return to Title", "ReturnToTitle")
	title_button.pressed.connect(_on_title_pressed)
	actions.add_child(title_button)
	_detail_panel.hide()
	scroll.resized.connect(func(): _reflow_information_content.call_deferred())
	scroll.get_v_scroll_bar().visibility_changed.connect(func(): _reflow_information_content.call_deferred())


func wayfinding_report() -> Dictionary:
	return _landmark_ui.wayfinding_report()


func _on_landmark_gui_input(event: InputEvent, feature_id: String) -> void:
	_landmark_ui._on_landmark_gui_input(event, feature_id)


func _landmark_design_rect(feature_id: String) -> Rect2:
	return _landmark_ui._landmark_design_rect(feature_id)


func get_landmark(feature_id: String) -> Button:
	return _landmark_ui.get_landmark(feature_id)


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
	button.add_theme_stylebox_override("normal", HubStyles.toggle_style("button"))
	button.add_theme_stylebox_override("hover", HubStyles.toggle_style("hover"))
	button.add_theme_stylebox_override("pressed", HubStyles.toggle_style("selected"))
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
	var resources := UiKit.as_dictionary(_profile.get("resources", {}))
	var law_tallies := UiKit.as_dictionary(resources.get("law_tallies", {}))
	var progression := UiKit.as_dictionary(_profile.get("progression", {}))
	var class_name_text := String({"ranger": "Ranger", "alchemist": "Alchemist", "mage": "Mage"}.get(String(_profile.get("initial_class", "Not Created")), String(_profile.get("initial_class", "Not Created"))))
	_profile_label.text = "Lv.%d · %s" % [int(_character_snapshot.get("level", 1)), class_name_text]
	_profile_label.tooltip_text = "XP %d / %d\nLaw Tokens: Inscribe %d · Rewrite %d · Refine %d" % [
		int(_character_snapshot.get("level_experience", 0)), int(_character_snapshot.get("next_level_experience", 0)),
		int(law_tallies.get("inscribe", 0)), int(law_tallies.get("rewrite", 0)), int(law_tallies.get("refine", 0)),
	]
	var points := int(_character_snapshot.get("points_available", 0))
	_character_button.text = "Talents C · %d" % points if points > 0 else "Talents C"
	_landmark_ui._update_progress_markers(progression)
	_progress_label.text = _objectives._early_progress_text(progression).replace("Build", "Build").replace("Auto", "Proxy")
	_objective_label.text = _objectives._displayed_objective_text()
	var story_text := String(UiKit.as_dictionary(_story_snapshot.get("current_objective", {})).get("text", ""))
	if not story_text.is_empty() and story_text != _objective_label.text:
		_objective_label.tooltip_text = "%s\n%s" % [_objective_label.text, story_text]
	else:
		_objective_label.tooltip_text = _objective_label.text
	_detail_objective_label.text = "Current Target: " + _objective_label.text
	var message := _objectives._localized_status(_status_message)
	_detail_status_label.text = message if not message.is_empty() else DETAIL_STATUS_EMPTY_TEXT
	_detail_status_label.tooltip_text = _detail_status_label.text
	var narrative: Array[String] = []
	for change: Dictionary in _story_snapshot.get("town_changes", []):
		narrative.append(String(change.get("text", change.get("description", change.get("title", "")))))
	for entry: Dictionary in _story_snapshot.get("available_conversations", []):
		narrative.append("%s · %s" % [String(entry.get("npc_name", "")), String(entry.get("title", ""))])
	_detail_story_label.text = "\n\n".join(narrative)
	_detail_story_label.visible = not narrative.is_empty()
	_detail_result_label.text = _objectives._settlement_text()
	_detail_help_label.text = HELP_COPY_TEXT
	_reflow_information_content.call_deferred()
	_info_toggle.tooltip_text = "%s\n%s" % [DETAIL_TITLE_TEXT, _detail_status_label.text]
	var unread := 0
	for entry in _story_snapshot.get("journal_entries", []):
		if not bool(entry.get("is_read", false)): unread += 1
	_story_button.text = "Journal J · %d" % unread if unread > 0 else "Journal J"
	# Reflow labels after live growth/unread counts update the top band.
	_header.notification(Container.NOTIFICATION_SORT_CHILDREN)
	(_header.get_child(0) as Container).notification(Container.NOTIFICATION_SORT_CHILDREN)
	for child in _header.get_child(0).get_children():
		if child is Container: child.notification(Container.NOTIFICATION_SORT_CHILDREN)
	_residents._refresh_town_conversations()
	_landmark_ui._update_navigation_state()


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
	_interaction._update_nearby_feature()


func get_prompt_rect() -> Rect2:
	return _interaction.get_prompt_rect()


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
		_info_toggle.text = "Close" if expanded else "News"
	_residents._update_resident_markers()
	_update_nearby_feature()
	_reflow_information_content.call_deferred()


func _on_information_toggle_pressed() -> void:
	set_information_details_expanded(not _details_expanded)


func _hero_cell_design_rect() -> Rect2:
	return _interaction._hero_cell_design_rect()


func navigation_state() -> Array:
	return _landmark_ui.navigation_state()


func get_navigation_state(feature_id: String) -> Dictionary:
	return _landmark_ui.get_navigation_state(feature_id)


func navigation_card_activated(feature_id: String) -> bool:
	return _landmark_ui.navigation_card_activated(feature_id)


func _nav_title(feature_id: String) -> String:
	return _objectives._nav_title(feature_id)


func _feature_entry(feature_id: String) -> Dictionary:
	return _town.entry_for(feature_id) if _town != null else {}


func _hit_feature(point: Vector2) -> String:
	return _interaction._hit_feature(point)


func _on_town_state_changed(snapshot: Dictionary) -> void:
	_view.consume(snapshot)
	_update_nearby_feature()


func _place_control(control: Control, rect: Rect2) -> void:
	control.position = rect.position
	control.size = rect.size
	control.custom_minimum_size = rect.size


func _on_hub_entry_pressed(feature_id: String) -> void:
	if feature_id == "contract":
		contract_requested.emit()
	else:
		feature_requested.emit(feature_id)


func _on_title_pressed() -> void:
	title_requested.emit()
