extends SceneTree

const EntityDefinitionScript = preload("res://src/runtime/world/entity_definition.gd")
const ActorStateScript = preload("res://src/runtime/world/actor_state.gd")
const ActorRegistryScript = preload("res://src/runtime/world/actor_registry.gd")
const RoomDefinitionScript = preload("res://src/runtime/world/room_definition.gd")
const WorldAssetScript = preload("res://src/runtime/world/world_asset.gd")
const SpatialManifestScript = preload("res://src/runtime/world/spatial_manifest.gd")
const SceneRuntimeScript = preload("res://src/runtime/world/scene_runtime.gd")
const SimulationWorldScript = preload("res://src/runtime/world/simulation_world.gd")
const WorldPresenterScript = preload("res://src/runtime/world/world_presenter.gd")

var failures: Array[String] = []


func _initialize() -> void:
	_test_entity_definition_is_static()
	_test_actor_state_is_versioned_instance_state()
	_test_actor_registry_is_the_movement_commit_boundary()
	_test_simulation_orders_commands_and_versions_events()
	_test_presenter_has_separate_layers_and_no_debug_by_default()
	_test_scene_runtime_lifecycle()
	if failures.is_empty():
		print("PASS test_runtime_world.gd")
		quit(0)
		return
	for failure: String in failures:
		printerr("- %s" % failure)
	quit(1)


func _test_entity_definition_is_static() -> void:
	var raw := {
		"schema_version": 1,
		"entity_id": "hero",
		"feet_anchor": Vector2(3.5, 7.0),
		"footprint": {"kind": "circle", "radius": 6.0},
		"sort_baseline": 7.0,
		"parts": [{"part_id": "body", "visual_id": "hero.body"}],
		"prefab_path": "res://test/hero.tscn",
	}
	var parsed: Dictionary = EntityDefinitionScript.from_dict(raw)
	_expect(bool(parsed.ok), "entity: valid definition rejected")
	var entity = parsed.value
	var snapshot: Dictionary = entity.snapshot()
	_expect(snapshot.entity_id == "hero" and snapshot.feet_anchor == Vector2(3.5, 7.0), "entity: snapshot lost static bindings")
	var invalid := raw.duplicate(true)
	invalid["runtime_position"] = Vector2.ZERO
	var invalid_result: Dictionary = EntityDefinitionScript.from_dict(invalid)
	_expect(not bool(invalid_result.ok), "entity: runtime state was accepted into definition")


func _test_actor_state_is_versioned_instance_state() -> void:
	var created: Dictionary = ActorStateScript.create("hero", Vector2(10.0, 12.0), 6.0, "room/0", 4)
	_expect(bool(created.ok), "actor state: valid instance rejected")
	var state = created.value
	var stale: Dictionary = state.apply_motor_result({
		"position": Vector2(11.0, 12.0),
		"room_instance_id": "room/old",
		"world_revision": 4,
	}, 1)
	_expect(not bool(stale.ok) and state.feet_position == Vector2(10.0, 12.0), "actor state: stale room result changed position")
	var applied: Dictionary = state.apply_motor_result({
		"position": Vector2(11.0, 12.0),
		"room_instance_id": "room/0",
		"world_revision": 4,
		"facing": Vector2.RIGHT,
	}, 1)
	_expect(bool(applied.ok) and state.feet_position == Vector2(11.0, 12.0), "actor state: current motor result was rejected")
	_expect(state.previous_feet_position == Vector2(10.0, 12.0) and state.last_motor_tick == 1, "actor state: previous position or tick missing")


