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
const PixelGridIconScript = preload("res://src/presentation/pixel_grid_icon.gd")
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

## Legacy header art of the previous prototype. It is only a last resort for a
## page the production batch does not mark (immortality, research, unknown ids);
## every page the hamlet package covers draws its published cell instead.
const LEGACY_FACILITY_TEXTURES: Dictionary = {
	"loadout": "res://art/production/p1/legacy_facility_stations/equipment_rune_desk.png",
	"forge": "res://art/production/p1/legacy_facility_stations/destiny_forge.png",
	"training": "res://art/production/p1/legacy_facility_stations/training_report.png",
}

const FACILITY_TEXTURES: Dictionary = {
	"loadout": "res://art/production/p1/legacy_facility_stations/equipment_rune_desk.png",
	"forge": "res://art/production/p1/legacy_facility_stations/destiny_forge.png",
	"training": "res://art/production/p1/legacy_facility_stations/training_report.png",
}
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
## The player-facing proxy surface only lists the six behaviors implemented by
## the runtime. Slot order is fixed even when the installed core changes.
const CORE_ORDER: Array[String] = ["near_enemy_horizon", "direct_gait", "single_key_execution", "short_trace_memory"]
const IMPLEMENTED_CORE_IDS: Array[String] = ["near_enemy_horizon", "marking_prism", "direct_gait", "distance_keeping_gait", "single_key_execution", "short_trace_memory"]
const PROXY_SLOT_ORDER: Array[String] = ["perception", "movement", "execution", "memory"]
const PROXY_SLOT_LABELS: Dictionary = {
	"perception": "Perception Slot",
	"movement": "Action Slot",
	"execution": "Execution Slot",
	"memory": "Memory Slot",
}
const CORE_ROLES: Dictionary = {
	"near_enemy_horizon": "Perception",
	"marking_prism": "Perception",
	"direct_gait": "Action",
	"distance_keeping_gait": "Action",
	"single_key_execution": "Execution",
	"short_trace_memory": "Memory",
}
const FORGE_TRACKS: Array[String] = ["inscribe", "rewrite", "refine"]
const FORGE_TRACK_TITLES: Dictionary = {
	"inscribe": "Inscribe",
	"rewrite": "Rewrite",
	"refine": "Refine",
}
const FORGE_OPERATION_EXPLANATIONS: Dictionary = {
	"inscribe": "Add one affix; the new slot is selected automatically.",
	"rewrite": "The Sacred Law sequence selects the existing affix to replace; you cannot choose it.",
	"refine": "The Sacred Law sequence selects the eligible affix to refine; you cannot choose it.",
}
## Surface copy for the published training terms only (early_items.json and
## ranger_presets.json). Interface names come from the shared content vocabulary.
const TRAINING_GROWTH_NAMES := {"convergent": "Convergent", "critical": "Critical", "exponential": "Exponential"}
const LAW_TALLY_LABELS: Dictionary = {
	"inscribe": "Inscribe Law Tokens",
	"rewrite": "Rewrite Law Tokens",
	"refine": "Refine Law Tokens",
}
## Two authored skill lines plus a 32px icon need this much logical lane width
## before a two-column grid is safe. Narrow windows stack the four actions in one
## column inside the existing local scroll region instead of widening that region.
const LOADOUT_SKILL_TWO_COLUMN_REGION_MIN_WIDTH := 360.0
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
		_as_dictionary(_facility_data.get("base_items", {})),
		_as_dictionary(_facility_data.get("affix_families", {})),
		_as_dictionary(_facility_data.get("salvage_previews", {}))
	)
	if _facility_id == "loadout":
		var context := _as_dictionary(_facility_data.get("initial_focus", {}))
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
		_restore_forge_session_cursor()
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
	var context := _as_dictionary(_facility_data.get("initial_focus", {}))
	var instance_id := String(context.get("review_instance_id", "")).strip_edges()
	var slot := String(context.get("focus_slot", "")).strip_edges()
	if instance_id.is_empty() or slot.is_empty() or slot not in _as_array(_facility_data.get("prototype_open_slots", [])):
		return
	for raw_item in _as_array(_facility_data.get("inventory_equipment", [])):
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
	var context := _as_dictionary(_facility_data.get("initial_focus", {}))
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
	_clear_children(_cards)
	_clear_children(_actions)
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
			_build_loadout()
		"forge":
			_build_forge()
		"training":
			_build_training()
		"proxy":
			_build_proxy()
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
		return
	var legacy_path := String(LEGACY_FACILITY_TEXTURES.get(_facility_id, ""))
	if legacy_path.is_empty() or not ResourceLoader.exists(legacy_path):
		return
	var resource := ResourceLoader.load(legacy_path)
	if not resource is Texture2D:
		return
	_facility_icon = TextureRect.new()
	_facility_icon.name = "FacilityMark"
	_facility_icon.custom_minimum_size = Vector2(compact_size if compact_size.x > 0 and compact_size.y > 0 else Vector2i(128, 128))
	_facility_icon.texture = resource as Texture2D
	_facility_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_facility_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_facility_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_facility_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(_facility_icon)


## Overview cell holding the mark at its published size. A mark is wider than the
## text column, so it gets its own column instead of pushing the title row down.
## Returns null when this page has no published cell and no legacy station art,
## so the caller never reserves an empty column.
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


## True when this route has a published mark or the legacy station art the
## previous prototype used. Pages without one keep their text-only header.
func _has_page_mark() -> bool:
	if _art.is_ready() and _art.mark(_facility_id) != null:
		return true
	var legacy_path := String(LEGACY_FACILITY_TEXTURES.get(_facility_id, ""))
	return not legacy_path.is_empty() and ResourceLoader.exists(legacy_path)


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
	var icon: TextureRect = PixelGridIconScript.new() if scaled else TextureRect.new()
	icon.texture = texture
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_SCALE
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var display_size := native_size
	if scaled:
		display_size = native_size * FacilityArtScript.ICON_DISPLAY_SCALE
	icon.custom_minimum_size = Vector2(display_size)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return icon

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
		icon.name = "%s_%s" % [node_prefix, _stable_node_token(resolved[index])]
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


func _build_loadout() -> void:
	if _has_real_loadout_data():
		_build_real_loadout()
		return
	_build_legacy_loadout()


func _build_legacy_loadout() -> void:
	var builds := _as_array(_facility_data.get("available_builds", []))
	var active_data := _as_dictionary(_facility_data.get("active_build", {}))
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
		var display_name := _build_display_name(build, rendered, verified)
		var title := "%s%s" % ["[Current Kit] " if selected else "", display_name]
		var p_text := _format_value(build.get("p", _nested_value(build, ["parameters", "p"], "Unknown")))
		var conclusion := "Unverified"
		if verified:
			conclusion = String(build.get("state", build.get("growth_state", build.get("conclusion", build.get("verified_growth_name", "Verified")))))
		var body := "Continuation Chance: %s\nGrowth Conclusion: %s\nSkill: %s\nRune: %s\nLaw: %s\nEquipment Affixes / Calibration: %s" % [
			p_text,
			conclusion,
			_component_text(build, "skill", "Piercing Arrow"),
			_component_text(build, "rune", "Breeding Split"),
			_component_text(build, "law", "Pack Hunt Mark"),
			_equipment_text(build),
		]
		_add_card(title, body, "BuildCard_%s" % preset_id)
		_add_payload_action("Select %s" % display_name, "select_ranger_build", {"preset_id": preset_id}, "SelectBuild_%s" % preset_id)
		# The calibration presets name their skill, rune and law; each one that the
		# icon batch publishes gets its own cell beside the card it belongs to.
		var card: Node = find_child("BuildCard_%s" % preset_id, true, false)
		if card != null:
			_add_icon_row(card, [
				_art.canonical_id("rune", _component_id(build, "rune")),
				_art.canonical_id("law", _component_id(build, "law")),
			], "LegacyBuildIcon")
		rendered += 1
	if rendered == 0:
		_add_card("Build data unavailable", "No valid kit is available; p, component stats, and verification results remain unknown.", "BuildDataUnavailable")


func _has_real_loadout_data() -> bool:
	for key in ["equipment_slots", "prototype_open_slots", "inventory_equipment", "base_items", "affix_families", "active_build", "resolved_build"]:
		if not _facility_data.has(key):
			return false
	var equipment_slots := _as_array(_facility_data.get("equipment_slots", []))
	var open_slots := _as_array(_facility_data.get("prototype_open_slots", []))
	var active := _as_dictionary(_facility_data.get("active_build", {}))
	return equipment_slots.size() == 12 \
		and open_slots.size() == 4 \
		and _facility_data.get("inventory_equipment") is Array \
		and _facility_data.get("base_items") is Dictionary \
		and _facility_data.get("affix_families") is Dictionary \
		and active.get("equipped_item_ids") is Dictionary \
		and _facility_data.get("resolved_build") is Dictionary


func _build_real_loadout() -> void:
	var slots := _as_array(_facility_data.get("equipment_slots", []))
	var open := _as_array(_facility_data.get("prototype_open_slots", []))
	var active := _as_dictionary(_facility_data.get("active_build", {}))
	var equipped := _as_dictionary(active.get("equipped_item_ids", {}))
	var inventory := _as_array(_facility_data.get("inventory_equipment", []))
	_normalize_focus_slot(open)
	var stage := Control.new()
	stage.name = "LoadoutConceptRoot"
	stage.custom_minimum_size = Vector2(_layout_frame.x, maxf(570,_layout_frame.y))
	stage.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cards.add_child(stage)
	_facility_root = stage
	var regions := FacilityLayoutScript.loadout_regions(Vector2(_layout_frame.x,maxf(570,_layout_frame.y)))
	var slot_column := _workbench_region(stage,"LoadoutSlotsRegion",regions.slots)
	var left := _workbench_region(stage,"LoadoutLockedRegion",regions.locked)
	var right := _workbench_region(stage,"LoadoutCompareRegion",regions.compare)
	var hero := _workbench_region(stage,"LoadoutHeroRegion",regions.hero)
	slot_column.add_theme_constant_override("separation", 2)
	_build_slot_grid(slot_column, slots, open, equipped, inventory, {})
	var character_note := _note_label("Select a slot to compare and replace equipment in your backpack")
	character_note.name = "LoadoutCharacterDescription"
	slot_column.add_child(character_note)
	_build_loadout_skill_strip(left)
	var locked := _section_in(left, "Backpack and Progression", "ClosedEquipmentSlots")
	var locked_style := _recessed_panel_style("well")
	locked_style.content_margin_top = 4
	locked_style.content_margin_bottom = 4
	_section_panel(locked).add_theme_stylebox_override("panel", locked_style)
	locked.add_theme_constant_override("separation", 2)
	var reason := _note_label("Main Hand · Off Hand · Gloves · Ring\n" + _resolved_build_fact_lines()[1].get_slice("    Class:", 0))
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

## Bounded columns: children never feed their content minimum back into the
## root page width. Each content lane scrolls locally if the text grows.
func _grid_cell_box() -> StyleBox:
	var box := _recessed_panel_style("well")
	box.content_margin_left = 8.0
	box.content_margin_top = 6.0
	box.content_margin_right = 8.0
	box.content_margin_bottom = 6.0
	return box


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
	var regions := FacilityLayoutScript.loadout_regions(Vector2(_layout_frame.x, maxf(570.0, _layout_frame.y)))
	row.columns = 2 if float((regions.locked as Rect2).size.x) >= LOADOUT_SKILL_TWO_COLUMN_REGION_MIN_WIDTH else 1
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("h_separation", 4)
	parent.add_child(row)
	var skills := _as_array(_as_dictionary(_facility_data.get("active_build", {})).get("skills", []))
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
		button.name = "SkillSummary_%s" % _stable_node_token(skill_id)
		button.text = _compact_skill_text(skill, index + 1)
		button.tooltip_text = "Click to view %s's full targeting, effects, cooldown, synergies, and limits" % String(skill.get("name", "this skill"))
		var texture: Texture2D = _skill_icons.icon(skill_id)
		if texture != null:
			button.icon = texture
			button.expand_icon = false
			button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			button.set_meta("canonical_id", "action.%s" % skill_id)
		button.pressed.connect(_on_skill_summary_pressed.bind(skill_id))
		row.add_child(button)


func _compact_skill_text(skill: Dictionary, slot_index: int) -> String:
	if skill.is_empty():
		return "Skill Slot %d\nDetails unavailable" % slot_index
	var bindings := _as_array(skill.get("key_bindings", []))
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


func _on_skill_summary_pressed(skill_id: String) -> void:
	if _skill_detail_dialog == null:
		return
	var skill := _player_skill_entry(skill_id)
	if skill.is_empty():
		return
	var readable_text := _readable_build.format_skill(skill)
	_skill_detail_dialog.title = "Full Skill Details · %s" % String(skill.get("name", "Skill"))
	_skill_detail_dialog.dialog_text = ""
	_skill_detail_text.text = _skill_detail_paragraphs(readable_text)
	_skill_detail_scroll.scroll_vertical = 0
	_skill_detail_dialog.min_size = Vector2i(760, 500)
	_skill_detail_dialog.size = Vector2i(760, 500)
	_layout_skill_detail_dialog()
	_skill_detail_dialog.popup_centered_clamped(Vector2i(760, 500), 0.9)
	call_deferred("_layout_skill_detail_dialog")


