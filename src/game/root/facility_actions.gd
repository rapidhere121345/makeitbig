class_name FacilityActions
extends RefCounted

## Facility action dispatch extracted from GameRoot. This collaborator owns the
## request dispatcher, the forge finishers, the player-facing label helpers, and
## the loadout telemetry builders, reaching owner state and presentation through
## the untyped owner reference.
const SceneRouterScript = preload("res://src/game/scene_router.gd")
const PlayerFacingStatusScript = preload("res://src/presentation/player_facing_status.gd")
const CoreResult := preload("res://src/core/result.gd")
const Collections := preload("res://src/core/collections.gd")

const LOADOUT_PARAMETER_KEYS: Array[String] = ["p", "T", "v", "d", "turn", "damage", "max_health"]
const SLOT_LABELS := {
	"main_hand": "Main Hand", "off_hand": "Off Hand", "gloves": "Gloves", "ring": "Ring",
	"head": "Head", "chest": "Chest", "legs": "Legs", "feet": "Feet",
	"wrists": "Wrists", "belt": "Belt", "ring_2": "Ring 2", "neck": "Necklace",
}
const PRESET_LABELS := {"convergent": "Convergent", "critical": "Critical", "exponential": "Exponential"}

var _root


func _init(root) -> void:
	_root = root


