extends "res://tests/helpers/application_state_suite.gd"

## Profile creation, tutorial completion and the contract/session lifecycle.


func run() -> Array[String]:
	var failures: Array[String] = []
	_test_defaults(failures)
	_test_class_validation_and_new_profile(failures)
	_test_tutorial_completion(failures)
	_test_alias_isolation(failures)
	_test_contract_validation(failures)
	_test_session_lifecycle(failures)
	_test_abandon(failures)
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
