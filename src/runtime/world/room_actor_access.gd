class_name RoomActorAccess
extends RefCounted

## Room-scoped typed access to ActorRegistry plus the spatial commit boundary.
##
## ActorRegistry remains the identity/store authority.  This object owns the
## room's stable actor-id to generational-handle map and routes every pose
## change through MovementResolver before committing it to the store and
## DynamicSpatialIndex.  It is a composition-root service, not a second
## gameplay authority.

const ActorRegistryScript := preload("res://src/runtime/world/actor_registry.gd")
const ActorStateScript := preload("res://src/runtime/world/actor_state.gd")
const MovementResolverScript := preload("res://src/runtime/spatial/movement_resolver.gd")
const DynamicSpatialIndexScript := preload("res://src/runtime/spatial/dynamic_spatial_index.gd")
const StaticSpatialIndexScript := preload("res://src/runtime/spatial/static_spatial_index.gd")
const SpatialChannelsScript := preload("res://src/runtime/spatial/spatial_channels.gd")
const SimEntityHandleScript := preload("res://src/runtime/simulation/sim_entity_handle.gd")
const RoomMovementPolicyPortScript := preload("res://src/runtime/world/room_movement_policy_port.gd")
const CoreResult := preload("res://src/core/result.gd")

var simulation: SimulationWorld = null
var registry: ActorRegistry = null
var static_index: StaticSpatialIndex = null
var dynamic_index: DynamicSpatialIndex = null
var movement_resolver: MovementResolver = null
var overlay: SpatialOverlay = null
var room_instance_id := ""
var world_revision := -1

var _handles: Dictionary = {}
var _body_generations: Dictionary = {}
var _body_channels: Dictionary = {}
## Optional room-scoped movement policy seam: when a move request arrives
## without an explicit policy, the resolver may supply one for this actor.
## An invalid resolver or a null return keeps the default collision policy.
var movement_policy_port: RoomMovementPolicyPort = null


func configure(
	world: SimulationWorld,
	actors: ActorRegistry,
	static_value: StaticSpatialIndex,
	dynamic_value: DynamicSpatialIndex,
	movement_value: MovementResolver,
	overlay_value: SpatialOverlay = null
) -> Dictionary:
	if world == null or actors == null or static_value == null or dynamic_value == null or movement_value == null:
		return CoreResult.failure("room_actor_access_dependencies_unavailable")
	if not static_value.is_valid():
		return CoreResult.failure("room_actor_access_static_index_invalid")
	if world.kernel == null or not world.kernel.is_configured() or world.actor_registry != actors:
		return CoreResult.failure("room_actor_access_world_registry_mismatch")
	simulation = world
	registry = actors
	static_index = static_value
	dynamic_index = dynamic_value
	movement_resolver = movement_value
	overlay = overlay_value
	room_instance_id = world.kernel.room_instance_id
	world_revision = world.kernel.world_revision
	_handles.clear()
	_body_generations.clear()
	_body_channels.clear()
	movement_policy_port = null
	return {"ok": true, "error": ""}


func actor(actor_id: String) -> ActorState:
	var handle: SimEntityHandle = _handles.get(actor_id, null)
	if handle == null or registry == null:
		return null
	var resolved: SimOutcome = registry.resolve(handle)
	return resolved.value if resolved.ok and resolved.value is ActorStateScript else null


func actor_handle(actor_id: String) -> SimEntityHandle:
	return _handles.get(actor_id, null)


## Validates a handle at the room boundary before a spatial producer can use
## it as an attack source.  A handle with the same slot and generation from a
## previous room instance is still a valid value, but it is not valid for this
## access object and must fail closed.
func accepts_handle(handle: SimEntityHandle) -> bool:
	return (
		handle != null
		and registry != null
		and handle.matches_scope(registry.store_id(), room_instance_id, world_revision)
		and registry.is_live(handle)
	)


func has_actor(actor_id: String) -> bool:
	var handle: SimEntityHandle = _handles.get(actor_id, null)
	return handle != null and registry != null and registry.is_live(handle)


func actor_ids() -> Array[String]:
	var result: Array[String] = []
	for key: Variant in _handles.keys():
		if has_actor(String(key)):
			result.append(String(key))
	result.sort()
	return result


func actor_id_for_handle(handle: SimEntityHandle) -> String:
	if handle == null:
		return ""
	for actor_id: String in _handles.keys():
		if _handles[actor_id] == handle:
			return actor_id
	return ""


## Stable combat identity for this room. It is derived from the kernel-issued
## key and never from a mutable actor id or a SceneTree path.
func entity_key_for_handle(handle: SimEntityHandle) -> String:
	if handle == null or registry == null:
		return ""
	var resolved: SimOutcome = registry.resolve(handle)
	if not resolved.ok or not resolved.value is ActorStateScript:
		return ""
	return "actor/%d" % int((resolved.value as ActorState).stable_key)