func request_facility_action(facility_id: String, action_id: String, payload: Dictionary = {}) -> Dictionary:
	var normalized_facility := facility_id.strip_edges().to_lower()
	if normalized_facility not in _root.FACILITY_ROUTES:
		return CoreResult.failure("unknown_facility")
	if _root.current_route != normalized_facility:
		return CoreResult.failure("wrong_route")
	if normalized_facility == SceneRouterScript.ROUTE_LOADOUT and action_id in ["equip_item", "unequip_item", "salvage_item"]:
		var before: Dictionary = _loadout_telemetry_snapshot() if action_id in ["equip_item", "unequip_item"] else {}
		var subject := String(payload.get("instance_id", payload.get("slot", "")))
		var subject_item := _owned_equipment_for_telemetry(String(payload.get("instance_id", "")))
		if action_id == "unequip_item":
			var slot := String(payload.get("slot", ""))
			subject_item = _equipped_item_for_slot(slot)
		var subject_label := _equipment_label(subject_item, _slot_label(String(payload.get("slot", ""))))
		var action_label := "Salvage" if action_id == "salvage_item" else ("Unequip item" if action_id == "unequip_item" else "Equip item")
		var changed: Dictionary
		if action_id == "equip_item":
			changed = _root.application_state.equip_item(String(payload.get("instance_id", "")))
		elif action_id == "unequip_item":
			changed = _root.application_state.unequip_item(String(payload.get("slot", "")))
		else:
			changed = _root.application_state.salvage_item(String(payload.get("instance_id", "")))
		if not bool(changed.get("ok", false)):
			_root._status_message = PlayerFacingStatusScript.failure(action_label, String(changed.get("error", "unknown_error")))
			_root._present_facility(normalized_facility, _root._status_message)
			return changed
		if action_id == "salvage_item":
			_root._record_playtest("item_salvaged", {
				"instance_id": subject,
				"operation": String(changed.get("operation", "")),
				"amount": int(changed.get("amount", 0)),
			})
			_root._status_message = _root._persist("Salvaged: %s -> %s Law Tokens x%d" % [subject_label, _law_tally_label(String(changed.get("operation", ""))), int(changed.get("amount", 0))], SceneRouterScript.ROUTE_BASE)
		else:
			_root._record_playtest("loadout_changed", _build_loadout_telemetry(action_id, subject, before))
			_root._status_message = _root._persist("%s: %s" % ["Unequipped" if action_id == "unequip_item" else "Equipped", subject_label], SceneRouterScript.ROUTE_BASE)
		_root._present_facility(normalized_facility, _root._status_message)
		return changed
	if normalized_facility == SceneRouterScript.ROUTE_LOADOUT and action_id == "select_ranger_build":
		var selected: Dictionary = _root.application_state.select_ranger_build(String(payload.get("preset_id", "")))
		if not bool(selected.get("ok", false)):
			_root._status_message = PlayerFacingStatusScript.failure("Switch Build", String(selected.get("error", "unknown_error")))
			_root._present_facility(normalized_facility, _root._status_message)
			return selected
		_root._status_message = _root._persist("Build switched: %s" % _preset_label(String(payload.get("preset_id", ""))), SceneRouterScript.ROUTE_BASE)
		var selected_resolved: Dictionary = _root.application_state.resolved_build_snapshot()
		_root._record_playtest("loadout_changed", {
			"action": "select_ranger_build",
			"subject": String(payload.get("preset_id", "")),
			"build_fingerprint": String(selected_resolved.get("build_fingerprint", "")),
		})
		_root._present_facility(normalized_facility, _root._status_message)
		return selected
	if normalized_facility == SceneRouterScript.ROUTE_TRAINING and action_id == "run_training_trial":
		var trial: Dictionary = _root.application_state.run_training_trial()
		if not bool(trial.get("ok", false)):
			_root._status_message = PlayerFacingStatusScript.failure("Training", String(trial.get("error", "unknown_error")))
			_root._present_facility(normalized_facility, _root._status_message)
			return trial
		_root._status_message = _root._persist("Training dummy trial complete", SceneRouterScript.ROUTE_BASE)
		var trial_report: Dictionary = trial.get("report", {}) if trial.get("report", {}) is Dictionary else {}
		var trial_resolved: Dictionary = _root.application_state.resolved_build_snapshot()
		_root._record_playtest("training_completed", {
			"build_fingerprint": String(trial_report.get("build_fingerprint", "")),
			"training_seed": int(trial_report.get("training_seed", 0)),
			"p": float(trial_report.get("p", 0.0)),
			"R": float(trial_report.get("R", 0.0)),
			"growth_classification": String(trial_report.get("state", "")),
			"growth_curve": (trial_report.get("growth_curve", []) as Array).duplicate(true) if trial_report.get("growth_curve", []) is Array else [],
			"action": String(trial_report.get("action", "")),
			"missing_interfaces": (trial_resolved.get("missing_interfaces", []) as Array).duplicate(true) if trial_resolved.get("missing_interfaces", []) is Array else [],
		})
		_root._present_facility(normalized_facility, _root._status_message)
		return trial
	if normalized_facility == SceneRouterScript.ROUTE_PROXY and action_id in ["equip_proxy_core", "configure_proxy_core"]:
		var core_id := String(payload.get("core_id", "")).strip_edges()
		var changed: Dictionary
		if action_id == "equip_proxy_core":
			changed = _root.application_state.equip_proxy_core(core_id)
		else:
			var settings_value: Variant = payload.get("settings", {})
			changed = _root.application_state.configure_proxy_core(core_id, (settings_value as Dictionary).duplicate(true) if settings_value is Dictionary else {})
		if not bool(changed.get("ok", false)):
			var proxy_action := "Install proxy core" if action_id == "equip_proxy_core" else "Adjust proxy core"
			_root._status_message = PlayerFacingStatusScript.failure(proxy_action, String(changed.get("error", "unknown_error")))
			_root._present_facility(normalized_facility, _root._status_message)
			return changed
		var core_label := _proxy_core_label(core_id)
		if action_id == "equip_proxy_core":
			_root._status_message = _root._persist("Proxy core installed: %s" % core_label, SceneRouterScript.ROUTE_BASE)
		else:
			var band := String((payload.get("settings", {}) as Dictionary).get("distance_band", "")) if payload.get("settings", {}) is Dictionary else ""
			var band_label: String = String({"near": "Near", "mid": "Mid", "far": "Far"}.get(band, band))
			_root._status_message = _root._persist("%s distance band set to: %s" % [core_label, band_label], SceneRouterScript.ROUTE_BASE)
		_root._record_playtest("proxy_build_changed", {
			"action": action_id,
			"core_id": core_id,
			"settings": (payload.get("settings", {}) as Dictionary).duplicate(true) if payload.get("settings", {}) is Dictionary else {},
			"proxy_build_fingerprint": String((changed.get("resolved_proxy_build", {}) as Dictionary).get("semantic_fingerprint", "")),
		})
		_root._present_facility(normalized_facility, _root._status_message)
		return changed
	if normalized_facility == SceneRouterScript.ROUTE_FORGE and action_id == "select_forge_item":
		var selected_id := String(payload.get("instance_id", "")).strip_edges()
		var selected: Dictionary = _root.application_state.forge_select_target(selected_id, int(payload.get("revision", -1)))
		if not bool(selected.get("ok", false)):
			_root._status_message = PlayerFacingStatusScript.failure("Select Forge Target", String(selected.get("error", "unknown_error")))
			_root._present_facility(normalized_facility, _root._status_message)
			return selected
		var selected_snapshot: Dictionary = _root.application_state.forge_snapshot()
		_root._status_message = "Forge target selected: %s" % String((selected_snapshot.target_item as Dictionary).get("base_name", selected_id))
		_root._present_facility(normalized_facility, _root._status_message)
		return {"ok": true, "instance_id": selected_id, "snapshot": selected_snapshot.duplicate(true)}
	if normalized_facility == SceneRouterScript.ROUTE_FORGE and action_id == "select_forge_operation":
		var selected_operation: Dictionary = _root.application_state.forge_select_operation(String(payload.get("operation", "")), int(payload.get("revision", -1)))
		return _finish_forge_action(normalized_facility, selected_operation, "")
	if normalized_facility == SceneRouterScript.ROUTE_FORGE and action_id == "forge_reveal":
		var revealed: Dictionary = _root.application_state.forge_reveal(int(payload.get("limit", 8)), int(payload.get("revision", -1)))
		return _finish_forge_action(normalized_facility, revealed, "Law Token forecast complete")
	if normalized_facility == SceneRouterScript.ROUTE_FORGE and action_id == "forge_reveal_more":
		var revealed_more: Dictionary = _root.application_state.forge_reveal_more(String(payload.get("session_id", "")), int(payload.get("limit", 8)))
		return _finish_forge_action(normalized_facility, revealed_more, "Law Token forecast expanded")
	if normalized_facility == SceneRouterScript.ROUTE_FORGE and action_id == "forge_select_candidate":
		var selected_candidate: Dictionary = _root.application_state.forge_select_candidate(String(payload.get("session_id", "")), String(payload.get("candidate_id", "")))
		return _finish_forge_action(normalized_facility, selected_candidate, "Future candidate selected")
	if normalized_facility == SceneRouterScript.ROUTE_FORGE and action_id == "forge_cancel":
		var cancelled: Dictionary = _root.application_state.forge_cancel(String(payload.get("session_id", "")))
		return _finish_forge_action(normalized_facility, cancelled, "Forge forecast cancelled")
	if normalized_facility != SceneRouterScript.ROUTE_FORGE or action_id != "forge_commit":
		_root._status_message = PlayerFacingStatusScript.failure("This facility action", "action_unavailable")
		_root._present_facility(normalized_facility, _root._status_message)
		return CoreResult.failure("action_unavailable")
	var prepared: Dictionary = _root.application_state.forge_prepare_commit(String(payload.get("session_id", "")))
	if not bool(prepared.get("ok", false)):
		return _finish_forge_action(normalized_facility, prepared, "")
	var commit_token := String(prepared.commit_token)
	if not _root._test_session and not _root._prototype_debug_no_persist:
		var saved: Dictionary = _root.save_store.save((prepared.next_payload as Dictionary).duplicate(true))
		if not bool(saved.get("ok", false)):
			_root.application_state.forge_abort_commit(commit_token)
			var detail := String(saved.get("error", "unknown error"))
			_root.flow_error.emit("save_failed", detail)
			return _forge_action_failure(normalized_facility, "save_failed", detail)
	var committed: Dictionary = _root.application_state.forge_finalize_commit(commit_token)
	if not bool(committed.get("ok", false)):
		return _finish_forge_action(normalized_facility, committed, "")
	var result_value: Variant = committed.get("candidate", {})
	var result: Dictionary = result_value if result_value is Dictionary else {}
	var committed_view: Dictionary = _root.application_state.forge_snapshot()
	var committed_target: Dictionary = (committed_view.get("target_item", {}) as Dictionary) if bool(committed_view.get("ok", false)) else {}
	var raw_result_item: Dictionary = result.get("result_item", {}) as Dictionary
	var item_label := _equipment_label(committed_target, _equipment_label(raw_result_item, "Selected item"))
	var family_label := String(result.get("family_name", "")).strip_edges()
	if family_label.is_empty():
		family_label = "Selected affix"
	_root._status_message = "Forged: %s gained %s tier %d, costing %d %s Law Tokens" % [
		item_label, family_label,
		int(result.get("tier", 0)), int(committed.get("cost", 0)), _law_tally_label(String(committed.get("operation", ""))),
	]
	_root._record_playtest("forge_committed", {
		"instance_id": String((result.result_item as Dictionary).get("instance_id", "")),
		"operation": String(committed.get("operation", "")),
		"family_id": String(result.get("family_id", "")),
		"tier": int(result.get("tier", 0)),
		"cost": int(committed.get("cost", 0)),
	})
	_root._present_facility(normalized_facility, _root._status_message)
	return committed


