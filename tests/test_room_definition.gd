extends SceneTree

const RoomDefinitionScript = preload("res://src/runtime/world/room_definition.gd")
const WorldAssetScript = preload("res://src/runtime/world/world_asset.gd")
const SpatialManifestScript = preload("res://src/runtime/world/spatial_manifest.gd")

var failures: Array[String] = []


func _initialize() -> void:
	_test_room_validation()
	_test_world_asset_is_static()
	_test_manifest_digest_is_stable()
	_test_runtime_state_does_not_write_back()
	_test_channels_do_not_mix()
	for failure: String in failures:
		printerr(failure)
	print("PASS test_room_definition.gd" if failures.is_empty() else "FAIL test_room_definition.gd")
	quit(0 if failures.is_empty() else 1)


func _test_room_validation() -> void:
	var valid := RoomDefinitionScript.new({
		"room_id": "chapter1.hearth",
		"world_asset_id": "world.hearth.v1",
		"encounter_id": "encounter.none",
		"ruleset_id": "ranger.chapter1",
		"tags": ["town", "safe"],
	})
	_expect(valid.is_valid(), "a complete room definition must validate")
	_expect(valid.snapshot()["tags"] == ["safe", "town"], "room tags must have stable semantic order")
	var missing := RoomDefinitionScript.validate_data({
		"room_id": "room.only",
		"world_asset_id": "asset",
		"encounter_id": "encounter",
		"ruleset_id": "rules",
	})
	_expect(_contains(missing, "missing_field:tags"), "missing tags must be rejected")
	var unknown := RoomDefinitionScript.validate_data({
		"room_id": "room",
		"world_asset_id": "asset",
		"encounter_id": "encounter",
		"ruleset_id": "rules",
		"tags": ["town"],
		"runtime_state": {"entered": true},
	})
	_expect(_contains(unknown, "unknown_field:runtime_state"), "unknown room fields must be rejected")


func _test_world_asset_is_static() -> void:
	var asset := WorldAssetScript.new("res://world/hearth.tscn", "res://world/hearth.spatial.json", "game", "presentation", 1)
	_expect(asset.is_valid(), "a complete world asset must validate")
	_expect(not asset.snapshot().has("runtime_state"), "world asset must not expose runtime state")
	_expect(WorldAssetScript.validate_data({"world_scene_path": "scene"}).has("missing_field:manifest_path"), "world asset fields are required")


func _test_manifest_digest_is_stable() -> void:
	var first := _manifest_fixture(false)
	var second := _manifest_fixture(true)
	var normalized := SpatialManifestScript.normalize_data(first.snapshot())
	_expect(bool(normalized.get("ok", false)), "a legal spatial manifest must normalize")
	_expect(SpatialManifestScript.validate_data(first.snapshot()).is_empty(), "a legal spatial manifest must validate")
	_expect(first.digest_input() == second.digest_input(), "manifest digest input must ignore authored dictionary and stable collection order")
	_expect(first.digest_sha256() == second.digest_sha256(), "manifest digest must be stable")
	_expect(first.digest_input()["stable_bindings"][0]["binding_id"] == "gate.a", "stable bindings must sort by stable id")


func _test_runtime_state_does_not_write_back() -> void:
	var manifest := _manifest_fixture(false)
	var snapshot: Dictionary = manifest.snapshot()
	snapshot["stable_bindings"][0]["runtime_state"] = {"open": true}
	snapshot["stable_bindings"][0]["channels"]["movement"] = false
	_expect(manifest.movement_bindings().size() == 1, "mutating a snapshot must not change manifest state")
	_expect(not manifest.digest_input()["stable_bindings"][0].has("runtime_state"), "runtime keys must not enter digest input")
	var source := FileAccess.get_file_as_string("res://src/runtime/world/spatial_manifest.gd")
	_expect(not source.contains("var runtime_state") and not source.contains("var instance_id"), "manifest must not own runtime state fields")


func _test_channels_do_not_mix() -> void:
	var manifest := _manifest_fixture(false)
	_expect(manifest.movement_bindings().size() == 1, "movement channel must select only movement bindings")
	_expect(manifest.navigation_bindings().size() == 1, "navigation channel must select only navigation bindings")
	_expect(manifest.vision_occluders().size() == 1, "vision channel must select only vision occluders")
	_expect(manifest.projectile_blockers().size() == 1, "projectile channel must select only projectile blockers")
	_expect(manifest.occlusion_bindings().size() == 1, "occlusion channel must select only occlusion bindings")
	_expect(manifest.bindings_for_channel("unknown").is_empty(), "unknown channels must not fall through to another channel")
	_expect(not source_has_method("is_blocked"), "the contract must not expose a universal is_blocked helper")


func _manifest_fixture(reverse_order: bool) -> RefCounted:
	var bindings: Array = [
		{"binding_id": "gate.b", "channels": {"movement": false, "navigation": true, "vision": false, "projectile": false, "occlusion": false}},
		{"binding_id": "gate.a", "channels": {"movement": true, "navigation": false, "vision": true, "projectile": true, "occlusion": true}},
	]
	if reverse_order:
		bindings.reverse()
	var data := {
		"coordinate_convention": {"up": "negative_y", "units": "pixel"},
		"stable_bindings": bindings,
		"traversal_profiles": [{"profile_id": "default", "speed": 1}],
		"regions_and_portals": [{"region_id": "hearth", "portals": ["gate.a"]}],
		"spawn_interaction_exit_sockets": [{"socket_id": "exit.main", "kind": "exit"}],
		"gameplay_spatial_metadata": {"room_kind": "safe"},
	}
	return SpatialManifestScript.new(data)


func source_has_method(method_name: String) -> bool:
	for method: Dictionary in SpatialManifestScript.new().get_method_list():
		if String(method.get("name", "")) == method_name:
			return true
	return false


func _contains(values: Array[String], expected: String) -> bool:
	return values.has(expected)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
