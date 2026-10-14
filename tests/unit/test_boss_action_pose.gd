extends SceneTree
## Standalone contract check for the colossus action pose layer
## (src/presentation/boss_action_pose.gd): three distinguishable attacks across
## two phases, additive-only, quantized and rate-independent.
##
## Run it on its own:
##   godot --headless --path . --script res://tests/unit/test_boss_action_pose.gd
##
## The suite drives the pure helper with the authoritative boss timing only - a
## 24-tick windup, one active tick, a 24-tick recovery and a 30-tick phase
## transition. The pure helper checks do not simulate gameplay.
## The recovery-bridge check additionally replays the real state machine in a
## mounted Main session with real Simulation ticks and the real world view.

const BossActionPoseScript = preload("res://src/presentation/boss_action_pose.gd")
const CombatEnemyStateScript := preload("res://src/runtime/world/combat_enemy_state.gd")

const BOSS_WINDUP_TICKS: int = 24
const BOSS_ACTIVE_TICKS: int = 1
const BOSS_RECOVERY_TICKS: int = 24
const BOSS_TRANSITION_TICKS: int = 30
const ACTIONS: Array[String] = ["slam", "sweep", "lane"]
const RENDER_RATES: Array[int] = [30, 60, 144]
const PHASES: Array[int] = [1, 2]
const FACINGS: Array[Vector2] = [
	Vector2.DOWN,
	Vector2.UP,
	Vector2.LEFT,
	Vector2.RIGHT,
	Vector2(-0.71, 0.71),
	Vector2(0.36, -0.93),
]
const HAND_CEILING: int = BossActionPoseScript.MAX_HAND_OFFSET_PX
const BODY_CEILING: int = BossActionPoseScript.MAX_BODY_OFFSET_PX
const CORE_TINT_CEILING: float = 1.30
## The authority timeline the rate test replays: slam, one idle tick, sweep, one
## idle tick, lane.
const AUTHORITY_ACTIONS: Array[String] = ["slam", "sweep", "lane"]
const ACTION_STARTS: Array[int] = [0, 50, 100]

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_frame_contract()
	_test_idle_zero()
	_test_stage_bounds()
	_test_distinct_attacks()
	_test_windup_hold_and_single_tick_active()
	_test_recovery_retracts_to_zero()
	_test_phase2_consistency()
	_test_render_rate_equivalence()
	_test_recovery_bridge()
	if failures.is_empty():
		print("PASS  test_boss_action_pose.gd: colossus action pose and recovery bridge contract")
		quit(0)
		return
	printerr("%d pose check(s) failed:" % failures.size())
	for failure: String in failures:
		printerr("- %s" % failure)
	quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


## The sim's window for one stage of an action that starts at action_start:
## windup [start, start+24), the single active tick, recovery [start+25, start+49).
func _window(action_start: int, stage: String) -> Vector2i:
	var impact := action_start + BOSS_WINDUP_TICKS
	match stage:
		"windup":
			return Vector2i(action_start, impact)
		"active":
			return Vector2i(impact, impact + BOSS_ACTIVE_TICKS)
		_:
			return Vector2i(impact + BOSS_ACTIVE_TICKS, impact + BOSS_ACTIVE_TICKS + BOSS_RECOVERY_TICKS)


## One frame exactly as main will ask for it.
func _pose(action: String, stage: String, tick: int, action_start: int, phase: int = 1, facing: Vector2 = Vector2.DOWN, phase_state: String = "stable") -> Dictionary:
	var window := _window(action_start, stage)
	return BossActionPoseScript.pose(action, stage, tick, window.x, window.y, phase, facing, phase_state)


func _signature(frame: Dictionary) -> String:
	return "%s|%s|%s|%s|%s" % [frame["tag"], frame["body_offset_px"], frame["left_hand_offset_px"], frame["right_hand_offset_px"], frame["core_offset_px"]]


func _hand_reach(frame: Dictionary) -> float:
	var left: Vector2i = frame["left_hand_offset_px"]
	var right: Vector2i = frame["right_hand_offset_px"]
	return float(maxi(maxi(absi(left.x), absi(left.y)), maxi(absi(right.x), absi(right.y))))


func _dot(offset: Vector2i, axis: Vector2) -> float:
	return Vector2(offset).dot(axis)


