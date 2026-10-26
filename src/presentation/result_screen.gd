class_name ResultScreen
extends Control
## Contract settlement: what actually happened in the run that just ended.
##
## The header and actions stay pinned. The left lane scrolls complete reward
## and item text inside a bounded viewport, with pagination outside that viewport.
## Three-column combat metrics retain their existing layout and typography.
##
## Content: values come from the settlement payload; the only bar uses actual
## rooms_completed / room_count. No score or event tree is inferred. Missing data is
## left out instead of being drawn as a zero -- a reported zero is a reading and
## stays -- and a field outside the known table is listed raw in the collapsible
## Calculation Details block, together with the untruncated drop ids.
##
## Drop cards: the face of a card is what the run produced -- the published Chinese
## name of the base item, its slot and its affixes -- beside one full-size subject
## icon. The instance id, the base id, the raw affix families and the drop source
## never enter the player-facing face. They stay reachable through
## get_equipment_card_texts for the F10 evidence harness and get_detail_text.
##
## Names: read-only from the content table (EarlyItemRegistry over
## content/early_items.json). An explicit name field on the drop wins, then the
## published table, then the raw id -- an id neither source covers keeps its own
## text and is never guessed at.
##
## Art: drop icons are canonical cells of the published 24-icon batch, read through
## FacilityArt. An id the package does not publish resolves to null and the card
## keeps its text alone; no stand-in is drawn in its place.

signal base_requested
signal ending_requested
signal contract_requested
signal loadout_review_requested(instance_id: String, slot: String)

const ShellThemeScript = preload("res://src/presentation/shell_theme.gd")
const FacilityArtScript = preload("res://src/presentation/facility_art.gd")
const EarlyItemRegistryScript = preload("res://src/content/early_item_registry.gd")
const PlayerReadableBuildScript = preload("res://src/presentation/player_readable_build.gd")
const EquipmentPresentationModelScript = preload("res://src/presentation/models/equipment_presentation_model.gd")
const UiKit := preload("res://src/presentation/ui_kit.gd")
const ResultTextScript = preload("res://src/presentation/result/result_text.gd")
const ResultWidgetsScript = preload("res://src/presentation/result/result_widgets.gd")
const ResultReportPanelScript = preload("res://src/presentation/result/result_report_panel.gd")
const ResultLootPanelScript = preload("res://src/presentation/result/result_loot_panel.gd")

## The shell's one UI resolution. Every rect below is expressed in these pixels.
const DESIGN_SIZE := Vector2(1280.0, 720.0)
const SCREEN_MARGIN := 24

const DETAIL_HEADING := "Calculation Details"
const DETAIL_SHOW_TEXT := "Show Calculation Details"
const DETAIL_HIDE_TEXT := "Hide Calculation Details"
const BASE_BUTTON_TEXT := "Return to Hub"
const ENDING_BUTTON_TEXT := "View Epilogue"
const CONTRACT_BUTTON_TEXT := "Depart Again"

var _built := false
var _result: Dictionary = {}
var _contract: Dictionary = {}
## Live ownership/equipment is separate from the immutable settlement receipt.
var _current_profile: Dictionary = {}
var _art = FacilityArtScript.new()
var _art_error := ""
## The read-only content table that names base items and affix families, or null
## when this package cannot read it -- every id then stays raw on the card.
var _item_registry: Variant = null
var _player_readable = PlayerReadableBuildScript.new()
var _equipment_model: EquipmentPresentationModelScript = null
var _detail_visible := false
var _detail_panel: PanelContainer
var _detail_button: Button
## The header/report lane and the loot lane are collaborators under
## src/presentation/result/; the screen keeps the shell layout, the footer
## actions, the settlement state and the public accessors.
var _report = ResultReportPanelScript.new(self)
var _loot = ResultLootPanelScript.new(self)
var _content: Control
var _base_button: Button
var _ending_button: Button
var _contract_button: Button


func _ready() -> void:
	_build_ui()
	_apply_presentation()
	_focus_default_action.call_deferred()


func present(result: Dictionary, contract: Dictionary = {}, current_profile: Dictionary = {}) -> void:
	_result = result.duplicate(true)
	_contract = contract.duplicate(true)
	_current_profile = current_profile.duplicate(true)
	_equipment_model = EquipmentPresentationModelScript.new(_player_readable, _registry_rows("base_items"), _registry_rows("affix_families"), {}, "Unknown Equipment")
	if _built:
		_apply_presentation()
		_focus_default_action()


