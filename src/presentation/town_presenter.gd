class_name TownPresenter
extends Node2D

## Pure town presentation. Receives detached snapshots, animates art, follows
## the camera, and puts every actor in the shared WorldPresenter sort root.
const RangerAnimationScript := preload("res://src/presentation/ranger_animation.gd")
const HamletLifeAnimationScript := preload("res://src/presentation/hamlet_life_animation.gd")
const OcclusionControllerScript := preload("res://src/presentation/occlusion/occlusion_controller.gd")
const AuthoredRevealScript := preload("res://src/presentation/occlusion/authored_reveal_controller.gd")
const SilhouetteRevealScript := preload("res://src/presentation/occlusion/silhouette_reveal_controller.gd")
const PrimitiveFadeScript := preload("res://src/presentation/occlusion/primitive_fade_controller.gd")
const PairedRevealScript := preload("res://src/presentation/occlusion/paired_reveal_controller.gd")
const DressingScript := preload("res://src/presentation/world_dressing.gd")
const GroundingScript := preload("res://src/presentation/town_grounding.gd")
const Readability = preload("res://src/presentation/actor_readability.gd")
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
var _dressing = DressingScript.new()
var _dressing_layer: Node2D
var _grounding_layer: Node2D
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
var _authored_reveal = AuthoredRevealScript.new()
var _silhouette_reveal = SilhouetteRevealScript.new()
var _primitive_fade = PrimitiveFadeScript.new()
var _paired_reveal = PairedRevealScript.new()
var _protected_resident := ""
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
	if not _dressing.load_assets():
		_load_errors.append(_dressing.pending_reason)
	if not ranger_animation.has_real_art():
		_load_errors.append_array(ranger_animation.pending_reasons())
	if not life_animation.has_real_art():
		_load_errors.append_array(life_animation.pending_reasons())
	return {"ok": _load_errors.is_empty(), "error": "" if _load_errors.is_empty() else "town_character_assets_missing", "errors": _load_errors.duplicate()}


func attach(presenter: Variant, initial_state: Dictionary, presentation_runtime: Variant = null) -> Dictionary:
	_authored_reveal.clear()
	_silhouette_reveal.clear()
	_primitive_fade.clear()
	_paired_reveal.clear()
	_protected_resident = ""
	## Pieces surviving a re-attach must not keep a stale reveal material from
	## the previous binding; retired pieces are freed with their scene.
	for occluder_id: String in _occluder_piece_cache.keys():
		var piece: CanvasItem = _occluder_piece(occluder_id)
		if piece != null and piece.material != null and piece.material == _occluder_materials.get(occluder_id, null):
			piece.material = null
	_occluder_piece_cache.clear()
	_occluder_materials.clear()
	if not _load_errors.is_empty() or ranger_animation == null or life_animation == null or not ranger_animation.has_real_art() or not life_animation.has_real_art():
		return {"ok": false, "error": "town_character_assets_missing", "errors": _load_errors.duplicate()}
	if is_instance_valid(_dressing_layer):
		_dressing_layer.free()
	if is_instance_valid(_grounding_layer):
		_grounding_layer.free()
	world_presenter = presenter
	_grounding_layer = GroundingScript.new()
	_grounding_layer.name = "TownGrounding"
	_grounding_layer.configure(world_presenter.sort_root)
	world_presenter.ground_effects_layer.add_child(_grounding_layer)
	_dressing_layer = _dressing.create_town_layer()
	world_presenter.ground_effects_layer.add_child(_dressing_layer)
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
	world_presenter.sync_actor(HERO_ID, hero_world_position(), Vector2.ZERO, 1, HERO_ID)
	_update_interaction_anchor()
	_hero_frame = ranger_animation.resolve({"facing": _state.get("hero_facing", "south"), "moving": _state.get("hero_moving", false),
		"tick": int(_state.get("tick", 0)), "phase_ticks": int(_state.get("tick", 0))})
	_apply_frame(_hero_sprite, _hero_frame)
	for id: String in _resident_views:
		world_presenter.sync_actor("town/npc/" + id, (_state.get("residents", {}) as Dictionary).get(id, Vector2.ZERO), Vector2.ZERO, 1, "town/npc/" + id)
	var shadow_actors: Array[Dictionary] = [{"id": HERO_ID, "feet": hero_world_position()}]
	_hero_sprite.self_modulate = _grounding_layer.illumination_at(hero_world_position())
	for id: String in _resident_views:
		var feet: Vector2 = (_state.get("residents", {}) as Dictionary).get(id, Vector2.ZERO)
		shadow_actors.append({"id": "town/npc/" + id, "feet": feet})
		(_resident_views[id].node as Sprite2D).self_modulate = _grounding_layer.illumination_at(feet)
	_grounding_layer.sync_actors(shadow_actors)
	_update_life()
	_update_destination()
	_sync_occlusion(0.0)