func _same_axis(a: Vector2i, b: Vector2i) -> bool:
	return (b.x == 0 or a.x == 0 or signi(a.x) == signi(b.x)) and (b.y == 0 or a.y == 0 or signi(a.y) == signi(b.y))


func _check_bounds(label: String, frame: Dictionary) -> void:
	var body: Vector2i = frame["body_offset_px"]
	var left: Vector2i = frame["left_hand_offset_px"]
	var right: Vector2i = frame["right_hand_offset_px"]
	var core: Vector2i = frame["core_offset_px"]
	_expect(core == body, "%s: the core must ride the body offset" % label)
	_expect(maxi(absi(body.x), absi(body.y)) <= BODY_CEILING, "%s: body offset %s exceeds %d px" % [label, body, BODY_CEILING])
	_expect(maxi(absi(left.x), absi(left.y)) <= HAND_CEILING, "%s: left fist offset %s exceeds %d px" % [label, left, HAND_CEILING])
	_expect(maxi(absi(right.x), absi(right.y)) <= HAND_CEILING, "%s: right fist offset %s exceeds %d px" % [label, right, HAND_CEILING])


## Phase 2 is the same motion, heavier: same direction, never less travel.
func _expect_amplified(light: Vector2i, heavy: Vector2i, label: String) -> void:
	_expect(absi(heavy.x) >= absi(light.x) and absi(heavy.y) >= absi(light.y), "%s: phase 2 travels less than phase 1 (%s -> %s)" % [label, light, heavy])
	_expect(light.x == 0 or signi(heavy.x) == signi(light.x), "%s: phase 2 flipped the x direction (%s -> %s)" % [label, light, heavy])
	_expect(light.y == 0 or signi(heavy.y) == signi(light.y), "%s: phase 2 flipped the y direction (%s -> %s)" % [label, light, heavy])
	_expect(not (light != Vector2i.ZERO and heavy == Vector2i.ZERO), "%s: phase 2 erased a phase 1 motion" % label)


## The authority timeline of one slam -> idle -> sweep -> idle -> lane pass at 30 Hz.
func _authority_frame(tick: int) -> Dictionary:
	for index in AUTHORITY_ACTIONS.size():
		var start: int = ACTION_STARTS[index]
		var span := BOSS_WINDUP_TICKS + BOSS_ACTIVE_TICKS + BOSS_RECOVERY_TICKS
		if tick >= start and tick < start + span:
			return {"action": AUTHORITY_ACTIONS[index], "stage": _authority_stage(tick - start), "start": start}
	return {"action": "none", "stage": "none", "start": tick}


func _authority_stage(age: int) -> String:
	if age < BOSS_WINDUP_TICKS:
		return "windup"
	if age < BOSS_WINDUP_TICKS + BOSS_ACTIVE_TICKS:
		return "active"
	return "recovery"


func _authority_pose(tick: int, phase: int = 2, facing: Vector2 = Vector2.DOWN) -> Dictionary:
	var authority := _authority_frame(tick)
	var stage := String(authority["stage"])
	if stage == "none":
		return BossActionPoseScript.pose(String(authority["action"]), "none", tick, tick, tick, phase, facing)
	var window := _window(int(authority["start"]), stage)
	return BossActionPoseScript.pose(String(authority["action"]), stage, tick, window.x, window.y, phase, facing)


func _test_frame_contract() -> void:
	var frame := _pose("slam", "windup", 0, 0, 2)
	var keys := frame.keys()
	keys.sort()
	var expected := BossActionPoseScript.FRAME_FIELDS.duplicate()
	expected.sort()
	_expect(keys == expected, "frame keys moved away from the contract: %s" % [keys])
	_expect(frame["tag"] is String, "the frame tag must be a string")
	_expect(frame["core_tint"] is Color, "the frame core tint must be a color")
	for field in ["body_offset_px", "left_hand_offset_px", "right_hand_offset_px", "core_offset_px"]:
		_expect(frame[field] is Vector2i, "frame %s must be a quantized Vector2i" % field)
	# Purity: every call returns a fresh frame, and repeated calls cannot drift.
	var first := _pose("lane", "active", 24, 0, 2)
	first["right_hand_offset_px"] = Vector2i(999, 999)
	var second := _pose("lane", "active", 24, 0, 2)
	_expect(second["right_hand_offset_px"] != Vector2i(999, 999), "pose() handed out shared state")
	_expect(_signature(second) == _signature(_pose("lane", "active", 24, 0, 2)), "pose() drifted between identical calls")


