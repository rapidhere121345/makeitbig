class_name DeathSettlementResult
extends RefCounted

var tick := -1
var entity_key := ""
var duplicate := false
var removal_request: Dictionary = {}
var encounter_notification: RefCounted = null
var loot_spawn_request: Dictionary = {}
var events: Array[Dictionary] = []


func snapshot() -> Dictionary:
	return {
		"tick": tick,
		"entity_key": entity_key,
		"duplicate": duplicate,
		"removal_request": removal_request.duplicate(true),
		"encounter_notification": encounter_notification.snapshot() if encounter_notification != null else {},
		"loot_spawn_request": loot_spawn_request.duplicate(true),
		"events": events.duplicate(true),
	}
