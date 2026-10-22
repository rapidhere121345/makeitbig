extends SceneTree

const PlayerFixture := preload("res://tests/helpers/player_domain_fixture.gd")
const Skill := preload("res://src/systems/ranger_skill_rules.gd")
const Timeline := preload("res://src/systems/player_action_timeline.gd")
const Protocol := preload("res://src/systems/combat_command_protocol.gd")
const ContentRegistryScript := preload("res://src/content/content_registry.gd")
const ProxyBuildScript := preload("res://src/systems/proxy_build.gd")
const RangerAnimationScript := preload("res://src/presentation/ranger_animation.gd")
const ArenaWorldViewScript := preload("res://src/presentation/arena_world_view.gd")


var fixture := PlayerFixture.new()
var session: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	root.size = Vector2i(1280, 720)
	session = fixture.mount(_skill_room(), fixture.build({"d": 100.0, "max_health": 1.0e9}), true)
	var arena = session.arena
	await process_frame

	_test_loadout_gate(arena, failures)
	_test_hunter_mark(arena, failures)
	_test_mark_priority_and_damage(arena, failures)
	_test_action_timeline_and_buffer(arena, failures)
	_test_piercing_arrow_frozen_impact_geometry(arena, failures)
	_test_projectile_entity_bound(arena, failures)
	_test_kill_cancels_only_matching_buffered_arrow(arena, failures)
	_test_same_tick_runtime_arbitration(arena, failures)
	_test_proxy_decision_state_runtime(arena, failures)
	_test_proxy_current_legality_runtime(arena, failures)
	_test_proxy_resolved_variants_runtime(arena, failures)
	_test_proxy_retreat_runtime(arena, failures)
	_test_proxy_target_death_reacquire_state_reset(arena, failures)
	_test_dodge_facing_integration(arena, failures)
	_test_dodge_interrupts_arrow(arena, failures)
	_test_mobility_boundary_buffer(arena, failures)
	_test_dash(arena, failures)
	_test_input_map_movement(arena, failures)
	_test_manual_pointer_exact_selection(arena, failures)
	_test_manual_pointer_blank_and_quick_edge(arena, failures)
	_test_manual_pointer_lock_lifecycle(arena, failures)
	_test_assisted_and_pointer_arbitration(arena, failures)
	_test_auto_ignores_manual_device_state(arena, failures)
	_test_pointer_camera_round_trip(arena, failures)
	_test_pointer_command_protocol_boundary(arena, failures)
	_test_held_attack_repeats_without_buffer_churn(arena, failures)
	_test_hash_sensitivity(arena, failures)
	_test_arena_reset(arena, failures)

	_release_input_actions()
	fixture.free_session(session)
	if failures.is_empty():
		print("PASS  test_ranger_combat_skills.gd")
		quit(0)
		return
	for failure in failures:
		printerr("- %s" % failure)
	quit(1)


func _test_loadout_gate(arena: Node, failures: Array[String]) -> void:
	_configure_enemies(arena, {}, ["piercing_arrow", "", ""])
	_expect(not _cast(arena, "hunter_mark") and _player(arena).marked_entity_id == 0, "unequipped hunter mark accepted input", failures)
	_expect(not _dash(arena, Vector2.RIGHT) and _player(arena).dash_remaining_ticks == 0, "unequipped dash accepted input", failures)
	_configure_enemies(arena, {}, ["piercing_arrow", "dash", "hunter_mark"])
	_expect(not _cast(arena, "hunter_mark") and not _dash(arena, Vector2.RIGHT), "skills in the wrong slots bypassed fixed-slot gating", failures)
	arena.presentation.skill_requested.emit("hunter_mark")
	arena.presentation.skill_requested.emit("dash")
	_expect(not arena.command_source.hunter_mark_requested and not arena.command_source.dash_requested, "unequipped HUD actions bypassed loadout", failures)
	_configure_enemies(arena)
	_expect(_cast(arena, "hunter_mark"), "equipped hunter mark was rejected", failures)
	_expect(_dash(arena, Vector2.RIGHT), "equipped dash was rejected", failures)
	fixture.wait_ready(arena, "dash_cooldown_ticks")
	arena.selected_mode = "Auto"
	_start_proxy(arena, _white_proxy_build())
	var auto_abilities: Array[String] = []
	for command in arena._auto_commands():
		if String(command.get("kind", "")) == "cast":
			auto_abilities.append(String(command.get("ability_id", "")))
	_expect("hunter_mark" not in auto_abilities and "dash" not in auto_abilities, "Auto issued a hidden skill 2/3 command", failures)
	arena.selected_mode = "Manual"


func _test_hunter_mark(arena: Node, failures: Array[String]) -> void:
	_configure_enemies(arena)
	var near = arena.enemies[0]
	var far = arena.enemies[1]
	arena.teleport_actor("enemy/%d" % near.entity_id, arena.player_position + Vector2(70.0, 0.0))
	arena.teleport_actor("enemy/%d" % far.entity_id, arena.player_position + Vector2(120.0, 0.0))
	_expect(_cast(arena, "hunter_mark") and _player(arena).marked_entity_id == near.entity_id, "hunter mark did not select nearest in-range living enemy", failures)
	_expect(arena.battle_report == "Hunter's Mark locked: Melee Pursuer." and "entity" not in arena.battle_report and "#" not in arena.battle_report, "hunter mark report exposed an internal entity id: %s" % arena.battle_report, failures)
	var expiry: int = _player(arena).hunter_mark_expires_tick
	_expect(expiry == arena.sim_tick + Skill.HUNTER_MARK_DURATION_TICKS, "hunter mark expiry tick is not fixed", failures)
	_expect(not _cast(arena, "hunter_mark") and _player(arena).hunter_mark_expires_tick == expiry, "hunter mark ignored independent cooldown", failures)
	fixture.advance_to(arena, expiry)
	_expect(_player(arena).marked_entity_id == 0 and _player(arena).hunter_mark_expires_tick == 0, "hunter mark did not clear at expiry tick", failures)
	fixture.wait_ready(arena, "hunter_mark_cooldown_ticks")
	arena.teleport_actor("enemy/%d" % near.entity_id, arena.player_position + Vector2(151.0, 0.0))
	arena.teleport_actor("enemy/%d" % far.entity_id, arena.player_position + Vector2(180.0, 0.0))
	_expect(not _cast(arena, "hunter_mark") and _player(arena).marked_entity_id == 0, "hunter mark accepted a target outside 1.5x range", failures)
	arena.teleport_actor("enemy/%d" % near.entity_id, arena.player_position + Vector2(150.0, 0.0))
	_expect(_cast(arena, "hunter_mark"), "hunter mark rejected a target on the range boundary", failures)
	near.health = 0.0
	fixture.step(arena)
	_expect(_player(arena).marked_entity_id == 0, "hunter mark did not clear when target died", failures)


func _test_mark_priority_and_damage(arena: Node, failures: Array[String]) -> void:
	_configure_enemies(arena)
	var first = arena.enemies[0]
	var marked = arena.enemies[1]
	arena.teleport_actor("enemy/%d" % first.entity_id, arena.player_position + Vector2(140.0, 0.0))
	arena.teleport_actor("enemy/%d" % marked.entity_id, arena.player_position + Vector2(80.0, 0.0))
	_expect(_cast(arena, "hunter_mark") and _player(arena).marked_entity_id == marked.entity_id, "priority setup failed to mark requested target", failures)
	arena.teleport_actor("enemy/%d" % first.entity_id, arena.player_position + Vector2(20.0, 0.0))
	var base_damage: float = float(arena.locked_payload) * float(arena._current_model().total_events_float)
	first.health = base_damage * 4.0
	marked.health = base_damage * 4.0
	var first_before: float = first.health
	var marked_before: float = marked.health
	_cast_and_resolve_arrow(arena)
	_expect(is_equal_approx(first.health, first_before), "piercing arrow ignored the legal marked-target priority", failures)
	_expect(is_equal_approx(marked_before - marked.health, base_damage * Skill.HUNTER_MARK_DAMAGE_MULTIPLIER), "marked target did not receive fixed 1.25x damage", failures)


