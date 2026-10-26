extends RefCounted

const GameRootScript = preload("res://src/game/game_root.gd")
const Assert := preload("res://tests/helpers/assert.gd")
const TEST_DIRECTORY: String = "user://makeitbig-game-root-tests"

class FakeArena:
	extends Node

	signal completed(result: Dictionary)
	signal abandoned(result: Dictionary)

	var config: Dictionary = {}
	var started: bool = false

	func start_session(value: Dictionary) -> Dictionary:
		if started:
			return {"ok": false, "error": "already_started"}
		started = true
		config = value.duplicate(true)
		return {"ok": true}

	func resolve(result: Dictionary) -> void:
		completed.emit(result.duplicate(true))


class FakePlaytestLog:
	extends RefCounted

	var events: Array[Dictionary] = []
	var active := false

	func start_session(context: Dictionary, _requested_session_id: String = "") -> Dictionary:
		active = true
		events.append({"event_id": "session_started", "payload": {}, "context": context.duplicate(true)})
		return {"ok": true}

	func record(event_id: String, payload: Dictionary = {}) -> Dictionary:
		if not active:
			return {"ok": false, "error": "session_not_started"}
		events.append({"event_id": event_id, "payload": payload.duplicate(true)})
		return {"ok": true}

	func finish(payload: Dictionary = {}) -> Dictionary:
		var recorded := record("session_finished", payload)
		active = false
		return recorded

	func is_active() -> bool:
		return active


class FailingSaveStore:
	extends RefCounted

	func save(_payload: Dictionary) -> Dictionary:
		return {"ok": false, "error": "injected_save_failure"}


func run() -> Array[String]:
	var failures: Array[String] = []
	_cleanup_test_directory()
	_test_complete_route_loop_and_resume(failures)
	_cleanup_test_directory()
	_test_proxy_player_flow(failures)
	_cleanup_test_directory()
	_test_result_drop_review_route(failures)
	_cleanup_test_directory()
	_test_defeat_and_victory_reason_output(failures)
	_cleanup_test_directory()
	_test_presentation_flag_wiring(failures)
	_cleanup_test_directory()
	_test_playtest_event_wiring(failures)
	_cleanup_test_directory()
	_test_capture_contract(failures)
	_cleanup_test_directory()
	return failures


