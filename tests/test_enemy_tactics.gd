extends SceneTree

const EnemyTacticsScript := preload("res://src/systems/enemy_tactics.gd")
const ArenaGeometry := preload("res://src/runtime/geometry/arena_geometry.gd")

const DEFAULT_ARENA := Rect2(0.0, 0.0, 640.0, 480.0)

var failures: Array[String] = []
var tactics = EnemyTacticsScript.new()


func _initialize() -> void:
	_test_malformed_input()
	_test_no_mutation_and_order_invariance()
	_test_melee_ring_and_separation()
	_test_charger_ranges()
	_test_charger_padding_contact_projection()
	_test_fan_ranges_and_strafe()
	_test_fan_attack_radius_boundary()
	_test_fan_strafe_liveness()
	_test_fan_lane_order_invariance()
	_test_fan_lane_wait_approaches_attack_range()
	_test_snapshot_lane_occupancy_and_recovery_handoff()
	_test_one_action_per_kind_with_moving_waiters()
	_test_independent_kind_lanes()
	_test_locked_action()
	_test_boss_cycle()
	_test_arena_and_hazard_scoring()
	_test_polygon_steering_lane()
	_test_ring_inner_antipode_planning()
	_test_rectangle_geometry_straight_controls()
	_test_quantization()
	if failures.is_empty():
		print("PASS  test_enemy_tactics.gd")
		quit(0)
		return
	for failure in failures:
		printerr("- %s" % failure)
	quit(1)


func _base_snapshot(enemies: Array, hazards: Array = [], arena_rect: Rect2 = DEFAULT_ARENA, walkable_geometry: Variant = null) -> Dictionary:
	var geometry: Dictionary = ArenaGeometry.from_layout("rectangle", arena_rect, 0.0) if walkable_geometry == null else walkable_geometry
	return {
		"snapshot_version": EnemyTacticsScript.SNAPSHOT_VERSION,
		"tick": 120,
		"player_position": arena_rect.get_center(),
		"arena_rect": arena_rect,
		"walkable_geometry": geometry,
		"enemies": enemies,
		"hazards": hazards,
	}


func _enemy(entity_id: int, kind_id: String, position: Vector2, action_state: String = "idle") -> Dictionary:
	var result := {
		"entity_id": entity_id,
		"kind_id": kind_id,
		"position": position,
		"action_state": action_state,
		"health": 100.0,
		"facing": Vector2.RIGHT,
	}
	if kind_id == "threshold_colossus":
		result["phase"] = "sealed"
		result["next_action_index"] = 0
	return result


func _test_malformed_input() -> void:
	var mismatched_geometry := ArenaGeometry.from_layout("rectangle", Rect2(0.0, 0.0, 320.0, 240.0), 0.0)
	var invalid_geometry := ArenaGeometry.from_layout("rectangle", DEFAULT_ARENA, 0.0)
	invalid_geometry["kind"] = "unknown"
	var missing_geometry := _base_snapshot([])
	missing_geometry.erase("walkable_geometry")
	var cases: Array = [
		null,
		{},
		{"snapshot_version": 99, "tick": 0, "player_position": Vector2.ZERO, "arena_rect": Rect2(0, 0, 10, 10), "walkable_geometry": ArenaGeometry.from_layout("rectangle", Rect2(0, 0, 10, 10), 0.0), "enemies": []},
		_base_snapshot([{"entity_id": 1}]),
		_base_snapshot([_enemy(1, "melee_pursuer", Vector2.ZERO), _enemy(1, "fan_ranged", Vector2.ONE)]),
		_base_snapshot([_enemy(1, "unknown", Vector2.ZERO)]),
		_base_snapshot([], [{"active_geometry": {"shape": "circle", "center": Vector2.ZERO, "radius": -1.0}}]),
		missing_geometry,
		_base_snapshot([], [], DEFAULT_ARENA, invalid_geometry),
		_base_snapshot([], [], DEFAULT_ARENA, mismatched_geometry),
	]
	for index in cases.size():
		var result: Dictionary = tactics.plan(cases[index])
		_expect(not bool(result.get("ok", true)), "malformed: case %d did not fail closed" % index)
		_expect((result.get("intents", []) as Array).is_empty(), "malformed: case %d leaked intents" % index)
		_expect(not String(result.get("error", "")).is_empty(), "malformed: case %d has no error" % index)


