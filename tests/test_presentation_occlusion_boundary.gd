extends SceneTree

const FrameScript := preload("res://src/presentation/presentation_frame.gd")
const ControllerScript := preload("res://src/presentation/occlusion/occlusion_controller.gd")


func _initialize() -> void:
	var failures: Array[String] = []
	var missing_art: Dictionary = FrameScript.build(1, 2, [{
		"stable_id": "actor/1", "visual_id": "ranger", "feet_anchor": Vector2.ZERO,
		"baseline_y": 0.0, "rank": 0,
	}])
	_expect(not bool(missing_art.get("ok", false)), "presentation frame accepted missing art box", failures)
	var raw_entries: Array[Dictionary] = [
		{"stable_id": "actor/1", "visual_id": "ranger", "feet_anchor": Vector2(4.0, 5.0), "baseline_y": 5.0, "rank": 0, "art_box": Rect2(0.0, 0.0, 8.0, 12.0)},
		{"stable_id": "foreground/1", "visual_id": "pillar", "feet_anchor": Vector2(4.0, 8.0), "baseline_y": 8.0, "rank": 0, "art_box": Rect2(2.0, 2.0, 8.0, 8.0)},
	]
	var built: Dictionary = FrameScript.build(3, 2, raw_entries)
	_expect(bool(built.get("ok", false)), "valid presentation frame rejected", failures)
	if bool(built.get("ok", false)):
		var frame: Variant = built["value"]
		raw_entries[0]["feet_anchor"] = Vector2(99.0, 99.0)
		_expect(frame.entries[0]["feet_anchor"] == Vector2(4.0, 5.0), "presentation frame retained a mutable source reference", failures)
		var plan_result: Dictionary = frame.occlusion_plan()
		_expect(bool(plan_result.get("ok", false)), "presentation frame could not produce occlusion plan", failures)
		if bool(plan_result.get("ok", false)):
			var plan: Variant = plan_result["value"]
			var report: Dictionary = plan.occlusion_report("actor/1")
			_expect(bool(report.get("occluded", false)) and (report.get("occluder_ids", []) as Array) == ["foreground/1"], "occlusion did not use front art geometry", failures)
			var controller: Variant = ControllerScript.new()
			_expect(bool(controller.adopt_plan(plan).get("ok", false)), "occlusion controller rejected detached plan", failures)
			_expect(bool(controller.set_cover("actor/1", 0.5).get("ok", false)), "occlusion cover update failed", failures)
			controller.update(0.1)
			_expect(controller.alpha("actor/1") < 1.0, "occlusion alpha did not transition", failures)
	# Tiny but real Y differences must take precedence over rank in both
	# frame order and the occlusion plan; approximate equality changes depth.
	var close_entries := raw_entries.duplicate(true)
	close_entries[0].baseline_y = 5.000001
	close_entries[0].rank = 0
	close_entries[1].baseline_y = 5.0
	close_entries[1].rank = 1
	var close_frame := FrameScript.build(4, 2, close_entries)
	_expect(close_frame.ok, "close-baseline frame rejected", failures)
	if close_frame.ok:
		_expect(close_frame.value.entries[0].stable_id == "foreground/1", "frame ignored a small baseline difference", failures)
		var close_plan: Dictionary = close_frame.value.occlusion_plan()
		_expect(close_plan.ok and close_plan.value.entries()[0].stable_id == close_frame.value.entries[0].stable_id,
			"frame and plan order disagree at close baselines", failures)
	for failure: String in failures:
		printerr("- %s" % failure)
	print("PASS test_presentation_occlusion_boundary.gd" if failures.is_empty() else "FAIL test_presentation_occlusion_boundary.gd")
	quit(0 if failures.is_empty() else 1)


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
