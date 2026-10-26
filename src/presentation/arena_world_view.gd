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

const PaletteScript = preload("res://src/presentation/combat_palette.gd")
const AtmosphereScript = preload("res://src/presentation/scene_atmosphere.gd")
const GroundingScript = preload("res://src/presentation/grounding_effects.gd")
const RoomCatalogScript = preload("res://src/runtime/world/room_catalog.gd")
const SortRelation = preload("res://src/presentation/occlusion_query.gd")
const PrimitiveFade := preload("res://src/presentation/occlusion/primitive_fade_controller.gd")
const PairedReveal := preload("res://src/presentation/occlusion/paired_reveal_controller.gd")
## Whole-object generated world pack: each family sprite is ONE opaque texture
## plus its baked transparent variant on the same canvas/anchor, with one
## authored detection rect (occupied AABB grown by DETECTION_GROW) in local
## canvas coordinates. Absent the pack, the approved atlas keeps drawing the
## historical fixtures unchanged.
const GENERATED_WORLD_PATH := "res://art/production/p1/generated_world_v02/assets.json"
const GENERATED_GROUND_ID := "arena_ground"
## Pack asset id -> live arena sprite id. The whole-object entries replace
## the legacy cells atomically once sections.arena.complete is true.
const GENERATED_SPRITE_IDS := {
	"ruin_wall_corner": "ruin.wall_corner",
	"ruin_gate": "ruin.gate",
	"ruin_low_pier": "ruin.low_pier",
	"ruin_broken_wall": "ruin.broken_wall",
	"tower": "tower",
}
## Existing 128px ruin cells share an anchor at row 120. Keep their lower
## 36px of visible structure solid; source pixels are neither repainted nor moved.
const STRUCTURE_BASE_ROW := 84.0
const STRUCTURE_VOLUME_PAD := 4.0
const ATMOSPHERE_PRESET := "arena"

const SCENE_ATLAS_PATH: String = "res://art/production/p1/actors_v02/scene_atlas.json"
const SCENE_LAYOUT_PATH: String = "res://art/production/p1/combat_style_r13/v03/layout.json"
const LEGACY_ATLAS_PATH: String = "res://art/production/p1/actors_v02/legacy_atlas.json"
const APPROVED_GROUND_PATH: String = "res://art/production/p1/combat_style_r13/v03/ground.png"
const APPROVED_GROUND_KEY: String = "approved_ground"
const DISPLAY_SCALE: float = 2.0
const GAMEPLAY_TO_WORLD: float = 0.72
const WORLD_SIZE := Vector2(1024.0, 640.0)
## The mapped playfield is centred on this world point, so the authored ruins and
## tower end up along the walkable edges instead of on top of the fight.
const WORLD_FOCUS := Vector2(512.0, 360.0)
## Extra world headroom kept above the hero (native units) so a colossus head and
## the boss target shape stay clear of the frame and the top HUD strip.
const CAMERA_UP_OFFSET: float = 96.0
const FORE_FADE: float = 0.45
## Conservative cutaway: a ruin, the tower or the colossus that really covers the
## hero keeps its authored alpha everywhere except the hero's own overlap window,
## where the stack is capped so the hero's real source pixels survive the 0.20
## per-channel visibility gate instead of being washed out by a whole-cell fade.
## The window is the hero cell grown by CUTAWAY_WINDOW_PAD, so no drawn hero
## pixel ever sits on the window edge. The window is a rectangle on the same
## integer grid the rest of the arena draws on.
const CUTAWAY_TOTAL_OPACITY: float = 0.16
const CUTAWAY_WINDOW_PAD: float = 2.0
## Index of the window inside the five tiling pieces (four solid bands first).
const CUTAWAY_WINDOW_INDEX: int = 4
## Alpha bounds stay conservative by one source pixel so antialiased edge pixels
## and the integer destination rounding cannot make an occluder too small.
const ALPHA_VISIBLE_BOUNDS_PADDING: float = 1.0
## A source pixel with any meaningful alpha is part of the visual occluder.  The
## mask is used only to decide whether two drawn cells really meet; the one
## pixel bounds padding above remains the conservative box used for diagnostics.
const ALPHA_OCCLUSION_THRESHOLD: float = 0.0
const GROUND_SPRITE_ID: String = "scene.ground"
## Only these calibration_v01 sprites are reused read-only; the reworked atlas
## owns everything else, so a missing reworked sprite stays missing instead of
## silently falling back to an older drawing.
const LEGACY_SPRITE_IDS: Array[String] = [
	"tower.upper", "tower.base",
	"enemy.melee.idle", "enemy.melee.windup", "enemy.melee.active", "enemy.melee.recover",
	"enemy.charger.idle", "enemy.charger.windup", "enemy.charger.active", "enemy.charger.recover",
	"enemy.ranged.idle", "enemy.ranged.windup", "enemy.ranged.active", "enemy.ranged.recover",
]
const CELL_CONTRACTS := {
	"scene.ground": {"size": Vector2i(1024, 640)},
	"ground.snow_wedge": {"size": Vector2i(128, 96), "anchor": Vector2i(64, 90)},
	"ground.snow_strip": {"size": Vector2i(128, 96), "anchor": Vector2i(64, 90)},
	"ground.rubble_apron": {"size": Vector2i(128, 96), "anchor": Vector2i(64, 90)},
	"ground.foundation": {"size": Vector2i(128, 96), "anchor": Vector2i(64, 90)},
	"ruin.wall_corner": {"size": Vector2i(128, 128), "anchor": Vector2i(64, 120)},
	"ruin.gate": {"size": Vector2i(128, 128), "anchor": Vector2i(64, 120)},
	"ruin.low_pier": {"size": Vector2i(128, 128), "anchor": Vector2i(64, 120)},
	"ruin.broken_wall": {"size": Vector2i(128, 128), "anchor": Vector2i(64, 120)},
	"ranger.south.idle": {"size": Vector2i(32, 48), "anchor": Vector2i(16, 44)},
	"ranger.north.idle": {"size": Vector2i(32, 48), "anchor": Vector2i(16, 44)},
	"ranger.east.idle": {"size": Vector2i(32, 48), "anchor": Vector2i(16, 44)},
	"ranger.west.idle": {"size": Vector2i(32, 48), "anchor": Vector2i(16, 44)},
	"boss.body_phase1": {"size": Vector2i(128, 128), "anchor": Vector2i(64, 120)},
	"boss.body_phase2": {"size": Vector2i(128, 128), "anchor": Vector2i(64, 120)},
	"boss.hand_left": {"size": Vector2i(48, 64), "anchor": Vector2i(24, 56)},
	"boss.hand_right": {"size": Vector2i(48, 64), "anchor": Vector2i(24, 56)},
	"boss.core_phase1": {"size": Vector2i(32, 64), "anchor": Vector2i(16, 56)},
	"boss.core_phase2": {"size": Vector2i(32, 64), "anchor": Vector2i(16, 56)},
	"tower.upper": {"size": Vector2i(128, 192), "anchor": Vector2i(64, 184), "keep_rows": [0, 148]},
	"tower.base": {"size": Vector2i(128, 192), "anchor": Vector2i(64, 184), "keep_rows": [148, 192]},
	"enemy.melee.idle": {"size": Vector2i(48, 48), "anchor": Vector2i(24, 44)},
	"enemy.melee.windup": {"size": Vector2i(48, 48), "anchor": Vector2i(24, 44)},
	"enemy.melee.active": {"size": Vector2i(48, 48), "anchor": Vector2i(24, 44)},
	"enemy.melee.recover": {"size": Vector2i(48, 48), "anchor": Vector2i(24, 44)},
	"enemy.charger.idle": {"size": Vector2i(48, 48), "anchor": Vector2i(24, 44)},
	"enemy.charger.windup": {"size": Vector2i(48, 48), "anchor": Vector2i(24, 44)},
	"enemy.charger.active": {"size": Vector2i(48, 48), "anchor": Vector2i(24, 44)},
	"enemy.charger.recover": {"size": Vector2i(48, 48), "anchor": Vector2i(24, 44)},
	"enemy.ranged.idle": {"size": Vector2i(48, 48), "anchor": Vector2i(24, 44)},
	"enemy.ranged.windup": {"size": Vector2i(48, 48), "anchor": Vector2i(24, 44)},
	"enemy.ranged.active": {"size": Vector2i(48, 48), "anchor": Vector2i(24, 44)},
	"enemy.ranged.recover": {"size": Vector2i(48, 48), "anchor": Vector2i(24, 44)},
}
const BOSS_CORE_OFFSET := Vector2(0.0, -38.0)
const BOSS_HAND_LEFT_OFFSET := Vector2(-68.0, -18.0)
const BOSS_HAND_RIGHT_OFFSET := Vector2(68.0, -18.0)
const TOWER_UPPER_FADE: float = 0.52

