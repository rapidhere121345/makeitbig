extends SceneTree

const ArenaCombatPresenterScript := preload("res://src/presentation/arena_combat_presenter.gd")
const ArenaGeometryScript := preload("res://src/runtime/geometry/arena_geometry.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	var presenter := ArenaCombatPresenterScript.new()
	var contract: Dictionary = presenter.contract_report()
	_expect(bool(contract.get("writes_gameplay_state", true)) == false, "presenter exposes gameplay writes", failures)
	_expect(bool(contract.get("fallback_art", true)) == false, "presenter advertises fallback art", failures)
	_expect(String(contract.get("canvas_owner", "")).contains("caller"), "presenter hides transform order", failures)
	var invalid := presenter.validate_frame({})
	_expect(invalid.begins_with("frame missing required key"), "empty frame was accepted", failures)
	var disabled := _frame()
	disabled["presentation_enabled"] = false
	var canvas := Node2D.new()
	presenter.draw_ground(canvas, disabled)
	_expect(String(presenter.presentation_report().get("state", "")) == "disabled", "disabled frame was not inert", failures)
	var ready := _frame()
	ready["presentation_enabled"] = true
	ready["in_arena"] = true
	var missing_geometry := ready.duplicate(true)
	missing_geometry["walkable_geometry"] = {}
	_expect(presenter.validate_frame(missing_geometry).begins_with("frame key walkable_geometry invalid:"), "arena frame accepted missing geometry", failures)
	var wrong_layout := ready.duplicate(true)
	wrong_layout["walkable_geometry"] = ArenaGeometryScript.from_layout("ring", ready["arena_rect"], 0.0)
	_expect(presenter.validate_frame(wrong_layout) == "frame key walkable_geometry layout mismatch", "arena frame accepted geometry from another layout", failures)
	var wrong_arena := ready.duplicate(true)
	wrong_arena["walkable_geometry"] = ArenaGeometryScript.from_layout("rectangle_arena", Rect2(5.0, 0.0, 100.0, 100.0), 0.0)
	_expect(presenter.validate_frame(wrong_arena) == "frame key walkable_geometry arena mismatch", "arena frame accepted another room's bounds", failures)
	presenter.draw_ground(canvas, ready)
	_expect(String(presenter.presentation_report().get("state", "")) == "ready", "valid frame did not complete the projection pass", failures)
	canvas.free()
	if failures.is_empty():
		print("ARENA_COMBAT_PRESENTER_PASS")
		quit(0)
		return
	for failure: String in failures:
		printerr("ARENA_COMBAT_PRESENTER_FAIL: " + failure)
	quit(1)


func _frame() -> Dictionary:
	return {
		"presentation_enabled": false,
		"in_arena": false,
		"arena_rect": Rect2(0.0, 0.0, 100.0, 100.0),
		"layout_id": "rectangle_arena",
		"walkable_geometry": ArenaGeometryScript.from_layout("rectangle_arena", Rect2(0.0, 0.0, 100.0, 100.0), 0.0),
		"sim_tick": 0,
		"player_position": Vector2.ZERO,
		"player_facing": Vector2.RIGHT,
		"enemies": [],
		"hazard_states": [],
		"projectiles": [],
		"traces": [],
		"combat_feedback_marks": [],
		"player_damage_overlay": {},
		"dash_remaining_ticks": 0,
		"dash_direction": Vector2.RIGHT,
		"dodge_remaining_ticks": 0,
		"dash_step": 0.0,
		"attack_target_ui": {},
		"marked_enemy": null,
		"marked_expires_tick": 0,
		"font": null,
	}


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
