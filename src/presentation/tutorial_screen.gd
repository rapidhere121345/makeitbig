class_name TutorialScreen
extends Control

signal completed

const ShellThemeScript = preload("res://src/presentation/shell_theme.gd")
## Production art for this arena: published JSON atlases only. The early
## placeholder sheet and the procedural checkerboard are gone; the gameplay
## layer (range circle, real trace, aim marker) stays procedural.
const TutorialArtScript = preload("res://src/presentation/tutorial_art.gd")
const RangerAnimationScript = preload("res://src/presentation/ranger_animation.gd")
const PlayerActionTimelineScript = preload("res://src/systems/player_action_timeline.gd")
const DESIGN_SIZE := Vector2(1280.0, 720.0)
const ARENA_SIZE := Vector2(856.0, 480.0)
const PLAYABLE_BOUNDS := Rect2(62.0, 76.0, 732.0, 344.0)
const HERO_START := Vector2(150.0, 270.0)
const TARGET_POSITION := Vector2(700.0, 240.0)
const MOVE_SPEED := 240.0
const MOVE_REQUIRED_DISTANCE := 140.0
const DODGE_DISTANCE := 92.0
const CAST_RANGE := 280.0
## Pointer picking mirrors the combat convention in ManualAimResolver: the aim
## anchor sits 22px above the target's feet point and the pick radius equals
## the combat body radius (34px). The drill must not invent its own hit rule.
const TARGET_PICK_ANCHOR_OFFSET := Vector2(0.0, -22.0)
const TARGET_PICK_RADIUS := 34.0
## One actionable hint at a time; it expires back to the checklist status.
const HINT_DURATION_SECONDS := 1.4
## The arena's origin inside the design canvas; shared with _mouse_is_over_arena.
const ARENA_ORIGIN := Vector2(32.0, 78.0)
const TRACE_DURATION := 0.34
## Tutorial-local Piercing Arrow authority. Travel is exactly 24 arena units per
## 30 Hz tick; the 4-unit arrow circle sweeps against the normal target's
## 34-unit public aim circle, so a low render rate cannot skip contact.
const PROJECTILE_SPEED := 720.0
const PROJECTILE_RADIUS := 4.0
const TARGET_CONTACT_RADIUS := 34.0
## Latched action events: one id per dodge / cast, so a redraw can never restart
## a clip and the same cast only ever fires once.
const EVENT_DODGE := "tutorial/dodge"
const EVENT_CAST := "tutorial/cast"
## The 2x ranger cell is 96px tall with its feet 88px below the head, while the
## playable band starts 76px below the arena's top edge. The canvas therefore
## paints 12px of slate above the arena so the head is never cropped at the top
## bound; the playable geometry itself is untouched.
const HERO_HEADROOM := float(TutorialArtScript.RANGER_ANCHOR.y * TutorialArtScript.SCALE) - PLAYABLE_BOUNDS.position.y


