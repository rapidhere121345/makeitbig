extends SceneTree
## Presentation-only input feedback regressions: a blank world click explains
## itself after release and expires on the combat clock, unavailable Q/E
## presses explain without enqueueing commands, the assisted-aim indicator
## snapshot resolves the actual target, and none of the new UI-only state
## reaches the semantic hash.

const PlayerFixture := preload("res://tests/helpers/player_domain_fixture.gd")
const Protocol := preload("res://src/systems/combat_command_protocol.gd")

var failures: Array[String] = []
var fixture := PlayerFixture.new()


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var session := fixture.mount(_room(), fixture.build({"d": 100.0}), true)
	var arena = session.arena
	await process_frame

	_test_blank_click_feedback_after_release(arena)
	_test_successful_intent_clears_feedback(arena)
	_test_feedback_expiry_and_reset(arena)
	_test_unavailable_skill_feedback_without_commands(arena)
	_test_assisted_rejection_cue(arena)
	_test_pointer_out_of_range_notice(arena)
	_test_assisted_indicator_snapshot_target(arena)
	_test_feedback_never_reaches_semantic_hash(arena)

	_release_input_actions()
	fixture.free_session(session)
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
	arena.input_adapter.capture_attack_event(_mouse_attack_event(blank_screen, true), false, arena.gameplay_snapshot())
	_expect(_piercing_cast(arena.input_adapter.collect_commands(arena.gameplay_snapshot())).is_empty(),
		"blank click: the press already queued a piercing cast")
	_expect(arena.presentation.feedback.active_input_feedback(arena.sim_tick) == "Click an enemy to shoot · Or hold Space for aim assist",
		"blank click: the press did not show the actionable hint immediately")
	arena.input_adapter.capture_attack_event(_mouse_attack_event(blank_screen, false), false, arena.gameplay_snapshot())
	var transient: String = arena.presentation.feedback.active_input_feedback(arena.sim_tick)
	_expect(arena.presentation.feedback.active_input_feedback(arena.sim_tick) == "Click an enemy to shoot · Or hold Space for aim assist",
		"blank click: a normal release erased the hint before its duration")
	arena.refresh_presentation()
	var notice := arena.presentation.hud.find_child("InputFeedbackLabel", true, false) as Label
	_expect(notice != null and notice.visible and notice.text == transient,
		"blank click: the visible HUD input notice did not show the hint after release")
	_expect(_piercing_cast(arena.input_adapter.collect_commands(arena.gameplay_snapshot())).is_empty() and int(arena.shots) == 0,
		"blank click: the hint accompanied or replaced a real shot")


func _test_successful_intent_clears_feedback(arena: Node) -> void:
	_configure_enemies(arena)
	arena.presentation.feedback.show_input_feedback("Click an enemy to shoot · Or hold Space for aim assist", arena.sim_tick)
	var target = arena.enemies[0]
	_place(arena, "enemy/%d" % target.entity_id, arena.player_position + Vector2(70.0, 0.0))
	var target_screen := _gameplay_to_screen(arena, target.position + Vector2(0.0, -22.0))
	arena.input_adapter.capture_attack_event(_mouse_attack_event(target_screen, true), false, arena.gameplay_snapshot())
	_expect(arena.presentation.feedback.active_input_feedback(arena.sim_tick).is_empty(),
		"successful pointer lock kept the stale blank-click hint")
	arena.input_adapter.capture_attack_event(_mouse_attack_event(target_screen, false), false, arena.gameplay_snapshot())

	arena.presentation.feedback.show_input_feedback("Click an enemy to shoot · Or hold Space for aim assist", arena.sim_tick)
	arena.input_adapter.request_assisted_attack()
	_expect(not _piercing_cast(arena.input_adapter.collect_commands(arena.gameplay_snapshot())).is_empty(),
		"assisted attempt in range did not queue its cast")
	_expect(arena.presentation.feedback.active_input_feedback(arena.sim_tick).is_empty(),
		"successful assisted intent kept the stale hint")
	arena.refresh_presentation()
	var notice := arena.presentation.hud.find_child("InputFeedbackLabel", true, false) as Label
	_expect(notice != null and not notice.visible,
		"successful assisted intent left the visible HUD notice on screen")


func _test_feedback_expiry_and_reset(arena: Node) -> void:
	var hint: String = "Click an enemy to shoot · Or hold Space for aim assist"
	_configure_enemies(arena)
	arena.presentation.feedback.show_input_feedback(hint, arena.sim_tick)
	_expect(arena.presentation.feedback.active_input_feedback(arena.sim_tick) == hint, "the hint was not on screen before its expiry window")
	var expiry_tick: int = arena.sim_tick + int(arena.presentation.feedback.INPUT_FEEDBACK_DURATION_TICKS)
	fixture.advance_to(arena, expiry_tick - 1)
	_expect(arena.presentation.feedback.active_input_feedback(arena.sim_tick) == hint, "the hint vanished one tick before its expiry")
	fixture.step(arena)
	_expect(arena.presentation.feedback.active_input_feedback(arena.sim_tick).is_empty(),
		"transient feedback survived its expiry tick")
	arena.refresh_presentation()
	var notice := arena.presentation.hud.find_child("InputFeedbackLabel", true, false) as Label
	_expect(notice != null and not notice.visible, "expired hint stayed on the visible HUD notice")
	arena.presentation.feedback.show_input_feedback(hint, arena.sim_tick)
	_configure_enemies(arena)
	_expect(arena.presentation.feedback.active_input_feedback(arena.sim_tick).is_empty(),
		"a room wave reset kept the previous room's input hint")
	arena.release_manual_controls()
	_expect(arena.presentation.feedback.active_input_feedback(arena.sim_tick).is_empty(),
		"the manual intent reset kept transient input feedback alive")


