extends SceneTree
## Bounds contract for the code-native combat markings (ART_BIBLE v0.9 §07/§09).
##
## The markings may only ever describe the range the simulation resolves: the
## hatch is clipped to the authoritative rect, the brackets stay open and short,
## and no helper touches gameplay data. The combat presenter draw paths are
## checked by source so the fix cannot silently regress to a closed box or a full
## circle.
const CombatMarks = preload("res://src/presentation/combat_marks.gd")
const Assert := preload("res://tests/helpers/assert.gd")

const MAIN_SOURCE_PATH := "res://src/game/main.gd"
const CONTROLLER_SOURCE_PATH := "res://src/presentation/combat_presentation_controller.gd"
const HELPER_SOURCE_PATH := "res://src/presentation/combat_marks.gd"
const PRESENTER_SOURCE_PATH := "res://src/presentation/arena_presenter.gd"
const COMBAT_PRESENTER_SOURCE_PATH := "res://src/presentation/arena_combat_presenter.gd"
const EPSILON := 0.0001

var failures: Array[String] = []


func _initialize() -> void:
	_test_hatch_is_clipped_to_the_range()
	_test_hatch_survives_arbitrary_rect_sizes()
	_test_brackets_stay_open_and_short()
	_test_markings_do_not_mutate_gameplay_data()
	_test_draw_paths_use_the_clipped_marks()
	for failure in failures:
		printerr(failure)
	print("PASS  test_combat_marks.gd" if failures.is_empty() else "FAIL test_combat_marks.gd")
	quit(0 if failures.is_empty() else 1)


## The boss slam windup hatched from outside the rect, so the ground advertised
## more ground than the slam covers. Every emitted endpoint must now sit inside
## the rect the simulation hands the resolver.
func _test_hatch_is_clipped_to_the_range() -> void:
	var rect := Rect2(Vector2(13.0, 7.0), Vector2(76.0, 60.0))
	var segments := CombatMarks.diagonal_hatch_segments(rect, 12.0)
	_expect(not segments.is_empty(), "a 76x60 slam range must still hatch")
	var edges := {"left": false, "right": false, "top": false, "bottom": false}
	for segment in segments:
		_expect(segment.size() == 2, "a hatch segment is one line")
		var from: Vector2 = segment[0]
		var to: Vector2 = segment[1]
		_expect(_inside(rect, from) and _inside(rect, to), "hatch endpoint escaped the range: %s -> %s" % [from, to])
		_expect(absf(absf(to.x - from.x) - absf(to.y - from.y)) <= EPSILON, "hatch keeps its 45 degree read")
		_expect(from.distance_to(to) > EPSILON, "a hatch line is never a point")
		edges["left"] = edges["left"] or _touches(from.x, to.x, rect.position.x)
		edges["right"] = edges["right"] or _touches(from.x, to.x, rect.end.x)
		edges["top"] = edges["top"] or _touches(from.y, to.y, rect.position.y)
		edges["bottom"] = edges["bottom"] or _touches(from.y, to.y, rect.end.y)
	for edge: String in edges.keys():
		_expect(edges[edge], "the clipped hatch still reaches the %s edge of the authored range" % edge)


func _test_hatch_survives_arbitrary_rect_sizes() -> void:
	## Wide, tall, square, tiny and a negative-size rect: the helper normalizes and
	## clips all of them instead of trusting one authored slam size.
	var rects: Array[Rect2] = [
		Rect2(Vector2(0.0, 0.0), Vector2(76.0, 60.0)),
		Rect2(Vector2(-40.0, 12.5), Vector2(37.0, 211.0)),
		Rect2(Vector2(8.0, 8.0), Vector2(211.0, 37.0)),
		Rect2(Vector2(4.0, 4.0), Vector2(9.0, 9.0)),
		Rect2(Vector2(2.0, 2.0), Vector2(1.5, 1.5)),
		Rect2(Vector2(50.0, 50.0), Vector2(-20.0, -30.0)),
	]
	for rect in rects:
		var bounds := rect.abs()
		var segments := CombatMarks.diagonal_hatch_segments(rect, 12.0)
		_expect(not segments.is_empty(), "a %s range must hatch" % bounds.size)
		for segment in segments:
			_expect(_inside(bounds, segment[0]) and _inside(bounds, segment[1]), "hatch endpoint escaped %s" % bounds.size)
			_expect(is_finite(segment[0].x) and is_finite(segment[0].y) and is_finite(segment[1].x) and is_finite(segment[1].y), "hatch stays finite for %s" % bounds.size)
	_expect(CombatMarks.diagonal_hatch_segments(Rect2(Vector2(3.0, 3.0), Vector2.ZERO), 12.0).is_empty(), "a zero-area range hatches nothing")
	_expect(CombatMarks.diagonal_hatch_segments(rects[0], 0.0).size() <= CombatMarks.MAX_HATCH_SEGMENTS, "a degenerate spacing cannot flood the draw pass")


