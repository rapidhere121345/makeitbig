extends SceneTree
## Directed R14 regression: real profile authority + persistent CharacterScreen.
## XP is a labelled fixture; every allocation/refund/reset uses change_talent.
## Headless checks cannot approve GPU contrast or pointer/scroll behaviour.

const Character = preload("res://src/presentation/character_screen.gd")
const Board = preload("res://src/presentation/ranger_talent_board.gd")
const Facility = preload("res://src/presentation/facility_screen.gd")
const Authority = preload("res://src/game/application_state.gd")
const Progression = preload("res://src/systems/character_progression.gd")
const ShellSkin = preload("res://src/presentation/shell_theme.gd")
const Items = preload("res://src/content/early_item_registry.gd")
const INVESTMENTS := [
	"ranger_steady_string", "ranger_long_breath", "ranger_keen_eye",
	"ranger_light_step", "ranger_recovery_pose", "ranger_close_turn",
	"ranger_continuation_calibration", "ranger_defocused_tracking",
]

var failures: Array[String] = []
var check_count := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1280, 720)
	root.gui_embed_subwindows = true
	var state = Authority.new()
	_expect(bool(state.start_new_profile("ranger").ok), "real profile created")
	_expect(bool(state.complete_tutorial().ok), "public tutorial fixture accepted")
	var payload: Dictionary = state.persistent_payload("base")
	payload.profile.character.experience = Progression.threshold(12)
	_expect(bool(state.restore_persistent_payload(payload).ok), "XP-only fixture validated by authority")
	print("FIXTURE: level-12 XP via serialized public restore; no injected talents, wins or equipment")
	var screen = Character.new()
	root.add_child(screen)
	await _settle()
	screen.present(state.growth_snapshot())
	await _settle()
	var first := screen.find_child("TalentNode_" + INVESTMENTS[0], true, false) as Button
	_expect(first != null, "production first node exists")
	if first == null:
		_finish()
		return
	first.pressed.emit()
	_check_board(screen, state, 0, [false, false])
	# Local request must never invent allocation, and the board must reflect the
	# pending request even while the same valid node remains selected.
	var requests: Array[String] = []
	screen.talent_requested.connect(func(id: String): requests.append(id))
	var original_profile: Dictionary = state.profile
	(screen.find_child("AllocateTalentButton", true, false) as Button).pressed.emit()
	_expect(requests == [INVESTMENTS[0]], "selected allocation emits exactly one domain request")
	_expect(state.profile == original_profile, "unanswered UI request never changes profile")
	for node in screen.find_children("TalentNode_*", "Button", true, false):
		_expect((node as Button).disabled, "pending request reaches board button " + String(node.name))
	screen.present(state.growth_snapshot())
	_check_board(screen, state, 0, [false, false])

	# Keep the original selection throughout all authority updates. This is the
	# exact branch that used to skip board.present at both tier thresholds.
	for index in INVESTMENTS.size():
		var receipt: Dictionary = state.change_talent("allocate", INVESTMENTS[index])
		_expect(bool(receipt.get("ok", false)), "authority accepts investment " + INVESTMENTS[index])
		screen.present(state.growth_snapshot())
		await _settle()
		var spent := index + 1
		_check_board(screen, state, spent, [spent >= 3, spent >= 8])
		if spent in [3, 8]:
			print("GATE_OPEN: spent=%d selection=%s" % [spent, INVESTMENTS[0]])

	# Reverse refunds are legal under the production prerequisites. 8→7 closes
	# the third tier, and 3→2 closes the second, without replacing the selection.
	for index in range(INVESTMENTS.size() - 1, 0, -1):
		var receipt: Dictionary = state.change_talent("refund", INVESTMENTS[index])
		_expect(bool(receipt.get("ok", false)), "authority accepts refund " + INVESTMENTS[index])
		screen.present(state.growth_snapshot())
		await _settle()
		_check_board(screen, state, index, [index >= 3, index >= 8])
		if index in [7, 2]: print("GATE_WITHDRAW: spent=%d" % index)
	_expect(bool(state.change_talent("reset").ok), "public reset accepted")
	screen.present(state.growth_snapshot())
	_check_board(screen, state, 0, [false, false])
	root.remove_child(screen)
	screen.free()
	await _check_skill_and_edges(state)
	_finish()

