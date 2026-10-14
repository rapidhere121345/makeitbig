extends SceneTree

const ArenaPresenterScript := preload("res://src/presentation/arena_presenter.gd")

var _frame_calls := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	var presenter := ArenaPresenterScript.new()
	root.add_child(presenter)

	## An unconfigured presenter has no frame to project and must not invent actor
	## or rectangle art. Its report still exposes the stable integration contract.
	presenter.request_redraw()
	await process_frame
	var unconfigured: Dictionary = presenter.presentation_report()
	_expect(String(unconfigured.get("state", "")) == ArenaPresenterScript.STATE_UNCONFIGURED,
		"unconfigured presenter did not stay inert", failures)
	_expect(not bool(unconfigured.get("fallback_art", true)),
		"unconfigured presenter advertised fallback art", failures)
	_expect((unconfigured.get("contract", {}) as Dictionary).has("frame_keys"),
		"unconfigured report did not expose the frame contract", failures)

	presenter.configure(Callable(self, "_invalid_frame"))
	_expect(_frame_calls == 0, "configure pulled the frame before drawing", failures)
	presenter.request_redraw()
	await process_frame
	var invalid: Dictionary = presenter.presentation_report()
	_expect(String(invalid.get("state", "")) == ArenaPresenterScript.STATE_PRESENTATION_ERROR,
		"invalid frame did not expose a presentation error", failures)
	_expect(not bool(invalid.get("fallback_art", true)),
		"invalid frame advertised fallback art", failures)
	_expect(_frame_calls == 1, "presenter did not pull one frame during draw", failures)
	var contract: Dictionary = invalid.get("contract", {})
	_expect(String(contract.get("callback_direction", "")).begins_with("presenter pulls"),
		"report lost callback direction", failures)
	var extension: Dictionary = invalid.get("extension", {})
	_expect(String(extension.get("actors", "")) == "reserved",
		"report did not preserve the actor extension seam", failures)
	var layers: Array = contract.get("draw_layers", [])
	_expect(layers.has("decals") and layers.has("structure_shadows"),
		"report did not expose the static world passes", failures)

	presenter.queue_free()
	_finish(failures)


func _invalid_frame() -> Dictionary:
	_frame_calls += 1
	return {}


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)


func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print("ARENA_PRESENTER_PASS")
		quit(0)
		return
	for failure: String in failures:
		printerr("ARENA_PRESENTER_FAIL: " + failure)
	quit(1)
