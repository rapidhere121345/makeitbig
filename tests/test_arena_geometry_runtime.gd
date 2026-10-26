extends SceneTree

const Geometry := preload("res://src/runtime/geometry/arena_geometry.gd")
const Assert := preload("res://tests/helpers/assert.gd")

var failures: Array[String] = []


func _initialize() -> void:
	_test_from_layout_and_rectangle_projection()
	_test_corridor_projection()
	_test_ring_projection()
	_test_native_boundary_planning()
	_test_native_boundary_footprint_clearance()
	_test_line_segment_walkability()
	_test_invalid_schema_fails_closed()
	_test_candidate_order()
	_test_rectangle_corner_meaningful_detour()
	_test_ring_antipode_detour()
	_test_repeatability()
	if failures.is_empty():
		print("PASS  test_arena_geometry_runtime.gd")
		quit(0)
		return
	for failure: String in failures:
		printerr("- %s" % failure)
	quit(1)


func _test_from_layout_and_rectangle_projection() -> void:
	var geometry: Dictionary = Geometry.from_layout("rectangle_arena", Rect2(10.0, 20.0, 400.0, 200.0), 10.0)
	_expect(geometry.keys().size() == 7, "rectangle: schema does not have exactly seven fields")
	_expect(geometry == {
		"schema_version": 1,
		"kind": "rectangle",
		"bounds": Rect2(20.0, 30.0, 380.0, 180.0),
		"center": Vector2(210.0, 120.0),
		"corridor_half_height": 0.0,
		"inner_radius": 0.0,
		"outer_radius": 0.0,
	}, "rectangle: from_layout fields changed")
	var normalized: Dictionary = Geometry.normalize(geometry)
	_expect(bool(normalized.ok) and normalized.value == geometry and String(normalized.error).is_empty(), "rectangle: valid geometry did not normalize exactly")
	var result: Dictionary = Geometry.project(Vector2(-50.0, 500.0), geometry)
	_expect(bool(result.ok) and result.position == Vector2(20.0, 210.0), "rectangle: exact bounds projection changed")


func _test_corridor_projection() -> void:
	var short: Dictionary = Geometry.from_layout("corridor", Rect2(0.0, 0.0, 400.0, 200.0), 10.0)
	_expect(is_equal_approx(float(short.corridor_half_height), 45.0), "corridor: quarter-height cap changed")
	var short_result: Dictionary = Geometry.project(Vector2(500.0, -100.0), short)
	_expect(bool(short_result.ok) and short_result.position == Vector2(390.0, 55.0), "corridor: short exact projection changed")
	var tall: Dictionary = Geometry.from_layout("corridor", Rect2(0.0, 0.0, 600.0, 600.0), 0.0)
	_expect(is_equal_approx(float(tall.corridor_half_height), 72.0), "corridor: 72-unit cap changed")
	var tall_result: Dictionary = Geometry.project(Vector2(300.0, 500.0), tall)
	_expect(bool(tall_result.ok) and tall_result.position == Vector2(300.0, 372.0), "corridor: tall exact projection changed")


func _test_ring_projection() -> void:
	var geometry: Dictionary = Geometry.from_layout("ring", Rect2(0.0, 0.0, 1000.0, 800.0), 0.0)
	_expect(geometry.center == Vector2(500.0, 400.0), "ring: center changed")
	_expect(is_equal_approx(float(geometry.inner_radius), 160.0) and is_equal_approx(float(geometry.outer_radius), 344.0), "ring: Main-compatible radii changed")
	var center_result: Dictionary = Geometry.project(Vector2(500.0, 400.0), geometry)
	_expect(bool(center_result.ok) and center_result.position == Vector2(660.0, 400.0), "ring: zero offset did not use stable RIGHT")
	var inner_result: Dictionary = Geometry.project(Vector2(500.0, 300.0), geometry)
	_expect(bool(inner_result.ok) and inner_result.position == Vector2(500.0, 240.0), "ring: inner-radius projection changed")
	var outer_result: Dictionary = Geometry.project(Vector2(500.0, 900.0), geometry)
	_expect(bool(outer_result.ok) and outer_result.position == Vector2(500.0, 744.0), "ring: rectangle-first outer projection changed")


