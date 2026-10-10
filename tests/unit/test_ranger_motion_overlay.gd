extends SceneTree
## Contract checks for the evidence-based ranger motion overlay: every accent
## pixel must hug the authored skin pixels in every published pose, walk stays
## stride-locked, and the west walk reader regression keeps 0-1-2-3 looping.

const RangerMotionOverlayScript = preload("res://src/presentation/ranger_motion_overlay.gd")
const RangerAnimationScript = preload("res://src/presentation/ranger_animation.gd")

const FACINGS: Array[String] = ["north", "south", "east", "west"]
const ACTION_FRAMES := {"idle": 1, "walk": 4, "shoot": 4, "dodge": 2, "dash": 2, "hit": 1, "death": 3}


func _initialize() -> void:
	var failures: Array[String] = []
	_test_palette_is_the_skin_palette(failures)
	_test_walk_is_stride_locked(failures)
	_test_idle_breath_is_bounded(failures)
	_test_trail_belongs_to_the_dodge_window(failures)
	_test_evidence_engine_ready(failures)
	_test_plans_hug_authored_pixels_across_every_pose(failures)
	_test_action_gating(failures)
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


func _each_pose() -> Array:
	var poses: Array = []
	for facing: String in FACINGS:
		for action: String in ACTION_FRAMES.keys():
			for frame in int(ACTION_FRAMES[action]):
				poses.append([facing, action, frame])
	return poses


func _test_palette_is_the_skin_palette(failures: Array[String]) -> void:
	_expect(RangerMotionOverlayScript.INK == Color("111820"), "overlay: INK left the skin ink", failures)
	_expect(RangerMotionOverlayScript.SLATE == Color("2a3543"), "overlay: SLATE left the skin slate", failures)
	_expect(RangerMotionOverlayScript.SLATE_LIGHT == Color("91a4b4"), "overlay: SLATE_LIGHT left the skin light slate", failures)
	_expect(RangerMotionOverlayScript.BONE == Color("e9ddc3"), "overlay: BONE left the skin bone", failures)
	_expect(RangerMotionOverlayScript.BONE_SHADE == Color("d3cbb5"), "overlay: BONE_SHADE left the skin bone shade", failures)
	_expect(RangerMotionOverlayScript.COPPER == Color("ad734d"), "overlay: COPPER left the old copper", failures)
	_expect(RangerMotionOverlayScript.COPPER_LIGHT == Color("eead56"), "overlay: COPPER_LIGHT left the skin gold", failures)
	_expect(RangerMotionOverlayScript.COLD == Color("61a6a5"), "overlay: COLD left the approved motion teal", failures)


func _test_walk_is_stride_locked(failures: Array[String]) -> void:
	for frame in 4:
		var at_zero: Dictionary = RangerMotionOverlayScript.motion_signature("walk", "west", frame, 0.0)
		var later: Dictionary = RangerMotionOverlayScript.motion_signature("walk", "west", frame, 7.3)
		_expect(at_zero == later, "overlay: walk frame %d drifted with the wall clock" % frame, failures)
	for frame in 4:
		var signature: Dictionary = RangerMotionOverlayScript.motion_signature("walk", "west", frame, 0.0)
		var pass_frame := frame == 1 or frame == 3
		_expect(int(signature["kick"]) == (1 if pass_frame else 0), "overlay: walk frame %d hem kick is wrong" % frame, failures)
		_expect(float(signature["bob"]) == (-1.0 if pass_frame else 0.0), "overlay: walk frame %d bob is wrong" % frame, failures)


func _test_idle_breath_is_bounded(failures: Array[String]) -> void:
	var first: Dictionary = RangerMotionOverlayScript.motion_signature("idle", "south", 0, 0.0)
	var second: Dictionary = RangerMotionOverlayScript.motion_signature("idle", "south", 0, 0.4)
	for key: String in ["sway", "bob"]:
		_expect(is_finite(float(first[key])) and absf(float(first[key])) <= 0.61, "overlay: idle %s is unbounded" % key, failures)
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


func _test_evidence_engine_ready(failures: Array[String]) -> void:
	_expect(RangerMotionOverlayScript._evidence_ready(), "overlay: the published skin/atlas evidence did not load", failures)
	var masks: Dictionary = RangerMotionOverlayScript._cell_masks("west", "walk", 0)
	_expect(not masks.is_empty(), "overlay: west walk masks are empty", failures)
	if not masks.is_empty():
		_expect((masks["content"] as Dictionary).size() > 400, "overlay: west walk content mask lost pixels", failures)
		_expect((masks["bone"] as Dictionary).size() > 60, "overlay: west walk bone mask lost pixels", failures)


