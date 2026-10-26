class_name KernelReconciler
extends RefCounted

## Kernel and Boss combat reconciliation extracted from MainArena. It binds the
## room's kernel ports and Boss domain, mirrors published kernel combat results
## back onto the room-facing enemy records, and settles kernel deaths. All room
## state stays owned by MainArena and is reached through the typed owner
## reference; call order and arithmetic are unchanged from the original methods.

const BossCombatDomainScript := preload("res://src/runtime/combat/boss_combat_domain.gd")
const DeathSettlementNotificationScript := preload("res://src/runtime/combat/death_settlement_notification.gd")
const SimTickContextScript := preload("res://src/runtime/simulation/sim_tick_context.gd")
const MainHitAdmissionPortScript := preload("res://src/game/ports/main_hit_admission_port.gd")

var _main: MainArena


func _init(main: MainArena) -> void:
	_main = main


func _bind_kernel_room_ports() -> bool:
	if _main.room_spatial_port == null or _main.room_combat_port == null or _main.room_encounter_port == null:
		push_error("kernel_room_ports_unavailable")
		return false
	var hit_admission_port := MainHitAdmissionPortScript.new()
	var admission_bound: Dictionary = hit_admission_port.bind(_main)
	if not bool(admission_bound.get("ok", false)):
		push_error("kernel_hit_admission_port_bind_failed:%s" % String(admission_bound.get("error", "unknown")))
		return false
	var filter_bound: Dictionary = _main.room_combat_port.bind_hit_admission_port(hit_admission_port)
	if not bool(filter_bound.get("ok", false)):
		push_error("kernel_hit_admission_port_bind_failed:%s" % String(filter_bound.get("error", "unknown")))
		return false
	var player_damage_bound: Dictionary = _main.room_combat_port.bind_player_rule_port(_main.player_combat_rules)
	if not bool(player_damage_bound.get("ok", false)):
		push_error("kernel_player_damage_port_bind_failed:%s" % String(player_damage_bound.get("error", "unknown")))
		return false
	var flight_configured: Dictionary = _main._kernel_arrow_flight.configure(_main.room_spatial_port)
	if not bool(flight_configured.get("ok", false)):
		push_error("kernel_arrow_flight_configure_failed:%s" % String(flight_configured.get("error", "unknown")))
		return false
	if not _bind_boss_kernel_domain():
		return false
	_main.last_kernel_snapshot = null
	_main.kernel_snapshot_publications.clear()
	_main.kernel_reconcile_events.clear()
	_main._enemy_stable_keys.clear()
	_main._kernel_settlement_cursor = 0
	_main._boss_domain_targets.clear()
	_main._boss_settlement_cursor = 0
	_main._boss_encounter_authority = false
	return true


func _bind_boss_kernel_domain() -> bool:
	if _main.simulation_world == null or String(_main.simulation_world.room_instance_id).is_empty() or int(_main.simulation_world.world_revision) < 0:
		push_error("boss_domain_room_identity_unavailable")
		return false
	var domain := BossCombatDomainScript.new()
	var configured: Dictionary = domain.configure(String(_main.simulation_world.room_instance_id), int(_main.simulation_world.world_revision))
	if not bool(configured.get("ok", false)):
		push_error("boss_domain_configure_failed:%s" % String(configured.get("error", "unknown")))
		return false
	var spatial_bound: Dictionary = _main.room_spatial_port.bind_boss_domain(domain)
	if not bool(spatial_bound.get("ok", false)):
		push_error("boss_spatial_domain_bind_failed:%s" % String(spatial_bound.get("error", "unknown")))
		return false
	var combat_bound: Dictionary = _main.room_combat_port.bind_boss_domain(domain)
	if not bool(combat_bound.get("ok", false)):
		push_error("boss_combat_domain_bind_failed:%s" % String(combat_bound.get("error", "unknown")))
		return false
	if _main.room_spatial_port.boss_domain != domain or _main.room_combat_port.boss_domain != domain:
		push_error("boss_domain_instance_mismatch")
		return false
	var boss_flight_configured: Dictionary = _main._kernel_boss_flight.configure(_main.room_spatial_port)
	if not bool(boss_flight_configured.get("ok", false)):
		push_error("kernel_boss_flight_configure_failed:%s" % String(boss_flight_configured.get("error", "unknown")))
		return false
	_main._boss_combat_domain = domain
	return true