func _test_no_mutation_and_order_invariance() -> void:
	var enemies := [
		_enemy(9, "fan_ranged", Vector2(520.0, 240.0)),
		_enemy(2, "melee_pursuer", Vector2(100.0, 100.0)),
		_enemy(5, "charging_raider", Vector2(80.0, 240.0)),
	]
	var snapshot := _base_snapshot(enemies, [{"warning_geometry": {"shape": "rect", "rect": Rect2(200, 180, 40, 120)}}])
	var before: Dictionary = snapshot.duplicate(true)
	var forward: Dictionary = tactics.plan(snapshot)
	_expect(snapshot == before, "purity: plan mutated the caller snapshot")
	var reversed: Dictionary = before.duplicate(true)
	(reversed["enemies"] as Array).reverse()
	var backward: Dictionary = tactics.plan(reversed)
	_expect(bool(forward.ok) and forward == backward, "ordering: reversed enemy input changed intents")
	var ids: Array[int] = []
	for intent: Dictionary in forward.intents:
		ids.append(int(intent.entity_id))
		for field in ["entity_id", "move_direction", "speed_scale", "request_action", "action_direction", "action_distance", "reason"]:
			_expect(intent.has(field), "intent schema: entity %d is missing %s" % [int(intent.entity_id), field])
		if String(intent.request_action) == "charge":
			_expect(float(intent.action_distance) > 0.0, "intent schema: charge has no positive action_distance")
		else:
			_expect(is_zero_approx(float(intent.action_distance)), "intent schema: non-charge intent leaked action_distance")
	_expect(ids == [2, 5, 9], "ordering: output is not sorted by stable entity_id: %s" % str(ids))


func _test_melee_ring_and_separation() -> void:
	var enemies := [
		_enemy(1, "melee_pursuer", Vector2(100.0, 240.0)),
		_enemy(2, "melee_pursuer", Vector2(104.0, 240.0)),
		_enemy(3, "melee_pursuer", Vector2(108.0, 240.0)),
	]
	var result: Dictionary = tactics.plan(_base_snapshot(enemies))
	var directions := {}
	for intent: Dictionary in result.intents:
		directions[Vector2(intent.move_direction)] = true
		_expect(String(intent.reason) == "melee_ring_slot", "melee: pursuer did not approach its ring slot")
	_expect(directions.size() == 3, "melee: ring slots/separation did not yield unique intents")
	var in_range := tactics.plan(_base_snapshot([_enemy(7, "melee_pursuer", Vector2(298.0, 240.0))]))
	_expect(String(in_range.intents[0].request_action) == "melee_attack", "melee: true melee range did not request attack")
	_expect(Vector2(in_range.intents[0].move_direction) == Vector2.ZERO, "melee: attack intent translated")


func _test_charger_ranges() -> void:
	var far: Dictionary = tactics.plan(_base_snapshot([_enemy(4, "charging_raider", Vector2(20.0, 240.0))])).intents[0]
	_expect(String(far.reason) == "charger_approach" and Vector2(far.move_direction).x > 0.0, "charger: far range did not approach")
	var band: Dictionary = tactics.plan(_base_snapshot([_enemy(4, "charging_raider", Vector2(180.0, 240.0))])).intents[0]
	_expect(String(band.request_action) == "charge" and Vector2(band.action_direction) == Vector2(1.0, 0.0), "charger: launch band did not freeze charge toward snapshot player")
	_expect(is_equal_approx(float(band.action_distance), 140.0), "charger: launch band did not freeze the 140px contact distance")
	var close: Dictionary = tactics.plan(_base_snapshot([_enemy(4, "charging_raider", Vector2(300.0, 240.0))])).intents[0]
	_expect(String(close.request_action).is_empty() and String(close.reason) == "charger_create_space", "charger: point-blank range requested a charge")
	_expect(Vector2(close.move_direction).x < 0.0, "charger: point-blank range did not create space")
	var setup: Dictionary = tactics.plan(_base_snapshot([_enemy(5, "charging_raider", Vector2(250.0, 240.0))])).intents[0]
	_expect(String(setup.request_action).is_empty() and String(setup.reason) == "charger_strafe_for_band", "charger: below launch minimum did not strafe for spacing")


