class_name PlaytestRecorder
extends RefCounted

## Playtest telemetry extracted from GameRoot. This collaborator owns the
## session start, event record and finish calls against the owner's playtest
## log, plus the session, profile and route wall-clock timers, and reaches the
## shell through GameRoot's public API.
const ApplicationStateScript = preload("res://src/game/application_state.gd")
const PlaytestLogScript = preload("res://src/game/playtest_log.gd")
const EarlyCampaignRegistryScript = preload("res://src/content/early_campaign_registry.gd")
const EarlyItemRegistryScript = preload("res://src/content/early_item_registry.gd")

var _root: GameRoot
var _session_started_msec := 0
var _profile_started_msec := 0
var _route_entered_msec := 0


func _init(root: GameRoot) -> void:
	_root = root


func start_session() -> void:
	if _root.playtest_log == null:
		_root.playtest_log = PlaytestLogScript.new(_root.playtest_log_directory)
	if not _root.playtest_log is PlaytestLogScript:
		return
	_session_started_msec = Time.get_ticks_msec()
	_route_entered_msec = _session_started_msec
	_root.playtest_log.start_session({
		"prototype": "early_game",
		"profile_schema_version": ApplicationStateScript.SCHEMA_VERSION,
		"content_versions": {
			"early_campaign": EarlyCampaignRegistryScript.SCHEMA_VERSION,
			"early_items": EarlyItemRegistryScript.EXPECTED_SCHEMA_VERSION,
		},
		"engine_version": Engine.get_version_info().get("string", "unknown"),
	})


func record(event_id: String, payload: Dictionary = {}) -> void:
	if _root.prototype_debug.no_persist:
		return
	if not _root.playtest_log is PlaytestLogScript:
		return
	if not bool(_root.playtest_log.is_active()):
		return
	_root.playtest_log.record(event_id, payload.duplicate(true))


func finish(reason: String) -> void:
	if not _root.playtest_log is PlaytestLogScript:
		return
	if not bool(_root.playtest_log.is_active()):
		return
	_root.playtest_log.finish({"reason": reason})


## Starts the profile wall clock when a new profile is created.
func mark_profile_started() -> void:
	_profile_started_msec = Time.get_ticks_msec()


## Records a committed route change with the dwell and elapsed timers, then
## restarts the route dwell clock.
func record_route_change(previous_route: String, route: String) -> void:
	var now_msec := Time.get_ticks_msec()
	record("route_changed", {
		"from": previous_route,
		"to": route,
		"previous_dwell_msec": maxi(0, now_msec - _route_entered_msec) if _route_entered_msec > 0 else 0,
		"session_elapsed_msec": maxi(0, now_msec - _session_started_msec) if _session_started_msec > 0 else 0,
		"profile_elapsed_msec": profile_elapsed_msec(),
	})
	_route_entered_msec = now_msec


func profile_elapsed_msec() -> int:
	if _profile_started_msec <= 0:
		return 0
	return maxi(0, Time.get_ticks_msec() - _profile_started_msec)
