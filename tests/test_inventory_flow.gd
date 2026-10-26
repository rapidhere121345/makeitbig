extends SceneTree

const Facility = preload("res://src/presentation/facility_screen.gd")
const Fixture = preload("res://tests/test_facility_screen.gd")
const Comparison = preload("res://src/presentation/equipment_comparison.gd")
const Assert := preload("res://tests/helpers/assert.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_comparison()
	var fixture := Fixture.new()
	var data: Dictionary = fixture._real_loadout_snapshot()
	fixture.free()
	var original := data.duplicate(true)
	root.size = Vector2i(1280, 720)
	var screen := Facility.new()
	root.add_child(screen)
	screen.present("loadout", {}, {}, "", data)
	await _settle()
	var actions: Array = []
	screen.action_requested.connect(func(facility: String, action: String, payload: Dictionary): actions.append([facility, action, payload]))
	var bar := screen.find_child("EquipmentFilterBar", true, false)
	var keyword := screen.find_child("CandidateKeywordFilter", true, false) as LineEdit
	var same_search := keyword.get_instance_id()
	keyword.grab_focus()
	keyword.text = "Swift Bow"
	keyword.caret_column = 1
	keyword.text_changed.emit(keyword.text)
	await _settle()
	_expect(keyword.get_instance_id() == same_search and is_instance_valid(keyword) and keyword.has_focus() and keyword.caret_column == 1,
		"Filtering replaced the search field or lost its editing cursor")
	_expect(screen.get_visible_text().contains("Click Reset to view all"), "Empty search has no recovery action")
	bar.reset_query()
	await _settle()
	_expect(screen.backpack_cell("loot:bow/2") != null and screen.backpack_cell("equipped_main") != null, "Reset did not restore the owned item and candidate")
	_expect(screen.find_child("BackpackStatus_equipped_main", true, false) != null, "Equipped item has no explicit state badge")
	var picker := screen.find_child("EquipmentBackpack", true, false) as Control
	var picker_rect := picker.get_global_rect()
	var toggle := screen.get_action_button("CandidateFiltersToggle")
	toggle.grab_focus()
	toggle.pressed.emit()
	await _settle()
	var dialog := screen.find_child("CandidateFilterDialog", true, false) as AcceptDialog
	_expect(dialog != null and dialog.visible and picker.get_global_rect() == picker_rect, "Advanced filters displaced the inventory")
	var rune := screen.find_child("CandidateRuneFilter", true, false) as CheckButton
	rune.button_pressed = true
	await _settle()
	_expect(bool(bar.current_query().requires_rune) and dialog.visible and screen.find_child("CandidateKeywordFilter", true, false).get_instance_id() == same_search,
		"Changing an advanced condition replaced the toolbar or closed its dialog")
	dialog.get_ok_button().pressed.emit()
	await _settle()
	_expect(not dialog.visible and toggle.has_focus(), "Closing filters did not restore their opener")
	bar.reset_query()
	await _settle()
	_expect(actions.is_empty() and data == original and screen._facility_data == original,
		"Inspecting/filtering inventory mutated equipment or emitted a domain action")
	screen.queue_free()
	await process_frame
	if failures.is_empty():
		print("PASS  test_inventory_flow.gd")
	else:
		for failure in failures: printerr("- " + failure)
	quit(0 if failures.is_empty() else 1)


func _check_comparison() -> void:
	var current := {"p": 0.61, "turn": 0.16, "damage": 100.0}
	var replacement := {"p": 0.54, "turn": 0.12, "damage": 112.0}
	var rows := Comparison.comparison_rows(current, replacement)
	var by_key := {}
	for row in rows: by_key[row.key] = row
	_expect(by_key.p.delta_text == "−7 percentage points" and not by_key.p.improves, "Probability delta must use percentage points")
	_expect(by_key.turn.delta_text == "Faster 0.04s" and by_key.turn.improves, "Shorter turn time was not identified as faster")
	_expect(by_key.damage.delta_text == "+12", "Damage comparison has no exact delta")
	_expect(Comparison.comparison_rows({"p": 0.5}, {"damage": 12}).is_empty(), "Disjoint parameters became a fake comparison")
	_expect(Comparison.comparison_rows({"damage": 1}, {"damage": NAN}).is_empty(), "Nonfinite preview was rendered as a valid attribute")
	var grid := Comparison.new()
	grid.present(current, replacement)
	var count := grid.get_child_count()
	grid.present(current, replacement)
	_expect(grid.get_child_count() == count and grid.columns == 4, "Repeated comparison appended duplicate rows")
	grid.free()


func _settle() -> void:
	for index in 4: await process_frame


func _expect(condition: bool, detail: String) -> void: Assert.expect(condition, detail, failures)