func _test_line_segment_walkability() -> void:
	var rectangle := Geometry.from_layout("rectangle_arena", Rect2(0.0, 0.0, 400.0, 200.0), 10.0)
	_expect(Geometry.line_segment_walkable(Vector2(10.0, 10.0), Vector2(390.0, 190.0), rectangle) == {"ok": true, "error": "", "walkable": true}, "segment rectangle: contained diagonal was rejected")
	_expect(Geometry.line_segment_walkable(Vector2(9.0, 10.0), Vector2(390.0, 190.0), rectangle) == {"ok": true, "error": "", "walkable": false}, "segment rectangle: outside endpoint was accepted")

	var corridor := Geometry.from_layout("corridor", Rect2(0.0, 0.0, 600.0, 600.0), 0.0)
	_expect(bool(Geometry.line_segment_walkable(Vector2(0.0, 228.0), Vector2(600.0, 372.0), corridor).walkable), "segment corridor: contained convex diagonal was rejected")
	_expect(not bool(Geometry.line_segment_walkable(Vector2(300.0, 227.9), Vector2(300.0, 372.0), corridor).walkable), "segment corridor: endpoint outside canonical strip was accepted")

	var ring := Geometry.from_layout("ring", Rect2(0.0, 0.0, 1000.0, 800.0), 0.0)
	var center: Vector2 = ring["center"]
	var inner_radius := float(ring["inner_radius"])
	var outer_radius := float(ring["outer_radius"])
	var tangent_half_chord := sqrt(outer_radius * outer_radius - inner_radius * inner_radius)
	var tangent_start := center + Vector2(-tangent_half_chord, inner_radius)
	var tangent_end := center + Vector2(tangent_half_chord, inner_radius)
	_expect(bool(Geometry.line_segment_walkable(tangent_start, tangent_end, ring).walkable), "segment ring: exact inner tangent was rejected")
	_expect(not bool(Geometry.line_segment_walkable(center - Vector2.RIGHT * inner_radius, center + Vector2.RIGHT * inner_radius, ring).walkable), "segment ring: inner antipode chord crossed the hole")
	_expect(not bool(Geometry.line_segment_walkable(center + Vector2.RIGHT * (inner_radius - 0.01), center + Vector2.UP * outer_radius, ring).walkable), "segment ring: endpoint inside inner radius was accepted")
	_expect(not bool(Geometry.line_segment_walkable(center + Vector2.RIGHT * (outer_radius + 0.01), center + Vector2.UP * outer_radius, ring).walkable), "segment ring: endpoint outside outer radius was accepted")

	var bad_from := Geometry.line_segment_walkable("bad", Vector2.ZERO, ring)
	var bad_to := Geometry.line_segment_walkable(Vector2.ZERO, Vector2(INF, 0.0), ring)
	var bad_geometry := ring.duplicate(true)
	bad_geometry["inner_radius"] = -1.0
	var bad_shape := Geometry.line_segment_walkable(center, center, bad_geometry)
	_expect(not bool(bad_from.ok) and String(bad_from.error) == "invalid_from_point" and not bool(bad_from.walkable), "segment invalid: bad start did not fail explicitly")
	_expect(not bool(bad_to.ok) and String(bad_to.error) == "invalid_to_point" and not bool(bad_to.walkable), "segment invalid: bad end did not fail explicitly")
	_expect(not bool(bad_shape.ok) and not String(bad_shape.error).is_empty() and not bool(bad_shape.walkable), "segment invalid: malformed geometry did not fail explicitly")


func _test_native_boundary_planning() -> void:
	var arena := Rect2(42.0, 190.0, 1196.0, 488.0)
	for layout: String in ["rectangle_arena", "corridor", "ring"]:
		var boundary := Geometry.movement_boundary(layout, arena)
		for padding: float in [0.0, 14.0, 16.0, 28.0]:
			var native := Geometry.from_native_boundary(boundary, arena, padding)
			var baseline := Geometry.from_layout(layout, arena, padding)
			_expect(native.get("kind", "") == baseline["kind"] and native.get("bounds", Rect2()) == baseline["bounds"], "native planner: %s changed bounds/kind" % layout)
			for key: String in ["inner_radius", "outer_radius", "corridor_half_height"]:
				_expect(is_equal_approx(float(native.get(key, -1.0)), float(baseline[key])), "native planner: %s changed v03 %s" % [layout, key])
	var custom_ring := {"type": "ring", "center": arena.get_center(), "inner_radius": 80.0, "outer_radius": 180.0}
	var custom := Geometry.from_native_boundary(custom_ring, arena, 0.0)
	_expect(custom.get("inner_radius", 0.0) == 80.0 and custom.get("outer_radius", 0.0) == 180.0, "native planner: scene-authored radii were replaced by layout formulas")
	_expect(not bool(Geometry.line_segment_walkable(arena.get_center() - Vector2(100.0, 0.0), arena.get_center() + Vector2(100.0, 0.0), custom).walkable), "native planner: authored ring chord crossed the hole")
	_expect(Geometry.from_native_boundary({}, arena, 14.0).is_empty(), "native planner: missing boundary created a rectangle")
	_expect(Geometry.from_native_boundary(custom_ring, arena, 244.0).is_empty(), "native planner: impossible inset was accepted")
	_expect(Geometry.from_native_boundary(custom_ring, Rect2(arena.position + Vector2.ONE, arena.size), 0.0).is_empty(), "native planner: displaced source identity was ignored")