func _test_action_timeline_and_buffer(arena: Node, failures: Array[String]) -> void:
	_configure_enemies(arena, {"v": 400.0})
	var target = arena.enemies[0]
	arena.teleport_actor("enemy/%d" % target.entity_id, arena.player_position + Vector2(90.0, 0.0))
	target.health = 1.0e12
	target.maximum_health = target.health
	var health_before: float = target.health
	var started := fixture.cast(arena, "piercing_arrow", target.entity_id)
	_expect(bool(started.get("accepted", false)), "timeline: valid arrow request was rejected", failures)
	_expect(is_equal_approx(target.health, health_before), "timeline: arrow dealt damage on the request tick", failures)
	var windup_ui: Dictionary = arena.presentation.frame_builder.attack_state(arena.gameplay_snapshot(), arena.input_adapter.view_state(arena.gameplay_snapshot()))
	_expect(String(windup_ui.label) == "Draw" and int(windup_ui.phase_remaining_ticks) == Timeline.WINDUP_TICKS, "timeline: HUD did not expose the full windup window", failures)
	_expect(int(arena.presentation.animations.ranger_state(arena.gameplay_snapshot()).shoot_ticks) == 0, "timeline: shoot animation did not start on the accepted action", failures)
	var start_tick: int = arena.sim_tick
	var frozen_aim: Vector2 = (_player(arena).attack_origins.values()[0] as Dictionary).get("direction", Vector2.RIGHT)
	# Reduced windup motion uses ordinary commands and the one registry motor.
	for _tick in Timeline.WINDUP_TICKS - 1:
		fixture.step(arena, [fixture.command(arena, "move", 0, frozen_aim)])
	_expect(is_equal_approx(target.health, health_before), "timeline: arrow resolved before the impact tick", failures)
	var moved_feet: Vector2 = arena.player_position
	var expected_release_origin: Vector2 = moved_feet + RangerAnimationScript.arrow_attachment_offset(
		RangerAnimationScript.facing_key(_player(arena).player_facing),
		RangerAnimationScript.shoot_frame_at_tick(Timeline.WINDUP_TICKS),
		ArenaWorldViewScript.GAMEPLAY_TO_WORLD)
	fixture.step(arena)
	_expect(arena.sim_tick == start_tick + Timeline.WINDUP_TICKS and is_equal_approx(target.health, health_before) and arena.projectiles.size() == 1, "timeline: release did not create one in-flight authoritative projectile", failures)
	var released_projectile = arena.projectiles[0]
	# Observe the spawn boundary before the same production tick advances flight.
	var release_frame := fixture.release_frame(arena, released_projectile.action_instance_id)
	_expect(release_frame.position == release_frame.origin and release_frame.previous_position == release_frame.origin, "timeline: release frame jumped the arrow away from the authored bow-hand socket", failures)
	_expect(released_projectile.origin.is_equal_approx(expected_release_origin), "timeline: windup movement left the released arrow behind the current bow-hand socket", failures)
	_expect(String(arena.presentation.frame_builder.attack_state(arena.gameplay_snapshot(), arena.input_adapter.view_state(arena.gameplay_snapshot())).label) == "Release", "timeline: impact tick was not exposed as Release", failures)
	var release_tick: int = arena.sim_tick
	_advance_arrow_until_resolved(arena)
	_expect(target.health < health_before and String(arena.last_attack_outcome.get("outcome", "")) == "damage" and arena.sim_tick > release_tick, "timeline: damage did not wait for projectile contact (release=%d resolved=%d outcome=%s health=%.3f/%.3f)" % [release_tick, arena.sim_tick, String(arena.last_attack_outcome.get("outcome", "")), target.health, health_before], failures)
	_expect(String(arena.presentation.frame_builder.attack_state(arena.gameplay_snapshot(), arena.input_adapter.view_state(arena.gameplay_snapshot())).label) == "Recovery", "timeline: recovery was not exposed as Recovery", failures)
	var ready_tick := start_tick + Skill.PIERCING_ARROW_COOLDOWN_TICKS
	fixture.advance_to(arena, ready_tick - Timeline.INPUT_BUFFER_TICKS)
	_expect(_player(arena).attack_cooldown_ticks == 4, "timeline: real cooldown did not expose the four-tick buffer window", failures)
	_expect(bool(arena.request_player_cast("piercing_arrow", target.entity_id).get("accepted", false)), "timeline: request inside the four-tick buffer was rejected", failures)
	var buffered_ui: Dictionary = arena.presentation.frame_builder.attack_state(arena.gameplay_snapshot(), arena.input_adapter.view_state(arena.gameplay_snapshot()))
	_expect(bool(buffered_ui.buffered) and bool(buffered_ui.request_open), "timeline: accepted buffer was not visible to the HUD", failures)


func _test_piercing_arrow_frozen_impact_geometry(arena: Node, failures: Array[String]) -> void:
	_configure_enemies(arena)
	var target = arena.enemies[0]
	var actor_origin: Vector2 = arena.player_position
	arena.teleport_actor("enemy/%d" % target.entity_id, actor_origin + Vector2(90.0, 22.0))
	target.health = 1.0e12
	target.maximum_health = target.health
	var health_before: float = target.health
	_expect(_start_frozen_arrow(arena, target, Vector2.RIGHT), "frozen impact: on-ray setup was rejected", failures)
	fixture.advance_to(arena, arena.sim_tick + Timeline.WINDUP_TICKS)
	_expect(arena.projectiles.size() == 1 and is_equal_approx(target.health, health_before), "frozen impact: release did not leave damage pending behind a real projectile", failures)
	var projectile = arena.projectiles[0]
	var release_tick: int = arena.sim_tick
	var frozen_origin: Vector2 = projectile.origin
	var frozen_direction: Vector2 = projectile.direction
	var frozen_speed: float = projectile.speed
	var frozen_range: float = projectile.maximum_range
	var frozen_damage: float = projectile.ordinary_damage
	var frozen_build: Dictionary = arena.framework_resolved_build.duplicate(true)
	## Contract state cannot retarget or rescale an arrow after release.
	arena.framework_resolved_build = fixture.build({"d": 1.0, "damage": 1.0, "v": 1.0})
	_advance_arrow_until_resolved(arena)
	arena.framework_resolved_build = frozen_build
	_expect(target.health < health_before and String(arena.last_attack_outcome.get("outcome", "")) == "damage", "frozen impact: swept projectile did not damage its intended target", failures)
	_expect(is_equal_approx(health_before - target.health, frozen_damage), "frozen impact: post-release build changes altered projectile damage", failures)
	_expect(arena.sim_tick > release_tick and arena.projectiles.is_empty(), "frozen impact: projectile resolved without fixed-tick travel", failures)
	_expect(frozen_speed > 0.0 and is_equal_approx(frozen_range, arena.locked_targeting_distance), "frozen impact: release did not freeze speed and range", failures)
	var contact: Vector2 = arena.last_attack_outcome.get("contact_point", Vector2.ZERO)
	_expect(absf((contact - frozen_origin).cross(frozen_direction)) < 0.01, "frozen impact: contact left the frozen arrow path", failures)
	_expect(not arena.presentation.feedback.traces.is_empty() and arena.presentation.feedback.traces[0].from == contact, "frozen impact: hit effect redrew an instant origin-to-target trace", failures)

	_configure_enemies(arena)
	target = arena.enemies[0]
	actor_origin = arena.player_position
	arena.teleport_actor("enemy/%d" % target.entity_id, actor_origin + Vector2(60.0, 22.0))
	target.health = 1.0e12
	target.maximum_health = target.health
	health_before = target.health
	_expect(_start_frozen_arrow(arena, target, Vector2.RIGHT), "frozen impact: lateral-miss setup was rejected", failures)
	arena.teleport_actor("enemy/%d" % target.entity_id, actor_origin + Vector2(60.0, 220.0))
	fixture.advance_to(arena, arena.sim_tick + Timeline.WINDUP_TICKS)
	projectile = arena.projectiles[0]
	frozen_origin = projectile.origin
	frozen_direction = projectile.direction
	_advance_arrow_until_resolved(arena)
	_expect(is_equal_approx(target.health, health_before) and String(arena.last_attack_outcome.get("outcome", "")) == "miss", "frozen impact: laterally moved target was damaged", failures)
	_expect((arena.last_attack_outcome.get("contact_point", Vector2.ZERO) as Vector2).is_equal_approx(frozen_origin + frozen_direction * arena.locked_targeting_distance), "frozen impact: lateral miss did not stop at frozen world range", failures)
	_expect(arena.presentation.feedback.traces.is_empty(), "frozen impact: a miss fabricated an impact trace", failures)

	_configure_enemies(arena)
	target = arena.enemies[0]
	actor_origin = arena.player_position
	arena.teleport_actor("enemy/%d" % target.entity_id, actor_origin + Vector2(60.0, 22.0))
	target.health = 1.0e12
	target.maximum_health = target.health
	health_before = target.health
	_expect(_start_frozen_arrow(arena, target, Vector2.RIGHT), "frozen impact: range-miss setup was rejected", failures)
	arena.teleport_actor("enemy/%d" % target.entity_id, actor_origin + Vector2(arena.locked_targeting_distance + 40.0, 22.0))
	fixture.advance_to(arena, arena.sim_tick + Timeline.WINDUP_TICKS)
	projectile = arena.projectiles[0]
	frozen_origin = projectile.origin
	frozen_direction = projectile.direction
	_advance_arrow_until_resolved(arena)
	_expect(is_equal_approx(target.health, health_before) and String(arena.last_attack_outcome.get("outcome", "")) == "miss", "frozen impact: target moved beyond frozen range was damaged", failures)
	_expect((arena.last_attack_outcome.get("contact_point", Vector2.ZERO) as Vector2).is_equal_approx(frozen_origin + frozen_direction * arena.locked_targeting_distance), "frozen impact: range miss did not resolve at frozen range", failures)


func _test_projectile_entity_bound(arena: Node, failures: Array[String]) -> void:
	# A slow frozen projectile build keeps real arrows in flight across casts.
	_configure_enemies(arena, {"v": 1.0})
	var target = arena.enemies[0]
	arena.teleport_actor("enemy/%d" % target.entity_id, arena.player_position + Vector2(80.0, 0.0))
	target.health = 1.0e30
	target.maximum_health = target.health
	for _index in range(arena.combat_system.MAX_ACTIVE_PIERCING_PROJECTILES + 1):
		fixture.wait_ready(arena)
		var receipt := fixture.cast(arena, "piercing_arrow", target.entity_id, Vector2.RIGHT)
		_expect(bool(receipt.get("accepted", false)), "projectile bound: real cast setup failed", failures)
		fixture.advance_to(arena, arena.sim_tick + Timeline.WINDUP_TICKS)
	_expect(arena.projectiles.size() == arena.combat_system.MAX_ACTIVE_PIERCING_PROJECTILES, "projectile bound: active arrow entities exceeded their fixed cap", failures)
	_expect(String(arena.last_attack_outcome.get("reason", "")) == "projectile_limit", "projectile bound: overflow did not resolve deterministically", failures)


