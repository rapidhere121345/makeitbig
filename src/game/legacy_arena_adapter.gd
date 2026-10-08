class_name LegacyArenaAdapter
extends Node

signal completed(result: Dictionary)
signal abandoned(result: Dictionary)

const LEGACY_ARENA_SCENE := preload("res://src/game/main.tscn")
const VALID_MODES := ["Manual", "Auto"]
const VALID_PRESET_IDS := ["convergent", "critical", "exponential"]
var _current_config: Dictionary = {}
var _start_attempted := false
var _finalized := false
var _legacy: Node
var _return_button: Object


func set_effects_volume(value: float) -> void:
	if is_instance_valid(_legacy) and _legacy.has_method("set_effects_volume"):
		_legacy.call("set_effects_volume", value)


func release_manual_controls() -> void:
	if is_instance_valid(_legacy) and _legacy.has_method("release_manual_controls"):
		_legacy.call("release_manual_controls")


func take_continuous_manual_input() -> RefCounted:
	if is_instance_valid(_legacy):
		return _legacy.call("take_continuous_manual_input") as RefCounted
	return null


func resume_continuous_manual_input(continued_input: RefCounted) -> void:
	if is_instance_valid(_legacy):
		_legacy.call("resume_continuous_manual_input", continued_input)

var current_config: Dictionary:
	get:
		return _current_config.duplicate(true)


func _init() -> void:
	set_process(false)


func start_session(config: Dictionary) -> Dictionary:
	if _start_attempted:
		return _error("already_started")
	_start_attempted = true
	_current_config = config.duplicate(true)

	var presentation_value: Variant = _current_config.get("presentation_enabled", true)
	if typeof(presentation_value) != TYPE_BOOL:
		return _error("invalid_presentation_enabled")
	_current_config["presentation_enabled"] = bool(presentation_value)

	var mode := String(_current_config.get("mode", ""))
	if mode not in VALID_MODES:
		return _error("invalid_mode")
	var framework_context: Variant = _current_config.get("framework_context", {})
	if not framework_context is Dictionary:
		return _error("invalid_framework_context")
	var room_value: Variant = _current_config.get("room", {})
	if not room_value is Dictionary:
		return _error("invalid_room")
	var room: Dictionary = (room_value as Dictionary).duplicate(true)
	_current_config["room"] = room.duplicate(true)
	var resolved_value: Variant = (framework_context as Dictionary).get("resolved_build", {})
	if not _is_valid_resolved_build(resolved_value):
		return _error("invalid_resolved_build")
	var resolved_build: Dictionary = (resolved_value as Dictionary).duplicate(true)
	var resolved_proxy_value: Variant = (framework_context as Dictionary).get("resolved_proxy_build", {})
	if not resolved_proxy_value is Dictionary:
		return _error("invalid_resolved_proxy_build")
	var resolved_proxy_build: Dictionary = (resolved_proxy_value as Dictionary).duplicate(true)
	if mode == "Auto" and resolved_proxy_build.is_empty():
		return _error("invalid_resolved_proxy_build")
	# The preset name is now only a compatibility/display label. Combat reads the
	# frozen resolved build injected below.
	var preset_id := String(resolved_build.get("growth_classification", "convergent"))
	if preset_id not in VALID_PRESET_IDS:
		preset_id = "convergent"
	_current_config["mode"] = mode
	_current_config["preset_id"] = preset_id
	_current_config["resolved_build"] = resolved_build.duplicate(true)

	var instance := LEGACY_ARENA_SCENE.instantiate()
	if instance == null:
		return _error("scene_instantiate_failed")
	_legacy = instance
	# Configure the embedded arena before _ready() runs. In particular, this
	# prevents project-level smoke arguments from starting a second, context-free
	# legacy session while the adapter is mounting it.
	_legacy.set("embedded_session", true)
	_legacy.set("test_session", true)
	_legacy.set("presentation_enabled", bool(_current_config.get("presentation_enabled", true)))
	room["room_index"] = int(_current_config.get("room_index", 0))
	room["room_count"] = int(_current_config.get("room_count", 1))
	_legacy.set("framework_room", room.duplicate(true))
	var automation_smoke := bool(_current_config.get("automation_smoke", false))
	_legacy.set("automation_smoke", automation_smoke)
	var active_build: Variant = (framework_context as Dictionary).get("active_build", {})
	if active_build is Dictionary:
		_legacy.set("framework_active_build", (active_build as Dictionary).duplicate(true))
	_legacy.set("framework_resolved_build", resolved_build.duplicate(true))
	_legacy.set("framework_resolved_proxy_build", resolved_proxy_build.duplicate(true))
	add_child(_legacy)
	if not _legacy.is_node_ready():
		_cleanup_legacy()
		return _error("legacy_not_ready")
	if not _legacy.has_method("_enter_arena"):
		_cleanup_legacy()
		return _error("legacy_api_unavailable")

	# The framework profile is the only persistence and contract-reward authority
	# while the legacy arena is embedded.
	_legacy.set("last_save_message", "Embedded session — framework owns persistence")
	_connect_return_button()

	_legacy.set("selected_mode", mode)
	_legacy.set("selected_preset", preset_id)
	_legacy.call("_enter_arena")
	if not bool(_legacy.get("in_arena")):
		_cleanup_legacy()
		return _error("arena_start_failed")
	set_process(true)
	return {"ok": true}