func grounding_report() -> Dictionary:
	return _grounding_layer.report() if is_instance_valid(_grounding_layer) else {}


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
	# Subject alpha is only consumed for live actors. Scenery is an occluder,
	# driven separately below by its cover over actors; computing scenery's
	# own cover scanned every scenery pair on each new simulation frame.
	for stable_id: String in actor_presentation_ids():
		var report: Dictionary = plan.occlusion_report(stable_id)
		if bool(report.get("ok", false)):
			_occlusion_controller.set_cover(stable_id, float(report.get("cover_fraction", 0.0)))
	## Reveal policy: a native front piece stays globally opaque unless it
	## explicitly opts into a policy. Unconfigured legacy pieces keep the
	## exact-silhouette clear over the CURRENT opaque silhouette of each
	## covered actor that holds a readability slot (the hero and the resident
	## the hub is protecting for conversation). Pieces with an explicit
	## reveal_policy meta are dispatched instead: "authored_variant" swaps in
	## mask art, "primitive_fade" eases the opted-in upper part's own
	## modulate.a over a protected actor's readability box against authored
	## occlusion volumes, and "none" is an explicit solid base that never
	## enters the fallback. Ambient residents behind a piece read through the
	## authored art gaps only, and actor nodes are never occluders — only
	## native pieces with an occlusion binding id carry reveal materials.
	## Actor ids are populated completely before any relationship is read, so
	## the actor-occluder diagnostic never depends on iteration order.
	var actor_ids: Dictionary = {}
	for actor_id: String in actor_presentation_ids():
		actor_ids[actor_id] = true
	var occluder_covers: Dictionary = {}
	var occluder_slot_actors: Dictionary = {}
	var occluder_actor_ids: Array[String] = []
	for actor_id: String in actor_presentation_ids():
		for occluder: Dictionary in plan.occluders_of(actor_id):
			var occluder_id := String(occluder.get("stable_id", ""))
			if occluder_id.is_empty():
				continue
			var cover := float(occluder.get("cover_fraction", 0.0))
			occluder_covers[occluder_id] = maxf(float(occluder_covers.get(occluder_id, 0.0)), cover)
			if actor_ids.has(occluder_id) and not occluder_actor_ids.has(occluder_id):
				occluder_actor_ids.append(occluder_id)
			if _reveal_slot_eligible(actor_id):
				(occluder_slot_actors.get_or_add(occluder_id, []) as Array).append(actor_id)
	occluder_actor_ids.sort()
	## Every plan entry that is not an actor is a native front piece: covered
	## pieces get their tiered window, uncovered pieces ease back to opaque.
	## Resolving the piece node here also seeds the node cache.
	for entry: Dictionary in entries:
		var stable_id := String(entry.get("stable_id", ""))
		if stable_id.is_empty() or actor_ids.has(stable_id):
			continue
		var native := _occluder_piece(stable_id)
		if native != null and native.has_meta("reveal_policy"):
			var piece_policy := String(native.get_meta("reveal_policy"))
			## Policy dispatch: an explicitly configured piece is never part
			## of the legacy silhouette fallback. Any reveal material the
			## piece collected while it was still unconfigured is detached
			## here, so an explicit solid base (policy "none") and a fade
			## target both draw exactly their configured pixels — modulate.a 1
			## alone would still let a leftover silhouette material cut them.
			_detach_silhouette_material(stable_id, native)
			if piece_policy == PrimitiveFadeScript.POLICY:
				if native.has_meta("reveal_variant_path") or native.has_meta("reveal_full_path"):
					_reset_occlusion("primitive_fade_invalid", ["primitive_fade_policy_conflict:" + stable_id])
					return
				if not _primitive_fade.has_piece(stable_id):
					var faded: Dictionary = _primitive_fade.register_piece(stable_id, native as Sprite2D,
						native.get_meta("occlusion_volumes", null))
					if not bool(faded.get("ok", false)):
						_reset_occlusion("primitive_fade_invalid", [String(faded.get("error", "unknown"))])
						return
			elif piece_policy == PairedRevealScript.POLICY:
				## Whole-object pair: no mask, no volumes, one detection rect.
				if native.has_meta("reveal_mask_path") or native.has_meta("occlusion_volumes"):
					_reset_occlusion("paired_reveal_invalid", ["paired_reveal_policy_conflict:" + stable_id])
					return
				if not _paired_reveal.has_piece(stable_id):
					var paired: Dictionary = _paired_reveal.register_native_piece(stable_id, native as Sprite2D)
					if not bool(paired.get("ok", false)):
						_reset_occlusion("paired_reveal_invalid", [String(paired.get("error", "unknown"))])
						return
			elif piece_policy == "authored_variant" and not _authored_reveal.has_piece(stable_id):
				var registered: Dictionary = _authored_reveal.register_native_piece(stable_id, native as Sprite2D)
				if not registered.ok:
					_reset_occlusion("authored_reveal_invalid", [registered.error])
					return
			continue
		_occlusion_controller.set_occluder_cover(stable_id, float(occluder_covers.get(stable_id, 0.0)))
	var protected: Array[Dictionary] = []
	for actor_id: String in actor_presentation_ids():
		if actor_id != HERO_ID and actor_id != "town/npc/" + _protected_resident:
			continue
		var anchor := _actor_world_position(actor_id)
		if anchor.is_finite():
			protected.append({"stable_id": actor_id, "baseline_y": anchor.y, "rank": 1,
				"readability_box": Rect2(anchor + Vector2(-8, -34), Vector2(16, 28))})
	_authored_reveal.update(entries, protected, maxf(display_delta, 0.0))
	_primitive_fade.update(entries, protected, maxf(display_delta, 0.0))
	_paired_reveal.update(entries, protected, maxf(display_delta, 0.0))
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
	var silhouette_rows: Dictionary = {}
	for occluder_id: String in _occlusion_controller.occluder_ids():
		var piece: CanvasItem = _occluder_piece(occluder_id)
		if piece != null and piece.has_meta("reveal_policy"):
			## One policy per piece: an explicitly dispatched piece (solid
			## base, authored variant, or primitive fade) is never part of
			## the legacy silhouette fallback, even if a stale window row
			## from before the dispatch remains in the report registry.
			continue
		var window := _occlusion_controller.occluder_alpha(occluder_id)
		var piece_alpha := clampf(window, 0.0, 1.0) if is_finite(window) else 1.0
		window_alphas[occluder_id] = piece_alpha
		if piece != null:
			## Pieces are globally opaque; the window value stays report-only
			## continuity for the detached plan tiers. What changes on screen is
			## only the shader's exact silhouette clear.
			piece.modulate.a = 1.0
			silhouette_rows[occluder_id] = _apply_silhouette_reveal(occluder_id, piece,
				occluder_slot_actors.get(occluder_id, []), maxf(display_delta, 0.0))
	_silhouette_reveal.drop_except(silhouette_rows.keys())
	## Whether any live plan selected an actual actor node as a foreground
	## occluder. Such entries keep their legacy report row but can never carry
	## a reveal material: actor sprites have no occlusion binding id, so the
	## exact reveal is native-piece only by construction.
	var native_only := true
	for occluder_id: String in silhouette_rows.keys():
		if actor_ids.has(occluder_id):
			native_only = false
	_occlusion_report = {"available": true, "reason": "", "plan_size": entries.size(),
		"occluded_ids": occluded_ids, "alphas": alphas, "occluder_alphas": window_alphas,
		"silhouette_reveal": silhouette_rows, "actor_occluder_ids": occluder_actor_ids,
		"silhouette_native_piece_only": native_only, "authored_reveal": _authored_reveal.report(),
		"primitive_fade": _primitive_fade.report(), "paired_reveal": _paired_reveal.report()}


