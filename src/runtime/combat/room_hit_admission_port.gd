class_name RoomHitAdmissionPort
extends RefCounted

## Typed admission boundary evaluated before DamageResolution.
## The room may suppress a translated hit, while RoomCombatPort retains
## ordering, buffering and damage authority.

func admit(_hit: Dictionary) -> Dictionary:
	return {"allowed": false, "reason": "room_hit_admission_unimplemented"}
