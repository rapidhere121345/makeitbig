class_name HamletConceptView
extends Node2D
## Formal hub: one continuous, actor-free town image at normalized layout points.
## Dynamic ranger/resident cells share world units with hand-traced, feet-sorted
## image polygons. Explicit configure(atlas, layout) fixtures retain the legacy
## 640x360 sprite/split-row contract. Missing art remains a reported dependency.

const NATIVE_VIEW := Vector2i(640, 360)
## Shared ranger action reader: the same atlas, framing and state mapping the
## arena and the tutorial use. The approved four-way static cells stay the hub's
## explicit fallback while the action atlas is pending or broken.
const RangerAnimationScript = preload("res://src/presentation/ranger_animation.gd")
## Published life package reader: the resident work cycles and the socket
## effects. The approved static residents stay the fallback while it is pending.
const HamletLifeAnimationScript = preload("res://src/presentation/hamlet_life_animation.gd")
const HamletTownLayerScript = preload("res://src/presentation/hamlet_town_layer.gd")
const HamletCollisionScript = preload("res://src/presentation/hamlet_collision.gd")
const ScenePatchScript = preload("res://src/presentation/hamlet_scene_patch.gd")
const AtmosphereScript = preload("res://src/presentation/scene_atmosphere.gd")
const AtmosphereLayerScript = preload("res://src/presentation/scene_atmosphere_layer.gd")
const ATMOSPHERE_PRESET := "hamlet"
const ATMOSPHERE_BOUNDS := Rect2(Vector2.ZERO, GROUND_BAND_SIZE)
const HEARTH_LIGHT_FEET := Vector2(504.0, 371.0)
const FORGE_LIGHT_FEET := Vector2(792.0, 412.0)
const DESIGN_TO_WORLD := 0.5
const DEFAULT_WORLD_SIZE := Vector2(1024.0, 640.0)
const DEFAULT_HERO_START := Vector2(500.0, 402.0)
const DEFAULT_HERO_FACING := "south"
const HERO_SPEED := 96.0
const WORLD_MARGIN := 20.0
const HOTSPOT := 72.0
const SPLIT_FADE_ALPHA := 0.52
## Conservative cutaway: a foreground band that covers the avatar keeps its
## authored alpha everywhere except the avatar's own overlap window, where the
## whole stack is capped so the avatar's real source pixels survive the 0.20
## per-channel visibility gate instead of being washed out by a whole-building
## fade. The window is the avatar cell grown by CUTAWAY_WINDOW_PAD so no drawn
## avatar pixel ever sits on the window edge.
const CUTAWAY_TOTAL_OPACITY := 0.16
const CUTAWAY_WINDOW_PAD := 2.0
## Index of the window inside the five tiling pieces (four solid bands first).
const CUTAWAY_WINDOW_INDEX := 4
const DEFAULT_GROUND_ID := "scene.ground"
const GROUND_SPRITE_FALLBACK := "hamlet.ground"
const GROUND_BAND_SIZE := Vector2(1024.0, 640.0)

const LAYER_GROUND := "ground"
const LAYER_OBJECT := "object"
const LAYER_NPC := "npc"
const LAYERS := [LAYER_GROUND, LAYER_OBJECT, LAYER_NPC]
## A socket sprite joins _sprite_nodes under its own prefix, so the shared
## cutaway already sees it and no second registry has to be kept in step.
const LIFE_NODE_PREFIX := "life."

const FACINGS := ["south", "north", "west", "east"]
const FACING_IDS := {
	"south": "ranger.south.idle",
	"north": "ranger.north.idle",
	"west": "ranger.west.idle",
	"east": "ranger.east.idle",
}
const INTERACTION_IDS := ["contract", "loadout", "forge", "training", "proxy"]

const DEFAULT_ATLAS_PATH := "res://art/production/p1/hamlet_style_r13/atlas.json"
const DEFAULT_LAYOUT_PATH := "res://art/production/p1/hamlet_town/layout.json"
const LEGACY_LAYOUT_PATH := "res://art/production/p1/hamlet_framing_v03/layout.json"
const SCENE_ATLAS_PATH := "res://art/production/p1/scene_rework_v01/atlas.json"
const GROUND_ATLAS_PATH := "res://art/production/p1/ground_refine_v01/atlas.json"
## R13 keeps the warmer path-and-commons ground direction and adds only a
## peripheral environmental frame; current framing and facility layout stay put.
const SURFACE_ATLAS_PATH := "res://art/production/p1/hamlet_ground_r14/atlas.json"
const ATLAS_SOURCES := [
	{"key": "surface", "path": SURFACE_ATLAS_PATH},
	{"key": "hamlet", "path": DEFAULT_ATLAS_PATH},
	{"key": "scene", "path": SCENE_ATLAS_PATH},
	{"key": "ground", "path": GROUND_ATLAS_PATH},
]
const SPRITE_ORDER := ["surface", "hamlet", "scene", "ground"]
const GROUND_ORDER := ["surface", "hamlet", "ground", "scene"]

const SCENE_COLOR := Color("2a3643")
const SKIRT_COLOR := Color("1a222b")

## Placement ids that drive the hub entries when the layout publishes none of
## its own. Legacy design-space fallbacks: the old 1280x720 base hub table
## halved into the 640x360 world.
const FALLBACK_ENTRIES := {
	"contract": {"feet": Vector2(320.0, 152.5), "radius": 94.0, "order": 0, "locked": false, "label": "契约台"},
	"loadout": {"feet": Vector2(196.0, 187.0), "radius": 92.0, "order": 1, "locked": false, "label": "装备 / 符文页"},
	"forge": {"feet": Vector2(444.0, 187.0), "radius": 92.0, "order": 2, "locked": false, "label": "律筹锻造台"},
	"training": {"feet": Vector2(437.5, 295.5), "radius": 96.0, "order": 3, "locked": false, "label": "训练木桩与战报"},
	"proxy": {"feet": Vector2(202.5, 291.5), "radius": 96.0, "order": 4, "locked": true, "label": "代理舱"},
}

var world_root: Node2D
var field_layer: Node2D
var ground_base_layer: Node2D
var ground_layer: Node2D
var town_layer: HamletTownLayerScript
var object_lower_layer: Node2D
var actor_layer: Node2D
var world_viewport: SubViewport
var world_display: TextureRect

var _atlases: Dictionary = {}
var _sprites: Dictionary = {}
var _texture_meta: Dictionary = {}
var _textures: Dictionary = {}
var _hit_images: Dictionary = {}
var _pending_reasons: Array[String] = []
var _texture_reasons: Array[String] = []
var _ground_note := ""
var _pending_logged := false
var _ground_logged := false

var _layout: Dictionary = {}
var _layout_loaded := false
var _feature_entries: Array[Dictionary] = []
var _collision := HamletCollisionScript.new()
var _sprite_nodes: Dictionary = {}
var _fade_targets: Array[Dictionary] = []
## Life art state: the resident and socket sprites the published package placed,
## plus the reasons this view itself refused one. A missing life package never
## reaches is_ready(), so the hub's established fixtures keep their answer.
var life_animation
var _life_residents: Array[Dictionary] = []
var _life_effects: Array[Dictionary] = []
var _life_pending: Array[String] = []
## Lazy five-piece cutter per foreground sprite: created only for a sprite the
## avatar actually stands behind, hidden again the moment it is clear.
var _cutaway_cache: Dictionary = {}

var _world_size := DEFAULT_WORLD_SIZE
var _view_size := Vector2(NATIVE_VIEW)
var _display_size := Vector2(1280, 720)
var _scene_texture: Texture2D
var _scene_patches: Array[Node2D] = []
var _world_bounds := Rect2(Vector2(WORLD_MARGIN, WORLD_MARGIN), DEFAULT_WORLD_SIZE - Vector2(WORLD_MARGIN * 2.0, WORLD_MARGIN * 2.0))
var _hero_position := DEFAULT_HERO_START
## The follow anchor leaves more visible street ahead of the ranger. World and
## view dimensions are separate: resizing a window never reveals the whole town.
## Old layouts/fixtures retain their centre anchor.
var _hero_screen_anchor := Vector2(NATIVE_VIEW) * 0.5
var _hero_facing := DEFAULT_HERO_FACING
var _walk_time := 0.0
var _nearby_feature_id := ""
var _world_dirty := true
var _walking := false
var _destination_marker: Polygon2D
var _destination_id := ""

var _hero_sprite: Sprite2D
var _hero_shadow: Polygon2D
var _atmosphere_base: AtmosphereLayerScript
var _atmosphere_light: AtmosphereLayerScript
var _atmosphere_fore: AtmosphereLayerScript
## Action reader and its presentation clocks. The hub has no combat, so only the
## walk/idle cycle ever runs here, on the hub's own clock.
var ranger_animation
var _idle_time := 0.0
var _hero_frame_key := ""


func _ready() -> void:
	process_priority = -10
	_build_layers()
	if ranger_animation == null:
		ranger_animation = RangerAnimationScript.new()
	if life_animation == null:
		life_animation = HamletLifeAnimationScript.new()
	set_process(true)


## ------------------------------------------------------------------- loading

func load_default_assets() -> bool:
	## Reads the published pair from disk. Missing or half-authored files leave
	## the view in its pending state, which the screen renders as plain ground.
	_atlases.clear()
	_pending_reasons.clear()
	_texture_reasons.clear()
	_texture_meta.clear()
	_load_atlas_sources()
	if ranger_animation == null:
		ranger_animation = RangerAnimationScript.new()
	if life_animation == null:
		life_animation = HamletLifeAnimationScript.new()
	life_animation.load_default_assets()
	var layout_file := FileAccess.open(DEFAULT_LAYOUT_PATH, FileAccess.READ)
	if layout_file == null:
		_pending_reasons.append("layout missing at %s" % DEFAULT_LAYOUT_PATH)
		_layout = {}
		_layout_loaded = false
	else:
		var parsed: Variant = JSON.parse_string(layout_file.get_as_text())
		layout_file.close()
		if parsed is Dictionary:
			_layout = parsed
			_layout_loaded = true
		else:
			_pending_reasons.append("layout.json is not a JSON object")
			_layout = {}
			_layout_loaded = false
	_configure(_atlases, _layout)
	return is_ready()


