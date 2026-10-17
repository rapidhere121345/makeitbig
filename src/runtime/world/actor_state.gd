class_name ActorState
extends RefCounted

## Typed actor record for the fixed-tick simulation kernel.
##
## One ActorState is one actor instance in one room-scoped entity store. The
## record owns only gameplay state: kinematics, lifecycle, and combat surface.
## Identity (handle + stable key) is assigned by the kernel through the store
## contract; room and revision stamps make stale references detectable.

const SimOutcomeScript := preload("res://src/runtime/simulation/sim_outcome.gd")

var handle: SimEntityHandle = null
var stable_key: int = 0
var feet_position := Vector2.ZERO
var previous_feet_position := Vector2.ZERO
var velocity := Vector2.ZERO
var facing := Vector2.DOWN
var footprint_radius: float = 0.0
var alive: bool = true
var hit_points: int = 0
## Combat resolution uses fractional health; hit_points remains the integer
## projection consumed by simple actor consumers.
var health: float = 0.0
var maximum_health: float = 0.0
var resistances: Dictionary = {}
var archetype_id: String = ""
var spawn_key: String = ""
var loot_tags: Array[String] = []
var part_ids: PackedStringArray = PackedStringArray()
var room_instance_id: String = ""
var world_revision: int = -1
var last_movement_tick: int = -1


static func create(
	start_position: Vector2,
	radius: float,
	instance_id: String,
	revision: int,
	initial_facing: Vector2 = Vector2.DOWN,
	initial_hit_points: int = 1,
	initial_maximum_health: float = -1.0,
	initial_resistances: Dictionary = {},
	initial_archetype_id: String = "",
	initial_spawn_key: String = "",
	initial_loot_tags: Array[String] = []
) -> ActorState:
	var record := ActorState.new()
	record.feet_position = start_position
	record.previous_feet_position = start_position
	record.footprint_radius = radius
	record.room_instance_id = instance_id.strip_edges()
	record.world_revision = revision
	record.maximum_health = maxf(0.0, initial_maximum_health if initial_maximum_health >= 0.0 else float(initial_hit_points))
	record.health = minf(record.maximum_health, maxf(0.0, float(initial_hit_points)))
	record.hit_points = ceili(record.health)
	record.resistances = initial_resistances.duplicate(true)
	record.archetype_id = initial_archetype_id.strip_edges()
	record.spawn_key = initial_spawn_key.strip_edges()
	record.loot_tags = initial_loot_tags.duplicate()
	if initial_facing.is_finite() and initial_facing.length_squared() > 0.000001:
		record.facing = initial_facing.normalized()
	return record


## Kernel record contract: identity assignment. Called by the store only.
func set_entity_identity(assigned_handle: SimEntityHandle, assigned_key: int) -> void:
	handle = assigned_handle
	stable_key = assigned_key


func get_entity_handle() -> SimEntityHandle:
	return handle


## Kernel record contract: detached read view.
func build_entity_view() -> SimEntityView:
	var view := ActorEntityView.new()
	view.fill_identity(handle, stable_key, room_instance_id, world_revision)
	view.alive = alive
	view.feet_position = feet_position
	view.previous_feet_position = previous_feet_position
	view.velocity = velocity
	view.facing = facing
	view.footprint_radius = footprint_radius
	view.hit_points = hit_points
	view.health = health
	view.maximum_health = maximum_health
	view.resistances = resistances.duplicate(true)
	view.archetype_id = archetype_id
	view.spawn_key = spawn_key
	view.loot_tags = loot_tags.duplicate()
	return view


## Kernel record contract: deterministic snapshot payload (fixed field order).
func snapshot_payload() -> Array:
	var sorted_parts := Array(part_ids)
	sorted_parts.sort()
	return [
		feet_position.x, feet_position.y,
		previous_feet_position.x, previous_feet_position.y,
		velocity.x, velocity.y,
		facing.x, facing.y,
		footprint_radius,
		hit_points,
		health,
		maximum_health,
		_sorted_resistances(),
		archetype_id,
		spawn_key,
		Array(loot_tags),
		last_movement_tick,
		sorted_parts,
	]


## Movement commit boundary. Only the spatial port (via the registry) may call
## this inside the movement phase; monotonic ticks keep commits one-per-tick.
func commit_movement(new_position: Vector2, committed_tick: int, new_facing: Vector2 = Vector2.ZERO) -> SimOutcome:
	if handle == null or not handle.is_valid():
		return SimOutcome.failure(&"unidentified_record")
	if committed_tick < 0 or committed_tick <= last_movement_tick:
		return SimOutcome.failure(&"non_monotonic_movement_tick")
	if not new_position.is_finite():
		return SimOutcome.failure(&"invalid_movement_position")
	previous_feet_position = feet_position
	feet_position = new_position
	velocity = new_position - previous_feet_position
	if new_facing.is_finite() and new_facing.length_squared() > 0.000001:
		facing = new_facing.normalized()
	last_movement_tick = committed_tick
	return SimOutcome.success()


## Out-of-band room placement used while assembling or positioning a room.
## A teleport changes the current pose immediately, but it is not a motor
## submission and therefore must not consume a fixed simulation tick.
func teleport(new_position: Vector2, new_facing: Vector2 = Vector2.ZERO) -> SimOutcome:
	if handle == null or not handle.is_valid():
		return SimOutcome.failure(&"unidentified_record")
	if not new_position.is_finite():
		return SimOutcome.failure(&"invalid_teleport_position")
	previous_feet_position = new_position
	feet_position = new_position
	velocity = Vector2.ZERO
	if new_facing.is_finite() and new_facing.length_squared() > 0.000001:
		facing = new_facing.normalized()
	return SimOutcome.success()


## Applies an already-resolved health value. DamageResolution owns the formula;
## this method only commits its detached result to the actor record.
func commit_resolved_health(resolved_health: float) -> SimOutcome:
	if not is_finite(resolved_health) or resolved_health < 0.0 or resolved_health > maximum_health + 0.000001:
		return SimOutcome.failure(&"invalid_resolved_health")
	if not alive:
		return SimOutcome.success()
	health = clampf(resolved_health, 0.0, maximum_health)
	hit_points = ceili(health)
	if health <= 0.0:
		alive = false
	return SimOutcome.success()


## Domain hook retained for simple typed test ports. It delegates to the same
## health commit boundary and never performs a damage calculation.
func apply_damage(amount: int) -> void:
	if amount <= 0 or not alive:
		return
	commit_resolved_health(maxf(0.0, health - float(amount)))


func _sorted_resistances() -> Array:
	var result: Array = []
	var keys: Array[String] = []
	for key: Variant in resistances.keys():
		keys.append(String(key))
	keys.sort()
	for key: String in keys:
		result.append([key, float(resistances[key])])
	return result


class ActorEntityView:
	extends SimEntityView

	var feet_position := Vector2.ZERO
	var previous_feet_position := Vector2.ZERO
	var velocity := Vector2.ZERO
	var facing := Vector2.DOWN
	var footprint_radius: float = 0.0
	var hit_points: int = 0
	var health: float = 0.0
	var maximum_health: float = 0.0
	var resistances: Dictionary = {}
	var archetype_id: String = ""
	var spawn_key: String = ""
	var loot_tags: Array[String] = []