func _test_charger_padding_contact_projection() -> void:
	var authored_arena := Rect2(0.0, 0.0, 640.0, 480.0)
	for layout_id in ["rectangle_arena", "corridor"]:
		var player_geometry := ArenaGeometry.from_layout(layout_id, authored_arena, 14.0)
		var enemy_geometry := ArenaGeometry.from_layout(layout_id, authored_arena, 16.0)
		var player := Vector2(float(player_geometry.bounds.position.x), float(player_geometry.center.y))
		var enemy_position := player + Vector2.RIGHT * 100.0
		var player_check: Dictionary = ArenaGeometry.project(player, player_geometry)
		var contact: Dictionary = ArenaGeometry.project(player, enemy_geometry)
		_expect(bool(player_check.ok) and Vector2(player_check.position).is_equal_approx(player), "charger %s padding: player edge is not legal under padding 14" % layout_id)
		_expect(bool(contact.ok) and player.distance_to(Vector2(contact.position)) <= EnemyTacticsScript.CHARGER_CONTACT_RADIUS, "charger %s padding: projected contact left the shared hit tolerance" % layout_id)
		var snapshot := _base_snapshot([_enemy(20, "charging_raider", enemy_position)], [], enemy_geometry.bounds, enemy_geometry)
		snapshot["player_position"] = player
		var intent: Dictionary = tactics.plan(snapshot).intents[0]
		_expect(String(intent.request_action) == "charge", "charger %s padding: legal edge target did not start charge" % layout_id)
		_expect(Vector2(intent.action_direction).is_equal_approx(enemy_position.direction_to(Vector2(contact.position))), "charger %s padding: frozen direction did not target projected contact" % layout_id)
		_expect(is_equal_approx(float(intent.action_distance), snappedf(enemy_position.distance_to(Vector2(contact.position)), 0.001)) and is_equal_approx(float(intent.action_distance), 98.0), "charger %s padding: action_distance did not freeze the projected 98px segment" % layout_id)
		var execution_endpoint := enemy_position + Vector2(intent.action_direction).normalized() * float(intent.action_distance)
		var execution_path: Dictionary = ArenaGeometry.line_segment_walkable(enemy_position, execution_endpoint, enemy_geometry)
		_expect(bool(execution_path.ok) and bool(execution_path.walkable), "charger %s padding: serialized execution endpoint is not walkable" % layout_id)

	var player_geometry := ArenaGeometry.from_layout("rectangle_arena", authored_arena, 14.0)
	var enemy_geometry := ArenaGeometry.from_layout("rectangle_arena", authored_arena, 30.0)
	var player := Vector2(float(player_geometry.bounds.position.x), float(player_geometry.center.y))
	var enemy_position := player + Vector2.RIGHT * 100.0
	var contact: Dictionary = ArenaGeometry.project(player, enemy_geometry)
	_expect(player.distance_to(Vector2(contact.position)) > EnemyTacticsScript.CHARGER_CONTACT_RADIUS, "charger padding: unreachable fixture did not exceed contact tolerance")
	var snapshot := _base_snapshot([_enemy(21, "charging_raider", enemy_position)], [], enemy_geometry.bounds, enemy_geometry)
	snapshot["player_position"] = player
	var blocked: Dictionary = tactics.plan(snapshot).intents[0]
	_expect(String(blocked.request_action).is_empty() and String(blocked.reason) == "charger_contact_unreachable", "charger padding: target beyond contact tolerance requested charge")
	_expect(is_zero_approx(float(blocked.action_distance)), "charger padding: rejected target leaked action_distance")


func _test_fan_ranges_and_strafe() -> void:
	var far: Dictionary = tactics.plan(_base_snapshot([_enemy(2, "fan_ranged", Vector2(20.0, 240.0))])).intents[0]
	_expect(String(far.reason) == "fan_approach" and Vector2(far.move_direction).x > 0.0, "fan: far range did not approach")
	var close: Dictionary = tactics.plan(_base_snapshot([_enemy(2, "fan_ranged", Vector2(220.0, 240.0))])).intents[0]
	_expect(String(close.reason) == "fan_retreat" and Vector2(close.move_direction).x < 0.0, "fan: close range did not retreat")
	var legal: Dictionary = tactics.plan(_base_snapshot([_enemy(2, "fan_ranged", Vector2(150.0, 240.0))])).intents[0]
	_expect(String(legal.request_action) == "fan_attack", "fan: legal distance band did not request fan attack")
	var even: Dictionary = tactics.plan(_base_snapshot([_enemy(2, "fan_ranged", Vector2(200.0, 240.0), "range_hold")])).intents[0]
	var odd: Dictionary = tactics.plan(_base_snapshot([_enemy(3, "fan_ranged", Vector2(200.0, 240.0), "range_hold")])).intents[0]
	_expect(String(even.reason) == "fan_strafe_hold" and String(odd.reason) == "fan_strafe_hold", "fan: hysteresis hold did not strafe")
	_expect(signf(Vector2(even.move_direction).y) == -signf(Vector2(odd.move_direction).y), "fan: entity parity did not choose opposite strafes")
	var hysteresis: Dictionary = tactics.plan(_base_snapshot([_enemy(2, "fan_ranged", Vector2(198.0, 240.0), "range_hold")])).intents[0]
	_expect(String(hysteresis.reason) != "fan_retreat", "fan: exit hysteresis collapsed to enter threshold")
	var breathing_enemy := _enemy(2, "fan_ranged", Vector2(150.0, 240.0))
	breathing_enemy["next_action_ready_tick"] = 130
	var breathing: Dictionary = tactics.plan(_base_snapshot([breathing_enemy])).intents[0]
	_expect(String(breathing.request_action).is_empty() and String(breathing.reason) == "fan_strafe_hold", "fan: post-action breath did not produce a real strafe window")


