extends RefCounted
## Hero travel and interaction extracted from BaseHubScreen: nearby-stand and
## gateway activation, world clicks and the proximity badge geometry. Reaches
## the town runtime and presenter through the owner reference.

var _hub: BaseHubScreen


func _init(hub: BaseHubScreen) -> void:
	_hub = hub


func activate_nearby_feature() -> bool:
	if _hub.is_dialogue_open(): return false
	var feature_id := _hub._town.nearby_feature_id()
	if feature_id.is_empty():
		return false
	return _hub.navigation_card_activated(feature_id)


func activate_nearby_interaction() -> bool:
	var resident_id := _hub.nearby_resident_id()
	if not resident_id.is_empty(): return _hub.talk_to_resident(resident_id)
	if not _hub._town.nearby_feature_id().is_empty(): return activate_nearby_feature()
	return activate_nearby_gateway()


func nearby_gateway_id() -> String:
	if _hub._view == null or _hub.is_dialogue_open() or _hub._details_expanded: return ""
	return _hub._town.nearby_gateway_id()


## Exit gates open the same screens their facility counterpart does; they never
## start combat themselves. A far press, open dialogue or details does nothing.
func activate_nearby_gateway() -> bool:
	var gateway_id := nearby_gateway_id()
	if gateway_id.is_empty(): return false
	match String(_hub._town.entry_for_gateway(gateway_id).get("action", "")):
		"contract":
			_hub.contract_requested.emit()
			return true
	return false


func click_at_design_point(point: Vector2) -> bool:
	if _hub.is_dialogue_open() or _hub._details_expanded: return false
	## Distant stations become destinations. Only a nearby station opens a page.
	if _hub._view == null:
		return false
	var world_point := _hub._view.world_point_at_design(point, _hub._design_canvas.position, _hub._design_canvas.scale)
	if _hub._residents._click_resident(world_point): return true
	var feature_id := _hit_feature(world_point)
	if feature_id.is_empty():
		return false
	return _hub.navigation_card_activated(feature_id)


func click_at_world_point(world_point: Vector2) -> bool:
	if _hub.is_dialogue_open() or _hub._details_expanded: return false
	## Test and replay entry point: a click expressed in world coordinates goes
	## through the same camera conversion the real pointer uses.
	if _hub._view == null:
		return false
	if _hub._residents._click_resident(world_point): return true
	var feature_id := _hit_feature(world_point)
	if feature_id.is_empty():
		return false
	return _hub.navigation_card_activated(feature_id)


func _update_nearby_feature() -> void:
	## The badge follows the live avatar cell: it is measured from its own copy and
	## placed beside the feet, never as a fixed band across the bottom of the frame.
	if _hub._nearby_panel == null or _hub._view == null:
		return
	_hub._landmark_ui._update_navigation_state()
	if _hub._details_expanded or _hub.is_dialogue_open():
		_hub._view.set_interaction_focus(false)
		_hub._nearby_panel.hide()
		_hub._prompt_rect = Rect2()
		return
	var feature_id := _hub._town.nearby_feature_id()
	_hub._residents._update_resident_markers()
	var resident_id := _hub.nearby_resident_id()
	var gateway := _hub._town.entry_for_gateway(nearby_gateway_id()) if feature_id.is_empty() and resident_id.is_empty() else {}
	if feature_id.is_empty() and resident_id.is_empty() and gateway.is_empty():
		_hub._view.set_interaction_focus(false)
		_hub._nearby_panel.visible = false
		_hub._prompt_rect = Rect2()
		return
	## The badge names the stand, so the hint is what activate_nearby_interaction()
	## actually opens. A resident in range still wins, exactly like the E priority:
	## nearby_resident_id() only yields a resident who is closer than the stand.
	_hub._nearby_label.text = _facility_prompt_text(feature_id) if gateway.is_empty() else "[E / Space] Enter %s" % String(gateway.label)
	if not resident_id.is_empty():
		_hub._nearby_label.text = "[E] Talk to %s" % String(_hub._resident_conversations[resident_id].get("npc_name", ""))
	_hub._view.set_interaction_focus(true, resident_id if not resident_id.is_empty() else feature_id)
	_hub._nearby_label.tooltip_text = _hub._nearby_label.text
	_hub._prompt_rect = _resolve_prompt_rect()
	_hub._place_control(_hub._nearby_panel, _hub._prompt_rect)
	_hub._place_control(_hub._nearby_label, Rect2(Vector2.ZERO, _hub._prompt_rect.size))
	_hub._nearby_panel.visible = true


func _facility_prompt_text(feature_id: String) -> String:
	var entry := _hub._town.entry_for(feature_id) if _hub._view != null else {}
	var label := String(entry.get("label", ""))
	if label.is_empty():
		label = _hub._nav_title(feature_id)
	return "[E / Space] Enter %s" % label


