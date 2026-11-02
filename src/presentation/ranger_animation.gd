class_name RangerAnimation
extends "res://src/presentation/actor_clip_reader.gd"
## Shared ranger action reader/controller for the published action atlas
## res://art/production/p1/ranger_actions_v01/atlas.json (2026-09-14 hand-off).
##
## One instance per view. The arena feeds it authoritative sim ticks, the base
## hub and the tutorial feed it their presentation clock; the file itself never
## writes gameplay state, never touches damage, collision, AI or drops, and
## never changes an authoritative hash.
##
## Atlas schema (identical to the published title_life_v01 package):
##   schema_version  1
##   native_view     [640, 360]
##   textures        {key: {path, width, height}}
##   sprites         {id: {texture, rect [x,y,48,48], anchor [ax,ay], facing?,
##                          state?}}
##   animations      {"ranger.<facing>.<action>": {frames: [sprite_id], fps,
##                          loop}}
## Every frame's rect and anchor are read from the manifest, so a later pack may
## place cells wherever it likes. The 48x48 cell keeps the old 38px body height
## and the (24,44) foot point; a frame that disagrees with those numbers is a
## broken delivery and is reported, not drawn.
##
## State keys consumed by resolve() (the trigger contract):
##   facing        Vector2 or "south"/"north"/"east"/"west"
##   dead          bool, true once the hero is down (death clip holds its last
##                 frame)
##   death_ticks   ticks since death was first observed
##   hit_ticks     ticks since the last damage event, -1 when none is live
##   dodge_ticks   ticks since the dodge started, -1 when not dodging
##   dash_ticks    ticks since the dash (Dash) started, -1 when not dashing
##   shoot_ticks   ticks since the shot started, -1 when not shooting
##   moving        bool, drives walk vs idle
##   phase_ticks   loop clock for idle/walk (sim tick or presentation clock)
##   tick          the caller's current clock tick, kept for the integration
##                 report only (sim tick in the arena, presentation tick in the
##                 hub and the tutorial)
##
## One-shot clips expire on their own published length, so a caller may hand over
## a raw counter and still fall through to the next live action.
##
## Runtime action ages come from the fixed-tick authority. Piercing Arrow now has
## a real windup and impact tick, so all four authored frames are part of play.
## Atlas FPS selects a pose inside that authority-owned window; it never decides
## when damage, movement, immunity, or an action end occurs.
##
## Event latching: latch_event() records the first tick of one (source, cast)
## pair and ignores every repeat, so redrawing can never restart a clip and the
## same cast only ever fires once. latched_ticks() then reports its age.

const ArtSets := preload("res://src/presentation/art/art_sets.gd")
const ATLAS_PATH := ArtSets.RANGER_ACTIONS_V01 + "/atlas.json"
const TEXTURE_KEY := "ranger"
const TEXTURE_PATH := ArtSets.RANGER_ACTIONS_V01 + "/ranger.png"
## The original paths remain the animation contract's provenance. The live
## material skin is the actors_v02 pack, which keeps that contract and
## explicitly binds a same-size material skin.
const STYLE_ATLAS_PATH := ArtSets.ACTORS_V02 + "/ranger_atlas.json"
const STYLE_TEXTURE_PATH := ArtSets.ACTORS_V02 + "/ranger.png"
const NATIVE_VIEW := Vector2i(640, 360)
const SCHEMA_VERSION := 1
const ArrowOrigin := preload("res://src/systems/ranger_arrow_origin.gd")
## The action cell. 48x48 with a (24,44) foot anchor holds the approved 38px
## hero body at the same height and the same ground contact as the old 32x48
## idle cell; the extra width is padding for poses that reach sideways.
const DEFAULT_ANCHOR := ArrowOrigin.FOOT_ANCHOR
const BODY_HEIGHT := 38
const FACINGS: Array[String] = ["south", "north", "east", "west"]
const ACTIONS: Array[String] = ["idle", "walk", "shoot", "dodge", "dash", "hit", "death"]
## First live action wins. Hit is deliberately below displacement and shooting:
## the renderer adds a reaction overlay without replacing the action that is
## still moving or releasing the ranger.
const ACTION_PRIORITY: Array[String] = ["death", "dodge", "dash", "shoot", "hit", "walk", "idle"]
## The agreed timing of the hand-off. It is read as a contract check, never as a
## substitute for the manifest: a disagreement is listed in contract_notes() and
## the frame count still comes from the published clips.
const ACTION_CONTRACT := {
	"idle": {"frames": 1, "fps": 8, "loop": true},
	"walk": {"frames": 4, "fps": 8, "loop": true},
	"shoot": {"frames": ArrowOrigin.SHOOT_FRAMES, "fps": ArrowOrigin.SHOOT_FPS, "loop": false},
	"dodge": {"frames": 2, "fps": 12, "loop": false},
	"dash": {"frames": 2, "fps": 12, "loop": false},
	"hit": {"frames": 1, "fps": 8, "loop": false},
	"death": {"frames": 3, "fps": 6, "loop": false},
}
## The frame each action enters at. All current actions begin at their authored
## first frame because their preparation now has an authoritative time window.
const ACTION_RUNTIME_ENTRY := {}
## Bow-hand socket inside each authored 48px shoot cell. The atlas gives the
## foot anchor only; using that anchor as the arrow origin put the projectile at
## the Ranger's boots. These per-facing/per-frame points follow the actual grip
## as the bow is raised and released.
const ARROW_ATTACHMENT_BY_FACING_FRAME := ArrowOrigin.SOCKETS
## The approved west-facing walk sheet has two contact poses whose painted sole is
## one source pixel above the shared (24,44) foot anchor.  Keep the authoritative
## foot point stable by compensating only those presentation frames.  This does
## not alter the manifest anchor, the facing, or a projectile socket (which is
## resolved separately from the current shoot frame).
const WALK_DRAW_OFFSET_BY_FACING_FRAME := {
	"west": [Vector2i(0, 1), Vector2i.ZERO, Vector2i.ZERO, Vector2i(0, 1)],
}