func configure(atlas: Dictionary, layout: Dictionary) -> void:
	## Fixture entry point: both contracts already in memory, nothing else read.
	_atlases = {"hamlet": atlas.duplicate(true)}
	_pending_reasons.clear()
	_texture_reasons.clear()
	_ground_note = ""
	_sprites.clear()
	_texture_meta.clear()
	_textures.clear()
	_pending_logged = false
	_layout = layout.duplicate(true)
	_layout_loaded = true
	_life_clear()
	_configure(_atlases, _layout)


func is_ready() -> bool:
	return _pending_reasons.is_empty() and not _sprites.is_empty() and not _layout.is_empty()


func pending_reasons() -> Array[String]:
	var result := _pending_reasons.duplicate()
	result.append_array(_texture_reasons)
	return result


func texture_reasons() -> Array[String]:
	## A PNG that cannot be decoded costs one invisible sprite, not the whole
	## layout: the rest of the approved arrangement still renders.
	return _texture_reasons.duplicate()


func _load_atlas_sources() -> void:
	for source: Dictionary in ATLAS_SOURCES:
		# Formal mode needs only dynamic character cells from the old package.
		if String(source.key) != "hamlet":
			continue
		var key := String(source.key)
		var path := String(source.path)
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			continue
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		file.close()
		if parsed is Dictionary:
			_atlases[key] = parsed


func _configure(atlases: Dictionary, layout: Dictionary) -> void:
	_hit_images.clear()
	if world_root == null:
		_build_layers()
	_sprites = _collect_sprites(atlases)
	_textures = _load_textures()
	_world_size = _point(layout.get("world", layout.get("world_size", [])), DEFAULT_WORLD_SIZE, _world_size)
	_scene_texture = null
	_view_size = _point(layout.get("view_size", []), Vector2(NATIVE_VIEW))
	world_viewport.size = Vector2i(_view_size)
	set_world_scale(2, _display_size)
	var scene_path := String(layout.get("scene_texture", ""))
	if not scene_path.is_empty():
		if ResourceLoader.exists(scene_path):
			_scene_texture = ResourceLoader.load(scene_path) as Texture2D
		if _scene_texture == null:
			_scene_texture = _read_texture_raw(scene_path)
		if _scene_texture == null:
			_pending_reasons.append("town scene missing or undecodable at %s" % scene_path)
	_world_bounds = Rect2(
		Vector2(WORLD_MARGIN, WORLD_MARGIN),
		(_world_size - Vector2(WORLD_MARGIN * 2.0, WORLD_MARGIN * 2.0)).max(Vector2(1.0, 1.0))
	)
	var start := _point(layout.get("hero_start", []), DEFAULT_HERO_START, DEFAULT_HERO_START)
	if layout.has("hero_start_uv"):
		start = _point(layout.hero_start_uv, Vector2.ZERO) * _world_size
	_hero_position = _clamped(start)
	_hero_screen_anchor = _view_size * 0.5
	var declared_anchor: Variant = layout.get("hero_screen_anchor", null)
	if declared_anchor != null:
		if _integer_list(declared_anchor, 2):
			var anchor := _point(declared_anchor, _hero_screen_anchor)
			if Rect2(Vector2.ZERO, _view_size).has_point(anchor):
				_hero_screen_anchor = anchor
			else:
				_pending_reasons.append("hero_screen_anchor must be inside the native viewport")
		else:
			_pending_reasons.append("hero_screen_anchor must be two JSON integers")
	_hero_facing = DEFAULT_HERO_FACING
	_walk_time = 0.0
	_nearby_feature_id = ""
	_feature_entries = _build_feature_entries(layout)
	_collision.configure(layout)
	if town_layer != null:
		town_layer.configure(_feature_entries, _world_size, layout, _scene_texture)
	# The full scene already owns its lighting and terrain. Keep the previous
	# atmosphere and sockets only for explicit legacy fixtures.
	for atmosphere: Node2D in [_atmosphere_base, _atmosphere_light, _atmosphere_fore]:
		atmosphere.visible = not _scene_mode()
	_rebuild_world()
	_world_dirty = true


func _collect_sprites(atlases: Dictionary) -> Dictionary:
	var result := {}
	for group: String in SPRITE_ORDER:
		var atlas: Variant = atlases.get(group, null)
		if not atlas is Dictionary:
			continue
		var data := atlas as Dictionary
		if not _integer_list(data.get("native_view", null), 2):
			_pending_reasons.append("atlas %s native_view must be two JSON integers" % group)
		var texture_meta := _atlas_textures(data)
		var declared: Variant = data.get("sprites", null)
		if not declared is Dictionary:
			_pending_reasons.append("atlas %s sprites must be a dictionary" % group)
			continue
		for raw_id: Variant in (declared as Dictionary).keys():
			var sprite_id := String(raw_id)
			if result.has(sprite_id):
				continue
			var entry: Variant = (declared as Dictionary)[raw_id]
			if not entry is Dictionary:
				_pending_reasons.append("atlas %s sprite %s must be a dictionary" % [group, sprite_id])
				continue
			var accepted := _accept_sprite(group, sprite_id, entry as Dictionary, texture_meta)
			if accepted:
				result[sprite_id] = accepted
	return result


func _atlas_textures(atlas: Dictionary) -> Dictionary:
	var result := {}
	var declared: Variant = atlas.get("textures", null)
	if not declared is Dictionary:
		return result
	for raw_key: Variant in (declared as Dictionary).keys():
		var entry: Variant = (declared as Dictionary)[raw_key]
		if not entry is Dictionary:
			continue
		var metadata := entry as Dictionary
		result[String(raw_key)] = {
			"path": String(metadata.get("path", "")),
			"width": int(metadata.get("width", 0)),
			"height": int(metadata.get("height", 0)),
		}
	return result


func _accept_sprite(group: String, sprite_id: String, entry: Dictionary, texture_meta: Dictionary) -> Dictionary:
	var rect: Variant = entry.get("rect", null)
	var anchor: Variant = entry.get("anchor", null)
	if not _integer_list(rect, 4) or int((rect as Array)[2]) <= 0 or int((rect as Array)[3]) <= 0:
		_pending_reasons.append("%s sprite %s rect must be four JSON integers with a positive size" % [group, sprite_id])
		return {}
	if not _integer_list(anchor, 2) or int((anchor as Array)[0]) < 0 or int((anchor as Array)[1]) < 0:
		## A composite building declares its feet offset as a pair of non-negative
		## integers; that offset may reach past its own cell, exactly like
		## hamlet.hearth anchor [160,212] on a 320x224 cell.
		_pending_reasons.append("%s sprite %s anchor must be two non-negative JSON integers" % [group, sprite_id])
		return {}
	var texture_key := String(entry.get("texture", ""))
	var metadata: Variant = texture_meta.get(texture_key, null)
	if not metadata is Dictionary:
		_pending_reasons.append("%s sprite %s references unknown texture %s" % [group, sprite_id, texture_key])
		return {}
	var qualified := "%s:%s" % [group, texture_key]
	_texture_meta[qualified] = (metadata as Dictionary).duplicate(true)
	return {
		"rect": rect,
		"anchor": anchor,
		"texture": qualified,
	}


func _load_textures() -> Dictionary:
	## A shipped build keeps only the imported texture, so ResourceLoader is asked
	## first; the raw PNG decode is the same-machine fallback for a tree whose
	## import step has not run yet. Both paths check the declared size.
	var result := {}
	for texture_key: String in _texture_meta.keys():
		var metadata := _texture_meta[texture_key] as Dictionary
		var path := String(metadata.get("path", ""))
		var expected := Vector2i(int(metadata.get("width", 0)), int(metadata.get("height", 0)))
		if path.is_empty() or expected.x <= 0 or expected.y <= 0:
			_texture_reasons.append("texture %s needs a path and a positive width/height" % texture_key)
			continue
		var imported: Texture2D = null
		if ResourceLoader.exists(path):
			imported = ResourceLoader.load(path) as Texture2D
		if imported != null:
			if Vector2i(imported.get_size()) != expected:
				_texture_reasons.append("texture %s is %s, atlas declares %s" % [texture_key, imported.get_size(), expected])
				continue
			result[texture_key] = imported
			continue
		if not FileAccess.file_exists(path):
			_texture_reasons.append("texture %s missing at %s" % [texture_key, path])
			continue
		var decoded := _decode_png_path(path)
		if decoded == null:
			_texture_reasons.append("texture %s is not a decodable PNG" % texture_key)
			continue
		if decoded.get_size() != expected:
			_texture_reasons.append("texture %s is %s, atlas declares %s" % [texture_key, decoded.get_size(), expected])
			continue
		result[texture_key] = ImageTexture.create_from_image(decoded)
	return result


func _decode_png_path(path: String) -> Image:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var bytes := file.get_buffer(file.get_length())
	file.close()
	return _decode_png(bytes)


func _read_texture_raw(path: String) -> Texture2D:
	var decoded := _decode_png_path(path)
	return ImageTexture.create_from_image(decoded) if decoded != null else null


