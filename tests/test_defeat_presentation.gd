extends SceneTree

## Real-death acceptance for the two-phase defeat delivery.
##
## Phase 1 -- authoritative, immediate: a real impact latches the defeat on the
## death tick and the session completes once on the very next router frame,
## before the published death clip has finished. Nothing about the picture can
## delay the result, the rewards or the save.
## Phase 2 -- visual, bounded: the arena screen the session already has keeps
## drawing the published clip, the route layer defers only the result *screen*
## until the clip reports done (or its own one-second bound passes), and a public
## skip releases it early. The settlement is never replayed.
##
## Honored contracts:
##  * the death is never hand-filled. A real melee pursuer in the production room
##    roster lands its own contact damage through _enemy_ai._update_melee_tick(); the only
##    fixtures are the roster, the enemy's starting contact distance and a health
##    value equal to that one impact.
##  * the GameRoot layer asserts the settlement at its real time point through
##    the durable save generation, the saved payload and the playtest record --
##    not through a cached field.
##  * frames are driven at 30/60/144Hz in the real processing order: the router is
##    the parent node of the arena it mounted, so it processes first.

const GameRootScript := preload("res://src/game/game_root.gd")
const CombatRoomRuntimeScript := preload("res://src/game/combat_room_runtime.gd")
const DefeatPresentationScript := preload("res://src/presentation/defeat_presentation.gd")
const EarlyItemRegistryScript := preload("res://src/content/early_item_registry.gd")
const BuildResolverScript := preload("res://src/systems/build_resolver.gd")

## Production melee contact damage (main.gd _update_melee_tick). A health value
## equal to it means one real impact is fatal; the impact is still the death.
const MELEE_CONTACT_DAMAGE: float = 5.0
const MELEE_CONTACT_SOURCE := "enemy/1/melee_pursuer"
const ONE_FRAME_SECONDS := 1.0 / 6.0
const FRAME_RATES: Array[int] = [30, 60, 144]
const MAX_ALIVE_FRAMES: int = 600
const MAX_WINDOW_FRAMES: int = 400
const TEST_SAVE_DIRECTORY: String = "user://makeitbig-defeat-window-tests"


## The arena screen GameRoot mounts in place of the real controller. It carries
## no authoritative state: it only reports defeat readiness on demand, so the
## route layer can be exercised without a battle.
class DeathScreen:
	extends Node

	signal completed(result: Dictionary)
	signal abandoned(result: Dictionary)

	## false = the published defeat clip is still playing on this screen.
	var clip_ready := false
	var started := false
	var config: Dictionary = {}

	func start_session(value: Dictionary) -> Dictionary:
		if started:
			return {"ok": false, "error": "already_started"}
		started = true
		config = value.duplicate(true)
		return {"ok": true}

	func defeat_presentation_ready() -> bool:
		return clip_ready

	func resolve(result: Dictionary) -> void:
		completed.emit(result.duplicate(true))

	func cancel(result: Dictionary) -> void:
		abandoned.emit(result.duplicate(true))


class FakePlaytestLog:
	extends RefCounted

	var events: Array[Dictionary] = []
	var active := false

	func start_session(context: Dictionary, _requested_session_id: String = "") -> Dictionary:
		active = true
		events.append({"event_id": "session_started", "payload": {}, "context": context.duplicate(true)})
		return {"ok": true}

	func record(event_id: String, payload: Dictionary = {}) -> Dictionary:
		if not active:
			return {"ok": false, "error": "session_not_started"}
		events.append({"event_id": event_id, "payload": payload.duplicate(true)})
		return {"ok": true}

	func finish(payload: Dictionary = {}) -> Dictionary:
		var recorded := record("session_finished", payload)
		active = false
		return recorded

	func is_active() -> bool:
		return active


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	# Pin the viewport so the arena rectangle and spawn geometry stay stable.
	root.size = Vector2i(1280, 720)
	var failures: Array[String] = []
	_test_window_contract(failures)
	var death_ticks: Array[int] = []
	for rate: int in FRAME_RATES:
		death_ticks.append(_test_real_death(failures, rate))
	var consistent := death_ticks.size() == FRAME_RATES.size()
	for tick: int in death_ticks:
		consistent = consistent and tick == death_ticks[0]
	_expect(consistent, "real death: the authoritative death tick moved with the frame rate: %s" % str(death_ticks), failures)
	_test_presentation_off(failures)
	_test_return_button_skip(failures)
	_test_settlement_before_screen_swap(failures)
	_test_ready_release_and_skip(failures)
	_test_unchanged_outcomes(failures)
	_test_production_chain(failures)
	_finish(failures)


