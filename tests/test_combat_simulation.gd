extends SceneTree

## CombatSimulation orchestration regression over the typed kernel stack:
## SimulationWorld/SimKernel, RoomSpatialPort, RoomActorAccess,
## StaticSpatialIndex/DynamicSpatialIndex and the shared MovementResolver.
##   source scripts/project_env.sh
##   "$GODOT_BIN" --headless --path . --script res://tests/test_combat_simulation.gd

const Simulation := preload("res://src/systems/combat_simulation.gd")
const State := preload("res://src/runtime/world/player_combat_state.gd")
const World := preload("res://src/runtime/world/simulation_world.gd")
const Rules := preload("res://src/systems/player_combat_rules.gd")
const Stream := preload("res://src/systems/combat_event_stream.gd")
const Protocol := preload("res://src/systems/combat_command_protocol.gd")
const PhasePort := preload("res://tests/helpers/callable_combat_phase_port.gd")
const RoomSpatialPortScript := preload("res://src/runtime/world/room_spatial_port.gd")
const RoomActorAccessScript := preload("res://src/runtime/world/room_actor_access.gd")
const StaticSpatialIndexScript := preload("res://src/runtime/spatial/static_spatial_index.gd")
const DynamicSpatialIndexScript := preload("res://src/runtime/spatial/dynamic_spatial_index.gd")
const SpatialOverlayScript := preload("res://src/runtime/spatial/spatial_overlay.gd")
const MovementResolverScript := preload("res://src/runtime/spatial/movement_resolver.gd")
const Assert := preload("res://tests/helpers/assert.gd")

const SPAWN := Vector2(200.0, 200.0)

var failures: Array[String] = []
var world: SimulationWorld = null
var access: RoomActorAccess = null
var state := State.new()
var events: Array[String] = []
var elapsed := -1.0
var first_slice: Dictionary = {}


func _initialize() -> void:
	var spatial_port := RoomSpatialPortScript.new()
	world = World.new(spatial_port)
	_expect(world.configure("simulation-room", 2, 30).ok, "simulation world configuration failed")
	var static_build: Dictionary = StaticSpatialIndexScript.build({
		"schema_version": StaticSpatialIndexScript.SCHEMA_VERSION,
		"asset_id": "test/simulation-room",
		"surfaces": [],
		"movement_boundary": {"kind": "rect", "rect": Rect2(0.0, 0.0, 1600.0, 900.0)},
	})
	_expect(bool(static_build.get("ok", false)), "static spatial index rejected the simulation room")
	var dynamic := DynamicSpatialIndexScript.new()
	var overlay := SpatialOverlayScript.new()
	var resolver_build: Dictionary = MovementResolverScript.make(static_build.get("value"), overlay, dynamic)
	_expect(bool(resolver_build.get("ok", false)), "movement resolver rejected the simulation room")
	access = RoomActorAccessScript.new()
	_expect(bool(access.configure(world, world.actor_registry, static_build.get("value"), dynamic, resolver_build.get("value"), overlay).get("ok", false)), "room actor access rejected the typed room")
	spatial_port.bind(access)
	_expect(bool(access.register_actor("ranger", SPAWN, 14.0).get("ok", false)), "typed room rejected the ranger registration")
	_expect(bool(state.reset_for_room({}, access, "ranger", world.tick).get("ok", false)), "player state rejected the typed room")
	var rules := Rules.new()
	_expect(bool(rules.configure(state, world, Stream.new()).get("ok", false)), "rules configure failed")
	var simulation := Simulation.new()
	var callbacks := {}
	for name: String in PhasePort.REQUIRED:
		callbacks[name] = Callable(self, name)
	var phase_port = PhasePort.new()
	_expect(bool(phase_port.bind(callbacks).get("ok", false)), "phase port bind failed")
	_expect(simulation.configure(world, rules, phase_port).ok, "simulation configure failed")
	var result := simulation.step()
	_expect(result.ok and result.tick == 1 and world.tick == 1, "simulation did not commit one real world tick")
	_expect(is_equal_approx(elapsed, 1.0 / 30.0), "elapsed time diverged from world")
	_expect(events == ["elapsed", "targets", "player_pre", "room", "hazards", "collect", "route", "targets", "player_post", "enemies", "projectiles", "hits", "end", "timeout"], "room/player phase order changed: " + str(events))
	_expect(first_slice.player_position == SPAWN and result.player_step.player.player_position.x > SPAWN.x, "pre/post player snapshots did not bracket movement")
	_expect(state.snapshot(world.tick).attack_cooldown_ticks == 13, "simulation did not execute domain action")
	_expect(access.actor("ranger").last_movement_tick == world.tick, "motion used a second authority tick")
	_expect(not Simulation.new().configure(world, rules, {}).ok, "missing room callbacks accepted")
	_expect(not Simulation.new().step().ok, "unconfigured simulation stepped")
	# Explicit harness teardown: sever the kernel -> port -> access -> registry
	# borrow cycle so the room graph frees at exit.
	if world != null and world.kernel != null:
		world.kernel.shutdown()
	for failure: String in failures: printerr("FAIL: " + failure)
	if failures.is_empty(): print("COMBAT_SIMULATION_PASS")
	quit(0 if failures.is_empty() else 1)


func read_only_targets() -> Array[Dictionary]:
	events.append("targets")
	return [{"entity_id": 7, "kind_id": "grunt", "health": 100.0, "position": Vector2(100, 0), "is_boss": false}]


func set_elapsed(value: float) -> void:
	events.append("elapsed")
	elapsed = value


func consume_player_events(result: Dictionary) -> void:
	if not result.has("motion"):
		events.append("player_pre")
		first_slice = result.player
	else:
		events.append("player_post")


func update_room_rules() -> void: events.append("room")
func refresh_hazard_states() -> void: events.append("hazards")


func collect_commands() -> Array[Dictionary]:
	events.append("collect")
	return [Protocol.cast(world.tick, "ranger", 1, "piercing_arrow", 7, 1000, 0), Protocol.move(world.tick, "ranger", 2, 1000, 0, 1000)]


func route_commands(commands: Array) -> Dictionary:
	events.append("route")
	return Protocol.arbitrate(commands, world.tick, state.equipped_ability_ids())


func update_enemies() -> void: events.append("enemies")
func advance_projectiles() -> void: events.append("projectiles")
func resolve_hazard_hits() -> void: events.append("hits")
func check_battle_end() -> void: events.append("end")
func check_timeout() -> void: events.append("timeout")


func _expect(condition: bool, message: String) -> void: Assert.expect(condition, message, failures)