func _test_kill_cancels_only_matching_buffered_arrow(arena: Node, failures: Array[String]) -> void:
	_configure_enemies(arena, {"v": 50.0})
	var first = arena.enemies[0]
	var second = arena.enemies[1]
	arena.teleport_actor("enemy/%d" % first.entity_id, arena.player_position + Vector2(60.0, 0.0))
	arena.teleport_actor("enemy/%d" % second.entity_id, arena.player_position + Vector2(90.0, 0.0))
	first.health = 1.0
	first.maximum_health = 1.0
	second.health = 1.0e12
	second.maximum_health = second.health
	var initial := fixture.cast(arena, "piercing_arrow", first.entity_id)
	var start_tick: int = arena.sim_tick
	fixture.advance_to(arena, start_tick + Timeline.WINDUP_TICKS)
	_expect(arena.projectiles.size() == 1 and first in arena.enemies, "kill buffer: release damaged before projectile contact", failures)
	fixture.advance_to(arena, start_tick + Skill.PIERCING_ARROW_COOLDOWN_TICKS - Timeline.INPUT_BUFFER_TICKS)
	var buffered: Dictionary = arena.request_player_cast("piercing_arrow", first.entity_id)
	_expect(String(buffered.get("status", "")) == "buffered" and int(buffered.get("start_tick", -1)) == start_tick + Skill.PIERCING_ARROW_COOLDOWN_TICKS, "kill buffer: same-target request was not queued inside its window", failures)
	var buffered_request_id := int(buffered.get("request_id", 0))
	_advance_arrow_until_resolved(arena)
	_expect(bool(initial.get("accepted", false)) and first not in arena.enemies, "kill buffer: first arrow did not kill the first target", failures)
	_expect(not arena.presentation.feedback.attack_request_sources.has(buffered_request_id), "kill buffer: canceled request retained its input source", failures)
	fixture.advance_to(arena, 20)
	var accepted_count := 0
	var miss_count := 0
	for event: Dictionary in arena.combat_event_stream.snapshot().events:
		if String(event.get("type", "")) == "action_accepted" and String(event.get("actor_id", "")) == "ranger":
			accepted_count += 1
		if String(event.get("type", "")) == "attack_resolved" and String(event.get("outcome", "")) == "miss":
			miss_count += 1
	_expect(second in arena.enemies and not arena.battle_over, "kill buffer: surviving second enemy incorrectly ended the battle", failures)
	_expect(arena.shots == 1 and accepted_count == 1 and miss_count == 0, "kill buffer: canceled request started or resolved after the kill", failures)

	# Killing one target preserves a follow-up queued for a different living entity.
	_configure_enemies(arena, {"v": 50.0})
	first = arena.enemies[0]
	second = arena.enemies[1]
	arena.teleport_actor("enemy/%d" % first.entity_id, arena.player_position + Vector2(60.0, 0.0))
	arena.teleport_actor("enemy/%d" % second.entity_id, arena.player_position + Vector2(90.0, 0.0))
	first.health = 1.0
	second.health = 1.0e12
	fixture.cast(arena, "piercing_arrow", first.entity_id)
	start_tick = arena.sim_tick
	fixture.advance_to(arena, start_tick + Skill.PIERCING_ARROW_COOLDOWN_TICKS - Timeline.INPUT_BUFFER_TICKS)
	buffered = arena.request_player_cast("piercing_arrow", second.entity_id)
	_expect(String(buffered.get("status", "")) == "buffered", "kill buffer: different-target follow-up was not queued", failures)
	_advance_arrow_until_resolved(arena)
	_expect(first not in arena.enemies and int(_player(arena).timeline.buffered.get("target_entity_id", 0)) == second.entity_id,
		"kill buffer: first target death canceled a different living target's buffer", failures)
	fixture.advance_to(arena, int(buffered.get("start_tick", arena.sim_tick)) + Timeline.WINDUP_TICKS)
	_advance_arrow_until_resolved(arena)
	_expect(second in arena.enemies and arena.shots == 2 and arena.arrow_hits == 2,
		"kill buffer: preserved follow-up did not produce its second real contact", failures)


func _test_same_tick_runtime_arbitration(arena: Node, failures: Array[String]) -> void:
	_configure_enemies(arena)
	fixture.drive(arena, {"input": true})
	arena.in_arena = true
	arena.command_source.dodge_requested = true
	arena.command_source.dash_requested = true
	arena._simulate_tick()
	_expect(_player(arena).dodge_remaining_ticks > 0 and _player(arena).dash_remaining_ticks == 0, "arbitration: same-tick dodge and dash both changed mobility authority", failures)
	var dash_rejected := false
	for receipt: Dictionary in arena.last_command_receipts:
		var command: Dictionary = receipt.get("command", {})
		if String(command.get("kind", "")) == Protocol.KIND_CAST and String(command.get("ability_id", "")) == Protocol.ABILITY_DASH:
			dash_rejected = String(receipt.get("reason", "")) == "action_conflict"
	_expect(dash_rejected, "arbitration: losing dash did not retain an explicit conflict receipt", failures)

	_configure_enemies(arena)
	fixture.drive(arena, {"input": true})
	arena.in_arena = true
	var target = arena.enemies[0]
	arena.teleport_actor("enemy/%d" % target.entity_id, arena.player_position + Vector2(60.0, 0.0))
	var base_damage: float = float(arena.locked_payload) * float(arena._current_model().total_events_float)
	target.health = base_damage * 10.0
	target.maximum_health = target.health
	var before: float = target.health
	arena.command_source.hunter_mark_requested = true
	arena.command_source.attack_requested = true
	arena._simulate_tick()
	var active: Dictionary = _player(arena).timeline.active
	_expect(_player(arena).marked_entity_id == target.entity_id and int(active.get("target_entity_id", 0)) == target.entity_id, "arbitration: mark was not committed before the compatible arrow", failures)
	for _step in Timeline.WINDUP_TICKS:
		arena._simulate_tick()
	_expect(is_equal_approx(target.health, before) and arena.projectiles.size() == 1,
		"arbitration: release bypassed the real projectile travel window", failures)
	var projectile_guard := 0
	while not arena.projectiles.is_empty() and projectile_guard < 120:
		arena._simulate_tick()
		projectile_guard += 1
	_expect(is_equal_approx(before - target.health, base_damage * Skill.HUNTER_MARK_DAMAGE_MULTIPLIER), "arbitration: same-tick mark did not affect the locked arrow impact", failures)


func _test_proxy_decision_state_runtime(arena: Node, failures: Array[String]) -> void:
	_configure_enemies(arena)
	arena.selected_mode = "Auto"
	_start_proxy(arena, _white_proxy_build())
	var first = arena.enemies[0]
	var second = arena.enemies[1]
	arena.teleport_actor("enemy/%d" % first.entity_id, arena.player_position + Vector2(50.0, 0.0))
	arena.teleport_actor("enemy/%d" % second.entity_id, arena.player_position + Vector2(80.0, 0.0))
	var first_commands: Array[Dictionary] = arena._auto_commands()
	_expect(_cast_target(first_commands) == first.entity_id and _cast_has_aim(first_commands), "proxy: first perception did not emit an explicit target and aim", failures)
	arena.teleport_actor("enemy/%d" % first.entity_id, arena.player_position + Vector2(90.0, 0.0))
	arena.teleport_actor("enemy/%d" % second.entity_id, arena.player_position + Vector2(20.0, 0.0))
	fixture.advance_to(arena, 29)
	arena._auto_commands()
	var retained_state: Dictionary = arena.proxy_intent_system.decision_state_snapshot()
	_expect(int(retained_state.get("target_entity_id", 0)) == first.entity_id
			and int(retained_state.get("next_perception_tick", 0)) == 30
			and arena._proxy_trace_snapshot().has("perception:retain_target"),
		"proxy: target changed before the 30-tick perception refresh", failures)
	fixture.advance_to(arena, 30)
	var refreshed_commands: Array[Dictionary] = arena._auto_commands()
	_expect(_cast_target(refreshed_commands) == second.entity_id, "proxy: target did not refresh on the public perception tick", failures)
	arena.selected_mode = "Manual"


