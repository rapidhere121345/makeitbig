extends SceneTree

## Focused regression suite for the fixed-tick simulation kernel.
##
## Run: godot --headless --path . --script res://tests/test_simulation_kernel.gd
## Covers: fixed phase order, command ordering, deferred structural changes,
## generational handles, never-reused stable keys, stale-reference rejection,
## death settlement, and byte-stable snapshots.

const SimKernelScript = preload("res://src/runtime/simulation/sim_kernel.gd")
const SimTickPipelineScript = preload("res://src/runtime/simulation/sim_tick_pipeline.gd")
const SimCommandScript = preload("res://src/runtime/simulation/sim_command.gd")
const SimEntityHandleScript = preload("res://src/runtime/simulation/sim_entity_handle.gd")
const ActorStateScript = preload("res://src/runtime/world/actor_state.gd")
const WorldFactory = preload("res://tests/simulation/sim_test_world_factory.gd")

const EXPECTED_PHASES: Array[String] = [
	"begin_tick_read_view",
	"intent",
	"action_commit",
	"movement_boundary",
	"dynamic_index_refresh",
	"continuous_queries",
	"damage_status",
	"death_settlement",
	"structural_commit",
	"authoritative_snapshot",
]

var failures: Array[String] = []
## Every world created by this harness. Shutdown at the end of the run severs
## the kernel -> port -> registry borrow cycle so the engine exits without
## leaking the room graphs; this is explicit cleanup, not a suppressed warning.
var _fixtures: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_phase_contract_is_fixed()
	_test_kernel_fails_closed_before_configuration()
	_test_command_submission_order()
	_test_command_stamps_reject_stale_references()
	_test_deferred_spawn_and_despawn()
	_test_generation_invalidation_and_no_id_reuse()
	_test_death_settlement_tombstones_then_reclaims()
	_test_record_contract_enforced()
	_test_snapshot_byte_stability_and_key_ordering()
	_test_full_tick_with_fake_ports_without_main()
	_teardown_fixtures()

	if failures.is_empty():
		print("PASS  test_simulation_kernel.gd")
		quit(0)
		return
	printerr("FAIL  test_simulation_kernel.gd")
	for failure in failures:
		printerr("- %s" % failure)
	quit(1)


## Registers a world with the harness so its kernel can be torn down at the
## end of the run. Every fixture must come through here.
func _fixture() -> Dictionary:
	var fixture: Dictionary = WorldFactory.make_world()
	_fixtures.append(fixture)
	return fixture


func _teardown_fixtures() -> void:
	for fixture in _fixtures:
		var world = fixture.get("world")
		if world != null and world.kernel != null:
			world.kernel.shutdown()
	_fixtures.clear()


func _test_phase_contract_is_fixed() -> void:
	_expect(SimTickPipelineScript.PHASE_COUNT == 10, "pipeline must define exactly ten phases", failures)
	var names: Array[String] = []
	for phase_name in SimTickPipelineScript.PHASE_NAMES:
		names.append(String(phase_name))
	_expect(names == EXPECTED_PHASES, "phase names must match the contract order exactly", failures)

	var bare_world = SimKernelScript.new().step_tick()
	_expect(not bare_world.ok and bare_world.error == &"kernel_not_configured", "unconfigured kernel must refuse to tick", failures)

	var fixture := _fixture()
	var world = fixture["world"]
	var none = fixture["presentation"]
	none.snapshots.clear()
	var first: SimOutcome = world.step_tick()
	_expect(first.ok, "configured kernel must tick: %s" % first.error, failures)
	var snapshot = first.value
	_expect(snapshot.phase_trace.size() == 10, "tick trace must contain all ten phases", failures)
	for phase_index in EXPECTED_PHASES.size():
		_expect(String(snapshot.phase_trace[phase_index]) == EXPECTED_PHASES[phase_index],
			"phase %d must be %s" % [phase_index, EXPECTED_PHASES[phase_index]], failures)
	var second: SimOutcome = world.step_tick()
	_expect(second.value.phase_trace == snapshot.phase_trace, "phase order must be identical every tick", failures)