func _test_native_boundary_footprint_clearance() -> void:
	var arena := Rect2(42.0, 190.0, 1196.0, 488.0)
	var ring := Geometry.movement_boundary("ring", arena)
	var ring_center := arena.get_center()
	var ring_geometry := Geometry.from_native_boundary_for_footprint(ring, arena, 14.0)
	_expect(Rect2(ring_geometry.get("bounds", Rect2())) == arena.grow(-14.0), "native footprint: ring bounds did not inset by the actor radius")
	_expect(is_equal_approx(float(ring_geometry.get("inner_radius", 0.0)), 111.6) and is_equal_approx(float(ring_geometry.get("outer_radius", 0.0)), 195.84), "native footprint: ring clearance did not offset both radii")
	var projected_inner: Dictionary = Geometry.project(ring_center + Vector2.RIGHT * 100.0, ring_geometry)
	_expect(bool(projected_inner.get("ok", false)) and is_equal_approx(Vector2(projected_inner["position"]).distance_to(ring_center), 111.6), "native footprint: inner projection still entered the actor's forbidden band")
	var corridor := Geometry.movement_boundary("corridor", arena)
	var corridor_geometry := Geometry.from_native_boundary_for_footprint(corridor, arena, 14.0)
	_expect(is_equal_approx(float(corridor_geometry.get("corridor_half_height", 0.0)), 58.0), "native footprint: corridor half-height did not subtract the actor radius")
	var rectangle := Geometry.movement_boundary("rectangle_arena", arena)
	var rectangle_geometry := Geometry.from_native_boundary_for_footprint(rectangle, arena, 14.0)
	_expect(Rect2(rectangle_geometry.get("bounds", Rect2())) == arena.grow(-14.0), "native footprint: rectangle bounds changed clearance semantics")
	_expect(Geometry.from_native_boundary_for_footprint(ring, arena, 230.0).is_empty(), "native footprint: impossible ring radius was accepted")


func _test_invalid_schema_fails_closed() -> void:
	var valid: Dictionary = Geometry.from_layout("ring", Rect2(0.0, 0.0, 1000.0, 800.0), 0.0)
	var cases: Array = []
	cases.append(null)
	var missing := valid.duplicate(true)
	missing.erase("center")
	cases.append(missing)
	var extra := valid.duplicate(true)
	extra["unexpected"] = true
	cases.append(extra)
	var old_schema := valid.duplicate(true)
	old_schema["schema_version"] = 2
	cases.append(old_schema)
	var non_finite := valid.duplicate(true)
	non_finite["center"] = Vector2(INF, 0.0)
	cases.append(non_finite)
	var displaced_center := valid.duplicate(true)
	displaced_center["center"] += Vector2.ONE
	cases.append(displaced_center)
	var bad_bounds := valid.duplicate(true)
	bad_bounds["bounds"] = Rect2(0.0, 0.0, 0.0, 10.0)
	cases.append(bad_bounds)
	var bad_ring := valid.duplicate(true)
	bad_ring["inner_radius"] = 400.0
	cases.append(bad_ring)
	var approximate_ring := valid.duplicate(true)
	approximate_ring["outer_radius"] = 401.0
	cases.append(approximate_ring)
	var bad_corridor := Geometry.from_layout("corridor", Rect2(0.0, 0.0, 600.0, 600.0), 0.0)
	bad_corridor["corridor_half_height"] = 301.0
	cases.append(bad_corridor)
	var bad_rectangle := Geometry.from_layout("rectangle_arena", Rect2(0.0, 0.0, 100.0, 100.0), 0.0)
	bad_rectangle["outer_radius"] = 1.0
	cases.append(bad_rectangle)
	for index in cases.size():
		var result: Dictionary = Geometry.normalize(cases[index])
		_expect(not bool(result.get("ok", true)) and not String(result.get("error", "")).is_empty() and Dictionary(result.get("value", {"leak": true})).is_empty(), "schema: invalid case %d did not fail closed" % index)
	var bad_project: Dictionary = Geometry.project("bad", valid)
	_expect(not bool(bad_project.ok) and bad_project.position == Vector2.ZERO, "schema: project leaked a position for invalid input")


