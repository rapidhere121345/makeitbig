extends RefCounted

## Offline WorldAsset/SpatialManifest baker.  Native Godot scenes are the
## only authoring input: the baker validates the native scene contract,
## derives the immutable spatial manifest payload, enforces the authoring
## validation tier and computes the two detached build digests.  There is
## no compatibility shimming here; any invalid input fails closed.

const SpatialManifestScript = preload("res://src/runtime/world/spatial_manifest.gd")
const WorldAssetScript = preload("res://src/runtime/world/world_asset.gd")

const SCHEMA_VERSION: int = WorldAssetScript.SCHEMA_VERSION


## Bakes one native room scene into {manifest, world_asset} payloads.
## expected is forwarded to RoomAssetRoot.validate_contract().
static func bake_scene(scene_path: String, manifest_path: String, expected: Dictionary = {}) -> Dictionary:
	if scene_path.strip_edges().is_empty() or manifest_path.strip_edges().is_empty():
		return _failure(["missing_bake_paths"])
	var packed := load(scene_path) as PackedScene
	if packed == null:
		return _failure(["invalid_native_scene"])
	var scene := packed.instantiate()
	var author: Node = scene if scene.has_method("validate_contract") else scene.get_node_or_null("RoomAsset")
	if author == null or not author.has_method("derive_spatial_manifest"):
		scene.free()
		return _failure(["missing_native_author"])
	var expected_contract: Dictionary = expected.duplicate(true)
	if not expected_contract.has("gameplay_source"):
		expected_contract["gameplay_source"] = manifest_path.get_file()
	var report: Dictionary = author.call("validate_contract", expected_contract)
	if not bool(report.get("ok", false)):
		scene.free()
		return _failure(_prefix_errors("native_contract_invalid", report.get("errors", [])))
	var payload: Variant = author.call("derive_spatial_manifest")
	scene.free()
	if not payload is Dictionary:
		return _failure(["native_derive_failed"])
	var authoring_errors := SpatialManifestScript.validate_authoring_data(payload)
	if not authoring_errors.is_empty():
		return _failure(_prefix_errors("authoring_invalid", authoring_errors))
	var normalized := SpatialManifestScript.normalize_data(payload)
	if not bool(normalized.get("ok", false)):
		return _failure(_prefix_errors("manifest_invalid", normalized.get("errors", [])))
	var gameplay := SpatialManifestScript.digest_payload_sha256(SpatialManifestScript.gameplay_digest_input(payload))
	var presentation := SpatialManifestScript.digest_payload_sha256(SpatialManifestScript.presentation_digest_input(payload))
	var asset := {
		"world_scene_path": scene_path,
		"manifest_path": manifest_path,
		"gameplay_digest": gameplay,
		"presentation_digest": presentation,
		"schema_version": SCHEMA_VERSION,
	}
	var asset_errors := WorldAssetScript.validate_data(asset)
	if not asset_errors.is_empty():
		return _failure(_prefix_errors("world_asset_invalid", asset_errors))
	return {
		"ok": true,
		"errors": [],
		"scene_path": scene_path,
		"manifest_path": manifest_path,
		"manifest": normalized["value"],
		"world_asset": asset,
	}


static func write_manifest(result: Dictionary, path: String) -> Dictionary:
	return _write_json(result.get("manifest", null), path)


static func write_world_asset(result: Dictionary, path: String) -> Dictionary:
	return _write_json(result.get("world_asset", null), path)


static func _write_json(payload: Variant, path: String) -> Dictionary:
	if not payload is Dictionary:
		return {"ok": false, "errors": ["missing_bake_payload"]}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "errors": ["output_unwritable:%s" % path]}
	file.store_string(JSON.stringify(payload, "\t", true, true) + "\n")
	file.close()
	return {"ok": true, "errors": []}


static func _failure(errors: Array) -> Dictionary:
	var typed: Array[String] = []
	for error: Variant in errors:
		typed.append(str(error))
	return {"ok": false, "errors": typed, "manifest": {}, "world_asset": {}}


static func _prefix_errors(prefix: String, errors: Variant) -> Array:
	var result: Array = []
	if errors is Array:
		for error: Variant in errors:
			result.append("%s:%s" % [prefix, str(error)])
	else:
		result.append(prefix)
	return result
