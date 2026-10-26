class_name PairedRevealController
extends RefCounted

## Whole-object paired-texture reveal for generated environment assets. One
## registered piece is a single Sprite2D whose opaque texture crossfades with
## its baked transparent variant on the SAME canvas through one premultiplied
## shader mix — the variant's authored alpha is used exactly once, the piece's
## own modulate.a is never touched, and there is no region mask, no split
## band and no per-pixel actor cutout anywhere in the path.
##
## Detection is one authored detection rectangle in world space (mounted meta
## "occlusion_rect"; the author source is the occupied AABB grown by
## DETECTION_GROW in local canvas coordinates, placement-translated). A piece
## opens while it sorts in front of a protected actor AND that rectangle
## covers enough of the actor's readability box; hysteresis keeps a graze
## from flickering the pair. All query inputs are detached presentation
## values; nothing here writes the simulation, the scene, or any other piece.

const RevealShader := preload("res://src/presentation/occlusion/authored_reveal.gdshader")
const SortRelation := preload("res://src/presentation/occlusion_query.gd")
const POLICY := "paired_reveal"
const DETECTION_GROW := 8.0
const TRANSITION_SECONDS := 0.15
const ENTER_COVERAGE := 0.08
const EXIT_COVERAGE := 0.02

var _pieces: Dictionary = {}


func has_piece(stable_id: String) -> bool:
	return _pieces.has(stable_id)


## Registers one paired piece. The sprite must be a single unflipped,
## unregioned canvas; the variant must share its size; the detection
## rectangle must be finite, non-degenerate and already contain the occupied
## opaque-texel bounds grown by DETECTION_GROW — the same containment the
## author contract enforces, re-checked here so a malformed meta fails
## closed instead of guessing geometry.
func register_piece(stable_id: String, sprite: Sprite2D, revealed: Texture2D, detection_rect: Rect2) -> Dictionary:
	return _register_piece(stable_id, sprite, revealed, detection_rect,
		sprite.global_transform if sprite != null else Transform2D.IDENTITY)


func _register_piece(stable_id: String, sprite: Sprite2D, revealed: Texture2D, detection_rect: Rect2, canvas_to_world: Transform2D) -> Dictionary:
	if stable_id.is_empty() or sprite == null or sprite.texture == null or revealed == null:
		return {"ok": false, "error": "paired_reveal_missing_resource"}
	if _pieces.has(stable_id):
		return {"ok": false, "error": "paired_reveal_duplicate_binding:" + stable_id}
	if sprite.region_enabled or sprite.hframes != 1 or sprite.vframes != 1 or sprite.flip_h or sprite.flip_v:
		return {"ok": false, "error": "paired_reveal_requires_single_canvas:" + stable_id}
	if sprite.texture.get_size() != revealed.get_size():
		return {"ok": false, "error": "paired_reveal_canvas_mismatch:" + stable_id}
	## Registration and queries both use world coordinates. Only the image
	## containment check uses canvas coordinates. get_rect() includes offset
	## and centering. The caller supplies the transform into its query domain.
	if not canvas_to_world.x.is_equal_approx(Vector2.RIGHT) or not canvas_to_world.y.is_equal_approx(Vector2.DOWN):
		return {"ok": false, "error": "paired_reveal_requires_translation:" + stable_id}
	var canvas_origin := canvas_to_world * sprite.get_rect().position
	var canvas_rect := Rect2(detection_rect.position - canvas_origin, detection_rect.size)
	var rect_error := _validate_detection_rect(canvas_rect, sprite.texture)
	if not rect_error.is_empty():
		return {"ok": false, "error": rect_error + ":" + stable_id}
	var material := ShaderMaterial.new()
	material.shader = RevealShader
	material.set_shader_parameter("revealed_texture", revealed)
	material.set_shader_parameter("reveal_weight", 0.0)
	_pieces[stable_id] = {"sprite": weakref(sprite), "previous_material": sprite.material,
		"material": material, "rect": detection_rect, "open": false, "weight": 0.0,
		"coverage": 0.0, "actors": {}}
	sprite.material = material
	return {"ok": true, "error": ""}