func _boss_domain_room_is_current() -> bool:
	return (
		_main._boss_combat_domain != null
		and _main.room_spatial_port != null
		and _main.room_spatial_port.boss_domain == _main._boss_combat_domain
		and _main.room_combat_port != null
		and _main.room_combat_port.boss_domain == _main._boss_combat_domain
		and _main.simulation_world != null
		and _main._boss_combat_domain.room_id == String(_main.simulation_world.room_instance_id)
		and int(_main._boss_combat_domain.world_revision) == int(_main.simulation_world.world_revision)
	)


func _is_boss_kernel_projectile(projectile) -> bool:
	if projectile == null:
		return false
	var enemy := _main._enemy_by_entity_id(int(projectile.target_entity_id))
	return enemy != null and enemy.is_boss and _boss_domain_room_is_current()


func _is_normal_kernel_projectile(projectile) -> bool:
	if projectile == null or _main.room_spatial_port == null or _main.room_combat_port == null:
		return false
	var enemy := _main._enemy_by_entity_id(int(projectile.target_entity_id))
	return enemy == null or not enemy.is_boss


func _is_kernel_projectile(projectile) -> bool:
	if projectile == null or _main.room_spatial_port == null or _main.room_combat_port == null:
		return false
	return _is_normal_kernel_projectile(projectile) or _is_boss_kernel_projectile(projectile)


## The room-facing enemy record remains the health record other migrating
## systems read; the actor store is the kernel resolution substrate. They are
## synced at query submission so DamageResolution always resolves the current
## committed health, and the reconcile mirrors the result back.
## The room-facing enemy record remains the record other migrating systems
## read and mutate; the actor store is the kernel resolution substrate. Both
## health and pose are synced at query submission so the spatial indexes and
## DamageResolution always resolve the current committed room-facing record.
## In production the mirror is written after actor commits, so the pose sync
## is a no-op; a failed relocation keeps the authoritative actor pose.
func _sync_kernel_target_record(projectile) -> void:
	var enemy := _main._enemy_by_entity_id(int(projectile.target_entity_id))
	if enemy == null or enemy.is_boss:
		return
	var actor_id := "enemy/%d" % enemy.entity_id
	if _main.actor_registry == null or not _main.actor_registry.has_actor(actor_id):
		return
	var state = _main.actor_registry.actor(actor_id)
	if state == null or not state.alive:
		return
	if state.feet_position.distance_squared_to(enemy.position) > 0.000001:
		var relocated: Dictionary = _main.actor_registry.teleport_actor(actor_id, enemy.position)
		if bool(relocated.get("ok", false)):
			enemy.position = relocated.get("position", enemy.position)
	# The room-facing record may legally sit above its spawn maximum (legacy
	# fixtures raise health without raising maximum); the actor store must be
	# able to hold the current committed value.
	state.maximum_health = maxf(state.maximum_health, maxf(maxf(1.0, enemy.health), enemy.maximum_health))
	if absf(state.health - enemy.health) > 0.0005:
		state.commit_resolved_health(maxf(0.0, enemy.health))


