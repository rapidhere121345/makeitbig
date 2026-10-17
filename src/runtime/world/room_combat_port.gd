class_name RoomCombatPort
extends SimCombatPort

## The room-facing combat boundary for the fixed-tick kernel.
##
## Spatial producers submit SimHit facts only. This port translates those
## facts into CombatHitRecord values, builds detached CombatTargetView values,
## invokes DamageResolution, and commits the returned health values to actor
## records. It is the only production path that turns a hit into damage.

const DamageResolutionScript := preload("res://src/runtime/combat/damage_resolution.gd")
const StatusLedgerScript := preload("res://src/runtime/combat/status_effect_ledger.gd")
const DeathSettlementScript := preload("res://src/runtime/combat/death_settlement.gd")
const HitRecordScript := preload("res://src/runtime/combat/combat_hit_record.gd")
const ActorStateScript := preload("res://src/runtime/world/actor_state.gd")
const BossDomainScript := preload("res://src/runtime/combat/boss_combat_domain.gd")
const HitAdmissionPortScript := preload("res://src/runtime/combat/room_hit_admission_port.gd")
const DeathSettlementResultScript := preload("res://src/runtime/combat/death_settlement_result.gd")
const DeathSettlementNotificationScript := preload("res://src/runtime/combat/death_settlement_notification.gd")

## Typed contact kinds whose integer SimHit amount carries milli-damage.
## SimHit transports whole units only; production ranger arrows freeze their
## float damage intent at milli precision and this boundary converts it back
## exactly once, before DamageResolution sees the record.
const MILLI_DAMAGE_CONTACT_KINDS: Array[StringName] = [&"ranger_arrow", &"hostile_attack"]
const PLAYER_CONTACT_KINDS: Array[StringName] = [&"hazard", &"hostile_attack"]

var actors: Variant = null
var damage_resolution: Variant = null
var status_ledger: Variant = null
var death_settlement: Variant = null
var room_loot: Variant = null
var player_rule_port: Variant = null
var room_id := ""
var world_revision := -1
## Optional hit admission gate, evaluated on the translated CombatHitRecord
## before DamageResolution. Production uses it to keep legacy semantics that
## belong to the damage boundary: an arrow only admits its locked non-boss
## target, and a periodic barrier suppresses the hit before resolution.
var hit_admission_port: RoomHitAdmissionPort = null

var last_batch: Dictionary = {}
var last_settlements: Array[Dictionary] = []
## Admitted hit record snapshots for this tick, in HitBuffer order. They carry
## contact points and typed attack identity for the room reconcile boundary.
var last_hits: Array[Dictionary] = []
## Hits consumed from the tick's HitBuffer after admission, per resolve.
var consumed_hits := 0
var _last_source_by_target: Dictionary = {}
var boss_domain: BossCombatDomain = null
var last_boss_batch: Dictionary = {}
var last_boss_settlements: Array[Dictionary] = []
var last_boss_death_notifications: Array[RefCounted] = []
var _boss_notification_cursor := 0
var pending_player_contacts: Array[Dictionary] = []
var last_player_contact_receipts: Array[Dictionary] = []
var last_player_hazard_receipts: Array[Dictionary] = []
var _settled_player_attack_ids: Dictionary = {}


func bind(actor_access: Variant) -> void:
	actors = actor_access
	if actors == null:
		return
	room_id = String(actors.room_instance_id)
	world_revision = int(actors.world_revision)
	if damage_resolution == null:
		damage_resolution = DamageResolutionScript.new()
	if status_ledger == null:
		status_ledger = StatusLedgerScript.new()
	status_ledger.reset()
	if death_settlement == null:
		death_settlement = DeathSettlementScript.new()
	death_settlement.configure(room_id, world_revision)
	last_batch = {}
	last_settlements.clear()
	last_hits.clear()
	consumed_hits = 0
	_last_source_by_target.clear()
	boss_domain = null
	last_boss_batch = {}
	last_boss_settlements.clear()
	last_boss_death_notifications.clear()
	_boss_notification_cursor = 0
	pending_player_contacts.clear()
	last_player_contact_receipts.clear()
	last_player_hazard_receipts.clear()
	_settled_player_attack_ids.clear()
	player_rule_port = null
	hit_admission_port = null


