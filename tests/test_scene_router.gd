extends RefCounted

const SceneRouter = preload("res://src/game/scene_router.gd")
const Assert := preload("res://tests/helpers/assert.gd")

var _signal_events: Array[Dictionary] = []


func run() -> Array[String]:
	var failures: Array[String] = []
	_test_default_state(failures)
	_test_main_loop(failures)
	_test_facility_routes(failures)
	_test_ending_route(failures)
	_test_invalid_requests(failures)
	_test_noop(failures)
	_test_pending_and_cancel(failures)
	_test_reset_atomicity(failures)
	_test_alias_isolation(failures)
	_test_route_changed(failures)
	return failures


func _test_default_state(failures: Array[String]) -> void:
	var router := SceneRouter.new()
	_expect(router.current_route == SceneRouter.ROUTE_BOOT, "scene router: default route must be boot", failures)
	_expect(not router.has_pending(), "scene router: new router must not have a pending route", failures)
	_expect(router.pending_route.is_empty(), "scene router: empty pending route must use the stable empty value", failures)
	_expect(router.pending_payload.is_empty(), "scene router: new router must have no pending payload", failures)
	_expect(router.history.is_empty(), "scene router: new router must have empty history", failures)
	_expect(not bool(router.commit().ok), "scene router: commit without pending must fail", failures)
	_expect(router.commit().error == SceneRouter.ERROR_NO_PENDING, "scene router: empty commit error changed", failures)


func _test_main_loop(failures: Array[String]) -> void:
	var router := SceneRouter.new()
	var loop: Array[String] = [
		SceneRouter.ROUTE_TITLE,
		SceneRouter.ROUTE_TUTORIAL,
		SceneRouter.ROUTE_BASE,
		SceneRouter.ROUTE_CONTRACT,
		SceneRouter.ROUTE_ARENA,
		SceneRouter.ROUTE_RESULT,
		SceneRouter.ROUTE_BASE,
	]
	for route in loop:
		_expect(router.can_transition(route), "scene router: expected transition to %s" % route, failures)
		var requested: Dictionary = router.request(route, {"route": route})
		_expect(bool(requested.get("ok", false)), "scene router: request to %s failed" % route, failures)
		var committed: Dictionary = router.commit()
		_expect(bool(committed.get("ok", false)), "scene router: commit to %s failed" % route, failures)
		_expect(router.current_route == route, "scene router: commit did not reach %s" % route, failures)
	_expect(router.history.size() == loop.size(), "scene router: main loop history length changed", failures)


func _test_facility_routes(failures: Array[String]) -> void:
	var router := SceneRouter.new()
	for route in [SceneRouter.ROUTE_TITLE, SceneRouter.ROUTE_BASE]:
		router.request(route)
		router.commit()
	for facility in [SceneRouter.ROUTE_LOADOUT, SceneRouter.ROUTE_FORGE, SceneRouter.ROUTE_TRAINING, SceneRouter.ROUTE_PROXY, SceneRouter.ROUTE_IMMORTALITY]:
		_expect(router.can_transition(facility), "scene router: base cannot enter %s" % facility, failures)
		router.request(facility)
		router.commit()
		_expect(router.can_transition(SceneRouter.ROUTE_BASE), "scene router: %s cannot return to base" % facility, failures)
		router.request(SceneRouter.ROUTE_BASE)
		router.commit()
	router.request(SceneRouter.ROUTE_TRAINING)
	router.commit()
	_expect(router.can_transition(SceneRouter.ROUTE_RESEARCH), "scene router: training cannot open research", failures)
	router.request(SceneRouter.ROUTE_RESEARCH)
	router.commit()
	router.request(SceneRouter.ROUTE_BASE)
	router.commit()
	_expect(router.current_route == SceneRouter.ROUTE_BASE, "scene router: facility loop did not return to base", failures)

	var result_router := SceneRouter.new()
	for route in [SceneRouter.ROUTE_TITLE, SceneRouter.ROUTE_BASE, SceneRouter.ROUTE_CONTRACT, SceneRouter.ROUTE_ARENA, SceneRouter.ROUTE_RESULT]:
		result_router.request(route)
		result_router.commit()
	_expect(result_router.can_transition(SceneRouter.ROUTE_LOADOUT), "scene router: result cannot open loadout to compare a settled drop", failures)
	var review_request := result_router.request(SceneRouter.ROUTE_LOADOUT, {"review_instance_id": "drop:1", "focus_slot": "gloves"})
	_expect(bool(review_request.get("ok", false)), "scene router: result-to-loadout review request failed", failures)
	if bool(review_request.get("ok", false)):
		var review_commit := result_router.commit()
		_expect(bool(review_commit.get("ok", false)) and review_commit.payload == {"review_instance_id": "drop:1", "focus_slot": "gloves"},
			"scene router: result-to-loadout review context was not preserved", failures)
		_expect(result_router.can_transition(SceneRouter.ROUTE_RESULT), "scene router: reviewed loadout cannot return to settlement", failures)


func _test_ending_route(failures: Array[String]) -> void:
	var router := SceneRouter.new()
	for route in [SceneRouter.ROUTE_TITLE, SceneRouter.ROUTE_BASE, SceneRouter.ROUTE_CONTRACT, SceneRouter.ROUTE_ARENA, SceneRouter.ROUTE_RESULT, SceneRouter.ROUTE_ENDING, SceneRouter.ROUTE_BASE]:
		var requested: Dictionary = router.request(route)
		_expect(bool(requested.get("ok", false)), "scene router: ending path rejected %s" % route, failures)
		if bool(requested.get("ok", false)) and not bool(requested.get("noop", false)):
			router.commit()
	_expect(router.current_route == SceneRouter.ROUTE_BASE, "scene router: ending path did not return to base", failures)


