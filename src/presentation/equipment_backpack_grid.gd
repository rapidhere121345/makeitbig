class_name EquipmentBackpackGrid
extends VBoxContainer
## Fixed-height, paged equipment picker. Every inventory item owns one icon cell;
## the caller owns the single shared detail surface and gameplay actions.

signal item_inspected(instance_id: String)
signal item_activated(instance_id: String)
signal page_changed(page_index: int, page_count: int)

const Shell = preload("res://src/presentation/shell_theme.gd")

const CELL_SIZE := Vector2(76, 76)
const CELL_GAP := 6
const PAGER_HEIGHT := 34.0

var _selected_id := ""
var _cells: Dictionary = {}
var _hovered_id := ""
var _focused_id := ""
var _entries: Array = []
var _columns := 4
var _rows := 2
var _node_prefix := "Backpack"
var _page_index := 0
var _grid: GridContainer
var _viewport: Control
var _pager: HBoxContainer
var _previous_button: Button
var _page_label: Label
var _next_button: Button


func configure(entries: Array, selected_id: String, columns: int = 4, node_prefix: String = "Backpack", rows: int = 2) -> void:
	_selected_id = selected_id
	_entries = entries.duplicate(true)
	_columns = maxi(1, columns)
	_rows = maxi(1, rows)
	_node_prefix = node_prefix
	name = "EquipmentBackpack"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 4)

	_viewport = Control.new()
	_viewport.name = "EquipmentBackpackViewport"
	_viewport.custom_minimum_size = Vector2(0, float(_rows) * CELL_SIZE.y + float(_rows - 1) * CELL_GAP)
	_viewport.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_viewport.clip_contents = true
	_viewport.mouse_filter = Control.MOUSE_FILTER_STOP
	_viewport.gui_input.connect(_on_viewport_input)
	_viewport.resized.connect(_layout_grid)
	add_child(_viewport)

	_grid = GridContainer.new()
	_grid.name = "EquipmentBackpackCells"
	_grid.columns = _columns
	_grid.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", CELL_GAP)
	_grid.add_theme_constant_override("v_separation", CELL_GAP)
	_viewport.add_child(_grid)

	_pager = HBoxContainer.new()
	_pager.name = "EquipmentBackpackPager"
	_pager.custom_minimum_size.y = PAGER_HEIGHT
	_pager.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pager.add_theme_constant_override("separation", 6)
	add_child(_pager)
	_previous_button = Button.new()
	_previous_button.name = "BackpackPreviousPage"
	_previous_button.text = "<" if _columns == 2 else "上页"
	_previous_button.tooltip_text = "上一页"
	_previous_button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_previous_button.custom_minimum_size.x = 32.0 if _columns == 2 else 72.0
	_previous_button.focus_mode = Control.FOCUS_ALL
	_previous_button.pressed.connect(_change_page.bind(-1))
	_pager.add_child(_previous_button)
	_page_label = Label.new()
	_page_label.name = "BackpackPageLabel"
	_page_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_page_label.add_theme_font_size_override("font_size", 18)
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_page_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_pager.add_child(_page_label)
	_next_button = Button.new()
	_next_button.name = "BackpackNextPage"
	_next_button.text = ">" if _columns == 2 else "下页"
	_next_button.tooltip_text = "下一页"
	_next_button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_next_button.custom_minimum_size.x = 32.0 if _columns == 2 else 72.0
	_next_button.focus_mode = Control.FOCUS_ALL
	_next_button.pressed.connect(_change_page.bind(1))
	_pager.add_child(_next_button)

	var selected_index := _entry_index(_selected_id)
	if selected_index >= 0:
		_page_index = selected_index / _page_capacity()
	_render_page()
	call_deferred("_layout_grid")


func select_item(instance_id: String) -> void:
	_selected_id = instance_id
	for raw_id in _cells:
		var cell := _cells[raw_id] as PanelContainer
		if cell != null:
			cell.add_theme_stylebox_override("panel", _cell_box(String(raw_id) == _selected_id))


func show_item(instance_id: String) -> void:
	var index := _entry_index(instance_id)
	if index < 0:
		return
	var target_page := index / _page_capacity()
	if target_page != _page_index:
		_page_index = target_page
		_render_page()
	select_item(instance_id)


func get_cell(instance_id: String) -> PanelContainer:
	return _cells.get(instance_id, null) as PanelContainer


func inspected_item_id() -> String:
	return _focused_id if not _focused_id.is_empty() else _hovered_id


func page_index() -> int:
	return _page_index


func page_count() -> int:
	return maxi(1, ceili(float(_entries.size()) / float(_page_capacity())))


func set_page(index: int) -> void:
	var target := clampi(index, 0, page_count() - 1)
	if target == _page_index:
		return
	_page_index = target
	_render_page()


func visible_instance_ids() -> Array[String]:
	var ids: Array[String] = []
	for id in _cells:
		ids.append(String(id))
	return ids


func _page_capacity() -> int:
	return _columns * _rows


func _entry_index(instance_id: String) -> int:
	for index in _entries.size():
		var entry: Variant = _entries[index]
		if entry is Dictionary and String((entry as Dictionary).get("instance_id", "")) == instance_id:
			return index
	return -1


