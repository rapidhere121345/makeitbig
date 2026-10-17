class_name EncounterStepResult
extends RefCounted

const SpawnRequestScript := preload("res://src/runtime/encounter/encounter_spawn_request.gd")

var tick := -1
var phase := "idle"
var changed := false
var victory := false
var defeat := false
var spawn_requests: Array = []
var events: Array[Dictionary] = []


func snapshot() -> Dictionary:
	var requests: Array[Dictionary] = []
	for request: Variant in spawn_requests:
		requests.append(request.snapshot())
	return {
		"tick": tick,
		"phase": phase,
		"changed": changed,
		"victory": victory,
		"defeat": defeat,
		"spawn_requests": requests,
		"events": events.duplicate(true),
	}
