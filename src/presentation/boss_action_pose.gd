extends RefCounted
## Boss action pose layer for the threshold colossus: three telegraphed moves,
## two phases, one pure function.
##
## The simulation stays the only authority. This file reads the values it already
## publishes and replays them as additive native-pixel offsets:
##
##   body_feet  = feet_world + pose["body_offset_px"]
##   core_feet  = feet_world + BOSS_CORE_OFFSET + pose["core_offset_px"]
##   left_feet  = feet_world + BOSS_HAND_LEFT_OFFSET
##                + (enemy.left_hand_position - left_base) * GAMEPLAY_TO_WORLD
##                + pose["left_hand_offset_px"]
##   right_feet = feet_world + BOSS_HAND_RIGHT_OFFSET
##                + (enemy.right_hand_position - right_base) * GAMEPLAY_TO_WORLD
##                + pose["right_hand_offset_px"]
##
## The offsets are added on top of the approved baseline. They never replace the
## authoritative hand deltas, which keep deciding where the fists really are and
## stay part of the replay hash.
##
## Nothing here writes gameplay state, reads a clock or a frame delta, samples
## randomness, or draws a pixel, so:
##  * a redraw can never restart a clip or change a telegraph;
##  * damage, collision and the replay hash are untouched - the sim resolves its
##    damage on the single authoritative active tick, and this pose only ever
##    shows that tick and then retracts;
##  * the same authority tick renders the same pose at 30, 60 and 144 Hz;
##  * every motion step is quantized to a whole native pixel.
##
## The three moves read the approved
## docs/art-production/concepts/v0.9-p1-complete/11_boss_vfx_language.png language:
##   slam   both fists lift, one-tick drop, heavy return
##   sweep  the right fist pulls along the sim's own perpendicular axis, one-tick
##          sweep-through to the other side, then return
##   lane   the right fist cocks back off the authoritative facing, one-tick
##          thrust along it, then return
## The sealed colossus only slams; the awakened one cycles slam, sweep and lane.
##
## The sim drops its own hand deltas back to the baseline on the first recovery
## tick, so authority_recovery_hand_offsets() hands the draw call back the share
## of the strike the sim dropped, in world pixels: the fists then retract from
## where the active tick left them instead of stepping to the base.

## The three boss moves, in the order the awakened colossus cycles them in
## src/game/main.gd _update_boss_tick. Anything else stays at the neutral pose, so
## a normal enemy state can never borrow a colossus pose.
const ACTIONS: Array[String] = ["slam", "sweep", "lane"]

## The four stages, named exactly like the sim's action_state values.
const STAGE_IDLE: String = "idle"
const STAGE_WINDUP: String = "windup"
const STAGE_ACTIVE: String = "active"
const STAGE_RECOVERY: String = "recovery"
## The phase transition is presentation-owned elsewhere (the sim zeroes the hands
## and main draws its own rings), so the pose stays neutral through it.
const PHASE_TRANSITION: String = "transition"

## Frame contract: exactly the keys pose() returns.
const FRAME_FIELDS: Array[String] = [
	"tag",
	"body_offset_px",
	"left_hand_offset_px",
	"right_hand_offset_px",
	"core_offset_px",
	"core_tint",
]

## Windup travel reaches full reach at this fraction of the telegraph and then
## holds, so the pose is already promising the hit while the danger shape keeps
## counting down (and a longer telegraph keeps the same readable shape).
const WINDUP_FILL: float = 1.5
## The awakened colossus carries more weight: travel grows, direction, staging
## and the frame contract do not change.
const PHASE2_TRAVEL_SCALE: float = 1.15

## slam: both fists lift together and flare one pixel outward while they rise,
## then drop on the active tick with the body sinking behind them.
const SLAM_LIFT_PX: float = 14.0
const SLAM_SINK_PX: float = 9.0
const SLAM_FLARE_PX: float = 1.0
const SLAM_BODY_RISE_PX: float = 1.0
const SLAM_BODY_DROP_PX: float = 2.0
## sweep: the right fist amplifies the sim's own perpendicular pull on the windup
## and crosses to the other side of that axis on the active tick.
const SWEEP_PULL_PX: float = 12.0
const SWEEP_BODY_SHIFT_PX: float = 2.0
## lane: the right fist cocks back off the facing and lifts, then thrusts along
## it with a small body lunge behind the punch.
const LANE_COCK_BACK_PX: float = 10.0
const LANE_COCK_LIFT_PX: float = 2.0
const LANE_PUNCH_PX: float = 16.0
const LANE_PUNCH_DIP_PX: float = 2.0
const LANE_BODY_ROCK_PX: float = 1.0
const LANE_BODY_LUNGE_PX: float = 3.0

## The sim's own active-tick hand deltas, mirrored read-only from
## src/game/main.gd _update_boss_hands. It adds these on top of the base while the
## state is "windup" or "active"; the recovery bridge below returns the share of
## them the sim drops when it flips the state back, so the seam never shows.
const SLAM_ACTIVE_HAND_PX: float = 18.0
const SWEEP_ACTIVE_HAND_PX: float = 18.0
const LANE_ACTIVE_HAND_PX: Vector2 = Vector2(8.0, -10.0)

