class_name FacilityScreen
extends Control

signal base_requested
signal destination_requested(route: String)
signal action_requested(facility_id: String, action_id: String, payload: Dictionary)

const ShellThemeScript = preload("res://src/presentation/shell_theme.gd")
const FacilityArtScript = preload("res://src/presentation/facility_art.gd")
const FacilityLayoutScript = preload("res://src/presentation/facility_layout.gd")
const LoadoutCharacterViewScript = preload("res://src/presentation/loadout_character_view.gd")
const TrainingTraceViewScript = preload("res://src/presentation/training_trace_view.gd")
const LockedSlotMarkScript = preload("res://src/presentation/locked_slot_mark.gd")
const EquipmentBackpackGridScript = preload("res://src/presentation/equipment_backpack_grid.gd")
const EquipmentFilterBarScript = preload("res://src/presentation/equipment_filter_bar.gd")
const PlayerReadableBuildScript = preload("res://src/presentation/player_readable_build.gd")
const EquipmentPresentationModelScript = preload("res://src/presentation/models/equipment_presentation_model.gd")
const PlayerFacingStatusScript = preload("res://src/presentation/player_facing_status.gd")
const CombatSkillIconsScript = preload("res://src/presentation/combat_skill_icons.gd")
const ProgressionIconsScript = preload("res://src/presentation/progression_icons.gd")
const EarlySkillRegistryScript = preload("res://src/content/early_skill_registry.gd")
const EarlyInterfaceVocabularyScript = preload("res://src/content/early_interface_vocabulary.gd")
## The forge authority owns the highest legal affix tier. Presentation reads this
## public contract only to stop offering a reveal the authority will reject.
const LawForgeScript = preload("res://src/systems/law_forge.gd")
const UiKit := preload("res://src/presentation/ui_kit.gd")
const FacilityItemText := preload("res://src/presentation/facility/item_text.gd")

const FACILITY_TITLES: Dictionary = {
	"loadout": "Loadout · Equipment and Runes",
	"forge": "Tempering Anvil · Law Token Forge",
	"training": "Training · Trials and Reports",
	"proxy": "Proxy Bay · Core Assembly",
	"immortality": "Eternal Altar · Immortality",
	"research": "Research · Laws and Fragments",
}
## One 18px neutral line under the Chinese title, stating what the page can and
## cannot do. The route id stays the lookup key, so a title can be reworded
## without moving a single published cell.
const FACILITY_SUBTITLES: Dictionary = {
	"loadout": "Choose loot and compare the effects of equipping it",
	"forge": "Forecasts are free; Law Tokens are spent only when you commit",
	"training": "Fire an arrow and see how far your equipment can take its chain",
	"proxy": "Assemble four slots; the proxy build freezes when the contract starts",
	"immortality": "Midgame content; this page is a roadmap only",
	"research": "Only discovered conclusions and missing interfaces are shown",
}
## Published Chinese names of the item parameters the item tables modify. Only a
## parameter the project already names under the same key is translated; every
## other parameter keeps its raw key on the card instead of borrowing a name it
## does not own.
## The two operations the item tables use, written the way a player reads one real
## modifier: damage multiply 1.12 -> Damage×1.12. Any other operation keeps its raw
## word, so an unknown operation is never dressed up as a symbol it may not mean.
const FORGE_TRACKS: Array[String] = ["inscribe", "rewrite", "refine"]
const FORGE_TRACK_TITLES: Dictionary = {
	"inscribe": "Inscribe",
	"rewrite": "Rewrite",
	"refine": "Refine",
}
## Surface copy for the published training terms only (early_items.json and
## ranger_presets.json). Interface names come from the shared content vocabulary.
const TRAINING_GROWTH_NAMES := {"convergent": "Convergent", "critical": "Critical", "exponential": "Exponential"}
const LAW_TALLY_LABELS: Dictionary = {
	"inscribe": "Inscribe Law Tokens",
	"rewrite": "Rewrite Law Tokens",
	"refine": "Refine Law Tokens",
}
## A raw identifier longer than this stops being readable copy and becomes
## reference data: the block keeps its Chinese name, its state and its actions on
## the surface and folds the raw field line behind its own disclosure.
const INSTANCE_ID_DISPLAY_LIMIT := 24
## The page margin, in one place: the header, the body and the composition frame all
## measure from it.
const PAGE_MARGIN := 20.0
## The vertical gap the page keeps between its header, its body and its footer. The
## composition frame subtracts both of them, so the frame is the room the body really
## has rather than the room the whole screen has.
const PAGE_ROW_GAP := 10.0
## Width reserved for the workspace's vertical scrollbar. A page whose content does not
## fit shows one, and that bar comes out of the width the body gets. It is reserved as a
## constant rather than measured: the bar appears and disappears while a page settles,
## and a frame that follows it would make the composition chase its own scrollbar.
const SCROLLBAR_RESERVE := 24.0
## The same budget for internal modifier entries: a base plus its affixes that
## stay under this many raw entries are still one readable line.
const RAW_FIELD_ENTRY_LIMIT := 3
## Node-name prefix per folded raw-field block owner. A folded block carries one
## stable toggle and keeps the original field line reachable under it.
const FIELD_BLOCK_TOGGLE_PREFIXES: Dictionary = {
	"current_item": "CurrentItemFieldsToggle",
	"candidate": "CandidateFieldsToggle",
}
## Controls whose names carry a stable semantic identity, so a rebuild can put the
## keyboard focus back on the same thing: the slot that is compared, one item's own
## disclosure, one item's actions, the two page-level switches. A control named by
## position alone is never restored — rebuilding between two different items would
## otherwise hand the focus to whatever now sits in that place.
const RESTORABLE_FOCUS_PREFIXES: Array[String] = [
	"LoadoutDetailsToggle", "SkillSummary_", "TrainingDetailsToggle", "ForgeTargetDetailsToggle",
	"SlotFocus_", "ConcernFocus_", "CandidateFieldsToggle_", "CurrentItemFieldsToggle_",
	"BackpackItem_", "Equip_", "Unequip_", "Salvage_", "ForgeCandidate_",
	"SelectForgeItem_", "FullItemDetails_", "BackpackPreviousPage", "BackpackNextPage",
	"ForgeOperation_", "ForgeReveal", "ForgeRevealMore", "ForgePreviousCandidate", "ForgeNextCandidate",
	"ForgeSelectCandidate", "ForgeConfirmSelection", "ForgeCancelSelection",
]

