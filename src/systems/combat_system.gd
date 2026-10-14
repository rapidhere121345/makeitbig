class_name CombatSystem
extends RefCounted

## Authoritative ranged combat system.
##
## Owns the player action's projectile lifecycle, swept contact, damage
## resolution and room outcome totals. It has no scene-tree, input or drawing code.
## Encounter and presentation effects cross this boundary through explicit
## callbacks. Cosmetic notifications carry values and never mutate UI state.

signal impact_trace_requested(position: Vector2, direction: Vector2, generations: int)
signal corpse_requested(visual: Dictionary)

const CombatQueryScript := preload("res://src/runtime/geometry/combat_query.gd")
const CombatArrowProjectileScript := preload("res://src/runtime/world/combat_arrow_projectile.gd")
const PiercingArrowModelScript := preload("res://src/systems/piercing_arrow_model.gd")
const RangerSkillRulesScript := preload("res://src/systems/ranger_skill_rules.gd")

const SIM_STEP_SECONDS: float = 1.0 / 30.0
const HUNTER_MARK_DAMAGE_MULTIPLIER: float = RangerSkillRulesScript.HUNTER_MARK_DAMAGE_MULTIPLIER
const ENEMY_HIT_FLASH_TICKS: int = 3
const MAX_ACTIVE_PIERCING_PROJECTILES: int = 16
## The live game uses the multipart query. Historical replay verification is an
## explicitly versioned contract and must never be selected implicitly.
const QUERY_PROFILE_MULTIPART_V2 := "multipart_v2"
const QUERY_PROFILE_HISTORICAL_CIRCLE_V1 := "historical_circle_v1"

var tick := 0
var player_position := Vector2.ZERO
var player_facing := Vector2.RIGHT
var locked_payload := 160.0
var locked_targeting_distance := 225.0
var projectile_speed := 1.0
var marked_entity_id := 0
var talent_capabilities: Dictionary = {}
var _boss_damage: BigValue = BigValue.from_float(0.0)
var _boss_maximum: BigValue = BigValue.from_float(0.0)
var _defeated := 0
var _room_ready := false
var enemies: Array[CombatEnemyState] = []
var projectiles: Array[CombatArrowProjectile] = []
var attack_origins: Dictionary = {}
var _shots := 0
var _arrow_hits := 0
var shots: int:
	get:
		return _shots
var arrow_hits: int:
	get:
		return _arrow_hits
var last_attack_outcome: Dictionary = {}
var battle_report := ""
# A fixed tick is one damage commit window. Keys contain domain IDs only.
var _hit_window_tick := -1
var _settled_groups: Dictionary = {}
var _advancing_projectiles := false
var _contact_submission_depth := 0
var _part_commit_targets: Array[CombatEnemyState] = []
var combat_event_stream
var manual_aim_resolver
var _player_rule_port: Object
var _configured := false
var _configuration_error := "player_rule_port_unavailable"
var query_profile: String = QUERY_PROFILE_MULTIPART_V2

var target_by_id_callback: Callable
var aim_candidate_callback: Callable
var current_model_callback: Callable
var target_blocked_callback: Callable
var maybe_summon_callback: Callable
var remove_target_callback: Callable
var cancel_buffered_target_callback: Callable
var update_mark_callback: Callable
var advance_sequence_callback: Callable
var reset_sequence_callback: Callable
var erase_attack_request_callback: Callable