func _test_fan_attack_radius_boundary() -> void:
	var center := DEFAULT_ARENA.get_center()
	var epsilon := 0.01
	for distance in [EnemyTacticsScript.FAN_ATTACK_RADIUS - epsilon, EnemyTacticsScript.FAN_ATTACK_RADIUS]:
		var intent: Dictionary = tactics.plan(_base_snapshot([_enemy(2, "fan_ranged", center - Vector2.RIGHT * distance)])).intents[0]
		_expect(String(intent.request_action) == "fan_attack", "fan: %.2f should be within the authored attack radius" % distance)
	var outside: Dictionary = tactics.plan(_base_snapshot([_enemy(2, "fan_ranged", center - Vector2.RIGHT * (EnemyTacticsScript.FAN_ATTACK_RADIUS + epsilon))])).intents[0]
	_expect(String(outside.request_action).is_empty() and String(outside.reason) == "fan_strafe_hold" and Vector2(outside.move_direction) != Vector2.ZERO, "fan: just outside the authored attack radius still requested an attack")


func _test_fan_strafe_liveness() -> void:
	var player := DEFAULT_ARENA.get_center()
	var snapshot := _base_snapshot([])
	snapshot["player_position"] = player
	var position := player - Vector2.RIGHT * 200.0
	var attack_tick := -1
	for tick in 96:
		var fan := _enemy(2, "fan_ranged", position, "range_hold")
		snapshot["tick"] = tick
		snapshot["enemies"] = [fan]
		var intent: Dictionary = tactics.plan(snapshot).intents[0]
		if String(intent.request_action) == "fan_attack":
			attack_tick = tick
			_expect(position.distance_to(player) <= EnemyTacticsScript.FAN_ATTACK_RADIUS, "fan liveness: attack started outside the authored radius")
			break
		_expect(String(intent.reason) == "fan_strafe_hold" and Vector2(intent.move_direction) != Vector2.ZERO, "fan liveness: tick %d stopped readable hold movement" % tick)
		var radial := position.direction_to(player)
		var tangent := Vector2(-radial.y, radial.x)
		_expect(absf(Vector2(intent.move_direction).dot(tangent)) >= 0.5, "fan liveness: tick %d lost its readable strafe component" % tick)
		var step := Vector2(intent.move_direction) * 58.0 * float(intent.speed_scale) / 30.0
		var projected: Dictionary = ArenaGeometry.project(position + step, snapshot["walkable_geometry"])
		_expect(bool(projected.ok) and position.distance_to(Vector2(projected.position)) > 0.01, "fan liveness: tick %d hold movement was swallowed" % tick)
		position = Vector2(projected.position)
	_expect(attack_tick >= 0 and attack_tick <= 96, "fan liveness: stationary target at 200 never entered the legal attack band")


func _test_fan_lane_order_invariance() -> void:
	var enemies := [
		_enemy(8, "fan_ranged", Vector2(150.0, 240.0)),
		_enemy(3, "fan_ranged", Vector2(160.0, 240.0)),
	]
	var forward: Dictionary = tactics.plan(_base_snapshot(enemies))
	var reversed_enemies: Array = enemies.duplicate(true)
	reversed_enemies.reverse()
	var backward: Dictionary = tactics.plan(_base_snapshot(reversed_enemies))
	_expect(forward == backward, "lane ordering: reversed fan input changed arbitration")
	var winner := _intent_for(forward, 3)
	var waiter := _intent_for(forward, 8)
	_expect(String(winner.request_action) == "fan_attack", "lane ordering: lowest fan entity_id did not win")
	_expect(String(waiter.request_action).is_empty(), "lane ordering: second fan also requested an action")
	_expect(Vector2(waiter.move_direction) != Vector2.ZERO, "lane ordering: waiting fan did not strafe")
	_expect(String(waiter.reason).contains("action_lane_occupied"), "lane ordering: waiting fan reason did not identify lane occupancy")


func _test_fan_lane_wait_approaches_attack_range() -> void:
	var player := DEFAULT_ARENA.get_center()
	var snapshot := _base_snapshot([])
	snapshot["player_position"] = player
	var position := player - Vector2.RIGHT * 200.0
	var initial_distance := position.distance_to(player)
	var ordering_snapshot := _base_snapshot([
		_enemy(9, "fan_ranged", position, "range_hold"),
		_enemy(2, "fan_ranged", player - Vector2.RIGHT * 150.0, "windup"),
	])
	ordering_snapshot["player_position"] = player
	var reversed_ordering_snapshot: Dictionary = ordering_snapshot.duplicate(true)
	var reversed_enemies: Array = reversed_ordering_snapshot["enemies"]
	reversed_enemies.reverse()
	reversed_ordering_snapshot["enemies"] = reversed_enemies
	_expect(tactics.plan(ordering_snapshot) == tactics.plan(reversed_ordering_snapshot), "fan lane approach: reversed input changed occupied-lane planning")
	for tick in 12:
		snapshot["tick"] = tick
		snapshot["enemies"] = [
			_enemy(2, "fan_ranged", player - Vector2.RIGHT * 150.0, "windup"),
			_enemy(9, "fan_ranged", position, "range_hold"),
		]
		var waiting := _intent_for(tactics.plan(snapshot), 9)
		var radial := position.direction_to(player)
		_expect(String(waiting.request_action).is_empty() and String(waiting.reason) == "fan_action_lane_occupied", "fan lane approach: tick %d did not remain a blocked waiter" % tick)
		_expect(Vector2(waiting.move_direction).dot(radial) > 0.45, "fan lane approach: tick %d lost its inward component outside the attack radius" % tick)
		position += Vector2(waiting.move_direction) * 58.0 * float(waiting.speed_scale) / 30.0
	_expect(position.distance_to(player) < initial_distance - 5.0, "fan lane approach: occupied lane did not reduce the waiting fan distance")

	var inside_position := player - Vector2.RIGHT * 160.0
	var inside := _intent_for(tactics.plan(_base_snapshot([
		_enemy(2, "fan_ranged", player - Vector2.RIGHT * 150.0, "windup"),
		_enemy(9, "fan_ranged", inside_position, "range_hold"),
	])), 9)
	var inside_radial := inside_position.direction_to(player)
	_expect(String(inside.reason) == "fan_action_lane_occupied" and absf(Vector2(inside.move_direction).dot(inside_radial)) <= 0.01, "fan lane approach: fan inside the attack radius pressed inward while waiting")


