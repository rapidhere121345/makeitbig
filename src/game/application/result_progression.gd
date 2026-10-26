extends RefCounted

## Contract-result progression extracted from ApplicationState: first-clear
## campaign completion and reward grants, the first-kill proxy unlock, Auto
## wins, Law Tally and legacy-drop settlement, auto-certification graduation
## and the story evidence a finished session leaves behind. Static; the live
## profile and active session dictionaries are passed in.
const ProfileRules := preload("res://src/game/application/profile_rules.gd")
const CampaignProgress := preload("res://src/game/application/campaign_progress.gd")
const ProxyBuilds := preload("res://src/game/application/proxy_builds.gd")

const STABLE_FIRST_REWARD_ITEMS := {
	"breeding_split_item": "reward_mainline_03_breeding_split_gloves",
	"pack_hunt_mark_item": "reward_mainline_05_pack_hunt_mark_ring",
}


static func is_auto_certification_graduation(profile: Dictionary, active_session: Dictionary, result: Dictionary) -> bool:
	if String(result.get("outcome", "")).to_lower() != "victory":
		return false
	if not _is_auto_certification_eligible(profile, active_session):
		return false
	var completed: Array = (profile.progression as Dictionary).completed_node_ids
	return "auto_certification" not in completed


static func _is_auto_certification_eligible(profile: Dictionary, active_session: Dictionary) -> bool:
	if String(active_session.get("contract_id", "")) != "auto_certification":
		return false
	if String(active_session.get("mode", "")) != "Auto":
		return false
	if profile.is_empty():
		return false
	var completed_value: Variant = (profile.progression as Dictionary).get("completed_node_ids", [])
	return completed_value is Array and "threshold_colossus" in (completed_value as Array)


static func apply_result_progression(profile: Dictionary, active_session: Dictionary, result: Dictionary) -> void:
	result["first_reward_tags"] = []
	result["proxy_component_drops"] = []
	var outcome := String(result.get("outcome", "")).to_lower()
	if profile.is_empty() or outcome not in ["victory", "final_victory"]:
		return
	var progression: Dictionary = profile.progression
	var completed_mode := String(active_session.get("mode", ""))
	var completed_contract_id := String(active_session.get("contract_id", ""))
	var rewards_value: Variant = result.get("rewards", {})
	var rewards: Dictionary = rewards_value if rewards_value is Dictionary else {}
	var wins_delta := _safe_reward_delta(rewards.get("contract_wins_delta", 1))
	var tallies_delta_value: Variant = rewards.get("law_tallies_delta", {})
	var tallies_delta: Dictionary = tallies_delta_value if tallies_delta_value is Dictionary else {}
	progression["contract_wins"] = int(progression.get("contract_wins", 0)) + wins_delta
	if completed_contract_id in CampaignProgress.repeatable_side_template_ids():
		if not progression.has("repeatable_completion_counts") or not (progression.repeatable_completion_counts is Dictionary):
			progression["repeatable_completion_counts"] = {}
		var counts: Dictionary = progression.repeatable_completion_counts
		var prior: Variant = counts.get(completed_contract_id, 0)
		counts[completed_contract_id] = (int(prior) if ProfileRules.is_non_negative_integer(prior) else 0) + 1
	if outcome == "final_victory":
		progression["ending_unlocked"] = true
	var first_fixed_completion := CampaignProgress.record_completed_node(profile, completed_contract_id, completed_mode)
	if first_fixed_completion:
		var registry: Variant = ProfileRules.loaded_early_campaign_registry()
		if registry != null:
			var completed_node: Dictionary = registry.get_node(completed_contract_id)
			var first_reward_tags: Array = (completed_node.get("first_reward_tags", []) as Array).duplicate(true)
			result["first_reward_tags"] = first_reward_tags.duplicate(true)
			var granted_items := _apply_first_reward_tags(profile, first_reward_tags)
			_append_granted_equipment_to_result(result, granted_items)
	if completed_contract_id == "threshold_colossus" and completed_mode == "Manual" and first_fixed_completion:
		progression["threshold_colossus_defeated"] = true
		progression["proxy_unlocked"] = true
		var granted := ProxyBuilds.grant_initial(profile, String(active_session.get("contract_id", "")))
		result["unlock"] = {
			"proxy_unlocked": true,
			"title": "First-kill proxy unlocked",
			"components": granted.duplicate(true),
		}
	if completed_mode == "Auto" and bool(progression.get("proxy_unlocked", false)):
		progression["auto_contract_wins"] = int(progression.get("auto_contract_wins", 0)) + 1
		var auto_win_number := int(progression.auto_contract_wins)
		if auto_win_number <= ProxyBuilds.AUTO_PROXY_REWARD_IDS.size():
			var dropped := ProxyBuilds.grant_core(profile, ProxyBuilds.AUTO_PROXY_REWARD_IDS[auto_win_number - 1], completed_contract_id)
			if not dropped.is_empty():
				result["proxy_component_drops"] = [dropped.duplicate(true)]
		progression["early_game_complete"] = "auto_certification" in (progression.completed_node_ids as Array)
	var law_tallies: Dictionary = (profile.resources as Dictionary).law_tallies
	for operation in ProfileRules.FORGE_OPERATIONS:
		law_tallies[operation] = int(law_tallies.get(operation, 0)) + _safe_reward_delta(tallies_delta.get(operation, 0))
	var drop_id := String(rewards.get("drop_id", "")).strip_edges()
	if not drop_id.is_empty():
		((profile.inventory as Dictionary).legacy_drops as Array).append({
			"id": drop_id,
			"label": String(rewards.get("drop_label", drop_id)),
			"source_contract": String(active_session.get("contract_id", "")),
		})


