extends SceneTree

const ActorMotorScript := preload("res://src/runtime/geometry/actor_motor.gd")
const GeometryQueryScript := preload("res://src/runtime/geometry/geometry_query.gd")

var failures: Array[String] = []


func _initialize() -> void:
	_test_public_data_api()
	_test_empty_field()
	_test_rect_head_on_and_tangent_slide()
	_test_convex_polygon_diagonal()
	_test_circle_start_contact_and_reverse_escape()
	_test_start_inside_is_not_exempt()
	_test_polygon_corner_slide_preserves_clearance()
	_test_inner_corner_and_multi_contact_order()
	_test_narrow_channel()
	_test_rect_boundary()
	_test_corridor_boundary()
	_test_ring_boundary()
	_test_ring_exact_tick1_clearance()
	_test_ring_curved_tangents_and_reversal()
	_test_ring_and_blocker_intersection()
	_test_boundary_results_are_stable()
	_test_fixed_tick_rates()
	if failures.is_empty():
		print("PASS  test_actor_motor.gd")
		quit(0)
		return
	for failure: String in failures:
		printerr("- " + failure)
	quit(1)


func _test_public_data_api() -> void:
	var query := GeometryQueryScript.new()
	_expect(query.register({"id": "z-wall", "kind": "rect", "rect": Rect2(10.0, -4.0, 2.0, 8.0)}), "api: rect registration failed")
	_expect(query.register("a-circle", {"kind": "circle", "center": Vector2(30.0, 0.0), "radius": 2.0}), "api: circle registration failed")
	_expect(query.register_polygon("m-polygon", PackedVector2Array([Vector2(40.0, 0.0), Vector2(44.0, 0.0), Vector2(40.0, 4.0)])), "api: polygon registration failed")
	var snapshot: Array[Dictionary] = query.snapshot()
	_expect(snapshot.size() == 3, "api: snapshot did not retain all blockers")
	_expect(query.blocker_ids() == ["a-circle", "m-polygon", "z-wall"], "api: snapshot order depends on registration order")
	_expect(not query.is_position_clear(Vector2(30.0, 0.0), 0.5), "api: circle overlap was reported clear")
	_expect(query.is_position_clear(Vector2(0.0, 0.0), 0.5), "api: empty point was reported blocked")
	var hits: Array[Dictionary] = query.sweep(Vector2(0.0, 0.0), Vector2(50.0, 0.0), 0.5)
	var first_physical_id := ""
	var first_physical_time := INF
	for hit: Dictionary in hits:
		if float(hit.get("time", INF)) < first_physical_time:
			first_physical_time = float(hit.get("time", INF))
			first_physical_id = String(hit.get("blocker_id", ""))
	_expect(first_physical_id == "z-wall", "api: sweep did not expose the first physical hit")
	query.clear()
	_expect(query.snapshot().is_empty() and query.sweep(Vector2.ZERO, Vector2.ONE, 1.0).is_empty(), "api: clear retained blocker data")


func _test_empty_field() -> void:
	var motor := ActorMotorScript.new(1.25)
	var start := Vector2(1.25, -2.75)
	var displacement := Vector2(17.5, 6.25)
	var result: Dictionary = motor.move(start, displacement, Rect2(-100.0, -100.0, 400.0, 400.0))
	_expect(_near_vector(result.position, start + displacement), "empty: displacement was not preserved")
	_expect(not bool(result.blocked) and (result.contacts as Array).is_empty(), "empty: field reported a false collision")
	_expect(_near_vector(result.remaining, Vector2.ZERO), "empty: completed movement retained a remainder")
	_expect(int(result.iterations) == 1, "empty: fixed tick did not complete in one query")


