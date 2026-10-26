extends SceneTree

const CharacterScreenScript = preload("res://src/presentation/character_screen.gd")
const TalentBoardScript = preload("res://src/presentation/ranger_talent_board.gd")
const ApplicationStateScript = preload("res://src/game/application_state.gd")
const ShellThemeScript = preload("res://src/presentation/shell_theme.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	root.size = Vector2i(1280, 720)
	var screen = CharacterScreenScript.new()
	root.add_child(screen)
	await process_frame

	var requested: Array[String] = []
	var refunded: Array[String] = []
	var resets := [0]
	var stances: Array[String] = []
	var closes := [0]
	screen.talent_requested.connect(func(talent_id: String) -> void: requested.append(talent_id))
	screen.talent_refund_requested.connect(func(talent_id: String) -> void: refunded.append(talent_id))
	screen.reset_requested.connect(func() -> void: resets[0] += 1)
	screen.stance_requested.connect(func(stance: String) -> void: stances.append(stance))
	screen.closed.connect(func() -> void: closes[0] += 1)

	screen.present(_snapshot(false, false))
	await process_frame
	_test_keyboard_entry_focus(screen, failures)
	_test_real_talent_names_fit(screen, failures)
	_test_point_count_copy(screen, failures)
	_test_selected_node_and_copy(screen, failures)
	_test_long_detail_dark_paper_contrast(screen, failures)
	_test_locked_screen_never_emits(screen, requested, refunded, resets, failures)
	_test_signals_wait_for_authoritative_present(screen, requested, refunded, resets, stances, failures)
	_test_escape(screen, closes, failures)
	await _test_desktop_bounds_and_readability(screen, failures)

	root.remove_child(screen)
	screen.free()
	if failures.is_empty():
		print("CHARACTER_SCREEN_PASS")
		quit(0)
	else:
		for failure in failures:
			printerr("character screen: %s" % failure)
		quit(1)


func _test_keyboard_entry_focus(screen, failures: Array[String]) -> void:
	## Initial entry seeds focus on the selected talent's button so keyboard
	## navigation starts somewhere meaningful.
	var owner := root.gui_get_focus_owner()
	var selected: Button = screen._talent_board.node_button(screen._selected_talent_id)
	_expect(selected != null and owner == selected,
		"character: initial focus did not land on the selected talent", failures)
	## An ordinary authoritative refresh must not steal focus back.
	var other := screen.find_child("CloseCharacterButton", true, false) as Button
	if other != null:
		other.grab_focus()
		screen.present(_snapshot(false, false))
		_expect(root.gui_get_focus_owner() == other,
			"character: refresh stole keyboard focus", failures)


## The REAL authored names (Continuation Calibration, Final-Generation Reload,
## …) are the ones that clipped — synthetic fixtures hid it. Present the live
## growth snapshot and require every node name fully readable in its lane.
func _test_real_talent_names_fit(screen, failures: Array[String]) -> void:
	var app := ApplicationStateScript.new()
	app.start_new_profile("ranger")
	var live := app.growth_snapshot()
	var trees: Array = live.get("trees", [])
	_expect(not trees.is_empty(), "live growth snapshot has no trees", failures)
	if trees.is_empty():
		return
	## The board presents only the implemented ranger tree; the live snapshot
	## also carries future class trees that are intentionally not rendered.
	var real_names := {}
	for tree_value in trees:
		var tree: Dictionary = tree_value
		if String(tree.get("id", "")) != "ranger":
			continue
		for node_value in tree.get("nodes", []):
			real_names[String((node_value as Dictionary).id)] = String((node_value as Dictionary).get("name", ""))
	screen.present(live)
	var board := screen.find_child("RangerTalentBoard", true, false) as Control
	var checked := 0
	for node_id: String in real_names:
		var button := screen.find_child("TalentNode_" + node_id, true, false) as Button
		var lane := button.get_node_or_null("TalentName") as Label if button != null else null
		if lane == null:
			_expect(false, "live node %s lost its name lane" % node_id, failures)
			continue
		checked += 1
		_expect(lane.text == real_names[node_id],
			"live node %s lane shows '%s' not '%s'" % [node_id, lane.text, real_names[node_id]], failures)
		_expect(lane.get_visible_line_count() == lane.get_line_count() and lane.get_line_count() <= 3,
			"live node %s name wraps past its lane: '%s'" % [node_id, lane.text], failures)
		var lane_rect := lane.get_global_rect()
		_expect(board != null and board.get_global_rect().encloses(lane_rect),
			"live node %s lane escaped the board: %s" % [node_id, str(lane_rect)], failures)
		for other: Button in _talent_nodes(screen):
			var center := other.get_global_rect().get_center()
			var radius := Vector2.ONE * TalentBoardScript.MEDALLION_RADIUS
			_expect(not lane_rect.intersects(Rect2(center - radius, radius * 2.0)),
				"live name %s overlaps drawn medallion %s" % [node_id, other.name], failures)
	_expect(checked == 15, "live board checked %d of 15 authored names" % checked, failures)
	screen.present(_snapshot(false, false))


func _test_point_count_copy(screen, failures: Array[String]) -> void:
	var snapshot := _snapshot(false, false)
	var points := screen.get("_points_label") as Label
	for count in [0, 1, 2]:
		snapshot["points_available"] = count
		screen.present(snapshot)
		_expect(points != null and points.text == "%d %s" % [count, "point" if count == 1 else "points"],
			"available talent points lost their spacing or singular/plural form", failures)
	screen.present(_snapshot(false, false))


func _test_selected_node_and_copy(screen, failures: Array[String]) -> void:
	var board: Control = screen.find_child("RangerTalentBoard", true, false) as Control
	var nodes := _talent_nodes(screen)
	_expect(board != null and nodes.size() == 15, "growth structure did not keep all fifteen Ranger nodes inspectable", failures)
	var selected: Button = screen.find_child("TalentNode_aim", true, false) as Button
	_expect(selected != null and not selected.disabled, "available central node was not selectable", failures)
	selected.emit_signal("pressed")
	var title: Label = screen.find_child("SelectedTalentName", true, false) as Label
	var description: Label = screen.find_child("SelectedTalentDescription", true, false) as Label
	_expect(title != null and title.text == "Steady Aim", "central click did not select the node for the fixed detail panel", failures)
	_expect(description != null and description.autowrap_mode != TextServer.AUTOWRAP_OFF and "standing still" in description.text, "long node description did not remain readable wrapped copy", failures)
	var stance_gate: Label = screen.find_child("StanceGateLabel", true, false) as Label
	var stance_row: HBoxContainer = screen.find_child("StanceRow", true, false) as HBoxContainer
	_expect(stance_gate != null and stance_gate.visible and stance_row != null and not stance_row.visible, "stance controls appeared before their key talent snapshot flag", failures)


func _test_locked_screen_never_emits(screen, requested: Array[String], refunded: Array[String], resets: Array, failures: Array[String]) -> void:
	screen.present(_snapshot(true, false))
	var locked_node: Button = screen.find_child("TalentNode_trail", true, false) as Button
	var allocate: Button = screen.find_child("AllocateTalentButton", true, false) as Button
	var refund: Button = screen.find_child("RefundTalentButton", true, false) as Button
	var reset: Button = screen.find_child("ResetTalentsButton", true, false) as Button
	_expect(locked_node != null and not locked_node.disabled and allocate.disabled and refund.disabled and reset.disabled, "locked snapshot must allow inspection but reject growth actions", failures)
	locked_node.emit_signal("pressed")
	allocate.emit_signal("pressed")
	refund.emit_signal("pressed")
	reset.emit_signal("pressed")
	_expect(requested.is_empty() and refunded.is_empty() and resets[0] == 0, "locked controls emitted a domain request", failures)


func _test_signals_wait_for_authoritative_present(screen, requested: Array[String], refunded: Array[String], resets: Array, stances: Array[String], failures: Array[String]) -> void:
	screen.present(_snapshot(false, false))
	var aim: Button = screen.find_child("TalentNode_aim", true, false) as Button
	aim.emit_signal("pressed")
	var allocate: Button = screen.find_child("AllocateTalentButton", true, false) as Button
	allocate.emit_signal("pressed")
	_expect(requested == ["aim"], "allocate did not emit exactly the selected talent id", failures)
	_expect(allocate.disabled and "waiting for the character profile to update" in (screen.find_child("CharacterStatus", true, false) as Label).text, "allocate press invented an immediate success state", failures)

	screen.present(_snapshot(false, true))
	var refund: Button = screen.find_child("RefundTalentButton", true, false) as Button
	refund.emit_signal("pressed")
	_expect(refunded == ["aim"], "refund did not emit the allocated selected talent id", failures)

	screen.present(_snapshot(false, false))
	var reset: Button = screen.find_child("ResetTalentsButton", true, false) as Button
	reset.emit_signal("pressed")
	_expect(resets[0] == 1, "free reset did not emit its explicit request", failures)

	screen.present(_snapshot(false, false, true))
	var far: Button = screen.find_child("Stance_far", true, false) as Button
	_expect(far != null and far.visible and not far.disabled, "stance controls did not appear after the authoritative key-talent flag", failures)
	far.emit_signal("pressed")
	_expect(stances == ["far"], "stance selection did not emit the requested stance", failures)


func _test_escape(screen, closes: Array, failures: Array[String]) -> void:
	var event := InputEventKey.new()
	event.pressed = true
	event.keycode = KEY_ESCAPE
	screen._unhandled_key_input(event)
	_expect(closes[0] == 1, "Esc did not emit closed", failures)


func _test_desktop_bounds_and_readability(screen, failures: Array[String]) -> void:
	for size in [Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1600, 900), Vector2i(1600, 1000), Vector2i(1920, 1080)]:
		root.size = size
		await process_frame
		var workspace: Control = screen.find_child("CharacterWorkspace", true, false) as Control
		var tree: Control = screen.find_child("TalentTreePanel", true, false) as Control
		var board: Control = screen.find_child("RangerTalentBoard", true, false) as Control
		var detail: Control = screen.find_child("TalentDetailPanel", true, false) as Control
		var board_title := _talent_board_title(screen)
		_expect(workspace != null and workspace.get_global_rect().size.y > 250.0, "%s workspace lost its desktop height" % size, failures)
		_expect(tree != null and detail != null and tree.get_global_rect().end.x <= detail.get_global_rect().position.x + 1.0, "%s tree and fixed detail pane overlap" % size, failures)
		_expect(detail != null and detail.get_global_rect().end.x <= float(size.x - CharacterScreenScript.PAGE_MARGIN + 1), "%s detail pane left the viewport" % size, failures)
		var node_buttons := _talent_nodes(screen)
		var node_button: Button = screen.find_child("TalentNode_trail", true, false) as Button
		var detail_copy: Label = screen.find_child("SelectedTalentDescription", true, false) as Label
		_expect(node_button != null, "%s talent node is missing" % size, failures)
		_expect(detail_copy != null and detail_copy.get_theme_font_size("font_size") >= ShellThemeScript.BODY_FONT_SIZE, "%s detail copy dropped below 22px body readability" % size, failures)
		for node in node_buttons:
			var rect := (node as Control).get_global_rect()
			_expect(tree != null and rect.position.x >= tree.get_global_rect().position.x and rect.end.x <= tree.get_global_rect().end.x + 1.0, "%s talent node escaped the board" % size, failures)
			_expect(board != null and board.get_global_rect().encloses(rect.grow(10.0)), "%s visible talent medallion escaped RangerTalentBoard and can collide with its title or edge" % size, failures)
			_expect(board_title != null and not board_title.get_global_rect().intersects(rect.grow(10.0)), "%s talent medallion overlaps the external board title" % size, failures)
			for other in node_buttons:
				if other == node:
					continue
				_expect(not rect.intersects((other as Control).get_global_rect()), "%s talent nodes overlap" % size, failures)
			var lane := (node as Control).get_node_or_null("TalentName") as Label
			_expect(lane != null, "%s lost its TalentName lane" % size, failures)
			if lane != null:
				_expect(not lane.text.is_empty() and not lane.text.contains("…"),
					"%s talent name clipped: '%s'" % [size, lane.text], failures)
				_expect(lane.get_theme_font_size("font_size") >= 18,
					"%s talent name fell below the 18px floor" % size, failures)
				_expect(lane.get_visible_line_count() == lane.get_line_count() and lane.get_line_count() <= 3,
					"%s talent name wraps past its visible lane: '%s'" % [size, lane.text], failures)
				var lane_rect := lane.get_global_rect()
				_expect(board != null and board.get_global_rect().encloses(lane_rect),
					"%s name lane escaped RangerTalentBoard: %s" % [size, str(lane_rect)], failures)
				for other in node_buttons:
					if other == node:
						continue
					_expect(not lane_rect.intersects((other as Control).get_global_rect()),
						"%s name lane of %s overlaps medallion %s" % [size, node.name, (other as Control).name], failures)
		_test_talent_board_annotations(screen, node_buttons, size, failures)
		var viewport := Rect2(Vector2.ZERO, Vector2(size))
		for node in screen.find_children("*", "Control", true, false):
			if node.is_visible_in_tree():
				var rect := (node as Control).get_global_rect()
				_expect(viewport.encloses(rect), "%s visible control %s escaped the viewport after selecting the longest detail: %s" % [size, node.name, rect], failures)


