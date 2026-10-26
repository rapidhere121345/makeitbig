class_name RouteSnapshots
extends RefCounted

## Route snapshot builders extracted from GameRoot. These assemble the loadout
## facility data, the campaign contract board, and the active-build view,
## reaching application state and the owner's last-contract and prototype-debug
## state through the untyped owner reference.
const CharacterProgressionScript = preload("res://src/systems/character_progression.gd")
const EarlyCampaignRegistryScript = preload("res://src/content/early_campaign_registry.gd")
const EarlyItemRegistryScript = preload("res://src/content/early_item_registry.gd")

var _root


func _init(root) -> void:
	_root = root


func _loadout_facility_snapshot() -> Dictionary:
	var snapshot: Dictionary = _root.application_state.early_game_snapshot().duplicate(true)
	if not bool(snapshot.get("ok", false)):
		return snapshot
	var profile_snapshot: Dictionary = _root.application_state.profile
	var inventory_value: Variant = profile_snapshot.get("inventory", {})
	var inventory: Dictionary = inventory_value if inventory_value is Dictionary else {}
	var equipment_value: Variant = inventory.get("equipment", [])
	snapshot["inventory_equipment"] = (equipment_value as Array).duplicate(true) if equipment_value is Array else []
	snapshot["resolved_build"] = _root.application_state.resolved_build_snapshot().duplicate(true)
	var equip_previews := {}
	var salvage_previews := {}
	for item_value in (snapshot.inventory_equipment as Array):
		if not item_value is Dictionary:
			continue
		var instance_id := String((item_value as Dictionary).get("instance_id", ""))
		var preview: Dictionary = _root.application_state.preview_equip_item(instance_id)
		if bool(preview.get("ok", false)):
			equip_previews[instance_id] = preview.duplicate(true)
		var salvage: Dictionary = _root.application_state.salvage_item_preview(instance_id)
		if bool(salvage.get("ok", false)):
			salvage_previews[instance_id] = salvage.duplicate(true)
	snapshot["equip_previews"] = equip_previews
	snapshot["salvage_previews"] = salvage_previews
	snapshot["equipment_slots"] = EarlyItemRegistryScript.EQUIPMENT_SLOTS.duplicate()
	snapshot["prototype_open_slots"] = EarlyItemRegistryScript.PROTOTYPE_OPEN_SLOTS.duplicate()
	var registry = EarlyItemRegistryScript.new()
	var load_errors: Array[String] = registry.load_all()
	if not load_errors.is_empty():
		snapshot["loadout_errors"] = load_errors.duplicate()
		return snapshot
	snapshot["base_items"] = registry.base_items.duplicate(true)
	snapshot["affix_families"] = registry.affix_families.duplicate(true)
	return snapshot


func _campaign_contract_snapshot() -> Dictionary:
	var progress: Dictionary = _root.application_state.campaign_progress_snapshot()
	if not bool(progress.get("ok", false)):
		return progress
	var registry = EarlyCampaignRegistryScript.new()
	var load_errors: Array[String] = registry.load_campaign()
	if not load_errors.is_empty():
		return {"ok": false, "error": "campaign_content_invalid", "details": load_errors.duplicate()}
	var completed_value: Variant = progress.get("completed_node_ids", [])
	var available_value: Variant = progress.get("available_node_ids", [])
	var completed: Array = completed_value if completed_value is Array else []
	var available: Array = available_value if available_value is Array else []
	var profile_snapshot: Dictionary = _root.application_state.profile
	var progression_value: Variant = profile_snapshot.get("progression", {})
	var progression: Dictionary = progression_value if progression_value is Dictionary else {}
	var repeatable_counts_value: Variant = progression.get("repeatable_completion_counts", {})
	var repeatable_counts: Dictionary = repeatable_counts_value if repeatable_counts_value is Dictionary else {}
	var node_ids: Array[String] = registry.mainline_order()
	for side_id in _root.EARLY_SIDE_NODE_IDS:
		node_ids.append(side_id)
	var nodes: Array[Dictionary] = []
	for node_id in node_ids:
		var node: Dictionary = registry.get_node(node_id)
		if node.is_empty():
			continue
		var room_count := 1
		if node.has("room_sequence") and node.room_sequence is Array:
			room_count = maxi(1, (node.room_sequence as Array).size())
		elif node.has("room_template") and node.room_template is Dictionary:
			room_count = maxi(1, int((node.room_template as Dictionary).get("room_count", 1)))
		var node_snapshot := {
			"id": node_id,
			"kind": String(node.get("kind", "")),
			"available": node_id in available,
			"completed": node_id in completed,
			"repeatable": bool(node.get("repeatable", false)),
			"allowed_modes": (node.get("allowed_modes", []) as Array).duplicate(),
			"room_count": room_count,
			"drop_tags": (node.get("drop_tags", []) as Array).duplicate(),
			"first_reward_tags": (node.get("first_reward_tags", []) as Array).duplicate(),
			"experience_reward": CharacterProgressionScript.contract_experience(node_id, node_id not in completed),
			"unlock_prerequisites": (node.get("unlock_prerequisites", []) as Array).duplicate(),
		}
		if bool(node_snapshot.repeatable):
			var completion_count := maxi(0, int(repeatable_counts.get(node_id, 0)))
			var suggested_seed := int(_root.DEFAULT_CONTRACT.seed) + completion_count
			if String(_root._last_contract.get("contract_id", "")) == node_id:
				suggested_seed = int(_root._last_contract.get("seed", suggested_seed))
				var last_outcome := String(_root.application_state.last_result.get("outcome", "")).to_lower()
				if last_outcome in ["victory", "final_victory"]:
					suggested_seed = suggested_seed + 1 if suggested_seed < 2147483647 else -2147483648
			node_snapshot["completion_count"] = completion_count
			node_snapshot["next_attempt_number"] = completion_count + 1
			node_snapshot["suggested_seed"] = suggested_seed
		if _root._prototype_debug_has_seed:
			node_snapshot["suggested_seed"] = _root._prototype_debug_seed_override
		nodes.append(node_snapshot)
	var result := progress.duplicate(true)
	result["nodes"] = nodes
	return result


func _active_build_from_snapshot(snapshot: Dictionary) -> Dictionary:
	var nested: Variant = snapshot.get("active_build", snapshot)
	return (nested as Dictionary).duplicate(true) if nested is Dictionary else {}