func _test_rect_head_on_and_tangent_slide() -> void:
	var motor := ActorMotorScript.new(2.0)
	_expect(motor.register_rect("wall", Rect2(10.0, 0.0, 4.0, 20.0)), "rect: registration failed")
	var head_on: Dictionary = motor.move(Vector2.ZERO, Vector2(30.0, 0.0), Rect2(-100.0, -100.0, 300.0, 300.0))
	_expect(_near(float(head_on.position.x), 8.0) and _near(float(head_on.position.y), 0.0), "rect: head-on sweep crossed the expanded face")
	_expect(bool(head_on.blocked) and (head_on.contacts as Array).size() == 1, "rect: head-on collision metadata is incomplete")
	if not (head_on.contacts as Array).is_empty():
		var contact: Dictionary = (head_on.contacts as Array)[0]
		_expect(String(contact.blocker_id) == "wall" and _near_vector(contact.normal, Vector2.LEFT), "rect: head-on normal is unstable")
		_expect(_near(float(contact.time), 8.0 / 30.0), "rect: continuous hit time changed")
	_expect(motor.is_position_clear(head_on.position, Rect2(-100.0, -100.0, 300.0, 300.0)), "rect: resolved face position penetrates the blocker")

	# Start exactly on the rounded footprint's top contact.  The diagonal
	# request has an inward component and should keep its tangent component.
	var tangent: Dictionary = motor.move(Vector2(12.0, -2.0), Vector2(20.0, 20.0), Rect2(-100.0, -100.0, 300.0, 300.0))
	_expect(_near_vector(tangent.position, Vector2(32.0, -2.0)), "rect: tangent slide lost free-axis motion")
	_expect(bool(tangent.blocked), "rect: tangent collision was not reported")
	_expect(motor.is_position_clear(tangent.position, Rect2(-100.0, -100.0, 300.0, 300.0)), "rect: tangent slide entered the wall")


func _test_convex_polygon_diagonal() -> void:
	var motor := ActorMotorScript.new(1.0)
	var triangle := PackedVector2Array([Vector2(0.0, 0.0), Vector2(10.0, 0.0), Vector2(0.0, 10.0)])
	_expect(motor.register_polygon("slope", triangle), "polygon: registration failed")
	var result: Dictionary = motor.move(Vector2(8.0, 8.0), Vector2(-10.0, -10.0), Rect2(-100.0, -100.0, 300.0, 300.0))
	var expected_sum := 10.0 + sqrt(2.0)
	_expect(_near(float(result.position.x + result.position.y), expected_sum), "polygon: diagonal face did not stop at the circular offset")
	if (result.contacts as Array).is_empty():
		_expect(false, "polygon: diagonal contact metadata is missing")
	else:
		_expect(_near_vector((result.contacts as Array)[0].normal, Vector2(1.0, 1.0).normalized()), "polygon: diagonal normal was not returned")
	_expect(motor.is_position_clear(result.position), "polygon: diagonal stop penetrates the triangle")


func _test_circle_start_contact_and_reverse_escape() -> void:
	var motor := ActorMotorScript.new(2.0)
	_expect(motor.register_circle("boulder", Vector2(20.0, 0.0), 3.0), "circle: registration failed")
	var leaving: Dictionary = motor.move(Vector2(25.0, 0.0), Vector2(7.0, 0.0), Rect2(-100.0, -100.0, 300.0, 300.0))
	_expect(_near_vector(leaving.position, Vector2(32.0, 0.0)), "circle: reverse escape from t=0 contact was blocked")
	_expect(not bool(leaving.blocked), "circle: leaving a contact was incorrectly marked blocked")
	var entering: Dictionary = motor.move(Vector2(25.0, 0.0), Vector2(-7.0, 0.0), Rect2(-100.0, -100.0, 300.0, 300.0))
	_expect(_near_vector(entering.position, Vector2(25.0, 0.0)), "circle: t=0 contact allowed inward movement")
	_expect(bool(entering.blocked) and (entering.contacts as Array).size() == 1, "circle: t=0 contact was not exposed")
	_expect(motor.is_position_clear(entering.position), "circle: exact tangent was treated as penetration")