func _test_complete_route_loop_and_resume(failures: Array[String]) -> void:
	var game = _create_game()
	_expect(game.current_route == "title", "game root: fresh boot did not reach title", failures)
	_expect(bool(game.start_new_game("ranger").get("ok", false)), "game root: new profile failed", failures)
	_expect(game.current_route == "tutorial" and game.application_state.has_profile(), "game root: new profile did not reach tutorial", failures)
	_expect(bool(game.complete_tutorial().get("ok", false)) and game.current_route == "base", "game root: tutorial did not reach base", failures)

	_expect(bool(game.open_facility("loadout").get("ok", false)), "game root: loadout did not open", failures)
	var loadout_data: Dictionary = game.current_screen.get("_facility_data")
	_expect(loadout_data.has("active_build") and loadout_data.has("training"), "game root: loadout did not receive early-game snapshot", failures)
	loadout_data.active_build["preset_id"] = "tampered"
	_expect(String(game.application_state.active_build_snapshot().active_build.preset_id) == "convergent", "game root: facility snapshot leaked into application state", failures)
	var selected: Dictionary = game.request_facility_action("loadout", "select_ranger_build", {"preset_id": "exponential"})
	_expect(bool(selected.get("ok", false)) and String(game.application_state.active_build_snapshot().active_build.preset_id) == "exponential", "game root: ranger Build selection was not routed", failures)
	loadout_data = game.current_screen.get("_facility_data")
	var equip_previews: Dictionary = loadout_data.get("equip_previews", {})
	var fixed_start_preview: Dictionary = equip_previews.get("fixed_start_main_hand", {})
	_expect(bool(fixed_start_preview.get("ok", false))
		and String(fixed_start_preview.get("build_fingerprint", "")).length() == 64
		and fixed_start_preview.get("final_parameters", {}) is Dictionary,
		"game root: loadout did not receive authoritative candidate previews", failures)
	if bool(fixed_start_preview.get("ok", false)):
		(fixed_start_preview.final_parameters as Dictionary)["p"] = -1.0
		_expect(float(game.application_state.preview_equip_item("fixed_start_main_hand").final_parameters.p) >= 0.0,
			"game root: candidate preview snapshot aliases application state", failures)
	var unequipped: Dictionary = game.request_facility_action("loadout", "unequip_item", {"slot": "main_hand"})
	_expect(bool(unequipped.get("ok", false)) and String(game.application_state.profile.active_build.equipped_item_ids.main_hand).is_empty(), "game root: real unequip action was not routed atomically", failures)
	var equipped: Dictionary = game.request_facility_action("loadout", "equip_item", {"instance_id": "calibration_exponential_main_hand"})
	_expect(bool(equipped.get("ok", false)) and String(game.application_state.active_build_snapshot().active_build.preset_id) == "exponential", "game root: real equip action did not restore the active Build", failures)
	_expect(bool(game.leave_facility().get("ok", false)), "game root: loadout did not return to base", failures)

	_expect(bool(game.open_contract().get("ok", false)) and game.current_route == "contract", "game root: base did not open contract prep", failures)
	game.current_screen.call("_build_ui")
	game.current_screen.call("_apply_presentation")
	var build_label: Label = game.current_screen.get("_build_label")
	var skill_label: Label = game.current_screen.find_child("SkillName_piercing_arrow", true, false)
	var continuation: Label = game.current_screen.find_child("Departure_p", true, false)
	var build_details: String = game.current_screen._components_summary(game.current_screen._active_build(), game.current_screen._resolved_build())
	var growth_conclusion: String = game.current_screen._growth_conclusion(game.current_screen._resolved_build())
	var mode_picker: OptionButton = game.current_screen.get("_mode_picker")
	var contract_picker: OptionButton = game.current_screen.get("_contract_picker")
	_expect(build_label != null and not build_label.visible and continuation != null and "%" in continuation.text
		and "Build Fingerprint: " not in build_label.text and growth_conclusion == "Unverified"
		and "exponential" not in build_label.text.to_lower(),
		"game root: contract did not present the real unverified Build safely", failures)
	_expect(skill_label != null and skill_label.text == "Piercing Arrow" and "Breeding Split" in build_details and "Pack Hunt Mark" in build_details, "game root: contract Build did not use the player-facing component names", failures)
	_expect(mode_picker != null and mode_picker.selected == 0 and mode_picker.is_item_disabled(1), "game root: fresh contract was not Manual with Auto disabled", failures)
	_expect(contract_picker != null and _selected_contract_id(contract_picker) == "mainline_01_first_hunt", "game root: contract board did not select the first available authored node", failures)
	game.set("_auto_smoke_session", true)
	var locked_auto: Dictionary = game.launch_contract({"contract_id": "auto_certification", "mode": "Auto", "preset_id": "critical", "seed": 5, "room_count": 1})
	game.set("_auto_smoke_session", false)
	_expect(String(locked_auto.get("error", "")) == "proxy_locked" and game.current_route == "contract", "game root: locked Auto did not stay on contract route", failures)
	_expect(bool(game.cancel_contract().get("ok", false)), "game root: locked contract could not be cancelled", failures)

	_expect(bool(game.open_facility("training").get("ok", false)), "game root: training did not open", failures)
	var training_data: Dictionary = game.current_screen.get("_facility_data")
	_expect(training_data.has("available_builds")
		and String((training_data.get("resolved_build", {}) as Dictionary).get("build_fingerprint", "")).length() == 64,
		"game root: training did not receive the current resolved Build", failures)
	var trial: Dictionary = game.request_facility_action("training", "run_training_trial")
	_expect(bool(trial.get("ok", false)) and String((trial.report as Dictionary).preset_id) == "exponential", "game root: training trial was not routed for active Build", failures)
	_expect(bool(game.leave_facility().get("ok", false)), "game root: training did not return to base", failures)
	_expect(bool(game.open_facility("proxy").get("ok", false)), "game root: proxy did not open", failures)
	var proxy_data: Dictionary = game.current_screen.get("_facility_data")
	_expect(proxy_data.has("proxy") and not bool((proxy_data.proxy as Dictionary).unlocked), "game root: proxy did not receive locked early-game snapshot", failures)
	_expect(bool(game.leave_facility().get("ok", false)), "game root: proxy did not return to base", failures)

	_expect(bool(game.open_contract().get("ok", false)), "game root: verified contract prep failed", failures)
	game.current_screen.call("_build_ui")
	game.current_screen.call("_apply_presentation")
	build_label = game.current_screen.get("_build_label")
	_expect(build_label != null and game.current_screen._growth_conclusion(game.current_screen._resolved_build()) == "Exponential" and "exponential" not in build_label.text.to_lower(), "game root: verified growth state was not presented", failures)
	var config := {
		"contract_id": "mainline_01_first_hunt",
		"mode": "Manual",
		"preset_id": "critical",
		"seed": 123,
		"room_count": 1,
	}
	_expect(bool(game.launch_contract(config).get("ok", false)) and game.current_route == "arena", "game root: first authored Manual contract did not launch", failures)
	var arena := game.current_screen as FakeArena
	_expect(arena != null and arena.started and arena.config.preset_id == "exponential" and config.preset_id == "critical", "game root: caller overrode the locked Build preset", failures)
	_expect(arena != null and String((arena.config.resolved_build as Dictionary).build_fingerprint).length() == 64, "game root: contract did not freeze the resolved Build", failures)
	_expect(arena != null and String((arena.config.room_plan as Dictionary).source) == "early_campaign" and String(((arena.config.room_plan as Dictionary).rooms[0] as Dictionary).enemy_ids[0]) == "melee_pursuer", "game root: authored RoomPlan did not reach the arena", failures)
	_expect(arena != null and int((arena.config.framework_context as Dictionary).contract_wins) == 0, "game root: arena did not receive progression context", failures)
	_expect(arena != null and String(((arena.config.framework_context as Dictionary).active_build as Dictionary).preset_id) == "exponential", "game root: active Build snapshot was not injected", failures)
	_expect(arena != null and (arena.config.framework_context as Dictionary).resolved_build == arena.config.resolved_build, "game root: framework context and session received different resolved Builds", failures)
	_expect(arena != null and ((arena.config.framework_context as Dictionary).resolved_proxy_build as Dictionary).is_empty(), "game root: Manual contract carried an active proxy decision contract", failures)
	if arena != null:
		((arena.config.framework_context as Dictionary).active_build as Dictionary).skills[0] = "tampered"
		((arena.config.framework_context as Dictionary).resolved_build as Dictionary).final_parameters.p = 0.01
		_expect(String(game.application_state.active_build_snapshot().active_build.skills[0]) == "piercing_arrow", "game root: active Build context was not deeply isolated", failures)
		_expect(float(game.application_state.resolved_build_snapshot().final_parameters.p) > 0.5, "game root: frozen resolved Build leaked back into profile state", failures)
		arena.resolve({
			"outcome": "victory",
			"ticks": 90,
			"elapsed_seconds": 3.0,
			"casts": 4,
			"defeated": 7,
			"rewards": {
				"contract_wins_delta": 1,
				"law_tallies_delta": {"inscribe": 2, "rewrite": 0, "refine": 0},
			},
		})
	_expect(game.current_route == "result", "game root: completed arena did not reach result", failures)
	_expect(not game.application_state.is_auto_mode_unlocked(), "game root: ordinary Manual victory incorrectly unlocked Auto", failures)
	_expect(bool(game.leave_result().get("ok", false)) and game.current_route == "base", "game root: result did not return to base", failures)

	var remaining_mainline := [
		"mainline_02_priority_under_pressure",
		"mainline_03_first_elite",
		"mainline_04_hazard_and_forge",
		"mainline_05_growth_gate",
	]
	for index in remaining_mainline.size():
		var node_id: String = remaining_mainline[index]
		_expect(bool(game.open_contract().get("ok", false)), "game root: could not open contract board for %s" % node_id, failures)
		var node_config := {"contract_id": node_id, "mode": "Manual", "preset_id": "convergent", "seed": 200 + index, "room_count": 1}
		_expect(bool(game.launch_contract(node_config).get("ok", false)), "game root: authored node %s did not launch" % node_id, failures)
		var node_arena := game.current_screen as FakeArena
		_expect(node_arena != null and String((node_arena.config.room_plan as Dictionary).contract_id) == node_id, "game root: %s lost its authored RoomPlan" % node_id, failures)
		if node_arena != null:
			node_arena.resolve({"outcome": "victory", "rewards": {"contract_wins_delta": 1}})
		_expect(game.current_route == "result", "game root: %s victory did not reach result" % node_id, failures)
		_expect(bool(game.leave_result().get("ok", false)), "game root: %s result did not return to base" % node_id, failures)
	_expect(not game.application_state.is_auto_mode_unlocked(), "game root: pre-Boss mainline victory unlocked Auto", failures)

	_expect(bool(game.open_facility("loadout").get("ok", false)), "game root: rewarded loadout did not open", failures)
	var rewarded_loadout: Dictionary = game.current_screen.get("_facility_data")
	var salvage_previews: Dictionary = rewarded_loadout.get("salvage_previews", {})
	var salvage_id := ""
	for raw_item in (rewarded_loadout.get("inventory_equipment", []) as Array):
		if raw_item is Dictionary and String((raw_item as Dictionary).get("source", {}).get("type", "")) == "campaign_drop":
			var candidate_id := String((raw_item as Dictionary).get("instance_id", ""))
			if salvage_previews.has(candidate_id):
				salvage_id = candidate_id
				break
	_expect(not salvage_id.is_empty(), "game root: campaign drops produced no authoritative salvage previews", failures)
	if not salvage_id.is_empty():
		var salvage_preview: Dictionary = salvage_previews[salvage_id]
		var salvage_operation := String(salvage_preview.get("operation", ""))
		var inventory_before := (game.application_state.profile.inventory.equipment as Array).size()
		var tallies_before := int((game.application_state.profile.resources.law_tallies as Dictionary).get(salvage_operation, 0))
		var salvaged: Dictionary = game.request_facility_action("loadout", "salvage_item", {"instance_id": salvage_id})
		_expect(bool(salvaged.get("ok", false))
			and (game.application_state.profile.inventory.equipment as Array).size() == inventory_before - 1
			and int((game.application_state.profile.resources.law_tallies as Dictionary).get(salvage_operation, 0)) == tallies_before + 1,
			"game root: confirmed salvage did not remove one campaign drop and refund its Law Tally", failures)
		var refreshed_loadout: Dictionary = game.current_screen.get("_facility_data")
		_expect(not (refreshed_loadout.get("salvage_previews", {}) as Dictionary).has(salvage_id)
			and String(game.request_facility_action("loadout", "salvage_item", {"instance_id": salvage_id}).get("error", "")) == "item_not_owned",
			"game root: salvaged item remained actionable or could be salvaged twice", failures)
	_expect(bool(game.leave_facility().get("ok", false)), "game root: rewarded loadout did not return to base", failures)

	_expect(bool(game.open_contract().get("ok", false)), "game root: could not open threshold colossus contract", failures)
	var boss_config := {"contract_id": "threshold_colossus", "mode": "Manual", "preset_id": "convergent", "seed": 311, "room_count": 1}
	_expect(bool(game.launch_contract(boss_config).get("ok", false)), "game root: threshold colossus contract did not launch", failures)
	var boss_arena := game.current_screen as FakeArena
	_expect(boss_arena != null and String((((boss_arena.config.room_plan as Dictionary).rooms as Array)[0] as Dictionary).boss_id) == "threshold_colossus", "game root: threshold colossus RoomPlan lost the Boss id", failures)
	if boss_arena != null:
		boss_arena.resolve({"outcome": "victory", "rewards": {"contract_wins_delta": 1}})
	_expect(game.current_route == "result" and game.application_state.is_auto_mode_unlocked(), "game root: threshold colossus first victory did not unlock Auto", failures)
	_destroy_game(game)


	game = _create_game()
	var boss_restored_early: Dictionary = game.application_state.early_game_snapshot()
	var boss_restored_proxy: Dictionary = (boss_restored_early.get("proxy", {}) as Dictionary).get("build", {})
	_expect(game.current_route == "base", "game root: Boss Result restart did not recover the persisted safe route", failures)
	_expect(game.application_state.is_auto_mode_unlocked(), "game root: Boss Result restart lost Auto unlock", failures)
	_expect((boss_restored_proxy.get("cores", []) as Array) == ["near_enemy_horizon", "direct_gait", "single_key_execution", "short_trace_memory"], "game root: Boss Result restart lost the fixed four white cores", failures)
	_expect(not bool((boss_restored_early.get("progression", {}) as Dictionary).get("early_game_complete", false)), "game root: Boss Result restart prematurely restored early-game completion", failures)

	game.open_contract()
	var auto_config := {"contract_id": "auto_certification", "mode": "Auto", "preset_id": "convergent", "seed": 7, "room_count": 1}
	_expect(bool(game.launch_contract(auto_config).get("ok", false)), "game root: unlocked Auto certification did not launch", failures)
	var auto_arena := game.current_screen as FakeArena
	_expect(auto_arena != null and auto_arena.config.preset_id == "exponential", "game root: Auto caller overrode active Build", failures)
	_expect(auto_arena != null
		and String((((auto_arena.config.framework_context as Dictionary).resolved_proxy_build as Dictionary).cores[0] as Dictionary).core_id) == "near_enemy_horizon",
		"game root: unlocked resolved proxy Build was not injected", failures)
	if auto_arena != null:
		var frozen_proxy: Dictionary = (auto_arena.config.framework_context as Dictionary).resolved_proxy_build
		(frozen_proxy.cores[0] as Dictionary)["core_id"] = "tampered"
		var profile_proxy: Dictionary = game.application_state.resolved_proxy_build_snapshot()
		_expect(bool(profile_proxy.get("ok", false))
			and String(profile_proxy.resolved_proxy_build.cores[0].core_id) == "near_enemy_horizon",
			"game root: frozen resolved proxy Build leaked back into profile state", failures)
	if auto_arena != null:
		auto_arena.resolve({"outcome": "victory", "rewards": {"contract_wins_delta": 1, "law_tallies_delta": {"inscribe": 1, "rewrite": 0, "refine": 0}}})
	_expect(game.current_route == "result", "game root: Auto result did not reach result route", failures)
	_expect(bool(game.application_state.profile.progression.early_game_complete) and "auto_certification" in (game.application_state.profile.progression.completed_node_ids as Array), "game root: Auto certification did not settle early-game completion", failures)
	_expect(String(game.application_state.last_result.get("outcome", "")) == "final_victory", "game root: Auto graduation was not normalized to final_victory", failures)
	_expect(bool(game.open_ending().get("ok", false)) and game.current_route == "ending", "game root: final Auto victory did not open the ending", failures)
	_destroy_game(game)
	game = _create_game()
	var auto_restored_early: Dictionary = game.application_state.early_game_snapshot()
	_expect(game.current_route == "base", "game root: Auto Result restart did not recover the persisted safe route", failures)
	_expect(bool((auto_restored_early.get("progression", {}) as Dictionary).get("early_game_complete", false)), "game root: Auto Result restart lost early-game completion", failures)
	_expect("auto_certification" in ((auto_restored_early.get("progression", {}) as Dictionary).get("completed_node_ids", []) as Array), "game root: Auto Result restart lost Auto certification completion", failures)

	_expect(bool(game.open_facility("forge").get("ok", false)), "game root: rewarded profile could not open forge", failures)
	var forge_before: Dictionary = game.application_state.forge_snapshot()
	var forge_target_id := String(forge_before.target_instance_id)
	var forge_target_name := String((forge_before.target_item as Dictionary).get("base_name", ""))
	var presented_forge: Dictionary = game.current_screen.get("_facility_data")
	var forge_mirror_properties: Array[String] = []
	for property in game.get_property_list():
		if String((property as Dictionary).get("name", "")) in ["_forge_affix_index", "_forge_target_instance_id"]:
			forge_mirror_properties.append(String((property as Dictionary).get("name", "")))
	_expect(forge_mirror_properties.is_empty() and String(presented_forge.get("operation", "")) == "inscribe"
		and not presented_forge.has("affix_index") and not (presented_forge.get("context", {}) as Dictionary).has("affix_index"),
		"game root: forge context retained mirrored selected-affix state", failures)
	var operation_selected: Dictionary = game.request_facility_action("forge", "select_forge_operation", {"operation": "rewrite"})
	presented_forge = game.current_screen.get("_facility_data")
	_expect(bool(operation_selected.get("ok", false)) and String(presented_forge.operation) == "rewrite"
		and not presented_forge.has("affix_index") and not (presented_forge.get("context", {}) as Dictionary).has("affix_index"),
		"game root: operation intent was not presented without selected-affix state", failures)
	game.request_facility_action("forge", "select_forge_operation", {"operation": "inscribe"})
	var target_selected: Dictionary = game.request_facility_action("forge", "select_forge_item", {"instance_id": forge_target_id})
	_expect(bool(target_selected.get("ok", false)) and String((game.current_screen.get("_facility_data") as Dictionary).target_instance_id) == forge_target_id,
		"game root: target intent did not round-trip through ApplicationState", failures)
	var premature_commit: Dictionary = game.request_facility_action("forge", "forge_commit", {})
	var forge_status := String(game.current_screen.get("_status_message"))
	_expect(String(premature_commit.get("error", "")) == "candidate_not_selected",
		"game root: forge refusal lost its stable machine code: %s" % str(premature_commit), failures)
	_expect(forge_status.contains("Select") and not forge_status.contains("candidate_not_selected"),
		"game root: forge refusal was not player-readable: %s" % forge_status, failures)
	var revealed: Dictionary = game.request_facility_action("forge", "forge_reveal", {})
	var revealed_candidates: Array = ((revealed.get("session", {}) as Dictionary).get("candidates", []) as Array)
	var revealed_candidate: Dictionary = revealed_candidates[0] if not revealed_candidates.is_empty() else {}
	_expect(bool(revealed.get("ok", false)) and revealed_candidate.has("affected_affix_index")
		and not revealed_candidate.has("affix_index") and not (revealed.get("context", {}) as Dictionary).has("affix_index"),
		"game root: synchronized forge reveal failed or exposed affix_index: %s" % str(revealed), failures)
	var forged: Dictionary = revealed
	if bool(revealed.get("ok", false)):
		var forge_session_id := String(revealed.session.session_id)
		var candidate_id := String(revealed.session.candidates[0].candidate_id)
		game.request_facility_action("forge", "forge_select_candidate", {"session_id": forge_session_id, "candidate_id": candidate_id})
		var before_failed_save: Dictionary = game.application_state.profile
		var real_save_store = game.save_store
		game.save_store = FailingSaveStore.new()
		var failed_commit: Dictionary = game.request_facility_action("forge", "forge_commit", {"session_id": forge_session_id})
		forge_status = String(game.current_screen.get("_status_message"))
		_expect(String(failed_commit.get("error", "")) == "save_failed",
			"game root: failed forge save lost its stable machine code: %s" % str(failed_commit), failures)
		_expect(game.application_state.profile == before_failed_save,
			"game root: failed forge save changed the committed profile", failures)
		var retry_snapshot: Dictionary = game.application_state.forge_snapshot()
		_expect(String((retry_snapshot.get("session", {}) as Dictionary).get("state", "")) == "selected",
			"game root: failed forge save lost retry state: %s" % str(retry_snapshot.get("session", {})), failures)
		_expect(forge_status.contains("Equipment and Law Tokens are unchanged") and not forge_status.contains("injected_save_failure"),
			"game root: failed forge save leaked an internal error: %s" % forge_status, failures)
		game.save_store = real_save_store
		forged = game.request_facility_action("forge", "forge_commit", {"session_id": forge_session_id})
	_expect(bool(forged.get("ok", false)), "game root: forge candidate did not commit", failures)
	forge_status = String(game.current_screen.get("_status_message"))
	_expect(forge_status.contains("Forged:") and not forge_target_name.is_empty() and forge_status.contains(forge_target_name),
		"game root: forge success did not show a readable completion: %s" % forge_status, failures)
	_expect(forge_target_id.is_empty() or not forge_status.contains(forge_target_id),
		"game root: forge success leaked inventory instance id %s in: %s" % [forge_target_id, forge_status], failures)
	var forge_snapshot: Dictionary = game.application_state.forge_snapshot()
	_expect(not ((forge_snapshot.affixes as Array)[0] as Dictionary).is_empty(), "game root: committed forge affix was not retained", failures)
	var forged_fingerprint := String(game.application_state.resolved_build_snapshot().build_fingerprint)
	_expect(bool(game.leave_facility().get("ok", false)) and game.current_route == "base", "game root: forge did not return to base", failures)
	_destroy_game(game)

	var resumed = _create_game()
	_expect(resumed.current_route == "base", "game root: persisted safe route did not resume at base", failures)
	_expect(String(resumed.application_state.last_result.get("outcome", "")) == "final_victory", "game root: persisted final result was not restored", failures)
	var resumed_early: Dictionary = resumed.application_state.early_game_snapshot()
	_expect(String((resumed_early.active_build as Dictionary).preset_id) == "exponential", "game root: active Build did not survive restart", failures)
	var resumed_resolved: Dictionary = resumed.application_state.resolved_build_snapshot()
	_expect(String(resumed_resolved.get("build_fingerprint", "")) == forged_fingerprint
		and not ((resumed_early.training as Dictionary).reports_by_fingerprint as Dictionary).has(forged_fingerprint),
		"game root: forged Build fingerprint persistence or verification invalidation is wrong", failures)
	_expect(bool((resumed_early.proxy as Dictionary).unlocked) and bool((resumed_early.progression as Dictionary).early_game_complete), "game root: early-game completion did not survive restart", failures)
	var resumed_forge: Dictionary = resumed.application_state.forge_snapshot()
	_expect(not ((resumed_forge.affixes as Array)[0] as Dictionary).is_empty(), "game root: forge state did not survive restart", failures)
	_expect(bool(resumed.return_to_title().get("ok", false)) and resumed.current_route == "title", "game root: base did not return to title", failures)
	_expect(bool(resumed.continue_game().get("ok", false)) and resumed.current_route == "base", "game root: continue did not restore the loaded profile", failures)
	_expect(not bool(resumed.launch_contract(config).get("ok", false)), "game root: action from wrong route was accepted", failures)
	_destroy_game(resumed)


