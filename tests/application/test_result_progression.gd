extends "res://tests/helpers/application_state_suite.gd"

## Reward settlement and the Threshold Colossus defeat diagnosis.


func run() -> Array[String]:
	var failures: Array[String] = []
	_test_reward_settlement(failures)
	_test_boss_defeat_bottleneck(failures)
	return failures


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
