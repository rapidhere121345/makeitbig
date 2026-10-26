extends SceneTree
const Progress = preload("res://src/systems/character_progression.gd")
const State = preload("res://src/game/application_state.gd")
const Assert := preload("res://tests/helpers/assert.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_expect(Progress.snapshot({"experience":0}).level == 1, "fresh character level")
	var last_points := 0
	for level in range(1, 51):
		var reading := Progress.snapshot({"experience":Progress.threshold(level)})
		_expect(reading.level == level, "level threshold %d" % level)
		_expect(reading.points_earned >= last_points, "points decrease")
		last_points = reading.points_earned
	_expect(last_points == 30, "50-level budget must be 30")
	var capped := Progress.award({"experience":Progress.maximum_experience()-1}, 1000000)
	_expect(capped.level_after == 50 and capped.experience_delta == 1, "cap must not overflow")
	for invalid in [{}, {"experience":-1}, {"experience":1.5}, {"experience":INF}, {"experience":0,"level":50}]:
		_expect(not Progress.is_valid_state(invalid), "invalid persisted XP accepted")
	var state := State.new()
	state.start_new_profile("ranger")
	var base := state.resolved_build_snapshot()
	state.complete_tutorial()
	var xp: int = state.profile.character.experience
	state.complete_tutorial()
	_expect(state.profile.character.experience == xp and state.character_snapshot().points_available == 1, "tutorial rewards must be exactly once")
	_expect(state.resolved_build_snapshot().final_parameters == base.final_parameters, "level alone changed combat parameters")
	state.prepare_contract({"contract_id":"mainline_01_first_hunt","mode":"Manual","seed":1,"room_count":1})
	state.begin_session()
	var result := state.complete_session({"outcome":"victory","rewards":{"experience_delta":9999999}})
	_expect(result.result.character_growth.experience_delta == 80, "XP must come from contract content, not submitted reward values")
	var after: int = state.profile.character.experience
	_expect(not state.complete_session({"outcome":"victory"}).ok and state.profile.character.experience == after, "duplicate settlement granted XP")
	state.prepare_contract({"contract_id":"mainline_02_priority_under_pressure","mode":"Manual","seed":2,"room_count":1})
	state.begin_session()
	state.complete_session({"outcome":"defeat","rewards":{"experience_delta":999}})
	_expect(state.profile.character.experience == after, "failed contract granted completion XP")
	var restored := State.new()
	_expect(restored.restore_persistent_payload(JSON.parse_string(JSON.stringify(state.persistent_payload()))).ok, "XP save roundtrip failed")
	_expect(restored.character_snapshot() == state.character_snapshot(), "growth changed after loading")
	if failures.is_empty():
		print("PASS test_character_progression.gd")
	else:
		for problem in failures: printerr(problem)
	quit(0 if failures.is_empty() else 1)

func _expect(ok: bool, message: String) -> void: Assert.expect(ok, message, failures)
