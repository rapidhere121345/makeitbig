extends RefCounted

## Room equipment-drop settlement extracted from ApplicationState: folds the
## per-room loot ledger into the inventory, then rolls the deterministic
## session-level drops (including the repeatable side-contract pity guarantee).
## Static; the live profile and active session dictionaries are passed in.
const EquipmentDropGeneratorScript = preload("res://src/systems/equipment_drop_generator.gd")
const ProfileRules := preload("res://src/game/application/profile_rules.gd")
const CampaignProgress := preload("res://src/game/application/campaign_progress.gd")
const BossDiagnosis := preload("res://src/game/application/boss_diagnosis.gd")

const ROOM_EQUIPMENT_DROP_INDEX := 0
const PITY_SIDE_CONTRACT_ID := "side_affix_and_law_tallies"
const PITY_TRIGGER_PERIOD := 3
const PITY_EXPONENTIAL_P_THRESHOLD := 0.5
const PITY_TARGET_GROWTH := "piercing_continuation"
const PITY_TARGET_RANGE := "seeking_distance"
const PITY_TARGET_LIFETIME := "projectile_lifetime"
const PITY_TARGET_POWER := "carrier_power"


static func settle_room_equipment_drops(profile: Dictionary, active_session: Dictionary, result: Dictionary) -> void:
	var rewards_value: Variant = result.get("rewards", {})
	var rewards: Dictionary = rewards_value if rewards_value is Dictionary else {}
	var added: Array = []
	var ledger_room_indices: Dictionary = {}
	var ledger_items := _collect_room_loot_items(result, ledger_room_indices)
	for item_value: Variant in ledger_items:
		if item_value is Dictionary:
			var item: Dictionary = (item_value as Dictionary).duplicate(true)
			var registry: Variant = ProfileRules.loaded_item_registry()
			if registry != null and registry.validate_item_instance(item).is_empty():
				var instance_id := String(item.get("instance_id", ""))
				if not instance_id.is_empty() and ProfileRules.owned_equipment(profile, instance_id).is_empty():
					(((profile.inventory as Dictionary).equipment) as Array).append(item.duplicate(true))
					added.append(item.duplicate(true))
	var attempt_number := CampaignProgress.repeatable_attempt_for_session(profile, active_session)
	var pity_family := ""
	if attempt_number > 0:
		rewards["repeatable_attempt_number"] = attempt_number
		if String(active_session.get("contract_id", "")) == PITY_SIDE_CONTRACT_ID and attempt_number % PITY_TRIGGER_PERIOD == 0:
			var resolved_value: Variant = active_session.get("resolved_build", {})
			var resolved_build: Dictionary = resolved_value if resolved_value is Dictionary else {}
			pity_family = _pity_family_for_resolved_build(resolved_build)
	var outcome := String(result.get("outcome", "")).to_lower()
	if not profile.is_empty() and outcome in ["victory", "final_victory"] and _equipment_drops_unlocked_for_session(profile, active_session):
		added.append_array(_generate_new_room_equipment(profile, active_session, result, attempt_number, pity_family, rewards, ledger_room_indices))
	rewards["equipment_drops"] = added.duplicate(true)
	rewards["equipment_drop_count"] = added.size()
	result["rewards"] = rewards


static func _equipment_drops_unlocked_for_session(profile: Dictionary, active_session: Dictionary) -> bool:
	if not bool(profile.get("tutorial_complete", false)):
		return false
	var registry: Variant = ProfileRules.loaded_early_campaign_registry()
	if registry == null:
		return false
	var contract_id := String(active_session.get("contract_id", ""))
	if contract_id == "tutorial_ranger_basics":
		return false
	return registry.get_node(contract_id).is_empty() or registry.is_unlocked(
		contract_id, profile.progression.completed_node_ids, String(active_session.get("mode", ""))
	)


