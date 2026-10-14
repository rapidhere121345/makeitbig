class_name TownPresenter
extends Node2D

## Pure town presentation. Receives detached snapshots, animates art, follows
## the camera, and puts every actor in the shared WorldPresenter sort root.
const RangerAnimationScript := preload("res://src/presentation/ranger_animation.gd")
const HamletLifeAnimationScript := preload("res://src/presentation/hamlet_life_animation.gd")
const HERO_ID := "town/ranger"
const DESTINATION_EDGE_MARGIN := Vector2(22, 96)
const HERO_SPEED := 96.0

var world_viewport: SubViewport
var world_display: TextureRect
var world_presenter
var ranger_animation
var life_animation
var _state: Dictionary = {}
var _hero_sprite: Sprite2D
var _resident_views: Dictionary = {}
var _destination_marker: Polygon2D
var _destination_indicator: Polygon2D
var _destination_occluded := false
var _load_errors: Array[String] = []
var _attached := false
var _hero_frame: Dictionary = {}


func _ready() -> void:
	ensure_viewport()


func ensure_viewport() -> void:
	if world_viewport != null:
		return
	world_viewport = SubViewport.new()
	world_viewport.name = "TownViewport"
	world_viewport.size = Vector2i(640, 360)
	world_viewport.disable_3d = true
	world_viewport.transparent_bg = false
	world_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	world_viewport.gui_disable_input = true
	add_child(world_viewport)
	world_display = TextureRect.new()
	world_display.name = "TownDisplay"
	world_display.texture = world_viewport.get_texture()
	world_display.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	world_display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	world_display.size = Vector2(640, 360)
	add_child(world_display)


func load_character_assets() -> Dictionary:
	ranger_animation = RangerAnimationScript.new()
	life_animation = HamletLifeAnimationScript.new()
	life_animation.load_default_assets()
	_load_errors.clear()
	if not ranger_animation.has_real_art():
		_load_errors.append_array(ranger_animation.pending_reasons())
	if not life_animation.has_real_art():
		_load_errors.append_array(life_animation.pending_reasons())
	return {"ok": _load_errors.is_empty(), "error": "" if _load_errors.is_empty() else "town_character_assets_missing", "errors": _load_errors.duplicate()}


func attach(presenter: Variant, initial_state: Dictionary) -> Dictionary:
	if not _load_errors.is_empty() or ranger_animation == null or life_animation == null or not ranger_animation.has_real_art() or not life_animation.has_real_art():
		return {"ok": false, "error": "town_character_assets_missing", "errors": _load_errors.duplicate()}
	world_presenter = presenter
	_hero_sprite = _actor_sprite("Ranger")
	world_presenter.register_actor_view(HERO_ID, _hero_sprite)
	var clips := {}
	for resident: Dictionary in life_animation.resident_entries():
		clips[String(resident.placement)] = resident
	for resident: Dictionary in initial_state.get("resident_definitions", []):
		var id := String(resident.id)
		if not clips.has(id):
			return {"ok": false, "error": "town_resident_clip_missing:" + id}
		var sprite := _actor_sprite("Resident_" + id)
		world_presenter.register_actor_view("town/npc/" + id, sprite)
		_resident_views[id] = {"node": sprite, "clip": String(clips[id].clip), "phase": float(clips[id].phase)}
	_destination_marker = Polygon2D.new()
	_destination_marker.name = "TownDestinationMarker"
	_destination_marker.polygon = PackedVector2Array([Vector2(-6, -55), Vector2(6, -55), Vector2(0, -45)])
	_destination_marker.color = Color("e5b67c")
	world_presenter.foreground_layer.add_child(_destination_marker)
	_destination_indicator = Polygon2D.new()
	_destination_indicator.name = "TownDestinationIndicator"
	_destination_indicator.polygon = PackedVector2Array([Vector2(8, 0), Vector2(-5, 6), Vector2(-5, -6)])
	_destination_indicator.color = Color("e5b67c")
	_destination_indicator.z_index = 30
	world_viewport.add_child(_destination_indicator)
	_attached = true
	consume(initial_state)
	return {"ok": true, "error": ""}


