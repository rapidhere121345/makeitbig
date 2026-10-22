class_name AuthoredRevealController
extends RefCounted

## Renderer-owned state for authored upper-part variants. Its immutable mask
## describes the FULL state even while the revealed image is being drawn.
## All query inputs are detached presentation values; no gameplay writes.
const RevealShader := preload("res://src/presentation/occlusion/authored_reveal.gdshader")
const SortRelation := preload("res://src/presentation/occlusion_query.gd")
const ENTER_COVER := 0.12
const EXIT_COVER := 0.04
const TRANSITION_SECONDS := 0.15

var _pieces: Dictionary = {}


func has_piece(stable_id: String) -> bool:
	return _pieces.has(stable_id)


func register_piece(stable_id: String, sprite: Sprite2D, revealed: Texture2D, full_mask: Image) -> Dictionary:
	if stable_id.is_empty() or sprite == null or sprite.texture == null or revealed == null or full_mask == null:
		return {"ok": false, "error": "reveal_missing_resource"}
	if _pieces.has(stable_id):
		return {"ok": false, "error": "reveal_duplicate_binding:" + stable_id}
	if sprite.region_enabled or sprite.hframes != 1 or sprite.vframes != 1 or sprite.flip_h or sprite.flip_v:
		return {"ok": false, "error": "reveal_requires_single_canvas:" + stable_id}
	var size := Vector2i(sprite.texture.get_size())
	if size != Vector2i(revealed.get_size()) or size != full_mask.get_size():
		return {"ok": false, "error": "reveal_canvas_mismatch:" + stable_id}
	var mask := full_mask.duplicate() as Image
	if mask.is_compressed() and mask.decompress() != OK:
		return {"ok": false, "error": "reveal_mask_decode:" + stable_id}
	var material := ShaderMaterial.new()
	material.shader = RevealShader
	material.set_shader_parameter("revealed_texture", revealed)
	material.set_shader_parameter("reveal_weight", 0.0)
	_pieces[stable_id] = {"sprite": weakref(sprite), "previous_material": sprite.material,
		"material": material, "mask": mask, "open": false, "weight": 0.0, "coverage": 0.0}
	sprite.material = material
	return {"ok": true, "error": ""}


func register_native_piece(stable_id: String, sprite: Sprite2D) -> Dictionary:
	var variant_path := String(sprite.get_meta("reveal_variant_path", ""))
	var mask_path := String(sprite.get_meta("reveal_mask_path", ""))
	var variant := _read_texture(variant_path)
	var mask_texture := _read_texture(mask_path)
	if variant == null or mask_texture == null:
		return {"ok": false, "error": "reveal_asset_missing:" + stable_id}
	return register_piece(stable_id, sprite, variant, mask_texture.get_image())


static func _read_texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	# Fresh author previews may precede editor import. Exported production
	# assets resolve through ResourceLoader above.
	if FileAccess.file_exists(path):
		var image := Image.new()
		if image.load(path) == OK:
			return ImageTexture.create_from_image(image)
	return null


## subjects carry stable_id, baseline_y, rank and a world-space readability_box.
## The box is a stable head/torso region, not an animation cell's transparent
## margins. Any protected subject can request reveal; a graze cannot cancel it.
func update(entries: Array, subjects: Array, delta: float) -> void:
	var by_id := {}
	for entry: Dictionary in entries:
		by_id[String(entry.stable_id)] = entry
	for stable_id: String in _pieces.keys():
		var state: Dictionary = _pieces[stable_id]
		var sprite: Variant = (state.sprite as WeakRef).get_ref()
		if sprite == null:
			_pieces.erase(stable_id)
			continue
		var maximum := 0.0
		if by_id.has(stable_id):
			var part: Dictionary = by_id[stable_id]
			for subject: Dictionary in subjects:
				if SortRelation.is_front(part, subject):
					maximum = maxf(maximum, mask_coverage(state.mask, part.art_box, subject.readability_box))
		var was_open := bool(state.open)
		state.open = maximum > EXIT_COVER if was_open else maximum >= ENTER_COVER
		state.coverage = maximum
		state.weight = move_toward(float(state.weight), 1.0 if state.open else 0.0,
			maxf(delta, 0.0) / TRANSITION_SECONDS)
		(state.material as ShaderMaterial).set_shader_parameter("reveal_weight", state.weight)


## Pixel-cell intersection against the immutable full-state alpha mask.
## Transparent gaps contribute no coverage. This reads a cached CPU image,
## never a GPU framebuffer or a collision shape.
static func mask_coverage(mask: Image, world_box: Rect2, subject_box: Rect2) -> float:
	if world_box.size.x <= 0.0 or world_box.size.y <= 0.0 or subject_box.get_area() <= 0.0:
		return 0.0
	var overlap := world_box.intersection(subject_box)
	if not overlap.has_area():
		return 0.0
	var size := mask.get_size()
	var pixel_size := world_box.size / Vector2(size)
	var lo := ((overlap.position - world_box.position) / pixel_size).floor()
	var hi := ((overlap.end - world_box.position) / pixel_size).ceil()
	var covered := 0.0
	for y in range(maxi(0, int(lo.y)), mini(size.y, int(hi.y))):
		for x in range(maxi(0, int(lo.x)), mini(size.x, int(hi.x))):
			if mask.get_pixel(x, y).a < 0.5:
				continue
			var pixel := Rect2(world_box.position + Vector2(x, y) * pixel_size, pixel_size)
			covered += pixel.intersection(overlap).get_area()
	return clampf(covered / subject_box.get_area(), 0.0, 1.0)


func reset() -> void:
	for state: Dictionary in _pieces.values():
		state.open = false
		state.weight = 0.0
		state.coverage = 0.0
		(state.material as ShaderMaterial).set_shader_parameter("reveal_weight", 0.0)


func clear() -> void:
	for state: Dictionary in _pieces.values():
		var sprite: Variant = (state.sprite as WeakRef).get_ref()
		if sprite != null and sprite.material == state.material:
			sprite.material = state.previous_material
	_pieces.clear()


func report() -> Dictionary:
	var result := {}
	for stable_id: String in _pieces:
		var state: Dictionary = _pieces[stable_id]
		result[stable_id] = {"open": state.open, "weight": state.weight, "coverage": state.coverage}
	return result