var pending_reason: String = ""

var _sprites: Dictionary = {}
var _textures: Dictionary = {}
var _texture_images: Dictionary = {}
var _alpha_visible_bounds: Dictionary = {}
var _alpha_masks: Dictionary = {}
var _decals: Array[Dictionary] = []
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
## One actor-over-actor cutaway plan per hero position. Structures use their
## own upper-band primitive fade and do not consume this local actor budget.
var _cutaway_hero := Vector2(INF, INF)
var _cutaway_front: Array[Dictionary] = []
var _cutaway_window := Rect2()
var _cutaway_share := 1.0
var _actor_cutaway_ready := false
var _actor_occluders: Array[Dictionary] = []
## The colossus is drawn by this file but its live position only exists at draw
## time, so the report can only speak about the colossus of the frame that was
## really drawn.
var _ready := false
var _atmosphere_drawn := false
var _grounding_counts := {"contact": 0, "base": 0, "base_ids": [], "lit": 0}
var _grounding_lights_cache: Array = []
var _room_catalog: RefCounted
var _structure_fades: Dictionary = {}
var _layout_id := "rectangle_arena"
var _room_structure_overrides: Dictionary = {}
## Whole-object generated sprites: sprite_id -> {texture_key, opaque, variant,
## canvas, anchor, occupied_rect, occlusion_rect(canvas-local)}. One ShaderMaterial
## per placed piece key carries the eased reveal weight.
var _generated_sprites: Dictionary = {}
var _paired_materials: Dictionary = {}
## Fixture seams: production always points at GENERATED_WORLD_PATH; tests may
## substitute a synthetic pack to exercise the whole-object branch.
var generated_world_path := GENERATED_WORLD_PATH


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


func decal_placements() -> Array[Dictionary]:
	if not _generated_sprites.is_empty():
		return []
	return _decals.duplicate(true)


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
	_texture_images.clear()
	_alpha_visible_bounds.clear()
	_alpha_masks.clear()
	_decals.clear()
	_structures.clear()
	_room_structure_overrides.clear()
	_ready = false
	var scene_atlas := _read_json(SCENE_ATLAS_PATH)
	var legacy_atlas := _read_json(LEGACY_ATLAS_PATH)
	var layout := _read_json(SCENE_LAYOUT_PATH)
	if scene_atlas.is_empty() or legacy_atlas.is_empty() or layout.is_empty():
		return false
	if not _select_union(scene_atlas, legacy_atlas):
		return false
	if not _load_textures(scene_atlas, legacy_atlas):
		return false
	if not _validate_cells():
		return false
	if not _read_layout(layout):
		return false
	if not _load_generated_world():
		return false
	## The floor pack is required whenever the generated world pack claims
	## authority; an absent generated pack is the historical-fixture flag.
	if not room_floor_pack_path.is_empty():
		_room_scene.pack_path = room_floor_pack_path
	if not _room_scene.load_assets(FileAccess.file_exists(generated_world_path), WORLD_FOCUS, GAMEPLAY_TO_WORLD):
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
	_cutaway_hero = Vector2(INF, INF)
	_atmosphere_drawn = false
	_actor_cutaway_ready = false
	_actor_occluders.clear()


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
	## A loaded room floor pack owns every layout's plate; the shared approved
	## ground only draws on the explicit historical-fixture seam.
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
	## The generated plate already contains its terrain detail. Legacy snow and
	## foundation stamps belong only to the historical atlas composition.
	for placement in decal_placements():
		draw_sprite(canvas, String(placement.get("id", "")), gameplay_to_world(_point(placement.get("feet", []))))


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


## Shadow from the structure's actual lowest opaque contour (its base band, or the whole
## generated object) at the geometry the draw path really uses; source art is untouched.
func _draw_base_shadow(canvas: CanvasItem, sprite_id: String, feet_world: Vector2) -> void:
	var bands := structure_geometry(sprite_id, feet_world)
	for index in range(bands.size() - 1, -1, -1):
		var band: Dictionary = bands[index]
		if String(band.part) == "upper":
			continue
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

static func cutaway_window(cell: Rect2) -> Rect2:
	## The hero cell plus its pad, kept on the integer pixel grid the arena draws
	## on so a cut cell always lands on whole source pixels.
	var grown := cell.grow(CUTAWAY_WINDOW_PAD)
	return Rect2(grown.position.round(), grown.size.round())


