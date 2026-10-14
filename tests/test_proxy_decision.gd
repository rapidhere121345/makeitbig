extends SceneTree

const ContentRegistry := preload("res://src/content/content_registry.gd")
const ProxyBuild := preload("res://src/systems/proxy_build.gd")
const Decision := preload("res://src/systems/proxy_decision.gd")
const Protocol := preload("res://src/systems/combat_command_protocol.gd")
const ArenaGeometry := preload("res://src/runtime/geometry/arena_geometry.gd")
const TEST_ARENA := Rect2(-320.0, -320.0, 640.0, 640.0)

var builds := {}


func _initialize() -> void:
	var failures: Array[String] = []
	var registry := ContentRegistry.new()
	var errors: Array[String] = registry.load_all()
	_expect(errors.is_empty(), "catalog failed to load: %s" % str(errors), failures)
	if errors.is_empty():
		builds.white = _compile(registry.cores, "near_enemy_horizon", "direct_gait")
		builds.marking_direct = _compile(registry.cores, "marking_prism", "direct_gait")
		for band in ["near", "mid", "far"]:
			builds[band] = _compile(registry.cores, "near_enemy_horizon", "distance_keeping_gait", band)
		for key in builds:
			_expect(not builds[key].is_empty(), "build fixture %s failed" % key, failures)
		_test_resolved_only_and_exact_schemas(failures)
		_test_snapshot_v3_observation_authority(failures)
		_test_near_retention_and_order(failures)
		_test_marking_priority_and_two_candidate_fallback(failures)
		_test_direct_thresholds_and_execution(failures)
		_test_distance_settings(failures)
		_test_no_progress_and_isolation(failures)
		_test_deterministic_continuation(failures)
	if failures.is_empty():
		print("PASS  test_proxy_decision.gd")
		quit(0)
		return
	for failure in failures:
		printerr("- %s" % failure)
	quit(1)


func _test_resolved_only_and_exact_schemas(failures: Array[String]) -> void:
	var white: Dictionary = builds.white
	var state := Decision.initial_state(white)
	_expect(state.keys() == ["state_version", "last_committed_action", "movement_band", "next_perception_tick", "target_entity_id"], "white initial state is not state_version plus its exact contract", failures)
	var marking_state := Decision.initial_state(builds.marking_direct)
	_expect(marking_state.keys() == ["state_version", "candidate_entity_ids", "last_committed_action", "movement_band", "next_perception_tick", "target_entity_id"], "marking initial state lacks its owned candidate field", failures)
	_expect(Decision.initial_state({}).is_empty(), "invalid resolved build produced state", failures)
	var snapshot := _snapshot(0, [_enemy(1, Vector2(5, 0))])
	var raw := {"cores": ["near_enemy_horizon", "direct_gait", "single_key_execution", "short_trace_memory"]}
	_expect(not Decision.decide(snapshot, raw, state, 0).ok, "Decision accepted raw core ids", failures)
	var stale := white.duplicate(true)
	stale.cores[0].capabilities.refresh_period_ticks = 31
	var stale_result := Decision.decide(snapshot, stale, state, 0)
	_expect(not stale_result.ok and stale_result.error == "semantic_fingerprint_mismatch" and stale_result.commands.is_empty(), "stale resolved fingerprint did not fail closed", failures)
	var extra_state := state.duplicate(true)
	extra_state.future = true
	_expect(Decision.decide(snapshot, white, extra_state, 0).error == "invalid_state", "extra state field was accepted", failures)
	var wrong_state := state.duplicate(true)
	wrong_state.state_version = 2
	_expect(Decision.decide(snapshot, white, wrong_state, 0).error == "wrong_state_version", "wrong state version was accepted", failures)
	_expect(Decision.decide(snapshot, white, state, -1).error == "invalid_sequence_start", "negative sequence was accepted", failures)


