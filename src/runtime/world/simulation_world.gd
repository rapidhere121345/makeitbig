class_name SimulationWorld
extends RefCounted

## Room composition root for the fixed-tick simulation kernel.
##
## One SimulationWorld binds one room instance: room identity + world revision,
## the presentation-to-tick accumulator, the typed actor store, and the four
## typed integration ports. All tick authority lives in SimKernel; this class
## only wires a room together and forwards commands.

const SimKernelScript := preload("res://src/runtime/simulation/sim_kernel.gd")
const SimSnapshotScript := preload("res://src/runtime/simulation/sim_snapshot.gd")
const SimReadViewScript := preload("res://src/runtime/simulation/sim_read_view.gd")
const SimOutcomeScript := preload("res://src/runtime/simulation/sim_outcome.gd")

var kernel: SimKernel = null
var actor_registry: ActorRegistry = null

## Read-only aliases used by room domains.  The kernel remains the sole owner
## of both values; callers cannot advance the authority clock by assigning to
## these properties.
var tick: int:
	get:
		return kernel.tick if kernel != null else 0

var tick_rate: int:
	get:
		return kernel.tick_rate if kernel != null else 0

var room_instance_id: String:
	get:
		return kernel.room_instance_id if kernel != null else ""

var world_revision: int:
	get:
		return kernel.world_revision if kernel != null else -1


func _init(
	spatial: SimSpatialPort = null,
	combat: SimCombatPort = null,
	encounter: SimEncounterPort = null,
	presentation: SimPresentationPort = null,
	existing_registry: ActorRegistry = null
) -> void:
	kernel = SimKernelScript.new()
	actor_registry = existing_registry if existing_registry != null else ActorRegistry.new()
	kernel.set_ports(spatial, combat, encounter, presentation)


func configure(instance_id: String, revision: int, tick_rate: int) -> SimOutcome:
	var registry_configured: SimOutcome = actor_registry.configure(instance_id, revision)
	if not registry_configured.ok:
		return registry_configured
	var stores: Array[SimEntityStore] = [actor_registry.store()]
	var kernel_configured: SimOutcome = kernel.configure(instance_id.strip_edges(), revision, tick_rate, stores, actor_registry.store_id())
	if not kernel_configured.ok:
		return kernel_configured
	actor_registry.attach_kernel(kernel)
	return SimOutcome.success()


func queue_command(command: SimCommand) -> SimOutcome:
	return kernel.queue_command(command)


## Converts one presentation frame into whole authority ticks.
func ticks_for_frame(frame_delta: float) -> int:
	return kernel.consume_frame(frame_delta)


## Runs one authoritative tick. Returns the tick snapshot on success.
func step_tick() -> SimOutcome:
	return kernel.step_tick()


## Runs every tick owed by one presentation frame, in order.
func advance_frame(frame_delta: float) -> Array[SimSnapshot]:
	var snapshots: Array[SimSnapshot] = []
	var owed: int = ticks_for_frame(frame_delta)
	for _tick_index in owed:
		var result: SimOutcome = step_tick()
		if not result.ok:
			break
		snapshots.append(result.value)
	return snapshots


func latest_snapshot() -> SimSnapshot:
	return kernel.latest_snapshot


func reset_clock() -> void:
	if kernel != null and kernel.clock != null:
		kernel.clock.reset()


## Detached read view of the current live state (outside-tick read).
func build_detached_view() -> SimReadView:
	return SimReadViewScript.build(kernel.tick, kernel.room_instance_id, kernel.world_revision, kernel.stores)
