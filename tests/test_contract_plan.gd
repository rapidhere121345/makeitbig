extends RefCounted

const ContractPlan = preload("res://src/game/contract_plan.gd")


func run() -> Array[String]:
	var failures: Array[String] = []
	_test_validation_boundaries(failures)
	_test_first_contract_single_room(failures)
	_test_standard_bounds(failures)
	_test_determinism_and_seed_divergence(failures)
	_test_boss_contract(failures)
	_test_branch_contract(failures)
	_test_fixed_early_campaign_node(failures)
	_test_repeatable_early_campaign_node(failures)
	_test_alias_isolation(failures)
	return failures


func _test_validation_boundaries(failures: Array[String]) -> void:
	_expect(_code(ContractPlan.build({"contract_id": 7, "seed": 1, "room_count": 6})) == "invalid_contract_id",
		"validation: contract_id type must be String or StringName", failures)
	_expect(_code(ContractPlan.build({"contract_id": "  ", "seed": 1, "room_count": 6})) == "invalid_contract_id",
		"validation: blank contract_id must fail", failures)
	_expect(_code(ContractPlan.build({"contract_id": "x", "seed": 1.0, "room_count": 6})) == "invalid_seed",
		"validation: seed must be TYPE_INT", failures)
	_expect(_code(ContractPlan.build({"contract_id": "x", "seed": 1, "room_count": 6.0})) == "invalid_room_count",
		"validation: room_count must be TYPE_INT", failures)
	for room_count in [1, 5, 13]:
		_expect(_code(ContractPlan.build({"contract_id": "regular", "seed": 1, "room_count": room_count})) == "invalid_room_count",
			"validation: regular room_count %d must fail" % room_count, failures)
	_expect(bool(ContractPlan.build({"contract_id": &"named_contract", "seed": 1, "room_count": 6}).get("ok", false)),
		"validation: non-empty StringName contract_id must pass", failures)


func _test_first_contract_single_room(failures: Array[String]) -> void:
	var result: Dictionary = ContractPlan.build({"contract_id": "first_contract", "seed": 11, "room_count": 1})
	_expect(bool(result.get("ok", false)), "first contract: one room must pass", failures)
	if not bool(result.get("ok", false)):
		return
	var room: Dictionary = result.plan.rooms[0]
	_expect(room.index == 0 and room.is_boss and room.objective == "hunt_elite",
		"first contract: sole room must be the indexed elite boss", failures)
	_expect(not room.has("branches"), "first contract: boss must not expose branches", failures)


func _test_standard_bounds(failures: Array[String]) -> void:
	for room_count in [6, 12]:
		var result: Dictionary = ContractPlan.build({"contract_id": "boundary", "seed": 22, "room_count": room_count})
		_expect(bool(result.get("ok", false)) and result.plan.rooms.size() == room_count,
			"bounds: room_count %d must build exactly that many rooms" % room_count, failures)


func _test_determinism_and_seed_divergence(failures: Array[String]) -> void:
	var config := {"contract_id": "determinism", "seed": -919, "room_count": 9}
	var first: Dictionary = ContractPlan.build(config)
	var second: Dictionary = ContractPlan.build(config)
	var other_seed: Dictionary = ContractPlan.build({"contract_id": "determinism", "seed": -918, "room_count": 9})
	_expect(first == second, "determinism: identical config must produce identical output", failures)
	_expect(first.plan.rooms != other_seed.plan.rooms, "determinism: different seeds must change the room sequence", failures)


func _test_boss_contract(failures: Array[String]) -> void:
	var result: Dictionary = ContractPlan.build({"contract_id": "boss_rules", "seed": 33, "room_count": 12})
	var rooms: Array = result.plan.rooms
	for index in range(rooms.size()):
		var room: Dictionary = rooms[index]
		_expect(room.index == index, "boss: room index must match array position %d" % index, failures)
		_expect(room.is_boss == (index == rooms.size() - 1), "boss: only final room may be boss", failures)
		_expect(String(room.room_id) != "", "boss: every room needs a stable room_id", failures)
		_expect(ContractPlan.layouts.has(room.layout), "boss: layout must come from public catalog", failures)
		_expect(ContractPlan.objectives.has(room.objective), "boss: objective must come from public catalog", failures)
		_expect(ContractPlan.drop_tags.has(room.drop_tag), "boss: drop tag must come from public catalog", failures)
		_expect(ContractPlan.risk_tags.has(room.risk_tag), "boss: risk tag must come from public catalog", failures)
	_expect(rooms[-1].objective == "hunt_elite", "boss: final objective must be hunt_elite", failures)


