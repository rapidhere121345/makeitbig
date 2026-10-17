class_name RoomRewardPort
extends RefCounted

## Typed boundary for committing a legacy/profile reward after room victory.

func commit(_reward: Dictionary) -> Dictionary:
	return {"ok": false, "error": "room_reward_port_unimplemented"}
