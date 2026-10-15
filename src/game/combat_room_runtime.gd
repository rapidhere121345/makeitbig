class_name CombatRoomRuntime
extends Node

signal completed(result: Dictionary)
signal abandoned(result: Dictionary)

const SceneRuntimeScript := preload("res://src/runtime/world/scene_runtime.gd")
const RoomDefinitionScript := preload("res://src/runtime/world/room_definition.gd")
const WorldAssetScript := preload("res://src/runtime/world/world_asset.gd")
const RoomCatalogScript := preload("res://src/runtime/world/room_catalog.gd")
const EncounterDirectorScript := preload("res://src/game/encounter_director.gd")
const CombatRoomResultScript := preload("res://src/game/combat_room_result.gd")
const VALID_MODES := ["Manual", "Auto"]
const VALID_PRESET_IDS := ["convergent", "critical", "exponential"]
const SIMULATION_TICK_RATE := 30
var _current_config: Dictionary = {}
var _start_attempted := false
var _finalized := false
var _room_instance: Node
var room_catalog: RefCounted
var scene_runtime: SceneRuntime

var room_instance: Node:
	get:
		return _room_instance if is_instance_valid(_room_instance) else null


func set_effects_volume(value: float) -> void:
	if is_instance_valid(_room_instance) and _room_instance.has_method("set_effects_volume"):
		_room_instance.call("set_effects_volume", value)


func release_manual_controls() -> void:
	if is_instance_valid(_room_instance) and _room_instance.has_method("release_manual_controls"):
		_room_instance.call("release_manual_controls")


func take_continuous_manual_input() -> RefCounted:
	if is_instance_valid(_room_instance):
		return _room_instance.call("take_continuous_manual_input") as RefCounted
	return null


func resume_continuous_manual_input(continued_input: RefCounted) -> void:
	if is_instance_valid(_room_instance):
		_room_instance.call("resume_continuous_manual_input", continued_input)

var current_config: Dictionary:
	get:
		return _current_config.duplicate(true)


func _init() -> void:
	room_catalog = RoomCatalogScript.new()
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

	if not _current_config.get("mode", null) is String:
		return _error("invalid_mode")
	var mode := String(_current_config["mode"])
	if mode not in VALID_MODES:
		return _error("invalid_mode")
	var framework_context: Variant = _current_config.get("framework_context", {})
	if not framework_context is Dictionary:
		return _error("invalid_framework_context")
	if not (framework_context as Dictionary).get("active_build", {}) is Dictionary:
		return _error("invalid_framework_context")
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

	var room_value: Variant = _current_config.get("room", {})
	if not room_value is Dictionary:
		return _error("invalid_room")
	var room: Dictionary = (room_value as Dictionary).duplicate(true)
	if not room.has("room_id") and room.get("id", null) is String:
		room["room_id"] = String(room.get("id"))
	var room_id_value: Variant = room.get("room_id", null)
	if not room_id_value is String or String(room_id_value).strip_edges().is_empty():
		return _error("invalid_room:missing_room_field:room_id")
	_current_config["room"] = room.duplicate(true)
	if not _current_config.get("room_index", 0) is int or not _current_config.get("room_count", 1) is int:
		return _error("invalid_room_index")
	var room_index := int(_current_config.get("room_index", 0))
	var room_count := int(_current_config.get("room_count", 1))
	if room_index < 0 or room_count <= 0 or room_index >= room_count:
		return _error("invalid_room_index")
	var room_validation_error := EncounterDirectorScript.validate_room(room, room_catalog)
	if not room_validation_error.is_empty():
		## The native Main instance remains the final encounter assembly boundary.
		## Preserve that startup error for an unknown roster id while retaining the
		## reason for callers that need to diagnose the authored room.
		if room_validation_error == "unknown_enemy_id":
			return _error("room_runtime_start_failed", {"reason": room_validation_error})
		return _error("invalid_room:%s" % room_validation_error)

	room["room_index"] = room_index
	room["room_count"] = room_count
	_current_config["room"] = room.duplicate(true)
	var room_asset_result: Dictionary = room_catalog.resolve(room)
	if not bool(room_asset_result.get("ok", false)):
		return _error("invalid_room_layout")
	var room_definition = RoomDefinitionScript.new(_room_definition_data(room))
	var world_asset = WorldAssetScript.new(room_asset_result.get("asset", {}))
	scene_runtime = SceneRuntimeScript.new()
	scene_runtime.name = "SceneRuntime"
	add_child(scene_runtime)
	var mount_result: Dictionary = scene_runtime.mount(
		room_definition,
		world_asset,
		null,
		null,
		room_index,
		SIMULATION_TICK_RATE,
		Callable(self, "_configure_room_instance")
	)
	if not bool(mount_result.get("ok", false)):
		_cleanup_room_instance()
		return _error(String(mount_result.get("error", "scene_mount_failed")))
	_room_instance = scene_runtime.mounted_scene
	if _room_instance == null or not _room_instance.is_node_ready():
		_cleanup_room_instance()
		return _error("room_not_ready")
	if not _room_instance.has_method("start_room") or not _room_instance.has_signal("return_requested"):
		_cleanup_room_instance()
		return _error("room_api_unavailable")

	# The framework profile is the only persistence and contract-reward authority
	# while the combat room is embedded.
	_room_instance.set("last_save_message", "Embedded session — framework owns persistence")
	_connect_return_requested()

	_room_instance.set("selected_mode", mode)
	_room_instance.set("selected_preset", preset_id)
	_room_instance.call("start_room")
	if not bool(_room_instance.get("in_arena")):
		var deployment_reason := String(_room_instance.get("last_save_message"))
		_cleanup_room_instance()
		return _error("room_runtime_start_failed", {"reason": deployment_reason})
	set_process(true)
	return {"ok": true}


