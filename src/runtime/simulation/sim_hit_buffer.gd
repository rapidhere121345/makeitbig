class_name SimHitBuffer
extends RefCounted

## Per-tick hit collection, cleared by the begin-tick phase.

var _hits: Array[SimHit] = []


func append(hit: SimHit) -> void:
	if hit != null and hit.target != null:
		_hits.append(hit)


func hits() -> Array[SimHit]:
	return _hits


func clear() -> void:
	_hits.clear()