## Native mounted opt-in: the baked sprite carries reveal_variant_path and a
## WORLD-space occlusion_rect meta. Missing or malformed metas fail closed.
func register_native_piece(stable_id: String, sprite: Sprite2D) -> Dictionary:
	var variant_path := String(sprite.get_meta("reveal_variant_path", ""))
	var rect: Variant = sprite.get_meta("occlusion_rect", null)
	var variant := _read_texture(variant_path)
	if variant == null:
		return {"ok": false, "error": "paired_reveal_asset_missing:" + stable_id}
	if not rect is Rect2:
		return {"ok": false, "error": "paired_reveal_missing_rect:" + stable_id}
	## Native children retain authored world positions beneath SortRoot.
	## Ancestors translate the entire world for the camera; their display
	## transform must not enter the world-space detection query.
	return _register_piece(stable_id, sprite, variant, rect, sprite.transform)


static func _read_texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	if FileAccess.file_exists(path):
		var image := Image.new()
		if image.load(path) == OK:
			return ImageTexture.create_from_image(image)
	return null


## entries carry the detached plan rows (stable_id, baseline_y, rank,
## art_box); subjects carry stable_id, baseline_y, rank and a world-space
## readability_box — the same protected-actor contract every reveal
## controller consumes. A piece opens only while it sorts in front of a
## protected actor and its detection rect covers enough of that actor's box.
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
		var next := advance_state(state.rect, by_id.get(stable_id, {}), subjects, state, delta)
		for key: String in next:
			state[key] = next[key]
		(state.material as ShaderMaterial).set_shader_parameter("reveal_weight", next.weight)


## Shared state transition for Sprite2D mounts and immediate-mode combat
## draws. Call once per committed presentation frame, never per draw. The
## coverage is the fraction of one readability box the detection rect
## covers — a deterministic pure function of the rect and the boxes.
static func advance_state(rect: Rect2, part: Dictionary, subjects: Array, previous: Dictionary, delta: float) -> Dictionary:
	var maximum := 0.0
	var contributors := {}
	if not part.is_empty():
		for subject: Dictionary in subjects:
			if not SortRelation.is_front(part, subject):
				continue
			var coverage := coverage_of(rect, subject.readability_box)
			if coverage > 0.0:
				contributors[String(subject.stable_id)] = coverage
				maximum = maxf(maximum, coverage)
	var opened := maximum >= (EXIT_COVERAGE if bool(previous.get("open", false)) else ENTER_COVERAGE)
	var weight := move_toward(float(previous.get("weight", 0.0)), 1.0 if opened else 0.0,
		maxf(delta, 0.0) / TRANSITION_SECONDS)
	return {"open": opened, "weight": weight, "coverage": maximum, "actors": contributors}


## Fraction of the subject box covered by the detection rect — same
## "share of the readability box" convention PrimitiveFadeController uses,
## so a graze and a real cover rank identically across both policies.
static func coverage_of(rect: Rect2, box: Rect2) -> float:
	if not box.has_area() or not rect.intersects(box):
		return 0.0
	return clampf(rect.intersection(box).get_area() / box.get_area(), 0.0, 1.0)


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


static func _validate_detection_rect(rect: Rect2, opaque_texture: Texture2D) -> String:
	if not rect.position.is_finite() or not rect.size.is_finite() or rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return "paired_reveal_invalid_rect"
	var image := opaque_texture.get_image() if opaque_texture != null else null
	return detection_rect_error(rect, image)


## Fail-closed and detach paths: every registered piece returns to its
## opaque state; registrations survive a reset (the plan may return).
func reset() -> void:
	for state: Dictionary in _pieces.values():
		state["open"] = false
		state["weight"] = 0.0
		state["coverage"] = 0.0
		state["actors"] = {}
		(state.material as ShaderMaterial).set_shader_parameter("reveal_weight", 0.0)


func clear() -> void:
	for state: Dictionary in _pieces.values():
		var sprite: Variant = (state.sprite as WeakRef).get_ref()
		if sprite != null and sprite.material == state.material:
			sprite.material = state.previous_material
	_pieces.clear()


## Honest per-piece audit: the live eased weight (not a plan intention), the
## coverage holding it open, the protected actor ids contributing, and the
## exact world detection rect. Never aliased as mask or cutout evidence.
func report() -> Dictionary:
	var result := {}
	for stable_id: String in _pieces.keys():
		var state: Dictionary = _pieces[stable_id]
		var rect: Rect2 = state.rect
		result[stable_id] = {
			"policy": POLICY,
			"open": bool(state["open"]),
			"weight": float(state["weight"]),
			"coverage": float(state["coverage"]),
			"actors": (state["actors"] as Dictionary).duplicate(true),
			"occlusion_rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y],
			"transition_seconds": TRANSITION_SECONDS,
		}
	return result
