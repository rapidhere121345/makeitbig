extends RefCounted
## Ground-plane rendering only. Cached native-pixel masks, no authored texture
## mutation, collision reads, random state, animation offsets or per-frame images.
const SHADOW := Color(0.025, 0.032, 0.045)
const AMBER := Color(1.0, 0.63, 0.28)
const ARCANE := Color(0.30, 0.68, 0.78)
const MAX_BASE_STAMPS := 128
const POOL_HEIGHT_RATIO := 0.85
static var _contact_texture: ImageTexture
static var _pool_texture: ImageTexture
static var _bases: Dictionary = {}

static func _radial(contact: bool) -> ImageTexture:
	if contact and _contact_texture != null:
		return _contact_texture
	if not contact and _pool_texture != null:
		return _pool_texture
	var image := Image.create(64, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 64:
			var p := Vector2((x + 0.5 - 32.0) / 32.0, (y + 0.5 - 16.0) / 16.0)
			var edge := clampf(1.0 - p.length(), 0.0, 1.0)
			# A dense contact core seats the feet; only its outer edge feathers.
			# Light pools retain the gentler falloff across their whole footprint.
			var alpha := clampf(edge * 3.0, 0.0, 1.0) if contact else pow(edge, 1.7)
			# Eight steps retain quiet pixel clusters instead of a smooth bloom.
			alpha = floorf(alpha * 8.0) / 8.0
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	var texture := ImageTexture.create_from_image(image)
	if contact:
		_contact_texture = texture
	else:
		_pool_texture = texture
	return texture

static func draw_contact(canvas: CanvasItem, feet: Vector2, size: Vector2, strength: float = 0.42) -> void:
	if canvas == null or size.x <= 0.0 or size.y <= 0.0:
		return
	# Expose the contact just below the boots instead of hiding its strongest
	# rows underneath the sprite. The upper rows still meet the feet anchor.
	var rect := Rect2((feet + Vector2(0.0, 2.0) - size * 0.5).round(), size.round())
	canvas.draw_texture_rect(_radial(true), rect, false, Color(SHADOW, clampf(strength, 0.0, 0.6)))

## The lowest opaque contour within the sprite's base band supplies the seam.
## Roof/canopy pixels high above the base cannot create a floating shadow.
## Anchor is relative to region, as with draw_texture_rect_region's destination.
static func base_stamp(texture: Texture2D, region: Rect2, anchor: Vector2) -> Dictionary:
	if texture == null or not region.has_area():
		return {}
	var identity := texture.resource_path if not texture.resource_path.is_empty() else str(texture.get_instance_id())
	var key := "%s:%s:%s" % [identity, region, anchor]
	if _bases.has(key):
		var cached: Dictionary = _bases[key]
		_bases.erase(key)
		_bases[key] = cached
		return cached
	var source := texture.get_image()
	if source == null:
		return {}
	if source.is_compressed() and source.decompress() != OK:
		return {}
	var crop := Rect2i(region).intersection(Rect2i(Vector2i.ZERO, source.get_size()))
	if not crop.has_area():
		return {}
	var bottoms := PackedInt32Array()
	bottoms.resize(crop.size.x)
	bottoms.fill(-1)
	var lowest := -1
	for x in crop.size.x:
		for y in range(crop.size.y - 1, -1, -1):
			if source.get_pixel(crop.position.x + x, crop.position.y + y).a > 0.5:
				bottoms[x] = y
				lowest = maxi(lowest, y)
				break
	if lowest < 0:
		return {}
	var band := maxi(8, ceili(crop.size.y * 0.27))
	var top := maxi(0, lowest - band)
	var image := Image.create(crop.size.x + 16, lowest - top + 14, false, Image.FORMAT_RGBA8)
	for x in bottoms.size():
		var y: int = bottoms[x]
		if y < top:
			continue
		for down in range(-1, 10):
			for spread in range(-3, 5):
				var point := Vector2i(x + 5 + spread + int(maxi(down, 0) * 0.35), y - top + 2 + down)
				if point.x < 0 or point.y < 0 or point.x >= image.get_width() or point.y >= image.get_height():
					continue
				var alpha := 0.43 * maxf(0.0, 1.0 - absf(float(down) - 1.0) / 9.0) * (1.0 - absf(float(spread)) / 5.0)
				if alpha > image.get_pixelv(point).a:
					image.set_pixelv(point, Color(SHADOW, alpha))
	var result := {"texture": ImageTexture.create_from_image(image), "offset": Vector2(-5, top - 2) - anchor + Vector2(crop.position) - region.position,
		"base_y": lowest - anchor.y, "source_unchanged": true}
	while _bases.size() >= MAX_BASE_STAMPS:
		_bases.erase(_bases.keys()[0])
	_bases[key] = result
	return result

static func draw_base(canvas: CanvasItem, texture: Texture2D, region: Rect2, anchor: Vector2, feet: Vector2, strength: float = 1.0) -> void:
	var stamp := base_stamp(texture, region, anchor)
	if canvas != null and not stamp.is_empty():
		canvas.draw_texture(stamp.texture, (feet + (stamp.offset as Vector2)).round(), Color(1.0, 1.0, 1.0, clampf(strength, 0.0, 1.0)))

static func draw_pool(canvas: CanvasItem, feet: Vector2, radius: float, color: Color, strength: float = 0.2) -> void:
	if canvas == null or radius <= 0.0:
		return
	var size := Vector2(radius * 2.0, radius * POOL_HEIGHT_RATIO)
	canvas.draw_texture_rect(_radial(false), Rect2((feet - size * 0.5).round(), size.round()), false,
		Color(color, clampf(strength, 0.0, 0.28)))

## Color-only light response. Alpha is always one: reveal and sprite coverage
## remain entirely controlled by their existing rendering paths.
static func illumination(feet: Vector2, lights: Array) -> Color:
	var warmth := Vector3.ZERO
	for light: Dictionary in lights:
		var radius := float(light.get("radius", 0.0))
		if radius <= 0.0:
			continue
		var delta: Vector2 = feet - (light.position as Vector2)
		delta.y *= 2.0 / POOL_HEIGHT_RATIO
		var weight := pow(clampf(1.0 - delta.length() / radius, 0.0, 1.0), 2.0) * float(light.get("strength", 0.2))
		var color: Color = light.get("color", AMBER)
		warmth += Vector3(color.r, color.g, color.b) * weight * 0.65
	return Color(1.0 + minf(warmth.x, 0.16), 1.0 + minf(warmth.y, 0.13), 1.0 + minf(warmth.z, 0.12), 1.0)

static func draw_dressing(canvas: CanvasItem, texture: Texture2D, anchor: Vector2, feet: Vector2, family: String) -> void:
	if texture == null:
		return
	if family == "votives":
		draw_pool(canvas, feet, 23.0, AMBER, 0.19)
	elif family == "relic":
		draw_pool(canvas, feet, 18.0, ARCANE, 0.09)
	draw_base(canvas, texture, Rect2(Vector2.ZERO, texture.get_size()), anchor, feet, 0.95)
	canvas.draw_texture(texture, (feet - anchor).round())
