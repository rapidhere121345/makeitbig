class_name WorldPresenter
extends Node2D

const RoomSceneSetupPortScript := preload("res://src/runtime/world/room_scene_setup_port.gd")

## Presentation-only world tree. Gameplay systems submit positions and states;
## this node never writes them back and never draws collision geometry.

const LAYER_NAMES: Array[String] = ["Ground", "GroundEffects", "SortRoot", "Foreground"]

var ground_layer: Node2D
var ground_effects_layer: Node2D
var native_world_layer: Node2D
var sort_root: Node2D
var foreground_layer: Node2D
var _actor_views: Dictionary = {}
var _debug_geometry_visible := false
var _native_scene: Node
var _native_content: Array[Node] = []
var _native_bindings: Dictionary = {}


func _ready() -> void:
	_ensure_layers()


func _ensure_layers() -> void:
	if ground_layer != null:
		return
	ground_layer = Node2D.new()
	ground_layer.name = "Ground"
	ground_layer.z_index = -20
	add_child(ground_layer)
	ground_effects_layer = Node2D.new()
	ground_effects_layer.name = "GroundEffects"
	ground_effects_layer.z_index = -10
	add_child(ground_effects_layer)
	native_world_layer = Node2D.new()
	native_world_layer.name = "NativeWorld"
	native_world_layer.z_index = 0
	add_child(native_world_layer)
	sort_root = Node2D.new()
	sort_root.name = "SortRoot"
	sort_root.y_sort_enabled = true
	sort_root.z_index = 0
	add_child(sort_root)
	foreground_layer = Node2D.new()
	foreground_layer.name = "Foreground"
	foreground_layer.z_index = 20
	add_child(foreground_layer)


func mount_world_scene(scene: PackedScene, setup: RoomSceneSetupPort = null, native_contract: Dictionary = {}) -> Node:
	_ensure_layers()
	if scene == null or is_instance_valid(_native_scene):
		return null
	var instance := scene.instantiate()
	if instance == null:
		return null
	if setup != null:
		setup.setup(instance)
	var contract_path := String(native_contract.get("native_contract_path", ""))
	var author_root := instance.get_node_or_null(contract_path) if not contract_path.is_empty() else null
	if author_root == null:
		instance.free()
		return null
	var validation: Variant = author_root.call("validate_contract")
	var expected := native_contract.duplicate(true)
	expected.erase("native_contract_path")
	if not validation is Dictionary or not bool((validation as Dictionary).get("ok", false)) or (validation as Dictionary).get("value", null) != expected:
		instance.free()
		return null
	var bindings: Variant = native_contract.get("bindings", null)
	if not bindings is Dictionary:
		instance.free()
		return null
	var groups: Dictionary = {}
	for group_name: String in LAYER_NAMES:
		var group := author_root.get_node_or_null(group_name) as Node2D
		if group == null or group.transform != Transform2D.IDENTITY:
			instance.free()
			return null
		groups[group_name] = group
	for path: Variant in bindings:
		var node := author_root.get_node_or_null(String(path))
		if node == null:
			_native_bindings.clear()
			instance.free()
			return null
		_native_bindings[String(bindings[path])] = node
	native_world_layer.add_child(instance)
	_native_scene = instance
	for group_name: String in LAYER_NAMES:
		var group: Node2D = groups[group_name]
		var shared_layer := native_group(group_name)
		for child: Node in group.get_children():
			_detach_external_owners(child, child)
			child.reparent(shared_layer, false)
			_native_content.append(child)
	return instance


func _detach_external_owners(node: Node, subtree: Node) -> void:
	if node.owner != null and node.owner != subtree and not subtree.is_ancestor_of(node.owner):
		node.owner = null
	for child: Node in node.get_children():
		_detach_external_owners(child, subtree)


## The native author tree is read by setup before any content is rebound. Static
## buildings and dynamic actor views then share exactly this SortRoot.
func native_group(group_name: String) -> Node2D:
	_ensure_layers()
	match group_name:
		"Ground": return ground_layer
		"GroundEffects": return ground_effects_layer
		"SortRoot": return sort_root
		"Foreground": return foreground_layer
	return null


func native_binding_node(binding_id: String) -> Node:
	var node: Variant = _native_bindings.get(binding_id, null)
	return node if node is Node and is_instance_valid(node) else null


func unmount_world_scene() -> void:
	for actor_id: String in actor_ids():
		unregister_actor_view(actor_id)
	for node: Node in _native_content:
		if is_instance_valid(node) and not node.is_queued_for_deletion():
			if node.get_parent() != null:
				node.get_parent().remove_child(node)
			node.queue_free()
	_native_content.clear()
	_native_bindings.clear()
	if is_instance_valid(_native_scene):
		if _native_scene.get_parent() != null:
			_native_scene.get_parent().remove_child(_native_scene)
		_native_scene.queue_free()
	_native_scene = null


