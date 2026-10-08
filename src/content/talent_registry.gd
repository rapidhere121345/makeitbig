class_name TalentRegistry
extends RefCounted

const CONTENT_PATH := "res://content/character_talents.json"
const EXPECTED_SCHEMA_VERSION := 1
const FORBIDDEN_DATA_KEYS: Array[String] = ["script", "script_path", "code", "source_code", "callable", "method"]

var trees: Dictionary = {}
var nodes: Dictionary = {}
var tree_order: Array[String] = []
var load_errors: Array[String] = []


func _init(path: String = CONTENT_PATH) -> void:
	load_catalog(path)


func load_catalog(path: String = CONTENT_PATH) -> Array[String]:
	var data := _read_json(path)
	load_errors = validate_content(data)
	if load_errors.is_empty():
		_ingest(data)
	else:
		trees.clear()
		nodes.clear()
		tree_order.clear()
	return load_errors.duplicate()


func validate_content(data: Dictionary) -> Array[String]:
	var failures: Array[String] = []
	_check_exact_keys(data, ["schema_version", "source", "note", "trees", "global_limits"], [], "talents", failures)
	_check_forbidden_keys(data, "talents", failures)
	if not _is_exact_integer(data.get("schema_version", null)) or int(data.schema_version) != EXPECTED_SCHEMA_VERSION:
		failures.append("talents: schema_version must be %d" % EXPECTED_SCHEMA_VERSION)
	if String(data.get("source", "")).strip_edges().is_empty():
		failures.append("talents: source must be non-empty text")
	if String(data.get("note", "")).strip_edges().is_empty():
		failures.append("talents: note must be non-empty text")
	var limits: Dictionary = data.get("global_limits", {})
	if not _valid_global_limits(limits):
		failures.append("talents: global_limits must keep one point per node, two key talents, and three stances")
	var values: Variant = data.get("trees", null)
	if not values is Array or (values as Array).size() != 3:
		failures.append("talents: trees must contain exactly three entries")
		return failures
	var seen_tree: Dictionary = {}
	var seen_node: Dictionary = {}
	var seen_class: Dictionary = {}
	for raw_tree in values:
		if not raw_tree is Dictionary:
			failures.append("talents: tree must be an object")
			continue
		var tree: Dictionary = raw_tree
		_check_exact_keys(tree, ["id", "name", "class_id", "layer_requirements", "implemented", "nodes"], ["pending_reason"], "talent tree", failures)
		_check_forbidden_keys(tree, "talent tree", failures)
		var tree_id := _required_text(tree, "id", "talent tree", failures)
		if seen_tree.has(tree_id):
			failures.append("talents: duplicate tree id '%s'" % tree_id)
		seen_tree[tree_id] = true
		_required_text(tree, "name", "talent tree %s" % tree_id, failures)
		var class_id := _required_text(tree, "class_id", "talent tree %s" % tree_id, failures)
		if class_id != "":
			if seen_class.has(class_id):
				failures.append("talents: duplicate class_id '%s'" % class_id)
			seen_class[class_id] = true
		if _integer_array(tree.get("layer_requirements", null)) != [0, 3, 8]:
			failures.append("talents: tree %s layer requirements must be 0/3/8" % tree_id)
		if typeof(tree.get("implemented", null)) != TYPE_BOOL:
			failures.append("talents: tree %s implemented must be boolean" % tree_id)
		var node_values: Variant = tree.get("nodes", null)
		if not node_values is Array or (node_values as Array).size() != 15:
			failures.append("talents: tree %s must contain 15 nodes" % tree_id)
			continue
		var layer_counts := {}
		var key_count := 0
		for raw_node in node_values:
			if not raw_node is Dictionary:
				failures.append("talents: node must be an object")
				continue
			var node: Dictionary = raw_node
			var optional: Array = ["effect", "implemented", "pending_reason"]
			_check_exact_keys(node, ["id", "name", "layer", "is_key", "description"], optional, "talent node", failures)
			_check_forbidden_keys(node, "talent node", failures)
			var node_id := _required_text(node, "id", "talent node", failures)
			_required_text(node, "description", "talent node %s" % node_id, failures)
			if seen_node.has(node_id):
				failures.append("talents: duplicate node id '%s'" % node_id)
			seen_node[node_id] = true
			_required_text(node, "name", "talent node %s" % node_id, failures)
			var layer_value: Variant = node.get("layer", null)
			var layer := _exact_integer(layer_value)
			if layer < 1 or layer > 3:
				failures.append("talents: node %s layer must be 1..3" % node_id)
			else:
				layer_counts[layer] = int(layer_counts.get(layer, 0)) + 1
			if typeof(node.get("is_key", null)) != TYPE_BOOL:
				failures.append("talents: node %s is_key must be boolean" % node_id)
			elif bool(node.is_key):
				key_count += 1
			if node.has("implemented") and typeof(node.implemented) != TYPE_BOOL:
				failures.append("talents: node %s implemented must be boolean" % node_id)
			if node.has("pending_reason") and String(node.pending_reason).strip_edges().is_empty():
				failures.append("talents: node %s pending_reason must be non-empty" % node_id)
			if node.has("effect"):
				_validate_effect(node.effect, node_id, failures)
		if layer_counts != {1: 5, 2: 5, 3: 5}:
			failures.append("talents: tree %s layers must each contain five nodes" % tree_id)
		if key_count != 3:
			failures.append("talents: tree %s must contain exactly three key talents" % tree_id)
	return failures


