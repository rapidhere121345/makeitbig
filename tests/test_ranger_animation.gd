extends SceneTree
## Contract checks for the shared ranger action reader/controller.
##
## The suite is written to pass in the current state (the action atlas is still
## being produced) without ever letting a silent fallback pass: the delivered
## path is only accepted as READY when the whole four-facing x seven-action
## matrix validates, and every other outcome has to be reported explicitly as
## pending or invalid with a named reason.

const RangerAnimationScript = preload("res://src/presentation/ranger_animation.gd")
const BaseHubScript = preload("res://src/presentation/base_hub_screen.gd")
const ArenaWorldViewScript = preload("res://src/presentation/arena_world_view.gd")
const Assert := preload("res://tests/helpers/assert.gd")
## A published sheet used as fixture pixels. No art or placeholder atlas is
## created by this test.
const FIXTURE_SHEET := "res://art/production/p1/calibration_v01/enemies.png"
const FIXTURE_SHEET_SIZE := Vector2i(192, 144)


func _initialize() -> void:
	var failures: Array[String] = []
	_test_contract_constants(failures)
	_test_production_state(failures)
	_test_state_mapping(failures)
	_test_event_latching(failures)
	_test_frame_math(failures)
	_test_arrow_attachment_anchors(failures)
	_test_west_walk_foot_stability(failures)
	_test_delivered_manifest(failures)
	_test_integration_report(failures)
	_test_shoot_release_mapping(failures)
	_test_broken_deliveries(failures)
	_test_view_integration(failures)
	if failures.is_empty():
		print("PASS  test_ranger_animation.gd: ranger action atlas contract")
		quit(0)
		return
	printerr("%d check(s) failed:" % failures.size())
	for failure: String in failures:
		printerr("- %s" % failure)
	quit(1)


func _test_contract_constants(failures: Array[String]) -> void:
	## The 48x48 cell with a (24,44) anchor holds the approved 38px body at the
	## same height and ground contact as the old 32x48 idle cell.
	_expect(RangerAnimationScript.CELL == Vector2i(48, 48), "animation: the action cell is no longer 48x48", failures)
	_expect(RangerAnimationScript.DEFAULT_ANCHOR == Vector2i(24, 44), "animation: the action anchor is no longer (24,44)", failures)
	_expect(RangerAnimationScript.DEFAULT_ANCHOR.y * 2 == 88, "animation: the 2x foot row moved away from 88px below the head", failures)
	_expect(RangerAnimationScript.BODY_HEIGHT == 38, "animation: the preserved hero body height changed", failures)
	_expect(RangerAnimationScript.SIM_TICKS_PER_SECOND == 30, "animation: the tick base moved away from the 30Hz sim", failures)
	_expect(RangerAnimationScript.FACINGS == ["south", "north", "east", "west"], "animation: the four facings changed", failures)
	_expect(RangerAnimationScript.ACTIONS == ["idle", "walk", "shoot", "dodge", "dash", "hit", "death"], "animation: the action set changed", failures)
	for action: String in RangerAnimationScript.ACTIONS:
		_expect(RangerAnimationScript.ACTION_PRIORITY.has(action), "animation: %s has no priority slot" % action, failures)
	_expect(String(RangerAnimationScript.ATLAS_PATH).begins_with("res://art/production/p1/ranger_actions_v01/"), "animation: the atlas moved away from the agreed package", failures)
	_expect(String(RangerAnimationScript.TEXTURE_PATH) == "res://art/production/p1/ranger_actions_v01/ranger.png", "animation: the sheet moved away from the agreed path", failures)
	_expect(RangerAnimationScript.fallback_sprite_id("west") == "ranger.west.idle", "animation: the pending fallback is not the approved static idle cell", failures)