func _test_snapshot_lane_occupancy_and_recovery_handoff() -> void:
	var waiting := _enemy(9, "fan_ranged", Vector2(160.0, 240.0))
	var acting := _enemy(2, "fan_ranged", Vector2(150.0, 240.0), "windup")
	for occupied_state in ["windup", "active"]:
		acting["action_state"] = occupied_state
		var occupied: Dictionary = tactics.plan(_base_snapshot([waiting, acting]))
		var blocked := _intent_for(occupied, 9)
		_expect(String(blocked.request_action).is_empty(), "snapshot lane: %s fan did not block a new fan action" % occupied_state)
		_expect(Vector2(blocked.move_direction) != Vector2.ZERO and String(blocked.reason).contains("action_lane_occupied"), "snapshot lane: %s did not produce lane-wait movement" % occupied_state)

	acting["action_state"] = "recovery"
	var released: Dictionary = tactics.plan(_base_snapshot([waiting, acting]))
	var recovering := _intent_for(released, 2)
	var successor := _intent_for(released, 9)
	_expect(String(recovering.reason) == "action_locked" and String(recovering.request_action).is_empty(), "snapshot lane: recovering actor stopped being locked")
	_expect(String(successor.request_action) == "fan_attack", "snapshot lane: recovery did not release the lane to a waiter")


func _test_one_action_per_kind_with_moving_waiters() -> void:
	var cases := [
		{"kind": "melee_pursuer", "positions": [Vector2(298.0, 240.0), Vector2(300.0, 240.0)]},
		{"kind": "charging_raider", "positions": [Vector2(180.0, 240.0), Vector2(170.0, 240.0)]},
		{"kind": "fan_ranged", "positions": [Vector2(150.0, 240.0), Vector2(160.0, 240.0)]},
	]
	for case: Dictionary in cases:
		var positions: Array = case["positions"]
		var result: Dictionary = tactics.plan(_base_snapshot([
			_enemy(1, String(case["kind"]), positions[0]),
			_enemy(2, String(case["kind"]), positions[1]),
		]))
		var action_count := 0
		var waiter_count := 0
		for intent: Dictionary in result.intents:
			if not String(intent.request_action).is_empty():
				action_count += 1
			else:
				waiter_count += 1
				_expect(Vector2(intent.move_direction) != Vector2.ZERO, "lane %s: waiter had zero movement" % String(case["kind"]))
				_expect(String(intent.reason).contains("action_lane_occupied"), "lane %s: waiter reason missed lane occupancy" % String(case["kind"]))
		_expect(action_count == 1 and waiter_count == 1, "lane %s: expected one action and one moving waiter" % String(case["kind"]))


func _test_independent_kind_lanes() -> void:
	var result: Dictionary = tactics.plan(_base_snapshot([
		_enemy(1, "melee_pursuer", Vector2(298.0, 240.0)),
		_enemy(2, "charging_raider", Vector2(180.0, 240.0)),
		_enemy(3, "fan_ranged", Vector2(150.0, 240.0)),
	]))
	var actions: Array[String] = []
	for intent: Dictionary in result.intents:
		actions.append(String(intent.request_action))
	_expect(actions == ["melee_attack", "charge", "fan_attack"], "lane kinds: independent kinds did not act together: %s" % str(actions))
	_expect(is_zero_approx(float(result.intents[0].action_distance)) and float(result.intents[1].action_distance) > 0.0 and is_zero_approx(float(result.intents[2].action_distance)), "lane kinds: action_distance leaked outside charge")


func _test_locked_action() -> void:
	for state in ["windup", "active", "recovery", "transition"]:
		var intent: Dictionary = tactics.plan(_base_snapshot([_enemy(11, "charging_raider", Vector2(180.0, 240.0), state)])).intents[0]
		_expect(Vector2(intent.move_direction) == Vector2.ZERO and is_zero_approx(float(intent.speed_scale)), "locked: %s translated" % state)
		_expect(String(intent.request_action).is_empty() and String(intent.reason) == "action_locked", "locked: %s requested a new action" % state)


