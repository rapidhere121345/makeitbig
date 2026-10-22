class_name EnvironmentObjectBaker
extends RefCounted

const Definition := preload("res://src/runtime/world/environment_object_definition.gd")
const Placement := preload("res://src/runtime/world/environment_object_placement.gd")
const TARGETS: Array[String] = ["Ground", "GroundEffects", "SortRoot", "GeometrySources", "GeometrySources/Static", "Sockets"]


## Expand detached author sources once. Repeating an unchanged expansion is a
## no-op; edited sources require a fresh author scene, never a runtime rebuild.
static func expand(root: Node2D) -> Dictionary:
	var errors: Array[String] = []
	_check_container(root, ".", errors)
	for path: String in TARGETS + ["EnvironmentObjects"]:
		_check_container(root.get_node_or_null(path), path, errors)
	if not errors.is_empty():
		return {"ok": false, "errors": errors}
	var placements: Array[Node] = root.get_node("EnvironmentObjects").get_children()
	placements.sort_custom(func(a: Node, b: Node) -> bool:
		return (a.placement_id if a is Placement else String(a.name)) < (b.placement_id if b is Placement else String(b.name)))
	var placement_ids := {}
	var entries: Array[Dictionary] = []
	var sources: Array = []
	for child: Node in placements:
		if not child is Placement:
			errors.append("invalid_environment_placement_node:" + String(child.name))
			continue
		var placement := child as Placement
		var placement_errors := placement.validate()
		errors.append_array(placement_errors)
		if placement_ids.has(placement.placement_id):
			errors.append("duplicate_environment_placement:" + placement.placement_id)
		placement_ids[placement.placement_id] = true
		if not placement_errors.is_empty():
			continue
		var definition := placement.definition
		sources.append([placement.placement_id, placement.position, definition.asset_id, definition.canvas_size,
			definition.visual_parts, definition.ground_parts, definition.footprints, definition.movement_envelopes, definition.sockets])
		_append_entries(placement, entries)
	if not errors.is_empty():
		return {"ok": false, "errors": errors}
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.binding_id < b.binding_id)
	var signature := _canonical(sources).sha256_text()
	if root.has_meta("_environment_source_signature") and root.get_meta("_environment_source_signature") != signature:
		errors.append("environment_source_changed_after_expansion")
	var bindings := {}
	_collect_bindings(root, bindings, errors)
	var new_entries: Array[Dictionary] = []
	for entry: Dictionary in entries:
		var existing: Node = bindings.get(entry.binding_id)
		if existing != null:
			if existing.get_parent() != root.get_node(entry.target) or existing.get_meta("_environment_entry", {}) != entry or not _matches(existing, entry):
				errors.append("environment_binding_conflict:" + entry.binding_id)
			continue
		var parent := root.get_node(entry.target)
		if parent.has_node(NodePath(_node_name(entry.binding_id))):
			errors.append("environment_node_name_conflict:" + entry.binding_id)
		new_entries.append(entry)
	if not new_entries.is_empty() and root.is_inside_tree():
		errors.append("environment_expansion_requires_detached_scene")
	if not errors.is_empty():
		return {"ok": false, "errors": errors}
	for entry: Dictionary in new_entries:
		var node := _make_node(entry)
		root.get_node(entry.target).add_child(node)
		node.owner = root
	root.set_meta("_environment_source_signature", signature)
	return {"ok": true, "errors": errors}


static func _append_entries(placement: Placement, entries: Array[Dictionary]) -> void:
	var definition := placement.definition
	for part: Dictionary in definition.visual_parts + definition.ground_parts:
		var sorted_part := part in definition.visual_parts
		var anchor: Vector2 = part.sort_anchor if sorted_part else Vector2.ZERO
		var entry := {
			"binding_id": placement.placement_id + "/" + String(part.part_id),
			"asset_id": definition.asset_id, "target": "SortRoot" if sorted_part else String(part.get("layer", "Ground")),
			"type": "visual", "position": placement.position + anchor,
			"offset": part.canvas_offset - anchor, "full_path": part.full_path,
			"sort_rank": int(part.get("sort_rank", 0)),
			"revealed_path": String(part.get("revealed_path", "")), "mask_path": String(part.get("mask_path", "")),
		}
		entries.append(entry)
	for shape: Dictionary in definition.movement_envelopes:
		var entry := {
			"binding_id": placement.placement_id + "/" + String(shape.part_id),
			"asset_id": definition.asset_id, "target": "GeometrySources/Static", "type": shape.type,
			"position": placement.position + (shape.center if shape.type == "circle" else Vector2.ZERO),
		}
		if shape.type == "circle":
			entry.radius = float(shape.radius)
		else:
			entry.points = shape.points.duplicate()
		entries.append(entry)
	for socket: Dictionary in definition.sockets:
		entries.append({
			"binding_id": placement.placement_id + "/" + String(socket.part_id),
			"asset_id": definition.asset_id, "target": "Sockets", "type": "socket",
			"position": placement.position + socket.position, "socket": socket.duplicate(true),
		})


