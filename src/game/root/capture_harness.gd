class_name CaptureHarness
extends RefCounted

## Capture and evidence harness extracted from GameRoot. It validates capture
## requests, prepares routes, and writes settlement evidence, reaching the
## presentation and replay state through the untyped owner reference.
const SceneRouterScript = preload("res://src/game/scene_router.gd")
const SaveStoreScript = preload("res://src/persistence/save_store.gd")

## Routes the harness can prepare. Settlement routes stay absent on purpose: they
## are played, never prepared, so such a request has to fail loudly.
const CAPTURE_ROUTES: Array[String] = [
	"title", "tutorial", "base",
	"loadout", "forge", "training", "proxy", "immortality", "research",
	"contract",
]
## Opt-in settlement evidence: each stage names one real --auto-smoke settlement,
## and nothing is injected to reach it.
const CAPTURE_STAGES: Array[String] = ["boss", "auto"]
const CAPTURE_EVIDENCE_PROTOCOL: String = "mib-settlement-capture-v1"
const CAPTURE_EVIDENCE_SUFFIX: String = ".json"

var _root


func _init(root) -> void:
	_root = root


## Pure command-line contract for the capture harness. Read-only: it never moves
## the route or starts the simulation, so a command line can be checked first.
func capture_request_report(arguments: PackedStringArray) -> Dictionary:
	var capture_paths: Array[String] = _capture_argument_values(arguments, "--capture=")
	var capture_routes: Array[String] = _capture_argument_values(arguments, "--capture-route=")
	var capture_stages: Array[String] = _capture_argument_values(arguments, "--capture-stage=")
	var report := {
		"ok": true,
		"error": "",
		"detail": "",
		"capture_path": "",
		"capture_route": "",
		"capture_stage": "",
		"auto_smoke": arguments.has("--auto-smoke"),
		"presentation_off": arguments.has("--presentation-off"),
	}
	for entry: Array in [["--capture", capture_paths], ["--capture-route", capture_routes], ["--capture-stage", capture_stages]]:
		var flag := String(entry[0])
		var values: Array = entry[1]
		if values.size() > 1:
			return _capture_request_error(report, "conflicting_capture_flag", "%s was given %d times with different values: %s" % [flag, values.size(), str(values)])
		if values.size() == 1 and String(values[0]).strip_edges().is_empty():
			return _capture_request_error(report, "empty_capture_value", "%s needs a value" % flag)
	report["capture_path"] = capture_paths[0] if capture_paths.size() == 1 else ""
	report["capture_route"] = capture_routes[0] if capture_routes.size() == 1 else ""
	report["capture_stage"] = capture_stages[0] if capture_stages.size() == 1 else ""
	var capture_path := String(report["capture_path"])
	var capture_route := String(report["capture_route"])
	var capture_stage := String(report["capture_stage"])
	var auto_smoke := bool(report["auto_smoke"])
	if not capture_route.is_empty() and capture_route not in CAPTURE_ROUTES:
		return _capture_request_error(report, "unsupported_capture_route", "--capture-route=%s is not supported; supported routes: %s. A settlement cannot be prepared, only played: use --auto-smoke with --capture-stage=boss|auto." % [capture_route, ", ".join(PackedStringArray(CAPTURE_ROUTES))])
	if not capture_stage.is_empty() and capture_stage not in CAPTURE_STAGES:
		return _capture_request_error(report, "unsupported_capture_stage", "--capture-stage=%s is not supported; supported stages: %s, each naming one real settlement of the --auto-smoke replay." % [capture_stage, ", ".join(PackedStringArray(CAPTURE_STAGES))])
	if not capture_stage.is_empty() and not capture_route.is_empty():
		return _capture_request_error(report, "capture_route_conflict", "--capture-route prepares a screen by itself while --capture-stage waits for a real settlement; they cannot be combined.")
	if auto_smoke and not capture_route.is_empty():
		return _capture_request_error(report, "auto_smoke_rejects_capture_route", "--auto-smoke drives its own replay and cannot be combined with --capture-route; ask for --capture-stage=boss|auto instead.")
	if auto_smoke and not capture_path.is_empty() and capture_stage.is_empty():
		return _capture_request_error(report, "auto_smoke_requires_capture_stage", "--auto-smoke with --capture would photograph whatever frame the replay happens to be on; ask for --capture-stage=boss|auto instead.")
	if not capture_stage.is_empty():
		if not auto_smoke:
			return _capture_request_error(report, "capture_stage_requires_auto_smoke", "--capture-stage=%s photographs a real settlement, which only --auto-smoke produces." % capture_stage)
		if capture_path.is_empty():
			return _capture_request_error(report, "capture_stage_requires_capture_path", "--capture-stage=%s needs an explicit --capture=<fresh png path>." % capture_stage)
		if bool(report["presentation_off"]):
			return _capture_request_error(report, "capture_stage_rejects_presentation_off", "--presentation-off cannot produce settlement evidence; the presentation layer must stay on.")
	return report


