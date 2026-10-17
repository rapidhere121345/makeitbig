class_name EncounterSpawnRequest
extends RefCounted

var request_id := ""
var room_id := ""
## Runtime stamps are added by RoomEncounterPort when the detached domain
## request crosses into a mounted room.  room_id remains the authored encounter
## identity; these fields identify the live SceneRuntime instance.
var room_instance_id := ""
var world_revision := -1
var wave_id := ""
var spawn_key := ""
var archetype_id := ""
var socket_id := ""
var requested_tick := -1
var ordinal := -1
var tags: Array[String] = []


func snapshot() -> Dictionary:
	return {
		"request_id": request_id,
		"room_id": room_id,
		"room_instance_id": room_instance_id,
		"world_revision": world_revision,
		"wave_id": wave_id,
		"spawn_key": spawn_key,
		"archetype_id": archetype_id,
		"socket_id": socket_id,
		"requested_tick": requested_tick,
		"ordinal": ordinal,
		"tags": tags.duplicate(),
	}
