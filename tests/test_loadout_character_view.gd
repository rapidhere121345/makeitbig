extends SceneTree

const Preview := preload("res://src/presentation/loadout_character_view.gd")
const CREST_PATH := "res://art/production/p1/ui_crafted_v01/crest.png"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	var preview := Preview.new()
	root.add_child(preview)
	preview.refresh()
	var report := preview.frame_report()
	_expect(report.drawing and report.clip == "ranger.east.idle" and report.frame == 0,
		"preview lost the published static Ranger pose", failures)
	_expect(report.cell == [48, 48] and report.anchor == [24, 44]
		and report.display_scale == 4 and report.display_pixels == [192, 192]
		and String(report.render_texture_path).ends_with("actors_v02/ranger.png"),
		"crafted decoration changed the native actor cell, scale, art, or foot anchor", failures)
	_expect(preview.custom_minimum_size == Vector2(192, 192)
		and preview.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST,
		"crafted decoration changed preview sizing or pixel filtering", failures)
	var crest := preview.get_node_or_null("RangerCrest") as TextureRect
	_expect(crest != null and crest.texture != null and crest.visible,
		"published crafted crest did not load", failures)
	if crest != null and crest.texture != null:
		var authored := Image.new()
		var image_error := authored.load_png_from_buffer(FileAccess.get_file_as_bytes(CREST_PATH))
		_expect(image_error == OK and authored.get_size() == Vector2i(160, 160)
			and crest.texture.get_image().get_data() == authored.get_data(),
			"preview crest differs from the published 160px material", failures)
		_expect(crest.show_behind_parent and crest.self_modulate.a >= 0.5
			and crest.self_modulate.a <= 0.8 and preview.modulate == Color.WHITE,
			"crest must remain visible behind the unmodulated native actor", failures)
		_expect(crest.mouse_filter == Control.MOUSE_FILTER_IGNORE
			and crest.focus_mode == Control.FOCUS_NONE,
			"decorative crest intercepts navigation or pointer input", failures)
		_expect(crest.stretch_mode == TextureRect.STRETCH_KEEP_CENTERED,
			"crest no longer preserves its native pixel size", failures)
		for size: Vector2 in [Vector2(192, 192), Vector2(240, 256)]:
			preview.size = size
			await process_frame
			var material_size := crest.texture.get_size()
			var material_rect := Rect2(crest.position + (crest.size - material_size) * 0.5, material_size)
			_expect(Rect2(Vector2.ZERO, size).encloses(material_rect),
				"crest clips at preview size %s" % size, failures)
	preview.free()
	await process_frame
	if failures.is_empty():
		print("PASS  test_loadout_character_view.gd")
		quit(0)
	else:
		for failure in failures:
			printerr("- " + failure)
		quit(1)


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