func _test_proxy_player_flow(failures: Array[String]) -> void:
	var game = _create_game()
	game.start_new_game("ranger")
	game.complete_tutorial()
	var manual_nodes: Array[String] = [
		"mainline_01_first_hunt",
		"mainline_02_priority_under_pressure",
		"mainline_03_first_elite",
		"mainline_04_hazard_and_forge",
		"mainline_05_growth_gate",
		"threshold_colossus",
	]
	for index in manual_nodes.size():
		var node_id := manual_nodes[index]
		_expect(bool(game.open_contract().get("ok", false)),
			"proxy player flow: could not open contract board for %s" % node_id, failures)
		var launched: Dictionary = game.launch_contract({
			"contract_id": node_id,
			"mode": "Manual",
			"seed": 8100 + index,
			"room_count": 1,
		})
		_expect(bool(launched.get("ok", false)),
			"proxy player flow: prerequisite %s did not launch" % node_id, failures)
		var arena := game.current_screen as FakeArena
		if arena != null:
			arena.resolve({"outcome": "victory", "rewards": {"contract_wins_delta": 1}})
		_expect(game.current_route == "result",
			"proxy player flow: prerequisite %s did not settle" % node_id, failures)
		_expect(bool(game.leave_result().get("ok", false)),
			"proxy player flow: prerequisite %s result could not return to base" % node_id, failures)

	var initial_raw: Dictionary = game.application_state.profile.proxy_build.duplicate(true)
	var initial_resolved: Dictionary = game.application_state.resolved_proxy_build_snapshot().resolved_proxy_build
	_expect(initial_raw == {
		"cores": ["near_enemy_horizon", "direct_gait", "single_key_execution", "short_trace_memory"],
		"settings": {},
		"attachments": ["", "", ""],
	}, "proxy player flow: Boss unlock did not install the fixed four-core build", failures)

	game.open_contract()
	var certification: Dictionary = game.launch_contract({
		"contract_id": "auto_certification",
		"mode": "Auto",
		"seed": 8201,
		"room_count": 1,
	})
	_expect(bool(certification.get("ok", false)), "proxy player flow: Auto certification did not launch", failures)
	var certification_arena := game.current_screen as FakeArena
	if certification_arena != null:
		var frozen: Dictionary = certification_arena.config.framework_context.resolved_proxy_build
		_expect(String((frozen.cores[0] as Dictionary).core_id) == "near_enemy_horizon"
			and String((frozen.cores[1] as Dictionary).core_id) == "direct_gait",
			"proxy player flow: certification did not freeze the initial resolved build", failures)
		certification_arena.resolve({"outcome": "victory", "rewards": {"contract_wins_delta": 1}})
	var first_result: Dictionary = game.application_state.last_result
	var first_drops: Array = first_result.get("proxy_component_drops", [])
	_expect(game.current_route == "result" and first_drops.size() == 1
		and String((first_drops[0] as Dictionary).get("id", "")) == "marking_prism"
		and game.application_state.profile.proxy_build == initial_raw,
		"proxy player flow: first Auto win did not grant marking as inventory-only", failures)
	game.current_screen.call("_build_ui")
	game.current_screen.call("_apply_presentation")
	var first_cards: Array = game.current_screen.call("get_proxy_component_card_texts")
	_expect(first_cards.size() == 1 and String(first_cards[0]).contains("Mark Prism")
		and String(first_cards[0]).contains("Not installed; current proxy build unchanged"),
		"proxy player flow: marking settlement was not presented as uninstalled inventory", failures)
	game.leave_result()

	game.open_facility("proxy")
	var proxy_before: Dictionary = game.current_screen.get("_facility_data")
	var catalog_before: Dictionary = (proxy_before.proxy as Dictionary).catalog
	_expect(catalog_before.has("marking_prism")
		and String((catalog_before.marking_prism as Dictionary).name) == "Mark Prism",
		"proxy player flow: player-readable keyed core catalog did not reach the facility", failures)
	var marking: Dictionary = game.request_facility_action("proxy", "equip_proxy_core", {"core_id": "marking_prism"})
	_expect(bool(marking.get("ok", false))
		and String(game.application_state.profile.proxy_build.cores[0]) == "marking_prism"
		and String(marking.resolved_proxy_build.semantic_fingerprint) != String(initial_resolved.semantic_fingerprint)
		and String(game.current_screen.get("_status_message")).contains("Mark Prism"),
		"proxy player flow: marking core could not be installed through the facility", failures)
	game.leave_facility()

	game.open_contract()
	var first_side: Dictionary = game.launch_contract({
		"contract_id": "side_targeted_equipment",
		"mode": "Auto",
		"seed": 8202,
		"room_count": 1,
	})
	_expect(bool(first_side.get("ok", false)),
		"proxy player flow: repeatable side contract did not accept unlocked Auto", failures)
	var first_side_arena := game.current_screen as FakeArena
	if first_side_arena != null:
		var frozen_marking: Dictionary = first_side_arena.config.framework_context.resolved_proxy_build
		_expect(String((frozen_marking.cores[0] as Dictionary).core_id) == "marking_prism",
			"proxy player flow: installed marking core was not frozen into the next contract", failures)
		first_side_arena.resolve({"outcome": "victory", "rewards": {"contract_wins_delta": 1}})
	var second_result: Dictionary = game.application_state.last_result
	var second_drops: Array = second_result.get("proxy_component_drops", [])
	_expect(second_drops.size() == 1
		and String((second_drops[0] as Dictionary).get("id", "")) == "distance_keeping_gait"
		and String(game.application_state.profile.proxy_build.cores[1]) == "direct_gait",
		"proxy player flow: second Auto win did not grant distance gait without auto-installing it", failures)
	game.leave_result()

	game.open_facility("proxy")
	var distance: Dictionary = game.request_facility_action("proxy", "equip_proxy_core", {"core_id": "distance_keeping_gait"})
	var mid_fingerprint := String((distance.get("resolved_proxy_build", {}) as Dictionary).get("semantic_fingerprint", ""))
	var configured: Dictionary = game.request_facility_action("proxy", "configure_proxy_core", {
		"core_id": "distance_keeping_gait",
		"settings": {"distance_band": "far"},
	})
	var far_resolved: Dictionary = configured.get("resolved_proxy_build", {})
	_expect(bool(distance.get("ok", false)) and bool(configured.get("ok", false))
		and String(game.application_state.profile.proxy_build.cores[1]) == "distance_keeping_gait"
		and String(game.application_state.profile.proxy_build.settings.distance_keeping_gait.distance_band) == "far"
		and not mid_fingerprint.is_empty()
		and String(far_resolved.get("semantic_fingerprint", "")) != mid_fingerprint,
		"proxy player flow: distance gait installation or far-band configuration did not persist semantically", failures)
	game.leave_facility()

	game.open_contract()
	var second_side: Dictionary = game.launch_contract({
		"contract_id": "side_targeted_equipment",
		"mode": "Auto",
		"seed": 8203,
		"room_count": 1,
	})
	_expect(bool(second_side.get("ok", false)),
		"proxy player flow: configured repeatable Auto contract did not launch", failures)
	var second_side_arena := game.current_screen as FakeArena
	if second_side_arena != null:
		var frozen_far: Dictionary = second_side_arena.config.framework_context.resolved_proxy_build
		_expect(String((frozen_far.cores[0] as Dictionary).core_id) == "marking_prism"
			and String((frozen_far.cores[1] as Dictionary).core_id) == "distance_keeping_gait"
			and String((frozen_far.cores[1] as Dictionary).settings.distance_band) == "far",
			"proxy player flow: configured build was not frozen into the next contract", failures)
		second_side_arena.resolve({"outcome": "victory", "rewards": {"contract_wins_delta": 1}})
	var third_result: Dictionary = game.application_state.last_result
	_expect((third_result.get("proxy_component_drops", []) as Array).is_empty()
		and int(game.application_state.profile.progression.auto_contract_wins) == 3
		and game.application_state.profile.inventory.proxy_components.size() == 6,
		"proxy player flow: third Auto win duplicated a finite component reward", failures)
	_destroy_game(game)


