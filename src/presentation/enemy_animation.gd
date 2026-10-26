class_name EnemyAnimation
extends RefCounted
## Shared enemy action reader for the published three-role action atlas
## res://art/production/p1/enemy_actions_v01/atlas.json (2026-09-14 hand-off).
##
## One instance per view. The arena feeds it authoritative simulation ticks plus
## a presentation clock; the file itself never writes gameplay state, never
## touches damage, collision, AI, drops or the deterministic RNG, and never
## changes an authoritative hash.
##
## Atlas schema (identical to ranger_actions_v01):
##   schema_version  1
##   native_view     [640, 360]
##   textures        {key: {path, width, height}}
##   sprites         {"<role>.east.<action>.<index>": {texture, rect [x,y,48,48],
##                          anchor [ax,ay], facing?, state?, source?}}
##   animations      {"<role>.east.<action>": {frames: [sprite_id], fps, loop}}
##
## The pack is published east-facing: the 13 east IDs of every role are the
## strict production set, and a west frame is the same cell mirrored about the
## published (24,44) anchor -- the centre of a 48x48 cell, so the mirror keeps
## the feet exactly where the calibration pack already drew them. An atlas that
## also declares west sprites and clips is validated too and is used as declared;
## only what is not declared is mirrored. A missing west declaration is never a
## reason to invent art.
##
## State keys consumed by resolve() (the trigger contract):
##   role                "melee" / "charger" / "ranged"
##   facing              Vector2 or "east"/"west"
##   action_state        the authoritative enemy state: "none" / "windup" /
##                       "active" / "recovery"
##   state_started_tick  authoritative first tick of that state
##   state_ends_tick     authoritative last tick of that state (the windup clip is
##                       phase-normalized across exactly this window)
##   moving              bool, inferred from the position the simulation really
##                       moved, never from a redraw
##   phase_ticks         loop clock for idle/walk: the 30Hz-authority ticks the
##                       enemy really moved. It is never a per-render delta, so
##                       one authority tick reads one frame at every render rate
##   hit_ticks           age of the latched hp-drop event, -1 when none is live
##   dead                bool, true once the entity is a detached corpse
##   death_ticks         ticks since the kill was observed (corpse clock)
##   tick                the caller's current clock tick, kept for the integration
##                       report only
##
## Authority first: an authoritative windup or active state is never masked by an
## inferred hit reaction, and the death clip outranks everything. A one-shot
## reaction expires on its own published length, so a caller may hand over a raw
## counter and still fall through to the next live action.
##
## Event latching: latch_event() records the first tick of one (source, cast) pair
## and ignores every repeat, so redrawing can never restart a reaction clip and
## the same hp drop only ever fires once. latched_ticks() then reports its age.

const ATLAS_PATH := "res://art/production/p1/enemy_actions_v01/atlas.json"
const TEXTURE_KEY := "enemies"
const TEXTURE_PATH := "res://art/production/p1/enemy_actions_v01/enemies.png"
const PACK_PREFIX := "res://art/production/p1/enemy_actions_v01/"
## Keep the published action identity; the explicit skin binding changes only
## same-size texture pixels and is also reported on each resolved frame.
const STYLE_ATLAS_PATH := "res://art/production/p1/actors_v02/enemy_atlas.json"
const STYLE_TEXTURE_PATH := "res://art/production/p1/actors_v02/enemies.png"
const NATIVE_VIEW := Vector2i(640, 360)
const SCHEMA_VERSION := 1
## The action cell. 48x48 with a (24,44) foot anchor is the same cell the
## calibration enemies were published on, so the swap keeps the ground contact.
const CELL := Vector2i(48, 48)
const DEFAULT_ANCHOR := Vector2i(24, 44)
const SIM_TICKS_PER_SECOND := 30
const ROLES: Array[String] = ["melee", "charger", "ranged"]
## The pack is authored east-facing; west is the mirrored read.
const FACINGS: Array[String] = ["east", "west"]
const ACTIONS: Array[String] = ["idle", "walk", "windup", "active", "recover", "hit", "death"]
## First live action wins. An authoritative windup/active outranks a hit reaction
## on purpose: a flinch must never hide the telegraph the player is dodging. The
## death clip outranks everything, and walk/idle only ever apply when nothing
## else is running.
const ACTION_PRIORITY: Array[String] = ["death", "windup", "active", "hit", "recover", "walk", "idle"]
## The agreed slot counts of one role: 13 IDs, 7 clips.
const ACTION_FRAME_COUNTS := {
	"idle": 1,
	"walk": 4,
	"windup": 2,
	"active": 1,
	"recover": 1,
	"hit": 1,
	"death": 3,
}
## The agreed timing of the hand-off. It is read as a contract check, never as a
## substitute for the manifest: a disagreement is listed in contract_notes() and
## the published clips still supply the frames.
const ACTION_CONTRACT := {
	"idle": {"frames": 1, "fps": 8, "loop": true},
	"walk": {"frames": 4, "fps": 8, "loop": true},
	"windup": {"frames": 2, "fps": 8, "loop": false, "phase_normalized": true},
	"active": {"frames": 1, "fps": 8, "loop": false},
	"recover": {"frames": 1, "fps": 8, "loop": false},
	"hit": {"frames": 1, "fps": 8, "loop": false},
	"death": {"frames": 3, "fps": 6, "loop": false},
}
## The published contract: a standing enemy reuses the same-facing recovery pose
## as idle instead of a fourteenth drawing. The atlas may publish it either as an
## explicit <role>.east.idle.0 cell or by pointing the idle clip at recover.0;
## both are disclosed in the production report, neither is a failure.
const IDLE_ALIAS_MODE_DECLARED := "declared_id"
const IDLE_ALIAS_MODE_IMPLICIT := "recover_alias"
## How long a detached corpse keeps its last death frame on the ground after the
## published clip has finished. Presentation only: nothing waits for it.
const CORPSE_HOLD_TICKS := 60
const STATE_READY := "ready"
## The new pack has not been delivered: the approved calibration cells stay on
## screen as an explicit, reported fallback.
const STATE_PENDING := "pending"
## A delivered atlas that does not satisfy the contract. Never drawn, always
## reported, so a broken pack cannot pass as finished art.
const STATE_INVALID := "invalid"

