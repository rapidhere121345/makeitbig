extends SceneTree

func _initialize() -> void:
	var repo = get_script().resource_path.get_base_dir().path_join("../../..").simplify_path()
	for version in ["v03"]:
		var img = Image.load_from_file(repo.path_join("docs/art-production/p1-story-portraits-r14/sources/portraits-" + version + "-original.png"))
		img.convert(Image.FORMAT_RGBA8)
		print(version)
		for index in range(6):
			var col = index % 3
			var row = index / 3
			var x = col * 458
			var y = int(row * 1145 / 2.0)
			var end_y = int((row + 1) * 1145 / 2.0)
			var counts = {}
			for threshold in [1, 8, 32, 128, 240, 254, 255]:
				var count := 0
				var low = Vector2i(img.get_width(), img.get_height())
				var high = Vector2i.ZERO
				for py in range(y, end_y):
					for px in range(x, x + 458):
						if roundi(img.get_pixel(px, py).a * 255) >= threshold:
							count += 1
							low = low.min(Vector2i(px, py))
							high = high.max(Vector2i(px, py))
				counts[str(threshold)] = {"count": count, "min": str(low), "max": str(high)}
			print(index, " ", JSON.stringify(counts))
	quit()
