class_name RangerTalentBoard
extends Control
## All fifteen Ranger talents on one non-scrolling, hand-routed board.
##
## The board owns only presentation.  Allocation state comes from authoritative
## node dictionaries and every interaction remains a normal focusable Button.

signal talent_selected(talent_id: String)

const ProgressionIconsScript = preload("res://src/presentation/progression_icons.gd")
const SharedPalette := preload("res://src/presentation/palette.gd")
const UiKit := preload("res://src/presentation/ui_kit.gd")

const SLATE := Color("1b2630")
const SLATE_RAISED := Color("273743")
const SLATE_DEEP := Color("17222b")
const PAPER := Color("c8ab78")
const COPPER_DULL := Color("8e6743")
const COPPER := SharedPalette.COPPER_EDGE
const COPPER_BRIGHT := Color("d7a46b")
const LAW := Color("8fb7b2")
const BONE := SharedPalette.BONE
const NEUTRAL := Color("8a94a1")
const INK := SharedPalette.SLATE_INK
const NODE_SIZE := Vector2(56, 56)
const MEDALLION_RADIUS := 32.0
const ROW_LABEL_WIDTH := 64.0
const ROW_LABEL_GUTTER := 88.0
const GATE_LABEL_WIDTH := 280.0

var _buttons: Array[Button] = []
var _tier_headings: Array[Label] = []
var _gate_labels: Array[Label] = []
var _nodes_by_tier: Dictionary = {}
var _selected_id := ""
var _interactive := true
var _icons = ProgressionIconsScript.new()


func _init() -> void:
	custom_minimum_size = Vector2(680, 420)
	mouse_filter = Control.MOUSE_FILTER_PASS
	_icons.load_icons()
	_build()


func _notification(what: int) -> void:
	if what == Control.NOTIFICATION_RESIZED:
		_layout()


func present(nodes_by_tier: Dictionary, selected_id: String, interactive: bool) -> void:
	_nodes_by_tier = nodes_by_tier.duplicate(true)
	_selected_id = selected_id
	_interactive = interactive
	_sync_buttons()
	_layout()
	queue_redraw()


func node_button(talent_id: String) -> Button:
	for button in _buttons:
		if String(button.get_meta("talent_id", "")) == talent_id:
			return button
	return null


func icons_ready() -> bool:
	return _icons.is_ready()


func icons_pending_reason() -> String:
	return _icons.pending_reason


func set_progression_icons(reader: RefCounted) -> void:
	_icons = reader
	if not _nodes_by_tier.is_empty():
		_sync_buttons()


func _build() -> void:
	for tier in range(3):
		var heading := Label.new()
		heading.name = "TalentTierHeading_%d" % (tier + 1)
		heading.add_theme_font_size_override("font_size", 22)
		heading.add_theme_color_override("font_color", COPPER_BRIGHT)
		heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(heading)
		_tier_headings.append(heading)
		if tier > 0:
			var gate := Label.new()
			gate.name = "TalentTierGate_%d" % (tier + 1)
			gate.add_theme_font_size_override("font_size", 18)
			gate.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			gate.add_theme_color_override("font_color", COPPER_BRIGHT)
			gate.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			gate.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			gate.custom_minimum_size = Vector2(64, 40)
			gate.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(gate)
			_gate_labels.append(gate)
		for slot in range(5):
			var button := Button.new()
			button.name = "TalentSlot_%d_%d" % [tier + 1, slot + 1]
			button.focus_mode = Control.FOCUS_ALL
			button.toggle_mode = true
			button.clip_text = true
			button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			button.add_theme_font_size_override("font_size", 22)
			button.pressed.connect(_on_button_pressed.bind(button))
			add_child(button)
			var mark := Label.new()
			mark.name = "AllocationMark"
			mark.position = Vector2(43, 3)
			mark.add_theme_font_size_override("font_size", 18)
			mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
			button.add_child(mark)
			## The medallion's own text stays empty: names live in a separate
			## two-line lane under the circle, so long titles never clip.
			var name_label := Label.new()
			name_label.name = "TalentName"
			name_label.add_theme_font_size_override("font_size", 18)
			name_label.add_theme_color_override("font_outline_color", INK)
			name_label.add_theme_constant_override("outline_size", 2)
			name_label.add_theme_constant_override("line_spacing", -8)
			name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			button.add_child(name_label)
			_buttons.append(button)


