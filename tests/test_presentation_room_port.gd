extends SceneTree

## Headless seam test: authoritative SimSnapshot rows -> typed presentation
## bindings -> PresentationFrame -> OcclusionPlan -> OcclusionController.
## Runs the real fixed-tick kernel with test-only fake ports, so the rows the
## projector consumes are the store's real snapshot rows.

const SimTestWorldScript := preload("res://src/runtime/world/simulation_world.gd")
const ActorRegistryScript := preload("res://src/runtime/world/actor_registry.gd")
const RoomActorAccessScript := preload("res://src/runtime/world/room_actor_access.gd")
const RoomPresentationPortScript := preload("res://src/runtime/world/room_presentation_port.gd")
const BindingScript := preload("res://src/presentation/room_presentation_binding.gd")
const ProjectorScript := preload("res://src/presentation/room_presentation_projector.gd")
const SnapshotScript := preload("res://src/runtime/simulation/sim_snapshot.gd")
const ControllerScript := preload("res://src/presentation/occlusion/occlusion_controller.gd")
const StaticSpatialIndexScript := preload("res://src/runtime/spatial/static_spatial_index.gd")
const DynamicSpatialIndexScript := preload("res://src/runtime/spatial/dynamic_spatial_index.gd")
const SpatialOverlayScript := preload("res://src/runtime/spatial/spatial_overlay.gd")
const MovementResolverScript := preload("res://src/runtime/spatial/movement_resolver.gd")
const SpatialFixtures := preload("res://tests/spatial/spatial_fixtures.gd")
const FakeSpatialPortScript := preload("res://tests/simulation/fake_spatial_port.gd")
const FakeCombatPortScript := preload("res://tests/simulation/fake_combat_port.gd")
const FakeEncounterPortScript := preload("res://tests/simulation/fake_encounter_port.gd")

const ROOM_ID := "presentation-port-room"
const REVISION := 7
const TICK_RATE := 30

# Authored feet positions inside the 200x120 open fixture boundary.
const HERO_FEET := Vector2(60.0, 40.0)
const GRUNT_FEET := Vector2(92.0, 62.0)
const SCOUT_FEET := Vector2(150.0, 30.0)
const PILLAR_FEET := Vector2(66.0, 70.0)
# Real authored art boxes, bottom-center anchored on their own feet.
const HERO_BOX := Rect2(-14.0, -48.0, 28.0, 48.0)
const GRUNT_BOX := Rect2(-12.0, -40.0, 24.0, 40.0)
const SCOUT_BOX := Rect2(-12.0, -40.0, 24.0, 40.0)
const PILLAR_BOX := Rect2(-20.0, -64.0, 40.0, 64.0)

var failures: Array[String] = []
## Worlds mounted by this harness; shutdown severs the kernel -> port ->
## access -> registry borrow cycle so the engine exits without room-graph leaks.
var _worlds: Array = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_binding_rejects_missing_or_substitute_art_box()
	_test_unbound_port_keeps_header_only_frame()
	await _test_projected_frame_drives_multi_actor_occlusion()
	await _test_missing_actor_binding_fails_closed_then_recovers()
	_test_projector_verifies_snapshot_rows()
	await _test_presentation_churn_never_writes_simulation()
	for world in _worlds:
		if world != null and world.kernel != null:
			world.kernel.shutdown()
	_worlds.clear()
	for failure: String in failures:
		printerr("- %s" % failure)
	print("PASS test_presentation_room_port.gd" if failures.is_empty() else "FAIL test_presentation_room_port.gd")
	quit(0 if failures.is_empty() else 1)


func _test_binding_rejects_missing_or_substitute_art_box() -> void:
	var missing := BindingScript.for_actor("hero", "ranger.body", 2, null)
	_expect(not bool(missing.get("ok", false)) and String(missing.get("error", "")) == "missing_presentation_art_box", "binding accepted a missing art box", failures)
	# A footprint radius is gameplay collision data: it must be rejected by name.
	var radius_substitute := BindingScript.for_actor("hero", "ranger.body", 2, 6.0)
	_expect(not bool(radius_substitute.get("ok", false)), "binding accepted a footprint radius as art box", failures)
	var zero_box := BindingScript.for_actor("hero", "ranger.body", 2, Rect2(0.0, 0.0, 8.0, 0.0))
	_expect(not bool(zero_box.get("ok", false)), "binding accepted a zero-height art box", failures)
	var non_finite := BindingScript.for_actor("hero", "ranger.body", 2, Rect2(Vector2.INF, Vector2(8.0, 8.0)))
	_expect(not bool(non_finite.get("ok", false)), "binding accepted a non-finite art box", failures)
	var no_static_feet := BindingScript.for_static_piece("pillar", "scene.pillar", 0, PILLAR_BOX, null)
	_expect(not bool(no_static_feet.get("ok", false)), "static binding accepted a missing feet anchor", failures)
	var valid := BindingScript.for_actor("hero", "ranger.body", 2, HERO_BOX)
	_expect(bool(valid.get("ok", false)), "binding rejected a real art box", failures)


