extends RefCounted
## R13 snowy-outpost production skin. New ground, ruins, beacon and colossus
## textures keep the original scene/legacy cells, layout and module anchors.
##
## The world fills the whole window: the camera shows exactly the approved native
## 640x360 framing at an integer 2x, follows the hero and keeps world headroom
## above it so a colossus is never cut by the frame or the HUD.
##
## This file is presentation only. It never writes gameplay state and never
## derives damage, collision, AI or drop behaviour. The single size conversion in
## this package is the invertible transform built in begin_frame():
##
##   world  = anchor + (gameplay - arena.position) * GAMEPLAY_TO_WORLD
##   screen = clip.position + (world - camera_origin) * DISPLAY_SCALE
##
## so the playfield keeps its full geometry (uniform scale, no per-axis squeeze)
## while the sprites are drawn at the fixed native 2x.

const Readability = preload("res://src/presentation/actor_readability.gd")
const PaletteScript = preload("res://src/presentation/combat_palette.gd")
const AtmosphereScript = preload("res://src/presentation/scene_atmosphere.gd")
const GroundingScript = preload("res://src/presentation/grounding_effects.gd")
const RoomCatalogScript = preload("res://src/runtime/world/room_catalog.gd")
const SortRelation = preload("res://src/presentation/occlusion_query.gd")
const JsonIO := preload("res://src/core/json_io.gd")
const TextureLoader := preload("res://src/presentation/art/texture_loader.gd")
## Collaborators in src/presentation/arena_world/. The view keeps the frame state
## (camera, hero cell, sprite and texture tables) and passes itself to the ones
## that need it, so nothing holds a reference back to the view. The parameter
## stays untyped to avoid a preload cycle.
const AlphaOcclusionScript := preload("res://src/presentation/arena_world/alpha_occlusion.gd")
const AssetLoaderScript := preload("res://src/presentation/arena_world/asset_loader.gd")
const BossPartsScript := preload("res://src/presentation/arena_world/boss_parts.gd")
const CutawayScript := preload("res://src/presentation/arena_world/cutaway.gd")
const GeneratedWorldScript := preload("res://src/presentation/arena_world/generated_world.gd")
const StructureFadesScript := preload("res://src/presentation/arena_world/structure_fades.gd")
## Constants the owners of these tables publish; re-exported so callers keep
## reaching them through the view.
const GENERATED_WORLD_PATH := GeneratedWorldScript.GENERATED_WORLD_PATH
const ATMOSPHERE_PRESET := "arena"

const SCENE_ATLAS_PATH: String = AssetLoaderScript.SCENE_ATLAS_PATH
const SCENE_LAYOUT_PATH: String = AssetLoaderScript.SCENE_LAYOUT_PATH
const LEGACY_ATLAS_PATH: String = AssetLoaderScript.LEGACY_ATLAS_PATH
const APPROVED_GROUND_KEY: String = AssetLoaderScript.APPROVED_GROUND_KEY
const LEGACY_SPRITE_IDS: Array[String] = AssetLoaderScript.LEGACY_SPRITE_IDS
const CELL_CONTRACTS := AssetLoaderScript.CELL_CONTRACTS
const DISPLAY_SCALE: float = 2.0
const GAMEPLAY_TO_WORLD: float = 0.72
const WORLD_SIZE := Vector2(1024.0, 640.0)
## The mapped playfield is centred on this world point, so the authored ruins and
## tower end up along the walkable edges instead of on top of the fight.
const WORLD_FOCUS := Vector2(512.0, 360.0)
## Extra world headroom kept above the hero (native units) so a colossus head and
## the boss target shape stay clear of the frame and the top HUD strip.
const CAMERA_UP_OFFSET: float = 96.0
const FORE_FADE: float = BossPartsScript.FORE_FADE
const CUTAWAY_TOTAL_OPACITY: float = CutawayScript.CUTAWAY_TOTAL_OPACITY
const CUTAWAY_WINDOW_PAD: float = CutawayScript.CUTAWAY_WINDOW_PAD
const CUTAWAY_WINDOW_INDEX: int = CutawayScript.CUTAWAY_WINDOW_INDEX
const ALPHA_VISIBLE_BOUNDS_PADDING: float = AlphaOcclusionScript.ALPHA_VISIBLE_BOUNDS_PADDING
const BOSS_CORE_OFFSET := BossPartsScript.BOSS_CORE_OFFSET
const BOSS_HAND_LEFT_OFFSET := BossPartsScript.BOSS_HAND_LEFT_OFFSET
const BOSS_HAND_RIGHT_OFFSET := BossPartsScript.BOSS_HAND_RIGHT_OFFSET
const TOWER_UPPER_FADE: float = 0.52

var pending_reason: String = ""

var _sprites: Dictionary = {}
var _textures: Dictionary = {}
var _structures: Array[Dictionary] = []
var _tower_feet := Vector2.ZERO
var _clip := Rect2()
var _arena := Rect2()
var _anchor := Vector2.ZERO
var _origin := Vector2.ZERO
var _hero_world := Vector2.ZERO
## The default envelope covers the approved fallback idle cell.  A resolved
## action frame may have a draw offset, so ArenaActorPresenter replaces this
## with the exact destination rectangle before any foreground plan is built.
var _hero_occlusion_box := Rect2()
## The colossus is drawn by this file but its live position only exists at draw
## time, so the report can only speak about the colossus of the frame that was
## really drawn.
var _ready := false
var _atmosphere_drawn := false
var _grounding_counts := {"contact": 0, "base": 0, "base_ids": [], "lit": 0}
var _grounding_lights_cache: Array = []
var _room_catalog: RefCounted
var _layout_id := "rectangle_arena"
var _room_structure_overrides: Dictionary = {}
## Fixture seams: production always points at GENERATED_WORLD_PATH; tests may
## substitute a synthetic pack to exercise the whole-object branch.
var generated_world_path := GENERATED_WORLD_PATH
var _alpha := AlphaOcclusionScript.new()
var _loader := AssetLoaderScript.new()
var _generated := GeneratedWorldScript.new()
var _fades := StructureFadesScript.new()
var _cutaway := CutawayScript.new()
var _boss := BossPartsScript.new()


