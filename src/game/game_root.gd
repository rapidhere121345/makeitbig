class_name GameRoot
extends Node

signal flow_route_changed(previous_route: String, current_route: String)
signal flow_error(error_code: String, detail: String)

const ApplicationStateScript = preload("res://src/game/application_state.gd")
const SceneRouterScript = preload("res://src/game/scene_router.gd")
const ContractPlanScript = preload("res://src/game/contract_plan.gd")
const ContractRunControllerScript = preload("res://src/game/contract_run_controller.gd")
const ContractRoomCommitPortScript = preload("res://src/game/contract_room_commit_port.gd")
const SaveStoreScript = preload("res://src/persistence/save_store.gd")
const PlaytestLogScript = preload("res://src/game/playtest_log.gd")
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
const Locale = preload("res://src/localization/game_locale.gd")
const CoreResult := preload("res://src/core/result.gd")

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
const AUTO_SMOKE_TIME_SCALE := 20.0
## Shared by GameRoot and the capture harness; settlement captures only accept it.
const CAPTURE_STAGE_ROUTE: String = "result"
## The published defeat clip may hold the result *screen*, never the result: the
## settlement, the progression, the save and the playtest record already happened
## in the same call that produced this route. This bound is the route layer's own
## clock, so a screen that never reports readiness keeps a corpse for at most
## this long.
const DEFEAT_ROUTE_FALLBACK_SECONDS: float = 1.0

const DEFAULT_SAVE_DIRECTORY: String = "user://framework-saves"
const PROTOTYPE_DEBUG_FORCED_DROP_TAG: String = "equipment_general"
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
var _language_code := "en"
var _menu_scale := 1.0
var _render_quality := "balanced"
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
	Locale.acquire()
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
	_pixel_stage.set_render_quality(_render_quality)
	add_child(_pixel_stage)
	_pixel_stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## The F10 test console and the session menu service live in
## src/game/root/test_console_host.gd; these thin forwarders keep the owner's
## method names for the remaining call sites.
var _test_console_host_impl  # untyped to avoid a preload cycle
func _test_console_host() -> TestConsoleHost:
	if _test_console_host_impl == null:
		_test_console_host_impl = TestConsoleHost.new(self)
	return _test_console_host_impl


func _ensure_test_console() -> void:
	_test_console_host()._ensure_test_console()


func get_test_console() -> CanvasLayer:
	return _test_console_host().get_test_console()


func get_session_menu() -> CanvasLayer:
	return _test_console_host().get_session_menu()


func _ensure_session_menu() -> void:
	_test_console_host()._ensure_session_menu()


func _resume_current_route() -> void:
	_test_console_host()._resume_current_route()


func _refresh_test_console() -> void:
	_test_console_host()._refresh_test_console()


## The display, audio and player-settings service lives in
## src/game/root/display_settings.gd; these thin forwarders keep the owner's
## method names for the remaining call sites.
var _display_settings_impl  # untyped to avoid a preload cycle
func _display_settings() -> DisplaySettings:
	if _display_settings_impl == null:
		_display_settings_impl = DisplaySettings.new(self)
	return _display_settings_impl


func _set_language(code: String) -> void:
	_display_settings()._set_language(code)


func _set_render_quality(value: String) -> void:
	_display_settings()._set_render_quality(value)


func _set_menu_scale(value: float) -> void:
	_display_settings()._set_menu_scale(value)


func _set_effects_volume(value: float) -> void:
	_display_settings()._set_effects_volume(value)


func _apply_route_preferences() -> void:
	_display_settings()._apply_route_preferences()


func _usable_display_size() -> Vector2i:
	return _display_settings()._usable_display_size()


func _apply_display_settings(resolution: Vector2i, fullscreen: bool) -> void:
	_display_settings()._apply_display_settings(resolution, fullscreen)


func _acquire_stage_window() -> void:
	_display_settings()._acquire_stage_window()