## The shared window's own contract: published frames, the last-frame hold, the
## named skip, reset, and the frames it refuses to count.
func _test_window_contract(failures: Array[String]) -> void:
	var window = DefeatPresentationScript.new({"frames": 3, "fps": 6})
	_expect(window.frame_count() == 3 and is_equal_approx(window.frame_seconds(), ONE_FRAME_SECONDS),
		"window: the published death timing was not adopted", failures)
	_expect(not window.route_ready() and String(window.state()) == DefeatPresentationScript.STATE_WAITING,
		"window: a fresh window already reported the clip as shown", failures)
	var delta := 1.0 / 60.0
	## A live non-death frame and a fallback frame are not published death frames.
	window.observe_frame({"action": "idle", "frame": 0, "frame_count": 1, "fps": 8, "fallback": false}, delta)
	window.observe_frame({"action": "death", "frame": 0, "fallback": true}, delta)
	_expect(window.committed_frames() == 0 and not window.route_ready(),
		"window: a non-death or fallback frame was counted as the defeat clip", failures)
	## Two frames on screen forever never close it: the last frame is missing.
	for _index in 60:
		window.observe_frame(_death_frame(0), delta)
		window.observe_frame(_death_frame(1), delta)
	_expect(not window.route_ready() and str(window.report().get("missing_frames", [])) == "[2]",
		"window: a clip that never drew its last frame was reported as shown", failures)
	## Less than the published 1/6s of last frame is not enough ...
	for _index in 9:
		window.observe_frame(_death_frame(2), delta)
	_expect(not window.route_ready(), "window: the last frame closed the window before its published 1/6s", failures)
	## ... and the tenth 1/60s step is.
	window.observe_frame(_death_frame(2), delta)
	_expect(window.route_ready() and String(window.state()) == DefeatPresentationScript.STATE_COMPLETE,
		"window: the published last-frame hold did not close the window", failures)
	_expect(is_equal_approx(window.closed_seconds(), window.screen_seconds()),
		"window: the window closed at a screen time it never recorded", failures)
	window.reset()
	_expect(not window.route_ready() and String(window.state()) == DefeatPresentationScript.STATE_WAITING and window.committed_frames() == 0,
		"window: reset kept stale screen evidence", failures)
	window.skip("unit")
	_expect(window.route_ready() and String(window.state()) == DefeatPresentationScript.STATE_SKIPPED
		and String(window.report().get("skip_reason", "")) == "unit",
		"window: the named skip was not recorded", failures)


## Real death at one render rate. Returns the authoritative death tick.
func _test_real_death(failures: Array[String], rate: int) -> int:
	var tag := "%dHz" % rate
	var delta := 1.0 / float(rate)
	var session := _start_death_session(failures, true)
	var arena: Node = session.get("arena")
	var runtime: Node = session.get("runtime")
	var completed: Array = session.get("completed")
	if arena == null or runtime == null:
		_teardown(session)
		return -1

	# --- phase 1a: the production simulation lands its own fatal impact.
	var death_tick := -1
	for _frame_index in MAX_ALIVE_FRAMES:
		_advance_frame(session, delta)
		if float(arena.get("player_health")) <= 0.0:
			death_tick = int(arena.get("sim_tick"))
			break
	if death_tick < 0:
		_expect(false, "real death %s: the melee pursuer never landed a fatal impact" % tag, failures)
		_teardown(session)
		return -1
	_expect(bool(arena.get("battle_over")) and not bool(arena.get("battle_victory")),
		"real death %s: the defeat did not latch on the death tick" % tag, failures)
	var player: Dictionary = arena.player_combat_state.snapshot(arena.sim_tick)
	_expect(String(player.last_damage_source_id) == MELEE_CONTACT_SOURCE and int(player.last_damage_tick) == death_tick,
		"real death %s: the lethal damage did not come from the melee pursuer on the death tick" % tag, failures)
	_expect(String(arena.get("battle_report")).begins_with("DEFEAT"),
		"real death %s: the defeat report was not latched with the death" % tag, failures)
	_expect(completed.is_empty(), "real death %s: the settlement ran inside the death frame's own arena pass" % tag, failures)
	var death_report: Dictionary = arena.call("defeat_presentation_report")
	_expect(not bool(death_report.get("route_ready", true)) and String(death_report.get("hold_reason", "")) == DefeatPresentationScript.HOLD_REASON,
		"real death %s: the arena did not hold its side of the window on the death frame" % tag, failures)

	# --- phase 1b: the session completes on the next router frame, while the clip
	# is still playing and the screen is still the arena.
	_advance_frame(session, delta)
	_expect(completed.size() == 1, "real death %s: the session did not complete once right after the death" % tag, failures)
	if completed.size() == 1:
		var result: Dictionary = completed[0]
		_expect(String(result.get("outcome", "")) == "defeat" and String(result.get("failure_reason", "")) == MELEE_CONTACT_SOURCE
			and int(result.get("death_tick", -1)) == death_tick and int(result.get("ticks", -1)) == death_tick,
			"real death %s: the completed result lost the authoritative death" % tag, failures)
	var window_at_settlement: Dictionary = (arena.call("defeat_presentation_report") as Dictionary).get("window", {})
	_expect(String(window_at_settlement.get("state", "")) != DefeatPresentationScript.STATE_COMPLETE,
		"real death %s: the settlement waited for the death clip to finish" % tag, failures)
	_expect(not bool(runtime.call("defeat_presentation_ready")),
		"real death %s: the arena reported the clip done while it was still playing" % tag, failures)
	_expect(int(arena.get("sim_tick")) == death_tick,
		"real death %s: the simulation kept ticking after the death" % tag, failures)

	# --- phase 2: the clip finishes on the screen the session already has, and the
	# relay only then reports the visual window done.
	var non_death_frames: Array[String] = []
	var window_frames := 0
	var ready_at := -1
	for _frame_index in MAX_WINDOW_FRAMES:
		_advance_frame(session, delta)
		window_frames += 1
		var action := String((arena.presentation.animations.ranger_frame as Dictionary).get("action", ""))
		if action != DefeatPresentationScript.ACTION_DEATH:
			non_death_frames.append("window frame %d drew '%s'" % [window_frames, action])
		if bool(runtime.call("defeat_presentation_ready")):
			ready_at = window_frames
			break
	_expect(ready_at > 0, "real death %s: the published death clip never finished on screen" % tag, failures)
	_expect(non_death_frames.is_empty(),
		"real death %s: the drawn hero frame left the death clip while the corpse was on screen: %s" % [tag, ", ".join(PackedStringArray(non_death_frames))], failures)
	var window: Dictionary = (arena.call("defeat_presentation_report") as Dictionary).get("window", {})
	_expect(String(window.get("state", "")) == DefeatPresentationScript.STATE_COMPLETE,
		"real death %s: the routed window state was '%s'" % [tag, String(window.get("state", ""))], failures)
	_expect(int(window.get("frames_seen", 0)) == int(window.get("frame_count", 0)) and str(window.get("missing_frames", [])) == "[]",
		"real death %s: published death frames never reached the screen: %s" % [tag, str(window.get("missing_frames", []))], failures)
	_expect(float(window.get("last_frame_seconds", 0.0)) + DefeatPresentationScript.DURATION_EPSILON >= ONE_FRAME_SECONDS,
		"real death %s: the last death frame was on screen for %.4fs, not the published 1/6s" % [tag, float(window.get("last_frame_seconds", 0.0))], failures)
	_expect(float(window.get("closed_seconds", -1.0)) > 0.0 and float(window.get("closed_seconds", 0.0)) <= 1.0,
		"real death %s: the window closed at %.4fs, outside its bound" % [tag, float(window.get("closed_seconds", -1.0))], failures)
	_expect(int(arena.get("sim_tick")) == death_tick,
		"real death %s: the simulation moved while the corpse was on screen" % tag, failures)

	# --- repeats and exits never settle a defeat twice.
	runtime.call("_process", delta)
	runtime.call("request_abandon")
	arena.call("defeat_skip_presentation", "after_window")
	runtime.call("_process", delta)
	_expect(completed.size() == 1 and (session.get("abandoned") as Array).is_empty(),
		"real death %s: a repeat, abandon or skip re-settled the result" % tag, failures)
	_teardown(session)
	return death_tick


