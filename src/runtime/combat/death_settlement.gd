class_name DeathSettlement
extends RefCounted

const RequestScript := preload("res://src/runtime/combat/death_settlement_request.gd")
const ResultScript := preload("res://src/runtime/combat/death_settlement_result.gd")
const NotificationScript := preload("res://src/runtime/combat/death_settlement_notification.gd")

var room_id := ""
var world_revision := -1
var last_tick := -1
var _settled: Dictionary = {}


func configure(identifier: String, revision: int = 0, initial_tick: int = -1) -> Dictionary:
	if not _valid_id(identifier) or revision < 0 or initial_tick < -1:
		return _failure("invalid_death_settlement_configuration")
	room_id = identifier
	world_revision = revision
	last_tick = initial_tick
	_settled.clear()
	return {"ok": true, "error": "", "snapshot": snapshot()}


func reset() -> void:
	room_id = ""
	world_revision = -1
	last_tick = -1
	_settled.clear()


## Converts one authoritative death into structural requests. The death key is
## the stable entity key, so a stale duplicate can never create a second remove,
## encounter notification, or loot spawn.
func settle(raw_request: Variant) -> Dictionary:
	if room_id.is_empty():
		return _failure("death_settlement_not_configured")
	var parsed: Dictionary = RequestScript.from_data(raw_request)
	if not bool(parsed.get("ok", false)):
		return parsed
	var request: Variant = parsed["value"]
	if request.room_id != room_id:
		return _failure("death_request_room_mismatch")
	if _settled.has(request.entity_key):
		var duplicate_snapshot: Dictionary = _settled[request.entity_key].duplicate(true)
		duplicate_snapshot["duplicate"] = true
		return {"ok": true, "error": "", "changed": false, "duplicate": true, "snapshot": duplicate_snapshot}
	if request.tick < last_tick:
		return _failure("stale_death_settlement_tick")

	last_tick = maxi(last_tick, request.tick)
	var result: Variant = ResultScript.new()
	result.tick = request.tick
	result.entity_key = request.entity_key
	result.removal_request = {
		"tick": request.tick,
		"entity_key": request.entity_key,
		"reason": request.death_reason,
		"world_revision": world_revision,
	}
	var encounter_notification: RefCounted = NotificationScript.new()
	encounter_notification.tick = request.tick
	encounter_notification.room_id = room_id
	encounter_notification.world_revision = world_revision
	encounter_notification.entity_key = request.entity_key
	encounter_notification.spawn_key = request.spawn_key
	result.encounter_notification = encounter_notification
	if request.can_drop:
		result.loot_spawn_request = {
			"tick": request.tick,
			"room_id": room_id,
			"source": request.loot_source,
			"source_entity_key": request.entity_key,
			"position": request.position,
			"tags": request.loot_tags.duplicate(),
			"archetype_id": request.archetype_id,
		}
	result.events.append({
		"tick": request.tick,
		"type": "death_settled",
		"entity_key": request.entity_key,
		"source_key": request.source_key,
	})
	var stored: Dictionary = result.snapshot()
	_settled[request.entity_key] = stored
	return {"ok": true, "error": "", "changed": true, "duplicate": false, "value": result, "snapshot": stored.duplicate(true)}


func settle_batch(tick: int, raw_requests: Array) -> Dictionary:
	if tick < 0 or tick < last_tick:
		return _failure("stale_death_settlement_tick")
	var normalized: Array[Dictionary] = []
	for raw_request: Variant in raw_requests:
		var parsed: Dictionary = RequestScript.from_data(raw_request)
		if not bool(parsed.get("ok", false)):
			return parsed
		var request: Variant = parsed["value"]
		if request.tick != tick:
			return _failure("death_batch_tick_mismatch")
		normalized.append(request.snapshot())
	normalized.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return String(left.get("entity_key", "")) < String(right.get("entity_key", ""))
	)
	var results: Array[Dictionary] = []
	for raw: Dictionary in normalized:
		var settled: Dictionary = settle(raw)
		if not bool(settled.get("ok", false)):
			return settled
		results.append(settled.get("snapshot", {}).duplicate(true))
	return {"ok": true, "error": "", "changed": not results.is_empty(), "results": results, "snapshot": snapshot()}


func snapshot() -> Dictionary:
	var settled_keys: Array[String] = []
	for key: Variant in _settled.keys():
		settled_keys.append(String(key))
	settled_keys.sort()
	var values: Array[Dictionary] = []
	for key: String in settled_keys:
		values.append(_settled[key].duplicate(true))
	return {
		"room_id": room_id,
		"world_revision": world_revision,
		"last_tick": last_tick,
		"settled_keys": settled_keys,
		"results": values,
	}


func _valid_id(value: String) -> bool:
	return not value.is_empty() and value == value.strip_edges() and not value.contains(" ")


static func _failure(error: String) -> Dictionary:
	return {"ok": false, "error": error}
