class_name ResultLootPanel
extends RefCounted
## The left-hand loot lane of the ResultScreen, extracted from it. This
## collaborator owns the reward summary, the paginated equipment cards, the
## proxy-component cards, the first-clear core rewards and the equipment
## detail overlay, reaching the settlement, the live profile, the icon batch
## and the equipment model through the untyped screen reference.

const ShellThemeScript = preload("res://src/presentation/shell_theme.gd")
const UiKit := preload("res://src/presentation/ui_kit.gd")
const ResultTextScript = preload("res://src/presentation/result/result_text.gd")
const ResultWidgetsScript = preload("res://src/presentation/result/result_widgets.gd")

const DROP_HEADING := "New Items and Rewards"
const REVIEW_DROP_TEXT := "Comparison (Not Equipped)"
const EQUIPMENT_DETAIL_TEXT := "Details"
const EQUIPMENT_DETAIL_CLOSE_TEXT := "Close Details"
const PREVIOUS_PAGE_TEXT := "Previous Page"
const NEXT_PAGE_TEXT := "Next Page"
const REWARD_DETAIL_SHOW_TEXT := "Reward Details"
const REWARD_DETAIL_HIDE_TEXT := "Hide Details"
const PROXY_DETAIL_SHOW_TEXT := "Protocol Details"
const PROXY_DETAIL_HIDE_TEXT := "Hide Protocol"

const CARD_NODE_NAME := "EquipmentCard"
const CARD_TEXT_NODE_NAME := "EquipmentCardText"
const CARD_NAME_NODE_NAME := "EquipmentCardName"
const BASE_ICON_NODE_NAME := "EquipmentBaseIcon"
const SLOT_BADGE_NODE_NAME := "EquipmentSlotBadge"
## The complete field line of one drop, kept on its card so
## get_equipment_card_texts can read it back whatever the card face shows.
const CARD_AUDIT_META := "audit_text"

## Read by the screen after apply(): the drops and proxy components this
## settlement produced, which also feed the header copy.
var equipment_drop_entries: Array = []
var proxy_component_count := 0
var reward_label: Label

var _screen
var _equipment_page := 0
var _equipment_page_size := 2
var _loot_scroll: ScrollContainer
var _reward_detail_button: Button
var _reward_detail_label: Label
var _skill_cue_label: Label
var _proxy_component_box: VBoxContainer
var _proxy_detail_button: Button
var _equipment_box: VBoxContainer
var _equipment_pagination: HBoxContainer
var _previous_page_button: Button
var _next_page_button: Button
var _page_label: Label
var _equipment_detail_overlay: Control
var _equipment_detail_title: Label
var _equipment_detail_body: Label
var _equipment_detail_return_focus: Control = null
var _core_rewards: GridContainer


func _init(screen) -> void:
	_screen = screen


func build_detail_overlay() -> void:
	_equipment_detail_overlay = Control.new()
	_equipment_detail_overlay.name = "EquipmentDetailOverlay"
	_equipment_detail_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_equipment_detail_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_equipment_detail_overlay.visible = false
	_screen.add_child(_equipment_detail_overlay)
	var detail_dim := ColorRect.new()
	detail_dim.color = Color(ShellThemeScript.INK, 0.86)
	detail_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	detail_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_equipment_detail_overlay.add_child(detail_dim)
	var detail_panel := PanelContainer.new()
	detail_panel.name = "EquipmentDetailPanel"
	detail_panel.set_anchors_preset(Control.PRESET_CENTER)
	detail_panel.set_offsets_preset(Control.PRESET_CENTER)
	detail_panel.size = Vector2.ZERO
	detail_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	detail_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	detail_panel.offset_left = -450.0
	detail_panel.offset_right = 450.0
	detail_panel.offset_top = -300.0
	detail_panel.offset_bottom = 300.0
	detail_panel.add_theme_stylebox_override("panel", ResultWidgetsScript.frame(ShellThemeScript.INK, ShellThemeScript.AMBER, 2))
	_equipment_detail_overlay.add_child(detail_panel)
	var detail_column := VBoxContainer.new()
	detail_column.add_theme_constant_override("separation", 10)
	detail_panel.add_child(detail_column)
	var detail_header := HBoxContainer.new()
	detail_header.add_theme_constant_override("separation", 12)
	detail_column.add_child(detail_header)
	_equipment_detail_title = Label.new()
	_equipment_detail_title.name = "EquipmentDetailTitle"
	_equipment_detail_title.text = EQUIPMENT_DETAIL_TEXT
	_equipment_detail_title.add_theme_font_size_override("font_size", ResultWidgetsScript.METRIC_VALUE_FONT_SIZE)
	_equipment_detail_title.add_theme_color_override("font_color", ShellThemeScript.BONE)
	_equipment_detail_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_equipment_detail_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_header.add_child(_equipment_detail_title)
	var close_button := Button.new()
	close_button.name = "EquipmentDetailClose"
	close_button.text = EQUIPMENT_DETAIL_CLOSE_TEXT
	close_button.pressed.connect(_on_equipment_detail_closed)
	detail_header.add_child(close_button)
	_equipment_detail_body = Label.new()
	_equipment_detail_body.name = "EquipmentDetailBody"
	_equipment_detail_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_equipment_detail_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_equipment_detail_body.add_theme_font_size_override("font_size", ShellThemeScript.BODY_FONT_SIZE)
	_equipment_detail_body.add_theme_color_override("font_color", ShellThemeScript.BONE)
	var detail_scroll := ScrollContainer.new()
	detail_scroll.name = "EquipmentDetailScroll"
	detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail_column.add_child(detail_scroll)
	_equipment_detail_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.add_child(_equipment_detail_body)


