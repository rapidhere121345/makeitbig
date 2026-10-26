extends RefCounted
const Assert := preload("res://tests/helpers/assert.gd")


func run() -> Array[String]:
	var failures: Array[String] = []
	_check_state(failures, 0.49, PiercingArrowModel.STATE_CONVERGENT, 0.98)
	_check_state(failures, 0.50, PiercingArrowModel.STATE_CRITICAL, 1.0)
	_check_state(failures, 0.61, PiercingArrowModel.STATE_EXPONENTIAL, 1.22)

	var geometric: float = PiercingArrowModel.geometric_expectation()
	_expect(failures, absf(geometric - 4.0 / 3.0) < 0.000001, "base no-split expectation must be 4/3")

	var before_boundary: Dictionary = PiercingArrowModel.evaluate(0.25, 0.699, 100.0, 200.0, 0.2)
	var on_boundary: Dictionary = PiercingArrowModel.evaluate(0.25, 0.7, 100.0, 200.0, 0.2)
	var additive_turn: Dictionary = PiercingArrowModel.evaluate(0.25, 1.019, 10.0, 1000.0, 0.5)
	_expect(failures, int(before_boundary["g"]) == 0, "lifetime just below a generation must keep g=0")
	_expect(failures, int(on_boundary["g"]) == 1, "exact lifetime boundary must admit the next generation")
	_expect(failures, int(additive_turn["g"]) == 1, "flight and non-compressible turn times must add")
	_expect(failures, PiercingArrowModel.generation_count(1.0, 10.0, 0.0, 0.2) == 0, "zero speed must be safe")
	var no_split: Dictionary = PiercingArrowModel.evaluate(0.61, 2.0, 100.0, 200.0, 0.1, false, true)
	_expect(failures, str(no_split["state"]) == PiercingArrowModel.STATE_CONVERGENT, "ordinary continuation must not be branch-exponential")
	_expect(failures, absf(float(no_split["unbounded_geometric"]) - 1.0 / 0.39) < 0.000001, "no-split infinite geometric expectation must be 1/(1-p)")
	return failures


func _check_state(failures: Array[String], p: float, expected_state: String, expected_r: float) -> void:
	var result: Dictionary = PiercingArrowModel.evaluate(p, 2.0, 100.0, 200.0, 0.1)
	_expect(failures, str(result["state"]) == expected_state, "p=%s should be %s" % [p, expected_state])
	_expect(failures, absf(float(result["R"]) - expected_r) < 0.000001, "p=%s should produce R=%s" % [p, expected_r])
	_expect(failures, int(result["g"]) == 3, "d/v + turn time should produce g=3")
	var expected_total: float = 3.881592 if p == 0.49 else (4.0 if p == 0.5 else 5.524248)
	_expect(failures, absf(float(result["total_events_float"]) - expected_total) < 0.00001, "unexpected finite event sum for p=%s" % p)


func _expect(failures: Array[String], condition: bool, message: String) -> void: Assert.expect(condition, message, failures)
