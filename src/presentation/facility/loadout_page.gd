class_name FacilityLoadoutPage
extends RefCounted

## Loadout page extracted from FacilityScreen. This collaborator owns the legacy
## and real loadout builds, the slot strip and its focus switching, the skill
## summary strip and its detail dialog, the candidate backpack and its shared
## detail pane, and the hero preview report, reaching owner state and
## presentation through the untyped owner reference.
const ShellThemeScript = preload("res://src/presentation/shell_theme.gd")
const FacilityArtScript = preload("res://src/presentation/facility_art.gd")
const FacilityLayoutScript = preload("res://src/presentation/facility_layout.gd")
const LoadoutCharacterViewScript = preload("res://src/presentation/loadout_character_view.gd")
const EquipmentBackpackGridScript = preload("res://src/presentation/equipment_backpack_grid.gd")
const EquipmentFilterBarScript = preload("res://src/presentation/equipment_filter_bar.gd")
const PlayerReadableBuildScript = preload("res://src/presentation/player_readable_build.gd")
const UiKit := preload("res://src/presentation/ui_kit.gd")
const FacilityItemText := preload("res://src/presentation/facility/item_text.gd")

## Two authored skill lines plus a 32px icon need this much logical lane width
## before a two-column grid is safe. Narrow windows stack the four actions in one
## column inside the existing local scroll region instead of widening that region.
const LOADOUT_SKILL_TWO_COLUMN_REGION_MIN_WIDTH := 360.0

var _screen


func _init(screen) -> void:
	_screen = screen


func _build_loadout() -> void:
	if _has_real_loadout_data():
		_build_real_loadout()
		return
	_build_legacy_loadout()


func _build_legacy_loadout() -> void:
	var builds := UiKit.as_array(_screen._facility_data.get("available_builds", []))
	var active_data := UiKit.as_dictionary(_screen._facility_data.get("active_build", {}))
	var active_id := String(active_data.get("id", active_data.get("preset_id", "")))
	var rendered := 0
	for value in builds:
		if not value is Dictionary:
			continue
		var build: Dictionary = value
		var preset_id := String(build.get("id", "")).strip_edges()
		if preset_id.is_empty():
			continue
		var selected := bool(build.get("selected", false)) or preset_id == active_id
		var verified := bool(build.get("verified", false))
		var display_name := FacilityItemText.build_display_name(build, rendered, verified)
		var title := "%s%s" % ["[Current Kit] " if selected else "", display_name]
		var p_text := FacilityItemText.format_value(build.get("p", FacilityItemText.nested_value(build, ["parameters", "p"], "Unknown")))
		var conclusion := "Unverified"
		if verified:
			conclusion = String(build.get("state", build.get("growth_state", build.get("conclusion", build.get("verified_growth_name", "Verified")))))
		var body := "Continuation Chance: %s\nGrowth Conclusion: %s\nSkill: %s\nRune: %s\nLaw: %s\nEquipment Affixes / Calibration: %s" % [
			p_text,
			conclusion,
			FacilityItemText.component_text(build, "skill", "Piercing Arrow"),
			FacilityItemText.component_text(build, "rune", "Breeding Split"),
			FacilityItemText.component_text(build, "law", "Pack Hunt Mark"),
			FacilityItemText.equipment_text(build),
		]
		_screen._add_card(title, body, "BuildCard_%s" % preset_id)
		_screen._add_payload_action("Select %s" % display_name, "select_ranger_build", {"preset_id": preset_id}, "SelectBuild_%s" % preset_id)
		# The calibration presets name their skill, rune and law; each one that the
		# icon batch publishes gets its own cell beside the card it belongs to.
		var card: Node = _screen.find_child("BuildCard_%s" % preset_id, true, false)
		if card != null:
			_screen._add_icon_row(card, [
				_screen._art.canonical_id("rune", FacilityItemText.component_id(build, "rune")),
				_screen._art.canonical_id("law", FacilityItemText.component_id(build, "law")),
			], "LegacyBuildIcon")
		rendered += 1
	if rendered == 0:
		_screen._add_card("Build data unavailable", "No valid kit is available; p, component stats, and verification results remain unknown.", "BuildDataUnavailable")


func _has_real_loadout_data() -> bool:
	for key in ["equipment_slots", "prototype_open_slots", "inventory_equipment", "base_items", "affix_families", "active_build", "resolved_build"]:
		if not _screen._facility_data.has(key):
			return false
	var equipment_slots := UiKit.as_array(_screen._facility_data.get("equipment_slots", []))
	var open_slots := UiKit.as_array(_screen._facility_data.get("prototype_open_slots", []))
	var active := UiKit.as_dictionary(_screen._facility_data.get("active_build", {}))
	return equipment_slots.size() == 12 \
		and open_slots.size() == 4 \
		and _screen._facility_data.get("inventory_equipment") is Array \
		and _screen._facility_data.get("base_items") is Dictionary \
		and _screen._facility_data.get("affix_families") is Dictionary \
		and active.get("equipped_item_ids") is Dictionary \
		and _screen._facility_data.get("resolved_build") is Dictionary


