extends SceneTree

## Focused regression for RoomSpatialPort inside a real fixed tick.
##
## Run: godot --headless --path . --script res://tests/test_spatial_room_port.gd
## Covers: static wall blocking for queued path queries and movement intents,
## dynamic target hits at the swept TOI, the equal-TOI wall-priority rule,
## safe no-op ticks without queries, and fail-closed queue validation.
##
# Geometry note: query sources in these tests keep their own body out of the
# swept hurtbox bucket. Self-hit suppression is still a port contract, while
# the geometry kernel separately rejects separating and negative-entry roots.

const Fixtures := preload("res://tests/spatial/spatial_fixtures.gd")
const StaticSpatialIndexScript := preload("res://src/runtime/spatial/static_spatial_index.gd")
const DynamicSpatialIndexScript := preload("res://src/runtime/spatial/dynamic_spatial_index.gd")
const MovementResolverScript := preload("res://src/runtime/spatial/movement_resolver.gd")
const SpatialOverlayScript := preload("res://src/runtime/spatial/spatial_overlay.gd")
const SpatialChannels := preload("res://src/runtime/spatial/spatial_channels.gd")
const RoomSpatialPortScript := preload("res://src/runtime/world/room_spatial_port.gd")
const RoomActorAccessScript := preload("res://src/runtime/world/room_actor_access.gd")
const SimulationWorldScript := preload("res://src/runtime/world/simulation_world.gd")
const SimCommandScript := preload("res://src/runtime/simulation/sim_command.gd")
const Assert := preload("res://tests/helpers/assert.gd")

var failures: Array[String] = []
## Every world mounted by this harness. Shutdown at the end of the run severs
## the kernel -> port -> access -> registry borrow cycle so the engine exits
## without leaking the room graphs; explicit cleanup, not a suppressed warning.
var _worlds: Array[SimulationWorld] = []


func _initialize() -> void:
	_test_static_wall_blocks_query_and_movement()
	_test_overlay_commits_at_movement_boundary()
	_test_dynamic_target_hit_at_toi()
	_test_equal_toi_wall_wins_over_target()
	_test_no_queries_is_safe_noop()
	_test_queue_validation_fails_closed()
	_test_stale_source_handle_fails_closed()
	_test_unbound_port_reports_errors_without_hits()
	_test_own_body_never_takes_self_damage()
	_test_separating_body_never_takes_false_damage()
	_teardown_worlds()
	if failures.is_empty():
		print("PASS  test_spatial_room_port.gd")
		quit(0)
		return
	printerr("FAIL  test_spatial_room_port.gd")
	for failure in failures:
		printerr("- %s" % failure)
	quit(1)


func _test_static_wall_blocks_query_and_movement() -> void:
	var room := _make_room(Fixtures.wall_world())
	if room.is_empty():
		_expect(false, "wall: room fixture failed to mount")
		return
	var world: SimulationWorld = room["world"]
	var port: RoomSpatialPort = room["port"]
	var access: RoomActorAccess = room["access"]
	# Movement-only source body: the shooter's hurtbox must not participate
	# in its own projectile sweeps (see the geometry-gap note above).
	var ranger_spawn := access.register_actor("ranger", Vector2(20.0, 60.0), 6.0, 20, &"soft", [SpatialChannels.MOVEMENT])
	_expect(bool(ranger_spawn["ok"]), "wall: ranger failed to spawn: %s" % String(ranger_spawn.get("error", "")))
	var ranger: SimEntityHandle = access.actor_handle("ranger")
	var query := RoomSpatialPortScript.PathQuery.make(
		ranger, SpatialChannels.PROJECTILE, Vector2(30.0, 60.0), Vector2(140.0, 0.0), 0.0, 3, &"projectile"
	)
	var queued: Dictionary = port.queue_path_query(query)
	_expect(bool(queued["ok"]), "wall: valid projectile query was rejected: %s" % str(queued.get("errors", [])))
	var ticked: SimOutcome = world.step_tick()
	_expect(ticked.ok, "wall: tick failed: %s" % String(ticked.error))
	var results := port.take_path_results()
	_expect(results.size() == 1, "wall: expected one path result, got %d" % results.size())
	if results.size() == 1:
		var result: RoomSpatialPortScript.PathResult = results[0]
		_expect(result.ok, "wall: resolver rejected the query: %s" % str(result.errors))
		_expect(result.clipped, "wall: projectile path crossed the wall without clipping")
		_expect(_near(result.stop_toi, 0.5), "wall: projectile stop toi changed: %s" % str(result.stop_toi))
		_expect(_near(result.end_point.x, 100.0), "wall: projectile end point crossed the wall plane")
		_expect(result.hit_actor_ids.is_empty(), "wall: static stop produced phantom entity hits")
	var hits := world.kernel.hit_buffer.hits()
	_expect(hits.is_empty(), "wall: static-only clip must not write SimHit records")

	# Movement still commits through the room MovementResolver boundary.
	var mover_spawn := access.register_actor("mover", Vector2(80.0, 60.0), 6.0, 20)
	_expect(bool(mover_spawn["ok"]), "wall: mover failed to spawn")
	var commanded: SimOutcome = world.queue_command(SimCommandScript.control(access.actor_handle("mover"), Vector2(40.0, 0.0), false))
	_expect(commanded.ok, "wall: control command was rejected")
	var moved: SimOutcome = world.step_tick()
	_expect(moved.ok, "wall: movement tick failed")
	var mover := access.actor("mover")
	_expect(mover != null and _near(mover.feet_position.x, 94.0), "wall: mover tunneled past the MovementResolver contact plane")
	_expect(mover != null and _near(mover.feet_position.y, 60.0), "wall: mover drifted off the movement axis")
	var body := access.dynamic_index.body("mover")
	_expect(not body.is_empty() and _near((body["position"] as Vector2).x, 94.0), "wall: committed pose missed the dynamic index")
	_expect(world.kernel.hit_buffer.hits().is_empty(), "wall: blocked movement wrote hit records")


