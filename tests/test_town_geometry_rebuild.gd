extends SceneTree
const TownControllerScript := preload("res://src/runtime/world/town_controller.gd")
const NativeScene := preload("res://content/rooms/town/hearthside.tscn")
const Spatial := preload("res://src/runtime/world/spatial_manifest.gd")
const SpatialChannels := preload("res://src/runtime/spatial/spatial_channels.gd")
var failures: Array[String] = []
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var controller := TownControllerScript.new()
	root.add_child(controller)
	var mounted := controller.mount(controller)
	_expect(bool(mounted.get("ok", false)), "production native mount failed: " + str(mounted))
	if bool(mounted.get("ok", false)):
		var registry: Variant = controller.scene_runtime.actor_registry
		var town = controller.town
		_expect(registry == town.registry and registry.has_movement_boundary(), "native geometry did not use the injected registry")
		_expect(controller.scene_runtime.static_spatial_index.surface_ids(SpatialChannels.MOVEMENT).size() > 100, "native convex shapes missing")
		var spatial: Dictionary = controller.scene_runtime.manifest.snapshot()
		var source := NativeScene.instantiate()
		_expect(Spatial.new(source.derive_spatial_manifest()).digest_input() == controller.scene_runtime.manifest.digest_input(), "native source and offline manifest differ")
		var native: Variant = source.get_node("SortRoot/contract")
		native.set_meta("texture_path", "res://content/rooms/town/layers/not-delivered.png")
		var broken: Dictionary = source.validate_contract()
		_expect(not broken.ok and str(broken.errors).contains("missing_native_texture"), "missing native asset was silently accepted")
		source.free()
		for id: String in town._content.routes:
			for point: Vector2 in town.route_points(id):
				_expect(town.hero_position_is_clear(point), "route waypoint blocked: %s %s" % [id, point])
	# Sever the kernel -> port -> access -> registry borrow cycle before the
	# mounted town runtime is freed, so its room graph cannot leak at exit.
	if controller.scene_runtime != null and controller.scene_runtime.simulation != null and controller.scene_runtime.simulation.kernel != null:
		controller.scene_runtime.simulation.kernel.shutdown()
	controller.free()
	for failure: String in failures: printerr(failure)
	print("TOWN_GEOMETRY_REBUILD ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
func _expect(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