func _test_candidate_order() -> void:
	var positive: Array[Vector2] = Geometry.candidate_directions(Vector2.RIGHT, 1)
	var negative: Array[Vector2] = Geometry.candidate_directions(Vector2.RIGHT, -1)
	_expect(positive.size() == 9 and negative.size() == 9, "candidates: expected nine deterministic directions")
	var magnitudes: Array[float] = [0.0, PI / 8.0, -PI / 8.0, PI / 4.0, -PI / 4.0, PI * 3.0 / 8.0, -PI * 3.0 / 8.0, PI / 2.0, -PI / 2.0]
	for index in magnitudes.size():
		_expect(positive[index].is_equal_approx(Vector2.RIGHT.rotated(magnitudes[index])), "candidates: +sign index %d changed" % index)
		_expect(negative[index].is_equal_approx(Vector2.RIGHT.rotated(-magnitudes[index])), "candidates: -sign index %d is not mirrored" % index)


func _test_ring_antipode_detour() -> void:
	var geometry: Dictionary = Geometry.from_layout("ring", Rect2(0.0, 0.0, 1000.0, 800.0), 0.0)
	var position := Vector2(340.0, 400.0)
	var positive: Dictionary = Geometry.choose_feasible_direction(position, Vector2.RIGHT, 40.0, geometry, 1)
	var negative: Dictionary = Geometry.choose_feasible_direction(position, Vector2.RIGHT, 40.0, geometry, -1)
	_expect(bool(positive.ok) and bool(positive.detour) and float(positive.actual_displacement) > 40.0 * 0.05, "detour: +sign did not make five-percent progress")
	_expect(bool(negative.ok) and bool(negative.detour) and float(negative.actual_displacement) > 40.0 * 0.05, "detour: -sign did not make five-percent progress")
	_expect(Vector2(positive.direction).is_equal_approx(Vector2.RIGHT.rotated(PI / 8.0)), "detour: +sign did not choose its first movable candidate")
	_expect(Vector2(negative.direction).is_equal_approx(Vector2.RIGHT.rotated(-PI / 8.0)), "detour: -sign did not choose its first movable candidate")
	var positive_position: Vector2 = positive.projected_position
	var negative_position: Vector2 = negative.projected_position
	_expect(is_equal_approx(positive_position.x, negative_position.x) and is_equal_approx(positive_position.y - 400.0, -(negative_position.y - 400.0)), "detour: stable signs are not geometric mirrors")


func _test_rectangle_corner_meaningful_detour() -> void:
	# This is Main's rectangle-arena public proxy geometry: the 42px arena margin
	# plus 14px player padding puts its top-left walkable corner at (56, 204).
	var geometry := Geometry.from_layout("rectangle_arena", Rect2(42.0, 190.0, 1196.0, 488.0), 14.0)
	var position := Vector2(56.0, 204.0)
	var desired := Vector2(-2.0, -1.998)
	var lookahead := 24.0
	var nearly_outward := desired.normalized().rotated(-PI / 4.0)
	var tiny_projection := Geometry.project(position + nearly_outward * lookahead, geometry)
	var tiny_displacement := position.distance_to(Vector2(tiny_projection.position))
	_expect(tiny_displacement > 0.01 and tiny_displacement < lookahead * 0.05, "corner: fixture no longer produces the quantization-swallowed candidate")

	var choice: Dictionary = Geometry.choose_feasible_direction(position, desired, lookahead, geometry, 1)
	_expect(bool(choice.ok) and bool(choice.detour), "corner: blocked retreat did not choose a detour")
	_expect(float(choice.actual_displacement) >= lookahead * 0.05, "corner: detour accepted less than five percent of lookahead")
	_expect(Vector2(choice.direction).x > -0.99, "corner: detour remained the nearly pure outward direction")


func _test_repeatability() -> void:
	var geometry: Dictionary = Geometry.from_layout("ring", Rect2(0.0, 0.0, 1000.0, 800.0), 0.0)
	var first: Dictionary = Geometry.choose_feasible_direction(Vector2(340.0, 400.0), Vector2.RIGHT, 40.0, geometry, 1)
	for iteration in 16:
		_expect(Geometry.choose_feasible_direction(Vector2(340.0, 400.0), Vector2.RIGHT, 40.0, geometry, 1) == first, "repeatability: identical input changed at iteration %d" % iteration)
	var free: Dictionary = Geometry.choose_feasible_direction(Vector2(500.0, 240.0), Vector2.RIGHT, 20.0, geometry, 1)
	_expect(bool(free.ok) and not bool(free.detour) and free.direction == Vector2.RIGHT, "repeatability: a movable direct direction was not preferred")


func _expect(condition: bool, message: String) -> void: Assert.expect(condition, message, failures)