func _init(load_images := true, path_overrides: Dictionary = {}, atlas_override: Dictionary = {}) -> void:
	## path_overrides / atlas_override exist for tests: pointing a reader at a
	## missing or malformed manifest has to exercise the reported pending and
	## invalid paths instead of a special case.
	var atlas_path := String(path_overrides.get("atlas", STYLE_ATLAS_PATH))
	_read_atlas(atlas_path, atlas_override)
	if atlas_override.is_empty() and atlas_path == STYLE_ATLAS_PATH and _state == STATE_READY and _style_texture_paths.get(TEXTURE_KEY, "") != STYLE_TEXTURE_PATH:
		_state = STATE_INVALID
		_reasons.append("R13 manifest must declare its ranger material texture")
	if _state == STATE_READY and load_images:
		_load_images()


func pending_reason() -> String:
	if not _reasons.is_empty():
		return "; ".join(PackedStringArray(_reasons))
	if not has_real_art():
		return "ranger action textures are not loaded"
	return ""


func clip_ids() -> Array[String]:
	var result: Array[String] = []
	for facing: String in FACINGS:
		for action: String in ACTIONS:
			result.append(clip_id(facing, action))
	return result


## The approved static four-way cell this reader falls back to. Each view already
## reads that cell from its own published atlas.
static func fallback_sprite_id(facing: String) -> String:
	return "ranger.%s.idle" % facing


static func clip_id(facing: String, action: String) -> String:
	return "ranger.%s.%s" % [facing, action]


## The release boundary samples the same authored shoot frame as resolve().
static func shoot_frame_at_tick(shoot_ticks: int) -> int:
	return ArrowOrigin.shoot_frame_at_tick(shoot_ticks)


static func arrow_attachment_local(facing: Variant, frame: int) -> Vector2i:
	return ArrowOrigin.attachment_local(facing, frame)


## Converts the authored cell socket into deterministic gameplay coordinates.
## world_units_per_gameplay is supplied by the arena transform so the rendered
## hand and the authoritative release point remain the same point on screen.
static func arrow_attachment_offset(facing: Variant, frame: int, world_units_per_gameplay: float) -> Vector2:
	return ArrowOrigin.attachment_offset(facing, frame, world_units_per_gameplay)


## Four-way facing bucket. Screen space: +y points down.
static func facing_key(facing: Variant) -> String:
	return ArrowOrigin.facing_key(facing)


## Runtime integration diagnostic: the frame that was actually handed to a
## renderer (action, facing, clip, frame, rect, anchor, fallback) plus the last
## latched event token and its time. Recorded on every resolve(), so a captured
## frame can be compared against the state it was drawn in.
func integration_report() -> Dictionary:
	var report := _last_frame.duplicate(true)
	report["asset_state"] = _state
	report["pending_reason"] = pending_reason()
	var now_tick := int(report.get("resolved_tick", -1))
	var events := {}
	for kind: String in _events.keys():
		var entry := _events[kind] as Dictionary
		var tick := int(entry.get("tick", -1))
		events[kind] = {
			"token": String(entry.get("id", "")),
			"tick": tick,
			"age_ticks": maxi(0, now_tick - tick) if now_tick >= 0 else -1,
		}
	report["events"] = events
	return report