## Keep every production formatter character in order. Only blank lines are
## inserted before semantic sections; the rules, numbers and limitations are
## neither rewritten nor abbreviated by this presentation.
func _skill_detail_paragraphs(readable_text: String) -> String:
	var result := readable_text
	for heading: String in ["Target Rule: ", "Full Effect: ", "Cooldown: ", "Synergy: ", "Limits: "]:
		result = result.replace("\n" + heading, "\n\n" + heading)
	return result


## Keep the complete player-readable description inside the fixed dialog body. The
## title belongs to AcceptDialog's title bar and its close button remains in the
## dialog footer, so only the description can scroll.
func _layout_skill_detail_dialog() -> void:
	if _skill_detail_dialog == null or _skill_detail_scroll == null or _skill_detail_text == null:
		return
	var dialog_size := _skill_detail_dialog.size
	var body_position := Vector2(20.0, 44.0)
	var body_size := Vector2(maxf(0.0, dialog_size.x - 40.0), maxf(0.0, dialog_size.y - 116.0))
	_skill_detail_reading_surface.position = body_position - Vector2(8, 8)
	_skill_detail_reading_surface.size = body_size + Vector2(16, 16)
	_skill_detail_scroll.position = body_position
	_skill_detail_scroll.size = body_size
	# Reserve the scrollbar lane while wrapping. This guarantees that a long key,
	# parameter name or Chinese phrase wraps vertically instead of producing a
	# horizontal overflow.
	_skill_detail_text.custom_minimum_size.x = maxf(0.0, body_size.x - 18.0)
	_skill_detail_text.size.x = _skill_detail_text.custom_minimum_size.x
	call_deferred("_fit_skill_detail_text")


## Label's wrapped height is resolved after it knows the scroll viewport width.
## Feed that resolved height back as the scroll child's minimum so the outer
## ScrollContainer receives a real vertical overflow instead of a clipped label.
func _fit_skill_detail_text() -> void:
	if _skill_detail_scroll == null or _skill_detail_text == null:
		return
	var content_width := maxf(0.0, _skill_detail_scroll.size.x - 18.0)
	_skill_detail_text.custom_minimum_size = Vector2(content_width, 0.0)
	_skill_detail_text.size = Vector2(content_width, 0.0)
	var wrapped_height := _skill_detail_text.get_minimum_size().y
	_skill_detail_text.custom_minimum_size = Vector2(content_width, wrapped_height)
	_skill_detail_text.size = Vector2(content_width, wrapped_height)


func _player_skill_entry(skill_id: String) -> Dictionary:
	for registry_key in ["early_skill_registry", "skill_registry", "skills"]:
		var entry := _as_dictionary(_as_dictionary(_facility_data.get(registry_key, {})).get(skill_id, {}))
		if not entry.is_empty():
			return entry
	return _skill_registry.get_skill(skill_id)


func _player_readable_skill_text(skill_id: String) -> String:
	var skill := _player_skill_entry(skill_id)
	return _readable_build.format_skill(skill) if not skill.is_empty() else ""



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
	var active := _as_dictionary(_facility_data.get("active_build", {}))
	for kind in ["runes", "laws"]:
		for value in _as_array(active.get(kind, [])):
			lines.append(_player_modifier_name(_display_value(value)))
	_show_item_detail("Build Reference", "\n".join(lines), get_action_button("LoadoutDetailsToggle"))
	_item_detail_dialog.title = "Build Details"


func _on_closed_slot_reference_pressed() -> void:
	if _item_detail_dialog == null or _item_detail_dialog_text == null:
		return
	var slots := _as_array(_facility_data.get("equipment_slots", []))
	var open := _as_array(_facility_data.get("prototype_open_slots", []))
	var lines: Array[String] = ["All 12 Slot States"]
	for raw_slot in slots:
		var slot := String(raw_slot)
		lines.append("%s: %s" % [_slot_title(slot), "Available" if slot in open else "Unavailable"])
	_show_item_detail("Slot Reference", "\n".join(lines), get_action_button("ClosedSlotReferenceToggle"))
	_item_detail_dialog.title = "All Slot Details"


## Readable reference facts for the complete build dialog. Growth classification
## is revealed only by a training report for the current build fingerprint.
func _resolved_build_fact_lines() -> Array[String]:
	var resolved := _as_dictionary(_facility_data.get("resolved_build", {}))
	var parameters := _as_dictionary(resolved.get("final_parameters", {}))
	var parameter_lines: Array[String] = []
	for parameter in PlayerReadableBuildScript.PARAMETER_ORDER:
		parameter_lines.append(_readable_build.format_parameter(parameter, parameters.get(parameter, null)))
	var fingerprint := String(resolved.get("build_fingerprint", ""))
	var training := _as_dictionary(_facility_data.get("training", {}))
	var classification := "Unverified"
	var report := _matched_training_report(training, fingerprint)
	if not report.is_empty():
		var reported := String(report.get("state", "")).strip_edges()
		if not reported.is_empty():
			classification = reported
	classification = String(TRAINING_GROWTH_NAMES.get(classification, classification))
	return [
		"Final Stats: " + "  ·  ".join(parameter_lines),
		"Growth Classification: %s    Class: %s" % [classification, String({"ranger":"Ranger", "alchemist":"Alchemist", "mage":"Mage"}.get(String(_profile.get("initial_class", "")), "Not Created"))],
		"Connected Interfaces: %s" % _resolved_interface_facts_text(resolved.get("connected_interfaces", [])),
		"Missing Interfaces: %s" % _resolved_interface_facts_text(resolved.get("missing_interfaces", [])),
	]


func _resolved_interface_facts_text(value: Variant) -> String:
	var labels: Array[String] = []
	for id: Variant in _as_array(value):
		labels.append(EarlyInterfaceVocabularyScript.player_name(String(id)))
	return _joined_or_none(labels)


## The formal 12-slot state as one grid, in the published table's own order: the four
## open slots carry their equipped base, their real state word and their focus
## control, the locked ones keep their outline, their published Chinese name and their
## lock reason and offer no action at all. The two groups are laid out where the
## approved cell puts them: the open slots form the first row of the page, and the
## locked remainder is a compact grid of one-line cells below the decision. The grid
## works out how many columns it needs from the frame the page froze, so a 1024-wide
## frame stacks the strip instead of shrinking a cell below the 64px icon display.
func _build_slot_grid(parent: Container, equipment_slots: Array, open_slots: Array, equipped_ids: Dictionary, inventory: Array, _composition: Dictionary) -> void:
	var section := _section_in(parent, "", "OpenSlotStrip")
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
	var item := _inventory_item_by_id(inventory, String(equipped_ids.get(slot,"")))
	var focused := slot == _focus_slot
	var token := _stable_node_token(slot)
	var cell := PanelContainer.new()
	cell.name = "LoadoutSlotCell_" + token
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.add_theme_stylebox_override("panel", _slot_cell_box(focused,item.is_empty()))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",2)
	cell.add_child(column)
	var title := _note_label(_slot_title(slot))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	var canonical := _art.canonical_id("equipment_slot",slot) if item.is_empty() else _art.canonical_id("equipment_base",String(item.get("base_item_id","")))
	var texture := _body_icon_texture(canonical)
	if texture != null:
		var icon := _icon_node(texture,FacilityArtScript.ICON_NATIVE_SIZE,true)
		icon.name = "SlotIcon_" + token
		icon.set_meta("canonical_id",canonical)
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		column.add_child(icon)
	var state := _note_label("Unequipped" if item.is_empty() else "Equipped")
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
	var section := _section_in(composition.get("parent", _cards), "", "SlotCompareSection")
	_section_panel(section).add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	if _focus_slot.is_empty() or _focus_slot not in open_slots:
		section.add_child(_note_label("No available slots on this page can be compared."))
		return
	var candidates_panel := _section_in(section, "Equipment Backpack · %s" % _slot_title(_focus_slot), "CandidateListPanel_%s" % _stable_node_token(_focus_slot))
	var panel_style := _section_panel(candidates_panel).get_theme_stylebox("panel").duplicate() as StyleBox
	panel_style.content_margin_top = 6
	panel_style.content_margin_bottom = 6
	_section_panel(candidates_panel).add_theme_stylebox_override("panel", panel_style)
	candidates_panel.add_theme_constant_override("separation", 4)
	var alternatives := _same_slot_candidates(_focus_slot, String(equipped_ids.get(_focus_slot, "")), inventory)
	_build_candidate_filters(candidates_panel, alternatives)
	_candidate_results = VBoxContainer.new()
	_candidate_results.name = "CandidateResults"
	_candidate_results.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	candidates_panel.add_child(_candidate_results)
	_refresh_candidate_results()


func _refresh_candidate_results() -> void:
	if not is_instance_valid(_candidate_results):
		return
	_clear_children(_candidate_results)
	_loadout_backpack_detail = null
	_loadout_backpack_detail_region = null
	_loadout_empty_hint = null
	_loadout_detail_pointer_inside = false
	_loadout_backpack_items = []
	var active := _as_dictionary(_facility_data.get("active_build", {}))
	var equipped_id := String(_as_dictionary(active.get("equipped_item_ids", {})).get(_focus_slot, ""))
	var inventory := _as_array(_facility_data.get("inventory_equipment", []))
	var current := _inventory_item_by_id(inventory, equipped_id)
	var all_alternatives := _same_slot_candidates(_focus_slot, equipped_id, inventory)
	var alternatives := _filter_sort_candidates(all_alternatives)
	_candidate_filter_bar.set_result_count(alternatives.size(), all_alternatives.size())
	if current.is_empty() and alternatives.is_empty():
		_candidate_results.add_child(_note_label("No candidates match. Click Reset to view all." if not all_alternatives.is_empty() else "No replacement candidates for this slot."))
		return
	# Inventory density lives in one icon grid. Hover, keyboard focus, and controller
	# focus all select the same one-item detail pane, so long prose is instantiated
	# once rather than once per inventory item.
	_loadout_backpack_items = []
	if not current.is_empty():
		_loadout_backpack_items.append(current.duplicate(true))
	_loadout_backpack_items.append_array(alternatives.duplicate(true))
	_loadout_backpack_equipped_id = equipped_id
	if not _loadout_backpack_pinned_id.is_empty() and _inventory_item_by_id(_loadout_backpack_items, _loadout_backpack_pinned_id).is_empty():
		_loadout_backpack_pinned_id = ""
	_loadout_backpack_selection = _loadout_review_instance_id if not _inventory_item_by_id(_loadout_backpack_items, _loadout_review_instance_id).is_empty() else _loadout_backpack_pinned_id
	var backpack_row := _make_row("CandidateBackpackRow")
	# Keep pointer travel from an icon into its shared action pane continuous.
	backpack_row.add_theme_constant_override("separation", 0)
	_candidate_results.add_child(backpack_row)
	var backpack := EquipmentBackpackGridScript.new()
	# Give the comparison most of the width; larger windows add one icon column.
	var backpack_columns := 3 if _layout_frame.x >= 1400.0 else 2
	var backpack_width := float(backpack_columns * 76 + (backpack_columns - 1) * 6)
	backpack.custom_minimum_size.x = backpack_width
	var initial_backpack_id := _loadout_backpack_selection if not _loadout_backpack_selection.is_empty() else equipped_id
	backpack.configure(_backpack_entries(_loadout_backpack_items, "CandidateBackpackIcon"), initial_backpack_id, backpack_columns, "CandidateBackpack", 2)
	# configure() gives the reusable picker expand/fill defaults; override them only
	# after configuration so this lane stays at its measured grid width.
	backpack.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	backpack.item_inspected.connect(_on_loadout_backpack_inspected)
	backpack.item_activated.connect(_on_loadout_backpack_activated)
	backpack_row.add_child(backpack)
	_loadout_empty_hint = VBoxContainer.new()
	_loadout_empty_hint.name = "BackpackInspectionHint"
	_loadout_empty_hint.alignment = BoxContainer.ALIGNMENT_CENTER
	_loadout_empty_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_loadout_empty_hint.custom_minimum_size.y = 246
	var hint_title := _body_label("No Matching Candidates" if alternatives.is_empty() and not all_alternatives.is_empty() else "Choose a piece of loot to see what it changes")
	hint_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loadout_empty_hint.add_child(hint_title)
	var hint_note := _note_label("Click Reset to view all\nEquipped items can still be inspected" if alternatives.is_empty() and not all_alternatives.is_empty() else "Hover to inspect · Click to pin comparison\nReview both gains and costs before equipping")
	hint_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loadout_empty_hint.add_child(hint_note)
	backpack_row.add_child(_loadout_empty_hint)
	_loadout_backpack_detail_region = Control.new()
	_loadout_backpack_detail_region.name = "BackpackDetail"
	_loadout_backpack_detail_region.custom_minimum_size = Vector2(0, 246)
	_loadout_backpack_detail_region.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_loadout_backpack_detail_region.clip_contents = true
	_loadout_backpack_detail_region.mouse_entered.connect(_on_loadout_detail_mouse_entered)
	_loadout_backpack_detail_region.mouse_exited.connect(_on_loadout_detail_mouse_exited)
	backpack_row.add_child(_loadout_backpack_detail_region)
	_loadout_backpack_detail = VBoxContainer.new()
	_loadout_backpack_detail.name = "BackpackDetailContent"
	_loadout_backpack_detail.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_loadout_backpack_detail.offset_left = 8.0
	_loadout_backpack_detail.offset_top = 4.0
	_loadout_backpack_detail.offset_right = -8.0
	_loadout_backpack_detail.offset_bottom = -4.0
	_loadout_backpack_detail_region.add_child(_loadout_backpack_detail)
	if _loadout_backpack_selection.is_empty():
		_loadout_backpack_detail_region.visible = false
	else:
		_render_loadout_backpack_detail(_loadout_backpack_selection)


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
			"icon_node_name": "%s_%s" % [icon_prefix, _stable_node_token(instance_id)],
			"status_label": "Equipped" if instance_id in _as_dictionary(_as_dictionary(_facility_data.get("active_build", {})).get("equipped_item_ids", {})).values() else ("This Run" if instance_id == _loadout_review_instance_id else ""),
		})
	return entries