func consume(state: Dictionary) -> void:
	_state = state.duplicate(true)
	if not _attached:
		return
	world_viewport.size = Vector2i(_state.get("view_size", Vector2(640, 360)))
	world_presenter.position = -camera_world_offset()
	world_presenter.sync_actor(HERO_ID, hero_world_position())
	_hero_frame = ranger_animation.resolve({"facing": _state.get("hero_facing", "south"), "moving": _state.get("hero_moving", false),
		"tick": int(_state.get("tick", 0)), "phase_ticks": int(_state.get("tick", 0))})
	_apply_frame(_hero_sprite, _hero_frame)
	for id: String in _resident_views:
		world_presenter.sync_actor("town/npc/" + id, (_state.get("residents", {}) as Dictionary).get(id, Vector2.ZERO))
	_update_life()
	_update_destination()


func _process(delta: float) -> void:
	if _attached:
		life_animation.tick(delta)
		_update_life()


func _update_life() -> void:
	for record: Dictionary in _resident_views.values():
		_apply_frame(record.node, life_animation.frame_at(record.clip, life_animation.life_time() + float(record.phase)))


func _apply_frame(sprite: Sprite2D, frame: Dictionary) -> void:
	if frame.is_empty() or bool(frame.get("fallback", false)) or not frame.get("texture", null) is Texture2D:
		_load_errors.append("town_character_frame_invalid:" + String(sprite.name))
		sprite.hide()
		return
	sprite.texture = frame.texture
	sprite.region_rect = Rect2(frame.get("rect", Rect2()))
	sprite.offset = -Vector2(frame.get("anchor", Vector2.ZERO)) + Vector2(frame.get("draw_offset", Vector2.ZERO))


func _actor_sprite(node_name: String) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.name = node_name
	sprite.centered = false
	sprite.region_enabled = true
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return sprite


func is_ready() -> bool:
	return _attached and _load_errors.is_empty()


func pending_reasons() -> Array[String]:
	return _load_errors.duplicate()


func hero_world_position() -> Vector2:
	return _state.get("hero_position", Vector2.ZERO)


func hero_facing() -> String:
	return String(_state.get("hero_facing", "south"))


func world_size() -> Vector2:
	return _state.get("world_size", Vector2(1536, 960))


func world_bounds() -> Rect2:
	return _state.get("world_bounds", Rect2())


func hero_screen_anchor() -> Vector2:
	return _state.get("hero_screen_anchor", Vector2(320, 222))


func camera_world_offset() -> Vector2:
	var view_size: Vector2 = _state.get("view_size", Vector2(640, 360))
	return (hero_world_position().floor() - hero_screen_anchor()).clamp(Vector2.ZERO, (world_size() - view_size).max(Vector2.ZERO))


func set_world_scale(scale_multiple: int, available_size := Vector2(1280, 720)) -> void:
	ensure_viewport()
	var view_size := Vector2(world_viewport.size)
	var factor := minf(available_size.x / view_size.x, available_size.y / view_size.y)
	world_display.size = view_size
	world_display.scale = Vector2.ONE * factor
	world_display.position = ((available_size - view_size * factor) * 0.5).floor()


func world_point_at_design(point: Vector2, _canvas_position: Vector2, _canvas_scale: Vector2) -> Vector2:
	return world_display.get_global_transform_with_canvas().affine_inverse() * point + camera_world_offset()


func design_point_for_world(point: Vector2, _canvas_position: Vector2, _canvas_scale: Vector2) -> Vector2:
	return world_display.get_global_transform_with_canvas() * (point - camera_world_offset())


func feature_visual_rect(feature_id: String) -> Rect2:
	var bounds := Rect2()
	if world_presenter == null:
		return bounds
	for sprite: Node in world_presenter.sort_root.get_children():
		if sprite is Sprite2D and String(sprite.get_meta("interaction", "")) == feature_id:
			var visual := sprite as Sprite2D
			var rect := Rect2(visual.position + visual.offset, visual.texture.get_size())
			bounds = rect if bounds == Rect2() else bounds.merge(rect)
	return bounds


