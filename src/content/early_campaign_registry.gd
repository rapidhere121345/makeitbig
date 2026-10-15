class_name EarlyCampaignRegistry
extends RefCounted

const DeterministicRng = preload("res://src/core/deterministic_rng.gd")
const DEFAULT_PATH := "res://content/early_campaign.json"
const SCHEMA_VERSION := 1

const EXPECTED_COUNTS := {
	"layouts": 3,
	"objectives": 3,
	"hazards": 2,
	"normal_enemies": 3,
	"elite_rules": 2,
	"bosses": 1,
	"fixed_nodes": 8,
	"repeatable_templates": 2,
}
const FIXED_KINDS: Array[String] = [
	"tutorial", "mainline", "mainline", "mainline", "mainline", "mainline", "boss", "auto_certification",
]
const MODES: Array[String] = ["Manual", "Auto"]
const TOP_LEVEL_FIELDS: Array[String] = [
	"schema_version", "campaign_id", "layouts", "objectives", "hazards", "normal_enemies",
	"elite_rules", "bosses", "reward_tags", "drop_tags", "fixed_nodes", "repeatable_templates",
]
const NODE_FIELDS: Array[String] = [
	"id", "kind", "unlock_prerequisites", "room_sequence", "room_template", "first_reward_tags",
	"drop_tags", "allowed_modes", "repeatable",
]
const ROOM_FIELDS: Array[String] = [
	"id", "layout_id", "objective_id", "hazard_ids", "enemy_ids", "elite_rule_ids", "boss_id",
	"drop_tags", "new_problem_id", "loot_slots", "combat_stats",
]
const LAYOUT_FIELDS: Array[String] = [
	"id", "display_name", "concept", "landmark", "entry_hint", "exit_hint",
]
const TEMPLATE_FIELDS: Array[String] = [
	"room_count", "layout_ids", "objective_ids", "hazard_ids", "enemy_ids", "elite_rule_ids", "drop_tags",
	"room_overrides",
]

var _data: Dictionary = {}
var _nodes: Dictionary = {}
var _fixed_order: Array[String] = []


func load_campaign(path: String = DEFAULT_PATH) -> Array[String]:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ["campaign: cannot open '%s'" % path]
	var parser := JSON.new()
	var parse_error := parser.parse(file.get_as_text())
	if parse_error != OK:
		return ["campaign: invalid JSON at line %d: %s" % [parser.get_error_line(), parser.get_error_message()]]
	if not (parser.data is Dictionary):
		return ["campaign: root must be an object"]
	return load_data(parser.data)


func load_data(candidate: Dictionary) -> Array[String]:
	var failures := validate_campaign(candidate)
	if not failures.is_empty():
		_data.clear()
		_nodes.clear()
		_fixed_order.clear()
		return failures
	_data = candidate.duplicate(true)
	_rebuild_indexes()
	return []


func validate_campaign(candidate: Dictionary) -> Array[String]:
	var failures: Array[String] = []
	_validate_pure_data(candidate, "campaign", failures)
	_validate_fields(candidate, TOP_LEVEL_FIELDS, "campaign", failures)
	if candidate.get("schema_version", null) != SCHEMA_VERSION:
		failures.append("campaign: schema_version must be %d" % SCHEMA_VERSION)
	if String(candidate.get("campaign_id", "")) != "early_campaign":
		failures.append("campaign: campaign_id must be 'early_campaign'")

	var ids_by_catalog := {}
	var global_ids := {}
	_validate_object_catalog(candidate, "layouts", LAYOUT_FIELDS, ids_by_catalog, global_ids, failures)
	_validate_object_catalog(candidate, "objectives", ["id", "timeout_rule"], ids_by_catalog, global_ids, failures)
	_validate_object_catalog(candidate, "hazards", ["id"], ids_by_catalog, global_ids, failures)
	_validate_object_catalog(candidate, "normal_enemies", ["id", "role"], ids_by_catalog, global_ids, failures)
	_validate_object_catalog(candidate, "elite_rules", ["id", "rule"], ids_by_catalog, global_ids, failures)
	_validate_object_catalog(candidate, "bosses", ["id", "phases", "telegraphed_move_count", "forbidden_mechanics"], ids_by_catalog, global_ids, failures)
	_validate_string_catalog(candidate, "reward_tags", ids_by_catalog, global_ids, failures)
	_validate_string_catalog(candidate, "drop_tags", ids_by_catalog, global_ids, failures)
	_validate_catalog_semantics(candidate, failures)

	var all_nodes := {}
	var fixed: Variant = candidate.get("fixed_nodes", [])
	var templates: Variant = candidate.get("repeatable_templates", [])
	_validate_count_and_type(fixed, "fixed_nodes", failures)
	_validate_count_and_type(templates, "repeatable_templates", failures)
	if fixed is Array:
		_validate_nodes(fixed, false, ids_by_catalog, all_nodes, global_ids, failures)
	if templates is Array:
		_validate_nodes(templates, true, ids_by_catalog, all_nodes, global_ids, failures)
	_validate_progression(fixed if fixed is Array else [], templates if templates is Array else [], all_nodes, failures)
	return failures


