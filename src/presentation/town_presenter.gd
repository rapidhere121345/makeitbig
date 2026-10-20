class_name TownPresenter
extends Node2D

## Pure town presentation. Receives detached snapshots, animates art, follows
## the camera, and puts every actor in the shared WorldPresenter sort root.
const RangerAnimationScript := preload("res://src/presentation/ranger_animation.gd")
const HamletLifeAnimationScript := preload("res://src/presentation/hamlet_life_animation.gd")
const OcclusionControllerScript := preload("res://src/presentation/occlusion/occlusion_controller.gd")
const HERO_ID := "town/ranger"
const HERO_VISUAL_ID := "ranger.town.idle"
const DESTINATION_EDGE_MARGIN := Vector2(22, 96)
const HERO_SPEED := 96.0
const INTERACTION_ANCHOR_COLOR := Color("e5b67c")

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
var _interaction_anchor: Node2D
var _interaction_focus_active := false
var _interaction_focus_id := ""
var _destination_occluded := false
var _load_errors: Array[String] = []
var _attached := false
var _hero_frame: Dictionary = {}
var _presentation_runtime: Variant = null
var _occlusion_controller = OcclusionControllerScript.new()
var _occlusion_report: Dictionary = {"available": false, "reason": "presentation_unbound", "alphas": {}}


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


func attach(presenter: Variant, initial_state: Dictionary, presentation_runtime: Variant = null) -> Dictionary:
	_occluder_piece_cache.clear()
	if not _load_errors.is_empty() or ranger_animation == null or life_animation == null or not ranger_animation.has_real_art() or not life_animation.has_real_art():
		return {"ok": false, "error": "town_character_assets_missing", "errors": _load_errors.duplicate()}
	world_presenter = presenter
	_presentation_runtime = presentation_runtime
	_occlusion_controller = OcclusionControllerScript.new()
	_occlusion_report = {"available": false, "reason": "presentation_unbound", "alphas": {}}
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
	_build_interaction_anchor()
	_destination_indicator = Polygon2D.new()
	_destination_indicator.name = "TownDestinationIndicator"
	_destination_indicator.polygon = PackedVector2Array([Vector2(8, 0), Vector2(-5, 6), Vector2(-5, -6)])
	_destination_indicator.color = Color("e5b67c")
	_destination_indicator.z_index = 30
	world_viewport.add_child(_destination_indicator)
	_attached = true
	consume(initial_state)
	var presentation_errors: Array[String] = []
	if presentation_runtime != null:
		presentation_errors = _bind_actor_presentations(presentation_runtime)
		if not presentation_errors.is_empty():
			return {"ok": false, "error": presentation_errors[0], "errors": presentation_errors}
	return {"ok": true, "error": ""}


## Pushes every registered actor's real drawn cell into the mounted
## SceneRuntime presentation projector. The box is the animation cell the
## sprite really samples, bottom-center anchored on the authoritative sim
## feet (rect.size minus the cell anchor) — never collision geometry, and
## any rejection fails the attach so a mounted town can never pass READY
## with a half-bound presentation domain.
func _bind_actor_presentations(runtime: Variant) -> Array[String]:
	if runtime == null or not runtime.has_method("bind_actor_presentation"):
		return ["town_presentation_runtime_invalid"]
	var metadata := hero_visual_metadata()
	var hero_rect: Array = metadata.get("rect", [])
	var hero_anchor: Array = metadata.get("anchor", [])
	if hero_rect.size() != 4 or hero_anchor.size() != 2:
		return ["town_hero_visual_metadata_invalid"]
	var hero_bound: Dictionary = runtime.bind_actor_presentation(
		HERO_ID,
		HERO_VISUAL_ID,
		1,
		Rect2(-float(hero_anchor[0]), -float(hero_anchor[1]), float(hero_rect[2]), float(hero_rect[3]))
	)
	if not bool(hero_bound.get("ok", false)):
		return ["town_hero_presentation_binding_failed:%s" % String(hero_bound.get("error", "unknown"))]
	for id: String in _resident_views.keys():
		var record: Dictionary = _resident_views[id]
		var clip := String(record["clip"])
		var frame: Dictionary = life_animation.frame_at(clip, 0.0)
		var cell: Rect2 = frame.get("rect", Rect2())
		var anchor: Vector2 = frame.get("anchor", Vector2.ZERO)
		if cell.size.x <= 0.0 or cell.size.y <= 0.0:
			return ["town_resident_visual_metadata_invalid:" + id]
		var resident_bound: Dictionary = runtime.bind_actor_presentation(
			"town/npc/" + id,
			clip,
			1,
			Rect2(-anchor.x, -anchor.y, cell.size.x, cell.size.y)
		)
		if not bool(resident_bound.get("ok", false)):
			return ["town_resident_presentation_binding_failed:%s:%s" % [id, String(resident_bound.get("error", "unknown"))]]
	return []


