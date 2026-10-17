extends SceneTree

## Historical Boss multipart combat contract, migrated to BossCombatDomain.
##
## The legacy CombatSystem Boss damage/flight branches are deleted: Boss
## contacts resolve only through the typed Boss domain, and the removed seam
## fails closed. Normal-enemy and player-domain behavior stays asserted
## through the unchanged CombatSystem paths.

const Combat := preload("res://src/systems/combat_system.gd")
const Enemy := preload("res://src/runtime/world/combat_enemy_state.gd")
const Arrow := preload("res://src/runtime/world/combat_arrow_projectile.gd")
const Stream := preload("res://src/systems/combat_event_stream.gd")
const Aim := preload("res://src/systems/manual_aim_resolver.gd")
const RoomPort := preload("res://tests/helpers/callable_combat_system_room_port.gd")
const Big := preload("res://src/core/big_value.gd")
const BossDomainScript := preload("res://src/runtime/combat/boss_combat_domain.gd")
const BossQueryScript := preload("res://src/runtime/combat/boss_attack_query.gd")
const BossDamageValueScript := preload("res://src/runtime/combat/boss_damage_value.gd")
const BossTargetScript := preload("res://src/runtime/combat/boss_target_view.gd")
const BossHurtboxScript := preload("res://src/runtime/combat/boss_hurtbox.gd")
const Channels := preload("res://src/runtime/spatial/spatial_channels.gd")
const HandleScript := preload("res://src/runtime/simulation/sim_entity_handle.gd")

var failures: Array[String] = []


class StaticOnlyResolver extends RefCounted:
	func resolve_path(_request: Dictionary) -> Dictionary:
		return {"ok": true, "contacts": []}


class PlayerRulePortStub extends RefCounted:
	var retained_aggregate: BigValue = BigValue.from_float(0.0)
	var retained_ordinary := 0.0

	func consume_first_critical_bonus() -> int:
		return 0

	func retain_missed_arrow(aggregate: BigValue, ordinary: float) -> void:
		retained_aggregate = retained_aggregate.add(aggregate.multiply(BigValue.from_float(0.5)))
		retained_ordinary += ordinary * 0.5

	func take_retained_arrow() -> Dictionary:
		var result := {"aggregate": retained_aggregate.duplicate_value(), "ordinary": retained_ordinary}
		retained_aggregate = BigValue.from_float(0.0)
		retained_ordinary = 0.0
		return result


func _initialize() -> void:
	_test_typed_boss_domain_contract()
	_test_ordinary_enemy_flight_and_dedup()
	_test_legacy_boss_seam_fails_closed()
	if failures.is_empty():
		print("PASS test_boss_parts_combat.gd")
		quit(0)
		return
	for failure: String in failures:
		printerr("- %s" % failure)
	quit(1)


