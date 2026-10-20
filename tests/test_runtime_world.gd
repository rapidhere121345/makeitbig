extends SceneTree

const EntityDefinitionScript = preload("res://src/runtime/world/entity_definition.gd")
const ActorStateScript = preload("res://src/runtime/world/actor_state.gd")
const ActorRegistryScript = preload("res://src/runtime/world/actor_registry.gd")
const SimulationWorldScript = preload("res://src/runtime/world/simulation_world.gd")
const RoomActorAccessScript = preload("res://src/runtime/world/room_actor_access.gd")
const SimCommandScript = preload("res://src/runtime/simulation/sim_command.gd")
const SimEntityHandleScript = preload("res://src/runtime/simulation/sim_entity_handle.gd")
const StaticSpatialIndexScript = preload("res://src/runtime/spatial/static_spatial_index.gd")
const DynamicSpatialIndexScript = preload("res://src/runtime/spatial/dynamic_spatial_index.gd")
const SpatialOverlayScript = preload("res://src/runtime/spatial/spatial_overlay.gd")
const MovementResolverScript = preload("res://src/runtime/spatial/movement_resolver.gd")
const RoomDefinitionScript = preload("res://src/runtime/world/room_definition.gd")
const WorldAssetScript = preload("res://src/runtime/world/world_asset.gd")
const SpatialManifestScript = preload("res://src/runtime/world/spatial_manifest.gd")
const SceneRuntimeScript = preload("res://src/runtime/world/scene_runtime.gd")
const WorldPresenterScript = preload("res://src/runtime/world/world_presenter.gd")
const ContractPlanScript = preload("res://src/game/contract_plan.gd")
const CombatRoomRuntimeScript = preload("res://src/game/combat_room_runtime.gd")
const ItemRegistryScript = preload("res://src/content/early_item_registry.gd")
const BuildResolverScript = preload("res://src/systems/build_resolver.gd")
const ContentRegistryScript = preload("res://src/content/content_registry.gd")
const ProxyBuildScript = preload("res://src/systems/proxy_build.gd")
const WorldFactory = preload("res://tests/simulation/sim_test_world_factory.gd")

const RING_BOUNDARY := {"kind": "ring", "center": Vector2(640.0, 434.0), "inner_radius": 97.6, "outer_radius": 209.84}
const RING_LEGAL_START := Vector2(461.7138366699219, 515.0391845703125)

var failures: Array[String] = []
var first_session_spawn := Vector2.ZERO
## Kernel graphs created by this harness; shutdown severs the kernel -> port
## -> access -> registry borrow cycle so the engine exits without leaking
## the migration fixtures' room graphs.
var _worlds: Array = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_entity_definition_is_static()
	_test_actor_state_is_versioned_instance_state()
	_test_actor_commit_rejects_stale_room_references()
	_test_actor_access_is_the_movement_commit_boundary()
	_test_simulation_orders_commands_and_stamps_versions()
	_test_presenter_has_separate_layers_and_no_debug_by_default()
	_test_ring_access_commit_clearance()
	_test_access_rejects_illegal_geometry_without_state_pollution()
	_test_scene_runtime_lifecycle()
	await _test_ring_real_combat_ticks()
	for world in _worlds:
		if world != null and world.kernel != null:
			world.kernel.shutdown()
	_worlds.clear()
	if failures.is_empty():
		print("PASS test_runtime_world.gd")
		quit(0)
		return
	for failure: String in failures:
		printerr("- %s" % failure)
	quit(1)


func _make_room_access(room: String, revision: int, boundary: Variant = null, surfaces: Array = []) -> Dictionary:
	var asset: Dictionary = {"schema_version": 1, "asset_id": "test/%s" % room, "surfaces": surfaces}
	if boundary != null:
		asset["movement_boundary"] = boundary
	var static_build: Dictionary = StaticSpatialIndexScript.build(asset)
	if not bool(static_build.get("ok", false)):
		return {"ok": false, "error": "static index rejected: %s" % str(static_build.get("errors", []))}
	var world = SimulationWorldScript.new()
	var configured: SimOutcome = world.configure(room, revision, 30)
	if not configured.ok:
		return {"ok": false, "error": String(configured.error)}
	_worlds.append(world)
	var dynamic := DynamicSpatialIndexScript.new()
	var overlay := SpatialOverlayScript.new()
	var resolver_build: Dictionary = MovementResolverScript.make(static_build.get("value"), overlay, dynamic)
	if not bool(resolver_build.get("ok", false)):
		return {"ok": false, "error": "movement resolver rejected"}
	var access = RoomActorAccessScript.new()
	var access_result: Dictionary = access.configure(world, world.actor_registry, static_build.get("value"), dynamic, resolver_build.get("value"), overlay)
	if not bool(access_result.get("ok", false)):
		return {"ok": false, "error": String(access_result.get("error", ""))}
	return {"ok": true, "error": "", "world": world, "access": access}