func _test_dynamic_target_hit_at_toi() -> void:
	var room := _make_room(Fixtures.open_world())
	if room.is_empty():
		_expect(false, "toi: room fixture failed to mount")
		return
	var world: SimulationWorld = room["world"]
	var port: RoomSpatialPort = room["port"]
	var access: RoomActorAccess = room["access"]
	_expect(bool(access.register_actor("ranger", Vector2(20.0, 60.0), 6.0, 20, &"soft", [SpatialChannels.MOVEMENT])["ok"]), "toi: ranger failed to spawn")
	_expect(bool(access.register_actor("slime", Vector2(60.0, 60.0), 6.0, 5)["ok"]), "toi: slime failed to spawn")
	var ranger: SimEntityHandle = access.actor_handle("ranger")
	var slime: SimEntityHandle = access.actor_handle("slime")
	var query := RoomSpatialPortScript.PathQuery.make(
		ranger, SpatialChannels.PROJECTILE, Vector2(30.0, 60.0), Vector2(40.0, 0.0), 0.0, 3, &"projectile"
	)
	_expect(bool(port.queue_path_query(query)["ok"]), "toi: valid query was rejected")
	_expect(world.step_tick().ok, "toi: tick failed")
	var results := port.take_path_results()
	_expect(results.size() == 1, "toi: expected one path result")
	if results.size() == 1:
		var result: RoomSpatialPortScript.PathResult = results[0]
		_expect(result.ok and result.clipped, "toi: dynamic target did not clip the path")
		_expect(_near(result.stop_toi, 0.6), "toi: dynamic stop toi changed: %s" % str(result.stop_toi))
		_expect(_near(result.end_point.x, 54.0), "toi: dynamic end point changed")
		_expect(result.hit_actor_ids == ["slime"], "toi: hit target identity lost: %s" % str(result.hit_actor_ids))
	var hits := world.kernel.hit_buffer.hits()
	_expect(hits.size() == 1, "toi: expected exactly one SimHit, got %d" % hits.size())
	if hits.size() == 1:
		var hit: SimHit = hits[0]
		_expect(hit.source == ranger, "toi: hit source was not the attacking handle")
		_expect(hit.target == slime, "toi: hit target was not the swept actor handle")
		_expect(hit.amount == 3, "toi: hit amount did not carry the query amount")
		_expect(hit.contact_kind == &"projectile", "toi: hit contact kind lost")

	# The query executed exactly once; later ticks neither replay it nor leak
	# stale results or hits.
	_expect(port.pending_path_query_count() == 0, "toi: executed query stayed pending")
	_expect(world.step_tick().ok, "toi: follow-up tick failed")
	_expect(port.take_path_results().is_empty(), "toi: results leaked across ticks")
	_expect(world.kernel.hit_buffer.hits().is_empty(), "toi: hits leaked across ticks")


