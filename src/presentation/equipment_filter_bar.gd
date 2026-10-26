extends VBoxContainer
## Inventory display preferences only. Changing a query never equips or destroys
## an item; the host refreshes its results without replacing these input controls.

signal query_changed(query: Dictionary)

const Shell = preload("res://src/presentation/shell_theme.gd")
const Readable = preload("res://src/presentation/player_readable_build.gd")
const UiKit := preload("res://src/presentation/ui_kit.gd")
const SORTS := {"name": "By Name", "highest_tier": "By Highest Affix Tier", "affix_count": "By Affix Count"}

var _query: Dictionary = default_query()
var _families: Dictionary = {}
var _keyword: LineEdit
var _sort: OptionButton
var _toggle: Button
var _reset: Button
var _summary: Label
var _dialog: AcceptDialog
var _family: OptionButton
var _tier: OptionButton
var _flags: Dictionary = {}
var _syncing := false
var _match_count := 0
var _total_count := 0


static func default_query() -> Dictionary:
	return {"keyword": "", "family": "", "min_tier": 0, "requires_rune": false,
		"requires_law": false, "requires_salvage": false, "sort": "name"}


func _init() -> void:
	name = "EquipmentFilterBar"
	theme = Shell.create()
	add_theme_constant_override("separation", 4)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	add_child(row)
	_keyword = LineEdit.new()
	_keyword.name = "CandidateKeywordFilter"
	_keyword.placeholder_text = "Search equipment or affixes"
	_keyword.clear_button_enabled = true
	_keyword.custom_minimum_size = Vector2(150, 36)
	_keyword.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_keyword.add_theme_font_size_override("font_size", 18)
	_keyword.text_changed.connect(func(value: String): _change("keyword", value))
	row.add_child(_keyword)
	_sort = OptionButton.new()
	_sort.name = "CandidateSort"
	_sort.add_theme_font_size_override("font_size", 18)
	for key: String in SORTS:
		_sort.add_item(SORTS[key])
		_sort.set_item_metadata(_sort.item_count - 1, key)
	_sort.item_selected.connect(func(index: int): _change("sort", _sort.get_item_metadata(index)))
	row.add_child(_sort)
	_toggle = _button("Filter", "CandidateFiltersToggle")
	_toggle.pressed.connect(_open_filters)
	row.add_child(_toggle)
	_reset = _button("Reset", "CandidateFiltersReset")
	_reset.tooltip_text = "Clear filters to show all candidates for this slot"
	_reset.pressed.connect(reset_query)
	row.add_child(_reset)
	for control: Control in [_keyword, _sort, _toggle, _reset]:
		for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
			if not control.has_theme_stylebox(state): continue
			var box := control.get_theme_stylebox(state).duplicate() as StyleBox
			box.content_margin_top = 4
			box.content_margin_bottom = 4
			box.content_margin_left = 8
			box.content_margin_right = 8
			control.add_theme_stylebox_override(state, box)
	_summary = Label.new()
	_summary.name = "CandidateFilterSummary"
	_summary.add_theme_font_size_override("font_size", 18)
	_summary.add_theme_color_override("font_color", Shell.NEUTRAL)
	_summary.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_summary)
	_build_dialog()


func configure(query: Dictionary, candidates: Array[Dictionary], families: Dictionary) -> void:
	_query = default_query()
	_query.merge(query, true)
	_families = families.duplicate(true)
	_family.clear()
	_family.add_item("All Affix Families")
	_family.set_item_metadata(0, "")
	var ids: Array[String] = []
	for item in candidates:
		for affix: Dictionary in item.get("affixes", []):
			var id := String(affix.get("family_id", ""))
			if not id.is_empty() and id not in ids:
				ids.append(id)
	ids.sort()
	for id in ids:
		_family.add_item(String(_families.get(id, {}).get("name", "Unknown Affix")))
		_family.set_item_metadata(_family.item_count - 1, id)
	_sync_controls()


func set_result_count(matches: int, total: int) -> void:
	_match_count = matches
	_total_count = total
	_update_summary()


func current_query() -> Dictionary:
	return _query.duplicate(true)


func reset_query() -> void:
	_query = default_query()
	_sync_controls()
	query_changed.emit(current_query())
	if _dialog.visible:
		_family.grab_focus()
	else:
		_keyword.grab_focus()


