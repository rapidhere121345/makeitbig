class_name TutorialArt
extends RefCounted
## Production art for the tutorial training arena, read strictly from the
## published JSON atlases (2026-09-14 tutorial landing pass).
##
## Roles and their approved sources:
## - hero: scene_rework_v01 `ranger.<facing>.idle`, 32x48 cells anchored at
##   (16,44). Drawn at the slice's native 2x presentation scale (64x96) and
##   placed by its foot point, never by its centre.
## - the single melee target: calibration_v01 `enemy.melee.idle`, 48x48 cell
##   anchored at (24,44), drawn at 2x. The tutorial target keeps the melee
##   enemy's identity; a training-dummy stand-in would change what the
##   checklist asks the player to hit, so it is not allowed here.
## - floor: the approved ground_refine_v01 ground.png, used as an integer 2x
##   window that covers the arena. The 1024-wide sheet is never scaled down to
##   the arena's display width.
##
## Every cell is read from the atlas JSON and then checked against its approved
## cell contract, so nothing is cropped by a hard-coded position. Any missing
## file, malformed entry or disagreement with the published metadata leaves the
## loader invalid and reports the reason: the arena then draws its gameplay
## layer alone instead of faking a character out of polygons.

const RangerAnimationScript = preload("res://src/presentation/ranger_animation.gd")

const NATIVE_VIEW := Vector2i(640, 360)
## Art pixels are shown at integer 2x throughout this slice.
const SCALE := 2

const RANGER_ATLAS_PATH := "res://art/production/p1/scene_rework_v01/atlas.json"
const TARGET_ATLAS_PATH := "res://art/production/p1/calibration_v01/atlas.json"
const GROUND_ATLAS_PATH := "res://art/production/p1/ground_refine_v01/atlas.json"
const RANGER_TEXTURE_PATH := "res://art/production/p1/scene_rework_v01/ranger.png"
const TARGET_TEXTURE_PATH := "res://art/production/p1/calibration_v01/enemies.png"
const GROUND_TEXTURE_PATH := "res://art/production/p1/ground_refine_v01/ground.png"

const RANGER_FACING_SPRITES := {
	"east": "ranger.east.idle",
	"north": "ranger.north.idle",
	"south": "ranger.south.idle",
	"west": "ranger.west.idle",
}
const RANGER_CELL := Vector2i(32, 48)
const RANGER_ANCHOR := Vector2i(16, 44)
const TARGET_SPRITE_ID := "enemy.melee.idle"
const TARGET_CELL := Vector2i(48, 48)
const TARGET_ANCHOR := Vector2i(24, 44)
const GROUND_SPRITE_ID := "scene.ground"
const GROUND_CELL := Vector2i(1024, 640)

var valid := false
var pending_reasons: Array[String] = []
## sprite id -> { rect: Rect2i, anchor: Vector2i, texture_key, texture_path,
## texture_size }, only ever filled from a validated atlas entry.
var sprites := {}
## Shared ranger action reader. The approved four-way idle cells above stay the
## arena's explicit fallback while the action atlas is pending or broken; this
## reader never substitutes art, it only reports which frame the state asks for.
var ranger_animation
var _texture_meta := {}
var _images := {}