func _test_production_state(failures: Array[String]) -> void:
	## The published atlas is part of the delivery now, so the production path is
	## mandatory: a pending or invalid production reader fails this check instead of
	## passing quietly. The missing-atlas case is exercised only by the negative
	## fixture that points at a path that is known not to exist.
	var animation = RangerAnimationScript.new()
	_expect(animation.has_real_art(), "animation: the published ranger action atlas did not load: %s" % animation.pending_reason(), failures)
	_expect(animation.asset_state() == RangerAnimationScript.STATE_READY, "animation: the published atlas reports %s: %s" % [animation.asset_state(), animation.pending_reason()], failures)
	_expect(animation.pending_reason().is_empty(), "animation: the healthy delivery reported problems: %s" % animation.pending_reason(), failures)
	_expect(animation.texture_path() == RangerAnimationScript.TEXTURE_PATH, "animation: the delivered sheet is not the agreed ranger.png: %s" % animation.texture_path(), failures)
	_expect(animation.sprite_ids().size() == 68, "animation: the published sheet holds %d sprites instead of 68" % animation.sprite_ids().size(), failures)
	_expect(animation.clip_ids().size() == 28, "animation: the published atlas holds %d animations instead of 28" % animation.clip_ids().size(), failures)
	_expect(animation.contract_notes().is_empty(), "animation: the delivered timing disagrees with the hand-off: %s" % str(animation.contract_notes()), failures)
	for clip: String in animation.clip_ids():
		_expect(animation.frame_count(clip) > 0, "animation: %s published no frames" % clip, failures)
	if not animation.has_real_art():
		return
	## Every action of the published matrix resolves to a real frame whose rect and
	## anchor come from the manifest, and the idle alias keeps its own cell.
	var samples := {
		"idle": {"facing": "south"},
		"walk": {"facing": "south", "moving": true, "phase_ticks": 0},
		"shoot": {"facing": "east", "shoot_ticks": 0},
		"dodge": {"facing": "west", "dodge_ticks": 0},
		"dash": {"facing": "north", "dash_ticks": 0},
		"hit": {"facing": "south", "hit_ticks": 0},
		"death": {"facing": "south", "dead": true, "death_ticks": 0},
	}
	for action: String in samples.keys():
		var frame: Dictionary = animation.resolve(samples[action] as Dictionary)
		_expect(frame.get("fallback", true) == false, "animation: %s resolved to a fallback: %s" % [action, str(frame.get("reason", ""))], failures)
		_expect(String(frame["action"]) == action, "animation: %s resolved as %s" % [action, String(frame["action"])], failures)
		_expect((frame["rect"] as Rect2i).size == RangerAnimationScript.CELL, "animation: %s read a %s frame" % [action, str(frame["rect"])], failures)
		_expect((frame["anchor"] as Vector2i) == RangerAnimationScript.DEFAULT_ANCHOR, "animation: %s read anchor %s" % [action, str(frame["anchor"])], failures)
		_expect(frame["texture"] != null, "animation: %s resolved without a texture" % action, failures)


func _test_state_mapping(failures: Array[String]) -> void:
	## The priority table every view shares: death > hit > dodge > dash > shoot >
	## walk > idle, with the agreed clip lengths standing in before delivery.
	var animation = RangerAnimationScript.new(false)
	_expect(String(animation.resolve({"dead": true, "hit_ticks": 0, "dodge_ticks": 0, "dash_ticks": 0, "shoot_ticks": 0, "moving": true}).get("action", "")) == "death", "animation: death did not outrank the live reactions", failures)
	_expect(String(animation.resolve({"facing": Vector2.LEFT, "dead": true}).get("facing", "")) == "west", "animation: the death frame ignored the facing", failures)
	_expect(String(animation.resolve({"hit_ticks": 0, "dodge_ticks": 0, "dash_ticks": 0, "shoot_ticks": 0, "moving": true}).get("action", "")) == "dodge", "animation: hit reaction replaced a live dodge", failures)
	_expect(String(animation.resolve({"hit_ticks": -1, "dodge_ticks": 0, "dash_ticks": 0, "shoot_ticks": 0, "moving": true}).get("action", "")) == "dodge", "animation: a live dodge did not outrank dash, shoot and walk", failures)
	_expect(String(animation.resolve({"hit_ticks": -1, "dodge_ticks": -1, "dash_ticks": 0, "shoot_ticks": 0, "moving": true}).get("action", "")) == "dash", "animation: a live dash did not outrank shoot and walk", failures)
	_expect(String(animation.resolve({"hit_ticks": -1, "dodge_ticks": -1, "dash_ticks": -1, "shoot_ticks": 0, "moving": true}).get("action", "")) == "shoot", "animation: a live shot did not outrank walk", failures)
	_expect(String(animation.resolve({"moving": true}).get("action", "")) == "walk", "animation: movement did not select the walk clip", failures)
	_expect(String(animation.resolve({}).get("action", "")) == "idle", "animation: a standing ranger did not fall back to idle", failures)
	## A counter that outlives its published clip must fall through instead of
	## holding a stale action.
	_expect(String(animation.resolve({"shoot_ticks": 9}).get("action", "")) == "shoot", "animation: the shoot clip ended before its published length", failures)
	_expect(String(animation.resolve({"shoot_ticks": 10}).get("action", "")) == "idle", "animation: an expired shoot counter stayed selected", failures)
	_expect(String(animation.resolve({"hit_ticks": 3}).get("action", "")) == "hit", "animation: the hit clip ended before its published length", failures)
	_expect(String(animation.resolve({"hit_ticks": 4}).get("action", "")) == "idle", "animation: an expired hit counter stayed selected", failures)
	## Facing buckets, shared with the views.
	_expect(RangerAnimationScript.facing_key(Vector2.RIGHT) == "east", "animation: +x did not read as the east cell", failures)
	_expect(RangerAnimationScript.facing_key(Vector2.LEFT) == "west", "animation: -x did not read as the west cell", failures)
	_expect(RangerAnimationScript.facing_key(Vector2.UP) == "north", "animation: -y did not read as the north cell", failures)
	_expect(RangerAnimationScript.facing_key(Vector2.DOWN) == "south", "animation: +y did not read as the south cell", failures)
	_expect(RangerAnimationScript.facing_key(Vector2.ZERO) == "south", "animation: a standing ranger does not face the camera", failures)
	_expect(RangerAnimationScript.facing_key(Vector2(-0.2, -3.0)) == "north", "animation: a mostly-upward heading read as a side cell", failures)
	_expect(RangerAnimationScript.facing_key("north") == "north", "animation: a published facing name was not accepted", failures)
	_expect(RangerAnimationScript.facing_key("diagonal") == "south", "animation: an unknown facing name did not fall back to south", failures)


