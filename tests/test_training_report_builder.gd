extends RefCounted

const TrainingReportBuilder = preload("res://src/systems/training_report_builder.gd")
const Assert := preload("res://tests/helpers/assert.gd")


func run() -> Array[String]:
	var failures: Array[String] = []
	_test_seed_mapping(failures)
	_test_generation_sampling(failures)
	_test_cumulative_events_boundaries(failures)
	_test_action_precedence_and_order(failures)
	_test_report_shape_and_alias_isolation(failures)
	return failures


func _test_seed_mapping(failures: Array[String]) -> void:
	_expect(TrainingReportBuilder.training_seed("") == 0, "seed: short fingerprint must map to zero", failures)
	var fingerprint := "0000001234567" + "a".repeat(51)
	_expect(TrainingReportBuilder.training_seed(fingerprint) == 0x1234567,
		"seed: first 13 hex characters must map verbatim", failures)


func _test_generation_sampling(failures: Array[String]) -> void:
	_expect(TrainingReportBuilder.growth_sample_generations(-2) == [0],
		"sampling: negative generation must clamp to G0", failures)
	_expect(TrainingReportBuilder.growth_sample_generations(0) == [0],
		"sampling: G0 must return only G0", failures)
	_expect(TrainingReportBuilder.growth_sample_generations(1) == [0, 1],
		"sampling: two generations must both be retained", failures)
	_expect(TrainingReportBuilder.growth_sample_generations(10) == [0, 2, 4, 6, 8, 10],
		"sampling: long runs must use six evenly spaced generations", failures)


func _test_cumulative_events_boundaries(failures: Array[String]) -> void:
	_expect(_near(_layer0(TrainingReportBuilder.expected_cumulative_events(0.0, 4)), 1.0),
		"cumulative: non-positive R must produce one event", failures)
	_expect(_near(_layer0(TrainingReportBuilder.expected_cumulative_events(1.0, 4)), 5.0),
		"cumulative: critical R must use the linear finite series", failures)
	_expect(_near(_layer0(TrainingReportBuilder.expected_cumulative_events(2.0, 3)), 15.0),
		"cumulative: ordinary geometric sum must stay exact", failures)
	var huge: BigValue = TrainingReportBuilder.expected_cumulative_events(10.0, 400)
	_expect(huge != null and huge.layer == 1 and is_finite(huge.magnitude),
		"cumulative: overflowing totals must compress without NaN or INF", failures)
	_expect(TrainingReportBuilder.expected_cumulative_events(2.0, -1) != null
		and _near(_layer0(TrainingReportBuilder.expected_cumulative_events(2.0, -1)), 0.0),
		"cumulative: negative generation must produce zero", failures)


func _test_action_precedence_and_order(failures: Array[String]) -> void:
	var first := TrainingReportBuilder.action({
		"missing_interfaces": ["experimental_link", "breedable_event"],
		"growth_classification": "exponential",
	})
	_expect(first == "Add the Breedable Child Arrows interface so descendants can keep branching.",
		"action: breedable_event must outrank other gaps and growth advice", failures)
	var second := TrainingReportBuilder.action({"missing_interfaces": ["branch_target_history"]})
	_expect(second == "Add the Branch Target History interface to keep tracking branched descendants.",
		"action: branch history must outrank growth advice", failures)
	var fallback := TrainingReportBuilder.action({
		"missing_interfaces": ["lineage_lifetime_pause", "experimental_link"],
	})
	_expect(fallback.contains(", ") and fallback.contains("experimental_link"),
		"action: remaining interfaces must use sorted shared names and retain unknown ids", failures)
	_expect(TrainingReportBuilder.action({"growth_classification": "critical"}) == "Try a small increase in continuation chance, then test whether growth exceeds critical.",
		"action: critical growth sentence must remain unchanged", failures)


func _test_report_shape_and_alias_isolation(failures: Array[String]) -> void:
	var event_data := {"layer": 0, "magnitude": 9.0}
	var resolved := {
		"build_fingerprint": "0000001234567" + "a".repeat(51),
		"final_parameters": {"p": 0.75},
		"R": 2.0,
		"generation_count": 5,
		"total_events": event_data,
		"total_events_float": 63.0,
		"growth_classification": "exponential",
		"missing_interfaces": [],
	}
	var report: Dictionary = TrainingReportBuilder.build_report(resolved, "fixed_start")
	_expect(report.keys() == ["preset_id", "build_fingerprint", "training_seed", "p", "R", "g",
		"event_count", "event_count_display", "event_count_value", "growth_curve", "action", "state", "report"],
		"report: field order and complete schema must remain unchanged", failures)
	_expect(int(report.training_seed) == 0x1234567 and String(report.event_count_display) == "9.0",
		"report: seed and BigValue display must remain unchanged", failures)
	_expect(String(report.report) == "p=0.75, R=2.00, g=5, events=9.0: exponential",
		"report: summary string must remain byte-for-byte unchanged", failures)
	var curve: Array = report.growth_curve
	_expect(curve.size() == 6 and int(curve[0].generation) == 0 and int(curve[5].generation) == 5,
		"report: curve must include G0 and Gg", failures)
	event_data["magnitude"] = 123.0
	_expect(float((report.event_count_value as Dictionary).magnitude) == 9.0,
		"report: event count payload must be deep-copied", failures)


func _expect(condition: bool, detail: String, failures: Array[String]) -> void: Assert.expect(condition, detail, failures)


func _layer0(value: BigValue) -> float:
	return value.magnitude if value != null and value.layer == 0 else NAN


func _near(left: float, right: float) -> bool:
	return absf(left - right) <= 1.0e-10