func get_prompt_rect() -> Rect2:
	## Design-space rectangle of the proximity badge while it is on screen, an empty
	## rectangle while the avatar stands away from every stand.
	if _hub._nearby_panel == null or not _hub._nearby_panel.visible:
		return Rect2()
	return _hub._prompt_rect


func _hero_foot_design_point() -> Vector2:
	## Where the avatar's foot point lands on the 1280x720 canvas with the live
	## camera of this screen.
	if _hub._view == null:
		return BaseHubScreen.HERO_ENTRY_FOOT_ANCHOR
	var screen_point := _hub._view.design_point_for_world(_hub._town.hero_world_position(), _hub._design_canvas.position, _hub._design_canvas.scale)
	return _hub._design_canvas.get_global_transform_with_canvas().affine_inverse() * screen_point


func _hero_cell_design_rect() -> Rect2:
	## The avatar's own drawn cell in design space, read from the metadata the
	## renderer draws from. The fallback is the published 48x48 action cell with
	## its (24,44) anchor, so the badge keeps its distances while art is pending.
	var cell := Vector2(48.0, 48.0)
	var anchor := Vector2(24.0, 44.0)
	var foot := Vector2.ZERO
	if _hub._view != null:
		var metadata: Dictionary = _hub._view.hero_visual_metadata()
		var rect: Array = metadata.get("rect", [])
		var metadata_anchor: Array = metadata.get("anchor", [])
		if rect.size() == 4 and metadata_anchor.size() == 2:
			cell = Vector2(float(rect[2]), float(rect[3]))
			anchor = Vector2(float(metadata_anchor[0]), float(metadata_anchor[1]))
		foot = _hub._town.hero_world_position()
	if _hub._view == null:
		return Rect2((foot - anchor) * BaseHubScreen.WORLD_TO_DESIGN, cell * BaseHubScreen.WORLD_TO_DESIGN)
	var screen_to_canvas := _hub._design_canvas.get_global_transform_with_canvas().affine_inverse()
	var top_left := screen_to_canvas * _hub._view.design_point_for_world(foot - anchor, _hub._design_canvas.position, _hub._design_canvas.scale)
	var bottom_right := screen_to_canvas * _hub._view.design_point_for_world(foot - anchor + cell, _hub._design_canvas.position, _hub._design_canvas.scale)
	return Rect2(top_left, bottom_right - top_left)


func _prompt_width() -> float:
	## Just the width the badge's own copy needs, clamped to its published bounds.
	var font: Font = _hub._nearby_label.get_theme_font("font")
	var measured := BaseHubScreen.PROMPT_MIN_WIDTH
	if font != null:
		measured = font.get_string_size(_hub._nearby_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, BaseHubScreen.PROMPT_FONT_SIZE).x + 24.0
	return clampf(measured, BaseHubScreen.PROMPT_MIN_WIDTH, BaseHubScreen.PROMPT_MAX_WIDTH)


func _resolve_prompt_rect() -> Rect2:
	## Under the feet while the world leaves room and above the head when it does
	## not: never over the avatar's own cell and never off the canvas.
	var foot := _hero_foot_design_point()
	var cell := _hero_cell_design_rect()
	var bottom_limit := BaseHubScreen.DESIGN_SIZE.y - BaseHubScreen.PROMPT_CLEARANCE
	var width := _prompt_width()
	var top := cell.end.y + BaseHubScreen.PROMPT_GAP
	if top + BaseHubScreen.PROMPT_HEIGHT > bottom_limit:
		var above := cell.position.y - BaseHubScreen.PROMPT_GAP - BaseHubScreen.PROMPT_HEIGHT
		top = above if above >= BaseHubScreen.HEADER_RECT.end.y + BaseHubScreen.PROMPT_CLEARANCE else bottom_limit - BaseHubScreen.PROMPT_HEIGHT
	top = clampf(top, BaseHubScreen.HEADER_RECT.end.y + BaseHubScreen.PROMPT_CLEARANCE, bottom_limit - BaseHubScreen.PROMPT_HEIGHT)
	var left := clampf(foot.x - width * 0.5, BaseHubScreen.PROMPT_MARGIN, BaseHubScreen.DESIGN_SIZE.x - BaseHubScreen.PROMPT_MARGIN - width)
	## Snapped to the pixel grid like every other hub rectangle: the world is drawn
	## at whole-number scale, so a half-pixel badge would soften its own edge.
	return Rect2(floorf(left), floorf(top), ceilf(width), BaseHubScreen.PROMPT_HEIGHT)


func _hit_feature(point: Vector2) -> String:
	var id := _hub._view.hit_test(point)
	if not id.is_empty():
		return id
	var distance := INF
	for feature: Dictionary in _hub._town.feature_entries():
		var gap := point.distance_squared_to(feature.feet)
		if gap <= pow(float(feature.radius), 2.0) and gap < distance:
			distance = gap
			id = String(feature.id)
	return id
