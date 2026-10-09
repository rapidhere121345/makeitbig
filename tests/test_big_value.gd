extends RefCounted

const BigValue = preload("res://src/core/big_value.gd")


func run() -> Array[String]:
	var errors: Array[String] = []
	_test_construction(errors)
	_test_equivalent_representations_and_ordering(errors)
	_test_arithmetic(errors)
	_test_formatting(errors)
	return errors


func _test_construction(errors: Array[String]) -> void:
	var zero = BigValue.from_float(0.0)
	_check(zero != null and zero.layer == 0 and zero.magnitude == 0.0, "zero must be canonical", errors)
	_check(BigValue.from_float(-1.0) == null, "negative float must be rejected", errors)
	_check(BigValue.from_float(NAN) == null, "NaN must be rejected", errors)
	_check(BigValue.from_float(INF) == null, "infinity must be rejected", errors)

	var power = BigValue.from_power10(400.0)
	_check(power.layer == 1 and _near(power.magnitude, 400.0), "10^400 must stay compressed", errors)
	var promoted = BigValue.from_float(1.0e308)
	_check(promoted.layer == 1 and _near(promoted.magnitude, 308.0), "large finite float must normalize to layer 1", errors)
	_check(BigValue.from_tetration10(-1) == null, "negative tetration height must be rejected", errors)
	_check(BigValue.from_tetration10(0).compare(BigValue.from_float(1.0)) == 0, "10^^0 must equal 1", errors)
	_check(BigValue.from_tetration10(3).layer == 1, "10^^3 must use layer 1", errors)
	_check(BigValue.from_tetration10(5).layer == 3, "10^^5 must use layer 3", errors)


func _test_equivalent_representations_and_ordering(errors: Array[String]) -> void:
	var ten := BigValue.from_float(10.0)
	var power_4 := BigValue.from_power10(4.0)
	_check(power_4.compare(BigValue.from_float(10000.0)) == 0,
		"10^4 power and ordinary representations must compare equal", errors)
	_check(power_4.compare(ten.pow_float(4.0)) == 0,
		"10^4 constructor and exponentiation representations must compare equal", errors)

	var power_100 := BigValue.from_power10(100.0)
	_check(power_100.compare(BigValue.from_float(1.0e100)) == 0,
		"10^100 power and ordinary representations must compare equal", errors)
	_check(power_100.compare(BigValue.from_components(1, 100.0)) == 0,
		"10^100 power and component representations must compare equal", errors)

	var power_400 := BigValue.from_power10(400.0)
	_check(power_400.compare(ten.pow_float(400.0)) == 0,
		"10^400 constructor and exponentiation representations must compare equal", errors)
	_check(power_400.compare(BigValue.from_components(1, 400.0)) == 0,
		"10^400 power and component representations must compare equal", errors)
	_check(power_400.compare(power_100) > 0 and power_100.compare(power_4) > 0,
		"10^4, 10^100, and 10^400 must be strictly ordered", errors)

	for exponent in [10, 100]:
		var by_exponentiation = BigValue.from_float(2.0).pow_float(float(exponent))
		var by_float = BigValue.from_float(pow(2.0, float(exponent)))
		_check(by_exponentiation.compare(by_float) == 0,
			"2^%d exponentiation and ordinary representations must compare equal" % exponent, errors)
	var power_2_2048 = BigValue.from_float(2.0).pow_float(2048.0)
	var power_2_2048_log = BigValue.from_power10(2048.0 * log(2.0) / log(10.0))
	_check(power_2_2048.compare(power_2_2048_log) == 0,
		"2^2048 exponentiation and compressed representations must compare equal", errors)
	_check(BigValue.from_float(2.0).pow_float(2048.0).compare(
		BigValue.from_float(2.0).pow_float(2047.0)) > 0,
		"2^n must compare above 2^(n-1) in compressed range", errors)

	var tower_10 := BigValue.from_tetration10(10)
	_check(tower_10.compare(BigValue.from_components(8, 1.0e10)) == 0,
		"10^^10 tetration and component representations must compare equal", errors)
	_check(tower_10.compare(BigValue.from_tetration10(9)) > 0,
		"10^^10 must compare above the adjacent lower tower", errors)
	_check(tower_10.compare(BigValue.from_tetration10(11)) < 0,
		"10^^10 must compare below the adjacent higher tower", errors)


func _test_arithmetic(errors: Array[String]) -> void:
	var two = BigValue.from_float(2.0)
	var three = BigValue.from_float(3.0)
	_check(_near(two.add(three).magnitude, 5.0), "2 + 3 must equal 5", errors)
	_check(_near(two.multiply(three).magnitude, 6.0), "2 * 3 must equal 6", errors)
	_check(_near(three.pow_float(2.0).magnitude, 9.0), "3^2 must equal 9", errors)
	_check(BigValue.from_float(0.0).pow_float(0.0).compare(BigValue.from_float(1.0)) == 0, "0^0 policy must be 1", errors)
	_check(BigValue.from_float(0.0).pow_float(-1.0) == null, "zero to a negative power must be rejected", errors)

	var huge = BigValue.from_power10(400.0)
	var huge_squared = huge.multiply(huge)
	_check(huge_squared.layer == 1 and _near(huge_squared.magnitude, 800.0), "10^400 squared must be 10^800", errors)
	var huge_sum = huge.add(huge)
	_check(huge_sum.layer == 1 and _near(huge_sum.magnitude, 400.301029995664), "equal layer-1 values must add in log space", errors)
	_check(huge.log10().compare(BigValue.from_float(400.0)) == 0, "log10 must lower a layer", errors)
	_check(BigValue.from_float(0.1).log10() == null, "negative logarithm must be outside BigValue domain", errors)
	_check(BigValue.from_tetration10(5).compare(BigValue.from_tetration10(4)) > 0, "higher normalized layer must compare larger", errors)


func _test_formatting(errors: Array[String]) -> void:
	_check(BigValue.from_float(0.0).to_short_string() == "0", "zero short format must be stable", errors)
	var trillion_text: String = BigValue.from_float(1000000000000.0).to_short_string()
	_check(trillion_text.begins_with("1") and trillion_text.ends_with("e12"), "large layer-0 values must use compact scientific notation, got %s" % trillion_text, errors)
	_check(BigValue.from_power10(400.0).to_short_string().begins_with("1e"), "layer 1 must use exponent notation", errors)
	_check(BigValue.from_tetration10(4).to_short_string().begins_with("10^^2"), "layer 2 must use tower notation", errors)


func _check(condition: bool, message: String, errors: Array[String]) -> void:
	if not condition:
		errors.append(message)


func _near(left: float, right: float, relative_epsilon: float = 1.0e-10) -> bool:
	return absf(left - right) <= relative_epsilon * maxf(1.0, absf(right))
