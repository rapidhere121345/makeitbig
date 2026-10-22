extends SceneTree
## Reproducible technical integration preview, NOT hometown art acceptance.
## Run on a rendering display:
## GODOT --path . --script res://tools/modular_town_preview.gd
## Output must be fresh; override with -- --output=res://build/current/another-round

const Definition := preload("res://src/runtime/world/environment_object_definition.gd")
const Placement := preload("res://src/runtime/world/environment_object_placement.gd")
const Baker := preload("res://src/runtime/world/environment_object_baker.gd")
const TownRoot := preload("res://src/runtime/world/town_scene_root.gd")
const TownControllerScript := preload("res://src/runtime/world/town_controller.gd")
const TownView := preload("res://src/presentation/town_presenter.gd")

var output := "res://build/current/modular-town-preview-r2"
var errors: Array[String] = []
var frames: Array[Dictionary] = []
var checks: Array[Dictionary] = []
var controller
var view
var caption: Label


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name().to_lower().contains("headless"):
		printerr("GPU SKIP: modular town preview requires a rendering display")
		quit(2)
		return
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			output = argument.trim_prefix("--output=")
	if not output.begins_with("res://build/") or ".." in output or DirAccess.dir_exists_absolute(output):
		printerr("PREVIEW REJECTED: fresh res://build/ output required")
		quit(2)
		return
	if DirAccess.make_dir_recursive_absolute(output) != OK:
		printerr("PREVIEW REJECTED: cannot create output")
		quit(2)
		return
	root.size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	if not _author_scene():
		_finish()
		return
	view = TownView.new()
	root.add_child(view)
	view.set_process(false)
	controller = TownControllerScript.new()
	root.add_child(controller)
	var mounted: Dictionary = controller.mount(view.world_viewport, output.path_join("preview.tscn"), output.path_join("preview.spatial.json"))
	_check(bool(mounted.get("ok", false)), "production_mount", mounted)
	if not errors.is_empty():
		_finish()
		return
	var loaded: Dictionary = view.load_character_assets()
	_check(bool(loaded.get("ok", false)), "real_character_assets", loaded)
	var attached: Dictionary = view.attach(controller.scene_runtime.presenter, controller.town.snapshot(), controller.scene_runtime)
	_check(bool(attached.get("ok", false)), "production_presenter_attach", attached)
	if not errors.is_empty():
		_finish()
		return
	view.set_world_scale(2, Vector2(1280, 720))
	caption = Label.new()
	caption.position = Vector2(16, 8)
	caption.add_theme_font_size_override("font_size", 18)
	caption.add_theme_color_override("font_color", Color("fff4c2"))
	caption.add_theme_color_override("font_shadow_color", Color.BLACK)
	caption.add_theme_constant_override("shadow_offset_x", 2)
	caption.add_theme_constant_override("shadow_offset_y", 2)
	root.add_child(caption)
	await _walkthrough()
	_finish()


