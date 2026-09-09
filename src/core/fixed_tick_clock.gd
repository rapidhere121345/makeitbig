class_name FixedTickClock
extends RefCounted

## Converts presentation-frame time into a deterministic number of authority
## ticks. Gameplay code receives only whole ticks; it never receives frame
## delta. The fractional phase is presentation scheduling state and is excluded
## from save/replay semantics.

const DEFAULT_TICKS_PER_SECOND: int = 30
const PHASE_EPSILON: float = 0.000000001

var ticks_per_second: int
var phase: float = 0.0


func _init(rate: int = DEFAULT_TICKS_PER_SECOND) -> void:
	ticks_per_second = maxi(1, rate)


func reset() -> void:
	phase = 0.0


func consume_frame(frame_delta: float) -> int:
	if is_nan(frame_delta) or is_inf(frame_delta) or frame_delta <= 0.0:
		return 0
	phase += frame_delta * float(ticks_per_second)
	var whole_ticks: int = maxi(0, int(floor(phase + PHASE_EPSILON)))
	phase -= float(whole_ticks)
	if absf(phase) <= PHASE_EPSILON:
		phase = 0.0
	return whole_ticks

