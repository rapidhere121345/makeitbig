class_name GameRoot
extends Node

signal flow_route_changed(previous_route: String, current_route: String)
signal flow_error(error_code: String, detail: String)

const CharacterProgressionScript = preload("res://src/systems/character_progression.gd")
const ApplicationStateScript = preload("res://src/game/application_state.gd")
const SceneRouterScript = preload("res://src/game/scene_router.gd")
const ContractPlanScript = preload("res://src/game/contract_plan.gd")
const ContractRunControllerScript = preload("res://src/game/contract_run_controller.gd")
const ContractRoomCommitPortScript = preload("res://src/game/contract_room_commit_port.gd")
const SaveStoreScript = preload("res://src/persistence/save_store.gd")
const PlaytestLogScript = preload("res://src/game/playtest_log.gd")
const EarlyCampaignRegistryScript = preload("res://src/content/early_campaign_registry.gd")
const EarlyItemRegistryScript = preload("res://src/content/early_item_registry.gd")
const TitleScreenScript = preload("res://src/presentation/title_screen.gd")
const TutorialScreenScript = preload("res://src/presentation/tutorial_screen.gd")
const StoryScreenScript = preload("res://src/presentation/story_screen.gd")
const CharacterScreenScript = preload("res://src/presentation/character_screen.gd")
const BaseHubScreenScript = preload("res://src/presentation/base_hub_screen.gd")
const FacilityScreenScript = preload("res://src/presentation/facility_screen.gd")
const ContractScreenScript = preload("res://src/presentation/contract_screen.gd")
const ResultScreenScript = preload("res://src/presentation/result_screen.gd")
const EndingScreenScript = preload("res://src/presentation/ending_screen.gd")
const PixelStageScript = preload("res://src/presentation/pixel_stage.gd")
const PlayerFacingStatusScript = preload("res://src/presentation/player_facing_status.gd")
const TestConsoleScript = preload("res://src/presentation/test_console.gd")
const SessionMenuScript = preload("res://src/presentation/session_menu.gd")
const DisplayPolicyScript = preload("res://src/presentation/display_policy.gd")

const FACILITY_ROUTES: Array[String] = ["loadout", "forge", "training", "proxy", "immortality", "research"]
const ADAPTIVE_SHELL_ROUTES: Array[String] = [
	"loadout", "forge", "training", "proxy", "immortality", "research",
	"contract", "result", "ending", "character", "story",
]
const EARLY_SIDE_NODE_IDS: Array[String] = ["side_targeted_equipment", "side_affix_and_law_tallies"]
const AUTO_SMOKE_SETUP_NODE_IDS: Array[String] = [
	"mainline_01_first_hunt",
	"mainline_02_priority_under_pressure",
	"mainline_03_first_elite",
	"mainline_04_hazard_and_forge",
	"mainline_05_growth_gate",
]
const AUTO_SMOKE_WHITE_CORES: Array[String] = [
	"near_enemy_horizon",
	"direct_gait",
	"single_key_execution",
	"short_trace_memory",
]
const AUTO_SMOKE_SEED := 52969
const AUTO_SMOKE_TIME_SCALE := 20.0
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
const CAPTURE_STAGE_ROUTE: String = "result"
const CAPTURE_EVIDENCE_PROTOCOL: String = "mib-settlement-capture-v1"
const CAPTURE_EVIDENCE_SUFFIX: String = ".json"
## The published defeat clip may hold the result *screen*, never the result: the
## settlement, the progression, the save and the playtest record already happened
## in the same call that produced this route. This bound is the route layer's own
## clock, so a screen that never reports readiness keeps a corpse for at most
## this long.
const DEFEAT_ROUTE_FALLBACK_SECONDS: float = 1.0

const DEFAULT_SAVE_DIRECTORY: String = "user://framework-saves"
const PROTOTYPE_DEBUG_DIRECTIVES_PATH: String = "res://tools/prototype_debug_directives.gd"
const PROTOTYPE_DEBUG_RUNTIME_PATH: String = "res://tools/prototype_debug_runtime.gd"
const PROTOTYPE_DEBUG_DEFAULT_SAVE_DIRECTORY: String = "user://makeitbig-prototype-debug"
const PROTOTYPE_DEBUG_REJECTED_SAVE_DIRECTORY: String = "user://makeitbig-prototype-debug-rejected"
const PROTOTYPE_DEBUG_FORCED_DROP_TAG: String = "equipment_general"
const LOADOUT_PARAMETER_KEYS: Array[String] = ["p", "T", "v", "d", "turn", "damage", "max_health"]
const SLOT_LABELS := {
	"main_hand": "Main Hand", "off_hand": "Off Hand", "gloves": "Gloves", "ring": "Ring",
	"head": "Head", "chest": "Chest", "legs": "Legs", "feet": "Feet",
	"wrists": "Wrists", "belt": "Belt", "ring_2": "Ring 2", "neck": "Necklace",
}
const PRESET_LABELS := {"convergent": "Convergent", "critical": "Critical", "exponential": "Exponential"}
const DEFAULT_CONTRACT: Dictionary = {
	"contract_id": "first_contract",
	"mode": "Manual",
	"preset_id": "convergent",
	"seed": 52969,
	"room_count": 1,
}

@export var save_directory_path: String = DEFAULT_SAVE_DIRECTORY
@export var playtest_log_directory: String = PlaytestLogScript.DEFAULT_DIRECTORY
@export var playtest_logging_enabled: bool = true

## Tests and future encounter implementations may provide a zero-argument
## factory before this node enters the tree. The returned node must expose
## start_session(config) plus completed(result) and abandoned(result) signals.
var room_runtime_factory: Callable
## Called as (exit_code, reason) when set; invalid means the real get_tree().quit.
var exit_code_hook: Callable
var application_state
var scene_router
var save_store
var playtest_log

var current_route: String:
	get:
		return SceneRouterScript.ROUTE_BOOT if scene_router == null else String(scene_router.current_route)

var current_screen: Node:
	get:
		return _current_screen

var last_contract: Dictionary:
	get:
		return _last_contract.duplicate(true)

var _current_screen: Node
## Town browsing is transient presentation state, separate from the save schema.
var _town_travel: Dictionary = {}
var _pixel_stage: Control
var _test_console: CanvasLayer
var _session_menu: CanvasLayer
var _menu_paused_screen: Node
var _menu_previous_process_mode: int = Node.PROCESS_MODE_INHERIT
var _effects_volume := 0.45
var _windowed_resolution := Vector2i(1600, 900)
## Test hook: pretends the screen has this usable size. ZERO means ask the OS.
var usable_display_override := Vector2i.ZERO
var _settings_loaded := false
var _stage_window: Window
## Multiple mounted roots occur in tests and tooling. Share the window lease so
## one exiting root cannot restore stretch underneath another live pixel stage.
static var _stage_window_leases: Dictionary = {}
var _last_contract: Dictionary = {}
## The result screen waiting for a defeat clip that is still playing on the arena
## screen, plus how it was released. The settlement is never part of this state.
var _pending_visual_route: Dictionary = {}
var _pending_route_release_reason: String = ""
var _status_message: String = ""
## A facility reached from settlement keeps its return destination while domain
## actions re-present that same screen. The one-shot drop focus remains in the
## transition payload; this value only preserves truthful navigation copy.
var _facility_return_route: String = SceneRouterScript.ROUTE_BASE
var _test_session: bool = false
var _auto_smoke_session: bool = false
var _auto_smoke_stage: String = ""
var _auto_smoke_state_hash_output_path: String = ""
var _auto_smoke_boss_result: Dictionary = {}
var _auto_smoke_settlement_count := 0
var _auto_smoke_previous_time_scale := 1.0
var _auto_smoke_finished := false
var _capture_request: Dictionary = {}
var _initialized: bool = false
var _playtest_session_started_msec := 0
var _playtest_profile_started_msec := 0
var _playtest_route_entered_msec := 0
var _presentation_enabled := true
var _prototype_debug_dto: Dictionary = {}
var _prototype_debug_rejected := false
var _prototype_debug_reject_reason := ""
var _prototype_debug_no_persist := false
var _prototype_debug_has_seed := false
var _prototype_debug_seed_override := 0
var _prototype_debug_force_family := ""
var prototype_debug_summary: Dictionary = {}


func _enter_tree() -> void:
	if _pixel_stage != null:
		_acquire_stage_window()


func _ready() -> void:
	_ensure_pixel_stage()
	initialize()
	_ensure_test_console()
	_ensure_session_menu()
	# Some tests prepare the route before entering the SceneTree. Keep that
	# supported, but once mounted use the same logical viewport as normal play.
	if _current_screen != null and _current_screen.get_parent() == self:
		_apply_presentation_policy(current_route)
		_current_screen.reparent(get_presentation_viewport())


func _ensure_pixel_stage() -> void:
	if _pixel_stage != null or not is_inside_tree():
		return
	# Only the graphical GameRoot owns the outer window's stretch policy. Keep
	# standalone screen fixtures and headless simulation on their existing 1280
	# project canvas (the headless OS window itself defaults to a tiny 64x64).
	_acquire_stage_window()
	_pixel_stage = PixelStageScript.new()
	_pixel_stage.name = "PixelStage"
	add_child(_pixel_stage)
	_pixel_stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## Test and verification metadata has one opt-in home. The console lives on the
## root viewport rather than inside a routed SubViewport, so changing routes or
## presentation policies cannot duplicate it. It is hidden and does not query a
## snapshot until the tester presses F10.
func _ensure_test_console() -> void:
	if _test_console != null or not is_inside_tree():
		return
	_test_console = TestConsoleScript.new()
	_test_console.name = "TestConsole"
	_test_console.layer = 100
	add_child(_test_console)
	_test_console.call("configure", Callable(self, "_test_console_snapshot"))


func get_test_console() -> CanvasLayer:
	return _test_console


func get_session_menu() -> CanvasLayer:
	return _session_menu


func _ensure_session_menu() -> void:
	if _session_menu != null or not is_inside_tree():
		return
	_session_menu = SessionMenuScript.new()
	_session_menu.name = "SessionMenu"
	# The console gets first refusal on Escape when it is open.
	add_child(_session_menu)
	move_child(_session_menu, _test_console.get_index() if _test_console != null else 0)
	_session_menu.opened.connect(_pause_current_route)
	_session_menu.resumed.connect(_resume_current_route)
	_session_menu.abandon_requested.connect(_abandon_from_menu)
	_session_menu.display_requested.connect(_apply_display_settings)
	_session_menu.effects_volume_changed.connect(_set_effects_volume)
	_load_player_settings()
	_session_menu.set_route(current_route)
	_session_menu.set_resolution_options(DisplayPolicyScript.menu_options(_usable_display_size(), _windowed_resolution), _windowed_resolution)
	_session_menu.sync_settings(_windowed_resolution, get_window().mode == Window.MODE_FULLSCREEN, _effects_volume)
	_apply_route_preferences()


func _pause_current_route() -> void:
	if _current_screen == null or not is_instance_valid(_current_screen):
		return
	_menu_paused_screen = _current_screen
	_menu_previous_process_mode = _current_screen.process_mode
	if _current_screen.has_method("release_manual_controls"):
		_current_screen.call("release_manual_controls")
	# This stops the fixed clock at the route boundary. Time spent paused is not
	# added to it, and other mounted roots/test fixtures keep their own lifetime.
	_current_screen.process_mode = Node.PROCESS_MODE_DISABLED


func _resume_current_route() -> void:
	if is_instance_valid(_menu_paused_screen):
		if _menu_paused_screen.has_method("release_manual_controls"):
			_menu_paused_screen.call("release_manual_controls")
		_menu_paused_screen.process_mode = _menu_previous_process_mode
	_menu_paused_screen = null


func _abandon_from_menu() -> void:
	if current_route == SceneRouterScript.ROUTE_ARENA and _current_screen != null and _current_screen.has_method("request_abandon"):
		_current_screen.call("request_abandon")


func _set_effects_volume(value: float) -> void:
	_effects_volume = clampf(value, 0.0, 1.0)
	_apply_route_preferences()
	_save_player_settings()


func _apply_route_preferences() -> void:
	if _current_screen != null and _current_screen.has_method("set_effects_volume"):
		_current_screen.call("set_effects_volume", _effects_volume)


## Usable size of the current screen, or ZERO (no upper bound) when it is unknown.
func _usable_display_size() -> Vector2i:
	if usable_display_override != Vector2i.ZERO:
		return usable_display_override
	if DisplayServer.get_name().to_lower().contains("headless"):
		return Vector2i.ZERO
	return DisplayServer.screen_get_usable_rect(get_window().current_screen).size


func _apply_display_settings(resolution: Vector2i, fullscreen: bool) -> void:
	var usable := _usable_display_size()
	if resolution.x <= 0 or resolution.y <= 0:
		return
	resolution = DisplayPolicyScript.fit_window(resolution, usable)
	_windowed_resolution = resolution
	var window := get_window()
	if not DisplayServer.get_name().to_lower().contains("headless"):
		window.min_size = DisplayPolicyScript.MIN_WINDOW
		window.mode = Window.MODE_FULLSCREEN if fullscreen else Window.MODE_WINDOWED
		if not fullscreen:
			var origin := DisplayServer.screen_get_usable_rect(window.current_screen).position
			window.size = resolution
			window.position = origin + (usable - resolution) / 2
	if _session_menu != null:
		_session_menu.set_resolution_options(DisplayPolicyScript.menu_options(usable, resolution), resolution)
		_session_menu.sync_settings(resolution, fullscreen, _effects_volume)
	_save_player_settings(fullscreen)