func _test_idle_zero() -> void:
	for action in ["none", "contact", "charge", "fan", "", "slam"]:
		for stage in ["none", "idle", ""]:
			var frame := BossActionPoseScript.pose(action, stage, 500, 500, 500, 2, Vector2.DOWN)
			_expect(frame["tag"] == "idle", "idle %s/%s is not tagged idle" % [action, stage])
			for field in ["body_offset_px", "left_hand_offset_px", "right_hand_offset_px", "core_offset_px"]:
				_expect(frame[field] == Vector2i.ZERO, "idle %s/%s leaks %s=%s" % [action, stage, field, frame[field]])
	# The phase transition zeroes the hands in the sim; the pose stays neutral too.
	var transition := BossActionPoseScript.pose("slam", "windup", 1000, 1000, 1000 + BOSS_TRANSITION_TICKS, 2, Vector2.DOWN, "transition")
	_expect(transition["tag"] == "idle", "the phase transition must not pose the body")
	_expect(transition["left_hand_offset_px"] == Vector2i.ZERO and transition["right_hand_offset_px"] == Vector2i.ZERO, "the phase transition must not move the fists")
	# Phase 1 keeps the approved art untouched.
	var idle_phase1 := BossActionPoseScript.pose("none", "none", 0, 0, 0, 1)
	_expect(idle_phase1["core_tint"] == Color.WHITE, "the phase 1 core tint must stay the approved white")


func _test_stage_bounds() -> void:
	var action_start := 400
	for action in ACTIONS:
		for stage in ["windup", "active", "recovery"]:
			var window := _window(action_start, stage)
			for phase in PHASES:
				for facing in FACINGS:
					for tick in range(window.x - 3, window.y + 4):
						var frame := _pose(action, stage, tick, action_start, phase, facing)
						_check_bounds("%s/%s p%d tick %d facing %s" % [action, stage, phase, tick, facing], frame)
						_expect(String(frame["tag"]) != "idle", "%s/%s lost its stage tag" % [action, stage])
					# A tick far outside the window must clamp, not extrapolate.
					for tick in [window.x - 10000, window.y + 10000]:
						_check_bounds("%s/%s p%d wild tick %d" % [action, stage, phase, tick], _pose(action, stage, tick, action_start, phase, facing))


func _test_distinct_attacks() -> void:
	# The concept's own framing (the hero is south of the colossus) gives exact
	# integer axes after quantization.
	var start := 120
	var windup_end := start + BOSS_WINDUP_TICKS - 1
	var active_tick := start + BOSS_WINDUP_TICKS
	var signatures := {}
	for action in ACTIONS:
		var cocked := _pose(action, "windup", windup_end, start, 2)
		var struck := _pose(action, "active", active_tick, start, 2)
		signatures[action] = _signature(struck)
		_expect(_signature(cocked) != _signature(BossActionPoseScript.pose("none", "none", 0, 0, 0, 2)), "%s: its windup is indistinguishable from idle" % action)
		_expect(_signature(cocked) != _signature(struck), "%s: the active tick left the windup pose unchanged" % action)
	_expect(signatures["slam"] != signatures["sweep"] and signatures["sweep"] != signatures["lane"] and signatures["slam"] != signatures["lane"], "the three attacks must read differently on their active tick")
	var slam_lift := _pose("slam", "windup", windup_end, start, 2)
	var slam_hit := _pose("slam", "active", active_tick, start, 2)
	var lift_left: Vector2i = slam_lift["left_hand_offset_px"]
	var lift_right: Vector2i = slam_lift["right_hand_offset_px"]
	var hit_left: Vector2i = slam_hit["left_hand_offset_px"]
	var hit_right: Vector2i = slam_hit["right_hand_offset_px"]
	_expect(lift_left.y < 0 and lift_right.y < 0, "slam must lift both fists")
	_expect(lift_left.y == lift_right.y, "slam must lift both fists by the same native travel")
	_expect(lift_left.x == -lift_right.x, "the slam flare must mirror")
	_expect(hit_left == hit_right and hit_left.y > 0, "slam must drop both fists together")
	for facing in FACINGS:
		var forward := facing.normalized()
		var side := forward.rotated(-PI * 0.5)
		var sweep_windup: Vector2i = _pose("sweep", "windup", windup_end, start, 2, facing)["right_hand_offset_px"]
		var sweep_hit: Vector2i = _pose("sweep", "active", active_tick, start, 2, facing)["right_hand_offset_px"]
		var lane_windup: Vector2i = _pose("lane", "windup", windup_end, start, 2, facing)["right_hand_offset_px"]
		var lane_hit: Vector2i = _pose("lane", "active", active_tick, start, 2, facing)["right_hand_offset_px"]
		_expect(_dot(sweep_windup, side) > 0.0, "sweep must pull along the sim's perpendicular axis (facing %s)" % facing)
		_expect(_dot(sweep_hit, side) < 0.0, "sweep must cross to the other side of that axis (facing %s)" % facing)
		_expect(absf(_dot(sweep_hit, side)) > absf(_dot(sweep_hit, forward)), "sweep travel must stay perpendicular to the punch axis (facing %s)" % facing)
		_expect(_dot(lane_windup, forward) < 0.0, "lane must cock the fist back off the facing (facing %s)" % facing)
		_expect(_dot(lane_hit, forward) > 0.0, "lane must punch along the facing (facing %s)" % facing)
		_expect(absf(_dot(lane_hit, forward)) > absf(_dot(lane_hit, side)), "lane travel must stay on the punch axis (facing %s)" % facing)
		_expect(_pose("sweep", "active", active_tick, start, 2, facing)["left_hand_offset_px"] == Vector2i.ZERO, "sweep must not throw the left fist (facing %s)" % facing)
		_expect(_pose("lane", "active", active_tick, start, 2, facing)["left_hand_offset_px"] == Vector2i.ZERO, "lane must not throw the left fist (facing %s)" % facing)