class TrainingArenaCanvas extends Control:
	var hero_position := HERO_START
	var target_position := TARGET_POSITION
	var hero_facing := Vector2.RIGHT
	var projectile_active := false
	var projectile_previous_position := Vector2.ZERO
	var projectile_position := Vector2.ZERO
	var projectile_direction := Vector2.RIGHT
	var target_flash_time := 0.0
	## Trigger fields for the shared ranger reader, filled by the screen's own
	## presentation clock.
	var ranger_state := {}
	## The frame this arena would draw, resolved once per state change instead of
	## inside _draw(): a state sweep can then read the live frame without a GPU
	## frame, and a capture never reads the atlas mid-draw.
	var hero_frame := {}
	## Validated production art (see TutorialArt). Null or invalid art draws the
	## gameplay layer only: no stand-in character is ever faked in its place.
	var art

	func _init() -> void:
		## Pixel art stays on its own grid: nearest sampling, no smoothing. The arena
		## never clips its own drawing either, because the 96px hero cell legitimately
		## reaches above the arena rect when it stands on the top playable bound.
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		clip_contents = false

	func art_ready() -> bool:
		return art != null and art.has_real_art()

	func _draw() -> void:
		draw_rect(Rect2(Vector2(0.0, -HERO_HEADROOM), ARENA_SIZE + Vector2(0.0, HERO_HEADROOM)), ShellThemeScript.DEEP_BLUE)
		var field := Rect2(28.0, 38.0, 800.0, 402.0)
		draw_rect(field, ShellThemeScript.GROUND)
		_draw_ground()
		draw_rect(field, ShellThemeScript.NEUTRAL, false, 3.0)
		draw_circle(TARGET_POSITION, CAST_RANGE, Color(ShellThemeScript.PROXY, 0.055))
		draw_arc(TARGET_POSITION, CAST_RANGE, 0.0, TAU, 80, Color(ShellThemeScript.PROXY, 0.30), 2.0)
		_draw_target()
		_draw_hero()
		if projectile_active:
			_draw_projectile()

	func _draw_projectile() -> void:
		var aim := projectile_direction.normalized()
		if aim.length_squared() <= 0.000001:
			return
		var side := aim.rotated(PI * 0.5)
		var shaft_tail := projectile_position - aim * 15.0
		if projectile_previous_position.distance_squared_to(projectile_position) > 0.000001:
			draw_line(projectile_previous_position, projectile_position, Color(ShellThemeScript.AMBER, 0.42), 5.0, false)
		draw_line(shaft_tail, projectile_position, Color(ShellThemeScript.INK, 0.90), 6.0, false)
		draw_line(shaft_tail, projectile_position, ShellThemeScript.BONE, 2.4, false)
		draw_line(shaft_tail - side * 3.5, shaft_tail, ShellThemeScript.AMBER, 2.2, false)
		draw_line(shaft_tail + side * 3.5, shaft_tail, ShellThemeScript.AMBER, 2.2, false)
		draw_colored_polygon(PackedVector2Array([
			projectile_position + aim * 7.0,
			projectile_position - aim * 2.0 + side * 4.5,
			projectile_position - aim * 2.0 - side * 4.5,
		]), ShellThemeScript.AMBER)
		draw_circle(projectile_position + aim * 1.5, 2.0, ShellThemeScript.BONE)

	## The approved ground_refine_v01 sheet as an integer 2x window that covers
	## the arena: a 428x240 crop drawn at exactly 2x, never the full 1024px sheet
	## squeezed into 856px. The flat field colour underneath is kept as the slate
	## fallback the pending state shows.
	func _draw_ground() -> void:
		if not art_ready():
			return
		var ground: Dictionary = art.ground_sprite()
		var texture: Texture2D = ground.get("_texture")
		if texture == null:
			return
		var crop: Rect2i = art.ground_crop_rect(Vector2i(ARENA_SIZE))
		if crop.size == Vector2i.ZERO:
			return
		draw_texture_rect_region(texture, Rect2(Vector2.ZERO, Vector2(crop.size) * float(TutorialArtScript.SCALE)), Rect2(crop))

	func _draw_hero() -> void:
		## No stand-in body: a pending ranger cell is reported as ASSETS PENDING and
		## leaves the field empty, while the facing indicator keeps working.
		var sprite: Dictionary = hero_frame if not hero_frame.is_empty() else (_hero_frame() if art_ready() else {})
		var texture: Texture2D = sprite.get("texture", sprite.get("_texture"))
		if texture != null:
			_draw_ellipse(hero_position + Vector2(0.0, 3.0), Vector2(21.0, 7.0), Color(0.0, 0.0, 0.0, 0.5))
			draw_texture_rect_region(texture, _sprite_dest(hero_position, sprite), Rect2(sprite.get("rect")))
		draw_line(hero_position, hero_position + hero_facing * 25.0, ShellThemeScript.AMBER, 3.0)

	## The shared action frame while the published action atlas is in hand, and
	## the approved four-way static idle cell otherwise. The reader always flags
	## that fallback, so this branch is never an unreported substitution.
	func refresh_hero_frame() -> void:
		hero_frame = _hero_frame()


	func _hero_frame() -> Dictionary:
		if not art_ready():
			return {}
		var animation = art.ranger_animation_reader()
		if animation != null and animation.has_real_art():
			var state: Dictionary = ranger_state if not ranger_state.is_empty() else {"facing": hero_facing}
			var frame: Dictionary = animation.resolve(state)
			if not bool(frame.get("fallback", true)):
				return frame
		return art.ranger_sprite(hero_facing)

	func _draw_target() -> void:
		var flash := target_flash_time > 0.0
		## The single melee target keeps its identity: the calibration_v01 melee
		## enemy, never a training-dummy stand-in.
		var sprite: Dictionary = art.target_sprite() if art_ready() else {}
		var texture: Texture2D = sprite.get("_texture")
		if texture != null:
			_draw_ellipse(target_position + Vector2(0.0, 3.0), Vector2(25.0, 8.0), Color(0.0, 0.0, 0.0, 0.45))
			draw_texture_rect_region(texture, _sprite_dest(target_position, sprite), Rect2(sprite.get("rect")), ShellThemeScript.AMBER if flash else Color.WHITE)
		## The aim marker under the target stays procedural: it marks the single
		## legal target even while the sprite is pending, and carries the hit
		## feedback together with the flash tint above it.
		draw_line(target_position + Vector2(-25.0, 30.0), target_position + Vector2(25.0, 30.0), ShellThemeScript.AMBER if flash else ShellThemeScript.WARNING, 4.0)

	## Screen-snapped destination for a cell placed by its foot point. Only the
	## drawn origin is snapped; the caller's simulation coordinates are untouched.
	func _sprite_dest(feet: Vector2, sprite: Dictionary) -> Rect2:
		var cell: Rect2i = sprite.get("rect", Rect2i())
		var anchor: Vector2i = sprite.get("anchor", Vector2i.ZERO)
		var scale := TutorialArtScript.SCALE
		return Rect2(TutorialArtScript.sprite_origin(feet, anchor, scale), Vector2(cell.size) * float(scale))

	func _draw_ellipse(center: Vector2, radii: Vector2, color: Color) -> void:
		var points := PackedVector2Array()
		for index in range(20):
			var angle := TAU * float(index) / 20.0
			points.append(center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
		draw_colored_polygon(points, color)


var _built := false
var _initial_class := "ranger"
var _design_canvas: Control
var _arena: TrainingArenaCanvas
## Validated production art for the arena (TutorialArt). Kept untyped so the
## screen still loads if the helper script is being re-imported.
var _art
var _art_note: Label
var _class_label: Label
var _status_label: Label
var _move_label: Label
var _dodge_label: Label
var _cast_label: Label
var _enter_button: Button
var _hero_position := HERO_START
var _last_direction := Vector2.RIGHT
var _moved_distance := 0.0
var _move_complete := false
var _dodge_complete := false
var _cast_complete := false
var _completed_emitted := false
var _hint_seconds := 0.0
## Presentation clock for the shared ranger reader (a forward-running tick), the
## movement flag of the current input frame, and the per-event sequence numbers
## the action latches key on. None of these feed the checklist or the tuning.
var _anim_seconds := 0.0
var _anim_tick := 0
var _moving := false
var _dodge_events := 0
var _cast_events := 0
var _action_timeline = PlayerActionTimelineScript.new()
var _attack_origins: Dictionary = {}
var _projectile: Dictionary = {}


func _ready() -> void:
	_build_ui()
	_apply_presentation()


func _process(delta: float) -> void:
	if _arena != null and _arena.target_flash_time > 0.0:
		_arena.target_flash_time = maxf(0.0, _arena.target_flash_time - maxf(0.0, delta))
	if _hint_seconds > 0.0:
		_hint_seconds = maxf(0.0, _hint_seconds - maxf(0.0, delta))
		if _hint_seconds <= 0.0:
			_update_checklist()
	_anim_seconds += maxf(0.0, delta)
	_anim_tick = int(_anim_seconds * float(RangerAnimationScript.SIM_TICKS_PER_SECOND))
	_process_tutorial_action_events(_action_timeline.advance(_anim_tick))
	_advance_projectile_to_tick(_anim_tick)
	var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	simulate_move(direction, delta)
	_sync_arena()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if not key_event.pressed or key_event.echo:
			return
		var key := key_event.physical_keycode if key_event.physical_keycode != KEY_NONE else key_event.keycode
		if key == KEY_SHIFT or key == KEY_CTRL:
			request_dodge()
			_mark_input_handled()
		elif key == KEY_SPACE:
			request_cast()
			_mark_input_handled()
	elif event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if not mouse_event.pressed or not _mouse_is_over_arena(mouse_event.position):
			return
		if mouse_event.button_index == MOUSE_BUTTON_RIGHT:
			request_dodge()
			_mark_input_handled()
		elif mouse_event.button_index == MOUSE_BUTTON_LEFT:
			_attempt_pointer_cast(mouse_event.position)
			_mark_input_handled()


func present(initial_class: String) -> void:
	_initial_class = initial_class
	if _built:
		_apply_presentation()


func simulate_move(direction: Vector2, delta: float) -> void:
	if not _built or delta <= 0.0:
		return
	var movement := direction.limit_length(1.0)
	if movement.length_squared() <= 0.0001:
		_moving = false
		_sync_arena()
		return
	_moving = true
	var action_phase: String = _action_timeline.phase_at(_anim_tick)
	var action_speed_scale := 0.38 if action_phase == PlayerActionTimelineScript.PHASE_WINDUP else (0.72 if action_phase == PlayerActionTimelineScript.PHASE_RECOVERY else 1.0)
	var previous := _hero_position
	_hero_position += movement * MOVE_SPEED * action_speed_scale * delta
	_hero_position.x = clampf(_hero_position.x, PLAYABLE_BOUNDS.position.x, PLAYABLE_BOUNDS.end.x)
	_hero_position.y = clampf(_hero_position.y, PLAYABLE_BOUNDS.position.y, PLAYABLE_BOUNDS.end.y)
	_last_direction = movement.normalized()
	_moved_distance += previous.distance_to(_hero_position)
	_move_complete = _moved_distance >= MOVE_REQUIRED_DISTANCE
	_sync_arena()
	_update_checklist()


func request_dodge(direction: Vector2 = Vector2.ZERO) -> bool:
	if not _built:
		return false
	var dodge_direction := direction.limit_length(1.0)
	if dodge_direction.length_squared() <= 0.0001:
		dodge_direction = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if dodge_direction.length_squared() <= 0.0001:
		dodge_direction = _last_direction
	dodge_direction = dodge_direction.normalized()
	var previous := _hero_position
	_hero_position = _clamp_to_bounds(_hero_position + dodge_direction * DODGE_DISTANCE)
	if previous.distance_to(_hero_position) < DODGE_DISTANCE * 0.5:
		dodge_direction = -dodge_direction
		_hero_position = _clamp_to_bounds(previous + dodge_direction * DODGE_DISTANCE)
	if previous.distance_to(_hero_position) < DODGE_DISTANCE * 0.5:
		return false
	_last_direction = dodge_direction
	_process_tutorial_action_events((_action_timeline.interrupt(_anim_tick, "dodge").get("events", []) as Array))
	_dodge_complete = true
	_dodge_events += 1
	_latch_ranger_event(EVENT_DODGE, "ranger:dodge:%d" % _dodge_events)
	_sync_arena()
	_update_checklist()
	return true


func request_cast() -> bool:
	if not _built or _hero_position.distance_to(TARGET_POSITION) > CAST_RANGE:
		if _status_label != null:
			_status_label.text = "Out of range: move right toward the training target, then try again."
		return false
	_last_direction = _hero_position.direction_to(TARGET_POSITION)
	_process_tutorial_action_events(_action_timeline.advance(_anim_tick))
	var receipt: Dictionary = _action_timeline.request_attack(_anim_tick, 1, _last_direction, _anim_tick)
	if not bool(receipt.get("accepted", false)):
		if _status_label != null:
			_status_label.text = "Recovering from the shot. Wait a moment before firing."
		return false
	## A successful shot is a newer intent than any standing input hint; the
	## windup status below must replace it immediately.
	_hint_seconds = 0.0
	_process_tutorial_action_events(_action_timeline.advance(_anim_tick))
	if String(receipt.get("status", "")) in ["buffered", "replaced"] and _status_label != null:
		_status_label.text = "Next arrow queued."
	_sync_arena()
	_update_checklist()
	return true


## Manual-combat-aligned pointer shot. The click must pick the real target
## anchor; empty ground never casts and answers with one short, expiring hint.
func _attempt_pointer_cast(viewport_position: Vector2) -> void:
	var local_position := viewport_position
	if _design_canvas != null:
		local_position = _design_canvas.get_global_transform_with_canvas().affine_inverse() * viewport_position
	pointer_cast_at_arena(local_position - ARENA_ORIGIN)


## Arena-space picking half, kept public for input regressions. The return
## value names why a click did nothing; the player-visible result is the cast
## itself or the expiring hint.
func pointer_cast_at_arena(arena_position: Vector2) -> Dictionary:
	if not _pointer_hits_target(arena_position):
		_show_hint("Missed the training target · Click its circle, or press Space for aim assist")
		return {"accepted": false, "reason": "empty"}
	if request_cast():
		return {"accepted": true, "reason": "hit"}
	return {"accepted": false, "reason": "range"}


func _pointer_hits_target(arena_position: Vector2) -> bool:
	return arena_position.distance_to(TARGET_POSITION + TARGET_PICK_ANCHOR_OFFSET) <= TARGET_PICK_RADIUS


func _show_hint(text_value: String) -> void:
	if _status_label != null:
		_status_label.text = text_value
	_hint_seconds = HINT_DURATION_SECONDS


func current_status_text() -> String:
	return _status_label.text if _status_label != null else ""


func hint_active() -> bool:
	return _hint_seconds > 0.0


func _process_tutorial_action_events(events: Array) -> void:
	for value: Variant in events:
		if not value is Dictionary:
			continue
		var event: Dictionary = value
		match String(event.get("type", "")):
			"action_started":
				_cast_events += 1
				var action_id := int(event.get("action_instance_id", 0))
				var facing := RangerAnimationScript.facing_key(_last_direction)
				var release_frame := RangerAnimationScript.shoot_frame_at_tick(PlayerActionTimelineScript.WINDUP_TICKS)
				## Tutorial coordinates draw source pixels at 2x, hence 0.5 source
				## pixels per arena unit in the shared socket conversion helper.
				var origin := _hero_position + RangerAnimationScript.arrow_attachment_offset(
					facing,
					release_frame,
					1.0 / float(TutorialArtScript.SCALE)
				)
				var direction := origin.direction_to(TARGET_POSITION)
				if direction == Vector2.ZERO:
					direction = _last_direction.normalized() if _last_direction != Vector2.ZERO else Vector2.RIGHT
				_attack_origins[action_id] = {
					"origin": origin,
					"direction": direction,
					"facing": facing,
					"release_frame": release_frame,
				}
				_latch_ranger_event(EVENT_CAST, "ranger:cast:%d:action:%d" % [_cast_events, int(event.get("action_instance_id", 0))])
				if _status_label != null:
					_status_label.text = "Drawing the bow. Wait for the arrow to fire."
			"action_impact":
				_release_projectile(event)
			"action_interrupted":
				_attack_origins.erase(int(event.get("action_instance_id", 0)))
				if _status_label != null:
					_status_label.text = "Dodging interrupted the draw. Steady yourself and try again."
			"action_ended":
				_attack_origins.erase(int(event.get("action_instance_id", 0)))


func _release_projectile(event: Dictionary) -> void:
	var action_id := int(event.get("action_instance_id", 0))
	var release: Dictionary = _attack_origins.get(action_id, {})
	var origin: Vector2 = release.get("origin", _hero_position)
	var direction: Vector2 = release.get("direction", origin.direction_to(TARGET_POSITION))
	if direction.length_squared() <= 0.000001:
		direction = Vector2.RIGHT
	_projectile = {
		"active": true,
		"action_instance_id": action_id,
		"spawned_tick": int(event.get("tick", _anim_tick)),
		"last_tick": int(event.get("tick", _anim_tick)),
		"origin": origin,
		"previous_position": origin,
		"position": origin,
		"direction": direction.normalized(),
		"speed": PROJECTILE_SPEED,
		"distance_travelled": 0.0,
		"facing": String(release.get("facing", RangerAnimationScript.facing_key(_last_direction))),
		"release_frame": int(release.get("release_frame", RangerAnimationScript.shoot_frame_at_tick(PlayerActionTimelineScript.WINDUP_TICKS))),
	}


func _advance_projectile_to_tick(target_tick: int) -> void:
	if _projectile.is_empty() or not bool(_projectile.get("active", false)):
		return
	while bool(_projectile.get("active", false)) and int(_projectile.get("last_tick", target_tick)) < target_tick:
		var next_tick := int(_projectile["last_tick"]) + 1
		_advance_projectile_tick(next_tick)


func _advance_projectile_tick(tick: int) -> void:
	var start: Vector2 = _projectile.get("position", Vector2.ZERO)
	var direction: Vector2 = _projectile.get("direction", Vector2.RIGHT)
	var remaining := maxf(0.0, CAST_RANGE - float(_projectile.get("distance_travelled", 0.0)))
	var step := minf(PROJECTILE_SPEED / float(RangerAnimationScript.SIM_TICKS_PER_SECOND), remaining)
	var finish := start + direction * step
	_projectile["previous_position"] = start
	_projectile["last_tick"] = tick
	var contact: Variant = _swept_circle_contact(start, finish, TARGET_POSITION, TARGET_CONTACT_RADIUS + PROJECTILE_RADIUS)
	if contact != null:
		var point := contact as Vector2
		_projectile["position"] = point
		_projectile["distance_travelled"] = (_projectile.get("origin", point) as Vector2).distance_to(point)
		_projectile["active"] = false
		_projectile["contact_tick"] = tick
		_projectile["contact_position"] = point
		_cast_complete = true
		if _arena != null:
			_arena.target_flash_time = TRACE_DURATION
		_update_checklist()
		return
	_projectile["position"] = finish
	_projectile["distance_travelled"] = float(_projectile.get("distance_travelled", 0.0)) + step
	if step <= 0.0 or float(_projectile["distance_travelled"]) >= CAST_RANGE:
		_projectile["active"] = false
		_projectile["miss_tick"] = tick


## First contact of a moving circle against the stationary target circle.
## Returning the entry point, rather than only a boolean, keeps the final fixed
## tick position deterministic even when one step crosses the whole boundary.
func _swept_circle_contact(start: Vector2, finish: Vector2, center: Vector2, radius: float) -> Variant:
	var segment := finish - start
	var segment_length := segment.length()
	if segment_length <= 0.0:
		return start if start.distance_squared_to(center) <= radius * radius else null
	var aim := segment / segment_length
	var projection := (center - start).dot(aim)
	var perpendicular_squared := (center - start).length_squared() - projection * projection
	var radius_squared := radius * radius
	if perpendicular_squared > radius_squared:
		return null
	var reach := sqrt(maxf(0.0, radius_squared - perpendicular_squared))
	var contact_distance := projection - reach
	var exit_distance := projection + reach
	if exit_distance < 0.0 or contact_distance > segment_length:
		return null
	return start + aim * clampf(contact_distance, 0.0, segment_length)


func get_checklist_snapshot() -> Dictionary:
	return {
		"move": _move_complete,
		"dodge": _dodge_complete,
		"cast_hit": _cast_complete,
		"moved_distance": _moved_distance,
		"all_complete": _all_complete(),
	}


## Read-only copy of the tutorial projectile authority for deterministic tests
## and diagnostics. Callers cannot mutate the live flight through this snapshot.
func get_projectile_snapshot() -> Dictionary:
	if _projectile.is_empty():
		return {"active": false}
	return _projectile.duplicate(true)


func get_player_position() -> Vector2:
	return _hero_position


func set_player_position(position: Vector2) -> void:
	_hero_position = _clamp_to_bounds(position)
	_sync_arena()


func get_target_position() -> Vector2:
	return TARGET_POSITION


func is_enter_enabled() -> bool:
	return _enter_button != null and not _enter_button.disabled


func _build_ui() -> void:
	if _built:
		return
	_built = true
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	## The screen itself stays transparent to mouse picks: with the default STOP
	## it consumed every arena click at the subviewport's GUI stage, and
	## _unhandled_input never saw it. The Enter button keeps its own hit area.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = ShellThemeScript.create()

	var background := ColorRect.new()
	background.color = ShellThemeScript.INK
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	_design_canvas = Control.new()
	_design_canvas.name = "TutorialDesignCanvas"
	_design_canvas.custom_minimum_size = DESIGN_SIZE
	_design_canvas.size = DESIGN_SIZE
	_design_canvas.clip_contents = true
	## Full-screen STOP here consumed arena clicks before _unhandled_input.
	_design_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_design_canvas)
	resized.connect(_layout_design_canvas)
	_layout_design_canvas()

	var title := Label.new()
	title.text = "Before Departure · A Bow in the Snow"
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", ShellThemeScript.AMBER)
	_place_control(title, Rect2(32.0, 8.0, 760.0, 42.0))
	_design_canvas.add_child(title)

	_class_label = Label.new()
	_class_label.name = "ClassLabel"
	_class_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_class_label.add_theme_font_size_override("font_size", 18)
	_class_label.add_theme_color_override("font_color", ShellThemeScript.NEUTRAL)
	_place_control(_class_label, Rect2(790.0, 25.0, 458.0, 30.0))
	_design_canvas.add_child(_class_label)

	_arena = TrainingArenaCanvas.new()
	_arena.name = "TrainingArena"
	_arena.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var arena_frame := Control.new()
	arena_frame.name = "ArenaFrame"
	arena_frame.clip_contents = true
	arena_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place_control(arena_frame, Rect2(32.0, 78.0 - HERO_HEADROOM, ARENA_SIZE.x, ARENA_SIZE.y + HERO_HEADROOM))
	_design_canvas.add_child(arena_frame)
	_place_control(_arena, Rect2(0.0, HERO_HEADROOM, ARENA_SIZE.x, ARENA_SIZE.y))
	arena_frame.add_child(_arena)
	_load_tutorial_art()

	var intro := _guide_label("", "The old road is silent. Hearthside needs the old tower's warmth. Practice your bow before setting out.")
	intro.name = "TutorialIntro"
	_place_control(intro, Rect2(32.0, 48.0, 1216.0, 28.0))
	_design_canvas.add_child(intro)
	var guide := VBoxContainer.new()
	guide.name = "ActionGuide"
	_place_control(guide, Rect2(916.0, 90.0, 324.0, 450.0))
	guide.add_theme_constant_override("separation", 20)
	_design_canvas.add_child(guide)
	var heading := Label.new()
	heading.text = "Practice Before Departure"
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	heading.add_theme_font_size_override("font_size", 24)
	heading.add_theme_color_override("font_color", ShellThemeScript.AMBER)
	guide.add_child(heading)
	_move_label = _guide_label("", "")
	guide.add_child(_move_label)
	_dodge_label = _guide_label("", "")
	guide.add_child(_dodge_label)
	_cast_label = _guide_label("", "")
	guide.add_child(_cast_label)
	var rule := Label.new()
	rule.text = "Any order. The target will not attack. An arrow must hit to count."
	rule.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rule.add_theme_font_size_override("font_size", 18)
	rule.add_theme_color_override("font_color", ShellThemeScript.NEUTRAL)
	guide.add_child(rule)

	_status_label = Label.new()
	_status_label.text = "First, move right toward the training target."
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_font_size_override("font_size", 20)
	_status_label.add_theme_color_override("font_color", ShellThemeScript.PROXY)
	_place_control(_status_label, Rect2(32.0, 574.0, 856.0, 54.0))
	_design_canvas.add_child(_status_label)

	_enter_button = Button.new()
	_enter_button.name = "EnterBaseButton"
	_enter_button.text = "Complete All Three Exercises"
	_enter_button.disabled = true
	_enter_button.custom_minimum_size.y = 58.0
	_enter_button.pressed.connect(_on_completed_pressed)
	_place_control(_enter_button, Rect2(908.0, 580.0, 340.0, 58.0))
	_design_canvas.add_child(_enter_button)

	## Only readable while the arena art is not fully published: the screen says so
	## instead of quietly pretending the approved art is in place.
	_art_note = Label.new()
	_art_note.name = "TutorialArtNote"
	_art_note.text = ""
	_art_note.visible = false
	_art_note.add_theme_font_size_override("font_size", ShellThemeScript.MIN_FONT_SIZE)
	_art_note.add_theme_color_override("font_color", ShellThemeScript.WARNING)
	_place_control(_art_note, Rect2(32.0, 632.0, 856.0, 26.0))
	_design_canvas.add_child(_art_note)

	_sync_arena()
	_update_checklist()


