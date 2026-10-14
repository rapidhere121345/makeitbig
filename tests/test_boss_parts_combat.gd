extends SceneTree

const Combat := preload("res://src/systems/combat_system.gd")
const Enemy := preload("res://src/runtime/world/combat_enemy_state.gd")
const Arrow := preload("res://src/runtime/world/combat_arrow_projectile.gd")
const State := preload("res://src/runtime/world/player_combat_state.gd")
const Rules := preload("res://src/systems/player_combat_rules.gd")
const Registry := preload("res://src/runtime/world/actor_registry.gd")
const World := preload("res://src/runtime/world/simulation_world.gd")
const Stream := preload("res://src/systems/combat_event_stream.gd")
const Big := preload("res://src/core/big_value.gd")
const Encounter := preload("res://src/game/encounter_director.gd")
const Aim := preload("res://src/systems/manual_aim_resolver.gd")

var failures: Array[String] = []
var combat: Combat
var boss: Enemy
var stream: Stream
var rules: Rules
var state: State
var encounter: Encounter
var blocked_port_calls := 0
var model_state := "normal"
var queue_changes := false
var boundary_observations := 0


func _initialize() -> void:
	_test_shared_group_and_stable_order()
	_test_distinct_groups_and_identity()
	_test_closed_and_broken()
	_test_commit_boundary()
	_test_idle_commit_boundary()
	_test_invalid_shapes()
	_test_default_boss_poses_and_real_release()
	_test_room_totals_and_snapshots()
	_test_ordinary_kill_totals()
	_test_remaining_boundaries()
	_test_barrier_delegation()
	_test_real_critical_and_miss_ports()
	_test_reset_during_commit()
	if failures.is_empty():
		print("PASS test_boss_parts_combat.gd")
		quit(0)
		return
	for failure: String in failures:
		printerr("- %s" % failure)
	quit(1)


func _setup(parts: Array[Dictionary]) -> void:
	stream = Stream.new()
	var registry := Registry.new()
	var world := World.new()
	registry.configure("boss-parts-room", 1)
	registry.register_actor("ranger", Vector2.ZERO, 14.0)
	world.configure(30, "boss-parts-room", 1)
	state = State.new()
	state.reset_for_room({"final_parameters": {"max_health": 100.0, "d": 225.0}, "skills": ["piercing_arrow"], "talent_capabilities": {"expiry_payload_retention": 0.5, "first_critical_bonus_generations": 2, "three_skill_rhythm_windup_ticks": 2}}, registry, "ranger", world.tick)
	rules = Rules.new()
	_expect(rules.configure(state, world, stream).ok, "real PlayerCombatRules rejected fixture")
	boss = Enemy.new(Vector2(100, 0), 1000.0, true, 41, "threshold_colossus")
	boss.parts = parts.duplicate(true)
	encounter = Encounter.new()
	blocked_port_calls = 0
	model_state = "normal"
	combat = Combat.new()
	_expect(combat.configure({"player_rule_port": rules, "current_model": _model, "target_blocked": _delegated_blocked, "advance_sequence": rules.advance_three_skill_sequence, "reset_sequence": rules.reset_three_skill_sequence}).ok, "strict player port rejected real rules")
	_expect(combat.reset_room(Big.from_float(10000)).ok, "room reset rejected")
	var enemies: Array[CombatEnemyState] = [boss]
	_expect(combat.set_context(1, Vector2.ZERO, Vector2.RIGHT, 10.0, 225.0, 6000.0, 0, {}, stream, Aim.new(), enemies).ok, "headless context rejected")
	queue_changes = false
	boundary_observations = 0


func _part(id: String, group: String, offset: Vector2 = Vector2.ZERO) -> Dictionary:
	return {"part_id": id, "pose": offset, "hurtbox": {"type": "circle", "radius": 10.0}, "damage_group_id": group, "broken": false, "active": true}


func _arrow(id: int, target_id: int = 41) -> Arrow:
	return Arrow.new(id, target_id, 0, Vector2.ZERO, Vector2.RIGHT, 225.0, 6000.0, Big.from_float(10), 10.0, Big.from_float(1), 10.0)


func _sweep(arrow: Arrow, target: Enemy = null) -> Dictionary:
	return combat.resolve_projectile_sweep(arrow, boss if target == null else target, Vector2.ZERO, Vector2(200, 0))


