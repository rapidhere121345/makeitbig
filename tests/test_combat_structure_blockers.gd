extends SceneTree

## Regression for authored combat static blockers (ruins, gates, tower).
##
## Run: godot --headless --path . --script res://tests/test_combat_structure_blockers.gd
## Covers: the native scene contract accepts the authored blocker set, the
## authored blockers stay consistent with the production art layout JSON, the
## committed manifests and room catalog digests match a fresh offline bake,
## and a mounted production room turns the blockers into movement surfaces
## (walls, gates and the tower additionally into projectile surfaces).

const BakeCore := preload("res://tools/world_manifest/bake_core.gd")
const SpatialScript := preload("res://src/runtime/world/spatial_manifest.gd")
const SceneRuntimeScript := preload("res://src/runtime/world/scene_runtime.gd")
const Channels := preload("res://src/runtime/spatial/spatial_channels.gd")

const ROOMS: Array[String] = ["rectangle_arena", "corridor", "ring"]
const LAYOUT_PATH := "res://art/production/p1/combat_style_r13/v03/layout.json"
const CATALOG_PATH := "res://content/rooms/combat/room_catalog.json"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_authoring_matches_layout()
	_test_manifest_and_catalog_digests()
	_test_mounted_collision_channels()
	for failure: String in failures:
		printerr(failure)
	if failures.is_empty():
		print("PASS  test_combat_structure_blockers.gd")
		quit(0)
		return
	printerr("FAIL  test_combat_structure_blockers.gd")
	quit(1)


## Every combat scene authors one blocker per layout structure plus the tower,
## in layout order, at the exact authored feet. This pins the gameplay
## collision against the same production art layout the presenter draws.
func _test_authoring_matches_layout() -> void:
	var layout: Variant = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_PATH))
	if not layout is Dictionary:
		_expect(false, "layout: combat layout JSON missing")
		return
	var expected: Array = []
	for entry: Variant in (layout as Dictionary).get("structures", []):
		expected.append({"id": String((entry as Dictionary)["id"]), "feet": _point((entry as Dictionary)["feet"])})
	var tower_feet := _point((layout as Dictionary).get("tower_feet", []))
	expected.append({"id": "tower", "feet": tower_feet})
	for room: String in ROOMS:
		var packed := load("res://content/rooms/combat/%s.tscn" % room) as PackedScene
		if packed == null:
			_expect(false, "%s: scene failed to load" % room)
			continue
		var scene := packed.instantiate()
		var author: Variant = scene.get_node_or_null("RoomAsset")
		if author == null:
			_expect(false, "%s: missing RoomAsset root" % room)
			scene.free()
			continue
		var report: Dictionary = author.call("validate_contract")
		_expect(bool(report.get("ok", false)), "%s: native contract rejected authored blockers: %s" % [room, str(report.get("errors", []))])
		var static_container: Variant = (author as Node).get_node_or_null("GeometrySources/Static")
		if static_container == null:
			_expect(false, "%s: missing GeometrySources/Static" % room)
			scene.free()
			continue
		var children: Array = (static_container as Node).get_children()
		_expect(children.size() == expected.size(), "%s: expected %d authored blockers, found %d" % [room, expected.size(), children.size()])
		for index: int in mini(children.size(), expected.size()):
			var blocker: Node = children[index]
			var binding_id := String(blocker.get_meta("binding_id", ""))
			var sprite_id := String(expected[index]["id"])
			var feet: Vector2 = expected[index]["feet"]
			var node := blocker as Node2D
			_expect(binding_id == "combat/structure/tower" if sprite_id == "tower" else binding_id.begins_with("combat/structure/%s#" % sprite_id), "%s: blocker %d id %s does not match layout sprite %s" % [room, index, binding_id, sprite_id])
			if node != null:
				_expect(node.position.is_equal_approx(feet), "%s: blocker %d (%s) feet %s moved from layout %s" % [room, index, sprite_id, str(node.position), str(feet)])
		scene.free()


