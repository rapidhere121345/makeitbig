class_name SceneAtmosphere
extends RefCounted
## Lightweight scene atmosphere in world/native-pixel coordinates.
##
## This is presentation-only vector drawing: no gameplay state, no random
## numbers, no per-frame texture allocation. The three call shapes are stable:
##   draw_base(canvas, rect, preset)  - cold ambient base under world art
##   draw_ground(canvas, rect, preset, lights) - directional depth and warm pools
##   draw_fore(canvas, rect, preset)  - bounded cold edge atmosphere
## Palette presets keep the same file in the arena, hamlet and hearth scenes.

const AMBIENT := {
	"arena": Color(0.34, 0.43, 0.55, 0.11),
	"hamlet": Color(0.31, 0.40, 0.52, 0.10),
	"hearth": Color(0.25, 0.34, 0.47, 0.14),
}
const FOG := {
	"arena": Color(0.43, 0.54, 0.63, 0.13),
	"hamlet": Color(0.37, 0.48, 0.59, 0.16),
	"hearth": Color(0.29, 0.40, 0.52, 0.22),
}
const WARM := Color(1.00, 0.67, 0.34)
const FIRE_CORE := Color(1.00, 0.84, 0.44)
const FIRE_TONGUE := Color(0.98, 0.55, 0.22)
const COLD_SHAFT := Color(0.49, 0.66, 0.88)
const GROUND_SHADE := Color(0.10, 0.14, 0.20)

const DIRECTION := Vector2(0.387192645, 0.921999614)
const MAX_WARM_LIGHTS := 6
const SOFT_LIGHT_SIZE := 64
const EDGE_SIZE := 96

static var _soft_light_texture: ImageTexture
static var _edge_texture: ImageTexture

static func preset_is_valid(preset: String) -> bool:
	return AMBIENT.has(preset)

static func draw_base(canvas: CanvasItem, rect: Rect2, preset: String) -> void:
	if canvas == null or not preset_is_valid(preset) or rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	canvas.draw_rect(rect, Color(AMBIENT[preset]))

static func draw_ground(
	canvas: CanvasItem,
	rect: Rect2,
	preset: String,
	lights: Array = [],
	include_fore := false
) -> void:
	if canvas == null or not preset_is_valid(preset) or rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	_draw_directional_shading(canvas, rect)
	_draw_light_pools(canvas, rect, lights)
	if include_fore:
		_draw_vertical_fog(canvas, rect, FOG[preset])
		_draw_edge_vignette(canvas, rect, FOG[preset])

static func draw_fore(canvas: CanvasItem, rect: Rect2, preset: String) -> void:
	if canvas == null or not preset_is_valid(preset) or rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	_draw_vertical_fog(canvas, rect, FOG[preset])
	_draw_edge_vignette(canvas, rect, FOG[preset])

static func draw_lights(canvas: CanvasItem, rect: Rect2, lights: Array = []) -> void:
	if canvas == null or rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	_draw_light_pools(canvas, rect, lights)

static func draw_directional_shade_for_test(canvas: CanvasItem, rect: Rect2) -> void:
	_draw_directional_shading(canvas, rect)

static func warm_light(position: Vector2, radius: float, strength: float = 0.20) -> Dictionary:
	return {"position": position, "radius": maxf(4.0, radius), "strength": clampf(strength, 0.0, 0.32)}

static func draw_fire(canvas: CanvasItem, sockets: Array, time: float) -> void:
	## Presentation-only spark flicker over the authored fire sources: small
	## integer-aligned warm sparks and a low-intensity glow. Deterministic from
	## the render clock: no RNG and no gameplay state writes, so replay hashes
	## and authoritative state stay untouched.
	if canvas == null:
		return
	for socket: Variant in sockets:
		if socket is not Dictionary:
			continue
		var point: Variant = socket.get("point", null)
		if point is not Vector2:
			continue
		var origin: Vector2 = point
		var seed := float(socket.get("seed", 0.0))
		var height := maxf(8.0, float(socket.get("height", 24.0)))
		var pulse := 0.5 + 0.5 * sin(time * 2.6 + seed * 1.7)
		canvas.draw_circle(origin + Vector2(0.0, -height * 0.16), height * 0.40, Color(FIRE_TONGUE, 0.05 + 0.03 * pulse))
		canvas.draw_circle(origin + Vector2(0.0, -height * 0.12), height * 0.20, Color(FIRE_CORE, 0.10 + 0.05 * pulse))
		for index in 4:
			var phase := fposmod(time * 0.62 + seed + float(index) * 0.27, 1.0)
			var sway := sin(time * 2.4 + seed * 2.3 + float(index) * 2.1) * height * 0.12
			var cell := Vector2.ONE * (2.0 - float(index % 2))
			var position := (origin + Vector2(sway * phase + float(index - 1) * height * 0.10, -phase * height)).floor()
			var color := FIRE_CORE.lerp(FIRE_TONGUE, phase)
			canvas.draw_rect(Rect2(position, cell), Color(color, (1.0 - phase) * 0.42))

