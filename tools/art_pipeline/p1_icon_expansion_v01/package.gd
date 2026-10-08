extends SceneTree

const SCHEMA_VERSION := 1
const CELL_SIZE := 32
const PADDING := 2
const MAX_CONTENT_SIZE := 28
const EXPECTED_GROUPS := {
	"ranger_talents": {"texture": "ranger_talents.png", "count": 15},
	"law_tokens": {"texture": "law_tokens.png", "count": 3},
}


func _init() -> void:
	var args := _read_args()
	if args.is_empty():
		_fail("usage: --recipe=<absolute recipe.json> --out=<absolute output directory>")
		return
	var recipe_path: String = args.get("recipe", "")
	var output_dir: String = args.get("out", "")
	if not recipe_path.is_absolute_path() or not output_dir.is_absolute_path():
		_fail("--recipe and --out must be absolute paths")
		return
	if not FileAccess.file_exists(recipe_path):
		_fail("recipe does not exist: %s" % recipe_path)
		return
	if not _output_is_fresh(output_dir):
		return
	var recipe := _read_json(recipe_path, "recipe")
	if recipe.is_empty():
		return
	var palette := _parse_palette(recipe)
	if palette.is_empty():
		return
	var packed := _prepare_atlases(recipe, palette)
	if packed.is_empty():
		return
	if DirAccess.make_dir_recursive_absolute(output_dir) != OK:
		_fail("cannot create output directory: %s" % output_dir)
		return
	if not _write_outputs(output_dir, packed, palette):
		return
	print("P1_ICON_EXPANSION_PACKAGE_PASS")
	quit(0)


func _read_args() -> Dictionary:
	var result := {}
	var args := OS.get_cmdline_user_args()
	var index := 0
	while index < args.size():
		var arg: String = args[index]
		if arg.begins_with("--recipe="):
			result["recipe"] = arg.substr("--recipe=".length())
		elif arg.begins_with("--out="):
			result["out"] = arg.substr("--out=".length())
		elif arg == "--recipe" or arg == "--out":
			if index + 1 >= args.size():
				return {}
			result[arg.trim_prefix("--")] = args[index + 1]
			index += 1
		index += 1
	if not result.has("recipe") or not result.has("out"):
		return {}
	return result


func _output_is_fresh(output_dir: String) -> bool:
	if FileAccess.file_exists(output_dir):
		_fail("output path is a file: %s" % output_dir)
		return false
	if not DirAccess.dir_exists_absolute(output_dir):
		return true
	var directory := DirAccess.open(output_dir)
	if directory == null:
		_fail("cannot inspect output directory: %s" % output_dir)
		return false
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
			directory.list_dir_end()
			_fail("output directory must be empty: %s" % output_dir)
			return false
		entry = directory.get_next()
	directory.list_dir_end()
	return true


