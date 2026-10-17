class_name SimKernel
extends RefCounted

## Fixed-tick simulation kernel and entity lifecycle authority.
##
## The kernel owns: typed room-scoped stores, the five typed buffers, the
## never-reused stable-key counter, generational slot lifecycle, and execution
## of the fixed phase pipeline. It never knows damage formulas, geometry, or
## render nodes; domain behavior enters only through the four typed ports.
##
## Determinism rules enforced here:
##   - gameplay iteration is always by ascending stable key
##   - structural changes commit in enqueue order at tick end
##   - dead entities tombstone before their storage is reclaimed
##   - stale room/revision/handle references fail closed

const FixedTickClockScript := preload("res://src/core/fixed_tick_clock.gd")
const SimCommandBufferScript := preload("res://src/runtime/simulation/sim_command_buffer.gd")
const SimIntentBufferScript := preload("res://src/runtime/simulation/sim_intent_buffer.gd")
const SimHitBufferScript := preload("res://src/runtime/simulation/sim_hit_buffer.gd")
const SimStatusBufferScript := preload("res://src/runtime/simulation/sim_status_buffer.gd")
const SimStructuralChangeBufferScript := preload("res://src/runtime/simulation/sim_structural_change_buffer.gd")
const SimStructuralChangeScript := preload("res://src/runtime/simulation/sim_structural_change.gd")
const SimReadViewScript := preload("res://src/runtime/simulation/sim_read_view.gd")
const SimTickContextScript := preload("res://src/runtime/simulation/sim_tick_context.gd")
const SimTickPipelineScript := preload("res://src/runtime/simulation/sim_tick_pipeline.gd")
const SimSnapshotScript := preload("res://src/runtime/simulation/sim_snapshot.gd")
const SimOutcomeScript := preload("res://src/runtime/simulation/sim_outcome.gd")
const DeathSettlementNotificationScript := preload("res://src/runtime/combat/death_settlement_notification.gd")

const DEFAULT_TICK_RATE: int = 30

var tick_rate: int = DEFAULT_TICK_RATE
var tick: int = 0
var room_instance_id: String = ""
var world_revision: int = -1
var latest_snapshot: SimSnapshot = null
var last_phase_trace: Array[StringName] = []
## Fail-closed diagnostics: structural changes the kernel had to drop this tick.
## Gameplay never depends on this list; it exists so rejected work is visible.
var tick_diagnostics: Array[StringName] = []

var clock = null
var stores: Array[SimEntityStore] = []
var primary_store_id: StringName = &""

var command_buffer: SimCommandBuffer = null
var intent_buffer: SimIntentBuffer = null
var hit_buffer: SimHitBuffer = null
var status_buffer: SimStatusBuffer = null
var structural_buffer: SimStructuralChangeBuffer = null

var spatial_port: SimSpatialPort = null
var combat_port: SimCombatPort = null
var encounter_port: SimEncounterPort = null
var presentation_port: SimPresentationPort = null

var _pipeline = null
var _next_stable_key: int = SimStableKey.FIRST_VALID_KEY
var _configured: bool = false
## Terminal teardown flag set by shutdown(). A retired room kernel refuses all
## further work for the rest of its lifetime; it can never be re-armed.
var _shutdown: bool = false


func _init() -> void:
	command_buffer = SimCommandBufferScript.new()
	intent_buffer = SimIntentBufferScript.new()
	hit_buffer = SimHitBufferScript.new()
	status_buffer = SimStatusBufferScript.new()
	structural_buffer = SimStructuralChangeBufferScript.new()
	_pipeline = SimTickPipelineScript.new()


func configure(
	instance_id: String,
	revision: int,
	new_tick_rate: int,
	entity_stores: Array[SimEntityStore],
	default_store_id: StringName
) -> SimOutcome:
	if _shutdown:
		return SimOutcome.failure(&"kernel_shutdown")
	if instance_id.strip_edges().is_empty():
		return SimOutcome.failure(&"invalid_room_instance_id")
	if revision < 0:
		return SimOutcome.failure(&"invalid_world_revision")
	if new_tick_rate <= 0:
		return SimOutcome.failure(&"invalid_tick_rate")
	if entity_stores.is_empty():
		return SimOutcome.failure(&"no_entity_stores")
	var found_primary: bool = false
	for store in entity_stores:
		if store.store_id == default_store_id:
			found_primary = true
	if not found_primary:
		return SimOutcome.failure(&"unknown_primary_store")
	for store in entity_stores:
		var store_configured: SimOutcome = store.configure(instance_id.strip_edges(), revision)
		if not store_configured.ok:
			return store_configured

	room_instance_id = instance_id.strip_edges()
	world_revision = revision
	tick_rate = new_tick_rate
	stores = entity_stores.duplicate()
	primary_store_id = default_store_id
	tick = 0
	_next_stable_key = SimStableKey.FIRST_VALID_KEY
	_configured = true
	latest_snapshot = null
	last_phase_trace = []
	clock = FixedTickClockScript.new(tick_rate)
	command_buffer.clear()
	intent_buffer.clear()
	hit_buffer.clear()
	status_buffer.clear()
	structural_buffer.clear()
	return SimOutcome.success()