var _state := STATE_PENDING
var _reasons: Array[String] = []
var _notes: Array[String] = []
var _cell := CELL
var _sprites := {}
var _animations := {}
var _texture_meta := {}
var _style_texture_paths := {}
var _textures := {}
## Published PNG pixels per texture key, kept for the alias cross-checks: the
## bytes on disk are the source of truth even when an import cache disagrees.
var _raw_images := {}
var _events := {}
var _last_frame := {}
var _production := {}
## Alias cross-checks that need the published pixels: recorded at validation
## time, resolved once the sheet is in hand.
var _pending_alias_checks: Array[Dictionary] = []


func _init(load_images := true, path_overrides: Dictionary = {}, atlas_override: Dictionary = {}) -> void:
	## path_overrides / atlas_override exist for tests: pointing a reader at a
	## missing or malformed manifest has to exercise the reported pending and
	## invalid paths instead of a special case.
	var atlas_path := String(path_overrides.get("atlas", STYLE_ATLAS_PATH))
	_read_atlas(atlas_path, atlas_override)
	if atlas_override.is_empty() and atlas_path == STYLE_ATLAS_PATH and _state == STATE_READY and _style_texture_paths.get(TEXTURE_KEY, "") != STYLE_TEXTURE_PATH:
		_state = STATE_INVALID
		_reasons.append("R13 manifest must declare its enemy material texture")
	if _state == STATE_READY and load_images:
		_load_images()


func asset_state() -> String:
	return _state


## True only when a validated manifest and every declared texture are in hand.
## Views draw the action frames exactly when this is true.
func has_real_art() -> bool:
	return _state == STATE_READY and not _textures.is_empty() and _textures.size() == _texture_meta.size()


## While this is true the caller keeps drawing its approved calibration cells.
## It is never silent: pending_reason() always names the cause.
func using_fallback() -> bool:
	return not has_real_art()


func pending_reasons() -> Array[String]:
	return _reasons.duplicate()


func pending_reason() -> String:
	if not _reasons.is_empty():
		return "; ".join(PackedStringArray(_reasons))
	if not has_real_art():
		return "enemy action textures are not loaded"
	return ""


## Timings that were agreed for a delivered atlas but disagree with it. Empty on
## a pack that matches the hand-off; the frames themselves still come from the
## manifest either way.
func contract_notes() -> Array[String]:
	return _notes.duplicate()


func texture_path() -> String:
	## Logical source sheet; render_texture_path() names the pixels actually drawn.
	return String((_texture_meta.get(TEXTURE_KEY, {}) as Dictionary).get("path", ""))


func render_texture_path() -> String:
	return String(_style_texture_paths.get(TEXTURE_KEY, texture_path()))


## The runtime matrix: every role and action the reader can resolve, east cells
## plus the west read (declared or mirrored).
func clip_ids() -> Array[String]:
	var result: Array[String] = []
	for role: String in ROLES:
		for facing: String in FACINGS:
			for action: String in ACTIONS:
				result.append(clip_id(role, facing, action))
	return result


## Clips the atlas really declares, in publication order.
func declared_clip_ids() -> Array[String]:
	var result: Array[String] = []
	for raw_id: Variant in _animations.keys():
		result.append(String(raw_id))
	return result


## Clips read as the east cell mirrored about the (24,44) anchor.
func mirrored_clip_ids() -> Array[String]:
	var result: Array[String] = []
	for role: String in ROLES:
		for action: String in ACTIONS:
			if not _animations.has(clip_id(role, "west", action)):
				result.append(clip_id(role, "west", action))
	return result


func clip_info(clip: String) -> Dictionary:
	return (_animations.get(clip, {}) as Dictionary).duplicate(true)


