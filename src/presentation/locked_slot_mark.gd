extends Control

const SharedPalette := preload("res://src/presentation/palette.gd")
## Code-native UI lock, not an equipment sprite or new world-art substitute.
## Integer, hard-edged slate mark; lock reason remains real readable text.
func _init() -> void:
	custom_minimum_size = Vector2(24,28)
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var slate := Color("69777b")
	draw_rect(Rect2(6,0,12,4),slate)
	draw_rect(Rect2(3,4,4,10),slate)
	draw_rect(Rect2(17,4,4,10),slate)
	draw_rect(Rect2(1,12,22,16),slate)
	draw_rect(Rect2(10,17,4,7),SharedPalette.SLATE_INK)