func _read_json(path: String, label: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_fail("cannot open %s: %s" % [label, path])
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		_fail("%s is not a JSON object: %s" % [label, path])
		return {}
	return parsed


func _parse_palette(recipe: Dictionary) -> Array:
	if int(recipe.get("schema_version", -1)) != SCHEMA_VERSION:
		_fail("recipe schema_version must be 1")
		return []
	var declared = recipe.get("palette", [])
	if not (declared is Array) or declared.size() != 8:
		_fail("recipe palette must contain exactly 8 #rrggbb entries")
		return []
	var palette: Array = []
	var seen := {}
	for entry in declared:
		if not (entry is String) or not _is_hex_colour(entry):
			_fail("invalid palette colour: %s" % str(entry))
			return []
		var key: String = String(entry).to_lower()
		if seen.has(key):
			_fail("palette colours must be distinct: %s" % entry)
			return []
		seen[key] = true
		palette.append(_colour_from_hex(key))
	return palette


func _is_hex_colour(value: String) -> bool:
	if value.length() != 7 or not value.begins_with("#"):
		return false
	for character in value.substr(1):
		if not (character >= "0" and character <= "9") and not (character.to_lower() >= "a" and character.to_lower() <= "f"):
			return false
	return true


func _colour_from_hex(value: String) -> Color:
	return Color(
		float(value.substr(1, 2).hex_to_int()) / 255.0,
		float(value.substr(3, 2).hex_to_int()) / 255.0,
		float(value.substr(5, 2).hex_to_int()) / 255.0,
		1.0
	)


func _prepare_atlases(recipe: Dictionary, palette: Array) -> Array:
	var groups = recipe.get("groups", [])
	if not (groups is Array) or groups.size() != EXPECTED_GROUPS.size():
		_fail("recipe must contain exactly ranger_talents and law_tokens groups")
		return []
	var found_groups := {}
	var seen_ids := {}
	var seen_canonical_ids := {}
	var source_cache := {}
	var prepared_by_id := {}
	for group_data in groups:
		if not (group_data is Dictionary):
			_fail("every group must be an object")
			return []
		var group_id: String = String(group_data.get("id", ""))
		if not EXPECTED_GROUPS.has(group_id) or found_groups.has(group_id):
			_fail("unexpected or duplicate group: %s" % group_id)
			return []
		var expected: Dictionary = EXPECTED_GROUPS[group_id]
		var texture: String = String(group_data.get("texture", ""))
		if texture != String(expected["texture"]):
			_fail("%s texture must be %s" % [group_id, expected["texture"]])
			return []
		var sprites = group_data.get("sprites", [])
		if not (sprites is Array) or sprites.size() != int(expected["count"]):
			_fail("%s must contain %d sprites" % [group_id, expected["count"]])
			return []
		var cells: Array = []
		var report_sprites: Array = []
		for sprite_data in sprites:
			if not (sprite_data is Dictionary):
				_fail("every sprite must be an object")
				return []
			var sprite_id: String = String(sprite_data.get("id", ""))
			var canonical_id: String = String(sprite_data.get("canonical_id", ""))
			if sprite_id.is_empty() or canonical_id.is_empty() or seen_ids.has(sprite_id) or seen_canonical_ids.has(canonical_id):
				_fail("sprite ids and canonical_ids must be non-empty and globally unique")
				return []
			var source_path: String = String(sprite_data.get("source", ""))
			if not source_path.is_absolute_path() or not FileAccess.file_exists(source_path):
				_fail("source PNG is missing or not absolute: %s" % source_path)
				return []
			if source_path.get_extension().to_lower() != "png":
				_fail("source must be a PNG: %s" % source_path)
				return []
			var source_info := _load_source(source_path, source_cache)
			if source_info.is_empty():
				return []
			var rect := _parse_rect(sprite_data.get("source_rect", []), source_info["image"], sprite_id)
			if rect.size.x <= 0 or rect.size.y <= 0:
				return []
			var processed := _process_rect(source_info["image"], rect, palette, sprite_id)
			if processed.is_empty():
				return []
			seen_ids[sprite_id] = true
			seen_canonical_ids[canonical_id] = true
			cells.append(processed["image"])
			report_sprites.append({
				"id": sprite_id,
				"canonical_id": canonical_id,
				"source": source_path,
				"source_sha256": source_info["sha256"],
				"source_dimensions": [source_info["image"].get_width(), source_info["image"].get_height()],
				"source_rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y],
				"original_bbox": [
					rect.position.x + int(processed["bbox_in_source_rect"][0]),
					rect.position.y + int(processed["bbox_in_source_rect"][1]),
					int(processed["bbox_in_source_rect"][2]),
					int(processed["bbox_in_source_rect"][3]),
				],
				"bbox_in_source_rect": processed["bbox_in_source_rect"],
				"tight_dimensions": processed["tight_dimensions"],
				"normalized_dimensions": processed["normalized_dimensions"],
			})
		found_groups[group_id] = true
		prepared_by_id[group_id] = {"id": group_id, "texture": texture, "cells": cells, "report_sprites": report_sprites}
	if found_groups.size() != EXPECTED_GROUPS.size() or seen_ids.size() != 18:
		_fail("recipe must yield exactly 18 unique sprite ids")
		return []
	return [prepared_by_id["ranger_talents"], prepared_by_id["law_tokens"]]


func _load_source(path: String, cache: Dictionary) -> Dictionary:
	if cache.has(path):
		return cache[path]
	var image := Image.load_from_file(path)
	if image == null or image.is_empty():
		_fail("cannot load source PNG: %s" % path)
		return {}
	if image.get_format() not in [Image.FORMAT_RGBA8, Image.FORMAT_LA8]:
		_fail("source PNG has no alpha channel: %s" % path)
		return {}
	image.convert(Image.FORMAT_RGBA8)
	var has_transparency := false
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a < 1.0:
				has_transparency = true
				break
		if has_transparency:
			break
	if not has_transparency:
		_fail("fully opaque source PNG is rejected: %s" % path)
		return {}
	var result := {"image": image, "sha256": FileAccess.get_sha256(path)}
	if String(result["sha256"]).is_empty():
		_fail("cannot calculate source SHA-256: %s" % path)
		return {}
	cache[path] = result
	return result


func _parse_rect(raw_rect, source: Image, sprite_id: String) -> Rect2i:
	if not (raw_rect is Array) or raw_rect.size() != 4:
		_fail("%s source_rect must be [x,y,width,height]" % sprite_id)
		return Rect2i()
	for value in raw_rect:
		if not (value is int) and not (value is float):
			_fail("%s source_rect values must be integers" % sprite_id)
			return Rect2i()
		if int(value) != value:
			_fail("%s source_rect values must be integers" % sprite_id)
			return Rect2i()
	var rect := Rect2i(int(raw_rect[0]), int(raw_rect[1]), int(raw_rect[2]), int(raw_rect[3]))
	if rect.position.x < 0 or rect.position.y < 0 or rect.size.x <= 0 or rect.size.y <= 0 or rect.end.x > source.get_width() or rect.end.y > source.get_height():
		_fail("%s source_rect is outside its source image" % sprite_id)
		return Rect2i()
	return rect


func _process_rect(source: Image, rect: Rect2i, palette: Array, sprite_id: String) -> Dictionary:
	var normalized: Image = source.get_region(rect)
	normalized.convert(Image.FORMAT_RGBA8)
	var bbox: Rect2i = _normalise_alpha_and_find_bbox(normalized)
	if bbox.size.x <= 0 or bbox.size.y <= 0:
		_fail("%s source_rect has no opaque pixels after alpha thresholding" % sprite_id)
		return {}
	var tight: Image = normalized.get_region(bbox)
	var scale: float = min(float(MAX_CONTENT_SIZE) / float(tight.get_width()), float(MAX_CONTENT_SIZE) / float(tight.get_height()))
	var target_width: int = max(1, int(round(float(tight.get_width()) * scale)))
	var target_height: int = max(1, int(round(float(tight.get_height()) * scale)))
	if tight.get_width() != target_width or tight.get_height() != target_height:
		tight.resize(target_width, target_height, Image.INTERPOLATE_NEAREST)
	_map_to_palette(tight, palette)
	var cell: Image = Image.create(CELL_SIZE, CELL_SIZE, false, Image.FORMAT_RGBA8)
	cell.fill(Color(0, 0, 0, 0))
	cell.blit_rect(tight, Rect2i(0, 0, tight.get_width(), tight.get_height()), Vector2i(int((CELL_SIZE - target_width) / 2), int((CELL_SIZE - target_height) / 2)))
	return {
		"image": cell,
		"bbox_in_source_rect": [bbox.position.x, bbox.position.y, bbox.size.x, bbox.size.y],
		"tight_dimensions": [bbox.size.x, bbox.size.y],
		"normalized_dimensions": [target_width, target_height],
	}


func _normalise_alpha_and_find_bbox(image: Image) -> Rect2i:
	var min_x := image.get_width()
	var min_y := image.get_height()
	var max_x := -1
	var max_y := -1
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var pixel: Color = image.get_pixel(x, y)
			if int(round(pixel.a * 255.0)) >= 128:
				image.set_pixel(x, y, Color(pixel.r, pixel.g, pixel.b, 1.0))
				min_x = min(min_x, x)
				min_y = min(min_y, y)
				max_x = max(max_x, x)
				max_y = max(max_y, y)
			else:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
	if max_x < min_x:
		return Rect2i()
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)


