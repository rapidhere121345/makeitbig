class_name RoomSpatialPort
extends SimSpatialPort

const BossDomainScript := preload("res://src/runtime/combat/boss_combat_domain.gd")
const BossQueryScript := preload("res://src/runtime/combat/boss_attack_query.gd")
const BossPathResultScript := preload("res://src/runtime/combat/boss_path_result.gd")

## SimulationKernel spatial port for one mounted room.
##
## Explicit path-query protocol: attack and projectile definitions build
## typed PathQuery records and queue them on this port before a tick.  The
## fixed CONTINUOUS_QUERIES phase executes every queued query exactly once
## through the room's ContinuousHitResolver, appends dynamic hit contacts to
## the tick's SimHitBuffer, and publishes typed PathResult records for the
## caller that advanced the path.  There is no generic event bus, no string
## callback, and no attack invented from actor overlap.

var actors: Variant = null

var _path_queries: Array[PathQuery] = []
var _path_results: Array[PathResult] = []
var _hit_resolver: ContinuousHitResolver = null
var boss_domain: BossCombatDomain = null
var _boss_queries: Array[BossAttackQuery] = []
var _boss_path_results: Array[BossPathResult] = []
var _player_hits: Array[PlayerHit] = []

## Typed player contact staged for the next kernel DAMAGE_STATUS phase.
## The hazard helper below uses this same SimHit path; hostile enemy impacts
## use an explicit contact kind and milli payload.
class PlayerHit:
	extends RefCounted

	var target: SimEntityHandle = null
	var amount: int = 0
	var source_key := ""
	var contact_point := Vector2.ZERO
	var attack_instance_id := ""
	var contact_kind: StringName = &""

	func validate() -> String:
		if target == null or not target.is_valid():
			return "player_hit.target_invalid"
		if amount < 1:
			return "player_hit.amount_invalid"
		if source_key.strip_edges().is_empty():
			return "player_hit.source_missing"
		if not contact_point.is_finite():
			return "player_hit.contact_point_invalid"
		if attack_instance_id.strip_edges().is_empty():
			return "player_hit.attack_instance_missing"
		if contact_kind not in [&"hazard", &"hostile_attack"]:
			return "player_hit.contact_kind_invalid"
		return ""


## One explicit attack/projectile sweep for exactly one tick.
##
## The caller owns the path geometry: start the path outside the source's own
## body (the resolver clips a non-piercing path at the first hurtbox it
## touches).  Contacts against the source's own handle are skipped, and
## dynamic hit contacts become SimHit records carrying this query's amount and
## contact kind.
class PathQuery:
	extends RefCounted

	var source: SimEntityHandle = null
	var channel: StringName = &""
	var start: Vector2 = Vector2.ZERO
	var displacement: Vector2 = Vector2.ZERO
	var radius: float = 0.0
	var piercing: bool = false
	var amount: int = 0
	var contact_kind: StringName = &""
	var attack_instance_id := ""
	var part_id := "body"
	var damage_group_id := "body"
	var damage_type := "physical"
	var priority := 0
	var penetration_index := 0
	var allow_repeat_target := false

	static func make(
		from_entity: SimEntityHandle,
		query_channel: StringName,
		path_start: Vector2,
		path_displacement: Vector2,
		path_radius: float,
		hit_amount: int,
		kind: StringName,
		path_piercing: bool = false,
		attack_id: String = "",
		query_part_id: String = "body",
		query_damage_group_id: String = "body",
		query_damage_type: String = "physical",
		query_priority: int = 0,
		query_penetration_index: int = 0,
		query_allow_repeat_target: bool = false
	) -> PathQuery:
		var query := PathQuery.new()
		query.source = from_entity
		query.channel = query_channel
		query.start = path_start
		query.displacement = path_displacement
		query.radius = path_radius
		query.piercing = path_piercing
		query.amount = hit_amount
		query.contact_kind = kind
		query.attack_instance_id = attack_id
		query.part_id = query_part_id
		query.damage_group_id = query_damage_group_id
		query.damage_type = query_damage_type
		query.priority = query_priority
		query.penetration_index = query_penetration_index
		query.allow_repeat_target = query_allow_repeat_target
		return query