func _test_unavailable_skill_feedback_without_commands(arena: Node) -> void:
	_configure_enemies(arena, ["piercing_arrow", "", ""])
	var commands_before: int = arena.input_adapter.collect_commands(arena.gameplay_snapshot()).size()
	arena._unhandled_input(_key_event(KEY_Q, true))
	_expect(not bool(arena.command_source.hunter_mark_requested), "unequipped Q still requested the mark")
	_expect(arena.presentation.feedback.active_input_feedback(arena.sim_tick) == "Hunter's Mark is not equipped in this build · Cannot Cast Yet",
		"unequipped Q produced no truthful feedback")
	arena._unhandled_input(_key_event(KEY_E, true))
	_expect(not bool(arena.command_source.dash_requested) and int(fixture.player(arena).dash_remaining_ticks) == 0,
		"unequipped E still dashed")
	_expect(arena.presentation.feedback.active_input_feedback(arena.sim_tick) == "Dash is not equipped in this build · Cannot Cast Yet",
		"unequipped E produced no truthful feedback")
	_expect(arena.input_adapter.collect_commands(arena.gameplay_snapshot()).size() == commands_before,
		"unavailable skill presses enqueued combat commands")
	var stale_hint: String = arena.presentation.feedback.active_input_feedback(arena.sim_tick)
	_configure_enemies(arena)
	arena.presentation.feedback.show_input_feedback(stale_hint, arena.sim_tick)
	arena._unhandled_input(_key_event(KEY_Q, true))
	_expect(bool(arena.command_source.hunter_mark_requested), "equipped Q was gated away")
	_expect(arena.presentation.feedback.active_input_feedback(arena.sim_tick).is_empty(),
		"equipped Q left the stale unavailable-skill hint on screen")
	arena.release_manual_controls()


func _test_assisted_rejection_cue(arena: Node) -> void:
	_configure_enemies(arena)
	var far = arena.enemies[0]
	_place(arena, "enemy/%d" % far.entity_id, arena.player_position + Vector2(260.0, 0.0))
	_place(arena, "enemy/%d" % arena.enemies[1].entity_id, arena.player_position + Vector2(300.0, 40.0))
	arena.input_adapter.request_assisted_attack()
	## Out-of-range assists queue at their target; the authority rejects them at
	## cast time. Targeting rules are unchanged — assert the queue, then execute.
	var queued: Dictionary = _piercing_cast(arena.input_adapter.collect_commands(arena.gameplay_snapshot()))
	_expect(not queued.is_empty() and int(queued.get("target_entity_id", 0)) == int(far.entity_id),
		"out-of-range assisted attempt did not queue at its visible target")
	var receipt: Dictionary = arena.request_player_cast(String(queued.ability_id), int(queued.target_entity_id),
		Vector2(float(queued.get("direction_x_milli", 0)), float(queued.get("direction_y_milli", 0))).normalized(), arena.ATTACK_SOURCE_ASSISTED)
	_expect(not bool(receipt.get("accepted", false)) and String(receipt.get("reason", "")) == "target_out_of_range",
		"out-of-range assisted attempt was not rejected by the player domain")
	_expect(arena.presentation.feedback.active_input_feedback(arena.sim_tick) == "Target out of range · Move closer to shoot",
		"out-of-range assisted attempt produced no actionable cue")
	_expect(int(arena.shots) == 0 and arena.projectiles.is_empty(),
		"the out-of-range cue accompanied a real shot")
	_configure_enemies(arena)
	for enemy in arena.enemies:
		enemy.health = 0.0
	arena.input_adapter.request_assisted_attack()
	_piercing_cast(arena.input_adapter.collect_commands(arena.gameplay_snapshot()))
	_expect(arena.presentation.feedback.active_input_feedback(arena.sim_tick) == "No target · Move closer to an enemy, then press Space",
		"assisted attempt without any living target produced no cue")