func _test_shared_group_and_stable_order() -> void:
	_setup([_part("hand", "body"), _part("head", "body")])
	var query := combat.query_swept_hits(Vector2.ZERO, Vector2(200, 0), boss)
	_expect(query.ok and _ids(query.candidates) == ["hand", "head"], "coincident contacts did not sort by part ID")
	boss.parts.reverse()
	var reversed_query := combat.query_swept_hits(Vector2.ZERO, Vector2(200, 0), boss)
	_expect(query == reversed_query, "candidate order depends on part insertion order")
	_expect(query.candidates[0].target_entity_id == 41 and query.candidates[0].contact_point == Vector2(90, 0), "sweep lost logical target or first contact")
	var arrow := _arrow(11)
	var result := _sweep(arrow)
	_expect(result.ok and result.candidates.size() == 2 and result.settled.size() == 1, "head/hand shared group was not deduplicated")
	_expect(combat.arrow_hits == 1 and combat.outcome_snapshot().boss_damage.compare(Big.from_float(10)) == 0 and _damage_events().size() == 1, "shared group did not apply exactly one real payload")
	var repeated := _sweep(_arrow(11))
	_expect(repeated.ok and repeated.settled.is_empty() and combat.arrow_hits == 1, "same attack/target/group settled twice in one window")
	_expect(_sweep(_arrow(12)).settled.size() == 1, "different attack instance was incorrectly deduplicated")
	combat.tick += 1
	_expect(_sweep(_arrow(11)).settled.size() == 1, "new commit window retained stale dedup state")


func _test_distinct_groups_and_identity() -> void:
	_setup([_part("hand", "limb", Vector2(20, 0)), _part("head", "core", Vector2(-20, 0))])
	var result := _sweep(_arrow(20))
	_expect(result.ok and _ids(result.settled) == ["head", "hand"], "distinct groups did not settle in first contact order")
	_expect(combat.outcome_snapshot().boss_damage.compare(Big.from_float(20)) == 0 and combat.arrow_hits == 2, "distinct damage groups did not each apply real boss damage")
	var events := _damage_events()
	_expect(events.size() == 2 and events[0].part_id == "head" and events[0].damage_group_id == "core" and events[1].part_id == "hand" and events[1].damage_group_id == "limb", "production damage events lost part/group attribution")
	var other := Enemy.new(Vector2(100, 0), 1000.0, true, 42, "threshold_colossus")
	other.parts = boss.parts.duplicate(true)
	_expect(_sweep(_arrow(20, 42), other).settled.size() == 2, "dedup conflated two logical target IDs")
	_expect(not _sweep(_arrow(21, 42)).ok, "mismatched projectile logical target accepted")


func _test_closed_and_broken() -> void:
	var broken := _part("broken", "limb")
	broken.broken = true
	var closed := _part("closed", "core")
	closed.active = false
	_setup([broken, closed])
	var result := _sweep(_arrow(30))
	_expect(result.ok and result.candidates.is_empty() and result.settled.is_empty(), "broken/closed part was hittable")
	_expect(combat.arrow_hits == 0 and combat.outcome_snapshot().boss_damage.is_zero() and _damage_events().is_empty(), "broken/closed parts changed damage")
	_expect(not boss.queue_part_state("missing", false, true).ok, "unknown part transition silently accepted")


func _test_commit_boundary() -> void:
	_setup([_part("head", "core"), _part("hand", "limb")])
	queue_changes = true
	combat.impact_trace_requested.connect(_during_impact)
	# Both projectiles in one flight submission see the original part snapshot.
	# A queued break/close must not remove the second group or second projectile.
	combat.projectiles.append(_arrow(40))
	combat.projectiles.append(_arrow(41))
	combat.advance_projectiles_tick()
	_expect(combat.arrow_hits == 4 and boundary_observations == 4, "queued part change leaked into active contact iteration")
	_expect(boss.parts.size() == 2 and bool(boss.parts[0].broken) and not bool(boss.parts[1].active), "part transitions were not committed after projectile iteration")
	_expect(combat.projectiles.is_empty(), "flight did not retire both contacted projectiles")
	combat.tick += 1
	var result := _sweep(_arrow(42))
	_expect(result.candidates.is_empty() and combat.arrow_hits == 4, "committed break/close remained hittable in next submission")


func _during_impact(_position: Vector2, _direction: Vector2, _generations: int) -> void:
	if not queue_changes:
		return
	_expect(not bool(boss.parts[0].broken) and bool(boss.parts[1].active), "part state mutated before commit boundary")
	boundary_observations += 1
	boss.queue_part_state("head", true, true)
	boss.queue_part_state("hand", false, false)


