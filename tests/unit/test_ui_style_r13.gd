extends SceneTree
## Real asset binding, identity preservation, contrast, cache and layout contract.
const Shell = preload("res://src/presentation/shell_theme.gd")
const GridIcon = preload("res://src/presentation/pixel_grid_icon.gd")
const Progression = preload("res://src/presentation/progression_icons.gd")
const Skills = preload("res://src/presentation/combat_skill_icons.gd")
const Assert := preload("res://tests/helpers/assert.gd")
const ICON_SHEET_DIRECTORY := "res://art/production/p1/ui_style_r13"
var errors: Array[String] = []
var preserved := 0
var contrasts: Dictionary = {}

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var theme := Shell.create()
	_expect(theme.default_font == Shell.data_font(), "packaged Chinese face")
	_expect(theme.get_font("font", "Button") == Shell.data_font()
		and theme.get_font("font", "DataLabel") == Shell.data_font(), "controls and values use the bundled medium sans face")
	_check_font_coverage()
	_expect(theme.default_font_size == 22 and Shell.MIN_FONT_SIZE == 18, "22/18 reading contract")
	_expect(Shell.WARNING == Color("d95149") and Shell.PROXY == Color("41b7ae")
		and Shell.ANOMALY == Color("7450a6"), "semantic colours retained")
	for kind in ["panel", "button", "well", "paper", "hover", "selected", "disabled"]:
		var first := Shell.panel_style(kind)
		var second := Shell.panel_style(kind)
		_expect(first != second and first is StyleBoxFlat, kind + " flat styles with independent margins")
		_expect(first.content_margin_left == 16 and first.content_margin_right == 16
			and first.content_margin_top == 12 and first.content_margin_bottom == 12, kind + " stable layout margins")
		first.content_margin_top = 3
		_expect(second.content_margin_top == 12, "caller override stays local")
		_expect(second.border_width_left == 0 and second.border_width_top == 0
			and second.border_width_right == 0, kind + " no enclosing decorative frame")
		if kind in ["button", "hover", "selected", "disabled"]:
			_expect(second.bg_color.r >= second.bg_color.g and second.bg_color.g >= second.bg_color.b
				and second.bg_color.a < 1.0, kind + " smoked warm surface instead of opaque blue blocks")
		var surface: Color = second.bg_color if second.bg_color.a > 0.0 else Shell.INK
		var body := (_luma(Shell.BONE)+0.05)/(_luma(surface)+0.05)
		var auxiliary := (_luma(Shell.NEUTRAL)+0.05)/(_luma(surface)+0.05)
		contrasts[kind] = {"body_min":body,"auxiliary_min":auxiliary}
		_expect(body >= 7.0 and auxiliary >= 4.5, kind + " reading contrast")
	_expect(Shell.section_style().bg_color.a == 0.0, "layout sections remain transparent")
	var action := Button.new()
	action.theme = theme
	root.add_child(action)
	Shell.apply_primary_button(action)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var style := action.get_theme_stylebox(state) as StyleBoxTexture
		_expect(style != null and style.texture != null, state + " engraved action material resolves")
		if style != null:
			_expect(style.content_margin_left == 16 and style.content_margin_right == 16
				and style.content_margin_top == 12 and style.content_margin_bottom == 12,
				state + " decoration preserves action layout")
			_expect(style.texture.get_height() <= 64, "button artwork has no excessive transparent padding")
	_expect(action.get_theme_stylebox("focus") == theme.get_stylebox("focus", "Button"),
		"material leaves keyboard focus intact")
	action.free()
	var focus := theme.get_stylebox("focus", "Button") as StyleBoxFlat
	_expect(focus != null and focus.border_width_left >= 2 and focus.bg_color.a == 0.0,
		"keyboard focus remains visible without obscuring the control")
	_expect(theme.get_stylebox("panel", "PopupPanel").bg_color.a == 1.0,
		"popup reading surface remains opaque")
	_preserve("res://art/production/p1/early_loop_v01/skills_actions.png", "skills_actions.png")
	_preserve("res://art/production/p1/icon_expansion_v01/ranger_talents.png", "ranger_talents.png")
	_preserve("res://art/production/p1/icon_expansion_v01/law_tokens.png", "law_tokens.png")
	var skills := Skills.new()
	var progression := Progression.new()
	_expect(skills.load_icons() and progression.load_icons(), "production readers resolve framed atlases")
	for id in Skills.SLOT_ICON_IDS:
		var texture := skills.icon(id)
		_expect(texture is AtlasTexture and texture.get_size() == Vector2(32,32)
			and texture == skills.icon(id), id + " atlas cell cached")
	for id in ["talent.ranger_steady_string", "law_token.inscribe", "law_token.rewrite", "law_token.refine"]:
		_expect(progression.icon(id) != null and progression.icon(id) == progression.icon(id), id + " progression cell cached")
	var host := Control.new()
	root.add_child(host)
	var icon := GridIcon.new()
	icon.texture = skills.icon("piercing_arrow")
	icon.custom_minimum_size = Vector2(64,64)
	icon.size = Vector2(64,64)
	host.add_child(icon)
	await process_frame
	_expect(icon.get_node_or_null("HearthsideIconWell") == null,
		"icons do not add a redundant ornamental box")
	_expect(icon.get_combined_minimum_size() == Vector2(64,64), "unframed icon retains layout size")
	var backdrop := Shell.add_backdrop(host)
	await process_frame
	_expect(backdrop.mouse_filter == Control.MOUSE_FILTER_IGNORE and not backdrop.is_processing(), "backdrop inert")
	host.free()
	print("UI_STYLE_R13 ", "pass" if errors.is_empty() else "fail", " preserved=",preserved," contrasts=", JSON.stringify(contrasts)," errors=",errors)
	quit(0 if errors.is_empty() else 1)

