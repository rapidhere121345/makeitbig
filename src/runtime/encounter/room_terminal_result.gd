class_name RoomTerminalResult
extends RefCounted

## Typed terminal decision returned by RoomEncounter.

var ok := false
var error := ""
var changed := false
var duplicate := false
var tick := -1
var room_instance_id := ""
var world_revision := -1
var phase := "idle"
var reason := ""


static func failure(error_code: String) -> RoomTerminalResult:
	var result := RoomTerminalResult.new()
	result.error = error_code
	return result


func snapshot() -> Dictionary:
	return {
		"ok": ok,
		"error": error,
		"changed": changed,
		"duplicate": duplicate,
		"tick": tick,
		"room_instance_id": room_instance_id,
		"world_revision": world_revision,
		"phase": phase,
		"victory": phase == "victory",
		"defeat": phase == "defeat",
		"reason": reason,
	}
