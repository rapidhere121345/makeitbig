extends SceneTree

## Display-backed probe for the two concept-detail layers of the facility pages:
## the loadout hero preview and the training generational trace.
##
## Unlike the rest of the suite this probe needs a real display, because it exists
## to check what the pages really draw, not only where their controls land. It
## mounts the real FacilityScreen class in a SubViewport at a fixed logical size,
## presents explicit fixtures, audits every visible control against the logical
## frame, and writes one PNG per page and size into the requested review folder.
##
## RUN: Godot with a real display, --script res://tests/unit/test_facility_concept_detail.gd
##   -- --out=/data/tmp/facility-concept-detail-new
##
## With a headless display it prints SKIP and exits 0, so it can never wedge a
## headless run: the layout contracts of the same pages are asserted by
## tests/test_facility_screen.gd, which runs in the normal suite.
const FacilityScreenScript = preload("res://src/presentation/facility_screen.gd")

const LONG_ID := "stress_drop_00_0123456789abcdef0123456789abcdef0123456789abcdef"

var out := ""
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			out = argument.trim_prefix("--out=")
	if DisplayServer.get_name() == "headless" or out.is_empty() or not out.is_absolute_path():
		print("SKIP  facility concept detail probe: needs a real display and --out=<absolute directory>")
		quit(0)
		return
	DirAccess.make_dir_recursive_absolute(out)
	await _capture("loadout", "loadout", Vector2i(1280, 720), _loadout_fixture())
	await _capture("loadout_folded", "loadout", Vector2i(1280, 720), _long_id_fixture())
	await _capture("loadout", "loadout", Vector2i(1024, 576), _loadout_fixture())
	await _capture("training", "training", Vector2i(1280, 720), _training_fixture())
	await _capture("training", "training", Vector2i(1024, 576), _training_fixture())
	_finish()


func _capture(file_id: String, route_id: String, size: Vector2i, fixture: Dictionary) -> void:
	var stage := SubViewport.new()
	stage.size = size
	stage.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	stage.disable_3d = true
	root.add_child(stage)
	var screen = FacilityScreenScript.new()
	stage.add_child(screen)
	await process_frame
	await process_frame
	var before := fixture.duplicate(true)
	screen.present(route_id, {}, {}, "", fixture)
	await process_frame
	await process_frame
	await process_frame
	if route_id == "loadout":
		_focus_loadout_candidate(screen)
		await process_frame
		await process_frame
	var audit := _frame_audit(screen, size, "%s @%dx%d" % [file_id, size.x, size.y])
	var report := {
		"id": file_id,
		"logical": [size.x, size.y],
		"frame_audit": audit,
		"character": screen.character_preview_report(),
		"trace": screen.training_trace_report(),
	}
	if route_id == "loadout":
		var strip: Control = screen.find_child("OpenSlotStrip", true, false)
		var comparison: Control = screen.find_child("SlotCompareSection", true, false)
		var portrait: Control = screen.find_child("LoadoutCharacterPanel", true, false)
		var equip: Button = screen.get_action_button("Equip_loot_bow_2")
		report["strip"] = [] if strip == null else [strip.size.x, strip.size.y]
		report["comparison_y"] = -1.0 if comparison == null else comparison.get_global_rect().position.y
		report["portrait"] = [] if portrait == null else [portrait.size.x, portrait.size.y, portrait.get_global_rect().position.y]
		report["equip_y"] = -1.0 if equip == null else equip.get_global_rect().position.y
		if strip != null and size.x == 1280:
			_expect(strip.size.y <= 150.0, "loadout: the open slot strip is %0.1f tall" % strip.size.y)
			_expect(comparison != null and comparison.get_global_rect().position.y <= 330.0,
				"loadout: the comparison starts below the first screen")
			_expect(equip != null and equip.get_global_rect().position.y <= 600.0,
				"loadout: the candidate action left the first screen")
	if route_id == "training":
		var trace: Control = screen.find_child("TrainingGrowthTrace", true, false)
		report["trace_rect"] = [] if trace == null else [trace.size.x, trace.size.y, trace.get_global_rect().position.y]
		_expect(trace != null, "training: the verified report drew no trace control")
	var file := "%s_%dx%d.png" % [file_id, size.x, size.y]
	RenderingServer.force_draw(false)
	var image := stage.get_texture().get_image()
	if image == null:
		_expect(false, "%s: no GPU image" % file)
	elif image.save_png(out.path_join(file)) != OK:
		_expect(false, "%s: png save failed" % file)
	report["file"] = file
	_expect(fixture == before, "%s: presenting mutated the caller fixture" % file_id)
	print("  %s %dx%d -> %s" % [file_id, size.x, size.y, JSON.stringify(report)])
	stage.queue_free()
	await process_frame