func _decode_png(bytes: PackedByteArray) -> Image:
	## The same raw decode the concept preview uses, with the same instance call:
	## the runtime stays free of the editor import step and of any dependency on
	## tools/ or build/ resources.
	var image := Image.new()
	if image.load_png_from_buffer(bytes) != OK:
		return null
	return image


func _build_feature_entries(layout: Dictionary) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var seen := {}
	for raw: Variant in layout.get("placements", []) as Array:
		if not raw is Dictionary:
			continue
		var item := raw as Dictionary
		var feature_id := String(item.get("interaction", ""))
		if not INTERACTION_IDS.has(feature_id) or seen.has(feature_id):
			continue
		seen[feature_id] = true
		entries.append(_entry_from_placement(feature_id, item))
	for feature_id: String in (FALLBACK_ENTRIES.keys() if layout.is_empty() else []):
		if seen.has(feature_id):
			continue
		seen[feature_id] = true
		entries.append(_entry_from_fallback(feature_id))
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.order) < int(b.order))
	return entries


func _entry_from_placement(feature_id: String, item: Dictionary) -> Dictionary:
	var fallback := _fallback(feature_id)
	var label := String(item.get("label", "")).strip_edges()
	if label.is_empty():
		label = String(fallback.get("label", feature_id))
	return {
		"id": feature_id,
		"label": label,
		"feet": _feet(item),
		"radius": float(item.get("radius", maxf(HOTSPOT, _sprite_hotspot_radius(String(item.get("sprite", "")))))),
		"order": int(fallback.get("order", 99)),
		"locked": bool(fallback.get("locked", false)),
		"sprite": String(item.get("sprite", "")),
		"from_layout": true,
	}


func _entry_from_fallback(feature_id: String) -> Dictionary:
	var fallback := _fallback(feature_id)
	return {
		"id": feature_id,
		"label": String(fallback.get("label", feature_id)),
		"feet": fallback.get("feet", DEFAULT_HERO_START) as Vector2,
		"radius": float(fallback.get("radius", HOTSPOT)),
		"order": int(fallback.get("order", 99)),
		"locked": bool(fallback.get("locked", false)),
		"sprite": "",
		"from_layout": false,
	}


func _fallback(feature_id: String) -> Dictionary:
	var raw: Variant = FALLBACK_ENTRIES.get(feature_id, null)
	return raw as Dictionary if raw is Dictionary else {}


## ------------------------------------------------------------------- travel

func move_hero(direction: Vector2, delta: float) -> void:
	if delta <= 0.0:
		return
	var movement := direction.limit_length(1.0)
	if movement.length_squared() > 0.0001:
		## Continuous float integration: identical distance covers 30, 60 and
		## 144 Hz, and a short high-refresh step never rounds away to zero.
		_hero_position = _collision.move(_hero_position, movement.normalized() * HERO_SPEED * delta, _world_bounds)
		_update_facing(movement)
		_walk_time += delta
		_walking = true
	else:
		_walking = false
		_walk_time = 0.0
	_world_dirty = true
	_update_hero_visual()
	_update_nearby()
	_update_split_fade()
	_update_cutaway()


func teleport_hero(point: Vector2) -> void:
	## Explicit positioning bypasses footprints, preserving occlusion fixtures.
	_hero_position = _clamped(point)
	_walking = false
	_walk_time = 0.0
	_world_dirty = true
	_update_hero_visual()
	_update_nearby()
	_update_split_fade()
	_update_cutaway()


func hero_world_position() -> Vector2:
	return _hero_position


func hero_snapped_position() -> Vector2i:
	return Vector2i(floori(_hero_position.x), floori(_hero_position.y))


func hero_facing() -> String:
	return _hero_facing


func world_size() -> Vector2:
	return _world_size


func world_bounds() -> Rect2:
	return _world_bounds


func camera_world_offset() -> Vector2:
	var offset := Vector2(hero_snapped_position()) - _hero_screen_anchor
	if _bounded_camera():
		return offset.clamp(Vector2.ZERO, (_world_size - _view_size).max(Vector2.ZERO))
	return offset


func _bounded_camera() -> bool:
	return bool((_layout.get("collision", {}) as Dictionary).get("bounded_camera", false))


func hero_screen_anchor() -> Vector2:
	return _hero_screen_anchor


func travel_snapshot() -> Dictionary:
	return {"position": _hero_position, "facing": _hero_facing, "destination": _destination_id}


func restore_travel(snapshot: Dictionary) -> void:
	if snapshot.get("position") is Vector2:
		teleport_hero(snapshot.position)
	if String(snapshot.get("facing", "")) in FACINGS:
		_hero_facing = String(snapshot.facing)
	set_destination(String(snapshot.get("destination", "contract")))
	_update_hero_visual()
	_sync_camera()


func set_destination(feature_id: String) -> void:
	var entry := entry_for(feature_id)
	_destination_id = feature_id if not entry.is_empty() else ""
	if _destination_marker == null:
		_destination_marker = Polygon2D.new()
		_destination_marker.name = "TownDestinationMarker"
		_destination_marker.polygon = PackedVector2Array([Vector2(-6, -55), Vector2(6, -55), Vector2(0, -45)])
		_destination_marker.color = Color("e5b67c")
		_destination_marker.z_index = 10
		world_root.add_child(_destination_marker)
	_destination_marker.visible = not entry.is_empty()
	if not entry.is_empty(): _destination_marker.position = entry.feet


func _update_facing(direction: Vector2) -> void:
	if absf(direction.x) > absf(direction.y):
		_hero_facing = "east" if direction.x > 0.0 else "west"
	else:
		_hero_facing = "south" if direction.y > 0.0 else "north"


func _clamped(candidate: Vector2) -> Vector2:
	return candidate.clamp(_world_bounds.position, _world_bounds.end)


## -------------------------------------------------------------- interaction

func feature_entries() -> Array[Dictionary]:
	return _feature_entries.duplicate(true)


func entry_for(feature_id: String) -> Dictionary:
	for entry: Dictionary in _feature_entries:
		if String(entry.id) == feature_id:
			return entry.duplicate(true)
	return {}


func nearby_feature_id() -> String:
	return _nearby_feature_id


func nearby_label() -> String:
	var entry := entry_for(_nearby_feature_id)
	return String(entry.get("label", ""))


func _update_nearby() -> void:
	## Only the published interaction routes take part, so the prompt never offers
	## a stand the player cannot open.
	var nearest_id := ""
	var nearest_gap := INF
	for entry: Dictionary in _feature_entries:
		var feet := entry.get("feet", Vector2.ZERO) as Vector2
		if _hero_position.distance_to(feet) > float(entry.get("radius", HOTSPOT)):
			continue
		var gap := _hero_position.distance_squared_to(feet)
		if gap < nearest_gap:
			nearest_gap = gap
			nearest_id = String(entry.get("id", ""))
	_nearby_feature_id = nearest_id


func hit_test(world_point: Vector2) -> String:
	## Visible art wins over another station's generous proximity radius. Among
	## overlapping opaque pixels use the foreground feet order; transparent atlas
	## padding never steals a click. Only empty ground falls back to nearest feet.
	var drawn_id := ""
	var front_y := -INF
	var nearest_id := ""
	var nearest_distance := INF
	for entry: Dictionary in _feature_entries:
		var feet := entry.get("feet", Vector2.ZERO) as Vector2
		var radius := float(entry.get("radius", HOTSPOT))
		var distance := world_point.distance_squared_to(feet)
		if distance <= radius * radius and distance < nearest_distance:
			nearest_distance = distance
			nearest_id = String(entry.get("id", ""))
		if feet.y >= front_y and _opaque_station_pixel(entry, world_point):
			front_y = feet.y
			drawn_id = String(entry.get("id", ""))
	return drawn_id if not drawn_id.is_empty() else nearest_id


func _opaque_station_pixel(entry: Dictionary, world_point: Vector2) -> bool:
	if _scene_mode():
		for patch: Dictionary in _layout.get("foreground", []):
			if String(patch.get("interaction", "")) == String(entry.id) and Geometry2D.is_point_in_polygon(world_point, _scene_polygon(patch)):
				return _scene_texture != null
		return false
	var cell := _drawn_rect(entry)
	if not cell.has_point(world_point):
		return false
	var id := String(entry.get("sprite", ""))
	var metadata := _sprite_entry(id)
	var texture := metadata.get("texture", null) as Texture2D
	if texture == null:
		return false
	if not _hit_images.has(id):
		_hit_images[id] = texture.get_image()
	var pixels := _hit_images[id] as Image
	if pixels == null or pixels.is_empty():
		return false
	var rect: Array = metadata.get("rect", [])
	var source := Vector2i((world_point - cell.position).floor()) + Vector2i(int(rect[0]), int(rect[1]))
	return Rect2i(Vector2i.ZERO, pixels.get_size()).has_point(source) and pixels.get_pixelv(source).a > 0.0


func world_point_at_design(design_point: Vector2, canvas_position: Vector2, canvas_scale: Vector2) -> Vector2:
	## The hub keeps design coordinates for its host API: 1280x720 design space,
	## 640x360 logical world, then the follow camera is taken back off so the
	## result is a world point the renderer can hit-test.
	if canvas_scale.x == 0.0 or canvas_scale.y == 0.0:
		return Vector2.ZERO
	var logical := world_display.get_global_transform_with_canvas().affine_inverse() * design_point
	return logical + camera_world_offset()


func design_point_for_world(world_point: Vector2, canvas_position: Vector2, canvas_scale: Vector2) -> Vector2:
	var logical := world_point - camera_world_offset()
	return world_display.get_global_transform_with_canvas() * logical


