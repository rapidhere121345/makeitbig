class_name RangerMotionOverlay
extends RefCounted
## Presentation-only material and motion layer for the ranger (2026-10 pass).
##
## The authored action atlas stays the sole source of the pose. This layer
## never paints a smooth vector figure over the sprite: every accent is a
## hard-edged, integer-aligned 1 px step in the hero's own palette, and every
## accent position is derived from the published skin pixels for the exact
## (facing, action, frame) being drawn, so gear can never drift off the body
## in any of the 68 authored poses. The evidence pass is read-only: it samples
## the published atlas and texture, never writes art, gameplay state, the
## (24,44) foot anchor, or the authoritative arrow socket.

## Palette lifted from the published ranger skin pixels: cold slate cloth,
## bone cloth and hair, old copper leather and gear, plus the approved cold
## teal reserved for motion.
const INK := Color("111820")
const SLATE := Color("2a3543")
const SLATE_LIGHT := Color("91a4b4")
const BONE := Color("e9ddc3")
const BONE_SHADE := Color("d3cbb5")
const COPPER := Color("ad734d")
const COPPER_LIGHT := Color("eead56")
const COLD := Color("61a6a5")

## Published evidence sources, tried in order. The R13 pair is what the
## runtime actually draws; the v01 pair is the provenance sheet.
const EVIDENCE_ATLAS_PATHS: Array[String] = [
	"res://art/production/p1/combat_style_r13/v03/ranger_atlas.json",
	"res://art/production/p1/ranger_actions_v01/atlas.json",
]

static var _evidence_atlas: Dictionary = {}
static var _evidence_image: Image = null
static var _evidence_tried := false
static var _mask_cache: Dictionary = {}


static func motion_signature(action: String, facing: String, frame: int, time: float) -> Dictionary:
	## Pure, bounded values make this layer easy to inspect without a scene.
	## Movement actions are stride-locked: the authored frame decides the pose
	## of the cloth, so a redraw or a 144 Hz window can never desync it from
	## the legs. Wall time only drives the sub-pixel standing breath.
	var f := clampi(frame, 0, 3)
	var sway := 0.0
	var bob := 0.0
	var trail := 0.0
	match action:
		"walk":
			## Authored cycle: frames 0 and 2 are foot contacts, frames 1 and
			## 3 are the knee pass where the body rises and the hem kicks back.
			if f == 1 or f == 3:
				sway = 1.0
				bob = -1.0
		"shoot":
			sway = -0.5 if f <= 1 else (1.0 if f == 2 else 0.25)
		"dodge", "dash":
			sway = 1.0
			trail = 1.5 - 0.6 * float(f)
		"hit":
			sway = 1.25
		_:
			sway = 0.5 * sin(maxf(0.0, time) * 1.05)
			bob = 0.6 * sin(maxf(0.0, time) * 1.6 + 0.8)
	return {
		"facing": facing if facing in ["north", "south", "east", "west"] else "south",
		"sway": sway,
		"bob": bob,
		"trail": clampf(trail, 0.0, 1.5),
		"kick": 1 if sway >= 0.999 else 0,
	}


static func draw_back(
	canvas: CanvasItem,
	feet_world: Vector2,
	facing: String,
	action: String,
	frame: int,
	time: float
) -> void:
	if canvas == null:
		return
	for entry: Dictionary in _accent_plan(facing, action, frame, time):
		if bool(entry.get("front", false)):
			continue
		canvas.draw_rect(Rect2(Vector2(feet_world) + Vector2(entry["point"]), Vector2.ONE), entry["color"])