func _test_unbound_port_keeps_header_only_frame() -> void:
	var port = RoomPresentationPortScript.new()
	var snapshot := SnapshotScript.new()
	snapshot.tick = 4
	snapshot.world_revision = REVISION
	snapshot.room_instance_id = ROOM_ID
	snapshot.rows = []
	port.on_snapshot(snapshot)
	_expect(port.latest_frame != null, "unbound port produced no frame", failures)
	if port.latest_frame != null:
		_expect(port.latest_frame.entries.is_empty(), "unbound port invented entries", failures)
		_expect(port.latest_frame.tick == 4 and port.latest_frame.world_revision == REVISION, "unbound port lost frame header", failures)
	var plan: Dictionary = port.latest_occlusion_plan()
	_expect(bool(plan.get("ok", false)) and (plan["value"] as Object).call("size") == 0, "unbound port plan is not an empty detached plan", failures)


func _make_world(presentation_port) -> Dictionary:
	var spatial = FakeSpatialPortScript.new()
	var combat = FakeCombatPortScript.new()
	var encounter = FakeEncounterPortScript.new()
	var world = SimTestWorldScript.new(spatial, combat, encounter, presentation_port, ActorRegistryScript.new())
	var configured = world.configure(ROOM_ID, REVISION, TICK_RATE)
	_expect(bool(configured.ok), "simulation world rejected configuration", failures)
	_worlds.append(world)
	var static_build: Dictionary = StaticSpatialIndexScript.build(SpatialFixtures.open_world())
	_expect(bool(static_build.get("ok", false)), "static spatial fixture rejected", failures)
	var dynamic_index = DynamicSpatialIndexScript.new()
	var overlay = SpatialOverlayScript.new()
	var movement: Dictionary = MovementResolverScript.make(static_build.get("value"), overlay, dynamic_index)
	_expect(bool(movement.get("ok", false)), "movement resolver rejected", failures)
	var access = RoomActorAccessScript.new()
	var access_result: Dictionary = access.configure(world, world.actor_registry, static_build.get("value"), dynamic_index, movement.get("value"), overlay)
	_expect(bool(access_result.get("ok", false)), "room actor access rejected configuration", failures)
	spatial.registry = world.actor_registry
	return {"world": world, "access": access, "port": presentation_port}


func _bind_seam(port, access) -> Dictionary:
	var projector = ProjectorScript.new()
	var bound: Dictionary = port.bind_projector(projector)
	_expect(bool(bound.get("ok", false)), "port rejected the projector", failures)
	_expect(bool(projector.bind_access(access).get("ok", false)), "projector rejected the actor access", failures)
	for config: Array in [
		["hero", "ranger.body", 2, HERO_BOX, HERO_FEET],
		["grunt", "grunt.body", 1, GRUNT_BOX, GRUNT_FEET],
		["scout", "scout.body", 1, SCOUT_BOX, SCOUT_FEET],
	]:
		var actor_binding: Dictionary = BindingScript.for_actor(config[0], config[1], config[2], config[3])
		_expect(bool(actor_binding.get("ok", false)), "actor binding for %s rejected" % config[0], failures)
		_expect(bool(projector.bind_actor_visual(actor_binding.get("value")).get("ok", false)), "projector rejected actor binding %s" % config[0], failures)
	var pillar: Dictionary = BindingScript.for_static_piece("pillar", "scene.pillar", 0, PILLAR_BOX, PILLAR_FEET)
	_expect(bool(pillar.get("ok", false)), "pillar binding rejected", failures)
	_expect(bool(projector.bind_static_visual(pillar.get("value")).get("ok", false)), "projector rejected the pillar binding", failures)
	return {"projector": projector}


