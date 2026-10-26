extends RefCounted

## Law Token forge context, reveal sessions and the two-phase commit extracted
## from ApplicationState. This object owns the transient forge state (context,
## session, pending commit, session serial); the profile and last result stay
## with the owner, which is passed into each call and never retained.
const LawForgeScript = preload("res://src/systems/law_forge.gd")
const EarlyItemRegistryScript = preload("res://src/content/early_item_registry.gd")
const CoreResult := preload("res://src/core/result.gd")
const Collections := preload("res://src/core/collections.gd")
const ProfileRules := preload("res://src/game/application/profile_rules.gd")
const BuildResolution := preload("res://src/game/application/build_resolution.gd")
const CampaignProgress := preload("res://src/game/application/campaign_progress.gd")
const ProfileCodec := preload("res://src/game/application/profile_codec.gd")

var _context: Dictionary = {}
var _session: Dictionary = {}
var _pending_commit: Dictionary = {}
var _session_serial := 0


## Drops the transient forge state. The serial is never reset so session ids
## stay unique across profile resets within one process.
func clear() -> void:
	_context.clear()
	_session.clear()
	_pending_commit.clear()


func invalidate_session() -> void:
	_session.clear()
	_pending_commit.clear()


func ensure_context(state) -> Dictionary:
	var profile: Dictionary = state._profile
	if profile.is_empty():
		return CoreResult.failure("profile_required")
	var registry: Variant = ProfileRules.loaded_item_registry()
	if registry == null:
		return CoreResult.failure("content_unavailable")
	var inventory_items: Array = []
	for raw_item in ((profile.inventory as Dictionary).equipment as Array):
		if raw_item is Dictionary and registry.validate_item_instance(raw_item).is_empty():
			inventory_items.append(_item_view(raw_item as Dictionary, registry))
	if inventory_items.is_empty():
		return CoreResult.failure("item_not_owned")
	var target_id := String(_context.get("target_instance_id", "")).strip_edges()
	if target_id.is_empty() or ProfileRules.owned_equipment(profile, target_id).is_empty():
		target_id = _default_target_id(profile, inventory_items)
	var operation := String(_context.get("operation", "inscribe"))
	if operation not in ProfileRules.FORGE_OPERATIONS:
		operation = "inscribe"
	return _set_context(profile, target_id, operation)


func select_target(state, instance_id: String, expected_revision: int = -1) -> Dictionary:
	var profile: Dictionary = state._profile
	if profile.is_empty():
		return CoreResult.failure("profile_required")
	var target_id := instance_id.strip_edges()
	if target_id.is_empty():
		return CoreResult.failure("invalid_instance_id")
	var item := ProfileRules.owned_equipment(profile, target_id)
	if item.is_empty():
		return CoreResult.failure("item_not_owned")
	var registry: Variant = ProfileRules.loaded_item_registry()
	if registry == null:
		return CoreResult.failure("content_unavailable")
	if not registry.validate_item_instance(item).is_empty():
		return CoreResult.failure("invalid_item")
	var ensured := ensure_context(state)
	if not bool(ensured.get("ok", false)):
		return ensured
	if expected_revision >= 0 and expected_revision != int(_context.revision):
		return CoreResult.failure("stale_forge_context")
	return _set_context(profile, target_id, String(_context.operation))


func select_operation(state, operation: String, expected_revision: int = -1) -> Dictionary:
	if operation not in ProfileRules.FORGE_OPERATIONS:
		return CoreResult.failure("unknown_operation")
	var ensured := ensure_context(state)
	if not bool(ensured.get("ok", false)):
		return ensured
	if expected_revision >= 0 and expected_revision != int(_context.revision):
		return CoreResult.failure("stale_forge_context")
	return _set_context(state._profile, String(_context.target_instance_id), operation)


