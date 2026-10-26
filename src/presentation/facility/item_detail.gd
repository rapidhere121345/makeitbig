class_name FacilityItemDetail
extends RefCounted

## Shared item-detail surface extracted from FacilityScreen. This collaborator
## owns the full-equipment-details dialog and its bounded layout, the complete
## raw item reference line, the folded raw-field disclosure blocks, and the
## salvage confirmation handlers, reading the dialog nodes and presentation
## state through the untyped owner reference.
const UiKit := preload("res://src/presentation/ui_kit.gd")
const FacilityItemText := preload("res://src/presentation/facility/item_text.gd")

var _screen


func _init(screen) -> void:
	_screen = screen


func _add_full_item_detail_button(parent: Container, item: Dictionary, title_text: String, detail_text: String) -> Button:
	var instance_id := String(item.get("instance_id", ""))
	var button := Button.new()
	button.name = "FullItemDetails_%s" % UiKit.stable_node_token(instance_id)
	button.text = "Full Equipment Details"
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.tooltip_text = "Open full item details; closing returns focus to this button"
	button.focus_mode = Control.FOCUS_ALL
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(_show_item_detail.bind(title_text, detail_text, button))
	parent.add_child(button)
	return button


func _show_item_detail(title_text: String, detail_text: String, source: Control) -> void:
	if _screen._item_detail_dialog == null or _screen._item_detail_dialog_text == null:
		return
	_screen._item_detail_return_focus = source
	_screen._item_detail_dialog.title = "Full Equipment Details · %s" % title_text
	_screen._item_detail_dialog.dialog_text = ""
	_screen._item_detail_dialog_text.text = detail_text
	_screen._item_detail_scroll.scroll_vertical = 0
	var target_size := _item_detail_target_size()
	_screen._item_detail_dialog.min_size = target_size
	_screen._item_detail_dialog.size = target_size
	_layout_item_detail_dialog()
	_screen._item_detail_dialog.popup_centered_clamped(target_size, 0.95)
	call_deferred("_layout_item_detail_dialog")


func _item_detail_target_size() -> Vector2i:
	var viewport_size: Vector2 = _screen.get_viewport_rect().size
	var bounded_width := minf(1040.0, maxf(760.0, viewport_size.x * 0.78))
	var bounded_height := minf(700.0, maxf(520.0, viewport_size.y * 0.82))
	return Vector2i(
		int(minf(bounded_width, maxf(320.0, viewport_size.x - 48.0))),
		int(minf(bounded_height, maxf(280.0, viewport_size.y - 32.0)))
	)


func _layout_item_detail_dialog() -> void:
	if _screen._item_detail_dialog == null or _screen._item_detail_scroll == null or _screen._item_detail_dialog_text == null:
		return
	var body_position := Vector2(20.0, 44.0)
	var body_size := Vector2(maxf(0.0, _screen._item_detail_dialog.size.x - 40.0), maxf(0.0, _screen._item_detail_dialog.size.y - 116.0))
	_screen._item_detail_scroll.position = body_position
	_screen._item_detail_scroll.size = body_size
	var content_width := maxf(0.0, body_size.x - 18.0)
	_screen._item_detail_dialog_text.custom_minimum_size = Vector2(content_width, 0.0)
	_screen._item_detail_dialog_text.size = Vector2(content_width, 0.0)
	call_deferred("_fit_item_detail_text")


func _fit_item_detail_text() -> void:
	if _screen._item_detail_scroll == null or _screen._item_detail_dialog_text == null:
		return
	var content_width: float = maxf(0.0, _screen._item_detail_scroll.size.x - 18.0)
	_screen._item_detail_dialog_text.custom_minimum_size = Vector2(content_width, 0.0)
	_screen._item_detail_dialog_text.size = Vector2(content_width, 0.0)
	var wrapped_height: float = _screen._item_detail_dialog_text.get_minimum_size().y
	_screen._item_detail_dialog_text.custom_minimum_size = Vector2(content_width, wrapped_height)
	_screen._item_detail_dialog_text.size = Vector2(content_width, wrapped_height)


func _on_item_detail_closed() -> void:
	var return_focus: Control = _screen._item_detail_return_focus
	_screen._item_detail_return_focus = null
	if return_focus != null and is_instance_valid(return_focus) and return_focus.is_visible_in_tree() \
		and (not return_focus is BaseButton or not (return_focus as BaseButton).disabled):
		return_focus.call_deferred("grab_focus")


## The snapshot's own base-item table entry for one owned item, or {} when the
## snapshot carries no entry: the page never invents a base it was not given.
func _base_item_data(item: Dictionary) -> Dictionary:
	return UiKit.as_dictionary(_screen._equipment_model.base_items.get(String(item.get("base_item_id", "")), {}))