func _drawn_rect(entry: Dictionary) -> Rect2:
	## The visual cell of a station: its own rect placed on its own anchor. The
	## walkable footprint for pathing is smaller and lives with the layout wiring.
	var metadata := _sprite_entry(String(entry.get("sprite", "")))
	if metadata.is_empty():
		return Rect2()
	var rect := metadata.get("rect", []) as Array
	var anchor := metadata.get("anchor", []) as Array
	if rect.size() != 4 or anchor.size() != 2:
		return Rect2()
	var feet := entry.get("feet", Vector2.ZERO) as Vector2
	return Rect2(feet - Vector2(float(anchor[0]), float(anchor[1])), Vector2(float(rect[2]), float(rect[3])))


## ------------------------------------------------------------------ drawing

func _build_layers() -> void:
	if world_root != null:
		return
	world_viewport = SubViewport.new()
	world_viewport.name = "WorldViewport"
	world_viewport.size = NATIVE_VIEW
	world_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	world_viewport.snap_2d_transforms_to_pixel = true
	world_viewport.snap_2d_vertices_to_pixel = true
	world_viewport.transparent_bg = true
	world_viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	add_child(world_viewport)

	var outside := ColorRect.new()
	outside.name = "OutsideSkirt"
	# The opaque skirt must stay beneath the negative-z world layers.
	outside.z_index = -20
	outside.color = SCENE_COLOR
	outside.set_anchors_preset(Control.PRESET_FULL_RECT)
	outside.mouse_filter = Control.MOUSE_FILTER_IGNORE
	world_viewport.add_child(outside)

	world_root = Node2D.new()
	world_root.name = "WorldRoot"
	world_viewport.add_child(world_root)
	for field: String in ["EdgeSkirt", "Ground", "GroundLayer", "TownConcept", "ObjectLower", "YSort"]:
		var layer: Node2D = HamletTownLayerScript.new() if field == "TownConcept" else Node2D.new()
		layer.name = field
		world_root.add_child(layer)
	field_layer = world_root.get_node("EdgeSkirt") as Node2D
	ground_base_layer = world_root.get_node("Ground") as Node2D
	ground_layer = world_root.get_node("GroundLayer") as Node2D
	town_layer = world_root.get_node("TownConcept") as HamletTownLayerScript
	object_lower_layer = world_root.get_node("ObjectLower") as Node2D
	actor_layer = world_root.get_node("YSort") as Node2D
	actor_layer.y_sort_enabled = true
	field_layer.z_index = -8
	ground_base_layer.z_index = -7
	ground_layer.z_index = -4
	## Paths are part of the floor composition: keep them beneath every authored
	## placement and resident socket, while remaining above the mirrored ground.
	town_layer.z_index = -6
	object_lower_layer.z_index = -3
	_atmosphere_base = AtmosphereLayerScript.new()
	_atmosphere_base.name = "AtmosphereBase"
	_atmosphere_base.preset = ATMOSPHERE_PRESET
	_atmosphere_base.bounds = ATMOSPHERE_BOUNDS
	_atmosphere_base.warm_lights = []
	_atmosphere_base.z_index = -6
	world_root.add_child(_atmosphere_base)
	_atmosphere_light = AtmosphereLayerScript.new()
	_atmosphere_light.name = "AtmosphereLight"
	_atmosphere_light.preset = ATMOSPHERE_PRESET
	_atmosphere_light.bounds = ATMOSPHERE_BOUNDS
	_atmosphere_light.warm_lights = atmosphere_warm_lights()
	_atmosphere_light.additive = true
	_atmosphere_light.light_only = true
	_atmosphere_light.z_index = -5
	world_root.add_child(_atmosphere_light)
	_atmosphere_fore = AtmosphereLayerScript.new()
	_atmosphere_fore.name = "AtmosphereFore"
	_atmosphere_fore.preset = ATMOSPHERE_PRESET
	_atmosphere_fore.bounds = Rect2(Vector2.ZERO, Vector2(NATIVE_VIEW))
	_atmosphere_fore.front = true
	_atmosphere_fore.z_index = 20
	world_viewport.add_child(_atmosphere_fore)

	world_display = TextureRect.new()
	world_display.name = "WorldDisplay"
	world_display.texture = world_viewport.get_texture()
	world_display.stretch_mode = TextureRect.STRETCH_SCALE
	world_display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	world_display.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	world_display.set_anchors_preset(Control.PRESET_TOP_LEFT)
	world_display.custom_minimum_size = Vector2(NATIVE_VIEW)
	world_display.size = Vector2(NATIVE_VIEW)
	world_display.position = Vector2.ZERO
	world_display.scale = Vector2(2.0, 2.0)
	world_display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_attach_display(world_display)


## Fixed sockets at the two published fires. They sit under every stand, so the
## fire art itself and all interactive objects remain untouched and readable.
func atmosphere_warm_lights() -> Array:
	return [
		AtmosphereScript.warm_light(HEARTH_LIGHT_FEET, 53.0, 0.18),
		AtmosphereScript.warm_light(FORGE_LIGHT_FEET, 38.0, 0.15),
	]


func atmosphere_report() -> Dictionary:
	var base_report: Dictionary = _atmosphere_base.atmosphere_report() if _atmosphere_base != null else {}
	var fore_report: Dictionary = _atmosphere_fore.atmosphere_report() if _atmosphere_fore != null else {}
	return {
		"preset": ATMOSPHERE_PRESET,
		"enabled": not _scene_mode(),
		"base_ready": _atmosphere_base != null and not _atmosphere_base.front,
		"light_ready": _atmosphere_light != null and _atmosphere_light.light_only and _atmosphere_light.additive,
		"fore_ready": _atmosphere_fore != null and _atmosphere_fore.front,
		"base": base_report,
		"fore": fore_report,
		"warm_light_count": atmosphere_warm_lights().size(),
		"drawn_inside_subviewport": world_viewport != null,
	}


func _attach_display(node: TextureRect) -> void:
	## The display sits under the screen's design canvas, which owns the uniform
	## UI scale; this class then pins the world to a whole-number multiple of it.
	add_child(node)


func set_world_scale(scale_multiple: int, available_size := Vector2(1280, 720)) -> void:
	## Fit the close follow view, never the full map, to the available canvas.
	## Legacy fixtures keep their integer pixel-stage scale and centering.
	if world_display == null:
		return
	_display_size = available_size
	var factor := float(maxi(1, scale_multiple))
	if _scene_mode():
		factor = minf(available_size.x / _view_size.x, available_size.y / _view_size.y)
	world_display.scale = Vector2.ONE * factor
	world_display.size = _view_size
	world_display.position = ((available_size - _view_size * factor) * 0.5).floor()


func _rebuild_world() -> void:
	if world_root == null:
		return
	if town_layer != null:
		## The connective layer is part of the approved world pass, never a
		## replacement for a missing atlas or ground package.
		town_layer.visible = is_ready()
	for layer: Node2D in [field_layer, ground_base_layer, ground_layer, object_lower_layer, actor_layer]:
		_clear_children(layer)
	_sprite_nodes.clear()
	_fade_targets.clear()
	_cutaway_cache.clear()
	_scene_patches.clear()
	_hero_sprite = null
	_hero_shadow = null
	if not is_ready():
		_log_pending()
		return
	if not _ground_note.is_empty():
		_log_ground_note()
	if _scene_mode():
		_draw_scene_foreground()
	else:
		_draw_ground_field()
	_draw_placements()
	_draw_life()
	_draw_hero()
	if _destination_marker != null:
		set_destination(_destination_id)


func _draw_ground_field() -> void:
	## Bounded authored terrain is drawn once. Legacy seamless fixture fields
	## retain their eight mirrored extensions and unrestricted follow camera.
	var metadata := _ground_entry()
	if metadata.is_empty():
		return
	var texture := metadata.get("texture", null) as Texture2D
	if texture == null:
		return
	var rect := metadata.get("rect", []) as Array
	if rect.size() != 4:
		return
	var band := Rect2(Vector2(float(rect[0]), float(rect[1])), Vector2(float(rect[2]), float(rect[3])))
	## The field is drawn at the world origin whatever anchor the sprite declares,
	## so a mirrored extension always lines up with the far edge of the 1024x640
	## surface instead of drifting with the sprite's own feet offset.
	var field_size := GROUND_BAND_SIZE
	if band.size != field_size:
		_pending_reasons.append("ground sprite covers %s, the world field is %s" % [band.size, field_size])
	_add_field_sprite(ground_base_layer, "GroundBase", texture, band, Vector2.ONE, Vector2.ZERO)
	if _bounded_camera():
		return
	for gy: int in [-1, 0, 1]:
		for gx: int in [-1, 0, 1]:
			if gx == 0 and gy == 0:
				continue
			var mirror := Vector2(1.0 if gx == 0 else -1.0, 1.0 if gy == 0 else -1.0)
			var offset := Vector2(2.0 * band.size.x if gx == 1 else 0.0, 2.0 * band.size.y if gy == 1 else 0.0)
			_add_field_sprite(field_layer, "MirroredField_%d_%d" % [gx, gy], texture, band, mirror, offset)


func _add_field_sprite(parent: Node2D, node_name: String, texture: Texture2D, band: Rect2, mirror: Vector2, offset: Vector2) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.name = node_name
	sprite.texture = texture
	sprite.centered = false
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.region_enabled = true
	sprite.region_rect = band
	sprite.scale = mirror
	sprite.position = offset
	parent.add_child(sprite)
	return sprite