func _test_windup_hold_and_single_tick_active() -> void:
	var start := 240
	var impact := start + BOSS_WINDUP_TICKS
	var fill_tick := start + int(ceil(float(BOSS_WINDUP_TICKS) / BossActionPoseScript.WINDUP_FILL))
	for action in ACTIONS:
		for phase in PHASES:
			var previous := -1.0
			for tick in range(start, impact):
				var reach := _hand_reach(_pose(action, "windup", tick, start, phase))
				_expect(reach >= previous, "%s p%d: the windup must never reverse (tick %d)" % [action, phase, tick])
				previous = reach
			# The lift is already in place while the danger shape still counts down.
			_expect(_signature(_pose(action, "windup", fill_tick, start, phase)) == _signature(_pose(action, "windup", impact - 1, start, phase)), "%s p%d: the windup must hold its reach to the impact tick" % [action, phase])
			_expect(_signature(_pose(action, "windup", impact + 30, start, phase)) == _signature(_pose(action, "windup", impact - 1, start, phase)), "%s p%d: a late windup read must clamp" % [action, phase])
			# The strike lives on the impact tick only.
			_expect(_signature(_pose(action, "active", impact, start, phase)) != _signature(_pose(action, "windup", impact - 1, start, phase)), "%s p%d: the strike tick must change the pose" % [action, phase])
			# Damage resolves on exactly one tick, so a longer active span may
			# never add travel: the pose is one constant peak.
			var peak := _signature(_pose(action, "active", impact, start, phase))
			for extra_active in range(1, 7):
				for tick in range(impact, impact + extra_active):
					var frame := BossActionPoseScript.pose(action, "active", tick, impact, impact + extra_active, phase)
					_expect(_signature(frame) == peak, "%s p%d: a %d-tick active span must not add travel (tick %d)" % [action, phase, extra_active, tick])


