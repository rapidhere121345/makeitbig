class_name HamletLifeAnimation
extends RefCounted
## Published hamlet life package reader for the base hub: the resident work
## cycles and the two socket effects the approved concept asks for.
##
## Contract (res://art/production/p1/actors_v02/residents/):
##   atlas.json -> schema_version 1, textures {key: {path, width, height}},
##                 sprites {id: {rect [x,y,w,h], anchor [ax,ay], texture}},
##                 animations {"<resident>.south.work": {frames, fps, loop}},
##                 four 48x48 cells anchored at [24,44] per resident, integer
##                 work speeds (mira 3, iven/taren/leia 2, oren 4 fps).
##   life.json  -> schema_version 1, residents [{placement, clip, phase}],
##                 effects [{id, owner, clip, offset, phase, layer?}], phases in
##                 seconds.
## The socket sheet is the approved title_life_v01 pair reused verbatim:
## life.fire (8x10, anchor [4,9], 4 fps) and life.steam (12x18, anchor [6,17],
## 2 fps) - the alpha and cadence the title card already ships.
##
## A socket offset is measured from the owner's own feet in world units, exactly
## like a placement, so the hub's feet sort keeps working; the clip's own anchor
## places the cell on that point. Nothing here is a substitute: a package that
## is missing or half-authored leaves the approved residents static on the
## layout and reports why. The clock is a presentation clock only - reading a
## life package never reads, writes or blocks gameplay state.
##
## The reader validates shape and structure (paths, arrays, rects, anchors, fps,
## bands) and publishes every approved number in life_report(); the exact cell,
## anchor, frame count and cadence are pinned by tests/unit/test_hamlet_life_animation.gd.

const LIFE_DIR := "res://art/production/p1/actors_v02/residents/"
const JsonIO := preload("res://src/core/json_io.gd")
const TextureLoader := preload("res://src/presentation/art/texture_loader.gd")
const LIFE_ATLAS_PATH := LIFE_DIR + "atlas.json"
const LIFE_MANIFEST_PATH := LIFE_DIR + "life.json"
const SCHEMA_VERSION := 1
const RESIDENT_CLIP_SUFFIX := ".south.work"
const RESIDENT_CELL := Vector2i(48, 48)
const RESIDENT_ANCHOR := Vector2i(24, 44)
const RESIDENT_FRAMES := 4
## A published loop that repeats one cell is not a cycle: two distinct cells is
## the floor the reader accepts, one distinct cell is refused as an art error.
const MIN_UNIQUE_FRAMES := 2
## A clock that accumulates 1/30 or 1/144 steps lands a hair below an exact
## frame boundary; this epsilon keeps the step count rate-independent without
## ever pulling a frame early by a measurable amount.
const CLOCK_EPSILON := 0.000000001

const EFFECT_ATLAS_PATH := "res://art/production/p1/title_life_v01/atlas.json"
const EFFECT_CLIPS: Array[String] = ["life.fire", "life.steam"]
const EFFECT_CELLS := {"life.fire": Vector2i(8, 10), "life.steam": Vector2i(12, 18)}
const EFFECT_ANCHORS := {"life.fire": Vector2i(4, 9), "life.steam": Vector2i(6, 17)}
const EFFECT_FRAMES := 4

const LAYER_LOWER := "lower"
const LAYER_UPPER := "upper"
const EFFECT_LAYERS: Array[String] = [LAYER_LOWER, LAYER_UPPER]
## A socket that declares no band joins the feet-sorted layer and inherits its
## owner's split fade, which can never draw over the avatar; "lower" opts into
## the owner's own solid band instead, drawn exactly like the stand's foot.
const DEFAULT_EFFECT_LAYER := LAYER_UPPER

var _clips: Dictionary = {}
var _residents: Array[Dictionary] = []
var _effects: Array[Dictionary] = []
var _pending: Array[String] = []
var _time := 0.0
var _art := false
var _effects_ready := false


## ------------------------------------------------------------------- loading

func load_default_assets() -> bool:
	return load_assets_at(LIFE_DIR)


