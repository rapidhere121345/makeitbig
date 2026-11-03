class_name RoomPresentationBinding
extends RefCounted

## Explicit typed visual binding for the detached presentation projection.
##
## A binding is the only allowed source of actor visual identity for
## PresentationFrame entries: stable id, visual id, authored rank and the
## REAL art box of the drawn piece. Construction rejects every entry without
## a finite positive-size art box. There is deliberately no constructor that
## accepts a collision shape, a footprint radius or debug geometry, so a
## missing art box can only fail the binding; it can never fall back to
## gameplay geometry.

var stable_id := ""
var visual_id := ""
var rank := 0
var art_box := Rect2()
## Authored world feet anchor for static authored pieces. Actor bindings
## keep this at Vector2.INF and resolve their feet from the authoritative
## snapshot on every projection.
var static_feet_anchor := Vector2.INF


## Visual binding for one real simulation actor. The feet anchor is never
## authored here; the projector reads it from the authoritative snapshot.
static func for_actor(stable_id: String, visual_id: String, rank: int, art_box_value: Variant) -> Dictionary:
	return _create(stable_id, visual_id, rank, art_box_value, Vector2.INF)


## Visual binding for one static authored foreground piece (pillar, tower
## cell, ruin). Its authored world feet anchor never moves after binding.
static func for_static_piece(stable_id: String, visual_id: String, rank: int, art_box_value: Variant, feet_anchor: Variant) -> Dictionary:
	if not feet_anchor is Vector2 or not (feet_anchor as Vector2).is_finite():
		return {"ok": false, "error": "invalid_static_feet_anchor"}
	return _create(stable_id, visual_id, rank, art_box_value, feet_anchor)


static func _create(stable_id: String, visual_id: String, rank: int, art_box_value: Variant, static_feet: Vector2) -> Dictionary:
	if not _valid_id(stable_id) or not _valid_id(visual_id):
		return {"ok": false, "error": "invalid_presentation_binding_identity"}
	if not rank is int or int(rank) < 0:
		return {"ok": false, "error": "invalid_presentation_binding_rank"}
	if not art_box_value is Rect2:
		# A non-Rect2 value (footprint radius, collision payload, absent box)
		# is exactly the forbidden substitution; reject it by name.
		return {"ok": false, "error": "missing_presentation_art_box"}
	var box: Rect2 = art_box_value
	if not box.position.is_finite() or not box.size.is_finite() or box.size.x <= 0.0 or box.size.y <= 0.0:
		return {"ok": false, "error": "invalid_presentation_art_box"}
	var binding := RoomPresentationBinding.new()
	binding.stable_id = stable_id
	binding.visual_id = visual_id
	binding.rank = int(rank)
	binding.art_box = Rect2(box.position, box.size)
	binding.static_feet_anchor = static_feet
	return {"ok": true, "error": "", "value": binding}


func is_actor_binding() -> bool:
	return not static_feet_anchor.is_finite()


func is_static_piece_binding() -> bool:
	return static_feet_anchor.is_finite()


static func _valid_id(value: String) -> bool:
	return not value.is_empty() and value == value.strip_edges() and not value.contains(" ")