func _test_recovery_retracts_to_zero() -> void:
	var start := 300
	var impact := start + BOSS_WINDUP_TICKS
	var recovery_start := impact + BOSS_ACTIVE_TICKS
	var recovery_end := recovery_start + BOSS_RECOVERY_TICKS
	for action in ACTIONS:
		for phase in PHASES:
			var peak := _pose(action, "active", impact, start, phase)
			var peak_reach := _hand_reach(peak)
			var previous := peak_reach
			for tick in range(recovery_start, recovery_end + 1):
				var reach := _hand_reach(_pose(action, "recovery", tick, start, phase))
				_expect(reach <= previous, "%s p%d: the recovery must only ever retract (tick %d)" % [action, phase, tick])
				previous = reach
			_expect(_hand_reach(_pose(action, "recovery", recovery_start, start, phase)) <= peak_reach, "%s p%d: the first recovery tick must not exceed the active peak" % [action, phase])
			var ended := _pose(action, "recovery", recovery_end, start, phase)
			for field in ["body_offset_px", "left_hand_offset_px", "right_hand_offset_px", "core_offset_px"]:
				_expect(ended[field] == Vector2i.ZERO, "%s p%d: the recovery must land exactly on the baseline, %s=%s" % [action, phase, field, ended[field]])
			# The retract never leaves the strike axis, so it cannot read as a
			# second strike in a new direction.
			_expect(_same_axis(_pose(action, "recovery", recovery_start + 1, start, phase)["right_hand_offset_px"], peak["right_hand_offset_px"]), "%s p%d: the recovery must return on the strike axis" % [action, phase])


func _test_phase2_consistency() -> void:
	var start := 360
	for action in ACTIONS:
		for stage in ["windup", "active", "recovery"]:
			var window := _window(start, stage)
			for facing in FACINGS:
				for tick in range(window.x - 1, window.y + 2):
					var phase1 := _pose(action, stage, tick, start, 1, facing)
					var phase2 := _pose(action, stage, tick, start, 2, facing)
					var label := "%s/%s tick %d facing %s" % [action, stage, tick, facing]
					_expect(phase1["tag"] == phase2["tag"], "%s: phase 2 must stay the same stage" % label)
					for field in ["body_offset_px", "left_hand_offset_px", "right_hand_offset_px"]:
						_expect_amplified(phase1[field] as Vector2i, phase2[field] as Vector2i, "%s: %s" % [label, field])
					var tint1: Color = phase1["core_tint"]
					var tint2: Color = phase2["core_tint"]
					_expect(tint1 == Color.WHITE, "%s: the phase 1 tint must stay the approved art" % label)
					_expect(tint2.r >= tint1.r and tint2.g >= tint1.g and tint2.b >= tint1.b and tint2.a >= tint1.a, "%s: the awakened core may only lift, never dim" % label)
					_expect(tint2.r <= CORE_TINT_CEILING and tint2.g <= CORE_TINT_CEILING and tint2.b <= CORE_TINT_CEILING, "%s: the awakened core tint must stay subtle" % label)


func _test_render_rate_equivalence() -> void:
	var last_tick: int = ACTION_STARTS[ACTION_STARTS.size() - 1] + BOSS_WINDUP_TICKS + BOSS_ACTIVE_TICKS + BOSS_RECOVERY_TICKS + 2
	var per_rate := {}
	for rate in RENDER_RATES:
		var by_tick := {}
		var frames := int(ceil(float(last_tick + 1) * float(rate) / 30.0))
		for frame_index in range(frames):
			var sim_tick := int(frame_index * 30 / rate)
			if sim_tick > last_tick:
				break
			# A render rate may only choose which ticks are sampled, never what a
			# tick looks like.
			var signature := _signature(_authority_pose(sim_tick))
			_expect(_signature(_authority_pose(sim_tick)) == signature, "%dHz: the pose depends on the render rate at tick %d" % [rate, sim_tick])
			if by_tick.has(sim_tick):
				_expect(by_tick[sim_tick] == signature, "%dHz: tick %d rendered two different poses" % [rate, sim_tick])
			else:
				by_tick[sim_tick] = signature
		per_rate[rate] = by_tick
	var reference: Dictionary = per_rate[30]
	_expect(reference.size() == last_tick + 1, "30Hz did not sample every authority tick (%d of %d)" % [reference.size(), last_tick + 1])
	for rate in RENDER_RATES:
		if rate == 30:
			continue
		var sampled: Dictionary = per_rate[rate]
		for tick in reference.keys():
			_expect(String(sampled.get(tick, "<missing>")) == String(reference[tick]), "%dHz would render tick %d differently from 30Hz" % [rate, tick])


## --- recovery bridge: the real authority and the real draw path --------------
##
## Everything above drives the pure helper. This last check drives the sim: a bare
## main.gd harness replays the real state machine into the real
## main._update_boss_hands, and the real arena view's boss_draw_parts() decodes the
## frame, so the seam between the authoritative active tick and the first recovery
## tick is measured on the numbers the draw call consumes.