## Presentation off: no window object, no hold, the same defeat.
func _test_presentation_off(failures: Array[String]) -> void:
	var delta := 1.0 / 60.0
	var session := _start_death_session(failures, false)
	var arena: Node = session.get("arena")
	var runtime: Node = session.get("runtime")
	var completed: Array = session.get("completed")
	if arena == null or runtime == null:
		_teardown(session)
		return
	_expect(arena.get("defeat_presentation") == null,
		"presentation off: a defeat window was created without presentation", failures)
	var death_tick := -1
	for _frame_index in MAX_ALIVE_FRAMES:
		_advance_frame(session, delta)
		if float(arena.get("player_health")) <= 0.0:
			death_tick = int(arena.get("sim_tick"))
			break
	if death_tick < 0:
		_expect(false, "presentation off: the melee pursuer never landed a fatal impact", failures)
		_teardown(session)
		return
	_expect(bool(runtime.call("defeat_presentation_ready")),
		"presentation off: the relay held a route without presentation", failures)
	_expect(float((arena.call("defeat_presentation_report") as Dictionary).get("death_seconds", -1.0)) == 0.0,
		"presentation off: the defeat clock advanced without presentation", failures)
	_advance_frame(session, delta)
	_expect(completed.size() == 1, "presentation off: the defeat did not complete once on the next frame", failures)
	if completed.size() == 1:
		_expect(String(completed[0].get("outcome", "")) == "defeat" and int(completed[0].get("ticks", -1)) == death_tick,
			"presentation off: the completed result lost the authoritative defeat", failures)
	_teardown(session)


## The player-facing skip: once the session is settled the runtime is finalized,
## and the real return button on the arena screen still has to end the window.
func _test_return_button_skip(failures: Array[String]) -> void:
	var delta := 1.0 / 60.0
	var session := _start_death_session(failures, true)
	var arena: Node = session.get("arena")
	var runtime: Node = session.get("runtime")
	var completed: Array = session.get("completed")
	if arena == null or runtime == null:
		_teardown(session)
		return
	var death_tick := -1
	for _frame_index in MAX_ALIVE_FRAMES:
		_advance_frame(session, delta)
		if float(arena.get("player_health")) <= 0.0:
			death_tick = int(arena.get("sim_tick"))
			break
	if death_tick < 0:
		_expect(false, "return button: the melee pursuer never landed a fatal impact", failures)
		_teardown(session)
		return
	## The settlement frame: the result is settled, the clip is still playing.
	_advance_frame(session, delta)
	_expect(completed.size() == 1, "return button: the session did not settle before the press", failures)
	var window_before: Dictionary = (arena.call("defeat_presentation_report") as Dictionary).get("window", {})
	_expect(String(window_before.get("state", "")) == DefeatPresentationScript.STATE_PLAYING
		and not bool(runtime.call("defeat_presentation_ready")),
		"return button: the window was not live and holding before the press", failures)
	var button: Variant = arena.presentation.hud.find_child("ReturnButton", true, false)
	_expect(button is Button and bool((button as Button).visible),
		"return button: the defeat screen offered no visible return button", failures)
	if button is Button:
		(button as Button).emit_signal("pressed")
	var window_after: Dictionary = (arena.call("defeat_presentation_report") as Dictionary).get("window", {})
	_expect(String(window_after.get("state", "")) == DefeatPresentationScript.STATE_SKIPPED
		and String(window_after.get("skip_reason", "")) == "return_to_base",
		"return button: a post-settlement press did not end the defeat window (state=%s)" % String(window_after.get("state", "")), failures)
	_expect(bool(runtime.call("defeat_presentation_ready")),
		"return button: the arena kept holding the route after the press", failures)
	_expect(completed.size() == 1 and (session.get("abandoned") as Array).is_empty(),
		"return button: the skip re-settled or abandoned the settled result", failures)
	if completed.size() == 1:
		_expect(String(completed[0].get("outcome", "")) == "defeat" and int(completed[0].get("ticks", -1)) == death_tick,
			"return button: the skip changed the settled result", failures)
	_teardown(session)


