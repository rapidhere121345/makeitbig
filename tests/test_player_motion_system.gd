extends SceneTree

## Player motion authority regression over the typed simulation stack:
## ActorState, SimulationWorld, RoomActorAccess, SimCommand and the shared
## MovementResolver. Headless, no GPU harness:
##   godot --headless --path . --script res://tests/test_player_motion_system.gd

const State := preload("res://src/runtime/world/player_combat_state.gd")
const Rules := preload("res://src/systems/player_combat_rules.gd")
const Stream := preload("res://src/systems/combat_event_stream.gd")
const SimulationWorldScript := preload("res://src/runtime/world/simulation_world.gd")
const RoomActorAccessScript := preload("res://src/runtime/world/room_actor_access.gd")
const RoomSpatialPortScript := preload("res://src/runtime/world/room_spatial_port.gd")
const StaticSpatialIndexScript := preload("res://src/runtime/spatial/static_spatial_index.gd")
const DynamicSpatialIndexScript := preload("res://src/runtime/spatial/dynamic_spatial_index.gd")
const SpatialOverlayScript := preload("res://src/runtime/spatial/spatial_overlay.gd")
const MovementResolverScript := preload("res://src/runtime/spatial/movement_resolver.gd")
const SimCommandScript := preload("res://src/runtime/simulation/sim_command.gd")
const Assert := preload("res://tests/helpers/assert.gd")

const PLAYER_SPEED := 245.0
const TICK_DISPLACEMENT := PLAYER_SPEED / 30.0
const MOVE_START := Vector2(200.0, 200.0)
const DASH_START := Vector2(600.0, 300.0)
const STATIONARY_START := Vector2(300.0, 300.0)

var failures: Array[String] = []
## Worlds mounted by this harness; shutdown severs the kernel -> port ->
## access -> registry borrow cycle so the engine exits without room-graph leaks.
var _worlds: Array = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_typed_motor_submission()
	_test_dash_duration_event_and_stationary_tick()
	for world in _worlds:
		if world != null and world.kernel != null:
			world.kernel.shutdown()
	_worlds.clear()
	for failure: String in failures: printerr("FAIL: " + failure)
	if failures.is_empty(): print("PLAYER_MOTION_SYSTEM_PASS")
	quit(0 if failures.is_empty() else 1)


func _expect(condition: bool, message: String) -> void: Assert.expect(condition, message, failures)


func _make_typed_room() -> Dictionary:
	var spatial_port = RoomSpatialPortScript.new()
	var world = SimulationWorldScript.new(spatial_port)
	var configured: SimOutcome = world.configure("motion-room", 2, 30)
	_expect(configured.ok, "simulation world configuration failed")
	_worlds.append(world)
	var static_build: Dictionary = StaticSpatialIndexScript.build({
		"schema_version": StaticSpatialIndexScript.SCHEMA_VERSION,
		"asset_id": "test/motion-room",
		"surfaces": [],
		"movement_boundary": {"kind": "rect", "rect": Rect2(0.0, 0.0, 1600.0, 900.0)},
	})
	_expect(bool(static_build.get("ok", false)), "static spatial index rejected the open room")
	var dynamic = DynamicSpatialIndexScript.new()
	var overlay = SpatialOverlayScript.new()
	var resolver_build: Dictionary = MovementResolverScript.make(static_build.get("value"), overlay, dynamic)
	_expect(bool(resolver_build.get("ok", false)), "movement resolver rejected the open room")
	var access = RoomActorAccessScript.new()
	var access_result: Dictionary = access.configure(world, world.actor_registry, static_build.get("value"), dynamic, resolver_build.get("value"), overlay)
	_expect(bool(access_result.get("ok", false)), "room actor access rejected the typed room")
	spatial_port.bind(access)
	return {"world": world, "access": access}


