extends SceneTree
const TownControllerScript := preload("res://src/runtime/world/town_controller.gd")
const TownRuntimeScript := preload("res://src/runtime/world/town_runtime.gd")
const SimulationWorldScript := preload("res://src/runtime/world/simulation_world.gd")
const RoomActorAccessScript := preload("res://src/runtime/world/room_actor_access.gd")
const RoomSpatialPortScript := preload("res://src/runtime/world/room_spatial_port.gd")
const StaticSpatialIndexScript := preload("res://src/runtime/spatial/static_spatial_index.gd")
const DynamicSpatialIndexScript := preload("res://src/runtime/spatial/dynamic_spatial_index.gd")
const SpatialOverlayScript := preload("res://src/runtime/spatial/spatial_overlay.gd")
const MovementResolverScript := preload("res://src/runtime/spatial/movement_resolver.gd")
const SpatialChannelsScript := preload("res://src/runtime/spatial/spatial_channels.gd")
var failures: Array[String] = []
## Kernel graphs created by this harness; shutdown severs the kernel -> port
## -> access -> registry borrow cycle so the engine exits without leaking
## the town fixtures' room graphs.
var _worlds: Array = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_fixed_commands()
	var controller := TownControllerScript.new()
	root.add_child(controller)
	var loaded := controller.mount(controller)
	_expect(bool(loaded.get("ok", false)), "native mount: " + str(loaded))
	if bool(loaded.get("ok", false)):
		var town = controller.town
		_expect(town.registry == controller.scene_runtime.actor_registry and town.simulation == controller.scene_runtime.simulation, "injected authority changed identity")
		_expect(town.hero_position_is_clear(town.hero_world_position()), "native spawn blocked")
		_test_routes(town)
		_test_travel(town)
		print("TOWN_NATIVE ready blockers=%d native=%d" % [controller.scene_runtime.static_spatial_index.surface_ids(SpatialChannelsScript.MOVEMENT).size(), controller.scene_runtime.presenter.sort_root.get_child_count()])
	if controller.scene_runtime != null and controller.scene_runtime.simulation != null and controller.scene_runtime.simulation.kernel != null:
		controller.scene_runtime.simulation.kernel.shutdown()
	controller.free()
	for failure: String in failures:
		printerr(failure)
	for world in _worlds:
		if world != null and world.kernel != null:
			world.kernel.shutdown()
	_worlds.clear()
	print("TOWN_RUNTIME ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)

func _fixture():
	var spatial_port := RoomSpatialPortScript.new()
	var simulation := SimulationWorldScript.new(spatial_port)
	var configured: SimOutcome = simulation.configure("town/test", 0, 30)
	_expect(configured.ok, "town fixture: simulation configuration failed")
	_worlds.append(simulation)
	var static_build: Dictionary = StaticSpatialIndexScript.build({
		"schema_version": StaticSpatialIndexScript.SCHEMA_VERSION,
		"asset_id": "test/town",
		"surfaces": [{
			"id": "wall",
			"shape": {"kind": "rect", "rect": Rect2(200.0, 100.0, 40.0, 240.0)},
			"channels": [SpatialChannelsScript.MOVEMENT],
			"opaque": true,
			"vision_mode": "opaque",
			"attenuation": 0.0,
			"occlusion_rank": 0,
		}],
		"movement_boundary": {"kind": "rect", "rect": Rect2(0.0, 0.0, 500.0, 500.0)},
	})
	_expect(bool(static_build.get("ok", false)), "town fixture: static index rejected the room")
	var dynamic := DynamicSpatialIndexScript.new()
	var overlay := SpatialOverlayScript.new()
	var resolver_build: Dictionary = MovementResolverScript.make(static_build.get("value"), overlay, dynamic)
	_expect(bool(resolver_build.get("ok", false)), "town fixture: movement resolver rejected the room")
	var registry := RoomActorAccessScript.new()
	var access_result: Dictionary = registry.configure(simulation, simulation.actor_registry, static_build.get("value"), dynamic, resolver_build.get("value"), overlay)
	_expect(bool(access_result.get("ok", false)), "town fixture: room actor access rejected the room")
	spatial_port.bind(registry)
	var registered: Dictionary = registry.register_actor(TownRuntimeScript.HERO_ID, Vector2(180.0, 150.0), 6.0)
	_expect(bool(registered.get("ok", false)), "town fixture: hero registration failed")
	var town := TownRuntimeScript.new()
	town.configure(simulation, registry, {"world_size": [500, 500]})
	return town

func _test_fixed_commands() -> void:
	var expected: Array = []
	for hz: int in [30, 60, 144]:
		var town = _fixture()
		var trace: Array = []
		town.state_changed.connect(func(state: Dictionary): trace.append([state.tick, state.hero_position, state.hero_facing]))
		# Equal command windows, including wall contact, sliding and immediate
		# reversal, all execute 30 authority ticks per second of display time.
		for direction: Vector2 in [Vector2(1, 1), Vector2.UP, Vector2.LEFT, Vector2.DOWN]:
			town.submit_move(direction)
			for frame: int in hz:
				town.advance_frame(1.0 / float(hz))
		_expect(town.simulation.tick == 120 and trace.size() == 120, "fixed tick count differs at %d" % hz)
		if expected.is_empty(): expected = trace
		else: _expect(trace == expected, "whole command trace differs at %d Hz" % hz)
		_expect(town.hero_position_is_clear(town.hero_world_position()), "contact/reverse penetrated at %d Hz" % hz)
		print("TOWN_TRACE hz=%d ticks=%d final=%s identical=%s" % [hz, town.simulation.tick, town.hero_world_position(), trace == expected])
	var town = _fixture()
	town.submit_move(Vector2.RIGHT)
	for tick: int in 20: town.step_tick()
	_expect(absf(town.hero_world_position().x - 194) < 0.001, "wall edge incorrect")
	var edge: Vector2 = town.hero_world_position()
	town.submit_move(Vector2.UP)
	town.step_tick()
	_expect(town.hero_world_position().x == edge.x and town.hero_world_position().y < edge.y, "wall tangent stuck")
	town.submit_move(Vector2.LEFT)
	town.step_tick()
	_expect(town.hero_world_position().x < edge.x, "reverse stuck at wall")
	var before: Vector2 = town.hero_world_position()
	town.submit_move(Vector2.ZERO)
	town.step_tick()
	_expect(town.hero_world_position() == before and not town.snapshot().hero_moving, "released move retained velocity")
	print("TOWN_EDGE slide/reverse/release PASS")

func _test_routes(town) -> void:
	var spawn: Vector2 = town.hero_world_position()
	for id: String in town._content.routes:
		town.registry.teleport_actor(TownRuntimeScript.HERO_ID, spawn)
		if id in TownRuntimeScript.FACILITY_IDS: town.select_destination(id)
		var progress := 0
		for target: Vector2 in town.route_points(id):
			var steps := 0
			while town.hero_world_position().distance_to(target) > 0.02 and steps < 1000:
				var offset: Vector2 = target - town.hero_world_position()
				town.submit_move(offset / (town.HERO_SPEED / 30.0))
				town.step_tick()
				steps += 1
			_expect(town.hero_world_position().distance_to(target) < 0.05, "route blocked: %s %s" % [id, target])
			_expect(town.hero_position_is_clear(town.hero_world_position()), "route position invalid:" + id)
			if id in TownRuntimeScript.FACILITY_IDS:
				var cursor := int(town.destination_guide().route_segment)
				_expect(cursor >= progress, "route guide regressed:" + id)
				progress = cursor
		print("TOWN_ROUTE %s reached cursor=%d" % [id, progress])

func _test_travel(town) -> void:
	town.select_destination("contract")
	var point: Vector2 = town.entry_for("contract").feet + Vector2(0, 16)
	_expect(bool(town.place_hero(point).get("ok", false)), "travel test approach blocked")
	var travel: Dictionary = town.travel_snapshot()
	var pos: Vector2 = town.hero_world_position()
	town.select_destination("forge")
	_expect(bool(town.restore_travel(travel).ok) and town.travel_snapshot() == travel, "travel position/facing/destination/cursor failed roundtrip")
	var invalid := travel.duplicate(true)
	invalid.position = Vector2(-100, -100)
	_expect(not town.restore_travel(invalid).ok and town.hero_world_position() == pos, "bad travel was accepted or partially committed")
	print("TOWN_TRAVEL atomic roundtrip PASS")

func _expect(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