func _test_brackets_stay_open_and_short() -> void:
	var frame := Rect2(Vector2(-11.0, 4.5), Vector2(44.0, 64.0))
	var half_extent := minf(frame.size.x, frame.size.y) * 0.5
	var segments := CombatMarks.corner_bracket_segments(frame, 10.0)
	_expect(segments.size() == 8, "four corners draw two arms each, got %d" % segments.size())
	for segment in segments:
		var from: Vector2 = segment[0]
		var to: Vector2 = segment[1]
		_expect(_on_boundary(frame, from) and _on_boundary(frame, to), "a bracket arm left the frame: %s -> %s" % [from, to])
		_expect(from.distance_to(to) <= 10.0 + EPSILON, "the requested short arm is honoured")
		_expect(from.distance_to(to) <= half_extent + EPSILON, "an arm never exceeds half the frame extent")
	_expect(_has_gaps(frame, segments), "the corners stay an open bracket, never a closed box")
	## An oversized request is clamped instead of closing the frame into a ring.
	var clamped := CombatMarks.corner_bracket_segments(frame, 999.0)
	_expect(clamped.size() == 8, "a clamped bracket still draws four corners")
	for segment in clamped:
		_expect(segment[0].distance_to(segment[1]) <= half_extent, "a clamped arm stays under half the extent")
	_expect(_has_gaps(frame, clamped), "even a clamped bracket keeps its gaps")
	_expect(CombatMarks.corner_bracket_segments(frame, 0.0).is_empty(), "a zero arm draws nothing")
	_expect(CombatMarks.corner_bracket_segments(Rect2(Vector2(3.0, 3.0), Vector2.ZERO), 6.0).is_empty(), "a degenerate frame draws nothing")
	## The published hunter mark geometry: 20/24 native wide, arms at half of that.
	for half in [10.0, 12.0]:
		var mark := CombatMarks.corner_bracket_segments(Rect2(Vector2(64.0, 32.0) - Vector2.ONE * half, Vector2.ONE * half * 2.0), half * 0.5)
		_expect(mark.size() == 8 and _has_gaps(Rect2(Vector2(64.0, 32.0) - Vector2.ONE * half, Vector2.ONE * half * 2.0), mark), "the %d native wide hunter mark stays an open bracket" % int(half * 2.0))


## A marking is geometry only: reading the same authoritative rect twice returns
## the same lines and never rewrites the shape dictionary it came from.
func _test_markings_do_not_mutate_gameplay_data() -> void:
	var target_shape := {"type": "rect", "rect": Rect2(Vector2(13.0, 7.0), Vector2(76.0, 60.0))}
	var before := str(target_shape)
	var first := CombatMarks.diagonal_hatch_segments(target_shape["rect"], 12.0)
	var second := CombatMarks.diagonal_hatch_segments(target_shape["rect"], 12.0)
	_expect(str(target_shape) == before, "computing a marking never rewrites the authoritative target shape")
	var identical := first.size() == second.size()
	for index in first.size():
		identical = identical and first[index][0] == second[index][0] and first[index][1] == second[index][1]
	_expect(identical, "the same range always yields the same clipped hatch")
	var helper_source := FileAccess.get_file_as_string(HELPER_SOURCE_PATH)
	_expect(not helper_source.is_empty(), "the markings helper is readable")
	_expect(not helper_source.contains("\nvar "), "the helper carries no member state to mutate")


