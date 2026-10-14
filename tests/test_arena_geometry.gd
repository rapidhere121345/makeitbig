extends SceneTree

const ArenaGeometryScript := preload("res://src/runtime/geometry/arena_geometry.gd")
const RoomAssetRootScript := preload("res://src/runtime/world/room_asset_root.gd")
const SceneRuntimeScript := preload("res://src/runtime/world/scene_runtime.gd")
var failures: Array[String] = []

func _initialize() -> void:
	_test_rect_and_corridor()
	_test_ring_keeps_hole()
	_test_unknown_and_invalid_rejected()
	_test_stable_snapshot()
	_test_native_scene_contract()
	if failures.is_empty():
		print("PASS  test_arena_geometry.gd")
		quit(0)
		return
	for failure in failures: printerr("- " + failure)
	quit(1)

func _test_rect_and_corridor() -> void:
	var rect := ArenaGeometryScript.new({"boundary": {"type": "rect", "rect": Rect2(0, 0, 100, 50)}})
	_expect(rect.is_position_clear(Vector2(50, 25)), "rect: interior rejected")
	_expect(not rect.is_position_clear(Vector2(-1, 25)), "rect: exterior accepted")
	var corridor := ArenaGeometryScript.new({"boundary": {"type": "corridor", "rect": Rect2(0, 20, 100, 10), "axis": "horizontal"}})
	_expect(corridor.boundary_contains(Vector2(50, 25)) and not corridor.boundary_contains(Vector2(50, 10)), "corridor: strip rule changed")

func _test_ring_keeps_hole() -> void:
	var ring := ArenaGeometryScript.new({"boundary": {"type": "ring", "center": Vector2.ZERO, "inner_radius": 10.0, "outer_radius": 30.0}})
	_expect(not ring.boundary_contains(Vector2.ZERO), "ring: hole collapsed")
	_expect(ring.boundary_contains(Vector2(20, 0)), "ring: annulus rejected")
	_expect(not ring.boundary_contains(Vector2(31, 0)), "ring: exterior accepted")

func _test_unknown_and_invalid_rejected() -> void:
	var unknown := ArenaGeometryScript.build({"boundary": {"type": "triangle"}})
	var bad := ArenaGeometryScript.build({"boundary": {"type": "rect", "rect": Rect2(0, 0, 1, 1)}, "blockers": [{"id": "x", "kind": "circle"}]})
	_expect(not unknown.ok and unknown.value.is_empty(), "unknown: configuration accepted")
	_expect(not bad.ok and bad.value.is_empty(), "invalid blocker: configuration accepted")

func _test_stable_snapshot() -> void:
	var geometry := ArenaGeometryScript.new({"boundary": {"type": "rect", "rect": Rect2(0, 0, 100, 100)}, "blockers": [{"id": "z", "points": [Vector2(70, 0), Vector2(80, 0), Vector2(80, 10)]}, {"id": "a", "points": [Vector2(0, 0), Vector2(10, 0), Vector2(0, 10)]}]})
	var snapshot := geometry.blocker_snapshot()
	_expect(snapshot.size() == 2 and snapshot[0]["id"] == "a" and snapshot[1]["id"] == "z", "snapshot: blocker order is unstable")
	_expect(not geometry.is_position_clear(Vector2(2, 2)), "convex blocker: overlap accepted")