func hit_test(point: Vector2) -> String:
	var selected := ""
	var front_y := -INF
	if world_presenter == null:
		return selected
	for node: Node in world_presenter.sort_root.get_children():
		if not node is Sprite2D or not node.has_meta("interaction"):
			continue
		var sprite := node as Sprite2D
		var id := String(sprite.get_meta("interaction"))
		if id.is_empty() or sprite.texture == null:
			continue
		var local := Vector2i((point - sprite.position - sprite.offset).floor())
		var pixels := sprite.texture.get_image()
		if Rect2i(Vector2i.ZERO, pixels.get_size()).has_point(local) and pixels.get_pixelv(local).a > 0.0 and sprite.position.y >= front_y:
			front_y = sprite.position.y
			selected = id
	return selected


func set_destination_occluded(value: bool) -> void:
	_destination_occluded = value
	_update_destination()


func _update_destination() -> void:
	if not _attached:
		return
	var guide: Dictionary = _state.get("destination", {})
	_destination_marker.visible = not guide.is_empty()
	_destination_indicator.visible = false
	if guide.is_empty():
		return
	var entry := {}
	for facility: Dictionary in _state.get("facilities", []):
		if String(facility.id) == String(guide.id):
			entry = facility
	if entry.is_empty():
		return
	_destination_marker.position = entry.feet
	var safe := Rect2(DESTINATION_EDGE_MARGIN, Vector2(world_viewport.size) - DESTINATION_EDGE_MARGIN * 2.0)
	_destination_indicator.visible = not bool(guide.get("arrived", false)) and (_destination_occluded or not safe.has_point(entry.feet - camera_world_offset()))
	_destination_indicator.position = (Vector2(guide.guide) - camera_world_offset()).clamp(safe.position, safe.end)
	_destination_indicator.rotation = Vector2(guide.direction).angle()


func destination_guide_report() -> Dictionary:
	var guide: Dictionary = (_state.get("destination", {}) as Dictionary).duplicate(true)
	guide["visible"] = _destination_indicator != null and _destination_indicator.visible
	if guide.has("guide"):
		guide["screen"] = Vector2(guide.guide) - camera_world_offset()
	return guide


func hero_visual_metadata() -> Dictionary:
	return {"rect": [0, 0, 48, 48], "anchor": [24, 44]}


func hero_animation_report() -> Dictionary:
	return _hero_frame.duplicate(true)


func ranger_animation_report() -> Dictionary:
	return ranger_animation.integration_report() if ranger_animation != null else {}


func life_report() -> Dictionary:
	var residents: Array[Dictionary] = []
	for id: String in _resident_views:
		var record: Dictionary = _resident_views[id]
		var sprite := record.node as Sprite2D
		residents.append({"id": id, "feet": sprite.position, "clip": record.clip,
			"frame": life_animation.frame_index(record.clip, life_animation.life_time() + float(record.phase)),
			"frames": life_animation.clip_frame_count(record.clip), "fps": life_animation.clip_fps(record.clip),
			"texture": life_animation.clip_texture_path(record.clip), "rect": sprite.region_rect, "offset": sprite.offset})
	return {"ready": is_ready(), "art": life_animation != null and life_animation.has_real_art(),
		"time": life_animation.life_time() if life_animation != null else 0.0, "residents": residents, "effects": [], "pending": pending_reasons()}


func render_audit() -> Dictionary:
	return {"ready": is_ready(), "view_size": Vector2(world_viewport.size), "ground_source_path": "res://content/rooms/town/layers/ground.png", "runtime_background_patches": 0,
		"unknown_underplate": "transparent", "supports_cutaway": false, "supports_fade": false,
		"shared_sort_root": world_presenter != null and world_presenter.sort_root.y_sort_enabled,
		"native_count": world_presenter.sort_root.get_child_count() - world_presenter.actor_ids().size() if world_presenter != null else 0}