## The settlement's real time point: complete_session(), the progression, the
## save and the playtest record all land inside the defeat frame, while the arena
## screen is still mounted. Then the route layer's own bound releases it.
func _test_settlement_before_screen_swap(failures: Array[String]) -> void:
	var session := _open_arena(failures, 7101)
	var game = session.get("game")
	var screen = session.get("screen")
	if game == null or screen == null:
		_teardown_game(session)
		return
	var generation_before := _save_generation(game)
	## Setup steps persist on their own, so the generation is relative here: the
	## settlement has to add exactly one, at its own time point.
	_expect(generation_before > 0, "game root: the profile setup never reached a save slot", failures)
	var events_before := _events_of(session.get("logger"), "contract_finished").size()
	screen.call("resolve", _defeat_result())

	# --- the settlement is durable and complete, on the arena screen.
	_expect(game.current_route == "arena", "game root: the result screen was swapped in without waiting (route=%s)" % game.current_route, failures)
	_expect(game.current_screen == screen and is_instance_valid(screen) and not screen.is_queued_for_deletion(),
		"game root: the arena screen was retired by the settlement", failures)
	var settled: Dictionary = game.save_store.load_latest()
	_expect(bool(settled.get("ok", false)) and int(settled.get("generation", -1)) == generation_before + 1,
		"game root: the defeat was not saved at its settlement time point (generation %s)" % str(settled.get("generation", -1)), failures)
	var payload: Dictionary = settled.get("payload", {}) if settled.get("payload", {}) is Dictionary else {}
	var saved_result: Dictionary = payload.get("last_result", {}) if payload.get("last_result", {}) is Dictionary else {}
	_expect(String(saved_result.get("outcome", "")) == "defeat" and String(saved_result.get("failure_reason", "")) == MELEE_CONTACT_SOURCE,
		"game root: the saved payload does not carry the settled defeat", failures)
	_expect(String(payload.get("safe_route", "")) == "base",
		"game root: the saved profile did not keep the recovery-safe route", failures)
	var settled_events := _events_of(session.get("logger"), "contract_finished")
	_expect(settled_events.size() == events_before + 1, "game root: the defeat was not recorded exactly once at settlement", failures)
	if settled_events.size() == events_before + 1:
		var recorded: Dictionary = settled_events[-1].get("payload", {})
		_expect(String(recorded.get("outcome", "")) == "defeat" and String(recorded.get("failure_reason", "")) == MELEE_CONTACT_SOURCE,
			"game root: the playtest settlement record lost the defeat", failures)
	_expect(String(game.application_state.last_result.get("outcome", "")) == "defeat",
		"game root: the application state did not hold the settled defeat", failures)
	var report: Dictionary = game.call("defeat_route_report")
	_expect(bool(report.get("pending", false)) and String(report.get("released_by", "")) == "",
		"game root: no result screen was pending after a defeat", failures)

	# --- a duplicate settlement while the result waits is refused outright.
	var last_result_before: Dictionary = game.application_state.last_result
	var duplicate: Dictionary = game.call("finish_contract", _defeat_result())
	_expect(not bool(duplicate.get("ok", false)) and String(duplicate.get("error", "")) == "result_pending",
		"game root: a duplicate settlement was not refused while the result was pending: %s" % str(duplicate), failures)
	_expect(_save_generation(game) == generation_before + 1,
		"game root: the duplicate settlement saved a second time", failures)
	_expect(_events_of(session.get("logger"), "contract_finished").size() == events_before + 1,
		"game root: the duplicate settlement was recorded twice", failures)
	_expect(game.application_state.last_result == last_result_before,
		"game root: the duplicate settlement rewrote last_result", failures)

	# --- the route layer's bound releases the screen when readiness never arrives.
	var delta := 1.0 / 60.0
	var held_frames := 0
	for _frame_index in 120:
		if game.current_route != "arena":
			break
		game.call("_process", delta)
		held_frames += 1
	_expect(game.current_route == "result", "game root: a screen that never reported readiness never let the result in", failures)
	var held_seconds := float(held_frames) * delta
	var bound: float = float(GameRootScript.DEFEAT_ROUTE_FALLBACK_SECONDS)
	_expect(held_seconds >= bound - delta and held_seconds <= bound + 2.0 * delta,
		"game root: the fallback released the screen after %.3fs instead of %.3fs" % [held_seconds, bound], failures)
	var released: Dictionary = game.call("defeat_route_report")
	_expect(String(released.get("released_by", "")) == "fallback" and not bool(released.get("pending", true)),
		"game root: the fallback release was not disclosed", failures)
	_expect(_save_generation(game) == generation_before + 1,
		"game root: the screen swap saved the settlement a second time", failures)
	_expect(_events_of(session.get("logger"), "contract_finished").size() == events_before + 1,
		"game root: the screen swap re-settled the defeat", failures)
	_teardown_game(session)


