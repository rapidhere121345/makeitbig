extends RefCounted
## Outpainted terrain fills camera overscan. The reviewed floor remains opaque
## over the playable interior; a narrow edge blend joins it to its expansion.
## Neither layer changes the native movement extent.

const EXTENSION_ORIGIN := Vector2(-256.0, -192.0)
const BLEND := 32.0

static func draw(canvas: CanvasItem, floor_texture: Texture2D, extension: Texture2D, size: Vector2) -> void:
	canvas.draw_texture_rect(extension, Rect2(EXTENSION_ORIGIN, extension.get_size()), false)
	var xs := [0.0, BLEND, size.x - BLEND, size.x]
	var ys := [0.0, BLEND, size.y - BLEND, size.y]
	var opacity := [0.0, 1.0, 1.0, 0.0]
	for y in range(3):
		for x in range(3):
			var points := PackedVector2Array([Vector2(xs[x], ys[y]), Vector2(xs[x + 1], ys[y]), Vector2(xs[x + 1], ys[y + 1]), Vector2(xs[x], ys[y + 1])])
			var uv := PackedVector2Array()
			for point in points:
				uv.append(point / size)
			var colors := PackedColorArray([
				Color(1, 1, 1, opacity[x] * opacity[y]),
				Color(1, 1, 1, opacity[x + 1] * opacity[y]),
				Color(1, 1, 1, opacity[x + 1] * opacity[y + 1]),
				Color(1, 1, 1, opacity[x] * opacity[y + 1]),
			])
			canvas.draw_polygon(points, colors, uv, floor_texture)