func _init() -> void:
	_room_catalog = RoomCatalogScript.new()


func is_ready() -> bool:
	return _ready


func world_size() -> Vector2:
	return WORLD_SIZE


func native_scale() -> float:
	return DISPLAY_SCALE


func gameplay_scale() -> float:
	return GAMEPLAY_TO_WORLD


func camera_up_offset() -> float:
	return CAMERA_UP_OFFSET


func clip_rect() -> Rect2:
	return _clip


func visible_world_size() -> Vector2:
	return _clip.size / DISPLAY_SCALE


func camera_origin() -> Vector2:
	return _origin


func hero_world() -> Vector2:
	return _hero_world


func structure_placements() -> Array[Dictionary]:
	var result: Array[Dictionary] = _structures.duplicate(true)
	var occurrences := {}
	var overrides: Dictionary = _room_structure_overrides.get(_layout_id, {})
	for placement: Dictionary in result:
		var id := String(placement.id)
		var ordinal := int(occurrences.get(id, 0))
		occurrences[id] = ordinal + 1
		var key := id + "#" + str(ordinal)
		if overrides.has(key):
			placement.feet = (overrides[key] as Array).duplicate()
	return result


func structure_draw_list() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for placement in structure_placements():
		result.append({
			"sprite_id": String(placement.get("id", "")),
			"feet_world": gameplay_to_world(_point(placement.get("feet", []))),
		})
	return result


func tower_feet() -> Vector2:
	var overrides: Dictionary = _room_structure_overrides.get(_layout_id, {})
	return _point(overrides.tower) if overrides.has("tower") else _tower_feet


func tower_feet_world() -> Vector2:
	return gameplay_to_world(tower_feet())


var _dressing = preload("res://src/presentation/world_dressing.gd").new()
var _room_scene = preload("res://src/presentation/combat_room_scene.gd").new()
## Fixture seam for the per-room floor pack; production uses the module default.
var room_floor_pack_path := ""


func dressing_report() -> Dictionary:
	return _dressing.report("arena")


func load_assets() -> bool:
	reset_structure_fades()
	pending_reason = ""
	_sprites.clear()
	_textures.clear()
	_alpha.clear()
	_structures.clear()
	_room_structure_overrides.clear()
	_ready = false
	var scene_atlas := _read_json(SCENE_ATLAS_PATH)
	var legacy_atlas := _read_json(LEGACY_ATLAS_PATH)
	var layout := _read_json(SCENE_LAYOUT_PATH)
	if scene_atlas.is_empty() or legacy_atlas.is_empty() or layout.is_empty():
		return false
	if not _loader.select_union(self, scene_atlas, legacy_atlas):
		return false
	if not _loader.load_textures(self, scene_atlas, legacy_atlas):
		return false
	if not _loader.validate_cells(self):
		return false
	if not _loader.read_layout(self, layout):
		return false
	if not _generated.load_pack(self):
		return false
	## The generated world pack always claims authority, so the floor pack is required.
	if not room_floor_pack_path.is_empty():
		_room_scene.pack_path = room_floor_pack_path
	if not _room_scene.load_assets(true, WORLD_FOCUS, GAMEPLAY_TO_WORLD):
		pending_reason = _room_scene.pending_reason
		return false
	if not _dressing.load_assets():
		pending_reason = _dressing.pending_reason
		return false
	_ready = true
	return true


func begin_frame(clip_rect: Rect2, focus_gameplay: Vector2, arena_rect: Rect2) -> void:
	_clip = clip_rect
	_arena = arena_rect
	_grounding_counts = {"contact": 0, "base": 0, "base_ids": [], "lit": 0}
	_grounding_lights_cache = []
	_anchor = WORLD_FOCUS - arena_rect.size * GAMEPLAY_TO_WORLD * 0.5
	_hero_world = gameplay_to_world(focus_gameplay)
	_hero_occlusion_box = _default_hero_cell(_hero_world)
	_origin = camera_origin_for(_hero_world)
	_atmosphere_drawn = false
	_cutaway.begin_frame()


## Clamped follow camera: the hero keeps the 640x360 framing with world headroom
## above it, and the window never leaves the authored world.
func camera_origin_for(hero_world_point: Vector2) -> Vector2:
	var visible := visible_world_size()
	var wanted := hero_world_point - visible * 0.5 + Vector2(0.0, -CAMERA_UP_OFFSET)
	var limit := Vector2(maxf(0.0, WORLD_SIZE.x - visible.x), maxf(0.0, WORLD_SIZE.y - visible.y))
	return Vector2(roundf(clampf(wanted.x, 0.0, limit.x)), roundf(clampf(wanted.y, 0.0, limit.y)))


func gameplay_to_world(gameplay_point: Vector2) -> Vector2:
	return _anchor + (gameplay_point - _arena.position) * GAMEPLAY_TO_WORLD


func world_to_gameplay(world_point: Vector2) -> Vector2:
	return _arena.position + (world_point - _anchor) / GAMEPLAY_TO_WORLD


func to_screen(world_point: Vector2) -> Vector2:
	return _clip.position + (world_point - _origin) * DISPLAY_SCALE


func to_world(screen_point: Vector2) -> Vector2:
	return _origin + (screen_point - _clip.position) / DISPLAY_SCALE


func gameplay_to_screen(gameplay_point: Vector2) -> Vector2:
	return to_screen(gameplay_to_world(gameplay_point))


