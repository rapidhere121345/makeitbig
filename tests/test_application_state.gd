extends RefCounted

const ApplicationState = preload("res://src/game/application_state.gd")
const BuildResolverScript = preload("res://src/systems/build_resolver.gd")
const EarlyItemRegistryScript = preload("res://src/content/early_item_registry.gd")
const LawForgeScript = preload("res://src/systems/law_forge.gd")
const ContractPlanScript = preload("res://src/game/contract_plan.gd")
const SaveStoreScript = preload("res://src/persistence/save_store.gd")


func run() -> Array[String]:
	var failures: Array[String] = []
	_test_defaults(failures)
	_test_class_validation_and_new_profile(failures)
	_test_tutorial_completion(failures)
	_test_ranger_build_api_and_training(failures)
	_test_training_report_augmentation(failures)
	_test_campaign_progression(failures)
	_test_proxy_component_transactions(failures)
	_test_auto_certification_graduation_normalization(failures)
	_test_first_hunt_equipment_drop_gate(failures)
	_test_alias_isolation(failures)
	_test_forge_defaults_and_preview(failures)
	_test_forge_context_normalization(failures)
	_test_forge_commit_and_atomic_failure(failures)
	_test_forge_inventory_target_preview_and_commit(failures)
	_test_forge_unique_result_horizon(failures)
	_test_contract_validation(failures)
	_test_session_lifecycle(failures)
	_test_reward_settlement(failures)
	_test_room_equipment_drop_settlement(failures)
	_test_boss_defeat_bottleneck(failures)
	_test_abandon(failures)
	_test_persistent_payload(failures)
	_test_old_schema_rejected(failures)
	_test_atomic_equipment_and_resolved_snapshot(failures)
	_test_restore_clears_transient_state(failures)
	_test_restore_rejects_atomically(failures)
	_test_repeatable_side_counting(failures)
	_test_repeatable_pity_guarantee(failures)
	_test_repeatable_pity_period(failures)
	_test_repeatable_seed_identity_and_isolation(failures)
	_test_repeatable_counts_persistence_and_validation(failures)
	_test_equip_preview_errors_are_atomic(failures)
	_test_equip_preview_matches_real_equip(failures)
	_test_equip_preview_interface_deltas(failures)
	_test_equip_preview_session_invariance(failures)
	_test_salvage_validation_errors(failures)
	_test_salvage_track_mapping_and_consistency(failures)
	_test_salvage_commit_and_atomics(failures)
	_test_salvage_persistence_roundtrip(failures)
	return failures


func _test_defaults(failures: Array[String]) -> void:
	var state := ApplicationState.new()
	_expect(not state.has_profile(), "defaults: profile should be absent", failures)
	_expect(state.profile.is_empty() and state.pending_contract.is_empty(), "defaults: profile and pending should be empty", failures)
	_expect(state.active_session.is_empty() and state.last_result.is_empty(), "defaults: session and result should be empty", failures)
	state.reset()
	_expect(not state.has_profile(), "defaults: reset should remain empty", failures)


func _test_class_validation_and_new_profile(failures: Array[String]) -> void:
	var state := ApplicationState.new()
	_expect(_code(state.start_new_profile("warrior")) == "invalid_class", "profile: unsupported class should fail", failures)
	var created: Dictionary = state.start_new_profile(" MAGE ")
	_expect(bool(created.get("ok", false)), "profile: supported class should create a profile", failures)
	var profile: Dictionary = state.profile
	_expect(int(profile.schema_version) == ApplicationState.PROFILE_SCHEMA_VERSION and profile.initial_class == "mage", "profile: schema or class changed", failures)
	_expect(profile.resources == {"law_tallies": {"inscribe": 0, "rewrite": 0, "refine": 0}} and not profile.has("forge"),
		"profile: Law Tally resource shape is wrong", failures)
	_expect(profile.inventory.keys() == ["equipment", "proxy_components", "legacy_drops"]
		and profile.inventory.equipment.size() == 4
		and profile.inventory.proxy_components.is_empty()
		and profile.inventory.legacy_drops.is_empty(), "profile: partitioned inventory shape is wrong", failures)
	_expect(profile.active_build.keys() == ["skills", "equipped_item_ids"]
		and profile.active_build.skills == ["piercing_arrow", "", ""]
		and profile.active_build.equipped_item_ids.size() == 12,
		"profile: persisted active build shape is wrong", failures)
	for slot in profile.active_build.equipped_item_ids:
		var expected_open: bool = slot in ["main_hand", "off_hand", "gloves", "ring_1"]
		_expect(not String(profile.active_build.equipped_item_ids[slot]).is_empty() == expected_open,
			"profile: fixed_start slot population is wrong for %s" % slot, failures)
	_expect(not profile.has("resolved_build") and not profile.active_build.has("resolved_build"),
		"profile: derived resolved build was persisted", failures)
	_expect(profile.proxy_build == {"cores": ["", "", "", ""], "settings": {}, "attachments": ["", "", ""]},
		"profile: schema 8 proxy build shape is wrong", failures)
	_expect(profile.progression.completed_node_ids == [], "profile: campaign completion should start empty", failures)


