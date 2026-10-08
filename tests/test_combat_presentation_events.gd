extends SceneTree

const MainScript := preload("res://src/game/main.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	var arena = MainScript.new()
	arena.embedded_session = true
	root.add_child(arena)
	await process_frame
	arena.in_arena = true
	arena.framework_room = {
		"room_id": "test.combat.presentation",
		"layout_id": "rectangle_arena",
		"objective_id": "clear",
		"hazard_ids": [],
		"enemy_ids": ["melee_pursuer", "fan_ranged"],
		"elite_rule_ids": [],
		"boss_id": "",
		"drop_tags": [],
	}
	arena._spawn_wave()

	_test_event_projection(arena, failures)
	_test_actual_motion_projection(arena, failures)
	_test_pause_release_and_audio_projection(arena, failures)
	_test_damage_text_formatting(arena, failures)

	root.remove_child(arena)
	arena.free()
	if failures.is_empty():
		print("PASS  test_combat_presentation_events.gd")
		quit(0)
		return
	for failure: String in failures:
		printerr("- %s" % failure)
	quit(1)


func _test_damage_text_formatting(arena: Node, failures: Array[String]) -> void:
	var before: String = arena._semantic_state_hash("float-text")
	for pair in [["253.968254", "254"], ["−253.968254", "−254"], ["-253.968254", "-254"],
		["+253.968254", "+254"], ["闪避", "闪避"], ["1.25e6", "1.25e6"], ["1.2K", "1.2K"], ["−1.25e6", "−1.25e6"]]:
		_expect(arena._compact_feedback_number(pair[0]) == pair[1], "damage text: wrong draw-only format for %s" % pair[0], failures)
	_expect(arena._semantic_state_hash("float-text") == before, "damage text formatting changed combat authority", failures)


func _test_event_projection(arena: Node, failures: Array[String]) -> void:
	var first = arena.enemies[0]
	var second = arena.enemies[1]
	arena.sim_tick = 12
	var damage_event: Dictionary = arena.combat_event_stream.emit(arena.sim_tick, "damage_applied", {
		"source_id": "ranger/piercing_arrow",
		"target_id": "enemy/%d" % first.entity_id,
		"target_entity_id": first.entity_id,
		"amount": "1.25e6",
		"contact_point": first.position,
	})
	var hash_before_projection: String = arena._semantic_state_hash("presentation")
	arena._consume_combat_presentation_events()
	var hash_after_projection: String = arena._semantic_state_hash("presentation")
	_expect(hash_before_projection == hash_after_projection, "event projection changed authoritative semantic state", failures)
	_expect(arena.presentation_event_cursor == int(damage_event.event_id), "presentation cursor did not advance to the consumed event", failures)
	_expect(arena.enemy_animation.latched_event_id("enemy/%d/hit" % first.entity_id) == "combat:%d" % int(damage_event.event_id), "enemy hit animation did not use the authority event id", failures)
	_expect(_mark_count(arena, "enemy_damage") == 1, "enemy damage did not create exactly one transient mark", failures)
	arena._consume_combat_presentation_events()
	_expect(_mark_count(arena, "enemy_damage") == 1, "redraw consumed the same damage event twice", failures)
	var repeated_damage: Dictionary = arena.combat_event_stream.emit(arena.sim_tick, "damage_applied", {
		"source_id": "ranger/piercing_arrow",
		"target_id": "enemy/%d" % first.entity_id,
		"target_entity_id": first.entity_id,
		"amount": "2.50e6",
		"contact_point": first.position + Vector2(1.0, 0.0),
	})
	arena._consume_combat_presentation_events()
	_expect(_mark_count(arena, "enemy_damage") == 1, "rapid damage on one target stacked unreadable duplicate marks", failures)
	var repeated_mark := _first_mark(arena, "enemy_damage")
	_expect(int(repeated_mark.get("event_id", 0)) == int(repeated_damage.event_id) and String(repeated_mark.get("text", "")) == "2.50e6", "coalesced damage mark did not show the latest authority event", failures)

	var blocked_event: Dictionary = arena.combat_event_stream.emit(arena.sim_tick, "attack_resolved", {
		"action_instance_id": 9,
		"source_id": "ranger/piercing_arrow",
		"target_entity_id": second.entity_id,
		"outcome": "blocked",
		"contact_point": second.position,
		"barrier_id": "periodic_barrier",
	})
	arena._consume_combat_presentation_events()
	_expect(_mark_count(arena, "blocked") == 1 and arena.presentation_event_cursor == int(blocked_event.event_id), "blocked result did not create its distinct feedback mark", failures)
	_expect(arena.enemy_animation.latched_ticks("enemy/%d/hit" % second.entity_id, arena.sim_tick) == -1, "blocked attack fabricated an enemy hit reaction", failures)

	arena.player_health = 100.0
	_expect(arena._damage_player(7.0, "enemy/%d/%s" % [first.entity_id, first.kind_id]), "player damage setup was rejected", failures)
	var player_damage_id: int = arena.combat_event_stream.latest_event_id()
	arena._consume_combat_presentation_events()
	_expect(arena.ranger_animation.latched_event_id(arena.RANGER_EVENT_HIT) == "combat:%d" % player_damage_id, "player hit animation did not use the damage event", failures)
	_expect(_mark_count(arena, "player_damage") == 1, "player damage did not create one reaction mark", failures)
	_test_player_damage_overlay_during_actions(arena, first, failures)

	var action_event: Dictionary = arena.combat_event_stream.emit(arena.sim_tick, "action_accepted", {
		"action_instance_id": 44,
		"actor_id": "ranger",
		"action_id": "piercing_arrow",
		"target_entity_id": first.entity_id,
	})
	arena._consume_combat_presentation_events()
	_expect(arena.ranger_animation.latched_event_id(arena.RANGER_EVENT_SHOT) == "combat:%d" % int(action_event.event_id), "shoot animation did not latch the accepted action event", failures)

	arena._advance_combat_feedback(arena.COMBAT_FEEDBACK_LIFETIME_SECONDS + 0.01)
	_expect(arena.combat_feedback_marks.is_empty(), "transient feedback outlived its bounded presentation window", failures)


func _test_player_damage_overlay_during_actions(arena: Node, target, failures: Array[String]) -> void:
	## A true damage event during Piercing Arrow must leave the authoritative
	## action selected while the independent impact overlay remains visible.
	arena.sim_tick = 40
	arena.player_health = 100.0
	arena.player_action_timeline.reset()
	arena.player_action_timeline.request_attack(arena.sim_tick, target.entity_id, Vector2.RIGHT)
	_expect(arena._damage_player(5.0, "enemy/%d/%s" % [target.entity_id, target.kind_id]), "player overlay: shooting damage setup was rejected", failures)
	var shooting_damage_id: int = arena.combat_event_stream.latest_event_id()
	arena._presentation_commit()
	var shoot_frame: Dictionary = arena.ranger_animation.resolve(arena._ranger_animation_state())
	var shoot_overlay: Dictionary = arena._player_damage_overlay_state()
	_expect(String(shoot_frame.get("action", "")) == "shoot", "player overlay: real damage replaced the shooting action", failures)
	_expect(String(shoot_overlay.get("event_id", "")) == "combat:%d" % shooting_damage_id and int(shoot_overlay.get("age_ticks", -1)) == 0, "player overlay: shooting damage did not open the event-bound channel", failures)
	var overlay_before_repeat := shoot_overlay.duplicate(true)
	arena._presentation_commit()
	_expect(arena._player_damage_overlay_state() == overlay_before_repeat, "player overlay: repeated presentation commit retriggered a damage event", failures)

	## Dash has lower-level movement authority but remains the selected action as
	## well; only the overlay is added on top of it.
	arena.sim_tick = 56
	arena.player_action_timeline.reset()
	arena.dash_started_tick = arena.sim_tick
	arena.dash_remaining_ticks = arena.DASH_DURATION_TICKS
	arena.player_health = 100.0
	_expect(arena._damage_player(6.0, "enemy/%d/%s" % [target.entity_id, target.kind_id]), "player overlay: dash damage setup was rejected", failures)
	var dash_damage_id: int = arena.combat_event_stream.latest_event_id()
	arena._presentation_commit()
	var dash_frame: Dictionary = arena.ranger_animation.resolve(arena._ranger_animation_state())
	var dash_overlay: Dictionary = arena._player_damage_overlay_state()
	_expect(String(dash_frame.get("action", "")) == "dash", "player overlay: real damage replaced the dash action", failures)
	_expect(String(dash_overlay.get("event_id", "")) == "combat:%d" % dash_damage_id, "player overlay: dash damage did not expose its authority event", failures)

	## The channel closes at a fixed tick boundary and an invulnerable dodge does
	## not invent a damage event, mark, or overlay.
	arena.sim_tick += arena.PLAYER_DAMAGE_OVERLAY_TICKS
	_expect(arena._player_damage_overlay_state().is_empty(), "player overlay: damage channel outlived its fixed window", failures)
	arena.combat_feedback_marks.clear()
	arena.ranger_animation.clear_events()
	arena.dash_remaining_ticks = 0
	arena.dodge_remaining_ticks = arena.DODGE_DURATION_TICKS
	var latest_before_avoid: int = arena.combat_event_stream.latest_event_id()
	_expect(not arena._damage_player(7.0, "enemy/%d/%s" % [target.entity_id, target.kind_id]), "player overlay: dodge immunity allowed damage", failures)
	arena._presentation_commit()
	_expect(arena.combat_event_stream.latest_event_id() == latest_before_avoid and arena._player_damage_overlay_state().is_empty() and _mark_count(arena, "player_damage") == 0, "player overlay: avoided damage fabricated feedback", failures)


func _test_actual_motion_projection(arena: Node, failures: Array[String]) -> void:
	arena.player_last_displacement = Vector2.ZERO
	Input.action_press("move_right")
	_expect(not arena._player_is_visually_moving(), "held input fabricated visual movement before authority moved the player", failures)
	Input.action_release("move_right")
	arena.player_last_displacement = Vector2(1.0, 0.0)
	_expect(arena._player_is_visually_moving(), "committed displacement did not drive the walk animation", failures)


func _test_pause_release_and_audio_projection(arena: Node, failures: Array[String]) -> void:
	arena.attack_requested = true
	arena.attack_requested_source = "assisted"
	arena.attack_requested_target_entity_id = 1
	arena.dodge_requested = true
	arena.hunter_mark_requested = true
	arena.dash_requested = true
	arena.mobility_input_buffer = {"kind": "dodge", "expires_tick": 99}
	arena.player_action_timeline.reset()
	arena.player_action_timeline.request_attack(arena.sim_tick, 1, Vector2.RIGHT)
	var accepted_before_release: bool = not arena.player_action_timeline.snapshot().get("active", {}).is_empty()
	arena.release_manual_controls()
	_expect(not arena.attack_requested and not arena.dodge_requested and not arena.hunter_mark_requested and not arena.dash_requested and arena.mobility_input_buffer.is_empty(), "pause release left ephemeral manual intent queued", failures)
	_expect(accepted_before_release and not arena.player_action_timeline.snapshot().get("active", {}).is_empty(), "pause release cancelled an already accepted timeline action", failures)
	arena.set_effects_volume(0.2)
	var report: Dictionary = arena.combat_feedback_report()
	_expect(report.get("mark_limit", 0) == arena.COMBAT_FEEDBACK_LIMIT, "feedback report lost the presentation bound", failures)
	var audio: Dictionary = report.get("audio", {})
	_expect(absf(float(audio.get("volume", -1.0)) - 0.2) < 0.001, "arena effects volume did not reach event-bound audio", failures)
	arena.set_effects_volume(arena.COMBAT_FEEDBACK_DEFAULT_VOLUME)


func _mark_count(arena: Node, kind: String) -> int:
	var count := 0
	for mark: Dictionary in arena.combat_feedback_marks:
		if String(mark.get("kind", "")) == kind:
			count += 1
	return count


func _first_mark(arena: Node, kind: String) -> Dictionary:
	for mark: Dictionary in arena.combat_feedback_marks:
		if String(mark.get("kind", "")) == kind:
			return mark
	return {}


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
