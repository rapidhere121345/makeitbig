extends SceneTree
const Suite := preload("res://tests/test_base_hub_screen.gd")
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var failures: Array[String] = Suite.new().run()
	for failure: String in failures: printerr(failure)
	print("TOWN_HUB ", "PASS" if failures.is_empty() else "FAIL", " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
