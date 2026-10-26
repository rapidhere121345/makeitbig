extends SceneTree
const Dressing := preload("res://src/presentation/world_dressing.gd")
const Icons := preload("res://src/presentation/combat_skill_icons.gd")
const Assert := preload("res://tests/helpers/assert.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var dressing := Dressing.new()
	_expect(dressing.load_assets(), dressing.pending_reason)
	for scene_id: String in ["town", "arena"]:
		var report := dressing.report(scene_id)
		_expect(report.ready and report.layer == "ground" and report.collision_bodies == 0, scene_id + " ground-only pack")
		_expect(int(report.count) == (32 if scene_id == "town" else 18), scene_id + " authored placement inventory")
		var copy: Array = report.placements
		copy.clear()
		_expect(int(dressing.report(scene_id).count) > 0, "reports cannot mutate live placements")
	var layer := dressing.create_town_layer()
	root.add_child(layer)
	await process_frame
	_expect(layer.get_child_count() == 0 and not layer.is_processing() and not layer.is_physics_processing(), "ground layer has no bodies, polling or simulation ticks")
	_expect(layer.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "native pixels preserved")
	var icons := Icons.new()
	_expect(icons.load_icons(), icons.pending_reason)
	var drawings := {}
	for id: String in Icons.SLOT_ICON_IDS:
		var icon := icons.icon(id) as AtlasTexture
		_expect(icon != null and icon.get_size() == Vector2(32, 32), id + " production icon binding")
		if icon == null:
			continue
		var image := icon.get_image()
		_expect(image.get_used_rect().size.x >= 16 and image.get_used_rect().size.y >= 16, id + " readable native silhouette")
		var hash_value := image.get_data().hex_encode().sha256_text()
		_expect(not drawings.has(hash_value), id + " distinct action silhouette")
		drawings[hash_value] = true
	layer.free()
	if failures.is_empty():
		print("PASS test_world_dressing.gd: 50 ground placements, four distinct native skill icons")
	else:
		printerr("FAIL test_world_dressing.gd ", failures)
	quit(0 if failures.is_empty() else 1)

func _expect(value: bool, message: String) -> void: Assert.expect(value, message, failures)
