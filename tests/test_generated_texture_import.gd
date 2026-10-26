extends SceneTree

## Imported and raw assets must fingerprint identically, including invisible
## RGB. Godot's default alpha-border repair otherwise changes the manifest
## after import, even though visible pixels and alpha stay unchanged.
func _initialize() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://art/production/p1/generated_world_v02/assets.json"))
	var paths: Array[String] = []
	for entry: Dictionary in manifest.assets.values():
		paths.append(String(entry.opaque_path))
		paths.append(String(entry.transparent_path))
	for entry: Dictionary in manifest.grounds.values():
		paths.append(String(entry.opaque_path))
	paths.append("res://art/production/p1/generated_world_v02/residents/residents.png")
	# Keep the previous world pack covered, and verify every new actor sheet
	# through Godot's imported texture path before accepting the replacement.
	for filename: String in ["ranger.png", "enemies.png", "residents/residents.png", "boss_body.png", "boss_core.png", "boss_hands.png", "ranger_idle.png", "legacy_enemies.png"]:
		paths.append("res://art/production/p1/actors_v02/" + filename)
	var polish: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://art/production/p1/world_polish_v01/assets.json"))
	for entry: Dictionary in polish.assets.values():
		paths.append(String(entry.path))
	var failures: Array[String] = []
	var expansion: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://art/production/p1/world_expansion_v01/assets.json"))
	var expected_expansion := ["bridge", "bridge_ne", "causeway_ground", "court_ground", "gateway", "house_east", "house_west", "ritual_ground", "town_ground", "wall"]
	var actual_expansion: Array = expansion.get("assets", {}).keys()
	actual_expansion.sort()
	if actual_expansion != expected_expansion:
		failures.append("world expansion asset inventory differs from the authored ten assets")
	for entry: Dictionary in expansion.get("assets", {}).values():
		if String(entry.get("status", "")) != "packed":
			failures.append("world expansion contains unpacked art")
			continue
		paths.append(String(entry.path))
		if entry.has("transparent_path"):
			paths.append(String(entry.transparent_path))
	var ordered: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://art/production/p1/town_order_v01/assets.json"))
	var ordered_ids: Array = ordered.get("assets", {}).keys()
	ordered_ids.sort()
	if ordered_ids != ["forge_west", "loadout_east", "wall_ne", "wall_north_south"]:
		failures.append("town order inventory differs from four authored variants")
	for entry: Dictionary in ordered.get("assets", {}).values():
		if String(entry.get("status", "")) != "packed":
			failures.append("town order contains unpacked art")
			continue
		paths.append(String(entry.path))
		paths.append(String(entry.transparent_path))
	var completed := 0
	for path: String in paths:
		if _check_texture(path, failures):
			completed += 1
	if paths.size() != 77 or completed != 77:
		failures.append("expected 77 complete imported texture checks, got %d/%d" % [completed, paths.size()])
	if not failures.is_empty():
		printerr("GENERATED_TEXTURE_IMPORT_FAIL ", failures)
		quit(1)
		return
	print("GENERATED_TEXTURE_IMPORT_PASS 77 exact RGBA8 images")
	quit(0)


func _check_texture(path: String, failures: Array[String]) -> bool:
	var settings := ConfigFile.new()
	if settings.load(path + ".import") != OK or settings.get_value("params", "process/fix_alpha_border", true) != false:
		failures.append("alpha border processing is not pinned off: " + path)
		return false
	var raw := Image.new()
	if raw.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK:
		failures.append("cannot decode raw PNG: " + path)
		return false
	var texture := load(path) as Texture2D
	if raw == null or texture == null:
		failures.append("missing raw/imported image: " + path)
		return false
	var imported := texture.get_image()
	if imported == null or (imported.is_compressed() and imported.decompress() != OK):
		failures.append("cannot decode imported texture: " + path)
		return false
	raw.convert(Image.FORMAT_RGBA8)
	imported.convert(Image.FORMAT_RGBA8)
	if raw.get_size() != imported.get_size() or raw.get_data() != imported.get_data():
		failures.append("import changed RGBA8 pixels: " + path)
		return false
	return true
