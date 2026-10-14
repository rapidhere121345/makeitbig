class_name TownRuntime
extends RefCounted

## Town gameplay consumes the room's one clock and one actor registry. No
## presentation node owns a second position, route cursor, or movement clock.
signal state_changed(snapshot: Dictionary)

const HERO_ID := "town/ranger"
const HERO_SPEED := 96.0
const FACILITY_IDS: Array[String] = ["contract", "loadout", "forge", "training", "proxy"]
const WAYPOINT_REACH := 12.0

var simulation
var registry
var _content: Dictionary = {}
var _input_direction := Vector2.ZERO
var _destination := "contract"
var _route_segment := 0
var _ready := false


func configure(world: Variant, actors: Variant, content: Dictionary) -> Dictionary:
	if world == null or actors == null or world.room_instance_id != actors.room_instance_id or world.world_revision != actors.world_revision:
		return _failure("town_dependencies_mismatch")
	if actors.actor(HERO_ID) == null or not actors.has_movement_boundary():
		return _failure("town_actor_or_boundary_missing")
	simulation = world
	registry = actors
	_content = content.duplicate(true)
	_input_direction = Vector2.ZERO
	_destination = "contract"
	_route_segment = 0
	_ready = true
	_update_route_progress()
	return {"ok": true, "error": ""}


func close() -> void:
	_ready = false
	_input_direction = Vector2.ZERO


func is_ready() -> bool:
	return _ready and simulation != null and registry != null and registry.actor(HERO_ID) != null


func submit_move(direction: Vector2) -> Dictionary:
	if not is_ready() or not direction.is_finite():
		return _failure("town_not_ready_or_invalid_intent")
	_input_direction = direction.limit_length(1.0) if not direction.is_zero_approx() else Vector2.ZERO
	return {"ok": true, "error": ""}


func advance_frame(display_delta: float) -> Dictionary:
	if not is_ready():
		return _failure("town_not_ready")
	var count: int = simulation.ticks_for_frame(display_delta)
	for index: int in count:
		var result := step_tick()
		if not bool(result.get("ok", false)):
			return result
	return {"ok": true, "error": "", "ticks": count, "tick": simulation.tick}


func step_tick() -> Dictionary:
	if not is_ready():
		return _failure("town_not_ready")
	var queued: Dictionary = simulation.queue_command({"kind": "town_move", "entity_id": HERO_ID, "direction": _input_direction})
	if not bool(queued.get("ok", false)):
		return queued
	var committed: Dictionary = simulation.step()
	var direction := Vector2.ZERO
	for command: Dictionary in committed.commands:
		if String(command.get("kind", "")) == "town_move" and String(command.get("entity_id", "")) == HERO_ID:
			direction = command.get("direction", Vector2.ZERO)
	var displacement := direction * HERO_SPEED / float(simulation.tick_rate)
	var moved: Dictionary = registry.move_actor(HERO_ID, displacement, int(committed.tick))
	if not bool(moved.get("ok", false)):
		return moved
	_update_route_progress()
	state_changed.emit(snapshot())
	return moved


func hero_world_position() -> Vector2:
	return registry.actor(HERO_ID).feet_position if is_ready() else Vector2.ZERO


func hero_facing() -> String:
	if not is_ready():
		return "south"
	var facing: Vector2 = registry.actor(HERO_ID).facing
	if absf(facing.x) > absf(facing.y):
		return "east" if facing.x > 0.0 else "west"
	return "south" if facing.y >= 0.0 else "north"


func hero_position_is_clear(point: Vector2) -> bool:
	return is_ready() and registry.is_position_clear(point, Rect2(), registry.actor(HERO_ID).footprint_radius)


func place_hero(point: Vector2) -> Dictionary:
	if not hero_position_is_clear(point):
		return _failure("town_placement_blocked")
	var result: Dictionary = registry.teleport_actor(HERO_ID, point)
	if bool(result.get("ok", false)):
		_input_direction = Vector2.ZERO
		_update_route_progress()
		state_changed.emit(snapshot())
	return result


func world_size() -> Vector2:
	var pair: Array = _content.get("world_size", [1536, 960])
	return Vector2(float(pair[0]), float(pair[1]))


func world_bounds() -> Rect2:
	var boundary: Dictionary = registry.movement_boundary_snapshot() if is_ready() else {}
	return (boundary.get("rect", Rect2()) as Rect2).grow(-float(registry.actor(HERO_ID).footprint_radius)) if is_ready() else Rect2()


func feature_entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for source: Dictionary in _content.get("facilities", []):
		var entry := source.duplicate(true)
		entry["feet"] = _point(source.get("position", []))
		entry["from_layout"] = true
		result.append(entry)
	return result