func build(parent: Control) -> void:
	var panel := PanelContainer.new()
	panel.name = "DropPanel"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 4)
	panel.add_child(column)
	column.add_child(ResultWidgetsScript.heading(DROP_HEADING))
	_loot_scroll = ScrollContainer.new()
	_loot_scroll.name = "ResultLootScroll"
	_loot_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_loot_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_loot_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_loot_scroll.follow_focus = true
	column.add_child(_loot_scroll)
	var loot := VBoxContainer.new()
	loot.name = "LootContent"
	loot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	loot.add_theme_constant_override("separation", 10)
	_loot_scroll.add_child(loot)
	var summary_row := HBoxContainer.new()
	summary_row.name = "RewardSummaryRow"
	summary_row.add_theme_constant_override("separation", 8)
	loot.add_child(summary_row)
	reward_label = Label.new()
	reward_label.name = "RewardSummary"
	reward_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	reward_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reward_label.add_theme_color_override("font_color", ShellThemeScript.BONE)
	summary_row.add_child(reward_label)
	_reward_detail_button = Button.new()
	_reward_detail_button.name = "RewardDetailButton"
	_reward_detail_button.text = REWARD_DETAIL_SHOW_TEXT
	_reward_detail_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_reward_detail_button.pressed.connect(_on_reward_detail_pressed)
	summary_row.add_child(_reward_detail_button)
	_skill_cue_label = Label.new()
	_skill_cue_label.name = "FirstSkillCue"
	_skill_cue_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_skill_cue_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_skill_cue_label.add_theme_font_size_override("font_size", ResultWidgetsScript.SECONDARY_FONT_SIZE)
	_skill_cue_label.add_theme_color_override("font_color", ShellThemeScript.AMBER)
	_skill_cue_label.visible = false
	loot.add_child(_skill_cue_label)
	_equipment_box = VBoxContainer.new()
	_equipment_box.name = "EquipmentCards"
	_equipment_box.add_theme_constant_override("separation", 8)
	_equipment_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	loot.add_child(_equipment_box)
	_core_rewards = GridContainer.new()
	_core_rewards.name = "FirstKillCoreRewards"
	_core_rewards.columns = 2
	_core_rewards.add_theme_constant_override("h_separation", 14)
	_core_rewards.add_theme_constant_override("v_separation", 4)
	loot.add_child(_core_rewards)
	_proxy_component_box = VBoxContainer.new()
	_proxy_component_box.name = "ProxyComponentDrops"
	_proxy_component_box.add_theme_constant_override("separation", 8)
	loot.add_child(_proxy_component_box)
	_reward_detail_label = Label.new()
	_reward_detail_label.name = "RewardDetailText"
	_reward_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_reward_detail_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_reward_detail_label.add_theme_font_size_override("font_size", ResultWidgetsScript.SUBTITLE_FONT_SIZE)
	_reward_detail_label.add_theme_color_override("font_color", ShellThemeScript.NEUTRAL)
	_reward_detail_label.visible = false
	loot.add_child(_reward_detail_label)
	_equipment_pagination = HBoxContainer.new()
	_equipment_pagination.name = "EquipmentPagination"
	_equipment_pagination.add_theme_constant_override("separation", 8)
	_equipment_pagination.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(_equipment_pagination)
	_previous_page_button = Button.new()
	_previous_page_button.name = "EquipmentPreviousPage"
	_previous_page_button.text = PREVIOUS_PAGE_TEXT
	_previous_page_button.pressed.connect(_on_previous_equipment_page)
	_equipment_pagination.add_child(_previous_page_button)
	_page_label = Label.new()
	_page_label.name = "EquipmentPageLabel"
	_page_label.add_theme_font_size_override("font_size", ResultWidgetsScript.SECONDARY_FONT_SIZE)
	_page_label.add_theme_color_override("font_color", ShellThemeScript.NEUTRAL)
	_page_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_page_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_equipment_pagination.add_child(_page_label)
	_next_page_button = Button.new()
	_next_page_button.name = "EquipmentNextPage"
	_next_page_button.text = NEXT_PAGE_TEXT
	_previous_page_button.text = PREVIOUS_PAGE_TEXT
	_next_page_button.pressed.connect(_on_next_equipment_page)
	_equipment_pagination.add_child(_next_page_button)


