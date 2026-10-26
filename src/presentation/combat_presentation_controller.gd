class_name CombatPresentationController
extends Node2D

## Canvas/HUD assembly only. Animation and feedback own their states; the frame
## builder projects detached gameplay values. No Main object or gameplay service
## is injected here, and no drawn frame can submit a motor operation.
signal skill_requested(ability: String)
signal return_requested

const WorldPresenterScript := preload("res://src/runtime/world/world_presenter.gd")
const SceneRuntimeScript := preload("res://src/runtime/world/scene_runtime.gd")
const Animations := preload("res://src/presentation/combat_animation_controller.gd")
const Feedback := preload("res://src/presentation/combat_feedback_controller.gd")
const FrameBuilder := preload("res://src/presentation/combat_presentation_frame_builder.gd")
const ArenaHud := preload("res://src/presentation/arena_hud.gd")
const ArenaPresenter := preload("res://src/presentation/arena_presenter.gd")
const ArenaCombatPresenter := preload("res://src/presentation/arena_combat_presenter.gd")
const ArenaActorPresenter := preload("res://src/presentation/arena_actor_presenter.gd")
const ArenaWorldView := preload("res://src/presentation/arena_world_view.gd")
const OcclusionControllerScript := preload("res://src/presentation/occlusion/occlusion_controller.gd")
const ShellTheme := preload("res://src/presentation/shell_theme.gd")
const PaletteScript := preload("res://src/presentation/combat_palette.gd")
const ROOM_ENTRY_DURATION_TICKS := 36
const COLOR_INK: Color = PaletteScript.INK
const COLOR_DEEP_BLUE: Color = PaletteScript.SLATE_0
const COLOR_GROUND: Color = PaletteScript.SLATE_1
const COLOR_NEUTRAL: Color = PaletteScript.SLATE_3
const COLOR_BONE: Color = PaletteScript.BONE
const COLOR_AMBER: Color = PaletteScript.COPPER
const COLOR_BLOOD: Color = PaletteScript.DANGER
const COLOR_WARNING: Color = PaletteScript.DANGER_BRIGHT
const COLOR_PROXY: Color = PaletteScript.COLD
const COLOR_ANOMALY: Color = PaletteScript.PURPLE

var enabled := true
var animations := Animations.new()
var feedback := Feedback.new()
var frame_builder := FrameBuilder.new()
var actor_presenter := ArenaActorPresenter.new()
var combat_presenter := ArenaCombatPresenter.new()
var arena_presenter: Node2D
var world_view: RefCounted
var world_pending_reason := ""
var font: Font
var hud: Control
var _input_projection := ArenaWorldView.new()
var _snapshot: Dictionary = {}
var _world_frame: Dictionary = {}
var _combat_frame: Dictionary = {}
var _actor_frame: Dictionary = {}
var _binding_mode := "unconfigured"
var _runtime_source: WeakRef
var _domain: WorldPresenter
var _domain_original_transform := Transform2D.IDENTITY
var _room_identity := ""
var _accept_frames := true
var _terminated := false
var _render_active := false
var _sort_report: Dictionary = {"ok": false, "error": "sort_binding_unconfigured"}
var _occlusion := OcclusionControllerScript.new()
var _occlusion_report: Dictionary = {"available": false, "reason": "binding_unavailable"}
var _ground_pass: Node2D


class GroundPass extends Node2D:
	var controller: WeakRef

	func _draw() -> void:
		var source: Variant = controller.get_ref() if controller != null else null
		if source != null:
			source.draw_ground_pass(self)


func _ready() -> void:
	# Mounted Main is inside NativeWorld. The canvas/HUD must not inherit the
	# gameplay camera transform applied to that world and all native actors.
	top_level = true
	global_transform = Transform2D.IDENTITY
	z_index = 30


## Explicit unmounted fixture path; never substitutes for a mounted dependency.
func configure_standalone() -> Dictionary:
	if _binding_mode == "mounted":
		return {"ok": false, "error": "mounted_binding_cannot_be_replaced"}
	_binding_mode = "standalone_unmounted"
	return {"ok": true, "error": ""}


