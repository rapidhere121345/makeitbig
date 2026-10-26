class_name RangerMotionOverlay
extends RefCounted
## Presentation-only motion layer for the ranger (2026-10 stride rework).
##
## The authored action atlas stays the sole source of the pose. This layer no
## longer paints a smooth vector figure over the sprite: every accent is a
## hard-edged, integer-aligned 1 px step drawn in colors the hero already
## wears, and every walk accent is locked to the authored stride frame instead
## of the wall clock, so cloak and gear answer the legs exactly when they pass.
## The layer draws around feet_world, never writes gameplay state, never moves
## the (24,44) foot anchor and never touches the authoritative arrow socket.

const SharedPalette := preload("res://src/presentation/palette.gd")

## Palette lifted from the published ranger skin pixels (ranger_actions_v01 /
## combat_style_r13 v03): cold slate cloth, bone cloth and hair, old copper
## leather and gear, plus the approved cold teal reserved for motion.
const INK := SharedPalette.SLATE_INK
const SLATE := Color("2a3543")
const SLATE_LIGHT := Color("91a4b4")
const BONE := SharedPalette.BONE
const BONE_SHADE := Color("d3cbb5")
const COPPER := Color("ad734d")
const COPPER_LIGHT := Color("eead56")
const COLD := SharedPalette.COLD_TEAL


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
			bob = 0.4 * sin(maxf(0.0, time) * 1.6 + 0.8)
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
	var signature := motion_signature(action, facing, frame, time)
	var facing_name := String(signature["facing"])
	# actors_v02 already contains the complete cloak, quiver and armor.
	# Only transient motion accents belong outside the authored sprite.
	if action in ["dodge", "dash"]:
		var count := clampi(int(round(float(signature["trail"]) * 4.0)), 0, 6)
		_draw_pixels(canvas, feet_world, _trail_pixels(facing_name, count), COLD, 0.5)


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
	var f := clampi(frame, 0, 3)
	if action == "walk" and (f == 0 or f == 2):
		_draw_pixels(canvas, feet_world, [_foot_dust_pixel(facing_name, f)], SLATE_LIGHT, 0.45)
	elif action == "shoot" and f == 2:
		_draw_pixels(canvas, feet_world, _release_pixels(facing_name), BONE, 0.8)


static func _draw_pixels(
	canvas: CanvasItem,
	feet_world: Vector2,
	points: Array[Vector2i],
	color: Color,
	alpha: float,
	bob := 0
) -> void:
	for point: Vector2i in points:
		canvas.draw_rect(
			Rect2(Vector2(feet_world) + Vector2(point) + Vector2(0.0, float(bob)), Vector2.ONE),
			Color(color, alpha),
			true
		)


static func _behind_axis(facing: String) -> Vector2i:
	match facing:
		"east": return Vector2i(-1, 0)
		"west": return Vector2i(1, 0)
	## Vertical facings trail toward the camera foot of the sprite.
	return Vector2i(0, 1)


static func _mirror(points: Array[Vector2i]) -> Array[Vector2i]:
	var mirrored: Array[Vector2i] = []
	for point: Vector2i in points:
		mirrored.append(Vector2i(-point.x, point.y))
	return mirrored


## One ink seat under the painted bone hem keeps the cloth grounded; the tip
## pixels sit at the hem's painted lower edge (cell rows ~30-34) and gain one
## further step behind on kick frames, so the cloak visibly answers the stride.
static func _hem_seat_pixels(facing: String) -> Array[Vector2i]:
	match facing:
		"east": return [Vector2i(-13, -9)]
		"west": return [Vector2i(13, -9)]
		"north": return [Vector2i(5, -8), Vector2i(-5, -8)]
	return [Vector2i(6, -9), Vector2i(-6, -9)]


static func _hem_tip_pixels(facing: String, kick: int) -> Array[Vector2i]:
	var base: Array[Vector2i]
	match facing:
		"east": base = [Vector2i(-14, -11), Vector2i(-13, -10)]
		"west": base = [Vector2i(14, -11), Vector2i(13, -10)]
		"north": base = [Vector2i(6, -9), Vector2i(-6, -9)]
		_: base = [Vector2i(7, -10), Vector2i(-7, -10)]
	if kick > 0:
		var behind := _behind_axis(facing)
		## Iterate a snapshot: appending to the array being iterated would
		## extend the loop forever.
		for point: Vector2i in base.duplicate():
			base.append(point + behind)
	return base