func _test_result_drop_review_route(failures: Array[String]) -> void:
	var game = _create_game()
	game.start_new_game("ranger")
	game.complete_tutorial()
	game.open_contract()
	var launched: Dictionary = game.launch_contract({
		"contract_id": "mainline_01_first_hunt",
		"mode": "Manual",
		"seed": 9127,
		"room_count": 1,
	})
	_expect(bool(launched.get("ok", false)), "game root review: setup contract did not launch", failures)
	var arena := game.current_screen as FakeArena
	if arena != null:
		arena.resolve({"outcome": "victory", "rewards": {}})
	_expect(game.current_route == "result", "game root review: setup did not reach result", failures)

	var review_item := {
		"instance_id": "review:drop/1",
		"base_item_id": "turnfeather_gloves",
		"slot": "gloves",
		"affixes": [{"family_id": "maximum_health", "tier": 2}],
		"rune_id": "",
		"law_id": "",
	}
	(game.application_state._profile.inventory.equipment as Array).append(review_item.duplicate(true))
	var equipped_before: Dictionary = (game.application_state.active_build_snapshot().active_build.equipped_item_ids as Dictionary).duplicate(true)
	var refused: Dictionary = game.review_result_drop("missing:drop", "gloves")
	_expect(String(refused.get("error", "")) == "item_not_owned" and game.current_route == "result",
		"game root review: an unowned result id changed route", failures)
	var stale_owned: Dictionary = game.review_result_drop("review:drop/1", "gloves")
	_expect(String(stale_owned.get("error", "")) == "drop_not_in_result" and game.current_route == "result",
		"game root review: an owned item absent from this settlement was accepted as its drop", failures)
	var last_result: Dictionary = game.application_state._last_result
	var last_rewards: Dictionary = last_result.get("rewards", {}) if last_result.get("rewards", {}) is Dictionary else {}
	last_rewards["equipment_drops"] = [review_item.duplicate(true)]
	last_rewards["equipment_drop_count"] = 1
	last_result["rewards"] = last_rewards
	game.application_state._last_result = last_result
	var reviewed: Dictionary = game.review_result_drop("review:drop/1", "gloves")
	_expect(bool(reviewed.get("ok", false)) and game.current_route == "loadout",
		"game root review: owned drop did not open loadout", failures)
	if game.current_route == "loadout" and game.current_screen != null:
		var facility_data: Dictionary = game.current_screen.get("_facility_data")
		var review_context: Dictionary = facility_data.get("initial_focus", {}) if facility_data.get("initial_focus", {}) is Dictionary else {}
		var focused_slot := String(game.current_screen.get("_focus_slot"))
		_expect(review_context == {"review_instance_id": "review:drop/1", "focus_slot": "gloves", "return_route": "result"}
			and focused_slot == "gloves",
			"game root review: loadout did not carry the exact settled candidate context=%s focus=%s" % [str(review_context), focused_slot], failures)
	_expect((game.application_state.active_build_snapshot().active_build.equipped_item_ids as Dictionary) == equipped_before,
		"game root review: opening comparison equipped or unequipped an item", failures)
	game._on_facility_back_requested("result")
	_expect(game.current_route == "result", "game root review: comparison could not return to the settlement decision", failures)
	game.review_result_drop("review:drop/1", "gloves")
	_expect(game.current_route == "loadout" and String(game.current_screen.get("_focus_slot")) == "gloves",
		"game root review: returning to the same settled drop lost its exact loadout target", failures)
	_destroy_game(game)


