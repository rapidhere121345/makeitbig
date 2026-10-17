extends SceneTree

## Focused integration for the room combat seam: a real RoomSpatialPort writes
## only SimHit facts, RoomCombatPort applies resistance and resolved health, and
## the fixed death phase settles one encounter notification for one lethal key.

const Fixtures := preload("res://tests/spatial/spatial_fixtures.gd")
const StaticSpatialIndexScript := preload("res://src/runtime/spatial/static_spatial_index.gd")
const DynamicSpatialIndexScript := preload("res://src/runtime/spatial/dynamic_spatial_index.gd")
const MovementResolverScript := preload("res://src/runtime/spatial/movement_resolver.gd")
const RoomSpatialPortScript := preload("res://src/runtime/world/room_spatial_port.gd")
const RoomCombatPortScript := preload("res://src/runtime/world/room_combat_port.gd")
const RoomHitAdmissionPortScript := preload("res://src/runtime/combat/room_hit_admission_port.gd")
const RoomEncounterPortScript := preload("res://src/runtime/world/room_encounter_port.gd")
const RoomActorAccessScript := preload("res://src/runtime/world/room_actor_access.gd")
const SimulationWorldScript := preload("res://src/runtime/world/simulation_world.gd")
const DeathSettlementNotificationScript := preload("res://src/runtime/combat/death_settlement_notification.gd")
const SpatialChannels := preload("res://src/runtime/spatial/spatial_channels.gd")

## Explicit harness cleanup: shutdown severs the kernel -> port -> access ->
## registry borrow cycle so the engine exits without leaking the room graph.
var _worlds: Array[SimulationWorld] = []


class FakeEncounter:
	var deaths: Array[Dictionary] = []

	func step(_tick: int) -> Variant:
		return null

	func notify_death(entity_key: String, tick: int) -> void:
		deaths.append({"entity_key": entity_key, "tick": tick})


class FakePlayerRules:
	var calls: Array[Dictionary] = []

	func apply_damage(tick: int, amount: float, source_id: String, source_position: Vector2) -> Dictionary:
		calls.append({"tick": tick, "amount": amount, "source_id": source_id, "source_position": source_position})
		return {"accepted": true, "status": "accepted", "reason": "ok"}


class AllowHitAdmission extends RoomHitAdmissionPortScript:
	func admit(_hit: Dictionary) -> Dictionary:
		return {"allowed": true, "reason": ""}