func _focus_loadout_candidate(screen: Control) -> void:
	# Candidate actions are lazy: inspect the real backpack cell before measuring
	# or capturing its shared detail pane, just as keyboard navigation does.
	var backpack := screen.find_child("EquipmentBackpack", true, false)
	_expect(backpack != null, "loadout: the equipment backpack is missing")
	if backpack == null:
		return
	backpack.show_item("loot:bow/2")
	var candidate := screen.find_child("BackpackItem_loot_bow_2", true, false) as Button
	_expect(candidate != null, "loadout: the candidate backpack cell is missing")
	if candidate != null:
		candidate.grab_focus()


## Every visible control has to stay inside the logical frame, and no visible text
## may drop below the shared 18px floor.
func _frame_audit(screen: Node, size: Vector2i, label: String) -> Dictionary:
	var region := Rect2(Vector2.ZERO, Vector2(size))
	var outside: Array[String] = []
	var small: Array[String] = []
	for node: Node in screen.find_children("*", "Control", true, false):
		var control := node as Control
		if not control.is_visible_in_tree():
			continue
		# A page scrolls inside its own workspace, so a control that lives inside a
		# ScrollContainer is allowed past the bottom edge; escaping sideways is not,
		# and everything outside a scroll region has to stay in the frame.
		var scrolling := _inside_scroll(control)
		var rect := control.get_global_rect()
		var escaped := rect.position.x < -1.0 or rect.position.x + rect.size.x > size.x + 1.0
		if scrolling:
			escaped = escaped and rect.position.x + rect.size.x > size.x + 1.0
		else:
			escaped = escaped or not region.encloses(rect)
		if escaped and outside.size() < 6:
			outside.append("%s %s" % [control.name, str(control.get_global_rect())])
		if (node is Label or node is Button) and control.get_theme_font_size("font_size") < 18 and small.size() < 6:
			small.append("%s=%d" % [control.name, control.get_theme_font_size("font_size")])
	_expect(outside.is_empty(), "%s: controls outside the logical frame: %s" % [label, str(outside)])
	_expect(small.is_empty(), "%s: text below the 18px floor: %s" % [label, str(small)])
	return {"outside": outside, "small_text": small}


func _inside_scroll(node: Node) -> bool:
	var walker := node.get_parent()
	while walker != null:
		if walker is ScrollContainer:
			return true
		walker = walker.get_parent()
	return false


