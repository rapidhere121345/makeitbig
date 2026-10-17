extends SceneTree

## Real fixed-tick Boss vertical slice.
##
## The room ports execute the query and DAMAGE_STATUS phases; the Boss domain
## owns only typed records, the multipart hit buffer, BigValue resolution and
## the explicit death settlement seam.

const Fixtures := preload("res://tests/spatial/spatial_fixtures.gd")
const StaticSpatialIndexScript := preload("res://src/runtime/spatial/static_spatial_index.gd")
const DynamicSpatialIndexScript := preload("res://src/runtime/spatial/dynamic_spatial_index.gd")
const MovementResolverScript := preload("res://src/runtime/spatial/movement_resolver.gd")
const SpatialChannels := preload("res://src/runtime/spatial/spatial_channels.gd")
const RoomSpatialPortScript := preload("res://src/runtime/world/room_spatial_port.gd")
const RoomCombatPortScript := preload("res://src/runtime/world/room_combat_port.gd")
const RoomActorAccessScript := preload("res://src/runtime/world/room_actor_access.gd")
const SimulationWorldScript := preload("res://src/runtime/world/simulation_world.gd")
const BossDomainScript := preload("res://src/runtime/combat/boss_combat_domain.gd")
const BossQueryScript := preload("res://src/runtime/combat/boss_attack_query.gd")
const BossDamageValueScript := preload("res://src/runtime/combat/boss_damage_value.gd")
const BossTargetScript := preload("res://src/runtime/combat/boss_target_view.gd")
const BossHurtboxScript := preload("res://src/runtime/combat/boss_hurtbox.gd")
const BigValueScript := preload("res://src/core/big_value.gd")

var failures: Array[String] = []
var worlds: Array[SimulationWorld] = []
var world: SimulationWorld = null
var spatial: RoomSpatialPort = null
var combat: RoomCombatPort = null
var access: RoomActorAccess = null
var domain: BossCombatDomain = null
var ranger: SimEntityHandle = null


func _initialize() -> void:
	_make_room()
	_test_multipart_query_order_and_wall_priority()
	_test_periodic_barrier_admission()
	_test_big_value_death_and_settlement_idempotence()
	_test_fail_closed_damage_boundary()
	_teardown()
	if failures.is_empty():
		print("PASS test_kernel_boss_combat.gd")
		quit(0)
		return
	printerr("FAIL test_kernel_boss_combat.gd")
	for failure: String in failures:
		printerr("- %s" % failure)
	quit(1)


func _make_room() -> void:
	var static_build: Dictionary = StaticSpatialIndexScript.build(Fixtures.wall_world())
	_expect(bool(static_build.get("ok", false)), "Boss kernel: wall fixture rejected")
	if not bool(static_build.get("ok", false)):
		return
	var static_index: StaticSpatialIndex = static_build["value"]
	var dynamic_index := DynamicSpatialIndexScript.new()
	var movement_build: Dictionary = MovementResolverScript.make(static_index, null, dynamic_index)
	_expect(bool(movement_build.get("ok", false)), "Boss kernel: movement resolver rejected")
	if not bool(movement_build.get("ok", false)):
		return

	spatial = RoomSpatialPortScript.new()
	combat = RoomCombatPortScript.new()
	world = SimulationWorldScript.new(spatial, combat, null, null)
	worlds.append(world)
	_expect(world.configure("boss-kernel-room", 7, 30).ok, "Boss kernel: fixed-tick world rejected")
	access = RoomActorAccessScript.new()
	var access_result: Dictionary = access.configure(world, world.actor_registry, static_index, dynamic_index, movement_build["value"], null)
	_expect(bool(access_result.get("ok", false)), "Boss kernel: actor access rejected")
	if not failures.is_empty():
		return
	spatial.bind(access)
	combat.bind(access)
	domain = BossDomainScript.new()
	_expect(bool(domain.configure("boss-kernel-room", 7).get("ok", false)), "Boss kernel: domain configure rejected")
	_expect(bool(spatial.bind_boss_domain(domain).get("ok", false)), "Boss kernel: spatial domain bind rejected")
	_expect(bool(combat.bind_boss_domain(domain).get("ok", false)), "Boss kernel: combat domain bind rejected")
	var ranger_result: Dictionary = access.register_actor("ranger", Vector2(20.0, 60.0), 4.0, 1, &"soft", [SpatialChannels.MOVEMENT])
	_expect(bool(ranger_result.get("ok", false)), "Boss kernel: ranger registration rejected")
	ranger = access.actor_handle("ranger")