func _bind_sort_source() -> void:
	var host := get_parent()
	var declared := host != null and host.get_property_list().any(func(item: Dictionary) -> bool: return item.name == "scene_runtime")
	if declared:
		var source: Variant = host.get("scene_runtime")
		if source != null:
			_binding_mode = "mounted"
			if not source is SceneRuntimeScript:
				_sort_report = {"ok": false, "error": "invalid_scene_runtime"}
				return
			_runtime_source = weakref(source)
			source.ready_changed.connect(_on_runtime_ready_changed)
		elif host.has_node("RoomAsset"):
			_binding_mode = "mounted"
			_sort_report = {"ok": false, "error": "mounted_runtime_detached"}
		elif _binding_mode != "mounted":
			# A bare Main.new() has no native author root and a declared null
			# injection: this is the explicit unmounted diagnostic/fixture path.
			_binding_mode = "standalone_unmounted"
	if _binding_mode == "standalone_unmounted":
		_domain = WorldPresenterScript.new()
		_domain.name = "StandaloneWorldPresenter"
		_domain.z_as_relative = false
		add_child(_domain)
		_domain_original_transform = _domain.transform


func _resolve_sort_domain() -> Dictionary:
	if _terminated or not is_inside_tree():
		return {"ok": false, "error": "presentation_session_closed"}
	if _binding_mode == "standalone_unmounted":
		if not is_instance_valid(_domain):
			return {"ok": false, "error": "standalone_sort_domain_unavailable"}
	elif _binding_mode == "mounted":
		var source: Variant = _runtime_source.get_ref() if _runtime_source != null else null
		if source == null or get_parent().get("scene_runtime") != source:
			return {"ok": false, "error": "mounted_runtime_detached"}
		if not source.is_ready() or source.mounted_scene != get_parent():
			return {"ok": false, "error": "native_room_not_mounted"}
		var domain_value: Variant = source.presenter
		if not is_instance_valid(domain_value) or not domain_value is WorldPresenterScript or domain_value.is_queued_for_deletion():
			return {"ok": false, "error": "native_sort_domain_unavailable"}
		if _room_identity.is_empty() or _room_identity != source.room_instance_id:
			## SceneRuntime.restart_room_instance() mints a new room instance id
			## for the same mounted room shell. The checks above already reject
			## any presentation whose host is not the currently mounted scene,
			## so an id change here is exactly the sanctioned in-place restart
			## boundary: re-latch the identity the way the runtime side
			## replace_projector() does, instead of permanently dropping event
			## consumption and drawing for the restarted room.
			_room_identity = source.room_instance_id
		if _domain != domain_value:
			actor_presenter.release_sort_views()
			_domain = domain_value
			_domain_original_transform = _domain.transform
	else:
		return {"ok": false, "error": "sort_binding_unconfigured"}
	if _domain.sort_root == null or not _domain.sort_root.y_sort_enabled:
		return {"ok": false, "error": "native_sort_root_invalid"}
	return {"ok": true, "error": ""}


func _on_runtime_ready_changed(ready: bool, _report: Dictionary) -> void:
	if not ready:
		_terminated = true
		_clear_render_state("presentation_session_closed")


func _exit_tree() -> void:
	_terminated = true
	_clear_render_state("presentation_session_closed")


func sort_report() -> Dictionary:
	var result := _sort_report.duplicate(true)
	result["binding_mode"] = _binding_mode
	result["render_active"] = _render_active
	result["actor_ids"] = _domain.actor_ids() if is_instance_valid(_domain) else []
	result["occlusion"] = _occlusion_report.duplicate(true)
	return result


func _set_native_visible(value: bool) -> void:
	if not is_instance_valid(_domain):
		return
	# NativeWorld contains Main and its input/HUD. Hide only the four drawing
	# layers, so off mode keeps exactly the same physical input ownership.
	for group: String in WorldPresenterScript.LAYER_NAMES:
		var layer := _domain.native_group(group)
		if is_instance_valid(layer):
			layer.visible = value


func _clear_render_state(reason: String = "") -> void:
	_render_active = false
	if world_view != null:
		world_view.reset_structure_fades()
	actor_presenter.release_sort_views()
	actor_presenter.apply_occlusion_alpha({})
	_occlusion_report = {"available": false, "reason": "presentation_session_closed"}
	_set_native_visible(false)
	if is_instance_valid(_domain):
		_domain.transform = _domain_original_transform
	_world_frame.clear()
	_combat_frame.clear()
	_actor_frame.clear()
	if is_instance_valid(arena_presenter):
		arena_presenter.hide()
	if is_instance_valid(_ground_pass):
		_ground_pass.queue_redraw()
	_sort_report = {"ok": reason.is_empty(), "error": reason}
	queue_redraw()



