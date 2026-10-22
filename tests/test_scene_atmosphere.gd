extends SceneTree
## Bounded acceptance check for the R11 scene-atmosphere package.
## Headless-safe: it validates the presentation contract, node placement and
## drawing budgets without launching the whole game or capturing pixels.
##
## Run:
##   GODOT --headless --path . --script res://tests/test_scene_atmosphere.gd
## Pixel regression (requires a rendering display; headless exits 2 / GPU SKIP):
##   GODOT --path . --script res://tests/test_scene_atmosphere.gd -- --gpu-cutout-only
## The existing --gpu capture mode also runs this isolated shader regression.
## Authored reveal fixture: -- --gpu-authored-reveal --output=/fresh/absolute/path

const Atmosphere = preload("res://src/presentation/scene_atmosphere.gd")
const AuthoredReveal = preload("res://src/presentation/occlusion/authored_reveal_controller.gd")
const AtmosphereLayerScript = preload("res://src/presentation/scene_atmosphere_layer.gd")
const BaseHubScript = preload("res://src/presentation/base_hub_screen.gd")
const ArenaWorldViewScript = preload("res://src/presentation/arena_world_view.gd")
const HearthReturnViewScript = preload("res://src/presentation/hearth_return_view.gd")

var failures: Array[String] = []
var output_dir := ""
var captures: Array[Dictionary] = []

func _initialize() -> void:
	if _has_arg("--gpu-authored-reveal"):
		call_deferred("_run_authored_reveal_gpu")
		return
	if _has_arg("--gpu-cutout-only"):
		call_deferred("_run_cutout_gpu")
		return
	if _has_arg("--gpu"):
		call_deferred("_run_gpu")
		return
	_test_presets()
	_test_layer()
	_test_hamlet()
	_test_arena()
	_test_hearth()
	if failures.is_empty():
		print("PASS ui_atmosphere_r11 lighting_check")
		quit(0)
		return
	printerr("%d atmosphere check(s) failed:" % failures.size())
	for failure in failures:
		printerr("- %s" % failure)
	quit(1)

