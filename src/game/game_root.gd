class_name GameRoot
extends SessionMenuHost

## The application shell: it owns routing, the mounted screen and the save, and
## composes the helper modules in src/game/root/, each of which owns the state of
## one concern (playtest_recorder, route_snapshots, capture, auto_smoke,
## test_console_host, contract_flow, facility_actions, display_settings,
## prototype_debug).
##
## Modules reach the shell only through its public API: status_message,
## transition(), persist(), present_title/base/contract/facility(),
## record_playtest(), request_exit(), is_test_session(), presentation_enabled,
## application_state, scene_router, save_store, playtest_log, current_route,
## current_screen, last_contract, get_presentation_viewport(), get_pixel_stage(),
## the flow_route_changed / flow_error signals and the public flow methods.

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
## Shared by GameRoot and the capture harness; settlement captures only accept it.
const CAPTURE_STAGE_ROUTE: String = "result"
## The published defeat clip may hold the result *screen*, never the result: the
## settlement, the progression, the save and the playtest record already happened
## in the same call that produced this route. This bound is the route layer's own
## clock, so a screen that never reports readiness keeps a corpse for at most
## this long.
const DEFEAT_ROUTE_FALLBACK_SECONDS: float = 1.0

const DEFAULT_SAVE_DIRECTORY: String = "user://framework-saves"
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
		return contract_flow.last_contract.duplicate(true)

## False when the command line passed --presentation-off. Read-only.
var presentation_enabled: bool:
	get:
		return _presentation_enabled

var _current_screen: Node
## Town browsing is transient presentation state, separate from the save schema.
var _town_travel: Dictionary = {}
var _pixel_stage: Control
## Player-facing message the next presented screen shows. Modules write it before
## re-presenting or transitioning.
var status_message: String = ""
## A facility reached from settlement keeps its return destination while domain
## actions re-present that same screen. The one-shot drop focus remains in the
## transition payload; this value only preserves truthful navigation copy.
var _facility_return_route: String = SceneRouterScript.ROUTE_BASE
var _test_session: bool = false
## Set from the launch arguments by DiagnosticsPolicy (always on in debug builds).
var _test_console_enabled: bool = true
var _initialized: bool = false
var _presentation_enabled := true
## Playtest telemetry and the timers it keeps (src/game/root/).
var playtest_recorder: PlaytestRecorder = PlaytestRecorder.new(self)
## Route snapshot builders for the loadout facility and the contract board.
var route_snapshots: RouteSnapshots = RouteSnapshots.new(self)
## The capture and evidence harness: request validation, route preparation and
## settlement evidence (src/game/root/).
var capture: CaptureHarness = CaptureHarness.new(self)
## The deterministic --auto-smoke replay driver and its state (src/game/root/).
var auto_smoke: AutoSmokeHarness = AutoSmokeHarness.new(self)
## The F10 test console and the in-game session menu (src/game/root/).
var test_console_host: TestConsoleHost = TestConsoleHost.new(self)
## The contract lifecycle, the last contract and the deferred result route
## (src/game/root/).
var contract_flow: ContractFlow = ContractFlow.new(self)
## The facility action dispatcher and loadout telemetry (src/game/root/).
var facility_actions: FacilityActions = FacilityActions.new(self)
## Display, audio and player settings, and the shared stage window lease
## (src/game/root/).
var display_settings: DisplaySettings = DisplaySettings.new(self)
## The --mib-* prototype debug tooling and the state it owns (src/game/root/).
var prototype_debug: PrototypeDebug = PrototypeDebug.new(self)


func _enter_tree() -> void:
	if _pixel_stage != null:
		display_settings.acquire_stage_window()


func _ready() -> void:
	Locale.acquire()
	_ensure_pixel_stage()
	initialize()
	if _test_console_enabled:
		test_console_host.ensure_test_console()
	test_console_host.ensure_session_menu()
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
	display_settings.acquire_stage_window()
	_pixel_stage = PixelStageScript.new()
	_pixel_stage.name = "PixelStage"
	_pixel_stage.set_render_quality(display_settings.render_quality)
	add_child(_pixel_stage)
	_pixel_stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func get_test_console() -> CanvasLayer:
	return test_console_host.test_console