func _test_boss_cycle() -> void:
	var boss := _enemy(20, "threshold_colossus", Vector2(320.0, 100.0))
	var sealed: Dictionary = tactics.plan(_base_snapshot([boss])).intents[0]
	_expect(String(sealed.request_action) == "slam" and Vector2(sealed.move_direction) == Vector2.ZERO, "boss: sealed contract is not stationary slam")
	var second_boss := _enemy(21, "threshold_colossus", Vector2(360.0, 100.0))
	var simultaneous: Dictionary = tactics.plan(_base_snapshot([second_boss, boss]))
	_expect(String(_intent_for(simultaneous, 20).request_action) == "slam" and String(_intent_for(simultaneous, 21).request_action) == "slam", "boss: ordinary action lanes affected simultaneous bosses")
	boss["phase"] = "awakened"
	var actions: Array[String] = []
	for index in 6:
		boss["next_action_index"] = index
		actions.append(String(tactics.plan(_base_snapshot([boss])).intents[0].request_action))
	_expect(actions == ["slam", "sweep", "lane", "slam", "sweep", "lane"], "boss: awakened cycle changed: %s" % str(actions))


func _test_arena_and_hazard_scoring() -> void:
	var edge_enemy := _enemy(8, "charging_raider", Vector2(620.0, 240.0))
	var snapshot := _base_snapshot([edge_enemy])
	var desired := Vector2.RIGHT
	var outside_score := tactics.score_candidate_direction(snapshot, edge_enemy, desired, Vector2.RIGHT)
	var inside_score := tactics.score_candidate_direction(snapshot, edge_enemy, desired, Vector2.LEFT)
	_expect(outside_score > inside_score, "scoring: leaving arena was not penalized")

	var hazard_snapshot := _base_snapshot([_enemy(8, "charging_raider", Vector2(200.0, 240.0))], [{
		"active_geometry": {"shape": "circle", "center": Vector2(234.0, 240.0), "radius": 18.0},
		"warning_geometry": {"shape": "rect", "rect": Rect2(215.0, 215.0, 45.0, 50.0)},
	}])
	var enemy: Dictionary = hazard_snapshot.enemies[0]
	var hazard_score := tactics.score_candidate_direction(hazard_snapshot, enemy, Vector2.RIGHT, Vector2.RIGHT)
	var clear_score := tactics.score_candidate_direction(hazard_snapshot, enemy, Vector2.RIGHT, Vector2.UP)
	_expect(hazard_score > clear_score, "scoring: public active/warning hazard geometry was ignored")
	var chosen := tactics.choose_candidate_direction(hazard_snapshot, enemy, Vector2.RIGHT)
	_expect(chosen != Vector2.RIGHT, "scoring: planner selected the hazardous candidate")

	var crowded_snapshot := _base_snapshot([
		_enemy(8, "melee_pursuer", Vector2(200.0, 240.0)),
		_enemy(9, "melee_pursuer", Vector2(234.0, 240.0)),
	])
	var crowded_enemy: Dictionary = crowded_snapshot.enemies[0]
	var overlap_score := tactics.score_candidate_direction(crowded_snapshot, crowded_enemy, Vector2.RIGHT, Vector2.RIGHT)
	var separated_score := tactics.score_candidate_direction(crowded_snapshot, crowded_enemy, Vector2.RIGHT, Vector2.UP)
	_expect(overlap_score > separated_score, "scoring: projected crowd overlap was not penalized")


