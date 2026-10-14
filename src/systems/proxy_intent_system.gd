class_name ProxyIntentSystem
extends RefCounted

## Room-local orchestration for the automatic player intent stream.
##
## ProxyDecision remains the pure, deterministic policy function. This service
## owns only the policy's contract-scoped continuation state and diagnostics;
## it never reads Input, moves an actor, validates room authority, or dispatches
## a command. The room supplies the public observation and the shared command
## sequence, then routes the returned commands through CombatCommandRouter.

const ProxyDecisionScript := preload("res://src/systems/proxy_decision.gd")

var resolved_build: Dictionary = {}
var decision_state: Dictionary = {}
var last_failure: Dictionary = {}
var last_trace: Array[String] = []


func begin_contract(build: Variant) -> Dictionary:
	var initial := ProxyDecisionScript.initial_state(build)
	if initial.is_empty():
		reset()
		return {"ok": false, "error": "invalid_initial_state"}
	resolved_build = build.duplicate(true) if build is Dictionary else {}
	decision_state = initial.duplicate(true)
	last_failure.clear()
	last_trace.clear()
	return {"ok": true, "state": decision_state.duplicate(true)}


func reset() -> void:
	resolved_build.clear()
	decision_state.clear()
	last_failure.clear()
	last_trace.clear()


func is_ready() -> bool:
	return not resolved_build.is_empty() and not decision_state.is_empty()


func decide(public_snapshot: Variant, sequence_start: int) -> Dictionary:
	if not is_ready():
		last_trace = ["reject:proxy_not_started"]
		last_failure = {
			"stage": "decision",
			"category": "lifecycle",
			"reason": "proxy_not_started",
			"tick": int(public_snapshot.get("tick", -1)) if public_snapshot is Dictionary else -1,
		}
		return {
			"ok": false,
			"error": "proxy_not_started",
			"commands": [],
			"next_state": {},
			"trace": last_trace.duplicate(),
			"next_sequence": sequence_start,
		}
	var result: Dictionary = ProxyDecisionScript.decide(public_snapshot, resolved_build, decision_state, sequence_start)
	last_trace.clear()
	for entry: Variant in result.get("trace", []):
		last_trace.append(String(entry))
	if not bool(result.get("ok", false)):
		last_failure = {
			"stage": "decision",
			"category": "protocol",
			"reason": String(result.get("error", "invalid_proxy_decision")),
			"tick": int(public_snapshot.get("tick", -1)) if public_snapshot is Dictionary else -1,
		}
		return result.duplicate(true)
	decision_state = (result.get("next_state", {}) as Dictionary).duplicate(true)
	last_failure.clear()
	return result.duplicate(true)


func decision_state_snapshot() -> Dictionary:
	return decision_state.duplicate(true)


func trace_snapshot() -> Array[String]:
	return last_trace.duplicate()


func failure_snapshot() -> Dictionary:
	return last_failure.duplicate(true)


func diagnostic_snapshot() -> Dictionary:
	return {
		"decision_state": decision_state_snapshot(),
		"last_failure": last_failure.duplicate(true),
		"last_trace": last_trace.duplicate(),
		"resolved_build_fingerprint": String(resolved_build.get("semantic_fingerprint", "")),
	}