func get_session_menu() -> CanvasLayer:
	return test_console_host.session_menu


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
	test_console_host.resume_current_route()
	playtest_recorder.finish("tree_exit")
	display_settings.release_stage_window()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		playtest_recorder.finish("object_freed")
	elif what == NOTIFICATION_WM_WINDOW_FOCUS_OUT and not _test_session \
			and current_route == SceneRouterScript.ROUTE_ARENA:
		test_console_host.open_session_menu()


## Drives the deferred result screen. Nothing authoritative happens here: the
## only work is asking the mounted screen whether its defeat clip is done and
## enforcing this layer's own fallback bound.
func _process(delta: float) -> void:
	if test_console_host.is_session_menu_open():
		return
	contract_flow.advance_pending_route(delta)


func initialize(arguments: PackedStringArray = OS.get_cmdline_user_args()) -> void:
	if _initialized:
		return
	_initialized = true
	if application_state == null:
		application_state = ApplicationStateScript.new()
	if scene_router == null:
		scene_router = SceneRouterScript.new()
	_presentation_enabled = not arguments.has("--presentation-off")
	_test_console_enabled = DiagnosticsPolicy.test_console_enabled(arguments)
	prototype_debug.consider(arguments)
	if save_store == null:
		save_store = SaveStoreScript.new(save_directory_path)
	prototype_debug.apply_wipe()
	if not scene_router.route_changed.is_connected(_on_route_changed):
		scene_router.route_changed.connect(_on_route_changed)
	var capture_path := ""
	auto_smoke.read_state_hash_argument(arguments)
	var request: Dictionary = capture_request_report(arguments)
	if not bool(request.get("ok", false)):
		capture.contract_fail(request)
		return
	capture.request = request
	capture_path = String(request.get("capture_path", ""))
	auto_smoke.session = arguments.has("--auto-smoke")
	_test_session = auto_smoke.session or arguments.has("--smoke") or arguments.has("--game-flow-smoke") or not capture_path.is_empty()
	if playtest_logging_enabled and DiagnosticsPolicy.playtest_logging_enabled(arguments, _test_session) and not prototype_debug.no_persist:
		playtest_recorder.start_session()
	if auto_smoke.session:
		auto_smoke.accelerate()
	_bootstrap(arguments)
	prototype_debug.apply_runtime()
	if not String(request.get("capture_route", "")).is_empty():
		if not capture.apply_request(request):
			return
	if not capture_path.is_empty() and capture.requested_stage().is_empty():
		capture.capture_frame.call_deferred(capture_path, String(request.get("capture_route", "")))
	elif arguments.has("--smoke"):
		_run_scene_smoke.call_deferred()


func start_new_game(initial_class: String = "ranger") -> Dictionary:
	if current_route != SceneRouterScript.ROUTE_TITLE:
		return CoreResult.failure("wrong_route")
	var created: Dictionary = application_state.start_new_profile(initial_class)
	if not bool(created.get("ok", false)):
		present_title(String(created.get("error", "profile_creation_failed")))
		return created
	contract_flow.clear_last_contract()
	playtest_recorder.mark_profile_started()
	record_playtest("profile_started", {"initial_class": String(application_state.profile.get("initial_class", initial_class))})
	status_message = persist("New profile saved", SceneRouterScript.ROUTE_TUTORIAL)
	return transition(SceneRouterScript.ROUTE_TUTORIAL)


func continue_game() -> Dictionary:
	if current_route != SceneRouterScript.ROUTE_TITLE:
		return CoreResult.failure("wrong_route")
	if not application_state.has_profile():
		present_title("No valid profile is available.")
		return CoreResult.failure("profile_required")
	var profile: Dictionary = application_state.profile
	return transition(SceneRouterScript.ROUTE_BASE if bool(profile.get("tutorial_complete", false)) else SceneRouterScript.ROUTE_TUTORIAL)


func complete_tutorial() -> Dictionary:
	if current_route != SceneRouterScript.ROUTE_TUTORIAL:
		return CoreResult.failure("wrong_route")
	var completed: Dictionary = application_state.complete_tutorial()
	if not bool(completed.get("ok", false)):
		return completed
	record_playtest("tutorial_completed", {"initial_class": String(application_state.profile.get("initial_class", ""))})
	status_message = persist("Ranger basics tutorial complete", SceneRouterScript.ROUTE_BASE)
	return transition(SceneRouterScript.ROUTE_BASE)