static func draw_front(
	canvas: CanvasItem,
	feet_world: Vector2,
	facing: String,
	action: String,
	frame: int,
	time: float
) -> void:
	if canvas == null:
		return
	var signature := motion_signature(action, facing, frame, time)
	var facing_name := String(signature["facing"])
	var bob := roundi(float(signature["bob"]))
	var strap := _gated_strap_points(facing_name, action, frame)
	if not strap.is_empty():
		canvas.draw_line(
			Vector2(feet_world) + Vector2(strap[0]) + Vector2(0.0, float(bob)),
			Vector2(feet_world) + Vector2(strap[1]) + Vector2(0.0, float(bob)),
			Color(INK, 0.7),
			1.0,
			false
		)
	for entry: Dictionary in _accent_plan(facing, action, frame, time):
		if not bool(entry.get("front", false)):
			continue
		canvas.draw_rect(Rect2(Vector2(feet_world) + Vector2(entry["point"]), Vector2.ONE), entry["color"])


## ------------------------------------------------------------------ plans

## Every accent this layer can draw, as integer local pixels relative to the
## foot point. "front" entries draw over the sprite, the rest behind it.
static func _accent_plan(facing: String, action: String, frame: int, time: float) -> Array[Dictionary]:
	var signature := motion_signature(action, facing, frame, time)
	var facing_name := String(signature["facing"])
	var f := clampi(frame, 0, 3)
	var bob := roundi(float(signature["bob"]))
	var kick := int(signature["kick"])
	var plan: Array[Dictionary] = []

	## Behind the sprite: hem seating and tips only; everything else reads
	## better over the authored pixels.
	for point: Vector2i in _hem_seat_pixels(facing_name, action, frame):
		plan.append({"point": point, "color": Color(INK, 0.5)})
	for point: Vector2i in _gated_hem_tips(facing_name, action, frame, kick):
		plan.append({"point": point, "color": Color(BONE, 0.95)})

	## Cloth folds: 1 px shade steps inside the authored bone mass, walking
	## every pose except the resting corpse.
	if action != "death":
		for entry: Dictionary in _cloak_fold_entries(facing_name, action, frame):
			plan.append(entry)

	## Structured quiver over the authored red shaft cluster, with the copper
	## strap pixel holding the tube to the back.
	for entry: Dictionary in _quiver_entries(facing_name, action, frame):
		plan.append(entry)
	_append_pixel(plan, _bobbed(_gated_quiver_strap_pixel(facing_name, action, frame), bob, facing_name, action, frame), Color(COPPER, 0.8))

	## Stepped shoulder plate found on the authored shoulder row.
	for entry: Dictionary in _pauldron_entries(facing_name, action, frame, bob):
		plan.append(entry)

	## The cold hood rim now traces the authored hair crown instead of an
	## invented arc above the head.
	for point: Vector2i in _hood_tick_pixels(facing_name, action, frame):
		plan.append({"point": point, "color": Color(COLD, 0.5), "front": true})

	if action == "walk":
		if f == 0 or f == 2:
			for point: Vector2i in _boot_highlight_pixels(facing_name, f):
				plan.append({"point": point, "color": Color(BONE_SHADE, 0.6), "front": true})
			_append_pixel(plan, _foot_dust_pixel(facing_name, f), Color(SLATE_LIGHT, 0.45), true)
		_append_pixel(plan, _bobbed(_gated_grip_pixel(facing_name, action, f), bob, facing_name, action, f), Color(COPPER_LIGHT, 0.8), true)
	elif action == "shoot":
		if f == 2:
			for point: Vector2i in _gated_release_pixels(facing_name, action, f):
				plan.append({"point": point, "color": Color(BONE, 0.6), "front": true})
		_append_pixel(plan, _bobbed(_gated_grip_pixel(facing_name, action, f), bob, facing_name, action, f), Color(COPPER_LIGHT, 0.7), true)
	elif action in ["dodge", "dash"]:
		var count := clampi(int(round(float(signature["trail"]) * 4.0)), 0, 6)
		var content_masks := _cell_masks(facing_name, action, frame)
		for point: Vector2i in _trail_pixels(facing_name, count):
			if facing_name in ["north", "south"] and not content_masks.is_empty() and not _near_content_cell(content_masks["content"], _to_cell(point), 1):
				continue
			plan.append({"point": point, "color": Color(COLD, 0.5)})
	elif action != "death":
		_append_pixel(plan, _bobbed(_gated_buckle_pixel(facing_name, action, frame), bob, facing_name, action, frame), Color(COPPER_LIGHT, 0.8), true)
	return plan


