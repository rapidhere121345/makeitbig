class_name SilhouetteRevealController
extends RefCounted

## Town-owned foreground reveal state for non-authored native front pieces.
## Where the legacy occluder window opened a broad circular hole at a covered
## actor's feet (retaining half the foreground at the 0.4 window tier, and
## exposing the legacy transparent ground whenever the anchor went stale), this
## controller gates and eases a reveal that clears the piece exactly over the
## actor's actual opaque silhouette. All inputs are detached presentation
## values read from live sprites; nothing here writes the simulation, the
## scene, or any piece's modulate.
##
## The transition is deliberately independent of the legacy window tiers: the
## reveal weight eases between 0 and 1 on its own clock regardless of where the
## occluder window alpha settles inside the 0.4..1 controller range.

const RevealShader := preload("res://src/presentation/occlusion/silhouette_reveal.gdshader")

## Foreground retained over the silhouette at full reveal. 0.0 keeps the
## actor's own frame colors exactly; anything outside the silhouette stays
## authored, so no veil is needed to mark the occlusion.
const CLEAR_ALPHA := 0.0
const TRANSITION_SECONDS := 0.15
## Hysteresis over the source-alpha refined coverage: the fraction of the
## actor's opaque silhouette texels that sit under the piece's own opaque
## texels. A whole-texture AABB overlap alone (for example the hero under the
## transparent tail of the Loadout PNG) must not open anything.
const ENTER_COVERAGE := 0.02
const EXIT_COVERAGE := 0.005
const OPAQUE_TEXEL_ALPHA := 0.5
const MAX_ACTORS := 8

var _states: Dictionary = {}
var _image_cache: Dictionary = {}


## Feeds one piece's per-actor refined coverage for this presentation frame and
## advances that piece's reveal transition. Actors with zero coverage keep
## their exact silhouette unavailable by design: a stale silhouette following
## an actor that walked out would expose the transparent legacy ground, so
## slots are only ever built from the current frame's real overlap.
func update(occluder_id: String, coverages: Dictionary, delta: float) -> Dictionary:
	var maximum := 0.0
	for actor_id: String in coverages.keys():
		maximum = maxf(maximum, float(coverages[actor_id]))
	var state: Dictionary = _states.get_or_add(occluder_id, {"open": false, "weight": 0.0, "coverage": 0.0, "actors": {}})
	state["open"] = (maximum >= EXIT_COVERAGE) if bool(state["open"]) else (maximum >= ENTER_COVERAGE)
	state["coverage"] = maximum
	state["actors"] = coverages.duplicate(true)
	state["weight"] = move_toward(float(state["weight"]), 1.0 if bool(state["open"]) else 0.0,
		maxf(delta, 0.0) / TRANSITION_SECONDS)
	return state.duplicate(true)


## Drops state for pieces the presenter no longer tracks, so a room restart
## cannot keep a closed reveal alive on a retired piece id.
func drop_except(tracked_ids: Array) -> void:
	for occluder_id: String in _states.keys():
		if not tracked_ids.has(occluder_id):
			_states.erase(occluder_id)


func reset() -> void:
	for state: Dictionary in _states.values():
		state["open"] = false
		state["weight"] = 0.0
		state["coverage"] = 0.0
		state["actors"] = {}


func clear() -> void:
	_states.clear()


func report() -> Dictionary:
	var result := {}
	for occluder_id: String in _states.keys():
		var state: Dictionary = _states[occluder_id]
		result[occluder_id] = {"open": state["open"], "weight": state["weight"], "coverage": state["coverage"]}
	return result


## The axis-aligned cell a Sprite2D really draws, in its own viewport's pixel
## space (the same space canvas FRAGCOORD reports). This is the live frame's
## placement — texture region, offset, centering, flip and the whole parent
## chain including the camera offset — never a collision box. The transform is
## CANVAS-INCLUSIVE (get_global_transform_with_canvas), so a viewport canvas
## translation is counted exactly once; the town camera is a node translation
## on WorldPresenter, which the global chain already carries. Bounded to the
## untransformed case: BOTH basis vectors of the composed transform must be
## the identity basis (any rotation, scale or skew — including a scaled or
## skewed canvas — yields no cell rather than a guess), as must a multi-frame
## sprite.
static func viewport_cell_rect(sprite: Sprite2D) -> Rect2:
	if sprite == null or sprite.texture == null or not sprite.is_visible_in_tree():
		return Rect2()
	if sprite.hframes != 1 or sprite.vframes != 1:
		return Rect2()
	var size: Vector2 = sprite.region_rect.size if sprite.region_enabled else sprite.texture.get_size()
	if size.x < 1.0 or size.y < 1.0:
		return Rect2()
	var transform := sprite.get_global_transform_with_canvas()
	if not transform.origin.is_finite() or not transform.x.is_equal_approx(Vector2.RIGHT) or not transform.y.is_equal_approx(Vector2.DOWN):
		return Rect2()
	var origin: Vector2 = sprite.offset - size * 0.5 if sprite.centered else sprite.offset
	return Rect2(transform * origin, size)