func _sync_buttons() -> void:
	var index := 0
	for tier in range(1, 4):
		var nodes: Array = _nodes_by_tier.get(tier, []) as Array
		for slot in range(5):
			var button := _buttons[index]
			index += 1
			if slot >= nodes.size():
				button.name = "TalentSlot_%d_%d" % [tier, slot + 1]
				button.text = "Empty"
				(button.get_node("TalentName") as Label).text = ""
				button.icon = null
				button.disabled = true
				button.visible = false
				button.set_meta("talent_id", "")
				continue
			var node: Dictionary = nodes[slot]
			var node_id := String(node.get("id", ""))
			button.name = "TalentNode_%s" % node_id
			button.visible = true
			button.set_meta("talent_id", node_id)
			button.text = ""
			(button.get_node("TalentName") as Label).text = String(node.get("name", node_id))
			button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
			button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			button.expand_icon = false
			button.add_theme_constant_override("icon_max_width", 32)
			button.add_theme_constant_override("icon_separation", 0)
			button.icon = _icons.icon("talent.%s" % node_id)
			button.disabled = not _interactive
			button.set_pressed_no_signal(node_id == _selected_id)
			button.tooltip_text = "%s / %s" % [String(node.get("name", node_id)), String(node.get("description", ""))]
			_apply_node_style(button, node, node_id == _selected_id)
			var mark := button.get_node("AllocationMark") as Label
			mark.text = "✓" if bool(node.get("allocated", false)) else ("+" if bool(node.get("can_allocate", false)) else "-")
			mark.add_theme_color_override("font_color", INK if bool(node.get("allocated", false)) else BONE)
		# Row labels deliberately carry no gate copy: the shared gate below is the
		# only place that describes the tier-total rule.
		_tier_headings[tier - 1].text = "%s\n%s" % ["Ⅰ" if tier == 1 else ("Ⅱ" if tier == 2 else "Ⅲ"), "Start" if tier == 1 else ("Hunt" if tier == 2 else "Key")]
		_tier_headings[tier - 1].tooltip_text = "Beginnings" if tier == 1 else ("Deep Hunt" if tier == 2 else "Mastery")
		if tier > 1:
			(_gate_labels[tier - 2] as Label).text = "%d prior pts" % (3 if tier == 2 else 8)
			(_gate_labels[tier - 2] as Label).tooltip_text = "Total points required in previous tiers"


func _layout() -> void:
	var index := 0
	for tier in range(3):
		var heading := _tier_headings[tier]
		heading.position = Vector2(8, _row_y(tier + 1) - 33.0)
		heading.size = Vector2(ROW_LABEL_WIDTH, 66)
		if tier > 0:
			var gate_label := _gate_labels[tier - 1] as Label
			# Thresholds occupy the left gutter between the two row headings.
			var midpoint := (_row_y(tier) + _row_y(tier + 1)) * 0.5
			gate_label.position = Vector2(2, midpoint - 25.0)
			gate_label.size = Vector2(72, 50)
		for slot in range(5):
			var button := _buttons[index]
			index += 1
			var center := node_center(tier + 1, slot)
			button.position = center - NODE_SIZE * 0.5
			button.size = NODE_SIZE
			## Name lane: centered under the medallion, as wide as the slot
			## spacing allows without touching the neighbour's circle.
			var lane := button.get_node("TalentName") as Label
			var lane_width := clampf(usable_slot_spacing() - 8.0, 96.0, 176.0)
			# A dedicated caption below the entire 64px medallion silhouette.
			# A 140px row reserves 66px for three lines, independently of icon size.
			lane.vertical_alignment = VERTICAL_ALIGNMENT_TOP
			lane.position = Vector2((NODE_SIZE.x - lane_width) * 0.5, 62.0)
			lane.size = Vector2(lane_width, 66.0)


func node_center(tier: int, slot: int) -> Vector2:
	# Reserve a real left gutter for the row tag.  Its right edge clears the
	# visible medallion ring, rather than merely the button's rectangular hitbox.
	var x_margin := ROW_LABEL_GUTTER
	var usable_width := maxf(180.0, size.x - x_margin - 16.0)
	var x := x_margin + usable_width * (float(slot) + 0.5) / 5.0
	var y := _row_y(tier)
	return Vector2(x, y)


## Horizontal pitch between slot centres — the width budget a name lane can use
## without reaching into the neighbouring medallion.
func usable_slot_spacing() -> float:
	var x_margin := ROW_LABEL_GUTTER
	return maxf(180.0, size.x - x_margin - 16.0) / 5.0


