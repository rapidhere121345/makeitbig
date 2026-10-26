extends SceneTree
## Contract test for the facility art integration: every glyph on the equipment,
## rune, forge, training and proxy pages must be one real cell of a published
## production sheet, addressed by canonical id and drawn at an integer scale.
##
## It reads the published PNGs and the atlas tables only; it writes nothing, and
## it fails loudly when a glyph is missing instead of accepting a stand-in.
##
## The bounded overlay is checked the same way: the pin is restated here from the
## package contract instead of read from the module under test, the overrides
## sheet is read as real pixels, and every published id is compared against the
## sheet it has to be cut from - the six pinned ids against the overrides sheet,
## the rest against the base batch - so a layer that kept the superseded cell,
## moved a cell, leaked onto another id or silently fell back cannot pass.

const FacilityScreenScript = preload("res://src/presentation/facility_screen.gd")
const FacilityArtScript = preload("res://src/presentation/facility_art.gd")
const Assert := preload("res://tests/helpers/assert.gd")

const ICON_NATIVE_SIZE := Vector2i(32, 32)
const ICON_DISPLAY_SIZE := Vector2(64.0, 64.0)

## Canonical id per page element this integration owns.
const SLOT_IDS := {
	"main_hand": "equipment_slot.main_hand",
	"off_hand": "equipment_slot.off_hand",
	"gloves": "equipment_slot.gloves",
	"ring_1": "equipment_slot.ring_1",
}
const BASE_IDS := {
	"ashwood_longbow": "equipment.ashwood_longbow",
	"swift_recurve_bow": "equipment.swift_recurve_bow",
	"turnfeather_gloves": "equipment.turnfeather_gloves",
	"vitality_ring": "equipment.vitality_ring",
}
const RUNE_IDS := {
	"breeding_split": "rune.breeding_split",
	"branch_scale": "rune.branch_scale",
	"afterimage_extension": "rune.afterimage_extension",
}
const LAW_IDS := {"pack_hunt_mark": "law.pack_hunt_mark"}
const CORE_IDS := {
	"near_enemy_horizon": "core.near_enemy_horizon",
	"direct_gait": "core.direct_gait",
	"single_key_execution": "core.single_key_execution",
	"short_trace_memory": "core.short_trace_memory",
}
## Published cell size per facility page, straight from the hamlet atlas table.
const FACILITY_MARKS := {
	"contract": Vector2i(112, 112),
	"loadout": Vector2i(112, 112),
	"training": Vector2i(112, 112),
	"proxy": Vector2i(112, 112),
	"forge": Vector2i(160, 144),
}

## The published overlay package and the one order it may repaint, restated from
## the package contract rather than read from the module under test: a wrong pin
## there has to fail these assertions instead of agreeing with them.
const OVERRIDE_DIRECTORY := "res://art/production/p1/equipment_readability_v02"
const OVERRIDE_TEXTURE_FILE := "overrides.png"
const OVERRIDE_CANVAS := Vector2i(96, 64)
const OVERRIDE_IDS: Array[String] = [
	"equipment.lineage_quiver", "equipment.farwatch_quiver", "equipment.turnfeather_gloves",
	"equipment.piercer_gloves", "equipment_slot.off_hand", "equipment_slot.gloves",
]
const OVERRIDE_CANONICAL_IDS: Array[String] = [
	"lineage_quiver", "farwatch_quiver", "turnfeather_gloves", "piercer_gloves", "off_hand", "gloves",
]
const OVERRIDE_CELLS: Array[Vector2i] = [
	Vector2i(0, 0), Vector2i(32, 0), Vector2i(64, 0), Vector2i(0, 32), Vector2i(32, 32), Vector2i(64, 32),
]
const BASE_ATLAS_PATH := "res://art/production/p1/early_loop_v01/atlas.json"
const BASE_ATLAS_DIRECTORY := "res://art/production/p1/early_loop_v01"
## The contract icon table of the base batch: four slots, eight item bases, three
## runes, one law and four proxy cores. The overlay repaints six of them.
const CONTRACT_ICON_COUNT: int = 20


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	_test_loader_contract(failures)
	_test_mark_lookup(failures)
	_test_override_layer(failures)
	_test_screen_glyphs(failures)
	# FacilityScreen owns embedded dialogs; their native subwindow resources are
	# released on the following idle pass after the screen fixture is freed.
	for child in root.get_children():
		child.free()
	await process_frame
	await process_frame
	_finish(failures)


func _test_loader_contract(failures: Array[String]) -> void:
	var art = FacilityArtScript.new()
	_expect(art.load_art(), "facility art: both production packages must load: %s" % art.pending_reason, failures)
	if not art.is_ready():
		return
	_expect(art.ICON_NATIVE_SIZE == ICON_NATIVE_SIZE, "facility art: the icon cell contract is not 32x32", failures)
	_expect(art.ICON_DISPLAY_SCALE == 2 and Vector2(art.ICON_DISPLAY_SIZE) == ICON_DISPLAY_SIZE,
		"facility art: body icons must display at an integer 2x (64px), not at an arbitrary size", failures)
	var tables := {
		"equipment_slot": SLOT_IDS, "equipment_base": BASE_IDS, "rune": RUNE_IDS,
		"law": LAW_IDS, "proxy_core": CORE_IDS,
	}
	for kind in tables:
		var table: Dictionary = tables[kind]
		for local_id in table:
			var canonical_id := String(table[local_id])
			_expect(art.canonical_id(kind, local_id) == canonical_id,
				"facility art: %s/%s does not resolve its canonical id" % [kind, local_id], failures)
			var texture := art.icon(canonical_id)
			var expected_region := _expected_region(canonical_id)
			_expect(texture is AtlasTexture, "facility art: %s has no real atlas cell" % canonical_id, failures)
			if not texture is AtlasTexture:
				continue
			var atlas := texture as AtlasTexture
			var sheet_size := _published_sheet_size(canonical_id)
			_expect(atlas.region == expected_region, "facility art: %s uses region %s instead of its published cell" % [canonical_id, str(atlas.region)], failures)
			_expect(atlas.atlas != null and Vector2i(atlas.atlas.get_size()) == sheet_size,
				"facility art: %s is not cut from its published %sx%s sheet" % [canonical_id, sheet_size.x, sheet_size.y], failures)
	_expect(art.canonical_id("equipment_base", "  ") == "", "facility art: a blank local id must resolve to nothing", failures)
	_expect(art.icon("") == null, "facility art: a blank canonical id must return no texture", failures)
	_expect(art.icon("equipment.not_published") == null, "facility art: an unpublished id must return no texture", failures)
	_expect("equipment.not_published" in art.missing_ids(), "facility art: an unpublished id must be reported as missing", failures)