## Typed outcome of one executed PathQuery, available after the tick in
## submission order.  Results never outlive the next executed tick.
class PathResult:
	extends RefCounted

	var ok := false
	var errors: Array[String] = []
	var channel: StringName = &""
	var piercing := false
	var clipped := false
	var stop_toi := 0.0
	var end_point := Vector2.ZERO
	var hit_actor_ids: Array[String] = []


func bind(actor_access: Variant) -> void:
	actors = actor_access
	# Binding happens at room-mount boundaries; anything still queued or
	# reported belonged to a previous mount and is dropped fail-closed.
	_path_queries.clear()
	_path_results.clear()
	_boss_queries.clear()
	_boss_path_results.clear()
	_player_hits.clear()
	_hit_resolver = null
	boss_domain = null


## Binds the Boss multipart domain to this room's query phase.  The domain owns
## the typed BossHitBuffer; this port only produces geometry contacts and hit
## facts.  A missing domain is a hard error at queue time.
func bind_boss_domain(domain: Variant) -> Dictionary:
	if not domain is BossDomainScript:
		return _failure("invalid_boss_domain")
	var typed: BossCombatDomain = domain
	if not typed.is_configured():
		return _failure("boss_domain_not_configured")
	boss_domain = typed
	_boss_queries.clear()
	_boss_path_results.clear()
	return {"ok": true, "error": ""}


## Queues one explicit multipart attack for the next fixed CONTINUOUS_QUERIES
## phase.  It is never inferred from actor overlap.
func queue_boss_path_query(query: Variant) -> Dictionary:
	if boss_domain == null:
		return _failure("boss_domain_unbound")
	if not query is BossQueryScript:
		return _failure("invalid_boss_path_query_type")
	var typed: BossAttackQuery = query
	var error := typed.validate()
	if not error.is_empty():
		return _failure(error)
	_boss_queries.append(typed)
	return {"ok": true, "error": "", "pending": _boss_queries.size()}


func pending_boss_path_query_count() -> int:
	return _boss_queries.size()


func take_boss_path_results() -> Array[BossPathResult]:
	return _boss_path_results.duplicate()


## Queues one explicit path query for the next CONTINUOUS_QUERIES phase.
## Shape validation is fail-closed; geometry resolution happens in the tick.
func queue_path_query(query: Variant) -> Dictionary:
	var errors: Array[String] = []
	if not query is PathQuery:
		errors.append("path_query:invalid_type")
		return {"ok": false, "errors": errors}
	var typed: PathQuery = query
	if typed.source == null:
		errors.append("path_query.source:missing")
	if typed.channel != SpatialChannels.PROJECTILE and typed.channel != SpatialChannels.ATTACK:
		errors.append("path_query.channel:invalid:%s" % String(typed.channel))
	if not typed.start.is_finite():
		errors.append("path_query.start:non_finite")
	if not typed.displacement.is_finite():
		errors.append("path_query.displacement:non_finite")
	if not is_finite(typed.radius) or typed.radius < 0.0:
		errors.append("path_query.radius:invalid")
	if typed.amount < 1:
		errors.append("path_query.amount:invalid")
	if typed.contact_kind == &"":
		errors.append("path_query.contact_kind:missing")
	if not errors.is_empty():
		return {"ok": false, "errors": errors}
	_path_queries.append(typed)
	return {"ok": true, "errors": [], "pending": _path_queries.size()}


func pending_path_query_count() -> int:
	return _path_queries.size()


## Queue one authored hazard contact. The hazard domain decides timing and
## containment; the room spatial port only turns the typed fact into SimHit.
func queue_hazard_hit(
	target: Variant,
	amount: int,
	source_key: String,
	contact_point: Vector2,
	attack_instance_id: String
) -> Dictionary:
	return queue_player_hit(target, amount, source_key, contact_point, attack_instance_id, &"hazard")