func _test_event_latching(failures: Array[String]) -> void:
	## One (source, cast) pair fires once: redrawing cannot restart the clip, and
	## a repeated id must never re-arm it.
	var animation = RangerAnimationScript.new(false)
	_expect(animation.latched_ticks("ranger/shoot", 10) == -1, "animation: an event was live before it fired", failures)
	_expect(animation.latch_event("ranger/shoot", "ranger:cast:3", 40), "animation: the first shot of a cast was not latched", failures)
	_expect(not animation.latch_event("ranger/shoot", "ranger:cast:3", 41), "animation: redrawing re-armed the same cast", failures)
	_expect(animation.latched_ticks("ranger/shoot", 40) == 0, "animation: the shot started late", failures)
	_expect(animation.latched_ticks("ranger/shoot", 45) == 5, "animation: the shot age is wrong: %d" % animation.latched_ticks("ranger/shoot", 45), failures)
	_expect(animation.latched_event_id("ranger/shoot") == "ranger:cast:3", "animation: the latched cast id changed", failures)
	_expect(animation.latch_event("ranger/shoot", "ranger:cast:4", 60), "animation: a later cast was ignored", failures)
	_expect(animation.latched_ticks("ranger/shoot", 61) == 1, "animation: the later cast did not restart the clock", failures)
	_expect(animation.latched_ticks("ranger/shoot", 30) == 0, "animation: a clock that ran backwards produced a negative age", failures)
	_expect(animation.latched_ticks("ranger/hit", 61) == -1, "animation: an unrelated event kind leaked its age", failures)
	_expect(not animation.latch_event("ranger/hit", "", 61), "animation: an empty event id was latched", failures)
	_expect(animation.latch_event("ranger/hit", "ranger:damage:7:melee_pursuer", 61), "animation: a damage event was not latched", failures)
	_expect(animation.latched_ticks("ranger/hit", 64) == 3, "animation: the hit age is wrong", failures)
	var state := {"hit_ticks": animation.latched_ticks("ranger/hit", 64)}
	_expect(String(animation.resolve(state).get("action", "")) == "hit", "animation: a latched hit did not drive the hit clip", failures)
	animation.clear_events()
	_expect(animation.latched_ticks("ranger/hit", 64) == -1, "animation: clearing events kept an age", failures)


func _test_frame_math(failures: Array[String]) -> void:
	_expect(RangerAnimationScript.frame_index_for(4, 8, 0.0, true) == 0, "animation: a looping clip did not start at frame 0", failures)
	_expect(RangerAnimationScript.frame_index_for(4, 8, 0.5, true) == 0, "animation: a 4-frame 8fps loop did not wrap after 0.5s", failures)
	_expect(RangerAnimationScript.frame_index_for(4, 8, 0.375, true) == 3, "animation: the third 8fps step did not land on frame 3", failures)
	_expect(RangerAnimationScript.frame_index_for(4, 12, 10.0, false) == 3, "animation: a one-shot clip did not hold its last frame", failures)
	_expect(RangerAnimationScript.frame_index_for(3, 6, 0.5, false) == 2, "animation: the death hold is not its published last frame", failures)
	_expect(RangerAnimationScript.frame_index_for(1, 8, 9.0, true) == 0, "animation: a single-frame clip moved", failures)
	_expect(RangerAnimationScript.frame_index_for(0, 8, 1.0, false) == 0, "animation: an empty clip produced a frame", failures)
	_expect(RangerAnimationScript.duration_ticks_for(4, 8) == 15, "animation: the 4-frame 8fps clip length changed", failures)
	_expect(RangerAnimationScript.duration_ticks_for(4, 12) == 10, "animation: the 4-frame 12fps clip length changed", failures)
	_expect(RangerAnimationScript.duration_ticks_for(2, 12) == 5, "animation: the 2-frame 12fps clip length changed", failures)
	_expect(RangerAnimationScript.duration_ticks_for(1, 8) == 4, "animation: the single-frame hit length changed", failures)
	_expect(RangerAnimationScript.duration_ticks_for(3, 6) == 15, "animation: the 3-frame 6fps death length changed", failures)


