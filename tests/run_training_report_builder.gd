extends SceneTree

const TestScript = preload("res://tests/test_training_report_builder.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = TestScript.new().run()
	if failures.is_empty():
		print("PASS  tests/test_training_report_builder.gd")
		quit(0)
		return
	for failure in failures:
		printerr(failure)
	quit(1)
