extends SceneTree

## Whole-AABB collision: production spawn-projection verification.
##
## Run: godot --headless --path . --script res://tests/test_spawn_projection_whole_blockers.gd
##
## For every combat layout x authored spawn profile, mount a real session via
## CombatRoomRuntime.start_session (the native Main spawn path) and verify the
## ACTUAL registered enemy positions:
##   - every roster enemy spawns (no vacuous pass, exact count)
##   - each registry position clears mounted static blockers at footprint 16
##     via the static spatial index MOVEMENT channel
##   - pairwise enemy distance >= 32 (16+16) and hero distance >= 30 (16+14)
## Positions/IDs are printed for audit. No spawn algorithm is replicated.

const Fixture := preload("res://tests/helpers/player_domain_fixture.gd")
const Channels := preload("res://src/runtime/spatial/spatial_channels.gd")

const ENEMY_R := 16.0
const PAIRWISE_MIN := 32.0
const HERO_MIN := 30.0  # enemy 16 + hero 14

## room_id selects the catalog spawn profile (profiles.get(room_id, "default")).
## Room dicts carry the complete schema used by test_enemy_runtime.
const CASES := [
	{"layout": "rectangle_arena", "room_id": "default", "count": 6},
	{"layout": "rectangle_arena", "room_id": "first_hunt_clear", "count": 3},
	{"layout": "rectangle_arena", "room_id": "first_hunt_followup", "count": 3},
	{"layout": "rectangle_arena", "room_id": "test.fixture", "count": 7},
	{"layout": "corridor", "room_id": "default", "count": 4},
	{"layout": "corridor", "room_id": "first_hunt_followup", "count": 3},
	{"layout": "ring", "room_id": "default", "count": 6},
]

var failures: Array[String] = []
var completed_cases := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var fixture := Fixture.new()
	for case: Dictionary in CASES:
		_check_case(fixture, case)
	_expect(completed_cases == CASES.size(),
		"only %d of %d cases completed (coroutine abort would otherwise pass)" % [
			completed_cases, CASES.size()])
	for failure: String in failures:
		printerr(failure)
	if failures.is_empty():
		print("PASS  test_spawn_projection_whole_blockers.gd")
		quit(0)
		return
	printerr("FAIL  test_spawn_projection_whole_blockers.gd")
	quit(1)


func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)


func _check_case(fixture: Variant, case: Dictionary) -> void:
	var layout := String(case["layout"])
	var room_id := String(case["room_id"])
	var count := int(case["count"])
	var roster: Array = []
	for i in count:
		roster.append("melee_pursuer")
	var room := {
		"room_id": room_id,
		"layout_id": layout,
		"objective_id": "clear",
		"hazard_ids": [],
		"enemy_ids": roster,
		"elite_rule_ids": [],
		"boss_id": "",
		"drop_tags": [],
	}
	var session: Dictionary = fixture.mount(room)
	var arena = session.get("arena", null)
	if arena == null:
		_expect(false, "%s/%s: mount produced no arena" % [layout, room_id])
		return
	var index: Variant = arena.scene_runtime.get("static_spatial_index") \
		if arena.get("scene_runtime") != null else null
	if index == null:
		_expect(false, "%s/%s: static spatial index unavailable" % [layout, room_id])
		fixture.free_session(session)
		return
	var enemies: Array = arena.enemies
	_expect(enemies.size() == count,
		"%s/%s: expected %d spawned enemies, got %d" % [layout, room_id, count, enemies.size()])
	var hero_actor: Variant = arena.actor_registry.actor("ranger")
	_expect(hero_actor != null, "%s/%s: ranger missing from actor registry" % [layout, room_id])
	var hero_position: Vector2 = hero_actor.feet_position if hero_actor != null else Vector2.ZERO
	var positions: Array[Vector2] = []
	var ids: Array[String] = []
	for enemy: Variant in enemies:
		var actor_id := "enemy/%d" % int(enemy.entity_id)
		var actor: Variant = arena.actor_registry.actor(actor_id)
		_expect(actor != null, "%s/%s: %s missing from actor registry" % [layout, room_id, actor_id])
		if actor == null:
			continue
		var position: Vector2 = actor.feet_position
		positions.append(position)
		ids.append(actor_id)
		_expect(index.is_position_clear(Channels.MOVEMENT, position, ENEMY_R),
			"%s/%s: %s registry position %s blocked at r16" % [layout, room_id, actor_id, str(position)])
		_expect(position.distance_to(hero_position) >= HERO_MIN,
			"%s/%s: %s at %s overlaps hero %s (%.1f < 30)" % [
				layout, room_id, actor_id, str(position), str(hero_position),
				position.distance_to(hero_position)])
	for i in positions.size():
		for j in range(i + 1, positions.size()):
			if positions[i].distance_to(positions[j]) < PAIRWISE_MIN:
				_expect(false, "%s/%s: %s vs %s pairwise %.1f < 32" % [
					layout, room_id, ids[i], ids[j], positions[i].distance_to(positions[j])])
	print("%s/%s: %d enemies, positions=%s ids=%s" % [
		layout, room_id, positions.size(), str(positions), str(ids)])
	fixture.free_session(session)
	completed_cases += 1
