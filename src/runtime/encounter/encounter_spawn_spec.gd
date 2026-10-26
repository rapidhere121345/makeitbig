class_name EncounterSpawnSpec
extends RefCounted

const SCHEMA_VERSION := 1
const SelfScript := preload("res://src/runtime/encounter/encounter_spawn_spec.gd")
const CoreResult := preload("res://src/core/result.gd")

var spawn_id := ""
var archetype_id := ""
var socket_id := ""
var count := 0
var first_tick := 0
var interval_ticks := 0
var tags: Array[String] = []


static func from_data(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return CoreResult.failure("spawn_spec_not_dictionary")
	var source: Dictionary = value
	for key: Variant in source.keys():
		if String(key) not in ["spawn_id", "archetype_id", "socket_id", "count", "first_tick", "interval_ticks", "tags"]:
			return CoreResult.failure("unknown_spawn_spec_field:%s" % String(key))
	var normalized_id := String(source.get("spawn_id", ""))
	var archetype := String(source.get("archetype_id", ""))
	var socket := String(source.get("socket_id", ""))
	var count_value: Variant = source.get("count", 1)
	var first_tick_value: Variant = source.get("first_tick", 0)
	var interval_value: Variant = source.get("interval_ticks", 0)
	if not _valid_id(normalized_id) or not _valid_id(archetype) or not _valid_id(socket):
		return CoreResult.failure("invalid_spawn_spec_identity")
	if not count_value is int or int(count_value) <= 0:
		return CoreResult.failure("invalid_spawn_spec_count")
	if not first_tick_value is int or int(first_tick_value) < 0:
		return CoreResult.failure("invalid_spawn_spec_first_tick")
	if not interval_value is int or int(interval_value) < 0:
		return CoreResult.failure("invalid_spawn_spec_interval")
	var tags: Array[String] = []
	var raw_tags: Variant = source.get("tags", [])
	if not raw_tags is Array:
		return CoreResult.failure("invalid_spawn_spec_tags")
	for raw_tag: Variant in raw_tags as Array:
		if not raw_tag is String or not _valid_id(String(raw_tag)):
			return CoreResult.failure("invalid_spawn_spec_tag")
		tags.append(String(raw_tag))
	tags.sort()
	var result: Variant = SelfScript.new()
	result.spawn_id = normalized_id
	result.archetype_id = archetype
	result.socket_id = socket
	result.count = int(count_value)
	result.first_tick = int(first_tick_value)
	result.interval_ticks = int(interval_value)
	result.tags = tags
	return {"ok": true, "error": "", "value": result}


func spawn_key(wave_id: String, ordinal: int) -> String:
	return "%s/%s/%d" % [wave_id, spawn_id, ordinal]


func requested_tick(wave_start_tick: int, ordinal: int) -> int:
	return wave_start_tick + first_tick + interval_ticks * ordinal


func snapshot() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"spawn_id": spawn_id,
		"archetype_id": archetype_id,
		"socket_id": socket_id,
		"count": count,
		"first_tick": first_tick,
		"interval_ticks": interval_ticks,
		"tags": tags.duplicate(),
	}


static func _valid_id(value: String) -> bool:
	if value.is_empty() or value != value.strip_edges():
		return false
	for character: String in value:
		if character in [" ", "\t", "\n", "\r"]:
			return false
	return true

