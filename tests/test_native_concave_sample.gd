extends SceneTree

const NativeScene := preload("res://content/rooms/samples/concave_hole_passage.tscn")
const Runtime := preload("res://src/runtime/world/scene_runtime.gd")
const Spatial := preload("res://src/runtime/world/spatial_manifest.gd")
const Arena := preload("res://src/runtime/geometry/arena_geometry.gd")
const MANIFEST_PATH := "res://content/rooms/samples/concave_hole_passage.spatial.json"
const RADIUS := 10.0
var failures: Array[String] = []
var traces: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var sha := FileAccess.get_sha256(MANIFEST_PATH)
	_test_derivative()
	_test_joint_runtime()
	_test_manifest_drift()
	_test_native_failures()
	_expect(FileAccess.get_sha256(MANIFEST_PATH) == sha, "tests changed generated manifest")
	for trace: Dictionary in traces:
		print("NATIVE_SAMPLE_TRACE ", JSON.stringify(trace, "", true, true))
	for failure: String in failures:
		printerr("FAIL: " + failure)
	if failures.is_empty():
		print("PASS test_native_concave_sample.gd native_to_manifest_to_runtime_to_registry_motor_to_unload=true")
	quit(0 if failures.is_empty() else 1)


func _definition() -> Dictionary:
	return {"room_id": "native.concave_hole_passage", "world_asset_id": "native/concave_hole_passage", "encounter_id": "geometry/probes", "ruleset_id": "geometry.samples.v1", "tags": ["native", "geometry"]}


func _asset() -> Dictionary:
	return {"world_scene_path": NativeScene.resource_path, "manifest_path": MANIFEST_PATH, "gameplay_digest": FileAccess.get_sha256(MANIFEST_PATH), "presentation_digest": FileAccess.get_sha256(NativeScene.resource_path), "schema_version": 1}


func _manifest() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))


func _test_derivative() -> void:
	var author := NativeScene.instantiate()
	var report: Dictionary = author.validate_contract()
	_expect(bool(report.ok), "current author contract invalid: " + str(report.errors))
	var derived: Dictionary = author.derive_spatial_manifest()
	_expect(Spatial.new(derived).is_valid(), "native derivative invalid")
	_expect(Spatial.new(derived).digest_input() == Spatial.new(_manifest()).digest_input(), "native and baked manifest differ")
	_expect(Spatial.new(derived).movement_bindings().size() == 9, "boundary and eight solid bindings were not derived")
	_expect(Spatial.new(derived).movement_geometry().get("type", "") == "rect", "static piece replaced canonical boundary")
	author.free()
	for invalid: Dictionary in [
		{"type": "circle", "points": [[0,0], [20,0], [0,20]]},
		{"type": "polygon", "points": [[0,0], [20,0], [0,20]], "approximate": true},
		{"type": "polygon", "points": [[0,0], [20,0], [10,5], [20,20], [0,20]]},
		{"type": "polygon", "points": [[0,0], [20,0], [20,0], [0,20]]},
		{"type": "polygon", "points": [[0,0], [true,0], [0,20]]},
	]:
		_expect(not bool(Arena.normalize_native_static_geometry(invalid).ok), "malformed or unknown static shape accepted: " + str(invalid))