## The player-facing name of one owned item, or its base id when the snapshot has
## no published name for it. Never a shortened or invented label.
func _item_display_name(item: Dictionary) -> String:
	return _screen._equipment_model.display_name(item)


## The complete raw reference line of one item: every field the snapshot holds,
## including the raw slot id, the whole instance id, the untranslated modifiers,
## each affix with its index and its family id, and the raw rune and law ids.
## This is the page's reference layer: the cards keep it folded by default behind
## their own stable toggle, and nothing here is dropped, renamed, or recomputed.
func _item_detail_text(item: Dictionary) -> String:
	var modifiers: Array[String] = []
	for raw_modifier in UiKit.as_array(_base_item_data(item).get("modifiers", [])):
		if raw_modifier is Dictionary:
			modifiers.append(FacilityItemText.modifier_text(raw_modifier))
	var affixes: Array[String] = []
	var families := UiKit.as_dictionary(_screen._facility_data.get("affix_families", {}))
	var affix_index := 1
	for raw_affix in UiKit.as_array(item.get("affixes", [])):
		if not raw_affix is Dictionary:
			continue
		var affix: Dictionary = raw_affix
		var family_id := String(affix.get("family_id", ""))
		var family := UiKit.as_dictionary(families.get(family_id, {}))
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
	if String(item.get("instance_id", "")).length() > _screen.INSTANCE_ID_DISPLAY_LIMIT:
		return true
	return _raw_entry_count(item) > _screen.RAW_FIELD_ENTRY_LIMIT


func _raw_entry_count(item: Dictionary) -> int:
	var base_id := String(item.get("base_item_id", ""))
	var base := UiKit.as_dictionary(UiKit.as_dictionary(_screen._facility_data.get("base_items", {})).get(base_id, {}))
	# Internal parameter entries only: the base's own modifiers plus the item's
	# affixes. The rune and the law are single short fields that stay readable, so
	# they never push a block over the budget on their own.
	return UiKit.as_array(base.get("modifiers", [])).size() + UiKit.as_array(item.get("affixes", [])).size()


## Why this block folds, in one line: the exact raw length or entry count, never a
## vague "too long". The toggle right below it names what is behind it.
func _raw_field_reason(item: Dictionary) -> String:
	var instance_id := String(item.get("instance_id", ""))
	if instance_id.length() > _screen.INSTANCE_ID_DISPLAY_LIMIT:
		return "instance_id: %d characters" % instance_id.length()
	return "%d internal entries" % _raw_entry_count(item)


func _field_block_key(kind: String, owner_id: String) -> String:
	return "%s:%s" % [kind, owner_id]


func _field_block_open(kind: String, owner_id: String) -> bool:
	return bool(_screen._open_field_blocks.get(_field_block_key(kind, owner_id), false))


func _field_block_toggle(kind: String, owner_id: String) -> Button:
	var open := _field_block_open(kind, owner_id)
	var toggle := Button.new()
	toggle.name = "%s_%s" % [
		String(_screen.FIELD_BLOCK_TOGGLE_PREFIXES.get(kind, "FieldBlockToggle")),
		UiKit.stable_node_token(owner_id),
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
	_screen._open_field_blocks[key] = not bool(_screen._open_field_blocks.get(key, false))
	if _screen._built:
		_screen._apply_presentation()


func _affix_effect_text(family: Dictionary, tier: int) -> String:
	return _screen._readable_build.format_affix({"family_id": String(family.get("id", "")), "tier": tier})


func _inventory_item_by_id(inventory: Array, instance_id: String) -> Dictionary:
	if instance_id.is_empty():
		return {}
	for raw_item in inventory:
		if raw_item is Dictionary and String((raw_item as Dictionary).get("instance_id", "")) == instance_id:
			return raw_item
	return {}


func _on_salvage_confirmed() -> void:
	if _screen._pending_salvage.is_empty():
		return
	var instance_id := String(_screen._pending_salvage.get("instance_id", ""))
	_screen._pending_salvage = {}
	_screen.action_requested.emit("loadout", "salvage_item", {"instance_id": instance_id})


func _on_salvage_canceled() -> void:
	_screen._pending_salvage = {}


## Difference summary for one forge inventory item, rendered as the button's second
## line so same-base Items with different affixes stay distinguishable at a glance.
## Every value is read directly from the passed forge snapshot; this never
## re-evaluates the build and never shows a formula, TTK, power rating, or
## instance_id. Up to two affixes as family_name + Chinese tier, then a "+N" overflow; with
## no affixes it falls back to rune/law; with neither it says "No Affixes".
func _item_difference_summary_text(item: Dictionary) -> String:
	return _screen._equipment_model.compact_difference(item)
