extends SceneTree
## Per-room combat place presentation: entry/exit alignment with authored
## sockets and blockers, sealed/wards-down exit state, original floor per room,
## fail-closed input validation and unchanged source geometry.

const SceneScript := preload("res://src/presentation/combat_room_scene.gd")
const RoomCatalogScript := preload("res://src/runtime/world/room_catalog.gd")
const FOCUS := Vector2(512.0, 360.0)
const SCALE := 0.72
const FIXTURE_DIR := "user://combat_room_scene_fixture"
const GAMEPLAY_DIGESTS := {
	"rectangle_arena": "44b78a7bb719e71eb03a9cb0a9b3383aff142e7e99d674c48e18388bf4b745b1",
	"corridor": "2d7430508dc51728a02e64d8461578a06c969f555e3202049a44160d876adcc6",
	"ring": "b08f815b682aeed5465c1cb3499cc579a18817698136c84bd6bd21d4ba8e99c5",
}

var failures: Array[String] = []


func _initialize() -> void:
	_test_source_geometry_unchanged()
	_test_alignment_on_legacy_seam()
	_test_exit_state_is_sealed_and_non_walkable()
	_test_court_entry_and_curb_gaps()
	_test_honest_hints()
	_test_original_floor_per_room()
	_test_inputs_fail_closed()
	_test_production_pack_state()
	for failure: String in failures:
		printerr("- %s" % failure)
	print("PASS test_combat_room_scenes.gd" if failures.is_empty() else "FAIL test_combat_room_scenes.gd")
	quit(0 if failures.is_empty() else 1)


func _test_source_geometry_unchanged() -> void:
	var catalog = RoomCatalogScript.new()
	for entry: Dictionary in catalog.catalog().get("rooms", []):
		var layout_id := String(entry.layout_id)
		_expect(String(entry.gameplay_digest) == String(GAMEPLAY_DIGESTS.get(layout_id, "")), "%s: gameplay digest moved; room presentation must not edit geometry" % layout_id)
	for layout_id: String in GAMEPLAY_DIGESTS:
		var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/rooms/combat/%s.spatial.json" % layout_id))
		var sockets: Array = manifest.get("spawn_interaction_exit_sockets", [])
		_expect(sockets.size() == 2, "%s: no exit socket may be added" % layout_id)
		for socket: Dictionary in sockets:
			_expect(String(socket.kind) == "spawn", "%s: sockets stay spawn-only" % layout_id)


func _legacy_scene() -> RefCounted:
	var scene = SceneScript.new()
	_expect(scene.load_assets(false, FOCUS, SCALE), "legacy seam load failed: %s" % scene.pending_reason)
	return scene