func _guide_label(title_text: String, instructions: String) -> Label:
	var label := Label.new()
	label.text = instructions if title_text.is_empty() else "%s\n%s" % [title_text, instructions]
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.y = 0.0
	label.add_theme_font_size_override("font_size", 18)
	return label


func _load_tutorial_art() -> void:
	_art = TutorialArtScript.new()
	if _arena != null:
		_arena.art = _art
	if not _art.has_real_art():
		for reason: String in _art.pending_reasons:
			printerr("ASSETS PENDING p1_tutorial_art_v02: " + reason)
	_sync_art_note()


func _sync_art_note() -> void:
	if _art_note == null:
		return
	var pending: bool = _art == null or not _art.has_real_art()
	_art_note.visible = pending
	_art_note.text = "ASSETS PENDING: tutorial artwork is not ready; this area shows gameplay placeholders." if pending else ""


## The validated arena art, for tests and for the graphics check.
func get_art():
	return _art


func get_arena() -> Control:
	return _arena


func art_pending_reasons() -> Array[String]:
	if _art == null:
		return ["ASSETS PENDING p1_tutorial_art_v02: no art loader"]
	return _art.pending_reasons


## The ranger action atlas is reported on its own: while it is pending or broken
## the arena keeps drawing the approved four-way idle cell, and this is what says
## so. It is deliberately not folded into art_pending_reasons(), which describes
## the three approved roles of this landing pass.
func ranger_action_pending_reasons() -> Array[String]:
	if _art == null:
		return ["ASSETS PENDING: no ranger action reader"]
	return _art.ranger_action_pending_reasons()


