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

## Ground footprints are authored in canvas-local pixels. Tall projected art
## and its reveal rectangle are deliberately not movement geometry.
const FOOTPRINT_PATH := "res://docs/art-production/generated-world-v02/ground_footprints.json"
const ASSET_PATH := "res://art/production/p1/generated_world_v02/assets.json"
var _band_rects: Dictionary = {}
var _tower_octagon: Array = [] # Historical variable name; current ground shape is a rectangle.

var failures: Array[String] = []


static func _snap16(v: Vector2) -> Vector2:
	return Vector2(roundf(v.x * 16.0) / 16.0, roundf(v.y * 16.0) / 16.0)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_load_ground_contract()
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


func _load_ground_contract() -> void:
	var recipe: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FOOTPRINT_PATH))
	var pack: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ASSET_PATH))
	for family: String in recipe.arena:
		var r: Array = recipe.arena[family].rect
		var anchor := _point(pack.assets[family].anchor)
		var pad := float(recipe.padding_native_px)
		var ground := Rect2(Vector2(float(r[0]), float(r[1])), Vector2(float(r[2]), float(r[3]))).grow(pad)
		var corners: Array = []
		for point: Vector2 in [ground.position, Vector2(ground.end.x, ground.position.y), ground.end, Vector2(ground.position.x, ground.end.y)]:
			corners.append((point-anchor)/0.72)
		_expect(ground.size.y < float(pack.assets[family].occupied_rect[3]), family + ": ground footprint accidentally became full-height artwork")
		if family == "tower":
			_tower_octagon = corners
		else:
			_band_rects[family.replace("ruin_", "ruin.")] = corners
	_expect(_band_rects.size() == 4 and _tower_octagon.size() == 4, "all five combat families need ground footprints")


## Every combat scene authors one blocker per layout structure plus the tower,
## in layout order, at the exact authored feet. Feet come from the production
## art layout JSON the presenter draws, then the shared per-room
## `room_structure_overrides` map (keyed "id#occurrence" in layout order)
## relocates pieces whose blocker and artwork move together. Each blocker also
## pins its collision shape: the reviewed ground rectangles for ruins and the tower. This keeps gameplay collision and visible
## art on the same data.
func _test_authoring_matches_layout() -> void:
	var layout: Variant = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_PATH))
	if not layout is Dictionary:
		_expect(false, "layout: combat layout JSON missing")
		return
	var catalog: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
	var layout_ids: Dictionary = {}
	if catalog is Dictionary:
		for entry: Variant in (catalog as Dictionary).get("rooms", []):
			var data: Dictionary = entry
			layout_ids[String(data.get("world_scene_path", ""))] = String(data.get("layout_id", ""))
	var overrides: Dictionary = (layout as Dictionary).get("room_structure_overrides", {})
	var expected: Array = []
	var occurrences: Dictionary = {}
	for entry: Variant in (layout as Dictionary).get("structures", []):
		var sprite_id := String((entry as Dictionary)["id"])
		var occurrence := int(occurrences.get(sprite_id, 0))
		occurrences[sprite_id] = occurrence + 1
		expected.append({"id": sprite_id, "key": "%s#%d" % [sprite_id, occurrence], "feet": _point((entry as Dictionary)["feet"])})
	var tower_feet := _point((layout as Dictionary).get("tower_feet", []))
	expected.append({"id": "tower", "key": "tower", "feet": tower_feet})
	for room: String in ROOMS:
		var scene_path := "res://content/rooms/combat/%s.tscn" % room
		var layout_id := String(layout_ids.get(scene_path, room))
		var room_overrides: Dictionary = overrides.get(layout_id, {}) if overrides is Dictionary else {}
		var packed := load(scene_path) as PackedScene
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
			if room_overrides.has(String(expected[index]["key"])):
				feet = _point(room_overrides[String(expected[index]["key"])])
			var node := blocker as Node2D
			_expect(binding_id == "combat/structure/tower" if sprite_id == "tower" else binding_id == "combat/structure/%s" % String(expected[index]["key"]), "%s: blocker %d id %s does not match layout sprite %s" % [room, index, binding_id, sprite_id])
			if node != null:
				_expect(node.position.is_equal_approx(feet), "%s: blocker %d (%s) feet %s moved from layout %s" % [room, index, sprite_id, str(node.position), str(feet)])
				_expect(not node.visible, "%s: blocker %d (%s) renders as a visible debug shape" % [room, index, sprite_id])
				var polygon: Variant = blocker.get("polygon")
				if polygon is PackedVector2Array:
					var rels: Array = _tower_octagon if sprite_id == "tower" else _band_rects.get(sprite_id, [])
					if (polygon as PackedVector2Array).size() != rels.size():
						_expect(false, "%s: blocker %d (%s) collision polygon has %d points, expected %d" % [room, index, sprite_id, (polygon as PackedVector2Array).size(), rels.size()])
					else:
						for corner: int in rels.size():
							var target: Vector2 = _snap16(node.position + rels[corner])
							var actual: Vector2 = node.position + polygon[corner]
							if (actual - target).length() > 0.001:
								_expect(false, "%s: blocker %d (%s) corner %d at %s, expected snapped %s" % [room, index, sprite_id, corner, str(actual), str(target)])
								break
				else:
					_expect(false, "%s: blocker %d (%s) lost its collision polygon" % [room, index, sprite_id])
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
	# Traverse below the tower's projected roof but north of its physical base.
	# The previous full-image blocker covered this entire horizontal leg.
	var behind_start := Vector2(80, 340)
	var behind_end := Vector2(270, 340)
	_expect(index.is_position_clear(Channels.MOVEMENT, Vector2(175, 340), 14.0), "2.5D: tower roof still blocks the ground behind it")
	_expect(index.sweep(Channels.MOVEMENT, behind_start, behind_end-behind_start, 14.0).is_empty(), "2.5D: continuous tower-back crossing is blocked")
	_expect(not index.is_position_clear(Channels.MOVEMENT, Vector2(175, 390), 14.0), "2.5D: tower foundation became walkable")
	_expect(not index.sweep(Channels.MOVEMENT, Vector2(175, 340), Vector2(0, 70), 14.0).is_empty(), "2.5D: rear approach penetrates tower foundation")
	var wall_center := Vector2(271.0, 224.0)
	var pier_center := Vector2(354.0, 237.0)
	_expect(not index.is_position_clear(Channels.MOVEMENT, wall_center, 6.0), "mount: wall_corner center is walkable")
	_expect(not index.is_position_clear(Channels.MOVEMENT, pier_center, 6.0), "mount: low_pier center is walkable")
	_expect(index.is_position_clear(Channels.MOVEMENT, wall_center + Vector2(0.0, 120.0), 14.0), "mount: open approach to the wall is blocked")
	var arrow: Array = index.sweep(Channels.PROJECTILE, wall_center + Vector2(0.0, -100.0), Vector2(0.0, 200.0), 0.0)
	_expect(not arrow.is_empty(), "mount: projectile sweep passed through the wall_corner blocker")
	# pier_center's column threads a former sub-pixel gap beside wall_corner0;
	# at 5px footing padding the continuous ruin footprints abut, so a projectile
	# would legitimately hit the wall there. Sweep over the neighbor-free pier.
	var free_pier_center := Vector2(601.0, 552.0)
	var over_pier: Array = index.sweep(Channels.PROJECTILE, free_pier_center + Vector2(0.0, -80.0), Vector2(0.0, 160.0), 0.0)
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