## Explicit frame access for the art pass and fixtures.
func frame_for(clip: String, index: int) -> Dictionary:
	var info := _animations.get(clip, {}) as Dictionary
	var frames := info.get("frames", []) as Array
	if frames.is_empty():
		return {}
	var resolved_index := clampi(index, 0, frames.size() - 1)
	var frame := _sprites.get(String(frames[resolved_index]), {}) as Dictionary
	if frame.is_empty():
		return {}
	return {
		"clip": clip,
		"frame": resolved_index,
		"frame_count": frames.size(),
		"rect": frame.get("rect", Rect2i()),
		"anchor": frame.get("anchor", DEFAULT_ANCHOR),
		"texture": _textures.get(String(frame.get("texture_key", "")), null),
		"texture_path": String(frame.get("texture_path", "")),
		"source_texture_path": String(frame.get("source_texture_path", "")),
		"source": String(frame.get("source", "")),
	}


func sprite_ids() -> Array[String]:
	var result: Array[String] = []
	for id: Variant in _sprites.keys():
		result.append(String(id))
	return result


func frame_count(clip: String) -> int:
	return (_animations.get(clip, {}) as Dictionary).get("frames", []).size()


## Published length of one role action in ticks; before delivery the agreed
## contract timing stands in, so the state mapping is testable while pending.
func clip_duration_ticks(role: String, action: String) -> int:
	var info := _animations.get(clip_id(role, "east", action), {}) as Dictionary
	if not info.is_empty():
		return int(info.get("duration_ticks", 0))
	var agreed := ACTION_CONTRACT.get(action, {}) as Dictionary
	if agreed.is_empty():
		return 0
	return duration_ticks_for(int(agreed.get("frames", 1)), int(agreed.get("fps", 8)))


## Whether the atlas is loaded strictly enough for the runtime to draw it.
func production_report() -> Dictionary:
	var loaded: Array[String] = []
	for role: String in ROLES:
		for id: String in required_east_ids(role):
			if _sprites.has(id):
				loaded.append(id)
	return {
		"state": _state,
		"pending_reason": pending_reason(),
		"notes": contract_notes(),
		"roles": ROLES.duplicate(),
		"required_id_count": required_id_count(),
		"loaded_east_ids": loaded,
		"alias_ids": _production.get("alias_ids", []),
		"missing_east_ids": _production.get("missing_east_ids", []),
		"declared_clips": declared_clip_ids(),
		"mirrored_clips": mirrored_clip_ids(),
		"idle_alias_mode": String(_production.get("idle_alias_mode", "")),
		"texture_path": texture_path(),
		"render_texture_path": render_texture_path(),
		"texture_keys": _texture_meta.keys(),
	}


## The approved static calibration cell this reader falls back to while the new
## pack is pending. It is the cell the arena already publishes; the reader only
## names it, it never draws it.
static func fallback_sprite_id(role: String, action_state: String) -> String:
	var pose := "idle"
	match action_state:
		"windup":
			pose = "windup"
		"active":
			pose = "active"
		"recovery":
			pose = "recover"
	return "enemy.%s.%s" % [role, pose]


static func clip_id(role: String, facing: String, action: String) -> String:
	return "%s.%s.%s" % [role, facing, action]


## The 13 agreed east IDs of one role.
static func required_east_ids(role: String) -> Array[String]:
	var ids: Array[String] = []
	for action: String in ACTIONS:
		for index in int(ACTION_FRAME_COUNTS.get(action, 1)):
			ids.append("%s.east.%s.%d" % [role, action, index])
	return ids


static func required_id_count() -> int:
	var count := 0
	for action: String in ACTIONS:
		count += int(ACTION_FRAME_COUNTS.get(action, 1))
	return count


## Integer frame for a clip at a given age. Looping clips wrap, one-shot clips
## hold their last published frame (the death hold).
static func frame_index_for(frame_count: int, fps: int, seconds: float, loop: bool) -> int:
	if frame_count <= 1:
		return 0
	var step := int(floor(maxf(0.0, seconds) * float(maxi(1, fps))))
	if loop:
		return posmod(step, frame_count)
	return mini(step, frame_count - 1)


## Phase-normalized frame across an authoritative window: the windup telegraph is
## read as progress through state_started_tick..state_ends_tick, never as a free
## running clock, so a longer windup holds each pose longer instead of speeding
## up. The last frame owns the closed end of the window.
static func phase_frame_index(frame_count: int, state_started_tick: int, state_ends_tick: int, now_tick: int) -> int:
	if frame_count <= 1:
		return 0
	var window := state_ends_tick - state_started_tick
	if window <= 0:
		return 0
	var progress := clampf(float(now_tick - state_started_tick) / float(window), 0.0, 1.0)
	return mini(int(floor(progress * float(frame_count))), frame_count - 1)


## Published length of a clip in 30Hz ticks: the window a one-shot action stays
## live for, and the shortest window a call site may round a duration up to.
static func duration_ticks_for(frame_count: int, fps: int) -> int:
	if frame_count <= 0:
		return 0
	return maxi(1, ceili(float(frame_count) / float(maxi(1, fps)) * float(SIM_TICKS_PER_SECOND)))


