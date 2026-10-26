extends RefCounted

## Equipment/inventory transactions extracted from ApplicationState: equip,
## try-on preview, unequip, salvage preview/commit and the inventory merge
## helpers. Static; the live profile dictionary is passed in and mutated in
## place. Forge-session invalidation after a salvage stays with the owner.
const EarlyItemRegistryScript = preload("res://src/content/early_item_registry.gd")
const CoreResult := preload("res://src/core/result.gd")
const Collections := preload("res://src/core/collections.gd")
const ProfileRules := preload("res://src/game/application/profile_rules.gd")
const BuildResolution := preload("res://src/game/application/build_resolution.gd")

const SALVAGE_REFUND_TALLIES := 1


static func equip_item(profile: Dictionary, instance_id: String) -> Dictionary:
	if profile.is_empty():
		return CoreResult.failure("profile_required")
	var normalized_id := instance_id.strip_edges()
	if normalized_id.is_empty():
		return CoreResult.failure("invalid_instance_id")
	var item := ProfileRules.owned_equipment(profile, normalized_id)
	if item.is_empty():
		return CoreResult.failure("item_not_owned")
	var registry: Variant = ProfileRules.loaded_item_registry()
	if registry == null or not registry.validate_item_instance(item).is_empty():
		return CoreResult.failure("invalid_item_instance")
	var slot := String(item.slot)
	if slot not in EarlyItemRegistryScript.PROTOTYPE_OPEN_SLOTS:
		return CoreResult.failure("slot_not_prototype_open")
	var active: Dictionary = (profile.active_build as Dictionary).duplicate(true)
	var equipped: Dictionary = active.equipped_item_ids
	for equipped_slot in EarlyItemRegistryScript.EQUIPMENT_SLOTS:
		if String(equipped.get(equipped_slot, "")) == normalized_id:
			return CoreResult.failure("item_already_equipped")
	equipped[slot] = normalized_id
	var resolved := BuildResolution.resolve_active_build(profile, active)
	if not bool(resolved.get("ok", false)):
		return CoreResult.failure("build_resolution_failed")
	profile["active_build"] = active
	return {"ok": true, "active_build": active.duplicate(true), "resolved_build": resolved.duplicate(true)}


## Read-only "try-on" preview for FacilityScreen's equip_previews contract.
## Validation order mirrors equip_item exactly. Nothing is persisted: the preview
## resolves a deep copy of active_build with the target slot replaced, through the
## single authoritative path BuildResolution.resolve_active_build. Deltas are computed against the
## current authoritative resolution; tags stay empty because the resolved Build
## exposes no authoritative tag set (never inferred from item affixes).
static func preview_equip_item(profile: Dictionary, instance_id: String) -> Dictionary:
	if profile.is_empty():
		return CoreResult.failure("profile_required")
	var normalized_id := instance_id.strip_edges()
	if normalized_id.is_empty():
		return CoreResult.failure("invalid_instance_id")
	var item := ProfileRules.owned_equipment(profile, normalized_id)
	if item.is_empty():
		return CoreResult.failure("item_not_owned")
	var registry: Variant = ProfileRules.loaded_item_registry()
	if registry == null or not registry.validate_item_instance(item).is_empty():
		return CoreResult.failure("invalid_item_instance")
	var slot := String(item.slot)
	if slot not in EarlyItemRegistryScript.PROTOTYPE_OPEN_SLOTS:
		return CoreResult.failure("slot_not_prototype_open")
	var active: Dictionary = (profile.active_build as Dictionary).duplicate(true)
	var equipped: Dictionary = active.equipped_item_ids
	for equipped_slot in EarlyItemRegistryScript.EQUIPMENT_SLOTS:
		if String(equipped.get(equipped_slot, "")) == normalized_id:
			return CoreResult.failure("item_already_equipped")
	var current_resolved := BuildResolution.resolve_active_build(profile, active)
	if not bool(current_resolved.get("ok", false)):
		return CoreResult.failure("build_resolution_failed")
	equipped[slot] = normalized_id
	var next_resolved := BuildResolution.resolve_active_build(profile, active)
	if not bool(next_resolved.get("ok", false)):
		return CoreResult.failure("build_resolution_failed")
	var current_connected := BuildResolution.resolved_connected_interfaces(current_resolved)
	var next_connected := BuildResolution.resolved_connected_interfaces(next_resolved)
	var current_tags := BuildResolution.resolved_tag_ids(current_resolved)
	var next_tags := BuildResolution.resolved_tag_ids(next_resolved)
	return {
		"ok": true,
		"instance_id": normalized_id,
		"slot": slot,
		"final_parameters": (next_resolved.final_parameters as Dictionary).duplicate(true),
		"growth_classification": String(next_resolved.growth_classification),
		"build_fingerprint": String(next_resolved.build_fingerprint),
		"interfaces_gained": Collections.string_array_difference(next_connected, current_connected),
		"interfaces_lost": Collections.string_array_difference(current_connected, next_connected),
		"tags_gained": Collections.string_array_difference(next_tags, current_tags),
		"tags_lost": Collections.string_array_difference(current_tags, next_tags),
		"current_resolved": current_resolved.duplicate(true),
		"resolved_build": next_resolved.duplicate(true),
	}


