class_name DamageBatchResult
extends RefCounted

var tick := -1
var outcomes: Array = []
var deaths: Array[String] = []
var rejected: Array[Dictionary] = []


func snapshot() -> Dictionary:
	var values: Array[Dictionary] = []
	for outcome: Variant in outcomes:
		values.append(outcome.snapshot())
	return {
		"tick": tick,
		"outcomes": values,
		"deaths": deaths.duplicate(),
		"rejected": rejected.duplicate(true),
	}