func _test_snapshot_v3_observation_authority(failures: Array[String]) -> void:
	var white: Dictionary = builds.white
	var white_state := Decision.initial_state(white)
	var valid := _snapshot(0, [_enemy(1, Vector2(5, 0))])
	_expect(Decision.decide(valid, white, white_state, 0).ok, "valid white snapshot v3 was rejected", failures)
	var old := valid.duplicate(true)
	old.snapshot_version = 2
	_expect(Decision.decide(old, white, white_state, 0).error == "wrong_snapshot_version", "snapshot v2 was accepted", failures)
	var extra := valid.duplicate(true)
	extra.hazards = []
	_expect(Decision.decide(extra, white, white_state, 0).error == "invalid_snapshot", "extra snapshot data was accepted", failures)
	forbidden_enemy_field(valid, "status", failures)
	forbidden_enemy_field(valid, "telegraph", failures)
	var white_tagged := valid.duplicate(true)
	white_tagged.visible_enemies[0].classification_tags = ["boss"]
	_expect(Decision.decide(white_tagged, white, white_state, 0).error == "invalid_snapshot", "white build accepted classification tags", failures)
	var marking_snapshot := _snapshot(0, [_enemy(1, Vector2(5, 0), 10.0, true, ["boss"], true)], true)
	var marking_result := Decision.decide(marking_snapshot, builds.marking_direct, Decision.initial_state(builds.marking_direct), 0)
	_expect(marking_result.ok, "marking build rejected authorized tags: %s" % marking_result.error, failures)
	var missing_tags := _snapshot(0, [_enemy(1, Vector2(5, 0))])
	_expect(Decision.decide(missing_tags, builds.marking_direct, Decision.initial_state(builds.marking_direct), 0).error == "invalid_snapshot", "marking build accepted missing classification_tags", failures)
	for bad_tag in ["status", "hazard", "telegraph", "private"]:
		var bad := _snapshot(0, [_enemy(1, Vector2(5, 0), 10.0, true, [bad_tag])], true)
		_expect(Decision.decide(bad, builds.marking_direct, Decision.initial_state(builds.marking_direct), 0).error == "invalid_snapshot", "marking accepted forbidden tag %s" % bad_tag, failures)


func forbidden_enemy_field(snapshot: Dictionary, field: String, failures: Array[String]) -> void:
	var bad := snapshot.duplicate(true)
	bad.visible_enemies[0][field] = "secret"
	_expect(Decision.decide(bad, builds.white, Decision.initial_state(builds.white), 0).error == "invalid_snapshot", "enemy field %s was accepted" % field, failures)


func _test_near_retention_and_order(failures: Array[String]) -> void:
	var build: Dictionary = builds.white
	var enemies := [_enemy(9, Vector2(-5, 0)), _enemy(3, Vector2(5, 0))]
	var forward := Decision.decide(_snapshot(0, enemies), build, Decision.initial_state(build), 10)
	var reversed := enemies.duplicate(true)
	reversed.reverse()
	var backward := Decision.decide(_snapshot(0, reversed), build, Decision.initial_state(build), 10)
	_expect(forward == backward and int(forward.next_state.target_entity_id) == 3, "near tie/order rule changed", failures)
	_expect(int(forward.next_state.next_perception_tick) == 30, "near did not consume 30-tick capability", failures)
	var retained := Decision.decide(_snapshot(29, [_enemy(3, Vector2(12, 0)), _enemy(2, Vector2(2, 0))]), build, forward.next_state, forward.next_sequence)
	_expect(int(retained.next_state.target_entity_id) == 3 and "perception:retain_target" in retained.trace, "near changed target before horizon", failures)
	var refreshed := Decision.decide(_snapshot(30, [_enemy(3, Vector2(12, 0)), _enemy(2, Vector2(2, 0))]), build, retained.next_state, retained.next_sequence)
	_expect(int(refreshed.next_state.target_entity_id) == 2 and "perception:refresh_periodic" in refreshed.trace, "near did not refresh at horizon", failures)
	var missing := Decision.decide(_snapshot(7, [_enemy(2, Vector2(8, 0))]), build, forward.next_state, forward.next_sequence)
	_expect(int(missing.next_state.target_entity_id) == 2 and int(missing.next_state.next_perception_tick) == 37 and "perception:refresh_target_missing" in missing.trace, "near missing target did not refresh immediately", failures)
	var filtered := Decision.decide(_snapshot(0, [_enemy(1, Vector2(1, 0), 10.0, false), _enemy(2, Vector2(6, 0))]), build, Decision.initial_state(build), 0)
	_expect(int(filtered.next_state.target_entity_id) == 2, "targetable=false enemy was selected", failures)