## The agreed length of one action from the hand-off contract, before delivery.
static func agreed_duration_ticks(action: String) -> int:
	var agreed := ACTION_CONTRACT.get(action, {}) as Dictionary
	if agreed.is_empty():
		return 0
	return duration_ticks_for(int(agreed.get("frames", 1)), int(agreed.get("fps", 8)))


## Two-way facing bucket. Enemies are published east and mirrored to west, and
## the old calibration read flipped on exactly the same test, so a zero or
## upward heading stays east.
static func facing_key(facing: Variant) -> String:
	if facing is String:
		var name := String(facing).to_lower()
		return name if FACINGS.has(name) else "east"
	if facing == null or not (facing is Vector2):
		return "east"
	return "west" if (facing as Vector2).x < -0.001 else "east"


## The arena's role key for one authoritative enemy kind. Unknown kinds read as
## the melee silhouette, exactly like the calibration mapping did.
static func role_key(kind_id: String) -> String:
	match kind_id:
		"charging_raider":
			return "charger"
		"fan_ranged":
			return "ranged"
		"melee_pursuer":
			return "melee"
	return kind_id if ROLES.has(kind_id) else "melee"


## Records the first tick of one event. Returns true only that first time, so a
## repeated call from a redraw, a second view or the same drop id is a no-op.
func latch_event(kind: String, event_id: String, tick: int) -> bool:
	if kind.is_empty() or event_id.is_empty():
		return false
	var current: Variant = _events.get(kind, null)
	if current is Dictionary and String((current as Dictionary).get("id", "")) == event_id:
		return false
	_events[kind] = {"id": event_id, "tick": tick}
	return true


func latched_event_id(kind: String) -> String:
	var current: Variant = _events.get(kind, null)
	if not current is Dictionary:
		return ""
	return String((current as Dictionary).get("id", ""))


## Age of the latched event, or -1 when this kind never fired. A clip therefore
## never restarts because something was drawn again.
func latched_ticks(kind: String, now_tick: int) -> int:
	var current: Variant = _events.get(kind, null)
	if not current is Dictionary:
		return -1
	return maxi(0, now_tick - int((current as Dictionary).get("tick", now_tick)))


func clear_events() -> void:
	_events.clear()


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
	report["production"] = production_report()
	return report


func last_frame() -> Dictionary:
	return _last_frame.duplicate(true)


## Resolves one frame for the current state. The result is always explicit about
## which branch it took:
##   fallback == true   the caller keeps its approved calibration cell and reason
##                      names the cause
##   fallback == false  rect/anchor/texture come from the manifest frame, and the
##                      caller must read the anchor per frame instead of assuming
##                      a cell slot
func resolve(state: Dictionary = {}) -> Dictionary:
	var tick := int(state.get("tick", -1))
	var role := role_key(String(state.get("role", "melee")))
	var facing := facing_key(state.get("facing", "east"))
	var action := live_action(state)
	if not has_real_art():
		return _record_resolution(fallback_frame(role, facing, action, clock_ticks(action, state)), tick)
	var read := _read_clip(role, facing, action)
	var info := read.get("info", {}) as Dictionary
	if info.is_empty():
		return _record_resolution(fallback_frame(role, facing, action, clock_ticks(action, state)), tick)
	var frames := info.get("frames", []) as Array
	var fps := int(info.get("fps", 8))
	var loop := bool(info.get("loop", false))
	var index := 0
	if bool(info.get("phase_normalized", false)):
		index = phase_frame_index(frames.size(), int(state.get("state_started_tick", tick)), int(state.get("state_ends_tick", tick)), tick)
	else:
		index = frame_index_for(frames.size(), fps, float(clock_ticks(action, state)) / float(SIM_TICKS_PER_SECOND), loop)
	var frame := _sprites.get(String(frames[clampi(index, 0, frames.size() - 1)]), {}) as Dictionary
	if frame.is_empty():
		return _record_resolution(fallback_frame(role, facing, action, clock_ticks(action, state)), tick)
	return _record_resolution({
		"role": role,
		"action": action,
		"facing": facing,
		"clip": String(read.get("clip", "")),
		"frame": index,
		"frame_count": frames.size(),
		"rect": frame.get("rect", Rect2i()),
		"anchor": frame.get("anchor", DEFAULT_ANCHOR),
		"texture": _textures.get(String(frame.get("texture_key", "")), null),
		"texture_path": String(frame.get("texture_path", "")),
		"source_texture_path": String(frame.get("source_texture_path", "")),
		"texture_key": String(frame.get("texture_key", "")),
		"source": String(frame.get("source", "")),
		"fps": fps,
		"loop": loop,
		"mirrored": bool(read.get("mirrored", false)),
		"flip_x": bool(read.get("flip_x", false)),
		"duration_ticks": int(info.get("duration_ticks", 0)),
		"progress_ticks": clock_ticks(action, state),
		"phase_normalized": bool(info.get("phase_normalized", false)),
		"fallback": false,
		"fallback_sprite_id": "",
		"state": _state,
		"reason": "",
	}, tick)


