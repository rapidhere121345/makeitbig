class_name DamageResolution
extends RefCounted

const HitScript := preload("res://src/runtime/combat/combat_hit_record.gd")
const TargetScript := preload("res://src/runtime/combat/combat_target_view.gd")
const OutcomeScript := preload("res://src/runtime/combat/damage_outcome.gd")
const BatchScript := preload("res://src/runtime/combat/damage_batch_result.gd")
const BossHitScript := preload("res://src/runtime/combat/boss_hit_record.gd")
const BossTargetScript := preload("res://src/runtime/combat/boss_target_view.gd")
const BossOutcomeScript := preload("res://src/runtime/combat/boss_damage_outcome.gd")
const BossBatchScript := preload("res://src/runtime/combat/boss_damage_batch_result.gd")
const BossDamageValueScript := preload("res://src/runtime/combat/boss_damage_value.gd")
const BigValueScript := preload("res://src/core/big_value.gd")
const CoreResult := preload("res://src/core/result.gd")

var _boss_window_tick := -1
var _boss_settled_groups: Dictionary = {}


## Resolves an ordered hit batch against detached target views. It never mutates
## a target or reaches into a scene node. The caller commits the returned
## outcomes during the damage phase.
func resolve(tick: int, raw_hits: Array, raw_targets: Array) -> Variant:
	var result: Variant = BatchScript.new()
	result.tick = tick
	if tick < 0:
		result.rejected.append({"reason": "invalid_damage_tick"})
		return result
	var targets: Dictionary = {}
	for raw_target: Variant in raw_targets:
		var parsed_target: Dictionary = TargetScript.from_data(raw_target.snapshot() if raw_target is Object and raw_target.has_method("snapshot") else raw_target)
		if not bool(parsed_target.get("ok", false)):
			result.rejected.append({"reason": parsed_target.get("error", "invalid_target_view")})
			continue
		var target: Variant = parsed_target["value"]
		targets[target.target_key] = target
	var hits: Array = []
	for raw_hit: Variant in raw_hits:
		var parsed_hit: Dictionary = HitScript.from_data(raw_hit.snapshot() if raw_hit is Object and raw_hit.has_method("snapshot") else raw_hit)
		if not bool(parsed_hit.get("ok", false)):
			result.rejected.append({"reason": parsed_hit.get("error", "invalid_hit")})
			continue
		var hit: Variant = parsed_hit["value"]
		if hit.tick != tick:
			result.rejected.append({"reason": "hit_tick_mismatch", "attack_instance_id": hit.attack_instance_id})
			continue
		hits.append(hit)
	var ordered: Array = HitScript.ordered(hits)
	var seen_attack_targets: Dictionary = {}
	var health: Dictionary = {}
	var alive: Dictionary = {}
	for target_key: String in targets.keys():
		var target: Variant = targets[target_key]
		health[target_key] = target.health
		alive[target_key] = target.alive and target.health > 0.0
	for hit: Variant in ordered:
		if not targets.has(hit.target_key):
			result.rejected.append({"reason": "unknown_target", "target_key": hit.target_key})
			continue
		if not bool(alive[hit.target_key]):
			continue
		var dedupe: String = hit.dedupe_key()
		if not hit.allow_repeat_target and seen_attack_targets.has(dedupe):
			continue
		seen_attack_targets[dedupe] = true
		var target: Variant = targets[hit.target_key]
		var requested: float = maxf(0.0, hit.base_damage)
		var resistance: float = target.resistance_for(hit.damage_type)
		var applied: float = maxf(0.0, requested * (1.0 - resistance))
		var remaining: float = maxf(0.0, float(health[hit.target_key]) - applied)
		health[hit.target_key] = remaining
		var outcome: Variant = OutcomeScript.new()
		outcome.tick = tick
		outcome.attack_instance_id = hit.attack_instance_id
		outcome.source_key = hit.source_key
		outcome.target_key = hit.target_key
		outcome.part_id = hit.part_id
		outcome.damage_type = hit.damage_type
		outcome.requested_damage = requested
		outcome.applied_damage = applied
		outcome.remaining_health = remaining
		outcome.lethal = remaining <= 0.0
		result.outcomes.append(outcome)
		if outcome.lethal:
			alive[hit.target_key] = false
			result.deaths.append(hit.target_key)
	result.deaths.sort()
	result.outcomes.sort_custom(func(left: Variant, right: Variant) -> bool:
		var left_key: String = "%s|%s|%s" % [left.target_key, left.attack_instance_id, left.part_id]
		var right_key: String = "%s|%s|%s" % [right.target_key, right.attack_instance_id, right.part_id]
		return left_key < right_key
	)
	return result


## Opens the Boss idempotence window for one fixed tick.  A later tick starts a
## fresh attack window; a stale tick is rejected before any state changes.
func begin_boss_tick(tick: int) -> Dictionary:
	if tick < 0 or (_boss_window_tick >= 0 and tick < _boss_window_tick):
		return CoreResult.failure("stale_boss_damage_tick")
	if tick > _boss_window_tick:
		_boss_window_tick = tick
		_boss_settled_groups.clear()
	return {"ok": true, "error": ""}