func catalog() -> Dictionary:
	if not load_errors.is_empty() or trees.is_empty() or nodes.is_empty():
		return {
			"ok": false,
			"errors": load_errors.duplicate(),
			"trees": [],
			"global_limits": {},
		}
	var result: Array[Dictionary] = []
	for tree_id in tree_order:
		var tree: Dictionary = trees[tree_id]
		var node_views: Array[Dictionary] = []
		for node_id in tree.node_order:
			var node: Dictionary = nodes[node_id].duplicate(true)
			node["implemented_class"] = bool(tree.implemented)
			node["implemented"] = bool(tree.implemented) and bool(node.get("implemented", true))
			node_view(node)
			node_views.append(node)
		var tree_view := tree.duplicate(true)
		tree_view["nodes"] = node_views
		result.append(tree_view)
	return {
		"ok": true,
		"schema_version": EXPECTED_SCHEMA_VERSION,
		"trees": result,
		"global_limits": {
			"points_per_node": 1,
			"key_talents": 2,
			"stances": ["near", "mid", "far"],
		},
	}


func node_view(node: Dictionary) -> void:
	# Dictionary is passed by reference. This hook keeps future UI projections
	# explicit without letting presentation read raw effect payloads.
	pass


func _validate_effect(value: Variant, node_id: String, failures: Array[String]) -> void:
	if not value is Dictionary:
		failures.append("talents: node %s effect must be an object" % node_id)
		return
	var effect: Dictionary = value
	var kind := String(effect.get("type", ""))
	if kind == "stance_parameters":
		_validate_stance_effect(effect, node_id, failures)
		return
	if kind == "parameter_multiply" or kind == "parameter_reduce":
		_check_exact_keys(effect, ["type", "parameter", "value"], [], "talent node %s effect" % node_id, failures)
	elif kind == "capability":
		_check_exact_keys(effect, ["type", "id", "value"], [], "talent node %s effect" % node_id, failures)
	else:
		failures.append("talents: node %s has unknown effect type '%s'" % [node_id, kind])
		return
	_check_forbidden_keys(effect, "talent node %s effect" % node_id, failures)
	if kind.begins_with("parameter_"):
		if String(effect.get("parameter", "")) not in ["v", "T", "turn"]:
			failures.append("talents: node %s targets a forbidden parameter" % node_id)
	elif String(effect.get("id", "")).strip_edges().is_empty():
		failures.append("talents: node %s capability id must be non-empty" % node_id)
	var effect_value: Variant = effect.get("value", null)
	var valid_number := typeof(effect_value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(effect_value)) and float(effect_value) > 0.0
	if not valid_number and effect_value != true:
		failures.append("talents: node %s effect value must be positive or true" % node_id)


