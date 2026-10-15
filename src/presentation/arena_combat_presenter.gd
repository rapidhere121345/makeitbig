class_name ArenaCombatPresenter
extends RefCounted

## Read-only projection for combat overlays.
##
## Main owns the authoritative snapshot and the order in which the canvas
## transforms are applied. This service owns the drawing rules for telegraphs,
## movement-boundary guides, projectiles, transient feedback and target markers.
## It never advances a clock, resolves a query, mutates an actor,
## or corrects a gameplay position.

const ArenaWorldViewScript := preload("res://src/presentation/arena_world_view.gd")
const CombatMarksScript := preload("res://src/presentation/combat_marks.gd")
const PaletteScript := preload("res://src/presentation/combat_palette.gd")
const EnemyTacticsScript := preload("res://src/systems/enemy_tactics.gd")
const ArenaGeometryScript := preload("res://src/runtime/geometry/arena_geometry.gd")
const RoomCatalogScript := preload("res://src/runtime/world/room_catalog.gd")

const FRAME_KEYS := {
	"presentation_enabled": "bool",
	"in_arena": "bool",
	"arena_rect": "Rect2",
	"layout_id": "String",
	"walkable_geometry": "Dictionary",
	"sim_tick": "int",
	"player_position": "Vector2",
	"player_facing": "Vector2",
	"enemies": "Array",
	"hazard_states": "Array",
	"projectiles": "Array",
	"traces": "Array",
	"combat_feedback_marks": "Array",
	"player_damage_overlay": "Dictionary",
	"dash_remaining_ticks": "int",
	"dash_direction": "Vector2",
	"dodge_remaining_ticks": "int",
	"dash_step": "float",
	"attack_target_ui": "Dictionary",
	"marked_enemy": "CombatEnemyState or null",
	"marked_expires_tick": "int",
	"font": "Font or null",
}

const OPTIONAL_FRAME_KEYS := {
	"presentation_geometry": "Dictionary",
}

const COLOR_INK: Color = PaletteScript.INK
const COLOR_NEUTRAL: Color = PaletteScript.SLATE_3
const COLOR_BONE: Color = PaletteScript.BONE
const COLOR_AMBER: Color = PaletteScript.COPPER
const COLOR_BLOOD: Color = PaletteScript.DANGER
const COLOR_WARNING: Color = PaletteScript.DANGER_BRIGHT
const COLOR_PROXY: Color = PaletteScript.COLD
const COLOR_ANOMALY: Color = PaletteScript.PURPLE
const COMBAT_FEEDBACK_LIFETIME_SECONDS: float = 0.72
const COMBAT_SPARK_LIFETIME_SECONDS: float = 0.15
const COMBAT_FEEDBACK_TEXT_FONT_SIZE: int = 14
const PLAYER_DAMAGE_OVERLAY_TICKS: int = 6
const POINTER_STATUS_OUT_OF_RANGE := "out_of_range"
const ATTACK_SOURCE_ASSISTED := "assisted"
const ATTACK_SOURCE_POINTER := "pointer"

var _last_report: Dictionary = {}
var _room_catalog: RefCounted


func _init() -> void:
	_room_catalog = RoomCatalogScript.new()


func contract_report() -> Dictionary:
	return {
		"frame_keys": FRAME_KEYS.duplicate(true),
		"optional_frame_keys": OPTIONAL_FRAME_KEYS.duplicate(true),
		"authority": "parent-owned read-only frame",
		"canvas_owner": "caller owns transform order and draw target",
		"draw_layers": ["ground_telegraphs", "world_target_markers", "combat_overlays"],
		"writes_gameplay_state": false,
		"fallback_art": false,
	}


func presentation_report() -> Dictionary:
	return _last_report.duplicate(true)


