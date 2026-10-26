extends SceneTree

## Mounted production Boss kernel test.
##
## This is not a port/domain fixture. It starts the real CombatRoomRuntime and
## native room, casts the production ranger skill, and requires the Boss arrow
## to cross the real fixed-tick seam:
##   Main.advance_projectiles -> BossArrowFlight -> RoomSpatialPort
##   .queue_boss_path_query -> CONTINUOUS_QUERIES -> BossHitBuffer ->
##   BossCombatDomain.resolve (BigValue DAMAGE_STATUS) ->
##   RoomCombatPort.settle_boss_deaths -> actor/encounter/loot/victory.

const Items := preload("res://src/content/early_item_registry.gd")
const Resolver := preload("res://src/systems/build_resolver.gd")
const BossDomainScript := preload("res://src/runtime/combat/boss_combat_domain.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var items := Items.new()
	_expect(items.load_all().is_empty(), "kernel boss: item registry failed")
	var resolved: Dictionary = Resolver.new(items).resolve_fixture("calibration_exponential")
	_expect(bool(resolved.get("ok", false)), "kernel boss: resolved build rejected")
	# Freeze a production-scale payload before Main resets the player domain.
	# This is a composition-root input, not a post-start authority mutation.
	resolved["total_events"] = {"layer": 1, "magnitude": 12.0}
	resolved["total_events_float"] = 1.0e12
	if not _failures.is_empty():
		_finish()
		return

	# Loaded at run time so this test can be syntax-checked while a parallel
	# CombatRoomRuntime patch is momentarily intermediate. The assertion still
	# mounts and drives that real production runtime.
	var room_runtime_script := load("res://src/game/combat_room_runtime.gd")
	var runtime = room_runtime_script.new()
	root.add_child(runtime)
	var started: Dictionary = runtime.start_session({
		"mode": "Manual",
		"presentation_enabled": false,
		"seed": 88127,
		"room": {
			"room_id": "test.kernel.production.boss",
			"layout_id": "rectangle_arena",
			"objective_id": "clear",
			"hazard_ids": [],
			"enemy_ids": [],
			"elite_rule_ids": [],
			"boss_id": "threshold_colossus",
			"drop_tags": [],
			"loot_slots": [{
				"slot_id": "boss_death_drop",
				"source": "enemy_death",
				"tag": "equipment_general",
				"pickup_radius": 18.0,
			}],
		},
		"framework_context": {
			"active_build": {"skills": ["piercing_arrow"]},
			"resolved_build": resolved,
		},
	})
	_expect(bool(started.get("ok", false)), "kernel boss: mounted runtime failed: %s" % str(started))
	if not bool(started.get("ok", false)):
		runtime.free()
		_finish()
		return
	runtime.set_process(false)
	var arena = runtime.room_instance
	arena.set_process(false)
	_run_boss_kill(arena)
	_run_stale_identity_fail_closed(arena)
	runtime.free()
	_finish()


func _run_boss_kill(arena) -> void:
	_expect(arena.scene_runtime != null and arena.scene_runtime.is_ready(), "kernel boss: native room was not mounted")
	_expect(arena.simulation_world == arena.scene_runtime.simulation, "kernel boss: Main did not adopt the mounted SimulationWorld")
	_expect(arena._boss_combat_domain != null, "kernel boss: production did not create a BossCombatDomain")
	_expect(arena.room_spatial_port.boss_domain == arena._boss_combat_domain, "kernel boss: spatial port did not bind the production Boss domain")
	_expect(arena.room_combat_port.boss_domain == arena._boss_combat_domain, "kernel boss: combat port did not bind the same Boss domain")
	_expect(arena._kernel_reconciler._boss_domain_room_is_current(), "kernel boss: Boss domain identity does not match the mounted room")
	_expect(arena._kernel_boss_flight.is_configured(), "kernel boss: Boss flight driver was not configured")
	if not _failures.is_empty():
		return
	_expect(arena.boss != null and arena.boss.is_boss, "kernel boss: production Boss failed to spawn")
	if arena.boss == null:
		return
	var boss = arena.boss
	var stable_key := ""
	for key: Variant in arena._enemy_stable_keys.keys():
		if int(arena._enemy_stable_keys[key]) == int(boss.entity_id):
			stable_key = String(key)
	_expect(not stable_key.is_empty(), "kernel boss: Boss actor stable key mapping missing")
	var domain_target = arena._boss_combat_domain.target(stable_key) if not stable_key.is_empty() else null
	_expect(domain_target != null, "kernel boss: Boss actor was not registered as a detached domain target")
	if domain_target != null:
		_expect(domain_target.maximum_health.compare(BigValue.from_power10(12.0)) == 0, "kernel boss: detached Boss lost the production BigValue maximum")
		_expect(domain_target.parts.size() == 3, "kernel boss: detached Boss lost its multipart hurtboxes")
		_expect(domain_target.spawn_key == "wave.production/threshold_colossus.0/0", "kernel boss: detached Boss spawn identity does not match the real encounter")
	if not _failures.is_empty():
		return

	var center := Vector2(500, 340)
	_expect(bool(arena.teleport_actor("ranger", center).get("ok", false)), "kernel boss: ranger placement failed")
	var boss_actor_id := "enemy/%d" % int(boss.entity_id)
	_expect(bool(arena.teleport_actor(boss_actor_id, center + Vector2(110.0, 54.0)).get("ok", false)), "kernel boss: Boss placement failed")
	if not _failures.is_empty():
		return
	_expect(arena.locked_build.get("total_events", {}) == {"layer": 1, "magnitude": 12.0}, "kernel boss: frozen build payload changed: %s" % str(arena.locked_build.get("total_events", {})))
	var cast_model: Dictionary = arena._current_model()
	_expect(cast_model.get("total_events", null) != null and (cast_model["total_events"] as BigValue).compare(BigValue.from_power10(12.0)) == 0, "kernel boss: cast model did not read frozen BigValue events: %s" % str(cast_model.get("total_events", {})))
	# Drive the real EncounterDirector barrier window onto the mounted Boss so
	# the production kernel path proves admission at the current fixed tick.
	var barrier_rules: Array[String] = ["periodic_barrier"]
	arena.encounter_director.elite_rule_ids = barrier_rules
	arena.encounter_director.elite_entity_id = int(boss.entity_id)
	# Pin the current fixed tick inside the active window before submitting the
	# cast. EncounterDirector recomputes this field during the room phase; the
	# explicit assignment keeps this mounted seam test deterministic at tick 0.
	arena.encounter_director.elite_barrier_active = true
	var health_before_barrier: BigValue = domain_target.health.duplicate_value()
	var settlements_before_barrier: int = arena.room_combat_port.last_boss_settlements.size()
	var loot_before_barrier: int = (arena.room_loot_snapshot.get("entities", []) as Array).size()
	var blocked_cast: Dictionary = arena.request_player_cast("piercing_arrow", int(boss.entity_id), Vector2.RIGHT)
	_expect(bool(blocked_cast.get("accepted", false)), "kernel boss: production barrier cast rejected: %s" % str(blocked_cast))
	var blocked_seen := false
	var blocked_steps := 0
	while blocked_steps < 12:
		var blocked_tick: Dictionary = arena.combat_simulation.step()
		_expect(bool(blocked_tick.get("ok", false)), "kernel boss: production barrier tick failed: %s" % str(blocked_tick))
		var blocked_batch: Dictionary = arena.room_combat_port.last_boss_batch
		for suppression: Variant in blocked_batch.get("suppressed", []):
			if suppression is Dictionary and String((suppression as Dictionary).get("reason", "")) == "periodic_barrier":
				blocked_seen = true
		blocked_steps += 1
		if blocked_seen:
			break
	_expect(blocked_seen, "kernel boss: mounted production barrier window did not suppress the Boss hit")
	_expect(domain_target.health.compare(health_before_barrier) == 0 and domain_target.alive, "kernel boss: blocked production hit changed Boss health/alive")
	_expect(arena.room_combat_port.last_boss_settlements.size() == settlements_before_barrier, "kernel boss: blocked production hit changed settlements")
	_expect((arena.room_loot_snapshot.get("entities", []) as Array).size() == loot_before_barrier, "kernel boss: blocked production hit changed loot")
	while arena.sim_tick < arena.encounter_director.ELITE_BARRIER_ACTIVE_TICKS:
		var cooldown_tick: Dictionary = arena.combat_simulation.step()
		_expect(bool(cooldown_tick.get("ok", false)), "kernel boss: production barrier cooldown tick failed: %s" % str(cooldown_tick))
	_expect(not arena.encounter_director.elite_barrier_active, "kernel boss: production fixed tick did not leave the barrier window")
	# The exponential calibration fixture is the real production-scale BigValue
	# payload source; the room/player rules freeze it before this cast.
	var cast: Dictionary = arena.request_player_cast("piercing_arrow", int(boss.entity_id), Vector2.RIGHT)
	_expect(bool(cast.get("accepted", false)), "kernel boss: production cast rejected: %s" % str(cast))

	var submitted := 0
	var queue_rejected := false
	var result_seen := false
	var outcome_seen := false
	var last_outcome := {}
	var cast_aggregate := "none"
	var damage_event_seen := false
	var settlement_seen := false
	var encounter_spawn_seen := false
	var encounter_death_seen := false
	var ticks := 0
	while ticks < 150 and not bool(arena.battle_over):
		var stepped: Dictionary = arena.combat_simulation.step()
		_expect(bool(stepped.get("ok", false)), "kernel boss: production tick failed: %s" % str(stepped))
		if not bool(stepped.get("ok", false)):
			break
		ticks = int(arena.sim_tick)
		if cast_aggregate == "none" and not arena.projectiles.is_empty():
			cast_aggregate = (arena.projectiles[0] as CombatArrowProjectile).aggregate_damage.to_short_string(12)
		submitted = maxi(submitted, int(arena._kernel_boss_flight.submitted_queries))
		queue_rejected = queue_rejected or not arena._kernel_boss_flight.last_queue_rejections.is_empty()
		if not arena.room_spatial_port.take_boss_path_results().is_empty():
			result_seen = true
		var batch: Dictionary = arena.room_combat_port.last_boss_batch
		if not (batch.get("outcomes", []) as Array).is_empty():
			outcome_seen = true
			last_outcome = (batch.get("outcomes", []) as Array)[0]
		for settlement: Dictionary in arena.room_combat_port.last_boss_settlements:
			if String(settlement.get("entity_key", "")) == stable_key:
				settlement_seen = true
		for notification: Dictionary in arena.room_encounter_port.spawned_notifications:
			if String(notification.get("entity_key", "")) == stable_key:
				encounter_spawn_seen = true
		for notification: Dictionary in arena.room_encounter_port.received_death_notifications:
			if String(notification.get("entity_key", "")) == stable_key:
				encounter_death_seen = true
	for event: Dictionary in arena.combat_event_stream.snapshot().events:
		if String(event.get("type", "")) == "damage_applied" and int(event.get("target_entity_id", 0)) == int(boss.entity_id):
			damage_event_seen = not String(event.get("boss_remaining_after", "")).is_empty()

	_expect(submitted >= 1, "kernel boss: mounted production never submitted queue_boss_path_query")
	_expect(not queue_rejected, "kernel boss: a production Boss path query was rejected")
	_expect(result_seen, "kernel boss: production never received a BossPathResult")
	_expect(outcome_seen, "kernel boss: BossHitBuffer outcome never reached DAMAGE_STATUS telemetry")
	_expect(damage_event_seen, "kernel boss: BigValue damage event lost Boss remaining health")
	_expect(settlement_seen, "kernel boss: Boss death did not produce a settlement receipt")
	_expect(encounter_spawn_seen, "kernel boss: real RoomEncounter never adopted the Boss actor")
	_expect(encounter_death_seen, "kernel boss: Boss settlement never reached RoomEncounterPort")
	_expect(arena.room_combat_port.last_boss_death_notifications.size() == 1, "kernel boss: Boss settlement did not expose a typed death notification")
	_expect(arena.room_encounter_port.failed_spawn_notifications.is_empty(), "kernel boss: Boss encounter deployment failed")
	_expect(int(arena.defeated) == 1 and int(arena.arrow_hits) == 1, "kernel boss: player telemetry did not record exactly one Boss hit/death: projectile=%s outcome=%s" % [cast_aggregate, str(last_outcome)])
	_expect(arena.boss_damage.compare(arena.boss_maximum) >= 0, "kernel boss: Boss damage mirror did not reach the BigValue maximum")
	_expect(not domain_target.alive and domain_target.health.is_zero(), "kernel boss: detached Boss health was not canonically zero")
	_expect(not arena.actor_registry.has_actor(boss_actor_id), "kernel boss: dead Boss actor stayed registered")
	_expect(bool(arena.battle_over) and bool(arena.battle_victory), "kernel boss: room did not reach terminal victory")
	_expect(not (arena.room_loot_snapshot.get("entities", []) as Array).is_empty(), "kernel boss: Boss settlement produced no room loot")
	for drop: Dictionary in arena.room_loot_snapshot.get("entities", []):
		var drop_position: Vector2 = drop["position"]
		_expect(arena.actor_registry.is_position_clear(drop_position, float(drop["pickup_radius"])), "kernel boss: drop lacks pickup clearance")
		_expect(drop_position.distance_to(boss.position) <= 64.0, "kernel boss: drop moved too far from the Boss")
	var encounter_snapshot: Dictionary = arena.scene_runtime.encounter_domain.snapshot()
	var records: Array = encounter_snapshot.get("spawn_records", [])
	_expect(records.size() == 1, "kernel boss: real RoomEncounter lost the Boss spawn record")
	if records.size() == 1:
		_expect(String(records[0].get("state", "")) == "dead" and String(records[0].get("entity_key", "")) == stable_key, "kernel boss: real RoomEncounter did not record the settlement identity")
	# RoomEncounter evaluates wave clear on the step after the death receipt. The
	# legacy terminal projection may stop Main's loop first, so advance once more.
	if String(encounter_snapshot.get("phase", "")) != "victory":
		var terminal_tick: Dictionary = arena.combat_simulation.step()
		_expect(bool(terminal_tick.get("ok", false)), "kernel boss: post-terminal encounter tick failed: %s" % str(terminal_tick))
		encounter_snapshot = arena.scene_runtime.encounter_domain.snapshot()
	_expect(String(encounter_snapshot.get("phase", "")) == "victory", "kernel boss: real RoomEncounter did not reach terminal victory")
	_expect(arena.room_combat_port.last_boss_settlements.size() == 1, "kernel boss: Boss settlement receipt duplicated")


func _run_stale_identity_fail_closed(arena) -> void:
	var stale := BossDomainScript.new()
	_expect(bool(stale.configure("stale.kernel.boss.room", int(arena.simulation_world.world_revision)).get("ok", false)), "kernel boss: stale domain fixture failed")
	_expect(bool(arena.room_spatial_port.bind_boss_domain(stale).get("ok", false)), "kernel boss: stale fixture could not exercise the typed port")
	_expect(bool(arena.room_combat_port.bind_boss_domain(stale).get("ok", false)), "kernel boss: stale fixture could not exercise the combat port")
	_expect(not arena._kernel_reconciler._boss_domain_room_is_current(), "kernel boss: a stale room identity was accepted as current")


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures.append(message)
	printerr("KERNEL_BOSS_FAILURE %s" % message)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS test_kernel_production_boss.gd")
		quit(0)
		return
	for failure: String in _failures:
		printerr("- %s" % failure)
	print("FAIL test_kernel_production_boss.gd")
	quit(1)