func bind_player_rule_port(port: Variant) -> Dictionary:
	if port == null or not port.has_method("apply_damage"):
		return _failure("invalid_player_rule_port")
	player_rule_port = port
	return {"ok": true, "error": ""}


## Typed Boss seam.  The spatial port and this combat port must bind the same
## domain instance so multipart queries and DAMAGE_STATUS share one HitBuffer.
func bind_boss_domain(domain: Variant) -> Dictionary:
	if not domain is BossDomainScript:
		return _failure("invalid_boss_domain")
	var typed: BossCombatDomain = domain
	if not typed.is_configured():
		return _failure("boss_domain_not_configured")
	boss_domain = typed
	last_boss_batch = {}
	last_boss_settlements.clear()
	last_boss_death_notifications.clear()
	_boss_notification_cursor = typed.last_settlement_notifications.size()
	return {"ok": true, "error": ""}


## Explicit structural/death phase seam for the parent kernel.  It is separate
## from resolve() so Boss death cannot be settled during the query phase.
func settle_boss_deaths(tick: int) -> Dictionary:
	if boss_domain == null:
		return _failure("boss_domain_unbound")
	var settled := boss_domain.settle_deaths(tick)
	if bool(settled.get("ok", false)):
		for receipt: Dictionary in settled.get("settlements", []):
			last_boss_settlements.append(receipt.duplicate(true))
		while _boss_notification_cursor < boss_domain.last_settlement_notifications.size():
			var notification: Variant = boss_domain.last_settlement_notifications[_boss_notification_cursor]
			_boss_notification_cursor += 1
			if notification is DeathSettlementNotificationScript:
				last_boss_death_notifications.append(notification)
	return settled


func bind_domains(
	new_damage_resolution: Variant = null,
	new_status_ledger: Variant = null,
	new_death_settlement: Variant = null,
	new_room_loot: Variant = null
) -> Dictionary:
	if new_damage_resolution != null:
		if not new_damage_resolution.has_method("resolve"):
			return _failure("invalid_damage_resolution")
		damage_resolution = new_damage_resolution
	if new_status_ledger != null:
		if not new_status_ledger.has_method("apply") or not new_status_ledger.has_method("collect_periodic_hits"):
			return _failure("invalid_status_ledger")
		status_ledger = new_status_ledger
	if new_death_settlement != null:
		if not new_death_settlement.has_method("settle"):
			return _failure("invalid_death_settlement")
		death_settlement = new_death_settlement
	if new_room_loot != null:
		if not new_room_loot.has_method("spawn"):
			return _failure("invalid_room_loot")
		room_loot = new_room_loot
	return {"ok": true, "error": ""}


func bind_hit_admission_port(port: RoomHitAdmissionPort) -> Dictionary:
	if port == null:
		return _failure("invalid_hit_admission_port")
	hit_admission_port = port
	return {"ok": true, "error": ""}