func _test_plans_hug_authored_pixels_across_every_pose(failures: Array[String]) -> void:
	for pose: Array in _each_pose():
		var facing := String(pose[0])
		var action := String(pose[1])
		var frame := int(pose[2])
		var masks: Dictionary = RangerMotionOverlayScript._cell_masks(facing, action, frame)
		if masks.is_empty():
			continue
		var content: Dictionary = masks["content"]
		var plan: Array[Dictionary] = RangerMotionOverlayScript._accent_plan(facing, action, frame, 0.35)
		for entry: Dictionary in plan:
			var point := entry["point"] as Vector2i
			var label := "%s %s.%d at %s" % [facing, action, frame, str(point)]
			_expect(absi(point.x) <= 24 and point.y <= 0 and point.y >= -44, "overlay: %s left the action cell" % label, failures)
			var color := entry["color"] as Color
			var is_wake := color.is_equal_approx(Color(RangerMotionOverlayScript.COLD, 0.5)) and not bool(entry.get("front", false))
			_expect(_hugs(content, point + Vector2i(24, 44), 2 if is_wake else 1), "overlay: %s floats off the authored pixels" % label, failures)


func _test_action_gating(failures: Array[String]) -> void:
	for facing: String in FACINGS:
		for frame in 4:
			var walk_plan: Array[Dictionary] = RangerMotionOverlayScript._accent_plan(facing, "walk", frame, 0.0)
			var contact := frame == 0 or frame == 2
			_expect(_count_color(walk_plan, Color(RangerMotionOverlayScript.SLATE_LIGHT, 0.45)) == (1 if contact else 0), "overlay: %s walk frame %d dust is not contact-gated" % [facing, frame], failures)
			_expect(_count_color(walk_plan, Color(RangerMotionOverlayScript.BONE_SHADE, 0.6)) == (2 if contact else 0), "overlay: %s walk frame %d boot highlight is not contact-gated" % [facing, frame], failures)
			_expect(_count_back_cold(walk_plan) == 0, "overlay: %s walk frame %d carried a trail" % [facing, frame], failures)
		for frame in 4:
			var shoot_plan: Array[Dictionary] = RangerMotionOverlayScript._accent_plan(facing, "shoot", frame, 0.0)
			var release_count := _count_color(shoot_plan, Color(RangerMotionOverlayScript.BONE, 0.6))
			_expect(release_count > 0 if frame == 2 else release_count == 0, "overlay: %s shoot frame %d release gating broke" % [facing, frame], failures)
		var dodge_plan: Array[Dictionary] = RangerMotionOverlayScript._accent_plan(facing, "dodge", 0, 0.0)
		_expect(_count_back_cold(dodge_plan) > 0, "overlay: %s dodge lost its trail" % facing, failures)
		var death_plan: Array[Dictionary] = RangerMotionOverlayScript._accent_plan(facing, "death", 0, 0.0)
		_expect(_count_color(death_plan, Color(RangerMotionOverlayScript.BONE_SHADE, 0.8)) == 0, "overlay: %s corpse kept walk folds" % facing, failures)


func _test_stride_changes_geometry(failures: Array[String]) -> void:
	var contact: Dictionary = RangerMotionOverlayScript.motion_signature("walk", "west", 0, 0.0)
	var pass_frame: Dictionary = RangerMotionOverlayScript.motion_signature("walk", "west", 1, 0.0)
	_expect(contact != pass_frame, "overlay: the walk signature ignored the stride frame", failures)
	_expect(RangerMotionOverlayScript._gated_hem_tips("west", "walk", 1, 1).size() > RangerMotionOverlayScript._gated_hem_tips("west", "walk", 0, 0).size(), "overlay: the west hem did not kick on the pass frame", failures)
	_expect(RangerMotionOverlayScript._gated_grip_pixel("west", "walk", 0) != RangerMotionOverlayScript._gated_grip_pixel("west", "walk", 1), "overlay: the west grip glint did not ride the stride", failures)
	_expect(RangerMotionOverlayScript._foot_dust_pixel("west", 0) != RangerMotionOverlayScript._foot_dust_pixel("west", 2), "overlay: the west dust speck did not switch feet", failures)
	_expect(RangerMotionOverlayScript._boot_highlight_pixels("west", 0) != RangerMotionOverlayScript._boot_highlight_pixels("west", 2), "overlay: the west boot highlight did not switch boots", failures)


