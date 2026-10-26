extends "res://tests/helpers/application_state_suite.gd"

## Ranger build selection, early-game snapshot and Training report authority.
const EarlyItemRegistryScript = preload("res://src/content/early_item_registry.gd")
const SaveStoreScript = preload("res://src/persistence/save_store.gd")
const TrainingReportBuilderScript = preload("res://src/systems/training_report_builder.gd")


func run() -> Array[String]:
	var failures: Array[String] = []
	_test_ranger_build_api_and_training(failures)
	_test_training_report_augmentation(failures)
	return failures


func _test_ranger_build_api_and_training(failures: Array[String]) -> void:
	var state := ApplicationState.new()
	_expect(_code(state.select_ranger_build("critical")) == "profile_required", "build: profile should be required", failures)
	_expect(_code(state.active_build_snapshot()) == "profile_required", "build snapshot: profile should be required", failures)
	_expect(_code(state.early_game_snapshot()) == "profile_required", "early game: profile should be required", failures)
	_expect(_code(state.run_training_trial()) == "profile_required", "training: profile should be required", failures)
	state.start_new_profile("ranger")
	var before: Dictionary = state.early_game_snapshot()
	_expect(before.available_builds.size() == 3, "early game: all ranger builds must be available", failures)
	for index in before.available_builds.size():
		var build: Dictionary = before.available_builds[index]
		_expect(build.name == "Preset %s" % String.chr(65 + index) and build.neutral_name == build.name,
			"early game: unverified build name must be neutral", failures)
		_expect(not bool(build.verified) and String(build.verified_growth_name).is_empty(),
			"early game: growth conclusion leaked before training", failures)
		_expect(String(build.skills[0].name) == "Piercing Arrow" and String(build.runes[0].name) == "Breeding Split" and String(build.laws[0].name) == "Pack Hunt Mark",
			"early game: UI build details are incomplete", failures)
	_expect(bool(before.available_builds[0].selected), "early game: convergent should be selected by default", failures)
	var leaked: Dictionary = state.active_build_snapshot()
	leaked.active_build.skills[0] = "changed"
	_expect(state.profile.active_build.skills[0] == "piercing_arrow", "build snapshot: returned data aliases profile", failures)
	_expect(_code(state.select_ranger_build("missing")) == "unknown_preset", "build: unknown preset error changed", failures)
	var expected_states := {"convergent": "convergent", "critical": "critical", "exponential": "exponential"}
	var expected_r := {"convergent": 0.98, "critical": 1.0, "exponential": 1.22}
	for preset_id in ["convergent", "critical", "exponential"]:
		var selected: Dictionary = state.select_ranger_build(preset_id)
		_expect(bool(selected.get("ok", false)) and selected.active_build.preset_id == preset_id,
			"build: %s was not persisted" % preset_id, failures)
		var trial: Dictionary = state.run_training_trial()
		_expect(bool(trial.get("ok", false)), "training: %s trial failed" % preset_id, failures)
		_expect(int(trial.report.g) == 80 and _near(float(trial.report.R), float(expected_r[preset_id])),
			"training: %s did not use equipped PiercingArrowModel parameters" % preset_id, failures)
		_expect(String(trial.report.state) == String(expected_states[preset_id]) and float(trial.report.event_count) > 0.0,
			"training: %s report state/event count is wrong" % preset_id, failures)
	var trained: Dictionary = state.early_game_snapshot()
	var reports_by_fingerprint: Dictionary = state.profile.training.reports_by_fingerprint
	_expect(reports_by_fingerprint.size() == 3,
		"training: one report per verified fingerprint must persist", failures)
	for fingerprint in reports_by_fingerprint:
		_expect(_is_fingerprint(String(fingerprint)), "training: verification is not a SHA-256 fingerprint", failures)
		_expect(String((reports_by_fingerprint[fingerprint] as Dictionary).build_fingerprint) == String(fingerprint),
			"training: report fingerprint does not match its map key", failures)
	_expect(state.profile.discoveries.size() == 3, "training: three growth discoveries must be recorded", failures)
	for build in trained.available_builds:
		_expect(bool(build.verified) and not String(build.verified_growth_name).is_empty(),
			"training: verified growth name missing", failures)
	(trained.training.reports_by_fingerprint as Dictionary).clear()
	_expect(state.profile.training.reports_by_fingerprint.size() == 3, "early game: snapshot aliases training state", failures)

	# Returning to A after training B must recover A's own report from the map.
	state.select_ranger_build("convergent")
	var returned_to_a := state.early_game_snapshot()
	var current_a_fingerprint := String(state.resolved_build_snapshot().build_fingerprint)
	_expect((returned_to_a.training.reports_by_fingerprint as Dictionary).has(current_a_fingerprint)
		and String(returned_to_a.training.reports_by_fingerprint[current_a_fingerprint].state) == "convergent",
		"training: A to B to A did not recover A's own report", failures)