func _test_idle_commit_boundary() -> void:
	_setup([_part("head", "body")])
	_expect(boss.queue_part_state("head", false, true).ok, "valid queued part transition rejected")
	_expect(bool(boss.parts[0].active) and not bool(boss.parts[0].broken), "queue changed part before a submission boundary")
	combat.advance_projectiles_tick()
	_expect(not bool(boss.parts[0].active) and bool(boss.parts[0].broken), "idle tick failed to commit pending part transitions")


func _test_invalid_shapes() -> void:
	var missing := _part("head", "body")
	missing.erase("hurtbox")
	_setup([_part("valid", "other"), missing])
	var result := _sweep(_arrow(50))
	_expect(not result.ok and result.error == "missing_hurtbox_shape" and result.candidates.is_empty(), "missing shape did not explicitly fail the complete sweep")
	_expect(combat.outcome_snapshot().boss_damage.is_zero() and _damage_events().is_empty(), "invalid shape allowed partial damage")
	combat.projectiles.append(_arrow(51))
	combat.advance_projectiles_tick()
	_expect(combat.projectiles.is_empty() and combat.last_attack_outcome.reason == "missing_hurtbox_shape" and combat.last_attack_outcome.outcome == "rejected", "production flight silently fell back to one circle for missing shape")
	boss.parts.clear()
	_expect(_sweep(_arrow(52)).error == "missing_hurtbox_parts", "empty Boss parts silently fell back to aim circle")
	for radius: Variant in [true, "10", -1.0, INF]:
		var malformed := _part("head", "body")
		malformed.hurtbox.radius = radius
		boss.parts = [malformed]
		_expect(not _sweep(_arrow(53)).ok, "invalid hurtbox radius accepted: " + str(radius))
	var unsupported := _part("head", "body")
	unsupported.hurtbox = {"type": "rect", "rect": Rect2(0, 0, 10, 10)}
	boss.parts = [unsupported]
	_expect(_sweep(_arrow(54)).error == "unsupported_hurtbox_shape", "unsupported hurtbox silently approximated")


func _test_default_boss_poses_and_real_release() -> void:
	_setup([])
	var production_boss := Enemy.new(Vector2(100, 0), 1000, true, 41, "threshold_colossus")
	boss.parts = production_boss.parts.duplicate(true)
	boss.left_hand_position = Vector2(60, 0)
	boss.right_hand_position = Vector2(160, 80)
	var query := combat.query_swept_hits(Vector2.ZERO, Vector2(200, 0), boss)
	_expect(query.ok and _ids(query.candidates) == ["left_hand"], "default Boss did not use authoritative hand pose")
	boss.left_hand_position = Vector2(60, 80)
	_expect(combat.query_swept_hits(Vector2.ZERO, Vector2(200, 0), boss).candidates.is_empty(), "moving hand left stale incoming hurtbox")
	boss.left_hand_position = Vector2(60, 0)
	# Real player domain owns retention; fixture contributes no combat port stub.
	rules.retain_missed_arrow(Big.from_float(20), 20.0)
	combat.resolve_piercing_arrow({"action_instance_id": 60, "tick": 1, "target_entity_id": 41, "aim_direction_milli": {"x": 1000, "y": 0}})
	_expect(combat.projectiles.size() == 1 and combat.shots == 1, "real arrow release did not spawn")
	combat.tick = 2
	combat.advance_projectiles_tick()
	_expect(combat.projectiles.is_empty() and combat.arrow_hits == 1 and combat.outcome_snapshot().boss_damage.compare(Big.from_float(20)) == 0, "real released arrow did not hit default Boss hand using domain retention")
	_expect(rules.take_retained_arrow().aggregate.is_zero(), "production hit failed to consume real retained payload")
	var event: Dictionary = _damage_events()[0]
	_expect(event.target_entity_id == 41 and event.part_id == "left_hand" and event.damage_group_id == "body", "real flight bypassed multipart production path")


func _model() -> Dictionary:
	return {"state": model_state, "total_events": Big.from_float(1), "total_events_float": 1.0, "g": 1}


func _ids(candidates: Array) -> Array:
	return candidates.map(func(hit: Dictionary) -> String: return String(hit.part_id))


