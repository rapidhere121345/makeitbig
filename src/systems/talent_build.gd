class_name TalentBuild
extends RefCounted

const TalentRegistryScript = preload("res://src/content/talent_registry.gd")

var registry: TalentRegistry


func _init(talent_registry: TalentRegistry = null) -> void:
	registry = talent_registry if talent_registry != null else TalentRegistryScript.new()


func validate(build: Dictionary, available_points: int, unlocked_classes: Array) -> Dictionary:
	var normalized := _normalize(build)
	var errors: Array[String] = normalized.errors
	for registry_error in registry.load_errors:
		errors.append("talents: %s" % registry_error)
	if registry.trees.is_empty() or registry.nodes.is_empty():
		errors.append("talents: talent registry is not loaded")
	var allocated: Array[String] = normalized.allocated_ids
	var tree_points := {}
	var key_talents: Array[String] = []
	if available_points < 0:
		errors.append("talents: available_points must be non-negative")
	for index in range(allocated.size()):
		var node_id := allocated[index]
		if not registry.nodes.has(node_id):
			errors.append("talents: unknown talent '%s'" % node_id)
			continue
		var node: Dictionary = registry.nodes[node_id]
		var tree_id := String(node.tree_id)
		tree_points[tree_id] = int(tree_points.get(tree_id, 0)) + 1
		if bool(node.is_key):
			key_talents.append(node_id)
		if not bool(registry.trees[tree_id].implemented) or not bool(node.get("implemented", true)):
			errors.append("talents: '%s' is not implemented in the current class runtime" % node_id)
	var duplicate_result := _first_duplicate(allocated)
	if duplicate_result != "":
		errors.append("talents: duplicate talent '%s'" % duplicate_result)
	var spent := _unique_count(allocated)
	if spent > available_points:
		errors.append("talents: allocated %d points with only %d available" % [spent, available_points])
	if key_talents.size() > 2:
		errors.append("talents: at most two key talents may be active")
	for tree_id in tree_points:
		var tree: Dictionary = registry.trees[tree_id]
		if not unlocked_classes.has(String(tree.class_id)):
			errors.append("talents: class '%s' is not unlocked" % String(tree.class_id))
		var layer_points := _tree_layer_points(allocated, String(tree_id))
		var lower_points := [0, int(layer_points[1]), int(layer_points[1]) + int(layer_points[2])]
		for layer in [2, 3]:
			var requirement := int(tree.layer_requirements[layer - 1])
			if int(lower_points[layer - 1]) < requirement and int(layer_points[layer]) > 0:
				errors.append("talents: tree '%s' needs %d points in lower layers before layer %d" % [tree_id, requirement, layer])
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"talents": normalized.value,
		"spent_points": spent,
		"unspent_points": maxi(0, available_points - spent) if errors.is_empty() else 0,
		"tree_points": tree_points,
		"key_talent_ids": key_talents,
	}


func compile(build: Dictionary, available_points: int, unlocked_classes: Array) -> Dictionary:
	var checked := validate(build, available_points, unlocked_classes)
	if not bool(checked.ok):
		return {
			"ok": false,
			"errors": checked.errors,
			"talents": {},
			"talent_capabilities": {},
			"talent_parameter_sources": [],
		}
	var capabilities := {}
	var parameter_sources: Array[Dictionary] = []
	for node_id in checked.talents.allocated_ids:
		var node: Dictionary = registry.nodes[node_id]
		if not node.has("effect"):
			continue
		var effect: Dictionary = node.effect
		if String(effect.type) == "capability":
			var id := String(effect.id)
			if id == "hunter_mark_duration_multiplier" or id == "dash_duration_multiplier" or id == "dodge_cooldown_reduction" or id == "p_overflow_damage_efficiency_bonus":
				capabilities[id] = float(capabilities.get(id, 0.0)) + float(effect.value)
			else:
				capabilities[id] = effect.value
		elif String(effect.type) == "stance_parameters":
			var stance := String(checked.talents.stance)
			var modifier: Dictionary = effect.get(stance, {})
			parameter_sources.append({
				"talent_id": node_id,
				"parameter": String(modifier.get("parameter", "")),
				"operation": String(modifier.get("operation", "")),
				"value": float(modifier.get("value", 0.0)),
			})
		else:
			parameter_sources.append({
				"talent_id": node_id,
				"parameter": String(effect.parameter),
				"operation": "multiply_bonus" if String(effect.type) == "parameter_multiply" else "reduce_percent",
				"value": float(effect.value),
			})
	return {
		"ok": true,
		"errors": [],
		"talents": checked.talents,
		"spent_points": int(checked.spent_points),
		"unspent_points": int(checked.unspent_points),
		"tree_points": checked.tree_points,
		"key_talent_ids": checked.key_talent_ids,
		"talent_capabilities": capabilities,
		"talent_parameter_sources": parameter_sources,
	}


func _normalize(value: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var raw_ids: Variant = value.get("allocated_ids", null)
	var allocated: Array[String] = []
	if not raw_ids is Array:
		errors.append("talents: allocated_ids must be an array")
	else:
		for raw_id in raw_ids:
			if not raw_id is String and not raw_id is StringName:
				errors.append("talents: allocated_ids entries must be text")
				continue
			var id := String(raw_id).strip_edges()
			if id.is_empty():
				errors.append("talents: allocated_ids entries must be non-empty text")
			allocated.append(id)
	var raw_stance: Variant = value.get("stance", "mid")
	var stance := String(raw_stance) if raw_stance is String or raw_stance is StringName else "invalid"
	if stance not in ["near", "mid", "far"]:
		errors.append("talents: stance must be near, mid, or far")
	for key in value:
		if String(key) not in ["allocated_ids", "stance"]:
			errors.append("talents: unknown build field '%s'" % key)
	return {
		"errors": errors,
		"allocated_ids": allocated,
		"value": {"allocated_ids": allocated, "stance": stance},
	}


func _first_duplicate(values: Array[String]) -> String:
	var seen: Dictionary = {}
	for value in values:
		if seen.has(value):
			return value
		seen[value] = true
	return ""


func _unique_count(values: Array[String]) -> int:
	var seen: Dictionary = {}
	for value in values:
		seen[value] = true
	return seen.size()


func _tree_layer_points(allocated: Array[String], tree_id: String) -> Dictionary:
	var result := {1: 0, 2: 0, 3: 0}
	var seen: Dictionary = {}
	for node_id in allocated:
		if seen.has(node_id) or not registry.nodes.has(node_id):
			continue
		var node: Dictionary = registry.nodes[node_id]
		if String(node.tree_id) != tree_id:
			continue
		seen[node_id] = true
		result[int(node.layer)] = int(result[int(node.layer)]) + 1
	return result