static func cutaway_alpha(count: int) -> float:
	## Even split of the local opacity budget: the source-over stack of any subset
	## of those cells never exceeds CUTAWAY_TOTAL_OPACITY, whatever the authored
	## fade already leaves on top of them.
	if count <= 0:
		return 1.0
	return clampf(1.0 - pow(1.0 - CUTAWAY_TOTAL_OPACITY, 1.0 / float(count)), 0.0, 1.0)


static func cutaway_pieces(quad: Rect2, core: Rect2) -> Array[Rect2]:
	## Four solid bands plus the window tile the drawn cell exactly once under
	## source-over blending, in the order they are drawn.
	var top := Rect2(quad.position, Vector2(quad.size.x, core.position.y - quad.position.y))
	var bottom := Rect2(Vector2(quad.position.x, core.end.y), Vector2(quad.size.x, quad.end.y - core.end.y))
	var left := Rect2(Vector2(quad.position.x, core.position.y), Vector2(core.position.x - quad.position.x, core.size.y))
	var right := Rect2(Vector2(core.end.x, core.position.y), Vector2(quad.end.x - core.end.x, core.size.y))
	return [top, bottom, left, right, core]


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
	var visible := _visible_region_bounds(_textures.get(String(metadata.get("texture", ""))) as Texture2D, region)
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
	var visible := _visible_region_bounds(texture, source_rect)
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
	return _occlusion_descriptor(_textures.get(String(metadata.get("texture", ""))) as Texture2D, region, destination, flip_x)


## Dynamic action frames use exactly the same descriptor contract as published
## sprites, including authored draw offsets and horizontal mirroring.
func frame_occlusion_descriptor(texture: Texture2D, source_rect: Rect2, feet_world: Vector2, anchor: Vector2, draw_offset: Vector2 = Vector2.ZERO, flip_x: bool = false) -> Dictionary:
	if source_rect.size.x <= 0.0 or source_rect.size.y <= 0.0:
		return {}
	var destination := Rect2((feet_world - anchor + draw_offset).round(), source_rect.size)
	return _occlusion_descriptor(texture, source_rect, destination, flip_x)


## Public read-only query used by actor and structure passes.  A missing or
## unreadable texture deliberately falls back to its destination box, matching
## the existing conservative art-box behavior.
func occlusion_descriptor_intersects(descriptor: Dictionary, query: Rect2) -> bool:
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
			if descriptor is Dictionary and occlusion_descriptor_intersects(descriptor, query):
				return true
		return false
	if visibility is Dictionary:
		return occlusion_descriptor_intersects(visibility, query)
	return false


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
func cutaway_front(_hero_world_point: Vector2) -> Array[Dictionary]:
	# Structures use whole upper-band transparency, never character cutouts.
	# This list is retained as a compatibility query for the actor-only budget.
	return []


func cutaway_for(art_box: Rect2, feet_world: Vector2, hero_world_point: Vector2, sort_rank: int = 1, stable_id: String = "actor", visibility: Variant = null) -> Dictionary:
	var cell := hero_cell_world(hero_world_point)
	var window := cutaway_window(cell)
	var actor_sort := SortRelation.entry(feet_world.y, sort_rank, stable_id)
	var overlaps := visibility_intersects(visibility, window) if visibility != null else art_box.intersects(window)
	if not SortRelation.is_front(actor_sort, _hero_sort_entry(hero_world_point)) or not overlaps:
		return {"window": window, "local_alpha": 1.0, "in_front": false}
	## This budget covers only actor-over-actor drawing; structures fade separately.
	var share := float(_cutaway_plan(hero_world_point)["alpha"]) if _actor_cutaway_ready else cutaway_alpha(cutaway_front(hero_world_point).size() + 1)
	return {"window": window, "local_alpha": share, "in_front": true}


## The actor pass supplies every live front-facing actor cell before drawing.
## Normal enemies and Boss parts share one local opacity budget.
func prepare_actor_occlusion(cells: Array[Dictionary], hero_world_point: Vector2) -> void:
	_actor_occluders.clear()
	var window := cutaway_window(hero_cell_world(hero_world_point))
	var hero_sort := _hero_sort_entry(hero_world_point)
	for cell: Dictionary in cells:
		var box: Rect2 = cell["art_box"]
		var visibility: Variant = cell.get("visibility", null)
		var stable_id := String(cell.get("stable_id", cell.get("id", "actor")))
		var sort_rank := int(cell.get("sort_rank", cell.get("rank", 1)))
		var baseline_y := float(cell.get("baseline_y", (cell.get("feet_world", Vector2.ZERO) as Vector2).y))
		var actor_sort := SortRelation.entry(baseline_y, sort_rank, stable_id)
		var overlaps := visibility_intersects(visibility, window) if visibility != null else box.intersects(window)
		if SortRelation.is_front(actor_sort, hero_sort) and overlaps:
			_actor_occluders.append(cell.duplicate())
	_actor_cutaway_ready = true
	_cutaway_hero = Vector2(INF, INF)


func _tower_upper_faded(hero_world_point: Vector2) -> bool:
	var feet := tower_feet_world()
	if _generated_sprites.has("tower"):
		if not SortRelation.is_front(SortRelation.entry(feet.y, 0, "structure/tower"), _hero_sort_entry(hero_world_point)):
			return false
		return paired_detection_rect_world("tower", feet).intersects(hero_cell_world(hero_world_point))
	if not SortRelation.is_front(SortRelation.entry(feet.y, 0, "structure/tower"), _hero_sort_entry(hero_world_point)):
		return false
	return visibility_intersects(sprite_occlusion_descriptor("tower.upper", feet), hero_cell_world(hero_world_point))


func _cutaway_plan(hero_world_point: Vector2) -> Dictionary:
	if _cutaway_hero != hero_world_point:
		_cutaway_hero = hero_world_point
		_cutaway_front = cutaway_front(hero_world_point)
		_cutaway_window = cutaway_window(hero_cell_world(hero_world_point))
		_cutaway_share = cutaway_alpha(_cutaway_front.size() + _actor_occluders.size())
	return {"window": _cutaway_window, "alpha": _cutaway_share, "front": _cutaway_front}


