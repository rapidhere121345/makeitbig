class_name TitleArtHelper
extends Control
## Title backdrop: a dedicated production plate plus real fire/steam frames,
## rendered at native 640x360 and shown at nearest integer scale. The UI has
## its own display-space layer, independent of the pixel-art transform.
##
## The view owns no art of its own. Every pixel is a cut from a published
## production texture, read through the same atlas.json + layout.json contract
## that the live base hub consumes (feet anchors, optional split_row banding,
## atlas order hamlet -> scene -> ground). While the pair is unpublished the
## backdrop stays the flat slate field and the reason is reported once as
## ASSETS PENDING, exactly like the hub: a missing sprite stays invisible and a
## missing texture costs one sprite, never a stand-in drawing.
##
## The title adds one thing the hub does not need - a fixed crop. The frame is
## derived from the layout's own placement for the surviving winter-watch tower
## and its shared-hearth canopy, so a re-published layout moves the title with it
## instead of drifting silently.
##
## title_life_v01 supplies four fire frames and four cooking-steam frames.
## Other environmental loops and ranger movement remain unproduced; static
## frames never stand in for a complete walk cycle.

const NATIVE_VIEW := Vector2i(640, 360)
const DISPLAY_SCALE := 2
const DISPLAY_SIZE := Vector2i(1280, 720)
const DEFAULT_FIELD_SIZE := Vector2(1024.0, 640.0)

const DEFAULT_ATLAS_PATH := "res://art/production/p1/hamlet_style_r13/atlas.json"
const DEFAULT_LAYOUT_PATH := "res://art/production/p1/hamlet_concept_v02/layout.json"
const SCENE_ATLAS_PATH := "res://art/production/p1/scene_rework_v01/atlas.json"
const GROUND_ATLAS_PATH := "res://art/production/p1/ground_refine_v01/atlas.json"
const ATLAS_SOURCES := [
	{"key": "hamlet", "path": DEFAULT_ATLAS_PATH},
	{"key": "scene", "path": SCENE_ATLAS_PATH},
	{"key": "ground", "path": GROUND_ATLAS_PATH},
]
const SPRITE_ORDER := ["hamlet", "scene", "ground"]
const GROUND_ORDER := ["hamlet", "ground", "scene"]
const DEFAULT_GROUND_ID := "scene.ground"
const GROUND_SPRITE_FALLBACK := "hamlet.ground"

## The produced, word-free title plate. Contract: native 640x360, drawn 1:1 into
## the 640x360 viewport and shown at nearest integer 2x, so the 1280x720 UI layer
## never resamples it and the left menu column never covers the tower.
const TITLE_PLATE_PATH := "res://art/production/p1/title_concept_v02/background.png"
const TITLE_PLATE_SIZE := Vector2i(640, 360)
const TITLE_PLATE_ATLAS_PATH := "res://art/production/p1/title_concept_v02/atlas.json"
const TITLE_PLATE_SPRITE_ID := "title.background"
const PLATE_STATUS_READY := "ready"
const PLATE_STATUS_PENDING := "pending"

## Backdrop sources, most preferred first. The produced plate is the title as
## approved; the layered crop of published production sprites is the provisional
## stand-in used only while the plate is unpublished, and it is reported as such
## rather than presented as the finished title.
const BACKDROP_PLATE := "plate"
const BACKDROP_LAYERS := "layers"
const BACKDROP_NONE := "none"
const PROVISIONAL_LAYERS_WHEN_PLATE_MISSING := true

const LAYER_GROUND := "ground"
const LAYER_OBJECT := "object"
const LAYER_NPC := "npc"

## Fixed crop: the placement that carries the ruined tower plus its shared hearth
## canopy, and where its feet land inside the 640x360 frame. Right of centre, so
## the left column stays free for the menu.
const FOCUS_PLACEMENT := "hearth"
const FOCUS_VIEW_POINT := Vector2(480.0, 300.0)

## The approved wanderer keeps its four static frames and stands in the opening
## between the menu column and the canopy. Nothing here animates it.
const WANDERER_FACING_IDS := {
	"south": "ranger.south.idle",
	"north": "ranger.north.idle",
	"west": "ranger.west.idle",
	"east": "ranger.east.idle",
}
const WANDERER_FACING := "east"
const WANDERER_VIEW_POINT := Vector2(296.0, 330.0)

const LOOP_STATUS_UNPRODUCED := "unproduced"
const LOOP_STATUS_READY := "ready"

## The produced life package: real flame and steam frames drawn as an independent
## overlay Node2D in this same integer-scaled 640x360 world layer, above the plate.
## Nothing is drawn when the frames are absent, and no flame is ever faked.
const TITLE_LIFE_ATLAS_PATH := "res://art/production/p1/title_life_v01/atlas.json"
## One overlay per published animation, placed on the plate's own pixel anchors:
## the flame sits on the brazier rim, the steam leaves the pot mouth 9px above it.
## Both were read off the plate, so a re-cut plate has to move them deliberately.
const LIFE_OVERLAYS := [
	{"animation": "life.fire", "node": "LifeFire", "anchor": Vector2i(338, 237)},
	{"animation": "life.steam", "node": "LifeSteam", "anchor": Vector2i(338, 228)},
]
const LIFE_ANCHORS := {
	"hearth_fire_pit": Vector2i(338, 237),
	"pot_steam_mouth": Vector2i(338, 228),
}
## Published cell sizes, kept as the contract the atlas is checked against.
const LIFE_EXPECTED_FRAMES := {
	"life.fire": Vector2i(8, 10),
	"life.steam": Vector2i(12, 18),
}
## fire is 4 frames at 4fps (1.0s) and steam 4 at 2fps (2.0s), so the two loops
## only meet again every 2 seconds: that common period is what the harness checks.
const LIFE_EXPECTED_PERIOD := 2.0

