extends SceneTree
## Contract checks for the pixel-locked ranger motion overlay, plus the west
## walk stride regression the overlay depends on: four authored frames must
## stay selected, cycle in order and loop while the hero moves west.

const RangerMotionOverlayScript = preload("res://src/presentation/ranger_motion_overlay.gd")
const RangerAnimationScript = preload("res://src/presentation/ranger_animation.gd")
const Assert := preload("res://tests/helpers/assert.gd")


func _initialize() -> void:
	var failures: Array[String] = []
	_test_palette_is_the_skin_palette(failures)
	_test_walk_is_stride_locked(failures)
	_test_idle_breath_is_bounded(failures)
	_test_trail_belongs_to_the_dodge_window(failures)
	_test_accent_geometry_stays_pixel_aligned_and_clear_of_the_feet(failures)
	_test_stride_changes_geometry(failures)
	_test_horizontal_facings_mirror(failures)
	_test_null_canvas_is_safe(failures)
	_test_west_walk_reader_regression(failures)
	if failures.is_empty():
		print("PASS  test_ranger_motion_overlay.gd: ranger motion overlay contract")
		quit(0)
		return
	printerr("%d check(s) failed:" % failures.size())
	for failure: String in failures:
		printerr("- %s" % failure)
	quit(1)


func _test_palette_is_the_skin_palette(failures: Array[String]) -> void:
	## The layer may only reuse colors the hero (or an approved motion accent)
	## already wears; a foreign palette is what read as a vector sticker.
	_expect(RangerMotionOverlayScript.INK == Color("111820"), "overlay: INK left the skin ink", failures)
	_expect(RangerMotionOverlayScript.SLATE == Color("2a3543"), "overlay: SLATE left the skin slate", failures)
	_expect(RangerMotionOverlayScript.SLATE_LIGHT == Color("91a4b4"), "overlay: SLATE_LIGHT left the skin light slate", failures)
	_expect(RangerMotionOverlayScript.BONE == Color("e9ddc3"), "overlay: BONE left the skin bone", failures)
	_expect(RangerMotionOverlayScript.COPPER == Color("ad734d"), "overlay: COPPER left the old copper", failures)
	_expect(RangerMotionOverlayScript.COPPER_LIGHT == Color("eead56"), "overlay: COPPER_LIGHT left the skin gold", failures)
	_expect(RangerMotionOverlayScript.COLD == Color("61a6a5"), "overlay: COLD left the approved motion teal", failures)


func _test_walk_is_stride_locked(failures: Array[String]) -> void:
	## Walk accents answer the authored frame, never the wall clock: the same
	## frame must produce the same signature at any render time.
	for frame in 4:
		var at_zero: Dictionary = RangerMotionOverlayScript.motion_signature("walk", "west", frame, 0.0)
		var later: Dictionary = RangerMotionOverlayScript.motion_signature("walk", "west", frame, 7.3)
		_expect(at_zero == later, "overlay: walk frame %d drifted with the wall clock" % frame, failures)
	for frame in 4:
		var signature: Dictionary = RangerMotionOverlayScript.motion_signature("walk", "west", frame, 0.0)
		var pass_frame := frame == 1 or frame == 3
		_expect(int(signature["kick"]) == (1 if pass_frame else 0), "overlay: walk frame %d hem kick is wrong" % frame, failures)
		_expect(float(signature["bob"]) == (-1.0 if pass_frame else 0.0), "overlay: walk frame %d bob is wrong" % frame, failures)
		_expect(is_finite(float(signature["sway"])) and absf(float(signature["sway"])) <= 2.0, "overlay: walk frame %d sway is unbounded" % frame, failures)


func _test_idle_breath_is_bounded(failures: Array[String]) -> void:
	var first: Dictionary = RangerMotionOverlayScript.motion_signature("idle", "south", 0, 0.0)
	var second: Dictionary = RangerMotionOverlayScript.motion_signature("idle", "south", 0, 0.4)
	for key: String in ["sway", "bob"]:
		_expect(is_finite(float(first[key])) and absf(float(first[key])) <= 0.51, "overlay: idle %s is unbounded" % key, failures)
	_expect(float(first["sway"]) != float(second["sway"]), "overlay: the idle breath froze", failures)
	_expect(String(RangerMotionOverlayScript.motion_signature("idle", "sideways", 0, 0.0)["facing"]) == "south", "overlay: an unknown facing did not fall back to south", failures)


func _test_trail_belongs_to_the_dodge_window(failures: Array[String]) -> void:
	var early: Dictionary = RangerMotionOverlayScript.motion_signature("dodge", "west", 0, 3.0)
	var late: Dictionary = RangerMotionOverlayScript.motion_signature("dodge", "west", 1, 3.0)
	_expect(float(early["trail"]) > float(late["trail"]), "overlay: the dodge trail did not fade inside the window", failures)
	_expect(float(RangerMotionOverlayScript.motion_signature("walk", "west", 0, 3.0)["trail"]) == 0.0, "overlay: a walk carried a dodge trail", failures)
	_expect(RangerMotionOverlayScript._trail_pixels("west", 6).size() == 6, "overlay: the full west wake lost its length", failures)
	_expect(RangerMotionOverlayScript._trail_pixels("west", 2).size() == 2, "overlay: the wake did not shorten", failures)
	for point: Vector2i in RangerMotionOverlayScript._trail_pixels("north", 6):
		_expect(point.y >= -5, "overlay: a vertical dodge wake crossed the legs", failures)