func snapshot(state) -> Dictionary:
	var ensured := ensure_context(state)
	if not bool(ensured.get("ok", false)):
		return ensured
	var profile: Dictionary = state._profile
	var registry: Variant = ProfileRules.loaded_item_registry()
	if registry == null:
		return CoreResult.failure("content_unavailable")
	var inventory_items: Array = []
	for raw_item in ((profile.inventory as Dictionary).equipment as Array):
		if raw_item is Dictionary and registry.validate_item_instance(raw_item).is_empty():
			inventory_items.append(_item_view(raw_item as Dictionary, registry))
	var target_id := String(_context.target_instance_id)
	var target := ProfileRules.owned_equipment(profile, target_id)
	if target.is_empty():
		return CoreResult.failure("item_not_owned")
	if not registry.validate_item_instance(target).is_empty():
		return CoreResult.failure("invalid_item")
	var unlocked := CampaignProgress.is_law_forge_unlocked(profile)
	return {
		"ok": true,
		"unlocked": unlocked,
		"locked_reason": "Complete Main Quest 04 to unlock Law Token forging" if not unlocked else "",
		"law_tallies": ((profile.resources as Dictionary).law_tallies as Dictionary).duplicate(true),
		"affix_families": registry.affix_families.duplicate(true),
		"target_item": _item_view(target, registry),
		"inventory_items": inventory_items.duplicate(true),
		"target_instance_id": target_id,
		"affixes": (target.affixes as Array).duplicate(true),
		"operation": String(_context.operation),
		"blocked": bool(_context.blocked),
		"blocked_reason": String(_context.blocked_reason),
		"revision": int(_context.revision),
		"context": _context.duplicate(true),
		"session": session_view(profile),
	}.duplicate(true)


func reveal(state, limit: int = 8, expected_revision: int = -1) -> Dictionary:
	var profile: Dictionary = state._profile
	if profile.is_empty():
		return CoreResult.failure("profile_required")
	if not CampaignProgress.is_law_forge_unlocked(profile):
		return CoreResult.failure("forge_locked")
	if limit < 1:
		return CoreResult.failure("invalid_page")
	var ensured := ensure_context(state)
	if not bool(ensured.get("ok", false)):
		return ensured
	if expected_revision >= 0 and expected_revision != int(_context.revision):
		return CoreResult.failure("stale_forge_context")
	if bool(_context.get("blocked", false)):
		return CoreResult.failure(String(_context.get("blocked_reason", "invalid_forge_context")))
	var target_id := String(_context.target_instance_id)
	var operation := String(_context.operation)
	var item := ProfileRules.owned_equipment(profile, target_id)
	if item.is_empty():
		return CoreResult.failure("item_not_owned")
	var registry: Variant = ProfileRules.loaded_item_registry()
	if registry == null:
		return CoreResult.failure("content_unavailable")
	var balance := int(((profile.resources as Dictionary).law_tallies as Dictionary).get(operation, 0))
	if balance <= 0:
		return CoreResult.failure("insufficient_law_tallies")
	_session_serial += 1
	var session_id := "%s|%s|%d" % [target_id, operation, _session_serial]
	session_id = session_id.sha256_text()
	var revealed: Dictionary = LawForgeScript.new(registry).reveal(item, operation, 0, mini(limit, balance), session_id)
	if not bool(revealed.get("ok", false)):
		invalidate_session()
		return revealed
	var enriched_candidates := _enrich_candidates(profile, item, (revealed.candidates as Array).duplicate(true), registry)
	_session = {
		"state": "revealed",
		"session_id": session_id,
		"target_instance_id": target_id,
		"target_item": item.duplicate(true),
		"operation": operation,
		"context_revision": int(_context.revision),
		"candidates": enriched_candidates,
		"unique_count": int(revealed.get("unique_count", enriched_candidates.size())),
		"selected_candidate_id": "",
		"has_more": enriched_candidates.size() < mini(balance, int(revealed.get("unique_count", enriched_candidates.size()))),
	}
	_pending_commit.clear()
	return {"ok": true, "session": session_view(profile)}


func reveal_more(state, session_id: String, limit: int = 8) -> Dictionary:
	var profile: Dictionary = state._profile
	if _session.is_empty():
		return CoreResult.failure("forge_session_required")
	if session_id.strip_edges().is_empty() or session_id != String(_session.get("session_id", "")):
		return CoreResult.failure("stale_forge_session")
	if String(_session.get("state", "")) == "prepared":
		return CoreResult.failure("commit_pending")
	if limit < 1:
		return CoreResult.failure("invalid_page")
	var current := ProfileRules.owned_equipment(profile, String(_session.target_instance_id))
	if current.is_empty() or current != _session.target_item:
		invalidate_session()
		return CoreResult.failure("stale_target")
	var registry: Variant = ProfileRules.loaded_item_registry()
	if registry == null:
		return CoreResult.failure("content_unavailable")
	var offset := (_session.candidates as Array).size()
	var operation := String(_session.operation)
	var balance := int(((profile.resources as Dictionary).law_tallies as Dictionary).get(operation, 0))
	var unique_count := int(_session.get("unique_count", 0))
	var remaining := mini(balance, unique_count) - offset
	if remaining <= 0:
		_session["has_more"] = false
		return {"ok": true, "session": session_view(profile)}
	var revealed: Dictionary = LawForgeScript.new(registry).reveal(
		current, operation, offset, mini(limit, remaining), String(_session.session_id)
	)
	if not bool(revealed.get("ok", false)):
		return revealed
	(_session.candidates as Array).append_array(_enrich_candidates(profile, current, (revealed.candidates as Array).duplicate(true), registry))
	_session["has_more"] = (_session.candidates as Array).size() < mini(balance, unique_count)
	return {"ok": true, "session": session_view(profile)}