func _test_defeat_and_victory_reason_output(failures: Array[String]) -> void:
	var logger := FakePlaytestLog.new()
	var game = _create_game()
	game.playtest_log = logger
	game.playtest_logging_enabled = true
	logger.start_session({})
	_expect(bool(game.start_new_game("ranger").get("ok", false)) and bool(game.complete_tutorial().get("ok", false)),
		"game root defeat: profile setup failed", failures)
	_expect(bool(game.open_contract().get("ok", false)), "game root defeat: contract board did not open", failures)
	var defeat_config := {"contract_id": "mainline_01_first_hunt", "mode": "Manual", "seed": 5150, "room_count": 1}
	_expect(bool(game.launch_contract(defeat_config).get("ok", false)), "game root defeat: contract did not launch", failures)
	var defeat_room_result := {"room_id": "room.source", "outcome": "defeat", "failure_reason": "enemy/fan_ranged"}
	var defeat_arena := game.current_screen as FakeArena
	if defeat_arena != null:
		defeat_arena.resolve({"outcome": "defeat", "failure_reason": "enemy/fan_ranged", "room_results": [defeat_room_result]})
		defeat_room_result["failure_reason"] = "caller.mutated"
	var defeat_event := _first_log_event(logger.events, "contract_finished")
	var defeat_payload: Dictionary = defeat_event.get("payload", {}) if defeat_event.get("payload", {}) is Dictionary else {}
	_expect(String(defeat_payload.get("failure_reason", "")) == "enemy/fan_ranged",
		"game root defeat: top-level failure reason was not retained", failures)
	_expect(String(((defeat_payload.get("rooms", []) as Array)[0] as Dictionary).get("failure_reason", "")) == "enemy/fan_ranged",
		"game root defeat: per-room failure reason was lost or aliased", failures)
	_expect(bool(game.leave_result().get("ok", false)), "game root defeat: result route did not close", failures)

	_expect(bool(game.open_contract().get("ok", false)), "game root victory: retry contract board did not open", failures)
	var victory_config := {"contract_id": "mainline_01_first_hunt", "mode": "Manual", "seed": 5151, "room_count": 1}
	_expect(bool(game.launch_contract(victory_config).get("ok", false)), "game root victory: retry contract did not launch", failures)
	var victory_arena := game.current_screen as FakeArena
	if victory_arena != null:
		victory_arena.resolve({"outcome": "victory", "room_results": [{"room_id": "room.source", "outcome": "victory"}]})
	var events := _log_events(logger.events, "contract_finished")
	_expect(events.size() == 2 and not (events[1].get("payload", {}) as Dictionary).has("failure_reason"),
		"game root victory: victory fabricated a failure reason", failures)
	_destroy_game(game)


