class_name StoryRegistry
extends RefCounted

const DEFAULT_PATH := "res://content/chapter_one_story.json"
const SCHEMA_VERSION := 1
const CAMPAIGN_NODES: Array[String] = [
	"tutorial_ranger_basics", "mainline_01_first_hunt", "mainline_02_priority_under_pressure",
	"mainline_03_first_elite", "mainline_04_hazard_and_forge", "mainline_05_growth_gate",
	"threshold_colossus", "auto_certification",
]
const TOP_LEVEL_FIELDS: Array[String] = ["schema_version", "chapter_id", "title", "campaign_nodes", "npcs", "units", "objectives", "growth_reactions"]
const UNIT_FIELDS: Array[String] = ["id", "stage", "requires", "title", "objective", "journal", "conversations", "town_changes"]
const CONVERSATION_FIELDS: Array[String] = ["id", "npc", "title", "pages"]
const KNOWN_FLAGS: Array[String] = ["proxy_unlocked", "early_game_complete", "equipment_discovered", "growth_observed", "exponential_observed"]

var _data: Dictionary = {}
var _units: Array[Dictionary] = []
var _npcs: Dictionary = {}


func load_story(path: String = DEFAULT_PATH) -> Array[String]:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ["story: cannot open '%s'" % path]
	var parser := JSON.new()
	var error := parser.parse(file.get_as_text())
	if error != OK:
		return ["story: invalid JSON at line %d: %s" % [parser.get_error_line(), parser.get_error_message()]]
	if not (parser.data is Dictionary):
		return ["story: root must be an object"]
	return load_data(parser.data)


func load_data(candidate: Dictionary) -> Array[String]:
	var failures := validate_story(candidate)
	_data.clear()
	_units.clear()
	_npcs.clear()
	if not failures.is_empty():
		return failures
	_data = candidate.duplicate(true)
	for npc_value in _data.npcs:
		var npc: Dictionary = npc_value
		_npcs[String(npc.id)] = npc.duplicate(true)
	for unit_value in _data.units:
		_units.append((unit_value as Dictionary).duplicate(true))
	return []


func validate_story(candidate: Dictionary) -> Array[String]:
	var failures: Array[String] = []
	_validate_pure_data(candidate, "story", failures)
	_validate_fields(candidate, TOP_LEVEL_FIELDS, "story", failures)
	if candidate.get("schema_version", null) != SCHEMA_VERSION:
		failures.append("story: schema_version must be %d" % SCHEMA_VERSION)
	if String(candidate.get("chapter_id", "")) != "chapter_one_remaining_warmth":
		failures.append("story: chapter_id must be 'chapter_one_remaining_warmth'")
	_validate_campaign_nodes(candidate.get("campaign_nodes", null), failures)
	var npc_ids := _validate_npcs(candidate.get("npcs", null), failures)
	_validate_units(candidate.get("units", null), npc_ids, failures)
	if not candidate.get("objectives") is Array:
		failures.append("story: objectives must be an array")
	else:
		for entry in candidate.objectives:
			if not entry is Dictionary:
				failures.append("story: objective entry must be an object")
				continue
			_validate_requirements(entry.get("requires"), "objective", failures)
			_validate_objective(entry.get("objective"), "objective", failures)
	if not candidate.get("growth_reactions") is Dictionary:
		failures.append("story: growth reactions must be an object")
	else:
		for kind in ["convergent", "critical", "exponential"]:
			var reaction: Variant = candidate.growth_reactions.get(kind)
			if not reaction is Dictionary:
				failures.append("story: missing growth reaction " + kind)
				continue
			if not reaction.get("title") is String or String(reaction.get("title", "")).strip_edges().is_empty():
				failures.append("story: growth reaction title required " + kind)
			_validate_pages(reaction.get("journal_pages"), kind, failures)
			_validate_pages(reaction.get("conversation_pages"), kind, failures)
	return failures


func objectives() -> Array:
	return (_data.get("objectives", []) as Array).duplicate(true)


func growth_reaction(kind: String) -> Dictionary:
	return (_data.get("growth_reactions", {}).get(kind, {}) as Dictionary).duplicate(true)


func story_units() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	result.assign(_units.duplicate(true))
	return result


func get_npc(npc_id: String) -> Dictionary:
	return (_npcs.get(npc_id, {}) as Dictionary).duplicate(true)