func _validate_stance_effect(effect: Dictionary, node_id: String, failures: Array[String]) -> void:
	_check_exact_keys(effect, ["type", "near", "mid", "far"], [], "talent node %s stance effect" % node_id, failures)
	for stance in ["near", "mid", "far"]:
		if not effect.get(stance, null) is Dictionary:
			failures.append("talents: node %s stance '%s' must be an object" % [node_id, stance])
			continue
		var modifier: Dictionary = effect[stance]
		_check_exact_keys(modifier, ["parameter", "operation", "value"], [], "talent node %s stance '%s'" % [node_id, stance], failures)
		if String(modifier.get("parameter", "")) not in ["T", "d", "turn"]:
			failures.append("talents: node %s stance '%s' targets a forbidden parameter" % [node_id, stance])
		if String(modifier.get("operation", "")) not in ["multiply_bonus", "reduce_percent"]:
			failures.append("talents: node %s stance '%s' has an unknown operation" % [node_id, stance])
		var value: Variant = modifier.get("value", null)
		if not _is_finite_number(value) or float(value) <= 0.0:
			failures.append("talents: node %s stance '%s' value must be positive" % [node_id, stance])


func _valid_global_limits(value: Variant) -> bool:
	if not value is Dictionary or value.size() != 3:
		return false
	if int(value.get("points_per_node", 0)) != 1 or int(value.get("key_talents", 0)) != 2:
		return false
	var stances: Variant = value.get("stances", null)
	return stances is Array and _string_array(stances) == ["near", "mid", "far"]


func _integer_array(value: Variant) -> Array[int]:
	var result: Array[int] = []
	if not value is Array:
		return result
	for entry in value:
		if not _is_exact_integer(entry):
			return []
		result.append(int(entry))
	return result


func _string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if not value is Array:
		return result
	for entry in value:
		if typeof(entry) != TYPE_STRING:
			return []
		result.append(String(entry))
	return result


func _ingest(data: Dictionary) -> void:
	trees.clear()
	nodes.clear()
	tree_order.clear()
	for raw_tree in data.trees:
		var tree: Dictionary = raw_tree.duplicate(true)
		var node_order: Array[String] = []
		for raw_node in tree.nodes:
			var node: Dictionary = raw_node.duplicate(true)
			node["tree_id"] = String(tree.id)
			node["class_id"] = String(tree.class_id)
			nodes[String(node.id)] = node
			node_order.append(String(node.id))
		tree["node_order"] = node_order
		trees[String(tree.id)] = tree
		tree_order.append(String(tree.id))


func _read_json(path: String) -> Dictionary:
	if not ResourceLoader.exists(path) and not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}


func _check_exact_keys(value: Dictionary, required: Array, optional: Array = [], context: String = "", failures: Array[String] = []) -> void:
	for key in required:
		if not value.has(key):
			failures.append("%s: missing field '%s'" % [context, key])
	for key in value:
		if String(key) not in required and String(key) not in optional:
			failures.append("%s: unknown field '%s'" % [context, key])


func _check_forbidden_keys(value: Dictionary, context: String, failures: Array[String]) -> void:
	for key in FORBIDDEN_DATA_KEYS:
		if value.has(key):
			failures.append("%s: forbidden data key '%s'" % [context, key])


func _required_text(value: Dictionary, key: String, context: String, failures: Array[String]) -> String:
	var result := String(value.get(key, "")).strip_edges()
	if result.is_empty():
		failures.append("%s: %s must be non-empty text" % [context, key])
	return result


func _exact_integer(value: Variant) -> int:
	return int(value) if _is_exact_integer(value) else 0


func _is_exact_integer(value: Variant) -> bool:
	if not _is_finite_number(value):
		return false
	var number := float(value)
	return is_equal_approx(number, roundf(number))


func _is_finite_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))
