extends SceneTree

const ActorMotorScript := preload("res://src/runtime/geometry/actor_motor.gd")
const GeometryQueryScript := preload("res://src/runtime/geometry/geometry_query.gd")

var failures: Array[String] = []


func _initialize() -> void:
	_test_multi_contact_corner()
	_test_multi_contact_narrow_gap()
	_test_long_displacement()
	_test_ring_nonzero_toi()
	_test_ring_tangent_and_reverse()
	_test_near_tangent()
	_test_deterministic_clearance_sweep()
	if failures.is_empty():
		print("PASS  test_footprint_edge_cases.gd")
		quit(0)
		return
	for failure: String in failures:
		printerr("- " + failure)
	quit(1)


func _test_multi_contact_corner() -> void:
	var motor := ActorMotorScript.new(1.0)
	motor.register_rect("vertical", Rect2(10.0, -20.0, 4.0, 30.0))
	motor.register_rect("horizontal", Rect2(-20.0, 10.0, 34.0, 4.0))
	var result: Dictionary = motor.move(Vector2.ZERO, Vector2(20.0, 20.0), Rect2(-100.0, -100.0, 300.0, 300.0))
	_expect(bool(result.get("ok", false)), "multi-contact: corner solve failed: %s" % str(result))
	_expect(motor.is_position_clear(result.position), "multi-contact: corner solve accepted an invalid position %s" % result.position)
	_expect((result.contacts as Array).size() == 2, "multi-contact: expected both corner contacts: %s" % str(result.contacts))


func _test_multi_contact_narrow_gap() -> void:
	var motor := ActorMotorScript.new(2.0)
	# Two nearly touching authored rectangles make a rounded narrow mouth.  A
	# first vertex hit must not project the center into the second rectangle.
	motor.register_rect("left", Rect2(61.959960938, -32.609390259, 2.164125919, 9.408182144))
	motor.register_rect("right", Rect2(64.009002686, -27.120042801, 21.808931351, 5.405274391))
	var result: Dictionary = motor.move(Vector2.ZERO, Vector2(150.0, -51.74124), Rect2(-1000.0, -1000.0, 3000.0, 3000.0))
	_expect(bool(result.get("ok", false)), "narrow-mouth: solver rejected a valid-start contact: %s" % str(result))
	_expect(motor.is_position_clear(result.position), "narrow-mouth: accepted an invalid endpoint %s" % result.position)


func _test_long_displacement() -> void:
	var motor := ActorMotorScript.new(2.0)
	# A long diagonal chord around a rounded rectangle corner needs more than
	# the historical eight contact iterations to consume the valid slide.
	motor.register_rect("corner", Rect2(10.0, -5.0, 3.0, 8.0))
	var result: Dictionary = motor.move(Vector2.ZERO, Vector2(120.0, 55.0), Rect2(-1000.0, -1000.0, 3000.0, 3000.0))
	_expect(bool(result.get("ok", false)), "long-displacement: solve failed: %s" % str(result))
	_expect(motor.is_position_clear(result.position), "long-displacement: endpoint invalid at %s" % result.position)
	_expect(result.remaining.length() < 0.001, "long-displacement: solver exhausted its budget with remainder %s after %d iterations" % [result.remaining, result.iterations])
	_expect(result.position.distance_to(Vector2.ZERO) > 80.0, "long-displacement: solver stopped too early at %s after %d iterations" % [result.position, result.iterations])


func _test_ring_tangent_and_reverse() -> void:
	var motor := ActorMotorScript.new(2.0)
	var center := Vector2(4.0, -7.0)
	_expect(motor.set_boundary({"type": "ring", "center": center, "inner_radius": 10.0, "outer_radius": 30.0}), "ring: boundary rejected")
	for outer: bool in [false, true]:
		var radial := Vector2.from_angle(0.371)
		var tangent := Vector2(-radial.y, radial.x)
		var limit := 10.0 + 2.0 if not outer else 30.0 - 2.0
		var start := center + radial * limit
		var tangent_result: Dictionary = motor.move(start, tangent * 7.0)
		_expect(bool(tangent_result.get("ok", false)) and motor.is_position_clear(tangent_result.position), "ring: tangent invalid on %s" % ("outer" if outer else "inner"))
		_expect((tangent_result.position - start).dot(tangent) > 5.0, "ring: tangent stalled on %s" % ("outer" if outer else "inner"))
		var reverse_motion := radial * 4.0 if not outer else -radial * 4.0
		var reverse_result: Dictionary = motor.move(tangent_result.position, reverse_motion)
		_expect(bool(reverse_result.get("ok", false)) and motor.is_position_clear(reverse_result.position), "ring: reverse invalid on %s" % ("outer" if outer else "inner"))
		_expect((reverse_result.position - tangent_result.position).dot(reverse_motion) > 3.0, "ring: reverse stalled on %s" % ("outer" if outer else "inner"))


