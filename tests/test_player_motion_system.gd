extends SceneTree

const State := preload("res://src/runtime/world/player_combat_state.gd")
const Registry := preload("res://src/runtime/world/actor_registry.gd")
const World := preload("res://src/runtime/world/simulation_world.gd")
const Motion := preload("res://src/systems/player_motion_system.gd")
const Rules := preload("res://src/systems/player_combat_rules.gd")
const Stream := preload("res://src/systems/combat_event_stream.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var registry := Registry.new()
	registry.configure("motion-room", 2)
	registry.register_actor("ranger", Vector2(10, 20), 14.0)
	var world := World.new()
	world.configure(30, "motion-room", 2)
	var state := State.new()
	state.reset_for_room({"skills": ["piercing_arrow", "hunter_mark", "dash"], "talent_capabilities": {"dash_duration_multiplier": 0.5}}, registry, "ranger", world.tick)
	var stream := Stream.new()
	var rules := Rules.new()
	rules.configure(state, world, stream)
	var motor := Motion.new()
	world.step()
	_expect(motor.advance_player(state, world, world.tick, Vector2.RIGHT).ok, "real world tick move failed")
	var position := state.position()
	_expect(is_equal_approx(position.x - 10.0, 245.0 / 30.0), "normal movement distance changed")
	var duplicate := motor.advance_player(state, world, world.tick, Vector2.LEFT)
	_expect(not duplicate.ok and duplicate.error == "non_monotonic_motor_tick" and state.position() == position, "same-tick move was not rejected without mutation")
	_expect(motor.advance_player(state, world, world.tick + 1, Vector2.RIGHT).error == "uncommitted_world_tick", "motor forged next tick")
	# Use a fresh domain for an actual rules tick; no test mutates a clock counter.
	registry.reset_actors()
	registry.register_actor("ranger", Vector2(10, 20), 14.0)
	state.reset_for_room({"skills": ["piercing_arrow", "hunter_mark", "dash"], "talent_capabilities": {"dash_duration_multiplier": 0.5}}, registry, "ranger", world.tick)
	rules.configure(state, world, stream)
	_expect(rules.request_cast(world.tick, "dash", 0, Vector2.LEFT).accepted, "dash rejected")
	_expect(state.snapshot(world.tick).dash_remaining_ticks == 9, "dash talent duration changed")
	var origin := state.position()
	for index: int in range(9):
		world.step()
		var step := rules.advance_tick(world.tick, {}, [])
		_expect(step.ok, "dash tick failed")
	# Legacy pre-tick decrement means casting between ticks traverses 8 steps;
	# normal runtime casts inside advance_tick and traverses all 9 steps.
	_expect(is_equal_approx(origin.x - state.position().x, 160.0), "dash motor distance did not respect scaled duration")
	var ended := stream.latest("displacement_ended")
	_expect(ended.kind == "dash" and ended.actual_to == state.position(), "dash completion event lost actual registry position")
	registry.reset_actors()
	registry.register_actor("ranger", Vector2.ZERO, 14.0)
	state.reset_for_room({}, registry, "ranger", world.tick)
	rules.configure(state, world, stream)
	world.step()
	_expect(rules.advance_tick(world.tick, {}, []).ok, "stationary tick failed")
	_expect(motor.advance_player(state, world, world.tick, Vector2.RIGHT).error == "non_monotonic_motor_tick", "stationary tick allowed a second motion submission")
	for failure: String in failures: printerr("FAIL: " + failure)
	if failures.is_empty(): print("PLAYER_MOTION_SYSTEM_PASS")
	quit(0 if failures.is_empty() else 1)


func _expect(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
