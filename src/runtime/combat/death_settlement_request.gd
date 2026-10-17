class_name DeathSettlementRequest
extends RefCounted

const SelfScript := preload("res://src/runtime/combat/death_settlement_request.gd")

const LOOT_SOURCES := ["enemy_death", "wave_clear"]

var tick := -1
var room_id := ""
var entity_key := ""
var source_key := ""
var spawn_key := ""
var archetype_id := ""
var position := Vector2.ZERO
var death_reason := "damage"
var loot_source := "enemy_death"
var loot_tags: Array[String] = []
var can_drop := true


static func from_data(value: Variant) -> Dictionary:
	var raw: Variant = value.snapshot() if value is Object and value.has_method("snapshot") else value
	if not raw is Dictionary:
		return _failure("death_request_not_dictionary")
	var source: Dictionary = raw
	for key: Variant in source.keys():
		if String(key) not in ["tick", "room_id", "entity_key", "source_key", "spawn_key", "archetype_id", "position", "death_reason", "loot_source", "loot_tags", "can_drop"]:
			return _failure("unknown_death_request_field:%s" % String(key))
	var result: Variant = SelfScript.new()
	var raw_tick: Variant = source.get("tick", -1)
	if not raw_tick is int:
		return _failure("invalid_death_request_tick")
	result.tick = int(raw_tick)
	result.room_id = String(source.get("room_id", ""))
	result.entity_key = String(source.get("entity_key", ""))
	result.source_key = String(source.get("source_key", ""))
	result.spawn_key = String(source.get("spawn_key", ""))
	result.archetype_id = String(source.get("archetype_id", ""))
	var raw_position: Variant = source.get("position", Vector2.ZERO)
	result.position = raw_position if raw_position is Vector2 else Vector2.INF
	result.death_reason = String(source.get("death_reason", "damage"))
	result.loot_source = String(source.get("loot_source", "enemy_death"))
	var raw_can_drop: Variant = source.get("can_drop", true)
	if not raw_can_drop is bool:
		return _failure("invalid_death_request_drop_flag")
	result.can_drop = bool(raw_can_drop)
	var raw_tags: Variant = source.get("loot_tags", [])
	if not raw_tags is Array:
		return _failure("invalid_death_request_tags")
	for raw_tag: Variant in raw_tags as Array:
		if not raw_tag is String or not _valid_id(String(raw_tag)):
			return _failure("invalid_death_request_tag")
		result.loot_tags.append(String(raw_tag))
	result.loot_tags.sort()
	var error: String = result.validate()
	if not error.is_empty():
		return _failure(error)
	return {"ok": true, "error": "", "value": result}


func validate() -> String:
	if tick < 0 or not _valid_id(room_id) or not _valid_id(entity_key):
		return "invalid_death_request_identity"
	if not source_key.is_empty() and not _valid_id(source_key):
		return "invalid_death_request_source"
	if not spawn_key.is_empty() and not _valid_id(spawn_key):
		return "invalid_death_request_spawn"
	if not archetype_id.is_empty() and not _valid_id(archetype_id):
		return "invalid_death_request_archetype"
	if not position.is_finite():
		return "invalid_death_request_position"
	if not _valid_id(death_reason) or loot_source not in LOOT_SOURCES:
		return "invalid_death_request_reason"
	return ""


func snapshot() -> Dictionary:
	return {
		"tick": tick,
		"room_id": room_id,
		"entity_key": entity_key,
		"source_key": source_key,
		"spawn_key": spawn_key,
		"archetype_id": archetype_id,
		"position": position,
		"death_reason": death_reason,
		"loot_source": loot_source,
		"loot_tags": loot_tags.duplicate(),
		"can_drop": can_drop,
	}


static func _valid_id(value: String) -> bool:
	return not value.is_empty() and value == value.strip_edges() and not value.contains(" ")


static func _failure(error: String) -> Dictionary:
	return {"ok": false, "error": error}