## Stable identities of every actor this presenter binds, for mounted
## production gates to cross-check the projector against this file's real
## metadata sources.
func actor_presentation_report() -> Array[Dictionary]:
	var report: Array[Dictionary] = []
	report.append({"stable_id": HERO_ID, "visual_id": HERO_VISUAL_ID})
	for id: String in _resident_views.keys():
		report.append({
			"stable_id": "town/npc/" + id,
			"visual_id": String((_resident_views[id] as Dictionary)["clip"]),
		})
	return report


func consume(state: Dictionary) -> void:
	_state = state.duplicate(true)
	if not _attached:
		return
	world_viewport.size = Vector2i(_state.get("view_size", Vector2(640, 360)))
	world_presenter.position = -camera_world_offset()
	world_presenter.sync_actor(HERO_ID, hero_world_position())
	_update_interaction_anchor()
	_hero_frame = ranger_animation.resolve({"facing": _state.get("hero_facing", "south"), "moving": _state.get("hero_moving", false),
		"tick": int(_state.get("tick", 0)), "phase_ticks": int(_state.get("tick", 0))})
	_apply_frame(_hero_sprite, _hero_frame)
	for id: String in _resident_views:
		world_presenter.sync_actor("town/npc/" + id, (_state.get("residents", {}) as Dictionary).get(id, Vector2.ZERO))
	_update_life()
	_update_destination()
	_sync_occlusion(0.0)


func _process(delta: float) -> void:
	if _attached:
		life_animation.tick(delta)
		_update_life()
		_update_interaction_anchor()
		_sync_occlusion(delta)


