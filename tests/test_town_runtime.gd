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
const Assert := preload("res://tests/helpers/assert.gd")
## Generated whole-object town: authored ground footprints are final movement
## geometry — projected visual height is walkable behind. The motor adds the
## six-pixel hero footprint once; the whole visual pair/detection is unchanged.
const OBSOLETE_LOADOUT_BLOCKERS: Array[String] = ["loadout_west_wall", "loadout_back_wall", "loadout_crates", "loadout_roof", "contract_roof", "forge_west_roof", "water_north_bridge", "water_south_bridge", "south_bank_seal"]
const TREE_SOUTH_FOOTPRINT := Rect2(972.0, 719.0, 26.0, 24.0)
const SPAWN := Vector2(576.0, 595.3125)
const LOADOUT_FACILITY_FEET := Vector2(711.0, 284.0625)
const RESIDENT_FEET := {"iven": Vector2(278.0, 300.9375), "taren": Vector2(719.0, 255.0), "oren": Vector2(1065.0, 340.3125),
	"leia": Vector2(344.0, 538.125), "mira": Vector2(1260.0, 452.8125)}
const LOADOUT_ROUTE: Array[Vector2] = [Vector2(576.0, 595.3125), Vector2(510.0, 496.875), Vector2(570.0, 375.0), Vector2(661.0, 298.125), Vector2(711.0, 284.0625)]
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
		_expect(town.hero_world_position() == SPAWN, "fresh mounted hero left the published spawn: %s" % town.hero_world_position())
		_test_old_travel_rejected(town)
		_test_routes(town)
		_test_travel(town)
		_test_perimeter_contact(town)
		_test_generated_layout(town, controller)
		_test_behind_projected_art(town)
		_test_expansion(town)
		_test_house_tree_wedge()
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

