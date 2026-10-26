extends SceneTree

const Timeline := preload("res://src/systems/player_action_timeline.gd")
const Assert := preload("res://tests/helpers/assert.gd")


func _initialize() -> void:
	var failures: Array[String] = []
	_test_exact_boundaries_and_single_impact(failures)
	_test_per_action_windup(failures)
	_test_skipped_tick_advance(failures)
	_test_buffer_window_and_replacement(failures)
	_test_cancel_buffered_target(failures)
	_test_interrupt(failures)
	_test_exact_restore_continuation(failures)
	_test_invalid_restore_fails_closed(failures)
	_test_duplicate_calls_are_deterministic(failures)
	if failures.is_empty():
		print("PASS  test_player_action_timeline.gd")
		quit(0)
		return
	for failure in failures:
		printerr("- %s" % failure)
	quit(1)


func _test_exact_boundaries_and_single_impact(failures: Array[String]) -> void:
	var timeline := Timeline.new()
	var receipt := timeline.request_attack(20, 7, Vector2(3.0, 4.0))
	_expect(bool(receipt.get("accepted", false)), "boundary: attack was not accepted", failures)
	for tick in range(20, 25):
		_expect(timeline.phase_at(tick) == Timeline.PHASE_WINDUP, "boundary: tick %d must be windup" % tick, failures)
	for tick in range(25, 30):
		_expect(timeline.phase_at(tick) == Timeline.PHASE_RECOVERY, "boundary: tick %d must be recovery" % tick, failures)
	_expect(timeline.phase_at(30) == Timeline.PHASE_IDLE, "boundary: tick 30 must be idle", failures)
	var events := timeline.advance(30)
	_expect(_types(events) == ["action_started", "action_impact", "action_ended"], "boundary: wrong event sequence", failures)
	_expect(_ticks(events) == [20, 25, 30], "boundary: wrong event ticks", failures)
	_expect(_count_type(events, "action_impact") == 1, "boundary: impact must occur exactly once", failures)


func _test_per_action_windup(failures: Array[String]) -> void:
	var timeline := Timeline.new()
	var default_receipt := timeline.request_attack(10, 1, Vector2.RIGHT)
	_expect(int(default_receipt.get("action_instance_id", 0)) == 1, "windup: default action was not accepted", failures)
	var default_events := timeline.advance(20)
	_expect(_ticks(default_events) == [10, 15, 20], "windup: default timing changed", failures)
	var fast := timeline.request_attack(21, 2, Vector2.RIGHT, -1, 4)
	_expect(bool(fast.get("accepted", false)), "windup: reduced windup was rejected", failures)
	var fast_events := timeline.advance(30)
	_expect(_ticks(fast_events) == [21, 25, 30], "windup: reduced action did not release one tick early", failures)
	for fast_event in fast_events:
		var event: Dictionary = fast_event
		if String(event.get("type", "")) == "action_impact":
			_expect(int(event.get("windup_ticks", -1)) == 4, "windup: impact event omitted the action length", failures)
	var invalid := timeline.request_attack(31, 3, Vector2.RIGHT, -1, 0)
	_expect(not bool(invalid.get("accepted", false)) and String(invalid.get("reason", "")) == "invalid_windup_ticks", "windup: invalid length was accepted", failures)


func _test_skipped_tick_advance(failures: Array[String]) -> void:
	var timeline := Timeline.new()
	timeline.request_attack(100, 3, Vector2.LEFT)
	var first := timeline.advance(104)
	_expect(_types(first) == ["action_started"], "skip: advance to 104 should only start", failures)
	var skipped := timeline.advance(110)
	_expect(_types(skipped) == ["action_impact", "action_ended"], "skip: crossed events were lost or reordered", failures)
	_expect(_ticks(skipped) == [105, 110], "skip: crossed events have wrong authoritative ticks", failures)


func _test_buffer_window_and_replacement(failures: Array[String]) -> void:
	var timeline := Timeline.new()
	timeline.request_attack(0, 1, Vector2.RIGHT)
	var accepted := timeline.request_attack(6, 2, Vector2.UP)
	_expect(accepted.get("status") == "buffered" and int(accepted.get("start_tick", -1)) == 10, "buffer: four-tick request was not accepted", failures)
	var replacement := timeline.request_attack(7, 9, Vector2.DOWN)
	_expect(replacement.get("status") == "replaced", "buffer: newest valid request did not explicitly replace", failures)
	_expect(int(replacement.get("replaced_request_id", 0)) == int(accepted.get("request_id", -1)), "buffer: replacement did not identify the older request", failures)
	var events := timeline.advance(15)
	_expect(_types(events) == ["action_started", "action_impact", "action_ended", "buffered_started", "action_started", "action_impact"], "buffer: wrong event sequence", failures)
	_expect(_ticks(events) == [0, 5, 10, 10, 10, 15], "buffer: wrong event ticks", failures)
	_expect(int(events[4].get("target_entity_id", 0)) == 9, "buffer: replaced target was still used", failures)
	_expect(int(events[0].get("action_instance_id", 0)) == 1 and int(events[4].get("action_instance_id", 0)) == 2, "buffer: action ids are not monotonic", failures)

	var rejected_timeline := Timeline.new()
	rejected_timeline.request_attack(0, 1, Vector2.RIGHT)
	var rejected := rejected_timeline.request_attack(5, 2, Vector2.UP)
	_expect(not bool(rejected.get("accepted", true)) and rejected.get("reason") == "outside_buffer_window", "buffer: five-tick request was not rejected", failures)


