extends SceneTree

const StoryRegistryScript = preload("res://src/content/story_registry.gd")
const StoryProgressionScript = preload("res://src/systems/story_progression.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var registry := StoryRegistryScript.new()
	var load_errors := registry.load_story()
	_expect(load_errors.is_empty(), "shipped story failed to load: %s" % str(load_errors))
	var progression := StoryProgressionScript.new(registry)
	_test_default_and_normalize(progression)
	_test_tutorial_opening(progression)
	_test_progressive_npcs_and_town(progression)
	_test_boss_auto_and_epilogue(progression)
	_test_read_ids_are_stable_and_reward_independent(progression)
	_test_validation_rejects_bad_data(registry)
	_test_real_evidence_gates(progression)
	if failures.is_empty():
		print("PASS story progression")
		quit(0)
	else:
		for failure in failures:
			printerr("- %s" % failure)
		quit(1)


func _test_default_and_normalize(progression: StoryProgression) -> void:
	_expect(progression.default_saved_story() == {"schema_version": 1, "read_entry_ids": []},
		"default saved_story shape changed")
	var normalized := progression.normalize_saved_story({"junk": true, "read_entry_ids": ["journal_p00_place_by_the_door", "missing", 4, "journal_p00_place_by_the_door"]})
	_expect(normalized == {"schema_version": 1, "read_entry_ids": ["journal_p00_place_by_the_door", "missing"]},
		"normalize did not deduplicate strings and drop non-string ids: %s" % str(normalized))


func _test_tutorial_opening(progression: StoryProgression) -> void:
	var snapshot := _snapshot([], false, false)
	var state := progression.evaluate(snapshot, progression.default_saved_story())
	_expect(state.journal_entries.is_empty() and state.available_conversations.is_empty() and state.town_changes.is_empty(),
		"story leaked before the tutorial")
	var tutorial_nodes: Array[String] = ["tutorial_ranger_basics"]
	var after_tutorial := progression.evaluate(_snapshot(tutorial_nodes, false, false), progression.default_saved_story())
	_expect(after_tutorial.journal_entries.size() == 1 and after_tutorial.available_conversations.size() == 2 and after_tutorial.town_changes.size() == 1,
		"tutorial did not unlock exactly the P00 opening")
	_expect(String(after_tutorial.current_objective.id) == "clear_outer_road",
		"post-tutorial objective did not point to the outer road")
	var journal: Dictionary = after_tutorial.journal_entries[0]
	_expect(String(journal.title) == "门边的位置" and bool(journal.is_read) == false,
		"journal title/read initial state is wrong")


func _test_progressive_npcs_and_town(progression: StoryProgression) -> void:
	var cases := [
		{"nodes": ["tutorial_ranger_basics"], "names": ["米拉", "莱娅"]},
		{"nodes": ["tutorial_ranger_basics", "mainline_01_first_hunt"], "names": ["米拉", "莱娅", "塔伦"]},
		{"nodes": ["tutorial_ranger_basics", "mainline_01_first_hunt", "mainline_02_priority_under_pressure"], "names": ["米拉", "莱娅", "塔伦", "奥伦"]},
		{"nodes": ["tutorial_ranger_basics", "mainline_01_first_hunt", "mainline_02_priority_under_pressure", "mainline_03_first_elite"], "names": ["米拉", "莱娅", "塔伦", "奥伦", "伊文"]},
	]
	for expected in cases:
		var completed_nodes: Array[String] = []
		completed_nodes.assign(expected.nodes)
		var state := progression.evaluate(_snapshot(completed_nodes, false, false), progression.default_saved_story())
		var names: Array[String] = []
		for conversation in state.available_conversations:
			names.append(String(conversation.npc_name))
		var unique := names.duplicate()
		unique.sort()
		var wanted: Array[String] = []
		wanted.assign(expected.names)
		wanted.sort()
		_expect(unique == wanted, "NPC reveal set was %s, expected %s" % [str(unique), str(wanted)])
		_expect(state.town_changes.size() == expected.nodes.size(),
			"town changes did not accumulate by actual completed stage")


func _test_boss_auto_and_epilogue(progression: StoryProgression) -> void:
	var all_nodes: Array[String] = ["tutorial_ranger_basics", "mainline_01_first_hunt", "mainline_02_priority_under_pressure", "mainline_03_first_elite", "mainline_04_hazard_and_forge", "mainline_05_growth_gate", "threshold_colossus", "auto_certification"]
	var through_boss: Array[String] = ["tutorial_ranger_basics", "mainline_01_first_hunt", "mainline_02_priority_under_pressure", "mainline_03_first_elite", "mainline_04_hazard_and_forge", "mainline_05_growth_gate", "threshold_colossus"]
	var after_boss := progression.evaluate(_snapshot(through_boss, true, false), progression.default_saved_story())
	_expect(after_boss.journal_entries.size() == 9 and String(after_boss.current_objective.id) == "finish_contemporary_recovery"
		and String(after_boss.current_objective.campaign_node) == "auto_certification",
		"Boss victory plus proxy unlock did not produce the actionable P08 Auto objective")
	var locked_p08 := progression.evaluate(_snapshot(through_boss, false, false), progression.default_saved_story())
	_expect(String(locked_p08.current_objective.id) == "configure_first_auto",
		"P08 leaked before threshold_colossus/proxy_unlocked")
	var before_boss := progression.evaluate(_snapshot(["tutorial_ranger_basics", "mainline_01_first_hunt", "mainline_02_priority_under_pressure", "mainline_03_first_elite", "mainline_04_hazard_and_forge", "mainline_05_growth_gate"], false, false), progression.default_saved_story())
	_expect(String(before_boss.current_objective.campaign_node) == "threshold_colossus",
		"pre-Boss objective did not point at the real threshold node")
	var epilogue := progression.evaluate(_snapshot(all_nodes, true, true), progression.default_saved_story())
	_expect(epilogue.journal_entries.size() == 10 and epilogue.town_changes.size() == 10,
		"early_game_complete flag did not append exactly P09")
	_expect(String(epilogue.current_objective.id) == "chapter_one_epilogue",
		"completed chapter objective did not stop at the first-chapter epilogue")
	for unit in epilogue.journal_entries:
		var objective: Dictionary = progression.evaluate(_snapshot(all_nodes, true, true), progression.default_saved_story()).current_objective
		_expect(String(objective.campaign_node) == "" or String(objective.campaign_node) in ["tutorial_ranger_basics", "mainline_01_first_hunt", "mainline_02_priority_under_pressure", "mainline_03_first_elite", "mainline_04_hazard_and_forge", "mainline_05_growth_gate", "threshold_colossus", "auto_certification"],
			"objective mapping referenced a non-actionable campaign node")
		break


func _test_read_ids_are_stable_and_reward_independent(progression: StoryProgression) -> void:
	var snapshot := _snapshot(["tutorial_ranger_basics"], false, false)
	var saved := progression.default_saved_story()
	var state_before := progression.evaluate(snapshot, saved)
	var state_after_reading := progression.evaluate(snapshot, saved)
	state_after_reading.journal_entries[0].is_read = true
	_expect(state_before.journal_entries[0].duplicate(true).has("is_read") and state_after_reading.journal_entries[0].duplicate(true).has("is_read"),
		"read state must be presentation metadata, not a reward field")
	var next := progression.mark_entry_read(snapshot, saved, "journal_p00_place_by_the_door")
	_expect(next == {"schema_version": 1, "read_entry_ids": ["journal_p00_place_by_the_door"]},
		"mark_entry_read did not return the promised saved_story shape: %s" % str(next))
	var read_state := progression.evaluate(snapshot, next)
	_expect(bool(read_state.journal_entries[0].is_read), "stable journal id did not restore read state")
	var invalid := progression.mark_entry_read(snapshot, next, "journal_not_unlocked")
	_expect(invalid == next, "mark_entry_read accepted an unreached journal id")


func _test_validation_rejects_bad_data(registry: StoryRegistry) -> void:
	var data := _read_story()
	data.units[0].id = data.units[1].id
	data.units.pop_back()
	var errors := registry.validate_story(data)
	_expect(_has(errors, "duplicate id") and _has(errors, "exactly ten"), "validator missed duplicate unit or count")
	var impure := _read_story()
	impure.runtime_hook = Callable(self, "_noop")
	_expect(_has(registry.validate_story(impure), "pure JSON"), "validator accepted a runtime callback")


func _noop() -> void:
	pass


func _snapshot(completed: Array[String], proxy_unlocked: bool, early_complete: bool) -> Dictionary:
	return {"completed_node_ids": completed, "proxy_unlocked": proxy_unlocked, "early_game_complete": early_complete, "equipment_discovered": "mainline_02_priority_under_pressure" in completed, "growth_observed": "mainline_03_first_elite" in completed, "first_growth_state": "convergent", "exponential_observed": "mainline_05_growth_gate" in completed}


func _read_story() -> Dictionary:
	var file := FileAccess.open("res://content/chapter_one_story.json", FileAccess.READ)
	return JSON.parse_string(file.get_as_text())


func _has(errors: Array[String], fragment: String) -> bool:
	for error in errors:
		if fragment in error:
			return true
	return false


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _test_real_evidence_gates(progression: StoryProgression) -> void:
	var snapshot := {"completed_node_ids":["tutorial_ranger_basics", "mainline_01_first_hunt", "mainline_02_priority_under_pressure", "mainline_03_first_elite", "mainline_04_hazard_and_forge", "mainline_05_growth_gate"]}
	var state := progression.evaluate(snapshot,{})
	for entry in state.journal_entries:
		_expect(int(entry.stage) not in [2,3,6], "chapter completion fabricated loot/training/growth evidence")
	_expect(state.current_objective.campaign_node == "threshold_colossus", "optional discovery blocked actual campaign objective")
	for kind in ["convergent", "critical", "exponential"]:
		snapshot["growth_observed"] = true
		snapshot["first_growth_state"] = kind
		snapshot["exponential_observed"] = kind == "exponential"
		state = progression.evaluate(snapshot,{})
		var titles := []
		var has_growth := false
		for entry in state.journal_entries:
			titles.append(entry.title)
			if int(entry.stage) == 6: has_growth = true
		_expect(has_growth == (kind == "exponential"), "true growth story ignored actual classification")
		_expect(("多了，然后停了" in titles) == (kind == "convergent"), "story forced a false failure on a successful player")
