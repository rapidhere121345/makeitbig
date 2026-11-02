class_name AutoSmokeHarness
extends RefCounted

## Drives the deterministic --auto-smoke replay on behalf of GameRoot. This
## harness owns the replay's session flag and stage state and reaches the shell
## through GameRoot's public API.
const SceneRouterScript = preload("res://src/game/scene_router.gd")
const ContractPlanScript = preload("res://src/game/contract_plan.gd")
const EarlyCampaignRegistryScript = preload("res://src/content/early_campaign_registry.gd")
const SaveStoreScript = preload("res://src/persistence/save_store.gd")

const AUTO_SMOKE_WHITE_CORES: Array[String] = [
	"near_enemy_horizon",
	"direct_gait",
	"single_key_execution",
	"short_trace_memory",
]
const AUTO_SMOKE_SEED := 52969
const TIME_SCALE := 20.0
## Mainline contracts the setup settles in memory before the real Boss and Auto runs.
const SETUP_NODE_IDS: Array[String] = [
	"mainline_01_first_hunt",
	"mainline_02_priority_under_pressure",
	"mainline_03_first_elite",
	"mainline_04_hazard_and_forge",
	"mainline_05_growth_gate",
]

## True when the command line passed --auto-smoke.
var session: bool = false
## setup, boss, auto or complete; empty before the replay starts.
var stage: String = ""
var state_hash_output_path: String = ""
var boss_result: Dictionary = {}
## Framework settlements counted so far (Boss, then Auto).
var settlement_count := 0
var previous_time_scale := 1.0
var finished := false

var _root: GameRoot


func _init(root: GameRoot) -> void:
	_root = root


## Reads --state-hash-out=<path>; the last occurrence wins.
func read_state_hash_argument(arguments: PackedStringArray) -> void:
	for argument: String in arguments:
		if argument.begins_with("--state-hash-out="):
			state_hash_output_path = argument.trim_prefix("--state-hash-out=")


## Runs the replay at AutoSmokeHarness.TIME_SCALE and remembers the previous scale.
func accelerate() -> void:
	previous_time_scale = Engine.time_scale
	Engine.time_scale = TIME_SCALE


## Counts a settled arena result and schedules the replay continuation. The stage
## is the one that was current before the settlement.
func on_arena_settled(settled_stage: String, result: Dictionary, settled: Dictionary) -> void:
	if not session or finished:
		return
	if bool(settled.get("ok", false)):
		settlement_count += 1
	_continue_auto_smoke.call_deferred(settled_stage, result.duplicate(true), settled.duplicate(true))


func start() -> void:
	stage = "setup"
	if not _auto_smoke_require_ok("route_title", _root.transition(SceneRouterScript.ROUTE_TITLE)):
		return
	if not _auto_smoke_require_ok("new_profile", _root.start_new_game("ranger")):
		return
	if not _auto_smoke_require_ok("tutorial", _root.complete_tutorial()):
		return
	if not _auto_smoke_require_ok("open_loadout", _root.open_facility(SceneRouterScript.ROUTE_LOADOUT)):
		return
	if not _auto_smoke_require_ok("select_build", _root.request_facility_action(SceneRouterScript.ROUTE_LOADOUT, "select_ranger_build", {"preset_id": "exponential"})):
		return
	if not _auto_smoke_require_ok("leave_loadout", _root.leave_facility()):
		return
	if not _auto_smoke_require_ok("open_training", _root.open_facility(SceneRouterScript.ROUTE_TRAINING)):
		return
	if not _auto_smoke_require_ok("training_trial", _root.request_facility_action(SceneRouterScript.ROUTE_TRAINING, "run_training_trial")):
		return
	if not _auto_smoke_require_ok("leave_training", _root.leave_facility()):
		return

	var setup: Dictionary = _prepare_auto_smoke_mainline()
	if not bool(setup.get("ok", false)):
		_auto_smoke_fail("setup", "%s: %s" % [String(setup.get("step", "mainline")), String(setup.get("error", "unknown_error"))])
		return
	var progress: Dictionary = _root.application_state.campaign_progress_snapshot()
	var completed: Array = progress.get("completed_node_ids", []) if bool(progress.get("ok", false)) else []
	for node_id: String in SETUP_NODE_IDS:
		if node_id not in completed:
			_auto_smoke_fail("setup", "missing completed node %s" % node_id)
			return
	if "threshold_colossus" in completed or "auto_certification" in completed:
		_auto_smoke_fail("setup", "setup illegally completed Boss or Auto")
		return
	if _root.application_state.is_auto_mode_unlocked():
		_auto_smoke_fail("setup", "setup illegally unlocked Auto")
		return

	if not _auto_smoke_require_ok("open_boss_contract", _root.open_contract()):
		return
	stage = "boss"
	var launched: Dictionary = _root.launch_contract({
		"contract_id": "threshold_colossus",
		"mode": "Manual",
		"preset_id": "exponential",
		"seed": AUTO_SMOKE_SEED,
		"room_count": 1,
		"automation_smoke": true,
	})
	if not bool(launched.get("ok", false)):
		_auto_smoke_fail("boss", "launch failed: %s" % String(launched.get("error", "unknown_error")))


