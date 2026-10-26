class_name FacilityForgePage
extends RefCounted

## Forge page extracted from FacilityScreen. This collaborator owns the forge
## workbench build, the target inventory and its inspection pane, the candidate
## cursor handlers, and the session/read-model helpers, reaching owner state and
## presentation through the untyped owner reference.
const ShellThemeScript = preload("res://src/presentation/shell_theme.gd")
const FacilityArtScript = preload("res://src/presentation/facility_art.gd")
const FacilityLayoutScript = preload("res://src/presentation/facility_layout.gd")
const EquipmentBackpackGridScript = preload("res://src/presentation/equipment_backpack_grid.gd")
## The forge authority owns the highest legal affix tier. Presentation reads this
## public contract only to stop offering a reveal the authority will reject.
const LawForgeScript = preload("res://src/systems/law_forge.gd")
const UiKit := preload("res://src/presentation/ui_kit.gd")
const FacilityItemText := preload("res://src/presentation/facility/item_text.gd")

const FORGE_OPERATION_EXPLANATIONS: Dictionary = {
	"inscribe": "Add one affix; the new slot is selected automatically.",
	"rewrite": "The Sacred Law sequence selects the existing affix to replace; you cannot choose it.",
	"refine": "The Sacred Law sequence selects the eligible affix to refine; you cannot choose it.",
}

var _screen


func _init(screen) -> void:
	_screen = screen


