extends SceneTree

const NativeScene := preload("res://content/rooms/town/hearthside.tscn")
const Spatial := preload("res://src/runtime/world/spatial_manifest.gd")
const Runtime := preload("res://src/runtime/world/scene_runtime.gd")
const MANIFEST_PATH := "res://content/rooms/town/hearthside.spatial.json"
var failures: Array[String] = []
var negative_cases := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var manifest_sha := FileAccess.get_sha256(MANIFEST_PATH)
	var scene_sha := FileAccess.get_sha256(NativeScene.resource_path)
	_test_current_scene()
	_test_transform_rejections()
	_test_leaf_positions()
	_test_mount_rejects_transformed_source()
	_expect(FileAccess.get_sha256(MANIFEST_PATH) == manifest_sha, "test changed baked manifest")
	_expect(FileAccess.get_sha256(NativeScene.resource_path) == scene_sha, "test changed native scene")
	for failure: String in failures:
		printerr("FAIL: " + failure)
	if failures.is_empty():
		print("PASS test_town_native_contract.gd negative_cases=%d native_manifest_unchanged=true" % negative_cases)
	quit(0 if failures.is_empty() else 1)


func _test_current_scene() -> void:
	var scene := NativeScene.instantiate()
	var report: Dictionary = scene.validate_contract()
	_expect(bool(report.ok), "current town rejected: " + str(report.errors))
	var derived: Dictionary = scene.derive_spatial_manifest()
	var baked: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	_expect(Spatial.new(derived).is_valid(), "current derivative invalid")
	_expect(Spatial.new(derived).digest_input() == Spatial.new(baked).digest_input(), "native derivative drifted from current baked manifest")
	scene.free()


func _test_transform_rejections() -> void:
	var sample := NativeScene.instantiate()
	var containers: Array[String] = [".", "GeometrySources", "GeometrySources/MovementBoundary", "GeometrySources/Static", "GeometrySources/Routes", "Sockets"]
	for route: Node in sample.get_node("GeometrySources/Routes").get_children():
		containers.append(String(sample.get_path_to(route)))
	var leaves: Array[String] = []
	# Both circle metadata sources and polygon sources use the same transform contract.
	var circle := ""
	var polygon := ""
	for shape: Node in sample.get_node("GeometrySources/Static").get_children():
		if shape.has_meta("radius") and circle.is_empty():
			circle = String(sample.get_path_to(shape))
		elif not shape.has_meta("radius") and polygon.is_empty():
			polygon = String(sample.get_path_to(shape))
	_expect(not circle.is_empty() and not polygon.is_empty(), "fixture needs both static source kinds")
	leaves.append_array([circle, polygon])
	for socket: Node in sample.get_node("Sockets").get_children():
		leaves.append(String(sample.get_path_to(socket)))
	for route: Node in sample.get_node("GeometrySources/Routes").get_children():
		leaves.append(String(sample.get_path_to(route.get_child(0))))
	sample.free()
	for path: String in containers + leaves:
		var mutations: Array[String] = ["rotation", "scale", "reflection", "collapse", "skew", "top_level"]
		if path in containers:
			mutations.append("position")
		for property: String in mutations:
			var scene := NativeScene.instantiate()
			var node := scene.get_node(path) as Node2D
			match property:
				"rotation": node.rotation = 0.25
				"scale": node.scale = Vector2(2, 1)
				"reflection": node.scale = Vector2(-1, 1)
				"collapse": node.scale = Vector2.ZERO
				"skew": node.skew = 0.2
				"top_level": node.set_as_top_level(true)
				"position": node.position += Vector2(8, 4)
			_expect_rejected(scene, "unsupported_native_transform:" + path, path + "/" + property)
			scene.free()
	var scene := NativeScene.instantiate()
	(scene.get_node(polygon) as Polygon2D).offset = Vector2(4, 0)
	_expect_rejected(scene, "unsupported_native_polygon_offset:" + polygon, "polygon offset")
	scene.free()


func _expect_rejected(scene: Node, expected_error: String, label: String) -> void:
	var derived: Dictionary = scene.derive_spatial_manifest()
	_expect(derived.get("ok", true) == false and derived.get("value", {"unexpected": true}).is_empty(), label + ": derive published data")
	_expect(expected_error in derived.get("errors", []), label + ": derive omitted source error: " + str(derived))
	var report: Dictionary = scene.validate_contract()
	_expect(not bool(report.ok) and report.value.is_empty() and expected_error in report.errors, label + ": contract accepted source: " + str(report))
	negative_cases += 1


func _test_leaf_positions() -> void:
	var scene := NativeScene.instantiate()
	var original: Dictionary = scene.derive_spatial_manifest()
	# These translations are already represented by the derivative. Do not ban
	# author positions just because ancestor transforms are unsupported.
	for shape: Node2D in scene.get_node("GeometrySources/Static").get_children():
		shape.position += Vector2(8, 4)
	for socket: Node2D in scene.get_node("Sockets").get_children():
		socket.position += Vector2(8, 4)
	for route: Node in scene.get_node("GeometrySources/Routes").get_children():
		for point: Node2D in route.get_children():
			point.position += Vector2(8, 4)
	var report: Dictionary = scene.validate_contract()
	_expect(bool(report.ok), "legal leaf positions rejected: " + str(report.errors))
	var changed: Dictionary = scene.derive_spatial_manifest()
	_expect(Spatial.new(changed).is_valid(), "translated derivative invalid")
	_expect(changed.spawn_interaction_exit_sockets[0].position != original.spawn_interaction_exit_sockets[0].position, "socket position ignored")
	_expect(changed.gameplay_spatial_metadata.static_geometry != original.gameplay_spatial_metadata.static_geometry, "static positions ignored")
	_expect(changed.gameplay_spatial_metadata.routes != original.gameplay_spatial_metadata.routes, "route point positions ignored")
	scene.free()


func _test_mount_rejects_transformed_source() -> void:
	var scene := NativeScene.instantiate()
	scene.get_node("GeometrySources/Static").position = Vector2(16, 0)
	var packed := PackedScene.new()
	_expect(packed.pack(scene) == OK, "negative scene packing failed")
	scene.free()
	var runtime := Runtime.new()
	root.add_child(runtime)
	var report: Dictionary = runtime.mount(
		{"room_id": "town/hearthside", "world_asset_id": "town/hearthside", "encounter_id": "town/exploration", "ruleset_id": "town/v1", "tags": ["town"]},
		{"world_scene_path": NativeScene.resource_path, "manifest_path": MANIFEST_PATH, "gameplay_digest": "test", "presentation_digest": "test", "schema_version": 1},
		packed)
	_expect(not bool(report.ok) and report.error == "native_scene_contract_invalid", "mount accepted transformed geometry: " + str(report))
	_expect(not runtime.is_ready() and runtime.mounted_scene == null, "invalid native scene reached READY")
	runtime.free()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