## Viewport/screen coordinates -> authoritative gameplay coordinates. This is
## the exact inverse of gameplay_to_screen() for the current begin_frame(), so
## pointer targeting uses the same camera clamp and integer display scale as the
## pixels the player sees.
func screen_to_gameplay(screen_point: Vector2) -> Vector2:
	return world_to_gameplay(to_world(screen_point))


## Native art (world) coordinates -> screen. Draw world art under this matrix.
func world_transform() -> Transform2D:
	return Transform2D(0.0, Vector2(DISPLAY_SCALE, DISPLAY_SCALE), 0.0, _clip.position - _origin * DISPLAY_SCALE)


## Gameplay (authoritative) coordinates -> screen. Draw telegraphs and status
## overlays under this matrix so nothing has to convert a single point by hand.
func gameplay_transform() -> Transform2D:
	var scale := DISPLAY_SCALE * GAMEPLAY_TO_WORLD
	return Transform2D(0.0, Vector2(scale, scale), 0.0, _clip.position + (_anchor - _arena.position * GAMEPLAY_TO_WORLD - _origin) * DISPLAY_SCALE)


## Draws one authoritative Piercing Arrow snapshot under gameplay_transform().
## The head is the projectile position; previous_position and origin supply only
## the bounded wake, so render cadence cannot move or lengthen the flight.
static func draw_piercing_arrow(
	canvas: CanvasItem,
	previous_position: Vector2,
	position: Vector2,
	direction: Vector2,
	origin: Vector2 = Vector2.INF
) -> void:
	if canvas == null or direction.length_squared() <= 0.000001:
		return
	var geometry := piercing_arrow_geometry(previous_position, position, direction, origin)
	var aim := geometry["aim"] as Vector2
	var side := geometry["side"] as Vector2
	var trail_start := geometry["trail_start"] as Vector2
	var trail_mid := geometry["trail_mid"] as Vector2
	var shaft_tail := geometry["shaft_tail"] as Vector2
	var shaft_head := geometry["shaft_head"] as Vector2
	var wake_length := float(geometry.get("wake_length", 0.0))
	var glow_start := position - aim * minf(20.0, wake_length + 4.0)
	## The broad, low-alpha wake is deliberately separate from the arrow shaft:
	## it keeps a fast arrow readable against both snow and slate without changing
	## its authoritative position or swept contact.
	canvas.draw_line(glow_start, position, Color(PaletteScript.COLD, 0.13), 4.0, false)
	canvas.draw_line(trail_start, trail_mid, Color(PaletteScript.COLD, 0.28), 1.8, false)
	canvas.draw_line(trail_mid, position, Color(PaletteScript.COLD, 0.55), 2.2, false)
	canvas.draw_line(shaft_tail, shaft_head, Color(PaletteScript.INK, 0.88), 3.8, false)
	canvas.draw_line(shaft_tail, shaft_head, PaletteScript.BONE, 1.8, false)
	canvas.draw_line(shaft_tail - side * 2.1, shaft_tail + aim * 2.4, PaletteScript.COPPER, 1.0, false)
	canvas.draw_line(shaft_tail + side * 2.1, shaft_tail + aim * 2.4, PaletteScript.COPPER, 1.0, false)
	canvas.draw_colored_polygon(PackedVector2Array([
		position + aim * 6.4,
		position - aim * 2.2 + side * 3.4,
		position - aim * 2.2 - side * 3.4,
	]), PaletteScript.COPPER)
	canvas.draw_rect(Rect2(position.round() - Vector2.ONE, Vector2(2, 2)), PaletteScript.BONE)
	for index in 3:
		var spark := (trail_start.lerp(position, float(index + 1) / 4.0) + side * (-2.0 if index % 2 == 0 else 2.0)).round()
		canvas.draw_rect(Rect2(spark, Vector2.ONE), Color(PaletteScript.COLD, 0.5))


## Pure geometry for the in-flight arrow. The wake never runs behind its frozen
## release origin and is capped at a short tail even after a long render frame.
static func piercing_arrow_geometry(
	previous_position: Vector2,
	position: Vector2,
	direction: Vector2,
	origin: Vector2 = Vector2.INF
) -> Dictionary:
	var aim := direction.normalized()
	var side := aim.rotated(PI * 0.5)
	var travel_from_origin := position.distance_to(origin) if origin.is_finite() else position.distance_to(previous_position)
	var previous_gap := position.distance_to(previous_position)
	var wake_length := minf(18.0, minf(previous_gap, maxf(0.0, travel_from_origin)))
	var trail_start := position - aim * wake_length
	var trail_mid := position - aim * wake_length * 0.5
	return {
		"aim": aim,
		"side": side,
		"trail_start": trail_start,
		"trail_mid": trail_mid,
		"shaft_tail": position - aim * 11.0,
		"shaft_head": position - aim * 1.8,
		"wake_length": wake_length,
	}


func visible_world_region() -> Rect2:
	return Rect2(_origin, visible_world_size())


func draw_ground(canvas: CanvasItem) -> void:
	## A loaded room floor pack owns every layout's plate; the generated arena
	## ground is the fallback when no room grounds are loaded.
	var texture: Texture2D = _room_scene.ground_texture(_layout_id) if _room_scene.has_grounds() else _textures.get(APPROVED_GROUND_KEY)
	if texture == null:
		return
	var region := visible_world_region().intersection(Rect2(Vector2.ZERO, WORLD_SIZE))
	if region.size.x <= 0.0 or region.size.y <= 0.0:
		return
	canvas.draw_texture_rect_region(texture, Rect2(region.position.round(), region.size), region)
	AtmosphereScript.draw_ground(
		canvas,
		region,
		ATMOSPHERE_PRESET,
		atmosphere_warm_lights(),
		true
	)
	_atmosphere_drawn = true