func _init() -> void:
	add_child(feedback)


func load_assets(presentation_enabled: bool, interface_theme: Theme) -> Array[String]:
	_bind_sort_source()
	enabled = presentation_enabled
	animations.enabled = enabled
	feedback.enabled = enabled
	var errors: Array[String] = []
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = ArenaHud.new()
	hud.theme = interface_theme
	layer.add_child(hud)
	hud.visible = false
	# Drawing may be disabled for replay, but the same controls still own input
	# and receive layout updates. Canvas visibility must not change held sources.
	hud.modulate.a = 1.0 if enabled else 0.0
	hud.skill_one_requested.connect(func() -> void: skill_requested.emit("piercing_arrow"))
	hud.skill_two_requested.connect(func() -> void: skill_requested.emit("hunter_mark"))
	hud.skill_three_requested.connect(func() -> void: skill_requested.emit("dash"))
	hud.dodge_requested.connect(func() -> void: skill_requested.emit("basic_dodge"))
	hud.return_requested.connect(_on_hud_return_requested)
	if _binding_mode == "unconfigured" or (_binding_mode == "mounted" and _runtime_source == null):
		errors.append("presentation:%s" % String(_sort_report.error))
	if not enabled:
		return errors
	font = ShellTheme.ui_font()
	feedback.load_assets()
	world_view = ArenaWorldView.new()
	if not world_view.load_assets():
		world_pending_reason = String(world_view.pending_reason)
		errors.append("arena_art:%s" % world_pending_reason)
		world_view = null
	animations.world_ready = world_view != null
	animations.load_assets()
	arena_presenter = ArenaPresenter.new()
	arena_presenter.name = "ArenaPresenter"
	arena_presenter.show_behind_parent = true
	arena_presenter.z_as_relative = false
	arena_presenter.z_index = -20
	add_child(arena_presenter)
	arena_presenter.configure(Callable(self, "world_frame"), Callable(self, "world_dependencies"))
	_ground_pass = GroundPass.new()
	_ground_pass.name = "CombatGroundEffects"
	_ground_pass.controller = weakref(self)
	_ground_pass.z_as_relative = false
	_ground_pass.z_index = -10
	add_child(_ground_pass)
	return errors


func reset_battle() -> void:
	_clear_render_state()
	_accept_frames = not _terminated
	animations.reset()
	feedback.reset()
	_world_frame.clear()
	_combat_frame.clear()
	_actor_frame.clear()


func leave_arena() -> void:
	_accept_frames = false
	_clear_render_state()
	animations.ranger_visual_time = 0.0
	animations._reset_enemy_animation()
	if animations.defeat_presentation != null and not animations.defeat_presentation.route_ready():
		animations.defeat_skip_presentation("return_to_base")
	if feedback.combat_feedback_audio != null:
		feedback.combat_feedback_audio.reset_audio()
	if hud != null:
		hud.visible = false


func advance_time(snapshot: Dictionary, delta: float) -> void:
	feedback.consume(snapshot.get("events", []), animations, int(snapshot.get("sim_tick", 0)))
	feedback.advance(delta)
	animations.advance_time(snapshot, delta)