func _test_alignment_on_legacy_seam() -> void:
	var scene = _legacy_scene()
	_expect(scene.is_ready() and not scene.has_grounds(), "legacy seam must load rooms without claiming floor plates")
	_expect(scene.ground_texture("rectangle_arena") == null, "legacy seam must not invent a floor")
	var court: Dictionary = scene.room_report("rectangle_arena")
	_expect((court.entry_point as Vector2).is_equal_approx(Vector2(420.0, 678.0)) and court.entry_normal == Vector2.DOWN, "court entry must sit on the south edge behind combat/spawn: %s" % court.entry_point)
	_expect(String(court.exit_binding) == "combat/structure/ruin.gate#0" and (court.exit_point as Vector2).is_equal_approx(Vector2(760.0, 235.9375)), "court exit must sit on the authored gate sill: %s" % court.exit_point)
	var causeway: Dictionary = scene.room_report("corridor")
	_expect((causeway.entry_point as Vector2).is_equal_approx(Vector2(420.0, 506.0)), "causeway entry must sit on the south lip next to combat/spawn: %s" % causeway.entry_point)
	_expect(String(causeway.exit_kind) == "boundary" and (causeway.exit_point as Vector2).is_equal_approx(Vector2(1238.0, 434.0)), "causeway exit must be the authoritative east band end: %s" % causeway.exit_point)
	var ring: Dictionary = scene.room_report("ring")
	var center := Vector2(640.0, 434.0)
	var entry: Vector2 = ring.entry_point
	_expect(absf(entry.distance_to(center) - 209.84) < 0.01, "ring entry must lie on the outer edge")
	_expect(absf((entry - center).angle_to((ring.spawn_socket as Vector2) - center)) < 0.001, "ring entry must face the spawn socket")
	_expect(String(ring.exit_binding) == "combat/structure/ruin.gate#0" and (ring.exit_point as Vector2).distance_to(center) > 209.84, "ring exit gate must stand outside the walkable ring")
	var families := ["fern", "mushrooms", "votives", "relic"]
	var lists := {}
	for layout_id: String in GAMEPLAY_DIGESTS:
		var report: Dictionary = scene.room_report(layout_id)
		var rows: Array = report.dressing
		_expect(rows.size() > 0 and rows.size() <= 12, "%s dress list size" % layout_id)
		for row: Dictionary in rows:
			_expect(families.has(row.family), "%s dress family %s" % [layout_id, row.family])
		_expect(not lists.has(str(rows)), "%s dress list repeats another room" % layout_id)
		lists[str(rows)] = true
		_expect(int(report.collision_bodies) == 0 and bool(report.presentation_only), "%s must stay presentation only" % layout_id)


func _test_exit_state_is_sealed_and_non_walkable() -> void:
	var scene = _legacy_scene()
	_expect(SceneScript.exit_state(false) == "sealed" and SceneScript.exit_state(true) == "wards_down", "exit ward states")
	for layout_id: String in GAMEPLAY_DIGESTS:
		var contested: Dictionary = scene.room_report(layout_id, false)
		var cleared: Dictionary = scene.room_report(layout_id, true)
		_expect(String(contested.exit_state) == "sealed" and String(cleared.exit_state) == "wards_down", "%s ward state follows room_cleared" % layout_id)
		_expect(not bool(cleared.exit_walkable) and String(cleared.advance_authority) == "room_settlement", "%s cleared exit must stay sealed; settlement advances the room" % layout_id)


func _test_court_entry_and_curb_gaps() -> void:
	var court: Dictionary = _legacy_scene().room_report("rectangle_arena")
	var entry: Vector2 = court.entry_world
	var field: Rect2 = court.field_world
	for slab: Rect2 in SceneScript.entry_slab_extents(entry, court.entry_normal):
		_expect(slab.end.y <= field.end.y + 3.5, "court entry slabs must straddle the south edge inward: %s" % slab)
	var runner: Dictionary = court.runner_world
	var spawn_world: Vector2 = court.spawn_world
	_expect(float(runner.length) > 0.0 and (runner.inner as Vector2).y <= spawn_world.y + 84.0 - 8.0, "court approach runner inner end must sit inside the spawn framing: %s" % runner.inner)
	_expect((runner.inner as Vector2).distance_to(spawn_world) >= 24.0 - 0.01, "approach runner must stop short of the spawn")
	_expect(absf(((runner.inner as Vector2) - entry).cross(spawn_world - entry)) < 0.01, "approach runner must follow the checked spawn-entry segment")
	for layout_id: String in ["corridor", "ring"]:
		_expect(float((_legacy_scene().room_report(layout_id).runner_world as Dictionary).length) < 1.0, "%s runner stays negligible next to its edge" % layout_id)
	var exit_world: Vector2 = court.exit_world
	var half := float(court.exit_span_world) * 0.5
	var gaps := [{"point": exit_world, "half": half}]
	var north := field.position
	_expect(SceneScript.curb_block_skipped(Vector2(exit_world.x, north.y - 3.5), north, Vector2.RIGHT, entry, gaps), "north curb must open at the gate sill")
	_expect(SceneScript.curb_block_skipped(Vector2(exit_world.x + half, north.y - 3.5), north, Vector2.RIGHT, entry, gaps), "north curb gap must cover the full gate span")
	_expect(not SceneScript.curb_block_skipped(Vector2(exit_world.x + half + 20.0, north.y - 3.5), north, Vector2.RIGHT, entry, gaps), "north curb must resume beyond the gate span")
	var south := Vector2(field.position.x, field.end.y)
	_expect(not SceneScript.curb_block_skipped(Vector2(exit_world.x, south.y + 3.5), south, Vector2.RIGHT, entry, gaps), "far edges keep their curb under the exit x")
	_expect(SceneScript.curb_block_skipped(entry + Vector2(0.0, 3.5), south, Vector2.RIGHT, entry, gaps), "south curb must open at the entry")