func is_loaded() -> bool:
	return not _data.is_empty()


func is_pure_json(value: Variant) -> bool:
	if value is Dictionary:
		for key in value:
			if not (key is String) or not is_pure_json(value[key]):
				return false
		return true
	if value is Array:
		for entry in value:
			if not is_pure_json(entry):
				return false
		return true
	return value is String or value is StringName or value is float or value is int or value is bool or value == null


func _validate_campaign_nodes(value: Variant, failures: Array[String]) -> void:
	if not (value is Array) or (value as Array).is_empty():
		failures.append("story: campaign_nodes must be a non-empty array")
		return
	for node in value:
		if not (node is String) or not CAMPAIGN_NODES.has(node):
			failures.append("story: unknown campaign node '%s'" % str(node))


func _validate_npcs(value: Variant, failures: Array[String]) -> Dictionary:
	var ids := {}
	if not (value is Array) or (value as Array).size() != 5:
		failures.append("story: npcs must contain exactly five NPCs")
		return ids
	for npc_value in value:
		if not (npc_value is Dictionary):
			failures.append("npcs: entries must be objects")
			continue
		var npc: Dictionary = npc_value
		_validate_fields(npc, ["id", "name", "reveal_node"], "npc", failures)
		var id := _required_id(npc.get("id", null), "npc", failures)
		if id == "":
			continue
		if ids.has(id):
			failures.append("npc: duplicate id '%s'" % id)
		ids[id] = true
		if not CAMPAIGN_NODES.has(String(npc.get("reveal_node", ""))):
			failures.append("npc %s: unknown reveal_node" % id)
	return ids


func _validate_units(value: Variant, npc_ids: Dictionary, failures: Array[String]) -> void:
	if not (value is Array) or (value as Array).size() != 10:
		failures.append("story: units must contain exactly ten first-chapter units")
	if not (value is Array):
		return
	var unit_ids := {}
	var journal_ids := {}
	var conversation_ids := {}
	var town_ids := {}
	var stages: Array[int] = []
	for unit_value in value:
		if not (unit_value is Dictionary):
			failures.append("units: entries must be objects")
			continue
		var unit: Dictionary = unit_value
		_validate_fields(unit, UNIT_FIELDS, "unit", failures)
		var id := _required_id(unit.get("id", null), "unit", failures)
		if id != "":
			if unit_ids.has(id):
				failures.append("unit: duplicate id '%s'" % id)
			unit_ids[id] = true
		var stage := int(unit.get("stage", -1))
		if stage < 0 or stages.has(stage):
			failures.append("unit %s: stage must be unique and non-negative" % id)
		stages.append(stage)
		_validate_requirements(unit.get("requires", null), id, failures)
		_validate_objective(unit.get("objective", null), id, failures)
		_validate_journal(unit.get("journal", null), id, journal_ids, failures)
		_validate_conversations(unit.get("conversations", null), id, npc_ids, conversation_ids, failures)
		_validate_town_changes(unit.get("town_changes", null), id, town_ids, failures)
	stages.sort()
	if stages != range(10):
		failures.append("story: unit stages must be exactly 0 through 9")


func _validate_requirements(value: Variant, unit_id: String, failures: Array[String]) -> void:
	if not (value is Dictionary) or not (value as Dictionary).has_all(["completed_nodes"]):
		failures.append("unit %s: requires.completed_nodes is required" % unit_id)
		return
	var requirements: Dictionary = value
	_validate_id_array(requirements.get("completed_nodes", null), "unit %s completed_nodes" % unit_id, CAMPAIGN_NODES, failures)
	var flags: Variant = requirements.get("flags", [])
	var allowed_flags: Array[String] = KNOWN_FLAGS
	_validate_id_array(flags, "unit %s flags" % unit_id, allowed_flags, failures)


func _validate_objective(value: Variant, unit_id: String, failures: Array[String]) -> void:
	if not (value is Dictionary) or not (value as Dictionary).has_all(["id", "text", "campaign_node"]):
		failures.append("unit %s: objective fields are invalid" % unit_id)
		return
	var objective: Dictionary = value
	_required_id(objective.get("id", null), "unit %s objective" % unit_id, failures)
	if not (objective.get("text", "") is String) or String(objective.get("text", "")).is_empty():
		failures.append("unit %s: objective text must be non-empty" % unit_id)
	var campaign_node := String(objective.get("campaign_node", ""))
	if campaign_node != "" and not CAMPAIGN_NODES.has(campaign_node):
		failures.append("unit %s: objective references unknown campaign node" % unit_id)