func _reset_occlusion(reason: String, errors: Array = []) -> void:
	_authored_reveal.reset()
	_silhouette_reveal.reset()
	_primitive_fade.reset()
	_paired_reveal.reset()
	for actor_id: String in actor_presentation_ids():
		_apply_actor_alpha(actor_id, 1.0)
	_occlusion_controller.clear_occluders()
	for occluder_id: String in _occluder_piece_cache.keys():
		var piece: CanvasItem = _occluder_piece(occluder_id)
		if piece != null:
			piece.modulate.a = 1.0
	for material: ShaderMaterial in _occluder_materials.values():
		material.set_shader_parameter("actor_count", 0)
		material.set_shader_parameter("reveal_weight", 0.0)
	_occlusion_report = {"available": false, "reason": reason, "errors": errors.duplicate(), "alphas": {}}


func _apply_actor_alpha(actor_id: String, alpha: float) -> void:
	var sprite := _actor_sprite_of(actor_id)
	if sprite != null:
		sprite.modulate.a = clampf(alpha, 0.0, 1.0)


## Detaches a piece's silhouette reveal material and forgets its cached
## uniform set, so a dispatched policy — including an explicit solid "none"
## base — can never keep cutting pixels the policy did not configure.
func _detach_silhouette_material(stable_id: String, piece: CanvasItem) -> void:
	if not _occluder_materials.has(stable_id):
		return
	if piece.material != null and piece.material == _occluder_materials.get(stable_id, null):
		piece.material = null
	_occluder_materials.erase(stable_id)


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