func _test_mark_lookup(failures: Array[String]) -> void:
	var art = FacilityArtScript.new()
	if not art.load_art():
		return
	for facility_id in FACILITY_MARKS:
		var texture := art.mark(String(facility_id))
		var expected_size: Vector2i = FACILITY_MARKS[facility_id]
		_expect(texture is AtlasTexture, "facility art: %s has no published facility mark" % String(facility_id), failures)
		if texture is AtlasTexture:
			var atlas := texture as AtlasTexture
			_expect(atlas.region.size == Vector2(expected_size),
				"facility art: %s mark is not its published native cell" % String(facility_id), failures)
		_expect(art.mark_size(String(facility_id)) == expected_size,
			"facility art: %s mark size does not match the published cell" % String(facility_id), failures)
	_expect(art.mark("research") == null and art.mark("immortality") == null,
		"facility art: an unmapped page must not borrow another facility's mark", failures)
	_expect(art.mark_size("research") == Vector2i.ZERO, "facility art: an unmapped page must report no mark size", failures)
	_expect(art.facility_key("Equipment / Runes  // LOADOUT") == "loadout",
		"facility art: a screen title must resolve to its published facility key", failures)
	_expect(art.facility_key("forge") == "forge", "facility art: the forge route must resolve to its own mark", failures)


## The bounded overlay: the package on disk has to be the pinned one, and the
## module has to serve exactly the six pinned ids from its sheet - at the pinned
## cell, with that sheet's real pixels, and each one visibly different from the
## base cell it superseded.
func _test_override_layer(failures: Array[String]) -> void:
	var atlas := _read_json(OVERRIDE_DIRECTORY.path_join("atlas.json"))
	var sheet := _read_png(OVERRIDE_DIRECTORY.path_join(OVERRIDE_TEXTURE_FILE))
	if atlas.is_empty() or sheet == null or sheet.get_size() != OVERRIDE_CANVAS:
		_expect(false, "facility art overlay: %s must publish a %s %s" % [OVERRIDE_DIRECTORY, str(OVERRIDE_CANVAS), OVERRIDE_TEXTURE_FILE], failures)
		return
	_expect(int(atlas.get("schema_version", 0)) == 1, "facility art overlay: the package must be a schema_version 1 atlas", failures)
	_test_override_table(atlas, sheet, failures)
	var art = FacilityArtScript.new()
	if not art.load_art():
		_expect(false, "facility art overlay: the published packages must load: %s" % art.pending_reason, failures)
		return
	_test_override_priority(art, sheet, failures)
	_test_override_boundaries(art, failures)
	_test_override_refusal(failures)


## The published table itself: six cells, the pinned order, the pinned ids,
## canonical ids and anchors, and cells that lie inside the real PNG.
func _test_override_table(atlas: Dictionary, sheet: Image, failures: Array[String]) -> void:
	var sprites: Array = chart(atlas)
	_expect(sprites.size() == OVERRIDE_IDS.size(),
		"facility art overlay: the package must publish exactly %d cells, not %d" % [OVERRIDE_IDS.size(), sprites.size()], failures)
	_expect(_declared_texture(atlas) == OVERRIDE_TEXTURE_FILE,
		"facility art overlay: the texture table must declare exactly id 'overrides' -> %s" % OVERRIDE_TEXTURE_FILE, failures)
	var seen: Array[String] = []
	for index in sprites.size():
		var raw: Variant = sprites[index]
		if not raw is Dictionary:
			_expect(false, "facility art overlay: cell %d must be an object" % index, failures)
			continue
		var entry: Dictionary = raw
		var entry_id := str(entry.get("id", ""))
		if index < OVERRIDE_IDS.size():
			var expected_id := OVERRIDE_IDS[index]
			var cell := OVERRIDE_CELLS[index]
			_expect(entry_id == expected_id, "facility art overlay: cell %d must be %s, not '%s'" % [index, expected_id, entry_id], failures)
			_expect(str(entry.get("canonical_id", "")) == OVERRIDE_CANONICAL_IDS[index],
				"facility art overlay: %s must carry the bare canonical id %s" % [expected_id, OVERRIDE_CANONICAL_IDS[index]], failures)
			_expect(str(entry.get("type", "")) == "ui_icon", "facility art overlay: %s must be a ui_icon" % expected_id, failures)
			_expect(str(entry.get("texture", "")) == OVERRIDE_TEXTURE_FILE,
				"facility art overlay: %s must be cut from %s" % [expected_id, OVERRIDE_TEXTURE_FILE], failures)
			_expect(_ints(entry.get("rect", [])) == [cell.x, cell.y, ICON_NATIVE_SIZE.x, ICON_NATIVE_SIZE.y],
				"facility art overlay: %s must occupy %s, not %s" % [expected_id, str(cell), str(entry.get("rect", []))], failures)
			var anchor := _ints(entry.get("anchor", []))
			_expect(anchor.size() == 2 and anchor == [16, 16] and anchor[0] * 2 == ICON_NATIVE_SIZE.x and anchor[1] * 2 == ICON_NATIVE_SIZE.y,
				"facility art overlay: %s must anchor at the 32x32 cell centre, not %s" % [expected_id, str(entry.get("anchor", []))], failures)
			_expect(Rect2i(Vector2i.ZERO, sheet.get_size()).encloses(Rect2i(cell, ICON_NATIVE_SIZE)),
				"facility art overlay: %s does not lie inside the published %s canvas" % [expected_id, str(OVERRIDE_CANVAS)], failures)
			_expect(_visible_pixels(sheet, Rect2i(cell, ICON_NATIVE_SIZE)) > 0,
				"facility art overlay: %s is an empty cell" % expected_id, failures)
		if entry_id in seen:
			_expect(false, "facility art overlay: %s is published twice" % entry_id, failures)
		seen.append(entry_id)
	_expect(seen.size() == OVERRIDE_IDS.size(),
		"facility art overlay: the package publishes %d ids instead of the pinned %d" % [seen.size(), OVERRIDE_IDS.size()], failures)
	for pinned_id in OVERRIDE_IDS:
		_expect(pinned_id in seen, "facility art overlay: %s must be published exactly once" % pinned_id, failures)


