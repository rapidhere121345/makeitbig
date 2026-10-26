extends SceneTree

## Production RoomEncounter seam coverage.  Every scenario mounts the real
## SceneRuntime with the native concave room scene; no fixture-only registry or
## fake port is used for spawn, generation, revision, death, or teardown.

const EncounterScript := preload("res://src/runtime/encounter/room_encounter.gd")
const SpawnRequestScript := preload("res://src/runtime/encounter/encounter_spawn_request.gd")
const SpawnResultScript := preload("res://src/runtime/encounter/encounter_spawn_result.gd")
const DeathSettlementNotificationScript := preload("res://src/runtime/combat/death_settlement_notification.gd")
const SpawnPortScript := preload("res://src/runtime/world/room_encounter_spawn_port.gd")
const RuntimeScript := preload("res://src/runtime/world/scene_runtime.gd")
const CombatRoomRuntimeScript := preload("res://src/game/combat_room_runtime.gd")
const EarlyItemRegistryScript := preload("res://src/content/early_item_registry.gd")
const BuildResolverScript := preload("res://src/systems/build_resolver.gd")
const SpatialScript := preload("res://src/runtime/world/spatial_manifest.gd")
const NativeScene := preload("res://content/rooms/samples/concave_hole_passage.tscn")
const Assert := preload("res://tests/helpers/assert.gd")

const MANIFEST_PATH := "res://content/rooms/samples/concave_hole_passage.spatial.json"
const AUTHORED_ENCOUNTER_PATH := "res://content/rooms/combat/encounter_waves.json"
const CAMPAIGN_PATH := "res://content/early_campaign.json"

var failures: Array[String] = []


class RejectSpawnPort extends SpawnPortScript:
	var owner_test: SceneTree = null

	func spawn(request: EncounterSpawnRequest, _context: Dictionary) -> Variant:
		if owner_test != null:
			owner_test._expect(request is SpawnRequestScript, "binding: production request lost its typed class")
		return SpawnResultScript.failed(request, "content_rejected")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_real_mount_spawn_order_ack_death_and_generation()
	_test_spawn_failure_and_terminal_defeat()
	_test_authored_content_schema_and_roster_binding()
	_test_authored_roster_mismatch_fails_closed()
	_test_production_authored_multi_wave_session()
	_test_mixed_boss_encounter_authority()
	_test_stale_tick_revision_and_unmount_shutdown()
	if failures.is_empty():
		print("PASS test_room_encounter_production.gd")
	else:
		for failure: String in failures:
			printerr("- " + failure)
		print("FAIL test_room_encounter_production.gd")
	quit(0 if failures.is_empty() else 1)


