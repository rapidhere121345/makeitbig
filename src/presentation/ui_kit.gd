extends RefCounted

## Small UI helpers repeated across screens. Everything here is static and
## screen-agnostic; screen-specific wording, colours and layout stay with the
## screen. Variants that differ in behaviour are separate, explicitly named
## functions rather than silent flags.

const UNSET_MARGINS := Vector4(-1.0, -1.0, -1.0, -1.0)


static func as_dictionary(value: Variant) -> Dictionary:
	return value as Dictionary if value is Dictionary else {}


static func as_array(value: Variant) -> Array:
	return value as Array if value is Array else []


## Detaches and queues every child of parent for deletion. Null-safe.
static func clear_children(parent: Node) -> void:
	if parent == null:
		return
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()


## Detaches and frees every child of parent immediately, for callers that must
## not see the old nodes again this frame. Null-safe.
static func clear_children_immediate(parent: Node) -> void:
	if parent == null:
		return
	for child in parent.get_children():
		parent.remove_child(child)
		child.free()


## ASCII letters, digits, "_" and "-" survive; every other character becomes "_".
static func stable_node_token(value: String) -> String:
	var token := ""
	for index in value.length():
		var character := value.substr(index, 1)
		var code := character.unicode_at(0)
		var legal := code >= 48 and code <= 57 or code >= 65 and code <= 90 or code >= 97 and code <= 122 or character in ["_", "-"]
		token += character if legal else "_"
	return token


## A single-line label with an explicit font size and colour.
static func colored_label(text_value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


## A named button with an explicit font size.
static func sized_button(text_value: String, node_name: String, font_size: int) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text_value
	button.add_theme_font_size_override("font_size", font_size)
	button.focus_mode = Control.FOCUS_ALL
	return button


## One atlas cell as a TextureRect displayed at display_size. pixel_grid selects
## the PixelGridIcon subclass that keeps a scaled cell on the logical pixel grid.
## It is referenced by class name so ShellTheme can use this module without a
## preload cycle through pixel_grid_icon.gd.
static func icon_node(texture: Texture2D, display_size: Vector2, pixel_grid: bool, stretch_mode: TextureRect.StretchMode) -> TextureRect:
	var icon: TextureRect = PixelGridIcon.new() if pixel_grid else TextureRect.new()
	icon.texture = texture
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = stretch_mode
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.custom_minimum_size = display_size
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return icon


## A flat box with a uniform border and corner radius. margins is
## (left, top, right, bottom) content margin; the default leaves them unset.
static func flat_style(fill: Color, border: Color, border_width: int = 0, corner_radius: int = 0, margins: Vector4 = UNSET_MARGINS) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(border_width)
	box.set_corner_radius_all(corner_radius)
	box.content_margin_left = margins.x
	box.content_margin_top = margins.y
	box.content_margin_right = margins.z
	box.content_margin_bottom = margins.w
	return box