func _build_real_loadout() -> void:
	var slots := UiKit.as_array(_screen._facility_data.get("equipment_slots", []))
	var open := UiKit.as_array(_screen._facility_data.get("prototype_open_slots", []))
	var active := UiKit.as_dictionary(_screen._facility_data.get("active_build", {}))
	var equipped := UiKit.as_dictionary(active.get("equipped_item_ids", {}))
	var inventory := UiKit.as_array(_screen._facility_data.get("inventory_equipment", []))
	_normalize_focus_slot(open)
	var stage := Control.new()
	stage.name = "LoadoutConceptRoot"
	stage.custom_minimum_size = Vector2(_screen._layout_frame.x, maxf(570,_screen._layout_frame.y))
	stage.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen._cards.add_child(stage)
	_screen._facility_root = stage
	var regions := FacilityLayoutScript.loadout_regions(Vector2(_screen._layout_frame.x,maxf(570,_screen._layout_frame.y)))
	var slot_column := _workbench_region(stage,"LoadoutSlotsRegion",regions.slots)
	var left := _workbench_region(stage,"LoadoutLockedRegion",regions.locked)
	var right := _workbench_region(stage,"LoadoutCompareRegion",regions.compare)
	var hero := _workbench_region(stage,"LoadoutHeroRegion",regions.hero)
	slot_column.add_theme_constant_override("separation", 2)
	_build_slot_grid(slot_column, slots, open, equipped, inventory, {})
	var character_note: Label = _screen._note_label("Select a slot to compare and replace equipment in your backpack")
	character_note.name = "LoadoutCharacterDescription"
	slot_column.add_child(character_note)
	_build_loadout_skill_strip(left)
	var locked: VBoxContainer = _screen._section_in(left, "Backpack and Progression", "ClosedEquipmentSlots")
	var locked_style: StyleBoxTexture = _screen._recessed_panel_style("well")
	locked_style.content_margin_top = 4
	locked_style.content_margin_bottom = 4
	_screen._section_panel(locked).add_theme_stylebox_override("panel", locked_style)
	locked.add_theme_constant_override("separation", 2)
	var reason: Label = _screen._note_label("Main Hand · Off Hand · Gloves · Ring\n" + _resolved_build_fact_lines()[1].get_slice("    Class:", 0))
	reason.name = "ClosedSlotReason"
	locked.add_child(reason)
	var slot_reference := Button.new()
	slot_reference.name = "ClosedSlotReferenceToggle"
	slot_reference.text = "All 12 Slots"
	slot_reference.tooltip_text = "View all slots and availability in the popup, without a long table on this page."
	slot_reference.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	slot_reference.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot_reference.pressed.connect(_on_closed_slot_reference_pressed)
	var reference_actions := HBoxContainer.new()
	reference_actions.name = "LoadoutReferenceActions"
	reference_actions.add_theme_constant_override("separation", 6)
	left.add_child(reference_actions)
	slot_reference.text = "Slot Details"
	slot_reference.add_theme_font_size_override("font_size", 18)
	reference_actions.add_child(slot_reference)
	_build_character_column(hero)
	_build_slot_compare(open, equipped, inventory, {"parent":right,"height":regions.compare.size.y})
	_build_loadout_details_entry(reference_actions)

func _workbench_region(stage: Control, node_name: String, rect: Rect2) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = node_name
	scroll.position = rect.position
	scroll.size = rect.size
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ShellThemeScript.hide_passive_scrollbar_chrome(scroll)
	stage.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation",8)
	scroll.add_child(column)
	return column


## The resolved-Build facts are reference data, not the decision: they stay behind
## one labeled toggle below the comparison, so the first screen of the page is the
## slot strip and the current item against its candidates.


## The action catalog starts the lower-left lane, before the locally scrollable
## locked equipment slots. Each equipped skill plus the always-available dodge
## names its binding and real cooldown; opening one description uses a bounded
## dialog, so complete copy never moves the equipment comparison or turns three
## long descriptions into one wall of text.
func _build_loadout_skill_strip(parent: Container) -> void:
	var row := GridContainer.new()
	row.name = "LoadoutSkillStrip"
	var regions := FacilityLayoutScript.loadout_regions(Vector2(_screen._layout_frame.x, maxf(570.0, _screen._layout_frame.y)))
	row.columns = 2 if float((regions.locked as Rect2).size.x) >= LOADOUT_SKILL_TWO_COLUMN_REGION_MIN_WIDTH else 1
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("h_separation", 4)
	parent.add_child(row)
	var skills := UiKit.as_array(UiKit.as_dictionary(_screen._facility_data.get("active_build", {})).get("skills", []))
	while skills.size() < 3:
		skills.append("")
	skills = skills.slice(0, 3)
	skills.append("basic_dodge")
	for index in skills.size():
		var skill_id := String(skills[index]).strip_edges()
		var button := Button.new()
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 48.0
		for state in ["normal", "hover", "pressed", "disabled"]:
			var skin := ShellThemeScript.panel_style("button" if state == "normal" else ("selected" if state == "pressed" else state))
			skin.content_margin_top = 3
			skin.content_margin_bottom = 3
			skin.content_margin_left = 4
			skin.content_margin_right = 4
			button.add_theme_stylebox_override(state, skin)
		# Exactly one authored break: the compact cooldown uses the short seconds
		# token so the icon, binding and value all fit without a third soft-wrapped
		# line in the narrow two-column lane.
		button.autowrap_mode = TextServer.AUTOWRAP_OFF
		button.add_theme_font_size_override("font_size", 18)
		button.focus_mode = Control.FOCUS_ALL
		if skill_id.is_empty():
			button.name = "SkillSummary_empty_%d" % (index + 1)
			button.text = "Slot %d\nLocked" % (index + 1)
			button.disabled = true
			button.tooltip_text = "This skill slot unlocks through the main quest"
			row.add_child(button)
			continue
		var skill := _player_skill_entry(skill_id)
		button.name = "SkillSummary_%s" % UiKit.stable_node_token(skill_id)
		button.text = _screen._compact_skill_text(skill, index + 1)
		button.tooltip_text = "Click to view %s's full targeting, effects, cooldown, synergies, and limits" % String(skill.get("name", "this skill"))
		var texture: Texture2D = _screen._skill_icons.icon(skill_id)
		if texture != null:
			button.icon = texture
			button.expand_icon = false
			button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			button.set_meta("canonical_id", "action.%s" % skill_id)
		button.pressed.connect(_on_skill_summary_pressed.bind(skill_id))
		row.add_child(button)


func _on_skill_summary_pressed(skill_id: String) -> void:
	if _screen._skill_detail_dialog == null:
		return
	var skill := _player_skill_entry(skill_id)
	if skill.is_empty():
		return
	var readable_text: String = _screen._readable_build.format_skill(skill)
	_screen._skill_detail_dialog.title = "Full Skill Details · %s" % String(skill.get("name", "Skill"))
	_screen._skill_detail_dialog.dialog_text = ""
	_screen._skill_detail_text.text = FacilityItemText.skill_detail_paragraphs(readable_text)
	_screen._skill_detail_scroll.scroll_vertical = 0
	_screen._skill_detail_dialog.min_size = Vector2i(760, 500)
	_screen._skill_detail_dialog.size = Vector2i(760, 500)
	_layout_skill_detail_dialog()
	_screen._skill_detail_dialog.popup_centered_clamped(Vector2i(760, 500), 0.9)
	call_deferred("_layout_skill_detail_dialog")