static func _make_node(entry: Dictionary) -> Node2D:
	var node: Node2D
	if entry.type == "visual":
		var sprite := Sprite2D.new()
		sprite.centered = false
		sprite.offset = entry.offset
		sprite.texture = Definition.read_texture(entry.full_path)
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.set_meta("texture_path", entry.full_path)
		sprite.set_meta("sort_rank", entry.sort_rank)
		sprite.set_meta("sort_stable_id", entry.binding_id)
		sprite.set_meta("reveal_policy", "none" if entry.revealed_path.is_empty() else "authored_variant")
		if not entry.revealed_path.is_empty():
			sprite.set_meta("reveal_full_path", entry.full_path)
			sprite.set_meta("reveal_variant_path", entry.revealed_path)
			sprite.set_meta("reveal_mask_path", entry.mask_path)
		node = sprite
	elif entry.type == "socket":
		node = Marker2D.new()
		for key: String in entry.socket:
			if key not in ["part_id", "position"]:
				node.set_meta(key, entry.socket[key])
	else:
		var polygon := Polygon2D.new()
		polygon.visible = false
		if entry.type == "circle":
			polygon.set_meta("radius", entry.radius)
		else:
			polygon.polygon = entry.points
		node = polygon
	node.name = _node_name(entry.binding_id)
	node.position = entry.position
	node.set_meta("binding_id", entry.binding_id)
	node.set_meta("environment_asset_id", entry.asset_id)
	node.set_meta("_environment_entry", entry.duplicate(true))
	return node


static func _matches(node: Node, entry: Dictionary) -> bool:
	# Compare the flattened spatial authority rather than trusting a binding ID.
	if not node is Node2D or node.is_set_as_top_level() or node.position != entry.position or node.transform.x != Vector2.RIGHT or node.transform.y != Vector2.DOWN:
		return false
	if entry.type == "visual":
		if not node is Sprite2D or node.centered or node.offset != entry.offset or node.get_meta("texture_path", "") != entry.full_path or node.get_meta("sort_rank", null) != entry.sort_rank or node.get_meta("sort_stable_id", "") != entry.binding_id:
			return false
		var policy := "none" if entry.revealed_path.is_empty() else "authored_variant"
		if node.get_meta("reveal_policy", "") != policy:
			return false
		return policy == "none" or (node.get_meta("reveal_full_path", "") == entry.full_path and node.get_meta("reveal_variant_path", "") == entry.revealed_path and node.get_meta("reveal_mask_path", "") == entry.mask_path)
	if entry.type == "socket":
		if not node is Marker2D:
			return false
		for key: String in entry.socket:
			if key not in ["part_id", "position"] and node.get_meta(key, null) != entry.socket[key]:
				return false
		return true
	return node is Polygon2D and node.offset == Vector2.ZERO and (node.get_meta("radius", null) == entry.radius if entry.type == "circle" else not node.has_meta("radius") and node.polygon == entry.points)


static func _check_container(node: Node, path: String, errors: Array[String]) -> void:
	if not node is Node2D:
		errors.append("missing_environment_group:" + path)
	elif node.is_set_as_top_level() or node.transform != Transform2D.IDENTITY:
		errors.append("unsupported_environment_container_transform:" + path)


static func _collect_bindings(node: Node, bindings: Dictionary, errors: Array[String]) -> void:
	if node.has_meta("binding_id"):
		var id := String(node.get_meta("binding_id"))
		if bindings.has(id):
			errors.append("duplicate_environment_existing_binding:" + id)
		bindings[id] = node
	for child: Node in node.get_children():
		_collect_bindings(child, bindings, errors)


static func _node_name(binding_id: String) -> String:
	return "Environment_" + binding_id.sha256_text().substr(0, 24)


static func _canonical(value: Variant) -> String:
	if value is Dictionary:
		var keys: Array = value.keys()
		keys.sort()
		var parts: Array[String] = []
		for key: Variant in keys:
			parts.append(var_to_str(key) + ":" + _canonical(value[key]))
		return "{" + ",".join(parts) + "}"
	if value is Array:
		var parts: Array[String] = []
		for item: Variant in value:
			parts.append(_canonical(item))
		return "[" + ",".join(parts) + "]"
	return var_to_str(value)