func _check_board(screen: Control, state: RefCounted, spent: int, expected_gates: Array) -> void:
	var board: Control = screen.find_child("RangerTalentBoard", true, false) as Control
	_expect(board != null, "real board exists")
	if board == null: return
	var snapshot: Dictionary = state.growth_snapshot()
	_expect(int(snapshot.points_spent) == spent, "authoritative spent total %d" % spent)
	_expect(String(screen.get("_selected_talent_id")) == INVESTMENTS[0]
		and String(board.get("_selected_id")) == INVESTMENTS[0], "selection retained in detail and board at %d" % spent)
	var rendered: Dictionary = board.get("_nodes_by_tier")
	var rendered_count := 0
	for tree: Dictionary in snapshot.trees:
		if String(tree.id) != "ranger": continue
		for node: Dictionary in tree.nodes:
			var actual: Dictionary = {}
			for candidate: Dictionary in rendered.get(int(node.tier), []):
				if String(candidate.id) == String(node.id): actual = candidate
			_expect(actual == node, "rendered production state equals authority for %s at %d" % [node.id, spent])
			rendered_count += 1
			var button := board.call("node_button", String(node.id)) as Button
			_expect(button != null and not button.disabled, "inspection restored after present for " + String(node.id))
			if button != null:
				_expect(button.button_pressed == (String(node.id) == INVESTMENTS[0]), "visible selected button follows retained selection " + String(node.id))
	_expect(rendered_count == 15, "all fifteen production talents retained")
	var drawn_gates: Array[bool] = []
	for tier in [2, 3]:
		var opened := false
		for node: Dictionary in rendered.get(tier, []):
			opened = opened or bool(node.allocated) or bool(node.can_allocate)
		drawn_gates.append(opened)
	_expect(drawn_gates == expected_gates, "board conduit gates at %d: %s expected %s" % [spent, drawn_gates, expected_gates])
	var selected := board.call("node_button", INVESTMENTS[0]) as Button
	var refund := screen.find_child("RefundTalentButton", true, false) as Button
	_expect(refund.disabled == (spent == 0), "selected refund availability follows authoritative withdrawal")
	var first_fill := (selected.get_theme_stylebox("normal") as StyleBoxFlat).bg_color
	_expect(first_fill == (Board.COPPER_BRIGHT if spent > 0 else Board.SLATE_DEEP), "visible allocation fill follows authority")