func commit(snapshot: Dictionary, input_view: Dictionary, display_delta: float = 0.0) -> Dictionary:
	if _terminated or not is_inside_tree() or (bool(snapshot.get("in_arena", false)) and not _accept_frames):
		_clear_render_state("presentation_session_closed")
		if is_instance_valid(hud):
			hud.visible = false
		return _sort_report.duplicate(true)
	_snapshot = snapshot
	if hud != null:
		hud.visible = bool(snapshot["in_arena"])
		hud.modulate.a = 1.0 if enabled else 0.0
	if not bool(snapshot["in_arena"]):
		_clear_render_state()
		return {"ok": true, "error": ""}
	if hud != null:
		hud.present(frame_builder.hud_frame(snapshot, input_view, _combat_focus_near_action_edge(snapshot, frame_builder.nearest_target(snapshot))))
	var binding := _resolve_sort_domain()
	if not bool(binding.ok):
		_clear_render_state(String(binding.error))
		return binding
	_input_projection.begin_frame(Rect2(Vector2.ZERO, get_viewport_rect().size), snapshot["player_position"], snapshot["arena_rect"])
	_domain.global_transform = _input_projection.gameplay_transform()
	_set_native_visible(enabled)
	if not enabled:
		_clear_render_state()
		_domain.global_transform = _input_projection.gameplay_transform()
		_sort_report = {"ok": true, "error": "", "state": "disabled"}
		return _sort_report.duplicate(true)
	if world_view == null or not world_view.is_ready():
		_clear_render_state("arena_art_unavailable")
		return _sort_report.duplicate(true)
	feedback.consume(snapshot.get("events", []), animations, int(snapshot["sim_tick"]))
	animations.commit(snapshot)
	animations.observe_frame(display_delta)
	var visual := {
		"ranger_visual_time": animations.ranger_visual_time,
		"ranger_frame": animations.ranger_frame.duplicate(true),
		"enemy_frames": animations.enemy_frames.duplicate(true),
		"enemy_corpses": animations.enemy_corpses.duplicate(true),
		"traces": feedback.traces.duplicate(),
		"combat_feedback_marks": feedback.combat_feedback_marks.duplicate(true),
		"player_damage_overlay": animations._player_damage_overlay_state(snapshot),
	}
	var viewport := Rect2(Vector2.ZERO, get_viewport_rect().size)
	_world_frame = frame_builder.world_frame(snapshot, viewport, world_pending_reason)
	_combat_frame = frame_builder.combat_frame(snapshot, input_view, visual, font)
	_actor_frame = frame_builder.actor_frame(snapshot, visual)
	# Camera preparation precedes occlusion and node submission. Draw callbacks
	# reuse this committed camera; they never reset the per-part cutaway plan.
	world_view.set_layout_id(String(snapshot.get("layout_id", "rectangle_arena")))
	world_view.begin_frame(viewport, snapshot["player_position"], snapshot["arena_rect"])
	_world_frame["camera_prepared"] = true
	_domain.global_transform = world_view.gameplay_transform()
	var submitted := actor_presenter.sync_sort_views(_domain, _actor_frame, world_view, display_delta)
	if not bool(submitted.ok):
		_clear_render_state(String(submitted.error))
		return submitted
	_sort_report = submitted.duplicate(true)
	_apply_detached_occlusion(display_delta)
	_render_active = true
	arena_presenter.show()
	_ground_pass.queue_redraw()
	queue_redraw()
	if is_instance_valid(arena_presenter):
		arena_presenter.request_redraw()
	return _sort_report.duplicate(true)


## Drives the drawn actor views from the mounted room's detached
## PresentationFrame/OcclusionPlan through the presentation-only
## OcclusionController. Every input is a detached plain-value plan and every
## output lands on drawn sort views, so occlusion display state can never
## reach simulation state. An unavailable plan resets all alphas instead of
## leaving stale dimming on screen.
func _apply_detached_occlusion(display_delta: float) -> void:
	if _binding_mode != "mounted" or _terminated:
		_record_occlusion(false, "binding_unavailable")
		return
	var source: Variant = _runtime_source.get_ref() if _runtime_source != null else null
	var port_value: Variant = source.get("presentation_port") if source != null else null
	if port_value == null or not port_value.has_method("latest_occlusion_plan"):
		actor_presenter.apply_occlusion_alpha({})
		_record_occlusion(false, "presentation_port_unavailable")
		return
	var plan_result: Dictionary = port_value.call("latest_occlusion_plan")
	if not bool(plan_result.get("ok", false)):
		actor_presenter.apply_occlusion_alpha({})
		var errors: Array = (plan_result.get("errors", []) as Array).slice(0, 3)
		_record_occlusion(false, "plan_unavailable", errors)
		return
	var plan: Variant = plan_result.get("value", null)
	if plan == null or not bool(_occlusion.call("sync_plan", plan).get("ok", false)):
		actor_presenter.apply_occlusion_alpha({})
		_record_occlusion(false, "plan_sync_failed")
		return
	var entries: Array = plan.call("entries")
	for entry: Variant in entries:
		var stable_id := String((entry as Dictionary)["stable_id"])
		var report: Dictionary = plan.call("occlusion_report", stable_id)
		if bool(report.get("ok", false)):
			_occlusion.call("set_cover", stable_id, float(report.get("cover_fraction", 0.0)))
	_occlusion.call("update", maxf(display_delta, 0.0))
	var alphas: Dictionary = {}
	var occluded_ids: Array[String] = []
	for entry: Variant in entries:
		var stable_id := String((entry as Dictionary)["stable_id"])
		var alpha: float = float(_occlusion.call("alpha", stable_id))
		alphas[stable_id] = alpha
		if alpha < 0.999:
			occluded_ids.append(stable_id)
	# Covered actors remain opaque. The covering structure owns transparency;
	# actor-over-actor readability still uses the local cutaway drawing path.
	actor_presenter.apply_occlusion_alpha({})
	_record_occlusion(true, "", [], {
		"plan_size": entries.size(),
		"occluded_ids": occluded_ids,
		"plan_alphas": alphas.duplicate(),
		"alphas": _opaque_actor_alphas(alphas),
		"primitive_fade": world_view.structure_fade_report(),
	})