const SCENE_COLOR := Color("151b22")

var world_viewport: SubViewport
var world_root: Node2D
var field_layer: Node2D
var ground_layer: Node2D
var object_lower_layer: Node2D
var actor_layer: Node2D
var world_display: TextureRect

var _atlases: Dictionary = {}
var _sprites: Dictionary = {}
var _texture_meta: Dictionary = {}
var _textures: Dictionary = {}
var _pending_reasons: Array[String] = []
var _texture_reasons: Array[String] = []
var _pending_logged: bool = false

var _layout: Dictionary = {}
var _field_size: Vector2 = DEFAULT_FIELD_SIZE
var _camera_offset: Vector2 = Vector2.ZERO
var _focus_feet: Vector2 = Vector2.ZERO
var _focus_from_layout: bool = false
var _wanderer_node: Sprite2D
var _plate_texture: Texture2D
var _plate_rect: Rect2 = Rect2(Vector2.ZERO, Vector2(TITLE_PLATE_SIZE))
var _plate_anchor: Vector2i = TITLE_PLATE_SIZE
var _plate_reason: String = ""
var _plate_consulted: bool = false
var _backdrop_source: String = BACKDROP_NONE
var life_overlay_layer: Node2D
var _life_animations: Dictionary = {}
var _life_nodes: Dictionary = {}
var _life_elapsed: float = 0.0
var _life_reason: String = ""


func _ready() -> void:
	_build_layers()
	set_process(false)


## ------------------------------------------------------------------- loading

func load_default_assets() -> bool:
	## Reads the published pair from disk. A missing or half-authored file leaves
	## the view pending, which the title renders as the plain slate field.
	_reset()
	_load_title_plate()
	_plate_consulted = true
	_load_life_overlay()
	for source: Dictionary in ATLAS_SOURCES:
		var parsed := _read_json_object(String(source.path))
		if parsed.is_empty():
			continue
		_atlases[String(source.key)] = parsed
	_layout = _read_json_object(DEFAULT_LAYOUT_PATH)
	if _layout.is_empty():
		_pending_reasons.append("layout missing or not a JSON object at %s" % DEFAULT_LAYOUT_PATH)
	_configure(_atlases, _layout)
	return is_ready()


func configure(atlas: Dictionary, layout: Dictionary) -> void:
	## Fixture entry point: both contracts already in memory, nothing else read.
	## The produced plate is deliberately not consulted here.
	configure_sources({"hamlet": atlas.duplicate(true)}, layout)


func configure_sources(atlases: Dictionary, layout: Dictionary) -> void:
	## Fixture entry point for the full atlas set (hamlet, scene, ground), so the
	## provisional crop can be exercised with the real sprite sources.
	_reset()
	_atlases = atlases.duplicate(true)
	if layout.is_empty():
		_pending_reasons.append("layout dictionary is empty")
	_configure(_atlases, layout.duplicate(true))


func is_ready() -> bool:
	return _backdrop_source != BACKDROP_NONE


func backdrop_source() -> String:
	return _backdrop_source


func plate_status() -> String:
	return PLATE_STATUS_READY if _plate_texture != null else PLATE_STATUS_PENDING


func plate_reason() -> String:
	## Why the produced plate was refused, in full: empty while it is accepted.
	return _plate_reason


func pending_reasons() -> Array[String]:
	var result := _pending_reasons.duplicate()
	result.append_array(_texture_reasons)
	return result


func texture_reasons() -> Array[String]:
	## One undecodable PNG costs one invisible sprite, not the whole backdrop.
	return _texture_reasons.duplicate()


func loop_status() -> String:
	return life_status()


func loop_ready() -> bool:
	return life_ready()


func life_status() -> String:
	return LOOP_STATUS_READY if life_ready() else LOOP_STATUS_UNPRODUCED


func life_ready() -> bool:
	return _life_animations.size() == LIFE_OVERLAYS.size() and _life_reason.is_empty()


func life_drawn() -> bool:
	## The overlay is authored against the produced plate, so it is only drawn on
	## that backdrop; the provisional crop reports the frames without placing them
	## on anchors that belong to a different image.
	return _backdrop_source == BACKDROP_PLATE and not _life_nodes.is_empty()


func life_reason() -> String:
	return _life_reason


func life_period() -> float:
	## The common period: the point where every loop is back on its first frame.
	var period := 0.0
	for name: String in _life_animations.keys():
		var animation := _life_animations[name] as Dictionary
		var fps := float(animation.get("fps", 0.0))
		var count := (animation.get("frames", []) as Array).size()
		if fps <= 0.0 or count <= 0:
			continue
		period = maxf(period, float(count) / fps)
	return period


func life_frame_index(animation_name: String, seconds: float) -> int:
	## One published step per 1/fps, wrapping because every published loop wraps.
	var animation := _life_animations.get(animation_name, {}) as Dictionary
	var fps := float(animation.get("fps", 0.0))
	var count := (animation.get("frames", []) as Array).size()
	if fps <= 0.0 or count <= 0:
		return -1
	var step := int(floor(maxf(0.0, seconds) * fps))
	return ((step % count) + count) % count


func set_life_time(seconds: float) -> void:
	## Harness and test entry: a deterministic clock, so frame comparisons never
	## depend on wall time. Purely visual - no save, profile or route is touched.
	_life_elapsed = maxf(0.0, seconds)
	_update_life_frames()


func life_time() -> float:
	return _life_elapsed