func _test_kernel_fails_closed_before_configuration() -> void:
	var kernel = SimKernelScript.new()
	var queued: SimOutcome = kernel.queue_command(SimCommandScript.control(SimEntityHandleScript.make(0, 1), Vector2.RIGHT, false))
	_expect(not queued.ok and queued.error == &"kernel_not_configured", "unconfigured kernel must reject commands", failures)

	var registry_alone = preload("res://src/runtime/world/actor_registry.gd").new()
	var early_spawn: SimOutcome = registry_alone.spawn_actor(Vector2.ZERO, 1.0, "room", 0)
	_expect(not early_spawn.ok and early_spawn.error == &"kernel_not_configured", "spawning before kernel attach must fail closed", failures)


func _test_command_submission_order() -> void:
	var fixture := _fixture()
	var world = fixture["world"]
	var spatial = fixture["spatial"]

	var first_record := ActorStateScript.create(Vector2.ZERO, 0.5, WorldFactory.DEFAULT_ROOM, WorldFactory.DEFAULT_REVISION, Vector2.DOWN, 5)
	var second_record := ActorStateScript.create(Vector2(10, 0), 0.5, WorldFactory.DEFAULT_ROOM, WorldFactory.DEFAULT_REVISION, Vector2.DOWN, 5)
	_expect(world.queue_command(SimCommandScript.spawn_entity(first_record)).ok, "spawn command one must enqueue", failures)
	_expect(world.queue_command(SimCommandScript.spawn_entity(second_record)).ok, "spawn command two must enqueue", failures)
	var tick_one: SimOutcome = world.step_tick()
	_expect(tick_one.ok, "tick one must run", failures)
	_expect(first_record.stable_key == 1 and second_record.stable_key == 2,
		"stable keys must follow command submission order (got %d, %d)" % [first_record.stable_key, second_record.stable_key], failures)

	_expect(world.queue_command(SimCommandScript.control(first_record.get_entity_handle(), Vector2(1, 0), false)).ok, "control one must enqueue", failures)
	_expect(world.queue_command(SimCommandScript.control(second_record.get_entity_handle(), Vector2(0, 1), false)).ok, "control two must enqueue", failures)
	_expect(world.queue_command(SimCommandScript.control(SimEntityHandleScript.make(99, 99), Vector2.ZERO, false)).ok, "stale control may enqueue and is dropped at commit", failures)
	var tick_two: SimOutcome = world.step_tick()
	_expect(tick_two.ok, "tick two must run", failures)
	_expect(spatial.movement_log == [[2, 1], [2, 2]],
		"control commands must commit in submission order and drop stale handles (got %s)" % str(spatial.movement_log), failures)

	var unknown := SimCommandScript.new()
	unknown.kind = 99
	var rejected: SimOutcome = world.queue_command(unknown)
	_expect(not rejected.ok and rejected.error == &"unknown_command_kind", "unknown command kinds must fail closed", failures)

	var late_record := ActorStateScript.create(Vector2(20, 0), 0.5, WorldFactory.DEFAULT_ROOM, WorldFactory.DEFAULT_REVISION, Vector2.DOWN, 5)
	world.queue_command(SimCommandScript.spawn_entity(late_record))
	world.step_tick()
	_expect(late_record.stable_key == 3, "stable keys must never repeat or regress (got %d)" % late_record.stable_key, failures)


