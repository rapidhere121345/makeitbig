extends SceneTree
## Bounded acceptance check for the R11 scene-atmosphere package.
## Headless-safe: it validates the presentation contract, node placement and
## drawing budgets without launching the whole game or capturing pixels.
##
## Run:
##   GODOT --headless --path . --script res://tests/test_scene_atmosphere.gd

const Atmosphere = preload("res://src/presentation/scene_atmosphere.gd")
const AtmosphereLayerScript = preload("res://src/presentation/scene_atmosphere_layer.gd")
const BaseHubScript = preload("res://src/presentation/base_hub_screen.gd")
const ArenaWorldViewScript = preload("res://src/presentation/arena_world_view.gd")
const HearthReturnViewScript = preload("res://src/presentation/hearth_return_view.gd")

var failures: Array[String] = []
var output_dir := ""
var captures: Array[Dictionary] = []

func _initialize() -> void:
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
	await _capture_hamlet()
	await _capture_hearth()
	await _capture_arena()
	var report := {"status":"pass" if failures.is_empty() else "fail", "errors":failures, "captures":captures, "fixture_note":"Isolated published scene views, fixed lighting toggles; not a playable combat test."}
	var file := FileAccess.open(output_dir.path_join("REPORT.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("R11_LIGHTING_GPU ",report.status," captures=",captures.size())
	quit(0 if failures.is_empty() else 1)

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
	_expect(not audit.supports_fade and not audit.supports_cutaway, "town: transparent underplate advertises opacity effects")
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