static func _append_pixel(plan: Array[Dictionary], point: Vector2i, color: Color, front := false) -> void:
	## Gated helpers return ZERO to say "nothing here"; never draw that.
	if point == Vector2i.ZERO:
		return
	plan.append({"point": point, "color": color, "front": front})


static func _bobbed(point: Vector2i, bob: int, facing: String, action: String, frame: int) -> Vector2i:
	## Only accents that sit on free pixels near the body may rise with the
	## pass frame; pinned accents stay locked to the authored pixels.
	if bob == 0 or point == Vector2i.ZERO:
		return point
	var masks := _cell_masks(facing, action, frame)
	if masks.is_empty():
		return point
	if _near_content_cell(masks["content"], _to_cell(point + Vector2i(0, bob)), 1):
		return point + Vector2i(0, bob)
	return point


## ------------------------------------------------------------------ rules

## 1 px shade steps inside the authored bone mass: a lower-boundary band that
## grounds the flat cloak, a behind-boundary band for side views, and two
## short interior creases. Deterministic per (facing, action, frame).
static func _cloak_fold_entries(facing: String, action: String, frame: int) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var masks := _cell_masks(facing, action, frame)
	if masks.is_empty():
		return entries
	var bone: Dictionary = masks["bone"]
	if bone.size() < 40:
		return entries
	var behind := _behind_axis(facing)
	var lower: Array[Vector2i] = []
	var side: Array[Vector2i] = []
	for point: Vector2i in bone.keys():
		var below := Vector2i(point.x, point.y + 1)
		if not bone.has(below) and point.y >= 18 and (point.x + point.y) % 2 == 0:
			lower.append(point)
		if behind.y == 0 and absi(behind.x) == 1:
			var back := point + behind
			if not bone.has(back) and point.y >= 10 and point.y <= 26 and point.y % 2 == 0:
				side.append(point)
	lower.sort()
	side.sort()
	for point: Vector2i in lower.slice(0, 14):
		entries.append({"point": _to_local(point), "color": Color(BONE_SHADE, 0.8), "front": true})
	for point: Vector2i in side.slice(0, 8):
		entries.append({"point": _to_local(point), "color": Color(BONE_SHADE, 0.55), "front": true})
	return entries


## Ink seats under the authored hem's lowest behind-half columns, so the flat
## bone mass reads as cloth resting on itself instead of a paper cutout.
static func _hem_seat_pixels(facing: String, action: String, frame: int) -> Array[Vector2i]:
	var masks := _cell_masks(facing, action, frame)
	if masks.is_empty():
		return []
	var bone: Dictionary = masks["bone"]
	var content: Dictionary = masks["content"]
	var behind := _behind_axis(facing)
	var lowest: Dictionary = {}
	for point: Vector2i in bone.keys():
		var on_behind_half := behind.x == 0 or signi(point.x - 24) == behind.x or point.x == 24
		if not on_behind_half:
			continue
		var known: int = lowest.get(point.x, -1)
		if point.y > known:
			lowest[point.x] = point.y
	var columns := lowest.keys()
	columns.sort()
	var seats: Array[Vector2i] = []
	var index := 0
	for column: Variant in columns:
		index += 1
		if index % 2 == 0:
			continue
		var seat := Vector2i(column, lowest[column] + 1)
		if seat.y > 40 or content.has(seat):
			continue
		seats.append(_to_local(seat))
		if seats.size() >= 4:
			break
	return seats