func load_assets_at(directory: String) -> bool:
	## Reads the published life pair and the approved socket sheet. A missing or
	## half-authored file leaves the reader empty and the hub on its static art.
	configure(JsonIO.read_object(directory.path_join("atlas.json")), JsonIO.read_object(directory.path_join("life.json")), JsonIO.read_object(EFFECT_ATLAS_PATH))
	return has_real_art()


func configure(resident_atlas: Dictionary, manifest: Dictionary, effect_atlas: Dictionary) -> void:
	## Fixture entry point: every contract already in memory, nothing else read.
	clear()
	if manifest.is_empty():
		_pending.append("life.json is missing or is not a JSON object at %s" % LIFE_MANIFEST_PATH)
	elif resident_atlas.is_empty():
		_pending.append("life atlas is missing or is not a JSON object at %s" % LIFE_ATLAS_PATH)
	else:
		_art = _collect_residents(resident_atlas, manifest)
	if not manifest.is_empty():
		_effects_ready = _collect_effects(manifest, effect_atlas)


func clear() -> void:
	_clips.clear()
	_residents.clear()
	_effects.clear()
	_pending.clear()
	_time = 0.0
	_art = false
	_effects_ready = false


func _collect_residents(atlas: Dictionary, manifest: Dictionary) -> bool:
	var animations := _animation_table(atlas)
	var declared: Variant = manifest.get("residents", null)
	if animations.is_empty():
		return false
	if not declared is Array or (declared as Array).is_empty():
		return _fail("life.json publishes no residents array")
	var textures := _load_declared_textures(atlas)
	if textures.is_empty():
		return false
	var built: Array[Dictionary] = []
	for raw: Variant in declared as Array:
		if not raw is Dictionary:
			return _fail("life.json residents must all be objects")
		var item := raw as Dictionary
		var placement := String(item.get("placement", "")).strip_edges()
		var clip := String(item.get("clip", "")).strip_edges()
		if placement.is_empty() or clip.is_empty():
			return _fail("a resident placement needs both a placement and a clip")
		if not _clip_usable(atlas, animations, clip, textures):
			return false
		built.append({"placement": placement, "clip": clip, "phase": _number_or_zero(item.get("phase", 0.0))})
	_residents = built
	return true


func _collect_effects(manifest: Dictionary, effect_atlas: Dictionary) -> bool:
	var declared: Variant = manifest.get("effects", null)
	if not declared is Array:
		return _fail("life.json publishes no effects array")
	var entries := declared as Array
	if entries.is_empty():
		return true
	if effect_atlas.is_empty():
		return _fail("socket atlas is missing or is not a JSON object at %s" % EFFECT_ATLAS_PATH)
	var animations := _animation_table(effect_atlas)
	if animations.is_empty():
		return false
	var textures := _load_declared_textures(effect_atlas)
	if textures.is_empty():
		return false
	var built: Array[Dictionary] = []
	for raw: Variant in entries:
		if not raw is Dictionary:
			return _fail("life.json effects must all be objects")
		var item := raw as Dictionary
		var socket_id := String(item.get("id", "")).strip_edges()
		var owner := String(item.get("owner", "")).strip_edges()
		var clip := String(item.get("clip", "")).strip_edges()
		if socket_id.is_empty() or owner.is_empty():
			return _fail("a socket needs both an id and an owner")
		if not EFFECT_CLIPS.has(clip):
			return _fail("socket %s asks for %s, the approved sheet publishes %s" % [socket_id, clip, ", ".join(EFFECT_CLIPS)])
		var offset: Variant = item.get("offset", null)
		if not offset is Array or (offset as Array).size() != 2 or not _numbers(offset as Array):
			return _fail("socket %s needs an offset pair measured from its owner's feet" % socket_id)
		var layer := String(item.get("layer", DEFAULT_EFFECT_LAYER)).strip_edges()
		if not EFFECT_LAYERS.has(layer):
			return _fail("socket %s declares band %s, the published bands are %s" % [socket_id, layer, ", ".join(EFFECT_LAYERS)])
		if not _clip_usable(effect_atlas, animations, clip, textures):
			return false
		var pair := offset as Array
		built.append({
			"id": socket_id,
			"owner": owner,
			"clip": clip,
			"offset": Vector2(float(pair[0]), float(pair[1])),
			"phase": _number_or_zero(item.get("phase", 0.0)),
			"layer": layer,
		})
	_effects = built
	return true