func _test_marking_priority_and_two_candidate_fallback(failures: Array[String]) -> void:
	var build: Dictionary = builds.marking_direct
	var snapshot := _snapshot(0, [
		_enemy(10, Vector2(1, 0), 10.0, true, [], true),
		_enemy(4, Vector2(8, 0), 10.0, true, ["boss"], true),
		_enemy(3, Vector2(7, 0), 10.0, true, ["elite"], true),
		_enemy(9, Vector2(9, 0), 10.0, true, ["marked"], true),
	], true)
	var first := Decision.decide(snapshot, build, Decision.initial_state(build), 0)
	_expect(first.ok and first.next_state.candidate_entity_ids == [9, 3] and int(first.next_state.target_entity_id) == 9, "marking priority/candidate limit changed", failures)
	var primary_missing := _snapshot(1, [
		_enemy(3, Vector2(7, 0), 10.0, true, ["elite"], true),
		_enemy(4, Vector2(1, 0), 10.0, true, ["boss"], true),
	], true)
	var fallback := Decision.decide(primary_missing, build, first.next_state, first.next_sequence)
	_expect(int(fallback.next_state.target_entity_id) == 3 and fallback.next_state.candidate_entity_ids == [9, 3] and "perception:fallback_candidate" in fallback.trace, "marking did not use only the retained second candidate", failures)
	var both_missing := _snapshot(2, [_enemy(4, Vector2(1, 0), 10.0, true, ["boss"], true)], true)
	var rescanned := Decision.decide(both_missing, build, fallback.next_state, fallback.next_sequence)
	_expect(int(rescanned.next_state.target_entity_id) == 4 and rescanned.next_state.candidate_entity_ids == [4] and "perception:refresh_candidates_missing" in rescanned.trace, "marking did not rescan after both retained candidates vanished", failures)


func _test_direct_thresholds_and_execution(failures: Array[String]) -> void:
	var build: Dictionary = builds.white
	var retreat := Decision.decide(_snapshot(0, [_enemy(1, Vector2(2.5, 0))]), build, Decision.initial_state(build), 40)
	_expect(retreat.commands == [Protocol.move(0, "ranger-1", 40, -1000, 0, 720), Protocol.cast(0, "ranger-1", 41, "piercing_arrow", 1, 1000, 0)], "direct 260 threshold or piercing-only execution changed", failures)
	var retreat_hold := Decision.decide(_snapshot(1, [_enemy(1, Vector2(3.0, 0))]), build, retreat.next_state, retreat.next_sequence)
	_expect(retreat_hold.commands[0].kind == "move", "direct retreat hysteresis before 380 changed", failures)
	var retreat_exit := Decision.decide(_snapshot(2, [_enemy(1, Vector2(3.8, 0))]), build, retreat_hold.next_state, retreat_hold.next_sequence)
	_expect(retreat_exit.commands[0].kind == "stop_move", "direct retreat exit 380 changed", failures)
	var approach := Decision.decide(_snapshot(0, [_enemy(1, Vector2(8.3, 0))]), build, Decision.initial_state(build), 0)
	_expect(approach.commands[0] == Protocol.move(0, "ranger-1", 0, 1000, 0, 720), "direct approach enter 820 changed", failures)
	var approach_keep := Decision.decide(_snapshot(1, [_enemy(1, Vector2(8.0, 0))]), build, approach.next_state, approach.next_sequence)
	_expect(approach_keep.commands[0].kind == "move", "direct approach hysteresis before 780 changed", failures)
	var approach_exit := Decision.decide(_snapshot(2, [_enemy(1, Vector2(7.8, 0))]), build, approach_keep.next_state, approach_keep.next_sequence)
	_expect(approach_exit.commands[0].kind == "stop_move", "direct approach exit 780 changed", failures)
	for command in retreat.commands:
		_expect(Protocol.validate(command, 0, [Protocol.ABILITY_PIERCING_ARROW], false).status == Protocol.STATUS_ACCEPTED, "decision emitted command outside CombatCommandProtocol", failures)


func _test_distance_settings(failures: Array[String]) -> void:
	var near_retreat := Decision.decide(_snapshot(0, [_enemy(1, Vector2(2.5, 0))]), builds.near, Decision.initial_state(builds.near), 0)
	var mid_approach := Decision.decide(_snapshot(0, [_enemy(1, Vector2(8.0, 0))]), builds.mid, Decision.initial_state(builds.mid), 0)
	var far_hold := Decision.decide(_snapshot(0, [_enemy(1, Vector2(9.5, 0))]), builds.far, Decision.initial_state(builds.far), 0)
	_expect(near_retreat.next_state.movement_band == "retreat", "near profile did not consume 260/340/500/580", failures)
	_expect(mid_approach.next_state.movement_band == "approach", "mid profile did not consume 420/500/700/780", failures)
	_expect(far_hold.next_state.movement_band == "hold", "far profile did not consume 580/660/900/980", failures)
	var same_near := Decision.decide(_snapshot(0, [_enemy(1, Vector2(5.0, 0))]), builds.near, Decision.initial_state(builds.near), 0)
	var same_far := Decision.decide(_snapshot(0, [_enemy(1, Vector2(5.0, 0))]), builds.far, Decision.initial_state(builds.far), 0)
	_expect(same_near.commands[0].kind == "stop_move" and same_far.commands[0].kind == "move" and same_far.commands[0].direction_x_milli == -1000, "distance setting change did not change command at the same relative range", failures)
	var scaled := _snapshot_at(0, Vector2.ZERO, [_enemy(1, Vector2(50, 0))], 100.0)
	var scaled_near := Decision.decide(scaled, builds.near, Decision.initial_state(builds.near), 0)
	_expect(scaled_near.commands[0].kind == "stop_move", "distance profile was converted to absolute meters instead of targeting_distance milli", failures)


