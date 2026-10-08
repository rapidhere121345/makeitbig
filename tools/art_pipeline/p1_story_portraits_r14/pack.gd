extends SceneTree

# Only transparent crop, nearest-neighbor resize and fixed-cell packing.
# All character pixels originate in the archived imagegen raster.
const IDS = ["mira", "iven", "taren", "leia", "oren"]
const SIZE = Vector2i(128, 160)
const LIMIT = Vector2i(120, 152)
var repo_root: String
var docs: String
var output: String
var failed := false

func _initialize() -> void:
	repo_root = get_script().resource_path.get_base_dir().path_join("../../..").simplify_path()
	docs = repo_root.path_join("docs/art-production/p1-story-portraits-r14")
	output = repo_root.path_join("art/production/p1/story_portraits_r14")
	var recipe = JSON.parse_string(FileAccess.get_file_as_string(docs.path_join("recipe.json")))
	if not recipe is Dictionary:
		fail("Missing recipe.json")
		quit(1)
		return
	var source_path = repo_root.path_join(recipe.source)
	var source = Image.load_from_file(source_path)
	if source == null:
		fail("Cannot load source")
		quit(1)
		return
	source.convert(Image.FORMAT_RGBA8)
	print("Godot ", Engine.get_version_info().string)
	print("source ", recipe.source, " size=", source.get_size(), " sha256=", sha256(source_path))
	var source_stats = stats(source)
	print("source RGBA ", JSON.stringify(source_stats))
	if source_stats.transparent_pixels == 0:
		fail("Generated source has no genuine transparent pixels")
	var columns: int = recipe.columns
	var rows: int = recipe.rows
	var selected_rects = recipe.get("source_rects", [])
	# Preflight every grid cell before creating any deliverable raster.
	for index in range(6):
		if selected_rects.size() == 5:
			# Audit only: every visible pixel stays inside its reviewed crop.
			# This threshold NEVER changes output alpha or colors.
			if index == 5:
				continue
			var selected = selected_rects[index]
			var crop = Rect2i(selected[0], selected[1], selected[2], selected[3])
			var grid_left = index % columns * source.get_width() / columns
			var grid_right = (index % columns + 1) * source.get_width() / columns
			var grid_top = int((index / columns) * source.get_height() / float(rows))
			var grid_bottom = int((index / columns + 1) * source.get_height() / float(rows))
			var lost_visible := 0
			for y in range(grid_top, grid_bottom):
				for x in range(grid_left, grid_right):
					if roundi(source.get_pixel(x, y).a * 255) >= 8 and not crop.has_point(Vector2i(x, y)):
						lost_visible += 1
			print(IDS[index], " crop audit alpha>=8 excluded=", lost_visible)
			if lost_visible > 0:
				fail("Reviewed crop clips visible pixels: " + str(IDS[index]))
			continue
		var col = index % columns
		var row = index / columns
		var left = int(col * source.get_width() / float(columns))
		var top = int(row * source.get_height() / float(rows))
		var right = int((col + 1) * source.get_width() / float(columns))
		var bottom = int((row + 1) * source.get_height() / float(rows))
		var cell = source.get_region(Rect2i(left, top, right - left, bottom - top))
		var bounds = cell.get_used_rect()
		if index == 5:
			if bounds.has_area():
				fail("Preflight: sixth cell is not completely transparent")
		elif not bounds.has_area() or bounds.position.x == 0 or bounds.position.y == 0 or bounds.end.x == cell.get_width() or bounds.end.y == cell.get_height():
			fail("Preflight: " + str(IDS[index]) + " empty or touching cell edge")
	if failed:
		print("RESULT FAIL source-preflight; no deliverable written")
		quit(1)
		return
	var verify_only = "--verify" in OS.get_cmdline_user_args()
	var preview = Image.create(384, 320, false, Image.FORMAT_RGBA8)
	preview.fill(Color.TRANSPARENT)
	# Mechanical fixed-cell previews on two UI-like mattes, not production art.
	var slate_preview = Image.create(384, 320, false, Image.FORMAT_RGBA8)
	slate_preview.fill(Color("303e49"))
	var ivory_preview = Image.create(384, 320, false, Image.FORMAT_RGBA8)
	ivory_preview.fill(Color("dfdacd"))
	var atlas := {}
	var report := {"source": recipe.source, "source_size": [source.get_width(), source.get_height()], "source_sha256": sha256(source_path), "source_rgba": source_stats, "portraits": {}, "errors": []}
	for index in range(6):
		var col = index % columns
		var row = index / columns
		var left = int(col * source.get_width() / float(columns))
		var top = int(row * source.get_height() / float(rows))
		var right = int((col + 1) * source.get_width() / float(columns))
		var bottom = int((row + 1) * source.get_height() / float(rows))
		var cell_rect = Rect2i(left, top, right - left, bottom - top)
		if selected_rects.size() == 5 and index < 5:
			var rect = selected_rects[index]
			cell_rect = Rect2i(rect[0], rect[1], rect[2], rect[3])
			left = cell_rect.position.x
			top = cell_rect.position.y
		var cell = source.get_region(cell_rect)
		var bounds = cell.get_used_rect()
		if index == 5:
			if selected_rects.size() == 5:
				print("empty_sixth_cell production pack=true; generated source empty cell is discarded")
				continue
			if bounds.has_area():
				fail("Sixth cell must be fully transparent: " + str(bounds))
			print("empty_sixth_cell ", not bounds.has_area())
			continue
		var id: String = IDS[index]
		if not bounds.has_area():
			fail(id + " has empty source cell")
			continue
		if selected_rects.size() != 5 and (bounds.position.x == 0 or bounds.position.y == 0 or bounds.end.x == cell.get_width() or bounds.end.y == cell.get_height()):
			fail(id + " touches source cell border; possible clipping or bleed")
		var bust = cell.get_region(bounds)
		var ratio = min(LIMIT.x / float(bust.get_width()), LIMIT.y / float(bust.get_height()))
		var scaled_size = Vector2i(max(1, int(floor(bust.get_width() * ratio))), max(1, int(floor(bust.get_height() * ratio))))
		bust.resize(scaled_size.x, scaled_size.y, Image.INTERPOLATE_NEAREST)
		var portrait = Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
		portrait.fill(Color.TRANSPARENT)
		var placement = Vector2i((SIZE.x - scaled_size.x) / 2, (SIZE.y - scaled_size.y) / 2)
		portrait.blit_rect(bust, Rect2i(Vector2i.ZERO, scaled_size), placement)
		var target = output.path_join(id + ".png")
		if verify_only:
			var saved = Image.load_from_file(target)
			if saved == null:
				fail(id + " missing output")
				continue
			saved.convert(Image.FORMAT_RGBA8)
			if saved.get_size() != SIZE or saved.get_data() != portrait.get_data():
				fail(id + " output differs from exact crop/nearest-neighbor recipe")
			portrait = saved
		else:
			save_immutable(portrait, target)
		var metrics = stats(portrait)
		var final_bounds = portrait.get_used_rect()
		var margins = [final_bounds.position.x, final_bounds.position.y, SIZE.x - final_bounds.end.x, SIZE.y - final_bounds.end.y]
		for margin in margins:
			if margin < 4:
				fail(id + " fails 4px transparent margin")
		if metrics.transparent_pixels == 0 or metrics.opaque_pixels == 0:
			fail(id + " invalid alpha")
		var record = {"source_cell": [left, top, cell_rect.size.x, cell_rect.size.y], "source_content_rect": [bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y], "nearest_size": [scaled_size.x, scaled_size.y], "placement": [placement.x, placement.y], "size": [128, 160], "margins_ltrb": margins, "rgba": metrics, "sha256": sha256(target)}
		report.portraits[id] = record
		atlas[id] = {"path": "res://art/production/p1/story_portraits_r14/" + id + ".png", "size": [128, 160]}
		preview.blit_rect(portrait, Rect2i(Vector2i.ZERO, SIZE), Vector2i(col * SIZE.x, row * SIZE.y))
		slate_preview.blend_rect(portrait, Rect2i(Vector2i.ZERO, SIZE), Vector2i(col * SIZE.x, row * SIZE.y))
		ivory_preview.blend_rect(portrait, Rect2i(Vector2i.ZERO, SIZE), Vector2i(col * SIZE.x, row * SIZE.y))
		print(id, " ", JSON.stringify(record))
	if not verify_only and not failed:
		write_json(output.path_join("atlas.json"), atlas)
		save_immutable(preview, docs.path_join("evidence/preview_1x.png"))
		save_immutable(slate_preview, docs.path_join("evidence/preview_slate_1x.png"))
		save_immutable(ivory_preview, docs.path_join("evidence/preview_ivory_1x.png"))
		preview.resize(768, 640, Image.INTERPOLATE_NEAREST)
		save_immutable(preview, docs.path_join("evidence/preview_2x_nearest.png"))
		write_json(docs.path_join("evidence/rgba-check.json"), report)
	if verify_only:
		var saved_atlas = JSON.parse_string(FileAccess.get_file_as_string(output.path_join("atlas.json")))
		if not saved_atlas is Dictionary or saved_atlas != JSON.parse_string(JSON.stringify(atlas)):
			fail("atlas.json mapping differs from required IDs, res paths or sizes")
		var expected = JSON.parse_string(FileAccess.get_file_as_string(docs.path_join("evidence/rgba-check.json")))
		if not expected is Dictionary or expected.source_sha256 != report.source_sha256 or expected.portraits != JSON.parse_string(JSON.stringify(report.portraits)):
			fail("Saved RGBA report, geometry or PNG SHA256 differs from current files")
		var packed_preview = Image.load_from_file(docs.path_join("evidence/preview_1x.png"))
		if packed_preview == null or packed_preview.get_size() != Vector2i(384, 320) or packed_preview.get_data() != preview.get_data():
			fail("Transparent preview differs from exact fixed-cell pack")
		elif packed_preview.get_region(Rect2i(256, 160, 128, 160)).get_used_rect().has_area():
			fail("Final preview sixth cell is not alpha=0")
	print("RESULT ", "FAIL" if failed else "PASS", " mode=", "verify" if verify_only else "pack")
	quit(1 if failed else 0)

func stats(img: Image) -> Dictionary:
	var data = img.get_data()
	var transparent := 0
	var partial := 0
	var opaque := 0
	for i in range(3, data.size(), 4):
		if data[i] == 0:
			transparent += 1
		elif data[i] == 255:
			opaque += 1
		else:
			partial += 1
	return {"format": "RGBA8", "transparent_pixels": transparent, "partial_alpha_pixels": partial, "opaque_pixels": opaque}

func sha256(path: String) -> String:
	var ctx = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(FileAccess.get_file_as_bytes(path))
	return ctx.finish().hex_encode()

func save_immutable(img: Image, path: String) -> void:
	if FileAccess.file_exists(path):
		if FileAccess.get_file_as_bytes(path) != img.save_png_to_buffer():
			fail("Refusing to overwrite different existing raster: " + path)
		return
	if img.save_png(path) != OK:
		fail("PNG save failed: " + path)

func write_json(path: String, value: Dictionary) -> void:
	var file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(value, "\t") + "\n")

func fail(message: String) -> void:
	failed = true
	push_error(message)