func open_contract() -> Dictionary:
	if current_route != SceneRouterScript.ROUTE_BASE:
		return CoreResult.failure("wrong_route")
	status_message = ""
	return transition(SceneRouterScript.ROUTE_CONTRACT)


func open_story() -> Dictionary:
	if current_route != SceneRouterScript.ROUTE_BASE: return CoreResult.failure("wrong_route")
	return transition(SceneRouterScript.ROUTE_STORY)


func read_story_entry(entry_id: String) -> Dictionary:
	if current_route != SceneRouterScript.ROUTE_STORY: return CoreResult.failure("wrong_route")
	var result: Dictionary = application_state.mark_story_read(entry_id)
	if bool(result.get("ok",false)): persist("Observation recorded.", SceneRouterScript.ROUTE_BASE)
	return result


func read_town_conversation(entry_id: String) -> Dictionary:
	if current_route != SceneRouterScript.ROUTE_BASE: return CoreResult.failure("wrong_route")
	var available := false
	for conversation: Dictionary in application_state.story_snapshot().get("available_conversations", []):
		if String(conversation.id) == entry_id: available = true
	if not available: return CoreResult.failure("story_entry_unavailable")
	var result: Dictionary = application_state.mark_story_read(entry_id)
	if bool(result.get("ok", false)):
		persist("", SceneRouterScript.ROUTE_BASE)
		_current_screen.present_adventure(application_state.character_snapshot(), application_state.story_snapshot())
	return result



func open_character() -> Dictionary:
	if current_route != SceneRouterScript.ROUTE_BASE: return CoreResult.failure("wrong_route")
	return transition(SceneRouterScript.ROUTE_CHARACTER)


func close_adventure_page() -> Dictionary:
	if current_route not in [SceneRouterScript.ROUTE_CHARACTER, SceneRouterScript.ROUTE_STORY]: return CoreResult.failure("wrong_route")
	return transition(SceneRouterScript.ROUTE_BASE)


func change_character_talent(action: String, value: String = "") -> Dictionary:
	if current_route != SceneRouterScript.ROUTE_CHARACTER: return CoreResult.failure("wrong_route")
	var result: Dictionary = application_state.change_talent(action, value)
	var message := ""
	if not bool(result.get("ok",false)):
		message = "Invalid allocation: check available points, tier investment, and keystone count."
	else:
		message = persist("", SceneRouterScript.ROUTE_BASE)
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
	status_message = ""
	return transition(route)


func leave_facility() -> Dictionary:
	if current_route not in FACILITY_ROUTES:
		return CoreResult.failure("wrong_route")
	return transition(SceneRouterScript.ROUTE_BASE)


## Dispatches a facility screen action to the facility action service.
func request_facility_action(facility_id: String, action_id: String, payload: Dictionary = {}) -> Dictionary:
	return facility_actions.request_facility_action(facility_id, action_id, payload)


func return_to_title() -> Dictionary:
	if current_route != SceneRouterScript.ROUTE_BASE:
		return CoreResult.failure("wrong_route")
	status_message = persist("Profile saved", SceneRouterScript.ROUTE_TITLE)
	return transition(SceneRouterScript.ROUTE_TITLE)


## Contract lifecycle entry points that screen signals connect to; the service
## lives in src/game/root/contract_flow.gd.
func cancel_contract() -> Dictionary:
	return contract_flow.cancel_contract()


func launch_contract(config: Dictionary) -> Dictionary:
	return contract_flow.launch_contract(config)


func finish_contract(result: Dictionary) -> Dictionary:
	return contract_flow.finish_contract(result)


func skip_defeat_presentation() -> Dictionary:
	return contract_flow.skip_defeat_presentation()


func defeat_route_report() -> Dictionary:
	return contract_flow.defeat_route_report()


func leave_result() -> Dictionary:
	return contract_flow.leave_result()


func review_result_drop(instance_id: String, slot: String) -> Dictionary:
	return contract_flow.review_result_drop(instance_id, slot)


func open_ending() -> Dictionary:
	return contract_flow.open_ending()


func leave_ending_to_base() -> Dictionary:
	return contract_flow.leave_ending_to_base()


func leave_ending_to_title() -> Dictionary:
	return contract_flow.leave_ending_to_title()


