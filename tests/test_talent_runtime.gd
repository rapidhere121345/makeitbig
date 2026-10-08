extends SceneTree

const Fixture := preload("res://tests/helpers/talent_runtime_fixture.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	var fixture := Fixture.new()
	_test_capabilities_come_from_locked_build(fixture, failures)
	_test_critical_hunter_once_after_pure_reads(fixture, failures)
	_test_last_generation_pool(fixture, failures)
	_test_wind_walker_interrupt_and_mark(fixture, failures)
	_test_defocused_tracking_candidate(fixture, failures)
	_test_light_step_keen_eye_recovery_pose(fixture, failures)
	_test_three_skill_rhythm(fixture, failures)
	_test_render_rates_and_presentation_switch(fixture, failures)
	if failures.is_empty():
		print("PASS  test_talent_runtime.gd")
		quit(0)
		return
	for failure in failures:
		printerr("- %s" % failure)
	quit(1)


func _test_capabilities_come_from_locked_build(fixture, failures: Array[String]) -> void:
	var session: Dictionary = fixture.start_session(["ranger_critical_hunter"])
	var arena = session.arena
	var expected: Dictionary = session.build.talent_capabilities
	_expect(arena.talent_capabilities == expected, "runtime talents still follow the framework_talent_build bypass", failures)
	_expect(arena.locked_build.talent_capabilities == expected, "locked build lost its compiled talent capabilities", failures)
	fixture.free_session(session)


func _test_critical_hunter_once_after_pure_reads(fixture, failures: Array[String]) -> void:
	var session: Dictionary = fixture.start_session(["ranger_critical_hunter"])
	var arena = session.arena
	var target = fixture.configure_target(arena)
	var base_events: float = float(arena._current_model().total_events_float)
	for _index in 8:
		arena._current_model()
		arena._player_attack_ui_state()
		arena._update_hud()
	_expect(is_equal_approx(float(arena._current_model().total_events_float), base_events), "model/HUD reads consumed the once-per-battle critical bonus", failures)
	_expect(fixture.release_arrow(arena, target), "critical hunter: first arrow did not release", failures)
	var first = arena.projectiles[0]
	var expected_first: float = (base_events + 2.0) * arena.locked_payload
	_expect(is_equal_approx(float(first.ordinary_damage), expected_first), "first critical arrow did not add exactly two generations (got %.3f want %.3f)" % [float(first.ordinary_damage), expected_first], failures)
	var damage_before := _normal_target_damage(arena, target)
	fixture.advance_projectiles(arena)
	_expect(_normal_target_damage(arena, target) - damage_before > expected_first * 0.99, "first critical bonus did not reach actual contact damage", failures)
	arena.attack_cooldown_ticks = 0
	arena.player_action_timeline.reset()
	arena.projectiles.clear()
	target.health = 1000000000.0
	_expect(fixture.release_arrow(arena, target), "critical hunter: second arrow did not release", failures)
	var second = arena.projectiles[0]
	_expect(is_equal_approx(float(second.ordinary_damage), base_events * arena.locked_payload), "critical hunter bonus repeated on the second arrow", failures)
	fixture.free_session(session)


func _test_last_generation_pool(fixture, failures: Array[String]) -> void:
	var session: Dictionary = fixture.start_session(["ranger_last_generation_loading"])
	var arena = session.arena
	var base_damage: float = float(arena.locked_build.total_events_float) * arena.locked_payload
	var target = fixture.configure_target(arena, Vector2(120.0, 0.0))
	_expect(fixture.release_arrow(arena, target), "last generation: expiring arrow did not release", failures)
	target.position = arena.player_position + Vector2(arena.locked_targeting_distance + 80.0, 220.0)
	var expiring = arena.projectiles[0]
	var health_before: float = target.health
	fixture.advance_projectiles(arena)
	_expect(String(arena.last_attack_outcome.get("outcome", "")) == "miss", "last generation: aimed-away arrow did not naturally expire (outcome=%s reason=%s tick=%d)" % [String(arena.last_attack_outcome.get("outcome", "")), String(arena.last_attack_outcome.get("reason", "")), arena.sim_tick], failures)
	_expect(is_equal_approx(target.health, health_before), "last generation: expired arrow directly damaged a target", failures)
	_expect(_boss_damage_float(arena) < 0.001, "last generation: miss directly added boss damage", failures)
	_expect(_near(float(expiring.ordinary_damage), base_damage, 0.001), "unexpected base arrow payload", failures)

	arena.attack_cooldown_ticks = 0
	arena.player_action_timeline.reset()
	target.position = arena.player_position + Vector2(120.0, 0.0)
	target.health = 1000000000.0
	var before_hit: float = target.health
	_expect(fixture.release_arrow(arena, target), "last generation: consuming arrow did not release", failures)
	fixture.advance_projectiles(arena)
	var first_consumption: float = before_hit - target.health
	_expect(_near(first_consumption, base_damage * 1.15, 0.05), "next valid hit did not consume the 15%% pool exactly once (got %.3f want %.3f)" % [first_consumption, base_damage * 1.15], failures)

	arena.attack_cooldown_ticks = 0
	arena.player_action_timeline.reset()
	target.position = arena.player_position + Vector2(120.0, 0.0)
	target.health = 1000000000.0
	before_hit = target.health
	_expect(fixture.release_arrow(arena, target), "last generation: post-consumption arrow did not release", failures)
	fixture.advance_projectiles(arena)
	_expect(_near(before_hit - target.health, base_damage, 0.05), "retained payload was recursively retained after one consumption", failures)

	arena.framework_resolved_build = session.build
	arena._enter_arena()
	var reset_target = fixture.configure_target(arena)
	_expect(fixture.release_arrow(arena, reset_target), "last generation: new-encounter arrow did not release", failures)
	var reset_before: float = reset_target.health
	fixture.advance_projectiles(arena)
	_expect(_near(reset_before - reset_target.health, base_damage, 0.05), "a new encounter inherited the previous retained pool", failures)
	fixture.free_session(session)


func _test_wind_walker_interrupt_and_mark(fixture, failures: Array[String]) -> void:
	var session: Dictionary = fixture.start_session(["ranger_wind_walker"])
	var arena = session.arena
	var target = fixture.configure_target(arena)
	_expect(arena._request_piercing_arrow(target.entity_id).get("accepted", false), "wind walker: arrow request was rejected", failures)
	_expect(arena._start_dodge_from_command(Vector2.UP), "wind walker: dodge was rejected", failures)
	var after_dodge: Dictionary = arena.player_action_timeline.snapshot()
	_expect(not (after_dodge.active.is_empty() and after_dodge.buffered.is_empty()), "wind walker dodge interrupted a live/buffered arrow", failures)
	arena._start_dash_from_command(Vector2.RIGHT)
	var after_dash: Dictionary = arena.player_action_timeline.snapshot()
	_expect(not (after_dash.active.is_empty() and after_dash.buffered.is_empty()), "wind walker dash interrupted a live/buffered arrow", failures)

	arena.player_action_timeline.reset()
	arena.dodge_remaining_ticks = 1
	arena.dash_remaining_ticks = 0
	arena.marked_entity_id = target.entity_id
	arena.hunter_mark_expires_tick = arena.sim_tick
	arena._update_hunter_mark_tick()
	_expect(arena.marked_entity_id == 0, "wind walker postponed mark expiry because a displacement was active", failures)
	fixture.free_session(session)

	var ordinary: Dictionary = fixture.start_session([])
	var plain = ordinary.arena
	var plain_target = fixture.configure_target(plain)
	plain._request_piercing_arrow(plain_target.entity_id)
	plain._start_dodge_from_command(Vector2.UP)
	var interrupted: Dictionary = plain.player_action_timeline.snapshot()
	_expect(interrupted.active.is_empty() and interrupted.buffered.is_empty(), "ordinary dodge no longer interrupts arrow windup/buffer", failures)
	fixture.free_session(ordinary)


func _test_defocused_tracking_candidate(fixture, failures: Array[String]) -> void:
	var session: Dictionary = fixture.start_session([])
	var arena = session.arena
	var marked_target = fixture.configure_target(arena)
	var nearer_target = arena.enemies[1]
	nearer_target.position = arena.player_position + Vector2(80.0, 0.0)
	nearer_target.health = 1000000000.0
	nearer_target.maximum_health = nearer_target.health
	_expect(arena._cast_hunter_mark(marked_target.entity_id), "defocused tracking: initial mark was rejected", failures)
	marked_target.position = arena.player_position + Vector2(arena.locked_targeting_distance * arena.HUNTER_MARK_RANGE_MULTIPLIER + 10.0, 0.0)
	arena._update_hunter_mark_tick()
	_expect(arena.marked_entity_id == 0 and arena.hunter_mark_expires_tick == 0,
		"defocused tracking: lost mark remained active", failures)
	_expect(arena.hunter_mark_candidate_entity_id == marked_target.entity_id
		and arena.hunter_mark_candidate_expires_tick == arena.sim_tick + 15,
		"defocused tracking: lost target did not retain the exact 15-tick candidate window", failures)

	marked_target.position = arena.player_position + Vector2(180.0, 0.0)
	var preferred = arena._preferred_skill_one_target()
	_expect(preferred != null and preferred.entity_id == marked_target.entity_id,
		"defocused tracking: candidate did not outrank the nearer unmarked target", failures)
	_expect(fixture.release_arrow(arena, marked_target), "defocused tracking: candidate arrow did not release", failures)
	var arrow = arena.projectiles[0]
	var base_damage: float = float(arena.locked_build.total_events_float) * arena.locked_payload
	_expect(_near(float(arrow.ordinary_damage), base_damage, 0.001),
		"defocused tracking: candidate restored hunter-mark damage multiplier", failures)

	arena.sim_tick = arena.hunter_mark_candidate_expires_tick + 1
	arena._update_talent_runtime_tick()
	_expect(arena.hunter_mark_candidate_entity_id == 0 and arena.hunter_mark_candidate_expires_tick == 0,
		"defocused tracking: candidate outlived its 15-tick window", failures)
	fixture.free_session(session)


func _test_light_step_keen_eye_recovery_pose(fixture, failures: Array[String]) -> void:
	var session: Dictionary = fixture.start_session([])
	var arena = session.arena
	var target = fixture.configure_target(arena)
	arena._cast_hunter_mark(target.entity_id)
	_expect(arena.hunter_mark_expires_tick == arena.sim_tick + int(round(arena.HUNTER_MARK_DURATION_TICKS * 1.10)), "keen eye did not extend the real mark expiry tick", failures)
	arena.dodge_cooldown_ticks = 0
	arena.dodge_remaining_ticks = 0
	arena.dash_remaining_ticks = 0
	arena._start_dodge_from_command(Vector2.RIGHT)
	_expect(arena.dodge_cooldown_ticks == int(round(arena.DODGE_COOLDOWN_TICKS * 0.92)), "recovery pose did not reduce the real dodge cooldown", failures)

	arena.dodge_remaining_ticks = 0
	arena.dodge_cooldown_ticks = 0
	var start: Vector2 = arena.player_position
	arena._start_dash_from_command(Vector2.RIGHT)
	var duration: int = arena.dash_remaining_ticks
	_expect(duration == int(round(arena.DASH_DURATION_TICKS * 1.10)), "light step did not lengthen the real dash duration", failures)
	for _index in duration:
		arena._advance_player_tick(Vector2.ZERO, 1.0)
		arena._advance_mobility_counters()
	_expect(_near(arena.player_position.distance_to(start), arena.DASH_TOTAL_DISTANCE, 0.10), "light step changed total dash displacement (distance=%.3f)" % arena.player_position.distance_to(start), failures)
	fixture.free_session(session)


func _test_three_skill_rhythm(fixture, failures: Array[String]) -> void:
	var session: Dictionary = fixture.start_session(["ranger_three_skill_rhythm", "ranger_wind_walker"])
	var arena = session.arena
	var target = fixture.configure_target(arena)
	_expect(fixture.release_arrow(arena, target), "three rhythm: opening arrow did not release", failures)
	fixture.advance_projectiles(arena)
	arena.attack_cooldown_ticks = 0
	arena.player_action_timeline.reset()
	arena.hunter_mark_cooldown_ticks = 0
	arena._cast_hunter_mark(target.entity_id)
	arena._start_dash_from_command(Vector2.RIGHT)
	arena._process_player_action_events(arena.player_action_timeline.advance(arena.sim_tick))
	var receipt: Dictionary = arena._request_piercing_arrow(target.entity_id)
	var snapshot: Dictionary = arena.player_action_timeline.snapshot()
	var request: Dictionary = snapshot.active if not snapshot.active.is_empty() else snapshot.buffered
	_expect(bool(receipt.get("accepted", false)) and int(request.get("windup_ticks", 5)) == 4, "three rhythm did not consume one 4-tick windup while wind walker retained it (status=%s windup=%s)" % [String(receipt.get("status", "")), str(request.get("windup_ticks", -1))], failures)
	arena.sim_tick = int(request.get("start_tick", arena.sim_tick)) + int(request.get("windup_ticks", 4))
	arena._process_player_action_events(arena.player_action_timeline.advance(arena.sim_tick))
	_expect(not arena.projectiles.is_empty(), "three rhythm accelerated arrow did not leave the bow", failures)
	fixture.free_session(session)


func _test_render_rates_and_presentation_switch(fixture, failures: Array[String]) -> void:
	var sessions: Array[Dictionary] = []
	for setting in [
		{"name": "off", "presentation": false, "delta": 1.0 / 30.0, "frames": 270},
		{"name": "30", "presentation": true, "delta": 1.0 / 30.0, "frames": 270},
		{"name": "60", "presentation": true, "delta": 1.0 / 60.0, "frames": 540},
		{"name": "144", "presentation": true, "delta": 1.0 / 144.0, "frames": 1296},
	]:
		var session: Dictionary = fixture.start_session(["ranger_critical_hunter"], bool(setting.presentation))
		session["name"] = String(setting.name)
		var arena = session.arena
		for _index in int(setting.frames):
			arena._process(float(setting.delta))
			arena._current_model()
			arena._player_attack_ui_state()
		var guard := 0
		while int(arena.sim_tick) < 270 and guard < 64:
			arena._process(float(setting.delta))
			guard += 1
		sessions.append(session)
	var baseline: Dictionary = _semantic_snapshot(sessions[0].arena)
	for session in sessions.slice(1):
		_expect(_semantic_snapshot(session.arena) == baseline, "render presentation/rate drifted semantic state (%s)" % String(session.name), failures)
		fixture.free_session(session)
	fixture.free_session(sessions[0])


func _normal_target_damage(arena, target) -> float:
	return float(target.maximum_health - target.health)


func _boss_damage_float(arena) -> float:
	var text: String = arena.boss_damage.to_short_string(12)
	return float(text.replace("e", "").to_float()) if text.is_valid_float() else 0.0


func _semantic_snapshot(arena) -> Dictionary:
	var enemy_states: Array[Dictionary] = []
	for enemy in arena.enemies:
		enemy_states.append({
			"id": int(enemy.entity_id),
			"kind": String(enemy.kind_id),
			"x": float(enemy.position.x),
			"y": float(enemy.position.y),
			"health": float(enemy.health),
			"state": String(enemy.action_state),
		})
	return {
		"tick": int(arena.sim_tick),
		"shots": int(arena.shots),
		"defeated": int(arena.defeated),
		"health": float(arena.player_health),
		"x": float(arena.player_position.x),
		"y": float(arena.player_position.y),
		"boss_damage": String(arena.boss_damage.to_short_string(10)),
		"enemies": enemy_states,
	}


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)


func _near(left: Variant, right: Variant, epsilon: float) -> bool:
	return absf(float(left) - float(right)) <= epsilon
