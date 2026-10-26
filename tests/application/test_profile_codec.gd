extends "res://tests/helpers/application_state_suite.gd"

## Persistent payload round-trip, schema rejection and atomic restore validation.


func run() -> Array[String]:
	var failures: Array[String] = []
	_test_persistent_payload(failures)
	_test_old_schema_rejected(failures)
	_test_restore_clears_transient_state(failures)
	_test_restore_rejects_atomically(failures)
	_test_repeatable_counts_persistence_and_validation(failures)
	return failures


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