## Six new, fourteen old: every id of the contract table is served with real
## pixels, and the sheet those pixels come from decides which half it is in. The
## pinned six must also differ from the cell they superseded, so a layer that
## loaded but never applied cannot pass.
func _test_override_priority(art, sheet: Image, failures: Array[String]) -> void:
	var required: Array[String] = art.required_ids()
	_expect(required.size() == CONTRACT_ICON_COUNT,
		"facility art overlay: the contract table must keep its %d published ids, not %d" % [CONTRACT_ICON_COUNT, required.size()], failures)
	var repainted := 0
	var kept := 0
	for canonical_id in required:
		var index := OVERRIDE_IDS.find(canonical_id)
		var served := _icon_pixels(art, canonical_id)
		if served == null:
			_expect(false, "facility art overlay: %s has no real atlas cell" % canonical_id, failures)
			continue
		_expect(_visible_pixels(served, Rect2i(Vector2i.ZERO, served.get_size())) > 0,
			"facility art overlay: %s has no visible pixel to compare" % canonical_id, failures)
		if index >= 0:
			var cell := OVERRIDE_CELLS[index]
			_expect(_icon_sheet_size(art, canonical_id) == OVERRIDE_CANVAS,
				"facility art overlay: %s is not served from the %s overrides sheet" % [canonical_id, str(OVERRIDE_CANVAS)], failures)
			_expect(_icon_region(art, canonical_id) == Rect2(cell.x, cell.y, ICON_NATIVE_SIZE.x, ICON_NATIVE_SIZE.y),
				"facility art overlay: %s is not served at its published cell %s" % [canonical_id, str(cell)], failures)
			var reference := _cell_pixels(sheet, Rect2i(cell, ICON_NATIVE_SIZE))
			_expect(_same_pixels(served, reference),
				"facility art overlay: %s does not draw the published %s pixels" % [canonical_id, OVERRIDE_TEXTURE_FILE], failures)
			var superseded := _base_pixels(_base_entry(canonical_id))
			_expect(superseded != null and not _same_pixels(served, superseded),
				"facility art overlay: %s still draws the superseded base cell" % canonical_id, failures)
			repainted += 1
		else:
			var base := _base_entry(canonical_id)
			var base_sheet := _base_sheet(base)
			_expect(base_sheet != null and _icon_sheet_size(art, canonical_id) == base_sheet.get_size(),
				"facility art overlay: %s left the base sheet it is published on" % canonical_id, failures)
			_expect(_same_pixels(served, _base_pixels(base)),
				"facility art overlay: %s no longer draws its published base cell" % canonical_id, failures)
			kept += 1
	_expect(repainted == OVERRIDE_IDS.size(),
		"facility art overlay: %d of %d pinned ids were repainted" % [repainted, OVERRIDE_IDS.size()], failures)
	_expect(kept == CONTRACT_ICON_COUNT - OVERRIDE_IDS.size(),
		"facility art overlay: %d untouched contract icons instead of %d" % [kept, CONTRACT_ICON_COUNT - OVERRIDE_IDS.size()], failures)


## The same base batch carries the four combat-action cells the arena HUD reads
## through its own module. The overlay is bounded to equipment ids, so those
## cells must still be served from skills_actions.png pixel for pixel.
func _test_override_boundaries(art, failures: Array[String]) -> void:
	var actions := 0
	for raw in chart(_read_json(BASE_ATLAS_PATH)):
		if not raw is Dictionary:
			continue
		var base: Dictionary = raw
		var entry_id := str(base.get("id", ""))
		if not entry_id.begins_with("action."):
			continue
		actions += 1
		_expect(_same_pixels(_icon_pixels(art, entry_id), _base_pixels(base)),
			"facility art overlay: %s no longer draws its published HUD cell" % entry_id, failures)
	_expect(actions == 4, "facility art overlay: the base batch must still carry its four action cells, not %d" % actions, failures)
	_expect(art.icon("equipment.not_published") == null, "facility art overlay: an unpublished id must stay empty", failures)


