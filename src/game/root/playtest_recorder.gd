class_name PlaytestRecorder
extends RefCounted

## Playtest telemetry extracted from GameRoot. This collaborator owns the
## session start, event record and finish calls against the owner's playtest
## log, plus the profile wall-clock helper, reaching owner state through the
## untyped owner reference.
const ApplicationStateScript = preload("res://src/game/application_state.gd")
const PlaytestLogScript = preload("res://src/game/playtest_log.gd")
const EarlyCampaignRegistryScript = preload("res://src/content/early_campaign_registry.gd")
const EarlyItemRegistryScript = preload("res://src/content/early_item_registry.gd")

var _root


func _init(root) -> void:
	_root = root


func _start_playtest_logging() -> void:
	if _root.playtest_log == null:
		_root.playtest_log = PlaytestLogScript.new(_root.playtest_log_directory)
	if not _root.playtest_log.has_method("start_session"):
		return
	_root._playtest_session_started_msec = Time.get_ticks_msec()
	_root._playtest_route_entered_msec = _root._playtest_session_started_msec
	_root.playtest_log.call("start_session", {
		"prototype": "early_game",
		"profile_schema_version": ApplicationStateScript.SCHEMA_VERSION,
		"content_versions": {
			"early_campaign": EarlyCampaignRegistryScript.SCHEMA_VERSION,
			"early_items": EarlyItemRegistryScript.EXPECTED_SCHEMA_VERSION,
		},
		"engine_version": Engine.get_version_info().get("string", "unknown"),
	})


func _record_playtest(event_id: String, payload: Dictionary = {}) -> void:
	if _root._prototype_debug_no_persist:
		return
	if _root.playtest_log == null or not _root.playtest_log.has_method("record"):
		return
	if _root.playtest_log.has_method("is_active") and not bool(_root.playtest_log.call("is_active")):
		return
	_root.playtest_log.call("record", event_id, payload.duplicate(true))


func _finish_playtest_logging(reason: String) -> void:
	if _root.playtest_log == null:
		return
	if _root.playtest_log.has_method("is_active") and not bool(_root.playtest_log.call("is_active")):
		return
	if _root.playtest_log.has_method("finish"):
		_root.playtest_log.call("finish", {"reason": reason})
	elif _root.playtest_log.has_method("close"):
		_root.playtest_log.call("close")


func _profile_elapsed_msec() -> int:
	if _root._playtest_profile_started_msec <= 0:
		return 0
	return maxi(0, Time.get_ticks_msec() - _root._playtest_profile_started_msec)
