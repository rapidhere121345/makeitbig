extends SceneTree

## Offline native-source manifest build. Never patch or merge a second map.
## Usage: godot --headless --path . --script res://tools/world_manifest/derive.gd -- --scene=res://...tscn --output=res://...spatial.json
func _initialize() -> void:
	var scene_path := ""
	var output_path := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--scene="):
			scene_path = argument.trim_prefix("--scene=")
		elif argument.begins_with("--output="):
			output_path = argument.trim_prefix("--output=")
		else:
			printerr("unknown_argument:" + argument)
			quit(1)
			return
	if scene_path.is_empty() or output_path.is_empty():
		printerr("--scene and --output required")
		quit(1)
		return
	var packed := load(scene_path) as PackedScene
	if packed == null:
		printerr("invalid_native_scene")
		quit(1)
		return
	var scene := packed.instantiate()
	var author := scene if scene.has_method("validate_contract") else scene.get_node_or_null("RoomAsset")
	if author == null or not author.has_method("derive_spatial_manifest"):
		printerr("missing_native_author")
		scene.free()
		quit(1)
		return
	var report: Dictionary = author.validate_contract({"gameplay_source": output_path.get_file()})
	if not bool(report.ok):
		printerr("native_contract_invalid:" + str(report.errors))
		scene.free()
		quit(1)
		return
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		printerr("manifest_output_unwritable")
		scene.free()
		quit(1)
		return
	file.store_string(JSON.stringify(author.derive_spatial_manifest(), "\t", true, true) + "\n")
	file.close()
	scene.free()
	print("NATIVE_MANIFEST_DERIVED " + scene_path + " -> " + output_path)
	quit(0)