## Keep the complete player-readable description inside the fixed dialog body. The
## title belongs to AcceptDialog's title bar and its close button remains in the
## dialog footer, so only the description can scroll.
func _layout_skill_detail_dialog() -> void:
	if _screen._skill_detail_dialog == null or _screen._skill_detail_scroll == null or _screen._skill_detail_text == null:
		return
	var dialog_size: Vector2 = _screen._skill_detail_dialog.size
	var body_position := Vector2(20.0, 44.0)
	var body_size := Vector2(maxf(0.0, dialog_size.x - 40.0), maxf(0.0, dialog_size.y - 116.0))
	_screen._skill_detail_reading_surface.position = body_position - Vector2(8, 8)
	_screen._skill_detail_reading_surface.size = body_size + Vector2(16, 16)
	_screen._skill_detail_scroll.position = body_position
	_screen._skill_detail_scroll.size = body_size
	# Reserve the scrollbar lane while wrapping. This guarantees that a long key,
	# parameter name or Chinese phrase wraps vertically instead of producing a
	# horizontal overflow.
	_screen._skill_detail_text.custom_minimum_size.x = maxf(0.0, body_size.x - 18.0)
	_screen._skill_detail_text.size.x = _screen._skill_detail_text.custom_minimum_size.x
	call_deferred("_fit_skill_detail_text")


## Label's wrapped height is resolved after it knows the scroll viewport width.
## Feed that resolved height back as the scroll child's minimum so the outer
## ScrollContainer receives a real vertical overflow instead of a clipped label.
func _fit_skill_detail_text() -> void:
	if _screen._skill_detail_scroll == null or _screen._skill_detail_text == null:
		return
	var content_width: float = maxf(0.0, _screen._skill_detail_scroll.size.x - 18.0)
	_screen._skill_detail_text.custom_minimum_size = Vector2(content_width, 0.0)
	_screen._skill_detail_text.size = Vector2(content_width, 0.0)
	var wrapped_height: float = _screen._skill_detail_text.get_minimum_size().y
	_screen._skill_detail_text.custom_minimum_size = Vector2(content_width, wrapped_height)
	_screen._skill_detail_text.size = Vector2(content_width, wrapped_height)


func _player_skill_entry(skill_id: String) -> Dictionary:
	for registry_key in ["early_skill_registry", "skill_registry", "skills"]:
		var entry := UiKit.as_dictionary(UiKit.as_dictionary(_screen._facility_data.get(registry_key, {})).get(skill_id, {}))
		if not entry.is_empty():
			return entry
	return _screen._skill_registry.get_skill(skill_id)



func _build_loadout_details_entry(parent: Container) -> void:
	var toggle := Button.new()
	toggle.name = "LoadoutDetailsToggle"
	toggle.text = "Build Details"
	toggle.add_theme_font_size_override("font_size", 18)
	toggle.tooltip_text = "View final stats, growth classification, and interfaces in a popup; your build stays unchanged."
	toggle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toggle.pressed.connect(_on_loadout_details_reference_pressed)
	parent.add_child(toggle)


func _on_loadout_details_reference_pressed() -> void:
	var lines := _resolved_build_fact_lines()
	var active := UiKit.as_dictionary(_screen._facility_data.get("active_build", {}))
	for kind in ["runes", "laws"]:
		for value in UiKit.as_array(active.get(kind, [])):
			lines.append(_player_modifier_name(FacilityItemText.display_value(value)))
	_screen._show_item_detail("Build Reference", "\n".join(lines), _screen.get_action_button("LoadoutDetailsToggle"))
	_screen._item_detail_dialog.title = "Build Details"


func _on_closed_slot_reference_pressed() -> void:
	if _screen._item_detail_dialog == null or _screen._item_detail_dialog_text == null:
		return
	var slots := UiKit.as_array(_screen._facility_data.get("equipment_slots", []))
	var open := UiKit.as_array(_screen._facility_data.get("prototype_open_slots", []))
	var lines: Array[String] = ["All 12 Slot States"]
	for raw_slot in slots:
		var slot := String(raw_slot)
		lines.append("%s: %s" % [_slot_title(slot), "Available" if slot in open else "Unavailable"])
	_screen._show_item_detail("Slot Reference", "\n".join(lines), _screen.get_action_button("ClosedSlotReferenceToggle"))
	_screen._item_detail_dialog.title = "All Slot Details"


## Readable reference facts for the complete build dialog. Growth classification
## is revealed only by a training report for the current build fingerprint.
func _resolved_build_fact_lines() -> Array[String]:
	var resolved := UiKit.as_dictionary(_screen._facility_data.get("resolved_build", {}))
	var parameters := UiKit.as_dictionary(resolved.get("final_parameters", {}))
	var parameter_lines: Array[String] = []
	for parameter in PlayerReadableBuildScript.PARAMETER_ORDER:
		parameter_lines.append(_screen._readable_build.format_parameter(parameter, parameters.get(parameter, null)))
	var fingerprint := String(resolved.get("build_fingerprint", ""))
	var training := UiKit.as_dictionary(_screen._facility_data.get("training", {}))
	var classification := "Unverified"
	var report := FacilityItemText.matched_training_report(training, fingerprint)
	if not report.is_empty():
		var reported := String(report.get("state", "")).strip_edges()
		if not reported.is_empty():
			classification = reported
	classification = String(_screen.TRAINING_GROWTH_NAMES.get(classification, classification))
	return [
		"Final Stats: " + "  ·  ".join(parameter_lines),
		"Growth Classification: %s    Class: %s" % [classification, String({"ranger":"Ranger", "alchemist":"Alchemist", "mage":"Mage"}.get(String(_screen._profile.get("initial_class", "")), "Not Created"))],
		"Connected Interfaces: %s" % FacilityItemText.resolved_interface_facts_text(resolved.get("connected_interfaces", [])),
		"Missing Interfaces: %s" % FacilityItemText.resolved_interface_facts_text(resolved.get("missing_interfaces", [])),
	]


## The formal 12-slot state as one grid, in the published table's own order: the four
## open slots carry their equipped base, their real state word and their focus
## control, the locked ones keep their outline, their published Chinese name and their
## lock reason and offer no action at all. The two groups are laid out where the
## approved cell puts them: the open slots form the first row of the page, and the
## locked remainder is a compact grid of one-line cells below the decision. The grid
## works out how many columns it needs from the frame the page froze, so a 1024-wide
## frame stacks the strip instead of shrinking a cell below the 64px icon display.
func _build_slot_grid(parent: Container, equipment_slots: Array, open_slots: Array, equipped_ids: Dictionary, inventory: Array, _composition: Dictionary) -> void:
	var section: VBoxContainer = _screen._section_in(parent, "", "OpenSlotStrip")
	var row := GridContainer.new()
	row.name = "OpenSlotRow"
	row.columns = 4
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("h_separation", 4)
	section.add_child(row)
	for raw_slot in open_slots:
		var slot := String(raw_slot)
		if slot in equipment_slots:
			row.add_child(_slot_cell(slot,equipped_ids,inventory,true,0,0))