func life_contract() -> Dictionary:
	## The published life package as this view consumes it: each overlay, the frame
	## it is showing, the atlas cell behind that frame and the anchors it stands on.
	var overlays: Array[Dictionary] = []
	for entry: Dictionary in LIFE_OVERLAYS:
		var animation_name := String(entry.animation)
		var animation := _life_animations.get(animation_name, {}) as Dictionary
		var frames := animation.get("frames", []) as Array
		var index := life_frame_index(animation_name, _life_elapsed)
		var frame := frames[index] as Dictionary if index >= 0 and index < frames.size() else {}
		var frame_rect := frame.get("rect", Rect2()) as Rect2
		var frame_anchor := frame.get("anchor", Vector2.ZERO) as Vector2
		overlays.append({
			"animation": animation_name,
			"node": String(entry.node),
			"anchor": entry.anchor,
			"drawn": _life_nodes.has(String(entry.node)),
			"fps": float(animation.get("fps", 0.0)),
			"frame_count": frames.size(),
			"frame_index": index,
			"frame_rect": frame_rect,
			"frame_size": Vector2i(int(frame_rect.size.x), int(frame_rect.size.y)),
			"frame_anchor": frame_anchor,
			"cell_in_native_view": Rect2(Vector2(entry.anchor as Vector2i) - frame_anchor, frame_rect.size),
		})
	return {
		"atlas_path": TITLE_LIFE_ATLAS_PATH,
		"status": life_status(),
		"reason": _life_reason,
		"drawn": life_drawn(),
		"time_seconds": _life_elapsed,
		"period_seconds": life_period(),
		"expected_period_seconds": LIFE_EXPECTED_PERIOD,
		"anchors": LIFE_ANCHORS.duplicate(),
		"overlays": overlays,
		"layer": "overlay Node2D in the same 640x360 integer-scaled world viewport",
	}


func _reset() -> void:
	_atlases = {}
	_sprites = {}
	_texture_meta = {}
	_textures = {}
	_pending_reasons.clear()
	_texture_reasons.clear()
	_pending_logged = false
	_plate_texture = null
	_plate_rect = Rect2(Vector2.ZERO, Vector2(TITLE_PLATE_SIZE))
	_plate_anchor = TITLE_PLATE_SIZE
	_plate_reason = ""
	_backdrop_source = BACKDROP_NONE
	_wanderer_node = null
	_plate_consulted = false
	_life_animations.clear()
	_life_nodes.clear()
	_life_elapsed = 0.0
	_life_reason = ""
	set_process(false)


func _read_json_object(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}


func _configure(atlases: Dictionary, layout: Dictionary) -> void:
	if world_root == null:
		_build_layers()
	if _plate_texture != null:
		## The produced plate is the whole title: no layout contract, no crop rules
		## and no layer sprite is drawn on top of it.
		_pending_reasons.clear()
		_texture_reasons.clear()
		_sprites = {}
		_layout = {}
		_field_size = Vector2(TITLE_PLATE_SIZE)
		_camera_offset = Vector2.ZERO
		_focus_feet = Vector2.ZERO
		_focus_from_layout = false
		_backdrop_source = BACKDROP_PLATE
		_rebuild_world()
		return
	_sprites = _collect_sprites(atlases)
	_textures = _load_textures()
	_layout = layout.duplicate(true) if not layout.is_empty() else _layout
	_field_size = _resolve_field_size()
	_resolve_camera()
	_backdrop_source = BACKDROP_LAYERS if _provisional_layers_available() else BACKDROP_NONE
	_rebuild_world()


func _provisional_layers_available() -> bool:
	return PROVISIONAL_LAYERS_WHEN_PLATE_MISSING and _pending_reasons.is_empty() and not _sprites.is_empty() and not _layout.is_empty()


func _load_title_plate() -> bool:
	## The plate is published like every other production package: an atlas with one
	## sprite cut from one texture. The bare PNG path stays the fallback for a tree
	## whose atlas has not been copied yet. Both paths demand the published native
	## size and a cell that covers the 640x360 frame: a plate that does neither would
	## have to be resampled, and this view never resamples pixel art.
	var atlas := _read_json_object(TITLE_PLATE_ATLAS_PATH)
	if not atlas.is_empty():
		return _load_plate_from_atlas(atlas)
	return _load_plate_from_png()


