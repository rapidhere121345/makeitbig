extends "res://src/runtime/world/room_encounter_spawn_port.gd"

const EncounterSpawnResultScript := preload("res://src/runtime/encounter/encounter_spawn_result.gd")

var _owner: MainArena = null


func bind(owner: MainArena) -> Dictionary:
	if owner == null or not is_instance_valid(owner):
		return {"ok": false, "error": "encounter_spawn_owner_unavailable"}
	_owner = owner
	return {"ok": true, "error": ""}


func spawn(request: EncounterSpawnRequest, context: Dictionary) -> Variant:
	if _owner == null or not is_instance_valid(_owner):
		return EncounterSpawnResultScript.failed(request, "encounter_spawn_owner_unavailable")
	return _owner.reconcile_encounter_spawn(request, context)