func _fixture_ready(fixture: Dictionary, label: String) -> bool:
	if bool(fixture.get("ok", false)):
		return true
	failures.append("%s: fixture failed: %s" % [label, String(fixture.get("error", ""))])
	return false


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
	var state: ActorState = ActorStateScript.create(Vector2(10.0, 12.0), 6.0, "room/0", 4, Vector2.DOWN, 3)
	_expect(state.feet_position == Vector2(10.0, 12.0) and state.previous_feet_position == Vector2(10.0, 12.0), "actor state: valid instance did not start at its authored pose")
	_expect(state.room_instance_id == "room/0" and state.world_revision == 4 and state.footprint_radius == 6.0, "actor state: room identity or footprint missing")
	var unassigned: SimOutcome = state.commit_movement(Vector2(11.0, 12.0), 1)
	_expect(not unassigned.ok and unassigned.error == &"unidentified_record" and state.feet_position == Vector2(10.0, 12.0), "actor state: unidentified record accepted a movement commit")
	state.set_entity_identity(SimEntityHandleScript.make(0, 1, &"actors", "room/0", 4), 1)
	var non_finite: SimOutcome = state.commit_movement(Vector2(INF, 12.0), 1)
	_expect(not non_finite.ok and non_finite.error == &"invalid_movement_position" and state.feet_position == Vector2(10.0, 12.0), "actor state: non-finite position was accepted")
	var applied: SimOutcome = state.commit_movement(Vector2(11.0, 12.0), 1, Vector2.RIGHT)
	_expect(applied.ok and state.feet_position == Vector2(11.0, 12.0), "actor state: current motor result was rejected")
	_expect(state.previous_feet_position == Vector2(10.0, 12.0) and state.last_movement_tick == 1 and state.velocity == Vector2(1.0, 0.0) and state.facing.is_equal_approx(Vector2.RIGHT), "actor state: previous position, tick, velocity or facing missing")
	var repeated: SimOutcome = state.commit_movement(Vector2(12.0, 12.0), 1)
	_expect(not repeated.ok and repeated.error == &"non_monotonic_movement_tick" and state.feet_position == Vector2(11.0, 12.0), "actor state: duplicate tick was accepted")
	var teleported: SimOutcome = state.teleport(Vector2(20.0, 12.0))
	_expect(teleported.ok and state.feet_position == Vector2(20.0, 12.0) and state.previous_feet_position == Vector2(20.0, 12.0) and state.velocity == Vector2.ZERO and state.last_movement_tick == 1, "actor state: teleport consumed a movement tick or leaked velocity")
	_expect(state.health == 3.0 and state.hit_points == 3 and state.maximum_health == 3.0, "actor state: initial health projection missing")
	state.apply_damage(1)
	_expect(state.alive and state.health == 2.0 and state.hit_points == 2, "actor state: damage did not reduce health")
	state.apply_damage(5)
	_expect(not state.alive and state.health == 0.0 and state.hit_points == 0, "actor state: lethal damage left the record alive")
	state.apply_damage(3)
	_expect(state.health == 0.0, "actor state: dead record absorbed damage")
	var rejected_health: SimOutcome = state.commit_resolved_health(state.maximum_health + 1.0)
	_expect(not rejected_health.ok and rejected_health.error == &"invalid_resolved_health", "actor state: out-of-range resolved health was accepted")


