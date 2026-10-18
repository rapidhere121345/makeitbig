class_name BossCombatDomain
extends RefCounted

const BigValueScript := preload("res://src/core/big_value.gd")
const SweepScript := preload("res://src/runtime/geometry/spatial_sweep.gd")
const ShapeScript := preload("res://src/runtime/geometry/spatial_shape.gd")
const ContactScript := preload("res://src/runtime/spatial/spatial_contact.gd")
const QueryScript := preload("res://src/runtime/combat/boss_attack_query.gd")
const PathResultScript := preload("res://src/runtime/combat/boss_path_result.gd")
const HitContactScript := preload("res://src/runtime/combat/boss_hit_contact.gd")
const HitRecordScript := preload("res://src/runtime/combat/boss_hit_record.gd")
const HitBufferScript := preload("res://src/runtime/combat/boss_hit_buffer.gd")
const TargetScript := preload("res://src/runtime/combat/boss_target_view.gd")
const DamageResolutionScript := preload("res://src/runtime/combat/damage_resolution.gd")
const DamageBatchScript := preload("res://src/runtime/combat/boss_damage_batch_result.gd")
const DeathSettlementScript := preload("res://src/runtime/combat/death_settlement.gd")
const DeathSettlementResultScript := preload("res://src/runtime/combat/death_settlement_result.gd")
const DeathSettlementNotificationScript := preload("res://src/runtime/combat/death_settlement_notification.gd")

## Room-scoped Boss multipart domain.
##
## query_path() is geometry-only and appends typed facts to hit_buffer. resolve()
## is the DAMAGE_STATUS seam. settle_deaths() is an explicit structural seam
## for the parent kernel/composition root; no scene object or callback is used.

var room_id := ""
var world_revision := -1
var active_tick := -1
var hit_buffer: BossHitBuffer = null
var damage_resolution: DamageResolution = null
var death_settlement: DeathSettlement = null

var last_batch: Dictionary = {}
var last_settlements: Array[Dictionary] = []
var last_settlement_notifications: Array[RefCounted] = []

var _targets: Dictionary = {}
var _pending_deaths: Dictionary = {}
var _settlement_receipts: Dictionary = {}
var _last_source_by_target: Dictionary = {}


func configure(identifier: String, revision: int) -> Dictionary:
	if not _valid_id(identifier) or revision < 0:
		return _failure("invalid_boss_domain_configuration")
	room_id = identifier
	world_revision = revision
	active_tick = -1
	hit_buffer = HitBufferScript.new()
	damage_resolution = DamageResolutionScript.new()
	death_settlement = DeathSettlementScript.new()
	var settlement_configured := death_settlement.configure(room_id, world_revision)
	if not bool(settlement_configured.get("ok", false)):
		return _failure("boss_death_settlement_unavailable")
	last_batch = {}
	last_settlements.clear()
	last_settlement_notifications.clear()
	_targets.clear()
	_pending_deaths.clear()
	_settlement_receipts.clear()
	_last_source_by_target.clear()
	return {"ok": true, "error": ""}


func is_configured() -> bool:
	return not room_id.is_empty() and hit_buffer != null and damage_resolution != null and death_settlement != null


func register_target(target: Variant) -> Dictionary:
	if not is_configured():
		return _failure("boss_domain_not_configured")
	if not target is TargetScript:
		return _failure("invalid_boss_target_type")
	var typed: BossTargetView = target
	var error := typed.validate()
	if not error.is_empty():
		return _failure(error)
	if typed.parts.is_empty():
		return _failure("missing_boss_hurtbox_parts")
	if _targets.has(typed.target_key):
		return _failure("duplicate_boss_target")
	_targets[typed.target_key] = typed
	return {"ok": true, "error": ""}


func target(target_key: String) -> BossTargetView:
	var value: Variant = _targets.get(target_key, null)
	return value if value is TargetScript else null


func target_keys() -> Array[String]:
	var result: Array[String] = []
	for key: Variant in _targets.keys():
		result.append(String(key))
	result.sort()
	return result


## Opens the shared hit buffer and the DamageResolution idempotence window.
func begin_tick(tick: int) -> Dictionary:
	if not is_configured():
		return _failure("boss_domain_not_configured")
	if tick < 0 or (active_tick >= 0 and tick < active_tick):
		return _failure("stale_boss_domain_tick")
	var buffer_result := hit_buffer.begin_tick(tick)
	if not bool(buffer_result.get("ok", false)):
		return buffer_result
	var damage_result := damage_resolution.begin_boss_tick(tick)
	if not bool(damage_result.get("ok", false)):
		return damage_result
	active_tick = tick
	return {"ok": true, "error": ""}