func _test_tutorial_completion(failures: Array[String]) -> void:
	var state := ApplicationState.new()
	_expect(_code(state.complete_tutorial()) == "profile_required", "tutorial: profile should be required", failures)
	state.start_new_profile("ranger")
	_expect(not bool(state.profile.tutorial_complete), "tutorial: new profile should start incomplete", failures)
	var completed: Dictionary = state.complete_tutorial()
	_expect(bool(completed.get("ok", false)) and bool(state.profile.tutorial_complete), "tutorial: completion was not persisted in profile", failures)
	state.complete_tutorial()
	_expect(state.profile.progression.completed_node_ids == ["tutorial_ranger_basics"],
		"tutorial: fixed tutorial node was not recorded exactly once", failures)


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
		_expect(build.name == "方案 %s" % String.chr(65 + index) and build.neutral_name == build.name,
			"early game: unverified build name must be neutral", failures)
		_expect(not bool(build.verified) and String(build.verified_growth_name).is_empty(),
			"early game: growth conclusion leaked before training", failures)
		_expect(String(build.skills[0].name) == "穿刺箭" and String(build.runes[0].name) == "孳生分裂" and String(build.laws[0].name) == "群猎印记",
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
	_expect(starter_action.contains("可繁殖子箭") and not starter_action.contains("breedable_event") and not starter_action.contains("branch_target_history"),
		"training augmentation: missing breeding_split must use its Chinese name without raw ids", failures)
	_expect(not starter_action.contains("寻找") and not starter_action.contains("实战"),
		"training augmentation: interface action must outrank growth-state advice", failures)

	# A crafted starting build with breeding_split but no pack_hunt_mark leaves
	# exactly branch_target_history missing and must select that tier.
	var crafted := _training_state_with_features(["breeding_split"], [])
	_expect(crafted != null, "training augmentation: crafted build restore failed", failures)
	if crafted != null:
		var crafted_trial: Dictionary = crafted.run_training_trial()
		var crafted_action := String(crafted_trial.report.get("action", ""))
		_expect(crafted_action.contains("分支目标记录") and not crafted_action.contains("branch_target_history") and not crafted_action.contains("breedable_event"),
			"training augmentation: missing pack_hunt_mark must use its Chinese name without raw ids", failures)
	var known_interface_names := {
		"piercing_continuation": "穿刺续行",
		"breedable_event": "可繁殖子箭",
		"branch_hit_counter": "分支命中计数",
		"branch_target_history": "分支目标记录",
		"lineage_lifetime_pause": "谱系寿命暂停",
	}
	for interface_id in known_interface_names:
		var known_action := state._training_action({"missing_interfaces": [interface_id]})
		_expect(known_action.contains(String(known_interface_names[interface_id])) and not known_action.contains(String(interface_id)),
			"training augmentation: known interface %s leaked its raw id or lost its Chinese name" % interface_id, failures)
	var fallback_action := state._training_action({"missing_interfaces": ["lineage_lifetime_pause", "experimental_link"]})
	_expect(fallback_action.contains("谱系寿命暂停") and fallback_action.contains("未收录接口（experimental_link）"),
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


func _test_campaign_progression(failures: Array[String]) -> void:
	var state := ApplicationState.new()
	_expect(_code(state.campaign_progress_snapshot()) == "profile_required", "campaign: profile should be required", failures)
	state.start_new_profile()
	var initial: Dictionary = state.campaign_progress_snapshot()
	_expect(initial.completed_node_ids == []
		and initial.available_node_ids == ["tutorial_ranger_basics"]
		and initial.next_mainline_node_id == "tutorial_ranger_basics",
		"campaign: initial availability or stable next node is wrong", failures)
	state.complete_tutorial()
	var after_tutorial: Dictionary = state.campaign_progress_snapshot()
	_expect(after_tutorial.completed_node_ids == ["tutorial_ranger_basics"]
		and after_tutorial.earned_reward_tags == ["starter_loadout"]
		and after_tutorial.available_node_ids == ["mainline_01_first_hunt"]
		and after_tutorial.next_mainline_node_id == "mainline_01_first_hunt",
		"campaign: tutorial did not unlock the first mainline node", failures)
	var initial_build: Dictionary = state.profile.active_build
	var premature_boss := _grant_session_result(state, "threshold_colossus", "Manual", "victory")
	var premature_auto := _grant_session_result(state, "auto_certification", "Auto", "victory")
	_expect(not state.is_auto_mode_unlocked()
		and int(state.profile.progression.auto_contract_wins) == 0
		and not bool(state.profile.progression.early_game_complete)
		and premature_boss.result.first_reward_tags == []
		and premature_auto.result.first_reward_tags == []
		and state.profile.active_build == initial_build,
		"campaign: authored prerequisites were bypassed through direct settlement", failures)
	var first_hunt := _grant_session_result(state, "mainline_01_first_hunt", "Manual", "victory")
	_expect(first_hunt.result.first_reward_tags == ["hunter_mark_skill", "equipment_compare_unlock"]
		and state.profile.active_build.skills == ["piercing_arrow", "hunter_mark", ""],
		"campaign rewards: first hunt did not grant hunter_mark in slot 2", failures)
	(first_hunt.result.first_reward_tags as Array)[0] = "tampered"
	_expect(state.last_result.first_reward_tags == ["hunter_mark_skill", "equipment_compare_unlock"],
		"campaign rewards: result first_reward_tags aliases internal result state", failures)
	var priority := _grant_session_result(state, "mainline_02_priority_under_pressure", "Manual", "victory")
	_expect(priority.result.first_reward_tags == ["dash_skill"]
		and state.profile.active_build.skills == ["piercing_arrow", "hunter_mark", "dash"],
		"campaign rewards: priority node did not grant dash in slot 3", failures)
	var failed_elite := _grant_session_result(state, "mainline_03_first_elite", "Manual", "defeat")
	_expect(failed_elite.result.first_reward_tags == []
		and _equipment_instance_count(state.profile.inventory.equipment, "reward_mainline_03_breeding_split_gloves") == 0,
		"campaign rewards: failed elite granted the stable semantic item", failures)
	var build_before_rune_reward: Dictionary = state.profile.active_build
	var before_rune: Dictionary = state.resolved_build_snapshot()
	var elite := _grant_session_result(state, "mainline_03_first_elite", "Manual", "victory")
	var after_rune: Dictionary = state.resolved_build_snapshot()
	_expect(elite.result.first_reward_tags == ["breeding_split_item"]
		and _equipment_instance_count(state.profile.inventory.equipment, "reward_mainline_03_breeding_split_gloves") == 1
		and _has_equipment_instance(elite.result.rewards.equipment_drops, "reward_mainline_03_breeding_split_gloves")
		and state.profile.active_build == build_before_rune_reward
		and String(after_rune.build_fingerprint) == String(before_rune.build_fingerprint)
		and after_rune.connected_interfaces == before_rune.connected_interfaces,
		"campaign rewards: elite item was not inventory-only before equip", failures)
	var equipped_rune := state.equip_item("reward_mainline_03_breeding_split_gloves")
	_expect(bool(equipped_rune.get("ok", false))
		and String(state.profile.active_build.equipped_item_ids.gloves) == "reward_mainline_03_breeding_split_gloves"
		and equipped_rune.resolved_build.rune_ids == ["breeding_split"]
		and "breedable_event" in (equipped_rune.resolved_build.connected_interfaces as Array)
		and String(equipped_rune.resolved_build.build_fingerprint) != String(before_rune.build_fingerprint),
		"campaign rewards: equipped mainline 03 instance did not own its rune/interface change", failures)
	var repeated_elite := _grant_session_result(state, "mainline_03_first_elite", "Manual", "victory")
	_expect(repeated_elite.result.first_reward_tags == []
		and _equipment_instance_count(state.profile.inventory.equipment, "reward_mainline_03_breeding_split_gloves") == 1,
		"campaign rewards: repeated elite completion duplicated the stable item", failures)
	var branch_snapshot: Dictionary = state.campaign_progress_snapshot()
	_expect(branch_snapshot.available_node_ids == ["mainline_04_hazard_and_forge", "side_targeted_equipment"]
		and "side_affix_and_law_tallies" in branch_snapshot.locked_node_ids,
		"campaign: fixed line or first repeatable branch availability is wrong", failures)
	var forge_reward := _grant_session_result(state, "mainline_04_hazard_and_forge", "Manual", "victory")
	_expect(forge_reward.result.first_reward_tags == ["law_forge_unlock"],
		"campaign rewards: forge unlock tag was not reported", failures)
	var forge_branch_snapshot: Dictionary = state.campaign_progress_snapshot()
	_expect(forge_branch_snapshot.available_node_ids == [
		"mainline_05_growth_gate", "side_targeted_equipment", "side_affix_and_law_tallies",
	], "campaign: repeatable branches did not become available in stable order", failures)
	var failed_growth := _grant_session_result(state, "mainline_05_growth_gate", "Manual", "defeat")
	_expect(failed_growth.result.first_reward_tags == []
		and _equipment_instance_count(state.profile.inventory.equipment, "reward_mainline_05_pack_hunt_mark_ring") == 0,
		"campaign rewards: failed growth gate granted the stable semantic item", failures)
	var build_before_law_reward: Dictionary = state.profile.active_build
	var before_law: Dictionary = state.resolved_build_snapshot()
	var growth_gate := _grant_session_result(state, "mainline_05_growth_gate", "Manual", "victory")
	var after_law: Dictionary = state.resolved_build_snapshot()
	_expect(growth_gate.result.first_reward_tags == ["pack_hunt_mark_item"]
		and _equipment_instance_count(state.profile.inventory.equipment, "reward_mainline_05_pack_hunt_mark_ring") == 1
		and _has_equipment_instance(growth_gate.result.rewards.equipment_drops, "reward_mainline_05_pack_hunt_mark_ring")
		and state.profile.active_build == build_before_law_reward
		and String(after_law.build_fingerprint) == String(before_law.build_fingerprint)
		and after_law.connected_interfaces == before_law.connected_interfaces,
		"campaign rewards: growth-gate item was not inventory-only before equip", failures)
	var equipped_law := state.equip_item("reward_mainline_05_pack_hunt_mark_ring")
	_expect(bool(equipped_law.get("ok", false))
		and String(state.profile.active_build.equipped_item_ids.ring_1) == "reward_mainline_05_pack_hunt_mark_ring"
		and equipped_law.resolved_build.law_ids == ["pack_hunt_mark"]
		and "branch_target_history" in (equipped_law.resolved_build.connected_interfaces as Array)
		and String(equipped_law.resolved_build.build_fingerprint) != String(before_law.build_fingerprint),
		"campaign rewards: equipped mainline 05 instance did not own its law/interface change", failures)
	_expect(not state.is_auto_mode_unlocked(), "proxy: new profile must not unlock Auto", failures)
	var ordinary := _grant_session_result(state, "ordinary_auto_contract", "Auto", "victory")
	var wrong_boss_mode := _grant_session_result(state, "threshold_colossus", "Auto", "victory")
	var wrong_auto_mode := _grant_session_result(state, "auto_certification", "Manual", "victory")
	_expect(not state.is_auto_mode_unlocked() and int(state.profile.progression.auto_contract_wins) == 0
		and not bool(state.profile.progression.early_game_complete)
		and ordinary.result.first_reward_tags == []
		and wrong_boss_mode.result.first_reward_tags == []
		and wrong_auto_mode.result.first_reward_tags == [],
		"campaign: wrong contract or mode crossed a progression authority boundary", failures)
	var boss_defeat := _grant_session_result(state, "threshold_colossus", "Manual", "defeat")
	_expect(not state.is_auto_mode_unlocked() and state.profile.inventory.proxy_components.is_empty()
		and boss_defeat.result.first_reward_tags == [],
		"proxy: Boss defeat advanced first-kill progression", failures)
	var victory := _grant_session_result(state, "threshold_colossus", "Manual", "victory")
	var expected_cores := ["near_enemy_horizon", "direct_gait", "single_key_execution", "short_trace_memory"]
	_expect(state.profile.proxy_build.cores == expected_cores and state.profile.inventory.proxy_components.size() == 4,
		"proxy: threshold colossus first victory did not equip/inventory the fixed four cores", failures)
	var resolved_proxy: Dictionary = state.resolved_proxy_build_snapshot()
	_expect(bool(resolved_proxy.get("ok", false))
		and (resolved_proxy.get("resolved_proxy_build", {}) as Dictionary).get("cores", []).size() == 4
		and String((resolved_proxy.get("resolved_proxy_build", {}) as Dictionary).get("semantic_fingerprint", "")).length() == 64,
		"proxy: installed profile build did not compile into a resolved contract", failures)
	if bool(resolved_proxy.get("ok", false)):
		(resolved_proxy.resolved_proxy_build.cores[0] as Dictionary)["core_id"] = "tampered"
		var resolved_again: Dictionary = state.resolved_proxy_build_snapshot()
		_expect(bool(resolved_again.get("ok", false))
			and String(resolved_again.resolved_proxy_build.cores[0].core_id) == "near_enemy_horizon",
			"proxy: resolved profile snapshots shared mutable output", failures)
	_expect(state.is_auto_mode_unlocked() and bool(state.profile.progression.threshold_colossus_defeated),
		"proxy: threshold colossus first victory did not unlock proxy progression", failures)
	_expect(bool(victory.result.unlock.proxy_unlocked) and victory.result.unlock.components.size() == 4,
		"proxy: settlement result lacks unlock presentation data", failures)
	_expect(victory.result.first_reward_tags == ["fixed_four_white_proxy_cores"],
		"campaign rewards: Boss first reward tag was not reported", failures)
	for item in state.profile.inventory.proxy_components:
		_expect(String(item.rarity) == "white" and String(item.type) == "proxy_core",
			"proxy: first-kill component must be a white proxy core", failures)
	var repeated_boss := _grant_session_result(state, "threshold_colossus", "Manual", "victory")
	_expect(state.profile.inventory.proxy_components.size() == 4
		and state.profile.progression.completed_node_ids.count("threshold_colossus") == 1
		and _equipment_instance_count(state.profile.inventory.equipment, "reward_mainline_03_breeding_split_gloves") == 1
		and _equipment_instance_count(state.profile.inventory.equipment, "reward_mainline_05_pack_hunt_mark_ring") == 1
		and repeated_boss.result.first_reward_tags == [],
		"proxy: repeated Boss victory duplicated cores or fixed completion", failures)
	var certification_defeat := _grant_session_result(state, "auto_certification", "Auto", "defeat")
	_expect(int(state.profile.progression.auto_contract_wins) == 0
		and certification_defeat.result.first_reward_tags == [],
		"early game: certification defeat advanced wins", failures)
	var certification := _grant_session_result(state, "auto_certification", "Auto", "victory")
	_expect(int(state.profile.progression.auto_contract_wins) == 1 and bool(state.profile.progression.early_game_complete),
		"early game: Auto certification victory did not complete", failures)
	_expect(certification.result.first_reward_tags == ["early_campaign_complete"],
		"campaign rewards: completion tag was not reported", failures)
	var repeated_certification := _grant_session_result(state, "auto_certification", "Auto", "victory")
	_expect(int(state.profile.progression.auto_contract_wins) == 2
		and state.profile.progression.completed_node_ids.count("auto_certification") == 1
		and repeated_certification.result.first_reward_tags == [],
		"early game: repeated certification win was not counted or duplicated fixed completion", failures)
	var completed_snapshot: Dictionary = state.campaign_progress_snapshot()
	_expect(completed_snapshot.next_mainline_node_id.is_empty()
		and completed_snapshot.available_node_ids == ["side_targeted_equipment", "side_affix_and_law_tallies"]
		and completed_snapshot.earned_reward_tags == [
			"starter_loadout", "hunter_mark_skill", "equipment_compare_unlock", "dash_skill",
			"breeding_split_item", "law_forge_unlock", "pack_hunt_mark_item",
			"fixed_four_white_proxy_cores", "early_campaign_complete",
		]
		and bool(completed_snapshot.early_game_complete),
		"campaign: completed fixed campaign snapshot or earned tag order is wrong", failures)
	(completed_snapshot.earned_reward_tags as Array)[0] = "tampered"
	_expect(state.campaign_progress_snapshot().earned_reward_tags[0] == "starter_loadout",
		"campaign rewards: earned_reward_tags snapshot aliases derived state", failures)


func _test_auto_certification_graduation_normalization(failures: Array[String]) -> void:
	# The real Auto certification victory after the Boss prerequisite is the
	# graduation settlement: persisted/returned/last_result outcome becomes
	# final_victory while the caller's raw result stays an ordinary victory.
	var state := _unlock_auto_certification()
	state.prepare_contract({"contract_id": "auto_certification", "mode": "Auto", "seed": 1, "room_count": 1})
	state.begin_session()
	var caller_result := {"outcome": "victory", "rewards": {"contract_wins_delta": 1}}
	var caller_before := caller_result.duplicate(true)
	var graduated: Dictionary = state.complete_session(caller_result)
	_expect(bool(graduated.get("ok", false))
		and String(graduated.result.outcome) == "final_victory"
		and String(state.last_result.outcome) == "final_victory",
		"auto graduation: authoritative settlement did not normalize to final_victory", failures)
	_expect(caller_result == caller_before and String(caller_result.outcome) == "victory",
		"auto graduation: caller result was mutated or relabeled", failures)
	_expect(bool(state.profile.progression.ending_unlocked)
		and bool(state.profile.progression.early_game_complete)
		and int(state.profile.progression.auto_contract_wins) == 1
		and "auto_certification" in (state.profile.progression.completed_node_ids as Array)
		and graduated.result.first_reward_tags == ["early_campaign_complete"],
		"auto graduation: normalized settlement did not synchronize ending/wins/completion", failures)

	var payload: Dictionary = state.persistent_payload("base")
	_expect(String(payload.last_result.outcome) == "final_victory"
		and bool(payload.profile.progression.ending_unlocked)
		and bool(payload.profile.progression.early_game_complete)
		and int(payload.profile.progression.auto_contract_wins) == 1,
		"auto graduation: persisted payload lost the normalized settlement", failures)
	var restored := ApplicationState.new()
	_expect(bool(restored.restore_persistent_payload(payload).get("ok", false))
		and String(restored.last_result.outcome) == "final_victory"
		and bool(restored.profile.progression.ending_unlocked)
		and bool(restored.profile.progression.early_game_complete),
		"auto graduation: restore did not round-trip the normalized settlement", failures)

	# Repeated certification victory is ordinary farming, not a second graduation.
	state.prepare_contract({"contract_id": "auto_certification", "mode": "Auto", "seed": 2, "room_count": 1})
	state.begin_session()
	var repeated: Dictionary = state.complete_session({"outcome": "victory", "rewards": {"contract_wins_delta": 1}})
	_expect(String(repeated.result.outcome) == "victory"
		and String(state.last_result.outcome) == "victory"
		and int(state.profile.progression.auto_contract_wins) == 2
		and state.profile.progression.completed_node_ids.count("auto_certification") == 1
		and repeated.result.first_reward_tags == [],
		"auto graduation: repeated certification was mis-normalized or double-counted", failures)

	# Error and defeat outcomes never normalize.
	var error_state := _unlock_auto_certification()
	error_state.prepare_contract({"contract_id": "auto_certification", "mode": "Auto", "seed": 3, "room_count": 1})
	error_state.begin_session()
	var error_result: Dictionary = error_state.complete_session({"outcome": "error", "error": "room_runtime_failed"})
	_expect(String(error_result.result.outcome) == "error" and not bool(error_state.profile.progression.ending_unlocked),
		"auto graduation: error outcome was normalized", failures)
	var defeat_state := _unlock_auto_certification()
	defeat_state.prepare_contract({"contract_id": "auto_certification", "mode": "Auto", "seed": 4, "room_count": 1})
	defeat_state.begin_session()
	var defeat_result: Dictionary = defeat_state.complete_session({"outcome": "defeat"})
	_expect(String(defeat_result.result.outcome) == "defeat" and int(defeat_state.profile.progression.auto_contract_wins) == 0,
		"auto graduation: defeat outcome was normalized", failures)

	# Wrong mode, ordinary contract, and unmet Boss prerequisite never normalize.
	var wrong_mode_state := _unlock_auto_certification()
	_expect(String(_grant_session_result(wrong_mode_state, "auto_certification", "Manual", "victory").result.outcome) == "victory"
		and int(wrong_mode_state.profile.progression.auto_contract_wins) == 0
		and not bool(wrong_mode_state.profile.progression.ending_unlocked),
		"auto graduation: Manual auto certification victory was normalized", failures)
	var ordinary_state := _unlock_auto_certification()
	_expect(String(_grant_session_result(ordinary_state, "ordinary_auto_contract", "Auto", "victory").result.outcome) == "victory"
		and not bool(ordinary_state.profile.progression.ending_unlocked),
		"auto graduation: ordinary contract victory was normalized", failures)
	var premature_state := ApplicationState.new()
	premature_state.start_new_profile()
	var premature: Dictionary = _grant_session_result(premature_state, "auto_certification", "Auto", "victory")
	_expect(String(premature.result.outcome) == "victory"
		and int(premature_state.profile.progression.auto_contract_wins) == 0
		and not bool(premature_state.profile.progression.early_game_complete)
		and not bool(premature_state.profile.progression.ending_unlocked),
		"auto graduation: Boss prerequisite was bypassed through normalization", failures)


func _test_proxy_component_transactions(failures: Array[String]) -> void:
	var locked := ApplicationState.new()
	locked.start_new_profile()
	var locked_before := locked.profile
	_expect(_code(locked.equip_proxy_core("near_enemy_horizon")) == "proxy_locked" and locked.profile == locked_before,
		"proxy transaction: locked profile equip was not rejected atomically", failures)

	var state := _unlock_auto_certification()
	var initial_build: Dictionary = state.profile.proxy_build
	var expected_initial := ["near_enemy_horizon", "direct_gait", "single_key_execution", "short_trace_memory"]
	_expect(initial_build == {"cores": expected_initial, "settings": {}, "attachments": ["", "", ""]},
		"proxy transaction: initial four-core raw build is not schema 8 canonical shape", failures)
	var initial_inventory: Array = state.profile.inventory.proxy_components
	_expect(initial_inventory.size() == 4, "proxy transaction: initial inventory count is wrong", failures)
	for index in initial_inventory.size():
		var item: Dictionary = initial_inventory[index]
		_expect(item.keys() == ["id", "name", "slot", "rarity", "type", "protocol", "source_contract"]
			and String(item.id) == String(expected_initial[index])
			and not String(item.name).is_empty() and not String(item.protocol).is_empty()
			and String(item.rarity) == "white" and String(item.type) == "proxy_core"
			and String(item.source_contract) == "threshold_colossus",
			"proxy transaction: initial component metadata is incomplete or out of order", failures)

	var snapshot: Dictionary = state.early_game_snapshot()
	var catalog_ids: Array = (snapshot.proxy.catalog as Dictionary).keys()
	for core_id in catalog_ids:
		var entry: Dictionary = snapshot.proxy.catalog[core_id]
		_expect((entry as Dictionary).keys() == ["id", "name", "slot", "protocol", "settings_schema", "default_settings"]
			and String(entry.id) == String(core_id)
			and not String((entry as Dictionary).name).is_empty()
			and not String((entry as Dictionary).protocol).is_empty(),
			"proxy transaction: readable catalog metadata shape is wrong", failures)
	_expect(snapshot.proxy.keys() == ["build", "unlocked", "inventory", "catalog", "resolved_build"]
		and catalog_ids == ["near_enemy_horizon", "marking_prism", "direct_gait", "distance_keeping_gait", "single_key_execution", "short_trace_memory"]
		and snapshot.proxy.inventory.size() == 4
		and _is_fingerprint(String(snapshot.proxy.resolved_build.semantic_fingerprint)),
		"proxy transaction: early snapshot did not expose exactly the six implemented cores", failures)
	(snapshot.proxy.catalog.near_enemy_horizon as Dictionary)["name"] = "tampered"
	(snapshot.proxy.inventory[0] as Dictionary)["protocol"] = "tampered"
	(snapshot.proxy.build.cores as Array)[0] = "tampered"
	(snapshot.proxy.resolved_build.cores[0] as Dictionary)["core_id"] = "tampered"
	var isolated := state.early_game_snapshot()
	_expect(String(isolated.proxy.catalog.near_enemy_horizon.name) != "tampered"
		and String(isolated.proxy.inventory[0].protocol) != "tampered"
		and String(isolated.proxy.build.cores[0]) == "near_enemy_horizon"
		and String(isolated.proxy.resolved_build.cores[0].core_id) == "near_enemy_horizon",
		"proxy transaction: early snapshot aliases internal or derived state", failures)

	var before_unowned := state.profile
	_expect(_code(state.equip_proxy_core("marking_prism")) == "proxy_core_not_owned" and state.profile == before_unowned,
		"proxy transaction: unowned implemented core was not rejected atomically", failures)
	_expect(_code(state.equip_proxy_core("state_parser")) == "unsupported_proxy_core" and state.profile == before_unowned,
		"proxy transaction: catalog-only unimplemented core was accepted or mutated state", failures)

	var first_auto := _grant_session_result(state, "ordinary_auto_one", "Auto", "victory")
	var second_auto := _grant_session_result(state, "ordinary_auto_two", "Auto", "victory")
	_expect(int(state.profile.progression.auto_contract_wins) == 2
		and first_auto.result.proxy_component_drops.size() == 1
		and String(first_auto.result.proxy_component_drops[0].id) == "marking_prism"
		and second_auto.result.proxy_component_drops.size() == 1
		and String(second_auto.result.proxy_component_drops[0].id) == "distance_keeping_gait"
		and state.profile.proxy_build == initial_build
		and state.profile.inventory.proxy_components.size() == 6,
		"proxy rewards: first two successful Auto wins did not grant ordered inventory-only cores", failures)
	var manual := _grant_session_result(state, "manual_after_unlock", "Manual", "victory")
	var defeat := _grant_session_result(state, "auto_defeat_after_unlock", "Auto", "defeat")
	var third_auto := _grant_session_result(state, "ordinary_auto_three", "Auto", "victory")
	_expect(int(state.profile.progression.auto_contract_wins) == 3
		and manual.result.proxy_component_drops.is_empty()
		and defeat.result.proxy_component_drops.is_empty()
		and third_auto.result.proxy_component_drops.is_empty()
		and state.profile.inventory.proxy_components.size() == 6,
		"proxy rewards: Manual, defeat, or third Auto emitted a component drop", failures)

	var marking := state.equip_proxy_core("marking_prism")
	_expect(bool(marking.get("ok", false)) and String(state.profile.proxy_build.cores[0]) == "marking_prism"
		and String(marking.resolved_proxy_build.cores[0].core_id) == "marking_prism",
		"proxy transaction: marking core did not replace only its slot", failures)
	var distance := state.equip_proxy_core("distance_keeping_gait")
	var default_fingerprint := String(distance.resolved_proxy_build.semantic_fingerprint)
	_expect(bool(distance.get("ok", false)) and String(state.profile.proxy_build.cores[1]) == "distance_keeping_gait"
		and (state.profile.proxy_build.settings as Dictionary).is_empty()
		and String(distance.resolved_proxy_build.cores[1].settings.distance_band) == "mid",
		"proxy transaction: distance core did not compile with default mid", failures)
	var near := state.configure_proxy_core("distance_keeping_gait", {"distance_band": "near"})
	var far := state.configure_proxy_core("distance_keeping_gait", {"distance_band": "far"})
	_expect(bool(near.get("ok", false)) and bool(far.get("ok", false))
		and String(near.resolved_proxy_build.semantic_fingerprint) != String(far.resolved_proxy_build.semantic_fingerprint)
		and String(near.resolved_proxy_build.semantic_fingerprint) != default_fingerprint,
		"proxy transaction: near/far settings did not produce distinct resolved fingerprints", failures)
	var direct := state.equip_proxy_core("direct_gait")
	_expect(bool(direct.get("ok", false)) and not state.profile.proxy_build.settings.has("distance_keeping_gait"),
		"proxy transaction: replacing distance with direct retained stale settings", failures)
	var distance_again := state.equip_proxy_core("distance_keeping_gait")
	_expect(bool(distance_again.get("ok", false))
		and not state.profile.proxy_build.settings.has("distance_keeping_gait")
		and String(distance_again.resolved_proxy_build.cores[1].settings.distance_band) == "mid",
		"proxy transaction: re-equipping distance reused removed configuration", failures)

	var before_invalid := state.profile
	_expect(_code(state.configure_proxy_core("distance_keeping_gait", {"distance_band": "meters"})).begins_with("proxy_build_")
		and state.profile == before_invalid,
		"proxy transaction: illegal settings were not rejected atomically", failures)
	state.equip_proxy_core("near_enemy_horizon")
	var before_uninstalled := state.profile
	_expect(_code(state.configure_proxy_core("marking_prism", {})) == "proxy_core_not_equipped"
		and state.profile == before_uninstalled,
		"proxy transaction: uninstalled core configuration was not rejected atomically", failures)

	var returned := state.equip_proxy_core("marking_prism")
	(returned.proxy_build.cores as Array)[0] = "tampered"
	(returned.resolved_proxy_build.cores[0] as Dictionary)["core_id"] = "tampered"
	_expect(String(state.profile.proxy_build.cores[0]) == "marking_prism"
		and String(state.resolved_proxy_build_snapshot().resolved_proxy_build.cores[0].core_id) == "marking_prism",
		"proxy transaction: API return aliases authoritative state", failures)

	var payload := state.persistent_payload("base")
	var missing_settings := payload.duplicate(true)
	missing_settings.profile.proxy_build.erase("settings")
	var extra_build_field := payload.duplicate(true)
	extra_build_field.profile.proxy_build["firmware"] = {}
	var mismatched_metadata := payload.duplicate(true)
	mismatched_metadata.profile.inventory.proxy_components[0].protocol = "tampered"
	var duplicate_component := payload.duplicate(true)
	duplicate_component.profile.inventory.proxy_components.append((duplicate_component.profile.inventory.proxy_components[0] as Dictionary).duplicate(true))
	var unowned_selected := payload.duplicate(true)
	unowned_selected.profile.inventory.proxy_components = []
	var unsupported_attachment := payload.duplicate(true)
	unsupported_attachment.profile.proxy_build.attachments[0] = "future_attachment"
	for invalid_payload in [missing_settings, extra_build_field, mismatched_metadata, duplicate_component, unowned_selected, unsupported_attachment]:
		var restored := ApplicationState.new()
		_expect(_code(restored.restore_persistent_payload(invalid_payload)) == "invalid_profile" and not restored.has_profile(),
			"proxy validation: malformed build or inventory metadata was accepted", failures)


func _test_alias_isolation(failures: Array[String]) -> void:
	var state := ApplicationState.new()
	var created: Dictionary = state.start_new_profile("ranger")
	(created.profile.resources.law_tallies as Dictionary)["inscribe"] = 99
	var exposed: Dictionary = state.profile
	(exposed.resources.law_tallies as Dictionary)["inscribe"] = 88
	_expect(int(state.profile.resources.law_tallies.inscribe) == 0, "alias: profile output leaked internal state", failures)
	var config := {"contract_id": " c-1 ", "mode": "auto", "seed": 7, "room_count": 2, "meta": {"rank": 1}}
	var prepared: Dictionary = state.prepare_contract(config)
	(config.meta as Dictionary)["rank"] = 9
	(prepared.contract.meta as Dictionary)["rank"] = 8
	_expect(int((state.pending_contract.meta as Dictionary).rank) == 1, "alias: contract input/output leaked internal state", failures)


func _test_first_hunt_equipment_drop_gate(failures: Array[String]) -> void:
	var state := ApplicationState.new()
	state.start_new_profile()
	var initial_inventory: Array = state.profile.inventory.equipment
	var before_tutorial := _complete_drop_gate_node(state, "mainline_01_first_hunt", 300)
	_expect(int(before_tutorial.result.rewards.equipment_drop_count) == 0
		and before_tutorial.result.first_reward_tags == [],
		"drop gate: first hunt granted rewards before the real tutorial", failures)
	state.complete_tutorial()
	var premature := _complete_drop_gate_node(state, "mainline_03_first_elite", 300)
	_expect(int(premature.result.rewards.equipment_drop_count) == 0,
		"drop gate: locked mainline03 completion produced equipment", failures)
	var plan_result := ContractPlanScript.build({"contract_id": "mainline_01_first_hunt", "seed": 301,
		"mode": "Manual", "completed_node_ids": state.profile.progression.completed_node_ids})
	_expect(bool(plan_result.get("ok", false)), "drop gate: real first hunt plan failed", failures)
	if not bool(plan_result.get("ok", false)):
		return
	var plan: Dictionary = plan_result.plan
	var config := {"contract_id": "mainline_01_first_hunt", "mode": "Manual", "seed": 301,
		"room_count": plan.room_count, "room_plan": plan}
	for outcome in ["defeat", "abandoned"]:
		state.prepare_contract(config)
		state.begin_session()
		var failed := state.complete_session({"outcome": outcome, "rooms_completed": 1})
		_expect(failed.result.rewards.equipment_drop_count == 0 and failed.result.first_reward_tags == []
			and state.profile.inventory.equipment == initial_inventory
			and "equipment_compare_unlock" not in state.campaign_progress_snapshot().earned_reward_tags,
			"drop gate: partial %s granted victory loot or comparison" % outcome, failures)
	state.prepare_contract(config)
	state.begin_session()
	var first := state.complete_session({"outcome": "victory", "rooms_completed": 2})
	_expect(int(first.result.rewards.equipment_drop_count) == 2
		and first.result.first_reward_tags == ["hunter_mark_skill", "equipment_compare_unlock"]
		and "equipment_compare_unlock" in state.campaign_progress_snapshot().earned_reward_tags,
		"drop gate: first victory did not grant each cleared room's equipment and comparison", failures)
	var drops: Array = first.result.rewards.equipment_drops
	_expect(drops.size() == 2 and drops[0].instance_id != drops[1].instance_id,
		"drop gate: first hunt room drops lost their separate identities", failures)
	if not drops.is_empty():
		_expect(bool(state.preview_equip_item(String(drops[0].instance_id)).get("ok", false)),
			"drop gate: first reward equipment could not be compared", failures)
	var restored := ApplicationState.new()
	_expect(bool(restored.restore_persistent_payload(state.persistent_payload("base")).get("ok", false))
		and restored.profile == state.profile,
		"drop gate: first hunt loot or progression failed persistence validation", failures)
	state.prepare_contract(config)
	state.begin_session()
	var repeated := state.complete_session({"outcome": "victory", "rooms_completed": 2})
	_expect(repeated.result.rewards.equipment_drop_count == 0 and repeated.result.first_reward_tags == [],
		"drop gate: same-seed replay duplicated room items or first-clear rewards", failures)
	var second := _complete_drop_gate_node(state, "mainline_02_priority_under_pressure", 302)
	var elite := _complete_drop_gate_node(state, "mainline_03_first_elite", 303)
	_expect(int(second.result.rewards.equipment_drop_count) == 1,
		"drop gate: mainline02 equipment remained blocked", failures)
	_expect(int(elite.result.rewards.equipment_drop_count) == 2
		and elite.result.first_reward_tags == ["breeding_split_item"]
		and _has_equipment_instance(elite.result.rewards.equipment_drops, "reward_mainline_03_breeding_split_gloves"),
		"drop gate: first legal elite lost its room drop or stable semantic reward", failures)
	var later := _complete_drop_gate_node(state, "repeatable_drop_contract", 304)
	_expect(int(later.result.rewards.equipment_drop_count) == 1,
		"drop gate: qualified RoomPlan equipment drops remained blocked", failures)


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


func _test_forge_defaults_and_preview(failures: Array[String]) -> void:
	var state := ApplicationState.new()
	_expect(_code(state.forge_snapshot()) == "profile_required", "forge: profile should be required", failures)
	state.start_new_profile()
	var locked_before := state.profile
	var locked: Dictionary = state.forge_snapshot()
	_expect(bool(locked.get("ok", false)) and not bool(locked.unlocked) and locked.session.state == "idle",
		"forge: locked snapshot or idle session is wrong", failures)
	_expect(state.profile == locked_before and _code(state.forge_reveal()) == "forge_locked",
		"forge: locked reveal changed state or bypassed reward gate", failures)
	_unlock_forge(state)
	_grant_victory(state, {"law_tallies_delta": {"inscribe": 12}}, "preview")
	var before := state.profile
	var snapshot: Dictionary = state.forge_snapshot()
	var target_id := String(snapshot.target_instance_id)
	var initial_revision := int(snapshot.revision)
	_expect(bool(snapshot.get("ok", false)) and bool(snapshot.unlocked) and snapshot.inventory_items.size() == 5,
		"forge: real inventory target snapshot is incomplete", failures)
	_expect(snapshot.has("law_tallies") and snapshot.has("affix_families") and snapshot.has("session"), "forge: stable UI snapshot fields are missing", failures)
	_expect(snapshot.operation == "inscribe" and not snapshot.has("affix_index") and not (snapshot.context as Dictionary).has("affix_index")
		and not bool(snapshot.blocked) and int(snapshot.revision) > 0,
		"forge: default context retained stale selected-affix state", failures)
	var revealed: Dictionary = state.forge_reveal()
	_expect(bool(revealed.get("ok", false)) and revealed.session.candidates.size() == 8
		and int(revealed.session.revealed_count) == 8 and int(revealed.session.affordable_count) == 12
		and bool(revealed.session.has_more),
		"forge: first page contract is wrong", failures)
	var first_candidate: Dictionary = revealed.session.candidates[0]
	var comparison: Dictionary = first_candidate.get("build_comparison", {})
	_expect(first_candidate.get("result_item", {}) is Dictionary
		and first_candidate.has("affected_affix_index") and not first_candidate.has("affix_index")
		and bool(first_candidate.get("target_is_equipped", false))
		and String(first_candidate.get("preview_impact", "")) == "current_build_immediate"
		and comparison.get("current_parameters", {}) is Dictionary
		and comparison.get("result_parameters", {}) is Dictionary
		and comparison.get("interfaces_gained", []) is Array
		and comparison.get("interfaces_lost", []) is Array
		and comparison.current_parameters != comparison.result_parameters,
		"forge: equipped candidate did not carry its immediate-build preview semantics", failures)
	var raw_target: Dictionary = {}
	for owned_item in state.profile.inventory.equipment as Array:
		if owned_item is Dictionary and String((owned_item as Dictionary).get("instance_id", "")) == target_id:
			raw_target = (owned_item as Dictionary).duplicate(true)
			break
	var registry := EarlyItemRegistryScript.new()
	var raw_reveal := LawForgeScript.new(registry).reveal(raw_target, "inscribe", 0, 8, String(revealed.session.session_id)) if registry.load_all().is_empty() else {}
	var raw_candidate: Dictionary = (raw_reveal.get("candidates", []) as Array)[0] if not (raw_reveal.get("candidates", []) as Array).is_empty() else {}
	var result_view: Dictionary = first_candidate.get("result_item_view", {}) as Dictionary
	_expect(not raw_target.is_empty() and first_candidate.result_item == raw_candidate.get("result_item", {})
		and not (first_candidate.result_item as Dictionary).has("base_name")
		and result_view.get("base_name", "") == "白蜡长弓"
		and not (result_view.get("affixes", []) as Array).is_empty()
		and String(((result_view.get("affixes", []) as Array)[0] as Dictionary).get("family_name", "")) == String(first_candidate.get("family_name", "")),
		"forge: raw result_item changed or its separate presentation view lost readable names", failures)
	_expect(bool(LawForgeScript.new(registry).validate_candidate(raw_target, "inscribe", first_candidate, String(revealed.session.session_id)).get("ok", false)),
		"forge: presentation view made the exact raw candidate fail validation", failures)
	var reveal_session_id := String(revealed.session.session_id)
	var more: Dictionary = state.forge_reveal_more(reveal_session_id)
	_expect(bool(more.get("ok", false)) and more.session.candidates.size() == 12
		and int(more.session.candidates[8].sequence_number) == 9 and not bool(more.session.has_more),
		"forge: reveal_more did not stop at the affordable horizon", failures)
	_expect(state.forge_reveal_more(reveal_session_id).session.candidates.size() == 12,
		"forge: reveal_more leaked results beyond the owned Law Tallies", failures)
	_expect(_code(state.forge_reveal_more("stale-session")) == "stale_forge_session",
		"forge: reveal_more accepted a stale session id", failures)
	(more.session.candidates[0] as Dictionary).result_item.affixes.clear()
	_expect(state.profile == before, "forge: reveal or returned session changed profile", failures)
	_expect(_code(state.forge_select_operation("unknown")) == "unknown_operation", "forge: unknown operation error changed", failures)
	var before_context_change_tallies: Dictionary = state.profile.resources.law_tallies.duplicate(true)
	var rewrite_context: Dictionary = state.forge_select_operation("rewrite")
	_expect(bool(rewrite_context.get("ok", false)) and rewrite_context.context.operation == "rewrite"
		and not (rewrite_context.context as Dictionary).has("affix_index") and state.forge_snapshot().session.state == "idle"
		and state.profile.resources.law_tallies == before_context_change_tallies,
		"forge: operation change did not remove slot state and cancel the old session without spending", failures)
	_expect(_code(state.forge_reveal(8, initial_revision)) == "stale_forge_context"
		and state.profile.resources.law_tallies == before_context_change_tallies,
		"forge: stale presentation revision started a new session or spent tallies", failures)


func _test_forge_commit_and_atomic_failure(failures: Array[String]) -> void:
	var state := ApplicationState.new()
	state.start_new_profile()
	_unlock_forge(state)
	_grant_victory(state, {"law_tallies_delta": {"inscribe": 5}}, "commit")
	var snapshot: Dictionary = state.forge_snapshot()
	var target_id := String(snapshot.target_instance_id)
	var before_fingerprint := String(state.resolved_build_snapshot().build_fingerprint)
	var reveal: Dictionary = state.forge_reveal()
	var candidate: Dictionary = reveal.session.candidates[1]
	var committed_result_item: Dictionary = (candidate.result_item as Dictionary).duplicate(true)
	var session_id := String(reveal.session.session_id)
	state.forge_select_candidate(session_id, String(candidate.candidate_id))
	var before_prepare := state.profile
	var prepared: Dictionary = state.forge_prepare_commit(session_id)
	_expect(bool(prepared.get("ok", false)) and int(prepared.cost) == 2 and (prepared.candidate as Dictionary).result_item == committed_result_item and state.profile == before_prepare,
		"forge commit: prepare mutated current profile", failures)
	state.forge_abort_commit(String(prepared.commit_token))
	_expect(state.profile == before_prepare and state.forge_snapshot().session.state == "selected",
		"forge commit: abort did not preserve retryable selection", failures)
	prepared = state.forge_prepare_commit(session_id)
	var committed: Dictionary = state.forge_finalize_commit(String(prepared.commit_token))
	_expect(bool(committed.get("ok", false)) and committed.operation == "inscribe" and int(committed.cost) == 2,
		"forge commit: finalize failed", failures)
	_expect(int(state.profile.resources.law_tallies.inscribe) == 3
		and String(state.resolved_build_snapshot().build_fingerprint) != before_fingerprint,
		"forge commit: result item or tally cost was not published", failures)
	var committed_item: Dictionary = {}
	for owned_item in state.profile.inventory.equipment as Array:
		if owned_item is Dictionary and String((owned_item as Dictionary).get("instance_id", "")) == target_id:
			committed_item = owned_item as Dictionary
			break
	_expect(committed_item == committed_result_item and not committed_item.has("base_name"),
		"forge commit: persisted equipment stopped using the exact raw result_item", failures)
	_expect(state.forge_snapshot().session.state == "idle", "forge commit: finalized session was not cleared", failures)
	var changed_profile := state.profile
	(changed_profile.resources.law_tallies as Dictionary)["rewrite"] = 5
	state.set("_profile", changed_profile)
	state.forge_select_operation("rewrite")
	var second_reveal: Dictionary = state.forge_reveal()
	for raw_rewrite_candidate in (second_reveal.get("session", {}) as Dictionary).get("candidates", []):
		var rewrite_candidate: Dictionary = raw_rewrite_candidate
		var affected_index := int(rewrite_candidate.get("affected_affix_index", -1))
		_expect(String(rewrite_candidate.get("operation", "")) == "rewrite"
			and affected_index >= 0 and not rewrite_candidate.has("affix_index")
			and (rewrite_candidate.get("result_item", {}) as Dictionary).get("affixes", []).size() == committed_item.affixes.size(),
			"forge commit: rewrite candidate was not a complete authority result with affected_affix_index", failures)
	session_id = String(second_reveal.session.session_id)
	state.forge_select_candidate(session_id, String(second_reveal.session.candidates[3].candidate_id))
	changed_profile = state.profile
	(changed_profile.resources.law_tallies as Dictionary)["rewrite"] = 3
	state.set("_profile", changed_profile)
	var before_failure := state.profile
	_expect(_code(state.forge_prepare_commit(session_id)) == "insufficient_law_tallies" and state.profile == before_failure,
		"forge commit: insufficient tally failure was not atomic", failures)


func _test_forge_inventory_target_preview_and_commit(failures: Array[String]) -> void:
	var state := ApplicationState.new()
	state.start_new_profile()
	state.select_ranger_build("exponential")
	state.select_ranger_build("critical")
	_unlock_forge(state)
	_grant_victory(state, {"law_tallies_delta": {"inscribe": 3}}, "inventory-target")
	var target_id := "calibration_exponential_main_hand"
	_expect(bool(state.forge_select_target(target_id).get("ok", false))
		and bool(state.forge_select_operation("inscribe").get("ok", false)),
		"forge inventory target: could not select the owned but unequipped target", failures)
	var before_fingerprint := String(state.resolved_build_snapshot().build_fingerprint)
	var before_equipped: Dictionary = (state.profile.active_build.equipped_item_ids as Dictionary).duplicate(true)
	var revealed: Dictionary = state.forge_reveal()
	var candidate: Dictionary = (revealed.session.candidates as Array)[0] if not (revealed.session.candidates as Array).is_empty() else {}
	var comparison: Dictionary = candidate.get("build_comparison", {})
	_expect(bool(revealed.get("ok", false)) and not bool(candidate.get("target_is_equipped", true))
		and String(candidate.get("preview_impact", "")) == "equip_after_commit"
		and comparison.get("current_parameters", {}) == state.resolved_build_snapshot().final_parameters
		and comparison.get("result_parameters", {}) is Dictionary
		and comparison.has("interfaces_gained") and comparison.has("interfaces_lost"),
		"forge inventory target: candidate did not declare the post-equip preview contract", failures)
	if candidate.is_empty():
		return
	var session_id := String(revealed.session.session_id)
	var result_item: Dictionary = (candidate.result_item as Dictionary).duplicate(true)
	state.forge_select_candidate(session_id, String(candidate.candidate_id))
	var prepared := state.forge_prepare_commit(session_id)
	var committed := state.forge_finalize_commit(String(prepared.get("commit_token", ""))) if bool(prepared.get("ok", false)) else {}
	var committed_item: Dictionary = {}
	for owned_item in state.profile.inventory.equipment as Array:
		if String((owned_item as Dictionary).get("instance_id", "")) == target_id:
			committed_item = owned_item as Dictionary
			break
	_expect(bool(committed.get("ok", false)) and committed_item == result_item
		and String(state.resolved_build_snapshot().build_fingerprint) == before_fingerprint
		and state.profile.active_build.equipped_item_ids == before_equipped,
		"forge inventory target: commit changed the build or failed to replace only the selected inventory instance", failures)


func _test_forge_context_normalization(failures: Array[String]) -> void:
	var state := ApplicationState.new()
	state.start_new_profile()
	_unlock_forge(state)
	var initial: Dictionary = state.forge_snapshot()
	var initial_target := String(initial.target_instance_id)
	var empty_target := ""
	var empty_slot := ""
	for item in (initial.inventory_items as Array):
		if String((item as Dictionary).get("instance_id", "")) != initial_target and (item as Dictionary).get("affixes", []).is_empty():
			empty_target = String((item as Dictionary).instance_id)
			empty_slot = String((item as Dictionary).slot)
			break
	state.forge_select_operation("rewrite")
	var target_changed: Dictionary = state.forge_select_target(empty_target)
	_expect(not empty_target.is_empty() and bool(target_changed.get("ok", false))
		and target_changed.context.operation == "rewrite" and not (target_changed.context as Dictionary).has("affix_index")
		and bool(target_changed.context.blocked) and target_changed.context.blocked_reason == "affix_required",
		"forge context: target change did not normalize an empty item into an explicit rewrite block", failures)
	var append_context: Dictionary = state.forge_select_operation("inscribe")
	_expect(not (append_context.context as Dictionary).has("affix_index") and not bool(append_context.context.blocked),
		"forge context: empty target retained selected-affix state for inscribe", failures)
	_grant_victory(state, {"law_tallies_delta": {"inscribe": 3}}, "context-target")
	var target_session: Dictionary = state.forge_reveal()
	var tallies_before_target: Dictionary = state.profile.resources.law_tallies.duplicate(true)
	state.forge_select_target(initial_target)
	_expect(bool(target_session.get("ok", false)) and state.forge_snapshot().session.state == "idle"
		and state.profile.resources.law_tallies == tallies_before_target,
		"forge context: target change did not cancel the session without spending", failures)
	state.forge_select_target(empty_target)

	var profile := state.profile
	var registry := EarlyItemRegistryScript.new()
	registry.load_all()
	var full_affixes: Array = []
	for family_id in registry.affix_families:
		var family: Dictionary = registry.affix_families[family_id]
		if empty_slot in (family.compatible_slots as Array):
			full_affixes.append({"family_id": String(family_id), "tier": 1})
			if full_affixes.size() == LawForgeScript.MAX_AFFIXES:
				break
	for index in (profile.inventory.equipment as Array).size():
		if String((profile.inventory.equipment[index] as Dictionary).instance_id) == empty_target:
			(profile.inventory.equipment[index] as Dictionary)["affixes"] = full_affixes.duplicate(true)
			break
	state.set("_profile", profile)
	var full: Dictionary = state.forge_snapshot()
	_expect(full_affixes.size() == LawForgeScript.MAX_AFFIXES and not full.has("affix_index")
		and bool(full.blocked) and full.blocked_reason == "affix_limit_reached",
		"forge context: full item did not expose an explicit blocked append context", failures)
	profile = state.profile
	for index in (profile.inventory.equipment as Array).size():
		if String((profile.inventory.equipment[index] as Dictionary).instance_id) == empty_target:
			for affix in ((profile.inventory.equipment[index] as Dictionary).affixes as Array):
				(affix as Dictionary)["tier"] = LawForgeScript.MAX_TIER
			break
	state.set("_profile", profile)
	state.forge_select_operation("inscribe")
	var refine: Dictionary = state.forge_select_operation("refine")
	_expect(not (refine.context as Dictionary).has("affix_index") and bool(refine.context.blocked)
		and refine.context.blocked_reason == "max_tier",
		"forge context: refine did not block an item whose affixes are all T4", failures)


func _test_forge_unique_result_horizon(failures: Array[String]) -> void:
	var state := ApplicationState.new()
	state.start_new_profile("ranger")
	_unlock_forge(state)
	var profile := state.profile
	(profile.resources.law_tallies as Dictionary)["refine"] = 8
	(profile.inventory as Dictionary).equipment.append({
		"instance_id": "calibration_exponential_main_hand",
		"base_item_id": "ashwood_longbow",
		"slot": "main_hand",
		"affixes": [{"family_id": "piercing_continuation", "tier": 3}],
		"rune_id": "",
		"law_id": "",
		"source": {"type": "calibration", "id": "calibration_exponential"},
		"law_seed": 2301,
	})
	state.set("_profile", profile)
	state.forge_select_target("calibration_exponential_main_hand")
	state.forge_select_operation("refine")
	var reveal: Dictionary = state.forge_reveal()
	_expect(bool(reveal.get("ok", false)) and reveal.session.candidates.size() == 1
		and int(reveal.session.affordable_count) == 1 and not bool(reveal.session.has_more),
		"forge uniqueness: T3 refine must stop at its one unique affordable result", failures)
	var candidate: Dictionary = reveal.session.candidates[0]
	var session_id := String(reveal.session.session_id)
	_expect(candidate.has("affected_affix_index") and int(candidate.affected_affix_index) == 0
		and not candidate.has("affix_index") and (candidate.result_item.affixes as Array).size() == 1
		and int((candidate.result_item.affixes[0] as Dictionary).tier) == LawForgeScript.MAX_TIER,
		"forge uniqueness: refine candidate was not a complete authority result with affected_affix_index", failures)
	_expect(bool(state.forge_reveal_more(session_id).get("ok", false)) and state.forge_snapshot().session.candidates.size() == 1,
		"forge uniqueness: reveal_more exceeded unique-result exhaustion", failures)
	_expect(bool(state.forge_select_candidate(session_id, String(candidate.candidate_id)).get("ok", false)),
		"forge uniqueness: exact unique candidate could not be selected", failures)
	var prepared: Dictionary = state.forge_prepare_commit(session_id)
	_expect(bool(prepared.get("ok", false)) and int(prepared.cost) == 1
		and String((prepared.candidate as Dictionary).result_item.instance_id) == "calibration_exponential_main_hand",
		"forge uniqueness: exact commit no longer preserves item identity", failures)


func _test_contract_validation(failures: Array[String]) -> void:
	var state := ApplicationState.new()
	_expect(_code(state.prepare_contract({})) == "profile_required", "contract: profile should be required", failures)
	state.start_new_profile()
	_expect(_code(state.prepare_contract({"contract_id": "", "mode": "Manual", "seed": 1, "room_count": 1})) == "invalid_contract_id", "contract: id should be non-empty", failures)
	_expect(_code(state.prepare_contract({"contract_id": "x", "mode": "Both", "seed": 1, "room_count": 1})) == "invalid_mode", "contract: mode should be constrained", failures)
	_expect(_code(state.prepare_contract({"contract_id": "x", "mode": "Manual", "seed": 1.5, "room_count": 1})) == "invalid_seed", "contract: seed should be an integer", failures)
	_expect(_code(state.prepare_contract({"contract_id": "x", "mode": "Manual", "seed": 9007199254740992, "room_count": 1})) == "invalid_seed", "contract: seed above JSON's exact range was accepted", failures)
	_expect(_code(state.prepare_contract({"contract_id": "x", "mode": "Manual", "seed": -9007199254740992, "room_count": 1})) == "invalid_seed", "contract: seed below JSON's exact range was accepted", failures)
	_expect(_code(state.prepare_contract({"contract_id": "x", "mode": "Manual", "seed": 1, "room_count": 0})) == "invalid_room_count", "contract: room count should be positive", failures)
	var ok: Dictionary = state.prepare_contract({"contract_id": " x ", "mode": "manual", "seed": -7, "room_count": 3})
	_expect(bool(ok.get("ok", false)) and ok.contract.contract_id == "x" and ok.contract.mode == "Manual", "contract: valid config should be normalized", failures)


func _test_session_lifecycle(failures: Array[String]) -> void:
	var state := ApplicationState.new()
	state.start_new_profile("alchemist")
	_expect(_code(state.begin_session()) == "pending_contract_required", "session: pending contract should be required", failures)
	state.prepare_contract({"contract_id": "alpha", "mode": "Auto", "seed": 42, "room_count": 4})
	var begun: Dictionary = state.begin_session()
	_expect(bool(begun.get("ok", false)), "session: begin should succeed", failures)
	_expect(state.pending_contract.is_empty(), "session: begin should consume pending contract", failures)
	_expect(int(state.active_session.room_index) == 0 and int(state.active_session.ticks) == 0, "session: counters should start at zero", failures)
	_expect(_code(state.prepare_contract({"contract_id": "beta", "mode": "Manual", "seed": 1, "room_count": 1})) == "active_session_exists", "session: active session should block prepare", failures)
	_expect(_code(state.begin_session()) == "active_session_exists", "session: a second begin should fail", failures)
	var result := {"outcome": "victory", "rewards": {"marker": 2}}
	var completed: Dictionary = state.complete_session(result)
	(result.rewards as Dictionary)["marker"] = 99
	(completed.result.rewards as Dictionary)["marker"] = 88
	_expect(state.active_session.is_empty() and state.pending_contract.is_empty(), "session: complete should clear transient state", failures)
	_expect(int((state.last_result.rewards as Dictionary).marker) == 2, "session: result should be deeply isolated", failures)
	_expect(_code(state.complete_session({})) == "active_session_required", "session: completing without active session should fail", failures)


func _test_abandon(failures: Array[String]) -> void:
	var state := ApplicationState.new()
	state.start_new_profile()
	state.prepare_contract({"contract_id": "pending", "mode": "Manual", "seed": 1, "room_count": 1})
	state.abandon_session()
	_expect(state.pending_contract.is_empty(), "abandon: pending contract should clear", failures)
	state.prepare_contract({"contract_id": "active", "mode": "Auto", "seed": 2, "room_count": 1})
	state.begin_session()
	state.abandon_session()
	_expect(state.pending_contract.is_empty() and state.active_session.is_empty(), "abandon: active state should clear", failures)


func _test_reward_settlement(failures: Array[String]) -> void:
	var state := ApplicationState.new()
	state.start_new_profile()
	state.prepare_contract({"contract_id": "rewarded", "mode": "Auto", "seed": 8, "room_count": 1})
	state.begin_session()
	var reward := {
		"outcome": "victory",
		"rewards": {
			"contract_wins_delta": 2,
			"law_tallies_delta": {"inscribe": 3, "rewrite": 2, "refine": 1},
			"drop_id": "core.alpha",
			"drop_label": "Alpha Core",
		},
	}
	state.complete_session(reward)
	var profile: Dictionary = state.profile
	_expect(int(profile.progression.contract_wins) == 2, "reward: victory wins were not applied", failures)
	_expect(profile.resources.law_tallies == {"inscribe": 3, "rewrite": 2, "refine": 1}, "reward: Law Tallies were not applied", failures)
	_expect(profile.inventory.proxy_components.is_empty()
		and profile.inventory.legacy_drops == [{"id": "core.alpha", "label": "Alpha Core", "source_contract": "rewarded"}],
		"reward: ordinary victory unlocked proxy or failed to record legacy drop", failures)
	reward.rewards.law_tallies_delta.inscribe = 99
	_expect(int(state.profile.resources.law_tallies.inscribe) == 3, "reward: applied profile aliases result input", failures)
	state.prepare_contract({"contract_id": "defeat", "mode": "Manual", "seed": 9, "room_count": 1})
	state.begin_session()
	state.complete_session({"outcome": "defeat", "rewards": {"contract_wins_delta": 9, "law_tallies_delta": {"inscribe": 9}}})
	_expect(state.profile == profile, "reward: non-victory result changed progression", failures)
	state.prepare_contract({"contract_id": "final", "mode": "Auto", "seed": 10, "room_count": 1})
	state.begin_session()
	state.complete_session({"outcome": "final_victory", "rewards": {"contract_wins_delta": 1}})
	_expect(bool(state.profile.progression.ending_unlocked), "reward: final victory did not unlock ending", failures)
	_grant_victory(state, {
		"law_tallies_delta": {"inscribe": 4, "rewrite": 5, "refine": 6},
	}, "three-track")
	profile = state.profile
	_expect(profile.resources.law_tallies == {"inscribe": 7, "rewrite": 7, "refine": 7}, "reward: three Law Tally tracks are wrong", failures)
	_grant_victory(state, {"law_tallies_delta": {"inscribe": -1, "rewrite": 1.0, "refine": "3"}}, "invalid-track-reward")
	_expect(state.profile.resources.law_tallies == profile.resources.law_tallies, "reward: invalid Law Tally deltas were applied", failures)


func _test_room_equipment_drop_settlement(failures: Array[String]) -> void:
	var plan := {"rooms": [
		{"room_id": "drop-room-a", "drop_tags": ["main_hand"]},
		{"room_id": "drop-room-b", "drop_tags": ["equipment_general"], "guarantee_family": "maximum_health"},
		{"room_id": "drop-room-c", "drop_tags": ["damage"]},
		{"room_id": "drop-room-non-equipment", "drop_tags": ["inscribe_tally"]},
	]}
	var state := ApplicationState.new()
	state.start_new_profile()
	_unlock_equipment_drops(state)
	var initial_equipment: Array = state.profile.inventory.equipment
	var initial_active_build: Dictionary = state.profile.active_build
	_begin_drop_session(state, 41001, plan)
	var completed: Dictionary = state.complete_session({"outcome": "victory", "rooms_completed": 99})
	var drops: Array = completed.result.rewards.equipment_drops
	var deterministic_drops: Array = drops.duplicate(true)
	_expect(drops.size() == 3 and int(completed.result.rewards.equipment_drop_count) == 3,
		"room drops: multi-room victory or upper-bound normalization produced the wrong count", failures)
	_expect(state.profile.inventory.equipment.size() == initial_equipment.size() + 3
		and state.profile.inventory.legacy_drops.is_empty(),
		"room drops: equipment was not partitioned into equipment-only inventory", failures)
	_expect(state.profile.active_build == initial_active_build,
		"room drops: settlement changed the equipped build", failures)
	if drops.size() >= 2:
		_expect(String(drops[0].slot) == "main_hand", "room drops: slot tag was not respected", failures)
		_expect(String(drops[1].affixes[0].family_id) == "maximum_health", "room drops: guarantee_family was not forwarded", failures)
	var registry := EarlyItemRegistryScript.new()
	var registry_failures: Array[String] = registry.load_all()
	_expect(registry_failures.is_empty(), "room drops: item registry failed to load", failures)
	var resolver := BuildResolverScript.new(registry)
	for item in drops:
		var validation: Array[String] = registry.validate_item_instance(item)
		_expect(validation.is_empty(), "room drops: settled item failed registry validation", failures)
		var resolved: Dictionary = resolver.resolve(_drop_test_base_parameters(), {String(item.slot): item}, "piercing_arrow")
		_expect(bool(resolved.get("ok", false)), "room drops: settled item was rejected by BuildResolver", failures)
	var replay_state := ApplicationState.new()
	replay_state.start_new_profile()
	_unlock_equipment_drops(replay_state)
	_begin_drop_session(replay_state, 41001, plan)
	var replayed: Dictionary = replay_state.complete_session({"outcome": "victory", "rooms_completed": 99})
	_expect(replayed.result.rewards.equipment_drops == deterministic_drops,
		"room drops: identical contract replay did not reproduce every ItemInstance field", failures)

	# Returned/result/profile snapshots must not share nested dictionaries.
	if not drops.is_empty():
		var stable_instance_id := String(state.last_result.rewards.equipment_drops[0].instance_id)
		completed.result.rewards.equipment_drops[0].instance_id = "mutated-return"
		var exposed_result: Dictionary = state.last_result
		exposed_result.rewards.equipment_drops[0].instance_id = "mutated-getter"
		var exposed_profile: Dictionary = state.profile
		var last_profile_index := (exposed_profile.inventory.equipment as Array).size() - 1
		var last_profile_instance_id := String(exposed_profile.inventory.equipment[last_profile_index].instance_id)
		exposed_profile.inventory.equipment[-1].instance_id = "mutated-profile"
		_expect(String(state.last_result.rewards.equipment_drops[0].instance_id) == stable_instance_id
			and _has_equipment_instance(state.profile.inventory.equipment, stable_instance_id)
			and String(state.profile.inventory.equipment[last_profile_index].instance_id) == last_profile_instance_id,
			"room drops: result/profile equipment snapshots alias external data", failures)

	# Replaying the same plan and seed must reproduce ids but report only actual additions.
	_begin_drop_session(state, 41001, plan)
	var repeated: Dictionary = state.complete_session({"outcome": "final_victory"})
	_expect(int(repeated.result.rewards.equipment_drop_count) == 0
		and repeated.result.rewards.equipment_drops.is_empty()
		and state.profile.inventory.equipment.size() == initial_equipment.size() + 3,
		"room drops: same-seed replay duplicated or falsely reported owned equipment", failures)

	_begin_drop_session(state, 41002, plan)
	var diverted: Dictionary = state.complete_session({"outcome": "victory", "rooms_completed": 1})
	_expect(int(diverted.result.rewards.equipment_drop_count) == 1
		and not _has_equipment_instance(deterministic_drops, String(diverted.result.rewards.equipment_drops[0].instance_id)),
		"room drops: different seed did not split the deterministic stream", failures)

	var defeated := ApplicationState.new()
	defeated.start_new_profile()
	_begin_drop_session(defeated, 51001, plan)
	var defeat_profile: Dictionary = defeated.profile
	var defeat: Dictionary = defeated.complete_session({"outcome": "defeat", "rooms_completed": 4})
	_expect(defeated.profile == defeat_profile
		and defeat.result.rewards.equipment_drops.is_empty()
		and int(defeat.result.rewards.equipment_drop_count) == 0,
		"room drops: defeat generated equipment or changed profile", failures)

	var bounded := ApplicationState.new()
	bounded.start_new_profile()
	_unlock_equipment_drops(bounded)
	_begin_drop_session(bounded, 61001, plan)
	var negative: Dictionary = bounded.complete_session({"outcome": "victory", "rooms_completed": -8})
	_expect(int(negative.result.rewards.equipment_drop_count) == 0,
		"room drops: negative rooms_completed was not clamped to zero", failures)
	_begin_drop_session(bounded, 61002, plan)
	var malformed: Dictionary = bounded.complete_session({"outcome": "victory", "rooms_completed": "4"})
	_expect(int(malformed.result.rewards.equipment_drop_count) == 0,
		"room drops: malformed rooms_completed did not fail closed", failures)


func _test_boss_defeat_bottleneck(failures: Array[String]) -> void:
	_expect(float(ApplicationState.BOSS_DIAGNOSIS_RANGE_MIN) == 120.0
		and float(ApplicationState.BOSS_DIAGNOSIS_LIFETIME_MIN) == 24.0,
		"boss bottleneck: named internal thresholds drifted", failures)

	# Real presets cover both growth branches and the qualified exponential fallback.
	var state := ApplicationState.new()
	state.start_new_profile()
	for preset_id in ["convergent", "critical", "exponential"]:
		state.select_ranger_build(preset_id)
		_begin_boss_defeat(state, state.resolved_build_snapshot())
		var completed: Dictionary = state.complete_session({"outcome": "defeat", "report": "DEFEAT — the ranger fell."})
		var expected_id: String = {
			"convergent": "growth_convergent",
			"critical": "growth_critical",
			"exponential": "boss_pattern_survival",
		}[preset_id]
		_expect_boss_bottleneck(completed, expected_id, failures)

	# Fabricated resolved builds cover short range, short lifetime, and fixed priority.
	_expect_boss_bottleneck(_boss_defeat_with_build("exponential", 80.0, 34.0), "targeting_range_short", failures)
	_expect_boss_bottleneck(_boss_defeat_with_build("exponential", 150.0, 8.0), "projectile_lifetime_short", failures)
	_expect_boss_bottleneck(_boss_defeat_with_build("exponential", 150.0, 34.0), "boss_pattern_survival", failures)
	_expect_boss_bottleneck(_boss_defeat_with_build("exponential", 80.0, 8.0), "targeting_range_short", failures)
	_expect_boss_bottleneck(_boss_defeat_with_build("convergent", 80.0, 8.0), "growth_convergent", failures)
	_expect_boss_bottleneck(_boss_defeat_with_build("critical", 80.0, 8.0), "growth_critical", failures)

	# No false positives: victory, ordinary contract, error outcome, Auto mode.
	var victory_state := ApplicationState.new()
	victory_state.start_new_profile()
	victory_state.select_ranger_build("exponential")
	_begin_boss_defeat(victory_state, victory_state.resolved_build_snapshot())
	_expect(not victory_state.complete_session({"outcome": "victory"}).result.has("primary_bottleneck"),
		"boss bottleneck: boss victory was misreported", failures)

	var ordinary_state := ApplicationState.new()
	ordinary_state.start_new_profile()
	ordinary_state.select_ranger_build("exponential")
	_begin_boss_defeat(ordinary_state, ordinary_state.resolved_build_snapshot(), "Manual", "mainline_05_growth_gate")
	_expect(not ordinary_state.complete_session({"outcome": "defeat"}).result.has("primary_bottleneck"),
		"boss bottleneck: ordinary contract defeat was misreported", failures)

	var error_state := ApplicationState.new()
	error_state.start_new_profile()
	error_state.select_ranger_build("exponential")
	_begin_boss_defeat(error_state, error_state.resolved_build_snapshot())
	_expect(not error_state.complete_session({"outcome": "error", "error": "room_runtime_failed"}).result.has("primary_bottleneck"),
		"boss bottleneck: error outcome was misreported", failures)

	var auto_state := ApplicationState.new()
	auto_state.start_new_profile()
	auto_state.select_ranger_build("exponential")
	_begin_boss_defeat(auto_state, auto_state.resolved_build_snapshot(), "Auto")
	_expect(not auto_state.complete_session({"outcome": "defeat"}).result.has("primary_bottleneck"),
		"boss bottleneck: Auto mode defeat was misreported", failures)

	# A qualifying defeat without a resolved build still yields exactly one fallback.
	_expect_boss_bottleneck(_boss_defeat_without_build(), "boss_pattern_survival", failures)

	# The caller's result must stay untouched and returned data must not alias internals.
	var copy_state := ApplicationState.new()
	copy_state.start_new_profile()
	_begin_boss_defeat(copy_state, _boss_resolved_build("exponential", 300.0, 30.0))
	var raw_result := {"outcome": "defeat", "report": "DEFEAT — raw.", "rewards": {"kept": true}}
	var raw_before := raw_result.duplicate(true)
	var copied: Dictionary = copy_state.complete_session(raw_result)
	_expect(raw_result == raw_before and not raw_result.has("primary_bottleneck"),
		"boss bottleneck: settlement mutated the caller result", failures)
	(copied.result.primary_bottleneck as Dictionary)["title"] = "mutated"
	_expect(String(copy_state.last_result.primary_bottleneck.id) == "boss_pattern_survival"
		and String(copy_state.last_result.primary_bottleneck.title) != "mutated",
		"boss bottleneck: returned result aliases internal state", failures)


func _begin_boss_defeat(state: ApplicationState, build: Dictionary, mode: String = "Manual", contract_id: String = "threshold_colossus") -> void:
	var config := {
		"contract_id": contract_id,
		"mode": mode,
		"seed": 1,
		"room_count": 1,
	}
	if not build.is_empty():
		config["resolved_build"] = build.duplicate(true)
	state.prepare_contract(config)
	state.begin_session()


func _boss_resolved_build(classification: String, distance: float, lifetime: float) -> Dictionary:
	return {
		"ok": true,
		"growth_classification": classification,
		"final_parameters": {
			"p": 0.61,
			"T": lifetime,
			"v": 620.0,
			"d": distance,
			"turn": 0.18,
			"damage": 100.0,
			"max_health": 100.0,
		},
	}


func _boss_defeat_with_build(classification: String, distance: float, lifetime: float) -> Dictionary:
	var state := ApplicationState.new()
	state.start_new_profile()
	_begin_boss_defeat(state, _boss_resolved_build(classification, distance, lifetime))
	return state.complete_session({"outcome": "defeat", "report": "DEFEAT — the ranger fell."})


func _boss_defeat_without_build() -> Dictionary:
	var state := ApplicationState.new()
	state.start_new_profile()
	_begin_boss_defeat(state, {})
	return state.complete_session({"outcome": "defeat"})


func _expect_boss_bottleneck(completed: Dictionary, expected_id: String, failures: Array[String]) -> void:
	var result_value: Variant = completed.get("result", {})
	var result: Dictionary = result_value if result_value is Dictionary else {}
	var bottleneck_value: Variant = result.get("primary_bottleneck", null)
	if not (bottleneck_value is Dictionary):
		failures.append("boss bottleneck: %s did not produce exactly one primary_bottleneck" % expected_id)
		return
	var bottleneck: Dictionary = bottleneck_value
	_expect(bottleneck.keys().size() == 4
		and bottleneck.has("id") and bottleneck.has("title") and bottleneck.has("action") and bottleneck.has("destination"),
		"boss bottleneck: %s must carry exactly id/title/action/destination" % expected_id, failures)
	_expect(String(bottleneck.get("id", "")) == expected_id,
		"boss bottleneck: expected %s, got %s" % [expected_id, String(bottleneck.get("id", ""))], failures)
	_expect(not String(bottleneck.get("title", "")).is_empty() and not String(bottleneck.get("action", "")).is_empty(),
		"boss bottleneck: %s has empty title or action" % expected_id, failures)
	_expect(not String(bottleneck.get("title", "")).contains("=")
		and not String(bottleneck.get("action", "")).contains("="),
		"boss bottleneck: %s leaks formula or numeric advice" % expected_id, failures)


func _begin_drop_session(state: ApplicationState, seed: int, plan: Dictionary) -> void:
	state.prepare_contract({
		"contract_id": "drop-settlement",
		"mode": "Manual",
		"seed": seed,
		"room_count": (plan.rooms as Array).size(),
		"room_plan": plan.duplicate(true),
	})
	state.begin_session()


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


func _drop_test_base_parameters() -> Dictionary:
	return {
		"p": 0.25,
		"T": 2.0,
		"v": 200.0,
		"d": 100.0,
		"turn": 0.1,
		"damage": 100.0,
		"critical_chance": 0.05,
		"max_health": 100.0,
	}


func _test_persistent_payload(failures: Array[String]) -> void:
	var state := ApplicationState.new()
	_expect(state.persistent_payload("base").safe_route == "title", "payload: no profile should force title", failures)
	state.start_new_profile()
	state.prepare_contract({"contract_id": "save-test", "mode": "Manual", "seed": 3, "room_count": 2})
	state.begin_session()
	var payload: Dictionary = state.persistent_payload("base")
	_expect(payload.keys().size() == 4 and payload.has("schema_version") and payload.has("profile") and payload.has("last_result") and payload.has("safe_route"), "payload: only persistent fields should be exported", failures)
	_expect(not payload.has("pending_contract") and not payload.has("active_session"), "payload: transient state leaked", failures)
	_expect(payload.profile.active_build.keys() == ["skills", "equipped_item_ids"],
		"payload: active_build must persist exactly skills and equipped_item_ids", failures)
	(payload.profile.resources.law_tallies as Dictionary)["inscribe"] = 100
	_expect(int(state.profile.resources.law_tallies.inscribe) == 0, "payload: exported profile leaked internal state", failures)
	_expect(state.persistent_payload("battle").safe_route == "base", "payload: invalid route should fall back to base", failures)


func _test_old_schema_rejected(failures: Array[String]) -> void:
	var source := ApplicationState.new()
	source.start_new_profile()
	for schema in [1, 2, 3, 4, 5, 6, 7]:
		var legacy := source.persistent_payload("base")
		legacy.schema_version = schema
		legacy.profile.schema_version = schema
		var state := ApplicationState.new()
		_expect(_code(state.restore_persistent_payload(legacy)) == "unsupported_schema_version" and not state.has_profile(),
			"restore: old schema %d was not rejected atomically" % schema, failures)


func _test_atomic_equipment_and_resolved_snapshot(failures: Array[String]) -> void:
	var state := ApplicationState.new()
	_expect(_code(state.equip_item("x")) == "profile_required", "equip: profile should be required", failures)
	_expect(_code(state.resolved_build_snapshot()) == "profile_required", "resolve: profile should be required", failures)
	state.start_new_profile()
	state.select_ranger_build("critical")
	var resolved: Dictionary = state.resolved_build_snapshot()
	_expect(bool(resolved.get("ok", false)) and int(resolved.generation_count) == 80
		and _is_fingerprint(String(resolved.build_fingerprint))
		and resolved.equipped_instance_ids.size() == 12,
		"resolve: fixture did not produce a complete deterministic snapshot", failures)
	var before_failure := state.profile
	_expect(_code(state.equip_item("not-owned")) == "item_not_owned", "equip: ownership was not enforced", failures)
	_expect(state.profile == before_failure, "equip: failed ownership check changed state", failures)
	_expect(_code(state.equip_item("calibration_critical_main_hand")) == "item_already_equipped",
		"equip: duplicate instance was not rejected", failures)
	_expect(state.profile == before_failure, "equip: duplicate rejection changed state", failures)
	var mixed: Dictionary = state.equip_item("fixed_start_main_hand")
	_expect(bool(mixed.get("ok", false)) and String(state.profile.active_build.equipped_item_ids.main_hand) == "fixed_start_main_hand",
		"equip: owned mixed-build item was not atomically equipped", failures)
	var unequipped: Dictionary = state.unequip_item("main_hand")
	_expect(bool(unequipped.get("ok", false)) and String(state.profile.active_build.equipped_item_ids.main_hand).is_empty(),
		"unequip: prototype-open slot was not cleared", failures)
	var before_bad_slot := state.profile
	_expect(_code(state.unequip_item("head")) == "slot_not_prototype_open" and state.profile == before_bad_slot,
		"unequip: closed slot failure was not atomic", failures)
	var payload := state.persistent_payload("base")
	_expect(not payload.profile.has("resolved_build") and not payload.profile.active_build.has("resolved_build")
		and not payload.profile.active_build.has("preset_id") and not payload.profile.active_build.has("equipment"),
		"payload: derived build data leaked into persistence", failures)


func _test_restore_clears_transient_state(failures: Array[String]) -> void:
	var source := ApplicationState.new()
	source.start_new_profile("mage")
	var payload: Dictionary = source.persistent_payload("base")
	var state := ApplicationState.new()
	state.start_new_profile("ranger")
	state.prepare_contract({"contract_id": "running", "mode": "Auto", "seed": 4, "room_count": 2})
	state.begin_session()
	var restored: Dictionary = state.restore_persistent_payload(payload)
	_expect(bool(restored.get("ok", false)) and restored.route == "base", "restore: valid payload should restore route", failures)
	_expect(state.profile.initial_class == "mage", "restore: profile should be replaced", failures)
	_expect(state.pending_contract.is_empty() and state.active_session.is_empty(), "restore: transient state should clear", failures)
	var no_profile: Dictionary = source.persistent_payload("title")
	no_profile.profile = {}
	no_profile.safe_route = "base"
	var empty_restored: Dictionary = state.restore_persistent_payload(no_profile)
	_expect(bool(empty_restored.get("ok", false)) and empty_restored.route == "title" and not state.has_profile(), "restore: absent profile should force title", failures)
	var json_round_trip: Dictionary = payload.duplicate(true)
	json_round_trip.schema_version = float(ApplicationState.SCHEMA_VERSION)
	json_round_trip.profile.schema_version = float(ApplicationState.SCHEMA_VERSION)
	json_round_trip.profile.resources.law_tallies.inscribe = 0.0
	json_round_trip.profile.resources.law_tallies.rewrite = 0.0
	json_round_trip.profile.resources.law_tallies.refine = 0.0
	json_round_trip.profile.progression.contract_wins = 0.0
	json_round_trip.profile.progression.auto_contract_wins = 0.0
	var json_restored: Dictionary = state.restore_persistent_payload(json_round_trip)
	_expect(bool(json_restored.get("ok", false)) and state.has_profile() and state.profile == payload.profile, "restore: exact JSON number fields were rejected or not normalized", failures)
	var saved_again: Dictionary = state.persistent_payload("base")
	var second := ApplicationState.new()
	_expect(bool(second.restore_persistent_payload(saved_again).get("ok", false)) and second.profile == state.profile, "restore: v8 save/restore did not round-trip", failures)


func _test_restore_rejects_atomically(failures: Array[String]) -> void:
	var state := ApplicationState.new()
	state.start_new_profile("alchemist")
	state.prepare_contract({"contract_id": "keep", "mode": "Manual", "seed": 5, "room_count": 1})
	var before_profile: Dictionary = state.profile
	var before_pending: Dictionary = state.pending_contract
	var future := state.persistent_payload("base")
	future.schema_version = ApplicationState.PROFILE_SCHEMA_VERSION + 1
	_expect(_code(state.restore_persistent_payload(future)) == "unsupported_schema_version", "restore: future schema should be rejected", failures)
	_expect(state.profile == before_profile and state.pending_contract == before_pending, "restore: future schema rejection should be atomic", failures)
	var bad_profile := state.persistent_payload("base")
	bad_profile.profile.resources.law_tallies.inscribe = -1
	_expect(_code(state.restore_persistent_payload(bad_profile)) == "invalid_profile", "restore: bad profile should be rejected", failures)
	_expect(state.profile == before_profile and state.pending_contract == before_pending, "restore: bad profile rejection should be atomic", failures)
	var legacy_training := state.persistent_payload("base")
	legacy_training.profile.training = {"verified_builds": [], "last_report": {}}
	_expect(_code(state.restore_persistent_payload(legacy_training)) == "invalid_profile",
		"restore: legacy training structure was accepted by schema 8", failures)
	_expect(state.profile == before_profile and state.pending_contract == before_pending,
		"restore: legacy training rejection was not atomic", failures)
	var mismatched_report := state.persistent_payload("base")
	var valid_fingerprint := "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
	var other_fingerprint := "ffeeddccbbaa99887766554433221100ffeeddccbbaa99887766554433221100"
	mismatched_report.profile.training.reports_by_fingerprint[valid_fingerprint] = {"build_fingerprint": other_fingerprint}
	_expect(_code(state.restore_persistent_payload(mismatched_report)) == "invalid_profile",
		"restore: report whose fingerprint differs from its map key was accepted", failures)
	var bad_forge := state.persistent_payload("base")
	bad_forge.profile["forge"] = {}
	_expect(_code(state.restore_persistent_payload(bad_forge)) == "invalid_profile", "restore: persisted forge draft should be rejected", failures)
	_expect(state.profile == before_profile and state.pending_contract == before_pending, "restore: forge draft rejection should be atomic", failures)
	var direct_semantics := state.persistent_payload("base")
	direct_semantics.profile.active_build["runes"] = ["breeding_split"]
	direct_semantics.profile.active_build["laws"] = ["pack_hunt_mark"]
	_expect(_code(state.restore_persistent_payload(direct_semantics)) == "invalid_profile",
		"restore: direct persisted rune/law arrays were accepted by schema 8", failures)
	_expect(state.profile == before_profile and state.pending_contract == before_pending,
		"restore: direct semantic-array rejection was not atomic", failures)


func _test_repeatable_side_counting(failures: Array[String]) -> void:
	var side_plan := {"rooms": [{"room_id": "side-count", "drop_tags": ["equipment_general"]}]}
	var state := ApplicationState.new()
	state.start_new_profile()
	_unlock_equipment_drops(state)
	var first := _complete_side_attempt(state, ApplicationState.PITY_SIDE_CONTRACT_ID, 75001, side_plan)
	_expect(int(first.result.rewards.repeatable_attempt_number) == 1
		and int(state.profile.progression.repeatable_completion_counts[ApplicationState.PITY_SIDE_CONTRACT_ID]) == 1,
		"repeatable: first success did not start at attempt 1", failures)
	_begin_side_session(state, ApplicationState.PITY_SIDE_CONTRACT_ID, 75002, side_plan)
	state.complete_session({"outcome": "defeat"})
	_begin_side_session(state, ApplicationState.PITY_SIDE_CONTRACT_ID, 75003, side_plan)
	state.complete_session({"outcome": "error", "error": "room_runtime_failed"})
	_expect(int(state.profile.progression.repeatable_completion_counts[ApplicationState.PITY_SIDE_CONTRACT_ID]) == 1,
		"repeatable: defeat or error advanced the count", failures)
	_begin_side_session(state, ApplicationState.PITY_SIDE_CONTRACT_ID, 75004, side_plan)
	state.abandon_session()
	_expect(int(state.profile.progression.repeatable_completion_counts[ApplicationState.PITY_SIDE_CONTRACT_ID]) == 1,
		"repeatable: abandon advanced the count", failures)
	var fixed := _grant_session_result(state, "threshold_colossus", "Manual", "victory")
	_expect(not (fixed.result.rewards as Dictionary).has("repeatable_attempt_number")
		and not (fixed.result.rewards as Dictionary).has("pity_guarantee_family"),
		"repeatable: fixed mainline result gained repeatable metadata", failures)
	_expect(state.profile.progression.repeatable_completion_counts == {ApplicationState.PITY_SIDE_CONTRACT_ID: 1},
		"repeatable: fixed mainline advanced the repeatable count", failures)
	var second := _complete_side_attempt(state, ApplicationState.PITY_SIDE_CONTRACT_ID, 75005, side_plan)
	_expect(int(second.result.rewards.repeatable_attempt_number) == 2
		and not (second.result.rewards as Dictionary).has("pity_guarantee_family"),
		"repeatable: second success misreported attempt or pity", failures)
	var third := _complete_side_attempt(state, ApplicationState.PITY_SIDE_CONTRACT_ID, 75006, side_plan)
	_expect(int(third.result.rewards.repeatable_attempt_number) == 3
		and String(third.result.rewards.pity_guarantee_family) == "piercing_continuation",
		"repeatable: third success did not trigger pity", failures)
	var targeted := _complete_side_attempt(state, "side_targeted_equipment", 75007, side_plan)
	_expect(int(targeted.result.rewards.repeatable_attempt_number) == 1
		and not (targeted.result.rewards as Dictionary).has("pity_guarantee_family")
		and state.profile.progression.repeatable_completion_counts == {
			ApplicationState.PITY_SIDE_CONTRACT_ID: 3,
			"side_targeted_equipment": 1,
		},
		"repeatable: second side template did not count independently", failures)


func _test_repeatable_pity_guarantee(failures: Array[String]) -> void:
	var pity_plan := {"rooms": [
		{"room_id": "pity-inscribe", "drop_tags": ["inscribe_tally"]},
		{"room_id": "pity-rewrite", "drop_tags": ["rewrite_tally"]},
	]}
	var registry := EarlyItemRegistryScript.new()
	var registry_errors: Array[String] = registry.load_all()
	_expect(registry_errors.is_empty(), "pity: item registry failed to load", failures)
	var cases := [
		{"name": "convergent", "classification": "convergent", "p": 0.25, "d": 150.0, "T": 34.0, "expected": "piercing_continuation"},
		{"name": "critical", "classification": "critical", "p": 0.25, "d": 150.0, "T": 34.0, "expected": "piercing_continuation"},
		{"name": "exponential-low-p", "classification": "exponential", "p": 0.50, "d": 150.0, "T": 34.0, "expected": "piercing_continuation"},
		{"name": "exponential-short-range", "classification": "exponential", "p": 1.0, "d": 80.0, "T": 34.0, "expected": "seeking_distance"},
		{"name": "exponential-short-lifetime", "classification": "exponential", "p": 1.0, "d": 150.0, "T": 8.0, "expected": "projectile_lifetime"},
		{"name": "exponential-qualified", "classification": "exponential", "p": 0.61, "d": 150.0, "T": 34.0, "expected": "carrier_power"},
	]
	for case_index in cases.size():
		var test_case: Dictionary = cases[case_index]
		var state := ApplicationState.new()
		state.start_new_profile()
		_unlock_equipment_drops(state)
		var build := _pity_resolved_build(
			String(test_case.classification), float(test_case.p), float(test_case.d), float(test_case.T)
		)
		var plan_snapshot: Dictionary = pity_plan.duplicate(true)
		for attempt in [1, 2, 3]:
			var completed := _complete_side_attempt(
				state, ApplicationState.PITY_SIDE_CONTRACT_ID, 78000 + case_index * 10 + attempt, pity_plan, build
			)
			var attempt_label := "%s attempt %d" % [String(test_case.name), attempt]
			if attempt < 3:
				_expect(int(completed.result.rewards.repeatable_attempt_number) == attempt
					and not (completed.result.rewards as Dictionary).has("pity_guarantee_family")
					and int(completed.result.rewards.equipment_drop_count) == 0,
					"pity: %s misreported a non-pity attempt" % attempt_label, failures)
			else:
				var family := String(completed.result.rewards.get("pity_guarantee_family", ""))
				_expect(family == String(test_case.expected)
					and int(completed.result.rewards.repeatable_attempt_number) == 3
					and int(completed.result.rewards.equipment_drop_count) == 1,
					"pity: %s did not guarantee the expected family" % attempt_label, failures)
				var drops: Array = completed.result.rewards.equipment_drops
				_expect(drops.size() == 1 and _drops_have_family(drops, family),
					"pity: %s produced no real target-family item" % attempt_label, failures)
				for item in drops:
					_expect(registry.validate_item_instance(item).is_empty()
						and String((item as Dictionary).source.type) == "campaign_drop",
						"pity: %s item was not a validated generator drop" % attempt_label, failures)
		_expect(pity_plan == plan_snapshot, "pity: settlement mutated the caller room plan", failures)


func _test_repeatable_pity_period(failures: Array[String]) -> void:
	var pity_plan := {"rooms": [{"room_id": "pity-inscribe", "drop_tags": ["inscribe_tally"]}]}
	var state := ApplicationState.new()
	state.start_new_profile()
	_unlock_equipment_drops(state)
	var build := _pity_resolved_build("exponential", 1.0, 150.0, 34.0)
	for attempt in range(1, 7):
		var completed := _complete_side_attempt(
			state, ApplicationState.PITY_SIDE_CONTRACT_ID, 79000 + attempt, pity_plan, build
		)
		_expect(int(completed.result.rewards.repeatable_attempt_number) == attempt,
			"pity period: attempt %d number drifted" % attempt, failures)
		var triggered: bool = attempt % 3 == 0
		_expect(bool(completed.result.rewards.has("pity_guarantee_family")) == triggered
			and int(completed.result.rewards.equipment_drop_count) == (1 if triggered else 0),
			"pity period: attempt %d guarantee behavior is wrong" % attempt, failures)
		if triggered:
			_expect(String(completed.result.rewards.pity_guarantee_family) == "carrier_power"
				and _drops_have_family(completed.result.rewards.equipment_drops as Array, "carrier_power"),
				"pity period: attempt %d guaranteed the wrong family" % attempt, failures)


func _test_repeatable_seed_identity_and_isolation(failures: Array[String]) -> void:
	var fixed_a := ApplicationState.new()
	fixed_a.start_new_profile()
	_unlock_equipment_drops(fixed_a)
	var fixed_first := _complete_drop_gate_node(fixed_a, "mainline_03_first_elite", 71001)
	var fixed_b := ApplicationState.new()
	fixed_b.start_new_profile()
	_unlock_equipment_drops(fixed_b)
	var fixed_second := _complete_drop_gate_node(fixed_b, "mainline_03_first_elite", 71001)
	_expect(int(fixed_first.result.rewards.equipment_drop_count) == 1
		and fixed_first.result.rewards.equipment_drops == fixed_second.result.rewards.equipment_drops,
		"repeatable: fixed mainline drop identity drifted or gained an attempt suffix", failures)
	_expect(not (fixed_first.result.rewards as Dictionary).has("repeatable_attempt_number"),
		"repeatable: fixed mainline result gained repeatable metadata", failures)

	var side_plan := {"rooms": [{"room_id": "side-identity", "drop_tags": ["equipment_general"]}]}
	var side := ApplicationState.new()
	side.start_new_profile()
	_unlock_equipment_drops(side)
	var seen_ids := {}
	for attempt in [1, 2, 3]:
		var completed := _complete_side_attempt(side, "side_targeted_equipment", 71002, side_plan)
		_expect(int(completed.result.rewards.repeatable_attempt_number) == attempt
			and int(completed.result.rewards.equipment_drop_count) == 1,
			"repeatable: attempt %d drop settlement is wrong" % attempt, failures)
		var item_id := String(completed.result.rewards.equipment_drops[0].instance_id)
		_expect(not seen_ids.has(item_id),
			"repeatable: attempt %d reused an instance_id from an earlier attempt" % attempt, failures)
		seen_ids[item_id] = true

	var replay_a := ApplicationState.new()
	replay_a.start_new_profile()
	_unlock_equipment_drops(replay_a)
	var replay_b := ApplicationState.new()
	replay_b.start_new_profile()
	_unlock_equipment_drops(replay_b)
	for attempt in [1, 2]:
		var first_a := _complete_side_attempt(replay_a, "side_targeted_equipment", 71003, side_plan)
		var first_b := _complete_side_attempt(replay_b, "side_targeted_equipment", 71003, side_plan)
		_expect(first_a.result.rewards.equipment_drops == first_b.result.rewards.equipment_drops,
			"repeatable: identical profile state + attempt %d + seed was not reproducible" % attempt, failures)

	var pity_state := ApplicationState.new()
	pity_state.start_new_profile()
	_unlock_equipment_drops(pity_state)
	var qualified := _pity_resolved_build("exponential", 1.0, 150.0, 34.0)
	_complete_side_attempt(pity_state, ApplicationState.PITY_SIDE_CONTRACT_ID, 71004, side_plan, qualified)
	_complete_side_attempt(pity_state, ApplicationState.PITY_SIDE_CONTRACT_ID, 71005, side_plan, qualified)
	_begin_side_session(pity_state, ApplicationState.PITY_SIDE_CONTRACT_ID, 71006, side_plan, qualified)
	var raw_result := {"outcome": "victory", "rooms_completed": 1, "rewards": {"custom": "kept"}}
	var raw_before: Dictionary = raw_result.duplicate(true)
	var copied := pity_state.complete_session(raw_result)
	_expect(raw_result == raw_before and not (raw_result.rewards as Dictionary).has("equipment_drops")
		and not (raw_result.rewards as Dictionary).has("repeatable_attempt_number")
		and not (raw_result.rewards as Dictionary).has("pity_guarantee_family"),
		"repeatable: settlement mutated the caller result", failures)
	_expect(String(copied.result.rewards.custom) == "kept"
		and String(copied.result.rewards.pity_guarantee_family) == "carrier_power",
		"repeatable: settlement dropped caller rewards or missed pity metadata", failures)
	(copied.result.rewards as Dictionary)["pity_guarantee_family"] = "mutated"
	_expect(String(pity_state.last_result.rewards.pity_guarantee_family) == "carrier_power",
		"repeatable: returned result aliases internal settlement state", failures)


func _test_repeatable_counts_persistence_and_validation(failures: Array[String]) -> void:
	var source := ApplicationState.new()
	source.start_new_profile("ranger")
	var payload: Dictionary = source.persistent_payload("base")
	payload.profile.progression.erase("repeatable_completion_counts")
	var state := ApplicationState.new()
	var restored: Dictionary = state.restore_persistent_payload(payload)
	_expect(_code(restored) == "invalid_profile" and not state.has_profile(),
		"repeatable: incomplete current schema was not rejected", failures)
	state.start_new_profile("ranger")
	var before: Dictionary = state.profile
	var bad_key := state.persistent_payload("base")
	bad_key.profile.progression.repeatable_completion_counts = {"unknown_side": 1}
	_expect(_code(state.restore_persistent_payload(bad_key)) == "invalid_profile" and state.profile == before,
		"repeatable: unknown template key was accepted", failures)
	var bad_value := state.persistent_payload("base")
	bad_value.profile.progression.repeatable_completion_counts = {ApplicationState.PITY_SIDE_CONTRACT_ID: -1}
	_expect(_code(state.restore_persistent_payload(bad_value)) == "invalid_profile" and state.profile == before,
		"repeatable: negative count was accepted", failures)
	var bad_type := state.persistent_payload("base")
	bad_type.profile.progression.repeatable_completion_counts = {ApplicationState.PITY_SIDE_CONTRACT_ID: 1.5}
	_expect(_code(state.restore_persistent_payload(bad_type)) == "invalid_profile" and state.profile == before,
		"repeatable: fractional count was accepted", failures)

	var counting := ApplicationState.new()
	counting.start_new_profile()
	_unlock_equipment_drops(counting)
	var side_plan := {"rooms": [{"room_id": "persist-side", "drop_tags": ["equipment_general"]}]}
	_complete_side_attempt(counting, ApplicationState.PITY_SIDE_CONTRACT_ID, 71007, side_plan)
	_complete_side_attempt(counting, ApplicationState.PITY_SIDE_CONTRACT_ID, 71008, side_plan)
	var saved: Dictionary = counting.persistent_payload("base")
	var reloaded := ApplicationState.new()
	var reload_restored: Dictionary = reloaded.restore_persistent_payload(saved)
	_expect(bool(reload_restored.get("ok", false))
		and reloaded.profile.progression.repeatable_completion_counts == {ApplicationState.PITY_SIDE_CONTRACT_ID: 2},
		"repeatable: save/restore lost repeatable counts", failures)
	var third := _complete_side_attempt(reloaded, ApplicationState.PITY_SIDE_CONTRACT_ID, 71009, side_plan)
	_expect(int(third.result.rewards.repeatable_attempt_number) == 3
		and String(third.result.rewards.pity_guarantee_family) == "piercing_continuation"
		and reloaded.profile.progression.repeatable_completion_counts == {ApplicationState.PITY_SIDE_CONTRACT_ID: 3},
		"repeatable: restored counts did not drive attempt numbering or pity", failures)


func _test_equip_preview_errors_are_atomic(failures: Array[String]) -> void:
	var empty_state := ApplicationState.new()
	_expect(_code(empty_state.preview_equip_item("anything")) == "profile_required",
		"preview: profile should be required", failures)

	var state := ApplicationState.new()
	state.start_new_profile()
	var before := state.profile
	_expect(_code(state.preview_equip_item("")) == "invalid_instance_id"
		and _code(state.preview_equip_item("   ")) == "invalid_instance_id",
		"preview: empty or blank instance id should be rejected", failures)
	_expect(_code(state.preview_equip_item("calibration_exponential_main_hand")) == "item_not_owned",
		"preview: unowned item should be rejected", failures)
	_expect(_code(state.preview_equip_item("fixed_start_main_hand")) == "item_already_equipped",
		"preview: already-equipped item should be rejected", failures)
	_expect(state.profile == before, "preview: failed previews changed profile state", failures)

	# Closed-slot parity: registry validation already rejects non-prototype-open slots,
	# so the preview slot guard (mirrored from equip_item) is defense-in-depth only with
	# the current content. This pins that invariant instead of reaching dead code.
	var registry := EarlyItemRegistryScript.new()
	_expect(registry.load_all().is_empty(), "preview: item registry failed to load", failures)
	var closed_slot_item: Dictionary = (before.inventory.equipment as Array)[0].duplicate(true)
	closed_slot_item["slot"] = "head"
	_expect(not registry.validate_item_instance(closed_slot_item).is_empty(),
		"preview: closed-slot items must fail registry validation before the preview slot guard", failures)


func _test_equip_preview_matches_real_equip(failures: Array[String]) -> void:
	var state := ApplicationState.new()
	state.start_new_profile()
	state.select_ranger_build("exponential")
	state.select_ranger_build("critical")
	# Owned = fixed_start + calibration_exponential + calibration_critical;
	# active build = calibration_critical.
	var current := state.resolved_build_snapshot()
	_expect(bool(current.get("ok", false)), "preview: current build did not resolve", failures)
	var current_p := float(current.final_parameters.p)
	var before := state.profile

	var up := state.preview_equip_item("calibration_exponential_main_hand")
	_expect(bool(up.get("ok", false))
		and String(up.instance_id) == "calibration_exponential_main_hand"
		and String(up.slot) == "main_hand",
		"preview: owned inventory candidate was not previewed", failures)
	_expect(float(up.final_parameters.p) > current_p,
		"preview: exponential main_hand should raise final p", failures)
	_expect(_is_fingerprint(String(up.build_fingerprint)) and not String(up.growth_classification).is_empty(),
		"preview: post-equip fingerprint or classification is missing", failures)
	_expect(up.interfaces_gained.is_empty() and up.interfaces_lost.is_empty()
		and up.tags_gained.is_empty() and up.tags_lost.is_empty(),
		"preview: affix-only swap must not fabricate interface or tag deltas", failures)
	_expect(up.current_resolved == current,
		"preview: current_resolved diverges from the authoritative snapshot", failures)

	var down := state.preview_equip_item("fixed_start_main_hand")
	_expect(bool(down.get("ok", false)) and float(down.final_parameters.p) < current_p,
		"preview: fixed main_hand should lower final p", failures)
	_expect(state.profile == before, "preview: previews changed profile state", failures)

	# Repeated previews are deterministic and returned data must not alias internals.
	var pristine := up.duplicate(true)
	_expect(state.preview_equip_item("calibration_exponential_main_hand") == pristine,
		"preview: repeated preview is not deterministic", failures)
	var tampered_parameters: Dictionary = up.resolved_build.final_parameters
	tampered_parameters["p"] = -999.0
	(up.final_parameters as Dictionary)["p"] = -999.0
	(up.interfaces_gained as Array).append("tampered")
	(up.tags_gained as Array).append("tampered")
	(up.current_resolved as Dictionary)["build_fingerprint"] = "tampered"
	_expect(state.preview_equip_item("calibration_exponential_main_hand") == pristine,
		"preview: returned preview data aliases internal state", failures)
	_expect(state.profile == before and state.resolved_build_snapshot() == current,
		"preview: preview mutated profile or resolved state", failures)

	# The previewed build must resolve exactly like the real equip.
	var equipped := state.equip_item("calibration_exponential_main_hand")
	_expect(bool(equipped.get("ok", false)), "preview: real equip after preview failed", failures)
	var after := state.resolved_build_snapshot()
	_expect(pristine.resolved_build == after
		and pristine.final_parameters == after.final_parameters
		and String(pristine.build_fingerprint) == String(after.build_fingerprint)
		and String(pristine.growth_classification) == String(after.growth_classification)
		and pristine.resolved_build.connected_interfaces == after.connected_interfaces,
		"preview: previewed resolved build diverges from the real equip result", failures)


func _test_equip_preview_interface_deltas(failures: Array[String]) -> void:
	var state := ApplicationState.new()
	state.start_new_profile()
	state.select_ranger_build("critical")
	for slot in ["main_hand", "off_hand", "gloves", "ring_1"]:
		_expect(bool(state.unequip_item(slot).get("ok", false)), "preview setup: unequip %s failed" % slot, failures)
		_expect(bool(state.equip_item("fixed_start_%s" % slot).get("ok", false)), "preview setup: equip fixed %s failed" % slot, failures)
	var current := state.resolved_build_snapshot()
	_expect(bool(current.get("ok", false)) and current.connected_interfaces == ["piercing_continuation"],
		"preview setup: fixed-equipment baseline interfaces are wrong", failures)
	var parameters_before: Dictionary = current.final_parameters

	# Calibration gloves carry the breeding_split rune -> exactly one gained interface.
	var gain := state.preview_equip_item("calibration_critical_gloves")
	_expect(bool(gain.get("ok", false))
		and gain.interfaces_gained == ["breedable_event"]
		and gain.interfaces_lost.is_empty(),
		"preview: rune item did not report the gained interface", failures)
	_expect(gain.tags_gained.is_empty() and gain.tags_lost.is_empty(),
		"preview: interface change must not fabricate tag deltas", failures)
	_expect(gain.final_parameters == parameters_before,
		"preview: pure interface item must not change final parameters", failures)

	# The real equip keeps the preview authoritative; dropping the rune reports the loss.
	var equipped := state.equip_item("calibration_critical_gloves")
	_expect(bool(equipped.get("ok", false)), "preview: real equip of rune item failed", failures)
	_expect(equipped.resolved_build == gain.resolved_build,
		"preview: rune preview diverged from the real equip result", failures)
	var before_loss := state.profile
	var loss := state.preview_equip_item("fixed_start_gloves")
	_expect(bool(loss.get("ok", false))
		and loss.interfaces_lost == ["breedable_event"]
		and loss.interfaces_gained.is_empty(),
		"preview: dropping the rune item did not report the lost interface", failures)
	_expect(loss.tags_gained.is_empty() and loss.tags_lost.is_empty(),
		"preview: dropped interface must not fabricate tag deltas", failures)
	_expect(state.profile == before_loss, "preview: loss preview changed profile state", failures)


func _test_equip_preview_session_invariance(failures: Array[String]) -> void:
	var state := ApplicationState.new()
	state.start_new_profile()
	state.select_ranger_build("critical")
	state.prepare_contract({"contract_id": "preview-probe", "mode": "Manual", "seed": 5, "room_count": 2})
	_expect(bool(state.begin_session().get("ok", false)), "preview: session setup failed", failures)
	var profile_before := state.profile
	var session_before := state.active_session
	var result_before := state.last_result
	var pending_before := state.pending_contract
	var preview := state.preview_equip_item("fixed_start_main_hand")
	_expect(bool(preview.get("ok", false)), "preview: probe during active session failed", failures)
	_expect(_code(state.preview_equip_item("missing-instance")) == "item_not_owned",
		"preview: unowned probe during session should fail", failures)
	_expect(state.profile == profile_before and state.active_session == session_before
		and state.last_result == result_before and state.pending_contract == pending_before,
		"preview: preview changed profile, pending, session, or result state", failures)


func _test_salvage_validation_errors(failures: Array[String]) -> void:
	var empty_state := ApplicationState.new()
	_expect(_code(empty_state.salvage_item_preview("fixed_start_main_hand")) == "profile_required"
		and _code(empty_state.salvage_item("fixed_start_main_hand")) == "profile_required",
		"salvage: profile should be required for preview and commit", failures)

	var state := ApplicationState.new()
	state.start_new_profile()
	_expect(_code(state.salvage_item_preview("")) == "invalid_instance_id"
		and _code(state.salvage_item_preview("   ")) == "invalid_instance_id"
		and _code(state.salvage_item("")) == "invalid_instance_id",
		"salvage: empty or blank instance id should be rejected", failures)
	_expect(_code(state.salvage_item_preview("missing-instance")) == "item_not_owned"
		and _code(state.salvage_item("missing-instance")) == "item_not_owned",
		"salvage: unowned instance should be rejected", failures)
	var starter_preview := state.salvage_item_preview("fixed_start_main_hand")
	_expect(bool(starter_preview.get("ok", false)) and String(starter_preview.get("equipped_slot", "")) == "main_hand",
		"salvage: equipped fixed-start item should preview an explicit safe unequip", failures)
	state.select_ranger_build("critical")
	var calibration_preview := state.salvage_item_preview("calibration_critical_main_hand")
	_expect(bool(calibration_preview.get("ok", false)) and String(calibration_preview.get("equipped_slot", "")) == "main_hand",
		"salvage: equipped calibration item should be eligible with safe unequip", failures)
	_inject_salvage_probe(state, _salvage_probe_item("salvage_probe_other", 1, "other"))
	_expect(bool(state.salvage_item_preview("salvage_probe_other").get("ok", false)),
		"salvage: a registry-valid owned item should not be rejected by source type", failures)
	var invalid: Dictionary = _salvage_probe_item("salvage_probe_invalid", 2)
	invalid["base_item_id"] = "no_such_base"
	_inject_salvage_probe(state, invalid)
	_expect(_code(state.salvage_item_preview("salvage_probe_invalid")) == "invalid_item_instance"
		and _code(state.salvage_item("salvage_probe_invalid")) == "invalid_item_instance",
		"salvage: registry-invalid item must be rejected", failures)
	_inject_salvage_probe(state, _salvage_probe_item("salvage_probe_equipped", 7))
	_expect(bool(state.unequip_item("main_hand").get("ok", false))
		and bool(state.equip_item("salvage_probe_equipped").get("ok", false)),
		"salvage: equipping the probe for safe-unequip coverage failed", failures)
	var equipped_preview := state.salvage_item_preview("salvage_probe_equipped")
	_expect(bool(equipped_preview.get("ok", false)) and String(equipped_preview.get("equipped_slot", "")) == "main_hand",
		"salvage: equipped item preview did not expose its safe-unequip slot", failures)
	var before_probes := state.profile
	_expect(bool(state.salvage_item_preview("salvage_probe_other").get("ok", false))
		and bool(state.salvage_item_preview("salvage_probe_equipped").get("ok", false))
		and _code(state.salvage_item("missing-instance")) == "item_not_owned"
		and state.profile == before_probes,
		"salvage: previews or rejected ids changed profile state", failures)

	var equipped_state := ApplicationState.new()
	equipped_state.start_new_profile()
	var equipped_commit := equipped_state.salvage_item("fixed_start_main_hand")
	_expect(bool(equipped_commit.get("ok", false))
		and String(equipped_commit.get("unequipped_slot", "")) == "main_hand"
		and String(equipped_state.profile.active_build.equipped_item_ids.main_hand).is_empty()
		and not _has_equipment_instance(equipped_state.profile.inventory.equipment, "fixed_start_main_hand")
		and bool(equipped_state.resolved_build_snapshot().get("ok", false)),
		"salvage: equipped starter commit did not atomically unequip, remove, and preserve a resolvable build", failures)


func _test_salvage_track_mapping_and_consistency(failures: Array[String]) -> void:
	var probes := {
		"salvage_probe_add": {"seed": 18, "operation": "inscribe"},
		"salvage_probe_rewrite": {"seed": 5, "operation": "rewrite"},
		"salvage_probe_refine": {"seed": 3, "operation": "refine"},
	}
	var registry := EarlyItemRegistryScript.new()
	_expect(registry.load_all().is_empty(), "salvage: item registry failed to load", failures)
	var state := ApplicationState.new()
	state.start_new_profile()
	for probe_id in probes:
		var probe: Dictionary = _salvage_probe_item(probe_id, int((probes[probe_id] as Dictionary).seed))
		_expect(registry.validate_item_instance(probe).is_empty(),
			"salvage: constructed %s probe failed registry validation" % probe_id, failures)
		_inject_salvage_probe(state, probe)
	var before := state.profile
	for probe_id in probes:
		var preview: Dictionary = state.salvage_item_preview(probe_id)
		_expect(bool(preview.get("ok", false))
			and String(preview.instance_id) == probe_id
			and String(preview.operation) == String((probes[probe_id] as Dictionary).operation)
			and int(preview.amount) == 1
			and preview.item == _salvage_probe_item(probe_id, int((probes[probe_id] as Dictionary).seed)),
			"salvage: deterministic track preview for %s is wrong" % probe_id, failures)
		_expect(state.profile == before, "salvage: preview for %s changed profile state" % probe_id, failures)
		var tampered: Dictionary = preview.item
		tampered["instance_id"] = "tampered"
		_expect(state.salvage_item_preview(probe_id).item == _salvage_probe_item(probe_id, int((probes[probe_id] as Dictionary).seed))
			and state.profile == before,
			"salvage: preview item aliased inventory for %s" % probe_id, failures)
	_expect(state.salvage_item_preview("salvage_probe_add").operation == state.salvage_item_preview("salvage_probe_add").operation
		and state.salvage_item_preview("salvage_probe_rewrite").operation == state.salvage_item_preview("salvage_probe_rewrite").operation
		and state.salvage_item_preview("salvage_probe_refine").operation == state.salvage_item_preview("salvage_probe_refine").operation,
		"salvage: repeated previews are not deterministic", failures)

	# A real campaign drop must follow the same chain end to end.
	var drop_state := ApplicationState.new()
	drop_state.start_new_profile()
	drop_state.complete_tutorial()
	_complete_drop_gate_node(drop_state, "mainline_01_first_hunt", 301)
	_complete_drop_gate_node(drop_state, "mainline_02_priority_under_pressure", 302)
	var elite := _complete_drop_gate_node(drop_state, "mainline_03_first_elite", 303)
	var drops: Array = elite.result.rewards.equipment_drops
	var campaign_drops: Array = drops.filter(func(item: Variant) -> bool:
		return item is Dictionary and String((item as Dictionary).get("source", {}).get("type", "")) == "campaign_drop"
	)
	_expect(drops.size() == 2 and campaign_drops.size() == 1, "salvage: room drop and stable reward were not separated", failures)
	if not campaign_drops.is_empty():
		var drop: Dictionary = campaign_drops[0]
		var identity := "%s|%d" % [String(drop.instance_id), int(drop.law_seed)]
		var expected_operation: String = ["inscribe", "rewrite", "refine"][int(("0x" + identity.sha256_text().substr(0, 8)).hex_to_int()) % 3]
		var drop_preview: Dictionary = drop_state.salvage_item_preview(String(drop.instance_id))
		_expect(bool(drop_preview.get("ok", false)) and String(drop_preview.operation) == String(expected_operation)
			and String(drop.source.type) == "campaign_drop",
			"salvage: real campaign drop track mapping is wrong", failures)


func _test_salvage_commit_and_atomics(failures: Array[String]) -> void:
	var state := ApplicationState.new()
	state.start_new_profile()
	_inject_salvage_probe(state, _salvage_probe_item("salvage_probe_add", 18))
	_inject_salvage_probe(state, _salvage_probe_item("salvage_probe_rewrite", 5))
	_inject_salvage_probe(state, _salvage_probe_item("salvage_probe_refine", 3))
	state.prepare_contract({"contract_id": "salvage-probe", "mode": "Manual", "seed": 1, "room_count": 1})
	_expect(bool(state.begin_session().get("ok", false)), "salvage: session setup failed", failures)
	var before := state.profile
	var before_session := state.active_session
	var before_result := state.last_result
	var before_inventory_size := (before.inventory.equipment as Array).size()
	var before_tallies: Dictionary = (before.resources.law_tallies as Dictionary).duplicate(true)

	var preview: Dictionary = state.salvage_item_preview("salvage_probe_add")
	var committed: Dictionary = state.salvage_item("salvage_probe_add")
	_expect(bool(committed.get("ok", false))
		and String(committed.instance_id) == "salvage_probe_add"
		and String(committed.operation) == "inscribe"
		and int(committed.amount) == 1,
		"salvage: valid add-track commit failed", failures)
	_expect(preview.item == committed.salvaged_item and String(preview.operation) == String(committed.operation)
		and int(preview.amount) == int(committed.amount),
		"salvage: preview and commit diverged", failures)
	var after := state.profile
	_expect((after.inventory.equipment as Array).size() == before_inventory_size - 1
		and not _has_equipment_instance(after.inventory.equipment, "salvage_probe_add")
		and _has_equipment_instance(after.inventory.equipment, "salvage_probe_rewrite")
		and _has_equipment_instance(after.inventory.equipment, "salvage_probe_refine"),
		"salvage: commit did not remove exactly the targeted instance", failures)
	_expect(int(after.resources.law_tallies.inscribe) == int(before_tallies.inscribe) + 1
		and int(after.resources.law_tallies.rewrite) == int(before_tallies.rewrite)
		and int(after.resources.law_tallies.refine) == int(before_tallies.refine),
		"salvage: inscribe tally refund is wrong", failures)
	_expect(after.active_build == before.active_build
		and after.training == before.training
		and after.progression == before.progression
		and state.active_session == before_session
		and state.last_result == before_result,
		"salvage: commit touched build, training, progression, cursors, session, or result", failures)
	var tampered: Dictionary = committed.salvaged_item
	tampered["instance_id"] = "tampered"
	_expect(not _has_equipment_instance(state.profile.inventory.equipment, "salvage_probe_add")
		and _code(state.salvage_item("salvage_probe_add")) == "item_not_owned"
		and not _has_equipment_instance(state.profile.inventory.equipment, "tampered"),
		"salvage: returned item aliased state or repeat salvage was not rejected", failures)
	for probe_id in ["salvage_probe_rewrite", "salvage_probe_refine"]:
		var expected_operation: String = "rewrite" if probe_id == "salvage_probe_rewrite" else "refine"
		var tallies_before: Dictionary = (state.profile.resources.law_tallies as Dictionary).duplicate(true)
		var done: Dictionary = state.salvage_item(probe_id)
		_expect(bool(done.get("ok", false)) and String(done.operation) == expected_operation and int(done.amount) == 1,
			"salvage: %s track commit failed" % probe_id, failures)
		_expect(int(state.profile.resources.law_tallies[expected_operation]) == int(tallies_before[expected_operation]) + 1,
			"salvage: %s tally refund is wrong" % probe_id, failures)


func _test_salvage_persistence_roundtrip(failures: Array[String]) -> void:
	var state := ApplicationState.new()
	state.start_new_profile()
	_inject_salvage_probe(state, _salvage_probe_item("salvage_probe_add", 18))
	var committed: Dictionary = state.salvage_item("salvage_probe_add")
	_expect(bool(committed.get("ok", false)), "salvage: persistence setup commit failed", failures)
	var payload: Dictionary = state.persistent_payload("base")
	_expect(payload.schema_version == ApplicationState.PROFILE_SCHEMA_VERSION and int(payload.profile.schema_version) == ApplicationState.PROFILE_SCHEMA_VERSION,
		"salvage: salvage changed the persisted schema version", failures)
	var restored := ApplicationState.new()
	_expect(bool(restored.restore_persistent_payload(payload).get("ok", false))
		and restored.profile == state.profile,
		"salvage: post-salvage payload did not restore round-trip", failures)
	_expect(not _has_equipment_instance(restored.profile.inventory.equipment, "salvage_probe_add")
		and int(restored.profile.resources.law_tallies.inscribe) == 1,
		"salvage: restored refund state is wrong", failures)


func _salvage_probe_item(instance_id: String, law_seed: int, source_type: String = "campaign_drop") -> Dictionary:
	var registry := EarlyItemRegistryScript.new()
	if not registry.load_all().is_empty():
		return {}
	var template: Dictionary = (registry.item_instances.get("fixed_start_main_hand", {}) as Dictionary).duplicate(true)
	if template.is_empty():
		return {}
	template["instance_id"] = instance_id
	template["source"] = {"type": source_type, "id": "salvage_probe"}
	template["law_seed"] = law_seed
	return template


func _inject_salvage_probe(state: ApplicationState, item: Dictionary) -> void:
	(state._profile.inventory.equipment as Array).append(item.duplicate(true))


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


func _pity_resolved_build(classification: String, growth_p: float, distance: float, lifetime: float) -> Dictionary:
	return {
		"ok": true,
		"growth_classification": classification,
		"final_parameters": {
			"p": growth_p,
			"T": lifetime,
			"v": 620.0,
			"d": distance,
			"turn": 0.18,
			"damage": 100.0,
			"max_health": 100.0,
		},
	}


func _drops_have_family(drops: Array, family: String) -> bool:
	for item in drops:
		if not (item is Dictionary):
			continue
		for affix in (item as Dictionary).get("affixes", []):
			if affix is Dictionary and String((affix as Dictionary).get("family_id", "")) == family:
				return true
	return false


func _grant_victory(state: ApplicationState, rewards: Dictionary, contract_id: String) -> void:
	state.prepare_contract({"contract_id": contract_id, "mode": "Auto", "seed": 1, "room_count": 1})
	state.begin_session()
	state.complete_session({"outcome": "victory", "rewards": rewards})


func _unlock_forge(state: ApplicationState) -> void:
	state.complete_tutorial()
	for node_id in [
		"mainline_01_first_hunt",
		"mainline_02_priority_under_pressure",
		"mainline_03_first_elite",
		"mainline_04_hazard_and_forge",
	]:
		_grant_session_result(state, node_id, "Manual", "victory")


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


func _near(actual: float, expected: float) -> bool:
	return absf(actual - expected) < 0.000001


func _is_fingerprint(value: String) -> bool:
	if value.length() != 64:
		return false
	for character in value:
		if character not in "0123456789abcdef":
			return false
	return true


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