## Whole-hand travel stays inside a third of the body's 128px width and the body
## never rocks more than a toe. The tests hold these ceilings.
const MAX_HAND_OFFSET_PX: int = 24
const MAX_BODY_OFFSET_PX: int = 4

## Both phases keep the authored palette. Separate core sprites already express
## awakening; a second tint would drift from the approved pixel colours.
const PHASE1_CORE_TINT: Color = Color.WHITE
const PHASE2_CORE_TINT: Color = Color.WHITE


## The one entry point. sim_tick and the two state timestamps come straight from
## the authoritative enemy record (state_started_tick / state_ends_tick), so the
## windup and recovery shapes are normalized against the real telegraph and
## recovery lengths instead of this file's idea of them.
##
## Returns the frame contract above. Every offset is zero for idle, the phase
## transition, and any action this layer does not own.
static func pose(
	action_id: String,
	action_state: String,
	sim_tick: int,
	state_started_tick: int,
	state_ends_tick: int,
	phase: int = 1,
	facing: Vector2 = Vector2.DOWN,
	phase_state: String = "stable"
) -> Dictionary:
	var frame := {
		"tag": STAGE_IDLE,
		"body_offset_px": Vector2i.ZERO,
		"left_hand_offset_px": Vector2i.ZERO,
		"right_hand_offset_px": Vector2i.ZERO,
		"core_offset_px": Vector2i.ZERO,
		"core_tint": PHASE2_CORE_TINT if phase >= 2 else PHASE1_CORE_TINT,
	}
	var stage := stage_for(action_state)
	if stage == STAGE_IDLE or phase_state == PHASE_TRANSITION or not ACTIONS.has(action_id):
		return frame
	var progress := state_progress(sim_tick, state_started_tick, state_ends_tick)
	var forward := _forward(facing)
	var side := forward.rotated(-PI * 0.5)
	var body := Vector2.ZERO
	var left := Vector2.ZERO
	var right := Vector2.ZERO
	var tag := STAGE_IDLE
	match action_id:
		"slam":
			var lift := _travel(SLAM_LIFT_PX, phase)
			var sink := _travel(SLAM_SINK_PX, phase)
			var flare := _travel(SLAM_FLARE_PX, phase)
			var rise := _travel(SLAM_BODY_RISE_PX, phase)
			var drop := _travel(SLAM_BODY_DROP_PX, phase)
			match stage:
				STAGE_WINDUP:
					var w := _windup_curve(progress)
					tag = "slam_lift"
					left = Vector2(-flare, -lift) * w
					right = Vector2(flare, -lift) * w
					body = Vector2(0.0, -rise * w)
				STAGE_ACTIVE:
					tag = "slam_impact"
					left = Vector2(0.0, sink)
					right = Vector2(0.0, sink)
					body = Vector2(0.0, drop)
				_:
					var back := 1.0 - _recovery_curve(progress)
					tag = "slam_return"
					left = Vector2(0.0, sink * back)
					right = Vector2(0.0, sink * back)
					body = Vector2(0.0, drop * back)
		"sweep":
			var pull := _travel(SWEEP_PULL_PX, phase)
			var shift := _travel(SWEEP_BODY_SHIFT_PX, phase)
			match stage:
				STAGE_WINDUP:
					var w := _windup_curve(progress)
					tag = "sweep_pull"
					right = side * (pull * w)
					body = side * (-shift * w)
				STAGE_ACTIVE:
					tag = "sweep_through"
					right = side * -pull
					body = side * shift
				_:
					var back := 1.0 - _recovery_curve(progress)
					tag = "sweep_return"
					right = side * (-pull * back)
					body = side * (shift * back)
		"lane":
			var cock := _travel(LANE_COCK_BACK_PX, phase)
			var lift := _travel(LANE_COCK_LIFT_PX, phase)
			var dip := _travel(LANE_PUNCH_DIP_PX, phase)
			var rock := _travel(LANE_BODY_ROCK_PX, phase)
			var lunge := _travel(LANE_BODY_LUNGE_PX, phase)
			var thrust := forward * _travel(LANE_PUNCH_PX, phase) + Vector2(0.0, dip)
			match stage:
				STAGE_WINDUP:
					var w := _windup_curve(progress)
					tag = "lane_cock"
					right = (-forward * cock + Vector2(0.0, -lift)) * w
					body = (-forward * rock) * w
				STAGE_ACTIVE:
					tag = "lane_thrust"
					right = thrust
					body = forward * lunge
				_:
					var back := 1.0 - _recovery_curve(progress)
					tag = "lane_return"
					right = thrust * back
					body = (forward * lunge) * back
	frame["tag"] = tag
	frame["body_offset_px"] = _quantize(body)
	frame["left_hand_offset_px"] = _quantize(left)
	frame["right_hand_offset_px"] = _quantize(right)
	## The core is drawn from the feet point, so it always rides the body offset.
	frame["core_offset_px"] = frame["body_offset_px"]
	return frame


