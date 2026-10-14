class_name ActorRegistry
extends RefCounted

## Room-scoped actor instances and the single movement authority.
##
## The registry owns mutable ActorState objects. Static blockers are registered
## once on the shared ActorMotor query; each move sets the active footprint
## radius, resolves exactly one displacement, and commits the result to the
## actor state. No caller may write an actor position directly through this
## boundary.

const ActorMotorScript := preload("res://src/runtime/geometry/actor_motor.gd")
const ActorStateScript := preload("res://src/runtime/world/actor_state.gd")

var room_instance_id := ""
var world_revision := 0
var _motor
var _actors: Dictionary = {}


func configure(instance_id: String, revision: int = 0, default_radius: float = 0.0) -> Dictionary:
	if instance_id.strip_edges().is_empty() or revision < 0 or not is_finite(default_radius) or default_radius < 0.0:
		return {"ok": false, "error": "invalid_actor_registry_configuration"}
	room_instance_id = instance_id.strip_edges()
	world_revision = revision
	_motor = ActorMotorScript.new(default_radius)
	_actors.clear()
	return {"ok": true, "error": ""}


## Content loaders use these methods to rebuild the room's static geometry. They
## never clear actor state; the room lifecycle owns actor registration.
func clear_geometry() -> void:
	if _motor != null:
		_motor.clear_geometry()


func reset_actors() -> bool:
	## Room waves reuse one SceneRuntime instance, but actor identities and motor
	## ticks belong to the new wave. Clearing only instance state preserves the
	## runtime's room/version identity and never mutates authored geometry.
	_actors.clear()
	return true


func set_geometry_radius(value: float) -> bool:
	if _motor == null or not is_finite(value) or value < 0.0:
		return false
	return bool(_motor.set_geometry_radius(value))


func set_boundary(boundary: Variant) -> bool:
	if _motor == null:
		return false
	return _motor.set_boundary(boundary)


func has_movement_boundary() -> bool:
	return _motor != null and not _motor.movement_boundary.is_empty()


func movement_boundary_snapshot() -> Dictionary:
	if _motor == null:
		return {}
	return _motor.movement_boundary.duplicate(true)


func register_rect(blocker_id: String, rect: Rect2) -> bool:
	if _motor == null:
		return false
	return _motor.register_rect(blocker_id, rect)


func register_circle(blocker_id: String, center: Vector2, radius: float) -> bool:
	if _motor == null:
		return false
	return _motor.register_circle(blocker_id, center, radius)


func register_polygon(blocker_id: String, points: PackedVector2Array) -> bool:
	if _motor == null:
		return false
	return _motor.register_polygon(blocker_id, points)


func register_actor(actor_id: String, position: Vector2, radius: float, part_ids: Array[String] = []) -> Dictionary:
	if _motor == null:
		return {"ok": false, "error": "registry_not_configured"}
	var id := actor_id.strip_edges()
	if id.is_empty() or _actors.has(id):
		return {"ok": false, "error": "duplicate_or_empty_actor_id"}
	var created: Dictionary = ActorStateScript.create(id, position, radius, room_instance_id, world_revision)
	if not bool(created.get("ok", false)):
		return created
	var state = created.get("value", null)
	if state == null:
		return {"ok": false, "error": "actor_state_creation_failed"}
	state.part_ids = part_ids.duplicate()
	_actors[id] = state
	return {"ok": true, "error": "", "value": state}


func unregister_actor(actor_id: String) -> Dictionary:
	var id := actor_id.strip_edges()
	if not _actors.has(id):
		return {"ok": false, "error": "unknown_actor"}
	_actors.erase(id)
	return {"ok": true, "error": ""}


func is_position_clear(position: Vector2, bounds: Rect2 = Rect2(), radius: float = -1.0) -> bool:
	if _motor == null or not position.is_finite():
		return false
	var previous_radius: float = float(_motor.radius)
	if radius >= 0.0:
		_motor.set_geometry_radius(radius)
	var result: bool = bool(_motor.is_position_clear(position, bounds))
	_motor.set_geometry_radius(previous_radius)
	return result


## Explicit room-entry/travel placement. It is the only sanctioned write to an
## actor's feet position outside move_actor; it does not project to a nearby
## point and therefore keeps invalid authored placements visible to validation.
func teleport_actor(actor_id: String, position: Vector2) -> Dictionary:
	var state = _actors.get(actor_id.strip_edges(), null)
	if state == null or not position.is_finite():
		return {"ok": false, "error": "unknown_or_invalid_actor"}
	state.previous_feet_position = state.feet_position
	state.feet_position = position
	state.velocity = Vector2.ZERO
	return {"ok": true, "error": "", "position": position}


func move_actor(actor_id: String, displacement: Vector2, tick: int, bounds: Rect2 = Rect2()) -> Dictionary:
	var state = _actors.get(actor_id.strip_edges(), null)
	if state == null or _motor == null:
		return {"ok": false, "error": "unknown_or_unconfigured_actor"}
	if tick < 0 or tick <= int(state.last_motor_tick):
		return {"ok": false, "error": "non_monotonic_motor_tick"}
	_motor.set_geometry_radius(float(state.footprint_radius))
	var result: Dictionary = _motor.move(state.feet_position, displacement, bounds)
	# The shared query is the commit contract. Failed moves never touch previous
	# position, velocity, facing or last_motor_tick in ActorState.
	if not bool(result.get("ok", false)):
		return result
	var position: Variant = result.get("position", null)
	if not position is Vector2 or not _motor.is_position_clear(position, bounds):
		result["ok"] = false
		result["error"] = "invalid_motor_clearance"
		return result
	result["room_instance_id"] = room_instance_id
	result["world_revision"] = world_revision
	result["tick"] = tick
	if displacement.length_squared() > 0.000001:
		result["facing"] = displacement.normalized()
	var applied: Dictionary = state.apply_motor_result(result, tick)
	if not bool(applied.get("ok", false)):
		return applied
	result["ok"] = true
	result["error"] = ""
	result["actor_id"] = actor_id
	result["displacement"] = applied.get("displacement", Vector2.ZERO)
	return result


func actor(actor_id: String) -> Variant:
	return _actors.get(actor_id.strip_edges(), null)


func actor_ids() -> Array[String]:
	var result: Array[String] = []
	for key: Variant in _actors.keys():
		result.append(String(key))
	result.sort()
	return result


func snapshot() -> Dictionary:
	var actors: Array[Dictionary] = []
	for id: String in actor_ids():
		actors.append((_actors[id] as RefCounted).call("snapshot"))
	return {
		"room_instance_id": room_instance_id,
		"world_revision": world_revision,
		"actor_ids": actor_ids(),
		"actors": actors,
		"blockers": _motor.snapshot() if _motor != null else [],
	}