func _build_forge() -> void:
	if _screen._facility_data.is_empty():
		_screen._section("Forge State Unavailable","ForgeUnavailable").add_child(_screen._body_label("Forge data is not yet available."))
		return
	var session := _forge_session()
	var candidates := _forge_candidates()
	var selected_id := String(session.get("selected_candidate_id", ""))
	var selected := _forge_candidate_by_id(selected_id)
	var browse_status := "No Candidates Forecast Yet"
	if not candidates.is_empty():
		browse_status = "Viewing %d / %d" % [_screen._forge_candidate_index + 1, candidates.size()]
		if not selected.is_empty():
			browse_status += " · Candidate %d selected" % (_forge_candidate_index_by_id(selected_id) + 1)
	var columns := _forge_stage_columns("ForgeConceptRoot", FacilityLayoutScript.FORGE_WEIGHTS, [
		{"title": "Step 1 · Choose", "status": "Target Equipment and Law Tokens"},
		{"title": "Step 2 · Forecast and Commit", "status": browse_status},
	])
	var input: VBoxContainer = columns[0]
	var workflow: VBoxContainer = columns[1]
	var target := UiKit.as_dictionary(_screen._facility_data.get("target_item",{}))
	var tallies := UiKit.as_dictionary(_screen._facility_data.get("law_tallies", {}))
	var target_panel: VBoxContainer = _screen._section_in(input,"","ForgeTargetPanel")
	var target_row: HBoxContainer = _screen._make_row("ForgeTargetCompactRow")
	target_row.alignment = BoxContainer.ALIGNMENT_CENTER
	target_panel.add_child(target_row)
	_screen._add_facility_mark(target_row, Vector2i(64, 54))
	var canonical: String = _screen._art.canonical_id("equipment_base", String(target.get("base_item_id", "")))
	var target_texture: Texture2D = _screen._body_icon_texture(canonical)
	if target_texture != null:
		# The compact target summary keeps the authored cell at native 32x32. The
		# backpack below uses the larger 2x cells for browsing.
		var target_icon: TextureRect = _screen._icon_node(target_texture, FacilityArtScript.ICON_NATIVE_SIZE, false)
		target_icon.name = "ForgeTargetIcon_%s" % UiKit.stable_node_token(canonical)
		target_icon.set_meta("canonical_id", canonical)
		target_row.add_child(target_icon)
	var target_copy := VBoxContainer.new()
	target_copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	target_copy.add_theme_constant_override("separation", 2)
	target_row.add_child(target_copy)
	var label: Label = _screen._body_label("Target · %s" % _forge_item_title(target))
	label.name = "ForgeTargetItem"
	label.tooltip_text = _forge_readable_item_text(target)
	target_copy.add_child(label)
	var target_note: Label = _screen._note_label("Hover over Backpack Items to Inspect Affixes")
	target_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	target_note.tooltip_text = "Hover over or focus equipment in the backpack below to see all affixes."
	target_copy.add_child(target_note)
	# Operation choice belongs to the active target. Keeping it in the same compact
	# workbench makes all three choices available before the locally scrolling
	# backpack, even on the supported 1280x720 canvas.
	var setup_panel := VBoxContainer.new()
	setup_panel.name = "ForgeSetupPanel"
	setup_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	target_panel.add_child(setup_panel)
	var operation_row: HBoxContainer = _screen._make_row("ForgeOperationRow")
	setup_panel.add_child(operation_row)
	for operation in _screen.FORGE_TRACKS:
		var operation_button := Button.new()
		operation_button.name = "ForgeOperation_%s" % operation
		operation_button.add_theme_font_size_override("font_size", 22)
		operation_button.text = "%s\n×%d" % [String(_screen.FORGE_TRACK_TITLES[operation]), _law_tally(operation, tallies)]
		operation_button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		operation_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		operation_button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		operation_button.expand_icon = false
		operation_button.add_theme_constant_override("icon_max_width", 32)
		operation_button.add_theme_constant_override("h_separation", 4)
		operation_button.icon = _screen._progression_icons.icon("law_token.%s" % operation)
		operation_button.tooltip_text = ("Current Operation · " if operation == _screen._forge_operation else "") + String(FORGE_OPERATION_EXPLANATIONS[operation])
		operation_button.autowrap_mode = TextServer.AUTOWRAP_OFF
		operation_button.custom_minimum_size.y = 48
		operation_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		operation_button.disabled = operation == _screen._forge_operation
		if operation == _screen._forge_operation:
			operation_button.add_theme_stylebox_override("disabled", ShellThemeScript.panel_style("selected"))
			operation_button.add_theme_color_override("font_disabled_color", ShellThemeScript.BONE)
			operation_button.add_theme_color_override("icon_disabled_color", Color.WHITE)
		# Stack the icon above two authored lines so English operation names stay
		# intact in the narrow three-column workbench.
		for state in ["normal", "hover", "pressed", "disabled"]:
			var style_kind: String = {"normal":"button", "hover":"hover", "pressed":"selected", "disabled":"disabled"}[state]
			if state == "disabled" and operation == _screen._forge_operation:
				style_kind = "selected"
			var style := ShellThemeScript.panel_style(style_kind).duplicate() as StyleBox
			style.content_margin_left = 6.0
			style.content_margin_right = 6.0
			style.content_margin_top = 2.0
			style.content_margin_bottom = 2.0
			operation_button.add_theme_stylebox_override(state, style)
		operation_button.pressed.connect(_on_forge_operation_selected.bind(operation))
		operation_row.add_child(operation_button)
	_build_forge_inventory(input,UiKit.as_array(_screen._facility_data.get("inventory_items",[])),String(_screen._facility_data.get("target_instance_id","")))
	if not bool(_screen._facility_data.get("unlocked",false)):
		var locked: VBoxContainer = _screen._section_in(workflow,"Law Token Forge Locked","ForgeLocked")
		locked.add_child(_screen._body_label(String(_screen._facility_data.get("locked_reason","Unlock requirements not yet met"))))
	else:
		if candidates.is_empty():
			var reveal_panel: VBoxContainer = _screen._section_in(workflow,"Forecast a Future with Law Tokens","ForgeRevealPanel")
			reveal_panel.add_child(_screen._note_label(String(FORGE_OPERATION_EXPLANATIONS[_screen._forge_operation])))
			var block_reason := _forge_operation_block_reason(_screen._forge_operation)
			if not block_reason.is_empty():
				reveal_panel.add_child(_screen._body_label(block_reason, ShellThemeScript.WARNING))
		_build_forge_browse(workflow)
	_build_forge_dock()


