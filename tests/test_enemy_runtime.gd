extends SceneTree

const PlayerFixture := preload("res://tests/helpers/player_domain_fixture.gd")
const Skill := preload("res://src/systems/ranger_skill_rules.gd")
const Timeline := preload("res://src/systems/player_action_timeline.gd")
const ApplicationStateScript := preload("res://src/game/application_state.gd")
const TalentFixture := preload("res://tests/helpers/talent_runtime_fixture.gd")
const ContractPlanScript := preload("res://src/game/contract_plan.gd")
const SnapshotBuilder := preload("res://src/game/combat_state_snapshot_builder.gd")
const StateCodec := preload("res://src/game/combat_state_codec.gd")


var fixture := PlayerFixture.new()
var session: Dictionary = {}


func _place_fixture_actor(arena: Node, actor_id: String, position: Vector2, failures: Array[String]) -> bool:
	var result: Dictionary = arena.teleport_actor(actor_id, position)
	var placed := bool(result.get("ok", false)) and (result.get("position", Vector2.INF) as Vector2).is_equal_approx(position)
	_expect(placed, "enemy fixture: %s placement at %s rejected: %s" % [actor_id, position, result], failures)
	return placed


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	root.size = Vector2i(1280, 720)
	_default_room()
	_test_spawn_roles(session.arena, failures)
	_test_damage_source_tracking(session.arena, failures)
	_test_charger_sequence(session.arena, failures)
	_test_fan_sequence(session.arena, failures)
	_test_fan_attack_radius_runtime(session.arena, failures)
	_test_same_role_action_lane_runtime(session.arena, failures)
	_test_recovery_end_has_same_tick_intent(session.arena, failures)
	_test_boss_runtime(session.arena, failures)
	_test_hash_role_sensitivity(session.arena, failures)
	_test_room_rosters_and_layouts(session.arena, failures)
	_test_public_proxy_geometry_snapshot(session.arena, failures)
	_test_authored_ring_runtime(session.arena, failures)
	_test_ring_charger_path_runtime(session.arena, failures)
	_test_charger_padding_edge_runtime(session.arena, failures)
	_test_invalid_charge_distance_runtime(session.arena, failures)
	_test_rectangle_runtime_does_not_detour(session.arena, failures)
	_test_melee_stuck_escape_intent(session.arena, failures)
	_test_room_completion_and_validation(session.arena, failures)
	_test_embedded_room_rewards(session.arena, failures)
	_test_hazards(session.arena, failures)
	_test_hazard_decision_boundaries(session.arena, failures)
	_test_elite_rules(session.arena, failures)
	_test_room_hash_sensitivity(session.arena, failures)
	_test_early_durability_and_first_hunt(session.arena, failures)

	fixture.free_session(session)
	if failures.is_empty():
		print("PASS  test_enemy_runtime.gd")
		quit(0)
		return
	for failure in failures:
		printerr("- %s" % failure)
	quit(1)


func _test_spawn_roles(arena: Node, failures: Array[String]) -> void:
	var counts := {"melee_pursuer": 0, "charging_raider": 0, "fan_ranged": 0, "threshold_colossus": 0}
	var ids: Array[int] = []
	for enemy in arena.enemies:
		counts[enemy.kind_id] = int(counts.get(enemy.kind_id, 0)) + 1
		ids.append(enemy.entity_id)
	_expect(counts.melee_pursuer == 2 and counts.charging_raider == 2 and counts.fan_ranged == 2, "spawn: normal role distribution is not 2/2/2", failures)
	_expect(counts.threshold_colossus == 1 and arena.boss.kind_id == "threshold_colossus", "spawn: threshold colossus kind is missing", failures)
	_expect(ids == [1, 2, 3, 4, 5, 6, 7], "spawn: entity IDs are not stable and ordered", failures)


func _test_damage_source_tracking(_arena: Node, failures: Array[String]) -> void:
	var fixture := TalentFixture.new()
	var session: Dictionary = fixture.start_session()
	var arena = session.arena
	arena.set_process(false)
	session.runtime.set_process(false)
	var target = fixture.configure_target(arena)
	fixture.advance_to(arena, 17)
	var rules = arena.player_combat_rules
	var applied: Dictionary = rules.apply_damage(17, 11.0, "enemy/charging_raider", target.position)
	var player := fixture.player(arena)
	_expect(applied.get("accepted", false) and player.last_damage_source_id == "enemy/charging_raider" and player.last_damage_tick == 17,
		"damage source: charging raider impact did not record a stable source", failures)
	_expect(arena.request_player_cast("dodge", 0, Vector2.UP).get("accepted", false), "damage source: real dodge setup failed", failures)
	var avoided: Dictionary = rules.apply_damage(17, 9.0, "hazard/moving_fireline", target.position)
	_expect(not avoided.get("accepted", false) and fixture.player(arena).last_damage_source_id == player.last_damage_source_id and fixture.player(arena).last_damage_tick == player.last_damage_tick,
		"damage source: avoided damage updated the last source", failures)
	fixture.advance_to(arena, 17 + int(fixture.player(arena).dodge_remaining_ticks))
	rules.apply_damage(arena.sim_tick, 7.0, "hazard/exposed_ground_zone", target.position)
	rules.apply_damage(arena.sim_tick, 1.2, "boss/slam", target.position)
	_expect(fixture.player(arena).last_damage_source_id == "boss/slam", "damage source: boss action source was not authoritative", failures)
	fixture.step(arena)
	var fatal_tick: int = arena.sim_tick
	rules.apply_damage(fatal_tick, float(fixture.player(arena).player_health) + 1.0, "enemy/melee_pursuer", target.position)
	player = fixture.player(arena)
	_expect(player.player_health == 0.0 and player.last_damage_source_id == "enemy/melee_pursuer" and player.last_damage_tick == fatal_tick,
		"damage source: fatal hit did not replace the prior source", failures)
	arena.start_room()
	player = fixture.player(arena)
	_expect(player.last_damage_source_id.is_empty() and player.last_damage_tick == -1000,
		"damage source: room entry did not reset death diagnostics", failures)
	fixture.free_session(session)


func _test_charger_sequence(arena: Node, failures: Array[String]) -> void:
	arena = _configure_room(arena, "rectangle_arena", "clear", ["charging_raider"])
	var charger = arena.enemies[0]
	fixture.advance_to(arena, 10)
	arena.teleport_actor("ranger", charger.position + Vector2(100.0, 0.0))
	var contact_distance: float = charger.position.distance_to(arena.player_position)
	var accepted: bool = arena._enemy_ai._start_charger_action(charger, charger.position.direction_to(arena.player_position), contact_distance)
	_expect(accepted and charger.action_state == "windup" and charger.impact_tick == 28, "charger: explicit-distance windup was not accepted", failures)
	_expect(is_equal_approx(charger.charge_length, 100.0), "charger: direct sequence did not freeze its explicit distance", failures)
	fixture.drive(arena, {"enemy_step": func() -> void: arena._enemy_ai._update_charger_tick(charger)})
	fixture.advance_to(arena, charger.impact_tick - 1)
	var active_steps := 0
	while charger.action_state != "recovery" and arena.sim_tick <= charger.impact_tick + arena.CHARGE_ACTIVE_TICKS:
		var before: Vector2 = charger.position
		fixture.step(arena)
		if charger.action_state == "active":
			active_steps += 1
			_expect(charger.position.distance_to(before) > 0.01, "charger: direct sequence swallowed an active body step", failures)
	var after_impact: float = arena.player_health
	_expect(active_steps == arena.CHARGE_ACTIVE_TICKS, "charger: direct sequence did not execute all active ticks", failures)
	_expect(charger.action_state == "recovery" and charger.impact_resolved and is_equal_approx(after_impact, 89.0), "charger: moving body did not complete with one contact hit", failures)
	fixture.step(arena)
	_expect(is_equal_approx(arena.player_health, after_impact), "charger: impact dealt damage more than once", failures)


