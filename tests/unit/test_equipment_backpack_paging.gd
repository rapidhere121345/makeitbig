extends SceneTree

const GridScript = preload("res://src/presentation/equipment_backpack_grid.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var host := Control.new()
	host.size = Vector2(420, 260)
	root.add_child(host)
	var grid = GridScript.new()
	grid.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.add_child(grid)
	var entries: Array = []
	for index in 10:
		entries.append({"instance_id": "item_%02d" % index, "display_name": "物品 %02d" % index})
	grid.configure(entries, "item_00", 4, "Test", 2)
	for frame in 6:
		await process_frame
	_expect(grid.page_count() == 2 and grid.page_index() == 0, "paged grid did not report two pages")
	_expect(grid.visible_instance_ids().size() == 8, "first page did not contain exactly two rows of four")
	var cells: Array[Node] = grid.find_children("BackpackCell_*", "PanelContainer", true, false)
	var cells_grid := grid.find_child("EquipmentBackpackCells", true, false) as GridContainer
	_expect(cells_grid != null and cells_grid.columns == 4 and cells_grid.size.x >= 320.0,
		"grid geometry is not four columns wide: %s" % ("missing" if cells_grid == null else "%d / %s" % [cells_grid.columns, str(cells_grid.size)]))
	_expect(cells.size() == 8, "first page rendered %d cells instead of 8" % cells.size())
	if cells.size() == 8:
		var first := (cells[0] as Control).position
		var fourth := (cells[3] as Control).position
		var fifth := (cells[4] as Control).position
		_expect(fourth.y == first.y and fourth.x > first.x and fifth.y > first.y,
			"grid did not lay out four columns before the second row: %s / %s / %s" % [str(first), str(fourth), str(fifth)])
	var viewport := grid.find_child("EquipmentBackpackViewport", true, false) as Control
	_expect(viewport != null and not viewport is ScrollContainer, "paged inventory still uses a ScrollContainer")
	var inspected: Array[String] = []
	var activated: Array[String] = []
	grid.item_inspected.connect(func(instance_id: String) -> void: inspected.append(instance_id))
	grid.item_activated.connect(func(instance_id: String) -> void: activated.append(instance_id))
	var first_button := grid.find_child("BackpackItem_item_00", true, false) as Button
	_expect(first_button != null and first_button.focus_mode == Control.FOCUS_ALL,
		"inventory cell is not keyboard/controller focusable")
	if first_button != null:
		first_button.mouse_entered.emit()
		first_button.focus_entered.emit()
		first_button.pressed.emit()
	_expect(inspected.has("item_00") and activated == ["item_00"],
		"hover/focus/activation did not preserve the stable item identity")
	var next := grid.find_child("BackpackNextPage", true, false) as Button
	_expect(next != null and not next.disabled and next.focus_mode == Control.FOCUS_ALL,
		"next-page keyboard/controller control is missing or disabled")
	if next != null:
		next.pressed.emit()
		await process_frame
	_expect(grid.page_index() == 1 and grid.visible_instance_ids() == ["item_08", "item_09"],
		"next page did not expose the final two stable items: %s" % str(grid.visible_instance_ids()))
	var wheel_up := InputEventMouseButton.new()
	wheel_up.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel_up.pressed = true
	grid._on_viewport_input(wheel_up)
	await process_frame
	_expect(grid.page_index() == 0, "mouse wheel did not preserve page navigation below compact layouts")
	grid.show_item("item_03")
	await process_frame
	_expect(grid.page_index() == 0 and grid.get_cell("item_03") != null,
		"show_item did not return to the page containing the requested item")
	host.free()
	if failures.is_empty():
		print("PASS  test_equipment_backpack_paging.gd")
		quit(0)
		return
	for failure in failures:
		printerr("- ", failure)
	quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