var _occluder_materials: Dictionary = {}


## The drawn sprite of one bound town actor: the hero's or a resident's live
## Sprite2D, whatever frame it currently shows.
func _actor_sprite_of(actor_id: String) -> Sprite2D:
	if actor_id == HERO_ID:
		return _hero_sprite if _hero_sprite != null and is_instance_valid(_hero_sprite) else null
	if actor_id.begins_with("town/npc/"):
		var record: Variant = _resident_views.get(actor_id.trim_prefix("town/npc/"), null)
		var sprite: Variant = record.get("node", null) if record is Dictionary else null
		return sprite if sprite is Sprite2D and is_instance_valid(sprite) else null
	return null


## Reveal slot eligibility: the hero and the resident the hub is currently
## protecting for conversation. Exact silhouette clears are a readability
## affordance for the player and their dialogue partner — ambient residents
## never receive them and the covering piece stays fully opaque over them.
func _reveal_slot_eligible(actor_id: String) -> bool:
	return actor_id == HERO_ID or (not _protected_resident.is_empty() and actor_id == "town/npc/" + _protected_resident)


var _silhouette_padding: ImageTexture


## Fills the uniform sampler array past actor_count. Always transparent so a
## renderer or shader regression that samples it can never clear anything.
func _silhouette_padding_texture() -> ImageTexture:
	if _silhouette_padding == null:
		var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
		image.fill(Color(0.0, 0.0, 0.0, 0.0))
		_silhouette_padding = ImageTexture.create_from_image(image)
	return _silhouette_padding