func configure(callbacks: Dictionary) -> Dictionary:
	_configured = false
	_player_rule_port = null
	_configuration_error = "player_rule_port_unavailable"
	query_profile = QUERY_PROFILE_MULTIPART_V2
	var player_rule_port_value: Variant = callbacks.get("player_rule_port", null)
	if not _is_valid_player_rule_port(player_rule_port_value):
		return _failure(_configuration_error)
	var blocked_port: Variant = callbacks.get("target_blocked", null)
	if not blocked_port is Callable or not (blocked_port as Callable).is_valid():
		_configuration_error = "target_blocked_port_unavailable"
		return _failure(_configuration_error)
	var query_profile_value: Variant = callbacks.get("query_profile", QUERY_PROFILE_MULTIPART_V2)
	if typeof(query_profile_value) != TYPE_STRING or String(query_profile_value) not in [QUERY_PROFILE_MULTIPART_V2, QUERY_PROFILE_HISTORICAL_CIRCLE_V1]:
		_configuration_error = "invalid_query_profile"
		return _failure(_configuration_error)
	query_profile = String(query_profile_value)
	_player_rule_port = player_rule_port_value as Object
	target_by_id_callback = callbacks.get("target_by_id", Callable())
	aim_candidate_callback = callbacks.get("aim_candidate", Callable())
	current_model_callback = callbacks.get("current_model", Callable())
	target_blocked_callback = callbacks.get("target_blocked", Callable())
	maybe_summon_callback = callbacks.get("maybe_summon", Callable())
	remove_target_callback = callbacks.get("remove_target", Callable())
	cancel_buffered_target_callback = callbacks.get("cancel_buffered_target", Callable())
	update_mark_callback = callbacks.get("update_mark", Callable())
	advance_sequence_callback = callbacks.get("advance_sequence", Callable())
	reset_sequence_callback = callbacks.get("reset_sequence", Callable())
	erase_attack_request_callback = callbacks.get("erase_attack_request", Callable())
	_configured = true
	_configuration_error = ""
	return {"ok": true, "error": ""}


func set_context(
	new_tick: int,
	new_player_position: Vector2,
	new_player_facing: Vector2,
	new_locked_payload: float,
	new_targeting_distance: float,
	new_projectile_speed: float,
	new_marked_entity_id: int,
	new_talent_capabilities: Dictionary,
	event_stream,
	resolver,
	new_enemies: Array[CombatEnemyState]
) -> Dictionary:
	if not _combat_ports_ready():
		return _failure(_configuration_error if not _configuration_error.is_empty() else "player_rule_port_unavailable")
	tick = maxi(0, new_tick)
	player_position = new_player_position
	player_facing = new_player_facing
	locked_payload = new_locked_payload
	locked_targeting_distance = new_targeting_distance
	projectile_speed = new_projectile_speed if is_finite(new_projectile_speed) and new_projectile_speed > 0.0 else 1.0
	marked_entity_id = new_marked_entity_id
	talent_capabilities = new_talent_capabilities
	combat_event_stream = event_stream
	manual_aim_resolver = resolver
	enemies = new_enemies
	return {"ok": true, "error": ""}


func _target_by_id(id: int) -> CombatEnemyState:
	if target_by_id_callback.is_valid():
		return target_by_id_callback.call(id)
	for enemy: CombatEnemyState in enemies:
		if enemy.entity_id == id:
			return enemy
	return null


func _aim_candidate(enemy: CombatEnemyState) -> Dictionary:
	if aim_candidate_callback.is_valid():
		var value: Variant = aim_candidate_callback.call(enemy)
		return value if value is Dictionary else {}
	return {"entity_id": enemy.entity_id, "kind_id": enemy.kind_id, "position": enemy.position, "health": enemy.health, "is_boss": enemy.is_boss}


func _current_model() -> Dictionary:
	if not current_model_callback.is_valid():
		return {}
	var value: Variant = current_model_callback.call()
	return value if value is Dictionary else {}


func _maybe_summon(enemy: CombatEnemyState) -> void:
	if maybe_summon_callback.is_valid():
		maybe_summon_callback.call(enemy)


func _remove_target(enemy: CombatEnemyState) -> void:
	if remove_target_callback.is_valid():
		remove_target_callback.call(enemy)
	else:
		enemies.erase(enemy)


func _cancel_buffered_target(entity_id: int) -> int:
	if not cancel_buffered_target_callback.is_valid():
		return 0
	return int(cancel_buffered_target_callback.call(entity_id))


