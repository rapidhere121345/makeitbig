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
const CombatSystemRoomPortScript := preload("res://src/runtime/combat/combat_system_room_port.gd")

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
var combat_event_stream
var manual_aim_resolver
var room_port: RefCounted = null
var _configured := false
var _configuration_error := "player_rule_port_unavailable"
var query_profile: String = QUERY_PROFILE_MULTIPART_V2

## All room interactions go through the typed room port below.


func bind_room(port: Variant, requested_query_profile: String = QUERY_PROFILE_MULTIPART_V2) -> Dictionary:
	_configured = false
	room_port = null
	_configuration_error = "combat_room_port_unavailable"
	query_profile = QUERY_PROFILE_MULTIPART_V2
	if not port is CombatSystemRoomPortScript or not is_instance_valid(port):
		return _failure(_configuration_error)
	if requested_query_profile not in [QUERY_PROFILE_MULTIPART_V2, QUERY_PROFILE_HISTORICAL_CIRCLE_V1]:
		return _failure("invalid_query_profile")
	var typed_port = port
	if not typed_port.is_ready():
		return _failure(_configuration_error)
	room_port = typed_port
	query_profile = requested_query_profile
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
	var resolved: Variant = room_port.target_by_id(id) if room_port != null else null
	if resolved != null:
		return resolved
	for enemy: CombatEnemyState in enemies:
		if enemy.entity_id == id:
			return enemy
	return null


func _aim_candidate(enemy: CombatEnemyState) -> Dictionary:
	if room_port != null:
		var candidate: Variant = room_port.aim_candidate(enemy)
		if not candidate.is_empty():
			return candidate
	return {"entity_id": enemy.entity_id, "kind_id": enemy.kind_id, "position": enemy.position, "health": enemy.health, "is_boss": enemy.is_boss}


func _current_model() -> Dictionary:
	return room_port.current_model() if room_port != null else {}


func _maybe_summon(enemy: CombatEnemyState) -> void:
	if room_port != null:
		room_port.maybe_summon(enemy)


func _remove_target(enemy: CombatEnemyState) -> void:
	if room_port != null:
		room_port.remove_target(enemy)
	# The coordinator's local fixture roster is a read-through cache.  The
	# mounted room port owns the authoritative actor removal; erasing the same
	# object from this cache keeps isolated domain fixtures deterministic.
	enemies.erase(enemy)


func _cancel_buffered_target(entity_id: int) -> int:
	return room_port.cancel_buffered_target(entity_id) if room_port != null else 0


func _update_mark() -> void:
	if room_port != null:
		room_port.update_mark()


func _advance_sequence(kind: String) -> void:
	if room_port != null:
		room_port.advance_sequence(kind)


func _reset_sequence() -> void:
	if room_port != null:
		room_port.reset_sequence()


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


func _erase_attack_request(request_id: int) -> void:
	if room_port != null and request_id > 0:
		room_port.erase_attack_request(request_id)


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


## Advances the legacy player-domain flight loop for normal targets only.
## Production ranger arrows fly through the kernel flight drivers; multipart
## Boss targets resolve exclusively in BossCombatDomain and are rejected by
## resolve_projectile_sweep before any contact can settle here.
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


## Kernel-path contact bookkeeping. The room already resolved damage through
## DamageResolution and mirrored the committed health; this method only owns
## the player-domain telemetry and event publication that legacy contacts
## produced, with identical payloads.
func apply_kernel_contact(
	projectile: CombatArrowProjectile,
	target: CombatEnemyState,
	contact_point: Vector2,
	part_hit: Dictionary,
	health_before: float,
	health_after: float,
	aggregate: BigValue
) -> void:
	if not _combat_ports_ready():
		return
	combat_event_stream.emit(tick, "action_impact", {
		"action_instance_id": projectile.action_instance_id,
		"actor_id": "ranger",
		"action_id": "piercing_arrow",
		"target_entity_id": target.entity_id,
		"part_id": part_hit.get("part_id", "body"), "damage_group_id": part_hit.get("damage_group_id", "body"),
		"contact_point": contact_point,
	})
	_arrow_hits += 1
	_advance_sequence("piercing_arrow")
	impact_trace_requested.emit(contact_point, projectile.direction, int(_current_model()["g"]))
	var outcome := "killed" if health_after <= 0.0 else "damage"
	last_attack_outcome = combat_event_stream.emit(tick, "attack_resolved", {
		"action_instance_id": projectile.action_instance_id, "source_id": "ranger/piercing_arrow",
		"target_entity_id": target.entity_id,
		"part_id": part_hit.get("part_id", "body"), "damage_group_id": part_hit.get("damage_group_id", "body"), "outcome": outcome,
		"contact_point": contact_point, "aggregate_damage": aggregate.to_short_string(6),
	})
	combat_event_stream.emit(tick, "damage_applied", {
		"action_instance_id": projectile.action_instance_id, "source_id": "ranger/piercing_arrow",
		"target_id": "enemy/%d" % target.entity_id, "target_entity_id": target.entity_id,
		"part_id": part_hit.get("part_id", "body"), "damage_group_id": part_hit.get("damage_group_id", "body"),
		"amount": aggregate.to_short_string(6),
		"health_before_milli": roundi(health_before * 1000.0), "health_after_milli": roundi(health_after * 1000.0),
		"boss_remaining_before": "",
		"boss_remaining_after": "",
		"contact_point": contact_point, "incoming_direction": projectile.direction,
	})
	battle_report = "穿刺箭命中：%s 次箭事件 × %.0f 载荷 → %s 总伤害。" % [projectile.event_count.to_short_string(4), projectile.payload, aggregate.to_short_string(4)]