func _finish_forge_action(facility_id: String, result: Dictionary, success_message: String) -> Dictionary:
	_root._status_message = success_message if bool(result.get("ok", false)) else PlayerFacingStatusScript.failure("Forge", String(result.get("error", "unknown_error")))
	_root._present_facility(facility_id, _root._status_message)
	return result


func _forge_action_failure(facility_id: String, error: String, detail: String = "") -> Dictionary:
	var result := CoreResult.failure(error)
	if not detail.is_empty():
		result["detail"] = detail
	return _finish_forge_action(facility_id, result, "")


func _law_tally_label(operation: String) -> String:
	match operation:
		"inscribe":
			return "Inscribe"
		"rewrite":
			return "Rewrite"
		"refine":
			return "Refine"
	return operation


func _equipment_label(item: Dictionary, fallback: String = "Selected item") -> String:
	var label := String(item.get("base_name", item.get("name", ""))).strip_edges()
	return label if not label.is_empty() else fallback


func _slot_label(slot: String) -> String:
	return String(SLOT_LABELS.get(slot, "Selected slot"))


func _preset_label(preset_id: String) -> String:
	return String(PRESET_LABELS.get(preset_id, "Current preset"))


func _proxy_core_label(core_id: String) -> String:
	var snapshot: Dictionary = _root.application_state.early_game_snapshot()
	var proxy_value: Variant = snapshot.get("proxy", {})
	var proxy: Dictionary = proxy_value if proxy_value is Dictionary else {}
	var catalog_value: Variant = proxy.get("catalog", {})
	var catalog: Dictionary = catalog_value if catalog_value is Dictionary else {}
	var core_value: Variant = catalog.get(core_id, {})
	var core: Dictionary = core_value if core_value is Dictionary else {}
	var label := String(core.get("name", "")).strip_edges()
	return label if not label.is_empty() else core_id