func _update_mark() -> void:
	if update_mark_callback.is_valid():
		update_mark_callback.call()


func _advance_sequence(kind: String) -> void:
	if advance_sequence_callback.is_valid():
		advance_sequence_callback.call(kind)


func _reset_sequence() -> void:
	if reset_sequence_callback.is_valid():
		reset_sequence_callback.call()


## Explicit room boundary. Context updates never write the outcome ledger.
func reset_room(new_boss_maximum: BigValue) -> Dictionary:
	if new_boss_maximum == null or new_boss_maximum.layer < 0 or not is_finite(new_boss_maximum.magnitude) or new_boss_maximum.magnitude < 0.0:
		return _failure("invalid_boss_maximum")
	if _advancing_projectiles or _contact_submission_depth > 0:
		return _failure("combat_commit_in_progress")
	_boss_maximum = new_boss_maximum.duplicate_value()
	_boss_damage = BigValue.from_float(0.0)
	_defeated = 0
	_shots = 0
	_arrow_hits = 0
	projectiles.clear()
	attack_origins.clear()
	# Do not clear the injected array: it may belong to the encounter authority.
	enemies = []
	_hit_window_tick = -1
	_settled_groups.clear()
	_part_commit_targets.clear()
	last_attack_outcome = {}
	battle_report = ""
	_room_ready = true
	return {"ok": true, "error": ""}


func outcome_snapshot() -> Dictionary:
	return {
		"boss_damage": _boss_damage.duplicate_value(),
		"boss_maximum": _boss_maximum.duplicate_value(),
		"defeated": _defeated, "shots": _shots, "arrow_hits": _arrow_hits,
	}


## Preserve the previous display subtraction exactly. Defeat uses compare().
func remaining_boss_health() -> BigValue:
	if not enemies.any(func(enemy: CombatEnemyState) -> bool: return enemy.is_boss):
		return BigValue.from_float(0.0)
	if _boss_damage.compare(_boss_maximum) >= 0:
		return BigValue.from_float(0.0)
	if _boss_damage.layer == 0 and _boss_maximum.layer == 0:
		return BigValue.from_float(maxf(0.0, _boss_maximum.magnitude - _boss_damage.magnitude))
	return _boss_maximum.duplicate_value()


func _erase_attack_request(request_id: int) -> void:
	if erase_attack_request_callback.is_valid() and request_id > 0:
		erase_attack_request_callback.call(request_id)