func _test_no_progress_and_isolation(failures: Array[String]) -> void:
	var geometry := ArenaGeometry.from_layout("corridor", Rect2(0.0, 0.0, 1.0, 1.0), 0.0)
	var snapshot := _snapshot_at(0, Vector2(1.0, 0.5), [_enemy(2, Vector2(11.0, 0.5))], 1.0, geometry)
	var before := snapshot.duplicate(true)
	var build_before: Dictionary = builds.white.duplicate(true)
	var state := Decision.initial_state(builds.white)
	var state_before := state.duplicate(true)
	var result := Decision.decide(snapshot, builds.white, state, 8)
	_expect(result.ok and result.commands == [Protocol.stop_move(0, "ranger-1", 8)] and "movement:no_progress" in result.trace, "no_progress did not stop safely", failures)
	_expect(snapshot == before and builds.white == build_before and state == state_before, "decision mutated an input", failures)
	var expected := result.duplicate(true)
	result.next_state.target_entity_id = 999
	result.commands[0].sequence = 999
	_expect(Decision.decide(snapshot, builds.white, state, 8) == expected, "output mutation polluted a later decision", failures)


func _test_deterministic_continuation(failures: Array[String]) -> void:
	var start := Decision.decide(_snapshot(0, [_enemy(5, Vector2(9, 3)), _enemy(8, Vector2(14, 0))]), builds.white, Decision.initial_state(builds.white), 100)
	var next := _snapshot(1, [_enemy(8, Vector2(2, 0)), _enemy(5, Vector2(8, 3))])
	var a := Decision.decide(next, builds.white, start.next_state.duplicate(true), start.next_sequence)
	var b := Decision.decide(next.duplicate(true), builds.white.duplicate(true), start.next_state.duplicate(true), start.next_sequence)
	_expect(a == b and int(a.next_state.target_entity_id) == 5, "continuation was not deterministic", failures)


func _compile(catalog: Dictionary, perception: String, movement: String, band: String = "") -> Dictionary:
	var raw := {"cores": [perception, movement, "single_key_execution", "short_trace_memory"]}
	if not band.is_empty():
		raw["settings"] = {"distance_keeping_gait": {"distance_band": band}}
	var result := ProxyBuild.compile(raw, catalog)
	if not result.ok:
		printerr("compile fixture failed perception=%s movement=%s band=%s error=%s" % [perception, movement, band, result.error])
	return result.value if result.ok else {}


func _snapshot(tick: int, enemies: Array, tagged: bool = false) -> Dictionary:
	return _snapshot_at(tick, Vector2.ZERO, enemies, 10.0)


func _snapshot_at(tick: int, player_position: Vector2, enemies: Array, targeting_distance: float, geometry: Dictionary = {}) -> Dictionary:
	var resolved_geometry := geometry if not geometry.is_empty() else ArenaGeometry.from_layout("rectangle", TEST_ARENA, 0.0)
	return {"snapshot_version": 3, "tick": tick, "actor_id": "ranger-1", "player_position": player_position, "facing": Vector2.RIGHT, "action_state": "idle", "attack_ready_tick": 0, "targeting_distance": targeting_distance, "visible_enemies": enemies.duplicate(true), "walkable_geometry": resolved_geometry.duplicate(true)}


func _enemy(entity_id: int, position: Vector2, health: float = 10.0, targetable: bool = true, tags: Array = [], include_tags: bool = false) -> Dictionary:
	var enemy := {"entity_id": entity_id, "position": position, "health": health, "targetable": targetable}
	if include_tags:
		enemy.classification_tags = tags.duplicate(true)
	return enemy


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
