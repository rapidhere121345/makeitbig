class_name PiercingArrowModel
extends RefCounted

## Pure, deterministic expectation model for Piercing Arrow.
## A generation consumes flight time plus the non-compressible minimum turn time.
## All descendants share the original arrow's lifetime.

const BASE_P: float = 0.25
const EPSILON: float = 0.000001

const STATE_CONVERGENT: String = "convergent"
const STATE_CRITICAL: String = "critical"
const STATE_EXPONENTIAL: String = "exponential"


static func geometric_expectation(p: float = BASE_P) -> float:
	if p < 0.0 or p >= 1.0:
		return INF
	return 1.0 / (1.0 - p)


static func generation_time(distance: float, speed: float, minimum_turn_time: float) -> float:
	if distance < 0.0 or speed <= 0.0 or minimum_turn_time < 0.0:
		return INF
	return distance / speed + minimum_turn_time


static func generation_count(
	shared_lifetime: float,
	distance: float,
	speed: float,
	minimum_turn_time: float
) -> int:
	if shared_lifetime < 0.0:
		return 0
	var step_time: float = generation_time(distance, speed, minimum_turn_time)
	if is_inf(step_time) or step_time <= 0.0:
		return 0
	return maxi(0, int(floor(shared_lifetime / step_time)))


static func growth_state(reproduction: float) -> String:
	if reproduction < 1.0 - EPSILON:
		return STATE_CONVERGENT
	if reproduction > 1.0 + EPSILON:
		return STATE_EXPONENTIAL
	return STATE_CRITICAL


static func evaluate(
	p: float = BASE_P,
	shared_lifetime: float = 2.4,
	distance: float = 180.0,
	speed: float = 600.0,
	minimum_turn_time: float = 0.2,
	has_spawn_split: bool = true,
	has_pack_mark: bool = true
) -> Dictionary:
	var safe_p: float = clampf(p, 0.0, 1.0)
	var step_time: float = generation_time(distance, speed, minimum_turn_time)
	var generations: int = generation_count(shared_lifetime, distance, speed, minimum_turn_time)
	# Without Spawn Split this is an ordinary one-arrow continuation chain.  Its
	# ratio is p (never branch-exponential for valid p).  Split + Pack Mark gives
	# two expected descendants per successful continuation, hence R = 2p.
	var reproduction: float = 2.0 * safe_p if has_spawn_split and has_pack_mark else safe_p
	var state: String = growth_state(reproduction)
	var total: BigValue = _finite_series(reproduction, generations)
	return {
		"p": safe_p,
		"R": reproduction,
		"g": generations,
		"generation_time": step_time,
		"state": state,
		"total_events": total,
		"total_events_float": _finite_series_float(reproduction, generations),
		"unbounded_geometric": geometric_expectation(safe_p) if not has_spawn_split else INF,
	}


static func _finite_series(reproduction: float, generations: int) -> BigValue:
	var terms: int = maxi(0, generations) + 1
	if reproduction == 0.0:
		return BigValue.from_float(1.0)
	if absf(reproduction - 1.0) <= EPSILON:
		return BigValue.from_float(float(terms))
	var ordinary: float = _finite_series_float(reproduction, generations)
	if not is_inf(ordinary) and not is_nan(ordinary):
		return BigValue.from_float(ordinary)

	# log10((R^n - 1) / (R - 1)); this remains representable when pow() does not.
	var leading_log: float = float(terms) * log(reproduction) / log(10.0)
	var correction: float = 0.0
	if leading_log < 16.0:
		correction = log(1.0 - pow(10.0, -leading_log)) / log(10.0)
	var result_log: float = leading_log + correction - log(reproduction - 1.0) / log(10.0)
	return BigValue.from_power10(result_log)


static func _finite_series_float(reproduction: float, generations: int) -> float:
	var terms: int = maxi(0, generations) + 1
	if reproduction == 0.0:
		return 1.0
	if absf(reproduction - 1.0) <= EPSILON:
		return float(terms)
	return (pow(reproduction, float(terms)) - 1.0) / (reproduction - 1.0)