func _on_loadout_backpack_inspected(instance_id: String) -> void:
	if instance_id.is_empty():
		# Focus transfer from an inventory cell to an action in the shared detail
		# pane settles after the cell's focus_exited signal. Decide on the next idle
		# turn so moving toward "Full Details" does not destroy the button mid-click.
		call_deferred("_finish_loadout_backpack_exit")
		return
	if instance_id == _loadout_backpack_selection:
		_render_loadout_backpack_detail(instance_id)
		return
	_loadout_backpack_selection = instance_id
	_render_loadout_backpack_detail(instance_id)


func _on_loadout_backpack_activated(instance_id: String) -> void:
	if _inventory_item_by_id(_loadout_backpack_items, instance_id).is_empty():
		return
	_loadout_backpack_pinned_id = instance_id
	_loadout_backpack_selection = instance_id
	_render_loadout_backpack_detail(instance_id)


func _on_loadout_detail_mouse_entered() -> void:
	_loadout_detail_pointer_inside = true


func _on_loadout_detail_mouse_exited() -> void:
	_loadout_detail_pointer_inside = false
	call_deferred("_finish_loadout_backpack_exit")


func _finish_loadout_backpack_exit() -> void:
	if _item_detail_dialog != null and _item_detail_dialog.visible:
		return
	if _loadout_detail_pointer_inside:
		return
	var focus_owner := get_viewport().gui_get_focus_owner() if get_viewport() != null else null
	if focus_owner != null and _loadout_backpack_detail_region != null \
		and (_loadout_backpack_detail_region == focus_owner or _loadout_backpack_detail_region.is_ancestor_of(focus_owner)):
		return
	var backpack := find_child("EquipmentBackpack", true, false)
	if backpack != null and backpack.has_method("inspected_item_id") \
		and not String(backpack.call("inspected_item_id")).is_empty():
		return
	if not _loadout_backpack_pinned_id.is_empty() \
		and not _inventory_item_by_id(_loadout_backpack_items, _loadout_backpack_pinned_id).is_empty():
		_loadout_backpack_selection = _loadout_backpack_pinned_id
		if backpack != null and backpack.has_method("select_item"):
			backpack.call("select_item", _loadout_backpack_pinned_id)
		_render_loadout_backpack_detail(_loadout_backpack_pinned_id)
		return
	_loadout_backpack_selection = ""
	if backpack != null and backpack.has_method("select_item"):
		backpack.call("select_item", _loadout_backpack_equipped_id)
	_render_loadout_backpack_detail("")


func _render_loadout_backpack_detail(instance_id: String) -> void:
	if _loadout_backpack_detail == null or not is_instance_valid(_loadout_backpack_detail):
		return
	_clear_children(_loadout_backpack_detail)
	var item := _inventory_item_by_id(_loadout_backpack_items, instance_id)
	if is_instance_valid(_loadout_empty_hint):
		_loadout_empty_hint.visible = item.is_empty()
	if item.is_empty():
		if _loadout_backpack_detail_region != null:
			_loadout_backpack_detail_region.visible = false
		return
	if _loadout_backpack_detail_region != null:
		_loadout_backpack_detail_region.visible = true
	if instance_id == _loadout_backpack_equipped_id:
		_add_current_item_backpack_detail(item)
	else:
		_add_candidate_block(_loadout_backpack_detail, item)
	_track_backpack_detail_actions(_loadout_backpack_detail_region, "loadout")