var _built := false
var _facility_id := "loadout"
var _profile: Dictionary = {}
var _last_result: Dictionary = {}
var _facility_data: Dictionary = {}
var _status_message := ""
## The open slot whose current item is compared against its same-slot
## candidates. Presentation state only: switching it emits nothing.
var _focus_slot := ""
## One settled drop the result screen asked this fresh loadout page to compare.
## It only changes the initial slot and candidate order; equipping remains an
## explicit action on the candidate card.
var _loadout_review_instance_id := ""
## Whether the resolved-Build detail block is unfolded. Presentation state only;
## it never changes what the page may do.
## Whether the training page's reference block is unfolded. It is its own switch:
## opening the loadout's detail block never opens this one, and neither of them
## changes what the page may read.
var _training_details_open := false
## Folded raw-field blocks the player has opened, by owner. Presentation state
## only: unfolding a long instance id or an internal modifier line never emits an
## action and never changes a payload.
var _open_field_blocks: Dictionary = {}
## The player's place in the page, kept across the body rebuild every disclosure
## switch performs: the workspace and candidate-list offsets as they were, and the
## stable name of the control the press came from. Presentation state only — the
## values are read back into controls that still mean the same thing, never into an
## action payload.
var _pending_scroll_restore: Dictionary = {}
## The restorable control by its own name: {"name": stable node name, "root": "cards"
## for a control the body built, "" for one in the fixed page frame}.
var _pending_focus_restore: Dictionary = {}
## Set while the compared slot is switching: the candidate list that follows is a
## different list, so the place read before the rebuild leaves its offset out.
var _slot_switch_pending := false
var _facility_switch_pending := false
## The lead row of the current page: the published facility mark plus the page's
## own overview panels. Rebuilt with the body, never reused across presents.
var _lead_row: HBoxContainer
## The concept composition root of the current page (the row the whole loadout or
## forge layout is built inside), and the size it was frozen with. Presentation
## only: a probe resolves the frame the page really laid out by name instead of
## assuming one. FacilityLayout owns the arithmetic behind it.
var _facility_root: Control = null
var _layout_frame := Vector2.ZERO
## Whether a freeze is already scheduled for this frame, so a rebuild never queues a
## second one.
var _freeze_queued := false
## Forge presentation cursor. Browsing remains local and free; selecting a complete
## future is an explicit domain action, and the separately rendered confirm button is
## the only path that spends a Law Tally.
var _forge_operation := "inscribe"
var _forge_candidate_index := 0
var _forge_committed_session_id := ""
var _candidate_query := EquipmentFilterBarScript.default_query()
var _candidate_filter_bar: Control
var _candidate_results: VBoxContainer
var _loadout_empty_hint: VBoxContainer
## Presentation-only backpack inspection. The domain target/equipped build stays
## authoritative until an explicit action is emitted from the shared detail pane.
var _loadout_backpack_selection := ""
## A click/controller activation pins inspection while hover remains transient.
## This is presentation state only; equip/unequip still require their own actions.
var _loadout_backpack_pinned_id := ""
var _loadout_detail_pointer_inside := false
var _forge_backpack_selection := ""
var _loadout_backpack_detail: VBoxContainer = null
var _forge_backpack_detail: VBoxContainer = null
var _loadout_backpack_detail_region: Control = null
var _forge_backpack_detail_region: Control = null
var _loadout_backpack_items: Array = []
var _forge_backpack_items: Array = []
var _loadout_backpack_equipped_id := ""
## The frames the last few freezes measured and what they did with each one, so a
## probe can see whether the composition settled instead of inferring it from sizes.
var _freeze_trace: Array[String] = []
## Every frame the freeze measured, newest last.
var _frames_seen: Array[String] = []
## Route the previous present() call showed, so a rebuild can keep the focused
## slot and the forge cursor while a freshly opened page starts at its first one.
var _previous_facility := ""
var _salvage_dialog: ConfirmationDialog
var _pending_salvage: Dictionary = {}
var _skill_detail_dialog: AcceptDialog
var _skill_detail_reading_surface: Panel
var _skill_detail_scroll: ScrollContainer
var _skill_detail_text: Label
var _recessed_panel_textures: Dictionary = {}
var _item_detail_dialog: AcceptDialog
var _item_detail_scroll: ScrollContainer
var _item_detail_dialog_text: Label
var _item_detail_return_focus: Control
var _facility_icon: TextureRect
var _title_label: Label
var _subtitle_label: Label
var _cards_scroll: ScrollContainer
var _cards_width_row: HBoxContainer
var _cards: VBoxContainer
var _footer: VBoxContainer
var _actions: HBoxContainer
var _status_label: Label
## The pinned header row. Kept so the composition frame can subtract the height it
## really takes instead of assuming one.
var _header_row: HBoxContainer
var _back_button: Button
var _art = FacilityArtScript.new()
var _readable_build = PlayerReadableBuildScript.new()
var _equipment_model: EquipmentPresentationModelScript = null
var _skill_registry = EarlySkillRegistryScript.new()
var _skill_icons = CombatSkillIconsScript.new()
var _progression_icons = ProgressionIconsScript.new()
var _art_errors: Array[String] = []
## The hero preview of the loadout page, kept so the page can report the exact
## frame it drew. Presentation only; it owns no gameplay state.
var _character_view: Control = null
## The generational trace of the training page's matching report, kept so the
## page can report which axis and points it really drew.
var _training_trace: Control = null


func _ready() -> void:
	_skill_registry.load_all()
	if not _skill_icons.load_icons():
		_art_errors.append(String(_skill_icons.pending_reason))
	_progression_icons.load_icons()
	_build_ui()
	_apply_presentation()
	call_deferred("_seed_entry_focus")
	# A page laid out for the frame it was built in re-freezes when that frame changes:
	# a resized host or a resized window re-runs the composition once instead of leaving
	# every cell sized for a frame that is gone.
	resized.connect(_on_frame_resized)


func _seed_entry_focus() -> void:
	# Start keyboard navigation on a safe, persistent action. Rebuilds use the
	# existing semantic focus restoration; this runs only when the screen enters.
	if not is_inside_tree() or not is_visible_in_tree():
		return
	if get_viewport().gui_get_focus_owner() == null and _pending_focus_restore.is_empty():
		_back_button.grab_focus()


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	var key := key_event.keycode if key_event.keycode != KEY_NONE else key_event.physical_keycode
	if not key_event.pressed or key_event.echo or key != KEY_ESCAPE:
		return
	for dialog in [_salvage_dialog, _skill_detail_dialog, _item_detail_dialog]:
		if dialog != null and dialog.visible:
			return
	var focus_owner := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if focus_owner is LineEdit or focus_owner is TextEdit:
		focus_owner.release_focus()
		get_viewport().set_input_as_handled()
		return
	_on_base_pressed()
	get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	var key := key_event.keycode if key_event.keycode != KEY_NONE else key_event.physical_keycode
	if not key_event.pressed or key_event.echo or key != KEY_ESCAPE:
		return
	for dialog in [_salvage_dialog, _skill_detail_dialog, _item_detail_dialog]:
		if dialog != null and dialog.visible:
			return
	var focus_owner := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if focus_owner is LineEdit or focus_owner is TextEdit:
		focus_owner.release_focus()
		get_viewport().set_input_as_handled()


func _on_frame_resized() -> void:
	if not _freeze_queued:
		_freeze_queued = true
		call_deferred("_freeze_layout")