func validate_frame(frame: Dictionary) -> String:
	for key in FRAME_KEYS:
		if not frame.has(key):
			return "frame missing required key: %s" % key
	if not frame["presentation_enabled"] is bool:
		return "frame key presentation_enabled must be bool"
	if not frame["in_arena"] is bool:
		return "frame key in_arena must be bool"
	if not frame["arena_rect"] is Rect2:
		return "frame key arena_rect must be Rect2"
	if not frame["layout_id"] is String:
		return "frame key layout_id must be String"
	var arena_rect: Rect2 = frame["arena_rect"]
	if not arena_rect.position.is_finite() or not arena_rect.size.is_finite() or arena_rect.size.x <= 0.0 or arena_rect.size.y <= 0.0:
		return "frame key arena_rect must be a finite positive rect"
	var layout_id := String(frame["layout_id"]).strip_edges()
	if layout_id.is_empty() or _room_catalog == null or not bool(_room_catalog.resolve({"layout_id": layout_id}).get("ok", false)):
		return "unknown_layout_id:%s" % layout_id
	if not frame["walkable_geometry"] is Dictionary:
		return "frame key walkable_geometry must be Dictionary"
	if not frame["sim_tick"] is int:
		return "frame key sim_tick must be int"
	if int(frame["sim_tick"]) < 0:
		return "frame key sim_tick must be non-negative"
	if not frame["player_position"] is Vector2:
		return "frame key player_position must be Vector2"
	if not frame["player_facing"] is Vector2:
		return "frame key player_facing must be Vector2"
	if not (frame["player_position"] as Vector2).is_finite() or not (frame["player_facing"] as Vector2).is_finite():
		return "frame key player position/facing must be finite"
	if not frame["enemies"] is Array:
		return "frame key enemies must be Array"
	if not frame["hazard_states"] is Array:
		return "frame key hazard_states must be Array"
	if not frame["projectiles"] is Array:
		return "frame key projectiles must be Array"
	if not frame["traces"] is Array:
		return "frame key traces must be Array"
	if not frame["combat_feedback_marks"] is Array:
		return "frame key combat_feedback_marks must be Array"
	if not frame["player_damage_overlay"] is Dictionary:
		return "frame key player_damage_overlay must be Dictionary"
	for key in ["dash_remaining_ticks", "dodge_remaining_ticks", "marked_expires_tick"]:
		if not frame[key] is int:
			return "frame key %s must be int" % key
	if not frame["dash_direction"] is Vector2:
		return "frame key dash_direction must be Vector2"
	if not (frame["dash_direction"] as Vector2).is_finite():
		return "frame key dash_direction must be finite"
	if not frame["dash_step"] is float and not frame["dash_step"] is int:
		return "frame key dash_step must be numeric"
	if not is_finite(float(frame["dash_step"])) or float(frame["dash_step"]) < 0.0:
		return "frame key dash_step must be finite and non-negative"
	if not frame["attack_target_ui"] is Dictionary:
		return "frame key attack_target_ui must be Dictionary"
	for counter_key: String in ["dash_remaining_ticks", "dodge_remaining_ticks", "marked_expires_tick"]:
		if int(frame[counter_key]) < 0:
			return "frame key %s must be non-negative" % counter_key
	var marked_enemy: Variant = frame["marked_enemy"]
	if marked_enemy != null and not marked_enemy is CombatEnemyState:
		return "frame key marked_enemy must be CombatEnemyState or null"
	for enemy_value: Variant in frame["enemies"]:
		if not enemy_value is CombatEnemyState:
			return "frame enemies must contain CombatEnemyState values"
		var enemy: CombatEnemyState = enemy_value
		if enemy.entity_id <= 0 or not enemy.position.is_finite() or not enemy.facing.is_finite() \
			or not is_finite(enemy.health) or not is_finite(enemy.maximum_health):
			return "frame enemy state is invalid"
	for hazard_value: Variant in frame["hazard_states"]:
		if not hazard_value is Dictionary:
			return "frame hazard_states must contain Dictionary values"
		var hazard: Dictionary = hazard_value
		for vector_key: String in ["origin", "direction"]:
			if hazard.has(vector_key) and not hazard[vector_key] is Vector2:
				return "frame hazard %s must be Vector2" % vector_key
			if hazard.has(vector_key) and not (hazard[vector_key] as Vector2).is_finite():
				return "frame hazard %s must be finite" % vector_key
	for projectile_value: Variant in frame["projectiles"]:
		if not projectile_value is CombatArrowProjectile:
			return "frame projectiles must contain CombatArrowProjectile values"
	for trace_value: Variant in frame["traces"]:
		if not trace_value is CombatArrowTrace:
			return "frame traces must contain CombatArrowTrace values"
	for mark_value: Variant in frame["combat_feedback_marks"]:
		if not mark_value is Dictionary:
			return "frame combat_feedback_marks must contain Dictionary values"
	if frame["font"] != null and not frame["font"] is Font:
		return "frame key font must be Font or null"
	if bool(frame["in_arena"]):
		var normalized := ArenaGeometryScript.normalize(frame["walkable_geometry"])
		if not bool(normalized.get("ok", false)):
			return "frame key walkable_geometry invalid:%s" % String(normalized.get("error", "unknown"))
		var expected_kind := ArenaGeometryScript.expected_kind_for_layout(layout_id)
		var actual_kind := String((normalized.get("value", {}) as Dictionary).get("kind", ""))
		if expected_kind.is_empty() or actual_kind != expected_kind:
			return "frame key walkable_geometry layout mismatch"
		var bounds: Rect2 = (normalized["value"] as Dictionary)["bounds"]
		var padding := bounds.position.x - arena_rect.position.x
		if padding < 0.0 or not bounds.grow(padding).is_equal_approx(arena_rect):
			return "frame key walkable_geometry arena mismatch"
		if frame.has("presentation_geometry"):
			if not frame["presentation_geometry"] is Dictionary:
				return "frame key presentation_geometry must be Dictionary"
			var presentation := ArenaGeometryScript.normalize(frame["presentation_geometry"])
			if not bool(presentation.get("ok", false)):
				return "frame key presentation_geometry invalid:%s" % String(presentation.get("error", "unknown"))
			var presentation_value: Dictionary = presentation["value"]
			if String(presentation_value.get("kind", "")) != expected_kind:
				return "frame key presentation_geometry layout mismatch"
			if not (presentation_value["bounds"] as Rect2).is_equal_approx(arena_rect):
				return "frame key presentation_geometry arena mismatch"
	return ""


