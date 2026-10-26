extends SceneTree
const Readability = preload("res://src/presentation/actor_readability.gd")
const Town = preload("res://src/presentation/town_presenter.gd")
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var town := Town.new()
	var hero := town._actor_sprite("Ranger")
	var resident := town._actor_sprite("Resident_mira")
	_expect(hero.material == Readability.material_for("hero"), "town hero has silhouette contrast")
	_expect(resident.material == Readability.material_for("resident"), "resident keeps a distinct friendly rim")
	_expect(hero.material != resident.material, "hero and resident accents are distinct")
	var view := Node2D.new()
	Readability.apply_unique(view, "hostile")
	var material := view.material
	Readability.apply_unique(view, "hostile")
	_expect(view.material == material and material != Readability.material_for("hostile"), "arena reuses one private material per actor")
	var image := Image.create(16, 8, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	for y in range(2,6):
		for x in range(2,6): image.set_pixel(x,y,Color(0.18,0.18,0.18,1))
	for y in 8:
		for x in range(8,16): image.set_pixel(x,y,Color.RED)
	var texture := ImageTexture.create_from_image(image)
	Readability.bind_region(view,texture,Rect2(0,0,8,8))
	_expect((view.material as ShaderMaterial).get_shader_parameter("source_region") == Vector4(0,0,0.5,1), "full frame bounds are retained across cutaway tiles")
	view.free()
	hero.free()
	resident.free()
	town.free()
	if "--render" in OS.get_cmdline_user_args():
		if DisplayServer.get_name().to_lower().contains("headless"):
			_expect(false, "rendered contrast checks require a real renderer")
		else:
			await _render(texture)
	for failure: String in failures: printerr(failure)
	print("ACTOR_READABILITY ","pass" if failures.is_empty() else "fail"," checks=",checks)
	quit(0 if failures.is_empty() else 1)

func _render(texture: Texture2D) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(160,80)
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	root.add_child(viewport)
	var backgrounds: Array[Color] = [Color(0.12,0.12,0.12,1),Color(0.85,0.85,0.85,1)]
	for i in 2:
		var background := ColorRect.new()
		background.position = Vector2(i*80,0)
		background.size = Vector2(80,80)
		background.color = backgrounds[i]
		viewport.add_child(background)
		var sprite := Sprite2D.new()
		sprite.centered = false
		sprite.region_enabled = true
		sprite.region_rect = Rect2(0,0,8,8)
		sprite.texture = texture
		sprite.position = Vector2(16+i*80,16)
		sprite.scale = Vector2(4,4)
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.material = Readability.material_for("hero")
		viewport.add_child(sprite)
	for i in 4: await process_frame
	await RenderingServer.frame_post_draw
	var pixels := viewport.get_texture().get_image()
	for i in 2:
		var x := 16+i*80
		_expect(pixels.get_pixel(x+14,30).r > 0.18, "body is brighter against either background")
		var outline := pixels.get_pixel(x+6,30)
		_expect(outline.r < backgrounds[i].r * 0.8, "dark keyline separates silhouette from background")
		_expect(absf(pixels.get_pixel(x+30,30).r-backgrounds[i].r)<0.01 and absf(pixels.get_pixel(x+30,30).g-backgrounds[i].g)<0.01, "neighboring red atlas cell never bleeds into region")
		var rim := pixels.get_pixel(x+10,26)
		_expect(rim.r > pixels.get_pixel(x+14,30).r+0.10, "light rim remains visible against dark ground")
	var destination := "res://build/current/language-display-20261026/actor-contrast-fixture.png"
	_expect(pixels.save_png(destination)==OK,"write rendered contrast fixture")
	viewport.free()
	await process_frame

func _expect(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)