func actor_snapshot(actor_id: String) -> Dictionary:
	var state := actor(actor_id)
	if state == null:
		return {}
	return {
		"actor_id": actor_id,
		"stable_key": state.stable_key,
		"entity_handle": state.handle,
		"feet_position": state.feet_position,
		"previous_feet_position": state.previous_feet_position,
		"velocity": state.velocity,
		"facing": state.facing,
		"footprint_radius": state.footprint_radius,
		"alive": state.alive,
		"hit_points": state.hit_points,
		"health": state.health,
		"maximum_health": state.maximum_health,
		"resistances": state.resistances.duplicate(true),
		"archetype_id": state.archetype_id,
		"spawn_key": state.spawn_key,
		"loot_tags": state.loot_tags.duplicate(),
		"active": dynamic_index != null and dynamic_index.is_active(actor_id),
		"last_movement_tick": state.last_movement_tick,
		# Existing player motion consumers use this semantic name; it is the
		# same committed tick, never a second clock.
		"last_motor_tick": state.last_movement_tick,
		"room_instance_id": state.room_instance_id,
		"world_revision": state.world_revision,
	}


func register_actor(
	actor_id: String,
	position: Vector2,
	radius: float,
	initial_hit_points: int = 1,
	collision_class: StringName = &"soft",
	channels: Array = [SpatialChannelsScript.MOVEMENT, SpatialChannelsScript.HURTBOX],
	part_ids: PackedStringArray = PackedStringArray(),
	initial_maximum_health: float = -1.0,
	initial_resistances: Dictionary = {},
	archetype_id: String = "",
	spawn_key: String = "",
	loot_tags: Array[String] = []
) -> Dictionary:
	var normalized_id := actor_id.strip_edges()
	if normalized_id.is_empty() or _handles.has(normalized_id):
		return CoreResult.failure("invalid_or_duplicate_actor_id")
	if not position.is_finite() or not is_finite(radius) or radius <= 0.0:
		return CoreResult.failure("invalid_actor_geometry")
	if not _is_clear(position, radius):
		return CoreResult.failure("actor_spawn_blocked")
	var spawned: SimOutcome = registry.spawn_actor(
		position,
		radius,
		room_instance_id,
		world_revision,
		Vector2.DOWN,
		initial_hit_points,
		part_ids,
		initial_maximum_health,
		initial_resistances,
		archetype_id,
		spawn_key,
		loot_tags
	)
	if not spawned.ok:
		return CoreResult.failure(String(spawned.error))
	var handle: SimEntityHandle = spawned.handle
	_handles[normalized_id] = handle
	_body_generations[normalized_id] = handle.generation
	_body_channels[normalized_id] = channels.duplicate()
	var body_result := dynamic_index.register_body({
		"entity_id": normalized_id,
		"generation": handle.generation,
		"position": position,
		"radius": radius,
		"channels": channels,
		"collision_class": collision_class,
		"faction": "",
	})
	if not bool(body_result.get("ok", false)):
		_handles.erase(normalized_id)
		_body_generations.erase(normalized_id)
		_body_channels.erase(normalized_id)
		# Setup-time failure is fatal to this registration.  The store has no
		# public rollback because structural mutation is otherwise kernel-owned.
		return CoreResult.failure("dynamic_body_registration_failed:%s" % String((body_result.get("errors", []) as Array).front() if not (body_result.get("errors", []) as Array).is_empty() else "unknown"))
	return {
		"ok": true,
		"error": "",
		"actor_id": normalized_id,
		"handle": handle,
		"stable_key": spawned.stable_key,
		"position": position,
		"displacement": Vector2.ZERO,
	}


func unregister_actor(actor_id: String) -> Dictionary:
	var normalized_id := actor_id.strip_edges()
	var handle: SimEntityHandle = _handles.get(normalized_id, null)
	if handle == null:
		return CoreResult.failure("unknown_actor")
	var body_result := dynamic_index.unregister_body(normalized_id)
	if not bool(body_result.get("ok", false)):
		return CoreResult.failure("dynamic_body_unregister_failed")
	var removed := registry.resolve(handle)
	if removed.ok:
		var record: ActorState = removed.value
		record.alive = false
		registry.store().mark_tombstone(handle)
	_handles.erase(normalized_id)
	_body_generations.erase(normalized_id)
	_body_channels.erase(normalized_id)
	return {"ok": true, "error": ""}