func resolve_piercing_arrow(action_event: Dictionary) -> void:
	var action_instance_id := int(action_event.get("action_instance_id", 0))
	var release_tick := int(action_event.get("tick", tick))
	var target_entity_id := int(action_event.get("target_entity_id", 0))
	if not _combat_ports_ready():
		_reject_player_rule_action(action_instance_id, target_entity_id)
		return
	var aim_data: Dictionary = action_event.get("aim_direction_milli", {})
	var aim := Vector2(float(aim_data.get("x", 0)), float(aim_data.get("y", 0))) / 1000.0
	if aim == Vector2.ZERO:
		aim = player_facing if player_facing != Vector2.ZERO else Vector2.RIGHT
	aim = aim.normalized()
	var origin_state: Variant = attack_origins.get(action_instance_id, {})
	var origin := player_position
	if origin_state is Dictionary:
		## Windup allows reduced movement. Spawn from the hand's release-frame socket
		## at the Ranger's current feet so the first arrow frame cannot lag behind the
		## moving actor. Direction, range, speed and damage remain frozen separately.
		origin = player_position + ((origin_state as Dictionary).get("release_offset", Vector2.ZERO) as Vector2)
		aim = (origin_state as Dictionary).get("direction", aim)
	var target := _target_by_id(target_entity_id)
	_shots += 1
	if projectiles.size() >= MAX_ACTIVE_PIERCING_PROJECTILES:
		last_attack_outcome = combat_event_stream.emit(release_tick, "attack_resolved", {
			"action_instance_id": action_instance_id, "source_id": "ranger/piercing_arrow",
			"target_entity_id": target_entity_id, "outcome": "miss",
			"contact_point": origin, "reason": "projectile_limit",
		})
		battle_report = "穿刺箭未能离弦：场上箭矢已达上限。"
		return
	var model: Dictionary = _current_model()
	if String(model.state) == PiercingArrowModelScript.STATE_CRITICAL:
		var bonus := _consume_first_critical_bonus()
		if bonus < 0:
			_reject_player_rule_action(action_instance_id, target_entity_id)
			return
		if bonus > 0:
			model.g = int(model.g) + bonus
			model.total_events = (model.total_events as BigValue).add(BigValue.from_float(float(bonus)))
			model.total_events_float = float(model.total_events_float) + float(bonus)
	var target_marked := target != null and target.entity_id == marked_entity_id
	var damage_multiplier := HUNTER_MARK_DAMAGE_MULTIPLIER if target_marked else 1.0
	var aggregate_damage: BigValue = (model["total_events"] as BigValue).multiply(BigValue.from_float(locked_payload * damage_multiplier))
	var ordinary_damage := float(model["total_events_float"]) * locked_payload * damage_multiplier
	var speed: float = current_projectile_speed()
	var projectile := CombatArrowProjectileScript.new(
		action_instance_id,
		target_entity_id,
		release_tick,
		origin,
		aim,
		locked_targeting_distance,
		speed,
		aggregate_damage,
		ordinary_damage,
		model["total_events"] as BigValue,
		locked_payload
	)
	projectiles.append(projectile)
	combat_event_stream.emit(release_tick, "projectile_spawned", {
		"action_instance_id": action_instance_id,
		"source_id": "ranger/piercing_arrow",
		"target_entity_id": target_entity_id,
		"origin": origin,
		"direction": aim,
		"maximum_range_milli": roundi(projectile.maximum_range * 1000.0),
		"speed_milli": roundi(projectile.speed * 1000.0),
	})
	battle_report = "穿刺箭已离弦。"


func current_projectile_speed() -> float:
	return projectile_speed


func advance_projectiles_tick() -> void:
	if not _combat_ports_ready():
		_reject_player_rule_action()
		return
	_advancing_projectiles = true
	for index: int in range(projectiles.size() - 1, -1, -1):
		var projectile := projectiles[index]
		## The release tick must present the arrow on the authored bow-hand socket.
		## Travel begins on the following fixed tick, preventing the first rendered
		## frame from jumping one full 30 Hz step away from the Ranger.
		if projectile.spawned_tick >= tick:
			projectile.previous_position = projectile.position
			continue
		var remaining := maxf(0.0, projectile.maximum_range - projectile.distance_travelled)
		var step := minf(projectile.speed * SIM_STEP_SECONDS, remaining)
		projectile.previous_position = projectile.position
		projectile.distance_travelled = minf(projectile.maximum_range, projectile.distance_travelled + step)
		var next_position := projectile.origin + projectile.direction * projectile.distance_travelled
		var target := _target_by_id(projectile.target_entity_id)
		var result := resolve_projectile_sweep(projectile, target, projectile.previous_position, next_position)
		if not bool(result.ok):
			last_attack_outcome = combat_event_stream.emit(tick, "attack_resolved", {
				"action_instance_id": projectile.action_instance_id, "target_entity_id": projectile.target_entity_id,
				"outcome": "rejected", "reason": String(result.error),
			})
			projectiles.remove_at(index)
			continue
		if not (result.candidates as Array).is_empty():
			projectile.position = result.candidates[0].contact_point
			projectiles.remove_at(index)
			continue
		projectile.position = next_position
		if projectile.distance_travelled >= projectile.maximum_range:
			resolve_projectile_miss(projectile)
			projectiles.remove_at(index)

	_advancing_projectiles = false
	_commit_part_states()