## Readiness releases the screen before the bound, and the public skip releases it
## on demand -- once, never twice.
func _test_ready_release_and_skip(failures: Array[String]) -> void:
	var session := _open_arena(failures, 7102)
	var game = session.get("game")
	var screen = session.get("screen")
	var logger = session.get("logger")
	if game == null or screen == null:
		_teardown_game(session)
		return
	var delta := 1.0 / 60.0
	var generation_at_open := _save_generation(game)
	screen.call("resolve", _defeat_result())
	for _index in 10:
		game.call("_process", delta)
	_expect(game.current_route == "arena", "game root: the result screen arrived before the clip was done", failures)
	screen.set("clip_ready", true)
	for _index in 2:
		game.call("_process", delta)
	_expect(game.current_route == "result", "game root: a finished clip did not release the result screen", failures)
	var report: Dictionary = game.call("defeat_route_report")
	_expect(String(report.get("released_by", "")) == "ready"
		and float(report.get("held_seconds", 0.0)) < float(GameRootScript.DEFEAT_ROUTE_FALLBACK_SECONDS),
		"game root: the clip release was not the one that moved the route", failures)
	var generation_after_ready := _save_generation(game)
	_expect(generation_after_ready == generation_at_open + 1 and _events_of(logger, "contract_finished").size() == 1,
		"game root: the clip release settled the defeat again", failures)

	# --- the public skip: the same settlement, released on demand.
	_expect(bool(game.leave_result().get("ok", false)), "game root: the result route did not close", failures)
	_expect(bool(game.open_contract().get("ok", false)), "game root: the contract board did not reopen", failures)
	_expect(bool(game.launch_contract({"contract_id": "mainline_01_first_hunt", "mode": "Manual", "seed": 7103, "room_count": 1}).get("ok", false)),
		"game root: the retry contract did not launch", failures)
	var second_screen = game.current_screen
	if second_screen == null or not second_screen.has_method("resolve"):
		_expect(false, "game root: the retry contract did not mount the arena screen", failures)
		_teardown_game(session)
		return
	var generation_before_skip := _save_generation(game)
	second_screen.call("resolve", _defeat_result(7103))
	_expect(game.current_route == "arena", "game root: the retry defeat did not wait for its clip", failures)
	var skipped: Dictionary = game.call("skip_defeat_presentation")
	_expect(bool(skipped.get("ok", false)) and game.current_route == "result",
		"game root: the public skip did not release the result screen: %s" % str(skipped), failures)
	_expect(String(game.call("defeat_route_report").get("released_by", "")) == "skipped",
		"game root: the skip was not disclosed as the release", failures)
	_expect(_save_generation(game) == generation_before_skip + 1,
		"game root: the skip did not settle exactly once", failures)
	_expect(_events_of(logger, "contract_finished").size() == 2, "game root: the skip re-settled the defeat", failures)
	var repeated: Dictionary = game.call("skip_defeat_presentation")
	_expect(not bool(repeated.get("ok", false)) and String(repeated.get("error", "")) == "no_pending_route",
		"game root: a repeated skip was accepted after the route moved", failures)
	_expect(_save_generation(game) == generation_before_skip + 1 and _events_of(logger, "contract_finished").size() == 2,
		"game root: a repeated skip re-settled the defeat", failures)
	_teardown_game(session)


## Victories, abandons and the smoke driver never wait on a defeat window.
func _test_unchanged_outcomes(failures: Array[String]) -> void:
	var session := _open_arena(failures, 7104)
	var game = session.get("game")
	var screen = session.get("screen")
	if game == null or screen == null:
		_teardown_game(session)
		return
	## The smoke driver owns its own route expectations outright.
	game.set("_auto_smoke_session", true)
	_expect(not bool(game.call("_defeat_window_holds_screen", {"outcome": "defeat"})),
		"game root: a smoke session would have held a defeat screen", failures)
	game.set("_auto_smoke_session", false)
	## A victory on a screen that never reports readiness still routes at once.
	screen.call("resolve", {"outcome": "victory", "room_results": [{"room_id": "room.source", "outcome": "victory"}]})
	_expect(game.current_route == "result", "game root: a victory waited for a defeat window", failures)
	_expect(not bool(game.call("defeat_route_report").get("pending", false)),
		"game root: a victory left a pending result screen behind", failures)
	## An abandon on the same screen also routes at once.
	_expect(bool(game.leave_result().get("ok", false)), "game root: the victory route did not close", failures)
	_expect(bool(game.open_contract().get("ok", false)), "game root: the contract board did not reopen for the abandon", failures)
	_expect(bool(game.launch_contract({"contract_id": "mainline_01_first_hunt", "mode": "Manual", "seed": 7105, "room_count": 1}).get("ok", false)),
		"game root: the abandon contract did not launch", failures)
	var abandon_screen = game.current_screen
	if abandon_screen == null or not abandon_screen.has_method("cancel"):
		_expect(false, "game root: the abandon contract did not mount the arena screen", failures)
		_teardown_game(session)
		return
	abandon_screen.call("cancel", {"outcome": "abandoned", "room_results": [{"room_id": "room.source", "outcome": "abandoned"}]})
	_expect(game.current_route == "result", "game root: an abandon waited for a defeat window", failures)
	_teardown_game(session)