static func _generate_new_room_equipment(profile: Dictionary, active_session: Dictionary, result: Dictionary, attempt_number: int = 0, pity_family: String = "", rewards: Dictionary = {}, skip_room_indices: Dictionary = {}) -> Array:
	var plan_value: Variant = active_session.get("room_plan", {})
	if not plan_value is Dictionary:
		return []
	var rooms_value: Variant = (plan_value as Dictionary).get("rooms", [])
	if not rooms_value is Array:
		return []
	var rooms: Array = rooms_value
	var room_limit := rooms.size()
	if result.has("rooms_completed"):
		var completed_value: Variant = result.get("rooms_completed")
		room_limit = clampi(int(completed_value), 0, rooms.size()) if ProfileRules.is_exact_integer(completed_value) else 0
	var registry: Variant = ProfileRules.loaded_item_registry()
	if registry == null:
		return []
	var generator: RefCounted = EquipmentDropGeneratorScript.new(registry)
	var equipment: Array = ((profile.inventory as Dictionary).equipment as Array)
	var owned_ids := {}
	for existing in equipment:
		if existing is Dictionary:
			owned_ids[String((existing as Dictionary).get("instance_id", ""))] = true
	var seed := int(active_session.get("seed", 0))
	var pity_pending := not pity_family.is_empty()
	var added: Array = []
	for room_index in range(room_limit):
		if skip_room_indices.has(room_index):
			continue
		var room_value: Variant = rooms[room_index]
		if not room_value is Dictionary:
			continue
		var room: Dictionary = room_value
		var tags_value: Variant = room.get("drop_tags", [])
		if not tags_value is Array:
			continue
		var tags: Array = (tags_value as Array).duplicate()
		var room_id := String(room.get("room_id", "")).strip_edges()
		if room_id.is_empty():
			room_id = "room_%d" % room_index
		var source_id := "room_%s_%d" % [room_id.sha256_text(), room_index]
		if attempt_number > 0:
			source_id = "%s_attempt_%d" % [source_id, attempt_number]
		var guarantee := ""
		var guarantee_value: Variant = room.get("guarantee_family", "")
		if ProfileRules.is_text(guarantee_value):
			guarantee = String(guarantee_value)
		if pity_pending:
			if not _has_recognized_equipment_tag(tags):
				tags.append(EquipmentDropGeneratorScript.GENERAL_TAGS[0])
			guarantee = pity_family
		var item: Dictionary = generator.generate_drop(
			seed, source_id, ROOM_EQUIPMENT_DROP_INDEX, tags, guarantee
		)
		if item.is_empty() or not registry.validate_item_instance(item).is_empty():
			continue
		var instance_id := String(item.get("instance_id", ""))
		if instance_id.is_empty() or owned_ids.has(instance_id):
			continue
		var snapshot := item.duplicate(true)
		equipment.append(snapshot.duplicate(true))
		added.append(snapshot)
		owned_ids[instance_id] = true
		if pity_pending:
			pity_pending = false
			rewards["pity_guarantee_family"] = pity_family
	return added


static func _collect_room_loot_items(result: Dictionary, room_indices: Dictionary) -> Array[Dictionary]:
	var collected: Array[Dictionary] = []
	var room_results_value: Variant = result.get("room_results", [])
	if not room_results_value is Array:
		return collected
	for room_index in (room_results_value as Array).size():
		var room_value: Variant = (room_results_value as Array)[room_index]
		if not room_value is Dictionary:
			continue
		var settlement_value: Variant = (room_value as Dictionary).get("room_loot_settlement", {})
		if not settlement_value is Dictionary or (settlement_value as Dictionary).is_empty():
			continue
		room_indices[room_index] = true
		var items_value: Variant = (settlement_value as Dictionary).get("items", [])
		if items_value is Array:
			for item_value: Variant in items_value:
				if item_value is Dictionary:
					collected.append((item_value as Dictionary).duplicate(true))
	return collected


static func _has_recognized_equipment_tag(tags: Array) -> bool:
	for value in tags:
		if not (value is String):
			continue
		var tag := String(value).strip_edges()
		if tag in EquipmentDropGeneratorScript.GENERAL_TAGS or EquipmentDropGeneratorScript.SLOT_TAGS.has(tag) or EquipmentDropGeneratorScript.FAMILY_TAGS.has(tag):
			return true
	return false


static func _pity_family_for_resolved_build(resolved_build: Dictionary) -> String:
	var classification := String(resolved_build.get("growth_classification", "")).to_lower()
	var parameters_value: Variant = resolved_build.get("final_parameters", {})
	var parameters: Dictionary = parameters_value if parameters_value is Dictionary else {}
	var growth_p := BossDiagnosis.boss_parameter(parameters, "p", 0.0)
	if classification != "exponential" or growth_p <= PITY_EXPONENTIAL_P_THRESHOLD:
		return PITY_TARGET_GROWTH
	if BossDiagnosis.boss_parameter(parameters, "d", INF) < BossDiagnosis.BOSS_DIAGNOSIS_RANGE_MIN:
		return PITY_TARGET_RANGE
	if BossDiagnosis.boss_parameter(parameters, "T", INF) < BossDiagnosis.BOSS_DIAGNOSIS_LIFETIME_MIN:
		return PITY_TARGET_LIFETIME
	return PITY_TARGET_POWER