func select_candidate(state, session_id: String, candidate_id: String) -> Dictionary:
	if _session.is_empty():
		return CoreResult.failure("forge_session_required")
	if session_id.strip_edges().is_empty() or session_id != String(_session.get("session_id", "")):
		return CoreResult.failure("stale_forge_session")
	if String(_session.get("state", "")) == "prepared":
		return CoreResult.failure("commit_pending")
	var normalized_id := candidate_id.strip_edges()
	for candidate_value in (_session.candidates as Array):
		var candidate: Dictionary = candidate_value
		if String(candidate.candidate_id) == normalized_id:
			_session["state"] = "selected"
			_session["selected_candidate_id"] = normalized_id
			return {"ok": true, "session": session_view(state._profile)}
	return CoreResult.failure("candidate_not_revealed")


func cancel(state, session_id: String = "") -> Dictionary:
	if not session_id.strip_edges().is_empty() and ( _session.is_empty() or session_id != String(_session.get("session_id", "")) ):
		return CoreResult.failure("stale_forge_session")
	_pending_commit.clear()
	_session.clear()
	return {"ok": true, "session": session_view(state._profile)}


func prepare_commit(state, session_id: String) -> Dictionary:
	var profile: Dictionary = state._profile
	if _session.is_empty() or String(_session.get("state", "")) != "selected":
		return CoreResult.failure("candidate_not_selected")
	if session_id.strip_edges().is_empty() or session_id != String(_session.get("session_id", "")):
		return CoreResult.failure("stale_forge_session")
	if not _pending_commit.is_empty():
		return CoreResult.failure("commit_pending")
	var target_id := String(_session.target_instance_id)
	var current := ProfileRules.owned_equipment(profile, target_id)
	if current.is_empty() or current != _session.target_item:
		invalidate_session()
		return CoreResult.failure("stale_target")
	var selected := _selected_candidate()
	if selected.is_empty():
		return CoreResult.failure("candidate_not_selected")
	var registry: Variant = ProfileRules.loaded_item_registry()
	if registry == null:
		return CoreResult.failure("content_unavailable")
	var verified: Dictionary = LawForgeScript.new(registry).validate_candidate(
		current, String(_session.operation), selected, String(_session.session_id)
	)
	if not bool(verified.get("ok", false)):
		invalidate_session()
		return verified
	var operation := String(_session.operation)
	var cost := int(selected.cost)
	var tallies: Dictionary = (profile.resources as Dictionary).law_tallies
	if int(tallies.get(operation, 0)) < cost:
		return CoreResult.failure("insufficient_law_tallies")
	var next_profile := profile.duplicate(true)
	var equipment: Array = (next_profile.inventory as Dictionary).equipment
	var inventory_index := ProfileRules.equipment_index(equipment, target_id)
	if inventory_index < 0:
		invalidate_session()
		return CoreResult.failure("stale_target")
	equipment[inventory_index] = (selected.result_item as Dictionary).duplicate(true)
	var next_tallies: Dictionary = (next_profile.resources as Dictionary).law_tallies
	next_tallies[operation] = int(next_tallies[operation]) - cost
	var commit_token := "%s|%s" % [String(_session.session_id), String(selected.candidate_id)]
	commit_token = commit_token.sha256_text()
	_pending_commit = {
		"commit_token": commit_token,
		"next_profile": next_profile,
		"candidate": selected.duplicate(true),
	}
	_session["state"] = "prepared"
	return {
		"ok": true,
		"commit_token": commit_token,
		"operation": operation,
		"cost": cost,
		"candidate": selected.duplicate(true),
		"next_payload": ProfileCodec.payload_for_profile(next_profile, state._last_result, "base"),
		"session": session_view(profile),
	}.duplicate(true)