## Prototype equipment salvage truth chain.
## Every owned, registry-valid ItemInstance may be salvaged, including starting
## and calibration equipment. If the target is equipped, assessment first builds
## and resolves an unequipped active_build candidate. Commit publishes that valid
## build together with inventory removal, so no persisted slot can retain a
## dangling instance id. Preview and commit use the same assessment and the
## domain remains authoritative for the Law Tally refund.
static func salvage_item_preview(profile: Dictionary, instance_id: String) -> Dictionary:
	if profile.is_empty():
		return CoreResult.failure("profile_required")
	var normalized_id := instance_id.strip_edges()
	if normalized_id.is_empty():
		return CoreResult.failure("invalid_instance_id")
	var assessment := _salvage_assessment(profile, normalized_id)
	if not bool(assessment.get("ok", false)):
		return assessment
	return {
		"ok": true,
		"instance_id": normalized_id,
		"operation": String(assessment.operation),
		"amount": SALVAGE_REFUND_TALLIES,
		"equipped_slot": String(assessment.get("equipped_slot", "")),
		"item": (assessment.item as Dictionary).duplicate(true),
	}


static func salvage_item(profile: Dictionary, instance_id: String) -> Dictionary:
	if profile.is_empty():
		return CoreResult.failure("profile_required")
	var normalized_id := instance_id.strip_edges()
	if normalized_id.is_empty():
		return CoreResult.failure("invalid_instance_id")
	var assessment := _salvage_assessment(profile, normalized_id)
	if not bool(assessment.get("ok", false)):
		return assessment
	var equipment: Array = (profile.inventory as Dictionary).equipment
	var inventory_index := -1
	for index in equipment.size():
		if equipment[index] is Dictionary and String((equipment[index] as Dictionary).get("instance_id", "")) == normalized_id:
			inventory_index = index
			break
	if inventory_index < 0:
		return CoreResult.failure("item_not_owned")
	var salvaged: Dictionary = (equipment[inventory_index] as Dictionary).duplicate(true)
	var next_active: Dictionary = (assessment.next_active_build as Dictionary).duplicate(true)
	equipment.remove_at(inventory_index)
	profile["active_build"] = next_active
	var operation := String(assessment.operation)
	var tallies: Dictionary = (profile.resources as Dictionary).law_tallies
	tallies[operation] = int(tallies.get(operation, 0)) + SALVAGE_REFUND_TALLIES
	return {
		"ok": true,
		"instance_id": normalized_id,
		"operation": operation,
		"amount": SALVAGE_REFUND_TALLIES,
		"unequipped_slot": String(assessment.get("equipped_slot", "")),
		"active_build": next_active.duplicate(true),
		"salvaged_item": salvaged,
	}


## Shared read-only validation for preview and commit. Both surfaces must fail
## closed with the same codes and must never mutate profile state.
static func _salvage_assessment(profile: Dictionary, normalized_id: String) -> Dictionary:
	var item := ProfileRules.owned_equipment(profile, normalized_id)
	if item.is_empty():
		return CoreResult.failure("item_not_owned")
	var registry: Variant = ProfileRules.loaded_item_registry()
	if registry == null or not registry.validate_item_instance(item).is_empty():
		return CoreResult.failure("invalid_item_instance")
	var active: Dictionary = (profile.active_build as Dictionary).duplicate(true)
	var equipped: Dictionary = active.equipped_item_ids
	var equipped_slot := ""
	for loop_slot in EarlyItemRegistryScript.EQUIPMENT_SLOTS:
		if String(equipped.get(loop_slot, "")) == normalized_id:
			equipped_slot = String(loop_slot)
			break
	if not equipped_slot.is_empty():
		equipped[equipped_slot] = ""
		var resolved := BuildResolution.resolve_active_build(profile, active)
		if not bool(resolved.get("ok", false)):
			return CoreResult.failure("build_resolution_failed")
	return {
		"ok": true,
		"item": item,
		"operation": _salvage_operation(item),
		"equipped_slot": equipped_slot,
		"next_active_build": active,
	}


## Deterministic cross-process refund track: stable item identity fields only.
## sha256(instance_id|law_seed) % 3 selects inscribe/rewrite/refine.
static func _salvage_operation(item: Dictionary) -> String:
	var identity := "%s|%d" % [String(item.get("instance_id", "")), int(item.get("law_seed", 0))]
	var digest := identity.sha256_text()
	var bucket := int(("0x" + digest.substr(0, 8)).hex_to_int()) % ProfileRules.FORGE_OPERATIONS.size()
	return ProfileRules.FORGE_OPERATIONS[bucket]


static func unequip_item(profile: Dictionary, slot: String) -> Dictionary:
	if profile.is_empty():
		return CoreResult.failure("profile_required")
	var normalized_slot := slot.strip_edges().to_lower()
	if normalized_slot not in EarlyItemRegistryScript.PROTOTYPE_OPEN_SLOTS:
		return CoreResult.failure("slot_not_prototype_open")
	var active: Dictionary = (profile.active_build as Dictionary).duplicate(true)
	(active.equipped_item_ids as Dictionary)[normalized_slot] = ""
	var resolved := BuildResolution.resolve_active_build(profile, active)
	if not bool(resolved.get("ok", false)):
		return CoreResult.failure("build_resolution_failed")
	profile["active_build"] = active
	return {"ok": true, "active_build": active.duplicate(true), "resolved_build": resolved.duplicate(true)}


static func merge_equipment_inventory(profile: Dictionary, items: Array) -> void:
	var equipment: Array = (profile.inventory as Dictionary).equipment
	for item in items:
		_append_unique_equipment(equipment, item)


static func _append_unique_equipment(equipment: Array, item: Variant) -> void:
	if not item is Dictionary:
		return
	var instance_id := String((item as Dictionary).get("instance_id", ""))
	for existing in equipment:
		if existing is Dictionary and String((existing as Dictionary).get("instance_id", "")) == instance_id:
			return
	equipment.append((item as Dictionary).duplicate(true))