func room_concept_report(layout_id: String) -> Dictionary:
	var concept: Dictionary = _room_catalog.presentation(layout_id) if _room_catalog != null else {}
	return {
		"layout_id": layout_id,
		"title": String(concept.get("display_name", "Arena")),
		"landmark": String(concept.get("landmark", "Boundary Marker")),
		"concept": String(concept.get("concept", "")),
		"entry_hint": String(concept.get("entry_hint", "")),
		"exit_hint": String(concept.get("exit_hint", "")),
		"presentation_only": true,
	}


## Each published layout draws its own place: code-native edge trim from the
## authoritative boundary, a ground-level entry threshold at the spawn socket
## side and a sealed exit ward (CombatRoomScene). It is drawn under actors and
## telegraphs and reads only the layout id, the running simulation tick for a
## bounded pulse, and the read-only cleared flag for the ward state.
func draw_room_concept(canvas: CanvasItem, layout_id: String, phase_ticks: int = 0, _walkable_geometry: Dictionary = {}, room_cleared: bool = false) -> void:
	if canvas == null:
		return
	var phase := fmod(float(phase_ticks), 60.0) / 60.0
	_room_scene.draw_room(canvas, layout_id, Callable(self, "gameplay_to_world"), GAMEPLAY_TO_WORLD, phase, room_cleared)


func room_scene_report(layout_id: String, room_cleared: bool = false) -> Dictionary:
	return _room_scene.room_report(layout_id, room_cleared)


func draw_decals(canvas: CanvasItem) -> void:
	if _room_scene.has_room(_layout_id):
		_room_scene.draw_dressing(canvas, _layout_id, visible_world_region())
	else:
		_dressing.draw_floor(canvas, "arena", visible_world_region())


## Cold edge atmosphere stays in the same world matrix as the arena art, after
## the decals and before gameplay ground effects. It is clipped to the visible
## world region, so it cannot bleed into HUD or UI layers.
func draw_atmosphere(canvas: CanvasItem) -> void:
	var region := visible_world_region().intersection(Rect2(Vector2.ZERO, WORLD_SIZE))
	if region.size.x <= 0.0 or region.size.y <= 0.0:
		return
	AtmosphereScript.draw_fore(canvas, region, ATMOSPHERE_PRESET)


## Cached pixel-ellipse contact shadow at the real feet, drawn before every actor
## so it reads as grounding rather than as lighting. `alpha` is the strength.
func draw_shadow(canvas: CanvasItem, feet_world: Vector2, width_world: float, depth_world: float, alpha: float) -> void:
	if alpha <= 0.0 or not visible_world_region().grow(width_world).has_point(feet_world):
		return
	_grounding_counts.contact += 1
	GroundingScript.draw_contact(canvas, feet_world, Vector2(width_world, depth_world), alpha)


## Room-local equipment is rendered as a small readable pickup marker. The item
## preview remains detached data; this pass never inspects or mutates inventory.
func draw_loot(canvas: CanvasItem, feet_world: Vector2, entity: Dictionary) -> void:
	if canvas == null or not feet_world.is_finite() or String(entity.get("state", "")) != "available":
		return
	var pulse := 1.0 + 0.12 * sin(float(entity.get("spawned_tick", 0)) * 0.25)
	var center := feet_world + Vector2(0.0, -10.0)
	var half := 6.0 * pulse
	var diamond := PackedVector2Array([
		center + Vector2(0.0, -half), center + Vector2(half, 0.0),
		center + Vector2(0.0, half), center + Vector2(-half, 0.0),
	])
	canvas.draw_colored_polygon(diamond, Color(PaletteScript.COLD, 0.86))
	canvas.draw_polyline(PackedVector2Array([
		center + Vector2(0.0, -half), center + Vector2(half, 0.0),
		center + Vector2(0.0, half), center + Vector2(-half, 0.0),
		center + Vector2(0.0, -half),
	]), PaletteScript.BONE, 1.0, false)


func draw_structure_shadows(canvas: CanvasItem) -> void:
	for placement in structure_placements():
		_draw_base_shadow(canvas, String(placement.get("id", "")), gameplay_to_world(_point(placement.get("feet", []))))
	_draw_base_shadow(canvas, "tower", tower_feet_world())


## Shadow from the generated structure's whole-object opaque contour at the
## geometry the draw path really uses; source art is untouched.
func _draw_base_shadow(canvas: CanvasItem, sprite_id: String, feet_world: Vector2) -> void:
	var bands := structure_geometry(sprite_id, feet_world)
	for index in range(bands.size() - 1, -1, -1):
		var band: Dictionary = bands[index]
		var texture: Texture2D = _textures.get(String(band.texture))
		if texture == null:
			break
		_grounding_counts.base += 1
		_grounding_counts.base_ids.append(sprite_id)
		GroundingScript.draw_base(canvas, texture, band.source, feet_world - (band.dest as Rect2).position, feet_world)
		return
	var size := _cell_size(sprite(sprite_id))
	_grounding_counts.contact += 1
	GroundingScript.draw_contact(canvas, feet_world, Vector2(maxf(size.x * 0.5, 40.0), maxf(size.y * 0.14, 12.0)), 0.30)


## The existing fixed warm sources (same positions, radii and strengths as the
## atmosphere pools), as light rows for GroundingScript.illumination. Cached per frame.
func grounding_lights() -> Array:
	if _grounding_lights_cache.is_empty():
		_grounding_lights_cache = [
			{"id": "tower", "position": tower_feet_world(), "radius": 44.0, "color": GroundingScript.AMBER, "strength": 0.17},
			{"id": "ruin", "position": ruin_light_feet_world(), "radius": 30.0, "color": GroundingScript.AMBER, "strength": 0.14},
		]
	return _grounding_lights_cache