func draw_ground(canvas: CanvasItem, frame: Dictionary) -> void:
	if canvas == null or not _frame_is_drawable(frame):
		return
	_draw_walkable_layout_boundaries(canvas, frame)
	var active_ticks := maxi(1, int(frame.get("charge_active_ticks", 10)))
	for enemy: CombatEnemyState in frame["enemies"]:
		if enemy.is_boss:
			_draw_boss_transition_rings(canvas, enemy, int(frame["sim_tick"]))
			_draw_boss_target_shape(canvas, enemy)
		else:
			_draw_normal_target_shape(canvas, enemy, active_ticks)
	for hazard: Dictionary in frame["hazard_states"]:
		_draw_hazard(canvas, hazard)
	_record_report(frame, "ground")


func draw_overlays(canvas: CanvasItem, frame: Dictionary, world_view: RefCounted) -> void:
	if canvas == null or world_view == null or not _frame_is_drawable(frame):
		return
	_draw_player_status_overlay(canvas, frame, world_view)
	_draw_piercing_projectiles(canvas, frame)
	for trace: CombatArrowTrace in frame["traces"]:
		var alpha: float = clampf(trace.remaining / 0.18, 0.0, 1.0)
		var direction := (trace.to - trace.from).normalized()
		var start := trace.to - direction * minf(10.0, trace.from.distance_to(trace.to))
		canvas.draw_line(start, trace.to, Color(COLOR_AMBER, alpha * 0.55), 1.2, false)
	_draw_combat_feedback_marks(canvas, frame)
	_record_report(frame, "overlays")


func draw_target_indicators(canvas: CanvasItem, frame: Dictionary, world_view: RefCounted) -> void:
	## These indicators are authored in world space. The caller must invoke this
	## pass under world_view.world_transform(), before gameplay overlays.
	if canvas == null or world_view == null or not _frame_is_drawable(frame):
		return
	_draw_mark_indicator(canvas, frame, world_view)
	_draw_pointer_target_indicator(canvas, frame, world_view)
	_record_report(frame, "world_target_markers")


func _frame_is_drawable(frame: Dictionary) -> bool:
	var error := validate_frame(frame)
	if not error.is_empty():
		_last_report = {
			"state": "presentation_error",
			"error": error,
			"contract": contract_report(),
		}
		return false
	if not bool(frame["presentation_enabled"]) or not bool(frame["in_arena"]):
		_record_report(frame, "disabled")
		return false
	return true


