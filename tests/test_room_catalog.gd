extends SceneTree

const RoomCatalogScript := preload("res://src/runtime/world/room_catalog.gd")

var failures: Array[String] = []


func _initialize() -> void:
	_test_catalog_validates()
	_test_layout_resolutions()
	_test_presentation_and_spawn_profiles()
	_test_explicit_fixture_profile()
	_test_profile_failures_close()
	_test_runtime_has_no_layout_manifest_branch()
	for failure: String in failures:
		printerr("- %s" % failure)
	print("PASS test_room_catalog.gd" if failures.is_empty() else "FAIL test_room_catalog.gd")
	quit(0 if failures.is_empty() else 1)


func _test_catalog_validates() -> void:
	var catalog = RoomCatalogScript.new()
	_expect(catalog.load_errors.is_empty(), "catalog: shipped room catalog did not validate: %s" % str(catalog.load_errors))
	var data: Dictionary = catalog.catalog()
	_expect(bool(data.get("ok", false)) and (data.get("rooms", []) as Array).size() == 3, "catalog: shipped catalog did not expose exactly three rooms")
	var invalid_path: Dictionary = data.duplicate(true)
	(invalid_path.rooms[0] as Dictionary)["world_scene_path"] = "res://content/rooms/combat/missing.tscn"
	var errors: Array[String] = catalog.validate_catalog(invalid_path)
	_expect(_has_fragment(errors, "missing_asset:world_scene_path"), "catalog: a missing native scene path was accepted: %s" % str(errors))
	var unknown_field: Dictionary = data.duplicate(true)
	(unknown_field.rooms[0] as Dictionary)["unexpected"] = true
	_expect(_has_fragment(catalog.validate_catalog(unknown_field), "unknown_field:unexpected"), "catalog: unknown fields were accepted")


func _test_layout_resolutions() -> void:
	var catalog = RoomCatalogScript.new()
	var resolved_paths: Dictionary = {}
	for layout_id: String in ["rectangle_arena", "corridor", "ring"]:
		var room := {"room_id": "generated.%s" % layout_id, "layout_id": layout_id}
		var resolved: Dictionary = catalog.resolve(room)
		_expect(bool(resolved.get("ok", false)), "catalog: failed to resolve %s: %s" % [layout_id, str(resolved)])
		resolved_paths[layout_id] = String(resolved.get("world_scene_path", ""))
		_expect(String(resolved.get("room_id", "")) == String(room.room_id), "catalog: arbitrary room id was not preserved for %s" % layout_id)
	var alias_result: Dictionary = catalog.resolve({"room_id": "arbitrary.room", "layout": "corridor"})
	_expect(bool(alias_result.get("ok", false)) and String(alias_result.get("layout_id", "")) == "corridor", "catalog: layout alias was not resolved")
	var paths: Array[String] = [String(resolved_paths.rectangle_arena), String(resolved_paths.corridor), String(resolved_paths.ring)]
	_expect(paths[0] != paths[1] and paths[0] != paths[2] and paths[1] != paths[2], "catalog: native scene paths were not distinct")
	var unknown: Dictionary = catalog.resolve({"room_id": "room.deep-copy", "layout_id": "unknown_layout"})
	_expect(String(unknown.get("error", "")) == "unknown_room_layout", "catalog: unknown layout did not return an explicit error")
	var missing: Dictionary = catalog.resolve({"room_id": "room.deep-copy"})
	_expect(String(missing.get("error", "")) == "missing_room_layout", "catalog: missing layout did not return an explicit error")


