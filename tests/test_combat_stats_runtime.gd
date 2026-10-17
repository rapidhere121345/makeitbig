extends SceneTree

## Combat stats runtime regression over the typed simulation stack:
## SimulationWorld/SimKernel, RoomSpatialPort, RoomActorAccess,
## StaticSpatialIndex/DynamicSpatialIndex and the shared MovementResolver.
##   source scripts/project_env.sh
##   "$GODOT_BIN" --headless --path . --script res://tests/test_combat_stats_runtime.gd

const State := preload("res://src/runtime/world/player_combat_state.gd")
const World := preload("res://src/runtime/world/simulation_world.gd")
const Rules := preload("res://src/systems/player_combat_rules.gd")
const Stream := preload("res://src/systems/combat_event_stream.gd")
const Protocol := preload("res://src/systems/combat_command_protocol.gd")
const RoomSpatialPortScript := preload("res://src/runtime/world/room_spatial_port.gd")
const RoomActorAccessScript := preload("res://src/runtime/world/room_actor_access.gd")
const StaticSpatialIndexScript := preload("res://src/runtime/spatial/static_spatial_index.gd")
const DynamicSpatialIndexScript := preload("res://src/runtime/spatial/dynamic_spatial_index.gd")
const SpatialOverlayScript := preload("res://src/runtime/spatial/spatial_overlay.gd")
const MovementResolverScript := preload("res://src/runtime/spatial/movement_resolver.gd")

const START := Vector2(10.0, 20.0)
const RADIUS := 14.0

var _failures: Array[String] = []
## Worlds mounted by this harness; shutdown severs the kernel -> port ->
## access -> registry borrow cycle so the engine exits without room-graph leaks.
var _worlds: Array = []


