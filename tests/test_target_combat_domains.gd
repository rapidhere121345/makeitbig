extends SceneTree

const EncounterScript := preload("res://src/runtime/encounter/room_encounter.gd")
const DamageScript := preload("res://src/runtime/combat/damage_resolution.gd")
const HitScript := preload("res://src/runtime/combat/combat_hit_record.gd")
const StatusScript := preload("res://src/runtime/combat/status_effect_ledger.gd")


func _initialize() -> void:
	var failures: Array[String] = []
	_test_encounter(failures)
	_test_damage(failures)
	_test_status(failures)
	for failure: String in failures:
		printerr("- %s" % failure)
	print("PASS test_target_combat_domains.gd" if failures.is_empty() else "FAIL test_target_combat_domains.gd")
	quit(0 if failures.is_empty() else 1)


func _test_encounter(failures: Array[String]) -> void:
	var encounter: Variant = EncounterScript.new()
	var configured: Dictionary = encounter.configure("room.test", [
		{
			"wave_id": "wave.01",
			"spawns": [{"spawn_id": "melee", "archetype_id": "melee", "socket_id": "north", "count": 1}],
			"next_wave_delay_ticks": 1,
		},
		{
			"wave_id": "wave.02",
			"spawns": [{"spawn_id": "ranged", "archetype_id": "ranged", "socket_id": "south", "count": 1}],
		},
	])
	_expect(bool(configured.get("ok", false)), "encounter configuration failed", failures)
	_expect(bool(encounter.start(0).get("ok", false)), "encounter start failed", failures)
	var first: Variant = encounter.step(0)
	_expect(first.spawn_requests.size() == 1 and first.phase == EncounterScript.PHASE_ACTIVE, "first wave did not emit one request", failures)
	if first.spawn_requests.size() == 1:
		var first_request: Variant = first.spawn_requests[0]
		_expect(bool(encounter.notify_spawned(first_request.spawn_key, "enemy/1", 0).get("ok", false)), "spawn registration failed", failures)
		_expect(bool(encounter.notify_death("enemy/1", 1).get("ok", false)), "death registration failed", failures)
	var cleared: Variant = encounter.step(1)
	_expect(cleared.phase == EncounterScript.PHASE_WAITING, "cleared wave did not enter waiting phase", failures)
	var second: Variant = encounter.step(2)
	_expect(second.spawn_requests.size() == 1 and second.spawn_requests[0].wave_id == "wave.02", "next wave did not start deterministically", failures)
	var snapshot_a := JSON.stringify(encounter.snapshot())
	var snapshot_b := JSON.stringify(encounter.snapshot())
	_expect(snapshot_a == snapshot_b, "encounter snapshot is not stable", failures)


func _test_damage(failures: Array[String]) -> void:
	var hits: Array = []
	for data: Dictionary in [
		{"tick": 4, "attack_instance_id": "arrow/1", "source_key": "ranger", "target_key": "enemy/1", "part_id": "body", "damage_group_id": "body", "base_damage": 50.0, "toi": 0.2},
		{"tick": 4, "attack_instance_id": "arrow/1", "source_key": "ranger", "target_key": "enemy/1", "part_id": "body", "damage_group_id": "body", "base_damage": 50.0, "toi": 0.3},
		{"tick": 4, "attack_instance_id": "arrow/2", "source_key": "ranger", "target_key": "enemy/1", "part_id": "body", "damage_group_id": "body", "base_damage": 60.0, "toi": 0.4},
	]:
		var parsed: Dictionary = HitScript.from_data(data)
		_expect(bool(parsed.get("ok", false)), "valid hit record rejected", failures)
		if bool(parsed.get("ok", false)):
			hits.append(parsed["value"])
	var resolver: Variant = DamageScript.new()
	var result: Variant = resolver.resolve(4, hits, [{"target_key": "enemy/1", "health": 100.0, "maximum_health": 100.0, "alive": true, "resistances": {"physical": 0.0}}])
	_expect(result.outcomes.size() == 2, "duplicate attack hit was not suppressed", failures)
	_expect(result.deaths == ["enemy/1"], "lethal damage did not produce one deterministic death", failures)
	_expect(is_equal_approx(result.outcomes[-1].remaining_health, 0.0), "damage result did not reach zero health", failures)


func _test_status(failures: Array[String]) -> void:
	var ledger: Variant = StatusScript.new()
	_expect(bool(ledger.reset().get("ok", false)), "status ledger reset failed", failures)
	var applied: Dictionary = ledger.apply(0, "enemy/1", "burning_ground", "hazard/1", 5, 2, 7.0)
	_expect(bool(applied.get("ok", false)), "periodic status application failed", failures)
	_expect(ledger.collect_periodic_hits(2).size() == 1, "first periodic status tick missing", failures)
	_expect(ledger.collect_periodic_hits(3).is_empty(), "periodic status fired before cadence", failures)
	_expect(ledger.collect_periodic_hits(4).size() == 1, "second periodic status tick missing", failures)
	var expired: Dictionary = ledger.advance(5)
	_expect((expired.get("expired", []) as Array).size() == 1, "status did not expire at boundary", failures)
	_expect(ledger.snapshot(5).effects.is_empty(), "expired status remained in snapshot", failures)


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
