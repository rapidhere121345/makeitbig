class_name ContractRoomCommitPort
extends RefCounted

## Typed framework boundary for committing a victorious room before the next
## room starts. The port owns no room state; it only crosses into the
## persistence/build authority and returns a detached result.

func commit(_room_index: int, _room_result: Dictionary) -> Dictionary:
	return {"ok": false, "error": "contract_room_commit_port_unimplemented"}