## Resolve one explicit multipart path.  Static opaque contacts are considered
## before dynamic Boss parts, with equal TOI going to the wall.
func query_path(query: Variant, resolver: Variant, source_key: String) -> BossPathResult:
	var result := PathResultScript.new()
	result.tick = active_tick
	if query is QueryScript:
		result.attack_instance_id = (query as BossAttackQuery).attack_instance_id
	if not is_configured() or active_tick < 0:
		result.errors.append("boss_query:domain_not_open")
		return result
	if not query is QueryScript:
		result.errors.append("boss_query:invalid_type")
		return result
	var typed: BossAttackQuery = query
	var query_error := typed.validate()
	if not query_error.is_empty():
		result.errors.append(query_error)
		return result
	if not _valid_id(source_key):
		result.errors.append("boss_query:source_unresolved")
		return result
	if resolver == null or not resolver.has_method("resolve_path"):
		result.errors.append("boss_query:resolver_unavailable")
		return result
	if not typed.target_key.is_empty() and not _targets.has(typed.target_key):
		result.errors.append("boss_query:unknown_target:%s" % typed.target_key)
		return result

	var static_result: Variant = resolver.resolve_path({
		"channel": typed.channel,
		"start": typed.start,
		"displacement": typed.displacement,
		"radius": typed.radius,
		"include_static": true,
		"include_dynamic": false,
		"dynamic_channels": [],
		"piercing": true,
	})
	if not static_result is Dictionary or not bool(static_result.get("ok", false)):
		result.errors.append("boss_query:static_resolution_failed")
		if static_result is Dictionary:
			result.errors.append_array(static_result.get("errors", []) as Array)
		return result

	var blocker_toi := INF
	var blocker_id := ""
	for raw_contact: Variant in static_result.get("contacts", []):
		if not raw_contact is ContactScript:
			continue
		var contact: SpatialContact = raw_contact
		if not _is_opaque_static(contact):
			continue
		if contact.toi < blocker_toi:
			blocker_toi = contact.toi
			blocker_id = contact.source_id

	var contacts: Array[BossHitContact] = []
	for target_key: String in target_keys():
		if not typed.target_key.is_empty() and typed.target_key != target_key:
			continue
		var target: BossTargetView = _targets[target_key]
		if not target.alive:
			continue
		for part: BossHurtbox in target.parts_snapshot():
			if not part.is_hittable():
				continue
			var raw_hit := SweepScript.sweep_circle_circle(
				typed.start,
				typed.displacement,
				typed.radius,
				part.world_center(target.position),
				part.radius,
				"boss_part",
				false
			)
			if raw_hit.is_empty():
				continue
			if is_finite(blocker_toi) and float(raw_hit.get("toi", 1.0)) >= blocker_toi - ShapeScript.DIRECTION_EPSILON:
				continue
			var hit_contact: BossHitContact = HitContactScript.new()
			hit_contact.target_key = target_key
			hit_contact.part_id = part.part_id
			hit_contact.damage_group_id = part.damage_group_id
			hit_contact.toi = float(raw_hit.get("toi", 0.0))
			hit_contact.contact_point = raw_hit.get("point", Vector2.ZERO)
			hit_contact.priority = part.priority
			contacts.append(hit_contact)
	contacts = HitContactScript.ordered(contacts)
	if not typed.piercing and contacts.size() > 1:
		contacts = [contacts[0]]

	var records: Array[BossHitRecord] = []
	for contact: BossHitContact in contacts:
		records.append(HitRecordScript.from_query(typed, contact, active_tick, source_key))
	var appended := hit_buffer.append_batch(records)
	if not bool(appended.get("ok", false)):
		result.errors.append(String(appended.get("error", "boss_hit_buffer_rejected")))
		return result

	var wall_reached := false
	if is_finite(blocker_toi):
		wall_reached = typed.piercing or contacts.is_empty() or blocker_toi <= contacts[0].toi + ShapeScript.DIRECTION_EPSILON
	result.ok = true
	result.hit_contacts = contacts
	result.blocked_by_static = wall_reached
	result.blocker_id = blocker_id if wall_reached else ""
	result.clipped = wall_reached or (not typed.piercing and not contacts.is_empty())
	if wall_reached:
		result.stop_toi = blocker_toi
	elif not typed.piercing and not contacts.is_empty():
		result.stop_toi = contacts[0].toi
	else:
		result.stop_toi = 1.0
	result.end_point = typed.start + typed.displacement * result.stop_toi
	return result