func get_node(node_id: String) -> Dictionary:
	if not _nodes.has(node_id):
		return {}
	return (_nodes[node_id] as Dictionary).duplicate(true)


func layout_info(layout_id: String) -> Dictionary:
	for value in (_data.get("layouts", []) as Array):
		if value is Dictionary and String((value as Dictionary).get("id", "")) == layout_id:
			return (value as Dictionary).duplicate(true)
	return {}


func normal_enemy_role_map() -> Dictionary:
	var result := {}
	for value: Variant in _data.get("normal_enemies", []):
		if value is Dictionary:
			result[String((value as Dictionary).get("id", ""))] = String((value as Dictionary).get("role", ""))
	return result


func is_unlocked(node_id: String, completed_node_ids: Array, mode: String) -> bool:
	if not _nodes.has(node_id) or mode not in MODES:
		return false
	var node: Dictionary = _nodes[node_id]
	if mode not in node.allowed_modes:
		return false
	var completed := {}
	for raw_id in completed_node_ids:
		if raw_id is String or raw_id is StringName:
			completed[String(raw_id)] = true
	for prerequisite in node.unlock_prerequisites:
		if not completed.has(String(prerequisite)):
			return false
	return true


func mainline_order() -> Array[String]:
	return _fixed_order.duplicate()


func instantiate_branch(template_id: String, seed: int, mode: String = "Manual") -> Dictionary:
	if not _nodes.has(template_id):
		return {"ok": false, "error": "unknown_template"}
	var node: Dictionary = _nodes[template_id]
	if String(node.get("kind", "")) != "side_template":
		return {"ok": false, "error": "not_a_template"}
	if mode not in (node.get("allowed_modes", []) as Array):
		return {"ok": false, "error": "mode_not_allowed"}
	var spec: Dictionary = node.room_template
	var rng = DeterministicRng.create(seed, "early_campaign/%s" % template_id)
	var rooms: Array[Dictionary] = []
	for index in range(int(spec.room_count)):
		var objective_id := _pick(spec.objective_ids, rng)
		var hazard_id := _pick(spec.hazard_ids, rng)
		var elite_rule_id := _pick(spec.elite_rule_ids, rng) if objective_id == "hunt_elite" else ""
		var room := {
			"id": "%s/%s/room_%02d" % [template_id, str(seed), index],
			"layout_id": _pick(spec.layout_ids, rng),
			"objective_id": objective_id,
			"hazard_ids": [] if hazard_id == "" else [hazard_id],
			"enemy_ids": [_pick(spec.enemy_ids, rng)],
			"elite_rule_ids": [] if elite_rule_id == "" else [elite_rule_id],
			"boss_id": "",
			"drop_tags": [_pick(spec.drop_tags, rng)],
			"new_problem_id": "",
		}
		for override_value: Variant in spec.get("room_overrides", []):
			if override_value is Dictionary and int((override_value as Dictionary).get("index", -1)) == index:
				var override: Dictionary = override_value
				for authored_field: String in ["loot_slots", "combat_stats"]:
					if override.has(authored_field):
						var authored_value: Variant = override.get(authored_field)
						room[authored_field] = authored_value.duplicate(true) if authored_value is Array or authored_value is Dictionary else authored_value
		rooms.append(room)
	return {"ok": true, "plan": {
		"schema_version": SCHEMA_VERSION,
		"template_id": template_id,
		"seed": seed,
		"mode": mode,
		"repeatable": true,
		"rooms": rooms,
	}.duplicate(true)}