func _test_draw_paths_use_the_clipped_marks() -> void:
	var source := FileAccess.get_file_as_string(MAIN_SOURCE_PATH)
	var controller_source := FileAccess.get_file_as_string(CONTROLLER_SOURCE_PATH)
	var combat_source := FileAccess.get_file_as_string(COMBAT_PRESENTER_SOURCE_PATH)
	_expect(not source.is_empty(), "main.gd is readable")
	_expect(not controller_source.is_empty(), "combat presentation controller is readable")
	_expect(not combat_source.is_empty(), "arena combat presenter is readable")
	var ground := _function_body(combat_source, "draw_ground")
	var draw := _function_body(controller_source, "_draw")
	var publication := _function_body(controller_source, "commit")
	var ground_pass := _function_body(controller_source, "draw_ground_pass")
	var slam := _function_body(combat_source, "_draw_boss_target_shape")
	var mark := _function_body(combat_source, "_draw_mark_indicator")
	var overlay := _function_body(combat_source, "_draw_player_status_overlay")
	var presenter_source := FileAccess.get_file_as_string(PRESENTER_SOURCE_PATH)
	_expect(not ground.is_empty() and not draw.is_empty() and not slam.is_empty() and not mark.is_empty() and not overlay.is_empty(), "the drawn entry points still exist")
	_expect(not presenter_source.is_empty(), "the arena presenter source is readable")
	_expect(not source.contains("_draw_legacy_") and not source.contains("actors_atlas"), "the retired flat-field and atlas drawing paths remain removed")
	_expect(_function_body(source, "_draw").is_empty(), "Main carries no combat draw pass")
	_expect(publication.contains("world_view.begin_frame") and publication.contains("actor_presenter.sync_sort_views") and ground_pass.contains("combat_presenter.draw_ground") and draw.contains("combat_presenter.draw_overlays") and not draw.contains("actor_presenter.draw(") and not draw.contains("_draw_presentation_error"), "the presentation controller owns frame publication and actor projection order")
	_expect(presenter_source.contains("_draw_presentation_error") and presenter_source.contains("draw_ground") and presenter_source.contains("draw_decals"), "ArenaPresenter owns the native world path and explicit load error")
	_expect(ground.contains("_draw_boss_target_shape") and ground.contains("_draw_hazard"), "world telegraphs and hazards still draw")
	_expect(ground.contains("_draw_walkable_layout_boundaries("), "true movement limits remain visible in approved world")
	var boundary := _function_body(combat_source, "_draw_walkable_layout_boundaries")
	_expect(boundary.contains("walkable_geometry") and boundary.contains("canvas.draw_arc(center, inner_radius") and boundary.contains("canvas.draw_arc(center, outer_radius"), "ring guides use the canonical annulus geometry")
	_expect(not boundary.contains("COLOR_AMBER") and boundary.contains("COLOR_NEUTRAL"), "movement boundaries do not masquerade as targets")
	_expect(slam.contains("CombatMarksScript.diagonal_hatch_segments(rect"), "the slam windup hatches through the clipped helper on the authoritative rect")
	_expect(slam.contains("draw_rect(rect, color)") and slam.contains("draw_rect(rect, color, false, 2.0)"), "active and recovery slam semantics are untouched")
	_expect(not mark.contains("draw_arc("), "the hunter mark is no longer a full circle")
	_expect(mark.contains("CombatMarksScript.corner_bracket_segments"), "the hunter mark draws open corner brackets")
	_expect(mark.contains("draw_colored_polygon(") and mark.contains("-126.0") and mark.contains("-56.0"), "the pixel diamond mark keeps its boss and enemy offsets")
	_expect(mark.contains("enemy.health <= 0.0") and mark.contains("marked_expires_tick"), "the mark remains gated by live target health and expiry")
	_expect(not overlay.contains("draw_rect(dodge_frame"), "the dodge no longer draws a closed box")
	_expect(overlay.contains("for side: float in [-1.0, 1.0]") and overlay.contains("Vector2(side * 16.0, 2.0)") and overlay.contains("Vector2(side * 5.0, -4.0)"), "the dodge draws short symmetric ground ticks outside the actor silhouette")
	_expect(overlay.contains("if int(frame[\"dodge_remaining_ticks\"]) > 0:") and overlay.contains("Color(COLOR_BONE, 0.85)"), "the bone dodge accents retain the simulation's active window")


func _function_body(source: String, name: String) -> String:
	var start := source.find("\nfunc %s(" % name)
	if start < 0:
		return ""
	var next := source.find("\nfunc ", start + 1)
	return source.substr(start, (next - start) if next > start else source.length() - start)


func _inside(rect: Rect2, point: Vector2) -> bool:
	return point.x >= rect.position.x - EPSILON and point.x <= rect.end.x + EPSILON and point.y >= rect.position.y - EPSILON and point.y <= rect.end.y + EPSILON


func _on_boundary(rect: Rect2, point: Vector2) -> bool:
	var on_x := (absf(point.x - rect.position.x) <= EPSILON or absf(point.x - rect.end.x) <= EPSILON) and point.y >= rect.position.y - EPSILON and point.y <= rect.end.y + EPSILON
	var on_y := (absf(point.y - rect.position.y) <= EPSILON or absf(point.y - rect.end.y) <= EPSILON) and point.x >= rect.position.x - EPSILON and point.x <= rect.end.x + EPSILON
	return on_x or on_y


func _touches(from: float, to: float, edge: float) -> bool:
	return absf(from - edge) <= EPSILON or absf(to - edge) <= EPSILON


## True while no frame edge is fully covered, i.e. the four corners really are an
## open bracket and not a closed ring around the actor.
func _has_gaps(frame: Rect2, segments: Array) -> bool:
	var top := 0.0
	var bottom := 0.0
	var left := 0.0
	var right := 0.0
	for segment in segments:
		var from: Vector2 = segment[0]
		var to: Vector2 = segment[1]
		if absf(from.y - to.y) <= EPSILON:
			if absf(from.y - frame.position.y) <= EPSILON:
				top += absf(to.x - from.x)
			elif absf(from.y - frame.end.y) <= EPSILON:
				bottom += absf(to.x - from.x)
		elif absf(from.x - to.x) <= EPSILON:
			if absf(from.x - frame.position.x) <= EPSILON:
				left += absf(to.y - from.y)
			elif absf(from.x - frame.end.x) <= EPSILON:
				right += absf(to.y - from.y)
	return top < frame.size.x - EPSILON and bottom < frame.size.x - EPSILON and left < frame.size.y - EPSILON and right < frame.size.y - EPSILON


func _expect(ok: bool, message: String) -> void: Assert.expect(ok, message, failures)