func _test_arrow_attachment_anchors(failures: Array[String]) -> void:
	var release_frame := RangerAnimationScript.shoot_frame_at_tick(5)
	_expect(release_frame == 2, "animation: release no longer samples shoot frame 2", failures)
	var expected := {
		"south": Vector2i(27, 25),
		"north": Vector2i(24, 15),
		"east": Vector2i(36, 24),
		"west": Vector2i(12, 24),
	}
	for facing: String in RangerAnimationScript.FACINGS:
		var anchors: Array = RangerAnimationScript.ARROW_ATTACHMENT_BY_FACING_FRAME[facing]
		_expect(anchors.size() == 4, "animation: %s does not publish one bow-hand anchor per shoot frame" % facing, failures)
		_expect(RangerAnimationScript.arrow_attachment_local(facing, release_frame) == expected[facing], "animation: %s release anchor drifted from the authored bow hand" % facing, failures)
		for frame in range(4):
			var anchor := RangerAnimationScript.arrow_attachment_local(facing, frame)
			_expect(anchor.x >= 0 and anchor.y >= 0 and anchor.x < RangerAnimationScript.CELL.x and anchor.y < RangerAnimationScript.CELL.y, "animation: %s frame %d attachment leaves its cell" % [facing, frame], failures)
	var east_offset := RangerAnimationScript.arrow_attachment_offset("east", release_frame, ArenaWorldViewScript.GAMEPLAY_TO_WORLD)
	var west_offset := RangerAnimationScript.arrow_attachment_offset("west", release_frame, ArenaWorldViewScript.GAMEPLAY_TO_WORLD)
	_expect(east_offset.x > 0.0 and west_offset.x < 0.0 and east_offset.y < 0.0 and west_offset.y < 0.0, "animation: side-facing release sockets are not above the feet and beside the bow hand", failures)


func _test_west_walk_foot_stability(failures: Array[String]) -> void:
	## West walk frames 0/3 are painted one pixel above the common atlas foot anchor.
	## The reader must publish the presentation-only correction continuously through
	## the loop; no frame may move the visual foot away from the gameplay foot point.
	var animation = RangerAnimationScript.new(true, {}, _fixture_atlas())
	var corrected := [0, 3]
	for phase_tick in range(0, 16):
		var frame: Dictionary = animation.resolve({"facing": "west", "moving": true, "phase_ticks": phase_tick})
		var frame_index := int(frame.get("frame", -1))
		var offset: Vector2i = frame.get("draw_offset", Vector2i.ZERO)
		var expected := Vector2i(0, 1) if frame_index in corrected else Vector2i.ZERO
		_expect(offset == expected, "animation: west walk frame %d has draw offset %s instead of %s" % [frame_index, str(offset), str(expected)], failures)
		var painted_sole_y := 43 if frame_index in corrected else 44
		_expect(painted_sole_y + offset.y == RangerAnimationScript.DEFAULT_ANCHOR.y, "animation: west walk frame %d shifts the foot point" % frame_index, failures)
	# The west release slot is intentionally independent of walk correction.
	var release := RangerAnimationScript.shoot_frame_at_tick(5)
	_expect(RangerAnimationScript.arrow_attachment_local("west", release) == Vector2i(12, 24), "animation: west release anchor regressed while fixing walk feet", failures)


