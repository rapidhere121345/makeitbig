extends SceneTree
## Real asset binding, identity preservation, contrast, cache and layout contract.
const Shell = preload("res://src/presentation/shell_theme.gd")
const GridIcon = preload("res://src/presentation/pixel_grid_icon.gd")
const Progression = preload("res://src/presentation/progression_icons.gd")
const Skills = preload("res://src/presentation/combat_skill_icons.gd")
var errors: Array[String] = []
var preserved := 0
var contrasts: Dictionary = {}

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var theme := Shell.create()
	_expect(theme.default_font == Shell.ui_font(), "packaged Chinese face")
	_expect(theme.get_font("font", "Button") == Shell.data_font()
		and theme.get_font("font", "DataLabel") == Shell.data_font(), "controls and values use the bundled medium sans face")
	_check_font_coverage()
	_expect(theme.default_font_size == 22 and Shell.MIN_FONT_SIZE == 18, "22/18 reading contract")
	_expect(Shell.WARNING == Color("d95149") and Shell.PROXY == Color("41b7ae")
		and Shell.ANOMALY == Color("7450a6"), "semantic colours retained")
	for kind in ["panel", "button", "well", "paper", "hover", "selected", "disabled"]:
		var first := Shell.panel_style(kind)
		var second := Shell.panel_style(kind)
		_expect(first != second and first.texture != null and first.texture == second.texture, kind + " cached texture, independent margins")
		_expect(first.content_margin_left == 16 and first.content_margin_right == 16
			and first.content_margin_top == 12 and first.content_margin_bottom == 12, kind + " stable layout margins")
		first.content_margin_top = 3
		_expect(second.content_margin_top == 12, "caller override stays local")
		var image := second.texture.get_image()
		_expect(image.get_size() == Vector2i(64,64), kind + " generated 64px material")
		var peak := 0.0
		for y in range(12,52):
			for x in range(12,52):
				var pixel := image.get_pixel(x,y)
				_expect(pixel.a == 1.0, kind + " writing surface opaque")
				peak = maxf(peak, _luma(pixel))
		var body := (_luma(Shell.BONE)+0.05)/(peak+0.05)
		var auxiliary := (_luma(Shell.NEUTRAL)+0.05)/(peak+0.05)
		contrasts[kind] = {"body_min":body,"auxiliary_min":auxiliary}
		_expect(body >= 7.0 and auxiliary >= 4.5, kind + " worst-pixel writing contrast")
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
	var well := icon.get_node("HearthsideIconWell") as TextureRect
	_expect(well.mouse_filter == Control.MOUSE_FILTER_IGNORE and well.show_behind_parent, "backing cannot block icon input or cover its foreground")
	_expect(well.texture == Shell.material_texture("icon_well") and well.size == icon.size
		and icon.get_combined_minimum_size() == Vector2(64,64), "backing preserves display/layout contract")
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
	_expect(after.load_png_from_buffer(FileAccess.get_file_as_bytes(Shell.MATERIAL_DIRECTORY.path_join(name))) == OK, "framed " + name)
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

func _expect(ok: bool, message: String) -> void:
	if not ok: errors.append(message)


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