func _test_command_stamps_reject_stale_references() -> void:
	var fixture := _fixture()
	var world = fixture["world"]

	var wrong_room := SimCommandScript.spawn_entity(ActorStateScript.create(Vector2.ZERO, 0.5, "r", 0))
	wrong_room.room_instance_id = "some-other-room"
	var room_result: SimOutcome = world.queue_command(wrong_room)
	_expect(not room_result.ok and room_result.error == &"stale_room_reference", "commands stamped with a foreign room must be rejected", failures)

	var wrong_revision := SimCommandScript.spawn_entity(ActorStateScript.create(Vector2.ZERO, 0.5, "r", 0))
	wrong_revision.world_revision = 999
	var revision_result: SimOutcome = world.queue_command(wrong_revision)
	_expect(not revision_result.ok and revision_result.error == &"stale_world_revision", "commands stamped with a stale revision must be rejected", failures)

	var wrong_store := SimCommandScript.spawn_entity(ActorStateScript.create(Vector2.ZERO, 0.5, "r", 0), &"no-such-store")
	_expect(world.queue_command(wrong_store).ok, "unknown store ids may enqueue", failures)
	var ticked: SimOutcome = world.step_tick()
	_expect(ticked.ok, "tick with unknown spawn store must still run", failures)
	_expect(ticked.value.entity_count() == 0, "spawn into an unknown store must not create entities", failures)
	_expect(world.kernel.tick_diagnostics.has(&"spawn_target_store_missing"), "dropped spawns must surface a diagnostic", failures)

	var reconfigured: SimOutcome = world.configure(WorldFactory.DEFAULT_ROOM, WorldFactory.DEFAULT_REVISION + 1, 30)
	_expect(reconfigured.ok, "reconfiguration to a new revision must succeed", failures)
	var old_revision_command := SimCommandScript.spawn_entity(ActorStateScript.create(Vector2.ZERO, 0.5, "r", 0))
	old_revision_command.world_revision = WorldFactory.DEFAULT_REVISION
	var stale_after_reconfigure: SimOutcome = world.queue_command(old_revision_command)
	_expect(not stale_after_reconfigure.ok, "commands from the previous revision must be rejected after reconfigure", failures)


func _test_deferred_spawn_and_despawn() -> void:
	var fixture := _fixture()
	var world = fixture["world"]
	var spatial = fixture["spatial"]

	var record := ActorStateScript.create(Vector2.ZERO, 0.5, WorldFactory.DEFAULT_ROOM, WorldFactory.DEFAULT_REVISION, Vector2.DOWN, 5)
	world.queue_command(SimCommandScript.spawn_entity(record))
	var tick_one: SimOutcome = world.step_tick()
	_expect(tick_one.ok, "tick one must run", failures)
	_expect(spatial.view_count_at_movement == [0], "spawn queued this tick must not be visible to tick one phases", failures)
	_expect(tick_one.value.entity_count() == 1,
		"structural commit precedes the snapshot phase, so tick one ends with the spawn applied", failures)

	var tick_two: SimOutcome = world.step_tick()
	_expect(tick_two.ok and tick_two.value.entity_count() == 1, "spawn must become authoritative at tick two", failures)
	var handle = record.get_entity_handle()
	_expect(handle.index == 0 and handle.generation == 1, "first spawn must occupy slot 0 generation 1", failures)

	world.queue_command(SimCommandScript.control(handle, Vector2(2, 0), false))
	world.queue_command(SimCommandScript.despawn_entity(handle))
	var tick_three: SimOutcome = world.step_tick()
	_expect(tick_three.ok, "tick three must run", failures)
	_expect(spatial.tombstoned_seen_during_movement == [record.stable_key],
		"despawned entity must be an inert tombstone by the movement phase", failures)
	_expect(tick_three.value.entity_count() == 0, "tick three snapshot must exclude the retired entity", failures)

	var tick_four: SimOutcome = world.step_tick()
	_expect(tick_four.ok and spatial.view_count_at_movement.back() == 0,
		"reclaimed storage must free the read view on the next tick", failures)
	_expect(record.stable_key == 1, "stable key remains owned by the retired entity", failures)