func register_actor_view(actor_id: String, view: Node2D) -> Dictionary:
	_ensure_layers()
	var id := actor_id.strip_edges()
	if id.is_empty() or view == null or _actor_views.has(id):
		return {"ok": false, "error": "invalid_or_duplicate_actor_view"}
	if view.get_parent() != null:
		view.reparent(sort_root)
	else:
		sort_root.add_child(view)
	view.set_meta("sort_rank", int(view.get_meta("sort_rank", 0)))
	view.set_meta("sort_stable_id", String(view.get_meta("sort_stable_id", id)))
	_actor_views[id] = view
	reorder_sort_root()
	return {"ok": true, "error": ""}


func unregister_actor_view(actor_id: String) -> void:
	var view: Variant = _actor_views.get(actor_id, null)
	_actor_views.erase(actor_id)
	if view is Node and is_instance_valid(view):
		if (view as Node).get_parent() != null:
			(view as Node).get_parent().remove_child(view)
		(view as Node).queue_free()


func sync_actor(actor_id: String, world_feet: Vector2, visual_offset := Vector2.ZERO, sort_rank: int = -1, stable_id: String = "") -> Dictionary:
	var view: Variant = _actor_views.get(actor_id, null)
	if not view is Node2D or not is_instance_valid(view):
		return {"ok": false, "error": "unknown_actor_view"}
	var actor_view := view as Node2D
	if sort_rank >= 0:
		actor_view.set_meta("sort_rank", sort_rank)
	if not stable_id.strip_edges().is_empty():
		actor_view.set_meta("sort_stable_id", stable_id)
	actor_view.position = world_feet + visual_offset
	reorder_sort_root()
	return {"ok": true, "error": ""}


## CanvasItem y-sort only compares the baseline.  Equal-baseline native and
## dynamic nodes therefore need an explicit sibling order so the shared
## presentation contract remains baseline/y -> rank -> stable id regardless of
## scene insertion order.  Native nodes may author sort_rank/sort_stable_id
## metadata; unnamed nodes use rank 0 and their stable scene name.
func reorder_sort_root() -> void:
	_ensure_layers()
	if sort_root == null:
		return
	var ordered: Array[Node] = []
	for child: Node in sort_root.get_children():
		ordered.append(child)
	ordered.sort_custom(func(left: Node, right: Node) -> bool:
			return _sort_child_precedes(left, right)
	)
	for index: int in ordered.size():
		if sort_root.get_child(index) != ordered[index]:
			sort_root.move_child(ordered[index], index)


func _sort_child_precedes(left: Node, right: Node) -> bool:
	var left_2d := left as Node2D
	var right_2d := right as Node2D
	var left_y := left_2d.position.y if left_2d != null else 0.0
	var right_y := right_2d.position.y if right_2d != null else 0.0
	if left_y != right_y:
		return left_y < right_y
	var left_rank := int(left.get_meta("sort_rank", 0))
	var right_rank := int(right.get_meta("sort_rank", 0))
	if left_rank != right_rank:
		return left_rank < right_rank
	var left_id := String(left.get_meta("sort_stable_id", left.name))
	var right_id := String(right.get_meta("sort_stable_id", right.name))
	if left_id != right_id:
		return left_id < right_id
	var left_name := String(left.name)
	var right_name := String(right.name)
	return left_name < right_name


func set_actor_visible(actor_id: String, visible: bool) -> bool:
	var view: Variant = _actor_views.get(actor_id, null)
	if not view is CanvasItem or not is_instance_valid(view):
		return false
	(view as CanvasItem).visible = visible
	return true


func set_debug_geometry_visible(visible: bool) -> void:
	_debug_geometry_visible = visible
	# Geometry diagnostics must live in a separate opt-in layer. The production
	# presenter never paints rectangles or polygons for a missing actor texture.
	if foreground_layer != null:
		foreground_layer.set_meta("debug_geometry_visible", _debug_geometry_visible)


func actor_ids() -> Array[String]:
	var ids: Array[String] = []
	for key: Variant in _actor_views.keys():
		ids.append(String(key))
	ids.sort()
	return ids


func presentation_report() -> Dictionary:
	return {
		"layers": LAYER_NAMES.duplicate(),
		"native_world_ready": native_world_layer != null,
		"actor_ids": actor_ids(),
		"debug_geometry_visible": _debug_geometry_visible,
		"sort_root_y_sort": sort_root != null and sort_root.y_sort_enabled,
		"native_content_count": _native_content.size(),
	}
