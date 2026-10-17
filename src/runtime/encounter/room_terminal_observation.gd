class_name RoomTerminalObservation
extends RefCounted

## Typed facts submitted at the end of a fixed room tick.  The composition
## root may mirror these facts, but it cannot decide the terminal phase.

var tick := -1
var room_instance_id := ""
var world_revision := -1
var player_alive := true
var current_wave_index := -1
var requested_member_count := 0
var alive_member_count := 0
var unresolved_member_count := 0
## Objective-specific completion fact.  The encounter still validates member
## counts and owns the terminal transition; this fact only describes a typed
## condition such as hunt-elite being satisfied while other actors remain.
var objective_satisfied := false


func is_valid() -> bool:
	return (
		tick >= 0
		and not room_instance_id.strip_edges().is_empty()
		and world_revision >= 0
		and current_wave_index >= -1
		and requested_member_count >= 0
		and alive_member_count >= 0
		and unresolved_member_count >= 0
		and alive_member_count <= requested_member_count
		and unresolved_member_count <= requested_member_count
	)


func snapshot() -> Dictionary:
	return {
		"tick": tick,
		"room_instance_id": room_instance_id,
		"world_revision": world_revision,
		"player_alive": player_alive,
		"current_wave_index": current_wave_index,
		"requested_member_count": requested_member_count,
		"alive_member_count": alive_member_count,
		"unresolved_member_count": unresolved_member_count,
		"objective_satisfied": objective_satisfied,
	}