## RGB-only light response (alpha 1, boost bounded by the helper). Any caller-tinted
## modulate (hit flash, telegraph or core tints) is returned untouched, so those keep
## priority; alpha, cutaway and reveal semantics are never read or changed here.
func _lit(modulate: Color, feet_world: Vector2) -> Color:
	if modulate.r != 1.0 or modulate.g != 1.0 or modulate.b != 1.0:
		return modulate
	var light := illumination_at(feet_world)
	return Color(light.r, light.g, light.b, modulate.a)


## Public RGB light multiplier (alpha always 1) at a world feet point, for presenters
## that draw frames directly. Multiply it into a draw colour's RGB only; never its alpha.
func illumination_at(feet_world: Vector2) -> Color:
	var light := GroundingScript.illumination(feet_world, grounding_lights())
	if light.r != 1.0 or light.g != 1.0 or light.b != 1.0:
		_grounding_counts.lit += 1
	return light


## Presentation-only counters for the last frame, for capture reports.
func grounding_report() -> Dictionary:
	var report := _grounding_counts.duplicate(true)
	report["lights"] = grounding_lights().duplicate(true)
	report["presentation_only"] = true
	return report


## Two fixed sources: holy light on the tower and a low ember reflection by the
## eastern ruin. No live enemy or projectile position is consumed, so a light can
## never expose or mask a gameplay object.


func ruin_light_feet_world() -> Vector2:
	for placement: Dictionary in structure_placements():
		if String(placement.id) == "ruin.broken_wall":
			return gameplay_to_world(_point(placement.feet))
	return tower_feet_world()


func atmosphere_warm_lights() -> Array:
	return [
		AtmosphereScript.warm_light(tower_feet_world(), 44.0, 0.17),
		AtmosphereScript.warm_light(ruin_light_feet_world(), 30.0, 0.14),
	]


func atmosphere_report() -> Dictionary:
	var report := AtmosphereScript.atmosphere_report(ATMOSPHERE_PRESET, visible_world_region(), atmosphere_warm_lights())
	report["base_drawn_with_ground"] = _atmosphere_drawn
	report["world_lights_clipped"] = (
		Rect2(Vector2.ZERO, WORLD_SIZE).encloses(Rect2(tower_feet_world() - Vector2.ONE * 44.0, Vector2.ONE * 88.0))
		and Rect2(Vector2.ZERO, WORLD_SIZE).encloses(Rect2(ruin_light_feet_world() - Vector2.ONE * 30.0, Vector2.ONE * 60.0))
	)
	return report


func draw_sprite(canvas: CanvasItem, sprite_id: String, feet_world: Vector2, flip_x: bool = false, modulate: Color = Color.WHITE, cut: Rect2 = Rect2(), cut_alpha: float = 1.0) -> void:
	var metadata := sprite(sprite_id)
	if metadata.is_empty():
		return
	_draw_cell(canvas, metadata, feet_world, flip_x, modulate, cut, cut_alpha)


## ---------------------------------------------------------------- cutaway
## Planning, budget and report live in arena_world/cutaway.gd.


static func cutaway_window(cell: Rect2) -> Rect2:
	return CutawayScript.cutaway_window(cell)


static func cutaway_alpha(count: int) -> float:
	return CutawayScript.cutaway_alpha(count)


static func cutaway_pieces(quad: Rect2, core: Rect2) -> Array[Rect2]:
	return CutawayScript.cutaway_pieces(quad, core)


## The world rect a cell really draws into: exactly the destination _draw_cell()
## uses, including a keep_rows band, so a cutaway is measured on real art.
func sprite_art_box(sprite_id: String, feet_world: Vector2, flip_x: bool = false) -> Rect2:
	var metadata := sprite(sprite_id)
	if metadata.is_empty():
		return Rect2()
	var region := _region_of(metadata)
	if region.size.x <= 0.0 or region.size.y <= 0.0:
		return Rect2()
	var rect: Rect2 = metadata.get("rect", Rect2())
	var anchor: Vector2 = metadata.get("anchor", Vector2.ZERO)
	var destination := Rect2((feet_world - anchor + (region.position - rect.position)).round(), region.size)
	var visible := _alpha.visible_bounds(_textures.get(String(metadata.get("texture", ""))) as Texture2D, region)
	if flip_x:
		visible.position.x = region.size.x - (visible.position.x + visible.size.x)
	return Rect2(destination.position + visible.position, visible.size)


## Dynamic action frames use the same source-region cache as published arena
## sprites. This only describes the pixels that can occlude; the draw pass still
## submits the complete source_rect at the complete destination rectangle.
func frame_art_box(texture: Texture2D, source_rect: Rect2, feet_world: Vector2, anchor: Vector2, draw_offset: Vector2 = Vector2.ZERO, flip_x: bool = false) -> Rect2:
	if source_rect.size.x <= 0.0 or source_rect.size.y <= 0.0:
		return Rect2()
	var destination := Rect2((feet_world - anchor + draw_offset).round(), source_rect.size)
	if texture == null:
		return destination
	var visible := _alpha.visible_bounds(texture, source_rect)
	if flip_x:
		visible.position.x = source_rect.size.x - (visible.position.x + visible.size.x)
	return Rect2(destination.position + visible.position, visible.size)


## A detached description of the pixels a published sprite really contributes
## to the foreground pass.  Callers keep the authored destination rectangle for
## drawing and use this descriptor only for visibility intersection.
func sprite_occlusion_descriptor(sprite_id: String, feet_world: Vector2, flip_x: bool = false) -> Dictionary:
	var metadata := sprite(sprite_id)
	if metadata.is_empty():
		return {}
	var region := _region_of(metadata)
	var rect: Rect2 = metadata.get("rect", Rect2())
	var anchor: Vector2 = metadata.get("anchor", Vector2.ZERO)
	var destination := Rect2((feet_world - anchor + (region.position - rect.position)).round(), region.size)
	return _alpha.describe(_textures.get(String(metadata.get("texture", ""))) as Texture2D, region, destination, flip_x)