func _test_real_mount_spawn_order_ack_death_and_generation() -> void:
	var encounter: Variant = EncounterScript.new()
	var configured: Dictionary = encounter.configure("native.encounter.production", [
		{
			"wave_id": "wave.01",
			"spawns": [
				{"spawn_id": "zeta", "archetype_id": "zeta", "socket_id": "socket/Spawn", "count": 1},
				{"spawn_id": "alpha", "archetype_id": "alpha", "socket_id": "socket/Spawn", "count": 2},
			],
			"next_wave_delay_ticks": 1,
		},
		{
			"wave_id": "wave.02",
			"spawns": [{"spawn_id": "omega", "archetype_id": "omega", "socket_id": "socket/Spawn", "count": 1}],
		},
	])
	_expect(bool(configured.get("ok", false)), "production: encounter configuration failed")
	var runtime := _mount_runtime(7, encounter, null, true)
	_expect(encounter.snapshot().phase == EncounterScript.PHASE_SPAWNING, "production: typed mount did not start the encounter")

	var first_tick = runtime.step_tick()
	_expect(first_tick.ok, "production: first fixed tick failed")
	_expect(first_tick.value.entity_count() == 0, "production: spawn mutated the same tick snapshot")
	_expect(runtime.encounter_spawn_results.size() == 3, "production: first wave did not produce three spawn receipts")
	_expect(runtime.actor_registry.actor_ids().size() == 3, "production: real actor access did not materialize all spawns")
	var requests: Array = runtime.encounter_port.last_step.get("spawn_requests", [])
	_expect(requests.size() == 3, "production: port lost typed spawn requests")
	if requests.size() == 3:
		_expect(requests[0].spawn_key == "wave.01/alpha/0" and requests[1].spawn_key == "wave.01/alpha/1" and requests[2].spawn_key == "wave.01/zeta/0", "production: spawn request order was not deterministic")
	var request_objects: Array = runtime.encounter_port.spawned_notifications
	_expect(request_objects.size() == 3, "production: spawned acknowledgements missing")
	for receipt: Dictionary in request_objects:
		_expect(int(receipt.get("stable_key", 0)) > 0 and int(receipt.get("generation", 0)) == 1, "production: spawned receipt lost stable key/generation")
		_expect(String(receipt.get("room_instance_id", "")) == runtime.room_instance_id and int(receipt.get("world_revision", -1)) == 7, "production: spawned receipt lost room revision")
	_expect(runtime.encounter_port.snapshot().terminal.phase == EncounterScript.PHASE_ACTIVE, "production: active terminal projection was wrong")

	for actor_id: String in runtime.actor_registry.actor_ids():
		var actor = runtime.actor_registry.actor(actor_id)
		actor.health = 0.0
		actor.hit_points = 0
		actor.alive = false
	var death_tick = runtime.step_tick()
	_expect(death_tick.ok, "production: death settlement tick failed")
	_expect(runtime.encounter_port.received_death_notifications.size() == 3, "production: death notifications were not returned through the port")
	var dead_notification: Dictionary = runtime.encounter_port.received_death_notifications[0]
	_expect(int(dead_notification.get("stable_key", 0)) > 0 and int(dead_notification.get("generation", 0)) == 1, "production: death receipt lost stable identity")
	var duplicate_death_count: int = runtime.encounter_port.received_death_notifications.size()
	runtime.encounter_port.on_death_settlement(_typed_death_notification(
		String(dead_notification.entity_key),
		runtime.simulation.tick,
		runtime.room_instance_id,
		runtime.world_revision,
		String(dead_notification.spawn_key)
	), _context(runtime))
	_expect(runtime.encounter_port.received_death_notifications.size() == duplicate_death_count, "production: duplicate death receipt was not idempotent")

	_expect(runtime.step_tick().ok, "production: wave clear tick failed")
	_expect(encounter.snapshot().phase == EncounterScript.PHASE_WAITING, "production: cleared wave did not wait for its delay")
	_expect(runtime.step_tick().ok, "production: wave transition tick failed")
	_expect(runtime.encounter_spawn_results.size() == 1, "production: second wave spawn acknowledgement missing")
	if runtime.encounter_port.spawned_notifications.size() == 4:
		var second_spawn: Dictionary = runtime.encounter_port.spawned_notifications[3]
		_expect(int(second_spawn.stable_key) == 4 and int(second_spawn.generation) == 2, "production: stable key/generation contract changed across deferred reuse")

	var second_actor_ids: Array[String] = runtime.actor_registry.actor_ids()
	_expect(second_actor_ids.size() == 1, "production: second wave actor was not the only live actor")
	if second_actor_ids.size() == 1:
		var second_actor = runtime.actor_registry.actor(second_actor_ids[0])
		second_actor.alive = false
		second_actor.health = 0.0
		second_actor.hit_points = 0
	_expect(runtime.step_tick().ok, "production: final death tick failed")
	_expect(runtime.step_tick().ok, "production: victory tick failed")
	_expect(encounter.snapshot().phase == EncounterScript.PHASE_VICTORY, "production: all waves did not reach victory")
	_expect(runtime.encounter_port.snapshot().terminal.victory, "production: victory terminal contract missing")
	runtime.shutdown()
	runtime.free()


