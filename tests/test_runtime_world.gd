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
const ContractPlanScript = preload("res://src/game/contract_plan.gd")
const CombatRoomRuntimeScript = preload("res://src/game/combat_room_runtime.gd")
const ItemRegistryScript = preload("res://src/content/early_item_registry.gd")
const BuildResolverScript = preload("res://src/systems/build_resolver.gd")
const ContentRegistryScript = preload("res://src/content/content_registry.gd")
const ProxyBuildScript = preload("res://src/systems/proxy_build.gd")

var failures: Array[String] = []
var _simulation_probe_ticks: Array[int] = []


class InvalidEndpointMotor:
	extends "res://src/runtime/geometry/actor_motor.gd"

	func move(start: Vector2, displacement: Vector2, _bounds: Rect2 = Rect2()) -> Dictionary:
		return {"ok": true, "error": "", "position": start + displacement, "blocked": false, "contacts": [], "remaining": Vector2.ZERO, "iterations": 1}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_entity_definition_is_static()
	_test_actor_state_is_versioned_instance_state()
	_test_actor_registry_is_the_movement_commit_boundary()
	_test_ring_registry_commit_clearance()
	_test_registry_rejects_before_mutating_actor_state()
	_test_simulation_orders_commands_and_versions_events()
	_test_presenter_has_separate_layers_and_no_debug_by_default()
	_test_scene_runtime_lifecycle()
	await _test_ring_real_combat_ticks()
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
	_expect(not bool(simulation.queue_command({"kind": "move", "room_instance_id": "room/old", "world_revision": 2}).ok), "simulation: stale room command was accepted")
	_expect(not bool(simulation.queue_command({"kind": "move", "room_instance_id": "room/0", "world_revision": 1}).ok), "simulation: stale revision command was accepted")
	simulation.queue_command({"entity_id": "z", "kind": "move"})
	simulation.queue_command({"entity_id": "a", "kind": "attack"})
	var event_result: Dictionary = simulation.publish_event({"kind": "spawned", "entity_id": "a"})
	_expect(bool(event_result.ok), "simulation: event rejected")
	var frame: Dictionary = simulation.step()
	_expect(int(frame.tick) == 1, "simulation: tick did not advance exactly once")
	_expect(String(frame.commands[0].entity_id) == "a" and String(frame.commands[1].entity_id) == "z", "simulation: command order depends on insertion")
	_expect(String(frame.commands[0].room_instance_id) == "room/0" and int(frame.commands[0].world_revision) == 2, "simulation: accepted command lost its version")
	_expect(int(frame.events[0].world_revision) == 2 and String(frame.events[0].room_instance_id) == "room/0", "simulation: event version context missing")
	_simulation_probe_ticks.clear()
	var first_frame_ticks := simulation.ticks_for_frame(1.0 / 30.0)
	_expect(first_frame_ticks == 1, "simulation: frame accumulator did not produce one authoritative tick")
	simulation.step()
	_expect(simulation.tick == 2, "simulation: frame tick was not committed by SimulationWorld")
	var second_frame_ticks := simulation.ticks_for_frame(0.5)
	_expect(second_frame_ticks == 15, "simulation: batched frame did not preserve fixed tick count")
	_simulation_probe_ticks.append(simulation.tick)
	_expect(_simulation_probe_ticks == [2], "simulation: room state was advanced outside an explicit step")


func _test_ring_registry_commit_clearance() -> void:
	var registry = ActorRegistryScript.new()
	registry.configure("room/ring-clearance", 3)
	registry.set_boundary({"type": "ring", "center": Vector2(640.0, 434.0), "inner_radius": 97.6, "outer_radius": 209.84})
	var start := Vector2(461.7138366699219, 515.0391845703125)
	registry.register_actor("ranger", start, 14.0)
	var actor = registry.actor("ranger")
	for tick in range(1, 61):
		var direction := Vector2.LEFT if tick <= 30 else Vector2.RIGHT
		var previous: Dictionary = actor.snapshot()
		var moved: Dictionary = registry.move_actor("ranger", direction * (245.0 / 30.0), tick)
		_expect(bool(moved.get("ok", false)), "ring registry: legal move failed at tick %d" % tick)
		_expect(registry.is_position_clear(actor.feet_position, Rect2(), 14.0), "ring registry: committed footprint illegal at tick %d" % tick)
		_expect(actor.last_motor_tick == tick and actor.previous_feet_position == previous.feet_position, "ring registry: tick/previous position did not commit exactly once")
		if tick == 1:
			_expect(actor.feet_position.distance_to(start) > 3.0, "ring registry: exact production tangent was discarded")
		if tick == 31:
			_expect(not bool(moved.blocked) and actor.feet_position.distance_to(previous.feet_position + direction * (245.0 / 30.0)) <= 0.0001, "ring registry: immediate reverse escape failed")
	var before_idle: Dictionary = actor.snapshot()
	var idle: Dictionary = registry.move_actor("ranger", Vector2.ZERO, 61)
	_expect(bool(idle.get("ok", false)) and actor.feet_position == before_idle.feet_position and actor.last_motor_tick == 61, "ring registry: stationary tick jittered or failed to commit")


