extends SceneTree
## Offline derivative only. Production SceneRuntime compares this payload with
## the native author source and never silently repairs a stale manifest.
const NativeScene := preload("res://content/rooms/town/hearthside.tscn")
const SpatialManifestScript := preload("res://src/runtime/world/spatial_manifest.gd")

func _initialize() -> void:
	var source := NativeScene.instantiate()
	var manifest = SpatialManifestScript.new(source.derive_spatial_manifest())
	if not manifest.is_valid():
		printerr(manifest.validate())
		source.free()
		quit(1)
		return
	var file := FileAccess.open("res://content/rooms/town/hearthside.spatial.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest.snapshot(), "\t", true, true) + "\n")
	file.close()
	source.free()
	print("TOWN_SPATIAL_BAKE PASS")
	quit(0)