func _test_multipart_query_order_and_wall_priority() -> void:
	if domain == null:
		return
	var target: BossTargetView = BossTargetScript.make(
		"boss/small",
		BigValueScript.from_float(4.0),
		Vector2.ZERO,
		"threshold_colossus",
		"wave.01/threshold",
		["boss.threshold"]
	)
	_expect(bool(target.add_part(BossHurtboxScript.make("head", "core", Vector2(50.0, 60.0), 3.0)).get("ok", false)), "Boss kernel: head hurtbox rejected")
	_expect(bool(target.add_part(BossHurtboxScript.make("left_hand", "limb", Vector2(65.0, 60.0), 3.0)).get("ok", false)), "Boss kernel: left hurtbox rejected")
	_expect(bool(target.add_part(BossHurtboxScript.make("right_hand", "limb", Vector2(80.0, 60.0), 3.0)).get("ok", false)), "Boss kernel: right hurtbox rejected")
	# The part touches the x=100 wall at exactly the same TOI as the wall.
	_expect(bool(target.add_part(BossHurtboxScript.make("shielded_core", "core", Vector2(104.0, 60.0), 4.0)).get("ok", false)), "Boss kernel: tie hurtbox rejected")
	_expect(bool(domain.register_target(target).get("ok", false)), "Boss kernel: multipart target registration rejected")

	var damage: BossDamageValue = BossDamageValueScript.from_milli(1500)
	var first := BossQueryScript.make(ranger, "boss/small", SpatialChannels.PROJECTILE, Vector2(20.0, 60.0), Vector2(140.0, 0.0), 0.0, true, "arrow/window-1", damage)
	var duplicate := first.duplicate_value()
	_expect(bool(spatial.queue_boss_path_query(first).get("ok", false)), "Boss kernel: first multipart query rejected")
	_expect(bool(spatial.queue_boss_path_query(duplicate).get("ok", false)), "Boss kernel: duplicate multipart query rejected")
	_expect(world.step_tick().ok, "Boss kernel: multipart fixed tick failed")

	var path_results := spatial.take_boss_path_results()
	_expect(path_results.size() == 2, "Boss kernel: query result count changed")
	for result: BossPathResult in path_results:
		_expect(result.ok, "Boss kernel: multipart path failed: %s" % str(result.errors))
		var part_ids: Array[String] = []
		for contact: BossHitContact in result.hit_contacts:
			part_ids.append(contact.part_id)
		_expect(part_ids == ["head", "left_hand", "right_hand"], "Boss kernel: multipart order/wall priority changed: %s" % str(part_ids))
		_expect(result.blocked_by_static and result.blocker_id == "wall", "Boss kernel: opaque wall did not win the equal-TOI tie")
		_expect(result.hit_contacts.all(func(contact: BossHitContact) -> bool: return contact.part_id != "shielded_core"), "Boss kernel: equal-TOI wall leaked a Boss part")

	var batch: Dictionary = combat.last_boss_batch
	var outcomes: Array = batch.get("outcomes", [])
	_expect(outcomes.size() == 2, "Boss kernel: same attack/target/group was not deduped: %s" % str(batch))
	if outcomes.size() == 2:
		_expect(String(outcomes[0].part_id) == "head" and String(outcomes[0].damage_group_id) == "core", "Boss kernel: first part attribution was lost")
		_expect(String(outcomes[1].part_id) == "left_hand" and String(outcomes[1].damage_group_id) == "limb", "Boss kernel: group attribution was lost")
		_expect(String(outcomes[0].requested_damage.kind) == "milli" and int(outcomes[0].requested_damage.milli) == 1500, "Boss kernel: milli payload crossed the boundary more than once")
		_expect(is_equal_approx(float(outcomes[0].applied_damage.big.magnitude), 1.5), "Boss kernel: milli payload did not become exact BigValue damage")
		_expect(is_equal_approx(float(outcomes[1].remaining_health.magnitude), 1.0), "Boss kernel: multipart damage total was not committed")
	_expect((batch.get("suppressed", []) as Array).size() == 4, "Boss kernel: duplicate/group suppression receipt count changed")
	_expect(domain.target("boss/small").health.compare(BigValueScript.from_float(1.0)) == 0, "Boss kernel: detached target health was not committed")