## The integration report is only ever as truthful as the last real resolve, so
## every path through resolve() records what it handed over.
func _record_resolution(frame: Dictionary, tick: int) -> Dictionary:
	frame["resolved_tick"] = tick
	_last_frame = frame.duplicate(true)
	return frame


## The explicit pending/invalid answer: fallback is the caller's approved
## calibration cell plus a reason, never a silent pass.
func fallback_frame(role: String, facing: String, action := "idle", clock := 0) -> Dictionary:
	return {
		"role": role,
		"action": action,
		"facing": facing,
		"clip": "",
		"frame": -1,
		"frame_count": 0,
		"rect": Rect2i(),
		"anchor": DEFAULT_ANCHOR,
		"texture": null,
		"texture_key": "",
		"source": "",
		"fps": 0,
		"loop": false,
		"mirrored": facing == "west",
		"flip_x": facing == "west",
		"duration_ticks": 0,
		"progress_ticks": clock,
		"phase_normalized": false,
		"fallback": true,
		"fallback_sprite_id": fallback_sprite_id(role, String(_fallback_state_for(action))),
		"state": _state,
		"reason": pending_reason(),
	}


static func _fallback_state_for(action: String) -> String:
	match action:
		"windup":
			return "windup"
		"active":
			return "active"
		"recover":
			return "recovery"
	return "none"


## First action whose trigger is live. An authoritative windup/active outranks a
## hit reaction; the death clip outranks everything; one-shot reactions drop out
## on their own published length, so a counter that outlives its clip falls
## through here.
func live_action(state: Dictionary) -> String:
	for action: String in ACTION_PRIORITY:
		if action == "idle":
			return action
		if _trigger_is_live(action, state):
			return action
	return "idle"


func _trigger_is_live(action: String, state: Dictionary) -> bool:
	var action_state := String(state.get("action_state", "none"))
	match action:
		"death":
			return bool(state.get("dead", false))
		"windup":
			return action_state == "windup"
		"active":
			return action_state == "active"
		"recover":
			return action_state == "recovery"
		"hit":
			var ticks := action_ticks(action, state)
			if ticks < 0:
				return false
			var window := _role_hit_window(state)
			return window <= 0 or ticks < window
		"walk":
			return bool(state.get("moving", false))
	return false


## Brief reaction window: the published hit length, or the agreed contract number
## while the pack is pending. The role only matters once the atlas is delivered.
func _role_hit_window(state: Dictionary) -> int:
	return clip_duration_ticks(role_key(String(state.get("role", "melee"))), "hit")


## Raw counter behind one action, -1 when the caller did not offer one.
func action_ticks(action: String, state: Dictionary) -> int:
	match action:
		"death":
			return maxi(0, int(state.get("death_ticks", 0))) if bool(state.get("dead", false)) else -1
		"walk", "idle":
			return int(state.get("phase_ticks", 0))
		"hit":
			return int(state.get("hit_ticks", -1))
	return -1


## Clock a clip is sampled at: looping clips run on the loop clock, one-shot
## clips on their own age. Windup is phase-normalized instead and ignores it.
func clock_ticks(action: String, state: Dictionary) -> int:
	if action == "idle" or action == "walk":
		return int(state.get("phase_ticks", 0))
	return maxi(0, action_ticks(action, state))


## The clip read for one role/facing/action: the declared east clip, a declared
## west clip when the pack publishes one, or the east clip mirrored.
func _read_clip(role: String, facing: String, action: String) -> Dictionary:
	var east := clip_id(role, "east", action)
	var east_info := _animations.get(east, {}) as Dictionary
	if east_info.is_empty():
		return {}
	if facing == "east":
		return {"clip": east, "info": east_info, "flip_x": false, "mirrored": false}
	var west := clip_id(role, "west", action)
	var west_info := _animations.get(west, {}) as Dictionary
	if not west_info.is_empty():
		return {"clip": west, "info": west_info, "flip_x": false, "mirrored": false}
	return {"clip": east, "info": east_info, "flip_x": true, "mirrored": true}


## ------------------------------------------------------------------ reading

func _read_atlas(path: String, atlas_override: Dictionary) -> void:
	if not atlas_override.is_empty():
		_validate(atlas_override)
		return
	if not FileAccess.file_exists(path):
		_state = STATE_PENDING
		_reasons.append("ASSETS PENDING: %s (enemy action atlas)" % path)
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_state = STATE_PENDING
		_reasons.append("ASSETS PENDING: cannot open %s (enemy action atlas)" % path)
		return
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		_state = STATE_INVALID
		_reasons.append("delivered atlas %s is not valid JSON: %s" % [path, json.get_error_message()])
		return
	var parsed: Variant = json.data
	if not parsed is Dictionary:
		_state = STATE_INVALID
		_reasons.append("delivered atlas %s is not a JSON object" % path)
		return
	_validate(parsed as Dictionary)


func _validate(atlas: Dictionary) -> void:
	_reasons.clear()
	_notes.clear()
	_pending_alias_checks.clear()
	_sprites.clear()
	_animations.clear()
	_texture_meta.clear()
	_production = {}
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
	_validate_production_ids()
	_state = STATE_READY if _reasons.is_empty() else STATE_INVALID