func _test_ring_nonzero_toi() -> void:
	var motor := ActorMotorScript.new(0.0)
	_expect(motor.set_boundary({"type": "ring", "center": Vector2.ZERO, "inner_radius": 10.0, "outer_radius": 30.0}), "ring TOI: boundary rejected")
	var inner: Dictionary = motor.move(Vector2(20.0, 0.0), Vector2(-31.0, 0.0))
	_expect(bool(inner.get("ok", false)) and _near_vector(inner.position, Vector2(10.0, 0.0)), "ring TOI: inner hit crossed the hole or stopped at the wrong endpoint: %s" % str(inner))
	_expect(_contact_time(inner, "ring:inner") > 0.0, "ring TOI: inner contact was reduced to t=0")
	var outer: Dictionary = motor.move(Vector2(20.0, 0.0), Vector2(31.0, 0.0))
	_expect(bool(outer.get("ok", false)) and _near_vector(outer.position, Vector2(30.0, 0.0)), "ring TOI: outer hit crossed the boundary or stopped at the wrong endpoint: %s" % str(outer))
	_expect(_contact_time(outer, "ring:outer") > 0.0, "ring TOI: outer contact was reduced to t=0")


func _test_near_tangent() -> void:
	var query := GeometryQueryScript.new()
	query.register_circle("disc", Vector2.ZERO, 5.0)
	var radius := 1.0
	var start := Vector2(-20.0, 6.0002)
	var motion := Vector2(40.0, 0.0)
	var hits: Array[Dictionary] = query.sweep(start, motion, radius)
	_expect(hits.is_empty(), "near-tangent: a path outside the distance tolerance reported a hit: %s" % str(hits))
	var tangent_hits: Array[Dictionary] = query.sweep(Vector2(-20.0, 6.00000001), motion, radius)
	_expect(not tangent_hits.is_empty(), "near-tangent: represented tangent did not report a stable contact")


## A compact deterministic stress pass keeps the endpoint invariant covered across
## mixed rectangle corners and ring chords without making the focused test depend
## on random process state.  Starts inside a blocker are skipped because the
## public contract deliberately rejects those instead of authoring a recovery.
func _test_deterministic_clearance_sweep() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xC0111DE
	var checked := 0
	for trial in 256:
		var motor := ActorMotorScript.new(0.5 + rng.randf() * 5.5)
		for blocker_index in 3:
			var origin := Vector2(rng.randf_range(-180.0, 180.0), rng.randf_range(-120.0, 120.0))
			var size := Vector2(rng.randf_range(2.0, 24.0), rng.randf_range(2.0, 24.0))
			motor.register_rect("stress_%02d" % blocker_index, Rect2(origin, size))
		var start := Vector2(rng.randf_range(-180.0, 180.0), rng.randf_range(-120.0, 120.0))
		if not motor.is_position_clear(start):
			continue
		checked += 1
		var displacement := Vector2(rng.randf_range(-260.0, 260.0), rng.randf_range(-220.0, 220.0))
		var result: Dictionary = motor.move(start, displacement, Rect2(-240.0, -180.0, 480.0, 360.0))
		_expect(bool(result.get("ok", false)), "stress: valid start was rejected at trial %d" % trial)
		_expect(motor.is_position_clear(result.position, Rect2(-240.0, -180.0, 480.0, 360.0)), "stress: endpoint lost clearance at trial %d: %s" % [trial, str(result)])
	_expect(checked >= 200, "stress: too many trials were discarded as invalid starts (%d)" % checked)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _contact_time(result: Dictionary, blocker_id: String) -> float:
	for contact: Dictionary in result.get("contacts", []):
		if String(contact.get("blocker_id", "")) == blocker_id:
			return float(contact.get("time", -1.0))
	return -1.0


func _near_vector(left: Vector2, right: Vector2, tolerance: float = 0.0001) -> bool:
	return left.distance_to(right) <= tolerance