## Unique values for one capture flag, in command-line order. Repeating a flag with
## the same value stays harmless; different values are a conflict the caller sees.
func _capture_argument_values(arguments: PackedStringArray, prefix: String) -> Array[String]:
	var values: Array[String] = []
	for argument: String in arguments:
		if not argument.begins_with(prefix):
			continue
		var value := argument.trim_prefix(prefix)
		if value not in values:
			values.append(value)
	return values


func _capture_request_error(report: Dictionary, error_code: String, detail: String) -> Dictionary:
	report["ok"] = false
	report["error"] = error_code
	report["detail"] = detail
	return report


## Read-only environment gate: a headless display server or a presentation-disabled
## run cannot draw a frame that proves anything, so both refuse instead of passing.
func capture_environment_report() -> Dictionary:
	var display := DisplayServer.get_name()
	var base := {"display": display, "presentation_enabled": _root._presentation_enabled}
	if display.to_lower().contains("headless"):
		base["ok"] = false
		base["error"] = "headless_display"
		base["detail"] = "the headless display server cannot draw a frame that proves GPU output"
		return base
	if not _root._presentation_enabled:
		base["ok"] = false
		base["error"] = "presentation_disabled"
		base["detail"] = "--presentation-off runs cannot produce visible evidence"
		return base
	base["ok"] = true
	base["error"] = ""
	base["detail"] = ""
	return base


## Settlement evidence must be fresh: an existing PNG or sidecar is refused.
func capture_evidence_target_available(path: String) -> Dictionary:
	if path.strip_edges().is_empty():
		return _capture_refusal("empty_capture_path", "a settlement capture needs an explicit --capture=<path>")
	var absolute_path := _globalize_capture_path(path)
	if absolute_path.get_file().is_empty() or DirAccess.dir_exists_absolute(absolute_path):
		return _capture_refusal("invalid_capture_path", "%s does not name a file" % path)
	var evidence_path := absolute_path + CAPTURE_EVIDENCE_SUFFIX
	if FileAccess.file_exists(absolute_path):
		return _capture_refusal("capture_path_not_fresh", "%s already exists; settlement evidence must be written to a fresh path" % absolute_path)
	if FileAccess.file_exists(evidence_path):
		return _capture_refusal("capture_path_not_fresh", "%s already exists; settlement evidence must be written to a fresh path" % evidence_path)
	return {"ok": true, "error": "", "detail": "", "path": absolute_path, "evidence_path": evidence_path}


