extends RefCounted

## Runtime applier for Make It Big prototype debug directives.
##
## GameRoot loads this script dynamically with
## load("res://tools/prototype_debug_runtime.gd"), so this script intentionally
## declares no class_name: it must never enter the global class cache or become
## an export-time dependency (tools/ is excluded from release exports).
##
## apply(game, dto) replays the production progression path instead of poking
## ApplicationState internals:
##   * profiles are rebuilt only through reset/start_new_profile/complete_tutorial
##   * campaign nodes settle through EarlyCampaignRegistry + ContractPlan +
##     prepare_contract/begin_session/complete_session, never by appending IDs
##   * the pre_boss ladder uses the calibration_exponential equipment path and
##     runs one real training trial
##   * forced items enter inventory through persistent_payload deep copies and
##     restore_persistent_payload
##
## The returned summary is stable and JSON-serializable; GameRoot records it as
## prototype_debug_applied. apply itself never writes a save.

const ContractPlanScript = preload("res://src/game/contract_plan.gd")
const EarlyCampaignRegistryScript = preload("res://src/content/early_campaign_registry.gd")
const EarlyItemRegistryScript = preload("res://src/content/early_item_registry.gd")

const REPLAY_SEED := 52969
const MAINLINE_NODE_IDS: Array[String] = [
	"mainline_01_first_hunt",
	"mainline_02_priority_under_pressure",
	"mainline_03_first_elite",
	"mainline_04_hazard_and_forge",
	"mainline_05_growth_gate",
]
const BOSS_NODE_ID := "threshold_colossus"
const AUTO_NODE_ID := "auto_certification"
const WHITE_PROXY_CORES: Array[String] = [
	"near_enemy_horizon",
	"direct_gait",
	"single_key_execution",
	"short_trace_memory",
]
const DEBUG_GRANT_SOURCE_TYPE := "debug_grant"


static func apply(game, dto: Dictionary) -> Dictionary:
	if not bool(dto.get("enabled", false)):
		return _failure("debug_disabled")
	var campaign_registry := EarlyCampaignRegistryScript.new()
	if not campaign_registry.load_campaign().is_empty():
		return _failure("campaign_content_unavailable")

	var changed := false
	var stage := "keep"
	if bool(dto.get("has_stage", false)):
		stage = String(dto.get("stage", "fresh"))
		var staged := _apply_stage(game, campaign_registry, stage)
		if not bool(staged.get("ok", false)):
			return staged
		changed = true

	var force_item_summary: Dictionary = {}
	var force_item_id := String(dto.get("force_item", ""))
	if not force_item_id.is_empty():
		var granted := _apply_force_item(game, force_item_id)
		if not bool(granted.get("ok", false)):
			return granted
		force_item_summary = (granted.get("item", {}) as Dictionary).duplicate(true)
		changed = true

	var force_family := String(dto.get("force_family", "")).strip_edges()
	if not force_family.is_empty():
		var family_ok := _validate_force_family(force_family)
		if not bool(family_ok.get("ok", false)):
			return family_ok

	var final_route := "base"
	if stage == "fresh":
		final_route = "title"
	elif stage == "keep":
		final_route = _current_safe_route(game)
	var routed := _route_to(game, final_route)
	if not bool(routed.get("ok", false)):
		return routed

	var summary := {
		"ok": true,
		"stage": stage,
		"route": final_route,
		"changed": changed,
	}
	if not force_family.is_empty():
		summary["force_family"] = force_family
	if not force_item_summary.is_empty():
		summary["force_item"] = force_item_summary.duplicate(true)
	return summary


