class_name ContractFlow
extends RefCounted

## Contract lifecycle extracted from GameRoot. This collaborator owns the
## contract launch and settlement path, the deferred defeat-result route
## window, and the result and ending exits, reaching owner state and
## presentation through the untyped owner reference.
const SceneRouterScript = preload("res://src/game/scene_router.gd")
const ContractPlanScript = preload("res://src/game/contract_plan.gd")
const EarlyItemRegistryScript = preload("res://src/content/early_item_registry.gd")
const CoreResult := preload("res://src/core/result.gd")

var _root


func _init(root) -> void:
	_root = root


func cancel_contract() -> Dictionary:
	if _root.current_route != SceneRouterScript.ROUTE_CONTRACT:
		return CoreResult.failure("wrong_route")
	_root.application_state.abandon_session()
	_root._status_message = "Contract preparation cancelled."
	return _root._transition(SceneRouterScript.ROUTE_BASE)


func launch_contract(config: Dictionary) -> Dictionary:
	if _root.current_route != SceneRouterScript.ROUTE_CONTRACT:
		return CoreResult.failure("wrong_route")
	var active_snapshot: Dictionary = _root.application_state.active_build_snapshot()
	var active_build: Dictionary = _root._active_build_from_snapshot(active_snapshot)
	var resolved_build: Dictionary = _root.application_state.resolved_build_snapshot()
	if not bool(resolved_build.get("ok", false)) or String(resolved_build.get("build_fingerprint", "")).length() != 64:
		_root._present_contract("active_build_invalid")
		return CoreResult.failure("active_build_invalid")
	# preset_id is a live session field: the active session record, the combat
	# growth-discovery telemetry and the room/run reports all carry it. The
	# frozen resolver output below remains the sole combat-parameter authority.
	var preset_id := String(resolved_build.get("growth_classification", "convergent"))
	if preset_id not in ["convergent", "critical", "exponential"]:
		preset_id = "convergent"
	var planned_config := config.duplicate(true)
	planned_config["preset_id"] = preset_id
	planned_config["resolved_build"] = resolved_build.duplicate(true)
	# Callers cannot bypass the CLI-presentation contract: the planned session
	# always carries the flag parsed from --presentation-off (default true).
	planned_config["presentation_enabled"] = _root._presentation_enabled
	var campaign_progress: Dictionary = _root.application_state.campaign_progress_snapshot()
	if not bool(campaign_progress.get("ok", false)):
		_root._present_contract(String(campaign_progress.get("error", "campaign_progress_invalid")))
		return campaign_progress
	planned_config["completed_node_ids"] = (campaign_progress.get("completed_node_ids", []) as Array).duplicate()
	if String(planned_config.get("mode", "")).strip_edges().to_lower() == "auto" and not _root.application_state.is_auto_mode_unlocked():
		_root._record_playtest("auto_rejected", {
			"contract_id": String(planned_config.get("contract_id", "")),
			"reason": "proxy_locked",
		})
		_root._present_contract("proxy_locked")
		return CoreResult.failure("proxy_locked")
	var resolved_proxy_build: Dictionary = {}
	if String(planned_config.get("mode", "")).strip_edges().to_lower() == "auto":
		var proxy_resolution: Dictionary = _root.application_state.resolved_proxy_build_snapshot()
		if not bool(proxy_resolution.get("ok", false)):
			var proxy_error := String(proxy_resolution.get("error", "invalid_proxy_build"))
			_root._present_contract(proxy_error)
			return proxy_resolution
		resolved_proxy_build = (proxy_resolution.resolved_proxy_build as Dictionary).duplicate(true)
	var plan_result: Dictionary = ContractPlanScript.build(planned_config)
	if not bool(plan_result.get("ok", false)):
		_root._present_contract(String(plan_result.get("error", "contract_plan_failed")))
		return plan_result
	var room_plan: Dictionary = (plan_result.get("plan", {}) as Dictionary).duplicate(true)
	if not _root._prototype_debug_force_family.is_empty():
		_apply_forced_drop_family(room_plan, _root._prototype_debug_force_family)
	planned_config["room_plan"] = room_plan
	planned_config["room_count"] = int(room_plan.get("room_count", planned_config.get("room_count", 0)))
	var profile: Dictionary = _root.application_state.profile
	var progression_value: Variant = profile.get("progression", {})
	var progression: Dictionary = progression_value if progression_value is Dictionary else {}
	planned_config["framework_context"] = {
		"contract_wins": maxi(0, int(progression.get("contract_wins", 0))),
		"active_build": active_build.duplicate(true),
		"resolved_build": resolved_build.duplicate(true),
		"resolved_proxy_build": resolved_proxy_build.duplicate(true),
	}
	var prepared: Dictionary = _root.application_state.prepare_contract(planned_config)
	if not bool(prepared.get("ok", false)):
		_root._present_contract(String(prepared.get("error", "contract_prepare_failed")))
		return prepared
	var begun: Dictionary = _root.application_state.begin_session()
	if not bool(begun.get("ok", false)):
		_root._present_contract(String(begun.get("error", "session_start_failed")))
		return begun
	if not _root._prototype_debug_force_family.is_empty():
		_root._prototype_debug_force_family = ""
	_root._last_contract = (begun.get("session", {}) as Dictionary).duplicate(true)
	_root._record_playtest("contract_started", {
		"contract_id": String(_root._last_contract.get("contract_id", "")),
		"mode": String(_root._last_contract.get("mode", "")),
		"seed": int(_root._last_contract.get("seed", 0)),
		"room_count": int(_root._last_contract.get("room_count", 0)),
		"build_fingerprint": String(resolved_build.get("build_fingerprint", "")),
		"proxy_build_fingerprint": String(resolved_proxy_build.get("semantic_fingerprint", "")),
	})
	_root._status_message = ""
	return _root._transition(SceneRouterScript.ROUTE_ARENA, _root._last_contract)