func _slot_cell(slot: String, equipped_ids: Dictionary, inventory: Array, _open_slot: bool, _cell_width: int, _cell_height: int) -> PanelContainer:
	var item: Dictionary = _screen._inventory_item_by_id(inventory, String(equipped_ids.get(slot,"")))
	var focused: bool = slot == _screen._focus_slot
	var token := UiKit.stable_node_token(slot)
	var cell := PanelContainer.new()
	cell.name = "LoadoutSlotCell_" + token
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.add_theme_stylebox_override("panel", _screen._slot_cell_box(focused,item.is_empty()))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",2)
	cell.add_child(column)
	var title: Label = _screen._note_label(_slot_title(slot))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	var canonical: String = _screen._art.canonical_id("equipment_slot",slot) if item.is_empty() else _screen._art.canonical_id("equipment_base",String(item.get("base_item_id","")))
	var texture: Texture2D = _screen._body_icon_texture(canonical)
	if texture != null:
		var icon: TextureRect = _screen._icon_node(texture,FacilityArtScript.ICON_NATIVE_SIZE,true)
		icon.name = "SlotIcon_" + token
		icon.set_meta("canonical_id",canonical)
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		column.add_child(icon)
	var state: Label = _screen._note_label("Unequipped" if item.is_empty() else "Equipped")
	state.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(state)
	var button := Button.new()
	button.name = "SlotFocus_" + token
	button.flat = true
	button.tooltip_text = "Current Comparison" if focused else "Compare With" + _slot_title(slot)
	button.pressed.connect(_on_slot_focus_pressed.bind(slot))
	cell.add_child(button)
	return cell


func _build_slot_compare(open_slots: Array, equipped_ids: Dictionary, inventory: Array, composition: Dictionary) -> void:
	var section: VBoxContainer = _screen._section_in(composition.get("parent", _screen._cards), "", "SlotCompareSection")
	_screen._section_panel(section).add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	if _screen._focus_slot.is_empty() or _screen._focus_slot not in open_slots:
		section.add_child(_screen._note_label("No available slots on this page can be compared."))
		return
	var candidates_panel: VBoxContainer = _screen._section_in(section, "Equipment Backpack · %s" % _slot_title(_screen._focus_slot), "CandidateListPanel_%s" % UiKit.stable_node_token(_screen._focus_slot))
	var panel_style := _screen._section_panel(candidates_panel).get_theme_stylebox("panel").duplicate() as StyleBox
	panel_style.content_margin_top = 6
	panel_style.content_margin_bottom = 6
	_screen._section_panel(candidates_panel).add_theme_stylebox_override("panel", panel_style)
	candidates_panel.add_theme_constant_override("separation", 4)
	var alternatives := _same_slot_candidates(_screen._focus_slot, String(equipped_ids.get(_screen._focus_slot, "")), inventory)
	_build_candidate_filters(candidates_panel, alternatives)
	_screen._candidate_results = VBoxContainer.new()
	_screen._candidate_results.name = "CandidateResults"
	_screen._candidate_results.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	candidates_panel.add_child(_screen._candidate_results)
	_refresh_candidate_results()


func _refresh_candidate_results() -> void:
	if not is_instance_valid(_screen._candidate_results):
		return
	UiKit.clear_children(_screen._candidate_results)
	_screen._loadout_backpack_detail = null
	_screen._loadout_backpack_detail_region = null
	_screen._loadout_empty_hint = null
	_screen._loadout_detail_pointer_inside = false
	_screen._loadout_backpack_items = []
	var active := UiKit.as_dictionary(_screen._facility_data.get("active_build", {}))
	var equipped_id := String(UiKit.as_dictionary(active.get("equipped_item_ids", {})).get(_screen._focus_slot, ""))
	var inventory := UiKit.as_array(_screen._facility_data.get("inventory_equipment", []))
	var current: Dictionary = _screen._inventory_item_by_id(inventory, equipped_id)
	var all_alternatives := _same_slot_candidates(_screen._focus_slot, equipped_id, inventory)
	var alternatives := _filter_sort_candidates(all_alternatives)
	_screen._candidate_filter_bar.set_result_count(alternatives.size(), all_alternatives.size())
	if current.is_empty() and alternatives.is_empty():
		_screen._candidate_results.add_child(_screen._note_label("No candidates match. Click Reset to view all." if not all_alternatives.is_empty() else "No replacement candidates for this slot."))
		return
	# Inventory density lives in one icon grid. Hover, keyboard focus, and controller
	# focus all select the same one-item detail pane, so long prose is instantiated
	# once rather than once per inventory item.
	_screen._loadout_backpack_items = []
	if not current.is_empty():
		_screen._loadout_backpack_items.append(current.duplicate(true))
	_screen._loadout_backpack_items.append_array(alternatives.duplicate(true))
	_screen._loadout_backpack_equipped_id = equipped_id
	if not _screen._loadout_backpack_pinned_id.is_empty() and _screen._inventory_item_by_id(_screen._loadout_backpack_items, _screen._loadout_backpack_pinned_id).is_empty():
		_screen._loadout_backpack_pinned_id = ""
	_screen._loadout_backpack_selection = _screen._loadout_review_instance_id if not _screen._inventory_item_by_id(_screen._loadout_backpack_items, _screen._loadout_review_instance_id).is_empty() else _screen._loadout_backpack_pinned_id
	var backpack_row: HBoxContainer = _screen._make_row("CandidateBackpackRow")
	# Keep pointer travel from an icon into its shared action pane continuous.
	backpack_row.add_theme_constant_override("separation", 0)
	_screen._candidate_results.add_child(backpack_row)
	var backpack := EquipmentBackpackGridScript.new()
	# Give the comparison most of the width; larger windows add one icon column.
	var backpack_columns: int = 3 if _screen._layout_frame.x >= 1400.0 else 2
	var backpack_width := float(backpack_columns * 76 + (backpack_columns - 1) * 6)
	backpack.custom_minimum_size.x = backpack_width
	var initial_backpack_id: String = _screen._loadout_backpack_selection if not _screen._loadout_backpack_selection.is_empty() else equipped_id
	backpack.configure(_screen._backpack_entries(_screen._loadout_backpack_items, "CandidateBackpackIcon"), initial_backpack_id, backpack_columns, "CandidateBackpack", 2)
	# configure() gives the reusable picker expand/fill defaults; override them only
	# after configuration so this lane stays at its measured grid width.
	backpack.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	backpack.item_inspected.connect(_on_loadout_backpack_inspected)
	backpack.item_activated.connect(_on_loadout_backpack_activated)
	backpack_row.add_child(backpack)
	_screen._loadout_empty_hint = VBoxContainer.new()
	_screen._loadout_empty_hint.name = "BackpackInspectionHint"
	_screen._loadout_empty_hint.alignment = BoxContainer.ALIGNMENT_CENTER
	_screen._loadout_empty_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_screen._loadout_empty_hint.custom_minimum_size.y = 246
	var hint_title: Label = _screen._body_label("No Matching Candidates" if alternatives.is_empty() and not all_alternatives.is_empty() else "Choose a piece of loot to see what it changes")
	hint_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_screen._loadout_empty_hint.add_child(hint_title)
	var hint_note: Label = _screen._note_label("Click Reset to view all\nEquipped items can still be inspected" if alternatives.is_empty() and not all_alternatives.is_empty() else "Hover to inspect · Click to pin comparison\nReview both gains and costs before equipping")
	hint_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_screen._loadout_empty_hint.add_child(hint_note)
	backpack_row.add_child(_screen._loadout_empty_hint)
	_screen._loadout_backpack_detail_region = Control.new()
	_screen._loadout_backpack_detail_region.name = "BackpackDetail"
	_screen._loadout_backpack_detail_region.custom_minimum_size = Vector2(0, 246)
	_screen._loadout_backpack_detail_region.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_screen._loadout_backpack_detail_region.clip_contents = true
	_screen._loadout_backpack_detail_region.mouse_entered.connect(_on_loadout_detail_mouse_entered)
	_screen._loadout_backpack_detail_region.mouse_exited.connect(_on_loadout_detail_mouse_exited)
	backpack_row.add_child(_screen._loadout_backpack_detail_region)
	_screen._loadout_backpack_detail = VBoxContainer.new()
	_screen._loadout_backpack_detail.name = "BackpackDetailContent"
	_screen._loadout_backpack_detail.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen._loadout_backpack_detail.offset_left = 8.0
	_screen._loadout_backpack_detail.offset_top = 4.0
	_screen._loadout_backpack_detail.offset_right = -8.0
	_screen._loadout_backpack_detail.offset_bottom = -4.0
	_screen._loadout_backpack_detail_region.add_child(_screen._loadout_backpack_detail)
	if _screen._loadout_backpack_selection.is_empty():
		_screen._loadout_backpack_detail_region.visible = false
	else:
		_render_loadout_backpack_detail(_screen._loadout_backpack_selection)


