extends Node2D
## A hand-traced foreground from the same full-town image. No rectangular floor
## crop joins the feet sort. UVs always refer to the decoded source dimensions.
var scene_texture: Texture2D
var world_size := Vector2(1024, 640)
var world_polygon := PackedVector2Array()
var cut_window := Rect2()
var cut_alpha := 1.0


func overlaps(window: Rect2) -> bool:
	return not Geometry2D.intersect_polygons(world_polygon, _rect_polygon(window)).is_empty()


func set_cutaway(window: Rect2, alpha: float) -> void:
	if window == cut_window and is_equal_approx(alpha, cut_alpha):
		return
	cut_window = window
	cut_alpha = alpha
	queue_redraw()


func _draw() -> void:
	if scene_texture == null or world_polygon.size() < 3:
		return
	for fragment: Dictionary in fragments():
		_draw_fragment(fragment.points, float(fragment.alpha))


func fragments() -> Array[Dictionary]:
	if cut_alpha >= 1.0 or not overlaps(cut_window):
		return [{"points": world_polygon, "alpha": 1.0}]
	# Four disjoint bands avoid a polygon subtraction returning a hole contour
	# which draw_polygon would fill again. Only the hero window is translucent.
	var core := cut_window.intersection(Rect2(Vector2.ZERO, world_size))
	var bands: Array[Rect2] = [Rect2(0, 0, world_size.x, core.position.y),
		Rect2(0, core.end.y, world_size.x, world_size.y - core.end.y),
		Rect2(0, core.position.y, core.position.x, core.size.y),
		Rect2(core.end.x, core.position.y, world_size.x - core.end.x, core.size.y), core]
	var result: Array[Dictionary] = []
	for index in bands.size():
		if bands[index].size.x <= 0.0 or bands[index].size.y <= 0.0:
			continue
		for polygon: PackedVector2Array in Geometry2D.intersect_polygons(world_polygon, _rect_polygon(bands[index])):
			result.append({"points": polygon, "alpha": cut_alpha if index == 4 else 1.0})
	return result


func _draw_fragment(points: PackedVector2Array, alpha: float) -> void:
	var local := PackedVector2Array()
	var uv := PackedVector2Array()
	for point: Vector2 in points:
		local.append(point - position)
		uv.append(point / world_size)
	draw_polygon(local, PackedColorArray([Color(1, 1, 1, alpha)]), uv, scene_texture)


func _rect_polygon(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])