func _record_report(frame: Dictionary, pass_name: String) -> void:
	_last_report = {
		"state": "disabled" if pass_name == "disabled" else "ready",
		"pass": pass_name,
		"sim_tick": int(frame.get("sim_tick", 0)),
		"enemy_count": (frame.get("enemies", []) as Array).size(),
		"projectile_count": (frame.get("projectiles", []) as Array).size(),
		"trace_count": (frame.get("traces", []) as Array).size(),
		"feedback_count": (frame.get("combat_feedback_marks", []) as Array).size(),
		"contract": contract_report(),
	}


func _draw_walkable_layout_boundaries(canvas: CanvasItem, frame: Dictionary) -> void:
	var arena: Rect2 = frame["arena_rect"]
	var geometry: Dictionary = frame.get("presentation_geometry", frame["walkable_geometry"])
	if geometry.is_empty():
		return
	var bounds: Rect2 = geometry["bounds"]
	var edge := Color(COLOR_NEUTRAL, 0.60)
	match String(frame["layout_id"]):
		"ring":
			var center: Vector2 = geometry.get("center", bounds.get_center())
			var inner_radius := float(geometry.get("inner_radius", 0.0))
			var outer_radius := float(geometry.get("outer_radius", 0.0))
			if inner_radius > 0.0 and outer_radius > inner_radius:
				canvas.draw_arc(center, inner_radius, 0.0, TAU, 96, edge, 1.5, false)
				canvas.draw_arc(center, outer_radius, 0.0, TAU, 96, edge, 1.5, false)
		"corridor":
			var half_height := float(geometry.get("corridor_half_height", 0.0))
			for sign_value in [-1.0, 1.0]:
				var y: float = bounds.get_center().y + half_height * sign_value
				var x := bounds.position.x
				while x < bounds.end.x:
					canvas.draw_line(Vector2(x, y), Vector2(minf(x + 18.0, bounds.end.x), y), edge, 1.5, false)
					x += 32.0


func _draw_hazard(canvas: CanvasItem, state: Dictionary) -> void:
	var phase := String(state.get("phase", "warning"))
	var color := Color(COLOR_WARNING, 0.20 if phase == "warning" else (0.58 if phase == "active" else 0.10))
	if String(state.get("id", "")) == "moving_fireline":
		var line_color := Color(COLOR_NEUTRAL, 0.18) if phase == "recovery" else color
		_draw_lane_shape(canvas, state.get("origin", Vector2.ZERO), state.get("direction", Vector2.RIGHT), float(state.get("length", 0.0)), float(state.get("width", 0.0)), line_color, phase == "active", phase == "warning")
	else:
		var origin: Vector2 = state.get("origin", Vector2.ZERO)
		var radius := float(state.get("radius", 0.0))
		canvas.draw_circle(origin, radius, color)
		canvas.draw_arc(origin, radius, 0.0, TAU, 32, COLOR_WARNING if phase != "recovery" else COLOR_NEUTRAL, 2.0)


func _draw_normal_target_shape(canvas: CanvasItem, enemy: CombatEnemyState, active_ticks: int) -> void:
	if enemy.action_state not in ["windup", "active"]:
		return
	var color := Color(COLOR_WARNING, 0.30) if enemy.action_state == "windup" else Color(COLOR_BLOOD, 0.62)
	if enemy.kind_id == "melee_pursuer":
		var origin: Vector2 = enemy.target_shape.get("origin", enemy.position)
		var radius := float(enemy.target_shape.get("radius", EnemyTacticsScript.MELEE_ATTACK_RANGE))
		if enemy.action_state == "active":
			canvas.draw_circle(origin, radius, color)
		canvas.draw_arc(origin, radius, 0.0, TAU, 24, COLOR_BONE if enemy.action_state == "active" else COLOR_WARNING, 2.0, false)
	elif enemy.kind_id == "charging_raider":
		if enemy.action_state == "windup":
			_draw_lane_shape(canvas, enemy.charge_origin, enemy.charge_direction, enemy.charge_length, enemy.charge_width, color, false)
		else:
			var step := enemy.charge_length / float(active_ticks)
			_draw_lane_shape(canvas, enemy.position, enemy.charge_direction, step, enemy.charge_width, color, true)
	elif enemy.kind_id == "fan_ranged":
		var fan_shape: Dictionary = enemy.target_shape
		_draw_fan_shape(canvas, fan_shape.get("origin", enemy.position), fan_shape.get("direction", enemy.facing), float(fan_shape.get("half_angle", 0.0)), float(fan_shape.get("radius", 0.0)), color, enemy.action_state == "active")


