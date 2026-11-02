extends SceneTree

## The room session's presentation event log: ordered drain, explicit clear and
## the bound that keeps a session stepped without a view from growing forever.

const Assert := preload("res://tests/helpers/assert.gd")


func _initialize() -> void:
	var failures: Array[String] = []
	_test_drain_order(failures)
	_test_clear(failures)
	_test_bound(failures)
	if failures.is_empty():
		print("PASS  test_room_session_events.gd")
		quit(0)
		return
	for failure: String in failures:
		printerr("- %s" % failure)
	quit(1)


func _test_drain_order(failures: Array[String]) -> void:
	var session := RoomSession.new()
	for index in 3:
		session.record_event(RoomPresentationEvent.input_feedback("event %d" % index, index))
	Assert.expect(session.pending_event_count() == 3, "log: three events should be pending", failures)
	var drained := session.drain_events()
	Assert.expect(drained.size() == 3 and drained[0].text == "event 0" and drained[2].text == "event 2", "log: drain should return the events in emission order", failures)
	Assert.expect(session.pending_event_count() == 0 and session.drain_events().is_empty(), "log: drain should leave the log empty", failures)


func _test_clear(failures: Array[String]) -> void:
	var session := RoomSession.new()
	session.record_event(RoomPresentationEvent.input_feedback("stale", 1))
	session.clear_events()
	Assert.expect(session.pending_event_count() == 0 and session.drain_events().is_empty(), "log: clear_events should discard pending events", failures)


func _test_bound(failures: Array[String]) -> void:
	var session := RoomSession.new()
	var total := RoomSession.MAX_PENDING_EVENTS * 3
	for index in total:
		session.record_event(RoomPresentationEvent.input_feedback("event %d" % index, index))
	var pending := session.pending_event_count()
	Assert.expect(pending <= RoomSession.MAX_PENDING_EVENTS, "log: an undrained session must stay within the bound (%d pending)" % pending, failures)
	Assert.expect(pending + session.dropped_events == total, "log: every event is either pending or counted as dropped", failures)
	var drained := session.drain_events()
	Assert.expect(drained[drained.size() - 1].text == "event %d" % (total - 1), "log: the newest event survives the bound", failures)
	for index in drained.size() - 1:
		if drained[index].tick + 1 != drained[index + 1].tick:
			failures.append("log: surviving events must stay contiguous and ordered")
			break
