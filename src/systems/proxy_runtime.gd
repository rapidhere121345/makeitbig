class_name ProxyRuntime
extends RefCounted

## Deterministic, scene-free executor for automation proxy builds.

const MODE_MANUAL := "manual"
const MODE_AUTO := "auto"
const PIPELINE := [&"perception", &"memory_update", &"tactics", &"movement_and_cast", &"confirmation", &"logistics"]
const CORE_SLOTS := [&"perception", &"movement", &"execution", &"memory"]
const PREDICTION_STABLE := "stable"
const PREDICTION_STRAINED := "strained"
const PREDICTION_UNKNOWN := "unknown"

var mode := ""
var mode_locked := false
var cores := {}
var locked_target := ""
var locked_skill := ""


func begin_contract(requested_mode: String) -> Dictionary:
	var normalized := requested_mode.to_lower()
	if normalized not in [MODE_MANUAL, MODE_AUTO]:
		return {"ok": false, "error": "invalid_mode"}
	if mode_locked:
		return {"ok": false, "error": "mode_locked", "mode": mode}
	mode = normalized
	mode_locked = true
	return {"ok": true, "mode": mode}


func end_contract() -> void:
	mode = ""
	mode_locked = false


func equip_core(slot: String, core: Dictionary) -> bool:
	var normalized := StringName(slot.to_lower())
	if normalized not in CORE_SLOTS:
		return false
	cores[normalized] = core.duplicate(true)
	return true


func install_white_proxy(target_id: String, skill_1: String = "piercing_arrow") -> void:
	locked_target = target_id
	locked_skill = skill_1
	cores = make_white_cores()


static func make_white_cores() -> Dictionary:
	return {
		&"perception": {"quality": "white", "capabilities": {"target_count": 1, "recognition": 1.0}},
		&"movement": {"quality": "white", "capabilities": {"pathing": 1.0, "range_control": 1.0}},
		&"execution": {"quality": "white", "capabilities": {"skill_count": 1, "timing": 1.0}},
		&"memory": {"quality": "white", "capabilities": {"target_memory": 1, "rotation_steps": 1}},
	}


func capability_check(requirements: Dictionary) -> Dictionary:
	var checks: Array[Dictionary] = []
	var has_unknown := false
	var has_shortfall := false
	for slot_name in CORE_SLOTS:
		var required: Variant = requirements.get(slot_name, requirements.get(String(slot_name), null))
		var core: Dictionary = cores.get(slot_name, {})
		var check := {
			"slot": String(slot_name),
			"status": "ok",
			"missing": [],
			"shortfalls": [],
		}
		if required == null or not (required is Dictionary) or core.is_empty():
			check.status = "unknown"
			has_unknown = true
			checks.append(check)
			continue
		var capabilities: Dictionary = core.get("capabilities", {})
		for capability in required.keys():
			if not capabilities.has(capability):
				check.missing.append(String(capability))
				has_unknown = true
				continue
			var needed: Variant = required[capability]
			var actual: Variant = capabilities[capability]
			if (needed is int or needed is float) and (actual is int or actual is float):
				if float(actual) < float(needed):
					check.shortfalls.append({"capability": String(capability), "required": needed, "actual": actual})
					has_shortfall = true
			elif actual != needed:
				check.shortfalls.append({"capability": String(capability), "required": needed, "actual": actual})
				has_shortfall = true
		if not check.missing.is_empty():
			check.status = "unknown"
		elif not check.shortfalls.is_empty():
			check.status = "insufficient"
		checks.append(check)
	var prediction := PREDICTION_STABLE
	if has_unknown:
		prediction = PREDICTION_UNKNOWN
	elif has_shortfall:
		prediction = PREDICTION_STRAINED
	return {"prediction": prediction, "checks": checks}


func predict(requirements: Dictionary) -> String:
	return String(capability_check(requirements).prediction)


func failure_record(stage: String, category: String, reason: String, required: Variant = null, actual: Variant = null) -> Dictionary:
	return _failure_record(stage, category, reason, required, actual)


func run_pipeline(context: Dictionary) -> Dictionary:
	if mode != MODE_AUTO or not mode_locked:
		return _failed_result("mode", "rotation", "automatic pipeline requires a locked auto contract", {}, {})
	var state := context.duplicate(true)
	var trace: Array[String] = []
	for stage_name in PIPELINE:
		trace.append(String(stage_name))
		var failure := _check_stage(stage_name, state)
		if not failure.is_empty():
			return {"ok": false, "trace": trace, "failure": _decorate_failure(failure, state)}
	return {"ok": true, "trace": trace, "state": state, "failure": {}}


