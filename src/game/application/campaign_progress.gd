extends RefCounted

## Campaign and story progression extracted from ApplicationState: the
## campaign node snapshot, fixed-node completion, repeatable side-contract
## bookkeeping, story evidence and growth discoveries. Static; the live profile
## dictionary is passed in and mutated in place.
const StoryProgressionScript = preload("res://src/systems/story_progression.gd")
const EarlyCampaignRegistryScript = preload("res://src/content/early_campaign_registry.gd")
const CoreResult := preload("res://src/core/result.gd")
const ProfileRules := preload("res://src/game/application/profile_rules.gd")


static func story_progress_for(source: Dictionary) -> Dictionary:
	var snapshot := (source.get("progression", {}) as Dictionary).duplicate(true)
	var records: Variant = source.get("discoveries", [])
	if records is Array:
		for record in records:
			if not record is Dictionary: continue
			if String(record.get("id", "")) == "first_equipment_find": snapshot["equipment_discovered"] = true
			if String(record.get("kind", "")) == "growth_state":
				snapshot["growth_observed"] = true
				if not snapshot.has("first_growth_state"): snapshot["first_growth_state"] = String(record.get("state", ""))
				if String(record.get("state", "")) == "exponential": snapshot["exponential_observed"] = true
	return snapshot


static func story_snapshot(profile: Dictionary) -> Dictionary:
	if profile.is_empty(): return {}
	return StoryProgressionScript.new().evaluate(story_progress_for(profile), profile.story)


static func mark_story_read(profile: Dictionary, active_session: Dictionary, entry_id: String) -> Dictionary:
	if profile.is_empty(): return CoreResult.failure("profile_required")
	if not active_session.is_empty(): return CoreResult.failure("story_locked")
	var available := false
	var story_state := story_snapshot(profile)
	for entry in story_state.get("journal_entries",[]) + story_state.get("available_conversations",[]):
		if String(entry.id) == entry_id: available = true
	if not available: return CoreResult.failure("story_entry_unavailable")
	profile.story = StoryProgressionScript.new().mark_entry_read(story_progress_for(profile), profile.story, entry_id)
	return {"ok":true}


static func is_valid_story(source: Dictionary) -> bool:
	var story: Variant = source.get("story")
	if not source.get("progression") is Dictionary: return false
	if not story is Dictionary or not ProfileRules.has_exact_keys(story,["schema_version","read_entry_ids"]): return false
	if not ProfileRules.is_exact_integer(story.schema_version) or int(story.schema_version) != 1 or not story.read_entry_ids is Array: return false
	var available: Dictionary = {}
	var story_state := StoryProgressionScript.new().evaluate(story_progress_for(source), {})
	for entry in story_state.get("journal_entries",[]) + story_state.get("available_conversations",[]):
		available[String(entry.id)] = true
	var seen := {}
	for value in story.read_entry_ids:
		if not ProfileRules.is_text(value) or not available.has(String(value)) or seen.has(String(value)): return false
		seen[String(value)] = true
	return true


static func campaign_snapshot(profile: Dictionary) -> Dictionary:
	if profile.is_empty():
		return CoreResult.failure("profile_required")
	var registry: Variant = ProfileRules.loaded_early_campaign_registry()
	if registry == null:
		return CoreResult.failure("content_unavailable")
	var completed: Array = ((profile.progression as Dictionary).completed_node_ids as Array).duplicate()
	var completed_lookup := {}
	for node_id_value in completed:
		completed_lookup[String(node_id_value)] = true
	var available: Array = []
	var locked: Array = []
	var fixed_order: Array[String] = registry.mainline_order()
	var ordered_ids: Array = fixed_order.duplicate()
	ordered_ids.append_array(repeatable_campaign_node_ids(registry))
	for node_id_value in ordered_ids:
		var node_id := String(node_id_value)
		var node: Dictionary = registry.get_node(node_id)
		if completed_lookup.has(node_id) and not bool(node.get("repeatable", false)):
			continue
		var unlocked := false
		for mode_value in (node.get("allowed_modes", []) as Array):
			if registry.is_unlocked(node_id, completed, String(mode_value)):
				unlocked = true
				break
		if unlocked:
			available.append(node_id)
		else:
			locked.append(node_id)
	var next_mainline_node_id := ""
	for node_id in fixed_order:
		if not completed_lookup.has(node_id):
			next_mainline_node_id = node_id
			break
	return {
		"ok": true,
		"completed_node_ids": completed,
		"earned_reward_tags": earned_reward_tags(registry, completed),
		"available_node_ids": available,
		"locked_node_ids": locked,
		"next_mainline_node_id": next_mainline_node_id,
		"early_game_complete": bool((profile.progression as Dictionary).early_game_complete),
	}.duplicate(true)


static func is_law_forge_unlocked(profile: Dictionary) -> bool:
	var progress := campaign_snapshot(profile)
	return bool(progress.get("ok", false)) and "law_forge_unlock" in (progress.earned_reward_tags as Array)