func _release_stage_window() -> void:
	_display_settings()._release_stage_window()


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
	Locale.release()
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
		return CoreResult.failure("wrong_route")
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
		return CoreResult.failure("wrong_route")
	if not application_state.has_profile():
		_present_title("No valid profile is available.")
		return CoreResult.failure("profile_required")
	var profile: Dictionary = application_state.profile
	return _transition(SceneRouterScript.ROUTE_BASE if bool(profile.get("tutorial_complete", false)) else SceneRouterScript.ROUTE_TUTORIAL)


func complete_tutorial() -> Dictionary:
	if current_route != SceneRouterScript.ROUTE_TUTORIAL:
		return CoreResult.failure("wrong_route")
	var completed: Dictionary = application_state.complete_tutorial()
	if not bool(completed.get("ok", false)):
		return completed
	_record_playtest("tutorial_completed", {"initial_class": String(application_state.profile.get("initial_class", ""))})
	_status_message = _persist("Ranger basics tutorial complete", SceneRouterScript.ROUTE_BASE)
	return _transition(SceneRouterScript.ROUTE_BASE)


func open_contract() -> Dictionary:
	if current_route != SceneRouterScript.ROUTE_BASE:
		return CoreResult.failure("wrong_route")
	_status_message = ""
	return _transition(SceneRouterScript.ROUTE_CONTRACT)


func open_story() -> Dictionary:
	if current_route != SceneRouterScript.ROUTE_BASE: return CoreResult.failure("wrong_route")
	return _transition(SceneRouterScript.ROUTE_STORY)


func read_story_entry(entry_id: String) -> Dictionary:
	if current_route != SceneRouterScript.ROUTE_STORY: return CoreResult.failure("wrong_route")
	var result: Dictionary = application_state.mark_story_read(entry_id)
	if bool(result.get("ok",false)): _persist("Observation recorded.", SceneRouterScript.ROUTE_BASE)
	return result


func read_town_conversation(entry_id: String) -> Dictionary:
	if current_route != SceneRouterScript.ROUTE_BASE: return CoreResult.failure("wrong_route")
	var available := false
	for conversation: Dictionary in application_state.story_snapshot().get("available_conversations", []):
		if String(conversation.id) == entry_id: available = true
	if not available: return CoreResult.failure("story_entry_unavailable")
	var result: Dictionary = application_state.mark_story_read(entry_id)
	if bool(result.get("ok", false)):
		_persist("", SceneRouterScript.ROUTE_BASE)
		_current_screen.present_adventure(application_state.character_snapshot(), application_state.story_snapshot())
	return result



func open_character() -> Dictionary:
	if current_route != SceneRouterScript.ROUTE_BASE: return CoreResult.failure("wrong_route")
	return _transition(SceneRouterScript.ROUTE_CHARACTER)


func close_adventure_page() -> Dictionary:
	if current_route not in [SceneRouterScript.ROUTE_CHARACTER, SceneRouterScript.ROUTE_STORY]: return CoreResult.failure("wrong_route")
	return _transition(SceneRouterScript.ROUTE_BASE)


func change_character_talent(action: String, value: String = "") -> Dictionary:
	if current_route != SceneRouterScript.ROUTE_CHARACTER: return CoreResult.failure("wrong_route")
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
		return CoreResult.failure("wrong_route")
	if route not in FACILITY_ROUTES or route == SceneRouterScript.ROUTE_RESEARCH:
		return CoreResult.failure("unknown_facility")
	if route == SceneRouterScript.ROUTE_FORGE:
		var forge_context: Dictionary = application_state.forge_ensure_context()
		if not bool(forge_context.get("ok", false)):
			return forge_context
	_status_message = ""
	return _transition(route)


func leave_facility() -> Dictionary:
	if current_route not in FACILITY_ROUTES:
		return CoreResult.failure("wrong_route")
	return _transition(SceneRouterScript.ROUTE_BASE)


