extends SceneTree

const CombatSystemScript := preload("res://src/systems/combat_system.gd")
const CombatEventStreamScript := preload("res://src/systems/combat_event_stream.gd")
const CombatEnemyStateScript := preload("res://src/runtime/world/combat_enemy_state.gd")
const CombatArrowProjectileScript := preload("res://src/runtime/world/combat_arrow_projectile.gd")
const ManualAimResolverScript := preload("res://src/systems/manual_aim_resolver.gd")
const RoomPortScript := preload("res://tests/helpers/callable_combat_system_room_port.gd")
const Assert := preload("res://tests/helpers/assert.gd")

class PlayerRulePortStub extends RefCounted:
	var critical_bonus_generations := 2
	var critical_consumed := false
	var critical_calls := 0
	var retained_ratio := 0.5
	var retain_calls := 0
	var take_calls := 0
	var retained_aggregate: BigValue = BigValue.from_float(0.0)
	var retained_ordinary := 0.0

	func consume_first_critical_bonus() -> int:
		critical_calls += 1
		if critical_consumed:
			return 0
		critical_consumed = true
		return critical_bonus_generations

	func retain_missed_arrow(aggregate: BigValue, ordinary: float) -> void:
		retain_calls += 1
		retained_aggregate = retained_aggregate.add(aggregate.multiply(BigValue.from_float(retained_ratio)))
		retained_ordinary += ordinary * retained_ratio

	func take_retained_arrow() -> Dictionary:
		take_calls += 1
		var result := {"aggregate": retained_aggregate.duplicate_value(), "ordinary": retained_ordinary}
		retained_aggregate = BigValue.from_float(0.0)
		retained_ordinary = 0.0
		return result

var enemy
var failures: Array[String] = []
var current_model_state := "normal"
var blocked_port_result: Variant = false
var blocked_port_calls := 0


func _initialize() -> void:
	var system = CombatSystemScript.new()
	var player_rule_port := PlayerRulePortStub.new()
	var feedback = preload("res://src/presentation/combat_feedback_controller.gd").new()
	system.impact_trace_requested.connect(feedback.add_impact_traces)
	enemy = CombatEnemyStateScript.new(Vector2(100.0, 22.0), 100.0, false, 1, "melee_pursuer")
	var stream = CombatEventStreamScript.new()
	var configured: Dictionary = _bind(system, {
		"player_rule_port": player_rule_port,
		"target_by_id": Callable(self, "_target_by_id"),
		"aim_candidate": Callable(self, "_aim_candidate"),
		"current_model": Callable(self, "_current_model"),
		"target_blocked": Callable(self, "_target_blocked"),
		"remove_target": Callable(self, "_remove_target"),
	})
	_expect(bool(configured.get("ok", false)), "combat system: callback contract was rejected")
	_expect(system.reset_room(BigValue.from_power10(12.0)).ok, "combat system: room reset rejected")
	_test_missing_player_rule_port()
	system.set_context(
		1,
		Vector2.ZERO,
		Vector2.RIGHT,
		10.0,
		225.0,
		3000.0,
		0,
		{},
		stream,
		ManualAimResolverScript.new(),
		[enemy]
	)
	system.attack_origins[7] = {"release_offset": Vector2.ZERO, "direction": Vector2.RIGHT}
	system.resolve_piercing_arrow({"action_instance_id": 7, "tick": 1, "target_entity_id": 1, "aim_direction_milli": {"x": 1000, "y": 0}})
	_expect(system.shots == 1 and system.projectiles.size() == 1, "combat system: release did not create one authoritative projectile")
	system.tick = 2
	system.advance_projectiles_tick()
	_expect(system.arrow_hits == 1 and system.projectiles.is_empty(), "combat system: swept flight did not resolve and retire the projectile")
	_expect(is_equal_approx(enemy.health, 90.0), "combat system: contact damage changed outside the projectile authority")
	_expect(feedback.traces.size() == 2, "combat system: contact did not create presentation-only impact traces")
	_expect(stream.snapshot().events.any(func(event: Dictionary) -> bool: return String(event.get("type", "")) == "damage_applied"), "combat system: damage event was not published")
	_test_player_rule_port_authority(system, player_rule_port, stream)
	_test_strict_blocked_port()
	_test_versioned_query_profiles()

	feedback.free()
	if failures.is_empty():
		print("PASS test_combat_system.gd")
		quit(0)
		return
	for failure: String in failures:
		printerr("- %s" % failure)
	quit(1)


