extends SceneTree

const Catalog := preload("res://src/runtime/world/room_catalog.gd")
const Runtime := preload("res://src/runtime/world/scene_runtime.gd")
const Definition := preload("res://src/runtime/world/room_definition.gd")
const Asset := preload("res://src/runtime/world/world_asset.gd")
const Geometry := preload("res://src/core/geometry/arena_geometry.gd")
const Content := preload("res://src/content/content_registry.gd")
const Build := preload("res://src/systems/proxy_build.gd")
const Decision := preload("res://src/systems/proxy_decision.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var entry: Dictionary = Catalog.new().resolve({"layout_id": "river_crossing"})
	var runtime = Runtime.new()
	root.add_child(runtime)
	var definition = Definition.new({"room_id": "navigation.test", "world_asset_id": "combat/river_crossing", "encounter_id": "encounter.none", "ruleset_id": "rules.default", "tags": ["test"]})
	var asset = Asset.new(entry.world_scene_path, entry.manifest_path, entry.gameplay_digest, entry.presentation_digest, 1)
	var mounted: Dictionary = runtime.mount(definition, asset, null, null, 0, 30)
	if not mounted.ok:
		_fail("mount failed: %s" % str(mounted))
		return
	var registry := Content.new()
	if not registry.load_all().is_empty():
		_fail("content failed to load")
		return
	var compiled: Dictionary = Build.compile({"cores": ["near_enemy_horizon", "direct_gait", "single_key_execution", "short_trace_memory"]}, registry.cores)
	var build: Dictionary = compiled.value
	var state := Decision.initial_state(build)
	var pos := Vector2(400, 250)
	var target := Vector2(950, 250)
	var geometry: Dictionary = Geometry.from_native_boundary_for_footprint(runtime.movement_boundary, runtime.authored_arena_rect, 14.0)
	var blockers: Array = []
	for blocker: Dictionary in runtime.actor_registry.static_blocker_bounds():
		blockers.append({"points": blocker.points} if blocker.has("points") else {"center": blocker.center, "radius": blocker.radius})
	if not runtime.register_actor("ranger", pos, 14.0).ok:
		_fail("spawn failed")
		return
	var sequence := 0
	var crossed := false
	var cast := false
	for tick in 1200:
		var snapshot := {"snapshot_version": 3, "tick": tick, "actor_id": "ranger", "player_position": pos, "facing": Vector2.RIGHT, "action_state": "idle", "attack_ready_tick": 0, "targeting_distance": 90.0, "visible_enemies": [{"entity_id": 1, "position": target, "health": 100.0, "targetable": true}], "walkable_geometry": geometry, "static_blockers": blockers}
		var result := Decision.decide(snapshot, build, state, sequence)
		if not result.ok:
			_fail("decision failed: %s" % result.error)
			return
		if result != Decision.decide(snapshot.duplicate(true), build, state.duplicate(true), sequence):
			_fail("decision is not deterministic")
			return
		state = result.next_state
		sequence = result.next_sequence
		for command: Dictionary in result.commands:
			if command.kind == "move":
				var direction := Vector2(command.direction_x_milli, command.direction_y_milli).normalized()
				var moved: Dictionary = runtime.move_actor("ranger", direction * 4.0, tick)
				pos = moved.position
			elif command.kind == "cast":
				cast = true
		crossed = crossed or pos.x > 820.0
		if cast:
			break
	if not crossed or not cast:
		_fail("stationary target across river was not reached: position=%s crossed=%s cast=%s" % [str(pos), crossed, cast])
		return
	runtime.unmount()
	runtime.queue_free()
	print("PASS test_proxy_terrain_navigation.gd")
	quit(0)

func _fail(message: String) -> void:
	printerr("FAIL test_proxy_terrain_navigation.gd: ", message)
	quit(1)
