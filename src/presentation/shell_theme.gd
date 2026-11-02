class_name ShellTheme
extends RefCounted
## Modern Hearthside shell: open sections, quiet surfaces and restrained accents.
## Presentation only; content margins stay stable so this skin does not trade
## away the established readable text and compact-window layout contracts.

const SharedPalette := preload("res://src/presentation/palette.gd")
const UiKit := preload("res://src/presentation/ui_kit.gd")
const MATERIAL_DIRECTORY := "res://art/production/p1/ui_style_r13"
const EXPLORATION_ART := "res://art/production/p1/ui_exploration_v01"
const CRAFTED_ART := "res://art/production/p1/ui_crafted_v01"
const TextureLoader := preload("res://src/presentation/art/texture_loader.gd")
static var _materials: Dictionary = {}


class MaterialBackdrop extends Control:
	var scenery: Texture2D
	var workshop := false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var motif := String(get_meta("motif", ""))
		if motif in ["contract_screen", "result_screen"]:
			scenery = ShellTheme.illustration_texture("contract_road" if motif == "contract_screen" else "settlement_table")
		elif motif == "facility_screen":
			workshop = true
			scenery = ShellTheme.crafted_texture("workshop")
		resized.connect(queue_redraw)
		queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), ShellTheme.INK)
		if scenery != null:
			var extent := scenery.get_size() * maxf(size.x / scenery.get_width(), size.y / scenery.get_height())
			var intensity := float(get_meta("material_intensity", 0.52))
			var tint := Color(intensity, intensity, intensity, 1) if workshop else Color(0.22, 0.25, 0.29, 1)
			draw_texture_rect(scenery, Rect2((size - extent) * 0.5, extent), false, tint)

## Full Simplified-Chinese faces, bundled with their upstream OFL licences.
## Serif carries the town's book/inscription character; medium sans keeps
## controls and numerical comparisons easy to scan. See art/fonts/PROVENANCE.md.
const FONT_PATH := "res://art/fonts/NotoSerifCJKsc-Medium.otf"
const DATA_FONT_PATH := "res://art/fonts/NotoSansCJKsc-Medium.otf"

## The body step stays comfortably readable in a 1600x900 desktop window. Smaller
## 18px copy is reserved for secondary notes; ordinary labels no longer use it to
## squeeze more rows onto screen.
const BODY_FONT_SIZE := 22
## Smallest size any shared control may ask for, so CJK never drops to unreadable.
const MIN_FONT_SIZE := 18
## Quiet hierarchy steps: sections and controls sit one step below body copy so
## panel titles stop competing with the text they frame.
const SECTION_FONT_SIZE := 20
const COMPACT_FONT_SIZE := 18

## Approved cold-slate ramp (2026-09-14 brief, plus the raised step shared with the
## production skin in combat_palette.gd so combat and shell agree on the greys).
const INK := SharedPalette.SLATE_INK
const DEEP_BLUE := SharedPalette.SHELL_DEEP_BLUE
const GROUND := SharedPalette.SLATE_GROUND
## Muted secondary copy. One readable step above the decorative slate, because the
## formal screens use this token for 18px body text, not for ornament.
const NEUTRAL := Color("a7ada9")
const BONE := SharedPalette.BONE
## Old-copper accent: idle edges use the dull tone, selection uses the bright one.
const COPPER_DULL := SharedPalette.COPPER_EDGE
const AMBER := Color("c49364")
## Semantic colours. Values intentionally unchanged: danger, success/proxy and
## true-magic already have approved meanings that this restyle must not move.
const WARNING := Color("d95149")
const PROXY := Color("41b7ae")
const ANOMALY := Color("7450a6")

static var _ui_font: FontFile = null
static var _ui_font_checked := false
static var _data_font: FontFile


## The packaged UI font, or null when the project has not imported it yet.
## Callers that only need "the theme already uses it" should not call this at all:
## create() wires it into the returned Theme.
static func ui_font() -> FontFile:
	if not _ui_font_checked:
		_ui_font_checked = true
		_ui_font = ResourceLoader.load(FONT_PATH, "FontFile") as FontFile
		if _ui_font == null:
			push_error(
				"ShellTheme: packaged UI font missing at %s. Import the project " % FONT_PATH
				+ "assets (godot --headless --path . --import) so Chinese UI text "
				+ "renders from the bundled font; no system font is substituted."
			)
	return _ui_font