func _build_ui() -> void:
	if _built:
		return
	_built = true
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = ShellThemeScript.create()
	_load_art()
	_load_item_names()

	ShellThemeScript.add_backdrop(self, "result_screen")

	var root := Control.new()
	root.name = "ResultRoot"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = SCREEN_MARGIN
	root.offset_top = SCREEN_MARGIN
	root.offset_right = -SCREEN_MARGIN
	root.offset_bottom = -SCREEN_MARGIN
	add_child(root)

	_report.build_header(root)
	_build_body(root)
	_build_footer(root)
	ResultWidgetsScript.place_section(root.get_node("ResultHeader"), 0.0, 0.0, 0.0, 107.0)
	ResultWidgetsScript.place_section(root.get_node("ResultContent"), 0.0, 1.0, 121.0, -32.0)
	ResultWidgetsScript.place_section(root.get_node("ResultFooter"), 1.0, 1.0, -44.0, 0.0)
	_layout_footer_against_body()
	resized.connect(_layout_footer_against_body)
	(root.get_node("ResultFooter") as Control).minimum_size_changed.connect(_layout_footer_against_body)
	resized.connect(_report.sync_metric_columns)
	resized.connect(_loot.sync_page_size)
	_report.sync_metric_columns()
	_loot.sync_page_size()


func _layout_footer_against_body() -> void:
	var body := get_node_or_null("ResultRoot/ResultContent") as Control
	var footer := get_node_or_null("ResultRoot/ResultFooter") as Control
	if body == null or footer == null:
		return
	footer.offset_top = -ceil(maxf(footer.get_minimum_size().y, footer.get_combined_minimum_size().y))
	body.offset_bottom = footer.offset_top - ResultWidgetsScript.BLOCK_SEPARATION


func _build_body(root: Control) -> void:
	## The body is fixed to the shell. Equipment text scrolls locally while its
	## pager stays pinned; the report lane keeps compact decision cards, and
	## diagnostics stay behind the F10 provider.
	_content = PanelContainer.new()
	_content.name = "ResultContent"
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.clip_contents = true
	_content.add_theme_stylebox_override("panel", ShellThemeScript.crafted_panel())
	root.add_child(_content)

	var columns := HBoxContainer.new()
	columns.name = "ResultColumns"
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", ResultWidgetsScript.BLOCK_SEPARATION)
	_content.add_child(columns)
	_loot.build(columns)
	_report.build(columns)
	_loot.build_detail_overlay()


func _build_footer(root: Control) -> void:
	var footer := HBoxContainer.new()
	footer.name = "ResultFooter"
	footer.add_theme_constant_override("separation", 12)
	root.add_child(footer)
	_contract_button = Button.new()
	_contract_button.name = "ContractAgainButton"
	_contract_button.text = CONTRACT_BUTTON_TEXT
	_contract_button.size_flags_stretch_ratio = 0.75
	_contract_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_contract_button.pressed.connect(_on_contract_pressed)
	footer.add_child(_contract_button)
	_base_button = Button.new()
	_base_button.name = "ReturnToBaseButton"
	_base_button.text = BASE_BUTTON_TEXT
	_base_button.size_flags_stretch_ratio = 1.3
	_base_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_base_button.pressed.connect(_on_base_pressed)
	footer.add_child(_base_button)
	_ending_button = Button.new()
	_ending_button.name = "EndingButton"
	_ending_button.text = ENDING_BUTTON_TEXT
	_ending_button.size_flags_stretch_ratio = 1.3
	_ending_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ending_button.pressed.connect(_on_ending_pressed)
	footer.add_child(_ending_button)


func _focus_default_action() -> void:
	if not is_inside_tree(): return
	if _ending_button != null and _ending_button.visible:
		_ending_button.grab_focus()
	elif _base_button != null and _base_button.visible:
		_base_button.grab_focus()


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	var key := key_event.keycode if key_event.keycode != KEY_NONE else key_event.physical_keycode
	if not key_event.pressed or key_event.echo or key != KEY_ESCAPE:
		return
	if _loot.is_detail_open():
		_loot.close_equipment_detail()
		accept_event()
		return
	if _base_button != null and _base_button.is_visible_in_tree():
		_on_base_pressed()
		accept_event()