## The whole production chain, driven frame by frame: GameRoot -> real
## ContractRunController -> real CombatRoomRuntime -> real arena. The defeat
## settles and is saved while the arena screen is still mounted and still drawing
## the fall, the clip finishes on that same screen, and only then does the result
## screen replace it. The second contract ends the same window with the player's
## own return button.
func _test_production_chain(failures: Array[String]) -> void:
	var delta := 1.0 / 60.0
	var session := _open_production_arena(failures, 7201)
	var game = session.get("game")
	var arena: Node = session.get("arena")
	if game == null or arena == null:
		_teardown_production(session)
		return
	var logger = session.get("logger")
	var generation_before := _save_generation(game)
	_fixture_contact_kill(arena, failures)
	var death_tick := _drive_production_to_death(session, delta)
	if death_tick < 0:
		_expect(false, "production chain: the melee pursuer never landed a fatal impact", failures)
		_teardown_production(session)
		return

	# --- the settlement lands inside the defeat frame, on the arena screen.
	_advance_production_frame(session, delta)
	_expect(game.current_route == "arena", "production chain: the result screen replaced the arena before the clip", failures)
	_expect(_save_generation(game) == generation_before + 1,
		"production chain: the defeat was not saved at its settlement time point (generation %d)" % _save_generation(game), failures)
	_expect(_events_of(logger, "contract_finished").size() == 1, "production chain: the defeat was not recorded exactly once", failures)
	_expect(bool(game.call("defeat_route_report").get("pending", false)),
		"production chain: the result screen was not waiting for the clip", failures)
	var controller = game.current_screen
	_expect(controller != null and controller.has_method("defeat_presentation_ready"),
		"production chain: the production controller was replaced or lost its relay", failures)
	_expect(is_instance_valid(arena) and not arena.is_queued_for_deletion() and String((arena.presentation.animations.ranger_frame as Dictionary).get("action", "")) == DefeatPresentationScript.ACTION_DEATH,
		"production chain: the mounted arena was not drawing the fall while the result waited", failures)
	if controller is Node:
		_expect((controller as Node).process_mode != Node.PROCESS_MODE_DISABLED,
			"production chain: the arena screen was disabled while the result waited", failures)

	# --- the same mounted screen finishes the clip, and only then the route moves.
	var held_frames := 0
	var left_death_clip := false
	for _frame_index in MAX_WINDOW_FRAMES:
		_advance_production_frame(session, delta)
		held_frames += 1
		if String((arena.presentation.animations.ranger_frame as Dictionary).get("action", "")) != DefeatPresentationScript.ACTION_DEATH:
			left_death_clip = true
		if game.current_route != "arena":
			break
	_expect(game.current_route == "result", "production chain: the finished clip did not release the result screen", failures)
	_expect(not left_death_clip, "production chain: the arena left the death clip while the result waited", failures)
	var released: Dictionary = game.call("defeat_route_report")
	_expect(String(released.get("released_by", "")) == "ready",
		"production chain: the result screen was not released by the clip itself: %s" % str(released), failures)
	var window: Dictionary = (arena.call("defeat_presentation_report") as Dictionary).get("window", {})
	_expect(String(window.get("state", "")) == DefeatPresentationScript.STATE_COMPLETE
		and str(window.get("missing_frames", [])) == "[]"
		and float(window.get("last_frame_seconds", 0.0)) + DefeatPresentationScript.DURATION_EPSILON >= ONE_FRAME_SECONDS,
		"production chain: the result screen replaced the arena before the whole clip was seen", failures)
	_expect(_save_generation(game) == generation_before + 1 and _events_of(logger, "contract_finished").size() == 1,
		"production chain: the screen swap settled the defeat again", failures)

	# --- the player's own return button ends the next window.
	_expect(bool(game.leave_result().get("ok", false)), "production chain: the result route did not close", failures)
	_expect(bool(game.open_contract().get("ok", false)), "production chain: the contract board did not reopen", failures)
	_expect(bool(game.launch_contract({"contract_id": "mainline_01_first_hunt", "mode": "Manual", "seed": 7203, "room_count": 1}).get("ok", false)),
		"production chain: the retry contract did not launch", failures)
	_attach_production_arena(session, failures)
	var retry_arena: Node = session.get("arena")
	if retry_arena == null:
		_teardown_production(session)
		return
	var retry_generation := _save_generation(game)
	_fixture_contact_kill(retry_arena, failures)
	if _drive_production_to_death(session, delta) < 0:
		_expect(false, "production chain: the retry contract never reached a real death", failures)
		_teardown_production(session)
		return
	_advance_production_frame(session, delta)
	_expect(bool(game.call("defeat_route_report").get("pending", false)),
		"production chain: the retry result was not waiting for its clip", failures)
	var retry_button: Variant = retry_arena.presentation.hud.find_child("ReturnButton", true, false)
	if retry_button is Button:
		(retry_button as Button).emit_signal("pressed")
	_expect(String(((retry_arena.call("defeat_presentation_report") as Dictionary).get("window", {}) as Dictionary).get("skip_reason", "")) == "return_to_base",
		"production chain: the return button did not end the retry window", failures)
	_advance_production_frame(session, delta)
	_expect(game.current_route == "result", "production chain: the return button did not release the result screen", failures)
	_expect(_save_generation(game) == retry_generation + 1 and _events_of(logger, "contract_finished").size() == 2,
		"production chain: the return button settled the retry defeat twice", failures)
	_teardown_production(session)