func _animation_table(atlas: Dictionary) -> Dictionary:
	var declared: Variant = atlas.get("animations", null)
	if not declared is Dictionary or (declared as Dictionary).is_empty():
		_fail("atlas publishes no animations dictionary")
		return {}
	return declared as Dictionary


func _clip_usable(atlas: Dictionary, animations: Dictionary, clip: String, textures: Dictionary) -> bool:
	## One published cycle, cut from its declared cells. A cycle that never
	## changes, a cadence that is not a whole number of frames per second, a
	## one-shot published as a life cycle and cells that sample outside their own
	## sheet are all refused here, so the hub keeps its approved static residents
	## instead of drawing a broken cycle.
	if _clips.has(clip):
		return true
	var raw: Variant = animations.get(clip, null)
	if not raw is Dictionary:
		return _fail("atlas publishes no %s animation" % clip)
	var animation := raw as Dictionary
	var fps := _number_or_zero(animation.get("fps", 0.0))
	if fps <= 0.0 or not is_equal_approx(fps, roundf(fps)):
		return _fail("%s declares fps %s, a life cadence is a whole number of frames per second" % [clip, animation.get("fps", 0.0)])
	if animation.has("loop") and not bool(animation.get("loop")):
		return _fail("%s is published as a one-shot, a life cycle loops" % clip)
	var raw_frames: Variant = animation.get("frames", null)
	var frame_count := (raw_frames as Array).size() if raw_frames is Array else 0
	if frame_count < MIN_UNIQUE_FRAMES:
		return _fail("%s declares %d frames, a cycle needs at least %d" % [clip, frame_count, MIN_UNIQUE_FRAMES])
	var sprites: Variant = atlas.get("sprites", null)
	if not sprites is Dictionary:
		return _fail("atlas publishes no sprites dictionary")
	var cells: Array[Dictionary] = []
	var cut: Array[String] = []
	for raw_id: Variant in raw_frames as Array:
		var frame := _cut_frame(sprites as Dictionary, textures, String(raw_id), clip)
		if frame.is_empty():
			return false
		var cell := frame["rect"] as Rect2
		var key := "%s|%s" % [str(cell.position), str(cell.size)]
		if not cut.has(key):
			cut.append(key)
		cells.append(frame)
	if cut.size() < MIN_UNIQUE_FRAMES:
		return _fail("%s repeats one cell, a cycle needs %d distinct frames" % [clip, MIN_UNIQUE_FRAMES])
	# One cycle, one cell, one anchor: a frame that moved its own anchor would
	# slide the resident or the socket off the feet the layout published.
	var cell_size := (cells[0]["rect"] as Rect2).size
	var cell_anchor := cells[0]["anchor"] as Vector2
	for frame: Dictionary in cells:
		if (frame["rect"] as Rect2).size != cell_size or frame["anchor"] != cell_anchor:
			return _fail("%s mixes %s and %s cells anchored at %s and %s: a cycle holds one cell and one anchor" % [clip, cell_size, (frame["rect"] as Rect2).size, cell_anchor, frame["anchor"]])
	_clips[clip] = {
		"fps": fps,
		"frames": cells,
		"unique_frames": cut.size(),
		"texture_path": String(cells[0]["texture_path"]),
		"cell": (cells[0]["rect"] as Rect2).size,
		"anchor": cells[0]["anchor"] as Vector2,
	}
	return true