const DomainFixture = preload("res://tests/helpers/player_domain_fixture.gd")
const Encounter = preload("res://src/game/encounter_director.gd")
const PresentationSnapshot = preload("res://src/presentation/combat_presentation_snapshot.gd")
const ArenaWorldViewScript = preload("res://src/presentation/arena_world_view.gd")
const ArenaActorPresenterScript = preload("res://src/presentation/arena_actor_presenter.gd")

## One whole native pixel: the grid the sim's 0.001 gameplay store and the draw
## call's own rounding already move on.
const BRIDGE_ONE_PX: float = 1.0
## The whole retract, summed over the recovery window.
const BRIDGE_TOTAL_PX: float = 1.5
## The lateral wobble one retract may show: the pose layer snaps its own share of
## the strike before this frame snaps the sum, and each snap is worth up to 0.71px.
const BRIDGE_DRIFT_PX: float = 1.5
## The authority tick the bridge cases replay on.
const BRIDGE_TICK: int = 600

## The harness and the world view the bridge check draws through.
var bridge_view
var bridge_harness
var bridge_fixture
var bridge_session: Dictionary
var actor_presenter


func _test_recovery_bridge() -> void:
	if not _open_bridge_harness():
		return
	var walked := 0
	for action in ACTIONS:
		for phase in PHASES:
			for facing in FACINGS:
				if _bridge_case(action, phase, facing):
					walked += 1
	_expect(walked == ACTIONS.size() * PHASES.size() * FACINGS.size(), "the recovery bridge walked %d of %d cases" % [walked, ACTIONS.size() * PHASES.size() * FACINGS.size()])
	if bridge_harness != null:
		bridge_fixture.free_session(bridge_session)
		bridge_harness = null
		bridge_session = {}
		bridge_fixture = null
	actor_presenter = null
	bridge_view = null


func _open_bridge_harness() -> bool:
	bridge_view = ArenaWorldViewScript.new()
	if not bridge_view.load_assets():
		_expect(false, "the recovery bridge needs the published arena atlas")
		return false
	bridge_fixture = DomainFixture.new()
	bridge_session = bridge_fixture.mount({"room_id": "test.pose.bridge", "layout_id": "rectangle_arena", "objective_id": "hunt_elite", "enemy_ids": [], "hazard_ids": [], "elite_rule_ids": [], "boss_id": "threshold_colossus", "drop_tags": []})
	bridge_harness = bridge_session.arena
	actor_presenter = ArenaActorPresenterScript.new()
	bridge_fixture.drive(bridge_harness)
	bridge_fixture.advance_to(bridge_harness, BRIDGE_TICK)
	var director = bridge_harness.encounter_director
	var enemy = bridge_harness.boss
	# Isolate the recovery bridge's real enemy state machine. Every callback
	# runs inside Simulation after the world tick and player motor commit.
	bridge_fixture.drive(bridge_harness, {"enemy_step": func() -> void:
		director._advance_action_state(enemy, Encounter.BOSS_ACTIVE_TICKS, Encounter.BOSS_RECOVERY_TICKS)
		director._update_boss_hands(enemy)
	})
	return true