## One real embedded session with a single melee pursuer in contact range and a
## health value equal to the impact it is about to land. Every write here is a
## scene fixture: no dead state, no battle_over, no victory flag.
func _start_death_session(failures: Array[String], presentation_enabled: bool) -> Dictionary:
	var session := {
		"runtime": null,
		"arena": null,
		"completed": [] as Array[Dictionary],
		"abandoned": [] as Array[Dictionary],
		"frames": {"driven": 0},
	}
	var resolved_build := _resolved_fixture()
	if resolved_build.is_empty():
		_expect(false, "fixture: the calibration_convergent Build did not resolve", failures)
		return session
	var runtime = CombatRoomRuntimeScript.new()
	root.add_child(runtime)
	var started: Dictionary = runtime.start_session({
		"contract_id": "embedded.defeat-window",
		"mode": "Manual",
		"preset_id": "convergent",
		"seed": 4242,
		"presentation_enabled": presentation_enabled,
		"room_count": 1,
		"room": {
			"room_id": "room.defeat-window",
			"layout_id": "rectangle_arena",
			"objective_id": "clear",
			"hazard_ids": [],
			"enemy_ids": ["melee_pursuer"],
			"elite_rule_ids": [],
			"boss_id": "",
			"drop_tags": [],
		},
		"framework_context": {"resolved_build": resolved_build},
	})
	_expect(bool(started.get("ok", false)), "fixture: the embedded session did not start: %s" % str(started), failures)
	var arena_value: Variant = runtime.get("room_instance")
	if not (arena_value is Node):
		_expect(false, "fixture: the runtime mounted no arena", failures)
		_teardown(session)
		return session
	var arena := arena_value as Node
	session["runtime"] = runtime
	session["arena"] = arena
	runtime.completed.connect(_capture_route.bind(session))
	runtime.abandoned.connect(_capture_abandon.bind(session))
	## The loop below owns the clock, so the engine never double-processes this
	## arena while the test drives it frame by frame.
	arena.set_process(false)
	var roster: Array = arena.get("enemies")
	if roster.size() != 1:
		_expect(false, "fixture: the room spawned %d enemies instead of one melee pursuer" % roster.size(), failures)
		_teardown(session)
		return session
	_expect(not bool(arena.get("battle_over")) and float(arena.get("player_health")) > 0.0
		and String(arena.player_combat_state.snapshot(arena.sim_tick).last_damage_source_id).is_empty(),
		"fixture: the session was already over before the real impact", failures)
	var enemy: Variant = roster[0]
	arena.teleport_actor("enemy/%d" % enemy.entity_id, (arena.get("player_position") as Vector2) + Vector2(12.0, 0.0))
	_prepare_contact_health(arena, failures)
	return session


## Router frame order: the runtime is the arena's parent, so it processes first
## and only ever sees frames the arena already presented. The arena keeps
## processing after this call because nothing has taken its screen away yet.
func _advance_frame(session: Dictionary, delta: float) -> void:
	var counters: Dictionary = session["frames"]
	counters["driven"] = int(counters.get("driven", 0)) + 1
	(session["runtime"] as Node).call("_process", delta)
	(session["arena"] as Node).call("_process", delta)


func _capture_route(result: Dictionary, session: Dictionary) -> void:
	var completed: Array = session["completed"]
	completed.append(result.duplicate(true))


func _capture_abandon(result: Dictionary, session: Dictionary) -> void:
	var abandoned: Array = session["abandoned"]
	abandoned.append(result.duplicate(true))


func _teardown(session: Dictionary) -> void:
	var runtime: Node = session.get("runtime")
	if runtime != null and is_instance_valid(runtime):
		if runtime.get_parent() == root:
			root.remove_child(runtime)
		runtime.free()
	session["runtime"] = null
	session["arena"] = null


## One injected profile, contract board and arena screen, with a playtest log the
## test can count and a save directory the test can clean.
func _open_arena(failures: Array[String], seed_value: int) -> Dictionary:
	_cleanup_save_directory()
	var logger := FakePlaytestLog.new()
	var game = GameRootScript.new()
	game.save_directory_path = TEST_SAVE_DIRECTORY
	game.room_runtime_factory = Callable(self, "_make_death_screen")
	game.playtest_logging_enabled = false
	game.initialize(PackedStringArray())
	game.playtest_log = logger
	game.playtest_logging_enabled = true
	logger.start_session({})
	var session := {"game": game, "logger": logger, "screen": null}
	var profile_ready: bool = bool(game.start_new_game("ranger").get("ok", false)) and bool(game.complete_tutorial().get("ok", false))
	_expect(profile_ready, "game root: the profile did not reach the base", failures)
	_expect(bool(game.open_contract().get("ok", false)), "game root: the contract board did not open", failures)
	var launched: Dictionary = game.launch_contract({
		"contract_id": "mainline_01_first_hunt",
		"mode": "Manual",
		"seed": seed_value,
		"room_count": 1,
	})
	_expect(bool(launched.get("ok", false)), "game root: the contract did not launch: %s" % str(launched), failures)
	_expect(game.current_screen is DeathScreen, "game root: the injected arena screen was not mounted", failures)
	session["screen"] = game.current_screen
	return session


func _make_death_screen() -> Node:
	return DeathScreen.new()


func _teardown_game(session: Dictionary) -> void:
	var game = session.get("game")
	if game != null and is_instance_valid(game):
		game.free()
	_cleanup_save_directory()


## The production chain, mounted for real: the injected screen here is the real
## ContractRunController, which mounts the real runtime and the real arena. The
## arena only becomes ready inside a tree, so this game is added to the root and
## every node's frame is driven by the test.
func _open_production_arena(failures: Array[String], seed_value: int) -> Dictionary:
	_cleanup_save_directory()
	var logger := FakePlaytestLog.new()
	var game = GameRootScript.new()
	game.save_directory_path = TEST_SAVE_DIRECTORY
	game.playtest_logging_enabled = false
	game.initialize(PackedStringArray())
	game.playtest_log = logger
	game.playtest_logging_enabled = true
	logger.start_session({})
	root.add_child(game)
	game.set_process(false)
	var session := {"game": game, "logger": logger, "screen": null, "runtime": null, "arena": null}
	var profile_ready: bool = bool(game.start_new_game("ranger").get("ok", false)) and bool(game.complete_tutorial().get("ok", false))
	_expect(profile_ready, "production chain: the profile did not reach the base", failures)
	_expect(bool(game.open_contract().get("ok", false)), "production chain: the contract board did not open", failures)
	_expect(bool(game.launch_contract({"contract_id": "mainline_01_first_hunt", "mode": "Manual", "seed": seed_value, "room_count": 1}).get("ok", false)),
		"production chain: the contract did not launch", failures)
	_attach_production_arena(session, failures)
	return session


