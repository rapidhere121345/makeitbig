class_name ContractRunController
extends Node

signal completed(result: Dictionary)
signal abandoned(result: Dictionary)
signal room_changed(room_index: int, room_count: int, room: Dictionary)

const DEFAULT_ROOM_RUNTIME_SCRIPT := preload("res://src/game/combat_room_runtime.gd")
const ERROR_ALREADY_STARTED := "already_started"
const ERROR_INVALID_ROOM_COUNT := "invalid_room_count"
const ERROR_INVALID_ROOM_PLAN := "invalid_room_plan"
const ERROR_ROOM_RUNTIME_FACTORY_FAILED := "room_runtime_factory_failed"
const ERROR_ROOM_RUNTIME_API_UNAVAILABLE := "room_runtime_api_unavailable"
const ERROR_ROOM_RUNTIME_START_FAILED := "room_runtime_start_failed"
const ERROR_ROOM_COMMIT_FAILED := "room_commit_failed"

## Tests and future room implementations may inject a zero-argument factory
## before this node enters the tree.
var room_runtime_factory: Callable

## Framework port for the room-victory path. When set, it is called with
## (room_index, room_result) after a room victory and before the next room
## starts. It must return the ApplicationState boundary result
## Dictionary{ok,error,committed_items,resolved_build,active_build}. On success
## only this controller's detached framework context for the next room adopts
## the returned active_build/resolved_build; room plan, results and runtime
## authority stay unchanged. When unset, room transitions keep the launch-time
## framework context.
var room_commit_port: Callable

var current_config: Dictionary:
	get:
		return _current_config.duplicate(true)

var current_room_index: int:
	get:
		return _current_room_index

var room_count: int:
	get:
		return _rooms.size()

var _current_config: Dictionary = {}
var _rooms: Array[Dictionary] = []
var _current_room_index := -1
var _current_runtime: Node
var _room_results: Array[Dictionary] = []
var _rooms_completed := 0
var _start_attempted := false
var _finalized := false
var _effects_volume := 0.45


func set_effects_volume(value: float) -> void:
	_effects_volume = clampf(value, 0.0, 1.0)
	if is_instance_valid(_current_runtime) and _current_runtime.has_method("set_effects_volume"):
		_current_runtime.call("set_effects_volume", _effects_volume)


func release_manual_controls() -> void:
	if is_instance_valid(_current_runtime) and _current_runtime.has_method("release_manual_controls"):
		_current_runtime.call("release_manual_controls")


func start_session(config: Dictionary) -> Dictionary:
	if _start_attempted:
		return _error(ERROR_ALREADY_STARTED)
	_start_attempted = true
	_current_config = config.duplicate(true)

	var requested_room_count: Variant = _current_config.get("room_count", null)
	if typeof(requested_room_count) != TYPE_INT or int(requested_room_count) < 1:
		return _error(ERROR_INVALID_ROOM_COUNT)

	var prepared_rooms := _prepare_rooms(int(requested_room_count))
	if not bool(prepared_rooms.get("ok", false)):
		return _error(String(prepared_rooms.get("error", ERROR_INVALID_ROOM_PLAN)))
	_rooms.assign(prepared_rooms.get("rooms", []) as Array)

	var started := _start_room(0, false)
	if not bool(started.get("ok", false)):
		return started
	return {"ok": true}


func request_abandon() -> void:
	if _finalized or _current_runtime == null or not is_instance_valid(_current_runtime):
		return
	if _current_runtime.has_method("request_abandon"):
		_current_runtime.call("request_abandon")


## Presentation-only relay for the route layer: the arena screen mounted right
## now reports whether its published defeat clip is still on screen. It changes
## no aggregate summary, no settlement and no room-runtime signal.
func defeat_presentation_ready() -> bool:
	if _current_runtime == null or not is_instance_valid(_current_runtime):
		return true
	if not _current_runtime.has_method("defeat_presentation_ready"):
		return true
	return bool(_current_runtime.call("defeat_presentation_ready"))


func _prepare_rooms(expected_count: int) -> Dictionary:
	var source_rooms: Variant = null
	if _current_config.has("room_plan"):
		var room_plan: Variant = _current_config.get("room_plan")
		if not (room_plan is Dictionary):
			return _error(ERROR_INVALID_ROOM_PLAN)
		if (room_plan as Dictionary).has("rooms"):
			source_rooms = (room_plan as Dictionary).get("rooms")

	var prepared: Array[Dictionary] = []
	if source_rooms == null:
		for _index in expected_count:
			prepared.append({})
		return {"ok": true, "rooms": prepared}
	if not (source_rooms is Array) or (source_rooms as Array).size() != expected_count:
		return _error(ERROR_INVALID_ROOM_PLAN)
	for room: Variant in (source_rooms as Array):
		if not (room is Dictionary):
			return _error(ERROR_INVALID_ROOM_PLAN)
		prepared.append((room as Dictionary).duplicate(true))
	return {"ok": true, "rooms": prepared}