func _target_by_id(entity_id: int):
	return enemy if entity_id == enemy.entity_id else null


func _aim_candidate(target) -> Dictionary:
	return {"entity_id": target.entity_id, "kind_id": target.kind_id, "position": target.position, "health": target.health, "is_boss": target.is_boss}


func _current_model() -> Dictionary:
	return {"state": current_model_state, "total_events": BigValue.from_float(1.0), "total_events_float": 1.0, "g": 1}


func _target_blocked(_target) -> bool:
	return false


func _bind(system: CombatSystem, callbacks: Dictionary) -> Dictionary:
	var port := RoomPortScript.new()
	var prepared: Dictionary = port.configure(callbacks)
	if not bool(prepared.get("ok", false)):
		return prepared
	var profile := String(callbacks.get("query_profile", CombatSystemScript.QUERY_PROFILE_MULTIPART_V2))
	return system.bind_room(port, profile)


func _remove_target(_target) -> void:
	pass


func _test_missing_player_rule_port() -> void:
	var system = CombatSystemScript.new()
	var result: Dictionary = _bind(system, {})
	_expect(not bool(result.get("ok", true)) and String(result.get("error", "")) == "player_rule_port_unavailable", "combat system: missing player rule port silently configured")


func _test_player_rule_port_authority(system, player_rule_port: PlayerRulePortStub, stream) -> void:
	current_model_state = "critical"
	var context_enemies: Array[CombatEnemyState] = [enemy as CombatEnemyState]
	system.set_context(
		3,
		Vector2.ZERO,
		Vector2.RIGHT,
		10.0,
		225.0,
		3000.0,
		0,
		{"expiry_payload_retention": 0.5},
		stream,
		ManualAimResolverScript.new(),
		context_enemies
	)
	system.attack_origins[8] = {"release_offset": Vector2.ZERO, "direction": Vector2.RIGHT}
	system.resolve_piercing_arrow({"action_instance_id": 8, "tick": 3, "target_entity_id": 1, "aim_direction_milli": {"x": 1000, "y": 0}})
	var first_critical: CombatArrowProjectile = system.projectiles.back()
	_expect(first_critical.event_count.compare(BigValue.from_float(3.0)) == 0, "combat system: first critical did not consume the domain bonus")
	system.attack_origins[9] = {"release_offset": Vector2.ZERO, "direction": Vector2.RIGHT}
	system.resolve_piercing_arrow({"action_instance_id": 9, "tick": 3, "target_entity_id": 1, "aim_direction_milli": {"x": 1000, "y": 0}})
	var second_critical: CombatArrowProjectile = system.projectiles.back()
	_expect(second_critical.event_count.compare(BigValue.from_float(1.0)) == 0 and player_rule_port.critical_calls == 2, "combat system: repeated critical consumed the bonus more than once")
	system.projectiles.clear()
	current_model_state = "normal"
	var take_calls_before := player_rule_port.take_calls
	var missed := CombatArrowProjectileScript.new(10, 1, 4, Vector2.ZERO, Vector2.RIGHT, 225.0, 3000.0, BigValue.from_float(40.0), 20.0, BigValue.from_float(1.0), 10.0)
	system.tick = 4
	system.resolve_projectile_miss(missed)
	_expect(player_rule_port.retain_calls == 1 and player_rule_port.retained_aggregate.compare(BigValue.from_float(20.0)) == 0 and is_equal_approx(player_rule_port.retained_ordinary, 10.0), "combat system: missed payload did not belong to the player domain")
	var hit := CombatArrowProjectileScript.new(11, 1, 5, Vector2.ZERO, Vector2.RIGHT, 225.0, 3000.0, BigValue.from_float(10.0), 5.0, BigValue.from_float(1.0), 10.0)
	system.tick = 5
	system.resolve_projectile_contact(hit, enemy, Vector2(100.0, 22.0))
	_expect(player_rule_port.take_calls == take_calls_before + 1 and hit.aggregate_damage.compare(BigValue.from_float(30.0)) == 0 and is_equal_approx(hit.ordinary_damage, 15.0), "combat system: retained aggregate/ordinary was not consumed into the next hit")
	var emptied := player_rule_port.take_retained_arrow()
	_expect(emptied.aggregate.is_zero() and is_zero_approx(float(emptied.ordinary)), "combat system: retained domain values were not cleared after take")


