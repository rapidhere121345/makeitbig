extends SceneTree

const SCHEMA_VERSION := 1
const CELL_SIZE := 32
const PADDING := 2
const EXPECTED_SPRITE_COUNT := 18
const EXPECTED_TEXTURES := {
	"ranger_talents.png": 15,
	"law_tokens.png": 3,
}


func _init() -> void:
	var output_dir := _read_output_dir()
	if output_dir.is_empty():
		_fail("usage: --out=<absolute packaged output directory>")
		return
	if not output_dir.is_absolute_path() or not DirAccess.dir_exists_absolute(output_dir):
		_fail("--out must name an existing absolute output directory")
		return
	var manifest_path := output_dir.path_join("atlas.json")
	if not FileAccess.file_exists(manifest_path):
		_fail("atlas.json is missing: %s" % manifest_path)
		return
	var manifest := _read_manifest(manifest_path)
	if manifest.is_empty():
		return
	if not _verify_manifest(output_dir, manifest):
		return
	print("P1_ICON_EXPANSION_VERIFY_PASS")
	quit(0)


func _read_output_dir() -> String:
	var args := OS.get_cmdline_user_args()
	var index := 0
	while index < args.size():
		var arg: String = args[index]
		if arg.begins_with("--out="):
			return arg.substr("--out=".length())
		if arg == "--out" and index + 1 < args.size():
			return args[index + 1]
		index += 1
	return ""