## One strike, from its impact tick through its recovery window, driven by the real
## state machine and drawn through the real pose plus the real world view.
## It reports whether the whole window ran: a case that aborts half way must fail
## the suite, not leave it looking green.
func _bridge_case(action: String, phase: int, facing: Vector2) -> bool:
	var label := "%s p%d %s" % [action, phase, facing]
	var enemy = bridge_harness.boss
	_expect(bool(bridge_harness.teleport_actor("enemy/%d" % enemy.entity_id, bridge_harness._arena_rect().get_center()).get("ok", false)), "bridge boss deployment failed")
	var awakened := phase >= 2
	## Each fist has its own base, exactly the pair main._update_boss_hands() and
	## the world view use: measuring one against the other reads a 68px phantom.
	var base_left: Vector2 = enemy.position + Vector2(-43.0 if awakened else -34.0, -8.0 if awakened else 0.0)
	var base_right: Vector2 = enemy.position + Vector2(38.0 if awakened else 34.0, 12.0 if awakened else 0.0)
	enemy.phase_id = "awakened" if awakened else "sealed"
	enemy.action_id = action
	enemy.facing = facing
	enemy.next_action_index = ACTIONS.find(action)
	bridge_harness.teleport_actor("ranger", enemy.position + facing * 200.0)
	# Begin the real Encounter action at the currently committed world tick;
	# subsequent cases keep advancing the same world instead of rewinding it.
	bridge_harness.encounter_director._begin_action(enemy, action, Encounter.BOSS_WINDUP_TICKS)
	enemy.facing = facing
	var impact: int = enemy.impact_tick
	var recovery_start: int = impact + Encounter.BOSS_ACTIVE_TICKS
	var recovery_end: int = recovery_start + Encounter.BOSS_RECOVERY_TICKS
	var drawn: Dictionary = {}
	var published: Dictionary = {}
	var strike: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO]
	for tick in range(impact, recovery_end):
		bridge_fixture.advance_to(bridge_harness, tick)
		var hash_before: String = bridge_harness._semantic_state_hash("recovery_bridge")
		var draw_enemy = PresentationSnapshot.enemy_record(enemy)
		var frame: Dictionary = actor_presenter.boss_visual_pose(draw_enemy, tick)
		_expect(hash_before.length() == 64, "%s: the state hash guard could not run" % label)
		_expect(bridge_harness._semantic_state_hash("recovery_bridge") == hash_before, "%s: drawing tick %d moved the replay hash" % [label, tick])
		drawn[tick] = _drawn_hands(draw_enemy, frame)
		published[tick] = _published_fields(draw_enemy, tick)
		if tick == impact:
			strike = [enemy.left_hand_position - base_left, enemy.right_hand_position - base_right]
	var scale: float = ArenaWorldViewScript.GAMEPLAY_TO_WORLD
	var active_hand: Array = drawn[impact]
	var start_hand: Array = drawn[recovery_start]
	## (a) The mirror still matches what the sim really published on the active
	## tick: a changed strike formula fails here instead of leaving a seam.
	var owed: Dictionary = BossActionPoseScript.authority_recovery_hand_offsets(action, "recovery", recovery_start, recovery_start, recovery_end, facing, scale)
	_expect((Vector2(owed["left"]) - strike[0] * scale).length() <= BRIDGE_ONE_PX, "%s: the bridge mirror drifted from the real left strike" % label)
	_expect((Vector2(owed["right"]) - strike[1] * scale).length() <= BRIDGE_ONE_PX, "%s: the bridge mirror drifted from the real right strike" % label)
	## (b) The seam: the first recovery tick draws what the active tick drew.
	_expect(active_hand[0].length() > BRIDGE_ONE_PX or active_hand[1].length() > BRIDGE_ONE_PX, "%s: the active tick drew no strike" % label)
	_expect((start_hand[0] - active_hand[0]).length() <= BRIDGE_ONE_PX, "%s: the left fist stepped %.2f px at recovery start" % [label, (start_hand[0] - active_hand[0]).length()])
	_expect((start_hand[1] - active_hand[1]).length() <= BRIDGE_ONE_PX, "%s: the right fist stepped %.2f px at recovery start" % [label, (start_hand[1] - active_hand[1]).length()])
	## (c) Both fists retract, and (d) every rate draws the same window.
	for arm in [0, 1]:
		_bridge_retract(label, arm, start_hand, drawn, recovery_start, recovery_end)
	_bridge_rates(label, drawn, published, impact, recovery_end)
	return true