## Fixed stage headers over independently scrolling bodies. Forge uses one setup
## lane and one decision lane; a long inventory or future result remains locally
## scrollable without duplicating the selected item in a third lane.
func _forge_stage_columns(node_name: String, weights: Array, stages: Array) -> Array:
	var stage := Control.new()
	stage.name = node_name
	stage.custom_minimum_size = Vector2(0, _screen._layout_frame.y)
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen._cards.add_child(stage)
	_screen._facility_root = stage
	var rectangles := FacilityLayoutScript.columns(_screen._layout_frame, weights)
	var result: Array = []
	for index in weights.size():
		var rect: Rect2 = rectangles[index]
		var panel := PanelContainer.new()
		panel.name = node_name + "Column" + str(index)
		panel.position = rect.position
		panel.size = rect.size
		panel.add_theme_stylebox_override("panel", _screen._grid_cell_box())
		stage.add_child(panel)
		var shell := VBoxContainer.new()
		shell.add_theme_constant_override("separation", 6)
		panel.add_child(shell)
		var stage_data: Dictionary = stages[index] if index < stages.size() and stages[index] is Dictionary else {}
		var title: Label = _screen._heading_label(String(stage_data.get("title", "")))
		title.name = "ForgeStage%dTitle" % (index + 1)
		shell.add_child(title)
		var status: Label = _screen._note_label(String(stage_data.get("status", "")))
		status.name = "ForgeStage%dStatus" % (index + 1)
		status.add_theme_color_override("font_color", ShellThemeScript.BONE)
		shell.add_child(status)
		var scroll := ScrollContainer.new()
		scroll.name = node_name + "Column" + str(index) + "BodyScroll"
		scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		ShellThemeScript.hide_passive_scrollbar_chrome(scroll)
		shell.add_child(scroll)
		var body := VBoxContainer.new()
		body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body.add_theme_constant_override("separation", 8)
		scroll.add_child(body)
		result.append(body)
	return result

func _on_forge_operation_selected(operation: String) -> void:
	if operation not in _screen.FORGE_TRACKS or operation == _screen._forge_operation:
		return
	_screen._forge_candidate_index = 0
	_screen.action_requested.emit("forge", "select_forge_operation", {"operation": operation, "revision": _forge_revision()})


func _build_forge_browse(parent: Container) -> void:
	var panel: VBoxContainer = _screen._section_in(parent, "Future Outcome", "ForgeBrowsePanel")
	var candidates := _forge_candidates()
	var browse: Label = _screen._body_label("No future has been forecast. Choose equipment and Law Tokens, then use the button below.")
	browse.name = "ForgeBrowseSelectionState"
	panel.add_child(browse)
	if candidates.is_empty():
		return
	var candidate := _current_forge_candidate()
	var candidate_id := String(candidate.get("candidate_id", ""))
	var selected_id := String(_forge_session().get("selected_candidate_id", ""))
	var relation := "Viewing · Not Selected"
	if candidate_id == selected_id:
		relation = "Current Future Selected · Ready to Commit"
	elif not selected_id.is_empty():
		relation = "Viewing a New Future · Candidate %d Selected" % (_forge_candidate_index_by_id(selected_id) + 1)
	browse.text = "%s\nCandidate %d / %d · Selecting costs %d %s\n%s" % [
		relation, _screen._forge_candidate_index + 1, candidates.size(),
		FacilityItemText.forge_candidate_cost(candidate), FacilityItemText.law_token_name(_forge_session_operation(), FacilityItemText.forge_candidate_cost(candidate)),
		_forge_candidate_change_text(candidate),
	]
	var equipped := bool(candidate.get("target_is_equipped", false))
	panel.add_child(_screen._note_label("Current Build Changes After Commit" if equipped else "Commit leaves current build unchanged; expected changes when equipped"))
	var impact := UiKit.as_dictionary(candidate.get("build_comparison", {}))
	_screen._add_interface_changes(panel, impact)
	var comparison = preload("res://src/presentation/equipment_comparison.gd").new()
	comparison.name = "ForgeBuildComparison"
	comparison.present(impact.get("current_parameters", {}), impact.get("result_parameters", {}), "After Commit" if equipped else "When Equipped")
	panel.add_child(comparison)
	var result_item := FacilityItemText.forge_candidate_result_item_view(candidate)
	var detail: Button = _screen._add_full_item_detail_button(panel, result_item, "Forge Forecast · " + _forge_item_title(result_item),
		"Forecast Outcome\n%s\n\n%s" % [_forge_readable_item_text(result_item), _forge_build_change_text(candidate)])
	detail.name = "ForgeFullResultDetail"
	detail.text = "Full Equipment and Build Details"