func _test_actor_commit_rejects_stale_room_references() -> void:
	var fixture := _make_room_access("room/0", 4)
	if not _fixture_ready(fixture, "stale room access"):
		return
	var access = fixture.access
	var spawned: SimOutcome = access.registry.spawn_actor(Vector2.ZERO, 2.0, "room/0", 4)
	_expect(spawned.ok and spawned.stable_key > 0, "registry: setup spawn failed")
	if not spawned.ok:
		return
	var record: ActorState = spawned.value
	if record == null:
		var resolved_record: SimOutcome = access.registry.resolve(spawned.handle)
		_expect(resolved_record.ok and resolved_record.value is ActorState, "registry: spawned record did not resolve")
		if not resolved_record.ok:
			return
		record = resolved_record.value
	record.room_instance_id = "room/old"
	var stale: SimOutcome = access.registry.commit_movement(spawned.handle, Vector2(4.0, 0.0), 1)
	_expect(not stale.ok and stale.error == &"stale_room_reference" and record.feet_position == Vector2.ZERO, "registry: stale room reference moved the record")
	record.room_instance_id = "room/0"
	var recovered: SimOutcome = access.registry.commit_movement(spawned.handle, Vector2(4.0, 0.0), 1)
	_expect(recovered.ok and record.feet_position == Vector2(4.0, 0.0), "registry: current room reference was rejected")


func _test_actor_access_is_the_movement_commit_boundary() -> void:
	var wall := {"id": "wall", "shape": {"kind": "rect", "rect": Rect2(20.0, -20.0, 4.0, 40.0)}, "channels": [&"movement"]}
	var fixture := _make_room_access("room/registry", 7, null, [wall])
	if not _fixture_ready(fixture, "access boundary"):
		return
	var access = fixture.access
	var registered: Dictionary = access.register_actor("hero", Vector2.ZERO, 2.0)
	_expect(bool(registered.get("ok", false)), "access: actor registration failed")
	var moved: Dictionary = access.move_actor("hero", Vector2(40.0, 0.0), 1)
	_expect(bool(moved.get("ok", false)) and bool(moved.get("blocked", false)), "access: blocked displacement did not commit a slide-resolved position")
	var state = access.actor("hero")
	_expect(state != null and state.feet_position.x < 20.0, "access: actor crossed its blocker")
	_expect(access.is_position_clear(state.feet_position, 2.0), "access: committed footprint overlaps the blocker")
	var repeated: Dictionary = access.move_actor("hero", Vector2.RIGHT, 1)
	_expect(not bool(repeated.get("ok", false)), "access: duplicate tick was accepted")
	_expect(access.actor_ids() == ["hero"], "access: actor identity order changed")


func _test_simulation_orders_commands_and_stamps_versions() -> void:
	var fixture := WorldFactory.make_world("room/0", 2, 30)
	var world = fixture["world"]
	var spatial = fixture["spatial"]
	_worlds.append(world)

	var stale_room := SimCommandScript.control(SimEntityHandleScript.make(0, 1), Vector2.ZERO, false)
	stale_room.room_instance_id = "room/old"
	var room_result: SimOutcome = world.queue_command(stale_room)
	_expect(not room_result.ok and room_result.error == &"stale_room_reference", "simulation: stale room command was accepted")
	var stale_revision := SimCommandScript.control(SimEntityHandleScript.make(0, 1), Vector2.ZERO, false)
	stale_revision.world_revision = 1
	var revision_result: SimOutcome = world.queue_command(stale_revision)
	_expect(not revision_result.ok and revision_result.error == &"stale_world_revision", "simulation: stale revision command was accepted")

	var first_record := ActorStateScript.create(Vector2.ZERO, 0.5, "room/0", 2)
	var second_record := ActorStateScript.create(Vector2(10.0, 0.0), 0.5, "room/0", 2)
	_expect(world.queue_command(SimCommandScript.spawn_entity(second_record)).ok, "simulation: first queued spawn was rejected")
	_expect(world.queue_command(SimCommandScript.spawn_entity(first_record)).ok, "simulation: second queued spawn was rejected")
	_expect(world.ticks_for_frame(1.0 / 30.0) == 1, "simulation: frame accumulator did not produce one authoritative tick")
	_expect(world.tick == 0, "simulation: consuming a frame advanced the authority clock without step_tick")
	var first: SimOutcome = world.step_tick()
	_expect(first.ok and world.tick == 1 and int(first.value.tick) == 1, "simulation: tick did not advance exactly once")
	_expect(String(first.value.room_instance_id) == "room/0" and int(first.value.world_revision) == 2, "simulation: snapshot lost its version context")
	_expect(second_record.stable_key == 1 and first_record.stable_key == 2, "simulation: stable keys did not follow command submission order")

	var control_second := SimCommandScript.control(second_record.get_entity_handle(), Vector2.LEFT, false)
	var control_first := SimCommandScript.control(first_record.get_entity_handle(), Vector2.RIGHT, false)
	_expect(world.queue_command(control_second).ok and world.queue_command(control_first).ok, "simulation: control commands were rejected")
	_expect(String(control_second.room_instance_id) == "room/0" and int(control_second.world_revision) == 2 and int(control_first.world_revision) == 2, "simulation: accepted command lost its stamped version")
	var second: SimOutcome = world.step_tick()
	_expect(second.ok, "simulation: control tick failed")
	_expect(spatial.movement_log == [[2, 1], [2, 2]], "simulation: commands did not commit in submission order")

	_expect(world.ticks_for_frame(0.5) == 15, "simulation: batched frame did not preserve fixed tick count")
	_expect(world.tick == 2, "simulation: room state was advanced outside an explicit step")
	var snapshots: Array[SimSnapshot] = world.advance_frame(0.5)
	_expect(snapshots.size() == 15 and world.tick == 17, "simulation: advance_frame did not run exactly the owed ticks")