func _test_fan_sequence(arena: Node, failures: Array[String]) -> void:
	arena = _configure_room(arena, "rectangle_arena", "clear", ["fan_ranged"])
	var fan = arena.enemies[0]
	fixture.advance_to(arena, 40)
	arena.teleport_actor("ranger", fan.position + Vector2(140.0, 0.0))
	arena._enemy_ai._start_fan_action(fan)
	_expect(fan.action_state == "windup" and fan.impact_tick == 61, "fan: windup or impact tick is wrong", failures)
	fixture.drive(arena, {"enemy_step": func() -> void: arena._enemy_ai._update_fan_tick(fan)})
	fixture.advance_to(arena, fan.impact_tick)
	var recovery_tick: int = fan.state_ends_tick
	_expect(fan.action_state == "active" and fan.impact_resolved, "fan: did not enter resolved active state", failures)
	# The enemy phase queues a typed player contact.  Damage is committed at the
	# next fixed tick after the kernel has consumed that contact.
	fixture.step(arena)
	var after_impact: float = arena.player_health
	_expect(is_equal_approx(after_impact, 92.0), "fan: authoritative cone did not deal expected impact damage", failures)
	# Repeated resolver submission at the same committed world tick cannot hit twice.
	arena._enemy_ai._update_fan_tick(fan)
	_expect(is_equal_approx(arena.player_health, after_impact), "fan: impact dealt damage more than once", failures)
	fixture.advance_to(arena, recovery_tick)
	_expect(fan.action_state == "recovery", "fan: active did not advance to recovery", failures)


func _test_fan_attack_radius_runtime(arena: Node, failures: Array[String]) -> void:
	arena = _configure_room(arena, "rectangle_arena", "clear", ["fan_ranged"])
	var fan = arena.enemies[0]
	arena.teleport_actor("ranger", arena._arena_rect().get_center())
	arena.teleport_actor("enemy/%d" % fan.entity_id, arena.player_position - Vector2.RIGHT * 200.0)
	var outside_before: Vector2 = fan.position
	fixture.drive(arena, {"enemies": true})
	fixture.step(arena)
	_expect(fan.action_state == "none" and fan.motion_state == "moving" and fan.position != outside_before and String(fan.tactic_reason) == "fan_strafe_hold", "fan radius: target at 200 started an empty attack instead of moving", failures)
	fixture.drive(arena)
	fixture.advance_to(arena, 39)
	arena.teleport_actor("enemy/%d" % fan.entity_id, arena.player_position - Vector2.RIGHT * arena.EnemyTacticsScript.FAN_ATTACK_RADIUS)
	fixture.drive(arena, {"enemies": true})
	fixture.step(arena)
	_expect(fan.action_state == "windup" and is_equal_approx(float(fan.target_shape.get("radius", 0.0)), arena.EnemyTacticsScript.FAN_ATTACK_RADIUS), "fan radius: legal start did not freeze the shared target shape", failures)
	fixture.advance_to(arena, fan.impact_tick)
	fixture.step(arena)
	_expect(is_equal_approx(arena.player_health, 92.0), "fan radius: stationary target at the legal boundary was not hit", failures)
	_default_room()


func _test_same_role_action_lane_runtime(arena: Node, failures: Array[String]) -> void:
	arena = _configure_room(arena, "rectangle_arena", "clear", ["fan_ranged", "fan_ranged"])
	arena.combat_event_stream.reset()
	## Use the open eastern floor so whole-object blockers cannot redirect
	## the waiting fan; retain exact 150-unit distances and lane timing.
	if not _place_fixture_actor(arena, "ranger", Vector2(1100.0, 434.0), failures):
		return
	var first = arena.enemies[0]
	var waiting = arena.enemies[1]
	if not _place_fixture_actor(arena, "enemy/%d" % first.entity_id, arena.player_position + Vector2(0.0, -150.0), failures):
		return
	if not _place_fixture_actor(arena, "enemy/%d" % waiting.entity_id, arena.player_position + Vector2(0.0, 150.0), failures):
		return

	fixture.drive(arena, {"enemies": true})
	fixture.step(arena)
	_expect(first.action_state == "windup" and first.impact_tick == 22, "action lane: lowest stable fan did not own the first windup", failures)
	_expect(waiting.action_state == "none" and waiting.motion_state == "moving" and String(waiting.tactic_reason).contains("action_lane_occupied"), "action lane: waiting fan neither yielded nor kept strafing", failures)

	for tick in range(2, 23):

		fixture.step(arena)
	# Tick 22 queues the contact; tick 23 commits it through RoomCombatPort.
	fixture.step(arena)
	var damage_events_at_first_impact := 0
	for event: Dictionary in arena.combat_event_stream.snapshot().events:
		if String(event.get("type", "")) == "attack_resolved" and String(event.get("outcome", "")) == "damage" and int(event.get("tick", -1)) == 23:
			damage_events_at_first_impact += 1
	_expect(is_equal_approx(arena.player_health, 92.0) and damage_events_at_first_impact == 1, "action lane: one telegraph still produced stacked same-tick fan damage", failures)
	_expect(waiting.action_state == "none", "action lane: waiting fan entered windup before the active lane released", failures)

	## Planning observes the first attacker as active at tick 23, then sees recovery
	## at tick 24 and must immediately hand the role lane to the waiting fan.

	fixture.step(arena)

	fixture.step(arena)
	_expect(first.action_state == "recovery" and waiting.action_state == "windup" and waiting.impact_tick == 45, "action lane: recovery did not release the role lane to its waiter", failures)
	arena = _default_room()


func _test_recovery_end_has_same_tick_intent(arena: Node, failures: Array[String]) -> void:
	arena = _configure_room(arena, "rectangle_arena", "clear", ["melee_pursuer"])
	arena.teleport_actor("ranger", arena._arena_rect().get_center())
	var enemy = arena.enemies[0]
	arena.teleport_actor("enemy/%d" % enemy.entity_id, arena.player_position + Vector2(100.0, 0.0))
	enemy.action_state = "recovery"
	enemy.action_id = "contact"
	enemy.action_instance_id = 77
	enemy.state_ends_tick = 40
	enemy.motion_state = "idle"
	fixture.advance_to(arena, 39)
	var before: Vector2 = enemy.position
	fixture.drive(arena, {"enemies": true})
	fixture.step(arena)
	_expect(enemy.action_state == "none" and enemy.motion_state == "moving" and enemy.position != before and String(enemy.tactic_reason) != "action_locked", "recovery boundary: ending tick discarded the newly available movement intent", failures)
	arena = _default_room()
	var boss = arena.boss
	boss.action_state = "recovery"
	boss.action_id = "slam"
	boss.action_instance_id = 78
	boss.state_ends_tick = 50
	fixture.advance_to(arena, 49)
	fixture.drive(arena, {"enemies": true})
	fixture.step(arena)
	_expect(boss.action_state == "windup" and boss.state_started_tick == 50, "recovery boundary: boss ending tick discarded the next authoritative action", failures)
	_default_room()


func _test_boss_runtime(arena: Node, failures: Array[String]) -> void:
	arena = _configure_room(arena, "rectangle_arena", "hunt_elite", [], "threshold_colossus")
	# A real frozen build/contact supplies the exact 50% threshold. No totals writes.
	fixture.reset(arena, {}, fixture.build({"p": 0.0, "damage": 5.0e11, "d": 225.0}))
	fixture.drive(arena)
	var boss = arena.boss
	arena.teleport_actor("ranger", boss.position + Vector2(-140.0, 0.0))
	arena.player_combat_rules.apply_damage(arena.sim_tick, 23.0, "fixture/setup", boss.position)
	_expect(_cast_and_resolve_arrow(arena), "boss: real threshold arrow setup failed", failures)
	_expect(arena.boss_damage.compare(arena.boss_maximum.multiply(BigValue.from_float(0.5))) == 0 and arena.arrow_hits == 1, "boss: real contact did not establish exactly 50% damage", failures)
	fixture.advance_to(arena, 99)
	fixture.drive(arena, {"enemy_step": func() -> void: arena._enemy_ai._update_boss_tick(boss)})
	fixture.step(arena)
	_expect(boss.phase_id == "sealed" and boss.phase_state == "transition", "boss: 50% threshold did not start sealed transition", failures)
	_expect(is_equal_approx(arena.player_health, 77.0), "boss: phase transition dealt damage", failures)
	var transition_end: int = boss.state_ends_tick
	fixture.advance_to(arena, transition_end)
	_expect(boss.phase_id == "awakened" and boss.phase_state == "stable", "boss: transition did not finish awakened", failures)
	_expect(boss.core_open and boss.core_vulnerable, "boss: awakened core state is not exposed", failures)
	_expect(boss.left_hand_position - boss.position != -(boss.right_hand_position - boss.position), "boss: phase 2 hands are still symmetric", failures)
	_expect(is_equal_approx(arena.player_health, 77.0), "boss: transition completion dealt damage", failures)
	var actions: Array[String] = []
	for _index in 3:
		fixture.step(arena)
		actions.append(boss.action_id)
		fixture.advance_to(arena, boss.impact_tick)
		fixture.advance_to(arena, boss.state_ends_tick)
		fixture.advance_to(arena, boss.state_ends_tick)
	_expect(actions == ["slam", "sweep", "lane"], "boss: phase 2 move cycle is not slam/sweep/lane", failures)
	_default_room()