func _validate_declared_cell(atlas: Dictionary) -> void:
	## The pipeline writes cell_size; cell is accepted as the same statement.
	for key: String in ["cell", "cell_size"]:
		if atlas.has(key):
			var cell: Variant = atlas.get(key)
			if not _integer_list(cell, 2) or Vector2i(int((cell as Array)[0]), int((cell as Array)[1])) != CELL:
				_reasons.append("atlas %s must be [%d,%d]" % [key, CELL.x, CELL.y])
	if atlas.has("anchor"):
		var anchor: Variant = atlas.get("anchor")
		if not _integer_list(anchor, 2) or Vector2i(int((anchor as Array)[0]), int((anchor as Array)[1])) != DEFAULT_ANCHOR:
			_reasons.append("atlas anchor must be [%d,%d]" % [DEFAULT_ANCHOR.x, DEFAULT_ANCHOR.y])


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
		return
	var enemies_path := String((_texture_meta[TEXTURE_KEY] as Dictionary).get("path", ""))
	if enemies_path != TEXTURE_PATH:
		if enemies_path.ends_with("enemies.png"):
			## Drift that still draws: a sheet under the agreed name somewhere else in
			## the project. Reported, and the delivery gate wants the note empty.
			_notes.append("the enemies sheet is published at %s, the hand-off agreed %s" % [enemies_path, TEXTURE_PATH])
		else:
			_reasons.append("the %s texture must be published as %s" % [TEXTURE_KEY, TEXTURE_PATH])


func _validate_style_textures(atlas: Dictionary) -> void:
	_style_texture_paths.clear()
	var bindings: Variant = atlas.get("render_textures", {})
	if not bindings is Dictionary:
		_reasons.append("render_textures must be a dictionary")
		return
	for raw_key: Variant in bindings.keys():
		var key := String(raw_key)
		var binding: Variant = bindings[raw_key]
		if key != TEXTURE_KEY or not binding is Dictionary:
			_reasons.append("unsupported enemy material binding: %s" % key)
			continue
		var source: Dictionary = _texture_meta.get(key, {})
		if String(binding.get("path", "")) != STYLE_TEXTURE_PATH or int(binding.get("width", 0)) != int(source.get("width", -1)) or int(binding.get("height", 0)) != int(source.get("height", -1)):
			_reasons.append("enemy material skin must preserve the source dimensions at %s" % STYLE_TEXTURE_PATH)
			continue
		_style_texture_paths[key] = STYLE_TEXTURE_PATH


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
		if not _integer_list(rect_values, 4) or int((rect_values as Array)[2]) <= 0 or int((rect_values as Array)[3]) <= 0:
			_reasons.append("sprite %s rect must be four JSON integers with a positive size" % sprite_id)
			continue
		if not _integer_list(anchor_values, 2) or int((anchor_values as Array)[0]) < 0 or int((anchor_values as Array)[1]) < 0:
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
		var parts := sprite_id.split(".")
		var parsed_role := ""
		var parsed_facing := ""
		var parsed_action := ""
		if parts.size() == 4:
			parsed_role = parts[0] if ROLES.has(parts[0]) else ""
			parsed_facing = parts[1] if FACINGS.has(parts[1]) else ""
			parsed_action = parts[2] if ACTIONS.has(parts[2]) else ""
			if parsed_role.is_empty() or parsed_facing.is_empty() or parsed_action.is_empty():
				_notes.append("sprite %s is not part of the agreed three-role matrix" % sprite_id)
		elif not parts.is_empty():
			_notes.append("sprite %s is not part of the agreed three-role matrix" % sprite_id)
		var anchor := Vector2i(int((anchor_values as Array)[0]), int((anchor_values as Array)[1]))
		if anchor != DEFAULT_ANCHOR:
			## The west read mirrors about the (24,44) anchor; another anchor means the
			## mirrored cell lands somewhere the east cell never stood.
			_notes.append("sprite %s anchors at %s, the hand-off agreed %s" % [sprite_id, str(anchor), str(DEFAULT_ANCHOR)])
		_sprites[sprite_id] = {
			"rect": cell_rect,
			"anchor": anchor,
			"texture_key": texture_key,
			"texture_path": String(_style_texture_paths.get(texture_key, texture_meta.get("path", ""))),
			"source_texture_path": String(texture_meta.get("path", "")),
			"texture_size": texture_size,
			"role": String(entry.get("role", parsed_role)),
			"facing": String(entry.get("facing", parsed_facing)),
			"state": String(entry.get("state", entry.get("action", parsed_action))),
			## A published pose may be reused across actions (idle is the same-facing
			## recovery); the atlas has to say so.
			"source": String(entry.get("source", entry.get("source_pose", ""))),
		}