func _test_presenter_has_separate_layers_and_no_debug_by_default() -> void:
	var presenter = WorldPresenterScript.new()
	get_root().add_child(presenter)
	presenter._ensure_layers()
	var report: Dictionary = presenter.presentation_report()
	_expect(report.layers == ["Ground", "GroundEffects", "SortRoot", "Foreground"], "presenter: layer contract changed")
	_expect(not bool(report.debug_geometry_visible), "presenter: geometry diagnostics enabled by default")
	_expect(bool(report.sort_root_y_sort), "presenter: sort root is not y-sorted")
	presenter.queue_free()


func _test_ring_access_commit_clearance() -> void:
	var fixture := _make_room_access("room/ring-clearance", 3, RING_BOUNDARY)
	if not _fixture_ready(fixture, "ring access"):
		return
	var access = fixture.access
	var registered: Dictionary = access.register_actor("ranger", RING_LEGAL_START, 14.0)
	_expect(bool(registered.get("ok", false)), "ring access: legal registration failed")
	var actor = access.actor("ranger")
	for tick in range(1, 61):
		var direction := Vector2.LEFT if tick <= 30 else Vector2.RIGHT
		var previous: Vector2 = actor.feet_position
		var moved: Dictionary = access.move_actor("ranger", direction * (245.0 / 30.0), tick)
		_expect(bool(moved.get("ok", false)), "ring access: legal move failed at tick %d" % tick)
		_expect(access.is_position_clear(actor.feet_position, 14.0), "ring access: committed footprint illegal at tick %d" % tick)
		_expect(actor.last_movement_tick == tick and actor.previous_feet_position == previous, "ring access: tick/previous position did not commit exactly once")
		if tick == 1:
			_expect(actor.feet_position.distance_to(RING_LEGAL_START) > 3.0, "ring access: exact production tangent was discarded")
		if tick == 31:
			_expect(not bool(moved.get("blocked", false)) and actor.feet_position.distance_to(previous + direction * (245.0 / 30.0)) <= 0.0001, "ring access: immediate reverse escape failed")
	var before_position: Vector2 = actor.feet_position
	var idle: Dictionary = access.move_actor("ranger", Vector2.ZERO, 61)
	_expect(bool(idle.get("ok", false)) and actor.feet_position == before_position and actor.last_movement_tick == 61, "ring access: stationary tick jittered or failed to commit")


