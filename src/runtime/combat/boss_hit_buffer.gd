class_name BossHitBuffer
extends RefCounted

const HitScript := preload("res://src/runtime/combat/boss_hit_record.gd")
const CoreResult := preload("res://src/core/result.gd")

## Room-scoped typed hit buffer for multipart Boss contacts.  It is opened at
## the continuous-query phase and consumed once by DAMAGE_STATUS.

var tick := -1
var _hits: Array[BossHitRecord] = []


func begin_tick(next_tick: int) -> Dictionary:
	if next_tick < 0 or (tick >= 0 and next_tick < tick):
		return CoreResult.failure("stale_boss_hit_tick")
	if next_tick > tick:
		_hits.clear()
		tick = next_tick
	return {"ok": true, "error": ""}


func append_batch(values: Array) -> Dictionary:
	if tick < 0:
		return CoreResult.failure("boss_hit_buffer_not_open")
	var validated: Array[BossHitRecord] = []
	for value: Variant in values:
		if not value is HitScript:
			return CoreResult.failure("invalid_boss_hit_type")
		var hit: BossHitRecord = value
		if hit.tick != tick:
			return CoreResult.failure("boss_hit_tick_mismatch")
		var error := hit.validate()
		if not error.is_empty():
			return CoreResult.failure(error)
		validated.append(hit)
	_hits.append_array(validated)
	return {"ok": true, "error": "", "count": validated.size()}


func hits() -> Array[BossHitRecord]:
	return _hits.duplicate()


func take_ordered() -> Array:
	var result := HitScript.ordered(_hits)
	_hits.clear()
	return result


func clear() -> void:
	_hits.clear()


func size() -> int:
	return _hits.size()


func snapshot() -> Dictionary:
	var values: Array[Dictionary] = []
	for hit: BossHitRecord in HitScript.ordered(_hits):
		values.append(hit.snapshot())
	return {"tick": tick, "hits": values}

