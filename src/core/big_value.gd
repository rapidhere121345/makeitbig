class_name BigValue
extends RefCounted

## A non-negative, finite large number.
##
## Canonical representation:
##   layer 0: magnitude
##   layer 1: 10 ^ magnitude
##   layer 2: 10 ^ (10 ^ magnitude), and so on.
## Zero has the single representation (0, 0).  Negative values, NaN, infinity,
## negative layers, and logarithms whose result would be negative are outside
## this type's domain.  Public constructors return null for such input.

const LAYER0_LIMIT: float = 1.0e307
const LOG10_LAYER0_LIMIT: float = 307.0
const LOG10_FLOAT_MIN: float = -323.0
const COMPARE_INVALID: int = 2

var layer: int = 0
var magnitude: float = 0.0


func _init() -> void:
	pass


static func from_float(value: float) -> BigValue:
	if not _is_finite(value) or value < 0.0:
		return null
	return _make(0, value)


static func from_power10(exponent: float) -> BigValue:
	if not _is_finite(exponent):
		return null
	if exponent < LOG10_FLOAT_MIN:
		# Positive underflow is deliberately rounded to the canonical zero.
		return _make(0, 0.0)
	return _make(1, exponent)


static func from_tetration10(height: int) -> BigValue:
	# Uses the standard convention 10^^0 = 1.
	if height < 0:
		return null
	if height == 0:
		return _make(0, 1.0)
	if height == 1:
		return _make(0, 10.0)
	# 10^^2 = 10^10.  Every further step adds one stored layer.
	return _make(height - 2, 1.0e10)


static func from_components(value_layer: int, value_magnitude: float) -> BigValue:
	if value_layer < 0 or not _is_finite(value_magnitude):
		return null
	if value_layer == 0 and value_magnitude < 0.0:
		return null
	return _make(value_layer, value_magnitude)


func duplicate_value() -> BigValue:
	return _make(layer, magnitude)


func is_zero() -> bool:
	return layer == 0 and magnitude == 0.0


func compare(other: BigValue) -> int:
	if other == null:
		return COMPARE_INVALID
	if layer < other.layer:
		return -1
	if layer > other.layer:
		return 1
	if magnitude < other.magnitude:
		return -1
	if magnitude > other.magnitude:
		return 1
	return 0


func add(other: BigValue) -> BigValue:
	if other == null:
		return null
	if is_zero():
		return other.duplicate_value()
	if other.is_zero():
		return duplicate_value()

	if layer == 0 and other.layer == 0:
		var sum: float = magnitude + other.magnitude
		if _is_finite(sum):
			return from_float(sum)

	# At layer 1, adding in logarithmic space still changes the stored
	# exponent.  At higher layers that correction is below float precision.
	var own_log: BigValue = log10()
	var other_log: BigValue = other.log10()
	if own_log != null and other_log != null and own_log.layer == 0 and other_log.layer == 0:
		var high: float = maxf(own_log.magnitude, other_log.magnitude)
		var low: float = minf(own_log.magnitude, other_log.magnitude)
		var correction: float = 0.0
		if high - low < 17.0:
			correction = log(1.0 + pow(10.0, low - high)) / log(10.0)
		return from_power10(high + correction)
	return duplicate_value() if compare(other) >= 0 else other.duplicate_value()


func multiply(other: BigValue) -> BigValue:
	if other == null:
		return null
	if is_zero() or other.is_zero():
		return from_float(0.0)

	if layer == 0 and other.layer == 0:
		var product: float = magnitude * other.magnitude
		if _is_finite(product):
			return from_float(product)
		return from_power10(_float_log10(magnitude) + _float_log10(other.magnitude))

	# A finite multiplier changes a layer-1 exponent by log10(multiplier).
	if layer == 0:
		return _multiply_large_by_float(other, magnitude)
	if other.layer == 0:
		return _multiply_large_by_float(self, other.magnitude)

	var exponent: BigValue = log10().add(other.log10())
	return _pow10_big(exponent)