func _draw_boss_transition_rings(canvas: CanvasItem, enemy: CombatEnemyState, sim_tick: int) -> void:
	if enemy.phase_state != "transition":
		return
	var progress := clampf(float(sim_tick - enemy.state_started_tick) / float(maxi(1, enemy.state_ends_tick - enemy.state_started_tick)), 0.0, 1.0)
	for layer in range(3):
		var half_size := 40.0 - float(layer) * 8.0 - progress * (8.0 + float(layer) * 3.0)
		canvas.draw_rect(Rect2(enemy.position - Vector2.ONE * half_size, Vector2.ONE * half_size * 2.0), COLOR_ANOMALY, false, 2.0)


func _draw_player_status_overlay(canvas: CanvasItem, frame: Dictionary, world_view: RefCounted) -> void:
	var player_position: Vector2 = frame["player_position"]
	var damage_overlay: Dictionary = frame["player_damage_overlay"]
	if not damage_overlay.is_empty():
		var offset: Vector2 = damage_overlay.get("offset", Vector2.ZERO)
		var alpha := float(damage_overlay.get("alpha", 0.0))
		var body := Rect2(player_position + offset - Vector2(11.0, 37.0), Vector2(22.0, 31.0))
		for segment in CombatMarksScript.corner_bracket_segments(body.grow(7.0), 4.0):
			canvas.draw_line(segment[0], segment[1], Color(COLOR_WARNING, alpha), 1.2, false)
	var dash_remaining := int(frame["dash_remaining_ticks"])
	if dash_remaining > 0:
		var dash_direction: Vector2 = frame["dash_direction"]
		var dash_step := float(frame["dash_step"])
		for trail_index in range(1, 4):
			canvas.draw_circle(player_position - dash_direction * dash_step * float(trail_index), 8.0 - float(trail_index), Color(COLOR_PROXY, 0.28 / float(trail_index)))
	if int(frame["dodge_remaining_ticks"]) > 0:
		var dodge_frame := Rect2(player_position - Vector2(22.0, 54.0), Vector2(44.0, 64.0))
		for segment in CombatMarksScript.corner_bracket_segments(dodge_frame, 10.0):
			canvas.draw_line(segment[0], segment[1], COLOR_BONE, 2.0)
	var aim_origin := player_position + Vector2(0.0, -24.0)
	var player_facing: Vector2 = frame["player_facing"]
	var aim_direction := player_facing.normalized() if player_facing.length_squared() > 0.0001 else Vector2.RIGHT
	var aim_end := aim_origin + aim_direction * 18.0
	var aim_side := aim_direction.rotated(PI * 0.5)
	canvas.draw_line(aim_origin, aim_end, Color(COLOR_INK, 0.92), 5.0, false)
	canvas.draw_line(aim_origin, aim_end, COLOR_AMBER, 2.0, false)
	canvas.draw_line(aim_end - aim_direction * 6.0 + aim_side * 4.0, aim_end, COLOR_AMBER, 2.0, false)
	canvas.draw_line(aim_end - aim_direction * 6.0 - aim_side * 4.0, aim_end, COLOR_AMBER, 2.0, false)
	canvas.draw_circle(aim_origin, 2.5, COLOR_AMBER)


func _draw_piercing_projectiles(canvas: CanvasItem, frame: Dictionary) -> void:
	for projectile: CombatArrowProjectile in frame["projectiles"]:
		ArenaWorldViewScript.draw_piercing_arrow(canvas, projectile.previous_position, projectile.position, projectile.direction, projectile.origin)