func _rebuild_indexes() -> void:
	_nodes.clear()
	_fixed_order.clear()
	for node_value in _data.fixed_nodes:
		var node: Dictionary = node_value
		_nodes[String(node.id)] = node.duplicate(true)
		_fixed_order.append(String(node.id))
	for node_value in _data.repeatable_templates:
		var node: Dictionary = node_value
		_nodes[String(node.id)] = node.duplicate(true)


func _validate_count_and_type(value: Variant, field: String, failures: Array[String]) -> void:
	if not (value is Array):
		failures.append("campaign: %s must be an array" % field)
		return
	var expected := int(EXPECTED_COUNTS[field])
	if value.size() != expected:
		failures.append("campaign: %s has %d entries, expected %d" % [field, value.size(), expected])


func _validate_object_catalog(candidate: Dictionary, field: String, allowed_fields: Array[String], ids_by_catalog: Dictionary, global_ids: Dictionary, failures: Array[String]) -> void:
	var value: Variant = candidate.get(field, [])
	_validate_count_and_type(value, field, failures)
	var ids := {}
	if value is Array:
		for entry_value in value:
			if not (entry_value is Dictionary):
				failures.append("%s: entries must be objects" % field)
				continue
			var entry: Dictionary = entry_value
			_validate_fields(entry, allowed_fields, field, failures)
			var id := _required_id(entry.get("id", null), field, failures)
			_register_id(id, field, ids, global_ids, failures)
	ids_by_catalog[field] = ids


func _validate_string_catalog(candidate: Dictionary, field: String, ids_by_catalog: Dictionary, global_ids: Dictionary, failures: Array[String]) -> void:
	var value: Variant = candidate.get(field, [])
	var ids := {}
	if not (value is Array) or value.is_empty():
		failures.append("campaign: %s must be a non-empty array" % field)
	else:
		for raw_id in value:
			var id := _required_id(raw_id, field, failures)
			_register_id(id, field, ids, global_ids, failures)
	ids_by_catalog[field] = ids


func _validate_catalog_semantics(candidate: Dictionary, failures: Array[String]) -> void:
	_validate_exact_catalog_ids(candidate, "layouts", ["rectangle_arena", "corridor", "ring"], failures)
	for layout_value in candidate.get("layouts", []):
		if not layout_value is Dictionary:
			continue
		var layout: Dictionary = layout_value
		for field in ["display_name", "concept", "landmark", "entry_hint", "exit_hint"]:
			if String(layout.get(field, "")).strip_edges().is_empty():
				failures.append("layout %s: %s must be a non-empty string" % [String(layout.get("id", "")), field])
	_validate_exact_catalog_ids(candidate, "objectives", ["clear", "hunt_elite", "timed_break"], failures)
	_validate_exact_catalog_ids(candidate, "hazards", ["exposed_ground_zone", "moving_fireline"], failures)
	_validate_exact_catalog_ids(candidate, "normal_enemies", ["melee_pursuer", "charging_raider", "fan_ranged"], failures)
	_validate_exact_catalog_ids(candidate, "elite_rules", ["periodic_barrier", "summon_reinforcements"], failures)
	var expected_roles := ["melee_chase", "telegraphed_charge", "telegraphed_fan_ranged"]
	var actual_roles: Array[String] = []
	for entry_value in candidate.get("normal_enemies", []):
		if entry_value is Dictionary:
			actual_roles.append(String(entry_value.get("role", "")))
	actual_roles.sort()
	expected_roles.sort()
	if actual_roles != expected_roles:
		failures.append("normal_enemies: roles must be melee chase, telegraphed charge, and telegraphed fan ranged")
	var elite_rules: Array = candidate.get("elite_rules", [])
	var rule_values: Array[String] = []
	for entry_value in elite_rules:
		if entry_value is Dictionary:
			rule_values.append(String(entry_value.get("rule", "")))
	rule_values.sort()
	if rule_values != ["periodic_barrier", "summon_reinforcements"]:
		failures.append("elite_rules: must be periodic barrier and summon reinforcements")
	var bosses: Array = candidate.get("bosses", [])
	if bosses.size() == 1 and bosses[0] is Dictionary:
		var boss: Dictionary = bosses[0]
		if String(boss.get("id", "")) != "threshold_colossus" or int(boss.get("phases", 0)) != 2 or int(boss.get("telegraphed_move_count", 0)) != 3:
			failures.append("bosses: threshold_colossus must have 2 phases and 3 telegraphed moves")


