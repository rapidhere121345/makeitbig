extends SceneTree

const RegistryScript = preload("res://src/content/early_campaign_registry.gd")
const ContractPlanScript = preload("res://src/game/contract_plan.gd")


func _initialize() -> void:
	var failures: Array[String] = []
	_test_shipped_contract(failures)
	_test_first_hunt_roster_plan(failures)
	_test_progression_interfaces(failures)
	_test_invalid_reference_cycle_and_counts(failures)
	_test_pure_data_gate(failures)
	_test_seeded_templates(failures)
	_test_auto_cannot_precede_boss(failures)
	if failures.is_empty():
		print("PASS  test_early_campaign.gd")
		quit(0)
		return
	for failure in failures:
		printerr("- %s" % failure)
	quit(1)


func _test_shipped_contract(failures: Array[String]) -> void:
	var registry = RegistryScript.new()
	var errors: Array[String] = registry.load_campaign()
	_expect(errors.is_empty(), "shipped contract must validate, got %s" % str(errors), failures)
	if not errors.is_empty():
		return
	var data := _read_shipped_data()
	_expect(data.layouts.size() == 3 and data.objectives.size() == 3 and data.hazards.size() == 2,
		"catalog: expected exactly 3 layouts, 3 objectives, and 2 hazards", failures)
	for layout_value in data.layouts:
		var layout: Dictionary = layout_value
		for field in ["display_name", "concept", "landmark", "entry_hint", "exit_hint"]:
			_expect(not String(layout.get(field, "")).strip_edges().is_empty(), "layout %s is missing readable %s" % [String(layout.get("id", "")), field], failures)
	_expect(data.normal_enemies.size() == 3 and data.elite_rules.size() == 2 and data.bosses.size() == 1,
		"catalog: expected exactly 3 normal enemies, 2 elite rules, and 1 boss", failures)
	_expect(data.fixed_nodes.size() == 8 and data.repeatable_templates.size() == 2,
		"nodes: expected exactly 8 fixed nodes and 2 repeatable templates", failures)
	var kinds := {"tutorial": 0, "mainline": 0, "boss": 0, "auto_certification": 0}
	var problem_ids := {}
	for node_value in data.fixed_nodes:
		var node: Dictionary = node_value
		kinds[node.kind] = int(kinds.get(node.kind, 0)) + 1
		_expect(node.has("unlock_prerequisites") and node.has("room_sequence") and node.has("first_reward_tags")
			and node.has("drop_tags") and node.has("allowed_modes") and node.has("repeatable"),
			"node %s is missing a required contract field" % node.id, failures)
		for room_value in node.room_sequence:
			var room: Dictionary = room_value
			_expect(room.new_problem_id is String, "room %s must use one scalar new_problem_id" % room.id, failures)
			if String(room.new_problem_id) != "":
				_expect(not problem_ids.has(room.new_problem_id), "new problem %s was introduced in more than one room" % room.new_problem_id, failures)
				problem_ids[room.new_problem_id] = true
	_expect(kinds == {"tutorial": 1, "mainline": 5, "boss": 1, "auto_certification": 1},
		"nodes: fixed kind census changed: %s" % str(kinds), failures)
	for template_value in data.repeatable_templates:
		var template: Dictionary = template_value
		_expect(bool(template.repeatable) and template.kind == "side_template" and template.has("room_template")
			and not template.has("room_sequence"), "template %s must be repeatable pure template data" % template.id, failures)


func _test_first_hunt_roster_plan(failures: Array[String]) -> void:
	var built := ContractPlanScript.build({"contract_id": "mainline_01_first_hunt", "seed": 301,
		"mode": "Manual", "completed_node_ids": ["tutorial_ranger_basics"]})
	_expect(bool(built.get("ok", false)), "first hunt: production RoomPlan failed", failures)
	if not bool(built.get("ok", false)):
		return
	_expect(int(built.plan.room_count) == 2, "first hunt: expected two short rooms", failures)
	_expect(built.plan.rooms[0].layout_id == "rectangle_arena" and built.plan.rooms[1].layout_id == "corridor",
		"first hunt: the two authored rooms must demonstrate different spaces", failures)
	var ids := {}
	for room: Dictionary in built.plan.rooms:
		_expect(room.enemy_ids == ["melee_pursuer", "melee_pursuer", "melee_pursuer"]
			and room.objective_id == "clear" and room.hazard_ids.is_empty() and room.elite_rule_ids.is_empty()
			and room.boss_id == "" and room.drop_tags == ["equipment_general"],
			"first hunt: roster multiplicity or real room loot was lost", failures)
		_expect(not ids.has(room.room_id), "first hunt: rooms share an identity", failures)
		ids[room.room_id] = true
	var registry = RegistryScript.new()
	var invalid_roster := _read_shipped_data()
	invalid_roster.fixed_nodes[1].room_sequence[0].enemy_ids.append("melee_pursuer_copy")
	_expect(_has(registry.validate_campaign(invalid_roster), "unknown reference"),
		"first hunt: roster accepted an invented enemy kind ID", failures)
	var duplicate_hazard := _read_shipped_data()
	duplicate_hazard.fixed_nodes[1].room_sequence[0].hazard_ids = ["moving_fireline", "moving_fireline"]
	_expect(_has(registry.validate_campaign(duplicate_hazard), "duplicate reference"),
		"first hunt: roster multiplicity accidentally allowed duplicate rule references", failures)


