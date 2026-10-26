extends SceneTree

const CombatQueryScript := preload("res://src/runtime/geometry/combat_query.gd")
const Assert := preload("res://tests/helpers/assert.gd")

var failures: Array[String] = []


func _initialize() -> void:
	_test_shapes()
	_test_sweeps()
	_test_invalid_shapes()
	if failures.is_empty():
		print("PASS test_combat_query.gd")
		quit(0)
		return
	for failure: String in failures:
		printerr("- %s" % failure)
	quit(1)


func _test_shapes() -> void:
	_expect(CombatQueryScript.shape_contains({"type": "circle", "origin": Vector2.ZERO, "radius": 5.0}, Vector2(3.0, 4.0)), "combat query: circle boundary was rejected")
	_expect(CombatQueryScript.shape_contains({"type": "rect", "rect": Rect2(-2.0, -2.0, 4.0, 4.0)}, Vector2.ONE), "combat query: rectangle was rejected")
	_expect(CombatQueryScript.shape_contains({"type": "lane", "origin": Vector2.ZERO, "direction": Vector2.RIGHT, "length": 10.0, "width": 4.0}, Vector2(6.0, 1.0)), "combat query: lane was rejected")
	_expect(not CombatQueryScript.shape_contains({"type": "lane", "origin": Vector2.ZERO, "direction": Vector2.RIGHT, "length": 10.0, "width": 4.0}, Vector2(6.0, 3.0)), "combat query: lane width was ignored")
	_expect(CombatQueryScript.shape_contains({"type": "fan", "origin": Vector2.ZERO, "direction": Vector2.RIGHT, "half_angle": PI * 0.25, "radius": 10.0}, Vector2(6.0, 2.0)), "combat query: fan was rejected")
	_expect(not CombatQueryScript.shape_contains({"type": "fan", "origin": Vector2.ZERO, "direction": Vector2.RIGHT, "half_angle": PI * 0.25, "radius": 10.0}, Vector2(-6.0, 0.0)), "combat query: fan accepted a rear point")


func _test_sweeps() -> void:
	var contact: Variant = CombatQueryScript.swept_circle_contact(Vector2.ZERO, Vector2(20.0, 0.0), Vector2(10.0, 0.0), 2.0)
	_expect(contact is Vector2 and is_equal_approx((contact as Vector2).x, 8.0), "combat query: swept circle returned the wrong first contact")
	var initial: Variant = CombatQueryScript.swept_circle_contact(Vector2(10.0, 0.0), Vector2(10.0, 0.0), Vector2(10.0, 0.0), 2.0)
	_expect(initial is Vector2 and initial == Vector2(10.0, 0.0), "combat query: initial overlap was not detected")
	_expect(CombatQueryScript.swept_circle_contact(Vector2.ZERO, Vector2(4.0, 0.0), Vector2(10.0, 0.0), 1.0) == null, "combat query: disjoint sweep reported a hit")
	_expect(is_equal_approx(CombatQueryScript.distance_to_segment(Vector2(5.0, 3.0), Vector2.ZERO, Vector2(10.0, 0.0)), 3.0), "combat query: segment distance changed")


func _test_invalid_shapes() -> void:
	for shape: Dictionary in [
		{"type": "circle"},
		{"type": "circle", "origin": Vector2.ZERO, "radius": true},
		{"type": "circle", "origin": Vector2.ZERO, "radius": "5"},
		{"type": "rect", "rect": Rect2(0, 0, -10, 10)},
		{"type": "fan", "origin": Vector2.ZERO, "direction": Vector2.RIGHT, "half_angle": PI + 0.1, "radius": 10.0},
		{"type": "fan", "origin": Vector2.ZERO, "direction": Vector2.RIGHT, "half_angle": "0", "radius": 10.0},
		{"type": "lane", "origin": Vector2.ZERO, "length": 10.0, "width": 4.0},
		{"type": "lane", "origin": Vector2.ZERO, "direction": Vector2.RIGHT, "length": 10.0, "width": INF},
	]:
		_expect(not CombatQueryScript.shape_contains(shape, Vector2.ZERO), "combat query: malformed shape was accepted: %s" % str(shape))


func _expect(condition: bool, message: String) -> void: Assert.expect(condition, message, failures)