func _on_forge_confirm_selection() -> void:
	var session := _forge_session()
	if session.is_empty() or String(session.get("selected_candidate_id", "")).is_empty():
		return
	var session_id := String(session.get("session_id", ""))
	if session_id == _screen._forge_committed_session_id:
		return
	_screen._forge_committed_session_id = session_id
	_screen.action_requested.emit("forge","forge_commit",{"session_id": session_id})
	_screen._apply_presentation()


func _on_forge_cancel_selection() -> void:
	var session_id := String(_forge_session().get("session_id", ""))
	if not session_id.is_empty():
		_screen.action_requested.emit("forge", "forge_cancel", {"session_id": session_id})


## Target inventory inside the first lane of the two-column forge composition.
func _build_forge_inventory(parent: Container, inventory: Array, target_id: String) -> void:
	var section: VBoxContainer = _screen._section_in(parent, "Select Forge Target", "ForgeInventorySection")
	var panel: PanelContainer = _screen._section_panel(section)
	if panel != null:
		panel.custom_minimum_size.x = 0.0
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_screen._forge_backpack_items = inventory.duplicate(true)
	var row := VBoxContainer.new()
	row.name = "ForgeBackpackRow"
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 4)
	section.add_child(row)
	var backpack := EquipmentBackpackGridScript.new()
	var initial_backpack_id: String = _screen._forge_backpack_selection if not _screen._forge_backpack_selection.is_empty() else target_id
	backpack.configure(_screen._backpack_entries(inventory, "ForgeBackpackIcon"), initial_backpack_id, 4, "ForgeBackpack", 1)
	backpack.item_inspected.connect(_on_forge_backpack_inspected)
	row.add_child(backpack)
	_screen._forge_backpack_detail_region = Control.new()
	_screen._forge_backpack_detail_region.name = "BackpackDetail"
	_screen._forge_backpack_detail_region.custom_minimum_size = Vector2(0, 104)
	_screen._forge_backpack_detail_region.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_screen._forge_backpack_detail_region.clip_contents = true
	row.add_child(_screen._forge_backpack_detail_region)
	_screen._forge_backpack_detail = VBoxContainer.new()
	_screen._forge_backpack_detail.name = "BackpackDetailContent"
	_screen._forge_backpack_detail.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen._forge_backpack_detail.offset_left = 8.0
	_screen._forge_backpack_detail.offset_top = 6.0
	_screen._forge_backpack_detail.offset_right = -8.0
	_screen._forge_backpack_detail.offset_bottom = -6.0
	_screen._forge_backpack_detail_region.add_child(_screen._forge_backpack_detail)
	if _screen._forge_backpack_selection.is_empty() or _screen._inventory_item_by_id(inventory, _screen._forge_backpack_selection).is_empty():
		_screen._forge_backpack_selection = target_id
	_render_forge_backpack_detail(_screen._forge_backpack_selection)
	_screen._forge_backpack_detail_region.visible = false


func _on_forge_backpack_inspected(instance_id: String) -> void:
	if instance_id.is_empty():
		call_deferred("_finish_forge_backpack_exit")
		return
	_screen._forge_backpack_selection = instance_id
	_render_forge_backpack_detail(instance_id)


