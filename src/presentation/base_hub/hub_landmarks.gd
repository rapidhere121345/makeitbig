extends RefCounted
## Landmark navigation bar extracted from BaseHubScreen: the facility plates
## that hover over the world, their focus wiring, occluder-window fade and
## destination selection. Presentation only; reaches the hub's town runtime,
## presenter and snapshots through the owner reference.

const ShellThemeScript = preload("res://src/presentation/shell_theme.gd")
const UiKit := preload("res://src/presentation/ui_kit.gd")

## Facility landmarks hover above the world plane, so an avatar walking under
## one would otherwise read as a dark silhouette behind a mostly opaque plate
## (GPU visual acceptance 2026-10-20). The same occluder-window semantics as
## the town pieces apply: a landmark covering the hero's cell eases open and
## closes again once the hero leaves it. Pure presentation; never gameplay.
const LANDMARK_WINDOW_ALPHA := 0.35
const LANDMARK_WINDOW_RATE := 8.0

var _hub: BaseHubScreen
var _landmark_styles: Dictionary = {}


func _init(hub: BaseHubScreen) -> void:
	_hub = hub


func _update_landmark_windows(delta: float) -> void:
	if _hub._view == null or _hub._design_canvas == null:
		return
	var hero_cell := _hub._hero_cell_design_rect()
	for feature_id: String in _hub._landmarks.keys():
		var landmark: Control = _hub._landmarks[feature_id]
		if not landmark.visible:
			landmark.modulate.a = 1.0
			continue
		var plate := Rect2(landmark.position, BaseHubScreen.LANDMARK_SIZE)
		var target := LANDMARK_WINDOW_ALPHA if plate.intersects(hero_cell) else 1.0
		var current := float(landmark.modulate.a)
		var step: float = LANDMARK_WINDOW_RATE * maxf(delta, 0.0)
		landmark.modulate.a = move_toward(current, target, step)


func _navigation_has_focus() -> bool:
	var viewport := _hub.get_viewport()
	if viewport == null:
		return false
	var owner := viewport.gui_get_focus_owner()
	for landmark: Control in _hub._landmarks.values():
		if owner != null and (owner == landmark or landmark.is_ancestor_of(owner)):
			return true
	return false


func _focus_visible_landmark(reverse: bool) -> bool:
	var visible_ids: Array[String] = []
	for feature_id: String in BaseHubScreen.LANDMARK_FEATURE_IDS:
		var landmark := get_landmark(feature_id)
		if landmark != null and landmark.is_visible_in_tree():
			visible_ids.append(feature_id)
	if visible_ids.is_empty():
		return false
	var current := -1
	var focus_owner := _hub.get_viewport().gui_get_focus_owner() if _hub.is_inside_tree() else null
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


func _build_landmarks() -> void:
	for feature_id: String in BaseHubScreen.LANDMARK_FEATURE_IDS:
		var landmark := BaseHubScreen.TownLandmark.new(feature_id)
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
		_hub._design_canvas.add_child(landmark)
		var copy := Control.new()
		copy.name = "Copy"
		copy.mouse_filter = Control.MOUSE_FILTER_IGNORE
		copy.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		copy.offset_left = 10.0
		copy.offset_top = 4.0
		copy.offset_right = -10.0
		copy.offset_bottom = -4.0
		landmark.add_child(copy)
		var title := _hub._copy_label("", "Title", 22)
		title.clip_text = true
		title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		title.position = Vector2.ZERO
		title.size = Vector2(BaseHubScreen.LANDMARK_SIZE.x - 20.0, 32.0)
		copy.add_child(title)
		var status := _hub._copy_label("", "Status", 18)
		status.clip_text = true
		status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		status.position = Vector2(0.0, 36.0)
		status.size = Vector2(BaseHubScreen.LANDMARK_SIZE.x - 20.0, 28.0)
		copy.add_child(status)
		_hub._landmarks[feature_id] = landmark
	_hub._town.select_destination(_hub._town.destination_id())