func last_event(kind: String) -> Dictionary:
	var entry: Variant = _events.get(kind, null)
	if not entry is Dictionary:
		return {}
	return (entry as Dictionary).duplicate(true)


## Resolves one frame for the current state. The result is always explicit about
## which branch it took:
##   fallback == true   the caller draws its own approved static idle cell and
##                      reason names the cause
##   fallback == false  rect/anchor/texture come from the manifest frame, and the
##                      caller must read the anchor per frame instead of
##                      assuming a cell slot
func resolve(state: Dictionary = {}) -> Dictionary:
	var tick := int(state.get("tick", -1))
	var facing := facing_key(state.get("facing", "south"))
	var action := live_action(state, facing)
	var clip := clip_id(facing, action)
	var info := _animations.get(clip, {}) as Dictionary
	var ticks := action_ticks(action, state, facing)
	var clock := clock_ticks(action, state, facing)
	if not has_real_art() or info.is_empty():
		return _record_resolution(fallback_frame(facing, action, clock), tick)
	var frames := info.get("frames", []) as Array
	var fps := int(info.get("fps", 8))
	var loop := bool(info.get("loop", false))
	var index := frame_index_for(frames.size(), fps, float(clock) / float(SIM_TICKS_PER_SECOND), loop)
	var entry := int(info.get("entry_frame", 0))
	if not loop and entry > 0:
		## A one-shot clip enters at its live frame and holds its last one, so a
		## pose the authority never had is never drawn.
		index = mini(entry + index, frames.size() - 1)
	var frame := _sprites.get(String(frames[index]), {}) as Dictionary
	if frame.is_empty():
		return _record_resolution(fallback_frame(facing, action, clock), tick)
	return _record_resolution({
		"action": action,
		"facing": facing,
		"clip": clip,
		"frame": index,
		"frame_count": frames.size(),
		"rect": frame.get("rect", Rect2i()),
		"anchor": frame.get("anchor", DEFAULT_ANCHOR),
		"draw_offset": walk_draw_offset(facing, action, index),
		"texture": _textures.get(String(frame.get("texture_key", "")), null),
		"texture_path": String(frame.get("texture_path", "")),
		"source_texture_path": String(frame.get("source_texture_path", "")),
		"texture_key": String(frame.get("texture_key", "")),
		"source": String(frame.get("source", "")),
		"fps": fps,
		"loop": loop,
		"entry_frame": entry,
		"duration_ticks": int(info.get("duration_ticks", 0)),
		"progress_ticks": ticks,
		"fallback": false,
		"fallback_sprite_id": "",
		"state": _state,
		"reason": "",
	}, tick)


## The explicit pending/invalid answer: pending is the approved static four-way
## cell plus a reason, never a silent pass.
func fallback_frame(facing: String, action := "idle", clock := 0) -> Dictionary:
	return {
		"action": action,
		"facing": facing,
		"clip": "",
		"frame": -1,
		"frame_count": 0,
		"rect": Rect2i(),
		"anchor": _cell_anchor(),
		"draw_offset": Vector2i.ZERO,
		"texture": null,
		"texture_key": "",
		"source": "",
		"fps": 0,
		"loop": false,
		"duration_ticks": 0,
		"progress_ticks": clock,
		"fallback": true,
		"fallback_sprite_id": fallback_sprite_id(facing),
		"state": _state,
		"reason": pending_reason(),
	}


## First action whose trigger is live. One-shot clips drop out on their own
## published length, so a counter that outlives its clip falls through here.
func live_action(state: Dictionary, facing: String) -> String:
	for action: String in ACTION_PRIORITY:
		var ticks := action_ticks(action, state, facing)
		if action == "idle":
			return action
		if action == "death":
			if bool(state.get("dead", false)):
				return action
			continue
		if ticks < 0:
			continue
		if action == "walk":
			if bool(state.get("moving", false)):
				return action
			continue
		## Displacement actions may last longer than their short authored clip. The
		## authority supplies that exact window and the last pose is held until it
		## ends; atlas duration remains the fallback for standalone art fixtures.
		var window := int(state.get("%s_window_ticks" % action, duration_ticks(action, facing)))
		if window <= 0 or ticks < window:
			return action
	return "idle"


