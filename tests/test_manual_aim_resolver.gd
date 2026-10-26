extends SceneTree

const ResolverScript := preload("res://src/systems/manual_aim_resolver.gd")
const Assert := preload("res://tests/helpers/assert.gd")

var failures: Array[String] = []
var resolver = ResolverScript.new()


func _initialize() -> void:
	_test_left_and_right_exact_selection()
	_test_blank_does_not_fall_back()
	_test_out_of_range_stays_locked()
	_test_dead_candidates_are_ignored()
	_test_normal_and_boss_boundaries()
	_test_overlap_and_reversed_order()
	_test_inputs_are_unchanged()
	_test_malformed_inputs_fail_closed()
	if failures.is_empty():
		print("PASS  test_manual_aim_resolver.gd")
		quit(0)
		return
	for failure: String in failures:
		printerr("- %s" % failure)
	quit(1)


func _test_left_and_right_exact_selection() -> void:
	var candidates := [
		_candidate(11, "melee_pursuer", Vector2(-100.0, 0.0)),
		_candidate(22, "fan_ranged", Vector2(100.0, 0.0)),
	]
	var left: Dictionary = resolver.resolve_pointer(Vector2(-100.0, -22.0), Vector2.ZERO, 200.0, candidates)
	_expect(bool(left.ok) and int(left.target_entity_id) == 11, "left/right: left pointer chose the wrong entity")
	_expect(Vector2(left.aim_direction).x < 0.0 and is_zero_approx(Vector2(left.aim_direction).y), "left/right: left aim direction has the wrong sign")
	_expect(Vector2(left.pointer_gameplay) == Vector2(-100.0, -22.0) and Vector2(left.target_anchor) == Vector2(-100.0, -22.0), "left/right: success result lost pointer or anchor geometry")
	_expect(is_equal_approx(float(left.target_radius), 34.0) and bool(left.in_range) and String(left.reason) == "ok", "left/right: in-range success fields changed contract")
	var right: Dictionary = resolver.resolve_pointer(Vector2(100.0, -22.0), Vector2.ZERO, 200.0, candidates)
	_expect(bool(right.ok) and int(right.target_entity_id) == 22, "left/right: right pointer chose the wrong entity")
	_expect(Vector2(right.aim_direction).x > 0.0 and is_zero_approx(Vector2(right.aim_direction).y), "left/right: right aim direction has the wrong sign")


func _test_blank_does_not_fall_back() -> void:
	var result: Dictionary = resolver.resolve_pointer(Vector2.ZERO, Vector2.ZERO, 500.0, [
		_candidate(1, "melee_pursuer", Vector2(200.0, 200.0)),
	])
	_expect(not bool(result.ok), "blank: empty gameplay space selected a nearest enemy")
	_expect(int(result.target_entity_id) == 0 and not bool(result.in_range) and String(result.reason) == "no_pointer_target", "blank: failure result changed contract")


func _test_out_of_range_stays_locked() -> void:
	var enemy := _candidate(7, "charging_raider", Vector2(120.0, 0.0))
	var result: Dictionary = resolver.resolve_pointer(Vector2(120.0, -22.0), Vector2.ZERO, 50.0, [enemy])
	_expect(bool(result.ok) and int(result.target_entity_id) == 7, "range: explicit pointer target was discarded")
	_expect(not bool(result.in_range) and String(result.reason) == "target_out_of_range", "range: out-of-range lock was reported as fireable")
	_expect(Vector2(result.aim_direction) == Vector2.RIGHT, "range: aim did not point to the enemy feet")


func _test_dead_candidates_are_ignored() -> void:
	var dead := _candidate(1, "melee_pursuer", Vector2(100.0, 22.0), 0.0)
	var alive := _candidate(2, "melee_pursuer", Vector2(120.0, 22.0))
	var selected: Dictionary = resolver.resolve_pointer(Vector2(100.0, 0.0), Vector2.ZERO, 500.0, [dead, alive])
	_expect(bool(selected.ok) and int(selected.target_entity_id) == 2, "dead: defeated candidate participated in selection")
	var all_dead: Dictionary = resolver.resolve_pointer(Vector2(100.0, 0.0), Vector2.ZERO, 500.0, [dead])
	_expect(not bool(all_dead.ok) and String(all_dead.reason) == "no_pointer_target", "dead: all-dead input did not behave like blank space")