func _apply_presentation() -> void:
	var outcome := String(_result.get("outcome", "unknown")).to_lower()
	var is_final_victory := outcome == "final_victory"
	_report.apply_header(_result, outcome)
	_ending_button.visible = is_final_victory
	_contract_button.visible = not is_final_victory
	_base_button.size_flags_stretch_ratio = 0.75 if is_final_victory else 1.3
	ResultWidgetsScript.set_button_primary(_base_button, not is_final_victory)
	ResultWidgetsScript.set_button_primary(_ending_button, is_final_victory)
	_report.apply_report(_result, _contract)
	_loot.apply(_result, UiKit.as_dictionary(_result.get("rewards", {})))
	_report.apply_headline(_result, outcome, _loot.equipment_drop_entries.size(), _loot.proxy_component_count)


## The authoritative instance id, whole. A display that shortens an id hides the one
## field that identifies which drop this actually is, so nothing is cut here; the
## audit line and Calculation Details print it in full, and the detail block may break inside it.
func _registry_rows(table: String) -> Dictionary:
	if _item_registry == null:
		return {}
	return UiKit.as_dictionary(_item_registry.base_items if table == "base_items" else _item_registry.affix_families)


func _sync_detail_visibility() -> void:
	if _detail_panel == null:
		return
	_detail_panel.visible = _detail_visible
	_detail_button.text = DETAIL_HIDE_TEXT if _detail_visible else DETAIL_SHOW_TEXT


## Read-only load of the published icon batch. A package that cannot be read leaves
## the reason for the detail block; every card keeps its text either way.
func _load_art() -> void:
	_art_error = ""
	if _art.load_art():
		return
	_art_error = String(_art.pending_reason)


## Read-only load of the content table that names base items and affix families. A
## package whose table cannot be read keeps both lookups empty, and every id then
## stays raw on the card instead of borrowing a name it was never given.
func _load_item_names() -> void:
	var registry = EarlyItemRegistryScript.new()
	if not registry.load_all().is_empty():
		return
	_item_registry = registry
	_player_readable = PlayerReadableBuildScript.new(registry)
	_equipment_model = EquipmentPresentationModelScript.new(_player_readable, _registry_rows("base_items"), _registry_rows("affix_families"), {}, "Unknown Equipment")


## ---- public surface used by the router, the harness and the tests ----


func get_reward_text() -> String:
	return _loot.reward_label.tooltip_text if _loot.reward_label != null else ""


func get_diagnosis_text() -> String:
	return _report.diagnosis_label.text if _report.diagnosis_label != null else ""


func get_report_text() -> String:
	return _report.report_label.text if _report.report_label != null else ""


## The authoritative run facts beside the report: contract, mode, room progress,
## per-room outcomes and the named failure reason.
func get_run_facts_text() -> String:
	return _report.run_facts_label.text if _report.run_facts_label != null else ""


## The settlement payload as this screen received it, for evidence capture: the
## copy on screen can be read back against the authority that produced it.
func get_presented_result() -> Dictionary:
	return _result.duplicate(true)


func get_presented_contract() -> Dictionary:
	return _contract.duplicate(true)


func get_detail_text() -> String:
	var rewards := UiKit.as_dictionary(_result.get("rewards", {}))
	var drop_field_texts: Array[String] = []
	for entry in ResultTextScript.equipment_entries(_result, rewards):
		drop_field_texts.append(_loot.equipment_field_text(entry))
	return "\n".join(ResultTextScript.detail_lines(_result, _contract, _art_error) + ResultTextScript.detail_raw_lines(_result, drop_field_texts))


func set_detail_visible(value: bool) -> void:
	_detail_visible = value
	_sync_detail_visibility()


func is_detail_visible() -> bool:
	return _detail_panel != null and _detail_panel.visible


## The equipment lane's accessors and focus entry point forward to the loot
## collaborator.
func focus_equipment(instance_id: String) -> void:
	_loot.focus_equipment(instance_id)


func get_equipment_card_count() -> int:
	return _loot.get_equipment_card_count()


func get_proxy_component_card_texts() -> Array[String]:
	return _loot.get_proxy_component_card_texts()


func get_equipment_card_texts() -> Array[String]:
	return _loot.get_equipment_card_texts()


func get_equipment_card_summaries() -> Array[String]:
	return _loot.get_equipment_card_summaries()


## Kept as a forwarder: the unit tests read the route nodes the screen would draw.
func _reported_route_steps() -> Array:
	return ResultTextScript.reported_route_steps(_result)


func _on_base_pressed() -> void:
	base_requested.emit()


func _on_contract_pressed() -> void:
	contract_requested.emit()


func _on_review_drop_pressed(instance_id: String, slot: String) -> void:
	loadout_review_requested.emit(instance_id, slot)


func _on_ending_pressed() -> void:
	ending_requested.emit()