func _test_hash_role_sensitivity(arena: Node, failures: Array[String]) -> void:
	var charger = _enemy_of_kind(arena, "charging_raider")
	var original_kind: String = charger.kind_id
	var first_hash: String = arena._semantic_state_hash("test")
	charger.kind_id = "fan_ranged"
	var second_hash: String = arena._semantic_state_hash("test")
	charger.kind_id = original_kind
	_expect(not first_hash.is_empty() and first_hash != second_hash, "hash: enemy role difference is not semantic", failures)


func _test_room_rosters_and_layouts(arena: Node, failures: Array[String]) -> void:
	var positions := {}
	for layout in ["rectangle_arena", "corridor", "ring"]:
		arena = _configure_room(arena, layout, "clear", ["melee_pursuer", "charging_raider", "fan_ranged"])
		var kinds: Array[String] = []
		var ids: Array[int] = []
		for enemy in arena.enemies:
			kinds.append(enemy.kind_id)
			ids.append(enemy.entity_id)
		_expect(kinds == ["melee_pursuer", "charging_raider", "fan_ranged"] and ids == [1, 2, 3], "room roster/order/entity IDs changed for %s" % layout, failures)
		_expect(arena.boss == null, "normal room unexpectedly spawned a Boss", failures)
		positions[layout] = arena.enemies[0].position
	_expect(positions.rectangle_arena != positions.corridor and positions.corridor != positions.ring and positions.rectangle_arena != positions.ring, "layouts do not produce distinct deterministic spawn geometry", failures)
	var center: Vector2 = arena._arena_rect().get_center()
	var ring_clamp: Vector2 = arena._clamp_to_arena(center, 14.0)
	var ring_geometry: Dictionary = arena._walkable_geometry(14.0)
	_expect(not Vector2(ring_clamp).is_equal_approx(center)
		and is_equal_approx(ring_clamp.distance_to(center), float(ring_geometry.get("inner_radius", 0.0))),
		"ring layout did not project its center onto the authored inner boundary", failures)


func _test_public_proxy_geometry_snapshot(arena: Node, failures: Array[String]) -> void:
	arena = _configure_room(arena, "ring", "clear", ["melee_pursuer", "charging_raider", "fan_ranged"])
	var snapshot: Dictionary = arena._player_commands._public_proxy_snapshot()
	var geometry: Dictionary = snapshot.get("walkable_geometry", {})
	_expect(int(snapshot.get("snapshot_version", -1)) == arena.ProxyDecisionScript.SNAPSHOT_VERSION, "public proxy snapshot did not use ProxyDecision's version constant", failures)
	_expect(not geometry.is_empty() and String(geometry.get("kind", "")) == "ring"
		and float(geometry.get("inner_radius", 0.0)) > 0.0 and not geometry.has("layout_id"), "public proxy snapshot did not expose the sanitized ring geometry", failures)
	_expect(not snapshot.has("layout_id") and not snapshot.has("room_id") and not snapshot.has("hazards") and not snapshot.has("telegraphs"), "public proxy snapshot exposed route, room, or future state", failures)
	for enemy: Dictionary in snapshot.get("visible_enemies", []):
		_expect(enemy.has("targetable")
			and not enemy.has("classification_tags")
			and not enemy.has("kind_id")
			and not enemy.has("action_id")
			and not enemy.has("action_state"),
			"public white proxy snapshot exposed classification or enemy kind/action state", failures)
	var normalized: Dictionary = arena.ProxyDecisionScript._normalize_snapshot(snapshot, [])
	_expect(bool(normalized.get("ok", false)), "ProxyDecision rejected Main's public walkable-geometry snapshot", failures)


func _test_authored_ring_runtime(arena: Node, failures: Array[String]) -> void:
	# Preserve the authored six-entity crowd-control fixture. The player starts
	# on the legal ring band; charger launch authority is covered by the chord
	# test below. Use the inner north/south axis, clear of the moved southern
	# pier. The pair remains exactly antipodal and starts 200 units from the
	# west-side player, outside both attack bands, with a walkable approach.
	arena = _configure_room(arena, "ring", "clear", ["charging_raider", "melee_pursuer", "melee_pursuer", "fan_ranged", "fan_ranged", "melee_pursuer"])
	var center: Vector2 = arena._arena_rect().get_center()
	if not _place_fixture_actor(arena, "ranger", center + Vector2.LEFT * 160.0, failures):
		return
	var charger = arena.enemies[0]
	var fan = arena.enemies[3]
	var melee = arena.enemies[5]
	if not _place_fixture_actor(arena, "enemy/%d" % charger.entity_id, center + Vector2.DOWN * 120.0, failures):
		return
	if not _place_fixture_actor(arena, "enemy/%d" % fan.entity_id, center + Vector2.UP * 120.0, failures):
		return
	_expect((charger.position - center).normalized().dot((fan.position - center).normalized()) < -0.999, "authored ring: charger/fan fixture is not antipodal", failures)

	var fan_entered_band := false
	var fan_started := false
	var fan_band_tick := -1
	var fan_start_tick := -1
	var melee_tangent_displacement := 0.0
	var stalled_runs := {}
	var maximum_stalled_run := 0
	fixture.drive(arena, {"enemies": true})
	for tick in range(1, 241):

		var planned: Dictionary = arena.enemy_tactics.plan(arena._enemy_ai._enemy_tactics_snapshot())
		var intents_by_id := {}
		for intent: Dictionary in planned.get("intents", []):
			intents_by_id[int(intent.get("entity_id", 0))] = intent
		var before := {}
		for enemy in arena.enemies:
			before[enemy.entity_id] = enemy.position
		fixture.step(arena)

		var fan_distance: float = fan.position.distance_to(arena.player_position)
		var fan_in_band: bool = fan_distance >= arena.EnemyTacticsScript.FAN_ATTACK_MIN_RANGE and fan_distance <= arena.EnemyTacticsScript.FAN_ATTACK_RADIUS
		if fan_in_band and not fan_entered_band:
			fan_band_tick = tick
		fan_entered_band = fan_entered_band or fan_in_band
		if fan.action_instance_id > 0 and not fan_started:
			fan_start_tick = tick
		fan_started = fan_started or fan.action_instance_id > 0
		if tick <= 60:
			var melee_before: Vector2 = before[melee.entity_id]
			var melee_step: Vector2 = melee.position - melee_before
			var radial: Vector2 = melee_before - center
			if not radial.is_zero_approx():
				melee_tangent_displacement += absf(melee_step.dot(radial.normalized().rotated(PI * 0.5)))

		for enemy in arena.enemies:
			var intent: Dictionary = intents_by_id.get(enemy.entity_id, {})
			var requested_move := (intent.get("move_direction", Vector2.ZERO) as Vector2).length_squared() > 0.000001 and float(intent.get("speed_scale", 0.0)) > 0.0
			var actual_distance: float = enemy.position.distance_to(before[enemy.entity_id])
			var run := int(stalled_runs.get(enemy.entity_id, 0))
			run = run + 1 if requested_move and actual_distance <= 0.01 else 0
			stalled_runs[enemy.entity_id] = run
			maximum_stalled_run = maxi(maximum_stalled_run, run)

	_expect(fan_entered_band and fan_started, "authored ring: fan did not enter its legal attack band and start by tick 240", failures)
	_expect(melee_tangent_displacement > 0.01, "authored ring: melee entity 6 had no tangential displacement in its first 60 ticks", failures)
	_expect(maximum_stalled_run <= 4, "authored ring: requested movement stalled for %d consecutive ticks" % maximum_stalled_run, failures)
	print("ENEMY_RUNTIME_AUTHORED_RING_METRICS fan_band_tick=%d fan_start_tick=%d melee6_tangent_60=%.3f max_stalled_run=%d" % [fan_band_tick, fan_start_tick, melee_tangent_displacement, maximum_stalled_run])