func _test_spawn_failure_and_terminal_defeat() -> void:
	var runtime := _mount_runtime(9)
	var failed_encounter: Variant = EncounterScript.new()
	failed_encounter.configure("native.encounter.failure", [{
		"wave_id": "wave.failure",
		"spawns": [{"spawn_id": "blocked", "archetype_id": "blocked", "socket_id": "socket/Spawn", "count": 1}],
	}])
	var reject_port := RejectSpawnPort.new()
	reject_port.owner_test = self
	var bind_result: Dictionary = runtime.bind_encounter(failed_encounter, reject_port)
	_expect(bool(bind_result.get("ok", false)), "failure: custom production binding rejected")
	_expect(bool(runtime.start_encounter().get("ok", false)), "failure: encounter start failed")
	_expect(runtime.step_tick().ok, "failure: spawn failure tick failed")
	_expect(runtime.encounter_port.failed_spawn_notifications.size() == 1, "failure: spawn failure receipt missing")
	_expect(failed_encounter.snapshot().spawn_records[0].state == "failed", "failure: domain did not receive spawn failure")
	_expect(runtime.step_tick().ok, "failure: failed wave terminal tick failed")
	_expect(failed_encounter.snapshot().phase == EncounterScript.PHASE_VICTORY, "failure: failed spawn did not clear the wave")
	runtime.shutdown()
	runtime.free()

	var defeat_runtime := _mount_runtime(10)
	var defeat_encounter: Variant = EncounterScript.new()
	defeat_encounter.configure("native.encounter.defeat", [{
		"wave_id": "wave.defeat",
		"spawns": [{"spawn_id": "never", "archetype_id": "never", "socket_id": "socket/Spawn", "count": 1}],
	}])
	_expect(bool(defeat_runtime.bind_encounter(defeat_encounter).get("ok", false)), "defeat: encounter bind failed")
	_expect(bool(defeat_runtime.start_encounter().get("ok", false)), "defeat: encounter start failed")
	_expect(bool(defeat_runtime.request_encounter_defeat("player_dead").get("ok", false)), "defeat: defeat request failed")
	_expect(defeat_runtime.step_tick().ok, "defeat: terminal fixed tick failed")
	_expect(defeat_encounter.snapshot().phase == EncounterScript.PHASE_DEFEAT and defeat_runtime.encounter_port.snapshot().terminal.defeat, "defeat: terminal state contract missing")
	_expect(defeat_runtime.encounter_port.pending_spawn_requests.is_empty(), "defeat: terminal state emitted a spawn request")
	for _post_terminal in 3:
		_expect(defeat_runtime.step_tick().ok, "defeat: post-terminal fixed tick failed")
		_expect(defeat_runtime.encounter_port.pending_spawn_requests.is_empty(), "defeat: terminal defeat emitted a later spawn request")
	_expect(defeat_runtime.encounter_port.spawned_notifications.is_empty(), "defeat: terminal defeat produced a spawn acknowledgement")
	defeat_runtime.shutdown()
	defeat_runtime.free()


func _test_authored_content_schema_and_roster_binding() -> void:
	var authored: Variant = JSON.parse_string(FileAccess.get_file_as_string(AUTHORED_ENCOUNTER_PATH))
	_expect(authored is Dictionary, "authored: content file did not parse")
	if not authored is Dictionary:
		return
	var rooms: Dictionary = authored.get("rooms", {})
	_expect(rooms.has("priority_charge") and rooms.has("auto_certification_clear"), "authored: verifiable corridor rooms missing from content")
	var campaign_rooms := _campaign_rooms_by_id()
	_expect(campaign_rooms.has("priority_charge") and campaign_rooms.has("auto_certification_clear"), "authored: campaign rooms disappeared from the campaign content")
	for room_id: String in ["priority_charge", "auto_certification_clear"]:
		var entry: Dictionary = rooms.get(room_id, {})
		var waves: Array = entry.get("waves", [])
		_expect(waves.size() >= 2, "authored: %s did not author multi-wave content" % room_id)
		var totals: Dictionary = {}
		var wave_ids: Dictionary = {}
		for raw_wave: Variant in waves:
			_expect(raw_wave is Dictionary, "authored: %s wave is not an object" % room_id)
			if not raw_wave is Dictionary:
				continue
			var wave: Dictionary = raw_wave
			var wave_id := String(wave.get("wave_id", ""))
			_expect(not wave_id.is_empty() and not wave_ids.has(wave_id), "authored: %s wave ids are not unique and ordered" % room_id)
			wave_ids[wave_id] = true
			for raw_spawn: Variant in wave.get("spawns", []):
				if not raw_spawn is Dictionary:
					continue
				var spec: Dictionary = raw_spawn
				var archetype := String(spec.get("archetype_id", ""))
				totals[archetype] = int(totals.get(archetype, 0)) + int(float(spec.get("count", 0)))
		var roster: Array = (campaign_rooms.get(room_id, {}) as Dictionary).get("enemy_ids", [])
		var expected: Dictionary = {}
		for roster_value: Variant in roster:
			var roster_id := String(roster_value)
			expected[roster_id] = int(expected.get(roster_id, 0)) + 1
		_expect(totals == expected, "authored: %s waves do not bind the validated roster %s vs %s" % [room_id, totals, expected])