## Prepares the requested route and reports exactly where the harness ended up. An
## unreachable request is a mismatch, never a soft landing on another screen.
func prepare_capture_route(route: String) -> Dictionary:
	if route == SceneRouterScript.ROUTE_TITLE:
		if _root.current_route == SceneRouterScript.ROUTE_BASE:
			_root.return_to_title()
		elif _root.current_route == SceneRouterScript.ROUTE_TUTORIAL:
			_root._transition(SceneRouterScript.ROUTE_TITLE)
		return _capture_route_report(route)
	if _root.current_route == SceneRouterScript.ROUTE_TITLE:
		_root.start_new_game("ranger")
	if route == SceneRouterScript.ROUTE_TUTORIAL:
		return _capture_route_report(route)
	if _root.current_route == SceneRouterScript.ROUTE_TUTORIAL:
		_root.complete_tutorial()
	if route == SceneRouterScript.ROUTE_BASE:
		return _capture_route_report(route)
	if route == SceneRouterScript.ROUTE_RESEARCH and _root.current_route == SceneRouterScript.ROUTE_BASE:
		_root.open_facility(SceneRouterScript.ROUTE_TRAINING)
		_root._on_facility_destination_requested(SceneRouterScript.ROUTE_RESEARCH)
		return _capture_route_report(route)
	if route in _root.FACILITY_ROUTES and _root.current_route == SceneRouterScript.ROUTE_BASE:
		_root.open_facility(route)
		return _capture_route_report(route)
	if route == SceneRouterScript.ROUTE_CONTRACT and _root.current_route == SceneRouterScript.ROUTE_BASE:
		_root.open_contract()
	return _capture_route_report(route)


## Read-only requested/actual route report for one preparation attempt.
func _capture_route_report(requested_route: String) -> Dictionary:
	var actual_route: String = _root.current_route
	var reached := actual_route == requested_route
	var detail := ""
	if not reached and requested_route not in CAPTURE_ROUTES:
		detail = "--capture-route=%s is not supported; supported routes: %s. A settlement is never prepared, only played: use --auto-smoke with --capture-stage=boss|auto." % [requested_route, ", ".join(PackedStringArray(CAPTURE_ROUTES))]
	elif not reached:
		detail = "--capture-route=%s could not be prepared from this state; the harness stopped at %s." % [requested_route, actual_route]
	return {
		"ok": reached,
		"error": "" if reached else "route_mismatch",
		"detail": detail,
		"requested_route": requested_route,
		"actual_route": actual_route,
	}


## Applies a validated request. Anything but the requested screen fails loudly
## instead of saving a frame for a screen nobody reached.
func _apply_capture_request(request: Dictionary) -> bool:
	var requested_route := String(request.get("capture_route", ""))
	var report: Dictionary = prepare_capture_route(requested_route)
	if bool(report.get("ok", false)):
		return true
	_capture_fail(
		String(report.get("error", "route_mismatch")),
		String(report.get("detail", "")),
		requested_route,
		String(report.get("actual_route", _root.current_route)),
		String(request.get("capture_stage", "")),
		String(request.get("capture_path", ""))
	)
	return false


func _capture_stage() -> String:
	return String(_root._capture_request.get("capture_stage", ""))


## Route capture: --capture=<path> [--capture-route=<route>], written only when the
## harness is really on the requested screen and the environment can draw one.
func capture_frame(path: String, requested_route: String = "") -> void:
	var environment: Dictionary = capture_environment_report()
	if not bool(environment.get("ok", false)):
		_capture_fail(String(environment.get("error", "capture_environment_invalid")), String(environment.get("detail", "")), requested_route, _root.current_route, "", path)
		return
	if not requested_route.is_empty() and _root.current_route != requested_route:
		_capture_fail("route_mismatch", "the requested screen is not current any more: requested=%s actual=%s" % [requested_route, _root.current_route], requested_route, _root.current_route, "", path)
		return
	await _root.get_tree().process_frame
	await _root.get_tree().process_frame
	await RenderingServer.frame_post_draw
	var written: Dictionary = _write_viewport_png(path)
	if not bool(written.get("ok", false)):
		_capture_fail(String(written.get("error", "png_write_failed")), String(written.get("detail", "")), requested_route, _root.current_route, "", path)
		return
	print("CAPTURE_PASS %s capture_kind=route requested_route=%s actual_route=%s requested_stage=none actual_stage=none" % [
		path,
		requested_route if not requested_route.is_empty() else "none",
		_root.current_route,
	])
	_root.get_tree().quit(0)