func _test_joint_runtime() -> void:
	var runtime := Runtime.new()
	root.add_child(runtime)
	var ready_blocker_counts: Array[int] = []
	runtime.ready_changed.connect(func(ready: bool, report: Dictionary):
		if ready: ready_blocker_counts.append((report.actors.blockers as Array).size()))
	var loaded: Dictionary = runtime.mount(_definition(), _asset())
	_expect(bool(loaded.ok) and runtime.is_ready(), "native runtime mount failed: " + str(loaded))
	if not runtime.is_ready():
		runtime.free()
		return
	var registry = runtime.actor_registry
	var world = runtime.simulation
	_expect(ready_blocker_counts == [8], "READY preceded static registration")
	_expect(not registry.is_position_clear(Vector2(700,60), Rect2(), RADIUS), "outer notch did not make an irregular walkable region")
	_expect(registry.is_position_clear(Vector2(550,60), Rect2(), RADIUS), "legal side of outer notch blocked")
	_expect(not registry.is_position_clear(Vector2(215,315), Rect2(), RADIUS), "closed hole interior was walkable")
	_expect(not registry.is_position_clear(Vector2(175,315), Rect2(), RADIUS), "center outside hole hid footprint overlap")
	_expect(registry.is_position_clear(Vector2(415,230), Rect2(), RADIUS), "exact diameter opening rejected a tangent footprint")
	_expect(not registry.is_position_clear(Vector2(415,230), Rect2(), RADIUS + 0.01), "critical opening accepted oversized footprint")
	_expect(not registry.is_position_clear(Vector2(415,230.01), Rect2(), RADIUS), "critical opening ignored off-center overlap")
	var registered: Dictionary = runtime.register_actor("survey/ranger", _socket(runtime, "Spawn"), RADIUS)
	_expect(bool(registered.ok), "authored spawn failed registration")
	var view := Node2D.new()
	view.name = "SurveyRanger"
	_expect(bool(runtime.presenter.register_actor_view("survey/ranger", view).ok), "shared presenter actor registration failed")
	_place(runtime, "HoleApproach")
	var hole := _move(runtime, Vector2(180,0), "cross_hole")
	_expect(bool(hole.blocked) and _near(hole.position.x,170) and _has_contact(hole, "solid/Hole"), "cross-hole sweep did not stop on solid island")
	_place(runtime, "SlideApproach")
	var slide := _move(runtime, Vector2(60,20), "island_slide")
	_expect(bool(slide.blocked) and _near(slide.position.x,170) and slide.position.y > 325, "oblique island contact lost tangent slide")
	var reverse := _move(runtime, Vector2(-30,0), "island_reverse")
	_expect(reverse.position.x < slide.position.x and not bool(reverse.blocked), "island reverse could not escape contact")
	_place(runtime, "CornerApproach")
	var corner := _move(runtime, Vector2(-80,-80), "inside_corner")
	_expect(bool(corner.blocked) and _near(corner.position.x,630) and _near(corner.position.y,410), "inside corner did not settle on both walls")
	for index: int in 8:
		var held := _move(runtime, Vector2(-8,-8), "corner_hold")
		_expect(held.position.distance_to(corner.position) < 0.002, "corner drifted on repeated inward ticks")
	var escaped := _move(runtime, Vector2(30,30), "corner_reverse")
	_expect(escaped.position.x > corner.position.x and escaped.position.y > corner.position.y, "inside corner reverse escape failed")
	_place(runtime, "NarrowApproach")
	var narrow := _move(runtime, Vector2(110,0), "gap_19_5")
	_expect(bool(narrow.blocked) and narrow.position.x < 400, "slightly narrow opening admitted diameter-20 footprint")
	var backed := _move(runtime, Vector2(-30,0), "narrow_reverse")
	_expect(backed.position.x < narrow.position.x, "narrow doorway reverse failed")
	_place(runtime, "CriticalApproach")
	var critical := _move(runtime, Vector2(110,0), "gap_20")
	_expect(_near(critical.position.x,470) and _near(critical.position.y,230), "exact diameter opening could not be traversed")
	_place(runtime, "WideApproach")
	var wide := _move(runtime, Vector2(110,0), "gap_22")
	_expect(_near(wide.position.x,470) and _near(wide.position.y,351), "wide opening could not be traversed")
	var wide_back := _move(runtime, Vector2(-110,0), "wide_reverse")
	_expect(_near(wide_back.position.x,360), "wide opening reverse traverse failed")
	var instance_id := runtime.room_instance_id
	var revision := runtime.world_revision
	var unmounted: Dictionary = runtime.unmount()
	_expect(bool(unmounted.ok) and not runtime.is_ready() and runtime.mounted_scene == null, "unmount left native room ready")
	_expect(registry.actor_ids().is_empty() and registry.snapshot().blockers.is_empty() and not registry.has_movement_boundary(), "unmount left registrations on retained registry")
	_expect(runtime.actor_registry.snapshot().blockers.is_empty() and runtime.presenter.actor_ids().is_empty(), "unmount left current geometry/visual registrations")
	_expect(runtime.presenter.native_binding_node("island.visual") == null, "unmount retained native visual binding")
	_expect(runtime.move_actor("survey/ranger", Vector2.ONE, world.tick).error == "runtime_not_ready", "stale movement accepted after unload")
	_expect(not runtime.accepts_version(instance_id, revision), "unloaded identity remained accepted")
	var remount: Dictionary = runtime.mount(_definition(), _asset(), null, null, revision + 1)
	_expect(bool(remount.ok) and runtime.room_instance_id != instance_id and runtime.actor_registry != registry, "remount reused stale identity/registry")
	_expect(runtime.actor_registry.snapshot().blockers.size() == 8 and runtime.actor_registry.actor_ids().is_empty(), "remount duplicated solids or retained actors")
	runtime.unmount()
	runtime.free()