func _draw_placements() -> void:
	for raw: Variant in _layout.get("placements", []) as Array:
		if not raw is Dictionary:
			continue
		var item := raw as Dictionary
		var placement_id := String(item.get("id", ""))
		if placement_id.is_empty():
			continue
		var sprite_id := String(item.get("sprite", ""))
		if sprite_id.is_empty():
			continue
		if String(item.get("layer", "")) == LAYER_GROUND:
			_sprite_nodes[placement_id] = _add_sprite(ground_layer, item, 0, -1, "Ground_%s" % placement_id)
			continue
		var split_row := int(item.get("split_row", 0))
		if split_row <= 0:
			_sprite_nodes[placement_id] = _add_sprite(actor_layer, item, 0, -1, "Object_%s" % placement_id)
			continue
		# Image rows grow downward. The solid foot is below split_row; only the
		# top belongs in the feet-sorted layer and is allowed to fade.
		_sprite_nodes["%s.lower" % placement_id] = _add_sprite(object_lower_layer, item, split_row, -1, "Lower_%s" % placement_id)
		var upper := _add_sprite(actor_layer, item, 0, split_row, "Upper_%s" % placement_id)
		_sprite_nodes["%s.upper" % placement_id] = upper
		if upper != null:
			_fade_targets.append({"item": item, "sprite": upper})


func _add_sprite(parent: Node2D, item: Dictionary, row_start: int, row_end: int, node_name: String) -> Sprite2D:
	## One sprite, its own rect and anchor, optional split_row crop: the lower
	## band stands in the ground layer, the upper band joins the y-sorted feet
	## layer with the avatar. No cell size is ever assumed.
	var metadata := _sprite_entry(String(item.get("sprite", "")))
	if metadata.is_empty():
		return null
	var texture := metadata.get("texture", null) as Texture2D
	var rect := metadata.get("rect", []) as Array
	var anchor := metadata.get("anchor", []) as Array
	if texture == null or rect.size() != 4 or anchor.size() != 2:
		return null
	var height := int(rect[3])
	var top := clampi(row_start, 0, height)
	var bottom := height if row_end < 0 else clampi(row_end, 0, height)
	if bottom <= top:
		return null
	var band := _clip_band(_feet(item), rect, anchor, top, bottom)
	if band.is_empty():
		return null
	var sprite := Sprite2D.new()
	sprite.name = node_name
	sprite.set_meta("sprite_id", String(item.get("sprite", "")))
	sprite.texture = texture
	sprite.centered = false
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.region_enabled = true
	sprite.region_rect = band.region
	sprite.position = Vector2(_feet(item))
	sprite.offset = band.offset
	parent.add_child(sprite)
	return sprite


func _clip_band(feet: Vector2, rect: Array, anchor: Array, row_start: int, row_end: int) -> Dictionary:
	## A composite station may stand with part of its cell outside the world
	## field. Only the part that overlaps the authored world is drawn, so no cell
	## is ever trusted to fit inside the world.
	var cell := Rect2(feet - Vector2(float(anchor[0]), float(anchor[1])), Vector2(float(rect[2]), float(rect[3])))
	var band := Rect2(cell.position + Vector2(0.0, float(row_start)), Vector2(cell.size.x, float(row_end - row_start)))
	var visible := band.intersection(Rect2(Vector2.ZERO, _world_size if _scene_mode() else GROUND_BAND_SIZE))
	if visible.size.x <= 0.0 or visible.size.y <= 0.0:
		return {}
	var cut := visible.position - band.position
	return {
		"region": Rect2(
			Vector2(float(rect[0]) + cut.x, float(rect[1]) + float(row_start) + cut.y),
			visible.size
		),
		"offset": Vector2(-float(anchor[0]) + cut.x, -float(anchor[1]) + float(row_start) + cut.y),
	}


func _draw_hero() -> void:
	## Rect and anchor come from the shared action frame when it is available and
	## from the approved static four-way cell otherwise: the frame's own anchor is
	## used, never an assumed cell slot.
	var metadata := _hero_sprite_metadata()
	if metadata.is_empty():
		return
	var texture := metadata.get("texture", null) as Texture2D
	var rect := metadata.get("rect", []) as Array
	var anchor := metadata.get("anchor", []) as Array
	if texture == null or rect.size() != 4 or anchor.size() != 2:
		return
	# Contact footprint stays independent of atlas padding and cannot sample a
	# transparent corner pixel from the new action sheet as the old shadow did.
	var shadow := Polygon2D.new()
	shadow.name = "HeroShadow"
	shadow.polygon = PackedVector2Array([Vector2(-12, -2), Vector2(-8, -4), Vector2(8, -4), Vector2(12, -2), Vector2(12, 2), Vector2(8, 4), Vector2(-8, 4), Vector2(-12, 2)])
	shadow.color = Color(0.0, 0.0, 0.0, 0.35)
	actor_layer.add_child(shadow)
	shadow.z_index = -1
	_hero_shadow = shadow
	var hero := Sprite2D.new()
	hero.name = "Hero"
	hero.texture = texture
	hero.centered = false
	hero.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	hero.region_enabled = true
	hero.region_rect = Rect2(Vector2(float(rect[0]), float(rect[1])), Vector2(float(rect[2]), float(rect[3])))
	hero.offset = Vector2(-float(anchor[0]), -float(anchor[1]))
	actor_layer.add_child(hero)
	_hero_sprite = hero
	_update_hero_visual()


func _update_hero_visual() -> void:
	var point := Vector2(hero_snapped_position())
	if _hero_sprite != null:
		var metadata := _hero_sprite_metadata()
		if not metadata.is_empty():
			_hero_sprite.texture = metadata.get("texture", null) as Texture2D
			var rect := metadata.get("rect", []) as Array
			var anchor := metadata.get("anchor", []) as Array
			if rect.size() == 4 and anchor.size() == 2:
				_hero_sprite.region_rect = Rect2(Vector2(float(rect[0]), float(rect[1])), Vector2(float(rect[2]), float(rect[3])))
				_hero_sprite.offset = Vector2(-float(anchor[0]), -float(anchor[1]))
		_hero_sprite.position = point
	if _hero_shadow != null:
		_hero_shadow.position = point


func hero_sprite_id(facing: String) -> String:
	var wanted := String(FACING_IDS.get(facing, FACING_IDS[DEFAULT_HERO_FACING]))
	return wanted if _sprites.has(wanted) else String(FACING_IDS[DEFAULT_HERO_FACING])


## Metadata the hero sprite is drawn from: the shared action frame while the
## published action atlas is in hand, or the approved static four-way cell, which
## the reader reports as an explicit pending fallback rather than a substitution.
func _hero_sprite_metadata() -> Dictionary:
	var frame := _ranger_frame()
	if not frame.is_empty():
		var texture: Texture2D = frame.get("texture")
		var rect: Rect2i = frame.get("rect", Rect2i())
		var anchor: Vector2i = frame.get("anchor", RangerAnimationScript.DEFAULT_ANCHOR)
		if texture != null and rect.size.x > 0 and rect.size.y > 0:
			return {
				"texture": texture,
				"rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y],
				"anchor": [anchor.x, anchor.y],
			}
	return _sprite_entry(hero_sprite_id(_hero_facing))


## The shared action frame, or an empty dictionary while the atlas is pending or
## broken. The fallback is never silent: ranger_action_pending_reasons() says why.
func _ranger_frame() -> Dictionary:
	if ranger_animation == null or not ranger_animation.has_real_art():
		return {}
	var frame: Dictionary = ranger_animation.resolve(_hero_animation_state())
	if bool(frame.get("fallback", true)):
		return {}
	return frame


func _hero_animation_state() -> Dictionary:
	## Only walk and idle are ever live in the hub; the loop clock is the hub's own
	## presentation clock and never feeds gameplay.
	var seconds: float = _walk_time if _walking else _idle_time
	var clock := int(round(seconds * float(RangerAnimationScript.SIM_TICKS_PER_SECOND)))
	return {
		"facing": _hero_facing,
		"moving": _walking,
		"dead": false,
		"hit_ticks": -1,
		"dodge_ticks": -1,
		"dash_ticks": -1,
		"shoot_ticks": -1,
		"phase_ticks": clock,
		"tick": clock,
	}


func ranger_action_pending_reasons() -> Array[String]:
	if ranger_animation == null:
		return ["ASSETS PENDING: no ranger action reader"]
	return ranger_animation.pending_reasons()


## Tests and the graphics check: which frame the hero sprite is being drawn from.
func hero_animation_report() -> Dictionary:
	var frame := _ranger_frame()
	return {
		"fallback": frame.is_empty(),
		"clip": String(frame.get("clip", "")),
		"frame": int(frame.get("frame", -1)),
		"facing": _hero_facing,
		"walking": _walking,
	}


## Runtime integration diagnostic for the art pass: the frame the hub is drawing
## the hero from, plus the last action event it latched and when.
func ranger_animation_report() -> Dictionary:
	var report := {"pending_reason": "", "state": _hero_animation_state()}
	if ranger_animation != null:
		report["reader"] = ranger_animation.integration_report()
		report["pending_reason"] = ranger_animation.pending_reason()
	return report


func _process(delta: float) -> void:
	if _world_dirty:
		_sync_camera()
	_update_hero_animation(delta)
	_update_life(delta)
	_update_split_fade()
	_update_cutaway()


## Presentation clock only: the idle cycle advances here, the walk cycle keeps
## the clock move_hero() already maintains, and nothing here writes gameplay.
func _update_hero_animation(delta: float) -> void:
	if ranger_animation == null or not ranger_animation.has_real_art():
		return
	if not _walking:
		_idle_time += maxf(0.0, delta)
	var frame := _ranger_frame()
	var frame_key := "%s:%d" % [String(frame.get("clip", "")), int(frame.get("frame", -1))]
	if frame_key == _hero_frame_key:
		return
	_hero_frame_key = frame_key
	_update_hero_visual()


func _sync_camera() -> void:
	if world_root == null:
		return
	world_root.position = -camera_world_offset()
	_world_dirty = false