func is_configured() -> bool:
	return _configured


func set_ports(
	new_spatial: SimSpatialPort,
	new_combat: SimCombatPort,
	new_encounter: SimEncounterPort,
	new_presentation: SimPresentationPort
) -> void:
	if _shutdown:
		return
	spatial_port = new_spatial
	combat_port = new_combat
	encounter_port = new_encounter
	presentation_port = new_presentation


## Room teardown boundary and the only way out of the kernel's borrow cycle.
##
## Ownership contract: the kernel owns the four typed port references and
## borrows the entity stores, while ports borrow the actor registry and the
## registry borrows this kernel back (kernel -> port -> access -> registry ->
## kernel). RefCounted cannot free that cycle by itself, so a dropped world
## without shutdown leaks the entire room graph on every room unmount and at
## engine exit. shutdown() severs the kernel-owned edges, releases entity
## storage through each store, and fails the kernel closed permanently: ticks,
## commands, reconfiguration, and port rewiring are all refused after
## teardown. Safe on an unconfigured kernel and idempotent.
func shutdown() -> void:
	_shutdown = true
	_configured = false
	spatial_port = null
	combat_port = null
	encounter_port = null
	presentation_port = null
	for store in stores:
		store.shutdown()
	stores = []
	latest_snapshot = null
	last_phase_trace = []
	tick_diagnostics = []
	clock = null
	command_buffer.clear()
	intent_buffer.clear()
	hit_buffer.clear()
	status_buffer.clear()
	structural_buffer.clear()


func queue_command(command: SimCommand) -> SimOutcome:
	if not _configured:
		return SimOutcome.failure(&"kernel_not_configured")
	return command_buffer.enqueue(command, room_instance_id, world_revision)


## Presentation frame to whole authority ticks. The kernel owns the only
## accumulator; no other system may keep frame time.
func consume_frame(frame_delta: float) -> int:
	if clock == null:
		return 0
	return int(clock.consume_frame(frame_delta))


func allocate_stable_key() -> int:
	var assigned: int = _next_stable_key
	_next_stable_key += 1
	return assigned


func next_stable_key() -> int:
	return _next_stable_key


## Resolves a handle to a live (non-tombstoned) record, fail closed.
func resolve_live(handle: SimEntityHandle, store_id: StringName = &"") -> SimOutcome:
	var store := _store_by_id(store_id)
	if store == null:
		return SimOutcome.failure(&"unknown_store")
	var resolved: SimOutcome = store.resolve(handle)
	if not resolved.ok:
		return resolved
	if store.is_tombstoned(handle):
		return SimOutcome.failure(&"entity_tombstoned")
	return resolved


## Advances exactly one authoritative tick through the fixed pipeline.
func step_tick() -> SimOutcome:
	if not _configured:
		return SimOutcome.failure(&"kernel_not_configured")

	tick += 1
	tick_diagnostics.clear()
	intent_buffer.clear()
	hit_buffer.clear()
	status_buffer.clear()
	structural_buffer.clear()
	var view: SimReadView = SimReadViewScript.build(tick, room_instance_id, world_revision, stores)
	var ctx: SimTickContext = SimTickContextScript.new()
	ctx.tick = tick
	ctx.room_instance_id = room_instance_id
	ctx.world_revision = world_revision
	ctx.view = view
	ctx.stores = stores
	ctx.intents = intent_buffer
	ctx.hits = hit_buffer
	ctx.statuses = status_buffer
	ctx.structural = structural_buffer

	last_phase_trace = _pipeline.run(self, ctx)
	return SimOutcome.success().with_value(latest_snapshot)


