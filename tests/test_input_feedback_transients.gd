extends SceneTree
## Presentation-only input feedback regressions: a blank world click explains
## itself after release and expires on the combat clock, unavailable Q/E
## presses explain without enqueueing commands, the assisted-aim indicator
## snapshot resolves the actual target, and none of the new UI-only state
## reaches the semantic hash.

const MainScript := preload("res://src/game/main.gd")
const Protocol := preload("res://src/systems/combat_command_protocol.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var arena = MainScript.new()
	arena.embedded_session = true
	root.add_child(arena)
	await process_frame
	arena.selected_mode = "Manual"
	arena.locked_targeting_distance = 100.0

	_test_blank_click_feedback_after_release(arena)
	_test_successful_intent_clears_feedback(arena)
	_test_feedback_expiry_and_reset(arena)
	_test_unavailable_skill_feedback_without_commands(arena)
	_test_assisted_rejection_cue(arena)
	_test_pointer_out_of_range_notice(arena)
	_test_assisted_indicator_snapshot_target(arena)
	_test_feedback_never_reaches_semantic_hash(arena)

	_release_input_actions()
	root.remove_child(arena)
	arena.free()
	if failures.is_empty():
		print("PASS  tests/test_input_feedback_transients.gd")
		quit(0)
		return
	printerr("%d input feedback check(s) failed:" % failures.size())
	for failure in failures:
		printerr("- %s" % failure)
	quit(1)


func _test_blank_click_feedback_after_release(arena: Node) -> void:
	_configure_enemies(arena)
	var blank: Vector2 = arena.player_position + Vector2(0.0, 90.0)
	var blank_screen: Vector2 = _gameplay_to_screen(arena, blank)
	arena._capture_manual_attack_event(_mouse_attack_event(blank_screen, true), false)
	_expect(_piercing_cast(arena._manual_commands()).is_empty(),
		"blank click: the press already queued a piercing cast")
	_expect(arena._active_input_feedback() == "点击敌人射击 · 或按住空格辅助瞄准",
		"blank click: the press did not show the actionable hint immediately")
	arena._capture_manual_attack_event(_mouse_attack_event(blank_screen, false), false)
	var transient: String = arena._active_input_feedback()
	_expect(arena._active_input_feedback() == "点击敌人射击 · 或按住空格辅助瞄准",
		"blank click: a normal release erased the hint before its duration")
	arena._update_hud()
	var notice := arena.hud_panel.find_child("InputFeedbackLabel", true, false) as Label
	_expect(notice != null and notice.visible and notice.text == transient,
		"blank click: the visible HUD input notice did not show the hint after release")
	_expect(_piercing_cast(arena._manual_commands()).is_empty() and int(arena.shots) == 0,
		"blank click: the hint accompanied or replaced a real shot")


func _test_successful_intent_clears_feedback(arena: Node) -> void:
	_configure_enemies(arena)
	arena._show_input_feedback("点击敌人射击 · 或按住空格辅助瞄准")
	var target = arena.enemies[0]
	target.position = arena.player_position + Vector2(70.0, 0.0)
	var target_screen := _gameplay_to_screen(arena, target.position + Vector2(0.0, -22.0))
	arena._capture_manual_attack_event(_mouse_attack_event(target_screen, true), false)
	_expect(arena._active_input_feedback().is_empty(),
		"successful pointer lock kept the stale blank-click hint")
	arena._capture_manual_attack_event(_mouse_attack_event(target_screen, false), false)

	arena._show_input_feedback("点击敌人射击 · 或按住空格辅助瞄准")
	arena._queue_assisted_attack()
	_expect(not _piercing_cast(arena._manual_commands()).is_empty(),
		"assisted attempt in range did not queue its cast")
	_expect(arena._active_input_feedback().is_empty(),
		"successful assisted intent kept the stale hint")
	arena._update_hud()
	var notice := arena.hud_panel.find_child("InputFeedbackLabel", true, false) as Label
	_expect(notice != null and not notice.visible,
		"successful assisted intent left the visible HUD notice on screen")


func _test_feedback_expiry_and_reset(arena: Node) -> void:
	var hint: String = "点击敌人射击 · 或按住空格辅助瞄准"
	_configure_enemies(arena)
	arena._show_input_feedback(hint)
	_expect(arena._active_input_feedback() == hint, "the hint was not on screen before its expiry window")
	arena.sim_tick += int(arena.INPUT_FEEDBACK_DURATION_TICKS)
	arena.sim_tick -= 1
	_expect(arena._active_input_feedback() == hint, "the hint vanished one tick before its expiry")
	arena.sim_tick += 1
	_expect(arena._active_input_feedback().is_empty(),
		"transient feedback survived its expiry tick")
	arena._update_hud()
	var notice := arena.hud_panel.find_child("InputFeedbackLabel", true, false) as Label
	_expect(notice != null and not notice.visible, "expired hint stayed on the visible HUD notice")
	arena._show_input_feedback(hint)
	arena._spawn_wave()
	_expect(arena._active_input_feedback().is_empty(),
		"a room wave reset kept the previous room's input hint")
	arena._reset_manual_attack_intent()
	_expect(arena._active_input_feedback().is_empty(),
		"the manual intent reset kept transient input feedback alive")


func _test_unavailable_skill_feedback_without_commands(arena: Node) -> void:
	_configure_enemies(arena)
	arena.framework_active_build = {"skills": ["piercing_arrow", "", ""]}
	var commands_before: int = arena._manual_commands().size()
	arena._unhandled_input(_key_event(KEY_Q, true))
	_expect(not bool(arena.hunter_mark_requested), "unequipped Q still requested the mark")
	_expect(arena._active_input_feedback() == "猎人印记未装配在本场构筑 · 暂无法施放",
		"unequipped Q produced no truthful feedback")
	arena._unhandled_input(_key_event(KEY_E, true))
	_expect(not bool(arena.dash_requested) and int(arena.dash_remaining_ticks) == 0,
		"unequipped E still dashed")
	_expect(arena._active_input_feedback() == "突袭未装配在本场构筑 · 暂无法施放",
		"unequipped E produced no truthful feedback")
	_expect(arena._manual_commands().size() == commands_before,
		"unavailable skill presses enqueued combat commands")
	arena.framework_active_build = {"skills": ["piercing_arrow", "hunter_mark", "dash"]}
	arena._unhandled_input(_key_event(KEY_Q, true))
	_expect(bool(arena.hunter_mark_requested), "equipped Q was gated away")
	_expect(arena._active_input_feedback().is_empty(),
		"equipped Q left the stale unavailable-skill hint on screen")
	arena.hunter_mark_requested = false


func _test_assisted_rejection_cue(arena: Node) -> void:
	_configure_enemies(arena)
	arena.locked_targeting_distance = 100.0
	var far = arena.enemies[0]
	far.position = arena.player_position + Vector2(260.0, 0.0)
	arena.enemies[1].position = arena.player_position + Vector2(300.0, 40.0)
	arena._queue_assisted_attack()
	## Out-of-range assists queue at their target; the authority rejects them at
	## cast time. Targeting rules are unchanged — assert the queue, then execute.
	var queued: Dictionary = _piercing_cast(arena._manual_commands())
	_expect(not queued.is_empty() and int(queued.get("target_entity_id", 0)) == int(far.entity_id),
		"out-of-range assisted attempt did not queue at its visible target")
	arena._execute_cast_command(queued)
	_expect(arena._active_input_feedback() == "目标在射程外 · 靠近后再射",
		"out-of-range assisted attempt produced no actionable cue")
	_expect(int(arena.shots) == 0 and arena.projectiles.is_empty(),
		"the out-of-range cue accompanied a real shot")
	_configure_enemies(arena)
	for enemy in arena.enemies:
		enemy.health = 0.0
	arena._queue_assisted_attack()
	_piercing_cast(arena._manual_commands())
	_expect(arena._active_input_feedback() == "暂无目标 · 靠近敌人后按空格",
		"assisted attempt without any living target produced no cue")


func _test_pointer_out_of_range_notice(arena: Node) -> void:
	_configure_enemies(arena)
	var far = arena.enemies[0]
	far.position = arena.player_position + Vector2(260.0, 0.0)
	arena.enemies[1].position = arena.player_position + Vector2(300.0, 40.0)
	var far_screen := _gameplay_to_screen(arena, far.position + Vector2(0.0, -22.0))
	arena._capture_manual_attack_event(_mouse_attack_event(far_screen, true), false)
	_expect(arena._active_input_feedback() == "目标在射程外 · 靠近后再射",
		"pointer out-of-range press produced no actionable notice")
	arena._capture_manual_attack_event(_mouse_attack_event(far_screen, false), false)
	_expect(arena._active_input_feedback() == "目标在射程外 · 靠近后再射",
		"pointer out-of-range notice did not stay legible after release")
	_expect(int(arena.shots) == 0 and arena.projectiles.is_empty(),
		"the pointer out-of-range notice accompanied a real shot")


func _test_assisted_indicator_snapshot_target(arena: Node) -> void:
	_configure_enemies(arena)
	arena.locked_targeting_distance = 100.0
	var near = arena.enemies[0]
	var far = arena.enemies[1]
	near.position = arena.player_position + Vector2(70.0, 0.0)
	far.position = arena.player_position + Vector2(120.0, 0.0)
	var state: Dictionary = arena._attack_target_ui_state()
	_expect(String(state.get("source", "")) == arena.ATTACK_SOURCE_ASSISTED
		and int(state.get("target_entity_id", 0)) == int(near.entity_id),
		"assisted snapshot: assist did not choose the nearest living enemy")
	_expect(float(state.get("target_radius", 0.0)) > 0.0
		and (state.get("target_anchor", Vector2.ZERO) as Vector2).distance_to(near.position + Vector2(0.0, -22.0)) < 0.01,
		"assisted snapshot: the indicator ignored the combat aim anchor")
	arena.marked_entity_id = int(far.entity_id)
	arena.hunter_mark_expires_tick = int(arena.sim_tick) + 100
	far.position = arena.player_position + Vector2(90.0, 0.0)
	var marked_state: Dictionary = arena._attack_target_ui_state()
	_expect(int(marked_state.get("target_entity_id", 0)) == int(far.entity_id),
		"assisted snapshot: a live mark lost priority over plain nearest")
	arena.marked_entity_id = 0
	arena.hunter_mark_expires_tick = 0


func _test_feedback_never_reaches_semantic_hash(arena: Node) -> void:
	_configure_enemies(arena)
	var baseline: String = arena._semantic_state_hash("skills")
	arena._show_input_feedback("点击敌人射击 · 或按住空格辅助瞄准")
	_expect(arena._semantic_state_hash("skills") == baseline,
		"semantic hash consumed transient input feedback")
	arena._reset_manual_attack_intent()
	_expect(arena._active_input_feedback().is_empty(),
		"the semantic-hash reset left transient input feedback alive")


func _configure_enemies(arena: Node) -> void:
	_release_input_actions()
	arena._reset_manual_attack_intent()
	arena.player_action_timeline.reset()
	arena.combat_event_stream.reset()
	arena.framework_active_build = {"skills": ["piercing_arrow", "hunter_mark", "dash"]}
	arena.embedded_session = true
	arena.in_arena = true
	arena.battle_over = false
	arena.framework_room = {
		"room_id": "test.input.feedback",
		"layout_id": "rectangle_arena",
		"objective_id": "clear",
		"hazard_ids": [],
		"enemy_ids": ["melee_pursuer", "fan_ranged"],
		"elite_rule_ids": [],
		"boss_id": "",
		"drop_tags": [],
	}
	arena._spawn_wave()
	arena.player_position = arena._arena_rect().get_center()


func _gameplay_to_screen(arena: Node, gameplay_point: Vector2) -> Vector2:
	arena.world_view.begin_frame(Rect2(Vector2.ZERO, arena.get_viewport_rect().size), arena.player_position, arena._arena_rect())
	return arena.world_view.gameplay_to_screen(gameplay_point)


func _mouse_attack_event(position: Vector2, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = position
	event.global_position = position
	event.pressed = pressed
	return event


func _key_event(physical_keycode: Key, pressed: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = physical_keycode
	event.pressed = pressed
	return event


func _piercing_cast(commands: Array) -> Dictionary:
	for command: Dictionary in commands:
		if String(command.get("kind", "")) == Protocol.KIND_CAST and String(command.get("ability_id", "")) == Protocol.ABILITY_PIERCING_ARROW:
			return command
	return {}


func _release_input_actions() -> void:
	for action in [&"move_left", &"move_right", &"move_up", &"move_down", &"attack", &"dodge", &"skill_2", &"skill_3"]:
		Input.action_release(action)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