func request_abandon() -> void:
	if not _session_is_active():
		return
	if bool(_legacy.get("battle_over")):
		_finish_completed()
		return
	_finish_abandoned()


func _process(_delta: float) -> void:
	if not _session_is_active():
		return
	if bool(_legacy.get("battle_over")):
		_finish_completed()


## Presentation-only relay for the route layer: the mounted arena reports whether
## the published defeat clip is still on screen. Read it after completed(); it
## delays no signal, no settlement and no authoritative result.
func defeat_presentation_ready() -> bool:
	if _legacy == null or not is_instance_valid(_legacy):
		return true
	if not _legacy.has_method("defeat_route_ready"):
		return true
	return bool(_legacy.call("defeat_route_ready"))


func _on_return_button_pressed() -> void:
	if not _session_is_active():
		return
	if bool(_legacy.get("battle_over")):
		_finish_completed()
		return
	_finish_abandoned()


func _finish_completed() -> void:
	var victory := bool(_legacy.get("battle_victory"))
	_finalize(&"completed", "victory" if victory else "defeat")


func _finish_abandoned() -> void:
	_finalize(&"abandoned", "abandoned")


func _finalize(signal_name: StringName, outcome: String) -> void:
	if _finalized:
		return
	_finalized = true
	set_process(false)
	var result := _build_result(outcome)
	if signal_name == &"completed":
		completed.emit(result)
	else:
		abandoned.emit(result)


