extends SceneTree

const State := preload("res://src/runtime/world/player_combat_state.gd")
const Registry := preload("res://src/runtime/world/actor_registry.gd")
const World := preload("res://src/runtime/world/simulation_world.gd")
const Rules := preload("res://src/systems/player_combat_rules.gd")
const Motion := preload("res://src/systems/player_motion_system.gd")
const Stream := preload("res://src/systems/combat_event_stream.gd")
const Protocol := preload("res://src/systems/combat_command_protocol.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	var slow := _session("slow", 72.0, 96.0, 6, 12, 30)
	var fast := _session("fast", 144.0, 192.0, 6, 7, 18)
	_expect(bool(slow.get("ok", false)) and bool(fast.get("ok", false)), "stats runtime: explicit combat sheets were rejected")
	if not bool(slow.get("ok", false)) or not bool(fast.get("ok", false)):
		_finish()
		return

	var slow_world: Object = slow.world
	var fast_world: Object = fast.world
	var slow_rules: Object = slow.rules
	var fast_rules: Object = fast.rules
	var no_targets: Array[Dictionary] = []
	slow_world.step()
	fast_world.step()
	var intent := {"movement": Vector2.RIGHT, "speed_scale": 1.0, "commands": [], "receipts": []}
	_expect(bool(slow_rules.advance_tick(slow_world.tick, intent, no_targets).get("ok", false)), "stats runtime: slow build movement tick failed")
	_expect(bool(fast_rules.advance_tick(fast_world.tick, intent, no_targets).get("ok", false)), "stats runtime: fast build movement tick failed")
	var slow_position: Vector2 = slow.state.position()
	var fast_position: Vector2 = fast.state.position()
	_expect(is_equal_approx(slow_position.x, 10.0 + 72.0 / 30.0), "stats runtime: slow move_speed was not consumed")
	_expect(is_equal_approx(fast_position.x, 10.0 + 144.0 / 30.0), "stats runtime: fast move_speed was not consumed")
	_expect(fast_position.x > slow_position.x and slow.registry.is_position_clear(slow_position), "stats runtime: same command did not produce two valid movement outcomes")

	# Flare-style resolved stats keep the movement model explicit. An authored
	# accelerated sheet ramps toward the same max speed on fixed ticks instead
	# of silently treating acceleration as dead content.
	var accelerated := _session("accelerated", 120.0, 96.0, 6, 12, 30, "accelerated", 60.0)
	_expect(bool(accelerated.get("ok", false)), "stats runtime: accelerated combat sheet was rejected")
	if bool(accelerated.get("ok", false)):
		var accelerated_world: Object = accelerated.world
		var accelerated_rules: Object = accelerated.rules
		var accelerated_state: Object = accelerated.state
		accelerated_world.step()
		_expect(bool(accelerated_rules.advance_tick(accelerated_world.tick, intent, no_targets).get("ok", false)), "stats runtime: accelerated first tick failed")
		var first_accelerated_position: Vector2 = accelerated_state.position()
		accelerated_world.step()
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
	# total distance, duration and cooldown, while ActorRegistry still owns the
	# final collision-safe position.
	var slow_dodge := _session("slow-dodge", 72.0, 96.0, 6, 12, 30)
	var fast_dodge := _session("fast-dodge", 144.0, 192.0, 6, 7, 18)
	var slow_dodge_world: Object = slow_dodge.world
	var fast_dodge_world: Object = fast_dodge.world
	var slow_dodge_rules: Object = slow_dodge.rules
	var fast_dodge_rules: Object = fast_dodge.rules
	slow_dodge_world.step()
	fast_dodge_world.step()
	var dodge_command := Protocol.dodge(1, "ranger", 1, 1000, 0)
	var dodge_intent := {"movement": Vector2.ZERO, "speed_scale": 1.0, "commands": [dodge_command], "receipts": []}
	_expect(bool(slow_dodge_rules.advance_tick(slow_dodge_world.tick, dodge_intent, no_targets).get("ok", false)), "stats runtime: slow dodge start failed")
	_expect(bool(fast_dodge_rules.advance_tick(fast_dodge_world.tick, dodge_intent, no_targets).get("ok", false)), "stats runtime: fast dodge start failed")
	for _tick in range(5):
		slow_dodge_world.step()
		fast_dodge_world.step()
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
	var legacy_registry := Registry.new()
	legacy_registry.configure("legacy-stats", 1)
	legacy_registry.register_actor("ranger", Vector2(10.0, 20.0), 14.0)
	var legacy_world := World.new()
	legacy_world.configure(30, "legacy-stats", 1)
	var legacy_state := State.new()
	_expect(bool(legacy_state.reset_for_room({"final_parameters": {"max_health": 100.0}}, legacy_registry, "ranger", 0).get("ok", false)), "stats runtime: legacy build reset failed")
	_expect(not legacy_state.combat_stats_enabled() and is_equal_approx(legacy_state.move_speed(), 245.0), "stats runtime: legacy build changed its movement contract")

	_finish()


func _session(room_id: String, move_speed: float, dodge_distance: float, dodge_duration: int, attack_cooldown: int, dodge_cooldown: int, movement_model: String = "direct", acceleration: float = -1.0) -> Dictionary:
	var registry := Registry.new()
	var configured := registry.configure(room_id, 1)
	if not bool(configured.get("ok", false)) or not bool(registry.register_actor("ranger", Vector2(10.0, 20.0), 14.0).get("ok", false)):
		return {"ok": false}
	var world := World.new()
	if not bool(world.configure(30, room_id, 1).get("ok", false)):
		return {"ok": false}
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
	var reset: Dictionary = state.reset_for_room(build, registry, "ranger", 0)
	if not bool(reset.get("ok", false)):
		return {"ok": false, "error": reset.get("error", "reset_failed")}
	var stream := Stream.new()
	var rules := Rules.new()
	var ready: Dictionary = rules.configure(state, world, stream)
	if not bool(ready.get("ok", false)):
		return {"ok": false, "error": ready.get("error", "rules_failed")}
	return {"ok": true, "registry": registry, "world": world, "state": state, "rules": rules}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	for failure: String in _failures:
		printerr("- %s" % failure)
	print("PASS test_combat_stats_runtime.gd" if _failures.is_empty() else "FAIL test_combat_stats_runtime.gd")
	quit(0 if _failures.is_empty() else 1)