func _update_split_fade() -> void:
	## The half-tone rule of the approved concept: a stand's upper body drops to
	## a translucent band while the avatar crosses in front of it, and the lower
	## band plus the whole ground stay untouched.
	if _fade_targets.is_empty() and _life_effects.is_empty():
		return
	var parts := _hero_parts()
	var hero := Rect2(Vector2(hero_snapped_position()) - Vector2(parts.x, parts.y), Vector2(parts.z, parts.w))
	for target: Dictionary in _fade_targets:
		var sprite := target.get("sprite", null) as Sprite2D
		if sprite == null:
			continue
		var item := target.get("item", {}) as Dictionary
		sprite.modulate.a = _split_fade_alpha(item, hero)
	## An upper-band socket is its owner's own upper band continued: it inherits
	## the half-tone the loop above just wrote, so a fire inside a faded hearth
	## fades with it instead of burning at full alpha through a translucent stand.
	for record: Dictionary in _life_effects:
		var source := record.get("fade_source", null) as Sprite2D
		var node := record.get("node", null) as Sprite2D
		if source == null or node == null or source == node:
			continue
		node.modulate.a = source.modulate.a


func _split_fade_alpha(item: Dictionary, hero_box: Rect2) -> float:
	var split_row := int(item.get("split_row", 0))
	var metadata := _sprite_entry(String(item.get("sprite", "")))
	if split_row <= 0 or metadata.is_empty():
		return 1.0
	var rect := metadata.get("rect", []) as Array
	var anchor := metadata.get("anchor", []) as Array
	if rect.size() != 4 or anchor.size() != 2:
		return 1.0
	var feet := _feet(item)
	if hero_snapped_position().y >= feet.y:
		return 1.0
	var standing_height := float(mini(split_row, int(rect[3])))
	var standing := Rect2(
		feet - Vector2(float(anchor[0]), float(anchor[1])),
		Vector2(float(rect[2]), standing_height)
	)
	return SPLIT_FADE_ALPHA if hero_box.intersects(standing) else 1.0


## ------------------------------------------------------------------ life art

## Applies the published life package on top of the static placements. A
## resident work cycle replaces that placement's texture, cell and offset while
## its feet stay exactly where the layout put them; every declared socket adds
## one looping effect on its owner's feet. A package that is missing or
## half-authored leaves the approved static residents untouched: nothing here
## fakes a cycle, and nothing here can fail the hub's readiness.
func _draw_life() -> void:
	_life_residents.clear()
	_life_effects.clear()
	_life_pending.clear()
	if life_animation == null:
		return
	for entry: Dictionary in life_animation.resident_entries():
		var placement := String(entry.get("placement", ""))
		var node := _sprite_nodes.get(placement, null) as Sprite2D
		if node == null:
			_life_pending.append("resident %s has no placement in this layout" % placement)
			continue
		var record := {
			"placement": placement,
			"clip": String(entry.get("clip", "")),
			"phase": float(entry.get("phase", 0.0)),
			"socket_offset": Vector2.ZERO,
			"node": node,
		}
		node.set_meta("life_clip", String(record["clip"]))
		_life_residents.append(record)
		_apply_life_frame_if_changed(record)
	if not _scene_mode():
		for entry: Dictionary in life_animation.effect_entries():
			_add_life_effect(entry)


func _add_life_effect(entry: Dictionary) -> void:
	## One socket, carried by its owner's own feet: the sprite position stays the
	## owner's feet so the hub's feet sort keeps the socket inside its owner's own
	## band, and the authored socket offset lives in the sprite offset next to the
	## clip's anchor. An upper socket joins the feet-sorted layer and rides its
	## owner's half-tone; a lower socket joins the owner's own solid band.
	var socket_id := String(entry.get("id", ""))
	var owner_id := String(entry.get("owner", ""))
	var owner := _life_owner_node(owner_id)
	if owner == null:
		_life_pending.append("socket %s has no owner %s in this layout" % [socket_id, owner_id])
		return
	var layer := String(entry.get("layer", HamletLifeAnimationScript.DEFAULT_EFFECT_LAYER))
	var parent := object_lower_layer if layer == HamletLifeAnimationScript.LAYER_LOWER else actor_layer
	if parent == null:
		return
	var node := Sprite2D.new()
	node.name = "Life_%s" % socket_id
	node.centered = false
	node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	node.region_enabled = true
	node.position = owner.position
	node.set_meta("sprite_id", String(entry.get("clip", "")))
	node.set_meta("life_socket", socket_id)
	node.set_meta("life_owner", owner_id)
	node.set_meta("life_layer", layer)
	parent.add_child(node)
	_sprite_nodes["%s%s" % [LIFE_NODE_PREFIX, socket_id]] = node
	var record := {
		"id": socket_id,
		"owner": owner_id,
		"clip": String(entry.get("clip", "")),
		"phase": float(entry.get("phase", 0.0)),
		"socket_offset": entry.get("offset", Vector2.ZERO) as Vector2,
		"layer": layer,
		"node": node,
		"fade_source": _life_fade_source(owner_id, layer),
	}
	_life_effects.append(record)
	_apply_life_frame_if_changed(record)


func _life_owner_node(owner_id: String) -> Sprite2D:
	## Any band the owner published on: both bands stand on the same feet, so the
	## socket lands on the same point whichever one this layout drew.
	var lower := _sprite_nodes.get("%s.lower" % owner_id, null) as Sprite2D
	return lower if lower != null else _sprite_nodes.get(owner_id, null) as Sprite2D


func _life_fade_source(owner_id: String, layer: String) -> Sprite2D:
	## Only an upper socket shares its owner's half-tone: the owner's own upper
	## band is the sprite the split fade already owns.
	if layer != HamletLifeAnimationScript.LAYER_UPPER:
		return null
	return _sprite_nodes.get("%s.upper" % owner_id, null) as Sprite2D


func _apply_life_frame_if_changed(record: Dictionary) -> void:
	## One published step, applied only when the clip really moved on: the shared
	## cutaway reads this cell, so it must always measure the frame on screen.
	if life_animation == null:
		return
	var clip := String(record.get("clip", ""))
	var frame: Dictionary = life_animation.frame_at(clip, life_animation.life_time() + float(record.get("phase", 0.0)))
	if frame.is_empty():
		return
	var key := "%s:%d" % [clip, int(frame.get("index", -1))]
	if key == String(record.get("frame_key", "")):
		return
	record["frame_key"] = key
	_apply_life_frame(record.get("node", null) as Sprite2D, frame, record.get("socket_offset", Vector2.ZERO) as Vector2)


func _apply_life_frame(node: Sprite2D, frame: Dictionary, socket_offset: Vector2) -> void:
	## The published cell, clipped to the world field exactly like a static cell.
	## The node itself never moves: a resident keeps its layout feet and a socket
	## keeps its owner's, and the whole authored offset - socket offset plus the
	## clip's own anchor - lands in the sprite offset.
	if node == null:
		return
	var rect := frame.get("rect", Rect2()) as Rect2
	var anchor := frame.get("anchor", Vector2.ZERO) as Vector2
	var band := _clip_band(
		node.position + socket_offset,
		[rect.position.x, rect.position.y, rect.size.x, rect.size.y],
		[anchor.x, anchor.y],
		0,
		int(rect.size.y)
	)
	if band.is_empty():
		return
	node.texture = frame.get("texture", null) as Texture2D
	node.region_rect = band["region"] as Rect2
	node.offset = socket_offset + (band["offset"] as Vector2)


func _update_life(delta: float) -> void:
	## Before the split fade and the cutaway: both measure the frames this call
	## just placed, and neither may run on last frame's cell. Presentation only -
	## the hub's life clock never reaches gameplay.
	if life_animation == null:
		return
	life_animation.tick(delta)
	for record: Dictionary in _life_residents:
		_apply_life_frame_if_changed(record)
	for record: Dictionary in _life_effects:
		_apply_life_frame_if_changed(record)


## ------------------------------------------------------------------ cutaway

func _hero_cell_world() -> Rect2:
	## The avatar's own drawn cell: the rect the split fade measures against and
	## every external visibility check samples, never a gameplay collision box.
	var parts := _hero_parts()
	return Rect2(Vector2(hero_snapped_position()) - Vector2(parts.x, parts.y), Vector2(parts.z, parts.w))


static func cutaway_window(cell: Rect2) -> Rect2:
	## The avatar cell plus its pad, kept on the integer pixel grid the hub draws
	## on so a cut band always lands on whole source pixels.
	var grown := cell.grow(CUTAWAY_WINDOW_PAD)
	return Rect2(grown.position.round(), grown.size.round())


static func cutaway_alpha(count: int) -> float:
	## Even split of the local opacity budget: the source-over stack of any
	## subset of those layers never exceeds CUTAWAY_TOTAL_OPACITY, whatever else
	## the authored split fade already leaves on top of them.
	if count <= 0:
		return 1.0
	return clampf(1.0 - pow(1.0 - CUTAWAY_TOTAL_OPACITY, 1.0 / float(count)), 0.0, 1.0)


func _sprite_art_box(sprite: Sprite2D) -> Rect2:
	## Where the sprite's own region really lands in world units, from the anchor
	## and the band it was clipped to, so a partial cell is measured honestly.
	return Rect2(sprite.offset + sprite.position, sprite.region_rect.size)