## Opt-in settlement evidence for --auto-smoke --capture-stage=boss|auto. The
## settlement has already happened when this is called; it only waits for the
## committed Result frame, saves the PNG plus its JSON sidecar, and hands the
## replay back to the continuation it interrupted. No simulation input is written.
func settlement_stage(stage: String) -> Dictionary:
	var environment: Dictionary = capture_environment_report()
	if not bool(environment.get("ok", false)):
		return _capture_refusal(String(environment.get("error", "capture_environment_invalid")), String(environment.get("detail", "")))
	if _root.current_route != _root.CAPTURE_STAGE_ROUTE:
		return _capture_refusal("route_mismatch", "settlement evidence requires the committed %s route; actual=%s" % [_root.CAPTURE_STAGE_ROUTE, _root.current_route])
	if _root._auto_smoke_stage != stage:
		return _capture_refusal("stage_mismatch", "requested stage=%s is not the settled stage=%s" % [stage, _root._auto_smoke_stage])
	var path := String(_root._capture_request.get("capture_path", ""))
	var target: Dictionary = capture_evidence_target_available(path)
	if not bool(target.get("ok", false)):
		return _capture_refusal(String(target.get("error", "capture_target_unavailable")), String(target.get("detail", "")))
	# Two frames to build and lay out the result screen, then its post-draw signal.
	await _root.get_tree().process_frame
	await _root.get_tree().process_frame
	await RenderingServer.frame_post_draw
	var written: Dictionary = _write_viewport_png(path)
	if not bool(written.get("ok", false)):
		return _capture_refusal(String(written.get("error", "png_write_failed")), String(written.get("detail", "")))
	var absolute_path := String(written.get("path", path))
	var evidence_path := absolute_path + CAPTURE_EVIDENCE_SUFFIX
	var evidence: Dictionary = _capture_settlement_evidence(stage, absolute_path, evidence_path)
	var evidence_written: Dictionary = _write_json_file(evidence_path, evidence)
	if not bool(evidence_written.get("ok", false)):
		return _capture_refusal(String(evidence_written.get("error", "evidence_write_failed")), String(evidence_written.get("detail", "")))
	var png_sha := FileAccess.get_sha256(absolute_path)
	var result: Dictionary = _root.application_state.last_result
	print("CAPTURE_PASS %s capture_kind=settlement requested_stage=%s actual_stage=%s requested_route=%s actual_route=%s contract_id=%s outcome=%s ticks=%d framework_settlements=%d setup_synthetic_wins=%d png_sha256=%s evidence=%s" % [
		path,
		stage,
		_root._auto_smoke_stage,
		_root.CAPTURE_STAGE_ROUTE,
		_root.current_route,
		String(result.get("contract_id", "")),
		String(result.get("outcome", "")),
		int(result.get("ticks", 0)),
		_root._auto_smoke_settlement_count,
		_root.AUTO_SMOKE_SETUP_NODE_IDS.size(),
		png_sha,
		evidence_path,
	])
	return {
		"ok": true,
		"error": "",
		"detail": "",
		"path": absolute_path,
		"evidence": evidence_path,
		"png_sha256": png_sha,
		"requested_stage": stage,
		"actual_stage": _root._auto_smoke_stage,
		"requested_route": _root.CAPTURE_STAGE_ROUTE,
		"actual_route": _root.current_route,
	}