func _test_authored_roster_mismatch_fails_closed() -> void:
	var resolved: Dictionary = _resolved_fixture("calibration_convergent")
	_expect(bool(resolved.get("ok", false)), "mismatch: resolved combat build was rejected")
	if not bool(resolved.get("ok", false)):
		return
	var runtime = CombatRoomRuntimeScript.new()
	root.add_child(runtime)
	var started: Dictionary = runtime.start_session({
		"mode": "Manual",
		"presentation_enabled": false,
		"seed": 13,
		"room": {
			"room_id": "priority_charge",
			"layout_id": "corridor",
			"objective_id": "clear",
			"hazard_ids": [],
			"enemy_ids": ["melee_pursuer", "melee_pursuer"],
			"elite_rule_ids": [],
			"boss_id": "",
			"drop_tags": [],
		},
		"framework_context": {
			"active_build": {"skills": ["piercing_arrow"]},
			"resolved_build": resolved,
		},
	})
	_expect(not bool(started.get("ok", false)), "mismatch: roster mismatch started an authored session")
	_expect(String(started.get("reason", "")).contains("authored_encounter_roster_mismatch"), "mismatch: fail-closed reason lost the authored roster error: %s" % str(started))
	runtime.queue_free()


func _test_production_authored_multi_wave_session() -> void:
	var resolved: Dictionary = _resolved_fixture("calibration_convergent")
	_expect(bool(resolved.get("ok", false)), "production: resolved combat build was rejected")
	if not bool(resolved.get("ok", false)):
		return
	var runtime = CombatRoomRuntimeScript.new()
	root.add_child(runtime)
	var started: Dictionary = runtime.start_session({
		"mode": "Manual",
		"presentation_enabled": false,
		"seed": 17,
		"room": {
			"room_id": "priority_charge",
			"layout_id": "corridor",
			"objective_id": "clear",
			"hazard_ids": [],
			"enemy_ids": ["melee_pursuer", "charging_raider"],
			"elite_rule_ids": [],
			"boss_id": "",
			"drop_tags": [],
		},
		"framework_context": {
			"active_build": {"skills": ["piercing_arrow"]},
			"resolved_build": resolved,
		},
	})
	_expect(bool(started.get("ok", false)), "production: authored session failed to start: %s" % str(started))
	if not bool(started.get("ok", false)):
		runtime.queue_free()
		return
	runtime.set_process(false)
	var arena: Node = runtime.room_instance
	arena.set_process(false)
	var scene_runtime: Node = runtime.scene_runtime
	var port: Variant = scene_runtime.get("encounter_port")
	var encounter: Variant = scene_runtime.get("encounter_domain")
	var registry: Variant = scene_runtime.get("actor_registry")
	_expect(port != null and encounter != null and registry != null, "production: authored session did not bind the typed encounter domain")
	if port == null or encounter == null or registry == null:
		runtime.free()
		return
	var melee_id := ""
	var charger_id := ""
	for actor_id: String in registry.actor_ids():
		var archetype := String(registry.actor_snapshot(actor_id).get("archetype_id", ""))
		if archetype == "melee_pursuer":
			melee_id = actor_id
		elif archetype == "charging_raider":
			charger_id = actor_id
	_expect(melee_id.is_empty() and not charger_id.is_empty(), "production: authored deploy pre-registered a later-wave actor")
	if charger_id.is_empty():
		runtime.free()
		return
	var charger = _arena_enemy(arena, "charging_raider")
	_expect(charger != null, "production: authored arena lost its charging_raider record")
	_expect(_arena_enemy(arena, "melee_pursuer") == null, "production: later-wave enemy was created before its request")
	if charger == null:
		runtime.free()
		return

	var first_wave_ready := _advance_until(arena, func() -> bool:
		return port.spawned_notifications.size() == 1
	, 30)
	_expect(first_wave_ready, "production: wave.01 did not adopt its legacy actor")
	if first_wave_ready:
		var first_receipt: Dictionary = port.spawned_notifications[0]
		_expect(String(first_receipt.get("spawn_key", "")) == "wave.01.charge/charger/0", "production: wave.01 did not use the authored spawn key")
		_expect(String(first_receipt.get("entity_key", "")) == registry.entity_key_for_handle(registry.actor_handle(charger_id)), "production: wave.01 adopted the wrong roster actor")

	var cast_accepted := _cast_real_arrow(arena, charger)
	_expect(cast_accepted, "production: real arrow against the wave.01 charger was rejected")
	var charger_dead := _advance_until(arena, func() -> bool:
		return arena._enemy_by_entity_id(charger.entity_id) == null
	, 120)
	_expect(charger_dead, "production: wave.01 charger did not die through the production projectile path")
	_expect(port.spawned_notifications.size() == 1, "production: wave.02 spawned before wave.01 cleared")
	if not charger_dead or port.received_death_notifications.is_empty():
		runtime.free()
		return
	var death_receipt: Dictionary = port.received_death_notifications[0]
	var duplicate_count: int = port.received_death_notifications.size()
	port.on_death_settlement(_typed_death_notification(
		String(death_receipt.get("entity_key", "")),
		int(death_receipt.get("tick", -1)),
		scene_runtime.room_instance_id,
		scene_runtime.world_revision,
		String(death_receipt.get("spawn_key", ""))
	), _context(scene_runtime))
	_expect(port.received_death_notifications.size() == duplicate_count, "production: duplicate death settlement was not idempotent")

	var second_wave_ready := _advance_until(arena, func() -> bool:
		return port.spawned_notifications.size() == 2
	, 120)
	_expect(second_wave_ready, "production: wave.02 did not adopt its legacy actor after wave.01 cleared")
	if second_wave_ready:
		var second_receipt: Dictionary = port.spawned_notifications[1]
		_expect(String(second_receipt.get("spawn_key", "")) == "wave.02.pursuit/pursuer/0", "production: wave.02 did not use the authored spawn key")
		_expect(int(second_receipt.get("tick", -1)) > int(death_receipt.get("tick", -1)), "production: wave.02 spawned in the same tick as the wave.01 death")
		melee_id = ""
		for actor_id: String in registry.actor_ids():
			if String(registry.actor_snapshot(actor_id).get("archetype_id", "")) == "melee_pursuer":
				melee_id = actor_id
		_expect(not melee_id.is_empty(), "production: wave.02 request did not materialize its actor")
		var melee_key: String = registry.entity_key_for_handle(registry.actor_handle(melee_id)) if not melee_id.is_empty() else ""
		_expect(not melee_key.is_empty() and port.is_entity_bound(melee_key), "production: wave.02 materialization did not register its member")
		_expect(bool(registry.actor_snapshot(melee_id).get("active", false)), "production: wave.02 deployment did not activate its materialized actor")
		var active_hurtbox := false
		for body: Dictionary in scene_runtime.dynamic_spatial_index.bodies(&"hurtbox"):
			if String(body.get("entity_id", "")) == melee_id:
				active_hurtbox = true
		_expect(active_hurtbox, "production: adopted wave.02 actor was missing from the hurtbox index")
		_expect(int(encounter.snapshot().get("current_wave_index", -1)) == 1, "production: authored wave order was not sequential")

	var melee = _arena_enemy(arena, "melee_pursuer")
	_expect(melee != null, "production: authored arena lost its melee_pursuer record")
	if melee == null or not _cast_real_arrow(arena, melee):
		_expect(false, "production: real arrow against the wave.02 pursuer was rejected")
		runtime.free()
		return
	var finished := _advance_until(arena, func() -> bool:
		return bool(arena.battle_over)
	, 120)
	_expect(finished and bool(arena.battle_victory), "production: authored multi-wave did not finish in victory")
	for _post_terminal in 3:
		arena.call("_simulate_tick")
	_expect(String(encounter.snapshot().get("phase", "")) == "victory", "production: encounter domain did not reach authored victory")
	_expect(bool(port.snapshot().get("terminal", {}).get("victory", false)), "production: port terminal projection missed authored victory")
	_expect(port.pending_spawn_requests.is_empty(), "production: terminal victory emitted a later spawn request")
	_expect(port.spawned_notifications.size() == 2, "production: terminal victory produced an extra spawn acknowledgement")

	var completed: Array[Dictionary] = []
	runtime.completed.connect(func(result: Dictionary) -> void: completed.append(result.duplicate(true)))
	runtime.request_abandon()
	_expect(completed.size() == 1 and String(completed[0].get("outcome", "")) == "victory", "production: authored session did not emit one victory result")
	runtime.free()