## The window and the share one placed cell of this frame's plan draws with. Empty
## means that cell keeps its authored alpha for this frame: a ruin that stands
## behind the hero is never cut, and only the instance that really sorts in front
## of it shares the window, even when the arena places the same ruin twice.
func _cutaway_for_cell(sprite_id: String, feet_world: Vector2, hero_world_point: Vector2) -> Dictionary:
	var plan := _cutaway_plan(hero_world_point)
	for entry: Dictionary in plan["front"] as Array:
		var entry_id := String(entry["id"])
		## The tower is one occluder published as tower.base and tower.upper, so a
		## band matches the occluder it belongs to.
		if not (entry_id == sprite_id or sprite_id.begins_with(entry_id + ".")):
			continue
		if not (entry["feet_world"] as Vector2).is_equal_approx(feet_world):
			continue
		return {"window": plan["window"], "alpha": plan["alpha"]}
	return {"window": Rect2(), "alpha": 1.0}


## The colossus is one occluder drawn as four sprites: when it really stands in
## front of the hero they all share a single split of the budget the ruins are not
## already using, so body, core and both hands can never stack opaquely.
func _boss_cutaway(sprite_ids: Array, feet_list: Array, feet_world: Vector2, hero_world_point: Vector2, sort_feet_list: Array = []) -> Dictionary:
	var plan := _cutaway_plan(hero_world_point)
	var window: Rect2 = plan["window"]
	var overlapping := 0
	var hero_sort := _hero_sort_entry(hero_world_point)
	var part_ids := ["body", "core", "left_hand", "right_hand"]
	for index: int in sprite_ids.size():
		var sort_feet: Vector2 = feet_world if index < 2 else feet_list[index]
		if index < sort_feet_list.size():
			sort_feet = sort_feet_list[index] as Vector2
		var sort_id := "enemy/boss/%s" % String(part_ids[index] if index < part_ids.size() else sprite_ids[index])
		var actor_sort := SortRelation.entry(sort_feet.y, 3, sort_id)
		var visibility := sprite_occlusion_descriptor(String(sprite_ids[index]), feet_list[index] as Vector2)
		if SortRelation.is_front(actor_sort, hero_sort) and visibility_intersects(visibility, window):
			overlapping += 1
	if overlapping <= 0:
		return {"window": Rect2(), "alpha": 1.0}
	if _actor_cutaway_ready:
		return {"window": window, "alpha": plan["alpha"]}
	return {"window": window, "alpha": cutaway_alpha((plan["front"] as Array).size() + overlapping)}


## Read-only cutaway diagnostic for the external visibility harness: how many
## foreground cells really cover the hero, the total local opacity they compose
## to, and the window itself. Nothing here writes or re-sorts the arena.
func occlusion_report(hero_world_point: Vector2) -> Dictionary:
	var cell := hero_cell_world(hero_world_point)
	var window := cutaway_window(cell)
	var front := cutaway_front(hero_world_point)
	var alpha := cutaway_alpha(front.size() + _actor_occluders.size())
	var entries: Array[Dictionary] = []
	var front_ids: Array[String] = []
	var opacity := 0.0
	for entry: Dictionary in front:
		var local := alpha * float(entry["base_alpha"])
		opacity = 1.0 - (1.0 - opacity) * (1.0 - local)
		front_ids.append(String(entry["id"]))
		entries.append({
			"id": String(entry["id"]),
			"sprite_id": String(entry["id"]),
			"node": String(entry["id"]),
			"feet_world": entry["feet_world"],
			"art_box": entry["art_box"],
			"local_alpha": local,
			"overlap": entry["overlap"],
		})
	for actor: Dictionary in _actor_occluders:
		var local := alpha * float(actor.get("base_alpha", 1.0))
		opacity = 1.0 - (1.0 - opacity) * (1.0 - local)
		var entry := actor.duplicate()
		entry["local_alpha"] = local
		entry["overlap"] = (entry["art_box"] as Rect2).intersection(window)
		entries.append(entry)
		front_ids.append(String(entry["id"]))

	return {
		"hero_world": hero_world_point,
		"hero_cell_world": cell,
		"window_world": window,
		"window_pad": CUTAWAY_WINDOW_PAD,
		"occluder_count": entries.size(),
		"local_alpha_each": alpha,
		"local_opacity_total": opacity,
		"occluders": entries,
		"front_ids": front_ids,
		"front_nodes": front_ids.duplicate(),
		"unchanged": entries.is_empty(),
		"primitive_fade": structure_fade_report(),
		"local_opacity_scope": "actor-over-actor cutaway only; structure bands reported separately",
	}


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
	var in_front: Array[String] = []
	var faded: Array[String] = []
	var full_covers: Array[String] = []
	var box := hero_cell_world(hero_world_point)
	for state: Dictionary in _structure_fades.values():
		if not SortRelation.is_front(state.part, _hero_sort_entry(hero_world_point)) or not (state.volume as Rect2).intersects(box):
			continue
		var id := String(state.sprite_id)
		in_front.append(id)
		if float(state.alpha) < 1.0:
			faded.append(id)
		elif (state.volume as Rect2).encloses(box):
			full_covers.append(id)
	return {"hero_cell": box, "in_front": in_front, "faded": faded,
		"unfaded_full_covers": full_covers, "hero_visible": full_covers.is_empty(),
		"scope": "upper structure bands and whole-object paired rects; solid-base clearance is a movement contract"}


func draw_structure(canvas: CanvasItem, sprite_id: String, feet_world: Vector2, _hero_world_point: Vector2) -> void:
	for band: Dictionary in structure_geometry(sprite_id, feet_world):
		_draw_cell_piece(canvas, _textures[band.texture], band.source, band.dest, band.dest, _lit(Color(1, 1, 1, band.alpha), feet_world))


func structure_draw_alpha(sprite_id: String, feet_world: Vector2, hero_world_point: Vector2) -> float:
	return structure_fade(sprite_id, feet_world, hero_world_point)


func draw_tower(canvas: CanvasItem, _hero_world_point: Vector2) -> void:
	for band: Dictionary in structure_geometry("tower", tower_feet_world()):
		_draw_cell_piece(canvas, _textures[band.texture], band.source, band.dest, band.dest, _lit(Color(1, 1, 1, band.alpha), tower_feet_world()))