func finalize_commit(state, commit_token: String) -> Dictionary:
	if _pending_commit.is_empty() or String(_pending_commit.commit_token) != commit_token:
		return CoreResult.failure("invalid_commit_token")
	var candidate: Dictionary = (_pending_commit.candidate as Dictionary).duplicate(true)
	state._profile = (_pending_commit.next_profile as Dictionary).duplicate(true)
	_pending_commit.clear()
	_session.clear()
	return {
		"ok": true,
		"operation": String(candidate.operation),
		"cost": int(candidate.cost),
		"candidate": candidate,
		"result_item": (candidate.result_item as Dictionary).duplicate(true),
		"remaining_law_tallies": int(((state._profile.resources as Dictionary).law_tallies as Dictionary).get(String(candidate.operation), 0)),
	}.duplicate(true)


func abort_commit(state, commit_token: String) -> Dictionary:
	if _pending_commit.is_empty() or String(_pending_commit.commit_token) != commit_token:
		return CoreResult.failure("invalid_commit_token")
	_pending_commit.clear()
	_session["state"] = "selected"
	return {"ok": true, "session": session_view(state._profile)}


func session_view(profile: Dictionary) -> Dictionary:
	if _session.is_empty():
		return {
			"state": "idle",
			"session_id": "",
			"target_instance_id": "",
			"operation": "",
			"candidates": [],
			"selected_candidate_id": "",
			"revealed_count": 0,
			"affordable_count": 0,
			"has_more": false,
		}
	var view := _session.duplicate(true)
	view.erase("target_item")
	var operation := String(view.get("operation", ""))
	var balance := int(((profile.resources as Dictionary).law_tallies as Dictionary).get(operation, 0))
	var unique_count := int(view.get("unique_count", 0))
	var affordable_count := mini(balance, unique_count)
	view["revealed_count"] = (view.candidates as Array).size()
	view["affordable_count"] = affordable_count
	view["has_more"] = (view.candidates as Array).size() < affordable_count
	return view.duplicate(true)


func _default_target_id(profile: Dictionary, inventory_items: Array) -> String:
	var equipped: Dictionary = profile.active_build.equipped_item_ids
	var main_hand_id := String(equipped.get("main_hand", ""))
	if not main_hand_id.is_empty():
		for item in inventory_items:
			if String((item as Dictionary).get("instance_id", "")) == main_hand_id:
				return main_hand_id
	return String((inventory_items[0] as Dictionary).get("instance_id", "")) if not inventory_items.is_empty() else ""


func _set_context(profile: Dictionary, target_id: String, operation: String) -> Dictionary:
	var item := ProfileRules.owned_equipment(profile, target_id)
	if item.is_empty():
		return CoreResult.failure("item_not_owned")
	var affixes: Array = item.get("affixes", [])
	var affix_count := affixes.size()
	var blocked_reason := ""
	if operation == "inscribe":
		if affix_count >= LawForgeScript.MAX_AFFIXES:
			blocked_reason = "affix_limit_reached"
	elif operation in ["rewrite", "refine"]:
		if affix_count == 0:
			blocked_reason = "affix_required"
		elif operation == "rewrite":
			var registry: Variant = ProfileRules.loaded_item_registry()
			if registry == null or not bool(LawForgeScript.new(registry).validate_request(item, operation).get("ok", false)):
				blocked_reason = "rewrite_not_legal"
		elif operation == "refine":
			var has_eligible_affix := false
			for affix in affixes:
				if int((affix as Dictionary).get("tier", 0)) < LawForgeScript.MAX_TIER:
					has_eligible_affix = true
					break
			if not has_eligible_affix:
				blocked_reason = "max_tier"
	else:
		return CoreResult.failure("unknown_operation")
	var previous_revision := int(_context.get("revision", 0))
	var changed := _context.is_empty() \
		or String(_context.get("target_instance_id", "")) != target_id \
		or String(_context.get("operation", "")) != operation \
		or String(_context.get("blocked_reason", "")) != blocked_reason
	if changed:
		invalidate_session()
		_context = {
			"target_instance_id": target_id,
			"operation": operation,
			"blocked": not blocked_reason.is_empty(),
			"blocked_reason": blocked_reason,
			"revision": previous_revision + 1,
		}
	return {"ok": true, "context": _context.duplicate(true)}