func finish_contract(result: Dictionary) -> Dictionary:
	if _root.current_route != SceneRouterScript.ROUTE_ARENA:
		return CoreResult.failure("wrong_route")
	if not _root._pending_visual_route.is_empty():
		## This defeat already settled and its result screen is still waiting for the
		## clip: a duplicate signal must not settle again or rewrite last_result.
		return CoreResult.failure("result_pending")
	var normalized := result.duplicate(true)
	if String(normalized.get("outcome", "")).is_empty():
		normalized["outcome"] = "error"
	var completed: Dictionary = _root.application_state.complete_session(normalized)
	if not bool(completed.get("ok", false)):
		_root.flow_error.emit(String(completed.get("error", "session_complete_failed")), "Could not settle encounter result")
		return completed
	var completed_result: Dictionary = completed.get("result", normalized) if completed.get("result", normalized) is Dictionary else normalized
	var log_payload := {
		"contract_id": String(completed_result.get("contract_id", _root._last_contract.get("contract_id", ""))),
		"mode": String(completed_result.get("mode", _root._last_contract.get("mode", ""))),
		"seed": int(completed_result.get("seed", _root._last_contract.get("seed", 0))),
		"outcome": String(completed_result.get("outcome", "")),
		"ticks": int(completed_result.get("ticks", 0)),
		"elapsed_seconds": float(completed_result.get("elapsed_seconds", 0.0)),
		"room_count": int(completed_result.get("room_count", 0)),
		"rooms_completed": int(completed_result.get("rooms_completed", 0)),
		"casts": int(completed_result.get("casts", 0)),
		"defeated": int(completed_result.get("defeated", 0)),
	}
	var failure_reason := String(completed_result.get("failure_reason", ""))
	if not failure_reason.is_empty():
		log_payload["failure_reason"] = failure_reason
	var rewards_value: Variant = completed_result.get("rewards", {})
	if rewards_value is Dictionary:
		var rewards: Dictionary = rewards_value
		var equipment_ids: Array[String] = []
		var drops_value: Variant = rewards.get("equipment_drops", [])
		if drops_value is Array:
			for drop_value in drops_value:
				if drop_value is Dictionary:
					equipment_ids.append(String((drop_value as Dictionary).get("instance_id", "")))
		log_payload["rewards"] = {
			"law_tallies_delta": (rewards.get("law_tallies_delta", {}) as Dictionary).duplicate(true) if rewards.get("law_tallies_delta", {}) is Dictionary else {},
			"equipment_drop_ids": equipment_ids,
			"repeatable_attempt_number": int(rewards.get("repeatable_attempt_number", 0)),
			"pity_guarantee_family": String(rewards.get("pity_guarantee_family", "")),
		}
	var room_summaries: Array[Dictionary] = []
	var room_results_value: Variant = completed_result.get("room_results", [])
	if room_results_value is Array:
		for room_value in room_results_value:
			if not room_value is Dictionary:
				continue
			var room: Dictionary = room_value
			room_summaries.append({
				"room_id": String(room.get("room_id", "")),
				"objective": String(room.get("objective", "")),
				"layout": String(room.get("layout", "")),
				"outcome": String(room.get("outcome", "")),
				"ticks": int(room.get("ticks", 0)),
				"elapsed_seconds": float(room.get("elapsed_seconds", 0.0)),
				"casts": int(room.get("casts", 0)),
				"defeated": int(room.get("defeated", 0)),
			})
			var room_failure_reason := String(room.get("failure_reason", ""))
			if not room_failure_reason.is_empty():
				room_summaries[room_summaries.size() - 1]["failure_reason"] = room_failure_reason
	if not room_summaries.is_empty():
		log_payload["rooms"] = room_summaries
	var bottleneck_value: Variant = completed_result.get("primary_bottleneck", null)
	if bottleneck_value is Dictionary:
		log_payload["primary_bottleneck"] = String((bottleneck_value as Dictionary).get("id", ""))
	_root._record_playtest("contract_finished", log_payload)
	var unlock_value: Variant = completed_result.get("unlock", {})
	if unlock_value is Dictionary and bool((unlock_value as Dictionary).get("proxy_unlocked", false)):
		_root._record_playtest("auto_unlocked", {
			"contract_id": String(completed_result.get("contract_id", "")),
			"components": ((unlock_value as Dictionary).get("components", []) as Array).duplicate(true) if (unlock_value as Dictionary).get("components", []) is Array else [],
			"profile_elapsed_msec": _root._profile_elapsed_msec(),
		})
	var progression_value: Variant = _root.application_state.profile.get("progression", {})
	var progression: Dictionary = progression_value if progression_value is Dictionary else {}
	if (
		bool(progression.get("early_game_complete", false))
		and String(completed_result.get("contract_id", "")) == "auto_certification"
		and String(completed_result.get("outcome", "")) == "final_victory"
	):
		_root._record_playtest("early_game_completed", {
			"contract_id": "auto_certification",
			"profile_elapsed_msec": _root._profile_elapsed_msec(),
		})
	_root._status_message = _root._persist("Contract result saved", SceneRouterScript.ROUTE_BASE)
	return _route_to_result(completed_result)