## The covered actor's authoritative feet anchor. A missing resident position
## yields a non-finite point and contributes no hole instead of opening one at
## a guessed location.
func _actor_world_position(actor_id: String) -> Vector2:
	if actor_id == HERO_ID:
		return hero_world_position()
	if actor_id.begins_with("town/npc/"):
		var residents: Variant = _state.get("residents", {})
		if residents is Dictionary:
			var pos: Variant = (residents as Dictionary).get(actor_id.trim_prefix("town/npc/"), null)
			if pos is Vector2:
				return pos
	return Vector2.INF


## Opens the actual-silhouette reveal on one covering front piece. The AABB
## candidates from the detached plan are refined against the live source
## alpha, so an overlap with a piece's transparent tail opens nothing; the
## piece then clears exactly over each covered actor's current opaque
## silhouette texels while every other pixel keeps its authored look. The
## reveal weight eases on the silhouette controller's own clock — where the
## legacy window tier settles between 0.4 and 1 no longer bounds how clear the
## actor becomes. Returns the applied, diagnostic-ready row.
func _apply_silhouette_reveal(occluder_id: String, piece: CanvasItem, actor_ids: Array, display_delta: float) -> Dictionary:
	var coverages: Dictionary = {}
	for actor_id: String in actor_ids:
		var sprite := _actor_sprite_of(actor_id)
		if sprite != null:
			coverages[actor_id] = _silhouette_reveal.silhouette_coverage(sprite, piece as Sprite2D)
	var state: Dictionary = _silhouette_reveal.update(occluder_id, coverages, display_delta)
	var slots: Array[String] = []
	for actor_id: String in coverages.keys():
		if float(coverages[actor_id]) > 0.0:
			slots.append(actor_id)
	slots.sort_custom(func(left: String, right: String) -> bool:
		if not is_equal_approx(float(coverages[left]), float(coverages[right])):
			return float(coverages[left]) > float(coverages[right])
		return left < right)
	if slots.size() > SilhouetteRevealScript.MAX_ACTORS:
		slots = slots.slice(0, SilhouetteRevealScript.MAX_ACTORS)
	var material: ShaderMaterial = _occluder_materials.get(occluder_id, null)
	if material == null:
		material = ShaderMaterial.new()
		material.shader = _silhouette_reveal.RevealShader
		piece.material = material
		_occluder_materials[occluder_id] = material
	## Uniform arrays are uploaded at the shader's declared length, padded past
	## actor_count with an always-transparent texel source: renderers validate
	## the whole array, while the count guard never samples the padding.
	var cells := PackedVector4Array()
	cells.resize(SilhouetteRevealScript.MAX_ACTORS)
	var regions := PackedVector4Array()
	regions.resize(SilhouetteRevealScript.MAX_ACTORS)
	var flags := PackedVector4Array()
	flags.resize(SilhouetteRevealScript.MAX_ACTORS)
	var textures: Array = []
	textures.resize(SilhouetteRevealScript.MAX_ACTORS)
	for index in range(SilhouetteRevealScript.MAX_ACTORS):
		textures[index] = _silhouette_padding_texture()
	var actor_rows: Dictionary = {}
	for slot in slots.size():
		var actor_id := String(slots[slot])
		var sprite := _actor_sprite_of(actor_id)
		var cell: Rect2 = SilhouetteRevealScript.viewport_cell_rect(sprite)
		var region: Rect2 = SilhouetteRevealScript.cell_region(sprite)
		var texture: Texture2D = sprite.texture
		cells[slot] = Vector4(cell.position.x, cell.position.y, cell.size.x, cell.size.y)
		regions[slot] = Vector4(region.position.x, region.position.y, region.size.x, region.size.y)
		flags[slot] = Vector4(1.0 if sprite.flip_h else 0.0, 1.0 if sprite.flip_v else 0.0,
			texture.get_width(), texture.get_height())
		textures[slot] = texture
		actor_rows[actor_id] = {
			"coverage": float(coverages[actor_id]),
			"cell": [cell.position.x, cell.position.y, cell.size.x, cell.size.y],
			"region": [region.position.x, region.position.y, region.size.x, region.size.y],
			"source_frame": String(texture.resource_path),
			"flip_h": sprite.flip_h, "flip_v": sprite.flip_v,
			"modulate": sprite.modulate.a,
		}
	material.set_shader_parameter("actor_cells", cells)
	material.set_shader_parameter("actor_regions", regions)
	material.set_shader_parameter("actor_flags", flags)
	material.set_shader_parameter("actor_textures", textures)
	material.set_shader_parameter("actor_count", slots.size())
	material.set_shader_parameter("reveal_weight", float(state["weight"]))
	material.set_shader_parameter("clear_alpha", SilhouetteRevealScript.CLEAR_ALPHA)
	return {
		"occluder": occluder_id,
		"open": bool(state["open"]),
		"weight": float(state["weight"]),
		"coverage": float(state["coverage"]),
		"clear_alpha": SilhouetteRevealScript.CLEAR_ALPHA,
		"actor_count": slots.size(),
		"piece_modulate": piece.modulate.a,
		"actors": actor_rows,
	}


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


