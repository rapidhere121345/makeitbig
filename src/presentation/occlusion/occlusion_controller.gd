class_name OcclusionController
extends RefCounted

## Presentation-side occlusion controller contract.  It owns ONLY its own
## interpolation and alpha-transition state: high-refresh display feet
## positions smoothing toward authoritative sim anchors, and per-stable-id
## alpha moving toward a cover-derived target.  It takes no scene, no
## simulation object and no channel data; every input is a plain value or
## a detached OcclusionPlan, so it has no way to write simulation state.

const PlanScript = preload("res://src/presentation/occlusion/occlusion_plan.gd")

const DEFAULT_ALPHA_RATE: float = 5.0
const DEFAULT_FOLLOW_RATE: float = 20.0
const OCCLUDED_TARGET_ALPHA: float = 0.4
const CLEAR_TARGET_ALPHA: float = 1.0
## Cover tiers (audit R2: an occluded subject must not turn into a ghost the
## moment its feet graze a front piece's bounding box).  Below
## COVER_GRAZE_THRESHOLD the overlap is a graze and must NOT dim at all;
## between the thresholds the alpha target ramps linearly from the clear
## target down to the occluded target; at or above COVER_FULL_THRESHOLD any
## cover maps straight onto the occluded target.  Presentation comfort
## tuning only: the fractions come from art-box geometry and carry no
## gameplay meaning.
const COVER_GRAZE_THRESHOLD: float = 0.15
const COVER_FULL_THRESHOLD: float = 0.45

var _plan: Variant = null
var _state: Dictionary = {}
## Occluder window registry: stable ids of front pieces that currently cover
## an actor, each easing toward its own cover-tier alpha. Kept separate from
## the subject registry so a piece can window open while its subject stays
## fully opaque.
var _occluder_state: Dictionary = {}


## Adopts a detached plan as the current presentation truth.  Display
## state starts at the authoritative anchors with full alpha.
func adopt_plan(plan: Variant) -> Dictionary:
	if not plan is PlanScript:
		return {"ok": false, "errors": ["invalid_occlusion_plan"]}
	_plan = plan
	_state.clear()
	_occluder_state.clear()
	for entry: Dictionary in plan.call("entries"):
		var stable_id := String(entry["stable_id"])
		_state[stable_id] = {
			"display_feet": entry["feet_anchor"],
			"target_feet": entry["feet_anchor"],
			"alpha": CLEAR_TARGET_ALPHA,
			"target_alpha": CLEAR_TARGET_ALPHA,
		}
	return {"ok": true, "errors": []}


## Feeds one detached plan for the current display frame. The tracked id set
## is adopted only when it actually changes (spawn, death, room restart), so
## consecutive tick plans keep their interpolation and alpha transitions
## instead of being reset every frame. Deterministic: equal inputs always
## produce equal state.
func sync_plan(plan: Variant) -> Dictionary:
	if not plan is PlanScript:
		return {"ok": false, "errors": ["invalid_occlusion_plan"]}
	var next_ids: Dictionary = {}
	for entry: Dictionary in plan.call("entries"):
		next_ids[String(entry["stable_id"])] = true
	var same_set: bool = next_ids.size() == _state.size()
	if same_set:
		for stable_id: String in next_ids.keys():
			if not _state.has(stable_id):
				same_set = false
				break
	if not same_set:
		return adopt_plan(plan)
	for entry: Dictionary in plan.call("entries"):
		var state: Dictionary = _state[String(entry["stable_id"])]
		var anchor: Vector2 = entry["feet_anchor"]
		if anchor.is_finite():
			state["target_feet"] = anchor
	return {"ok": true, "errors": []}


## Feeds one authoritative simulation feet anchor (plain values only).
## This updates the presentation target; it never touches the simulation.
func set_subject_anchor(stable_id: String, feet_world: Vector2) -> Dictionary:
	if not _state.has(stable_id):
		return {"ok": false, "error": "unknown_stable_id"}
	if not feet_world.is_finite():
		return {"ok": false, "error": "invalid_feet_anchor"}
	(_state[stable_id] as Dictionary)["target_feet"] = feet_world
	return {"ok": true, "error": ""}


## Feeds a cover fraction (from OcclusionPlan.occlusion_report) and maps
## it onto an alpha transition target through the named cover tiers.  A
## grazing cover stays clear, a partial cover ramps toward the occluded
## target, a full cover dims straight to it, and a clear subject returns
## to full alpha.
func set_cover(stable_id: String, cover_fraction: float) -> Dictionary:
	if not _state.has(stable_id):
		return {"ok": false, "error": "unknown_stable_id"}
	if not is_finite(cover_fraction) or cover_fraction < 0.0:
		return {"ok": false, "error": "invalid_cover_fraction"}
	(_state[stable_id] as Dictionary)["target_alpha"] = _target_alpha_for_cover(cover_fraction)
	return {"ok": true, "error": ""}