func _add_current_item_backpack_detail(item: Dictionary) -> void:
	var instance_id := String(item.get("instance_id", ""))
	var slot := String(item.get("slot", _focus_slot))
	var token := _stable_node_token(instance_id)
	var title := _body_label("Equipped · %s" % _item_display_name(item))
	title.name = "BackpackDetailName"
	_loadout_backpack_detail.add_child(title)
	var summary := _note_label(_item_inline_summary_text(item))
	summary.name = "CurrentItemSummary_%s" % _stable_node_token(slot)
	summary.add_theme_color_override("font_color", ShellThemeScript.BONE)
	_loadout_backpack_detail.add_child(summary)
	var actions := _make_row("BackpackActions")
	_loadout_backpack_detail.add_child(actions)
	_action_button(actions, "Unequip", "unequip_item", {"slot": slot}, "Unequip_%s" % _stable_node_token(slot))
	_add_full_item_detail_button(
		actions,
		item,
		"Equipped · %s" % _item_display_name(item),
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
		_loadout_backpack_detail.add_child(salvage_button)


func _add_full_item_detail_button(parent: Container, item: Dictionary, title_text: String, detail_text: String) -> Button:
	var instance_id := String(item.get("instance_id", ""))
	var button := Button.new()
	button.name = "FullItemDetails_%s" % _stable_node_token(instance_id)
	button.text = "Full Equipment Details"
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.tooltip_text = "Open full item details; closing returns focus to this button"
	button.focus_mode = Control.FOCUS_ALL
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(_show_item_detail.bind(title_text, detail_text, button))
	parent.add_child(button)
	return button


func _show_item_detail(title_text: String, detail_text: String, source: Control) -> void:
	if _item_detail_dialog == null or _item_detail_dialog_text == null:
		return
	_item_detail_return_focus = source
	_item_detail_dialog.title = "Full Equipment Details · %s" % title_text
	_item_detail_dialog.dialog_text = ""
	_item_detail_dialog_text.text = detail_text
	_item_detail_scroll.scroll_vertical = 0
	var target_size := _item_detail_target_size()
	_item_detail_dialog.min_size = target_size
	_item_detail_dialog.size = target_size
	_layout_item_detail_dialog()
	_item_detail_dialog.popup_centered_clamped(target_size, 0.95)
	call_deferred("_layout_item_detail_dialog")


func _item_detail_target_size() -> Vector2i:
	var viewport_size := get_viewport_rect().size
	var bounded_width := minf(1040.0, maxf(760.0, viewport_size.x * 0.78))
	var bounded_height := minf(700.0, maxf(520.0, viewport_size.y * 0.82))
	return Vector2i(
		int(minf(bounded_width, maxf(320.0, viewport_size.x - 48.0))),
		int(minf(bounded_height, maxf(280.0, viewport_size.y - 32.0)))
	)


func _layout_item_detail_dialog() -> void:
	if _item_detail_dialog == null or _item_detail_scroll == null or _item_detail_dialog_text == null:
		return
	var body_position := Vector2(20.0, 44.0)
	var body_size := Vector2(maxf(0.0, _item_detail_dialog.size.x - 40.0), maxf(0.0, _item_detail_dialog.size.y - 116.0))
	_item_detail_scroll.position = body_position
	_item_detail_scroll.size = body_size
	var content_width := maxf(0.0, body_size.x - 18.0)
	_item_detail_dialog_text.custom_minimum_size = Vector2(content_width, 0.0)
	_item_detail_dialog_text.size = Vector2(content_width, 0.0)
	call_deferred("_fit_item_detail_text")


func _fit_item_detail_text() -> void:
	if _item_detail_scroll == null or _item_detail_dialog_text == null:
		return
	var content_width := maxf(0.0, _item_detail_scroll.size.x - 18.0)
	_item_detail_dialog_text.custom_minimum_size = Vector2(content_width, 0.0)
	_item_detail_dialog_text.size = Vector2(content_width, 0.0)
	var wrapped_height := _item_detail_dialog_text.get_minimum_size().y
	_item_detail_dialog_text.custom_minimum_size = Vector2(content_width, wrapped_height)
	_item_detail_dialog_text.size = Vector2(content_width, wrapped_height)


func _on_item_detail_closed() -> void:
	var return_focus := _item_detail_return_focus
	_item_detail_return_focus = null
	if return_focus != null and is_instance_valid(return_focus) and return_focus.is_visible_in_tree() \
		and (not return_focus is BaseButton or not (return_focus as BaseButton).disabled):
		return_focus.call_deferred("grab_focus")


## The hero who wears the compared equipment stands beside the slot grid, so the page
## answers "who is this for" without leaving the first screen — the same place cell
## 03 of the approved concept sheet puts him. The frame is the ranger's own published
## one; the caption names the clip, the cell and the integer display multiple in
## words, and says plainly that this is the hero body rather than a paper doll whose
## appearance follows the equipped items. No second class is offered or drawn.
func _build_character_column(parent: Container) -> void:
	var content := _section_in(parent, "", "LoadoutCharacterPanel")
	content.add_theme_constant_override("separation", 0)
	var box := StyleBoxEmpty.new()
	_section_panel(content).add_theme_stylebox_override("panel",box)
	var row := _make_row("LoadoutCharacterRow")
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_child(row)
	var view := LoadoutCharacterViewScript.new()
	view.name = "LoadoutCharacterPortrait"
	view.refresh()
	view.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(view)
	_character_view = view
	# The full identity copy remains with the open equipment slots, where it is
	# visible without reducing the authored portrait cell.
	view.tooltip_text = "Current Ranger · White Hood · Longbow and Backpack\nEquipment changes stats, not the current appearance."
	view.mouse_filter = Control.MOUSE_FILTER_STOP
	var caption := _note_label("Current Ranger · White Hood\nLongbow and Backpack · Fixed Appearance")
	caption.name = "LoadoutCharacterCaption"
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.visible = false
	content.add_child(caption)


func character_preview_report() -> Dictionary:
	if _character_view == null:
		return {"present": false, "drawing": false, "notes": ["the loadout page built no hero preview"]}
	var report: Dictionary = _character_view.frame_report()
	report["present"] = true
	return report


func _add_candidate_block(parent: Container, item: Dictionary) -> void:
	var instance_id := String(item.get("instance_id", ""))
	var token := _stable_node_token(instance_id)
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
	var name_label := _body_label(_item_display_name(item))
	name_label.name = "CandidateName_%s" % token
	headline.add_child(name_label)
	if instance_id == _loadout_review_instance_id:
		var located := _note_label("This Run's Drop · Located")
		located.name = "ReviewedDrop_%s" % token
		located.add_theme_color_override("font_color", ShellThemeScript.AMBER)
		headline.add_child(located)
	var preview_state_text := _candidate_preview_state_text(item)
	var preview_summary := _note_label("Verified" if preview_state_text.begins_with("Sacred Law Preview: Verified") else "Unverified")
	preview_summary.name = "CandidatePreviewStateSummary_%s" % token
	preview_summary.tooltip_text = preview_state_text
	preview_summary.size_flags_horizontal = Control.SIZE_SHRINK_END
	preview_summary.custom_minimum_size.x = 112.0
	preview_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	headline.add_child(preview_summary)
	var actions := _make_row("BackpackActions")
	content.add_child(actions)
	var equip := _action_button(actions, "Equip", "equip_item", {"instance_id": instance_id}, "Equip_%s" % token)
	equip.tooltip_text = "Equip and Apply · " + _item_display_name(item)
	var decision_text := _candidate_decision_text(instance_id)
	var preview := _equip_preview_data(instance_id)
	_add_interface_changes(content, preview)
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
	comparison.present(_facility_data.resolved_build.final_parameters, _equip_preview_data(instance_id).get("final_parameters", {}))
	comparison_body.add_child(comparison)
	var summary := _note_label(_candidate_inline_item_facts(item))
	summary.name = "CandidateSummary_%s" % token
	comparison_body.add_child(summary)
	var detail_text := "%s\n\nEquipment Conclusion\n%s\n\nSacred Law Preview\n%s\n%s" % [
		_item_summary_text(item, true),
		decision_text,
		preview_state_text,
		_equip_preview_text(instance_id),
	]
	var full_detail := _add_full_item_detail_button(actions, item, _item_display_name(item), detail_text)
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


## Sacred Law Preview is a state word, not a promise: a classification only appears when the
## candidate's own fingerprint has passed the test range.
func _candidate_preview_state_text(item: Dictionary) -> String:
	var preview := _equip_preview_data(String(item.get("instance_id", "")))
	if preview.is_empty():
		return "Sacred Law Preview: Unverified (no preview data for this candidate)"
	var fingerprint := String(preview.get("build_fingerprint", "")).strip_edges()
	var training := _as_dictionary(_facility_data.get("training", {}))
	var report := _matched_training_report(training, fingerprint)
	if not report.is_empty():
		var classification := String(report.get("state", "")).strip_edges()
		var readable_classification := String(TRAINING_GROWTH_NAMES.get(classification, classification if not classification.is_empty() else "Unknown"))
		return "Sacred Law Preview: Verified · Growth classification %s" % readable_classification
	return "Sacred Law Preview: Unverified (this build has not passed Training; unknown does not mean failure)"


func _same_slot_candidates(slot: String, equipped_id: String, inventory: Array) -> Array[Dictionary]:
	return _equipment_model.same_slot_candidates(slot, equipped_id, inventory)


func _build_candidate_filters(parent: Container, candidates: Array[Dictionary]) -> void:
	_candidate_filter_bar = EquipmentFilterBarScript.new()
	parent.add_child(_candidate_filter_bar)
	_candidate_filter_bar.configure(_candidate_query, candidates, _as_dictionary(_facility_data.get("affix_families", {})))
	_candidate_filter_bar.query_changed.connect(_on_candidate_query_changed)


func _filter_sort_candidates(candidates: Array[Dictionary]) -> Array[Dictionary]:
	var query := _candidate_query.duplicate(true)
	query["reviewed_instance_id"] = _loadout_review_instance_id
	return _equipment_model.filter_sort(candidates, query)


func _on_candidate_query_changed(query: Dictionary) -> void:
	_candidate_query = query.duplicate(true)
	# The filter controls stay alive: typing, caret position and an open filter
	# window survive while only the inventory results are refreshed.
	_refresh_candidate_results()


## The formal 12-slot table minus the four open ones: a lock line each and one
## shared reason. No action, no icon, and never the word Unequipped.
## Rune/law row: the shared formatter owns all player-facing names and semantics.


## Switching the compared slot is presentation state: it rebuilds the page and
## emits nothing, so no equip/unequip request can be triggered by looking.
func _on_slot_focus_pressed(slot: String) -> void:
	if slot.is_empty() or slot == _focus_slot:
		return
	var active := _as_dictionary(_facility_data.get("active_build", {}))
	var equipped_ids := _as_dictionary(active.get("equipped_item_ids", {}))
	var inventory := _as_array(_facility_data.get("inventory_equipment", []))
	var candidates := _same_slot_candidates(slot, String(equipped_ids.get(slot, "")), inventory)
	if not String(_candidate_query.family).is_empty() and not _candidate_family_exists(candidates, String(_candidate_query.family)):
		_candidate_query.family = ""
	_loadout_review_instance_id = ""
	_loadout_backpack_pinned_id = ""
	_loadout_backpack_selection = ""
	_focus_slot = slot
	# The candidates of the new slot are a different list: they start at their own first
	# row, and only the page's own offset is carried across the rebuild.
	_slot_switch_pending = true
	if _built:
		_apply_presentation()


func _candidate_family_exists(candidates: Array[Dictionary], family_id: String) -> bool:
	for item in candidates:
		for raw_affix in _as_array(item.get("affixes", [])):
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
		_focus_slot = ""
		return
	if not _loadout_review_instance_id.is_empty() and _focus_slot in slot_ids:
		return
	if _previous_facility == _facility_id and _focus_slot in slot_ids:
		return
	_focus_slot = String(slot_ids[0])


## The snapshot's own base-item table entry for one owned item, or {} when the
## snapshot carries no entry: the page never invents a base it was not given.
func _base_item_data(item: Dictionary) -> Dictionary:
	return _as_dictionary(_equipment_model.base_items.get(String(item.get("base_item_id", "")), {}))


## The player-facing name of one owned item, or its base id when the snapshot has
## no published name for it. Never a shortened or invented label.
func _item_display_name(item: Dictionary) -> String:
	return _equipment_model.display_name(item)


func _joined_or_none(value: Variant) -> String:
	var text := _display_value(value)
	return text if not text.is_empty() else "None"


## The upstream equip preview for one candidate, or {} when the snapshot has no
## usable entry for it. Only the authoritative preview payload passes: the screen
## never recomputes a Build and never turns a failed preview into a silent guess.
func _equip_preview_data(instance_id: String) -> Dictionary:
	if instance_id.is_empty():
		return {}
	var previews := _as_dictionary(_facility_data.get("equip_previews", {}))
	var preview_value: Variant = previews.get(instance_id, null)
	if not preview_value is Dictionary or not bool((preview_value as Dictionary).get("ok", true)):
		return {}
	return preview_value


## The complete raw reference line of one item: every field the snapshot holds,
## including the raw slot id, the whole instance id, the untranslated modifiers,
## each affix with its index and its family id, and the raw rune and law ids.
## This is the page's reference layer: the cards keep it folded by default behind
## their own stable toggle, and nothing here is dropped, renamed, or recomputed.
func _item_detail_text(item: Dictionary) -> String:
	var modifiers: Array[String] = []
	for raw_modifier in _as_array(_base_item_data(item).get("modifiers", [])):
		if raw_modifier is Dictionary:
			modifiers.append(_modifier_text(raw_modifier))
	var affixes: Array[String] = []
	var families := _as_dictionary(_facility_data.get("affix_families", {}))
	var affix_index := 1
	for raw_affix in _as_array(item.get("affixes", [])):
		if not raw_affix is Dictionary:
			continue
		var affix: Dictionary = raw_affix
		var family_id := String(affix.get("family_id", ""))
		var family := _as_dictionary(families.get(family_id, {}))
		var tier := int(affix.get("tier", 0))
		var effect := _affix_effect_text(family, tier)
		affixes.append("%d. %s T%d%s(family_id: %s)" % [
			affix_index,
			String(family.get("name", family_id)),
			tier,
			" · %s" % effect if not effect.is_empty() else "",
			family_id,
		])
		affix_index += 1
	return "%s\nSlot: %s\ninstance_id: %s\nBase modifiers: %s\naffixes: %s\nrune: %s  ·  law: %s" % [
		_item_display_name(item),
		String(item.get("slot", "Unknown")),
		String(item.get("instance_id", "Unknown")),
		"; ".join(modifiers) if not modifiers.is_empty() else "None",
		"; ".join(affixes) if not affixes.is_empty() else "None",
		String(item.get("rune_id", "")) if not String(item.get("rune_id", "")).is_empty() else "None",
		String(item.get("law_id", "")) if not String(item.get("law_id", "")).is_empty() else "None",
	]


## One item's card summary: the published cell beside the player-readable Chinese
## summary of what the item really is. The raw reference line lives in the folded
## block under it, so the summary is what the card always shows.
##
## options keys: summary_node_name, show_name, icon_canonical, icon_prefix,
## icon_name.
func _raw_fields_are_long(item: Dictionary) -> bool:
	if String(item.get("instance_id", "")).length() > INSTANCE_ID_DISPLAY_LIMIT:
		return true
	return _raw_entry_count(item) > RAW_FIELD_ENTRY_LIMIT


func _raw_entry_count(item: Dictionary) -> int:
	var base_id := String(item.get("base_item_id", ""))
	var base := _as_dictionary(_as_dictionary(_facility_data.get("base_items", {})).get(base_id, {}))
	# Internal parameter entries only: the base's own modifiers plus the item's
	# affixes. The rune and the law are single short fields that stay readable, so
	# they never push a block over the budget on their own.
	return _as_array(base.get("modifiers", [])).size() + _as_array(item.get("affixes", [])).size()


## Why this block folds, in one line: the exact raw length or entry count, never a
## vague "too long". The toggle right below it names what is behind it.
func _raw_field_reason(item: Dictionary) -> String:
	var instance_id := String(item.get("instance_id", ""))
	if instance_id.length() > INSTANCE_ID_DISPLAY_LIMIT:
		return "instance_id: %d characters" % instance_id.length()
	return "%d internal entries" % _raw_entry_count(item)


## The player-facing facts of one item, one line each: the published base name, the
## real modifiers and affix tiers in the player's own words, and the rune and law by
## their published Chinese names. The page's own tables are the only source: a
## parameter the tables do not name keeps its raw key, and nothing here is
## recomputed, scored, or invented.
func _item_summary_text(item: Dictionary, show_name := true) -> String:
	var formatted := _readable_build.format_item(item)
	return "%s\n%s" % [_item_display_name(item), formatted] if show_name else formatted


## Three intentional, non-ellipsized lines for the fixed first-screen pane. The
## explicit modal carries full effect prose; this surface keeps identity and the
## important material/affix/rune/law facts readable beside the paged inventory.
func _item_inline_summary_text(item: Dictionary) -> String:
	return _equipment_model.current_inline_summary(item)


func _candidate_inline_item_facts(item: Dictionary) -> String:
	## The clarification follows the authoritative preview payload: with a valid
	## preview the comparison above already contains the base multipliers; without
	## one the note says so instead of implying a comparison happened.
	var preview := _equip_preview_data(String(item.get("instance_id", "")))
	return _equipment_model.candidate_inline_facts(item, "included" if not preview.is_empty() else "no_preview")


## The modal receives the complete authoritative comparison. The fixed pane shows
## the changed parameters plus a literal route to the remaining interface/tag facts.
func _player_modifier_name(modifier_id: String) -> String:
	return _equipment_model.modifier_name(modifier_id)


func _field_block_key(kind: String, owner_id: String) -> String:
	return "%s:%s" % [kind, owner_id]


func _field_block_open(kind: String, owner_id: String) -> bool:
	return bool(_open_field_blocks.get(_field_block_key(kind, owner_id), false))


func _field_block_toggle(kind: String, owner_id: String) -> Button:
	var open := _field_block_open(kind, owner_id)
	var toggle := Button.new()
	toggle.name = "%s_%s" % [
		String(FIELD_BLOCK_TOGGLE_PREFIXES.get(kind, "FieldBlockToggle")),
		_stable_node_token(owner_id),
	]
	toggle.text = "Hide Raw Details" if open else "Show Raw Details"
	toggle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toggle.tooltip_text = "Show only this item's raw fields; no equipment, salvage, or data changes"
	toggle.pressed.connect(_on_field_block_toggled.bind(kind, owner_id))
	return toggle


## Unfolding reference data is presentation state: it rebuilds the page and emits
## nothing, so a long id can never be mistaken for an equip request.
func _on_field_block_toggled(kind: String, owner_id: String) -> void:
	if kind.is_empty() or owner_id.is_empty():
		return
	var key := _field_block_key(kind, owner_id)
	_open_field_blocks[key] = not bool(_open_field_blocks.get(key, false))
	if _built:
		_apply_presentation()


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
	var final_parameters := _as_dictionary(preview.get("final_parameters", {}))
	var resolved := _as_dictionary(_facility_data.get("resolved_build", {}))
	var current_parameters := _as_dictionary(resolved.get("final_parameters", {}))
	var lines: Array[String] = []
	if not final_parameters.is_empty() and not current_parameters.is_empty():
		var parameter_changes: Array[String] = []
		for parameter in PlayerReadableBuildScript.PARAMETER_ORDER:
			var next_value: Variant = final_parameters.get(parameter, null)
			if not _is_number(next_value):
				continue
			var current_value: Variant = current_parameters.get(parameter, null)
			var next_float := float(next_value)
			if _is_number(current_value):
				var current_float := float(current_value)
				if absf(next_float - current_float) <= 0.0001:
					continue
				parameter_changes.append("%s: %s → %s(%s%s)" % [
					_readable_build.parameter_name(parameter),
					_readable_build.format_parameter_value(parameter, current_float),
					_readable_build.format_parameter_value(parameter, next_float),
					"+" if next_float > current_float else "", _format_value(next_float - current_float),
				])
			else:
				parameter_changes.append("%s: Not Recorded -> %s (New)" % [_readable_build.parameter_name(parameter), _readable_build.format_parameter_value(parameter, next_float)])
		if not parameter_changes.is_empty():
			lines.append("Build Changes When Equipped:" + "  ·  ".join(parameter_changes))
	_append_preview_group(lines, preview, "interfaces_gained", "Interfaces Gained")
	_append_preview_group(lines, preview, "interfaces_lost", "Interfaces Lost")
	_append_preview_group(lines, preview, "tags_gained", "Tags Gained")
	_append_preview_group(lines, preview, "tags_lost", "Tags Lost")
	return "\n".join(lines)


## Compact decision layer, never an invented recommendation. Parameter deltas
## and concrete interface names come from the authoritative preview before the
## equip action; the complete canonical comparison remains below that action.
func _candidate_decision_text(instance_id: String) -> String:
	var preview := _equip_preview_data(instance_id)
	var resolved := _as_dictionary(_facility_data.get("resolved_build", {}))
	var summary := _readable_build.format_candidate_decision_summary(
		_as_dictionary(resolved.get("final_parameters", {})),
		preview
	)
	return summary.replace("Stats: ", "Stats When Equipped: ")


func _append_preview_group(lines: Array[String], preview: Dictionary, key: String, label: String) -> void:
	var values := _as_array(preview.get(key, []))
	if values.is_empty():
		return
	if key.begins_with("interfaces_"):
		var names: Array[String] = []
		for value in values:
			names.append(EarlyInterfaceVocabularyScript.player_name(String(value)))
		lines.append("%s: %s" % [label, ", ".join(names)])
	else:
		lines.append("%s: %d items" % [label, values.size()])


func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


func _modifier_text(modifier: Dictionary) -> String:
	return "%s %s %s" % [
		String(modifier.get("parameter", "Unknown")),
		String(modifier.get("operation", "Unknown")),
		_format_value(modifier.get("value", "Unknown")),
	]


func _affix_effect_text(family: Dictionary, tier: int) -> String:
	return _readable_build.format_affix({"family_id": String(family.get("id", "")), "tier": tier})


func _inventory_item_by_id(inventory: Array, instance_id: String) -> Dictionary:
	if instance_id.is_empty():
		return {}
	for raw_item in inventory:
		if raw_item is Dictionary and String((raw_item as Dictionary).get("instance_id", "")) == instance_id:
			return raw_item
	return {}


func _slot_display_name(slot: String) -> String:
	return _readable_build.slot_label(slot)


## The player-facing slot name on its own. Titles carry the Chinese name only;
## the raw slot id stays in the detail rows that name a concrete item.
func _slot_title(slot: String) -> String:
	return _readable_build.slot_label(slot)


## The four open slot names as one player-facing list, for the locked-slot reason
## line. Raw ids stay on the locked lines that already name their own slot.
func _stable_node_token(value: String) -> String:
	var token := ""
	for index in value.length():
		var character := value.substr(index, 1)
		var code := character.unicode_at(0)
		var legal := code >= 48 and code <= 57 or code >= 65 and code <= 90 or code >= 97 and code <= 122 or character in ["_", "-"]
		token += character if legal else "_"
	return token


func _salvage_action_for(item: Dictionary, instance_id: String) -> Dictionary:
	return _equipment_model.salvage_action(item) if instance_id == String(item.get("instance_id", "")) else {}


## The confirmation names the clicked item in player terms while its authoritative
## instance id stays in the pending command only. A compact slot + trait signature
## distinguishes same-base variants without exposing persistence fields.
func _salvage_item_identity(item: Dictionary) -> String:
	return "%s\n%s · %s" % [
		_item_display_name(item),
		_slot_display_name(String(item.get("slot", ""))),
		_item_difference_summary_text(item),
	]


func _on_salvage_pressed(instance_id: String, readable_identity: String, operation: String, amount: int, equipped_slot: String = "") -> void:
	if instance_id.is_empty() or operation not in LAW_TALLY_LABELS or amount < 1 or _salvage_dialog == null:
		return
	_pending_salvage = {"instance_id": instance_id, "operation": operation, "amount": amount, "equipped_slot": equipped_slot}
	var equipped_notice := "\nCurrently equipped: confirming safely unequips %s before salvaging." % _slot_display_name(equipped_slot) if not equipped_slot.is_empty() else ""
	_salvage_dialog.dialog_text = "Salvaging: %s\nReturns: %s x%d%s\nSalvage is irreversible. The item cannot be recovered after confirmation." % [
		readable_identity,
		String(LAW_TALLY_LABELS[operation]),
		amount,
		equipped_notice,
	]
	_salvage_dialog.popup_centered()


func _on_salvage_confirmed() -> void:
	if _pending_salvage.is_empty():
		return
	var instance_id := String(_pending_salvage.get("instance_id", ""))
	_pending_salvage = {}
	action_requested.emit("loadout", "salvage_item", {"instance_id": instance_id})


func _on_salvage_canceled() -> void:
	_pending_salvage = {}


func _build_forge() -> void:
	if _facility_data.is_empty():
		_section("Forge State Unavailable","ForgeUnavailable").add_child(_body_label("Forge data is not yet available."))
		return
	var session := _forge_session()
	var candidates := _forge_candidates()
	var selected_id := String(session.get("selected_candidate_id", ""))
	var selected := _forge_candidate_by_id(selected_id)
	var browse_status := "No Candidates Forecast Yet"
	if not candidates.is_empty():
		browse_status = "Viewing %d / %d" % [_forge_candidate_index + 1, candidates.size()]
		if not selected.is_empty():
			browse_status += " · Candidate %d selected" % (_forge_candidate_index_by_id(selected_id) + 1)
	var columns := _forge_stage_columns("ForgeConceptRoot", FacilityLayoutScript.FORGE_WEIGHTS, [
		{"title": "Step 1 · Choose", "status": "Target Equipment and Law Tokens"},
		{"title": "Step 2 · Forecast and Commit", "status": browse_status},
	])
	var input: VBoxContainer = columns[0]
	var workflow: VBoxContainer = columns[1]
	var target := _as_dictionary(_facility_data.get("target_item",{}))
	var tallies := _as_dictionary(_facility_data.get("law_tallies", {}))
	var target_panel := _section_in(input,"","ForgeTargetPanel")
	var target_row := _make_row("ForgeTargetCompactRow")
	target_row.alignment = BoxContainer.ALIGNMENT_CENTER
	target_panel.add_child(target_row)
	_add_facility_mark(target_row, Vector2i(64, 54))
	var canonical := _art.canonical_id("equipment_base", String(target.get("base_item_id", "")))
	var target_texture := _body_icon_texture(canonical)
	if target_texture != null:
		# The compact target summary keeps the authored cell at native 32x32. The
		# backpack below uses the larger 2x cells for browsing.
		var target_icon := _icon_node(target_texture, FacilityArtScript.ICON_NATIVE_SIZE, false)
		target_icon.name = "ForgeTargetIcon_%s" % _stable_node_token(canonical)
		target_icon.set_meta("canonical_id", canonical)
		target_row.add_child(target_icon)
	var target_copy := VBoxContainer.new()
	target_copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	target_copy.add_theme_constant_override("separation", 2)
	target_row.add_child(target_copy)
	var label := _body_label("Target · %s" % _forge_item_title(target))
	label.name = "ForgeTargetItem"
	label.tooltip_text = _forge_readable_item_text(target)
	target_copy.add_child(label)
	var target_note := _note_label("Hover over Backpack Items to Inspect Affixes")
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
	var operation_row := _make_row("ForgeOperationRow")
	setup_panel.add_child(operation_row)
	for operation in FORGE_TRACKS:
		var operation_button := Button.new()
		operation_button.name = "ForgeOperation_%s" % operation
		operation_button.add_theme_font_size_override("font_size", 22)
		operation_button.text = "%s\n×%d" % [String(FORGE_TRACK_TITLES[operation]), _law_tally(operation, tallies)]
		operation_button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		operation_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		operation_button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		operation_button.expand_icon = false
		operation_button.add_theme_constant_override("icon_max_width", 32)
		operation_button.add_theme_constant_override("h_separation", 4)
		operation_button.icon = _progression_icons.icon("law_token.%s" % operation)
		operation_button.tooltip_text = ("Current Operation · " if operation == _forge_operation else "") + String(FORGE_OPERATION_EXPLANATIONS[operation])
		operation_button.autowrap_mode = TextServer.AUTOWRAP_OFF
		operation_button.custom_minimum_size.y = 48
		operation_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		operation_button.disabled = operation == _forge_operation
		if operation == _forge_operation:
			operation_button.add_theme_stylebox_override("disabled", ShellThemeScript.panel_style("selected"))
			operation_button.add_theme_color_override("font_disabled_color", ShellThemeScript.BONE)
			operation_button.add_theme_color_override("icon_disabled_color", Color.WHITE)
		# Stack the icon above two authored lines so English operation names stay
		# intact in the narrow three-column workbench.
		for state in ["normal", "hover", "pressed", "disabled"]:
			var style_kind: String = {"normal":"button", "hover":"hover", "pressed":"selected", "disabled":"disabled"}[state]
			if state == "disabled" and operation == _forge_operation:
				style_kind = "selected"
			var style := ShellThemeScript.panel_style(style_kind).duplicate() as StyleBox
			style.content_margin_left = 6.0
			style.content_margin_right = 6.0
			style.content_margin_top = 2.0
			style.content_margin_bottom = 2.0
			operation_button.add_theme_stylebox_override(state, style)
		operation_button.pressed.connect(_on_forge_operation_selected.bind(operation))
		operation_row.add_child(operation_button)
	_build_forge_inventory(input,_as_array(_facility_data.get("inventory_items",[])),String(_facility_data.get("target_instance_id","")))
	if not bool(_facility_data.get("unlocked",false)):
		var locked := _section_in(workflow,"Law Token Forge Locked","ForgeLocked")
		locked.add_child(_body_label(String(_facility_data.get("locked_reason","Unlock requirements not yet met"))))
	else:
		if candidates.is_empty():
			var reveal_panel := _section_in(workflow,"Forecast a Future with Law Tokens","ForgeRevealPanel")
			reveal_panel.add_child(_note_label(String(FORGE_OPERATION_EXPLANATIONS[_forge_operation])))
			var block_reason := _forge_operation_block_reason(_forge_operation)
			if not block_reason.is_empty():
				reveal_panel.add_child(_body_label(block_reason, ShellThemeScript.WARNING))
		_build_forge_browse(workflow)
	_build_forge_dock()


## Fixed stage headers over independently scrolling bodies. Forge uses one setup
## lane and one decision lane; a long inventory or future result remains locally
## scrollable without duplicating the selected item in a third lane.
func _forge_stage_columns(node_name: String, weights: Array, stages: Array) -> Array:
	var stage := Control.new()
	stage.name = node_name
	stage.custom_minimum_size = Vector2(0, _layout_frame.y)
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cards.add_child(stage)
	_facility_root = stage
	var rectangles := FacilityLayoutScript.columns(_layout_frame, weights)
	var result: Array = []
	for index in weights.size():
		var rect: Rect2 = rectangles[index]
		var panel := PanelContainer.new()
		panel.name = node_name + "Column" + str(index)
		panel.position = rect.position
		panel.size = rect.size
		panel.add_theme_stylebox_override("panel", _grid_cell_box())
		stage.add_child(panel)
		var shell := VBoxContainer.new()
		shell.add_theme_constant_override("separation", 6)
		panel.add_child(shell)
		var stage_data: Dictionary = stages[index] if index < stages.size() and stages[index] is Dictionary else {}
		var title := _heading_label(String(stage_data.get("title", "")))
		title.name = "ForgeStage%dTitle" % (index + 1)
		shell.add_child(title)
		var status := _note_label(String(stage_data.get("status", "")))
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
	if operation not in FORGE_TRACKS or operation == _forge_operation:
		return
	_forge_candidate_index = 0
	action_requested.emit("forge", "select_forge_operation", {"operation": operation, "revision": _forge_revision()})


func _build_forge_browse(parent: Container) -> void:
	var panel := _section_in(parent, "Future Outcome", "ForgeBrowsePanel")
	var candidates := _forge_candidates()
	var browse := _body_label("No future has been forecast. Choose equipment and Law Tokens, then use the button below.")
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
		relation, _forge_candidate_index + 1, candidates.size(),
		_forge_candidate_cost(candidate), _law_token_name(_forge_session_operation(), _forge_candidate_cost(candidate)),
		_forge_candidate_change_text(candidate),
	]
	var equipped := bool(candidate.get("target_is_equipped", false))
	panel.add_child(_note_label("Current Build Changes After Commit" if equipped else "Commit leaves current build unchanged; expected changes when equipped"))
	var impact := _as_dictionary(candidate.get("build_comparison", {}))
	_add_interface_changes(panel, impact)
	var comparison = preload("res://src/presentation/equipment_comparison.gd").new()
	comparison.name = "ForgeBuildComparison"
	comparison.present(impact.get("current_parameters", {}), impact.get("result_parameters", {}), "After Commit" if equipped else "When Equipped")
	panel.add_child(comparison)
	var result_item := _forge_candidate_result_item_view(candidate)
	var detail := _add_full_item_detail_button(panel, result_item, "Forge Forecast · " + _forge_item_title(result_item),
		"Forecast Outcome\n%s\n\n%s" % [_forge_readable_item_text(result_item), _forge_build_change_text(candidate)])
	detail.name = "ForgeFullResultDetail"
	detail.text = "Full Equipment and Build Details"