func _test_playtest_event_wiring(failures: Array[String]) -> void:
	var logger := FakePlaytestLog.new()
	var game = GameRootScript.new()
	game.save_directory_path = TEST_DIRECTORY
	game.room_runtime_factory = Callable(self, "_make_fake_arena")
	game.playtest_log = logger
	game.playtest_logging_enabled = true
	game.initialize(PackedStringArray())
	_expect(bool(logger.active), "game root log: playtest session did not start", failures)
	_expect(bool(game.start_new_game("ranger").get("ok", false)), "game root log: profile setup failed", failures)
	_expect(bool(game.complete_tutorial().get("ok", false)), "game root log: tutorial setup failed", failures)
	_expect(bool(game.open_facility("loadout").get("ok", false)), "game root log: loadout did not open", failures)
	var selected_result: Dictionary = game.request_facility_action("loadout", "select_ranger_build", {"preset_id": "exponential"})
	_expect(bool(selected_result.get("ok", false)),
		"game root log: loadout action failed", failures)
	var unequip_result: Dictionary = game.request_facility_action("loadout", "unequip_item", {"slot": "main_hand"})
	var equip_result: Dictionary = game.request_facility_action("loadout", "equip_item", {"instance_id": "calibration_exponential_main_hand"})
	_expect(bool(unequip_result.get("ok", false)) and bool(equip_result.get("ok", false)),
		"game root log: real equipment tradeoff setup failed", failures)
	selected_result["active_build"] = {"tampered": true}
	selected_result["resolved_build"] = {"tampered": true}
	unequip_result["active_build"] = {"tampered": true}
	equip_result["resolved_build"] = {"tampered": true}
	_expect(String(game.application_state.active_build_snapshot().active_build.preset_id) == "exponential"
		and String(game.application_state.resolved_build_snapshot().build_fingerprint).length() == 64,
		"game root log: loadout action return values aliased application state", failures)
	_expect(bool(game.leave_facility().get("ok", false)), "game root log: loadout did not close", failures)
	_expect(bool(game.open_facility("training").get("ok", false)), "game root log: training did not open", failures)
	var trial: Dictionary = game.request_facility_action("training", "run_training_trial")
	_expect(bool(trial.get("ok", false)), "game root log: training action failed", failures)
	_expect(bool(game.leave_facility().get("ok", false)), "game root log: training did not close", failures)
	_expect(bool(game.open_contract().get("ok", false)), "game root log: contract board did not open", failures)
	_expect(String(game.launch_contract({"contract_id": "auto_certification", "mode": "Auto", "seed": 7, "room_count": 1}).get("error", "")) == "proxy_locked",
		"game root log: locked Auto setup was not rejected", failures)
	var launch_config := {"contract_id": "mainline_01_first_hunt", "mode": "Manual", "seed": 8080, "room_count": 1}
	_expect(bool(game.launch_contract(launch_config).get("ok", false)), "game root log: contract did not launch", failures)
	launch_config["seed"] = -1
	var arena := game.current_screen as FakeArena
	if arena != null:
		arena.resolve({"outcome": "victory", "ticks": 123, "rooms_completed": 1, "casts": 7, "defeated": 4})
	_expect(game.current_route == "result", "game root log: contract did not settle", failures)

	var profile_event := _first_log_event(logger.events, "profile_started")
	var session_event := _first_log_event(logger.events, "session_started")
	var tutorial_event := _first_log_event(logger.events, "tutorial_completed")
	var loadout_event := _first_log_event(logger.events, "loadout_changed")
	var training_event := _first_log_event(logger.events, "training_completed")
	var started_event := _first_log_event(logger.events, "contract_started")
	var finished_event := _first_log_event(logger.events, "contract_finished")
	var auto_rejected_event := _first_log_event(logger.events, "auto_rejected")
	var route_event := _first_log_event(logger.events, "route_changed")
	var content_versions: Dictionary = (session_event.get("context", {}) as Dictionary).get("content_versions", {})
	_expect(content_versions == {"early_campaign": 1, "early_items": 1},
		"game root log: session context lost content versions", failures)
	_expect(String((profile_event.get("payload", {}) as Dictionary).get("initial_class", "")) == "ranger",
		"game root log: profile event is missing its class", failures)
	_expect(not tutorial_event.is_empty(), "game root log: tutorial completion was not recorded", failures)
	_expect(String((loadout_event.get("payload", {}) as Dictionary).get("build_fingerprint", "")).length() == 64,
		"game root log: loadout event lost the resolved fingerprint", failures)
	var loadout_events := _log_events(logger.events, "loadout_changed")
	_expect(loadout_events.size() == 3, "game root log: real equipment tradeoffs were not recorded", failures)
	if loadout_events.size() == 3:
		var calibration_fingerprint := String((loadout_events[0].get("payload", {}) as Dictionary).get("build_fingerprint", ""))
		var unequip_payload: Dictionary = loadout_events[1].get("payload", {}) if loadout_events[1].get("payload", {}) is Dictionary else {}
		var equip_payload: Dictionary = loadout_events[2].get("payload", {}) if loadout_events[2].get("payload", {}) is Dictionary else {}
		_expect(String(unequip_payload.get("action", "")) == "unequip_item" and String(unequip_payload.get("slot", "")) == "main_hand"
			and String(unequip_payload.get("previous_instance_id", "")) == "calibration_exponential_main_hand"
			and String(unequip_payload.get("next_instance_id", "")) == "",
			"game root log: unequip before/after state was not authoritative", failures)
		_expect(String(equip_payload.get("action", "")) == "equip_item" and String(equip_payload.get("slot", "")) == "main_hand"
			and String(equip_payload.get("previous_instance_id", "")) == ""
			and String(equip_payload.get("next_instance_id", "")) == "calibration_exponential_main_hand",
			"game root log: equip before/after state was not authoritative", failures)
		_expect(String(unequip_payload.get("previous_build_fingerprint", "")) == calibration_fingerprint
			and String(unequip_payload.get("new_build_fingerprint", "")) != calibration_fingerprint
			and String(equip_payload.get("previous_build_fingerprint", "")) == String(unequip_payload.get("new_build_fingerprint", ""))
			and String(equip_payload.get("new_build_fingerprint", "")) == calibration_fingerprint,
			"game root log: equipment fingerprints did not bracket the authoritative API calls", failures)
		_expect(not String(unequip_payload.get("growth_before", "")).is_empty() and not String(unequip_payload.get("growth_after", "")).is_empty()
			and (unequip_payload.get("interfaces_gained", null) is Array) and (unequip_payload.get("interfaces_lost", null) is Array)
			and (unequip_payload.get("parameter_deltas", null) is Dictionary),
			"game root log: equipment tradeoff telemetry lost growth/interface diagnostics", failures)
		var parameter_deltas: Dictionary = unequip_payload.get("parameter_deltas", {}) if unequip_payload.get("parameter_deltas", {}) is Dictionary else {}
		var has_limited_parameters := not parameter_deltas.is_empty()
		for parameter_key in ["p", "T", "v", "d", "turn", "damage", "max_health"]:
			has_limited_parameters = has_limited_parameters and parameter_deltas.has(parameter_key)
		_expect(has_limited_parameters and not unequip_payload.has("equipped") and not unequip_payload.has("inventory"),
			"game root log: equipment telemetry did not use finite parameter deltas without full inventory", failures)
	_expect(String((training_event.get("payload", {}) as Dictionary).get("build_fingerprint", "")).length() == 64,
		"game root log: training event lost the verified fingerprint", failures)
	_expect(float((training_event.get("payload", {}) as Dictionary).get("p", 0.0)) > 0.0
		and float((training_event.get("payload", {}) as Dictionary).get("R", 0.0)) > 0.0
		and int((training_event.get("payload", {}) as Dictionary).get("training_seed", -1)) >= 0
		and (training_event.get("payload", {}) as Dictionary).get("growth_curve", null) is Array
		and not String((training_event.get("payload", {}) as Dictionary).get("action", "")).is_empty()
		and (training_event.get("payload", {}) as Dictionary).get("missing_interfaces", null) is Array,
		"game root log: training event lost reproducibility or growth diagnostics", failures)
	_expect(String((auto_rejected_event.get("payload", {}) as Dictionary).get("reason", "")) == "proxy_locked",
		"game root log: locked Auto rejection was not recorded", failures)
	_expect(int((started_event.get("payload", {}) as Dictionary).get("seed", 0)) == 8080
		and String((started_event.get("payload", {}) as Dictionary).get("contract_id", "")) == "mainline_01_first_hunt",
		"game root log: contract start was missing frozen identity", failures)
	_expect(String((finished_event.get("payload", {}) as Dictionary).get("outcome", "")) == "victory"
		and int((finished_event.get("payload", {}) as Dictionary).get("ticks", 0)) == 123,
		"game root log: contract finish was missing the authoritative result", failures)
	_expect(not route_event.is_empty()
		and int((route_event.get("payload", {}) as Dictionary).get("previous_dwell_msec", -1)) >= 0
		and int((route_event.get("payload", {}) as Dictionary).get("session_elapsed_msec", -1)) >= 0,
		"game root log: route transitions or duration fields were not recorded", failures)
	_destroy_game(game)
	_expect(not logger.active and not _first_log_event(logger.events, "session_finished").is_empty(),
		"game root log: playtest session did not close with the tree", failures)