## Kernel-path blocked contact: the room's hit admission gate suppressed the
## hit before DamageResolution, so only the blocked telemetry remains.
func apply_kernel_blocked(
	projectile: CombatArrowProjectile,
	target: CombatEnemyState,
	contact_point: Vector2
) -> void:
	if not _combat_ports_ready() or target == null:
		return
	combat_event_stream.emit(tick, "action_impact", {
		"action_instance_id": projectile.action_instance_id,
		"actor_id": "ranger",
		"action_id": "piercing_arrow",
		"target_entity_id": target.entity_id,
		"part_id": "body", "damage_group_id": "body",
		"contact_point": contact_point,
	})
	_reset_sequence()
	impact_trace_requested.emit(contact_point, projectile.direction, 1)
	last_attack_outcome = combat_event_stream.emit(tick, "attack_resolved", {
		"action_instance_id": projectile.action_instance_id, "source_id": "ranger/piercing_arrow",
		"target_entity_id": target.entity_id,
		"part_id": "body", "damage_group_id": "body", "outcome": "blocked",
		"contact_point": contact_point, "barrier_id": "periodic_barrier",
	})
	battle_report = "穿刺箭被周期屏障阻断。"


## Mirrors the Boss domain's committed BigValue result for the legacy phase
## transition and presentation readers. This is telemetry only: the value is
## derived from DamageResolution output and never feeds back into resolution.
func sync_boss_domain_resolution(maximum: BigValue, applied: BigValue, remaining: BigValue) -> Dictionary:
	if maximum == null or applied == null or remaining == null:
		return _failure("invalid_boss_domain_resolution_mirror")
	if maximum.compare(remaining) < 0 or remaining.layer < 0 or not is_finite(remaining.magnitude):
		return _failure("invalid_boss_domain_resolution_mirror")
	if _boss_maximum.compare(maximum) != 0:
		_boss_maximum = maximum.duplicate_value()
		_boss_damage = BigValue.from_float(0.0)
	_boss_damage = _boss_damage.add(applied)
	if _boss_damage.compare(_boss_maximum) >= 0:
		_boss_damage = _boss_maximum.duplicate_value()
	return {"ok": true, "error": ""}


## Kernel-path Boss contact telemetry. BossCombatDomain already resolved the
## multipart BigValue payload and committed detached health; this boundary only
## publishes the same player-domain events the legacy contact produced.
func apply_boss_kernel_contact(
	projectile: CombatArrowProjectile,
	target: CombatEnemyState,
	contact_point: Vector2,
	part_hit: Dictionary,
	health_before: BigValue,
	health_after: BigValue,
	aggregate: BigValue
) -> void:
	if not _combat_ports_ready() or target == null:
		return
	combat_event_stream.emit(tick, "action_impact", {
		"action_instance_id": projectile.action_instance_id,
		"actor_id": "ranger",
		"action_id": "piercing_arrow",
		"target_entity_id": target.entity_id,
		"part_id": part_hit.get("part_id", "body"),
		"damage_group_id": part_hit.get("damage_group_id", "body"),
		"contact_point": contact_point,
	})
	_arrow_hits += 1
	_advance_sequence("piercing_arrow")
	impact_trace_requested.emit(contact_point, projectile.direction, int(_current_model()["g"]))
	var outcome := "killed" if health_after.is_zero() else "damage"
	last_attack_outcome = combat_event_stream.emit(tick, "attack_resolved", {
		"action_instance_id": projectile.action_instance_id,
		"source_id": "ranger/piercing_arrow",
		"target_entity_id": target.entity_id,
		"part_id": part_hit.get("part_id", "body"),
		"damage_group_id": part_hit.get("damage_group_id", "body"),
		"outcome": outcome,
		"contact_point": contact_point,
		"aggregate_damage": aggregate.to_short_string(6),
	})
	combat_event_stream.emit(tick, "damage_applied", {
		"action_instance_id": projectile.action_instance_id,
		"source_id": "ranger/piercing_arrow",
		"target_id": "enemy/%d" % target.entity_id,
		"target_entity_id": target.entity_id,
		"part_id": part_hit.get("part_id", "body"),
		"damage_group_id": part_hit.get("damage_group_id", "body"),
		"amount": aggregate.to_short_string(6),
		"health_before_milli": 0,
		"health_after_milli": 0,
		"boss_remaining_before": health_before.to_short_string(6) if health_before != null else "",
		"boss_remaining_after": health_after.to_short_string(6) if health_after != null else "",
		"contact_point": contact_point,
		"incoming_direction": projectile.direction,
	})
	battle_report = "穿刺箭命中：%s 次箭事件 × %.0f 载荷 → %s 总伤害。" % [
		projectile.event_count.to_short_string(4),
		projectile.payload,
		aggregate.to_short_string(4),
	]