static func repeatable_campaign_node_ids(registry: Variant) -> Array:
	var file := FileAccess.open(EarlyCampaignRegistryScript.DEFAULT_PATH, FileAccess.READ)
	if file == null:
		return []
	var data: Variant = JSON.parse_string(file.get_as_text())
	if not (data is Dictionary):
		return []
	var templates: Variant = (data as Dictionary).get("repeatable_templates", [])
	if not (templates is Array):
		return []
	var result: Array = []
	for node_value in (templates as Array):
		if not (node_value is Dictionary):
			continue
		var node_id := String((node_value as Dictionary).get("id", ""))
		if not node_id.is_empty() and not registry.get_node(node_id).is_empty():
			result.append(node_id)
	return result


static func repeatable_side_template_ids() -> Array:
	var registry: Variant = ProfileRules.loaded_early_campaign_registry()
	if registry == null:
		return []
	return repeatable_campaign_node_ids(registry)


static func is_valid_repeatable_completion_counts(value: Variant) -> bool:
	if not (value is Dictionary):
		return false
	var allowed := {}
	for node_id in repeatable_side_template_ids():
		allowed[node_id] = true
	for key in (value as Dictionary):
		if not ProfileRules.is_text(key) or not allowed.has(String(key)):
			return false
		if not ProfileRules.is_non_negative_integer((value as Dictionary)[key]):
			return false
	return true


static func repeatable_attempt_for_session(profile: Dictionary, active_session: Dictionary) -> int:
	if profile.is_empty():
		return 0
	var contract_id := String(active_session.get("contract_id", ""))
	if contract_id not in repeatable_side_template_ids():
		return 0
	var progression: Dictionary = profile.progression
	var counts_value: Variant = progression.get("repeatable_completion_counts", {})
	var prior := 0
	if counts_value is Dictionary:
		var prior_value: Variant = (counts_value as Dictionary).get(contract_id, 0)
		prior = int(prior_value) if ProfileRules.is_non_negative_integer(prior_value) else 0
	return prior + 1


static func is_valid_completed_node_ids(value: Variant) -> bool:
	if not (value is Array):
		return false
	var registry: Variant = ProfileRules.loaded_early_campaign_registry()
	if registry == null:
		return false
	var fixed_order: Array[String] = registry.mainline_order()
	var previous_index := -1
	for node_id_value in (value as Array):
		if not ProfileRules.is_text(node_id_value):
			return false
		var node_id := String(node_id_value)
		var node_index := fixed_order.find(node_id)
		if node_index < 0 or node_index <= previous_index:
			return false
		previous_index = node_index
	return true


static func record_completed_node(profile: Dictionary, node_id: String, completed_mode: String = "") -> bool:
	var registry: Variant = ProfileRules.loaded_early_campaign_registry()
	if registry == null:
		return false
	var fixed_order: Array[String] = registry.mainline_order()
	if node_id not in fixed_order:
		return false
	var node: Dictionary = registry.get_node(node_id)
	if not completed_mode.is_empty() and completed_mode not in (node.get("allowed_modes", []) as Array):
		return false
	var progression: Dictionary = profile.progression
	var completed: Array = progression.completed_node_ids
	for prerequisite_value in (node.get("unlock_prerequisites", []) as Array):
		if String(prerequisite_value) not in completed:
			return false
	if node_id in completed:
		return false
	completed.append(node_id)
	completed.sort_custom(func(a: Variant, b: Variant) -> bool:
		return fixed_order.find(String(a)) < fixed_order.find(String(b))
	)
	return true


static func earned_reward_tags(registry: Variant, completed_node_ids: Array) -> Array:
	var completed := {}
	for node_id_value in completed_node_ids:
		completed[String(node_id_value)] = true
	var seen := {}
	var earned: Array = []
	for node_id in registry.mainline_order():
		if not completed.has(node_id):
			continue
		var node: Dictionary = registry.get_node(node_id)
		for tag_value in (node.get("first_reward_tags", []) as Array):
			var tag := String(tag_value)
			if not seen.has(tag):
				seen[tag] = true
				earned.append(tag)
	return earned


static func record_growth_discovery(profile: Dictionary, report: Dictionary) -> void:
	if String(report.get("state", "")) not in ["convergent", "critical", "exponential"]: return
	var discovery_id := "growth_%s" % String(report.state)
	for existing in (profile.discoveries as Array):
		if existing is Dictionary and String((existing as Dictionary).get("id", "")) == discovery_id:
			return
	(profile.discoveries as Array).append({
		"id": discovery_id,
		"kind": "growth_state",
		"state": String(report.state),
		"preset_id": String(report.preset_id),
		"p": float(report.p),
		"R": float(report.R),
		"build_fingerprint": String(report.get("build_fingerprint", "")),
		"source": String(report.get("source", "training")),
	})


static func refresh_early_game_completion(profile: Dictionary) -> void:
	var progression: Dictionary = profile.progression
	if "auto_certification" in (progression.completed_node_ids as Array):
		progression["early_game_complete"] = true