func _row_y(tier: int) -> float:
	var row_height := size.y / 3.0
	return 38.0 + (row_height - 140.0) * 0.5 + float(tier - 1) * row_height


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), SLATE)

	# Warm work-paper behind the routes, framed by cold stone.
	var paper_margin := Vector2(18, 16)
	var paper_rect := Rect2(paper_margin, size - paper_margin * 2.0)
	draw_rect(paper_rect, Color(0.13, 0.14, 0.12, 0.58))
	draw_rect(paper_rect, Color(PAPER.r, PAPER.g, PAPER.b, 0.20), false, 2.0)

	# Three route bands: broad, faded and slightly uneven.
	for tier in range(3):
		var y := _row_y(tier + 1)
		var band := Rect2(Vector2(24, y - 34), Vector2(size.x - 48, 68))
		draw_rect(band, Color(SLATE_RAISED.r, SLATE_RAISED.g, SLATE_RAISED.b, 0.52 if tier == 1 else 0.38))
		draw_line(Vector2(28, band.position.y), Vector2(size.x - 28, band.position.y), Color(COPPER.r, COPPER.g, COPPER.b, 0.24), 2.0)
		draw_line(Vector2(28, band.end.y), Vector2(size.x - 28, band.end.y), Color(COPPER.r, COPPER.g, COPPER.b, 0.18), 2.0)

	# Tier totals, not adjacent-node prerequisites: every node in a tier feeds a
	# shared collector, then one threshold medallion fans out to the next tier.
	for tier in range(1, 3):
		var target_nodes: Array = _nodes_by_tier.get(tier + 1, []) as Array
		var opened := false
		for node in target_nodes:
			opened = opened or bool((node as Dictionary).get("allocated", false)) or bool((node as Dictionary).get("can_allocate", false))
		_draw_tier_conduit(tier, tier + 1, opened)

	# Engraved rings turn each button's circular hitbox into a visible medallion.
	for button in _buttons:
		if String(button.get_meta("talent_id", "")).is_empty():
			continue
		var center := button.position + button.size * 0.5
		var points := PackedVector2Array()
		for side in range(6):
			var angle := PI / 6.0 + TAU * float(side) / 6.0
			points.append(center + Vector2(cos(angle), sin(angle)) * MEDALLION_RADIUS)
		draw_colored_polygon(points, Color(0, 0, 0, 0))
		draw_polyline(points, Color(PAPER.r, PAPER.g, PAPER.b, 0.20), 2.0)
		draw_arc(center, 30.0, 0.0, TAU, 40, Color(COPPER.r, COPPER.g, COPPER.b, 0.22), 1.0)

	# Law-light pools mark allocated medallions; a copper nail marks locked ones.
	for button in _buttons:
		var talent_id := String(button.get_meta("talent_id", ""))
		if talent_id.is_empty():
			continue
		var node := _find_node(talent_id)
		var center := button.position + button.size * 0.5
		if bool(node.get("allocated", false)):
			for ring in range(4):
				draw_circle(center, 38.0 + ring * 8.0, Color(LAW.r, LAW.g, LAW.b, 0.050 - ring * 0.009))
		elif not bool(node.get("can_allocate", false)):
			draw_circle(center + Vector2(20, 20), 3.0, Color(COPPER.r, COPPER.g, COPPER.b, 0.70))

	# Corner rivets and a warm reading lamp keep the board materially anchored.
	for corner in [Vector2(14, 14), Vector2(size.x - 14, 14), Vector2(14, size.y - 14), Vector2(size.x - 14, size.y - 14)]:
		draw_circle(corner, 4.0, Color(COPPER.r, COPPER.g, COPPER.b, 0.65))
	for ring in range(5):
		draw_circle(Vector2(size.x * 0.90, size.y * 0.10), 35.0 + ring * 28.0, Color(0.92, 0.66, 0.31, 0.025 - ring * 0.003))