func _test_presentation_flag_wiring(failures: Array[String]) -> void:
	var off_game = GameRootScript.new()
	off_game.save_directory_path = TEST_DIRECTORY
	off_game.room_runtime_factory = Callable(self, "_make_fake_arena")
	off_game.playtest_logging_enabled = false
	off_game.initialize(PackedStringArray(["--presentation-off"]))
	_expect(bool(off_game.start_new_game("ranger").get("ok", false)), "game root presentation: profile setup failed", failures)
	_expect(bool(off_game.complete_tutorial().get("ok", false)), "game root presentation: tutorial setup failed", failures)
	_expect(bool(off_game.open_contract().get("ok", false)), "game root presentation: contract board did not open", failures)
	# The caller tries to bypass the CLI flag; launch_contract must force it off.
	var off_config := {"contract_id": "mainline_01_first_hunt", "mode": "Manual", "preset_id": "convergent", "seed": 41, "room_count": 1, "presentation_enabled": true}
	_expect(bool(off_game.launch_contract(off_config).get("ok", false)), "game root presentation: contract did not launch", failures)
	var off_arena := off_game.current_screen as FakeArena
	_expect(off_arena != null and bool(off_arena.config.get("presentation_enabled", true)) == false, "game root presentation: --presentation-off did not force config.presentation_enabled=false", failures)
	_destroy_game(off_game)

	_cleanup_test_directory()
	var on_game = GameRootScript.new()
	on_game.save_directory_path = TEST_DIRECTORY
	on_game.room_runtime_factory = Callable(self, "_make_fake_arena")
	on_game.playtest_logging_enabled = false
	on_game.initialize(PackedStringArray())
	_expect(bool(on_game.start_new_game("ranger").get("ok", false)), "game root presentation: default profile setup failed", failures)
	_expect(bool(on_game.complete_tutorial().get("ok", false)), "game root presentation: default tutorial setup failed", failures)
	_expect(bool(on_game.open_contract().get("ok", false)), "game root presentation: default contract board did not open", failures)
	var on_config := {"contract_id": "mainline_01_first_hunt", "mode": "Manual", "preset_id": "convergent", "seed": 41, "room_count": 1}
	_expect(bool(on_game.launch_contract(on_config).get("ok", false)), "game root presentation: default contract did not launch", failures)
	var on_arena := on_game.current_screen as FakeArena
	_expect(on_arena != null and bool(on_arena.config.get("presentation_enabled", false)) == true, "game root presentation: default run lost presentation_enabled=true", failures)
	_destroy_game(on_game)


func _first_log_event(events: Array[Dictionary], event_id: String) -> Dictionary:
	for event in events:
		if String(event.get("event_id", "")) == event_id:
			return event.duplicate(true)
	return {}