func _configure_room_instance(instance: Node) -> void:
	## SceneRuntime owns instantiation. This callback injects room context before
	## the native scene enters the tree, so its _ready() cannot start a contextless
	## session or create a second runtime authority.
	_room_instance = instance
	instance.set("embedded_session", true)
	instance.set("test_session", true)
	instance.set("presentation_enabled", bool(_current_config.get("presentation_enabled", true)))
	instance.set("framework_room", (_current_config.get("room", {}) as Dictionary).duplicate(true))
	instance.set("framework_seed", int(_current_config.get("seed", 0)))
	instance.set("automation_smoke", bool(_current_config.get("automation_smoke", false)))
	var framework_context: Dictionary = _current_config.get("framework_context", {})
	var active_build: Variant = framework_context.get("active_build", {})
	if active_build is Dictionary:
		instance.set("framework_active_build", (active_build as Dictionary).duplicate(true))
		instance.set("framework_resolved_build", (_current_config.get("resolved_build", {}) as Dictionary).duplicate(true))
		instance.set("framework_resolved_proxy_build", (framework_context.get("resolved_proxy_build", {}) as Dictionary).duplicate(true))
	instance.set("scene_runtime", scene_runtime)


func _room_definition_data(room: Dictionary) -> Dictionary:
	var room_id := String(room["room_id"])
	var layout := String(room["layout_id"])
	return {
		"room_id": room_id,
		"world_asset_id": "combat/%s" % layout,
		"encounter_id": "encounter/%s" % room_id,
		"ruleset_id": "combat.rules.v1",
		"tags": ["combat", layout],
	}


func request_abandon() -> void:
	if not _session_is_active():
		return
	if bool(_room_instance.get("battle_over")):
		_finish_completed()
		return
	_finish_abandoned()


func _process(_delta: float) -> void:
	if not _session_is_active():
		return
	if bool(_room_instance.get("battle_over")):
		_finish_completed()


