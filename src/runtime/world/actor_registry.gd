class_name ActorRegistry
extends RefCounted

## Typed room-scoped registry over the kernel actor store.
##
## This is the actor-component face of the simulation kernel: setup-time
## spawning, fail-closed resolution, and the movement commit boundary used by
## the spatial port. The registry owns no geometry; boundary resolution belongs
## to whichever SimSpatialPort the room wires in.
##
## Lifecycle rule: configure the owning SimulationWorld first; the registry
## pulls stable keys from the kernel so identities never collide and never get
## reused. Mid-tick spawning must go through SimCommand.Kind.SPAWN instead so
## structural changes stay deferred to the structural commit phase.

const ActorStateScript := preload("res://src/runtime/world/actor_state.gd")
const SimEntityStoreScript := preload("res://src/runtime/simulation/sim_entity_store.gd")
const SimOutcomeScript := preload("res://src/runtime/simulation/sim_outcome.gd")

const STORE_ID: StringName = &"actors"

var _store: SimEntityStore = null
var _kernel: SimKernel = null


func _init() -> void:
	_store = SimEntityStoreScript.new(STORE_ID, ActorStateScript)


func configure(instance_id: String, revision: int) -> SimOutcome:
	return _store.configure(instance_id, revision)


## Called by SimulationWorld.configure once the kernel accepted the room.
func attach_kernel(kernel: SimKernel) -> void:
	_kernel = kernel


func store() -> SimEntityStore:
	return _store


func store_id() -> StringName:
	return STORE_ID


## Setup-time immediate spawn (room construction, wave assembly). Legal only
## between world configuration and the first tick, or between ticks during
## explicit room maintenance.
func spawn_actor(
	start_position: Vector2,
	radius: float,
	instance_id: String,
	revision: int,
	initial_facing: Vector2 = Vector2.DOWN,
	initial_hit_points: int = 1,
	parts: PackedStringArray = PackedStringArray(),
	initial_maximum_health: float = -1.0,
	initial_resistances: Dictionary = {},
	archetype_id: String = "",
	spawn_key: String = "",
	loot_tags: Array[String] = []
) -> SimOutcome:
	if _kernel == null or not _kernel.is_configured():
		return SimOutcome.failure(&"kernel_not_configured")
	if instance_id.strip_edges() != _store.room_instance_id or revision != _store.world_revision:
		return SimOutcome.failure(&"stale_room_reference")
	if not start_position.is_finite() or not is_finite(radius) or radius <= 0.0:
		return SimOutcome.failure(&"invalid_actor_setup")
	var record := ActorStateScript.create(
		start_position,
		radius,
		instance_id,
		revision,
		initial_facing,
		initial_hit_points,
		initial_maximum_health,
		initial_resistances,
		archetype_id,
		spawn_key,
		loot_tags
	)
	record.part_ids = parts.duplicate()
	return _store.spawn(record, _kernel.allocate_stable_key())


func resolve(handle: SimEntityHandle) -> SimOutcome:
	return _store.resolve(handle)


func is_live(handle: SimEntityHandle) -> bool:
	return _store.is_live(handle)


## Movement commit boundary for the spatial port. Validates the record against
## the current room identity before the record accepts the position.
func commit_movement(handle: SimEntityHandle, new_position: Vector2, committed_tick: int, new_facing: Vector2 = Vector2.ZERO) -> SimOutcome:
	var resolved: SimOutcome = _store.resolve(handle)
	if not resolved.ok:
		return resolved
	var record: ActorState = resolved.value
	if record.room_instance_id != _store.room_instance_id or record.world_revision != _store.world_revision:
		return SimOutcome.failure(&"stale_room_reference")
	return record.commit_movement(new_position, committed_tick, new_facing)


func actors_sorted_by_key() -> Array[ActorState]:
	var records: Array[ActorState] = []
	for slot in _store.live_slots_sorted_by_key():
		records.append(slot.record)
	return records


func live_count() -> int:
	return _store.live_count()