func _author_scene() -> bool:
	var ground := _blank(Vector2i(960, 640), Color("666d66"))
	for y in range(0, 640, 32):
		ground.fill_rect(Rect2i(0, y, 960, 1), Color("747b70"))
	for x in range(0, 960, 32):
		ground.fill_rect(Rect2i(x, 0, 1, 640), Color("747b70"))
	ground.fill_rect(Rect2i(12, 352, 936, 88), Color("938977"))
	ground.fill_rect(Rect2i(568, 12, 64, 616), Color("938977"))
	_outline(ground, Rect2i(206, 276, 140, 56), Color("e4bb67"))
	_outline(ground, Rect2i(212, 282, 128, 44), Color("aa6657"))
	for center: Vector2 in [Vector2(528, 338), Vector2(698, 428)]:
		_disc(ground, center, 21, Color("e4bb67"))
		_disc(ground, center, 14, Color("aa6657"))
	for box: Rect2i in [Rect2i(400, 478, 160, 20), Rect2i(640, 478, 160, 20)]:
		_outline(ground, box, Color("e4bb67"))
	var ground_path := _texture("ground", ground)
	var building := _building()
	var tree := _tree()
	var fence := _fence()
	var source := TownRoot.new()
	source.name = "GreyboxTown"
	source.world_size = Vector2(960, 640)
	source.modular_environment_objects = true
	source.modular_underplate_path = ground_path
	source.gameplay_source = "preview.spatial.json"
	for group: String in ["Ground", "GroundEffects", "SortRoot", "Foreground", "GeometrySources", "Sockets", "EnvironmentObjects"]:
		_add_node(source, group)
	source.get_node("SortRoot").y_sort_enabled = true
	for group: String in ["Static", "Routes", "MovementBoundary"]:
		_add_node(source.get_node("GeometrySources"), group)
	source.get_node("GeometrySources/MovementBoundary").set_meta("rect", Rect2(12, 12, 936, 616))
	source.get_node("GeometrySources/MovementBoundary").set_meta("binding_id", "town/movement-boundary")
	var lower := Definition.new()
	lower.asset_id = "greybox.continuous-ground"
	lower.canvas_size = Vector2i(960, 640)
	lower.ground_parts = [{"part_id": "underplate", "full_path": ground_path, "canvas_offset": Vector2.ZERO, "layer": "Ground"}]
	_place(source, "ground", lower, Vector2.ZERO)
	_place(source, "building", building, Vector2(180, 180))
	_place(source, "tree-west", tree, Vector2(480, 210))
	_place(source, "tree-east", tree, Vector2(650, 300))
	_place(source, "gate-fence", fence, Vector2(400, 460))
	_socket(source, "Spawn", "spawn", "town/spawn", "spawn", Vector2(260, 180))
	_socket(source, "Contract", "interaction", "greybox/contract", "contract", Vector2(600, 540))
	var expanded := Baker.expand(source)
	_check(expanded.ok, "environment_baker_expand", expanded)
	var contract := source.validate_contract()
	_check(contract.ok, "native_author_contract", {"errors": contract.errors})
	if errors.is_empty():
		_own_children(source, source)
		var packed := PackedScene.new()
		_check(packed.pack(source) == OK, "pack_owned_native_scene")
		_check(ResourceSaver.save(packed, output.path_join("preview.tscn")) == OK, "save_native_scene")
		var manifest := source.derive_spatial_manifest()
		var file := FileAccess.open(output.path_join("preview.spatial.json"), FileAccess.WRITE)
		file.store_string(JSON.stringify(manifest, "\t"))
	source.free()
	return errors.is_empty()


func _building() -> Resource:
	var definition := Definition.new()
	definition.asset_id = "greybox.building"
	definition.canvas_size = Vector2i(192, 160)
	var common := _blank(definition.canvas_size)
	common.fill_rect(Rect2i(32, 98, 128, 48), Color("b7ad91"))
	common.fill_rect(Rect2i(40, 108, 28, 20), Color("5f777d"))
	common.fill_rect(Rect2i(124, 108, 28, 20), Color("5f777d"))
	common.fill_rect(Rect2i(83, 110, 26, 36), Color("574b43"))
	var full := _blank(definition.canvas_size)
	var polygon := PackedVector2Array([Vector2(8, 96), Vector2(44, 16), Vector2(148, 16), Vector2(184, 96)])
	for y in range(16, 97):
		for x in range(8, 185):
			if Geometry2D.is_point_in_polygon(Vector2(x, y), polygon):
				full.set_pixel(x, y, Color("81584e") if y % 12 > 1 else Color("a0775d"))
	var revealed := _blank(definition.canvas_size)
	# Low structural stubs join the unchanged wall. A retained high beam
	# crossed the hero's torso in the preceding visual review.
	revealed.fill_rect(Rect2i(32, 84, 6, 14), Color("887052"))
	revealed.fill_rect(Rect2i(154, 84, 6, 14), Color("887052"))
	revealed.fill_rect(Rect2i(30, 82, 10, 4), Color("a0775d"))
	revealed.fill_rect(Rect2i(152, 82, 10, 4), Color("a0775d"))
	definition.visual_parts = [
		_visual("common", _texture("building_common", common), Vector2(96, 146)),
		_visual("upper", _texture("building_upper", full), Vector2(96, 110), _texture("building_revealed", revealed), _texture("building_mask", full)),
	]
	definition.footprints = [_polygon_shape("contact", Rect2(32, 102, 128, 44))]
	definition.movement_envelopes = [_polygon_shape("envelope", Rect2(26, 96, 140, 56))]
	return definition


