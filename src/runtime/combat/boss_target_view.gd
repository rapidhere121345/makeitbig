class_name BossTargetView
extends RefCounted

class AdmissionState:
	var blocked := false
	var reason := ""

	func snapshot() -> Dictionary:
		return {"blocked": blocked, "reason": reason}

const BigValueScript := preload("res://src/core/big_value.gd")
const HurtboxScript := preload("res://src/runtime/combat/boss_hurtbox.gd")

## Detached Boss target state consumed by the BigValue DamageResolution path.

var target_key := ""
var health: BigValue = null
var maximum_health: BigValue = null
var alive := true
var position := Vector2.ZERO
var archetype_id := ""
var spawn_key := ""
var loot_tags: Array[String] = []
var parts: Array[BossHurtbox] = []
## Typed admission state owned by the detached target. New targets are open by
## default; callers must use set_admission() to close the gate.
var admission: AdmissionState = AdmissionState.new()

var admission_blocked: bool:
	get:
		return admission.blocked

var admission_reason: String:
	get:
		return admission.reason


static func make(
	identifier: String,
	maximum: BigValue,
	feet_position: Vector2,
	archetype: String = "",
	spawn: String = "",
	tags: Array[String] = []
) -> BossTargetView:
	var result := BossTargetView.new()
	result.target_key = identifier
	result.maximum_health = maximum.duplicate_value() if maximum != null else null
	result.health = maximum.duplicate_value() if maximum != null else null
	result.position = feet_position
	result.archetype_id = archetype
	result.spawn_key = spawn
	result.loot_tags = tags.duplicate()
	return result


func validate() -> String:
	if not _valid_id(target_key) or not position.is_finite():
		return "invalid_boss_target_identity"
	if not _valid_big(maximum_health) or maximum_health.is_zero():
		return "invalid_boss_target_maximum"
	if not _valid_big(health) or health.compare(maximum_health) > 0 or health.compare(BigValueScript.from_float(0.0)) < 0:
		return "invalid_boss_target_health"
	if alive != (health.compare(BigValueScript.from_float(0.0)) > 0):
		return "invalid_boss_target_alive_state"
	if admission == null:
		return "invalid_boss_target_admission"
	if admission.blocked:
		if admission.reason.is_empty() or not _valid_id(admission.reason):
			return "invalid_boss_target_admission"
	elif not admission.reason.is_empty():
		return "invalid_boss_target_admission"
	if (not archetype_id.is_empty() and not _valid_id(archetype_id)) or (not spawn_key.is_empty() and not _valid_id(spawn_key)):
		return "invalid_boss_target_spawn_identity"
	for tag: String in loot_tags:
		if not _valid_id(tag):
			return "invalid_boss_target_loot_tag"
	for part: BossHurtbox in parts:
		var error := part.validate()
		if not error.is_empty() or part.target_key != target_key:
			return "invalid_boss_target_part"
	return ""


func set_admission(next_blocked: bool, next_reason: String = "") -> Dictionary:
	if next_blocked:
		if next_reason.is_empty() or not _valid_id(next_reason):
			return _failure("invalid_boss_target_admission")
	elif not next_reason.is_empty():
		return _failure("invalid_boss_target_admission")
	if admission == null:
		return _failure("invalid_boss_target_admission")
	admission.blocked = next_blocked
	admission.reason = next_reason
	return {"ok": true, "error": ""}


func add_part(part: Variant) -> Dictionary:
	if not part is HurtboxScript:
		return _failure("invalid_boss_hurtbox_type")
	var typed: BossHurtbox = part
	var error := typed.validate()
	if not error.is_empty():
		return _failure(error)
	if typed.target_key.is_empty():
		typed.target_key = target_key
	elif typed.target_key != target_key:
		return _failure("boss_hurtbox_target_mismatch")
	for existing: BossHurtbox in parts:
		if existing.part_id == typed.part_id:
			return _failure("duplicate_boss_hurtbox_part")
	parts.append(typed)
	parts.sort_custom(func(left: BossHurtbox, right: BossHurtbox) -> bool:
		return left.sort_key() < right.sort_key()
	)
	return {"ok": true, "error": ""}


func parts_snapshot() -> Array[BossHurtbox]:
	var result: Array[BossHurtbox] = []
	for part: BossHurtbox in parts:
		result.append(part.duplicate_value())
	return result


func commit_health(value: BigValue) -> Dictionary:
	if not _valid_big(value) or value.compare(maximum_health) > 0:
		return _failure("invalid_boss_resolved_health")
	health = value.duplicate_value()
	alive = not health.is_zero()
	return {"ok": true, "error": ""}


func set_part_state(part_id_value: String, next_active: bool, next_broken: bool) -> Dictionary:
	for part: BossHurtbox in parts:
		if part.part_id != part_id_value:
			continue
		part.active = next_active
		part.broken = next_broken
		return {"ok": true, "error": ""}
	return _failure("unknown_boss_hurtbox_part")


func snapshot() -> Dictionary:
	var part_values: Array[Dictionary] = []
	for part: BossHurtbox in parts:
		part_values.append(part.snapshot())
	return {
		"target_key": target_key,
		"health": _big_snapshot(health),
		"maximum_health": _big_snapshot(maximum_health),
		"alive": alive,
		"position": position,
		"archetype_id": archetype_id,
		"spawn_key": spawn_key,
		"loot_tags": loot_tags.duplicate(),
		"admission": admission.snapshot() if admission != null else {},
		"admission_blocked": admission_blocked,
		"admission_reason": admission_reason,
		"parts": part_values,
	}


static func _valid_big(value: Variant) -> bool:
	return value is BigValueScript and value.layer >= 0 and is_finite(value.magnitude) and (value.layer > 0 or value.magnitude >= 0.0)


static func _big_snapshot(value: BigValue) -> Dictionary:
	return {"layer": value.layer, "magnitude": value.magnitude} if value != null else {}


static func _valid_id(value: String) -> bool:
	return not value.is_empty() and value == value.strip_edges() and not value.contains(" ")


static func _failure(error: String) -> Dictionary:
	return {"ok": false, "error": error}