func _load_plate_from_atlas(atlas: Dictionary) -> bool:
	var declared: Variant = atlas.get("sprites", null)
	if not declared is Dictionary or not (declared as Dictionary).has(TITLE_PLATE_SPRITE_ID):
		_plate_reason = "atlas %s publishes no %s sprite" % [TITLE_PLATE_ATLAS_PATH, TITLE_PLATE_SPRITE_ID]
		return false
	var raw_entry: Variant = (declared as Dictionary)[TITLE_PLATE_SPRITE_ID]
	if not raw_entry is Dictionary:
		_plate_reason = "atlas %s sprite %s must be a dictionary" % [TITLE_PLATE_ATLAS_PATH, TITLE_PLATE_SPRITE_ID]
		return false
	var entry := raw_entry as Dictionary
	var rect: Variant = entry.get("rect", null)
	var anchor: Variant = entry.get("anchor", null)
	if not _integer_list(rect, 4) or int((rect as Array)[2]) <= 0 or int((rect as Array)[3]) <= 0:
		_plate_reason = "atlas %s declares a rect that is not four JSON integers with a positive size" % TITLE_PLATE_ATLAS_PATH
		return false
	if not _integer_list(anchor, 2) or int((anchor as Array)[0]) < 0 or int((anchor as Array)[1]) < 0:
		_plate_reason = "atlas %s declares an anchor that is not two non-negative JSON integers" % TITLE_PLATE_ATLAS_PATH
		return false
	var texture_key := String(entry.get("texture", ""))
	var declared_textures: Variant = atlas.get("textures", null)
	if not declared_textures is Dictionary or not (declared_textures as Dictionary).has(texture_key):
		_plate_reason = "atlas %s references unknown texture %s" % [TITLE_PLATE_ATLAS_PATH, texture_key]
		return false
	var raw_metadata: Variant = (declared_textures as Dictionary)[texture_key]
	if not raw_metadata is Dictionary:
		_plate_reason = "atlas %s texture %s must be a dictionary" % [TITLE_PLATE_ATLAS_PATH, texture_key]
		return false
	var metadata := raw_metadata as Dictionary
	var path := String(metadata.get("path", ""))
	var declared_size := Vector2i(int(metadata.get("width", 0)), int(metadata.get("height", 0)))
	var texture := _load_texture_at(path, declared_size)
	if texture == null:
		_plate_reason = "texture %s is missing or is not %s at %s" % [texture_key, declared_size, path]
		return false
	var plate_rect := Rect2(
		Vector2(float((rect as Array)[0]), float((rect as Array)[1])),
		Vector2(float((rect as Array)[2]), float((rect as Array)[3]))
	)
	if not Rect2(Vector2.ZERO, Vector2(texture.get_size())).encloses(plate_rect):
		_plate_reason = "rect %s leaves the %s texture" % [plate_rect, texture.get_size()]
		return false
	if not plate_rect.encloses(Rect2(Vector2.ZERO, Vector2(NATIVE_VIEW))):
		_plate_reason = "covers %s, the title frame is %s" % [plate_rect, NATIVE_VIEW]
		return false
	_plate_texture = texture
	_plate_rect = plate_rect
	_plate_anchor = Vector2i(int((anchor as Array)[0]), int((anchor as Array)[1]))
	return true


func _load_plate_from_png() -> bool:
	var texture := _load_texture_at(TITLE_PLATE_PATH, TITLE_PLATE_SIZE)
	if texture != null:
		_plate_texture = texture
		return true
	var decoded := _decode_png_path(TITLE_PLATE_PATH)
	if decoded == null:
		_plate_reason = "is not published at %s" % TITLE_PLATE_PATH
		return false
	_plate_reason = "is %s at %s, the title contract is %s" % [decoded.get_size(), TITLE_PLATE_PATH, TITLE_PLATE_SIZE]
	return false


func _load_texture_at(path: String, declared_size: Vector2i) -> Texture2D:
	## Imported resource first, raw PNG second: a tree whose import step has not
	## run yet still gets its plate, and a wrong size is refused either way.
	if path.is_empty() or declared_size.x <= 0 or declared_size.y <= 0:
		return null
	if ResourceLoader.exists(path):
		var imported := ResourceLoader.load(path) as Texture2D
		if imported != null:
			return imported if Vector2i(imported.get_size()) == declared_size else null
	var decoded := _decode_png_path(path)
	if decoded == null or decoded.get_size() != declared_size:
		return null
	var texture: Texture2D = ImageTexture.create_from_image(decoded)
	return texture


func _load_life_overlay() -> bool:
	## Reads the produced life package: two looping animations cut from their own
	## texture. A missing or malformed frame set leaves the overlay unproduced and
	## reported; no substitute flame is ever drawn in its place.
	_life_reason = ""
	var atlas := _read_json_object(TITLE_LIFE_ATLAS_PATH)
	if atlas.is_empty():
		_life_reason = "life atlas is not published at %s" % TITLE_LIFE_ATLAS_PATH
		return false
	var sprites: Variant = atlas.get("sprites", null)
	var declared_animations: Variant = atlas.get("animations", null)
	if not sprites is Dictionary or not declared_animations is Dictionary:
		_life_reason = "life atlas needs a sprites dictionary and an animations dictionary"
		return false
	var textures := _load_declared_textures(_atlas_textures(atlas))
	if textures.is_empty():
		return false
	for entry: Dictionary in LIFE_OVERLAYS:
		var animation_name := String(entry.animation)
		var raw_animation: Variant = (declared_animations as Dictionary).get(animation_name, null)
		if not raw_animation is Dictionary:
			_life_reason = "life atlas publishes no %s animation" % animation_name
			return false
		var animation := raw_animation as Dictionary
		if not bool(animation.get("loop", false)):
			_life_reason = "%s is not published as a loop" % animation_name
			return false
		var fps := float(animation.get("fps", 0.0))
		if fps <= 0.0:
			_life_reason = "%s declares fps %s" % [animation_name, fps]
			return false
		var raw_frames: Variant = animation.get("frames", null)
		if not raw_frames is Array or (raw_frames as Array).is_empty():
			_life_reason = "%s declares no frames" % animation_name
			return false
		var frames: Array[Dictionary] = []
		for raw_id: Variant in raw_frames as Array:
			var frame := _life_frame(String(raw_id), sprites as Dictionary, textures)
			if frame.is_empty():
				_life_reason = "%s frame %s could not be cut" % [animation_name, String(raw_id)]
				return false
			frames.append(frame)
		var expected := Vector2i(LIFE_EXPECTED_FRAMES.get(animation_name, Vector2i.ZERO))
		for frame: Dictionary in frames:
			var cell := (frame.rect as Rect2).size
			if expected != Vector2i.ZERO and Vector2i(cell) != expected:
				_life_reason = "%s frames are %s, the published cell is %s" % [animation_name, cell, expected]
				return false
		_life_animations[animation_name] = {"fps": fps, "frames": frames}
	if _life_animations.size() != LIFE_OVERLAYS.size() or life_period() <= 0.0:
		_life_reason = "the life package has no usable period"
		_life_animations.clear()
		return false
	return true


