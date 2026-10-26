extends "res://tests/helpers/application_state_suite.gd"

## Law Token forge context, reveal sessions and the two-phase commit.
const EarlyItemRegistryScript = preload("res://src/content/early_item_registry.gd")
const LawForgeScript = preload("res://src/systems/law_forge.gd")


func run() -> Array[String]:
	var failures: Array[String] = []
	_test_forge_defaults_and_preview(failures)
	_test_forge_commit_and_atomic_failure(failures)
	_test_forge_inventory_target_preview_and_commit(failures)
	_test_forge_context_normalization(failures)
	_test_forge_unique_result_horizon(failures)
	return failures


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
		and result_view.get("base_name", "") == "Ash Longbow"
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


func _unlock_forge(state: ApplicationState) -> void:
	state.complete_tutorial()
	for node_id in [
		"mainline_01_first_hunt",
		"mainline_02_priority_under_pressure",
		"mainline_03_first_elite",
		"mainline_04_hazard_and_forge",
	]:
		_grant_session_result(state, node_id, "Manual", "victory")