func _on_loadout_backpack_inspected(instance_id: String) -> void:
	if instance_id.is_empty():
		# Focus transfer from an inventory cell to an action in the shared detail
		# pane settles after the cell's focus_exited signal. Decide on the next idle
		# turn so moving toward "Full Details" does not destroy the button mid-click.
		call_deferred("_finish_loadout_backpack_exit")
		return
	if instance_id == _screen._loadout_backpack_selection:
		_render_loadout_backpack_detail(instance_id)
		return
	_screen._loadout_backpack_selection = instance_id
	_render_loadout_backpack_detail(instance_id)


func _on_loadout_backpack_activated(instance_id: String) -> void:
	if _screen._inventory_item_by_id(_screen._loadout_backpack_items, instance_id).is_empty():
		return
	_screen._loadout_backpack_pinned_id = instance_id
	_screen._loadout_backpack_selection = instance_id
	_render_loadout_backpack_detail(instance_id)


func _on_loadout_detail_mouse_entered() -> void:
	_screen._loadout_detail_pointer_inside = true


func _on_loadout_detail_mouse_exited() -> void:
	_screen._loadout_detail_pointer_inside = false
	call_deferred("_finish_loadout_backpack_exit")


func _finish_loadout_backpack_exit() -> void:
	if _screen._item_detail_dialog != null and _screen._item_detail_dialog.visible:
		return
	if _screen._loadout_detail_pointer_inside:
		return
	var focus_owner: Control = _screen.get_viewport().gui_get_focus_owner() if _screen.get_viewport() != null else null
	if focus_owner != null and _screen._loadout_backpack_detail_region != null \
		and (_screen._loadout_backpack_detail_region == focus_owner or _screen._loadout_backpack_detail_region.is_ancestor_of(focus_owner)):
		return
	var backpack: Node = _screen.find_child("EquipmentBackpack", true, false)
	if backpack != null and backpack.has_method("inspected_item_id") \
		and not String(backpack.call("inspected_item_id")).is_empty():
		return
	if not _screen._loadout_backpack_pinned_id.is_empty() \
		and not _screen._inventory_item_by_id(_screen._loadout_backpack_items, _screen._loadout_backpack_pinned_id).is_empty():
		_screen._loadout_backpack_selection = _screen._loadout_backpack_pinned_id
		if backpack != null and backpack.has_method("select_item"):
			backpack.call("select_item", _screen._loadout_backpack_pinned_id)
		_render_loadout_backpack_detail(_screen._loadout_backpack_pinned_id)
		return
	_screen._loadout_backpack_selection = ""
	if backpack != null and backpack.has_method("select_item"):
		backpack.call("select_item", _screen._loadout_backpack_equipped_id)
	_render_loadout_backpack_detail("")


func _render_loadout_backpack_detail(instance_id: String) -> void:
	if _screen._loadout_backpack_detail == null or not is_instance_valid(_screen._loadout_backpack_detail):
		return
	UiKit.clear_children(_screen._loadout_backpack_detail)
	var item: Dictionary = _screen._inventory_item_by_id(_screen._loadout_backpack_items, instance_id)
	if is_instance_valid(_screen._loadout_empty_hint):
		_screen._loadout_empty_hint.visible = item.is_empty()
	if item.is_empty():
		if _screen._loadout_backpack_detail_region != null:
			_screen._loadout_backpack_detail_region.visible = false
		return
	if _screen._loadout_backpack_detail_region != null:
		_screen._loadout_backpack_detail_region.visible = true
	if instance_id == _screen._loadout_backpack_equipped_id:
		_add_current_item_backpack_detail(item)
	else:
		_add_candidate_block(_screen._loadout_backpack_detail, item)
	_screen._track_backpack_detail_actions(_screen._loadout_backpack_detail_region, "loadout")


