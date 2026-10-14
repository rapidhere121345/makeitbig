extends SceneTree

const Runtime := preload("res://src/game/combat_room_runtime.gd")
const ItemRegistry := preload("res://src/content/early_item_registry.gd")
const BuildResolver := preload("res://src/systems/build_resolver.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var registry := ItemRegistry.new()
	_expect(registry.load_all().is_empty(), "mounted presentation registry failed")
	var build: Dictionary = BuildResolver.new(registry).resolve_fixture("calibration_convergent")
	var runtimes: Array = []
	for enabled in [true, false]:
		var runtime := Runtime.new()
		root.add_child(runtime)
		var result := runtime.start_session({
			"contract_id": "test.presentation.boundary", "mode": "Manual", "seed": 52969,
			"presentation_enabled": enabled,
			"room": {"room_id": "test.presentation.boundary", "layout_id": "rectangle_arena", "objective_id": "clear", "hazard_ids": [], "enemy_ids": ["melee_pursuer"], "elite_rule_ids": [], "boss_id": "", "drop_tags": []},
			"framework_context": {"active_build": {}, "resolved_build": build},
		})
		_expect(result.ok, "real mounted presentation fixture failed: " + str(result))
		if not result.ok:
			runtime.free()
			quit(1)
			return
		runtime.set_process(false)
		runtime.room_instance.set_process(false)
		runtimes.append(runtime)
	var visible = runtimes[0].room_instance
	var hidden = runtimes[1].room_instance
	await process_frame
	_expect(visible.presentation.sort_report().binding_mode == "mounted" and hidden.presentation.sort_report().binding_mode == "mounted", "visible/off fixtures did not use mounted production controller binding")
	_expect(visible.scene_runtime.presenter.sort_root.visible and not hidden.scene_runtime.presenter.sort_root.visible, "off mode did not hide native drawing layers")
	_expect(visible.presentation.hud.visible and hidden.presentation.hud.visible and is_zero_approx(hidden.presentation.hud.modulate.a), "off mode removed HUD input participation")
	for arena in [visible, hidden]:
		arena.selected_mode = "Manual"
		arena.in_arena = true
		arena.locked_targeting_distance = 500.0
		arena.framework_room = {
			"room_id": "test.presentation.boundary", "layout_id": "rectangle_arena",
			"objective_id": "clear", "hazard_ids": [],
			"enemy_ids": ["melee_pursuer"], "elite_rule_ids": [],
			"boss_id": "", "drop_tags": [],
		}
		_expect(arena._spawn_wave(), "fixture failed to spawn")
		_expect(bool(arena.teleport_actor("ranger", arena._arena_rect().get_center()).get("ok", false)), "fixture failed to place player")
		var enemy = arena.enemies[0]
		_expect(bool(arena.teleport_actor("enemy/%d" % enemy.entity_id, arena.player_position + Vector2(100.0, 0.0)).get("ok", false)), "fixture failed to place target")
		enemy.health = 1.0e12
		enemy.maximum_health = enemy.health

	var authority_hash: String = visible._semantic_state_hash("boundary")
	var snapshot: Dictionary = visible.gameplay_snapshot()
	var original: Vector2 = visible.enemies[0].position
	snapshot.enemies[0].position += Vector2(400.0, 300.0)
	snapshot.enemies[0].target_shape["test_mutation"] = true
	snapshot["player_position"] = Vector2.ZERO
	snapshot["boss_damage"].magnitude += 900.0
	_expect(visible.enemies[0].position == original and not visible.enemies[0].target_shape.has("test_mutation"), "presentation snapshot retained a live enemy reference")
	_expect(visible._semantic_state_hash("boundary") == authority_hash, "detached snapshot mutation reached gameplay authority")

	var view = visible.presentation.world_view
	view.begin_frame(Rect2(Vector2.ZERO, visible.get_viewport_rect().size), visible.player_position, visible._arena_rect())
	var point: Vector2 = view.gameplay_to_screen(original + Vector2(0.0, -22.0))
	# Identical physical press/release trajectory must mean the same entity even
	# when every renderer is disabled. A quick release preserves the pending edge.
	for arena in [visible, hidden]:
		for pressed in [true, false]:
			var event := InputEventMouseButton.new()
			event.button_index = MOUSE_BUTTON_LEFT
			event.position = point
			event.pressed = pressed
			arena.input_adapter.capture_attack_event(event, false, arena.gameplay_snapshot())
		_expect(arena.command_source.attack_requested_target_entity_id == 1, "physical pointing lost its stable entity id")

	Input.action_press("move_right")
	for index in 30:
		if index == 6:
			Input.action_release("move_right")
		for arena in [visible, hidden]:
			arena._simulate_tick()
		visible.refresh_presentation(1.0 / 144.0)
		_expect(visible._semantic_state_hash("boundary") == hidden._semantic_state_hash("boundary"), "drawing changed gameplay at fixed tick %d" % visible.sim_tick)
	Input.action_release("move_right")
	_expect(visible.shots == 1 and visible.arrow_hits == 1, "input trajectory did not retain one resolved cast")

	# Prove Main's motor wiring cannot invent a later tick to bypass the registry.
	Input.action_press("move_right")
	for arena in [visible, hidden]:
		arena._simulate_tick()
	Input.action_release("move_right")
	_expect(int(visible.actor_registry.actor("ranger").last_motor_tick) == visible.sim_tick, "fixture did not commit movement at the current simulation tick")
	var before_tick: int = visible.sim_tick
	var before_position: Vector2 = visible.actor_registry.actor("ranger").feet_position
	var before_hash: String = visible._semantic_state_hash("boundary")
	var duplicate: Dictionary = visible._commit_actor_move("ranger", Vector2(40.0, 0.0))
	_expect(not bool(duplicate.get("ok", true)) and duplicate.get("error") == "non_monotonic_motor_tick", "same-tick movement was accepted through Main")
	_expect(visible.sim_tick == before_tick and visible.actor_registry.actor("ranger").feet_position == before_position and visible._semantic_state_hash("boundary") == before_hash, "rejected movement changed a tick, actor or replay state")
	visible.simulation_world.step()
	var next: Dictionary = visible._commit_actor_move("ranger", Vector2(4.0, 0.0))
	_expect(bool(next.get("ok", false)) and int(next.get("tick", -1)) == visible.sim_tick, "real SimulationWorld advancement did not permit the next movement")

	for runtime in runtimes:
		var domain: WorldPresenter = runtime.scene_runtime.presenter
		runtime.scene_runtime.unmount()
		_expect(domain.actor_ids().is_empty(), "mounted visible/off teardown leaked actor views")
		runtime.free()
	await process_frame
	if failures.is_empty():
		print("PASS test_combat_presentation_boundary.gd")
		quit(0)
		return
	for failure: String in failures:
		printerr("- %s" % failure)
	quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