func _opaque_actor_alphas(plan_alphas: Dictionary) -> Dictionary:
	var result := {}
	for id: String in plan_alphas:
		result[id] = 1.0
	return result


func _record_occlusion(available: bool, reason: String = "", errors: Array = [], detail: Dictionary = {}) -> void:
	_occlusion_report = {"available": available, "reason": reason, "errors": errors.duplicate()}
	if available:
		_occlusion_report.merge(detail, true)


func world_frame() -> Dictionary:
	return _world_frame.duplicate(true)


func world_dependencies() -> Dictionary:
	return {"world_view": world_view, "font": font}


func screen_to_gameplay(screen_point: Vector2, snapshot: Dictionary) -> Vector2:
	# Coordinate interpretation is available even when all drawing is disabled.
	_input_projection.begin_frame(Rect2(Vector2.ZERO, get_viewport_rect().size), snapshot["player_position"], snapshot["arena_rect"])
	return _input_projection.screen_to_gameplay(screen_point)


func is_pointer_over_interface(point: Vector2 = Vector2(-INF, -INF)) -> bool:
	if hud == null or not hud.visible:
		return false
	# Production ArenaHud accepts the event coordinate so a physical click is
	# classified before Control hover state catches up. Lightweight HUD doubles
	# used by presentation tests still expose the original zero-argument query;
	# preserve that contract instead of sending an invalid call into the double.
	if _pointer_query_accepts_point(hud):
		return bool(hud.call("is_pointer_over_interface", point))
	return bool(hud.call("is_pointer_over_interface"))


func _pointer_query_accepts_point(node: Object) -> bool:
	for method: Dictionary in node.get_method_list():
		if String(method.get("name", "")) != "is_pointer_over_interface":
			continue
		var arguments = method.get("args", [])
		return arguments is Array and not (arguments as Array).is_empty()
	return false


func draw_ground_pass(canvas: CanvasItem) -> void:
	if not _render_active:
		return
	canvas.draw_set_transform_matrix(world_view.world_transform())
	actor_presenter.draw_shadows(canvas, _actor_frame, world_view)
	canvas.draw_set_transform_matrix(world_view.gameplay_transform())
	combat_presenter.draw_ground(canvas, _combat_frame)
	canvas.draw_set_transform_matrix(Transform2D.IDENTITY)


func _draw() -> void:
	if not _render_active:
		return
	draw_set_transform_matrix(world_view.world_transform())
	combat_presenter.draw_target_indicators(self, _combat_frame, world_view)
	draw_set_transform_matrix(world_view.gameplay_transform())
	combat_presenter.draw_overlays(self, _combat_frame, world_view)
	draw_set_transform_matrix(Transform2D.IDENTITY)
	_draw_room_entry_overlay(Rect2(Vector2.ZERO, get_viewport_rect().size))


func _combat_focus_near_action_edge(snapshot: Dictionary, nearest: CombatEnemyState) -> bool:
	var frame := Rect2(Vector2.ZERO, get_viewport_rect().size)
	if frame.size.x <= 0.0 or frame.size.y <= 0.0:
		return false
	_input_projection.begin_frame(frame, snapshot["player_position"], snapshot["arena_rect"])
	var edge := Rect2(frame.end - Vector2(332.0, 190.0), Vector2(324.0, 182.0)).grow(24.0)
	if edge.has_point(_input_projection.gameplay_to_screen(snapshot["player_position"])):
		return true
	if nearest != null and edge.has_point(_input_projection.gameplay_to_screen(nearest.position)):
		return true
	return snapshot["boss"] != null and edge.has_point(_input_projection.gameplay_to_screen(snapshot["boss"].position))


