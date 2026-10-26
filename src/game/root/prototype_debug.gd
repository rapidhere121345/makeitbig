class_name PrototypeDebug
extends RefCounted

## Prototype debug tooling extracted from GameRoot. This collaborator owns the
## --mib-* directive parsing, the save wipe, the runtime application and the
## rejection path, reaching owner state and presentation through the untyped
## owner reference.
const SceneRouterScript = preload("res://src/game/scene_router.gd")
const SaveStoreScript = preload("res://src/persistence/save_store.gd")

const PROTOTYPE_DEBUG_DIRECTIVES_PATH: String = "res://tools/prototype_debug_directives.gd"
const PROTOTYPE_DEBUG_RUNTIME_PATH: String = "res://tools/prototype_debug_runtime.gd"
const PROTOTYPE_DEBUG_DEFAULT_SAVE_DIRECTORY: String = "user://makeitbig-prototype-debug"
const PROTOTYPE_DEBUG_REJECTED_SAVE_DIRECTORY: String = "user://makeitbig-prototype-debug-rejected"

var _root


func _init(root) -> void:
	_root = root


## Only considers prototype debug tooling when at least one --mib-* argument is
## present, and only after OS.is_debug_build() is true.  The directives and the
## runtime are loaded dynamically; no compile-time preload dependency on tools/
## exists.
func _consider_prototype_debug(arguments: PackedStringArray) -> void:
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
	var dto: Dictionary = directives_script.parse(arguments)
	if not bool(dto.get("ok", false)):
		_reject_prototype_debug("parse_failed", str(dto.get("error", "unknown_debug_flag")))
		return
	if not bool(dto.get("enabled", false)):
		return
	_root._prototype_debug_dto = dto.duplicate(true)
	_root.save_directory_path = String(dto.get("save_directory", PROTOTYPE_DEBUG_DEFAULT_SAVE_DIRECTORY))
	_root.playtest_log_directory = _root.save_directory_path.trim_suffix("/") + "/playtest"
	_root._prototype_debug_no_persist = bool(dto.get("no_persist", false))
	if bool(dto.get("has_seed", false)):
		_root._prototype_debug_has_seed = true
		_root._prototype_debug_seed_override = int(dto.get("seed", 0))


func _apply_prototype_debug_wipe() -> void:
	if _root._prototype_debug_rejected or _root._prototype_debug_dto.is_empty():
		return
	if not bool(_root._prototype_debug_dto.get("wipe", false)):
		return
	var wiped: Dictionary = _root.save_store.delete_all()
	if not bool(wiped.get("ok", false)):
		_reject_prototype_debug("wipe_failed", str(wiped.get("error", "unknown_error")))
		return
	_root.application_state.reset()


func _apply_prototype_debug_runtime() -> void:
	if _root._prototype_debug_rejected or _root._prototype_debug_dto.is_empty():
		return
	var runtime_script: Script = load(PROTOTYPE_DEBUG_RUNTIME_PATH)
	if runtime_script == null:
		_reject_prototype_debug("tool_load_failed", "could not load prototype debug runtime")
		return
	var summary: Dictionary = runtime_script.apply(_root, _root._prototype_debug_dto)
	if not bool(summary.get("ok", false)):
		_reject_prototype_debug("apply_failed", str(summary.get("error", "prototype_debug_apply_failed")))
		_root._transition(SceneRouterScript.ROUTE_TITLE)
		return
	_root.prototype_debug_summary = summary.duplicate(true)
	var forced_family := String(summary.get("force_family", "")).strip_edges()
	_root._prototype_debug_force_family = forced_family if not forced_family.is_empty() else ""
	print("PROTOTYPE_DEBUG_APPLIED %s" % JSON.stringify(_root.prototype_debug_summary))
	_root._record_playtest("prototype_debug_applied", _root.prototype_debug_summary)
	if not bool(summary.get("changed", false)):
		return
	var safe_route := SceneRouterScript.ROUTE_TITLE
	if _root.current_route == SceneRouterScript.ROUTE_BASE or _root.current_route == SceneRouterScript.ROUTE_TUTORIAL:
		safe_route = _root.current_route
	_root._persist("Prototype debug applied", safe_route)


## Rejects a debug request with a stable log line and flow_error, then isolates
## the session so the default real save directory is never touched.
func _reject_prototype_debug(reason: String, detail: String) -> void:
	if _root._prototype_debug_rejected:
		return
	_root._prototype_debug_rejected = true
	_root._prototype_debug_reject_reason = reason
	print("PROTOTYPE_DEBUG_REJECTED reason=%s detail=%s" % [reason, detail])
	_root.flow_error.emit("prototype_debug_rejected", "%s: %s" % [reason, detail])
	_root._prototype_debug_dto = {}
	_root._prototype_debug_has_seed = false
	_root._prototype_debug_seed_override = 0
	_root._prototype_debug_force_family = ""
	_root._prototype_debug_no_persist = false
	_root.save_directory_path = PROTOTYPE_DEBUG_REJECTED_SAVE_DIRECTORY
	_root.playtest_log_directory = PROTOTYPE_DEBUG_REJECTED_SAVE_DIRECTORY.path_join("playtest")
	_root.application_state.reset()
	if _root.save_store != null:
		_root.save_store = SaveStoreScript.new(PROTOTYPE_DEBUG_REJECTED_SAVE_DIRECTORY)