func _test_honest_hints() -> void:
	var catalog = RoomCatalogScript.new()
	var campaign: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/early_campaign.json"))
	for layout: Dictionary in campaign.layouts:
		var presentation: Dictionary = catalog.presentation(String(layout.id))
		for field: String in ["entry_hint", "exit_hint"]:
			_expect(String(presentation.get(field, "")) == String(layout.get(field, "")), "%s %s differs between catalog and campaign" % [layout.id, field])
		var exit_hint := String(layout.exit_hint)
		_expect(exit_hint.contains("Leave") and exit_hint.contains("seal") and not exit_hint.contains("pass through"), "%s exit hint must not claim a walk-through exit" % layout.id)


func _write_png(path: String, color: Color, size: Vector2i) -> String:
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(color)
	image.save_png(path)
	return FileAccess.get_sha256(path)


func _write_json(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()


func _fixture_pack(colors: Array) -> String:
	DirAccess.make_dir_recursive_absolute(FIXTURE_DIR)
	var assets := {}
	var ids := ["court_ground", "causeway_ground", "ritual_ground"]
	for index: int in ids.size():
		var path := "%s/%s.png" % [FIXTURE_DIR, ids[index]]
		var sha := _write_png(path, colors[index], Vector2i(1024, 640))
		assets[ids[index]] = {"status": "packed", "path": path, "canvas": [1024, 640], "anchor": [0, 0], "sha256": sha}
	var pack_path := FIXTURE_DIR + "/assets.json"
	_write_json(pack_path, {"schema_version": 1, "assets": assets})
	return pack_path


func _test_original_floor_per_room() -> void:
	var scene = SceneScript.new()
	scene.pack_path = _fixture_pack([Color(0.2, 0.2, 0.2), Color(0.3, 0.25, 0.2), Color(0.15, 0.12, 0.2)])
	_expect(scene.load_assets(true, FOCUS, SCALE), "fixture floor pack load failed: %s" % scene.pending_reason)
	var paths := {}
	var hashes := {}
	for layout_id: String in GAMEPLAY_DIGESTS:
		var report: Dictionary = scene.room_report(layout_id)
		var texture: Texture2D = scene.ground_texture(layout_id)
		_expect(texture != null and texture.get_size() == Vector2(1024, 640), "%s floor plate must load at 1024x640" % layout_id)
		paths[report.ground_path] = true
		hashes[report.ground_sha256] = true
	_expect(paths.size() == 3 and hashes.size() == 3, "each room needs its own original floor plate")
	var duplicate = SceneScript.new()
	duplicate.pack_path = _fixture_pack([Color(0.2, 0.2, 0.2), Color(0.2, 0.2, 0.2), Color(0.15, 0.12, 0.2)])
	_expect(not duplicate.load_assets(true, FOCUS, SCALE) and not duplicate.is_ready(), "a repeated floor plate must fail closed")
	var pending = SceneScript.new()
	pending.pack_path = _fixture_pack([Color(0.2, 0.2, 0.2), Color(0.3, 0.25, 0.2), Color(0.15, 0.12, 0.2)])
	var pack: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(pending.pack_path))
	pack["assets"]["ritual_ground"]["status"] = "pending"
	_write_json(pending.pack_path, pack)
	_expect(not pending.load_assets(true, FOCUS, SCALE) and String(pending.pending_reason).contains("not packed"), "a pending floor entry with a stale hash must fail closed")


