extends SceneTree

const StatsScript := preload("res://src/game/combat_stats_snapshot.gd")
const WaveScript := preload("res://src/runtime/encounter/wave_definition.gd")
const LootScript := preload("res://src/runtime/combat/combat_room_loot_rebuild.gd")
const ItemRegistryScript := preload("res://src/content/early_item_registry.gd")
const GeneratorScript := preload("res://src/systems/equipment_drop_generator.gd")
const PlacementPortScript := preload("res://src/runtime/world/room_loot_placement_port.gd")


class AlwaysClearPlacement:
	extends PlacementPortScript

	func is_position_clear(_position: Vector2, _radius: float) -> bool:
		return true


func _initialize() -> void:
	var failures: Array[String] = []
	_test_stats(failures)
	_test_waves(failures)
	_test_loot(failures)
	for failure: String in failures:
		printerr("- %s" % failure)
	print("PASS test_real_combat_domains.gd" if failures.is_empty() else "FAIL test_real_combat_domains.gd")
	quit(0 if failures.is_empty() else 1)


func _test_stats(failures: Array[String]) -> void:
	var data := _stats_data()
	var built := StatsScript.from_data(data)
	_expect(bool(built.ok), "stats: valid resolved sheet was rejected", failures)
	if not bool(built.ok):
		return
	var stats: RefCounted = built.value
	var snapshot: Dictionary = stats.snapshot()
	_expect(float(snapshot.move_speed) == 72.0 and int(snapshot.dodge_distance) == 96, "stats: numeric fields were not preserved", failures)
	(snapshot.resistances as Dictionary)["physical"] = 0.99
	_expect(float(stats.resistances.physical) == 0.25, "stats: snapshot leaked resistance storage", failures)
	var missing := data.duplicate(true)
	missing.erase("provenance")
	_expect(not bool(StatsScript.from_data(missing).ok), "stats: missing provenance was accepted", failures)
	var build_result := StatsScript.from_resolved_build({
		"final_parameters": {"max_health": 120.0, "damage": 55.0, "v": 240.0, "d": 225.0},
		"combat_stats": {"move_speed": 72.0, "acceleration": 120.0, "dodge_distance": 96.0, "attack_cooldown_ticks": 12, "dodge_duration_ticks": 6, "dodge_cooldown_ticks": 30, "resistances": {"physical": 0.25}},
	})
	_expect(bool(build_result.ok) and float((build_result.value as RefCounted).maximum_health) == 120.0, "stats: resolved build adapter failed", failures)
	var missing_combat := StatsScript.from_resolved_build({"final_parameters": {"max_health": 120.0, "damage": 55.0, "v": 240.0, "d": 225.0}})
	_expect(String(missing_combat.error) == "missing_combat_stats", "stats: missing combat stats did not fail closed", failures)


func _test_waves(failures: Array[String]) -> void:
	var wave_data := {
		"wave_id": "wave_01",
		"start_delay_ticks": 30,
		"spawns": [{"spawn_id": "enemy_a", "archetype_id": "melee_pursuer", "socket_id": "spawn.a", "count": 2}],
		"clear_policy": "all_dead",
		"next_wave_delay_ticks": 15,
	}
	var normalized := WaveScript.from_data(wave_data)
	_expect(bool(normalized.ok), "waves: valid authored wave was rejected", failures)
	if bool(normalized.ok):
		var wave: RefCounted = normalized.value
		_expect(wave.total_spawn_count() == 2, "waves: spawn count was not preserved", failures)
		var copy: Dictionary = wave.snapshot()
		(copy.spawns as Array)[0]["archetype_id"] = "tampered"
		_expect(String(wave.spawn_specs[0].archetype_id) == "melee_pursuer", "waves: snapshot leaked spawn definition", failures)
	var duplicate := wave_data.duplicate(true)
	duplicate["spawns"] = [wave_data.spawns[0].duplicate(true), wave_data.spawns[0].duplicate(true)]
	_expect(not bool(WaveScript.from_data(duplicate).ok) and String(WaveScript.from_data(duplicate).error).contains("duplicate_spawn_id"), "waves: duplicate spawn identity was accepted", failures)
	var unknown := wave_data.duplicate(true)
	unknown["unexpected"] = true
	_expect(not bool(WaveScript.from_data(unknown).ok), "waves: unknown field was accepted", failures)