func _cut_frame(sprites: Dictionary, textures: Dictionary, frame_id: String, clip: String) -> Dictionary:
	var raw: Variant = sprites.get(frame_id, null)
	if not raw is Dictionary:
		return _fail_frame("%s frame %s is not published by the atlas" % [clip, frame_id])
	var entry := raw as Dictionary
	var rect: Variant = entry.get("rect", null)
	var declared_anchor: Variant = entry.get("anchor", null)
	if not _integer_list(rect, 4) or not _integer_list(declared_anchor, 2):
		return _fail_frame("%s frame %s needs an integer rect and anchor" % [clip, frame_id])
	var rect_values := rect as Array
	var cell := Rect2(
		Vector2(float(rect_values[0]), float(rect_values[1])),
		Vector2(float(rect_values[2]), float(rect_values[3]))
	)
	var texture_meta: Variant = textures.get(String(entry.get("texture", "")), null)
	if not texture_meta is Dictionary:
		return _fail_frame("%s frame %s asks for texture %s, which is not loaded" % [clip, frame_id, String(entry.get("texture", ""))])
	var metadata := texture_meta as Dictionary
	var texture := metadata.get("texture", null) as Texture2D
	if texture == null:
		return _fail_frame("%s frame %s has no texture" % [clip, frame_id])
	if cell.size.x <= 0.0 or cell.size.y <= 0.0:
		return _fail_frame("%s frame %s is an empty cell" % [clip, frame_id])
	if not Rect2(Vector2.ZERO, texture.get_size()).encloses(cell):
		return _fail_frame("%s frame %s samples outside %s" % [clip, frame_id, String(metadata.get("path", ""))])
	var anchor_values := declared_anchor as Array
	return {
		"texture": texture,
		"rect": cell,
		"anchor": Vector2(float(anchor_values[0]), float(anchor_values[1])),
		"texture_path": String(metadata.get("path", "")),
	}


func _load_declared_textures(atlas: Dictionary) -> Dictionary:
	## Only the PNGs this atlas declares, each checked against its declared size.
	## A shipped build keeps only the imported texture, so ResourceLoader is asked
	## first; the raw decode is the same-machine fallback for a tree whose import
	## step has not run yet. One undecodable PNG costs its own clips, not the pass.
	var declared: Variant = atlas.get("textures", null)
	if not declared is Dictionary:
		_fail("atlas publishes no textures dictionary")
		return {}
	var table := declared as Dictionary
	var result := {}
	for raw_key: Variant in table.keys():
		var texture_key := String(raw_key)
		var raw_meta: Variant = table[raw_key]
		if not raw_meta is Dictionary:
			_fail("texture %s declares no metadata" % texture_key)
			return {}
		var metadata := raw_meta as Dictionary
		var path := String(metadata.get("path", ""))
		var declared_size := Vector2i(int(metadata.get("width", 0)), int(metadata.get("height", 0)))
		var texture := load_texture_at(path, declared_size)
		if texture == null:
			_fail("texture %s is missing or is not %s at %s" % [texture_key, declared_size, path])
			return {}
		result[texture_key] = {"texture": texture, "path": path}
	return result


func load_texture_at(path: String, declared_size: Vector2i) -> Texture2D:
	## PCK-safe loader: the imported resource first, the raw PNG second. Both
	## paths check the declared size, so a half-imported tree never ships a
	## half-scaled sheet into the hub.
	return TextureLoader.load_sized(path, declared_size, true)


## ------------------------------------------------------------------- runtime

func has_real_art() -> bool:
	return _art and not _residents.is_empty()


func life_ready() -> bool:
	return has_real_art() and _effects_ready


func pending_reasons() -> Array[String]:
	return _pending.duplicate()


func tick(delta: float) -> void:
	## Presentation clock only. A negative or wild delta cannot rewind a cycle.
	_time += maxf(0.0, delta)


func life_time() -> float:
	return _time


func set_life_time_for_test(seconds: float) -> void:
	## Fixture clock: one deterministic instant instead of an accumulated one.
	_time = maxf(0.0, seconds)


func clip_entry(clip: String) -> Dictionary:
	var entry: Variant = _clips.get(clip, null)
	return entry if entry is Dictionary else {}


func clip_fps(clip: String) -> float:
	return float(clip_entry(clip).get("fps", 0.0))


func clip_frame_count(clip: String) -> int:
	return (clip_entry(clip).get("frames", []) as Array).size()


func clip_unique_frames(clip: String) -> int:
	return int(clip_entry(clip).get("unique_frames", 0))