func _test_access_rejects_illegal_geometry_without_state_pollution() -> void:
	var fixture := _make_room_access("room/invalid-motor", 4, RING_BOUNDARY)
	if not _fixture_ready(fixture, "invalid geometry access"):
		return
	var access = fixture.access
	# An illegal author placement is refused at registration: no actor, no
	# state, and no committed tick can exist for it.
	var refused: Dictionary = access.register_actor("invalid", Vector2(640.0, 434.0), 14.0)
	_expect(not bool(refused.get("ok", false)) and String(refused.get("error", "")) == "actor_spawn_blocked", "access: illegal author spawn was not refused at registration")
	_expect(not access.has_actor("invalid"), "access: refused spawn leaked an actor id")
	var registered: Dictionary = access.register_actor("invalid", RING_LEGAL_START, 14.0)
	_expect(bool(registered.get("ok", false)), "access: legal retry after refusal failed")
	var bad_input: Dictionary = access.move_actor("invalid", Vector2(INF, 0.0), 1)
	_expect(not bool(bad_input.get("ok", false)) and String(bad_input.get("error", "")) == "invalid_movement_request", "access: invalid displacement was accepted")
	var before: Dictionary = access.actor_snapshot("invalid")
	_expect(not before.is_empty(), "access: actor snapshot missing")
	var blocked_teleport: Dictionary = access.teleport_actor("invalid", Vector2(640.0, 434.0))
	_expect(not bool(blocked_teleport.get("ok", false)) and String(blocked_teleport.get("error", "")) == "teleport_blocked", "access: blocked teleport was accepted")
	_expect(access.actor_snapshot("invalid") == before, "access: rejected input polluted ActorState")
	# The commit boundary judges every endpoint through the real shared query:
	# a displacement straight into the boundary commits a legal slide position,
	# never an illegal endpoint.
	var inward := (Vector2(640.0, 434.0) - RING_LEGAL_START).normalized()
	var into_boundary: Dictionary = access.move_actor("invalid", inward * 300.0, 1)
	_expect(bool(into_boundary.get("ok", false)) and bool(into_boundary.get("blocked", false)), "access: boundary-crossing displacement did not resolve against the boundary")
	_expect(access.is_position_clear(access.actor("invalid").feet_position, 14.0), "access: committed endpoint violated clearance")
	_expect(access.actor_snapshot("invalid") != before, "access: legal slide did not commit state")
	var repeated: Dictionary = access.move_actor("invalid", Vector2.ZERO, 1)
	_expect(not bool(repeated.get("ok", false)), "access: duplicate tick was accepted after a commit")
	var unknown: Dictionary = access.move_actor("missing", Vector2.RIGHT, 1)
	_expect(not bool(unknown.get("ok", false)) and String(unknown.get("error", "")) == "unknown_actor", "access: unknown actor was not rejected")