func protect_dialogue_resident(resident_id: String) -> void:
	_protected_resident = resident_id if _resident_views.has(resident_id) else ""


func actor_alpha(stable_id: String) -> float:
	var sprite := _actor_sprite_of(stable_id)
	return sprite.modulate.a if sprite != null else 1.0


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
	sprite.material = Readability.material_for("hero" if node_name == "Ranger" else "resident")
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
	var contract: Dictionary = {}
	if _presentation_runtime != null:
		var value: Variant = _presentation_runtime.get("native_scene_contract")
		if value is Dictionary:
			contract = value
	## Actual drawn state, kept distinct from the plan's hypothetical alphas:
	## every actor's real modulate plus the silhouette uniforms really applied
	## to covering front pieces (source frame, viewport cell, refined opaque
	## coverage), so a rendered frame can be verified against what the draw
	## calls consumed instead of against presentation intentions.
	var modulates: Dictionary = {}
	for actor_id: String in actor_presentation_ids():
		modulates[actor_id] = actor_alpha(actor_id)
	var silhouette: Dictionary = _occlusion_report.get("silhouette_reveal", {}) if _occlusion_report.get("available", false) else {}
	var primitive: Dictionary = _occlusion_report.get("primitive_fade", {}) if _occlusion_report.get("available", false) else {}
	var paired: Dictionary = _occlusion_report.get("paired_reveal", {}) if _occlusion_report.get("available", false) else {}
	return {"ready": is_ready(), "dressing": _dressing.report("town"), "view_size": Vector2(world_viewport.size), "ground_source_path": contract.get("ground_source_path", ""), "runtime_background_patches": 0,
		"unknown_underplate": contract.get("unknown_underplate", "unknown"),
		"supports_cutaway": contract.get("supports_cutaway", false), "supports_fade": contract.get("supports_fade", false),
		"occlusion_available": bool(_occlusion_report.get("available", false)),
		"shared_sort_root": world_presenter != null and world_presenter.sort_root.y_sort_enabled,
		"native_count": world_presenter.sort_root.get_child_count() - world_presenter.actor_ids().size() if world_presenter != null else 0,
		"actor_modulates": modulates,
		"silhouette_reveal": {"clear_alpha": SilhouetteRevealScript.CLEAR_ALPHA, "occluders": silhouette,
			"actor_occluder_ids": _occlusion_report.get("actor_occluder_ids", []).duplicate(),
			"native_piece_only": bool(_occlusion_report.get("silhouette_native_piece_only", true))},
		"primitive_fade": {"faded_alpha": PrimitiveFadeScript.FADED_ALPHA,
			"transition_seconds": PrimitiveFadeScript.TRANSITION_SECONDS,
			"occluders": primitive},
		"paired_reveal": {"transition_seconds": PairedRevealScript.TRANSITION_SECONDS,
			"occluders": paired}}