func _register_actors(access) -> void:
	for config: Array in [
		["hero", HERO_FEET],
		["grunt", GRUNT_FEET],
		["scout", SCOUT_FEET],
	]:
		var registered: Dictionary = access.register_actor(config[0], config[1], 6.0)
		_expect(bool(registered.get("ok", false)), "actor %s spawn rejected" % config[0], failures)


func _entry(port, stable_id: String) -> Dictionary:
	for entry: Dictionary in port.latest_frame.entries:
		if String(entry["stable_id"]) == stable_id:
			return entry
	return {}


func _test_projected_frame_drives_multi_actor_occlusion() -> void:
	var port = RoomPresentationPortScript.new()
	var fixture := _make_world(port)
	var access = fixture["access"]
	_register_actors(access)
	_bind_seam(port, access)
	var stepped = fixture["world"].step_tick()
	_expect(bool(stepped.ok), "kernel tick failed", failures)
	var frame = port.latest_frame
	_expect(frame != null, "projected frame missing after tick", failures)
	if frame == null:
		return
	_expect(frame.entries.size() == 4, "frame entry count mismatch", failures)
	# Real actor projection: authoritative feet, authored rank, real art box.
	var hero := _entry(port, "hero")
	var hero_access: Dictionary = access.actor_snapshot("hero")
	_expect(hero.get("feet_anchor", Vector2.INF) == hero_access.get("feet_position", Vector2.INF), "hero feet did not come from the authoritative snapshot", failures)
	_expect(int(hero.get("rank", -1)) == 2, "hero lost its authored rank", failures)
	_expect(hero.get("visual_id", "") == "ranger.body", "hero lost its visual id", failures)
	var hero_world_box := Rect2(HERO_FEET + HERO_BOX.position, HERO_BOX.size)
	_expect(hero.get("art_box", Rect2()) == hero_world_box, "hero art box is not the authored box anchored on its feet", failures)
	_expect(hero.get("art_box", Rect2()) != Rect2(HERO_FEET.x - 6.0, HERO_FEET.y - 6.0, 12.0, 12.0), "hero art box equals its footprint circle", failures)
	# Draw order: baseline, then rank, then stable id.
	var ordered_ids: Array[String] = []
	for entry: Dictionary in frame.entries:
		ordered_ids.append(String(entry["stable_id"]))
	var expected_ids: Array[String] = ["scout", "hero", "grunt", "pillar"]
	_expect(ordered_ids == expected_ids, "frame entries are not in baseline/rank order: %s" % [ordered_ids], failures)
	# Multi-actor foreground occlusion through the detached plan.
	var plan: Dictionary = port.latest_occlusion_plan()
	_expect(bool(plan.get("ok", false)), "projected frame produced no occlusion plan", failures)
	if not bool(plan.get("ok", false)):
		return
	var occlusion_plan = plan["value"]
	var hero_report: Dictionary = occlusion_plan.occlusion_report("hero")
	var grunt_report: Dictionary = occlusion_plan.occlusion_report("grunt")
	var scout_report: Dictionary = occlusion_plan.occlusion_report("scout")
	_expect(bool(hero_report.get("occluded", false)) and (hero_report.get("occluder_ids", []) as Array) == ["pillar"], "hero occluders wrong: %s" % [hero_report.get("occluder_ids", [])], failures)
	_expect(bool(grunt_report.get("occluded", false)) and (grunt_report.get("occluder_ids", []) as Array) == ["pillar"], "grunt occluders wrong: %s" % [grunt_report.get("occluder_ids", [])], failures)
	_expect(not bool(scout_report.get("occluded", true)) and float(scout_report.get("cover_fraction", 1.0)) == 0.0, "scout reported occluded", failures)
	_expect(float(hero_report.get("cover_fraction", 0.0)) > 0.0 and float(grunt_report.get("cover_fraction", 0.0)) > 0.0, "occlusion coverage lost", failures)
	# Alpha targets: covered actors dim toward their tiered cover target (full
	# coverage sinks to the occluded target, partial coverage interpolates),
	# the clear actor stays at full alpha.
	var controller = ControllerScript.new()
	_expect(bool(controller.adopt_plan(occlusion_plan).get("ok", false)), "controller rejected the projected plan", failures)
	for cover: Array in [["hero", hero_report], ["grunt", grunt_report], ["scout", scout_report]]:
		var set_result: Dictionary = controller.set_cover(String(cover[0]), float((cover[1] as Dictionary)["cover_fraction"]))
		_expect(bool(set_result.get("ok", false)), "cover update rejected an id from the report", failures)
	controller.update(0.5)
	_expect(is_equal_approx(controller.alpha("hero"), ControllerScript.OCCLUDED_TARGET_ALPHA), "hero alpha target is not the occluded target", failures)
	var grunt_cover := float(grunt_report.get("cover_fraction", 0.0))
	var grunt_tier_ratio := clampf((grunt_cover - ControllerScript.COVER_GRAZE_THRESHOLD) / (ControllerScript.COVER_FULL_THRESHOLD - ControllerScript.COVER_GRAZE_THRESHOLD), 0.0, 1.0)
	var grunt_tier_target := lerpf(1.0, ControllerScript.OCCLUDED_TARGET_ALPHA, grunt_tier_ratio)
	_expect(is_equal_approx(controller.alpha("grunt"), grunt_tier_target), "grunt alpha target is not its tiered cover target", failures)
	_expect(is_equal_approx(controller.alpha("scout"), ControllerScript.CLEAR_TARGET_ALPHA), "scout alpha target is not clear", failures)