func _run_gpu() -> void:
	if DisplayServer.get_name().to_lower().contains("headless"):
		printerr("GPU SKIP: display is headless")
		quit(2)
		return
	output_dir = _arg("--output=")
	if not output_dir.is_absolute_path() or DirAccess.dir_exists_absolute(output_dir):
		printerr("GPU REJECTED: fresh absolute --output directory required")
		quit(2)
		return
	if DirAccess.make_dir_recursive_absolute(output_dir) != OK:
		printerr("GPU REJECTED: cannot create %s" % output_dir)
		quit(2)
		return
	await _test_cutout_gpu()
	await _test_authored_reveal_gpu()
	await _capture_hamlet()
	await _capture_hearth()
	await _capture_arena()
	var report := {"status":"pass" if failures.is_empty() else "fail", "errors":failures, "captures":captures, "fixture_note":"Synthetic shader fixtures plus isolated published scene views with fixed lighting toggles; not production-art acceptance or a playable combat test."}
	var file := FileAccess.open(output_dir.path_join("REPORT.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("R11_LIGHTING_GPU ",report.status," captures=",captures.size())
	quit(0 if failures.is_empty() else 1)

func _run_cutout_gpu() -> void:
	if DisplayServer.get_name().to_lower().contains("headless"):
		printerr("GPU SKIP: cutout pixel regression requires a rendering display")
		quit(2)
		return
	await _test_cutout_gpu()
	for failure in failures:
		printerr("- %s" % failure)
	print("CUTOUT_GPU ", "pass" if failures.is_empty() else "fail")
	quit(0 if failures.is_empty() else 1)

func _test_cutout_gpu() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(96, 32)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var source := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	source.fill(Color(0.5, 0.75, 0.25, 0.65))
	source.fill_rect(Rect2i(0, 0, 16, 32), Color(0.8, 0.3, 0.6, 0.4))
	var texture := ImageTexture.create_from_image(source)
	var material := ShaderMaterial.new()
	material.shader = load("res://src/presentation/occlusion/occluder_cutout.gdshader")
	material.set_shader_parameter("hole_count", 0)
	material.set_shader_parameter("feather", 2.0)
	material.set_shader_parameter("inner_alpha", 0.18)
	for index in range(3):
		var sprite := Sprite2D.new()
		sprite.centered = false
		sprite.texture = texture
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.position = Vector2(index * 32, 0)
		sprite.modulate = Color(0.8, 0.6, 0.9, 0.7)
		sprite.self_modulate = Color(0.9, 0.8, 0.7, 0.85)
		if index == 1:
			sprite.material = material
		elif index == 2:
			# A native alpha-only reference also handles render-target blending.
			sprite.modulate.a *= 0.18
		viewport.add_child(sprite)
	await _settle()
	await RenderingServer.frame_post_draw
	var identity := viewport.get_texture().get_image()
	if identity == null or identity.is_empty():
		_expect(false, "cutout GPU returned no rendered pixels")
		viewport.queue_free()
		return
	var identity_error := 0.0
	for y in range(32):
		for x in range(32):
			identity_error = maxf(identity_error, _color_error(identity.get_pixel(x, y), identity.get_pixel(x + 32, y)))
	_expect(identity.get_pixel(20, 16).a > 0.1, "cutout reference must contain visible translucent pixels")
	_expect(identity_error <= 2.0 / 255.0, "hole_count=0 changed texture/modulate RGBA: error=%f" % identity_error)

	var holes := PackedVector4Array()
	holes.resize(8)
	holes[0] = Vector4(48.0, 16.0, 6.0, 0.0)
	material.set_shader_parameter("holes", holes)
	material.set_shader_parameter("hole_count", 1)
	await _settle()
	await RenderingServer.frame_post_draw
	var cutout := viewport.get_texture().get_image()
	var exterior_error := 0.0
	for y in range(32):
		for x in range(32):
			if Vector2(x + 0.5, y + 0.5).distance_to(Vector2(16, 16)) >= 9.0:
				exterior_error = maxf(exterior_error, _color_error(cutout.get_pixel(x, y), cutout.get_pixel(x + 32, y)))
	var center := cutout.get_pixel(50, 16)
	var expected_center := cutout.get_pixel(82, 16)
	_expect(_color_error(center, expected_center) <= 2.0 / 255.0, "cutout center differs from native alpha-only reference: actual=%s expected=%s" % [center, expected_center])
	_expect(center.a < cutout.get_pixel(18, 16).a * 0.3, "cutout did not reduce center alpha")
	_expect(exterior_error <= 2.0 / 255.0, "cutout changed unaffected exterior RGBA: error=%f" % exterior_error)
	print("CUTOUT_GPU identity_error=", identity_error, " exterior_error=", exterior_error, " center=", center, " expected=", expected_center)
	viewport.queue_free()
	await process_frame

func _color_error(a: Color, b: Color) -> float:
	return maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), maxf(absf(a.b - b.b), absf(a.a - b.a)))