func _on_forge_confirm_selection() -> void:
	var session := _forge_session()
	if session.is_empty() or String(session.get("selected_candidate_id", "")).is_empty():
		return
	var session_id := String(session.get("session_id", ""))
	if session_id == _forge_committed_session_id:
		return
	_forge_committed_session_id = session_id
	action_requested.emit("forge","forge_commit",{"session_id": session_id})
	_apply_presentation()


func _on_forge_cancel_selection() -> void:
	var session_id := String(_forge_session().get("session_id", ""))
	if not session_id.is_empty():
		action_requested.emit("forge", "forge_cancel", {"session_id": session_id})


## Target inventory inside the first lane of the two-column forge composition.
func _build_forge_inventory(parent: Container, inventory: Array, target_id: String) -> void:
	var section := _section_in(parent, "Select Forge Target", "ForgeInventorySection")
	var panel := _section_panel(section)
	if panel != null:
		panel.custom_minimum_size.x = 0.0
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_forge_backpack_items = inventory.duplicate(true)
	var row := VBoxContainer.new()
	row.name = "ForgeBackpackRow"
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 4)
	section.add_child(row)
	var backpack := EquipmentBackpackGridScript.new()
	var initial_backpack_id := _forge_backpack_selection if not _forge_backpack_selection.is_empty() else target_id
	backpack.configure(_backpack_entries(inventory, "ForgeBackpackIcon"), initial_backpack_id, 4, "ForgeBackpack", 1)
	backpack.item_inspected.connect(_on_forge_backpack_inspected)
	row.add_child(backpack)
	_forge_backpack_detail_region = Control.new()
	_forge_backpack_detail_region.name = "BackpackDetail"
	_forge_backpack_detail_region.custom_minimum_size = Vector2(0, 104)
	_forge_backpack_detail_region.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_forge_backpack_detail_region.clip_contents = true
	row.add_child(_forge_backpack_detail_region)
	_forge_backpack_detail = VBoxContainer.new()
	_forge_backpack_detail.name = "BackpackDetailContent"
	_forge_backpack_detail.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_forge_backpack_detail.offset_left = 8.0
	_forge_backpack_detail.offset_top = 6.0
	_forge_backpack_detail.offset_right = -8.0
	_forge_backpack_detail.offset_bottom = -6.0
	_forge_backpack_detail_region.add_child(_forge_backpack_detail)
	if _forge_backpack_selection.is_empty() or _inventory_item_by_id(inventory, _forge_backpack_selection).is_empty():
		_forge_backpack_selection = target_id
	_render_forge_backpack_detail(_forge_backpack_selection)
	_forge_backpack_detail_region.visible = false


