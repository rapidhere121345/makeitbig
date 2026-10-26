extends RefCounted
## Alpha-mask occlusion queries extracted from ArenaWorldView. Each source region
## of a texture is cached as horizontal visible runs, so exact pixel
## intersection stays cheap enough for the per-frame actor/structure prepass.
## Pure cache plus geometry: the world view keeps the sprite metadata and passes
## the texture, source rect and destination in.

## Alpha bounds stay conservative by one source pixel so antialiased edge pixels
## and the integer destination rounding cannot make an occluder too small.
const ALPHA_VISIBLE_BOUNDS_PADDING: float = 1.0
## A source pixel with any meaningful alpha is part of the visual occluder.  The
## mask is used only to decide whether two drawn cells really meet; the one
## pixel bounds padding above remains the conservative box used for diagnostics.
const ALPHA_OCCLUSION_THRESHOLD: float = 0.0

var _texture_images: Dictionary = {}
var _alpha_visible_bounds: Dictionary = {}
var _alpha_masks: Dictionary = {}


func clear() -> void:
	_texture_images.clear()
	_alpha_visible_bounds.clear()
	_alpha_masks.clear()


## Public read-only query used by actor and structure passes.  A missing or
## unreadable texture deliberately falls back to its destination box, matching
## the existing conservative art-box behavior.
func descriptor_intersects(descriptor: Dictionary, query: Rect2) -> bool:
	if descriptor.is_empty() or query.size.x <= 0.0 or query.size.y <= 0.0:
		return false
	var art_box: Rect2 = descriptor.get("art_box", descriptor.get("destination", Rect2()))
	if not art_box.intersects(query):
		return false
	if bool(descriptor.get("conservative", true)):
		return true
	var destination: Rect2 = descriptor.get("destination", Rect2())
	var source_rect: Rect2 = descriptor.get("source_rect", Rect2())
	var mask: Dictionary = descriptor.get("mask", {})
	var rows: Array = mask.get("rows", [])
	if rows.is_empty() or destination.size.x <= 0.0 or destination.size.y <= 0.0:
		return true
	var overlap := destination.intersection(query)
	var width := maxi(0, roundi(source_rect.size.x))
	var height := maxi(0, roundi(source_rect.size.y))
	if width <= 0 or height <= 0 or overlap.size.x <= 0.0 or overlap.size.y <= 0.0:
		return false
	var x0 := clampi(floori(overlap.position.x - destination.position.x), 0, width)
	var x1 := clampi(ceili(overlap.end.x - destination.position.x), 0, width)
	var y0 := clampi(floori(overlap.position.y - destination.position.y), 0, height)
	var y1 := clampi(ceili(overlap.end.y - destination.position.y), 0, height)
	if x0 >= x1 or y0 >= y1:
		return false
	var flipped := bool(descriptor.get("flip_x", false))
	for local_y in range(y0, y1):
		## flip_x mirrors columns only; the source row keeps its authored Y.
		var source_y := local_y
		if source_y < 0 or source_y >= rows.size():
			continue
		var runs: PackedInt32Array = rows[source_y]
		var source_x0 := width - x1 if flipped else x0
		var source_x1 := width - x0 if flipped else x1
		for run_index in range(0, runs.size(), 2):
			if int(runs[run_index]) < source_x1 and int(runs[run_index + 1]) > source_x0:
				return true
	return false


func visibility_intersects(visibility: Variant, query: Rect2) -> bool:
	if visibility is Array:
		for descriptor: Variant in visibility:
			if descriptor is Dictionary and descriptor_intersects(descriptor, query):
				return true
		return false
	if visibility is Dictionary:
		return descriptor_intersects(visibility, query)
	return false


func _texture_cache_key(texture: Texture2D, source_rect: Rect2) -> String:
	if texture == null:
		return "<null>|%s" % str(source_rect)
	var identity := texture.resource_path
	if identity.is_empty():
		identity = "instance:%d" % texture.get_instance_id()
	return "%s|%d,%d,%d,%d" % [identity, roundi(source_rect.position.x), roundi(source_rect.position.y), roundi(source_rect.size.x), roundi(source_rect.size.y)]


func _texture_image(texture: Texture2D) -> Image:
	if texture == null:
		return null
	var identity := texture.resource_path
	if identity.is_empty():
		identity = "instance:%d" % texture.get_instance_id()
	if not _texture_images.has(identity):
		_texture_images[identity] = texture.get_image()
	return _texture_images.get(identity) as Image