func _validate_exact_catalog_ids(candidate: Dictionary, field: String, expected: Array[String], failures: Array[String]) -> void:
	var actual: Array[String] = []
	for entry_value in candidate.get(field, []):
		if entry_value is Dictionary:
			actual.append(String(entry_value.get("id", "")))
	actual.sort()
	var sorted_expected := expected.duplicate()
	sorted_expected.sort()
	if actual != sorted_expected:
		failures.append("%s: stable IDs must be exactly %s" % [field, str(sorted_expected)])


func _validate_nodes(values: Array, templates: bool, catalogs: Dictionary, all_nodes: Dictionary, global_ids: Dictionary, failures: Array[String]) -> void:
	for value in values:
		if not (value is Dictionary):
			failures.append("nodes: entries must be objects")
			continue
		var node: Dictionary = value
		_validate_fields(node, NODE_FIELDS, "node", failures)
		var id := _required_id(node.get("id", null), "node", failures)
		_register_id(id, "node", all_nodes, global_ids, failures)
		if id != "":
			all_nodes[id] = node
		if not (node.get("unlock_prerequisites", null) is Array):
			failures.append("node %s: unlock_prerequisites must be an array" % id)
		_validate_string_references(node.get("first_reward_tags", null), catalogs.get("reward_tags", {}), "node %s first_reward_tags" % id, true, failures)
		_validate_string_references(node.get("drop_tags", null), catalogs.get("drop_tags", {}), "node %s drop_tags" % id, true, failures)
		_validate_modes(node, id, templates, failures)
		if templates:
			if String(node.get("kind", "")) != "side_template" or node.get("repeatable", false) != true:
				failures.append("node %s: repeatable template kind/rule is invalid" % id)
			if node.has("room_sequence") or not (node.get("room_template", null) is Dictionary):
				failures.append("node %s: template must define only room_template" % id)
			else:
				_validate_template(node.room_template, id, catalogs, failures)
		else:
			if node.get("repeatable", true) != false:
				failures.append("node %s: fixed nodes must not be repeatable" % id)
			if node.has("room_template") or not (node.get("room_sequence", null) is Array) or node.get("room_sequence", []).is_empty():
				failures.append("node %s: fixed node must define only a non-empty room_sequence" % id)
			else:
				for room_value in node.room_sequence:
					_validate_room(room_value, id, catalogs, global_ids, failures)


func _validate_modes(node: Dictionary, id: String, template: bool, failures: Array[String]) -> void:
	var expected := ["Manual", "Auto"] if template else (["Auto"] if String(node.get("kind", "")) == "auto_certification" else ["Manual"])
	var modes: Variant = node.get("allowed_modes", null)
	if not (modes is Array) or modes != expected:
		failures.append("node %s: allowed_modes must be exactly %s" % [id, str(expected)])


func _validate_room(value: Variant, node_id: String, catalogs: Dictionary, global_ids: Dictionary, failures: Array[String]) -> void:
	if not (value is Dictionary):
		failures.append("node %s: room entries must be objects" % node_id)
		return
	var room: Dictionary = value
	_validate_fields(room, ROOM_FIELDS, "node %s room" % node_id, failures)
	var room_id := _required_id(room.get("id", null), "node %s room" % node_id, failures)
	var local := {}
	_register_id(room_id, "room", local, global_ids, failures)
	_validate_reference(room.get("layout_id", null), catalogs.get("layouts", {}), "room %s layout_id" % room_id, false, failures)
	_validate_reference(room.get("objective_id", null), catalogs.get("objectives", {}), "room %s objective_id" % room_id, false, failures)
	_validate_string_references(room.get("hazard_ids", null), catalogs.get("hazards", {}), "room %s hazard_ids" % room_id, false, failures)
	# A room roster lists instances: several entries may reference the same kind.
	_validate_string_references(room.get("enemy_ids", null), catalogs.get("normal_enemies", {}), "room %s enemy_ids" % room_id, false, failures, false, true)
	_validate_string_references(room.get("elite_rule_ids", null), catalogs.get("elite_rules", {}), "room %s elite_rule_ids" % room_id, false, failures)
	_validate_reference(room.get("boss_id", null), catalogs.get("bosses", {}), "room %s boss_id" % room_id, true, failures)
	_validate_string_references(room.get("drop_tags", null), catalogs.get("drop_tags", {}), "room %s drop_tags" % room_id, true, failures)
	var problem: Variant = room.get("new_problem_id", null)
	if not (problem is String):
		failures.append("room %s: new_problem_id must be a string" % room_id)
	_validate_room_features(room, "room %s" % room_id, catalogs, failures)