## The migrated Boss guarantees: stable multipart contact order independent of
## insertion order, one payload per damage group per arrow, exact BigValue
## death, dead-target idempotence and one settlement receipt.
func _test_typed_boss_domain_contract() -> void:
	var domain: BossCombatDomain = BossDomainScript.new()
	_expect(bool(domain.configure("boss-parts-room", 1).get("ok", false)), "typed domain configuration rejected")
	var target: BossTargetView = BossTargetScript.make("boss/colossus", Big.from_float(20), Vector2(100, 0), "threshold_colossus", "wave.test/threshold", ["boss.threshold"])
	_expect(bool(target.add_part(BossHurtboxScript.make("head", "body", Vector2.ZERO, 10.0)).get("ok", false)), "typed head hurtbox rejected")
	_expect(bool(target.add_part(BossHurtboxScript.make("hand", "body", Vector2.ZERO, 10.0)).get("ok", false)), "typed hand hurtbox rejected")
	_expect(bool(target.add_part(BossHurtboxScript.make("core", "core", Vector2(20, 0), 10.0)).get("ok", false)), "typed core hurtbox rejected")
	_expect(bool(domain.register_target(target).get("ok", false)), "typed Boss target registration rejected")
	var handle := HandleScript.make(3, 1)
	var resolver := StaticOnlyResolver.new()
	_expect(bool(domain.begin_tick(1).get("ok", false)), "typed domain tick rejected")
	var query := BossQueryScript.make(handle, "boss/colossus", Channels.PROJECTILE, Vector2.ZERO, Vector2(200, 0), 0.0, true, "arrow/11", BossDamageValueScript.from_milli(10000))
	var first: BossPathResult = domain.query_path(query, resolver, "actor/ranger")
	_expect(first.ok and _part_ids(first.hit_contacts) == ["hand", "head", "core"], "typed contacts lost stable group/TOI order: %s" % str(first.errors))

	var resolved: Dictionary = domain.resolve(1)
	_expect(bool(resolved.get("ok", false)), "typed DAMAGE_STATUS resolve rejected")
	var batch: Dictionary = domain.last_batch
	var outcomes: Array = batch.get("outcomes", [])
	_expect(outcomes.size() == 2 and String(outcomes[0].part_id) == "hand" and String(outcomes[0].damage_group_id) == "body" and String(outcomes[1].part_id) == "core" and String(outcomes[1].damage_group_id) == "core", "typed shared-group dedup and part attribution changed: %s" % str(batch))
	_expect((batch.get("suppressed", []) as Array).size() == 1, "typed same-group part was not suppressed exactly once")
	_expect((batch.get("deaths", []) as Array) == ["boss/colossus"], "typed exact maximum did not produce one death")
	_expect(domain.target("boss/colossus").health.is_zero() and not domain.target("boss/colossus").alive, "typed committed health was not the canonical zero")

	var repeated: BossPathResult = domain.query_path(query.duplicate_value(), resolver, "actor/ranger")
	_expect(repeated.ok and repeated.hit_contacts.is_empty(), "typed dead target accepted a repeated multipart query")
	var re_resolved: Dictionary = domain.resolve(1)
	_expect(bool(re_resolved.get("ok", false)) and (domain.last_batch.get("outcomes", []) as Array).is_empty(), "typed dead target settled repeated damage")

	var settled: Dictionary = domain.settle_deaths(1)
	var receipts: Array = settled.get("settlements", [])
	_expect(bool(settled.get("ok", false)) and receipts.size() == 1 and String(receipts[0].get("entity_key", "")) == "boss/colossus", "typed death settlement did not produce one receipt")
	var settled_again: Dictionary = domain.settle_deaths(1)
	_expect(bool(settled_again.get("ok", false)) and (settled_again.get("settlements", []) as Array).is_empty(), "typed settlement was not idempotent")


## Preserved normal-enemy/player-domain behavior after the Boss branch removal.
func _test_ordinary_enemy_flight_and_dedup() -> void:
	var combat := _combat_fixture()
	var ordinary := Enemy.new(Vector2(100, 22), 10, false, 41, "melee_pursuer")
	var supplied: Array[CombatEnemyState] = [ordinary]
	_expect(bool(combat.reset_room(Big.from_float(0)).get("ok", false)), "ordinary room reset rejected")
	_expect(_context(combat, 1, supplied).ok, "ordinary context rejected")
	combat.resolve_piercing_arrow({"action_instance_id": 90, "tick": 1, "target_entity_id": 41, "aim_direction_milli": {"x": 1000, "y": 0}})
	combat.tick = 2
	combat.advance_projectiles_tick()
	var killed: Dictionary = combat.outcome_snapshot()
	_expect(ordinary.health == 0 and killed.defeated == 1 and killed.shots == 1 and killed.arrow_hits == 1 and killed.boss_damage.is_zero() and supplied.is_empty(), "ordinary flight/death totals changed after the Boss branch removal")
	combat.resolve_projectile_contact(_arrow(90), ordinary, ordinary.position)
	combat.resolve_projectile_contact(_arrow(91), ordinary, ordinary.position)
	_expect(combat.outcome_snapshot().defeated == 1 and _damage_events(combat).size() == 1, "dead ordinary target duplicated damage")
	var live := Enemy.new(Vector2(100, 22), 100, false, 42, "melee_pursuer")
	_expect(_context(combat, 3, [live]).ok, "live ordinary context rejected")
	combat.resolve_projectile_contact(_arrow(92, 42), live, live.position)
	combat.resolve_projectile_contact(_arrow(92, 42), live, live.position)
	_expect(live.health == 90 and combat.outcome_snapshot().arrow_hits == 2, "ordinary direct-contact attack/group dedup changed")