## The atlas region the sprite samples for its cell.
static func cell_region(sprite: Sprite2D) -> Rect2:
	if sprite == null or sprite.texture == null:
		return Rect2()
	if sprite.region_enabled:
		return sprite.region_rect
	return Rect2(Vector2.ZERO, sprite.texture.get_size())


## Source-alpha refined coverage: how much of the actor's drawn opaque
## silhouette sits under the piece's own opaque texels, measured over VIEWPORT
## PIXEL CENTERS — the exact points the shader shades — through the same
## floor-then-mirror integer texel convention the shader uses. A fractional
## cell origin or a flip can therefore never desynchronize the CPU refinement
## from the GPU clear. Deterministic pure function of the two sprites' live
## draw state; both cells live in the same viewport pixel space, so the camera
## offset cancels out.
func silhouette_coverage(actor: Sprite2D, piece: Sprite2D) -> float:
	var actor_cell := viewport_cell_rect(actor)
	var piece_cell := viewport_cell_rect(piece)
	if not actor_cell.has_area() or not piece_cell.has_area() or not actor_cell.intersects(piece_cell):
		return 0.0
	var actor_region := cell_region(actor)
	var piece_region := cell_region(piece)
	if actor_region.size.x < 1.0 or actor_region.size.y < 1.0 or piece_region.size.x < 1.0 or piece_region.size.y < 1.0:
		return 0.0
	var actor_image := _image_of(actor.texture)
	var piece_image := _image_of(piece.texture)
	if actor_image == null or piece_image == null:
		return 0.0
	var actor_bounds := Rect2i(Vector2i.ZERO, actor_image.get_size())
	var piece_bounds := Rect2i(Vector2i.ZERO, piece_image.get_size())
	var opaque := 0
	var hits := 0
	for py in range(int(floor(actor_cell.position.y)), int(ceil(actor_cell.end.y))):
		for px in range(int(floor(actor_cell.position.x)), int(ceil(actor_cell.end.x))):
			var center := Vector2(float(px) + 0.5, float(py) + 0.5)
			if not actor_cell.has_point(center):
				continue
			var actor_texel := texel_at(actor_cell, actor_region, actor, center)
			if not actor_bounds.has_point(actor_texel) or actor_image.get_pixelv(actor_texel).a < OPAQUE_TEXEL_ALPHA:
				continue
			opaque += 1
			if not piece_cell.has_point(center):
				continue
			var piece_texel := texel_at(piece_cell, piece_region, piece, center)
			if piece_bounds.has_point(piece_texel) and piece_image.get_pixelv(piece_texel).a >= OPAQUE_TEXEL_ALPHA:
				hits += 1
	return float(hits) / float(opaque) if opaque > 0 else 0.0


## The atlas texel one viewport pixel center samples: floor the center into
## the cell as an integer pixel index, mirror that integer for flips, then
## step into the atlas region. Mirroring the float center instead (or adding
## a half before flooring) lands a texel off whenever an origin is fractional
## or an axis is flipped; the shader's index convention is identical.
static func texel_at(cell: Rect2, region: Rect2, sprite: Sprite2D, center: Vector2) -> Vector2i:
	var index := Vector2i(
		int(floor(center.x - cell.position.x)),
		int(floor(center.y - cell.position.y)))
	if sprite.flip_h:
		index.x = int(cell.size.x) - 1 - index.x
	if sprite.flip_v:
		index.y = int(cell.size.y) - 1 - index.y
	return Vector2i(int(region.position.x) + index.x, int(region.position.y) + index.y)


## Cached decoded image per texture. Actor frames and native piece art are
## static imports, so each texture decodes once per presenter lifetime.
func _image_of(texture: Texture2D) -> Image:
	if texture == null:
		return null
	var key := texture.get_instance_id()
	if _image_cache.has(key):
		return _image_cache[key]
	var image := texture.get_image()
	if image == null or image.is_empty():
		return null
	if image.is_compressed() and image.decompress() != OK:
		return null
	_image_cache[key] = image
	return image