## Dynamic action frames use exactly the same descriptor contract as published
## sprites, including authored draw offsets and horizontal mirroring.
func frame_occlusion_descriptor(texture: Texture2D, source_rect: Rect2, feet_world: Vector2, anchor: Vector2, draw_offset: Vector2 = Vector2.ZERO, flip_x: bool = false) -> Dictionary:
	if source_rect.size.x <= 0.0 or source_rect.size.y <= 0.0:
		return {}
	var destination := Rect2((feet_world - anchor + draw_offset).round(), source_rect.size)
	return _alpha.describe(texture, source_rect, destination, flip_x)


## Public read-only query used by actor and structure passes (the mask cache is
## arena_world/alpha_occlusion.gd).
func occlusion_descriptor_intersects(descriptor: Dictionary, query: Rect2) -> bool:
	return _alpha.descriptor_intersects(descriptor, query)


func visibility_intersects(visibility: Variant, query: Rect2) -> bool:
	return _alpha.visibility_intersects(visibility, query)


## The actor presenter calls this after resolving the frame that will actually
## be drawn.  Keeping the box here makes static cutaway, actor prepass, Boss
## helpers and diagnostics consume the same integer destination rectangle.
func set_hero_occlusion_box(box: Rect2) -> bool:
	if not box.position.is_finite() or not box.size.is_finite() or box.size.x <= 0.0 or box.size.y <= 0.0:
		return false
	_hero_occlusion_box = box
	return true


func _hero_sort_entry(hero_world_point: Vector2) -> Dictionary:
	return SortRelation.entry(hero_world_point.y, 2, "ranger/body")


func _structure_stable_id(structure_index: int, sprite_id: String) -> String:
	return "structure/%d/%s" % [structure_index, sprite_id]


## Compatibility query for the actor cutaway budget. Structure transparency
## is reported separately by structure_fade_report().
func cutaway_front(hero_world_point: Vector2) -> Array[Dictionary]:
	return _cutaway.cutaway_front(hero_world_point)


func cutaway_for(art_box: Rect2, feet_world: Vector2, hero_world_point: Vector2, sort_rank: int = 1, stable_id: String = "actor", visibility: Variant = null) -> Dictionary:
	return _cutaway.cutaway_for(self, art_box, feet_world, hero_world_point, sort_rank, stable_id, visibility)


## The actor pass supplies every live front-facing actor cell before drawing.
## Normal enemies and Boss parts share one local opacity budget.
func prepare_actor_occlusion(cells: Array[Dictionary], hero_world_point: Vector2) -> void:
	_cutaway.prepare_actor_occlusion(self, cells, hero_world_point)


func _boss_cutaway(sprite_ids: Array, feet_list: Array, feet_world: Vector2, hero_world_point: Vector2, sort_feet_list: Array = []) -> Dictionary:
	return _cutaway.boss_cutaway(self, sprite_ids, feet_list, feet_world, hero_world_point, sort_feet_list)


## Read-only cutaway diagnostic for the external visibility harness.
func occlusion_report(hero_world_point: Vector2) -> Dictionary:
	return _cutaway.occlusion_report(self, hero_world_point)


## Static ruins in front of the hero fade out instead of hiding it, the same
## treatment the approved sample applies to the tower. Props behind the hero need
## no fade because the y-sort already draws them first.
func structure_fade(sprite_id: String, feet_world: Vector2, _hero_world_point: Vector2) -> float:
	return float(structure_fade_state(sprite_id, feet_world).get("alpha", 1.0))


func hero_cell_world(hero_world_point: Vector2) -> Rect2:
	# Actions can extend a bow/cape beyond the old 32px idle cell. The live frame
	# supplies the exact destination box; callers asking about another point get
	# the conservative fallback envelope used before a frame is resolved.
	if _hero_world.is_equal_approx(hero_world_point) and _hero_occlusion_box.size.x > 0.0 and _hero_occlusion_box.size.y > 0.0:
		return _hero_occlusion_box
	return _default_hero_cell(hero_world_point)


func _default_hero_cell(hero_world_point: Vector2) -> Rect2:
	return Rect2(hero_world_point - Vector2(24.0, 44.0), Vector2(48.0, 48.0))


## Exactly the destination rectangle _draw_cell() uses, in screen pixels, so a
## harness can compare real pixels against the real placement.
func sprite_screen_rect(sprite_id: String, feet_world: Vector2) -> Rect2:
	var metadata := sprite(sprite_id)
	if metadata.is_empty():
		return Rect2()
	var rect: Rect2 = metadata.get("rect", Rect2())
	var anchor: Vector2 = metadata.get("anchor", Vector2.ZERO)
	var region := rect
	if metadata.has("keep_rows"):
		var rows: Array = metadata["keep_rows"]
		region = Rect2(rect.position.x, rect.position.y + float(rows[0]), rect.size.x, float(rows[1]) - float(rows[0]))
	var destination := Rect2((feet_world - anchor + (region.position - rect.position)).round(), region.size)
	return Rect2(to_screen(destination.position), destination.size * DISPLAY_SCALE)


## Upper-band report. Solid-base clearance belongs to the authored movement
## contract and rendered acceptance, not this presentation-only overlap query.
func hero_cover_report(hero_world_point: Vector2) -> Dictionary:
	return _fades.hero_cover_report(self, hero_world_point)


func draw_structure(canvas: CanvasItem, sprite_id: String, feet_world: Vector2, _hero_world_point: Vector2) -> void:
	for band: Dictionary in structure_geometry(sprite_id, feet_world):
		_draw_cell_piece(canvas, _textures[band.texture], band.source, band.dest, band.dest, _lit(Color(1, 1, 1, band.alpha), feet_world))


func structure_draw_alpha(sprite_id: String, feet_world: Vector2, hero_world_point: Vector2) -> float:
	return structure_fade(sprite_id, feet_world, hero_world_point)