func _validate_journal(value: Variant, unit_id: String, ids: Dictionary, failures: Array[String]) -> void:
	if not (value is Dictionary) or not (value as Dictionary).has_all(["id", "entry_type", "pages"]):
		failures.append("unit %s: journal fields are invalid" % unit_id)
		return
	var journal: Dictionary = value
	var id := _required_id(journal.get("id", null), "journal", failures)
	if id != "":
		if ids.has(id):
			failures.append("journal: duplicate id '%s'" % id)
		ids[id] = true
	if not (journal.get("entry_type", "") is String) or String(journal.get("entry_type", "")).is_empty():
		failures.append("journal %s: entry_type must be non-empty" % id)
	_validate_pages(journal.get("pages", null), "journal %s" % id, failures)


func _validate_conversations(value: Variant, unit_id: String, npc_ids: Dictionary, ids: Dictionary, failures: Array[String]) -> void:
	if not (value is Array) or (value as Array).is_empty():
		failures.append("unit %s: conversations must be a non-empty array" % unit_id)
		return
	for conversation_value in value:
		if not (conversation_value is Dictionary):
			failures.append("unit %s: conversations entries must be objects" % unit_id)
			continue
		var conversation: Dictionary = conversation_value
		_validate_fields(conversation, CONVERSATION_FIELDS, "conversation", failures)
		var id := _required_id(conversation.get("id", null), "conversation", failures)
		if id != "":
			if ids.has(id):
				failures.append("conversation: duplicate id '%s'" % id)
			ids[id] = true
		if not npc_ids.has(String(conversation.get("npc", ""))):
			failures.append("conversation %s: unknown npc" % id)
		_validate_pages(conversation.get("pages", null), "conversation %s" % id, failures)


func _validate_town_changes(value: Variant, unit_id: String, ids: Dictionary, failures: Array[String]) -> void:
	if not (value is Array) or (value as Array).is_empty():
		failures.append("unit %s: town_changes must be a non-empty array" % unit_id)
		return
	for change_value in value:
		if not (change_value is Dictionary):
			failures.append("unit %s: town_changes entries must be objects" % unit_id)
			continue
		var change: Dictionary = change_value
		_validate_fields(change, ["id", "title", "description"], "town change", failures)
		var id := _required_id(change.get("id", null), "town change", failures)
		if id != "":
			if ids.has(id):
				failures.append("town change: duplicate id '%s'" % id)
			ids[id] = true
		if not (change.get("title", "") is String) or String(change.get("title", "")).is_empty():
			failures.append("town change %s: title must be non-empty" % id)
		if not (change.get("description", "") is String) or String(change.get("description", "")).is_empty():
			failures.append("town change %s: description must be non-empty" % id)


func _validate_pages(value: Variant, label: String, failures: Array[String]) -> void:
	if not (value is Array) or (value as Array).is_empty():
		failures.append("%s: pages must be a non-empty array" % label)
		return
	for page in value:
		if not (page is String) or String(page).is_empty():
			failures.append("%s: pages must be non-empty strings" % label)


func _validate_id_array(value: Variant, label: String, allowed: Array[String], failures: Array[String]) -> void:
	if not (value is Array):
		failures.append("%s must be an array" % label)
		return
	for id in value:
		if not (id is String) or not allowed.has(id):
			failures.append("%s contains unknown id '%s'" % [label, str(id)])


func _validate_pure_data(value: Variant, label: String, failures: Array[String]) -> void:
	if not is_pure_json(value):
		failures.append("%s: content must be pure JSON data" % label)


func _validate_fields(value: Dictionary, fields: Array[String], label: String, failures: Array[String]) -> void:
	for field in value:
		if not fields.has(String(field)):
			failures.append("%s: unknown field '%s'" % [label, str(field)])
	for field in fields:
		if not value.has(field):
			failures.append("%s: missing field '%s'" % [label, field])


func _required_id(value: Variant, label: String, failures: Array[String]) -> String:
	if not (value is String) or String(value).is_empty():
		failures.append("%s: id must be a non-empty string" % label)
		return ""
	return String(value)
