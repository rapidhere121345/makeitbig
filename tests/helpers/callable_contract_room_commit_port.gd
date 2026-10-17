class_name CallableContractRoomCommitPort
extends "res://src/game/contract_room_commit_port.gd"

## Tests-only adapter. Production code receives ContractRoomCommitPort and
## never parses a callback bag; tests may still inject a small behavior using a
## Callable behind this typed substitute.

var commit_callback: Callable


func commit(room_index: int, room_result: Dictionary) -> Dictionary:
	if not commit_callback.is_valid():
		return {"ok": false, "error": "test_commit_port_unbound"}
	var result: Variant = commit_callback.call(room_index, room_result)
	return result as Dictionary if result is Dictionary else {"ok": false, "error": "test_commit_port_invalid_result"}
