class_name PiercingArrows
extends RefCounted

## Piercing-arrow and projectile plumbing extracted from MainArena: casting,
## per-tick kernel flight submission, contact/miss resolution and combat-target
## removal. Combat state stays owned by MainArena and is reached through the
## typed owner reference.

var _main: MainArena
## The room authority; read at use time, never cache its replaced members.
var _session: RoomSession


func _init(main: MainArena) -> void:
	_main = main
	_session = main.session


func _resolve_piercing_arrow(action_event: Dictionary, action_player: Dictionary) -> void:
	_main.sync_combat_context(action_player)
	var previous_report := String(_session.combat_system.battle_report)
	var previous_event_id: int = _session.combat_event_stream.latest_event_id()
	_session.combat_system.resolve_piercing_arrow(action_event)
	_main.adopt_combat_report(previous_report, previous_event_id)


func _current_projectile_speed() -> float:
	var speed := 0.0
	if not _session.locked_build.is_empty():
		speed = float((_session.locked_build.get("final_parameters", {}) as Dictionary).get("v", 0.0))
	elif _main.content_registry != null:
		speed = float(_main.content_registry.preset_equipped_parameters.get("speed", 0.0))
	if not is_finite(speed) or speed <= 0.0:
		return 1.0
	return speed


func _advance_piercing_projectiles_tick() -> void:
	_main.sync_combat_context()
	var previous_report := String(_session.combat_system.battle_report)
	var previous_event_id: int = _session.combat_event_stream.latest_event_id()
	# Every production ranger arrow flies through the mounted kernel. Normal
	# targets use PathQuery/SimHit; Boss targets use BossAttackQuery and the
	# multipart BossHitBuffer. Both paths resolve in the fixed
	# CONTINUOUS_QUERIES/DAMAGE_STATUS phases; neither may settle here.
	if _session.room_spatial_port != null and _session.room_combat_port != null and _session.kernel_bindings.arrow_flight.is_configured():
		var ranger_handle = _session.actor_registry.actor_handle("ranger") if _session.actor_registry != null else null
		_session.kernel_bindings.arrow_flight.submit_tick(
			_session.combat_system.projectiles,
			ranger_handle,
			_session.sim_tick,
			_session.combat_system.room_port
		)
	if _session.room_spatial_port != null and _session.room_combat_port != null and _session.kernel_bindings.boss_flight.is_configured() and _main.kernel_reconciler.boss_domain_room_is_current():
		var ranger_handle = _session.actor_registry.actor_handle("ranger") if _session.actor_registry != null else null
		_session.kernel_bindings.boss_flight.submit_tick(
			_session.combat_system.projectiles,
			ranger_handle,
			_session.sim_tick,
			_session.combat_system.room_port
		)
	_main.adopt_combat_report(previous_report, previous_event_id)


func _resolve_piercing_arrow_contact(projectile: CombatArrowProjectile, target: CombatEnemyState, contact_point: Vector2) -> void:
	_main.sync_combat_context()
	var previous_report := String(_session.combat_system.battle_report)
	var previous_event_id: int = _session.combat_event_stream.latest_event_id()
	_session.combat_system.resolve_projectile_contact(projectile, target, contact_point)
	_main.adopt_combat_report(previous_report, previous_event_id)


func _resolve_piercing_arrow_miss(projectile: CombatArrowProjectile) -> void:
	_main.sync_combat_context()
	var previous_report := String(_session.combat_system.battle_report)
	var previous_event_id: int = _session.combat_event_stream.latest_event_id()
	_session.combat_system.resolve_projectile_miss(projectile)
	_main.adopt_combat_report(previous_report, previous_event_id)


func _piercing_arrow_swept_contact(start: Vector2, finish: Vector2, target: CombatEnemyState) -> Variant:
	_main.sync_combat_context()
	return _session.combat_system.swept_contact(start, finish, target)


func remove_combat_target(target: CombatEnemyState) -> void:
	_main.enemies.erase(target)
	if target == null or target.health > 0.0:
		return
	var actor_id := "enemy/%d" % target.entity_id
	if _session.actor_registry != null and _session.actor_registry.has_actor(actor_id):
		var unregistered: Dictionary = _session.actor_registry.unregister_actor(actor_id)
		if not bool(unregistered.get("ok", false)):
			push_error("enemy_actor_unregister_failed:%d:%s" % [target.entity_id, String(unregistered.get("error", "unknown"))])
	_main.spawn_room_loot_for_source("enemy_death", target.entity_id, target.position)


func cancel_buffered_target(entity_id: int) -> int:
	return _session.player_combat_rules.cancel_buffered_target(entity_id)


func erase_attack_request(request_id: int) -> void:
	if request_id > 0:
		_session.record_event(RoomPresentationEvent.request_forgotten(request_id))