static func _apply_stage(game, campaign_registry, stage: String) -> Dictionary:
	if stage == "fresh":
		game.application_state.reset()
		return {"ok": true}
	if stage not in ["base", "pre_boss", "post_boss", "graduated"]:
		return _failure("invalid_stage")

	game.application_state.reset()
	var created: Dictionary = game.application_state.start_new_profile("ranger")
	if not bool(created.get("ok", false)):
		return created
	var tutorial: Dictionary = game.application_state.complete_tutorial()
	if not bool(tutorial.get("ok", false)):
		return tutorial
	if stage == "base":
		return {"ok": true}

	# pre_boss and beyond use the real calibration_exponential equipment path
	# and run one training trial so the Boss can be tested immediately.
	var selected: Dictionary = game.application_state.select_ranger_build("exponential")
	if not bool(selected.get("ok", false)):
		return selected
	var trained: Dictionary = game.application_state.run_training_trial()
	if not bool(trained.get("ok", false)):
		return trained

	for node_id in MAINLINE_NODE_IDS:
		var settled: Dictionary = _settle_campaign_node(game, campaign_registry, node_id, "Manual")
		if not bool(settled.get("ok", false)):
			return settled
	if stage == "pre_boss":
		return _verify_pre_boss(game)

	var boss: Dictionary = _settle_campaign_node(game, campaign_registry, BOSS_NODE_ID, "Manual")
	if not bool(boss.get("ok", false)):
		return boss
	var post_boss := _verify_post_boss(game)
	if not bool(post_boss.get("ok", false)):
		return post_boss
	if stage == "post_boss":
		return {"ok": true}

	var auto_settled: Dictionary = _settle_campaign_node(game, campaign_registry, AUTO_NODE_ID, "Auto")
	if not bool(auto_settled.get("ok", false)):
		return auto_settled
	return _verify_graduated(game)


static func _settle_campaign_node(game, campaign_registry, node_id: String, mode: String) -> Dictionary:
	var progress: Dictionary = game.application_state.campaign_progress_snapshot()
	if not bool(progress.get("ok", false)):
		return _failure("campaign_progress_invalid")
	var completed: Array = (progress.get("completed_node_ids", []) as Array).duplicate()
	var available: Array = progress.get("available_node_ids", [])
	if node_id in completed or node_id not in available:
		return _failure("node_not_legally_available")
	var node: Dictionary = campaign_registry.get_node(node_id)
	if node.is_empty():
		return _failure("unknown_campaign_node")
	var room_sequence_value: Variant = node.get("room_sequence", [])
	if not room_sequence_value is Array:
		return _failure("empty_room_sequence")
	var room_count := (room_sequence_value as Array).size()
	if room_count < 1:
		return _failure("empty_room_sequence")

	var config := {
		"contract_id": node_id,
		"mode": mode,
		"preset_id": "exponential",
		"seed": REPLAY_SEED,
		"room_count": room_count,
		"completed_node_ids": completed,
	}
	var planned: Dictionary = ContractPlanScript.build(config)
	if not bool(planned.get("ok", false)):
		return planned
	config["room_plan"] = (planned.get("plan", {}) as Dictionary).duplicate(true)
	var prepared: Dictionary = game.application_state.prepare_contract(config)
	if not bool(prepared.get("ok", false)):
		return prepared
	var begun: Dictionary = game.application_state.begin_session()
	if not bool(begun.get("ok", false)):
		return begun
	var settled: Dictionary = game.application_state.complete_session({
		"outcome": "victory",
		"contract_id": node_id,
		"mode": mode,
		"room_count": room_count,
		"rooms_completed": room_count,
		"ticks": room_count * 90,
		"elapsed_seconds": float(room_count) * 3.0,
		"casts": room_count * 4,
		"defeated": room_count * 7,
		"rewards": {"contract_wins_delta": 1},
	})
	if not bool(settled.get("ok", false)):
		return settled
	return {"ok": true}


static func _verify_pre_boss(game) -> Dictionary:
	var profile: Dictionary = game.application_state.profile
	var progression: Dictionary = profile.get("progression", {})
	var completed: Array = progression.get("completed_node_ids", [])
	for node_id in MAINLINE_NODE_IDS:
		if node_id not in completed:
			return _failure("mainline_incomplete")
	if "threshold_colossus" in completed or "auto_certification" in completed:
		return _failure("stage_overshot")
	if game.application_state.is_auto_mode_unlocked():
		return _failure("auto_prematurely_unlocked")
	return {"ok": true}