func _test_ring_inner_antipode_planning() -> void:
	# This height yields a 91.2-unit inner radius, so antipodes are 182.4
	# units apart and sit inside the charger's ordinary 88..190 launch band.
	var arena := Rect2(0.0, 0.0, 640.0, 456.0)
	var geometry := ArenaGeometry.from_layout("ring", arena, 0.0)
	var center: Vector2 = geometry["center"]
	var inner_radius := float(geometry["inner_radius"])
	var enemy_position := center - Vector2.RIGHT * inner_radius
	var antipode := center + Vector2.RIGHT * inner_radius
	_expect(is_equal_approx(enemy_position.distance_to(antipode), 182.4), "ring charger: antipode fixture left the launch band")

	var charger_snapshot := _base_snapshot([_enemy(2, "charging_raider", enemy_position)], [], arena, geometry)
	charger_snapshot["player_position"] = antipode
	var initial: Dictionary = tactics.plan(charger_snapshot).intents[0]
	_expect(String(initial.request_action).is_empty() and String(initial.reason) == "charger_path_blocked", "ring charger: blocked launch chord requested charge")
	_expect(Vector2(initial.move_direction) != Vector2.ZERO and absf(Vector2.RIGHT.cross(Vector2(initial.move_direction))) >= 0.8, "ring charger: blocked launch did not produce a feasible tangent/setup move")

	var simulated_position := enemy_position
	var launch_iteration := -1
	for iteration in 360:
		charger_snapshot["enemies"] = [_enemy(2, "charging_raider", simulated_position)]
		var intent: Dictionary = tactics.plan(charger_snapshot).intents[0]
		var path: Dictionary = ArenaGeometry.line_segment_walkable(simulated_position, antipode, geometry)
		if String(intent.request_action) == "charge":
			launch_iteration = iteration
			var expected_distance := snappedf(simulated_position.distance_to(antipode), 0.001)
			var execution_endpoint := simulated_position + Vector2(intent.action_direction).normalized() * float(intent.action_distance)
			var execution_path: Dictionary = ArenaGeometry.line_segment_walkable(simulated_position, execution_endpoint, geometry)
			_expect(bool(path.ok) and bool(path.walkable), "ring charger: iterative planner launched before the contact chord became walkable")
			_expect(is_equal_approx(float(intent.action_distance), expected_distance), "ring charger: action_distance did not match projected contact distance")
			_expect(bool(execution_path.ok) and bool(execution_path.walkable), "ring charger: quantized execution endpoint left the validated chord")
			break
		var distance := simulated_position.distance_to(antipode)
		if distance >= EnemyTacticsScript.CHARGER_LAUNCH_MIN_RANGE and distance <= EnemyTacticsScript.CHARGER_LAUNCH_MAX_RANGE:
			_expect(not bool(path.walkable), "ring charger: planner kept moving after a legal in-band launch chord was available")
			_expect(String(intent.reason) == "charger_path_blocked", "ring charger: blocked in-band setup reason changed at iteration %d" % iteration)
		var step := Vector2(intent.move_direction) * 62.0 / 30.0 * float(intent.speed_scale)
		var projected: Dictionary = ArenaGeometry.project(simulated_position + step, geometry)
		_expect(bool(projected.ok) and simulated_position.distance_to(Vector2(projected.position)) > 0.01, "ring charger: setup movement was swallowed at iteration %d" % iteration)
		simulated_position = projected.position
	_expect(launch_iteration >= 0, "ring charger: deterministic setup never produced a legal launch chord")

	# Retain the wider ring used by the existing all-role detour controls so fan
	# and charger remain outside their action bands in this movement-only check.
	arena = Rect2(0.0, 0.0, 640.0, 640.0)
	geometry = ArenaGeometry.from_layout("ring", arena, 0.0)
	center = geometry["center"]
	inner_radius = float(geometry["inner_radius"])
	enemy_position = center - Vector2.RIGHT * inner_radius
	antipode = center + Vector2.RIGHT * inner_radius
	for kind_id in ["melee_pursuer", "charging_raider", "fan_ranged"]:
		var even_id := 6 if kind_id == "melee_pursuer" else (2 if kind_id == "charging_raider" else 4)
		var odd_id := even_id + 1
		var even_direction := _ring_direction_for(kind_id, even_id, arena, geometry, enemy_position, antipode)
		var odd_direction := _ring_direction_for(kind_id, odd_id, arena, geometry, enemy_position, antipode)
		_expect(signf(Vector2.RIGHT.cross(even_direction)) == 1.0, "ring %s: even ID did not choose the stable positive tangent" % kind_id)
		_expect(signf(Vector2.RIGHT.cross(odd_direction)) == -1.0, "ring %s: odd ID did not choose the stable negative tangent" % kind_id)

	var combined_player := antipode + Vector2.RIGHT * EnemyTacticsScript.MELEE_RING_RADIUS
	var combined_enemies := [
		_enemy(6, "melee_pursuer", enemy_position),
		_enemy(2, "charging_raider", enemy_position),
		_enemy(4, "fan_ranged", enemy_position),
	]
	var forward_snapshot := _base_snapshot(combined_enemies, [], arena, geometry)
	forward_snapshot["player_position"] = combined_player
	var forward: Dictionary = tactics.plan(forward_snapshot)
	var reversed_enemies: Array = combined_enemies.duplicate(true)
	reversed_enemies.reverse()
	var backward_snapshot := _base_snapshot(reversed_enemies, [], arena, geometry)
	backward_snapshot["player_position"] = combined_player
	var backward: Dictionary = tactics.plan(backward_snapshot)
	_expect(forward == backward, "ring ordering: reversed enemy input changed geometry-aware intents")