func _bootstrap(arguments: PackedStringArray) -> void:
	if arguments.has("--auto-smoke"):
		auto_smoke.start()
		return
	if prototype_debug.rejected:
		transition(SceneRouterScript.ROUTE_TITLE)
		return

	var initial_route: String = SceneRouterScript.ROUTE_TITLE
	var loaded: Dictionary = save_store.load_latest()
	if bool(loaded.get("ok", false)):
		var restored: Dictionary = application_state.restore_persistent_payload(loaded.get("payload", {}))
		if bool(restored.get("ok", false)):
			initial_route = String(restored.get("route", SceneRouterScript.ROUTE_TITLE))
			status_message = "Restored save generation %d." % int(loaded.get("generation", 0))
		else:
			status_message = PlayerFacingStatusScript.failure("Load profile", String(restored.get("error", "invalid_payload")))
	elif String(loaded.get("error", "")) != "no valid save slot":
		status_message = PlayerFacingStatusScript.failure("Load profile", String(loaded.get("error", "unknown_error")))
	transition(initial_route)


## True for --smoke, --game-flow-smoke, --auto-smoke and capture runs, which never
## write saves or settings.
func is_test_session() -> bool:
	return _test_session


## Requests a route change through the scene router and renders it. Returns the
## router's result; emits flow_error when the request is refused.
func transition(route: String, payload: Dictionary = {}) -> Dictionary:
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
	contract_flow.supersede_pending_route()
	playtest_recorder.record_route_change(previous_route, route)
	flow_route_changed.emit(previous_route, route)
	test_console_host.refresh_test_console()


func _render_route(route: String, payload: Dictionary = {}) -> void:
	test_console_host.sync_route(route)
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
			present_title(status_message)
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
			screen.feature_requested.connect(open_facility)
			screen.character_requested.connect(open_character)
			screen.story_requested.connect(open_story)
			screen.conversation_read.connect(read_town_conversation)
			_current_screen = screen
			_mount_screen(screen)
			present_base(status_message)
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
			screen.base_requested.connect(request_facility_back.bind(back_destination, String(payload.get("review_instance_id", ""))))
			screen.destination_requested.connect(request_facility_destination)
			screen.action_requested.connect(request_facility_action)
			_current_screen = screen
			_mount_screen(screen)
			present_facility(route, status_message, payload)
		SceneRouterScript.ROUTE_CONTRACT:
			var screen = ContractScreenScript.new()
			screen.start_requested.connect(launch_contract)
			screen.cancel_requested.connect(cancel_contract)
			_current_screen = screen
			_mount_screen(screen)
			present_contract(status_message)
		SceneRouterScript.ROUTE_ARENA:
			var screen: Node = make_arena_screen()
			if screen == null:
				_handle_arena_launch_failure("room_runtime_factory_failed")
				return
			screen.connect("completed", _settle_arena_result)
			screen.connect("abandoned", _settle_arena_result)
			_current_screen = screen
			_mount_screen(screen)
			var launch_result: Variant = screen.start_session(payload.duplicate(true))
			display_settings.apply_route_preferences()
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
			screen.contract_requested.connect(contract_flow.open_next_contract_from_result)
			_current_screen = screen
			_mount_screen(screen)
			screen.present(application_state.last_result, contract_flow.last_contract, application_state.profile)
			screen.focus_equipment(String(payload.get("review_instance_id", "")))
		SceneRouterScript.ROUTE_ENDING:
			var screen = EndingScreenScript.new()
			screen.base_requested.connect(leave_ending_to_base)
			screen.title_requested.connect(leave_ending_to_title)
			_current_screen = screen
			_mount_screen(screen)
			screen.present(application_state.profile, application_state.last_result)


## Builds the arena screen node: the room_runtime_factory result when one is set,
## otherwise the real contract run controller bound to the application state.
func make_arena_screen() -> Node:
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


func _settle_arena_result(result: Dictionary) -> void:
	var stage := auto_smoke.stage
	var settled: Dictionary = finish_contract(result)
	auto_smoke.on_arena_settled(stage, result, settled)


## Facility screen navigation to another facility; refused unless the router allows it.
func request_facility_destination(route: String) -> void:
	if route not in FACILITY_ROUTES or not scene_router.can_transition(route):
		flow_error.emit("facility_destination_blocked", "%s -> %s" % [current_route, route])
		return
	status_message = ""
	transition(route)