func _tree() -> Resource:
	var definition := Definition.new()
	definition.asset_id = "greybox.tree-shared-definition"
	definition.canvas_size = Vector2i(96, 144)
	var trunk := _blank(definition.canvas_size)
	trunk.fill_rect(Rect2i(43, 52, 10, 85), Color("887052"))
	trunk.fill_rect(Rect2i(30, 66, 36, 6), Color("887052"))
	trunk.fill_rect(Rect2i(38, 132, 20, 6), Color("887052"))
	var canopy := _blank(definition.canvas_size)
	_disc(canopy, Vector2(48, 48), 43, Color("344e49"))
	_disc(canopy, Vector2(40, 40), 30, Color("4f6e5a"))
	canopy.fill_rect(Rect2i(44, 10, 8, 22), Color.TRANSPARENT)
	var revealed := _blank(definition.canvas_size)
	# Revealing only the complete common trunk avoids isolated leaf strips.
	definition.visual_parts = [
		_visual("common", _texture("tree_common", trunk), Vector2(48, 128)),
		_visual("upper", _texture("tree_upper", canopy), Vector2(48, 128), _texture("tree_revealed", revealed), _texture("tree_mask", canopy)),
	]
	definition.footprints = [{"part_id": "contact", "type": "circle", "center": Vector2(48, 128), "radius": 10.0}]
	definition.movement_envelopes = [{"part_id": "envelope", "type": "circle", "center": Vector2(48, 128), "radius": 14.0}]
	return definition


func _fence() -> Resource:
	var definition := Definition.new()
	definition.asset_id = "greybox.open-gate"
	definition.canvas_size = Vector2i(400, 64)
	var image := _blank(definition.canvas_size)
	for x: int in [0, 240]:
		image.fill_rect(Rect2i(x, 22, 160, 5), Color("c2b18a"))
		image.fill_rect(Rect2i(x, 8, 160, 5), Color("c2b18a"))
		for post in range(x, x + 160, 20):
			image.fill_rect(Rect2i(post, 2, 6, 36), Color("9c8463"))
	definition.visual_parts = [_visual("rails", _texture("gate_fence", image), Vector2(200, 36))]
	definition.footprints = [_polygon_shape("contact-left", Rect2(0, 24, 160, 8)), _polygon_shape("contact-right", Rect2(240, 24, 160, 8))]
	definition.movement_envelopes = [_polygon_shape("envelope-left", Rect2(0, 18, 160, 20)), _polygon_shape("envelope-right", Rect2(240, 18, 160, 20))]
	return definition