func _on_reward_detail_pressed() -> void:
	if _reward_detail_label == null or _reward_detail_button == null:
		return
	_reward_detail_label.visible = not _reward_detail_label.visible
	_reward_detail_button.text = REWARD_DETAIL_HIDE_TEXT if _reward_detail_label.visible else REWARD_DETAIL_SHOW_TEXT
	if _loot_scroll != null:
		# The disclosure button keeps focus after activation. ScrollContainer's
		# follow_focus would otherwise pull the viewport back to that button on the
		# next layout frame, undoing the reveal below.
		_loot_scroll.follow_focus = not _reward_detail_label.visible
	if _reward_detail_label.visible and _loot_scroll != null:
		# The disclosure button sits above the loot cards. On a compact result page
		# the newly revealed copy can therefore begin below the current viewport;
		# reveal it as part of the same action so the click has an immediate, visible
		# result and keyboard users do not have to guess where the text went.
		call_deferred("_ensure_reward_detail_visible")


func _ensure_reward_detail_visible() -> void:
	if _loot_scroll == null or _reward_detail_label == null or not _reward_detail_label.visible:
		return
	# The VBox must receive the visibility change before ScrollContainer can measure
	# the new child height. Two layout frames cover both the child minimum-size
	# notification and the outer result layout without polling in _process().
	await _screen.get_tree().process_frame
	await _screen.get_tree().process_frame
	if is_instance_valid(_loot_scroll) and is_instance_valid(_reward_detail_label) and _reward_detail_label.visible:
		_loot_scroll.ensure_control_visible(_reward_detail_label)
		await _screen.get_tree().process_frame
		var viewport_rect := _loot_scroll.get_global_rect()
		var detail_rect := _reward_detail_label.get_global_rect()
		const REVEAL_MARGIN := 8.0
		if detail_rect.position.y < viewport_rect.position.y + REVEAL_MARGIN:
			_loot_scroll.scroll_vertical = maxi(0, _loot_scroll.scroll_vertical - ceili(viewport_rect.position.y + REVEAL_MARGIN - detail_rect.position.y))
		elif detail_rect.end.y > viewport_rect.end.y - REVEAL_MARGIN:
			_loot_scroll.scroll_vertical += ceili(detail_rect.end.y - (viewport_rect.end.y - REVEAL_MARGIN))


func sync_page_size() -> void:
	var page_size := 1
	if page_size == _equipment_page_size:
		return
	_equipment_page_size = page_size
	_equipment_page = 0
	if _screen._built:
		_render_equipment_cards()


func _apply_first_skill_cue() -> void:
	if _skill_cue_label == null:
		return
	var lines: Array[String] = []
	for cue in ResultTextScript.first_skill_cues(_screen._result):
		if _skill_ready_in_build(String(cue.skill_id), int(cue.slot_index)):
			lines.append("First-clear skill unlock: %s (%s · %s) · %s" % [cue.name, cue.key, cue.slot, cue.hint])
		else:
			## The tag alone is not equip state: if the granted slot is occupied
			## or absent in the resolved build, promise only the unlock.
			lines.append("First-clear skill unlock: %s · Unlocked; equip at Loadout %s" % [cue.name, cue.slot])
	_skill_cue_label.text = "\n".join(lines)
	_skill_cue_label.tooltip_text = _skill_cue_label.text
	_skill_cue_label.visible = not lines.is_empty()


