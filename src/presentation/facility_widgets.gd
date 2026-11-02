extends RefCounted
## Stateless widget factories shared by the facility screen and its page
## scripts: rows, labels, section panels, cell styles and icon nodes.

const ShellThemeScript = preload("res://src/presentation/shell_theme.gd")
const FacilityArtScript = preload("res://src/presentation/facility_art.gd")
const UiKit := preload("res://src/presentation/ui_kit.gd")


## An open workspace section with a 22px heading. `parent` receives the panel
## and the returned VBox is its content, so a page lays out its own rows inside
## instead of feeding a generic card framework.
static func section_in(parent: Container, heading_text: String, node_name: String = "") -> VBoxContainer:
	var panel := PanelContainer.new()
	if not node_name.is_empty():
		panel.name = node_name
	panel.add_theme_stylebox_override("panel", ShellThemeScript.section_style())
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	panel.add_child(content)
	if not heading_text.is_empty():
		content.add_child(heading_label(heading_text))
	return content


static func make_row(node_name: String = "") -> HBoxContainer:
	var row := HBoxContainer.new()
	if not node_name.is_empty():
		row.name = node_name
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 12)
	return row


static func heading_label(text: String) -> Label:
	var label := body_label(text)
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color("dcc494"))
	return label


## Page copy at the approved 20px body step. Every label wraps: a semantic name
## is never trimmed away to keep a column narrow.
static func body_label(text: String, color: Color = ShellThemeScript.BONE) -> Label:
	var label := Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", color)
	return label


## Secondary copy: states, reasons and hints. Never below the 18px floor.
static func note_label(text: String) -> Label:
	var label := body_label(text, ShellThemeScript.NEUTRAL)
	label.add_theme_font_size_override("font_size", 18)
	return label


## "Key: Value" stays one Label so the value cannot be read without the key that
## names it, and text collection sees exactly what the screen shows.
static func fact_label(parent: Container, key: String, value: String, color: Color = ShellThemeScript.BONE) -> Label:
	var label := body_label("%s: %s" % [key, value], color)
	parent.add_child(label)
	return label


## Slot emphasis: the focused slot uses the bright copper edge, an empty one a
## dim edge, a filled one the idle copper. The state word in the cell is what
## actually says which case this is; the edge only reinforces it.
static func slot_cell_box(focused: bool, empty: bool) -> StyleBox:
	var box := ShellThemeScript.panel_style("selected") if focused else ShellThemeScript.panel_style("disabled" if empty else "button")
	box.content_margin_left = 0
	box.content_margin_right = 0
	box.content_margin_top = 0
	box.content_margin_bottom = 0
	return box


## Informational rows keep compact spacing without looking like selected slots.
static func plain_cell_box() -> StyleBoxFlat:
	var box := recessed_panel_style("well")
	box.content_margin_left = 0
	box.content_margin_right = 0
	box.content_margin_top = 0
	box.content_margin_bottom = 0
	return box


## Shared flat surfaces replace the old pixel-processed nine-slice borders.
static func recessed_panel_style(kind: String = "well") -> StyleBoxFlat:
	return ShellThemeScript.panel_style(kind)


## Builds one real TextureRect over a published atlas region. `scaled` is the
## integer 2x that only the 32x32 icon batch may use; a facility mark passes
## false and keeps its native pixel size so it is never resampled smaller.
static func icon_node(texture: Texture2D, native_size: Vector2i, scaled: bool) -> TextureRect:
	var display_size := native_size
	if scaled:
		display_size = native_size * FacilityArtScript.ICON_DISPLAY_SCALE
	return UiKit.icon_node(texture, Vector2(display_size), scaled, TextureRect.STRETCH_KEEP_ASPECT_CENTERED)


## Bounded columns: children never feed their content minimum back into the
## root page width. Each content lane scrolls locally if the text grows.
static func grid_cell_box() -> StyleBox:
	var box := recessed_panel_style("well")
	box.content_margin_left = 8.0
	box.content_margin_top = 6.0
	box.content_margin_right = 8.0
	box.content_margin_bottom = 6.0
	return box