func _draw_combat_feedback_marks(canvas: CanvasItem, frame: Dictionary) -> void:
	var font: Font = frame["font"]
	for mark: Dictionary in frame["combat_feedback_marks"]:
		var duration := maxf(0.001, float(mark.get("duration", COMBAT_FEEDBACK_LIFETIME_SECONDS)))
		var remaining := clampf(float(mark.get("remaining", 0.0)), 0.0, duration)
		var progress := 1.0 - remaining / duration
		var alpha := clampf(remaining / minf(0.24, duration), 0.0, 1.0)
		var kind := String(mark.get("kind", ""))
		var position: Vector2 = mark.get("position", Vector2.ZERO)
		var color := COLOR_BONE
		if kind == "player_damage":
			color = COLOR_WARNING
		elif kind == "blocked":
			color = COLOR_PROXY
		elif kind == "miss":
			color = COLOR_NEUTRAL
		elif kind == "death":
			color = COLOR_AMBER
		var live_color := Color(color, alpha)
		match kind:
			"enemy_damage", "player_damage":
				var incoming: Vector2 = mark.get("incoming_direction", Vector2.RIGHT)
				_draw_contact_sparks(canvas, position, incoming, live_color, remaining)
				if kind == "player_damage":
					var bar_top := position + Vector2(-11.0, -7.0)
					canvas.draw_line(bar_top, bar_top + Vector2(22.0, 0.0), live_color, 2.5)
					canvas.draw_line(bar_top + Vector2(9.0, 0.0), bar_top + Vector2(9.0, -6.0), live_color, 2.5)
			"blocked":
				for segment: Array in CombatMarksScript.corner_bracket_segments(Rect2(position - Vector2.ONE * 11.0, Vector2.ONE * 22.0), 5.0):
					canvas.draw_line(segment[0], segment[1], live_color, 1.5)
			"miss", "avoided":
				if kind == "avoided":
					for index in 2:
						canvas.draw_arc(position + Vector2(-4.0 + 8.0 * float(index), -3.0), 8.0, -PI * 0.18, PI * 0.62, 9, live_color, 2.0, true)
				else:
					canvas.draw_line(position + Vector2(-7.0, 0.0), position + Vector2(7.0, 0.0), live_color, 2.0)
			"death":
				_draw_death_burst(canvas, position, progress, live_color, Color(COLOR_WARNING, alpha * 0.65))
		if font != null:
			var text := _compact_feedback_number(String(mark.get("text", "")))
			var lane := int(mark.get("text_lane", 0))
			var height := 64.0 if kind == "player_damage" else 38.0
			var baseline := position + Vector2(-49.0, -height - float(lane) * 15.0 - progress * 14.0)
			var outline_color := Color(COLOR_INK, 0.92 * alpha)
			for offset: Vector2 in [Vector2(-1.0, 0.0), Vector2(1.0, 0.0), Vector2(0.0, -1.0), Vector2(0.0, 1.0)]:
				canvas.draw_string(font, baseline + offset, text, HORIZONTAL_ALIGNMENT_CENTER, 98.0, COMBAT_FEEDBACK_TEXT_FONT_SIZE, outline_color)
			canvas.draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_CENTER, 98.0, COMBAT_FEEDBACK_TEXT_FONT_SIZE, live_color)


func _draw_contact_sparks(canvas: CanvasItem, position: Vector2, direction: Vector2, color: Color, mark_remaining: float) -> void:
	if direction == Vector2.ZERO:
		direction = Vector2.RIGHT
	direction = direction.normalized()
	var age := COMBAT_FEEDBACK_LIFETIME_SECONDS - mark_remaining
	var spark_alpha := clampf(1.0 - age / COMBAT_SPARK_LIFETIME_SECONDS, 0.0, 1.0)
	if spark_alpha <= 0.0:
		return
	for index in 2:
		var spread := (-0.58 + 1.16 * float(index)) * (1.0 - 0.38 * float(index))
		var spark_direction := direction.rotated(spread)
		canvas.draw_line(position, position + spark_direction * (7.0 + 3.0 * float(index)), Color(color, color.a * spark_alpha), 1.0)


func _draw_death_burst(canvas: CanvasItem, position: Vector2, progress: float, edge: Color, core: Color) -> void:
	for index in 8:
		var angle := TAU * (float(index) + progress * 0.35) / 8.0
		var direction := Vector2.from_angle(angle)
		canvas.draw_line(position + direction * (6.0 + progress * 11.0), position + direction * (16.0 + progress * 22.0), edge, 2.0)
	canvas.draw_circle(position, 6.0 + progress * 6.0, core)


func _draw_mark_indicator(canvas: CanvasItem, frame: Dictionary, world_view: RefCounted) -> void:
	var target: Variant = frame["marked_enemy"]
	if target == null or not target is CombatEnemyState:
		return
	var enemy: CombatEnemyState = target
	if enemy.health <= 0.0 or int(frame["sim_tick"]) >= int(frame["marked_expires_tick"]):
		return
	var feet: Vector2 = world_view.gameplay_to_world(enemy.position)
	var dot := feet + Vector2(0.0, -126.0 if enemy.is_boss else -56.0)
	var half_extent := 12.0 if enemy.is_boss else 10.0
	var bracket := Rect2(dot - Vector2(half_extent, 4.0), Vector2(half_extent * 2.0, 8.0))
	for segment in CombatMarksScript.corner_bracket_segments(bracket, 3.0):
		canvas.draw_line(segment[0], segment[1], COLOR_AMBER, 2.0)
	canvas.draw_circle(dot, 2.0, COLOR_AMBER)


