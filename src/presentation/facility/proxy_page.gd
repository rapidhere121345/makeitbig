class_name FacilityProxyPage
extends RefCounted

## Proxy Bay page extracted from FacilityScreen. This collaborator owns the
## sealed and unlocked proxy builds, the fixed core strip, the core inventory
## and the distance-band settings, reaching owner state and presentation
## through the untyped owner reference.
const FacilityArtScript = preload("res://src/presentation/facility_art.gd")
const UiKit := preload("res://src/presentation/ui_kit.gd")
const FacilityItemText := preload("res://src/presentation/facility/item_text.gd")

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

var _screen


func _init(screen) -> void:
	_screen = screen


func _build_proxy() -> void:
	var proxy := UiKit.as_dictionary(_screen._facility_data.get("proxy", {}))
	var progression := UiKit.as_dictionary(_screen._facility_data.get("progression", {}))
	var unlocked := bool(proxy.get("unlocked", progression.get("proxy_unlocked", false)))
	if not unlocked:
		_build_proxy_core_strip(CORE_ORDER.duplicate(), false)
		var locked: VBoxContainer = _screen._section("Proxy Bay · Sealed", "ProxyLocked")
		locked.add_child(_screen._body_label("Unlock requirement: defeat the Threshold Colossus in Manual.\nAuto cannot be selected before the first kill."))
		locked.add_child(_screen._note_label("Actions and configuration are unavailable while sealed."))
		var capability: VBoxContainer = _screen._section("Abilities After Unlock", "ProxyUnlockPreview")
		capability.add_child(_screen._body_label("The first-kill reward previews four Common cores: find the nearest target -> maintain distance along the shortest viable path (retreat at close range) -> cast skill slot 1."))
		return
	var core_ids := _proxy_core_ids(proxy)
	_build_proxy_core_strip(core_ids, true)
	var status: VBoxContainer = _screen._section("Auto Available", "ProxyAuto")
	status.add_child(_screen._body_label("The Proxy Bay is unlocked for Auto contracts. Your four-slot build freezes at contract start; later changes do not affect an active contract."))
	status.add_child(_screen._note_label("Attachments Not Yet Available"))
	_build_proxy_inventory(proxy, core_ids)
	_build_proxy_distance_settings(proxy, core_ids)
	var progress: VBoxContainer = _screen._section("Early Progress", "ProxyProgress")
	_screen._fact_label(progress, "Auto Wins", str(int(progression.get("auto_contract_wins", 0))))
	_screen._fact_label(progress, "Early Chapter Complete", "Yes" if bool(progression.get("early_game_complete", false)) else "No")


## The four fixed cores of the first-kill reward, each in its own slot cell. The
## locked page previews them with the reward wording; the unlocked page states
## which ones are connected and keeps the same fixed order.
func _build_proxy_core_strip(core_ids: Array[String], unlocked: bool) -> void:
	var heading := "First-Kill Reward · Four Common Cores (Sealed Preview)"
	if unlocked:
		heading = "Current Assembly · Perception -> Action -> Execution -> Memory"
	var section: VBoxContainer = _screen._section_in(_screen._page_lead_row(), heading, "ProxyCoreStrip")
	var row: HBoxContainer = _screen._make_row("ProxyCoreRow")
	section.add_child(row)
	for core_id in core_ids:
		row.add_child(_proxy_core_cell(core_id, unlocked))


func _proxy_core_cell(core_id: String, unlocked: bool) -> PanelContainer:
	var cell := PanelContainer.new()
	cell.name = "ProxyCoreCell_%s" % UiKit.stable_node_token(core_id)
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.add_theme_stylebox_override("panel", _screen._slot_cell_box(unlocked, not unlocked))
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 6)
	cell.add_child(content)
	var canonical: String = _screen._art.canonical_id("proxy_core", core_id)
	var texture: Texture2D = _screen._body_icon_texture(canonical)
	if texture != null:
		var icon: TextureRect = _screen._icon_node(texture, FacilityArtScript.ICON_NATIVE_SIZE, true)
		icon.name = "%s_%s" % ["CoreIcon" if unlocked else "RewardCoreIcon", UiKit.stable_node_token(canonical)]
		icon.set_meta("canonical_id", canonical)
		content.add_child(icon)
	content.add_child(_screen._body_label("%s · %s" % [_proxy_core_display_name(core_id, {}), String(CORE_ROLES.get(core_id, "Core"))]))
	content.add_child(_screen._note_label("Connected" if unlocked else "Sealed"))
	return cell