func _test_proxy_current_legality_runtime(arena: Node, failures: Array[String]) -> void:
	arena.embedded_session = true
	arena.framework_active_build = {"skills": ["piercing_arrow", "hunter_mark", "dash"]}
	arena.framework_resolved_proxy_build = _white_proxy_build()
	arena.framework_room = {
		"room_id": "test.ranger.proxy_barrier",
		"layout_id": "rectangle_arena",
		"objective_id": "hunt_elite",
		"hazard_ids": [],
		"enemy_ids": ["melee_pursuer", "fan_ranged"],
		"elite_rule_ids": ["periodic_barrier"],
		"boss_id": "",
		"drop_tags": [],
	}
	fixture.reset(arena, arena.framework_room, fixture.build({"d": 100.0, "max_health": 1.0e9}))
	fixture.drive(arena)
	arena.teleport_actor("ranger", arena._arena_rect().get_center())
	var elite = arena.enemies[0]
	var secondary = arena.enemies[1]
	arena.teleport_actor("enemy/%d" % elite.entity_id, arena.player_position + Vector2(20.0, 0.0))
	arena.teleport_actor("enemy/%d" % secondary.entity_id, arena.player_position + Vector2(60.0, 0.0))
	arena.selected_mode = "Auto"
	_start_proxy(arena, arena.framework_resolved_proxy_build)
	arena._update_room_rules_tick()
	var public_snapshot: Dictionary = arena._public_proxy_snapshot()
	var elite_is_publicly_blocked := false
	for visible_enemy: Dictionary in public_snapshot.visible_enemies:
		if int(visible_enemy.get("entity_id", 0)) == elite.entity_id:
			elite_is_publicly_blocked = not bool(visible_enemy.get("targetable", true))
	_expect(arena.elite_barrier_active and elite_is_publicly_blocked, "proxy legality: active elite barrier was not projected as current non-targetable state", failures)
	_expect(not public_snapshot.has("elite_barrier_active")
		and "periodic_barrier" not in str(public_snapshot)
		and "classification_tags" not in str(public_snapshot),
		"proxy legality: hidden barrier identity, classification, or phase leaked into the white snapshot", failures)
	_expect(_cast_target(arena._auto_commands()) == secondary.entity_id, "proxy legality: agent attacked the nearer shielded elite instead of the farther legal target", failures)

	## Opening the barrier does not grant the white core an extra perception sample.
	## It may reacquire only on the next public 30-tick horizon.
	arena.enemies.erase(secondary)
	_start_proxy(arena, arena.framework_resolved_proxy_build)
	arena._update_room_rules_tick()
	_expect(_cast_target(arena._auto_commands()) == 0, "proxy legality: only shielded target still produced an attack", failures)
	fixture.advance_to(arena, 20)
	arena._update_room_rules_tick()
	_expect(not arena.elite_barrier_active and _cast_target(arena._auto_commands()) == 0, "proxy legality: barrier opening leaked an out-of-cadence perception refresh", failures)
	fixture.advance_to(arena, 30)
	_expect(_cast_target(arena._auto_commands()) == elite.entity_id, "proxy legality: next public horizon did not reacquire the opened elite", failures)
	arena.selected_mode = "Manual"


func _test_proxy_resolved_variants_runtime(arena: Node, failures: Array[String]) -> void:
	_configure_enemies(arena)
	arena.selected_mode = "Auto"
	var ordinary = arena.enemies[0]
	var elite = arena.enemies[1]
	arena.teleport_actor("enemy/%d" % ordinary.entity_id, arena.player_position + Vector2(20.0, 0.0))
	arena.teleport_actor("enemy/%d" % elite.entity_id, arena.player_position + Vector2(60.0, 0.0))
	arena.elite_entity_id = elite.entity_id
	var marking_build := _proxy_build("marking_prism", "direct_gait")
	_start_proxy(arena, marking_build)
	var marking_snapshot: Dictionary = arena._public_proxy_snapshot()
	var elite_tags: Array = []
	for enemy_view: Dictionary in marking_snapshot.visible_enemies:
		if int(enemy_view.entity_id) == elite.entity_id:
			elite_tags = (enemy_view.get("classification_tags", []) as Array).duplicate()
	_expect("elite" in elite_tags and _cast_target(arena._auto_commands()) == elite.entity_id,
		"resolved proxy: marking prism did not receive public classification and prioritize the elite", failures)

	arena.teleport_actor("enemy/%d" % ordinary.entity_id, arena.player_position + Vector2(55.0, 0.0))
	arena.enemies.clear()
	arena.enemies.append(ordinary)
	arena.elite_entity_id = 0
	var near_build := _proxy_build("near_enemy_horizon", "distance_keeping_gait", "near")
	var far_build := _proxy_build("near_enemy_horizon", "distance_keeping_gait", "far")
	_start_proxy(arena, near_build)
	var near_commands: Array[Dictionary] = arena._auto_commands()
	var near_hash: String = arena._semantic_state_hash("proxy_variant")
	_start_proxy(arena, far_build)
	var far_commands: Array[Dictionary] = arena._auto_commands()
	var far_hash: String = arena._semantic_state_hash("proxy_variant")
	_expect(not near_commands.is_empty() and String(near_commands[0].kind) == Protocol.KIND_STOP_MOVE,
		"resolved proxy: near distance band did not hold at 55% targeting distance", failures)
	_expect(not far_commands.is_empty() and String(far_commands[0].kind) == Protocol.KIND_MOVE and int(far_commands[0].direction_x_milli) == -1000,
		"resolved proxy: far distance band did not retreat at the same relative distance", failures)
	_expect(not near_hash.is_empty() and near_hash != far_hash,
		"resolved proxy: effective distance setting did not change Main semantic state", failures)
	arena.selected_mode = "Manual"
	arena.framework_resolved_proxy_build = _white_proxy_build()


func _test_proxy_retreat_runtime(arena: Node, failures: Array[String]) -> void:
	arena.embedded_session = true
	arena.framework_active_build = {"skills": ["piercing_arrow", "hunter_mark", "dash"]}
	arena.framework_resolved_proxy_build = _white_proxy_build()
	fixture.reset(arena, arena.framework_room, fixture.build({"d": 100.0, "max_health": 1.0e9, "damage": 1.0}))
	fixture.drive(arena, {"input": true, "enemies": true})
	arena.teleport_actor("ranger", arena._arena_rect().get_center())
	arena.selected_mode = "Auto"
	arena.in_arena = true
	arena.battle_over = false
	_start_proxy(arena, arena.framework_resolved_proxy_build)
	arena.combat_event_stream.reset()
	var target = arena.enemies[0]
	arena.teleport_actor("enemy/%d" % target.entity_id, arena.player_position + Vector2(20.0, 0.0))
	target.health = 1.0e30
	target.maximum_health = target.health
	var start_player: Vector2 = arena.player_position
	var start_target: Vector2 = target.position
	var start_distance: float = start_player.distance_to(start_target)
	var retreat_exit_distance: float = arena.locked_targeting_distance * 0.38
	var public_snapshot: Dictionary = arena._public_proxy_snapshot()
	var public_enemy: Dictionary = public_snapshot.visible_enemies[0]
	_expect(not public_snapshot.has("enemy_tactics") and not public_snapshot.has("room_id") and not public_enemy.has("kind_id") and not public_enemy.has("action_state"), "proxy retreat: runtime exposed hidden enemy or room state", failures)

	var first_displacement := Vector2.ZERO
	var first_trace: Array[String] = []
	var maximum_distance := start_distance
	var saw_retreat := false
	var saw_hold_after_retreat := false
	var hold_streak := 0
	var accepted_retreat_move := false
	var accepted_cast := false
	var observed_bands: Array[String] = []
	for step in 30:
		var before_player: Vector2 = arena.player_position
		arena._simulate_tick()
		var distance: float = arena.player_position.distance_to(target.position)
		maximum_distance = maxf(maximum_distance, distance)
		var proxy_state: Dictionary = arena.proxy_intent_system.decision_state_snapshot()
		var band := String(proxy_state.get("movement_band", ""))
		observed_bands.append(band)
		if step == 0:
			first_displacement = arena.player_position - before_player
			first_trace = arena.proxy_intent_system.trace_snapshot()
		for receipt: Dictionary in arena.last_command_receipts:
			if String(receipt.get("status", "")) != Protocol.STATUS_ACCEPTED:
				continue
			var command: Dictionary = receipt.get("command", {})
			if String(command.get("kind", "")) == Protocol.KIND_MOVE and int(command.get("speed_milli", 0)) == 720:
				accepted_retreat_move = true
			if String(command.get("kind", "")) == Protocol.KIND_CAST and String(command.get("ability_id", "")) == Protocol.ABILITY_PIERCING_ARROW and int(command.get("target_entity_id", 0)) == target.entity_id:
				accepted_cast = true
		if band == "retreat":
			saw_retreat = true
			hold_streak = 0
		elif saw_retreat and band == "hold":
			saw_hold_after_retreat = true
			hold_streak += 1
		else:
			hold_streak = 0
		if saw_hold_after_retreat and hold_streak >= 4:
			break

	var ranger_action_accepted := false
	var ranger_action_impacted := false
	for event: Dictionary in arena.combat_event_stream.snapshot().events:
		if String(event.get("actor_id", "")) != "ranger" or String(event.get("action_id", "")) != Protocol.ABILITY_PIERCING_ARROW:
			continue
		if String(event.get("type", "")) == "action_accepted":
			ranger_action_accepted = true
		elif String(event.get("type", "")) == "action_impact":
			ranger_action_impacted = true
	var away_from_start_target: Vector2 = start_player.direction_to(start_target)
	_expect(first_displacement.dot(away_from_start_target) < 0.0 and "movement:retreat" in first_trace, "proxy retreat: first real Main displacement was not away from the close target", failures)
	_expect(accepted_retreat_move, "proxy retreat: no ordinary accepted speed-720 move receipt was observed", failures)
	_expect(accepted_cast and ranger_action_accepted and ranger_action_impacted, "proxy retreat: shared cast timeline did not accept and impact while range control was active", failures)
	_expect(saw_retreat and saw_hold_after_retreat and maximum_distance >= retreat_exit_distance, "proxy retreat: real distance never crossed the retreat exit band before hold: %s / %.3f" % [str(observed_bands), maximum_distance], failures)
	_expect(hold_streak >= 4, "proxy retreat: retreat-to-hold transition jittered during the four-tick stability window: %s" % str(observed_bands), failures)
	arena.selected_mode = "Manual"