func _render_page() -> void:
	if _grid == null:
		return
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.free()
	_cells.clear()
	_hovered_id = ""
	_focused_id = ""
	_page_index = clampi(_page_index, 0, page_count() - 1)
	var first := _page_index * _page_capacity()
	var last := mini(_entries.size(), first + _page_capacity())
	for index in range(first, last):
		var raw_entry: Variant = _entries[index]
		if raw_entry is Dictionary:
			_add_entry(_grid, raw_entry as Dictionary, _node_prefix)
	_previous_button.disabled = _page_index <= 0
	_next_button.disabled = _page_index >= page_count() - 1
	_page_label.text = "%d / %d" % [_page_index + 1, page_count()]
	_pager.visible = page_count() > 1
	page_changed.emit(_page_index, page_count())
	call_deferred("_layout_grid")


func _layout_grid() -> void:
	if _grid == null or _viewport == null:
		return
	_grid.position = Vector2.ZERO
	_grid.size = _viewport.size


func _change_page(offset: int) -> void:
	var target := clampi(_page_index + offset, 0, page_count() - 1)
	if target == _page_index:
		return
	_page_index = target
	_render_page()


func _on_viewport_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not (event as InputEventMouseButton).pressed:
		return
	var mouse_event := event as InputEventMouseButton
	if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
		_change_page(-1)
		accept_event()
	elif mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_change_page(1)
		accept_event()


func _add_entry(grid: GridContainer, entry: Dictionary, node_prefix: String) -> void:
	var instance_id := String(entry.get("instance_id", "")).strip_edges()
	if instance_id.is_empty():
		return
	var token := _stable_token(instance_id)
	var cell := PanelContainer.new()
	cell.name = "BackpackCell_%s" % token
	cell.custom_minimum_size = CELL_SIZE
	cell.add_theme_stylebox_override("panel", _cell_box(instance_id == _selected_id))
	grid.add_child(cell)
	_cells[instance_id] = cell

	var icon_value: Variant = entry.get("icon", null)
	if icon_value is Texture2D:
		var icon_center := CenterContainer.new()
		icon_center.name = "BackpackIconCenter_%s" % token
		icon_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(icon_center)
		var icon := TextureRect.new()
		icon.name = String(entry.get("icon_node_name", "%sIcon_%s" % [node_prefix, token]))
		icon.texture = icon_value as Texture2D
		icon.custom_minimum_size = Vector2(64, 64)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_SCALE
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.set_meta("canonical_id", String(entry.get("canonical_id", "")))
		icon_center.add_child(icon)

	var status := String(entry.get("status_label", ""))
	if not status.is_empty():
		var overlay := Control.new()
		overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(overlay)
		var badge := PanelContainer.new()
		badge.name = "BackpackStatus_%s" % token
		badge.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		badge.offset_top = -24
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var background := StyleBoxFlat.new()
		background.bg_color = Color(0.035, 0.055, 0.075, 0.95)
		badge.add_theme_stylebox_override("panel", background)
		overlay.add_child(badge)
		var label := Label.new()
		label.text = status
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 18)
		label.add_theme_color_override("font_color", Shell.BONE)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.add_child(label)

	var button := Button.new()
	button.name = "BackpackItem_%s" % token
	button.flat = true
	button.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	button.focus_mode = Control.FOCUS_ALL
	button.tooltip_text = String(entry.get("tooltip", entry.get("display_name", "装备")))
	button.mouse_entered.connect(_hover_entered.bind(instance_id))
	button.mouse_exited.connect(_hover_exited.bind(instance_id))
	button.focus_entered.connect(_focus_entered.bind(instance_id))
	button.focus_exited.connect(_focus_exited.bind(instance_id))
	button.pressed.connect(_activate.bind(instance_id))
	cell.add_child(button)


func _inspect(instance_id: String) -> void:
	select_item(instance_id)
	item_inspected.emit(instance_id)


func _hover_entered(instance_id: String) -> void:
	_hovered_id = instance_id
	_inspect(instance_id)


func _hover_exited(instance_id: String) -> void:
	if _hovered_id == instance_id:
		_hovered_id = ""
	if _focused_id.is_empty():
		item_inspected.emit("")


func _focus_entered(instance_id: String) -> void:
	_focused_id = instance_id
	_inspect(instance_id)


func _focus_exited(instance_id: String) -> void:
	if _focused_id == instance_id:
		_focused_id = ""
	if _hovered_id.is_empty():
		item_inspected.emit("")


func _activate(instance_id: String) -> void:
	select_item(instance_id)
	item_inspected.emit(instance_id)
	item_activated.emit(instance_id)


func _cell_box(selected: bool) -> StyleBox:
	var box := Shell.panel_style("selected" if selected else "well")
	box.content_margin_left = 5
	box.content_margin_top = 5
	box.content_margin_right = 5
	box.content_margin_bottom = 5
	return box


func _stable_token(value: String) -> String:
	var token := ""
	for index in value.length():
		var character := value.substr(index, 1)
		var code := character.unicode_at(0)
		var legal := code >= 48 and code <= 57 or code >= 65 and code <= 90 or code >= 97 and code <= 122 or character in ["_", "-"]
		token += character if legal else "_"
	return token
