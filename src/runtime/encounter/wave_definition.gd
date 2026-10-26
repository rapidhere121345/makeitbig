class_name WaveDefinition
extends RefCounted

const SCHEMA_VERSION := 1
const CLEAR_POLICIES := ["all_dead", "manual"]
const SpawnSpecScript := preload("res://src/runtime/encounter/encounter_spawn_spec.gd")
const CoreResult := preload("res://src/core/result.gd")

var wave_id := ""
var start_delay_ticks := 0
var next_wave_delay_ticks := 0
var clear_policy := "all_dead"
var objective_tag := ""
var spawn_specs: Array = []


static func from_data(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return CoreResult.failure("wave_not_dictionary")
	var source: Dictionary = value
	for key: Variant in source.keys():
		if String(key) not in ["wave_id", "start_delay_ticks", "next_wave_delay_ticks", "clear_policy", "objective_tag", "spawns"]:
			return CoreResult.failure("unknown_wave_field:%s" % String(key))
	var identifier := String(source.get("wave_id", ""))
	if not _valid_id(identifier):
		return CoreResult.failure("invalid_wave_id")
	var start_delay: Variant = source.get("start_delay_ticks", 0)
	var next_delay: Variant = source.get("next_wave_delay_ticks", 0)
	var policy := String(source.get("clear_policy", "all_dead"))
	if not start_delay is int or int(start_delay) < 0 or not next_delay is int or int(next_delay) < 0:
		return CoreResult.failure("invalid_wave_delay")
	if policy not in CLEAR_POLICIES:
		return CoreResult.failure("invalid_wave_clear_policy")
	var objective := String(source.get("objective_tag", ""))
	if not objective.is_empty() and not _valid_id(objective):
		return CoreResult.failure("invalid_wave_objective_tag")
	var raw_spawns: Variant = source.get("spawns", [])
	if not raw_spawns is Array or (raw_spawns as Array).is_empty():
		return CoreResult.failure("missing_wave_spawns")
	var result: Variant = preload("res://src/runtime/encounter/wave_definition.gd").new()
	result.wave_id = identifier
	result.start_delay_ticks = int(start_delay)
	result.next_wave_delay_ticks = int(next_delay)
	result.clear_policy = policy
	result.objective_tag = objective
	var seen: Dictionary = {}
	for raw_spawn: Variant in raw_spawns as Array:
		var parsed: Dictionary = SpawnSpecScript.from_data(raw_spawn)
		if not bool(parsed.get("ok", false)):
			return parsed
		var spec: Variant = parsed["value"]
		if seen.has(spec.spawn_id):
			return CoreResult.failure("duplicate_spawn_id:%s" % spec.spawn_id)
		seen[spec.spawn_id] = true
		result.spawn_specs.append(spec)
	result.spawn_specs.sort_custom(func(left: Variant, right: Variant) -> bool:
		return left.spawn_id < right.spawn_id
	)
	return {"ok": true, "error": "", "value": result}


func total_spawn_count() -> int:
	var result := 0
	for spec: Variant in spawn_specs:
		result += spec.count
	return result


func snapshot() -> Dictionary:
	var spawns: Array[Dictionary] = []
	for spec: Variant in spawn_specs:
		spawns.append(spec.snapshot())
	return {
		"schema_version": SCHEMA_VERSION,
		"wave_id": wave_id,
		"start_delay_ticks": start_delay_ticks,
		"next_wave_delay_ticks": next_wave_delay_ticks,
		"clear_policy": clear_policy,
		"objective_tag": objective_tag,
		"spawns": spawns,
	}


static func _valid_id(value: String) -> bool:
	return not value.is_empty() and value == value.strip_edges() and not value.contains(" ")

