class_name OcclusionPlan
extends RefCounted

## Detached presentation-only occlusion data.  A plan is built from
## explicit entries: feet anchor, baseline, rank, stable id and the ACTUAL
## art box of the piece.  It carries no channel truth: there is no
## accessor that could feed movement, vision or projectile logic, and an
## entry without an art box is rejected instead of falling back to a
## collision rectangle or a placeholder actor.

const SortRelation = preload("res://src/presentation/occlusion_query.gd")

const ENTRY_FIELDS: Array[String] = ["stable_id", "baseline_y", "rank", "feet_anchor", "art_box"]

var _entries: Array[Dictionary] = []
var _by_id: Dictionary = {}


## Builds an ordered plan.  Returns {ok, errors} on rejection or
## {ok, value} with the detached OcclusionPlan instance.
static func build(entries_value: Variant) -> Dictionary:
	if not entries_value is Array:
		return {"ok": false, "errors": ["invalid_type:occlusion_plan_entries"]}
	var errors: Array[String] = []
	var seen: Dictionary = {}
	var canonical: Array[Dictionary] = []
	for index in (entries_value as Array).size():
		var raw: Variant = (entries_value as Array)[index]
		if not raw is Dictionary:
			errors.append("invalid_entry_type:occlusion_plan[%d]" % index)
			continue
		var entry: Dictionary = raw
		for key: Variant in entry.keys():
			if not ENTRY_FIELDS.has(str(key)):
				errors.append("unknown_entry_field:%s[%d]" % [str(key), index])
		for field: String in ENTRY_FIELDS:
			if not entry.has(field):
				errors.append("missing_entry_field:%s[%d]" % [field, index])
		var stable_id := String(entry.get("stable_id", "")).strip_edges()
		if stable_id.is_empty():
			errors.append("missing_stable_id:occlusion_plan[%d]" % index)
		elif seen.has(stable_id):
			errors.append("duplicate_stable_id:%s" % stable_id)
		else:
			seen[stable_id] = true
		var baseline_value: Variant = entry.get("baseline_y", null)
		if not (baseline_value is int or baseline_value is float) or not is_finite(float(baseline_value)):
			errors.append("invalid_baseline_y:occlusion_plan[%d]" % index)
		var rank_value: Variant = entry.get("rank", null)
		if not (rank_value is int or (rank_value is float and is_equal_approx(float(rank_value), roundf(float(rank_value))))) or int(rank_value) < 0:
			errors.append("invalid_rank:occlusion_plan[%d]" % index)
		var feet := _point_from(entry.get("feet_anchor", null))
		if not feet.is_finite():
			errors.append("invalid_feet_anchor:occlusion_plan[%d]" % index)
		if not entry.has("art_box"):
			errors.append("missing_art_box:%s" % stable_id if not stable_id.is_empty() else "missing_art_box:occlusion_plan[%d]" % index)
		else:
			var box := _rect_from(entry["art_box"])
			if not _valid_box(box):
				errors.append("invalid_art_box:occlusion_plan[%d]" % index)
		if not entry.has("stable_id") or not entry.has("baseline_y") or not entry.has("rank") or not entry.has("feet_anchor") or not entry.has("art_box"):
			continue
		canonical.append({
			"stable_id": stable_id,
			"baseline_y": float(entry["baseline_y"]),
			"rank": int(entry["rank"]),
			"feet_anchor": feet,
			"art_box": _rect_from(entry["art_box"]),
		})
	if not errors.is_empty():
		return {"ok": false, "errors": errors}
	canonical.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return SortRelation.precedes(left, right)
	)
	var plan: OcclusionPlan = load("res://src/presentation/occlusion/occlusion_plan.gd").new()
	for entry: Dictionary in canonical:
		var detached := entry.duplicate(true)
		plan._entries.append(detached)
		plan._by_id[String(detached["stable_id"])] = detached
	return {"ok": true, "errors": [], "value": plan}


## Ordered, detached copies.  The order is the total draw order
## (baseline_y, rank, stable_id) shared with the occlusion relation.
func entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Dictionary in _entries:
		result.append(entry.duplicate(true))
	return result


func has(stable_id: String) -> bool:
	return _by_id.has(stable_id)


func entry(stable_id: String) -> Dictionary:
	if not _by_id.has(stable_id):
		return {}
	return (_by_id[stable_id] as Dictionary).duplicate(true)


func size() -> int:
	return _entries.size()


## Pieces drawn in front of the subject (higher baseline/rank) whose real
## art box overlaps the subject art box, in deterministic plan order.
func occluders_of(stable_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not _by_id.has(stable_id):
		return result
	var subject_entry: Dictionary = _by_id[stable_id]
	for candidate: Dictionary in _entries:
		if String(candidate["stable_id"]) == stable_id:
			continue
		if not SortRelation.is_front(candidate, subject_entry):
			continue
		if not (candidate["art_box"] as Rect2).intersects(subject_entry["art_box"] as Rect2):
			continue
		result.append(candidate.duplicate(true))
	return result


## Headless report for one subject: whether front pieces cover its real
## art pixels and how much of its own box they cover (clamped to 1.0).
func occlusion_report(stable_id: String) -> Dictionary:
	if not _by_id.has(stable_id):
		return {"ok": false, "error": "unknown_stable_id", "occluded": false, "occluder_ids": [], "cover_fraction": 0.0}
	var occluders := occluders_of(stable_id)
	var subject := _by_id[stable_id] as Dictionary
	var subject_box: Rect2 = subject["art_box"]
	var subject_area: float = subject_box.get_area()
	var covered := 0.0
	var ids: Array[String] = []
	for occluder: Dictionary in occluders:
		ids.append(String(occluder["stable_id"]))
		covered += (subject_box.intersection(occluder["art_box"] as Rect2)).get_area()
	var cover_fraction := 0.0 if subject_area <= 0.0 else clampf(covered / subject_area, 0.0, 1.0)
	return {
		"ok": true,
		"occluded": not ids.is_empty(),
		"occluder_ids": ids,
		"cover_fraction": cover_fraction,
	}


## Explicit marker: this object is presentation truth only.
func is_presentation_only() -> bool:
	return true


## JSON-safe payload of the ordered plan (arrays, no engine types).
func to_payload() -> Array:
	var result: Array = []
	for entry: Dictionary in _entries:
		var box: Rect2 = entry["art_box"]
		var feet: Vector2 = entry["feet_anchor"]
		result.append({
			"stable_id": entry["stable_id"],
			"baseline_y": entry["baseline_y"],
			"rank": entry["rank"],
			"feet_anchor": [feet.x, feet.y],
			"art_box": [box.position.x, box.position.y, box.size.x, box.size.y],
		})
	return result


static func _point_from(value: Variant) -> Vector2:
	if value is Vector2:
		return value
	if value is Array:
		var values: Array = value
		if values.size() == 2 and values.all(func(item: Variant) -> bool: return item is int or item is float):
			return Vector2(float(values[0]), float(values[1]))
	return Vector2.INF


static func _rect_from(value: Variant) -> Rect2:
	if value is Rect2:
		return value
	if value is Array:
		var values: Array = value
		if values.size() == 4 and values.all(func(item: Variant) -> bool: return item is int or item is float):
			return Rect2(float(values[0]), float(values[1]), float(values[2]), float(values[3]))
	return Rect2()


static func _valid_box(box: Rect2) -> bool:
	return box.position.is_finite() and box.size.is_finite() and box.size.x > 0.0 and box.size.y > 0.0
