extends SceneTree
const Game = preload("res://src/game/game_root.gd")
const Progress = preload("res://src/systems/character_progression.gd")
const Assert := preload("res://tests/helpers/assert.gd")
var errors: Array[String] = []
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var game := Game.new()
	game.save_directory_path = "user://r9-integration-test"
	game.playtest_logging_enabled = false
	game.initialize(PackedStringArray(["--game-flow-smoke"]))
	root.add_child(game)
	await process_frame
	_expect(game.start_new_game("ranger").ok,"new game")
	_expect(game.complete_tutorial().ok,"tutorial")
	_expect(game.current_route == "base","tutorial returns to usable base")
	_expect(game.current_screen.find_child("OpenCharacter",true,false) != null,"growth entry missing")
	_expect(game.open_character().ok,"growth route")
	var old_fingerprint: String = game.application_state.resolved_build_snapshot().build_fingerprint
	_expect(game.change_character_talent("allocate","ranger_steady_string").ok,"spend actual tutorial point")
	var build: Dictionary = game.application_state.resolved_build_snapshot()
	_expect(build.build_fingerprint != old_fingerprint,"talents missing from fingerprint")
	_expect(game.application_state.character_snapshot().points_available == 0,"budget not consumed")
	_expect(not game.change_character_talent("allocate","ranger_long_breath").ok,"overspent talent budget")
	var archive: Dictionary = game.application_state.persistent_payload()
	var before: Dictionary = game.application_state.profile
	archive.profile.character.experience = -1
	_expect(not game.application_state.restore_persistent_payload(archive).ok and game.application_state.profile == before,"invalid XP restore not atomic")
	archive = game.application_state.persistent_payload()
	archive.profile.progression = null
	_expect(not game.application_state.restore_persistent_payload(archive).ok and game.application_state.profile == before,"invalid story progression restore not atomic")
	game.close_adventure_page()
	_expect(game.open_story().ok,"story route")
	var state: Dictionary = game.current_screen.current_state()
	_expect(not state.journal_entries.is_empty(),"opening journal missing")
	var read_id: String = state.journal_entries[0].id
	var xp: int = game.application_state.profile.character.experience
	_expect(game.read_story_entry(read_id).ok,"read entry")
	_expect(not game.read_story_entry("future_fake_entry").ok,"future story falsely unlocked")
	_expect(game.application_state.profile.character.experience == xp,"reading awards combat XP")
	game.close_adventure_page()
	var saved: Dictionary = game.application_state.persistent_payload()
	var restored := Game.ApplicationStateScript.new()
	_expect(restored.restore_persistent_payload(JSON.parse_string(JSON.stringify(saved))).ok,"growth/story persistence")
	_expect(read_id in restored.profile.get("story",{}).get("read_entry_ids",[]),"read status lost")
	_expect(restored.resolved_build_snapshot().get("build_fingerprint","") == build.build_fingerprint,"talent semantics change on load")
	game.open_contract()
	_expect(game.launch_contract({"contract_id":"mainline_01_first_hunt","mode":"Manual","seed":52969,"room_count":1}).ok,"launch talented contract")
	var locked: Dictionary = game.application_state.active_session
	_expect(not game.application_state.change_talent("reset").ok,"contract allowed free respec")
	_expect(game.application_state.active_session == locked,"failed respec changed frozen contract")
	_expect(locked.get("resolved_build",{}).get("build_fingerprint","") == build.get("build_fingerprint",""),"runtime not given selected talent")
	if game.current_route == "arena": game.current_screen.request_abandon()
	await process_frame
	game.free()
	await process_frame
	var trial_state := Game.ApplicationStateScript.new()
	trial_state.start_new_profile("ranger")
	trial_state.complete_tutorial()
	trial_state.select_ranger_build("critical")
	var first_trial: Dictionary = trial_state.run_training_trial()
	var first_fingerprint: String = first_trial.report.build_fingerprint
	trial_state.change_talent("allocate", "ranger_steady_string")
	var second_fingerprint: String = trial_state.resolved_build_snapshot().build_fingerprint
	_expect(first_fingerprint != second_fingerprint, "training ignored talent change")
	_expect(not trial_state.profile.training.reports_by_fingerprint.has(second_fingerprint), "old report leaked into new talent build")
	trial_state.run_training_trial()
	trial_state.change_talent("reset")
	_expect(trial_state.resolved_build_snapshot().build_fingerprint == first_fingerprint, "free respec did not restore build semantics")
	_expect(trial_state.profile.training.reports_by_fingerprint.size() == 2, "training report identity lost after respec")
	for error in errors: printerr(error)
	print("CHARACTER_STORY_INTEGRATION ","PASS" if errors.is_empty() else "FAIL")
	quit(0 if errors.is_empty() else 1)
func _expect(value:bool,message:String)->void: Assert.expect(value, message, errors)