## Facility screen back button: returns to the result review or leaves to the base.
func request_facility_back(destination: String, reviewed_item_id: String = "") -> void:
	if destination == SceneRouterScript.ROUTE_RESULT \
			and current_route == SceneRouterScript.ROUTE_LOADOUT \
			and not application_state.last_result.is_empty() \
			and scene_router.can_transition(SceneRouterScript.ROUTE_RESULT):
		transition(SceneRouterScript.ROUTE_RESULT, {"review_instance_id": reviewed_item_id})
		return
	leave_facility()


## Presents the title screen with the given message when it is the current screen.
func present_title(message: String) -> void:
	if _current_screen is TitleScreenScript:
		_current_screen.present(application_state.has_profile(), message)


## Presents the base hub with the given message when it is the current screen.
func present_base(message: String) -> void:
	if _current_screen is BaseHubScreenScript:
		_current_screen.present(application_state.profile, application_state.last_result, message, route_snapshots.campaign_contract_snapshot())

		_current_screen.present_adventure(application_state.character_snapshot(), application_state.story_snapshot())


## Presents the contract board with the given message when it is the current screen.
func present_contract(message: String) -> void:
	if _current_screen is ContractScreenScript:
		var build_snapshot: Dictionary = application_state.early_game_snapshot().duplicate(true)
		if bool(build_snapshot.get("ok", false)):
			build_snapshot["resolved_build"] = application_state.resolved_build_snapshot().duplicate(true)
		build_snapshot["auto_mode_unlocked"] = application_state.is_auto_mode_unlocked()
		build_snapshot["campaign"] = route_snapshots.campaign_contract_snapshot()
		_current_screen.present(application_state.profile, contract_flow.last_contract, message, build_snapshot)


## Presents a facility screen; context carries one-shot loadout focus hints.
func present_facility(facility_id: String, message: String, presentation_context: Dictionary = {}) -> void:
	if _current_screen is FacilityScreenScript:
		var facility_data: Dictionary = {}
		if facility_id == SceneRouterScript.ROUTE_FORGE:
			application_state.forge_ensure_context()
			facility_data = application_state.forge_snapshot()
		elif facility_id == SceneRouterScript.ROUTE_LOADOUT:
			facility_data = route_snapshots.loadout_facility_snapshot()
			facility_data["return_route"] = _facility_return_route
			if not presentation_context.is_empty():
				facility_data["initial_focus"] = presentation_context.duplicate(true)
		elif facility_id == SceneRouterScript.ROUTE_TRAINING:
			facility_data = application_state.early_game_snapshot()
			if bool(facility_data.get("ok", false)):
				facility_data["resolved_build"] = application_state.resolved_build_snapshot().duplicate(true)
		elif facility_id == SceneRouterScript.ROUTE_PROXY:
			facility_data = application_state.early_game_snapshot()
		_current_screen.present(facility_id, application_state.profile, application_state.last_result, message, facility_data)


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


## Saves the profile unless this is a test session or prototype debug no-persist
## run. Returns reason on success, or a player-facing save failure message.
func persist(reason: String, safe_route: String) -> String:
	if _test_session or prototype_debug.no_persist:
		return reason
	var saved: Dictionary = save_store.save(application_state.persistent_payload(safe_route))
	if bool(saved.get("ok", false)):
		return reason
	var detail := String(saved.get("error", "unknown error"))
	flow_error.emit("save_failed", detail)
	return PlayerFacingStatusScript.error_message("save_failed")


## Capture entry points; the harness lives in src/game/root/capture_harness.gd.
func capture_request_report(arguments: PackedStringArray) -> Dictionary:
	return capture.capture_request_report(arguments)


func capture_environment_report() -> Dictionary:
	return capture.capture_environment_report()


func capture_evidence_target_available(path: String) -> Dictionary:
	return capture.capture_evidence_target_available(path)


func prepare_capture_route(route: String) -> Dictionary:
	return capture.prepare_capture_route(route)


## Reports the final exit code to exit_code_hook instead of ending the process.
func request_exit(code: int, reason: String) -> void:
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


## Appends one event to the playtest log when logging is active.
func record_playtest(event_id: String, payload: Dictionary = {}) -> void:
	playtest_recorder.record(event_id, payload)


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