## Queues one typed player contact for the next fixed DAMAGE_STATUS phase.
## The spatial port does not apply damage; it only turns the fact into SimHit.
## A pending attack identity is accepted once so a repeated producer call
## cannot create two player settlements in the same kernel tick.
func queue_player_hit(
	target: Variant,
	amount: int,
	source_key: String,
	contact_point: Vector2,
	attack_instance_id: String,
	contact_kind: StringName
) -> Dictionary:
	var hit := PlayerHit.new()
	hit.target = target if target is SimEntityHandle else null
	hit.amount = amount
	hit.source_key = source_key
	hit.contact_point = contact_point
	hit.attack_instance_id = attack_instance_id
	hit.contact_kind = contact_kind
	var error := hit.validate()
	if not error.is_empty():
		return {"ok": false, "error": error}
	for pending: PlayerHit in _player_hits:
		if pending.attack_instance_id == hit.attack_instance_id:
			return {"ok": false, "error": "player_hit.duplicate_attack_instance"}
	_player_hits.append(hit)
	return {"ok": true, "error": "", "pending": _player_hits.size()}


## Results of the queries executed by the most recent tick, in queue order.
func take_path_results() -> Array[PathResult]:
	return _path_results.duplicate()


func apply_movement(ctx: SimTickContext) -> void:
	if actors == null:
		return
	for intent: SimIntent in ctx.intents.intents():
		var resolved: SimOutcome = actors.registry.resolve(intent.entity)
		if not resolved.ok:
			continue
		var state: ActorState = resolved.value
		if not state.alive:
			continue
		var actor_id := _actor_id_for_handle(intent.entity)
		if actor_id.is_empty():
			continue
		# CONTROL commands carry a normalized intent. Room-specific speed and
		# action displacement are owned by the caller that creates the command;
		# the generic room port only commits the supplied vector through the
		# room's MovementResolver boundary.
		actors.move_actor(actor_id, intent.move_direction, ctx.tick)


func refresh_dynamic_index(_ctx: SimTickContext) -> void:
	if actors != null:
		actors.sync_dynamic_index()


func run_continuous_queries(ctx: SimTickContext) -> void:
	_path_results.clear()
	_boss_path_results.clear()
	if boss_domain != null:
		var opened := boss_domain.begin_tick(ctx.tick)
		if not bool(opened.get("ok", false)):
			_fail_boss_queries(ctx.tick, String(opened.get("error", "boss_domain_tick_rejected")))
	if _path_queries.is_empty() and _boss_queries.is_empty():
		_flush_player_hits(ctx)
		return
	if actors == null:
		for query: PathQuery in _path_queries:
			var unbound := PathResult.new()
			unbound.channel = query.channel
			unbound.piercing = query.piercing
			unbound.errors.append("path_query:spatial_access_unbound")
			_path_results.append(unbound)
		_path_queries.clear()
		_fail_boss_queries(ctx.tick, "boss_query:spatial_access_unbound")
		_player_hits.clear()
		return
	if _hit_resolver == null:
		var built: Dictionary = ContinuousHitResolver.make(actors.static_index, actors.dynamic_index, actors.overlay)
		if not bool(built.get("ok", false)):
			for query: PathQuery in _path_queries:
				var unavailable := PathResult.new()
				unavailable.channel = query.channel
				unavailable.piercing = query.piercing
				unavailable.errors.append("path_query:resolver_unavailable")
				_path_results.append(unavailable)
			_path_queries.clear()
			_fail_boss_queries(ctx.tick, "boss_query:resolver_unavailable")
			_player_hits.clear()
			return
		_hit_resolver = built["value"]
	while not _path_queries.is_empty():
		var query: PathQuery = _path_queries[0]
		_path_queries.remove_at(0)
		_execute_path_query(query, ctx)
	while not _boss_queries.is_empty():
		var boss_query: BossAttackQuery = _boss_queries[0]
		_boss_queries.remove_at(0)
		_execute_boss_query(boss_query, ctx)
	_flush_player_hits(ctx)


