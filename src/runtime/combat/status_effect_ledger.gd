class_name RuntimeStatusEffectLedger
extends RefCounted

const InstanceScript := preload("res://src/runtime/combat/status_effect_instance.gd")
const HitScript := preload("res://src/runtime/combat/combat_hit_record.gd")
const CoreResult := preload("res://src/core/result.gd")

const STACK_POLICIES := ["replace", "refresh", "ignore", "stack"]

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
	target_key: String,
	effect_id: String,
	source_key: String,
	duration_ticks: int,
	period_ticks: int,
	magnitude: float,
	damage_type: String = "physical",
	stack_policy: String = "replace",
	max_stacks: int = 1
) -> Dictionary:
	var error := _validate_request(tick, target_key, effect_id, source_key, duration_ticks, period_ticks, magnitude, damage_type, stack_policy, max_stacks)
	if not error.is_empty():
		return CoreResult.failure(error)
	_prepare_tick(tick)
	_expire_at(tick)
	var current: Array = _active_for(target_key, effect_id, tick)
	if stack_policy == "ignore" and not current.is_empty():
		return {"ok": true, "error": "", "changed": false, "reason": "already_active", "snapshot": snapshot(tick)}
	var instance: Variant = _new_instance(tick, target_key, effect_id, source_key, duration_ticks, period_ticks, magnitude, damage_type)
	var next: Array = []
	if stack_policy == "replace":
		next = [instance]
	elif stack_policy == "refresh":
		if current.is_empty():
			next = [instance]
		else:
			var refreshed: Variant = current[0]
			refreshed.source_key = source_key
			refreshed.started_tick = tick
			refreshed.expires_tick = tick + duration_ticks
			refreshed.next_tick = tick + period_ticks if period_ticks > 0 else -1
			refreshed.period_ticks = period_ticks
			refreshed.magnitude = magnitude
			refreshed.damage_type = damage_type
			next = [refreshed]
	else:
		next = current.duplicate()
		if next.size() < max_stacks:
			next.append(instance)
		else:
			next[_oldest_index(next)] = instance
	next.sort_custom(func(left: Variant, right: Variant) -> bool:
		return left.sequence < right.sequence
	)
	_effects[target_key] = next
	return {"ok": true, "error": "", "changed": true, "reason": stack_policy, "snapshot": snapshot(tick)}


func advance(tick: int) -> Dictionary:
	if tick < 0 or tick < _last_tick:
		return CoreResult.failure("stale_status_tick")
	_prepare_tick(tick)
	return {"ok": true, "error": "", "expired": _expire_at(tick), "snapshot": snapshot(tick)}


func collect_periodic_hits(tick: int) -> Array:
	var result: Array = []
	if tick < 0 or tick < _last_tick:
		return result
	_prepare_tick(tick)
	_expire_at(tick)
	for target_key: String in _sorted_target_keys():
		var active: Array = _effects[target_key]
		for instance: Variant in active:
			if instance.period_ticks <= 0 or not instance.active_at(tick) or instance.next_tick < 0 or tick < instance.next_tick:
				continue
			var hit: Variant = HitScript.new()
			hit.tick = tick
			hit.attack_instance_id = "status/%s/%d" % [instance.instance_id, tick]
			hit.source_key = instance.source_key
			hit.target_key = instance.target_key
			hit.part_id = "body"
			hit.damage_group_id = instance.instance_id
			hit.damage_type = instance.damage_type
			hit.contact_kind = "status"
			hit.toi = 0.0
			hit.base_damage = instance.magnitude
			result.append(hit)
			instance.next_tick += instance.period_ticks
	result = HitScript.ordered(result)
	return result