func _fixture(custom_surfaces: Array = [], spawn: Vector2 = Vector2(180.0, 150.0), world_size: Array = [500, 500]):
	var spatial_port := RoomSpatialPortScript.new()
	var simulation := SimulationWorldScript.new(spatial_port)
	var configured: SimOutcome = simulation.configure("town/test", 0, 30)
	_expect(configured.ok, "town fixture: simulation configuration failed")
	_worlds.append(simulation)
	var static_build: Dictionary = StaticSpatialIndexScript.build({
		"schema_version": StaticSpatialIndexScript.SCHEMA_VERSION,
		"asset_id": "test/town",
		"surfaces": custom_surfaces if not custom_surfaces.is_empty() else [{
			"id": "wall",
			"shape": {"kind": "rect", "rect": Rect2(200.0, 100.0, 40.0, 240.0)},
			"channels": [SpatialChannelsScript.MOVEMENT],
			"opaque": true,
			"vision_mode": "opaque",
			"attenuation": 0.0,
			"occlusion_rank": 0,
		}],
		"movement_boundary": {"kind": "rect", "rect": Rect2(Vector2.ZERO, Vector2(world_size[0], world_size[1]))},
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
	var registered: Dictionary = registry.register_actor(TownRuntimeScript.HERO_ID, spawn, 6.0)
	_expect(bool(registered.get("ok", false)), "town fixture: hero registration failed")
	var town := TownRuntimeScript.new()
	town.configure(simulation, registry, {"world_size": world_size})
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

## A saved travel position that was floor before the Loadout footprint (750,230
## is inside it now) must fail through restore_travel on a FRESH mounted town:
## expected failure, no partial commit, the hero stays on the published spawn.
func _test_old_travel_rejected(town) -> void:
	var spawn: Vector2 = town.hero_world_position()
	_expect(spawn == SPAWN, "fresh town is not at the published spawn: %s" % spawn)
	var before: Dictionary = town.travel_snapshot()
	for former_floor: Vector2 in [Vector2(711.0, 190.0), Vector2(985.0, 731.0)]:
		var stale := before.duplicate(true)
		stale.position = former_floor
		var restored: Dictionary = town.restore_travel(stale)
		_expect(not bool(restored.get("ok", true)), "former-floor travel position %s was restored: %s" % [former_floor, str(restored)])
		_expect(town.hero_world_position() == spawn, "rejected travel moved the hero off the spawn: %s" % town.hero_world_position())
		_expect(town.travel_snapshot() == before, "rejected travel partially committed state")
	_expect(town.hero_position_is_clear(town.hero_world_position()), "the retained spawn is not legal floor")
	print("TOWN_STALE_TRAVEL rejected spawn=%s" % spawn)


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

## Invisible perimeter contact uses the same authoritative sweep/slide path as
## objects: walking into the south limit stops, tangent motion slides, and
## reversing escapes without a teleport or an invalid committed tick.
func _test_perimeter_contact(town) -> void:
	var bounds: Rect2 = town.world_bounds()
	var start := Vector2(1470, bounds.end.y - 44)
	var previous: Vector2 = town.hero_world_position()
	_expect(not town.place_hero(Vector2(1470, bounds.end.y + 1)).ok, "outside map edge accepted")
	_expect(town.hero_world_position() == previous, "rejected edge placement moved the hero")
	_expect(town.place_hero(start).ok, "perimeter approach start blocked")
	town.submit_move(Vector2.DOWN)
	for tick in 40:
		_expect(town.step_tick().ok and town.hero_position_is_clear(town.hero_world_position()), "perimeter approach penetrated")
	var contact: Vector2 = town.hero_world_position()
	_expect(absf(contact.y - bounds.end.y) < 0.1, "perimeter blocked at wrong hero center: %s bounds=%s" % [contact, bounds])
	town.submit_move(Vector2(1, 1))
	for tick in 6:
		_expect(town.step_tick().ok and town.hero_position_is_clear(town.hero_world_position()), "perimeter tangent penetrated")
	_expect(town.hero_world_position().x > contact.x + 8, "perimeter tangent stuck")
	town.submit_move(Vector2.UP)
	for tick in 6:
		_expect(town.step_tick().ok and town.hero_position_is_clear(town.hero_world_position()), "perimeter reversal penetrated")
	_expect(town.hero_world_position().y < contact.y - 8, "perimeter reversal stuck")
	print("TOWN_PERIMETER contact=%s escape=%s" % [contact, town.hero_world_position()])


func _test_generated_layout(town, controller) -> void:
	var ids: Array[String] = controller.scene_runtime.static_spatial_index.surface_ids(SpatialChannelsScript.MOVEMENT)
	for obsolete: String in OBSOLETE_LOADOUT_BLOCKERS:
		for id: String in ids:
			_expect(not id.begins_with("town/static/%s" % obsolete), "obsolete illustration collision survived: " + id)
	var envelope_ids: Array = ids.filter(func(id: String) -> bool: return id.begins_with("town/static/loadout_envelope"))
	_expect(envelope_ids.size() == 2, "one ground-footprint rect must derive as two triangles")
	var radius: float = town.registry.actor(TownRuntimeScript.HERO_ID).footprint_radius
	var saved: Vector2 = town.hero_world_position()
	for blocked: Vector2 in [Vector2(711, 190), Vector2(711, 200), Vector2(760, 215)]:
		_expect(not town.place_hero(blocked).ok and town.hero_world_position() == saved, "blocked shop placement moved the hero")
	var pine_center_x := TREE_SOUTH_FOOTPRINT.get_center().x
	var pine_top := TREE_SOUTH_FOOTPRINT.position.y
	_expect(not town.hero_position_is_clear(Vector2(pine_center_x, pine_top - radius + 1)), "pine trunk footprint is smaller than its rect")
	_expect(town.hero_position_is_clear(Vector2(pine_center_x, pine_top - radius - 1)), "pine footprint inflated hero radius twice")
	_expect(town.place_hero(Vector2(pine_center_x, pine_top - 22)).ok, "pine trunk approach start rejected")
	town.submit_move(Vector2.DOWN)
	for tick in 40:
		_expect(town.step_tick().ok and town.hero_position_is_clear(town.hero_world_position()), "pine trunk contact penetrated")
	var pine_contact: Vector2 = town.hero_world_position()
	_expect(absf(pine_contact.y - (pine_top - radius)) < 0.1, "pine trunk face contact incorrect")
	town.submit_move(Vector2.UP)
	for tick in 6:
		_expect(town.step_tick().ok and town.hero_position_is_clear(town.hero_world_position()), "pine trunk reversal penetrated")
	_expect(town.hero_world_position().y < pine_contact.y - 8, "pine trunk reversal stuck")
	## Loadout is a re-oriented diagonal hall: approach each front face along
	## its inward normal and stop exactly one hero radius from the authored
	## footprint polygon, then reverse.
	var authored: Node = (load("res://content/rooms/town/hearthside.tscn") as PackedScene).instantiate()
	var hall: PackedVector2Array = (authored.get_node("GeometrySources/Static/loadout_envelope") as Polygon2D).polygon
	authored.free()
	for face: int in hall.size():
		var a: Vector2 = hall[face]
		var b: Vector2 = hall[(face + 1) % hall.size()]
		var middle := a.lerp(b, 0.5)
		var outward := (b - a).orthogonal().normalized()
		if Geometry2D.is_point_in_polygon(middle + outward, hall):
			outward = -outward
		if outward.y <= 0.0:
			continue
		var start := middle + outward * 26.0
		_expect(town.place_hero(start).ok, "shop footprint approach start blocked")
		town.submit_move(-outward)
		for tick in 60:
			_expect(town.step_tick().ok and town.hero_position_is_clear(town.hero_world_position()), "shop footprint contact penetrated")
		var stopped: Vector2 = town.hero_world_position()
		var gap := stopped.distance_to(Geometry2D.get_closest_point_to_segment(stopped, a, b))
		_expect(absf(gap - radius) < 0.1, "shop footprint face incorrect: %s gap=%f" % [stopped, gap])
		town.submit_move(outward)
		for tick in 6:
			_expect(town.step_tick().ok, "shop face reversal rejected")
		_expect(town.hero_world_position().distance_to(stopped) > 8.0, "shop face reversal stuck")
	town.submit_move(Vector2.ZERO)
	_expect(town.place_hero(SPAWN).ok, "published spawn became blocked")
	_expect(town.entry_for("loadout").feet == LOADOUT_FACILITY_FEET, "Loadout interaction socket moved")
	var residents: Dictionary = town.resident_positions()
	for id: String in RESIDENT_FEET:
		_expect(residents.has(id) and (residents[id] as Vector2).is_equal_approx(RESIDENT_FEET[id]), "resident socket moved: " + id)
		var actor = town.registry.actor("town/npc/" + id)
		_expect(actor != null and town.registry.is_position_clear(actor.feet_position, Rect2(), actor.footprint_radius), "enlarged geometry overlaps resident: " + id)
	_expect(town.route_points("loadout") == LOADOUT_ROUTE, "Loadout route changed")
	for facility: String in TownRuntimeScript.FACILITY_IDS:
		_expect(is_equal_approx(float(town.entry_for(facility).radius), 48.0), "facility interaction reach changed: " + facility)
	print("TOWN_GENERATED_LAYOUT loadout_hall=%s pine_contact=%s" % [hall, pine_contact])


## 2.5D traversal: projected visual height is walkable. Every case crosses a
## row that sat INSIDE the retired whole-image envelope yet above the authored
## ground footprint — the hero must move continuously through it, never enter
## the footprint itself, and escape again by reversing or rounding the corner.
func _test_behind_projected_art(town) -> void:
	## Stand rows visually reviewed inside the old occupied envelopes, all
	## clear of the authored footprints by more than the hero radius.
	for row: Dictionary in [
		{"id": "contract", "feet": Vector2(283, 280), "stand": Vector2(283, 206), "sweep": [Vector2(230, 206), Vector2(336, 206)]},
		{"id": "loadout", "feet": Vector2(711, 238), "solid": Vector2(711, 190), "stand": Vector2(711, 140), "sweep": [Vector2(650, 124), Vector2(770, 124)]},
		{"id": "forge", "feet": Vector2(1107, 310), "solid": Vector2(1107, 284), "stand": Vector2(1091, 175), "sweep": [Vector2(1000, 178), Vector2(1200, 178)]},
		{"id": "proxy", "feet": Vector2(1390, 440), "stand": Vector2(1390, 377), "sweep": [Vector2(1297, 377), Vector2(1455, 377)]},
		{"id": "tree_south", "feet": Vector2(985, 738), "stand": Vector2(985, 700), "sweep": [Vector2(950, 700), Vector2(1020, 700)]},
		{"id": "lamp_0", "feet": Vector2(410, 265), "stand": Vector2(410, 235), "sweep": [Vector2(370, 235), Vector2(450, 235)]},
	]:
		_expect(bool(town.place_hero(row.stand).ok), "%s: stand behind projected art rejected" % row.id)
		town.submit_move(Vector2.ZERO)
		var start: Vector2 = row.sweep[0]
		var finish: Vector2 = row.sweep[1]
		_expect(bool(town.place_hero(start).ok), "%s: behind-art sweep start rejected" % row.id)
		town.submit_move(Vector2.RIGHT)
		for tick in 200:
			_expect(town.step_tick().ok and town.hero_position_is_clear(town.hero_world_position()), "%s: behind-art sweep penetrated" % row.id)
			if town.hero_world_position().x >= finish.x:
				break
		var crossed: Vector2 = town.hero_world_position()
		_expect(crossed.x >= finish.x - 0.01 and absf(crossed.y - start.y) < 0.01, "%s: hero cannot walk continuously behind the object (stuck at %s)" % [row.id, crossed])
		town.submit_move(Vector2.LEFT)
		for tick in 200:
			_expect(town.step_tick().ok and town.hero_position_is_clear(town.hero_world_position()), "%s: behind-art return penetrated" % row.id)
			if town.hero_world_position().x <= start.x:
				break
		var returned: Vector2 = town.hero_world_position()
		_expect(returned.x <= start.x + 0.01 and absf(returned.y - start.y) < 0.01, "%s: behind-art reversal did not escape (stopped at %s)" % [row.id, returned])
		## The ground footprint itself stays solid from every side.
		_expect(not town.place_hero(row.get("solid", row.feet)).ok, "%s: ground footprint interior walkable" % row.id)
		print("TOWN_BEHIND %s sweep=%s..%s PASS" % [row.id, start, finish])
	## Rounding a corner: diagonal into the loadout footprint's bottom-left
	## corner slides along the faces instead of wedging or penetrating, and
	## the reverse diagonal escapes.
	_expect(bool(town.place_hero(Vector2(560, 250)).ok), "corner approach start blocked")
	town.submit_move(Vector2(1, -1).normalized())
	for tick in 90:
		_expect(town.step_tick().ok and town.hero_position_is_clear(town.hero_world_position()), "corner rounding penetrated")
	var cornered: Vector2 = town.hero_world_position()
	_expect(cornered.x > 560 or cornered.y < 250, "corner approach made no progress: %s" % cornered)
	town.submit_move(Vector2(-1, 1).normalized())
	for tick in 90:
		_expect(town.step_tick().ok and town.hero_position_is_clear(town.hero_world_position()), "corner reversal penetrated")
	_expect(town.hero_world_position().distance_to(cornered) > 8, "corner reversal stuck at %s" % town.hero_world_position())
	town.submit_move(Vector2.ZERO)
	print("TOWN_CORNER diagonal=%s reverse=%s PASS" % [cornered, town.hero_world_position()])


const LAYOUT_PATH := "res://docs/art-production/world-expansion-20261025/town_layout.json"

## Drives the hero toward target through the authority motor; every tick must
## stay legal. Returns the final position (stops early when blocked).
func _drive(town, target: Vector2, ticks: int) -> Vector2:
	for tick in ticks:
		var offset: Vector2 = target - town.hero_world_position()
		if offset.length() < 0.02:
			break
		town.submit_move(offset / (town.HERO_SPEED / 30.0) if offset.length() < town.HERO_SPEED / 30.0 else offset.normalized())
		_expect(town.step_tick().ok and town.hero_position_is_clear(town.hero_world_position()), "expansion drive penetrated at %s" % town.hero_world_position())
	town.submit_move(Vector2.ZERO)
	return town.hero_world_position()


## World expansion acceptance driven by the reviewed recipe geometry: both
## bridges cross continuously in both directions, open water and cliffs
## reject placement, deck rails/banks/gate towers stop the hero and reversal
## escapes, and the gate arch is walkable underneath its projected art.
func _test_expansion(town) -> void:
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_PATH))
	var saved: Vector2 = town.hero_world_position()
	for crossing: Dictionary in layout.probes.crossings:
		var north := Vector2(float(crossing.path[0][0]), float(crossing.path[0][1]))
		var south := Vector2(float(crossing.path[-1][0]), float(crossing.path[-1][1]))
		_expect(town.place_hero(north).ok, "%s: north landing blocked" % crossing.id)
		_expect(_drive(town, south, 400).distance_to(south) < 0.05, "%s: cannot cross north->south (stopped %s)" % [crossing.id, town.hero_world_position()])
		_expect(_drive(town, north, 400).distance_to(north) < 0.05, "%s: cannot cross south->north (stopped %s)" % [crossing.id, town.hero_world_position()])
		## Off the deck sideways is water: perpendicular pushes stop at the
		## rail line and reversal returns onto the deck.
		var middle := north.lerp(south, 0.5)
		var side := (south - north).orthogonal().normalized()
		for direction: Vector2 in [side, -side]:
			_expect(not town.place_hero(middle + direction * 40.0).ok, "%s: water beside deck accepted" % crossing.id)
			_expect(town.place_hero(middle).ok, "%s: deck middle blocked" % crossing.id)
			var stopped := _drive(town, middle + direction * 40.0, 60)
			_expect(stopped.distance_to(middle) > 4.0 and stopped.distance_to(middle) < 30.0, "%s: rail contact wrong at %s" % [crossing.id, stopped])
			_expect(_drive(town, middle, 60).distance_to(middle) < 0.05, "%s: rail reversal stuck" % crossing.id)
		print("TOWN_BRIDGE %s two-way PASS" % crossing.id)
	for point: Array in layout.probes.blocked:
		_expect(not town.place_hero(Vector2(float(point[0]), float(point[1]))).ok, "water/cliff/wall probe accepted %s" % [point])
	for point: Array in layout.probes.clear:
		_expect(town.place_hero(Vector2(float(point[0]), float(point[1]))).ok, "clear probe rejected %s" % [point])
	## North bank contact into open water, then reverse.
	_expect(town.place_hero(Vector2(1000, 700)).ok, "bank approach start blocked")
	var bank := _drive(town, Vector2(1000, 860), 90)
	_expect(bank.y > 705.0 and bank.y < 830.0 and bank.distance_to(Vector2(1000, 860)) > 40.0, "bank contact wrong at %s" % bank)
	_expect(_drive(town, Vector2(1000, 700), 90).distance_to(Vector2(1000, 700)) < 0.05, "bank reversal stuck")
	## Expedition gate: walk under the arch to the map edge and back; the
	## tower plinth stops a hero walking straight into it.
	var gate: Dictionary = {}
	for item: Dictionary in layout.placements:
		if item.name == "gate_expedition":
			gate = item
	var gate_feet := Vector2(float(gate.feet[0]), float(gate.feet[1]))
	var arch_north := gate_feet + Vector2(-1, -80)
	var arch_south := gate_feet + Vector2(-1, -22)
	_expect(town.place_hero(arch_north).ok, "gate approach blocked")
	_expect(_drive(town, arch_south, 120).distance_to(arch_south) < 0.05, "gate arch passage blocked at %s" % town.hero_world_position())
	_expect(_drive(town, arch_north, 120).distance_to(arch_north) < 0.05, "gate arch reversal stuck")
	var tower_start := gate_feet + Vector2(-60, -90)
	_expect(town.place_hero(tower_start).ok, "tower approach blocked")
	var tower := _drive(town, tower_start + Vector2(0, 80), 90)
	_expect(tower.y < gate_feet.y - 50.0, "gate tower footprint missing at %s" % tower)
	_expect(_drive(town, tower_start, 90).distance_to(tower_start) < 0.05, "gate tower reversal stuck")
	## Behind a south wall: projected parapet is walkable, the base is not.
	_expect(town.place_hero(Vector2(500, 860)).ok, "behind-wall start blocked")
	_expect(_drive(town, Vector2(650, 860), 200).distance_to(Vector2(650, 860)) < 0.05, "cannot walk behind wall art")
	_expect(not town.place_hero(Vector2(575, 893)).ok, "wall base walkable")
	_expect(town.place_hero(saved).ok, "saved position lost")
	print("TOWN_EXPANSION bridges/water/gate/wall PASS")