## Keeps the detached BossTargetView pose/part facts equal to the actor-backed
## room mirror before a query. Health is deliberately not copied: once the room
## starts, BossCombatDomain owns BigValue health and mortality.
func _sync_boss_kernel_target(projectile) -> BossTargetView:
	var enemy := _main._enemy_by_entity_id(int(projectile.target_entity_id))
	if enemy == null or not enemy.is_boss or not _boss_domain_room_is_current():
		return null
	var target: BossTargetView = _main._boss_domain_targets.get(int(enemy.entity_id), null)
	if target == null or not target.alive:
		return null
	var actor_id := "enemy/%d" % enemy.entity_id
	if _main.actor_registry != null and _main.actor_registry.has_actor(actor_id):
		var state = _main.actor_registry.actor(actor_id)
		if state == null or not state.alive:
			return null
		enemy.position = state.feet_position
	target.position = enemy.position
	var admission_blocked: bool = _main.encounter_director != null and _main.encounter_director.is_target_blocked(enemy)
	var admission := target.set_admission(admission_blocked, "periodic_barrier" if admission_blocked else "")
	if not bool(admission.get("ok", false)):
		push_error("boss_domain_admission_sync_failed:%s" % String(admission.get("error", "unknown")))
		return null
	for room_part: Dictionary in enemy.hurtbox_parts():
		for boss_part: BossHurtbox in target.parts:
			if boss_part.part_id != String(room_part.get("part_id", "")):
				continue
			boss_part.local_offset = room_part.get("pose", boss_part.local_offset)
			var state_result: Dictionary = target.set_part_state(
				boss_part.part_id,
				bool(room_part.get("active", true)),
				bool(room_part.get("broken", false))
			)
			if not bool(state_result.get("ok", false)):
				push_error("boss_domain_part_sync_failed:%s" % boss_part.part_id)
				return null
	return target


## Hit admission at the damage boundary. Keeps the legacy arrow contract
## while the sweep itself moved to the kernel's typed path queries: only the
## locked non-boss target is admitted, and the elite periodic barrier
## suppresses the hit before DamageResolution.
func _admit_kernel_hit(hit: Dictionary) -> Dictionary:
	var attack_id := String(hit.get("attack_instance_id", ""))
	if not attack_id.begins_with("arrow/"):
		return {"allowed": true, "reason": ""}
	var action_id := int(attack_id.trim_prefix("arrow/"))
	var projectile = null
	for candidate in _main.combat_system.projectiles:
		if int(candidate.action_instance_id) == action_id:
			projectile = candidate
			break
	if projectile == null:
		return {"allowed": false, "reason": "arrow_not_in_flight"}
	var enemy := _main._enemy_by_entity_id(int(projectile.target_entity_id))
	if enemy == null or enemy.is_boss:
		return {"allowed": false, "reason": "legacy_big_value_target"}
	var hit_entity_id := int(_main._enemy_stable_keys.get(String(hit.get("target_key", "")), 0))
	if hit_entity_id != int(projectile.target_entity_id):
		return {"allowed": false, "reason": "not_locked_target"}
	if _main.encounter_director != null and _main.encounter_director.is_target_blocked(enemy):
		return {"allowed": false, "reason": "periodic_barrier"}
	return {"allowed": true, "reason": ""}


func _enemy_by_stable_key(target_key: String) -> CombatEnemyState:
	var entity_id := int(_main._enemy_stable_keys.get(target_key, 0))
	if entity_id <= 0:
		return null
	return _main._enemy_by_entity_id(entity_id)