func _cutaway_candidates(hero_point: Vector2, window: Rect2) -> Array[Dictionary]:
	## Foreground sprites only: anything the feet sort already draws before the
	## avatar cannot hide it, so it keeps today's alpha untouched.
	var found: Array[Dictionary] = []
	for raw_id: Variant in _sprite_nodes.keys():
		var sprite := _sprite_nodes[raw_id] as Sprite2D
		if sprite == null or sprite.get_parent() != actor_layer:
			continue
		if sprite.position.y <= hero_point.y:
			continue
		var box := _sprite_art_box(sprite)
		if not box.intersects(window):
			continue
		found.append({
			"id": String(raw_id),
			"sprite_id": String(sprite.get_meta("sprite_id", "")),
			"sprite": sprite,
			"feet_world": sprite.position,
			"art_box": box,
			"overlap": box.intersection(window),
		})
	return found


func _update_cutaway() -> void:
	if actor_layer == null:
		return
	if _scene_mode():
		var window := cutaway_window(_hero_cell_world())
		var candidates := _scene_occluders(window)
		var alpha := cutaway_alpha(candidates.size())
		for patch: Node2D in _scene_patches:
			patch.set_cutaway(window, alpha if candidates.has(patch) else 1.0)
		return
	var window := cutaway_window(_hero_cell_world())
	var candidates := _cutaway_candidates(Vector2(hero_snapped_position()), window)
	var alpha := cutaway_alpha(candidates.size())
	var active: Dictionary = {}
	for entry: Dictionary in candidates:
		active[entry["sprite"]] = true
	for raw_id: Variant in _sprite_nodes.keys():
		var sprite := _sprite_nodes[raw_id] as Sprite2D
		if sprite == null or sprite.get_parent() != actor_layer:
			continue
		if active.has(sprite):
			_cut_sprite(sprite, window, alpha * sprite.modulate.a)
		else:
			_release_cutaway(sprite)


func _cut_sprite(sprite: Sprite2D, window: Rect2, local_alpha: float) -> void:
	## Programmatic local alpha: the band is split into the four regions that keep
	## the authored alpha plus the avatar's own window at the cutaway alpha. The
	## object keeps its whole form outside the avatar and nothing is re-sorted.
	var quad := Rect2(sprite.offset, sprite.region_rect.size)
	var core := Rect2(window.position - sprite.position, window.size).intersection(quad)
	if core.size.x <= 0.0 or core.size.y <= 0.0:
		_release_cutaway(sprite)
		return
	var pieces := _cutaway_pieces(quad, core)
	var nodes := _cutaway_nodes(sprite)
	for index: int in pieces.size():
		var piece: Rect2 = pieces[index]
		var node: Sprite2D = nodes[index]
		if node == null:
			continue
		node.texture = sprite.texture
		node.position = sprite.position
		node.visible = piece.size.x > 0.0 and piece.size.y > 0.0
		if not node.visible:
			continue
		node.region_rect = Rect2(sprite.region_rect.position + (piece.position - quad.position), piece.size)
		node.offset = piece.position
		node.modulate = Color(1.0, 1.0, 1.0, local_alpha if index == CUTAWAY_WINDOW_INDEX else sprite.modulate.a)
	## The authored sprite steps aside for this frame: the five pieces tile exactly
	## its own cell, so the band is never drawn twice.
	sprite.visible = false


static func _cutaway_pieces(quad: Rect2, core: Rect2) -> Array[Rect2]:
	## Four solid bands plus the window tile the drawn cell exactly once under
	## source-over blending, in the order they are drawn.
	var top := Rect2(quad.position, Vector2(quad.size.x, core.position.y - quad.position.y))
	var bottom := Rect2(Vector2(quad.position.x, core.end.y), Vector2(quad.size.x, quad.end.y - core.end.y))
	var left := Rect2(Vector2(quad.position.x, core.position.y), Vector2(core.position.x - quad.position.x, core.size.y))
	var right := Rect2(Vector2(core.end.x, core.position.y), Vector2(quad.end.x - core.end.x, core.size.y))
	return [top, bottom, left, right, core]


func _cutaway_nodes(sprite: Sprite2D) -> Array:
	var key := int(sprite.get_instance_id())
	var cached: Variant = _cutaway_cache.get(key, null)
	if cached != null:
		return cached as Array
	var nodes: Array = []
	for index: int in 5:
		var node := Sprite2D.new()
		node.name = "Cut_%s_%d" % [sprite.name, index]
		node.centered = false
		node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		node.region_enabled = true
		node.visible = false
		actor_layer.add_child(node)
		nodes.append(node)
	_cutaway_cache[key] = nodes
	return nodes


func _release_cutaway(sprite: Sprite2D) -> void:
	## Leaving the band restores the authored drawing in the same frame.
	if sprite == null:
		return
	if not sprite.visible:
		sprite.visible = true
	var cached: Variant = _cutaway_cache.get(int(sprite.get_instance_id()), null)
	if cached == null:
		return
	for node: Sprite2D in cached as Array:
		if node != null and node.visible:
			node.visible = false


## Read-only cutaway diagnostic for the external visibility harness: how many
## foreground layers really cover the avatar, the total local opacity they
## compose to, and the window itself. Nothing here writes or re-sorts the scene.
func occlusion_report() -> Dictionary:
	if _scene_mode():
		return _scene_occlusion_report()
	var hero_point := Vector2(hero_snapped_position())
	var cell := _hero_cell_world()
	var window := cutaway_window(cell)
	var candidates := _cutaway_candidates(hero_point, window)
	var alpha := cutaway_alpha(candidates.size())
	var entries: Array[Dictionary] = []
	var front_ids: Array[String] = []
	var front_nodes: Array[String] = []
	var opacity := 0.0
	for entry: Dictionary in candidates:
		var sprite := entry["sprite"] as Sprite2D
		var local := alpha * sprite.modulate.a
		opacity = 1.0 - (1.0 - opacity) * (1.0 - local)
		front_ids.append(String(entry["id"]))
		front_nodes.append(String(sprite.name))
		entries.append({
			"id": String(entry["id"]),
			"sprite_id": String(entry["sprite_id"]),
			"node": String(sprite.name),
			"feet_world": entry["feet_world"],
			"art_box": entry["art_box"],
			"local_alpha": local,
			"overlap": entry["overlap"],
		})
	return {
		"hero_world": _hero_position,
		"hero_snapped": hero_point,
		"hero_cell_world": cell,
		"window_world": window,
		"window_pad": CUTAWAY_WINDOW_PAD,
		"occluder_count": entries.size(),
		"local_alpha_each": alpha,
		"local_opacity_total": opacity,
		"occluders": entries,
		"front_ids": front_ids,
		"front_nodes": front_nodes,
		"unchanged": entries.is_empty(),
	}


func _hero_parts() -> Vector4:
	## Hero anchor and cell packed together: xy is the anchor, zw the cell size.
	var metadata := _hero_sprite_metadata()
	if not metadata.is_empty():
		var rect := metadata.get("rect", []) as Array
		var anchor := metadata.get("anchor", []) as Array
		if rect.size() == 4 and anchor.size() == 2:
			return Vector4(float(anchor[0]), float(anchor[1]), float(rect[2]), float(rect[3]))
	return Vector4(16.0, 44.0, 32.0, 48.0)


## ------------------------------------------------------------------- lookup

func _ground_entry() -> Dictionary:
	var wanted := String(_layout.get("ground_sprite", ""))
	if wanted.is_empty():
		wanted = DEFAULT_GROUND_ID
	var order: Array = GROUND_ORDER if wanted == DEFAULT_GROUND_ID else SPRITE_ORDER
	var resolved := _resolve_sprite_id(wanted, order)
	if resolved.is_empty():
		resolved = _resolve_sprite_id(GROUND_SPRITE_FALLBACK, SPRITE_ORDER)
	if resolved.is_empty():
		resolved = _resolve_sprite_id(DEFAULT_GROUND_ID, GROUND_ORDER)
	if resolved.is_empty():
		## A missing world field costs the backdrop, not the layout: the stations
		## still stand, so this is reported separately from a broken contract.
		_ground_note = "ground sprite %s is missing from every atlas" % wanted
		return {}
	return _sprite_entry(resolved)


func _resolve_sprite_id(sprite_id: String, order: Array) -> String:
	if sprite_id.is_empty() or not _sprites.has(sprite_id):
		return ""
	for group: String in order:
		var metadata := _sprite_entry(sprite_id)
		if metadata.is_empty():
			continue
		if String(metadata.get("source", "")) == group:
			return sprite_id
	return sprite_id


func _sprite_entry(sprite_id: String) -> Dictionary:
	var raw: Variant = _sprites.get(sprite_id, null)
	if not raw is Dictionary:
		return {}
	var metadata := (raw as Dictionary).duplicate(true)
	metadata["texture"] = _textures.get(String(metadata.get("texture", ""))) as Texture2D
	return metadata


func _sprite_hotspot_radius(sprite_id: String) -> float:
	var metadata := _sprite_entry(sprite_id)
	if metadata.is_empty():
		return HOTSPOT
	var rect := metadata.get("rect", []) as Array
	if rect.size() != 4:
		return HOTSPOT
	return maxf(float(rect[2]), float(rect[3])) * 0.75


func _feet(item: Dictionary) -> Vector2:
	if item.has("feet_uv"):
		return _point(item.feet_uv, Vector2.ZERO) * _world_size
	var feet: Variant = item.get("feet", null)
	if _integer_list(feet, 2):
		return Vector2(float((feet as Array)[0]), float((feet as Array)[1]))
	return Vector2.ZERO


func _scene_mode() -> bool:
	return not String(_layout.get("scene_texture", "")).is_empty()


func _scene_polygon(item: Dictionary) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point: Array in item.get("points_uv", []):
		result.append(Vector2(float(point[0]), float(point[1])) * _world_size)
	return result


func _draw_scene_foreground() -> void:
	for item: Dictionary in _layout.get("foreground", []):
		var patch := ScenePatchScript.new()
		patch.name = "Scene_%s" % String(item.id)
		patch.set_meta("placement_id", String(item.id))
		patch.world_size = _world_size
		patch.scene_texture = _scene_texture
		patch.world_polygon = _scene_polygon(item)
		patch.position = _feet(item)
		patch.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		actor_layer.add_child(patch)
		_scene_patches.append(patch)


