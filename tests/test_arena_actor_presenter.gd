extends SceneTree

const ArenaActorPresenterScript := preload("res://src/presentation/arena_actor_presenter.gd")
const CombatEnemyStateScript := preload("res://src/runtime/world/combat_enemy_state.gd")
const Assert := preload("res://tests/helpers/assert.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	var presenter := ArenaActorPresenterScript.new()
	var contract: Dictionary = presenter.contract_report()
	_expect((contract.get("frame_keys", {}) as Dictionary).has("enemy_frames"), "actor frame contract lost resolved enemy frames", failures)
	_expect((contract.get("draw_layers", []) as Array).has("actor_shadows"), "actor presenter does not own actor shadows", failures)
	_expect(String(contract.get("canvas_owner", "")).contains("caller"), "actor presenter hides transform ownership", failures)
	_expect(bool(contract.get("writes_gameplay_state", true)) == false, "actor presenter exposes gameplay writes", failures)
	_expect(bool(contract.get("fallback_art", true)) == false, "actor presenter advertises fallback art", failures)
	_expect(String(contract.get("native_sort_interface", "")).contains("sync_sort_views"), "actor presenter omitted explicit native SortRoot integration seam", failures)
	_expect(String(contract.get("sort_identity", "")).contains("entity/part IDs"), "actor presenter replaced gameplay identity with view identity", failures)

	var frame := _frame()
	_expect(presenter.validate_frame(frame).is_empty(), "valid actor frame was rejected", failures)
	var disabled := frame.duplicate(true)
	disabled["presentation_enabled"] = false
	var canvas := Node2D.new()
	presenter.draw_shadows(canvas, disabled, RefCounted.new())
	_expect(String(presenter.presentation_report().get("state", "")) == "disabled", "disabled actor frame was not inert", failures)
	_expect(frame["player_position"] == Vector2.ZERO and frame["enemy_frames"].is_empty(), "disabled actor projection mutated its frame", failures)

	presenter.draw_shadows(canvas, {}, RefCounted.new())
	_expect(String(presenter.presentation_report().get("state", "")) == "presentation_error", "invalid actor frame was accepted", failures)

	var enemy = CombatEnemyStateScript.new(Vector2(400.0, 300.0), 100.0, true, 1, "threshold_colossus")
	enemy.action_id = "slam"
	enemy.action_state = "recovery"
	enemy.state_started_tick = 100
	enemy.state_ends_tick = 124
	var before_left: Vector2 = enemy.left_hand_position
	var before_right: Vector2 = enemy.right_hand_position
	var pose: Dictionary = presenter.boss_visual_pose(enemy, 110)
	_expect(pose.has("left_hand_offset_px") and pose.has("right_hand_offset_px"), "Boss pose projection omitted hand offsets", failures)
	_expect(enemy.left_hand_position == before_left and enemy.right_hand_position == before_right, "Boss pose projection mutated authoritative hands", failures)

	var main_source := FileAccess.get_file_as_string("res://src/game/main.gd")
	_expect(not main_source.contains("func _draw_actors_ysorted"), "Main retained the old actor y-sort entry point", failures)
	_expect(not main_source.contains("func _draw_enemy("), "Main retained the old enemy draw entry point", failures)
	var combat_source := FileAccess.get_file_as_string("res://src/presentation/arena_combat_presenter.gd")
	_expect(not combat_source.contains("func draw_actor_shadows"), "combat presenter retained actor shadow ownership", failures)

	canvas.free()
	if failures.is_empty():
		print("ARENA_ACTOR_PRESENTER_PASS")
		quit(0)
		return
	for failure: String in failures:
		printerr("ARENA_ACTOR_PRESENTER_FAIL: " + failure)
	quit(1)


func _frame() -> Dictionary:
	return {
		"presentation_enabled": true,
		"in_arena": true,
		"sim_tick": 0,
		"player_position": Vector2.ZERO,
		"player_facing": Vector2.RIGHT,
		"ranger_visual_time": 0.0,
		"ranger_frame": {},
		"enemy_frames": {},
		"enemies": [],
		"enemy_corpses": [],
		"boss_health_ratio": 1.0,
	}


func _expect(condition: bool, message: String, failures: Array[String]) -> void: Assert.expect(condition, message, failures)
