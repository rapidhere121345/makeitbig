extends "res://tests/helpers/application_state_suite.gd"

## Campaign node completion, unlocks and auto-certification graduation.


func run() -> Array[String]:
	var failures: Array[String] = []
	_test_campaign_progression(failures)
	_test_auto_certification_graduation_normalization(failures)
	return failures


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
