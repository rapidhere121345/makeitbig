class_name RangerArrowFlight
extends RefCounted

## Production flight driver for ranger piercing arrows on the fixed-tick
## kernel.
##
## Each tick the mounted room submits exactly one typed PathQuery per
## in-flight kernel-managed projectile. The kernel's CONTINUOUS_QUERIES phase
## resolves the sweep against the room's static and dynamic spatial indexes,
## writes SimHit records into the tick's HitBuffer, and DamageResolution (via
## RoomCombatPort) is the only place the hit becomes damage. This driver owns
## flight state and the frozen per-arrow damage intent; it never computes
## damage outcomes and never mutates target health.
##
## Legacy parity contracts kept here:
##   - an arrow only connects with its locked target (the room's hit
##     admission gate enforces it at the damage boundary), so the query is
##     piercing and passes through other hurtboxes without stopping;
##   - the release tick holds the arrow on the authored bow socket;
##   - damage is frozen once per arrow at its first flight tick, including
##     any retained payload taken from the player rules at that moment;
##   - the connection geometry equals the legacy manual-aim body circle
##     exactly: a 34px circle anchored 22px above the target's feet. The
##     query path is translated onto that anchor band (down 22px from the
##     flight line, which leaves the bow socket near the anchor height) and
##     padded 18px over the registered 16px feet hurtbox. The authoritative
##     contact point still comes from the real frozen flight path.

const RoomSpatialPortScript := preload("res://src/runtime/world/room_spatial_port.gd")
const RoomCombatPortScript := preload("res://src/runtime/world/room_combat_port.gd")
const CombatSystemRoomPortScript := preload("res://src/runtime/combat/combat_system_room_port.gd")
const Channels := preload("res://src/runtime/spatial/spatial_channels.gd")

const TICK_RATE := 30
const SIM_STEP_SECONDS := 1.0 / float(TICK_RATE)
const LEGACY_AIM_CIRCLE_RADIUS := 34.0
const LEGACY_ANCHOR_OFFSET := Vector2(0.0, -22.0)
const ENEMY_HURTBOX_RADIUS := 16.0
const QUERY_REACH := LEGACY_AIM_CIRCLE_RADIUS - ENEMY_HURTBOX_RADIUS

var spatial_port: RoomSpatialPort = null
## Evidence counters: how many typed path queries production actually queued
## through RoomSpatialPort.queue_path_query, and which attacks were submitted.
var submitted_queries := 0
var last_submitted_attack_ids: Array[String] = []
var last_queue_rejections: Array[Dictionary] = []

var _pending: Array = []
var _arrow_damage: Dictionary = {}


class FlightRecord:
	extends RefCounted

	var attack_key := ""
	var milli_amount := 0
	var aggregate: BigValue = null
	var ordinary_total := 0.0
	var projectile = null
	var query_ok := false
	var query_start := Vector2.ZERO
	var query_displacement := Vector2.ZERO

	func snapshot() -> Dictionary:
		return {
			"attack_instance_id": attack_key,
			"milli_amount": milli_amount,
			"ordinary_total": ordinary_total,
			"query_ok": query_ok,
			"query_start": query_start,
			"query_displacement": query_displacement,
		}


func configure(port: Variant) -> Dictionary:
	if port == null or not port.has_method("queue_path_query") or not port.has_method("take_path_results"):
		return _failure("ranger_flight_spatial_port_unavailable")
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


## Advances every kernel-managed projectile by one tick and queues its typed
## path query. The room port owns target selection, retained payload and
## mirror synchronization; no callback bag crosses this production boundary.
func submit_tick(
	projectiles: Array,
	source_handle,
	current_tick: int,
	flight_port: CombatSystemRoomPort
) -> Dictionary:
	if not is_configured() or flight_port == null:
		return _failure("ranger_flight_not_configured")
	last_submitted_attack_ids.clear()
	last_queue_rejections.clear()
	if source_handle == null:
		return {"ok": true, "error": "", "submitted": 0}
	var submitted := 0
	for projectile in projectiles:
		if projectile == null:
			continue
		if not flight_port.is_normal_kernel_projectile(projectile):
			continue
		var attack_key := "arrow/%d" % int(projectile.action_instance_id)
		if int(projectile.spawned_tick) >= current_tick:
			# The release tick presents the arrow on the authored socket; the
			# first sweep begins on the following fixed tick.
			projectile.previous_position = projectile.position
			continue
		var frozen: Dictionary = _frozen_damage(attack_key, projectile, flight_port)
		flight_port.sync_kernel_target_record(projectile)
		var remaining_range := maxf(0.0, projectile.maximum_range - projectile.distance_travelled)
		var step := minf(projectile.speed * SIM_STEP_SECONDS, remaining_range)
		projectile.previous_position = projectile.position
		projectile.distance_travelled = minf(projectile.maximum_range, projectile.distance_travelled + step)
		projectile.position = projectile.origin + projectile.direction * projectile.distance_travelled
		var path_start: Vector2 = projectile.previous_position
		var path_displacement: Vector2 = projectile.position - projectile.previous_position
		var query := RoomSpatialPortScript.PathQuery.make(
			source_handle,
			Channels.PROJECTILE,
			path_start - LEGACY_ANCHOR_OFFSET,
			path_displacement,
			QUERY_REACH,
			int(frozen["milli"]),
			RoomCombatPortScript.MILLI_DAMAGE_CONTACT_KINDS[0],
			true,
			attack_key,
			"body",
			"body",
			"physical"
		)
		var queued: Dictionary = spatial_port.queue_path_query(query)
		var record := FlightRecord.new()
		record.attack_key = attack_key
		record.milli_amount = int(frozen["milli"])
		record.aggregate = frozen["aggregate"]
		record.ordinary_total = float(frozen["ordinary"])
		record.projectile = projectile
		record.query_ok = bool(queued.get("ok", false))
		record.query_start = path_start
		record.query_displacement = path_displacement
		_pending.append(record)
		if record.query_ok:
			submitted += 1
			submitted_queries += 1
			last_submitted_attack_ids.append(attack_key)
		else:
			last_queue_rejections.append({
				"attack_instance_id": attack_key,
				"errors": (queued.get("errors", []) as Array).duplicate(),
			})
	return {"ok": true, "error": "", "submitted": submitted}


## PathQuery results are published in submission order; the reconcile
## boundary zips them with these records one-to-one.
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
	var ordinary_total := maxf(0.0, float(projectile.ordinary_damage) + retained_ordinary)
	var frozen := {
		"milli": maxi(1, roundi(ordinary_total * 1000.0)),
		"aggregate": aggregate,
		"ordinary": ordinary_total,
	}
	_arrow_damage[attack_key] = frozen
	return frozen


static func _failure(error: String) -> Dictionary:
	return {"ok": false, "error": error}