func _prepare_auto_smoke_mainline() -> Dictionary:
	var campaign_registry = EarlyCampaignRegistryScript.new()
	var load_errors: Array[String] = campaign_registry.load_campaign()
	if not load_errors.is_empty():
		return {"ok": false, "step": "campaign_load", "error": "; ".join(load_errors)}
	for contract_id: String in SETUP_NODE_IDS:
		var progress: Dictionary = _root.application_state.campaign_progress_snapshot()
		if not bool(progress.get("ok", false)):
			return {"ok": false, "step": contract_id, "error": String(progress.get("error", "campaign_progress_invalid"))}
		var completed: Array = progress.get("completed_node_ids", [])
		var available: Array = progress.get("available_node_ids", [])
		if contract_id not in available or contract_id in completed:
			return {"ok": false, "step": contract_id, "error": "node_not_legally_available"}
		var node: Dictionary = campaign_registry.get_node(contract_id)
		var room_count := maxi(1, (node.get("room_sequence", []) as Array).size())
		var config := {
			"contract_id": contract_id,
			"mode": "Manual",
			"preset_id": "exponential",
			"seed": AUTO_SMOKE_SEED,
			"room_count": room_count,
			"completed_node_ids": completed.duplicate(),
		}
		var planned: Dictionary = ContractPlanScript.build(config)
		if not bool(planned.get("ok", false)):
			return {"ok": false, "step": contract_id, "error": String(planned.get("error", "contract_plan_failed"))}
		config["room_plan"] = (planned.get("plan", {}) as Dictionary).duplicate(true)
		var prepared: Dictionary = _root.application_state.prepare_contract(config)
		if not bool(prepared.get("ok", false)):
			return {"ok": false, "step": contract_id, "error": String(prepared.get("error", "contract_prepare_failed"))}
		var begun: Dictionary = _root.application_state.begin_session()
		if not bool(begun.get("ok", false)):
			return {"ok": false, "step": contract_id, "error": String(begun.get("error", "session_start_failed"))}
		var settled: Dictionary = _root.application_state.complete_session({
			"outcome": "victory",
			"contract_id": contract_id,
			"mode": "Manual",
			"rewards": {"contract_wins_delta": 1},
		})
		if not bool(settled.get("ok", false)):
			return {"ok": false, "step": contract_id, "error": String(settled.get("error", "session_complete_failed"))}
	return {"ok": true}


func _auto_smoke_require_ok(step: String, result: Dictionary) -> bool:
	if bool(result.get("ok", false)):
		return true
	_auto_smoke_fail(stage, "%s failed: %s" % [step, String(result.get("error", "unknown_error"))])
	return false


