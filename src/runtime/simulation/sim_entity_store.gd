class_name SimEntityStore
extends RefCounted

## Typed, room-scoped entity storage.
##
## A store accepts records of exactly one script type (fail closed otherwise)
## and is owned by one kernel configuration. Identity, generation, tombstones,
## and slot reuse live here; domain logic never touches slots directly.
##
## Record contract (validated at spawn):
##   - set_entity_identity(handle: SimEntityHandle, key: int) -> void
##   - build_entity_view() -> SimEntityView
##   - snapshot_payload() -> Array
##   - readable "alive" property

const SimEntitySlotScript := preload("res://src/runtime/simulation/sim_entity_slot.gd")
const SimEntityHandleScript := preload("res://src/runtime/simulation/sim_entity_handle.gd")
const SimEntityViewScript := preload("res://src/runtime/simulation/sim_entity_view.gd")
const SimOutcomeScript := preload("res://src/runtime/simulation/sim_outcome.gd")

var store_id: StringName = &""
var room_instance_id: String = ""
var world_revision: int = -1
var _record_script: Script = null
var _slots: Array[SimEntitySlot] = []
var _free_indices: Array[int] = []


func _init(assigned_id: StringName, record_script: Script) -> void:
	store_id = assigned_id
	_record_script = record_script


func configure(instance_id: String, revision: int) -> SimOutcome:
	if instance_id.strip_edges().is_empty() or revision < 0:
		return SimOutcome.failure(&"invalid_store_configuration")
	room_instance_id = instance_id.strip_edges()
	world_revision = revision
	_slots.clear()
	_free_indices.clear()
	return SimOutcome.success()


## Room teardown: releases every record slot and fails the store closed.
## Called by SimKernel.shutdown() so retired room storage can never resolve,
## spawn, or resurrect entities after teardown.
func shutdown() -> void:
	room_instance_id = ""
	world_revision = -1
	_slots.clear()
	_free_indices.clear()


func record_script() -> Script:
	return _record_script


## Immediate structural spawn with a kernel-assigned stable key. Legal only
## outside a tick (room setup) or inside the structural commit phase, which is
## the only in-tick caller. The kernel owns key allocation; stores never invent
## identities.
func spawn(record: Variant, assigned_key: int) -> SimOutcome:
	if record == null:
		return SimOutcome.failure(&"null_record")
	if not record is Object:
		return SimOutcome.failure(&"record_type_mismatch")
	if not _record_script.instance_has(record):
		return SimOutcome.failure(&"record_type_mismatch")
	if not _satisfies_contract(record):
		return SimOutcome.failure(&"invalid_record_contract")
	if assigned_key < SimStableKey.FIRST_VALID_KEY:
		return SimOutcome.failure(&"invalid_stable_key")
	if room_instance_id.is_empty():
		return SimOutcome.failure(&"store_not_configured")

	var slot_index: int = -1
	if not _free_indices.is_empty():
		slot_index = _free_indices.pop_back()
	else:
		slot_index = _slots.size()
		_slots.append(SimEntitySlotScript.new())
	var slot: SimEntitySlot = _slots[slot_index]
	slot.generation += 1
	slot.stable_key = assigned_key
	slot.tombstone = false
	slot.record = record

	var handle := SimEntityHandleScript.make(
		slot_index,
		slot.generation,
		store_id,
		room_instance_id,
		world_revision
	)
	record.set_entity_identity(handle, slot.stable_key)
	return SimOutcome.success().with_handle(handle).with_key(slot.stable_key)


## Marks the entity dead-but-present. Storage is reclaimed by reclaim_tombstones().
func mark_tombstone(handle: SimEntityHandle) -> SimOutcome:
	var resolved := _resolve(handle)
	if not resolved.ok:
		return resolved
	var slot: SimEntitySlot = resolved.value
	if slot.tombstone:
		return SimOutcome.failure(&"already_tombstoned")
	slot.tombstone = true
	slot.record.alive = false
	return SimOutcome.success().with_key(slot.stable_key)


## Frees tombstoned storage. Called by the structural commit phase only.
func reclaim_tombstones() -> int:
	var reclaimed: int = 0
	for slot_index in _slots.size():
		var slot: SimEntitySlot = _slots[slot_index]
		if slot.occupied() and slot.tombstone:
			slot.record = null
			slot.stable_key = 0
			_free_indices.append(slot_index)
			reclaimed += 1
	return reclaimed


func resolve(handle: SimEntityHandle) -> SimOutcome:
	var resolved := _resolve(handle)
	if not resolved.ok:
		return resolved
	return SimOutcome.success().with_value(resolved.value.record).with_key(resolved.value.stable_key)


func is_live(handle: SimEntityHandle) -> bool:
	var resolved := _resolve(handle)
	return resolved.ok and resolved.value.is_live()


func is_tombstoned(handle: SimEntityHandle) -> bool:
	var resolved := _resolve(handle)
	return resolved.ok and resolved.value.tombstone


func live_count() -> int:
	var total: int = 0
	for slot in _slots:
		if slot.is_live():
			total += 1
	return total


## Deterministic iteration: live slots sorted by stable key. No Dictionary
## iteration ever participates in gameplay ordering.
func live_slots_sorted_by_key() -> Array[SimEntitySlot]:
	var live: Array[SimEntitySlot] = []
	for slot in _slots:
		if slot.is_live():
			live.append(slot)
	live.sort_custom(func(left: SimEntitySlot, right: SimEntitySlot) -> bool:
		return left.stable_key < right.stable_key)
	return live


func build_views_sorted_by_key() -> Array[SimEntityView]:
	var views: Array[SimEntityView] = []
	for slot in live_slots_sorted_by_key():
		views.append(slot.record.build_entity_view())
	return views


## Death settlement sweep: tombstones every occupied slot whose record reports
## alive == false, in stable-key order. Returns views of the entities that
## transitioned to tombstone so the kernel can notify hooks and defer reclaims.
func tombstone_dead_records() -> Array[SimEntityView]:
	var settled: Array[SimEntityView] = []
	for slot in live_slots_sorted_by_key():
		if not bool(slot.record.get("alive")):
			slot.tombstone = true
			settled.append(slot.record.build_entity_view())
	return settled


func snapshot_rows() -> Array:
	var rows: Array = []
	for slot in live_slots_sorted_by_key():
		var record: Variant = slot.record
		rows.append([
			slot.stable_key,
			_index_of_slot(slot),
			slot.generation,
			1 if bool(record.get("alive")) else 0,
			room_instance_id,
			world_revision,
			record.snapshot_payload(),
		])
	return rows


func _index_of_slot(target: SimEntitySlot) -> int:
	for slot_index in _slots.size():
		if _slots[slot_index] == target:
			return slot_index
	return -1


func _resolve(handle: SimEntityHandle) -> SimOutcome:
	if handle == null or not handle.is_valid():
		return SimOutcome.failure(&"invalid_entity_handle")
	if not handle.matches_scope(store_id, room_instance_id, world_revision):
		return SimOutcome.failure(&"stale_entity_handle")
	if handle.index >= _slots.size():
		return SimOutcome.failure(&"stale_entity_handle")
	var slot: SimEntitySlot = _slots[handle.index]
	if slot.record == null or slot.generation != handle.generation:
		return SimOutcome.failure(&"stale_entity_handle")
	return SimOutcome.success().with_value(slot)


func _satisfies_contract(record: Variant) -> bool:
	return record.has_method("set_entity_identity") \
		and record.has_method("build_entity_view") \
		and record.has_method("snapshot_payload") \
		and record.get("alive") != null
