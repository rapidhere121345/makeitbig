extends SceneTree

const Driver := preload("res://src/game/diagnostics/smoke_input_driver.gd")
const Protocol := preload("res://src/systems/combat_command_protocol.gd")
const Fixture := preload("res://tests/helpers/talent_runtime_fixture.gd")
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _observation() -> Dictionary:
	return {
		"player": {"sim_tick": 44, "player_position": Vector2(200, 200), "player_facing": Vector2.RIGHT, "equipped_skills": ["piercing_arrow", "hunter_mark", "dash"], "hunter_mark_cooldown_ticks": 0, "dodge_cooldown_ticks": 0, "attack_cooldown_ticks": 4},
		"targets": [{"entity_id": 9, "health": 10.0, "position": Vector2(390, 200)}, {"entity_id": 2, "health": 10.0, "position": Vector2(10, 200)}],
		"targeting_distance": 225.0, "hazards": [], "boss": {},
	}


func _run() -> void:
	var driver := Driver.new()
	var observation := _observation()
	var unchanged := observation.duplicate(true)
	var decision := driver.decide(observation, 12)
	var expected: Array[Dictionary] = [Protocol.move(44, "ranger", 12, -1000, 0, 720), Protocol.cast(44, "ranger", 13, "hunter_mark", 2), Protocol.cast(44, "ranger", 14, "piercing_arrow", 2, -1000, 0)]
	_expect(decision.commands == expected and decision.next_sequence == 15, "range/tie/skill order or protocol sequence changed")
	_expect(observation == unchanged and driver.decide(observation, 12) == decision, "driver mutated authority or kept hidden sequence state")
	observation.hazards = [{"id": "moving_fireline", "phase": "active", "origin": Vector2(200, 0), "width": 34.0, "cycle_tick": 44}]
	decision = driver.decide(observation, 12)
	_expect(driver.requires_dodge(observation), "final active fireline tick stopped threatening the player")
	expected = [Protocol.move(44, "ranger", 12, 0, -1000, 1000), Protocol.cast(44, "ranger", 13, "hunter_mark", 2), Protocol.dodge(44, "ranger", 14, 0, -1000), Protocol.cast(44, "ranger", 15, "piercing_arrow", 2, -1000, 0)]
	_expect(decision.commands == expected and decision.next_sequence == 16, "threat movement/dodge/arrow command ordering changed")
	var routed := Protocol.arbitrate(decision.commands, 44, ["piercing_arrow", "hunter_mark", "dash"])
	_expect(routed.commands.size() == 3 and routed.receipts[-1].reason == "action_conflict", "smoke bypassed ordinary same-tick arbitration")
	observation.player.dodge_cooldown_ticks = 1
	_expect(not driver.requires_dodge(observation), "smoke dodge ignored cooldown")
	observation.player.dodge_cooldown_ticks = 0
	observation.hazards[0].phase = "recovery"
	_expect(not driver.requires_dodge(observation), "recovering fireline was treated as active")
	observation.boss = {"impact_tick": 45, "target_shape": {"type": "rect", "rect": Rect2(190, 190, 20, 20)}}
	_expect(driver.requires_dodge(observation), "next-tick Boss impact lost threat geometry")
	observation.boss.impact_tick = 46
	_expect(not driver.requires_dodge(observation), "Boss dodge started before the original next-tick window")
	observation.targets[0].health = 0.0
	observation.targets[1].health = 0.0
	decision = driver.decide(observation, 12)
	_expect(decision.commands.is_empty() and decision.next_sequence == 12, "empty roster generated commands or consumed sequence ids")
	_test_main_assembly()
	for failure: String in failures:
		printerr("FAIL: " + failure)
	if failures.is_empty():
		print("PASS test_smoke_input_driver.gd")
	quit(0 if failures.is_empty() else 1)


func _test_main_assembly() -> void:
	var fixture := Fixture.new()
	var session: Dictionary = fixture.start_session()
	var arena = session.arena
	arena.set_process(false)
	session.runtime.set_process(false)
	fixture.configure_target(arena)
	fixture.advance_to(arena, 12)
	arena.automation_smoke = true
	var observation := {"player": fixture.player(arena), "targets": arena._read_only_targets(), "hazards": arena.hazard_states.duplicate(true), "boss": {}, "targeting_distance": arena.locked_targeting_distance}
	var before: String = arena._semantic_state_hash("smoke-read")
	var expected: Dictionary = arena.smoke_input_driver.decide(observation, arena.command_sequence)
	var commands: Array[Dictionary] = arena._simulation_collect_commands()
	_expect(commands == expected.commands and arena.command_sequence == expected.next_sequence, "Main did not assemble the independent smoke input driver")
	# Sequence is intentionally consumed; all player and encounter observations remain detached.
	var sequence_after: int = arena.command_sequence
	arena.command_sequence -= commands.size()
	_expect(arena._semantic_state_hash("smoke-read") == before, "collecting smoke inputs mutated gameplay authority")
	arena.command_sequence = sequence_after
	var next_tick_commands: Array[Dictionary] = []
	for command: Dictionary in commands:
		var copy := command.duplicate(true)
		copy.tick += 1
		next_tick_commands.append(copy)
	fixture.step(arena, next_tick_commands)
	_expect(fixture.player(arena).timeline.active.get("target_entity_id", 0) == arena.enemies[0].entity_id and fixture.player(arena).timeline.active.get("start_tick", -1) == 13, "smoke commands failed the real Simulation/Rules input path")
	fixture.free_session(session)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