func _test_delivered_manifest(failures: Array[String]) -> void:
	## An in-memory manifest that matches the agreed matrix, built on published
	## pixels: frames are read from it per frame, including deliberately un-gridded
	## rects and differing anchors, so nothing may assume a fixed cell slot.
	var animation = RangerAnimationScript.new(true, {}, _fixture_atlas())
	_expect(animation.asset_state() == RangerAnimationScript.STATE_READY, "animation: a matching manifest did not validate: %s" % animation.pending_reason(), failures)
	if animation.asset_state() != RangerAnimationScript.STATE_READY:
		return
	_expect(animation.has_real_art(), "animation: a validated manifest loaded no textures", failures)
	_expect(animation.contract_notes().is_empty(), "animation: a matching manifest reported contract drift: %s" % str(animation.contract_notes()), failures)
	_expect(animation.clip_ids().size() == 28, "animation: the matrix is not four facings by seven actions", failures)
	_expect(animation.frame_count("ranger.south.walk") == 4, "animation: the walk clip lost its four frames", failures)
	_expect(animation.clip_info("ranger.south.death").get("loop", true) == false, "animation: the death clip is looping", failures)

	var idle: Dictionary = animation.resolve({"facing": Vector2.DOWN})
	_expect(not bool(idle["fallback"]), "animation: a validated manifest still reported a fallback", failures)
	_expect(String(idle["clip"]) == "ranger.south.idle", "animation: the idle clip is wrong: %s" % String(idle["clip"]), failures)
	_expect((idle["rect"] as Rect2i) == Rect2i(0, 0, 48, 48), "animation: the idle frame rect is not read from the manifest: %s" % str(idle["rect"]), failures)
	_expect((idle["anchor"] as Vector2i) == Vector2i(24, 44), "animation: the idle frame anchor is not read from the manifest: %s" % str(idle["anchor"]), failures)
	_expect(idle["texture"] != null, "animation: the resolved frame carries no texture", failures)

	var walk_first: Dictionary = animation.resolve({"facing": "east", "moving": true, "phase_ticks": 0})
	var walk_third: Dictionary = animation.resolve({"facing": "east", "moving": true, "phase_ticks": 12})
	_expect(String(walk_first["clip"]) == "ranger.east.walk", "animation: the walk clip is wrong: %s" % String(walk_first["clip"]), failures)
	_expect(int(walk_first["frame"]) == 0 and int(walk_third["frame"]) == 3, "animation: the walk loop did not advance with the clock", failures)
	_expect((walk_third["rect"] as Rect2i) == Rect2i(49, 0, 48, 48), "animation: a frame rect was assumed instead of read: %s" % str(walk_third["rect"]), failures)
	_expect((walk_third["anchor"] as Vector2i) == Vector2i(22, 44), "animation: a frame anchor was assumed instead of read: %s" % str(walk_third["anchor"]), failures)

	var death: Dictionary = animation.resolve({"dead": true, "death_ticks": 12})
	_expect(String(death["clip"]) == "ranger.south.death", "animation: the death clip is wrong: %s" % String(death["clip"]), failures)
	_expect(int(death["frame"]) == 2, "animation: the death clip does not hold its last frame", failures)
	_expect(int(death["frame_count"]) == 3, "animation: the death clip lost a frame", failures)

	var shot: Dictionary = animation.resolve({"facing": Vector2.RIGHT, "shoot_ticks": 5})
	_expect(String(shot["clip"]) == "ranger.east.shoot", "animation: the shot clip is wrong: %s" % String(shot["clip"]), failures)
	_expect(int(shot["frame"]) == 2, "animation: the shot did not start at its release frame: %d" % int(shot["frame"]), failures)


func _test_integration_report(failures: Array[String]) -> void:
	## The art pass reads this after a GPU capture to prove which frame was really
	## drawn and when the last event fired.
	var animation = RangerAnimationScript.new(true, {}, _fixture_atlas())
	_expect(animation.last_frame().is_empty(), "animation: the report started with a frame already drawn", failures)
	_expect((animation.integration_report().get("events", {}) as Dictionary).is_empty(), "animation: the report started with events", failures)
	animation.latch_event("ranger/shot", "ranger:cast:7", 40)
	var frame: Dictionary = animation.resolve({"facing": "west", "moving": true, "phase_ticks": 5, "tick": 41})
	_expect(int(frame["frame"]) == 1, "animation: the diagnostic resolve landed on frame %d instead of 1" % int(frame["frame"]), failures)
	var report: Dictionary = animation.integration_report()
	_expect(String(report["action"]) == "walk", "animation: the report lost the action", failures)
	_expect(String(report["facing"]) == "west", "animation: the report lost the facing", failures)
	_expect(String(report["clip"]) == "ranger.west.walk", "animation: the report lost the clip", failures)
	_expect(int(report["frame"]) == 1, "animation: the report lost the frame", failures)
	_expect((report["rect"] as Rect2i) == Rect2i(49, 0, 48, 48), "animation: the report lost the frame rect", failures)
	_expect((report["anchor"] as Vector2i) == Vector2i(24, 44), "animation: the report lost the frame anchor", failures)
	_expect(int(report["resolved_tick"]) == 41, "animation: the report lost the tick it was resolved at", failures)
	_expect(report["fallback"] == false, "animation: a drawn frame was reported as a fallback", failures)
	var events: Dictionary = report["events"]
	var shot: Dictionary = events.get("ranger/shot", {})
	_expect(String(shot.get("token", "")) == "ranger:cast:7", "animation: the report lost the event token: %s" % str(shot), failures)
	_expect(int(shot.get("tick", -1)) == 40 and int(shot.get("age_ticks", -1)) == 1, "animation: the report lost the event time: %s" % str(shot), failures)
	_expect(String(animation.last_event("ranger/shot").get("id", "")) == "ranger:cast:7", "animation: last_event did not answer", failures)
	_expect(animation.last_event("ranger/hit").is_empty(), "animation: last_event invented an event", failures)
	var pending = RangerAnimationScript.new(false)
	pending.resolve({"tick": 9})
	var pending_report: Dictionary = pending.integration_report()
	_expect(pending_report["fallback"] == true, "animation: the pending report hid its fallback", failures)
	_expect(not String(pending_report["reason"]).is_empty(), "animation: the pending report hid its reason", failures)
	_expect(int(pending_report["resolved_tick"]) == 9, "animation: the pending report lost its tick", failures)