func _test_missing_actor_binding_fails_closed_then_recovers() -> void:
	var port = RoomPresentationPortScript.new()
	var fixture := _make_world(port)
	var access = fixture["access"]
	_register_actors(access)
	access.register_actor("unbound", Vector2(30.0, 90.0), 6.0)
	var seam := _bind_seam(port, access)
	var stepped = fixture["world"].step_tick()
	_expect(bool(stepped.ok), "kernel tick failed in fail-closed scenario", failures)
	_expect(port.latest_frame == null, "missing binding still produced a frame", failures)
	var errors: Array[String] = port.last_projection_errors
	_expect(errors.has("missing_presentation_binding:unbound"), "projection did not name the unbound actor: %s" % [errors], failures)
	var plan: Dictionary = port.latest_occlusion_plan()
	_expect(not bool(plan.get("ok", false)) and (plan.get("errors", []) as Array).has("missing_presentation_binding:unbound"), "occlusion plan succeeded without a full frame", failures)
	# Binding the missing visual recovers the seam on the next tick.
	var late_binding: Dictionary = BindingScript.for_actor("unbound", "unbound.body", 1, Rect2(-12.0, -40.0, 24.0, 40.0))
	_expect(bool(late_binding.get("ok", false)), "late binding rejected", failures)
	var projector = seam["projector"]
	_expect(bool(projector.bind_actor_visual(late_binding.get("value")).get("ok", false)), "projector rejected the late binding", failures)
	var recovered = fixture["world"].step_tick()
	_expect(bool(recovered.ok), "kernel tick failed after recovery", failures)
	_expect(port.latest_frame != null and _entry(port, "unbound").has("art_box"), "seam did not recover after binding the missing visual", failures)