func _validate_template(spec: Dictionary, node_id: String, catalogs: Dictionary, failures: Array[String]) -> void:
	_validate_fields(spec, TEMPLATE_FIELDS, "template %s" % node_id, failures)
	var raw_room_count: Variant = spec.get("room_count", null)
	if (typeof(raw_room_count) != TYPE_INT and typeof(raw_room_count) != TYPE_FLOAT) or float(raw_room_count) != float(int(raw_room_count)) or int(raw_room_count) <= 0:
		failures.append("template %s: room_count must be a positive integer" % node_id)
	_validate_string_references(spec.get("layout_ids", null), catalogs.get("layouts", {}), "template %s layout_ids" % node_id, true, failures)
	_validate_string_references(spec.get("objective_ids", null), catalogs.get("objectives", {}), "template %s objective_ids" % node_id, true, failures)
	_validate_string_references(spec.get("hazard_ids", null), catalogs.get("hazards", {}), "template %s hazard_ids" % node_id, true, failures, true)
	_validate_string_references(spec.get("enemy_ids", null), catalogs.get("normal_enemies", {}), "template %s enemy_ids" % node_id, true, failures)
	_validate_string_references(spec.get("elite_rule_ids", null), catalogs.get("elite_rules", {}), "template %s elite_rule_ids" % node_id, true, failures, true)
	_validate_string_references(spec.get("drop_tags", null), catalogs.get("drop_tags", {}), "template %s drop_tags" % node_id, true, failures)
	if spec.has("room_overrides"):
		var overrides: Variant = spec.get("room_overrides")
		if not overrides is Array or (overrides as Array).is_empty():
			failures.append("template %s: room_overrides must be a non-empty array" % node_id)
		else:
			var seen_indexes := {}
			for override_value: Variant in overrides:
				if not override_value is Dictionary:
					failures.append("template %s: room override must be an object" % node_id)
					continue
				var override: Dictionary = override_value
				_validate_fields(override, ["index", "loot_slots", "combat_stats"], "template %s room override" % node_id, failures)
				var index_value: Variant = override.get("index", null)
				if not _is_integer_number(index_value) or int(index_value) < 0 or int(index_value) >= int(raw_room_count):
					failures.append("template %s: room override index is out of range" % node_id)
				else:
					var index := int(index_value)
					if seen_indexes.has(index):
						failures.append("template %s: duplicate room override index %d" % [node_id, index])
					seen_indexes[index] = true
				if not override.has("loot_slots") and not override.has("combat_stats"):
					failures.append("template %s: room override has no authored content" % node_id)
				_validate_room_features(override, "template %s room override" % node_id, catalogs, failures)