func present(
	facility_id: String,
	profile: Dictionary,
	last_result: Dictionary = {},
	status_message: String = "",
	facility_data: Dictionary = {}
) -> void:
	var previous_facility := _facility_id
	_facility_id = facility_id.strip_edges().to_lower()
	_profile = profile.duplicate(true)
	_last_result = last_result.duplicate(true)
	_facility_data = facility_data.duplicate(true)
	_equipment_model = EquipmentPresentationModelScript.new(
		_readable_build,
		UiKit.as_dictionary(_facility_data.get("base_items", {})),
		UiKit.as_dictionary(_facility_data.get("affix_families", {})),
		UiKit.as_dictionary(_facility_data.get("salvage_previews", {}))
	)
	if _facility_id == "loadout":
		var context := UiKit.as_dictionary(_facility_data.get("initial_focus", {}))
		var return_route := String(_facility_data.get("return_route", context.get("return_route", "")))
		if return_route != "result":
			_loadout_review_instance_id = ""
		elif not context.is_empty():
			# Only a fresh transition reapplies focus and clears filters. A domain
			# action may re-present this page with the persistent return route but
			# must not turn that refresh into another initial-navigation event.
			_loadout_review_instance_id = ""
			_apply_initial_loadout_focus()
	else:
		_loadout_review_instance_id = ""
	_status_message = status_message
	_sync_back_button()
	_pending_salvage = {}
	if _salvage_dialog != null and _salvage_dialog.visible:
		_salvage_dialog.hide()
	if _skill_detail_dialog != null and _skill_detail_dialog.visible:
		_skill_detail_dialog.hide()
	if _facility_id == "forge":
		_forge_operation = String(_facility_data.get("operation", "inscribe"))
		if _forge_operation not in FORGE_TRACKS:
			_forge_operation = "inscribe"
		_forge_page()._restore_forge_session_cursor()
	if previous_facility != _facility_id:
		_training_details_open = false
		_open_field_blocks.clear()
		# A different page is a different place: it starts at its own first screen
		# instead of restoring an offset or a focus that belonged to the page before.
		_pending_scroll_restore.clear()
		_pending_focus_restore.clear()
		_loadout_backpack_selection = ""
		_loadout_backpack_pinned_id = ""
		_loadout_detail_pointer_inside = false
		_forge_backpack_selection = ""
	_previous_facility = previous_facility
	_facility_switch_pending = previous_facility != _facility_id
	if previous_facility != _facility_id and _cards_scroll != null:
		_cards_scroll.scroll_vertical = 0
	if _built:
		_apply_presentation()


func _apply_initial_loadout_focus() -> void:
	var context := UiKit.as_dictionary(_facility_data.get("initial_focus", {}))
	var instance_id := String(context.get("review_instance_id", "")).strip_edges()
	var slot := String(context.get("focus_slot", "")).strip_edges()
	if instance_id.is_empty() or slot.is_empty() or slot not in UiKit.as_array(_facility_data.get("prototype_open_slots", [])):
		return
	for raw_item in UiKit.as_array(_facility_data.get("inventory_equipment", [])):
		if not raw_item is Dictionary:
			continue
		var item: Dictionary = raw_item
		if String(item.get("instance_id", "")) != instance_id or String(item.get("slot", "")) != slot:
			continue
		_focus_slot = slot
		_loadout_review_instance_id = instance_id
		# A direct result action must reveal the requested item. Filters from a reused
		# screen are presentation state and cannot hide the explicit review target.
		_candidate_query = EquipmentFilterBarScript.default_query()
		return


func _build_ui() -> void:
	if _built:
		return
	_built = true
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = ShellThemeScript.create()
	# One read-only load for the whole screen. A missing or malformed package is
	# reported once and leaves the pages text-only; it never draws a stand-in.
	if not _art.load_art():
		_art_errors.append(String(_art.pending_reason))

	ShellThemeScript.add_backdrop(self, "facility_screen")

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, int(PAGE_MARGIN))
	add_child(margin)

	var page := VBoxContainer.new()
	page.name = "FacilityPage"
	page.add_theme_constant_override("separation", 10)
	margin.add_child(page)

	# Pinned header: a 30px bone Chinese title with one 18px neutral state line,
	# and the return button laid out in the same row instead of floating over the
	# page. Nothing here scrolls, so it cannot end up behind a tall page.
	var header := HBoxContainer.new()
	header.name = "FacilityHeader"
	header.add_theme_constant_override("separation", 14)
	page.add_child(header)
	_header_row = header
	_title_label = Label.new()
	_title_label.name = "FacilityTitle"
	_title_label.add_theme_font_size_override("font_size", 30)
	_title_label.add_theme_color_override("font_color", ShellThemeScript.BONE)
	header.add_child(_title_label)
	_subtitle_label = Label.new()
	_subtitle_label.name = "FacilitySubtitle"
	_subtitle_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_subtitle_label.add_theme_font_size_override("font_size", 18)
	_subtitle_label.add_theme_color_override("font_color", ShellThemeScript.NEUTRAL)
	header.add_child(_subtitle_label)
	_back_button = Button.new()
	_back_button.name = "ReturnToBaseButton"
	_back_button.text = "Hub"
	_back_button.tooltip_text = "Return to Hub"
	# A wrapping Button reports a one-pixel minimum width, so in a plain row it would
	# be squeezed to its own padding and wrap into a tall empty box. The return button
	# is a fixed short label: give it the width its text needs on one line.
	_back_button.custom_minimum_size = Vector2(120, 0)
	_back_button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_back_button.pressed.connect(_on_base_pressed)
	header.add_child(_back_button)

	# One vertical workspace: pages scroll inside it, horizontally disabled so a
	# long name can only wrap, never push the page sideways.
	_cards_scroll = ScrollContainer.new()
	_cards_scroll.name = "FacilityCardsScroll"
	_cards_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_cards_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# Keep the normal scroll thumb visible: long inventories and protocols must
	# advertise that their clipped lower content can be reached.
	page.add_child(_cards_scroll)
	_cards_width_row = HBoxContainer.new()
	_cards_width_row.name = "FacilityBodyWidthRow"
	_cards_width_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cards_width_row.add_theme_constant_override("separation", 0)
	_cards_scroll.add_child(_cards_width_row)
	var left_body_gutter := Control.new()
	left_body_gutter.name = "FacilityBodyLeftGutter"
	left_body_gutter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_body_gutter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cards_width_row.add_child(left_body_gutter)
	_cards = VBoxContainer.new()
	_cards.name = "FacilityBody"
	# The body uses the available width through 1600px windows, then remains a
	# centred reading column. This keeps 1920px copy from becoming very long lines
	# while the adaptive shell still uses the full window for its pinned furniture.
	_cards.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_cards.add_theme_constant_override("separation", 10)
	_cards_width_row.add_child(_cards)
	var right_body_gutter := Control.new()
	right_body_gutter.name = "FacilityBodyRightGutter"
	right_body_gutter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_body_gutter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cards_width_row.add_child(right_body_gutter)

	# Pinned footer: status line above the page's own always-reachable controls.
	_footer = VBoxContainer.new()
	_footer.name = "FacilityFooter"
	_footer.add_theme_constant_override("separation", 8)
	page.add_child(_footer)
	_status_label = Label.new()
	_status_label.name = "FacilityStatus"
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_font_size_override("font_size", 18)
	_status_label.add_theme_color_override("font_color", ShellThemeScript.PROXY)
	_footer.add_child(_status_label)
	_actions = HBoxContainer.new()
	_actions.name = "FacilityFooterActions"
	_actions.add_theme_constant_override("separation", 10)
	_footer.add_child(_actions)

	_salvage_dialog = ConfirmationDialog.new()
	_salvage_dialog.name = "SalvageConfirmation"
	_salvage_dialog.title = "Confirm Salvage"
	_salvage_dialog.ok_button_text = "Confirm Salvage"
	_salvage_dialog.cancel_button_text = "Cancel"
	_salvage_dialog.confirmed.connect(_on_salvage_confirmed)
	_salvage_dialog.canceled.connect(_on_salvage_canceled)
	_salvage_dialog.close_requested.connect(_on_salvage_canceled)
	add_child(_salvage_dialog)

	_skill_detail_dialog = AcceptDialog.new()
	_skill_detail_dialog.name = "SkillDetailDialog"
	_skill_detail_dialog.title = "Full Skill Details"
	_skill_detail_dialog.ok_button_text = "Close"
	_skill_detail_dialog.dialog_autowrap = false
	_skill_detail_dialog.about_to_popup.connect(_layout_skill_detail_dialog)
	_skill_detail_dialog.size_changed.connect(_layout_skill_detail_dialog)
	add_child(_skill_detail_dialog)
	# AcceptDialog's stock label makes the window grow with a long description.
	# Leave it empty and render the complete player copy in the bounded scroll region
	# below the title and above the fixed close button.
	_skill_detail_dialog.get_label().visible = false
	# Recess only this long reading area. The authored cloth/wood/copper window
	# stays visible around it; the translucent cold cloth ground quiets its weave
	# beneath the complete text without modulating the text or any other dialog.
	_skill_detail_reading_surface = Panel.new()
	_skill_detail_reading_surface.name = "SkillDetailReadingSurface"
	_skill_detail_reading_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var reading_ground := StyleBoxFlat.new()
	reading_ground.bg_color = Color(0.114, 0.153, 0.192, 0.94)
	reading_ground.border_color = Color("594e40")
	reading_ground.set_border_width_all(1)
	_skill_detail_reading_surface.add_theme_stylebox_override("panel", reading_ground)
	_skill_detail_dialog.add_child(_skill_detail_reading_surface)
	_skill_detail_scroll = ScrollContainer.new()
	_skill_detail_scroll.name = "SkillDetailScroll"
	_skill_detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_skill_detail_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_skill_detail_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	_skill_detail_dialog.add_child(_skill_detail_scroll)
	_skill_detail_text = Label.new()
	_skill_detail_text.name = "SkillDetailText"
	_skill_detail_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_skill_detail_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_skill_detail_text.add_theme_font_size_override("font_size", 22)
	_skill_detail_text.add_theme_constant_override("line_spacing", 4)
	_skill_detail_text.add_theme_color_override("font_color", ShellThemeScript.BONE)
	_skill_detail_scroll.add_child(_skill_detail_text)

	_item_detail_dialog = AcceptDialog.new()
	_item_detail_dialog.name = "ItemDetailDialog"
	_item_detail_dialog.title = "Full Equipment Details"
	_item_detail_dialog.ok_button_text = "Close"
	_item_detail_dialog.dialog_autowrap = false
	_item_detail_dialog.about_to_popup.connect(_layout_item_detail_dialog)
	_item_detail_dialog.size_changed.connect(_layout_item_detail_dialog)
	_item_detail_dialog.confirmed.connect(_on_item_detail_closed)
	_item_detail_dialog.canceled.connect(_on_item_detail_closed)
	_item_detail_dialog.close_requested.connect(_on_item_detail_closed)
	add_child(_item_detail_dialog)
	_item_detail_dialog.get_label().visible = false
	_item_detail_scroll = ScrollContainer.new()
	_item_detail_scroll.name = "ItemDetailScroll"
	_item_detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_item_detail_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_item_detail_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	_item_detail_dialog.add_child(_item_detail_scroll)
	_item_detail_dialog_text = Label.new()
	_item_detail_dialog_text.name = "ItemDetailText"
	_item_detail_dialog_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_item_detail_dialog_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_item_detail_dialog_text.add_theme_font_size_override("font_size", 22)
	_item_detail_dialog_text.add_theme_color_override("font_color", ShellThemeScript.BONE)
	_item_detail_scroll.add_child(_item_detail_dialog_text)
	_sync_back_button()