func _init(load_images := true, path_overrides: Dictionary = {}) -> void:
	## path_overrides is for tests: pointing a role at a missing or malformed
	## atlas has to exercise the ASSETS PENDING path, not a special case.
	var ranger_atlas := _read_atlas(String(path_overrides.get("ranger", RANGER_ATLAS_PATH)), "scene_rework_v01")
	var target_atlas := _read_atlas(String(path_overrides.get("target", TARGET_ATLAS_PATH)), "calibration_v01")
	var ground_atlas := _read_atlas(String(path_overrides.get("ground", GROUND_ATLAS_PATH)), "ground_refine_v01")
	if not ranger_atlas.is_empty():
		for facing in RANGER_FACING_SPRITES.keys():
			_take_sprite(
				ranger_atlas, String(RANGER_FACING_SPRITES[facing]),
				RANGER_CELL, RANGER_ANCHOR, RANGER_TEXTURE_PATH, String(facing), false
			)
	if not target_atlas.is_empty():
		_take_sprite(target_atlas, TARGET_SPRITE_ID, TARGET_CELL, TARGET_ANCHOR, TARGET_TEXTURE_PATH, "", false)
	if not ground_atlas.is_empty():
		_take_sprite(ground_atlas, GROUND_SPRITE_ID, GROUND_CELL, null, GROUND_TEXTURE_PATH, "", true)
	_validate()
	if valid and load_images:
		_load_images()
	ranger_animation = RangerAnimationScript.new(
		load_images,
		{"atlas": String(path_overrides.get("actions", RangerAnimationScript.ATLAS_PATH))}
	)


## True only when every approved cell and every approved texture is present and
## agrees with the published atlas.
func has_real_art() -> bool:
	return valid and _images.size() == 3 and _texture_meta.size() == 3


func pending_reason() -> String:
	return "; ".join(PackedStringArray(pending_reasons))


func sprite(sprite_id: String) -> Dictionary:
	var entry := (sprites.get(sprite_id, {}) as Dictionary).duplicate(true)
	if entry.is_empty():
		return {}
	entry["_texture"] = _images.get(String(entry.get("texture_key", "")))
	return entry


func ranger_sprite(facing: Vector2) -> Dictionary:
	var sprite_id: Variant = RANGER_FACING_SPRITES.get(facing_key(facing), null)
	if sprite_id == null:
		return {}
	return sprite(sprite_id)


## The shared action reader, so the arena and the base hub read the same atlas
## the same way.
func ranger_animation_reader():
	return ranger_animation


## Resolves one ranger frame. The answer is explicit: fallback == true means the
## caller draws the approved static cell above, and the reason names the cause.
func ranger_action_frame(state: Dictionary) -> Dictionary:
	if ranger_animation == null:
		return {}
	return ranger_animation.resolve(state)


## Reported separately from the three approved roles: a late action atlas must
## neither blank the arena nor pass as delivered art.
func ranger_action_pending_reasons() -> Array[String]:
	if ranger_animation == null:
		return ["ASSETS PENDING: no ranger action reader"]
	return ranger_animation.pending_reasons()


func target_sprite() -> Dictionary:
	return sprite(TARGET_SPRITE_ID)


func ground_sprite() -> Dictionary:
	return sprite(GROUND_SPRITE_ID)


func ground_texture() -> Texture2D:
	var entry := sprites.get(GROUND_SPRITE_ID, {}) as Dictionary
	return _images.get(String(entry.get("texture_key", "")))


## The integer 2x window of the approved ground sheet that covers the arena.
func ground_crop_rect(arena_size: Vector2i) -> Rect2i:
	var entry := sprites.get(GROUND_SPRITE_ID, {}) as Dictionary
	if entry.is_empty():
		return Rect2i()
	return crop_rect_for(arena_size, entry.get("texture_size", Vector2i.ZERO) as Vector2i, SCALE)


## Centred, integer, and never a downscale: the window is at most the sheet, so
## an 856x480 arena reads a 428x240 crop at 2x instead of squeezing 1024px.
static func crop_rect_for(arena_size: Vector2i, texture_size: Vector2i, scale: int) -> Rect2i:
	if scale <= 0 or arena_size.x <= 0 or arena_size.y <= 0:
		return Rect2i()
	var crop := Vector2i(ceili(float(arena_size.x) / float(scale)), ceili(float(arena_size.y) / float(scale)))
	if texture_size.x < crop.x or texture_size.y < crop.y:
		return Rect2i()
	return Rect2i(
		Vector2i(floori(float(texture_size.x - crop.x) / 2.0), floori(float(texture_size.y - crop.y) / 2.0)),
		crop
	)