func _on_forge_backpack_inspected(instance_id: String) -> void:
	if instance_id.is_empty():
		call_deferred("_finish_forge_backpack_exit")
		return
	_forge_backpack_selection = instance_id
	_render_forge_backpack_detail(instance_id)


func _finish_forge_backpack_exit() -> void:
	if _item_detail_dialog != null and _item_detail_dialog.visible:
		return
	var focus_owner := get_viewport().gui_get_focus_owner() if get_viewport() != null else null
	if focus_owner != null and _forge_backpack_detail_region != null \
		and (_forge_backpack_detail_region == focus_owner or _forge_backpack_detail_region.is_ancestor_of(focus_owner)):
		return
	var backpack := find_child("EquipmentBackpack", true, false)
	if backpack != null and backpack.has_method("inspected_item_id") \
		and not String(backpack.call("inspected_item_id")).is_empty():
		return
	_forge_backpack_selection = ""
	if backpack != null and backpack.has_method("select_item"):
		backpack.call("select_item", String(_facility_data.get("target_instance_id", "")))
	_render_forge_backpack_detail("")


func _render_forge_backpack_detail(instance_id: String) -> void:
	if _forge_backpack_detail == null or not is_instance_valid(_forge_backpack_detail):
		return
	_clear_children(_forge_backpack_detail)
	var item := _inventory_item_by_id(_forge_backpack_items, instance_id)
	if item.is_empty():
		if _forge_backpack_detail_region != null:
			_forge_backpack_detail_region.visible = false
		return
	if _forge_backpack_detail_region != null:
		_forge_backpack_detail_region.visible = true
	var instance_token := _stable_node_token(instance_id)
	var selected := instance_id == String(_facility_data.get("target_instance_id", ""))
	var action_row := _make_row("BackpackActions")
	_forge_backpack_detail.add_child(action_row)
	var name_label := _body_label(_forge_item_title(item))
	name_label.name = "BackpackDetailName"
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.max_lines_visible = 2
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.tooltip_text = "%s\n%s" % [_forge_item_title(item), _item_difference_summary_text(item)]
	action_row.add_child(name_label)
	var choose := Button.new()
	choose.name = "SelectForgeItem_%s" % instance_token
	choose.text = "Current Target" if selected else "Set as Target"
	choose.disabled = selected
	choose.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	choose.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	choose.pressed.connect(_on_forge_target_selected.bind(instance_id))
	action_row.add_child(choose)
	_add_full_item_detail_button(
		action_row,
		item,
		_forge_item_title(item),
		_forge_readable_item_text(item)
	)
	_track_backpack_detail_actions(_forge_backpack_detail_region, "forge")


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


## The pinned forge dock: candidate controls, exact Law Tally cost, and the
## snapshot summary. It stays visible while the tracks above scroll.
func _build_forge_dock() -> void:
	if not bool(_facility_data.get("unlocked", false)):
		return
	var session := _forge_session()
	if session.is_empty():
		var reveal := Button.new()
		reveal.name = "ForgeReveal"
		reveal.add_theme_stylebox_override("normal", ShellThemeScript.panel_style("selected"))
		reveal.text = "Forecast with %s · No Tokens Spent Yet" % _law_token_name(_forge_operation)
		reveal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		reveal.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		reveal.disabled = not _forge_operation_block_reason(_forge_operation).is_empty() or not _forge_can_start()
		reveal.pressed.connect(_on_forge_reveal)
		_actions.add_child(reveal)
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
	_actions.add_child(previous)
	var next := Button.new()
	next.name = "ForgeNextCandidate"
	next.text = "Next"
	next.tooltip_text = "Next Candidate"
	next.autowrap_mode = TextServer.AUTOWRAP_OFF
	next.custom_minimum_size.x = 100
	next.disabled = candidates.size() <= 1
	next.pressed.connect(_on_forge_candidate_shift.bind(1))
	_actions.add_child(next)
	if bool(session.get("has_more", false)):
		var more := Button.new()
		more.name = "ForgeRevealMore"
		more.text = "Forecast More"
		more.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		more.custom_minimum_size.x = 120
		more.pressed.connect(_on_forge_reveal_more)
		_actions.add_child(more)
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
		_actions.add_child(select)
	else:
		var confirm := Button.new()
		confirm.name = "ForgeConfirmSelection"
		confirm.add_theme_stylebox_override("normal", ShellThemeScript.panel_style("selected"))
		var selected := _forge_candidate_by_id(selected_id)
		confirm.text = "Confirm Commit · Spend %d %s" % [_forge_candidate_cost(selected), _law_token_name(_forge_session_operation(), _forge_candidate_cost(selected))]
		if not _forge_candidate_affordable(selected):
			confirm.text = "Not Enough Law Tokens · Need %d %s, Have %d" % [
				_forge_candidate_cost(selected),
				_law_token_name(_forge_session_operation(), _forge_candidate_cost(selected)),
				_law_tally(_forge_session_operation()),
			]
		confirm.disabled = selected.is_empty() or not _forge_candidate_affordable(selected) or String(session.get("session_id", "")) == _forge_committed_session_id
		confirm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		confirm.custom_minimum_size.x = 280
		confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		confirm.pressed.connect(_on_forge_confirm_selection)
		_actions.add_child(confirm)
	var cancel := Button.new()
	cancel.name = "ForgeCancelSelection"
	cancel.text = "Cancel This Forge"
	cancel.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cancel.custom_minimum_size.x = 180
	cancel.disabled = _forge_session().is_empty()
	cancel.pressed.connect(_on_forge_cancel_selection)
	_actions.add_child(cancel)


## Two coherent columns: what the current build actually is, and what the last
## matching report actually says. The first screen is the four readable cards — the
## growth conclusion, the interfaces that are wired, the ones that are missing and
## the next step — and then the matched report's R / g / event count over its trace.
## The parameter wall, the fingerprint and the untranslated report line wait behind
## the page's own reference toggle. A fingerprint that has not passed the range
## shows Unverified on both sides; unknown is never written as a failure, and a report
## from another build is never drawn as this build's reading.
func _build_training() -> void:
	var resolved := _training_resolved_build()
	if resolved.is_empty():
		var unavailable := _section("Training Data Unavailable", "TrainingUnavailable")
		unavailable.add_child(_body_label("The current build cannot be resolved: stats, connected interfaces, and growth conclusions are unavailable."))
		_add_payload_action("Run Training Trial", "run_training_trial", {}, "RunTrainingTrial")
		return
	var training := _as_dictionary(_facility_data.get("training", {}))
	var fingerprint := String(resolved.get("build_fingerprint", "")).strip_edges()
	var matched := _matched_training_report(training, fingerprint)
	var verified := not matched.is_empty()
	var row := _page_lead_row()
	var current_panel := _section_in(row, "Current Build", "TrainingActiveBuild")
	var growth_conclusion := "Unverified"
	if verified:
		var classification := String(matched.get("state", "")).strip_edges()
		if not classification.is_empty():
			growth_conclusion = String(TRAINING_GROWTH_NAMES.get(classification, classification))
	_training_card(current_panel, "Growth Conclusion", growth_conclusion, true, "TrainingConclusionCard")
	current_panel.add_child(_note_label("Growth conclusions appear only after this fingerprint passes Training; unverified does not mean failure."))
	_training_card(current_panel, "Connected Interfaces", _training_interface_text(resolved.get("connected_interfaces", [])), false, "TrainingConnectedCard")
	_training_card(current_panel, "Missing Interfaces", _training_interface_text(resolved.get("missing_interfaces", [])), false, "TrainingMissingCard")
	var report_panel := _section_in(row, "Current Build Training Report", "TrainingLastReport")
	var identity := _note_label("Status: Complete · This report belongs to the current build") if verified else _note_label("Status: Not Yet Trained\nNext Step: Run Training Trial")
	identity.name = "TrainingReportIdentity"
	report_panel.add_child(identity)
	var action := String(matched.get("action", "")).strip_edges()
	if not action.is_empty():
		_training_card(report_panel, "Next Step", action, false, "TrainingNextStepCard")
	var readings := _body_label(_training_readings_text(matched))
	readings.name = "TrainingReading"
	report_panel.add_child(readings)
	_add_growth_trace(report_panel, matched)
	if matched.is_empty():
		report_panel.add_child(_note_label("Unknown does not mean failure: no growth conclusion is given until training completes."))
	else:
		report_panel.add_child(_note_label("These readings come from the current build's training results."))
	_build_training_details(resolved, training, fingerprint, verified)
	_add_payload_action("Run Training Trial", "run_training_trial", {}, "RunTrainingTrial")


## One readable card of the training page: an 18px state word over the value the
## page is allowed to read. The cards share the cold slate surface and the dim edge
## of the loadout cells; only the card that carries the conclusion takes the bright
## old-copper focus edge, so the one reading the first screen has to deliver is the
## one block that is marked. Nothing here is derived: the value is the resolved
## Build's own word or the matched report's own sentence.
func _training_interface_text(value: Variant) -> String:
	var labels: Array[String] = []
	for id: Variant in _as_array(value):
		labels.append(EarlyInterfaceVocabularyScript.player_name(String(id)))
	return _joined_or_none(labels)


func _training_card(parent: Container, title_text: String, value_text: String, focused: bool, node_name: String) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = node_name
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", _slot_cell_box(focused, not focused))
	parent.add_child(card)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 4)
	card.add_child(content)
	content.add_child(_note_label(title_text))
	content.add_child(_body_label(value_text))
	return card


## The page's reference layer: the complete public parameters, the build fingerprint
## and the raw report line, which carries the seed, the complete generational string
## and every untranslated field. It is folded by default and owns its own toggle, so
## unfolding the loadout's detail block never unfolds this one. Nothing is removed
## from the page: the surface states the conclusion, the fold keeps the evidence.
func _build_training_details(resolved: Dictionary, training: Dictionary, fingerprint: String, verified: bool) -> void:
	var section := _section("Reference Data", "TrainingReferenceData")
	var toggle := Button.new()
	toggle.name = "TrainingDetailsToggle"
	toggle.text = "Hide Training Details" if _training_details_open else "Show Training Details (Final Stats / Full Curve)"
	toggle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toggle.pressed.connect(_on_training_details_toggled)
	section.add_child(toggle)
	if not _training_details_open:
		return
	var parameters := _as_dictionary(resolved.get("final_parameters", {}))
	var parameter_lines: Array[String] = []
	for parameter in PlayerReadableBuildScript.PARAMETER_ORDER:
		parameter_lines.append(_readable_build.format_parameter(parameter, parameters.get(parameter, null)))
	_fact_label(section, "Final Stats", "  ·  ".join(parameter_lines))
	_fact_label(section, "Connected Interfaces", _training_interface_text(resolved.get("connected_interfaces", [])))
	_fact_label(section, "Missing Interfaces", _training_interface_text(resolved.get("missing_interfaces", [])))
	section.add_child(_body_label(_training_report_text(training, fingerprint, verified)))


func _on_training_details_toggled() -> void:
	_training_details_open = not _training_details_open
	if _built:
		_apply_presentation()


## The generational trace of the matching report and nothing else. No report, a
## report from another build, or an unverified build leaves the page with its text
## only: an earlier valid curve is never redrawn as if it were the current one.
func _add_growth_trace(parent: Container, matched: Dictionary) -> void:
	if matched.is_empty():
		return
	var points := _growth_curve_points(matched.get("growth_curve", []))
	if points.size() < 2:
		return
	var trace := TrainingTraceViewScript.new()
	trace.name = "TrainingGrowthTrace"
	parent.add_child(trace)
	trace.present(points)
	_training_trace = trace
	var axis := _note_label(trace.axis_caption())
	axis.name = "TrainingGrowthTraceAxis"
	parent.add_child(axis)
	# The trace always draws every point of the reading line; only its labels thin out
	# when they would collide, so the rule is stated instead of implied.
	parent.add_child(_note_label("The curve retains every sample from this trial."))


## The generational trace the training page really drew, for tests and the report.
func training_trace_report() -> Dictionary:
	if _training_trace == null:
		return {"present": false, "drawing": false}
	var report: Dictionary = _training_trace.trace_report()
	report["present"] = true
	return report


## The one report the page is allowed to read: the build must have passed the test
## range and the stored report must carry exactly that fingerprint. Anything else is
## a report about a different build, and is reported as "not verified" instead of
## being shown as this build's readings.
func _matched_training_report(training: Dictionary, fingerprint: String) -> Dictionary:
	if fingerprint.is_empty():
		return {}
	var reports_by_fingerprint := _as_dictionary(training.get("reports_by_fingerprint", {}))
	var report := _as_dictionary(reports_by_fingerprint.get(fingerprint, {}))
	if report.is_empty() or String(report.get("build_fingerprint", "")).strip_edges() != fingerprint:
		return {}
	return report.duplicate(true)


