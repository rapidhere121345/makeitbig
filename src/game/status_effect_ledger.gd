class_name StatusEffectLedger
extends RefCounted

## Room-local timed status authority.
##
## A ledger stores only resolved instances. Content and combat rules decide
## when to apply an effect; this object owns time ordering, expiry, stacking,
## and detached observation. It deliberately does not evaluate modifiers.

const STACK_POLICIES: Array[String] = ["replace", "refresh", "stack", "ignore"]
const CoreResult := preload("res://src/core/result.gd")
const MODIFIER_OPERATIONS: Array[String] = ["add", "multiply", "multiply_bonus", "reduce_percent"]
const MODIFIER_FIELDS: Array[String] = ["parameter", "operation", "value"]

var _effects: Dictionary = {}
var _next_sequence := 1
var _last_tick := -1


func reset(initial_tick: int = -1) -> Dictionary:
	if initial_tick < -1:
		return CoreResult.failure("invalid_initial_tick")
	_effects.clear()
	_next_sequence = 1
	_last_tick = initial_tick
	return {"ok": true, "error": ""}


func apply(
	tick: int,
	effect_id: String,
	source_id: String,
	duration_ticks: int,
	magnitude: float,
	stack_policy: String = "replace",
	max_stacks: int = 1,
	modifier: Dictionary = {}
) -> Dictionary:
	var validation := _validate_request(tick, effect_id, source_id, duration_ticks, magnitude, stack_policy, max_stacks, modifier)
	if not bool(validation.get("ok", false)):
		return validation
	_prepare_tick(tick)
	_expire_at(tick)
	var normalized_id := effect_id.strip_edges()
	var existing: Array[Dictionary] = _active_for(normalized_id, tick)
	if stack_policy == "ignore" and not existing.is_empty():
		return {
			"ok": true, "error": "", "changed": false, "reason": "already_active",
			"effect": _effect_snapshot(existing[0]), "snapshot": snapshot(tick),
		}

	var instance := _new_instance(tick, normalized_id, source_id.strip_edges(), duration_ticks, magnitude, modifier)
	var next_effects: Array[Dictionary] = []
	var applied_effect: Dictionary = instance
	if stack_policy == "replace":
		next_effects = [instance]
	elif stack_policy == "refresh":
		if existing.is_empty():
			next_effects = [instance]
		else:
			var refreshed := existing[0].duplicate(true)
			refreshed["source_id"] = source_id.strip_edges()
			refreshed["started_tick"] = tick
			refreshed["expires_tick"] = tick + duration_ticks
			refreshed["magnitude"] = magnitude
			refreshed["modifier"] = modifier.duplicate(true)
			next_effects = [refreshed]
			applied_effect = refreshed
	else:
		next_effects = existing.duplicate(true)
		if next_effects.size() < max_stacks:
			next_effects.append(instance)
		else:
			var replace_index := _oldest_index(next_effects)
			next_effects[replace_index] = instance
			applied_effect = instance
	_effects[normalized_id] = next_effects
	return {
		"ok": true, "error": "", "changed": true, "reason": stack_policy,
		"effect": _effect_snapshot(applied_effect), "snapshot": snapshot(tick),
	}


func advance(tick: int) -> Dictionary:
	if tick < 0 or tick < _last_tick:
		return CoreResult.failure("stale_status_tick")
	_prepare_tick(tick)
	var expired := _expire_at(tick)
	return {"ok": true, "error": "", "expired": expired, "snapshot": snapshot(tick)}


func remove(tick: int, effect_id: String) -> Dictionary:
	if tick < 0 or tick < _last_tick:
		return CoreResult.failure("stale_status_tick")
	if not _valid_id(effect_id):
		return CoreResult.failure("invalid_effect_id")
	_prepare_tick(tick)
	_expire_at(tick)
	var normalized_id := effect_id.strip_edges()
	var removed: Array[Dictionary] = []
	for effect: Dictionary in _active_for(normalized_id, tick):
		removed.append(_effect_snapshot(effect))
	_effects.erase(normalized_id)
	return {"ok": true, "error": "", "removed": removed, "snapshot": snapshot(tick)}


func has_active(tick: int, effect_id: String) -> bool:
	if tick < 0 or tick < _last_tick or not _valid_id(effect_id):
		return false
	return not _active_for(effect_id.strip_edges(), tick).is_empty()