## The quiver is structured over the authored red shaft cluster: bone
## fletchings one pixel above the cluster's top row, copper nocks on it.
static func _quiver_entries(facing: String, action: String, frame: int) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var masks := _cell_masks(facing, action, frame)
	if masks.is_empty():
		return entries
	var red: Dictionary = masks["red"]
	if red.size() < 6:
		return entries
	var top := 48
	for point: Vector2i in red.keys():
		top = mini(top, point.y)
	var top_row: Array[Vector2i] = []
	for point: Vector2i in red.keys():
		if point.y <= top + 2:
			top_row.append(point)
	top_row.sort()
	if top_row.size() < 3:
		return entries
	var picks: Array[Vector2i] = [top_row[0], top_row[top_row.size() >> 1], top_row[top_row.size() - 1]]
	var used := {}
	for pick: Vector2i in picks:
		var nock := Vector2i(pick.x, pick.y)
		var fletch := Vector2i(pick.x, pick.y - 1)
		if used.has(nock):
			continue
		used[nock] = true
		if not masks["content"].has(fletch) or masks["red"].has(fletch) or fletch.y >= top:
			entries.append({"point": _to_local(nock), "color": Color(BONE, 0.95), "front": true})
		else:
			entries.append({"point": _to_local(fletch), "color": Color(BONE, 0.95), "front": true})
		entries.append({"point": _to_local(nock), "color": Color(COPPER, 0.9), "front": true})
	return entries


## The cold rim traces the authored hair crown: min/mid/max bone columns of
## the crown rows, never floating above the silhouette.
static func _hood_tick_pixels(facing: String, action: String, frame: int) -> Array[Vector2i]:
	var masks := _cell_masks(facing, action, frame)
	if masks.is_empty():
		return []
	var bone: Dictionary = masks["bone"]
	if bone.is_empty():
		return []
	var top := 48
	for point: Vector2i in bone.keys():
		top = mini(top, point.y)
	var crown: Array[Vector2i] = []
	for point: Vector2i in bone.keys():
		if point.y <= top + 1:
			crown.append(point)
	crown.sort()
	if crown.size() < 3:
		return []
	var ticks: Array[Vector2i] = [crown[0], crown[crown.size() >> 1], crown[crown.size() - 1]]
	var pixels: Array[Vector2i] = []
	for tick: Vector2i in ticks:
		pixels.append(_to_local(Vector2i(tick.x, tick.y)))
	return pixels


## The shoulder plate lands on the authored shoulder run: the first content
## row (below the head) wide enough to be a shoulder, behind half.
static func _pauldron_entries(facing: String, action: String, frame: int, bob: int) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var masks := _cell_masks(facing, action, frame)
	if masks.is_empty():
		return entries
	var content: Dictionary = masks["content"]
	var shoulder := _torso_row(content)
	if shoulder.is_empty():
		return entries
	var y := int(shoulder["y"])
	var run_from := int(shoulder["from"])
	var run_to := int(shoulder["to"])
	var behind := _behind_axis(facing)
	var cols: Array[int] = []
	if behind.x > 0:
		for x in range(run_to - 3, run_to + 1):
			cols.append(x)
	elif behind.x < 0:
		for x in range(run_from, run_from + 4):
			cols.append(x)
	else:
		var mid := (run_from + run_to) >> 1
		for x in range(mid - 2, mid + 3):
			cols.append(x)
	var edge_cols: Array[int] = []
	if behind.x >= 0:
		edge_cols.append(cols[cols.size() - 2])
		edge_cols.append(cols[cols.size() - 1])
	else:
		edge_cols.append(cols[0])
		edge_cols.append(cols[1])
	for row in 2:
		for x in cols:
			var point := Vector2i(x, y + row)
			if not content.has(point):
				continue
			entries.append({"point": _bobbed(_to_local(point), bob, facing, action, frame), "color": Color(INK, 0.65), "front": true})
	for x in edge_cols:
		var point := Vector2i(x, y - 1)
		if not _near_content_cell(content, point, 1):
			continue
		entries.append({"point": _bobbed(_to_local(point), bob, facing, action, frame), "color": Color(COPPER, 0.8), "front": true})
	return entries