func _test_ring_charger_path_runtime(arena: Node, failures: Array[String]) -> void:
	arena = _configure_room(arena, "ring", "clear", ["charging_raider"])
	var player_geometry: Dictionary = arena._walkable_geometry(14.0)
	var enemy_geometry: Dictionary = arena._walkable_geometry(16.0)
	_expect(String(player_geometry.get("kind", "")) == "ring" and String(enemy_geometry.get("kind", "")) == "ring",
		"ring runtime: ring rooms did not expose the authored annulus", failures)
	_expect(float(player_geometry.get("inner_radius", 0.0)) > 0.0 and float(enemy_geometry.get("outer_radius", 0.0)) > float(enemy_geometry.get("inner_radius", 0.0)),
		"ring runtime: authored annulus radii are invalid", failures)
	var center: Vector2 = enemy_geometry["center"]
	var fixture_standoff: float = clampf(120.0, arena.EnemyTacticsScript.CHARGER_LAUNCH_MIN_RANGE, arena.EnemyTacticsScript.CHARGER_LAUNCH_MAX_RANGE)

	var charger = arena.enemies[0]
	var arc_half_angle := asin(fixture_standoff / 320.0)
	## The east band hosts an authored low-pier blocker; the antipodal west
	## chord keeps the fixture geometry clear of every authored structure.
	arena.teleport_actor("enemy/%d" % charger.entity_id, center + Vector2.from_angle(PI - arc_half_angle) * 160.0)
	arena.teleport_actor("ranger", center + Vector2.from_angle(PI + arc_half_angle) * 160.0)
	var player_projection: Dictionary = arena.ArenaGeometryScript.project(arena.player_position, player_geometry)
	var charger_projection: Dictionary = arena.ArenaGeometryScript.project(charger.position, enemy_geometry)
	_expect(bool(player_projection.ok) and Vector2(player_projection.position).is_equal_approx(arena.player_position), "ring runtime: in-band player start is illegal under padding 14", failures)
	_expect(bool(charger_projection.ok) and Vector2(charger_projection.position).is_equal_approx(charger.position), "ring runtime: in-band charger start is illegal under padding 16", failures)
	var initial_distance: float = charger.position.distance_to(arena.player_position)
	_expect(initial_distance >= arena.EnemyTacticsScript.CHARGER_LAUNCH_MIN_RANGE and initial_distance <= arena.EnemyTacticsScript.CHARGER_LAUNCH_MAX_RANGE, "ring runtime: launch fixture is outside the charge band", failures)
	var direct_chord: Dictionary = arena.ArenaGeometryScript.line_segment_walkable(charger.position, arena.player_position, enemy_geometry)
	_expect(bool(direct_chord.ok) and bool(direct_chord.walkable), "ring runtime: the chord within the authored band is not walkable", failures)
	var initial_plan: Dictionary = arena.enemy_tactics.plan(arena._enemy_ai._enemy_tactics_snapshot())
	var initial_intent: Dictionary = initial_plan.intents[0]
	_expect(String(initial_intent.request_action) == "charge" and String(initial_intent.reason) == "charger_launch_band", "ring runtime: a legal in-band chord did not launch immediately", failures)

	var setup_displacement := 0.0
	var launch_tick := -1
	var launch_distance := 0.0
	var active_steps := 0
	var active_nonzero_steps := 0
	var active_swallowed_steps := 0
	var active_displacement := 0.0
	var hit := false
	var launch_count := 0
	var completed_cycles := 0
	var maximum_setup_stalled_run := 0
	var setup_stalled_run := 0
	var player_after_init_direct_moves := 0
	var initial_player_position: Vector2 = arena.player_position
	var charge_action_instance_ids: Array[int] = []
	var frozen_distance_sum := 0.0
	var health_before_first_action := -1.0
	fixture.drive(arena, {"enemies": true})
	for tick in range(1, 1201):

		var planned: Dictionary = arena.enemy_tactics.plan(arena._enemy_ai._enemy_tactics_snapshot())
		var intent: Dictionary = planned.intents[0]
		var before: Vector2 = charger.position
		var state_before: String = charger.action_state
		var requested_charge := String(intent.request_action) == "charge"
		if requested_charge:
			var execution_endpoint: Vector2 = charger.position + Vector2(intent.action_direction).normalized() * float(intent.action_distance)
			var launch_path: Dictionary = arena.ArenaGeometryScript.line_segment_walkable(charger.position, execution_endpoint, enemy_geometry)
			_expect(bool(launch_path.ok) and bool(launch_path.walkable), "ring runtime: Main accepted charge before the frozen line became walkable", failures)
			launch_count += 1
			if launch_count == 1:
				health_before_first_action = arena.player_health
			if launch_tick < 0:
				launch_tick = tick
				launch_distance = charger.position.distance_to(arena.player_position)
		fixture.step(arena)
		if requested_charge:
			charge_action_instance_ids.append(charger.action_instance_id)
			frozen_distance_sum += charger.charge_length
			_expect(is_equal_approx(charger.charge_length, float(intent.action_distance)), "ring runtime: Main charge_length drifted from action_distance", failures)
		if not arena.player_position.is_equal_approx(initial_player_position):
			player_after_init_direct_moves += 1
		var actual_step: float = charger.position.distance_to(before)
		if launch_tick < 0:
			setup_displacement += actual_step
		var requested_setup_move := String(intent.request_action).is_empty() and Vector2(intent.move_direction).length_squared() > 0.000001 and float(intent.speed_scale) > 0.0
		setup_stalled_run = setup_stalled_run + 1 if requested_setup_move and actual_step <= 0.01 else 0
		maximum_setup_stalled_run = maxi(maximum_setup_stalled_run, setup_stalled_run)
		if charger.action_state == "active":
			active_steps += 1
			active_displacement += actual_step
			if actual_step > 0.01:
				active_nonzero_steps += 1
			else:
				active_swallowed_steps += 1
		if arena.player_health < 100.0:
			hit = true
		if state_before == "active" and charger.action_state == "recovery":
			completed_cycles += 1
		if completed_cycles >= 1:
			break
	# The impact tick queues the hostile contact; allow the following kernel
	# tick to commit it before inspecting the authoritative receipt.
	if launch_count >= 1:
		fixture.step(arena)

	var first_resolution: Dictionary = {}
	if charge_action_instance_ids.size() >= 1:
		var first_action_instance_id := charge_action_instance_ids[0]
		for event: Dictionary in arena.combat_event_stream.snapshot().events:
			if String(event.get("type", "")) == "attack_resolved" and int(event.get("action_instance_id", -1)) == first_action_instance_id and String(event.get("outcome", "")) == "damage":
				first_resolution = event
				break
	_expect(is_zero_approx(setup_displacement), "ring runtime: an in-band launch produced unexpected setup movement", failures)
	_expect(launch_tick >= 1 and launch_tick <= 600, "ring runtime: charger did not launch within 600 ticks", failures)
	_expect(player_after_init_direct_moves == 0, "ring runtime: test moved the player after fixture initialization", failures)
	_expect(launch_count == 1 and completed_cycles == 1 and charge_action_instance_ids.size() == 1, "ring runtime: first legal charge did not complete exactly one action cycle", failures)
	_expect(active_steps == arena.CHARGE_ACTIVE_TICKS and active_nonzero_steps == active_steps, "ring runtime: first legal charge did not move on every active tick", failures)
	_expect(active_swallowed_steps == 0, "ring runtime: charge active lost %d body steps to ring projection" % active_swallowed_steps, failures)
	_expect(absf(active_displacement - frozen_distance_sum) <= 0.05, "ring runtime: body displacement did not equal frozen action distances", failures)
	_expect(maximum_setup_stalled_run <= 4, "ring runtime: setup stalled for %d consecutive ticks" % maximum_setup_stalled_run, failures)
	_expect(not first_resolution.is_empty() and String(first_resolution.get("source_id", "")) == "enemy/%d/charging_raider" % charger.entity_id and String(first_resolution.get("target_id", "")) == "ranger" and String(first_resolution.get("outcome", "")) == "damage", "ring runtime: first legal charger action lacked authoritative damage resolution", failures)
	_expect(is_equal_approx(health_before_first_action - arena.player_health, 11.0), "ring runtime: first legal charger action did not apply exactly 11 HP damage", failures)
	print("ENEMY_RUNTIME_RING_CHARGE_METRICS standoff=%.3f initial_distance=%.3f launch_tick=%d launch_distance=%.3f launches=%d completed_cycles=%d first_action_instance=%d first_hp_delta=%.1f setup_displacement=%.3f max_setup_stalled=%d active_steps=%d active_nonzero=%d active_swallowed=%d frozen_distance_sum=%.3f active_displacement=%.3f hit=%s player_after_init_direct_moves=%d" % [fixture_standoff, initial_distance, launch_tick, launch_distance, launch_count, completed_cycles, charge_action_instance_ids[0] if charge_action_instance_ids.size() >= 1 else -1, health_before_first_action - arena.player_health, setup_displacement, maximum_setup_stalled_run, active_steps, active_nonzero_steps, active_swallowed_steps, frozen_distance_sum, active_displacement, str(hit), player_after_init_direct_moves])