func _test_presentation_and_spawn_profiles() -> void:
	var catalog = RoomCatalogScript.new()
	var rectangle_presentation: Dictionary = catalog.presentation("rectangle_arena")
	_expect(String(rectangle_presentation.get("display_name", "")) == "破碎前哨", "catalog: rectangle presentation was not content-owned")
	_expect(String(rectangle_presentation.get("exit_hint", "")) == "清场后穿过东侧残门。", "catalog: rectangle presentation fields were incomplete")
	_expect(String(catalog.presentation("corridor").get("display_name", "")) == "风切通道", "catalog: corridor presentation was not resolved")
	_expect(String(catalog.presentation("ring").get("display_name", "")) == "回收环场", "catalog: ring presentation was not resolved")

	_expect_offsets(catalog.spawn_offsets({"layout_id": "rectangle_arena", "room_id": "generated.rectangle"}, 5), [
		Vector2(-145.0, -80.0), Vector2(0.0, -80.0), Vector2(145.0, -80.0),
		Vector2(-145.0, 30.0), Vector2(0.0, 30.0),
	], "rectangle default")
	_expect_offsets(catalog.spawn_offsets({"layout_id": "rectangle_arena", "room_id": "first_hunt_clear"}, 3), [
		Vector2(-220.0, 100.0) + Vector2.from_angle(deg_to_rad(-69.0)) * 350.0,
		Vector2(-220.0, 100.0) + Vector2.from_angle(deg_to_rad(-35.0)) * 350.0,
		Vector2(-220.0, 100.0) + Vector2.from_angle(0.0) * 350.0,
	], "rectangle first hunt")
	_expect_offsets(catalog.spawn_offsets({"layout_id": "rectangle_arena", "room_id": "first_hunt_followup"}, 3), [
		Vector2(-220.0, 100.0) + Vector2.from_angle(deg_to_rad(-60.0)) * 350.0,
		Vector2(-220.0, 100.0) + Vector2.from_angle(deg_to_rad(-25.0)) * 350.0,
		Vector2(-220.0, 100.0) + Vector2.from_angle(deg_to_rad(10.0)) * 350.0,
	], "rectangle follow-up")
	_expect_offsets(catalog.spawn_offsets({"layout_id": "corridor", "room_id": "generated.corridor"}, 5), [
		Vector2(-180.0, -42.0), Vector2(-60.0, 42.0), Vector2(60.0, -42.0),
		Vector2(180.0, 42.0), Vector2(-180.0, -42.0),
	], "corridor default")
	var corridor_followup: Array[Vector2] = catalog.spawn_offsets({"layout_id": "corridor", "room_id": "first_hunt_followup"}, 3)
	var corridor_expected: Array[Vector2] = []
	for offset_y: float in [-4.0, -3.0, -2.0]:
		corridor_expected.append(Vector2(-220.0, 58.0) + Vector2(sqrt(350.0 * 350.0 - offset_y * offset_y), offset_y))
	_expect_offsets(corridor_followup, corridor_expected, "corridor follow-up")
	_expect_offsets(catalog.spawn_offsets({"layout_id": "ring", "room_id": "generated.ring"}, 4), [
		Vector2(0.0, -175.0), Vector2(175.0, 0.0), Vector2(0.0, 175.0), Vector2(-175.0, 0.0),
	], "ring default")


func _test_profile_failures_close() -> void:
	var catalog = RoomCatalogScript.new()
	var insufficient_fan: Array[Vector2] = catalog.spawn_offsets({"layout_id": "rectangle_arena", "room_id": "first_hunt_clear"}, 4)
	_expect(insufficient_fan.is_empty(), "catalog: a fan profile accepted more actors than its authored sockets")
	var insufficient_band: Array[Vector2] = catalog.spawn_offsets({"layout_id": "corridor", "room_id": "first_hunt_followup"}, 4)
	_expect(insufficient_band.is_empty(), "catalog: an approach profile accepted more actors than its authored sockets")
	var invalid_profiles: Dictionary = catalog.catalog()
	(invalid_profiles.rooms[0] as Dictionary).spawn_profiles.erase("default")
	var profile_errors: Array[String] = catalog.validate_catalog(invalid_profiles)
	_expect(_has_fragment(profile_errors, "spawn_profiles: missing default profile"), "catalog: a room without a default spawn profile was accepted")


func _test_explicit_fixture_profile() -> void:
	var catalog = RoomCatalogScript.new()
	var offsets := catalog.spawn_offsets({"layout_id": "rectangle_arena", "room_id": "test.fixture"}, 7)
	_expect(offsets == [
		Vector2(-70.0, -150.0), Vector2(115.0, -125.0), Vector2(210.0, 25.0),
		Vector2(125.0, 150.0), Vector2(-65.0, 165.0), Vector2(-210.0, -45.0),
		Vector2(250.0, -40.0),
	], "catalog: explicit test fixture profile did not preserve authored offsets")


func _test_runtime_has_no_layout_manifest_branch() -> void:
	var source := FileAccess.get_file_as_string("res://src/game/combat_room_runtime.gd")
	_expect(not source.contains("_manifest_path_for_layout"), "runtime: hard-coded manifest resolver still exists")
	_expect(not source.contains("match layout_id"), "runtime: layout match branch still exists")
	var main_source := FileAccess.get_file_as_string("res://src/game/main.gd")
	_expect(main_source.contains("room_catalog.spawn_offsets"), "main: spawn placement is not delegated to RoomCatalog")
	_expect(not main_source.contains("match id"), "main: layout-specific spawn branch still exists")
	_expect(not main_source.contains("first_hunt_clear"), "main: room-specific spawn profile leaked back into runtime code")


func _has_fragment(values: Array[String], fragment: String) -> bool:
	for value: String in values:
		if value.contains(fragment):
			return true
	return false


func _expect_offsets(actual: Array[Vector2], expected: Array[Vector2], label: String) -> void:
	_expect(actual.size() == expected.size(), "catalog: %s returned %d offsets, expected %d" % [label, actual.size(), expected.size()])
	if actual.size() != expected.size():
		return
	for index in expected.size():
		_expect(actual[index].distance_to(expected[index]) <= 0.0001, "catalog: %s offset %d was %s, expected %s" % [label, index, actual[index], expected[index]])


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