## Boot-top highlight on the striking boot for contact frames only.
static func _boot_highlight_pixels(facing: String, frame: int) -> Array[Vector2i]:
	var masks := _cell_masks(facing, "walk", frame)
	if masks.is_empty():
		return []
	var leather: Dictionary = masks["leather"]
	var behind := _behind_axis(facing)
	var candidates: Array[Vector2i] = []
	for point: Vector2i in leather.keys():
		if point.y >= 26:
			candidates.append(point)
	if candidates.is_empty():
		return []
	var left_is_pick := _striking_side_is_left(behind, frame == 2)
	var half: Array[Vector2i] = []
	var other: Array[Vector2i] = []
	for point: Vector2i in candidates:
		if (point.x < 24) == left_is_pick:
			half.append(point)
		else:
			other.append(point)
	half.sort()
	other.sort()
	var picked: Array[Vector2i] = half.slice(0, 2)
	for point: Vector2i in other:
		if picked.size() >= 2:
			break
		picked.append(point)
	var pixels: Array[Vector2i] = []
	for point: Vector2i in picked:
		pixels.append(_to_local(point))
	return pixels


## One dust speck beside the authored striking boot on contact frames.
static func _foot_dust_pixel(facing: String, frame: int) -> Vector2i:
	var masks := _cell_masks(facing, "walk", frame)
	if masks.is_empty():
		return Vector2i.ZERO
	var content: Dictionary = masks["content"]
	var bottom := -1
	for point: Vector2i in content.keys():
		bottom = maxi(bottom, point.y)
	if bottom < 0:
		return Vector2i.ZERO
	var behind := _behind_axis(facing)
	var left_is_pick := _striking_side_is_left(behind, frame == 2)
	var pick_x := -1
	var best := 1 if left_is_pick else -1
	for point: Vector2i in content.keys():
		if point.y != bottom:
			continue
		if (point.x < 24) != left_is_pick:
			continue
		var score := -point.x if left_is_pick else point.x
		if score > best:
			best = score
			pick_x = point.x
	if pick_x < 0:
		for point: Vector2i in content.keys():
			if point.y != bottom:
				continue
			if pick_x < 0 or absi(point.x - 24) > absi(pick_x - 24):
				pick_x = point.x
		if pick_x < 0:
			return Vector2i.ZERO
	var outward := 1 if pick_x >= 24 else -1
	var dust := Vector2i(pick_x + outward, bottom)
	if content.has(dust):
		dust = Vector2i(pick_x, bottom - 1)
	return _to_local(dust)


## The striking half is the front boot on frame 0 and the back boot on
## frame 2; vertical facings simply alternate left/right.
static func _striking_side_is_left(behind: Vector2i, pick_behind: bool) -> bool:
	if behind.x > 0:
		return not pick_behind
	if behind.x < 0:
		return pick_behind
	return not pick_behind


## ------------------------------------------------------------------ fixed gear

static func _gated_hem_tips(facing: String, action: String, frame: int, kick: int) -> Array[Vector2i]:
	var tips: Array[Vector2i] = []
	var masks := _cell_masks(facing, action, frame)
	if masks.is_empty():
		return tips
	var content: Dictionary = masks["content"]
	var behind := _behind_axis(facing)
	var base: Array[Vector2i] = []
	match facing:
		"east": base = [Vector2i(-14, -11), Vector2i(-13, -10)]
		"west": base = [Vector2i(14, -11), Vector2i(13, -10)]
		"north": base = [Vector2i(6, -9), Vector2i(-6, -9)]
		_: base = [Vector2i(7, -10), Vector2i(-7, -10)]
	if kick > 0:
		for point: Vector2i in base.duplicate():
			base.append(point + behind)
	for point: Vector2i in base:
		if _near_content_cell(content, _to_cell(point), 1):
			tips.append(point)
	return tips


static func _gated_strap_points(facing: String, action: String, frame: int) -> Array[Vector2i]:
	var points: Array[Vector2i] = []
	match facing:
		"east": points = [Vector2i(7, -31), Vector2i(-5, -13)]
		"west": points = [Vector2i(-7, -31), Vector2i(5, -13)]
		"north": points = [Vector2i(5, -31), Vector2i(-4, -14)]
		_: points = [Vector2i(-6, -31), Vector2i(5, -14)]
	var masks := _cell_masks(facing, action, frame)
	if masks.is_empty():
		return []
	var content: Dictionary = masks["content"]
	for point: Vector2i in points:
		if not _near_content_cell(content, _to_cell(point), 1):
			return []
	return points


