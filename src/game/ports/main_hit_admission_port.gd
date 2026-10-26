extends "res://src/runtime/combat/room_hit_admission_port.gd"

var _owner: MainArena = null


func bind(owner: MainArena) -> Dictionary:
	if owner == null or not is_instance_valid(owner):
		return {"ok": false, "error": "hit_admission_owner_unavailable"}
	_owner = owner
	return {"ok": true, "error": ""}


func admit(hit: Dictionary) -> Dictionary:
	if _owner == null or not is_instance_valid(_owner):
		return {"allowed": false, "reason": "hit_admission_owner_unavailable"}
	return _owner._kernel_reconciler._admit_kernel_hit(hit)
