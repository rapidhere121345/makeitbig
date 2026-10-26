extends SceneTree

const ContentRegistryScript := preload("res://src/content/content_registry.gd")
const ProxyBuildScript := preload("res://src/systems/proxy_build.gd")
const ProxyIntentSystemScript := preload("res://src/systems/proxy_intent_system.gd")
const ArenaGeometryScript := preload("res://src/runtime/geometry/arena_geometry.gd")
const Assert := preload("res://tests/helpers/assert.gd")


func _initialize() -> void:
	var failures: Array[String] = []
	var registry := ContentRegistryScript.new()
	var load_errors: Array[String] = registry.load_all()
	_expect(load_errors.is_empty(), "content registry failed: %s" % str(load_errors), failures)
	if load_errors.is_empty():
		var compiled: Dictionary = ProxyBuildScript.compile({
			"cores": ["near_enemy_horizon", "direct_gait", "single_key_execution", "short_trace_memory"],
		}, registry.cores)
		_expect(bool(compiled.get("ok", false)), "proxy fixture did not compile", failures)
		if bool(compiled.get("ok", false)):
			_run_contract(compiled.get("value", {}), failures)
	if failures.is_empty():
		print("PASS  test_proxy_intent_system.gd")
		quit(0)
		return
	for failure in failures:
		printerr("- %s" % failure)
	quit(1)


func _run_contract(build: Dictionary, failures: Array[String]) -> void:
	var system := ProxyIntentSystemScript.new()
	_expect(not system.is_ready(), "new proxy intent system was ready without a contract", failures)
	var before_start: Dictionary = system.decide(_snapshot(0), 0)
	_expect(not bool(before_start.get("ok", true)) and String(before_start.get("error", "")) == "proxy_not_started", "unstarted proxy emitted an intent", failures)
	_expect(not system.failure_snapshot().is_empty(), "unstarted proxy did not publish a lifecycle failure", failures)

	var started: Dictionary = system.begin_contract(build)
	_expect(bool(started.get("ok", false)) and system.is_ready(), "valid resolved proxy contract was not started", failures)
	var initial_state := system.decision_state_snapshot()
	var decision: Dictionary = system.decide(_snapshot(0), 7)
	_expect(bool(decision.get("ok", false)), "valid public snapshot was rejected: %s" % String(decision.get("error", "")), failures)
	_expect(int(system.decision_state_snapshot().get("target_entity_id", 0)) == 1, "proxy intent system did not commit the selected target", failures)
	_expect(int(decision.get("next_sequence", 0)) > 7, "proxy intent system did not advance the shared command sequence", failures)
	_expect(not system.trace_snapshot().is_empty(), "proxy intent system lost the policy trace", failures)
	_expect(initial_state != system.decision_state_snapshot(), "proxy intent system state did not advance", failures)

	var committed_state := system.decision_state_snapshot()
	var invalid_snapshot := _snapshot(1)
	invalid_snapshot["private_room_state"] = true
	var rejected: Dictionary = system.decide(invalid_snapshot, int(decision.next_sequence))
	_expect(not bool(rejected.get("ok", true)) and String(rejected.get("error", "")) == "invalid_snapshot", "invalid public observation was accepted", failures)
	_expect(system.decision_state_snapshot() == committed_state, "rejected observation mutated proxy continuation state", failures)
	_expect(String(system.failure_snapshot().get("category", "")) == "protocol", "proxy protocol failure lost its category", failures)

	var state_copy := system.decision_state_snapshot()
	state_copy["target_entity_id"] = 999
	_expect(int(system.decision_state_snapshot().get("target_entity_id", 0)) == 1, "state snapshot was an alias", failures)
	system.reset()
	_expect(not system.is_ready() and system.decision_state_snapshot().is_empty(), "reset left a live proxy contract", failures)
	var raw_start: Dictionary = system.begin_contract({"cores": ["near_enemy_horizon"]})
	_expect(not bool(raw_start.get("ok", true)), "raw proxy configuration bypassed resolved-build validation", failures)


func _snapshot(tick: int) -> Dictionary:
	return {
		"snapshot_version": 3,
		"tick": tick,
		"actor_id": "ranger",
		"player_position": Vector2.ZERO,
		"facing": Vector2.RIGHT,
		"action_state": "idle",
		"attack_ready_tick": 0,
		"targeting_distance": 10.0,
		"visible_enemies": [{
			"entity_id": 1,
			"position": Vector2(5.0, 0.0),
			"health": 10.0,
			"targetable": true,
		}],
		"walkable_geometry": ArenaGeometryScript.from_layout("rectangle", Rect2(-100.0, -100.0, 200.0, 200.0), 0.0),
	}


func _expect(condition: bool, message: String, failures: Array[String]) -> void: Assert.expect(condition, message, failures)