func resolve(ctx: SimTickContext) -> void:
	last_hits.clear()
	consumed_hits = 0
	if actors == null or damage_resolution == null:
		last_batch = {"tick": ctx.tick, "outcomes": [], "deaths": [], "rejected": ["combat_dependencies_unavailable"]}
		_resolve_boss_domain(ctx.tick)
		return

	_apply_status_requests(ctx)
	var raw_hits: Array = []
	var hit_index := 0
	var suppressed: Array[Dictionary] = []
	for hit: SimHit in ctx.hits.hits():
		var translated: Variant = _to_hit_record(hit, ctx.tick, hit_index)
		hit_index += 1
		if translated != null:
			if PLAYER_CONTACT_KINDS.has(StringName(translated.contact_kind)) and _actor_id_for_key(String(translated.target_key)) == "ranger":
				var player_attack_id := String(translated.attack_instance_id)
				if _settled_player_attack_ids.has(player_attack_id) or pending_player_contacts.any(func(value: Dictionary) -> bool: return String(value.get("attack_instance_id", "")) == player_attack_id):
					var duplicate: Dictionary = translated.snapshot()
					duplicate["reason"] = "duplicate_player_attack"
					suppressed.append(duplicate)
					continue
				pending_player_contacts.append({
					"tick": ctx.tick,
					"amount": translated.base_damage,
					"source_id": translated.source_key,
					"source_position": translated.contact_point,
					"attack_instance_id": translated.attack_instance_id,
					"contact_kind": String(translated.contact_kind),
				})
				consumed_hits += 1
				last_hits.append(translated.snapshot())
				continue
			var verdict: Dictionary = _admit_hit(translated)
			if not bool(verdict.get("allowed", true)):
				var rejected: Dictionary = translated.snapshot()
				rejected["reason"] = String(verdict.get("reason", "filtered"))
				suppressed.append(rejected)
				continue
			consumed_hits += 1
			last_hits.append(translated.snapshot())
			raw_hits.append(translated)
	if status_ledger != null:
		var periodic: Variant = status_ledger.collect_periodic_hits(ctx.tick)
		if periodic is Array:
			raw_hits.append_array(periodic)

	var targets: Array[Dictionary] = []
	for actor_id: String in actors.actor_ids():
		var snapshot: Dictionary = actors.actor_snapshot(actor_id)
		if snapshot.is_empty():
			continue
		var target_key := _target_key_for_snapshot(snapshot)
		if target_key.is_empty():
			continue
		targets.append({
			"target_key": target_key,
			"health": float(snapshot.get("health", snapshot.get("hit_points", 0))),
			"maximum_health": float(snapshot.get("maximum_health", snapshot.get("hit_points", 0))),
			"alive": bool(snapshot.get("alive", false)),
			"resistances": (snapshot.get("resistances", {}) as Dictionary).duplicate(true),
		})

	var result: Variant = damage_resolution.resolve(ctx.tick, raw_hits, targets)
	if result == null or not result.has_method("snapshot"):
		last_batch = {"tick": ctx.tick, "outcomes": [], "deaths": [], "rejected": ["damage_resolution_invalid_result"]}
		return
	for outcome: Variant in result.outcomes:
		var target_actor := _actor_for_key(String(outcome.target_key))
		if target_actor == null:
			continue
		target_actor.commit_resolved_health(float(outcome.remaining_health))
		_last_source_by_target[String(outcome.target_key)] = String(outcome.source_key)
	last_batch = result.snapshot()
	if not suppressed.is_empty():
		last_batch["suppressed"] = suppressed
	_resolve_boss_domain(ctx.tick)