func _continue_auto_smoke(completed_stage: String, arena_result: Dictionary, settlement: Dictionary) -> void:
	if finished:
		return
	if completed_stage != stage:
		_auto_smoke_fail(completed_stage, "stale settlement while current stage is %s" % stage)
		return
	if not bool(settlement.get("ok", false)):
		_auto_smoke_fail(completed_stage, "framework settlement failed: %s" % String(settlement.get("error", "unknown_error")))
		return
	if _root.current_route != SceneRouterScript.ROUTE_RESULT:
		_auto_smoke_fail(completed_stage, "framework settlement did not enter Result; route=%s" % _root.current_route)
		return
	if String(arena_result.get("outcome", "")) != "victory":
		var reason := String(arena_result.get("error", arena_result.get("report", "non-victory result")))
		_auto_smoke_fail(completed_stage, reason)
		return

	if completed_stage == "boss":
		if settlement_count != 1:
			_auto_smoke_fail("boss", "expected first framework settlement, got %d" % settlement_count)
			return
		var boss_progress: Dictionary = _root.application_state.campaign_progress_snapshot()
		var boss_completed: Array = boss_progress.get("completed_node_ids", []) if bool(boss_progress.get("ok", false)) else []
		var profile: Dictionary = _root.application_state.profile
		var proxy_build: Dictionary = profile.get("proxy_build", {})
		var cores: Array = proxy_build.get("cores", [])
		if cores != AUTO_SMOKE_WHITE_CORES:
			_auto_smoke_fail("boss", "fixed four white cores missing: %s" % [cores])
			return
		if not _root.application_state.is_auto_mode_unlocked():
			_auto_smoke_fail("boss", "Auto was not unlocked by real Boss settlement")
			return
		if "threshold_colossus" not in boss_completed or "auto_certification" in boss_completed:
			_auto_smoke_fail("boss", "campaign progression is invalid after Boss: %s" % [boss_completed])
			return
		if bool((profile.get("progression", {}) as Dictionary).get("early_game_complete", false)):
			_auto_smoke_fail("boss", "Boss settlement completed the early game before Auto")
			return
		boss_result = _root.application_state.last_result.duplicate(true)
		if _root.capture.requested_stage() == "boss":
			# Settled already: photograph Result before leaving it.
			_auto_smoke_capture_stage.call_deferred("boss")
			return
		_auto_smoke_advance_after_boss_result()
		return

	if completed_stage != "auto":
		_auto_smoke_fail(completed_stage, "unexpected completed stage")
		return
	if settlement_count != 2:
		_auto_smoke_fail("auto", "expected two framework settlements, got %d" % settlement_count)
		return
	var final_progress: Dictionary = _root.application_state.campaign_progress_snapshot()
	var final_completed: Array = final_progress.get("completed_node_ids", []) if bool(final_progress.get("ok", false)) else []
	var final_profile: Dictionary = _root.application_state.profile
	var progression: Dictionary = final_profile.get("progression", {})
	if not bool(progression.get("early_game_complete", false)) or "auto_certification" not in final_completed:
		_auto_smoke_fail("auto", "real Auto settlement did not complete the early game")
		return
	var final_result: Dictionary = _root.application_state.last_result
	if String(final_result.get("contract_id", "")) != "auto_certification" or String(final_result.get("mode", "")) != "Auto":
		_auto_smoke_fail("auto", "Result lost Auto contract identity")
		return
	if String(final_result.get("outcome", "")) != "final_victory":
		_auto_smoke_fail("auto", "real Auto graduation did not produce final_victory")
		return
	if _root.capture.requested_stage() == "auto":
		# Settle first, photograph Result, and only then open the Ending.
		_auto_smoke_capture_stage.call_deferred("auto")
		return
	_auto_smoke_finish_after_auto_result()


## The rest of the Boss stage: leave Result, reopen the board, launch real Auto.
func _auto_smoke_advance_after_boss_result() -> void:
	if not _auto_smoke_require_ok("leave_boss_result", _root.leave_result()):
		return
	if not _auto_smoke_require_ok("open_auto_contract", _root.open_contract()):
		return
	stage = "auto"
	var launched: Dictionary = _root.launch_contract({
		"contract_id": "auto_certification",
		"mode": "Auto",
		"preset_id": "exponential",
		"seed": AUTO_SMOKE_SEED,
		"room_count": 1,
		"automation_smoke": true,
	})
	if not bool(launched.get("ok", false)):
		_auto_smoke_fail("auto", "launch failed: %s" % String(launched.get("error", "unknown_error")))


## Photographs one settled stage and resumes the replay. A failed capture fails the
## smoke too: a replay that cannot produce its own evidence must not pass.
func _auto_smoke_capture_stage(stage: String) -> void:
	var captured: Dictionary = await _root.capture.settlement_stage(stage)
	if not bool(captured.get("ok", false)):
		_root.capture.fail_line(
			String(captured.get("error", "unknown_error")),
			String(captured.get("detail", "")),
			_root.CAPTURE_STAGE_ROUTE,
			_root.current_route,
			stage,
			String(_root.capture.request.get("capture_path", ""))
		)
		_auto_smoke_fail(stage, "settlement capture failed: %s: %s" % [String(captured.get("error", "unknown_error")), String(captured.get("detail", ""))])
		return
	if stage == "boss":
		_auto_smoke_advance_after_boss_result()
		return
	_auto_smoke_finish_after_auto_result()