func _test_big_value_death_and_settlement_idempotence() -> void:
	if domain == null:
		return
	var target: BossTargetView = BossTargetScript.make(
		"boss/huge",
		BigValueScript.from_power10(400),
		Vector2.ZERO,
		"threshold_colossus",
		"wave.01/huge",
		["boss.threshold"]
	)
	_expect(bool(target.add_part(BossHurtboxScript.make("core", "core", Vector2(50.0, 60.0), 3.0)).get("ok", false)), "Boss kernel: BigValue hurtbox rejected")
	_expect(bool(domain.register_target(target).get("ok", false)), "Boss kernel: BigValue target registration rejected")
	var huge_damage: BossDamageValue = BossDamageValueScript.from_big(BigValueScript.from_power10(400))
	var query := BossQueryScript.make(ranger, "boss/huge", SpatialChannels.PROJECTILE, Vector2(20.0, 60.0), Vector2(140.0, 0.0), 0.0, false, "arrow/huge-1", huge_damage)
	_expect(bool(spatial.queue_boss_path_query(query).get("ok", false)), "Boss kernel: BigValue query rejected")
	_expect(world.step_tick().ok, "Boss kernel: BigValue fixed tick failed")
	var batch: Dictionary = combat.last_boss_batch
	_expect((batch.get("deaths", []) as Array) == ["boss/huge"], "Boss kernel: exact BigValue damage did not produce one death")
	_expect(not domain.target("boss/huge").alive, "Boss kernel: lethal BigValue did not mark target dead")
	if not (batch.get("outcomes", []) as Array).is_empty():
		var outcome: Dictionary = batch.outcomes[0]
		_expect(int(outcome.remaining_health.layer) == 0 and is_zero_approx(float(outcome.remaining_health.magnitude)), "Boss kernel: lethal remaining BigValue was not canonical zero")

	var settled := combat.settle_boss_deaths(world.tick)
	_expect(bool(settled.get("ok", false)) and (settled.get("settlements", []) as Array).size() == 1, "Boss kernel: death settlement did not produce one receipt")
	var repeated := combat.settle_boss_deaths(world.tick)
	_expect(bool(repeated.get("ok", false)) and (repeated.get("settlements", []) as Array).is_empty(), "Boss kernel: repeated death settlement produced another receipt")
	_expect(combat.last_boss_settlements.size() == 1, "Boss kernel: settlement telemetry duplicated")

	# A dead Boss is absent from the next multipart query, even if an old attack
	# identity is submitted again in a new fixed window.
	var repeated_attack := BossQueryScript.make(ranger, "boss/huge", SpatialChannels.PROJECTILE, Vector2(20.0, 60.0), Vector2(140.0, 0.0), 0.0, false, "arrow/huge-1", huge_damage)
	_expect(bool(spatial.queue_boss_path_query(repeated_attack).get("ok", false)), "Boss kernel: dead-target query was rejected instead of resolving empty")
	_expect(world.step_tick().ok, "Boss kernel: dead-target fixed tick failed")
	_expect((combat.last_boss_batch.get("outcomes", []) as Array).is_empty() and (combat.last_boss_batch.get("deaths", []) as Array).is_empty(), "Boss kernel: dead target accepted repeated damage/death")
	_expect(combat.last_boss_settlements.size() == 1, "Boss kernel: dead target changed settlement count")