func _skill_ready_in_build(skill_id: String, slot_index: int) -> bool:
	## Readiness comes from the resolved loadout, not the reward tag: the skill
	## must sit in its own hotkey slot (the grant can no-op when that slot is
	## occupied), mirroring main.gd's _is_skill_equipped(slot_index, skill_id).
	var active := UiKit.as_dictionary(_screen._current_profile.get("active_build", {}))
	var skills: Variant = active.get("skills", [])
	if not (skills is Array):
		return false
	var slots := skills as Array
	return slot_index >= 0 and slot_index < slots.size() and String(slots[slot_index]) == skill_id


func _render_core_rewards(rewards: Dictionary) -> void:
	UiKit.clear_children_immediate(_core_rewards)
	_core_rewards.visible = ResultTextScript.is_first_proxy_unlock(_screen._result, rewards)
	if not _core_rewards.visible:
		return
	# Only the actual first-unlock record may display the fixed reward set.
	# Explicit future/partial payloads are not padded to four granted objects.
	var granted_names := ResultTextScript.proxy_core_names(_screen._result, rewards)
	var featured := equipment_drop_entries.is_empty() and ResultTextScript.proxy_component_entries(_screen._result).is_empty()
	_core_rewards.add_theme_constant_override("v_separation", 12 if featured else 4)
	for core_id in ResultTextScript.FIXED_CORE_IDS:
		var core_name := String(ResultTextScript.PROXY_CORE_LABELS[core_id])
		if not core_name in granted_names:
			continue
		var texture: Texture2D = _screen._art.icon("core." + core_id)
		if texture == null:
			continue
		var reward := PanelContainer.new()
		reward.name = "CoreReward_" + core_id
		reward.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		reward.add_theme_stylebox_override("panel", ShellThemeScript.panel_style("well") if featured else StyleBoxEmpty.new())
		_core_rewards.add_child(reward)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12 if featured else 6)
		reward.add_child(row)
		var icon := ResultWidgetsScript.icon_node(texture, featured)
		if featured:
			icon.custom_minimum_size = Vector2(96, 96)
		icon.set_meta("canonical_id", "core." + core_id)
		row.add_child(icon)
		var label := Label.new()
		label.text = core_name
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", ShellThemeScript.BODY_FONT_SIZE if featured else ResultWidgetsScript.SUBTITLE_FONT_SIZE)
		row.add_child(label)


## The current fixed page. Every entry remains reachable through pagination and
## every evidence accessor still reports payload order.
func _render_equipment_cards() -> void:
	_clear_equipment_cards()
	var first := _equipment_page * _equipment_page_size
	var last := mini(first + _equipment_page_size, equipment_drop_entries.size())
	for index in range(first, last):
		_equipment_box.add_child(_equipment_card(equipment_drop_entries[index], index))
	_sync_equipment_pagination()


func _equipment_page_count() -> int:
	return maxi(1, ceili(float(equipment_drop_entries.size()) / float(_equipment_page_size)))


func _sync_equipment_pagination() -> void:
	if _equipment_pagination == null:
		return
	var page_count := _equipment_page_count()
	_equipment_page = clampi(_equipment_page, 0, page_count - 1)
	_equipment_pagination.visible = page_count > 1
	_page_label.text = "%d / %d" % [_equipment_page + 1, page_count]
	_previous_page_button.disabled = _equipment_page == 0
	_next_page_button.disabled = _equipment_page >= page_count - 1