func _draw_pointer_target_indicator(canvas: CanvasItem, frame: Dictionary, world_view: RefCounted) -> void:
	var state: Dictionary = frame["attack_target_ui"]
	var source := String(state.get("source", ""))
	if source != ATTACK_SOURCE_POINTER and source != ATTACK_SOURCE_ASSISTED:
		return
	if not bool(state.get("has_target", false)):
		return
	var center_gameplay: Vector2 = state.get("target_anchor", Vector2.ZERO)
	var radius_gameplay := float(state.get("target_radius", 0.0))
	if radius_gameplay <= 0.0:
		return
	var center: Vector2 = world_view.gameplay_to_world(center_gameplay)
	var radius: float = center.distance_to(world_view.gameplay_to_world(center_gameplay + Vector2(radius_gameplay, 0.0)))
	if source == ATTACK_SOURCE_ASSISTED:
		_draw_assisted_target_circle(canvas, state, center, radius)
		return
	var bracket := Rect2(center - Vector2.ONE * radius, Vector2.ONE * radius * 2.0)
	var color := Color(COLOR_NEUTRAL, 0.82) if String(state.get("status", "")) == POINTER_STATUS_OUT_OF_RANGE else Color(COLOR_PROXY, 0.96)
	for segment in CombatMarksScript.corner_bracket_segments(bracket, clampf(radius * 0.34, 6.0, 18.0)):
		canvas.draw_line(segment[0], segment[1], color, 1.5)
	var diamond := PackedVector2Array([
		center + Vector2(0.0, -4.0),
		center + Vector2(4.0, 0.0),
		center + Vector2(0.0, 4.0),
		center + Vector2(-4.0, 0.0),
		center + Vector2(0.0, -4.0),
	])
	canvas.draw_polyline(diamond, color, 1.5)


func _draw_assisted_target_circle(canvas: CanvasItem, state: Dictionary, center: Vector2, radius: float) -> void:
	var tint := Color(COLOR_PROXY, 0.55) if bool(state.get("in_range", false)) else Color(COLOR_NEUTRAL, 0.45)
	var segments := 16
	var sweep := TAU / float(segments) * 0.55
	for index in range(segments):
		var start := TAU * float(index) / float(segments)
		canvas.draw_arc(center, radius, start, start + sweep, 4, tint, 1.5, false)


func _draw_bracket_rect(canvas: CanvasItem, rect: Rect2) -> void:
	var corner := 13.0
	for point in [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]:
		var sx := 1.0 if point.x == rect.position.x else -1.0
		var sy := 1.0 if point.y == rect.position.y else -1.0
		canvas.draw_line(point, point + Vector2(sx * corner, 0.0), COLOR_WARNING, 3.0)
		canvas.draw_line(point, point + Vector2(0.0, sy * corner), COLOR_WARNING, 3.0)


