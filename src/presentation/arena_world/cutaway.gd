extends RefCounted
## Actor-over-actor cutaway planning extracted from ArenaWorldView: the shared
## window/opacity budget, the per-frame occluder list and the read-only
## occlusion report. The world view owns the hero cell, sprite metadata and the
## cell drawing, so methods that need them take the view as their first argument
## (explicit dependency, no back-reference, no reference cycle).

const SortRelation = preload("res://src/presentation/occlusion_query.gd")

## Conservative cutaway: a ruin, the tower or the colossus that really covers the
## hero keeps its authored alpha everywhere except the hero's own overlap window,
## where the stack is capped so the hero's real source pixels survive the 0.20
## per-channel visibility gate instead of being washed out by a whole-cell fade.
## The window is the hero cell grown by CUTAWAY_WINDOW_PAD, so no drawn hero
## pixel ever sits on the window edge. The window is a rectangle on the same
## integer grid the rest of the arena draws on.
const CUTAWAY_TOTAL_OPACITY: float = 0.16
const CUTAWAY_WINDOW_PAD: float = 2.0
## Index of the window inside the five tiling pieces (four solid bands first).
const CUTAWAY_WINDOW_INDEX: int = 4

## One actor-over-actor cutaway plan per hero position. Structures use their
## own whole-object paired reveal and do not consume this local actor budget.
var _cutaway_hero := Vector2(INF, INF)
var _cutaway_front: Array[Dictionary] = []
var _cutaway_window := Rect2()
var _cutaway_share := 1.0
var _actor_cutaway_ready := false
var _actor_occluders: Array[Dictionary] = []


func begin_frame() -> void:
	_cutaway_hero = Vector2(INF, INF)
	_actor_cutaway_ready = false
	_actor_occluders.clear()


static func cutaway_window(cell: Rect2) -> Rect2:
	## The hero cell plus its pad, kept on the integer pixel grid the arena draws
	## on so a cut cell always lands on whole source pixels.
	var grown := cell.grow(CUTAWAY_WINDOW_PAD)
	return Rect2(grown.position.round(), grown.size.round())


static func cutaway_alpha(count: int) -> float:
	## Even split of the local opacity budget: the source-over stack of any subset
	## of those cells never exceeds CUTAWAY_TOTAL_OPACITY, whatever the authored
	## fade already leaves on top of them.
	if count <= 0:
		return 1.0
	return clampf(1.0 - pow(1.0 - CUTAWAY_TOTAL_OPACITY, 1.0 / float(count)), 0.0, 1.0)


static func cutaway_pieces(quad: Rect2, core: Rect2) -> Array[Rect2]:
	## Four solid bands plus the window tile the drawn cell exactly once under
	## source-over blending, in the order they are drawn.
	var top := Rect2(quad.position, Vector2(quad.size.x, core.position.y - quad.position.y))
	var bottom := Rect2(Vector2(quad.position.x, core.end.y), Vector2(quad.size.x, quad.end.y - core.end.y))
	var left := Rect2(Vector2(quad.position.x, core.position.y), Vector2(core.position.x - quad.position.x, core.size.y))
	var right := Rect2(Vector2(core.end.x, core.position.y), Vector2(quad.end.x - core.end.x, core.size.y))
	return [top, bottom, left, right, core]


## Compatibility query for the actor cutaway budget. Structure transparency
## is reported separately by structure_fade_report().
func cutaway_front(_hero_world_point: Vector2) -> Array[Dictionary]:
	# Structures use whole upper-band transparency, never character cutouts.
	# This list is retained as a compatibility query for the actor-only budget.
	return []


func cutaway_for(view, art_box: Rect2, feet_world: Vector2, hero_world_point: Vector2, sort_rank: int = 1, stable_id: String = "actor", visibility: Variant = null) -> Dictionary:
	var cell = view.hero_cell_world(hero_world_point)
	var window := cutaway_window(cell)
	var actor_sort := SortRelation.entry(feet_world.y, sort_rank, stable_id)
	var overlaps = view.visibility_intersects(visibility, window) if visibility != null else art_box.intersects(window)
	if not SortRelation.is_front(actor_sort, view._hero_sort_entry(hero_world_point)) or not overlaps:
		return {"window": window, "local_alpha": 1.0, "in_front": false}
	## This budget covers only actor-over-actor drawing; structures fade separately.
	var share := float(_cutaway_plan(view, hero_world_point)["alpha"]) if _actor_cutaway_ready else cutaway_alpha(cutaway_front(hero_world_point).size() + 1)
	return {"window": window, "local_alpha": share, "in_front": true}