func _ring_direction_for(kind_id: String, entity_id: int, arena: Rect2, geometry: Dictionary, enemy_position: Vector2, antipode: Vector2) -> Vector2:
	var player_position := antipode
	if kind_id == "melee_pursuer":
		var slot_angle := TAU * float(posmod(entity_id, EnemyTacticsScript.MELEE_SLOT_COUNT)) / float(EnemyTacticsScript.MELEE_SLOT_COUNT)
		player_position -= Vector2.RIGHT.rotated(slot_angle) * EnemyTacticsScript.MELEE_RING_RADIUS
	var snapshot := _base_snapshot([_enemy(entity_id, kind_id, enemy_position)], [], arena, geometry)
	snapshot["player_position"] = player_position
	var radial_projection: Dictionary = ArenaGeometry.project(enemy_position + Vector2.RIGHT * EnemyTacticsScript.CANDIDATE_LOOKAHEAD, geometry)
	_expect(enemy_position.distance_to(Vector2(radial_projection["position"])) <= 0.01, "ring %s: fixture radial step was not swallowed" % kind_id)
	var result: Dictionary = tactics.plan(snapshot)
	_expect(bool(result.ok), "ring %s: valid geometry snapshot failed" % kind_id)
	var direction := Vector2(result.intents[0].move_direction)
	var landing: Dictionary = ArenaGeometry.project(enemy_position + direction * EnemyTacticsScript.CANDIDATE_LOOKAHEAD, geometry)
	_expect(String(result.intents[0].request_action).is_empty(), "ring %s: fixture unexpectedly requested an action" % kind_id)
	_expect(enemy_position.distance_to(Vector2(landing["position"])) > 0.01, "ring %s: planner kept a swallowed radial direction" % kind_id)
	_expect(absf(Vector2.RIGHT.cross(direction)) >= 0.8, "ring %s: planner did not choose a tangentially feasible detour: %s" % [kind_id, str(direction)])
	return direction


func _test_rectangle_geometry_straight_controls() -> void:
	var arena := Rect2(0.0, 0.0, 640.0, 640.0)
	var geometry := ArenaGeometry.from_layout("rectangle", arena, 0.0)
	var player := Vector2(468.0, 320.0)
	var enemies := [
		_enemy(6, "melee_pursuer", Vector2(100.0, 320.0)),
		_enemy(2, "charging_raider", Vector2(100.0, 320.0)),
		_enemy(4, "fan_ranged", Vector2(100.0, 320.0)),
	]
	for enemy: Dictionary in enemies:
		var snapshot := _base_snapshot([enemy], [], arena, geometry)
		snapshot["player_position"] = player
		var intent: Dictionary = tactics.plan(snapshot).intents[0]
		_expect(Vector2(intent.move_direction) == Vector2.RIGHT, "rectangle %s: unobstructed approach stopped moving straight" % String(enemy["kind_id"]))


func _test_quantization() -> void:
	var intent: Dictionary = tactics.plan(_base_snapshot([_enemy(13, "melee_pursuer", Vector2(37.1234, 91.9876))])).intents[0]
	var charge: Dictionary = tactics.plan(_base_snapshot([_enemy(14, "charging_raider", Vector2(180.1234, 240.0))])).intents[0]
	for value: float in [Vector2(intent.move_direction).x, Vector2(intent.move_direction).y, float(intent.speed_scale), Vector2(intent.action_direction).x, Vector2(intent.action_direction).y, float(intent.action_distance), Vector2(charge.action_direction).x, Vector2(charge.action_direction).y, float(charge.action_distance)]:
		_expect(is_equal_approx(value, snappedf(value, 0.001)), "quantization: output %.9f is not fixed to 0.001" % value)
	_expect(Vector2(intent.move_direction).length() <= 1.001, "quantization: move direction was not clamped")
	_expect(String(charge.request_action) == "charge" and float(charge.action_distance) > 0.0, "quantization: charge action_distance was not preserved")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _intent_for(result: Dictionary, entity_id: int) -> Dictionary:
	for intent: Dictionary in result.get("intents", []):
		if int(intent.get("entity_id", -1)) == entity_id:
			return intent
	return {}


func _test_polygon_steering_lane() -> void:
	var enemy := _enemy(1, "charging_raider", Vector2(300, 240))
	var snapshot := _base_snapshot([enemy])
	var plain: float = tactics.score_candidate_direction(snapshot, enemy, Vector2.RIGHT, Vector2.RIGHT)
	# Two long wall rectangles leave a 60px lane. Their bounding circles cover
	# that lane, but their actual edges leave a radius-16 actor room to pass.
	snapshot["static_blockers"] = [
		{"center": Vector2(320, 155), "radius": 220.0,
		 "points": PackedVector2Array([Vector2(100, 100), Vector2(540, 100), Vector2(540, 210), Vector2(100, 210)])},
		{"center": Vector2(320, 325), "radius": 220.0,
		 "points": PackedVector2Array([Vector2(100, 270), Vector2(540, 270), Vector2(540, 380), Vector2(100, 380)])},
	]
	var along: float = tactics.score_candidate_direction(snapshot, enemy, Vector2.RIGHT, Vector2.RIGHT)
	var into_wall: float = tactics.score_candidate_direction(snapshot, enemy, Vector2.RIGHT, Vector2.UP)
	_expect(is_equal_approx(along, plain), "polygon steering: legal lane inherited the enclosing-circle penalty")
	_expect(into_wall > along + 100.0, "polygon steering: entering the actual wall was not penalized")
	_expect(tactics.choose_candidate_direction(snapshot, enemy, Vector2.RIGHT).is_equal_approx(Vector2.RIGHT), "polygon steering: clear lane detoured")