func describe(texture: Texture2D, source_rect: Rect2, destination: Rect2, flip_x: bool) -> Dictionary:
	var fallback := {
		"texture": texture,
		"source_rect": source_rect,
		"destination": destination,
		"flip_x": flip_x,
		"art_box": destination,
		"conservative": true,
	}
	if texture == null or source_rect.size.x <= 0.0 or source_rect.size.y <= 0.0:
		return fallback
	var mask := _alpha_mask(texture, source_rect)
	## Keep the public art box identical to sprite_art_box/frame_art_box.  The
	## descriptor's mask remains unpadded and decides exact pixel intersection.
	var visible := visible_bounds(texture, source_rect)
	if flip_x:
		visible.position.x = source_rect.size.x - (visible.position.x + visible.size.x)
	fallback["art_box"] = Rect2(destination.position + visible.position, visible.size)
	fallback["mask"] = mask
	fallback["conservative"] = bool(mask.get("conservative", true))
	return fallback


## Cache each source region as horizontal visible runs.  This keeps exact alpha
## intersection cheap enough for the per-frame actor/structure prepass while
## preserving holes in gates, hands, cores and broken walls.
func _alpha_mask(texture: Texture2D, source_rect: Rect2) -> Dictionary:
	var fallback := {
		"bounds": Rect2(Vector2.ZERO, source_rect.size),
		"rows": [],
		"conservative": true,
	}
	if texture == null or source_rect.size.x <= 0.0 or source_rect.size.y <= 0.0:
		return fallback
	var key := _texture_cache_key(texture, source_rect)
	if _alpha_masks.has(key):
		return _alpha_masks[key] as Dictionary
	var image := _texture_image(texture)
	if image == null or image.is_empty():
		_alpha_masks[key] = fallback
		return fallback
	var source := Rect2i(source_rect.position.round(), source_rect.size.round())
	var width := maxi(0, source.size.x)
	var height := maxi(0, source.size.y)
	var rows: Array = []
	var min_x := width
	var min_y := height
	var max_x := 0
	var max_y := 0
	var found := false
	var image_size := image.get_size()
	for local_y in range(height):
		var runs := PackedInt32Array()
		var run_start := -1
		for local_x in range(width):
			var image_x := source.position.x + local_x
			var image_y := source.position.y + local_y
			var visible := image_x >= 0 and image_y >= 0 and image_x < image_size.x and image_y < image_size.y and image.get_pixel(image_x, image_y).a > ALPHA_OCCLUSION_THRESHOLD
			if visible and run_start < 0:
				run_start = local_x
			if not visible and run_start >= 0:
				runs.append(run_start)
				runs.append(local_x)
				run_start = -1
		if run_start >= 0:
			runs.append(run_start)
			runs.append(width)
		if runs.size() > 0:
			found = true
			min_x = mini(min_x, int(runs[0]))
			max_x = maxi(max_x, int(runs[runs.size() - 1]))
			min_y = mini(min_y, local_y)
			max_y = local_y + 1
		rows.append(runs)
	var result := fallback.duplicate(true)
	result["rows"] = rows
	if found:
		result["bounds"] = Rect2(Vector2(min_x, min_y), Vector2(max_x - min_x, max_y - min_y))
		result["conservative"] = false
	_alpha_masks[key] = result
	return result


func visible_bounds(texture: Texture2D, source_rect: Rect2) -> Rect2:
	var fallback := Rect2(Vector2.ZERO, source_rect.size)
	if texture == null or source_rect.size.x <= 0.0 or source_rect.size.y <= 0.0:
		return fallback
	var key := _texture_cache_key(texture, source_rect)
	if _alpha_visible_bounds.has(key):
		return _alpha_visible_bounds[key] as Rect2
	var mask := _alpha_mask(texture, source_rect)
	var local: Rect2 = mask.get("bounds", fallback)
	if bool(mask.get("conservative", true)):
		_alpha_visible_bounds[key] = fallback
		return fallback
	local = local.grow(ALPHA_VISIBLE_BOUNDS_PADDING).intersection(fallback)
	if local.size.x <= 0.0 or local.size.y <= 0.0:
		local = fallback
	_alpha_visible_bounds[key] = local
	return local