func _finish_forge_backpack_exit() -> void:
	if _screen._item_detail_dialog != null and _screen._item_detail_dialog.visible:
		return
	var focus_owner: Control = _screen.get_viewport().gui_get_focus_owner() if _screen.get_viewport() != null else null
	if focus_owner != null and _screen._forge_backpack_detail_region != null \
		and (_screen._forge_backpack_detail_region == focus_owner or _screen._forge_backpack_detail_region.is_ancestor_of(focus_owner)):
		return
	var backpack: Node = _screen.find_child("EquipmentBackpack", true, false)
	if backpack != null and backpack.has_method("inspected_item_id") \
		and not String(backpack.call("inspected_item_id")).is_empty():
		return
	_screen._forge_backpack_selection = ""
	if backpack != null and backpack.has_method("select_item"):
		backpack.call("select_item", String(_screen._facility_data.get("target_instance_id", "")))
	_render_forge_backpack_detail("")


func _render_forge_backpack_detail(instance_id: String) -> void:
	if _screen._forge_backpack_detail == null or not is_instance_valid(_screen._forge_backpack_detail):
		return
	UiKit.clear_children(_screen._forge_backpack_detail)
	var item: Dictionary = _screen._inventory_item_by_id(_screen._forge_backpack_items, instance_id)
	if item.is_empty():
		if _screen._forge_backpack_detail_region != null:
			_screen._forge_backpack_detail_region.visible = false
		return
	if _screen._forge_backpack_detail_region != null:
		_screen._forge_backpack_detail_region.visible = true
	var instance_token := UiKit.stable_node_token(instance_id)
	var selected := instance_id == String(_screen._facility_data.get("target_instance_id", ""))
	var action_row: HBoxContainer = _screen._make_row("BackpackActions")
	_screen._forge_backpack_detail.add_child(action_row)
	var name_label: Label = _screen._body_label(_forge_item_title(item))
	name_label.name = "BackpackDetailName"
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.max_lines_visible = 2
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.tooltip_text = "%s\n%s" % [_forge_item_title(item), _screen._item_difference_summary_text(item)]
	action_row.add_child(name_label)
	var choose := Button.new()
	choose.name = "SelectForgeItem_%s" % instance_token
	choose.text = "Current Target" if selected else "Set as Target"
	choose.disabled = selected
	choose.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	choose.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	choose.pressed.connect(_on_forge_target_selected.bind(instance_id))
	action_row.add_child(choose)
	_screen._add_full_item_detail_button(
		action_row,
		item,
		_forge_item_title(item),
		_forge_readable_item_text(item)
	)
	_screen._track_backpack_detail_actions(_screen._forge_backpack_detail_region, "forge")


