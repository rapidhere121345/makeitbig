class_name RoomHazards
extends RefCounted

## Hazard ticks and player-contact staging extracted from MainArena. This
## helper owns the hazard domain; the encounter director and kernel ports remain
## owned by MainArena and are reached through the typed owner reference.

const CombatHazardDomainScript := preload("res://src/runtime/combat/combat_hazard_domain.gd")

var _main: MainArena
## The room authority; read at use time, never cache its replaced members.
var _session: RoomSession
## The configured CombatHazardDomain, or null while the room runs on the
## EncounterDirector's own hazard states.
var domain: RefCounted = null


func _init(main: MainArena) -> void:
	_main = main
	_session = main.session


func _configure_hazard_domain(hazard_ids: Variant, center: Vector2) -> Dictionary:
	if _session.encounter_director == null or _session.encounter_director.room_port == null:
		return {"ok": false, "error": "hazard_room_port_unavailable"}
	if not hazard_ids is Array:
		return {"ok": false, "error": "invalid_hazard_ids"}
	var candidate: RefCounted = CombatHazardDomainScript.new()
	var configured: Dictionary = candidate.configure_ids(_session.encounter_director.room_port, _main.room_geometry.arena_rect(), hazard_ids, center)
	if not bool(configured.get("ok", false)):
		return configured
	domain = candidate
	var read_bound: Dictionary = _session.encounter_director.set_hazard_read_port(domain)
	if not bool(read_bound.get("ok", false)):
		return read_bound
	# The director's tactics snapshot consumes the same detached view objects;
	# it no longer advances or resolves them in production.
	_session.encounter_director.hazard_states = domain.snapshots()
	return {"ok": true, "error": "", "count": domain.hazards.size()}


func _update_hazards_tick() -> void:
	_refresh_hazard_states_tick()
	_resolve_hazard_hits_tick()


func _refresh_hazard_states_tick() -> void:
	if domain != null and domain.is_configured():
		var refreshed: Dictionary = domain.refresh(_session.sim_tick)
		if not bool(refreshed.get("ok", false)):
			_session.battle_report = "hazard_refresh_failed:%s" % String(refreshed.get("error", "unknown"))
		_session.encounter_director.hazard_states = domain.snapshots()
		return
	_main.sync_encounter_context()
	_session.encounter_director.refresh_hazard_states_tick()


func _resolve_hazard_hits_tick() -> void:
	if domain != null and domain.is_configured():
		var resolved: Dictionary = domain.resolve(_session.sim_tick, _session.player_position())
		if not bool(resolved.get("ok", false)):
			_session.battle_report = "hazard_resolve_failed:%s" % String(resolved.get("error", "unknown"))
		else:
			for contact: Dictionary in resolved.get("contacts", []):
				_session.combat_event_stream.emit(_session.sim_tick, "attack_resolved", {
					"action_instance_id": 0,
					"source_id": String(contact.get("source_id", "")),
					"target_id": _session.kit.actor_id(),
					"outcome": "queued",
					"contact_point": contact.get("contact_point", _session.player_position()),
				})
		# Player contacts are consumed after staging and after the kernel has
		# published this tick, preserving the existing fixed-tick boundary.
		if _session.room_combat_port != null:
			var receipts: Array[Dictionary] = _session.room_combat_port.commit_player_contacts(_session.sim_tick)
			for receipt: Dictionary in receipts:
				if String(receipt.get("contact_kind", "")) != "hostile_attack":
					continue
				_session.combat_event_stream.emit(_session.sim_tick, "attack_resolved", {
					"action_instance_id": int(String(receipt.get("attack_instance_id", "0"))),
					"source_id": String(receipt.get("source_id", "")),
					"target_id": _session.kit.actor_id(),
					"outcome": "damage" if bool(receipt.get("accepted", false)) else "avoided",
					"contact_point": _session.player_position(),
				})
		return
	_main.sync_encounter_context()
	var previous_report := String(_session.encounter_director.battle_report)
	_session.encounter_director.resolve_hazard_hits_tick()
	if _session.room_combat_port != null:
		var receipts: Array[Dictionary] = _session.room_combat_port.commit_player_contacts(_session.sim_tick)
		for receipt: Dictionary in receipts:
			if String(receipt.get("contact_kind", "")) != "hostile_attack":
				continue
			_session.combat_event_stream.emit(_session.sim_tick, "attack_resolved", {
				"action_instance_id": int(String(receipt.get("attack_instance_id", "0"))),
				"source_id": String(receipt.get("source_id", "")),
				"target_id": _session.kit.actor_id(),
				"outcome": "damage" if bool(receipt.get("accepted", false)) else "avoided",
				"contact_point": _session.player_position(),
			})
	_main.adopt_encounter_report(previous_report)


func _queue_kernel_hazard_hit(tick: int, amount: float, source_id: String, source_position: Vector2) -> Dictionary:
	return queue_kernel_player_hit(tick, amount, source_id, source_position)


## Stages one room-owned player contact for the next kernel tick. Hazard
## amounts stay integer-valued; enemy impacts use milli units so the existing
## 1.2/1.8 damage values cross SimHit without rounding.
func queue_kernel_player_hit(tick: int, amount: float, source_id: String, source_position: Vector2) -> Dictionary:
	if _session.room_spatial_port == null or _session.actor_registry == null:
		return {"ok": false, "error": "kernel_player_contact_port_unavailable"}
	if tick != _session.sim_tick or not is_finite(amount) or amount <= 0.0 or not source_position.is_finite():
		return {"ok": false, "error": "invalid_kernel_player_contact_context"}
	var contact_kind: StringName
	var encoded_amount: int
	var attack_instance_id := ""
	if source_id.begins_with("hazard/"):
		contact_kind = &"hazard"
		encoded_amount = maxi(1, roundi(amount))
		attack_instance_id = "hazard/%s/%d" % [source_id, tick]
	elif source_id.begins_with("enemy/") or source_id.begins_with("boss/"):
		contact_kind = &"hostile_attack"
		encoded_amount = maxi(1, roundi(amount * 1000.0))
		var action_instance_id := _hostile_action_instance_id(source_id)
		attack_instance_id = str(action_instance_id) if action_instance_id > 0 else "hostile/%s/%d" % [source_id, tick]
	else:
		return {"ok": false, "error": "invalid_kernel_player_contact_source"}
	var target: Variant = _session.actor_registry.actor_handle(_session.kit.actor_id())
	if target == null:
		return {"ok": false, "error": "player_actor_unavailable"}
	return _session.room_spatial_port.queue_player_hit(
		target,
		encoded_amount,
		source_id,
		source_position,
		attack_instance_id,
		contact_kind
	)


func _hostile_action_instance_id(source_id: String) -> int:
	if _session.encounter_director == null:
		return 0
	if source_id.begins_with("enemy/"):
		var parts := source_id.split("/")
		if parts.size() >= 2:
			var enemy: CombatEnemyState = _session.encounter_director._enemy_by_entity_id(int(parts[1]))
			return int(enemy.action_instance_id) if enemy != null else 0
	if source_id.begins_with("boss/") and _session.encounter_director.boss != null:
		return int(_session.encounter_director.boss.action_instance_id)
	return 0


func _new_hazard_state(id: String, center: Vector2) -> Dictionary:
	_main.sync_encounter_context()
	return _session.encounter_director.new_hazard_state(id, center)


func _hazard_contains(state: Dictionary, point: Vector2) -> bool:
	_main.sync_encounter_context()
	return _session.encounter_director.hazard_contains(state, point)