## Everything above already settled: complete_session(), the progression, the
## equipment drops, the save and the playtest record have all happened exactly
## once, inside this call. This only decides whether the result screen may
## replace the arena screen now, or has to wait for the defeat clip that is still
## playing on it.
func _route_to_result(completed_result: Dictionary) -> Dictionary:
	if not _defeat_window_holds_screen(completed_result):
		return _root._transition(SceneRouterScript.ROUTE_RESULT, completed_result)
	_root._pending_visual_route = {
		"route": SceneRouterScript.ROUTE_RESULT,
		"payload": completed_result.duplicate(true),
		"seconds": 0.0,
	}
	return {
		"ok": true,
		"noop": true,
		"route": _root.current_route,
		"pending_route": SceneRouterScript.ROUTE_RESULT,
		"deferred": true,
	}


## A defeated run whose clip is still on screen holds the route at the screen
## layer only. Victories, abandons, the smoke driver's own route expectations and
## any screen without the readiness relay are never held.
func _defeat_window_holds_screen(completed_result: Dictionary) -> bool:
	if _root._auto_smoke_session:
		return false
	if String(completed_result.get("outcome", "")) != "defeat":
		return false
	if _root._current_screen == null or not is_instance_valid(_root._current_screen):
		return false
	if not _root._current_screen.has_method("defeat_presentation_ready"):
		return false
	return not bool(_root._current_screen.call("defeat_presentation_ready"))


## Releases the deferred result screen and names why. No settlement is repeated
## here: a second call after the route moved is refused by the router itself.
func _release_pending_visual_route(reason: String) -> Dictionary:
	if _root._pending_visual_route.is_empty():
		return CoreResult.failure("no_pending_route")
	_root._pending_route_release_reason = reason
	var payload: Dictionary = _root._pending_visual_route.get("payload", {})
	_root._pending_visual_route = {}
	return _root._transition(SceneRouterScript.ROUTE_RESULT, payload)


## Public skip entry for the defeat window: the fall has been seen (or the caller
## does not want to wait for it), so the deferred result screen commits now. The
## settlement is untouched -- it already happened exactly once.
func skip_defeat_presentation() -> Dictionary:
	return _release_pending_visual_route("skipped")


## Read-only route-layer diagnostic for the defeat window: whether the result
## screen is still waiting for the clip, for how long, and what released it.
func defeat_route_report() -> Dictionary:
	return {
		"pending": not _root._pending_visual_route.is_empty(),
		"held_seconds": float(_root._pending_visual_route.get("seconds", 0.0)),
		"fallback_seconds": _root.DEFEAT_ROUTE_FALLBACK_SECONDS,
		"released_by": _root._pending_route_release_reason,
	}


func leave_result() -> Dictionary:
	if _root.current_route != SceneRouterScript.ROUTE_RESULT:
		return CoreResult.failure("wrong_route")
	return _root._transition(SceneRouterScript.ROUTE_BASE)


