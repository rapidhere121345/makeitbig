extends SceneTree

const TEST_SCRIPTS: Array[Script] = [
	preload("res://tests/test_big_value.gd"),
	preload("res://tests/test_application_state.gd"),
	preload("res://tests/test_training_report_builder.gd"),
	preload("res://tests/test_combat_state_codec.gd"),
	preload("res://tests/test_scene_router.gd"),
	preload("res://tests/test_contract_plan.gd"),
	preload("res://tests/test_game_root.gd"),
	preload("res://tests/test_base_hub_screen.gd"),
	preload("res://tests/test_systems.gd"),
	preload("res://tests/test_piercing_arrow.gd"),
	preload("res://tests/test_persistence.gd"),
	preload("res://tests/test_content.gd"),
	preload("res://tests/test_fixed_tick_clock.gd"),
	preload("res://tests/test_prototype_debug_directives.gd"),
	preload("res://tests/test_prototype_debug_runtime.gd"),
]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	for test_script in TEST_SCRIPTS:
		var suite: Object = test_script.new()
		var suite_failures: Array[String] = suite.run()
		var suite_name: String = test_script.resource_path.get_file()
		if suite_failures.is_empty():
			print("PASS  %s" % suite_name)
		else:
			for failure in suite_failures:
				failures.append("%s: %s" % [suite_name, failure])

	if failures.is_empty():
		print("\nAll Make It Big checks passed.")
		quit(0)
		return

	printerr("\n%d check(s) failed:" % failures.size())
	for failure in failures:
		printerr("- %s" % failure)
	quit(1)