func resolve_projectile_contact(projectile: CombatArrowProjectile, target: CombatEnemyState, contact_point: Vector2) -> void:
	var result := resolve_projectile_sweep(projectile, target, contact_point, contact_point)
	if not bool(result.ok):
		_configuration_error = String(result.error)
		_reject_player_rule_action(projectile.action_instance_id if projectile != null else 0, projectile.target_entity_id if projectile != null else 0)


## Same authority path used by fixed-tick flight and headless domain callers.
## The query freezes all candidates before callbacks or damage can queue changes.
## Deduplication lasts for this fixed tick, across repeated sweep submissions.
func resolve_projectile_sweep(projectile: CombatArrowProjectile, target: CombatEnemyState, start: Vector2, finish: Vector2) -> Dictionary:
	if not _combat_ports_ready():
		return _failure(_configuration_error)
	if projectile == null or projectile.action_instance_id <= 0 or (target != null and projectile.target_entity_id != target.entity_id):
		return _failure("invalid_projectile_target")
	var query := query_swept_hits(start, finish, target)
	if not bool(query.ok):
		return query
	if _hit_window_tick != tick:
		_hit_window_tick = tick
		_settled_groups.clear()
	if target != null and not _part_commit_targets.has(target):
		_part_commit_targets.append(target)
	var settled: Array[Dictionary] = []
	var consumed_retained := false
	for hit: Dictionary in query.candidates:
		if target.health <= 0.0:
			break
		var key := [projectile.action_instance_id, target.entity_id, String(hit.damage_group_id)]
		if _settled_groups.has(key):
			continue
		_settled_groups[key] = true
		_contact_submission_depth += 1
		var applied := _apply_projectile_contact(projectile, target, hit.contact_point, hit, not consumed_retained)
		_contact_submission_depth -= 1
		if not applied:
			_settled_groups.erase(key)
			if not _advancing_projectiles:
				_commit_part_states()
			return _failure(_configuration_error)
		consumed_retained = true
		settled.append(hit.duplicate(true))
	if not _advancing_projectiles:
		_commit_part_states()
	return {"ok": true, "error": "", "candidates": query.candidates, "settled": settled}


func _commit_part_states() -> void:
	# Include untouched enemies: encounter transitions must commit even when
	# there are no arrows. Retain contacted targets too if a kill removed them.
	for target: CombatEnemyState in enemies:
		if not _part_commit_targets.has(target):
			_part_commit_targets.append(target)
	for target: CombatEnemyState in _part_commit_targets:
		target.commit_part_states()
	_part_commit_targets.clear()


