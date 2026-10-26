extends SceneTree

## Shared runner and fixtures for the tests/application suites. Each suite
## extends this script, overrides run() and reports through the same failure
## list the former monolithic test_application_state.gd used; the base turns
## that list into a PASS line and a process exit code for test discovery.
const ApplicationState = preload("res://src/game/application_state.gd")
const Assert := preload("res://tests/helpers/assert.gd")


func _initialize() -> void:
	call_deferred("_run_suite")


func run() -> Array[String]:
	return []


func _run_suite() -> void:
	var failures: Array[String] = run()
	var suite_name: String = get_script().resource_path.get_file()
	if failures.is_empty():
		print("PASS  %s" % suite_name)
		quit(0)
		return
	for failure in failures:
		printerr("%s: %s" % [suite_name, failure])
	quit(1)


func _complete_drop_gate_node(state: ApplicationState, contract_id: String, seed: int) -> Dictionary:
	var plan := {"rooms": [{"room_id": contract_id, "drop_tags": ["equipment_general"]}]}
	state.prepare_contract({
		"contract_id": contract_id,
		"mode": "Manual",
		"seed": seed,
		"room_count": 1,
		"room_plan": plan,
	})
	state.begin_session()
	return state.complete_session({"outcome": "victory", "rooms_completed": 1})


func _unlock_equipment_drops(state: ApplicationState) -> void:
	state.complete_tutorial()
	for node_id in ["mainline_01_first_hunt", "mainline_02_priority_under_pressure", "mainline_03_first_elite", "mainline_04_hazard_and_forge"]:
		_grant_session_result(state, node_id, "Manual", "victory")


func _has_equipment_instance(equipment: Array, instance_id: String) -> bool:
	for item in equipment:
		if item is Dictionary and String((item as Dictionary).get("instance_id", "")) == instance_id:
			return true
	return false


func _equipment_instance_count(equipment: Array, instance_id: String) -> int:
	var count := 0
	for item in equipment:
		if item is Dictionary and String((item as Dictionary).get("instance_id", "")) == instance_id:
			count += 1
	return count


func _begin_side_session(state: ApplicationState, contract_id: String, seed: int, plan: Dictionary, resolved_build: Dictionary = {}) -> void:
	var config := {
		"contract_id": contract_id,
		"mode": "Manual",
		"seed": seed,
		"room_count": (plan.rooms as Array).size(),
		"room_plan": plan.duplicate(true),
	}
	if not resolved_build.is_empty():
		config["resolved_build"] = resolved_build.duplicate(true)
	state.prepare_contract(config)
	state.begin_session()


func _complete_side_attempt(state: ApplicationState, contract_id: String, seed: int, plan: Dictionary, resolved_build: Dictionary = {}) -> Dictionary:
	_begin_side_session(state, contract_id, seed, plan, resolved_build)
	return state.complete_session({"outcome": "victory", "rooms_completed": (plan.rooms as Array).size()})


func _grant_victory(state: ApplicationState, rewards: Dictionary, contract_id: String) -> void:
	state.prepare_contract({"contract_id": contract_id, "mode": "Auto", "seed": 1, "room_count": 1})
	state.begin_session()
	state.complete_session({"outcome": "victory", "rewards": rewards})


func _unlock_auto_certification() -> ApplicationState:
	var state := ApplicationState.new()
	state.start_new_profile()
	state.complete_tutorial()
	for node_id in [
		"mainline_01_first_hunt",
		"mainline_02_priority_under_pressure",
		"mainline_03_first_elite",
		"mainline_04_hazard_and_forge",
		"mainline_05_growth_gate",
	]:
		_grant_session_result(state, node_id, "Manual", "victory")
	_grant_session_result(state, "threshold_colossus", "Manual", "victory")
	return state


func _grant_session_result(state: ApplicationState, contract_id: String, mode: String, outcome: String) -> Dictionary:
	state.prepare_contract({"contract_id": contract_id, "mode": mode, "seed": 1, "room_count": 1})
	state.begin_session()
	return state.complete_session({"outcome": outcome})


func _code(result: Dictionary) -> String:
	return String(result.get("error", ""))


func _is_fingerprint(value: String) -> bool:
	if value.length() != 64:
		return false
	for character in value:
		if character not in "0123456789abcdef":
			return false
	return true


func _expect(condition: bool, message: String, failures: Array[String]) -> void: Assert.expect(condition, message, failures)