## Player rules advance after the kernel tick in mounted production. Commit
## all typed player contacts here, after the kernel has consumed the SimHit
## buffer. The contact facts are cleared before application so a malformed
## player-rule receipt cannot be retried on a later tick.
func commit_player_contacts(tick: int) -> Array[Dictionary]:
	last_player_contact_receipts.clear()
	last_player_hazard_receipts.clear()
	if pending_player_contacts.is_empty():
		return []
	var pending := pending_player_contacts.duplicate(true)
	pending_player_contacts.clear()
	for contact: Dictionary in pending:
		var attack_id := String(contact.get("attack_instance_id", ""))
		_settled_player_attack_ids[attack_id] = true
		var copy: Dictionary = {
			"accepted": false,
			"status": "rejected",
			"reason": "player_rule_port_unavailable",
		}
		if int(contact.get("tick", -1)) != tick:
			copy["reason"] = "stale_player_contact_tick"
		elif player_rule_port != null:
			var receipt: Variant = player_rule_port.apply_damage(
				tick,
				float(contact.get("amount", 0.0)),
				String(contact.get("source_id", "")),
				contact.get("source_position", Vector2.ZERO)
			)
			if receipt is Dictionary:
				copy = receipt.duplicate(true)
			else:
				copy["reason"] = "invalid_player_damage_receipt"
		copy["source_id"] = String(contact.get("source_id", ""))
		copy["attack_instance_id"] = attack_id
		copy["contact_kind"] = String(contact.get("contact_kind", ""))
		copy["source_position"] = contact.get("source_position", Vector2.ZERO)
		last_player_contact_receipts.append(copy)
		if String(contact.get("contact_kind", "")) == "hazard":
			last_player_hazard_receipts.append(copy.duplicate(true))
	return last_player_contact_receipts.duplicate(true)


## DeathSettlement is called by SimKernel after the record has become a
## tombstone but before storage reclamation. It returns the typed notification;
## the kernel forwards that record through RoomEncounterPort.
func on_death(entity_view: SimEntityView, ctx: SimTickContext) -> Variant:
	if entity_view == null:
		return null
	var actor_view: Variant = entity_view
	var entity_key := "actor/%d" % int(entity_view.stable_key)
	var settled_snapshot: Dictionary = {}
	var notification: RefCounted = null
	if death_settlement != null:
		var request := {
			"tick": ctx.tick,
			"room_id": room_id,
			"entity_key": entity_key,
			"source_key": String(_last_source_by_target.get(entity_key, "system")),
			"spawn_key": String(actor_view.spawn_key) if actor_view is ActorState.ActorEntityView else "",
			"archetype_id": String(actor_view.archetype_id) if actor_view is ActorState.ActorEntityView else "",
			"position": actor_view.feet_position if actor_view is ActorState.ActorEntityView else Vector2.ZERO,
			"death_reason": "damage",
			"loot_source": "enemy_death",
			"loot_tags": actor_view.loot_tags.duplicate() if actor_view is ActorState.ActorEntityView else [],
			"can_drop": true,
		}
		var settled: Dictionary = death_settlement.settle(request)
		if bool(settled.get("ok", false)):
			settled_snapshot = settled.get("snapshot", {})
			var value: Variant = settled.get("value", null)
			if value is DeathSettlementResultScript:
				notification = value.encounter_notification
			last_settlements.append(settled_snapshot.duplicate(true))
			var loot_request: Variant = settled_snapshot.get("loot_spawn_request", {})
			if room_loot != null and loot_request is Dictionary and not (loot_request as Dictionary).is_empty():
				room_loot.spawn(ctx.tick, loot_request)
	if actors.has_method("detach_dead_actor"):
		actors.detach_dead_actor(entity_view.handle)
	return notification


func combat_snapshot() -> Dictionary:
	return {
		"room_id": room_id,
		"world_revision": world_revision,
		"last_batch": last_batch.duplicate(true),
		"last_boss_batch": last_boss_batch.duplicate(true),
		"last_settlements": last_settlements.duplicate(true),
		"last_boss_settlements": last_boss_settlements.duplicate(true),
		"status": status_ledger.snapshot() if status_ledger != null and status_ledger.has_method("snapshot") else {},
	}


func _resolve_boss_domain(tick: int) -> void:
	if boss_domain == null:
		return
	var resolved := boss_domain.resolve(tick)
	if not bool(resolved.get("ok", false)):
		last_boss_batch = {"tick": tick, "outcomes": [], "deaths": [], "rejected": [String(resolved.get("error", "boss_resolution_failed"))], "suppressed": []}
		return
	last_boss_batch = (resolved.get("batch", {}) as Dictionary).duplicate(true)


