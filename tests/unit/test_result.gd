extends SceneTree
## Shared failure result gate (src/core/result.gd).
##   godot --headless --path . --script res://tests/unit/test_result.gd

const CoreResult := preload("res://src/core/result.gd")

var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	var failure := CoreResult.failure("wrong_route")
	_expect(failure == {"ok": false, "error": "wrong_route"}, "failure carries exactly ok=false and the error code")
	_expect(failure.size() == 2, "failure has no extra fields")
	_expect(not bool(failure.get("ok", true)), "failure reports ok=false")
	failure["extra"] = 1
	_expect(CoreResult.failure("wrong_route").size() == 2, "each failure is a fresh dictionary")
	_expect(not CoreResult.failure("a").is_read_only(), "failure results stay mutable like the helpers they replaced")
	for message in failures:
		printerr(message)
	print("RESULT ", "pass" if failures.is_empty() else "fail", " checks=", checks)
	quit(0 if failures.is_empty() else 1)


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append("FAIL: " + message)