## The training page only consumes the snapshot's resolved_build plus the
## training verification/report fields. It never reads available_builds,
## last_result, or the profile, and it never recomputes a Build.
func _training_resolved_build() -> Dictionary:
	var value: Variant = _facility_data.get("resolved_build", null)
	if not value is Dictionary:
		return {}
	var resolved: Dictionary = value
	if not bool(resolved.get("ok", true)):
		return {}
	if String(resolved.get("build_fingerprint", "")).strip_edges().is_empty():
		return {}
	return resolved


## The three numbers one matching report owns, and nothing else. With no matching
## report the line is the stand-in sentence: an older build's R, g or event count is
## never reprinted here as if it belonged to the current Build.
func _training_readings_text(report: Dictionary) -> String:
	if report.is_empty():
		return "Current build not yet trained"
	return "Training readings: R %s · g %s · Total Events %s" % [
		_format_value(report.get("R", report.get("r", "Unknown"))),
		_format_value(report.get("g", "Unknown")),
		String(report.get("event_count_display", _format_value(report.get("event_count", "Unknown")))),
	]


## The complete raw report line of the one matching report. It is the reference
## layer, not the reading: it restates the matched numbers and adds the state word,
## the reproducible seed, the complete generational string and the report's own
## action sentence. A mismatching or unverified build gets the stand-in sentence and
## no field of the old report at all.
func _training_report_text(training: Dictionary, fingerprint: String, verified: bool) -> String:
	var report := _matched_training_report(training, fingerprint) if verified else {}
	if report.is_empty():
		return "Current build not yet trained"
	var lines: Array[String] = [
		_training_readings_text(report),
		"Growth Classification: %s" % String(TRAINING_GROWTH_NAMES.get(String(report.get("state", "Unknown")), String(report.get("state", "Unknown")))),
	]
	var curve := _growth_curve_line(report.get("growth_curve", []))
	if not curve.is_empty():
		lines.append("Event Growth Curve: %s" % curve)
	var action := String(report.get("action", "")).strip_edges()
	if not action.is_empty():
		lines.append("Next Step: %s" % action)
	return "\n".join(lines)


## Renders growth_curve verbatim for display only. It keeps exactly the points that
## are Dictionaries with an exact-int generation and a non-empty String events_display;
## it never derives or recomputes any value.
func _growth_curve_line(value: Variant) -> String:
	var points := _growth_curve_points(value)
	if points.is_empty():
		return ""
	var rendered: Array[String] = []
	for point in points:
		rendered.append("G%d:%s" % [int(point.get("generation", 0)), String(point.get("events_display", ""))])
	return " → ".join(rendered)


## The growth_curve points the page may draw, verbatim and in generation order. The
## filter is the text line's filter, so a trace can never show a point the report
## line drops. The magnitude field is only ever the report's own comparable number:
## the finite events_float it already carries, or its display string when that string
## is a plain decimal or scientific reading. Nothing is recomputed from R or g, and a
## point without such a number keeps magnitude NAN, which is what turns a trace into
## the order-only form instead of a made-up height.
func _growth_curve_points(value: Variant) -> Array[Dictionary]:
	if not value is Array:
		return []
	var points: Array[Dictionary] = []
	for entry: Variant in (value as Array):
		if not entry is Dictionary:
			continue
		var point: Dictionary = entry
		var generation: Variant = point.get("generation", null)
		if typeof(generation) != TYPE_INT:
			continue
		var events: Variant = point.get("events_display", "")
		if not events is String:
			continue
		var events_display := String(events).strip_edges()
		if events_display.is_empty():
			continue
		points.append({
			"generation": int(generation),
			"events_display": events_display,
			"magnitude": _comparable_magnitude(point, events_display),
		})
	points.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return int(left.get("generation", 0)) < int(right.get("generation", 0))
	)
	return points


func _comparable_magnitude(point: Dictionary, events_display: String) -> float:
	var raw: Variant = point.get("events_float", null)
	if _is_number(raw) and is_finite(float(raw)) and float(raw) > 0.0:
		return float(raw)
	if not _is_decimal_reading(events_display):
		return NAN
	return float(events_display)


## True when a display string is a plain decimal or scientific reading, so the very
## same number can stand on an axis. A tower reading such as 10^^2(3.5), a unit
## suffix or any prose is not a comparable reading and keeps the trace on its
## order-only form.
func _is_decimal_reading(text: String) -> bool:
	var body := text.strip_edges()
	if body.is_empty():
		return false
	var digits := 0
	var digits_after_exponent := 0
	var seen_dot := false
	var seen_exponent := false
	for index in body.length():
		var character := body[index]
		if character >= "0" and character <= "9":
			digits += 1
			if seen_exponent:
				digits_after_exponent += 1
			continue
		if character == "." and not seen_dot and not seen_exponent:
			seen_dot = true
			continue
		if (character == "e" or character == "E") and not seen_exponent and digits > 0:
			seen_exponent = true
			continue
		if character == "+" or character == "-":
			if index == 0:
				continue
			if body[index - 1] == "e" or body[index - 1] == "E":
				continue
		return false
	if digits == 0:
		return false
	if seen_exponent and digits_after_exponent == 0:
		return false
	return true


func _build_proxy() -> void:
	var proxy := _as_dictionary(_facility_data.get("proxy", {}))
	var progression := _as_dictionary(_facility_data.get("progression", {}))
	var unlocked := bool(proxy.get("unlocked", progression.get("proxy_unlocked", false)))
	if not unlocked:
		_build_proxy_core_strip(CORE_ORDER.duplicate(), false)
		var locked := _section("Proxy Bay · Sealed", "ProxyLocked")
		locked.add_child(_body_label("Unlock requirement: defeat the Threshold Colossus in Manual.\nAuto cannot be selected before the first kill."))
		locked.add_child(_note_label("Actions and configuration are unavailable while sealed."))
		var capability := _section("Abilities After Unlock", "ProxyUnlockPreview")
		capability.add_child(_body_label("The first-kill reward previews four Common cores: find the nearest target -> maintain distance along the shortest viable path (retreat at close range) -> cast skill slot 1."))
		return
	var core_ids := _proxy_core_ids(proxy)
	_build_proxy_core_strip(core_ids, true)
	var status := _section("Auto Available", "ProxyAuto")
	status.add_child(_body_label("The Proxy Bay is unlocked for Auto contracts. Your four-slot build freezes at contract start; later changes do not affect an active contract."))
	status.add_child(_note_label("Attachments Not Yet Available"))
	_build_proxy_inventory(proxy, core_ids)
	_build_proxy_distance_settings(proxy, core_ids)
	var progress := _section("Early Progress", "ProxyProgress")
	_fact_label(progress, "Auto Wins", str(int(progression.get("auto_contract_wins", 0))))
	_fact_label(progress, "Early Chapter Complete", "Yes" if bool(progression.get("early_game_complete", false)) else "No")


## The four fixed cores of the first-kill reward, each in its own slot cell. The
## locked page previews them with the reward wording; the unlocked page states
## which ones are connected and keeps the same fixed order.
func _build_proxy_core_strip(core_ids: Array[String], unlocked: bool) -> void:
	var heading := "First-Kill Reward · Four Common Cores (Sealed Preview)"
	if unlocked:
		heading = "Current Assembly · Perception -> Action -> Execution -> Memory"
	var section := _section_in(_page_lead_row(), heading, "ProxyCoreStrip")
	var row := _make_row("ProxyCoreRow")
	section.add_child(row)
	for core_id in core_ids:
		row.add_child(_proxy_core_cell(core_id, unlocked))


func _proxy_core_cell(core_id: String, unlocked: bool) -> PanelContainer:
	var cell := PanelContainer.new()
	cell.name = "ProxyCoreCell_%s" % _stable_node_token(core_id)
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.add_theme_stylebox_override("panel", _slot_cell_box(unlocked, not unlocked))
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 6)
	cell.add_child(content)
	var canonical := _art.canonical_id("proxy_core", core_id)
	var texture := _body_icon_texture(canonical)
	if texture != null:
		var icon := _icon_node(texture, FacilityArtScript.ICON_NATIVE_SIZE, true)
		icon.name = "%s_%s" % ["CoreIcon" if unlocked else "RewardCoreIcon", _stable_node_token(canonical)]
		icon.set_meta("canonical_id", canonical)
		content.add_child(icon)
	content.add_child(_body_label("%s · %s" % [_proxy_core_display_name(core_id, {}), String(CORE_ROLES.get(core_id, "Core"))]))
	content.add_child(_note_label("Connected" if unlocked else "Sealed"))
	return cell


## The profile's own core list, mapped onto the published fixed cores and kept in
## the order it was stored in. An empty or unknown list falls back to the four
## fixed cores; an unknown word maps to nothing and keeps its own text cell.
func _proxy_core_ids(proxy: Dictionary) -> Array[String]:
	var proxy_build := _as_dictionary(proxy.get("build", {}))
	var by_slot := {}
	var catalog := _as_dictionary(proxy.get("catalog", {}))
	for raw_core in _as_array(proxy_build.get("cores", proxy.get("cores", []))):
		var core_id := _core_canonical_name(raw_core)
		if core_id.is_empty() or core_id not in IMPLEMENTED_CORE_IDS:
			continue
		var slot := String(_as_dictionary(catalog.get(core_id, {})).get("slot", _proxy_core_slot(core_id)))
		if slot in PROXY_SLOT_ORDER and not by_slot.has(slot):
			by_slot[slot] = core_id
	var ids: Array[String] = []
	for slot in PROXY_SLOT_ORDER:
		if by_slot.has(slot):
			ids.append(String(by_slot[slot]))
	if ids.size() != PROXY_SLOT_ORDER.size():
		return CORE_ORDER.duplicate()
	return ids


func _build_proxy_inventory(proxy: Dictionary, installed_ids: Array[String]) -> void:
	var section := _section("Core Inventory and Protocols", "ProxyInventory")
	var catalog := _as_dictionary(proxy.get("catalog", {}))
	var owned := {}
	for value in _as_array(proxy.get("inventory", [])):
		if not value is Dictionary:
			continue
		var item := value as Dictionary
		var core_id := String(item.get("id", "")).strip_edges()
		if core_id in IMPLEMENTED_CORE_IDS:
			owned[core_id] = item
	for core_id in IMPLEMENTED_CORE_IDS:
		var definition := _as_dictionary(catalog.get(core_id, {}))
		if definition.is_empty():
			continue
		var row := VBoxContainer.new()
		row.name = "ProxyInventoryRow_%s" % _stable_node_token(core_id)
		row.add_theme_constant_override("separation", 4)
		section.add_child(row)
		var slot := String(definition.get("slot", _proxy_core_slot(core_id)))
		var state := "Not Owned"
		if core_id in installed_ids:
			state = "Installed"
		elif owned.has(core_id):
			state = "In Storage"
		row.add_child(_body_label("%s · %s · %s" % [_proxy_core_display_name(core_id, definition), String(PROXY_SLOT_LABELS.get(slot, slot)), state]))
		row.add_child(_note_label("Protocol: %s" % String(definition.get("protocol", _as_dictionary(owned.get(core_id, {})).get("protocol", "Not Recorded")))))
		if owned.has(core_id) and core_id not in installed_ids:
			var button := Button.new()
			button.name = "ProxyEquip_%s" % _stable_node_token(core_id)
			button.text = "Install in %s" % String(PROXY_SLOT_LABELS.get(slot, slot))
			button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			button.pressed.connect(_on_payload_action_pressed.bind("equip_proxy_core", {"core_id": core_id}))
			row.add_child(button)


func _build_proxy_distance_settings(proxy: Dictionary, installed_ids: Array[String]) -> void:
	if "distance_keeping_gait" not in installed_ids:
		return
	var section := _section("Distance Band", "ProxyDistanceBand")
	section.add_child(_note_label("All distance bands scale with Piercing Arrow's actual range."))
	var settings := _as_dictionary(_as_dictionary(proxy.get("build", {})).get("settings", {}))
	var current := String(_as_dictionary(settings.get("distance_keeping_gait", {})).get("distance_band", "mid"))
	if current not in ["near", "mid", "far"]:
		current = "mid"
	var labels := {"near": "Near", "mid": "Mid", "far": "Far"}
	for band in ["near", "mid", "far"]:
		var button := Button.new()
		button.name = "ProxyDistanceBand_%s" % band
		button.text = "%s (Current)" % labels[band] if band == current else String(labels[band])
		button.disabled = band == current
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if band != current:
			button.pressed.connect(_on_payload_action_pressed.bind("configure_proxy_core", {"core_id": "distance_keeping_gait", "settings": {"distance_band": band}}))
		section.add_child(button)


func _proxy_core_slot(core_id: String) -> String:
	if core_id in ["near_enemy_horizon", "marking_prism"]:
		return "perception"
	if core_id in ["direct_gait", "distance_keeping_gait"]:
		return "movement"
	if core_id == "single_key_execution":
		return "execution"
	if core_id == "short_trace_memory":
		return "memory"
	return ""


func _proxy_core_display_name(core_id: String, definition: Dictionary) -> String:
	var name := String(definition.get("name", "")).strip_edges()
	if not name.is_empty():
		return name
	var labels := {
		"near_enemy_horizon": "Near-Enemy Sight",
		"marking_prism": "Mark Prism",
		"direct_gait": "Direct-Approach Legs",
		"distance_keeping_gait": "Range-Keeping Legs",
		"single_key_execution": "Single-Key Executor",
		"short_trace_memory": "Short-Trace Memory",
	}
	return String(labels.get(core_id, core_id))


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