func _expect_rejected(scenes: Dictionary, fragment: String, label: String) -> void:
	var path := FIXTURE_DIR + "/scenes_%s.json" % label
	DirAccess.make_dir_recursive_absolute(FIXTURE_DIR)
	_write_json(path, scenes)
	var scene = SceneScript.new()
	scene.scenes_path = path
	var loaded: bool = scene.load_assets(false, FOCUS, SCALE)
	_expect(not loaded and not scene.is_ready() and not scene.has_room("rectangle_arena"), "%s: invalid scene list was accepted" % label)
	_expect(String(scene.pending_reason).begins_with("ASSETS PENDING") and String(scene.pending_reason).contains(fragment), "%s: unexpected reason %s" % [label, scene.pending_reason])


func _test_inputs_fail_closed() -> void:
	var missing = SceneScript.new()
	missing.pack_path = FIXTURE_DIR + "/absent.json"
	_expect(not missing.load_assets(true, FOCUS, SCALE) and String(missing.pending_reason).contains("absent.json"), "missing floor pack must fail closed")
	var base: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SceneScript.SCENES_PATH))
	var reused: Dictionary = base.duplicate(true)
	reused["rooms"]["corridor"]["ground_id"] = "court_ground"
	_expect_rejected(reused, "reused", "reused_ground")
	var fake_exit: Dictionary = base.duplicate(true)
	fake_exit["rooms"]["rectangle_arena"]["exit"] = {"binding_ref": "combat/structure/ruin.low_pier#0", "style": "gate_ward"}
	_expect_rejected(fake_exit, "gate", "non_gate_exit")
	var ring_boundary: Dictionary = base.duplicate(true)
	ring_boundary["rooms"]["ring"]["exit"] = {"boundary_anchor": "east", "style": "boundary_ward"}
	_expect_rejected(ring_boundary, "boundary exit", "ring_boundary_exit")
	var other_socket: Dictionary = base.duplicate(true)
	other_socket["rooms"]["corridor"]["entry"]["socket_ref"] = "combat/encounter-origin"
	_expect_rejected(other_socket, "combat/spawn", "wrong_socket")
	var blocked_route: Dictionary = base.duplicate(true)
	var blocked_rows: Array = blocked_route["rooms"]["rectangle_arena"]["dressing"]
	blocked_rows[0] = {"id": "court/fern/0", "family": "fern", "feet": [353, 548]}
	_expect_rejected(blocked_route, "route", "dressing_on_route")
	var too_many: Dictionary = base.duplicate(true)
	var ring_rows: Array = too_many["rooms"]["ring"]["dressing"]
	for index: int in 13 - ring_rows.size():
		ring_rows.append({"id": "ritual/extra/%d" % index, "family": "fern", "feet": [60, 600 - index * 10]})
	_expect_rejected(too_many, "dress list", "too_many_dressing")
	var wrong_style: Dictionary = base.duplicate(true)
	wrong_style["rooms"]["ring"]["edge_style"] = "court"
	_expect_rejected(wrong_style, "edge style", "wrong_edge_style")


func _test_production_pack_state() -> void:
	var scene = SceneScript.new()
	var loaded: bool = scene.load_assets(true, FOCUS, SCALE)
	if FileAccess.file_exists(SceneScript.PACK_PATH):
		_expect(loaded and scene.has_grounds(), "production floor pack must validate: %s" % scene.pending_reason)
	else:
		_expect(not loaded and String(scene.pending_reason).contains("world_expansion_v01"), "absent production floor pack must fail closed")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