func _validate_animations(atlas: Dictionary) -> void:
	var declared: Variant = atlas.get("animations", null)
	if not declared is Dictionary:
		_reasons.append("atlas animations must be a dictionary")
		return
	var animations := declared as Dictionary
	for role: String in ROLES:
		for action: String in ACTIONS:
			_validate_clip(animations, role, "east", action, true)
	for raw_id: Variant in animations.keys():
		var clip := String(raw_id)
		var parts := clip.split(".")
		var known := parts.size() == 3 and ROLES.has(parts[0]) and FACINGS.has(parts[1]) and ACTIONS.has(parts[2])
		if not known:
			_notes.append("animation %s is not part of the agreed three-role matrix" % clip)
			continue
		if parts[1] == "west":
			_validate_clip(animations, parts[0], "west", parts[2], false)


func _validate_clip(animations: Dictionary, role: String, facing: String, action: String, required: bool) -> void:
	var clip := clip_id(role, facing, action)
	var value: Variant = animations.get(clip, null)
	if not value is Dictionary:
		if required:
			_reasons.append("animation %s is missing from the delivered atlas" % clip)
		else:
			_notes.append("animation %s is declared in the matrix but absent" % clip)
		return
	var entry := value as Dictionary
	var frames: Variant = entry.get("frames", null)
	if not frames is Array or (frames as Array).is_empty():
		_reasons.append("animation %s requires a non-empty frames array" % clip)
		return
	var agreed := ACTION_CONTRACT[action] as Dictionary
	var fps := int(entry.get("fps", agreed["fps"]))
	if fps < 1:
		_reasons.append("animation %s fps must be a positive integer" % clip)
		return
	var loop := bool(entry.get("loop", agreed["loop"]))
	var resolved: Array[String] = []
	for raw_frame: Variant in frames as Array:
		var frame_id := String(raw_frame)
		var frame := _sprites.get(frame_id, {}) as Dictionary
		if frame.is_empty():
			_reasons.append("animation %s frame %s is not a validated sprite" % [clip, frame_id])
			return
		var declared_role := String(frame.get("role", ""))
		if not declared_role.is_empty() and declared_role != role:
			_reasons.append("animation %s frame %s declares role %s" % [clip, frame_id, declared_role])
			return
		var declared_facing := String(frame.get("facing", ""))
		if not declared_facing.is_empty() and declared_facing != facing:
			_reasons.append("animation %s frame %s declares facing %s" % [clip, frame_id, declared_facing])
			return
		var declared_state := String(frame.get("state", ""))
		if not declared_state.is_empty() and declared_state != action:
			if action == "idle" and _frame_shares_recover_cell(role, frame_id):
				## The published contract: a standing enemy reuses the same-facing
				## recovery cell instead of a fourteenth drawing. Fully disclosed in the
				## production report, so it needs no separate reuse note here.
				resolved.append(frame_id)
				continue
			if String(frame.get("source", "")).is_empty():
				_reasons.append("animation %s frame %s declares state %s" % [clip, frame_id, declared_state])
				return
			## Disclosed cross-animation reuse (idle = the same-facing recovery):
			## accepted, but recorded instead of hidden.
			_notes.append("animation %s frame %s reuses the disclosed %s pose %s" % [clip, frame_id, declared_state, String(frame.get("source", ""))])
		resolved.append(frame_id)
	_animations[clip] = {
		"frames": resolved,
		"fps": fps,
		"loop": loop,
		"phase_normalized": action == "windup",
		"duration_ticks": duration_ticks_for(resolved.size(), fps) if not loop else 0,
	}
	_note_contract(clip, action, resolved.size(), fps, loop)


## The 13 east IDs of every role are the strict production set. The idle slot may
## be published as its own declared cell (aliasing the recover cell) or implicitly
## by pointing the idle clip at recover.0; either way the alias itself is checked
## and named in the production report.
func _validate_production_ids() -> void:
	var missing: Array[String] = []
	var alias_ids: Array[String] = []
	var mode := ""
	for role: String in ROLES:
		for id: String in required_east_ids(role):
			if _sprites.has(id):
				continue
			if id == "%s.east.idle.0" % role and _implicit_idle_alias(role):
				mode = IDLE_ALIAS_MODE_IMPLICIT if mode.is_empty() else mode
				alias_ids.append(id)
				continue
			missing.append(id)
		if mode.is_empty() and _sprites.has("%s.east.idle.0" % role):
			mode = IDLE_ALIAS_MODE_DECLARED
		_validate_idle_alias(role)
	if not missing.is_empty():
		_reasons.append("atlas is missing the production sprite(s) %s" % ", ".join(PackedStringArray(missing)))
	_production = {
		"missing_east_ids": missing,
		"alias_ids": alias_ids,
		"idle_alias_mode": mode,
	}


## True when the idle clip stands on the recover cell without a separate ID.
func _implicit_idle_alias(role: String) -> bool:
	var recover_id := "%s.east.recover.0" % role
	if not _sprites.has(recover_id):
		return false
	var info := _animations.get(clip_id(role, "east", "idle"), {}) as Dictionary
	var frames := info.get("frames", []) as Array
	if frames.size() != 1 or String(frames[0]) != recover_id:
		return false
	if String((_sprites[recover_id] as Dictionary).get("state", "")) not in ["", "recover", "idle"]:
		return false
	return true