func _test_overlay_commits_at_movement_boundary() -> void:
	var room := _make_room(Fixtures.open_world())
	if room.is_empty():
		_expect(false, "overlay boundary: room fixture failed to mount")
		return
	var world: SimulationWorld = room["world"]
	var access: RoomActorAccess = room["access"]
	var overlay: SpatialOverlay = room["overlay"]
	_expect(bool(access.register_actor("ranger", Vector2(20.0, 60.0), 6.0, 20)["ok"]), "overlay boundary: ranger failed to spawn")
	_expect(bool(overlay.add_surface({
		"id": "gate",
		"shape": {"kind": "rect", "rect": Rect2(48.0, 50.0, 4.0, 20.0)},
		"channels": [SpatialChannels.MOVEMENT],
	})["ok"]), "overlay boundary: gate request was rejected")
	_expect(overlay.revision() == 0 and overlay.pending_operation_count() == 1, "overlay boundary: gate changed before the fixed tick")
	_expect(world.queue_command(SimCommandScript.control(access.actor_handle("ranger"), Vector2(40.0, 0.0), false)).ok, "overlay boundary: movement command was rejected")
	_expect(world.step_tick().ok, "overlay boundary: first tick failed")
	var ranger := access.actor("ranger")
	_expect(overlay.revision() == 1 and overlay.last_committed_tick() == 1 and overlay.pending_operation_count() == 0, "overlay boundary: pending gate did not commit in movement phase")
	_expect(ranger != null and _near(ranger.feet_position.x, 42.0), "overlay boundary: movement read a half-committed gate")
	_expect(overlay.remove_surface("gate")["ok"], "overlay boundary: gate removal request was rejected")
	_expect(world.queue_command(SimCommandScript.control(access.actor_handle("ranger"), Vector2(40.0, 0.0), false)).ok, "overlay boundary: second movement command was rejected")
	_expect(world.step_tick().ok, "overlay boundary: second tick failed")
	_expect(overlay.revision() == 2 and overlay.last_committed_tick() == 2, "overlay boundary: gate removal did not commit on the next tick")
	_expect(ranger != null and _near(ranger.feet_position.x, 82.0), "overlay boundary: removed gate still affected the next committed tick")


func _test_equal_toi_wall_wins_over_target() -> void:
	var room := _make_room(Fixtures.tie_world())
	if room.is_empty():
		_expect(false, "tie: room fixture failed to mount")
		return
	var world: SimulationWorld = room["world"]
	var port: RoomSpatialPort = room["port"]
	var access: RoomActorAccess = room["access"]
	_expect(bool(access.register_actor("ranger", Vector2(10.0, 60.0), 6.0, 20, &"soft", [SpatialChannels.MOVEMENT])["ok"]), "tie: ranger failed to spawn")
	# The shield face and the guard hurtbox both contact the path at x=100.
	_expect(bool(access.register_actor("guard", Vector2(106.0, 60.0), 6.0, 5)["ok"]), "tie: guard failed to spawn")
	var query := RoomSpatialPortScript.PathQuery.make(
		access.actor_handle("ranger"), SpatialChannels.PROJECTILE, Vector2(20.0, 60.0), Vector2(90.0, 0.0), 0.0, 3, &"projectile"
	)
	_expect(bool(port.queue_path_query(query)["ok"]), "tie: valid query was rejected")
	_expect(world.step_tick().ok, "tie: tick failed")
	var results := port.take_path_results()
	_expect(results.size() == 1, "tie: expected one path result")
	if results.size() == 1:
		var result: RoomSpatialPortScript.PathResult = results[0]
		_expect(result.ok and result.clipped, "tie: shielded path did not clip")
		_expect(_near(result.stop_toi, 80.0 / 90.0), "tie: shield stop toi changed")
		_expect(_near(result.end_point.x, 100.0), "tie: shield end point changed")
		_expect(result.hit_actor_ids.is_empty(), "tie: equal-toi target behind the wall was hit anyway")
	_expect(world.kernel.hit_buffer.hits().is_empty(), "tie: wall-priority rule must suppress the SimHit record")