static func data_font() -> FontFile:
	if _data_font == null:
		_data_font = load(DATA_FONT_PATH) as FontFile
	return _data_font


static func create() -> Theme:
	var theme := Theme.new()
	theme.default_font = data_font()
	theme.default_font_size = BODY_FONT_SIZE

	theme.set_color("font_color", "Label", BONE)
	theme.set_color("font_shadow_color", "Label", INK)
	theme.set_constant("shadow_offset_x", "Label", 0)
	theme.set_constant("shadow_offset_y", "Label", 0)
	theme.set_constant("line_spacing", "Label", 4)
	theme.set_font_size("font_size", "Label", BODY_FONT_SIZE)
	theme.set_type_variation("DataLabel", "Label")
	theme.set_font("font", "DataLabel", data_font())
	for kind: String in ["Button", "OptionButton", "LineEdit", "PopupMenu", "TabBar", "Tree", "ItemList"]:
		theme.set_font("font", kind, data_font())

	theme.set_color("font_color", "Button", BONE)
	theme.set_color("font_hover_color", "Button", SharedPalette.BONE_HOVER)
	theme.set_color("font_pressed_color", "Button", Color("ffe0a1"))
	theme.set_color("font_disabled_color", "Button", NEUTRAL)
	theme.set_font_size("font_size", "Button", 20)
	theme.set_stylebox("normal", "Button", panel_style("button"))
	theme.set_stylebox("hover", "Button", panel_style("hover"))
	theme.set_stylebox("pressed", "Button", panel_style("selected"))
	theme.set_stylebox("focus", "Button", _box(Color(0, 0, 0, 0), BONE, 2, 0))
	theme.set_stylebox("disabled", "Button", panel_style("disabled"))

	# Smoked charcoal reading wells and bronze focus match the workshop materials.
	for control_type: String in ["LineEdit", "OptionButton"]:
		theme.set_color("font_color", control_type, BONE)
		theme.set_color("font_placeholder_color", control_type, NEUTRAL)
		theme.set_font_size("font_size", control_type, 20)
		theme.set_stylebox("normal", control_type, panel_style("disabled"))
		theme.set_stylebox("focus", control_type, _box(Color("17130f"), AMBER, 1, 0))
	theme.set_color("font_hover_color", "OptionButton", BONE)
	theme.set_color("font_pressed_color", "OptionButton", BONE)
	theme.set_stylebox("hover", "OptionButton", panel_style("hover"))
	theme.set_stylebox("pressed", "OptionButton", panel_style("selected"))

	theme.set_stylebox("panel", "PanelContainer", panel_style())
	theme.set_stylebox("panel", "PopupPanel", panel_style("paper"))
	theme.set_stylebox("panel", "AcceptDialog", panel_style("paper"))
	theme.set_color("font_color", "RichTextLabel", BONE)
	theme.set_color("default_color", "RichTextLabel", BONE)
	theme.set_constant("line_separation", "RichTextLabel", 4)
	theme.set_stylebox("background", "ProgressBar", _box(INK, Color("524c3e"), 1, 0))
	theme.set_stylebox("fill", "ProgressBar", _box(Color("866c43"), Color("c4a76a"), 1, 0))
	return theme


## Keep a ScrollContainer available for compact-window fallback and focus reveal
## without drawing a permanent rail through an otherwise fixed desktop page.
## Deliberate long-reading surfaces should keep the normal scrollbar instead.
static func hide_passive_scrollbar_chrome(scroll: ScrollContainer) -> void:
	var bar := scroll.get_v_scroll_bar()
	for style_name in ["scroll", "scroll_focus", "grabber", "grabber_highlight", "grabber_pressed"]:
		bar.add_theme_stylebox_override(style_name, StyleBoxEmpty.new())


static func _box(fill: Color, border: Color, width: int, radius: int) -> StyleBoxFlat:
	return UiKit.flat_style(fill, border, width, radius, Vector4(16.0, 12.0, 16.0, 12.0))


## Quiet borderless slate surface for overlays that need a reading ground.
static func slate_panel(edge: Color = COPPER_DULL, fill: Color = DEEP_BLUE) -> StyleBoxFlat:
	var box := _box(fill, edge, 0, 0)
	return box