func boss_draw_parts(feet_world: Vector2, phase: int, left_hand_delta_gameplay: Vector2, right_hand_delta_gameplay: Vector2, pose_frame: Dictionary = {}) -> Array[Dictionary]:
	var phase_id := 2 if phase >= 2 else 1
	var left_anchor := feet_world + BOSS_HAND_LEFT_OFFSET + left_hand_delta_gameplay * GAMEPLAY_TO_WORLD
	var right_anchor := feet_world + BOSS_HAND_RIGHT_OFFSET + right_hand_delta_gameplay * GAMEPLAY_TO_WORLD
	# Body/core share the actor's ground baseline. Hand baselines follow the
	# gameplay pose; cosmetic lift/recoil changes the sprite, never its ground.
	return [
		{"part_id": "body", "sprite_id": "boss.body_phase%d" % phase_id, "sort_feet": feet_world, "feet": feet_world + Vector2(pose_frame.get("body_offset_px", Vector2i.ZERO)), "tint": Color.WHITE},
		{"part_id": "core", "sprite_id": "boss.core_phase%d" % phase_id, "sort_feet": feet_world, "feet": feet_world + BOSS_CORE_OFFSET + Vector2(pose_frame.get("core_offset_px", Vector2i.ZERO)), "tint": Color(pose_frame.get("core_tint", Color.WHITE))},
		{"part_id": "left_hand", "sprite_id": "boss.hand_left", "sort_feet": left_anchor, "feet": left_anchor + Vector2(pose_frame.get("left_hand_offset_px", Vector2i.ZERO)), "tint": Color.WHITE},
		{"part_id": "right_hand", "sprite_id": "boss.hand_right", "sort_feet": right_anchor, "feet": right_anchor + Vector2(pose_frame.get("right_hand_offset_px", Vector2i.ZERO)), "tint": Color.WHITE},
	]


## One independently sorted authored cell. The sort anchor, rather than the
## logical Boss's root, decides whether this part is in front of the player.
func draw_boss_part(canvas: CanvasItem, part: Dictionary, hero_world_point: Vector2, sort_rank: int = 3, stable_id: String = "enemy/boss/part") -> void:
	var feet: Vector2 = part.feet
	var anchor: Vector2 = part.sort_feet
	var visibility := sprite_occlusion_descriptor(String(part.sprite_id), feet)
	var box: Rect2 = visibility.get("art_box", Rect2())
	var cut := cutaway_for(box, anchor, hero_world_point, sort_rank, stable_id, visibility)
	## Boss parts use the same local window as ruins.  Keeping the rest of the
	## part opaque preserves its mass and silhouette while the player remains
	## readable at the actual overlap.
	var alpha := 1.0
	var tint: Color = part.get("tint", Color.WHITE)
	tint.a *= alpha
	draw_sprite(canvas, String(part.sprite_id), feet, false, tint, cut["window"] if cut["in_front"] else Rect2(), float(cut["local_alpha"]))


## Body, core and both hands in world units, in the order they are drawn.
func boss_parts_world(feet_world: Vector2) -> Array[Rect2]:
	var parts: Array[Rect2] = []
	for part: Dictionary in boss_draw_parts(feet_world, 2, Vector2.ZERO, Vector2.ZERO):
		var box := sprite_art_box(String(part.get("sprite_id", "")), part.get("feet", feet_world))
		if box.size.x > 0.0 and box.size.y > 0.0:
			parts.append(box)
	return parts


## 1.0 when the colossus cannot hide the hero, FORE_FADE when it is in front of
## and overlapping the hero's real cells.
func boss_fade_alpha(
	feet_world: Vector2,
	hero_world_point: Vector2,
	phase: int = 2,
	left_hand_delta_gameplay: Vector2 = Vector2.ZERO,
	right_hand_delta_gameplay: Vector2 = Vector2.ZERO,
	pose_frame: Dictionary = {}
) -> float:
	var hero_cell := hero_cell_world(hero_world_point)
	for part: Dictionary in boss_draw_parts(feet_world, phase, left_hand_delta_gameplay, right_hand_delta_gameplay, pose_frame):
		var part_id := String(part.get("part_id", "part"))
		var sort_feet: Vector2 = part.get("sort_feet", feet_world)
		var visibility := sprite_occlusion_descriptor(String(part.get("sprite_id", "")), part.get("feet", feet_world))
		var art_box: Rect2 = visibility.get("art_box", Rect2())
		var actor_sort := SortRelation.entry(sort_feet.y, 3, "enemy/boss/%s" % part_id)
		if SortRelation.is_front(actor_sort, _hero_sort_entry(hero_world_point)) and visibility_intersects(visibility, hero_cell):
			return FORE_FADE
	return 1.0


## Colossus footprint in world units, used by the visibility checks so a boss
## head that leaves the frame or slips under the HUD can never pass as "fine".
func boss_body_rect_world(feet_world: Vector2) -> Rect2:
	return sprite_art_box("boss.body_phase2", feet_world)


func boss_hand_rect_world(feet_world: Vector2, left: bool) -> Rect2:
	var sprite_id := "boss.hand_left" if left else "boss.hand_right"
	var offset := BOSS_HAND_LEFT_OFFSET if left else BOSS_HAND_RIGHT_OFFSET
	return sprite_art_box(sprite_id, feet_world + offset)


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


func _occlusion_descriptor(texture: Texture2D, source_rect: Rect2, destination: Rect2, flip_x: bool) -> Dictionary:
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
	var visible := _visible_region_bounds(texture, source_rect)
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


func _visible_region_bounds(texture: Texture2D, source_rect: Rect2) -> Rect2:
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


func _prime_alpha_visible_bounds() -> void:
	for sprite_id: String in _sprites.keys():
		var metadata: Dictionary = _sprites[sprite_id]
		_visible_region_bounds(_textures.get(String(metadata.get("texture", ""))) as Texture2D, _region_of(metadata))


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
	var metadata := sprite(sprite_id)
	if metadata.is_empty():
		return []
	var rect: Rect2 = metadata.get("rect", Rect2())
	var anchor: Vector2 = metadata.get("anchor", Vector2.ZERO)
	var region := _region_of(metadata)
	var destination := Rect2((feet_world - anchor + (region.position - rect.position)).round(), region.size)
	var cut := _cutaway_for_cell(sprite_id, feet_world, hero_world_point)
	var core := _cutaway_core(destination, cut["window"] as Rect2, float(cut["alpha"]))
	if core.size.x <= 0.0 or core.size.y <= 0.0:
		return []
	return cut_pieces(destination, region, core, base_alpha, float(cut["alpha"]))


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


func _select_union(scene_atlas: Dictionary, legacy_atlas: Dictionary) -> bool:
	var scene_sprites := scene_atlas.get("sprites", {}) as Dictionary
	var legacy_sprites := legacy_atlas.get("sprites", {}) as Dictionary
	for sprite_id in scene_sprites.keys():
		if LEGACY_SPRITE_IDS.has(String(sprite_id)):
			pending_reason = "ASSETS PENDING: reworked atlas must not override %s" % sprite_id
			return false
		var normalized := _normalize_sprite(scene_sprites[sprite_id] as Dictionary)
		if normalized.is_empty():
			return false
		_sprites[String(sprite_id)] = normalized
	for sprite_id in LEGACY_SPRITE_IDS:
		var raw: Variant = legacy_sprites.get(sprite_id, {})
		if not raw is Dictionary:
			pending_reason = "ASSETS PENDING: calibration atlas lacks %s" % sprite_id
			return false
		var normalized := _normalize_sprite(raw as Dictionary)
		if normalized.is_empty():
			return false
		_sprites[sprite_id] = normalized
	return true


