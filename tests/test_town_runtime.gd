extends SceneTree
const TownControllerScript := preload("res://src/runtime/world/town_controller.gd")
const TownRuntimeScript := preload("res://src/runtime/world/town_runtime.gd")
const ActorRegistryScript := preload("res://src/runtime/world/actor_registry.gd")
const SimulationWorldScript := preload("res://src/runtime/world/simulation_world.gd")
var failures: Array[String] = []

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
		print("TOWN_NATIVE ready blockers=%d native=%d" % [town.registry.snapshot().blockers.size(), controller.scene_runtime.presenter.sort_root.get_child_count()])
	controller.free()
	for failure: String in failures:
		printerr(failure)
	print("TOWN_RUNTIME ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)

func _fixture():
	var registry := ActorRegistryScript.new()
	var simulation := SimulationWorldScript.new()
	registry.configure("town/test", 0)
	simulation.configure(30, "town/test", 0)
	registry.set_boundary({"type": "rect", "rect": Rect2(0, 0, 500, 500)})
	registry.register_rect("wall", Rect2(200, 100, 40, 240))
	registry.register_actor(TownRuntimeScript.HERO_ID, Vector2(180, 150), 6)
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