## The pinned forge dock: candidate controls, exact Law Tally cost, and the
## snapshot summary. It stays visible while the tracks above scroll.
func _build_forge_dock() -> void:
	if not bool(_screen._facility_data.get("unlocked", false)):
		return
	var session := _forge_session()
	if session.is_empty():
		var reveal := Button.new()
		reveal.name = "ForgeReveal"
		reveal.add_theme_stylebox_override("normal", ShellThemeScript.panel_style("selected"))
		reveal.text = "Forecast with %s · No Tokens Spent Yet" % FacilityItemText.law_token_name(_screen._forge_operation)
		reveal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		reveal.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		reveal.disabled = not _forge_operation_block_reason(_screen._forge_operation).is_empty() or not _forge_can_start()
		reveal.pressed.connect(_on_forge_reveal)
		_screen._actions.add_child(reveal)
		return
	var candidates := _forge_candidates()
	var previous := Button.new()
	previous.name = "ForgePreviousCandidate"
	previous.text = "Prev"
	previous.tooltip_text = "Previous Candidate"
	# These are short dock actions. Keep every one on a single line so the pinned
	# footer has a stable height instead of being pushed below a 1080p window.
	previous.autowrap_mode = TextServer.AUTOWRAP_OFF
	previous.custom_minimum_size.x = 100
	previous.disabled = candidates.size() <= 1
	previous.pressed.connect(_on_forge_candidate_shift.bind(-1))
	_screen._actions.add_child(previous)
	var next := Button.new()
	next.name = "ForgeNextCandidate"
	next.text = "Next"
	next.tooltip_text = "Next Candidate"
	next.autowrap_mode = TextServer.AUTOWRAP_OFF
	next.custom_minimum_size.x = 100
	next.disabled = candidates.size() <= 1
	next.pressed.connect(_on_forge_candidate_shift.bind(1))
	_screen._actions.add_child(next)
	if bool(session.get("has_more", false)):
		var more := Button.new()
		more.name = "ForgeRevealMore"
		more.text = "Forecast More"
		more.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		more.custom_minimum_size.x = 120
		more.pressed.connect(_on_forge_reveal_more)
		_screen._actions.add_child(more)
	var selected_id := String(session.get("selected_candidate_id", ""))
	var browsing_id := String(_current_forge_candidate().get("candidate_id", ""))
	if selected_id.is_empty() or browsing_id != selected_id:
		var select := Button.new()
		select.name = "ForgeSelectCandidate"
		select.add_theme_stylebox_override("normal", ShellThemeScript.panel_style("selected"))
		select.text = "Select Current Future" if selected_id.is_empty() else "Switch to Current Future"
		select.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		select.custom_minimum_size.x = 164
		select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		select.disabled = candidates.is_empty()
		select.pressed.connect(_on_forge_select_current_candidate)
		_screen._actions.add_child(select)
	else:
		var confirm := Button.new()
		confirm.name = "ForgeConfirmSelection"
		confirm.add_theme_stylebox_override("normal", ShellThemeScript.panel_style("selected"))
		var selected := _forge_candidate_by_id(selected_id)
		confirm.text = "Confirm Commit · Spend %d %s" % [FacilityItemText.forge_candidate_cost(selected), FacilityItemText.law_token_name(_forge_session_operation(), FacilityItemText.forge_candidate_cost(selected))]
		if not _forge_candidate_affordable(selected):
			confirm.text = "Not Enough Law Tokens · Need %d %s, Have %d" % [
				FacilityItemText.forge_candidate_cost(selected),
				FacilityItemText.law_token_name(_forge_session_operation(), FacilityItemText.forge_candidate_cost(selected)),
				_law_tally(_forge_session_operation()),
			]
		confirm.disabled = selected.is_empty() or not _forge_candidate_affordable(selected) or String(session.get("session_id", "")) == _screen._forge_committed_session_id
		confirm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		confirm.custom_minimum_size.x = 280
		confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		confirm.pressed.connect(_on_forge_confirm_selection)
		_screen._actions.add_child(confirm)
	var cancel := Button.new()
	cancel.name = "ForgeCancelSelection"
	cancel.text = "Cancel This Forge"
	cancel.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cancel.custom_minimum_size.x = 180
	cancel.disabled = _forge_session().is_empty()
	cancel.pressed.connect(_on_forge_cancel_selection)
	_screen._actions.add_child(cancel)


func _forge_session() -> Dictionary:
	var session := UiKit.as_dictionary(_screen._facility_data.get("session", {}))
	if String(session.get("session_id", "")).strip_edges().is_empty():
		return {}
	return session


func _restore_forge_session_cursor() -> void:
	var session := _forge_session()
	if session.is_empty():
		_screen._forge_candidate_index = 0
		_screen._forge_committed_session_id = ""
		return
	# A fresh authoritative presentation of the still-selected session means the
	# previous commit attempt was rejected or its save failed. Re-arm exactly that
	# choice for retry; a local rebuild after the press does not call this method,
	# so rapid repeated presses remain suppressed.
	if String(session.get("session_id", "")) != _screen._forge_committed_session_id or String(session.get("state", "")) == "selected":
		_screen._forge_committed_session_id = ""
	var selected_id := String(session.get("selected_candidate_id", ""))
	var candidates := _forge_candidates()
	for index in candidates.size():
		if String((candidates[index] as Dictionary).get("candidate_id", "")) == selected_id:
			_screen._forge_candidate_index = index
			return
	_screen._forge_candidate_index = clampi(_screen._forge_candidate_index, 0, maxi(0, candidates.size() - 1))