func draw_tower(canvas: CanvasItem, _hero_world_point: Vector2) -> void:
	for band: Dictionary in structure_geometry("tower", tower_feet_world()):
		_draw_cell_piece(canvas, _textures[band.texture], band.source, band.dest, band.dest, _lit(Color(1, 1, 1, band.alpha), tower_feet_world()))

## ------------------------------------------------------------------- boss
## Part layout, per-part cutaway and footprints live in arena_world/boss_parts.gd.


func boss_draw_parts(feet_world: Vector2, phase: int, left_hand_delta_gameplay: Vector2, right_hand_delta_gameplay: Vector2, pose_frame: Dictionary = {}) -> Array[Dictionary]:
	return _boss.boss_draw_parts(self, feet_world, phase, left_hand_delta_gameplay, right_hand_delta_gameplay, pose_frame)


func draw_boss_part(canvas: CanvasItem, part: Dictionary, hero_world_point: Vector2, sort_rank: int = 3, stable_id: String = "enemy/boss/part") -> void:
	_boss.draw_boss_part(self, canvas, part, hero_world_point, sort_rank, stable_id)


func boss_parts_world(feet_world: Vector2) -> Array[Rect2]:
	return _boss.boss_parts_world(self, feet_world)


func boss_fade_alpha(
	feet_world: Vector2,
	hero_world_point: Vector2,
	phase: int = 2,
	left_hand_delta_gameplay: Vector2 = Vector2.ZERO,
	right_hand_delta_gameplay: Vector2 = Vector2.ZERO,
	pose_frame: Dictionary = {}
) -> float:
	return _boss.boss_fade_alpha(self, feet_world, hero_world_point, phase, left_hand_delta_gameplay, right_hand_delta_gameplay, pose_frame)


func boss_body_rect_world(feet_world: Vector2) -> Rect2:
	return _boss.boss_body_rect_world(self, feet_world)


func boss_hand_rect_world(feet_world: Vector2, left: bool) -> Rect2:
	return _boss.boss_hand_rect_world(self, feet_world, left)


func sprite(sprite_id: String) -> Dictionary:
	return (_sprites.get(sprite_id, {}) as Dictionary).duplicate(true)


func _draw_cell(canvas: CanvasItem, metadata: Dictionary, feet_world: Vector2, flip_x: bool, modulate: Color, cut: Rect2 = Rect2(), cut_alpha: float = 1.0) -> void:
	var texture: Texture2D = _textures.get(String(metadata.get("texture", "")))
	if texture == null:
		return
	modulate = _lit(modulate, feet_world)
	var rect: Rect2 = metadata.get("rect", Rect2())
	var anchor: Vector2 = metadata.get("anchor", Vector2.ZERO)
	var region := _region_of(metadata)
	Readability.bind_region(canvas, texture, rect)
	var size := region.size
	var destination := Rect2((feet_world - anchor + (region.position - rect.position)).round(), size)
	var visible := destination.intersection(visible_world_region())
	if visible.size.x <= 0.0 or visible.size.y <= 0.0:
		return
	if flip_x:
		var center := destination.position + destination.size * 0.5
		var core := _cutaway_core(destination, cut, cut_alpha)
		var pieces: Array[Dictionary] = [{"dest": visible, "alpha": modulate.a}]
		if core.has_area():
			pieces = cut_pieces(destination, region, core, modulate.a, cut_alpha)
		# Compose with the active world transform; resetting to identity used to
		# put subsequent actors in raw screen coordinates when an enemy faced left.
		canvas.draw_set_transform_matrix(_canvas_world_transform(canvas) * Transform2D(0.0, Vector2(-1.0, 1.0), 0.0, center))
		for piece: Dictionary in pieces:
			var dest: Rect2 = piece["dest"]
			var mirrored_local := Rect2(Vector2(center.x - dest.end.x, dest.position.y - center.y), dest.size)
			var mirrored_source := Rect2(region.position + Vector2(destination.size.x - (dest.end.x - destination.position.x), dest.position.y - destination.position.y), dest.size)
			canvas.draw_texture_rect_region(texture, mirrored_local, mirrored_source, Color(modulate.r, modulate.g, modulate.b, float(piece["alpha"])))
		canvas.draw_set_transform_matrix(_canvas_world_transform(canvas))
		return
	if not flip_x:
		var core := _cutaway_core(destination, cut, cut_alpha)
		if core.size.x > 0.0 and core.size.y > 0.0:
			_draw_cut_cell(canvas, texture, region, destination, core, modulate, cut_alpha)
			return
	var source := Rect2(region.position + (visible.position - destination.position), visible.size)
	canvas.draw_texture_rect_region(texture, visible, source, modulate)


static func _region_of(metadata: Dictionary) -> Rect2:
	## The source band a cell keeps: the published rect, or the keep_rows slice the
	## tower publishes so its upper body and its foot stay separate cells.
	var rect: Rect2 = metadata.get("rect", Rect2())
	if not metadata.has("keep_rows"):
		return rect
	var rows: Array = metadata["keep_rows"]
	return Rect2(rect.position.x, rect.position.y + float(rows[0]), rect.size.x, float(rows[1]) - float(rows[0]))


func _prime_alpha_visible_bounds() -> void:
	for sprite_id: String in _sprites.keys():
		var metadata: Dictionary = _sprites[sprite_id]
		_alpha.visible_bounds(_textures.get(String(metadata.get("texture", ""))) as Texture2D, _region_of(metadata))


func _cutaway_core(destination: Rect2, cut: Rect2, cut_alpha: float) -> Rect2:
	## The window in destination-local units, on the integer grid so every piece
	## reads whole source pixels. An empty result means the cell is drawn as
	## authored, which is the whole-frame state whenever nothing covers the hero.
	if cut.size.x <= 0.0 or cut.size.y <= 0.0 or cut_alpha >= 0.999:
		return Rect2()
	var local := Rect2((cut.position - destination.position).round(), cut.size.round())
	return local.intersection(Rect2(Vector2.ZERO, destination.size))