static func atmosphere_report(preset: String, rect: Rect2, lights: Array = []) -> Dictionary:
	var usable: Array[Dictionary] = []
	for light in lights:
		if light is Dictionary and usable.size() < MAX_WARM_LIGHTS:
			var point: Variant = light.get("position", null)
			if point is Vector2:
				usable.append(light)
	return {
		"preset": preset,
		"valid": preset_is_valid(preset),
		"rect": rect,
		"warm_lights": usable,
		"soft_light_texture_size": _soft_light_texture.get_size() if _soft_light_texture != null else Vector2i(SOFT_LIGHT_SIZE, SOFT_LIGHT_SIZE),
		"edge_texture_size": _edge_texture.get_size() if _edge_texture != null else Vector2i(EDGE_SIZE, EDGE_SIZE),
		"grid_lines": 0,
		"scanline_bands": 0,
		"ground_pass": preset_is_valid(preset) and rect.size.x > 0.0 and rect.size.y > 0.0,
		"clipped": rect.size.x > 0.0 and rect.size.y > 0.0,
	}

static func _draw_directional_shading(canvas: CanvasItem, rect: Rect2) -> void:
	# Two broad, skewed shade fields replace the earlier 16px grid. Their edges
	# intentionally do not align with either axis, so depth reads as cast light
	# rather than tiling or scanlines.
	var skew := Vector2(rect.size.y * 0.16, rect.size.y * 0.07)
	var upper := PackedVector2Array([
		rect.position + Vector2(rect.size.x * 0.05, 0.0),
		rect.position + Vector2(rect.size.x * 0.48, 0.0) + skew,
		rect.position + Vector2(rect.size.x * 0.38, rect.size.y) + skew,
		rect.position + Vector2(-rect.size.x * 0.02, rect.size.y),
	])
	canvas.draw_colored_polygon(upper, Color(GROUND_SHADE, 0.055))
	var lower := PackedVector2Array([
		rect.position + Vector2(rect.size.x * 0.62, 0.0) + skew * 0.35,
		rect.position + Vector2(rect.size.x * 1.02, 0.0) + skew,
		rect.position + Vector2(rect.size.x * 0.94, rect.size.y) + skew * 0.65,
		rect.position + Vector2(rect.size.x * 0.52, rect.size.y),
	])
	canvas.draw_colored_polygon(lower, Color(GROUND_SHADE, 0.042))

static func _draw_light_pools(canvas: CanvasItem, rect: Rect2, lights: Array) -> void:
	for light in lights:
		if light is not Dictionary:
			continue
		var point: Variant = light.get("position", null)
		if point is not Vector2:
			continue
		var center: Vector2 = point
		if center.distance_to(rect.get_center()) > rect.size.length() + float(light.get("radius", 0.0)):
			continue
		var radius := maxf(4.0, float(light.get("radius", 16.0)))
		var strength := clampf(float(light.get("strength", 0.20)), 0.0, 0.32)
		var size := Vector2(radius * 2.06, radius * 1.04)
		canvas.draw_texture_rect(
			_soft_light(),
			Rect2(center - size * 0.5, size),
			false,
			Color(WARM, strength),
			false
		)
		var core := Vector2(radius * 0.78, radius * 0.42)
		canvas.draw_texture_rect(
			_soft_light(),
			Rect2(center - core * 0.5, core),
			false,
			Color(WARM, strength * 0.42),
			false
		)
		var shaft := Vector2(radius * 1.05, radius * 0.20)
		canvas.draw_texture_rect(
			_soft_light(),
			Rect2(center + Vector2(-radius * 0.28, -radius * 0.24) - shaft * 0.5, shaft),
			false,
			Color(COLD_SHAFT, strength * 0.16),
			false
		)

static func _draw_vertical_fog(canvas: CanvasItem, rect: Rect2, color: Color) -> void:
	canvas.draw_texture_rect(_edge_falloff(), rect, false, Color(color.r, color.g, color.b, color.a), false)

static func _draw_edge_vignette(canvas: CanvasItem, rect: Rect2, color: Color) -> void:
	# Share the smooth falloff; opaque rectangular strips read as UI borders.
	canvas.draw_texture_rect(_edge_falloff(), rect, false, Color(GROUND_SHADE, color.a * 0.35), false)

static func _soft_light() -> ImageTexture:
	if _soft_light_texture == null:
		var image := Image.create(SOFT_LIGHT_SIZE, SOFT_LIGHT_SIZE, false, Image.FORMAT_RGBA8)
		for y in SOFT_LIGHT_SIZE:
			for x in SOFT_LIGHT_SIZE:
				var point := Vector2((float(x) + 0.5) / float(SOFT_LIGHT_SIZE) - 0.5, (float(y) + 0.5) / float(SOFT_LIGHT_SIZE) - 0.5)
				var distance := point.length() * 2.0
				var falloff := clampf(1.0 - distance, 0.0, 1.0)
				falloff = pow(falloff, 1.48)
				image.set_pixel(x, y, Color(1.0, 1.0, 1.0, falloff))
		_soft_light_texture = ImageTexture.create_from_image(image)
	return _soft_light_texture

static func _edge_falloff() -> ImageTexture:
	if _edge_texture == null:
		var image := Image.create(EDGE_SIZE, EDGE_SIZE, false, Image.FORMAT_RGBA8)
		for y in EDGE_SIZE:
			for x in EDGE_SIZE:
				var point := Vector2((float(x) + 0.5) / float(EDGE_SIZE), (float(y) + 0.5) / float(EDGE_SIZE))
				var edge := maxf(absf(point.x - 0.5), absf(point.y - 0.5)) * 2.0
				var falloff := clampf((edge - 0.54) / 0.46, 0.0, 1.0)
				falloff = pow(falloff, 1.32)
				image.set_pixel(x, y, Color(1.0, 1.0, 1.0, falloff))
		_edge_texture = ImageTexture.create_from_image(image)
	return _edge_texture