func set_collision_class(actor_id: String, collision_class: StringName) -> Dictionary:
	if not _handles.has(actor_id) or dynamic_index == null:
		return CoreResult.failure("unknown_actor")
	var result: Dictionary = dynamic_index.set_collision_class(actor_id, collision_class)
	if not bool(result.get("ok", false)):
		var errors: Array = result.get("errors", [])
		return CoreResult.failure(String(errors.front() if not errors.is_empty() else "collision_class_update_failed"))
	return {"ok": true, "error": ""}


## Keeps the actor handle and store record alive while controlling whether the
## actor contributes to movement, vision, projectile, and hurtbox queries.
## Encounter adoption is the only production caller; the change is committed
## at the between-tick structural boundary by DynamicSpatialIndex.
func set_actor_active(actor_id: String, active: bool) -> Dictionary:
	if not _handles.has(actor_id) or dynamic_index == null or registry == null:
		return CoreResult.failure("unknown_actor")
	var handle: SimEntityHandle = _handles[actor_id]
	if not registry.is_live(handle):
		return CoreResult.failure("actor_not_live")
	var result := dynamic_index.set_active(actor_id, active)
	if not bool(result.get("ok", false)):
		var errors: Array = result.get("errors", [])
		return CoreResult.failure(String(errors.front() if not errors.is_empty() else "actor_activation_failed"))
	return {"ok": true, "error": "", "active": active}


func is_actor_active(actor_id: String) -> bool:
	return _handles.has(actor_id) and dynamic_index != null and dynamic_index.is_active(actor_id)


func set_movement_policy_port(port: RoomMovementPolicyPort) -> void:
	movement_policy_port = port


## Clears the live actor projection at a room restart boundary.  The entity
## store deliberately keeps the removed records as tombstones, so stable keys
## and generations remain monotonic across repeated room starts; only the
## room-facing id map and dynamic collision bodies are removed here.
func reset_actors() -> Dictionary:
	var removed: Array[String] = actor_ids()
	for actor_id: String in removed:
		var result := unregister_actor(actor_id)
		if not bool(result.get("ok", false)):
			return CoreResult.failure("actor_reset_failed:%s:%s" % [actor_id, String(result.get("error", "unknown"))])
	return {"ok": true, "error": "", "removed": removed}


## Removes a dead actor's dynamic collision body at the death-settlement
## boundary. The entity store still owns the tombstone until the kernel's
## structural commit, but no later query in this room may see its hurtbox.
func detach_dead_actor(handle: SimEntityHandle) -> Dictionary:
	if handle == null:
		return CoreResult.failure("invalid_entity_handle")
	for actor_id: String in _handles.keys():
		if _handles[actor_id] != handle:
			continue
		if dynamic_index != null:
			dynamic_index.unregister_body(actor_id)
		_handles.erase(actor_id)
		_body_generations.erase(actor_id)
		_body_channels.erase(actor_id)
		return {"ok": true, "error": "", "actor_id": actor_id}
	return CoreResult.failure("unknown_actor_handle")


func move_actor(actor_id: String, displacement: Vector2, committed_tick: int, movement_policy: Variant = null) -> Dictionary:
	var state := actor(actor_id)
	var handle: SimEntityHandle = _handles.get(actor_id, null)
	if state == null or handle == null:
		return _move_failure(Vector2.ZERO, "unknown_actor")
	if not is_actor_active(actor_id):
		return _move_failure(state.feet_position, "inactive_actor")
	if not displacement.is_finite() or committed_tick < 0:
		return _move_failure(state.feet_position, "invalid_movement_request")
	if movement_policy == null and movement_policy_port != null:
		movement_policy = movement_policy_port.resolve(actor_id)
	var request := {
		"start": state.feet_position,
		"displacement": displacement,
		"radius": state.footprint_radius,
		"source_id": actor_id,
		"include_boundary": true,
		"include_dynamic": true,
	}
	if movement_policy != null:
		request["policy"] = movement_policy
	var resolved := movement_resolver.move(request)
	if not bool(resolved.get("ok", false)):
		return _move_failure(state.feet_position, "movement_resolution_failed")
	var position: Vector2 = resolved.get("position", state.feet_position)
	var facing := displacement.normalized() if displacement.length_squared() > 0.000001 else Vector2.ZERO
	var committed: SimOutcome = registry.commit_movement(handle, position, committed_tick, facing)
	if not committed.ok:
		return _move_failure(state.feet_position, String(committed.error))
	var pose_result := dynamic_index.commit_pose(actor_id, position)
	if not bool(pose_result.get("ok", false)):
		return _move_failure(state.feet_position, "dynamic_pose_commit_failed")
	return {
		"ok": true,
		"error": "",
		"position": position,
		"previous_position": state.previous_feet_position,
		"displacement": position - state.previous_feet_position,
		"facing": state.facing,
		"contacts": resolved.get("contacts", []),
		"blocked": bool(resolved.get("blocked", false)),
	}