func _test_charger_padding_edge_runtime(arena: Node, failures: Array[String]) -> void:
	arena = _configure_room(arena, "rectangle_arena", "clear", ["charging_raider"])
	var player_geometry: Dictionary = arena._walkable_geometry(14.0)
	var enemy_geometry: Dictionary = arena._walkable_geometry(16.0)
	## The authored tower blocker sits near the vertical centre of the west
	## edge; slide the edge fixture south so the projected charge lane stays
	## clear of it.
	var player_start := Vector2(float(player_geometry.bounds.position.x), 460.0)
	var charger = arena.enemies[0]
	_expect(bool(arena.teleport_actor("ranger", player_start).get("ok", false)), "padding runtime: ranger fixture placement failed", failures)
	_expect(bool(arena.teleport_actor("enemy/%d" % charger.entity_id, player_start + Vector2.RIGHT * 100.0).get("ok", false)), "padding runtime: charger fixture placement failed", failures)
	var player_check: Dictionary = arena.ArenaGeometryScript.project(player_start, player_geometry)
	var contact: Dictionary = arena.ArenaGeometryScript.project(player_start, enemy_geometry)
	_expect(bool(player_check.ok) and Vector2(player_check.position).is_equal_approx(player_start), "padding runtime: player edge is illegal under padding 14", failures)
	_expect(bool(contact.ok) and is_equal_approx(player_start.distance_to(Vector2(contact.position)), 2.0), "padding runtime: enemy contact projection is not the expected 2px inset", failures)

	var start_tick := -1
	var frozen_charge_length := 0.0
	var active_steps := 0
	var active_nonzero_steps := 0
	var active_swallowed_steps := 0
	var active_displacement := 0.0
	var recovery_tick := -1
	var charge_action_instance_id := -1
	fixture.drive(arena, {"enemies": true})
	for tick in range(1, 81):

		var before: Vector2 = charger.position
		fixture.step(arena)
		if start_tick < 0 and charger.action_state == "windup":
			start_tick = tick
			frozen_charge_length = charger.charge_length
			charge_action_instance_id = charger.action_instance_id
			_expect(charger.charge_direction.is_equal_approx(charger.charge_origin.direction_to(Vector2(contact.position))), "padding runtime: Main did not freeze direction toward projected contact", failures)
		if charger.action_state == "active":
			var actual_step: float = charger.position.distance_to(before)
			active_steps += 1
			active_displacement += actual_step
			if actual_step > 0.01:
				active_nonzero_steps += 1
			else:
				active_swallowed_steps += 1
		if charger.action_state == "recovery":
			recovery_tick = tick
			break

	var authoritative_resolution := false
	for event: Dictionary in arena.combat_event_stream.snapshot().events:
		if String(event.get("type", "")) == "attack_resolved" and int(event.get("action_instance_id", -1)) == charge_action_instance_id and String(event.get("source_id", "")) == "enemy/%d/charging_raider" % charger.entity_id and String(event.get("target_id", "")) == "ranger":
			authoritative_resolution = String(event.get("outcome", "")) == "damage"
	_expect(start_tick > 0 and start_tick < 600, "padding runtime: legal edge target did not start charge", failures)
	_expect(is_equal_approx(frozen_charge_length, 98.0), "padding runtime: Main did not freeze the projected 98px distance", failures)
	_expect(active_steps == arena.CHARGE_ACTIVE_TICKS and active_nonzero_steps == arena.CHARGE_ACTIVE_TICKS and active_swallowed_steps == 0 and recovery_tick > start_tick, "padding runtime: charge did not move on all 10 active ticks", failures)
	## The frozen length still targets the 2px-inset contact, but the motor can
	## only travel to the padded boundary for the charger's registered
	## footprint, so the expected body displacement is the reachable portion of
	## the frozen lane. Drift beyond that clip stays a failure.
	var charger_state = arena.actor_registry.actor("enemy/%d" % charger.entity_id)
	var charger_footprint: float = float(charger_state.footprint_radius) if charger_state != null else 18.0
	var motor_reach: float = (player_start.x + 100.0) - float(arena._walkable_geometry(charger_footprint).bounds.position.x)
	_expect(absf(active_displacement - minf(frozen_charge_length, motor_reach)) <= 0.02, "padding runtime: body displacement did not equal the reachable frozen charge_length", failures)
	_expect(charger.impact_resolved and authoritative_resolution, "padding runtime: charge produced no authoritative hit/miss resolution", failures)
	_expect(is_equal_approx(arena.player_health, 89.0), "padding runtime: projected contact charge did not hit the static edge player", failures)
	_expect(arena.player_position.is_equal_approx(player_start), "padding runtime: player moved after fixture initialization", failures)
	print("ENEMY_RUNTIME_PADDING_EDGE_METRICS start_tick=%d recovery_tick=%d charge_length=%.3f active_steps=%d active_nonzero=%d active_swallowed=%d active_displacement=%.3f contact_offset=%.3f outcome_health=%.1f player_after_init_direct_moves=0" % [start_tick, recovery_tick, frozen_charge_length, active_steps, active_nonzero_steps, active_swallowed_steps, active_displacement, player_start.distance_to(Vector2(contact.position)), arena.player_health])


func _test_invalid_charge_distance_runtime(arena: Node, failures: Array[String]) -> void:
	var cases: Array = [null, 0.0, -1.0, INF]
	for index in cases.size():
		arena = _configure_room(arena, "rectangle_arena", "clear", ["charging_raider"])
		var charger = arena.enemies[0]
		var intent := {
			"entity_id": charger.entity_id,
			"move_direction": Vector2.ZERO,
			"speed_scale": 0.0,
			"request_action": "charge",
			"action_direction": Vector2.LEFT,
			"action_distance": cases[index],
			"reason": "invalid_distance_probe",
		}
		arena._enemy_ai._commit_normal_enemy_intent(charger, intent)
		_expect(charger.action_state == "none" and charger.action_instance_id == 0 and String(charger.tactic_reason) == "invalid_charge_execution", "invalid charge distance: case %d was not rejected" % index, failures)

	arena = _configure_room(arena, "rectangle_arena", "clear", ["charging_raider"])
	var charger = arena.enemies[0]
	arena._enemy_ai._commit_normal_enemy_intent(charger, {
		"entity_id": charger.entity_id,
		"move_direction": Vector2.ZERO,
		"speed_scale": 0.0,
		"request_action": "charge",
		"action_direction": Vector2.ZERO,
		"action_distance": 100.0,
		"reason": "invalid_direction_probe",
	})
	_expect(charger.action_state == "none" and charger.action_instance_id == 0 and String(charger.tactic_reason) == "invalid_charge_execution", "invalid charge direction: zero vector was not rejected", failures)


