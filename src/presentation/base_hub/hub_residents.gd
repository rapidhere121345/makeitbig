extends RefCounted
## Resident conversations extracted from BaseHubScreen: talk range and
## priority, the dialogue overlay, the talk markers and click targeting. The
## dialogue and conversation tables stay on the owner (tests read them).

const ShellThemeScript = preload("res://src/presentation/shell_theme.gd")
const TownDialogueScript = preload("res://src/presentation/town_dialogue.gd")
const HubStyles = preload("res://src/presentation/base_hub/hub_styles.gd")

var _hub  # untyped to avoid a preload cycle


func _init(hub) -> void:
	_hub = hub


func nearby_resident_id() -> String:
	if _hub._view == null or _hub.is_dialogue_open(): return ""
	var feet = _hub._town.hero_world_position()
	var facility_gap := INF
	var best_distance := INF
	var closest := ""
	var feature = _hub._town.entry_for(_hub._town.nearby_feature_id())
	if not feature.is_empty():
		facility_gap = feet.distance_to(feature.get("feet", Vector2(INF, INF)))
	for id: String in _hub._resident_conversations:
		if not _hub._town.resident_positions().has(id): continue
		var candidate = feet.distance_to(_hub._town.resident_positions()[id])
		## Strict nearest inside TALK_RADIUS: later/farther residents never
		## overwrite an earlier nearer one, whatever the iteration order.
		if candidate > _hub.TALK_RADIUS or candidate >= best_distance: continue
		best_distance = candidate
		closest = id
	if closest.is_empty() or best_distance > facility_gap + _hub.RESIDENT_PRIORITY_SLACK:
		return ""
	return closest


func talk_to_resident(resident_id: String) -> bool:
	if _hub._dialogue == null or _hub.is_dialogue_open() or not _hub._resident_conversations.has(resident_id): return false
	if not _hub._town.resident_positions().has(resident_id) or _hub._town.hero_world_position().distance_to(_hub._town.resident_positions()[resident_id]) > _hub.TALK_RADIUS: return false
	var opened = _hub._dialogue.open_conversation(_hub._resident_conversations[resident_id])
	if opened:
		_hub._view.protect_dialogue_resident(resident_id)
		_hub._nearby_panel.hide()
		_hub._prompt_rect = Rect2()
		_update_resident_markers()
		_hub._landmark_ui._update_landmarks()
	return opened


func _click_resident(point: Vector2) -> bool:
	for id: String in _hub._resident_conversations:
		if not _hub._town.resident_positions().has(id): continue
		var feet: Vector2 = _hub._town.resident_positions()[id]
		if Rect2(feet - Vector2(14, 34), Vector2(28, 40)).has_point(point):
			return talk_to_resident(id)
	return false


func _build_town_dialogue() -> void:
	_hub._dialogue = TownDialogueScript.new()
	_hub._design_canvas.add_child(_hub._dialogue)
	_hub._dialogue.finished.connect(func(entry_id: String): _hub.conversation_read.emit(entry_id))
	_hub._dialogue.dismissed.connect(func():
		_hub._view.protect_dialogue_resident("")
		_hub._update_nearby_feature()
	)


func _refresh_town_conversations() -> void:
	if _hub._view == null or _hub._dialogue == null: return
	_hub._resident_conversations.clear()
	for entry: Dictionary in _hub._story_snapshot.get("available_conversations", []):
		var id := String(entry.get("npc", ""))
		if not _hub._resident_conversations.has(id) or int(entry.stage) >= int(_hub._resident_conversations[id].stage):
			_hub._resident_conversations[id] = entry.duplicate(true)
	for id: String in _hub._resident_conversations:
		if _hub._resident_markers.has(id): continue
		var marker := Label.new()
		marker.name = "ResidentTalkMarker_" + id
		marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
		marker.text = "…"
		marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		marker.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		marker.add_theme_font_size_override("font_size", 18)
		marker.add_theme_color_override("font_color", ShellThemeScript.BONE)
		var bubble := HubStyles.hotspot_style(Color("111820ee"), ShellThemeScript.COPPER_DULL, 1)
		bubble.content_margin_left = 4
		bubble.content_margin_right = 4
		bubble.content_margin_top = 0
		bubble.content_margin_bottom = 0
		marker.add_theme_stylebox_override("normal", bubble)
		_hub._design_canvas.add_child(marker)
		_hub._design_canvas.move_child(marker, _hub._dialogue.get_index())
		_hub._resident_markers[id] = marker
	_hub._update_nearby_feature()


func _update_resident_markers() -> void:
	for id: String in _hub._resident_markers:
		var marker: Label = _hub._resident_markers[id]
		marker.visible = false
		if _hub._details_expanded or _hub.is_dialogue_open() or not _hub._town.resident_positions().has(id) or not _hub._resident_conversations.has(id): continue
		var global_point = _hub._view.design_point_for_world(_hub._town.resident_positions()[id] - Vector2(0, 38), _hub._design_canvas.position, _hub._design_canvas.scale)
		var point = _hub._design_canvas.get_global_transform_with_canvas().affine_inverse() * global_point
		marker.position = (point - Vector2(17, 28)).floor()
		marker.size = Vector2(34, 28)
		marker.visible = marker.position.y > _hub.HEADER_RECT.end.y and marker.position.y + 28 < _hub.DESIGN_SIZE.y and marker.position.x > 12 and marker.position.x + 34 < _hub.DESIGN_SIZE.x - 12
		marker.modulate.a = 0.55 if bool(_hub._resident_conversations[id].get("is_read", false)) else 1.0
