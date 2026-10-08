class_name ShellTheme
extends RefCounted
## R13: generated hearthside copper/wood fittings and cold woven materials.
## Presentation only; content margins stay stable so this skin does not trade
## away the established readable text and compact-window layout contracts.

const MATERIAL_DIRECTORY := "res://art/production/p1/ui_style_r13"
static var _materials: Dictionary = {}


class MaterialBackdrop extends Control:
	var cloth: Texture2D

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		cloth = ShellTheme.material_texture("backdrop_cloth")
		resized.connect(queue_redraw)
		queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), ShellTheme.INK)
		if cloth != null:
			draw_texture_rect(cloth, Rect2(Vector2.ZERO, size), true, Color(0.46, 0.50, 0.54, 1.0))

## Packaged Simplified-Chinese UI font: the complete "Noto Sans CJK SC" Regular
## face, repacked from the locally installed Debian fonts-noto-cjk collection.
## Provenance, licence and the regeneration command: art/fonts/PROVENANCE.md and
## tools/art_pipeline/repack_ui_font.py.
const FONT_PATH := "res://art/fonts/NotoSansCJKsc-Regular.mib-repack.otf"

## The body step stays comfortably readable in a 1600x900 desktop window. Smaller
## 18px copy is reserved for secondary notes; ordinary labels no longer use it to
## squeeze more rows onto screen.
const BODY_FONT_SIZE := 22
## Smallest size any shared control may ask for, so CJK never drops to unreadable.
const MIN_FONT_SIZE := 18

## Approved cold-slate ramp (2026-09-14 brief, plus the raised step shared with the
## production skin in combat_palette.gd so combat and shell agree on the greys).
const INK := Color("111820")
const DEEP_BLUE := Color("1d2731")
const GROUND := Color("2d3943")
## Muted secondary copy. One readable step above the decorative slate, because the
## formal screens use this token for 18px body text, not for ornament.
const NEUTRAL := Color("a7ada9")
const BONE := Color("e9ddc3")
## Old-copper accent: idle edges use the dull tone, selection uses the bright one.
const COPPER_DULL := Color("ad7950")
const AMBER := Color("c49364")
## Semantic colours. Values intentionally unchanged: danger, success/proxy and
## true-magic already have approved meanings that this restyle must not move.
const WARNING := Color("d95149")
const PROXY := Color("41b7ae")
const ANOMALY := Color("7450a6")

static var _ui_font: FontFile = null
static var _ui_font_checked := false


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


static func create() -> Theme:
	var theme := Theme.new()
	theme.default_font = ui_font()
	theme.default_font_size = BODY_FONT_SIZE

	theme.set_color("font_color", "Label", BONE)
	theme.set_color("font_shadow_color", "Label", INK)
	theme.set_constant("shadow_offset_x", "Label", 1)
	theme.set_constant("shadow_offset_y", "Label", 2)
	theme.set_font_size("font_size", "Label", BODY_FONT_SIZE)

	theme.set_color("font_color", "Button", BONE)
	theme.set_color("font_hover_color", "Button", Color("fff1ce"))
	theme.set_color("font_pressed_color", "Button", Color("ffe0a1"))
	theme.set_color("font_disabled_color", "Button", NEUTRAL)
	theme.set_font_size("font_size", "Button", 20)
	theme.set_stylebox("normal", "Button", panel_style("button"))
	theme.set_stylebox("hover", "Button", panel_style("hover"))
	theme.set_stylebox("pressed", "Button", panel_style("selected"))
	theme.set_stylebox("focus", "Button", _box(Color(0, 0, 0, 0), BONE, 2, 0))
	theme.set_stylebox("disabled", "Button", panel_style("disabled"))

	# Text entry reads as a recessed well: cool edge at rest, copper when active.
	for control_type: String in ["LineEdit", "OptionButton"]:
		theme.set_color("font_color", control_type, BONE)
		theme.set_color("font_placeholder_color", control_type, NEUTRAL)
		theme.set_font_size("font_size", control_type, 20)
		theme.set_stylebox("normal", control_type, panel_style("disabled"))
		theme.set_stylebox("focus", control_type, _box(DEEP_BLUE, AMBER, 1, 0))
	theme.set_color("font_hover_color", "OptionButton", BONE)
	theme.set_color("font_pressed_color", "OptionButton", BONE)
	theme.set_stylebox("hover", "OptionButton", panel_style("hover"))
	theme.set_stylebox("pressed", "OptionButton", panel_style("selected"))

	theme.set_stylebox("panel", "PanelContainer", panel_style())
	theme.set_stylebox("panel", "PopupPanel", panel_style())
	theme.set_stylebox("panel", "AcceptDialog", panel_style())
	theme.set_color("font_color", "RichTextLabel", BONE)
	theme.set_color("default_color", "RichTextLabel", BONE)
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
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(width)
	box.set_corner_radius_all(radius)
	box.content_margin_left = 16.0
	box.content_margin_top = 12.0
	box.content_margin_right = 16.0
	box.content_margin_bottom = 12.0
	return box


static func panel_style(kind: String = "panel") -> StyleBoxTexture:
	if kind not in ["panel", "button", "hover", "selected", "disabled", "well", "paper"]:
		kind = "panel"
	var box := StyleBoxTexture.new()
	box.texture = material_texture(kind)
	# Keep the authored material; recess reading surfaces and ordinary borders
	# so text, selected controls and active copper remain the visual priorities.
	if kind in ["paper", "well"]:
		box.modulate_color = Color(0.52, 0.57, 0.61, 1.0)
	elif kind == "panel":
		box.modulate_color = Color(0.64, 0.66, 0.69, 1.0)
	elif kind == "button":
		box.modulate_color = Color(0.78, 0.79, 0.80, 1.0)
	elif kind == "disabled":
		box.modulate_color = Color(0.58, 0.61, 0.65, 1.0)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		box.set_texture_margin(side, 12)
	box.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	box.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	box.content_margin_left = 16
	box.content_margin_right = 16
	box.content_margin_top = 12
	box.content_margin_bottom = 12
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