func _test_invalid_requests(failures: Array[String]) -> void:
	var router := SceneRouter.new()
	var unknown: Dictionary = router.request("missing")
	_expect(unknown == {"ok": false, "error": SceneRouter.ERROR_UNKNOWN_ROUTE}, "scene router: unknown route error changed", failures)
	var illegal: Dictionary = router.request(SceneRouter.ROUTE_ARENA)
	_expect(illegal == {"ok": false, "error": SceneRouter.ERROR_TRANSITION_NOT_ALLOWED}, "scene router: illegal edge error changed", failures)
	_expect(router.current_route == SceneRouter.ROUTE_BOOT and not router.has_pending(), "scene router: rejected request changed state", failures)
	_expect(not router.can_transition("missing", SceneRouter.ROUTE_BOOT), "scene router: unknown source was transitionable", failures)


func _test_noop(failures: Array[String]) -> void:
	var router := SceneRouter.new()
	var result: Dictionary = router.request(SceneRouter.ROUTE_BOOT, {"ignored": true})
	_expect(bool(result.get("ok", false)) and bool(result.get("noop", false)), "scene router: current-route request must be a successful noop", failures)
	_expect(not router.has_pending(), "scene router: noop must not queue a request", failures)
	_expect(router.history.is_empty(), "scene router: noop must not write history", failures)


func _test_pending_and_cancel(failures: Array[String]) -> void:
	var router := SceneRouter.new()
	_expect(bool(router.request(SceneRouter.ROUTE_TITLE).ok), "scene router: first pending request failed", failures)
	var second: Dictionary = router.request(SceneRouter.ROUTE_BASE)
	_expect(second == {"ok": false, "error": SceneRouter.ERROR_REQUEST_PENDING}, "scene router: concurrent pending error changed", failures)
	_expect(router.pending_route == SceneRouter.ROUTE_TITLE, "scene router: rejected second request replaced pending route", failures)
	router.cancel()
	_expect(not router.has_pending() and router.pending_payload.is_empty(), "scene router: cancel did not clear pending state", failures)
	_expect(bool(router.request(SceneRouter.ROUTE_BASE).ok), "scene router: request after cancel failed", failures)


func _test_reset_atomicity(failures: Array[String]) -> void:
	var router := SceneRouter.new()
	router.request(SceneRouter.ROUTE_TITLE, {"keep": 1})
	var before_payload: Dictionary = router.pending_payload
	var failed: Dictionary = router.reset("missing")
	_expect(failed == {"ok": false, "error": SceneRouter.ERROR_UNKNOWN_ROUTE}, "scene router: invalid reset error changed", failures)
	_expect(router.current_route == SceneRouter.ROUTE_BOOT, "scene router: invalid reset changed current route", failures)
	_expect(router.pending_route == SceneRouter.ROUTE_TITLE and router.pending_payload == before_payload, "scene router: invalid reset changed pending state", failures)
	router.commit()
	var reset_result: Dictionary = router.reset(SceneRouter.ROUTE_CONTRACT)
	_expect(bool(reset_result.get("ok", false)) and router.current_route == SceneRouter.ROUTE_CONTRACT, "scene router: valid reset did not set initial route", failures)
	_expect(not router.has_pending() and router.history.is_empty(), "scene router: valid reset did not clear transient state", failures)


func _test_alias_isolation(failures: Array[String]) -> void:
	var router := SceneRouter.new()
	var input_payload := {"nested": {"value": 1}}
	router.request(SceneRouter.ROUTE_TITLE, input_payload)
	input_payload.nested.value = 2
	var pending_copy: Dictionary = router.pending_payload
	_expect(int(pending_copy.nested.value) == 1, "scene router: pending payload aliases request input", failures)
	pending_copy.nested.value = 3
	_expect(int(router.pending_payload.nested.value) == 1, "scene router: pending payload getter leaks aliases", failures)
	var committed: Dictionary = router.commit()
	committed.payload.nested.value = 4
	var history_copy: Array = router.history
	_expect(int(history_copy[0].payload.nested.value) == 1, "scene router: commit result aliases history", failures)
	history_copy[0].payload.nested.value = 5
	history_copy.append({"injected": true})
	_expect(router.history.size() == 1 and int(router.history[0].payload.nested.value) == 1, "scene router: history getter leaks aliases", failures)


func _test_route_changed(failures: Array[String]) -> void:
	var router := SceneRouter.new()
	_signal_events.clear()
	router.route_changed.connect(_on_route_changed)
	router.request(SceneRouter.ROUTE_TITLE, {"nested": {"value": 7}})
	router.commit()
	_expect(_signal_events.size() == 1, "scene router: one commit must emit route_changed exactly once", failures)
	if _signal_events.size() == 1:
		_expect(_signal_events[0].previous_route == SceneRouter.ROUTE_BOOT, "scene router: signal previous route changed", failures)
		_expect(_signal_events[0].current_route == SceneRouter.ROUTE_TITLE, "scene router: signal current route changed", failures)
		_signal_events[0].payload.nested.value = 8
		_expect(int(router.history[0].payload.nested.value) == 7, "scene router: signal payload aliases history", failures)
	router.commit()
	router.cancel()
	router.reset()
	_expect(_signal_events.size() == 1, "scene router: non-commit operations emitted route_changed", failures)


func _on_route_changed(previous_route: String, current_route: String, payload: Dictionary) -> void:
	_signal_events.append({
		"previous_route": previous_route,
		"current_route": current_route,
		"payload": payload,
	})


func _expect(condition: bool, message: String, failures: Array[String]) -> void: Assert.expect(condition, message, failures)
