class_name ActorState
extends RefCounted

## Mutable simulation state for one logical actor.
##
## EntityDefinition describes what an actor is. ActorState is the per-room
## instance that can be snapshotted, advanced by the single motor authority,
## and discarded when the room revision changes.

const SCHEMA_VERSION := 1

var entity_id := ""
var part_ids: Array[String] = []
var feet_position := Vector2.ZERO
var previous_feet_position := Vector2.ZERO
var velocity := Vector2.ZERO
var footprint_radius := 0.0
var facing := Vector2.DOWN
var alive := true
var room_instance_id := ""
var world_revision := 0
var last_motor_tick := -1


static func create(
	stable_id: String,
	start_position: Vector2,
	radius: float,
	instance_id: String,
	revision: int = 0,
	initial_facing: Vector2 = Vector2.DOWN
) -> Dictionary:
	var id := stable_id.strip_edges()
	if id.is_empty() or not start_position.is_finite() or not is_finite(radius) or radius <= 0.0:
		return _failure("invalid_actor_state")
	if instance_id.strip_edges().is_empty() or revision < 0:
		return _failure("invalid_actor_version")
	var state := ActorState.new()
	state.entity_id = id
	state.feet_position = start_position
	state.previous_feet_position = start_position
	state.footprint_radius = radius
	state.room_instance_id = instance_id
	state.world_revision = revision
	if initial_facing.is_finite() and initial_facing.length_squared() > 0.000001:
		state.facing = initial_facing.normalized()
	return {"ok": true, "error": "", "value": state}


func apply_motor_result(result: Dictionary, tick: int) -> Dictionary:
	if not _same_version(result) or tick < 0:
		return {"ok": false, "error": "stale_actor_result"}
	var position: Variant = result.get("position", null)
	if not position is Vector2 or not (position as Vector2).is_finite():
		return {"ok": false, "error": "invalid_motor_position"}
	var displacement := (position as Vector2) - feet_position
	previous_feet_position = feet_position
	feet_position = position as Vector2
	velocity = displacement
	last_motor_tick = tick
	var direction: Variant = result.get("facing", null)
	if direction is Vector2 and (direction as Vector2).is_finite() and (direction as Vector2).length_squared() > 0.000001:
		facing = (direction as Vector2).normalized()
	return {"ok": true, "error": "", "displacement": displacement}


func mark_dead() -> void:
	alive = false
	velocity = Vector2.ZERO


func snapshot() -> Dictionary:
	var sorted_parts := part_ids.duplicate()
	sorted_parts.sort()
	return {
		"schema_version": SCHEMA_VERSION,
		"entity_id": entity_id,
		"part_ids": sorted_parts,
		"feet_position": feet_position,
		"previous_feet_position": previous_feet_position,
		"velocity": velocity,
		"footprint_radius": footprint_radius,
		"facing": facing,
		"alive": alive,
		"room_instance_id": room_instance_id,
		"world_revision": world_revision,
		"last_motor_tick": last_motor_tick,
	}


func _same_version(result: Dictionary) -> bool:
	return String(result.get("room_instance_id", "")) == room_instance_id \
		and int(result.get("world_revision", -1)) == world_revision


static func _failure(error: String) -> Dictionary:
	return {"ok": false, "error": error, "value": null}

