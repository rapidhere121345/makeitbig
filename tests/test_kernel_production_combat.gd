extends SceneTree

## Fail-closed production seam test for the kernel combat vertical slice.
##
## It mounts the real native room (SceneRuntime + Main + CombatSimulation),
## fires one production ranger piercing arrow, and requires the evidence chain
## to exist end to end:
##   Main.advance_projectiles -> RangerArrowFlight -> RoomSpatialPort
##   .queue_path_query -> kernel CONTINUOUS_QUERIES -> HitBuffer ->
##   RoomCombatPort.resolve (DamageResolution) -> actor health commit ->
##   kernel death settlement -> RoomEncounterPort notification -> room loot.
## Static fixtures passing without this mounted chain is a failure, not a
## substitute.

const Items := preload("res://src/content/early_item_registry.gd")
const Resolver := preload("res://src/systems/build_resolver.gd")
const CombatArrowProjectileScript := preload("res://src/runtime/world/combat_arrow_projectile.gd")
const BigValueScript := preload("res://src/core/big_value.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var items := Items.new()
	_expect(items.load_all().is_empty(), "kernel combat: item registry failed")
	if not _failures.is_empty():
		_finish()
		return
	var resolved: Dictionary = Resolver.new(items).resolve_fixture("calibration_convergent")
	_expect(bool(resolved.get("ok", false)), "kernel combat: resolved build rejected")
	if not _failures.is_empty():
		_finish()
		return
	# Keep test compilation independent from in-flight parallel edits to the
	# runtime wrapper; execution still loads and mounts the real production type.
	var room_runtime_script := load("res://src/game/combat_room_runtime.gd")
	var runtime = room_runtime_script.new()
	root.add_child(runtime)
	var started: Dictionary = runtime.start_session({
		"mode": "Manual",
		"presentation_enabled": false,
		"seed": 77231,
		"room": {
			"room_id": "test.kernel.production.combat",
			"layout_id": "rectangle_arena",
			"objective_id": "clear",
			"hazard_ids": [],
			"enemy_ids": ["melee_pursuer"],
			"elite_rule_ids": [],
			"boss_id": "",
			"drop_tags": [],
			"loot_slots": [{
				"slot_id": "enemy_death_drop",
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
	_expect(bool(started.get("ok", false)), "kernel combat: mounted runtime failed: %s" % String(started.get("error", "")))
	if not bool(started.get("ok", false)):
		runtime.free()
		_finish()
		return
	runtime.set_process(false)
	var arena = runtime.room_instance
	arena.set_process(false)
	_run_boss_kernel_predicate(arena)
	_run_kernel_kill_scenario(arena)
	runtime.free()
	_finish()


func _run_kernel_kill_scenario(arena) -> void:
	# Fail-closed production wiring: the mounted room must expose the typed
	# ports and drive itself; a fixture-only pass cannot satisfy these.
	_expect(arena.scene_runtime != null and arena.scene_runtime.is_ready(), "kernel combat: native room was not mounted")
	_expect(arena.simulation_world == arena.scene_runtime.simulation, "kernel combat: Main did not adopt the mounted SimulationWorld")
	_expect(arena.room_spatial_port != null and arena.room_combat_port != null and arena.room_encounter_port != null, "kernel combat: mounted room did not bind the typed kernel ports")
	var phase_port = arena.combat_simulation.phase_owner
	_expect(phase_port != null and phase_port is CombatPhasePort, "kernel combat: production phase owner is not typed")
	_expect(phase_port != arena, "kernel combat: production phases still receive Main directly")
	_expect(arena.room_phase_owner == phase_port, "kernel combat: Main did not retain its bound phase adapter")
	_expect(phase_port.is_ready(), "kernel combat: bound phase adapter is not ready")
	var encounter_domain = arena.scene_runtime.encounter_domain
	_expect(arena.room_encounter_port != null and bool(arena.room_encounter_port.snapshot().get("bound", false)), "kernel combat: mounted production did not bind the RoomEncounterPort")
	_expect(encounter_domain != null and encounter_domain.has_method("notify_death"), "kernel combat: mounted production did not bind a real RoomEncounter domain")
	if encounter_domain != null:
		_expect(String(encounter_domain.room_id) == "test.kernel.production.combat", "kernel combat: bound RoomEncounter lost the authored room identity")
	if not _failures.is_empty():
		return
	var enemies: Array = arena.enemies
	_expect(enemies.size() == 1, "kernel combat: room did not spawn exactly one enemy")
	if enemies.is_empty():
		return
	var enemy = enemies[0]
	var actor_id := "enemy/%d" % int(enemy.entity_id)
	var stable_key := ""
	for key: Variant in arena._enemy_stable_keys.keys():
		if int(arena._enemy_stable_keys[key]) == int(enemy.entity_id):
			stable_key = String(key)
	_expect(not stable_key.is_empty(), "kernel combat: enemy stable key mapping missing at registration")

	# Preserve the attack distance on the clear lane above the whole wall.
	var center: Vector2 = arena._arena_rect().get_center() + Vector2(0, -36)
	_expect(bool(arena.teleport_actor("ranger", center).get("ok", false)), "kernel combat: ranger placement failed")
	_expect(bool(arena.teleport_actor(actor_id, center + Vector2.RIGHT * 110.0).get("ok", false)), "kernel combat: enemy placement failed")
	enemy.health = 1.0
	enemy.maximum_health = 1.0

	var cast: Dictionary = arena.request_player_cast("piercing_arrow", int(enemy.entity_id), Vector2.RIGHT)
	_expect(bool(cast.get("accepted", false)), "kernel combat: production cast was rejected: %s" % str(cast))

	var max_submitted := 0
	var any_rejection := false
	var consumed_hits := 0
	var hit_attack_id := ""
	var settlement_seen := false
	var encounter_notification_seen := false
	var ticks := 0
	while ticks < 120 and not bool(arena.battle_over):
		var stepped: Dictionary = arena.combat_simulation.step()
		_expect(bool(stepped.get("ok", false)), "kernel combat: production tick failed: %s" % str(stepped))
		if not bool(stepped.get("ok", false)):
			break
		ticks = int(arena.sim_tick)
		max_submitted = maxi(max_submitted, int(arena._kernel_arrow_flight.submitted_queries))
		any_rejection = any_rejection or not arena._kernel_arrow_flight.last_queue_rejections.is_empty()
		consumed_hits = maxi(consumed_hits, int(arena.room_combat_port.consumed_hits))
		for hit: Dictionary in arena.room_combat_port.last_hits:
			if String(hit.get("target_key", "")) == stable_key:
				hit_attack_id = String(hit.get("attack_instance_id", ""))
		for settlement: Dictionary in arena.room_combat_port.last_settlements:
			if String(settlement.get("entity_key", "")) == stable_key:
				settlement_seen = true
		for notification: Dictionary in arena.room_encounter_port.received_death_notifications:
			if String(notification.get("entity_key", "")) == stable_key:
				encounter_notification_seen = true

	# The production evidence chain, in order.
	_expect(max_submitted >= 1, "kernel combat: mounted production code never called queue_path_query via RangerArrowFlight")
	_expect(not any_rejection, "kernel combat: a production path query was rejected at queue time")
	_expect(consumed_hits >= 1, "kernel combat: RoomCombatPort never consumed a HitBuffer record for the arrow")
	_expect(hit_attack_id.begins_with("arrow/"), "kernel combat: resolved hit record lost the typed attack identity")
	_expect(settlement_seen, "kernel combat: enemy death did not produce a kernel DeathSettlement receipt")
	_expect(encounter_notification_seen, "kernel combat: kernel death never reached RoomEncounterPort")
	_expect(arena.room_encounter_port.received_typed_death_notifications.size() == 1, "kernel combat: production death settlement did not cross RoomEncounterPort as a typed record")
	# Production deployment seam: RoomEncounter emitted the request, the typed
	# materializer created the actor through Main and the kernel death settlement
	# closed its spawn record.
	_expect(arena.room_encounter_port.failed_spawn_notifications.is_empty(), "kernel combat: encounter materialization failed")
	_expect(arena.room_encounter_port.spawned_notifications.size() == 1, "kernel combat: encounter did not acknowledge exactly one materialized actor")
	_expect(arena.room_encounter_port.pending_spawn_requests.is_empty(), "kernel combat: encounter spawn request never materialized after the kernel tick")
	# The dead actor is deregistered by the kernel, so after the kill the registry
	# must hold exactly the ranger and no duplicate encounter actor.
	var live_actor_ids: Array[String] = arena.actor_registry.actor_ids()
	var duplicate_kernel_actor := false
	for live_actor_id in live_actor_ids:
		if String(live_actor_id).begins_with("encounter/"):
			duplicate_kernel_actor = true
	_expect(not duplicate_kernel_actor, "kernel combat: encounter reconciliation spawned a duplicate kernel actor")
	_expect(live_actor_ids.size() == 1 and live_actor_ids[0] == "ranger", "kernel combat: post-kill actor registry is not exactly the ranger")
	for ack: Dictionary in arena.room_encounter_port.spawned_notifications:
		_expect(String(ack.get("entity_key", "")) == stable_key, "kernel combat: materialized entity key does not match the kernel settlement identity")
		_expect(String(ack.get("room_instance_id", "")) == arena.scene_runtime.room_instance_id and int(ack.get("world_revision", -1)) == int(arena.scene_runtime.world_revision), "kernel combat: materialized acknowledgement lost the room identity")
	_expect(int(arena.defeated) == 1, "kernel combat: defeat ledger did not record the kernel kill")
	_expect(not arena.actor_registry.has_actor(actor_id), "kernel combat: dead enemy actor stayed registered")
	_expect(encounter_domain != null and encounter_domain.has_method("snapshot"), "kernel combat: production encounter domain disappeared before settlement review")
	if encounter_domain != null and encounter_domain.has_method("snapshot"):
		var encounter_snapshot: Dictionary = encounter_domain.snapshot()
		var spawn_records: Array = encounter_snapshot.get("spawn_records", [])
		_expect(spawn_records.size() == 1, "kernel combat: real RoomEncounter lost the materialized spawn record")
		if spawn_records.size() == 1:
			var record: Dictionary = spawn_records[0]
			_expect(String(record.get("state", "")) == "dead" and String(record.get("entity_key", "")) == stable_key, "kernel combat: real RoomEncounter did not record the kernel death under the settlement identity")
		# Main's battle_over stops this loop before the next RoomEncounter.step,
		# so the wave-clear transition lands on a later tick in a continuing
		# session; same-tick evidence is the dead record plus the port receipt.
		_expect(String(encounter_snapshot.get("phase", "")) != "defeat", "kernel combat: real RoomEncounter reached a wrong terminal phase")
	var loot_entities: Array = arena.room_loot_snapshot.get("entities", [])
	_expect(not loot_entities.is_empty(), "kernel combat: death settlement loot request produced no room loot")
	_expect(bool(arena.battle_over) and bool(arena.battle_victory), "kernel combat: room did not reach a natural victory through the kernel kill")


func _run_boss_kernel_predicate(arena) -> void:
	# The production selector must include a Boss target whenever the same real
	# BossCombatDomain is bound to both mounted ports. There is no legacy flight
	# selector left in Main's production phase.
	var enemies: Array = arena.enemies
	if enemies.is_empty():
		_expect(false, "kernel combat: boss predicate probe lost all enemies")
		return
	var enemy = enemies[0]
	enemy.is_boss = true
	var projectile := CombatArrowProjectileScript.new(
		9901, int(enemy.entity_id), int(arena.sim_tick),
		Vector2.ZERO, Vector2.RIGHT, 100.0, 200.0,
		BigValueScript.from_float(10.0), 10.0,
		BigValueScript.from_float(1.0), 10.0
	)
	_expect(arena._kernel_reconciler._is_kernel_projectile(projectile), "kernel combat: boss target was excluded from the mounted kernel path")
	_expect(arena._kernel_reconciler._is_boss_kernel_projectile(projectile), "kernel combat: Boss selector rejected the boss projectile")
	_expect(not arena.has_method("_is_legacy_projectile"), "kernel combat: Main retained a legacy Boss production selector")
	enemy.is_boss = false


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures.append(message)
	printerr("KERNEL_COMBAT_FAILURE %s" % message)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS test_kernel_production_combat.gd")
		quit(0)
		return
	for failure: String in _failures:
		printerr("- %s" % failure)
	print("FAIL test_kernel_production_combat.gd")
	quit(1)