## Quiver fletching as three hard pixels over the back shoulder, with the old
## copper strap dot holding them down.
static func _quiver_pixels(facing: String) -> Array[Vector2i]:
	match facing:
		"east": return [Vector2i(-9, -23), Vector2i(-11, -24), Vector2i(-13, -23)]
		"west": return [Vector2i(9, -23), Vector2i(11, -24), Vector2i(13, -23)]
		"north": return [Vector2i(6, -24), Vector2i(8, -25), Vector2i(10, -24)]
	return [Vector2i(-8, -23), Vector2i(-6, -24), Vector2i(-4, -23)]


static func _quiver_strap_pixels(facing: String) -> Array[Vector2i]:
	match facing:
		"east": return [Vector2i(-8, -20)]
		"west": return [Vector2i(8, -20)]
		"north": return [Vector2i(5, -21)]
	return [Vector2i(-7, -20)]


## Small stepped shoulder plate on the back shoulder: two ink rows and a
## copper ridge, sized so it reads as gear, not as armor drawn over the pose.
static func _pauldron_rects(facing: String) -> Array[Rect2i]:
	match facing:
		"east": return [Rect2i(-10, -31, 5, 2), Rect2i(-10, -29, 3, 2)]
		"west": return [Rect2i(5, -31, 5, 2), Rect2i(7, -29, 3, 2)]
		"north": return [Rect2i(1, -32, 7, 2), Rect2i(3, -30, 3, 2)]
	return [Rect2i(-8, -32, 7, 2), Rect2i(-5, -30, 3, 2)]


static func _pauldron_edge_pixels(facing: String) -> Array[Vector2i]:
	match facing:
		"east": return [Vector2i(-6, -32), Vector2i(-7, -32), Vector2i(-8, -32)]
		"west": return [Vector2i(6, -32), Vector2i(7, -32), Vector2i(8, -32)]
		"north": return [Vector2i(2, -33), Vector2i(3, -33), Vector2i(4, -33)]
	return [Vector2i(-6, -33), Vector2i(-5, -33), Vector2i(-4, -33)]


static func _strap_points(facing: String) -> Array[Vector2i]:
	match facing:
		"east": return [Vector2i(7, -31), Vector2i(-5, -13)]
		"west": return [Vector2i(-7, -31), Vector2i(5, -13)]
		"north": return [Vector2i(5, -31), Vector2i(-4, -14)]
	return [Vector2i(-6, -31), Vector2i(5, -14)]


static func _buckle_pixels(facing: String) -> Array[Vector2i]:
	match facing:
		"east": return [Vector2i(1, -22)]
		"west": return [Vector2i(-1, -22)]
		"north": return [Vector2i(0, -21)]
	return [Vector2i(0, -23)]


## The approved cold teal keeps its reserved motion role: three hard ticks
## along the hood edge, replacing the old smooth arc.
static func _hood_tick_pixels(facing: String) -> Array[Vector2i]:
	match facing:
		"north": return [Vector2i(-3, -35), Vector2i(0, -36), Vector2i(3, -35)]
		"south": return [Vector2i(-3, -36), Vector2i(0, -36), Vector2i(3, -36)]
	return [Vector2i(-4, -35), Vector2i(0, -36), Vector2i(4, -35)]


## Stepped dodge/dash wake in the projectile wake family. Horizontal facings
## trail two 1 px streaks behind the back; vertical facings leave a ground
## speckle beside the feet so nothing is ever painted across the legs.
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


## A dust speck at the striking foot on contact frames only: frame 0 strikes
## with the front foot, frame 2 with the back foot.
static func _foot_dust_pixel(facing: String, frame: int) -> Vector2i:
	match facing:
		"east": return Vector2i(6, -2) if frame == 0 else Vector2i(-6, -2)
		"west": return Vector2i(-6, -2) if frame == 0 else Vector2i(6, -2)
	return Vector2i(-5, -2) if frame == 0 else Vector2i(5, -2)


## One copper glint on the bow grip; it rides the pass-frame body rise, so the
## weapon visibly answers the stride without moving the authored pose.
static func _grip_pixel(facing: String, frame: int) -> Vector2i:
	var rise := -1 if (frame == 1 or frame == 3) else 0
	match facing:
		"east": return Vector2i(11, -22 + rise)
		"west": return Vector2i(-11, -22 + rise)
		"north": return Vector2i(0, -29 + rise)
	return Vector2i(3, -20 + rise)


## Two bone pixels snapping off the string on the release frame.
static func _release_pixels(facing: String) -> Array[Vector2i]:
	match facing:
		"east": return [Vector2i(13, -21), Vector2i(15, -20)]
		"west": return [Vector2i(-13, -21), Vector2i(-15, -20)]
		"north": return [Vector2i(0, -31), Vector2i(0, -33)]
	return [Vector2i(-2, -20), Vector2i(-3, -18)]
