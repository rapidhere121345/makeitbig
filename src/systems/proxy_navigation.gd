extends RefCounted

## Static, footprint-aware routing for the proxy. The grid is only a planning
## aid; the actor motor remains the authority for every movement.
const ArenaGeometry := preload("res://src/core/geometry/arena_geometry.gd")
const Sweep := preload("res://src/core/geometry/spatial_sweep.gd")
const STEP := 24.0
const CLEARANCE := 15.0

static var _cached_geometry: Dictionary = {}
static var _cached_blockers: Array = []
static var _grid: AStarGrid2D
static var _origin := Vector2.ZERO


## Retreat needs a clear local step, not a route to a possibly blocked goal.
## Stable angular order chooses a side without introducing per-tick randomness.
static func retreat_direction(start: Vector2, away: Vector2, geometry: Dictionary, blockers: Array, stable_sign: int) -> Vector2:
	for candidate: Vector2 in ArenaGeometry.candidate_directions(away, stable_sign):
		if _clear_segment(start, start + candidate * STEP, geometry, blockers):
			return candidate
	return Vector2.ZERO


static func direction(start: Vector2, goal: Vector2, geometry: Dictionary, blockers: Array) -> Vector2:
	if _clear_segment(start, goal, geometry, blockers):
		return (goal - start).normalized()
	_ensure_grid(geometry, blockers)
	var start_id := _nearest_connected_cell(start, geometry, blockers)
	var goal_id := _nearest_connected_cell(goal, geometry, blockers)
	if start_id == Vector2i(-1, -1) or goal_id == Vector2i(-1, -1):
		return Vector2.ZERO
	var path := _grid.get_id_path(start_id, goal_id)
	if path.is_empty():
		return Vector2.ZERO
	var next := _grid.get_point_position(path[0])
	for id: Vector2i in path:
		var candidate := _grid.get_point_position(id)
		if not _clear_segment(start, candidate, geometry, blockers):
			break
		next = candidate
	if start.distance_squared_to(next) < 0.01:
		return Vector2.ZERO
	return (next - start).normalized()


static func _ensure_grid(geometry: Dictionary, blockers: Array) -> void:
	if _grid != null and _cached_geometry == geometry and _cached_blockers == blockers:
		return
	_cached_geometry = geometry.duplicate(true)
	_cached_blockers = blockers.duplicate(true)
	var bounds: Rect2 = geometry.bounds
	_origin = bounds.position
	_grid = AStarGrid2D.new()
	_grid.region = Rect2i(0, 0, ceili(bounds.size.x / STEP) + 1, ceili(bounds.size.y / STEP) + 1)
	_grid.cell_size = Vector2(STEP, STEP)
	_grid.offset = _origin
	_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_grid.update()
	for y: int in _grid.region.size.y:
		for x: int in _grid.region.size.x:
			var id := Vector2i(x, y)
			var point := _grid.get_point_position(id)
			if not _clear_segment(point, point, geometry, blockers):
				_grid.set_point_solid(id)


static func _nearest_connected_cell(point: Vector2, geometry: Dictionary, blockers: Array) -> Vector2i:
	var base := Vector2i(roundi((point.x - _origin.x) / STEP), roundi((point.y - _origin.y) / STEP))
	var best := Vector2i(-1, -1)
	var best_distance := INF
	for y: int in range(-2, 3):
		for x: int in range(-2, 3):
			var id := base + Vector2i(x, y)
			if not _grid.is_in_boundsv(id) or _grid.is_point_solid(id):
				continue
			var candidate := _grid.get_point_position(id)
			var distance := point.distance_squared_to(candidate)
			if distance < best_distance and _clear_segment(point, candidate, geometry, blockers):
				best = id
				best_distance = distance
	return best


static func _clear_segment(start: Vector2, end: Vector2, geometry: Dictionary, blockers: Array) -> bool:
	var line := ArenaGeometry.line_segment_walkable(start, end, geometry)
	if not bool(line.get("walkable", false)):
		return false
	for blocker: Dictionary in blockers:
		if blocker.has("points"):
			for hit: Dictionary in Sweep.sweep_circle_polygon(start, end - start, CLEARANCE, blocker.points):
				if not _separating_initial_hit(hit, end - start):
					return false
		else:
			var hit := Sweep.sweep_circle_circle(start, end - start, CLEARANCE, blocker.center, blocker.radius, "circle", false)
			if not hit.is_empty() and not _separating_initial_hit(hit, end - start):
				return false
	return true


## The planning margin can include a legal actor touching a surface. Permit a
## sweep that moves away from that initial contact so it can leave the margin.
static func _separating_initial_hit(hit: Dictionary, motion: Vector2) -> bool:
	return bool(hit.get("initial", false)) and motion.dot(Vector2(hit.get("normal", Vector2.ZERO))) > 0.0001