func _test_training_report_augmentation(failures: Array[String]) -> void:
	var state := ApplicationState.new()
	state.start_new_profile("ranger")
	var seeds := {}
	var actions := {}
	var fingerprints := {}
	for preset_id in ["convergent", "critical", "exponential"]:
		_expect(bool(state.select_ranger_build(preset_id).get("ok", false)),
			"training augmentation: %s selection failed" % preset_id, failures)
		var first: Dictionary = state.run_training_trial()
		_expect(bool(first.get("ok", false)), "training augmentation: %s trial failed" % preset_id, failures)
		var report: Dictionary = first.report
		var seed_value: Variant = report.get("training_seed", null)
		_expect(seed_value is int and int(seed_value) >= 0 and int(seed_value) <= 9007199254740991,
			"training augmentation: %s seed must be a JSON-safe non-negative int" % preset_id, failures)
		if seed_value is int:
			seeds[preset_id] = int(seed_value)
		fingerprints[preset_id] = String(report.get("build_fingerprint", ""))
		var action_value: Variant = report.get("action", null)
		_expect(action_value is String and not String(action_value).strip_edges().is_empty(),
			"training augmentation: %s action must be one non-empty sentence" % preset_id, failures)
		if action_value is String:
			actions[preset_id] = String(action_value)
		var curve_value: Variant = report.get("growth_curve", null)
		_expect(curve_value is Array and (curve_value as Array).size() >= 1,
			"training augmentation: %s growth curve is missing or empty" % preset_id, failures)
		if curve_value is Array:
			var curve: Array = curve_value
			_expect(curve.size() >= 4 and curve.size() <= 6,
				"training augmentation: %s curve must carry 4-6 sample points" % preset_id, failures)
			var previous_generation := -1
			for point_value in curve:
				_expect(point_value is Dictionary,
					"training augmentation: %s curve points must be dictionaries" % preset_id, failures)
				if not point_value is Dictionary:
					continue
				var point: Dictionary = point_value
				var generation: Variant = point.get("generation", null)
				var display: Variant = point.get("events_display", null)
				_expect(generation is int and display is String and not String(display).is_empty(),
					"training augmentation: %s curve point must carry generation and events_display" % preset_id, failures)
				if generation is int:
					_expect(int(generation) > previous_generation,
						"training augmentation: %s curve generations must strictly increase" % preset_id, failures)
					previous_generation = int(generation)
			if curve.size() >= 2 and curve[0] is Dictionary and curve[curve.size() - 1] is Dictionary:
				_expect(int((curve[0] as Dictionary).get("generation", -1)) == 0
					and int((curve[curve.size() - 1] as Dictionary).get("generation", -1)) == int(report.g),
					"training augmentation: %s curve must start at G0 and end at Gg" % preset_id, failures)
				_expect(String((curve[curve.size() - 1] as Dictionary).get("events_display", "")) == String(report.event_count_display),
					"training augmentation: %s final point must match event_count_display" % preset_id, failures)
		var second: Dictionary = state.run_training_trial()
		_expect(bool(second.get("ok", false)) and first.report == second.report,
			"training augmentation: %s rerun must reproduce the identical report" % preset_id, failures)
	var distinct_seeds := {}
	for preset_id in seeds:
		distinct_seeds[int(seeds[preset_id])] = true
	_expect(seeds.size() == 3 and distinct_seeds.size() >= 2 and fingerprints.size() == 3,
		"training augmentation: at least two distinct fingerprints must derive distinct seeds", failures)
	_expect(not SaveStoreScript.canonical_json(state.persistent_payload("base")).is_empty(),
		"training augmentation: persisted report exceeded canonical JSON limits", failures)
	_expect(String(actions.get("convergent", "")) != String(actions.get("critical", ""))
		and String(actions.get("critical", "")) != String(actions.get("exponential", ""))
		and String(actions.get("convergent", "")) != String(actions.get("exponential", "")),
		"training augmentation: the three growth states must produce distinct actions", failures)

	# The seed is a pure function of the fingerprint: a fresh instance and a
	# fresh trial must reproduce it exactly (process/restart stability proxy).
	var replay := ApplicationState.new()
	replay.start_new_profile("ranger")
	replay.select_ranger_build("exponential")
	var replay_trial: Dictionary = replay.run_training_trial()
	_expect(int(replay_trial.report.get("training_seed", -1)) == int(seeds.get("exponential", -1))
		and replay_trial.report.get("training_seed", -1) is int,
		"training augmentation: seed must be reproducible in a fresh instance", failures)

	# A real fresh starting build carries neither breeding_split nor
	# pack_hunt_mark, so the interface guidance must outrank the state sentence.
	var starter := ApplicationState.new()
	starter.start_new_profile("ranger")
	var starter_trial: Dictionary = starter.run_training_trial()
	var starter_action := String(starter_trial.report.get("action", ""))
	_expect(starter_action.contains("Breedable Child Arrows") and not starter_action.contains("breedable_event") and not starter_action.contains("branch_target_history"),
		"training augmentation: missing breeding_split must use its English name without raw ids", failures)
	_expect(not starter_action.contains("Find") and not starter_action.contains("combat"),
		"training augmentation: interface action must outrank growth-state advice", failures)

	# A crafted starting build with breeding_split but no pack_hunt_mark leaves
	# exactly branch_target_history missing and must select that tier.
	var crafted := _training_state_with_features(["breeding_split"], [])
	_expect(crafted != null, "training augmentation: crafted build restore failed", failures)
	if crafted != null:
		var crafted_trial: Dictionary = crafted.run_training_trial()
		var crafted_action := String(crafted_trial.report.get("action", ""))
		_expect(crafted_action.contains("Branch Target History") and not crafted_action.contains("branch_target_history") and not crafted_action.contains("breedable_event"),
			"training augmentation: missing pack_hunt_mark must use its English name without raw ids", failures)
	var known_interface_names := {
		"piercing_continuation": "Piercing Continuation",
		"breedable_event": "Breedable Child Arrows",
		"branch_hit_counter": "Branch Hit Counter",
		"branch_target_history": "Branch Target History",
		"lineage_lifetime_pause": "Lineage Lifetime Pause",
	}
	for interface_id in known_interface_names:
		var known_action := TrainingReportBuilderScript.action({"missing_interfaces": [interface_id]})
		_expect(known_action.contains(String(known_interface_names[interface_id])) and not known_action.contains(String(interface_id)),
			"training augmentation: known interface %s leaked its raw id or lost its English name" % interface_id, failures)
	var fallback_action := TrainingReportBuilderScript.action({"missing_interfaces": ["lineage_lifetime_pause", "experimental_link"]})
	_expect(fallback_action.contains("Lineage Lifetime Pause") and fallback_action.contains("Unknown Interface (experimental_link)"),
		"training augmentation: fallback interface guidance must use shared names and retain unknown ids", failures)

	# Tampering with the returned report must not pollute the stored map entry
	# and curve points must be distinct dictionaries, not shared aliases.
	var tamper_state := ApplicationState.new()
	tamper_state.start_new_profile("ranger")
	tamper_state.select_ranger_build("exponential")
	var tamper_trial: Dictionary = tamper_state.run_training_trial()
	var tampered: Dictionary = tamper_trial.report
	var original_first := String((tampered.growth_curve as Array)[0].events_display)
	var original_seed: Variant = tampered.training_seed
	var original_action: Variant = tampered.action
	(tampered.growth_curve as Array)[0].events_display = "HACKED"
	(tampered.growth_curve as Array)[0].generation = -100
	tampered.training_seed = -1
	tampered.action = "HACKED"
	var tamper_fingerprint := String(tamper_trial.report.build_fingerprint)
	var stored: Dictionary = tamper_state.profile.training.reports_by_fingerprint[tamper_fingerprint]
	_expect(String((stored.growth_curve as Array)[0].events_display) == original_first
		and int((stored.growth_curve as Array)[0].generation) == 0
		and int(stored.training_seed) == int(original_seed)
		and String(stored.action) == String(original_action),
		"training augmentation: tampering the returned report polluted the stored fingerprint report", failures)
	_expect(int((tampered.growth_curve as Array)[1].generation) == int((stored.growth_curve as Array)[1].generation)
		and String((tampered.growth_curve as Array)[1].events_display) != "HACKED",
		"training augmentation: growth curve points must not alias each other", failures)
	var replacement: Dictionary = tamper_state.run_training_trial()
	_expect(tamper_state.profile.training.reports_by_fingerprint.size() == 1
		and replacement.report == tamper_state.profile.training.reports_by_fingerprint[tamper_fingerprint]
		and String((replacement.report.growth_curve as Array)[0].events_display) == original_first,
		"training augmentation: repeated training did not deterministically replace the same map entry", failures)
	(replacement.report.growth_curve as Array)[0].events_display = "SECOND HACK"
	_expect(String((tamper_state.profile.training.reports_by_fingerprint[tamper_fingerprint].growth_curve as Array)[0].events_display) == original_first,
		"training augmentation: replacement return value aliases persisted state", failures)
	var persisted := tamper_state.persistent_payload("base")
	var restored := ApplicationState.new()
	_expect(bool(restored.restore_persistent_payload(persisted).get("ok", false))
		and restored.profile.training == tamper_state.profile.training,
		"training augmentation: report map did not survive persistence round-trip", failures)


func _training_state_with_features(runes: Array, laws: Array) -> ApplicationState:
	var state := ApplicationState.new()
	state.start_new_profile("ranger")
	var payload: Dictionary = state.persistent_payload("base")
	var registry := EarlyItemRegistryScript.new()
	if not registry.load_all().is_empty():
		return null
	var equipped: Dictionary = payload.profile.active_build.equipped_item_ids
	for rune_id in runes:
		if String(rune_id) != "breeding_split":
			return null
		var rune_item: Dictionary = registry.item_instances.reward_mainline_03_breeding_split_gloves.duplicate(true)
		(payload.profile.inventory.equipment as Array).append(rune_item)
		equipped["gloves"] = String(rune_item.instance_id)
	for law_id in laws:
		if String(law_id) != "pack_hunt_mark":
			return null
		var law_item: Dictionary = registry.item_instances.reward_mainline_05_pack_hunt_mark_ring.duplicate(true)
		(payload.profile.inventory.equipment as Array).append(law_item)
		equipped["ring_1"] = String(law_item.instance_id)
	if not bool(state.restore_persistent_payload(payload).get("ok", false)):
		return null
	return state


func _near(actual: float, expected: float) -> bool:
	return absf(actual - expected) < 0.000001