func wayfinding_report() -> Dictionary:
	var entry := _hub._town.entry_for(_hub._town.destination_id()) if _hub._view != null else {}
	if entry.is_empty(): return {}
	var delta: Vector2 = entry.feet - _hub._town.hero_world_position()
	var arrived := delta.length() <= float(entry.radius)
	var arrows := ["→", "↘", "↓", "↙", "←", "↖", "↑", "↗"]
	return {"id": _hub._town.destination_id(), "arrived": arrived, "distance": delta.length(),
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
	var grey := BaseHubScreen.COOL_GREY
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
	var entry := _hub._feature_entry(feature_id)
	if entry.is_empty():
		return Rect2()
	var feet: Vector2 = entry.get("feet", Vector2.ZERO)
	var building_top := feet.y + float(entry.get("landmark_offset_y", -112.0))
	var size := BaseHubScreen.LANDMARK_SIZE * BaseHubScreen.DESIGN_TO_WORLD
	var position := Vector2(feet.x - size.x * 0.5, building_top - BaseHubScreen.LANDMARK_GAP * BaseHubScreen.DESIGN_TO_WORLD - size.y)
	return Rect2(position, size)


func _landmark_design_rect(feature_id: String) -> Rect2:
	var world_rect := _landmark_world_rect(feature_id)
	if world_rect == Rect2() or _hub._view == null or _hub._design_canvas == null:
		return Rect2()
	var screen_point := _hub._view.design_point_for_world(world_rect.position, _hub._design_canvas.position, _hub._design_canvas.scale)
	var canvas_point := _hub._design_canvas.get_global_transform_with_canvas().affine_inverse() * screen_point
	return Rect2(canvas_point, BaseHubScreen.LANDMARK_SIZE)


func get_landmark(feature_id: String) -> Button:
	return _hub._landmarks.get(feature_id, null) as Button


func _update_landmarks() -> void:
	if _hub._view == null or _hub._design_canvas == null:
		return
	var camera := Rect2(_hub._view.camera_world_offset(), Vector2(_hub._view.world_viewport.size))
	var nearby_id := _hub._town.nearby_feature_id()
	_hub._nav_states = navigation_state()
	for state: Dictionary in _hub._nav_states:
		var feature_id := String(state.id)
		var landmark := get_landmark(feature_id)
		if landmark == null:
			continue
		var world_rect := _landmark_world_rect(feature_id)
		var design_rect := _landmark_design_rect(feature_id)
		landmark.visible = camera.encloses(world_rect) and BaseHubScreen.LANDMARK_SAFE_RECT.encloses(design_rect) and not _hub.is_dialogue_open() and not _hub._details_expanded
		_hub._place_control(landmark, Rect2(design_rect.position.floor(), BaseHubScreen.LANDMARK_SIZE))
		var title := landmark.get_node("Copy/Title") as Label
		var status := landmark.get_node("Copy/Status") as Label
		var nearby := feature_id == nearby_id
		var selected := feature_id == _hub._town.destination_id()
		if selected:
			## The label can be hidden while its world feet stay technically on
			## screen (the top band, another stand's art): the local road guide
			## must keep pointing until the stand's own interaction radius.
			_hub._view.set_destination_occluded(not (camera.encloses(world_rect) and BaseHubScreen.LANDMARK_SAFE_RECT.encloses(design_rect)))
		title.text = String(state.get("title", feature_id))
		status.text = String(state.get("status", ""))
		title.add_theme_color_override("font_color", ShellThemeScript.BONE if nearby or selected else BaseHubScreen.COOL_GREY)
		status.add_theme_color_override("font_color", ShellThemeScript.AMBER if nearby or selected else BaseHubScreen.COOL_GREY)
		landmark.tooltip_text = "%s\n%s\n%s\nClick for directions; approach, then click or press E to enter" % [
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
	for feature_id: String in BaseHubScreen.LANDMARK_FEATURE_IDS:
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


func navigation_state() -> Array:
	## One card state per facility, in the published order. The hub derives every
	## field from the save snapshot it was handed; the bar only draws the copy.
	var progression := UiKit.as_dictionary(_hub._profile.get("progression", {}))
	var earned_rewards := UiKit.as_array(_hub._campaign_snapshot.get("earned_reward_tags", []))
	var states: Array = []
	for feature_id: String in BaseHubScreen.LANDMARK_FEATURE_IDS:
		states.append({
			"id": feature_id,
			"title": _hub._nav_title(feature_id),
			"locked": _hub._objectives._nav_locked(feature_id, progression, earned_rewards),
			"reason": String(_hub._unlock_reasons.get(feature_id, "")),
			"status": _hub._objectives._nav_status_text(feature_id),
			"detail": _hub._objectives._nav_detail(feature_id, progression, earned_rewards),
			"current": feature_id == _hub._town.nearby_feature_id() if _hub._view != null else false,
		})
	return states


func get_navigation_state(feature_id: String) -> Dictionary:
	for state: Dictionary in navigation_state():
		if String(state.get("id", "")) == feature_id:
			return state
	return {}


func navigation_card_activated(feature_id: String) -> bool:
	## A far click is a request for directions, not a remote facility opening.
	if _hub.is_dialogue_open() or _hub._details_expanded or not BaseHubScreen.LANDMARK_FEATURE_IDS.has(feature_id):
		return false
	var entry := _hub._town.entry_for(feature_id)
	var within_reach := not entry.is_empty() and _hub._town.hero_world_position().distance_to(entry.feet) <= float(entry.radius)
	if not within_reach:
		## Only an explicit directions request moves the local road guide. Walking
		## up to a stand and entering it is not a destination choice, so a mistaken
		## visit (the baseline run entered loadout this way) cannot quietly stick.
		_hub._town.select_destination(feature_id)
	_update_landmarks()
	if _navigation_has_focus(): _hub.get_viewport().gui_get_focus_owner().release_focus()
	if within_reach:
		_hub._on_hub_entry_pressed(feature_id)
	return true


func _update_navigation_state() -> void:
	_update_landmarks()


func _update_progress_markers(progression: Dictionary) -> void:
	## The world markers stay the published placement labels plus one short player
	## note; the same derivation feeds the navigation cards, so a marker and its
	## card can never disagree about what is open.
	if _hub._view == null:
		return
	var earned_rewards := UiKit.as_array(_hub._campaign_snapshot.get("earned_reward_tags", []))
	_hub._marker_notes["contract"] = _hub._objectives._nav_detail("contract", progression, earned_rewards)
	_hub._marker_notes["loadout"] = _hub._objectives._nav_detail("loadout", progression, earned_rewards)
	_hub._marker_notes["forge"] = _hub._objectives._nav_detail("forge", progression, earned_rewards)
	_hub._marker_notes["training"] = _hub._objectives._nav_detail("training", progression, earned_rewards)
	_hub._marker_notes["proxy"] = _hub._objectives._nav_detail("proxy", progression, earned_rewards)
	_hub._marker_notes["immortality"] = ""
	_update_navigation_state()
