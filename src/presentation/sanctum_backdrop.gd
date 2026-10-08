extends Control
## Static, low-contrast scenery behind readable game panels. No input or clocks.
var motif := "forge"
var scenery: Texture2D

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(queue_redraw)
	scenery = load("res://art/production/p1/title_concept_v02/background.png")
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("0b1015"))
	if scenery != null:
		var scale_factor := ceilf(maxf(size.x / 640.0, size.y / 360.0))
		var image_size := Vector2(640, 360) * scale_factor
		draw_texture_rect(scenery, Rect2(((size-image_size)*0.5).floor(), image_size), false, Color(0.49,0.57,0.62,0.44))
	# Fine stone courses are fixed geometry, intentionally absent beneath text.
	for y in range(72, int(size.y)-20, 96):
		draw_line(Vector2(18,y), Vector2(size.x-18,y), Color(0.32,0.40,0.43,0.06), 1)
	var center := Vector2(size.x*0.73, size.y*0.48)
	var radius := minf(size.y*0.31, 246.0)
	var metal := Color(0.65,0.47,0.27,0.12)
	for ring in [radius, radius-10.0, radius*0.67]:
		draw_arc(center,ring,0,TAU,48,metal,1,false)
	for i in range(12):
		var direction := Vector2.from_angle(float(i)*TAU/12.0)
		draw_line(center+direction*(radius-16),center+direction*(radius+5),metal,2)
	# Broken corner fittings rather than a continuous spreadsheet border.
	var edge := Color("76583e")
	for corner in [Vector2(8,8),Vector2(size.x-8,8),Vector2(8,size.y-8),size-Vector2(8,8)]:
		var axis := Vector2(1 if corner.x < size.x/2 else -1,1 if corner.y < size.y/2 else -1)
		draw_line(corner,corner+Vector2(58*axis.x,0),edge,2)
		draw_line(corner,corner+Vector2(0,26*axis.y),edge,2)
		draw_rect(Rect2(corner+Vector2(4*axis.x,4*axis.y)-Vector2(1,1),Vector2(3,3)),Color("b48c5a"))