func _initialize() -> void:
	var failures: Array[String] = []
	var static_build: Dictionary = StaticSpatialIndexScript.build(Fixtures.open_world())
	_expect(bool(static_build.get("ok", false)), "room combat: static fixture failed", failures)
	if not failures.is_empty():
		_finish(failures)
		return
	var static_index: StaticSpatialIndex = static_build["value"]
	var dynamic_index := DynamicSpatialIndexScript.new()
	var movement_build: Dictionary = MovementResolverScript.make(static_index, null, dynamic_index)
	_expect(bool(movement_build.get("ok", false)), "room combat: movement resolver failed", failures)
	if not failures.is_empty():
		_finish(failures)
		return
	var spatial := RoomSpatialPortScript.new()
	var combat := RoomCombatPortScript.new()
	var encounter_port := RoomEncounterPortScript.new()
	var world := SimulationWorldScript.new(spatial, combat, encounter_port, null)
	_worlds.append(world)
	_expect(world.configure("room-combat-test", 3, 30).ok, "room combat: simulation configure failed", failures)
	var access := RoomActorAccessScript.new()
	var access_result: Dictionary = access.configure(world, world.actor_registry, static_index, dynamic_index, movement_build["value"], null)
	_expect(bool(access_result.get("ok", false)), "room combat: actor access configure failed", failures)
	if not failures.is_empty():
		_finish(failures)
		return
	spatial.bind(access)
	combat.bind(access)
	var encounter := FakeEncounter.new()
	encounter_port.bind(encounter)
	var player_rules := FakePlayerRules.new()
	var player_bound: Dictionary = combat.bind_player_rule_port(player_rules)
	_expect(bool(player_bound.get("ok", false)), "room combat: typed player rule port rejected", failures)
	var admission_bound: Dictionary = combat.bind_hit_admission_port(AllowHitAdmission.new())
	_expect(bool(admission_bound.get("ok", false)), "room combat: typed hit admission port rejected", failures)

	var source_result: Dictionary = access.register_actor("ranger", Vector2(20.0, 60.0), 5.0, 1, &"soft", [SpatialChannels.MOVEMENT])
	var target_result: Dictionary = access.register_actor(
		"slime", Vector2(60.0, 60.0), 5.0, 100, &"soft", [SpatialChannels.MOVEMENT, SpatialChannels.HURTBOX], PackedStringArray(), 100.0, {"physical": 0.25}, "slime", "wave.01/slime/0", ["equipment.common"]
	)
	_expect(bool(source_result.get("ok", false)) and bool(target_result.get("ok", false)), "room combat: actor registration failed", failures)
	if failures.is_empty():
		var hostile_queued: Dictionary = spatial.queue_player_hit(
			access.actor_handle("ranger"), 1200, "enemy/1/melee_pursuer", Vector2(12.0, 60.0), "7", &"hostile_attack"
		)
		_expect(bool(hostile_queued.get("ok", false)), "room combat: hostile player contact was rejected", failures)
		_expect(world.step_tick().ok, "room combat: hostile contact tick failed", failures)
		var hostile_receipts: Array[Dictionary] = combat.commit_player_contacts(world.tick)
		_expect(hostile_receipts.size() == 1 and player_rules.calls.size() == 1, "room combat: hostile contact did not settle exactly once", failures)
		if hostile_receipts.size() == 1 and player_rules.calls.size() == 1:
			_expect(is_equal_approx(float(player_rules.calls[0].amount), 1.2) and String(player_rules.calls[0].source_id) == "enemy/1/melee_pursuer" and String(hostile_receipts[0].attack_instance_id) == "7", "room combat: hostile source or milli damage was changed at the player boundary", failures)
		_expect(combat.commit_player_contacts(world.tick).is_empty(), "room combat: player contact receipt was applied twice", failures)
		var duplicate_hostile: Dictionary = spatial.queue_player_hit(
			access.actor_handle("ranger"), 1200, "enemy/1/melee_pursuer", Vector2(12.0, 60.0), "7", &"hostile_attack"
		)
		_expect(bool(duplicate_hostile.get("ok", false)), "room combat: duplicate contact fixture could not be staged", failures)
		_expect(world.step_tick().ok, "room combat: duplicate hostile tick failed", failures)
		_expect(combat.commit_player_contacts(world.tick).is_empty() and player_rules.calls.size() == 1, "room combat: repeated hostile attack identity settled twice", failures)

		# The typed port rejects deaths for actors that were never adopted into
		# the encounter. Register this direct harness member explicitly so the
		# death assertion exercises settlement rather than the adoption guard.
		encounter_port.bind_entity(access.actor_handle("slime"), "actor/2")
		var source: SimEntityHandle = access.actor_handle("ranger")
		var query := RoomSpatialPortScript.PathQuery.make(source, SpatialChannels.PROJECTILE, Vector2(30.0, 60.0), Vector2(40.0, 0.0), 0.0, 40, &"projectile", false, "arrow/1", "core", "core", "physical", 2)
		_expect(bool(spatial.queue_path_query(query).get("ok", false)), "room combat: first path query rejected", failures)
		_expect(world.step_tick().ok, "room combat: first tick failed", failures)
		var target = access.actor("slime")
		_expect(target != null and is_equal_approx(target.health, 70.0) and target.alive, "room combat: resistance was not applied to resolved health", failures)
		_expect(combat.last_batch.get("outcomes", []).size() == 1, "room combat: first hit did not produce one outcome", failures)
		if combat.last_batch.get("outcomes", []).size() == 1:
			var first_outcome: Dictionary = combat.last_batch.outcomes[0]
			_expect(String(first_outcome.get("attack_instance_id", "")) == "arrow/1" and String(first_outcome.get("part_id", "")) == "core", "room combat: typed attack facts were lost at the spatial seam", failures)

		var second_query := RoomSpatialPortScript.PathQuery.make(source, SpatialChannels.PROJECTILE, Vector2(30.0, 60.0), Vector2(40.0, 0.0), 0.0, 100, &"projectile")
		_expect(bool(spatial.queue_path_query(second_query).get("ok", false)), "room combat: lethal path query rejected", failures)
		_expect(world.step_tick().ok, "room combat: lethal tick failed", failures)
		_expect(encounter.deaths.size() == 1, "room combat: encounter received duplicate or missing death notification", failures)
		if encounter.deaths.size() == 1:
			_expect(String(encounter.deaths[0].entity_key) == "actor/2", "room combat: death notification lost stable entity key", failures)
		_expect(encounter_port.received_typed_death_notifications.size() == 1, "room combat: kernel death crossed the encounter port without a typed notification", failures)
		if encounter_port.received_typed_death_notifications.size() == 1:
			var typed_notification: Variant = encounter_port.received_typed_death_notifications[0]
			_expect(typed_notification is DeathSettlementNotificationScript and typed_notification.entity_key == "actor/2" and typed_notification.world_revision == 3, "room combat: typed death notification lost room identity", failures)
		_expect(combat.last_settlements.size() == 1, "room combat: DeathSettlement did not settle exactly once", failures)
		_expect(not access.has_actor("slime") and access.dynamic_index.body("slime").is_empty(), "room combat: dead actor remained in live/dynamic indexes", failures)

	_finish(failures)


func _finish(failures: Array[String]) -> void:
	for world in _worlds:
		if world != null and world.kernel != null:
			world.kernel.shutdown()
	_worlds.clear()
	if failures.is_empty():
		print("PASS test_room_combat_port.gd")
	else:
		for failure: String in failures:
			printerr("- %s" % failure)
		print("FAIL test_room_combat_port.gd")
	quit(0 if failures.is_empty() else 1)


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