func _test_accent_geometry_stays_pixel_aligned_and_clear_of_the_feet(failures: Array[String]) -> void:
	for facing: String in ["north", "south", "east", "west"]:
		var pixel_groups: Array = [
			RangerMotionOverlayScript._hem_seat_pixels(facing),
			RangerMotionOverlayScript._hem_tip_pixels(facing, 0),
			RangerMotionOverlayScript._hem_tip_pixels(facing, 1),
			RangerMotionOverlayScript._quiver_pixels(facing),
			RangerMotionOverlayScript._quiver_strap_pixels(facing),
			RangerMotionOverlayScript._pauldron_edge_pixels(facing),
			RangerMotionOverlayScript._strap_points(facing),
			RangerMotionOverlayScript._buckle_pixels(facing),
			RangerMotionOverlayScript._hood_tick_pixels(facing),
			RangerMotionOverlayScript._trail_pixels(facing, 6),
			RangerMotionOverlayScript._release_pixels(facing),
			[RangerMotionOverlayScript._foot_dust_pixel(facing, 0), RangerMotionOverlayScript._foot_dust_pixel(facing, 2)],
			[RangerMotionOverlayScript._grip_pixel(facing, 0), RangerMotionOverlayScript._grip_pixel(facing, 1)],
		]
		for group: Array in pixel_groups:
			for raw_point: Variant in group:
				var point := raw_point as Vector2i
				_expect(absi(point.x) <= 24 and point.y <= -1 and point.y >= -38, "overlay: %s accent left the action cell: %s" % [facing, str(point)], failures)
		for rect: Rect2i in RangerMotionOverlayScript._pauldron_rects(facing):
			_expect(rect.position.x <= 24 and rect.end.x <= 24 and rect.position.y >= -38 and rect.end.y <= -1, "overlay: the %s pauldron left the action cell" % facing, failures)


func _test_stride_changes_geometry(failures: Array[String]) -> void:
	## Visible gait response: the hem kicks, the dust switches feet and the
	## grip glint rides the pass-frame rise.
	_expect(RangerMotionOverlayScript._hem_tip_pixels("west", 0) != RangerMotionOverlayScript._hem_tip_pixels("west", 1), "overlay: the west hem did not kick on the pass frame", failures)
	_expect(RangerMotionOverlayScript._foot_dust_pixel("west", 0) != RangerMotionOverlayScript._foot_dust_pixel("west", 2), "overlay: the west dust speck did not switch feet", failures)
	_expect(RangerMotionOverlayScript._grip_pixel("west", 0) != RangerMotionOverlayScript._grip_pixel("west", 1), "overlay: the west grip glint did not ride the stride", failures)
	var contact: Dictionary = RangerMotionOverlayScript.motion_signature("walk", "west", 0, 0.0)
	var pass_frame: Dictionary = RangerMotionOverlayScript.motion_signature("walk", "west", 1, 0.0)
	_expect(contact != pass_frame, "overlay: the walk signature ignored the stride frame", failures)


func _test_horizontal_facings_mirror(failures: Array[String]) -> void:
	_expect(RangerMotionOverlayScript._hem_tip_pixels("east", 1) == RangerMotionOverlayScript._hem_tip_pixels("west", 1).map(func(point: Vector2i) -> Vector2i: return Vector2i(-point.x, point.y)), "overlay: the east hem did not mirror west", failures)
	_expect(RangerMotionOverlayScript._quiver_pixels("east") == RangerMotionOverlayScript._quiver_pixels("west").map(func(point: Vector2i) -> Vector2i: return Vector2i(-point.x, point.y)), "overlay: the east quiver did not mirror west", failures)
	_expect(RangerMotionOverlayScript._hem_seat_pixels("east") == RangerMotionOverlayScript._hem_seat_pixels("west").map(func(point: Vector2i) -> Vector2i: return Vector2i(-point.x, point.y)), "overlay: the east hem seat did not mirror west", failures)
	_expect(RangerMotionOverlayScript._quiver_strap_pixels("east") == RangerMotionOverlayScript._quiver_strap_pixels("west").map(func(point: Vector2i) -> Vector2i: return Vector2i(-point.x, point.y)), "overlay: the east quiver strap did not mirror west", failures)
	_expect(RangerMotionOverlayScript._pauldron_edge_pixels("east") == RangerMotionOverlayScript._pauldron_edge_pixels("west").map(func(point: Vector2i) -> Vector2i: return Vector2i(-point.x, point.y)), "overlay: the east pauldron edge did not mirror west", failures)
	_expect(RangerMotionOverlayScript._strap_points("east") == RangerMotionOverlayScript._strap_points("west").map(func(point: Vector2i) -> Vector2i: return Vector2i(-point.x, point.y)), "overlay: the east strap did not mirror west", failures)
	_expect(RangerMotionOverlayScript._buckle_pixels("east") == RangerMotionOverlayScript._buckle_pixels("west").map(func(point: Vector2i) -> Vector2i: return Vector2i(-point.x, point.y)), "overlay: the east buckle did not mirror west", failures)
	_expect(RangerMotionOverlayScript._trail_pixels("east", 6) == RangerMotionOverlayScript._trail_pixels("west", 6).map(func(point: Vector2i) -> Vector2i: return Vector2i(-point.x, point.y)), "overlay: the east wake did not mirror west", failures)
	_expect(RangerMotionOverlayScript._release_pixels("east") == RangerMotionOverlayScript._release_pixels("west").map(func(point: Vector2i) -> Vector2i: return Vector2i(-point.x, point.y)), "overlay: the east release did not mirror west", failures)
	_expect(RangerMotionOverlayScript._grip_pixel("east", 0) == Vector2i(-RangerMotionOverlayScript._grip_pixel("west", 0).x, RangerMotionOverlayScript._grip_pixel("west", 0).y), "overlay: the east grip did not mirror west", failures)