func _map_to_palette(image: Image, palette: Array) -> void:
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var pixel: Color = image.get_pixel(x, y)
			if pixel.a <= 0.0:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var nearest: Color = palette[0]
			var nearest_distance: float = INF
			for palette_colour in palette:
				var palette_rgb: Color = palette_colour as Color
				var dr: float = pixel.r - palette_rgb.r
				var dg: float = pixel.g - palette_rgb.g
				var db: float = pixel.b - palette_rgb.b
				var distance: float = dr * dr + dg * dg + db * db
				if distance < nearest_distance:
					nearest = palette_rgb
					nearest_distance = distance
			image.set_pixel(x, y, nearest)


func _write_outputs(output_dir: String, prepared: Array, palette: Array) -> bool:
	var atlas_manifest := {"schema_version": SCHEMA_VERSION, "sprites": [], "textures": []}
	var report := {
		"schema_version": SCHEMA_VERSION,
		"processing": {
			"alpha_threshold": 128,
			"cell_size": CELL_SIZE,
			"padding": PADDING,
			"max_content_size": MAX_CONTENT_SIZE,
			"resize": "nearest_neighbor_proportional_fit",
			"transparent_rgb": [0, 0, 0],
			"palette": _palette_strings(palette),
		},
		"groups": [],
	}
	for group in prepared:
		var cells: Array = group["cells"]
		var atlas := Image.create(CELL_SIZE * cells.size(), CELL_SIZE, false, Image.FORMAT_RGBA8)
		atlas.fill(Color(0, 0, 0, 0))
		for index in range(cells.size()):
			atlas.blit_rect(cells[index], Rect2i(0, 0, CELL_SIZE, CELL_SIZE), Vector2i(CELL_SIZE * index, 0))
		var texture: String = group["texture"]
		var output_path := output_dir.path_join(texture)
		if atlas.save_png(output_path) != OK:
			_fail("cannot save atlas: %s" % output_path)
			return false
		var output_sha256 := FileAccess.get_sha256(output_path)
		if output_sha256.is_empty():
			_fail("cannot calculate output SHA-256: %s" % output_path)
			return false
		atlas_manifest["textures"].append({"file": texture, "dimensions": [atlas.get_width(), atlas.get_height()]})
		var group_report := {"id": group["id"], "texture": texture, "output_sha256": output_sha256, "dimensions": [atlas.get_width(), atlas.get_height()], "sprites": []}
		var sprites: Array = group["report_sprites"]
		for index in range(sprites.size()):
			var sprite: Dictionary = sprites[index]
			var rect := [CELL_SIZE * index, 0, CELL_SIZE, CELL_SIZE]
			atlas_manifest["sprites"].append({
				"id": sprite["id"], "canonical_id": sprite["canonical_id"], "texture": texture,
				"rect": rect, "anchor": [16, 16], "type": "ui_icon",
			})
			var sprite_report := sprite.duplicate(true)
			sprite_report["atlas_rect"] = rect
			group_report["sprites"].append(sprite_report)
		report["groups"].append(group_report)
	if not _write_json(output_dir.path_join("atlas.json"), atlas_manifest):
		return false
	if not _write_json(output_dir.path_join("report.json"), report):
		return false
	return true


func _palette_strings(palette: Array) -> Array:
	var values: Array = []
	for colour in palette:
		values.append("#%02x%02x%02x" % [int(round(colour.r * 255.0)), int(round(colour.g * 255.0)), int(round(colour.b * 255.0))])
	return values


func _write_json(path: String, data: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_fail("cannot write JSON: %s" % path)
		return false
	file.store_string(JSON.stringify(data, "\t") + "\n")
	return true


func _fail(message: String) -> void:
	push_error("P1 icon expansion package failed: %s" % message)
	quit(1)