func _log_events(events: Array[Dictionary], event_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for event in events:
		if String(event.get("event_id", "")) == event_id:
			result.append(event.duplicate(true))
	return result


func _create_game():
	var game = GameRootScript.new()
	game.save_directory_path = TEST_DIRECTORY
	game.room_runtime_factory = Callable(self, "_make_fake_arena")
	game.playtest_logging_enabled = false
	game.initialize(PackedStringArray())
	return game


func _destroy_game(game: Node) -> void:
	game.free()


func _make_fake_arena() -> Node:
	return FakeArena.new()


func _selected_contract_id(picker: OptionButton) -> String:
	if picker == null or picker.selected < 0:
		return ""
	var metadata: Variant = picker.get_item_metadata(picker.selected)
	return String((metadata as Dictionary).get("id", "")) if metadata is Dictionary else ""


func _cleanup_test_directory() -> void:
	var absolute_directory: String = ProjectSettings.globalize_path(TEST_DIRECTORY)
	for file_name in ["save_a.json", "save_b.json", "save_a.json.tmp", "save_b.json.tmp"]:
		var path: String = absolute_directory.path_join(file_name)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	if DirAccess.dir_exists_absolute(absolute_directory):
		DirAccess.remove_absolute(absolute_directory)


func _expect(condition: bool, message: String, failures: Array[String]) -> void: Assert.expect(condition, message, failures)


## The capture harness is a contract, not a convenience: an unsupported or
## unreachable request has to fail loudly instead of saving a frame that would be
## read as evidence for a screen nobody reached.
func _test_capture_contract(failures: Array[String]) -> void:
	var probe = GameRootScript.new()
	probe.save_directory_path = TEST_DIRECTORY
	probe.playtest_logging_enabled = false
	var supported_capture := "/data/tmp/mib-capture-contract/shape.png"

	var route_request: Dictionary = probe.capture_request_report(PackedStringArray(["--capture-route=base", "--capture=" + supported_capture]))
	_expect(bool(route_request.get("ok", false)) and String(route_request.get("capture_route", "")) == "base" and String(route_request.get("capture_stage", "")).is_empty(),
		"game root capture: a supported route request was refused", failures)
	var boss_request: Dictionary = probe.capture_request_report(PackedStringArray(["--auto-smoke", "--capture-stage=boss", "--capture=" + supported_capture]))
	_expect(bool(boss_request.get("ok", false)) and String(boss_request.get("capture_stage", "")) == "boss",
		"game root capture: a valid Boss settlement request was refused", failures)
	_expect(bool(probe.capture_request_report(PackedStringArray(["--auto-smoke", "--capture-stage=auto", "--capture=" + supported_capture])).get("ok", false)),
		"game root capture: stage=auto was refused", failures)
	_expect(bool(probe.capture_request_report(PackedStringArray()).get("ok", false)),
		"game root capture: an ordinary command line was refused", failures)
	_expect(bool(probe.capture_request_report(PackedStringArray(["--capture=" + supported_capture, "--capture=" + supported_capture])).get("ok", false)),
		"game root capture: a repeated identical --capture was treated as a conflict", failures)

	## The defect this harness exists for: a settlement route is not preparable,
	## so it must never fall through to another screen and still report success.
	_expect(String(probe.capture_request_report(PackedStringArray(["--capture-route=result", "--capture=" + supported_capture])).get("error", "")) == "unsupported_capture_route",
		"game root capture: --capture-route=result was not rejected", failures)
	_expect(String(probe.capture_request_report(PackedStringArray(["--capture-route=banana", "--capture=" + supported_capture])).get("error", "")) == "unsupported_capture_route",
		"game root capture: an unknown route was not rejected", failures)
	_expect(String(probe.capture_request_report(PackedStringArray(["--auto-smoke", "--capture-stage=bogus", "--capture=" + supported_capture])).get("error", "")) == "unsupported_capture_stage",
		"game root capture: an unknown stage was not rejected", failures)
	_expect(String(probe.capture_request_report(PackedStringArray(["--capture-stage=boss", "--capture=" + supported_capture])).get("error", "")) == "capture_stage_requires_auto_smoke",
		"game root capture: --capture-stage without --auto-smoke was not rejected", failures)
	_expect(String(probe.capture_request_report(PackedStringArray(["--auto-smoke", "--capture-stage=boss"])).get("error", "")) == "capture_stage_requires_capture_path",
		"game root capture: --capture-stage without --capture was not rejected", failures)
	_expect(String(probe.capture_request_report(PackedStringArray(["--auto-smoke", "--capture-stage=boss", "--capture-route=base", "--capture=" + supported_capture])).get("error", "")) == "capture_route_conflict",
		"game root capture: --capture-stage and --capture-route were not treated as a conflict", failures)
	_expect(String(probe.capture_request_report(PackedStringArray(["--auto-smoke", "--capture-route=base", "--capture=" + supported_capture])).get("error", "")) == "auto_smoke_rejects_capture_route",
		"game root capture: --auto-smoke accepted --capture-route", failures)
	_expect(String(probe.capture_request_report(PackedStringArray(["--auto-smoke", "--capture=" + supported_capture])).get("error", "")) == "auto_smoke_requires_capture_stage",
		"game root capture: --auto-smoke accepted a stage-less --capture", failures)
	_expect(String(probe.capture_request_report(PackedStringArray(["--auto-smoke", "--presentation-off", "--capture-stage=auto", "--capture=" + supported_capture])).get("error", "")) == "capture_stage_rejects_presentation_off",
		"game root capture: --presentation-off was accepted as settlement evidence", failures)
	_expect(String(probe.capture_request_report(PackedStringArray(["--capture=/data/tmp/mib-capture-contract/a.png", "--capture=/data/tmp/mib-capture-contract/b.png"])).get("error", "")) == "conflicting_capture_flag",
		"game root capture: two different --capture paths were not treated as a conflict", failures)

	## This suite runs headless: the environment gate has to say so.
	var environment: Dictionary = probe.capture_environment_report()
	if DisplayServer.get_name().to_lower().contains("headless"):
		_expect(String(environment.get("error", "")) == "headless_display" and not bool(environment.get("ok", true)),
			"game root capture: a headless display was reported as a valid GPU capture", failures)
	else:
		_expect(bool(environment.get("ok", false)),
			"game root capture: a graphical environment was refused", failures)

	## Evidence has to be fresh evidence.
	var capture_directory: String = ProjectSettings.globalize_path("user://makeitbig-capture-contract-tests")
	DirAccess.make_dir_recursive_absolute(capture_directory)
	var fresh_path: String = capture_directory.path_join("fresh.png")
	_remove_capture_artifact(fresh_path)
	_remove_capture_artifact(fresh_path + ".json")
	_expect(bool(probe.capture_evidence_target_available(fresh_path).get("ok", false)),
		"game root capture: a fresh evidence path was refused", failures)
	_expect(String(probe.capture_evidence_target_available("").get("error", "")) == "empty_capture_path",
		"game root capture: an empty evidence path was accepted", failures)
	_expect(String(probe.capture_evidence_target_available(capture_directory).get("error", "")) == "invalid_capture_path",
		"game root capture: a directory was accepted as an evidence file", failures)
	var occupied := FileAccess.open(fresh_path, FileAccess.WRITE)
	if occupied != null:
		occupied.store_string("stale evidence")
		occupied.close()
	_expect(String(probe.capture_evidence_target_available(fresh_path).get("error", "")) == "capture_path_not_fresh",
		"game root capture: an existing png was accepted as fresh settlement evidence", failures)
	_remove_capture_artifact(fresh_path)
	var occupied_sidecar := FileAccess.open(fresh_path + ".json", FileAccess.WRITE)
	if occupied_sidecar != null:
		occupied_sidecar.store_string("stale sidecar")
		occupied_sidecar.close()
	_expect(String(probe.capture_evidence_target_available(fresh_path).get("error", "")) == "capture_path_not_fresh",
		"game root capture: an existing sidecar was accepted as fresh settlement evidence", failures)
	_remove_capture_artifact(fresh_path + ".json")
	_destroy_game(probe)

	## Route preparation reports the exact requested/actual pair.
	var game = _create_game()
	var prepared: Dictionary = game.prepare_capture_route("loadout")
	_expect(bool(prepared.get("ok", false)) and String(prepared.get("requested_route", "")) == "loadout" and String(prepared.get("actual_route", "")) == "loadout",
		"game root capture: a reachable route request did not report its actual route", failures)
	var mismatch: Dictionary = game.prepare_capture_route("base")
	_expect(not bool(mismatch.get("ok", true)) and String(mismatch.get("error", "")) == "route_mismatch"
		and String(mismatch.get("requested_route", "")) == "base" and String(mismatch.get("actual_route", "")) == "loadout",
		"game root capture: an unreachable route request was not reported as a mismatch", failures)
	_destroy_game(game)

	## End to end: the rejected defect request must refuse before bootstrap, exit
	## non-zero and leave no evidence behind.
	var refused = GameRootScript.new()
	refused.save_directory_path = TEST_DIRECTORY
	refused.playtest_logging_enabled = false
	var exits: Array = []
	refused.exit_code_hook = func(code: int, reason: String) -> void:
		exits.append({"code": code, "reason": reason})
	var stale_path: String = capture_directory.path_join("release_result.png")
	_remove_capture_artifact(stale_path)
	refused.initialize(PackedStringArray(["--capture-route=result", "--capture=" + stale_path]))
	var observed: Dictionary = exits[0] if exits.size() == 1 and exits[0] is Dictionary else {}
	_expect(int(observed.get("code", 0)) == 1 and String(observed.get("reason", "")) == "capture_fail:unsupported_capture_route",
		"game root capture: --capture-route=result did not fail loudly", failures)
	_expect(refused.current_route == "boot" and refused.current_screen == null,
		"game root capture: a refused request still booted the framework", failures)
	_expect(not FileAccess.file_exists(stale_path),
		"game root capture: a refused request still produced evidence", failures)
	_destroy_game(refused)
	_cleanup_capture_directory(capture_directory)


func _remove_capture_artifact(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _cleanup_capture_directory(directory: String) -> void:
	for file_name in ["fresh.png", "fresh.png.json", "release_result.png", "release_result.png.json"]:
		_remove_capture_artifact(directory.path_join(file_name))
