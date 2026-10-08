extends SceneTree

const Status := preload("res://src/presentation/player_facing_status.gd")


func _initialize() -> void:
	var failures: Array[String] = []
	_expect(Status.message("candidate_not_selected") == "请先选择一个已揭示的未来结果。", "raw forge error was not translated", failures)
	_expect(Status.message("inscribe_not_legal") == "当前装备没有可合法添铸的新词条。", "illegal inscribe did not explain the legal boundary", failures)
	_expect(Status.message("rewrite_not_legal") == "当前词条没有可合法改写的家族。", "illegal rewrite did not explain the legal boundary", failures)
	_expect(Status.message("refine_not_legal") == "当前词条已是最高阶，无法再精炼。", "max-tier refine did not explain the legal boundary", failures)
	var forge := Status.message("锻造拒绝：candidate_not_selected")
	_expect("锻造未完成" in forge and "candidate_not_selected" not in forge, "prefixed forge error leaked its internal code", failures)
	var persisted := Status.message("Tutorial complete (generation 7 / slot A).")
	_expect("游侠基础教程已完成" in persisted and "存档代 7" in persisted and "槽位 A" in persisted, "persistence suffix lost readable evidence", failures)
	_expect(Status.message("proxy_locked").contains("Manual") and not Status.message("proxy_locked").contains("proxy_locked"), "contract gate was not readable", failures)
	_expect(Status.message("future_internal_code") == Status.GENERIC_FAILURE, "unknown internal code leaked to the player", failures)
	_expect(Status.message("锻造完成：白蜡长弓获得续行 III 阶") == "锻造完成：白蜡长弓获得续行 III 阶", "already-readable Chinese status was changed", failures)
	_expect(Status.failure("拆解", "item_equipped").contains("先卸下") and not Status.failure("拆解", "item_equipped").contains("item_equipped"), "action failure did not explain recovery", failures)
	var enemy_source := Status.failure_source_label("enemy/391/fan_ranged")
	_expect(enemy_source == "扇射游猎者" and not enemy_source.contains("391") and not enemy_source.contains("fan_ranged") and not enemy_source.contains("/"), "enemy failure source leaked machine data: " + enemy_source, failures)
	_expect(Status.failure_source_label("boss/sweep") == "阈门巨像的横扫", "boss action was not translated", failures)
	_expect(Status.failure_source_label("hazard/moving_fireline") == "移动火线", "hazard source was not translated", failures)
	_expect(Status.failure_source_label("enemy/391/void_burst") == Status.UNKNOWN_FAILURE_SOURCE, "unknown failure source was not made generic", failures)
	_expect(Status.failure_source_label("") == Status.UNKNOWN_FAILURE_SOURCE, "empty failure source was not made generic", failures)
	_finish(failures)


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)


func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print("PASS  test_player_facing_status.gd")
		quit(0)
		return
	for failure: String in failures:
		printerr("- %s" % failure)
	quit(1)
