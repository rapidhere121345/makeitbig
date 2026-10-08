extends SceneTree
## Deterministic import of imagegen originals into the existing native cells.
## Only crop transparent margins, nearest-sample, and pack. Originals are kept;
## this tool does not generate artwork, recolour it, or change runtime anchors.

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1:
		printerr("Usage: --script pack.gd -- /absolute/recipe.json")
		quit(2)
		return
	var recipe: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var output := String(recipe.output)
	if not output.is_absolute_path() or DirAccess.dir_exists_absolute(output):
		printerr("Output must be a new absolute directory")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	var records: Array[Dictionary] = []
	for spec: Dictionary in recipe.sheets:
		var source := Image.load_from_file(String(spec.source))
		var template := Image.load_from_file(String(spec.template)) if spec.has("template") else null
		if source == null or (spec.has("template") and template == null):
			quit(3)
			return
		source.convert(Image.FORMAT_RGBA8)
		var grid := Vector2i(int(spec.grid[0]), int(spec.grid[1]))
		var source_grid := Vector2i(int(spec.get("source_grid", spec.grid)[0]), int(spec.get("source_grid", spec.grid)[1]))
		var size: Vector2i = template.get_size() if template != null else Vector2i(int(spec.size[0]), int(spec.size[1]))
		var cell := Vector2i(size.x / grid.x, size.y / grid.y)
		var packed := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
		var cells: Array[Dictionary] = []
		for index in range(grid.x * grid.y):
			var to_cell := Vector2i(index % grid.x, index / grid.x)
			var from_cell := to_cell
			if spec.has("cells"):
				from_cell = Vector2i(int(spec.cells[index][0]), int(spec.cells[index][1]))
			var begin := Vector2i(from_cell.x * source.get_width() / source_grid.x, from_cell.y * source.get_height() / source_grid.y)
			var end := Vector2i((from_cell.x + 1) * source.get_width() / source_grid.x, (from_cell.y + 1) * source.get_height() / source_grid.y)
			var source_rect := Rect2i(begin, end - begin)
			# Some generated poses reach across an otherwise uniform cell border.
			# Explicit import rectangles can exclude the adjacent actor's pixels;
			# this is a crop of the original, never a repaint of the sprite.
			var overrides: Dictionary = spec.get("source_rects", {})
			if overrides.has(str(index)):
				var declared: Array = overrides[str(index)]
				source_rect = Rect2i(int(declared[0]), int(declared[1]), int(declared[2]), int(declared[3]))
				begin = source_rect.position
			var cut := source.get_region(source_rect)
			var crop := _body_bounds(cut)
			var target := template.get_region(Rect2i(to_cell * cell, cell)).get_used_rect() if template != null else Rect2i(Vector2i.ONE, cell - Vector2i(2, 2))
			if crop.size.x == 0 or crop.size.y == 0 or not target.has_area():
				printerr("Empty cell: ", spec.file, " ", index)
				quit(3)
				return
			var factor := minf(float(target.size.x) / crop.size.x, float(target.size.y) / crop.size.y)
			var fitted := Vector2i(maxi(1, int(crop.size.x * factor)), maxi(1, int(crop.size.y * factor)))
			var pixels := cut.get_region(crop)
			pixels.resize(fitted.x, fitted.y, Image.INTERPOLATE_NEAREST)
			var destination := to_cell * cell + Vector2i(target.position.x + (target.size.x - fitted.x) / 2, target.end.y - fitted.y)
			packed.blit_rect(pixels, Rect2i(Vector2i.ZERO, fitted), destination)
			cells.append({"index":index, "source":[begin.x + crop.position.x, begin.y + crop.position.y, crop.size.x, crop.size.y], "destination":[destination.x,destination.y,fitted.x,fitted.y]})
		var path := output.path_join(String(spec.file))
		if String(spec.file).get_file() != String(spec.file) or packed.save_png(path) != OK:
			printerr("Invalid output filename or save failed")
			quit(3)
			return
		records.append({"file":spec.file, "source":spec.source, "source_sha256":FileAccess.get_sha256(spec.source), "sha256":FileAccess.get_sha256(path), "size":[size.x,size.y], "cells":cells})
	var report := FileAccess.open(output.path_join("IMPORT.json"), FileAccess.WRITE)
	report.store_string(JSON.stringify({"recipe":args[0],"recipe_sha256":FileAccess.get_sha256(args[0]),"operation":"transparent-margin crop, native nearest-neighbour fit, fixed cell packing","sheets":records}, "\t") + "\n")
	print("R13_STYLE_IMPORT_PASS sheets=", records.size())
	quit(0)


func _body_bounds(pixels: Image) -> Rect2i:
	# Bound by the solid body instead of a near-transparent generated glow.
	# Alpha inside the selected crop is preserved verbatim through the import.
	var low := pixels.get_size()
	var high := Vector2i(-1, -1)
	for y in pixels.get_height():
		for x in pixels.get_width():
			if pixels.get_pixel(x, y).a < 0.5:
				continue
			low = Vector2i(mini(low.x, x), mini(low.y, y))
			high = Vector2i(maxi(high.x, x), maxi(high.y, y))
	return Rect2i(low, high - low + Vector2i.ONE) if high.x >= low.x else Rect2i()