func _expect(condition: bool, message: String) -> void: Assert.expect(condition, message, failures)

## Captured regression: the house slope leads into the pine's rounded corner.
## Retain the historical geometry after the town cleanup removes this wedge.
## These are the original padded plinth and trunk, triangulated then snapped
## exactly like the native scene derivative. The real command/motor path runs.
## Repeated contact must remain a legal next-tick start, and allow reversal.
func _historical_wedge_surfaces() -> Array:
	var surfaces: Array = []
	var outlines: Array = [
		PackedVector2Array([Vector2(54.3536, 871.4132), Vector2(157.9362, 841.8182), Vector2(285.8286, 874.9754), Vector2(182.0513, 902.1552)]),
		PackedVector2Array([Vector2(177, 811), Vector2(203, 811), Vector2(203, 835), Vector2(177, 835)]),
	]
	for outline_index in outlines.size():
		var outline: PackedVector2Array = outlines[outline_index]
		var indices := Geometry2D.triangulate_polygon(outline)
		for triangle in range(0, indices.size(), 3):
			var points := PackedVector2Array()
			for corner in 3:
				points.append(outline[indices[triangle + corner]].snapped(Vector2.ONE / 64.0))
			surfaces.append({"id": "%s/%03d" % ["house_south_west_footprint_0" if outline_index == 0 else "tree_southwest_envelope", triangle / 3],
				"shape": {"kind": "polygon", "points": points}, "channels": [SpatialChannelsScript.MOVEMENT],
				"opaque": true, "vision_mode": "opaque", "attenuation": 0.0, "occlusion_rank": 0})
	return surfaces