func _test_mixed_boss_encounter_authority() -> void:
	var resolved: Dictionary = _resolved_fixture("calibration_exponential")
	_expect(bool(resolved.get("ok", false)), "mixed boss: resolved combat build was rejected")
	if not bool(resolved.get("ok", false)):
		return
	# Keep the mounted production payload deterministic while reducing the
	# detached Boss health below one hit for a short, real end-to-end seam test.
	resolved["total_events"] = {"layer": 1, "magnitude": 12.0}
	resolved["total_events_float"] = 1.0e12
	var runtime = CombatRoomRuntimeScript.new()
	root.add_child(runtime)
	var started: Dictionary = runtime.start_session({
		"mode": "Manual",
		"presentation_enabled": false,
		"seed": 1901,
		"room": {
			"room_id": "test.mixed.boss.encounter",
			"layout_id": "rectangle_arena",
			"objective_id": "clear",
			"hazard_ids": [],
			"enemy_ids": ["melee_pursuer"],
			"elite_rule_ids": [],
			"boss_id": "threshold_colossus",
			"drop_tags": [],
		},
		"framework_context": {
			"active_build": {"skills": ["piercing_arrow"]},
			"resolved_build": resolved,
		},
	})
	_expect(bool(started.get("ok", false)), "mixed boss: mounted runtime failed: %s" % str(started))
	if not bool(started.get("ok", false)):
		runtime.queue_free()
		return
	runtime.set_process(false)
	var arena: Node = runtime.room_instance
	arena.set_process(false)
	var scene_runtime: Node = runtime.scene_runtime
	var port: Variant = scene_runtime.get("encounter_port")
	var encounter: Variant = scene_runtime.get("encounter_domain")
	var registry: Variant = scene_runtime.get("actor_registry")
	_expect(port != null and encounter != null and registry != null, "mixed boss: shared encounter domain was not mounted")
	if port == null or encounter == null or registry == null:
		runtime.free()
		return
	var encounter_snapshot: Dictionary = encounter.snapshot()
	var waves: Array = encounter_snapshot.get("waves", [])
	_expect(waves.size() == 1 and (waves[0] as Dictionary).get("spawns", []).size() == 2, "mixed boss: shared wave did not include ordinary actor and Boss")
	var adopted := _advance_until(arena, func() -> bool:
		return port.spawned_notifications.size() == 2
	, 20)
	_expect(adopted, "mixed boss: shared encounter did not adopt both actors")
	var normal = _arena_enemy(arena, "melee_pursuer")
	var boss = _arena_enemy(arena, "threshold_colossus")
	_expect(normal != null and boss != null, "mixed boss: production actors were not both present")
	if normal == null or boss == null:
		runtime.free()
		return
	var normal_id := "enemy/%d" % int(normal.entity_id)
	var boss_id := "enemy/%d" % int(boss.entity_id)
	_expect(bool(registry.actor_snapshot(normal_id).get("active", false)), "mixed boss: ordinary actor was not active after deployment")
	_expect(bool(registry.actor_snapshot(boss_id).get("active", false)), "mixed boss: Boss actor was frozen by ordinary deployment")
	var normal_cast := _cast_real_arrow(arena, normal)
	_expect(normal_cast, "mixed boss: ordinary production cast was rejected")
	var normal_dead := _advance_until(arena, func() -> bool:
		return not registry.has_actor(normal_id)
	, 120)
	_expect(normal_dead, "mixed boss: ordinary death did not settle through the shared encounter")
	if not normal_dead:
		runtime.free()
		return
	var boss_target = arena._boss_combat_domain.target(arena._enemy_stable_keys.find_key(int(boss.entity_id)))
	_expect(boss_target != null, "mixed boss: Boss detached target was not registered")
	if boss_target == null:
		runtime.free()
		return
	var boss_cast := _cast_real_arrow(arena, boss)
	# The domain owns Boss BigValue health; lower that detached value explicitly
	# for this test after the real cast request has been accepted.
	boss_target.health = BigValue.from_float(1.0)
	_expect(boss_cast, "mixed boss: Boss production cast was rejected")
	var mixed_finished := _advance_until(arena, func() -> bool:
		return bool(arena.battle_over)
	, 150)
	_expect(mixed_finished and bool(arena.battle_victory), "mixed boss: Main did not reach victory after both domains settled")
	var boss_entity_key := String(boss_target.target_key)
	var boss_death_seen := false
	for receipt: Dictionary in port.received_death_notifications:
		if String(receipt.get("entity_key", "")) == boss_entity_key:
			boss_death_seen = true
	_expect(boss_death_seen, "mixed boss: Boss settlement did not reach the shared RoomEncounter")
	for _post_terminal in 2:
		arena.call("_simulate_tick")
	var final_snapshot: Dictionary = encounter.snapshot()
	_expect(String(final_snapshot.get("phase", "")) == EncounterScript.PHASE_VICTORY, "mixed boss: shared RoomEncounter terminal phase diverged from Main")
	_expect((final_snapshot.get("spawn_records", []) as Array).size() == 2, "mixed boss: shared encounter lost a member record")
	runtime.free()


