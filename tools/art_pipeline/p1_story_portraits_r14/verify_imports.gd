extends SceneTree
## Technical validation only: do not modify either authored or imported pixels.

func _initialize() -> void:
	var output := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="): output = arg.trim_prefix("--report=")
	if not output.is_absolute_path():
		quit(2)
		return
	var frozen: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/art-production/p1-story-portraits-r14/FROZEN.json"))
	var checks: Array = []
	var failures: Array[String] = []
	for entry: Dictionary in frozen.pngs:
		var path := String(entry.res_path)
		var raw := Image.load_from_file(path)
		var texture := ResourceLoader.load(path, "Texture2D") as Texture2D
		var imported: Image = texture.get_image() if texture != null else null
		var ok := raw != null and imported != null and texture is CompressedTexture2D
		if ok:
			raw.convert(Image.FORMAT_RGBA8)
			if imported.is_compressed(): imported.decompress()
			imported.convert(Image.FORMAT_RGBA8)
			ok = raw.get_size() == Vector2i(128,160) and raw.get_size() == imported.get_size() and raw.get_data() == imported.get_data()
			ok = ok and FileAccess.get_sha256(path) == String(entry.sha256)
		checks.append({"id":entry.id,"path":path,"native_import_exact_rgba8":ok,
			"source_sha256":FileAccess.get_sha256(path), "raw_rgba8_sha256":_hash(raw.get_data()) if raw != null else "",
			"imported_rgba8_sha256":_hash(imported.get_data()) if imported != null else ""})
		if not ok: failures.append(path)
	FileAccess.open(output, FileAccess.WRITE).store_string(JSON.stringify({"status":"pass" if failures.is_empty() else "fail", "checks":checks,"failures":failures},"\t")+"\n")
	print("R14_PORTRAITS_EXACT_RGBA ", "PASS" if failures.is_empty() else "FAIL", " count=",checks.size())
	quit(0 if failures.is_empty() else 1)


func _hash(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()
