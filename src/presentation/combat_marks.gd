extends RefCounted
## Code-native combat markings for the concept pass (ART_BIBLE v0.9 §07/§09).
##
## The bible draws an authoritative range as a hard edge outline plus sparse
## hatching ("真实范围的硬边轮廓 + 稀疏斜纹") and reads the hunter mark as an open
## bracket above the target ("标记=目标上方开口括号"). Danger geometry is
## generated from the simulation's own numbers and never baked into an atlas, so
## everything here takes plain value geometry and returns line segments:
##
##   diagonal_hatch_segments(rect, spacing) -> 45 degree hatch clipped to rect
##   corner_bracket_segments(frame, arm)     -> four open corner brackets
##
## No function reads an enemy, writes a dictionary or widens a shape, so a
## telegraph can only ever show the range the simulation will really resolve.

## Spacing the pre-fix windup pass hatched at, kept so the pattern density still
## reads the same now that the lines are clipped instead of running long.
const HATCH_SPACING: float = 12.0

## Upper bound on emitted hatch lines: a caller handing in a degenerate spacing
## must not turn one telegraph into thousands of draw calls.
const MAX_HATCH_SEGMENTS: int = 256

## An open bracket keeps at least this much bare frame at every edge, so a
## clamped arm can never close the marking into the ring the bible rejects.
const OPEN_GAP: float = 1.0


static func diagonal_hatch_segments(rect: Rect2, spacing: float = HATCH_SPACING) -> Array[PackedVector2Array]:
	var bounds := rect.abs()
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return []
	var step := spacing if is_finite(spacing) and spacing > 0.0 else HATCH_SPACING
	## A step wider than the shape would step over a small telegraph entirely.
	step = minf(step, maxf(bounds.size.x, bounds.size.y))
	var segments: Array[PackedVector2Array] = []
	## Lines run bottom-left to top-right at 45 degrees, starting one full height
	## left of the range so the first diagonal enters at the bottom-left corner.
	var x := bounds.position.x - bounds.size.y
	while x < bounds.end.x and segments.size() < MAX_HATCH_SEGMENTS:
		var t_low := maxf(0.0, bounds.position.x - x)
		var t_high := minf(bounds.size.y, bounds.end.x - x)
		if t_high - t_low > 0.0:
			segments.append(PackedVector2Array([
				Vector2(x + t_low, bounds.end.y - t_low),
				Vector2(x + t_high, bounds.end.y - t_high),
			]))
		x += step
	return segments


static func corner_bracket_segments(frame: Rect2, arm: float) -> Array[PackedVector2Array]:
	var bounds := frame.abs()
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return []
	var requested := arm if is_finite(arm) else 0.0
	## Arms never reach half the frame extent, which is what keeps the four
	## corners an open bracket instead of a closed box around the actor.
	var limit := maxf(0.0, minf(bounds.size.x, bounds.size.y) * 0.5 - OPEN_GAP)
	var length := clampf(requested, 0.0, limit)
	if length <= 0.0:
		return []
	var segments: Array[PackedVector2Array] = []
	for point in [bounds.position, Vector2(bounds.end.x, bounds.position.y), bounds.end, Vector2(bounds.position.x, bounds.end.y)]:
		var sx := 1.0 if point.x == bounds.position.x else -1.0
		var sy := 1.0 if point.y == bounds.position.y else -1.0
		segments.append(PackedVector2Array([point, point + Vector2(sx * length, 0.0)]))
		segments.append(PackedVector2Array([point, point + Vector2(0.0, sy * length)]))
	return segments