func _test_start_inside_is_not_exempt() -> void:
	var motor := ActorMotorScript.new(1.0)
	_expect(motor.register_circle("solid", Vector2.ZERO, 5.0), "inside: registration failed")
	var result: Dictionary = motor.move(Vector2.ZERO, Vector2(20.0, 0.0), Rect2(-100.0, -100.0, 300.0, 300.0))
	_expect(_near_vector(result.position, Vector2.ZERO), "inside: start-inside state was silently projected or exempted")
	_expect(bool(result.blocked) and not (result.contacts as Array).is_empty(), "inside: penetrating start did not produce a contact")
	if not (result.contacts as Array).is_empty():
		_expect(bool((result.contacts as Array)[0].penetrating), "inside: contact did not identify penetration")


func _test_polygon_corner_slide_preserves_clearance() -> void:
	## A straight edge tangent can reach the rounded Minkowski corner in one
	## tick.  The contact query must expose that continuation and the motor must
	## never commit a sub-epsilon penetration from a valid start.
	var motor := ActorMotorScript.new(6.0)
	var fence_corner := PackedVector2Array([
		Vector2(446.000671387, 517.499511719),
		Vector2(456.0, 518.437438965),
		Vector2(477.000183105, 556.87487793),
		Vector2(463.999450684, 563.437438965),
	])
	_expect(motor.register_polygon("fence-corner", fence_corner), "corner slide: registration failed")
	var start := Vector2(451.7878, 512.0161)
	_expect(motor.is_position_clear(start), "corner slide: authored tangent start is not clear")
	var position := start
	for _tick in 12:
		var result: Dictionary = motor.move(position, Vector2.LEFT * 1.6, Rect2(20.0, 20.0, 1496.0, 920.0))
		position = result.position
		_expect(motor.is_position_clear(position, Rect2(20.0, 20.0, 1496.0, 920.0)), "corner slide: motor committed a penetrating endpoint at %s" % position)


func _test_inner_corner_and_multi_contact_order() -> void:
	var motor := ActorMotorScript.new(1.0)
	# The free quadrant is x < 10, y < 10.  Both faces are reached at the
	# same continuous time, so a single normal must not win by registration order.
	_expect(motor.register_rect("vertical", Rect2(10.0, -20.0, 4.0, 30.0)), "corner: vertical registration failed")
	_expect(motor.register_rect("horizontal", Rect2(-20.0, 10.0, 34.0, 4.0)), "corner: horizontal registration failed")
	var into_corner: Dictionary = motor.move(Vector2.ZERO, Vector2(20.0, 20.0), Rect2(-100.0, -100.0, 300.0, 300.0))
	_expect(_near_vector(into_corner.position, Vector2(9.0, 9.0)), "corner: simultaneous contacts did not stop at the inner corner")
	_expect((into_corner.contacts as Array).size() == 2, "corner: multi-contact collision lost one normal")
	if (into_corner.contacts as Array).size() == 2:
		_expect(String((into_corner.contacts as Array)[0].blocker_id) == "horizontal" and String((into_corner.contacts as Array)[1].blocker_id) == "vertical", "corner: contact order was not blocker-id stable")
	var reverse: Dictionary = motor.move(into_corner.position, Vector2(-4.0, -7.0), Rect2(-100.0, -100.0, 300.0, 300.0))
	_expect(_near_vector(reverse.position, Vector2(5.0, 2.0)), "corner: reverse movement did not leave both contacts")
	_expect(not bool(reverse.blocked), "corner: outward reverse movement was reported as blocked")


func _test_narrow_channel() -> void:
	var motor := ActorMotorScript.new(3.0)
	_expect(motor.register_rect("upper", Rect2(20.0, -10.0, 12.0, 18.0)), "channel: upper registration failed")
	_expect(motor.register_rect("lower", Rect2(20.0, 12.0, 12.0, 18.0)), "channel: lower registration failed")
	var result: Dictionary = motor.move(Vector2.ZERO, Vector2(60.0, 0.0), Rect2(-100.0, -100.0, 300.0, 300.0))
	_expect(float(result.position.x) < 20.0, "channel: a gap narrower than the diameter admitted the actor")
	_expect(motor.is_position_clear(result.position), "channel: stop position penetrates a channel wall")
	_expect(bool(result.blocked), "channel: blocked passage did not report contact")