func _check_skill_and_edges(state: RefCounted) -> void:
	var screen = Facility.new()
	root.add_child(screen)
	await _settle()
	# Only the skill catalogue fixture is widened; registry text remains real.
	var data: Dictionary = state.early_game_snapshot()
	var items = Items.new()
	_expect(items.load_all().is_empty(), "real equipment registry loaded")
	data.equipment_slots = Items.EQUIPMENT_SLOTS.duplicate()
	data.prototype_open_slots = Items.PROTOTYPE_OPEN_SLOTS.duplicate()
	data.inventory_equipment = state.profile.inventory.equipment.duplicate(true)
	data.base_items = items.base_items.duplicate(true)
	data.affix_families = items.affix_families.duplicate(true)
	data.resolved_build = state.resolved_build_snapshot()
	data.active_build.skills = ["piercing_arrow", "hunter_mark", "dash"]
	print("PRESENTATION_FIXTURE: production loadout fields + four skill catalogue entries; no profile unlock or selection changed")
	screen.present("loadout", state.profile, {}, "", data)
	await _settle()
	var before_profile: Dictionary = state.profile
	for id: String in ["piercing_arrow", "hunter_mark", "dash", "basic_dodge"]:
		var opener := screen.find_child("SkillSummary_" + id, true, false) as Button
		_expect(opener != null and not opener.disabled, "production skill opener " + id)
		if opener == null: continue
		opener.pressed.emit()
		await _settle()
		var dialog := screen.find_child("SkillDetailDialog", true, false) as AcceptDialog
		var label := dialog.find_child("SkillDetailText", true, false) as Label
		var scroll := dialog.find_child("SkillDetailScroll", true, false) as ScrollContainer
		var canonical: String = screen.call("_player_readable_skill_text", id)
		var paragraphs := canonical
		for heading: String in ["目标规则：", "完整效果：", "冷却：", "联动：", "限制："]:
			paragraphs = paragraphs.replace("\n" + heading, "\n\n" + heading)
		_expect(label.text == paragraphs and not canonical.is_empty(), "all production characters retained with only semantic blank lines " + id)
		_expect(label.get_theme_font_size("font_size") == 22, "core skill text is 22px " + id)
		_expect(label.size.y >= label.get_minimum_size().y - 1, "complete wrapped text receives its required height " + id)
		_expect(label.size.x <= scroll.size.x + 1, "no horizontal text overflow " + id)
		_expect(dialog.get_ok_button().is_visible_in_tree() and dialog.get_ok_button().get_global_rect().position.y >= scroll.get_global_rect().end.y,
			"fixed close button stays below the scroll viewport " + id)
		_expect(screen.find_child("SkillDetailReadingSurface", true, false) != null, "local quiet reading surface exists")
		dialog.get_ok_button().pressed.emit()
		await _settle()
		_expect(not dialog.visible, "close action dismisses skill " + id)
	_expect(state.profile == before_profile, "detail inspection preserves production profile")
	# Pixel checks here prove that ONLY nine-slice edges change. They do not
	# approve GPU hierarchy, which remains the subsequent after run's job.
	var original := ShellSkin.panel_style("well")
	var recessed: StyleBoxTexture = screen.call("_recessed_panel_style", "well")
	var a := original.texture.get_image()
	var b := recessed.texture.get_image()
	if a.is_compressed(): a.decompress()
	if b.is_compressed(): b.decompress()
	_expect(a.get_size() == b.get_size(), "authored panel dimensions retained")
	var centers_equal := true
	var edge_darker := false
	for y in a.get_height():
		for x in a.get_width():
			if x >= 12 and y >= 12 and x < a.get_width() - 12 and y < a.get_height() - 12:
				centers_equal = centers_equal and a.get_pixel(x, y) == b.get_pixel(x, y)
			else:
				edge_darker = edge_darker or b.get_pixel(x, y).get_luminance() < a.get_pixel(x, y).get_luminance()
	print("MATERIAL_CHECK: centers_equal=%s edge_darker=%s image_formats=%s/%s" % [centers_equal, edge_darker, a.get_format(), b.get_format()])
	_expect(centers_equal and edge_darker, "only ordinary border pixels recessed, center material unchanged")
	var selected: StyleBoxTexture = screen.call("_slot_cell_box", true, false)
	_expect(selected.texture == ShellSkin.panel_style("selected").texture, "selected bright copper skin preserved")
	var reason := screen.find_child("ClosedSlotReason", true, false) as Label
	_expect(reason != null and reason.get_theme_font_size("font_size") >= 18, "locked reason retains 18px minimum")
	_expect(screen.find_child("SlotFocus_head", true, false) == null, "locked slot remains an inspection-only slot")
	root.remove_child(screen)
	screen.free()

func _settle() -> void:
	for _frame in range(6): await process_frame

func _expect(condition: bool, message: String) -> void:
	check_count += 1
	if not condition: failures.append(message)

func _finish() -> void:
	print("R14_DIRECTED_CHECKS: %d; failures: %d" % [check_count, failures.size()])
	for failure in failures: printerr("R14: " + failure)
	if failures.is_empty(): print("R14_TALENT_BOARD_REFRESH_PASS")
	quit(0 if failures.is_empty() else 1)
