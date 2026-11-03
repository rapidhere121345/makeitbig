extends RefCounted
class_name ArenaOcclusionQuery

## Deterministic relation shared by the pure actor projection and every
## foreground/occlusion query. A larger key is drawn later in the same domain.

static func entry(baseline_y: float, rank: int, stable_id: String) -> Dictionary:
	return {"baseline_y": baseline_y, "rank": rank, "stable_id": stable_id}


static func precedes(left: Dictionary, right: Dictionary) -> bool:
	var left_y := float(left.get("baseline_y", left.get("y", 0.0)))
	var right_y := float(right.get("baseline_y", right.get("y", 0.0)))
	if left_y < right_y:
		return true
	if left_y > right_y:
		return false
	var left_rank := int(left.get("rank", 0))
	var right_rank := int(right.get("rank", 0))
	if left_rank < right_rank:
		return true
	if left_rank > right_rank:
		return false
	return String(left.get("stable_id", left.get("id", ""))) < String(right.get("stable_id", right.get("id", "")))


static func is_front(occluder: Dictionary, subject: Dictionary) -> bool:
	return precedes(subject, occluder)