func _build_dialog() -> void:
	_dialog = AcceptDialog.new()
	_dialog.name = "CandidateFilterDialog"
	_dialog.title = "Filter Same-Slot Equipment"
	_dialog.ok_button_text = "Complete"
	_dialog.theme = Shell.create()
	_dialog.get_label().hide()
	_dialog.confirmed.connect(_restore_focus)
	_dialog.canceled.connect(_restore_focus)
	_dialog.close_requested.connect(_restore_focus)
	add_child(_dialog)
	var margin := MarginContainer.new()
	margin.name = "CandidateFilterControls"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.offset_left = 20
	margin.offset_top = 16
	margin.offset_right = -20
	margin.offset_bottom = -60
	_dialog.add_child(margin)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	margin.add_child(body)
	var note := Label.new()
	note.text = "Only the display changes; equipment and rewards are retained."
	note.add_theme_font_size_override("font_size", 18)
	note.add_theme_color_override("font_color", Shell.NEUTRAL)
	body.add_child(note)
	_family = OptionButton.new()
	_family.name = "CandidateFamilyFilter"
	_family.add_theme_font_size_override("font_size", 22)
	_family.item_selected.connect(func(index: int): _change("family", _family.get_item_metadata(index)))
	body.add_child(_family)
	_tier = OptionButton.new()
	_tier.name = "CandidateMinimumTierFilter"
	_tier.add_theme_font_size_override("font_size", 22)
	for value in range(5):
		_tier.add_item("Any Affix Tier" if value == 0 else "At Least %s Affixes" % Readable.new().tier_label(value))
	_tier.item_selected.connect(func(index: int): _change("min_tier", index))
	body.add_child(_tier)
	for entry in [["requires_rune", "With Rune", "CandidateRuneFilter"], ["requires_law", "With Law", "CandidateLawFilter"], ["requires_salvage", "Salvageable", "CandidateSalvageFilter"]]:
		var check := CheckButton.new()
		check.name = entry[2]
		check.text = entry[1]
		check.add_theme_font_size_override("font_size", 22)
		check.toggled.connect(func(enabled: bool): _change(entry[0], enabled))
		body.add_child(check)
		_flags[entry[0]] = check


func _sync_controls() -> void:
	_syncing = true
	_keyword.text = String(_query.keyword)
	for index in _sort.item_count:
		if _sort.get_item_metadata(index) == _query.sort:
			_sort.select(index)
	_family.select(0)
	for index in _family.item_count:
		if _family.get_item_metadata(index) == _query.family:
			_family.select(index)
	_tier.select(clampi(int(_query.min_tier), 0, 4))
	for key: String in _flags:
		(_flags[key] as CheckButton).set_pressed_no_signal(bool(_query[key]))
	_syncing = false
	_update_summary()


func _change(key: String, value: Variant) -> void:
	if _syncing or _query.get(key) == value:
		return
	_query[key] = value
	_update_summary()
	query_changed.emit(current_query())


func _update_summary() -> void:
	var parts: Array[String] = []
	if not String(_query.keyword).strip_edges().is_empty():
		parts.append("Keyword: %s" % String(_query.keyword).strip_edges())
	if not String(_query.family).is_empty():
		parts.append("Affix family: %s" % String(_families.get(_query.family, {}).get("name", "Unknown Affix")))
	if int(_query.min_tier) > 0:
		parts.append("Minimum tier: %s" % Readable.new().tier_label(int(_query.min_tier)))
	for pair in [["requires_rune", "With Rune"], ["requires_law", "With Law"], ["requires_salvage", "Salvageable"]]:
		if bool(_query[pair[0]]): parts.append(pair[1])
	_toggle.text = "Filter" if parts.is_empty() else "Filters · %d" % parts.size()
	_reset.disabled = parts.is_empty() and _query.sort == "name"
	var filters := "; ".join(parts)
	_summary.text = "%d / %d candidates" % [_match_count, _total_count] + (" · " + filters if not filters.is_empty() else " · No replacement candidates for this slot." if _total_count == 0 else " · Click an item to pin its comparison")
	_summary.tooltip_text = _summary.text + "; sort: " + String(SORTS.get(_query.sort, "By Name")).trim_prefix("By ")
	_toggle.tooltip_text = _summary.tooltip_text


func _open_filters() -> void:
	_dialog.popup_centered_clamped(Vector2i(560, 390), 0.9)
	call_deferred("_focus_control", _family)


func _restore_focus() -> void:
	call_deferred("_focus_control", _toggle)


func _focus_control(control: Control) -> void:
	if is_inside_tree() and is_instance_valid(control) and control.is_inside_tree() and control.is_visible_in_tree():
		control.grab_focus()


func _button(text_value: String, node_name: String) -> Button:
	return UiKit.sized_button(text_value, node_name, 18)