func pow_float(exponent: float) -> BigValue:
	if not _is_finite(exponent):
		return null
	# This library defines x^0, including 0^0, as the multiplicative identity.
	if exponent == 0.0:
		return from_float(1.0)
	if is_zero():
		return from_float(0.0) if exponent > 0.0 else null

	if layer == 0:
		var ordinary: float = pow(magnitude, exponent)
		if _is_finite(ordinary):
			return from_float(ordinary)
		var ordinary_log: float = _float_log10(magnitude) * exponent
		return from_power10(ordinary_log)

	var positive_log: BigValue = log10().multiply(from_float(absf(exponent)))
	if exponent > 0.0:
		return _pow10_big(positive_log)
	# Reciprocals smaller than the host float range round to zero.
	if positive_log.layer > 0 or positive_log.magnitude > -LOG10_FLOAT_MIN:
		return from_float(0.0)
	return from_power10(-positive_log.magnitude)


func log10() -> BigValue:
	# BigValue cannot encode a negative logarithm.
	if is_zero() or (layer == 0 and magnitude < 1.0):
		return null
	if layer == 0:
		return from_float(_float_log10(magnitude))
	return _make(layer - 1, magnitude)


func log10_float() -> float:
	# Convenience projection.  Results too large for float return +INF;
	# log10(0) returns -INF, matching common numeric libraries.
	if is_zero():
		return -INF
	if layer == 0:
		return _float_log10(magnitude)
	if layer == 1:
		return magnitude
	return INF


func to_short_string(significant_digits: int = 3) -> String:
	var digits: int = clampi(significant_digits, 1, 12)
	if is_zero():
		return "0"
	if layer == 0:
		if magnitude >= 1000000.0 or magnitude < 0.001:
			return _scientific_float(magnitude, digits)
		return String.num(magnitude, digits)
	if layer == 1:
		return "1e%s" % _compact_float(magnitude, digits)
	return "10^^%d(%s)" % [layer, _compact_float(magnitude, digits)]


func _to_string() -> String:
	return to_short_string()


static func _make(value_layer: int, value_magnitude: float) -> BigValue:
	var result := BigValue.new()
	result.layer = value_layer
	result.magnitude = value_magnitude
	result._normalize()
	return result


func _normalize() -> void:
	if layer == 0 and magnitude == 0.0:
		magnitude = 0.0
		return

	# Promote large ordinary floats so equivalent construction paths agree.
	if layer == 0 and magnitude > LAYER0_LIMIT:
		magnitude = _float_log10(magnitude)
		layer = 1

	# Collapse every layer that can be represented safely by the layer below.
	while layer > 0 and magnitude <= LOG10_LAYER0_LIMIT:
		magnitude = pow(10.0, magnitude)
		layer -= 1

	if layer == 0 and magnitude == 0.0:
		magnitude = 0.0


static func _pow10_big(exponent: BigValue) -> BigValue:
	if exponent == null:
		return null
	if exponent.layer == 0:
		return from_power10(exponent.magnitude)
	return _make(exponent.layer + 1, exponent.magnitude)


static func _multiply_large_by_float(large: BigValue, factor: float) -> BigValue:
	if factor == 0.0:
		return from_float(0.0)
	if large.layer == 1:
		return from_power10(large.magnitude + _float_log10(factor))
	# Finite factors are below the precision represented at layer 2+.
	return large.duplicate_value()


static func _float_log10(value: float) -> float:
	return log(value) / log(10.0)


static func _is_finite(value: float) -> bool:
	return not is_nan(value) and not is_inf(value)


static func _compact_float(value: float, digits: int) -> String:
	if absf(value) >= 1000000.0:
		return _scientific_float(value, digits)
	return String.num(value, digits)


static func _scientific_float(value: float, digits: int) -> String:
	if value == 0.0:
		return "0"
	var exponent: int = int(floor(log(absf(value)) / log(10.0)))
	var mantissa: float = value / pow(10.0, float(exponent))
	if absf(mantissa) >= 9.9999999995:
		mantissa /= 10.0
		exponent += 1
	elif absf(mantissa) < 1.0:
		mantissa *= 10.0
		exponent -= 1
	return "%se%d" % [String.num(mantissa, maxi(0, digits - 1)), exponent]