## The cover-tier map: continuous and monotonic by construction.  A pure
## function of the fraction, so equal inputs always produce equal targets
## and the existing eased alpha transition is untouched.
static func _target_alpha_for_cover(cover_fraction: float) -> float:
	if cover_fraction <= COVER_GRAZE_THRESHOLD:
		return CLEAR_TARGET_ALPHA
	if cover_fraction >= COVER_FULL_THRESHOLD:
		return OCCLUDED_TARGET_ALPHA
	var ramp: float = clampf(inverse_lerp(COVER_GRAZE_THRESHOLD, COVER_FULL_THRESHOLD, cover_fraction), 0.0, 1.0)
	return lerpf(CLEAR_TARGET_ALPHA, OCCLUDED_TARGET_ALPHA, ramp)


## Occluder window feed: one front piece's cover fraction over any tracked
## actor, mapped through the same tiers. A grazing overlap keeps the piece
## opaque; a full cover opens the window to the occluded target so the actor
## behind it stays readable. The presenter drives these ids; nothing here
## touches the simulation or the scene.
func set_occluder_cover(occluder_id: String, cover_fraction: float) -> Dictionary:
	if occluder_id.strip_edges().is_empty():
		return {"ok": false, "error": "invalid_occluder_id"}
	if not is_finite(cover_fraction) or cover_fraction < 0.0:
		return {"ok": false, "error": "invalid_cover_fraction"}
	if not _occluder_state.has(occluder_id):
		_occluder_state[occluder_id] = {"alpha": CLEAR_TARGET_ALPHA, "target_alpha": CLEAR_TARGET_ALPHA}
	(_occluder_state[occluder_id] as Dictionary)["target_alpha"] = _target_alpha_for_cover(cover_fraction)
	return {"ok": true, "error": ""}


## The eased window alpha of one front piece. Unknown ids report INF so a
## presenter can distinguish "fully clear" from "not tracked".
func occluder_alpha(occluder_id: String) -> float:
	if not _occluder_state.has(occluder_id):
		return INF
	return _occluder_state[occluder_id]["alpha"]


func occluder_ids() -> Array[String]:
	var ids: Array[String] = []
	for occluder_id: String in _occluder_state.keys():
		ids.append(occluder_id)
	ids.sort()
	return ids


func clear_occluders() -> void:
	_occluder_state.clear()


## Advances display interpolation and alpha transitions.  Clamp prevents
## overshoot; equal inputs always produce equal outputs (no clock or
## engine state is read inside).
func update(delta_seconds: float, alpha_rate: float = DEFAULT_ALPHA_RATE, follow_rate: float = DEFAULT_FOLLOW_RATE) -> void:
	if not is_finite(delta_seconds) or delta_seconds <= 0.0:
		return
	for stable_id: String in _state.keys():
		var entry: Dictionary = _state[stable_id]
		var target_feet: Vector2 = entry["target_feet"]
		var display_feet: Vector2 = entry["display_feet"]
		var blend := 1.0 - exp(-maxf(follow_rate, 0.0) * delta_seconds)
		entry["display_feet"] = display_feet.lerp(target_feet, blend)
		var target_alpha: float = entry["target_alpha"]
		var alpha: float = entry["alpha"]
		var step: float = maxf(alpha_rate, 0.0) * delta_seconds
		if alpha < target_alpha:
			entry["alpha"] = minf(alpha + step, target_alpha)
		elif alpha > target_alpha:
			entry["alpha"] = maxf(alpha - step, target_alpha)
	for occluder_id: String in _occluder_state.keys():
		var window: Dictionary = _occluder_state[occluder_id]
		var window_target: float = window["target_alpha"]
		var window_alpha: float = window["alpha"]
		var window_step: float = maxf(alpha_rate, 0.0) * delta_seconds
		if window_alpha < window_target:
			window["alpha"] = minf(window_alpha + window_step, window_target)
		elif window_alpha > window_target:
			window["alpha"] = maxf(window_alpha - window_step, window_target)


func display_feet(stable_id: String) -> Vector2:
	if not _state.has(stable_id):
		return Vector2.INF
	return _state[stable_id]["display_feet"]


func alpha(stable_id: String) -> float:
	if not _state.has(stable_id):
		return INF
	return _state[stable_id]["alpha"]


func tracked_ids() -> Array[String]:
	var ids: Array[String] = []
	for stable_id: String in _state.keys():
		ids.append(stable_id)
	ids.sort()
	return ids


## Deterministic presentation snapshot ordered by stable id.  Entries
## carry positions and alpha only: there is intentionally no geometry or
## channel payload here, and never a collision-rectangle fallback.
func snapshot() -> Dictionary:
	var result: Dictionary = {}
	for stable_id: String in tracked_ids():
		var entry: Dictionary = _state[stable_id]
		var feet: Vector2 = entry["display_feet"]
		result[stable_id] = {
			"display_feet": [feet.x, feet.y],
			"alpha": entry["alpha"],
		}
	return result