func _test_pointer_out_of_range_notice(arena: Node) -> void:
	_configure_enemies(arena)
	var far = arena.enemies[0]
	_place(arena, "enemy/%d" % far.entity_id, arena.player_position + Vector2(260.0, 0.0))
	_place(arena, "enemy/%d" % arena.enemies[1].entity_id, arena.player_position + Vector2(300.0, 40.0))
	var far_screen := _gameplay_to_screen(arena, far.position + Vector2(0.0, -22.0))
	arena.input_adapter.capture_attack_event(_mouse_attack_event(far_screen, true), false, arena.gameplay_snapshot())
	_expect(arena.presentation.feedback.active_input_feedback(arena.sim_tick) == "Target out of range · Move closer to shoot",
		"pointer out-of-range press produced no actionable notice")
	arena.input_adapter.capture_attack_event(_mouse_attack_event(far_screen, false), false, arena.gameplay_snapshot())
	_expect(arena.presentation.feedback.active_input_feedback(arena.sim_tick) == "Target out of range · Move closer to shoot",
		"pointer out-of-range notice did not stay legible after release")
	_expect(int(arena.shots) == 0 and arena.projectiles.is_empty(),
		"the pointer out-of-range notice accompanied a real shot")


func _test_assisted_indicator_snapshot_target(arena: Node) -> void:
	_configure_enemies(arena)
	var near = arena.enemies[0]
	var far = arena.enemies[1]
	_place(arena, "enemy/%d" % near.entity_id, arena.player_position + Vector2(70.0, 0.0))
	_place(arena, "enemy/%d" % far.entity_id, arena.player_position + Vector2(120.0, 0.0))
	var state: Dictionary = arena.presentation.frame_builder.attack_target(arena.gameplay_snapshot(), arena.input_adapter.view_state(arena.gameplay_snapshot()))
	_expect(String(state.get("source", "")) == arena.ATTACK_SOURCE_ASSISTED
		and int(state.get("target_entity_id", 0)) == int(near.entity_id),
		"assisted snapshot: assist did not choose the nearest living enemy")
	_expect(float(state.get("target_radius", 0.0)) > 0.0
		and (state.get("target_anchor", Vector2.ZERO) as Vector2).distance_to(near.position + Vector2(0.0, -22.0)) < 0.01,
		"assisted snapshot: the indicator ignored the combat aim anchor")
	var marked: Dictionary = fixture.cast(arena, "hunter_mark", int(far.entity_id))
	_expect(bool(marked.get("accepted", false)) and int(fixture.player(arena).marked_entity_id) == int(far.entity_id),
		"assisted snapshot: the domain did not establish the requested live mark")
	_place(arena, "enemy/%d" % far.entity_id, arena.player_position + Vector2(90.0, 0.0))
	var marked_state: Dictionary = arena.presentation.frame_builder.attack_target(arena.gameplay_snapshot(), arena.input_adapter.view_state(arena.gameplay_snapshot()))
	_expect(int(marked_state.get("target_entity_id", 0)) == int(far.entity_id),
		"assisted snapshot: a live mark lost priority over plain nearest")
	fixture.advance_to(arena, int(fixture.player(arena).hunter_mark_expires_tick))
	_expect(int(fixture.player(arena).marked_entity_id) == 0, "assisted snapshot: the real mark did not expire")


func _test_feedback_never_reaches_semantic_hash(arena: Node) -> void:
	_configure_enemies(arena)
	var baseline: String = arena._semantic_state_hash("skills")
	arena.presentation.feedback.show_input_feedback("Click an enemy to shoot · Or hold Space for aim assist", arena.sim_tick)
	_expect(arena._semantic_state_hash("skills") == baseline,
		"semantic hash consumed transient input feedback")
	arena.release_manual_controls()
	_expect(arena.presentation.feedback.active_input_feedback(arena.sim_tick).is_empty(),
		"the semantic-hash reset left transient input feedback alive")


func _configure_enemies(arena: Node, skills: Array = ["piercing_arrow", "hunter_mark", "dash"]) -> void:
	_release_input_actions()
	fixture.reset(arena, _room(), fixture.build({"d": 100.0}), skills)
	fixture.drive(arena)
	_expect(bool(_place(arena, "ranger", Vector2(880.0, 360.0)).get("ok", false)),
		"input feedback fixture: the legal registry player placement failed")


## This eastern lane leaves the exact +260 and +(300,40) range probes clear
## of whole scenery. Every setup still passes through production validation.
func _place(arena: Node, actor_id: String, position: Vector2) -> Dictionary:
	var receipt: Dictionary = arena.teleport_actor(actor_id, position)
	_expect(bool(receipt.get("ok", false)), "input feedback fixture: %s at %s rejected: %s" % [actor_id, position, receipt])
	return receipt


func _room() -> Dictionary:
	return {
		"room_id": "test.input.feedback",
		"layout_id": "rectangle_arena",
		"objective_id": "clear",
		"hazard_ids": [],
		"enemy_ids": ["melee_pursuer", "fan_ranged"],
		"elite_rule_ids": [],
		"boss_id": "",
		"drop_tags": [],
	}


func _gameplay_to_screen(arena: Node, gameplay_point: Vector2) -> Vector2:
	arena.presentation.world_view.begin_frame(Rect2(Vector2.ZERO, arena.get_viewport_rect().size), arena.player_position, arena._arena_rect())
	return arena.presentation.world_view.gameplay_to_screen(gameplay_point)


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