func _test_horizontal_facings_mirror(failures: Array[String]) -> void:
	var west_strap: Array[Vector2i] = RangerMotionOverlayScript._gated_strap_points("west", "walk", 0)
	var east_strap: Array[Vector2i] = RangerMotionOverlayScript._gated_strap_points("east", "walk", 0)
	_expect(west_strap.size() == 2 and east_strap.size() == 2, "overlay: walk straps were gated away on a side facing", failures)
	if west_strap.size() == 2 and east_strap.size() == 2:
		_expect(east_strap[0] == Vector2i(-west_strap[0].x, west_strap[0].y) and east_strap[1] == Vector2i(-west_strap[1].x, west_strap[1].y), "overlay: the east strap did not mirror west", failures)
	_expect(RangerMotionOverlayScript._gated_buckle_pixel("east", "walk", 0) == Vector2i(-RangerMotionOverlayScript._gated_buckle_pixel("west", "walk", 0).x, -0 + RangerMotionOverlayScript._gated_buckle_pixel("west", "walk", 0).y), "overlay: the east buckle did not mirror west", failures)
	_expect(RangerMotionOverlayScript._gated_grip_pixel("east", "walk", 0) == Vector2i(-RangerMotionOverlayScript._gated_grip_pixel("west", "walk", 0).x, RangerMotionOverlayScript._gated_grip_pixel("west", "walk", 0).y), "overlay: the east grip did not mirror west", failures)
	var west_trail: Array[Vector2i] = RangerMotionOverlayScript._trail_pixels("west", 6)
	var east_trail: Array[Vector2i] = RangerMotionOverlayScript._trail_pixels("east", 6)
	for index in west_trail.size():
		_expect(east_trail[index] == Vector2i(-west_trail[index].x, west_trail[index].y), "overlay: the east wake did not mirror west", failures)


func _test_null_canvas_is_safe(failures: Array[String]) -> void:
	RangerMotionOverlayScript.draw_back(null, Vector2.ZERO, "west", "walk", 1, 0.0)
	RangerMotionOverlayScript.draw_front(null, Vector2.ZERO, "west", "walk", 1, 0.0)
	_expect(true, "overlay: unreachable", failures)


func _test_west_walk_reader_regression(failures: Array[String]) -> void:
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
	for tick in 15:
		var first: Dictionary = animation.resolve({"facing": "west", "moving": true, "phase_ticks": tick})
		var wrapped: Dictionary = animation.resolve({"facing": "west", "moving": true, "phase_ticks": tick + 15})
		_expect(int(first["frame"]) == int(wrapped["frame"]), "overlay: west walk did not loop at tick %d" % tick, failures)
	_expect(RangerAnimationScript.walk_draw_offset("west", "walk", 0) == Vector2i(0, 1), "overlay: west contact frame 0 lost its foot correction", failures)
	_expect(RangerAnimationScript.walk_draw_offset("west", "walk", 1) == Vector2i.ZERO, "overlay: west pass frame 1 grew a draw offset", failures)
	_expect(RangerAnimationScript.walk_draw_offset("west", "walk", 3) == Vector2i(0, 1), "overlay: west contact frame 3 lost its foot correction", failures)
	_expect(RangerAnimationScript.arrow_attachment_local("west", 2) == Vector2i(12, 24), "overlay: the west release socket moved", failures)


func _hugs(content: Dictionary, cell_point: Vector2i, radius := 1) -> bool:
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if content.has(cell_point + Vector2i(dx, dy)):
				return true
	return false


func _count_color(plan: Array[Dictionary], target: Color) -> int:
	var count := 0
	for entry: Dictionary in plan:
		var color := entry["color"] as Color
		if color.is_equal_approx(target):
			count += 1
	return count


func _count_back_cold(plan: Array[Dictionary]) -> int:
	var count := 0
	for entry: Dictionary in plan:
		if bool(entry.get("front", false)):
			continue
		var color := entry["color"] as Color
		if color.is_equal_approx(Color(RangerMotionOverlayScript.COLD, 0.5)):
			count += 1
	return count


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