func _forge_session() -> Dictionary:
	var session := _as_dictionary(_facility_data.get("session", {}))
	if String(session.get("session_id", "")).strip_edges().is_empty():
		return {}
	return session


func _restore_forge_session_cursor() -> void:
	var session := _forge_session()
	if session.is_empty():
		_forge_candidate_index = 0
		_forge_committed_session_id = ""
		return
	# A fresh authoritative presentation of the still-selected session means the
	# previous commit attempt was rejected or its save failed. Re-arm exactly that
	# choice for retry; a local rebuild after the press does not call this method,
	# so rapid repeated presses remain suppressed.
	if String(session.get("session_id", "")) != _forge_committed_session_id or String(session.get("state", "")) == "selected":
		_forge_committed_session_id = ""
	var selected_id := String(session.get("selected_candidate_id", ""))
	var candidates := _forge_candidates()
	for index in candidates.size():
		if String((candidates[index] as Dictionary).get("candidate_id", "")) == selected_id:
			_forge_candidate_index = index
			return
	_forge_candidate_index = clampi(_forge_candidate_index, 0, maxi(0, candidates.size() - 1))


func _forge_candidates() -> Array[Dictionary]:
	var session := _forge_session()
	var revealed_count := int(session.get("revealed_count", 0))
	if revealed_count <= 0:
		return []
	var result: Array[Dictionary] = []
	for raw_candidate in _as_array(session.get("candidates", [])):
		if raw_candidate is Dictionary and not String((raw_candidate as Dictionary).get("candidate_id", "")).is_empty():
			result.append((raw_candidate as Dictionary).duplicate(true))
			if result.size() >= revealed_count:
				break
	return result


func _current_forge_candidate() -> Dictionary:
	var candidates := _forge_candidates()
	if candidates.is_empty():
		return {}
	_forge_candidate_index = clampi(_forge_candidate_index, 0, candidates.size() - 1)
	return candidates[_forge_candidate_index]


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


func _forge_candidate_cost(candidate: Dictionary) -> int:
	var sequence := maxi(1, int(candidate.get("sequence_number", 1)))
	return maxi(1, int(candidate.get("cost", sequence)))


func _forge_candidate_family_name(candidate: Dictionary) -> String:
	var formatted := _readable_build.format_affix(candidate)
	var named := formatted.get_slice(": ", 0)
	var tier := _readable_build.tier_label(int(candidate.get("tier", 0)))
	return named.trim_suffix(" " + tier) if named.ends_with(" " + tier) else named


func _forge_candidate_change_text(candidate: Dictionary) -> String:
	var result := "%s %s" % [
		_forge_candidate_family_name(candidate),
		_readable_build.tier_label(int(candidate.get("tier", 0))),
	]
	var operation := String(candidate.get("operation", _forge_session_operation()))
	if operation == "inscribe":
		return "New: %s" % result
	var previous_name := String(candidate.get("previous_family_name", "Existing Affix"))
	var previous_tier := _readable_build.tier_label(int(candidate.get("previous_tier", 0)))
	return "%s: %s %s → %s" % [
		"Automatic Refine" if operation == "refine" else "Automatic Rewrite",
		previous_name,
		previous_tier,
		result,
	]


func _forge_session_operation() -> String:
	var operation := String(_forge_session().get("operation", _forge_operation))
	return operation if operation in FORGE_TRACKS else _forge_operation


func _forge_revision() -> int:
	return int(_facility_data.get("revision", -1))


func _law_token_name(operation: String, count: int = -1) -> String:
	var label := String(LAW_TALLY_LABELS.get(operation, "Law Tokens"))
	return label.trim_suffix("s") if count == 1 else label


func _law_tally(operation: String, tallies: Dictionary = {}) -> int:
	var source := tallies if not tallies.is_empty() else _as_dictionary(_facility_data.get("law_tallies", {}))
	return maxi(0, int(source.get(operation, 0)))


func _forge_candidate_affordable(candidate: Dictionary) -> bool:
	var session := _forge_session()
	var affordable_count := maxi(0, int(session.get("affordable_count", 0)))
	var sequence := maxi(1, int(candidate.get("sequence_number", 1)))
	return sequence <= affordable_count and _forge_candidate_cost(candidate) <= _law_tally(_forge_session_operation())


func _forge_operation_block_reason(operation: String) -> String:
	if not bool(_facility_data.get("unlocked", false)):
		return "The Law Token Forge is not yet unlocked."
	if _as_dictionary(_facility_data.get("target_item", {})).is_empty() or String(_facility_data.get("target_instance_id", "")).is_empty():
		return "Select target equipment first."
	match String(_facility_data.get("blocked_reason", "")):
		"affix_limit_reached":
			return "Affixes full (maximum %d); cannot inscribe." % LawForgeScript.MAX_AFFIXES
		"affix_required":
			return "%s requires at least one existing affix." % String(FORGE_TRACK_TITLES.get(operation, "This operation"))
		"rewrite_not_legal":
			return "This item has no eligible new affix for rewriting."
		"max_tier":
			return "All existing affixes are at their highest tier and cannot be refined."
	if _law_tally(operation) <= 0:
		return "No %s available; cannot forecast a committable outcome." % _law_token_name(operation)
	return ""


func _forge_can_start() -> bool:
	return _forge_session().is_empty() and not String(_facility_data.get("target_instance_id", "")).is_empty()


func _on_forge_reveal() -> void:
	if not _forge_can_start() or not _forge_operation_block_reason(_forge_operation).is_empty():
		return
	action_requested.emit("forge", "forge_reveal", {"revision": _forge_revision()})


func _on_forge_reveal_more() -> void:
	var session_id := String(_forge_session().get("session_id", ""))
	if not session_id.is_empty() and bool(_forge_session().get("has_more", false)):
		action_requested.emit("forge", "forge_reveal_more", {"session_id": session_id})


func _on_forge_candidate_shift(offset: int) -> void:
	var candidates := _forge_candidates()
	if candidates.is_empty():
		return
	_forge_candidate_index = posmod(_forge_candidate_index + offset, candidates.size())
	if _built:
		_apply_presentation()


func _on_forge_select_current_candidate() -> void:
	var session_id := String(_forge_session().get("session_id", ""))
	var candidate_id := String(_current_forge_candidate().get("candidate_id", ""))
	if session_id.is_empty() or candidate_id.is_empty():
		return
	action_requested.emit("forge", "forge_select_candidate", {"session_id": session_id, "candidate_id": candidate_id})


func _on_forge_target_selected(instance_id: String) -> void:
	if instance_id.is_empty() or instance_id == String(_facility_data.get("target_instance_id", "")):
		return
	_forge_candidate_index = 0
	action_requested.emit("forge", "select_forge_item", {"instance_id": instance_id, "revision": _forge_revision()})


## Difference summary for one forge inventory item, rendered as the button's second
## line so same-base Items with different affixes stay distinguishable at a glance.
## Every value is read directly from the passed forge snapshot; this never
## re-evaluates the build and never shows a formula, TTK, power rating, or
## instance_id. Up to two affixes as family_name + Chinese tier, then a "+N" overflow; with
## no affixes it falls back to rune/law; with neither it says "No Affixes".
func _item_difference_summary_text(item: Dictionary) -> String:
	return _equipment_model.compact_difference(item)


func _forge_item_title(item: Dictionary) -> String:
	if item.is_empty():
		return "No Target Equipment Selected"
	return String(item.get("base_name", _item_display_name(item)))


func _forge_readable_item_text(item: Dictionary) -> String:
	if item.is_empty():
		return "No Equipment Data"
	return "%s\n%s" % [_forge_item_title(item), _readable_build.format_item(item)]


func _forge_candidate_result_item_view(candidate: Dictionary) -> Dictionary:
	var view := _as_dictionary(candidate.get("result_item_view", {}))
	return view if not view.is_empty() else _as_dictionary(candidate.get("result_item", {}))


func _forge_build_change_text(candidate: Dictionary) -> String:
	var comparison := _as_dictionary(candidate.get("build_comparison", {}))
	var current := _as_dictionary(comparison.get("current_parameters", {}))
	var after := _as_dictionary(comparison.get("result_parameters", {}))
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
	var comparison_text := _readable_build.format_comparison(current, after)
	var lines: Array[String] = ["%s: " % heading]
	if comparison_text.is_empty():
		lines.append("No Stat Changes")
	else:
		lines.append(comparison_text)
	_append_preview_group(lines, comparison, "interfaces_gained", "Interfaces Gained")
	_append_preview_group(lines, comparison, "interfaces_lost", "Interfaces Lost")
	return "\n".join(lines)


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


func _nested_value(source: Dictionary, path: Array[String], fallback: Variant) -> Variant:
	var cursor: Variant = source
	for key in path:
		if not cursor is Dictionary or not (cursor as Dictionary).has(key):
			return fallback
		cursor = (cursor as Dictionary).get(key)
	return cursor


func _component_text(build: Dictionary, key: String, fallback: String) -> String:
	var value: Variant = build.get("%s_id" % key, build.get(key, null))
	if value == null:
		value = _nested_value(build, ["components", key], null)
	if value == null and build.has("%ss" % key):
		var values := _as_array(build.get("%ss" % key, []))
		value = values[0] if not values.is_empty() else null
	var text := _display_value(value)
	if key == "skill" and not text.is_empty():
		return "Piercing Arrow"
	if text.is_empty():
		return fallback
	var labels := {
		"piercing_arrow": "Piercing Arrow", "spawning_split": "Breeding Split", "spawn_split": "Breeding Split",
		"pack_hunt_mark": "Pack Hunt Mark", "group_hunt_mark": "Pack Hunt Mark",
	}
	return String(labels.get(text.to_lower(), text))


## The stable id behind a legacy component field, when the snapshot carries one.
## A display-only object such as {"name": "Breeding Split"} has no id, so the lookup
## stays empty and the component keeps its text without borrowing other art.
func _component_id(build: Dictionary, key: String) -> String:
	var value: Variant = build.get("%s_id" % key, build.get(key, null))
	if value == null:
		value = _nested_value(build, ["components", key], null)
	if value == null and build.has("%ss" % key):
		var values := _as_array(build.get("%ss" % key, []))
		value = values[0] if not values.is_empty() else null
	if value is Dictionary:
		return String((value as Dictionary).get("id", ""))
	if value is String:
		return String(value)
	return ""


func _build_display_name(build: Dictionary, index: int, verified: bool) -> String:
	if verified:
		return String(build.get("verified_growth_name", build.get("growth_name", build.get("state", build.get("name", build.get("id", "Verified Preset"))))))
	var neutral_name := String(build.get("neutral_name", "")).strip_edges()
	if not neutral_name.is_empty():
		return neutral_name
	return "Preset %s" % String.chr(65 + clampi(index, 0, 25))


func _equipment_text(build: Dictionary) -> String:
	var value: Variant = build.get("equipment_summary", null)
	if value == null:
		var equipment := _as_dictionary(build.get("equipment", build.get("gear", {})))
		var details: Array[String] = []
		for key in ["name", "description", "summary", "affixes", "calibration"]:
			if equipment.has(key):
				var detail := _display_value(equipment.get(key))
				if not detail.is_empty() and detail not in details:
					details.append(detail)
		value = "; ".join(details) if not details.is_empty() else null
	if value == null:
		value = _nested_value(build, ["components", "equipment_summary"], null)
	var text := _display_value(value)
	return text if not text.is_empty() else "Unknown"


func _display_value(value: Variant) -> String:
	if value is Dictionary:
		var dictionary: Dictionary = value
		for key in ["name", "label", "summary", "id"]:
			if dictionary.has(key):
				return String(dictionary.get(key))
		var parts: Array[String] = []
		for key in dictionary:
			parts.append("%s=%s" % [String(key), _format_value(dictionary[key])])
		return ", ".join(parts)
	if value is Array:
		var parts: Array[String] = []
		for item in value:
			parts.append(_display_value(item))
		return ", ".join(parts)
	return "" if value == null else str(value)


func _format_value(value: Variant) -> String:
	if typeof(value) == TYPE_FLOAT:
		return ("%.4f" % float(value)).trim_suffix("0").trim_suffix("0").trim_suffix("0").trim_suffix(".")
	return _display_value(value)


func _core_canonical_name(value: Variant) -> String:
	var id := _display_value(value).strip_edges().to_lower()
	var aliases := {
		"nearest_enemy": "near_enemy_horizon",
		"perception": "near_enemy_horizon",
		"movement": "direct_gait",
		"action": "direct_gait",
		"execution": "single_key_execution",
		"memory": "short_trace_memory",
	}
	return String(aliases.get(id, id))


func _clear_children(parent: Node) -> void:
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()


func _as_dictionary(value: Variant) -> Dictionary:
	return value as Dictionary if value is Dictionary else {}


func _as_array(value: Variant) -> Array:
	return value as Array if value is Array else []


func _on_base_pressed() -> void:
	base_requested.emit()


func _on_action_pressed(action_id: String) -> void:
	action_requested.emit(_facility_id, action_id, {})


func _on_payload_action_pressed(action_id: String, payload: Dictionary) -> void:
	if _facility_id == "loadout" and action_id == "equip_item":
		_loadout_backpack_pinned_id = String(payload.instance_id)
	action_requested.emit(_facility_id, action_id, payload.duplicate(true))