func _load_declared_textures(texture_meta: Dictionary) -> Dictionary:
	var result := {}
	for texture_key: String in texture_meta.keys():
		var metadata := texture_meta[texture_key] as Dictionary
		var path := String(metadata.get("path", ""))
		var expected := Vector2i(int(metadata.get("width", 0)), int(metadata.get("height", 0)))
		var texture := _load_texture_at(path, expected)
		if texture == null:
			_life_reason = "life texture %s is missing or is not %s at %s" % [texture_key, expected, path]
			return {}
		result[texture_key] = texture
	return result


func _life_frame(sprite_id: String, sprites: Dictionary, textures: Dictionary) -> Dictionary:
	if not sprites.has(sprite_id):
		return {}
	var raw_entry: Variant = sprites[sprite_id]
	if not raw_entry is Dictionary:
		return {}
	var entry := raw_entry as Dictionary
	var rect: Variant = entry.get("rect", null)
	var anchor: Variant = entry.get("anchor", null)
	if not _integer_list(rect, 4) or not _integer_list(anchor, 2):
		return {}
	var texture: Variant = textures.get(String(entry.get("texture", "")), null)
	if not texture is Texture2D:
		return {}
	return {
		"texture": texture,
		"rect": Rect2(
			Vector2(float((rect as Array)[0]), float((rect as Array)[1])),
			Vector2(float((rect as Array)[2]), float((rect as Array)[3]))
		),
		"anchor": Vector2(float((anchor as Array)[0]), float((anchor as Array)[1])),
	}


func _collect_sprites(atlases: Dictionary) -> Dictionary:
	var result := {}
	for group: String in SPRITE_ORDER:
		var atlas: Variant = atlases.get(group, null)
		if not atlas is Dictionary:
			continue
		var declared: Variant = (atlas as Dictionary).get("sprites", null)
		if not declared is Dictionary:
			_pending_reasons.append("atlas %s sprites must be a dictionary" % group)
			continue
		var texture_meta := _atlas_textures(atlas as Dictionary)
		for raw_id: Variant in (declared as Dictionary).keys():
			var sprite_id := String(raw_id)
			if result.has(sprite_id):
				continue
			var entry: Variant = (declared as Dictionary)[raw_id]
			if not entry is Dictionary:
				_pending_reasons.append("atlas %s sprite %s must be a dictionary" % [group, sprite_id])
				continue
			var accepted := _accept_sprite(group, sprite_id, entry as Dictionary, texture_meta)
			if not accepted.is_empty():
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
		_pending_reasons.append("%s sprite %s anchor must be two non-negative JSON integers" % [group, sprite_id])
		return {}
	var texture_key := String(entry.get("texture", ""))
	var metadata: Variant = texture_meta.get(texture_key, null)
	if not metadata is Dictionary:
		_pending_reasons.append("%s sprite %s references unknown texture %s" % [group, sprite_id, texture_key])
		return {}
	var qualified := "%s:%s" % [group, texture_key]
	_texture_meta[qualified] = (metadata as Dictionary).duplicate(true)
	return {"rect": rect, "anchor": anchor, "texture": qualified, "source": group}


func _load_textures() -> Dictionary:
	## The shipped build keeps the imported texture, so ResourceLoader is asked
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
		var decoded := _decode_png_path(path)
		if decoded == null:
			_texture_reasons.append("texture %s missing or not a decodable PNG at %s" % [texture_key, path])
			continue
		if decoded.get_size() != expected:
			_texture_reasons.append("texture %s is %s, atlas declares %s" % [texture_key, decoded.get_size(), expected])
			continue
		var image_texture: Texture2D = ImageTexture.create_from_image(decoded)
		result[texture_key] = image_texture
	return result


func _decode_png_path(path: String) -> Image:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var bytes := file.get_buffer(file.get_length())
	file.close()
	var image := Image.new()
	if image.load_png_from_buffer(bytes) != OK:
		return null
	return image


## ------------------------------------------------------------------ framing

func _resolve_field_size() -> Vector2:
	var metadata := _sprite_entry(_ground_sprite_id())
	if metadata.is_empty():
		return DEFAULT_FIELD_SIZE
	var rect := metadata.get("rect", []) as Array
	if rect.size() != 4:
		return DEFAULT_FIELD_SIZE
	return Vector2(float(rect[2]), float(rect[3]))


func _resolve_camera() -> void:
	## The crop is pinned to the layout's own tower placement; without it the view
	## falls back to the centre of the published field and says so.
	var feet := _placement_feet(FOCUS_PLACEMENT)
	## A missing placement answers with a non-finite pair, which is an honest
	## "this layout does not publish it" rather than a coordinate guess.
	_focus_from_layout = feet.is_finite()
	_focus_feet = feet if _focus_from_layout else _field_size * 0.5
	var wanted := _focus_feet - FOCUS_VIEW_POINT
	## Integer offsets keep every world pixel on the native grid.
	_camera_offset = Vector2(floorf(wanted.x), floorf(wanted.y))
	if _field_size.x >= float(NATIVE_VIEW.x):
		_camera_offset.x = clampf(_camera_offset.x, 0.0, _field_size.x - float(NATIVE_VIEW.x))
	if _field_size.y >= float(NATIVE_VIEW.y):
		_camera_offset.y = clampf(_camera_offset.y, 0.0, _field_size.y - float(NATIVE_VIEW.y))