func _test_proxy_target_death_reacquire_state_reset(arena: Node, failures: Array[String]) -> void:
	_configure_enemies(arena, {"damage": 1000000.0})
	fixture.drive(arena, {"input": true, "enemies": true})
	arena.framework_resolved_proxy_build = _white_proxy_build()
	arena.selected_mode = "Auto"
	_start_proxy(arena, arena.framework_resolved_proxy_build)
	var first = arena.enemies[0]
	var second = arena.enemies[1]
	arena.teleport_actor("enemy/%d" % first.entity_id, arena.player_position + Vector2(20.0, 0.0))
	first.health = 1.0
	first.maximum_health = first.health
	arena.teleport_actor("enemy/%d" % second.entity_id, arena.player_position + Vector2(70.0, 0.0))
	second.health = 1.0e30
	second.maximum_health = second.health
	for enemy in [first, second]:
		enemy.action_state = "recovery"
		enemy.action_id = "contact"
		enemy.state_started_tick = 0
		enemy.state_ends_tick = 999999
		enemy.next_action_ready_tick = 999999

	var saw_retreat_on_first := false
	var first_died_through_main := false
	for _tick in 16:
		arena._simulate_tick()
		var proxy_state: Dictionary = arena.proxy_intent_system.decision_state_snapshot()
		if int(proxy_state.get("target_entity_id", 0)) == first.entity_id and String(proxy_state.get("movement_band", "")) == "retreat":
			saw_retreat_on_first = true
		if first not in arena.enemies:
			first_died_through_main = true
			break
	_expect(saw_retreat_on_first, "proxy reacquire: first target never committed retreat movement state", failures)
	_expect(first_died_through_main, "proxy reacquire: real Main piercing-arrow path did not kill the first target", failures)
	if first_died_through_main:
		## A distance between retreat enter and exit distinguishes a reset hold band
		## from an inherited retreat band on the target-missing reacquire tick.
		arena.teleport_actor("enemy/%d" % second.entity_id, arena.player_position + Vector2(30.0, 0.0))
		arena._simulate_tick()
		var proxy_state: Dictionary = arena.proxy_intent_system.decision_state_snapshot()
		_expect(int(proxy_state.get("target_entity_id", 0)) == second.entity_id, "proxy reacquire: target death did not reacquire the remaining enemy through real Main", failures)
		_expect(String(proxy_state.get("movement_band", "")) == "hold", "proxy reacquire: new target inherited the dead target's retreat movement band", failures)
	arena.selected_mode = "Manual"


func _test_dodge_facing_integration(arena: Node, failures: Array[String]) -> void:
	_configure_enemies(arena)
	var start: Vector2 = arena.player_position
	_expect(_dodge(arena, Vector2.UP), "dodge facing: upward dodge was rejected", failures)
	_expect(_player(arena).dodge_direction == Vector2.UP and _player(arena).player_facing == Vector2.UP, "dodge facing: authority and facing did not commit the upward direction together", failures)
	_expect(_player(arena).dodge_remaining_ticks == 5 and _player(arena).dodge_cooldown_ticks == 35, "dodge facing: fixed five-tick duration or 35-tick cooldown changed", failures)
	var previous: Vector2 = start
	for active_tick in Skill.DODGE_DURATION_TICKS:
		if active_tick > 0:
			fixture.step(arena)
		var frame: Dictionary = arena.presentation.animations.ranger_animation.resolve(arena.presentation.animations.ranger_state(arena.gameplay_snapshot()))
		_expect(String(frame.get("action", "")) == "dodge" and String(frame.get("facing", "")) == "north" and String(frame.get("clip", "")) == "ranger.north.dodge", "dodge facing: active tick %d did not resolve through Main state as north dodge" % active_tick, failures)
		var tick_displacement: Vector2 = arena.player_position - previous
		_expect(is_zero_approx(tick_displacement.x) and tick_displacement.y < 0.0, "dodge facing: active tick %d had a non-upward displacement component" % active_tick, failures)
		previous = arena.player_position
	var displacement: Vector2 = arena.player_position - start
	var expected_distance: float = Skill.DODGE_SPEED * arena.SIM_STEP_SECONDS * float(Skill.DODGE_DURATION_TICKS)
	_expect(is_zero_approx(displacement.x) and absf(displacement.y + expected_distance) <= 0.01, "dodge facing: five ticks did not move exclusively upward by the fixed distance", failures)
	fixture.wait_ready(arena, "dodge_cooldown_ticks")
	fixture.step(arena, [fixture.command(arena, "move", 0, Vector2.LEFT)])
	_expect(_dodge(arena, Vector2.ZERO), "dodge facing: directionless dodge was rejected", failures)
	_expect(_player(arena).dodge_direction == Vector2.LEFT and _player(arena).player_facing == Vector2.LEFT, "dodge facing: directionless dodge lost the pre-dodge facing fallback", failures)
	fixture.advance_to(arena, arena.sim_tick + Skill.DODGE_DURATION_TICKS)
	var idle_frame: Dictionary = arena.presentation.animations.ranger_animation.resolve(arena.presentation.animations.ranger_state(arena.gameplay_snapshot()))
	_expect(String(idle_frame.get("action", "")) == "idle" and String(idle_frame.get("facing", "")) == "west", "dodge facing: idle did not retain the last dodge direction", failures)
	fixture.wait_ready(arena, "dodge_cooldown_ticks")
	var damage: Dictionary = arena.player_combat_rules.apply_damage(arena.sim_tick, arena.player_health - 50.0, "fixture/setup", arena.player_position)
	_expect(bool(damage.get("accepted", false)), "dodge facing: health setup damage was rejected", failures)
	_expect(_dodge(arena, Vector2.ZERO) and _player(arena).dodge_direction == Vector2.LEFT and _player(arena).player_facing == Vector2.LEFT, "dodge facing: the next directionless action did not inherit the last dodge direction", failures)
	arena.player_combat_rules.apply_damage(arena.sim_tick, 7.0, "fixture/damage", arena.player_position)
	_expect(is_equal_approx(arena.player_health, 50.0), "dodge facing: active dodge lost its invulnerability", failures)


func _test_dodge_interrupts_arrow(arena: Node, failures: Array[String]) -> void:
	_configure_enemies(arena)
	var target = arena.enemies[0]
	arena.teleport_actor("enemy/%d" % target.entity_id, arena.player_position + Vector2(60.0, 0.0))
	target.health = 1.0e12
	target.maximum_health = target.health
	var health_before: float = target.health
	_expect(_cast_skill_one(arena), "dodge interrupt: arrow windup setup was rejected", failures)
	var active_before: Dictionary = _player(arena).timeline.active
	var impact_tick: int = int(active_before.get("start_tick", arena.sim_tick)) + Timeline.WINDUP_TICKS
	_expect(String(_player(arena).action_phase) == Timeline.PHASE_WINDUP, "dodge interrupt: arrow was not in windup before the dodge", failures)
	_expect(_dodge(arena, Vector2.LEFT), "dodge interrupt: lateral dodge during windup was rejected", failures)
	var interrupt_count := 0
	for event: Dictionary in arena.combat_event_stream.snapshot().events:
		if String(event.get("type", "")) == "action_interrupted" and String(event.get("action_id", "")) == "piercing_arrow":
			interrupt_count += 1
	_expect(interrupt_count == 1 and _player(arena).timeline.active.is_empty(), "dodge interrupt: timeline did not project exactly one interruption and clear the active arrow", failures)
	var dodge_frame: Dictionary = arena.presentation.animations.ranger_animation.resolve(arena.presentation.animations.ranger_state(arena.gameplay_snapshot()))
	_expect(_player(arena).player_facing == Vector2.LEFT and String(dodge_frame.get("action", "")) == "dodge" and String(dodge_frame.get("facing", "")) == "west" and String(dodge_frame.get("clip", "")) == "ranger.west.dodge", "dodge interrupt: facing and dodge animation did not switch sideways immediately", failures)
	fixture.advance_to(arena, impact_tick + 1)
	var impact_count := 0
	for event: Dictionary in arena.combat_event_stream.snapshot().events:
		if String(event.get("type", "")) == "action_impact" and String(event.get("action_id", "")) == "piercing_arrow":
			impact_count += 1
	_expect(impact_count == 0 and is_equal_approx(target.health, health_before), "dodge interrupt: interrupted arrow still impacted after its original impact tick", failures)