func _load_player_settings() -> void:
	if _settings_loaded or _test_session:
		return
	_settings_loaded = true
	var config := ConfigFile.new()
	if config.load(save_directory_path.path_join("display.cfg")) != OK:
		_apply_display_settings(_windowed_resolution, false)
		return
	var volume: Variant = config.get_value("audio", "effects", 0.45)
	if (volume is float or volume is int) and is_finite(float(volume)):
		_effects_volume = clampf(float(volume), 0.0, 1.0)
	_windowed_resolution = DisplayPolicyScript.parse_saved(
		config.get_value("display", "window", _windowed_resolution), _usable_display_size(), _windowed_resolution)
	var fullscreen: Variant = config.get_value("display", "fullscreen", false)
	_apply_display_settings(_windowed_resolution, fullscreen == true)


func _save_player_settings(fullscreen: Variant = null) -> void:
	if _test_session or not is_inside_tree():
		return
	var config := ConfigFile.new()
	config.set_value("audio", "effects", _effects_volume)
	config.set_value("display", "window", _windowed_resolution)
	config.set_value("display", "fullscreen", get_window().mode == Window.MODE_FULLSCREEN if fullscreen == null else fullscreen)
	var directory := ProjectSettings.globalize_path(save_directory_path)
	if DirAccess.make_dir_recursive_absolute(directory) == OK:
		config.save(directory.path_join("display.cfg"))


func _refresh_test_console() -> void:
	if _test_console != null \
		and _test_console.has_method("is_console_open") \
		and bool(_test_console.call("is_console_open")):
		_test_console.call("refresh")


## Raw ids, fingerprints, deterministic seeds, protocol unions and settlement
## payloads are useful to testers but are not game copy. Screens keep the human
## reading; F10 exposes this exact snapshot when a reproduction needs it.
func _test_console_snapshot() -> Dictionary:
	var window_size := Vector2i.ZERO
	if is_inside_tree() and get_window() != null:
		window_size = get_window().size
	var layout: Dictionary = _pixel_stage.call("layout_snapshot") if _pixel_stage != null else {}
	var logical_size: Vector2i = layout.get("ui_logic_size", Vector2i(1280, 720))
	var snapshot := {
		"route": current_route,
		"window_resolution": "%d × %d" % [window_size.x, window_size.y],
		"logical_resolution": "%d × %d · %s · %.3fx" % [
			logical_size.x,
			logical_size.y,
			String(layout.get("policy", "unmounted")),
			float(layout.get("ui_scale", 1.0)),
		],
		"build_id": "profile-schema-%d · Godot %s" % [
			ApplicationStateScript.SCHEMA_VERSION,
			String(Engine.get_version_info().get("string", "unknown")),
		],
		"test_flags": {
			"test_session": _test_session,
			"auto_smoke": _auto_smoke_session,
			"capture": not _capture_request.is_empty(),
			"prototype_debug": not _prototype_debug_dto.is_empty(),
			"presentation_enabled": _presentation_enabled,
		},
		"log_path": playtest_log.call("log_path") if playtest_log != null and playtest_log.has_method("log_path") else "",
		"sections": [
			{"title": "Full current contract data", "content": _last_contract.duplicate(true)},
			{"title": "Presentation layout", "content": layout.duplicate(true)},
		],
	}
	if application_state == null or not application_state.has_profile():
		snapshot["profile_id"] = "No profile created"
		snapshot["last_settlement_raw"] = {}
		return snapshot
	var profile_snapshot: Dictionary = application_state.profile
	var progression: Dictionary = profile_snapshot.get("progression", {}) if profile_snapshot.get("progression", null) is Dictionary else {}
	snapshot["profile_id"] = "%s · wins=%d · auto=%d" % [
		String(profile_snapshot.get("initial_class", "unknown")),
		int(progression.get("contract_wins", 0)),
		int(progression.get("auto_contract_wins", 0)),
	]
	var resolved: Dictionary = application_state.resolved_build_snapshot()
	var fingerprint := String(resolved.get("build_fingerprint", ""))
	var training: Dictionary = profile_snapshot.get("training", {}) if profile_snapshot.get("training", null) is Dictionary else {}
	var reports: Dictionary = training.get("reports_by_fingerprint", {}) if training.get("reports_by_fingerprint", null) is Dictionary else {}
	var matched_report: Dictionary = reports.get(fingerprint, {}) if reports.get(fingerprint, null) is Dictionary else {}
	snapshot["training_report"] = matched_report.duplicate(true)
	snapshot["raw_report"] = {
		"build_fingerprint": fingerprint,
		"matched_report": matched_report.duplicate(true),
		"reports_by_fingerprint": reports.duplicate(true),
	}
	var proxy_snapshot: Dictionary = application_state.resolved_proxy_build_snapshot()
	var resolved_proxy: Dictionary = proxy_snapshot.get("resolved_proxy_build", {}) if proxy_snapshot.get("resolved_proxy_build", null) is Dictionary else {}
	snapshot["proxy_protocol"] = resolved_proxy.duplicate(true)
	snapshot["proxy_fingerprint"] = String(resolved_proxy.get("semantic_fingerprint", ""))
	snapshot["last_settlement_raw"] = application_state.last_result.duplicate(true)
	(snapshot["sections"] as Array).append({"title": "Full current build data", "content": resolved.duplicate(true)})
	(snapshot["sections"] as Array).append({
		"title": "Raw profile equipment and proxy data",
		"content": {
			"active_build": (profile_snapshot.get("active_build", {}) as Dictionary).duplicate(true) if profile_snapshot.get("active_build", null) is Dictionary else {},
			"inventory": (profile_snapshot.get("inventory", {}) as Dictionary).duplicate(true) if profile_snapshot.get("inventory", null) is Dictionary else {},
			"proxy_build": (profile_snapshot.get("proxy_build", {}) as Dictionary).duplicate(true) if profile_snapshot.get("proxy_build", null) is Dictionary else {},
		},
	})
	return snapshot


func _acquire_stage_window() -> void:
	if _stage_window != null or DisplayServer.get_name().to_lower().contains("headless") or get_viewport() != get_window():
		return
	_stage_window = get_window()
	var id := _stage_window.get_instance_id()
	if not _stage_window_leases.has(id):
		_stage_window_leases[id] = {"count": 0, "previous_mode": _stage_window.content_scale_mode}
	_stage_window_leases[id]["count"] += 1
	_stage_window.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED


func _release_stage_window() -> void:
	if _stage_window == null or not is_instance_valid(_stage_window):
		_stage_window = null
		return
	var id := _stage_window.get_instance_id()
	if _stage_window_leases.has(id):
		_stage_window_leases[id]["count"] -= 1
		if int(_stage_window_leases[id]["count"]) == 0:
			_stage_window.content_scale_mode = int(_stage_window_leases[id]["previous_mode"])
			_stage_window_leases.erase(id)
	_stage_window = null


## Pixel-authored routes use a fixed 1280x720 canvas. Information-heavy shell
## routes may use a larger logical viewport; the arena's authoritative rectangle
## remains fixed regardless of either presentation policy.
func get_presentation_viewport() -> Viewport:
	return get_viewport() if _pixel_stage == null else _pixel_stage.get_presentation_viewport()


func get_pixel_stage() -> Control:
	return _pixel_stage


func _mount_screen(screen: Node) -> void:
	_ensure_pixel_stage()
	if _pixel_stage == null:
		add_child(screen)
	else:
		get_presentation_viewport().add_child(screen)


func _apply_presentation_policy(route: String) -> void:
	if _pixel_stage == null:
		return
	var policy := PixelStageScript.POLICY_ADAPTIVE_SHELL if route in ADAPTIVE_SHELL_ROUTES else PixelStageScript.POLICY_FIXED_PIXEL
	_pixel_stage.set_presentation_policy(policy)


func _exit_tree() -> void:
	_resume_current_route()
	_finish_playtest_logging("tree_exit")
	_release_stage_window()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_finish_playtest_logging("object_freed")
	elif what == NOTIFICATION_WM_WINDOW_FOCUS_OUT and not _test_session \
			and current_route == SceneRouterScript.ROUTE_ARENA and _session_menu != null:
		_session_menu.open_menu()


## Drives the deferred result screen. Nothing authoritative happens here: the
## only work is asking the mounted screen whether its defeat clip is done and
## enforcing this layer's own fallback bound.
func _process(delta: float) -> void:
	if _session_menu != null and _session_menu.is_open():
		return
	if _pending_visual_route.is_empty():
		return
	var elapsed: float = float(_pending_visual_route.get("seconds", 0.0)) + maxf(0.0, delta)
	_pending_visual_route["seconds"] = elapsed
	var ready := not _defeat_window_holds_screen(_pending_visual_route.get("payload", {}))
	if not ready and elapsed < DEFEAT_ROUTE_FALLBACK_SECONDS:
		return
	_release_pending_visual_route("ready" if ready else "fallback")


func initialize(arguments: PackedStringArray = OS.get_cmdline_user_args()) -> void:
	if _initialized:
		return
	_initialized = true
	if application_state == null:
		application_state = ApplicationStateScript.new()
	if scene_router == null:
		scene_router = SceneRouterScript.new()
	_parse_presentation_flag(arguments)
	_consider_prototype_debug(arguments)
	if save_store == null:
		save_store = SaveStoreScript.new(save_directory_path)
	_apply_prototype_debug_wipe()
	if not scene_router.route_changed.is_connected(_on_route_changed):
		scene_router.route_changed.connect(_on_route_changed)
	var capture_path := ""
	for argument: String in arguments:
		if argument.begins_with("--state-hash-out="):
			_auto_smoke_state_hash_output_path = argument.trim_prefix("--state-hash-out=")
	var request: Dictionary = capture_request_report(arguments)
	if not bool(request.get("ok", false)):
		_capture_contract_fail(request)
		return
	_capture_request = request
	capture_path = String(request.get("capture_path", ""))
	_auto_smoke_session = arguments.has("--auto-smoke")
	_test_session = _auto_smoke_session or arguments.has("--smoke") or arguments.has("--game-flow-smoke") or not capture_path.is_empty()
	if playtest_logging_enabled and not _test_session and not arguments.has("--no-playtest-log") and not _prototype_debug_no_persist:
		_start_playtest_logging()
	if _auto_smoke_session:
		_auto_smoke_previous_time_scale = Engine.time_scale
		Engine.time_scale = AUTO_SMOKE_TIME_SCALE
	_bootstrap(arguments)
	_apply_prototype_debug_runtime()
	if not String(request.get("capture_route", "")).is_empty():
		if not _apply_capture_request(request):
			return
	if not capture_path.is_empty() and _capture_stage().is_empty():
		_capture_frame.call_deferred(capture_path, String(request.get("capture_route", "")))
	elif arguments.has("--smoke"):
		_run_scene_smoke.call_deferred()


func start_new_game(initial_class: String = "ranger") -> Dictionary:
	if current_route != SceneRouterScript.ROUTE_TITLE:
		return _failure("wrong_route")
	var created: Dictionary = application_state.start_new_profile(initial_class)
	if not bool(created.get("ok", false)):
		_present_title(String(created.get("error", "profile_creation_failed")))
		return created
	_last_contract.clear()
	_playtest_profile_started_msec = Time.get_ticks_msec()
	_record_playtest("profile_started", {"initial_class": String(application_state.profile.get("initial_class", initial_class))})
	_status_message = _persist("New profile saved", SceneRouterScript.ROUTE_TUTORIAL)
	return _transition(SceneRouterScript.ROUTE_TUTORIAL)


func continue_game() -> Dictionary:
	if current_route != SceneRouterScript.ROUTE_TITLE:
		return _failure("wrong_route")
	if not application_state.has_profile():
		_present_title("No valid profile is available.")
		return _failure("profile_required")
	var profile: Dictionary = application_state.profile
	return _transition(SceneRouterScript.ROUTE_BASE if bool(profile.get("tutorial_complete", false)) else SceneRouterScript.ROUTE_TUTORIAL)


func complete_tutorial() -> Dictionary:
	if current_route != SceneRouterScript.ROUTE_TUTORIAL:
		return _failure("wrong_route")
	var completed: Dictionary = application_state.complete_tutorial()
	if not bool(completed.get("ok", false)):
		return completed
	_record_playtest("tutorial_completed", {"initial_class": String(application_state.profile.get("initial_class", ""))})
	_status_message = _persist("Ranger basics tutorial complete", SceneRouterScript.ROUTE_BASE)
	return _transition(SceneRouterScript.ROUTE_BASE)


func open_contract() -> Dictionary:
	if current_route != SceneRouterScript.ROUTE_BASE:
		return _failure("wrong_route")
	_status_message = ""
	return _transition(SceneRouterScript.ROUTE_CONTRACT)


func open_story() -> Dictionary:
	if current_route != SceneRouterScript.ROUTE_BASE: return _failure("wrong_route")
	return _transition(SceneRouterScript.ROUTE_STORY)


func read_story_entry(entry_id: String) -> Dictionary:
	if current_route != SceneRouterScript.ROUTE_STORY: return _failure("wrong_route")
	var result: Dictionary = application_state.mark_story_read(entry_id)
	if bool(result.get("ok",false)): _persist("Observation recorded.", SceneRouterScript.ROUTE_BASE)
	return result