func _placement_feet(placement_id: String) -> Vector2:
	for raw: Variant in _layout.get("placements", []) as Array:
		if not raw is Dictionary:
			continue
		var item := raw as Dictionary
		if String(item.get("id", "")) != placement_id:
			continue
		var feet: Variant = item.get("feet", null)
		if _integer_list(feet, 2):
			return Vector2(float((feet as Array)[0]), float((feet as Array)[1]))
	return Vector2(INF, INF)


func camera_offset() -> Vector2:
	return _camera_offset


func focus_feet() -> Vector2:
	return _focus_feet


func focus_from_layout() -> bool:
	return _focus_from_layout


func field_size() -> Vector2:
	return _field_size


func frame_report() -> Dictionary:
	## Everything the acceptance harness needs to judge the crop without owning
	## a second copy of the framing rules.
	var crop := Rect2(_camera_offset, Vector2(NATIVE_VIEW))
	var layered := _backdrop_source == BACKDROP_LAYERS
	var tower := _drawn_rect_in_view(FOCUS_PLACEMENT) if layered else Rect2()
	var has_tower := layered and not tower.size.is_zero_approx()
	return {
		"backdrop_source": _backdrop_source,
		"plate_status": plate_status(),
		"plate_path": TITLE_PLATE_PATH,
		"plate_size": TITLE_PLATE_SIZE,
		"plate_rect": _plate_rect,
		"plate_anchor": _plate_anchor,
		"focus_placement": FOCUS_PLACEMENT,
		"focus_from_layout": _focus_from_layout,
		"focus_world_feet": _focus_feet,
		"focus_view_point": FOCUS_VIEW_POINT,
		"camera_offset": _camera_offset,
		"integer_offset": _camera_offset == Vector2(floorf(_camera_offset.x), floorf(_camera_offset.y)),
		"field_size": _field_size,
		"crop": crop,
		"crop_inside_field": Rect2(Vector2.ZERO, _field_size).encloses(crop),
		"tower_rect_in_view": tower,
		"tower_available": has_tower,
		"tower_inside_view": has_tower and Rect2(Vector2.ZERO, Vector2(NATIVE_VIEW)).encloses(tower),
		"tower_feet_in_view": FOCUS_VIEW_POINT,
		"wanderer_view_point": WANDERER_VIEW_POINT,
		"wanderer_sprite_id": _wanderer_sprite_id(),
		"wanderer_drawn": _wanderer_node != null,
		"native_view": NATIVE_VIEW,
		"display_scale": DISPLAY_SCALE,
		"loop_status": loop_status(),
		"life": life_contract(),
	}


func _drawn_rect_in_view(placement_id: String) -> Rect2:
	var feet := _placement_feet(placement_id)
	if not feet.is_finite():
		return Rect2()
	var item := _placement(placement_id)
	var metadata := _sprite_entry(String(item.get("sprite", "")))
	if metadata.is_empty():
		return Rect2()
	var rect := metadata.get("rect", []) as Array
	var anchor := metadata.get("anchor", []) as Array
	if rect.size() != 4 or anchor.size() != 2:
		return Rect2()
	var cell := Rect2(feet - Vector2(float(anchor[0]), float(anchor[1])), Vector2(float(rect[2]), float(rect[3])))
	return Rect2(cell.position - _camera_offset, cell.size)


func _placement(placement_id: String) -> Dictionary:
	for raw: Variant in _layout.get("placements", []) as Array:
		if raw is Dictionary and String((raw as Dictionary).get("id", "")) == placement_id:
			return raw as Dictionary
	return {}


## ------------------------------------------------------------------ drawing

func _build_layers() -> void:
	if world_root != null:
		return
	## The backdrop is a still frame, but the viewport keeps redrawing so a late
	## texture import or a re-published layout never leaves a stale crop on screen.
	world_viewport = SubViewport.new()
	world_viewport.name = "TitleWorldViewport"
	world_viewport.size = NATIVE_VIEW
	world_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	world_viewport.snap_2d_transforms_to_pixel = true
	world_viewport.snap_2d_vertices_to_pixel = true
	world_viewport.transparent_bg = false
	add_child(world_viewport)

	var outside := ColorRect.new()
	outside.name = "SlateField"
	outside.color = SCENE_COLOR
	outside.set_anchors_preset(Control.PRESET_FULL_RECT)
	outside.mouse_filter = Control.MOUSE_FILTER_IGNORE
	world_viewport.add_child(outside)

	world_root = Node2D.new()
	world_root.name = "TitleWorldRoot"
	world_viewport.add_child(world_root)
	for layer_name: String in ["Field", "GroundLayer", "ObjectLower", "YSort", "LifeOverlay"]:
		var layer := Node2D.new()
		layer.name = layer_name
		world_root.add_child(layer)
	field_layer = world_root.get_node("Field") as Node2D
	ground_layer = world_root.get_node("GroundLayer") as Node2D
	object_lower_layer = world_root.get_node("ObjectLower") as Node2D
	actor_layer = world_root.get_node("YSort") as Node2D
	actor_layer.y_sort_enabled = true
	life_overlay_layer = world_root.get_node("LifeOverlay") as Node2D

	world_display = TextureRect.new()
	world_display.name = "TitleBackdropDisplay"
	world_display.texture = world_viewport.get_texture()
	world_display.stretch_mode = TextureRect.STRETCH_SCALE
	world_display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	world_display.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	world_display.set_anchors_preset(Control.PRESET_TOP_LEFT)
	world_display.custom_minimum_size = Vector2(NATIVE_VIEW)
	world_display.size = Vector2(NATIVE_VIEW)
	world_display.position = Vector2.ZERO
	world_display.scale = Vector2.ONE * float(DISPLAY_SCALE)
	world_display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(world_display)