func snapshot(tick: int = -1) -> Dictionary:
	var read_tick := _last_tick if tick < 0 else tick
	if read_tick < -1 or read_tick < _last_tick:
		return CoreResult.failure("stale_status_tick")
	var effects: Array[Dictionary] = []
	var ids: Array[String] = []
	for value: Variant in _effects.keys():
		ids.append(String(value))
	ids.sort()
	for effect_id: String in ids:
		var active := _active_for(effect_id, read_tick)
		active.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
			return int(left.sequence) < int(right.sequence)
		)
		for effect: Dictionary in active:
			effects.append(_effect_snapshot(effect))
	return {"ok": true, "error": "", "tick": read_tick, "last_tick": _last_tick, "effects": effects}


func _validate_request(
	tick: int,
	effect_id: String,
	source_id: String,
	duration_ticks: int,
	magnitude: float,
	stack_policy: String,
	max_stacks: int,
	modifier: Dictionary
) -> Dictionary:
	if tick < 0 or tick < _last_tick:
		return CoreResult.failure("stale_status_tick")
	if not _valid_id(effect_id):
		return CoreResult.failure("invalid_effect_id")
	if not _valid_id(source_id):
		return CoreResult.failure("invalid_source_id")
	if duration_ticks <= 0:
		return CoreResult.failure("invalid_duration_ticks")
	if not is_finite(magnitude):
		return CoreResult.failure("invalid_magnitude")
	if stack_policy not in STACK_POLICIES:
		return CoreResult.failure("invalid_stack_policy")
	if max_stacks <= 0:
		return CoreResult.failure("invalid_max_stacks")
	var modifier_error := _validate_modifier(modifier)
	if not modifier_error.is_empty():
		return CoreResult.failure(modifier_error)
	return {"ok": true, "error": ""}


func _validate_modifier(modifier: Dictionary) -> String:
	if modifier.is_empty():
		return ""
	for key: Variant in modifier.keys():
		if not key is String or String(key) not in MODIFIER_FIELDS:
			return "unknown_modifier_field:%s" % String(key)
	for field: String in MODIFIER_FIELDS:
		if not modifier.has(field):
			return "missing_modifier_field:%s" % field
	var parameter := String(modifier.get("parameter", ""))
	var operation := String(modifier.get("operation", ""))
	if not _valid_id(parameter):
		return "invalid_modifier_parameter"
	if operation not in MODIFIER_OPERATIONS:
		return "invalid_modifier_operation"
	var value: Variant = modifier.get("value")
	if (typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT) or not is_finite(float(value)):
		return "invalid_modifier_value"
	return ""


func _new_instance(tick: int, effect_id: String, source_id: String, duration_ticks: int, magnitude: float, modifier: Dictionary) -> Dictionary:
	var sequence := _next_sequence
	_next_sequence += 1
	return {
		"instance_id": "%s/%d" % [effect_id, sequence],
		"sequence": sequence,
		"effect_id": effect_id,
		"source_id": source_id,
		"started_tick": tick,
		"expires_tick": tick + duration_ticks,
		"magnitude": magnitude,
		"modifier": modifier.duplicate(true),
	}


func _prepare_tick(tick: int) -> void:
	_last_tick = maxi(_last_tick, tick)


func _expire_at(tick: int) -> Array[Dictionary]:
	var expired: Array[Dictionary] = []
	var ids: Array[String] = []
	for value: Variant in _effects.keys():
		ids.append(String(value))
	ids.sort()
	for effect_id: String in ids:
		var survivors: Array[Dictionary] = []
		for effect: Dictionary in _effects[effect_id]:
			if int(effect.expires_tick) <= tick:
				expired.append({
					"type": "expired", "effect_id": effect.effect_id,
					"instance_id": effect.instance_id, "tick": tick,
				})
			else:
				survivors.append(effect)
		if survivors.is_empty():
			_effects.erase(effect_id)
		else:
			_effects[effect_id] = survivors
	expired.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return String(left.instance_id) < String(right.instance_id)
	)
	return expired


func _active_for(effect_id: String, tick: int) -> Array[Dictionary]:
	var active: Array[Dictionary] = []
	for effect: Dictionary in (_effects.get(effect_id, []) as Array):
		if int(effect.expires_tick) > tick:
			active.append(effect)
	return active


func _oldest_index(effects: Array[Dictionary]) -> int:
	var index := 0
	for candidate in effects.size():
		if int(effects[candidate].sequence) < int(effects[index].sequence):
			index = candidate
	return index


func _effect_snapshot(effect: Dictionary) -> Dictionary:
	return effect.duplicate(true)


static func _valid_id(value: String) -> bool:
	if value.strip_edges().is_empty() or value != value.strip_edges():
		return false
	for character: String in value:
		if character in [" ", "\t", "\n", "\r"]:
			return false
	return true