func _draw_cut_cell(canvas: CanvasItem, texture: Texture2D, region: Rect2, destination: Rect2, core: Rect2, modulate: Color, cut_alpha: float) -> void:
	## Programmatic local alpha: the cell is split into the four bands that keep
	## the authored alpha plus the hero's own window at the cutaway alpha, so the
	## ruin keeps its whole form outside the hero and nothing is re-sorted.
	for piece: Dictionary in cut_pieces(destination, region, core, modulate.a, cut_alpha, false):
		_draw_cell_piece(canvas, texture, region, destination, piece["dest"], Color(modulate.r, modulate.g, modulate.b, float(piece["alpha"])))


## The rectangles a cut cell is drawn from, in draw order. One source of truth for
## the drawing and for the read-only geometry the visibility harness compares
## against real pixels, so a reported window is always the drawn window.
func cut_pieces(destination: Rect2, region: Rect2, core: Rect2, base_alpha: float, cut_alpha: float, clipped: bool = true) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var pieces := cutaway_pieces(Rect2(Vector2.ZERO, destination.size), core)
	for index: int in pieces.size():
		var piece: Rect2 = pieces[index]
		if piece.size.x <= 0.0 or piece.size.y <= 0.0:
			continue
		var dest := Rect2(destination.position + piece.position, piece.size)
		if clipped:
			dest = dest.intersection(visible_world_region())
			if dest.size.x <= 0.0 or dest.size.y <= 0.0:
				continue
		result.append({
			"dest": dest,
			"source": Rect2(region.position + (dest.position - destination.position), dest.size),
			"alpha": base_alpha * cut_alpha if index == CUTAWAY_WINDOW_INDEX else base_alpha,
			"window": index == CUTAWAY_WINDOW_INDEX,
		})
	return result


## Read-only geometry of one cell for this frame: what it is drawn as, where, from
## which source pixels and with which alpha. An empty list means the cell keeps its
## authored single-rectangle drawing.
func cutaway_geometry(sprite_id: String, feet_world: Vector2, hero_world_point: Vector2, base_alpha: float = 1.0) -> Array[Dictionary]:
	return _cutaway.cutaway_geometry(self, sprite_id, feet_world, hero_world_point, base_alpha)


func _draw_cell_piece(canvas: CanvasItem, texture: Texture2D, region: Rect2, destination: Rect2, piece: Rect2, modulate: Color) -> void:
	## One disjoint piece of a cell: clipped to the visible world exactly like the
	## whole cell is, and read from the same source region so a cut never
	## resamples the art.
	var visible := piece.intersection(visible_world_region())
	if visible.size.x <= 0.0 or visible.size.y <= 0.0:
		return
	var source := Rect2(region.position + (visible.position - destination.position), visible.size)
	canvas.draw_texture_rect_region(texture, visible, source, modulate)


func _cell_size(metadata: Dictionary) -> Vector2:
	var rect: Rect2 = metadata.get("rect", Rect2())
	return rect.size


func _read_json(path: String) -> Dictionary:
	var read := JsonIO.read_object_status(path)
	match String(read.status):
		JsonIO.STATUS_MISSING:
			pending_reason = "ASSETS PENDING: %s" % path
		JsonIO.STATUS_UNREADABLE:
			pending_reason = "ASSETS PENDING: cannot open %s" % path
		JsonIO.STATUS_INVALID:
			pending_reason = "ASSETS PENDING: invalid JSON in %s" % path
	return read.data


func _load_texture(path: String) -> Texture2D:
	# The approved PNG bytes are the source of truth: reading them directly keeps
	# the arena on the exact approved art even when an import cache is stale.
	# Exported builds fall back to the imported resource.
	var texture := TextureLoader.load_png_first(path)
	if texture == null:
		pending_reason = "ASSETS PENDING: missing %s" % path
	return texture


func _point(value: Variant) -> Vector2:
	if value is Vector2:
		return value
	if not value is Array or (value as Array).size() != 2:
		return Vector2.ZERO
	var array: Array = value
	return Vector2(float(array[0]), float(array[1]))


func _canvas_world_transform(canvas: CanvasItem) -> Transform2D:
	return canvas.get_meta("actor_world_transform", world_transform()) as Transform2D


## ----------------------------------------------------- structure fades
## Immediate-mode structure bands share the town controller's state machine; the
## eased state and materials live in arena_world/structure_fades.gd and the
## generated pack records in arena_world/generated_world.gd.
func reset_structure_fades() -> void:
	_fades.reset_structure_fades()


func set_layout_id(layout_id: String) -> void:
	if layout_id != _layout_id:
		_layout_id = layout_id
		reset_structure_fades()


func structure_fade_state(sprite_id: String, feet: Vector2) -> Dictionary:
	return _fades.structure_fade_state(sprite_id, feet)


func structure_fade_report() -> Dictionary:
	return _fades.structure_fade_report()


## The world-space detection rect of one whole-object generated piece, on the
## same feet-anchor mapping the draw pass uses.
func paired_detection_rect_world(sprite_id: String, feet: Vector2) -> Rect2:
	return _generated.detection_rect_world(sprite_id, feet)


## The material one placed whole-object piece draws through, or null before
## advance_structure_fades has created it.
func paired_reveal_material(sprite_id: String, feet: Vector2) -> Material:
	return _fades.paired_reveal_material(sprite_id, feet)


func structure_geometry(sprite_id: String, feet: Vector2) -> Array[Dictionary]:
	return _generated.geometry(sprite_id, feet)


func advance_structure_fades(drawables: Array, subjects: Array, delta: float) -> void:
	_fades.advance_structure_fades(self, drawables, subjects, delta)