## A package that is not the pinned one may not be substituted, and a refusal
## may not leave a single superseded cell behind. Both are exercised against the
## read-only seam, so nothing is written.
func _test_override_refusal(failures: Array[String]) -> void:
	for package in [BASE_ATLAS_DIRECTORY, OVERRIDE_DIRECTORY + "_not_published"]:
		var refused = FacilityArtScript.new()
		refused.override_directory = package
		_expect(not refused.load_art(), "facility art overlay: %s is not the pinned overlay and must be refused" % package, failures)
		_expect(not refused.is_ready(), "facility art overlay: a refused package must leave the module unready", failures)
		_expect(String(refused.pending_reason).begins_with("ASSETS PENDING"),
			"facility art overlay: a refused package must report its pending reason, not '%s'" % refused.pending_reason, failures)
		for canonical_id in OVERRIDE_IDS:
			_expect(refused.icon(canonical_id) == null,
				"facility art overlay: %s served %s from the superseded batch" % [package, canonical_id], failures)
		_expect(refused.icon("rune.breeding_split") == null,
			"facility art overlay: a failed load must serve no icon at all", failures)


func _test_screen_glyphs(failures: Array[String]) -> void:
	var screen = FacilityScreenScript.new()
	root.add_child(screen)
	_expect(screen.art_errors().is_empty(), "facility screen: the art packages did not load: %s" % str(screen.art_errors()), failures)

	for facility_id in FACILITY_MARKS:
		screen.present(String(facility_id), {}, {}, "", {})
		var mark: TextureRect = screen.facility_mark()
		var expected_size: Vector2i = FACILITY_MARKS[facility_id]
		_expect(mark != null, "facility screen: %s page has no header mark" % String(facility_id), failures)
		if mark == null:
			continue
		_expect(mark.name == "FacilityMark", "facility screen: the header mark lost its stable node name", failures)
		_expect(mark.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "facility screen: %s mark is not nearest-neighbour" % String(facility_id), failures)
		_expect(mark.custom_minimum_size == Vector2(expected_size),
			"facility screen: %s mark is not drawn at its published native size" % String(facility_id), failures)
		var atlas := mark.texture as AtlasTexture
		_expect(atlas != null and atlas.region.size == Vector2(expected_size),
			"facility screen: %s mark is not one published facility cell" % String(facility_id), failures)

	# A page with no published cell keeps its text and draws no substitute.
	screen.present("research", {}, {}, "", {})
	_expect(screen.facility_mark() == null, "facility screen: an unmapped page drew a substitute header mark", failures)
	_expect(screen.get_visible_text().contains("Research"), "facility screen: the unmapped page lost its own title copy", failures)

	var snapshot: Dictionary = _real_loadout_snapshot()
	screen.present("loadout", {}, {}, "", snapshot)
	_expect(not screen.backpack_detail().visible, "facility screen: equipment detail is visible before hover/focus", failures)
	_focus_backpack(screen, "equipped_main")
	var text: String = screen.get_visible_text()
	# The real equip/lock actions survive the art pass untouched.
	_expect(screen.get_action_button("Unequip_main_hand") != null,
		"facility screen: the art pass dropped the focused current item's unequip action", failures)
	_expect(screen.get_action_button("Equip_equipped_main") == null,
		"facility screen: an equipped item still offers an equip action", failures)
	_expect(text.contains("Unequipped") and text.contains("Ash Longbow") and text.contains("Rune Breeding Split")
		and text.contains("Law Pack Hunt Mark")
		and not text.contains("instance_id: equipped_main"),
		"facility screen: the default card lost its readable facts or exposed raw fields", failures)
	var current_toggle: Button = screen.get_action_button("CurrentItemFieldsToggle_main_hand")
	_expect(current_toggle == null and not text.contains("instance_id: equipped_main"),
		"facility screen: current raw item fields escaped the test console", failures)
	_focus_backpack(screen, "loot:bow/2")
	_expect(screen.get_action_button("Equip_loot_bow_2") != null,
		"facility screen: the art pass dropped the focused candidate equip action", failures)
	for slot in SLOT_IDS:
		_expect(_icon_of(screen, "SlotIcon_%s" % String(slot)) != null,
			"facility screen: slot %s has no published slot or item glyph" % String(slot), failures)
	# Closed slots live in the complete reference, leaving the first screen for loot.
	var slots_button: Button = screen.get_action_button("ClosedSlotReferenceToggle")
	_expect(slots_button != null, "facility screen: complete slot reference is unreachable", failures)
	if slots_button != null:
		slots_button.pressed.emit()
	var slots_text := screen.find_child("ItemDetailText", true, false) as Label
	var slots_dialog := screen.find_child("ItemDetailDialog", true, false) as AcceptDialog
	_expect(slots_dialog != null and slots_dialog.visible, "facility screen: slot reference did not open", failures)
	for raw_slot: Variant in snapshot["equipment_slots"]:
		var slot := String(raw_slot)
		var is_open := slot in (snapshot["prototype_open_slots"] as Array)
		_expect(slots_text != null and slots_text.text.contains("%s: %s" % [screen._slot_title(slot), "Available" if is_open else "Unavailable"]),
			"facility screen: slot reference lost the real state for " + slot, failures)
		if not is_open:
			_expect(screen.find_child(_icon_node_name("LoadoutSlotCell", slot), true, false) == null,
				"facility screen: a closed slot returned to the working area", failures)
	if slots_dialog != null: slots_dialog.hide()
	for slot: String in SLOT_IDS.keys():
		var open_cell: Control = screen.find_child(_icon_node_name("LoadoutSlotCell", slot), true, false)
		_expect(open_cell != null and _lock_marks(open_cell) == 0,
			"facility screen: the open slot %s drew a lock mark" % slot, failures)
	_expect(_region_of(screen, "SlotIcon_main_hand") == _expected_region("equipment.ashwood_longbow"),
		"facility screen: the equipped main hand does not draw its real base icon", failures)
	_expect(_region_of(screen, "SlotIcon_off_hand") == _expected_region("equipment_slot.off_hand"),
		"facility screen: the empty off hand does not draw its own published slot cell", failures)
	_expect(_region_of(screen, "CandidateBackpackIcon_loot_bow_2") == _expected_region("equipment.swift_recurve_bow"),
		"facility screen: an inventory candidate does not draw its real base icon", failures)
	# Active modifiers moved into the complete build reference in R11 so the
	# working area stays on screen. Published cells are still verified by the
	# loader tests above; the actual UI entry must retain both readable names.
	var build_reference: Button = screen.get_action_button("LoadoutDetailsToggle")
	_expect(build_reference != null, "facility screen: complete build reference is unreachable", failures)
	if build_reference != null:
		build_reference.pressed.emit()
		var reference_text: Label = screen.find_child("ItemDetailText", true, false) as Label
		var reference_dialog: AcceptDialog = screen.find_child("ItemDetailDialog", true, false) as AcceptDialog
		_expect(reference_dialog != null and reference_dialog.visible and reference_text != null
			and reference_text.text.contains("Breeding Split") and reference_text.text.contains("Pack Hunt Mark"),
			"facility screen: complete build reference lost active rune or law names", failures)
		if reference_dialog != null:
			reference_dialog.hide()
	for name in ["SlotIcon_main_hand", "SlotIcon_off_hand", "CandidateBackpackIcon_loot_bow_2"]:
		_assert_body_icon(screen, name, failures)

	# The equip preview and the locked/unlocked actions are state, not art.
	var forge: Dictionary = _forge_snapshot(true)
	screen.present("forge", {}, {}, "", forge)
	_expect(_region_of(screen, "ForgeTargetIcon_equipment_ashwood_longbow") == _expected_region("equipment.ashwood_longbow"),
		"facility screen: the forge target does not draw its real base icon", failures)
	_expect(_region_of(screen, "ForgeBackpackIcon_loot_bow_2") == _expected_region("equipment.swift_recurve_bow"),
		"facility screen: a forge inventory item does not draw its real base icon", failures)
	_focus_backpack(screen, "loot:bow/2")
	var other_button: Button = screen.get_action_button("SelectForgeItem_loot_bow_2")
	_expect(other_button != null and not other_button.disabled, "facility screen: the forge selection contract changed", failures)
	# The two-column workflow starts with one free foresight action: before any
	# candidate is revealed the dock exposes neither Select nor Confirm, and the
	# retired third preview column may not return.
	_expect(screen.get_action_button("ForgeReveal") != null
		and screen.get_action_button("ForgeSelectCandidate") == null
		and screen.get_action_button("ForgeConfirmSelection") == null,
		"facility screen: the unrevealed forge did not keep its single foresight entry", failures)
	_expect(screen.find_child("ForgePreviewPanel", true, false) == null,
		"facility screen: the retired third preview column returned", failures)
	var locked: Dictionary = _forge_snapshot(false)
	screen.present("forge", {}, {}, "", locked)
	_expect(screen.get_action_button("ForgeReveal") == null
		and screen.get_action_button("ForgeSelectCandidate") == null
		and screen.get_action_button("ForgeConfirmSelection") == null,
		"facility screen: a locked forge gained foresight or commit actions after the art pass", failures)

	screen.present("proxy", {}, {}, "", snapshot)
	_expect(_region_of(screen, "RewardCoreIcon_core_near_enemy_horizon") == _expected_region("core.near_enemy_horizon"),
		"facility screen: the locked proxy reward preview does not draw the real white cores", failures)
	snapshot["proxy"]["unlocked"] = true
	snapshot["progression"]["proxy_unlocked"] = true
	screen.present("proxy", {}, {}, "", snapshot)
	var core_order: Array[String] = ["core.near_enemy_horizon", "core.direct_gait", "core.single_key_execution", "core.short_trace_memory"]
	# Every core now owns a distinct slot cell, so the order is read from the tree:
	# the published CoreIcon cells collected depth-first must be the published
	# perception -> action -> execution -> memory order.
	var rendered_cores: Array[String] = []
	for node: Node in screen.find_children("CoreIcon_*", "TextureRect", true, false):
		rendered_cores.append(str(node.get_meta("canonical_id", "")))
	_expect(rendered_cores == core_order,
		"facility screen: the four white cores are not one distinct slot each in perception to memory order: %s" % str(rendered_cores), failures)
	for canonical: String in core_order:
		var node_name := "CoreIcon_%s" % canonical.replace(".", "_")
		_expect(_region_of(screen, node_name) == _expected_region(canonical),
			"facility screen: white core %s is missing or drew the wrong cell" % canonical, failures)
	_assert_body_icon(screen, "CoreIcon_core_near_enemy_horizon", failures)

	# An id the batch does not publish stays text-only and is reported.
	var unknown: Dictionary = _real_loadout_snapshot()
	(unknown["inventory_equipment"] as Array)[1]["base_item_id"] = "unpublished_relic"
	screen.present("loadout", {}, {}, "", unknown)
	_focus_backpack(screen, "loot:bow/2")
	_expect(screen.get_action_button("Equip_loot_bow_2") != null,
		"facility screen: an unpublished base id removed the real equip action", failures)
	_expect(_icon_of(screen, "CandidateIcon_loot_bow_2") == null,
		"facility screen: an unpublished base id drew some other item's icon", failures)
	var equip_label: Button = screen.get_action_button("Equip_loot_bow_2")
	# Missing catalogue and art entries keep a safe readable fallback and a real
	# equip action. Internal IDs belong to the test console, not item names.
	_expect(equip_label != null and equip_label.text == "Equip"
		and equip_label.tooltip_text == "Equip and Apply · Unknown Base",
		"facility screen: an unpublished base id changed the item's own copy: %s" % ("" if equip_label == null else "%s / %s" % [equip_label.text, equip_label.tooltip_text]), failures)
	var unpublished_name: Label = screen.find_child("CandidateName_loot_bow_2", true, false) as Label
	_expect(unpublished_name != null and unpublished_name.visible and unpublished_name.text == "Unknown Base",
		"facility screen: an unpublished base id lost the candidate's own readable name", failures)
	var candidate_toggle: Button = screen.get_action_button("CandidateFieldsToggle_loot_bow_2")
	_expect(candidate_toggle == null and not screen.get_visible_text().contains("Base modifiers"),
		"facility screen: unpublished item exposed raw fields outside the test console", failures)
	_expect("equipment.unpublished_relic" in screen.missing_art_ids(),
		"facility screen: an unpublished base id was not reported as missing art", failures)

	root.remove_child(screen)
	screen.free()