func _socket(runtime: Node, name: String) -> Vector2:
	for socket: Dictionary in runtime.manifest.snapshot().spawn_interaction_exit_sockets:
		if socket.socket_id == "socket/" + name:
			return Vector2(socket.position[0], socket.position[1])
	_expect(false, "authored socket missing: " + name)
	return Vector2.INF


func _place(runtime: Node, name: String) -> void:
	var point := _socket(runtime, name)
	_expect(runtime.actor_registry.is_position_clear(point, Rect2(), RADIUS), "authored probe footprint blocked: " + name)
	_expect(bool(runtime.actor_registry.teleport_actor("survey/ranger", point).ok), "probe placement failed")


func _move(runtime: Node, displacement: Vector2, label: String) -> Dictionary:
	var tick: int = runtime.simulation.step().tick
	var moved: Dictionary = runtime.move_actor("survey/ranger", displacement, tick)
	_expect(bool(moved.get("ok", false)), label + ": registry movement rejected")
	var actor = runtime.actor_registry.actor("survey/ranger")
	_expect(actor.feet_position == moved.position and actor.last_motor_tick == tick, label + ": position/tick bypassed registry")
	_expect(runtime.actor_registry.is_position_clear(moved.position, Rect2(), RADIUS), label + ": movement ended with footprint penetration")
	_expect(bool(runtime.presenter.sync_actor("survey/ranger", actor.feet_position).ok), label + ": committed feet did not reach presenter")
	_expect(runtime.presenter.native_group("SortRoot").get_node("SurveyRanger").position == actor.feet_position, label + ": presenter changed feet transform")
	traces.append({"probe": label, "tick": tick, "position": [moved.position.x,moved.position.y], "blocked": moved.blocked})
	return moved


func _has_contact(moved: Dictionary, id: String) -> bool:
	for contact: Dictionary in moved.contacts:
		if contact.get("blocker_id", "") == id: return true
	return false


func _test_manifest_drift() -> void:
	for field: String in Spatial.FIELDS:
		var changed := _manifest()
		match field:
			"coordinate_convention": changed[field].scale = 2.0
			"stable_bindings": changed[field][1].geometry.points[0][0] += 0.25
			"traversal_profiles": changed[field][0].radius += 0.25
			"regions_and_portals": changed[field].append({"region_id": "unexpected", "portals": []})
			"spawn_interaction_exit_sockets": changed[field][0].position[0] += 1
			"gameplay_spatial_metadata": changed[field].unapproved = true
		var runtime := Runtime.new()
		var result: Dictionary = runtime.mount(_definition(), _asset(), null, changed)
		_expect(not bool(result.ok) and result.error == "native_manifest_mismatch", "drift accepted or wrong error for " + field + ": " + str(result))
		_expect(not runtime.is_ready() and runtime.actor_registry.snapshot().blockers.is_empty(), "drift left registered geometry")
		runtime.free()


func _test_native_failures() -> void:
	for mutation: String in ["spawn_in_hole", "spawn_overlap", "concave_piece", "duplicate_id", "unknown_channels", "ancestor_transform", "missing_solid_source"]:
		var scene := NativeScene.instantiate()
		match mutation:
			"spawn_in_hole": scene.get_node("Sockets/Spawn").position = Vector2(215,315)
			"spawn_overlap": scene.get_node("Sockets/Spawn").position = Vector2(175,315)
			"concave_piece": scene.get_node("GeometrySources/Static/Hole").polygon = PackedVector2Array([Vector2(180,280),Vector2(250,280),Vector2(210,300),Vector2(250,350),Vector2(180,350)])
			"duplicate_id": scene.get_node("GeometrySources/Static/Hole").set_meta("binding_id", "solid/Notch")
			"unknown_channels": scene.get_node("GeometrySources/Static/Hole").set_meta("channels", {"movement": true, "unknown": true})
			"ancestor_transform": scene.get_node("GeometrySources/Static").position = Vector2(1,0)
			"missing_solid_source": scene.get_node("GeometrySources/Static").free()
		var contract: Dictionary = scene.validate_contract()
		_expect(not bool(contract.ok), mutation + ": invalid native source accepted")
		var packed := PackedScene.new()
		_expect(packed.pack(scene) == OK, "negative scene pack failed")
		scene.free()
		var runtime := Runtime.new()
		var result: Dictionary = runtime.mount(_definition(), _asset(), packed)
		_expect(not bool(result.ok) and result.error == "native_scene_contract_invalid", mutation + ": invalid scene mounted: " + str(result))
		_expect(not runtime.is_ready() and runtime.actor_registry.snapshot().blockers.is_empty(), mutation + ": invalid source left geometry")
		runtime.free()


func _near(actual: float, expected: float) -> bool:
	return absf(actual - expected) < 0.002


func _expect(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