func _test_stale_tick_revision_and_unmount_shutdown() -> void:
	var runtime := _mount_runtime(11)
	var encounter: Variant = EncounterScript.new()
	encounter.configure("native.encounter.stale", [{
		"wave_id": "wave.stale",
		"spawns": [{"spawn_id": "one", "archetype_id": "one", "socket_id": "socket/Spawn", "count": 1}],
	}])
	runtime.bind_encounter(encounter)
	runtime.start_encounter()
	_expect(runtime.step_tick().ok, "stale: setup tick failed")
	var old_phase := String(encounter.snapshot().phase)
	var old_last_tick := int(encounter.snapshot().last_tick)
	var stale_step: Variant = encounter.step(old_last_tick - 1)
	_expect(stale_step.events.size() == 1 and stale_step.events[0].reason == "stale_encounter_tick", "stale: domain accepted an old tick")
	_expect(String(encounter.snapshot().phase) == old_phase and int(encounter.snapshot().last_tick) == old_last_tick, "stale: old tick mutated encounter state")
	var stale_ack: Dictionary = runtime.encounter_port.on_spawn_failed("wave.stale/one/0", old_last_tick, "late", runtime.room_instance_id, runtime.world_revision + 1)
	_expect(not bool(stale_ack.get("ok", false)) and String(stale_ack.get("error", "")) == "stale_spawn_failure_context", "stale: old room revision was accepted")
	var old_port = runtime.encounter_port
	var old_instance := runtime.room_instance_id
	_expect(bool(runtime.unmount().get("ok", false)), "lifecycle: unmount failed")
	_expect(not runtime.is_ready() and not bool(old_port.snapshot().get("bound", true)), "lifecycle: port stayed bound after unmount")
	var after_unmount: SimOutcome = runtime.step_tick()
	_expect(not after_unmount.ok and after_unmount.error == &"runtime_not_ready", "lifecycle: stale runtime step was accepted")
	_expect(not bool(old_port.on_spawn_failed("wave.stale/one/0", 1, "late").get("ok", false)), "lifecycle: retired port accepted a receipt")
	_expect(bool(runtime.mount(_definition(), _asset(), NativeScene, null, 12, 30).get("ok", false)), "lifecycle: remount failed")
	_expect(runtime.room_instance_id != old_instance and runtime.world_revision == 12, "lifecycle: remount did not publish a new room revision")
	_expect(bool(runtime.shutdown().get("ok", false)) and not runtime.is_ready(), "lifecycle: explicit shutdown failed")
	runtime.free()