func _attach_production_arena(session: Dictionary, failures: Array[String]) -> void:
	var game = session.get("game")
	var controller = game.current_screen
	session["screen"] = controller
	if controller == null or not controller.has_method("defeat_presentation_ready"):
		_expect(false, "production chain: the production controller was not mounted", failures)
		session["runtime"] = null
		session["arena"] = null
		return
	var runtime = controller.get("_current_runtime")
	if runtime == null or not runtime.has_method("defeat_presentation_ready"):
		_expect(false, "production chain: the production runtime was not mounted", failures)
		session["runtime"] = null
		session["arena"] = null
		return
	var arena_value: Variant = runtime.get("room_instance")
	if not (arena_value is Node):
		_expect(false, "production chain: the real arena was not mounted", failures)
		session["runtime"] = null
		session["arena"] = null
		return
	var arena := arena_value as Node
	session["runtime"] = runtime
	session["arena"] = arena
	## The test owns the clock for every node in the chain.
	(runtime as Node).set_process(false)
	arena.set_process(false)
	var roster: Variant = arena.get("enemies")
	_expect(roster is Array and (roster as Array).size() == 3,
		"production chain: first hunt must mount its three authored melee pursuers", failures)
	if roster is Array:
		for enemy in roster:
			_expect(String(enemy.kind_id) == "melee_pursuer", "production chain: first hunt mounted an unexpected enemy kind", failures)


func _fixture_contact_kill(arena: Node, failures: Array[String]) -> void:
	var roster: Array = arena.get("enemies")
	if roster.is_empty():
		return
	var enemy: Variant = roster[0]
	arena.teleport_actor("enemy/%d" % enemy.entity_id, (arena.get("player_position") as Vector2) + Vector2(12.0, 0.0))
	_prepare_contact_health(arena, failures)


func _prepare_contact_health(arena: Node, failures: Array[String]) -> void:
	var player: Dictionary = arena.player_combat_state.snapshot(arena.sim_tick)
	var receipt: Dictionary = arena.player_combat_rules.apply_damage(arena.sim_tick, float(player.player_health) - MELEE_CONTACT_DAMAGE, "fixture/contact-preparation", player.player_position)
	var prepared: Dictionary = arena.player_combat_state.snapshot(arena.sim_tick)
	_expect(bool(receipt.get("accepted", false)) and is_equal_approx(float(prepared.player_health), MELEE_CONTACT_DAMAGE) and not arena.battle_over, "fixture: Rules did not prepare a living player for one fatal contact", failures)


## GameRoot processes before its children, then the router, then the arena.
func _advance_production_frame(session: Dictionary, delta: float) -> void:
	(session["game"] as Node).call("_process", delta)
	(session["runtime"] as Node).call("_process", delta)
	(session["arena"] as Node).call("_process", delta)


func _drive_production_to_death(session: Dictionary, delta: float) -> int:
	var arena: Node = session.get("arena")
	for _frame_index in MAX_ALIVE_FRAMES:
		_advance_production_frame(session, delta)
		if float(arena.get("player_health")) <= 0.0:
			return int(arena.get("sim_tick"))
	return -1


func _teardown_production(session: Dictionary) -> void:
	var game = session.get("game")
	if game != null and is_instance_valid(game):
		if game.get_parent() == root:
			root.remove_child(game)
		game.free()
	_cleanup_save_directory()


func _defeat_result(seed_value: int = 0) -> Dictionary:
	return {
		"outcome": "defeat",
		"seed": seed_value,
		"ticks": 42,
		"elapsed_seconds": 1.4,
		"casts": 0,
		"defeated": 0,
		"failure_reason": MELEE_CONTACT_SOURCE,
		"room_results": [{"room_id": "room.source", "outcome": "defeat", "failure_reason": MELEE_CONTACT_SOURCE}],
	}


func _save_generation(game: Node) -> int:
	var loaded: Dictionary = game.save_store.load_latest()
	return int(loaded.get("generation", 0)) if bool(loaded.get("ok", false)) else 0


func _events_of(logger: Object, event_id: String) -> Array:
	var result: Array = []
	if logger == null:
		return result
	for event: Dictionary in (logger.get("events") as Array):
		if String(event.get("event_id", "")) == event_id:
			result.append(event)
	return result


func _cleanup_save_directory() -> void:
	var absolute_directory: String = ProjectSettings.globalize_path(TEST_SAVE_DIRECTORY)
	for file_name in ["save_a.json", "save_b.json", "save_a.json.tmp", "save_b.json.tmp"]:
		var path: String = absolute_directory.path_join(file_name)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	if DirAccess.dir_exists_absolute(absolute_directory):
		DirAccess.remove_absolute(absolute_directory)


func _death_frame(index: int) -> Dictionary:
	return {
		"action": DefeatPresentationScript.ACTION_DEATH,
		"frame": index,
		"frame_count": 3,
		"fps": 6,
		"fallback": false,
	}


func _resolved_fixture() -> Dictionary:
	var registry = EarlyItemRegistryScript.new()
	if not registry.load_all().is_empty():
		return {}
	return BuildResolverScript.new(registry).resolve_fixture("calibration_convergent")


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)


func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print("PASS  test_defeat_presentation.gd")
		quit(0)
		return
	for failure in failures:
		printerr("- %s" % failure)
	quit(1)
