extends SceneTree
const Trace = preload("res://src/presentation/training_trace_view.gd")
var failures: Array[String] = []

func _initialize() -> void:
	var view = Trace.new()
	view.present([
		{"generation":0,"events_display":"10","magnitude":10.0},
		{"generation":5,"events_display":"10","magnitude":10.0},
	])
	_expect(view.axis_caption().contains("same event count"), "flat axis must be described before draw")
	_expect(is_equal_approx(float(view.trace_report().flat_decade),1.0), "flat decade derived from current report")
	view.present([
		{"generation":0,"events_display":"1","magnitude":1.0},
		{"generation":5,"events_display":"10","magnitude":10.0},
	])
	_expect(not view.axis_caption().contains("same event count"), "flat caption must not leak across reports")
	_expect(view.trace_report().flat_decade == null, "nonflat JSON report uses null, not NaN")
	view.present([
		{"generation":0,"events_display":"1","magnitude":1.0},
		{"generation":5,"events_display":"10^^3(1.25)"},
	])
	_expect(view.trace_report().mode == "order" and view.trace_report().magnitudes == [1.0,null], "tower notation must not get a fabricated value")
	_expect(view.axis_caption().contains("not used"), "order-only caption")
	var serialized := JSON.stringify(view.trace_report())
	_expect(JSON.parse_string(serialized).events_display == ["1","10^^3(1.25)"], "exact display values survive report serialization")
	view.present([])
	_expect(not view.is_drawing() and view.trace_report().point_count == 0, "clearing report removes old points")
	view.free()
	for failure in failures:
		printerr(failure)
	print("PASS  test_training_trace_view.gd" if failures.is_empty() else "FAIL test_training_trace_view.gd")
	quit(0 if failures.is_empty() else 1)

func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
