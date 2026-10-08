extends SceneTree

const ResultScreenScript = preload("res://src/presentation/result_screen.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var host := Control.new()
	host.size = Vector2(1280, 720)
	root.add_child(host)
	var screen := ResultScreenScript.new()
	host.add_child(screen)
	var reviews: Array[int] = [0]
	screen.loadout_review_requested.connect(func(_instance_id: String, _slot: String) -> void:
		reviews[0] += 1
	)
	screen.present({
		"outcome": "victory",
		"rewards": {
			"equipment_drops": [{
				"instance_id": "navigation_drop",
				"base_item_id": "ashwood_longbow",
				"slot": "main_hand",
				"affixes": [],
			}],
			"equipment_drop_count": 1,
		},
	}, {}, {
			"inventory": {"equipment": [{"instance_id": "navigation_drop", "base_item_id": "ashwood_longbow", "slot": "main_hand", "affixes": []}]},
			"active_build": {"equipped_item_ids": {}},
		})
	await _frames(3)

	var base_button := screen.find_child("ReturnToBaseButton", true, false) as Button
	var contract_button := screen.find_child("ContractAgainButton", true, false) as Button
	var review_button := screen.find_child("ReviewDrop_navigation_drop", true, false) as Button
	var detail_button := screen.find_child("EquipmentDetailButton", true, false) as Button
	_expect(base_button != null and base_button.has_focus(), "result: initial keyboard focus is not on the primary return action")
	_expect(base_button != null and base_button.has_theme_stylebox_override("normal")
		and contract_button != null and not contract_button.has_theme_stylebox_override("normal"),
		"result: ordinary settlement actions are not visually separated into primary and secondary")
	_expect(base_button.size_flags_stretch_ratio > contract_button.size_flags_stretch_ratio,
		"result: primary and secondary footer actions have equal visual weight")
	_expect(review_button != null and review_button.has_theme_stylebox_override("normal"),
		"result: equipment comparison is not the primary action on its drop card")

	review_button.grab_focus()
	await _press_accept()
	_expect(reviews[0] == 1, "result: one keyboard accept did not emit exactly one comparison request")

	detail_button.grab_focus()
	await _press_accept()
	var overlay := screen.find_child("EquipmentDetailOverlay", true, false) as Control
	var close_button := screen.find_child("EquipmentDetailClose", true, false) as Button
	_expect(overlay.visible and close_button.has_focus(), "result: equipment detail did not take keyboard focus")
	await _press_accept()
	_expect(not overlay.visible and detail_button.has_focus(), "result: closing equipment detail did not restore the source focus")

	detail_button.grab_focus()
	await _press_accept()
	review_button.grab_focus()
	await _press_escape()
	_expect(not overlay.visible and review_button.has_focus(), "result: Escape did not close equipment detail to the comparison action")

	var report_button := screen.find_child("ReportDetailButton", true, false) as Button
	var evidence := screen.find_child("EvidenceCard_observed", true, false) as Control
	report_button.grab_focus()
	await _press_accept()
	_expect(evidence.is_visible_in_tree() and report_button.has_focus(), "result: report detail activation lost its toggle focus")
	await _press_accept()
	_expect(not evidence.is_visible_in_tree() and report_button.has_focus(), "result: report detail collapse lost its toggle focus")

	screen.present({"outcome": "final_victory", "rewards": {}})
	await _frames(2)
	var ending_button := screen.find_child("EndingButton", true, false) as Button
	_expect(ending_button != null and ending_button.has_focus()
		and ending_button.has_theme_stylebox_override("normal")
		and not base_button.has_theme_stylebox_override("normal"),
		"result: final-victory focus and primary styling did not move to the ending action")

	host.free()
	if failures.is_empty():
		print("PASS  tests/test_contract_result_navigation.gd: contract/result navigation")
		quit(0)
		return
	printerr("%d navigation check(s) failed:" % failures.size())
	for failure in failures:
		printerr("- %s" % failure)
	quit(1)


func _press_accept() -> void:
	var key := InputEventKey.new()
	key.keycode = KEY_ENTER
	key.physical_keycode = KEY_ENTER
	key.pressed = true
	root.push_input(key, true)
	await _frames(1)
	key = key.duplicate()
	key.pressed = false
	root.push_input(key, true)
	await _frames(2)


func _press_escape() -> void:
	var focus_owner := root.gui_get_focus_owner()
	var key := InputEventKey.new()
	key.keycode = KEY_ESCAPE
	key.physical_keycode = KEY_ESCAPE
	key.pressed = true
	var screen := focus_owner as ResultScreenScript
	while screen == null and focus_owner != null:
		focus_owner = focus_owner.get_parent() as Control
		screen = focus_owner as ResultScreenScript
	if screen != null:
		screen.call("_unhandled_input", key)
	await _frames(1)
	key = InputEventKey.new()
	key.keycode = KEY_ESCAPE
	key.physical_keycode = KEY_ESCAPE
	key.pressed = false
	if screen != null:
		screen.call("_unhandled_input", key)
	await _frames(2)


func _frames(count: int) -> void:
	for _index in count:
		await process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