func _damage_events() -> Array:
	return stream.snapshot().events.filter(func(event: Dictionary) -> bool: return String(event.get("type", "")) == "damage_applied")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _delegated_blocked(target: CombatEnemyState) -> bool:
	blocked_port_calls += 1
	return encounter.is_target_blocked(target)


func _context(new_tick: int, targets: Array[CombatEnemyState]) -> Dictionary:
	return combat.set_context(new_tick, Vector2.ZERO, Vector2.RIGHT, 10.0, 225.0, 6000.0, 0, {}, stream, Aim.new(), targets)


func _test_room_totals_and_snapshots() -> void:
	_setup([_part("head", "body"), _part("hand", "body")])
	var maximum := Big.from_float(20)
	_expect(combat.reset_room(maximum).ok, "explicit new room reset rejected")
	maximum.magnitude = 999
	_expect(_context(1, [boss]).ok and combat.remaining_boss_health().compare(Big.from_float(20)) == 0, "room maximum aliases reset input")
	combat.resolve_piercing_arrow({"action_instance_id": 80, "tick": 1, "target_entity_id": 41, "aim_direction_milli": {"x": 1000, "y": 0}})
	combat.tick = 2
	combat.advance_projectiles_tick()
	var outcome := combat.outcome_snapshot()
	_expect(outcome.boss_damage.compare(Big.from_float(10)) == 0 and outcome.boss_maximum.compare(Big.from_float(20)) == 0 and outcome.defeated == 0 and outcome.shots == 1 and outcome.arrow_hits == 1, "real multipart flight did not commit one payload to the sole ledger")
	_expect(combat.remaining_boss_health().compare(Big.from_float(10)) == 0, "50 percent damage did not leave exact remaining health")
	var first_event: Dictionary = _damage_events()[0]
	_expect(first_event.boss_remaining_before == "20.0" and first_event.boss_remaining_after == "10.0", "remaining health event semantics changed: %s -> %s" % [first_event.boss_remaining_before, first_event.boss_remaining_after])
	# Object values need an explicit BigValue clone; Dictionary.duplicate alone
	# would retain these objects and leak writes back to the authority.
	outcome.boss_damage.magnitude = 900
	outcome.boss_maximum.layer = 2
	outcome.defeated = 99
	outcome.shots = 99
	outcome.arrow_hits = 99
	var remaining := combat.remaining_boss_health()
	remaining.magnitude = 700
	_expect(_context(3, [boss]).ok, "new fixed tick context rejected")
	var untouched := combat.outcome_snapshot()
	_expect(untouched.boss_damage.compare(Big.from_float(10)) == 0 and untouched.boss_maximum.compare(Big.from_float(20)) == 0 and untouched.defeated == 0 and untouched.shots == 1 and untouched.arrow_hits == 1 and combat.remaining_boss_health().compare(Big.from_float(10)) == 0, "snapshot/remaining edits or set_context contaminated combat totals")
	combat.resolve_piercing_arrow({"action_instance_id": 81, "tick": 3, "target_entity_id": 41, "aim_direction_milli": {"x": 1000, "y": 0}})
	combat.tick = 4
	combat.advance_projectiles_tick()
	var killed := combat.outcome_snapshot()
	_expect(killed.boss_damage.compare(Big.from_float(20)) == 0 and killed.defeated == 1 and killed.shots == 2 and killed.arrow_hits == 2 and boss.health == 0 and combat.remaining_boss_health().is_zero(), "exact maximum did not commit one Boss death")
	_expect(_sweep(_arrow(81)).settled.is_empty() and combat.outcome_snapshot().defeated == 1, "repeated dead Boss sweep incremented totals")
	var event_types: Array = stream.snapshot().events.map(func(event: Dictionary) -> String: return String(event.type))
	_expect(event_types == ["projectile_spawned", "action_impact", "attack_resolved", "damage_applied", "projectile_spawned", "action_impact", "attack_resolved", "damage_applied", "death_applied"], "hit/death event order changed")
	var next_boss := Enemy.new(Vector2(100, 0), 1000, true, 41, "threshold_colossus")
	next_boss.parts = [_part("head", "body")]
	combat.projectiles.append(_arrow(82))
	combat.attack_origins[82] = {"release_offset": Vector2.ONE}
	_expect(combat.reset_room(Big.from_float(7)).ok and combat.projectiles.is_empty() and combat.attack_origins.is_empty() and combat.last_attack_outcome.is_empty(), "new room carried previous flight state")
	var fresh := combat.outcome_snapshot()
	_expect(fresh.boss_damage.is_zero() and fresh.defeated == 0 and fresh.shots == 0 and fresh.arrow_hits == 0 and fresh.boss_maximum.compare(Big.from_float(7)) == 0 and combat.remaining_boss_health().is_zero(), "new room did not clear all outcome totals")
	_expect(_context(4, [next_boss]).ok, "new room context rejected")
	_expect(_sweep(_arrow(81), next_boss).settled.size() == 1 and combat.outcome_snapshot().defeated == 1 and combat.outcome_snapshot().boss_damage.compare(Big.from_float(10)) == 0, "new room retained old attack dedup or capped overkill damage")
	_expect(combat.remaining_boss_health().is_zero(), "overkill did not clamp remaining health to zero")