func _test_mobility_boundary_buffer(arena: Node, failures: Array[String]) -> void:
	_configure_enemies(arena)
	var target = arena.enemies[0]
	arena.teleport_actor("enemy/%d" % target.entity_id, arena.player_position + Vector2(60.0, 0.0))
	_expect(_cast_skill_one(arena), "mobility buffer: recovery setup arrow was rejected", failures)
	fixture.advance_to(arena, arena.sim_tick + Timeline.WINDUP_TICKS + 1)
	_expect(_player(arena).action_phase == Timeline.PHASE_RECOVERY, "mobility buffer: arrow did not enter recovery", failures)
	_expect(_dodge(arena, Vector2.LEFT), "mobility buffer: dodge during arrow recovery was lost instead of interrupting immediately", failures)
	_configure_enemies(arena)
	_expect(_dash(arena, Vector2.RIGHT), "mobility buffer: real dash setup failed", failures)
	fixture.advance_to(arena, arena.sim_tick + Skill.DASH_DURATION_TICKS - 2)
	var buffered := fixture.cast(arena, "dodge")
	_expect(_player(arena).dodge_remaining_ticks == 0 and String(buffered.get("reason", "")) == "mobility_buffered", "mobility buffer: dodge bypassed the active dash exclusion", failures)
	fixture.step(arena)
	_expect(_player(arena).dodge_remaining_ticks > 0 and _player(arena).player_facing == Vector2.RIGHT, "mobility buffer: dodge pressed near dash end was completely lost", failures)
	_configure_enemies(arena)


func _test_dash(arena: Node, failures: Array[String]) -> void:
	_configure_enemies(arena)
	var start: Vector2 = arena.player_position
	_expect(_dash(arena, Vector2.UP) and _player(arena).dash_direction == Vector2.UP, "dash did not use current movement input", failures)
	_expect(not bool(arena.request_player_cast("dash", 0, Vector2.RIGHT).get("accepted", false)), "dash repeated while already active", failures)
	fixture.advance_to(arena, arena.sim_tick + Skill.DASH_DURATION_TICKS - 1)
	_expect(is_equal_approx(arena.player_position.distance_to(start), Skill.DASH_TOTAL_DISTANCE), "dash total fixed-tick displacement is wrong", failures)
	fixture.step(arena)
	_expect(not bool(arena.request_player_cast("dash", 0, Vector2.LEFT).get("accepted", false)), "dash ignored independent cooldown", failures)
	fixture.wait_ready(arena, "dash_cooldown_ticks")
	fixture.step(arena, [fixture.command(arena, "move", 0, Vector2.LEFT)])
	arena.player_combat_rules.apply_damage(arena.sim_tick, arena.player_health - 50.0, "fixture/setup", arena.player_position)
	_expect(_dash(arena, Vector2.ZERO) and _player(arena).dash_direction == Vector2.LEFT, "dash did not fall back to player facing", failures)
	arena.player_combat_rules.apply_damage(arena.sim_tick, 7.0, "fixture/damage", arena.player_position)
	_expect(is_equal_approx(arena.player_health, 43.0), "dash incorrectly granted dodge immunity", failures)


func _test_input_map_movement(arena: Node, failures: Array[String]) -> void:
	arena.selected_mode = "Manual"
	Input.action_press("move_right")
	var commands: Array[Dictionary] = arena.input_adapter.collect_commands(arena.gameplay_snapshot())
	Input.action_release("move_right")
	var found_move := false
	for command in commands:
		if String(command.get("kind", "")) == "move" and int(command.get("direction_x_milli", 0)) >= 990:
			found_move = true
	_expect(found_move, "manual movement did not consume the shared InputMap action", failures)


func _test_manual_pointer_exact_selection(arena: Node, failures: Array[String]) -> void:
	_configure_enemies(arena)
	var left = arena.enemies[0]
	var right = arena.enemies[1]
	arena.teleport_actor("enemy/%d" % left.entity_id, arena.player_position + Vector2(-80.0, 0.0))
	arena.teleport_actor("enemy/%d" % right.entity_id, arena.player_position + Vector2(80.0, 0.0))
	for target in [left, right]:
		var anchor: Vector2 = target.position + Vector2(0.0, -22.0)
		arena.input_adapter.capture_attack_event(_mouse_attack_event(_gameplay_to_screen(arena, anchor), true), false, arena.gameplay_snapshot())
		var command: Dictionary = _piercing_cast(arena.input_adapter.collect_commands(arena.gameplay_snapshot()))
		var expected_x := -1000 if target == left else 1000
		_expect(int(command.get("target_entity_id", 0)) == target.entity_id, "pointer exact selection: click chose the wrong left/right entity", failures)
		_expect(int(command.get("direction_x_milli", 0)) == expected_x and int(command.get("direction_y_milli", 1)) == 0, "pointer exact selection: cast aimed at the elevated click anchor instead of target feet", failures)
		_expect(arena.input_adapter.manual_pointer_target_anchor == anchor and is_equal_approx(arena.input_adapter.manual_pointer_target_radius, 34.0), "pointer exact selection: normal enemy anchor/radius changed", failures)
		arena.input_adapter.capture_attack_event(_mouse_attack_event(_gameplay_to_screen(arena, anchor), false), false, arena.gameplay_snapshot())
		arena.release_manual_controls()


func _test_manual_pointer_blank_and_quick_edge(arena: Node, failures: Array[String]) -> void:
	_configure_enemies(arena)
	var blank: Vector2 = arena.player_position + Vector2(0.0, 90.0)
	var blank_screen: Vector2 = _gameplay_to_screen(arena, blank)
	arena.input_adapter.capture_attack_event(_mouse_attack_event(blank_screen, true), false, arena.gameplay_snapshot())
	_expect(_piercing_cast(arena.input_adapter.collect_commands(arena.gameplay_snapshot())).is_empty(), "pointer blank: empty space fell back to another enemy", failures)
	_expect(arena.input_adapter.manual_pointer_target_entity_id == 0 and arena.input_adapter.manual_pointer_status == arena.input_adapter.POINTER_STATUS_NO_TARGET, "pointer blank: empty click retained a target lock", failures)
	arena.input_adapter.capture_attack_event(_mouse_attack_event(blank_screen, false), false, arena.gameplay_snapshot())

	_configure_enemies(arena)
	var target = arena.enemies[0]
	arena.teleport_actor("enemy/%d" % target.entity_id, arena.player_position + Vector2(70.0, 0.0))
	var target_screen := _gameplay_to_screen(arena, target.position + Vector2(0.0, -22.0))
	arena.input_adapter.capture_attack_event(_mouse_attack_event(target_screen, true), false, arena.gameplay_snapshot())
	arena.input_adapter.capture_attack_event(_mouse_attack_event(target_screen, false), false, arena.gameplay_snapshot())
	_expect(arena.input_adapter.manual_pointer_target_entity_id == 0 and arena.command_source.attack_requested_source == arena.ATTACK_SOURCE_POINTER, "pointer quick edge: release cleared the queued press edge", failures)
	var quick_command: Dictionary = _piercing_cast(arena.input_adapter.collect_commands(arena.gameplay_snapshot()))
	_expect(int(quick_command.get("target_entity_id", 0)) == target.entity_id, "pointer quick edge: press/release before fixed tick lost its cast", failures)


func _test_manual_pointer_lock_lifecycle(arena: Node, failures: Array[String]) -> void:
	_configure_enemies(arena)
	var locked = arena.enemies[0]
	var other = arena.enemies[1]
	arena.teleport_actor("enemy/%d" % locked.entity_id, arena.player_position + Vector2(160.0, 0.0))
	arena.teleport_actor("enemy/%d" % other.entity_id, arena.player_position + Vector2(30.0, 70.0))
	var locked_screen := _gameplay_to_screen(arena, locked.position + Vector2(0.0, -22.0))
	arena.input_adapter.capture_attack_event(_mouse_attack_event(locked_screen, true), false, arena.gameplay_snapshot())
	_expect(arena.input_adapter.manual_pointer_target_entity_id == locked.entity_id and arena.input_adapter.manual_pointer_status == arena.input_adapter.POINTER_STATUS_OUT_OF_RANGE, "pointer range: out-of-range click did not retain the entity lock", failures)
	_expect(_piercing_cast(arena.input_adapter.collect_commands(arena.gameplay_snapshot())).is_empty(), "pointer range: out-of-range lock emitted a cast", failures)
	arena.teleport_actor("ranger", locked.position + Vector2(-80.0, 0.0))
	var entered_command: Dictionary = _piercing_cast(arena.input_adapter.collect_commands(arena.gameplay_snapshot()))
	_expect(int(entered_command.get("target_entity_id", 0)) == locked.entity_id, "pointer range: entering range while held did not fire at the original entity", failures)
	arena.input_adapter.capture_attack_event(_mouse_attack_event(locked_screen, false), false, arena.gameplay_snapshot())
	_expect(arena.input_adapter.manual_pointer_target_entity_id == 0 and arena.input_adapter.manual_pointer_status == arena.input_adapter.POINTER_STATUS_NONE, "pointer release: lock state was not cleared", failures)

	_configure_enemies(arena)
	locked = arena.enemies[0]
	other = arena.enemies[1]
	arena.teleport_actor("enemy/%d" % locked.entity_id, arena.player_position + Vector2(80.0, 0.0))
	arena.teleport_actor("enemy/%d" % other.entity_id, arena.player_position + Vector2(20.0, 0.0))
	locked_screen = _gameplay_to_screen(arena, locked.position + Vector2(0.0, -22.0))
	arena.input_adapter.capture_attack_event(_mouse_attack_event(locked_screen, true), false, arena.gameplay_snapshot())
	locked.health = 0.0
	_expect(_piercing_cast(arena.input_adapter.collect_commands(arena.gameplay_snapshot())).is_empty(), "pointer death: dead lock switched to the nearer living enemy", failures)
	_expect(arena.input_adapter.manual_pointer_target_entity_id == locked.entity_id and arena.input_adapter.manual_pointer_status == arena.input_adapter.POINTER_STATUS_LOST, "pointer death: original entity identity/status was not retained as lost", failures)
	_expect(_piercing_cast(arena.input_adapter.collect_commands(arena.gameplay_snapshot())).is_empty(), "pointer death: held lost lock later fell back to another enemy", failures)
	arena.input_adapter.capture_attack_event(_mouse_attack_event(locked_screen, false), false, arena.gameplay_snapshot())


