class_name BossDamageBatchResult
extends RefCounted

var tick := -1
var outcomes: Array[BossDamageOutcome] = []
var deaths: Array[String] = []
var rejected: Array[Dictionary] = []
var suppressed: Array[Dictionary] = []


func snapshot() -> Dictionary:
	var values: Array[Dictionary] = []
	for outcome: BossDamageOutcome in outcomes:
		values.append(outcome.snapshot())
	return {
		"tick": tick,
		"outcomes": values,
		"deaths": deaths.duplicate(),
		"rejected": rejected.duplicate(true),
		"suppressed": suppressed.duplicate(true),
	}
