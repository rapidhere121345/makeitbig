extends SceneTree

const CombatEventStreamScript := preload("res://src/systems/combat_event_stream.gd")


func _initialize() -> void:
	var failures: Array[String] = []
	var stream = CombatEventStreamScript.new(3)
	_expect(stream.emit(-1, "damage_applied").is_empty(), "negative tick was accepted", failures)
	_expect(stream.emit(0, "unknown").is_empty(), "unknown event type was accepted", failures)
	var first: Dictionary = stream.emit(4, "action_accepted", {"actor_id": "ranger", "tick": 99})
	var spawned: Dictionary = stream.emit(4, "projectile_spawned", {"source_id": "ranger/piercing_arrow"})
	_expect(String(spawned.get("type", "")) == "projectile_spawned", "authoritative projectile spawn event was rejected", failures)
	var second: Dictionary = stream.emit(5, "damage_applied", {"amount": 7.0, "source_id": "enemy/1"})
	stream.emit(5, "attack_resolved", {"outcome": "damage"})
	stream.emit(6, "action_ended", {"action_id": "piercing_arrow"})
	_expect(int(first.event_id) == 1 and int(spawned.event_id) == 2 and int(second.event_id) == 3, "event ids are not monotonic", failures)
	_expect(int(first.tick) == 4, "reserved event fields were overwritten", failures)
	var retained: Array[Dictionary] = stream.events_after(0)
	_expect(retained.size() == 3 and int(retained[0].event_id) == 3, "bounded journal retained the wrong events", failures)
	var at_five: Array[Dictionary] = stream.events_between(5, 5)
	_expect(at_five.size() == 2 and at_five[0].type == "damage_applied" and at_five[1].type == "attack_resolved", "same-tick event order changed", failures)
	retained[0]["amount"] = 999.0
	_expect(float(stream.events_after(1)[0].amount) == 7.0, "event readers alias authority data", failures)
	var state: Dictionary = stream.snapshot()
	var restored = CombatEventStreamScript.new()
	_expect(restored.restore_exact(state), "exact snapshot did not restore", failures)
	_expect(restored.snapshot() == state, "restored journal differs", failures)
	var malformed: Dictionary = state.duplicate(true)
	malformed["next_event_id"] = 2
	_expect(not CombatEventStreamScript.new().restore_exact(malformed), "invalid next id restored", failures)
	var continued: Dictionary = restored.emit(7, "death_applied")
	_expect(int(continued.event_id) == 6, "restored event id did not continue", failures)
	if failures.is_empty():
		print("PASS  test_combat_event_stream.gd")
		quit(0)
		return
	for failure: String in failures:
		printerr("- %s" % failure)
	quit(1)


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