func _rebuild_world() -> void:
	if world_root == null:
		return
	for layer: Node2D in [field_layer, ground_layer, object_lower_layer, actor_layer, life_overlay_layer]:
		_clear_children(layer)
	_wanderer_node = null
	_life_nodes.clear()
	_log_pending()
	if _backdrop_source == BACKDROP_NONE:
		set_process(false)
		return
	if _backdrop_source == BACKDROP_PLATE:
		world_root.position = Vector2.ZERO
		_draw_plate()
		_draw_life_overlay()
		set_process(life_drawn())
		return
	world_root.position = -_camera_offset
	_draw_ground_field()
	_draw_placements()
	_draw_wanderer()
	set_process(life_drawn())


func _draw_life_overlay() -> void:
	## Real published frames only, on the plate's own pixel anchors, inside the same
	## 640x360 layer that is already scaled by the integer 2x display.
	if life_overlay_layer == null or not life_ready() or _backdrop_source != BACKDROP_PLATE:
		return
	for entry: Dictionary in LIFE_OVERLAYS:
		var animation_name := String(entry.animation)
		var animation := _life_animations.get(animation_name, {}) as Dictionary
		var frames := animation.get("frames", []) as Array
		if frames.is_empty():
			continue
		var first := frames[0] as Dictionary
		var sprite := Sprite2D.new()
		sprite.name = String(entry.node)
		sprite.texture = first.texture as Texture2D
		sprite.centered = false
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.region_enabled = true
		sprite.region_rect = first.rect as Rect2
		sprite.position = Vector2(entry.anchor as Vector2i)
		sprite.offset = -(first.anchor as Vector2)
		sprite.set_meta("animation", animation_name)
		life_overlay_layer.add_child(sprite)
		_life_nodes[String(entry.node)] = sprite
	_update_life_frames()


func _update_life_frames() -> void:
	for node_name: String in _life_nodes.keys():
		var sprite := _life_nodes[node_name] as Sprite2D
		if sprite == null or not is_instance_valid(sprite):
			continue
		var animation_name := String(sprite.get_meta("animation", ""))
		var animation := _life_animations.get(animation_name, {}) as Dictionary
		var frames := animation.get("frames", []) as Array
		var index := life_frame_index(animation_name, _life_elapsed)
		if index < 0 or index >= frames.size():
			continue
		var frame := frames[index] as Dictionary
		sprite.texture = frame.texture as Texture2D
		sprite.region_rect = frame.rect as Rect2
		sprite.set_meta("frame_index", index)


func _process(delta: float) -> void:
	if not life_drawn():
		set_process(false)
		return
	_life_elapsed += delta
	_update_life_frames()


func _draw_plate() -> void:
	## One produced image at its own native size, drawn at the world origin and
	## shown 2x. Nothing is layered on top of it.
	## The plate is placed by its own published rect and anchor, so the declared
	## cell lands on the native view origin whatever anchor the atlas declares.
	_add_region_sprite(field_layer, "TitlePlate", _plate_texture, _plate_rect, Vector2(_plate_anchor), -Vector2(_plate_anchor))


func _draw_ground_field() -> void:
	## The ground is drawn at the world origin whatever anchor its sprite declares,
	## exactly like the hub, so the title crop shows the same surface.
	var metadata := _sprite_entry(_ground_sprite_id())
	if metadata.is_empty():
		return
	var texture := metadata.get("texture", null) as Texture2D
	var rect := metadata.get("rect", []) as Array
	if texture == null or rect.size() != 4:
		return
	var band := Rect2(Vector2(float(rect[0]), float(rect[1])), Vector2(float(rect[2]), float(rect[3])))
	_add_region_sprite(field_layer, "GroundField", texture, band, Vector2.ZERO, Vector2.ZERO)


func _draw_placements() -> void:
	for raw: Variant in _layout.get("placements", []) as Array:
		if not raw is Dictionary:
			continue
		var item := raw as Dictionary
		var placement_id := String(item.get("id", ""))
		if placement_id.is_empty() or String(item.get("sprite", "")).is_empty():
			continue
		if String(item.get("layer", LAYER_OBJECT)) == LAYER_GROUND:
			_add_sprite(ground_layer, item, 0, -1, "Ground_%s" % placement_id)
			continue
		var split_row := int(item.get("split_row", 0))
		if split_row <= 0:
			_add_sprite(actor_layer, item, 0, -1, "Object_%s" % placement_id)
			continue
		## Image rows grow downward: the solid foot stays under the feet-sorted
		## layer, only the standing band joins it, exactly like the live hub.
		_add_sprite(object_lower_layer, item, split_row, -1, "Lower_%s" % placement_id)
		_add_sprite(actor_layer, item, 0, split_row, "Upper_%s" % placement_id)


func _draw_wanderer() -> void:
	var metadata := _sprite_entry(_wanderer_sprite_id())
	if metadata.is_empty():
		return
	var texture := metadata.get("texture", null) as Texture2D
	var rect := metadata.get("rect", []) as Array
	var anchor := metadata.get("anchor", []) as Array
	if texture == null or rect.size() != 4 or anchor.size() != 2:
		return
	var feet := WANDERER_VIEW_POINT + _camera_offset
	var sprite := Sprite2D.new()
	sprite.name = "Wanderer"
	sprite.set_meta("sprite_id", _wanderer_sprite_id())
	sprite.texture = texture
	sprite.centered = false
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.region_enabled = true
	sprite.region_rect = Rect2(Vector2(float(rect[0]), float(rect[1])), Vector2(float(rect[2]), float(rect[3])))
	sprite.position = feet
	sprite.offset = Vector2(-float(anchor[0]), -float(anchor[1]))
	actor_layer.add_child(sprite)
	_wanderer_node = sprite