func _sync_back_button() -> void:
	if _back_button == null:
		return
	var context := UiKit.as_dictionary(_facility_data.get("initial_focus", {}))
	var return_route := String(_facility_data.get("return_route", context.get("return_route", "")))
	_back_button.text = "Results" if return_route == "result" else "Hub"
	_back_button.tooltip_text = "Return to Results" if return_route == "result" else "Return to Hub"


func _apply_presentation() -> void:
	# The rebuild below frees the focused control and resets every scroll region, so
	# the player's place is read while the old body is still alive. A switch that
	# rebuilds because the compared slot changed has no list to return to: its saved
	# offset does not resolve to a node any more, which is how the comparison starts
	# at its first candidate.
	var switched_facility := _facility_switch_pending
	if switched_facility:
		_pending_scroll_restore.clear()
		_pending_focus_restore.clear()
		if _cards_scroll != null:
			_cards_scroll.scroll_vertical = 0
	else:
		_read_presentation_place(not _slot_switch_pending)
	_facility_switch_pending = false
	_slot_switch_pending = false
	UiKit.clear_children(_cards)
	UiKit.clear_children(_actions)
	_facility_icon = null
	_lead_row = null
	_facility_root = null
	_character_view = null
	_training_trace = null
	_loadout_backpack_detail = null
	_candidate_filter_bar = null
	_candidate_results = null
	_loadout_empty_hint = null
	_forge_backpack_detail = null
	_loadout_backpack_detail_region = null
	_loadout_detail_pointer_inside = false
	_forge_backpack_detail_region = null
	_loadout_backpack_items = []
	_forge_backpack_items = []
	_loadout_backpack_equipped_id = ""
	# The frame comes first: every builder below reads it, so the body is always laid
	# out for the frame the layout module names, including the very first build.
	_layout_frame = _measure_layout_frame()
	_cards.custom_minimum_size.x = _layout_frame.x
	_title_label.text = String(FACILITY_TITLES.get(_facility_id, "Unknown Facility"))
	_subtitle_label.text = String(FACILITY_SUBTITLES.get(_facility_id, "UNKNOWN FACILITY · This entry is not registered"))
	# The mark belongs to the page, not to one data branch: it is placed before any
	# builder runs, so a page that has no snapshot still shows its own published
	# cell instead of dropping it.
	# Forge owns its compact mark for every nonempty snapshot, even without "ok".
	if _has_page_mark() and not (_facility_id == "forge" and not _facility_data.is_empty()) and not (_facility_id == "loadout" and _has_real_loadout_data()):
		_page_lead_row()

	match _facility_id:
		"loadout":
			_loadout_page()._build_loadout()
		"forge":
			_forge_page()._build_forge()
		"training":
			_training_page()._build_training()
		"proxy":
			_proxy_page()._build_proxy()
		"immortality":
			_build_immortality()
		"research":
			_build_research()
		_:
			_add_card("Unrecognized Facility", "id: %s\nThis entry is not registered. No action was performed." % _facility_id)

	_status_label.text = PlayerFacingStatusScript.message(_status_message)
	_status_label.visible = not _status_message.is_empty()
	_restore_switched_place()
	if switched_facility:
		call_deferred("_reset_workspace_scroll")
	if not _freeze_queued:
		_freeze_queued = true
		call_deferred("_freeze_layout")


func _reset_workspace_scroll() -> void:
	_pending_scroll_restore.clear()
	if _cards_scroll != null:
		_cards_scroll.scroll_vertical = 0


## The workspace the body is laid out in. It is taken from the viewport the screen is
## drawn in, minus the fixed page furniture (margin, header, status line, row gaps),
## and never from a container the body itself sizes: a scrolling area's width depends
## on how wide its content wants to be, so measuring the frame there would make the
## frame depend on the body it is supposed to decide. The viewport answer is available
## even on the very first build, before this control has been given a rect of its own,
## which is why the first page a player sees is already the concept composition.
## The height is what the area would have if this page did not scroll, so the
## composition's fit test answers the real question — would the decision have fitted —
## instead of re-reading the scrollbar it may have caused.
func _measure_layout_frame() -> Vector2:
	var outer := get_viewport_rect().size
	if get_parent() is Control and (get_parent() as Control).size.x > 1.0:
		outer = (get_parent() as Control).size
	return FacilityLayoutScript.frame(outer,_facility_id)