## The committed spatial manifests and the room catalog stay byte-equivalent
## to a fresh offline bake of the native scenes, and every blocker carries the
## authored channel split: movement always, projectile only for wall shapes.
func _test_manifest_and_catalog_digests() -> void:
	var catalog: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
	if not catalog is Dictionary:
		_expect(false, "catalog: room catalog JSON missing")
		return
	for entry: Variant in (catalog as Dictionary).get("rooms", []):
		var room := String((entry as Dictionary)["layout_id"])
		var manifest_path := String((entry as Dictionary)["manifest_path"])
		var scene_path := String((entry as Dictionary)["world_scene_path"])
		var result: Dictionary = BakeCore.bake_scene(scene_path, manifest_path)
		_expect(bool(result.get("ok", false)), "%s: fresh bake failed: %s" % [room, str(result.get("errors", []))])
		if not bool(result.get("ok", false)):
			continue
		var asset: Dictionary = result["world_asset"]
		_expect(String(asset["gameplay_digest"]) == String((entry as Dictionary)["gameplay_digest"]), "%s: catalog gameplay digest diverged from a fresh bake" % room)
		_expect(String(asset["presentation_digest"]) == String((entry as Dictionary)["presentation_digest"]), "%s: catalog presentation digest diverged from a fresh bake" % room)
		var committed: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
		if not committed is Dictionary:
			_expect(false, "%s: committed manifest missing" % room)
			continue
		var blockers: Array = []
		for binding: Variant in (committed as Dictionary).get("stable_bindings", []):
			if String((binding as Dictionary).get("kind", "")) == "static_blocker":
				blockers.append(binding)
		_expect(blockers.size() == 13, "%s: expected 13 static blockers in manifest, found %d" % [room, blockers.size()])
		for binding: Variant in blockers:
			var entry_channels: Dictionary = (binding as Dictionary).get("channels", {})
			var binding_id := String((binding as Dictionary)["binding_id"])
			_expect(bool(entry_channels.get("movement", false)), "%s: blocker %s lost its movement channel" % [room, binding_id])
			var blocks_projectile := bool(entry_channels.get("projectile", false))
			if binding_id.begins_with("combat/structure/ruin.low_pier#"):
				_expect(not blocks_projectile, "%s: low pier %s must stay passable for projectiles" % [room, binding_id])
			else:
				_expect(blocks_projectile, "%s: wall blocker %s must stop projectiles" % [room, binding_id])
			_expect(not bool(entry_channels.get("occlusion", false)), "%s: blocker %s must not claim the presentation occlusion channel" % [room, binding_id])


## A mounted production combat room turns the authored blockers into real
## spatial surfaces: movement blocks bodies on wall and pier shapes, the
## projectile channel carries exactly the wall shapes, and a swept projectile
## stops at the first blocker surface.
func _test_mounted_collision_channels() -> void:
	var packed := load("res://content/rooms/combat/rectangle_arena.tscn") as PackedScene
	var manifest_path := "res://content/rooms/combat/rectangle_arena.spatial.json"
	var manifest := SpatialScript.new(JSON.parse_string(FileAccess.get_file_as_string(manifest_path)))
	var runtime: SceneRuntime = SceneRuntimeScript.new()
	root.add_child(runtime)
	var mounted: Dictionary = runtime.mount(
		{
			"room_id": "combat.rectangle_arena",
			"world_asset_id": "combat/rectangle_arena",
			"encounter_id": "encounter.structure-regression",
			"ruleset_id": "rules.structure-regression",
			"tags": ["regression"],
		},
		{
			"world_scene_path": packed.resource_path,
			"manifest_path": manifest_path,
			"gameplay_digest": manifest.gameplay_digest_sha256(),
			"presentation_digest": manifest.presentation_digest_sha256(),
			"schema_version": 1,
		},
		packed,
		null,
		0,
		30
	)
	_expect(bool(mounted.get("ok", false)), "mount: production rectangle_arena failed to mount with blockers: %s" % str(mounted))
	if not bool(mounted.get("ok", false)):
		runtime.free()
		return
	var index: Variant = runtime.static_spatial_index
	if index == null:
		_expect(false, "mount: static spatial index unavailable")
		runtime.shutdown()
		runtime.free()
		return
	var movement_ids: Array = index.surface_ids(Channels.MOVEMENT)
	var projectile_ids: Array = index.surface_ids(Channels.PROJECTILE)
	_expect(movement_ids.has("combat/structure/ruin.wall_corner#0"), "mount: wall_corner#0 missing from movement surfaces")
	_expect(movement_ids.has("combat/structure/tower"), "mount: tower missing from movement surfaces")
	_expect(movement_ids.has("combat/structure/ruin.low_pier#0"), "mount: low_pier#0 missing from movement surfaces")
	_expect(projectile_ids.has("combat/structure/ruin.wall_corner#0"), "mount: wall_corner#0 missing from projectile surfaces")
	_expect(projectile_ids.has("combat/structure/tower"), "mount: tower missing from projectile surfaces")
	_expect(not projectile_ids.has("combat/structure/ruin.low_pier#0"), "mount: low_pier#0 must not stop projectiles")
	var wall_center := Vector2(271.0, 224.0)
	var pier_center := Vector2(354.0, 237.0)
	_expect(not index.is_position_clear(Channels.MOVEMENT, wall_center, 6.0), "mount: wall_corner center is walkable")
	_expect(not index.is_position_clear(Channels.MOVEMENT, pier_center, 6.0), "mount: low_pier center is walkable")
	_expect(index.is_position_clear(Channels.MOVEMENT, wall_center + Vector2(0.0, 120.0), 14.0), "mount: open approach to the wall is blocked")
	var arrow: Array = index.sweep(Channels.PROJECTILE, wall_center + Vector2(0.0, -100.0), Vector2(0.0, 200.0), 0.0)
	_expect(not arrow.is_empty(), "mount: projectile sweep passed through the wall_corner blocker")
	var over_pier: Array = index.sweep(Channels.PROJECTILE, pier_center + Vector2(0.0, -80.0), Vector2(0.0, 160.0), 0.0)
	_expect(over_pier.is_empty(), "mount: projectile sweep was clipped by the low pier")
	runtime.shutdown()
	runtime.free()


func _point(value: Variant) -> Vector2:
	if value is Array and (value as Array).size() == 2:
		return Vector2(float((value as Array)[0]), float((value as Array)[1]))
	return Vector2(INF, INF)


func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