func _test_actor_registry_is_the_movement_commit_boundary() -> void:
	var registry = ActorRegistryScript.new()
	var configured: Dictionary = registry.configure("room/registry", 7)
	_expect(bool(configured.ok), "registry: valid room configuration rejected")
	_expect(registry.register_rect("wall", Rect2(20.0, -20.0, 4.0, 40.0)), "registry: blocker registration failed")
	var registered: Dictionary = registry.register_actor("hero", Vector2.ZERO, 2.0)
	_expect(bool(registered.ok), "registry: actor registration failed")
	var moved: Dictionary = registry.move_actor("hero", Vector2(40.0, 0.0), 1, Rect2(-100.0, -100.0, 300.0, 300.0))
	_expect(bool(moved.ok) and bool(moved.blocked), "registry: motor result was not committed")
	var state = registry.actor("hero")
	_expect(state != null and state.feet_position.x < 20.0, "registry: actor crossed its blocker")
	var repeated: Dictionary = registry.move_actor("hero", Vector2.RIGHT, 1)
	_expect(not bool(repeated.ok), "registry: duplicate tick was accepted")
	_expect(registry.actor_ids() == ["hero"], "registry: actor identity order changed")


func _test_simulation_orders_commands_and_versions_events() -> void:
	var simulation = SimulationWorldScript.new()
	var configured: Dictionary = simulation.configure(30, "room/0", 2)
	_expect(bool(configured.ok), "simulation: valid configuration rejected")
	simulation.queue_command({"entity_id": "z", "kind": "move"})
	simulation.queue_command({"entity_id": "a", "kind": "attack"})
	var event_result: Dictionary = simulation.publish_event({"kind": "spawned", "entity_id": "a"})
	_expect(bool(event_result.ok), "simulation: event rejected")
	var frame: Dictionary = simulation.step()
	_expect(int(frame.tick) == 1, "simulation: tick did not advance exactly once")
	_expect(String(frame.commands[0].entity_id) == "a" and String(frame.commands[1].entity_id) == "z", "simulation: command order depends on insertion")
	_expect(int(frame.events[0].world_revision) == 2 and String(frame.events[0].room_instance_id) == "room/0", "simulation: event version context missing")


func _test_presenter_has_separate_layers_and_no_debug_by_default() -> void:
	var presenter = WorldPresenterScript.new()
	get_root().add_child(presenter)
	presenter._ensure_layers()
	var report: Dictionary = presenter.presentation_report()
	_expect(report.layers == ["Ground", "GroundEffects", "SortRoot", "Foreground"], "presenter: layer contract changed")
	_expect(not bool(report.debug_geometry_visible), "presenter: geometry diagnostics enabled by default")
	_expect(bool(report.sort_root_y_sort), "presenter: sort root is not y-sorted")
	presenter.queue_free()


func _test_scene_runtime_lifecycle() -> void:
	var runtime = SceneRuntimeScript.new()
	get_root().add_child(runtime)
	var definition = RoomDefinitionScript.new({
		"room_id": "room/1",
		"world_asset_id": "asset/1",
		"encounter_id": "encounter.none",
		"ruleset_id": "rules.default",
		"tags": ["sample"],
	})
	var asset = WorldAssetScript.new("res://world/room.tscn", "res://world/room.spatial.json", "game", "presentation", 1)
	var manifest = SpatialManifestScript.new({
		"coordinate_convention": {"units": "pixel"},
		"stable_bindings": [],
		"traversal_profiles": [],
		"regions_and_portals": [],
		"spawn_interaction_exit_sockets": [],
		"gameplay_spatial_metadata": {},
	})
	var mounted: Dictionary = runtime.mount(definition, asset, null, manifest, 3, 30)
	_expect(bool(mounted.ok) and runtime.is_ready(), "runtime: valid room did not mount")
	_expect(String(runtime.report().room_instance_id) == "room/1/1", "runtime: room identity missing")
	var duplicate: Dictionary = runtime.mount(definition, asset, null, manifest, 0, 30)
	_expect(not bool(duplicate.ok), "runtime: second mount replaced active room")
	_expect(runtime.accepts_version("room/1/1", 3), "runtime: current version was not accepted")
	_expect(not runtime.accepts_version("room/1/1", 2), "runtime: stale revision was accepted")
	var unmounted: Dictionary = runtime.unmount()
	_expect(bool(unmounted.ok) and not runtime.is_ready(), "runtime: unmount did not clear state")
	runtime.queue_free()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