func _test_house_tree_wedge() -> void:
	var town = _fixture(_historical_wedge_surfaces(), Vector2(90, 846), [1536, 960])
	var start := Vector2(90.0, 846.0)
	var target := Vector2(170.026, 872.3854)
	_expect(bool(town.place_hero(start).get("ok", false)), "house/tree wedge: clear start placement failed")
	_expect(not town.hero_position_is_clear(target), "house/tree wedge: fixture target must be solid")
	for tick in 96:
		var before: Vector2 = town.hero_world_position()
		_expect(bool(town.submit_move((target - before).normalized()).get("ok", false)), "house/tree wedge: move rejected")
		_expect(bool(town.step_tick().get("ok", false)), "house/tree wedge: step rejected")
		_expect(town.hero_position_is_clear(town.hero_world_position()), "house/tree wedge: invalid endpoint at tick %d: %s" % [tick, town.hero_world_position()])
	var contact: Vector2 = town.hero_world_position()
	_expect(contact.distance_to(start) > 50.0 and contact.distance_to(target) > 6.0, "house/tree wedge: failed to approach solid contact")
	var reverse: Vector2 = (start - contact).normalized()
	for tick in 40:
		town.submit_move(reverse)
		town.step_tick()
		_expect(town.hero_position_is_clear(town.hero_world_position()), "house/tree wedge: reverse endpoint invalid")
	_expect(town.hero_world_position().distance_to(contact) > 30.0, "house/tree wedge: contact trapped hero on reversal")
	town.submit_move(Vector2.ZERO)
	town.step_tick()
	print("TOWN_WEDGE repeated_contact=96 reverse=40 clear=", town.hero_position_is_clear(town.hero_world_position()))