func _test_rect_boundary() -> void:
	var motor := ActorMotorScript.new(2.0)
	var bounds := Rect2(0.0, 0.0, 20.0, 20.0)
	_expect(motor.set_boundary({"type": "rect", "rect": bounds}), "rect boundary: registration failed")
	var result: Dictionary = motor.move(Vector2(10.0, 10.0), Vector2(-30.0, 0.0), bounds)
	_expect(_near_vector(result.position, Vector2(2.0, 10.0)), "rect boundary: continuous sweep did not stop at the footprint boundary")
	_expect(bool(result.blocked) and motor.is_position_clear(result.position), "rect boundary: resolved position is invalid")
	var outside: Dictionary = motor.move(Vector2(-4.0, 10.0), Vector2(1.0, 0.0), bounds)
	_expect(_near_vector(outside.position, Vector2(-4.0, 10.0)), "rect boundary: an outside start was projected to a nearest walkable point")
	_expect(bool(outside.blocked), "rect boundary: outside start was silently exempted")
	var reverse: Dictionary = motor.move(Vector2(2.0, 10.0), Vector2(4.0, 0.0), bounds)
	_expect(_near_vector(reverse.position, Vector2(6.0, 10.0)) and not bool(reverse.blocked), "rect boundary: reverse movement from a boundary contact was blocked")

	var corner: Dictionary = motor.move(Vector2(10.0, 10.0), Vector2(-30.0, -30.0), bounds)
	_expect(_near_vector(corner.position, Vector2(2.0, 2.0)), "rect boundary: corner movement crossed the footprint boundary")
	_expect((corner.contacts as Array).size() == 2, "rect boundary: corner movement lost one boundary contact")


func _test_corridor_boundary() -> void:
	var motor := ActorMotorScript.new(3.0)
	var corridor := Rect2(0.0, 0.0, 100.0, 40.0)
	_expect(motor.set_boundary({"type": "corridor", "rect": corridor, "axis": "horizontal", "half_height": 10.0}), "corridor boundary: registration failed")
	var right_edge: Dictionary = motor.move(Vector2(50.0, 20.0), Vector2(100.0, 0.0))
	_expect(_near_vector(right_edge.position, Vector2(97.0, 20.0)), "corridor boundary: outer x edge ignored footprint clearance")
	_expect(bool(right_edge.blocked) and motor.is_position_clear(right_edge.position), "corridor boundary: x edge result was invalid")
	var top_edge: Dictionary = motor.move(Vector2(50.0, 20.0), Vector2(0.0, -100.0))
	_expect(_near_vector(top_edge.position, Vector2(50.0, 13.0)), "corridor boundary: inner y edge ignored footprint clearance")
	_expect(bool(top_edge.blocked) and motor.is_position_clear(top_edge.position), "corridor boundary: y edge result was invalid")
	var tangent: Dictionary = motor.move(Vector2(50.0, 13.0), Vector2(10.0, 0.0))
	_expect(_near_vector(tangent.position, Vector2(60.0, 13.0)) and not bool(tangent.blocked), "corridor boundary: tangent movement was blocked")