func _consume_kernel_room_combat() -> void:
	if _main.room_spatial_port == null or _main.room_combat_port == null or not _main._kernel_arrow_flight.is_configured():
		return
	var published_snapshot = _main.simulation_world.latest_snapshot() if _main.simulation_world != null else null
	if published_snapshot != null and published_snapshot.has_method("sha256_hex"):
		var published_tick := int(published_snapshot.tick)
		if _main.last_kernel_snapshot == null or int(_main.last_kernel_snapshot.tick) != published_tick:
			_main.last_kernel_snapshot = published_snapshot
			_main.kernel_snapshot_publications.append({
				"tick": published_tick,
				"room_instance_id": String(published_snapshot.room_instance_id),
				"world_revision": int(published_snapshot.world_revision),
				"phase": "kernel.snapshot.published",
				"hash": published_snapshot.sha256_hex(),
			})
	_main._combat_context()
	var previous_report := String(_main.combat_system.battle_report)
	var previous_event_id: int = _main.combat_event_stream.latest_event_id()
	var results: Array = _main.room_spatial_port.take_path_results()
	var records: Array = _main._kernel_arrow_flight.pending_records()
	var published_tick := int(_main.last_kernel_snapshot.tick) if _main.last_kernel_snapshot != null else -1
	var published_hash: String = _main.last_kernel_snapshot.sha256_hex() if _main.last_kernel_snapshot != null and _main.last_kernel_snapshot.has_method("sha256_hex") else ""
	_main.kernel_reconcile_events.append({
		"phase": "room.reconcile.begin",
		"tick": _main.sim_tick,
		"snapshot_tick": published_tick,
		"snapshot_hash": published_hash,
		"path_results": results.size(),
		"pending_arrows": records.size(),
	})
	var admitted: Dictionary = {}
	for hit: Dictionary in _main.room_combat_port.last_hits:
		admitted[String(hit.get("attack_instance_id", ""))] = hit
	var suppressed: Dictionary = {}
	for entry: Variant in _main.room_combat_port.last_batch.get("suppressed", []):
		if entry is Dictionary:
			suppressed[String((entry as Dictionary).get("attack_instance_id", ""))] = entry
	var outcome_by_attack: Dictionary = {}
	for outcome: Variant in _main.room_combat_port.last_batch.get("outcomes", []):
		if outcome is Dictionary:
			outcome_by_attack[String((outcome as Dictionary).get("attack_instance_id", ""))] = outcome
	var count := mini(results.size(), records.size())
	for index in count:
		var result = results[index]
		var record = records[index]
		var projectile = record.projectile
		if projectile == null or not _main.combat_system.projectiles.has(projectile):
			continue
		var attack_key: String = record.attack_key
		if admitted.has(attack_key) and outcome_by_attack.has(attack_key):
			_reconcile_kernel_hit(projectile, record, admitted[attack_key], outcome_by_attack[attack_key])
			_main.kernel_reconcile_events.append({
				"phase": "room.reconcile.arrow_hit",
				"tick": _main.sim_tick,
				"snapshot_tick": published_tick,
				"snapshot_hash": published_hash,
				"attack_instance_id": attack_key,
				"target_key": String(admitted[attack_key].get("target_key", "")),
			})
			_retire_kernel_projectile(projectile, attack_key)
			continue
		if suppressed.has(attack_key):
			var rejection: Dictionary = suppressed[attack_key]
			# Only a barrier block on the locked target consumes the arrow.
			# Every other suppression (a piercing pass-through on a non-locked
			# hurtbox, a legacy BigValue target) leaves the arrow in flight.
			if String(rejection.get("reason", "")) == "periodic_barrier":
				var blocked_enemy := _enemy_by_stable_key(String(rejection.get("target_key", "")))
				var blocked_point_value: Variant = rejection.get("contact_point", projectile.position)
				var blocked_point: Vector2 = blocked_point_value if blocked_point_value is Vector2 else projectile.position
				projectile.position = blocked_point
				_main.combat_system.apply_kernel_blocked(projectile, blocked_enemy, blocked_point)
				_retire_kernel_projectile(projectile, attack_key)
				continue
		if result != null and bool(result.clipped):
			projectile.position = result.end_point
			_main.combat_system.resolve_projectile_miss(projectile)
			_retire_kernel_projectile(projectile, attack_key)
			continue
		if projectile.distance_travelled >= projectile.maximum_range:
			_main.combat_system.resolve_projectile_miss(projectile)
			_retire_kernel_projectile(projectile, attack_key)
	_main._kernel_arrow_flight.clear_pending()
	_reconcile_kernel_deaths()
	_consume_kernel_boss_combat(published_tick, published_hash)
	_main.kernel_reconcile_events.append({
		"phase": "room.reconcile.end",
		"tick": _main.sim_tick,
		"snapshot_tick": published_tick,
		"snapshot_hash": published_hash,
		"path_results": results.size(),
		"pending_arrows": records.size(),
	})
	_main._combat_report(previous_report, previous_event_id)