## Proxy components are settlement inventory records, not equipment. Their own
## section has no loadout-comparison action and states that the frozen build did
## not change when the drop entered inventory.
func _render_proxy_component_cards(entries: Array) -> void:
	UiKit.clear_children_immediate(_proxy_component_box)
	_proxy_component_box.visible = not entries.is_empty()
	if entries.is_empty():
		_proxy_detail_button = null
		return
	var heading_row := HBoxContainer.new()
	heading_row.name = "ProxyComponentHeadingRow"
	heading_row.add_theme_constant_override("separation", 8)
	_proxy_component_box.add_child(heading_row)
	var heading := Label.new()
	heading.name = "ProxyComponentDropHeading"
	heading.text = "Proxy Components x%d · Stored, Not Installed" % entries.size()
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	heading.add_theme_font_size_override("font_size", ShellThemeScript.BODY_FONT_SIZE)
	heading.add_theme_color_override("font_color", ShellThemeScript.PROXY)
	heading_row.add_child(heading)
	_proxy_detail_button = Button.new()
	_proxy_detail_button.name = "ProxyComponentDetailButton"
	_proxy_detail_button.text = PROXY_DETAIL_SHOW_TEXT
	_proxy_detail_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_proxy_detail_button.pressed.connect(_on_proxy_detail_pressed)
	heading_row.add_child(_proxy_detail_button)
	for entry_value in entries:
		var entry := entry_value as Dictionary
		var card := PanelContainer.new()
		card.name = "ProxyComponentDrop_%s" % UiKit.stable_node_token(String(entry.get("id", "")))
		card.add_theme_stylebox_override("panel", ResultWidgetsScript.frame(ShellThemeScript.INK, ShellThemeScript.COPPER_DULL, 1))
		_proxy_component_box.add_child(card)
		var body := VBoxContainer.new()
		body.add_theme_constant_override("separation", 4)
		card.add_child(body)
		var title := Label.new()
		title.name = "ProxyComponentName"
		title.text = "%s · %s" % [String(entry.get("name", entry.get("id", "Unknown Core"))), ResultTextScript.proxy_slot_label(String(entry.get("slot", "")))]
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		title.add_theme_font_size_override("font_size", ShellThemeScript.BODY_FONT_SIZE)
		body.add_child(title)
		var protocol := Label.new()
		protocol.name = "ProxyComponentProtocol"
		protocol.text = "Protocol: %s\nNot installed; current proxy build unchanged" % String(entry.get("protocol", "Not Recorded"))
		protocol.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		protocol.add_theme_font_size_override("font_size", ResultWidgetsScript.SUBTITLE_FONT_SIZE)
		protocol.add_theme_color_override("font_color", ShellThemeScript.NEUTRAL)
		body.add_child(protocol)
		protocol.visible = false
		card.tooltip_text = protocol.text
		title.tooltip_text = protocol.text
		card.mouse_filter = Control.MOUSE_FILTER_STOP


func _on_proxy_detail_pressed() -> void:
	if _proxy_detail_button == null:
		return
	var expanded := _proxy_detail_button.text == PROXY_DETAIL_HIDE_TEXT
	for card in _proxy_component_box.get_children():
		var protocol := card.find_child("ProxyComponentProtocol", true, false) as Label
		if protocol != null:
			protocol.visible = not expanded
	_proxy_detail_button.text = PROXY_DETAIL_SHOW_TEXT if expanded else PROXY_DETAIL_HIDE_TEXT