func _forge_candidates() -> Array[Dictionary]:
	var session := _forge_session()
	var revealed_count := int(session.get("revealed_count", 0))
	if revealed_count <= 0:
		return []
	var result: Array[Dictionary] = []
	for raw_candidate in UiKit.as_array(session.get("candidates", [])):
		if raw_candidate is Dictionary and not String((raw_candidate as Dictionary).get("candidate_id", "")).is_empty():
			result.append((raw_candidate as Dictionary).duplicate(true))
			if result.size() >= revealed_count:
				break
	return result


func _current_forge_candidate() -> Dictionary:
	var candidates := _forge_candidates()
	if candidates.is_empty():
		return {}
	_screen._forge_candidate_index = clampi(_screen._forge_candidate_index, 0, candidates.size() - 1)
	return candidates[_screen._forge_candidate_index]


func _forge_candidate_by_id(candidate_id: String) -> Dictionary:
	if candidate_id.is_empty():
		return {}
	for candidate in _forge_candidates():
		if String(candidate.get("candidate_id", "")) == candidate_id:
			return candidate
	return {}


func _forge_candidate_index_by_id(candidate_id: String) -> int:
	if candidate_id.is_empty():
		return -1
	var candidates := _forge_candidates()
	for index in candidates.size():
		if String(candidates[index].get("candidate_id", "")) == candidate_id:
			return index
	return -1


func _forge_candidate_family_name(candidate: Dictionary) -> String:
	var formatted: String = _screen._readable_build.format_affix(candidate)
	var named := formatted.get_slice(": ", 0)
	var tier: String = _screen._readable_build.tier_label(int(candidate.get("tier", 0)))
	return named.trim_suffix(" " + tier) if named.ends_with(" " + tier) else named


func _forge_candidate_change_text(candidate: Dictionary) -> String:
	var result := "%s %s" % [
		_forge_candidate_family_name(candidate),
		_screen._readable_build.tier_label(int(candidate.get("tier", 0))),
	]
	var operation := String(candidate.get("operation", _forge_session_operation()))
	if operation == "inscribe":
		return "New: %s" % result
	var previous_name := String(candidate.get("previous_family_name", "Existing Affix"))
	var previous_tier: String = _screen._readable_build.tier_label(int(candidate.get("previous_tier", 0)))
	return "%s: %s %s → %s" % [
		"Automatic Refine" if operation == "refine" else "Automatic Rewrite",
		previous_name,
		previous_tier,
		result,
	]


func _forge_session_operation() -> String:
	var operation := String(_forge_session().get("operation", _screen._forge_operation))
	return operation if operation in _screen.FORGE_TRACKS else _screen._forge_operation


func _forge_revision() -> int:
	return int(_screen._facility_data.get("revision", -1))


func _law_tally(operation: String, tallies: Dictionary = {}) -> int:
	var source := tallies if not tallies.is_empty() else UiKit.as_dictionary(_screen._facility_data.get("law_tallies", {}))
	return maxi(0, int(source.get(operation, 0)))


func _forge_candidate_affordable(candidate: Dictionary) -> bool:
	var session := _forge_session()
	var affordable_count := maxi(0, int(session.get("affordable_count", 0)))
	var sequence := maxi(1, int(candidate.get("sequence_number", 1)))
	return sequence <= affordable_count and FacilityItemText.forge_candidate_cost(candidate) <= _law_tally(_forge_session_operation())


func _forge_operation_block_reason(operation: String) -> String:
	if not bool(_screen._facility_data.get("unlocked", false)):
		return "The Law Token Forge is not yet unlocked."
	if UiKit.as_dictionary(_screen._facility_data.get("target_item", {})).is_empty() or String(_screen._facility_data.get("target_instance_id", "")).is_empty():
		return "Select target equipment first."
	match String(_screen._facility_data.get("blocked_reason", "")):
		"affix_limit_reached":
			return "Affixes full (maximum %d); cannot inscribe." % LawForgeScript.MAX_AFFIXES
		"affix_required":
			return "%s requires at least one existing affix." % String(_screen.FORGE_TRACK_TITLES.get(operation, "This operation"))
		"rewrite_not_legal":
			return "This item has no eligible new affix for rewriting."
		"max_tier":
			return "All existing affixes are at their highest tier and cannot be refined."
	if _law_tally(operation) <= 0:
		return "No %s available; cannot forecast a committable outcome." % FacilityItemText.law_token_name(operation)
	return ""