func _test_scene_runtime_lifecycle() -> void:
	var runtime = SceneRuntimeScript.new()
	get_root().add_child(runtime)
	var definition = RoomDefinitionScript.new({
		"room_id": "room/1",
		"world_asset_id": "combat/corridor",
		"encounter_id": "encounter.none",
		"ruleset_id": "rules.default",
		"tags": ["sample"],
	})
	var real_manifest_path := "res://content/rooms/combat/corridor.spatial.json"
	var manifest_file := FileAccess.open(real_manifest_path, FileAccess.READ)
	var manifest_payload: Variant = JSON.parse_string(manifest_file.get_as_text()) if manifest_file != null else null
	var real_manifest = SpatialManifestScript.from_dict(manifest_payload)
	var gameplay_digest := real_manifest.gameplay_digest_sha256()
	var presentation_digest := real_manifest.presentation_digest_sha256()
	var missing_scene_asset = WorldAssetScript.new("res://content/rooms/combat/missing.tscn", real_manifest_path, "game", "presentation", 1)
	var missing_scene: Dictionary = runtime.mount(definition, missing_scene_asset, null, null, 3, 30)
	_expect(String(missing_scene.get("error", "")) == "world_scene_missing" and not runtime.is_ready(), "runtime: missing world scene was not rejected before mount")
	var missing_manifest_asset = WorldAssetScript.new("res://src/game/main.tscn", "res://content/rooms/combat/missing.spatial.json", "game", "presentation", 1)
	var missing_manifest: Dictionary = runtime.mount(definition, missing_manifest_asset, null, null, 3, 30)
	_expect(String(missing_manifest.get("error", "")) == "manifest_missing" and not runtime.is_ready(), "runtime: missing manifest was not rejected before mount")
	var missing_native_contract_asset = WorldAssetScript.new("res://src/game/main.tscn", real_manifest_path, gameplay_digest, presentation_digest, 1)
	var missing_native_contract: Dictionary = runtime.mount(definition, missing_native_contract_asset, null, null, 3, 30)
	_expect(String(missing_native_contract.get("error", "")) == "native_scene_contract_missing" and not runtime.is_ready(), "runtime: a scene without the native room contract was accepted")
	var asset = WorldAssetScript.new("res://content/rooms/combat/corridor.tscn", real_manifest_path, gameplay_digest, presentation_digest, 1)
	var mounted: Dictionary = runtime.mount(definition, asset, null, null, 3, 30)
	_expect(bool(mounted.get("ok", false)) and runtime.is_ready(), "runtime: valid room did not mount")
	_expect(String(runtime.report().room_instance_id) == "room/1/1", "runtime: room identity missing")
	var report: Dictionary = runtime.report()
	var native_scene: Dictionary = report.get("native_scene", {})
	_expect(String(native_scene.get("layout_id", "")) == "corridor" and (native_scene.get("groups", []) as Array).size() == 6, "runtime: native room scene contract was not published")
	_expect(String((native_scene.get("bindings", {}) as Dictionary).get("Sockets/CombatSpawn", "")) == "combat/spawn", "runtime: native spawn binding was not published")
	var boundary: Dictionary = report.get("movement_boundary", {})
	_expect(String(boundary.get("type", "")) == "corridor" and boundary.get("rect", Rect2()).is_equal_approx(Rect2(42.0, 190.0, 1196.0, 488.0)), "runtime: manifest boundary was not converted to the authored corridor")
	var registered: Dictionary = runtime.register_actor("hero", Vector2(640.0, 434.0), 14.0)
	_expect(bool(registered.get("ok", false)), "runtime: manifest-backed actor registration failed")
	var moved: Dictionary = runtime.move_actor("hero", Vector2(0.0, -200.0), 1)
	_expect(bool(moved.get("ok", false)) and bool(moved.get("blocked", false)) and float(moved.position.y) >= 375.9, "runtime: manifest boundary did not constrain actor movement")
	var duplicate: Dictionary = runtime.mount(definition, asset, null, null, 0, 30)
	_expect(not bool(duplicate.ok), "runtime: second mount replaced active room")
	_expect(runtime.accepts_version("room/1/1", 3), "runtime: current version was not accepted")
	_expect(not runtime.accepts_version("room/1/1", 2), "runtime: stale revision was accepted")
	# Sever the kernel borrow cycle before unmount replaces the simulation, so
	# the retired room graph frees instead of leaking.
	if runtime.simulation != null and runtime.simulation.kernel != null:
		runtime.simulation.kernel.shutdown()
	var retired_world = runtime.simulation
	var unmounted: Dictionary = runtime.unmount()
	# The unmount boundary must run against live storage; sever the retired
	# kernel graph only after it completed, so it frees instead of leaking.
	if retired_world != null and retired_world.kernel != null:
		retired_world.kernel.shutdown()
	_expect(bool(unmounted.ok) and not runtime.is_ready(), "runtime: unmount did not clear state")
	runtime.queue_free()


