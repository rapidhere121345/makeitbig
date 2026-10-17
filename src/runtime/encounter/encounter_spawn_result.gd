class_name EncounterSpawnResult
extends RefCounted

## Detached result returned by a production encounter spawn binding.
##
## A successful result carries the kernel-owned identity assigned to the
## materialized actor.  The binding may allocate that identity through the
## room actor access boundary, but it must never invent a stable key or
## generation.

const SimEntityHandleScript := preload("res://src/runtime/simulation/sim_entity_handle.gd")
const SelfScript := preload("res://src/runtime/encounter/encounter_spawn_result.gd")

const KIND_SPAWNED := "spawned"
const KIND_FAILED := "failed"

var kind := KIND_FAILED
var spawn_key := ""
var entity_key := ""
var handle: SimEntityHandle = null
var stable_key := 0
var generation := 0
var room_instance_id := ""
var world_revision := -1
var error := ""


static func spawned(
	request: Variant,
	assigned_handle: SimEntityHandle,
	assigned_entity_key: String,
	assigned_stable_key: int,
	assigned_generation: int = -1,
	assigned_room_instance_id: String = "",
	assigned_world_revision: int = -1
) -> Variant:
	var result: Variant = SelfScript.new()
	result.kind = KIND_SPAWNED
	result.spawn_key = String(request.spawn_key) if request != null else ""
	result.entity_key = assigned_entity_key.strip_edges()
	result.handle = assigned_handle
	result.stable_key = assigned_stable_key
	result.generation = assigned_generation if assigned_generation >= 0 else (assigned_handle.generation if assigned_handle != null else 0)
	result.room_instance_id = assigned_room_instance_id
	result.world_revision = assigned_world_revision
	result.error = ""
	return result


static func failed(request: Variant, reason: String) -> Variant:
	var result: Variant = SelfScript.new()
	result.kind = KIND_FAILED
	result.spawn_key = String(request.spawn_key) if request != null else ""
	result.error = reason.strip_edges()
	return result


func is_spawned() -> bool:
	return kind == KIND_SPAWNED


func is_failed() -> bool:
	return kind == KIND_FAILED


func snapshot() -> Dictionary:
	return {
		"kind": kind,
		"spawn_key": spawn_key,
		"entity_key": entity_key,
		"handle": handle.encode() if handle != null else "",
		"stable_key": stable_key,
		"generation": generation,
		"room_instance_id": room_instance_id,
		"world_revision": world_revision,
		"error": error,
	}