func _add_sprite(parent: Node2D, item: Dictionary, row_start: int, row_end: int, node_name: String) -> Sprite2D:
	## One sprite, its own rect and anchor, optional split_row crop, clipped to the
	## published field. No cell size is ever assumed.
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
	var feet: Variant = item.get("feet", null)
	if not _integer_list(feet, 2):
		return null
	var band := _clip_band(Vector2(float((feet as Array)[0]), float((feet as Array)[1])), rect, anchor, top, bottom)
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
	sprite.position = Vector2(float((feet as Array)[0]), float((feet as Array)[1]))
	sprite.offset = band.offset
	parent.add_child(sprite)
	return sprite


func _add_region_sprite(parent: Node2D, node_name: String, texture: Texture2D, band: Rect2, position: Vector2, offset: Vector2) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.name = node_name
	sprite.texture = texture
	sprite.centered = false
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.region_enabled = true
	sprite.region_rect = band
	sprite.position = position
	sprite.offset = offset
	parent.add_child(sprite)
	return sprite


func _clip_band(feet: Vector2, rect: Array, anchor: Array, row_start: int, row_end: int) -> Dictionary:
	var cell := Rect2(feet - Vector2(float(anchor[0]), float(anchor[1])), Vector2(float(rect[2]), float(rect[3])))
	var band := Rect2(cell.position + Vector2(0.0, float(row_start)), Vector2(cell.size.x, float(row_end - row_start)))
	var visible := band.intersection(Rect2(Vector2.ZERO, _field_size))
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


## ------------------------------------------------------------------- lookup

func _ground_sprite_id() -> String:
	var wanted := String(_layout.get("ground_sprite", ""))
	if wanted.is_empty():
		wanted = DEFAULT_GROUND_ID
	var order: Array = GROUND_ORDER if wanted == DEFAULT_GROUND_ID else SPRITE_ORDER
	var resolved := _resolve_sprite_id(wanted, order)
	if resolved.is_empty():
		resolved = _resolve_sprite_id(GROUND_SPRITE_FALLBACK, SPRITE_ORDER)
	if resolved.is_empty():
		resolved = _resolve_sprite_id(DEFAULT_GROUND_ID, GROUND_ORDER)
	return resolved


func _wanderer_sprite_id() -> String:
	## Same fallback order as the hub hero: the facing the title asks for first,
	## then the hub's own default facing.
	var wanted := String(WANDERER_FACING_IDS.get(WANDERER_FACING, WANDERER_FACING_IDS["south"]))
	if _sprites.has(wanted):
		return wanted
	var fallback := String(WANDERER_FACING_IDS["south"])
	return fallback if _sprites.has(fallback) else ""


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


func _log_pending() -> void:
	if _pending_logged:
		return
	_pending_logged = true
	if _plate_consulted and _plate_texture == null:
		var detail := plate_reason()
		if detail.is_empty():
			detail = "is not published at %s" % TITLE_PLATE_PATH
		var suffix := ""
		if _backdrop_source == BACKDROP_LAYERS:
			suffix = " (showing the provisional layered crop of published production sprites)"
		printerr("ASSETS PENDING p1_title_runtime_v02: produced title plate %s%s" % [detail, suffix])
	for reason: String in pending_reasons():
		printerr("ASSETS PENDING p1_title_runtime_v02: " + reason)


## ------------------------------------------------------------- test support

func replace_textures_for_test(source: Dictionary) -> void:
	## Tests only: an in-memory atlas still has to prove it renders, so the decoded
	## image is supplied directly instead of being read from disk.
	for texture_key: String in source.keys():
		var value: Variant = source[texture_key]
		if value is Texture2D:
			_textures[texture_key] = value
	_rebuild_world()


func render_audit() -> Dictionary:
	var layers := {"field": 0, "ground": 0, "object_lower": 0, "actors": 0}
	if field_layer != null:
		layers["field"] = field_layer.get_child_count()
	if ground_layer != null:
		layers["ground"] = ground_layer.get_child_count()
	if object_lower_layer != null:
		layers["object_lower"] = object_lower_layer.get_child_count()
	if actor_layer != null:
		layers["actors"] = actor_layer.get_child_count()
	return {
		"ready": is_ready(),
		"backdrop_source": _backdrop_source,
		"plate_status": plate_status(),
		"pending": _pending_reasons.duplicate(),
		"texture_pending": _texture_reasons.duplicate(),
		"layers": layers,
		"camera_offset": _camera_offset,
		"field_size": _field_size,
		"wanderer": _wanderer_node.name if _wanderer_node != null else "",
		"sprite_nodes": _sprite_node_names(),
		"loop_status": loop_status(),
		"life_status": life_status(),
		"life_drawn": life_drawn(),
		"life_reason": _life_reason,
		"life_nodes": _life_nodes.keys(),
		"life_time": _life_elapsed,
		"life_period": life_period(),
	}


func _sprite_node_names() -> Array[String]:
	var names: Array[String] = []
	for layer: Node2D in [ground_layer, object_lower_layer, actor_layer]:
		if layer == null:
			continue
		for child in layer.get_children():
			names.append(child.name)
	return names


func native_image() -> Image:
	## The 640x360 native frame, for the capture harness' pixel checks. Headless
	## sessions have no rendered viewport, so this returns null there.
	if world_viewport == null:
		return null
	var texture := world_viewport.get_texture()
	if texture == null:
		return null
	var image := texture.get_image()
	return image if image != null and not image.is_empty() else null


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


static func whole_number(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) != TYPE_FLOAT:
		return false
	var number := float(value)
	return is_finite(number) and number == floor(number)