func _mount_runtime(revision: int, encounter: Variant = null, spawn_binding: Variant = null, auto_start: bool = false) -> SceneRuntime:
	var runtime: SceneRuntime = RuntimeScript.new()
	root.add_child(runtime)
	var mounted: Dictionary = runtime.mount(_definition(), _asset(), NativeScene, null, revision, 30, null, encounter, spawn_binding, auto_start)
	_expect(bool(mounted.get("ok", false)) and runtime.is_ready(), "mount: real SceneRuntime mount failed: %s" % str(mounted))
	return runtime


func _definition() -> Dictionary:
	return {
		"room_id": "native.encounter.room",
		"world_asset_id": "native/concave_hole_passage",
		"encounter_id": "encounter.production",
		"ruleset_id": "rules.production",
		"tags": ["production"],
	}


func _asset() -> Dictionary:
	var manifest := SpatialScript.new(JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH)))
	return {
		"world_scene_path": NativeScene.resource_path,
		"manifest_path": MANIFEST_PATH,
		"gameplay_digest": manifest.gameplay_digest_sha256(),
		"presentation_digest": manifest.presentation_digest_sha256(),
		"schema_version": 1,
	}


func _campaign_rooms_by_id() -> Dictionary:
	var campaign: Variant = JSON.parse_string(FileAccess.get_file_as_string(CAMPAIGN_PATH))
	var rooms: Dictionary = {}
	_collect_campaign_rooms(campaign, rooms)
	return rooms