## DAMAGE_STATUS phase.  Hits are consumed before targets are committed.
func resolve(tick: int) -> Dictionary:
	var opened := begin_tick(tick)
	if not bool(opened.get("ok", false)):
		return opened
	var hits := hit_buffer.take_ordered()
	var targets: Array[BossTargetView] = []
	for key: String in target_keys():
		targets.append(_targets[key])
	# Admission is a typed target fact, so the domain consumes it before the
	# damage resolver. A blocked hit becomes a suppression receipt and is never
	# submitted to DamageResolution or allowed to affect health/death state.
	var admitted_hits: Array[BossHitRecord] = []
	var suppressed: Array[Dictionary] = []
	for hit: BossHitRecord in hits:
		var target: BossTargetView = _targets.get(hit.target_key, null)
		if target != null and target.admission_blocked:
			var blocked := hit.snapshot()
			blocked["blocked"] = true
			blocked["reason"] = target.admission_reason
			suppressed.append(blocked)
			continue
		admitted_hits.append(hit)
	var batch: Variant = damage_resolution.resolve_boss(tick, admitted_hits, targets)
	if not batch is DamageBatchScript:
		return _failure("boss_damage_resolution_invalid_result")
	batch.suppressed.append_array(suppressed)
	for outcome: BossDamageOutcome in batch.outcomes:
		var target: BossTargetView = _targets.get(outcome.target_key, null)
		if target == null:
			return _failure("boss_damage_target_disappeared")
		var committed := target.commit_health(outcome.remaining_health)
		if not bool(committed.get("ok", false)):
			return _failure("boss_damage_commit_failed")
		_last_source_by_target[outcome.target_key] = outcome.source_key
		if outcome.lethal and not _pending_deaths.has(outcome.target_key) and not _settlement_receipts.has(outcome.target_key):
			_pending_deaths[outcome.target_key] = _death_request(target, tick)
	last_batch = batch.snapshot()
	return {"ok": true, "error": "", "batch": last_batch}


## Structural/death phase seam for the parent kernel.  Repeating the call
## returns no new request and cannot create another loot/encounter receipt.
func settle_deaths(tick: int) -> Dictionary:
	if not is_configured() or tick != active_tick:
		return _failure("boss_settlement_tick_mismatch")
	var new_settlements: Array[Dictionary] = []
	var keys: Array[String] = []
	for key: Variant in _pending_deaths.keys():
		keys.append(String(key))
	keys.sort()
	for key: String in keys:
		var settled: Dictionary = death_settlement.settle(_pending_deaths[key])
		if not bool(settled.get("ok", false)):
			return settled
		var snapshot: Dictionary = settled.get("snapshot", {}).duplicate(true)
		_settlement_receipts[key] = snapshot
		last_settlements.append(snapshot)
		new_settlements.append(snapshot)
		var value: Variant = settled.get("value", null)
		if value is DeathSettlementResultScript and value.encounter_notification is DeathSettlementNotificationScript:
			last_settlement_notifications.append(value.encounter_notification)
		_pending_deaths.erase(key)
	return {
		"ok": true,
		"error": "",
		"changed": not new_settlements.is_empty(),
		"settlements": new_settlements,
		"duplicate_keys": _settlement_receipts.keys() if new_settlements.is_empty() else [],
	}


func snapshot() -> Dictionary:
	var target_values: Array[Dictionary] = []
	for key: String in target_keys():
		target_values.append((_targets[key] as BossTargetView).snapshot())
	return {
		"room_id": room_id,
		"world_revision": world_revision,
		"active_tick": active_tick,
		"targets": target_values,
		"hit_buffer": hit_buffer.snapshot() if hit_buffer != null else {},
		"last_batch": last_batch.duplicate(true),
		"last_settlements": last_settlements.duplicate(true),
		"settled_keys": _settlement_receipts.keys(),
	}


func _death_request(target: BossTargetView, tick: int) -> Dictionary:
	return {
		"tick": tick,
		"room_id": room_id,
		"world_revision": world_revision,
		"entity_key": target.target_key,
		"source_key": String(_last_source_by_target.get(target.target_key, "system")),
		"spawn_key": target.spawn_key,
		"archetype_id": target.archetype_id,
		"position": target.position,
		"death_reason": "damage",
		"loot_source": "enemy_death",
		"loot_tags": target.loot_tags.duplicate(),
		"can_drop": true,
	}


func _is_opaque_static(contact: SpatialContact) -> bool:
	if contact.kind != ContactScript.KIND_STATIC_SURFACE and contact.kind != ContactScript.KIND_OVERLAY_SURFACE:
		return false
	return String(contact.response.get("reason", "")) == "environment_opaque" and not bool(contact.response.get("hit", false))


static func _valid_id(value: String) -> bool:
	return not value.is_empty() and value == value.strip_edges() and not value.contains(" ")


static func _failure(error: String) -> Dictionary:
	return {"ok": false, "error": error}