func clip_texture_path(clip: String) -> String:
	return String(clip_entry(clip).get("texture_path", ""))


func frame_index(clip: String, seconds: float) -> int:
	## One published step per 1/fps, wrapping: every life cycle is a loop. Time
	## before the first frame clamps to it instead of wrapping backwards.
	var entry := clip_entry(clip)
	var fps := float(entry.get("fps", 0.0))
	var count := (entry.get("frames", []) as Array).size()
	if fps <= 0.0 or count <= 0:
		return -1
	var step := int(floor(maxf(0.0, seconds) * fps + CLOCK_EPSILON))
	return ((step % count) + count) % count


func frame_at(clip: String, seconds: float) -> Dictionary:
	## The cell this clip shows at that instant, or an empty dictionary while the
	## clip is unpublished. A fresh dictionary each call: no shared frame state.
	var index := frame_index(clip, seconds)
	if index < 0:
		return {}
	var entry := clip_entry(clip)
	var frames := entry.get("frames", []) as Array
	var frame := (frames[index] as Dictionary).duplicate()
	frame["index"] = index
	frame["frames"] = frames.size()
	frame["unique_frames"] = int(entry.get("unique_frames", 0))
	frame["fps"] = float(entry.get("fps", 0.0))
	frame["clip"] = clip
	return frame


func resident_entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Dictionary in _residents:
		result.append({
			"placement": String(entry["placement"]),
			"clip": String(entry["clip"]),
			"phase": float(entry["phase"]),
		})
	return result


func effect_entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Dictionary in _effects:
		result.append({
			"id": String(entry["id"]),
			"owner": String(entry["owner"]),
			"clip": String(entry["clip"]),
			"offset": entry["offset"] as Vector2,
			"phase": float(entry["phase"]),
			"layer": String(entry["layer"]),
		})
	return result


func life_report() -> Dictionary:
	## Every number a GPU check needs to name the frame that is on screen: the
	## clip, its index inside the published cycle, the source sheet it was cut
	## from and the cell it really samples. Nothing here touches the scene tree.
	var residents: Array[Dictionary] = []
	for entry: Dictionary in _residents:
		residents.append(_entry_report(entry, String(entry["placement"])))
	var effects: Array[Dictionary] = []
	for entry: Dictionary in _effects:
		var report := _entry_report(entry, String(entry["id"]))
		report["owner"] = String(entry["owner"])
		report["layer"] = String(entry["layer"])
		report["offset"] = entry["offset"] as Vector2
		effects.append(report)
	return {
		"ready": life_ready(),
		"art": has_real_art(),
		"effects_ready": _effects_ready,
		"time": _time,
		"residents": residents,
		"effects": effects,
		"pending": _pending.duplicate(),
	}


func _entry_report(entry: Dictionary, entry_id: String) -> Dictionary:
	var clip := String(entry["clip"])
	var phase := float(entry["phase"])
	var frame := frame_at(clip, _time + phase)
	return {
		"id": entry_id,
		"clip": clip,
		"phase": phase,
		"frame": int(frame.get("index", -1)),
		"frames": int(frame.get("frames", 0)),
		"unique_frames": int(frame.get("unique_frames", 0)),
		"fps": float(frame.get("fps", 0.0)),
		"texture": clip_texture_path(clip),
		"rect": frame.get("rect", Rect2()),
		"anchor": frame.get("anchor", Vector2.ZERO),
	}


## ------------------------------------------------------------------ validation

func _fail(reason: String) -> bool:
	## Every refusal is reported once, in the order the package was read.
	_pending.append(reason)
	return false


func _fail_frame(reason: String) -> Dictionary:
	_pending.append(reason)
	return {}


func _integer_list(value: Variant, size: int) -> bool:
	if not value is Array or (value as Array).size() != size:
		return false
	return _numbers(value as Array)


func _numbers(values: Array) -> bool:
	for element: Variant in values:
		if not _number(element):
			return false
	return true


func _number(value: Variant) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	return is_finite(float(value))


func _number_or_zero(value: Variant) -> float:
	return float(value) if _number(value) else 0.0
