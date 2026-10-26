extends "res://tests/test_facility_screen.gd"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var completed := 0
	for facility: String in ["loadout", "training", "forge", "proxy"]:
		var snapshot: Dictionary
		match facility:
			"loadout": snapshot = _real_loadout_snapshot()
			"training": snapshot = _training_snapshot(false, _layout_fingerprint(), {})
			"forge": snapshot = _forge_snapshot(true)
			"proxy": snapshot = _proxy_unlocked_snapshot()
		var screen := FacilityScreenScript.new()
		root.add_child(screen)
		screen.present(facility, {}, {}, "", snapshot)
		for frame in range(4):
			await process_frame
		var back := screen.find_child("ReturnToBaseButton", true, false) as Button
		_expect_focus(back != null and root.gui_get_focus_owner() == back,
			facility + ": initial keyboard focus missing")
		var next := InputEventKey.new()
		next.keycode = KEY_TAB
		next.pressed = true
		root.push_input(next)
		await process_frame
		var chosen := root.gui_get_focus_owner()
		_expect_focus(chosen != null and chosen != back, facility + ": Tab did not enter page controls")
		screen.present(facility, {}, {}, "", snapshot)
		for frame in range(4):
			await process_frame
		_expect_focus(root.gui_get_focus_owner() != back,
			facility + ": refresh stole focus back to Hub")
		var scroll := screen.find_child("FacilityCardsScroll", true, false) as ScrollContainer
		_expect_focus(scroll != null and not scroll.get_v_scroll_bar().get_theme_stylebox("grabber") is StyleBoxEmpty,
			facility + ": scroll thumb must remain visible when content overflows")
		var returns := [0]
		screen.base_requested.connect(func() -> void: returns[0] += 1)
		back.grab_focus()
		var accept := InputEventAction.new()
		accept.action = &"ui_accept"
		accept.pressed = true
		root.push_input(accept)
		accept = InputEventAction.new()
		accept.action = &"ui_accept"
		accept.pressed = false
		root.push_input(accept)
		_expect_focus(returns[0] == 1, facility + ": focused Hub action did not activate")
		screen.free()
		await process_frame
		completed += 1
	_expect_focus(completed == 4, "all four facility cases must complete")
	if failures.is_empty():
		print("PASS test_facility_entry_focus.gd")
	else:
		for failure in failures:
			printerr(failure)
	quit(0 if failures.is_empty() else 1)


func _expect_focus(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