func _test_rectangle_runtime_does_not_detour(arena: Node, failures: Array[String]) -> void:
	arena = _configure_room(arena, "rectangle_arena", "clear", ["charging_raider"])
	var center := Vector2(450.0, 630.0)
	_expect(bool(arena.teleport_actor("ranger", center).get("ok", false)), "rectangle runtime: ranger fixture placement failed", failures)
	var charger = arena.enemies[0]
	_expect(bool(arena.teleport_actor("enemy/%d" % charger.entity_id, center + Vector2(250.0, 0.0)).get("ok", false)), "rectangle runtime: charger fixture placement failed", failures)
	var before: Vector2 = charger.position

	fixture.drive(arena, {"enemies": true})
	fixture.step(arena)
	var displacement: Vector2 = charger.position - before
	_expect(displacement.x < -0.01 and absf(displacement.y) <= 0.01, "rectangle runtime: direct approach triggered a walkable-geometry detour", failures)
	print("ENEMY_RUNTIME_RECT_METRICS dx=%.3f dy=%.3f" % [displacement.x, displacement.y])


func _test_room_completion_and_validation(arena: Node, failures: Array[String]) -> void:
	arena = _configure_room(arena, "rectangle_arena", "clear", ["melee_pursuer"])
	_defeat_target(arena, arena.enemies[0], failures)
	arena._check_battle_end()
	_expect(arena.battle_over and arena.battle_victory, "normal clear room did not win with no living targets", failures)
	arena = _configure_room(arena, "rectangle_arena", "timed_break", ["melee_pursuer"])
	fixture.advance_to(arena, 901)
	arena._update_room_rules_tick()
	_expect(not arena.timed_bonus_available and not arena.battle_over, "timed_break timeout incorrectly failed the room", failures)
	arena = _configure_room(arena, "rectangle_arena", "hunt_elite", ["melee_pursuer", "fan_ranged"])
	var elite = arena.enemies[0]
	_defeat_target(arena, elite, failures)
	arena._check_battle_end()
	_expect(arena.battle_over and arena.battle_victory and arena.enemies.size() == 1, "hunt_elite did not use the first enemy as authoritative objective", failures)
	arena = _configure_room(arena, "rectangle_arena", "hunt_elite", [], "threshold_colossus")
	_expect(arena.boss != null and arena.enemies.size() == 1 and arena.boss.entity_id == 1, "Boss room did not spawn authoritative threshold colossus", failures)
	arena.framework_room.enemy_ids = ["unknown_enemy"]
	_expect(arena._framework_room_error() == "unknown_enemy_id", "unknown enemy did not fail closed", failures)
	arena.framework_room.enemy_ids = []
	arena.framework_room.boss_id = "unknown_boss"
	_expect(arena._framework_room_error() == "unknown_boss_id", "unknown Boss did not fail closed", failures)


func _test_embedded_room_rewards(arena: Node, failures: Array[String]) -> void:
	arena = _configure_room(arena, "rectangle_arena", "clear", ["melee_pursuer"], "", [], [], ["equipment_general", "damage", "add_dice", "rewrite_dice", "refine_dice"])
	_defeat_target(arena, arena.enemies[0], failures)
	arena._check_battle_end()
	_expect(arena.battle_victory, "embedded rewards: clear room did not remain a victory", failures)
	_expect(arena.room_reward_snapshot == {
		"add_dice_delta": 1,
		"rewrite_dice_delta": 1,
		"refine_dice_delta": 1,
		"bonus_earned": false,
		"bonus_lost": false,
	}, "embedded rewards: room_drop_tags were not mapped exactly to three tracks", failures)

	arena = _configure_room(arena, "rectangle_arena", "timed_break", ["melee_pursuer"], "", [], [], ["equipment_general"])
	fixture.advance_to(arena, 901)
	arena._update_room_rules_tick()
	_defeat_target(arena, arena.enemies[0], failures)
	arena._check_battle_end()
	_expect(arena.battle_victory and arena.room_reward_snapshot == {
		"add_dice_delta": 0,
		"rewrite_dice_delta": 0,
		"refine_dice_delta": 0,
		"bonus_earned": false,
		"bonus_lost": true,
	}, "embedded rewards: timed timeout was not bonus-only", failures)


func _test_hazards(arena: Node, failures: Array[String]) -> void:
	for hazard_id in ["exposed_ground_zone", "moving_fireline"]:
		arena = _configure_room(arena, "rectangle_arena", "clear", ["melee_pursuer"], "", [hazard_id])
		var center: Vector2 = arena._arena_rect().get_center()
		# Both the waiting position and the hit position are legal registry feet.
		arena.teleport_actor("ranger", center + Vector2(350.0, 170.0))
		fixture.advance_to(arena, 30)
		var state: Dictionary = arena.hazard_states[0]
		var hit_position: Vector2 = state.origin + Vector2(0.0, state.length * 0.5) if hazard_id == "moving_fireline" else state.origin + Vector2(0, -45)
		_expect(bool(arena.teleport_actor("ranger", hit_position).get("ok", false)), "%s hit pose is blocked" % hazard_id, failures)
		fixture.step(arena)
		fixture.step(arena)
		var after_hit: float = arena.player_health
		fixture.step(arena)
		_expect(after_hit < 100.0 and is_equal_approx(arena.player_health, after_hit), "%s did not deal exactly one hit per cycle" % hazard_id, failures)
		arena.teleport_actor("ranger", center + Vector2(350.0, 170.0))
		fixture.advance_to(arena, 119)
		var before_dodge: float = arena.player_health
		_expect(fixture.cast(arena, "dodge", 0, Vector2.UP).get("accepted", false), "%s real dodge setup failed" % hazard_id, failures)
		state = arena.hazard_states[0]
		hit_position = state.origin + Vector2(0.0, state.length * 0.5) if hazard_id == "moving_fireline" else state.origin + Vector2(0, -45)
		_expect(bool(arena.teleport_actor("ranger", hit_position).get("ok", false)), "%s hit pose is blocked" % hazard_id, failures)
		arena._hazards._update_hazards_tick()
		_expect(is_equal_approx(arena.player_health, before_dodge), "%s ignored dodge immunity" % hazard_id, failures)


func _test_hazard_decision_boundaries(arena: Node, failures: Array[String]) -> void:
	for hazard_id in ["exposed_ground_zone", "moving_fireline"]:
		arena = _configure_room(arena, "rectangle_arena", "clear", ["melee_pursuer"], "", [hazard_id])
		fixture.advance_to(arena, arena.HAZARD_WARNING_TICKS - 1)
		fixture.drive(arena, {"enemies": true})
		fixture.step(arena)
		var state: Dictionary = arena.hazard_states[0]
		_expect(int(state.cycle_tick) == arena.HAZARD_WARNING_TICKS and String(state.phase) == "active", "%s decision boundary: enemy planning retained the previous tick hazard phase" % hazard_id, failures)
	arena = _configure_room(arena, "rectangle_arena", "clear", ["melee_pursuer"], "", ["moving_fireline"])
	fixture.advance_to(arena, arena.HAZARD_WARNING_TICKS + arena.HAZARD_ACTIVE_TICKS - 1)
	var fireline: Dictionary = arena.hazard_states[0]
	arena.teleport_actor("ranger", fireline.origin + Vector2(0.0, fireline.length * 0.5))
	_expect(arena.smoke_input_driver.requires_dodge({"player": arena.player_combat_state.snapshot(arena.sim_tick), "hazards": arena.hazard_states.duplicate(true), "boss": {"impact_tick": arena.boss.impact_tick, "target_shape": arena.boss.target_shape.duplicate(true)} if arena.boss != null else {}}), "moving_fireline decision boundary: player logic ignored the final active tick", failures)