## Kernel-path death bookkeeping: the kernel already tombstoned the actor and
## DeathSettlement produced its typed receipt; this publishes the legacy
## defeat counters, event and detached corpse request.
func note_kernel_death(target: CombatEnemyState) -> void:
	if target == null:
		return
	_defeated += 1
	combat_event_stream.emit(tick, "death_applied", {
		"source_id": "ranger/piercing_arrow", "target_id": "enemy/%d" % target.entity_id,
		"target_entity_id": target.entity_id,
		"part_id": "body", "damage_group_id": "body", "position": target.position,
	})
	corpse_requested.emit({
		"entity_id": target.entity_id, "kind_id": target.kind_id,
		"position": target.position, "facing": target.facing,
		"is_boss": target.is_boss,
	})


func remove_projectile(projectile: CombatArrowProjectile) -> void:
	projectiles.erase(projectile)


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
	# Deleted legacy Boss branch: multipart BigValue targets resolve only in
	# BossCombatDomain through the kernel flight drivers. A Boss target on this
	# seam fails closed before any query, damage or ledger write can happen.
	if target != null and target.is_boss:
		return _failure("boss_target_requires_boss_domain")
	var query := query_swept_hits(start, finish, target)
	if not bool(query.ok):
		return query
	if _hit_window_tick != tick:
		_hit_window_tick = tick
		_settled_groups.clear()
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
			return _failure(_configuration_error)
		consumed_retained = true
		settled.append(hit.duplicate(true))
	return {"ok": true, "error": "", "candidates": query.candidates, "settled": settled}


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
			"boss_remaining_before": "",
			"boss_remaining_after": "",
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
	if not _configured or room_port == null:
		return _failure("combat_room_port_unavailable")
	var value: Variant = room_port.target_blocked(target)
	if not value is Dictionary:
		return _failure("target_blocked_port_invalid_result")
	var verdict: Dictionary = value
	if not bool(verdict.get("ok", false)):
		return _failure(String(verdict.get("error", "target_blocked_port_unavailable")))
	if typeof(verdict.get("blocked", null)) != TYPE_BOOL:
		return _failure("target_blocked_port_invalid_result")
	return {"ok": true, "error": "", "blocked": bool(verdict.get("blocked", false))}


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


func _combat_ports_ready() -> bool:
	if not _configured:
		if _configuration_error.is_empty():
			_configuration_error = "player_rule_port_unavailable"
		return false
	if room_port == null or not room_port.is_ready():
		_configuration_error = "combat_room_port_unavailable"
		return false
	if not _room_ready:
		_configuration_error = "combat_room_not_reset"
		return false
	_configuration_error = ""
	return true


func _consume_first_critical_bonus() -> int:
	if not _combat_ports_ready():
		return -1
	var value: Variant = room_port.consume_first_critical_bonus()
	if typeof(value) != TYPE_INT or int(value) < 0:
		_configuration_error = "player_rule_port_invalid_critical_result"
		return -1
	return int(value)


func _retain_missed_arrow(aggregate: BigValue, ordinary: float) -> bool:
	if not _combat_ports_ready() or aggregate == null or not is_finite(ordinary):
		_configuration_error = "player_rule_port_invalid_retention_input"
		return false
	return room_port.retain_missed_arrow(aggregate, ordinary)


func _take_retained_arrow() -> Dictionary:
	if not _combat_ports_ready():
		return {"ok": false, "error": _configuration_error}
	var value: Variant = room_port.take_retained_arrow()
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