## The deleted legacy Boss damage/flight branches fail closed, while the
## versioned pure query and the production Boss mirror seam keep working.
func _test_legacy_boss_seam_fails_closed() -> void:
	var combat := _combat_fixture()
	var boss := Enemy.new(Vector2(100, 0), 1000, true, 41, "threshold_colossus")
	_expect(bool(combat.reset_room(Big.from_float(10000)).get("ok", false)), "legacy seam room reset rejected")
	_expect(_context(combat, 1, [boss]).ok, "legacy seam context rejected")
	var query: Dictionary = combat.query_swept_hits(Vector2.ZERO, Vector2(200, 0), boss)
	_expect(query.ok and not (query.candidates as Array).is_empty() and String(query.candidates[0].part_id) == "left_hand", "versioned multipart query lost the default Boss pose")
	var receipt: Dictionary = combat.resolve_projectile_sweep(_arrow(11), boss, Vector2.ZERO, Vector2(200, 0))
	_expect(not receipt.ok and receipt.error == "boss_target_requires_boss_domain", "legacy Boss sweep did not fail closed")
	_expect(boss.health == 1000 and combat.outcome_snapshot().arrow_hits == 0 and combat.outcome_snapshot().defeated == 0 and combat.outcome_snapshot().boss_damage.is_zero() and _damage_events(combat).is_empty(), "failed-closed Boss sweep changed health, totals or events")
	combat.projectiles.append(_arrow(12))
	combat.tick = 2
	combat.advance_projectiles_tick()
	_expect(combat.projectiles.is_empty() and combat.last_attack_outcome.outcome == "rejected" and combat.last_attack_outcome.reason == "boss_target_requires_boss_domain", "legacy Boss flight did not retire with an explicit rejection")
	_expect(boss.health == 1000 and combat.outcome_snapshot().boss_damage.is_zero() and combat.outcome_snapshot().arrow_hits == 0, "legacy Boss flight contaminated player-domain totals")
	_expect(bool(combat.sync_boss_domain_resolution(Big.from_float(20), Big.from_float(10), Big.from_float(10)).get("ok", false)), "Boss domain mirror rejected a valid resolution")
	_expect(bool(combat.sync_boss_domain_resolution(Big.from_float(20), Big.from_float(10), Big.from_float(0)).get("ok", false)), "Boss domain mirror rejected the lethal clamp")
	var mirrored: Dictionary = combat.outcome_snapshot()
	_expect(mirrored.boss_damage.compare(Big.from_float(20)) == 0 and mirrored.boss_maximum.compare(Big.from_float(20)) == 0, "Boss mirror did not clamp to the room maximum")
	_expect(bool(combat.sync_boss_domain_resolution(Big.from_float(7), Big.from_float(3), Big.from_float(4)).get("ok", false)), "Boss domain mirror rejected a new room maximum")
	_expect(combat.outcome_snapshot().boss_damage.compare(Big.from_float(3)) == 0 and combat.outcome_snapshot().boss_maximum.compare(Big.from_float(7)) == 0, "new Boss maximum did not reset the mirror ledger")
	_expect(not bool(combat.sync_boss_domain_resolution(Big.from_float(7), Big.from_float(1), Big.from_float(8)).get("ok", false)), "Boss mirror accepted an inconsistent resolution")
	_expect(combat.outcome_snapshot().boss_damage.compare(Big.from_float(3)) == 0, "rejected Boss mirror partially wrote the ledger")


func _combat_fixture() -> Combat:
	var system := Combat.new()
	var port := RoomPort.new()
	var prepared: Dictionary = port.configure({
		"player_rule_port": PlayerRulePortStub.new(),
		"current_model": _model,
		"target_blocked": _not_blocked,
	})
	_expect(bool(prepared.get("ok", false)), "combat fixture rejected the strict player port")
	var configured: Dictionary = system.bind_room(port)
	_expect(bool(configured.get("ok", false)), "combat fixture rejected the typed room port")
	return system


func _context(combat: Combat, new_tick: int, targets: Array[CombatEnemyState]) -> Dictionary:
	return combat.set_context(new_tick, Vector2.ZERO, Vector2.RIGHT, 10.0, 225.0, 6000.0, 0, {}, Stream.new(), Aim.new(), targets)


func _arrow(id: int, target_id: int = 41) -> CombatArrowProjectile:
	return Arrow.new(id, target_id, 0, Vector2.ZERO, Vector2.RIGHT, 225.0, 6000.0, Big.from_float(10), 10.0, Big.from_float(1), 10.0)


func _model() -> Dictionary:
	return {"state": "normal", "total_events": Big.from_float(1), "total_events_float": 1.0, "g": 1}


func _not_blocked(_target: CombatEnemyState) -> bool:
	return false


func _damage_events(combat: Combat) -> Array:
	return combat.combat_event_stream.snapshot().events.filter(func(event: Dictionary) -> bool: return String(event.get("type", "")) == "damage_applied")


func _part_ids(contacts: Array) -> Array:
	var result: Array = []
	for contact: BossHitContact in contacts:
		result.append(contact.part_id)
	return result


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