func _read_manifest(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_fail("cannot read atlas.json")
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		_fail("atlas.json is not a JSON object")
		return {}
	return parsed


func _verify_manifest(output_dir: String, manifest: Dictionary) -> bool:
	if int(manifest.get("schema_version", -1)) != SCHEMA_VERSION:
		_fail("atlas.json schema_version must be 1")
		return false
	var texture_data = manifest.get("textures", [])
	var sprite_data = manifest.get("sprites", [])
	if not (texture_data is Array) or not (sprite_data is Array):
		_fail("atlas.json textures and sprites must be arrays")
		return false
	if texture_data.size() != EXPECTED_TEXTURES.size() or sprite_data.size() != EXPECTED_SPRITE_COUNT:
		_fail("atlas.json must describe 2 atlases and 18 sprites")
		return false
	var textures := {}
	for texture_entry in texture_data:
		if not (texture_entry is Dictionary):
			_fail("texture entry must be an object")
			return false
		var file: String = String(texture_entry.get("file", ""))
		if not EXPECTED_TEXTURES.has(file) or textures.has(file):
			_fail("unexpected or duplicate texture: %s" % file)
			return false
		var dimensions = texture_entry.get("dimensions", [])
		if not _is_integer_pair(dimensions) or int(dimensions[0]) != CELL_SIZE * int(EXPECTED_TEXTURES[file]) or int(dimensions[1]) != CELL_SIZE:
			_fail("invalid declared dimensions for %s" % file)
			return false
		var image_path := output_dir.path_join(file)
		if not FileAccess.file_exists(image_path):
			_fail("atlas texture is missing: %s" % image_path)
			return false
		var image := Image.load_from_file(image_path)
		if image == null or image.is_empty() or image.get_format() != Image.FORMAT_RGBA8:
			_fail("atlas texture must be a readable PNG with alpha: %s" % file)
			return false
		if image.get_width() != int(dimensions[0]) or image.get_height() != int(dimensions[1]):
			_fail("atlas PNG dimensions do not match atlas.json: %s" % file)
			return false
		image.convert(Image.FORMAT_RGBA8)
		textures[file] = image
	if textures.size() != EXPECTED_TEXTURES.size():
		_fail("both required atlas textures are not present")
		return false
	var seen_ids := {}
	var seen_canonical_ids := {}
	var slots_by_texture := {}
	for sprite_entry in sprite_data:
		if not (sprite_entry is Dictionary):
			_fail("sprite entry must be an object")
			return false
		var id: String = String(sprite_entry.get("id", ""))
		var canonical_id: String = String(sprite_entry.get("canonical_id", ""))
		var texture: String = String(sprite_entry.get("texture", ""))
		if id.is_empty() or canonical_id.is_empty() or seen_ids.has(id) or seen_canonical_ids.has(canonical_id):
			_fail("sprite ids and canonical_ids must be non-empty and unique")
			return false
		if not textures.has(texture) or String(sprite_entry.get("type", "")) != "ui_icon":
			_fail("sprite has an unknown texture or invalid type: %s" % id)
			return false
		var rect = sprite_entry.get("rect", [])
		if not _is_integer_quad(rect) or int(rect[1]) != 0 or int(rect[2]) != CELL_SIZE or int(rect[3]) != CELL_SIZE or int(rect[0]) < 0 or int(rect[0]) % CELL_SIZE != 0:
			_fail("sprite does not occupy one 32x32 atlas cell: %s" % id)
			return false
		var anchor = sprite_entry.get("anchor", [])
		if not _is_integer_pair(anchor) or int(anchor[0]) != 16 or int(anchor[1]) != 16:
			_fail("sprite anchor must be [16,16]: %s" % id)
			return false
		var slot := int(rect[0]) / CELL_SIZE
		if slot < 0 or slot >= int(EXPECTED_TEXTURES[texture]):
			_fail("sprite cell is outside its atlas: %s" % id)
			return false
		if not slots_by_texture.has(texture):
			slots_by_texture[texture] = {}
		if slots_by_texture[texture].has(slot):
			_fail("multiple sprites occupy atlas cell %d in %s" % [slot, texture])
			return false
		if not _verify_cell(textures[texture], Rect2i(int(rect[0]), 0, CELL_SIZE, CELL_SIZE), id):
			return false
		seen_ids[id] = true
		seen_canonical_ids[canonical_id] = true
		slots_by_texture[texture][slot] = true
	if seen_ids.size() != EXPECTED_SPRITE_COUNT:
		_fail("expected 18 unique sprite ids")
		return false
	for texture in EXPECTED_TEXTURES:
		if not slots_by_texture.has(texture) or slots_by_texture[texture].size() != int(EXPECTED_TEXTURES[texture]):
			_fail("atlas cells must be filled exactly once: %s" % texture)
			return false
	return true


func _verify_cell(atlas: Image, rect: Rect2i, id: String) -> bool:
	var min_x := CELL_SIZE
	var min_y := CELL_SIZE
	var max_x := -1
	var max_y := -1
	var unique_colours := {}
	for local_y in range(CELL_SIZE):
		for local_x in range(CELL_SIZE):
			var pixel := atlas.get_pixel(rect.position.x + local_x, rect.position.y + local_y)
			var alpha := int(round(pixel.a * 255.0))
			if alpha != 0 and alpha != 255:
				_fail("alpha must be binary: %s" % id)
				return false
			var red := int(round(pixel.r * 255.0))
			var green := int(round(pixel.g * 255.0))
			var blue := int(round(pixel.b * 255.0))
			if alpha == 0:
				if red != 0 or green != 0 or blue != 0:
					_fail("transparent pixels must use RGB 0,0,0: %s" % id)
					return false
				continue
			if local_x < PADDING or local_x >= CELL_SIZE - PADDING or local_y < PADDING or local_y >= CELL_SIZE - PADDING:
				_fail("sprite breaches 2px transparent padding: %s" % id)
				return false
			unique_colours["%d,%d,%d" % [red, green, blue]] = true
			min_x = min(min_x, local_x)
			min_y = min(min_y, local_y)
			max_x = max(max_x, local_x)
			max_y = max(max_y, local_y)
	if max_x < min_x:
		_fail("empty icon cell: %s" % id)
		return false
	if max_x - min_x + 1 > CELL_SIZE - PADDING * 2 or max_y - min_y + 1 > CELL_SIZE - PADDING * 2:
		_fail("icon content exceeds 28x28: %s" % id)
		return false
	if unique_colours.size() > 8:
		_fail("icon contains more than 8 opaque RGB colours: %s" % id)
		return false
	return true


func _is_integer_pair(value) -> bool:
	return value is Array and value.size() == 2 and _is_integer(value[0]) and _is_integer(value[1])


func _is_integer_quad(value) -> bool:
	return value is Array and value.size() == 4 and _is_integer(value[0]) and _is_integer(value[1]) and _is_integer(value[2]) and _is_integer(value[3])


func _is_integer(value) -> bool:
	return (value is int) or (value is float and int(value) == value)


func _fail(message: String) -> void:
	push_error("P1 icon expansion verification failed: %s" % message)
	quit(1)
