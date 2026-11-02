extends RefCounted
## Shared reader for the actor action atlases (RangerAnimation, EnemyAnimation):
## the ready/pending/invalid asset state and its reasons, atlas loading, the
## published sprite and clip tables, frame lookup, one-shot event latching and
## the integration record. Subclasses validate their own atlas contract in
## _validate() and supply their identity through the hooks at the end.

## The action cell shared by every actor pack (48x48); each reader documents
## its foot anchor next to DEFAULT_ANCHOR.
const CELL := Vector2i(48, 48)
const SIM_TICKS_PER_SECOND := 30
const STATE_READY := "ready"
## The atlas has not been delivered yet: the reader's approved static cells stay
## on screen as an explicit, reported fallback.
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
var _events := {}
var _last_frame := {}


func asset_state() -> String:
	return _state


## True only when a validated manifest and every declared texture are in hand.
## Views draw the action frames exactly when this is true.
func has_real_art() -> bool:
	return _state == STATE_READY and not _textures.is_empty() and _textures.size() == _texture_meta.size()


## While this is true the caller must draw its own approved static idle cell.
## It is never silent: pending_reason() always names the cause.
func using_fallback() -> bool:
	return not has_real_art()


func pending_reasons() -> Array[String]:
	return _reasons.duplicate()


## Timings that were agreed for a delivered atlas but disagree with it. Empty on
## a pack that matches the hand-off; the frames themselves still come from the
## manifest either way.
func contract_notes() -> Array[String]:
	return _notes.duplicate()


func texture_path() -> String:
	## Logical source sheet; render_texture_path() names the pixels actually drawn.
	return String((_texture_meta.get(_texture_key(), {}) as Dictionary).get("path", ""))


func render_texture_path() -> String:
	return String(_style_texture_paths.get(_texture_key(), texture_path()))


func clip_info(clip: String) -> Dictionary:
	return (_animations.get(clip, {}) as Dictionary).duplicate(true)


## Explicit frame access for the art pass and fixtures. Frames before a clip's
## runtime entry (the shoot preparation) are reachable here and nowhere else in
## the runtime, so a prepared-bow pose can be inspected without ever being drawn
## as a live shot.
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
		"anchor": frame.get("anchor", _default_anchor()),
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


## Integer frame for a clip at a given age. Looping clips wrap, one-shot clips
## hold their last published frame (the death hold).
static func frame_index_for(frame_count: int, fps: int, seconds: float, loop: bool) -> int:
	if frame_count <= 1:
		return 0
	var step := int(floor(maxf(0.0, seconds) * float(maxi(1, fps))))
	if loop:
		return posmod(step, frame_count)
	return mini(step, frame_count - 1)


## Published length of a clip in 30Hz ticks: the window a one-shot action stays
## live for, and the shortest window a call site may round a duration up to.
static func duration_ticks_for(frame_count: int, fps: int) -> int:
	if frame_count <= 0:
		return 0
	return maxi(1, ceili(float(frame_count) / float(maxi(1, fps)) * float(SIM_TICKS_PER_SECOND)))


## Records the first tick of one event. Returns true only that first time, so a
## repeated call from a redraw, a second view or the same cast id is a no-op.
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


func last_frame() -> Dictionary:
	return _last_frame.duplicate(true)


## The integration report is only ever as truthful as the last real resolve, so
## every path through resolve() records what it handed over.
func _record_resolution(frame: Dictionary, tick: int) -> Dictionary:
	frame["resolved_tick"] = tick
	_last_frame = frame.duplicate(true)
	return frame


func _validate_declared_cell(atlas: Dictionary) -> void:
	## The pipeline writes cell_size; cell is accepted as the same statement.
	for key: String in ["cell", "cell_size"]:
		if atlas.has(key):
			var cell: Variant = atlas.get(key)
			if not integer_list(cell, 2) or Vector2i(int((cell as Array)[0]), int((cell as Array)[1])) != CELL:
				_reasons.append("atlas %s must be [%d,%d]" % [key, CELL.x, CELL.y])
	if atlas.has("anchor"):
		var anchor: Variant = atlas.get("anchor")
		if not integer_list(anchor, 2) or Vector2i(int((anchor as Array)[0]), int((anchor as Array)[1])) != _default_anchor():
			_reasons.append("atlas anchor must be [%d,%d]" % [_default_anchor().x, _default_anchor().y])


## Raw-file fallback for an unimported development tree. Imported PNG resources
## are handled above; globalizing a missing raw PNG cannot recreate it in a PCK.
static func open_resource(path: String) -> FileAccess:
	var file := FileAccess.open(path, FileAccess.READ)
	if file != null:
		return file
	return FileAccess.open(ProjectSettings.globalize_path(path), FileAccess.READ)


static func integer_list(value: Variant, count: int) -> bool:
	if not value is Array or (value as Array).size() != count:
		return false
	for number: Variant in value as Array:
		if typeof(number) not in [TYPE_INT, TYPE_FLOAT]:
			return false
		if not is_finite(float(number)) or float(number) != floor(float(number)):
			return false
	return true


func _read_atlas(path: String, atlas_override: Dictionary) -> void:
	if not atlas_override.is_empty():
		_validate(atlas_override)
		return
	if not FileAccess.file_exists(path):
		_state = STATE_PENDING
		_reasons.append("ASSETS PENDING: %s (%s action atlas)" % [path, _reader_label()])
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_state = STATE_PENDING
		_reasons.append("ASSETS PENDING: cannot open %s (%s action atlas)" % [path, _reader_label()])
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


func _validate_style_textures(atlas: Dictionary) -> void:
	_style_texture_paths.clear()
	var bindings: Variant = atlas.get("render_textures", {})
	if not bindings is Dictionary:
		_reasons.append("render_textures must be a dictionary")
		return
	for raw_key: Variant in bindings.keys():
		var key := String(raw_key)
		var binding: Variant = bindings[raw_key]
		if key != _texture_key() or not binding is Dictionary:
			_reasons.append("unsupported %s material binding: %s" % [_reader_label(), key])
			continue
		var source: Dictionary = _texture_meta.get(key, {})
		if String(binding.get("path", "")) != _style_texture_path() or int(binding.get("width", 0)) != int(source.get("width", -1)) or int(binding.get("height", 0)) != int(source.get("height", -1)):
			_reasons.append("%s material skin must preserve the source dimensions at %s" % [_reader_label(), _style_texture_path()])
			continue
		_style_texture_paths[key] = _style_texture_path()


## ------------------------------------------------------------------- hooks

## Validates a parsed atlas against the subclass contract.
func _validate(_atlas: Dictionary) -> void:
	pass


func _texture_key() -> String:
	return ""


func _default_anchor() -> Vector2i:
	return Vector2i.ZERO


func _style_texture_path() -> String:
	return ""


func _reader_label() -> String:
	return "actor"
