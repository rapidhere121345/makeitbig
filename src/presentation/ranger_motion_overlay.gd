class_name RangerMotionOverlay
extends RefCounted
## A small, presentation-only layer for the ranger's silhouette.
##
## The action atlas remains the source of the character's authored poses. This
## pass adds the pieces that are hard to communicate with a short pixel clip:
## the uneven cloak edge, a strapped quiver, a shoulder guard and a few
## restrained motion accents. It is drawn around the atlas frame, never feeds
## back into gameplay, and only uses a render clock so 60/144 Hz windows do not
## freeze between 30 Hz authority ticks.

const INK := Color("0b1117")
const SLATE := Color("33434d")
const SLATE_LIGHT := Color("71808a")
const BONE := Color("e9ddc3")
const COPPER := Color("bb713d")
const COPPER_LIGHT := Color("e2ad6d")
const COLD := Color("61a6a5")


static func motion_signature(action: String, facing: String, frame: int, time: float) -> Dictionary:
	## Pure, bounded values make this layer easy to inspect without constructing a
	## scene. The facing is part of the signature so a held foot point can never
	## inherit a side-facing sway after a turn.
	var phase := maxf(0.0, time) * TAU * 1.35 + float(frame) * 0.43
	var rate := 1.0
	var amplitude := 0.8
	match action:
		"walk":
			rate = 1.8
			amplitude = 1.8
		"shoot":
			rate = 1.25
			amplitude = 1.1
		"dodge", "dash":
			rate = 2.8
			amplitude = 2.4
	var wave := sin(phase * rate)
	var secondary := cos(phase * rate * 0.63 + 0.7)
	return {
		"facing": facing if facing in ["north", "south", "east", "west"] else "south",
		"sway": wave * amplitude,
		"bob": secondary * (0.45 if action == "idle" else 0.75),
		"trail": clampf(absf(wave) * (1.0 if action in ["idle", "walk"] else 1.35), 0.0, 1.5),
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
	var sway := float(signature["sway"])
	var bob := float(signature["bob"])
	var trail := float(signature["trail"])
	var local_cloak := _cloak_points(facing, sway)
	var cloak := PackedVector2Array()
	for point: Vector2 in local_cloak:
		cloak.append(feet_world + point + Vector2(0.0, bob))
	canvas.draw_colored_polygon(cloak, Color(SLATE, 0.40))
	canvas.draw_polyline(cloak, Color(INK, 0.72), 2.2, false)

	var facing_axis := _facing_axis(facing)
	var side_axis := Vector2(-facing_axis.y, facing_axis.x)
	var quiver := feet_world + _quiver_offset(facing) + Vector2(0.0, bob)
	canvas.draw_line(quiver + Vector2(-2.0, -16.0), quiver + Vector2(3.0, 2.0), Color(INK, 0.75), 4.0, false)
	canvas.draw_line(quiver + Vector2(-2.0, -16.0), quiver + Vector2(3.0, 2.0), Color(COPPER, 0.72), 1.3, false)
	for index in 3:
		var arrow_x := float(index - 1) * 2.4
		canvas.draw_line(
			quiver + Vector2(arrow_x, -15.0),
			quiver + Vector2(arrow_x - side_axis.x * 2.0, -21.0),
			Color(BONE, 0.48),
			1.0,
			false
		)

	if action in ["dodge", "dash"]:
		var ribbon_origin := feet_world + Vector2(0.0, -17.0 + bob)
		var ribbon_direction := -facing_axis
		var length := 14.0 + trail * 11.0
		canvas.draw_line(ribbon_origin + side_axis * 5.0, ribbon_origin + ribbon_direction * length + side_axis * 5.0, Color(COLD, 0.32), 2.0, false)
		canvas.draw_line(ribbon_origin - side_axis * 4.0, ribbon_origin + ribbon_direction * (length - 4.0) - side_axis * 4.0, Color(COPPER_LIGHT, 0.34), 1.2, false)
	elif action == "walk":
		var hem := feet_world + Vector2(0.0, -7.0 + bob)
		canvas.draw_line(hem - side_axis * 8.0, hem + side_axis * 8.0 + -facing_axis * (2.0 + sway * 0.55), Color(COPPER, 0.48), 1.2, false)


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
	var sway := float(signature["sway"])
	var bob := float(signature["bob"])
	var axis := _facing_axis(facing)
	var side := Vector2(-axis.y, axis.x)

	## The uneven shoulder plate and diagonal harness give the small sprite a
	## readable identity at gameplay scale without repainting the source sheet.
	var shoulder := feet_world + _shoulder_offset(facing) + Vector2(0.0, bob)
	var pauldron := PackedVector2Array([
		shoulder + Vector2(-6.0, -3.0),
		shoulder + Vector2(1.0, -6.0),
		shoulder + Vector2(7.0, -2.0),
		shoulder + Vector2(4.0, 4.0),
		shoulder + Vector2(-4.0, 3.0),
	])
	canvas.draw_colored_polygon(pauldron, Color(INK, 0.58))
	canvas.draw_polyline(pauldron, Color(COPPER_LIGHT, 0.72), 1.1, false)

	var strap_top := feet_world + side * 6.0 + Vector2(0.0, -35.0 + bob)
	var strap_bottom := feet_world - side * 5.0 + Vector2(0.0, -10.0 + bob)
	canvas.draw_line(strap_top, strap_bottom, Color(INK, 0.72), 3.0, false)
	canvas.draw_line(strap_top, strap_bottom, Color(COPPER, 0.68), 1.0, false)
	canvas.draw_circle(feet_world + side * 5.0 + Vector2(0.0, -20.0 + bob), 1.8, COPPER_LIGHT)

	## A broken cold rim catches the hood and keeps the face readable against
	## both the snow and the dark arena floor.
	var hood := feet_world + Vector2(0.0, -35.0 + bob)
	canvas.draw_arc(hood, 7.0, PI * 0.12, PI * 0.88, 7, Color(COLD, 0.58), 1.0, false)
	canvas.draw_line(hood + side * 5.0, hood + side * 8.0 + axis * 2.0, Color(BONE, 0.42), 1.0, false)

	if action == "shoot":
		## The bow string is a short, high contrast accent during the pull and
		## release frames. The actual arrow socket remains owned by authority.
		var hand := feet_world + _hand_offset(facing, frame)
		var bow_tip := feet_world + axis * 10.0 + Vector2(0.0, -30.0 + bob)
		canvas.draw_line(hand - side * 6.0, hand + side * 6.0, Color(BONE, 0.52), 1.0, false)
		canvas.draw_line(hand, bow_tip, Color(COPPER_LIGHT, 0.54), 1.1, false)
		canvas.draw_circle(hand + axis * 2.0, 2.0, Color(COPPER_LIGHT, 0.50))
	elif action in ["dodge", "dash"]:
		var buckle := feet_world + Vector2(0.0, -15.0 + bob)
		canvas.draw_circle(buckle + side * sway * 0.25, 2.2, Color(COPPER_LIGHT, 0.65))
	else:
		var clasp := feet_world + axis * 2.0 + Vector2(0.0, -25.0 + bob)
		canvas.draw_circle(clasp, 1.7, Color(COPPER_LIGHT, 0.62))


static func _facing_axis(facing: String) -> Vector2:
	match facing:
		"north": return Vector2.UP
		"east": return Vector2.RIGHT
		"west": return Vector2.LEFT
	return Vector2.DOWN


static func _cloak_points(facing: String, sway: float) -> PackedVector2Array:
	match facing:
		"east":
			return PackedVector2Array([
				Vector2(-10.0, -34.0), Vector2(-20.0, -29.0 + sway), Vector2(-23.0, -12.0 + sway),
				Vector2(-12.0, -5.0), Vector2(-3.0, -10.0), Vector2(-4.0, -27.0),
			])
		"west":
			return PackedVector2Array([
				Vector2(10.0, -34.0), Vector2(20.0, -29.0 - sway), Vector2(23.0, -12.0 - sway),
				Vector2(12.0, -5.0), Vector2(3.0, -10.0), Vector2(4.0, -27.0),
			])
		"north":
			return PackedVector2Array([
				Vector2(-12.0, -35.0), Vector2(10.0, -35.0), Vector2(14.0, -20.0 + sway),
				Vector2(6.0, -5.0), Vector2(-9.0, -6.0), Vector2(-15.0, -21.0 - sway),
			])
	return PackedVector2Array([
		Vector2(-11.0, -34.0), Vector2(10.0, -34.0), Vector2(16.0, -19.0 + sway),
		Vector2(8.0, -5.0), Vector2(-7.0, -4.0), Vector2(-16.0, -19.0 - sway),
	])


static func _quiver_offset(facing: String) -> Vector2:
	match facing:
		"east": return Vector2(-10.0, -24.0)
		"west": return Vector2(10.0, -24.0)
		"north": return Vector2(9.0, -25.0)
	return Vector2(-9.0, -24.0)


static func _shoulder_offset(facing: String) -> Vector2:
	match facing:
		"east": return Vector2(8.0, -29.0)
		"west": return Vector2(-8.0, -29.0)
		"north": return Vector2(8.0, -30.0)
	return Vector2(-8.0, -29.0)


static func _hand_offset(facing: String, frame: int) -> Vector2:
	var lift := float(clampi(frame, 0, 3)) * 0.8
	match facing:
		"east": return Vector2(12.0, -21.0 - lift)
		"west": return Vector2(-12.0, -21.0 - lift)
		"north": return Vector2(0.0, -28.0 - lift)
	return Vector2(4.0, -18.0 - lift)
