class_name PrototypeDebug
extends RefCounted

## Prototype debug tooling extracted from GameRoot. This collaborator owns the
## --mib-* directive parsing, the save wipe, the runtime application and the
## rejection path, plus the state they produce, and reaches the shell through
## GameRoot's public API.
const SceneRouterScript = preload("res://src/game/scene_router.gd")
const SaveStoreScript = preload("res://src/persistence/save_store.gd")

const PROTOTYPE_DEBUG_DIRECTIVES_PATH: String = "res://tools/prototype_debug_directives.gd"
const PROTOTYPE_DEBUG_RUNTIME_PATH: String = "res://tools/prototype_debug_runtime.gd"
const PROTOTYPE_DEBUG_DEFAULT_SAVE_DIRECTORY: String = "user://makeitbig-prototype-debug"
const PROTOTYPE_DEBUG_REJECTED_SAVE_DIRECTORY: String = "user://makeitbig-prototype-debug-rejected"
## Drop tag the one-shot force-family override adds to every room of the next plan.
const FORCED_DROP_TAG: String = "equipment_general"

## Parsed directives; empty when no debug request is active or after a rejection.
var dto: Dictionary = {}
var rejected := false
var reject_reason := ""
## True when the request asked for a run that writes no save and no playtest log.
var no_persist := false
var has_seed := false
var seed_override := 0
## One-shot drop family override; ContractFlow clears it after the session begins.
var force_family := ""
## What the debug runtime applied (stage, route, changed), empty until applied.
var summary: Dictionary = {}

var _root: GameRoot


func _init(root: GameRoot) -> void:
	_root = root


## Only considers prototype debug tooling when at least one --mib-* argument is
## present, and only after OS.is_debug_build() is true.  The directives and the
## runtime are loaded dynamically; no compile-time preload dependency on tools/
## exists.
func consider(arguments: PackedStringArray) -> void:
	var mib_requested := false
	for argument in arguments:
		if argument.begins_with("--mib-"):
			mib_requested = true
			break
	if not mib_requested:
		return
	if not OS.is_debug_build():
		_reject_prototype_debug("debug_build_required", "prototype debug tools require a debug build")
		return
	var directives_script: Script = load(PROTOTYPE_DEBUG_DIRECTIVES_PATH)
	if directives_script == null:
		_reject_prototype_debug("tool_load_failed", "could not load prototype debug directives")
		return
	var parsed: Dictionary = directives_script.parse(arguments)
	if not bool(parsed.get("ok", false)):
		_reject_prototype_debug("parse_failed", str(parsed.get("error", "unknown_debug_flag")))
		return
	if not bool(parsed.get("enabled", false)):
		return
	dto = parsed.duplicate(true)
	_root.save_directory_path = String(parsed.get("save_directory", PROTOTYPE_DEBUG_DEFAULT_SAVE_DIRECTORY))
	_root.playtest_log_directory = _root.save_directory_path.trim_suffix("/") + "/playtest"
	no_persist = bool(parsed.get("no_persist", false))
	if bool(parsed.get("has_seed", false)):
		has_seed = true
		seed_override = int(parsed.get("seed", 0))


func apply_wipe() -> void:
	if rejected or dto.is_empty():
		return
	if not bool(dto.get("wipe", false)):
		return
	var wiped: Dictionary = _root.save_store.delete_all()
	if not bool(wiped.get("ok", false)):
		_reject_prototype_debug("wipe_failed", str(wiped.get("error", "unknown_error")))
		return
	_root.application_state.reset()


func apply_runtime() -> void:
	if rejected or dto.is_empty():
		return
	var runtime_script: Script = load(PROTOTYPE_DEBUG_RUNTIME_PATH)
	if runtime_script == null:
		_reject_prototype_debug("tool_load_failed", "could not load prototype debug runtime")
		return
	var applied: Dictionary = runtime_script.apply(_root, dto)
	if not bool(applied.get("ok", false)):
		_reject_prototype_debug("apply_failed", str(applied.get("error", "prototype_debug_apply_failed")))
		_root.transition(SceneRouterScript.ROUTE_TITLE)
		return
	summary = applied.duplicate(true)
	var forced_family := String(applied.get("force_family", "")).strip_edges()
	force_family = forced_family if not forced_family.is_empty() else ""
	print("PROTOTYPE_DEBUG_APPLIED %s" % JSON.stringify(summary))
	_root.record_playtest("prototype_debug_applied", summary)
	if not bool(applied.get("changed", false)):
		return
	var safe_route := SceneRouterScript.ROUTE_TITLE
	if _root.current_route == SceneRouterScript.ROUTE_BASE or _root.current_route == SceneRouterScript.ROUTE_TUTORIAL:
		safe_route = _root.current_route
	_root.persist("Prototype debug applied", safe_route)


## Rejects a debug request with a stable log line and flow_error, then isolates
## the session so the default real save directory is never touched.
func _reject_prototype_debug(reason: String, detail: String) -> void:
	if rejected:
		return
	rejected = true
	reject_reason = reason
	print("PROTOTYPE_DEBUG_REJECTED reason=%s detail=%s" % [reason, detail])
	_root.flow_error.emit("prototype_debug_rejected", "%s: %s" % [reason, detail])
	dto = {}
	has_seed = false
	seed_override = 0
	force_family = ""
	no_persist = false
	_root.save_directory_path = PROTOTYPE_DEBUG_REJECTED_SAVE_DIRECTORY
	_root.playtest_log_directory = PROTOTYPE_DEBUG_REJECTED_SAVE_DIRECTORY.path_join("playtest")
	_root.application_state.reset()
	if _root.save_store != null:
		_root.save_store = SaveStoreScript.new(PROTOTYPE_DEBUG_REJECTED_SAVE_DIRECTORY)