func _start_room(index: int, emit_change: bool, continued_input: RefCounted = null) -> Dictionary:
	var runtime := _make_room_runtime()
	if runtime == null:
		return _error(ERROR_ROOM_RUNTIME_FACTORY_FAILED)
	if not runtime.has_method("start_session") or not runtime.has_signal("completed") or not runtime.has_signal("abandoned"):
		runtime.queue_free()
		return _error(ERROR_ROOM_RUNTIME_API_UNAVAILABLE)

	_current_room_index = index
	_current_runtime = runtime
	runtime.connect(&"completed", Callable(self, "_on_runtime_completed").bind(runtime, index))
	runtime.connect(&"abandoned", Callable(self, "_on_runtime_abandoned").bind(runtime, index))
	add_child(runtime)

	var room_config := _current_config.duplicate(true)
	room_config["room_index"] = index
	room_config["room"] = _rooms[index].duplicate(true)
	var launch_result: Variant = runtime.call("start_session", room_config)
	set_effects_volume(_effects_volume)
	if not (launch_result is Dictionary) or not bool((launch_result as Dictionary).get("ok", false)):
		var error_code := ERROR_ROOM_RUNTIME_START_FAILED
		if launch_result is Dictionary:
			error_code = String((launch_result as Dictionary).get("error", error_code))
		_retire_current_runtime()
		return _error(error_code)
	if continued_input != null and runtime.has_method("resume_continuous_manual_input"):
		runtime.call("resume_continuous_manual_input", continued_input)

	if emit_change and not _finalized and _current_runtime == runtime and _current_room_index == index:
		room_changed.emit(index, _rooms.size(), _rooms[index].duplicate(true))
	return {"ok": true}


func _make_room_runtime() -> Node:
	if room_runtime_factory.is_valid():
		var candidate: Variant = room_runtime_factory.call()
		return candidate as Node if candidate is Node else null
	return DEFAULT_ROOM_RUNTIME_SCRIPT.new()


func _on_runtime_completed(result: Dictionary, runtime: Node, index: int) -> void:
	if not _accepts_signal(runtime, index):
		return
	var isolated_result := result.duplicate(true)
	_room_results.append(isolated_result)
	var outcome := String(isolated_result.get("outcome", ""))
	if outcome == "victory":
		_rooms_completed += 1
		if index + 1 < _rooms.size():
			if room_commit_port.is_valid():
				var committed: Variant = room_commit_port.call(index, isolated_result.duplicate(true))
				if not (committed is Dictionary) or not bool((committed as Dictionary).get("ok", false)):
					_retire_current_runtime()
					var commit_error := "invalid_commit_result"
					if committed is Dictionary:
						commit_error = String((committed as Dictionary).get("error", "invalid_commit_result"))
					_room_results.append({
						"outcome": "error",
						"error": ERROR_ROOM_COMMIT_FAILED,
						"commit_error": commit_error,
						"report": "Room victory commit failed before the next room.",
					})
					_finalize_completed("error")
					return
				_apply_room_commit_to_context(committed as Dictionary)
			var continued_input: RefCounted = null
			if String(_current_config.get("mode", "")) == "Manual" and runtime.has_method("take_continuous_manual_input"):
				continued_input = runtime.call("take_continuous_manual_input") as RefCounted
			_retire_current_runtime()
			var next_started := _start_room(index + 1, true, continued_input)
			if not bool(next_started.get("ok", false)):
				_room_results.append({
					"outcome": "error",
					"error": String(next_started.get("error", ERROR_ROOM_RUNTIME_START_FAILED)),
					"report": "Room runtime could not start.",
				})
				_finalize_completed("error")
			return
	_finalize_completed(outcome)