func _validate_room_features(room: Dictionary, context: String, catalogs: Dictionary, failures: Array[String]) -> void:
	if room.has("loot_slots"):
		var slots_value: Variant = room.get("loot_slots")
		if not slots_value is Array or (slots_value as Array).is_empty():
			failures.append("%s: loot_slots must be a non-empty array" % context)
		else:
			var seen_slots := {}
			for slot_value: Variant in slots_value:
				if not slot_value is Dictionary:
					failures.append("%s: loot slot must be an object" % context)
					continue
				var slot: Dictionary = slot_value
				_validate_fields(slot, ["slot_id", "source", "tags", "pickup_radius", "guaranteed", "guarantee_family"], "%s loot slot" % context, failures)
				var slot_id := String(slot.get("slot_id", "")).strip_edges()
				if slot_id.is_empty() or seen_slots.has(slot_id):
					failures.append("%s: loot slot id must be unique and non-empty" % context)
				seen_slots[slot_id] = true
				if String(slot.get("source", "")) not in ["enemy_death", "wave_clear"]:
					failures.append("%s: loot slot source is invalid" % context)
				_validate_string_references(slot.get("tags", null), catalogs.get("drop_tags", {}), "%s loot slot tags" % context, true, failures)
				if not _is_finite_number(slot.get("pickup_radius", null)) or float(slot.get("pickup_radius")) <= 0.0:
					failures.append("%s: loot slot pickup_radius must be positive" % context)
				if slot.has("guaranteed") and not slot.get("guaranteed") is bool:
					failures.append("%s: loot slot guaranteed must be boolean" % context)
				if slot.has("guarantee_family") and not slot.get("guarantee_family") is String:
					failures.append("%s: loot slot guarantee_family must be a string" % context)
	if room.has("combat_stats"):
		var stats_value: Variant = room.get("combat_stats")
		if not stats_value is Dictionary:
			failures.append("%s: combat_stats must be an object" % context)
		else:
			var stats: Dictionary = stats_value
			var allowed: Array[String] = ["move_speed", "acceleration", "dodge_distance", "attack_cooldown_ticks", "dodge_duration_ticks", "dodge_cooldown_ticks", "resistances", "movement_model"]
			_validate_fields(stats, allowed, "%s combat_stats" % context, failures)
			if stats.has("movement_model") and (not stats.movement_model is String or String(stats.movement_model) not in ["direct", "accelerated"]):
				failures.append("%s combat_stats.movement_model must be direct or accelerated" % context)
			for field: String in ["move_speed", "acceleration", "dodge_distance"]:
				if not _is_finite_number(stats.get(field, null)) or float(stats.get(field)) <= 0.0:
					failures.append("%s combat_stats.%s must be positive" % [context, field])
			for field: String in ["attack_cooldown_ticks", "dodge_duration_ticks", "dodge_cooldown_ticks"]:
				if not _is_integer_number(stats.get(field, null)) or int(stats.get(field)) < 0:
					failures.append("%s combat_stats.%s must be a non-negative integer" % [context, field])
			var resistances: Variant = stats.get("resistances", null)
			if not resistances is Dictionary:
				failures.append("%s combat_stats.resistances must be an object" % context)
			else:
				for resistance_id: Variant in resistances.keys():
					if not resistance_id is String or not _is_finite_number(resistances[resistance_id]) or float(resistances[resistance_id]) < 0.0 or float(resistances[resistance_id]) > 1.0:
						failures.append("%s combat_stats resistance is invalid" % context)


func _validate_progression(fixed: Array, templates: Array, all_nodes: Dictionary, failures: Array[String]) -> void:
	for node_value in fixed + templates:
		if not (node_value is Dictionary):
			continue
		var node: Dictionary = node_value
		for raw_prerequisite in node.get("unlock_prerequisites", []):
			var prerequisite := String(raw_prerequisite)
			if not all_nodes.has(prerequisite):
				failures.append("node %s: unknown prerequisite '%s'" % [String(node.get("id", "")), prerequisite])
	if fixed.size() != FIXED_KINDS.size():
		return
	for index in range(fixed.size()):
		if not (fixed[index] is Dictionary):
			continue
		var node: Dictionary = fixed[index]
		if String(node.get("kind", "")) != FIXED_KINDS[index]:
			failures.append("fixed_nodes: node %d must have kind '%s'" % [index, FIXED_KINDS[index]])
		var expected_prerequisites: Array = [] if index == 0 else [String((fixed[index - 1] as Dictionary).get("id", ""))]
		if node.get("unlock_prerequisites", null) != expected_prerequisites:
			failures.append("node %s: fixed progression must depend exactly on its predecessor" % String(node.get("id", "")))
	if String((fixed[6] as Dictionary).get("id", "")) != "threshold_colossus":
		failures.append("fixed_nodes: Boss must be threshold_colossus at position 7")
	if String((fixed[7] as Dictionary).get("id", "")) != "auto_certification":
		failures.append("fixed_nodes: auto_certification must follow the Boss")
	for index in range(fixed.size()):
		if not (fixed[index] is Dictionary):
			continue
		var has_boss := false
		for room_value in (fixed[index] as Dictionary).get("room_sequence", []):
			if room_value is Dictionary and String(room_value.get("boss_id", "")) != "":
				has_boss = true
		if has_boss != (index == 6):
			failures.append("node %s: only the Boss node may reference a boss" % String((fixed[index] as Dictionary).get("id", "")))
	for node_value in fixed:
		if node_value is Dictionary:
			_detect_cycle(String(node_value.get("id", "")), all_nodes, {}, {}, failures)
	var reachable := {}
	if fixed[0] is Dictionary:
		reachable[String(fixed[0].get("id", ""))] = true
	var changed := true
	while changed:
		changed = false
		for node_value in fixed + templates:
			if not (node_value is Dictionary):
				continue
			var node: Dictionary = node_value
			var id := String(node.get("id", ""))
			if reachable.has(id):
				continue
			var can_reach := true
			for prerequisite in node.get("unlock_prerequisites", []):
				can_reach = can_reach and reachable.has(String(prerequisite))
			if can_reach and not node.get("unlock_prerequisites", []).is_empty():
				reachable[id] = true
				changed = true
	for id in all_nodes:
		if not reachable.has(id):
			failures.append("node %s: is not reachable from the tutorial" % id)