func _build_result(outcome: String) -> Dictionary:
	var snapshot_value: Variant = _legacy.get("room_reward_snapshot")
	var legacy_rewards: Dictionary = snapshot_value.duplicate(true) if snapshot_value is Dictionary else {}
	var drop_tags_value: Variant = _copy_room_value("drop_tags")
	var drop_tags: Array = drop_tags_value if drop_tags_value is Array else []
	var rewards: Dictionary = legacy_rewards.duplicate(true)
	for legacy_key in ["fate_dice", "fate_dice_delta", "add_dice_delta", "rewrite_dice_delta", "refine_dice_delta", "reroll_dice_delta", "drop_id", "drop_label"]:
		rewards.erase(legacy_key)
	rewards["law_tallies_delta"] = {
		"inscribe": int(legacy_rewards.get("add_dice_delta", 0)) + (1 if "inscribe_tally" in drop_tags else 0),
		"rewrite": int(legacy_rewards.get("rewrite_dice_delta", 0)) + (1 if "rewrite_tally" in drop_tags else 0),
		"refine": int(legacy_rewards.get("refine_dice_delta", 0)) + (1 if "refine_tally" in drop_tags else 0),
	}
	var result := {
		"outcome": outcome,
		"contract_id": _copy_config_value("contract_id"),
		"mode": String(_current_config.get("mode", "")),
		"preset_id": String(_current_config.get("preset_id", "convergent")),
		"build_fingerprint": String((_current_config.get("resolved_build", {}) as Dictionary).get("build_fingerprint", "")),
		"seed": _copy_config_value("seed"),
		"room_id": _copy_room_value("room_id"),
		"objective": _copy_room_value("objective_id", "objective"),
		"layout": _copy_room_value("layout_id", "layout"),
		"drop_tags": drop_tags.duplicate(true),
		"ticks": int(_legacy.get("sim_tick")),
		"elapsed_seconds": float(_legacy.get("elapsed")),
		"casts": int(_legacy.get("shots")),
		"arrow_hits": int(_legacy.get("arrow_hits")),
		"defeated": int(_legacy.get("defeated")),
		"report": String(_legacy.get("battle_report")),
		"rewards": rewards,
	}
	if outcome == "defeat":
		result["failure_reason"] = String(_legacy.get("last_damage_source_id"))
		result["death_tick"] = int(_legacy.get("last_damage_tick"))
	var automation_failure := String(_legacy.get("automation_smoke_failure"))
	if not automation_failure.is_empty():
		result["error"] = automation_failure
	return result


func _copy_config_value(key: String) -> Variant:
	return {"value": _current_config.get(key)}.duplicate(true)["value"]


func _copy_room_value(key: String, fallback_key: String = "") -> Variant:
	var room: Dictionary = _current_config.get("room", {})
	var value: Variant = room.get(key, room.get(fallback_key) if not fallback_key.is_empty() else null)
	return {"value": value}.duplicate(true)["value"]


func _connect_return_button() -> void:
	var candidate: Variant = _legacy.get("return_button")
	if not (candidate is Object) or not is_instance_valid(candidate):
		return
	var candidate_object := candidate as Object
	if not candidate_object.has_signal("pressed"):
		return
	_return_button = candidate_object
	var callback := Callable(self, "_on_return_button_pressed")
	if not _return_button.is_connected("pressed", callback):
		_return_button.connect("pressed", callback)


func _is_valid_resolved_build(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var build: Dictionary = value
	if not bool(build.get("ok", false)):
		return false
	var fingerprint := String(build.get("build_fingerprint", ""))
	if fingerprint.length() != 64:
		return false
	for character in fingerprint:
		if character not in "0123456789abcdef":
			return false
	var parameters: Variant = build.get("final_parameters", {})
	if not parameters is Dictionary:
		return false
	for key in ["p", "T", "v", "d", "turn", "damage", "max_health"]:
		var parameter: Variant = (parameters as Dictionary).get(key, null)
		if typeof(parameter) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(parameter)):
			return false
	return true


func _disconnect_return_button() -> void:
	if _return_button == null or not is_instance_valid(_return_button):
		_return_button = null
		return
	var callback := Callable(self, "_on_return_button_pressed")
	if _return_button.is_connected("pressed", callback):
		_return_button.disconnect("pressed", callback)
	_return_button = null


func _session_is_active() -> bool:
	return not _finalized and _legacy != null and is_instance_valid(_legacy)


func _cleanup_legacy() -> void:
	set_process(false)
	_disconnect_return_button()
	if _legacy == null or not is_instance_valid(_legacy):
		_legacy = null
		return
	if _legacy.get_parent() == self:
		remove_child(_legacy)
	_legacy.queue_free()
	_legacy = null


func _error(code: String) -> Dictionary:
	set_process(false)
	return {"ok": false, "error": code}