func _test_loot(failures: Array[String]) -> void:
	var registry := ItemRegistryScript.new()
	var load_errors: Array[String] = registry.load_all()
	_expect(load_errors.is_empty(), "loot: item registry failed to load", failures)
	if not load_errors.is_empty():
		return
	var generator := GeneratorScript.new(registry)
	var ledger := LootScript.new()
	var configured := ledger.configure("real_room_01", 77123, [
		{"slot_id": "wave_01_drop", "source": "wave_clear", "tags": ["equipment_general"], "pickup_radius": 18.0},
		{"slot_id": "defeat_drop", "source": "enemy_death", "tags": ["equipment_general"], "pickup_radius": 18.0},
	], generator, AlwaysClearPlacement.new())
	_expect(bool(configured.get("ok", false)), "loot: target room authority configuration failed", failures)
	var spawned := ledger.spawn(30, {
		"tick": 30, "room_id": "real_room_01", "source": "wave_clear",
		"source_entity_key": "wave/101", "position": Vector2(100.0, 120.0),
		"tags": ["equipment_general"],
	})
	_expect(bool(spawned.ok), "loot: deterministic room drop failed to spawn", failures)
	if not bool(spawned.ok):
		return
	var entity_id := String(spawned.entity.loot_entity_id)
	var repeated := ledger.spawn(31, {
		"tick": 31, "room_id": "real_room_01", "source": "wave_clear",
		"source_entity_key": "wave/101", "position": Vector2(100.0, 120.0),
		"tags": ["equipment_general"],
	})
	_expect(String(repeated.error) == "no_matching_loot_slot", "loot: duplicate slot was accepted", failures)
	var pickup_request := ledger.request_pickup(32, "ranger", entity_id)
	_expect(bool(pickup_request.get("ok", false)), "loot: pickup request was rejected", failures)
	var out_of_range: Array[Dictionary] = ledger.commit_pickups(33, 100.0, Vector2(140.0, 120.0), false, false)
	var out_of_range_receipt: Dictionary = out_of_range[0] if not out_of_range.is_empty() else {}
	_expect(String(out_of_range_receipt.get("error", "")) == "loot_out_of_range", "loot: out-of-range pickup was accepted", failures)
	var retry := ledger.request_pickup(33, "ranger", entity_id)
	_expect(bool(retry.get("ok", false)), "loot: in-range pickup could not be retried", failures)
	var picked_receipts: Array[Dictionary] = ledger.commit_pickups(34, 100.0, Vector2(110.0, 120.0), false, false)
	var picked: Dictionary = picked_receipts[0] if not picked_receipts.is_empty() else {}
	_expect(bool(picked.get("ok", false)), "loot: in-range pickup was rejected", failures)
	var settled := ledger.settle("victory")
	_expect(bool(settled.ok) and (settled.items as Array).size() == 1, "loot: victory did not settle picked item", failures)
	var second_settle := ledger.settle("defeat")
	_expect(second_settle == settled, "loot: repeated settlement changed the receipt", failures)
	var detached := ledger.snapshot()
	(detached.entities as Array)[0]["state"] = "tampered"
	_expect(String(ledger.snapshot().entities[0].state) == LootScript.PICKED_STATE, "loot: snapshot leaked entity state", failures)
	var defeat_ledger := LootScript.new()
	defeat_ledger.configure("real_room_01", 77123, [
		{"slot_id": "defeat_drop", "source": "enemy_death", "tags": ["equipment_general"], "pickup_radius": 18.0},
	], generator, AlwaysClearPlacement.new())
	var defeat_spawn := defeat_ledger.spawn(1, {
		"tick": 1, "room_id": "real_room_01", "source": "enemy_death",
		"source_entity_key": "enemy/102", "position": Vector2.ZERO,
		"tags": ["equipment_general"],
	})
	var defeat := defeat_ledger.settle("defeat")
	_expect(bool(defeat_spawn.ok) and (defeat.items as Array).is_empty() and String(defeat.entities[0].state) == LootScript.FORFEITED_STATE, "loot: defeat granted or retained a room item", failures)


func _stats_data() -> Dictionary:
	var provenance := {}
	for field: String in StatsScript.NUMERIC_FIELDS + StatsScript.INTEGER_FIELDS:
		provenance[field] = ["character_base:%s" % field]
	return {
		"schema_version": StatsScript.SCHEMA_VERSION,
		"maximum_health": 120.0,
		"damage": 55.0,
		"projectile_speed": 240.0,
		"targeting_distance": 225.0,
		"move_speed": 72.0,
		"acceleration": 120.0,
		"dodge_distance": 96.0,
		"attack_cooldown_ticks": 12,
		"dodge_duration_ticks": 6,
		"dodge_cooldown_ticks": 30,
		"resistances": {"physical": 0.25},
		"provenance": provenance,
	}


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