func _detect_cycle(id: String, nodes: Dictionary, visiting: Dictionary, visited: Dictionary, failures: Array[String]) -> void:
	if visited.has(id) or not nodes.has(id):
		return
	if visiting.has(id):
		failures.append("mainline: prerequisite cycle at '%s'" % id)
		return
	visiting[id] = true
	for prerequisite in (nodes[id] as Dictionary).get("unlock_prerequisites", []):
		_detect_cycle(String(prerequisite), nodes, visiting, visited, failures)
	visiting.erase(id)
	visited[id] = true


func _validate_string_references(value: Variant, catalog: Dictionary, context: String, require_non_empty: bool, failures: Array[String], allow_empty_id: bool = false, allow_duplicates: bool = false) -> void:
	if not (value is Array) or (require_non_empty and value.is_empty()):
		failures.append("%s must be %sstring array" % [context, "a non-empty " if require_non_empty else "a "])
		return
	var seen := {}
	for raw_id in value:
		if not (raw_id is String):
			failures.append("%s must contain only strings" % context)
			continue
		var id := String(raw_id)
		if id == "" and allow_empty_id:
			continue
		if id == "" or not catalog.has(id):
			failures.append("%s: unknown reference '%s'" % [context, id])
		if seen.has(id) and not allow_duplicates:
			failures.append("%s: duplicate reference '%s'" % [context, id])
		seen[id] = true


func _validate_reference(value: Variant, catalog: Dictionary, context: String, allow_empty: bool, failures: Array[String]) -> void:
	if not (value is String):
		failures.append("%s must be a string" % context)
		return
	var id := String(value)
	if id == "" and allow_empty:
		return
	if not catalog.has(id):
		failures.append("%s: unknown reference '%s'" % [context, id])


func _validate_fields(value: Dictionary, allowed: Array[String], context: String, failures: Array[String]) -> void:
	for key in value:
		if not (key is String) or String(key) not in allowed:
			failures.append("%s: unknown field '%s'" % [context, str(key)])


func _required_id(value: Variant, context: String, failures: Array[String]) -> String:
	if not (value is String) or String(value).is_empty() or String(value) != String(value).strip_edges():
		failures.append("%s: id must be a non-empty trimmed string" % context)
		return ""
	return String(value)


func _register_id(id: String, context: String, local_ids: Dictionary, global_ids: Dictionary, failures: Array[String]) -> void:
	if id == "":
		return
	if local_ids.has(id):
		failures.append("%s: duplicate id '%s'" % [context, id])
	if global_ids.has(id) and String(global_ids[id]) == context:
		failures.append("campaign: id '%s' is reused by %s and %s" % [id, String(global_ids[id]), context])
	local_ids[id] = true
	global_ids[id] = context


func _is_integer_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == float(int(value))


func _is_finite_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


func _validate_pure_data(value: Variant, path: String, failures: Array[String]) -> void:
	var kind := typeof(value)
	if kind in [TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING]:
		return
	if kind == TYPE_ARRAY:
		for index in range(value.size()):
			_validate_pure_data(value[index], "%s[%d]" % [path, index], failures)
		return
	if kind == TYPE_DICTIONARY:
		for key in value:
			if not (key is String):
				failures.append("%s: dictionary keys must be strings" % path)
			_validate_pure_data(value[key], "%s.%s" % [path, str(key)], failures)
		return
	failures.append("%s: value type %s is not pure JSON data" % [path, type_string(kind)])


func _pick(values: Array, rng: DeterministicRng) -> String:
	return String(values[rng.next_int(values.size())])