func entry_for(id: String) -> Dictionary:
	for entry: Dictionary in feature_entries():
		if String(entry.id) == id:
			return entry
	return {}


func nearby_feature_id() -> String:
	var nearest := ""
	var distance := INF
	for entry: Dictionary in feature_entries():
		var gap := hero_world_position().distance_squared_to(entry.feet)
		if gap <= pow(float(entry.radius), 2.0) and gap < distance:
			nearest = String(entry.id)
			distance = gap
	return nearest


func resident_positions() -> Dictionary:
	var result := {}
	if not is_ready():
		return result
	for resident: Dictionary in _content.get("residents", []):
		var id := String(resident.id)
		var actor: Variant = registry.actor("town/npc/" + id)
		if actor != null:
			result[id] = actor.feet_position
	return result


func route_points(id: String) -> Array[Vector2]:
	var points: Array[Vector2] = []
	for pair: Array in (_content.get("routes", {}) as Dictionary).get(id, []):
		points.append(_point(pair))
	return points


func destination_id() -> String:
	return _destination


func select_destination(id: String) -> void:
	var selected := id if not entry_for(id).is_empty() else ""
	if selected != _destination:
		_route_segment = 0
	_destination = selected
	_update_route_progress()
	state_changed.emit(snapshot())


func _update_route_progress() -> void:
	var points := route_points(_destination)
	if points.size() < 2:
		_route_segment = 0
		return
	_route_segment = clampi(_route_segment, 0, points.size() - 2)
	var best := INF
	var nearest := 0
	for index: int in points.size() - 1:
		var point := Geometry2D.get_closest_point_to_segment(hero_world_position(), points[index], points[index + 1])
		var distance := hero_world_position().distance_squared_to(point)
		if distance < best - 0.0001 or (is_equal_approx(distance, best) and index > nearest):
			best = distance
			nearest = index
	_route_segment = maxi(_route_segment, nearest)
	while _route_segment < points.size() - 2 and hero_world_position().distance_to(points[_route_segment + 1]) <= WAYPOINT_REACH:
		_route_segment += 1


func destination_guide() -> Dictionary:
	var entry := entry_for(_destination)
	if entry.is_empty():
		return {}
	var points := route_points(_destination)
	var guide: Vector2 = points[mini(_route_segment + 1, points.size() - 1)] if points.size() >= 2 else entry.feet
	return {"id": _destination, "guide": guide, "route_segment": _route_segment,
		"arrived": hero_world_position().distance_to(entry.feet) <= float(entry.radius), "direction": guide - hero_world_position()}


func travel_snapshot() -> Dictionary:
	return {"position": hero_world_position(), "facing": hero_facing(), "destination": _destination, "route_segment": _route_segment}


func restore_travel(travel: Dictionary) -> Dictionary:
	var point: Variant = travel.get("position", null)
	var facing := String(travel.get("facing", "south"))
	var destination := String(travel.get("destination", "contract"))
	if not point is Vector2 or not hero_position_is_clear(point) or facing not in ["south", "north", "east", "west"] or entry_for(destination).is_empty():
		return _failure("invalid_town_travel")
	registry.teleport_actor(HERO_ID, point)
	registry.actor(HERO_ID).facing = {"south": Vector2.DOWN, "north": Vector2.UP, "east": Vector2.RIGHT, "west": Vector2.LEFT}[facing]
	_input_direction = Vector2.ZERO
	_destination = destination
	_route_segment = maxi(0, int(travel.get("route_segment", 0)))
	_update_route_progress()
	state_changed.emit(snapshot())
	return {"ok": true, "error": ""}


func snapshot() -> Dictionary:
	return {"ready": is_ready(), "tick": int(simulation.tick) if simulation != null else 0,
		"tick_rate": int(simulation.tick_rate) if simulation != null else 30,
		"hero_position": hero_world_position(), "hero_facing": hero_facing(),
		"hero_moving": not registry.actor(HERO_ID).velocity.is_zero_approx() if is_ready() else false,
		"world_size": world_size(), "world_bounds": world_bounds(), "facilities": feature_entries(),
		"residents": resident_positions(), "resident_definitions": _content.get("residents", []).duplicate(true),
		"view_size": _point(_content.get("view_size", [640, 360])),
		"hero_screen_anchor": _point(_content.get("hero_screen_anchor", [320, 222])),
		"destination": destination_guide()}


static func _point(pair: Array) -> Vector2:
	return Vector2(float(pair[0]), float(pair[1])) if pair.size() == 2 else Vector2.ZERO


func _failure(error: String) -> Dictionary:
	return {"ok": false, "error": error}