func _test_ordinary_kill_totals() -> void:
	_setup([])
	_expect(combat.reset_room(Big.from_float(0)).ok, "ordinary room zero Boss maximum rejected")
	var ordinary := Enemy.new(Vector2(100, 22), 10, false, 41, "melee_pursuer")
	var supplied: Array[CombatEnemyState] = [ordinary]
	_expect(_context(1, supplied).ok and combat.remaining_boss_health().is_zero(), "ordinary room exposed Boss health")
	combat.resolve_piercing_arrow({"action_instance_id": 90, "tick": 1, "target_entity_id": 41, "aim_direction_milli": {"x": 1000, "y": 0}})
	combat.tick = 2
	combat.advance_projectiles_tick()
	var killed := combat.outcome_snapshot()
	_expect(ordinary.health == 0 and killed.defeated == 1 and killed.shots == 1 and killed.arrow_hits == 1 and killed.boss_damage.is_zero() and supplied.is_empty(), "real ordinary arrow did not commit one death without Boss damage")
	combat.resolve_projectile_contact(_arrow(90), ordinary, ordinary.position)
	combat.resolve_projectile_contact(_arrow(91), ordinary, ordinary.position)
	_expect(combat.outcome_snapshot().defeated == 1 and _damage_events().size() == 1 and stream.snapshot().events.filter(func(event: Dictionary) -> bool: return event.type == "death_applied").size() == 1, "direct contacts to a dead ordinary target duplicated damage/death")
	var live := Enemy.new(Vector2(100, 22), 100, false, 42, "melee_pursuer")
	_expect(_context(3, [live]).ok, "live ordinary context rejected")
	combat.resolve_projectile_contact(_arrow(92, 42), live, live.position)
	combat.resolve_projectile_contact(_arrow(92, 42), live, live.position)
	_expect(live.health == 90 and combat.outcome_snapshot().arrow_hits == 2, "ordinary direct contacts bypassed attack/group dedup")


func _test_remaining_boundaries() -> void:
	_setup([_part("head", "body")])
	for maximum: BigValue in [Big.from_float(10), Big.from_float(1.0e12), Big.from_power10(400), Big.from_tetration10(5)]:
		_expect(combat.reset_room(maximum).ok and _context(1, [boss]).ok, "remaining boundary room setup rejected")
		boss.health = 1000
		_expect(combat.remaining_boss_health().compare(maximum) == 0, "untouched maximum health changed")
		_sweep(_arrow(100))
		var expected := Big.from_float(maxf(0, maximum.magnitude - 10)) if maximum.layer == 0 else maximum
		var remaining := combat.remaining_boss_health()
		_expect(remaining.compare(expected) == 0, "remaining health changed legacy layer subtraction semantics")
		remaining.layer = 9
		remaining.magnitude = 9
		_expect(combat.remaining_boss_health().compare(expected) == 0 and combat.outcome_snapshot().boss_maximum.compare(maximum) == 0, "large remaining projection was not detached")
		if maximum.layer > 0:
			var fatal := _arrow(101)
			fatal.aggregate_damage = maximum.duplicate_value()
			_sweep(fatal)
			_expect(combat.remaining_boss_health().is_zero() and combat.outcome_snapshot().defeated == 1, "large BigValue exact defeat changed compare semantics")
	_expect(combat.reset_room(Big.from_float(0)).ok and _context(2, [boss]).ok and combat.remaining_boss_health().is_zero(), "zero maximum remaining boundary changed")
	var before := combat.outcome_snapshot()
	for bad: BigValue in [null, _malformed_big(-1, 1), _malformed_big(0, -1), _malformed_big(0, NAN), _malformed_big(1, INF)]:
		var reset := combat.reset_room(bad)
		_expect(not reset.ok and reset.error == "invalid_boss_maximum", "malformed maximum was accepted")
		var after := combat.outcome_snapshot()
		_expect(after.boss_damage.compare(before.boss_damage) == 0 and after.boss_maximum.compare(before.boss_maximum) == 0 and after.defeated == before.defeated, "invalid room reset partially wrote ledger")