## Tests and the graphics check: the exact trigger fields the arena is drawing.
func get_ranger_animation_state() -> Dictionary:
	return _ranger_animation_state()


## Runtime integration diagnostic for the art pass: the frame the drill is
## drawing the hero from, plus the last latched action token and its time.
func get_ranger_animation_report() -> Dictionary:
	var report := {"pending_reason": "", "state": _ranger_animation_state()}
	var animation = _ranger_animation_reader()
	if animation != null:
		report["reader"] = animation.integration_report()
		report["pending_reason"] = animation.pending_reason()
	return report


## Tests only: swap the arena art (including a deliberately broken loader) and
## let the screen report the resulting state the same way it would at startup.
func apply_art_for_test(art) -> void:
	_art = art
	if _arena != null:
		_arena.art = art
	_sync_art_note()
	_sync_arena()


func _apply_presentation() -> void:
	# Only Ranger is playable in this slice; do not expose placeholder class copy.
	_class_label.text = "Ranger"


func _layout_design_canvas() -> void:
	if _design_canvas == null:
		return
	var canvas_scale := minf(size.x / DESIGN_SIZE.x, size.y / DESIGN_SIZE.y)
	if canvas_scale <= 0.0:
		return
	_design_canvas.scale = Vector2.ONE * canvas_scale
	_design_canvas.position = (size - DESIGN_SIZE * canvas_scale) * 0.5