func _test_elite_rules(arena: Node, failures: Array[String]) -> void:
	arena = _configure_room(arena, "rectangle_arena", "hunt_elite", ["melee_pursuer", "fan_ranged"], "", [], ["periodic_barrier"])
	var elite = arena.enemies[0]
	arena.teleport_actor("ranger", elite.position)
	arena._update_room_rules_tick()
	var health_before: float = elite.health
	_cast_and_resolve_arrow(arena)
	_expect(arena.elite_barrier_active and is_equal_approx(elite.health, health_before), "periodic barrier did not truly block damage", failures)
	fixture.advance_to(arena, 20)
	arena._update_room_rules_tick()
	_cast_and_resolve_arrow(arena)
	_expect(not arena.elite_barrier_active and elite.health < health_before, "periodic barrier did not open at fixed tick", failures)

	arena = _configure_room(arena, "ring", "hunt_elite", ["melee_pursuer"], "", [], ["summon_reinforcements"])
	elite = arena.enemies[0]
	elite.health = elite.maximum_health * 0.5
	fixture.drive(arena, {"enemies": true})
	fixture.step(arena)
	var count_after_summon: int = arena.enemies.size()
	fixture.step(arena)
	_expect(arena.reinforcements_summoned and count_after_summon == 2 and arena.enemies.size() == 2 and arena.enemies[1].entity_id == 2
		and arena.enemies[1].health == 720.0 and arena.enemies[1].maximum_health == 720.0,
		"reinforcement rule did not summon exactly once with stable ID and normal melee durability", failures)

	arena = _configure_room(arena, "ring", "hunt_elite", ["melee_pursuer"], "", [], ["summon_reinforcements"])
	elite = arena.enemies[0]
	## A point-blank teleport onto the elite drops the arrow's frozen bow-socket
	## path inside the target's hurtbox, where the kernel sweep skips the
	## initially-overlapping body and the shot always strafes. Hold a clear
	## firing lane south-west of the elite instead: that quadrant hosts no
	## authored blocker, so the dropped 22px query line reaches the elite's
	## feet without grazing any padded projectile surface.
	arena.teleport_actor("ranger", arena._arena_rect().get_center() + Vector2.from_angle(-PI * 0.75) * 175.0)
	elite.health = 1.0
	_cast_and_resolve_arrow(arena)
	arena._check_battle_end()
	_expect(arena.reinforcements_summoned and arena.enemies.size() == 1 and arena.enemies[0].entity_id == 2, "lethal threshold crossing skipped the reinforcement", failures)
	_expect(not arena.battle_over, "hunt elite ended before summoned reinforcement was cleared", failures)
	_defeat_target(arena, arena.enemies[0], failures)
	arena._check_battle_end()
	_expect(arena.battle_over and arena.battle_victory, "hunt elite did not finish after summoned reinforcement was cleared", failures)


func _test_room_hash_sensitivity(arena: Node, failures: Array[String]) -> void:
	arena = _configure_room(arena, "corridor", "timed_break", ["melee_pursuer"], "", ["moving_fireline"], ["periodic_barrier"])
	var first: String = arena._semantic_state_hash("test")
	arena.layout_id = "ring"
	var layout_hash: String = arena._semantic_state_hash("test")
	arena.layout_id = "corridor"
	arena.hazard_states[0].origin += Vector2(1.0, 0.0)
	var hazard_hash: String = arena._semantic_state_hash("test")
	arena.hazard_states[0].origin -= Vector2(1.0, 0.0)
	arena.room_id = "hash.changed"
	var room_hash: String = arena._semantic_state_hash("test")
	arena.room_id = "test.corridor.timed_break"
	arena.room_drop_tags.append("damage")
	var drop_hash: String = arena._semantic_state_hash("test")
	arena.room_drop_tags.pop_back()
	arena.elite_barrier_active = not arena.elite_barrier_active
	var elite_hash: String = arena._semantic_state_hash("test")
	arena.elite_barrier_active = not arena.elite_barrier_active
	arena.timed_bonus_available = false
	var objective_hash: String = arena._semantic_state_hash("test")
	_defeat_target(arena, arena.enemies[0], failures)
	var reward_hash: String = arena._semantic_state_hash("test")
	_expect(arena.room_reward_snapshot.bonus_lost, "room hash: real timed victory did not commit its lost bonus", failures)
	var settled: Dictionary = SnapshotBuilder.build_runtime_state(arena, "test")
	var without_bonus_loss: Dictionary = settled.duplicate(true)
	without_bonus_loss.room_reward_snapshot.bonus_lost = false
	_expect(StateCodec.sha256_canonical(settled) == reward_hash and StateCodec.sha256_canonical(without_bonus_loss) != reward_hash,
		"room hash: settled reward state alone lost hash sensitivity", failures)
	_expect(not first.is_empty() and first != layout_hash and first != hazard_hash and first != room_hash and first != drop_hash and first != elite_hash and first != objective_hash and objective_hash != reward_hash, "walkable layout or authoritative room state lost hash sensitivity", failures)


func _test_early_durability_and_first_hunt(arena: Node, failures: Array[String]) -> void:
	for kind_id: String in ["melee_pursuer", "charging_raider", "fan_ranged"]:
		arena = _configure_room(arena, "rectangle_arena", "clear", [kind_id])
		var normal_health: float = arena.enemies[0].health
		_expect(normal_health == float(arena.EARLY_NORMAL_HEALTH_BY_KIND[kind_id]),
			"early durability: normal %s did not use its role's base health" % kind_id, failures)
		arena = _configure_room(arena, "rectangle_arena", "hunt_elite", [kind_id])
		_expect(arena.enemies[0].health >= 1000.0 and arena.enemies[0].health > normal_health * 2.0,
			"early durability: elite %s lost its distinct health pool" % kind_id, failures)
	var state = ApplicationStateScript.new()
	state.start_new_profile("ranger")
	state.complete_tutorial()
	var built := ContractPlanScript.build({"contract_id": "mainline_01_first_hunt", "seed": 301,
		"mode": "Manual", "completed_node_ids": state.profile.progression.completed_node_ids})
	_expect(bool(built.get("ok", false)), "first hunt runtime: real RoomPlan failed", failures)
	if not bool(built.get("ok", false)):
		return
	arena.test_session = true
	arena.automation_smoke = false
	arena.selected_mode = "Manual"
	arena.framework_resolved_build = state.resolved_build_snapshot()
	arena.framework_active_build = state.profile.active_build
	arena.set_process(false)
	var initial_build: Dictionary = state.resolved_build_snapshot()
	var stationary := _first_hunt_input_run(arena, built.plan.rooms, false, failures, initial_build)
	var reactive := _first_hunt_input_run(session.arena, built.plan.rooms, true, failures, initial_build)
	for metrics: Dictionary in [stationary, reactive]:
		_expect(float(metrics.seconds) >= 15.0 and float(metrics.seconds) <= 25.0,
			"first hunt runtime: real two-room input run escaped 15–25 seconds: %s" % str(metrics), failures)
		_expect(int(metrics.warnings) > 0 and int(metrics.defeated) == 6,
			"first hunt runtime: missing telegraphs or six real kills", failures)
	_expect(float(stationary.damage) > 0.0 and float(stationary.damage) <= 112.0,
		"first hunt runtime: stationary play had no consequence or exceeded the opening damage budget", failures)
	_expect(float(reactive.damage) < float(stationary.damage) and int(reactive.dodges) > 0
		and int(reactive.move_ticks) > 0,
		"first hunt runtime: real movement/dodge input gave no damage reduction", failures)