## The profile's own core list, mapped onto the published fixed cores and kept in
## the order it was stored in. An empty or unknown list falls back to the four
## fixed cores; an unknown word maps to nothing and keeps its own text cell.
func _proxy_core_ids(proxy: Dictionary) -> Array[String]:
	var proxy_build := UiKit.as_dictionary(proxy.get("build", {}))
	var by_slot := {}
	var catalog := UiKit.as_dictionary(proxy.get("catalog", {}))
	for raw_core in UiKit.as_array(proxy_build.get("cores", proxy.get("cores", []))):
		var core_id := FacilityItemText.core_canonical_name(raw_core)
		if core_id.is_empty() or core_id not in IMPLEMENTED_CORE_IDS:
			continue
		var slot := String(UiKit.as_dictionary(catalog.get(core_id, {})).get("slot", _proxy_core_slot(core_id)))
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
	var section: VBoxContainer = _screen._section("Core Inventory and Protocols", "ProxyInventory")
	var catalog := UiKit.as_dictionary(proxy.get("catalog", {}))
	var owned := {}
	for value in UiKit.as_array(proxy.get("inventory", [])):
		if not value is Dictionary:
			continue
		var item := value as Dictionary
		var core_id := String(item.get("id", "")).strip_edges()
		if core_id in IMPLEMENTED_CORE_IDS:
			owned[core_id] = item
	for core_id in IMPLEMENTED_CORE_IDS:
		var definition := UiKit.as_dictionary(catalog.get(core_id, {}))
		if definition.is_empty():
			continue
		var row := VBoxContainer.new()
		row.name = "ProxyInventoryRow_%s" % UiKit.stable_node_token(core_id)
		row.add_theme_constant_override("separation", 4)
		section.add_child(row)
		var slot := String(definition.get("slot", _proxy_core_slot(core_id)))
		var state := "Not Owned"
		if core_id in installed_ids:
			state = "Installed"
		elif owned.has(core_id):
			state = "In Storage"
		row.add_child(_screen._body_label("%s · %s · %s" % [_proxy_core_display_name(core_id, definition), String(PROXY_SLOT_LABELS.get(slot, slot)), state]))
		row.add_child(_screen._note_label("Protocol: %s" % String(definition.get("protocol", UiKit.as_dictionary(owned.get(core_id, {})).get("protocol", "Not Recorded")))))
		if owned.has(core_id) and core_id not in installed_ids:
			var button := Button.new()
			button.name = "ProxyEquip_%s" % UiKit.stable_node_token(core_id)
			button.text = "Install in %s" % String(PROXY_SLOT_LABELS.get(slot, slot))
			button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			button.pressed.connect(_screen._on_payload_action_pressed.bind("equip_proxy_core", {"core_id": core_id}))
			row.add_child(button)


func _build_proxy_distance_settings(proxy: Dictionary, installed_ids: Array[String]) -> void:
	if "distance_keeping_gait" not in installed_ids:
		return
	var section: VBoxContainer = _screen._section("Distance Band", "ProxyDistanceBand")
	section.add_child(_screen._note_label("All distance bands scale with Piercing Arrow's actual range."))
	var settings := UiKit.as_dictionary(UiKit.as_dictionary(proxy.get("build", {})).get("settings", {}))
	var current := String(UiKit.as_dictionary(settings.get("distance_keeping_gait", {})).get("distance_band", "mid"))
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
			button.pressed.connect(_screen._on_payload_action_pressed.bind("configure_proxy_core", {"core_id": "distance_keeping_gait", "settings": {"distance_band": band}}))
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