## Screen-snapped top-left pixel for a cell placed by a world foot point. The
## caller's simulation coordinates are never modified; only the drawn origin is
## snapped into the art's own pixel grid.
static func sprite_origin(feet: Vector2, anchor: Vector2i, scale: int) -> Vector2:
	return Vector2(roundf(feet.x - float(anchor.x * scale)), roundf(feet.y - float(anchor.y * scale)))


## Four-way facing bucket for the idle cells. Screen space: +y points down.
static func facing_key(facing: Vector2) -> String:
	if facing.length_squared() <= 0.0001:
		return "south"
	if absf(facing.x) >= absf(facing.y):
		return "east" if facing.x > 0.0 else "west"
	return "north" if facing.y < 0.0 else "south"


func _read_atlas(path: String, label: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		pending_reasons.append("ASSETS PENDING: %s (%s atlas)" % [path, label])
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		pending_reasons.append("ASSETS PENDING: cannot open %s (%s atlas)" % [path, label])
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		pending_reasons.append("ASSETS PENDING: invalid JSON in %s (%s atlas)" % [path, label])
		return {}
	var atlas := parsed as Dictionary
	if int(atlas.get("schema_version", 0)) != 1:
		pending_reasons.append("%s atlas schema_version must be 1" % label)
	var native := atlas.get("native_view", []) as Array
	if native.size() != 2 or Vector2i(int(native[0]), int(native[1])) != NATIVE_VIEW:
		pending_reasons.append("%s atlas native_view must be [640,360]" % label)
	return atlas


func _take_sprite(
	atlas: Dictionary,
	sprite_id: String,
	cell: Vector2i,
	anchor: Variant,
	texture_path: String,
	facing: String,
	require_full_sheet: bool
) -> void:
	var raw: Variant = (atlas.get("sprites", {}) as Dictionary).get(sprite_id, null)
	if typeof(raw) != TYPE_DICTIONARY:
		pending_reasons.append("sprite %s is missing from its approved atlas" % sprite_id)
		return
	var entry := raw as Dictionary
	var rect_values := entry.get("rect", []) as Array
	var anchor_values := entry.get("anchor", []) as Array
	if not _integer_list(rect_values, 4) or not _integer_list(anchor_values, 2):
		pending_reasons.append("sprite %s requires integer rect[4] / anchor[2]" % sprite_id)
		return
	var cell_rect := Rect2i(
		Vector2i(int(rect_values[0]), int(rect_values[1])),
		Vector2i(int(rect_values[2]), int(rect_values[3]))
	)
	var cell_anchor := Vector2i(int(anchor_values[0]), int(anchor_values[1]))
	if cell_rect.size != cell:
		pending_reasons.append("sprite %s violates its %s cell contract" % [sprite_id, str(cell)])
		return
	if anchor is Vector2i and cell_anchor != anchor:
		pending_reasons.append("sprite %s violates its %s anchor contract" % [sprite_id, str(anchor)])
		return
	if cell_rect.position.x % cell.x != 0 or cell_rect.position.y % cell.y != 0:
		pending_reasons.append("sprite %s cell is not grid aligned" % sprite_id)
		return
	if not facing.is_empty() and String(entry.get("facing", "")) != facing:
		pending_reasons.append("sprite %s does not declare its %s facing" % [sprite_id, facing])
		return
	var texture_key := String(entry.get("texture", ""))
	var texture_meta := (atlas.get("textures", {}) as Dictionary).get(texture_key, {}) as Dictionary
	if texture_meta.is_empty():
		pending_reasons.append("sprite %s references unknown texture %s" % [sprite_id, texture_key])
		return
	if String(texture_meta.get("path", "")) != texture_path:
		pending_reasons.append("sprite %s must come from %s" % [sprite_id, texture_path])
		return
	var texture_size := Vector2i(int(texture_meta.get("width", 0)), int(texture_meta.get("height", 0)))
	if texture_size.x <= 0 or texture_size.y <= 0 or not Rect2i(Vector2i.ZERO, texture_size).encloses(cell_rect):
		pending_reasons.append("sprite %s cell lies outside its texture" % sprite_id)
		return
	if require_full_sheet and (cell_rect.position != Vector2i.ZERO or cell_rect.size != texture_size):
		pending_reasons.append("sprite %s must be the full published sheet" % sprite_id)
		return
	if _texture_meta.has(texture_key) and _texture_meta[texture_key] != texture_meta:
		pending_reasons.append("texture %s is described twice with different metadata" % texture_key)
		return
	_texture_meta[texture_key] = texture_meta.duplicate(true)
	sprites[sprite_id] = {
		"rect": cell_rect,
		"anchor": cell_anchor,
		"texture_key": texture_key,
		"texture_path": texture_path,
		"texture_size": texture_size,
	}


func _validate() -> void:
	var reasons := pending_reasons.duplicate()
	for sprite_id in RANGER_FACING_SPRITES.values():
		if not sprites.has(String(sprite_id)):
			reasons.append("missing sprite metadata: %s" % String(sprite_id))
	for sprite_id: String in [TARGET_SPRITE_ID, GROUND_SPRITE_ID]:
		if not sprites.has(sprite_id):
			reasons.append("missing sprite metadata: %s" % sprite_id)
	for texture_key in _texture_meta.keys():
		var meta := _texture_meta[texture_key] as Dictionary
		if not String(meta.get("path", "")).begins_with("res://"):
			reasons.append("texture %s path must be res://" % texture_key)
		if int(meta.get("width", 0)) <= 0 or int(meta.get("height", 0)) <= 0:
			reasons.append("texture %s requires positive dimensions" % texture_key)
	pending_reasons = reasons
	valid = pending_reasons.is_empty()


func _load_images() -> void:
	for texture_key in _texture_meta.keys():
		var meta := _texture_meta[texture_key] as Dictionary
		var path := String(meta.get("path", ""))
		var expected := Vector2i(int(meta.get("width", 0)), int(meta.get("height", 0)))
		# Release packs contain imported textures, not necessarily source PNGs.
		if ResourceLoader.exists(path, "Texture2D"):
			var imported := ResourceLoader.load(path, "Texture2D") as Texture2D
			if imported != null and Vector2i(imported.get_size()) == expected:
				_images[texture_key] = imported
				continue
		var file := _open_resource(path)
		var image := Image.new()
		if file == null or file.get_length() == 0 or image.load_png_from_buffer(file.get_buffer(file.get_length())) != OK:
			pending_reasons.append("ASSETS PENDING: cannot load %s" % path)
			continue
		if image.get_size() != expected:
			pending_reasons.append("%s is %s, the atlas says %s (stale metadata?)" % [path, str(image.get_size()), str(expected)])
			continue
		_images[texture_key] = ImageTexture.create_from_image(image)
	valid = pending_reasons.is_empty() and _images.size() == _texture_meta.size() and _texture_meta.size() == 3


## Raw-file fallback for an unimported development tree. Imported PNG resources
## are handled above; globalizing a missing raw PNG cannot recreate it in a PCK.
func _open_resource(path: String) -> FileAccess:
	var file := FileAccess.open(path, FileAccess.READ)
	if file != null:
		return file
	return FileAccess.open(ProjectSettings.globalize_path(path), FileAccess.READ)


func _integer_list(value: Variant, count: int) -> bool:
	if not value is Array or (value as Array).size() != count:
		return false
	for number in value as Array:
		if typeof(number) not in [TYPE_INT, TYPE_FLOAT]:
			return false
		if not is_finite(float(number)) or float(number) != floor(float(number)):
			return false
	return true
