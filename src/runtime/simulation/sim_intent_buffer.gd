class_name SimIntentBuffer
extends RefCounted

## Per-tick intent collection, cleared by the begin-tick phase.
##
## Order contract: encounter intents are appended first in stable-key order,
## control-command intents second in submission order. Consumers must preserve
## this order; it is part of the deterministic phase contract.

var _intents: Array[SimIntent] = []


func append(intent: SimIntent) -> void:
	if intent != null and intent.entity != null:
		_intents.append(intent)


func intents() -> Array[SimIntent]:
	return _intents


func clear() -> void:
	_intents.clear()