## BigValue/milli multipart DamageResolution path.  It resolves detached
## BossTargetView values and returns detached outcomes; the room domain commits
## those values after the batch is complete.
func resolve_boss(tick: int, raw_hits: Array, raw_targets: Array) -> Variant:
	var result: Variant = BossBatchScript.new()
	result.tick = tick
	var opened := begin_boss_tick(tick)
	if not bool(opened.get("ok", false)):
		result.rejected.append({"reason": String(opened.get("error", "stale_boss_damage_tick"))})
		return result

	var targets: Dictionary = {}
	for raw_target: Variant in raw_targets:
		if not raw_target is BossTargetScript:
			result.rejected.append({"reason": "invalid_boss_target_type"})
			continue
		var target: BossTargetView = raw_target
		var target_error := target.validate()
		if not target_error.is_empty():
			result.rejected.append({"reason": target_error})
			continue
		if targets.has(target.target_key):
			result.rejected.append({"reason": "duplicate_boss_target", "target_key": target.target_key})
			continue
		targets[target.target_key] = target

	var hits: Array[BossHitRecord] = []
	for raw_hit: Variant in raw_hits:
		if not raw_hit is BossHitScript:
			result.rejected.append({"reason": "invalid_boss_hit_type"})
			continue
		var hit: BossHitRecord = raw_hit
		var hit_error := hit.validate()
		if not hit_error.is_empty():
			result.rejected.append({"reason": hit_error})
			continue
		if hit.tick != tick:
			result.rejected.append({"reason": "boss_hit_tick_mismatch", "attack_instance_id": hit.attack_instance_id})
			continue
		hits.append(hit)

	var health: Dictionary = {}
	var alive: Dictionary = {}
	for target_key: String in targets.keys():
		var target: BossTargetView = targets[target_key]
		health[target_key] = target.health.duplicate_value()
		alive[target_key] = target.alive

	for hit: BossHitRecord in BossHitScript.ordered(hits):
		if not targets.has(hit.target_key):
			result.rejected.append({"reason": "unknown_boss_target", "target_key": hit.target_key})
			continue
		if not bool(alive[hit.target_key]):
			result.suppressed.append({"reason": "boss_target_dead", "dedupe_key": hit.dedupe_key()})
			continue
		var dedupe_key := hit.dedupe_key()
		if _boss_settled_groups.has(dedupe_key):
			result.suppressed.append({"reason": "duplicate_boss_attack_window", "dedupe_key": dedupe_key})
			continue
		_boss_settled_groups[dedupe_key] = true

		var requested: BigValue = hit.damage.to_big_value()
		if requested == null:
			result.rejected.append({"reason": "invalid_boss_damage_value", "dedupe_key": dedupe_key})
			_boss_settled_groups.erase(dedupe_key)
			continue
		var resolved := _resolve_big_damage(health[hit.target_key] as BigValue, requested)
		if not bool(resolved.get("ok", false)):
			result.rejected.append({"reason": String(resolved.get("error", "invalid_boss_damage_resolution")), "dedupe_key": dedupe_key})
			_boss_settled_groups.erase(dedupe_key)
			continue
		var outcome: BossDamageOutcome = BossOutcomeScript.new()
		outcome.tick = tick
		outcome.attack_instance_id = hit.attack_instance_id
		outcome.source_key = hit.source_key
		outcome.target_key = hit.target_key
		outcome.part_id = hit.part_id
		outcome.damage_group_id = hit.damage_group_id
		outcome.damage_type = hit.damage_type
		outcome.requested_damage = hit.damage.duplicate_value()
		outcome.applied_damage = BossDamageValueScript.from_big(resolved["applied"] as BigValue)
		outcome.remaining_health = (resolved["remaining"] as BigValue).duplicate_value()
		outcome.lethal = bool(resolved["lethal"])
		result.outcomes.append(outcome)
		health[hit.target_key] = outcome.remaining_health.duplicate_value()
		if outcome.lethal:
			alive[hit.target_key] = false
			if not result.deaths.has(hit.target_key):
				result.deaths.append(hit.target_key)
	result.deaths.sort()
	return result


func _resolve_big_damage(current: BigValue, requested: BigValue) -> Dictionary:
	if not _valid_big(current) or not _valid_big(requested):
		return CoreResult.failure("invalid_boss_health_or_damage")
	var comparison := current.compare(requested)
	if comparison <= 0:
		return {
			"ok": true,
			"applied": current.duplicate_value(),
			"remaining": BigValueScript.from_float(0.0),
			"lethal": true,
		}
	if current.layer == 0 and requested.layer == 0:
		var remaining := BigValueScript.from_float(maxf(0.0, current.magnitude - requested.magnitude))
		return {
			"ok": remaining != null,
			"applied": requested.duplicate_value(),
			"remaining": remaining,
			"lethal": remaining != null and remaining.is_zero(),
		}
	# BigValue deliberately has no lossy subtraction operator.  When a finite
	# lower-layer hit cannot be represented in the target's layer, retain the
	# exact target projection and report the exact applied payload.
	return {
		"ok": true,
		"applied": requested.duplicate_value(),
		"remaining": current.duplicate_value(),
		"lethal": false,
	}


func _valid_big(value: Variant) -> bool:
	return value is BigValueScript and value.layer >= 0 and is_finite(value.magnitude) and (value.layer > 0 or value.magnitude >= 0.0)

