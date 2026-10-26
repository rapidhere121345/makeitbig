extends SceneTree

## Dedicated lifecycle regression for the fixed-tick kernel teardown contract.
##
## Run: godot --headless --path . --script res://tests/test_kernel_lifecycle.gd
## Covers: shutdown safety before configuration, fail-closed semantics after
## teardown, port-borrow severance, and proof that the kernel -> port ->
## registry borrow cycle actually frees the whole room graph once shutdown()
## has run — including the production RoomSpatialPort/RoomActorAccess chain.

const SimKernelScript = preload("res://src/runtime/simulation/sim_kernel.gd")
const SimCommandScript = preload("res://src/runtime/simulation/sim_command.gd")
const SimEntityHandleScript = preload("res://src/runtime/simulation/sim_entity_handle.gd")
const WorldFactory = preload("res://tests/simulation/sim_test_world_factory.gd")
const Assert := preload("res://tests/helpers/assert.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_shutdown_before_configuration_is_safe_and_idempotent()
	_test_shutdown_fails_the_kernel_and_store_closed()
	_test_shutdown_severs_the_borrow_cycle_and_frees_the_room_graph()
	_test_shutdown_severs_the_production_port_chain_too()

	if failures.is_empty():
		print("PASS  test_kernel_lifecycle.gd")
		quit(0)
		return
	printerr("FAIL  test_kernel_lifecycle.gd")
	for failure in failures:
		printerr("- %s" % failure)
	quit(1)


func _test_shutdown_before_configuration_is_safe_and_idempotent() -> void:
	var kernel = SimKernelScript.new()
	kernel.shutdown()
	kernel.shutdown()
	_expect(not kernel.is_configured(), "shutdown must leave the kernel unconfigured", failures)
	var queued: SimOutcome = kernel.queue_command(SimCommandScript.control(SimEntityHandleScript.make(0, 1), Vector2.ZERO, false))
	_expect(not queued.ok and queued.error == &"kernel_not_configured",
		"shutdown must keep an unconfigured kernel fail-closed for commands", failures)


func _test_shutdown_fails_the_kernel_and_store_closed() -> void:
	var fixture: Dictionary = WorldFactory.make_world()
	var world = fixture["world"]
	var spawn: SimOutcome = world.actor_registry.spawn_actor(Vector2.ZERO, 0.5, WorldFactory.DEFAULT_ROOM, WorldFactory.DEFAULT_REVISION)
	_expect(spawn.ok, "lifecycle setup spawn must succeed: %s" % spawn.error, failures)
	_expect(world.kernel.step_tick().ok, "lifecycle setup tick must run", failures)

	world.kernel.shutdown()

	_expect(not world.kernel.is_configured(), "shutdown must retire the kernel", failures)
	_expect(world.kernel.spatial_port == null and world.kernel.combat_port == null \
			and world.kernel.encounter_port == null and world.kernel.presentation_port == null,
		"shutdown must sever every port borrow", failures)

	var tick: SimOutcome = world.kernel.step_tick()
	_expect(not tick.ok and tick.error == &"kernel_not_configured", "ticks after shutdown must fail closed", failures)
	var queued: SimOutcome = world.kernel.queue_command(SimCommandScript.control(spawn.handle, Vector2.ZERO, false))
	_expect(not queued.ok and queued.error == &"kernel_not_configured", "commands after shutdown must fail closed", failures)
	var stores: Array[SimEntityStore] = [world.actor_registry.store()]
	var reconfigured: SimOutcome = world.kernel.configure(WorldFactory.DEFAULT_ROOM, WorldFactory.DEFAULT_REVISION, 30, stores, world.actor_registry.store_id())
	_expect(not reconfigured.ok and reconfigured.error == &"kernel_shutdown", "reconfiguration after shutdown must fail closed", failures)
	world.kernel.set_ports(fixture["spatial"], fixture["combat"], fixture["encounter"], fixture["presentation"])
	_expect(world.kernel.spatial_port == null, "port rewiring after shutdown must be ignored", failures)

	var respawn: SimOutcome = world.actor_registry.spawn_actor(Vector2.ONE, 0.5, WorldFactory.DEFAULT_ROOM, WorldFactory.DEFAULT_REVISION)
	_expect(not respawn.ok and respawn.error == &"kernel_not_configured", "setup spawns after shutdown must fail closed", failures)
	var resolve: SimOutcome = world.actor_registry.resolve(spawn.handle)
	_expect(not resolve.ok, "resolving retired room storage must fail closed", failures)


func _test_shutdown_severs_the_borrow_cycle_and_frees_the_room_graph() -> void:
	var probe: Array = []
	_build_shutdown_probe(probe)
	_expect(probe.size() == 1 and probe[0] != null, "cycle probe must capture one weakref", failures)
	if probe.size() == 1 and probe[0] != null:
		_expect(probe[0].get_ref() == null,
			"shutdown must break the kernel -> port -> registry borrow cycle so the whole room graph frees", failures)


## Builds a full configured world with ports, shuts the kernel down, and leaves
## only a weakref behind. When this helper returns, its locals drop: without
## the severance the kernel -> port -> registry borrow loop keeps every object
## alive and the weakref never expires.
func _build_shutdown_probe(probe: Array) -> void:
	var fixture: Dictionary = WorldFactory.make_world()
	var world = fixture["world"]
	var kernel_object: Object = world.kernel
	var spawn: SimOutcome = world.actor_registry.spawn_actor(Vector2.ZERO, 0.5, WorldFactory.DEFAULT_ROOM, WorldFactory.DEFAULT_REVISION)
	if not spawn.ok:
		failures.append("cycle probe setup spawn failed: %s" % spawn.error)
	world.kernel.shutdown()
	probe.append(weakref(kernel_object))


## Same severance proof against the real production wiring: kernel ->
## RoomSpatialPort -> RoomActorAccess -> ActorRegistry -> kernel. Only weakrefs
## survive this helper; the chain must free once shutdown() severed it.
func _test_shutdown_severs_the_production_port_chain_too() -> void:
	var probe: Array = []
	_build_production_port_probe(probe)
	_expect(probe.size() == 2 and probe[0] != null and probe[1] != null,
		"production probe must capture kernel and port weakrefs", failures)
	if probe.size() == 2 and probe[0] != null and probe[1] != null:
		_expect(probe[0].get_ref() == null and probe[1].get_ref() == null,
			"shutdown must free the production RoomSpatialPort -> RoomActorAccess -> ActorRegistry chain", failures)


func _build_production_port_probe(probe: Array) -> void:
	var static_build: Dictionary = StaticSpatialIndex.build({
		"schema_version": StaticSpatialIndex.SCHEMA_VERSION,
		"asset_id": "lifecycle-probe-room",
		"surfaces": [],
		"movement_boundary": {"kind": "rect", "rect": Rect2(0.0, 0.0, 200.0, 200.0)},
	})
	if not bool(static_build["ok"]):
		failures.append("production probe static index failed: %s" % str(static_build["errors"]))
		return
	var static_index: StaticSpatialIndex = static_build["value"]
	var dynamic_index := DynamicSpatialIndex.new()
	var overlay := SpatialOverlay.new()
	var movement_build: Dictionary = MovementResolver.make(static_index, overlay, dynamic_index)
	if not bool(movement_build["ok"]):
		failures.append("production probe movement resolver failed")
		return

	var spatial_port := RoomSpatialPort.new()
	var registry := ActorRegistry.new()
	var world := SimulationWorld.new(spatial_port, RoomCombatPort.new(), RoomEncounterPort.new(), RoomPresentationPort.new(), registry)
	var configured: SimOutcome = world.configure("lifecycle-probe-room", 1, 30)
	if not configured.ok:
		failures.append("production probe configure failed: %s" % configured.error)
		return
	var access := RoomActorAccess.new()
	var access_result: Dictionary = access.configure(world, registry, static_index, dynamic_index, movement_build["value"], overlay)
	if not bool(access_result["ok"]):
		failures.append("production probe access failed: %s" % str(access_result["error"]))
		return
	spatial_port.bind(access)

	var kernel_object: Object = world.kernel
	var port_object: Object = spatial_port
	world.kernel.shutdown()
	probe.append(weakref(kernel_object))
	probe.append(weakref(port_object))


func _expect(condition: bool, message: String, failures_list: Array[String]) -> void: Assert.expect(condition, message, failures_list)