func _initialize() -> void:
	var slow := _session("slow", 72.0, 96.0, 6, 12, 30)
	var fast := _session("fast", 144.0, 192.0, 6, 7, 18)
	_expect(bool(slow.get("ok", false)) and bool(fast.get("ok", false)), "stats runtime: explicit combat sheets were rejected")
	if not bool(slow.get("ok", false)) or not bool(fast.get("ok", false)):
		_finish()
		return

	var slow_world: SimulationWorld = slow.world
	var fast_world: SimulationWorld = fast.world
	var slow_rules: Object = slow.rules
	var fast_rules: Object = fast.rules
	var no_targets: Array[Dictionary] = []
	slow_world.step_tick()
	fast_world.step_tick()
	var intent := {"movement": Vector2.RIGHT, "speed_scale": 1.0, "commands": [], "receipts": []}
	_expect(bool(slow_rules.advance_tick(slow_world.tick, intent, no_targets).get("ok", false)), "stats runtime: slow build movement tick failed")
	_expect(bool(fast_rules.advance_tick(fast_world.tick, intent, no_targets).get("ok", false)), "stats runtime: fast build movement tick failed")
	var slow_position: Vector2 = slow.state.position()
	var fast_position: Vector2 = fast.state.position()
	_expect(is_equal_approx(slow_position.x, 10.0 + 72.0 / 30.0), "stats runtime: slow move_speed was not consumed")
	_expect(is_equal_approx(fast_position.x, 10.0 + 144.0 / 30.0), "stats runtime: fast move_speed was not consumed")
	# The committed pose must be collision-safe under the room's shared
	# MovementResolver, which is the only movement boundary the typed room has.
	var slow_clear: Dictionary = (slow.resolver as MovementResolver).move({
		"start": slow_position,
		"displacement": Vector2.ZERO,
		"radius": RADIUS,
		"source_id": "ranger",
		"include_boundary": true,
		"include_dynamic": true,
	})
	_expect(fast_position.x > slow_position.x and bool(slow_clear.get("ok", false)) and not bool(slow_clear.get("blocked", true)), "stats runtime: same command did not produce two valid movement outcomes")

	# Flare-style resolved stats keep the movement model explicit. An authored
	# accelerated sheet ramps toward the same max speed on fixed ticks instead
	# of silently treating acceleration as dead content.
	var accelerated := _session("accelerated", 120.0, 96.0, 6, 12, 30, "accelerated", 60.0)
	_expect(bool(accelerated.get("ok", false)), "stats runtime: accelerated combat sheet was rejected")
	if bool(accelerated.get("ok", false)):
		var accelerated_world: SimulationWorld = accelerated.world
		var accelerated_rules: Object = accelerated.rules
		var accelerated_state: Object = accelerated.state
		accelerated_world.step_tick()
		_expect(bool(accelerated_rules.advance_tick(accelerated_world.tick, intent, no_targets).get("ok", false)), "stats runtime: accelerated first tick failed")
		var first_accelerated_position: Vector2 = accelerated_state.position()
		accelerated_world.step_tick()
		_expect(bool(accelerated_rules.advance_tick(accelerated_world.tick, intent, no_targets).get("ok", false)), "stats runtime: accelerated second tick failed")
		var second_accelerated_position: Vector2 = accelerated_state.position()
		_expect(second_accelerated_position.x > first_accelerated_position.x and first_accelerated_position.x > 10.0, "stats runtime: acceleration did not ramp committed movement")
		_expect(first_accelerated_position.x - 10.0 < 120.0 / 30.0, "stats runtime: accelerated first tick bypassed the acceleration limit")
		var accelerated_slice: Dictionary = accelerated_state.snapshot(accelerated_world.tick)
		_expect(String((accelerated_slice.get("combat_stats", {}) as Dictionary).get("movement_model", "")) == "accelerated", "stats runtime: movement model was lost in the detached sheet")
		_expect(float(accelerated_slice.get("player_velocity", Vector2.ZERO).x) > 0.0, "stats runtime: accelerated velocity was not retained in the room state")

	var slow_snapshot: Dictionary = slow.state.snapshot(slow_world.tick)
	_expect(bool(slow_snapshot.get("combat_stats", {}).get("move_speed", 0.0) == 72.0), "stats runtime: detached player slice omitted resolved stats")
	(slow_snapshot.combat_stats as Dictionary)["move_speed"] = 9999.0
	_expect(float(slow.state.combat_stats_snapshot().move_speed) == 72.0, "stats runtime: stats snapshot leaked mutable storage")

	# Both sessions receive the same dodge command. The configured sheet owns
	# total distance, duration and cooldown, while RoomActorAccess still owns
	# the final collision-safe position through the MovementResolver.
	var slow_dodge := _session("slow-dodge", 72.0, 96.0, 6, 12, 30)
	var fast_dodge := _session("fast-dodge", 144.0, 192.0, 6, 7, 18)
	var slow_dodge_world: SimulationWorld = slow_dodge.world
	var fast_dodge_world: SimulationWorld = fast_dodge.world
	var slow_dodge_rules: Object = slow_dodge.rules
	var fast_dodge_rules: Object = fast_dodge.rules
	slow_dodge_world.step_tick()
	fast_dodge_world.step_tick()
	var dodge_command := Protocol.dodge(1, "ranger", 1, 1000, 0)
	var dodge_intent := {"movement": Vector2.ZERO, "speed_scale": 1.0, "commands": [dodge_command], "receipts": []}
	_expect(bool(slow_dodge_rules.advance_tick(slow_dodge_world.tick, dodge_intent, no_targets).get("ok", false)), "stats runtime: slow dodge start failed")
	_expect(bool(fast_dodge_rules.advance_tick(fast_dodge_world.tick, dodge_intent, no_targets).get("ok", false)), "stats runtime: fast dodge start failed")
	for _tick in range(5):
		slow_dodge_world.step_tick()
		fast_dodge_world.step_tick()
		_expect(bool(slow_dodge_rules.advance_tick(slow_dodge_world.tick, {"movement": Vector2.ZERO, "commands": [], "receipts": []}, no_targets).get("ok", false)), "stats runtime: slow dodge continuation failed")
		_expect(bool(fast_dodge_rules.advance_tick(fast_dodge_world.tick, {"movement": Vector2.ZERO, "commands": [], "receipts": []}, no_targets).get("ok", false)), "stats runtime: fast dodge continuation failed")
	var slow_dodge_position: Vector2 = slow_dodge.state.position()
	var fast_dodge_position: Vector2 = fast_dodge.state.position()
	_expect(is_equal_approx(slow_dodge_position.x, 10.0 + 96.0), "stats runtime: slow dodge distance was not resolved")
	_expect(is_equal_approx(fast_dodge_position.x, 10.0 + 192.0), "stats runtime: fast dodge distance was not resolved")
	_expect(int(slow_dodge.state.snapshot(slow_dodge_world.tick).dodge_cooldown_ticks) == 25, "stats runtime: slow dodge cooldown did not use the resolved base")
	_expect(int(fast_dodge.state.snapshot(fast_dodge_world.tick).dodge_cooldown_ticks) == 13, "stats runtime: fast dodge cooldown did not use the resolved base")

	# A legacy build with no combat_stats keeps the historical constants and
	# therefore does not silently change existing replays.
	var legacy := _typed_room("legacy-stats")
	_expect(bool(legacy.get("ok", false)), "stats runtime: legacy room rejected the typed stack")
	if bool(legacy.get("ok", false)):
		var legacy_state := State.new()
		var legacy_reset: Dictionary = legacy_state.reset_for_room({"final_parameters": {"max_health": 100.0}}, legacy.access, "ranger", 0)
		_expect(bool(legacy_reset.get("ok", false)), "stats runtime: legacy build reset failed")
		_expect(not legacy_state.combat_stats_enabled() and is_equal_approx(legacy_state.move_speed(), 245.0), "stats runtime: legacy build changed its movement contract")

	_finish()