func _expect(condition: bool, message: String) -> void: Assert.expect(condition, message, failures)


class DisposableBlockedPort extends Node:
	func is_target_blocked(_target: CombatEnemyState) -> bool:
		return false


func _blocked_port_value(_target: CombatEnemyState) -> Variant:
	blocked_port_calls += 1
	return blocked_port_result


func _test_strict_blocked_port() -> void:
	var system = CombatSystemScript.new()
	var player_rules := PlayerRulePortStub.new()
	for port_value: Variant in [null, Callable(), "blocked", true, 0]:
		var result: Dictionary = _bind(system, {"player_rule_port": player_rules, "target_blocked": port_value})
		_expect(not result.ok and result.error == "combat_room_port_unavailable", "combat system: missing/invalid blocked port configured")
	var stream = CombatEventStreamScript.new()
	var target := CombatEnemyStateScript.new(Vector2(100, 22), 100, false, 71, "melee_pursuer")
	var targets: Array[CombatEnemyState] = [target]
	_expect(_bind(system, {"player_rule_port": player_rules, "target_blocked": _blocked_port_value, "current_model": _current_model}).ok, "combat system: strict blocked port setup rejected")
	var unreset: Dictionary = system.set_context(1, Vector2.ZERO, Vector2.RIGHT, 10.0, 225.0, 3000.0, 0, {}, stream, ManualAimResolverScript.new(), targets)
	_expect(not unreset.ok and unreset.error == "combat_room_not_reset", "combat system: context silently created room totals without reset")
	_expect(system.reset_room(BigValue.from_float(0)).ok, "combat system: strict blocked fixture reset failed")
	_expect(system.set_context(1, Vector2.ZERO, Vector2.RIGHT, 10.0, 225.0, 3000.0, 0, {}, stream, ManualAimResolverScript.new(), targets).ok, "combat system: strict blocked fixture context failed")
	player_rules.retain_missed_arrow(BigValue.from_float(20), 20)
	blocked_port_calls = 0
	for bad_value: Variant in [null, 0, 1, "false", {}, [], BigValue.from_float(0)]:
		blocked_port_result = bad_value
		var arrow := CombatArrowProjectileScript.new(200, 71, 0, Vector2.ZERO, Vector2.RIGHT, 225, 3000, BigValue.from_float(10), 10, BigValue.from_float(1), 10)
		var event_count: int = stream.latest_event_id()
		var take_calls_before: int = player_rules.take_calls
		var receipt: Dictionary = system.resolve_projectile_sweep(arrow, target, Vector2.ZERO, Vector2(200, 0))
		_expect(not receipt.ok and receipt.error == "target_blocked_port_invalid_result" and system.last_attack_outcome.outcome == "rejected" and system.last_attack_outcome.reason == receipt.error, "combat system: non-bool blocked response was not explicitly rejected")
		_expect(target.health == 100 and system.outcome_snapshot().arrow_hits == 0 and system.outcome_snapshot().defeated == 0 and stream.latest_event_id() == event_count and player_rules.take_calls == take_calls_before, "combat system: bad blocked response changed health, ledger, events or retained payload")
	_expect(blocked_port_calls == 7, "combat system: bad port result used a local fallback or stale answer")
	# Same identity/window must be retryable after a dependency rejection.
	blocked_port_result = false
	var retry := CombatArrowProjectileScript.new(200, 71, 0, Vector2.ZERO, Vector2.RIGHT, 225, 3000, BigValue.from_float(10), 10, BigValue.from_float(1), 10)
	var accepted: Dictionary = system.resolve_projectile_sweep(retry, target, Vector2.ZERO, Vector2(200, 0))
	_expect(accepted.ok and accepted.settled.size() == 1 and target.health == 80 and system.outcome_snapshot().arrow_hits == 1, "combat system: valid retry retained rejected dedup key or lost player retention")
	# The production flight loop publishes an explicit rejection and retires
	# its projectile, without publishing action_impact or damage_applied.
	blocked_port_result = "false"
	var flight := CombatArrowProjectileScript.new(201, 71, 0, Vector2.ZERO, Vector2.RIGHT, 225, 6000, BigValue.from_float(10), 10, BigValue.from_float(1), 10)
	system.projectiles.append(flight)
	system.tick = 2
	var before_flight: int = stream.latest_event_id()
	system.advance_projectiles_tick()
	_expect(system.projectiles.is_empty() and system.last_attack_outcome.outcome == "rejected" and system.last_attack_outcome.reason == "target_blocked_port_invalid_result" and stream.latest_event_id() == before_flight + 1 and target.health == 80 and system.outcome_snapshot().arrow_hits == 1, "combat system: invalid production barrier answer damaged target or failed rejection")
	var disposable := DisposableBlockedPort.new()
	_expect(_bind(system, {"player_rule_port": player_rules, "target_blocked": disposable.is_target_blocked, "current_model": _current_model}).ok, "combat system: disposable blocked dependency configuration failed")
	disposable.free()
	var unavailable: Dictionary = system.set_context(3, Vector2.ZERO, Vector2.RIGHT, 10.0, 225.0, 3000.0, 0, {}, stream, ManualAimResolverScript.new(), targets)
	_expect(not unavailable.ok and unavailable.error == "combat_room_port_unavailable", "combat system: freed blocked dependency accepted new context")
	var before_shots: int = system.shots
	system.resolve_piercing_arrow({"action_instance_id": 202, "tick": 3, "target_entity_id": 71, "aim_direction_milli": {"x": 1000, "y": 0}})
	_expect(system.shots == before_shots and system.projectiles.is_empty() and system.last_attack_outcome.outcome == "rejected" and system.last_attack_outcome.reason == "combat_room_port_unavailable", "combat system: missing live barrier dependency spawned a shot")
	_expect(not system.target_is_currently_blocked(target).ok, "combat system: direct blocked query masked missing dependency")