func _test_projector_verifies_snapshot_rows() -> void:
	var port = RoomPresentationPortScript.new()
	var fixture := _make_world(port)
	var access = fixture["access"]
	_register_actors(access)
	var seam := _bind_seam(port, access)
	var projector = seam["projector"]
	var access_snapshot: Dictionary = access.actor_snapshot("hero")
	var stable_key := int(access_snapshot["stable_key"])
	# Correct row format copied from SimEntityStore.snapshot_rows():
	# [stable_key, slot_index, generation, alive, room_instance_id, world_revision, payload].
	var good_row := [
		stable_key, 0, int(access_snapshot["entity_handle"].generation), 1,
		ROOM_ID, REVISION,
		[HERO_FEET.x, HERO_FEET.y, HERO_FEET.x, HERO_FEET.y, 0.0, 0.0, 0.0, 1.0, 6.0, 1, -1, []],
	]
	var all_rows: Array = []
	for actor_id: String in access.actor_ids():
		var row_actor: Dictionary = access.actor_snapshot(actor_id)
		var row_feet: Vector2 = row_actor["feet_position"]
		all_rows.append([
			int(row_actor["stable_key"]), 0, int((row_actor["entity_handle"] as Object).get("generation")), 1,
			ROOM_ID, REVISION,
			[row_feet.x, row_feet.y, row_feet.x, row_feet.y, 0.0, 0.0, 0.0, 1.0, 6.0, 1, -1, []],
		])
	var missing_row_snapshot := SnapshotScript.new()
	missing_row_snapshot.tick = 1
	missing_row_snapshot.tick_rate = TICK_RATE
	missing_row_snapshot.room_instance_id = ROOM_ID
	missing_row_snapshot.world_revision = REVISION
	missing_row_snapshot.rows = []
	var missing_result: Dictionary = projector.project(missing_row_snapshot)
	_expect(not bool(missing_result.get("ok", false)) and (missing_result.get("errors", []) as Array).has("actor_missing_from_snapshot:hero"), "projector accepted an actor absent from snapshot rows", failures)
	var dead_row_snapshot := _snapshot_copy(missing_row_snapshot)
	var dead_row := good_row.duplicate()
	dead_row[3] = 0
	dead_row_snapshot.rows = [dead_row]
	var dead_result: Dictionary = projector.project(dead_row_snapshot)
	_expect(not bool(dead_result.get("ok", false)) and (dead_result.get("errors", []) as Array).has("actor_not_alive_in_snapshot:hero"), "projector accepted a dead row", failures)
	var mismatch_row_snapshot := _snapshot_copy(missing_row_snapshot)
	var moved_row := good_row.duplicate()
	moved_row[6][0] = 123.0
	mismatch_row_snapshot.rows = [moved_row]
	var mismatch_result: Dictionary = projector.project(mismatch_row_snapshot)
	_expect(not bool(mismatch_result.get("ok", false)) and (mismatch_result.get("errors", []) as Array).has("snapshot_feet_mismatch:hero"), "projector accepted mismatched row feet", failures)
	var stale_revision_snapshot := _snapshot_copy(missing_row_snapshot)
	stale_revision_snapshot.rows = all_rows
	stale_revision_snapshot.world_revision = REVISION + 1
	var stale_result: Dictionary = projector.project(stale_revision_snapshot)
	_expect(not bool(stale_result.get("ok", false)) and (stale_result.get("errors", []) as Array).has("presentation_revision_mismatch"), "projector accepted a stale world revision", failures)
	var ok_snapshot := _snapshot_copy(missing_row_snapshot)
	ok_snapshot.rows = all_rows
	var ok_result: Dictionary = projector.project(ok_snapshot)
	_expect(bool(ok_result.get("ok", false)), "projector rejected a matching snapshot", failures)


func _snapshot_copy(source: SimSnapshot) -> SimSnapshot:
	var copy := SnapshotScript.new()
	copy.tick = source.tick
	copy.tick_rate = source.tick_rate
	copy.room_instance_id = source.room_instance_id
	copy.world_revision = source.world_revision
	copy.next_stable_key = source.next_stable_key
	copy.rows = source.rows.duplicate(true)
	copy.phase_trace = source.phase_trace.duplicate()
	return copy


func _test_presentation_churn_never_writes_simulation() -> void:
	var port_a = RoomPresentationPortScript.new()
	var port_b = RoomPresentationPortScript.new()
	var world_a := _make_world(port_a)
	var world_b := _make_world(port_b)
	_register_actors(world_a["access"])
	_register_actors(world_b["access"])
	_bind_seam(port_a, world_a["access"])
	var controller = ControllerScript.new()
	for tick_index in 3:
		var stepped_a = world_a["world"].step_tick()
		var stepped_b = world_b["world"].step_tick()
		_expect(bool(stepped_a.ok) and bool(stepped_b.ok), "kernel tick failed in detachment scenario", failures)
		var hash_a: String = world_a["world"].latest_snapshot().sha256_hex()
		var hash_b: String = world_b["world"].latest_snapshot().sha256_hex()
		_expect(hash_a == hash_b, "identical worlds diverged before presentation churn", failures)
		# Heavy presentation-side churn on world A only.
		if port_a.latest_frame != null:
			var plan: Dictionary = port_a.latest_occlusion_plan()
			if bool(plan.get("ok", false)):
				if tick_index == 0:
					controller.adopt_plan(plan["value"])
				for stable_id: String in controller.tracked_ids():
					controller.set_subject_anchor(stable_id, Vector2(123.0, 45.0))
					controller.set_cover(stable_id, 0.9)
				controller.update(0.25)
				controller.update(0.25)
		_expect(world_a["world"].latest_snapshot().sha256_hex() == hash_a, "presentation churn mutated the adopted snapshot hash", failures)
	# The authoritative hashes still match after churn.
	var final_a: String = world_a["world"].latest_snapshot().sha256_hex()
	var final_b: String = world_b["world"].latest_snapshot().sha256_hex()
	_expect(final_a == final_b, "presentation churn wrote simulation state", failures)


func _expect(condition: bool, message: String, failures_list: Array[String]) -> void:
	if not condition:
		failures_list.append(message)
