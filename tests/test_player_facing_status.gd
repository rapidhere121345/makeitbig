extends SceneTree

const Status := preload("res://src/presentation/player_facing_status.gd")
const Assert := preload("res://tests/helpers/assert.gd")


func _initialize() -> void:
	var failures: Array[String] = []
	_expect(Status.message("candidate_not_selected") == "Select a revealed future outcome first.", "raw forge error was not translated", failures)
	_expect(Status.message("inscribe_not_legal") == "This item has no eligible new affix to inscribe.", "illegal inscribe did not explain the legal boundary", failures)
	_expect(Status.message("rewrite_not_legal") == "This affix has no eligible family to rewrite.", "illegal rewrite did not explain the legal boundary", failures)
	_expect(Status.message("refine_not_legal") == "This affix is already at its highest tier and cannot be refined.", "max-tier refine did not explain the legal boundary", failures)
	var forge := Status.message("Forge rejected: candidate_not_selected")
	_expect("Forge failed" in forge and "candidate_not_selected" not in forge, "prefixed forge error leaked its internal code", failures)
	var persisted := Status.message("Tutorial complete (generation 7 / slot A).")
	_expect("Ranger basics tutorial complete" in persisted and "generation 7" in persisted and "slot A" in persisted, "persistence suffix lost readable evidence", failures)
	_expect(Status.message("proxy_locked").contains("Manual") and not Status.message("proxy_locked").contains("proxy_locked"), "contract gate was not readable", failures)
	_expect(Status.message("future_internal_code") == Status.GENERIC_FAILURE, "unknown internal code leaked to the player", failures)
	_expect(Status.message("Forged: White Ash Longbow gained Continuation tier III") == "Forged: White Ash Longbow gained Continuation tier III", "already-readable Chinese status was changed", failures)
	_expect(Status.failure("Salvage", "item_equipped").contains("Unequip") and not Status.failure("Salvage", "item_equipped").contains("item_equipped"), "action failure did not explain recovery", failures)
	var enemy_source := Status.failure_source_label("enemy/391/fan_ranged")
	_expect(enemy_source == "Fan-Shot Hunter" and not enemy_source.contains("391") and not enemy_source.contains("fan_ranged") and not enemy_source.contains("/"), "enemy failure source leaked machine data: " + enemy_source, failures)
	_expect(Status.failure_source_label("boss/sweep") == "Threshold Colossus sweep", "boss action was not translated", failures)
	_expect(Status.failure_source_label("hazard/moving_fireline") == "Moving Fireline", "hazard source was not translated", failures)
	_expect(Status.failure_source_label("enemy/391/void_burst") == Status.UNKNOWN_FAILURE_SOURCE, "unknown failure source was not made generic", failures)
	_expect(Status.failure_source_label("") == Status.UNKNOWN_FAILURE_SOURCE, "empty failure source was not made generic", failures)
	_finish(failures)


func _expect(condition: bool, message: String, failures: Array[String]) -> void: Assert.expect(condition, message, failures)


func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print("PASS  test_player_facing_status.gd")
		quit(0)
		return
	for failure: String in failures:
		printerr("- %s" % failure)
	quit(1)