## Applies a successful framework commit to the detached config the next room
## reads. Only framework_context (and its sibling resolved_build hint) change.
func _apply_room_commit_to_context(committed: Dictionary) -> void:
	var framework_value: Variant = _current_config.get("framework_context", {})
	var framework: Dictionary = framework_value if framework_value is Dictionary else {}
	var resolved_value: Variant = committed.get("resolved_build", {})
	if resolved_value is Dictionary and not (resolved_value as Dictionary).is_empty():
		framework["resolved_build"] = (resolved_value as Dictionary).duplicate(true)
		_current_config["resolved_build"] = (resolved_value as Dictionary).duplicate(true)
	var active_value: Variant = committed.get("active_build", {})
	if active_value is Dictionary and not (active_value as Dictionary).is_empty():
		framework["active_build"] = (active_value as Dictionary).duplicate(true)
	_current_config["framework_context"] = framework


func _on_runtime_abandoned(result: Dictionary, runtime: Node, index: int) -> void:
	if not _accepts_signal(runtime, index):
		return
	_room_results.append(result.duplicate(true))
	_finalize_abandoned()


func _accepts_signal(runtime: Node, index: int) -> bool:
	return not _finalized and runtime == _current_runtime and index == _current_room_index


func _finalize_completed(outcome: String) -> void:
	if _finalized:
		return
	_finalized = true
	completed.emit(_build_summary(outcome))


func _finalize_abandoned() -> void:
	if _finalized:
		return
	_finalized = true
	abandoned.emit(_build_summary("abandoned"))


func _build_summary(outcome: String) -> Dictionary:
	var ticks := 0
	var elapsed_seconds := 0.0
	var casts := 0
	var defeated := 0
	var report := ""
	var law_tallies_delta := {"inscribe": 0, "rewrite": 0, "refine": 0}
	var failure_reason := ""
	var room_loot_settlements: Array[Dictionary] = []
	var room_loot_items: Array[Dictionary] = []
	for room_result: Dictionary in _room_results:
		ticks += int(room_result.get("ticks", 0))
		elapsed_seconds += float(room_result.get("elapsed_seconds", 0.0))
		casts += int(room_result.get("casts", 0))
		defeated += int(room_result.get("defeated", 0))
		var candidate_report := String(room_result.get("report", ""))
		if not candidate_report.is_empty():
			report = candidate_report
		var rewards: Variant = room_result.get("rewards", {})
		if rewards is Dictionary:
			var room_tallies_value: Variant = (rewards as Dictionary).get("law_tallies_delta", {})
			if room_tallies_value is Dictionary:
				for operation in law_tallies_delta:
					law_tallies_delta[operation] = int(law_tallies_delta[operation]) + int((room_tallies_value as Dictionary).get(operation, 0))
		if failure_reason.is_empty() and String(room_result.get("outcome", "")) == outcome:
			failure_reason = String(room_result.get("failure_reason", ""))
		var loot_value: Variant = room_result.get("room_loot_settlement", {})
		if loot_value is Dictionary and not (loot_value as Dictionary).is_empty():
			room_loot_settlements.append((loot_value as Dictionary).duplicate(true))
			var items_value: Variant = (loot_value as Dictionary).get("items", [])
			if items_value is Array:
				for item_value: Variant in items_value:
					if item_value is Dictionary:
						room_loot_items.append((item_value as Dictionary).duplicate(true))

	var summary := {
		"outcome": outcome,
		"contract_id": _copy_config_value("contract_id"),
		"mode": _copy_config_value("mode"),
		"preset_id": _copy_config_value("preset_id"),
		"seed": _copy_config_value("seed"),
		"rooms_completed": _rooms_completed,
		"room_count": _rooms.size(),
		"ticks": ticks,
		"elapsed_seconds": elapsed_seconds,
		"casts": casts,
		"defeated": defeated,
		"report": report,
		"rewards": {
			"contract_wins_delta": 1 if outcome == "victory" else 0,
			"law_tallies_delta": law_tallies_delta.duplicate(true),
		},
		"room_results": _room_results.duplicate(true),
	}
	if not room_loot_settlements.is_empty():
		summary["room_loot_settlements"] = room_loot_settlements.duplicate(true)
		summary["room_loot_items"] = room_loot_items.duplicate(true)
	if outcome == "defeat" and not failure_reason.is_empty():
		summary["failure_reason"] = failure_reason
	return summary


func _copy_config_value(key: String) -> Variant:
	return {"value": _current_config.get(key)}.duplicate(true)["value"]


func _retire_current_runtime() -> void:
	var runtime := _current_runtime
	_current_runtime = null
	if runtime == null or not is_instance_valid(runtime):
		return
	if runtime.get_parent() == self:
		remove_child(runtime)
	runtime.queue_free()


func _error(code: String) -> Dictionary:
	return {"ok": false, "error": code}