func _walkthrough() -> void:
	_advance(Vector2.ZERO, 1.0 / 30.0)
	await _capture("01_full")
	for index in range(30):
		_advance(Vector2.DOWN, 1.0 / 30.0)
		var weight := _weight("building/upper")
		if weight > 0.0 and weight < 1.0:
			await _capture("02_mid")
			break
		await process_frame
	_check(_weight("building/upper") > 0.0 and _weight("building/upper") < 1.0, "mounted_intermediate_reveal")
	await _move(Vector2.DOWN, 0.4, 60)
	_check(_weight("building/upper") == 1.0, "mounted_building_open", view.occlusion_report())
	await _capture("03_open")
	var deadline := Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < deadline:
		_advance(Vector2.ZERO, 1.0 / 60.0)
		if _weight("building/upper") != 1.0:
			_check(false, "mounted_hold_lost_reveal", view.occlusion_report())
			break
		await process_frame
	await _capture("04_held")
	await _move(Vector2.RIGHT, 2.0, 60)
	await _move(Vector2.ZERO, 0.3, 60)
	_check(_weight("building/upper") == 0.0, "mounted_building_closed")
	await _capture("05_closed_pan")
	_place_hero(Vector2(260, 370))
	await _move(Vector2.UP, 1.0, 60)
	var blocked: Vector2 = controller.town.hero_world_position()
	_check(blocked.y >= 337.9 and blocked.y < 350, "building_movement_envelope_stops_actor", {"feet": _pair(blocked)})
	await _capture("06_near_blocker")
	_place_hero(Vector2(562, 305))
	await _move(Vector2.ZERO, 0.3, 60)
	await _capture("07_tree_behind_baseline")
	await _move(Vector2.DOWN, 0.5, 60)
	_check(controller.town.hero_world_position().y > 338, "tree_baseline_crossed_with_ticks")
	await _capture("08_tree_front_baseline")
	await _move(Vector2.RIGHT, 1.4, 60)
	_check(view.camera_world_offset().x > 300, "production_camera_pan", {"camera": _pair(view.camera_world_offset())})
	await _capture("09_second_tree_camera_pan")
	_place_hero(Vector2(520, 440))
	await _move(Vector2.DOWN, 0.8, 60)
	_check(controller.town.hero_world_position().y < 473, "fence_blocks_outside_gate")
	await _capture("10_fence_blocker")
	var endpoints: Array[Vector2] = []
	for fps: int in [30, 120]:
		_place_hero(Vector2(600, 440))
		var initial_tick: int = controller.town.snapshot().tick
		await _move(Vector2.DOWN, 1.0, fps)
		var through: Vector2 = controller.town.hero_world_position()
		_check(through.y > 530, "gate_passage_%dfps" % fps, {"feet": _pair(through)})
		await _capture("11_gate_passage_%dfps" % fps)
		await _move(Vector2.UP, 1.0, fps)
		var reversed: Vector2 = controller.town.hero_world_position()
		endpoints.append(reversed)
		_check(reversed.distance_to(Vector2(600, 440)) < 0.02, "gate_reversal_%dfps" % fps, {"feet": _pair(reversed)})
		_check(controller.town.snapshot().tick - initial_tick == 60, "fixed_tick_trace_%dfps" % fps)
		await _capture("12_gate_reversal_%dfps" % fps)
	_check(endpoints[0].distance_to(endpoints[1]) < 0.02, "30_120fps_endpoint_equivalence")


func _advance(direction: Vector2, delta: float) -> void:
	var result: Dictionary = controller.advance_frame(direction, delta)
	if not bool(result.get("ok", false)):
		errors.append("authoritative_move_failed:" + str(result))
	view.consume(controller.town.snapshot())
	view._process(delta)


func _move(direction: Vector2, seconds: float, fps: int) -> void:
	for frame in range(roundi(seconds * fps)):
		_advance(direction, 1.0 / fps)
		await process_frame


func _place_hero(point: Vector2) -> void:
	var placed: Dictionary = controller.town.place_hero(point)
	_check(bool(placed.get("ok", false)), "place_valid_trace_start", {"feet": _pair(point), "result": placed})
	_advance(Vector2.ZERO, 1.0 / 30.0)


func _weight(id: String) -> float:
	return float(view.occlusion_report().get("authored_reveal", {}).get(id, {}).get("weight", -1.0))


func _capture(name: String) -> void:
	caption.text = "GREYBOX / RENDERER INTEGRATION ONLY / " + name + " / 2x pixels"
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := output.path_join(name + ".png")
	_check(image != null and not image.is_empty() and image.save_png(path) == OK, "capture_" + name)
	var frame := {"name": name, "feet": _pair(controller.town.hero_world_position()),
		"camera": _pair(view.camera_world_offset()), "tick": controller.town.snapshot().tick,
		"occlusion": view.occlusion_report(), "sha256": FileAccess.get_sha256(path)}
	frames.append(frame)
	print("GREYBOX_FRAME ", JSON.stringify(frame))


func _check(ok: bool, name: String, detail: Dictionary = {}) -> void:
	checks.append({"check": name, "ok": ok, "detail": detail})
	if not ok:
		errors.append(name + ": " + JSON.stringify(detail))
		printerr("GREYBOX_FAIL ", name, " ", detail)


