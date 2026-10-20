extends SceneTree

const State = preload("res://src/game/application_state.gd")
const CombatRoomRuntimeScript = preload("res://src/game/combat_room_runtime.gd")
const CombatFixture = preload("res://tests/helpers/talent_runtime_fixture.gd")
const SkillRules = preload("res://src/systems/ranger_skill_rules.gd")
const Encounter = preload("res://src/game/encounter_director.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_training_and_persistence()
	_test_campaign_is_not_evidence()
	for outcome in ["miss", "blocked", "damage", "wrong_fingerprint"]:
		_test_actual_projectile_evidence(outcome)
	await process_frame
	for failure in failures: printerr(failure)
	print("STORY_EVIDENCE ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)

func _fresh():
	var state := State.new()
	state.start_new_profile("ranger")
	state.complete_tutorial()
	return state

func _has_stage(state, stage: int) -> bool:
	for entry in state.story_snapshot().journal_entries:
		if int(entry.stage) == stage: return true
	return false

func _test_training_and_persistence() -> void:
	for kind in ["convergent", "critical", "exponential"]:
		var state = _fresh()
		state.select_ranger_build(kind)
		_expect(not _has_stage(state, 3) and not _has_stage(state, 6), "equipping a build fabricated a story")
		state.run_training_trial()
		_expect(_has_stage(state, 3), "actual training did not unlock its reaction")
		_expect(_has_stage(state, 6) == (kind == "exponential"), "growth story ignored observed result")
		_expect(state.story_progress_snapshot().first_growth_state == kind, "first result was not retained")
		var discovery_count: int = state.profile.discoveries.size()
		state.run_training_trial()
		_expect(state.profile.discoveries.size() == discovery_count, "repeat training duplicated story evidence")
		for entry in state.story_snapshot().journal_entries:
			_expect(state.mark_story_read(entry.id).ok, "evidence-unlocked entry cannot be read")
		var restored := State.new()
		var reload_result: Dictionary = restored.restore_persistent_payload(JSON.parse_string(JSON.stringify(state.persistent_payload())))
		_expect(reload_result.ok, "observed/read story does not reload")
		_expect(restored.story_snapshot() == state.story_snapshot(), "observed story/read state changed on reload")
		state.select_ranger_build("exponential" if kind != "exponential" else "convergent")
		state.run_training_trial()
		_expect(state.story_progress_snapshot().first_growth_state == kind, "later training rewrote the first event")

func _test_campaign_is_not_evidence() -> void:
	var state = _fresh()
	var nodes := ["mainline_01_first_hunt", "mainline_02_priority_under_pressure", "mainline_03_first_elite", "mainline_04_hazard_and_forge", "mainline_05_growth_gate"]
	# Synthetic victories deliberately contain no combat evidence. Settlement is
	# still responsible for real first-clear drops, XP and route progression.
	for node in nodes:
		_expect(state.prepare_contract({"contract_id":node,"mode":"Manual","seed":52969,"room_count":1}).ok, "campaign fixture prepare")
		state.begin_session()
		state.complete_session({"outcome":"victory","rewards":{}})
		_expect(not _has_stage(state, 3) and not _has_stage(state, 6), "completion alone fabricated growth")
	_expect(_has_stage(state, 2), "settled first-clear equipment did not unlock discovery")
	_expect(state.story_snapshot().current_objective.campaign_node == "threshold_colossus", "optional training blocks main route")

func _test_actual_projectile_evidence(outcome: String) -> void:
	var state = _fresh()
	state.select_ranger_build("exponential")
	_expect(state.prepare_contract({"contract_id":"mainline_01_first_hunt","mode":"Manual","seed":52969,"room_count":1,"resolved_build":state.resolved_build_snapshot()}).ok, "real evidence contract prepare")
	_expect(state.begin_session().ok, "real evidence session begin")
	var frozen: Dictionary = state.active_session.resolved_build
	var runtime := CombatRoomRuntimeScript.new()
	root.add_child(runtime)
	var room_definition: Dictionary = {"room_id":"story.evidence","layout_id":"rectangle_arena","objective_id":"clear","enemy_ids":["melee_pursuer"],"hazard_ids":[],"elite_rule_ids":[],"boss_id":"","drop_tags":[]}
	if outcome == "blocked":
		room_definition.objective_id = "hunt_elite"
		room_definition.elite_rule_ids = ["periodic_barrier"]
	var started: Dictionary = runtime.start_session({
		"contract_id":"mainline_01_first_hunt","mode":"Manual","seed":52969,"presentation_enabled":false,
		"room":room_definition,
		"framework_context":{"active_build":state.profile.active_build,"resolved_build":frozen},
	})
	_expect(started.ok, "actual evidence arena launch")
	var arena = runtime.get("room_instance")
	var fixture := CombatFixture.new()
	var target = fixture.configure_target(arena)
	if outcome == "blocked":
		# Cast in the open interval and release one tick before the next real
		# barrier window. Projectile travel starts on the following tick.
		fixture.advance_to(arena, Encounter.ELITE_BARRIER_PERIOD_TICKS - SkillRules.PIERCING_ARROW_WINDUP_TICKS - 2)
		_expect(not arena.encounter_director.is_target_blocked(target), "blocked fixture did not cast in the barrier's open interval")
	## "miss" aims into open space north of the player: the released line holds
	## no target regardless of how the melee AI walks after the release.
	var aim := Vector2.ZERO
	if outcome == "miss":
		aim = Vector2(0, -1)
	_expect(fixture.release_arrow(arena, target, aim), "actual evidence arrow release")
	if outcome == "miss":
		## Park the target far south through the registry: the melee AI chases
		## the player (the arrow origin), so the body must be moved off any
		## approach line the released arrow could still cross.
		_expect(bool(arena.teleport_actor("enemy/%d" % target.entity_id, arena._arena_rect().get_center() + Vector2(120.0, 200.0)).get("ok", false)), "miss fixture could not park the target clear of the line")
	if outcome == "blocked":
		_expect(arena.sim_tick == Encounter.ELITE_BARRIER_PERIOD_TICKS - 1 and not arena.encounter_director.is_target_blocked(target), "blocked fixture did not release before the barrier transition")
	fixture.advance_projectiles(arena)
	if outcome == "blocked":
		var contact: Dictionary = arena.combat_event_stream.latest("attack_resolved")
		_expect(contact.get("outcome", "") == "blocked" and contact.get("barrier_id", "") == "periodic_barrier" and int(contact.get("tick", -1)) >= Encounter.ELITE_BARRIER_PERIOD_TICKS and arena.encounter_director.is_target_blocked(target), "actual projectile contact did not meet the live periodic barrier")
		print("STORY_BARRIER_TRACE release_tick=", Encounter.ELITE_BARRIER_PERIOD_TICKS - 1, " contact_tick=", contact.get("tick", -1), " outcome=", contact.get("outcome", ""))
	var room: Dictionary = runtime.build_result("defeat")
	_expect(int(room.casts) == 1, "actual projectile was not cast")
	_expect(int(room.arrow_hits) == (1 if outcome in ["damage", "wrong_fingerprint"] else 0), "miss/barrier fabricated a hit: outcome=%s hits=%s" % [outcome, str(room.arrow_hits)])
	if outcome == "wrong_fingerprint": room.build_fingerprint = "different-build"
	state.complete_session({"outcome":"defeat","room_results":[room],"rewards":{}})
	_expect(_has_stage(state, 6) == (outcome == "damage"), "story accepted invalid evidence or lost actual contact")
	_expect(state.profile.character.experience == 60, "observing growth on defeat granted completion XP")
	runtime.free()

func _expect(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