## Recovery bridge. main._enemy_ai._update_boss_hands publishes its active hand deltas only
## while the state is "windup" or "active": on the first recovery tick both fists
## are back at the base, while the frame before it drew the hit. pose() already
## retracts its own share of the strike, so this returns the share the sim
## dropped, in world pixels, ready to be added to the two hand fields of a
## recovery frame:
##
##   recovery_hand(p) + bridge(p) == (1 - smoothstep(p)) * strike_hand
##
## strike_hand is what the active tick really drew: the authoritative delta the
## sim published on that tick times the world scale. The mirror lives in
## _sim_active_left()/_sim_active_right() and test_boss_action_pose.gd compares
## them against the real main._enemy_ai._update_boss_hands output, so a change to the sim's
## strike formula fails the suite instead of silently leaving a seam.
##
## Every other stage returns zero, so windup and active draw exactly what they
## drew before. This is a pure read of the published fields - no clock, no
## randomness, no simulation write - so no tick, timestamp, target shape or
## replay hash can move.
##
## The two values are deliberately left unsnapped: the caller adds them to the
## hand fields of the recovery frame and snaps that sum once, so the pose layer's
## own rounding and the bridge's cannot fight over the last pixel.
static func authority_recovery_hand_offsets(
	action_id: String,
	action_state: String,
	sim_tick: int,
	state_started_tick: int,
	state_ends_tick: int,
	facing: Vector2 = Vector2.DOWN,
	world_scale: float = 1.0
) -> Dictionary:
	var none := {"left": Vector2.ZERO, "right": Vector2.ZERO}
	if stage_for(action_state) != STAGE_RECOVERY or not ACTIONS.has(action_id):
		return none
	var owed := 1.0 - _recovery_curve(state_progress(sim_tick, state_started_tick, state_ends_tick))
	return {
		"left": _sim_active_left(action_id, facing) * world_scale * owed,
		"right": _sim_active_right(action_id, facing) * world_scale * owed,
	}


## The sim's own active-tick hand deltas, mirrored read-only from
## src/game/main.gd _update_boss_hands, in the gameplay units main hands to the
## world view. slam drops the left fist only (the pose layer carries the right one
## on the same tick), sweep pulls the right fist along the sim's own perpendicular
## axis, lane pushes the fists apart on a fixed pair of vectors the sim does not
## rotate with the facing.
static func _sim_active_left(action_id: String, facing: Vector2) -> Vector2:
	match action_id:
		"slam":
			return Vector2(0.0, SLAM_ACTIVE_HAND_PX)
		"lane":
			return -LANE_ACTIVE_HAND_PX
		_:
			return Vector2.ZERO


static func _sim_active_right(action_id: String, facing: Vector2) -> Vector2:
	match action_id:
		"sweep":
			return facing.rotated(-PI * 0.5) * -SWEEP_ACTIVE_HAND_PX
		"lane":
			return LANE_ACTIVE_HAND_PX
		_:
			return Vector2.ZERO


## The sim's action_state mapped onto this layer's four stages. "recover" is
## accepted because the atlas side spells the same stage that way.
static func stage_for(action_state: String) -> String:
	match action_state:
		STAGE_WINDUP:
			return STAGE_WINDUP
		STAGE_ACTIVE:
			return STAGE_ACTIVE
		"recovery", "recover":
			return STAGE_RECOVERY
		_:
			return STAGE_IDLE


## Normalized progress inside an authoritative state, clamped to [0, 1]. A tick
## before the start reports 0.0, a tick at or past the end reports 1.0, and a
## state with no span never divides by zero.
static func state_progress(sim_tick: int, state_started_tick: int, state_ends_tick: int) -> float:
	var span := state_ends_tick - state_started_tick
	if span <= 0:
		return 1.0
	return clampf(float(sim_tick - state_started_tick) / float(span), 0.0, 1.0)


## Windup: smooth ramp that reaches full reach at WINDUP_FILL and holds there.
static func _windup_curve(progress: float) -> float:
	return _smoothstep(clampf(progress * WINDUP_FILL, 0.0, 1.0))


## Recovery: smooth 1 -> 0 return, used as "how much of the peak is still on".
static func _recovery_curve(progress: float) -> float:
	return _smoothstep(progress)


## 0 -> 1 -> 0 velocity at both ends, so a retract never snaps off the peak and
## never pops off the baseline when the sim flips the state to "none".
static func _smoothstep(value: float) -> float:
	var x := clampf(value, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


## The authoritative facing, guarded so a zero or non-finite facing still gives
## a finite pose.
static func _forward(facing: Vector2) -> Vector2:
	if not is_finite(facing.x) or not is_finite(facing.y) or facing.length_squared() <= 0.000001:
		return Vector2.DOWN
	return facing.normalized()


## Phase 2 is heavier, not different: one scalar per move amplitude.
static func _travel(amplitude: float, phase: int) -> float:
	return amplitude * (PHASE2_TRAVEL_SCALE if phase >= 2 else 1.0)


## Native-pixel quantization: every offset the renderer adds is a whole pixel.
static func _quantize(offset: Vector2) -> Vector2i:
	return Vector2i(roundi(offset.x), roundi(offset.y))
