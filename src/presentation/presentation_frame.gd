class_name PresentationFrame
extends RefCounted

const SelfScript := preload("res://src/presentation/presentation_frame.gd")
const OcclusionPlanScript := preload("res://src/presentation/occlusion/occlusion_plan.gd")

const ENTRY_FIELDS: Array[String] = ["stable_id", "visual_id", "feet_anchor", "baseline_y", "rank", "art_box"]

var tick := -1
var world_revision := -1
var entries: Array[Dictionary] = []


static func build(authoritative_tick: int, revision: int, raw_entries: Variant) -> Dictionary:
	if authoritative_tick < 0 or revision < 0 or not raw_entries is Array:
		return _failure("invalid_presentation_frame_header")
	var result: Variant = SelfScript.new()
	result.tick = authoritative_tick
	result.world_revision = revision
	var seen: Dictionary = {}
	for raw_value: Variant in raw_entries as Array:
		if not raw_value is Dictionary:
			return _failure("presentation_entry_not_dictionary")
		var raw: Dictionary = raw_value
		for key: Variant in raw.keys():
			if String(key) not in ENTRY_FIELDS:
				return _failure("unknown_presentation_entry_field:%s" % String(key))
		for field: String in ENTRY_FIELDS:
			if not raw.has(field):
				return _failure("missing_presentation_entry_field:%s" % field)
		var stable_id := String(raw.get("stable_id", ""))
		var visual_id := String(raw.get("visual_id", ""))
		if not _valid_id(stable_id) or not _valid_id(visual_id) or seen.has(stable_id):
			return _failure("invalid_presentation_entry_identity")
		var feet: Variant = raw.get("feet_anchor")
		if not feet is Vector2 or not (feet as Vector2).is_finite():
			return _failure("invalid_presentation_feet_anchor")
		var baseline: Variant = raw.get("baseline_y")
		if not (baseline is int or baseline is float) or not is_finite(float(baseline)):
			return _failure("invalid_presentation_baseline")
		var rank: Variant = raw.get("rank")
		if not rank is int or int(rank) < 0:
			return _failure("invalid_presentation_rank")
		var art_box: Variant = raw.get("art_box")
		if not art_box is Rect2 or not (art_box as Rect2).position.is_finite() or not (art_box as Rect2).size.is_finite() or (art_box as Rect2).size.x <= 0.0 or (art_box as Rect2).size.y <= 0.0:
			return _failure("invalid_presentation_art_box")
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
		if not is_equal_approx(float(left["baseline_y"]), float(right["baseline_y"])):
			return float(left["baseline_y"]) < float(right["baseline_y"])
		if int(left["rank"]) != int(right["rank"]):
			return int(left["rank"]) < int(right["rank"])
		return String(left["stable_id"]) < String(right["stable_id"])
	)
	return {"ok": true, "error": "", "value": result}


func occlusion_plan() -> Dictionary:
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


static func _failure(error: String) -> Dictionary:
	return {"ok": false, "error": error}