func _finish() -> void:
	if failures.is_empty():
		print("PASS  test_facility_concept_detail.gd: %s" % out)
		quit(0)
		return
	for failure in failures:
		printerr("- %s" % failure)
	quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _loadout_fixture() -> Dictionary:
	return {
		"ok": true,
		"equipment_slots": ["head", "chest", "pants", "leg_armor", "gloves", "bracers", "belt", "main_hand", "off_hand", "ring_1", "ring_2", "necklace"],
		"prototype_open_slots": ["main_hand", "off_hand", "gloves", "ring_1"],
		"base_items": {
			"ashwood_longbow": {"id": "ashwood_longbow", "name": "Ash Longbow", "slot": "main_hand", "modifiers": [{"parameter": "damage", "operation": "multiply", "value": 1.12}]},
			"swift_recurve_bow": {"id": "swift_recurve_bow", "name": "Swiftstring Recurve", "slot": "main_hand", "modifiers": [{"parameter": "v", "operation": "multiply", "value": 1.1}]},
			"farwatch_quiver": {"id": "farwatch_quiver", "name": "Farwatch Quiver", "slot": "off_hand", "modifiers": [{"parameter": "T", "operation": "multiply", "value": 1.08}]},
			"turnfeather_gloves": {"id": "turnfeather_gloves", "name": "Guiding Fletch Gloves", "slot": "gloves", "modifiers": [{"parameter": "turn", "operation": "multiply", "value": 0.94}]},
			"vitality_ring": {"id": "vitality_ring", "name": "Vitality Ring", "slot": "ring_1", "modifiers": [{"parameter": "max_health", "operation": "multiply", "value": 1.12}]},
		},
		"affix_families": {
			"piercing_continuation": {"id": "piercing_continuation", "name": "Piercing Arrow Continuation Chance", "parameter": "p", "operation": "add", "tiers": [{"tier": 2, "value": 0.07}, {"tier": 3, "value": 0.09}]},
		},
		"inventory_equipment": [
			{"instance_id": "equipped_main", "base_item_id": "ashwood_longbow", "slot": "main_hand", "affixes": [{"family_id": "piercing_continuation", "tier": 2}], "rune_id": "breeding_split", "law_id": "pack_hunt_mark"},
			{"instance_id": "loot:bow/2", "base_item_id": "swift_recurve_bow", "slot": "main_hand", "affixes": [], "rune_id": "", "law_id": ""},
			{"instance_id": "loot:quiver/3", "base_item_id": "farwatch_quiver", "slot": "off_hand", "affixes": [{"family_id": "piercing_continuation", "tier": 3}], "rune_id": "", "law_id": ""},
			{"instance_id": "equipped_gloves", "base_item_id": "turnfeather_gloves", "slot": "gloves", "affixes": [], "rune_id": "", "law_id": ""},
			{"instance_id": "equipped_ring", "base_item_id": "vitality_ring", "slot": "ring_1", "affixes": [], "rune_id": "", "law_id": ""},
		],
		"active_build": {
			"preset_id": "exponential",
			"skills": ["piercing_arrow", "", ""],
			"runes": ["breeding_split"],
			"laws": ["pack_hunt_mark"],
			"equipped_item_ids": {"head": "", "chest": "", "pants": "", "leg_armor": "", "gloves": "equipped_gloves", "bracers": "", "belt": "", "main_hand": "equipped_main", "off_hand": "", "ring_1": "equipped_ring", "ring_2": "", "necklace": ""},
		},
		"resolved_build": {
			"ok": true,
			"final_parameters": {"p": 0.61, "T": 34.0, "v": 682.0, "d": 165.0, "turn": 0.16, "damage": 160.0, "max_health": 112.0},
			"connected_interfaces": ["breedable_event", "branch_target_history"],
			"missing_interfaces": ["lineage_lifetime_pause"],
			"build_fingerprint": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
			"growth_classification": "exponential",
		},
		"equip_previews": {
			"loot:bow/2": {
				"ok": true,
				"final_parameters": {"p": 0.54, "T": 34.0, "v": 750.2, "d": 165.0, "turn": 0.16, "damage": 160.0, "max_health": 112.0},
				"interfaces_gained": ["quick_draw"],
				"interfaces_lost": ["breedable_event"],
				"tags_gained": ["swift"],
				"tags_lost": ["breed"],
			},
		},
		"proxy": {"unlocked": false, "cores": ["near_enemy_horizon", "direct_gait", "single_key_execution", "short_trace_memory"]},
		"progression": {"threshold_colossus_defeated": false, "proxy_unlocked": false, "auto_contract_wins": 0, "early_game_complete": false},
		"training": {"reports_by_fingerprint": {}},
	}


## The same page with one genuinely long raw block, so the folded form is rendered
## and can be looked at next to the short one.
func _long_id_fixture() -> Dictionary:
	var fixture := _loadout_fixture()
	var item: Dictionary = (fixture["inventory_equipment"] as Array)[0]
	item["instance_id"] = LONG_ID
	item["affixes"] = [{"family_id": "piercing_continuation", "tier": 2}, {"family_id": "piercing_continuation", "tier": 3}]
	((fixture["active_build"] as Dictionary)["equipped_item_ids"] as Dictionary)["main_hand"] = LONG_ID
	return fixture


func _training_fixture() -> Dictionary:
	var fixture := _loadout_fixture()
	var fingerprint := String((fixture["resolved_build"] as Dictionary)["build_fingerprint"])
	fixture["training"] = {
		"reports_by_fingerprint": {
			fingerprint: {
				"preset_id": "exponential",
				"build_fingerprint": fingerprint,
				"p": 0.61,
				"R": 1.22,
				"g": 18,
				"event_count": 1000000000000.0,
				"event_count_display": "1000000000000",
				"state": "exponential",
				"training_seed": 42,
				"growth_curve": [
					{"generation": 0, "events_display": "1"},
					{"generation": 6, "events_display": "48"},
					{"generation": 12, "events_display": "4096"},
					{"generation": 18, "events_display": "1000000000000"},
				],
				"action": "Keep forecasting with this build",
			},
		},
	}
	return fixture
