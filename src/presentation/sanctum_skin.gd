extends RefCounted
## Small cached nine-slice materials. Generated once; no imported art is edited.
static var _textures: Dictionary = {}

static func style(kind: String = "panel") -> StyleBoxTexture:
	if not _textures.has(kind): _textures[kind] = _make_texture(kind)
	var box := StyleBoxTexture.new()
	box.texture = _textures[kind]
	for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]:
		box.set_texture_margin(side,12)
	box.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	box.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	box.content_margin_left = 16
	box.content_margin_right = 16
	box.content_margin_top = 12
	box.content_margin_bottom = 12
	return box

static func _make_texture(kind: String) -> Texture2D:
	var img := Image.create(48,48,false,Image.FORMAT_RGBA8)
	var fill := Color("1a252c")
	var rim := Color("72583f")
	var light := Color("a78a5c")
	if kind == "button": fill = Color("263133")
	if kind in ["hover", "selected"]:
		fill = Color("40372b") if kind == "selected" else Color("323b39")
		rim = Color("b28b51")
		light = Color("dfc48d")
	if kind == "disabled":
		fill = Color("172025")
		rim = Color("384448")
		light = Color("586269")
	if kind == "well":
		fill = Color("10191f")
		rim = Color("46514e")
	if kind == "paper":
		fill = Color("292b27")
		rim = Color("807052")
	img.fill(Color.TRANSPARENT)
	for y in range(48):
		for x in range(48):
			var edge := mini(mini(x,47-x),mini(y,47-y))
			var corner := mini(x,47-x)+mini(y,47-y)
			if corner < 5: continue
			var color := fill
			# A restrained woven/grained material, low enough contrast for text.
			if (x*13+y*7)%23 == 0: color = fill.lightened(0.025)
			if y%6 == 0: color = fill.darkened(0.065)
			if edge == 0 or corner == 5: color = Color("080d11")
			elif edge == 1: color = rim
			elif edge == 2: color = light.darkened(0.30) if y < 24 else rim.darkened(0.45)
			elif edge == 4: color = fill.lightened(0.085)
			img.set_pixel(x,y,color)
	for point in [Vector2i(7,7),Vector2i(40,7),Vector2i(7,40),Vector2i(40,40)]:
		img.set_pixel(point.x,point.y,light)
		img.set_pixel(point.x+1,point.y+1,rim.darkened(0.3))
	return ImageTexture.create_from_image(img)