func _freeze_layout() -> void:
	_freeze_queued = false
	if not _built or _cards_scroll == null or _cards == null:
		return
	_sync_cards_min_height()
	var measured := _measure_layout_frame()
	if not _layout_needs_rebuild(_layout_frame, measured):
		# The frame has stopped meaning anything new: adopt the reading and keep the
		# body that is already laid out in it. A scrollbar appearing can move the frame
		# by its own width from one sort to the next, and rebuilding on that would chase
		# a wobble instead of the composition.
		if measured.y > 0.0:
			_layout_frame = measured
		_note_freeze("%s keep" % str(measured))
		_restore_switched_place_late()
		return
	_layout_frame = measured
	_note_freeze("%s rebuild" % str(measured))
	_apply_presentation()
	_restore_switched_place_late()


func _note_freeze(entry: String) -> void:
	_freeze_trace.append(entry)
	if _freeze_trace.size() > 8:
		_freeze_trace.remove_at(0)


## The place the player is in right now, read before a rebuild tears the body down:
## the workspace offset, the same-slot candidate list offset, and the control that
## holds the keyboard focus. The workspace is read from the control this screen owns,
## not searched for below the page root — it is the page's ancestor, so a search there
## would never find it. Only a control with a stable semantic name is recorded as the
## focus: a page without focus and without scroll keeps an empty record instead of
## inventing a place to return to.
func _read_presentation_place(keep_candidate_offset := true) -> void:
	_pending_scroll_restore.clear()
	_pending_focus_restore = {}
	if _cards_scroll != null:
		_pending_scroll_restore["FacilityCardsScroll"] = _cards_scroll.scroll_vertical
	if keep_candidate_offset and _facility_root != null:
		var candidates := _facility_root.find_child("EquipmentBackpack", true, false)
		if candidates != null and candidates.has_method("page_index"):
			_pending_scroll_restore["EquipmentBackpackPage"] = int(candidates.call("page_index"))
	var viewport := get_viewport()
	if viewport != null:
		var owner := viewport.gui_get_focus_owner()
		if owner != null and owner != self and is_ancestor_of(owner):
			_pending_focus_restore = _restorable_focus(owner)


## The identity a rebuild may put the keyboard focus back on: the control's own stable
## name and which of the two roots it lives in. A name that is only positional, an
## engine-generated `@VBoxContainer@N`, or a control that is not one of the page's
## semantic actions records nothing, so the focus can never land on whatever happens to
## sit in that place after the rebuild.
func _restorable_focus(control: Control) -> Dictionary:
	if control == null:
		return {}
	var name := String(control.name)
	if name.is_empty() or name.begins_with("@"):
		return {}
	var allowed := false
	for prefix in RESTORABLE_FOCUS_PREFIXES:
		if name.begins_with(prefix):
			allowed = true
			break
	if not allowed:
		return {}
	if _cards != null and _cards.is_ancestor_of(control):
		return {"name":name, "root":"cards"}
	if is_ancestor_of(control):
		return {"name":name, "root":""}
	return {}


## After the rebuilt body exists, the offsets across the rebuild are put back. The
## workspace scroll region belongs to this screen and outlives the body, so its offset
## is written on the control itself instead of being searched for below the page root
## (where it does not live). The candidate list is a new node below that root, and a
## list whose name is not there any more — the one a slot switch replaced — stays at
## its own first row rather than borrowing the offset of a list it never was.
func _restore_switched_place() -> void:
	var workspace_offset: Variant = _pending_scroll_restore.get("FacilityCardsScroll", null)
	if workspace_offset != null and _cards_scroll != null:
		_cards_scroll.scroll_vertical = int(workspace_offset)
	var candidate_page: Variant = _pending_scroll_restore.get("EquipmentBackpackPage", null)
	if candidate_page == null or _facility_root == null:
		return
	var candidates := _facility_root.find_child("EquipmentBackpack", true, false)
	if candidates != null and candidates.has_method("set_page"):
		candidates.call("set_page", int(candidate_page))


## The control the recorded identity names in the body that is on screen now, or null
## when it was not rebuilt, cannot take focus any more, or sits in a state that should
## not be focused: a different item, a disabled action or a hidden block means the page
## changed shape, and a control the player never used is not a safe place to land.
func _focused_control() -> Control:
	if _pending_focus_restore.is_empty():
		return null
	var root_name := String(_pending_focus_restore.get("root", ""))
	var anchor: Node = _cards if root_name == "cards" else self
	if anchor == null:
		return null
	var control := _named_control(anchor, String(_pending_focus_restore.get("name", "")))
	if control == null or not control.is_inside_tree() or control.focus_mode == Control.FOCUS_NONE:
		return null
	if not control.is_visible_in_tree():
		return null
	var button := control as Button
	if button != null and button.disabled:
		return null
	return control


## One named control below an anchor, searched by the page's own semantic names. The
## engine's `@VBoxContainer@N` placeholders are skipped: they name a position, and a
## position is not an identity. The search walks the tree directly because the page
## builds its body in code, so its children carry no owner for find_child() to accept.
func _named_control(anchor: Node, control_name: String) -> Control:
	if control_name.is_empty() or control_name.begins_with("@"):
		return null
	for child: Node in anchor.get_children():
		if String(child.name) == control_name:
			return child as Control
		var found := _named_control(child, control_name)
		if found != null:
			return found
	return null


## The second half of the same restore, run once the rebuilt containers have sorted:
## a scrollbar whose range only exists after that sort clamps the saved offset itself,
## and the freed control has released the focus by then. Restoring it is what keeps Tab
## moving from the control the player just used; a rebuilt page that no longer has that
## control simply stays without one, exactly as it did before.
func _restore_switched_place_late() -> void:
	if _pending_focus_restore.is_empty() and _pending_scroll_restore.is_empty():
		return
	_restore_switched_place()
	if _pending_focus_restore.is_empty():
		return
	var restored := _focused_control()
	if restored == null:
		return
	var viewport := get_viewport()
	if viewport != null and viewport.gui_get_focus_owner() != restored:
		restored.grab_focus()


## Whether a frame change is worth rebuilding the body for: the decision the layout
## module makes (how many columns the slot grid has, whether the hero stands beside
## the slots) or a real change in the frame the composition is measured against.
## A difference that flips nothing keeps the frame the page was built with, so the
## page settles instead of rebuilding on every scrollbar.
func _layout_needs_rebuild(previous: Vector2, measured: Vector2) -> bool:
	return previous.distance_to(measured) > 1.0


func _sync_cards_min_height() -> void:
	if _cards_scroll == null or _cards == null:
		return
	_cards.custom_minimum_size = Vector2(_layout_frame.x, 0.0)


## The concept composition of the page that is on screen right now: the frame it
## was frozen with, whether the decision fits inside that frame without scrolling,
## and the slot grid the loadout page really laid out. A probe reads this instead of
## re-deriving the frame from node positions; every number is the one the page built
## with. Pure report: reading it changes nothing.
func layout_report() -> Dictionary:
	var report := {
		"facility": _facility_id,
		"frame": [_layout_frame.x, _layout_frame.y],
		"root": "" if _facility_root == null else String(_facility_root.name),
	}
	if _facility_id == "loadout":
		report["regions"] = FacilityLayoutScript.loadout_regions(Vector2(_layout_frame.x,maxf(570,_layout_frame.y)))
	else:
		report["column_rects"] = FacilityLayoutScript.columns(_layout_frame, FacilityLayoutScript.FORGE_WEIGHTS)
	if _facility_id in ["loadout", "forge"]:
		report["backpack_rect"] = _reported_node_rect("EquipmentBackpack")
		report["detail_rect"] = _reported_node_rect("BackpackDetail")
		var backpack_actions := find_child("BackpackActions", true, false) as Control
		report["action_rect"] = backpack_actions.get_global_rect() if backpack_actions != null else _reported_node_rect("FacilityFooterActions")
		var detail_node := find_child("BackpackDetail", true, false) as Control
		report["detail_visible"] = detail_node != null and detail_node.visible
	report["visual_fit_verified"] = false
	return report