func _assert_body_icon(screen: Node, node_name: String, failures: Array[String]) -> void:
	var icon := _icon_of(screen, node_name)
	if icon == null:
		_expect(false, "facility screen: %s is missing" % node_name, failures)
		return
	_expect(icon.custom_minimum_size == ICON_DISPLAY_SIZE and icon.size == ICON_DISPLAY_SIZE,
		"facility screen: %s is not displayed at 64x64 from a 32x32 cell" % node_name, failures)
	_expect(icon.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST,
		"facility screen: %s is not nearest-neighbour" % node_name, failures)
	_expect(icon.expand_mode == TextureRect.EXPAND_IGNORE_SIZE and icon.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED,
		"facility screen: %s must preserve its aspect at the integer 2x cell size" % node_name, failures)
	var atlas := icon.texture as AtlasTexture
	_expect(atlas != null and atlas.region.size == Vector2(ICON_NATIVE_SIZE),
		"facility screen: %s is not one 32x32 published cell" % node_name, failures)


func _focus_backpack(screen: Node, instance_id: String) -> void:
	var token := instance_id.replace(":", "_").replace("/", "_")
	var button := screen.find_child("BackpackItem_%s" % token, true, false) as Button
	if button != null:
		button.focus_entered.emit()


func _icon_of(screen: Node, node_name: String) -> TextureRect:
	return screen.find_child(node_name, true, false) as TextureRect