func _apply_projectile_contact(projectile: CombatArrowProjectile, target: CombatEnemyState, contact_point: Vector2, part_hit: Dictionary = {}, consume_retained: bool = true) -> bool:
	if not _combat_ports_ready():
		_reject_player_rule_action(projectile.action_instance_id, projectile.target_entity_id)
		return false
	if target == null or target.health <= 0.0:
		return true
	var blocked := target_is_currently_blocked(target)
	if not bool(blocked.ok):
		_configuration_error = String(blocked.error)
		_reject_player_rule_action(projectile.action_instance_id, projectile.target_entity_id)
		return false
	combat_event_stream.emit(tick, "action_impact", {
		"action_instance_id": projectile.action_instance_id,
		"actor_id": "ranger",
		"action_id": "piercing_arrow",
		"target_entity_id": target.entity_id,
		"part_id": part_hit.get("part_id", "body"), "damage_group_id": part_hit.get("damage_group_id", "body"),
		"contact_point": contact_point,
	})
	if bool(blocked.blocked):
		_reset_sequence()
		impact_trace_requested.emit(contact_point, projectile.direction, 1)
		last_attack_outcome = combat_event_stream.emit(tick, "attack_resolved", {
			"action_instance_id": projectile.action_instance_id, "source_id": "ranger/piercing_arrow",
			"target_entity_id": target.entity_id,
			"part_id": part_hit.get("part_id", "body"), "damage_group_id": part_hit.get("damage_group_id", "body"), "outcome": "blocked",
			"contact_point": contact_point, "barrier_id": "periodic_barrier",
		})
		battle_report = "穿刺箭被周期屏障阻断。"
		return true
	if consume_retained:
		var retained := _take_retained_arrow()
		if not bool(retained.get("ok", false)):
			_reject_player_rule_action(projectile.action_instance_id, projectile.target_entity_id)
			return false
		projectile.aggregate_damage = projectile.aggregate_damage.add(retained["aggregate"] as BigValue)
		projectile.ordinary_damage += float(retained["ordinary"])
	_arrow_hits += 1
	var health_before := target.health
	_advance_sequence("piercing_arrow")
	var boss_before := remaining_boss_health().to_short_string(6) if target.is_boss else ""
	if target.is_boss:
		_boss_damage = _boss_damage.add(projectile.aggregate_damage)
		if _boss_damage.compare(_boss_maximum) >= 0:
			target.health = 0.0
	else:
		target.health = snappedf(maxf(0.0, target.health - projectile.ordinary_damage), 0.001)
		_maybe_summon(target)
	target.hit_flash_until_tick = tick + ENEMY_HIT_FLASH_TICKS
	impact_trace_requested.emit(contact_point, projectile.direction, int(_current_model()["g"]))
	var outcome := "killed" if target.health <= 0.0 else "damage"
	last_attack_outcome = combat_event_stream.emit(tick, "attack_resolved", {
		"action_instance_id": projectile.action_instance_id, "source_id": "ranger/piercing_arrow",
		"target_entity_id": target.entity_id,
		"part_id": part_hit.get("part_id", "body"), "damage_group_id": part_hit.get("damage_group_id", "body"), "outcome": outcome,
		"contact_point": contact_point, "aggregate_damage": projectile.aggregate_damage.to_short_string(6),
	})
	combat_event_stream.emit(tick, "damage_applied", {
		"action_instance_id": projectile.action_instance_id, "source_id": "ranger/piercing_arrow",
		"target_id": "enemy/%d" % target.entity_id, "target_entity_id": target.entity_id,
		"part_id": part_hit.get("part_id", "body"), "damage_group_id": part_hit.get("damage_group_id", "body"),
		"amount": projectile.aggregate_damage.to_short_string(6),
		"health_before_milli": roundi(health_before * 1000.0), "health_after_milli": roundi(target.health * 1000.0),
		"boss_remaining_before": boss_before,
		"boss_remaining_after": remaining_boss_health().to_short_string(6) if target.is_boss else "",
		"contact_point": contact_point, "incoming_direction": projectile.direction,
	})
	battle_report = "穿刺箭命中：%s 次箭事件 × %.0f 载荷 → %s 总伤害。" % [projectile.event_count.to_short_string(4), projectile.payload, projectile.aggregate_damage.to_short_string(4)]
	if target.health <= 0.0:
		_defeated += 1
		combat_event_stream.emit(tick, "death_applied", {
			"source_id": "ranger/piercing_arrow", "target_id": "enemy/%d" % target.entity_id,
			"target_entity_id": target.entity_id,
			"part_id": part_hit.get("part_id", "body"), "damage_group_id": part_hit.get("damage_group_id", "body"), "position": target.position,
		})
		_remove_target(target)
		var canceled_request_id: int = _cancel_buffered_target(target.entity_id)
		if canceled_request_id > 0:
				_erase_attack_request(canceled_request_id)
		## Presentation only: the detached death clip plays where the simulation
		## killed the enemy and never delays the despawn itself.
		corpse_requested.emit({
			"entity_id": target.entity_id, "kind_id": target.kind_id,
			"position": target.position, "facing": target.facing,
			"is_boss": target.is_boss,
		})
		_update_mark()

	return true


