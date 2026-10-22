extends SceneTree
## Headless node geometry and interactions; never evidence of GPU pixels.
const Screen = preload("res://src/presentation/facility_screen.gd")
const Fixtures = preload("res://tests/test_facility_screen.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var fixture = Fixtures.new()
	var host := Control.new()
	root.add_child(host)
	var screen = Screen.new()
	host.add_child(screen)
	for size in [Vector2(1280,720),Vector2(1366,768),Vector2(1600,900),Vector2(1600,1000),Vector2(1920,1080),Vector2(1024,576)]:
		host.size = size
		for route in ["loadout","forge"]:
			screen.present(route,{}, {}, "",fixture._real_loadout_snapshot() if route == "loadout" else fixture._forge_snapshot(true))
			for frame in range(12): await process_frame
			print("LAYOUT ",route," ",size," root=",screen.size," frame=",screen._layout_frame)
			for node in screen.find_children("*","ScrollContainer",true,false):
				var scroll := node as ScrollContainer
				# Dropdowns own internal scrolling for long option lists. Like detail
				# readers, they need visible scroll affordances; they are not the
				# passive page-layout fallback this check is intended to suppress.
				var is_reader := String(scroll.name) in ["SkillDetailScroll", "ItemDetailScroll"] or _inside_popup_menu(scroll)
				var rail := scroll.get_v_scroll_bar().get_theme_stylebox("scroll")
				if is_reader and rail is StyleBoxEmpty:
					failures.append("%s %s active reader or dropdown lost visible scrollbar chrome" % [route, str(size)])
				elif not is_reader and not rail is StyleBoxEmpty:
					failures.append("%s %s passive scrollbar chrome remains on %s" % [route, str(size), str(scroll.get_path())])
				if not is_reader and scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED:
					failures.append("%s %s passive scroll fallback was disabled on %s" % [route, str(size), str(scroll.get_path())])
				if not scroll.is_visible_in_tree(): continue
				if scroll.get_h_scroll_bar().max_value > scroll.size.x + 1.0:
					failures.append("%s %s width %s contents %s" % [route,str(size),str(node.get_path()),str(node.get_h_scroll_bar().max_value)])
			var names := ["ReturnToBaseButton","OpenSlotStrip","LoadoutSkillStrip","SkillSummary_piercing_arrow","SkillSummary_hunter_mark","SkillSummary_dash","SkillSummary_basic_dodge","ClosedEquipmentSlots","LoadoutCharacterPortrait","SlotCompareSection","EquipmentBackpack","EquipmentBackpackViewport","EquipmentBackpackPager","BackpackCell_loot_bow_2","BackpackItem_loot_bow_2","BackpackDetail","ForgeTargetPanel","ForgeSetupPanel","ForgeRevealPanel","ForgeReveal"]
			for name in names:
				var node := screen.find_child(name,true,false) as Control
				if node != null:
					print(name," ",node.get_global_rect()," visible=",_inside(node,screen))
					if name in ["ReturnToBaseButton","ForgeReveal"] or (size.x == 1280 and name in ["OpenSlotStrip","LoadoutSkillStrip","SkillSummary_piercing_arrow","SkillSummary_hunter_mark","SkillSummary_dash","SkillSummary_basic_dodge","LoadoutCharacterPortrait","EquipmentBackpack","BackpackCell_loot_bow_2","BackpackItem_loot_bow_2"]):
						if not _inside(node,screen): failures.append(route+" "+str(size)+" clipped "+name)
			var backpack := screen.find_child("EquipmentBackpack", true, false)
			if backpack != null and backpack.find_child("EquipmentBackpackScroll", true, false) != null:
				failures.append(route+" "+str(size)+" backpack still uses a ScrollContainer")
			if route == "loadout":
				_check_loadout_composition(screen,size)
			else:
				_check_forge_composition(screen,size)
			if route == "forge":
				var before := JSON.stringify(screen._facility_data)
				var events: Array = []
				var listener := func(f,a,p): events.append([f,a,p])
				screen.action_requested.connect(listener)
				var reveal := screen.get_action_button("ForgeReveal") as Button
				if reveal != null and reveal.disabled:
					var inscribe := screen.get_action_button("ForgeOperation_inscribe") as Button
					if inscribe != null and not inscribe.disabled:
						inscribe.pressed.emit()
					reveal = screen.get_action_button("ForgeReveal") as Button
				events.clear()
				if reveal == null: failures.append("forge reveal is missing")
				if reveal != null: reveal.pressed.emit()
				var after_reveal := JSON.stringify(screen._facility_data)
				if events.size() != 1 or String(events[0][1]) != "forge_reveal" or before != after_reveal or not (events[0][2] as Dictionary).has("revision") or (events[0][2] as Dictionary).has("affix_index"):
					failures.append("free reveal did not emit once with only a revision without mutating presentation state: size=%s events=%s state_changed=%s disabled=%s operation=%s block=%s can_start=%s" % [
						str(size), str(events), str(before != after_reveal), str(reveal.disabled if reveal != null else true),
						String(screen.get("_forge_operation")),
						String(screen._forge_operation_block_reason(String(screen.get("_forge_operation")))), str(screen._forge_can_start()),
					])
				events.clear()
				screen.present("forge", {}, {}, "", fixture._forge_snapshot(true, true))
				for frame in range(2): await process_frame
				# Single decision surface while browsing an unselected future: select is
				# the only armed primary, and no control or payload names an affix slot.
				var select := screen.get_action_button("ForgeSelectCandidate") as Button
				if select == null: failures.append("forge candidate selection is missing")
				if select != null and select.disabled: failures.append("forge candidate selection is disabled while browsing")
				if screen.get_action_button("ForgeConfirmSelection") != null: failures.append("confirm appeared beside select while the browsed future is unselected")
				_check_no_affix_slot_choice(screen, size)
				if select != null: select.pressed.emit()
				if events.size() != 1 or String(events[0][1]) != "forge_select_candidate" or not (events[0][2] as Dictionary).has("candidate_id") or (events[0][2] as Dictionary).has("affix_index"):
					failures.append("candidate selection did not emit once")
				events.clear()
				# After the authoritative re-present with the selection, the rebuilt
				# footer swaps select for confirm: still exactly one armed primary.
				screen.present("forge", {}, {}, "", fixture._forge_snapshot(true, true, "candidate-1"))
				for frame in range(2): await process_frame
				if screen.get_action_button("ForgeSelectCandidate") != null: failures.append("select survived after the browsed future became the selected one")
				var armed_confirm := screen.get_action_button("ForgeConfirmSelection") as Button
				if armed_confirm == null: failures.append("confirm is missing once the selected future is being browsed")
				elif armed_confirm.disabled: failures.append("confirm is disabled although the browsed future is selected and affordable")
				_check_no_affix_slot_choice(screen, size)
				events.clear()
				screen.present("forge", {}, {}, "", fixture._forge_snapshot(true, true, "candidate-1"))
				for frame in range(2): await process_frame
				var confirm := screen.get_action_button("ForgeConfirmSelection") as Button
				if confirm == null: failures.append("forge confirm is missing")
				if confirm != null: confirm.pressed.emit()
				if events.size() != 1 or String(events[0][1]) != "forge_commit" or (events[0][2] as Dictionary).has("affix_index"): failures.append("confirm did not emit once")
				confirm = screen.get_action_button("ForgeConfirmSelection") as Button
				if confirm != null: confirm.pressed.emit()
				if events.size() != 1: failures.append("double confirm emitted twice")
				screen.action_requested.disconnect(listener)
	host.size = Vector2(1280, 720)
	for flag in [null, true, false]:
		var snapshot: Dictionary = fixture._forge_snapshot(true)
		if flag != null:
			snapshot["ok"] = flag
		screen.present("forge", {}, {}, "", snapshot)
		for frame in range(4): await process_frame
		if screen.find_child("FacilityOverview", true, false) != null:
			failures.append("nonempty forge duplicates its compact mark with a page lead: %s" % str(flag))
		if screen.find_children("FacilityMark", "", true, false).size() != 1:
			failures.append("nonempty forge must show exactly one mark: %s" % str(flag))
		_check_forge_composition(screen, host.size)
	screen.present("forge", {}, {}, "", {})
	for frame in range(4): await process_frame
	if screen.find_child("FacilityOverview", true, false) == null or screen.find_children("FacilityMark", "", true, false).size() != 1:
		failures.append("unavailable forge lost its single page mark")
	print("WORKBENCH_LAYOUT ","pass" if failures.is_empty() else "fail", " ",failures)
	host.free()
	fixture.free()
	quit(0 if failures.is_empty() else 1)

func _inside_popup_menu(node: Node) -> bool:
	var ancestor := node.get_parent()
	while ancestor != null:
		if ancestor is PopupMenu:
			return true
		ancestor = ancestor.get_parent()
	return false

func _inside(node: Control, screen: Control) -> bool:
	var rect := node.get_global_rect()
	if not node.is_visible_in_tree() or not screen.get_global_rect().encloses(rect): return false
	var parent := node.get_parent()
	while parent is Control:
		if parent.clip_contents and not parent.get_global_rect().encloses(rect): return false
		parent = parent.get_parent()
	return true


## Concept 10/03 at the size under test: the four open slots and the hero share the top
## row. The four action summaries start the lower-left local scroll lane, beside the
## current/candidate comparison; the eight locked cells remain behind them in that same
## reachable lane. On the shipped 1280 canvas the candidate identity and primary Equip
## action sit inside the first screen; the longer comparison follows in local scroll. The smaller
## frame may scroll vertically, and the sweep above still forbids sideways overflow.
func _check_loadout_composition(screen: Control, size: Vector2) -> void:
	var tag := "loadout %dx%d" % [int(size.x),int(size.y)]
	var slots: Control = screen.find_child("LoadoutSlotsRegion",true,false)
	var hero_region: Control = screen.find_child("LoadoutHeroRegion",true,false)
	var locked: Control = screen.find_child("LoadoutLockedRegion",true,false)
	var compare: Control = screen.find_child("LoadoutCompareRegion",true,false)
	var strip: Control = screen.find_child("OpenSlotStrip",true,false)
	var skill_strip: Control = screen.find_child("LoadoutSkillStrip",true,false)
	var closed: Control = screen.find_child("ClosedEquipmentSlots",true,false)
	var comparison: Control = screen.find_child("SlotCompareSection",true,false)
	var portrait: Control = screen.find_child("LoadoutCharacterPortrait",true,false)
	if slots == null or hero_region == null or locked == null or compare == null or strip == null or skill_strip == null or closed == null or comparison == null or portrait == null:
		failures.append(tag+" is missing a concept region, the slot/skill strip, the locked grid, the comparison or the hero")
		return
	var report: Dictionary = screen.layout_report()
	var regions: Dictionary = report.get("regions",{})
	var origin := slots.get_global_rect().position
	for key in ["slots","hero","locked","compare"]:
		var region_node: Control = {"slots":slots,"hero":hero_region,"locked":locked,"compare":compare}[key]
		var measured := Rect2(region_node.get_global_rect().position - origin,region_node.get_global_rect().size)
		if not _same_rect(measured,regions.get(key,Rect2())):
			failures.append("%s: the %s region is not the reported one (%s vs %s)" % [tag,key,str(measured),str(regions.get(key,Rect2()))])
	if hero_region.get_global_rect().position.x < slots.get_global_rect().end.x or not _same_top(hero_region,slots):
		failures.append("%s: the hero region is not right of the four slots on the same top edge" % tag)
	if portrait.get_global_rect().position.x < strip.get_global_rect().end.x or not _same_top(portrait,strip):
		failures.append("%s: the hero is not right of the four open slots on the same top edge" % tag)
	if skill_strip.get_global_rect().position.y < slots.get_global_rect().end.y + 1.0:
		failures.append("%s: the skill strip is not below the four-slot row" % tag)
	if closed.get_global_rect().position.y < skill_strip.get_global_rect().end.y - 1.0:
		failures.append("%s: the locked grid is not after the skill strip" % tag)
	if comparison.get_global_rect().position.x < locked.get_global_rect().end.x or not _same_top(comparison,locked):
		failures.append("%s: the comparison is not right of the lower-left region on the same top edge" % tag)
	if not locked is ScrollContainer or not locked.is_ancestor_of(closed):
		failures.append("%s: the locked grid is not reachable through its local scroll region" % tag)
	var open_row := screen.find_child("OpenSlotRow",true,false) as GridContainer
	var closed_row := screen.find_child("ClosedSlotRow",true,false) as GridContainer
	if open_row == null or open_row.columns != 4 or open_row.get_child_count() != 4:
		failures.append("%s: the open slots are not four cells on one row" % tag)
	if closed_row != null:
		failures.append("%s: locked slots still consume the comparison workspace" % tag)
	if screen.find_child("ClosedSlotReferenceToggle",true,false) == null:
		failures.append("%s: folded slots lost their explanation entry" % tag)
	if size.x < 1280.0:
		return
	var skill_buttons := screen.find_children("SkillSummary_*", "Button", true, false)
	if skill_buttons.size() != 4:
		failures.append("%s: the lower-left lane does not expose four skill actions" % tag)
	for node: Control in [strip,skill_strip,portrait]:
		if not _inside(node,screen):
			failures.append("%s: %s is clipped out of the first screen (%s)" % [tag,node.name,str(node.get_global_rect())])
	for skill_value in skill_buttons:
		var skill_button := skill_value as Control
		if skill_button != null and not _inside(skill_button,screen):
			failures.append("%s: skill action %s is clipped out of the first screen (%s)" % [tag,skill_button.name,str(skill_button.get_global_rect())])
	if open_row != null:
		for raw_cell: Node in open_row.get_children():
			var cell := raw_cell as Control
			if cell != null and not _inside(cell,screen):
				failures.append("%s: the open slot cell %s is clipped out of the first screen (%s)" % [tag,cell.name,str(cell.get_global_rect())])
	# The compact backpack owns one icon per item. Long candidate/current-item copy
	# must not be instantiated until hover or keyboard focus asks for the single
	# shared detail surface.
	var backpack := screen.find_child("EquipmentBackpack",true,false) as Control
	var candidate_cell := screen.backpack_cell("loot:bow/2") as Control
	var candidate_button := screen.find_child("BackpackItem_loot_bow_2",true,false) as Control
	var detail := screen.backpack_detail() as Control
	if backpack == null or candidate_cell == null or candidate_button == null or detail == null:
		failures.append("%s: the compact backpack, first candidate cell or shared detail is missing" % tag)
	else:
		for node: Control in [backpack,candidate_cell,candidate_button]:
			if not _inside(node,screen):
				failures.append("%s: %s is clipped out of the first screen (%s)" % [tag,node.name,str(node.get_global_rect())])
		if detail.visible:
			failures.append("%s: equipment detail is visible before hover/focus" % tag)
	for retired: String in ["CandidateCell_loot_bow_2","CandidateName_loot_bow_2","Equip_loot_bow_2"]:
		if screen.find_child(retired,true,false) != null:
			failures.append("%s: long candidate node %s was instantiated before inspection" % [tag,retired])


## The forge keeps its compact target summary and icon backpack in the first column.
## Complete item detail appears only after inspection; all three operation choices
## stay first-screen at 1280x720 so selecting a target or Law Tally never requires
## repeated scrolling.
## The final composition is two ordered stage columns with one candidate view and
## a single decision surface in the footer: no third column and no duplicate
## preview panel may exist.
func _check_forge_composition(screen: Control, size: Vector2) -> void:
	if size.x < 1280.0:
		return
	var tag := "forge 1280x720"
	var mark: Control = screen.find_child("FacilityMark",true,false)
	var target_panel: Control = screen.find_child("ForgeTargetPanel",true,false)
	var stock: Control = screen.find_child("ForgeInventorySection",true,false)
	var target_item: Control = screen.find_child("ForgeTargetItem",true,false)
	var backpack: Control = screen.find_child("EquipmentBackpack",true,false)
	var detail: Control = screen.find_child("BackpackDetail",true,false)
	if mark == null or target_panel == null or stock == null or target_item == null or backpack == null or detail == null:
		failures.append(tag+": the facility mark, compact backpack, shared detail or target summary is missing")
		return
	for node: Control in [target_item,mark,backpack]:
		if not _inside(node,screen):
			failures.append("%s: %s is not on the first screen (%s)" % [tag,node.name,str(node.get_global_rect())])
	if detail.visible:
		failures.append(tag+": forge item detail is visible before hover/focus")
	for operation: String in ["inscribe","rewrite","refine"]:
		var operation_button := screen.get_action_button("ForgeOperation_%s" % operation) as Control
		if operation_button == null:
			failures.append("%s: operation %s is missing" % [tag,operation])
		elif not _inside(operation_button,screen):
			failures.append("%s: operation %s requires scrolling (%s)" % [tag,operation,str(operation_button.get_global_rect())])
	if mark.get_global_rect().end.y > stock.get_global_rect().position.y + 1.0:
		failures.append("%s: the facility mark is not above the stock list" % tag)
	var column_zero: Control = screen.find_child("ForgeConceptRootColumn0",true,false)
	var column_one: Control = screen.find_child("ForgeConceptRootColumn1",true,false)
	if column_zero == null or column_one == null:
		failures.append(tag+": the two stage columns are not both present")
		return
	if screen.find_child("ForgeConceptRootColumn2",true,false) != null:
		failures.append(tag+": a retired third stage column is still built")
	if not column_one.get_global_rect().position.x >= column_zero.get_global_rect().end.x - 1.0:
		failures.append(tag+": the stage columns are not ordered left to right (%s vs %s)" % [str(column_zero.get_global_rect()),str(column_one.get_global_rect())])
	for title_index in [1,2]:
		if screen.find_child("ForgeStage%dTitle" % title_index,true,false) == null:
			failures.append(tag+": stage title %d is missing" % title_index)
	if screen.find_child("ForgeStage3Title",true,false) != null or screen.find_child("ForgeStage3Status",true,false) != null:
		failures.append(tag+": a retired third stage header is still built")
	for retired in ["ForgePreviewPanel","ForgePreviewItem","ForgePreviewSelectionState","ForgePreviewCost","ForgePreviewIcon"]:
		if screen.find_child(retired,true,false) != null:
			failures.append(tag+": the retired duplicate preview node %s is still built" % retired)
	if column_one.get_global_rect().get_area() <= 0.0 or column_zero.get_global_rect().get_area() <= 0.0:
		failures.append(tag+": a stage column has no size")


## Reveal and selection never expose or accept an affix-slot choice: the whole
## candidate carries the authority-selected affected_affix_index and the complete
## future item, so no interactive control on the forge page may name a slot.
func _check_no_affix_slot_choice(screen: Control, size: Vector2) -> void:
	var tag := "forge %dx%d" % [int(size.x),int(size.y)]
	for retired in ["ForgeSlot_0","AffixSlot_0","SelectForgeSlot","ForgeNextAffix","ForgePrevAffix"]:
		if screen.get_action_button(retired) != null:
			failures.append(tag+": the retired affix-slot control %s is back" % retired)
	if screen.get("_forge_slot") != null:
		failures.append(tag+": the presentation layer holds a _forge_slot again")
	for value in screen.find_children("*","Control",true,false):
		var node := value as Node
		if not (node is Button or node is OptionButton or node is ItemList or node is SpinBox):
			continue
		var node_name := String(node.name)
		if node_name.begins_with("ForgeInventoryCell"):
			continue
		var lowered := node_name.to_lower()
		if lowered.contains("affixslot") or (node_name.begins_with("Forge") and lowered.contains("slot")):
			failures.append(tag+": an interactive control names a slot choice (%s)" % node_name)


## Whether two rects describe the same box within one pixel.
func _same_rect(left: Rect2, right: Rect2) -> bool:
	return left.position.distance_to(right.position) <= 1.0 and left.size.distance_to(right.size) <= 1.0


## Whether two controls start on the same row: the concept's rows are shared edges.
func _same_top(left: Control, right: Control) -> bool:
	return absf(left.get_global_rect().position.y - right.get_global_rect().position.y) <= 1.0


## Whether an eight-cell grid really lays out as two rows of four: the first four share
## one top edge, the last four share a lower one.