func _normalize_sprite(raw: Dictionary) -> Dictionary:
	var rect: Array = raw.get("rect", [])
	var anchor: Array = raw.get("anchor", [])
	if rect.size() != 4 or anchor.size() != 2:
		pending_reason = "ASSETS PENDING: malformed rect/anchor for %s" % String(raw.get("texture", ""))
		return {}
	var normalized := {
		"texture": String(raw.get("texture", "")),
		"rect": Rect2(float(rect[0]), float(rect[1]), float(rect[2]), float(rect[3])),
		"anchor": Vector2(float(anchor[0]), float(anchor[1])),
	}
	if raw.has("keep_rows"):
		normalized["keep_rows"] = (raw.get("keep_rows") as Array).duplicate()
	return normalized


func _load_textures(scene_atlas: Dictionary, legacy_atlas: Dictionary) -> bool:
	var sources: Dictionary = (scene_atlas.get("textures", {}) as Dictionary).duplicate(true)
	var legacy_sources: Dictionary = legacy_atlas.get("textures", {})
	for sprite_id: String in LEGACY_SPRITE_IDS:
		var key := String(_sprites[sprite_id].get("texture", ""))
		if not legacy_sources.has(key):
			pending_reason = "ASSETS PENDING: reused sprite %s has no texture metadata" % sprite_id
			return false
		if sources.has(key) and sources[key] != legacy_sources[key]:
			pending_reason = "ASSETS PENDING: conflicting texture key %s in composed atlas" % key
			return false
		sources[key] = legacy_sources[key]
	for texture_key in sources.keys():
		var metadata := sources[texture_key] as Dictionary
		var path := _scoped_texture_path(String(texture_key), String(metadata.get("path", "")))
		var texture := _load_texture(path)
		if texture == null:
			return false
		if texture.get_width() != int(metadata.get("width", 0)) or texture.get_height() != int(metadata.get("height", 0)):
			pending_reason = "ASSETS PENDING: %s size does not match its atlas entry" % path
			return false
		_textures[String(texture_key)] = texture
	var ground := _load_texture(APPROVED_GROUND_PATH)
	if ground == null:
		return false
	if ground.get_width() != int(WORLD_SIZE.x) or ground.get_height() != int(WORLD_SIZE.y):
		pending_reason = "ASSETS PENDING: approved ground must be 1024x640"
		return false
	_textures[APPROVED_GROUND_KEY] = ground
	_prime_alpha_visible_bounds()
	return true


## The reworked atlas ships its own ground; the approved ground_refine_v01 land
## texture replaces it for every arena use, including any legacy lookup.
func _scoped_texture_path(texture_key: String, path: String) -> String:
	if texture_key == "ground" and String(_sprites.get(GROUND_SPRITE_ID, {}).get("texture", "")) == "ground":
		return APPROVED_GROUND_PATH
	return path


func _validate_cells() -> bool:
	for sprite_id in CELL_CONTRACTS.keys():
		var metadata := sprite(String(sprite_id))
		if metadata.is_empty():
			pending_reason = "ASSETS PENDING: missing sprite %s" % sprite_id
			return false
		var contract: Dictionary = CELL_CONTRACTS[sprite_id]
		var rect: Rect2 = metadata.get("rect", Rect2())
		var expected_size: Vector2i = contract.get("size", Vector2i.ZERO)
		if Vector2i(rect.size) != expected_size:
			pending_reason = "ASSETS PENDING: %s violates its cell size contract" % sprite_id
			return false
		if contract.has("anchor"):
			var expected_anchor: Vector2i = contract.get("anchor", Vector2i.ZERO)
			if Vector2i(metadata.get("anchor", Vector2.ZERO)) != expected_anchor:
				pending_reason = "ASSETS PENDING: %s violates its anchor contract" % sprite_id
				return false
	if _sprites.get(GROUND_SPRITE_ID, {}).get("texture", "") != "ground":
		pending_reason = "ASSETS PENDING: scene.ground must come from the ground texture"
		return false
	return true


func _read_layout(layout: Dictionary) -> bool:
	var world := _point(layout.get("world_size", []))
	if world != WORLD_SIZE:
		pending_reason = "ASSETS PENDING: layout world_size must be 1024x640"
		return false
	_tower_feet = _point(layout.get("tower_feet", []))
	var overrides: Variant = layout.get("room_structure_overrides", {})
	if not overrides is Dictionary:
		pending_reason = "ASSETS PENDING: invalid room structure overrides"
		return false
	_room_structure_overrides = (overrides as Dictionary).duplicate(true)
	for value in layout.get("decals", []) as Array:
		_decals.append((value as Dictionary).duplicate(true))
	for value in layout.get("structures", []) as Array:
		_structures.append((value as Dictionary).duplicate(true))
	var valid_ids := {"tower": true}
	var occurrences := {}
	for placement: Dictionary in _structures:
		var id := String(placement.id)
		var ordinal := int(occurrences.get(id, 0))
		occurrences[id] = ordinal + 1
		valid_ids[id + "#" + str(ordinal)] = true
	for room: Variant in _room_structure_overrides:
		var values: Variant = _room_structure_overrides[room]
		if room not in ["rectangle_arena", "corridor", "ring"] or not values is Dictionary:
			pending_reason = "ASSETS PENDING: unknown room structure override"
			return false
		for id: Variant in values:
			var point: Variant = values[id]
			if not valid_ids.has(id) or not point is Array or (point as Array).size() != 2:
				pending_reason = "ASSETS PENDING: invalid structure override identity or point"
				return false
			for coordinate: Variant in point:
				if not (coordinate is float or coordinate is int) or not is_finite(float(coordinate)):
					pending_reason = "ASSETS PENDING: nonfinite structure override"
					return false
	if _decals.is_empty() or _structures.is_empty():
		pending_reason = "ASSETS PENDING: layout must place decals and structures"
		return false
	for placement in _decals + _structures:
		var metadata := sprite(String(placement.get("id", "")))
		if metadata.is_empty():
			pending_reason = "ASSETS PENDING: layout places %s without an atlas sprite" % String(placement.get("id", ""))
			return false
		var cell := Rect2(WORLD_FOCUS + (_point(placement.get("feet", [])) - Vector2(640, 434)) * GAMEPLAY_TO_WORLD - (metadata.get("anchor", Vector2.ZERO) as Vector2), _cell_size(metadata))
		if not Rect2(Vector2.ZERO, WORLD_SIZE).encloses(cell):
			pending_reason = "ASSETS PENDING: %s leaves the world" % String(placement.get("id", ""))
			return false
	return true


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		pending_reason = "ASSETS PENDING: %s" % path
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		pending_reason = "ASSETS PENDING: cannot open %s" % path
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		pending_reason = "ASSETS PENDING: invalid JSON in %s" % path
		return {}
	return parsed as Dictionary