## Accent variant used on headers and selected frames: slate fill, brighter
## bronze rule on the bottom edge only.
static func slate_header() -> StyleBoxFlat:
	var box := _box(Color("18222b"), DEEP_BLUE, 1, 0)
	box.border_color = Color("00000000")
	box.set_border_width_all(0)
	box.border_width_bottom = 2
	box.border_color = COPPER_DULL
	return box


## Section containers keep layout margins without painting another card.
static func section_style() -> StyleBoxFlat:
	return _box(Color.TRANSPARENT, Color.TRANSPARENT, 0, 0)


static func primary_button_style(tint: Color = Color.WHITE) -> StyleBoxTexture:
	var box := StyleBoxTexture.new()
	box.texture = crafted_texture("action")
	box.modulate_color = tint
	# Only the narrow engraved caps and metal rims retain their native size.
	# Layout margins deliberately match the open UI's existing button contract.
	box.texture_margin_left = 24
	box.texture_margin_right = 24
	box.texture_margin_top = 6
	box.texture_margin_bottom = 6
	box.content_margin_left = 16
	box.content_margin_right = 16
	box.content_margin_top = 12
	box.content_margin_bottom = 12
	return box


static func apply_primary_button(button: Button) -> void:
	button.add_theme_stylebox_override("normal", primary_button_style())
	button.add_theme_stylebox_override("hover", primary_button_style(Color(1.3, 1.2, 1.05)))
	button.add_theme_stylebox_override("pressed", primary_button_style(Color(0.75, 0.75, 0.75)))
	button.add_theme_stylebox_override("disabled", primary_button_style(Color(0.42, 0.42, 0.42)))
	# Focus stays the shared high-contrast outline, independent of hover or art.


static func crafted_texture(name: String) -> Texture2D:
	var key := "crafted/" + name
	if not _materials.has(key):
		var path := CRAFTED_ART.path_join(name + ".png")
		var loaded := TextureLoader.load_imported_first(path)
		if loaded.texture == null:
			push_error("Crafted UI material missing: " + path)
		_materials[key] = loaded.texture
	return _materials[key] as Texture2D


static func panel_style(kind: String = "panel") -> StyleBoxFlat:
	var box := section_style()
	match kind:
		"panel":
			box.bg_color = Color("171511f2")
		"paper":
			box.bg_color = Color("171511")
			box.set_corner_radius_all(4)
		"button":
			box.bg_color = Color("100f0dcc")
			box.border_color = Color("66523b99")
			box.border_width_bottom = 1
		"hover":
			box.bg_color = Color("221c14e6")
			box.border_color = COPPER_DULL
			box.border_width_bottom = 1
		"selected":
			box.bg_color = Color("2b2115e6")
			box.border_color = AMBER
			box.border_width_bottom = 2
		"disabled":
			box.bg_color = Color("08080799")
		"well":
			pass
	return box


## One upload per authored material. Fresh styleboxes let callers adjust their
## margins without changing another screen; textures are shared across routes.
static func material_texture(kind: String) -> Texture2D:
	if not _materials.has(kind):
		var path := MATERIAL_DIRECTORY.path_join(kind + "_v01.png")
		var texture: Texture2D = null
		if ResourceLoader.exists(path):
			texture = load(path) as Texture2D
		elif FileAccess.file_exists(path):
			var image := Image.new()
			if image.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) == OK:
				texture = ImageTexture.create_from_image(image)
		if texture == null:
			push_error("R13 UI material missing: " + path)
		_materials[kind] = texture
	return _materials[kind] as Texture2D


static func add_backdrop(host: Control, motif: String = "forge") -> Control:
	host.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var backdrop := MaterialBackdrop.new()
	backdrop.name = "SanctumBackdrop"
	backdrop.set_meta("motif", motif)
	host.add_child(backdrop)
	host.move_child(backdrop, 0)
	return backdrop


static func illustration_texture(name: String) -> Texture2D:
	var key := "illustration/" + name
	if not _materials.has(key):
		_materials[key] = load(EXPLORATION_ART.path_join(name + ".png")) as Texture2D
	return _materials[key] as Texture2D


## Kept as the shared major-section entry point; sections no longer draw frames.
static func crafted_panel() -> StyleBoxFlat:
	return section_style()


static func illustration_panel(name: String, minimum_height: float) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", crafted_panel())
	panel.custom_minimum_size.y = minimum_height
	var art := TextureRect.new()
	art.name = "Illustration"
	art.texture = illustration_texture(name)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(art)
	return panel