func _item_view(item: Dictionary, registry: Variant) -> Dictionary:
	var view := item.duplicate(true)
	var base: Dictionary = registry.base_items.get(String(item.base_item_id), {})
	view["base_name"] = String(base.get("name", item.base_item_id))
	var visible_affixes: Array = []
	for raw_affix in (item.affixes as Array):
		var affix: Dictionary = raw_affix
		var family: Dictionary = registry.affix_families.get(String(affix.family_id), {})
		visible_affixes.append({
			"family_id": String(affix.family_id),
			"family_name": String(family.get("name", affix.family_id)),
			"tier": int(affix.tier),
		})
	view["affixes"] = visible_affixes
	return view


func _selected_candidate() -> Dictionary:
	var selected_id := String(_session.get("selected_candidate_id", ""))
	for candidate_value in (_session.get("candidates", []) as Array):
		var candidate: Dictionary = candidate_value
		if String(candidate.get("candidate_id", "")) == selected_id:
			return candidate.duplicate(true)
	return {}


func _enrich_candidates(profile: Dictionary, target_item: Dictionary, candidates: Array, registry: Variant) -> Array:
	var result: Array = candidates.duplicate(true)
	# Candidate result_item stays the exact LawForge authority payload. The sibling
	# view is deliberately presentation-only so validation and commit keep comparing
	# and applying the complete raw ItemInstance.
	for index in result.size():
		if not result[index] is Dictionary:
			continue
		var candidate: Dictionary = result[index]
		var result_item: Variant = candidate.get("result_item", {})
		if result_item is Dictionary:
			candidate["result_item_view"] = _item_view(result_item as Dictionary, registry)
			result[index] = candidate
	var slot := String(target_item.get("slot", ""))
	if slot not in EarlyItemRegistryScript.PROTOTYPE_OPEN_SLOTS:
		return result
	var inventory: Array = ((profile.inventory as Dictionary).equipment as Array).duplicate(true)
	var target_index := ProfileRules.equipment_index(inventory, String(target_item.get("instance_id", "")))
	if target_index < 0:
		return result
	var active_build: Dictionary = (profile.active_build as Dictionary).duplicate(true)
	var equipped_ids: Variant = active_build.get("equipped_item_ids", {})
	if not equipped_ids is Dictionary:
		return result
	var target_is_equipped := String((equipped_ids as Dictionary).get(slot, "")) == String(target_item.get("instance_id", ""))
	var current_resolved := BuildResolution.resolve_with_inventory(active_build, inventory, profile)
	if not bool(current_resolved.get("ok", false)):
		return result
	var current_parameters: Dictionary = (current_resolved.get("final_parameters", {}) as Dictionary).duplicate(true)
	var comparison_build: Dictionary = active_build.duplicate(true)
	if not target_is_equipped:
		(comparison_build.equipped_item_ids as Dictionary)[slot] = String(target_item.get("instance_id", ""))
	for index in result.size():
		if not result[index] is Dictionary:
			continue
		var candidate: Dictionary = result[index]
		var result_item: Variant = candidate.get("result_item", {})
		if not result_item is Dictionary:
			continue
		var result_inventory := inventory.duplicate(true)
		result_inventory[target_index] = (result_item as Dictionary).duplicate(true)
		var result_resolved := BuildResolution.resolve_with_inventory(comparison_build, result_inventory, profile)
		if not bool(result_resolved.get("ok", false)):
			continue
		var result_parameters: Dictionary = (result_resolved.get("final_parameters", {}) as Dictionary).duplicate(true)
		candidate["target_is_equipped"] = target_is_equipped
		candidate["preview_impact"] = "current_build_immediate" if target_is_equipped else "equip_after_commit"
		var current_interfaces := BuildResolution.resolved_connected_interfaces(current_resolved)
		var result_interfaces := BuildResolution.resolved_connected_interfaces(result_resolved)
		candidate["build_comparison"] = {
			"current_parameters": current_parameters.duplicate(true),
			"result_parameters": result_parameters.duplicate(true),
			"interfaces_gained": Collections.string_array_difference(result_interfaces, current_interfaces),
			"interfaces_lost": Collections.string_array_difference(current_interfaces, result_interfaces),
		}
		result[index] = candidate
	return result