func _open_next_contract_from_result() -> void:
	if _root.current_route != SceneRouterScript.ROUTE_RESULT:
		return
	var result := leave_result()
	if bool(result.get("ok", false)):
		_root.open_contract()


## A settled equipment drop is already in the authoritative inventory. This route
## changes only what the player is looking at: it validates the owned instance,
## carries a one-shot focus hint to the loadout screen, and never equips the item.
func review_result_drop(instance_id: String, slot: String) -> Dictionary:
	if _root.current_route != SceneRouterScript.ROUTE_RESULT:
		return CoreResult.failure("wrong_route")
	var normalized_id := instance_id.strip_edges()
	var normalized_slot := slot.strip_edges()
	var item: Dictionary = _root._owned_equipment_for_telemetry(normalized_id)
	if item.is_empty():
		return CoreResult.failure("item_not_owned")
	var settled_drop := _settled_result_equipment(normalized_id)
	if settled_drop.is_empty():
		return CoreResult.failure("drop_not_in_result")
	if normalized_slot.is_empty() or String(item.get("slot", "")) != normalized_slot or String(settled_drop.get("slot", "")) != normalized_slot:
		return CoreResult.failure("slot_mismatch")
	if normalized_slot not in EarlyItemRegistryScript.PROTOTYPE_OPEN_SLOTS:
		return CoreResult.failure("slot_locked")
	var active := _root.application_state.active_build_snapshot().get("active_build", {}) as Dictionary
	var equipped := active.get("equipped_item_ids", {}) as Dictionary
	_root._status_message = "Drop located; it is equipped. Inspect or unequip it." if String(equipped.get(normalized_slot, "")) == normalized_id else "Drop located; compare it and decide whether to equip it."
	_root._record_playtest("drop_review_started", {
		"instance_id": normalized_id,
		"slot": normalized_slot,
		"base_item_id": String(item.get("base_item_id", "")),
	})
	return _root._transition(SceneRouterScript.ROUTE_LOADOUT, {
		"review_instance_id": normalized_id,
		"focus_slot": normalized_slot,
		"return_route": SceneRouterScript.ROUTE_RESULT,
	})


func _settled_result_equipment(instance_id: String) -> Dictionary:
	var result: Dictionary = _root.application_state.last_result
	var rewards_value: Variant = result.get("rewards", {})
	if not rewards_value is Dictionary:
		return {}
	var drops_value: Variant = (rewards_value as Dictionary).get("equipment_drops", [])
	if not drops_value is Array:
		return {}
	for drop_value in drops_value:
		if drop_value is Dictionary and String((drop_value as Dictionary).get("instance_id", "")) == instance_id:
			return (drop_value as Dictionary).duplicate(true)
	return {}


func open_ending() -> Dictionary:
	if _root.current_route != SceneRouterScript.ROUTE_RESULT:
		return CoreResult.failure("wrong_route")
	if String(_root.application_state.last_result.get("outcome", "")) != "final_victory":
		return CoreResult.failure("ending_locked")
	return _root._transition(SceneRouterScript.ROUTE_ENDING)


func leave_ending_to_base() -> Dictionary:
	if _root.current_route != SceneRouterScript.ROUTE_ENDING:
		return CoreResult.failure("wrong_route")
	return _root._transition(SceneRouterScript.ROUTE_BASE)


func leave_ending_to_title() -> Dictionary:
	if _root.current_route != SceneRouterScript.ROUTE_ENDING:
		return CoreResult.failure("wrong_route")
	_root._status_message = _root._persist("Epilogue checkpoint saved", SceneRouterScript.ROUTE_TITLE)
	return _root._transition(SceneRouterScript.ROUTE_TITLE)


## One-shot debug drop override: after ContractPlan.build, every room of the
## next RoomPlan gains the general equipment drop tag (when missing) and a
## guarantee_family.  ApplicationState's existing drop-unlock gate still
## applies; the pending override is cleared only after begin_session succeeds.
func _apply_forced_drop_family(room_plan: Dictionary, family: String) -> void:
	var rooms_value: Variant = room_plan.get("rooms", [])
	if not rooms_value is Array:
		return
	for room_value in rooms_value:
		if not room_value is Dictionary:
			continue
		var room: Dictionary = room_value
		var tags_value: Variant = room.get("drop_tags", [])
		var tags: Array = (tags_value as Array).duplicate() if tags_value is Array else []
		if not tags.has(_root.PROTOTYPE_DEBUG_FORCED_DROP_TAG):
			tags.append(_root.PROTOTYPE_DEBUG_FORCED_DROP_TAG)
		room["drop_tags"] = tags
		room["guarantee_family"] = family