## Raw counter behind one action, -1 when the caller did not offer one.
func action_ticks(action: String, state: Dictionary, facing: String) -> int:
	match action:
		"death":
			return maxi(0, int(state.get("death_ticks", 0))) if bool(state.get("dead", false)) else -1
		"walk", "idle":
			return int(state.get("phase_ticks", 0))
		_:
			return int(state.get("%s_ticks" % action, -1))


## Clock a clip is sampled at: looping clips run on the loop clock, one-shot
## clips on their own age.
func clock_ticks(action: String, state: Dictionary, facing: String) -> int:
	if action == "idle" or action == "walk":
		return int(state.get("phase_ticks", 0))
	return maxi(0, action_ticks(action, state, facing))


## Published length of one action clip in ticks; before delivery the agreed
## contract timing stands in, so the state mapping is testable while pending.
func duration_ticks(action: String, facing: String) -> int:
	var info := _animations.get(clip_id(facing, action), {}) as Dictionary
	if not info.is_empty():
		return int(info.get("duration_ticks", 0))
	var agreed := ACTION_CONTRACT.get(action, {}) as Dictionary
	if agreed.is_empty():
		return 0
	return duration_ticks_for(int(agreed.get("frames", 1)), int(agreed.get("fps", 8)))


## A draw-only correction for documented contact-pose drift.  Keeping it next to
## frame resolution makes every view consume the same offset and leaves the
## simulation's anchor and all projectile maths untouched.
static func walk_draw_offset(facing: String, action: String, frame_index: int) -> Vector2i:
	if action != "walk":
		return Vector2i.ZERO
	var offsets: Variant = WALK_DRAW_OFFSET_BY_FACING_FRAME.get(facing_key(facing), [])
	if not offsets is Array or frame_index < 0 or frame_index >= (offsets as Array).size():
		return Vector2i.ZERO
	var offset: Variant = (offsets as Array)[frame_index]
	return offset as Vector2i if offset is Vector2i else Vector2i.ZERO


func _cell_anchor() -> Vector2i:
	return DEFAULT_ANCHOR


## ------------------------------------------------------------------ reading


func _validate(atlas: Dictionary) -> void:
	_reasons.clear()
	_notes.clear()
	_sprites.clear()
	_animations.clear()
	_texture_meta.clear()
	if int(atlas.get("schema_version", 0)) != SCHEMA_VERSION:
		_reasons.append("atlas schema_version must be %d" % SCHEMA_VERSION)
	var native: Variant = atlas.get("native_view", [])
	if not native is Array or (native as Array).size() != 2 or Vector2i(int((native as Array)[0]), int((native as Array)[1])) != NATIVE_VIEW:
		_reasons.append("atlas native_view must be [%d,%d]" % [NATIVE_VIEW.x, NATIVE_VIEW.y])
	_validate_declared_cell(atlas)
	_validate_textures(atlas)
	_validate_style_textures(atlas)
	_validate_sprites(atlas)
	_validate_animations(atlas)
	_state = STATE_READY if _reasons.is_empty() else STATE_INVALID


func _validate_textures(atlas: Dictionary) -> void:
	var declared: Variant = atlas.get("textures", null)
	if not declared is Dictionary:
		_reasons.append("atlas textures must be a dictionary")
		return
	for raw_key: Variant in (declared as Dictionary).keys():
		var key := String(raw_key)
		var value: Variant = (declared as Dictionary)[raw_key]
		if not value is Dictionary:
			_reasons.append("texture %s must be a dictionary" % key)
			continue
		var meta := value as Dictionary
		var path := String(meta.get("path", ""))
		var size := Vector2i(int(meta.get("width", 0)), int(meta.get("height", 0)))
		if not path.begins_with("res://"):
			_reasons.append("texture %s path must be res://" % key)
		if size.x <= 0 or size.y <= 0:
			_reasons.append("texture %s requires positive dimensions" % key)
		_texture_meta[key] = {"path": path, "width": size.x, "height": size.y}
	if not _texture_meta.has(TEXTURE_KEY):
		_reasons.append("atlas must declare the %s texture" % TEXTURE_KEY)


