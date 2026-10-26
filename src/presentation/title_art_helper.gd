class_name TitleArtHelper
extends Control
## Title backdrop: a dedicated production plate plus real fire/steam frames,
## rendered at native 640x360 and shown at nearest integer scale. The UI has
## its own display-space layer, independent of the pixel-art transform.
##
## The view owns no art of its own. The plate and every life frame are cuts of a
## published production texture, read through an atlas.json contract. While the
## plate is unpublished the backdrop stays the flat slate field and the reason is
## reported once as ASSETS PENDING: a missing texture is never replaced by a
## stand-in drawing.
##
## title_life_v01 supplies four fire frames and four cooking-steam frames.
## Other environmental loops and ranger movement remain unproduced; static
## frames never stand in for a complete walk cycle.

const NATIVE_VIEW := Vector2i(640, 360)
const DISPLAY_SCALE := 2
const DISPLAY_SIZE := Vector2i(1280, 720)

## The produced, word-free title plate. Contract: native 640x360, drawn 1:1 into
## the 640x360 viewport and shown at nearest integer 2x, so the 1280x720 UI layer
## never resamples it and the left menu column never covers the tower.
const TITLE_PLATE_PATH := "res://art/production/p1/title_concept_v02/background.png"
const TITLE_PLATE_SIZE := Vector2i(640, 360)
const TITLE_PLATE_ATLAS_PATH := "res://art/production/p1/title_concept_v02/atlas.json"
const TITLE_PLATE_SPRITE_ID := "title.background"
const PLATE_STATUS_READY := "ready"
const PLATE_STATUS_PENDING := "pending"

## Backdrop sources. The produced plate is the title as approved; with no plate
## the backdrop is the flat slate field and the reason is reported.
const BACKDROP_PLATE := "plate"
const BACKDROP_NONE := "none"

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
var world_display: TextureRect

var _pending_reasons: Array[String] = []
var _pending_logged: bool = false

var _plate_texture: Texture2D
var _plate_rect: Rect2 = Rect2(Vector2.ZERO, Vector2(TITLE_PLATE_SIZE))
var _plate_anchor: Vector2i = TITLE_PLATE_SIZE
var _plate_reason: String = ""
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
	## Reads the published plate and life package from disk. A missing or
	## half-authored file leaves the view pending, which the title renders as the
	## plain slate field.
	_reset()
	_load_title_plate()
	_load_life_overlay()
	_configure()
	return is_ready()


## Fixture entry point: nothing is published, so the view renders the flat slate
## field and reports why. Nothing is read from disk.
func withdraw_assets_for_test() -> void:
	_reset()
	_configure()


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
	return _pending_reasons.duplicate()


func loop_status() -> String:
	return life_status()


func loop_ready() -> bool:
	return life_ready()


func life_status() -> String:
	return LOOP_STATUS_READY if life_ready() else LOOP_STATUS_UNPRODUCED


func life_ready() -> bool:
	return _life_animations.size() == LIFE_OVERLAYS.size() and _life_reason.is_empty()


func life_drawn() -> bool:
	## The overlay is authored against the produced plate's own pixels, so it is
	## only drawn on that backdrop.
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
	_pending_reasons.clear()
	_pending_logged = false
	_plate_texture = null
	_plate_rect = Rect2(Vector2.ZERO, Vector2(TITLE_PLATE_SIZE))
	_plate_anchor = TITLE_PLATE_SIZE
	_plate_reason = ""
	_backdrop_source = BACKDROP_NONE
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


func _configure() -> void:
	if world_root == null:
		_build_layers()
	if _plate_texture == null:
		var detail := _plate_reason
		if detail.is_empty():
			detail = "is not published at %s" % TITLE_PLATE_ATLAS_PATH
		_pending_reasons.append("produced title plate %s" % detail)
		_backdrop_source = BACKDROP_NONE
		_rebuild_world()
		return
	## The produced plate is the whole title: no layer sprite is drawn on top of it.
	_backdrop_source = BACKDROP_PLATE
	_rebuild_world()


func _load_title_plate() -> bool:
	## The plate is published like every other production package: an atlas with one
	## sprite cut from one texture. It demands the published native size and a cell
	## that covers the 640x360 frame: a plate that does neither would have to be
	## resampled, and this view never resamples pixel art.
	var atlas := _read_json_object(TITLE_PLATE_ATLAS_PATH)
	if atlas.is_empty():
		_plate_reason = "atlas %s is missing or not a JSON object" % TITLE_PLATE_ATLAS_PATH
		return false
	return _load_plate_from_atlas(atlas)


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

func frame_report() -> Dictionary:
	## Everything the acceptance harness needs to judge the frame without owning
	## a second copy of the framing rules.
	return {
		"backdrop_source": _backdrop_source,
		"plate_status": plate_status(),
		"plate_path": TITLE_PLATE_PATH,
		"plate_size": TITLE_PLATE_SIZE,
		"plate_rect": _plate_rect,
		"plate_anchor": _plate_anchor,
		"native_view": NATIVE_VIEW,
		"display_scale": DISPLAY_SCALE,
		"loop_status": loop_status(),
		"life": life_contract(),
	}


## ------------------------------------------------------------------ drawing

func _build_layers() -> void:
	if world_root != null:
		return
	## The backdrop is a still frame, but the viewport keeps redrawing so a late
	## texture import never leaves a stale frame on screen.
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
	for layer_name: String in ["Field", "LifeOverlay"]:
		var layer := Node2D.new()
		layer.name = layer_name
		world_root.add_child(layer)
	field_layer = world_root.get_node("Field") as Node2D
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
	for layer: Node2D in [field_layer, life_overlay_layer]:
		_clear_children(layer)
	_life_nodes.clear()
	_log_pending()
	if _backdrop_source == BACKDROP_NONE:
		set_process(false)
		return
	world_root.position = Vector2.ZERO
	_draw_plate()
	_draw_life_overlay()
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


## ---------------------------------------------------------------- reporting

func _log_pending() -> void:
	if _pending_logged:
		return
	_pending_logged = true
	for reason: String in pending_reasons():
		printerr("ASSETS PENDING p1_title_runtime_v02: " + reason)


## ------------------------------------------------------------- test support

func render_audit() -> Dictionary:
	var layers := {"field": 0}
	if field_layer != null:
		layers["field"] = field_layer.get_child_count()
	return {
		"ready": is_ready(),
		"backdrop_source": _backdrop_source,
		"plate_status": plate_status(),
		"pending": _pending_reasons.duplicate(),
		"layers": layers,
		"loop_status": loop_status(),
		"life_status": life_status(),
		"life_drawn": life_drawn(),
		"life_reason": _life_reason,
		"life_nodes": _life_nodes.keys(),
		"life_time": _life_elapsed,
		"life_period": life_period(),
	}


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