## One drop: the published subject icon, the Chinese name of the base item, its
## slot badge and the named affixes on the card face, with the complete field line
## kept on the card for get_equipment_card_texts. The face carries no instance id.
func _equipment_card(entry: Dictionary, entry_index: int = 0) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = CARD_NODE_NAME
	card.add_theme_stylebox_override("panel", ResultWidgetsScript.frame(ShellThemeScript.INK, ShellThemeScript.COPPER_DULL, 1))
	card.set_meta(CARD_AUDIT_META, equipment_field_text(entry))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	card.add_child(row)
	## The card has one subject: the item the run actually produced, at the batch's
	## single allowed display step. A drop the batch does not publish keeps its text
	## alone -- no stand-in image is drawn in its place.
	var base_item_id := String(entry.get("base_item_id", "")).strip_edges()
	var subject_texture: Texture2D = null
	if not base_item_id.is_empty():
		subject_texture = _screen._art.icon("equipment.%s" % base_item_id)
	if subject_texture != null:
		var subject := ResultWidgetsScript.icon_node(subject_texture)
		subject.name = BASE_ICON_NODE_NAME
		subject.set_meta("canonical_id", "equipment.%s" % base_item_id)
		row.add_child(subject)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 4)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(body)
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 8)
	body.add_child(title_row)
	var slot := String(entry.get("slot", "")).strip_edges()
	var slot_texture: Texture2D = null
	if not slot.is_empty():
		slot_texture = _screen._art.icon("equipment_slot.%s" % slot)
	if slot_texture != null:
		## The slot is an identity badge at its native 32px cell, so it never reads
		## as a second image of the same size competing with the dropped item.
		var badge := ResultWidgetsScript.icon_node(slot_texture, false)
		badge.name = SLOT_BADGE_NODE_NAME
		badge.set_meta("canonical_id", "equipment_slot.%s" % slot)
		title_row.add_child(badge)
	var name_label := Label.new()
	name_label.name = CARD_NAME_NODE_NAME
	name_label.text = _item_display_name(entry)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", ShellThemeScript.BODY_FONT_SIZE)
	name_label.add_theme_color_override("font_color", ShellThemeScript.BONE)
	title_row.add_child(name_label)
	var detail_button := Button.new()
	detail_button.name = "EquipmentDetailButton"
	detail_button.text = EQUIPMENT_DETAIL_TEXT
	detail_button.tooltip_text = "Show this item's full stats"
	detail_button.pressed.connect(_on_equipment_detail_pressed.bind(entry_index))
	title_row.add_child(detail_button)
	var instance_id := String(entry.get("instance_id", "")).strip_edges()
	if not instance_id.is_empty() and not slot.is_empty():
		# Keep the decision in the card's first screen. Equipment descriptions can be
		# long and scroll independently; hiding the only comparison entry below them
		# would make the settlement look informational rather than actionable.
		var review_button := Button.new()
		review_button.name = "ReviewDrop_%s" % UiKit.stable_node_token(instance_id)
		var equipment_state := _equipment_state(entry)
		review_button.text = String({
			"equipped": "Inspect (Equipped)", "owned": REVIEW_DROP_TEXT,
			"missing": "No Longer in Backpack", "unknown": "Compare at Loadout",
		}.get(equipment_state, "Compare at Loadout"))
		review_button.disabled = equipment_state == "missing"
		review_button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		review_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		review_button.custom_minimum_size = Vector2(188.0, 0.0)
		ResultWidgetsScript.set_button_primary(review_button, true)
		review_button.tooltip_text = "%s; open Loadout to inspect this %s item" % [_equipment_status_text(entry), _screen._player_readable.slot_label(slot)]
		review_button.pressed.connect(_screen._on_review_drop_pressed.bind(instance_id, slot))
		body.add_child(review_button)
	var summary := Label.new()
	summary.name = CARD_TEXT_NODE_NAME
	summary.text = _equipment_summary_text(entry)
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary.add_theme_font_size_override("font_size", ResultWidgetsScript.SUBTITLE_FONT_SIZE)
	summary.add_theme_color_override("font_color", ShellThemeScript.NEUTRAL)
	body.add_child(summary)
	return card


## Ownership and equipment come from the current profile, independently of the
## immutable item record in the settlement receipt.
func _equipment_state(entry: Dictionary) -> String:
	if _screen._current_profile.is_empty():
		return "unknown"
	var instance_id := String(entry.get("instance_id", ""))
	var active := UiKit.as_dictionary(_screen._current_profile.get("active_build", {}))
	var equipped := UiKit.as_dictionary(active.get("equipped_item_ids", {}))
	if not instance_id.is_empty() and String(equipped.get(String(entry.get("slot", "")), "")) == instance_id:
		return "equipped"
	var inventory := UiKit.as_dictionary(_screen._current_profile.get("inventory", {}))
	var items: Variant = inventory.get("equipment", [])
	if items is Array:
		for item: Variant in items:
			if item is Dictionary and String(item.get("instance_id", "")) == instance_id:
				return "owned"
	return "missing"


func _equipment_status_text(entry: Dictionary) -> String:
	match _equipment_state(entry):
		"equipped": return "Currently equipped and in use"
		"owned": return "In backpack, not equipped"
		"missing": return "No longer in backpack; acquisition record retained"
	return "Equipment state not read; inspect it at the Loadout"


func _equipment_summary_text(entry: Dictionary) -> String:
	var affixes: Array[String] = _screen._equipment_model.affix_labels(entry.get("affixes", []), true)
	return "%s\nAffixes: %s" % [
		_equipment_status_summary(entry),
		", ".join(affixes) if not affixes.is_empty() else "No Record",
	]