func _test_versioned_query_profiles() -> void:
	var system := CombatSystemScript.new()
	var player_rules := PlayerRulePortStub.new()
	var boss := CombatEnemyStateScript.new(Vector2(100.0, 0.0), 1000.0, true, 99, "threshold_colossus")
	var stream := CombatEventStreamScript.new()
	var common := {
		"player_rule_port": player_rules,
		"aim_candidate": Callable(self, "_aim_candidate"),
		"current_model": Callable(self, "_current_model"),
		"target_blocked": Callable(self, "_target_blocked"),
	}
	_expect(_bind(system, common).ok, "combat system: default multipart query profile rejected")
	_expect(system.reset_room(BigValue.from_float(0)).ok, "combat system: profile fixture reset rejected")
	_expect(system.set_context(1, Vector2.ZERO, Vector2.RIGHT, 10.0, 225.0, 3000.0, 0, {}, stream, ManualAimResolverScript.new(), [boss]).ok, "combat system: profile fixture context rejected")
	var multipart := system.query_swept_hits(Vector2.ZERO, Vector2(200.0, 0.0), boss)
	_expect(multipart.ok and not multipart.candidates.is_empty() and String(multipart.candidates[0].part_id) == "left_hand", "combat system: default query did not use live multipart hurtboxes")
	var invalid := common.duplicate(true)
	invalid["query_profile"] = "implicit_legacy_fallback"
	var invalid_result: Dictionary = _bind(system, invalid)
	_expect(not invalid_result.ok and invalid_result.error == "invalid_query_profile", "combat system: unknown query profile was accepted")
	var historical := common.duplicate(true)
	historical["query_profile"] = CombatSystemScript.QUERY_PROFILE_HISTORICAL_CIRCLE_V1
	_expect(_bind(system, historical).ok, "combat system: explicit historical query profile rejected")
	_expect(system.reset_room(BigValue.from_float(0)).ok, "combat system: historical profile reset rejected")
	_expect(system.set_context(1, Vector2.ZERO, Vector2.RIGHT, 10.0, 225.0, 3000.0, 0, {}, stream, ManualAimResolverScript.new(), [boss]).ok, "combat system: historical profile context rejected")
	var legacy := system.query_swept_hits(Vector2.ZERO, Vector2(200.0, 0.0), boss)
	_expect(legacy.ok and legacy.candidates.size() == 1 and String(legacy.candidates[0].part_id) == "body", "combat system: historical geometry was not explicit single-circle replay semantics")