## The actor pass supplies every live front-facing actor cell before drawing.
## Normal enemies and Boss parts share one local opacity budget.
func prepare_actor_occlusion(view, cells: Array[Dictionary], hero_world_point: Vector2) -> void:
	_actor_occluders.clear()
	var window := cutaway_window(view.hero_cell_world(hero_world_point))
	var hero_sort = view._hero_sort_entry(hero_world_point)
	for cell: Dictionary in cells:
		var box: Rect2 = cell["art_box"]
		var visibility: Variant = cell.get("visibility", null)
		var stable_id := String(cell.get("stable_id", cell.get("id", "actor")))
		var sort_rank := int(cell.get("sort_rank", cell.get("rank", 1)))
		var baseline_y := float(cell.get("baseline_y", (cell.get("feet_world", Vector2.ZERO) as Vector2).y))
		var actor_sort := SortRelation.entry(baseline_y, sort_rank, stable_id)
		var overlaps = view.visibility_intersects(visibility, window) if visibility != null else box.intersects(window)
		if SortRelation.is_front(actor_sort, hero_sort) and overlaps:
			_actor_occluders.append(cell.duplicate())
	_actor_cutaway_ready = true
	_cutaway_hero = Vector2(INF, INF)


func _tower_upper_faded(view, hero_world_point: Vector2) -> bool:
	var feet = view.tower_feet_world()
	if not SortRelation.is_front(SortRelation.entry(feet.y, 0, "structure/tower"), view._hero_sort_entry(hero_world_point)):
		return false
	return view.paired_detection_rect_world("tower", feet).intersects(view.hero_cell_world(hero_world_point))


func _cutaway_plan(view, hero_world_point: Vector2) -> Dictionary:
	if _cutaway_hero != hero_world_point:
		_cutaway_hero = hero_world_point
		_cutaway_front = cutaway_front(hero_world_point)
		_cutaway_window = cutaway_window(view.hero_cell_world(hero_world_point))
		_cutaway_share = cutaway_alpha(_cutaway_front.size() + _actor_occluders.size())
	return {"window": _cutaway_window, "alpha": _cutaway_share, "front": _cutaway_front}


## The window and the share one placed cell of this frame's plan draws with. Empty
## means that cell keeps its authored alpha for this frame: a ruin that stands
## behind the hero is never cut, and only the instance that really sorts in front
## of it shares the window, even when the arena places the same ruin twice.
func _cutaway_for_cell(view, sprite_id: String, feet_world: Vector2, hero_world_point: Vector2) -> Dictionary:
	var plan := _cutaway_plan(view, hero_world_point)
	for entry: Dictionary in plan["front"] as Array:
		var entry_id := String(entry["id"])
		## The tower is one occluder published as tower.base and tower.upper, so a
		## band matches the occluder it belongs to.
		if not (entry_id == sprite_id or sprite_id.begins_with(entry_id + ".")):
			continue
		if not (entry["feet_world"] as Vector2).is_equal_approx(feet_world):
			continue
		return {"window": plan["window"], "alpha": plan["alpha"]}
	return {"window": Rect2(), "alpha": 1.0}