func _test_no_queries_is_safe_noop() -> void:
	var room := _make_room(Fixtures.open_world())
	if room.is_empty():
		_expect(false, "noop: room fixture failed to mount")
		return
	var world: SimulationWorld = room["world"]
	var port: RoomSpatialPort = room["port"]
	var access: RoomActorAccess = room["access"]
	_expect(bool(access.register_actor("ranger", Vector2(20.0, 60.0), 6.0, 20)["ok"]), "noop: ranger failed to spawn")
	_expect(port.pending_path_query_count() == 0, "noop: fresh port already had pending queries")
	for step in 2:
		var ticked: SimOutcome = world.step_tick()
		_expect(ticked.ok, "noop: tick %d failed" % step)
		_expect(port.take_path_results().is_empty(), "noop: tick %d invented path results" % step)
		_expect(world.kernel.hit_buffer.hits().is_empty(), "noop: tick %d invented hits" % step)
		var snapshot: SimSnapshot = ticked.value
		var trace_names: Array[String] = []
		for phase in snapshot.phase_trace:
			trace_names.append(String(phase))
		_expect(trace_names.has("continuous_queries"), "noop: tick %d lost the continuous_queries phase" % step)


func _test_queue_validation_fails_closed() -> void:
	var room := _make_room(Fixtures.open_world())
	if room.is_empty():
		_expect(false, "queue: room fixture failed to mount")
		return
	var world: SimulationWorld = room["world"]
	var port: RoomSpatialPort = room["port"]
	var access: RoomActorAccess = room["access"]
	_expect(bool(access.register_actor("ranger", Vector2(20.0, 60.0), 6.0, 20, &"soft", [SpatialChannels.MOVEMENT])["ok"]), "queue: ranger failed to spawn")
	_expect(bool(access.register_actor("slime", Vector2(60.0, 60.0), 6.0, 5)["ok"]), "queue: slime failed to spawn")
	var ranger: SimEntityHandle = access.actor_handle("ranger")
	var rejection_cases := [
		[null, "path_query:invalid_type"],
		[{}, "path_query:invalid_type"],
		[RoomSpatialPortScript.PathQuery.make(null, SpatialChannels.PROJECTILE, Vector2(30.0, 60.0), Vector2(40.0, 0.0), 0.0, 3, &"projectile"), "path_query.source:missing"],
		[RoomSpatialPortScript.PathQuery.make(ranger, SpatialChannels.MOVEMENT, Vector2(30.0, 60.0), Vector2(40.0, 0.0), 0.0, 3, &"projectile"), "path_query.channel:invalid:movement"],
		[RoomSpatialPortScript.PathQuery.make(ranger, SpatialChannels.PROJECTILE, Vector2(NAN, 60.0), Vector2(40.0, 0.0), 0.0, 3, &"projectile"), "path_query.start:non_finite"],
		[RoomSpatialPortScript.PathQuery.make(ranger, SpatialChannels.PROJECTILE, Vector2(30.0, 60.0), Vector2(INF, 0.0), 0.0, 3, &"projectile"), "path_query.displacement:non_finite"],
		[RoomSpatialPortScript.PathQuery.make(ranger, SpatialChannels.PROJECTILE, Vector2(30.0, 60.0), Vector2(40.0, 0.0), -1.0, 3, &"projectile"), "path_query.radius:invalid"],
		[RoomSpatialPortScript.PathQuery.make(ranger, SpatialChannels.PROJECTILE, Vector2(30.0, 60.0), Vector2(40.0, 0.0), 0.0, 0, &"projectile"), "path_query.amount:invalid"],
		[RoomSpatialPortScript.PathQuery.make(ranger, SpatialChannels.PROJECTILE, Vector2(30.0, 60.0), Vector2(40.0, 0.0), 0.0, 3, &""), "path_query.contact_kind:missing"],
	]
	for entry: Array in rejection_cases:
		var result: Dictionary = port.queue_path_query(entry[0])
		_expect(not bool(result["ok"]), "queue: invalid query was accepted: %s" % str(entry[1]))
		_expect((result["errors"] as Array).has(entry[1]), "queue: expected error %s, got %s" % [str(entry[1]), str(result.get("errors", []))])
	_expect(port.pending_path_query_count() == 0, "queue: rejected queries changed the pending queue")

	var arrow := RoomSpatialPortScript.PathQuery.make(
		ranger, SpatialChannels.PROJECTILE, Vector2(30.0, 60.0), Vector2(40.0, 0.0), 0.0, 3, &"projectile"
	)
	var slash := RoomSpatialPortScript.PathQuery.make(
		ranger, SpatialChannels.ATTACK, Vector2(30.0, 60.0), Vector2(40.0, 0.0), 0.0, 5, &"melee"
	)
	_expect(bool(port.queue_path_query(arrow)["ok"]), "queue: valid projectile query was rejected")
	_expect(bool(port.queue_path_query(slash)["ok"]), "queue: valid attack query was rejected")
	_expect(port.pending_path_query_count() == 2, "queue: pending count lost queued queries")
	_expect(world.step_tick().ok, "queue: tick failed")
	_expect(port.pending_path_query_count() == 0, "queue: executed queries stayed pending")
	var results := port.take_path_results()
	_expect(results.size() == 2, "queue: expected two path results, got %d" % results.size())
	if results.size() == 2:
		_expect(results[0].channel == SpatialChannels.PROJECTILE, "queue: result order lost the projectile query")
		_expect(results[1].channel == SpatialChannels.ATTACK, "queue: result order lost the attack query")
	var hits := world.kernel.hit_buffer.hits()
	_expect(hits.size() == 2, "queue: expected two SimHit records, got %d" % hits.size())
	if hits.size() == 2:
		_expect(hits[0].amount == 3 and hits[0].contact_kind == &"projectile", "queue: projectile hit identity lost")
		_expect(hits[1].amount == 5 and hits[1].contact_kind == &"melee", "queue: attack hit identity lost")