func _test_shoot_release_mapping(failures: Array[String]) -> void:
	## The authority now owns a 5-tick windup and releases at age 5. The atlas
	## exposes both preparation poses before the release and recovery poses.
	var animation = RangerAnimationScript.new(true, {}, _fixture_atlas())
	_expect(int(RangerAnimationScript.ACTION_RUNTIME_ENTRY.get("shoot", 0)) == 0, "animation: the shoot runtime no longer begins at preparation", failures)
	var duration: int = RangerAnimationScript.duration_ticks_for(4, 12)
	var seen := {}
	for elapsed in range(0, duration + 3):
		var frame: Dictionary = animation.resolve({"facing": "south", "shoot_ticks": elapsed})
		if String(frame["action"]) != "shoot":
			continue
		seen[int(frame["frame"])] = true
	_expect(seen.keys().size() == 4 and seen.has(0) and seen.has(1) and seen.has(2) and seen.has(3), "animation: the runtime shot did not play all authored phases: %s" % str(seen.keys()), failures)
	_expect(int(animation.resolve({"facing": "south", "shoot_ticks": 0})["frame"]) == 0, "animation: the accepted action did not begin at preparation frame", failures)
	_expect(int(animation.resolve({"facing": "south", "shoot_ticks": 5})["frame"]) == 2, "animation: the impact tick did not draw the release frame", failures)
	_expect(int(animation.resolve({"facing": "south", "shoot_ticks": 9})["frame"]) == 3, "animation: the shot did not hold its recovery frame", failures)
	var prepared: Dictionary = animation.frame_for("ranger.south.shoot", 0)
	_expect((prepared.get("rect", Rect2i()) as Rect2i) == Rect2i(0, 48, 48, 48), "animation: the preparation frame is not readable for fixtures: %s" % str(prepared.get("rect", Rect2i())), failures)
	_expect(int(animation.clip_info("ranger.south.shoot").get("entry_frame", -1)) == 0, "animation: the clip does not publish its runtime entry", failures)
	_expect(int(animation.integration_report().get("entry_frame", -1)) == 0, "animation: the integration report lost the runtime entry", failures)