## The facility action dispatcher lives in src/game/root/facility_actions.gd;
## these thin forwarders keep the owner's method names for the remaining call sites.
var _facility_actions_impl  # untyped to avoid a preload cycle
func _facility_actions() -> FacilityActions:
	if _facility_actions_impl == null:
		_facility_actions_impl = FacilityActions.new(self)
	return _facility_actions_impl


func request_facility_action(facility_id: String, action_id: String, payload: Dictionary = {}) -> Dictionary:
	return _facility_actions().request_facility_action(facility_id, action_id, payload)


func _owned_equipment_for_telemetry(instance_id: String) -> Dictionary:
	return _facility_actions()._owned_equipment_for_telemetry(instance_id)


func return_to_title() -> Dictionary:
	if current_route != SceneRouterScript.ROUTE_BASE:
		return CoreResult.failure("wrong_route")
	_status_message = _persist("Profile saved", SceneRouterScript.ROUTE_TITLE)
	return _transition(SceneRouterScript.ROUTE_TITLE)


## The contract lifecycle lives in src/game/root/contract_flow.gd;
## these thin forwarders keep the owner's method names for the remaining call sites.
var _contract_flow_impl  # untyped to avoid a preload cycle
func _contract_flow() -> ContractFlow:
	if _contract_flow_impl == null:
		_contract_flow_impl = ContractFlow.new(self)
	return _contract_flow_impl


func cancel_contract() -> Dictionary:
	return _contract_flow().cancel_contract()


func launch_contract(config: Dictionary) -> Dictionary:
	return _contract_flow().launch_contract(config)


func finish_contract(result: Dictionary) -> Dictionary:
	return _contract_flow().finish_contract(result)


func _defeat_window_holds_screen(completed_result: Dictionary) -> bool:
	return _contract_flow()._defeat_window_holds_screen(completed_result)


func _release_pending_visual_route(reason: String) -> Dictionary:
	return _contract_flow()._release_pending_visual_route(reason)


func skip_defeat_presentation() -> Dictionary:
	return _contract_flow().skip_defeat_presentation()


func defeat_route_report() -> Dictionary:
	return _contract_flow().defeat_route_report()


func leave_result() -> Dictionary:
	return _contract_flow().leave_result()


func _open_next_contract_from_result() -> void:
	_contract_flow()._open_next_contract_from_result()


func review_result_drop(instance_id: String, slot: String) -> Dictionary:
	return _contract_flow().review_result_drop(instance_id, slot)


func open_ending() -> Dictionary:
	return _contract_flow().open_ending()


func leave_ending_to_base() -> Dictionary:
	return _contract_flow().leave_ending_to_base()


func leave_ending_to_title() -> Dictionary:
	return _contract_flow().leave_ending_to_title()


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


## The --mib-* prototype debug tooling lives in
## src/game/root/prototype_debug.gd; these thin forwarders keep the owner's
## method names for the remaining call sites.
var _prototype_debug_impl  # untyped to avoid a preload cycle
func _prototype_debug() -> PrototypeDebug:
	if _prototype_debug_impl == null:
		_prototype_debug_impl = PrototypeDebug.new(self)
	return _prototype_debug_impl


func _consider_prototype_debug(arguments: PackedStringArray) -> void:
	_prototype_debug()._consider_prototype_debug(arguments)


func _apply_prototype_debug_wipe() -> void:
	_prototype_debug()._apply_prototype_debug_wipe()


func _apply_prototype_debug_runtime() -> void:
	_prototype_debug()._apply_prototype_debug_runtime()


## The --auto-smoke replay driver lives in src/game/root/auto_smoke_harness.gd;
## these thin forwarders keep the owner's method names for the remaining call sites.
var _auto_smoke_harness  # untyped to avoid a preload cycle
func _auto_smoke() -> AutoSmokeHarness:
	if _auto_smoke_harness == null:
		_auto_smoke_harness = AutoSmokeHarness.new(self)
	return _auto_smoke_harness