func _preserve(old_path: String, name: String) -> void:
	var before := Image.new()
	var after := Image.new()
	_expect(before.load_png_from_buffer(FileAccess.get_file_as_bytes(old_path)) == OK, "original " + name)
	_expect(after.load_png_from_buffer(FileAccess.get_file_as_bytes(ICON_SHEET_DIRECTORY.path_join(name))) == OK, "framed " + name)
	_expect(before.get_size() == after.get_size(), name + " atlas dimensions")
	var backing_pixels := 0
	for y in before.get_height():
		for x in before.get_width():
			var original := before.get_pixel(x,y)
			var actual := after.get_pixel(x,y)
			if original.a == 1.0:
				_expect(original == actual, name + " opaque identity pixel")
				preserved += 1
			elif original.a == 0.0 and actual.a == 1.0:
				backing_pixels += 1
	_expect(backing_pixels > 100, name + " real material now connected")

func _luma(color: Color) -> float:
	var c := color.srgb_to_linear()
	return c.r*0.2126+c.g*0.7152+c.b*0.0722

func _expect(ok: bool, message: String) -> void: Assert.expect(ok, message, errors)


func _check_font_coverage() -> void:
	var characters := {}
	_collect_cjk("res://src", characters)
	_collect_cjk("res://content", characters)
	for character: String in "0123456789%+−×→←◆◇·: , .!?()''":
		characters[character] = true
	for font: FontFile in [Shell.ui_font(), Shell.data_font()]:
		_expect(font != null and not font.allow_system_fallback, "bundled font does not rely on system fallback")
		if font == null: continue
		for character: String in characters:
			_expect(font.has_char(character.unicode_at(0)), "%s missing %s" % [font.get_font_name(), character])
	print("FONT_COVERAGE checked ", characters.size(), " project characters in both bundled faces")


func _collect_cjk(path: String, characters: Dictionary) -> void:
	var expression := RegEx.create_from_string("[\\x{3400}-\\x{9FFF}]")
	for file: String in DirAccess.get_files_at(path):
		if file.get_extension() not in ["gd", "json"]: continue
		for match: RegExMatch in expression.search_all(FileAccess.get_file_as_string(path.path_join(file))):
			characters[match.get_string()] = true
	for directory: String in DirAccess.get_directories_at(path):
		_collect_cjk(path.path_join(directory), characters)