func _test_ring_real_combat_ticks() -> void:
	var plan: Dictionary = ContractPlanScript.build({"contract_id": "side_targeted_equipment", "seed": 0, "mode": "Manual"}).plan
	var items = ItemRegistryScript.new()
	_expect(items.load_all().is_empty(), "ring real ticks: item load failed")
	var content = ContentRegistryScript.new()
	_expect(content.load_all().is_empty(), "ring real ticks: content load failed")
	var build: Dictionary = BuildResolverScript.new(items).resolve_fixture("calibration_convergent")
	var proxy: Dictionary = ProxyBuildScript.compile({"cores": ["near_enemy_horizon", "direct_gait", "single_key_execution", "short_trace_memory"]}, content.cores)
	_expect(bool(build.get("ok", false)) and bool(proxy.get("ok", false)), "ring real ticks: canonical fixture rejected")
	var first_frames: Array[Dictionary] = []
	for repetition in 2:
		var runtime = CombatRoomRuntimeScript.new()
		get_root().add_child(runtime)
		var started: Dictionary = runtime.start_session({"contract_id": "side_targeted_equipment", "seed": 0, "mode": "Manual",
			"room_index": 1, "room_count": 3, "room": plan.rooms[1], "presentation_enabled": false,
			"framework_context": {"resolved_build": build, "resolved_proxy_build": proxy.get("value", {}), "active_build": {"skills": ["piercing_arrow"]}}})
		_expect(bool(started.get("ok", false)), "ring real ticks: production room failed to start")
		if not bool(started.get("ok", false)):
			runtime.queue_free()
			await process_frame
			return
		var arena = runtime.room_instance
		var scene = runtime.scene_runtime
		var registry = arena.actor_registry
		var world = arena.simulation_world
		arena.set_process(false)
		runtime.set_process(false)
		_expect(registry != null and registry.has_actor("ranger") and world != null, "ring real ticks: Main actor access missing after start")
		var session_spawn: Vector2 = registry.actor("ranger").feet_position
		if repetition == 0:
			first_session_spawn = session_spawn
		else:
			_expect(session_spawn == first_session_spawn, "ring real ticks: identical sessions produced different player spawns")
		_expect(registry.is_position_clear(session_spawn, 14.0), "ring real ticks: production spawn footprint illegal")
		## The native contract stores the raw derive payload; the mounted
		## manifest stores its canonical snapshot (sorted, trimmed). Compare
		## through the same canonical form the repeatable matrix uses.
		_expect(SpatialManifestScript.new(scene.native_scene_contract.spatial_manifest).snapshot() == scene.manifest.snapshot(), "ring real ticks: native manifest differed")
		var frames: Array[Dictionary] = []
		for tick in range(1, 61):
			var action := "move_left" if tick <= 20 or (tick >= 41 and tick <= 50) else "move_right"
			var previous: Vector2 = registry.actor("ranger").feet_position
			Input.action_press(action)
			var stepped: Dictionary = arena.combat_simulation.step()
			Input.action_release(action)
			_expect(bool(stepped.get("ok", false)) and int(world.tick) == tick, "ring real ticks: real step failed or fabricated tick %d" % tick)
			var frame := {"tick": tick, "actors": []}
			for id: String in registry.actor_ids():
				var actor = registry.actor(id)
				var position: Vector2 = actor.feet_position
				var footprint: float = actor.footprint_radius
				_expect(registry.is_position_clear(position, scene.authored_arena_rect, footprint) and registry.is_position_clear(position, Rect2(), footprint), "ring real ticks: %s footprint illegal at tick %d" % [id, tick])
				_expect(actor.room_instance_id == world.room_instance_id and actor.world_revision == world.world_revision and int(actor.last_movement_tick) <= tick, "ring real ticks: actor identity or motor tick invalid")
				frame.actors.append({"id": id, "position": position, "radius": footprint, "last_movement_tick": actor.last_movement_tick})
			var player = registry.actor("ranger")
			_expect(player.last_movement_tick == tick and player.previous_feet_position == previous, "ring real ticks: player motor did not commit exactly once")
			if tick == 1:
				_expect(player.feet_position.distance_to(previous) > 3.0, "ring real ticks: tick1 tangent stuck")
			if tick == 21:
				_expect(player.feet_position.distance_to(previous + Vector2.RIGHT * (245.0 / 30.0)) <= 0.0001, "ring real ticks: immediate reverse lost free displacement")
			frames.append(frame)
		if repetition == 0:
			first_frames = frames
		else:
			_expect(frames == first_frames, "ring real ticks: same authored room and public input produced different actor positions")
		runtime.request_abandon()
		_expect(bool(scene.unmount().get("ok", false)), "ring real ticks: native room unmount failed")
		_expect(scene.entity_registry.live_count() == 0, "ring real ticks: production unload retained live actors")
		runtime.queue_free()
		# The abandon/unmount boundary must run against live storage; sever the
		# retired kernel graph afterwards so it frees instead of leaking.
		if world != null and world.kernel != null:
			world.kernel.shutdown()
		await process_frame
		await process_frame
	print("RING_REAL_TICKS checked=120 repetitions=2")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
