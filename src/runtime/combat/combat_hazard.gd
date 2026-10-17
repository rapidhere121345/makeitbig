class_name CombatHazard
extends RefCounted

## Typed room hazard record.
##
## A hazard owns its authored shape, cycle, active window and per-cycle
## suppression. It never applies damage itself; it asks the room port to stage
## a typed player contact for the fixed DAMAGE_STATUS phase.

const CombatQueryScript := preload("res://src/runtime/geometry/combat_query.gd")

const WARNING_TICKS: int = 30
const ACTIVE_TICKS: int = 15
const CYCLE_TICKS: int = 90

var hazard_id := ""
var phase := "warning"
var cycle := 0
var cycle_tick := 0
var last_hit_cycle := -1
var origin := Vector2.ZERO
var direction := Vector2.ZERO
var length := 0.0
var width := 0.0
var radius := 0.0

var _view: Dictionary = {}


func configure(id: String, center: Vector2) -> Dictionary:
	if id not in ["exposed_ground_zone", "moving_fireline"]:
		return {"ok": false, "error": "unknown_hazard_id"}
	if not center.is_finite():
		return {"ok": false, "error": "invalid_hazard_origin"}
	hazard_id = id
	phase = "warning"
	cycle = 0
	cycle_tick = 0
	last_hit_cycle = -1
	if id == "moving_fireline":
		origin = center
		direction = Vector2.DOWN
		length = 0.0
		width = 34.0
		radius = 0.0
	else:
		origin = center + Vector2(70.0, 0.0)
		direction = Vector2.ZERO
		length = 0.0
		width = 0.0
		radius = 82.0
	_publish_view()
	return {"ok": true, "error": ""}


func import_view(state: Variant) -> Dictionary:
	if not state is Dictionary:
		return {"ok": false, "error": "invalid_hazard_view"}
	var value: Dictionary = state
	var id := String(value.get("id", hazard_id))
	if id != hazard_id:
		return {"ok": false, "error": "hazard_id_changed"}
	var candidate_origin: Variant = value.get("origin", origin)
	var candidate_direction: Variant = value.get("direction", direction)
	if not candidate_origin is Vector2 or not (candidate_origin as Vector2).is_finite():
		return {"ok": false, "error": "invalid_hazard_origin"}
	if not candidate_direction is Vector2 or not (candidate_direction as Vector2).is_finite():
		return {"ok": false, "error": "invalid_hazard_direction"}
	origin = candidate_origin
	direction = candidate_direction
	length = maxf(0.0, float(value.get("length", length)))
	width = maxf(0.0, float(value.get("width", width)))
	radius = maxf(0.0, float(value.get("radius", radius)))
	last_hit_cycle = int(value.get("last_hit_cycle", last_hit_cycle))
	return {"ok": true, "error": ""}


func advance(at_tick: int, arena_rect: Rect2, room_port: EncounterRoomPort) -> Dictionary:
	if at_tick < 0 or not arena_rect.position.is_finite() or not arena_rect.size.is_finite() or arena_rect.size.x <= 0.0 or arena_rect.size.y <= 0.0:
		return {"ok": false, "error": "invalid_hazard_tick_or_bounds"}
	cycle = at_tick / CYCLE_TICKS
	cycle_tick = at_tick % CYCLE_TICKS
	phase = "warning" if cycle_tick < WARNING_TICKS else ("active" if cycle_tick < WARNING_TICKS + ACTIVE_TICKS else "recovery")
	if hazard_id == "moving_fireline":
		var progress := float(cycle_tick) / float(CYCLE_TICKS - 1)
		var candidate := Vector2(lerpf(arena_rect.position.x, arena_rect.end.x, progress), arena_rect.position.y)
		if not candidate.is_finite():
			return {"ok": false, "error": "invalid_hazard_position"}
		var quantized := room_port.quantize_position(candidate) if room_port != null else Vector2(INF, INF)
		if not quantized.is_finite():
			return {"ok": false, "error": "hazard_quantization_rejected"}
		origin = quantized
		length = arena_rect.size.y
	_publish_view()
	return {"ok": true, "error": ""}


func contains(point: Vector2) -> bool:
	if not point.is_finite() or phase != "active":
		return false
	if hazard_id == "moving_fireline":
		return CombatQueryScript.lane_contains(point, origin, direction, length, width)
	return point.distance_to(origin) <= radius


func queue_player_contact(at_tick: int, player_position: Vector2, room_port: EncounterRoomPort) -> Dictionary:
	if room_port == null:
		return {"ok": false, "error": "hazard_room_port_unavailable"}
	if phase != "active" or cycle == last_hit_cycle or not contains(player_position):
		return {"ok": true, "queued": false, "reason": "hazard_not_contacting"}
	var amount := 9.0 if hazard_id == "moving_fireline" else 7.0
	var source_id := "hazard/%s" % hazard_id
	var queued := room_port.queue_player_hazard_hit(at_tick, amount, source_id, origin)
	if not bool(queued.get("ok", false)):
		return {"ok": false, "error": String(queued.get("error", "hazard_contact_rejected"))}
	last_hit_cycle = cycle
	_publish_view()
	return {"ok": true, "queued": true, "source_id": source_id, "source_position": origin, "contact_point": player_position, "tick": at_tick}


func snapshot() -> Dictionary:
	_publish_view()
	return _view


func mutable_view() -> Dictionary:
	if _view.is_empty():
		_publish_view()
	return _view


func sync_external_view() -> Dictionary:
	## The returned view is intentionally detached from simulation callers, but
	## test/debug composition roots may edit it before the next tick. Import
	## only that explicit boundary; production never mutates the view.
	return import_view(_view)


func _publish_view() -> void:
	_view["id"] = hazard_id
	_view["phase"] = phase
	_view["cycle"] = cycle
	_view["cycle_tick"] = cycle_tick
	_view["last_hit_cycle"] = last_hit_cycle
	_view["origin"] = origin
	_view["direction"] = direction
	_view["length"] = length
	_view["width"] = width
	_view["radius"] = radius