func _scene_occluders(window: Rect2) -> Array[Node2D]:
	var found: Array[Node2D] = []
	for patch: Node2D in _scene_patches:
		if patch.position.y > float(hero_snapped_position().y) and patch.overlaps(window):
			found.append(patch)
	return found


func _scene_occlusion_report() -> Dictionary:
	var cell := _hero_cell_world()
	var window := cutaway_window(cell)
	var candidates := _scene_occluders(window)
	var alpha := cutaway_alpha(candidates.size())
	var entries: Array[Dictionary] = []
	var ids: Array[String] = []
	var nodes: Array[String] = []
	for patch: Node2D in candidates:
		var id := String(patch.get_meta("placement_id"))
		ids.append(id)
		nodes.append(String(patch.name))
		entries.append({"id": id, "node": String(patch.name), "feet_world": patch.position,
			"polygon_world": patch.world_polygon, "local_alpha": alpha, "overlap": window})
	return {"hero_world": _hero_position, "hero_snapped": Vector2(hero_snapped_position()),
		"hero_cell_world": cell, "window_world": window, "window_pad": CUTAWAY_WINDOW_PAD,
		"occluder_count": entries.size(), "occluders": entries, "front_ids": ids, "front_nodes": nodes,
		"local_alpha_each": alpha, "local_opacity_total": 1.0 - pow(1.0 - alpha, candidates.size()),
		"unchanged": candidates.is_empty(), "source_size": _scene_texture.get_size() if _scene_texture != null else Vector2.ZERO}


func _log_pending() -> void:
	if _pending_logged:
		return
	_pending_logged = true
	for reason: String in pending_reasons():
		printerr("ASSETS PENDING p1_hamlet_concept_v02: " + reason)


func _log_ground_note() -> void:
	## Warning only: the stations keep their own pending state and still render.
	if _ground_logged:
		return
	_ground_logged = true
	printerr("ASSETS PENDING p1_hamlet_concept_v02 (backdrop only): " + _ground_note)


## ------------------------------------------------------------- test support

func configure_life_for_test(resident_atlas: Dictionary, manifest: Dictionary, effect_atlas: Dictionary) -> void:
	## Fixture entry: the life package already in memory, nothing else read. The
	## layout, its residents and their feet stay exactly the fixture's own.
	if life_animation == null:
		life_animation = HamletLifeAnimationScript.new()
	life_animation.configure(resident_atlas, manifest, effect_atlas)
	_rebuild_world()
	_world_dirty = true


func set_life_time_for_test(seconds: float) -> void:
	## Fixture clock: one deterministic instant for every resident and socket.
	if life_animation == null:
		return
	life_animation.set_life_time_for_test(seconds)
	for record: Dictionary in _life_residents:
		_apply_life_frame_if_changed(record)
	for record: Dictionary in _life_effects:
		_apply_life_frame_if_changed(record)


func life_pending_reasons() -> Array[String]:
	## The life package's own pending list. It is deliberately not part of
	## pending_reasons(): a hub whose life art is still pending is established,
	## and its fixtures keep answering exactly as they did before this pass.
	var reasons := _life_pending.duplicate()
	if life_animation != null:
		reasons.append_array(life_animation.pending_reasons())
	return reasons


func life_report() -> Dictionary:
	## Read-only life diagnostic for the graphics pass: every resident and socket
	## with the clip it runs, the frame it shows, the sheet it was cut from and
	## the world point it stands on. Nothing here writes or re-sorts the scene.
	var residents: Array[Dictionary] = []
	for record: Dictionary in _life_residents:
		residents.append(_life_node_report(record, String(record.get("placement", ""))))
	var effects: Array[Dictionary] = []
	for record: Dictionary in _life_effects:
		var entry := _life_node_report(record, String(record.get("id", "")))
		var source := record.get("fade_source", null) as Sprite2D
		entry["owner"] = String(record.get("owner", ""))
		entry["layer"] = String(record.get("layer", ""))
		entry["fade_source"] = String(source.name) if source != null else ""
		effects.append(entry)
	return {
		"ready": life_animation != null and life_animation.life_ready(),
		"scene_effects": town_layer.town_report().get("effects", []) if _scene_mode() and town_layer != null else [],
		"art": life_animation != null and life_animation.has_real_art(),
		"time": life_animation.life_time() if life_animation != null else 0.0,
		"residents": residents,
		"effects": effects,
		"pending": life_pending_reasons(),
	}


func _life_node_report(record: Dictionary, entry_id: String) -> Dictionary:
	var node := record.get("node", null) as Sprite2D
	var clip := String(record.get("clip", ""))
	var phase := float(record.get("phase", 0.0))
	var seconds: float = (life_animation.life_time() + phase) if life_animation != null else phase
	return {
		"id": entry_id,
		"clip": clip,
		"phase": phase,
		"frame": life_animation.frame_index(clip, seconds) if life_animation != null else -1,
		"frames": life_animation.clip_frame_count(clip) if life_animation != null else 0,
		"fps": life_animation.clip_fps(clip) if life_animation != null else 0.0,
		"texture": life_animation.clip_texture_path(clip) if life_animation != null else "",
		"node": String(node.name) if node != null else "",
		"feet": node.position if node != null else Vector2.ZERO,
		"offset": node.offset if node != null else Vector2.ZERO,
		"socket_offset": record.get("socket_offset", Vector2.ZERO) as Vector2,
		"rect": node.region_rect if node != null else Rect2(),
	}


func _life_clear() -> void:
	## The in-memory fixture entry point takes exactly the contracts it was
	## handed, so no life package survives it.
	_life_residents.clear()
	_life_effects.clear()
	_life_pending.clear()
	if life_animation != null:
		life_animation.clear()


func replace_textures_for_test(source: Dictionary) -> void:
	_hit_images.clear()
	## Tests only: an in-memory atlas still has to prove it renders, so the
	## decoded image is supplied directly instead of being read from disk.
	for texture_key: String in source.keys():
		var value: Variant = source[texture_key]
		if value is Texture2D:
			_textures[texture_key] = value
	_rebuild_world()
	_world_dirty = true


func render_audit() -> Dictionary:
	var layers := {"ground": 0, "ground_layer": 0, "town_concept": 0, "object_lower": 0, "actors": 0, "skirt": 0}
	if ground_base_layer != null:
		layers["ground"] = ground_base_layer.get_child_count()
	if ground_layer != null:
		layers["ground_layer"] = ground_layer.get_child_count()
	if town_layer != null:
		layers["town_concept"] = 1
	if object_lower_layer != null:
		layers["object_lower"] = object_lower_layer.get_child_count()
	if actor_layer != null:
		layers["actors"] = actor_layer.get_child_count()
	if field_layer != null:
		layers["skirt"] = field_layer.get_child_count()
	var facilities: Array[Dictionary] = []
	for entry: Dictionary in _feature_entries:
		facilities.append({
			"id": String(entry.id),
			"feet": entry.get("feet", Vector2.ZERO),
			"radius": float(entry.get("radius", HOTSPOT)),
			"locked": bool(entry.get("locked", false)),
			"sprite": String(entry.get("sprite", "")),
			"from_layout": bool(entry.get("from_layout", false)),
		})
	var fades: Array[float] = []
	for target: Dictionary in _fade_targets:
		var sprite := target.get("sprite", null) as Sprite2D
		fades.append(sprite.modulate.a if sprite != null else 1.0)
	var ground_id := String(_layout.get("ground_sprite", DEFAULT_GROUND_ID))
	var ground_meta := _sprites.get(ground_id, {}) as Dictionary
	var ground_texture_meta := _texture_meta.get(String(ground_meta.get("texture", "")), {}) as Dictionary
	return {
		"ready": is_ready(),
		"pending": _pending_reasons.duplicate(),
		"texture_pending": _texture_reasons.duplicate(),
		"world_size": _world_size,
		"view_size": _view_size,
		"hero": _hero_position,
		"hero_snapped": Vector2(hero_snapped_position()),
		"facing": _hero_facing,
		"camera_offset": camera_world_offset(),
		"hero_screen_anchor": _hero_screen_anchor,
		"nearby": _nearby_feature_id,
		"facilities": facilities,
		"layers": layers,
		"town_concept": town_layer.town_report() if town_layer != null else {"ready": false},
		"fades": fades,
		"sprite_nodes": _sprite_nodes.keys(),
		"ground_node": ground_base_layer.get_child(0).name if ground_base_layer != null and ground_base_layer.get_child_count() > 0 else "",
		"ground_source_path": String(_layout.get("scene_texture", ground_texture_meta.get("path", ""))),
	}


func _clear_children(parent: Node) -> void:
	if parent == null:
		return
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()


func _integer_list(value: Variant, size: int) -> bool:
	if not value is Array or (value as Array).size() != size:
		return false
	for element: Variant in value as Array:
		if not whole_number(element):
			return false
	return true


func _point(value: Variant, fallback: Vector2, alt_fallback: Vector2 = Vector2(INF, INF)) -> Vector2:
	if value is Array and (value as Array).size() == 2:
		var pair := value as Array
		if _finite_number(pair[0]) and _finite_number(pair[1]):
			return Vector2(float(pair[0]), float(pair[1]))
	return fallback if alt_fallback.x == INF else alt_fallback


func _finite_number(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) != TYPE_FLOAT:
		return false
	return is_finite(float(value))


static func whole_number(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) != TYPE_FLOAT:
		return false
	var number := float(value)
	return is_finite(number) and number == floor(number)