func _equipped_item_for_slot(slot: String) -> Dictionary:
	var profile: Dictionary = _root.application_state.profile
	var active_value: Variant = profile.get("active_build", {})
	var active: Dictionary = active_value if active_value is Dictionary else {}
	var equipped_value: Variant = active.get("equipped_item_ids", {})
	var equipped: Dictionary = equipped_value if equipped_value is Dictionary else {}
	return _owned_equipment_for_telemetry(String(equipped.get(slot, "")))


func _owned_equipment_for_telemetry(instance_id: String) -> Dictionary:
	var inventory_value: Variant = _root.application_state.profile.get("inventory", {})
	var inventory: Dictionary = inventory_value if inventory_value is Dictionary else {}
	var equipment_value: Variant = inventory.get("equipment", [])
	if not equipment_value is Array:
		return {}
	for item_value in equipment_value:
		if item_value is Dictionary and String((item_value as Dictionary).get("instance_id", "")) == instance_id:
			return (item_value as Dictionary).duplicate(true)
	return {}


func _loadout_telemetry_snapshot() -> Dictionary:
	var active_value: Variant = _root.application_state.active_build_snapshot().get("active_build", {})
	var resolved: Dictionary = _root.application_state.resolved_build_snapshot()
	var active: Dictionary = active_value if active_value is Dictionary else {}
	var equipped_value: Variant = active.get("equipped_item_ids", {})
	var equipped: Dictionary = equipped_value if equipped_value is Dictionary else {}
	return {
		"build_fingerprint": String(resolved.get("build_fingerprint", "")),
		"growth": String(resolved.get("growth_classification", "")),
		"interfaces": _resolved_interface_ids(resolved),
		"parameters": _finite_build_parameters(resolved),
		"equipped": equipped.duplicate(true),
	}


