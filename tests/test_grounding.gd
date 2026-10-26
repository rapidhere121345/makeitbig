extends SceneTree
const Effects := preload("res://src/presentation/grounding_effects.gd")
const Hub := preload("res://src/presentation/base_hub_screen.gd")
const Assert := preload("res://tests/helpers/assert.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_contour()
	_test_light_budget()
	_test_cache_bound()
	var hub := Hub.new()
	root.add_child(hub)
	await process_frame
	_expect(bool(hub.town_load_report.get("ok", false)), "production town mounts")
	if bool(hub.town_load_report.get("ok", false)):
		var view = hub.get_hub_view()
		var town = hub.get_town_runtime()
		var before: Dictionary = town.snapshot()
		view.consume(before)
		var report: Dictionary = view.grounding_report()
		_expect(report.base_count == view.world_presenter.sort_root.get_child_count() - 6, "every native sortable object grounded; actors separate")
		_expect(report.actors.size() == 6 and report.lights.size() >= 12, "hero, five residents and authored light sources")
		_expect(report.actors[0].feet == town.hero_world_position(), "hero shadow follows authoritative feet")
		var layer: Node2D = view._grounding_layer
		_expect(layer.get_parent() == view.world_presenter.ground_effects_layer, "shadows share native world camera transform")
		_expect(layer.get_parent().z_index > view.world_presenter.ground_layer.z_index and layer.get_parent().z_index < view.world_presenter.sort_root.z_index, "receiver above bridge deck and below actor/scenery")
		for actor: Dictionary in report.actors:
			var node: Sprite2D = view._actor_sprite_of(actor.id)
			_expect(node.position == actor.feet and node.self_modulate.a == 1.0 and node.modulate.a == 1.0, "opaque actor anchored " + String(actor.id))
		var lamp: Sprite2D = view.world_presenter.native_binding_node("town/native/lamp_0")
		_expect(lamp.self_modulate.r > lamp.self_modulate.b and lamp.self_modulate.a == 1.0, "warm source illuminates sprite RGB without alpha")
		_expect(town.snapshot() == before, "presentation cannot change authority")
		# Camera changes must not move source positions or foot contacts in world space.
		var moved := before.duplicate(true)
		moved["hero_screen_anchor"] = Vector2(160, 120)
		var prior_camera: Vector2 = view.camera_world_offset()
		view.consume(moved)
		_expect(view.camera_world_offset() != prior_camera, "camera probe actually changes framing")
		_expect(view.grounding_report().actors == report.actors, "camera-independent shadow feet")
		var controller = hub._town_controller
		if controller.scene_runtime != null:
			controller.scene_runtime.simulation.kernel.shutdown()
	hub.free()
	for failure: String in failures:
		printerr(failure)
	print("GROUNDING ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)

func _test_contour() -> void:
	var source := Image.create(32, 48, false, Image.FORMAT_RGBA8)
	# A high, detached canopy must not produce a base seam at its own height.
	source.fill_rect(Rect2i(1, 2, 30, 5), Color.WHITE)
	source.fill_rect(Rect2i(12, 25, 8, 19), Color.WHITE)
	var bytes := source.get_data()
	var texture := ImageTexture.create_from_image(source)
	var stamp := Effects.base_stamp(texture, Rect2(0, 0, 32, 48), Vector2(16, 44))
	_expect(not stamp.is_empty(), "non-empty contact mask")
	if stamp.is_empty():
		return
	var image: Image = stamp.texture.get_image()
	var visible := image.get_used_rect()
	var world_top := float(visible.position.y) + (stamp.offset as Vector2).y
	_expect(world_top >= -3.0 and world_top <= 0.0, "shadow starts at real lowest contact, not canopy or cell top")
	_expect(visible.size.x < 24, "trunk shadow excludes detached canopy width")
	_expect(texture.get_image().get_data() == bytes, "source pixels untouched")
	_expect(Effects.base_stamp(texture, Rect2(0, 0, 32, 48), Vector2(16, 44)).texture == stamp.texture, "static mask reused across frames")
	var clipped := Effects.base_stamp(texture, Rect2(-4, -3, 36, 51), Vector2(20, 47))
	_expect(clipped.offset == stamp.offset, "clipping source region preserves visible base position")
	_expect(clipped.texture.get_image().get_data() == image.get_data(), "clipped region draws same contact mask")

func _test_cache_bound() -> void:
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	for index in 140:
		var texture := ImageTexture.create_from_image(image)
		Effects.base_stamp(texture, Rect2(0, 0, 4, 4), Vector2(2, 3))
	_expect(Effects._bases.size() <= Effects.MAX_BASE_STAMPS, "repeated resource reloads cannot retain unbounded GPU masks")

func _test_light_budget() -> void:
	var lights: Array = [{"position": Vector2.ZERO, "radius": 40.0, "color": Effects.AMBER, "strength": 0.25}]
	var warm := Effects.illumination(Vector2.ZERO, lights)
	_expect(warm.r > warm.g and warm.g > warm.b and warm.a == 1.0, "warm RGB response preserves alpha")
	_expect(Effects.illumination(Vector2(80, 0), lights) == Color.WHITE, "no world-wide light wash")
	_expect(Effects.illumination(Vector2(0, 20), lights) == Color.WHITE, "sprite outside vertical pool receives no stray illumination")
	for index in 40:
		lights.append(lights[0])
	var crowded := Effects.illumination(Vector2.ZERO, lights)
	_expect(crowded.r <= 1.161 and crowded.g <= 1.131 and crowded.b <= 1.121 and crowded.a == 1.0, "overlapping sources keep readability budget")

func _expect(value: bool, message: String) -> void: Assert.expect(value, message, failures)