func _test_talent_board_annotations(screen: Control, node_buttons: Array[Button], resolution: Vector2i, failures: Array[String]) -> void:
	var expected_headings := ["Ⅰ\nStart", "Ⅱ\nHunt", "Ⅲ\nKey"]
	var expected_gates := ["3 prior pts", "8 prior pts"]
	var annotations: Array[Control] = []
	for tier in range(3):
		var heading: Label = screen.find_child("TalentTierHeading_%d" % (tier + 1), true, false) as Label
		_expect(heading != null and heading.text == expected_headings[tier], "%s tier %d did not remain a compact row marker" % [resolution, tier + 1], failures)
		if heading != null:
			annotations.append(heading)
	for gate_index in range(2):
		var gate: Label = screen.find_child("TalentTierGate_%d" % (gate_index + 2), true, false) as Label
		_expect(gate != null and gate.text == expected_gates[gate_index], "%s shared tier-total gate %d lost its rule" % [resolution, gate_index + 2], failures)
		if gate != null:
			annotations.append(gate)
	for annotation in annotations:
		var annotation_rect := annotation.get_global_rect()
		for node in node_buttons:
			_expect(not annotation_rect.intersects(node.get_global_rect().grow(10.0)), "%s annotation %s overlaps the visible medallion of %s" % [resolution, annotation.name, node.name], failures)