## The screen names every icon cell after the canonical id it resolved, folded
## into one node token. Deriving the expected name the same way keeps the test
## honest about which published id it is asserting.
func _icon_node_name(prefix: String, token_source: String) -> String:
	var token := ""
	for index in token_source.length():
		var character := token_source.substr(index, 1)
		var code := character.unicode_at(0)
		var legal := code >= 48 and code <= 57 or code >= 65 and code <= 90 or code >= 97 and code <= 122 or character in ["_", "-"]
		token += character if legal else "_"
	return "%s_%s" % [prefix, token]


func _region_of(screen: Node, node_name: String) -> Rect2:
	var icon := _icon_of(screen, node_name)
	if icon == null or not icon.texture is AtlasTexture:
		return Rect2()
	return (icon.texture as AtlasTexture).region


## The code-native lock: a Control whose script is the published lock module, drawn
## from integer rectangles rather than cut from any art sheet.
func _lock_marks(node: Node) -> int:
	var count := 0
	for child: Node in node.find_children("*", "Control", true, false):
		var script := child.get_script() as Script
		if script != null and String(script.resource_path).ends_with("locked_slot_mark.gd"):
			count += 1
	return count


## Published cells drawn under a node: a locked slot that carried one would be reading
## as equipment, so the count there has to stay zero.
func _published_icons(node: Node) -> int:
	var count := 0
	for child: Node in node.find_children("*", "TextureRect", true, false):
		if not str((child as TextureRect).get_meta("canonical_id", "")).is_empty():
			count += 1
	return count


func _is_pinned(canonical_id: String) -> bool:
	return canonical_id in OVERRIDE_IDS


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}


## The published file's own pixels, not the imported resource's: this is the
## independent side of every pixel comparison below.
func _read_png(path: String) -> Image:
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var image := Image.new()
	if image.load_png_from_buffer(file.get_buffer(file.get_length())) != OK:
		return null
	return image


func _ints(value: Variant) -> Array:
	if not value is Array:
		return []
	var listed: Array = value
	var converted: Array = []
	for item in listed:
		converted.append(int(item))
	return converted


## The one texture the overlay table declares, or an empty string when the table
## is not exactly the pinned one.
func _declared_texture(atlas: Dictionary) -> String:
	var textures: Variant = atlas.get("textures", [])
	if not textures is Array or (textures as Array).size() != 1:
		return ""
	var meta: Variant = (textures as Array)[0]
	if not meta is Dictionary:
		return ""
	var declared: Dictionary = meta
	if str(declared.get("id", "")) != "overrides":
		return ""
	return str(declared.get("file", ""))