func resolve_projectile_miss(projectile: CombatArrowProjectile) -> void:
	if not _combat_ports_ready():
		_reject_player_rule_action(projectile.action_instance_id, projectile.target_entity_id)
		return
	var target := _target_by_id(projectile.target_entity_id)
	_reset_sequence()
	var target_invalid := target == null or target.health <= 0.0
	var reason := "target_invalid" if target_invalid else "left_frozen_path"
	var retention := clampf(float(talent_capabilities.get("expiry_payload_retention", 0.0)), 0.0, 1.0)
	# The player domain owns the retention ratio and the retained payload. The
	# ratio kept in the event is read-only build telemetry; CombatSystem never
	# reconstructs or stores the retained values locally.
	if not _retain_missed_arrow(projectile.aggregate_damage, projectile.ordinary_damage):
		_reject_player_rule_action(projectile.action_instance_id, projectile.target_entity_id)
		return
	last_attack_outcome = combat_event_stream.emit(tick, "attack_resolved", {
		"action_instance_id": projectile.action_instance_id, "source_id": "ranger/piercing_arrow",
		"target_entity_id": projectile.target_entity_id, "outcome": "miss",
		"contact_point": projectile.position, "reason": reason,
		"retained_payload_ratio": clampf(float(talent_capabilities.get("expiry_payload_retention", 0.0)), 0.0, 1.0),
	})
	if retention > 0.0:
		battle_report = "穿刺箭落空：保留 %.0f%% 载荷，待下一支命中箭兑现。" % (retention * 100.0)
	else:
		battle_report = "穿刺箭落空：锁定目标已失效。" if reason == "target_invalid" else "穿刺箭落空：锁定目标已离开冻结弹道。"


## Read-only encounter port. A malformed answer is a rejection, never damage.
func target_is_currently_blocked(target: CombatEnemyState) -> Dictionary:
	if not _configured or not target_blocked_callback.is_valid():
		return _failure("target_blocked_port_unavailable")
	var value: Variant = target_blocked_callback.call(target)
	if typeof(value) != TYPE_BOOL:
		return _failure("target_blocked_port_invalid_result")
	return {"ok": true, "error": "", "blocked": value}


## Pure query with an explicit failure result; missing Boss shapes never fall
## back to the legacy aim circle. Selection/aiming remains a separate concern.
func query_swept_hits(start: Vector2, finish: Vector2, target: CombatEnemyState) -> Dictionary:
	if target == null or target.health <= 0.0:
		return {"ok": true, "error": "", "candidates": []}
	if target.is_boss and query_profile == QUERY_PROFILE_HISTORICAL_CIRCLE_V1:
		return _query_historical_boss_circle(start, finish, target)
	if target.is_boss or not target.parts.is_empty():
		return CombatQueryScript.swept_parts(start, finish, target.entity_id, target.position, target.hurtbox_parts())
	if manual_aim_resolver == null:
		return _failure("aim_resolver_unavailable")
	var candidate := _aim_candidate(target)
	var anchor: Vector2 = manual_aim_resolver.target_anchor(candidate)
	var radius: float = manual_aim_resolver.target_radius(candidate)
	var contact: Variant = CombatQueryScript.swept_circle_contact(start, finish, anchor, radius) if radius > 0.0 else null
	var candidates: Array[Dictionary] = []
	if contact != null:
		candidates.append({"target_entity_id": target.entity_id, "part_id": "body", "damage_group_id": "body", "contact_point": contact})
	return {"ok": true, "error": "", "candidates": candidates}