func _test_branch_contract(failures: Array[String]) -> void:
	var result: Dictionary = ContractPlan.build({"contract_id": "branch_rules", "seed": 44, "room_count": 12})
	var rooms: Array = result.plan.rooms
	for index in range(rooms.size()):
		var room: Dictionary = rooms[index]
		var should_branch: bool = not bool(room.is_boss) and (index + 1) % 3 == 0
		_expect(room.has("branches") == should_branch, "branches: room %d branch cadence changed" % index, failures)
		if not should_branch:
			continue
		var branches: Array = room.branches
		_expect(branches.size() == 2, "branches: room %d must expose two choices" % index, failures)
		if branches.size() != 2:
			continue
		for branch in branches:
			_expect(branch.keys().size() == 3 and branch.has("id") and branch.has("drop_tag") and branch.has("risk_tag"),
				"branches: each public choice must contain only id/drop_tag/risk_tag", failures)
			_expect(ContractPlan.drop_tags.has(branch.drop_tag) and ContractPlan.risk_tags.has(branch.risk_tag),
				"branches: choice tags must come from public catalogs", failures)
		_expect(branches[0] != branches[1], "branches: the two choices must not be identical", failures)


func _test_fixed_early_campaign_node(failures: Array[String]) -> void:
	var locked: Dictionary = ContractPlan.build({
		"contract_id": "mainline_02_priority_under_pressure",
		"seed": 71,
		"mode": "Manual",
		"completed_node_ids": [],
	})
	_expect(_code(locked) == "contract_locked", "early campaign: prerequisite gate was not enforced", failures)
	var result: Dictionary = ContractPlan.build({
		"contract_id": "mainline_02_priority_under_pressure",
		"seed": 71,
		"mode": "Manual",
		"completed_node_ids": ["tutorial_ranger_basics", "mainline_01_first_hunt"],
	})
	_expect(bool(result.get("ok", false)), "early campaign: fixed node did not build", failures)
	if not bool(result.get("ok", false)):
		return
	var plan: Dictionary = result.plan
	_expect(plan.source == "early_campaign" and plan.version == 2 and plan.room_count == 2, "early campaign: fixed-node plan envelope changed", failures)
	_expect(plan.rooms[0].enemy_ids == ["melee_pursuer", "charging_raider"], "early campaign: first authored enemy mix was not preserved", failures)
	_expect(plan.rooms[1].layout_id == "ring" and plan.rooms[1].objective_id == "clear", "early campaign: authored room semantics were not preserved", failures)
	_expect(String(plan.rooms[0].display_name) == "Windcut Passage" and not String(plan.rooms[0].entry_hint).is_empty()
		and String(plan.rooms[1].display_name) == "Salvage Ring" and not String(plan.rooms[1].exit_hint).is_empty(),
		"early campaign: room presentation contract was not carried into the plan", failures)
	_expect(_code(ContractPlan.build({"contract_id": "auto_certification", "seed": 1, "mode": "Manual"})) == "mode_not_allowed", "early campaign: mode gate was not enforced", failures)


func _test_repeatable_early_campaign_node(failures: Array[String]) -> void:
	var config := {"contract_id": "side_targeted_equipment", "seed": 88, "mode": "Manual"}
	var first: Dictionary = ContractPlan.build(config)
	var second: Dictionary = ContractPlan.build(config)
	var other: Dictionary = ContractPlan.build({"contract_id": "side_targeted_equipment", "seed": 89, "mode": "Manual"})
	var automatic: Dictionary = ContractPlan.build({"contract_id": "side_targeted_equipment", "seed": 88, "mode": "Auto"})
	_expect(first == second, "early campaign: repeatable template changed for the same seed", failures)
	_expect(bool(first.get("ok", false)) and first.plan.repeatable and first.plan.room_count == 3, "early campaign: repeatable template envelope changed", failures)
	_expect(first.plan.rooms != other.plan.rooms, "early campaign: repeatable template ignored seed divergence", failures)
	_expect(bool(automatic.get("ok", false)) and String(automatic.plan.mode) == "Auto" and automatic.plan.rooms == first.plan.rooms,
		"early campaign: repeatable template could not run the same seeded room plan in Auto", failures)
	for room in (first.plan.rooms as Array):
		_expect(not (room as Dictionary).enemy_ids.is_empty() and not (room as Dictionary).drop_tags.is_empty(), "early campaign: generated room lost enemy/drop content", failures)


func _test_alias_isolation(failures: Array[String]) -> void:
	var config := {"contract_id": "aliases", "seed": 55, "room_count": 6, "meta": {"value": 1}}
	var first: Dictionary = ContractPlan.build(config)
	config.meta.value = 9
	first.plan.rooms[0].layout = "mutated"
	if first.plan.rooms[2].has("branches"):
		first.plan.rooms[2].branches[0].drop_tag = "mutated"
	var rebuilt: Dictionary = ContractPlan.build({"contract_id": "aliases", "seed": 55, "room_count": 6})
	_expect(config.meta.value == 9, "alias: build must not mutate caller input", failures)
	_expect(rebuilt.plan.rooms[0].layout != "mutated", "alias: room output mutation leaked into a later build", failures)
	_expect(rebuilt.plan.rooms[2].branches[0].drop_tag != "mutated", "alias: nested branch output mutation leaked", failures)


func _code(result: Dictionary) -> String:
	return String(result.get("error", ""))


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