func remove(tick: int, target_key: String, effect_id: String) -> Dictionary:
	if tick < 0 or tick < _last_tick:
		return CoreResult.failure("stale_status_tick")
	if not _valid_id(target_key) or not _valid_id(effect_id):
		return CoreResult.failure("invalid_status_identity")
	_prepare_tick(tick)
	_expire_at(tick)
	var removed: Array[Dictionary] = []
	for instance: Variant in _effects.get(target_key, []):
		if instance.effect_id == effect_id:
			removed.append(instance.snapshot())
	var survivors: Array = []
	for instance: Variant in _effects.get(target_key, []):
		if instance.effect_id != effect_id:
			survivors.append(instance)
	_effects[target_key] = survivors
	if (_effects.get(target_key, []) as Array).is_empty():
		_effects.erase(target_key)
	return {"ok": true, "error": "", "removed": removed, "snapshot": snapshot(tick)}


func snapshot(tick: int = -1) -> Dictionary:
	var read_tick := _last_tick if tick < 0 else tick
	var values: Array[Dictionary] = []
	for target_key: String in _sorted_target_keys():
		var active: Array = _effects[target_key]
		for instance: Variant in active:
			if instance.active_at(read_tick):
				values.append(instance.snapshot())
	values.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_key := "%s|%s|%09d" % [String(left.target_key), String(left.effect_id), int(left.sequence)]
		var right_key := "%s|%s|%09d" % [String(right.target_key), String(right.effect_id), int(right.sequence)]
		return left_key < right_key
	)
	return {"last_tick": _last_tick, "tick": read_tick, "effects": values}


func _new_instance(tick: int, target_key: String, effect_id: String, source_key: String, duration_ticks: int, period_ticks: int, magnitude: float, damage_type: String) -> Variant:
	var instance: Variant = InstanceScript.new()
	instance.instance_id = "%s/%d" % [effect_id, _next_sequence]
	instance.target_key = target_key
	instance.source_key = source_key
	instance.effect_id = effect_id
	instance.started_tick = tick
	instance.expires_tick = tick + duration_ticks
	instance.period_ticks = period_ticks
	instance.next_tick = tick + period_ticks if period_ticks > 0 else -1
	instance.magnitude = magnitude
	instance.damage_type = damage_type
	instance.sequence = _next_sequence
	_next_sequence += 1
	return instance


func _expire_at(tick: int) -> Array[Dictionary]:
	var expired: Array[Dictionary] = []
	for target_key: String in _sorted_target_keys():
		var survivors: Array = []
		for instance: Variant in _effects[target_key]:
			if instance.expires_tick <= tick:
				expired.append({"target_key": target_key, "instance_id": instance.instance_id, "effect_id": instance.effect_id, "tick": tick})
			else:
				survivors.append(instance)
		if survivors.is_empty():
			_effects.erase(target_key)
		else:
			_effects[target_key] = survivors
	return expired


func _active_for(target_key: String, effect_id: String, tick: int) -> Array:
	var result: Array = []
	for instance: Variant in _effects.get(target_key, []):
		if instance.effect_id == effect_id and instance.active_at(tick):
			result.append(instance)
	return result


func _oldest_index(values: Array) -> int:
	var result := 0
	for index in values.size():
		if values[index].sequence < values[result].sequence:
			result = index
	return result


func _prepare_tick(tick: int) -> void:
	_last_tick = maxi(_last_tick, tick)


func _sorted_target_keys() -> Array[String]:
	var result: Array[String] = []
	for key: Variant in _effects.keys():
		result.append(String(key))
	result.sort()
	return result


func _validate_request(tick: int, target_key: String, effect_id: String, source_key: String, duration_ticks: int, period_ticks: int, magnitude: float, damage_type: String, stack_policy: String, max_stacks: int) -> String:
	if tick < 0 or tick < _last_tick:
		return "stale_status_tick"
	if not _valid_id(target_key) or not _valid_id(effect_id) or not _valid_id(source_key) or not _valid_id(damage_type):
		return "invalid_status_identity"
	if duration_ticks <= 0 or period_ticks < 0 or (period_ticks > 0 and period_ticks > duration_ticks):
		return "invalid_status_timing"
	if not is_finite(magnitude) or magnitude < 0.0:
		return "invalid_status_magnitude"
	if stack_policy not in STACK_POLICIES or max_stacks <= 0:
		return "invalid_status_stack_policy"
	return ""


func _valid_id(value: String) -> bool:
	return not value.is_empty() and value == value.strip_edges() and not value.contains(" ")

