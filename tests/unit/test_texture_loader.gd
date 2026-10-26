extends SceneTree
## Shared texture loader gate (src/presentation/art/texture_loader.gd).
##   godot --headless --path . --script res://tests/unit/test_texture_loader.gd

const TextureLoader := preload("res://src/presentation/art/texture_loader.gd")
const TEMP_DIR := "user://texture_loader_test"
const IMPORTED_PNG := "res://art/production/p1/hamlet_life_v01/residents.png"
const IMPORTED_SIZE := Vector2i(192, 240)

var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(TEMP_DIR)
	var raw_path := TEMP_DIR.path_join("probe.png")
	var probe := Image.create(16, 8, false, Image.FORMAT_RGBA8)
	probe.fill(Color(0.25, 0.5, 0.75, 1.0))
	probe.save_png(raw_path)
	var junk_path := TEMP_DIR.path_join("junk.png")
	var junk := FileAccess.open(junk_path, FileAccess.WRITE)
	junk.store_string("not a png")
	junk.close()
	var empty_path := TEMP_DIR.path_join("empty.png")
	FileAccess.open(empty_path, FileAccess.WRITE).close()
	var missing_path := TEMP_DIR.path_join("missing.png")

	_decode(raw_path, junk_path, missing_path)
	_png_first(raw_path, missing_path)
	_imported_first(raw_path, junk_path, empty_path, missing_path)
	_sized(raw_path, missing_path)
	_imported_or_file(raw_path, missing_path)

	for name in ["probe.png", "junk.png", "empty.png"]:
		DirAccess.remove_absolute(TEMP_DIR.path_join(name))
	DirAccess.remove_absolute(TEMP_DIR)
	for message in failures:
		printerr(message)
	print("TEXTURE_LOADER ", "pass" if failures.is_empty() else "fail", " checks=", checks)
	quit(0 if failures.is_empty() else 1)


func _decode(raw_path: String, junk_path: String, missing_path: String) -> void:
	var image := TextureLoader.decode_png_path(raw_path)
	_expect(image != null and image.get_size() == Vector2i(16, 8), "decode_png_path reads a raw PNG")
	_expect(TextureLoader.decode_png_path(junk_path) == null, "decode_png_path rejects non-PNG bytes")
	_expect(TextureLoader.decode_png_path(missing_path) == null, "decode_png_path rejects a missing file")


func _png_first(raw_path: String, missing_path: String) -> void:
	var raw := TextureLoader.load_png_first(raw_path)
	_expect(raw != null and Vector2i(raw.get_size()) == Vector2i(16, 8), "load_png_first reads an unimported PNG")
	var imported := TextureLoader.load_png_first(IMPORTED_PNG)
	_expect(imported != null and Vector2i(imported.get_size()) == IMPORTED_SIZE, "load_png_first reads shipped art")
	_expect(TextureLoader.load_png_first(missing_path) == null, "load_png_first returns null for a missing file")


func _imported_first(raw_path: String, junk_path: String, empty_path: String, missing_path: String) -> void:
	var imported := TextureLoader.load_imported_first(IMPORTED_PNG)
	_expect(imported.texture != null and imported.error == TextureLoader.ERROR_NONE, "load_imported_first returns the imported resource")
	var raw := TextureLoader.load_imported_first(raw_path)
	_expect(raw.texture != null and raw.error == TextureLoader.ERROR_NONE, "load_imported_first falls back to the raw PNG")
	_expect(TextureLoader.load_imported_first(missing_path).error == TextureLoader.ERROR_MISSING, "load_imported_first reports a missing file")
	_expect(TextureLoader.load_imported_first(empty_path).error == TextureLoader.ERROR_UNREADABLE, "load_imported_first reports an empty file as unreadable")
	_expect(TextureLoader.load_imported_first(junk_path).error == TextureLoader.ERROR_INVALID_PNG, "load_imported_first reports undecodable bytes")
	_expect(TextureLoader.load_imported_first(junk_path).texture == null, "load_imported_first returns no texture on failure")


func _sized(raw_path: String, missing_path: String) -> void:
	for fallback: bool in [true, false]:
		var label := "load_sized(fallback=%s)" % fallback
		_expect(TextureLoader.load_sized(IMPORTED_PNG, IMPORTED_SIZE, fallback) != null, label + " accepts an imported texture of the declared size")
		_expect(TextureLoader.load_sized(raw_path, Vector2i(16, 8), fallback) != null, label + " decodes a raw PNG of the declared size")
		_expect(TextureLoader.load_sized(raw_path, Vector2i(32, 8), fallback) == null, label + " refuses a raw size mismatch")
		_expect(TextureLoader.load_sized(missing_path, Vector2i(16, 8), fallback) == null, label + " refuses a missing file")
		_expect(TextureLoader.load_sized("", Vector2i(16, 8), fallback) == null, label + " refuses an empty path")
		_expect(TextureLoader.load_sized(raw_path, Vector2i.ZERO, fallback) == null, label + " refuses a non-positive size")
		_expect(TextureLoader.load_sized(IMPORTED_PNG, Vector2i(1, 1), fallback) == null, label + " refuses an imported size mismatch")


func _imported_or_file(raw_path: String, missing_path: String) -> void:
	for fallback: bool in [true, false]:
		var label := "load_imported_or_file(fallback=%s)" % fallback
		_expect(TextureLoader.load_imported_or_file(IMPORTED_PNG, fallback) != null, label + " loads the imported resource")
		var raw := TextureLoader.load_imported_or_file(raw_path, fallback)
		_expect(raw != null and Vector2i(raw.get_size()) == Vector2i(16, 8), label + " loads an unimported image file")
		_expect(TextureLoader.load_imported_or_file(missing_path, fallback) == null, label + " returns null for a missing file")


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append("FAIL: " + message)