## Compact read-only copy of what the run settled, plus the exact route/stage.
func _capture_settlement_evidence(stage: String, absolute_path: String, evidence_path: String) -> Dictionary:
	var result: Dictionary = _root.application_state.last_result
	var profile: Dictionary = _root.application_state.profile
	var progression_value: Variant = profile.get("progression", {})
	var progression: Dictionary = progression_value if progression_value is Dictionary else {}
	var proxy_value: Variant = profile.get("proxy_build", {})
	var proxy_build: Dictionary = proxy_value if proxy_value is Dictionary else {}
	var screen_name := ""
	if _root._current_screen != null and is_instance_valid(_root._current_screen) and _root._current_screen.get_script() != null:
		screen_name = String((_root._current_screen.get_script() as Script).resource_path.get_file())
	return {
		"protocol": CAPTURE_EVIDENCE_PROTOCOL,
		"capture_kind": "real_arena_simulation_settlement",
		"requested_stage": stage,
		"actual_stage": _root._auto_smoke_stage,
		"requested_route": _root.CAPTURE_STAGE_ROUTE,
		"actual_route": _root.current_route,
		"screen": screen_name,
		"capture_path": absolute_path,
		"evidence_path": evidence_path,
		"captured_at_utc": Time.get_datetime_string_from_system(true, true),
		"engine_version": String(Engine.get_version_info().get("string", "unknown")),
		"display": DisplayServer.get_name(),
		"presentation_enabled": _root._presentation_enabled,
		"injected_result_or_state": false,
		"setup_synthetic_wins": _root.AUTO_SMOKE_SETUP_NODE_IDS.size(),
		"framework_settlements": _root._auto_smoke_settlement_count,
		"settlement": _root._auto_smoke_result_summary(result),
		"progression": {
			"completed_node_ids": (progression.get("completed_node_ids", []) as Array).duplicate(),
			"proxy_unlocked": bool(progression.get("proxy_unlocked", false)),
			"proxy_cores": (proxy_build.get("cores", []) as Array).duplicate(),
			"proxy_inventory_ids": _root._proxy_inventory_ids(profile),
			"early_game_complete": bool(progression.get("early_game_complete", false)),
		},
	}


func _write_viewport_png(path: String) -> Dictionary:
	var absolute_path := _globalize_capture_path(path)
	var directory := absolute_path.get_base_dir()
	if not directory.is_empty():
		var directory_error := DirAccess.make_dir_recursive_absolute(directory)
		if directory_error != OK:
			return {"ok": false, "error": "directory_unavailable", "path": path, "detail": error_string(directory_error)}
	var error: Error = _root.get_viewport().get_texture().get_image().save_png(absolute_path)
	if error != OK:
		return {"ok": false, "error": "png_write_failed", "path": path, "detail": error_string(error)}
	return {"ok": true, "error": "", "path": absolute_path, "detail": ""}


func _write_json_file(path: String, data: Dictionary) -> Dictionary:
	var directory := path.get_base_dir()
	if not directory.is_empty():
		var directory_error := DirAccess.make_dir_recursive_absolute(directory)
		if directory_error != OK:
			return {"ok": false, "error": "directory_unavailable", "detail": error_string(directory_error)}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "evidence_write_failed", "detail": error_string(FileAccess.get_open_error())}
	file.store_string(SaveStoreScript.canonical_json(data) + "\n")
	file.close()
	return {"ok": true, "error": "", "detail": ""}


## Relative paths stay anchored to res:// as before; everything else is globalized.
func _globalize_capture_path(path: String) -> String:
	var candidate := path
	if not candidate.is_absolute_path() and not candidate.begins_with("user://") and not candidate.begins_with("res://"):
		candidate = ProjectSettings.globalize_path("res://" + candidate)
	return ProjectSettings.globalize_path(candidate)


## One loud line per refused capture, naming the requested and actual route/stage.
func _capture_fail(error_code: String, detail: String, requested_route: String, actual_route: String, requested_stage: String, capture_path: String) -> void:
	_capture_fail_line(error_code, detail, requested_route, actual_route, requested_stage, capture_path)
	_root._request_exit(1, "capture_fail:%s" % error_code)


func _capture_fail_line(error_code: String, detail: String, requested_route: String, actual_route: String, requested_stage: String, capture_path: String) -> void:
	printerr("CAPTURE_FAIL reason=%s requested_route=%s actual_route=%s requested_stage=%s capture=%s detail=%s" % [
		error_code,
		requested_route if not requested_route.is_empty() else "none",
		actual_route,
		requested_stage if not requested_stage.is_empty() else "none",
		capture_path if not capture_path.is_empty() else "none",
		detail,
	])


func _capture_contract_fail(report: Dictionary) -> void:
	_capture_fail(
		String(report.get("error", "capture_request_invalid")),
		String(report.get("detail", "")),
		String(report.get("capture_route", "")),
		_root.current_route,
		String(report.get("capture_stage", "")),
		String(report.get("capture_path", ""))
	)


func _capture_refusal(error_code: String, detail: String) -> Dictionary:
	return {"ok": false, "error": error_code, "detail": detail}
