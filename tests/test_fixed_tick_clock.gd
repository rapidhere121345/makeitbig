extends RefCounted

const FixedTickClock = preload("res://src/core/fixed_tick_clock.gd")
const Assert := preload("res://tests/helpers/assert.gd")


func run() -> Array[String]:
	var failures: Array[String] = []
	_test_render_rates(failures)
	_test_invalid_and_batched_frames(failures)
	return failures


func _test_render_rates(failures: Array[String]) -> void:
	const DURATION_SECONDS := 120
	const EXPECTED_TICKS := DURATION_SECONDS * FixedTickClock.DEFAULT_TICKS_PER_SECOND
	for render_rate in [30, 60, 144]:
		var clock := FixedTickClock.new()
		var ticks := 0
		for _frame in DURATION_SECONDS * render_rate:
			ticks += clock.consume_frame(1.0 / float(render_rate))
		_expect(ticks == EXPECTED_TICKS,
			"fixed clock: %d Hz produced %d ticks, expected %d" % [render_rate, ticks, EXPECTED_TICKS], failures)


func _test_invalid_and_batched_frames(failures: Array[String]) -> void:
	var clock := FixedTickClock.new(30)
	_expect(clock.consume_frame(-1.0) == 0, "fixed clock: negative delta must be ignored", failures)
	_expect(clock.consume_frame(INF) == 0, "fixed clock: infinite delta must be ignored", failures)
	_expect(clock.consume_frame(0.5) == 15, "fixed clock: half a second must produce 15 ticks", failures)
	clock.reset()
	_expect(clock.phase == 0.0, "fixed clock: reset must clear fractional phase", failures)


func _expect(condition: bool, message: String, failures: Array[String]) -> void: Assert.expect(condition, message, failures)