func _validate_sprites(atlas: Dictionary) -> void:
	var declared: Variant = atlas.get("sprites", null)
	if not declared is Dictionary:
		_reasons.append("atlas sprites must be a dictionary")
		return
	for raw_id: Variant in (declared as Dictionary).keys():
		var sprite_id := String(raw_id)
		var value: Variant = (declared as Dictionary)[raw_id]
		if not value is Dictionary:
			_reasons.append("sprite %s must be a dictionary" % sprite_id)
			continue
		var entry := value as Dictionary
		var rect_values: Variant = entry.get("rect", null)
		var anchor_values: Variant = entry.get("anchor", null)
		if not integer_list(rect_values, 4) or int((rect_values as Array)[2]) <= 0 or int((rect_values as Array)[3]) <= 0:
			_reasons.append("sprite %s rect must be four JSON integers with a positive size" % sprite_id)
			continue
		if not integer_list(anchor_values, 2) or int((anchor_values as Array)[0]) < 0 or int((anchor_values as Array)[1]) < 0:
			_reasons.append("sprite %s anchor must be two non-negative JSON integers" % sprite_id)
			continue
		var cell_rect := Rect2i(
			Vector2i(int((rect_values as Array)[0]), int((rect_values as Array)[1])),
			Vector2i(int((rect_values as Array)[2]), int((rect_values as Array)[3]))
		)
		if cell_rect.size != CELL:
			_reasons.append("sprite %s violates its %s action cell" % [sprite_id, str(CELL)])
			continue
		var texture_key := String(entry.get("texture", ""))
		var texture_meta := _texture_meta.get(texture_key, {}) as Dictionary
		if texture_meta.is_empty():
			_reasons.append("sprite %s references unknown texture %s" % [sprite_id, texture_key])
			continue
		var texture_size := Vector2i(int(texture_meta.get("width", 0)), int(texture_meta.get("height", 0)))
		if not Rect2i(Vector2i.ZERO, texture_size).encloses(cell_rect):
			_reasons.append("sprite %s cell lies outside texture %s" % [sprite_id, texture_key])
			continue
		_sprites[sprite_id] = {
			"rect": cell_rect,
			"anchor": Vector2i(int((anchor_values as Array)[0]), int((anchor_values as Array)[1])),
			"texture_key": texture_key,
			"texture_path": String(_style_texture_paths.get(texture_key, texture_meta.get("path", ""))),
			"source_texture_path": String(texture_meta.get("path", "")),
			"texture_size": texture_size,
			"facing": String(entry.get("facing", "")),
			"state": String(entry.get("state", entry.get("action", ""))),
			## A published pose may be reused across actions (the standing idle is
			## the same-facing shoot recovery); the atlas has to say so.
			"source": String(entry.get("source", entry.get("source_pose", ""))),
		}


func _validate_animations(atlas: Dictionary) -> void:
	var declared: Variant = atlas.get("animations", null)
	if not declared is Dictionary:
		_reasons.append("atlas animations must be a dictionary")
		return
	var animations := declared as Dictionary
	for facing: String in FACINGS:
		for action: String in ACTIONS:
			_validate_clip(animations, facing, action)
	for raw_id: Variant in animations.keys():
		var clip := String(raw_id)
		if not _clip_is_expected(clip):
			_notes.append("animation %s is not part of the agreed ranger matrix" % clip)


func _validate_clip(animations: Dictionary, facing: String, action: String) -> void:
	var clip := clip_id(facing, action)
	var value: Variant = animations.get(clip, null)
	if not value is Dictionary:
		_reasons.append("animation %s is missing from the delivered atlas" % clip)
		return
	var entry := value as Dictionary
	var frames: Variant = entry.get("frames", null)
	if not frames is Array or (frames as Array).is_empty():
		_reasons.append("animation %s requires a non-empty frames array" % clip)
		return
	var fps := int(entry.get("fps", ACTION_CONTRACT[action]["fps"]))
	if fps < 1:
		_reasons.append("animation %s fps must be a positive integer" % clip)
		return
	var loop := bool(entry.get("loop", ACTION_CONTRACT[action]["loop"]))
	var resolved: Array[String] = []
	for raw_frame: Variant in frames as Array:
		var frame_id := String(raw_frame)
		var frame := _sprites.get(frame_id, {}) as Dictionary
		if frame.is_empty():
			_reasons.append("animation %s frame %s is not a validated sprite" % [clip, frame_id])
			return
		var declared_facing := String(frame.get("facing", ""))
		if not declared_facing.is_empty() and declared_facing != facing:
			_reasons.append("animation %s frame %s declares facing %s" % [clip, frame_id, declared_facing])
			return
		var declared_state := String(frame.get("state", ""))
		if not declared_state.is_empty() and declared_state != action:
			if String(frame.get("source", "")).is_empty():
				_reasons.append("animation %s frame %s declares state %s" % [clip, frame_id, declared_state])
				return
			## Disclosed cross-animation reuse (idle = the same-facing shoot
			## recovery): accepted, but recorded instead of hidden.
			_notes.append("animation %s frame %s reuses the disclosed %s pose %s" % [clip, frame_id, declared_state, String(frame.get("source", ""))])
		resolved.append(frame_id)
	var entry_frame := _runtime_entry(clip, action, entry.get("entry_frame", null), resolved.size())
	if entry_frame < 0:
		return
	_animations[clip] = {
		"frames": resolved,
		"fps": fps,
		"loop": loop,
		"entry_frame": entry_frame,
		"duration_ticks": duration_ticks_for(resolved.size(), fps) if not loop else 0,
	}
	_note_contract(clip, action, resolved.size(), fps, loop)


