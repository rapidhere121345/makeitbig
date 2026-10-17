extends SceneTree

const BakeCore := preload("res://tools/world_manifest/bake_core.gd")

## Offline native-source bake. Never patches or merges a second map; the
## native scene is the only authoring input and every failure fails closed.
## Usage:
##   godot --headless --path . --script res://tools/world_manifest/derive.gd -- \
##     --scene=res://...tscn --output=res://...spatial.json [--asset-out=res://...asset.json]
func _initialize() -> void:
	var scene_path := ""
	var output_path := ""
	var asset_out_path := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--scene="):
			scene_path = argument.trim_prefix("--scene=")
		elif argument.begins_with("--output="):
			output_path = argument.trim_prefix("--output=")
		elif argument.begins_with("--asset-out="):
			asset_out_path = argument.trim_prefix("--asset-out=")
		else:
			printerr("unknown_argument:" + argument)
			quit(1)
			return
	if scene_path.is_empty() or output_path.is_empty():
		printerr("--scene and --output required")
		quit(1)
		return
	var result: Dictionary = BakeCore.bake_scene(scene_path, output_path)
	if not bool(result.get("ok", false)):
		printerr("bake_failed:" + str(result.get("errors", [])))
		quit(1)
		return
	var written := BakeCore.write_manifest(result, output_path)
	if not bool(written.get("ok", false)):
		printerr("manifest_output_unwritable")
		quit(1)
		return
	if not asset_out_path.is_empty():
		var asset_written := BakeCore.write_world_asset(result, asset_out_path)
		if not bool(asset_written.get("ok", false)):
			printerr("asset_output_unwritable")
			quit(1)
			return
		print("NATIVE_WORLD_ASSET_BAKED " + scene_path + " -> " + asset_out_path)
	print("NATIVE_MANIFEST_DERIVED " + scene_path + " -> " + output_path)
	quit(0)