## Applies only the detached presentation plan to the town's drawn actor
## sprites. The plan is never fed back into TownRuntime or SceneRuntime; a
## missing plan resets display alpha to full and records the failure.
func _sync_occlusion(display_delta: float) -> void:
	if _presentation_runtime == null:
		_reset_occlusion("presentation_runtime_unbound")
		return
	var port: Variant = _presentation_runtime.get("presentation_port") if _presentation_runtime is Object else null
	if port == null or not port.has_method("latest_occlusion_plan"):
		_reset_occlusion("presentation_port_unavailable")
		return
	var plan_result: Dictionary = port.latest_occlusion_plan()
	if not bool(plan_result.get("ok", false)):
		_reset_occlusion("plan_unavailable", (plan_result.get("errors", []) as Array).slice(0, 3))
		return
	var plan: Variant = plan_result.get("value", null)
	var synced: Dictionary = _occlusion_controller.sync_plan(plan)
	if not bool(synced.get("ok", false)):
		_reset_occlusion("plan_sync_failed")
		return
	var entries: Array = plan.entries()
	for entry: Dictionary in entries:
		var stable_id := String(entry.get("stable_id", ""))
		var report: Dictionary = plan.occlusion_report(stable_id)
		if bool(report.get("ok", false)):
			_occlusion_controller.set_cover(stable_id, float(report.get("cover_fraction", 0.0)))
	## Occluder windows replace subject dimming: a dimmed actor under an
	## opaque front piece was invisible anyway (GPU visual acceptance
	## 2026-10-20), so the piece itself opens a tiered window instead and the
	## actor sprite stays fully opaque.
	var occluder_covers: Dictionary = {}
	var actor_ids: Dictionary = {}
	for actor_id: String in actor_presentation_ids():
		actor_ids[actor_id] = true
		for occluder: Dictionary in plan.occluders_of(actor_id):
			var occluder_id := String(occluder.get("stable_id", ""))
			if occluder_id.is_empty():
				continue
			var cover := float(occluder.get("cover_fraction", 0.0))
			occluder_covers[occluder_id] = minf(float(occluder_covers.get(occluder_id, INF)), cover)
	## Every plan entry that is not an actor is a native front piece: covered
	## pieces get their tiered window, uncovered pieces ease back to opaque.
	## Resolving the piece node here also seeds the node cache.
	for entry: Dictionary in entries:
		var stable_id := String(entry.get("stable_id", ""))
		if stable_id.is_empty() or actor_ids.has(stable_id):
			continue
		_occlusion_controller.set_occluder_cover(stable_id, float(occluder_covers.get(stable_id, 0.0)))
		_occluder_piece(stable_id)
	_occlusion_controller.update(maxf(display_delta, 0.0))
	var alphas: Dictionary = {}
	var window_alphas: Dictionary = {}
	var occluded_ids: Array[String] = []
	for actor_id: String in actor_presentation_ids():
		var alpha := float(_occlusion_controller.alpha(actor_id))
		alphas[actor_id] = alpha
		if alpha < 0.999:
			occluded_ids.append(actor_id)
		_apply_actor_alpha(actor_id, 1.0)
	for occluder_id: String in _occlusion_controller.occluder_ids():
		var piece: CanvasItem = _occluder_piece(occluder_id)
		var window := _occlusion_controller.occluder_alpha(occluder_id)
		var piece_alpha := clampf(window, 0.0, 1.0) if is_finite(window) else 1.0
		window_alphas[occluder_id] = piece_alpha
		if piece != null:
			piece.modulate.a = piece_alpha
	_occlusion_report = {"available": true, "reason": "", "plan_size": entries.size(),
		"occluded_ids": occluded_ids, "alphas": alphas, "occluder_alphas": window_alphas}


func _reset_occlusion(reason: String, errors: Array = []) -> void:
	for actor_id: String in actor_presentation_ids():
		_apply_actor_alpha(actor_id, 1.0)
	_occlusion_controller.clear_occluders()
	for occluder_id: String in _occluder_piece_cache.keys():
		var piece: CanvasItem = _occluder_piece(occluder_id)
		if piece != null:
			piece.modulate.a = 1.0
	_occlusion_report = {"available": false, "reason": reason, "errors": errors.duplicate(), "alphas": {}}


func _apply_actor_alpha(actor_id: String, alpha: float) -> void:
	var sprite: Sprite2D = _hero_sprite if actor_id == HERO_ID else null
	if sprite == null and actor_id.begins_with("town/npc/"):
		var resident_id := actor_id.trim_prefix("town/npc/")
		var record: Variant = _resident_views.get(resident_id, null)
		sprite = record.get("node", null) if record is Dictionary else null
	if sprite != null and is_instance_valid(sprite):
		sprite.modulate.a = clampf(alpha, 0.0, 1.0)


func actor_presentation_ids() -> Array[String]:
	var ids: Array[String] = [HERO_ID]
	for id: String in _resident_views.keys():
		ids.append("town/npc/" + id)
	ids.sort()
	return ids


## Mounted native front pieces by occlusion binding id. The cache is keyed by
## the ids seen in occlusion plans; it is cleared on attach so a room restart
## can never reuse a freed node.
var _occluder_piece_cache: Dictionary = {}


func _occluder_piece(occluder_id: String) -> CanvasItem:
	if _occluder_piece_cache.has(occluder_id):
		var cached: Variant = _occluder_piece_cache[occluder_id]
		if cached is CanvasItem and is_instance_valid(cached as CanvasItem):
			return cached
		_occluder_piece_cache.erase(occluder_id)
		return null
	## The mounted native pieces are reparented out of the room scene into the
	## world presenter's shared layers at mount, so the search root is the
	## SceneRuntime node itself: its subtree owns both the mounted scene and
	## the presenter layers.
	if _presentation_runtime == null or not _presentation_runtime is Node:
		return null
	var piece: CanvasItem = _find_binding_piece(_presentation_runtime as Node, occluder_id)
	if piece != null:
		_occluder_piece_cache[occluder_id] = piece
	return piece