## One fist's window: it may slow down, it may rest on a whole pixel, but it may
## never jump, leave the strike vector or push forward again, and it has to land
## on the baseline the sim is already holding.
func _bridge_retract(label: String, arm: int, start_hand: Array, drawn: Dictionary, recovery_start: int, recovery_end: int) -> void:
	var origin: Vector2 = start_hand[arm]
	if origin.length() <= BRIDGE_ONE_PX:
		return
	var axis := origin.normalized()
	## The window is a smoothstep, so its largest step is 1.5 times the strike
	## divided by the window length; anything bigger is a jump.
	## Two quantization steps of slack on top of the curve: the pose layer snaps
	## its own share before this frame snaps the sum.
	var ceiling := origin.length() * 1.5 / float(recovery_end - recovery_start) + BRIDGE_ONE_PX * 2.0
	var reached := origin.length()
	var previous := origin
	for tick in range(recovery_start + 1, recovery_end):
		var current: Vector2 = (drawn[tick] as Array)[arm]
		## How far along the strike vector the fist still is, and how far off it.
		var along := current.dot(axis)
		var across := (current - axis * along).length()
		_expect(across <= BRIDGE_DRIFT_PX, "%s: fist %d drifted %.2f px off the strike line at tick %d" % [label, arm, across, tick])
		_expect(along <= reached + BRIDGE_ONE_PX, "%s: fist %d pushed %.2f px back out at tick %d" % [label, arm, along - reached, tick])
		_expect((current - previous).length() <= ceiling, "%s: fist %d jumped %.2f px at tick %d" % [label, arm, (current - previous).length(), tick])
		reached = along
		previous = current
	_expect(previous.length() <= BRIDGE_ONE_PX, "%s: fist %d ended %.2f px off the baseline" % [label, arm, previous.length()])
	_expect(reached <= BRIDGE_TOTAL_PX, "%s: fist %d still %.2f px out of its %.2f px strike" % [label, arm, reached, origin.length()])


## A render rate only chooses which tick is drawn, never what a tick looks like:
## every rate re-renders the published fields of the tick it lands on.
func _bridge_rates(label: String, drawn: Dictionary, published: Dictionary, first: int, recovery_end: int) -> void:
	var last := recovery_end - 1
	for rate in RENDER_RATES:
		var frames := int(ceil(float(last - first + 1) * float(rate) / 30.0))
		for frame_index in range(frames):
			var tick: int = first + int(frame_index * 30 / rate)
			if tick > last:
				break
			var again: Array = _render_published(published[tick])
			var during: Array = drawn[tick]
			_expect((again[0] - during[0]).length() <= 0.0001 and (again[1] - during[1]).length() <= 0.0001, "%dHz %s: tick %d draws a different recovery" % [rate, label, tick])


## The two hand deltas the world view will actually place, read back from the same
## boss_draw_parts() the GPU pass and the cutaway prepass both consume.
func _drawn_hands(enemy, frame: Dictionary) -> Array[Vector2]:
	var awakened: bool = enemy.phase_id == "awakened"
	var feet: Vector2 = bridge_view.gameplay_to_world(enemy.position)
	var base_left: Vector2 = enemy.position + Vector2(-43.0 if awakened else -34.0, -8.0 if awakened else 0.0)
	var base_right: Vector2 = enemy.position + Vector2(38.0 if awakened else 34.0, 12.0 if awakened else 0.0)
	var parts: Array[Dictionary] = bridge_view.boss_draw_parts(feet, 2 if awakened else 1, enemy.left_hand_position - base_left, enemy.right_hand_position - base_right, frame)
	return [
		(parts[2]["feet"] as Vector2) - feet - ArenaWorldViewScript.BOSS_HAND_LEFT_OFFSET,
		(parts[3]["feet"] as Vector2) - feet - ArenaWorldViewScript.BOSS_HAND_RIGHT_OFFSET,
	]


## Everything the pose layer and the bridge read, so a frame can be re-rendered
## later from the published fields alone.
func _published_fields(enemy, tick: int) -> Dictionary:
	return {
		"tick": tick,
		"action_id": enemy.action_id,
		"action_state": enemy.action_state,
		"state_started_tick": enemy.state_started_tick,
		"state_ends_tick": enemy.state_ends_tick,
		"phase_id": enemy.phase_id,
		"phase_state": enemy.phase_state,
		"facing": enemy.facing,
		"position": enemy.position,
		"left": enemy.left_hand_position,
		"right": enemy.right_hand_position,
	}


func _render_published(fields: Dictionary) -> Array[Vector2]:
	var enemy = CombatEnemyStateScript.new(fields["position"], 100.0, true, 1, "threshold_colossus")
	enemy.phase_id = fields["phase_id"]
	enemy.phase_state = fields["phase_state"]
	enemy.action_id = fields["action_id"]
	enemy.action_state = fields["action_state"]
	enemy.state_started_tick = fields["state_started_tick"]
	enemy.state_ends_tick = fields["state_ends_tick"]
	enemy.facing = fields["facing"]
	enemy.left_hand_position = fields["left"]
	enemy.right_hand_position = fields["right"]
	return _drawn_hands(enemy, actor_presenter.boss_visual_pose(enemy, fields["tick"]))