## True when this frame really is the role's recovery cell: the same published
## ID, or a cell that lands on exactly the same rect and anchor.
func _frame_shares_recover_cell(role: String, frame_id: String) -> bool:
	var recover_id := "%s.east.recover.0" % role
	if frame_id == recover_id:
		return true
	var frame := _sprites.get(frame_id, {}) as Dictionary
	var recover := _sprites.get(recover_id, {}) as Dictionary
	if frame.is_empty() or recover.is_empty():
		return false
	return frame.get("rect", Rect2i()) == recover.get("rect", Rect2i()) and frame.get("anchor", Vector2i.ZERO) == recover.get("anchor", Vector2i.ZERO)


## The published contract is that idle reuses the same-facing recovery cell. A
## distinct standing pose is drawn, but it is not the agreed alias and is
## reported as drift instead of passing for it.
func _validate_idle_alias(role: String) -> void:
	var idle_id := "%s.east.idle.0" % role
	var recover_id := "%s.east.recover.0" % role
	if not _sprites.has(idle_id) or not _sprites.has(recover_id):
		return
	var idle := _sprites[idle_id] as Dictionary
	var recover := _sprites[recover_id] as Dictionary
	if idle.get("rect", Rect2i()) == recover.get("rect", Rect2i()):
		return
	## The published packing gives the alias its own cell; the pixels then have to
	## prove the reuse, which needs the sheet loaded.
	_pending_alias_checks.append({"idle_id": idle_id, "recover_id": recover_id})


## Cross-checks the alias on the real pixels once the sheet is in hand. A sheet
## this build cannot read back proves nothing and is never reported as drift.
func _resolve_alias_checks() -> void:
	for check: Dictionary in _pending_alias_checks:
		var idle_id := String(check["idle_id"])
		var recover_id := String(check["recover_id"])
		var idle_image := _cell_image(_sprites.get(idle_id, {}) as Dictionary)
		var recover_image := _cell_image(_sprites.get(recover_id, {}) as Dictionary)
		if idle_image == null or recover_image == null:
			continue
		if not _images_match(idle_image, recover_image):
			_notes.append("sprite %s is not the agreed %s drawing" % [idle_id, recover_id])
	_pending_alias_checks.clear()


## Two published cells are the same drawing when every pixel visible in either of
## them is identical. The RGB under a fully transparent pixel is not art -- the
## importer itself re-fills it -- so it can never turn the alias into drift.
func _images_match(left: Image, right: Image) -> bool:
	if left.get_size() != right.get_size() or left.get_format() != right.get_format():
		return false
	var a := left.get_data()
	var b := right.get_data()
	if a == b:
		return true
	if left.get_format() != Image.FORMAT_RGBA8 or a.size() != b.size():
		return false
	for index in range(0, a.size(), 4):
		if a[index + 3] == 0 and b[index + 3] == 0:
			continue
		if a[index] != b[index] or a[index + 1] != b[index + 1] or a[index + 2] != b[index + 2] or a[index + 3] != b[index + 3]:
			return false
	return true


## The published pixels of one validated cell, or null when this build has no
## source pixels to compare (a release pack without the raw sheet). A null answer
## proves nothing, so it is never reported as drift.
func _cell_image(sprite: Dictionary) -> Image:
	if sprite.is_empty():
		return null
	var image: Image = _raw_images.get(String(sprite.get("texture_key", "")), null)
	if image == null:
		return null
	var rect: Rect2i = sprite.get("rect", Rect2i())
	if not Rect2i(Vector2i.ZERO, image.get_size()).encloses(rect):
		return null
	return image.get_region(rect)


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
				_remember_raw_pixels(texture_key, path)
				continue
		var file := _open_resource(path)
		var image := Image.new()
		if file == null or file.get_length() == 0 or image.load_png_from_buffer(file.get_buffer(file.get_length())) != OK:
			_reasons.append("cannot load %s" % path)
			continue
		if image.get_size() != expected:
			_reasons.append("%s is %s, the atlas says %s (stale metadata?)" % [path, str(image.get_size()), str(expected)])
			continue
		_raw_images[texture_key] = image
		_textures[texture_key] = ImageTexture.create_from_image(image)
	if not _reasons.is_empty():
		_state = STATE_INVALID
		return
	_resolve_alias_checks()


## The published bytes of one declared texture, decoded for the pixel
## cross-checks only. A release pack without source files simply has nothing to
## compare, which is never reported as drift.
func _remember_raw_pixels(texture_key: String, path: String) -> void:
	var file := _open_resource(path)
	if file == null or file.get_length() == 0:
		return
	var image := Image.new()
	if image.load_png_from_buffer(file.get_buffer(file.get_length())) == OK:
		_raw_images[texture_key] = image


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
	for number: Variant in value as Array:
		if typeof(number) not in [TYPE_INT, TYPE_FLOAT]:
			return false
		if not is_finite(float(number)) or float(number) != floor(float(number)):
			return false
	return true