func _test_native_scene_contract() -> void:
	var fixture := _native_fixture()
	var runtime := SceneRuntimeScript.new()
	root.add_child(runtime)
	var variants: Array[Dictionary] = []
	for field: String in ["geometry", "channels", "traversal", "portals", "sockets", "metadata", "coordinates"]:
		var changed: Dictionary = fixture["manifest"].duplicate(true)
		match field:
			"geometry": changed["stable_bindings"][0]["geometry"]["inner_radius"] += 1.0
			"channels": changed["stable_bindings"][0]["channels"]["occlusion"] = true
			"traversal": changed["traversal_profiles"][0]["radius"] = 1.0
			"portals": changed["regions_and_portals"][0]["portals"] = [{"portal_id": "stale"}]
			"sockets": changed["spawn_interaction_exit_sockets"][0]["position"][0] += 1.0
			"metadata": changed["gameplay_spatial_metadata"]["stale"] = true
			"coordinates": changed["coordinate_convention"]["scale"] = 2.0
		variants.append(changed)
	for changed: Dictionary in variants:
		var rejected := runtime.mount(fixture["definition"], fixture["asset"], fixture["scene"], changed)
		_expect(rejected.get("error", "") == "native_manifest_mismatch" and not runtime.is_ready(), "native source: a changed derived manifest was mounted: %s" % str(rejected))
	var wrong_identity: Dictionary = fixture["definition"].duplicate(true)
	wrong_identity["world_asset_id"] = "combat/corridor"
	var identity := runtime.mount(wrong_identity, fixture["asset"], fixture["scene"], fixture["manifest"])
	_expect(identity.get("error", "") == "room_identity_mismatch", "native source: room identity did not bind to the author scene")
	var raw_invalid: Dictionary = fixture["manifest"].duplicate(true)
	raw_invalid["unknown"] = true
	var unknown := runtime.mount(fixture["definition"], fixture["asset"], fixture["scene"], raw_invalid)
	_expect(unknown.get("error", "") == "invalid_spatial_manifest", "native source: unknown manifest fields were silently discarded")
	var unsafe_fixture := _native_fixture(true)
	var unsafe := runtime.mount(unsafe_fixture["definition"], unsafe_fixture["asset"], unsafe_fixture["scene"], fixture["manifest"])
	_expect(unsafe.get("error", "") == "native_scene_contract_invalid", "native source: a player socket in the ring hole was accepted")
	var setup_observed: Array[bool] = []
	var mounted := runtime.mount(fixture["definition"], fixture["asset"], fixture["scene"], fixture["manifest"], 2, 30,
		func(instance: Node) -> void: setup_observed.append(instance.has_node("RoomAsset/SortRoot/Building")))
	_expect(bool(mounted.get("ok", false)) and runtime.is_ready(), "native source: valid authored room failed to mount: %s" % str(mounted))
	if runtime.is_ready():
		_expect(setup_observed == [true], "native mount: setup could not inspect source before shared-layer binding")
		_expect(runtime.authored_arena_rect == Rect2(0, 0, 200, 200), "native source: authored bounds were not published")
		_expect(runtime.spawn_socket_bindings == [{"binding": "combat/encounter-origin", "position": Vector2(100, 100)}, {"binding": "combat/spawn", "position": Vector2(170, 100)}], "native source: spawn socket schema/coordinates changed")
		var registered := runtime.register_actor("ranger", Vector2(170, 100), 14.0)
		var moved := runtime.move_actor("ranger", Vector2(-140, 0), 1)
		_expect(bool(registered.get("ok", false)) and bool(moved.get("ok", false)) and bool(moved.get("blocked", false)) and Vector2(moved.get("position", Vector2.ZERO)).distance_to(Vector2(100, 100)) >= 53.999, "native ring: runtime actor crossed the authored hole")
		var shared_sort := runtime.presenter.native_group("SortRoot")
		var building := shared_sort.get_node_or_null("Building")
		var actor_view := Node2D.new()
		actor_view.name = "DynamicRanger"
		runtime.presenter.register_actor_view("ranger", actor_view)
		_expect(building != null and building.get_parent() == actor_view.get_parent(), "native sort: building and actor have parallel sorting roots")
		var surface := runtime.presenter.native_binding_node("ground.surface")
		_expect(surface != null and surface.get_parent() == runtime.presenter.native_group("Ground"), "native binding: source reference was lost while moving visual content")
		runtime.unmount()
		_expect(shared_sort.get_child_count() == 0 and runtime.presenter.actor_ids().is_empty() and runtime.presenter.native_binding_node("ground.surface") == null and runtime.movement_boundary.is_empty(), "native unmount: old visuals, actors or geometry survived")
		var remounted := runtime.mount(fixture["definition"], fixture["asset"], fixture["scene"], fixture["manifest"], 3, 30)
		_expect(bool(remounted.get("ok", false)) and runtime.room_instance_id == "native.test/2" and not runtime.accepts_version("native.test/1", 2), "native remount: instance identity or stale-version rejection failed")
		runtime.unmount()
	root.remove_child(runtime)
	runtime.free()


func _native_fixture(socket_in_hole: bool = false) -> Dictionary:
	var scene_root := Node2D.new()
	scene_root.name = "NativeRoom"
	var author := RoomAssetRootScript.new()
	author.name = "RoomAsset"
	author.scene_id = "combat.ring"
	author.layout_id = "ring"
	author.gameplay_source = "ring.spatial.json"
	author.presentation_source = "arena_world_view"
	author.arena_rect = Rect2(0, 0, 200, 200)
	author.traversal_radius = 14.0
	scene_root.add_child(author)
	for group_name: String in RoomAssetRootScript.REQUIRED_GROUPS:
		var group := Node2D.new()
		group.name = group_name
		group.y_sort_enabled = group_name == "SortRoot"
		author.add_child(group)
	var surface := Node2D.new()
	surface.name = "Surface"
	surface.set_meta("binding_id", "ground.surface")
	author.get_node("Ground").add_child(surface)
	var geometry := Node2D.new()
	geometry.name = "MovementBoundary"
	geometry.set_meta("binding_id", "combat/movement-boundary")
	geometry.set_meta("source", "arena.geometry.v1")
	geometry.set_meta("channels", RoomAssetRootScript.MOVEMENT_CHANNELS.duplicate(true))
	geometry.set_meta("geometry", {"type": "ring", "center": Vector2(100, 100), "inner_radius": 40.0, "outer_radius": 86.0})
	author.get_node("GeometrySources").add_child(geometry)
	for socket_name: String in ["CombatSpawn", "EncounterOrigin"]:
		var socket := Marker2D.new()
		socket.name = socket_name
		socket.position = Vector2(170, 100) if socket_name == "CombatSpawn" and not socket_in_hole else Vector2(100, 100)
		socket.set_meta("binding_id", "combat/spawn" if socket_name == "CombatSpawn" else "combat/encounter-origin")
		socket.set_meta("kind", "spawn")
		author.get_node("Sockets").add_child(socket)
	var building := Node2D.new()
	building.name = "Building"
	author.get_node("SortRoot").add_child(building)
	_assign_owner(scene_root, scene_root)
	var packed := PackedScene.new()
	packed.pack(scene_root)
	var data := author.derive_spatial_manifest()
	scene_root.free()
	return {
		"scene": packed,
		"manifest": data,
		"definition": {"room_id": "native.test", "world_asset_id": "combat/ring", "encounter_id": "encounter/test", "ruleset_id": "combat.rules.v1", "tags": ["combat"]},
		"asset": {"world_scene_path": "res://content/rooms/combat/ring.tscn", "manifest_path": "res://content/rooms/combat/ring.spatial.json", "gameplay_digest": "test", "presentation_digest": "test", "schema_version": 1},
	}


func _assign_owner(node: Node, scene_root: Node) -> void:
	if node != scene_root:
		node.owner = scene_root
	for child: Node in node.get_children():
		_assign_owner(child, scene_root)

func _expect(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