func _flush_player_hits(ctx: SimTickContext) -> void:
	while not _player_hits.is_empty():
		var authored: PlayerHit = _player_hits[0]
		_player_hits.remove_at(0)
		if not authored.validate().is_empty():
			continue
		var hit := SimHit.make(null, authored.target, authored.amount, authored.contact_kind)
		hit.source_key = authored.source_key
		hit.attack_instance_id = authored.attack_instance_id
		hit.damage_group_id = authored.source_key
		hit.contact_point = authored.contact_point
		ctx.hits.append(hit)


func _execute_path_query(query: PathQuery, ctx: SimTickContext) -> void:
	var result := PathResult.new()
	result.channel = query.channel
	result.piercing = query.piercing
	_path_results.append(result)
	var resolved: Dictionary = _hit_resolver.resolve_path({
		"channel": query.channel,
		"start": query.start,
		"displacement": query.displacement,
		"radius": query.radius,
		"piercing": query.piercing,
	})
	if not bool(resolved.get("ok", false)):
		result.errors.append_array(resolved.get("errors", []) as Array)
		return
	result.ok = true
	result.clipped = bool(resolved["clipped"])
	result.stop_toi = float(resolved["stop_toi"])
	result.end_point = resolved["end_point"]
	for entry: Variant in resolved["contacts"]:
		var contact := entry as SpatialContact
		if contact.kind != SpatialContact.KIND_DYNAMIC:
			continue
		if not bool(contact.response.get("hit", false)):
			continue
		# Hit classification is the consumer's contract: a dynamic contact
		# only becomes damage when the path overlaps it or is still entering
		# it.  This mirrors the movement resolver's blocking classification
		# and keeps separating or tangential contacts (for example a body
		# already behind the path start) from being recorded as hits.
		if not contact.penetrating and query.displacement.dot(contact.normal) >= -SpatialShape.DIRECTION_EPSILON:
			continue
		var target: SimEntityHandle = actors.actor_handle(contact.source_id)
		if target == null or target.generation != contact.generation:
			result.errors.append("path_query:target_unresolved:%s:%d" % [contact.source_id, contact.generation])
			continue
		if target == query.source:
			continue
		var hit := SimHit.make(query.source, target, query.amount, query.contact_kind)
		hit.attack_instance_id = query.attack_instance_id
		hit.part_id = query.part_id
		hit.damage_group_id = query.damage_group_id
		hit.damage_type = query.damage_type
		hit.toi = contact.toi
		hit.priority = query.priority
		hit.penetration_index = query.penetration_index
		hit.allow_repeat_target = query.allow_repeat_target
		hit.contact_point = contact.point
		ctx.hits.append(hit)
		result.hit_actor_ids.append(contact.source_id)


func _execute_boss_query(query: BossAttackQuery, ctx: SimTickContext) -> void:
	if boss_domain == null:
		_boss_path_results.append(BossPathResultScript.failure(ctx.tick, query.attack_instance_id, "boss_domain_unbound"))
		return
	var source_key := String(actors.entity_key_for_handle(query.source)) if actors.has_method("entity_key_for_handle") else ""
	var result: BossPathResult = boss_domain.query_path(query, _hit_resolver, source_key)
	_boss_path_results.append(result)


func _fail_boss_queries(at_tick: int, error: String) -> void:
	while not _boss_queries.is_empty():
		var query: BossAttackQuery = _boss_queries[0]
		_boss_queries.remove_at(0)
		_boss_path_results.append(BossPathResultScript.failure(at_tick, query.attack_instance_id, error))


func _actor_id_for_handle(handle: SimEntityHandle) -> String:
	if actors == null or handle == null:
		return ""
	for actor_id: String in actors.actor_ids():
		if actors.actor_handle(actor_id) == handle:
			return actor_id
	return ""


static func _failure(error: String) -> Dictionary:
	return {"ok": false, "error": error}