func _forge_can_start() -> bool:
	return _forge_session().is_empty() and not String(_screen._facility_data.get("target_instance_id", "")).is_empty()


func _on_forge_reveal() -> void:
	if not _forge_can_start() or not _forge_operation_block_reason(_screen._forge_operation).is_empty():
		return
	_screen.action_requested.emit("forge", "forge_reveal", {"revision": _forge_revision()})


func _on_forge_reveal_more() -> void:
	var session_id := String(_forge_session().get("session_id", ""))
	if not session_id.is_empty() and bool(_forge_session().get("has_more", false)):
		_screen.action_requested.emit("forge", "forge_reveal_more", {"session_id": session_id})


func _on_forge_candidate_shift(offset: int) -> void:
	var candidates := _forge_candidates()
	if candidates.is_empty():
		return
	_screen._forge_candidate_index = posmod(_screen._forge_candidate_index + offset, candidates.size())
	if _screen._built:
		_screen._apply_presentation()


func _on_forge_select_current_candidate() -> void:
	var session_id := String(_forge_session().get("session_id", ""))
	var candidate_id := String(_current_forge_candidate().get("candidate_id", ""))
	if session_id.is_empty() or candidate_id.is_empty():
		return
	_screen.action_requested.emit("forge", "forge_select_candidate", {"session_id": session_id, "candidate_id": candidate_id})


func _on_forge_target_selected(instance_id: String) -> void:
	if instance_id.is_empty() or instance_id == String(_screen._facility_data.get("target_instance_id", "")):
		return
	_screen._forge_candidate_index = 0
	_screen.action_requested.emit("forge", "select_forge_item", {"instance_id": instance_id, "revision": _forge_revision()})


func _forge_item_title(item: Dictionary) -> String:
	if item.is_empty():
		return "No Target Equipment Selected"
	return String(item.get("base_name", _screen._item_display_name(item)))


func _forge_readable_item_text(item: Dictionary) -> String:
	if item.is_empty():
		return "No Equipment Data"
	return "%s\n%s" % [_forge_item_title(item), _screen._readable_build.format_item(item)]


func _forge_build_change_text(candidate: Dictionary) -> String:
	var comparison := UiKit.as_dictionary(candidate.get("build_comparison", {}))
	var current := UiKit.as_dictionary(comparison.get("current_parameters", {}))
	var after := UiKit.as_dictionary(comparison.get("result_parameters", {}))
	var preview_impact := String(candidate.get("preview_impact", ""))
	var target_is_equipped: Variant = candidate.get("target_is_equipped", null)
	if not (target_is_equipped is bool):
		return "Forge target equipment state is missing"
	var heading := ""
	if bool(target_is_equipped) and preview_impact == "current_build_immediate":
		heading = "Target Equipped · Current Build Changes After Commit"
	elif not bool(target_is_equipped) and preview_impact == "equip_after_commit":
		heading = "Target Not Equipped · Commit Leaves Current Build Unchanged; Expected Changes When Equipped"
	else:
		return "Inconsistent Forge Preview Semantics"
	if current.is_empty() or after.is_empty():
		return "%s: No Data" % heading
	var comparison_text: String = _screen._readable_build.format_comparison(current, after)
	var lines: Array[String] = ["%s: " % heading]
	if comparison_text.is_empty():
		lines.append("No Stat Changes")
	else:
		lines.append(comparison_text)
	FacilityItemText.append_preview_group(lines, comparison, "interfaces_gained", "Interfaces Gained")
	FacilityItemText.append_preview_group(lines, comparison, "interfaces_lost", "Interfaces Lost")
	return "\n".join(lines)
