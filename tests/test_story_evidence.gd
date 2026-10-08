extends SceneTree

const State = preload("res://src/game/application_state.gd")
const Adapter = preload("res://src/game/legacy_arena_adapter.gd")
const CombatFixture = preload("res://tests/helpers/talent_runtime_fixture.gd")
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
	var adapter := Adapter.new()
	root.add_child(adapter)
	var started: Dictionary = adapter.start_session({
		"contract_id":"mainline_01_first_hunt","mode":"Manual","seed":52969,"presentation_enabled":false,
		"room":{"room_id":"story.evidence","layout_id":"rectangle_arena","objective_id":"clear","enemy_ids":["melee_pursuer"],"hazard_ids":[],"elite_rule_ids":[],"boss_id":"","drop_tags":[]},
		"framework_context":{"active_build":state.profile.active_build,"resolved_build":frozen},
	})
	_expect(started.ok, "actual evidence arena launch")
	var arena = adapter.get("_legacy")
	var fixture := CombatFixture.new()
	var target = fixture.configure_target(arena)
	_expect(fixture.release_arrow(arena, target), "actual evidence arrow release")
	if outcome == "miss": target.position += Vector2(0, 100)
	if outcome == "blocked":
		arena.elite_entity_id = target.entity_id
		arena.elite_barrier_active = true
	fixture.advance_projectiles(arena)
	var room: Dictionary = adapter._build_result("defeat")
	_expect(int(room.casts) == 1, "actual projectile was not cast")
	_expect(int(room.arrow_hits) == (1 if outcome in ["damage", "wrong_fingerprint"] else 0), "miss/barrier fabricated a hit")
	if outcome == "wrong_fingerprint": room.build_fingerprint = "different-build"
	state.complete_session({"outcome":"defeat","room_results":[room],"rewards":{}})
	_expect(_has_stage(state, 6) == (outcome == "damage"), "story accepted invalid evidence or lost actual contact")
	_expect(state.profile.character.experience == 60, "observing growth on defeat granted completion XP")
	adapter.free()

func _expect(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