func _test_assisted_and_pointer_arbitration(arena: Node, failures: Array[String]) -> void:
	_configure_enemies(arena)
	var nearest = arena.enemies[0]
	var marked = arena.enemies[1]
	arena.teleport_actor("enemy/%d" % nearest.entity_id, arena.player_position + Vector2(25.0, 0.0))
	arena.teleport_actor("enemy/%d" % marked.entity_id, arena.player_position + Vector2(80.0, 0.0))
	_expect(_cast(arena, "hunter_mark", marked.entity_id), "assisted Space: real mark setup failed", failures)
	arena.input_adapter.capture_attack_event(_attack_key_event(true), true, arena.gameplay_snapshot())
	_expect(_cast_target(arena.input_adapter.collect_commands(arena.gameplay_snapshot())) == marked.entity_id, "assisted Space: HUD hover or nearest target overrode the live mark", failures)
	arena.input_adapter.capture_attack_event(_attack_key_event(false), true, arena.gameplay_snapshot())

	arena.release_manual_controls()
	fixture.advance_to(arena, int(_player(arena).hunter_mark_expires_tick))
	arena.input_adapter.capture_attack_event(_attack_key_event(true), true, arena.gameplay_snapshot())
	_expect(_cast_target(arena.input_adapter.collect_commands(arena.gameplay_snapshot())) == nearest.entity_id, "assisted Space: nearest-target fallback regressed under HUD hover", failures)
	arena.input_adapter.capture_attack_event(_attack_key_event(false), true, arena.gameplay_snapshot())

	arena.release_manual_controls()
	var nearest_screen := _gameplay_to_screen(arena, nearest.position + Vector2(0.0, -22.0))
	arena.input_adapter.capture_attack_event(_mouse_attack_event(nearest_screen, true), true, arena.gameplay_snapshot())
	_expect(_piercing_cast(arena.input_adapter.collect_commands(arena.gameplay_snapshot())).is_empty() and arena.input_adapter.manual_pointer_target_entity_id == 0, "HUD-owned pointer press started a world attack", failures)
	arena.input_adapter.capture_attack_event(_mouse_attack_event(nearest_screen, false), true, arena.gameplay_snapshot())

	arena.release_manual_controls()
	var pointer_target = marked
	var pointer_screen := _gameplay_to_screen(arena, pointer_target.position + Vector2(0.0, -22.0))
	arena.input_adapter.capture_attack_event(_mouse_attack_event(pointer_screen, true), false, arena.gameplay_snapshot())
	arena.input_adapter.capture_attack_event(_attack_key_event(true), false, arena.gameplay_snapshot())
	_expect(_cast_target(arena.input_adapter.collect_commands(arena.gameplay_snapshot())) == pointer_target.entity_id, "pointer/assisted arbitration: Space overrode the held pointer entity", failures)
	arena.input_adapter.capture_attack_event(_attack_key_event(false), false, arena.gameplay_snapshot())
	arena.input_adapter.capture_attack_event(_mouse_attack_event(pointer_screen, false), false, arena.gameplay_snapshot())


func _test_auto_ignores_manual_device_state(arena: Node, failures: Array[String]) -> void:
	_configure_enemies(arena)
	arena.selected_mode = "Auto"
	var input_before: Dictionary = arena.input_adapter.manual_combat_input.snapshot()
	var hash_before: String = arena._semantic_state_hash("auto_pointer_ignored")
	arena.input_adapter.capture_attack_event(_mouse_attack_event(Vector2(320.0, 240.0), true), false, arena.gameplay_snapshot())
	var input_after: Dictionary = arena.input_adapter.manual_combat_input.snapshot()
	var hash_after: String = arena._semantic_state_hash("auto_pointer_ignored")
	_expect(input_after == input_before, "auto input boundary: pointer device state entered ManualCombatInput", failures)
	_expect(hash_after == hash_before, "auto input boundary: ignored pointer activity changed the deterministic hash", failures)
	arena.input_adapter.capture_attack_event(_mouse_attack_event(Vector2(320.0, 240.0), false), false, arena.gameplay_snapshot())
	arena.selected_mode = "Manual"


func _test_pointer_camera_round_trip(arena: Node, failures: Array[String]) -> void:
	var arena_rect: Rect2 = arena._walkable_geometry(14.0).bounds
	var cases := [
		{"player": arena_rect.get_center(), "offset": Vector2(70.0, 0.0), "label": "center"},
		{"player": arena_rect.position + Vector2(8.0, 8.0), "offset": Vector2(60.0, 40.0), "label": "top_left_clamp"},
		{"player": arena_rect.end - Vector2(8.0, 8.0), "offset": Vector2(-60.0, -40.0), "label": "bottom_right_clamp"},
	]
	for camera_case: Dictionary in cases:
		_configure_enemies(arena)
		arena.teleport_actor("ranger", camera_case.player)
		var target = arena.enemies[0]
		arena.teleport_actor("enemy/%d" % target.entity_id, arena.player_position + Vector2(camera_case.offset))
		arena.enemies[1].health = 0.0
		var anchor: Vector2 = target.position + Vector2(0.0, -22.0)
		var screen: Vector2 = _gameplay_to_screen(arena, anchor)
		var round_trip: Vector2 = arena.presentation.world_view.screen_to_gameplay(screen)
		_expect(round_trip.distance_to(anchor) <= 0.001, "camera %s: screen/gameplay round trip drifted" % String(camera_case.label), failures)
		arena.input_adapter.capture_attack_event(_mouse_attack_event(screen, true), false, arena.gameplay_snapshot())
		_expect(_cast_target(arena.input_adapter.collect_commands(arena.gameplay_snapshot())) == target.entity_id, "camera %s: transformed click selected the wrong entity" % String(camera_case.label), failures)
		arena.input_adapter.capture_attack_event(_mouse_attack_event(screen, false), false, arena.gameplay_snapshot())


func _test_pointer_command_protocol_boundary(arena: Node, failures: Array[String]) -> void:
	_configure_enemies(arena)
	var target = arena.enemies[0]
	arena.teleport_actor("enemy/%d" % target.entity_id, arena.player_position + Vector2(60.0, 45.0))
	var screen := _gameplay_to_screen(arena, target.position + Vector2(0.0, -22.0))
	arena.input_adapter.capture_attack_event(_mouse_attack_event(screen, true), false, arena.gameplay_snapshot())
	var command: Dictionary = _piercing_cast(arena.input_adapter.collect_commands(arena.gameplay_snapshot()))
	var receipt: Dictionary = Protocol.validate(command, arena.sim_tick, [Protocol.ABILITY_PIERCING_ARROW])
	_expect(String(command.get("kind", "")) == Protocol.KIND_CAST and String(command.get("ability_id", "")) == Protocol.ABILITY_PIERCING_ARROW, "pointer protocol: final command was not a normal piercing_arrow cast", failures)
	_expect(int(command.get("target_entity_id", 0)) == target.entity_id and command.has("direction_x_milli") and command.has("direction_y_milli"), "pointer protocol: target or quantized direction was missing", failures)
	_expect(String(receipt.get("status", "")) == Protocol.STATUS_ACCEPTED, "pointer protocol: generated cast failed CombatCommandProtocol validation", failures)
	for forbidden in ["source", "attack_source", "input_source", "pointer", "pointer_gameplay", "mouse", "screen_position"]:
		_expect(not command.has(forbidden), "pointer protocol: input metadata leaked into final command field %s" % forbidden, failures)
	arena.input_adapter.capture_attack_event(_mouse_attack_event(screen, false), false, arena.gameplay_snapshot())


func _test_held_attack_repeats_without_buffer_churn(arena: Node, failures: Array[String]) -> void:
	_configure_enemies(arena)
	fixture.drive(arena, {"input": true})
	arena.in_arena = true
	arena.combat_event_stream.reset()
	arena.input_adapter.manual_combat_input.reset()
	arena.command_source.attack_requested = false
	for enemy in arena.enemies:
		arena.teleport_actor("enemy/%d" % enemy.entity_id, arena.player_position + Vector2(60.0 + float(enemy.entity_id), 0.0))
		enemy.health = 1.0e30
		enemy.maximum_health = enemy.health

	## Cursor hover must not affect Space. One physical press should start now, then
	## occupy exactly one future buffer slot at each 13-tick cooldown boundary.
	arena.input_adapter.capture_attack_event(_attack_key_event(true), true, arena.gameplay_snapshot())
	_expect(arena.command_source.attack_requested, "held attack: Space over the HUD did not queue the initial edge", failures)
	for _tick in 30:
		arena._simulate_tick()
	var starts: Array[int] = []
	for event: Dictionary in arena.combat_event_stream.snapshot().events:
		if String(event.get("type", "")) == "action_accepted" and String(event.get("actor_id", "")) == "ranger":
			starts.append(int(event.get("tick", -1)))
	_expect(starts == [1, 14, 27], "held attack: one hold produced the wrong fixed-tick starts %s" % str(starts), failures)
	_expect(int(_player(arena).timeline.next_request_id) == 4, "held attack: the held source replaced the same buffer repeatedly", failures)

	arena.input_adapter.capture_attack_event(_attack_key_event(false), true, arena.gameplay_snapshot())
	for _tick in 20:
		arena._simulate_tick()
	var starts_after_release := 0
	for event: Dictionary in arena.combat_event_stream.snapshot().events:
		if String(event.get("type", "")) == "action_accepted" and String(event.get("actor_id", "")) == "ranger":
			starts_after_release += 1
	_expect(starts_after_release == 3, "held attack: release allowed another automatic cast", failures)