func _finish() -> void:
	var report := {"status": "pass" if errors.is_empty() else "fail",
		"classification": "GREYBOX TECHNICAL PREVIEW ONLY - NOT production-art acceptance",
		"display": OS.get_environment("DISPLAY"), "audio": "Dummy (launch contract)",
		"renderer": RenderingServer.get_video_adapter_name(),
		"godot": Engine.get_version_info().string, "exit_code": 0 if errors.is_empty() else 1,
		"source_scene": output.path_join("preview.tscn"), "source_manifest": output.path_join("preview.spatial.json"),
		"checks": checks, "errors": errors, "frames": frames}
	var file := FileAccess.open(output.path_join("REPORT.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	var note := FileAccess.open(output.path_join("VISUAL_REPORT.txt"), FileAccess.WRITE)
	note.store_string("GREYBOX technical renderer preview, not hometown art acceptance.\n"
		+ "Generated continuous opaque ground; building common/upper/revealed parts;\n"
		+ "two translated instances of one tree definition; open gate and fence.\n"
		+ "Yellow ground markings show movement margins, rust marks show contact.\n"
		+ "Uses native SceneRuntime, projector, TownPresenter, real ranger, and fixed ticks.\n"
		+ "Screenshots require human inspection; numeric checks alone do not establish visual quality.\n"
		+ "Result: " + report.status + "\nErrors: " + str(errors) + "\n")
	note.close()
	print("MODULAR_TOWN_PREVIEW ", report.status, " output=", output)
	quit(report.exit_code)


func _texture(name: String, image: Image) -> String:
	var path := output.path_join(name + ".res")
	_check(ResourceSaver.save(ImageTexture.create_from_image(image), path) == OK, "save_texture_" + name)
	_check(image.save_png(output.path_join(name + "_source.png")) == OK, "save_source_" + name)
	return path


func _blank(size: Vector2i, color := Color.TRANSPARENT) -> Image:
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return image


func _outline(image: Image, rect: Rect2i, color: Color) -> void:
	image.fill_rect(Rect2i(rect.position, Vector2i(rect.size.x, 2)), color)
	image.fill_rect(Rect2i(rect.position.x, rect.end.y - 2, rect.size.x, 2), color)
	image.fill_rect(Rect2i(rect.position, Vector2i(2, rect.size.y)), color)
	image.fill_rect(Rect2i(rect.end.x - 2, rect.position.y, 2, rect.size.y), color)


func _disc(image: Image, center: Vector2, radius: float, color: Color) -> void:
	for y in range(maxi(0, int(center.y - radius)), mini(image.get_height(), int(center.y + radius + 1))):
		for x in range(maxi(0, int(center.x - radius)), mini(image.get_width(), int(center.x + radius + 1))):
			if Vector2(x, y).distance_to(center) <= radius:
				image.set_pixel(x, y, color)


func _visual(id: String, path: String, anchor: Vector2, variant := "", mask := "") -> Dictionary:
	var part := {"part_id": id, "full_path": path, "canvas_offset": Vector2.ZERO, "sort_anchor": anchor, "sort_rank": 0}
	if not variant.is_empty():
		part.merge({"revealed_path": variant, "mask_path": mask})
	return part


func _polygon_shape(id: String, rect: Rect2) -> Dictionary:
	return {"part_id": id, "type": "polygon", "points": PackedVector2Array([
		rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])}


func _add_node(parent: Node, name: String) -> Node2D:
	var node := Node2D.new()
	node.name = name
	parent.add_child(node)
	return node


func _place(source: Node, id: String, definition: Resource, position: Vector2) -> void:
	var placement := Placement.new()
	placement.name = id
	placement.placement_id = id
	placement.definition = definition
	placement.position = position
	source.get_node("EnvironmentObjects").add_child(placement)


func _socket(source: Node, name: String, kind: String, binding: String, id: String, position: Vector2) -> void:
	var socket := Marker2D.new()
	socket.name = name
	socket.position = position
	for key: String in ["kind", "binding_id", "id", "label", "radius"]:
		socket.set_meta(key, {"kind": kind, "binding_id": binding, "id": id, "label": "GREYBOX contract", "radius": 32.0}[key])
	source.get_node("Sockets").add_child(socket)


func _own_children(parent: Node, owner_root: Node) -> void:
	for child: Node in parent.get_children():
		child.owner = owner_root
		_own_children(child, owner_root)


func _pair(point: Vector2) -> Array:
	return [point.x, point.y]