func _test_unbound_port_reports_errors_without_hits() -> void:
	var port := RoomSpatialPortScript.new()
	var world := SimulationWorldScript.new(port, null, null, null)
	var configured: SimOutcome = world.configure("unbound-port-room", 2, 30)
	_expect(configured.ok, "unbound: world configuration failed")
	_worlds.append(world)
	# The queue only checks shape; execution reports the missing room access
	# instead of silently dropping the query or crashing the tick.
	var query := RoomSpatialPortScript.PathQuery.make(
		SimEntityHandle.make(0, 1, &"actors", "unbound-port-room", 2), SpatialChannels.PROJECTILE, Vector2.ZERO, Vector2(10.0, 0.0), 0.0, 1, &"projectile"
	)
	_expect(bool(port.queue_path_query(query)["ok"]), "unbound: valid query was rejected at queue time")
	var ticked: SimOutcome = world.step_tick()
	_expect(ticked.ok, "unbound: tick with unbound port failed")
	var results := port.take_path_results()
	_expect(results.size() == 1, "unbound: expected one reported result, got %d" % results.size())
	if results.size() == 1:
		_expect(not results[0].ok and results[0].errors.has("path_query:spatial_access_unbound"), "unbound: missing access was not reported fail-closed")
	_expect(world.kernel.hit_buffer.hits().is_empty(), "unbound: unbound port invented hits")


func _test_stale_source_handle_fails_closed() -> void:
	var room := _make_room(Fixtures.open_world())
	if room.is_empty():
		_expect(false, "stale: room fixture failed to mount")
		return
	var world: SimulationWorld = room["world"]
	var port: RoomSpatialPort = room["port"]
	var access: RoomActorAccess = room["access"]
	_expect(bool(access.register_actor("ranger", Vector2(20.0, 60.0), 6.0, 20, &"soft", [SpatialChannels.MOVEMENT])["ok"]), "stale: ranger failed to spawn")
	_expect(bool(access.register_actor("slime", Vector2(60.0, 60.0), 6.0, 5)["ok"]), "stale: slime failed to spawn")
	var current: SimEntityHandle = access.actor_handle("ranger")
	var stale := SimEntityHandle.make(current.index, current.generation, current.store_id, "retired-room/1", current.world_revision)
	var query := RoomSpatialPortScript.PathQuery.make(
		stale, SpatialChannels.PROJECTILE, Vector2(30.0, 60.0), Vector2(40.0, 0.0), 0.0, 3, &"projectile"
	)
	_expect(bool(port.queue_path_query(query).get("ok", false)), "stale: structurally valid old-room query was rejected before execution")
	_expect(world.step_tick().ok, "stale: tick failed")
	var results := port.take_path_results()
	_expect(results.size() == 1 and not results[0].ok and results[0].errors.has("path_query:source_stale"), "stale: old-room source was allowed into the query: %s" % str(results))
	_expect(world.kernel.hit_buffer.hits().is_empty(), "stale: old-room source created a hit")