func _retire_kernel_projectile(projectile, attack_key: String) -> void:
	_main.combat_system.remove_projectile(projectile)
	_main._kernel_arrow_flight.forget_arrow(attack_key)


func _consume_kernel_boss_combat(published_tick: int, published_hash: String) -> void:
	if not _main._kernel_boss_flight.is_configured():
		return
	if not _boss_domain_room_is_current():
		push_error("boss_domain_room_mismatch:%s:%d" % [String(_main._boss_combat_domain.room_id), int(_main._boss_combat_domain.world_revision)])
		_main._kernel_boss_flight.clear_pending()
		return
	var results: Array = _main.room_spatial_port.take_boss_path_results()
	var records: Array = _main._kernel_boss_flight.pending_records()
	var batch: Dictionary = _main.room_combat_port.last_boss_batch
	if not (batch.get("rejected", []) as Array).is_empty():
		push_error("boss_damage_resolution_rejected:%s" % str(batch.get("rejected", [])))
	var outcome_by_attack: Dictionary = {}
	for outcome: Variant in batch.get("outcomes", []):
		if outcome is Dictionary:
			outcome_by_attack[String((outcome as Dictionary).get("attack_instance_id", ""))] = outcome
	var suppressed_by_attack: Dictionary = {}
	for suppressed: Variant in batch.get("suppressed", []):
		if suppressed is Dictionary:
			var suppressed_value: Dictionary = suppressed as Dictionary
			suppressed_by_attack[String(suppressed_value.get("attack_instance_id", ""))] = suppressed_value
	var count := mini(results.size(), records.size())
	for index in count:
		var result = results[index]
		var record = records[index]
		var projectile = record.projectile
		if projectile == null or not _main.combat_system.projectiles.has(projectile):
			continue
		var attack_key: String = record.attack_key
		if not outcome_by_attack.has(attack_key):
			if suppressed_by_attack.has(attack_key):
				var suppression: Dictionary = suppressed_by_attack[attack_key]
				if String(suppression.get("reason", "")) == "periodic_barrier":
					var blocked_enemy := _main._enemy_by_entity_id(int(projectile.target_entity_id))
					var blocked_point_value: Variant = suppression.get("contact_point", projectile.position)
					var blocked_point: Vector2 = blocked_point_value if blocked_point_value is Vector2 else projectile.position
					projectile.position = blocked_point
					_main.combat_system.apply_kernel_blocked(projectile, blocked_enemy, blocked_point)
					_retire_boss_kernel_projectile(projectile, attack_key)
					continue
			if result != null and bool(result.clipped):
				projectile.position = result.end_point
				_main.combat_system.resolve_projectile_miss(projectile)
				_retire_boss_kernel_projectile(projectile, attack_key)
			elif projectile.distance_travelled >= projectile.maximum_range:
				_main.combat_system.resolve_projectile_miss(projectile)
				_retire_boss_kernel_projectile(projectile, attack_key)
			continue
		var outcome: Dictionary = outcome_by_attack[attack_key]
		var enemy := _main._enemy_by_entity_id(int(projectile.target_entity_id))
		if enemy == null or not enemy.is_boss:
			push_error("boss_kernel_target_mirror_unresolved:%s" % attack_key)
			continue
		var target: BossTargetView = _main._boss_domain_targets.get(int(enemy.entity_id), null)
		if target == null or record.health_before == null:
			push_error("boss_kernel_target_domain_unresolved:%s" % attack_key)
			continue
		var applied: BigValue = _big_value_from_snapshot(outcome.get("applied_damage", {}).get("big", {}))
		var remaining: BigValue = _big_value_from_snapshot(outcome.get("remaining_health", {}))
		if applied == null or remaining == null:
			push_error("boss_kernel_outcome_big_value_invalid:%s" % attack_key)
			continue
		var mirrored: Dictionary = _main.combat_system.sync_boss_domain_resolution(target.maximum_health, applied, remaining)
		if not bool(mirrored.get("ok", false)):
			push_error("boss_domain_mirror_failed:%s" % String(mirrored.get("error", "unknown")))
			continue
		var contact := _boss_contact_for_outcome(result, outcome)
		var contact_point: Vector2 = contact.get("contact_point", projectile.position) if contact.get("contact_point", null) is Vector2 else projectile.position
		projectile.position = contact_point
		enemy.hit_flash_until_tick = _main.sim_tick + MainArena.ENEMY_HIT_FLASH_TICKS
		_main.combat_system.apply_boss_kernel_contact(
			projectile,
			enemy,
			contact_point,
			contact,
			record.health_before,
			remaining,
			record.aggregate
		)
		_main.kernel_reconcile_events.append({
			"phase": "room.reconcile.boss_arrow_hit",
			"tick": _main.sim_tick,
			"snapshot_tick": published_tick,
			"snapshot_hash": published_hash,
			"attack_instance_id": attack_key,
			"target_key": target.target_key,
			"part_id": String(outcome.get("part_id", "body")),
		})
		_retire_boss_kernel_projectile(projectile, attack_key)
		if bool(outcome.get("lethal", false)):
			enemy.health = 0.0
			_finalize_boss_kernel_death(enemy, target)
	_main._kernel_boss_flight.clear_pending()
	_settle_boss_kernel_deaths(published_tick)


