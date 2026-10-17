class_name RoomEncounterSpawnPort
extends RefCounted

## Typed production boundary for materializing a detached encounter request.
##
## Implementations own the room-specific actor adoption or registration policy.
## RoomEncounterPort owns request identity, live room context, result
## normalization, and acknowledgement; this interface only returns the
## existing EncounterSpawnResult contract.

const SpawnResultScript := preload("res://src/runtime/encounter/encounter_spawn_result.gd")


func spawn(request: EncounterSpawnRequest, _context: Dictionary) -> Variant:
	return SpawnResultScript.failed(request, "encounter_spawn_binding_unavailable")
