extends RefCounted
## Independent expectations read straight from the authored town scene, so tests
## compare runtime/manifest output against the scene's own declarations instead of
## against literal counts or against the report under test.

const SCENE := preload("res://content/rooms/town/hearthside.tscn")
const ORIGINAL_ART_ROOT := "res://art/production/p1/generated_world_v02/"
const EXPANSION_ART_ROOT := "res://art/production/p1/world_expansion_v01/"
const EXPANSION_GROUND := "res://art/production/p1/world_expansion_v01/town_ground.png"
const TOWN_ORDER_ART_ROOT := "res://art/production/p1/town_order_v01/"
const ART_ROOTS: Array[String] = [ORIGINAL_ART_ROOT, EXPANSION_ART_ROOT, TOWN_ORDER_ART_ROOT]
const PAIRED_POLICY := "paired_reveal"


static func art_path_accepted(path: String) -> bool:
	for root: String in ART_ROOTS:
		if path.begins_with(root):
			return true
	return false


## Keys:
##  * sort_ids: sorted binding ids of every SortRoot visual (the manifest's occlusion bindings).
##  * paired_ids: sorted subset whose reveal_policy is paired_reveal.
##  * unpaired_sort_ids: SortRoot visuals that are not paired (expected to be empty).
##  * ground_paths: texture_path of every Ground visual.
##  * ground_bridge_ids: sorted ids of Ground visuals whose id mentions a bridge.
##  * sort_bridge_ids: bridge ids that wrongly live in SortRoot (expected to be empty).
##  * static_ids: sorted ids of the movement surfaces GeometrySources/Static must derive
##    (circle shapes by id, polygons by per-triangle id after the degenerate-triangle skip).
##  * triangle_count / circle_count: the two kinds of static_ids.
static func load_expectations() -> Dictionary:
	var scene: Node = SCENE.instantiate()
	var result := {"sort_ids": [], "paired_ids": [], "unpaired_sort_ids": [], "ground_paths": [], "ground_bridge_ids": [],
		"sort_bridge_ids": [], "base_ground_paths": [], "static_ids": [], "triangle_count": 0, "circle_count": 0, "sort_paths": {}}
	for node: Node in scene.get_node("SortRoot").get_children():
		var id := String(node.get_meta("binding_id", ""))
		result.sort_ids.append(id)
		result.sort_paths[id] = String(node.get_meta("texture_path", ""))
		if String(node.get_meta("reveal_policy", "")) == PAIRED_POLICY:
			result.paired_ids.append(id)
		else:
			result.unpaired_sort_ids.append(id)
		if id.contains("bridge"):
			result.sort_bridge_ids.append(id)
	for node: Node in scene.get_node("Ground").get_children():
		var id := String(node.get_meta("binding_id", ""))
		result.ground_paths.append(String(node.get_meta("texture_path", "")))
		if id.contains("bridge"):
			result.ground_bridge_ids.append(id)
		else:
			result.base_ground_paths.append(String(node.get_meta("texture_path", "")))
	for shape: Polygon2D in scene.get_node("GeometrySources/Static").get_children():
		var id := String(shape.get_meta("binding_id", ""))
		if shape.has_meta("radius"):
			result.static_ids.append(id)
			result.circle_count += 1
			continue
		var indices := Geometry2D.triangulate_polygon(shape.polygon)
		for index: int in range(0, indices.size(), 3):
			var a := _snap(shape.polygon[indices[index]] + shape.position)
			var b := _snap(shape.polygon[indices[index + 1]] + shape.position)
			var c := _snap(shape.polygon[indices[index + 2]] + shape.position)
			if absf((b - a).cross(c - a)) <= 0.000001:
				continue
			result.static_ids.append("%s/%03d" % [id, index / 3])
			result.triangle_count += 1
	scene.free()
	for key: String in ["sort_ids", "paired_ids", "unpaired_sort_ids", "ground_bridge_ids", "sort_bridge_ids", "static_ids"]:
		result[key].sort()
	return result


static func sorted_strings(values: Array) -> Array:
	var result: Array = []
	for value: Variant in values:
		result.append(String(value))
	result.sort()
	return result


static func _snap(point: Vector2) -> Vector2:
	return Vector2(snappedf(point.x, 1.0 / 64.0), snappedf(point.y, 1.0 / 64.0))