func _test_generation_invalidation_and_no_id_reuse() -> void:
	var fixture := _fixture()
	var world = fixture["world"]
	var registry = world.actor_registry

	var spawned: SimOutcome = registry.spawn_actor(Vector2.ZERO, 0.5, WorldFactory.DEFAULT_ROOM, WorldFactory.DEFAULT_REVISION)
	_expect(spawned.ok and spawned.handle.index == 0 and spawned.handle.generation == 1 and spawned.stable_key == 1,
		"setup spawn must allocate slot 0 gen 1 key 1", failures)
	var first_handle = spawned.handle
	_expect(first_handle.store_id == registry.store_id() and first_handle.room_instance_id == WorldFactory.DEFAULT_ROOM and first_handle.world_revision == WorldFactory.DEFAULT_REVISION,
		"spawned handle must carry store, room and revision scope", failures)
	var round_trip := SimEntityHandleScript.parse(first_handle.encode())
	_expect(round_trip.equals_handle(first_handle), "scoped handle encode/parse lost identity", failures)
	var foreign_room := SimEntityHandleScript.make(first_handle.index, first_handle.generation, registry.store_id(), "other-room", WorldFactory.DEFAULT_REVISION)
	var foreign_revision := SimEntityHandleScript.make(first_handle.index, first_handle.generation, registry.store_id(), WorldFactory.DEFAULT_ROOM, WorldFactory.DEFAULT_REVISION + 1)
	var foreign_store := SimEntityHandleScript.make(first_handle.index, first_handle.generation, &"other-store", WorldFactory.DEFAULT_ROOM, WorldFactory.DEFAULT_REVISION)
	_expect(not registry.resolve(foreign_room).ok and not registry.resolve(foreign_revision).ok and not registry.resolve(foreign_store).ok,
		"handles from another room, revision or store must fail closed", failures)

	world.queue_command(SimCommandScript.despawn_entity(first_handle))
	_expect(world.step_tick().ok, "despawn tick must run", failures)
	_expect(not registry.is_live(first_handle), "retired handle must not resolve live", failures)

	var respawned: SimOutcome = registry.spawn_actor(Vector2(5, 5), 0.5, WorldFactory.DEFAULT_ROOM, WorldFactory.DEFAULT_REVISION)
	_expect(respawned.ok, "respawn must succeed", failures)
	_expect(respawned.handle.index == 0, "free slot must be reused", failures)
	_expect(respawned.handle.generation == 2, "reused slot must bump the generation", failures)
	_expect(respawned.stable_key == 2, "stable key must never be reused", failures)

	var stale_resolve: SimOutcome = registry.resolve(first_handle)
	_expect(not stale_resolve.ok and stale_resolve.error == &"stale_entity_handle", "old-generation handles must fail closed", failures)
	var fresh_resolve: SimOutcome = registry.resolve(respawned.handle)
	_expect(fresh_resolve.ok and fresh_resolve.stable_key == 2, "current handles must resolve", failures)

	var stale_handle := SimEntityHandleScript.make(0, 1, registry.store_id(), WorldFactory.DEFAULT_ROOM, WorldFactory.DEFAULT_REVISION)
	var stale_after_reuse: SimOutcome = registry.resolve(stale_handle)
	_expect(not stale_after_reuse.ok and stale_after_reuse.error == &"stale_entity_handle", "explicitly stale handles must fail closed", failures)
	var invalid_handle := SimEntityHandleScript.make(41, 1)
	_expect(not registry.resolve(invalid_handle).ok, "out-of-range handles must fail closed", failures)
	_expect(world.kernel.next_stable_key() == 3, "kernel counter must stay above every issued key", failures)


func _test_death_settlement_tombstones_then_reclaims() -> void:
	var fixture := _fixture()
	var world = fixture["world"]
	var combat = fixture["combat"]
	var encounter = fixture["encounter"]

	var victim: SimOutcome = world.actor_registry.spawn_actor(Vector2.ZERO, 0.5, WorldFactory.DEFAULT_ROOM, WorldFactory.DEFAULT_REVISION, Vector2.DOWN, 3)
	var survivor: SimOutcome = world.actor_registry.spawn_actor(Vector2(50, 50), 0.5, WorldFactory.DEFAULT_ROOM, WorldFactory.DEFAULT_REVISION, Vector2.DOWN, 3)
	_expect(victim.ok and survivor.ok, "setup spawns must succeed", failures)
	combat.scheduled_damage[victim.stable_key] = 99

	var kill_tick: SimOutcome = world.step_tick()
	_expect(kill_tick.ok, "kill tick must run", failures)
	_expect(combat.damage_applied_total == 99, "combat port must have applied the scheduled damage", failures)
	_expect(encounter.deaths == [victim.stable_key], "death settlement must notify the encounter port once", failures)
	_expect(kill_tick.value.entity_count() == 1, "dead entity must leave the authoritative snapshot at settlement", failures)
	_expect(not world.actor_registry.is_live(victim.handle), "victim handle must be inert after settlement", failures)

	world.queue_command(SimCommandScript.control(victim.handle, Vector2(1, 0), false))
	var after_control: SimOutcome = world.step_tick()
	_expect(after_control.ok, "tick with tombstoned control must run", failures)
	var survivor_record: ActorState = world.actor_registry.resolve(survivor.handle).value
	_expect(survivor_record.feet_position == Vector2(50, 50), "survivor must be untouched by the dropped command", failures)
	_expect(world.kernel.tick_diagnostics.is_empty(), "dropped control for tombstoned entity is a silent no-op by contract", failures)
	_expect(encounter.deaths == [victim.stable_key], "death notification must fire exactly once", failures)