## One cell of a published sheet as RGBA8 pixels. The sheet is copied first, so
## comparing never converts the image the module itself is holding.
func _cell_pixels(sheet: Image, rect: Rect2i) -> Image:
	if sheet == null or not Rect2i(Vector2i.ZERO, sheet.get_size()).encloses(rect):
		return null
	var copy := sheet.duplicate()
	if copy.get_format() != Image.FORMAT_RGBA8:
		copy.convert(Image.FORMAT_RGBA8)
	return copy.get_region(rect)


## Pixel identity of two cells, alpha across the whole cell and RGB wherever
## either cell is visible. RGB under a fully transparent pixel is not compared:
## the texture importer's alpha-border bleed legitimately rewrites it and no
## rendered pixel can show it, so comparing it would only invent failures.
func _same_pixels(served: Image, published: Image) -> bool:
	if served == null or published == null:
		return false
	if served.get_size() != published.get_size() or served.get_format() != published.get_format():
		return false
	for y in published.get_height():
		for x in published.get_width():
			var expected := published.get_pixel(x, y)
			var actual := served.get_pixel(x, y)
			if actual.a != expected.a:
				return false
			if (expected.a > 0.0 or actual.a > 0.0) and (actual.r != expected.r or actual.g != expected.g or actual.b != expected.b):
				return false
	return true


func _visible_pixels(sheet: Image, rect: Rect2i) -> int:
	var cell := _cell_pixels(sheet, rect)
	if cell == null:
		return 0
	var count := 0
	for y in cell.get_height():
		for x in cell.get_width():
			if cell.get_pixel(x, y).a > 0.0:
				count += 1
	return count


## The published base entry of a canonical id, straight from the base batch.
func _base_entry(canonical_id: String) -> Dictionary:
	for raw in chart(_read_json(BASE_ATLAS_PATH)):
		if raw is Dictionary and str((raw as Dictionary).get("id", "")) == canonical_id:
			return raw
	return {}


func _base_sheet(entry: Dictionary) -> Image:
	return _read_png(BASE_ATLAS_DIRECTORY.path_join(str(entry.get("texture", ""))))


func _base_pixels(entry: Dictionary) -> Image:
	if entry.is_empty():
		return null
	var rect := _ints(entry.get("rect", []))
	if rect.size() != 4:
		return null
	return _cell_pixels(_base_sheet(entry), Rect2i(rect[0], rect[1], rect[2], rect[3]))


## The pixels the module is really serving for one id: the region it returned, cut
## from the sheet it returned it from. Reading the served sheet's image is what
## makes these comparisons pixels rather than metadata.
func _icon_pixels(art, canonical_id: String) -> Image:
	var texture: Variant = art.icon(canonical_id)
	if not texture is AtlasTexture:
		return null
	var atlas := texture as AtlasTexture
	if atlas.atlas == null:
		return null
	var region := atlas.region
	return _cell_pixels(atlas.atlas.get_image(), Rect2i(int(region.position.x), int(region.position.y), int(region.size.x), int(region.size.y)))


func _icon_region(art, canonical_id: String) -> Rect2:
	var texture: Variant = art.icon(canonical_id)
	return (texture as AtlasTexture).region if texture is AtlasTexture else Rect2()


func _icon_sheet_size(art, canonical_id: String) -> Vector2i:
	var texture: Variant = art.icon(canonical_id)
	if not texture is AtlasTexture or (texture as AtlasTexture).atlas == null:
		return Vector2i.ZERO
	return Vector2i((texture as AtlasTexture).atlas.get_size())


## The published cell of a canonical id, read from the atlas table rather than
## from the module under test, so the assertion cannot agree with a wrong table.
## The overlay wins where it pins an id; everywhere else the base batch does.
func _expected_region(canonical_id: String) -> Rect2:
	if _is_pinned(canonical_id):
		for raw in chart(_read_json(OVERRIDE_DIRECTORY.path_join("atlas.json"))):
			if not raw is Dictionary or str((raw as Dictionary).get("id", "")) != canonical_id:
				continue
			var cell := _ints((raw as Dictionary).get("rect", []))
			if cell.size() == 4:
				return Rect2(float(cell[0]), float(cell[1]), float(cell[2]), float(cell[3]))
		return Rect2()
	var atlas := _read_json(BASE_ATLAS_PATH)
	var prefix := canonical_id.split(".", false)[0]
	var local_id := canonical_id
	if canonical_id.contains("."):
		local_id = canonical_id.substr(canonical_id.find(".") + 1)
	var expected_texture := ""
	match prefix:
		"equipment_slot":
			expected_texture = "equipment_slots"
		"equipment":
			expected_texture = "equipment_bases"
		"rune", "law":
			expected_texture = "runes_law"
		"core":
			expected_texture = "white_cores"
	for raw_entry in chart(atlas):
		var entry: Dictionary = raw_entry
		if str(entry.get("id", null)) != canonical_id:
			continue
		if not str(entry.get("texture", "")).begins_with(expected_texture):
			continue
		var rect: Array = entry.get("rect", [])
		if rect.size() != 4:
			continue
		return Rect2(float(rect[0]), float(rect[1]), float(rect[2]), float(rect[3]))
	return Rect2()