func _test_ring_boundary() -> void:
	var motor := ActorMotorScript.new(2.0)
	var center := Vector2.ZERO
	var inner := 10.0
	var outer := 30.0
	_expect(motor.set_boundary({"type": "ring", "center": center, "inner_radius": inner, "outer_radius": outer}), "ring boundary: registration failed")
	var inner_contact := Vector2.RIGHT * (inner + 2.0)
	var enter_hole: Dictionary = motor.move(inner_contact, Vector2.LEFT * 20.0)
	_expect(_near_vector(enter_hole.position, inner_contact), "ring boundary: movement entered the inner hole")
	_expect(bool(enter_hole.blocked) and motor.is_position_clear(enter_hole.position), "ring boundary: inner contact was not reported as a stable boundary")
	var inner_tangent: Dictionary = motor.move(inner_contact, Vector2.UP * 5.0)
	_expect(_near_vector(inner_tangent.position, inner_contact + Vector2.UP * 5.0), "ring boundary: tangent movement did not continue")
	var inner_reverse: Dictionary = motor.move(inner_contact, Vector2.RIGHT * 5.0)
	_expect(_near_vector(inner_reverse.position, inner_contact + Vector2.RIGHT * 5.0) and not bool(inner_reverse.blocked), "ring boundary: reverse movement could not escape the inner edge")

	var outer_contact := Vector2.RIGHT * (outer - 2.0)
	var leave_ring: Dictionary = motor.move(outer_contact, Vector2.RIGHT * 20.0)
	_expect(_near_vector(leave_ring.position, outer_contact), "ring boundary: movement crossed the outer edge")
	_expect(bool(leave_ring.blocked) and motor.is_position_clear(leave_ring.position), "ring boundary: outer contact was not reported as a stable boundary")
	var outer_reverse: Dictionary = motor.move(outer_contact, Vector2.LEFT * 5.0)
	_expect(_near_vector(outer_reverse.position, outer_contact - Vector2.RIGHT * 5.0) and not bool(outer_reverse.blocked), "ring boundary: reverse movement could not leave the outer contact")


func _test_boundary_results_are_stable() -> void:
	var motor := ActorMotorScript.new(2.0)
	_expect(motor.set_boundary({"type": "ring", "center": Vector2(12.0, -4.0), "inner_radius": 10.0, "outer_radius": 30.0}), "stability: ring registration failed")
	var start := Vector2(24.0, -4.0)
	var displacement := Vector2(20.0, 15.0)
	var first: Dictionary = motor.move(start, displacement)
	var second: Dictionary = motor.move(start, displacement)
	_expect(_near_vector(first.position, second.position), "stability: repeated ring result changed position")
	_expect(bool(first.blocked) == bool(second.blocked), "stability: repeated ring result changed blocked state")
	_expect(int(first.iterations) == int(second.iterations), "stability: repeated ring result changed iteration count")
	_expect((first.contacts as Array).size() == (second.contacts as Array).size(), "stability: repeated ring result changed contact count")
	if not (first.contacts as Array).is_empty() and not (second.contacts as Array).is_empty():
		var first_contact: Dictionary = (first.contacts as Array)[0]
		var second_contact: Dictionary = (second.contacts as Array)[0]
		_expect(String(first_contact.get("blocker_id", "")) == String(second_contact.get("blocker_id", "")), "stability: repeated ring result changed contact identity")
		_expect(_near(float(first_contact.get("time", 0.0)), float(second_contact.get("time", 0.0))), "stability: repeated ring result changed contact time")


func _test_ring_exact_tick1_clearance() -> void:
	var motor := ActorMotorScript.new(14.0)
	_expect(motor.set_boundary({"type": "ring", "center": Vector2(640.0, 434.0), "inner_radius": 97.6, "outer_radius": 209.84}), "ring tick1: boundary rejected")
	var start := Vector2(461.7138366699219, 515.0391845703125)
	var displacement := Vector2.LEFT * (245.0 / 30.0)
	_expect(motor.is_position_clear(start), "ring tick1: exact production spawn is not clear")
	var result: Dictionary = motor.move(start, displacement)
	_expect(bool(result.get("ok", false)) and motor.is_position_clear(result.position), "ring tick1: shared motor accepted an illegal footprint at %s" % result.position)
	_expect(start.distance_to(result.position) > 3.0, "ring tick1: tangent movement was discarded")
	_expect(result == motor.move(start, displacement), "ring tick1: identical input changed the result")
	var position: Vector2 = result.position
	for tick in 90:
		var moved: Dictionary = motor.move(position, displacement)
		_expect(motor.is_position_clear(moved.position), "ring tick1: consecutive tick %d committed an illegal footprint" % (tick + 2))
		position = moved.position
	var reverse: Dictionary = motor.move(result.position, -displacement)
	_expect(_near_vector(reverse.position, result.position - displacement) and not bool(reverse.blocked), "ring tick1: immediate reverse did not leave contact freely")