func _equipment_status_summary(entry: Dictionary) -> String:
	match _equipment_state(entry):
		"equipped": return "%s · Equipped" % _screen._player_readable.slot_label(String(entry.get("slot", "")))
		"owned": return "%s · Stored, Not Equipped" % _screen._player_readable.slot_label(String(entry.get("slot", "")))
		"missing": return "%s · No longer in backpack; acquisition record retained" % _screen._player_readable.slot_label(String(entry.get("slot", "")))
	return "%s · Inventory state not read" % _screen._player_readable.slot_label(String(entry.get("slot", "")))


func _equipment_full_text(entry: Dictionary) -> String:
	var current := UiKit.as_dictionary(entry.get("current_parameters", {}))
	var replacement := UiKit.as_dictionary(entry.get("equipped_parameters", {}))
	var historical_preview := "\nEquipment preview at acquisition:" if not current.is_empty() or not replacement.is_empty() else ""
	return "At acquisition: added to equipment storage\n%s%s\n%s" % [
		_equipment_status_text(entry), historical_preview, _screen._player_readable.format_item(entry, current, replacement),
	]


## The complete field line of one drop, printed as it stands: slot, published name,
## base id, affixes by their raw family ids, the untruncated instance id and the
## rest of the item record. This is what get_equipment_card_texts reads back.
func equipment_field_text(entry: Dictionary) -> String:
	return _screen._equipment_model.result_audit(entry)


func _clear_equipment_cards() -> void:
	UiKit.clear_children_immediate(_equipment_box)


func _open_equipment_detail(entry_index: int) -> void:
	var bounded := clampi(entry_index, 0, maxi(equipment_drop_entries.size() - 1, 0))
	if equipment_drop_entries.is_empty():
		return
	if not _equipment_detail_overlay.visible:
		var focus_owner: Control = _screen.get_viewport().gui_get_focus_owner() if _screen.is_inside_tree() else null
		_equipment_detail_return_focus = focus_owner if focus_owner is Control and _screen.is_ancestor_of(focus_owner) else null
	var entry := equipment_drop_entries[bounded] as Dictionary
	_equipment_detail_title.text = _item_display_name(entry)
	_equipment_detail_body.text = _equipment_full_text(entry)
	var panel := _equipment_detail_overlay.get_node("EquipmentDetailPanel") as Control
	var extent := Vector2(minf(900.0, _screen.size.x - 64.0), minf(600.0, _screen.size.y - 64.0))
	panel.offset_left = -extent.x / 2.0
	panel.offset_right = extent.x / 2.0
	panel.offset_top = -extent.y / 2.0
	panel.offset_bottom = extent.y / 2.0
	(_equipment_detail_overlay.find_child("EquipmentDetailScroll", true, false) as ScrollContainer).scroll_vertical = 0
	_equipment_detail_overlay.visible = true
	var close_button := _equipment_detail_overlay.find_child("EquipmentDetailClose", true, false) as Button
	# The detail sheet has one action. Keep Tab inside it until it is dismissed.
	close_button.focus_next = close_button.get_path_to(close_button)
	close_button.focus_previous = close_button.get_path_to(close_button)
	close_button.grab_focus()


func close_equipment_detail() -> void:
	if _equipment_detail_overlay != null:
		var current_focus: Control = _screen.get_viewport().gui_get_focus_owner() if _screen.is_inside_tree() else null
		if current_focus != null and _screen.is_ancestor_of(current_focus) \
				and not _equipment_detail_overlay.is_ancestor_of(current_focus):
			_equipment_detail_return_focus = current_focus
		_equipment_detail_overlay.visible = false
	var restored_focus := _equipment_detail_return_focus
	_equipment_detail_return_focus = null
	if restored_focus != null and is_instance_valid(restored_focus) and _screen.is_ancestor_of(restored_focus):
		restored_focus.grab_focus()
	else:
		_screen._focus_default_action()


func _on_equipment_detail_pressed(entry_index: int) -> void:
	_open_equipment_detail(entry_index)


func _on_equipment_detail_closed() -> void:
	close_equipment_detail()


func _on_previous_equipment_page() -> void:
	_set_equipment_page(_equipment_page - 1, _previous_page_button)


func focus_equipment(instance_id: String) -> void:
	for index in equipment_drop_entries.size():
		if String(equipment_drop_entries[index].get("instance_id", "")) == instance_id:
			_set_equipment_page(index / _equipment_page_size)
			return


