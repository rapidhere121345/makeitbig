class_name BossArrowFlight
extends RefCounted

## Production flight driver for multipart Boss piercing arrows.
##
## The driver advances the legacy projectile mirror, freezes its BigValue damage
## intent once, and submits one typed BossAttackQuery per fixed tick. The room
## kernel executes the query in CONTINUOUS_QUERIES; BossCombatDomain resolves
## its typed HitBuffer in DAMAGE_STATUS. This class never mutates Boss health.

const RoomSpatialPortScript := preload("res://src/runtime/world/room_spatial_port.gd")
const CombatSystemRoomPortScript := preload("res://src/runtime/combat/combat_system_room_port.gd")
const Channels := preload("res://src/runtime/spatial/spatial_channels.gd")
const QueryScript := preload("res://src/runtime/combat/boss_attack_query.gd")
const DamageValueScript := preload("res://src/runtime/combat/boss_damage_value.gd")
const CoreResult := preload("res://src/core/result.gd")

const TICK_RATE := 30
const SIM_STEP_SECONDS := 1.0 / float(TICK_RATE)

var spatial_port: RoomSpatialPort = null
var submitted_queries := 0
var last_submitted_attack_ids: Array[String] = []
var last_queue_rejections: Array[Dictionary] = []

var _pending: Array = []
var _arrow_damage: Dictionary = {}


class FlightRecord:
	extends RefCounted

	var attack_key := ""
	var target_key := ""
	var aggregate: BigValue = null
	var ordinary_total := 0.0
	var projectile = null
	var query_ok := false
	var query_start := Vector2.ZERO
	var query_displacement := Vector2.ZERO
	var health_before: BigValue = null

	func snapshot() -> Dictionary:
		return {
			"attack_instance_id": attack_key,
			"target_key": target_key,
			"ordinary_total": ordinary_total,
			"query_ok": query_ok,
			"query_start": query_start,
			"query_displacement": query_displacement,
		}


func configure(port: Variant) -> Dictionary:
	if port == null or not port.has_method("queue_boss_path_query") or not port.has_method("take_boss_path_results"):
		return CoreResult.failure("boss_flight_spatial_port_unavailable")
	spatial_port = port
	reset()
	return {"ok": true, "error": ""}


func is_configured() -> bool:
	return spatial_port != null


func reset() -> void:
	submitted_queries = 0
	last_submitted_attack_ids.clear()
	last_queue_rejections.clear()
	_pending.clear()
	_arrow_damage.clear()


func forget_arrow(attack_key: String) -> void:
	_arrow_damage.erase(attack_key)


func submit_tick(
	projectiles: Array,
	source_handle,
	current_tick: int,
	flight_port: CombatSystemRoomPort
) -> Dictionary:
	if not is_configured() or flight_port == null:
		return CoreResult.failure("boss_flight_not_configured")
	last_submitted_attack_ids.clear()
	last_queue_rejections.clear()
	if source_handle == null:
		return {"ok": true, "error": "", "submitted": 0}
	var submitted := 0
	for projectile in projectiles:
		if projectile == null:
			continue
		if not flight_port.is_boss_kernel_projectile(projectile):
			continue
		var attack_key := "arrow/%d" % int(projectile.action_instance_id)
		if int(projectile.spawned_tick) >= current_tick:
			projectile.previous_position = projectile.position
			continue
		var target: Variant = flight_port.sync_boss_kernel_target(projectile)
		var target_key := ""
		var health_before: BigValue = null
		if target != null and String(target.target_key) != "":
			target_key = String(target.target_key)
			health_before = target.health.duplicate_value()
		else:
			last_queue_rejections.append({
				"attack_instance_id": attack_key,
				"error": "boss_target_unresolved",
			})
			continue
		var frozen: Dictionary = _frozen_damage(attack_key, projectile, flight_port)
		var damage := DamageValueScript.from_big(frozen["aggregate"])
		var remaining_range := maxf(0.0, projectile.maximum_range - projectile.distance_travelled)
		var step := minf(projectile.speed * SIM_STEP_SECONDS, remaining_range)
		projectile.previous_position = projectile.position
		projectile.distance_travelled = minf(projectile.maximum_range, projectile.distance_travelled + step)
		projectile.position = projectile.origin + projectile.direction * projectile.distance_travelled
		var path_start: Vector2 = projectile.previous_position
		var path_displacement: Vector2 = projectile.position - projectile.previous_position
		var query := QueryScript.make(
			source_handle,
			target_key,
			Channels.PROJECTILE,
			path_start,
			path_displacement,
			0.0,
			true,
			attack_key,
			damage
		)
		var queued: Dictionary = spatial_port.queue_boss_path_query(query)
		var record := FlightRecord.new()
		record.attack_key = attack_key
		record.target_key = target_key
		record.aggregate = frozen["aggregate"]
		record.ordinary_total = float(frozen["ordinary"])
		record.projectile = projectile
		record.query_ok = bool(queued.get("ok", false))
		record.query_start = path_start
		record.query_displacement = path_displacement
		record.health_before = health_before
		_pending.append(record)
		if record.query_ok:
			submitted += 1
			submitted_queries += 1
			last_submitted_attack_ids.append(attack_key)
		else:
			last_queue_rejections.append({
				"attack_instance_id": attack_key,
				"error": String(queued.get("error", "boss_path_query_rejected")),
			})
	return {"ok": true, "error": "", "submitted": submitted}


func pending_records() -> Array:
	return _pending.duplicate()


func clear_pending() -> void:
	_pending.clear()


func _frozen_damage(attack_key: String, projectile, flight_port: CombatSystemRoomPort) -> Dictionary:
	if _arrow_damage.has(attack_key):
		return _arrow_damage[attack_key]
	var retained_ordinary := 0.0
	var aggregate: BigValue = projectile.aggregate_damage
	var retained: Variant = flight_port.take_retained_arrow()
	if retained is Dictionary:
		var aggregate_value: Variant = (retained as Dictionary).get("aggregate", null)
		var ordinary_value: Variant = (retained as Dictionary).get("ordinary", 0.0)
		if aggregate_value is BigValue and (typeof(ordinary_value) in [TYPE_INT, TYPE_FLOAT]) and not ordinary_value is bool:
			retained_ordinary = float(ordinary_value)
			aggregate = projectile.aggregate_damage.add(aggregate_value)
	var frozen := {
		"aggregate": aggregate,
		"ordinary": maxf(0.0, float(projectile.ordinary_damage) + retained_ordinary),
	}
	_arrow_damage[attack_key] = frozen
	return frozen
