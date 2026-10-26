extends SceneTree
## Shared collection helper gate (src/core/collections.gd).
##   godot --headless --path . --script res://tests/unit/test_collections.gd

const Collections := preload("res://src/core/collections.gd")

var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	var values: Array = ["b", "a", "c", "a", "d"]
	var excluded: Array = ["c", "x"]
	_expect(Collections.string_array_difference(values, excluded) == ["b", "a", "d"], "difference keeps first-seen order and drops duplicates")
	_expect(Collections.sorted_string_array_difference(values, excluded) == ["a", "b", "d"], "sorted difference orders ascending")
	_expect(Collections.string_array_difference([&"p", &"q", &"r"], ["q"]) == ["p", "r"], "StringName entries are coerced to strings before comparing")
	_expect(Collections.string_array_difference([], ["a"]).is_empty(), "an empty input has an empty difference")
	_expect(Collections.string_array_difference(["a"], []) == ["a"], "an empty exclusion keeps everything")
	_expect(Collections.string_array_difference(null, ["a"]).is_empty(), "a non-array input counts as empty")
	_expect(Collections.string_array_difference(["a"], null) == ["a"], "a non-array exclusion counts as empty")
	_expect(Collections.sorted_string_array_difference({"a": 1}, []).is_empty(), "sorted difference tolerates a non-array input")
	var typed: Array[String] = ["z", "y"]
	_expect(Collections.string_array_difference(typed, ["y"]) == ["z"], "typed string arrays are accepted")
	_expect(values == ["b", "a", "c", "a", "d"], "inputs are not mutated")
	for message in failures:
		printerr(message)
	print("COLLECTIONS ", "pass" if failures.is_empty() else "fail", " checks=", checks)
	quit(0 if failures.is_empty() else 1)


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append("FAIL: " + message)