func _first_hunt_input_run(arena: Node, rooms: Array, react: bool, failures: Array[String], resolved: Dictionary) -> Dictionary:
	var metrics := {"seconds": 0.0, "damage": 0.0, "warnings": 0, "dodges": 0, "move_ticks": 0, "defeated": 0}
	for room: Dictionary in rooms:
		arena = _mount_room(room, resolved, true)
		_expect(arena.enemies.size() == 3 and arena.enemies[0].health == 720.0
			and arena.enemies[0].entity_id == 1 and arena.enemies[2].entity_id == 3,
			"first hunt runtime: roster did not spawn three durable entities", failures)
		var start := arena.player_position as Vector2
		## Authored openings stay exactly on the profile ring; the registered
		## body may be nudged clear of an authored static blocker (deterministic
		## spawn projection), so the two are asserted separately.
		var director = arena.encounter_director
		var authored_offsets: Array = director.room_spawn_offsets
		for index: int in range(arena.enemies.size()):
			var enemy = arena.enemies[index]
			if index < authored_offsets.size():
				var authored: Vector2 = director.room_origin + authored_offsets[index]
				_expect(absf(start.distance_to(authored) - 350.0) < 0.01,
					"first hunt runtime: authored opening distances are not synchronized", failures)
				_expect(enemy.position.distance_to(authored) <= 300.0,
					"first hunt runtime: registered spawn left its authored slot", failures)
		var initial_health: float = arena.player_health
		var warning_count := 0
		var dodge_count := 0
		var move_ticks := 0
		var last_event_id := 0
		var first_hit_observed := false
		_early_key_input(KEY_SPACE, true)
		while not arena.battle_over and arena.sim_tick < arena.SIM_TICKS_PER_SECOND * 60:
			var react_now := false
			for enemy in arena.enemies:
				if enemy.action_state == "windup" and enemy.impact_tick == arena.sim_tick + 2:
					react_now = true
			if react and react_now:
				_early_key_input(KEY_A, true)
				if fixture.player(arena).dodge_cooldown_ticks == 0:
					_early_dodge_input(true)
					_early_dodge_input(false)
			elif fixture.player(arena).dodge_remaining_ticks == 0:
				_early_key_input(KEY_A, false)
			var position_before: Vector2 = arena.player_position
			arena._simulate_tick()
			if arena.player_position != position_before:
				move_ticks += 1
			for event: Dictionary in arena.combat_event_stream.events_after(last_event_id):
				last_event_id = int(event.event_id)
				if event.type == "action_accepted" and String(event.get("actor_id", "")).begins_with("enemy/"):
					warning_count += 1
				if event.type == "displacement_started" and event.get("kind", "") == "dodge":
					dodge_count += 1
			if not first_hit_observed and arena.arrow_hits > 0:
				first_hit_observed = true
				_expect(arena.enemies.size() == 3,
					"first hunt runtime: fresh starter arrow killed a full-health melee enemy", failures)
		_early_key_input(KEY_SPACE, false)
		_early_key_input(KEY_A, false)
		var damage: float = initial_health - arena.player_health
		print("FIRST_HUNT_INPUT mode=%s room=%s victory=%s seconds=%.2f casts=%d damage=%.1f warnings=%d dodges=%d move_ticks=%d" % [
			"reactive" if react else "stationary", room.room_id, str(arena.battle_victory), arena.elapsed,
			arena.shots, damage, warning_count, dodge_count, move_ticks])
		_expect(first_hit_observed and arena.battle_victory and damage <= initial_health * 0.5,
			"first hunt runtime: real input did not clear a room within the opening damage budget", failures)
		metrics.seconds += arena.elapsed
		metrics.damage += damage
		metrics.warnings += warning_count
		metrics.dodges += dodge_count
		metrics.move_ticks += move_ticks
		metrics.defeated += arena.defeated
	return metrics


func _early_key_input(code: int, pressed: bool) -> void:
	# Real device events flow through InputMap, GUI dispatch and Main's input handlers.
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _early_dodge_input(pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = pressed
	event.position = Vector2(320.0, 240.0) # Open playfield, outside the HUD.
	event.global_position = event.position
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _configure_room(_arena: Node, layout: String, objective: String, enemy_ids: Array, boss_id: String = "", hazards: Array = [], elite_rules: Array = [], drop_tags: Array = ["equipment_general"]) -> Node:
	var room := {
		"room_id": "test.%s.%s" % [layout, objective], "layout_id": layout,
		"objective_id": objective, "hazard_ids": hazards.duplicate(), "enemy_ids": enemy_ids.duplicate(),
		"elite_rule_ids": elite_rules.duplicate(), "boss_id": boss_id, "drop_tags": drop_tags.duplicate(),
	}
	return _mount_room(room)


func _test_melee_stuck_escape_intent(arena: Node, failures: Array[String]) -> void:
	## A melee pinned against unreachable geometry re-slots: in a ring it walks
	## the annulus tangent toward the player; in a rectangle it picks the wedge
	## nearest its own bearing instead of grinding the fixed far slot forever.
	arena = _configure_room(arena, "ring", "clear", ["melee_pursuer"])
	var enemy = arena.enemies[0]
	arena.teleport_actor("ranger", arena._arena_rect().get_center() + Vector2(-180.0, 80.0))
	arena.teleport_actor("enemy/%d" % enemy.entity_id, arena.player_position + Vector2(280.0, -20.0))
	enemy.stuck_ticks = 40
	enemy.stuck_anchor = enemy.position
	var ring_intent: Dictionary = arena.encounter_director._intent_for_enemy(enemy)
	_expect(String(ring_intent.get("reason", "")) == "melee_annulus_escape" and not (ring_intent.get("move_direction", Vector2.ZERO) as Vector2).is_zero_approx(),
		"escape: a stuck melee in a ring room did not get the annulus escape intent", failures)
	enemy.stuck_ticks = 0
	enemy.stuck_anchor = Vector2.INF
	var free_intent: Dictionary = arena.encounter_director._intent_for_enemy(enemy)
	_expect(String(free_intent.get("reason", "")) == "melee_ring_slot", "escape: an unstuck melee lost its authored ring slot reason", failures)
	arena = _configure_room(arena, "rectangle_arena", "clear", ["melee_pursuer"])
	enemy = arena.enemies[0]
	arena.teleport_actor("ranger", arena._arena_rect().get_center())
	arena.teleport_actor("enemy/%d" % enemy.entity_id, arena.player_position + Vector2(280.0, -20.0))
	enemy.stuck_ticks = 40
	enemy.stuck_anchor = enemy.position
	var escape_intent: Dictionary = arena.encounter_director._intent_for_enemy(enemy)
	_expect(String(escape_intent.get("reason", "")) == "melee_escape_slot",
		"escape: a stuck melee outside a ring did not get the same-side escape slot", failures)
	_default_room()


func _enemy_of_kind(arena: Node, kind_id: String) -> Variant:
	for enemy in arena.enemies:
		if enemy.kind_id == kind_id:
			return enemy
	return null


func _cast_and_resolve_arrow(arena: Node) -> bool:
	fixture.wait_ready(arena)
	var target = arena._preferred_skill_one_target()
	if target == null:
		return false
	var receipt := fixture.cast(arena, "piercing_arrow", target.entity_id)
	if not bool(receipt.get("accepted", false)):
		return false
	fixture.advance_to(arena, arena.sim_tick + Timeline.WINDUP_TICKS)
	fixture.resolve_projectiles(arena)
	return true


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)


func _mount_room(room: Dictionary, resolved: Dictionary = {}, live_input: bool = false) -> Node:
	if not session.is_empty():
		fixture.free_session(session)
	session = fixture.mount(room, resolved)
	fixture.drive(session.arena, {"input": live_input, "enemies": live_input})
	return session.arena


func _default_room() -> Node:
	var room: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/rooms/combat/test_fixture.json"))
	return _mount_room(room)


func _defeat_target(arena: Node, target, failures: Array[String]) -> void:
	# A low-health enemy initial state is settled by the real arrow contact,
	# which also increments CS totals and commits room completion normally.
	target.health = 1.0
	var start: Vector2 = arena.player_position
	## Authored blockers own static clearance, so the first lateral contact
	## offset can land on a registered blocker surface or outside the padded
	## walkable band (ring rooms seal the east lane). Try the four contact
	## offsets in a fixed deterministic order and keep the first one the
	## registry accepts; the real arrow contact itself stays unchanged.
	var footprint: float = 18.0
	var target_state = arena.actor_registry.actor("enemy/%d" % target.entity_id)
	if target_state != null:
		footprint = float(target_state.footprint_radius)
	var position: Vector2 = arena._clamp_to_arena(start + Vector2(60.0, 0.0), 16.0)
	for offset: Vector2 in [Vector2(60.0, 0.0), Vector2(-60.0, 0.0), Vector2(0.0, 60.0), Vector2(0.0, -60.0)]:
		var candidate: Vector2 = arena._clamp_to_arena(start + offset, 16.0)
		if arena.actor_registry.is_position_clear(candidate, footprint):
			position = candidate
			break
	arena.teleport_actor("enemy/%d" % target.entity_id, position)
	fixture.wait_ready(arena)
	var receipt := fixture.cast(arena, "piercing_arrow", target.entity_id)
	_expect(bool(receipt.get("accepted", false)), "room objective: real kill setup was rejected", failures)
	fixture.advance_to(arena, arena.sim_tick + Timeline.WINDUP_TICKS)
	fixture.resolve_projectiles(arena)
	_expect(target not in arena.enemies and arena.defeated > 0, "room objective: target did not die through CS contact", failures)