func _start_auto_smoke() -> void:
	_auto_smoke()._start_auto_smoke()


func _continue_auto_smoke(completed_stage: String, arena_result: Dictionary, settlement: Dictionary) -> void:
	_auto_smoke()._continue_auto_smoke(completed_stage, arena_result, settlement)


func _auto_smoke_result_summary(result: Dictionary) -> Dictionary:
	return _auto_smoke()._auto_smoke_result_summary(result)


func _proxy_inventory_ids(profile: Dictionary) -> Array[String]:
	return _auto_smoke()._proxy_inventory_ids(profile)


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

## The route snapshot builders live in src/game/root/route_snapshots.gd;
## these thin forwarders keep the owner's method names for the remaining call sites.
var _route_snapshots_impl  # untyped to avoid a preload cycle
func _route_snapshots() -> RouteSnapshots:
	if _route_snapshots_impl == null:
		_route_snapshots_impl = RouteSnapshots.new(self)
	return _route_snapshots_impl


func _loadout_facility_snapshot() -> Dictionary:
	return _route_snapshots()._loadout_facility_snapshot()


func _campaign_contract_snapshot() -> Dictionary:
	return _route_snapshots()._campaign_contract_snapshot()


func _active_build_from_snapshot(snapshot: Dictionary) -> Dictionary:
	return _route_snapshots()._active_build_from_snapshot(snapshot)


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


## The capture and evidence harness lives in src/game/root/capture_harness.gd;
## these thin forwarders keep the owner's method names for the remaining call sites.
var _capture_harness  # untyped to avoid a preload cycle
func _capture() -> CaptureHarness:
	if _capture_harness == null:
		_capture_harness = CaptureHarness.new(self)
	return _capture_harness


func capture_request_report(arguments: PackedStringArray) -> Dictionary:
	return _capture().capture_request_report(arguments)


func capture_environment_report() -> Dictionary:
	return _capture().capture_environment_report()


func capture_evidence_target_available(path: String) -> Dictionary:
	return _capture().capture_evidence_target_available(path)


func prepare_capture_route(route: String) -> Dictionary:
	return _capture().prepare_capture_route(route)


func _apply_capture_request(request: Dictionary) -> bool:
	return _capture()._apply_capture_request(request)


func _capture_stage() -> String:
	return _capture()._capture_stage()


func _capture_frame(path: String, requested_route: String = "") -> void:
	await _capture().capture_frame(path, requested_route)


func _capture_settlement_stage(stage: String) -> Dictionary:
	return await _capture().settlement_stage(stage)


func _capture_fail_line(error_code: String, detail: String, requested_route: String, actual_route: String, requested_stage: String, capture_path: String) -> void:
	_capture()._capture_fail_line(error_code, detail, requested_route, actual_route, requested_stage, capture_path)


func _capture_contract_fail(report: Dictionary) -> void:
	_capture()._capture_contract_fail(report)


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


## The playtest telemetry lives in src/game/root/playtest_recorder.gd; these
## thin forwarders keep the owner's method names for the remaining call sites.
var _playtest_recorder_impl  # untyped to avoid a preload cycle
func _playtest_recorder() -> PlaytestRecorder:
	if _playtest_recorder_impl == null:
		_playtest_recorder_impl = PlaytestRecorder.new(self)
	return _playtest_recorder_impl


func _start_playtest_logging() -> void:
	_playtest_recorder()._start_playtest_logging()


func _record_playtest(event_id: String, payload: Dictionary = {}) -> void:
	_playtest_recorder()._record_playtest(event_id, payload)


func _finish_playtest_logging(reason: String) -> void:
	_playtest_recorder()._finish_playtest_logging(reason)


func _profile_elapsed_msec() -> int:
	return _playtest_recorder()._profile_elapsed_msec()


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