func _talent_board_title(screen: Control) -> Label:
	for label in screen.find_children("*", "Label", true, false):
		if label is Label and (label as Label).text == "Hunting · Three-Tier Hunting Paths":
			return label as Label
	return null


func _test_long_detail_dark_paper_contrast(screen, failures: Array[String]) -> void:
	var longest: Button = screen.find_child("TalentNode_lure", true, false) as Button
	longest.emit_signal("pressed")
	var title: Label = screen.find_child("SelectedTalentName", true, false) as Label
	var description: Label = screen.find_child("SelectedTalentDescription", true, false) as Label
	var state: Label = screen.find_child("SelectedTalentState", true, false) as Label
	_expect(title.get_theme_font_size("font_size") >= ShellThemeScript.BODY_FONT_SIZE and description.get_theme_font_size("font_size") >= ShellThemeScript.BODY_FONT_SIZE and state.get_theme_font_size("font_size") >= ShellThemeScript.BODY_FONT_SIZE, "dark paper detail dropped below 22px readability", failures)
	_expect(_contrast_ratio(title.get_theme_color("font_color"), Color("292b27")) >= 4.5 and _contrast_ratio(description.get_theme_color("font_color"), Color("292b27")) >= 7.0 and _contrast_ratio(state.get_theme_color("font_color"), Color("292b27")) >= 7.0, "dark paper detail copy no longer meets title/body contrast", failures)