func read_town_conversation(entry_id: String) -> Dictionary:
	if current_route != SceneRouterScript.ROUTE_BASE: return _failure("wrong_route")
	var available := false
	for conversation: Dictionary in application_state.story_snapshot().get("available_conversations", []):
		if String(conversation.id) == entry_id: available = true
	if not available: return _failure("story_entry_unavailable")
	var result: Dictionary = application_state.mark_story_read(entry_id)
	if bool(result.get("ok", false)):
		_persist("", SceneRouterScript.ROUTE_BASE)
		_current_screen.present_adventure(application_state.character_snapshot(), application_state.story_snapshot())
	return result



func open_character() -> Dictionary:
	if current_route != SceneRouterScript.ROUTE_BASE: return _failure("wrong_route")
	return _transition(SceneRouterScript.ROUTE_CHARACTER)


func close_adventure_page() -> Dictionary:
	if current_route not in [SceneRouterScript.ROUTE_CHARACTER, SceneRouterScript.ROUTE_STORY]: return _failure("wrong_route")
	return _transition(SceneRouterScript.ROUTE_BASE)


func change_character_talent(action: String, value: String = "") -> Dictionary:
	if current_route != SceneRouterScript.ROUTE_CHARACTER: return _failure("wrong_route")
	var result: Dictionary = application_state.change_talent(action, value)
	var message := ""
	if not bool(result.get("ok",false)):
		message = "Invalid allocation: check available points, tier investment, and keystone count."
	else:
		message = _persist("", SceneRouterScript.ROUTE_BASE)
	_current_screen.present(application_state.growth_snapshot(), message)
	return result



func open_facility(route: String) -> Dictionary:
	if current_route != SceneRouterScript.ROUTE_BASE:
		return _failure("wrong_route")
	if route not in FACILITY_ROUTES or route == SceneRouterScript.ROUTE_RESEARCH:
		return _failure("unknown_facility")
	if route == SceneRouterScript.ROUTE_FORGE:
		var forge_context: Dictionary = application_state.forge_ensure_context()
		if not bool(forge_context.get("ok", false)):
			return forge_context
	_status_message = ""
	return _transition(route)


func leave_facility() -> Dictionary:
	if current_route not in FACILITY_ROUTES:
		return _failure("wrong_route")
	return _transition(SceneRouterScript.ROUTE_BASE)


func request_facility_action(facility_id: String, action_id: String, payload: Dictionary = {}) -> Dictionary:
	var normalized_facility := facility_id.strip_edges().to_lower()
	if normalized_facility not in FACILITY_ROUTES:
		return _failure("unknown_facility")
	if current_route != normalized_facility:
		return _failure("wrong_route")
	if normalized_facility == SceneRouterScript.ROUTE_LOADOUT and action_id in ["equip_item", "unequip_item", "salvage_item"]:
		var before: Dictionary = _loadout_telemetry_snapshot() if action_id in ["equip_item", "unequip_item"] else {}
		var subject := String(payload.get("instance_id", payload.get("slot", "")))
		var subject_item := _owned_equipment_for_telemetry(String(payload.get("instance_id", "")))
		if action_id == "unequip_item":
			var slot := String(payload.get("slot", ""))
			subject_item = _equipped_item_for_slot(slot)
		var subject_label := _equipment_label(subject_item, _slot_label(String(payload.get("slot", ""))))
		var action_label := "Salvage" if action_id == "salvage_item" else ("Unequip item" if action_id == "unequip_item" else "Equip item")
		var changed: Dictionary
		if action_id == "equip_item":
			changed = application_state.equip_item(String(payload.get("instance_id", "")))
		elif action_id == "unequip_item":
			changed = application_state.unequip_item(String(payload.get("slot", "")))
		else:
			changed = application_state.salvage_item(String(payload.get("instance_id", "")))
		if not bool(changed.get("ok", false)):
			_status_message = PlayerFacingStatusScript.failure(action_label, String(changed.get("error", "unknown_error")))
			_present_facility(normalized_facility, _status_message)
			return changed
		if action_id == "salvage_item":
			_record_playtest("item_salvaged", {
				"instance_id": subject,
				"operation": String(changed.get("operation", "")),
				"amount": int(changed.get("amount", 0)),
			})
			_status_message = _persist("Salvaged: %s -> %s Law Tokens x%d" % [subject_label, _law_tally_label(String(changed.get("operation", ""))), int(changed.get("amount", 0))], SceneRouterScript.ROUTE_BASE)
		else:
			_record_playtest("loadout_changed", _build_loadout_telemetry(action_id, subject, before))
			_status_message = _persist("%s: %s" % ["Unequipped" if action_id == "unequip_item" else "Equipped", subject_label], SceneRouterScript.ROUTE_BASE)
		_present_facility(normalized_facility, _status_message)
		return changed
	if normalized_facility == SceneRouterScript.ROUTE_LOADOUT and action_id == "select_ranger_build":
		var selected: Dictionary = application_state.select_ranger_build(String(payload.get("preset_id", "")))
		if not bool(selected.get("ok", false)):
			_status_message = PlayerFacingStatusScript.failure("Switch Build", String(selected.get("error", "unknown_error")))
			_present_facility(normalized_facility, _status_message)
			return selected
		_status_message = _persist("Build switched: %s" % _preset_label(String(payload.get("preset_id", ""))), SceneRouterScript.ROUTE_BASE)
		var selected_resolved: Dictionary = application_state.resolved_build_snapshot()
		_record_playtest("loadout_changed", {
			"action": "select_ranger_build",
			"subject": String(payload.get("preset_id", "")),
			"build_fingerprint": String(selected_resolved.get("build_fingerprint", "")),
		})
		_present_facility(normalized_facility, _status_message)
		return selected
	if normalized_facility == SceneRouterScript.ROUTE_TRAINING and action_id == "run_training_trial":
		var trial: Dictionary = application_state.run_training_trial()
		if not bool(trial.get("ok", false)):
			_status_message = PlayerFacingStatusScript.failure("Training", String(trial.get("error", "unknown_error")))
			_present_facility(normalized_facility, _status_message)
			return trial
		_status_message = _persist("Training dummy trial complete", SceneRouterScript.ROUTE_BASE)
		var trial_report: Dictionary = trial.get("report", {}) if trial.get("report", {}) is Dictionary else {}
		var trial_resolved: Dictionary = application_state.resolved_build_snapshot()
		_record_playtest("training_completed", {
			"build_fingerprint": String(trial_report.get("build_fingerprint", "")),
			"training_seed": int(trial_report.get("training_seed", 0)),
			"p": float(trial_report.get("p", 0.0)),
			"R": float(trial_report.get("R", 0.0)),
			"growth_classification": String(trial_report.get("state", "")),
			"growth_curve": (trial_report.get("growth_curve", []) as Array).duplicate(true) if trial_report.get("growth_curve", []) is Array else [],
			"action": String(trial_report.get("action", "")),
			"missing_interfaces": (trial_resolved.get("missing_interfaces", []) as Array).duplicate(true) if trial_resolved.get("missing_interfaces", []) is Array else [],
		})
		_present_facility(normalized_facility, _status_message)
		return trial
	if normalized_facility == SceneRouterScript.ROUTE_PROXY and action_id in ["equip_proxy_core", "configure_proxy_core"]:
		var core_id := String(payload.get("core_id", "")).strip_edges()
		var changed: Dictionary
		if action_id == "equip_proxy_core":
			changed = application_state.equip_proxy_core(core_id)
		else:
			var settings_value: Variant = payload.get("settings", {})
			changed = application_state.configure_proxy_core(core_id, (settings_value as Dictionary).duplicate(true) if settings_value is Dictionary else {})
		if not bool(changed.get("ok", false)):
			var proxy_action := "Install proxy core" if action_id == "equip_proxy_core" else "Adjust proxy core"
			_status_message = PlayerFacingStatusScript.failure(proxy_action, String(changed.get("error", "unknown_error")))
			_present_facility(normalized_facility, _status_message)
			return changed
		var core_label := _proxy_core_label(core_id)
		if action_id == "equip_proxy_core":
			_status_message = _persist("Proxy core installed: %s" % core_label, SceneRouterScript.ROUTE_BASE)
		else:
			var band := String((payload.get("settings", {}) as Dictionary).get("distance_band", "")) if payload.get("settings", {}) is Dictionary else ""
			var band_label: String = String({"near": "Near", "mid": "Mid", "far": "Far"}.get(band, band))
			_status_message = _persist("%s distance band set to: %s" % [core_label, band_label], SceneRouterScript.ROUTE_BASE)
		_record_playtest("proxy_build_changed", {
			"action": action_id,
			"core_id": core_id,
			"settings": (payload.get("settings", {}) as Dictionary).duplicate(true) if payload.get("settings", {}) is Dictionary else {},
			"proxy_build_fingerprint": String((changed.get("resolved_proxy_build", {}) as Dictionary).get("semantic_fingerprint", "")),
		})
		_present_facility(normalized_facility, _status_message)
		return changed
	if normalized_facility == SceneRouterScript.ROUTE_FORGE and action_id == "select_forge_item":
		var selected_id := String(payload.get("instance_id", "")).strip_edges()
		var selected: Dictionary = application_state.forge_select_target(selected_id, int(payload.get("revision", -1)))
		if not bool(selected.get("ok", false)):
			_status_message = PlayerFacingStatusScript.failure("Select Forge Target", String(selected.get("error", "unknown_error")))
			_present_facility(normalized_facility, _status_message)
			return selected
		var selected_snapshot: Dictionary = application_state.forge_snapshot()
		_status_message = "Forge target selected: %s" % String((selected_snapshot.target_item as Dictionary).get("base_name", selected_id))
		_present_facility(normalized_facility, _status_message)
		return {"ok": true, "instance_id": selected_id, "snapshot": selected_snapshot.duplicate(true)}
	if normalized_facility == SceneRouterScript.ROUTE_FORGE and action_id == "select_forge_operation":
		var selected_operation: Dictionary = application_state.forge_select_operation(String(payload.get("operation", "")), int(payload.get("revision", -1)))
		return _finish_forge_action(normalized_facility, selected_operation, "")
	if normalized_facility == SceneRouterScript.ROUTE_FORGE and action_id == "forge_reveal":
		var revealed: Dictionary = application_state.forge_reveal(int(payload.get("limit", 8)), int(payload.get("revision", -1)))
		return _finish_forge_action(normalized_facility, revealed, "Law Token forecast complete")
	if normalized_facility == SceneRouterScript.ROUTE_FORGE and action_id == "forge_reveal_more":
		var revealed_more: Dictionary = application_state.forge_reveal_more(String(payload.get("session_id", "")), int(payload.get("limit", 8)))
		return _finish_forge_action(normalized_facility, revealed_more, "Law Token forecast expanded")
	if normalized_facility == SceneRouterScript.ROUTE_FORGE and action_id == "forge_select_candidate":
		var selected_candidate: Dictionary = application_state.forge_select_candidate(String(payload.get("session_id", "")), String(payload.get("candidate_id", "")))
		return _finish_forge_action(normalized_facility, selected_candidate, "Future candidate selected")
	if normalized_facility == SceneRouterScript.ROUTE_FORGE and action_id == "forge_cancel":
		var cancelled: Dictionary = application_state.forge_cancel(String(payload.get("session_id", "")))
		return _finish_forge_action(normalized_facility, cancelled, "Forge forecast cancelled")
	if normalized_facility != SceneRouterScript.ROUTE_FORGE or action_id != "forge_commit":
		_status_message = PlayerFacingStatusScript.failure("This facility action", "action_unavailable")
		_present_facility(normalized_facility, _status_message)
		return _failure("action_unavailable")
	var prepared: Dictionary = application_state.forge_prepare_commit(String(payload.get("session_id", "")))
	if not bool(prepared.get("ok", false)):
		return _finish_forge_action(normalized_facility, prepared, "")
	var commit_token := String(prepared.commit_token)
	if not _test_session and not _prototype_debug_no_persist:
		var saved: Dictionary = save_store.save((prepared.next_payload as Dictionary).duplicate(true))
		if not bool(saved.get("ok", false)):
			application_state.forge_abort_commit(commit_token)
			var detail := String(saved.get("error", "unknown error"))
			flow_error.emit("save_failed", detail)
			return _forge_action_failure(normalized_facility, "save_failed", detail)
	var committed: Dictionary = application_state.forge_finalize_commit(commit_token)
	if not bool(committed.get("ok", false)):
		return _finish_forge_action(normalized_facility, committed, "")
	var result_value: Variant = committed.get("candidate", {})
	var result: Dictionary = result_value if result_value is Dictionary else {}
	var committed_view: Dictionary = application_state.forge_snapshot()
	var committed_target: Dictionary = (committed_view.get("target_item", {}) as Dictionary) if bool(committed_view.get("ok", false)) else {}
	var raw_result_item: Dictionary = result.get("result_item", {}) as Dictionary
	var item_label := _equipment_label(committed_target, _equipment_label(raw_result_item, "Selected item"))
	var family_label := String(result.get("family_name", "")).strip_edges()
	if family_label.is_empty():
		family_label = "Selected affix"
	_status_message = "Forged: %s gained %s tier %d, costing %d %s Law Tokens" % [
		item_label, family_label,
		int(result.get("tier", 0)), int(committed.get("cost", 0)), _law_tally_label(String(committed.get("operation", ""))),
	]
	_record_playtest("forge_committed", {
		"instance_id": String((result.result_item as Dictionary).get("instance_id", "")),
		"operation": String(committed.get("operation", "")),
		"family_id": String(result.get("family_id", "")),
		"tier": int(result.get("tier", 0)),
		"cost": int(committed.get("cost", 0)),
	})
	_present_facility(normalized_facility, _status_message)
	return committed


