extends RefCounted
## Colossus part layout, per-part cutaway/fade queries and footprints extracted
## from ArenaWorldView. The colossus is four independently sorted authored cells
## (body, core, two hands); the view supplies the sprite metadata, hero cell and
## cutaway budget, so each method takes it as its first argument.

const SortRelation = preload("res://src/presentation/occlusion_query.gd")

const FORE_FADE: float = 0.45
const BOSS_CORE_OFFSET := Vector2(0.0, -38.0)
const BOSS_HAND_LEFT_OFFSET := Vector2(-68.0, -18.0)
const BOSS_HAND_RIGHT_OFFSET := Vector2(68.0, -18.0)


func boss_draw_parts(view, feet_world: Vector2, phase: int, left_hand_delta_gameplay: Vector2, right_hand_delta_gameplay: Vector2, pose_frame: Dictionary = {}) -> Array[Dictionary]:
	var phase_id := 2 if phase >= 2 else 1
	var left_anchor = feet_world + BOSS_HAND_LEFT_OFFSET + left_hand_delta_gameplay * view.GAMEPLAY_TO_WORLD
	var right_anchor = feet_world + BOSS_HAND_RIGHT_OFFSET + right_hand_delta_gameplay * view.GAMEPLAY_TO_WORLD
	# Body/core share the actor's ground baseline. Hand baselines follow the
	# gameplay pose; cosmetic lift/recoil changes the sprite, never its ground.
	return [
		{"part_id": "body", "sprite_id": "boss.body_phase%d" % phase_id, "sort_feet": feet_world, "feet": feet_world + Vector2(pose_frame.get("body_offset_px", Vector2i.ZERO)), "tint": Color.WHITE},
		{"part_id": "core", "sprite_id": "boss.core_phase%d" % phase_id, "sort_feet": feet_world, "feet": feet_world + BOSS_CORE_OFFSET + Vector2(pose_frame.get("core_offset_px", Vector2i.ZERO)), "tint": Color(pose_frame.get("core_tint", Color.WHITE))},
		{"part_id": "left_hand", "sprite_id": "boss.hand_left", "sort_feet": left_anchor, "feet": left_anchor + Vector2(pose_frame.get("left_hand_offset_px", Vector2i.ZERO)), "tint": Color.WHITE},
		{"part_id": "right_hand", "sprite_id": "boss.hand_right", "sort_feet": right_anchor, "feet": right_anchor + Vector2(pose_frame.get("right_hand_offset_px", Vector2i.ZERO)), "tint": Color.WHITE},
	]


## One independently sorted authored cell. The sort anchor, rather than the
## logical Boss's root, decides whether this part is in front of the player.
func draw_boss_part(view, canvas: CanvasItem, part: Dictionary, hero_world_point: Vector2, sort_rank: int = 3, stable_id: String = "enemy/boss/part") -> void:
	var feet: Vector2 = part.feet
	var anchor: Vector2 = part.sort_feet
	var visibility = view.sprite_occlusion_descriptor(String(part.sprite_id), feet)
	var box: Rect2 = visibility.get("art_box", Rect2())
	var cut = view.cutaway_for(box, anchor, hero_world_point, sort_rank, stable_id, visibility)
	## Boss parts use the same local window as ruins.  Keeping the rest of the
	## part opaque preserves its mass and silhouette while the player remains
	## readable at the actual overlap.
	var alpha := 1.0
	var tint: Color = part.get("tint", Color.WHITE)
	tint.a *= alpha
	view.draw_sprite(canvas, String(part.sprite_id), feet, false, tint, cut["window"] if cut["in_front"] else Rect2(), float(cut["local_alpha"]))


## Body, core and both hands in world units, in the order they are drawn.
func boss_parts_world(view, feet_world: Vector2) -> Array[Rect2]:
	var parts: Array[Rect2] = []
	for part: Dictionary in boss_draw_parts(view, feet_world, 2, Vector2.ZERO, Vector2.ZERO):
		var box = view.sprite_art_box(String(part.get("sprite_id", "")), part.get("feet", feet_world))
		if box.size.x > 0.0 and box.size.y > 0.0:
			parts.append(box)
	return parts


## 1.0 when the colossus cannot hide the hero, FORE_FADE when it is in front of
## and overlapping the hero's real cells.
func boss_fade_alpha(
	view,
	feet_world: Vector2,
	hero_world_point: Vector2,
	phase: int = 2,
	left_hand_delta_gameplay: Vector2 = Vector2.ZERO,
	right_hand_delta_gameplay: Vector2 = Vector2.ZERO,
	pose_frame: Dictionary = {}
) -> float:
	var hero_cell = view.hero_cell_world(hero_world_point)
	for part: Dictionary in boss_draw_parts(view, feet_world, phase, left_hand_delta_gameplay, right_hand_delta_gameplay, pose_frame):
		var part_id := String(part.get("part_id", "part"))
		var sort_feet: Vector2 = part.get("sort_feet", feet_world)
		var visibility = view.sprite_occlusion_descriptor(String(part.get("sprite_id", "")), part.get("feet", feet_world))
		var art_box: Rect2 = visibility.get("art_box", Rect2())
		var actor_sort := SortRelation.entry(sort_feet.y, 3, "enemy/boss/%s" % part_id)
		if SortRelation.is_front(actor_sort, view._hero_sort_entry(hero_world_point)) and view.visibility_intersects(visibility, hero_cell):
			return FORE_FADE
	return 1.0


## Colossus footprint in world units, used by the visibility checks so a boss
## head that leaves the frame or slips under the HUD can never pass as "fine".
func boss_body_rect_world(view, feet_world: Vector2) -> Rect2:
	return view.sprite_art_box("boss.body_phase2", feet_world)


func boss_hand_rect_world(view, feet_world: Vector2, left: bool) -> Rect2:
	var sprite_id := "boss.hand_left" if left else "boss.hand_right"
	var offset := BOSS_HAND_LEFT_OFFSET if left else BOSS_HAND_RIGHT_OFFSET
	return view.sprite_art_box(sprite_id, feet_world + offset)