func _run_authored_reveal_gpu() -> void:
	if DisplayServer.get_name().to_lower().contains("headless"):
		printerr("GPU SKIP: authored reveal requires a rendering display")
		quit(2)
		return
	output_dir = _arg("--output=")
	if not output_dir.is_absolute_path() or DirAccess.dir_exists_absolute(output_dir):
		printerr("GPU REJECTED: fresh absolute --output directory required")
		quit(2)
		return
	if DirAccess.make_dir_recursive_absolute(output_dir) != OK:
		printerr("GPU REJECTED: cannot create output directory")
		quit(2)
		return
	await _test_authored_reveal_gpu()
	var report := {"status": "pass" if failures.is_empty() else "fail",
		"errors": failures, "captures": captures,
		"fixture_note": "Synthetic renderer fixture only; NOT production art acceptance. Panels left to right: native full, controller, native revealed, native premultiplied midpoint."}
	var file := FileAccess.open(output_dir.path_join("REPORT.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	for failure in failures:
		printerr("- %s" % failure)
	print("AUTHORED_REVEAL_GPU ", report.status)
	quit(0 if failures.is_empty() else 1)

func _reveal_subject(id: String, baseline: float, rank: int, box: Rect2) -> Dictionary:
	return {"stable_id": id, "baseline_y": baseline, "rank": rank, "readability_box": box}

func _test_authored_reveal_gpu() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(384, 64)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var controller := AuthoredReveal.new()
	var entries: Array = []
	var masks: Array[Image] = []
	var plane := Image.create(96, 64, false, Image.FORMAT_RGBA8)
	for y in range(64):
		for x in range(96):
			plane.set_pixel(x, y, Color(0.22, 0.38, 0.56) if (x / 8 + y / 8) % 2 == 0 else Color(0.38, 0.55, 0.67))
	var base := Image.create(96, 64, false, Image.FORMAT_RGBA8)
	base.fill(Color.TRANSPARENT)
	base.fill_rect(Rect2i(34, 40, 8, 18), Color(0.72, 0.48, 0.23))
	for panel in range(4):
		_reveal_sprite(viewport, ImageTexture.create_from_image(plane), Vector2(panel * 96, 0), false)
		_reveal_sprite(viewport, ImageTexture.create_from_image(base), Vector2(panel * 96, 0), false)
	for part in range(2):
		var full := Image.create(32, 32, false, Image.FORMAT_RGBA8)
		# Saturated RGB in transparent texels catches straight-alpha crossfades.
		full.fill(Color(1, 0, 1, 0))
		var color := Color(0.8, 0.35, 0.25) if part == 0 else Color(0.3, 0.75, 0.4)
		full.fill_rect(Rect2i(2, 2, 28, 28), color)
		full.fill_rect(Rect2i(2, 2, 6, 28), Color(color.r, color.g, color.b, 0.45))
		full.fill_rect(Rect2i(12, 0, 8, 32), Color(1, 0, 1, 0))
		var revealed := Image.create(32, 32, false, Image.FORMAT_RGBA8)
		revealed.fill(Color(0, 0, 1, 0))
		revealed.fill_rect(Rect2i(2, 2, 4, 28), Color(color.r, color.g, color.b, 0.45))
		var midpoint := _reveal_midpoint(full, revealed)
		var position := Vector2(12, 8) if part == 0 else Vector2(28, 16)
		var id := "part/a" if part == 0 else "part/b"
		entries.append({"stable_id": id, "baseline_y": 50.0 + part * 10,
			"rank": 0, "art_box": Rect2(position, Vector2(32, 32))})
		masks.append(full)
		for panel in range(4):
			var image := full if panel < 2 else (revealed if panel == 2 else midpoint)
			var sprite := _reveal_sprite(viewport, ImageTexture.create_from_image(image), position + Vector2(panel * 96, 0), true)
			if panel == 1:
				var result := controller.register_piece(id, sprite, ImageTexture.create_from_image(revealed), full)
				_expect(bool(result.ok), "authored reveal registration failed: %s" % result)

	var hero := _reveal_subject("hero", 0.0, 0, Rect2(36, 26, 4, 4))
	var graze := _reveal_subject("graze", 0.0, 0, Rect2(41, 35, 40, 40))
	controller.update(entries, [], 1.0)
	var full_capture := await _reveal_capture(viewport, "authored_full.png")
	var identity_error := _reveal_panel_error(full_capture, 0)
	_expect(identity_error <= 2.0 / 255.0, "authored full/native RGBA identity error=%f" % identity_error)

	# AABB overlap inside a transparent mask gap must never request reveal.
	var gap := _reveal_subject("hero", 0.0, 0, Rect2(25, 12, 3, 4))
	controller.update(entries, [gap], 1.0)
	for state: Dictionary in controller.report().values():
		_expect(not state.open and state.coverage == 0.0, "transparent mask gap opened a reveal part")
	# Behind, equal-key, and exact equal-baseline tie-breaks use the shared sort relation.
	for case: Dictionary in [
		{"id": "hero", "y": 70.0, "rank": 0, "open": false},
		{"id": "part/a", "y": 50.0, "rank": 0, "open": false},
		{"id": "zzz", "y": 50.0, "rank": 0, "open": false},
		{"id": "aaa", "y": 50.0, "rank": 0, "open": true},
		{"id": "zzz", "y": 50.0, "rank": -1, "open": true},
		{"id": "aaa", "y": 50.0, "rank": 1, "open": false},
	]:
		controller.reset()
		controller.update(entries, [_reveal_subject(case.id, case.y, case.rank, hero.readability_box)], 1.0)
		_expect(bool(controller.report()["part/a"].open) == bool(case.open), "front/equal-baseline semantics failed: %s" % case)
	controller.reset()
	controller.update(entries, [hero, graze], AuthoredReveal.TRANSITION_SECONDS * 0.5)
	for state: Dictionary in controller.report().values():
		_expect(state.open and is_equal_approx(state.weight, 0.5) and state.coverage == 1.0, "hero plus graze must open both overlapping parts halfway")
	var transition := await _reveal_capture(viewport, "authored_transition.png")
	var midpoint_error := _reveal_panel_error(transition, 3)
	_expect(midpoint_error <= 3.0 / 255.0, "premultiplied midpoint/native reference error=%f" % midpoint_error)
	controller.update(entries, [hero, graze], AuthoredReveal.TRANSITION_SECONDS * 0.5)
	var revealed_capture := await _reveal_capture(viewport, "authored_revealed.png")
	var revealed_error := _reveal_panel_error(revealed_capture, 2)
	_expect(revealed_error <= 2.0 / 255.0, "revealed/native RGBA reference error=%f" % revealed_error)
	var under := revealed_capture.get_pixel(96 + 38, 28)
	_expect(_color_error(under, plane.get_pixel(38, 28)) <= 2.0 / 255.0, "two overlapping revealed parts did not expose underlying plane")
	for image: Image in [full_capture, transition, revealed_capture]:
		_expect(_color_error(image.get_pixel(96 + 38, 54), image.get_pixel(38, 54)) <= 2.0 / 255.0, "common base darkened during transition")
	# Mutate the caller's mask, then hold the actual transparent variant for
	# three wall-clock seconds. Coverage must still use the cached FULL mask.
	for mask: Image in masks:
		mask.fill(Color.TRANSPARENT)
	var deadline := Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < deadline:
		controller.update(entries, [graze, hero], 1.0 / 60.0)
		for state: Dictionary in controller.report().values():
			_expect(state.open and state.weight == 1.0 and state.coverage == 1.0, "revealed state oscillated or lost immutable full-mask coverage")
		await process_frame
	var held := await _reveal_capture(viewport, "authored_held.png")
	_expect(_reveal_panel_error(held, 2) <= 2.0 / 255.0, "revealed render changed during three-second hold")
	print("AUTHORED_REVEAL_GPU synthetic_only identity_error=", identity_error,
		" midpoint_error=", midpoint_error, " revealed_error=", revealed_error,
		" hold_seconds=3 final_state=", controller.report())
	controller.clear()
	viewport.queue_free()
	await process_frame

func _reveal_sprite(viewport: SubViewport, texture: Texture2D, position: Vector2, tinted: bool) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.centered = false
	sprite.position = position
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if tinted:
		sprite.modulate = Color(0.8, 0.7, 0.9, 0.85)
		sprite.self_modulate = Color(0.9, 0.8, 0.7, 0.75)
	viewport.add_child(sprite)
	return sprite

func _reveal_midpoint(full: Image, revealed: Image) -> Image:
	var result := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in range(32):
		for x in range(32):
			var a := full.get_pixel(x, y)
			var b := revealed.get_pixel(x, y)
			var alpha := (a.a + b.a) * 0.5
			var rgb := (Vector3(a.r, a.g, a.b) * a.a + Vector3(b.r, b.g, b.b) * b.a) * 0.5
			rgb = rgb / alpha if alpha > 0.00001 else Vector3.ZERO
			result.set_pixel(x, y, Color(rgb.x, rgb.y, rgb.z, alpha))
	return result

func _reveal_panel_error(image: Image, reference: int) -> float:
	var error := 0.0
	for y in range(64):
		for x in range(96):
			error = maxf(error, _color_error(image.get_pixel(96 + x, y), image.get_pixel(reference * 96 + x, y)))
	return error

func _reveal_capture(viewport: SubViewport, name: String) -> Image:
	await _settle()
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	_expect(image != null and not image.is_empty(), "authored reveal capture returned no pixels")
	if image != null and not image.is_empty() and not output_dir.is_empty():
		var enlarged := image.duplicate() as Image
		enlarged.resize(image.get_width() * 3, image.get_height() * 3, Image.INTERPOLATE_NEAREST)
		var path := output_dir.path_join(name)
		_expect(enlarged.save_png(path) == OK, "authored reveal capture write failed: " + name)
		captures.append({"name": name, "sha256": FileAccess.get_sha256(path)})
	return image

func _capture_hamlet() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var hub := BaseHubScript.new()
	viewport.add_child(hub)
	hub._ready()
	var view := hub.get_hub_view()
	_expect(bool(hub.town_load_report.get("ok", false)), "GPU town must load native layers and actual actors")
	view.set_world_scale(2, Vector2(1280, 720))
	await _settle()
	await _save(viewport, "hamlet_before.png")
	view._process(0.51)
	await _save(viewport, "hamlet_after.png")
	viewport.queue_free()

func _capture_hearth() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var view = HearthReturnViewScript.new()
	viewport.add_child(view)
	view.size = Vector2(640, 360)
	view.scale = Vector2(2.0, 2.0)
	view.set_review_time(0.0)
	await _settle()
	view._atmosphere_layer.visible = false
	var plate: CanvasItem = view.get_node_or_null("AtmosphereBackground")
	if plate != null:
		plate.visible = false
	await _save(viewport, "hearth_before.png")
	view._atmosphere_layer.visible = true
	if plate != null:
		plate.visible = true
	await _save(viewport, "hearth_after.png")
	viewport.queue_free()

func _capture_arena() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var preview := ArenaPreview.new()
	viewport.add_child(preview)
	await _settle()
	preview.atmosphere = false
	preview.queue_redraw()
	await _save(viewport, "arena_before.png")
	preview.atmosphere = true
	preview.queue_redraw()
	await _save(viewport, "arena_after.png")
	viewport.queue_free()

func _settle() -> void:
	await process_frame
	await process_frame

func _save(viewport: SubViewport, file_name: String) -> void:
	await _settle()
	RenderingServer.force_draw(false)
	var image := viewport.get_texture().get_image()
	var path := output_dir.path_join(file_name)
	_expect(not image.is_empty() and image.save_png(path) == OK, "capture " + file_name)
	captures.append({"name":file_name, "width":image.get_width(), "height":image.get_height(), "sha256":FileAccess.get_sha256(path)})

func _arg(prefix: String) -> String:
	for argument in OS.get_cmdline_user_args():
		if String(argument).begins_with(prefix):
			return String(argument).substr(prefix.length())
	return ""

func _has_arg(name: String) -> bool:
	for argument in OS.get_cmdline_user_args():
		if String(argument) == name:
			return true
	return false

class ArenaPreview:
	extends Node2D
	var view = ArenaWorldViewScript.new()
	var atmosphere := true
	var ground := load("res://art/production/p1/ground_refine_v01/ground.png") as Texture2D

	func _init() -> void:
		view.load_assets()
		view.begin_frame(Rect2(Vector2.ZERO, Vector2(1280, 720)), Vector2(430, 360), Rect2(Vector2(42, 190), Vector2(1196, 488)))

	func _draw() -> void:
		draw_set_transform_matrix(view.world_transform())
		if atmosphere:
			view.draw_ground(self)
		else:
			var region := view.visible_world_region().intersection(Rect2(Vector2.ZERO, Vector2(1024, 640)))
			draw_texture_rect_region(ground, Rect2(region.position.round(), region.size), region)
		view.draw_decals(self)
		view.draw_structure_shadows(self)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _test_presets() -> void:
	for preset in ["arena", "hamlet", "hearth"]:
		_expect(Atmosphere.preset_is_valid(preset), "preset %s is not registered" % preset)
	_expect(not Atmosphere.preset_is_valid("debug"), "unknown presets must not draw")
	var light := Atmosphere.warm_light(Vector2(10, 20), -2.0, 2.0)
	_expect(Vector2(light.position) == Vector2(10, 20), "warm light lost its position")
	_expect(float(light.radius) >= 4.0, "warm light radius is not floored")
	_expect(float(light.strength) <= 0.32, "warm light strength exceeds the restraint ceiling")
	var report := Atmosphere.atmosphere_report("arena", Rect2(Vector2.ZERO, Vector2(640, 360)), [light, {}, light])
	_expect(int(report.warm_lights.size()) == 2, "warm light report did not cap or reject malformed entries")

func _test_layer() -> void:
	var layer = AtmosphereLayerScript.new()
	layer.preset = "hamlet"
	layer.bounds = Rect2(Vector2.ZERO, Vector2(1024, 640))
	layer.warm_lights = [Atmosphere.warm_light(Vector2(504, 371), 53.0, 0.18)]
	root.add_child(layer)
	var report: Dictionary = layer.atmosphere_report()
	_expect(bool(report.valid), "layer did not accept a registered preset")
	_expect(layer.get_child_count() == 0, "atmosphere layer must not create children")
	_expect(layer is Node2D, "atmosphere layer must remain a Node2D drawing primitive")

func _test_hamlet() -> void:
	var hub := BaseHubScript.new()
	root.add_child(hub)
	hub._ready()
	var view := hub.get_hub_view()
	_expect(bool(hub.town_load_report.get("ok", false)), "town: native assets did not load")
	var audit := view.render_audit()
	_expect(audit.runtime_background_patches == 0 and audit.native_count == 35, "town: native environmental art is missing")
	_expect(view.world_presenter.get_parent().get_parent() == view.world_viewport, "town: shared world layers escaped the SubViewport")
	_expect(view.world_presenter.ground_layer.z_index < view.world_presenter.sort_root.z_index, "town: ground covered native buildings")
	_expect(audit.supports_fade and audit.supports_cutaway, "town: native art did not advertise its authored opacity effects")
	hub.free()

func _test_arena() -> void:
	var view = ArenaWorldViewScript.new()
	_expect(view.load_assets(), "arena: published assets did not load")
	view.begin_frame(Rect2(Vector2.ZERO, Vector2(1280, 720)), Vector2(430, 360), Rect2(Vector2(42, 190), Vector2(1196, 488)))
	var lights: Array = view.atmosphere_warm_lights()
	var report: Dictionary = view.atmosphere_report()
	_expect(lights.size() == 2, "arena: expected tower and ruin light sources")
	_expect(bool(report.world_lights_clipped), "arena: a light source leaves the authored world")
	_expect(Rect2(Vector2.ZERO, Vector2(1024, 640)).encloses(report.rect), "arena: atmosphere report leaves the world")
	for light in lights:
		_expect(float(light.strength) <= 0.20, "arena: warm strength exceeds the restrained combat budget")

func _test_hearth() -> void:
	var view = HearthReturnViewScript.new()
	root.add_child(view)
	_expect(view.load_scene(), "hearth: published return scene did not load")
	var scene: Dictionary = view.scene_report()
	var atmosphere: Dictionary = scene.atmosphere
	_expect(bool(atmosphere.valid), "hearth: atmosphere is invalid")
	_expect(int(atmosphere.warm_lights.size()) == 1, "hearth: expected exactly one fire-side warm light")
	_expect(view._atmosphere_layer.get_child_count() == 0, "hearth: atmosphere layer created children")
	_expect(view._atmosphere_layer.z_index == 0, "hearth: atmosphere must stay above the parent background")
	for layer: Dictionary in view._layers:
		_expect(layer.node.z_index > view._atmosphere_layer.z_index, "hearth: published actor must stay above atmosphere")
	_expect(view.get_child(0) == view._atmosphere_layer, "hearth: atmosphere was not inserted before published sprites")
