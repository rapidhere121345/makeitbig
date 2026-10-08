class_name StoryProgression
extends RefCounted

const StoryRegistryScript = preload("res://src/content/story_registry.gd")
const DEFAULT_SAVED_STORY := {"schema_version": 1, "read_entry_ids": []}

var registry: StoryRegistry


func _init(story_registry: StoryRegistry = null) -> void:
	registry = story_registry if story_registry != null else StoryRegistryScript.new()
	if not registry.is_loaded():
		registry.load_story()


func evaluate(progress_snapshot: Dictionary, saved_story: Dictionary) -> Dictionary:
	var completed := _completed_ids(progress_snapshot)
	var flags := _flags(progress_snapshot)
	var read_ids := _read_ids(saved_story)
	var reached_units: Array[Dictionary] = []
	var current_unit := {}
	var highest_stage := -1
	for unit in registry.story_units():
		if not _requirements_met(unit.requires, completed, flags):
			continue
		reached_units.append(unit)
		if int(unit.stage) > highest_stage:
			highest_stage = int(unit.stage)
			current_unit = unit

	var journal_entries: Array[Dictionary] = []
	var available_conversations: Array[Dictionary] = []
	var town_changes: Array[Dictionary] = []
	for unit in reached_units:
		if int(unit.stage) == 3:
			var reaction := registry.growth_reaction(String(progress_snapshot.get("first_growth_state", "")))
			if not reaction.is_empty():
				unit.title = reaction.title
				unit.journal.pages = reaction.journal_pages.duplicate()
				unit.conversations[0].title = reaction.title
				unit.conversations[0].pages = reaction.conversation_pages.duplicate()
		var journal: Dictionary = (unit.journal as Dictionary).duplicate(true)
		journal["unit_id"] = String(unit.id)
		journal["stage"] = int(unit.stage)
		journal["title"] = String(unit.title)
		var journal_id := String(journal.id)
		journal["is_read"] = read_ids.has(journal_id)
		journal_entries.append(journal)
		for conversation_value in unit.conversations:
			var conversation: Dictionary = (conversation_value as Dictionary).duplicate(true)
			var npc: Dictionary = registry.get_npc(String(conversation.npc))
			conversation["npc_name"] = String(npc.get("name", "未知"))
			conversation["stage"] = int(unit.stage)
			conversation["is_read"] = read_ids.has(String(conversation.id))
			available_conversations.append(conversation)
		for change_value in unit.town_changes:
			town_changes.append((change_value as Dictionary).duplicate(true))

	# Quest navigation follows available contracts; optional discoveries never
	# force reading/training or send a progressed player back to an earlier node.
	for entry in registry.objectives():
		if _requirements_met(entry.requires, completed, flags):
			current_unit = {"objective": entry.objective}
	return {
		"journal_entries": journal_entries,
		"available_conversations": available_conversations,
		"current_objective": _objective_for(current_unit, progress_snapshot),
		"town_changes": town_changes,
	}


func mark_entry_read(progress_snapshot: Dictionary, saved_story: Dictionary, entry_id: String) -> Dictionary:
	var normalized := normalize_saved_story(saved_story)
	var state := evaluate(progress_snapshot, normalized)
	var valid := false
	for entry in state.journal_entries + state.available_conversations:
		if String(entry.id) == entry_id:
			valid = true
			break
	if not valid:
		return normalized
	var ids := _read_ids(normalized)
	ids[entry_id] = true
	var ordered: Array[String] = []
	for raw_id in normalized.get("read_entry_ids", []):
		var source_id := String(raw_id)
		if ids.has(source_id) and not ordered.has(source_id):
			ordered.append(source_id)
	if not ordered.has(entry_id):
		ordered.append(entry_id)
	return {"schema_version": 1, "read_entry_ids": ordered}


func normalize_saved_story(saved_story: Dictionary) -> Dictionary:
	return {"schema_version": 1, "read_entry_ids": _read_ids(saved_story).keys()}


func default_saved_story() -> Dictionary:
	return DEFAULT_SAVED_STORY.duplicate(true)


func _objective_for(unit: Dictionary, snapshot: Dictionary) -> Dictionary:
	if unit.is_empty():
		return {"id": "story_not_started", "text": "完成起步练习，进入旧路外段", "campaign_node": "tutorial_ranger_basics"}
	var objective: Dictionary = (unit.objective as Dictionary).duplicate(true)
	return objective


func _requirements_met(requirements: Dictionary, completed: Dictionary, flags: Dictionary) -> bool:
	for node in requirements.get("completed_nodes", []):
		if not completed.has(String(node)):
			return false
	for flag in requirements.get("flags", []):
		if not flags.has(String(flag)):
			return false
	return true


func _completed_ids(snapshot: Dictionary) -> Dictionary:
	var result := {}
	var value: Variant = snapshot.get("completed_node_ids", [])
	if value is Array:
		for node in value:
			if node is String or node is StringName:
				result[String(node)] = true
	return result


func _flags(snapshot: Dictionary) -> Dictionary:
	var result := {}
	if bool(snapshot.get("proxy_unlocked", false)):
		result["proxy_unlocked"] = true
	if bool(snapshot.get("early_game_complete", false)):
		result["early_game_complete"] = true
	for flag in ["equipment_discovered", "growth_observed", "exponential_observed"]:
		if bool(snapshot.get(flag, false)): result[flag] = true
	return result


func _read_ids(saved_story: Dictionary) -> Dictionary:
	var result := {}
	var value: Variant = saved_story.get("read_entry_ids", [])
	if value is Array:
		for entry_id in value:
			if entry_id is String or entry_id is StringName:
				result[String(entry_id)] = true
	return result