## Stable integration queries for UI probes and input adapters. Callers never need
## to know the grid's internal container hierarchy.
func backpack_cell(instance_id: String) -> Control:
	var backpack := find_child("EquipmentBackpack", true, false)
	if backpack != null and backpack.has_method("get_cell"):
		return backpack.call("get_cell", instance_id) as Control
	return null


func backpack_detail() -> Control:
	return find_child("BackpackDetail", true, false) as Control


func _reported_node_rect(node_name: String) -> Rect2:
	var node := find_child(node_name, true, false) as Control
	return Rect2() if node == null else node.get_global_rect()


## The facility mark cell. Most pages use the published native size. A dense
## workstation may request one explicit compact nearest-neighbour size so its art
## shares a row with the active target instead of pushing the controls below the
## viewport.
func _add_facility_mark(parent: Container, compact_size: Vector2i = Vector2i.ZERO) -> void:
	var mark: Texture2D = _art.mark(_facility_id) if _art.is_ready() else null
	if mark != null:
		var mark_size: Vector2i = compact_size if compact_size.x > 0 and compact_size.y > 0 else _art.mark_size(_facility_id)
		_facility_icon = _icon_node(mark, mark_size, false)
		_facility_icon.name = "FacilityMark"
		_facility_icon.set_meta("canonical_id", "facility.%s" % _art.facility_key(_facility_id))
		parent.add_child(_facility_icon)


## Overview cell holding the mark at its published size. A mark is wider than the
## text column, so it gets its own column instead of pushing the title row down.
## Returns null when this page has no published cell, so the caller never
## reserves an empty column.
func _mark_cell(caption: String) -> VBoxContainer:
	var cell := VBoxContainer.new()
	cell.name = "FacilityMarkCell"
	cell.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	cell.add_theme_constant_override("separation", 6)
	_add_facility_mark(cell)
	if _facility_icon == null:
		cell.free()
		return null
	if not caption.is_empty():
		cell.add_child(_note_label(caption))
	return cell


## True when this route has a published mark. Pages without one keep their
## text-only header.
func _has_page_mark() -> bool:
	return _art.is_ready() and _art.mark(_facility_id) != null


## The lead row, created on first use inside the current page. Every facility page
## that has a mark starts with it, so the mark always appears in the same place.
func _page_lead_row() -> HBoxContainer:
	if _lead_row != null:
		return _lead_row
	_lead_row = _make_row("FacilityOverview")
	_cards.add_child(_lead_row)
	var cell := _mark_cell("")
	if cell != null:
		_lead_row.add_child(cell)
	return _lead_row


## A hard-edged workspace panel with a 22px heading. `parent` receives the panel
## and the returned VBox is its content, so a page lays out its own rows inside
## instead of feeding a generic card framework.
func _section_in(parent: Container, heading_text: String, node_name: String = "") -> VBoxContainer:
	var panel := PanelContainer.new()
	if not node_name.is_empty():
		panel.name = node_name
	panel.add_theme_stylebox_override("panel", _recessed_panel_style("well" if node_name.begins_with("CandidateListPanel_") else "panel"))
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	panel.add_child(content)
	if not heading_text.is_empty():
		content.add_child(_heading_label(heading_text))
	return content


func _section(heading_text: String, node_name: String = "") -> VBoxContainer:
	return _section_in(_cards, heading_text, node_name)


## The panel that wraps a section's content, for the few rows that have to bound
## or weigh a whole section.
func _section_panel(content: VBoxContainer) -> PanelContainer:
	return content.get_parent() as PanelContainer


func _make_row(node_name: String = "") -> HBoxContainer:
	var row := HBoxContainer.new()
	if not node_name.is_empty():
		row.name = node_name
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 12)
	return row


func _heading_label(text: String) -> Label:
	var label := _body_label(text)
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color("dcc494"))
	return label


## Page copy at the approved 20px body step. Every label wraps: a semantic name
## is never trimmed away to keep a column narrow.
func _body_label(text: String, color: Color = ShellThemeScript.BONE) -> Label:
	var label := Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", color)
	return label


## Secondary copy: states, reasons and hints. Never below the 18px floor.
func _note_label(text: String) -> Label:
	var label := _body_label(text, ShellThemeScript.NEUTRAL)
	label.add_theme_font_size_override("font_size", 18)
	return label


## "Key: Value" stays one Label so the value cannot be read without the key that
## names it, and text collection sees exactly what the screen shows.
func _fact_label(parent: Container, key: String, value: String, color: Color = ShellThemeScript.BONE) -> Label:
	var label := _body_label("%s: %s" % [key, value], color)
	parent.add_child(label)
	return label


## A real action button: same emitter, node name and payload contract as before,
## but it wraps instead of clipping, so a long item name stays whole.
func _action_button(parent: Container, label_text: String, action_id: String, payload: Dictionary, node_name: String) -> Button:
	var button := Button.new()
	if not node_name.is_empty():
		button.name = node_name
	button.text = label_text
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(_on_payload_action_pressed.bind(action_id, payload.duplicate(true)))
	parent.add_child(button)
	return button


## Slot emphasis: the focused slot uses the bright copper edge, an empty one a
## dim edge, a filled one the idle copper. The state word in the cell is what
## actually says which case this is; the edge only reinforces it.
func _slot_cell_box(focused: bool, empty: bool) -> StyleBox:
	var box := ShellThemeScript.panel_style("selected") if focused else _recessed_panel_style("disabled" if empty else "well")
	box.content_margin_left = 0
	box.content_margin_right = 0
	box.content_margin_top = 0
	box.content_margin_bottom = 0
	return box


## Only the authored nine-slice edge is recessed. Its cloth/wood center pixels,
## layout margins and all text/icon colours stay unchanged. Selected and focus
## skins never enter this local cache; no global theme or PNG is edited.
func _recessed_panel_style(kind: String = "well") -> StyleBoxTexture:
	var box := ShellThemeScript.panel_style(kind)
	if not _recessed_panel_textures.has(kind):
		var image := box.texture.get_image().duplicate() as Image
		if image.is_compressed():
			image.decompress()
		for y in image.get_height():
			for x in image.get_width():
				var edge_distance := mini(mini(x, image.get_width() - 1 - x), mini(y, image.get_height() - 1 - y))
				if edge_distance >= 12:
					continue
				var colour := image.get_pixel(x, y)
				var edge_gain := lerpf(0.72, 1.0, smoothstep(8.0, 12.0, float(edge_distance)))
				image.set_pixel(x, y, Color(colour.r * edge_gain, colour.g * edge_gain, colour.b * edge_gain, colour.a))
		_recessed_panel_textures[kind] = ImageTexture.create_from_image(image)
	box.texture = _recessed_panel_textures[kind]
	return box


## Builds one real TextureRect over a published atlas region. `scaled` is the
## integer 2x that only the 32x32 icon batch may use; a facility mark passes
## false and keeps its native pixel size so it is never resampled smaller.
func _icon_node(texture: Texture2D, native_size: Vector2i, scaled: bool) -> TextureRect:
	var display_size := native_size
	if scaled:
		display_size = native_size * FacilityArtScript.ICON_DISPLAY_SCALE
	return UiKit.icon_node(texture, Vector2(display_size), scaled, TextureRect.STRETCH_KEEP_ASPECT_CENTERED)

