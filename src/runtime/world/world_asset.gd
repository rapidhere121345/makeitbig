class_name WorldAsset
extends RefCounted

## Static references and build digests for a world asset.  This object has no
## runtime node, instance identifier, transform or mutable simulation state.

const SpatialManifestScript = preload("res://src/runtime/world/spatial_manifest.gd")

## The only schema version the pipeline bakes and verifies.
const SCHEMA_VERSION: int = 1

const FIELDS: Array[String] = [
	"world_scene_path",
	"manifest_path",
	"gameplay_digest",
	"presentation_digest",
	"schema_version",
]

var world_scene_path: String = ""
var manifest_path: String = ""
var gameplay_digest: String = ""
var presentation_digest: String = ""
var schema_version: int = 0


func _init(
	world_scene_path_value: Variant = "",
	manifest_path_value: Variant = "",
	gameplay_digest_value: Variant = "",
	presentation_digest_value: Variant = "",
	schema_version_value: Variant = 0
) -> void:
	if world_scene_path_value is Dictionary:
		_assign_dictionary(world_scene_path_value as Dictionary)
		return
	world_scene_path = _text(world_scene_path_value)
	manifest_path = _text(manifest_path_value)
	gameplay_digest = _text(gameplay_digest_value)
	presentation_digest = _text(presentation_digest_value)
	schema_version = schema_version_value as int if schema_version_value is int else 0


static func from_dict(value: Variant) -> RefCounted:
	return _new_instance(value if value is Dictionary else {})


## Rebuilds the runtime asset record from an offline bake result (the
## dictionary produced by the tools/world_manifest baker).  Unknown bake
## shapes normalize to an invalid asset instead of being guessed.
static func from_bake(bake: Variant) -> RefCounted:
	if not bake is Dictionary:
		return _new_instance({})
	var payload: Dictionary = bake
	if payload.has("world_asset") and payload["world_asset"] is Dictionary:
		payload = payload["world_asset"]
	return _new_instance(payload)


## Pipeline verification gate between bake and mount: the manifest that is
## actually loaded must still reproduce both baked digests.  Accepts a
## SpatialManifest instance or an already canonical manifest dictionary.
func matches_manifest(manifest_value: Variant) -> Dictionary:
	var asset_errors := validate()
	if not asset_errors.is_empty():
		return {"ok": false, "errors": asset_errors, "value": {}}
	var manifest_payload: Variant = manifest_value
	if manifest_value is SpatialManifestScript:
		manifest_payload = manifest_value.call("snapshot")
	if not manifest_payload is Dictionary or not SpatialManifestScript.validate_data(manifest_payload).is_empty():
		return {"ok": false, "errors": ["invalid_manifest"], "value": {}}
	var manifest: Dictionary = manifest_payload
	var errors: Array[String] = []
	var gameplay := SpatialManifestScript.digest_payload_sha256(SpatialManifestScript.gameplay_digest_input(manifest))
	if gameplay != gameplay_digest:
		errors.append("digest_mismatch:gameplay")
	var presentation := SpatialManifestScript.digest_payload_sha256(SpatialManifestScript.presentation_digest_input(manifest))
	if presentation != presentation_digest:
		errors.append("digest_mismatch:presentation")
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"value": {"gameplay_digest": gameplay, "presentation_digest": presentation},
	}


func validate() -> Array[String]:
	var errors: Array[String] = []
	if world_scene_path.strip_edges().is_empty():
		errors.append("missing_or_empty:world_scene_path")
	if manifest_path.strip_edges().is_empty():
		errors.append("missing_or_empty:manifest_path")
	if gameplay_digest.strip_edges().is_empty():
		errors.append("missing_or_empty:gameplay_digest")
	if presentation_digest.strip_edges().is_empty():
		errors.append("missing_or_empty:presentation_digest")
	if schema_version <= 0:
		errors.append("invalid:schema_version")
	return errors


func is_valid() -> bool:
	return validate().is_empty()


func snapshot() -> Dictionary:
	return {
		"world_scene_path": world_scene_path.strip_edges(),
		"manifest_path": manifest_path.strip_edges(),
		"gameplay_digest": gameplay_digest.strip_edges(),
		"presentation_digest": presentation_digest.strip_edges(),
		"schema_version": schema_version,
	}


func digest_input() -> Dictionary:
	return snapshot()


static func validate_data(value: Variant) -> Array[String]:
	if not value is Dictionary:
		return ["invalid_type:world_asset"]
	var data: Dictionary = value
	var errors: Array[String] = []
	for field: String in FIELDS:
		if not data.has(field):
			errors.append("missing_field:%s" % field)
	for key: Variant in data.keys():
		var text_key := str(key)
		if not FIELDS.has(text_key):
			errors.append("unknown_field:%s" % text_key)
	var asset = _new_instance(data)
	for error: String in asset.validate():
		if not errors.has(error):
			errors.append(error)
	return errors


static func normalize_data(value: Variant) -> Dictionary:
	var errors := validate_data(value)
	if not errors.is_empty():
		return {"ok": false, "errors": errors, "value": {}}
	return {"ok": true, "errors": [], "value": _new_instance(value).snapshot()}


func _assign_dictionary(data: Dictionary) -> void:
	world_scene_path = _text(data.get("world_scene_path", ""))
	manifest_path = _text(data.get("manifest_path", ""))
	gameplay_digest = _text(data.get("gameplay_digest", ""))
	presentation_digest = _text(data.get("presentation_digest", ""))
	schema_version = data.get("schema_version", 0) as int if data.get("schema_version", 0) is int else 0


static func _new_instance(value: Dictionary) -> RefCounted:
	return load("res://src/runtime/world/world_asset.gd").new(value)


static func _text(value: Variant) -> String:
	if value is String or value is StringName:
		return String(value)
	return ""