func _on_next_equipment_page() -> void:
	_set_equipment_page(_equipment_page + 1, _next_page_button)


func _set_equipment_page(page: int, focus_after_render: Control = null) -> void:
	_equipment_page = clampi(page, 0, _equipment_page_count() - 1)
	_equipment_detail_return_focus = focus_after_render
	close_equipment_detail()
	_loot_scroll.scroll_vertical = 0
	_render_equipment_cards()


## The player-facing name of one dropped item: an explicit name field on the drop
## first, then the published base item of the content table. Unknown raw ids stay
## in the folded diagnostic text instead of leaking onto the player-facing card.
func _item_display_name(entry: Dictionary) -> String:
	return _screen._equipment_model.display_name(entry)


func get_equipment_card_count() -> int:
	return _equipment_box.get_child_count() if _equipment_box != null else 0


func get_proxy_component_card_texts() -> Array[String]:
	var texts: Array[String] = []
	if _proxy_component_box == null:
		return texts
	for card in _proxy_component_box.get_children():
		var name_label := card.find_child("ProxyComponentName", true, false) as Label
		var protocol_label := card.find_child("ProxyComponentProtocol", true, false) as Label
		if name_label != null and protocol_label != null:
			texts.append("%s\n%s" % [name_label.text, protocol_label.text])
	return texts


## The complete field set of every card, in card order: slot, published name, base
## id, raw affix families, the untruncated instance id and the rest of the item
## record. The card face shows the name, the slot and the affixes; this accessor is
## what the evidence harness reads back, so a shortened id cannot pass unnoticed.
func get_equipment_card_texts() -> Array[String]:
	var texts: Array[String] = []
	if _equipment_box == null:
		return texts
	for child in _equipment_box.get_children():
		var text_value := _card_audit_text(child)
		if not text_value.is_empty():
			texts.append(text_value)
	return texts


## What each card really shows, read from its visible labels rather than from a
## cached string, so a drift between the card and this accessor cannot pass.
func get_equipment_card_summaries() -> Array[String]:
	var texts: Array[String] = []
	if _equipment_box == null:
		return texts
	for child in _equipment_box.get_children():
		var parts: Array[String] = []
		for node_name in [CARD_NAME_NODE_NAME, CARD_TEXT_NODE_NAME]:
			var label := child.find_child(node_name, true, false) as Label
			if label != null and not label.text.strip_edges().is_empty():
				parts.append(label.text)
		if not parts.is_empty():
			texts.append(" · ".join(parts))
	return texts


## A card's own complete field line, wherever the card structure puts it.
func _card_audit_text(card: Node) -> String:
	var stored := String(card.get_meta(CARD_AUDIT_META, ""))
	if not stored.is_empty():
		return stored
	if card is Label:
		return (card as Label).text
	var label := card.find_child(CARD_TEXT_NODE_NAME, true, false) as Label
	return label.text if label != null else ""

## Rebuild the whole lane for a new settlement: the equipment page resets, the
## detail overlay closes, and the reward summary is recomputed from `rewards`.
func apply(result: Dictionary, rewards: Dictionary) -> void:
	equipment_drop_entries = ResultTextScript.equipment_entries(result, rewards)
	_equipment_page = 0
	_loot_scroll.scroll_vertical = 0
	close_equipment_detail()
	var proxy_component_entries := ResultTextScript.proxy_component_entries(result)
	proxy_component_count = proxy_component_entries.size()
	_render_proxy_component_cards(proxy_component_entries)
	_render_equipment_cards()
	var full_reward_text := "\n".join(ResultTextScript.reward_lines(result, rewards, equipment_drop_entries, proxy_component_entries))
	reward_label.tooltip_text = full_reward_text
	_reward_detail_label.text = full_reward_text
	_reward_detail_label.visible = false
	_reward_detail_button.text = REWARD_DETAIL_SHOW_TEXT
	_apply_first_skill_cue()
	reward_label.text = ResultTextScript.compact_reward_text(result, rewards, equipment_drop_entries, proxy_component_entries)
	_reward_detail_button.visible = reward_label.text != full_reward_text
	_render_core_rewards(rewards)


func is_detail_open() -> bool:
	return _equipment_detail_overlay != null and _equipment_detail_overlay.visible