## The 64x64 display rect of a canonical id, or null when the package publishes
## nothing under it. Null means no image: the caller's own text stays the only
## disclosure, and `_art.missing_ids()` names the id for the report.
func _body_icon_texture(canonical_id: String) -> Texture2D:
	if canonical_id.strip_edges().is_empty() or not _art.is_ready():
		return null
	return _art.icon(canonical_id)


## A row of real item/slot icons. Empty when nothing resolves, so a page keeps
## exactly the text it had before.
func _add_icon_row(parent: Container, canonical_ids: Array, node_prefix: String) -> HBoxContainer:
	var icons: Array[Texture2D] = []
	var resolved: Array[String] = []
	for raw_id in canonical_ids:
		var canonical_id := String(raw_id)
		var texture := _body_icon_texture(canonical_id)
		if texture == null:
			continue
		icons.append(texture)
		resolved.append(canonical_id)
	if icons.is_empty():
		return null
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for index in icons.size():
		var icon := _icon_node(icons[index], FacilityArtScript.ICON_NATIVE_SIZE, true)
		icon.name = "%s_%s" % [node_prefix, UiKit.stable_node_token(resolved[index])]
		icon.set_meta("canonical_id", resolved[index])
		row.add_child(icon)
	parent.add_child(row)
	return row


## One 64x64 icon beside a text label, added as a row so the label keeps its own
## name, wording and wrap. Returns the row, or the untouched label in `parent`
## when the id resolves to nothing.
func _add_text_icon_row(
	parent: Container,
	canonical_id: String,
	label_node: Label,
	node_prefix: String,
	icon_name: String
) -> Control:
	var texture := _body_icon_texture(canonical_id)
	if texture == null:
		parent.add_child(label_node)
		return label_node
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var icon := _icon_node(texture, FacilityArtScript.ICON_NATIVE_SIZE, true)
	icon.name = "%s_%s" % [node_prefix, icon_name]
	icon.set_meta("canonical_id", canonical_id)
	row.add_child(icon)
	label_node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label_node)
	parent.add_child(row)
	return row


## Bounded columns: children never feed their content minimum back into the
## root page width. Each content lane scrolls locally if the text grows.
func _grid_cell_box() -> StyleBox:
	var box := _recessed_panel_style("well")
	box.content_margin_left = 8.0
	box.content_margin_top = 6.0
	box.content_margin_right = 8.0
	box.content_margin_bottom = 6.0
	return box


func _compact_skill_text(skill: Dictionary, slot_index: int) -> String:
	if skill.is_empty():
		return "Skill Slot %d\nDetails unavailable" % slot_index
	var bindings := UiKit.as_array(skill.get("key_bindings", []))
	var primary_binding := "Unbound"
	if not bindings.is_empty():
		primary_binding = String(bindings[0]).replace("Left Mouse Button", "Left-click").replace("Right Mouse Button", "Right-click")
	var ticks_per_second := maxi(1, _skill_registry.ticks_per_second)
	var cooldown_seconds := float(int(skill.get("cooldown_ticks", 0))) / float(ticks_per_second)
	return "%s\n%s %ss" % [
		String(skill.get("name", "Skill Slot %d" % slot_index)),
		primary_binding,
		("%.2f" % cooldown_seconds).trim_suffix("0").trim_suffix("0").trim_suffix("."),
	]


func _player_readable_skill_text(skill_id: String) -> String:
	var skill := _player_skill_entry(skill_id)
	return _readable_build.format_skill(skill) if not skill.is_empty() else ""


func _backpack_entries(items: Array, icon_prefix: String) -> Array:
	var entries: Array = []
	for raw_item in items:
		if not raw_item is Dictionary:
			continue
		var item: Dictionary = raw_item
		var instance_id := String(item.get("instance_id", ""))
		var canonical := _art.canonical_id("equipment_base", String(item.get("base_item_id", "")))
		entries.append({
			"instance_id": instance_id,
			"display_name": _equipment_model.display_name(item),
			"tooltip": "%s\n%s" % [_equipment_model.display_name(item), _equipment_model.compact_difference(item)],
			"canonical_id": canonical,
			"icon": _body_icon_texture(canonical),
			"icon_node_name": "%s_%s" % [icon_prefix, UiKit.stable_node_token(instance_id)],
			"status_label": "Equipped" if instance_id in UiKit.as_dictionary(UiKit.as_dictionary(_facility_data.get("active_build", {})).get("equipped_item_ids", {})).values() else ("This Run" if instance_id == _loadout_review_instance_id else ""),
		})
	return entries


func _add_interface_changes(parent: Container, preview: Dictionary) -> void:
	for key in ["interfaces_gained", "interfaces_lost"]:
		var names: Array[String] = []
		for value in preview.get(key, []):
			names.append(EarlyInterfaceVocabularyScript.player_name(String(value)))
		if not names.is_empty():
			var note := _note_label(("Gained: " if key == "interfaces_gained" else "Lost: ") + ", ".join(names))
			note.name = "InterfaceGained" if key == "interfaces_gained" else "InterfaceLost"
			note.add_theme_color_override("font_color", ShellThemeScript.PROXY if key == "interfaces_gained" else ShellThemeScript.WARNING)
			parent.add_child(note)


func _track_backpack_detail_actions(region: Control, route: String) -> void:
	if region == null:
		return
	for node in region.find_children("*", "BaseButton", true, false):
		var button := node as BaseButton
		var callback := _on_backpack_detail_action_focus_exited.bind(route)
		if not button.focus_exited.is_connected(callback):
			button.focus_exited.connect(callback)


func _on_backpack_detail_action_focus_exited(route: String) -> void:
	if route == "loadout":
		call_deferred("_finish_loadout_backpack_exit")
	elif route == "forge":
		call_deferred("_finish_forge_backpack_exit")


func _build_immortality() -> void:
	var section := _section("Midgame Content", "ImmortalityMidgame")
	section.add_child(_body_label("Immortality is a midgame system, not required for early quests.\nThis page is a roadmap only; no actions are available."))


func _build_research() -> void:
	var discoveries := _section("Discovered Conclusions", "ResearchDiscoveries")
	discoveries.add_child(_body_label("Convergent / Critical / Exponential and higher growth entries appear only after dummy or combat verification.\nProfile discovery tracking is not yet implemented."))
	var targets := _section("Target Research", "ResearchTargets")
	targets.add_child(_body_label("Choose mechanic tags and target Laws to track contract sources and guaranteed-drop progress.\nTarget selection and tracking are not yet implemented."))
	var missing := _section("Missing Interfaces", "ResearchMissingInterfaces")
	missing.add_child(_body_label("Requires: breedable events\nRequires: full-chain refresh\nRequires: result feedback\n\nItems should state what is missing, not present inactive terms as usable."))
	_add_action("View Discovered Conclusions", "inspect_discoveries")
	_add_action("Set as Research Target", "set_research_target")
	_add_action("Check Missing Interfaces", "inspect_missing_interfaces")


func _add_card(title_text: String, body_text: String, node_name: String = "") -> void:
	var panel := PanelContainer.new()
	if not node_name.is_empty():
		panel.name = node_name
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	panel.add_child(content)
	var heading := Label.new()
	heading.text = title_text
	heading.add_theme_font_size_override("font_size", 23)
	heading.add_theme_color_override("font_color", ShellThemeScript.PROXY)
	content.add_child(heading)
	var body := Label.new()
	body.text = body_text
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(body)
	_cards.add_child(panel)


func _add_action(label_text: String, action_id: String) -> void:
	var button := Button.new()
	button.text = label_text
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(_on_action_pressed.bind(action_id))
	_actions.add_child(button)