static func _verify_post_boss(game) -> Dictionary:
	var profile: Dictionary = game.application_state.profile
	var progression: Dictionary = profile.get("progression", {})
	var completed: Array = progression.get("completed_node_ids", [])
	if "threshold_colossus" not in completed or "auto_certification" in completed:
		return _failure("boss_progression_invalid")
	if not game.application_state.is_auto_mode_unlocked():
		return _failure("auto_not_unlocked")
	var proxy_build: Dictionary = profile.get("proxy_build", {})
	var cores: Array = proxy_build.get("cores", [])
	if cores != WHITE_PROXY_CORES:
		return _failure("white_cores_missing")
	if bool(progression.get("early_game_complete", false)):
		return _failure("early_game_prematurely_complete")
	return {"ok": true}


static func _verify_graduated(game) -> Dictionary:
	var profile: Dictionary = game.application_state.profile
	var progression: Dictionary = profile.get("progression", {})
	var completed: Array = progression.get("completed_node_ids", [])
	if "auto_certification" not in completed:
		return _failure("graduation_incomplete")
	if String(game.application_state.last_result.get("outcome", "")) != "final_victory":
		return _failure("graduation_not_final_victory")
	if not bool(progression.get("ending_unlocked", false)):
		return _failure("ending_not_unlocked")
	if not bool(progression.get("early_game_complete", false)):
		return _failure("early_game_incomplete")
	return {"ok": true}


static func _apply_force_item(game, base_item_id: String) -> Dictionary:
	if not game.application_state.has_profile():
		return _failure("profile_required")
	var item_registry := EarlyItemRegistryScript.new()
	if not item_registry.load_all().is_empty():
		return _failure("item_content_unavailable")
	var normalized_id := base_item_id.strip_edges()
	if not item_registry.base_items.has(normalized_id):
		return _failure("unknown_base_item")
	var base: Dictionary = item_registry.base_items[normalized_id]
	var slot := String(base.get("slot", ""))
	var source_id := "debug-grant-%s" % normalized_id
	var instance_id := source_id.sha256_text()
	var law_seed := ("0x" + instance_id.substr(0, 13)).hex_to_int()
	var item := {
		"instance_id": instance_id,
		"base_item_id": normalized_id,
		"slot": slot,
		"affixes": [],
		"rune_id": "",
		"law_id": "",
		"source": {"type": DEBUG_GRANT_SOURCE_TYPE, "id": source_id},
		"law_seed": law_seed,
	}
	if not item_registry.validate_item_instance(item).is_empty():
		return _failure("invalid_granted_item")

	# Route the grant through a deep copy of the authoritative persistent
	# payload instead of mutating a profile getter copy.
	var payload: Dictionary = game.application_state.persistent_payload("base")
	var payload_profile: Dictionary = payload.get("profile", {})
	var inventory: Dictionary = payload_profile.get("inventory", {})
	var equipment: Array = inventory.get("equipment", [])
	for existing_value in equipment:
		if existing_value is Dictionary and String((existing_value as Dictionary).get("instance_id", "")) == instance_id:
			return {"ok": true, "item": item.duplicate(true)}
	equipment.append(item.duplicate(true))
	var restored: Dictionary = game.application_state.restore_persistent_payload(payload)
	if not bool(restored.get("ok", false)):
		return restored
	return {"ok": true, "item": item.duplicate(true)}


static func _validate_force_family(family_id: String) -> Dictionary:
	var item_registry := EarlyItemRegistryScript.new()
	if not item_registry.load_all().is_empty():
		return _failure("item_content_unavailable")
	if not item_registry.affix_families.has(family_id):
		return _failure("unknown_affix_family")
	return {"ok": true}


static func _route_to(game, route: String) -> Dictionary:
	if String(game.current_route) == route:
		return {"ok": true}
	var result: Variant = game.call("_transition", route)
	if not (result is Dictionary) or not bool((result as Dictionary).get("ok", false)):
		var error_code := "route_transition_failed"
		if result is Dictionary:
			error_code = String((result as Dictionary).get("error", error_code))
		return _failure(error_code)
	return {"ok": true}


static func _current_safe_route(game) -> String:
	var route := String(game.current_route)
	return route if route in ["title", "tutorial", "base"] else "title"


static func _failure(code: String) -> Dictionary:
	return {"ok": false, "error": code}