func _sync_arena() -> void:
	if _arena == null:
		return
	_arena.hero_position = _hero_position
	_arena.hero_facing = _last_direction
	_arena.projectile_active = bool(_projectile.get("active", false))
	_arena.projectile_previous_position = _projectile.get("previous_position", Vector2.ZERO)
	_arena.projectile_position = _projectile.get("position", Vector2.ZERO)
	_arena.projectile_direction = _projectile.get("direction", Vector2.RIGHT)
	_arena.ranger_state = _ranger_animation_state()
	_arena.refresh_hero_frame()
	_arena.queue_redraw()


## The reader's trigger contract, filled from the drill's own presentation clock.
## The drill has one target and no damage, so hit and death stay off; the
## checklist, the bounds and every tuning value are untouched by this.
func _ranger_animation_state() -> Dictionary:
	var action_snapshot: Dictionary = _action_timeline.snapshot()
	var active_action: Dictionary = action_snapshot.get("active", {})
	var shoot_ticks := -1
	if not active_action.is_empty():
		shoot_ticks = maxi(0, _anim_tick - int(active_action.get("start_tick", _anim_tick)))
	var state := {
		"facing": _last_direction,
		"moving": _moving,
		"phase_ticks": _anim_tick,
		"hit_ticks": -1,
		"dodge_ticks": -1,
		"shoot_ticks": shoot_ticks,
		"shoot_window_ticks": PlayerActionTimelineScript.WINDUP_TICKS + PlayerActionTimelineScript.RECOVERY_TICKS,
		"tick": _anim_tick,
	}
	var animation = _ranger_animation_reader()
	if animation == null:
		return state
	state["dodge_ticks"] = animation.latched_ticks(EVENT_DODGE, _anim_tick)
	return state


