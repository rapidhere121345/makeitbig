extends RefCounted

const CombatStateCodec = preload("res://src/game/combat_state_codec.gd")
const SaveStore = preload("res://src/persistence/save_store.gd")
const Assert := preload("res://tests/helpers/assert.gd")


func run() -> Array[String]:
	var failures: Array[String] = []
	_test_geometry_and_shapes(failures)
	_test_hash_safe_conversion(failures)
	_test_canonical_hash(failures)
	return failures


func _test_geometry_and_shapes(failures: Array[String]) -> void:
	var geometry := CombatStateCodec.geometry_state(Vector2(1.234, -2.345), Vector2(0.5, -0.25), 4.5, 0.125)
	_expect(geometry == {
		"direction_x_milli": 500,
		"direction_y_milli": -250,
		"origin_x_milli": 1234,
		"origin_y_milli": -2345,
		"size_a_milli": 4500,
		"size_b_milli": 125,
	}, "geometry: millipixel encoding must remain exact", failures)
	var rect := CombatStateCodec.target_shape_state({"type": "rect", "rect": Rect2(1.25, -2.0, 3.5, 4.25)})
	_expect(rect == {"type": "rect", "x_milli": 1250, "y_milli": -2000, "width_milli": 3500, "height_milli": 4250},
		"shape: rect encoding must remain exact", failures)
	var fan := CombatStateCodec.target_shape_state({"type": "fan", "origin": Vector2(2.0, 3.0), "direction": Vector2.LEFT, "radius": 6.0, "half_angle": 0.75})
	_expect((fan.get("geometry", {}) as Dictionary).get("size_a_milli", -1) == 6000,
		"shape: fan must use the shared geometry codec", failures)
	_expect(CombatStateCodec.target_shape_state({"type": "unknown"}) == {},
		"shape: unknown shapes must retain empty-state behavior", failures)


func _test_hash_safe_conversion(failures: Array[String]) -> void:
	var source := {
		"z": Vector2(1.5, -2.25),
		"a": [Vector2i(3, 4), Rect2(0.5, 1.5, 2.0, 2.5)],
	}
	var converted: Dictionary = CombatStateCodec.hash_safe(source)
	_expect(converted.keys() == ["a", "z"], "hash: dictionary keys must be sorted textually", failures)
	_expect((converted.z as Dictionary) == {"x_milli": 1500, "y_milli": -2250},
		"hash: Vector2 must use millipixel fields", failures)
	_expect((converted.a[0] as Dictionary) == {"x": 3, "y": 4},
		"hash: nested Vector2i must use integer fields", failures)
	_expect((converted.a[1] as Dictionary) == {"x_milli": 500, "y_milli": 1500, "width_milli": 2000, "height_milli": 2500},
		"hash: nested Rect2 must use millipixel fields", failures)


func _test_canonical_hash(failures: Array[String]) -> void:
	var state := {"b": 2, "a": CombatStateCodec.hash_safe(Vector2(0.5, 1.25))}
	var canonical := SaveStore.canonical_json(state)
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(canonical.to_utf8_buffer())
	var expected := context.finish().hex_encode()
	_expect(CombatStateCodec.sha256_canonical(state) == expected,
		"hash: canonical SHA-256 must use SaveStore byte ordering", failures)


func _expect(condition: bool, detail: String, failures: Array[String]) -> void: Assert.expect(condition, detail, failures)
