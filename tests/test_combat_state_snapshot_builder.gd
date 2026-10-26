extends SceneTree

const Builder := preload("res://src/game/combat_state_snapshot_builder.gd")
const Codec := preload("res://src/game/combat_state_codec.gd")
const Enemy := preload("res://src/runtime/world/combat_enemy_state.gd")
const Fixture := preload("res://tests/helpers/talent_runtime_fixture.gd")
const Assert := preload("res://tests/helpers/assert.gd")
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var fixture := Fixture.new()
	var session: Dictionary = fixture.start_session()
	var arena = session.arena
	arena.set_process(false)
	session.runtime.set_process(false)
	fixture.configure_target(arena)
	fixture.advance_to(arena, 5)
	var boss := Enemy.new(Vector2(600.0, 300.0), 1.0e12, true, 7, "threshold_colossus")
	arena.enemies.clear()
	arena.enemies.append(boss)
	arena.boss = boss
	var before := boss.gameplay_parts_snapshot()
	var baseline := Builder.build_runtime_state(arena, "parts")
	var baseline_hash := Codec.sha256_canonical(baseline)
	var parts: Array = baseline.enemies[0].parts
	_expect(parts.map(func(part: Dictionary) -> String: return part.part_id) == ["head", "left_hand", "right_hand"], "parts did not use stable ID ordering")
	_expect(parts[0].pose_y_milli == -74000 and parts[0].hurtbox.radius_milli == 56000 and typeof(parts[0].pose_x_milli) == TYPE_INT, "pose/hurtbox numeric encoding changed")
	parts[0].hurtbox.radius_milli = 1
	parts[1].active = false
	_expect(boss.gameplay_parts_snapshot() == before, "builder snapshot retained writable part authority")
	baseline = Builder.build_runtime_state(arena, "parts")
	boss.parts.reverse()
	_expect(Builder.hash_runtime(arena, "parts") == baseline_hash, "incidental part array order changed replay hash")
	var head := _part(boss, "head")
	head.active = false
	_expect(Builder.hash_runtime(arena, "parts") != baseline_hash, "active state was absent from gameplay hash")
	head.active = true
	head.broken = true
	_expect(Builder.hash_runtime(arena, "parts") != baseline_hash, "broken state was absent from gameplay hash")
	head.broken = false
	head.pose += Vector2(1.0, 0.0)
	_expect(Builder.hash_runtime(arena, "parts") != baseline_hash, "legal authored pose change was absent from gameplay hash")
	head.pose -= Vector2(1.0, 0.0)
	head.damage_group_id = "head-only"
	_expect(Builder.hash_runtime(arena, "parts") != baseline_hash, "damage grouping was absent from gameplay hash")
	head.damage_group_id = "body"
	head.hurtbox.radius += 1.0
	_expect(Builder.hash_runtime(arena, "parts") != baseline_hash, "hurtbox size was absent from gameplay hash")
	head.hurtbox.radius -= 1.0
	_expect(Builder.hash_runtime(arena, "parts") == baseline_hash, "restoring part values failed to restore the canonical hash")
	var pose_before: Vector2 = head.pose
	head.pose = pose_before + Vector2(0.0001, 0.0)
	var precise: Dictionary = Builder.build_runtime_state(arena, "parts")
	_expect(precise.enemies[0].parts[0].pose_x_milli == baseline.enemies[0].parts[0].pose_x_milli and Codec.sha256_canonical(precise) != baseline_hash, "milli rounding hid a sub-millipixel authored pose change")
	head.pose = pose_before
	var radius_before: float = head.hurtbox.radius
	head.hurtbox.radius = radius_before + 0.0001
	precise = Builder.build_runtime_state(arena, "parts")
	_expect(precise.enemies[0].parts[0].hurtbox.radius_milli == baseline.enemies[0].parts[0].hurtbox.radius_milli and Codec.sha256_canonical(precise) != baseline_hash, "milli rounding hid a sub-millipixel hurtbox radius change")
	head.hurtbox.radius = radius_before
	var hand_before: Vector2 = boss.left_hand_position
	boss.left_hand_position = hand_before + Vector2(0.0001, 0.0)
	precise = Builder.build_runtime_state(arena, "parts")
	var with_legacy_hand_fields := baseline.duplicate(true)
	with_legacy_hand_fields.enemies[0].left_hand_x_milli = precise.enemies[0].left_hand_x_milli
	with_legacy_hand_fields.enemies[0].left_hand_y_milli = precise.enemies[0].left_hand_y_milli
	_expect(precise.enemies[0].parts[1].resolved_pose_x_milli == baseline.enemies[0].parts[1].resolved_pose_x_milli and Codec.sha256_canonical(precise) != Codec.sha256_canonical(with_legacy_hand_fields), "milli rounding hid a sub-millipixel resolved hand pose change")
	boss.left_hand_position = hand_before
	_expect(Builder.hash_runtime(arena, "parts") == baseline_hash, "precise float observation changed the source geometry")
	boss.queue_part_state("right_hand", false, true)
	boss.queue_part_state("head", false, false)
	var pending_hash := Builder.hash_runtime(arena, "parts")
	_expect(pending_hash != baseline_hash and head.active, "queued transitions were absent from hash or committed while reading")
	var pending_snapshot := boss.gameplay_parts_snapshot()
	pending_snapshot.pending_part_transitions[0].changes[0].broken = true
	_expect(Builder.hash_runtime(arena, "parts") == pending_hash, "pending transition snapshot polluted the queue")
	var equivalent := Enemy.new(boss.position, boss.health, true, boss.entity_id, boss.kind_id)
	equivalent.queue_part_state("head", false, false)
	equivalent.queue_part_state("right_hand", false, true)
	arena.enemies.clear()
	arena.enemies.append(equivalent)
	arena.boss = equivalent
	_expect(Builder.hash_runtime(arena, "parts") == pending_hash, "independent part transition queue order changed replay hash")
	equivalent.queue_part_state("head", true, true)
	var ordered_hash := Builder.hash_runtime(arena, "parts")
	var reversed_changes := Enemy.new(boss.position, boss.health, true, boss.entity_id, boss.kind_id)
	reversed_changes.queue_part_state("head", true, true)
	reversed_changes.queue_part_state("head", false, false)
	reversed_changes.queue_part_state("right_hand", false, true)
	arena.enemies.clear()
	arena.enemies.append(reversed_changes)
	arena.boss = reversed_changes
	_expect(Builder.hash_runtime(arena, "parts") != ordered_hash, "same-part transition request order lost commit semantics")
	var outcome: Dictionary = arena.combat_system.outcome_snapshot()
	var state := Builder.build_runtime_state(arena, "parts")
	_expect(state.casts == outcome.shots and state.arrow_hits == outcome.arrow_hits and state.defeated == outcome.defeated and state.boss_damage.magnitude == String.num(outcome.boss_damage.magnitude, 12), "builder totals did not read CombatSystem outcome authority")
	arena.enemies.clear()
	state = Builder.build_runtime_state(arena, "victory")
	_expect(state.enemies.is_empty() and not state.has("parts") and state.sim_protocol_version == 1, "part extension changed empty-roster terminal field layout")
	fixture.free_session(session)
	for failure: String in failures:
		printerr("FAIL: " + failure)
	if failures.is_empty():
		print("PASS test_combat_state_snapshot_builder.gd (part order/state/pose/pending/detachment, totals authority)")
	quit(0 if failures.is_empty() else 1)


func _part(enemy, id: String) -> Dictionary:
	for part: Dictionary in enemy.parts:
		if part.part_id == id:
			return part
	return {}


func _expect(condition: bool, message: String) -> void: Assert.expect(condition, message, failures)