func _add_current_item_backpack_detail(item: Dictionary) -> void:
	var instance_id := String(item.get("instance_id", ""))
	var slot := String(item.get("slot", _screen._focus_slot))
	var token := UiKit.stable_node_token(instance_id)
	var title: Label = _screen._body_label("Equipped · %s" % _screen._item_display_name(item))
	title.name = "BackpackDetailName"
	_screen._loadout_backpack_detail.add_child(title)
	var summary: Label = _screen._note_label(_item_inline_summary_text(item))
	summary.name = "CurrentItemSummary_%s" % UiKit.stable_node_token(slot)
	summary.add_theme_color_override("font_color", ShellThemeScript.BONE)
	_screen._loadout_backpack_detail.add_child(summary)
	var actions: HBoxContainer = _screen._make_row("BackpackActions")
	_screen._loadout_backpack_detail.add_child(actions)
	_screen._action_button(actions, "Unequip", "unequip_item", {"slot": slot}, "Unequip_%s" % UiKit.stable_node_token(slot))
	_screen._add_full_item_detail_button(
		actions,
		item,
		"Equipped · %s" % _screen._item_display_name(item),
		_item_summary_text(item, true)
	)
	var salvage := _salvage_action_for(item, instance_id)
	if not salvage.is_empty():
		var salvage_button := Button.new()
		salvage_button.name = "Salvage_%s" % token
		salvage_button.text = "Salvage and Unequip (%s x%d)" % [String(salvage.get("label", "")), int(salvage.get("amount", 0))]
		salvage_button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		salvage_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		salvage_button.pressed.connect(_on_salvage_pressed.bind(
			instance_id,
			_salvage_item_identity(item),
			String(salvage.get("operation", "")),
			int(salvage.get("amount", 0)),
			slot
		))
		# Destructive work gets its own full-width secondary row. It must never make
		# Unequip or complete details collapse into three wrapped columns.
		_screen._loadout_backpack_detail.add_child(salvage_button)


## The hero who wears the compared equipment stands beside the slot grid, so the page
## answers "who is this for" without leaving the first screen — the same place cell
## 03 of the approved concept sheet puts him. The frame is the ranger's own published
## one; the caption names the clip, the cell and the integer display multiple in
## words, and says plainly that this is the hero body rather than a paper doll whose
## appearance follows the equipped items. No second class is offered or drawn.
func _build_character_column(parent: Container) -> void:
	var content: VBoxContainer = _screen._section_in(parent, "", "LoadoutCharacterPanel")
	content.add_theme_constant_override("separation", 0)
	var box := StyleBoxEmpty.new()
	_screen._section_panel(content).add_theme_stylebox_override("panel",box)
	var row: HBoxContainer = _screen._make_row("LoadoutCharacterRow")
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_child(row)
	var view := LoadoutCharacterViewScript.new()
	view.name = "LoadoutCharacterPortrait"
	view.refresh()
	view.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(view)
	_screen._character_view = view
	# The full identity copy remains with the open equipment slots, where it is
	# visible without reducing the authored portrait cell.
	view.tooltip_text = "Current Ranger · White Hood · Longbow and Backpack\nEquipment changes stats, not the current appearance."
	view.mouse_filter = Control.MOUSE_FILTER_STOP
	var caption: Label = _screen._note_label("Current Ranger · White Hood\nLongbow and Backpack · Fixed Appearance")
	caption.name = "LoadoutCharacterCaption"
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.visible = false
	content.add_child(caption)


func character_preview_report() -> Dictionary:
	if _screen._character_view == null:
		return {"present": false, "drawing": false, "notes": ["the loadout page built no hero preview"]}
	var report: Dictionary = _screen._character_view.frame_report()
	report["present"] = true
	return report


func _add_candidate_block(parent: Container, item: Dictionary) -> void:
	var instance_id := String(item.get("instance_id", ""))
	var token := UiKit.stable_node_token(instance_id)
	var cell := PanelContainer.new()
	cell.name = "CandidateCell_%s" % token
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cell.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	parent.add_child(cell)
	var content := VBoxContainer.new()
	## Two-point vertical gaps: the standard candidate block (name, actions,
	## comparison and all three fact lines) must clear the fixed pane at 720p
	## without shrinking the 18px fact text.
	content.add_theme_constant_override("separation", 2)
	cell.add_child(content)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	content.add_child(header)
	var headline := HBoxContainer.new()
	headline.name = "CandidateHeadline_%s" % token
	headline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	headline.add_theme_constant_override("separation", 8)
	header.add_child(headline)
	var name_label: Label = _screen._body_label(_screen._item_display_name(item))
	name_label.name = "CandidateName_%s" % token
	headline.add_child(name_label)
	if instance_id == _screen._loadout_review_instance_id:
		var located: Label = _screen._note_label("This Run's Drop · Located")
		located.name = "ReviewedDrop_%s" % token
		located.add_theme_color_override("font_color", ShellThemeScript.AMBER)
		headline.add_child(located)
	var preview_state_text := _candidate_preview_state_text(item)
	var preview_summary: Label = _screen._note_label("Verified" if preview_state_text.begins_with("Sacred Law Preview: Verified") else "Unverified")
	preview_summary.name = "CandidatePreviewStateSummary_%s" % token
	preview_summary.tooltip_text = preview_state_text
	preview_summary.size_flags_horizontal = Control.SIZE_SHRINK_END
	preview_summary.custom_minimum_size.x = 112.0
	preview_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	headline.add_child(preview_summary)
	var actions: HBoxContainer = _screen._make_row("BackpackActions")
	content.add_child(actions)
	var equip: Button = _screen._action_button(actions, "Equip", "equip_item", {"instance_id": instance_id}, "Equip_%s" % token)
	equip.tooltip_text = "Equip and Apply · " + _screen._item_display_name(item)
	var decision_text := _candidate_decision_text(instance_id)
	var preview := _equip_preview_data(instance_id)
	_screen._add_interface_changes(content, preview)
	var comparison_scroll := ScrollContainer.new()
	comparison_scroll.name = "CandidateFactsRow_%s" % token
	## Sized to the 246px detail pane after the name and action rows: the standard
	## three-line facts block fits, longer rune/law rows scroll deliberately, and
	## the container takes keyboard focus so the arrows reach the overflow. Font
	## sizes stay at the published 18px floor.
	comparison_scroll.custom_minimum_size.y = 78
	comparison_scroll.focus_mode = Control.FOCUS_ALL
	comparison_scroll.follow_focus = true
	comparison_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	comparison_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(comparison_scroll)
	var comparison_body := VBoxContainer.new()
	comparison_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	comparison_scroll.add_child(comparison_body)
	var comparison = preload("res://src/presentation/equipment_comparison.gd").new()
	comparison.name = "CandidateDecision_%s" % token
	comparison.tooltip_text = decision_text
	comparison.present(_screen._facility_data.resolved_build.final_parameters, _equip_preview_data(instance_id).get("final_parameters", {}))
	comparison_body.add_child(comparison)
	var summary: Label = _screen._note_label(_candidate_inline_item_facts(item))
	summary.name = "CandidateSummary_%s" % token
	comparison_body.add_child(summary)
	var detail_text := "%s\n\nEquipment Conclusion\n%s\n\nSacred Law Preview\n%s\n%s" % [
		_item_summary_text(item, true),
		decision_text,
		preview_state_text,
		_equip_preview_text(instance_id),
	]
	var full_detail: Button = _screen._add_full_item_detail_button(actions, item, _screen._item_display_name(item), detail_text)
	# The shared pane already establishes that this is equipment. The shorter label
	# keeps all three candidate actions on one readable line at 1280x720; the dialog
	# title and tooltip still use the complete wording.
	full_detail.text = "Details"
	var salvage := _salvage_action_for(item, instance_id)
	if not salvage.is_empty():
		var salvage_button := Button.new()
		salvage_button.name = "Salvage_%s" % token
		salvage_button.text = "Salvage ×%d" % int(salvage.get("amount", 0))
		salvage_button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		salvage_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		salvage_button.tooltip_text = "Salvage into %s x%d" % [String(salvage.get("label", "")), int(salvage.get("amount", 0))]
		salvage_button.pressed.connect(_on_salvage_pressed.bind(
			instance_id,
			_salvage_item_identity(item),
			String(salvage.get("operation", "")),
			int(salvage.get("amount", 0))
		))
		# Candidate actions share one row. The amount stays on the button and the full
		# yield stays in its tooltip, preventing a fourth vertical block from falling
		# below the 246px first-screen surface at 1280x720.
		actions.add_child(salvage_button)