func _test_normal_and_boss_boundaries() -> void:
	var normal := _candidate(3, "fan_ranged", Vector2(200.0, 200.0))
	_expect(resolver.target_anchor(normal) == Vector2(200.0, 178.0), "geometry: normal anchor is not 22 units above the feet")
	_expect(is_equal_approx(resolver.target_radius(normal), 34.0), "geometry: normal radius changed")
	var normal_edge: Dictionary = resolver.resolve_pointer(Vector2(234.0, 178.0), Vector2.ZERO, 500.0, [normal])
	_expect(bool(normal_edge.ok), "geometry: normal circle excluded its exact boundary")
	var normal_outside: Dictionary = resolver.resolve_pointer(Vector2(234.01, 178.0), Vector2.ZERO, 500.0, [normal])
	_expect(not bool(normal_outside.ok), "geometry: normal circle included space outside its boundary")

	var colossus := _candidate(4, "threshold_colossus", Vector2(400.0, 300.0))
	_expect(resolver.target_anchor(colossus) == Vector2(400.0, 226.0), "geometry: colossus anchor is not 74 units above the feet")
	_expect(is_equal_approx(resolver.target_radius(colossus), 92.0), "geometry: colossus radius changed")
	var boss_edge: Dictionary = resolver.resolve_pointer(Vector2(492.0, 226.0), Vector2.ZERO, 500.0, [colossus])
	_expect(bool(boss_edge.ok), "geometry: Boss circle excluded its exact boundary")
	var boss_outside: Dictionary = resolver.resolve_pointer(Vector2(492.01, 226.0), Vector2.ZERO, 500.0, [colossus])
	_expect(not bool(boss_outside.ok), "geometry: Boss circle included space outside its boundary")
	var flagged_boss := _candidate(5, "melee_pursuer", Vector2(500.0, 300.0), 10.0, true)
	_expect(resolver.target_anchor(flagged_boss) == Vector2(500.0, 226.0) and is_equal_approx(resolver.target_radius(flagged_boss), 92.0), "geometry: is_boss did not opt into Boss geometry")


func _test_overlap_and_reversed_order() -> void:
	var normal := _candidate(2, "melee_pursuer", Vector2(100.0, 122.0))
	var boss := _candidate(9, "threshold_colossus", Vector2(150.0, 174.0))
	var pointer := Vector2(120.0, 100.0)
	var forward: Dictionary = resolver.resolve_pointer(pointer, Vector2.ZERO, 500.0, [normal, boss])
	var backward: Dictionary = resolver.resolve_pointer(pointer, Vector2.ZERO, 500.0, [boss, normal])
	_expect(int(forward.target_entity_id) == 9, "overlap: selection did not use normalized squared distance")
	_expect(forward == backward, "overlap: reversing candidate order changed the result")

	var low_id := _candidate(3, "melee_pursuer", Vector2(200.0, 222.0))
	var high_id := _candidate(8, "threshold_colossus", Vector2(200.0, 274.0))
	var tied: Dictionary = resolver.resolve_pointer(Vector2(200.0, 200.0), Vector2.ZERO, 500.0, [high_id, low_id])
	_expect(int(tied.target_entity_id) == 3, "overlap: equal normalized scores did not break by entity_id")


func _test_inputs_are_unchanged() -> void:
	var pointer := Vector2(40.0, 18.0)
	var player := Vector2(10.0, 20.0)
	var distance := 90.0
	var candidates := [_candidate(6, "fan_ranged", Vector2(40.0, 40.0))]
	var before: Array = candidates.duplicate(true)
	resolver.resolve_pointer(pointer, player, distance, candidates)
	_expect(candidates == before, "purity: resolver mutated candidates")
	_expect(pointer == Vector2(40.0, 18.0) and player == Vector2(10.0, 20.0) and is_equal_approx(distance, 90.0), "purity: resolver changed scalar inputs")


func _test_malformed_inputs_fail_closed() -> void:
	var valid := [_candidate(1, "melee_pursuer", Vector2.ZERO)]
	var cases := [
		{"pointer": null, "player": Vector2.ZERO, "distance": 10.0, "candidates": valid, "reason": "invalid_pointer_gameplay"},
		{"pointer": Vector2.ZERO, "player": "bad", "distance": 10.0, "candidates": valid, "reason": "invalid_player_position"},
		{"pointer": Vector2.ZERO, "player": Vector2.ZERO, "distance": -1.0, "candidates": valid, "reason": "invalid_targeting_distance"},
		{"pointer": Vector2.ZERO, "player": Vector2.ZERO, "distance": 10.0, "candidates": {}, "reason": "invalid_candidates"},
		{"pointer": Vector2.ZERO, "player": Vector2.ZERO, "distance": 10.0, "candidates": [{"entity_id": 1}], "reason": "candidate_missing_kind_id"},
		{"pointer": Vector2.ZERO, "player": Vector2.ZERO, "distance": 10.0, "candidates": [_candidate(1, "melee_pursuer", Vector2.ZERO, -1.0)], "reason": "invalid_candidate_health"},
	]
	for index in cases.size():
		var item: Dictionary = cases[index]
		var result: Dictionary = resolver.resolve_pointer(item.pointer, item.player, item.distance, item.candidates)
		_expect(not bool(result.get("ok", true)), "malformed: case %d did not fail closed" % index)
		_expect(int(result.get("target_entity_id", -1)) == 0 and not bool(result.get("in_range", true)), "malformed: case %d leaked a target" % index)
		_expect(String(result.get("reason", "")) == String(item.reason), "malformed: case %d returned unstable reason %s" % [index, result.get("reason", "")])
	_expect(resolver.target_anchor(null) == Vector2.ZERO, "malformed: target_anchor did not safely reject invalid candidate")
	_expect(is_zero_approx(resolver.target_radius({"entity_id": 1})), "malformed: target_radius did not safely reject invalid candidate")


func _candidate(entity_id: int, kind_id: String, position: Vector2, health: float = 100.0, is_boss: Variant = null) -> Dictionary:
	var result := {
		"entity_id": entity_id,
		"kind_id": kind_id,
		"position": position,
		"health": health,
	}
	if is_boss != null:
		result["is_boss"] = is_boss
	return result


func _expect(condition: bool, message: String) -> void: Assert.expect(condition, message, failures)