## Pipeline executor callback. Phase order lives in SimTickPipeline; this match
## defines what each fixed slot does.
func execute_tick_phase(phase_id: int, ctx: SimTickContext) -> void:
	match phase_id:
		SimTickPipeline.Phase.BEGIN_TICK_READ_VIEW:
			pass  # Read view and buffers were prepared in step_tick.
		SimTickPipeline.Phase.INTENT:
			if encounter_port != null:
				encounter_port.produce_intents(ctx)
		SimTickPipeline.Phase.ACTION_COMMIT:
			_commit_actions(ctx)
		SimTickPipeline.Phase.MOVEMENT_BOUNDARY:
			if spatial_port != null:
				spatial_port.apply_movement(ctx)
		SimTickPipeline.Phase.DYNAMIC_INDEX_REFRESH:
			if spatial_port != null:
				spatial_port.refresh_dynamic_index(ctx)
		SimTickPipeline.Phase.CONTINUOUS_QUERIES:
			if spatial_port != null:
				spatial_port.run_continuous_queries(ctx)
		SimTickPipeline.Phase.DAMAGE_STATUS:
			if combat_port != null:
				combat_port.resolve(ctx)
		SimTickPipeline.Phase.DEATH_SETTLEMENT:
			_settle_deaths(ctx)
		SimTickPipeline.Phase.STRUCTURAL_COMMIT:
			_commit_structural(ctx)
		SimTickPipeline.Phase.AUTHORITATIVE_SNAPSHOT:
			_build_snapshot(ctx)


func _commit_actions(ctx: SimTickContext) -> void:
	for command in command_buffer.drain():
		match command.kind:
			SimCommand.Kind.SPAWN:
				var target_store: StringName = command.store_id if command.store_id != &"" else primary_store_id
				ctx.structural.enqueue(SimStructuralChangeScript.spawn_entity(command.spawn_record, target_store, &"command"))
			SimCommand.Kind.DESPAWN:
				var target_store := _store_by_id(command.store_id)
				var live_result: SimOutcome = resolve_live(command.target, command.store_id)
				if not live_result.ok:
					continue
				target_store.mark_tombstone(command.target)
				ctx.structural.enqueue(SimStructuralChangeScript.retire(command.target, &"command"))
			SimCommand.Kind.CONTROL:
				var control_result: SimOutcome = resolve_live(command.target, command.store_id)
				if not control_result.ok:
					continue
				ctx.intents.append(SimIntent.make(command.target, command.move_direction, command.primary_action, &"control"))


func _settle_deaths(ctx: SimTickContext) -> void:
	for store in stores:
		for entity_view in store.tombstone_dead_records():
			ctx.structural.enqueue(SimStructuralChangeScript.retire(entity_view.handle, &"death"))
			var notification: Variant = null
			if combat_port != null:
				notification = combat_port.on_death(entity_view, ctx)
			if encounter_port != null:
				if notification is DeathSettlementNotificationScript:
					encounter_port.on_death_settlement(notification, ctx)
				else:
					encounter_port.on_death(entity_view, ctx)


func _commit_structural(ctx: SimTickContext) -> void:
	for change in structural_buffer.drain():
		if change.kind != SimStructuralChange.Kind.SPAWN:
			continue
		var store := _store_by_id(change.target_store_id)
		if store == null:
			tick_diagnostics.append(&"spawn_target_store_missing")
			continue
		var spawn_result: SimOutcome = store.spawn(change.spawn_record, allocate_stable_key())
		if not spawn_result.ok:
			tick_diagnostics.append(spawn_result.error)
	for store in stores:
		store.reclaim_tombstones()


func _build_snapshot(ctx: SimTickContext) -> void:
	var merged_rows: Array = []
	for store in stores:
		merged_rows.append_array(store.snapshot_rows())
	merged_rows.sort_custom(func(left, right) -> bool:
		return int(left[0]) < int(right[0]))
	var snapshot: SimSnapshot = SimSnapshotScript.new()
	snapshot.tick = tick
	snapshot.tick_rate = tick_rate
	snapshot.room_instance_id = room_instance_id
	snapshot.world_revision = world_revision
	snapshot.next_stable_key = _next_stable_key
	snapshot.rows = merged_rows
	snapshot.phase_trace = ctx.phase_trace.duplicate()
	latest_snapshot = snapshot
	if presentation_port != null:
		presentation_port.on_snapshot(snapshot)


func _store_by_id(id: StringName) -> SimEntityStore:
	var target: StringName = id if id != &"" else primary_store_id
	for store in stores:
		if store.store_id == target:
			return store
	return null