static func _gated_quiver_strap_pixel(facing: String, action: String, frame: int) -> Vector2i:
	var point: Vector2i
	match facing:
		"east": point = Vector2i(-8, -20)
		"west": point = Vector2i(8, -20)
		"north": point = Vector2i(5, -21)
		_: point = Vector2i(-7, -20)
	if not _point_gated(facing, action, clampi(frame, 0, 3), point):
		return Vector2i.ZERO
	return point


static func _gated_grip_pixel(facing: String, action: String, frame: int) -> Vector2i:
	var rise := -1 if (frame == 1 or frame == 3) else 0
	var point: Vector2i
	match facing:
		"east": point = Vector2i(11, -22 + rise)
		"west": point = Vector2i(-11, -22 + rise)
		"north": point = Vector2i(0, -29 + rise)
		_: point = Vector2i(3, -20 + rise)
	if not _point_gated(facing, action, clampi(frame, 0, 3), point):
		return Vector2i.ZERO
	return point


static func _gated_buckle_pixel(facing: String, action: String, frame: int) -> Vector2i:
	var point: Vector2i
	match facing:
		"east": point = Vector2i(1, -22)
		"west": point = Vector2i(-1, -22)
		"north": point = Vector2i(0, -21)
		_: point = Vector2i(0, -23)
	if not _point_gated(facing, action, clampi(frame, 0, 3), point):
		return Vector2i.ZERO
	return point


static func _gated_release_pixels(facing: String, action: String, frame: int) -> Array[Vector2i]:
	var points: Array[Vector2i] = []
	match facing:
		"east": points = [Vector2i(13, -21), Vector2i(15, -20)]
		"west": points = [Vector2i(-13, -21), Vector2i(-15, -20)]
		"north": points = [Vector2i(0, -31), Vector2i(0, -33)]
		_: points = [Vector2i(-2, -20), Vector2i(-3, -18)]
	var kept: Array[Vector2i] = []
	for point: Vector2i in points:
		if _point_gated(facing, action, clampi(frame, 0, 3), point):
			kept.append(point)
	return kept


static func _trail_pixels(facing: String, count: int) -> Array[Vector2i]:
	var all_points: Array[Vector2i]
	match facing:
		"east":
			all_points = [
				Vector2i(-14, -16), Vector2i(-10, -15), Vector2i(-6, -15),
				Vector2i(-12, -19), Vector2i(-8, -18), Vector2i(-4, -18),
			]
		"west":
			all_points = [
				Vector2i(14, -16), Vector2i(10, -15), Vector2i(6, -15),
				Vector2i(12, -19), Vector2i(8, -18), Vector2i(4, -18),
			]
		_:
			all_points = [
				Vector2i(4, -1), Vector2i(-4, -1), Vector2i(4, -3),
				Vector2i(-4, -3), Vector2i(4, -5), Vector2i(-4, -5),
			]
	return all_points.slice(0, clampi(count, 0, all_points.size()))


## ------------------------------------------------------------------ evidence

static func _evidence_ready() -> bool:
	if not _evidence_tried:
		_load_evidence()
	return _evidence_image != null and not _evidence_atlas.is_empty()


static func _load_evidence() -> void:
	_evidence_tried = true
	for atlas_path: String in EVIDENCE_ATLAS_PATHS:
		var parsed := _read_json(atlas_path)
		if parsed.is_empty():
			continue
		var texture_path := ""
		var render_textures: Dictionary = parsed.get("render_textures", {})
		if render_textures.has("ranger"):
			texture_path = String((render_textures["ranger"] as Dictionary).get("path", ""))
		if texture_path.is_empty():
			var textures: Dictionary = parsed.get("textures", {})
			if textures.has("ranger"):
				texture_path = String((textures["ranger"] as Dictionary).get("path", ""))
		var image := _load_image(texture_path)
		if image == null:
			continue
		_evidence_atlas = parsed
		_evidence_image = image
		return


