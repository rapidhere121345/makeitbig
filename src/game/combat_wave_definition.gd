class_name CombatWaveDefinition
extends RefCounted

## Validated authored wave data. Runtime wave state belongs to the room facade;
## this object contains only immutable definition data.

const CLEAR_RULES: Array[String] = ["all_dead"]
const WAVE_FIELDS: Array[String] = ["wave_id", "spawn_tick", "enemies", "clear_when", "next_wave_delay_ticks"]
const SPAWN_FIELDS: Array[String] = ["spawn_id", "kind_id", "socket", "stats_id", "action_profile_id"]

var wave_id := ""
var spawn_tick := 0
var enemies: Array[Dictionary] = []
var clear_when := "all_dead"
var next_wave_delay_ticks := 0


static func normalize_data(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return _failure("invalid_wave_type")
	var data: Dictionary = value
	var errors: Array[String] = []
	for field: String in WAVE_FIELDS:
		if not data.has(field):
			errors.append("missing_field:%s" % field)
	for key: Variant in data.keys():
		if not key is String or String(key) not in WAVE_FIELDS:
			errors.append("unknown_field:%s" % String(key))
	if not _non_empty_text(data.get("wave_id", null)):
		errors.append("invalid_wave_id")
	if not _non_negative_integer(data.get("spawn_tick", null)):
		errors.append("invalid_spawn_tick")
	if not _non_negative_integer(data.get("next_wave_delay_ticks", null)):
		errors.append("invalid_next_wave_delay_ticks")
	if not data.get("clear_when", null) is String or String(data.get("clear_when", "")) not in CLEAR_RULES:
		errors.append("invalid_clear_when")
	var enemy_value: Variant = data.get("enemies", null)
	var normalized_enemies: Array[Dictionary] = []
	var seen_ids := {}
	if not enemy_value is Array or (enemy_value as Array).is_empty():
		errors.append("invalid_enemies")
	else:
		for index in range((enemy_value as Array).size()):
			var spawn_value: Variant = (enemy_value as Array)[index]
			var normalized := _normalize_spawn(spawn_value)
			if not bool(normalized.ok):
				errors.append("enemies[%d]:%s" % [index, String(normalized.error)])
				continue
			var spawn: Dictionary = normalized.value
			if seen_ids.has(spawn.spawn_id):
				errors.append("duplicate_spawn_id:%s" % String(spawn.spawn_id))
			else:
				seen_ids[spawn.spawn_id] = true
				normalized_enemies.append(spawn)
	if not errors.is_empty():
		return {"ok": false, "error": ";".join(errors), "errors": errors, "value": {}}
	var result: RefCounted = load("res://src/game/combat_wave_definition.gd").new()
	result.wave_id = String(data.wave_id)
	result.spawn_tick = int(data.spawn_tick)
	result.enemies = normalized_enemies.duplicate(true)
	result.clear_when = String(data.clear_when)
	result.next_wave_delay_ticks = int(data.next_wave_delay_ticks)
	return {"ok": true, "error": "", "errors": [], "value": result}


static func normalize_waves(value: Variant) -> Dictionary:
	if not value is Array or (value as Array).is_empty():
		return _failure("invalid_waves")
	var result: Array[Dictionary] = []
	var seen_ids := {}
	var errors: Array[String] = []
	for index in range((value as Array).size()):
		var normalized := normalize_data((value as Array)[index])
		if not bool(normalized.ok):
			errors.append("waves[%d]:%s" % [index, String(normalized.error)])
			continue
		var wave: CombatWaveDefinition = normalized.value
		if seen_ids.has(wave.wave_id):
			errors.append("duplicate_wave_id:%s" % wave.wave_id)
		else:
			seen_ids[wave.wave_id] = true
			result.append(wave.snapshot())
	if not errors.is_empty():
		return {"ok": false, "error": ";".join(errors), "errors": errors, "value": []}
	return {"ok": true, "error": "", "errors": [], "value": result}


func snapshot() -> Dictionary:
	return {
		"wave_id": wave_id,
		"spawn_tick": spawn_tick,
		"enemies": enemies.duplicate(true),
		"clear_when": clear_when,
		"next_wave_delay_ticks": next_wave_delay_ticks,
	}


static func _normalize_spawn(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {"ok": false, "error": "invalid_spawn_type", "value": {}}
	var data: Dictionary = value
	var errors: Array[String] = []
	for field: String in SPAWN_FIELDS:
		if not data.has(field):
			errors.append("missing_field:%s" % field)
	for key: Variant in data.keys():
		if not key is String or String(key) not in SPAWN_FIELDS:
			errors.append("unknown_field:%s" % String(key))
	for field: String in SPAWN_FIELDS:
		if not _non_empty_text(data.get(field, null)):
			errors.append("invalid_%s" % field)
	if not errors.is_empty():
		return {"ok": false, "error": ";".join(errors), "value": {}}
	var normalized := {}
	for field: String in SPAWN_FIELDS:
		normalized[field] = String(data[field]).strip_edges()
	return {"ok": true, "error": "", "value": normalized}


static func _non_empty_text(value: Variant) -> bool:
	return (value is String or value is StringName) and not String(value).strip_edges().is_empty()


static func _non_negative_integer(value: Variant) -> bool:
	return typeof(value) == TYPE_INT and int(value) >= 0


static func _failure(error: String) -> Dictionary:
	return {"ok": false, "error": error, "errors": [error], "value": []}