static func _find_binding_piece(root: Node, binding_id: String) -> CanvasItem:
	if root.get_meta("binding_id", "") == binding_id and root is CanvasItem:
		return root as CanvasItem
	for child: Node in root.get_children():
		var found: CanvasItem = _find_binding_piece(child, binding_id)
		if found != null:
			return found
	return null


func occlusion_report() -> Dictionary:
	return _occlusion_report.duplicate(true)


func actor_alpha(stable_id: String) -> float:
	if stable_id == HERO_ID and _hero_sprite != null and is_instance_valid(_hero_sprite):
		return _hero_sprite.modulate.a
	if stable_id.begins_with("town/npc/"):
		var record: Variant = _resident_views.get(stable_id.trim_prefix("town/npc/"), null)
		var sprite: Variant = record.get("node", null) if record is Dictionary else null
		if sprite is CanvasItem and is_instance_valid(sprite):
			return (sprite as CanvasItem).modulate.a
	return 1.0


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


## A nearby interaction needs a readable player anchor even when a native roof or
## fence correctly draws in front of the actor. This is a player feedback mark in
## the presentation foreground, not a copy of the actor and not a re-sort of any
## authored world object. It is only enabled by the hub while an interaction is
## actually available.
func _build_interaction_anchor() -> void:
	_interaction_anchor = Node2D.new()
	_interaction_anchor.name = "TownInteractionAnchor"
	_interaction_anchor.z_index = 2
	_interaction_anchor.visible = false
	world_presenter.foreground_layer.add_child(_interaction_anchor)
	var left := Line2D.new()
	left.name = "LeftWing"
	left.points = PackedVector2Array([Vector2(-11, 2), Vector2(-7, 6), Vector2(-2, 3)])
	left.width = 1.0
	left.default_color = INTERACTION_ANCHOR_COLOR
	left.antialiased = false
	_interaction_anchor.add_child(left)
	var right := Line2D.new()
	right.name = "RightWing"
	right.points = PackedVector2Array([Vector2(2, 3), Vector2(7, 6), Vector2(11, 2)])
	right.width = 1.0
	right.default_color = INTERACTION_ANCHOR_COLOR
	right.antialiased = false
	_interaction_anchor.add_child(right)
	var core := Polygon2D.new()
	core.name = "Core"
	core.polygon = PackedVector2Array([Vector2(-2, 1), Vector2(0, -1), Vector2(2, 1), Vector2(0, 3)])
	core.color = INTERACTION_ANCHOR_COLOR
	_interaction_anchor.add_child(core)


## Called by the hub presentation when the player is inside a readable
## interaction radius. The focus id is diagnostic only; it never enters the
## simulation or changes which facility the runtime accepts.
func set_interaction_focus(active: bool, focus_id: String = "") -> void:
	_interaction_focus_active = active
	_interaction_focus_id = focus_id if active else ""
	_update_interaction_anchor()


func _update_interaction_anchor() -> void:
	if _interaction_anchor == null or not is_instance_valid(_interaction_anchor):
		return
	_interaction_anchor.position = hero_world_position()
	_interaction_anchor.visible = _attached and _interaction_focus_active


func interaction_anchor_report() -> Dictionary:
	return {
		"active": _interaction_focus_active,
		"visible": _interaction_anchor != null and is_instance_valid(_interaction_anchor) and _interaction_anchor.visible,
		"focus_id": _interaction_focus_id,
		"world_position": hero_world_position(),
		"layer": "foreground_interaction",
	}


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
		"unknown_underplate": "transparent", "supports_cutaway": true, "supports_fade": true,
		"occlusion_available": bool(_occlusion_report.get("available", false)),
		"shared_sort_root": world_presenter != null and world_presenter.sort_root.y_sort_enabled,
		"native_count": world_presenter.sort_root.get_child_count() - world_presenter.actor_ids().size() if world_presenter != null else 0}