func simulate_minimal_ranger(encounter: Dictionary = {}) -> Dictionary:
	var target_id := String(encounter.get("target_id", locked_target))
	var skill_id := String(encounter.get("skill", locked_skill))
	var health := float(encounter.get("target_health", 3.0))
	var damage := float(encounter.get("skill_1_damage", 1.0))
	var max_actions := maxi(1, int(encounter.get("max_actions", 16)))
	var context := {
		"visible_targets": [target_id],
		"requested_target": target_id,
		"requested_skill": skill_id,
		"in_range": bool(encounter.get("in_range", true)),
		"path_blocked": bool(encounter.get("path_blocked", false)),
		"skill_ready": true,
		"rotation_steps": 1,
	}
	var pipeline_result := run_pipeline(context)
	if not pipeline_result.ok:
		return pipeline_result
	if damage <= 0.0:
		return _failed_result("execution", "timing", "skill damage must be positive", 0.000001, damage)
	var actions := mini(max_actions, ceili(health / damage))
	var remaining_health := maxf(0.0, health - float(actions) * damage)
	return {
		"ok": remaining_health <= 0.0,
		"target": target_id,
		"skill": skill_id,
		"actions": actions,
		"remaining_health": remaining_health,
		"trace": pipeline_result.trace,
		"failure": {} if remaining_health <= 0.0 else _failure_record("execution", "timing", "action budget exhausted", ceili(health / damage), max_actions),
	}


func _check_stage(stage: StringName, state: Dictionary) -> Dictionary:
	match stage:
		&"perception":
			if not cores.has(&"perception"):
				return _failure_record("perception", "recognition", "core is not installed", "installed core", null)
			var targets: Array = state.get("visible_targets", [])
			var requested_target := String(state.get("requested_target", locked_target))
			if requested_target.is_empty() or requested_target not in targets:
				return _failure_record("perception", "recognition", "locked target is not visible", requested_target, targets)
			if locked_target != "" and requested_target != locked_target:
				return _failure_record("perception", "recognition", "white proxy is locked to one target", locked_target, requested_target)
		&"memory_update":
			if not cores.has(&"memory"):
				return _failure_record("memory_update", "rotation", "core is not installed", "installed core", null)
			var memory_capabilities: Dictionary = cores[&"memory"].get("capabilities", {})
			var steps := int(state.get("rotation_steps", 1))
			if steps > int(memory_capabilities.get("rotation_steps", 0)):
				return _failure_record("memory_update", "rotation", "rotation memory exceeded", steps, memory_capabilities.get("rotation_steps", 0))
		&"movement_and_cast":
			if not cores.has(&"movement"):
				return _failure_record("movement_and_cast", "path", "movement core is not installed", "installed core", null)
			if bool(state.get("path_blocked", false)):
				return _failure_record("movement", "path", "path is blocked", false, true)
			if not bool(state.get("in_range", false)):
				return _failure_record("movement", "path", "cannot reach skill range", true, false)
			if not cores.has(&"execution"):
				return _failure_record("movement_and_cast", "timing", "execution core is not installed", "installed core", null)
			var requested_skill := String(state.get("requested_skill", locked_skill))
			if locked_skill != "" and requested_skill != locked_skill:
				return _failure_record("execution", "rotation", "white proxy can execute skill 1 only", locked_skill, requested_skill)
			if not bool(state.get("skill_ready", false)):
				return _failure_record("execution", "timing", "skill is not ready", true, false)
		&"confirmation":
			if bool(state.get("confirmation_required", false)) and not bool(state.get("action_confirmed", false)):
				return _failure_record("confirmation", "timing", "action result was not confirmed", true, false)
		&"logistics":
			if bool(state.get("pickup_requested", false)) and bool(state.get("pickup_blocked", false)):
				return _failure_record("logistics", "pickup", "requested pickup could not be completed", true, false)
	return {}


func _decorate_failure(failure: Dictionary, state: Dictionary) -> Dictionary:
	var decorated := failure.duplicate(true)
	decorated["tick"] = int(state.get("tick", 0))
	decorated["visible_state"] = state.get("visible_state", {}).duplicate(true)
	decorated["selected_target"] = String(state.get("requested_target", locked_target))
	decorated["candidate_actions"] = state.get("candidate_actions", []).duplicate(true)
	decorated["resources"] = state.get("resources", {}).duplicate(true)
	decorated["cooldowns"] = state.get("cooldowns", {}).duplicate(true)
	decorated["in_range"] = bool(state.get("in_range", false))
	decorated["line_of_sight"] = bool(state.get("line_of_sight", true))
	decorated["timers"] = state.get("timers", {}).duplicate(true)
	decorated["last_confirmed_action"] = state.get("last_confirmed_action", null)
	decorated["interrupted"] = bool(state.get("interrupted", false))
	decorated["path_blocked"] = bool(state.get("path_blocked", false))
	var events: Array = state.get("events", [])
	decorated["events"] = events.slice(maxi(0, events.size() - 20)).duplicate(true)
	return decorated


func _failure_record(stage: String, category: String, reason: String, required: Variant, actual: Variant) -> Dictionary:
	return {
		"id": "%s:%s:%s" % [stage, category, reason.to_snake_case()],
		"stage": stage,
		"category": category,
		"reason": reason,
		"required": required,
		"actual": actual,
	}


func _failed_result(stage: String, category: String, reason: String, required: Variant, actual: Variant) -> Dictionary:
	return {"ok": false, "trace": [], "failure": _failure_record(stage, category, reason, required, actual)}

