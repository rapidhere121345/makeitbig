class_name PresentationFrame
extends RefCounted

const SelfScript := preload("res://src/presentation/presentation_frame.gd")
const OcclusionPlanScript := preload("res://src/presentation/occlusion/occlusion_plan.gd")
const SortRelation := preload("res://src/presentation/occlusion_query.gd")
const CoreResult := preload("res://src/core/result.gd")

const ENTRY_FIELDS: Array[String] = ["stable_id", "visual_id", "feet_anchor", "baseline_y", "rank", "art_box"]

var tick := -1
var world_revision := -1
var entries: Array[Dictionary] = []
var _plan_key: Array = []
var _plan_cache: Dictionary = {}


static func build(authoritative_tick: int, revision: int, raw_entries: Variant) -> Dictionary:
	if authoritative_tick < 0 or revision < 0 or not raw_entries is Array:
		return CoreResult.failure("invalid_presentation_frame_header")
	var result: Variant = SelfScript.new()
	result.tick = authoritative_tick
	result.world_revision = revision
	var seen: Dictionary = {}
	for raw_value: Variant in raw_entries as Array:
		if not raw_value is Dictionary:
			return CoreResult.failure("presentation_entry_not_dictionary")
		var raw: Dictionary = raw_value
		for key: Variant in raw.keys():
			if String(key) not in ENTRY_FIELDS:
				return CoreResult.failure("unknown_presentation_entry_field:%s" % String(key))
		for field: String in ENTRY_FIELDS:
			if not raw.has(field):
				return CoreResult.failure("missing_presentation_entry_field:%s" % field)
		var stable_id := String(raw.get("stable_id", ""))
		var visual_id := String(raw.get("visual_id", ""))
		if not _valid_id(stable_id) or not _valid_id(visual_id) or seen.has(stable_id):
			return CoreResult.failure("invalid_presentation_entry_identity")
		var feet: Variant = raw.get("feet_anchor")
		if not feet is Vector2 or not (feet as Vector2).is_finite():
			return CoreResult.failure("invalid_presentation_feet_anchor")
		var baseline: Variant = raw.get("baseline_y")
		if not (baseline is int or baseline is float) or not is_finite(float(baseline)):
			return CoreResult.failure("invalid_presentation_baseline")
		var rank: Variant = raw.get("rank")
		if not rank is int or int(rank) < 0:
			return CoreResult.failure("invalid_presentation_rank")
		var art_box: Variant = raw.get("art_box")
		if not art_box is Rect2 or not (art_box as Rect2).position.is_finite() or not (art_box as Rect2).size.is_finite() or (art_box as Rect2).size.x <= 0.0 or (art_box as Rect2).size.y <= 0.0:
			return CoreResult.failure("invalid_presentation_art_box")
		result.entries.append({
			"stable_id": stable_id,
			"visual_id": visual_id,
			"feet_anchor": feet,
			"baseline_y": float(baseline),
			"rank": int(rank),
			"art_box": art_box,
		})
		seen[stable_id] = true
	result.entries.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return SortRelation.precedes(left, right)
	)
	return {"ok": true, "error": "", "value": result}


## `entries` is public and mutable, so the cached plan is reused only while the
## occlusion-relevant values are exactly equal to those it was built from.
## Plans are immutable and hand out detached copies, so sharing one is safe.
func occlusion_plan() -> Dictionary:
	var key: Array = []
	for entry: Dictionary in entries:
		key.append([entry.get("stable_id"), entry.get("baseline_y"), entry.get("rank"), entry.get("feet_anchor"), entry.get("art_box")])
	if not _plan_cache.is_empty() and key == _plan_key:
		return _plan_cache.duplicate()
	var result := _build_occlusion_plan()
	if bool(result.get("ok", false)):
		# Public entries may be replaced with the plan's accepted Array-form
		# coordinates. Snapshot nested containers so in-place edits invalidate.
		_plan_key = key.duplicate(true)
		_plan_cache = result.duplicate()
	else:
		_plan_key = []
		_plan_cache = {}
	return result


func _build_occlusion_plan() -> Dictionary:
	var occlusion_entries: Array[Dictionary] = []
	for entry: Dictionary in entries:
		occlusion_entries.append({
			"stable_id": entry["stable_id"],
			"baseline_y": entry["baseline_y"],
			"rank": entry["rank"],
			"feet_anchor": entry["feet_anchor"],
			"art_box": entry["art_box"],
		})
	return OcclusionPlanScript.build(occlusion_entries)


func snapshot() -> Dictionary:
	var copied: Array[Dictionary] = []
	for entry: Dictionary in entries:
		copied.append(entry.duplicate(true))
	return {"tick": tick, "world_revision": world_revision, "entries": copied}


static func _valid_id(value: String) -> bool:
	return not value.is_empty() and value == value.strip_edges() and not value.contains(" ")