func _test_record_contract_enforced() -> void:
	var fixture := _fixture()
	var world = fixture["world"]
	world.queue_command(SimCommandScript.spawn_entity("not-a-record"))
	var ticked: SimOutcome = world.step_tick()
	_expect(ticked.ok, "tick with invalid record must still run", failures)
	_expect(ticked.value.entity_count() == 0, "invalid records must never enter the store", failures)
	_expect(world.kernel.tick_diagnostics.has(&"record_type_mismatch"), "invalid record spawn must surface a diagnostic", failures)


func _test_snapshot_byte_stability_and_key_ordering() -> void:
	var first := _fixture()
	var second := _fixture()
	for fixture in [first, second]:
		var world = fixture["world"]
		var a: SimOutcome = world.actor_registry.spawn_actor(Vector2(1.5, 2.5), 0.5, WorldFactory.DEFAULT_ROOM, WorldFactory.DEFAULT_REVISION, Vector2.DOWN, 4)
		var b: SimOutcome = world.actor_registry.spawn_actor(Vector2(-3.25, 0.75), 0.75, WorldFactory.DEFAULT_ROOM, WorldFactory.DEFAULT_REVISION, Vector2.UP, 6)
		fixture["encounter"].move_directions[a.stable_key] = Vector2(0.3, -0.1)
		fixture["encounter"].move_directions[b.stable_key] = Vector2(-0.2, 0.4)
		for _tick in 3:
			_expect(world.step_tick().ok, "determinism setup ticks must run", failures)
	var first_bytes: PackedByteArray = first["presentation"].snapshots[2].to_bytes()
	var second_bytes: PackedByteArray = second["presentation"].snapshots[2].to_bytes()
	_expect(first_bytes == second_bytes, "identical op sequences must produce byte-identical tick snapshots", failures)
	_expect(first["presentation"].snapshots[2].sha256_hex() == second["presentation"].snapshots[2].sha256_hex(),
		"snapshot hashes must match across identical worlds", failures)
	_expect(first["presentation"].snapshots[0].to_bytes() != first["presentation"].snapshots[2].to_bytes(),
		"snapshots must differ as state advances", failures)

	var scramble := _fixture()
	var world = scramble["world"]
	var issued: Array[int] = []
	for spawn_index in 3:
		var spawned: SimOutcome = world.actor_registry.spawn_actor(Vector2(spawn_index, 0), 0.5, WorldFactory.DEFAULT_ROOM, WorldFactory.DEFAULT_REVISION)
		issued.append(spawned.stable_key)
	var middle_handle: SimEntityHandle = world.actor_registry.actors_sorted_by_key()[1].get_entity_handle()
	var dead_key: int = world.actor_registry.resolve(middle_handle).stable_key
	world.queue_command(SimCommandScript.despawn_entity(middle_handle))
	_expect(world.step_tick().ok, "scramble despawn tick must run", failures)
	var replacement: SimOutcome = world.actor_registry.spawn_actor(Vector2(9, 9), 0.5, WorldFactory.DEFAULT_ROOM, WorldFactory.DEFAULT_REVISION)
	issued.append(replacement.stable_key)
	var replacement_two: SimOutcome = world.actor_registry.spawn_actor(Vector2(12, 12), 0.5, WorldFactory.DEFAULT_ROOM, WorldFactory.DEFAULT_REVISION)
	issued.append(replacement_two.stable_key)
	var final_tick: SimOutcome = world.step_tick()
	_expect(final_tick.ok, "scramble final tick must run", failures)
	var snapshot_keys: Array[int] = final_tick.value.stable_keys()
	var expected_keys := issued.duplicate()
	expected_keys.sort()
	expected_keys.erase(dead_key)
	_expect(snapshot_keys == expected_keys,
		"snapshot rows must order by stable key regardless of slot reuse (got %s want %s)" % [str(snapshot_keys), str(expected_keys)], failures)
	var view_keys: Array[int] = []
	for entity_view in world.build_detached_view().entities:
		view_keys.append(entity_view.stable_key)
	_expect(view_keys == expected_keys, "detached views must order by stable key", failures)