func _snapshot(locked: bool, aim_allocated: bool, stance_available: bool = false) -> Dictionary:
	return {
		"level": 8,
		"max_level": 50,
		"experience": 84,
		"level_experience": 84,
		"next_level_experience": 120,
		"points_earned": 7,
		"points_spent": 2 if aim_allocated else 1,
		"points_available": 5 if aim_allocated else 6,
		"locked": locked,
		"stance": "mid",
		"stance_available": stance_available,
		"unlocked_classes": ["ranger"],
		"trees": [{
			"id": "ranger", "name": "Hunting", "available": true,
			"nodes": [
				_node("trail", "Tracking", 1, false, "Follow the traces left by your prey.", true, false),
				_node("mark", "Hunting Mark", 1, false, "Mark the current prey.", false, true),
				_node("step", "Light Step", 1, false, "Avoid unnecessary conflicts.", false, false, "Requires a prerequisite talent"),
				_node("camp", "Make Camp", 1, false, "Recover your readiness at the campfire.", false, false, "Requires a prerequisite talent"),
				_node("watch", "Watch", 1, false, "Observe changes in the hunting grounds.", false, false, "Requires a prerequisite talent"),
				_node("aim", "Steady Aim", 2, false, "Steady your breathing while standing still, making the next arrow more likely to strike a weak point.", aim_allocated, not aim_allocated),
				_node("hook", "Grapple", 2, false, "Quickly reposition across terrain.", false, false, "Requires a prerequisite talent"),
				_node("cover", "Cover", 2, false, "Use cover to maintain a safe distance.", false, false, "Requires a prerequisite talent"),
				_node("echo", "Echo", 2, false, "Record echoes of the prey's movement.", false, false, "Requires a prerequisite talent"),
				_node("wind", "Listen to the Wind", 2, false, "Read the wind to detect approaching enemies.", false, false, "Requires a prerequisite talent"),
				_node("near_key", "Close Hunt Mastery", 3, true, "Unlock the close-range stance.", false, false, "Requires a tier-two keystone"),
				_node("mid_key", "Midrange Mastery", 3, true, "Unlock the midrange stance.", false, false, "Requires a tier-two keystone"),
				_node("far_key", "Far Hunt Mastery", 3, true, "Unlock the long-range stance.", false, false, "Requires a tier-two keystone"),
					_node("lure", "Lure", 3, false, "After all three slots succeed in order, the next Piercing Arrow's windup drops from 5 to 4 ticks (-20%). Sequence: actual Piercing Arrow hit -> successful Hunter's Mark -> successful Dash. Consumes the one-use speedup when the next arrow is accepted. A miss, barrier block, interrupted action, or encounter re-entry clears the sequence. Requires 8 total points in tiers 1+2 of this tree.", false, false, "Requires a keystone"),
				_node("endure", "Endurance", 3, false, "Extend your hunting endurance.", false, false, "Requires a keystone"),
			],
		}],
	}


func _node(id: String, name: String, tier: int, keystone: bool, description: String, allocated: bool, can_allocate: bool, lock_reason: String = "") -> Dictionary:
	return {"id": id, "name": name, "tier": tier, "keystone": keystone, "description": description, "allocated": allocated, "can_allocate": can_allocate, "lock_reason": lock_reason}


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)


func _contrast_ratio(a: Color, b: Color) -> float:
	var la := _relative_luminance(a)
	var lb := _relative_luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


func _relative_luminance(color: Color) -> float:
	var r := _linear_channel(color.r)
	var g := _linear_channel(color.g)
	var b := _linear_channel(color.b)
	return 0.2126 * r + 0.7152 * g + 0.0722 * b


func _linear_channel(value: float) -> float:
	return value / 12.92 if value <= 0.04045 else pow((value + 0.055) / 1.055, 2.4)


func _talent_nodes(screen: Node) -> Array[Button]:
	var values: Array[Button] = []
	_collect_talent_nodes(screen, values)
	return values


func _collect_talent_nodes(node: Node, output: Array[Button]) -> void:
	for child in node.get_children():
		if child is Button and child.name.begins_with("TalentNode_"):
			output.append(child)
		_collect_talent_nodes(child, output)