func _load_texture(path: String) -> Texture2D:
	# The approved PNG bytes are the source of truth: reading them directly keeps
	# the arena on the exact approved art even when an import cache is stale.
	# Exported builds fall back to the imported resource.
	var absolute := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(absolute):
		var file := FileAccess.open(absolute, FileAccess.READ)
		if file != null and file.get_length() > 0:
			var image := Image.new()
			if image.load_png_from_buffer(file.get_buffer(file.get_length())) == OK:
				return ImageTexture.create_from_image(image)
	if ResourceLoader.exists(path):
		var resource: Variant = load(path)
		if resource is Texture2D:
			return resource
	pending_reason = "ASSETS PENDING: missing %s" % path
	return null


func _point(value: Variant) -> Vector2:
	if value is Vector2:
		return value
	if not value is Array or (value as Array).size() != 2:
		return Vector2.ZERO
	var array: Array = value
	return Vector2(float(array[0]), float(array[1]))


func _canvas_world_transform(canvas: CanvasItem) -> Transform2D:
	return canvas.get_meta("actor_world_transform", world_transform()) as Transform2D


## Immediate-mode structure bands share the town controller's state machine.
## Collision remains authored in room scenes; these boxes only affect drawing.
func reset_structure_fades() -> void:
	_structure_fades.clear()
	for material: ShaderMaterial in _paired_materials.values():
		material.set_shader_parameter("reveal_weight", 0.0)


func set_layout_id(layout_id: String) -> void:
	if layout_id != _layout_id:
		_layout_id = layout_id
		reset_structure_fades()


func _structure_key(sprite_id: String, feet: Vector2) -> String:
	return sprite_id + "@" + str(feet)


func structure_fade_state(sprite_id: String, feet: Vector2) -> Dictionary:
	return (_structure_fades.get(_structure_key(sprite_id, feet), {}) as Dictionary).duplicate(true)


func structure_fade_report() -> Dictionary:
	return _structure_fades.duplicate(true)


## The world-space detection rect of one whole-object generated piece: its
## authored canvas-local rect translated by the same feet-anchor mapping the
## draw pass uses, so detection matches the sort domain exactly.
func paired_detection_rect_world(sprite_id: String, feet: Vector2) -> Rect2:
	var record: Variant = _generated_sprites.get(sprite_id, null)
	if record == null:
		return Rect2()
	var local: Rect2 = record.occlusion_rect
	return Rect2(feet - (record.anchor as Vector2) + local.position, local.size)


## The material one placed whole-object piece draws through, or null for
## legacy banded structures. Created during advance_structure_fades; the
## presenter attaches it to that drawable's own sort view.
func paired_reveal_material(sprite_id: String, feet: Vector2) -> Material:
	return _paired_materials.get(_structure_key(sprite_id, feet), null)


func _paired_material(key: String, sprite_id: String) -> ShaderMaterial:
	var existing: Variant = _paired_materials.get(key, null)
	if existing is ShaderMaterial:
		return existing
	var record: Dictionary = _generated_sprites.get(sprite_id, {})
	var material := ShaderMaterial.new()
	material.shader = PairedReveal.RevealShader
	material.set_shader_parameter("revealed_texture", record.get("variant", null))
	material.set_shader_parameter("reveal_weight", 0.0)
	_paired_materials[key] = material
	return material


## Generated world pack: optional whole-object opaque/transparent pairs.
## An ABSENT pack file is the historical-fixture flag: the legacy atlas draws
## exactly as before. A PRESENT pack claims the authority — the arena section
## must be complete and every family sprite must carry status "packed" and
## validate, or the whole load fails closed (never a silent half-new scene
## and never a silent fallback while the pack is still assembling).
func _load_generated_world() -> bool:
	_generated_sprites.clear()
	_paired_materials.clear()
	if not FileAccess.file_exists(generated_world_path):
		return true
	var pack := _read_json(generated_world_path)
	if pack.is_empty():
		return false
	var grounds: Variant = pack.get("grounds", null)
	var ground_entry: Variant = (grounds as Dictionary).get(GENERATED_GROUND_ID, null) if grounds is Dictionary else null
	if not ground_entry is Dictionary or String((ground_entry as Dictionary).get("status", "")) != "packed":
		pending_reason = "ASSETS PENDING: generated arena ground is not packed"
		return false
	if ground_entry is Dictionary and String((ground_entry as Dictionary).get("status", "")) == "packed":
		var ground := _load_texture(String((ground_entry as Dictionary).get("opaque_path", "")))
		if ground == null:
			return false
		if ground.get_size() != WORLD_SIZE:
			pending_reason = "ASSETS PENDING: generated ground must be %dx%d" % [int(WORLD_SIZE.x), int(WORLD_SIZE.y)]
			return false
		_textures[APPROVED_GROUND_KEY] = ground
	var sections: Variant = pack.get("sections", null)
	var arena_section: Variant = (sections as Dictionary).get("arena", {}) if sections is Dictionary else {}
	if not arena_section is Dictionary or not bool((arena_section as Dictionary).get("complete", false)):
		pending_reason = "ASSETS PENDING: generated pack present but arena section is not complete"
		return false
	var assets: Variant = pack.get("assets", null)
	if not assets is Dictionary:
		pending_reason = "ASSETS PENDING: generated pack lacks assets"
		return false
	for asset_id: String in GENERATED_SPRITE_IDS.keys():
		var raw: Variant = (assets as Dictionary).get(asset_id, null)
		if not raw is Dictionary or String((raw as Dictionary).get("status", "")) != "packed":
			pending_reason = "ASSETS PENDING: generated asset %s is not packed" % asset_id
			return false
		var sprite_id := String(GENERATED_SPRITE_IDS[asset_id])
		var record := _normalize_generated_sprite(sprite_id, raw as Dictionary)
		if record.is_empty():
			return false
		_generated_sprites[sprite_id] = record
		_textures[record.texture_key] = record.opaque
		_sprites[sprite_id] = {"texture": record.texture_key,
			"rect": Rect2(Vector2.ZERO, record.canvas), "anchor": record.anchor}
	return true