func _finish_forge_action(facility_id: String, result: Dictionary, success_message: String) -> Dictionary:
	_status_message = success_message if bool(result.get("ok", false)) else PlayerFacingStatusScript.failure("Forge", String(result.get("error", "unknown_error")))
	_present_facility(facility_id, _status_message)
	return result


func _forge_action_failure(facility_id: String, error: String, detail: String = "") -> Dictionary:
	var result := _failure(error)
	if not detail.is_empty():
		result["detail"] = detail
	return _finish_forge_action(facility_id, result, "")


func _law_tally_label(operation: String) -> String:
	match operation:
		"inscribe":
			return "Inscribe"
		"rewrite":
			return "Rewrite"
		"refine":
			return "Refine"
	return operation


func _equipment_label(item: Dictionary, fallback: String = "Selected item") -> String:
	var label := String(item.get("base_name", item.get("name", ""))).strip_edges()
	return label if not label.is_empty() else fallback


func _slot_label(slot: String) -> String:
	return String(SLOT_LABELS.get(slot, "Selected slot"))


func _preset_label(preset_id: String) -> String:
	return String(PRESET_LABELS.get(preset_id, "Current preset"))


func _proxy_core_label(core_id: String) -> String:
	var snapshot: Dictionary = application_state.early_game_snapshot()
	var proxy_value: Variant = snapshot.get("proxy", {})
	var proxy: Dictionary = proxy_value if proxy_value is Dictionary else {}
	var catalog_value: Variant = proxy.get("catalog", {})
	var catalog: Dictionary = catalog_value if catalog_value is Dictionary else {}
	var core_value: Variant = catalog.get(core_id, {})
	var core: Dictionary = core_value if core_value is Dictionary else {}
	var label := String(core.get("name", "")).strip_edges()
	return label if not label.is_empty() else core_id


func _equipped_item_for_slot(slot: String) -> Dictionary:
	var profile: Dictionary = application_state.profile
	var active_value: Variant = profile.get("active_build", {})
	var active: Dictionary = active_value if active_value is Dictionary else {}
	var equipped_value: Variant = active.get("equipped_item_ids", {})
	var equipped: Dictionary = equipped_value if equipped_value is Dictionary else {}
	return _owned_equipment_for_telemetry(String(equipped.get(slot, "")))


func _owned_equipment_for_telemetry(instance_id: String) -> Dictionary:
	var inventory_value: Variant = application_state.profile.get("inventory", {})
	var inventory: Dictionary = inventory_value if inventory_value is Dictionary else {}
	var equipment_value: Variant = inventory.get("equipment", [])
	if not equipment_value is Array:
		return {}
	for item_value in equipment_value:
		if item_value is Dictionary and String((item_value as Dictionary).get("instance_id", "")) == instance_id:
			return (item_value as Dictionary).duplicate(true)
	return {}


func _loadout_telemetry_snapshot() -> Dictionary:
	var active_value: Variant = application_state.active_build_snapshot().get("active_build", {})
	var resolved: Dictionary = application_state.resolved_build_snapshot()
	var active: Dictionary = active_value if active_value is Dictionary else {}
	var equipped_value: Variant = active.get("equipped_item_ids", {})
	var equipped: Dictionary = equipped_value if equipped_value is Dictionary else {}
	return {
		"build_fingerprint": String(resolved.get("build_fingerprint", "")),
		"growth": String(resolved.get("growth_classification", "")),
		"interfaces": _resolved_interface_ids(resolved),
		"parameters": _finite_build_parameters(resolved),
		"equipped": equipped.duplicate(true),
	}


func _build_loadout_telemetry(action_id: String, subject: String, before: Dictionary) -> Dictionary:
	var after: Dictionary = _loadout_telemetry_snapshot()
	var slot := ""
	if action_id == "unequip_item":
		slot = String(subject)
	else:
		var item: Dictionary = _owned_equipment_for_telemetry(subject)
		slot = String(item.get("slot", ""))
	var previous_equipped: Dictionary = before.get("equipped", {}) if before.get("equipped", {}) is Dictionary else {}
	var next_equipped: Dictionary = after.get("equipped", {}) if after.get("equipped", {}) is Dictionary else {}
	return {
		"action": action_id,
		"slot": slot,
		"previous_instance_id": String(previous_equipped.get(slot, "")),
		"next_instance_id": String(next_equipped.get(slot, "")),
		"previous_build_fingerprint": String(before.get("build_fingerprint", "")),
		"new_build_fingerprint": String(after.get("build_fingerprint", "")),
		"growth_before": String(before.get("growth", "")),
		"growth_after": String(after.get("growth", "")),
		"interfaces_gained": _string_array_difference(after.get("interfaces", []), before.get("interfaces", [])),
		"interfaces_lost": _string_array_difference(before.get("interfaces", []), after.get("interfaces", [])),
		"parameter_deltas": _build_parameter_deltas(before.get("parameters", {}), after.get("parameters", {})),
	}


