extends "res://src/runtime/world/room_movement_policy_port.gd"

var _owner: MainArena = null


func bind(owner: MainArena) -> Dictionary:
	if owner == null or not is_instance_valid(owner):
		return {"ok": false, "error": "movement_policy_owner_unavailable"}
	_owner = owner
	return {"ok": true, "error": ""}


func resolve(actor_id: String) -> Variant:
	if _owner == null or not is_instance_valid(_owner):
		return null
	return _owner._resolve_ranger_movement_policy(actor_id)