func _draw_boss_target_shape(canvas: CanvasItem, enemy: CombatEnemyState) -> void:
	if enemy.action_state not in ["windup", "active", "recovery"] or enemy.target_shape.is_empty():
		return
	var active := enemy.action_state == "active"
	var recovery := enemy.action_state == "recovery"
	var color := Color(COLOR_NEUTRAL, 0.55) if recovery else (Color(COLOR_BLOOD, 0.68) if active else Color(COLOR_WARNING, 0.34))
	match enemy.action_id:
		"slam":
			var rect: Rect2 = enemy.target_shape.get("rect", Rect2())
			if active:
				canvas.draw_rect(rect, color)
				canvas.draw_line(rect.position, rect.end, COLOR_BONE, 3.0)
				canvas.draw_line(Vector2(rect.end.x, rect.position.y), Vector2(rect.position.x, rect.end.y), COLOR_BONE, 3.0)
			elif recovery:
				canvas.draw_rect(rect, color, false, 2.0)
			else:
				_draw_bracket_rect(canvas, rect)
				for segment in CombatMarksScript.diagonal_hatch_segments(rect, CombatMarksScript.HATCH_SPACING):
					canvas.draw_line(segment[0], segment[1], Color(COLOR_WARNING, 0.55), 1.0)
		"sweep":
			var origin: Vector2 = enemy.target_shape.get("origin", Vector2.ZERO)
			var direction: Vector2 = enemy.target_shape.get("direction", Vector2.RIGHT)
			var radius := float(enemy.target_shape.get("radius", 0.0))
			if recovery:
				canvas.draw_line(origin + direction * radius * 0.58, origin + direction * radius * 0.82, color, 4.0)
			else:
				_draw_fan_shape(canvas, origin, direction, float(enemy.target_shape.get("half_angle", 0.0)), radius, color, active)
		"lane":
			var recovery_scale := 0.55 if recovery else 1.0
			_draw_lane_shape(canvas, enemy.target_shape.get("origin", Vector2.ZERO), enemy.target_shape.get("direction", Vector2.RIGHT), float(enemy.target_shape.get("length", 0.0)) * recovery_scale, float(enemy.target_shape.get("width", 0.0)), color, active, not recovery)


func _draw_lane_shape(canvas: CanvasItem, origin: Vector2, direction: Vector2, length: float, width: float, color: Color, active: bool, emphasize_boundary: bool = true) -> void:
	var side := direction.rotated(PI * 0.5) * width * 0.5
	var finish := origin + direction * length
	var polygon := PackedVector2Array([origin + side, finish + side, finish - side, origin - side])
	if active:
		canvas.draw_colored_polygon(polygon, color)
		canvas.draw_line(finish + side, finish - side, COLOR_BONE, 3.0)
	else:
		var edge_color := Color(color, maxf(color.a, 0.80)) if emphasize_boundary else color
		for edge in [PackedVector2Array([origin + side, finish + side]), PackedVector2Array([origin - side, finish - side])]:
			if emphasize_boundary:
				canvas.draw_polyline(edge, Color(COLOR_INK, 0.88), 5.0)
			canvas.draw_polyline(edge, edge_color, 2.5 if emphasize_boundary else 3.0)
		for step in range(1, 5):
			var center := origin + direction * length * float(step) / 5.0
			canvas.draw_line(center + side, center + side * 0.55, edge_color, 2.0)
			canvas.draw_line(center - side, center - side * 0.55, edge_color, 2.0)


func _draw_fan_shape(canvas: CanvasItem, origin: Vector2, direction: Vector2, half_angle: float, radius: float, color: Color, active: bool) -> void:
	var points := PackedVector2Array([origin])
	const SEGMENTS := 12
	for index in range(SEGMENTS + 1):
		var angle := lerpf(-half_angle, half_angle, float(index) / float(SEGMENTS))
		points.append(origin + direction.rotated(angle) * radius)
	if active:
		canvas.draw_colored_polygon(points, color)
		canvas.draw_polyline(PackedVector2Array(points.slice(1)), COLOR_BONE, 3.0)
	else:
		for index in range(0, SEGMENTS + 1, 3):
			canvas.draw_line(origin, points[index + 1], color, 2.0)
		canvas.draw_polyline(PackedVector2Array(points.slice(1)), color, 3.0)


func _compact_feedback_number(value: String) -> String:
	if not value.contains("e") and not value.contains("E"):
		var sign_prefix := value.left(1) if value.begins_with("−") or value.begins_with("-") or value.begins_with("+") else ""
		var number_text := value.substr(sign_prefix.length())
		if number_text.is_valid_float() and is_finite(number_text.to_float()):
			return sign_prefix + String.num(roundf(number_text.to_float()), 0)
		return value
	var parsed := value.to_float()
	if not is_finite(parsed) or absf(parsed) < 10000.0:
		return value
	var exponent := 0
	var coefficient := absf(parsed)
	while coefficient >= 10.0:
		coefficient *= 0.1
		exponent += 1
	while coefficient < 1.0 and coefficient > 0.0:
		coefficient *= 10.0
		exponent -= 1
	var compact := String.num(coefficient, 2)
	while compact.contains(".") and (compact.ends_with("0") or compact.ends_with(".")):
		compact = compact.substr(0, compact.length() - 1)
	return "%s%se%d" % ["-" if parsed < 0.0 else "", compact, exponent]