static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return {}
	if json.data is Dictionary:
		return json.data as Dictionary
	return {}


static func _load_image(path: String) -> Image:
	if path.is_empty():
		return null
	var image := Image.new()
	if ResourceLoader.exists(path, "Texture2D"):
		var texture := ResourceLoader.load(path, "Texture2D") as Texture2D
		if texture != null:
			image = texture.get_image()
	else:
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			return null
		if image.load_png_from_buffer(file.get_buffer(file.get_length())) != OK:
			return null
	if image == null or image.is_empty():
		return null
	if image.is_compressed():
		image.decompress()
	return image


static func _cell_masks(facing: String, action: String, frame: int) -> Dictionary:
	if not _evidence_ready():
		return {}
	var key := "%s.%s.%d" % [facing, action, clampi(frame, 0, 3)]
	if _mask_cache.has(key):
		return _mask_cache[key]
	var masks := _scan_sprite(facing, action, clampi(frame, 0, 3))
	_mask_cache[key] = masks
	return masks


static func _scan_sprite(facing: String, action: String, frame: int) -> Dictionary:
	var empty := {}
	var animations: Dictionary = _evidence_atlas.get("animations", {})
	var clip: Dictionary = animations.get("ranger.%s.%s" % [facing, action], {})
	var frames: Array = clip.get("frames", [])
	if frame < 0 or frame >= frames.size():
		return empty
	var sprites: Dictionary = _evidence_atlas.get("sprites", {})
	var sprite: Dictionary = sprites.get(String(frames[frame]), {})
	var rect_values: Array = sprite.get("rect", [])
	if rect_values.size() != 4:
		return empty
	var rx := int(rect_values[0])
	var ry := int(rect_values[1])
	var content := {}
	var bone := {}
	var red := {}
	var leather := {}
	for y in range(48):
		for x in range(48):
			var color := _evidence_image.get_pixel(rx + x, ry + y)
			if color.a < 0.55:
				continue
			var point := Vector2i(x, y)
			content[point] = true
			if _near(color, BONE, 0.10) or _near(color, BONE_SHADE, 0.08):
				bone[point] = true
			if _near(color, Color("bd4653"), 0.28):
				red[point] = true
			if _near(color, Color("895d44"), 0.14) or _near(color, COPPER, 0.10):
				leather[point] = true
	return {"content": content, "bone": bone, "red": red, "leather": leather}


static func _near(color: Color, reference: Color, tolerance: float) -> bool:
	return absf(color.r - reference.r) <= tolerance and absf(color.g - reference.g) <= tolerance and absf(color.b - reference.b) <= tolerance


## The plate sits on the widest authored torso row (y 15..24): the head and
## hair rows are narrower, and a resting corpse finds no row at all.
static func _torso_row(content: Dictionary) -> Dictionary:
	var best := {}
	var best_width := 12
	for y in range(15, 25):
		var xs: Array[int] = []
		for point: Vector2i in content.keys():
			if point.y == y:
				xs.append(point.x)
		if xs.size() <= best_width:
			continue
		best_width = xs.size()
		xs.sort()
		best = {"y": y, "from": xs[0], "to": xs[xs.size() - 1]}
	return best


static func _point_gated(facing: String, action: String, frame: int, point: Vector2i) -> bool:
	if point == Vector2i.ZERO:
		return false
	var masks := _cell_masks(facing, action, frame)
	if masks.is_empty():
		return false
	return _near_content_cell(masks["content"], _to_cell(point), 1)


static func _near_content_cell(content: Dictionary, center: Vector2i, radius: int) -> bool:
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if content.has(center + Vector2i(dx, dy)):
				return true
	return false


static func _to_local(point_cell: Vector2i) -> Vector2i:
	return point_cell + Vector2i(-24, -44)


static func _to_cell(point_local: Vector2i) -> Vector2i:
	return point_local + Vector2i(24, 44)


static func _behind_axis(facing: String) -> Vector2i:
	match facing:
		"east": return Vector2i(-1, 0)
		"west": return Vector2i(1, 0)
	return Vector2i(0, 1)
