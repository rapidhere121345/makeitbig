extends SceneTree
## Shared UI helper gate (src/presentation/ui_kit.gd).
##   godot --headless --path . --script res://tests/unit/test_ui_kit.gd

const UiKit := preload("res://src/presentation/ui_kit.gd")

var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	_coercion()
	_children()
	_tokens()
	_builders()
	_styles()
	for message in failures:
		printerr(message)
	print("UI_KIT ", "pass" if failures.is_empty() else "fail", " checks=", checks)
	quit(0 if failures.is_empty() else 1)


func _coercion() -> void:
	_expect(UiKit.as_dictionary({"a": 1}) == {"a": 1}, "as_dictionary keeps a dictionary")
	_expect(UiKit.as_dictionary([1]).is_empty() and UiKit.as_dictionary(null).is_empty(), "as_dictionary maps other values to {}")
	_expect(UiKit.as_array([1, 2]) == [1, 2], "as_array keeps an array")
	_expect(UiKit.as_array({"a": 1}).is_empty() and UiKit.as_array("x").is_empty(), "as_array maps other values to []")


func _children() -> void:
	UiKit.clear_children(null)
	UiKit.clear_children_immediate(null)
	var queued := Node.new()
	var queued_child := Node.new()
	queued.add_child(queued_child)
	UiKit.clear_children(queued)
	_expect(queued.get_child_count() == 0, "clear_children detaches children")
	_expect(is_instance_valid(queued_child) and queued_child.is_queued_for_deletion(), "clear_children queues removal instead of freeing")
	queued_child.free()
	queued.free()
	var immediate := Node.new()
	var immediate_child := Node.new()
	immediate.add_child(immediate_child)
	UiKit.clear_children_immediate(immediate)
	_expect(immediate.get_child_count() == 0, "clear_children_immediate detaches children")
	_expect(not is_instance_valid(immediate_child), "clear_children_immediate frees children at once")
	immediate.free()


func _tokens() -> void:
	_expect(UiKit.stable_node_token("Abc_9-z") == "Abc_9-z", "stable_node_token keeps legal characters")
	_expect(UiKit.stable_node_token("a b.c/d") == "a_b_c_d", "stable_node_token replaces illegal characters")
	_expect(UiKit.stable_node_token("") == "", "stable_node_token accepts an empty string")


func _builders() -> void:
	var label := UiKit.colored_label("Hello", 22, Color.RED)
	_expect(label.text == "Hello" and label.get_theme_font_size("font_size") == 22, "colored_label sets text and size")
	_expect(label.get_theme_color("font_color") == Color.RED, "colored_label sets the colour")
	label.free()
	var button := UiKit.sized_button("Go", "GoButton", 18)
	_expect(button.name == "GoButton" and button.text == "Go", "sized_button sets name and text")
	_expect(button.get_theme_font_size("font_size") == 18 and button.focus_mode == Control.FOCUS_ALL, "sized_button sets size and focus")
	_expect(Button.new().focus_mode == Control.FOCUS_ALL, "a plain Button already focuses on all input")
	button.free()
	var plain := UiKit.icon_node(null, Vector2(32, 32), false, TextureRect.STRETCH_SCALE)
	_expect(plain.custom_minimum_size == Vector2(32, 32) and plain.stretch_mode == TextureRect.STRETCH_SCALE, "icon_node applies size and stretch mode")
	_expect(plain.mouse_filter == Control.MOUSE_FILTER_IGNORE and plain.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "icon_node ignores the mouse and never filters")
	_expect(not plain is PixelGridIcon, "icon_node returns a plain TextureRect when pixel_grid is false")
	plain.free()
	var grid := UiKit.icon_node(null, Vector2(64, 64), true, TextureRect.STRETCH_KEEP_ASPECT_CENTERED)
	_expect(grid is PixelGridIcon, "icon_node returns a PixelGridIcon when pixel_grid is true")
	grid.free()


func _styles() -> void:
	var bare := UiKit.flat_style(Color.BLACK, Color.WHITE)
	_expect(bare.get_border_width(SIDE_LEFT) == 0 and bare.get_content_margin(SIDE_LEFT) == -1.0, "flat_style defaults to no border and unset margins")
	var full := UiKit.flat_style(Color.RED, Color.BLUE, 2, 5, Vector4(1.0, 2.0, 3.0, 4.0))
	_expect(full.bg_color == Color.RED and full.border_color == Color.BLUE, "flat_style sets fill and border colours")
	_expect(full.get_border_width(SIDE_TOP) == 2 and full.get_border_width(SIDE_BOTTOM) == 2, "flat_style sets the border width on every side")
	_expect(full.corner_radius_top_left == 5 and full.corner_radius_bottom_right == 5, "flat_style sets every corner radius")
	_expect(full.get_content_margin(SIDE_LEFT) == 1.0 and full.get_content_margin(SIDE_TOP) == 2.0 and full.get_content_margin(SIDE_RIGHT) == 3.0 and full.get_content_margin(SIDE_BOTTOM) == 4.0, "flat_style margins are left, top, right, bottom")


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append("FAIL: " + message)