func _add_payload_action(label_text: String, action_id: String, payload: Dictionary, node_name: String = "") -> void:
	var button := Button.new()
	if not node_name.is_empty():
		button.name = node_name
	button.text = label_text
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(_on_payload_action_pressed.bind(action_id, payload.duplicate(true)))
	_actions.add_child(button)


## Same emitter as _add_payload_action, but the real button is wrapped in a named
## cell so a page can put one published icon beside it. The wrapper owns no
## input: the button keeps its own name, label, payload and disabled state.
func get_visible_text() -> String:
	var lines: Array[String] = []
	_collect_label_text(self, lines)
	return "\n".join(lines)


func get_action_button(node_name: String) -> Button:
	return find_child(node_name, true, false) as Button


func set_progression_icons(reader: RefCounted) -> void:
	_progression_icons = reader
	_apply_presentation()


## The header mark currently drawn: a published facility cell at its native
## size, or null when the page has no published cell and keeps text only.
func facility_mark() -> TextureRect:
	return _facility_icon


## One line per art package that failed to load, in load order. Empty when both
## production packages were read.
func art_errors() -> Array[String]:
	return _art_errors.duplicate()


## Progression icons are a separately delivered expansion. Their wait state is
## reported on its own channel, so an unpublished expansion cannot fail the
## already-accepted facility art package.
func progression_icon_errors() -> Array[String]:
	return [] if _progression_icons.is_ready() else [_progression_icons.pending_reason]


## Canonical ids this screen asked for and the packages do not publish, in
## first-request order. Reported, never drawn as something else.
func missing_art_ids() -> Array[String]:
	return _art.missing_ids()


func _collect_label_text(node: Node, lines: Array[String]) -> void:
	if node is Label and (node as Label).visible:
		lines.append((node as Label).text)
	for child in node.get_children():
		_collect_label_text(child, lines)


func _on_base_pressed() -> void:
	base_requested.emit()


func _on_action_pressed(action_id: String) -> void:
	action_requested.emit(_facility_id, action_id, {})


func _on_payload_action_pressed(action_id: String, payload: Dictionary) -> void:
	if _facility_id == "loadout" and action_id == "equip_item":
		_loadout_backpack_pinned_id = String(payload.instance_id)
	action_requested.emit(_facility_id, action_id, payload.duplicate(true))


## Thin forwarders: tests reach these moved text helpers through the screen
## instance, so the screen keeps the names and delegates to FacilityItemText.
func _law_token_name(operation: String, count: int = -1) -> String:
	return FacilityItemText.law_token_name(operation, count)


func _training_interface_text(value: Variant) -> String:
	return FacilityItemText.training_interface_text(value)


func _forge_candidate_result_item_view(candidate: Dictionary) -> Dictionary:
	return FacilityItemText.forge_candidate_result_item_view(candidate)


## The forge and training pages live in src/presentation/facility/; these thin
## accessors and forwarders keep the owner's method names for the remaining call
## sites, the tests, and the string-name deferred calls.
var _forge_page_impl  # untyped to avoid a preload cycle
func _forge_page() -> FacilityForgePage:
	if _forge_page_impl == null:
		_forge_page_impl = FacilityForgePage.new(self)
	return _forge_page_impl


var _training_page_impl  # untyped to avoid a preload cycle
func _training_page() -> FacilityTrainingPage:
	if _training_page_impl == null:
		_training_page_impl = FacilityTrainingPage.new(self)
	return _training_page_impl


func _forge_can_start() -> bool:
	return _forge_page()._forge_can_start()


func _forge_operation_block_reason(operation: String) -> String:
	return _forge_page()._forge_operation_block_reason(operation)


## Kept for the shared backpack-detail focus handler, which releases the forge
## inspection pane through a string-name deferred call.
func _finish_forge_backpack_exit() -> void:
	_forge_page()._finish_forge_backpack_exit()


## Kept for the tests and the concept report that read the training page's trace
## through the screen instance.
func training_trace_report() -> Dictionary:
	return _training_page().training_trace_report()


var _loadout_page_impl  # untyped to avoid a preload cycle
func _loadout_page() -> FacilityLoadoutPage:
	if _loadout_page_impl == null:
		_loadout_page_impl = FacilityLoadoutPage.new(self)
	return _loadout_page_impl


func _has_real_loadout_data() -> bool:
	return _loadout_page()._has_real_loadout_data()


## Kept for the skill detail dialog, whose signals are wired to the screen in
## _build_ui while the layout body belongs to the loadout page.
func _layout_skill_detail_dialog() -> void:
	_loadout_page()._layout_skill_detail_dialog()


func _player_skill_entry(skill_id: String) -> Dictionary:
	return _loadout_page()._player_skill_entry(skill_id)


func _slot_title(slot: String) -> String:
	return _loadout_page()._slot_title(slot)


## Kept for the shared backpack-detail focus handler, which releases the loadout
## inspection pane through a string-name deferred call.
func _finish_loadout_backpack_exit() -> void:
	_loadout_page()._finish_loadout_backpack_exit()


## Kept for the tests and the concept report that read the loadout page's hero
## preview through the screen instance.
func character_preview_report() -> Dictionary:
	return _loadout_page().character_preview_report()


var _proxy_page_impl  # untyped to avoid a preload cycle
func _proxy_page() -> FacilityProxyPage:
	if _proxy_page_impl == null:
		_proxy_page_impl = FacilityProxyPage.new(self)
	return _proxy_page_impl


## The shared item-detail surface lives in src/presentation/facility/; these thin
## forwarders keep its owner method names for the remaining page call sites and
## for the dialogs and their signals, which are wired to the screen in _build_ui.
var _item_detail_impl  # untyped to avoid a preload cycle
func _item_detail() -> FacilityItemDetail:
	if _item_detail_impl == null:
		_item_detail_impl = FacilityItemDetail.new(self)
	return _item_detail_impl


func _add_full_item_detail_button(parent: Container, item: Dictionary, title_text: String, detail_text: String) -> Button:
	return _item_detail()._add_full_item_detail_button(parent, item, title_text, detail_text)


func _show_item_detail(title_text: String, detail_text: String, source: Control) -> void:
	_item_detail()._show_item_detail(title_text, detail_text, source)


func _item_display_name(item: Dictionary) -> String:
	return _item_detail()._item_display_name(item)


func _item_difference_summary_text(item: Dictionary) -> String:
	return _item_detail()._item_difference_summary_text(item)


func _inventory_item_by_id(inventory: Array, instance_id: String) -> Dictionary:
	return _item_detail()._inventory_item_by_id(inventory, instance_id)


## Kept for the item detail dialog, whose layout signals are wired to the screen
## in _build_ui while the layout body belongs to the shared item-detail module.
func _layout_item_detail_dialog() -> void:
	_item_detail()._layout_item_detail_dialog()


## Kept for the item detail dialog, whose close signals are wired to the screen
## in _build_ui while the focus return belongs to the shared item-detail module.
func _on_item_detail_closed() -> void:
	_item_detail()._on_item_detail_closed()


## Kept for the salvage dialog, whose confirm signal is wired to the screen in
## _build_ui while the handler belongs to the shared item-detail module.
func _on_salvage_confirmed() -> void:
	_item_detail()._on_salvage_confirmed()


## Kept for the salvage dialog, whose cancel signals are wired to the screen in
## _build_ui while the handler belongs to the shared item-detail module.
func _on_salvage_canceled() -> void:
	_item_detail()._on_salvage_canceled()