func _test_broken_deliveries(failures: Array[String]) -> void:
	## Every broken delivery has to end in an explicit, named report, never in a
	## silent pass and never in a drawable frame.
	var missing = RangerAnimationScript.new(true, {"atlas": "res://art/production/p1/ranger_actions_v01/does_not_exist.json"})
	_expect(missing.asset_state() == RangerAnimationScript.STATE_PENDING, "animation: a missing atlas is not pending", failures)
	_expect(missing.pending_reason().contains("does_not_exist"), "animation: the pending reason does not name the missing atlas: %s" % missing.pending_reason(), failures)
	_expect(bool(missing.resolve({})["fallback"]), "animation: a missing atlas produced a drawable frame", failures)

	var not_json = RangerAnimationScript.new(true, {"atlas": "res://project.godot"})
	_expect(not_json.asset_state() == RangerAnimationScript.STATE_INVALID, "animation: a non-JSON delivery reported %s" % not_json.asset_state(), failures)
	_expect(not not_json.pending_reason().is_empty(), "animation: a non-JSON delivery was not reported", failures)
	_expect(bool(not_json.resolve({})["fallback"]), "animation: a non-JSON delivery produced a drawable frame", failures)

	var incomplete := _fixture_atlas()
	(incomplete["animations"] as Dictionary).erase("ranger.north.dash")
	var missing_clip = RangerAnimationScript.new(false, {}, incomplete)
	_expect(missing_clip.asset_state() == RangerAnimationScript.STATE_INVALID, "animation: a manifest without ranger.north.dash still reported %s" % missing_clip.asset_state(), failures)
	_expect(missing_clip.pending_reason().contains("ranger.north.dash"), "animation: the invalid report does not name the missing clip: %s" % missing_clip.pending_reason(), failures)
	_expect(bool(missing_clip.resolve({})["fallback"]), "animation: an incomplete manifest produced a drawable frame", failures)

	var wrong_cell := _fixture_atlas()
	((wrong_cell["sprites"] as Dictionary)["ranger.south.walk.0"] as Dictionary)["rect"] = [0, 0, 32, 48]
	var wrong_cell_reader = RangerAnimationScript.new(false, {}, wrong_cell)
	_expect(wrong_cell_reader.asset_state() == RangerAnimationScript.STATE_INVALID, "animation: a 32x48 frame cell was accepted", failures)
	_expect(wrong_cell_reader.pending_reason().contains("ranger.south.walk.0"), "animation: the invalid cell report does not name the sprite: %s" % wrong_cell_reader.pending_reason(), failures)

	var outside := _fixture_atlas()
	((outside["sprites"] as Dictionary)["ranger.south.hit.0"] as Dictionary)["rect"] = [160, 0, 48, 48]
	var outside_reader = RangerAnimationScript.new(false, {}, outside)
	_expect(outside_reader.asset_state() == RangerAnimationScript.STATE_INVALID, "animation: a frame outside its sheet was accepted", failures)

	var dangling := _fixture_atlas()
	((dangling["sprites"] as Dictionary)["ranger.south.shoot.0"] as Dictionary)["texture"] = "missing_key"
	var dangling_reader = RangerAnimationScript.new(false, {}, dangling)
	_expect(dangling_reader.asset_state() == RangerAnimationScript.STATE_INVALID, "animation: a frame with an unknown texture key was accepted", failures)

	var no_sheet := _fixture_atlas()
	(no_sheet["textures"] as Dictionary).erase("ranger")
	var no_sheet_reader = RangerAnimationScript.new(false, {}, no_sheet)
	_expect(no_sheet_reader.asset_state() == RangerAnimationScript.STATE_INVALID, "animation: an atlas without the ranger sheet was accepted", failures)

	var drifted := _fixture_atlas()
	((drifted["animations"] as Dictionary)["ranger.south.walk"] as Dictionary)["loop"] = false
	var drifted_reader = RangerAnimationScript.new(false, {}, drifted)
	_expect(drifted_reader.asset_state() == RangerAnimationScript.STATE_READY, "animation: a timing drift should stay drawable", failures)
	_expect(not drifted_reader.contract_notes().is_empty(), "animation: a timing drift against the hand-off was not reported", failures)

	## The published idle reuses the same-facing shoot recovery pose. Disclosed
	## reuse is accepted and recorded; an undeclared mismatch is not.
	var disclosed := _fixture_atlas()
	for facing: String in RangerAnimationScript.FACINGS:
		var pose_id := "ranger.%s.shoot.3" % facing
		var pose := (disclosed["sprites"] as Dictionary)[pose_id] as Dictionary
		pose["state"] = "shoot"
		pose["source"] = pose_id
		((disclosed["animations"] as Dictionary)["ranger.%s.idle" % facing] as Dictionary)["frames"] = [pose_id]
	var disclosed_reader = RangerAnimationScript.new(true, {}, disclosed)
	_expect(disclosed_reader.asset_state() == RangerAnimationScript.STATE_READY, "animation: a disclosed reused pose was rejected: %s" % disclosed_reader.pending_reason(), failures)
	var idle_frame: Dictionary = disclosed_reader.resolve({"facing": "south"})
	_expect(String(idle_frame["source"]) == "ranger.south.shoot.3", "animation: the reused pose was not disclosed in the resolved frame: %s" % str(idle_frame.get("source", "")), failures)
	_expect((idle_frame["rect"] as Rect2i) == Rect2i(0, 96, 48, 48), "animation: the reused pose read another rect: %s" % str(idle_frame["rect"]), failures)
	var disclosed_notes: Array[String] = disclosed_reader.contract_notes()
	var reuse_noted := false
	for note: String in disclosed_notes:
		if note.contains("reuses the disclosed shoot pose"):
			reuse_noted = true
	_expect(reuse_noted, "animation: the cross-animation reuse was not recorded: %s" % str(disclosed_notes), failures)

	var undeclared := _fixture_atlas()
	for facing: String in RangerAnimationScript.FACINGS:
		var pose_id := "ranger.%s.shoot.3" % facing
		((undeclared["sprites"] as Dictionary)[pose_id] as Dictionary)["state"] = "shoot"
		((undeclared["animations"] as Dictionary)["ranger.%s.idle" % facing] as Dictionary)["frames"] = [pose_id]
	var undeclared_reader = RangerAnimationScript.new(false, {}, undeclared)
	_expect(undeclared_reader.asset_state() == RangerAnimationScript.STATE_INVALID, "animation: an undeclared pose mismatch was accepted", failures)
	_expect(undeclared_reader.pending_reason().contains("ranger.south.idle"), "animation: the undeclared mismatch does not name the clip: %s" % undeclared_reader.pending_reason(), failures)