## Versioned replay geometry only. It is selected by the historical replay
## command line contract, never by a missing or malformed multipart snapshot.
func _query_historical_boss_circle(start: Vector2, finish: Vector2, target: CombatEnemyState) -> Dictionary:
	if manual_aim_resolver == null:
		return _failure("aim_resolver_unavailable")
	var candidate := _aim_candidate(target)
	var anchor: Vector2 = manual_aim_resolver.target_anchor(candidate)
	var radius: float = manual_aim_resolver.target_radius(candidate)
	var contact: Variant = CombatQueryScript.swept_circle_contact(start, finish, anchor, radius) if radius > 0.0 else null
	var candidates: Array[Dictionary] = []
	if contact != null:
		candidates.append({"target_entity_id": target.entity_id, "part_id": "body", "damage_group_id": "body", "contact_point": contact})
	return {"ok": true, "error": "", "candidates": candidates}


func swept_contact(start: Vector2, finish: Vector2, target: CombatEnemyState) -> Variant:
	var result := query_swept_hits(start, finish, target)
	if not bool(result.ok) or (result.candidates as Array).is_empty():
		return null
	return result.candidates[0].contact_point


func _is_valid_player_rule_port(value: Variant) -> bool:
	if not value is Object:
		return false
	var port := value as Object
	if not is_instance_valid(port):
		return false
	for method: String in ["consume_first_critical_bonus", "retain_missed_arrow", "take_retained_arrow"]:
		if not port.has_method(method):
			return false
	return true


func _combat_ports_ready() -> bool:
	if not _configured:
		if _configuration_error.is_empty():
			_configuration_error = "player_rule_port_unavailable"
		return false
	if not _is_valid_player_rule_port(_player_rule_port):
		_configuration_error = "player_rule_port_unavailable"
		return false
	if not target_blocked_callback.is_valid():
		_configuration_error = "target_blocked_port_unavailable"
		return false
	if not _room_ready:
		_configuration_error = "combat_room_not_reset"
		return false
	_configuration_error = ""
	return true


func _consume_first_critical_bonus() -> int:
	if not _combat_ports_ready():
		return -1
	var value: Variant = _player_rule_port.call("consume_first_critical_bonus")
	if typeof(value) != TYPE_INT or int(value) < 0:
		_configuration_error = "player_rule_port_invalid_critical_result"
		return -1
	return int(value)


func _retain_missed_arrow(aggregate: BigValue, ordinary: float) -> bool:
	if not _combat_ports_ready() or aggregate == null or not is_finite(ordinary):
		_configuration_error = "player_rule_port_invalid_retention_input"
		return false
	_player_rule_port.call("retain_missed_arrow", aggregate, ordinary)
	return true


func _take_retained_arrow() -> Dictionary:
	if not _combat_ports_ready():
		return {"ok": false, "error": _configuration_error}
	var value: Variant = _player_rule_port.call("take_retained_arrow")
	if not value is Dictionary:
		_configuration_error = "player_rule_port_invalid_retained_result"
		return {"ok": false, "error": _configuration_error}
	var aggregate: Variant = (value as Dictionary).get("aggregate", null)
	var ordinary: Variant = (value as Dictionary).get("ordinary", null)
	if not aggregate is BigValue or typeof(ordinary) not in [TYPE_INT, TYPE_FLOAT] or ordinary is bool or not is_finite(float(ordinary)):
		_configuration_error = "player_rule_port_invalid_retained_result"
		return {"ok": false, "error": _configuration_error}
	return {"ok": true, "error": "", "aggregate": aggregate, "ordinary": float(ordinary)}


func _reject_player_rule_action(action_instance_id: int = 0, target_entity_id: int = 0) -> void:
	var reason := _configuration_error if not _configuration_error.is_empty() else "player_rule_port_unavailable"
	last_attack_outcome = {
		"action_instance_id": action_instance_id,
		"source_id": "ranger/piercing_arrow",
		"target_entity_id": target_entity_id,
		"outcome": "rejected",
		"reason": reason,
	}
	battle_report = "穿刺箭拒绝：战斗依赖无效（%s）。" % reason


static func _failure(error: String) -> Dictionary:
	return {"ok": false, "error": error}