## Entry frame of a one-shot clip: the agreed runtime entry unless the manifest
## declares its own, which is then reported as drift. -1 rejects the clip.
func _runtime_entry(clip: String, action: String, declared: Variant, frame_count: int) -> int:
	var agreed := int(ACTION_RUNTIME_ENTRY.get(action, 0))
	var entry := agreed
	if typeof(declared) in [TYPE_INT, TYPE_FLOAT]:
		if not is_finite(float(declared)) or float(declared) != floor(float(declared)):
			_reasons.append("animation %s entry_frame must be an integer" % clip)
			return -1
		entry = int(declared)
		if entry != agreed:
			_notes.append("animation %s enters at frame %d, the hand-off agreed frame %d" % [clip, entry, agreed])
	elif declared != null:
		_reasons.append("animation %s entry_frame must be an integer" % clip)
		return -1
	if entry < 0 or entry > frame_count - 1:
		_reasons.append("animation %s entry frame %d is outside its %d frames" % [clip, entry, frame_count])
		return -1
	return entry


func _note_contract(clip: String, action: String, count: int, fps: int, loop: bool) -> void:
	var agreed := ACTION_CONTRACT.get(action, {}) as Dictionary
	if agreed.is_empty():
		return
	if count != int(agreed.get("frames", count)):
		_notes.append("animation %s publishes %d frames, the hand-off agreed %d" % [clip, count, int(agreed.get("frames", count))])
	if fps != int(agreed.get("fps", fps)):
		_notes.append("animation %s publishes %dfps, the hand-off agreed %dfps" % [clip, fps, int(agreed.get("fps", fps))])
	if loop != bool(agreed.get("loop", loop)):
		_notes.append("animation %s publishes loop=%s, the hand-off agreed %s" % [clip, str(loop), str(bool(agreed.get("loop", loop)))])


func _clip_is_expected(clip: String) -> bool:
	var parts := clip.split(".")
	if parts.size() != 3 or parts[0] != "ranger":
		return false
	return FACINGS.has(parts[1]) and ACTIONS.has(parts[2])


func _load_images() -> void:
	for texture_key: String in _texture_meta.keys():
		var meta := _texture_meta[texture_key] as Dictionary
		var path := String(_style_texture_paths.get(texture_key, meta.get("path", "")))
		var expected := Vector2i(int(meta.get("width", 0)), int(meta.get("height", 0)))
		# Release packs carry imported textures, not necessarily source PNGs.
		if ResourceLoader.exists(path, "Texture2D"):
			var imported := ResourceLoader.load(path, "Texture2D") as Texture2D
			if imported != null and Vector2i(imported.get_size()) == expected:
				_textures[texture_key] = imported
				continue
		var file := open_resource(path)
		var image := Image.new()
		if file == null or file.get_length() == 0 or image.load_png_from_buffer(file.get_buffer(file.get_length())) != OK:
			_reasons.append("cannot load %s" % path)
			continue
		if image.get_size() != expected:
			_reasons.append("%s is %s, the atlas says %s (stale metadata?)" % [path, str(image.get_size()), str(expected)])
			continue
		_textures[texture_key] = ImageTexture.create_from_image(image)
	if not _reasons.is_empty():
		_state = STATE_INVALID

## ------------------------------------------------------- reader identity
## Values the shared ActorClipReader code reads through these hooks.

func _texture_key() -> String:
	return TEXTURE_KEY


func _default_anchor() -> Vector2i:
	return DEFAULT_ANCHOR


func _style_texture_path() -> String:
	return STYLE_TEXTURE_PATH


func _reader_label() -> String:
	return "ranger"