func _test_periodic_barrier_admission() -> void:
	if domain == null:
		return
	var target: BossTargetView = BossTargetScript.make(
		"boss/barrier",
		BigValueScript.from_float(4.0),
		Vector2.ZERO,
		"threshold_colossus",
		"wave.01/barrier",
		["boss.threshold"]
	)
	_expect(not target.admission_blocked and target.admission_reason.is_empty(), "Boss kernel: new target did not default to open admission")
	_expect(bool(target.add_part(BossHurtboxScript.make("core", "core", Vector2(50.0, 60.0), 3.0)).get("ok", false)), "Boss kernel: barrier hurtbox rejected")
	_expect(bool(target.set_admission(true, "periodic_barrier").get("ok", false)), "Boss kernel: periodic barrier admission could not open")
	_expect(bool(domain.register_target(target).get("ok", false)), "Boss kernel: barrier target registration rejected")
	var health_before := target.health.duplicate_value()
	var blocked := BossQueryScript.make(ranger, "boss/barrier", SpatialChannels.PROJECTILE, Vector2(20.0, 60.0), Vector2(80.0, 0.0), 0.0, false, "arrow/barrier-1", BossDamageValueScript.from_milli(1500))
	_expect(bool(spatial.queue_boss_path_query(blocked).get("ok", false)), "Boss kernel: blocked barrier query rejected")
	_expect(world.step_tick().ok, "Boss kernel: blocked barrier fixed tick failed")
	var blocked_batch: Dictionary = combat.last_boss_batch
	_expect((blocked_batch.get("outcomes", []) as Array).is_empty(), "Boss kernel: periodic barrier produced a damage outcome")
	var blocked_suppressed: Array = blocked_batch.get("suppressed", [])
	_expect(blocked_suppressed.size() == 1 and String(blocked_suppressed[0].get("reason", "")) == "periodic_barrier", "Boss kernel: periodic barrier suppression receipt was not typed")
	_expect(target.health.compare(health_before) == 0 and target.alive, "Boss kernel: blocked hit changed health or alive state")
	_expect(combat.last_boss_settlements.is_empty(), "Boss kernel: blocked hit produced a settlement")
	_expect(bool(target.set_admission(false).get("ok", false)), "Boss kernel: periodic barrier admission could not close")
	var open := BossQueryScript.make(ranger, "boss/barrier", SpatialChannels.PROJECTILE, Vector2(20.0, 60.0), Vector2(80.0, 0.0), 0.0, false, "arrow/barrier-2", BossDamageValueScript.from_milli(1500))
	_expect(bool(spatial.queue_boss_path_query(open).get("ok", false)), "Boss kernel: open barrier query rejected")
	_expect(world.step_tick().ok, "Boss kernel: open barrier fixed tick failed")
	var open_batch: Dictionary = combat.last_boss_batch
	_expect((open_batch.get("outcomes", []) as Array).size() == 1, "Boss kernel: open barrier did not resolve damage")
	_expect(target.health.compare(health_before) < 0 and target.alive, "Boss kernel: open barrier damage was not committed")


func _test_fail_closed_damage_boundary() -> void:
	var invalid_milli: BossDamageValue = BossDamageValueScript.from_milli(-1)
	_expect(invalid_milli == null, "Boss kernel: negative milli damage was accepted")
	var invalid_query := BossQueryScript.make(ranger, "boss/small", SpatialChannels.PROJECTILE, Vector2(20.0, 60.0), Vector2(10.0, 0.0), 0.0, false, "arrow/invalid", null)
	_expect(not bool(spatial.queue_boss_path_query(invalid_query).get("ok", false)), "Boss kernel: missing typed damage payload fell back")
	var unbound_spatial: RoomSpatialPort = RoomSpatialPortScript.new()
	_expect(String(unbound_spatial.queue_boss_path_query(invalid_query).get("error", "")) == "boss_domain_unbound", "Boss kernel: unbound spatial port did not fail closed")


func _teardown() -> void:
	for mounted: SimulationWorld in worlds:
		if mounted != null and mounted.kernel != null:
			mounted.kernel.shutdown()
	worlds.clear()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