func _test_full_tick_with_fake_ports_without_main() -> void:
	var fixture := _fixture()
	var world = fixture["world"]
	var spatial = fixture["spatial"]
	var combat = fixture["combat"]
	var encounter = fixture["encounter"]
	var presentation = fixture["presentation"]

	var pursuer: SimOutcome = world.actor_registry.spawn_actor(Vector2.ZERO, 0.5, WorldFactory.DEFAULT_ROOM, WorldFactory.DEFAULT_REVISION, Vector2.DOWN, 2)
	var target: SimOutcome = world.actor_registry.spawn_actor(Vector2(0.8, 0.0), 0.5, WorldFactory.DEFAULT_ROOM, WorldFactory.DEFAULT_REVISION, Vector2.DOWN, 1)
	_expect(pursuer.ok and target.ok, "full-tick actors must spawn", failures)
	encounter.move_directions[pursuer.stable_key] = Vector2(1, 0)
	encounter.move_directions[target.stable_key] = Vector2(0, 0)

	for _tick in 4:
		_expect(world.step_tick().ok, "full-tick iterations must run", failures)

	_expect(presentation.snapshots.size() == 4, "presentation must receive one snapshot per tick", failures)
	_expect(spatial.refreshed_ticks == [1, 2, 3, 4], "dynamic index refresh must run every tick in order", failures)
	_expect(spatial.contact_hits_produced > 0, "continuous overlap query must produce contact hits", failures)
	_expect(combat.hits_resolved > 0, "combat port must resolve buffered hits", failures)
	_expect(encounter.deaths == [target.stable_key], "contact damage must settle the one-hit target", failures)
	_expect(world.kernel.tick_diagnostics.is_empty(), "clean full-tick run must produce no diagnostics", failures)

	var pursuer_record: ActorState = world.actor_registry.resolve(pursuer.handle).value
	_expect(pursuer_record.feet_position.x > 0.0, "encounter intent must have moved the pursuer", failures)
	_expect(pursuer_record.last_movement_tick == 4, "movement commits must be monotonic per tick", failures)

	var replay := _fixture()
	var replay_world = replay["world"]
	var rp: SimOutcome = replay_world.actor_registry.spawn_actor(Vector2.ZERO, 0.5, WorldFactory.DEFAULT_ROOM, WorldFactory.DEFAULT_REVISION, Vector2.DOWN, 2)
	var rt: SimOutcome = replay_world.actor_registry.spawn_actor(Vector2(0.8, 0.0), 0.5, WorldFactory.DEFAULT_ROOM, WorldFactory.DEFAULT_REVISION, Vector2.DOWN, 1)
	replay["encounter"].move_directions[rp.stable_key] = Vector2(1, 0)
	replay["encounter"].move_directions[rt.stable_key] = Vector2(0, 0)
	for _tick in 4:
		replay_world.step_tick()
	_expect(replay["presentation"].snapshots[3].to_bytes() == presentation.snapshots[3].to_bytes(),
		"the full fake-port run must be byte-reproducible without Main", failures)


func _expect(condition: bool, message: String, failures_list: Array[String]) -> void:
	if not condition:
		failures_list.append(message)