## The colossus is one occluder drawn as four sprites: when it really stands in
## front of the hero they all share a single split of the budget the ruins are not
## already using, so body, core and both hands can never stack opaquely.
func boss_cutaway(view, sprite_ids: Array, feet_list: Array, feet_world: Vector2, hero_world_point: Vector2, sort_feet_list: Array = []) -> Dictionary:
	var plan := _cutaway_plan(view, hero_world_point)
	var window: Rect2 = plan["window"]
	var overlapping := 0
	var hero_sort = view._hero_sort_entry(hero_world_point)
	var part_ids := ["body", "core", "left_hand", "right_hand"]
	for index: int in sprite_ids.size():
		var sort_feet: Vector2 = feet_world if index < 2 else feet_list[index]
		if index < sort_feet_list.size():
			sort_feet = sort_feet_list[index] as Vector2
		var sort_id := "enemy/boss/%s" % String(part_ids[index] if index < part_ids.size() else sprite_ids[index])
		var actor_sort := SortRelation.entry(sort_feet.y, 3, sort_id)
		var visibility = view.sprite_occlusion_descriptor(String(sprite_ids[index]), feet_list[index] as Vector2)
		if SortRelation.is_front(actor_sort, hero_sort) and view.visibility_intersects(visibility, window):
			overlapping += 1
	if overlapping <= 0:
		return {"window": Rect2(), "alpha": 1.0}
	if _actor_cutaway_ready:
		return {"window": window, "alpha": plan["alpha"]}
	return {"window": window, "alpha": cutaway_alpha((plan["front"] as Array).size() + overlapping)}


## Read-only cutaway diagnostic for the external visibility harness: how many
## foreground cells really cover the hero, the total local opacity they compose
## to, and the window itself. Nothing here writes or re-sorts the arena.
func occlusion_report(view, hero_world_point: Vector2) -> Dictionary:
	var cell = view.hero_cell_world(hero_world_point)
	var window := cutaway_window(cell)
	var front := cutaway_front(hero_world_point)
	var alpha := cutaway_alpha(front.size() + _actor_occluders.size())
	var entries: Array[Dictionary] = []
	var front_ids: Array[String] = []
	var opacity := 0.0
	for entry: Dictionary in front:
		var local := alpha * float(entry["base_alpha"])
		opacity = 1.0 - (1.0 - opacity) * (1.0 - local)
		front_ids.append(String(entry["id"]))
		entries.append({
			"id": String(entry["id"]),
			"sprite_id": String(entry["id"]),
			"node": String(entry["id"]),
			"feet_world": entry["feet_world"],
			"art_box": entry["art_box"],
			"local_alpha": local,
			"overlap": entry["overlap"],
		})
	for actor: Dictionary in _actor_occluders:
		var local := alpha * float(actor.get("base_alpha", 1.0))
		opacity = 1.0 - (1.0 - opacity) * (1.0 - local)
		var entry := actor.duplicate()
		entry["local_alpha"] = local
		entry["overlap"] = (entry["art_box"] as Rect2).intersection(window)
		entries.append(entry)
		front_ids.append(String(entry["id"]))

	return {
		"hero_world": hero_world_point,
		"hero_cell_world": cell,
		"window_world": window,
		"window_pad": CUTAWAY_WINDOW_PAD,
		"occluder_count": entries.size(),
		"local_alpha_each": alpha,
		"local_opacity_total": opacity,
		"occluders": entries,
		"front_ids": front_ids,
		"front_nodes": front_ids.duplicate(),
		"unchanged": entries.is_empty(),
		"primitive_fade": view.structure_fade_report(),
		"local_opacity_scope": "actor-over-actor cutaway only; structure bands reported separately",
	}


## Read-only geometry of one cell for this frame: what it is drawn as, where, from
## which source pixels and with which alpha. An empty list means the cell keeps its
## authored single-rectangle drawing.
func cutaway_geometry(view, sprite_id: String, feet_world: Vector2, hero_world_point: Vector2, base_alpha: float = 1.0) -> Array[Dictionary]:
	var metadata = view.sprite(sprite_id)
	if metadata.is_empty():
		return []
	var rect: Rect2 = metadata.get("rect", Rect2())
	var anchor: Vector2 = metadata.get("anchor", Vector2.ZERO)
	var region = view._region_of(metadata)
	var destination := Rect2((feet_world - anchor + (region.position - rect.position)).round(), region.size)
	var cut := _cutaway_for_cell(view, sprite_id, feet_world, hero_world_point)
	var core = view._cutaway_core(destination, cut["window"] as Rect2, float(cut["alpha"]))
	if core.size.x <= 0.0 or core.size.y <= 0.0:
		return []
	return view.cut_pieces(destination, region, core, base_alpha, float(cut["alpha"]))