func _typed_room(room_id: String) -> Dictionary:
	var spatial_port := RoomSpatialPortScript.new()
	var world: SimulationWorld = World.new(spatial_port)
	if not world.configure(room_id, 1, 30).ok:
		return {"ok": false}
	_worlds.append(world)
	var static_build: Dictionary = StaticSpatialIndexScript.build({
		"schema_version": StaticSpatialIndexScript.SCHEMA_VERSION,
		"asset_id": "test/%s" % room_id,
		"surfaces": [],
		"movement_boundary": {"kind": "rect", "rect": Rect2(-100.0, -100.0, 1800.0, 1100.0)},
	})
	if not bool(static_build.get("ok", false)):
		return {"ok": false}
	var dynamic := DynamicSpatialIndexScript.new()
	var overlay := SpatialOverlayScript.new()
	var resolver_build: Dictionary = MovementResolverScript.make(static_build.get("value"), overlay, dynamic)
	if not bool(resolver_build.get("ok", false)):
		return {"ok": false}
	var access := RoomActorAccessScript.new()
	if not bool(access.configure(world, world.actor_registry, static_build.get("value"), dynamic, resolver_build.get("value"), overlay).get("ok", false)):
		return {"ok": false}
	spatial_port.bind(access)
	if not bool(access.register_actor("ranger", START, RADIUS).get("ok", false)):
		return {"ok": false}
	return {"ok": true, "world": world, "access": access, "resolver": resolver_build.get("value")}


func _session(room_id: String, move_speed: float, dodge_distance: float, dodge_duration: int, attack_cooldown: int, dodge_cooldown: int, movement_model: String = "direct", acceleration: float = -1.0) -> Dictionary:
	var room := _typed_room(room_id)
	if not bool(room.get("ok", false)):
		return {"ok": false}
	var world: SimulationWorld = room.world
	var access: RoomActorAccess = room.access
	var state := State.new()
	var build := {
		"final_parameters": {"max_health": 120.0, "damage": 55.0, "v": 240.0, "d": 225.0},
		"skills": ["piercing_arrow", "hunter_mark", "dash"],
		"combat_stats": {
			"move_speed": move_speed, "acceleration": move_speed,
			"dodge_distance": dodge_distance, "attack_cooldown_ticks": attack_cooldown,
			"dodge_duration_ticks": dodge_duration, "dodge_cooldown_ticks": dodge_cooldown,
			"resistances": {"physical": 0.0},
		},
	}
	if acceleration > 0.0:
		(build.combat_stats as Dictionary)["acceleration"] = acceleration
	if movement_model != "direct":
		(build.combat_stats as Dictionary)["movement_model"] = movement_model
	var provenance := {}
	for field: String in ["move_speed", "acceleration", "dodge_distance", "attack_cooldown_ticks", "dodge_duration_ticks", "dodge_cooldown_ticks"]:
		provenance[field] = ["fixture:%s" % field]
	(build.combat_stats as Dictionary)["provenance"] = provenance
	var reset: Dictionary = state.reset_for_room(build, access, "ranger", 0)
	if not bool(reset.get("ok", false)):
		return {"ok": false, "error": reset.get("error", "reset_failed")}
	var stream := Stream.new()
	var rules := Rules.new()
	var ready: Dictionary = rules.configure(state, world, stream)
	if not bool(ready.get("ok", false)):
		return {"ok": false, "error": ready.get("error", "rules_failed")}
	return {"ok": true, "world": world, "access": access, "resolver": room.resolver, "state": state, "rules": rules}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	for world in _worlds:
		if world != null and world.kernel != null:
			world.kernel.shutdown()
	_worlds.clear()
	for failure: String in _failures:
		printerr("- %s" % failure)
	print("PASS test_combat_stats_runtime.gd" if _failures.is_empty() else "FAIL test_combat_stats_runtime.gd")
	quit(0 if _failures.is_empty() else 1)
