extends SceneTree

const DeathRequestScript := preload("res://src/runtime/combat/death_settlement_request.gd")
const DeathScript := preload("res://src/runtime/combat/death_settlement.gd")
const DeathNotificationScript := preload("res://src/runtime/combat/death_settlement_notification.gd")
const LootScript := preload("res://src/runtime/combat/combat_room_loot_rebuild.gd")
const PlacementPortScript := preload("res://src/runtime/world/room_loot_placement_port.gd")
const MountedPlacementScript := preload("res://src/game/main_loot_placement_port.gd")
const Assert := preload("res://tests/helpers/assert.gd")


class FakeMaterializer:
	func generate_drop(seed: int, stream_key: String, drop_index: int, tags: Array, guarantee_family: String) -> Dictionary:
		return {
			"instance_id": "%s/%d" % [stream_key, drop_index],
			"seed": seed,
			"tags": tags.duplicate(),
			"guarantee_family": guarantee_family,
		}


class AlwaysClearPlacement:
	extends PlacementPortScript

	func is_position_clear(_position: Vector2, _radius: float) -> bool:
		return true


class WallPlacementRoom:
	var divided := false

	func is_position_clear(position: Vector2, radius: float) -> bool:
		if divided:
			# A narrow pocket and a separate open area across a solid wall.
			return (position.x >= radius and position.x <= 32.0 - radius) or position.x >= 40.0 + radius
		return position.x >= radius


func _initialize() -> void:
	var failures: Array[String] = []
	_test_death_settlement(failures)
	_test_room_loot(failures)
	_test_near_wall_drop(failures)
	for failure: String in failures:
		printerr("- %s" % failure)
	print("PASS test_death_settlement_loot.gd" if failures.is_empty() else "FAIL test_death_settlement_loot.gd")
	quit(0 if failures.is_empty() else 1)


func _test_near_wall_drop(failures: Array[String]) -> void:
	var room := WallPlacementRoom.new()
	var placement := MountedPlacementScript.new()
	placement.configure(room)
	var origin := Vector2(16, 0)
	var resolved: Variant = placement.resolve_drop_position(origin, 18.0)
	_expect(resolved == Vector2(20, 0), "near-wall drop did not move to adjacent clear floor", failures)
	_expect(resolved == placement.resolve_drop_position(origin, 18.0), "near-wall drop is not deterministic", failures)
	_expect(placement.resolve_drop_position(Vector2(30, 0), 18.0) == Vector2(30, 0), "clear drop changed position", failures)
	_expect(placement.resolve_drop_position(Vector2.ZERO, 18.0) == null, "blocked drop origin was rescued", failures)
	room.divided = true
	_expect(placement.resolve_drop_position(origin, 18.0) == null, "drop crossed a wall to reach disconnected floor", failures)


func _test_death_settlement(failures: Array[String]) -> void:
	var settlement: Variant = DeathScript.new()
	_expect(bool(settlement.configure("room.test", 4).get("ok", false)), "death settlement configuration failed", failures)
	var request := {
		"tick": 8,
		"room_id": "room.test",
		"world_revision": 4,
		"entity_key": "enemy/1",
		"source_key": "ranger",
		"spawn_key": "wave.01/melee/0",
		"archetype_id": "melee",
		"position": Vector2(12.0, 5.0),
		"loot_tags": ["equipment.common"],
	}
	var first: Dictionary = settlement.settle(request)
	_expect(bool(first.get("ok", false)) and bool(first.get("changed", false)), "first death was not settled", failures)
	var value: Variant = first.get("value", null)
	_expect(value != null and not value.removal_request.is_empty() and value.encounter_notification is DeathNotificationScript, "death settlement did not emit removal and encounter requests", failures)
	_expect(value != null and value.encounter_notification is DeathNotificationScript, "death settlement did not emit a typed encounter notification", failures)
	if value != null and value.encounter_notification is DeathNotificationScript:
		_expect(value.encounter_notification.world_revision == 4, "typed death notification lost world revision", failures)
	_expect(not value.loot_spawn_request.is_empty(), "death settlement did not emit loot request", failures)
	var duplicate: Dictionary = settlement.settle(request)
	_expect(bool(duplicate.get("ok", false)) and bool(duplicate.get("duplicate", false)) and not bool(duplicate.get("changed", true)), "duplicate death emitted a second settlement", failures)
	_expect((settlement.snapshot().get("settled_keys", []) as Array).size() == 1, "death settlement key accounting is not idempotent", failures)
	var stale_request := request.duplicate(true)
	stale_request["world_revision"] = 5
	var stale: Dictionary = settlement.settle(stale_request)
	_expect(not bool(stale.get("ok", false)) and String(stale.get("error", "")) == "death_request_revision_mismatch", "stale death revision was accepted", failures)
	var invalid: Dictionary = DeathRequestScript.from_data({"tick": 8, "room_id": "room.test", "entity_key": "bad key", "position": Vector2.ZERO})
	_expect(not bool(invalid.get("ok", false)), "invalid death request was accepted", failures)


func _test_room_loot(failures: Array[String]) -> void:
	var loot: Variant = LootScript.new()
	var materializer := FakeMaterializer.new()
	var configured: Dictionary = loot.configure("room.test", 99, [
		{"slot_id": "enemy_drop", "source": "enemy_death", "tags": ["equipment.common"], "pickup_radius": 8.0},
	], materializer, AlwaysClearPlacement.new())
	_expect(bool(configured.get("ok", false)), "room loot configuration failed", failures)
	var spawned: Dictionary = loot.spawn(8, {
		"tick": 8,
		"room_id": "room.test",
		"source": "enemy_death",
		"source_entity_key": "enemy/1",
		"position": Vector2(10.0, 10.0),
		"tags": ["equipment.common"],
	})
	_expect(bool(spawned.get("ok", false)), "room loot spawn failed", failures)
	var loot_entity_id := String((spawned.get("entity", {}) as Dictionary).get("loot_entity_id", ""))
	_expect(not loot_entity_id.is_empty(), "room loot entity identity missing", failures)
	var rejected: Dictionary = loot.request_pickup(8, "ranger", loot_entity_id)
	_expect(bool(rejected.get("ok", false)), "room loot pickup request was rejected", failures)
	var out_of_range: Array[Dictionary] = loot.commit_pickups(9, 100.0, Vector2.ZERO, false, false)
	_expect(out_of_range.size() == 1 and not bool(out_of_range[0].get("ok", true)), "out of range pickup was accepted", failures)
	var second_request: Dictionary = loot.request_pickup(9, "ranger", loot_entity_id)
	_expect(bool(second_request.get("ok", false)), "room loot could not retry after rejected pickup", failures)
	var picked: Array[Dictionary] = loot.commit_pickups(10, 100.0, Vector2(10.0, 10.0), true, true)
	_expect(picked.size() == 1 and bool(picked[0].get("ok", false)), "in range victory pickup failed", failures)
	var settled: Dictionary = loot.settle("victory")
	_expect(bool(settled.get("ok", false)) and (settled.get("items", []) as Array).size() == 1, "picked room loot did not settle", failures)
	var repeated: Dictionary = loot.settle("victory")
	_expect(JSON.stringify(settled) == JSON.stringify(repeated), "room loot settlement was not idempotent", failures)
	var snapshot: Dictionary = loot.snapshot()
	_expect(String(((snapshot.get("entities", []) as Array)[0] as Dictionary).get("state", "")) == LootScript.PICKED_STATE, "settlement changed picked loot state", failures)
func _expect(condition: bool, message: String, failures: Array[String]) -> void: Assert.expect(condition, message, failures)
