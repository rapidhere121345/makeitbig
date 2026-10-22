extends SceneTree
## Input regressions for the tutorial's combat-aligned pointer shot: a left
## click must pick the real training target with ManualAimResolver's combat
## geometry, an empty-ground click never casts and answers with one short
## expiring hint, and the concise key instructions stay single-mention copy.

const TutorialScreenScript = preload("res://src/presentation/tutorial_screen.gd")
const RangerAnimationScript = preload("res://src/presentation/ranger_animation.gd")
const PlayerActionTimelineScript = preload("res://src/systems/player_action_timeline.gd")
const Game := preload("res://src/game/game_root.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var screen = TutorialScreenScript.new()
	root.add_child(screen)
	screen.present("ranger")

	_test_picking_geometry(screen)
	_test_copy_remains_single_mention(screen)
	await _test_empty_click_hint_lifecycle(screen)
	await _test_target_click_casts(screen)
	await _test_viewport_wrapper_routes_clicks(screen)
	await _test_real_event_dispatch_routes_to_tutorial()

	root.remove_child(screen)
	screen.free()
	if failures.is_empty():
		print("PASS  tests/test_tutorial_pointer_cast.gd")
		quit(0)
		return
	printerr("%d tutorial pointer cast check(s) failed:" % failures.size())
	for failure in failures:
		printerr("- %s" % failure)
	quit(1)


func _test_picking_geometry(screen) -> void:
	var anchor: Vector2 = screen.TARGET_POSITION + TutorialScreenScript.TARGET_PICK_ANCHOR_OFFSET
	screen.set_player_position(anchor - Vector2(120.0, 0.0))
	_expect(not screen._pointer_hits_target(anchor + Vector2(TutorialScreenScript.TARGET_PICK_RADIUS + 2.0, 0.0)),
		"tutorial pick: a click beyond the combat body radius hit the target")
	_expect(screen._pointer_hits_target(anchor + Vector2(TutorialScreenScript.TARGET_PICK_RADIUS - 2.0, 0.0)),
		"tutorial pick: a click inside the combat body radius missed the target")
	_expect(not screen._pointer_hits_target(screen.TARGET_POSITION + Vector2(0.0, 20.0)),
		"tutorial pick: a point below the sprite body counted as inside the anchor circle")


func _test_empty_click_hint_lifecycle(screen) -> void:
	screen.set_player_position(Vector2(440.0, 240.0))
	var receipt: Dictionary = screen.pointer_cast_at_arena(Vector2(120.0, 120.0))
	_expect(not bool(receipt.get("accepted", true)) and String(receipt.get("reason", "")) == "empty",
		"tutorial empty click: the click cast from empty ground")
	_expect(not bool(screen.get_checklist_snapshot().cast_hit),
		"tutorial empty click: empty ground completed the cast checklist")
	_expect(screen.hint_active() and screen.current_status_text().contains("Missed the training target"),
		"tutorial empty click: no actionable hint appeared")
	_expect(screen.current_status_text().contains("Space"),
		"tutorial empty click: the hint omitted the assisted-aim alternative")
	## A successful target cast is a newer intent: it must clear the standing
	## empty-click hint immediately, not let it outlive the windup.
	var hit: Dictionary = screen.pointer_cast_at_arena(screen.TARGET_POSITION + TutorialScreenScript.TARGET_PICK_ANCHOR_OFFSET)
	_expect(bool(hit.get("accepted", false)) and String(hit.get("reason", "")) == "hit",
		"tutorial empty click: the follow-up target click did not cast")
	_expect(not screen.hint_active() and not screen.current_status_text().contains("Missed the training target"),
		"tutorial empty click: a successful cast left the old hint on screen")
	_advance_ticks(screen, PlayerActionTimelineScript.WINDUP_TICKS + PlayerActionTimelineScript.RECOVERY_TICKS + 40)
	_expect(bool(screen.get_checklist_snapshot().cast_hit),
		"tutorial empty click: the follow-up cast never hit the target")


func _test_target_click_casts(screen) -> void:
	var anchor: Vector2 = screen.TARGET_POSITION + TutorialScreenScript.TARGET_PICK_ANCHOR_OFFSET
	var receipt: Dictionary = screen.pointer_cast_at_arena(anchor)
	_expect(bool(receipt.get("accepted", false)) and String(receipt.get("reason", "")) == "hit",
		"tutorial target click: an in-range click on the target did not cast")
	_expect(not screen.hint_active(), "tutorial target click: a successful cast left a hint active")
	_advance_ticks(screen, PlayerActionTimelineScript.WINDUP_TICKS + PlayerActionTimelineScript.RECOVERY_TICKS + 2)
	screen.set_player_position(TutorialScreenScript.PLAYABLE_BOUNDS.position)
	var range_receipt: Dictionary = screen.pointer_cast_at_arena(anchor)
	_expect(not bool(range_receipt.get("accepted", true)) and String(range_receipt.get("reason", "")) == "range",
		"tutorial target click: an out-of-range target click reported the wrong reason")
	_expect(screen.current_status_text().contains("Out of range"),
		"tutorial target click: the out-of-range guidance disappeared")


## The routing regression the rendered session caught: a real dispatched mouse
## event must travel Window -> PixelStage -> tutorial and change the visible
## status. Direct method calls cannot prove this path.
func _test_real_event_dispatch_routes_to_tutorial() -> void:
	var game = Game.new()
	## A unique throwaway save: reusing a stale fixture profile makes
	## start_new_game refuse, which is domain behavior, not a routing signal.
	game.save_directory_path = "user://input-check-dispatch-save-%d-%d" % [
		int(Time.get_unix_time_from_system() * 1000.0),
		OS.get_process_id(),
	]
	game.playtest_logging_enabled = false
	root.add_child(game)
	await _frames(3)
	game.initialize(PackedStringArray())
	await _frames(2)
	var started: bool = bool(game.start_new_game("ranger").get("ok", false))
	_expect(started and game.current_route == "tutorial", "dispatch fixture did not reach the tutorial")
	await _frames(3)
	if started:
		var screen = game.current_screen
		var press := InputEventMouseButton.new()
		press.button_index = MOUSE_BUTTON_LEFT
		press.position = Vector2(200.0, 400.0)
		press.global_position = press.position
		press.button_mask = MOUSE_BUTTON_MASK_LEFT
		press.pressed = true
		Input.parse_input_event(press)
		await _frames(2)
		var release := InputEventMouseButton.new()
		release.button_index = MOUSE_BUTTON_LEFT
		release.position = Vector2(200.0, 400.0)
		release.global_position = release.position
		release.pressed = false
		Input.parse_input_event(release)
		await _frames(1)
		_expect(screen.current_status_text().contains("Missed the training target") and screen.hint_active(),
			"a real dispatched empty click never reached the tutorial")
	game.queue_free()
	await _frames(2)


func _test_copy_remains_single_mention(screen) -> void:
	var copy := _visible_copy(screen)
	_expect(copy.count("Space") == 1 and copy.count("WASD") == 1 and copy.count("Shift") == 1,
		"tutorial copy: key instructions are no longer single-mention")
	_expect(copy.contains("the target"), "tutorial copy: the click-on-target rule is missing")


func _test_viewport_wrapper_routes_clicks(screen) -> void:
	## At exactly 1280x720 the design canvas transform is the identity, so real
	## viewport coordinates can be asserted end to end without matrix math.
	root.size = Vector2i(1280, 720)
	await process_frame
	await process_frame
	screen.set_player_position(Vector2(580.0, 240.0))
	var empty_click: Dictionary = {}
	screen._attempt_pointer_cast(Vector2(200.0, 150.0))
	empty_click = {"hint": screen.hint_active()}
	_expect(bool(empty_click.get("hint", false)),
		"tutorial wrapper: an empty viewport click produced no hint")
	_advance_ticks(screen, PlayerActionTimelineScript.WINDUP_TICKS + PlayerActionTimelineScript.RECOVERY_TICKS + 2)
	var anchor_viewport: Vector2 = TutorialScreenScript.ARENA_ORIGIN + screen.TARGET_POSITION + TutorialScreenScript.TARGET_PICK_ANCHOR_OFFSET
	var target_click: Dictionary = screen.pointer_cast_at_arena(anchor_viewport - TutorialScreenScript.ARENA_ORIGIN)
	_expect(bool(target_click.get("accepted", false)),
		"tutorial wrapper: the viewport-aligned target click did not cast")


func _visible_copy(node: Node) -> String:
	var copy := ""
	if node is Label and node.visible:
		copy += node.text + "\n"
	for child in node.get_children():
		copy += _visible_copy(child)
	return copy


func _advance_ticks(screen, ticks: int) -> void:
	## Same epsilon convention as the tutorial screen regression: a small float
	## guard so the shared authority never lands one tick short.
	screen._process(float(ticks) / float(RangerAnimationScript.SIM_TICKS_PER_SECOND) + 0.0001)


func _frames(count: int) -> void:
	for i in range(count):
		await process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