func _test_progression_interfaces(failures: Array[String]) -> void:
	var registry = RegistryScript.new()
	registry.load_campaign()
	var expected: Array[String] = [
		"tutorial_ranger_basics", "mainline_01_first_hunt", "mainline_02_priority_under_pressure",
		"mainline_03_first_elite", "mainline_04_hazard_and_forge", "mainline_05_growth_gate",
		"threshold_colossus", "auto_certification",
	]
	_expect(registry.mainline_order() == expected, "mainline_order: fixed authored order changed", failures)
	_expect(not registry.get_node("mainline_03_first_elite").is_empty(), "get_node: known node was not returned", failures)
	_expect(registry.get_node("mainline_01_first_hunt").get("first_reward_tags", []) == ["hunter_mark_skill", "equipment_compare_unlock"]
		and registry.get_node("mainline_03_first_elite").get("first_reward_tags", []) == ["breeding_split_item"]
		and registry.get_node("mainline_05_growth_gate").get("first_reward_tags", []) == ["pack_hunt_mark_item"],
		"semantic campaign rewards must be authored as equippable item tags", failures)
	_expect(registry.get_node("missing").is_empty(), "get_node: unknown node must return empty data", failures)
	var node_copy := registry.get_node("mainline_01_first_hunt")
	node_copy.id = "mutated"
	_expect(registry.get_node("mainline_01_first_hunt").id == "mainline_01_first_hunt", "get_node: caller mutation leaked into registry", failures)
	_expect(registry.is_unlocked("tutorial_ranger_basics", [], "Manual"), "unlock: tutorial must be initially reachable in Manual", failures)
	_expect(not registry.is_unlocked("mainline_01_first_hunt", [], "Manual"), "unlock: mainline prerequisite was ignored", failures)
	_expect(registry.is_unlocked("mainline_01_first_hunt", ["tutorial_ranger_basics"], "Manual"), "unlock: completed prerequisite was not accepted", failures)
	_expect(not registry.is_unlocked("mainline_01_first_hunt", ["tutorial_ranger_basics"], "Auto"), "unlock: Manual node accepted Auto mode", failures)
	_expect(registry.is_unlocked("side_targeted_equipment", ["mainline_03_first_elite"], "Manual"), "unlock: reachable side template remained locked", failures)
	_expect(registry.is_unlocked("side_targeted_equipment", ["mainline_03_first_elite"], "Auto"), "unlock: proxy-ready side template rejected Auto", failures)
	var forge_node: Dictionary = registry.get_node("mainline_04_hazard_and_forge")
	var forge_room_tags: Array[String] = []
	for room_value in (forge_node.get("room_sequence", []) as Array):
		for tag_value in ((room_value as Dictionary).get("drop_tags", []) as Array):
			var tag := String(tag_value)
			if tag.ends_with("_tally") and tag not in forge_room_tags:
				forge_room_tags.append(tag)
	forge_room_tags.sort()
	_expect(forge_node.get("first_reward_tags", []) == ["law_forge_unlock"]
		and forge_room_tags == ["inscribe_tally", "refine_tally", "rewrite_tally"],
		"forge unlock: mainline 04 must grant one reachable source for every Law Tally operation", failures)
	var forge_supply: Dictionary = registry.get_node("side_affix_and_law_tallies")
	_expect(forge_supply.get("unlock_prerequisites", []) == ["mainline_04_hazard_and_forge"]
		and forge_supply.get("first_reward_tags", []) == ["law_forge_unlock"],
		"forge supplies: repeatable Law Tally source must unlock with the forge", failures)