## Sacred Law Preview is a state word, not a promise: a classification only appears when the
## candidate's own fingerprint has passed the test range.
func _candidate_preview_state_text(item: Dictionary) -> String:
	var preview := _equip_preview_data(String(item.get("instance_id", "")))
	if preview.is_empty():
		return "Sacred Law Preview: Unverified (no preview data for this candidate)"
	var fingerprint := String(preview.get("build_fingerprint", "")).strip_edges()
	var training := UiKit.as_dictionary(_screen._facility_data.get("training", {}))
	var report := FacilityItemText.matched_training_report(training, fingerprint)
	if not report.is_empty():
		var classification := String(report.get("state", "")).strip_edges()
		var readable_classification := String(_screen.TRAINING_GROWTH_NAMES.get(classification, classification if not classification.is_empty() else "Unknown"))
		return "Sacred Law Preview: Verified · Growth classification %s" % readable_classification
	return "Sacred Law Preview: Unverified (this build has not passed Training; unknown does not mean failure)"


func _same_slot_candidates(slot: String, equipped_id: String, inventory: Array) -> Array[Dictionary]:
	return _screen._equipment_model.same_slot_candidates(slot, equipped_id, inventory)


func _build_candidate_filters(parent: Container, candidates: Array[Dictionary]) -> void:
	_screen._candidate_filter_bar = EquipmentFilterBarScript.new()
	parent.add_child(_screen._candidate_filter_bar)
	_screen._candidate_filter_bar.configure(_screen._candidate_query, candidates, UiKit.as_dictionary(_screen._facility_data.get("affix_families", {})))
	_screen._candidate_filter_bar.query_changed.connect(_on_candidate_query_changed)


func _filter_sort_candidates(candidates: Array[Dictionary]) -> Array[Dictionary]:
	var query: Dictionary = _screen._candidate_query.duplicate(true)
	query["reviewed_instance_id"] = _screen._loadout_review_instance_id
	return _screen._equipment_model.filter_sort(candidates, query)


func _on_candidate_query_changed(query: Dictionary) -> void:
	_screen._candidate_query = query.duplicate(true)
	# The filter controls stay alive: typing, caret position and an open filter
	# window survive while only the inventory results are refreshed.
	_refresh_candidate_results()


## The formal 12-slot table minus the four open ones: a lock line each and one
## shared reason. No action, no icon, and never the word Unequipped.
## Rune/law row: the shared formatter owns all player-facing names and semantics.


## Switching the compared slot is presentation state: it rebuilds the page and
## emits nothing, so no equip/unequip request can be triggered by looking.
func _on_slot_focus_pressed(slot: String) -> void:
	if slot.is_empty() or slot == _screen._focus_slot:
		return
	var active := UiKit.as_dictionary(_screen._facility_data.get("active_build", {}))
	var equipped_ids := UiKit.as_dictionary(active.get("equipped_item_ids", {}))
	var inventory := UiKit.as_array(_screen._facility_data.get("inventory_equipment", []))
	var candidates := _same_slot_candidates(slot, String(equipped_ids.get(slot, "")), inventory)
	if not String(_screen._candidate_query.family).is_empty() and not _candidate_family_exists(candidates, String(_screen._candidate_query.family)):
		_screen._candidate_query.family = ""
	_screen._loadout_review_instance_id = ""
	_screen._loadout_backpack_pinned_id = ""
	_screen._loadout_backpack_selection = ""
	_screen._focus_slot = slot
	# The candidates of the new slot are a different list: they start at their own first
	# row, and only the page's own offset is carried across the rebuild.
	_screen._slot_switch_pending = true
	if _screen._built:
		_screen._apply_presentation()


func _candidate_family_exists(candidates: Array[Dictionary], family_id: String) -> bool:
	for item in candidates:
		for raw_affix in UiKit.as_array(item.get("affixes", [])):
			if raw_affix is Dictionary and String((raw_affix as Dictionary).get("family_id", "")) == family_id:
				return true
	return false


## A freshly opened page starts at the first open slot; a rebuild of the same
## page (after an action, or after switching slots) keeps the player's choice.
func _normalize_focus_slot(open_slots: Array) -> void:
	var slot_ids: Array[String] = []
	for raw_slot in open_slots:
		slot_ids.append(String(raw_slot))
	if slot_ids.is_empty():
		_screen._focus_slot = ""
		return
	if not _screen._loadout_review_instance_id.is_empty() and _screen._focus_slot in slot_ids:
		return
	if _screen._previous_facility == _screen._facility_id and _screen._focus_slot in slot_ids:
		return
	_screen._focus_slot = String(slot_ids[0])


## The upstream equip preview for one candidate, or {} when the snapshot has no
## usable entry for it. Only the authoritative preview payload passes: the screen
## never recomputes a Build and never turns a failed preview into a silent guess.
func _equip_preview_data(instance_id: String) -> Dictionary:
	if instance_id.is_empty():
		return {}
	var previews := UiKit.as_dictionary(_screen._facility_data.get("equip_previews", {}))
	var preview_value: Variant = previews.get(instance_id, null)
	if not preview_value is Dictionary or not bool((preview_value as Dictionary).get("ok", true)):
		return {}
	return preview_value