func _test_ring_curved_tangents_and_reversal() -> void:
	var center := Vector2(640.0, 434.0)
	for footprint: float in [14.0, 16.0]:
		var motor := ActorMotorScript.new(footprint)
		motor.set_boundary({"type": "ring", "center": center, "inner_radius": 97.6, "outer_radius": 209.84})
		for degrees: float in [0.0, 12.3, 45.0, 90.0, 137.0, 155.545, 180.0, 225.0, 270.0, 315.0, 359.0]:
			var radial := Vector2.from_angle(deg_to_rad(degrees))
			var tangent := Vector2(-radial.y, radial.x)
			for outer: bool in [false, true]:
				var limit := 209.84 - footprint if outer else 97.6 + footprint
				var start := center + radial * limit
				var free_normal := -radial if outer else radial
				var label := "ring r%d angle%s %s" % [int(footprint), degrees, "outer" if outer else "inner"]
				_expect(motor.is_position_clear(start), label + ": contact start is not clear")
				for sign_value: float in [-1.0, 1.0]:
					var motion := tangent * sign_value * (245.0 / 30.0)
					var moved: Dictionary = motor.move(start, motion)
					_expect(motor.is_position_clear(moved.position), label + ": tangent result is not clear")
					_expect((moved.position - start).dot(motion.normalized()) > 8.0, label + ": tangent movement stuck")
					_expect(moved == motor.move(start, motion), label + ": tangent input is unstable")
					if not outer:
						_expect(_near_vector(moved.position, start + motion), label + ": inner tangent lost free movement")
					var into_edge := motion - free_normal * 4.0
					var sliding: Dictionary = motor.move(start, into_edge)
					_expect(motor.is_position_clear(sliding.position) and (sliding.position - start).dot(motion.normalized()) > 8.0, label + ": mixed input lost tangent clearance/movement")
					var reverse: Dictionary = motor.move(sliding.position, free_normal * 4.0)
					_expect(motor.is_position_clear(reverse.position) and not bool(reverse.blocked), label + ": reverse escape was blocked")
					_expect(_near_vector(reverse.position, sliding.position + free_normal * 4.0), label + ": reverse escape lost displacement")
				# Recompute the tangent each tick, so both directions stay on the
				# outer edge instead of relying on a once-fixed world direction.
				if outer:
					var position := start
					for sign_value: float in [-1.0, 1.0]:
						position = start
						for tick in 120:
							var current_radial := (position - center).normalized()
							var motion := Vector2(-current_radial.y, current_radial.x) * sign_value * (245.0 / 30.0)
							var moved: Dictionary = motor.move(position, motion)
							_expect(bool(moved.get("ok", false)) and motor.is_position_clear(moved.position), label + ": orbit footprint illegal at tick %d" % tick)
							_expect((moved.position - position).dot(motion.normalized()) > 8.0, label + ": orbit stalled or jittered at tick %d" % tick)
							position = moved.position
					var idle: Dictionary = motor.move(position, Vector2.ZERO)
					_expect(idle.position == position, label + ": idle contact jittered")
					var head_on: Dictionary = motor.move(start, radial * 5.0)
					_expect(_near_vector(head_on.position, start), label + ": outward-only contact jittered")
				else:
					var across_hole: Dictionary = motor.move(start, -radial * 500.0)
					_expect(_near_vector(across_hole.position, start) and bool(across_hole.blocked), label + ": swept displacement crossed the hole")