func _draw_room_entry_overlay(viewport_rect: Rect2) -> void:
	if not enabled or not _snapshot["embedded_session"] or _snapshot["framework_room"].is_empty() or _snapshot["battle_over"]:
		return
	var age_ticks: int = _snapshot["sim_tick"] - _snapshot["room_entry_start_tick"]
	if age_ticks < 0 or age_ticks >= ROOM_ENTRY_DURATION_TICKS:
		return
	var progress := float(age_ticks) / float(ROOM_ENTRY_DURATION_TICKS)
	var fade_in := clampf(progress / 0.18, 0.0, 1.0)
	var fade_out := clampf((1.0 - progress) / 0.24, 0.0, 1.0)
	var alpha := minf(fade_in, fade_out)
	if alpha <= 0.01:
		return
	var room_info := frame_builder.room_info(_snapshot)
	var room_count := maxi(1, int(_snapshot["framework_room"].get("room_count", 1)))
	var room_number := clampi(int(_snapshot["framework_room"].get("room_index", 0)) + 1, 1, room_count)
	var panel_width := minf(900.0, maxf(520.0, viewport_rect.size.x - 96.0))
	var panel := Rect2(Vector2((viewport_rect.size.x - panel_width) * 0.5, viewport_rect.size.y * 0.5 - 124.0), Vector2(panel_width, 248.0))
	draw_rect(viewport_rect, Color(COLOR_INK, 0.38 * alpha), true)
	draw_rect(panel, Color(COLOR_DEEP_BLUE, 0.94 * alpha), true)
	draw_rect(panel, Color(COLOR_AMBER, 0.86 * alpha), false, 2.0)
	draw_rect(Rect2(panel.position + Vector2(2.0, 2.0), Vector2(panel.size.x - 4.0, 6.0)), Color(COLOR_AMBER, 0.82 * alpha), true)
	var text_font: Font = font
	if text_font == null:
		return
	var center_x := panel.get_center().x
	var overline := "Through the Exit · Enter the Next Room" if room_number > 1 else "Chapter One Combat · Enter the First Room"
	var title := "Room %d / %d  ·  %s" % [room_number, room_count, String(room_info.get("display_name", "Arena"))]
	var concept := String(room_info.get("concept", ""))
	var entry_hint := String(room_info.get("entry_hint", ""))
	var objective := frame_builder.objective_label(_snapshot)
	var exit_hint := String(room_info.get("exit_hint", ""))
	var title_width := text_font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 30).x
	var overline_width := text_font.get_string_size(overline, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 18).x
	var concept_width := text_font.get_string_size(concept, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 19).x
	var hint_width := text_font.get_string_size(entry_hint, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 18).x
	draw_string(text_font, Vector2(center_x - overline_width * 0.5, panel.position.y + 42.0), overline, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 18, Color(COLOR_PROXY, alpha))
	draw_string(text_font, Vector2(center_x - title_width * 0.5, panel.position.y + 82.0), title, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 30, Color(COLOR_BONE, alpha))
	draw_string(text_font, Vector2(center_x - concept_width * 0.5, panel.position.y + 118.0), concept, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 19, Color(PaletteScript.BONE_DIM, alpha))
	draw_string(text_font, Vector2(center_x - hint_width * 0.5, panel.position.y + 151.0), entry_hint, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 18, Color(COLOR_AMBER, alpha))
	var footer := "%s  ·  %s  ·  %s" % [String(room_info.get("landmark", "Boundary Marker")), objective, exit_hint]
	var footer_width := text_font.get_string_size(footer, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16).x
	draw_string(text_font, Vector2(center_x - footer_width * 0.5, panel.position.y + 187.0), footer, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, Color(COLOR_NEUTRAL, alpha))
	var bar := Rect2(panel.position + Vector2(30.0, panel.size.y - 24.0), Vector2(panel.size.x - 60.0, 4.0))
	draw_rect(bar, Color(COLOR_INK, 0.78 * alpha), true)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * progress, bar.size.y)), Color(COLOR_AMBER, 0.90 * alpha), true)


func _on_hud_return_requested() -> void:
	# Settlement disconnects the runtime's return listener. The remaining death
	# clip belongs to presentation and must close before forwarding the intent.
	if animations.defeat_presentation != null and not animations.defeat_presentation.route_ready():
		animations.defeat_skip_presentation("return_to_base")
	return_requested.emit()