## Presentation-only relay for the route layer: the mounted arena reports whether
## the published defeat clip is still on screen. Read it after completed(); it
## delays no signal, no settlement and no authoritative result.
func defeat_presentation_ready() -> bool:
	if _room_instance == null or not is_instance_valid(_room_instance):
		return true
	if not _room_instance.has_method("defeat_route_ready"):
		return true
	return bool(_room_instance.call("defeat_route_ready"))


func _on_return_requested() -> void:
	if not _session_is_active():
		return
	if bool(_room_instance.get("battle_over")):
		_finish_completed()
		return
	_finish_abandoned()


func _finish_completed() -> void:
	var victory := bool(_room_instance.get("battle_victory"))
	_finalize(&"completed", "victory" if victory else "defeat")


func _finish_abandoned() -> void:
	_finalize(&"abandoned", "abandoned")


func _finalize(signal_name: StringName, outcome: String) -> void:
	if _finalized:
		return
	_finalized = true
	set_process(false)
	_disconnect_return_requested()
	if is_instance_valid(_room_instance) and _room_instance.has_method("settle_room_loot"):
		var loot_settlement: Variant = _room_instance.call("settle_room_loot", outcome)
		if not loot_settlement is Dictionary or not bool((loot_settlement as Dictionary).get("ok", false)):
			push_error("room_loot_settlement_failed:%s" % String((loot_settlement as Dictionary).get("error", "invalid_receipt")) if loot_settlement is Dictionary else "invalid_receipt")
			return
	if outcome == "abandoned":
		release_manual_controls()
		_room_instance.set_process(false)
	var result := build_result(outcome)
	if not bool(result.get("ok", true)):
		push_error("room_result_projection_failed:%s" % String(result.error))
		return
	if signal_name == &"completed":
		completed.emit(result)
	else:
		abandoned.emit(result)


func build_result(outcome: String) -> Dictionary:
	if not is_instance_valid(_room_instance):
		return _error("room_instance_unavailable")
	var state = _room_instance.get("player_combat_state")
	if not state is Object or not state.has_method("snapshot"):
		return _error("player_combat_state_unavailable")
	var player: Dictionary = state.snapshot(int(_room_instance.get("sim_tick")))
	var room_snapshot := {
		"room_reward_snapshot": _room_instance.get("room_reward_snapshot"),
		"room_loot_settlement": _room_instance.get("room_loot_settlement"),
		"sim_tick": _room_instance.get("sim_tick"),
		"elapsed": _room_instance.get("elapsed"),
		"shots": _room_instance.get("shots"),
		"arrow_hits": _room_instance.get("arrow_hits"),
		"defeated": _room_instance.get("defeated"),
		"battle_report": _room_instance.get("battle_report"),
		"automation_smoke_failure": _room_instance.get("automation_smoke_failure"),
	}
	for field: String in ["last_damage_source_id", "last_damage_tick"]:
		if player.has(field):
			room_snapshot[field] = player[field]
	return CombatRoomResultScript.build(_current_config, room_snapshot, outcome)


func _connect_return_requested() -> void:
	var callback := Callable(self, "_on_return_requested")
	if not _room_instance.is_connected("return_requested", callback):
		_room_instance.connect("return_requested", callback)


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


func _disconnect_return_requested() -> void:
	if not is_instance_valid(_room_instance) or not _room_instance.has_signal("return_requested"):
		return
	var callback := Callable(self, "_on_return_requested")
	if _room_instance.is_connected("return_requested", callback):
		_room_instance.disconnect("return_requested", callback)


func _session_is_active() -> bool:
	return not _finalized and _room_instance != null and is_instance_valid(_room_instance)


func _cleanup_room_instance() -> void:
	set_process(false)
	_disconnect_return_requested()
	if scene_runtime != null and is_instance_valid(scene_runtime):
		scene_runtime.unmount()
		if scene_runtime.get_parent() == self:
			remove_child(scene_runtime)
		scene_runtime.queue_free()
	scene_runtime = null
	_room_instance = null


func _error(code: String, details: Dictionary = {}) -> Dictionary:
	var result := {"ok": false, "error": code}
	result.merge(details.duplicate(true))
	return result