func _test_ring_and_blocker_intersection() -> void:
	for footprint: float in [14.0, 16.0]:
		var motor := ActorMotorScript.new(footprint)
		var center := Vector2(640.0, 434.0)
		motor.set_boundary({"type": "ring", "center": center, "inner_radius": 97.6, "outer_radius": 209.84})
		# This wall cuts through the outer circle. Its footprint offset and the
		# circle must both constrain the same submitted slide and its reversal.
		motor.register_rect("ring-crossing-wall", Rect2(600.0, 540.0, 260.0, 40.0))
		var limit := 209.84 - footprint
		var start := center + Vector2.from_angle(0.35) * limit
		var position := start
		for tick in 30:
			var moved: Dictionary = motor.move(position, Vector2(4.0, 9.0))
			_expect(motor.is_position_clear(moved.position), "ring+wall r%d: illegal footprint at tick %d" % [int(footprint), tick])
			_expect(moved == motor.move(position, Vector2(4.0, 9.0)), "ring+wall: same input changed the result")
			position = moved.position
		_expect(position.y <= 540.0 - footprint + GeometryQueryScript.CONTACT_EPSILON, "ring+wall: crossed the wall")
		_expect(start.distance_to(position) > 15.0, "ring+wall: legal slide was discarded")
		var reverse: Dictionary = motor.move(position, Vector2(-4.0, -9.0))
		_expect(motor.is_position_clear(reverse.position) and position.distance_to(reverse.position) > 9.0, "ring+wall: immediate reverse stuck")
		# A large outer tangent is retracted into the disk, then still swept
		# against the inner hole and static blockers; endpoint projection alone
		# would incorrectly tunnel through this thin wall on the chord.
		motor.clear_geometry()
		motor.register_rect("chord-wall", Rect2(685.0, 500.0, 8.0, 180.0))
		var chord_start := center + Vector2.RIGHT * limit
		var large: Dictionary = motor.move(chord_start, Vector2.DOWN * 1000.0)
		_expect(motor.is_position_clear(large.position) and bool(large.blocked), "ring+wall: large curved tangent returned an illegal footprint")
		_expect(large.position.x >= 693.0 + footprint - GeometryQueryScript.CONTACT_EPSILON, "ring+wall: curved continuation crossed the blocker")
		motor.clear_geometry()
		motor.set_boundary({"type": "ring", "center": center, "inner_radius": 174.0, "outer_radius": 209.84})
		var narrow: Dictionary = motor.move(chord_start, Vector2.DOWN * 1000.0)
		_expect(motor.is_position_clear(narrow.position), "narrow ring: curved continuation ended in the hole")
		var found_inner := false
		for contact: Dictionary in narrow.contacts:
			found_inner = found_inner or String(contact.get("blocker_id", "")) == "ring:inner"
		_expect(found_inner, "narrow ring: curved continuation skipped the hole sweep")


func _test_fixed_tick_rates() -> void:
	var finishes: Array[Vector2] = []
	for rate: int in [30, 60, 144, 240]:
		var motor := ActorMotorScript.new(1.0)
		motor.register_rect("long-wall", Rect2(50.0, -100.0, 3.0, 200.0))
		var position := Vector2.ZERO
		var tick_displacement := Vector2(120.0, 37.0) / float(rate)
		for _tick in rate:
			var step: Dictionary = motor.move(position, tick_displacement, Rect2(-1000.0, -1000.0, 3000.0, 3000.0))
			position = step.position
		finishes.append(position)
		_expect(_near(position.x, 49.0) and _near(position.y, 37.0), "tick: %d Hz crossed or drifted along the wall at %s" % [rate, position])
	for finish: Vector2 in finishes:
		_expect(finish.distance_to(finishes[0]) <= 0.0001, "tick: cumulative result changed with render/tick rate")


func _near(left: float, right: float, tolerance: float = 0.0001) -> bool:
	return absf(left - right) <= tolerance


func _near_vector(left: Vector2, right: Vector2, tolerance: float = 0.0001) -> bool:
	return left.distance_to(right) <= tolerance


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