func _boss_contact_for_outcome(result: Variant, outcome: Dictionary) -> Dictionary:
	if result == null:
		return {}
	var part_id := String(outcome.get("part_id", ""))
	for contact: BossHitContact in result.hit_contacts:
		if contact.part_id == part_id:
			return {"part_id": contact.part_id, "damage_group_id": contact.damage_group_id, "contact_point": contact.contact_point}
	if not result.hit_contacts.is_empty():
		var first: BossHitContact = result.hit_contacts[0]
		return {"part_id": first.part_id, "damage_group_id": first.damage_group_id, "contact_point": first.contact_point}
	return {}


func _big_value_from_snapshot(value: Variant) -> BigValue:
	if not value is Dictionary:
		return null
	var data: Dictionary = value
	return BigValue.from_components(int(data.get("layer", -1)), float(data.get("magnitude", NAN)))


func _retire_boss_kernel_projectile(projectile, attack_key: String) -> void:
	_main.combat_system.remove_projectile(projectile)
	_main._kernel_boss_flight.forget_arrow(attack_key)


func _finalize_boss_kernel_death(enemy: CombatEnemyState, target: BossTargetView) -> void:
	var actor_id := "enemy/%d" % enemy.entity_id
	if _main.actor_registry != null and _main.actor_registry.has_actor(actor_id):
		var unregistered: Dictionary = _main.actor_registry.unregister_actor(actor_id)
		if not bool(unregistered.get("ok", false)):
			push_error("boss_actor_unregister_failed:%d:%s" % [enemy.entity_id, String(unregistered.get("error", "unknown"))])
	_main._boss_domain_targets.erase(int(enemy.entity_id))
	_finalize_kernel_enemy_death(enemy)