func _test_cancel_buffered_target(failures: Array[String]) -> void:
	var timeline := Timeline.new()
	var active := timeline.request_attack(0, 4, Vector2.RIGHT)
	var buffered := timeline.request_attack(6, 9, Vector2.UP)
	_expect(bool(active.get("accepted", false)) and bool(buffered.get("accepted", false)), "cancel: setup requests were rejected", failures)
	_expect(timeline.cancel_buffered_target(8) == 0, "cancel: unrelated target removed the buffer", failures)
	_expect(int(timeline.snapshot().get("active", {}).get("request_id", 0)) == int(active.get("request_id", 0)), "cancel: unrelated target interrupted the active action", failures)
	_expect(timeline.cancel_buffered_target(9) == int(buffered.get("request_id", 0)), "cancel: matching target did not return its request id", failures)
	_expect(timeline.cancel_buffered_target(9) == 0, "cancel: already-cleared target returned a request twice", failures)
	var events := timeline.advance(20)
	_expect(_types(events) == ["action_started", "action_impact", "action_ended"], "cancel: cleared buffer still started or impacted", failures)


func _test_interrupt(failures: Array[String]) -> void:
	var timeline := Timeline.new()
	timeline.request_attack(40, 4, Vector2.RIGHT)
	timeline.request_attack(46, 5, Vector2.UP)
	var result := timeline.interrupt(43, "stunned")
	_expect(bool(result.get("accepted", false)) and result.get("status") == "interrupted", "interrupt: active action was not interrupted", failures)
	_expect(_types(result.get("events", [])) == ["action_started", "action_interrupted"], "interrupt: wrong event sequence", failures)
	_expect(timeline.phase_at(46) == Timeline.PHASE_IDLE, "interrupt: active or buffered action survived", failures)
	_expect(timeline.advance(60).is_empty(), "interrupt: cleared action later emitted events", failures)


func _test_exact_restore_continuation(failures: Array[String]) -> void:
	var original := Timeline.new()
	original.request_attack(10, 8, Vector2(1.0, 1.0))
	original.advance(12)
	original.request_attack(16, 11, Vector2.LEFT)
	var saved := original.snapshot()
	var restored := Timeline.new()
	_expect(restored.restore_exact(saved), "restore: valid exact snapshot was rejected", failures)
	saved["active"]["target_entity_id"] = 999
	var expected := original.advance(25)
	var actual := restored.advance(25)
	_expect(actual == expected, "restore: continuation diverged from original", failures)
	_expect(int(actual[0].get("target_entity_id", 0)) == 8, "restore: snapshot was not deep-safe", failures)
	var continued := restored.request_attack(26, 12, Vector2.DOWN)
	_expect(continued.get("status") == "buffered", "restore: continuation request was not buffered", failures)
	var continuation_events := restored.advance(30)
	_expect(_types(continuation_events) == ["action_ended", "buffered_started", "action_started"], "restore: continuation events were wrong", failures)
	_expect(int(continuation_events[2].get("action_instance_id", 0)) == 3, "restore: action instance id did not continue monotonically", failures)


func _test_invalid_restore_fails_closed(failures: Array[String]) -> void:
	var timeline := Timeline.new()
	timeline.request_attack(5, 3, Vector2.RIGHT)
	var invalid := timeline.snapshot()
	invalid["schema_version"] = 999
	_expect(not timeline.restore_exact(invalid), "restore: incompatible schema was accepted", failures)
	var reset_state := timeline.snapshot()
	_expect(int(reset_state["last_advanced_tick"]) == -1 and Dictionary(reset_state["active"]).is_empty(), "restore: invalid input did not reset closed", failures)
	var extra_key := reset_state.duplicate(true)
	extra_key["unexpected"] = true
	_expect(not timeline.restore_exact(extra_key), "restore: non-exact schema was accepted", failures)
	var impossible_buffer := Timeline.new()
	impossible_buffer.request_attack(0, 1, Vector2.RIGHT)
	impossible_buffer.request_attack(6, 2, Vector2.UP)
	var impossible_snapshot := impossible_buffer.snapshot()
	impossible_snapshot["buffered"]["start_tick"] = 11
	_expect(not timeline.restore_exact(impossible_snapshot), "restore: impossible five-tick buffer was accepted", failures)


func _test_duplicate_calls_are_deterministic(failures: Array[String]) -> void:
	var timeline := Timeline.new()
	var rejected_a := timeline.request_attack(0, 0, Vector2.RIGHT)
	var rejected_b := timeline.request_attack(0, 0, Vector2.RIGHT)
	_expect(rejected_a.get("reason") == rejected_b.get("reason"), "duplicate: invalid requests changed rejection semantics", failures)
	timeline.request_attack(2, 2, Vector2.RIGHT)
	var first := timeline.advance(7)
	var duplicate := timeline.advance(7)
	_expect(_count_type(first, "action_impact") == 1 and duplicate.is_empty(), "duplicate: same-tick advance duplicated impact", failures)
	var later := timeline.advance(12)
	_expect(_types(later) == ["action_ended"], "duplicate: end was missing after duplicate advance", failures)
	_expect(timeline.advance(12).is_empty(), "duplicate: same-tick advance duplicated end", failures)
	var stale := timeline.advance(11)
	_expect(stale.is_empty(), "duplicate: stale advance emitted data", failures)


func _types(events: Array) -> Array[String]:
	var result: Array[String] = []
	for event in events:
		result.append(String(event.get("type", "")))
	return result


func _ticks(events: Array) -> Array[int]:
	var result: Array[int] = []
	for event in events:
		result.append(int(event.get("tick", -1)))
	return result


func _count_type(events: Array, event_type: String) -> int:
	var count := 0
	for event in events:
		if String(event.get("type", "")) == event_type:
			count += 1
	return count


func _expect(condition: bool, message: String, failures: Array[String]) -> void: Assert.expect(condition, message, failures)
