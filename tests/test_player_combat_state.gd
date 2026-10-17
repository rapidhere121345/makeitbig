extends SceneTree

const State := preload("res://src/runtime/world/player_combat_state.gd")
const World := preload("res://src/runtime/world/simulation_world.gd")
const RoomSpatialPortScript := preload("res://src/runtime/world/room_spatial_port.gd")
const RoomActorAccessScript := preload("res://src/runtime/world/room_actor_access.gd")
const StaticSpatialIndexScript := preload("res://src/runtime/spatial/static_spatial_index.gd")
const DynamicSpatialIndexScript := preload("res://src/runtime/spatial/dynamic_spatial_index.gd")
const SpatialOverlayScript := preload("res://src/runtime/spatial/spatial_overlay.gd")
const MovementResolverScript := preload("res://src/runtime/spatial/movement_resolver.gd")
const Builder := preload("res://src/game/combat_state_snapshot_builder.gd")
const Combat := preload("res://src/systems/combat_system.gd")
const Rules := preload("res://src/systems/player_combat_rules.gd")
const Stream := preload("res://src/systems/combat_event_stream.gd")
const Big := preload("res://src/core/big_value.gd")
const RoomPort := preload("res://tests/helpers/callable_combat_system_room_port.gd")

var failures: Array[String] = []

class RoomSnapshotSource:
	extends RefCounted
	var player_combat_state
	var combat_system
	var sim_tick := 0
	var position_reads := 0
	var player_position: Vector2:
		get:
			position_reads += 1
			return Vector2(-9999, -9999)
	func _walkable_geometry(_radius: float) -> Dictionary: return {}
	func _content_hash() -> String: return "fixture"


func _initialize() -> void:
	for resource_path: String in ["res://src/runtime/world/player_combat_state.gd", "res://src/systems/player_combat_rules.gd", "res://tests/test_player_combat_state.gd", "res://tests/test_player_combat_rules.gd"]:
		var uid := FileAccess.get_file_as_string(resource_path + ".uid").strip_edges()
		_expect(ResourceUID.id_to_text(ResourceUID.text_to_id(uid)) == uid, "invalid UID sidecar: " + resource_path)
	var spatial_port := RoomSpatialPortScript.new()
	var world: SimulationWorld = World.new(spatial_port)
	_expect(world.configure("player-room", 3, 30).ok, "snapshot fixture world configuration failed")
	var static_build: Dictionary = StaticSpatialIndexScript.build({
		"schema_version": StaticSpatialIndexScript.SCHEMA_VERSION,
		"asset_id": "test/player-room",
		"surfaces": [],
		"movement_boundary": {"kind": "rect", "rect": Rect2(-100.0, -100.0, 1800.0, 1100.0)},
	})
	_expect(bool(static_build.get("ok", false)), "snapshot fixture static index configuration failed")
	var dynamic_index := DynamicSpatialIndexScript.new()
	var overlay := SpatialOverlayScript.new()
	var movement_build: Dictionary = MovementResolverScript.make(static_build.get("value"), overlay, dynamic_index)
	_expect(bool(movement_build.get("ok", false)), "snapshot fixture movement resolver configuration failed")
	var access := RoomActorAccessScript.new()
	_expect(bool(access.configure(world, world.actor_registry, static_build.get("value"), dynamic_index, movement_build.get("value"), overlay).get("ok", false)), "snapshot fixture actor access configuration failed")
	spatial_port.bind(access)
	_expect(bool(access.register_actor("ranger", Vector2(10, 20), 14.0).get("ok", false)), "snapshot fixture player registration failed")
	var state := State.new()
	var build := {"final_parameters": {"max_health": 125.0, "d": 225.0}, "skills": ["piercing_arrow", "hunter_mark", "dash"], "talent_capabilities": {"nested": {"value": 5}}}
	_expect(state.reset_for_room(build, access, "ranger", world.tick).ok, "reset rejected registered player")
	var rules := Rules.new()
	var stream := Stream.new()
	_expect(rules.configure(state, world, stream).ok, "snapshot fixture Rules configuration failed")
	var combat := Combat.new()
	var combat_port := RoomPort.new()
	_expect(combat_port.configure({"player_rule_port": rules, "target_blocked": func(_target) -> bool: return false}).ok, "snapshot fixture combat room port configuration failed")
	_expect(combat.bind_room(combat_port).ok, "snapshot fixture CombatSystem configuration failed")
	_expect(combat.reset_room(Big.from_float(0.0)).ok, "snapshot fixture combat outcome reset failed")
	build.talent_capabilities.nested.value = 99
	var first := state.snapshot(world.tick)
	_expect(first.player_health == 125.0 and first.player_position == Vector2(10, 20), "reset did not use locked health and registry position")
	first.talent_capabilities.nested.value = 17
	first.timeline.active["fake"] = true
	first.equipped_skills[1] = ""
	first.locked_build.final_parameters.max_health = 999
	first.retained_arrow_damage.magnitude = 500
	first.player_position = Vector2(10000, 10000)
	var second := state.snapshot(world.tick)
	_expect(second.talent_capabilities.nested.value == 5 and second.timeline.active.is_empty(), "nested snapshot escaped into domain")
	_expect(second.equipped_skills[1] == "hunter_mark" and second.locked_build.final_parameters.max_health == 125.0, "snapshot mutated frozen build")
	_expect(second.retained_arrow_damage.is_zero(), "BigValue reference escaped snapshot")
	_expect(world.step_tick().ok, "snapshot fixture world tick failed")
	_expect(access.move_actor("ranger", Vector2(3, 4), world.tick).get("ok", false), "external room movement failed")
	_expect(state.snapshot(world.tick).player_position == Vector2(13, 24), "domain cached a stale player position")
	var room := RoomSnapshotSource.new()
	room.player_combat_state = state
	room.combat_system = combat
	room.sim_tick = world.tick
	var replay := Builder.build_runtime_state(room, "ongoing")
	_expect(room.position_reads == 0 and replay.player_x_millipixels == 13000 and replay.player_y_millipixels == 24000, "replay builder read Main position instead of domain")
	_expect(replay.player_health_milli == 125000 and replay.action_timeline == second.timeline, "replay player encoding changed")
	_expect(replay.has_all(["enemies", "projectiles", "hazards", "forge", "room_reward_snapshot", "combat_events", "manual_input", "result", "tick"]), "replay lost non-player fields")
	_expect(not state.reset_for_room({}, access, "missing", 0).ok, "missing actor accepted")
	_finish("PLAYER_COMBAT_STATE_PASS")
	if world != null and world.kernel != null:
		world.kernel.shutdown()


func _expect(condition: bool, message: String) -> void:
	if not condition: failures.append(message)


func _finish(label: String) -> void:
	for failure: String in failures: printerr("FAIL: " + failure)
	if failures.is_empty(): print(label)
	quit(0 if failures.is_empty() else 1)