func _test_own_body_never_takes_self_damage() -> void:
	var room := _make_room(Fixtures.open_world())
	if room.is_empty():
		_expect(false, "self: room fixture failed to mount")
		return
	var world: SimulationWorld = room["world"]
	var port: RoomSpatialPort = room["port"]
	var access: RoomActorAccess = room["access"]
	# Default channels put the shooter's own hurtbox in the swept bucket; a
	# path started at the body center meets it immediately.  The port must
	# clip there without ever recording damage against the source handle.
	_expect(bool(access.register_actor("ranger", Vector2(20.0, 60.0), 6.0, 20)["ok"]), "self: ranger failed to spawn")
	_expect(bool(access.register_actor("slime", Vector2(60.0, 60.0), 6.0, 5)["ok"]), "self: slime failed to spawn")
	var ranger: SimEntityHandle = access.actor_handle("ranger")
	var query := RoomSpatialPortScript.PathQuery.make(
		ranger, SpatialChannels.PROJECTILE, Vector2(20.0, 60.0), Vector2(40.0, 0.0), 0.0, 3, &"projectile"
	)
	_expect(bool(port.queue_path_query(query)["ok"]), "self: valid query was rejected")
	_expect(world.step_tick().ok, "self: tick failed")
	var results := port.take_path_results()
	_expect(results.size() == 1 and results[0].clipped and _near(results[0].stop_toi, 0.0), "self: path through the own body did not clip at the start")
	if results.size() == 1:
		_expect(results[0].hit_actor_ids.is_empty(), "self: source body was reported as a hit target")
	var hits := world.kernel.hit_buffer.hits()
	_expect(hits.is_empty(), "self: source body took self damage")


func _test_separating_body_never_takes_false_damage() -> void:
	var room := _make_room(Fixtures.open_world())
	if room.is_empty():
		_expect(false, "separating: room fixture failed to mount")
		return
	var world: SimulationWorld = room["world"]
	var port: RoomSpatialPort = room["port"]
	var access: RoomActorAccess = room["access"]
	# The bystander is behind the path start and separating from it.  The
	# geometry clamp (see header note) reports a phantom toi-0 contact; the
	# port's entering classification must still refuse to record damage.
	_expect(bool(access.register_actor("ranger", Vector2(20.0, 60.0), 6.0, 20, &"soft", [SpatialChannels.MOVEMENT])["ok"]), "separating: ranger failed to spawn")
	_expect(bool(access.register_actor("bystander", Vector2(0.0 + 12.0, 60.0), 6.0, 5)["ok"]), "separating: bystander failed to spawn")
	var bystander: SimEntityHandle = access.actor_handle("bystander")
	var query := RoomSpatialPortScript.PathQuery.make(
		access.actor_handle("ranger"), SpatialChannels.PROJECTILE, Vector2(30.0, 60.0), Vector2(40.0, 0.0), 0.0, 3, &"projectile"
	)
	_expect(bool(port.queue_path_query(query)["ok"]), "separating: valid query was rejected")
	_expect(world.step_tick().ok, "separating: tick failed")
	for hit: SimHit in world.kernel.hit_buffer.hits():
		_expect(not hit.target.equals_handle(bystander), "separating: body behind the path start took phantom damage")


func _make_room(asset: Dictionary) -> Dictionary:
	var static_build: Dictionary = StaticSpatialIndexScript.build(asset)
	if not bool(static_build["ok"]):
		return {}
	var static_index: StaticSpatialIndex = static_build["value"]
	var dynamic_index := DynamicSpatialIndexScript.new()
	var overlay := SpatialOverlayScript.new()
	var movement_build: Dictionary = MovementResolverScript.make(static_index, overlay, dynamic_index)
	if not bool(movement_build["ok"]):
		return {}
	var port := RoomSpatialPortScript.new()
	var world := SimulationWorldScript.new(port, null, null, null)
	var configured: SimOutcome = world.configure("spatial-port-test-room", 5, 30)
	if not configured.ok:
		return {}
	_worlds.append(world)
	var access := RoomActorAccessScript.new()
	var access_result: Dictionary = access.configure(world, world.actor_registry, static_index, dynamic_index, movement_build["value"], overlay)
	if not bool(access_result.get("ok", false)):
		return {}
	port.bind(access)
	return {"world": world, "port": port, "access": access, "overlay": overlay}


func _teardown_worlds() -> void:
	for world in _worlds:
		if world != null and world.kernel != null:
			world.kernel.shutdown()
	_worlds.clear()


func _expect(condition: bool, message: String) -> void: Assert.expect(condition, message, failures)


func _near(a: float, b: float, epsilon: float = 0.0001) -> bool:
	return abs(a - b) <= epsilon