func _test_null_canvas_is_safe(failures: Array[String]) -> void:
	RangerMotionOverlayScript.draw_back(null, Vector2.ZERO, "west", "walk", 1, 0.0)
	RangerMotionOverlayScript.draw_front(null, Vector2.ZERO, "west", "walk", 1, 0.0)
	_expect(true, "overlay: unreachable", failures)


func _test_west_walk_reader_regression(failures: Array[String]) -> void:
	## The overlay only looks alive if the reader keeps selecting the four
	## authored west walk frames, in order, looping, with stable anchors.
	var animation = RangerAnimationScript.new()
	_expect(animation.has_real_art(), "overlay: the published ranger atlas did not load: %s" % animation.pending_reason(), failures)
	if not animation.has_real_art():
		return
	var distinct_rects := {}
	for index in 4:
		var authored: Dictionary = animation.frame_for("ranger.west.walk", index)
		distinct_rects[(authored["rect"] as Rect2i)] = true
		_expect((authored["anchor"] as Vector2i) == RangerAnimationScript.DEFAULT_ANCHOR, "overlay: west walk frame %d moved the anchor" % index, failures)
	_expect(distinct_rects.size() == 4, "overlay: west walk published %d distinct frames instead of 4" % distinct_rects.size(), failures)
	var order: Array[int] = []
	for tick in 60:
		var frame: Dictionary = animation.resolve({"facing": "west", "moving": true, "phase_ticks": tick})
		_expect(bool(frame.get("fallback", true)) == false, "overlay: west walk fell back at tick %d: %s" % [tick, str(frame.get("reason", ""))], failures)
		_expect(String(frame.get("clip", "")) == "ranger.west.walk", "overlay: west walk left its clip at tick %d" % tick, failures)
		var index := int(frame.get("frame", -1))
		if order.is_empty() or order[order.size() - 1] != index:
			order.append(index)
		_expect((frame["anchor"] as Vector2i) == RangerAnimationScript.DEFAULT_ANCHOR, "overlay: west walk tick %d shifted the foot point" % tick, failures)
	var expected_cycle: Array[int] = [0, 1, 2, 3]
	for index in order.size():
		_expect(order[index] == expected_cycle[index % 4], "overlay: west walk cycled %s instead of 0-1-2-3" % str(order), failures)
	_expect(order.size() >= 8, "overlay: west walk only produced %d frame changes in two seconds" % order.size(), failures)
	## The loop is exact: 8 fps over 30 Hz ticks repeats every 15 ticks.
	for tick in 15:
		var first: Dictionary = animation.resolve({"facing": "west", "moving": true, "phase_ticks": tick})
		var wrapped: Dictionary = animation.resolve({"facing": "west", "moving": true, "phase_ticks": tick + 15})
		_expect(int(first["frame"]) == int(wrapped["frame"]), "overlay: west walk did not loop at tick %d" % tick, failures)
	## The presentation draw offset and the arrow socket stay authoritative.
	_expect(RangerAnimationScript.walk_draw_offset("west", "walk", 0) == Vector2i(0, 1), "overlay: west contact frame 0 lost its foot correction", failures)
	_expect(RangerAnimationScript.walk_draw_offset("west", "walk", 1) == Vector2i.ZERO, "overlay: west pass frame 1 grew a draw offset", failures)
	_expect(RangerAnimationScript.walk_draw_offset("west", "walk", 3) == Vector2i(0, 1), "overlay: west contact frame 3 lost its foot correction", failures)
	_expect(RangerAnimationScript.arrow_attachment_local("west", 2) == Vector2i(12, 24), "overlay: the west release socket moved", failures)


func _expect(condition: bool, message: String, failures: Array[String]) -> void: Assert.expect(condition, message, failures)