func _draw_tier_conduit(from_tier: int, to_tier: int, opened: bool) -> void:
	var collector_y := (_row_y(from_tier) + _row_y(to_tier)) * 0.5
	var gate := Vector2(size.x * 0.5, collector_y)
	var from_first := node_center(from_tier, 0)
	var from_last := node_center(from_tier, 4)
	# Both routes remain traceable in greyscale. Open routes carry a broader,
	# brighter paper/copper stroke; locked routes keep a recessed copper trace.
	var line_color := Color(PAPER.r, PAPER.g, PAPER.b, 0.82 if opened else 0.38)
	var copper_color := Color(COPPER.r, COPPER.g, COPPER.b, 0.78 if opened else 0.32)
	var width := 4.0 if opened else 2.5

	for slot in range(5):
		_draw_curve(node_center(from_tier, slot), Vector2(node_center(from_tier, slot).x, collector_y), line_color, width)
	draw_line(Vector2(from_first.x, collector_y), Vector2(from_last.x, collector_y), copper_color, 4.0 if opened else 3.0)
	# The threshold is written in the gutter; a central badge would cover names.
	for slot in range(5):
		_draw_curve(gate, node_center(to_tier, slot), line_color, width)


func _draw_curve(from: Vector2, to: Vector2, color: Color, width: float) -> void:
	var control_offset := Vector2((to.x - from.x) * 0.12, (to.y - from.y) * 0.30)
	var points := PackedVector2Array()
	for step in range(10):
		var t := float(step) / 9.0
		var direct := from.lerp(to, t)
		points.append(direct + control_offset * sin(PI * t))
	draw_polyline(points, color, width)


func _draw_hex_gate(center: Vector2, opened: bool) -> void:
	var points := PackedVector2Array()
	for side in range(6):
		var angle := TAU * float(side) / 6.0
		points.append(center + Vector2(cos(angle), sin(angle)) * 16.0)
	draw_colored_polygon(points, Color("1c2833") if opened else Color("161f27"))
	draw_polyline(points, COPPER_BRIGHT if opened else Color("8e7352"), 3.0 if opened else 2.0)
	draw_arc(center, 23.0, 0.0, TAU, 24, Color(PAPER.r, PAPER.g, PAPER.b, 0.35 if opened else 0.14), 1.0)


func _apply_node_style(button: Button, node: Dictionary, selected: bool) -> void:
	var allocated := bool(node.get("allocated", false))
	var available := bool(node.get("can_allocate", false))
	var keystone := bool(node.get("keystone", false))
	var fill := SLATE_DEEP
	var border := COPPER_DULL
	var font_color := BONE if allocated or available else Color("9da5ab")
	if allocated:
		fill = COPPER_BRIGHT
		border = BONE
		font_color = INK
	elif available:
		border = COPPER_BRIGHT
	elif keystone:
		border = LAW
	var normal := _node_box(fill, border, 2 if selected else 1)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", _node_box(COPPER_BRIGHT if allocated else Color("31424f"), border, 2))
	button.add_theme_stylebox_override("pressed", _node_box(COPPER_BRIGHT if allocated else Color("243642"), border, 2))
	button.add_theme_stylebox_override("hover_pressed", _node_box(COPPER_BRIGHT if allocated else Color("31424f"), border, 2))
	button.add_theme_stylebox_override("disabled", _node_box(Color("16202a"), Color("2b3742"), 1))
	button.add_theme_stylebox_override("focus", _node_box(Color(0, 0, 0, 0), LAW, 3))
	button.add_theme_color_override("font_color", font_color)
	## Names cross the medallion's lower edge and the slate below it. The ink
	## outline keeps these state colors readable against both backgrounds.
	var lane := button.get_node_or_null("TalentName") as Label
	if lane != null:
		lane.add_theme_color_override("font_color",
			COPPER_BRIGHT if allocated else (BONE if available else NEUTRAL))
	button.add_theme_color_override("font_hover_color", INK if allocated else BONE)
	button.add_theme_color_override("font_pressed_color", INK if allocated else BONE)
	button.add_theme_color_override("font_hover_pressed_color", INK if allocated else BONE)
	button.add_theme_color_override("font_disabled_color", NEUTRAL)


func _node_box(fill: Color, border: Color, width: int) -> StyleBoxFlat:
	return UiKit.flat_style(fill, border, width, 54, Vector4(3.0, 6.0, 3.0, 0.0))


func _find_node(talent_id: String) -> Dictionary:
	for tier in range(1, 4):
		for node in _nodes_by_tier.get(tier, []) as Array:
			if String((node as Dictionary).get("id", "")) == talent_id:
				return node
	return {}




func _on_button_pressed(button: Button) -> void:
	talent_selected.emit(String(button.get_meta("talent_id", "")))
