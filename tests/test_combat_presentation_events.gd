extends SceneTree

const Fixture := preload("res://tests/helpers/talent_runtime_fixture.gd")
const Protocol := preload("res://src/systems/combat_command_protocol.gd")

var fixture := Fixture.new()
const ArenaCombatPresenterScript := preload("res://src/presentation/arena_combat_presenter.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	var session: Dictionary = fixture.start_session([], true)
	var arena = session.arena
	arena.set_process(false)
	session.runtime.set_process(false)
	fixture.configure_target(arena)
	await process_frame

	_test_event_projection(arena, failures)
	_test_actual_motion_projection(arena, failures)
	_test_pause_release_and_audio_projection(arena, failures)
	_test_damage_text_formatting(arena, failures)

	fixture.free_session(session)
	if failures.is_empty():
		print("PASS  test_combat_presentation_events.gd")
		quit(0)
		return
	for failure: String in failures:
		printerr("- %s" % failure)
	quit(1)


func _test_damage_text_formatting(arena: Node, failures: Array[String]) -> void:
	var before: String = arena._semantic_state_hash("float-text")
	var presenter := ArenaCombatPresenterScript.new()
	for pair in [["253.968254", "254"], ["−253.968254", "−254"], ["-253.968254", "-254"],
		["+253.968254", "+254"], ["Dodge", "Dodge"], ["1.25e6", "1.25e6"], ["1.2K", "1.2K"], ["−1.25e6", "−1.25e6"]]:
		_expect(String(presenter.call("_compact_feedback_number", pair[0])) == pair[1], "damage text: wrong draw-only format for %s" % pair[0], failures)
	_expect(arena._semantic_state_hash("float-text") == before, "damage text formatting changed combat authority", failures)


func _test_event_projection(arena: Node, failures: Array[String]) -> void:
	var first = arena.enemies[0]
	var second = arena.enemies[1]
	fixture.advance_to(arena, 12)
	var damage_event: Dictionary = arena.combat_event_stream.emit(arena.sim_tick, "damage_applied", {
		"source_id": "ranger/piercing_arrow",
		"target_id": "enemy/%d" % first.entity_id,
		"target_entity_id": first.entity_id,
		"amount": "1.25e6",
		"contact_point": first.position,
	})
	var hash_before_projection: String = arena._semantic_state_hash("presentation")
	arena.refresh_presentation()
	var hash_after_projection: String = arena._semantic_state_hash("presentation")
	_expect(hash_before_projection == hash_after_projection, "event projection changed authoritative semantic state", failures)
	_expect(arena.presentation.feedback.presentation_event_cursor == int(damage_event.event_id), "presentation cursor did not advance to the consumed event", failures)
	_expect(arena.presentation.animations.enemy_animation.latched_event_id("enemy/%d/hit" % first.entity_id) == "combat:%d" % int(damage_event.event_id), "enemy hit animation did not use the authority event id", failures)
	_expect(_mark_count(arena, "enemy_damage") == 1, "enemy damage did not create exactly one transient mark", failures)
	arena.refresh_presentation()
	_expect(_mark_count(arena, "enemy_damage") == 1, "redraw consumed the same damage event twice", failures)
	var repeated_damage: Dictionary = arena.combat_event_stream.emit(arena.sim_tick, "damage_applied", {
		"source_id": "ranger/piercing_arrow",
		"target_id": "enemy/%d" % first.entity_id,
		"target_entity_id": first.entity_id,
		"amount": "2.50e6",
		"contact_point": first.position + Vector2(1.0, 0.0),
	})
	arena.refresh_presentation()
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
	arena.refresh_presentation()
	_expect(_mark_count(arena, "blocked") == 1 and arena.presentation.feedback.presentation_event_cursor == int(blocked_event.event_id), "blocked result did not create its distinct feedback mark", failures)
	_expect(arena.presentation.animations.enemy_animation.latched_ticks("enemy/%d/hit" % second.entity_id, arena.sim_tick) == -1, "blocked attack fabricated an enemy hit reaction", failures)

	_expect(arena.player_combat_rules.apply_damage(arena.sim_tick, 7.0, "enemy/%d/%s" % [first.entity_id, first.kind_id], first.position).get("accepted", false), "player damage setup was rejected", failures)
	var player_damage_id: int = arena.combat_event_stream.latest_event_id()
	arena.refresh_presentation()
	_expect(arena.presentation.animations.ranger_animation.latched_event_id(arena.presentation.animations.RANGER_EVENT_HIT) == "combat:%d" % player_damage_id, "player hit animation did not use the damage event", failures)
	_expect(_mark_count(arena, "player_damage") == 1, "player damage did not create one reaction mark", failures)
	_test_player_damage_overlay_during_actions(arena, first, failures)

	var action_event: Dictionary = arena.combat_event_stream.emit(arena.sim_tick, "action_accepted", {
		"action_instance_id": 44,
		"actor_id": "ranger",
		"action_id": "piercing_arrow",
		"target_entity_id": first.entity_id,
	})
	arena.refresh_presentation()
	_expect(arena.presentation.animations.ranger_animation.latched_event_id(arena.presentation.animations.RANGER_EVENT_SHOT) == "combat:%d" % int(action_event.event_id), "shoot animation did not latch the accepted action event", failures)

	arena.presentation.feedback.advance_marks(arena.presentation.feedback.COMBAT_FEEDBACK_LIFETIME_SECONDS + 0.01)
	_expect(arena.presentation.feedback.combat_feedback_marks.is_empty(), "transient feedback outlived its bounded presentation window", failures)


func _test_player_damage_overlay_during_actions(arena: Node, target, failures: Array[String]) -> void:
	## A true damage event during Piercing Arrow must leave the authoritative
	## action selected while the independent impact overlay remains visible.
	fixture.wait_for_cast_ready(arena)
	_expect(fixture.cast(arena, "piercing_arrow", target.entity_id).get("accepted", false), "player overlay: real arrow request was rejected", failures)
	_expect(arena.player_combat_rules.apply_damage(arena.sim_tick, 5.0, "enemy/%d/%s" % [target.entity_id, target.kind_id], target.position).get("accepted", false), "player overlay: shooting damage setup was rejected", failures)
	var shooting_damage_id: int = arena.combat_event_stream.latest_event_id()
	arena.refresh_presentation()
	var shoot_frame: Dictionary = arena.presentation.animations.ranger_animation.resolve(arena.presentation.animations.ranger_state(arena.gameplay_snapshot()))
	var shoot_overlay: Dictionary = arena.presentation.animations._player_damage_overlay_state(arena.gameplay_snapshot())
	_expect(String(shoot_frame.get("action", "")) == "shoot", "player overlay: real damage replaced the shooting action", failures)
	_expect(String(shoot_overlay.get("event_id", "")) == "combat:%d" % shooting_damage_id and int(shoot_overlay.get("age_ticks", -1)) == 0, "player overlay: shooting damage did not open the event-bound channel", failures)
	var overlay_before_repeat := shoot_overlay.duplicate(true)
	arena.refresh_presentation()
	_expect(arena.presentation.animations._player_damage_overlay_state(arena.gameplay_snapshot()) == overlay_before_repeat, "player overlay: repeated presentation commit retriggered a damage event", failures)

	## Dash has lower-level movement authority but remains the selected action as
	## well; only the overlay is added on top of it.
	fixture.wait_for_cast_ready(arena)
	_expect(fixture.cast(arena, "dash").get("accepted", false), "player overlay: real dash was rejected", failures)
	_expect(arena.player_combat_rules.apply_damage(arena.sim_tick, 6.0, "enemy/%d/%s" % [target.entity_id, target.kind_id], target.position).get("accepted", false), "player overlay: dash damage setup was rejected", failures)
	var dash_damage_id: int = arena.combat_event_stream.latest_event_id()
	arena.refresh_presentation()
	var dash_frame: Dictionary = arena.presentation.animations.ranger_animation.resolve(arena.presentation.animations.ranger_state(arena.gameplay_snapshot()))
	var dash_overlay: Dictionary = arena.presentation.animations._player_damage_overlay_state(arena.gameplay_snapshot())
	_expect(String(dash_frame.get("action", "")) == "dash", "player overlay: real damage replaced the dash action", failures)
	_expect(String(dash_overlay.get("event_id", "")) == "combat:%d" % dash_damage_id, "player overlay: dash damage did not expose its authority event", failures)

	## The channel closes at a fixed tick boundary and an invulnerable dodge does
	## not invent a damage event, mark, or overlay.
	fixture.advance_to(arena, int(arena.sim_tick) + arena.presentation.animations.PLAYER_DAMAGE_OVERLAY_TICKS)
	_expect(arena.presentation.animations._player_damage_overlay_state(arena.gameplay_snapshot()).is_empty(), "player overlay: damage channel outlived its fixed window", failures)
	arena.presentation.feedback.combat_feedback_marks.clear()
	arena.presentation.animations.ranger_animation.clear_events()
	fixture.wait_for_cast_ready(arena)
	_expect(fixture.cast(arena, "dodge").get("accepted", false), "player overlay: real dodge was rejected", failures)
	var latest_before_avoid: int = arena.combat_event_stream.latest_event_id()
	_expect(not arena.player_combat_rules.apply_damage(arena.sim_tick, 7.0, "enemy/%d/%s" % [target.entity_id, target.kind_id], target.position).get("accepted", false), "player overlay: dodge immunity allowed damage", failures)
	arena.refresh_presentation()
	_expect(arena.combat_event_stream.latest_event_id() == latest_before_avoid and arena.presentation.animations._player_damage_overlay_state(arena.gameplay_snapshot()).is_empty() and _mark_count(arena, "player_damage") == 0, "player overlay: avoided damage fabricated feedback", failures)


func _test_actual_motion_projection(arena: Node, failures: Array[String]) -> void:
	fixture.wait_for_cast_ready(arena)
	fixture.step(arena)
	Input.action_press("move_right")
	_expect(not bool(arena.presentation.animations.ranger_state(arena.gameplay_snapshot()).moving), "held input fabricated visual movement before authority moved the player", failures)
	Input.action_release("move_right")
	var move := Protocol.move(int(arena.sim_tick) + 1, "ranger", int(arena.command_sequence), 1000, 0, 1000)
	arena.command_sequence += 1
	fixture.step(arena, [move])
	_expect(bool(arena.presentation.animations.ranger_state(arena.gameplay_snapshot()).moving), "committed displacement did not drive the walk animation", failures)


func _test_pause_release_and_audio_projection(arena: Node, failures: Array[String]) -> void:
	fixture.wait_for_cast_ready(arena)
	while int(fixture.player(arena).dodge_cooldown_ticks) > 0 or int(fixture.player(arena).dash_cooldown_ticks) > 0:
		fixture.step(arena)
	_expect(fixture.cast(arena, "dash").get("accepted", false), "pause release: real dash was rejected", failures)
	fixture.advance_to(arena, int(arena.sim_tick) + int(fixture.player(arena).dash_remaining_ticks) - 3)
	var buffered: Dictionary = fixture.cast(arena, "dodge")
	_expect(buffered.get("reason", "") == "mobility_buffered", "pause release: real mobility tail did not buffer", failures)
	var target = arena.enemies[0]
	_expect(bool(arena.teleport_actor("enemy/%d" % target.entity_id, arena.player_position + Vector2.LEFT * 120.0).get("ok", false)), "pause release: target placement failed", failures)
	var arrow_receipt: Dictionary = fixture.cast(arena, "piercing_arrow", target.entity_id)
	_expect(arrow_receipt.get("accepted", false), "pause release: live arrow was rejected (%s distance=%s range=%s)" % [str(arrow_receipt), arena.player_position.distance_to(target.position), arena.locked_targeting_distance], failures)
	arena.command_source.attack_requested = true
	arena.command_source.attack_requested_source = "assisted"
	arena.command_source.attack_requested_target_entity_id = target.entity_id
	arena.command_source.dodge_requested = true
	arena.command_source.hunter_mark_requested = true
	arena.command_source.dash_requested = true
	var accepted_before_release: bool = not fixture.player(arena).timeline.active.is_empty()
	arena.release_manual_controls()
	_expect(not arena.command_source.attack_requested and not arena.command_source.dodge_requested and not arena.command_source.hunter_mark_requested and not arena.command_source.dash_requested and fixture.player(arena).mobility_input_buffer.is_empty(), "pause release left ephemeral manual intent queued", failures)
	_expect(accepted_before_release and not fixture.player(arena).timeline.active.is_empty(), "pause release cancelled an already accepted timeline action", failures)
	arena.set_effects_volume(0.2)
	var report: Dictionary = arena.combat_feedback_report()
	_expect(report.get("mark_limit", 0) == arena.presentation.feedback.COMBAT_FEEDBACK_LIMIT, "feedback report lost the presentation bound", failures)
	var audio: Dictionary = report.get("audio", {})
	_expect(absf(float(audio.get("volume", -1.0)) - 0.2) < 0.001, "arena effects volume did not reach event-bound audio", failures)
	arena.set_effects_volume(arena.presentation.feedback.combat_feedback_audio.DEFAULT_VOLUME)


func _mark_count(arena: Node, kind: String) -> int:
	var count := 0
	for mark: Dictionary in arena.presentation.feedback.combat_feedback_marks:
		if String(mark.get("kind", "")) == kind:
			count += 1
	return count


func _first_mark(arena: Node, kind: String) -> Dictionary:
	for mark: Dictionary in arena.presentation.feedback.combat_feedback_marks:
		if String(mark.get("kind", "")) == kind:
			return mark
	return {}


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