## The player-facing facts of one item, one line each: the published base name, the
## real modifiers and affix tiers in the player's own words, and the rune and law by
## their published Chinese names. The page's own tables are the only source: a
## parameter the tables do not name keeps its raw key, and nothing here is
## recomputed, scored, or invented.
func _item_summary_text(item: Dictionary, show_name := true) -> String:
	var formatted: String = _screen._readable_build.format_item(item)
	return "%s\n%s" % [_screen._item_display_name(item), formatted] if show_name else formatted


## Three intentional, non-ellipsized lines for the fixed first-screen pane. The
## explicit modal carries full effect prose; this surface keeps identity and the
## important material/affix/rune/law facts readable beside the paged inventory.
func _item_inline_summary_text(item: Dictionary) -> String:
	return _screen._equipment_model.current_inline_summary(item)


func _candidate_inline_item_facts(item: Dictionary) -> String:
	## The clarification follows the authoritative preview payload: with a valid
	## preview the comparison above already contains the base multipliers; without
	## one the note says so instead of implying a comparison happened.
	var preview := _equip_preview_data(String(item.get("instance_id", "")))
	return _screen._equipment_model.candidate_inline_facts(item, "included" if not preview.is_empty() else "no_preview")


## The modal receives the complete authoritative comparison. The fixed pane shows
## the changed parameters plus a literal route to the remaining interface/tag facts.
func _player_modifier_name(modifier_id: String) -> String:
	return _screen._equipment_model.modifier_name(modifier_id)


## equip_previews is an optional, backward-compatible snapshot field keyed by
## item instance_id. Each entry is authoritative data already computed upstream:
## {
##   "ok": true,
##   "final_parameters": {"p": 0.68, "T": 34.0, "v": 750.2, ...},
##   "interfaces_gained": ["..."],
##   "interfaces_lost": ["..."],
##   "tags_gained": ["..."],
##   "tags_lost": ["..."]
## }
## Missing, non-dictionary, or explicitly ok:false entries fall back to the
## plain candidate detail. Only changed parameters are shown; the preview is
## never recomputed here and no derived guidance is added.
func _equip_preview_text(instance_id: String) -> String:
	var preview := _equip_preview_data(instance_id)
	if preview.is_empty():
		return ""
	var final_parameters := UiKit.as_dictionary(preview.get("final_parameters", {}))
	var resolved := UiKit.as_dictionary(_screen._facility_data.get("resolved_build", {}))
	var current_parameters := UiKit.as_dictionary(resolved.get("final_parameters", {}))
	var lines: Array[String] = []
	if not final_parameters.is_empty() and not current_parameters.is_empty():
		var parameter_changes: Array[String] = []
		for parameter in PlayerReadableBuildScript.PARAMETER_ORDER:
			var next_value: Variant = final_parameters.get(parameter, null)
			if not FacilityItemText.is_number(next_value):
				continue
			var current_value: Variant = current_parameters.get(parameter, null)
			var next_float := float(next_value)
			if FacilityItemText.is_number(current_value):
				var current_float := float(current_value)
				if absf(next_float - current_float) <= 0.0001:
					continue
				parameter_changes.append("%s: %s → %s(%s%s)" % [
					_screen._readable_build.parameter_name(parameter),
					_screen._readable_build.format_parameter_value(parameter, current_float),
					_screen._readable_build.format_parameter_value(parameter, next_float),
					"+" if next_float > current_float else "", FacilityItemText.format_value(next_float - current_float),
				])
			else:
				parameter_changes.append("%s: Not Recorded -> %s (New)" % [_screen._readable_build.parameter_name(parameter), _screen._readable_build.format_parameter_value(parameter, next_float)])
		if not parameter_changes.is_empty():
			lines.append("Build Changes When Equipped:" + "  ·  ".join(parameter_changes))
	FacilityItemText.append_preview_group(lines, preview, "interfaces_gained", "Interfaces Gained")
	FacilityItemText.append_preview_group(lines, preview, "interfaces_lost", "Interfaces Lost")
	FacilityItemText.append_preview_group(lines, preview, "tags_gained", "Tags Gained")
	FacilityItemText.append_preview_group(lines, preview, "tags_lost", "Tags Lost")
	return "\n".join(lines)


## Compact decision layer, never an invented recommendation. Parameter deltas
## and concrete interface names come from the authoritative preview before the
## equip action; the complete canonical comparison remains below that action.
func _candidate_decision_text(instance_id: String) -> String:
	var preview := _equip_preview_data(instance_id)
	var resolved := UiKit.as_dictionary(_screen._facility_data.get("resolved_build", {}))
	var summary: String = _screen._readable_build.format_candidate_decision_summary(
		UiKit.as_dictionary(resolved.get("final_parameters", {})),
		preview
	)
	return summary.replace("Stats: ", "Stats When Equipped: ")


func _slot_display_name(slot: String) -> String:
	return _screen._readable_build.slot_label(slot)


## The player-facing slot name on its own. Titles carry the Chinese name only;
## the raw slot id stays in the detail rows that name a concrete item.
func _slot_title(slot: String) -> String:
	return _screen._readable_build.slot_label(slot)


func _salvage_action_for(item: Dictionary, instance_id: String) -> Dictionary:
	return _screen._equipment_model.salvage_action(item) if instance_id == String(item.get("instance_id", "")) else {}


## The confirmation names the clicked item in player terms while its authoritative
## instance id stays in the pending command only. A compact slot + trait signature
## distinguishes same-base variants without exposing persistence fields.
func _salvage_item_identity(item: Dictionary) -> String:
	return "%s\n%s · %s" % [
		_screen._item_display_name(item),
		_slot_display_name(String(item.get("slot", ""))),
		_screen._item_difference_summary_text(item),
	]


func _on_salvage_pressed(instance_id: String, readable_identity: String, operation: String, amount: int, equipped_slot: String = "") -> void:
	if instance_id.is_empty() or operation not in _screen.LAW_TALLY_LABELS or amount < 1 or _screen._salvage_dialog == null:
		return
	_screen._pending_salvage = {"instance_id": instance_id, "operation": operation, "amount": amount, "equipped_slot": equipped_slot}
	var equipped_notice := "\nCurrently equipped: confirming safely unequips %s before salvaging." % _slot_display_name(equipped_slot) if not equipped_slot.is_empty() else ""
	_screen._salvage_dialog.dialog_text = "Salvaging: %s\nReturns: %s x%d%s\nSalvage is irreversible. The item cannot be recovered after confirmation." % [
		readable_identity,
		String(_screen.LAW_TALLY_LABELS[operation]),
		amount,
		equipped_notice,
	]
	_screen._salvage_dialog.popup_centered()