func _test_invalid_reference_cycle_and_counts(failures: Array[String]) -> void:
	var registry = RegistryScript.new()
	var bad_reference := _read_shipped_data()
	bad_reference.fixed_nodes[0].room_sequence[0].layout_id = "layout_not_real"
	_expect(_has(registry.validate_campaign(bad_reference), "unknown reference"), "validator: illegal catalog reference was accepted", failures)

	var cycle := _read_shipped_data()
	cycle.fixed_nodes[0].unlock_prerequisites = ["mainline_01_first_hunt"]
	_expect(_has(registry.validate_campaign(cycle), "cycle"), "validator: mainline prerequisite cycle was accepted", failures)

	var wrong_count := _read_shipped_data()
	wrong_count.layouts.pop_back()
	_expect(_has(registry.validate_campaign(wrong_count), "layouts has 2 entries, expected 3"), "validator: wrong exact catalog count was accepted", failures)

	var duplicate := _read_shipped_data()
	duplicate.hazards[1].id = duplicate.hazards[0].id
	_expect(_has(registry.validate_campaign(duplicate), "duplicate id"), "validator: duplicate stable ID was accepted", failures)


func _test_pure_data_gate(failures: Array[String]) -> void:
	var registry = RegistryScript.new()
	var impure := _read_shipped_data()
	impure["runtime_hook"] = Callable(self, "_read_shipped_data")
	var errors: Array[String] = registry.validate_campaign(impure)
	_expect(_has(errors, "not pure JSON data") and _has(errors, "unknown field"),
		"validator: runtime object/callback fields must be rejected", failures)


func _test_seeded_templates(failures: Array[String]) -> void:
	var registry = RegistryScript.new()
	registry.load_campaign()
	for template_id in ["side_targeted_equipment", "side_affix_and_law_tallies"]:
		var first: Dictionary = registry.instantiate_branch(template_id, 101)
		var repeated: Dictionary = registry.instantiate_branch(template_id, 101)
		var other: Dictionary = registry.instantiate_branch(template_id, 102)
		var automatic: Dictionary = registry.instantiate_branch(template_id, 101, "Auto")
		_expect(first == repeated, "seed: %s changed for identical seed" % template_id, failures)
		_expect(bool(automatic.get("ok", false)) and String(automatic.plan.mode) == "Auto" and automatic.plan.rooms == first.plan.rooms,
			"seed: %s did not preserve the same authored rooms for Auto" % template_id, failures)
		_expect(first.get("plan", {}).get("rooms", []) != other.get("plan", {}).get("rooms", []),
			"seed: %s did not vary across seeds 101 and 102" % template_id, failures)
		var template: Dictionary = registry.get_node(template_id).room_template
		for room_value in first.plan.rooms:
			var room: Dictionary = room_value
			_expect(room.layout_id in template.layout_ids and room.objective_id in template.objective_ids,
				"seed: generated layout/objective escaped %s bounds" % template_id, failures)
			_expect(room.hazard_ids.size() <= 1 and (room.hazard_ids.is_empty() or room.hazard_ids[0] in template.hazard_ids),
				"seed: generated hazard escaped %s bounds" % template_id, failures)
			_expect(room.enemy_ids.size() == 1 and room.enemy_ids[0] in template.enemy_ids,
				"seed: generated enemy escaped %s bounds" % template_id, failures)
			_expect(room.elite_rule_ids.size() <= 1 and (room.elite_rule_ids.is_empty() or room.elite_rule_ids[0] in template.elite_rule_ids),
				"seed: generated elite rule escaped %s bounds" % template_id, failures)
			_expect(room.drop_tags.size() == 1 and room.drop_tags[0] in template.drop_tags,
				"seed: generated drop escaped %s bounds" % template_id, failures)
			_expect(room.new_problem_id == "", "seed: repeatable room introduced a new problem", failures)


func _test_auto_cannot_precede_boss(failures: Array[String]) -> void:
	var registry = RegistryScript.new()
	registry.load_campaign()
	var before_boss := [
		"tutorial_ranger_basics", "mainline_01_first_hunt", "mainline_02_priority_under_pressure",
		"mainline_03_first_elite", "mainline_04_hazard_and_forge", "mainline_05_growth_gate",
	]
	_expect(not registry.is_unlocked("auto_certification", before_boss, "Auto"), "Auto unlocked before threshold_colossus completion", failures)
	before_boss.append("threshold_colossus")
	_expect(registry.is_unlocked("auto_certification", before_boss, "Auto"), "Auto stayed locked after threshold_colossus completion", failures)
	_expect(not registry.is_unlocked("auto_certification", before_boss, "Manual"), "Auto certification accepted Manual mode", failures)

	var reordered := _read_shipped_data()
	var auto_node: Dictionary = reordered.fixed_nodes.pop_back()
	reordered.fixed_nodes.insert(6, auto_node)
	_expect(_has(registry.validate_campaign(reordered), "must follow the Boss"), "validator: Auto node was accepted before Boss", failures)


func _read_shipped_data() -> Dictionary:
	var file := FileAccess.open("res://content/early_campaign.json", FileAccess.READ)
	return JSON.parse_string(file.get_as_text()).duplicate(true)


func _has(errors: Array[String], fragment: String) -> bool:
	for error in errors:
		if fragment in error:
			return true
	return false


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