func _apply_status_requests(ctx: SimTickContext) -> void:
	if status_ledger == null:
		return
	for application: SimStatusApplication in ctx.statuses.applications():
		var target_key: String = String(actors.entity_key_for_handle(application.target)) if actors.has_method("entity_key_for_handle") else ""
		if target_key.is_empty():
			continue
		var source_key: String = String(actors.entity_key_for_handle(application.source)) if application.source != null and actors.has_method("entity_key_for_handle") else "system"
		status_ledger.apply(
			ctx.tick,
			target_key,
			String(application.status_id),
			source_key if not source_key.is_empty() else "system",
			maxi(1, application.duration_ticks),
			0,
			float(application.magnitude)
		)


func _to_hit_record(hit: SimHit, tick: int, ordinal: int) -> Variant:
	if hit == null or hit.target == null:
		return null
	var target_key: String = String(actors.entity_key_for_handle(hit.target)) if actors.has_method("entity_key_for_handle") else ""
	if target_key.is_empty():
		return null
	var source_key: String = String(actors.entity_key_for_handle(hit.source)) if hit.source != null and actors.has_method("entity_key_for_handle") else "system"
	var record: Variant = HitRecordScript.new()
	record.tick = tick
	record.attack_instance_id = hit.attack_instance_id if not hit.attack_instance_id.is_empty() else "sim/%d/%d" % [tick, ordinal]
	record.source_key = hit.source_key if not hit.source_key.is_empty() else (source_key if not source_key.is_empty() else "system")
	record.target_key = target_key
	record.part_id = hit.part_id if not hit.part_id.is_empty() else "body"
	record.damage_group_id = hit.damage_group_id if not hit.damage_group_id.is_empty() else String(hit.contact_kind if not hit.contact_kind.is_empty() else &"body")
	record.damage_type = hit.damage_type if not hit.damage_type.is_empty() else "physical"
	record.contact_kind = String(hit.contact_kind if not hit.contact_kind.is_empty() else &"contact")
	record.toi = clampf(hit.toi, 0.0, 1.0)
	var base_damage := maxf(0.0, float(hit.amount))
	if MILLI_DAMAGE_CONTACT_KINDS.has(hit.contact_kind):
		base_damage = maxf(0.0, float(hit.amount) / 1000.0)
	record.base_damage = base_damage
	record.priority = maxi(0, hit.priority)
	record.penetration_index = maxi(0, hit.penetration_index)
	record.allow_repeat_target = hit.allow_repeat_target
	record.contact_point = hit.contact_point if hit.contact_point.is_finite() else Vector2.ZERO
	var error: String = record.validate()
	return record if error.is_empty() else null


func _admit_hit(record: Variant) -> Dictionary:
	if hit_admission_port == null:
		return {"allowed": false, "reason": "hit_admission_port_unavailable"}
	var verdict: Variant = hit_admission_port.admit(record.snapshot())
	if not verdict is Dictionary:
		return {"allowed": false, "reason": "hit_admission_invalid_result"}
	return verdict


func _target_key_for_snapshot(snapshot: Dictionary) -> String:
	return "actor/%d" % int(snapshot.get("stable_key", 0)) if int(snapshot.get("stable_key", 0)) > 0 else ""


func _actor_for_key(entity_key: String) -> ActorState:
	for actor_id: String in actors.actor_ids():
		var snapshot: Dictionary = actors.actor_snapshot(actor_id)
		if _target_key_for_snapshot(snapshot) != entity_key:
			continue
		var value: Variant = actors.actor(actor_id)
		if value is ActorState:
			return value
	return null


func _actor_id_for_key(entity_key: String) -> String:
	for actor_id: String in actors.actor_ids():
		var snapshot: Dictionary = actors.actor_snapshot(actor_id)
		if _target_key_for_snapshot(snapshot) == entity_key:
			return actor_id
	return ""


static func _failure(error: String) -> Dictionary:
	return {"ok": false, "error": error}