func _collect_campaign_rooms(node: Variant, rooms: Dictionary) -> void:
	if node is Dictionary:
		var data: Dictionary = node
		if data.has("id") and data.has("enemy_ids"):
			rooms[String(data.get("id", ""))] = data.duplicate(true)
		for value: Variant in data.values():
			_collect_campaign_rooms(value, rooms)
	elif node is Array:
		for value: Variant in node:
			_collect_campaign_rooms(value, rooms)


func _arena_enemy(arena: Node, archetype: String) -> Variant:
	for enemy: Variant in arena.enemies:
		if enemy != null and String(enemy.kind_id) == archetype:
			return enemy
	return null


func _cast_real_arrow(arena: Node, target: Variant) -> bool:
	var placement := _find_valid_attack_position(arena, target.position)
	if not bool(placement.get("ok", false)):
		return false
	if not bool(arena.teleport_actor("ranger", placement.position).get("ok", false)):
		return false
	target.health = 1.0
	target.maximum_health = 1.0
	var ready := _advance_until(arena, func() -> bool:
		return int(arena.player_combat_state.snapshot(arena.sim_tick).attack_cooldown_ticks) == 0
	, 120)
	if not ready:
		return false
	var cast: Dictionary = arena.request_player_cast("piercing_arrow", target.entity_id)
	return bool(cast.get("accepted", false))


func _find_valid_attack_position(arena: Node, target_position: Vector2) -> Dictionary:
	var targeting_distance: float = float(arena.player_combat_state.targeting_distance())
	for distance: float in [80.0, 100.0, 120.0, 140.0, 160.0, 180.0, 200.0]:
		if distance >= targeting_distance:
			continue
		for angle_index in 32:
			var candidate := target_position + Vector2.RIGHT.rotated(TAU * float(angle_index) / 32.0) * distance
			if arena.actor_registry.is_position_clear(candidate, arena._arena_rect(), 14.0):
				return {"ok": true, "position": candidate}
	return {"ok": false, "position": Vector2.ZERO}


func _advance_until(arena: Node, predicate: Callable, limit: int) -> bool:
	for _index in limit:
		if bool(predicate.call()):
			return true
		arena.call("_simulate_tick")
	return bool(predicate.call())


func _resolved_fixture(fixture_id: String) -> Dictionary:
	var registry = EarlyItemRegistryScript.new()
	if not registry.load_all().is_empty():
		return {}
	return BuildResolverScript.new(registry).resolve_fixture(fixture_id)


func _context(runtime: SceneRuntime) -> SimTickContext:
	var context := SimTickContext.new()
	context.tick = runtime.simulation.tick
	context.room_instance_id = runtime.room_instance_id
	context.world_revision = runtime.world_revision
	return context


func _typed_death_notification(entity_key: String, tick: int, room_id: String, revision: int, spawn_key: String) -> RefCounted:
	var notification: RefCounted = DeathSettlementNotificationScript.new()
	notification.entity_key = entity_key
	notification.tick = tick
	notification.room_id = room_id
	notification.world_revision = revision
	notification.spawn_key = spawn_key
	return notification


func _expect(condition: bool, message: String) -> void: Assert.expect(condition, message, failures)