## The Auto finale, re-checking the settlement identity first so a disturbed
## settlement fails loudly instead of hashing a different run.
func _auto_smoke_finish_after_auto_result() -> void:
	var final_result: Dictionary = _root.application_state.last_result
	if (
		String(final_result.get("contract_id", "")) != "auto_certification"
		or String(final_result.get("mode", "")) != "Auto"
		or String(final_result.get("outcome", "")) != "final_victory"
	):
		_auto_smoke_fail("auto", "Auto settlement identity changed before the replay finished")
		return
	if not _auto_smoke_require_ok("open_ending", _root.open_ending()):
		return
	if _root.current_route != SceneRouterScript.ROUTE_ENDING:
		_auto_smoke_fail("auto", "final victory did not enter Ending; route=%s" % _root.current_route)
		return
	var state_hash := _auto_smoke_semantic_hash(final_result)
	if state_hash.is_empty():
		_auto_smoke_fail("finalize", "could not calculate semantic hash")
		return
	if not _write_auto_smoke_state_hash(state_hash):
		_auto_smoke_fail("finalize", "could not write semantic hash")
		return
	finished = true
	stage = "complete"
	print("AUTO_SMOKE_PASS framework_settlements=%d route=%s boss_ticks=%d auto_ticks=%d early_game_complete=true state_hash=%s" % [
		settlement_count,
		_root.current_route,
		int(boss_result.get("ticks", 0)),
		int(final_result.get("ticks", 0)),
		state_hash,
	])
	Engine.time_scale = previous_time_scale
	_root.get_tree().quit(0)


func _auto_smoke_semantic_hash(final_result: Dictionary) -> String:
	var profile: Dictionary = _root.application_state.profile
	var progression: Dictionary = profile.get("progression", {})
	var proxy_build: Dictionary = profile.get("proxy_build", {})
	var semantic := {
		"protocol": "wp4-a-real-arena-v1",
		"route": _root.current_route,
		"framework_settlements": settlement_count,
		"completed_node_ids": (progression.get("completed_node_ids", []) as Array).duplicate(),
		"proxy_unlocked": bool(progression.get("proxy_unlocked", false)),
		"proxy_cores": (proxy_build.get("cores", []) as Array).duplicate(),
		"proxy_inventory_ids": proxy_inventory_ids(profile),
		"early_game_complete": bool(progression.get("early_game_complete", false)),
		"boss": result_summary(boss_result),
		"auto": result_summary(final_result),
	}
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	if context.update(SaveStoreScript.canonical_json(semantic).to_utf8_buffer()) != OK:
		return ""
	return context.finish().hex_encode()


func result_summary(result: Dictionary) -> Dictionary:
	var proxy_drops: Array[String] = []
	for drop_value in (result.get("proxy_component_drops", []) as Array if result.get("proxy_component_drops", null) is Array else []):
		if drop_value is Dictionary:
			proxy_drops.append(String((drop_value as Dictionary).get("id", "")))
	proxy_drops.sort()
	return {
		"outcome": String(result.get("outcome", "")),
		"contract_id": String(result.get("contract_id", "")),
		"mode": String(result.get("mode", "")),
		"room_count": int(result.get("room_count", 0)),
		"rooms_completed": int(result.get("rooms_completed", 0)),
		"ticks": int(result.get("ticks", 0)),
		"casts": int(result.get("casts", 0)),
		"defeated": int(result.get("defeated", 0)),
		"proxy_component_drop_ids": proxy_drops,
	}


func proxy_inventory_ids(profile: Dictionary) -> Array[String]:
	var inventory_value: Variant = profile.get("inventory", {})
	var inventory: Dictionary = inventory_value if inventory_value is Dictionary else {}
	var components_value: Variant = inventory.get("proxy_components", [])
	var ids: Array[String] = []
	if components_value is Array:
		for component_value in (components_value as Array):
			if component_value is Dictionary:
				ids.append(String((component_value as Dictionary).get("id", "")))
	ids.sort()
	return ids


func _write_auto_smoke_state_hash(state_hash: String) -> bool:
	if state_hash_output_path.is_empty():
		return true
	var output_path: String = state_hash_output_path
	if not output_path.is_absolute_path() and not output_path.begins_with("user://") and not output_path.begins_with("res://"):
		output_path = ProjectSettings.globalize_path("res://" + output_path)
	var output_directory := ProjectSettings.globalize_path(output_path).get_base_dir()
	if not output_directory.is_empty() and DirAccess.make_dir_recursive_absolute(output_directory) != OK:
		return false
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(state_hash + "\n")
	file.close()
	return true


func _auto_smoke_fail(stage: String, reason: String) -> void:
	if finished:
		return
	finished = true
	printerr("AUTO_SMOKE_FAIL stage=%s reason=%s route=%s framework_settlements=%d" % [stage, reason, _root.current_route, settlement_count])
	Engine.time_scale = previous_time_scale
	_root.request_exit(1, "auto_smoke_fail:%s:%s" % [stage, reason])