func _test_view_integration(failures: Array[String]) -> void:
	var hub := BaseHubScript.new()
	root.add_child(hub)
	hub._ready()
	var view := hub.get_hub_view()
	var town = hub.get_town_runtime()
	_expect(bool(hub.town_load_report.get("ok", false)), "view: native town assets did not load", failures)
	var report: Dictionary = view.hero_animation_report()
	_expect(not bool(report.get("fallback", true)) and report.get("texture", null) != null, "view: required ranger frame fell back", failures)
	_expect(String(report.get("clip", "")).begins_with("ranger.south."), "view: town facing/clip differs", failures)
	_expect(Vector2i((report.rect as Rect2i).size) == RangerAnimationScript.CELL and Vector2i(report.anchor) == RangerAnimationScript.DEFAULT_ANCHOR, "view: ranger cell or feet anchor changed", failures)
	hub.move_hero(Vector2.RIGHT, 1.0 / 30.0)
	var moving: Dictionary = view.hero_animation_report()
	_expect(moving.action == "walk" and moving.facing == "east" and int(moving.resolved_tick) == town.simulation.tick, "view: ranger presentation does not consume the fixed tick state", failures)
	var before: Dictionary = town.snapshot()
	view._process(0.2)
	_expect(town.snapshot() == before, "view: ranger presentation wrote town gameplay", failures)
	var world = ArenaWorldViewScript.new()
	var feet := Vector2(512, 320)
	_expect(world.hero_cell_world(feet) == Rect2(feet - Vector2(24, 44), Vector2(48, 48)), "view: visual occlusion misses extended action cell", failures)
	_shutdown_hub(hub)


func _fixture_atlas() -> Dictionary:
	## Published pixels, manifest-declared frames: no art is created here. Two
	## frames sit off the 48px grid and one anchor differs on purpose.
	var layout := {
		"idle": [[0, 0, 24, 44]],
		"walk": [[0, 0, 24, 44], [49, 0, 24, 44], [98, 0, 24, 44], [49, 0, 22, 44]],
		"shoot": [[0, 48, 24, 44], [49, 48, 24, 44], [98, 48, 24, 44], [0, 96, 24, 44]],
		"dodge": [[49, 96, 24, 44], [98, 96, 23, 44]],
		"dash": [[0, 0, 24, 44], [98, 96, 24, 45]],
		"hit": [[98, 48, 24, 44]],
		"death": [[0, 48, 24, 43], [49, 48, 24, 43], [98, 48, 23, 43]],
	}
	var contract: Dictionary = RangerAnimationScript.ACTION_CONTRACT
	var sprites := {}
	var animations := {}
	for facing: String in RangerAnimationScript.FACINGS:
		for action: String in RangerAnimationScript.ACTIONS:
			var agreement: Dictionary = contract[action]
			var ids: Array[String] = []
			var slots: Array = layout[action]
			for index in int(agreement["frames"]):
				var slot: Array = slots[index % slots.size()]
				var frame_id := "ranger.%s.%s.%d" % [facing, action, index]
				sprites[frame_id] = {
					"texture": "ranger",
					"rect": [slot[0], slot[1], 48, 48],
					"anchor": [slot[2], slot[3]],
					"facing": facing,
				}
				ids.append(frame_id)
			animations["ranger.%s.%s" % [facing, action]] = {
				"frames": ids,
				"fps": int(agreement["fps"]),
				"loop": bool(agreement["loop"]),
			}
	return {
		"schema_version": 1,
		"native_view": [640, 360],
		"textures": {"ranger": {"path": FIXTURE_SHEET, "width": FIXTURE_SHEET_SIZE.x, "height": FIXTURE_SHEET_SIZE.y}},
		"sprites": sprites,
		"animations": animations,
	}


func _expect(condition: bool, message: String, failures: Array[String]) -> void: Assert.expect(condition, message, failures)


func _shutdown_hub(hub: Node) -> void:
	if hub == null or not is_instance_valid(hub):
		return
	var controller: Variant = hub.get("_town_controller")
	if controller != null:
		var runtime: Variant = controller.get("scene_runtime")
		if runtime != null and runtime.has_method("unmount"):
			runtime.unmount()
	if hub.get_parent() != null:
		hub.get_parent().remove_child(hub)
	hub.free()