func _resolved_interface_ids(resolved: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var connected_value: Variant = resolved.get("connected_interfaces", [])
	if connected_value is Array:
		for value in connected_value:
			result.append(String(value))
	result.sort()
	return result

func _finite_build_parameters(resolved: Dictionary) -> Dictionary:
	var result := {}
	var parameters_value: Variant = resolved.get("final_parameters", {})
	var parameters: Dictionary = parameters_value if parameters_value is Dictionary else {}
	for key in LOADOUT_PARAMETER_KEYS:
		var value: Variant = parameters.get(key, null)
		if (value is int or value is float) and is_finite(float(value)):
			result[key] = float(value)
	return result


func _build_parameter_deltas(before: Dictionary, after: Dictionary) -> Dictionary:
	var result := {}
	for key in LOADOUT_PARAMETER_KEYS:
		if before.has(key) and after.has(key):
			result[key] = float(after[key]) - float(before[key])
	return result


func _string_array_difference(values: Variant, excluded: Variant) -> Array[String]:
	var result: Array[String] = []
	var excluded_strings: Array[String] = []
	if excluded is Array:
		for value in excluded:
			excluded_strings.append(String(value))
	if values is Array:
		for value in values:
			var candidate := String(value)
			if candidate not in excluded_strings and candidate not in result:
				result.append(candidate)
	result.sort()
	return result


func return_to_title() -> Dictionary:
	if current_route != SceneRouterScript.ROUTE_BASE:
		return _failure("wrong_route")
	_status_message = _persist("Profile saved", SceneRouterScript.ROUTE_TITLE)
	return _transition(SceneRouterScript.ROUTE_TITLE)


func cancel_contract() -> Dictionary:
	if current_route != SceneRouterScript.ROUTE_CONTRACT:
		return _failure("wrong_route")
	application_state.abandon_session()
	_status_message = "Contract preparation cancelled."
	return _transition(SceneRouterScript.ROUTE_BASE)


func launch_contract(config: Dictionary) -> Dictionary:
	if current_route != SceneRouterScript.ROUTE_CONTRACT:
		return _failure("wrong_route")
	var active_snapshot: Dictionary = application_state.active_build_snapshot()
	var active_build := _active_build_from_snapshot(active_snapshot)
	var resolved_build: Dictionary = application_state.resolved_build_snapshot()
	if not bool(resolved_build.get("ok", false)) or String(resolved_build.get("build_fingerprint", "")).length() != 64:
		_present_contract("active_build_invalid")
		return _failure("active_build_invalid")
	# preset_id remains a compatibility/display hint for the legacy arena. The
	# frozen resolver output below is the sole combat-parameter authority.
	var preset_id := String(resolved_build.get("growth_classification", "convergent"))
	if preset_id not in ["convergent", "critical", "exponential"]:
		preset_id = "convergent"
	var planned_config := config.duplicate(true)
	planned_config["preset_id"] = preset_id
	planned_config["resolved_build"] = resolved_build.duplicate(true)
	# Callers cannot bypass the CLI-presentation contract: the planned session
	# always carries the flag parsed from --presentation-off (default true).
	planned_config["presentation_enabled"] = _presentation_enabled
	var campaign_progress: Dictionary = application_state.campaign_progress_snapshot()
	if not bool(campaign_progress.get("ok", false)):
		_present_contract(String(campaign_progress.get("error", "campaign_progress_invalid")))
		return campaign_progress
	planned_config["completed_node_ids"] = (campaign_progress.get("completed_node_ids", []) as Array).duplicate()
	if String(planned_config.get("mode", "")).strip_edges().to_lower() == "auto" and not application_state.is_auto_mode_unlocked():
		_record_playtest("auto_rejected", {
			"contract_id": String(planned_config.get("contract_id", "")),
			"reason": "proxy_locked",
		})
		_present_contract("proxy_locked")
		return _failure("proxy_locked")
	var resolved_proxy_build: Dictionary = {}
	if String(planned_config.get("mode", "")).strip_edges().to_lower() == "auto":
		var proxy_resolution: Dictionary = application_state.resolved_proxy_build_snapshot()
		if not bool(proxy_resolution.get("ok", false)):
			var proxy_error := String(proxy_resolution.get("error", "invalid_proxy_build"))
			_present_contract(proxy_error)
			return proxy_resolution
		resolved_proxy_build = (proxy_resolution.resolved_proxy_build as Dictionary).duplicate(true)
	var plan_result: Dictionary = ContractPlanScript.build(planned_config)
	if not bool(plan_result.get("ok", false)):
		_present_contract(String(plan_result.get("error", "contract_plan_failed")))
		return plan_result
	var room_plan: Dictionary = (plan_result.get("plan", {}) as Dictionary).duplicate(true)
	if not _prototype_debug_force_family.is_empty():
		_apply_forced_drop_family(room_plan, _prototype_debug_force_family)
	planned_config["room_plan"] = room_plan
	planned_config["room_count"] = int(room_plan.get("room_count", planned_config.get("room_count", 0)))
	var profile: Dictionary = application_state.profile
	var progression_value: Variant = profile.get("progression", {})
	var progression: Dictionary = progression_value if progression_value is Dictionary else {}
	planned_config["framework_context"] = {
		"contract_wins": maxi(0, int(progression.get("contract_wins", 0))),
		"active_build": active_build.duplicate(true),
		"resolved_build": resolved_build.duplicate(true),
		"resolved_proxy_build": resolved_proxy_build.duplicate(true),
	}
	var prepared: Dictionary = application_state.prepare_contract(planned_config)
	if not bool(prepared.get("ok", false)):
		_present_contract(String(prepared.get("error", "contract_prepare_failed")))
		return prepared
	var begun: Dictionary = application_state.begin_session()
	if not bool(begun.get("ok", false)):
		_present_contract(String(begun.get("error", "session_start_failed")))
		return begun
	if not _prototype_debug_force_family.is_empty():
		_prototype_debug_force_family = ""
	_last_contract = (begun.get("session", {}) as Dictionary).duplicate(true)
	_record_playtest("contract_started", {
		"contract_id": String(_last_contract.get("contract_id", "")),
		"mode": String(_last_contract.get("mode", "")),
		"seed": int(_last_contract.get("seed", 0)),
		"room_count": int(_last_contract.get("room_count", 0)),
		"build_fingerprint": String(resolved_build.get("build_fingerprint", "")),
		"proxy_build_fingerprint": String(resolved_proxy_build.get("semantic_fingerprint", "")),
	})
	_status_message = ""
	return _transition(SceneRouterScript.ROUTE_ARENA, _last_contract)


func finish_contract(result: Dictionary) -> Dictionary:
	if current_route != SceneRouterScript.ROUTE_ARENA:
		return _failure("wrong_route")
	if not _pending_visual_route.is_empty():
		## This defeat already settled and its result screen is still waiting for the
		## clip: a duplicate signal must not settle again or rewrite last_result.
		return _failure("result_pending")
	var normalized := result.duplicate(true)
	if String(normalized.get("outcome", "")).is_empty():
		normalized["outcome"] = "error"
	var completed: Dictionary = application_state.complete_session(normalized)
	if not bool(completed.get("ok", false)):
		flow_error.emit(String(completed.get("error", "session_complete_failed")), "Could not settle encounter result")
		return completed
	var completed_result: Dictionary = completed.get("result", normalized) if completed.get("result", normalized) is Dictionary else normalized
	var log_payload := {
		"contract_id": String(completed_result.get("contract_id", _last_contract.get("contract_id", ""))),
		"mode": String(completed_result.get("mode", _last_contract.get("mode", ""))),
		"seed": int(completed_result.get("seed", _last_contract.get("seed", 0))),
		"outcome": String(completed_result.get("outcome", "")),
		"ticks": int(completed_result.get("ticks", 0)),
		"elapsed_seconds": float(completed_result.get("elapsed_seconds", 0.0)),
		"room_count": int(completed_result.get("room_count", 0)),
		"rooms_completed": int(completed_result.get("rooms_completed", 0)),
		"casts": int(completed_result.get("casts", 0)),
		"defeated": int(completed_result.get("defeated", 0)),
	}
	var failure_reason := String(completed_result.get("failure_reason", ""))
	if not failure_reason.is_empty():
		log_payload["failure_reason"] = failure_reason
	var rewards_value: Variant = completed_result.get("rewards", {})
	if rewards_value is Dictionary:
		var rewards: Dictionary = rewards_value
		var equipment_ids: Array[String] = []
		var drops_value: Variant = rewards.get("equipment_drops", [])
		if drops_value is Array:
			for drop_value in drops_value:
				if drop_value is Dictionary:
					equipment_ids.append(String((drop_value as Dictionary).get("instance_id", "")))
		log_payload["rewards"] = {
			"law_tallies_delta": (rewards.get("law_tallies_delta", {}) as Dictionary).duplicate(true) if rewards.get("law_tallies_delta", {}) is Dictionary else {},
			"equipment_drop_ids": equipment_ids,
			"repeatable_attempt_number": int(rewards.get("repeatable_attempt_number", 0)),
			"pity_guarantee_family": String(rewards.get("pity_guarantee_family", "")),
		}
	var room_summaries: Array[Dictionary] = []
	var room_results_value: Variant = completed_result.get("room_results", [])
	if room_results_value is Array:
		for room_value in room_results_value:
			if not room_value is Dictionary:
				continue
			var room: Dictionary = room_value
			room_summaries.append({
				"room_id": String(room.get("room_id", "")),
				"objective": String(room.get("objective", "")),
				"layout": String(room.get("layout", "")),
				"outcome": String(room.get("outcome", "")),
				"ticks": int(room.get("ticks", 0)),
				"elapsed_seconds": float(room.get("elapsed_seconds", 0.0)),
				"casts": int(room.get("casts", 0)),
				"defeated": int(room.get("defeated", 0)),
			})
			var room_failure_reason := String(room.get("failure_reason", ""))
			if not room_failure_reason.is_empty():
				room_summaries[room_summaries.size() - 1]["failure_reason"] = room_failure_reason
	if not room_summaries.is_empty():
		log_payload["rooms"] = room_summaries
	var bottleneck_value: Variant = completed_result.get("primary_bottleneck", null)
	if bottleneck_value is Dictionary:
		log_payload["primary_bottleneck"] = String((bottleneck_value as Dictionary).get("id", ""))
	_record_playtest("contract_finished", log_payload)
	var unlock_value: Variant = completed_result.get("unlock", {})
	if unlock_value is Dictionary and bool((unlock_value as Dictionary).get("proxy_unlocked", false)):
		_record_playtest("auto_unlocked", {
			"contract_id": String(completed_result.get("contract_id", "")),
			"components": ((unlock_value as Dictionary).get("components", []) as Array).duplicate(true) if (unlock_value as Dictionary).get("components", []) is Array else [],
			"profile_elapsed_msec": _profile_elapsed_msec(),
		})
	var progression_value: Variant = application_state.profile.get("progression", {})
	var progression: Dictionary = progression_value if progression_value is Dictionary else {}
	if (
		bool(progression.get("early_game_complete", false))
		and String(completed_result.get("contract_id", "")) == "auto_certification"
		and String(completed_result.get("outcome", "")) == "final_victory"
	):
		_record_playtest("early_game_completed", {
			"contract_id": "auto_certification",
			"profile_elapsed_msec": _profile_elapsed_msec(),
		})
	_status_message = _persist("Contract result saved", SceneRouterScript.ROUTE_BASE)
	return _route_to_result(completed_result)


## Everything above already settled: complete_session(), the progression, the
## equipment drops, the save and the playtest record have all happened exactly
## once, inside this call. This only decides whether the result screen may
## replace the arena screen now, or has to wait for the defeat clip that is still
## playing on it.
func _route_to_result(completed_result: Dictionary) -> Dictionary:
	if not _defeat_window_holds_screen(completed_result):
		return _transition(SceneRouterScript.ROUTE_RESULT, completed_result)
	_pending_visual_route = {
		"route": SceneRouterScript.ROUTE_RESULT,
		"payload": completed_result.duplicate(true),
		"seconds": 0.0,
	}
	return {
		"ok": true,
		"noop": true,
		"route": current_route,
		"pending_route": SceneRouterScript.ROUTE_RESULT,
		"deferred": true,
	}


## A defeated run whose clip is still on screen holds the route at the screen
## layer only. Victories, abandons, the smoke driver's own route expectations and
## any screen without the readiness relay are never held.
func _defeat_window_holds_screen(completed_result: Dictionary) -> bool:
	if _auto_smoke_session:
		return false
	if String(completed_result.get("outcome", "")) != "defeat":
		return false
	if _current_screen == null or not is_instance_valid(_current_screen):
		return false
	if not _current_screen.has_method("defeat_presentation_ready"):
		return false
	return not bool(_current_screen.call("defeat_presentation_ready"))


## Releases the deferred result screen and names why. No settlement is repeated
## here: a second call after the route moved is refused by the router itself.
func _release_pending_visual_route(reason: String) -> Dictionary:
	if _pending_visual_route.is_empty():
		return _failure("no_pending_route")
	_pending_route_release_reason = reason
	var payload: Dictionary = _pending_visual_route.get("payload", {})
	_pending_visual_route = {}
	return _transition(SceneRouterScript.ROUTE_RESULT, payload)


## Public skip entry for the defeat window: the fall has been seen (or the caller
## does not want to wait for it), so the deferred result screen commits now. The
## settlement is untouched -- it already happened exactly once.
func skip_defeat_presentation() -> Dictionary:
	return _release_pending_visual_route("skipped")


## Read-only route-layer diagnostic for the defeat window: whether the result
## screen is still waiting for the clip, for how long, and what released it.
func defeat_route_report() -> Dictionary:
	return {
		"pending": not _pending_visual_route.is_empty(),
		"held_seconds": float(_pending_visual_route.get("seconds", 0.0)),
		"fallback_seconds": DEFEAT_ROUTE_FALLBACK_SECONDS,
		"released_by": _pending_route_release_reason,
	}


func leave_result() -> Dictionary:
	if current_route != SceneRouterScript.ROUTE_RESULT:
		return _failure("wrong_route")
	return _transition(SceneRouterScript.ROUTE_BASE)


func _open_next_contract_from_result() -> void:
	if current_route != SceneRouterScript.ROUTE_RESULT:
		return
	var result := leave_result()
	if bool(result.get("ok", false)):
		open_contract()


## A settled equipment drop is already in the authoritative inventory. This route
## changes only what the player is looking at: it validates the owned instance,
## carries a one-shot focus hint to the loadout screen, and never equips the item.
func review_result_drop(instance_id: String, slot: String) -> Dictionary:
	if current_route != SceneRouterScript.ROUTE_RESULT:
		return _failure("wrong_route")
	var normalized_id := instance_id.strip_edges()
	var normalized_slot := slot.strip_edges()
	var item := _owned_equipment_for_telemetry(normalized_id)
	if item.is_empty():
		return _failure("item_not_owned")
	var settled_drop := _settled_result_equipment(normalized_id)
	if settled_drop.is_empty():
		return _failure("drop_not_in_result")
	if normalized_slot.is_empty() or String(item.get("slot", "")) != normalized_slot or String(settled_drop.get("slot", "")) != normalized_slot:
		return _failure("slot_mismatch")
	if normalized_slot not in EarlyItemRegistryScript.PROTOTYPE_OPEN_SLOTS:
		return _failure("slot_locked")
	var active := application_state.active_build_snapshot().get("active_build", {}) as Dictionary
	var equipped := active.get("equipped_item_ids", {}) as Dictionary
	_status_message = "Drop located; it is equipped. Inspect or unequip it." if String(equipped.get(normalized_slot, "")) == normalized_id else "Drop located; compare it and decide whether to equip it."
	_record_playtest("drop_review_started", {
		"instance_id": normalized_id,
		"slot": normalized_slot,
		"base_item_id": String(item.get("base_item_id", "")),
	})
	return _transition(SceneRouterScript.ROUTE_LOADOUT, {
		"review_instance_id": normalized_id,
		"focus_slot": normalized_slot,
		"return_route": SceneRouterScript.ROUTE_RESULT,
	})


func _settled_result_equipment(instance_id: String) -> Dictionary:
	var result: Dictionary = application_state.last_result
	var rewards_value: Variant = result.get("rewards", {})
	if not rewards_value is Dictionary:
		return {}
	var drops_value: Variant = (rewards_value as Dictionary).get("equipment_drops", [])
	if not drops_value is Array:
		return {}
	for drop_value in drops_value:
		if drop_value is Dictionary and String((drop_value as Dictionary).get("instance_id", "")) == instance_id:
			return (drop_value as Dictionary).duplicate(true)
	return {}


func open_ending() -> Dictionary:
	if current_route != SceneRouterScript.ROUTE_RESULT:
		return _failure("wrong_route")
	if String(application_state.last_result.get("outcome", "")) != "final_victory":
		return _failure("ending_locked")
	return _transition(SceneRouterScript.ROUTE_ENDING)


func leave_ending_to_base() -> Dictionary:
	if current_route != SceneRouterScript.ROUTE_ENDING:
		return _failure("wrong_route")
	return _transition(SceneRouterScript.ROUTE_BASE)


func leave_ending_to_title() -> Dictionary:
	if current_route != SceneRouterScript.ROUTE_ENDING:
		return _failure("wrong_route")
	_status_message = _persist("Epilogue checkpoint saved", SceneRouterScript.ROUTE_TITLE)
	return _transition(SceneRouterScript.ROUTE_TITLE)


func _bootstrap(arguments: PackedStringArray) -> void:
	if arguments.has("--auto-smoke"):
		_start_auto_smoke()
		return
	if _prototype_debug_rejected:
		_transition(SceneRouterScript.ROUTE_TITLE)
		return

	var initial_route: String = SceneRouterScript.ROUTE_TITLE
	var loaded: Dictionary = save_store.load_latest()
	if bool(loaded.get("ok", false)):
		var restored: Dictionary = application_state.restore_persistent_payload(loaded.get("payload", {}))
		if bool(restored.get("ok", false)):
			initial_route = String(restored.get("route", SceneRouterScript.ROUTE_TITLE))
			_status_message = "Restored save generation %d." % int(loaded.get("generation", 0))
		else:
			_status_message = PlayerFacingStatusScript.failure("Load profile", String(restored.get("error", "invalid_payload")))
	elif String(loaded.get("error", "")) != "no valid save slot":
		_status_message = PlayerFacingStatusScript.failure("Load profile", String(loaded.get("error", "unknown_error")))
	_transition(initial_route)


func _parse_presentation_flag(arguments: PackedStringArray) -> void:
	_presentation_enabled = not arguments.has("--presentation-off")


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
	_prototype_debug_dto = dto.duplicate(true)
	save_directory_path = String(dto.get("save_directory", PROTOTYPE_DEBUG_DEFAULT_SAVE_DIRECTORY))
	playtest_log_directory = save_directory_path.trim_suffix("/") + "/playtest"
	_prototype_debug_no_persist = bool(dto.get("no_persist", false))
	if bool(dto.get("has_seed", false)):
		_prototype_debug_has_seed = true
		_prototype_debug_seed_override = int(dto.get("seed", 0))


func _apply_prototype_debug_wipe() -> void:
	if _prototype_debug_rejected or _prototype_debug_dto.is_empty():
		return
	if not bool(_prototype_debug_dto.get("wipe", false)):
		return
	var wiped: Dictionary = save_store.delete_all()
	if not bool(wiped.get("ok", false)):
		_reject_prototype_debug("wipe_failed", str(wiped.get("error", "unknown_error")))
		return
	application_state.reset()


## One-shot debug drop override: after ContractPlan.build, every room of the
## next RoomPlan gains the general equipment drop tag (when missing) and a
## guarantee_family.  ApplicationState's existing drop-unlock gate still
## applies; the pending override is cleared only after begin_session succeeds.
func _apply_forced_drop_family(room_plan: Dictionary, family: String) -> void:
	var rooms_value: Variant = room_plan.get("rooms", [])
	if not rooms_value is Array:
		return
	for room_value in rooms_value:
		if not room_value is Dictionary:
			continue
		var room: Dictionary = room_value
		var tags_value: Variant = room.get("drop_tags", [])
		var tags: Array = (tags_value as Array).duplicate() if tags_value is Array else []
		if not tags.has(PROTOTYPE_DEBUG_FORCED_DROP_TAG):
			tags.append(PROTOTYPE_DEBUG_FORCED_DROP_TAG)
		room["drop_tags"] = tags
		room["guarantee_family"] = family


func _apply_prototype_debug_runtime() -> void:
	if _prototype_debug_rejected or _prototype_debug_dto.is_empty():
		return
	var runtime_script: Script = load(PROTOTYPE_DEBUG_RUNTIME_PATH)
	if runtime_script == null:
		_reject_prototype_debug("tool_load_failed", "could not load prototype debug runtime")
		return
	var summary: Dictionary = runtime_script.apply(self, _prototype_debug_dto)
	if not bool(summary.get("ok", false)):
		_reject_prototype_debug("apply_failed", str(summary.get("error", "prototype_debug_apply_failed")))
		_transition(SceneRouterScript.ROUTE_TITLE)
		return
	prototype_debug_summary = summary.duplicate(true)
	var forced_family := String(summary.get("force_family", "")).strip_edges()
	_prototype_debug_force_family = forced_family if not forced_family.is_empty() else ""
	print("PROTOTYPE_DEBUG_APPLIED %s" % JSON.stringify(prototype_debug_summary))
	_record_playtest("prototype_debug_applied", prototype_debug_summary)
	if not bool(summary.get("changed", false)):
		return
	var safe_route := SceneRouterScript.ROUTE_TITLE
	if current_route == SceneRouterScript.ROUTE_BASE or current_route == SceneRouterScript.ROUTE_TUTORIAL:
		safe_route = current_route
	_persist("Prototype debug applied", safe_route)


## Rejects a debug request with a stable log line and flow_error, then isolates
## the session so the default real save directory is never touched.
func _reject_prototype_debug(reason: String, detail: String) -> void:
	if _prototype_debug_rejected:
		return
	_prototype_debug_rejected = true
	_prototype_debug_reject_reason = reason
	print("PROTOTYPE_DEBUG_REJECTED reason=%s detail=%s" % [reason, detail])
	flow_error.emit("prototype_debug_rejected", "%s: %s" % [reason, detail])
	_prototype_debug_dto = {}
	_prototype_debug_has_seed = false
	_prototype_debug_seed_override = 0
	_prototype_debug_force_family = ""
	_prototype_debug_no_persist = false
	save_directory_path = PROTOTYPE_DEBUG_REJECTED_SAVE_DIRECTORY
	playtest_log_directory = PROTOTYPE_DEBUG_REJECTED_SAVE_DIRECTORY.path_join("playtest")
	application_state.reset()
	if save_store != null:
		save_store = SaveStoreScript.new(PROTOTYPE_DEBUG_REJECTED_SAVE_DIRECTORY)


func _start_auto_smoke() -> void:
	_auto_smoke_stage = "setup"
	if not _auto_smoke_require_ok("route_title", _transition(SceneRouterScript.ROUTE_TITLE)):
		return
	if not _auto_smoke_require_ok("new_profile", start_new_game("ranger")):
		return
	if not _auto_smoke_require_ok("tutorial", complete_tutorial()):
		return
	if not _auto_smoke_require_ok("open_loadout", open_facility(SceneRouterScript.ROUTE_LOADOUT)):
		return
	if not _auto_smoke_require_ok("select_build", request_facility_action(SceneRouterScript.ROUTE_LOADOUT, "select_ranger_build", {"preset_id": "exponential"})):
		return
	if not _auto_smoke_require_ok("leave_loadout", leave_facility()):
		return
	if not _auto_smoke_require_ok("open_training", open_facility(SceneRouterScript.ROUTE_TRAINING)):
		return
	if not _auto_smoke_require_ok("training_trial", request_facility_action(SceneRouterScript.ROUTE_TRAINING, "run_training_trial")):
		return
	if not _auto_smoke_require_ok("leave_training", leave_facility()):
		return

	var setup: Dictionary = _prepare_auto_smoke_mainline()
	if not bool(setup.get("ok", false)):
		_auto_smoke_fail("setup", "%s: %s" % [String(setup.get("step", "mainline")), String(setup.get("error", "unknown_error"))])
		return
	var progress: Dictionary = application_state.campaign_progress_snapshot()
	var completed: Array = progress.get("completed_node_ids", []) if bool(progress.get("ok", false)) else []
	for node_id: String in AUTO_SMOKE_SETUP_NODE_IDS:
		if node_id not in completed:
			_auto_smoke_fail("setup", "missing completed node %s" % node_id)
			return
	if "threshold_colossus" in completed or "auto_certification" in completed:
		_auto_smoke_fail("setup", "setup illegally completed Boss or Auto")
		return
	if application_state.is_auto_mode_unlocked():
		_auto_smoke_fail("setup", "setup illegally unlocked Auto")
		return

	if not _auto_smoke_require_ok("open_boss_contract", open_contract()):
		return
	_auto_smoke_stage = "boss"
	var launched: Dictionary = launch_contract({
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
	for contract_id: String in AUTO_SMOKE_SETUP_NODE_IDS:
		var progress: Dictionary = application_state.campaign_progress_snapshot()
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
		var prepared: Dictionary = application_state.prepare_contract(config)
		if not bool(prepared.get("ok", false)):
			return {"ok": false, "step": contract_id, "error": String(prepared.get("error", "contract_prepare_failed"))}
		var begun: Dictionary = application_state.begin_session()
		if not bool(begun.get("ok", false)):
			return {"ok": false, "step": contract_id, "error": String(begun.get("error", "session_start_failed"))}
		var settled: Dictionary = application_state.complete_session({
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
	_auto_smoke_fail(_auto_smoke_stage, "%s failed: %s" % [step, String(result.get("error", "unknown_error"))])
	return false


func _continue_auto_smoke(completed_stage: String, arena_result: Dictionary, settlement: Dictionary) -> void:
	if _auto_smoke_finished:
		return
	if completed_stage != _auto_smoke_stage:
		_auto_smoke_fail(completed_stage, "stale settlement while current stage is %s" % _auto_smoke_stage)
		return
	if not bool(settlement.get("ok", false)):
		_auto_smoke_fail(completed_stage, "framework settlement failed: %s" % String(settlement.get("error", "unknown_error")))
		return
	if current_route != SceneRouterScript.ROUTE_RESULT:
		_auto_smoke_fail(completed_stage, "framework settlement did not enter Result; route=%s" % current_route)
		return
	if String(arena_result.get("outcome", "")) != "victory":
		var reason := String(arena_result.get("error", arena_result.get("report", "non-victory result")))
		_auto_smoke_fail(completed_stage, reason)
		return

	if completed_stage == "boss":
		if _auto_smoke_settlement_count != 1:
			_auto_smoke_fail("boss", "expected first framework settlement, got %d" % _auto_smoke_settlement_count)
			return
		var boss_progress: Dictionary = application_state.campaign_progress_snapshot()
		var boss_completed: Array = boss_progress.get("completed_node_ids", []) if bool(boss_progress.get("ok", false)) else []
		var profile: Dictionary = application_state.profile
		var proxy_build: Dictionary = profile.get("proxy_build", {})
		var cores: Array = proxy_build.get("cores", [])
		if cores != AUTO_SMOKE_WHITE_CORES:
			_auto_smoke_fail("boss", "fixed four white cores missing: %s" % [cores])
			return
		if not application_state.is_auto_mode_unlocked():
			_auto_smoke_fail("boss", "Auto was not unlocked by real Boss settlement")
			return
		if "threshold_colossus" not in boss_completed or "auto_certification" in boss_completed:
			_auto_smoke_fail("boss", "campaign progression is invalid after Boss: %s" % [boss_completed])
			return
		if bool((profile.get("progression", {}) as Dictionary).get("early_game_complete", false)):
			_auto_smoke_fail("boss", "Boss settlement completed the early game before Auto")
			return
		_auto_smoke_boss_result = application_state.last_result.duplicate(true)
		if _capture_stage() == "boss":
			# Settled already: photograph Result before leaving it.
			_auto_smoke_capture_stage.call_deferred("boss")
			return
		_auto_smoke_advance_after_boss_result()
		return

	if completed_stage != "auto":
		_auto_smoke_fail(completed_stage, "unexpected completed stage")
		return
	if _auto_smoke_settlement_count != 2:
		_auto_smoke_fail("auto", "expected two framework settlements, got %d" % _auto_smoke_settlement_count)
		return
	var final_progress: Dictionary = application_state.campaign_progress_snapshot()
	var final_completed: Array = final_progress.get("completed_node_ids", []) if bool(final_progress.get("ok", false)) else []
	var final_profile: Dictionary = application_state.profile
	var progression: Dictionary = final_profile.get("progression", {})
	if not bool(progression.get("early_game_complete", false)) or "auto_certification" not in final_completed:
		_auto_smoke_fail("auto", "real Auto settlement did not complete the early game")
		return
	var final_result: Dictionary = application_state.last_result
	if String(final_result.get("contract_id", "")) != "auto_certification" or String(final_result.get("mode", "")) != "Auto":
		_auto_smoke_fail("auto", "Result lost Auto contract identity")
		return
	if String(final_result.get("outcome", "")) != "final_victory":
		_auto_smoke_fail("auto", "real Auto graduation did not produce final_victory")
		return
	if _capture_stage() == "auto":
		# Settle first, photograph Result, and only then open the Ending.
		_auto_smoke_capture_stage.call_deferred("auto")
		return
	_auto_smoke_finish_after_auto_result()


## The rest of the Boss stage: leave Result, reopen the board, launch real Auto.
func _auto_smoke_advance_after_boss_result() -> void:
	if not _auto_smoke_require_ok("leave_boss_result", leave_result()):
		return
	if not _auto_smoke_require_ok("open_auto_contract", open_contract()):
		return
	_auto_smoke_stage = "auto"
	var launched: Dictionary = launch_contract({
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
	var captured: Dictionary = await _capture_settlement_stage(stage)
	if not bool(captured.get("ok", false)):
		_capture_fail_line(
			String(captured.get("error", "unknown_error")),
			String(captured.get("detail", "")),
			CAPTURE_STAGE_ROUTE,
			current_route,
			stage,
			String(_capture_request.get("capture_path", ""))
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
	var final_result: Dictionary = application_state.last_result
	if (
		String(final_result.get("contract_id", "")) != "auto_certification"
		or String(final_result.get("mode", "")) != "Auto"
		or String(final_result.get("outcome", "")) != "final_victory"
	):
		_auto_smoke_fail("auto", "Auto settlement identity changed before the replay finished")
		return
	if not _auto_smoke_require_ok("open_ending", open_ending()):
		return
	if current_route != SceneRouterScript.ROUTE_ENDING:
		_auto_smoke_fail("auto", "final victory did not enter Ending; route=%s" % current_route)
		return
	var state_hash := _auto_smoke_semantic_hash(final_result)
	if state_hash.is_empty():
		_auto_smoke_fail("finalize", "could not calculate semantic hash")
		return
	if not _write_auto_smoke_state_hash(state_hash):
		_auto_smoke_fail("finalize", "could not write semantic hash")
		return
	_auto_smoke_finished = true
	_auto_smoke_stage = "complete"
	print("AUTO_SMOKE_PASS framework_settlements=%d route=%s boss_ticks=%d auto_ticks=%d early_game_complete=true state_hash=%s" % [
		_auto_smoke_settlement_count,
		current_route,
		int(_auto_smoke_boss_result.get("ticks", 0)),
		int(final_result.get("ticks", 0)),
		state_hash,
	])
	Engine.time_scale = _auto_smoke_previous_time_scale
	get_tree().quit(0)


func _auto_smoke_semantic_hash(final_result: Dictionary) -> String:
	var profile: Dictionary = application_state.profile
	var progression: Dictionary = profile.get("progression", {})
	var proxy_build: Dictionary = profile.get("proxy_build", {})
	var semantic := {
		"protocol": "wp4-a-real-arena-v1",
		"route": current_route,
		"framework_settlements": _auto_smoke_settlement_count,
		"completed_node_ids": (progression.get("completed_node_ids", []) as Array).duplicate(),
		"proxy_unlocked": bool(progression.get("proxy_unlocked", false)),
		"proxy_cores": (proxy_build.get("cores", []) as Array).duplicate(),
		"proxy_inventory_ids": _proxy_inventory_ids(profile),
		"early_game_complete": bool(progression.get("early_game_complete", false)),
		"boss": _auto_smoke_result_summary(_auto_smoke_boss_result),
		"auto": _auto_smoke_result_summary(final_result),
	}
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	if context.update(SaveStoreScript.canonical_json(semantic).to_utf8_buffer()) != OK:
		return ""
	return context.finish().hex_encode()


func _auto_smoke_result_summary(result: Dictionary) -> Dictionary:
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


func _proxy_inventory_ids(profile: Dictionary) -> Array[String]:
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
	if _auto_smoke_state_hash_output_path.is_empty():
		return true
	var output_path := _auto_smoke_state_hash_output_path
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
	if _auto_smoke_finished:
		return
	_auto_smoke_finished = true
	printerr("AUTO_SMOKE_FAIL stage=%s reason=%s route=%s framework_settlements=%d" % [stage, reason, current_route, _auto_smoke_settlement_count])
	Engine.time_scale = _auto_smoke_previous_time_scale
	_request_exit(1, "auto_smoke_fail:%s:%s" % [stage, reason])


func _transition(route: String, payload: Dictionary = {}) -> Dictionary:
	var requested: Dictionary = scene_router.request(route, payload)
	if not bool(requested.get("ok", false)):
		flow_error.emit(String(requested.get("error", "route_request_failed")), "%s -> %s" % [current_route, route])
		return requested
	if bool(requested.get("noop", false)):
		_render_route(current_route, payload)
		return requested
	var committed: Dictionary = scene_router.commit()
	if not bool(committed.get("ok", false)):
		flow_error.emit(String(committed.get("error", "route_commit_failed")), route)
	return committed


func _on_route_changed(previous_route: String, route: String, payload: Dictionary) -> void:
	_render_route(route, payload)
	## A committed route supersedes a deferred result screen. The settlement stays
	## exactly as it is and is never replayed from here.
	_pending_visual_route = {}
	var now_msec := Time.get_ticks_msec()
	_record_playtest("route_changed", {
		"from": previous_route,
		"to": route,
		"previous_dwell_msec": maxi(0, now_msec - _playtest_route_entered_msec) if _playtest_route_entered_msec > 0 else 0,
		"session_elapsed_msec": maxi(0, now_msec - _playtest_session_started_msec) if _playtest_session_started_msec > 0 else 0,
		"profile_elapsed_msec": _profile_elapsed_msec(),
	})
	_playtest_route_entered_msec = now_msec
	flow_route_changed.emit(previous_route, route)
	_refresh_test_console()


func _render_route(route: String, payload: Dictionary = {}) -> void:
	if _session_menu != null:
		_session_menu.close_menu()
		_session_menu.set_route(route)
	_retire_current_screen()
	if route in [SceneRouterScript.ROUTE_TITLE, SceneRouterScript.ROUTE_TUTORIAL]:
		_town_travel.clear()
	_apply_presentation_policy(route)
	match route:
		SceneRouterScript.ROUTE_TITLE:
			var screen = TitleScreenScript.new()
			screen.new_game_requested.connect(start_new_game)
			screen.continue_requested.connect(continue_game)
			_current_screen = screen
			_mount_screen(screen)
			_present_title(_status_message)
		SceneRouterScript.ROUTE_TUTORIAL:
			var screen = TutorialScreenScript.new()
			screen.completed.connect(complete_tutorial)
			_current_screen = screen
			_mount_screen(screen)
			screen.present(String(application_state.profile.get("initial_class", "ranger")))
		SceneRouterScript.ROUTE_BASE:
			var screen = BaseHubScreenScript.new()
			screen.contract_requested.connect(open_contract)
			screen.title_requested.connect(return_to_title)
			screen.feature_requested.connect(_on_feature_requested)
			screen.character_requested.connect(open_character)
			screen.story_requested.connect(open_story)
			screen.conversation_read.connect(read_town_conversation)
			_current_screen = screen
			_mount_screen(screen)
			_present_base(_status_message)
			if not _town_travel.is_empty(): screen.restore_travel(_town_travel)
		SceneRouterScript.ROUTE_STORY:
			var screen = StoryScreenScript.new()
			screen.closed.connect(close_adventure_page)
			screen.entry_read.connect(read_story_entry)
			_current_screen = screen
			_mount_screen(screen)
			screen.present(application_state.story_progress_snapshot(), application_state.profile.story)
		SceneRouterScript.ROUTE_CHARACTER:
			var screen = CharacterScreenScript.new()
			screen.closed.connect(close_adventure_page)
			screen.talent_requested.connect(func(id: String): change_character_talent("allocate",id))
			screen.talent_refund_requested.connect(func(id: String): change_character_talent("refund",id))
			screen.reset_requested.connect(func(): change_character_talent("reset"))
			screen.stance_requested.connect(func(stance: String): change_character_talent("stance",stance))
			_current_screen = screen
			_mount_screen(screen)
			screen.present(application_state.growth_snapshot())
		SceneRouterScript.ROUTE_LOADOUT, SceneRouterScript.ROUTE_FORGE, SceneRouterScript.ROUTE_TRAINING, SceneRouterScript.ROUTE_PROXY, SceneRouterScript.ROUTE_IMMORTALITY, SceneRouterScript.ROUTE_RESEARCH:
			var screen = FacilityScreenScript.new()
			var back_destination := String(payload.get("return_route", SceneRouterScript.ROUTE_BASE))
			_facility_return_route = back_destination
			screen.base_requested.connect(_on_facility_back_requested.bind(back_destination, String(payload.get("review_instance_id", ""))))
			screen.destination_requested.connect(_on_facility_destination_requested)
			screen.action_requested.connect(_on_facility_action_requested)
			_current_screen = screen
			_mount_screen(screen)
			_present_facility(route, _status_message, payload)
		SceneRouterScript.ROUTE_CONTRACT:
			var screen = ContractScreenScript.new()
			screen.start_requested.connect(launch_contract)
			screen.cancel_requested.connect(cancel_contract)
			_current_screen = screen
			_mount_screen(screen)
			_present_contract(_status_message)
		SceneRouterScript.ROUTE_ARENA:
			var screen: Node = _make_arena_screen()
			if screen == null:
				_handle_arena_launch_failure("room_runtime_factory_failed")
				return
			screen.connect("completed", _on_arena_completed)
			screen.connect("abandoned", _on_arena_abandoned)
			_current_screen = screen
			_mount_screen(screen)
			var launch_result: Variant = screen.call("start_session", payload.duplicate(true))
			_apply_route_preferences()
			if not (launch_result is Dictionary) or not bool((launch_result as Dictionary).get("ok", false)):
				var error_code := "room_runtime_start_failed"
				if launch_result is Dictionary:
					error_code = String((launch_result as Dictionary).get("error", error_code))
				_handle_arena_launch_failure(error_code)
		SceneRouterScript.ROUTE_RESULT:
			var screen = ResultScreenScript.new()
			screen.base_requested.connect(leave_result)
			screen.loadout_review_requested.connect(review_result_drop)
			screen.ending_requested.connect(open_ending)
			screen.contract_requested.connect(_open_next_contract_from_result)
			_current_screen = screen
			_mount_screen(screen)
			screen.present(application_state.last_result, _last_contract, application_state.profile)
			screen.focus_equipment(String(payload.get("review_instance_id", "")))
		SceneRouterScript.ROUTE_ENDING:
			var screen = EndingScreenScript.new()
			screen.base_requested.connect(leave_ending_to_base)
			screen.title_requested.connect(leave_ending_to_title)
			_current_screen = screen
			_mount_screen(screen)
			screen.present(application_state.profile, application_state.last_result)


func _make_arena_screen() -> Node:
	if room_runtime_factory.is_valid():
		var candidate: Variant = room_runtime_factory.call()
		return candidate as Node if candidate is Node else null
	var controller: Node = ContractRunControllerScript.new()
	if application_state != null:
		var commit_port := MainContractRoomCommitPort.new()
		var bound: Dictionary = commit_port.bind(application_state)
		if bool(bound.get("ok", false)):
			controller.set("room_commit_port", commit_port)
	return controller


func _handle_arena_launch_failure(error_code: String) -> void:
	flow_error.emit(error_code, "Encounter runtime could not start")
	_settle_arena_result({
		"outcome": "error",
		"error": error_code,
		"report": "Encounter runtime could not start.",
		"rewards": {},
	})


func _on_arena_completed(result: Dictionary) -> void:
	_settle_arena_result(result)


func _on_arena_abandoned(result: Dictionary) -> void:
	_settle_arena_result(result)


func _settle_arena_result(result: Dictionary) -> void:
	var stage := _auto_smoke_stage
	var settled: Dictionary = finish_contract(result)
	if not _auto_smoke_session or _auto_smoke_finished:
		return
	if bool(settled.get("ok", false)):
		_auto_smoke_settlement_count += 1
	_continue_auto_smoke.call_deferred(stage, result.duplicate(true), settled.duplicate(true))


func _on_feature_requested(feature_id: String) -> void:
	open_facility(feature_id)


func _on_facility_destination_requested(route: String) -> void:
	if route not in FACILITY_ROUTES or not scene_router.can_transition(route):
		flow_error.emit("facility_destination_blocked", "%s -> %s" % [current_route, route])
		return
	_status_message = ""
	_transition(route)


func _on_facility_back_requested(destination: String, reviewed_item_id: String = "") -> void:
	if destination == SceneRouterScript.ROUTE_RESULT \
			and current_route == SceneRouterScript.ROUTE_LOADOUT \
			and not application_state.last_result.is_empty() \
			and scene_router.can_transition(SceneRouterScript.ROUTE_RESULT):
		_transition(SceneRouterScript.ROUTE_RESULT, {"review_instance_id": reviewed_item_id})
		return
	leave_facility()


func _on_facility_action_requested(facility_id: String, action_id: String, payload: Dictionary) -> void:
	request_facility_action(facility_id, action_id, payload)


func _present_title(message: String) -> void:
	if _current_screen != null and _current_screen.has_method("present"):
		_current_screen.call("present", application_state.has_profile(), message)


func _present_base(message: String) -> void:
	if _current_screen != null and _current_screen.has_method("present"):
		_current_screen.call("present", application_state.profile, application_state.last_result, message, _campaign_contract_snapshot())

		_current_screen.present_adventure(application_state.character_snapshot(), application_state.story_snapshot())

func _present_contract(message: String) -> void:
	if _current_screen != null and _current_screen.has_method("present"):
		var build_snapshot: Dictionary = application_state.early_game_snapshot().duplicate(true)
		if bool(build_snapshot.get("ok", false)):
			build_snapshot["resolved_build"] = application_state.resolved_build_snapshot().duplicate(true)
		build_snapshot["auto_mode_unlocked"] = application_state.is_auto_mode_unlocked()
		build_snapshot["campaign"] = _campaign_contract_snapshot()
		_current_screen.call("present", application_state.profile, _last_contract, message, build_snapshot)


func _present_facility(facility_id: String, message: String, presentation_context: Dictionary = {}) -> void:
	if _current_screen != null and _current_screen.has_method("present"):
		var facility_data: Dictionary = {}
		if facility_id == SceneRouterScript.ROUTE_FORGE:
			application_state.forge_ensure_context()
			facility_data = application_state.forge_snapshot()
		elif facility_id == SceneRouterScript.ROUTE_LOADOUT:
			facility_data = _loadout_facility_snapshot()
			facility_data["return_route"] = _facility_return_route
			if not presentation_context.is_empty():
				facility_data["initial_focus"] = presentation_context.duplicate(true)
		elif facility_id == SceneRouterScript.ROUTE_TRAINING:
			facility_data = application_state.early_game_snapshot()
			if bool(facility_data.get("ok", false)):
				facility_data["resolved_build"] = application_state.resolved_build_snapshot().duplicate(true)
		elif facility_id == SceneRouterScript.ROUTE_PROXY:
			facility_data = application_state.early_game_snapshot()
		_current_screen.call("present", facility_id, application_state.profile, application_state.last_result, message, facility_data)

func _loadout_facility_snapshot() -> Dictionary:
	var snapshot: Dictionary = application_state.early_game_snapshot().duplicate(true)
	if not bool(snapshot.get("ok", false)):
		return snapshot
	var profile_snapshot: Dictionary = application_state.profile
	var inventory_value: Variant = profile_snapshot.get("inventory", {})
	var inventory: Dictionary = inventory_value if inventory_value is Dictionary else {}
	var equipment_value: Variant = inventory.get("equipment", [])
	snapshot["inventory_equipment"] = (equipment_value as Array).duplicate(true) if equipment_value is Array else []
	snapshot["resolved_build"] = application_state.resolved_build_snapshot().duplicate(true)
	var equip_previews := {}
	var salvage_previews := {}
	for item_value in (snapshot.inventory_equipment as Array):
		if not item_value is Dictionary:
			continue
		var instance_id := String((item_value as Dictionary).get("instance_id", ""))
		var preview: Dictionary = application_state.preview_equip_item(instance_id)
		if bool(preview.get("ok", false)):
			equip_previews[instance_id] = preview.duplicate(true)
		var salvage: Dictionary = application_state.salvage_item_preview(instance_id)
		if bool(salvage.get("ok", false)):
			salvage_previews[instance_id] = salvage.duplicate(true)
	snapshot["equip_previews"] = equip_previews
	snapshot["salvage_previews"] = salvage_previews
	snapshot["equipment_slots"] = EarlyItemRegistryScript.EQUIPMENT_SLOTS.duplicate()
	snapshot["prototype_open_slots"] = EarlyItemRegistryScript.PROTOTYPE_OPEN_SLOTS.duplicate()
	var registry = EarlyItemRegistryScript.new()
	var load_errors: Array[String] = registry.load_all()
	if not load_errors.is_empty():
		snapshot["loadout_errors"] = load_errors.duplicate()
		return snapshot
	snapshot["base_items"] = registry.base_items.duplicate(true)
	snapshot["affix_families"] = registry.affix_families.duplicate(true)
	return snapshot


func _campaign_contract_snapshot() -> Dictionary:
	var progress: Dictionary = application_state.campaign_progress_snapshot()
	if not bool(progress.get("ok", false)):
		return progress
	var registry = EarlyCampaignRegistryScript.new()
	var load_errors: Array[String] = registry.load_campaign()
	if not load_errors.is_empty():
		return {"ok": false, "error": "campaign_content_invalid", "details": load_errors.duplicate()}
	var completed_value: Variant = progress.get("completed_node_ids", [])
	var available_value: Variant = progress.get("available_node_ids", [])
	var completed: Array = completed_value if completed_value is Array else []
	var available: Array = available_value if available_value is Array else []
	var profile_snapshot: Dictionary = application_state.profile
	var progression_value: Variant = profile_snapshot.get("progression", {})
	var progression: Dictionary = progression_value if progression_value is Dictionary else {}
	var repeatable_counts_value: Variant = progression.get("repeatable_completion_counts", {})
	var repeatable_counts: Dictionary = repeatable_counts_value if repeatable_counts_value is Dictionary else {}
	var node_ids: Array[String] = registry.mainline_order()
	for side_id in EARLY_SIDE_NODE_IDS:
		node_ids.append(side_id)
	var nodes: Array[Dictionary] = []
	for node_id in node_ids:
		var node: Dictionary = registry.get_node(node_id)
		if node.is_empty():
			continue
		var room_count := 1
		if node.has("room_sequence") and node.room_sequence is Array:
			room_count = maxi(1, (node.room_sequence as Array).size())
		elif node.has("room_template") and node.room_template is Dictionary:
			room_count = maxi(1, int((node.room_template as Dictionary).get("room_count", 1)))
		var node_snapshot := {
			"id": node_id,
			"kind": String(node.get("kind", "")),
			"available": node_id in available,
			"completed": node_id in completed,
			"repeatable": bool(node.get("repeatable", false)),
			"allowed_modes": (node.get("allowed_modes", []) as Array).duplicate(),
			"room_count": room_count,
			"drop_tags": (node.get("drop_tags", []) as Array).duplicate(),
			"first_reward_tags": (node.get("first_reward_tags", []) as Array).duplicate(),
			"experience_reward": CharacterProgressionScript.contract_experience(node_id, node_id not in completed),
			"unlock_prerequisites": (node.get("unlock_prerequisites", []) as Array).duplicate(),
		}
		if bool(node_snapshot.repeatable):
			var completion_count := maxi(0, int(repeatable_counts.get(node_id, 0)))
			var suggested_seed := int(DEFAULT_CONTRACT.seed) + completion_count
			if String(_last_contract.get("contract_id", "")) == node_id:
				suggested_seed = int(_last_contract.get("seed", suggested_seed))
				var last_outcome := String(application_state.last_result.get("outcome", "")).to_lower()
				if last_outcome in ["victory", "final_victory"]:
					suggested_seed = suggested_seed + 1 if suggested_seed < 2147483647 else -2147483648
			node_snapshot["completion_count"] = completion_count
			node_snapshot["next_attempt_number"] = completion_count + 1
			node_snapshot["suggested_seed"] = suggested_seed
		if _prototype_debug_has_seed:
			node_snapshot["suggested_seed"] = _prototype_debug_seed_override
		nodes.append(node_snapshot)
	var result := progress.duplicate(true)
	result["nodes"] = nodes
	return result


func _active_build_from_snapshot(snapshot: Dictionary) -> Dictionary:
	var nested: Variant = snapshot.get("active_build", snapshot)
	return (nested as Dictionary).duplicate(true) if nested is Dictionary else {}


func _retire_current_screen() -> void:
	if _current_screen == null or not is_instance_valid(_current_screen):
		_current_screen = null
		return
	if _current_screen is BaseHubScreenScript:
		_town_travel = _current_screen.travel_snapshot()
	if _current_screen is CanvasItem:
		(_current_screen as CanvasItem).visible = false
	_current_screen.process_mode = Node.PROCESS_MODE_DISABLED
	_current_screen.queue_free()
	_current_screen = null


func _persist(reason: String, safe_route: String) -> String:
	if _test_session or _prototype_debug_no_persist:
		return reason
	var saved: Dictionary = save_store.save(application_state.persistent_payload(safe_route))
	if bool(saved.get("ok", false)):
		return reason
	var detail := String(saved.get("error", "unknown error"))
	flow_error.emit("save_failed", detail)
	return PlayerFacingStatusScript.error_message("save_failed")


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
	var base := {"display": display, "presentation_enabled": _presentation_enabled}
	if display.to_lower().contains("headless"):
		base["ok"] = false
		base["error"] = "headless_display"
		base["detail"] = "the headless display server cannot draw a frame that proves GPU output"
		return base
	if not _presentation_enabled:
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
		if current_route == SceneRouterScript.ROUTE_BASE:
			return_to_title()
		elif current_route == SceneRouterScript.ROUTE_TUTORIAL:
			_transition(SceneRouterScript.ROUTE_TITLE)
		return _capture_route_report(route)
	if current_route == SceneRouterScript.ROUTE_TITLE:
		start_new_game("ranger")
	if route == SceneRouterScript.ROUTE_TUTORIAL:
		return _capture_route_report(route)
	if current_route == SceneRouterScript.ROUTE_TUTORIAL:
		complete_tutorial()
	if route == SceneRouterScript.ROUTE_BASE:
		return _capture_route_report(route)
	if route == SceneRouterScript.ROUTE_RESEARCH and current_route == SceneRouterScript.ROUTE_BASE:
		open_facility(SceneRouterScript.ROUTE_TRAINING)
		_on_facility_destination_requested(SceneRouterScript.ROUTE_RESEARCH)
		return _capture_route_report(route)
	if route in FACILITY_ROUTES and current_route == SceneRouterScript.ROUTE_BASE:
		open_facility(route)
		return _capture_route_report(route)
	if route == SceneRouterScript.ROUTE_CONTRACT and current_route == SceneRouterScript.ROUTE_BASE:
		open_contract()
	return _capture_route_report(route)


## Read-only requested/actual route report for one preparation attempt.
func _capture_route_report(requested_route: String) -> Dictionary:
	var actual_route := current_route
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
		String(report.get("actual_route", current_route)),
		String(request.get("capture_stage", "")),
		String(request.get("capture_path", ""))
	)
	return false


func _capture_stage() -> String:
	return String(_capture_request.get("capture_stage", ""))


## Route capture: --capture=<path> [--capture-route=<route>], written only when the
## harness is really on the requested screen and the environment can draw one.
func _capture_frame(path: String, requested_route: String = "") -> void:
	var environment: Dictionary = capture_environment_report()
	if not bool(environment.get("ok", false)):
		_capture_fail(String(environment.get("error", "capture_environment_invalid")), String(environment.get("detail", "")), requested_route, current_route, "", path)
		return
	if not requested_route.is_empty() and current_route != requested_route:
		_capture_fail("route_mismatch", "the requested screen is not current any more: requested=%s actual=%s" % [requested_route, current_route], requested_route, current_route, "", path)
		return
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var written: Dictionary = _write_viewport_png(path)
	if not bool(written.get("ok", false)):
		_capture_fail(String(written.get("error", "png_write_failed")), String(written.get("detail", "")), requested_route, current_route, "", path)
		return
	print("CAPTURE_PASS %s capture_kind=route requested_route=%s actual_route=%s requested_stage=none actual_stage=none" % [
		path,
		requested_route if not requested_route.is_empty() else "none",
		current_route,
	])
	get_tree().quit(0)


## Opt-in settlement evidence for --auto-smoke --capture-stage=boss|auto. The
## settlement has already happened when this is called; it only waits for the
## committed Result frame, saves the PNG plus its JSON sidecar, and hands the
## replay back to the continuation it interrupted. No simulation input is written.
func _capture_settlement_stage(stage: String) -> Dictionary:
	var environment: Dictionary = capture_environment_report()
	if not bool(environment.get("ok", false)):
		return _capture_refusal(String(environment.get("error", "capture_environment_invalid")), String(environment.get("detail", "")))
	if current_route != CAPTURE_STAGE_ROUTE:
		return _capture_refusal("route_mismatch", "settlement evidence requires the committed %s route; actual=%s" % [CAPTURE_STAGE_ROUTE, current_route])
	if _auto_smoke_stage != stage:
		return _capture_refusal("stage_mismatch", "requested stage=%s is not the settled stage=%s" % [stage, _auto_smoke_stage])
	var path := String(_capture_request.get("capture_path", ""))
	var target: Dictionary = capture_evidence_target_available(path)
	if not bool(target.get("ok", false)):
		return _capture_refusal(String(target.get("error", "capture_target_unavailable")), String(target.get("detail", "")))
	# Two frames to build and lay out the result screen, then its post-draw signal.
	await get_tree().process_frame
	await get_tree().process_frame
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
	var result: Dictionary = application_state.last_result
	print("CAPTURE_PASS %s capture_kind=settlement requested_stage=%s actual_stage=%s requested_route=%s actual_route=%s contract_id=%s outcome=%s ticks=%d framework_settlements=%d setup_synthetic_wins=%d png_sha256=%s evidence=%s" % [
		path,
		stage,
		_auto_smoke_stage,
		CAPTURE_STAGE_ROUTE,
		current_route,
		String(result.get("contract_id", "")),
		String(result.get("outcome", "")),
		int(result.get("ticks", 0)),
		_auto_smoke_settlement_count,
		AUTO_SMOKE_SETUP_NODE_IDS.size(),
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
		"actual_stage": _auto_smoke_stage,
		"requested_route": CAPTURE_STAGE_ROUTE,
		"actual_route": current_route,
	}


## Compact read-only copy of what the run settled, plus the exact route/stage.
func _capture_settlement_evidence(stage: String, absolute_path: String, evidence_path: String) -> Dictionary:
	var result: Dictionary = application_state.last_result
	var profile: Dictionary = application_state.profile
	var progression_value: Variant = profile.get("progression", {})
	var progression: Dictionary = progression_value if progression_value is Dictionary else {}
	var proxy_value: Variant = profile.get("proxy_build", {})
	var proxy_build: Dictionary = proxy_value if proxy_value is Dictionary else {}
	var screen_name := ""
	if _current_screen != null and is_instance_valid(_current_screen) and _current_screen.get_script() != null:
		screen_name = String((_current_screen.get_script() as Script).resource_path.get_file())
	return {
		"protocol": CAPTURE_EVIDENCE_PROTOCOL,
		"capture_kind": "real_arena_simulation_settlement",
		"requested_stage": stage,
		"actual_stage": _auto_smoke_stage,
		"requested_route": CAPTURE_STAGE_ROUTE,
		"actual_route": current_route,
		"screen": screen_name,
		"capture_path": absolute_path,
		"evidence_path": evidence_path,
		"captured_at_utc": Time.get_datetime_string_from_system(true, true),
		"engine_version": String(Engine.get_version_info().get("string", "unknown")),
		"display": DisplayServer.get_name(),
		"presentation_enabled": _presentation_enabled,
		"injected_result_or_state": false,
		"setup_synthetic_wins": AUTO_SMOKE_SETUP_NODE_IDS.size(),
		"framework_settlements": _auto_smoke_settlement_count,
		"settlement": _auto_smoke_result_summary(result),
		"progression": {
			"completed_node_ids": (progression.get("completed_node_ids", []) as Array).duplicate(),
			"proxy_unlocked": bool(progression.get("proxy_unlocked", false)),
			"proxy_cores": (proxy_build.get("cores", []) as Array).duplicate(),
			"proxy_inventory_ids": _proxy_inventory_ids(profile),
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
	var error: Error = get_viewport().get_texture().get_image().save_png(absolute_path)
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
	_request_exit(1, "capture_fail:%s" % error_code)


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
		current_route,
		String(report.get("capture_stage", "")),
		String(report.get("capture_path", ""))
	)


func _capture_refusal(error_code: String, detail: String) -> Dictionary:
	return {"ok": false, "error": error_code, "detail": detail}


## Reports the final exit code to exit_code_hook instead of ending the process.
func _request_exit(code: int, reason: String) -> void:
	if exit_code_hook.is_valid():
		exit_code_hook.call(code, reason)
		return
	var tree := get_tree()
	if tree != null:
		tree.quit(code)


func _run_scene_smoke() -> void:
	# Exercise content-backed profile creation in memory so this check stays
	# independent from any save that happens to exist on the machine.
	application_state.reset()
	var profile_created: Dictionary = application_state.start_new_profile("ranger")
	var early_game: Dictionary = application_state.early_game_snapshot()
	var available_builds: Variant = early_game.get("available_builds", [])
	var contract_plan: Dictionary = ContractPlanScript.build(DEFAULT_CONTRACT)
	if _current_screen == null or not bool(profile_created.get("ok", false)) or not (available_builds is Array) or (available_builds as Array).size() != 3 or not bool(contract_plan.get("ok", false)):
		printerr("SCENE_SMOKE_FAIL route=%s profile=%s builds=%d contract=%s" % [
			current_route,
			str(profile_created),
			(available_builds as Array).size() if available_builds is Array else -1,
			str(contract_plan),
		])
		get_tree().quit(1)
		return
	print("SCENE_SMOKE_PASS framework=routes,builds,contract,persistence route=%s" % current_route)
	get_tree().quit(0)


func _start_playtest_logging() -> void:
	if playtest_log == null:
		playtest_log = PlaytestLogScript.new(playtest_log_directory)
	if not playtest_log.has_method("start_session"):
		return
	_playtest_session_started_msec = Time.get_ticks_msec()
	_playtest_route_entered_msec = _playtest_session_started_msec
	playtest_log.call("start_session", {
		"prototype": "early_game",
		"profile_schema_version": ApplicationStateScript.SCHEMA_VERSION,
		"content_versions": {
			"early_campaign": EarlyCampaignRegistryScript.SCHEMA_VERSION,
			"early_items": EarlyItemRegistryScript.EXPECTED_SCHEMA_VERSION,
		},
		"engine_version": Engine.get_version_info().get("string", "unknown"),
	})


func _record_playtest(event_id: String, payload: Dictionary = {}) -> void:
	if _prototype_debug_no_persist:
		return
	if playtest_log == null or not playtest_log.has_method("record"):
		return
	if playtest_log.has_method("is_active") and not bool(playtest_log.call("is_active")):
		return
	playtest_log.call("record", event_id, payload.duplicate(true))


func _finish_playtest_logging(reason: String) -> void:
	if playtest_log == null:
		return
	if playtest_log.has_method("is_active") and not bool(playtest_log.call("is_active")):
		return
	if playtest_log.has_method("finish"):
		playtest_log.call("finish", {"reason": reason})
	elif playtest_log.has_method("close"):
		playtest_log.call("close")


func _profile_elapsed_msec() -> int:
	if _playtest_profile_started_msec <= 0:
		return 0
	return maxi(0, Time.get_ticks_msec() - _playtest_profile_started_msec)


func _failure(error_code: String) -> Dictionary:
	return {"ok": false, "error": error_code}


## Typed bridge from the route composition root to ApplicationState. The
## controller never receives a Callable for framework settlement.
class MainContractRoomCommitPort extends ContractRoomCommitPortScript:

	var _owner: ApplicationState = null

	func bind(owner: ApplicationState) -> Dictionary:
		if owner == null:
			_owner = null
			return {"ok": false, "error": "contract_commit_owner_unavailable"}
		_owner = owner
		return {"ok": true, "error": ""}

	func commit(room_index: int, room_result: Dictionary) -> Dictionary:
		if _owner == null:
			return {"ok": false, "error": "contract_commit_owner_unavailable"}
		return _owner.commit_room_victory_and_resolve_next_build(room_index, room_result)