func _test_typed_motor_submission() -> void:
	var room := _make_typed_room()
	var world = room.world
	var access = room.access
	var registered: Dictionary = access.register_actor("ranger", MOVE_START, 14.0)
	_expect(bool(registered.get("ok", false)), "typed room rejected the ranger registration")
	var state: ActorState = access.actor("ranger")
	_expect(state != null and state.feet_position == MOVE_START, "actor state did not start at its authored pose")
	# The kernel is the only tick authority: movement enters as a typed CONTROL
	# command and commits exactly once through the room's MovementResolver.
	var queued: SimOutcome = world.queue_command(SimCommandScript.control(state.get_entity_handle(), Vector2.RIGHT * TICK_DISPLACEMENT, false))
	_expect(queued.ok, "typed CONTROL command was rejected")
	var stepped: SimOutcome = world.step_tick()
	_expect(stepped.ok and world.tick == 1, "kernel tick did not advance exactly once")
	_expect(is_equal_approx(state.feet_position.x - MOVE_START.x, TICK_DISPLACEMENT), "normal movement distance changed")
	_expect(state.feet_position.y == MOVE_START.y and state.velocity.is_equal_approx(Vector2.RIGHT * TICK_DISPLACEMENT) and state.facing.is_equal_approx(Vector2.RIGHT), "actor state kinematics did not commit the displacement")
	_expect(state.last_movement_tick == 1, "actor state lost its committed motor tick")
	# One motor submission per tick: a same-tick resubmission is refused
	# without mutating the committed record.
	var duplicate: Dictionary = access.move_actor("ranger", Vector2.LEFT * TICK_DISPLACEMENT, world.tick)
	_expect(not duplicate.ok and state.feet_position == MOVE_START + Vector2.RIGHT * TICK_DISPLACEMENT, "same-tick move was not rejected without mutation")
	# Gameplay cannot act on a tick the world has not committed.
	var player_state = State.new()
	var reset: Dictionary = player_state.reset_for_room({"skills": ["piercing_arrow", "hunter_mark", "dash"], "talent_capabilities": {"dash_duration_multiplier": 0.5}}, access, "ranger", world.tick)
	_expect(bool(reset.get("ok", false)), "player state rejected the typed room")
	var stream := Stream.new()
	var rules := Rules.new()
	_expect(bool(rules.configure(player_state, world, stream).get("ok", false)), "player rules rejected the typed room")
	_expect(not rules.advance_tick(world.tick + 1, {}, []).ok, "motor forged next tick")


func _test_dash_duration_event_and_stationary_tick() -> void:
	var room := _make_typed_room()
	var world = room.world
	var access = room.access
	var registered: Dictionary = access.register_actor("ranger", DASH_START, 14.0)
	_expect(bool(registered.get("ok", false)), "dash room rejected the ranger registration")
	var player_state = State.new()
	var reset: Dictionary = player_state.reset_for_room({"skills": ["piercing_arrow", "hunter_mark", "dash"], "talent_capabilities": {"dash_duration_multiplier": 0.5}}, access, "ranger", world.tick)
	_expect(bool(reset.get("ok", false)), "dash setup rejected the typed room")
	var stream := Stream.new()
	var rules := Rules.new()
	_expect(bool(rules.configure(player_state, world, stream).get("ok", false)), "dash rules rejected the typed room")
	_expect(rules.request_cast(world.tick, "dash", 0, Vector2.LEFT).accepted, "dash rejected")
	_expect(player_state.snapshot(world.tick).dash_remaining_ticks == 9, "dash talent duration changed")
	var origin: Vector2 = player_state.position()
	for index: int in range(9):
		var stepped: SimOutcome = world.step_tick()
		_expect(stepped.ok, "dash kernel tick failed")
		var step: Dictionary = rules.advance_tick(world.tick, {}, [])
		_expect(bool(step.get("ok", false)), "dash tick failed")
	# The cast lands between ticks: begin_tick decrements the mobility counter
	# before the first dash step, so the traversal is duration-1 displacements.
	_expect(is_equal_approx(origin.x - player_state.position().x, 160.0), "dash motor distance did not respect scaled duration")
	var ended: Dictionary = stream.latest("displacement_ended")
	_expect(String(ended.get("kind", "")) == "dash" and ended.get("actual_to", Vector2.ZERO) == player_state.position(), "dash completion event lost actual registry position")
	# One motor submission per real world tick, including a stationary tick.
	_expect(bool(access.reset_actors().get("ok", false)), "actor reset failed before the stationary phase")
	_expect(bool(access.register_actor("ranger", STATIONARY_START, 14.0).get("ok", false)), "stationary registration failed")
	var fresh_state = State.new()
	_expect(bool(fresh_state.reset_for_room({}, access, "ranger", world.tick).get("ok", false)), "stationary state rejected the typed room")
	var stationary_rules := Rules.new()
	_expect(bool(stationary_rules.configure(fresh_state, world, Stream.new()).get("ok", false)), "stationary rules rejected the typed room")
	var idle_step: SimOutcome = world.step_tick()
	_expect(idle_step.ok, "stationary kernel tick failed")
	_expect(stationary_rules.advance_tick(world.tick, {}, []).ok, "stationary tick failed")
	var stationary_state: ActorState = access.actor("ranger")
	_expect(stationary_state.last_movement_tick == world.tick and stationary_state.feet_position == STATIONARY_START, "stationary tick did not commit an exactly-once zero displacement")
	var resubmission: Dictionary = access.move_actor("ranger", Vector2.RIGHT * TICK_DISPLACEMENT, world.tick)
	_expect(not resubmission.ok, "stationary tick allowed a second motion submission")