func _build_loadout_telemetry(action_id: String, subject: String, before: Dictionary) -> Dictionary:
	var after: Dictionary = _loadout_telemetry_snapshot()
	var slot := ""
	if action_id == "unequip_item":
		slot = String(subject)
	else:
		var item: Dictionary = _owned_equipment_for_telemetry(subject)
		slot = String(item.get("slot", ""))
	var previous_equipped: Dictionary = before.get("equipped", {}) if before.get("equipped", {}) is Dictionary else {}
	var next_equipped: Dictionary = after.get("equipped", {}) if after.get("equipped", {}) is Dictionary else {}
	return {
		"action": action_id,
		"slot": slot,
		"previous_instance_id": String(previous_equipped.get(slot, "")),
		"next_instance_id": String(next_equipped.get(slot, "")),
		"previous_build_fingerprint": String(before.get("build_fingerprint", "")),
		"new_build_fingerprint": String(after.get("build_fingerprint", "")),
		"growth_before": String(before.get("growth", "")),
		"growth_after": String(after.get("growth", "")),
		"interfaces_gained": Collections.sorted_string_array_difference(after.get("interfaces", []), before.get("interfaces", [])),
		"interfaces_lost": Collections.sorted_string_array_difference(before.get("interfaces", []), after.get("interfaces", [])),
		"parameter_deltas": _build_parameter_deltas(before.get("parameters", {}), after.get("parameters", {})),
	}


func _resolved_interface_ids(resolved: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var connected_value: Variant = resolved.get("connected_interfaces", [])
	if connected_value is Array:
		for value in connected_value:
			result.append(String(value))
	result.sort()
	return result

func _finite_build_parameters(resolved: Dictionary) -> Dictionary:
	var result := {}
	var parameters_value: Variant = resolved.get("final_parameters", {})
	var parameters: Dictionary = parameters_value if parameters_value is Dictionary else {}
	for key in LOADOUT_PARAMETER_KEYS:
		var value: Variant = parameters.get(key, null)
		if (value is int or value is float) and is_finite(float(value)):
			result[key] = float(value)
	return result


func _build_parameter_deltas(before: Dictionary, after: Dictionary) -> Dictionary:
	var result := {}
	for key in LOADOUT_PARAMETER_KEYS:
		if before.has(key) and after.has(key):
			result[key] = float(after[key]) - float(before[key])
	return result
