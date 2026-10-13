class_name WorldPresenter
extends Node2D

## Presentation-only world tree. Gameplay systems submit positions and states;
## this node never writes them back and never draws collision geometry.

const LAYER_NAMES: Array[String] = ["Ground", "GroundEffects", "SortRoot", "Foreground"]

var ground_layer: Node2D
var ground_effects_layer: Node2D
var sort_root: Node2D
var foreground_layer: Node2D
var _actor_views: Dictionary = {}
var _debug_geometry_visible := false


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
	sort_root = Node2D.new()
	sort_root.name = "SortRoot"
	sort_root.y_sort_enabled = true
	sort_root.z_index = 0
	add_child(sort_root)
	foreground_layer = Node2D.new()
	foreground_layer.name = "Foreground"
	foreground_layer.z_index = 20
	add_child(foreground_layer)


func mount_world_scene(scene: PackedScene) -> Node:
	_ensure_layers()
	if scene == null:
		return null
	var instance := scene.instantiate()
	if instance == null:
		return null
	ground_layer.add_child(instance)
	return instance


func register_actor_view(actor_id: String, view: Node2D) -> Dictionary:
	_ensure_layers()
	var id := actor_id.strip_edges()
	if id.is_empty() or view == null or _actor_views.has(id):
		return {"ok": false, "error": "invalid_or_duplicate_actor_view"}
	if view.get_parent() != null:
		view.reparent(sort_root)
	else:
		sort_root.add_child(view)
	_actor_views[id] = view
	return {"ok": true, "error": ""}


func unregister_actor_view(actor_id: String) -> void:
	var view: Variant = _actor_views.get(actor_id, null)
	_actor_views.erase(actor_id)
	if view is Node and is_instance_valid(view):
		(view as Node).queue_free()


func sync_actor(actor_id: String, world_feet: Vector2, visual_offset := Vector2.ZERO) -> Dictionary:
	var view: Variant = _actor_views.get(actor_id, null)
	if not view is Node2D or not is_instance_valid(view):
		return {"ok": false, "error": "unknown_actor_view"}
	var actor_view := view as Node2D
	actor_view.position = world_feet + visual_offset
	return {"ok": true, "error": ""}


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
		"actor_ids": actor_ids(),
		"debug_geometry_visible": _debug_geometry_visible,
		"sort_root_y_sort": sort_root != null and sort_root.y_sort_enabled,
	}
