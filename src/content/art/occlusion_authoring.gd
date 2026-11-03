class_name OcclusionAuthoring
extends RefCounted

## The authored occlusion contract shared by the world mounts (runtime), the
## bake pipeline and the occlusion controllers (presentation): the policy ids,
## the paired-reveal detection-rect containment rule and the primitive-fade
## volume payload. Pure functions over authored data; no scene or presentation
## state.

const PRIMITIVE_FADE_POLICY := "primitive_fade"
const PAIRED_REVEAL_POLICY := "paired_reveal"
## A paired-reveal detection rect must contain the opaque texels grown by this
## margin (local canvas pixels).
const DETECTION_GROW := 8.0


## The opaque-texel bounds of one texture image. Empty when nothing is
## opaque; callers treat that as "no containment requirement to prove".
static func occupied_aabb(image: Image) -> Rect2:
	if image == null or image.is_empty():
		return Rect2()
	if image.is_compressed() and image.decompress() != OK:
		return Rect2()
	var min_p := Vector2i(1073741824, 1073741824)
	var max_p := Vector2i(-1073741824, -1073741824)
	for y: int in image.get_height():
		for x: int in image.get_width():
			if image.get_pixel(x, y).a > 0.0:
				min_p.x = mini(min_p.x, x)
				min_p.y = mini(min_p.y, y)
				max_p.x = maxi(max_p.x, x)
				max_p.y = maxi(max_p.y, y)
	if max_p.x < min_p.x:
		return Rect2()
	return Rect2(Vector2(min_p), Vector2(max_p - min_p) + Vector2.ONE)


## Shared fail-closed detection-rect check used by scene mounts, the baker
## path and the author definition. Returns an error string or "".
static func detection_rect_error(rect: Variant, opaque_image: Image) -> String:
	if not rect is Rect2:
		return "paired_reveal_missing_rect"
	var area: Rect2 = rect
	if not area.position.is_finite() or not area.size.is_finite() or area.size.x <= 0.0 or area.size.y <= 0.0:
		return "paired_reveal_invalid_rect"
	var occupied := occupied_aabb(opaque_image)
	if occupied.has_area() and not area.encloses(occupied.grow(DETECTION_GROW)):
		return "paired_reveal_rect_too_small"
	return ""


## Deterministic plain-value payload of placement-translated volumes, shared
## by the presenter audit and the scene-root presentation fingerprint.
static func volumes_payload(volumes: Variant) -> Array:
	var payload: Array = []
	if not volumes is Array:
		return payload
	for volume: Variant in volumes:
		if not volume is Dictionary:
			continue
		var data: Dictionary = volume
		if data.get("type") == "circle":
			var center: Vector2 = data.get("center", Vector2.INF)
			payload.append({"type": "circle", "center": [center.x, center.y], "radius": float(data.get("radius", 0.0))})
		elif data.get("type") == "polygon":
			var points: Array = []
			for point: Vector2 in data.get("points", PackedVector2Array()):
				points.append([point.x, point.y])
			payload.append({"type": "polygon", "points": points})
	return payload


## Fail-closed validation of one authored primitive-fade volume (a circle or a
## non-degenerate polygon). Returns an error string or "".
static func volume_error(volume: Variant) -> String:
	if not volume is Dictionary:
		return "primitive_fade_invalid_volume"
	var data: Dictionary = volume
	if data.get("type") == "circle":
		var center: Variant = data.get("center", null)
		if not center is Vector2 or not (center as Vector2).is_finite():
			return "primitive_fade_invalid_volume_center"
		if not _positive(data.get("radius", null)):
			return "primitive_fade_invalid_volume_radius"
		return ""
	if data.get("type") == "polygon":
		var points: Variant = data.get("points", null)
		if not points is PackedVector2Array:
			return "primitive_fade_invalid_volume_polygon"
		var packed: PackedVector2Array = points
		if packed.size() < 3:
			return "primitive_fade_invalid_volume_polygon"
		for point: Vector2 in packed:
			if not point.is_finite():
				return "primitive_fade_invalid_volume_polygon"
		## A collinear "polygon" still triangulates in this engine build,
		## so a near-zero signed area is the real degeneracy test.
		if Geometry2D.triangulate_polygon(packed).is_empty() or absf(SpatialShape.polygon_signed_area(packed)) <= 0.000001:
			return "primitive_fade_degenerate_volume_polygon"
		return ""
	return "primitive_fade_unknown_volume_type"


static func _positive(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) > 0.0