static func record_story_result_evidence(profile: Dictionary, active_session: Dictionary, result: Dictionary) -> void:
	var drops: Array = result.get("rewards", {}).get("equipment_drops", [])
	if not drops.is_empty():
		var already_seen := false
		for record in profile.discoveries:
			if record is Dictionary and String(record.get("id", "")) == "first_equipment_find": already_seen = true
		if not already_seen:
			profile.discoveries.append({"id":"first_equipment_find", "kind":"equipment_find", "instance_id":String(drops[0].get("instance_id", ""))})
	var frozen: Dictionary = active_session.get("resolved_build", {})
	if String(frozen.get("build_fingerprint", "")).is_empty(): return
	for room in result.get("room_results", []):
		if not room is Dictionary: continue
		if int(room.get("arrow_hits", 0)) <= 0 or String(room.get("build_fingerprint", "")) != String(frozen.get("build_fingerprint", "")): continue
		var parameters: Dictionary = frozen.get("final_parameters", {})
		CampaignProgress.record_growth_discovery(profile, {"state":String(frozen.get("growth_classification", "")), "preset_id":String(active_session.get("preset_id", "")), "p":float(parameters.get("p", 0)), "R":float(frozen.get("R", 0)), "build_fingerprint":String(frozen.build_fingerprint), "source":"combat"})
		break


static func _apply_first_reward_tags(profile: Dictionary, tags: Array) -> Array:
	var active: Dictionary = profile.active_build
	var stable_item_ids: Array[String] = []
	for tag_value in tags:
		var tag := String(tag_value)
		match tag:
			"hunter_mark_skill":
				_grant_skill_slot(active.skills as Array, "hunter_mark", 1)
			"dash_skill":
				_grant_skill_slot(active.skills as Array, "dash", 2)
		if STABLE_FIRST_REWARD_ITEMS.has(tag):
			stable_item_ids.append(String(STABLE_FIRST_REWARD_ITEMS[tag]))
	return _grant_stable_reward_items(profile, stable_item_ids)


## Stable semantic rewards enter inventory as immutable ItemInstance snapshots.
## They never write rune/law fields into active_build and only affect resolution
## after the player equips their instance_id in the matching slot.
static func _grant_stable_reward_items(profile: Dictionary, instance_ids: Array[String]) -> Array:
	if instance_ids.is_empty():
		return []
	var registry: Variant = ProfileRules.loaded_item_registry()
	if registry == null:
		return []
	var equipment: Array = ((profile.inventory as Dictionary).equipment as Array)
	var owned_ids := {}
	for value in equipment:
		if value is Dictionary:
			owned_ids[String((value as Dictionary).get("instance_id", ""))] = true
	var candidates: Array = []
	for instance_id in instance_ids:
		if owned_ids.has(instance_id):
			continue
		var item_value: Variant = registry.item_instances.get(instance_id, {})
		if not (item_value is Dictionary):
			return []
		var item: Dictionary = (item_value as Dictionary).duplicate(true)
		if not registry.validate_item_instance(item).is_empty():
			return []
		candidates.append(item)
	for item_value in candidates:
		var item: Dictionary = item_value
		equipment.append(item.duplicate(true))
	return candidates.duplicate(true)


static func _append_granted_equipment_to_result(result: Dictionary, granted: Array) -> void:
	if granted.is_empty():
		return
	var rewards_value: Variant = result.get("rewards", {})
	var rewards: Dictionary = rewards_value.duplicate(true) if rewards_value is Dictionary else {}
	var drops_value: Variant = rewards.get("equipment_drops", [])
	var drops: Array = drops_value.duplicate(true) if drops_value is Array else []
	for item in granted:
		drops.append((item as Dictionary).duplicate(true))
	rewards["equipment_drops"] = drops
	rewards["equipment_drop_count"] = drops.size()
	result["rewards"] = rewards


static func _grant_skill_slot(skills: Array, skill_id: String, slot_index: int) -> void:
	if slot_index < 0 or slot_index >= skills.size() or String(skills[slot_index]) == skill_id:
		return
	if not String(skills[slot_index]).is_empty():
		return
	var existing_index := skills.find(skill_id)
	if existing_index >= 0:
		skills[existing_index] = ""
	skills[slot_index] = skill_id


static func _safe_reward_delta(value: Variant) -> int:
	return int(value) if typeof(value) == TYPE_INT and int(value) >= 0 else 0