func _test_hash_sensitivity(arena: Node, failures: Array[String]) -> void:
	_configure_enemies(arena)
	var baseline: String = arena._semantic_state_hash("skills")
	arena.input_adapter.manual_pointer_gameplay = Vector2(11.0, 22.0)
	arena.command_source.attack_requested_pointer_gameplay = Vector2(33.0, 44.0)
	arena.input_adapter.manual_pointer_target_anchor = Vector2(55.0, 66.0)
	arena.input_adapter.manual_pointer_target_radius = 77.0
	var geometry_only: String = arena._semantic_state_hash("skills")
	_expect(geometry_only == baseline, "semantic hash includes pointer presentation geometry that cannot change a command", failures)
	arena.enemies.reverse()
	var reordered: String = arena._semantic_state_hash("skills")
	arena.enemies.reverse()
	_expect(reordered == baseline, "semantic hash depends on incidental enemy array order", failures)
	_expect(_cast(arena, "hunter_mark"), "semantic hash: real mark setup failed", failures)
	var mark_hash: String = arena._semantic_state_hash("skills")
	_expect(_dash(arena, Vector2.UP), "semantic hash: real dash setup failed", failures)
	var dash_hash: String = arena._semantic_state_hash("skills")
	fixture.advance_to(arena, arena.sim_tick + Skill.DASH_DURATION_TICKS - 2)
	fixture.cast(arena, "dodge", 0, Vector2.RIGHT)
	var mobility_buffer_hash: String = arena._semantic_state_hash("skills")
	# Same tick/position/timers before and after public input release isolates
	# the buffer's own contribution to the hash.
	var released: Dictionary = arena.player_combat_rules.release_input(arena.sim_tick)
	var released_hash: String = arena._semantic_state_hash("skills")
	_expect(not baseline.is_empty() and baseline != mark_hash and mark_hash != dash_hash and dash_hash != mobility_buffer_hash and released.get("cleared", false) and mobility_buffer_hash != released_hash, "semantic hash is not sensitive to mark/dash/buffer authority state", failures)


func _test_arena_reset(arena: Node, failures: Array[String]) -> void:
	_configure_enemies(arena)
	_expect(_cast(arena, "hunter_mark") and _dash(arena, Vector2.UP), "enter arena: live mark/dash setup failed", failures)
	fixture.advance_to(arena, arena.sim_tick + Skill.DASH_DURATION_TICKS - 2)
	fixture.cast(arena, "dodge")
	var before := _player(arena)
	_expect(before.marked_entity_id > 0 and before.hunter_mark_cooldown_ticks > 0 and before.dash_remaining_ticks > 0 and before.dash_cooldown_ticks > 0 and not before.mobility_input_buffer.is_empty(), "enter arena: reset fixture did not contain real skill state", failures)
	arena.start_room()
	var after := _player(arena)
	_expect(arena.in_arena and after.marked_entity_id == 0 and after.hunter_mark_expires_tick == 0 and after.hunter_mark_cooldown_ticks == 0 and after.dash_remaining_ticks == 0 and after.dash_cooldown_ticks == 0 and after.mobility_input_buffer.is_empty(), "enter arena did not reset skill authority state", failures)


func _configure_enemies(arena: Node, overrides: Dictionary = {}, skills: Array = ["piercing_arrow", "hunter_mark", "dash"]) -> void:
	_release_input_actions()
	var parameters := {"d": 100.0, "max_health": 1.0e9}
	parameters.merge(overrides, true)
	fixture.reset(arena, _skill_room(), fixture.build(parameters), skills)
	arena.teleport_actor("ranger", arena._arena_rect().get_center())
	fixture.drive(arena)
	for index in arena.enemies.size():
		arena.teleport_actor("enemy/%d" % arena.enemies[index].entity_id, arena.player_position + Vector2(60.0 + index * 30.0, 0.0))


func _cast_and_resolve_arrow(arena: Node) -> bool:
	fixture.wait_ready(arena)
	if not _cast_skill_one(arena):
		return false
	fixture.advance_to(arena, arena.sim_tick + Timeline.WINDUP_TICKS)
	_advance_arrow_until_resolved(arena)
	return true


func _start_frozen_arrow(arena: Node, target: Variant, aim: Vector2) -> bool:
	return bool(fixture.cast(arena, "piercing_arrow", target.entity_id, aim).get("accepted", false))


func _advance_arrow_until_resolved(arena: Node, maximum_ticks: int = 120) -> void:
	fixture.resolve_projectiles(arena, maximum_ticks)


func _cast_target(commands: Array[Dictionary]) -> int:
	for command: Dictionary in commands:
		if String(command.get("kind", "")) == Protocol.KIND_CAST and String(command.get("ability_id", "")) == Protocol.ABILITY_PIERCING_ARROW:
			return int(command.get("target_entity_id", 0))
	return 0


func _cast_has_aim(commands: Array[Dictionary]) -> bool:
	for command: Dictionary in commands:
		if String(command.get("kind", "")) == Protocol.KIND_CAST and String(command.get("ability_id", "")) == Protocol.ABILITY_PIERCING_ARROW:
			return command.has("direction_x_milli") and command.has("direction_y_milli")
	return false


func _piercing_cast(commands: Array[Dictionary]) -> Dictionary:
	for command: Dictionary in commands:
		if String(command.get("kind", "")) == Protocol.KIND_CAST and String(command.get("ability_id", "")) == Protocol.ABILITY_PIERCING_ARROW:
			return command
	return {}


func _gameplay_to_screen(arena: Node, gameplay_point: Vector2) -> Vector2:
	arena.presentation.world_view.begin_frame(Rect2(Vector2.ZERO, arena.get_viewport_rect().size), arena.player_position, arena._arena_rect())
	return arena.presentation.world_view.gameplay_to_screen(gameplay_point)


func _mouse_attack_event(position: Vector2, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = position
	event.global_position = position
	event.pressed = pressed
	return event


func _attack_key_event(pressed: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_SPACE
	event.pressed = pressed
	return event


func _release_input_actions() -> void:
	for action in [&"move_left", &"move_right", &"move_up", &"move_down", &"attack", &"dodge", &"skill_2", &"skill_3"]:
		Input.action_release(action)


func _white_proxy_build() -> Dictionary:
	return _proxy_build("near_enemy_horizon", "direct_gait")


func _start_proxy(arena: Node, build: Dictionary) -> void:
	arena.framework_resolved_proxy_build = build
	var started: Dictionary = arena.proxy_intent_system.begin_contract(build)
	if not bool(started.get("ok", false)):
		push_error("proxy test setup failed: %s" % String(started.get("error", "unknown")))
	arena.command_sequence = 0


func _proxy_build(perception_id: String, movement_id: String, distance_band: String = "") -> Dictionary:
	var registry = ContentRegistryScript.new()
	if not registry.load_all().is_empty():
		return {}
	var raw := {
		"cores": [perception_id, movement_id, "single_key_execution", "short_trace_memory"],
	}
	if movement_id == "distance_keeping_gait" and not distance_band.is_empty():
		raw["settings"] = {"distance_keeping_gait": {"distance_band": distance_band}}
	var compiled: Dictionary = ProxyBuildScript.compile(raw, registry.cores)
	return (compiled.get("value", {}) as Dictionary).duplicate(true) if bool(compiled.get("ok", false)) else {}


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)


func _skill_room() -> Dictionary:
	return {"room_id": "test.ranger.skills", "layout_id": "rectangle_arena", "objective_id": "clear", "hazard_ids": [], "enemy_ids": ["melee_pursuer", "fan_ranged"], "elite_rule_ids": [], "boss_id": "", "drop_tags": []}


func _player(arena: Node) -> Dictionary:
	return fixture.player(arena)


func _cast(arena: Node, ability: String, target_id: int = 0) -> bool:
	return bool(arena.request_player_cast(ability, target_id).get("accepted", false))


func _cast_skill_one(arena: Node) -> bool:
	var target = arena._preferred_skill_one_target()
	return target != null and bool(fixture.cast(arena, "piercing_arrow", target.entity_id).get("accepted", false))


func _dash(arena: Node, direction: Vector2) -> bool:
	return bool(fixture.cast(arena, "dash", 0, direction).get("accepted", false))


func _dodge(arena: Node, direction: Vector2) -> bool:
	return bool(fixture.cast(arena, "dodge", 0, direction).get("accepted", false))
