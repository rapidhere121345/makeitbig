extends SceneTree

const Simulation := preload("res://src/systems/combat_simulation.gd")
const State := preload("res://src/runtime/world/player_combat_state.gd")
const Registry := preload("res://src/runtime/world/actor_registry.gd")
const World := preload("res://src/runtime/world/simulation_world.gd")
const Rules := preload("res://src/systems/player_combat_rules.gd")
const Stream := preload("res://src/systems/combat_event_stream.gd")
const Protocol := preload("res://src/systems/combat_command_protocol.gd")

var failures: Array[String] = []
var world := World.new()
var state := State.new()
var events: Array[String] = []
var elapsed := -1.0
var first_slice: Dictionary = {}


func _initialize() -> void:
	var registry := Registry.new()
	registry.configure("simulation-room", 2)
	registry.register_actor("ranger", Vector2.ZERO, 14)
	world.configure(30, "simulation-room", 2)
	state.reset_for_room({}, registry, "ranger", world.tick)
	var rules := Rules.new()
	rules.configure(state, world, Stream.new())
	var simulation := Simulation.new()
	var callbacks := {}
	for name: String in Simulation.REQUIRED_CALLBACKS:
		callbacks[name] = Callable(self, name)
	_expect(simulation.configure(world, rules, callbacks).ok, "simulation configure failed")
	var result := simulation.step()
	_expect(result.ok and result.tick == 1 and world.tick == 1, "simulation did not commit one real world tick")
	_expect(is_equal_approx(elapsed, 1.0 / 30.0), "elapsed time diverged from world")
	_expect(events == ["elapsed", "targets", "player_pre", "room", "hazards", "collect", "route", "targets", "player_post", "enemies", "projectiles", "hits", "end", "timeout"], "room/player phase order changed: " + str(events))
	_expect(first_slice.player_position == Vector2.ZERO and result.player_step.player.player_position.x > 0.0, "pre/post player snapshots did not bracket movement")
	_expect(state.snapshot(world.tick).attack_cooldown_ticks == 13, "simulation did not execute domain action")
	_expect(registry.actor("ranger").last_motor_tick == world.tick, "motion used a second authority tick")
	_expect(not Simulation.new().configure(world, rules, {}).ok, "missing room callbacks accepted")
	_expect(not Simulation.new().step().ok, "unconfigured simulation stepped")
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


func _expect(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
