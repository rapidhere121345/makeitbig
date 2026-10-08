class_name DefeatPresentation
extends RefCounted
## Presentation-only defeat window for the published ranger death clip
## (ranger.<facing>.death: 3 frames at 6fps, the last one held).
##
## The arena hands this object every frame it resolves for its renderer, and the
## session router asks route_ready() before the result screen may replace the
## corpse. It answers one question -- have the published death frames been on
## screen long enough to be seen? -- and nothing else. It writes no gameplay
## state, reads no wall clock, and takes no part in damage, the death decision,
## the authoritative tick, rewards, drops or saves: those all latch on the death
## tick exactly as before. Only the visual route waits.
##
## The window closes when both published facts were observed:
##   * every frame of the clip was resolved at least once (the full
##     kneel / off-balance / face-down sequence), and
##   * the last frame was on screen for at least one published frame duration
##     (1/fps = 1/6s): the face-down hold the player has to see.
## The caller keeps its own hard deadline (the router's fallback clock); this
## object only reports what it saw, and a skip is always explicit and named.
##
## The unit observed is one presentation commit: the frame the arena resolved for
## its renderer on that frame, credited with that frame's presentation time. The
## pixel evidence stays the GPU capture of a real run, recorded separately.

const ACTION_DEATH := "death"
## The agreed contract timing, mirroring RangerAnimation.ACTION_CONTRACT. The
## arena passes the manifest numbers instead, so a republished clip is measured
## against its own published length rather than against this mirror.
const CLIP_FRAMES := 3
const CLIP_FPS := 6
## Summed float deltas can land a hair under a published 1/6s. That is float
## accumulation, not a frame that never showed.
const DURATION_EPSILON := 1e-6

## Nothing has been drawn yet: the window holds no evidence either way.
const STATE_WAITING := "waiting"
## Death frames are on screen but the window still owes part of the clip.
const STATE_PLAYING := "playing"
## Every published frame was seen and the last one was held long enough.
const STATE_COMPLETE := "complete"
## The caller skipped the window on purpose. Named, never silent.
const STATE_SKIPPED := "skipped"
## The single reason this object ever holds a route.
const HOLD_REASON := "defeat_clip_playing"

var _state := STATE_WAITING
var _frame_count := CLIP_FRAMES
var _fps := CLIP_FPS
var _frame_seconds := 1.0 / float(CLIP_FPS)
var _seen_frames: Array[bool] = [false, false, false]
var _seen_count := 0
var _committed_frames := 0
var _screen_seconds := 0.0
var _last_frame_seconds := 0.0
var _last_frame_index := -1
var _closed_seconds := -1.0
var _skip_reason := ""


func _init(timing: Dictionary = {}) -> void:
	if not timing.is_empty():
		_configure(int(timing.get("frames", CLIP_FRAMES)), int(timing.get("fps", CLIP_FPS)))


func state() -> String:
	return _state


func frame_count() -> int:
	return _frame_count


func frame_seconds() -> float:
	return _frame_seconds


func screen_seconds() -> float:
	return _screen_seconds


func last_frame_seconds() -> float:
	return _last_frame_seconds


func committed_frames() -> int:
	return _committed_frames


## The screen time this window closed at, or -1 while it is still open.
func closed_seconds() -> float:
	return _closed_seconds


## True when the route may move on: every published frame was resolved and the
## last one was on screen for at least one published frame duration.
func route_ready() -> bool:
	if _state == STATE_SKIPPED:
		return true
	return _seen_count >= _frame_count and _last_frame_seconds + DURATION_EPSILON >= _frame_seconds


## Empty when the route may move; otherwise the reason the window is still live.
func hold_reason() -> String:
	return "" if route_ready() else HOLD_REASON


## Records one presentation commit. `frame` is the frame the arena resolved for
## its renderer; only a published, non-fallback death frame counts, so a pending
## atlas or a live idle/hit/shoot frame can never close this window. Returns true
## once the window is closed, including the call that closed it.
func observe_frame(frame: Dictionary, screen_delta: float) -> bool:
	if _state == STATE_SKIPPED or frame.is_empty():
		return false
	if bool(frame.get("fallback", true)) or String(frame.get("action", "")) != ACTION_DEATH:
		return false
	var index := int(frame.get("frame", -1))
	if index < 0:
		return false
	var published_frames := maxi(1, int(frame.get("frame_count", _frame_count)))
	var published_fps := maxi(1, int(frame.get("fps", _fps)))
	if published_frames != _frame_count or published_fps != _fps:
		## The manifest is the timing authority: a pack that republishes the clip is
		## measured against its own numbers, and the window starts over on purpose.
		_configure(published_frames, published_fps)
	var delta := maxf(0.0, screen_delta)
	_committed_frames += 1
	_screen_seconds += delta
	_last_frame_index = index
	if index >= _seen_frames.size():
		_seen_frames.resize(index + 1)
	if not _seen_frames[index]:
		_seen_frames[index] = true
		_seen_count += 1
	if index == _frame_count - 1:
		_last_frame_seconds += delta
	if _state == STATE_WAITING:
		_state = STATE_PLAYING
	if not route_ready():
		return false
	_closed_seconds = _screen_seconds
	_state = STATE_COMPLETE
	return true


## Public skip: the caller decided the screen part is over (a player pressing
## return, an abandon request, a scripted capture). Never silent -- the reason is
## kept and reported.
func skip(reason: String = "") -> void:
	if _state == STATE_SKIPPED:
		return
	_state = STATE_SKIPPED
	_skip_reason = reason if not reason.is_empty() else "skipped"


## Back to no evidence at all: used when the hero is alive again or a new room
## starts, so a finished window can never hold a later route.
func reset() -> void:
	_state = STATE_WAITING
	_seen_count = 0
	for index in _seen_frames.size():
		_seen_frames[index] = false
	_committed_frames = 0
	_screen_seconds = 0.0
	_last_frame_seconds = 0.0
	_last_frame_index = -1
	_closed_seconds = -1.0
	_skip_reason = ""


func report() -> Dictionary:
	var missing: Array[int] = []
	for index in _frame_count:
		if index >= _seen_frames.size() or not _seen_frames[index]:
			missing.append(index)
	return {
		"state": _state,
		"route_ready": route_ready(),
		"hold_reason": hold_reason(),
		"frame_count": _frame_count,
		"fps": _fps,
		"frame_seconds": _frame_seconds,
		"committed_frames": _committed_frames,
		"frames_seen": _seen_count,
		"missing_frames": missing,
		"screen_seconds": _screen_seconds,
		"last_frame_seconds": _last_frame_seconds,
		"last_frame_index": _last_frame_index,
		"closed_seconds": _closed_seconds,
		"skip_reason": _skip_reason,
	}


func _configure(frames: int, fps: int) -> void:
	_frame_count = maxi(1, frames)
	_fps = maxi(1, fps)
	_frame_seconds = 1.0 / float(_fps)
	_seen_frames = []
	_seen_frames.resize(_frame_count)
	_state = STATE_WAITING
	reset()