## One generated sprite entry: canvas/anchor/rects plus the opaque and
## transparent texture pair. The detection rect must contain the opaque
## texture's MEASURED occupied bounds grown by DETECTION_GROW — the pack's
## own declared occupied_rect is metadata; the texture is the truth.
func _normalize_generated_sprite(sprite_id: String, raw: Dictionary) -> Dictionary:
	var canvas := _point(raw.get("canvas", []))
	var anchor := _point(raw.get("anchor", []))
	var occupied := _rect_of(raw.get("occupied_rect", []))
	var occlusion := _rect_of(raw.get("occlusion_rect", []))
	if canvas.x <= 0.0 or canvas.y <= 0.0 or not anchor.is_finite():
		pending_reason = "ASSETS PENDING: %s malformed canvas or anchor" % sprite_id
		return {}
	var opaque := _load_texture(String(raw.get("opaque_path", "")))
	var variant := _load_texture(String(raw.get("transparent_path", "")))
	if opaque == null or variant == null:
		return {}
	if opaque.get_size() != canvas or variant.get_size() != canvas:
		pending_reason = "ASSETS PENDING: %s pair must share the authored canvas" % sprite_id
		return {}
	if PairedReveal.detection_rect_error(occlusion, opaque.get_image()) != "":
		pending_reason = "ASSETS PENDING: %s detection rect must contain occupied.grow(%d)" % [sprite_id, int(PairedReveal.DETECTION_GROW)]
		return {}
	var variant_image := variant.get_image()
	var variant_max_alpha := 0.0
	for y: int in variant_image.get_height():
		for x: int in variant_image.get_width():
			variant_max_alpha = maxf(variant_max_alpha, variant_image.get_pixel(x, y).a)
	return {"texture_key": "generated/" + sprite_id, "opaque": opaque, "variant": variant,
		"canvas": canvas, "anchor": anchor, "occupied_rect": occupied, "occlusion_rect": occlusion,
		"variant_max_alpha": variant_max_alpha}


func _rect_of(value: Variant) -> Rect2:
	if value is Rect2:
		return value
	if not value is Array or (value as Array).size() != 4:
		return Rect2()
	var array: Array = value
	for component: Variant in array:
		if not (component is float or component is int) or not is_finite(float(component)):
			return Rect2()
	return Rect2(float(array[0]), float(array[1]), float(array[2]), float(array[3]))


func structure_geometry(sprite_id: String, feet: Vector2) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if _generated_sprites.has(sprite_id):
		var record: Dictionary = _generated_sprites[sprite_id]
		result.append({"part": "whole", "source": Rect2(Vector2.ZERO, record.canvas),
			"dest": Rect2((feet - (record.anchor as Vector2)).round(), record.canvas),
			"alpha": 1.0, "texture": String(record.texture_key)})
		return result
	var alpha := float(structure_fade_state(sprite_id, feet).get("alpha", 1.0))
	var ids: Array = ["tower.upper", "tower.base"] if sprite_id == "tower" else [sprite_id]
	for id: String in ids:
		var meta := sprite(id)
		if meta.is_empty():
			continue
		var rect: Rect2 = meta.rect
		var regions: Array[Rect2] = []
		if sprite_id == "tower":
			regions.append(_region_of(meta))
		else:
			regions.append(Rect2(rect.position, Vector2(rect.size.x, STRUCTURE_BASE_ROW)))
			regions.append(Rect2(rect.position + Vector2(0, STRUCTURE_BASE_ROW), Vector2(rect.size.x, rect.size.y - STRUCTURE_BASE_ROW)))
		for index in regions.size():
			var upper := id == "tower.upper" if sprite_id == "tower" else index == 0
			var region: Rect2 = regions[index]
			var dest := Rect2((feet - Vector2(meta.anchor) + region.position - rect.position).round(), region.size)
			result.append({"part": "upper" if upper else "base", "source": region, "dest": dest,
				"alpha": alpha if upper else 1.0, "texture": String(meta.texture)})
	return result


func structure_upper_volume(sprite_id: String, feet: Vector2) -> Rect2:
	for band: Dictionary in structure_geometry(sprite_id, feet):
		if band.part == "upper":
			return (band.dest as Rect2).grow(STRUCTURE_VOLUME_PAD)
	return Rect2()


func advance_structure_fades(drawables: Array, subjects: Array, delta: float) -> void:
	var next: Dictionary = {}
	for drawable: Dictionary in drawables:
		if drawable.kind not in ["structure", "tower"]:
			continue
		var id := "tower" if drawable.kind == "tower" else String(drawable.sprite)
		var feet: Vector2 = drawable.world
		var key := _structure_key(id, feet)
		if _generated_sprites.has(id):
			## Whole-object pair: one authored detection rect, one eased
			## reveal weight, no band split. The rect stays report-only
			## geometry; collision remains authored in the room scene.
			var rect := paired_detection_rect_world(id, feet)
			var state := PairedReveal.advance_state(rect, drawable, subjects, _structure_fades.get(key, {}), delta)
			var material := _paired_material(key, id)
			material.set_shader_parameter("reveal_weight", state.weight)
			state.merge({"policy": PairedReveal.POLICY, "sprite_id": id, "feet_world": feet,
				"part": drawable.duplicate(), "volume": rect, "material": material,
				"alpha": lerpf(1.0, float(_generated_sprites[id].variant_max_alpha), float(state.weight)),
				"variant_max_alpha": float(_generated_sprites[id].variant_max_alpha),
				"transition_seconds": PairedReveal.TRANSITION_SECONDS})
			next[key] = state
			continue
		var box := structure_upper_volume(id, feet)
		if not box.has_area():
			continue
		var volume := {"type": "polygon", "points": PackedVector2Array([box.position,
			Vector2(box.end.x, box.position.y), box.end, Vector2(box.position.x, box.end.y)])}
		var state := PrimitiveFade.advance_state([volume], drawable, subjects, _structure_fades.get(key, {}), delta)
		state.merge({"policy": PrimitiveFade.POLICY, "sprite_id": id, "feet_world": feet,
			"part": drawable.duplicate(), "volume": box, "base_alpha": 1.0,
			"faded_alpha": PrimitiveFade.FADED_ALPHA, "transition_seconds": PrimitiveFade.TRANSITION_SECONDS})
		next[key] = state
	_structure_fades = next
