class_name LoadoutCharacterView
extends Control

## Read-only hero preview for the loadout page.
##
## It draws one published frame of res://art/production/p1/ranger_actions_v01 at
## an integer multiple of the atlas' own 48x48 cell, so every source pixel stays
## a whole block of display pixels and the hero keeps the same body he has in the
## arena, the hamlet and the tutorial. The frame comes from the same
## RangerAnimation reader those scenes use; this view owns no gameplay state,
## never writes one, and never draws a second hero or another class.
##
## The pose is the current ranger's published idle frame, and the page's own
## caption says so: this is the hero body, not a paper doll, so it never claims
## that an equipped item has changed what the hero looks like.
##
## While the atlas is pending or invalid the view draws nothing at all and hands
## the reader's own reason to the page: a missing pack is reported, never filled
## in with another facing, another action, or a stand-in body.
const RangerAnimationScript = preload("res://src/presentation/ranger_animation.gd")
const ShellThemeScript = preload("res://src/presentation/shell_theme.gd")

## The published cell contract of the action atlas. The view reads the real cell
## from the manifest frame and reports a frame that disagrees with it.
const NATIVE_CELL := Vector2i(48, 48)
## Display scale. An integer multiple only: 4x fills the authored 192px hero
## lane exactly.
const DISPLAY_SCALE := 4
## The current ranger's published appearance on this page: the profile frame that
## reads the bow, held on the idle clip at its first frame. The page is static, so
## the preview never animates and never implies a live action or a cast.
const FACING := "east"
const ACTION := "idle"
## Ground contact: the manifest foot anchor is the single contact point the arena
## also uses, so the drawn ground line sits exactly under the feet. Presentation
## only; it is not a hitbox and carries no gameplay value.
const GROUND_WIDTH := 2
const GROUND_SPAN := 0.32

var _reader
var _frame: Dictionary = {}
var _state := RangerAnimationScript.STATE_PENDING
var _notes: Array[String] = []


func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reader = RangerAnimationScript.new()
	resized.connect(queue_redraw)


## Resolves the published frame this page shows and sizes the view for it. Safe
## to call before the view enters the tree; drawing itself waits for the layout.
func refresh() -> void:
	_notes.clear()
	_state = String(_reader.asset_state())
	_frame = {}
	custom_minimum_size = Vector2(NATIVE_CELL) * float(DISPLAY_SCALE)
	if not _reader.has_real_art():
		_notes.append(String(_reader.pending_reason()))
		queue_redraw()
		return
	# A fixed, closed state: no tick, no action counter, no clock. The reader
	# resolves it through its own published frame table, and a fallback answer is
	# reported instead of drawn.
	var resolved: Dictionary = _reader.resolve({
		"facing": FACING,
		"moving": false,
		"dead": false,
		"hit_ticks": -1,
		"dodge_ticks": -1,
		"dash_ticks": -1,
		"shoot_ticks": -1,
		"phase_ticks": 0,
		"tick": 0,
	})
	if bool(resolved.get("fallback", true)):
		_state = String(resolved.get("state", _state))
		_notes.append(String(resolved.get("reason", _reader.pending_reason())))
		queue_redraw()
		return
	var rect: Rect2i = resolved.get("rect", Rect2i())
	if resolved.get("texture") == null or rect.size.x <= 0 or rect.size.y <= 0:
		_notes.append("ASSETS PENDING: the resolved %s.%s frame carries no drawable region" % [FACING, ACTION])
		queue_redraw()
		return
	_frame = resolved
	if rect.size != NATIVE_CELL:
		_notes.append("cell drift: the manifest frame is %sx%s, the published cell is %sx%s" % [
			rect.size.x, rect.size.y, NATIVE_CELL.x, NATIVE_CELL.y,
		])
	queue_redraw()


## True while the page draws the published frame. False means the view is blank
## and pending_reasons() says why.
func is_drawing() -> bool:
	return not _frame.is_empty()


func native_cell() -> Vector2i:
	if _frame.is_empty():
		return NATIVE_CELL
	var rect: Rect2i = _frame.get("rect", Rect2i(Vector2i.ZERO, NATIVE_CELL))
	return rect.size


func display_pixels() -> Vector2i:
	return native_cell() * DISPLAY_SCALE


## Everything the page's caption and the art pass may quote about the preview:
## the exact clip and frame, the cell, the integer display scale, and the reader's
## own state. No derived value, no estimated size.
func frame_report() -> Dictionary:
	var rect: Rect2i = _frame.get("rect", Rect2i(Vector2i.ZERO, NATIVE_CELL))
	var anchor: Vector2i = _frame.get("anchor", RangerAnimationScript.DEFAULT_ANCHOR)
	return {
		"state": _state,
		"drawing": not _frame.is_empty(),
		"clip": String(_frame.get("clip", "")),
		"frame": int(_frame.get("frame", -1)),
		"facing": FACING,
		"action": ACTION,
		"cell": [rect.size.x, rect.size.y],
		"display_scale": DISPLAY_SCALE,
		"display_pixels": [rect.size.x * DISPLAY_SCALE, rect.size.y * DISPLAY_SCALE],
		"anchor": [anchor.x, anchor.y],
		"atlas_path": RangerAnimationScript.ATLAS_PATH,
		"texture_path": _reader.texture_path(),
		"notes": _notes.duplicate(),
	}


func pending_reasons() -> Array[String]:
	return _notes.duplicate()


func _draw() -> void:
	if _frame.is_empty():
		return
	var texture: Texture2D = _frame.get("texture")
	var rect: Rect2i = _frame.get("rect", Rect2i())
	if texture == null or rect.size.x <= 0 or rect.size.y <= 0:
		return
	var scale := float(DISPLAY_SCALE)
	var drawn := Vector2(rect.size) * scale
	var origin := Vector2(
		roundf((size.x - drawn.x) * 0.5),
		roundf(maxf(0.0, (size.y - drawn.y) * 0.5))
	)
	var anchor: Vector2i = _frame.get("anchor", RangerAnimationScript.DEFAULT_ANCHOR)
	var foot := origin + Vector2(anchor) * scale
	var half := drawn.x * GROUND_SPAN
	# A quiet etched plinth grounds the real character, without faking equipment
	# appearance or covering any opaque character pixels.
	var seal_center := Vector2(foot.x, foot.y - 60)
	draw_arc(seal_center, 71, -PI*0.90, PI*0.20, 32, Color("465048"), 2, false)
	draw_arc(seal_center, 64, PI*0.21, PI*1.10, 32, Color("765b3c"), 1, false)
	for i in range(8):
		var angle := float(i) * TAU / 8
		var direction := Vector2.from_angle(angle)
		draw_line(seal_center + direction*68, seal_center+direction*75, Color("87704c"), 2)
	var ground := PackedVector2Array([foot+Vector2(-half,0),foot+Vector2(0,-10),foot+Vector2(half,0),foot+Vector2(0,12)])
	draw_colored_polygon(ground, Color(0.02,0.035,0.045,0.75))
	draw_polyline(ground, Color("4c524c"), 1, false)
	draw_line(
		Vector2(foot.x - half, foot.y),
		Vector2(foot.x + half, foot.y),
		ShellThemeScript.GROUND,
		float(GROUND_WIDTH)
	)
	# The whole published cell, region to region, at the integer multiple. Nothing
	# is cropped, stretched to a non-integer size, or resampled with a smooth
	# filter: the control's texture_filter stays nearest.
	draw_texture_rect_region(texture, Rect2(origin, drawn), Rect2(rect), Color.WHITE, false, true)