func teleport_actor(actor_id: String, position: Vector2) -> Dictionary:
	var state := actor(actor_id)
	if state == null:
		return _move_failure(Vector2.ZERO, "unknown_actor")
	if not is_actor_active(actor_id):
		return _move_failure(state.feet_position, "inactive_actor")
	if not position.is_finite() or not _is_clear(position, state.footprint_radius):
		return _move_failure(state.feet_position, "teleport_blocked")
	var previous := state.feet_position
	var teleported: SimOutcome = state.teleport(position)
	if not teleported.ok:
		return _move_failure(previous, String(teleported.error))
	var pose_result := dynamic_index.commit_pose(actor_id, position)
	if not bool(pose_result.get("ok", false)):
		return _move_failure(previous, "dynamic_pose_commit_failed")
	return {"ok": true, "error": "", "position": position, "displacement": position - previous}


func is_position_clear(position: Vector2, radius_or_bounds: Variant, optional_radius: float = -1.0) -> bool:
	var radius := optional_radius if optional_radius >= 0.0 else float(radius_or_bounds)
	return _is_clear(position, radius)


## Initial placement must also clear already registered actors. Movement and
## teleports retain their existing soft-body policy; this query is for a body
## that has not joined the registry yet.
func is_spawn_position_clear(position: Vector2, radius: float) -> bool:
	return _is_clear(position, radius) and dynamic_index != null and dynamic_index.overlaps(SpatialChannelsScript.MOVEMENT, position, radius).is_empty()


func has_movement_boundary() -> bool:
	return static_index != null and not static_index.movement_boundary().is_empty()


## Authored blockers for local steering. Keep polygon edges as well as their
## bounds: a circumscribed circle can incorrectly close a narrow legal lane.
func static_blocker_bounds() -> Array[Dictionary]:
	if static_index == null:
		return []
	var bounds: Array[Dictionary] = []
	for surface_id: String in static_index.surface_ids(SpatialChannelsScript.MOVEMENT):
		var entry: Dictionary = static_index.surface(surface_id)
		var shape: Dictionary = entry.get("shape", {}) if entry is Dictionary else {}
		if shape.is_empty():
			continue
		match String(shape.get("kind", "")):
			"circle":
				bounds.append({"id": surface_id, "center": Vector2(shape["center"]), "radius": float(shape["radius"])})
			"polygon":
				var points: PackedVector2Array = shape["points"]
				if points.size() < 3:
					continue
				var center := Vector2.ZERO
				for point: Vector2 in points:
					center += point
				center /= float(points.size())
				var radius := 0.0
				for point: Vector2 in points:
					radius = maxf(radius, center.distance_to(point))
				bounds.append({"id": surface_id, "center": center, "radius": radius, "points": points})
	return bounds


func movement_boundary_snapshot() -> Dictionary:
	return static_index.movement_boundary() if static_index != null else {}


func sync_dynamic_index() -> void:
	if dynamic_index == null:
		return
	var poses: Array[Dictionary] = []
	for actor_id: String in _handles.keys():
		var handle: SimEntityHandle = _handles[actor_id]
		if registry == null or not registry.is_live(handle):
			# A dead record remains addressable until structural commit, but its
			# body must leave the dynamic query index immediately after settlement.
			dynamic_index.unregister_body(actor_id)
			continue
		var state := actor(actor_id)
		if state != null:
			poses.append({"entity_id": actor_id, "position": state.feet_position})
	if not poses.is_empty():
		dynamic_index.commit_poses(poses)


func snapshot() -> Dictionary:
	var actors: Array[Dictionary] = []
	for actor_id: String in actor_ids():
		actors.append(actor_snapshot(actor_id))
	return {
		"room_instance_id": room_instance_id,
		"world_revision": world_revision,
		"actor_ids": actor_ids(),
		"actors": actors,
		"dynamic_index": dynamic_index.snapshot() if dynamic_index != null else {},
	}


func _is_clear(position: Vector2, radius: float) -> bool:
	if static_index == null or not position.is_finite() or not is_finite(radius) or radius < 0.0:
		return false
	if not static_index.overlaps(SpatialChannelsScript.MOVEMENT, position, radius).is_empty():
		return false
	for contact: Variant in static_index.boundary_sweep(position, Vector2.ZERO, radius):
		if (contact as SpatialContact).penetrating:
			return false
	return true


static func _move_failure(position: Vector2, error: String) -> Dictionary:
	return {"ok": false, "error": error, "position": position, "displacement": Vector2.ZERO, "contacts": []}