func _malformed_big(layer: int, magnitude: float) -> BigValue:
	var value := Big.new()
	value.layer = layer
	value.magnitude = magnitude
	return value


func _test_barrier_delegation() -> void:
	_setup([_part("head", "body")])
	encounter.elite_entity_id = boss.entity_id
	encounter.elite_barrier_active = true
	rules.retain_missed_arrow(Big.from_float(20), 20)
	rules.advance_three_skill_sequence("piercing_arrow")
	var blocked := _sweep(_arrow(110))
	_expect(blocked.ok and blocked_port_calls == 1 and combat.last_attack_outcome.outcome == "blocked" and not encounter.is_targetable(boss), "actual hit failed to consume Encounter blocked port")
	_expect(combat.outcome_snapshot().boss_damage.is_zero() and combat.outcome_snapshot().arrow_hits == 0 and _damage_events().is_empty() and state.snapshot(1).three_skill_sequence_stage == 0, "barrier applied damage or failed to reset real sequence")
	encounter.elite_barrier_active = false
	_expect(_sweep(_arrow(111)).ok and blocked_port_calls == 2 and encounter.is_targetable(boss), "changed Encounter answer did not control the next contact")
	_expect(combat.outcome_snapshot().boss_damage.compare(Big.from_float(20)) == 0 and combat.outcome_snapshot().arrow_hits == 1 and rules.take_retained_arrow().aggregate.is_zero(), "blocked arrow consumed retained payload or unblocked arrow lost it")
	encounter.elite_barrier_active = true
	encounter.elite_entity_id = 99
	_expect(_sweep(_arrow(112)).ok and combat.outcome_snapshot().boss_damage.compare(Big.from_float(30)) == 0, "CombatSystem invented a barrier rule beyond Encounter target identity")


func _test_real_critical_and_miss_ports() -> void:
	_setup([_part("head", "body")])
	model_state = "critical"
	for id: int in [120, 121]:
		combat.resolve_piercing_arrow({"action_instance_id": id, "tick": 1, "target_entity_id": 41, "aim_direction_milli": {"x": 1000, "y": 0}})
	_expect(combat.projectiles[0].event_count.compare(Big.from_float(3)) == 0 and combat.projectiles[1].event_count.compare(Big.from_float(1)) == 0, "real first-critical domain bonus was not consumed once")
	combat.projectiles.clear()
	var miss := _arrow(122)
	miss.aggregate_damage = Big.from_float(40)
	miss.ordinary_damage = 20
	combat.resolve_projectile_miss(miss)
	_expect(combat.last_attack_outcome.outcome == "miss" and combat.outcome_snapshot().boss_damage.is_zero(), "miss changed combat damage ledger")
	_sweep(_arrow(123))
	_expect(combat.outcome_snapshot().boss_damage.compare(Big.from_float(30)) == 0 and rules.take_retained_arrow().aggregate.is_zero(), "miss retention was not consumed exactly once from real player rules")


func _test_reset_during_commit() -> void:
	_setup([_part("head", "body")])
	combat.impact_trace_requested.connect(func(_position: Vector2, _direction: Vector2, _generations: int) -> void:
		var reset := combat.reset_room(Big.from_float(1))
		_expect(not reset.ok and reset.error == "combat_commit_in_progress", "reentrant room reset split a real hit commit")
	)
	_expect(_sweep(_arrow(130)).ok and combat.outcome_snapshot().boss_damage.compare(Big.from_float(10)) == 0 and combat.outcome_snapshot().arrow_hits == 1, "rejected mid-hit reset contaminated direct sweep totals")

	combat.tick = 2
	combat.projectiles.append(_arrow(131))
	combat.advance_projectiles_tick()
	_expect(combat.projectiles.is_empty() and combat.outcome_snapshot().boss_damage.compare(Big.from_float(20)) == 0 and combat.outcome_snapshot().arrow_hits == 2, "rejected mid-flight reset contaminated projectile iteration")
