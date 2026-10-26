extends "res://tests/helpers/application_state_suite.gd"

## Room equipment-drop settlement, room-victory handoff and the repeatable pity guarantee.
const BuildResolverScript = preload("res://src/systems/build_resolver.gd")
const EarlyItemRegistryScript = preload("res://src/content/early_item_registry.gd")
const ContractPlanScript = preload("res://src/game/contract_plan.gd")


func run() -> Array[String]:
	var failures: Array[String] = []
	_test_first_hunt_equipment_drop_gate(failures)
	_test_room_equipment_drop_settlement(failures)
	_test_room_victory_commit_handoff(failures)
	_test_repeatable_side_counting(failures)
	_test_repeatable_pity_guarantee(failures)
	_test_repeatable_pity_period(failures)
	_test_repeatable_seed_identity_and_isolation(failures)
	return failures


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


func _test_room_victory_commit_handoff(failures: Array[String]) -> void:
	# Room 0 victory commits its picked loot exactly once, keeps the equipped
	# build untouched, refreshes the session build and advances the room cursor.
	var state := ApplicationState.new()
	state.start_new_profile("ranger")
	state.prepare_contract({
		"contract_id": "handoff.test",
		"mode": "Manual",
		"seed": 9001,
		"room_count": 2,
		"resolved_build": state.resolved_build_snapshot(),
		"room_plan": {"rooms": [{"room_id": "handoff-a"}, {"room_id": "handoff-b"}]},
	})
	state.begin_session()
	var inventory_size: int = (state.profile.inventory.equipment as Array).size()
	var active_before: Dictionary = state.profile.active_build
	var committed: Dictionary = state.commit_room_victory_and_resolve_next_build(
		0, _handoff_victory_result([_handoff_loot_instance(state, "handoff_loot_a")])
	)
	_expect(bool(committed.get("ok", false)), "handoff: room 0 commit failed: %s" % _code(committed), failures)
	if bool(committed.get("ok", false)):
		_expect((committed.committed_items as Array).size() == 1
			and String((committed.committed_items as Array)[0].instance_id) == "handoff_loot_a",
			"handoff: committed_items must carry the picked instance exactly once", failures)
		_expect((state.profile.inventory.equipment as Array).size() == inventory_size + 1
			and _has_equipment_instance(state.profile.inventory.equipment, "handoff_loot_a"),
			"handoff: picked loot did not land in the equipment inventory", failures)
		_expect(state.profile.active_build == active_before,
			"handoff: commit must not auto-equip loot", failures)
		_expect(int(state.active_session.room_index) == 1,
			"handoff: session room_index did not advance", failures)
		var fingerprint := String((committed.resolved_build as Dictionary).get("build_fingerprint", ""))
		_expect(fingerprint.length() == 64
			and (state.active_session.resolved_build as Dictionary) == (committed.resolved_build as Dictionary),
			"handoff: session resolved_build did not adopt the refreshed resolver output", failures)
		committed.resolved_build["build_fingerprint"] = "mutated"
		committed.active_build["equipped_item_ids"]["main_hand"] = "mutated"
		(committed.committed_items as Array)[0]["instance_id"] = "mutated"
		_expect(String((state.active_session.resolved_build as Dictionary).get("build_fingerprint", "")) == fingerprint
			and _has_equipment_instance(state.profile.inventory.equipment, "handoff_loot_a")
			and state.profile.active_build == active_before,
			"handoff: returned commit data aliases internal state", failures)

	# Rejections fail closed: session cursor and inventory stay untouched.
	var locked_inventory: int = (state.profile.inventory.equipment as Array).size()
	_expect(_code(state.commit_room_victory_and_resolve_next_build(
		0, _handoff_victory_result([_handoff_loot_instance(state, "handoff_loot_dup")])
	)) == "room_index_mismatch",
		"handoff: duplicate room 0 call must be rejected by the advanced cursor", failures)
	_expect(_code(state.commit_room_victory_and_resolve_next_build(5, _handoff_victory_result([]))) == "room_index_mismatch",
		"handoff: wrong room index must be rejected", failures)
	_expect(_code(state.commit_room_victory_and_resolve_next_build(1, {"outcome": "defeat"})) == "room_victory_required",
		"handoff: non-victory room result must be rejected", failures)
	var failed_settlement := _handoff_victory_result([])
	(failed_settlement.room_loot_settlement as Dictionary)["ok"] = false
	_expect(_code(state.commit_room_victory_and_resolve_next_build(1, failed_settlement)) == "invalid_room_loot_settlement",
		"handoff: failed settlement receipt must be rejected", failures)
	var lost_settlement := _handoff_victory_result([])
	(lost_settlement.room_loot_settlement as Dictionary)["outcome"] = "defeat"
	_expect(_code(state.commit_room_victory_and_resolve_next_build(1, lost_settlement)) == "invalid_room_loot_settlement",
		"handoff: settlement outcome must match the room victory", failures)
	var stray_items := _handoff_victory_result([])
	(stray_items.room_loot_settlement as Dictionary)["items"] = "not-an-array"
	_expect(_code(state.commit_room_victory_and_resolve_next_build(1, stray_items)) == "invalid_room_loot_settlement",
		"handoff: settlement items must be an array", failures)
	var unregistered := _handoff_victory_result([_handoff_loot_instance(state, "handoff_loot_bad")])
	((unregistered.room_loot_settlement as Dictionary).items as Array)[0].erase("affixes")
	_expect(_code(state.commit_room_victory_and_resolve_next_build(1, unregistered)) == "invalid_room_loot_item",
		"handoff: loot failing registry validation must be rejected", failures)
	_expect(_code(state.commit_room_victory_and_resolve_next_build(1, _handoff_victory_result(["not-an-item"]))) == "invalid_room_loot_item",
		"handoff: non-ItemInstance loot entry must be rejected", failures)
	_expect((state.profile.inventory.equipment as Array).size() == locked_inventory
		and int(state.active_session.room_index) == 1,
		"handoff: rejected commits must leave session and inventory untouched", failures)

	# A lootless victory still advances the cursor with nothing committed.
	var lootless: Dictionary = state.commit_room_victory_and_resolve_next_build(1, {"outcome": "victory"})
	_expect(bool(lootless.get("ok", false)) and (lootless.committed_items as Array).is_empty()
		and int(state.active_session.room_index) == 2,
		"handoff: lootless victory must commit nothing and advance the cursor", failures)

	# complete_session stays the single late settlement: committed loot is not
	# appended or re-reported twice.
	var finalized: Dictionary = state.complete_session({
		"outcome": "victory",
		"room_count": 2,
		"rooms_completed": 2,
		"room_results": [
			_handoff_victory_result([_handoff_loot_instance(state, "handoff_loot_a")]),
			{"outcome": "victory"},
		],
		"rewards": {},
	})
	_expect(bool(finalized.get("ok", false)), "handoff: contract settlement failed", failures)
	_expect(_equipment_instance_count(state.profile.inventory.equipment, "handoff_loot_a") == 1,
		"handoff: committed loot was appended a second time by complete_session", failures)
	_expect(((finalized.result.rewards as Dictionary).get("equipment_drops", []) as Array).is_empty(),
		"handoff: complete_session re-reported already committed loot", failures)

	# Without an active session the boundary fails closed.
	var fresh := ApplicationState.new()
	fresh.start_new_profile("ranger")
	_expect(_code(fresh.commit_room_victory_and_resolve_next_build(0, _handoff_victory_result([]))) == "active_session_required",
		"handoff: commit without an active session must fail", failures)


func _handoff_loot_instance(state: ApplicationState, instance_id: String) -> Dictionary:
	var item: Dictionary = (state.profile.inventory.equipment[0] as Dictionary).duplicate(true)
	item["instance_id"] = instance_id
	return item


func _handoff_victory_result(items: Array) -> Dictionary:
	return {
		"outcome": "victory",
		"room_loot_settlement": {
			"ok": true,
			"error": "",
			"outcome": "victory",
			"items": items.duplicate(true),
			"entities": [],
			"event_count": items.size(),
		},
	}


func _begin_drop_session(state: ApplicationState, seed: int, plan: Dictionary) -> void:
	state.prepare_contract({
		"contract_id": "drop-settlement",
		"mode": "Manual",
		"seed": seed,
		"room_count": (plan.rooms as Array).size(),
		"room_plan": plan.duplicate(true),
	})
	state.begin_session()


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