func _ranger_animation_reader():
	if _art == null:
		return null
	return _art.ranger_animation_reader()


## One latch per dodge / cast. Repeating the request, or drawing the arena again,
## can never restart a clip that is already playing.
func _latch_ranger_event(kind: String, event_id: String) -> void:
	var animation = _ranger_animation_reader()
	if animation == null:
		return
	animation.latch_event(kind, event_id, _anim_tick)


func _update_checklist() -> void:
	if not _built or _enter_button == null:
		return
	## An active hint is the newest player-facing fact; checklist refreshes
	## (movement, phases) must not erase it mid-sentence for up to 1.4 s.
	if _hint_seconds > 0.0:
		return
	_move_label.text = "%s Approach the training target\n%s" % [_mark(_move_complete), "Movement practiced" if _move_complete else "WASD / Arrow keys · Walk through the snow"]
	_dodge_label.text = "%s Try a dodge\n%s" % [_mark(_dodge_complete), "Dodge complete" if _dodge_complete else "Shift / Ctrl / Right-click · Dodge away"]
	_cast_label.text = "%s Hit with Piercing Arrow\n%s" % [_mark(_cast_complete), "Arrow hit the training target" if _cast_complete else "Space Aim assist · Left-click the target to shoot"]
	var was_locked := _enter_button.disabled
	_enter_button.disabled = not _all_complete()
	_enter_button.text = "Enter Hearthside" if _all_complete() else "Complete All Three Exercises"
	if _all_complete():
		_status_label.text = "Practice complete. Your bow and footing are ready. Head into Hearthside for a rest."
		if was_locked:
			_enter_button.grab_focus()
	elif _action_timeline.phase_at(_anim_tick) == PlayerActionTimelineScript.PHASE_WINDUP:
		_status_label.text = "Drawing the bow. Wait for the shot; dodging will interrupt it."
	elif _action_timeline.phase_at(_anim_tick) == PlayerActionTimelineScript.PHASE_RECOVERY:
		_status_label.text = "Recovering from the shot. You can fire again shortly."
	elif not _cast_complete:
		_status_label.text = "In range. Try a shot; the target flashes when hit." if _hero_position.distance_to(TARGET_POSITION) <= CAST_RANGE else "Out of range: move right toward the target, inside its cyan ring."
	elif not _dodge_complete:
		_status_label.text = "A hit! Now try dodging to practice getting clear."
	else:
		_status_label.text = "Hit and dodge complete. Walk a little farther to practice movement."


func _mark(done: bool) -> String:
	return "✓" if done else "□"


func _all_complete() -> bool:
	return _move_complete and _dodge_complete and _cast_complete


func _clamp_to_bounds(position: Vector2) -> Vector2:
	return Vector2(
		clampf(position.x, PLAYABLE_BOUNDS.position.x, PLAYABLE_BOUNDS.end.x),
		clampf(position.y, PLAYABLE_BOUNDS.position.y, PLAYABLE_BOUNDS.end.y)
	)


func _mouse_is_over_arena(viewport_position: Vector2) -> bool:
	if _design_canvas == null:
		return false
	var local_position := _design_canvas.get_global_transform_with_canvas().affine_inverse() * viewport_position
	return Rect2(ARENA_ORIGIN, ARENA_SIZE).has_point(local_position)


func _mark_input_handled() -> void:
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()


func _on_completed_pressed() -> void:
	if not _all_complete() or _completed_emitted:
		return
	_completed_emitted = true
	completed.emit()


func _place_control(control: Control, rect: Rect2) -> void:
	control.position = rect.position
	control.size = rect.size
	control.custom_minimum_size = rect.size