func _settle_boss_kernel_deaths(settlement_tick: int) -> void:
	if not _boss_domain_room_is_current():
		return
	if settlement_tick < 0:
		return
	var settled: Dictionary = _main.room_combat_port.settle_boss_deaths(settlement_tick)
	if not bool(settled.get("ok", false)):
		push_error("boss_death_settlement_failed:%s" % String(settled.get("error", "unknown")))
		return
	var settlements: Array[Dictionary] = _main.room_combat_port.last_boss_settlements
	var notifications: Array[RefCounted] = _main.room_combat_port.last_boss_death_notifications
	var context := SimTickContextScript.new()
	context.tick = settlement_tick
	context.room_instance_id = String(_main.simulation_world.room_instance_id)
	context.world_revision = int(_main.simulation_world.world_revision)
	while _main._boss_settlement_cursor < settlements.size():
		var settlement: Dictionary = settlements[_main._boss_settlement_cursor]
		var notification: Variant = notifications[_main._boss_settlement_cursor] if _main._boss_settlement_cursor < notifications.size() else null
		_main._boss_settlement_cursor += 1
		if _main.room_encounter_port != null and notification is DeathSettlementNotificationScript:
			_main.room_encounter_port.on_death_settlement(notification, context)
		elif _main.room_encounter_port != null:
			push_error("boss_death_notification_missing:%s" % String(settlement.get("entity_key", "")))
		var loot_value: Variant = settlement.get("loot_spawn_request", {})
		if loot_value is Dictionary and not (loot_value as Dictionary).is_empty():
			var entity_id := int(_main._enemy_stable_keys.get(String(settlement.get("entity_key", "")), 0))
			if entity_id <= 0:
				push_error("boss_death_loot_entity_unresolved:%s" % String(settlement.get("entity_key", "")))
				continue
			var position_value: Variant = (loot_value as Dictionary).get("position", Vector2.ZERO)
			var position: Vector2 = position_value if position_value is Vector2 else Vector2.ZERO
			_main._spawn_room_loot_for_source("enemy_death", entity_id, position)


func _reconcile_kernel_hit(projectile, record: Variant, hit: Dictionary, outcome: Dictionary) -> void:
	var enemy := _enemy_by_stable_key(String(hit.get("target_key", "")))
	if enemy == null:
		return
	var health_before: float = enemy.health
	var remaining: float = clampf(float(outcome.get("remaining_health", 0.0)), 0.0, maxf(enemy.maximum_health, health_before))
	# The resolver reports the target-side surface point; the authoritative
	# contact for events and traces is the point on the frozen arrow path.
	var toi := clampf(float(hit.get("toi", 0.0)), 0.0, 1.0)
	var contact: Vector2 = record.query_start + record.query_displacement * toi
	enemy.health = snappedf(remaining, 0.001)
	enemy.hit_flash_until_tick = _main.sim_tick + MainArena.ENEMY_HIT_FLASH_TICKS
	projectile.position = contact
	_main.combat_system.apply_kernel_contact(projectile, enemy, contact, hit, health_before, enemy.health, record.aggregate)
	_main._enemy_ai._maybe_summon_reinforcements(enemy)
	if enemy.health <= 0.0:
		_finalize_kernel_enemy_death(enemy)


func _finalize_kernel_enemy_death(enemy: CombatEnemyState) -> void:
	_main.enemies.erase(enemy)
	_main.combat_system.note_kernel_death(enemy)
	var canceled_request_id: int = _main._arrows._cancel_buffered_target(enemy.entity_id)
	if canceled_request_id > 0:
		_main._arrows._erase_attack_request(canceled_request_id)
	_main._refresh_player_mark()


func _reconcile_kernel_deaths() -> void:
	var settlements: Array[Dictionary] = _main.room_combat_port.last_settlements
	while _main._kernel_settlement_cursor < settlements.size():
		var settlement: Dictionary = settlements[_main._kernel_settlement_cursor]
		_main._kernel_settlement_cursor += 1
		var loot_value: Variant = settlement.get("loot_spawn_request", {})
		if not loot_value is Dictionary or (loot_value as Dictionary).is_empty():
			continue
		var entity_id := int(_main._enemy_stable_keys.get(String(settlement.get("entity_key", "")), 0))
		if entity_id <= 0:
			push_error("kernel_death_loot_entity_unresolved:%s" % String(settlement.get("entity_key", "")))
			continue
		var position_value: Variant = (loot_value as Dictionary).get("position", Vector2.ZERO)
		var position: Vector2 = position_value if position_value is Vector2 else Vector2.ZERO
		_main._spawn_room_loot_for_source("enemy_death", entity_id, position)