## The published canvas of the sheet a canonical id belongs to, straight from the
## atlas texture table.
func _published_sheet_size(canonical_id: String) -> Vector2i:
	if _is_pinned(canonical_id):
		# The overlay texture table carries no dimensions, so the published size
		# of the overrides sheet is read from the real file.
		var sheet := _read_png(OVERRIDE_DIRECTORY.path_join(OVERRIDE_TEXTURE_FILE))
		return sheet.get_size() if sheet != null else Vector2i.ZERO
	var atlas := _read_json(BASE_ATLAS_PATH)
	var prefix := canonical_id.split(".", false)[0]
	var sheet_id := ""
	match prefix:
		"equipment_slot":
			sheet_id = "equipment_slots"
		"equipment":
			sheet_id = "equipment_bases"
		"rune", "law":
			sheet_id = "runes_law"
		"core":
			sheet_id = "white_cores"
	var texture_table: Variant = atlas.get("textures", [])
	if not texture_table is Array:
		return Vector2i.ZERO
	for raw_meta in texture_table as Array:
		if not raw_meta is Dictionary:
			continue
		var meta: Dictionary = raw_meta
		if str(meta.get("id", null)) != sheet_id:
			continue
		var dimensions: Variant = meta.get("dimensions", [])
		if dimensions is Array and (dimensions as Array).size() == 2:
			return Vector2i(int((dimensions as Array)[0]), int((dimensions as Array)[1]))
	return Vector2i.ZERO


func chart(atlas: Dictionary) -> Array:
	var sprites: Variant = atlas.get("sprites", [])
	return sprites if sprites is Array else []


func _real_loadout_snapshot() -> Dictionary:
	return {
		"ok": true,
		"equipment_slots": ["head", "chest", "pants", "leg_armor", "gloves", "bracers", "belt", "main_hand", "off_hand", "ring_1", "ring_2", "necklace"],
		"prototype_open_slots": ["main_hand", "off_hand", "gloves", "ring_1"],
		"base_items": {
			"ashwood_longbow": {"id": "ashwood_longbow", "name": "Ash Longbow", "slot": "main_hand"},
			"swift_recurve_bow": {"id": "swift_recurve_bow", "name": "Swiftstring Recurve", "slot": "main_hand"},
			"turnfeather_gloves": {"id": "turnfeather_gloves", "name": "Guiding Fletch Gloves", "slot": "gloves"},
			"vitality_ring": {"id": "vitality_ring", "name": "Vitality Ring", "slot": "ring_1"},
		},
		"affix_families": {"piercing_continuation": {"id": "piercing_continuation", "name": "Piercing Arrow Continuation Chance", "tiers": [{"tier": 2, "value": 0.07}]}},
		"inventory_equipment": [
			{"instance_id": "equipped_main", "base_item_id": "ashwood_longbow", "slot": "main_hand", "affixes": [], "rune_id": "breeding_split", "law_id": "pack_hunt_mark"},
			{"instance_id": "loot:bow/2", "base_item_id": "swift_recurve_bow", "slot": "main_hand", "affixes": [], "rune_id": "", "law_id": ""},
			{"instance_id": "equipped_gloves", "base_item_id": "turnfeather_gloves", "slot": "gloves", "affixes": [], "rune_id": "", "law_id": ""},
			{"instance_id": "equipped_ring", "base_item_id": "vitality_ring", "slot": "ring_1", "affixes": [], "rune_id": "", "law_id": ""},
		],
		"active_build": {
			"skills": ["piercing_arrow", "", ""],
			"equipped_item_ids": {
				"head": "", "chest": "", "pants": "", "leg_armor": "", "gloves": "equipped_gloves", "bracers": "",
				"belt": "", "main_hand": "equipped_main", "off_hand": "", "ring_1": "equipped_ring", "ring_2": "", "necklace": "",
			},
			"runes": ["breeding_split"], "laws": ["pack_hunt_mark"], "preset_id": "exponential",
		},
		"resolved_build": {
			"ok": true,
			"final_parameters": {"p": 0.61, "T": 34.0, "v": 682.0, "d": 165.0, "turn": 0.16, "damage": 160.0, "max_health": 112.0},
			"connected_interfaces": ["breedable_event"], "missing_interfaces": [],
			"build_fingerprint": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
			"growth_classification": "exponential",
		},
		"training": {"reports_by_fingerprint": {}},
		"proxy": {"unlocked": false, "cores": ["nearest_enemy", "direct_gait", "single_key_execution", "short_trace_memory"]},
		"progression": {"proxy_unlocked": false, "auto_contract_wins": 0, "early_game_complete": false},
	}


func _forge_snapshot(unlocked: bool) -> Dictionary:
	var snapshot: Dictionary = _real_loadout_snapshot()
	var target: Dictionary = (snapshot["inventory_equipment"] as Array)[0].duplicate(true)
	target["base_name"] = "Ash Longbow"
	var other: Dictionary = (snapshot["inventory_equipment"] as Array)[1].duplicate(true)
	other["base_name"] = "Swiftstring Recurve"
	snapshot["ok"] = true
	snapshot["unlocked"] = unlocked
	snapshot["locked_reason"] = "Complete Main Quest 04 to unlock Law Token forging" if not unlocked else ""
	snapshot["inventory_items"] = [target.duplicate(true), other]
	snapshot["target_item"] = target
	snapshot["target_instance_id"] = "equipped_main"
	snapshot["affixes"] = []
	snapshot["operation"] = "inscribe"
	snapshot["blocked"] = false
	snapshot["blocked_reason"] = ""
	snapshot["revision"] = 0
	snapshot["law_tallies"] = {"inscribe": 2, "rewrite": 2, "refine": 2}
	# Candidates, including their read-only affected_affix_index metadata, are only
	# ever served inside an authoritative session; the player never inputs one.
	snapshot["session"] = {}
	return snapshot


func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print("PASS  test_facility_art.gd")
		quit(0)
		return
	for failure in failures:
		printerr("- %s" % failure)
	quit(1)


func _expect(condition: bool, message: String, failures: Array[String]) -> void: Assert.expect(condition, message, failures)