func _test_registry_rejects_before_mutating_actor_state() -> void:
	var registry = ActorRegistryScript.new()
	registry.configure("room/invalid-motor", 4)
	registry.set_boundary({"type": "ring", "center": Vector2(640.0, 434.0), "inner_radius": 97.6, "outer_radius": 209.84})
	# An invalid author placement remains observable through actor registration.
	# Movement must reject it without repairing it or consuming a motor tick.
	registry.register_actor("invalid", Vector2(640.0, 434.0), 14.0)
	var invalid = registry.actor("invalid")
	var before: Dictionary = invalid.snapshot()
	var rejected: Dictionary = registry.move_actor("invalid", Vector2.RIGHT * 200.0, 1)
	_expect(not bool(rejected.get("ok", false)) and rejected.get("error", "") == "invalid_motor_start", "registry: illegal author spawn was not explicitly rejected")
	_expect(invalid.snapshot() == before and not registry.is_position_clear(invalid.feet_position, Rect2(), 14.0), "registry: invalid author spawn was moved or state/tick polluted")
	var rejected_idle: Dictionary = registry.move_actor("invalid", Vector2.ZERO, 1)
	_expect(not bool(rejected_idle.get("ok", false)) and invalid.snapshot() == before, "registry: invalid stationary start consumed a tick")
	var valid_start := Vector2(461.7138366699219, 515.0391845703125)
	registry.teleport_actor("invalid", valid_start)
	var retried: Dictionary = registry.move_actor("invalid", Vector2.RIGHT, 1)
	_expect(bool(retried.get("ok", false)) and invalid.last_motor_tick == 1, "registry: rejected move consumed the later real tick")
	var valid_before: Dictionary = invalid.snapshot()
	var bad_input: Dictionary = registry.move_actor("invalid", Vector2(INF, 0.0), 2)
	_expect(not bool(bad_input.get("ok", false)) and invalid.snapshot() == valid_before, "registry: invalid input polluted ActorState")
	# Exercise the independent commit check with an intentionally lying motor;
	# the real shared query still judges its footprint, without a second clamp.
	registry._motor = InvalidEndpointMotor.new(14.0)
	registry.set_boundary({"type": "ring", "center": Vector2(640.0, 434.0), "inner_radius": 97.6, "outer_radius": 209.84})
	var bad_endpoint: Dictionary = registry.move_actor("invalid", Vector2.LEFT * 100.0, 2)
	_expect(not bool(bad_endpoint.get("ok", false)) and bad_endpoint.get("error", "") == "invalid_motor_clearance", "registry: illegal motor endpoint was accepted")
	_expect(invalid.snapshot() == valid_before, "registry: endpoint validation ran after apply_motor_result")
	_expect(not bad_endpoint.has("tick"), "registry: rejected endpoint fabricated a committed tick")


func _test_presenter_has_separate_layers_and_no_debug_by_default() -> void:
	var presenter = WorldPresenterScript.new()
	get_root().add_child(presenter)
	presenter._ensure_layers()
	var report: Dictionary = presenter.presentation_report()
	_expect(report.layers == ["Ground", "GroundEffects", "SortRoot", "Foreground"], "presenter: layer contract changed")
	_expect(not bool(report.debug_geometry_visible), "presenter: geometry diagnostics enabled by default")
	_expect(bool(report.sort_root_y_sort), "presenter: sort root is not y-sorted")
	presenter.queue_free()


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
		var registry = scene.actor_registry
		var world = scene.simulation
		arena.set_process(false)
		runtime.set_process(false)
		_expect(arena.actor_registry == registry and arena.simulation_world == world, "ring real ticks: Main did not use the native shared registry/world")
		_expect(scene.native_scene_contract.spatial_manifest == scene.manifest.snapshot(), "ring real ticks: native manifest differed")
		_expect(registry.actor("ranger").feet_position == Vector2(461.7138366699219, 515.0391845703125), "ring real ticks: production author spawn changed")
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
				_expect(actor.room_instance_id == world.room_instance_id and actor.world_revision == world.world_revision and int(actor.last_motor_tick) <= tick, "ring real ticks: actor identity or motor tick invalid")
				frame.actors.append({"id": id, "position": position, "radius": footprint, "last_motor_tick": actor.last_motor_tick})
			var player = registry.actor("ranger")
			_expect(player.last_motor_tick == tick and player.previous_feet_position == previous, "ring real ticks: player motor did not commit exactly once")
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
		runtime.queue_free()
		await process_frame
		await process_frame
		_expect(registry.actor_ids().is_empty() and registry.snapshot().blockers.is_empty(), "ring real ticks: production unload retained actor/blockers")
	print("RING_REAL_TICKS checked=120 repetitions=2")


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
	var missing_scene_asset = WorldAssetScript.new("res://content/rooms/combat/missing.tscn", real_manifest_path, "game", "presentation", 1)
	var missing_scene: Dictionary = runtime.mount(definition, missing_scene_asset, null, null, 3, 30)
	_expect(String(missing_scene.get("error", "")) == "world_scene_missing" and not runtime.is_ready(), "runtime: missing world scene was not rejected before mount")
	var missing_manifest_asset = WorldAssetScript.new("res://src/game/main.tscn", "res://content/rooms/combat/missing.spatial.json", "game", "presentation", 1)
	var missing_manifest: Dictionary = runtime.mount(definition, missing_manifest_asset, null, null, 3, 30)
	_expect(String(missing_manifest.get("error", "")) == "manifest_missing" and not runtime.is_ready(), "runtime: missing manifest was not rejected before mount")
	var missing_native_contract_asset = WorldAssetScript.new("res://src/game/main.tscn", real_manifest_path, "game", "presentation", 1)
	var missing_native_contract: Dictionary = runtime.mount(definition, missing_native_contract_asset, null, null, 3, 30)
	_expect(String(missing_native_contract.get("error", "")) == "native_scene_contract_missing" and not runtime.is_ready(), "runtime: a scene without the native room contract was accepted")
	var asset = WorldAssetScript.new("res://content/rooms/combat/corridor.tscn", real_manifest_path, "game", "presentation", 1)
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
	var unmounted: Dictionary = runtime.unmount()
	_expect(bool(unmounted.ok) and not runtime.is_ready(), "runtime: unmount did not clear state")
	runtime.queue_free()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
