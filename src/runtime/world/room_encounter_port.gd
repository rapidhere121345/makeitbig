class_name RoomEncounterPort
extends SimEncounterPort

## Production bridge between a RoomEncounter domain and a mounted
## SceneRuntime. The encounter remains a detached domain: this port stamps
## its requests with the live room identity, hands them to a production spawn
## binding only after the kernel tick has committed, and returns typed
## spawned/failed/death receipts to the domain.

const SpawnRequestScript := preload("res://src/runtime/encounter/encounter_spawn_request.gd")
const SpawnResultScript := preload("res://src/runtime/encounter/encounter_spawn_result.gd")
const SpawnPortScript := preload("res://src/runtime/world/room_encounter_spawn_port.gd")
const TerminalObservationScript := preload("res://src/runtime/encounter/room_terminal_observation.gd")
const TerminalResultScript := preload("res://src/runtime/encounter/room_terminal_result.gd")
const CoreResult := preload("res://src/core/result.gd")

var encounter: Variant = null
var _room_instance_id := ""
var _world_revision := -1
var _spawn_binding: RoomEncounterSpawnPort = null
var _bound := false
var _shutdown := false
var _last_tick := -1

var _handle_to_entity: Dictionary = {}
var _spawn_key_to_binding: Dictionary = {}
var _entity_to_binding: Dictionary = {}
var _dead_entities: Dictionary = {}

var pending_spawn_requests: Array = []
var last_step: Dictionary = {}
var last_spawn_results: Array[Dictionary] = []
var spawned_notifications: Array[Dictionary] = []
var failed_spawn_notifications: Array[Dictionary] = []
## Death notifications received from the kernel's settlement phase, in tick
## order. Each live stable entity is admitted once; duplicate settlement is
## acknowledged idempotently without calling RoomEncounter a second time.
var received_death_notifications: Array[Dictionary] = []
var received_typed_death_notifications: Array[RefCounted] = []
var rejected_notifications: Array[Dictionary] = []
var last_terminal_result: RoomTerminalResult = null


func bind(domain: Variant, room_instance: String = "", revision: int = -1) -> Dictionary:
	if domain == null or not domain.has_method("step") or not domain.has_method("notify_death"):
		return CoreResult.failure("invalid_room_encounter_domain")
	encounter = domain
	_room_instance_id = room_instance.strip_edges()
	_world_revision = revision
	_bound = true
	_shutdown = false
	_last_tick = -1
	_handle_to_entity.clear()
	_spawn_key_to_binding.clear()
	_entity_to_binding.clear()
	_dead_entities.clear()
	pending_spawn_requests.clear()
	last_step = {}
	last_spawn_results.clear()
	spawned_notifications.clear()
	failed_spawn_notifications.clear()
	received_death_notifications.clear()
	received_typed_death_notifications.clear()
	rejected_notifications.clear()
	last_terminal_result = null
	return {"ok": true, "error": ""}


func bind_spawn_binding(binding: RoomEncounterSpawnPort) -> Dictionary:
	if binding == null:
		_spawn_binding = null
		return {"ok": true, "error": ""}
	if not binding is SpawnPortScript:
		return CoreResult.failure("invalid_encounter_spawn_binding")
	_spawn_binding = binding as RoomEncounterSpawnPort
	return {"ok": true, "error": ""}


func clear_spawn_binding() -> void:
	_spawn_binding = null


func configure_context(room_instance: String, revision: int) -> Dictionary:
	if not _bound or _shutdown:
		return CoreResult.failure("encounter_port_unavailable")
	if room_instance.strip_edges().is_empty() or revision < 0:
		return CoreResult.failure("invalid_room_context")
	_room_instance_id = room_instance.strip_edges()
	_world_revision = revision
	_last_tick = -1
	return {"ok": true, "error": ""}


func bind_entity(handle: SimEntityHandle, entity_key: String) -> void:
	if _shutdown or handle == null or not handle.is_valid() or entity_key.strip_edges().is_empty():
		return
	var normalized := entity_key.strip_edges()
	_handle_to_entity[handle] = normalized
	_entity_to_binding[normalized] = {
		"entity_key": normalized,
		"handle": handle,
		"stable_key": 0,
		"generation": handle.generation,
		"room_instance_id": _room_instance_id,
		"world_revision": _world_revision,
		"spawn_key": "",
	}


## Fail-closed identity probe for production reconciliation bindings: a
## kernel entity key counts as bound only after a typed spawn acknowledgement
## registered it through on_spawned().
func is_entity_bound(entity_key: String) -> bool:
	var normalized := entity_key.strip_edges()
	return not normalized.is_empty() and _entity_to_binding.has(normalized)


func produce_intents(ctx: SimTickContext) -> void:
	if not _accept_context(ctx):
		return
	_step_encounter(ctx.tick)


## Startup deployment window.  CombatRoomRuntime calls this once after the
## mounted Main has configured RoomActorAccess and started RoomEncounter.  It
## emits tick zero requests without advancing the kernel clock, then the
## normal fixed tick path owns every later request.
func prime_spawn_requests(tick: int) -> Array[Dictionary]:
	if not _accept_tick(tick) or encounter == null:
		return []
	if pending_spawn_requests.is_empty():
		_step_encounter(tick)
	return _request_snapshots(pending_spawn_requests)


func _step_encounter(tick: int) -> void:
	if encounter == null:
		return
	var result: Variant = encounter.step(tick)
	if result == null or not result.has_method("snapshot"):
		_reject(tick, "invalid_encounter_step_result")
		return
	_last_tick = maxi(_last_tick, tick)
	last_step = result.snapshot()
	if result.spawn_requests is Array:
		for request: Variant in result.spawn_requests:
			if not request is SpawnRequestScript:
				_reject(tick, "invalid_typed_spawn_request")
				continue
			request.room_instance_id = _room_instance_id
			request.world_revision = _world_revision
			pending_spawn_requests.append(request)
		last_step["spawn_requests"] = _request_snapshots(result.spawn_requests)
	if last_step.has("phase"):
		last_step["terminal"] = String(last_step.get("phase", "")) in ["victory", "defeat"]


## Materializes requests after SimulationWorld.step_tick() returns. The
## kernel's authoritative snapshot for that tick has already been published;
## actor registration therefore lands in the between-tick structural window and
## becomes visible to the next fixed tick's read view.
func materialize_spawn_requests(tick: int, binding: RoomEncounterSpawnPort = null) -> Array[Dictionary]:
	last_spawn_results.clear()
	if not _accept_tick(tick):
		return []
	var requests: Array = drain_spawn_requests()
	var active_binding: RoomEncounterSpawnPort = binding if binding != null else _spawn_binding
	for request: Variant in requests:
		if not request is SpawnRequestScript:
			_reject(tick, "invalid_typed_spawn_request")
			continue
		if not _request_matches_context(request):
			_reject(tick, "stale_spawn_request_context")
			continue
		var result: Variant = _invoke_spawn_port(active_binding, request, tick)
		var normalized: Variant = _normalize_spawn_result(result, request)
		if normalized.is_spawned():
			var ack: Dictionary = on_spawned(
				request.spawn_key,
				normalized.entity_key,
				tick,
				normalized.handle,
				normalized.stable_key,
				normalized.generation,
				normalized.room_instance_id,
				normalized.world_revision
			)
			if not bool(ack.get("ok", false)):
				normalized = SpawnResultScript.failed(request, String(ack.get("error", "spawn_ack_rejected")))
		elif normalized.is_failed():
			on_spawn_failed(request.spawn_key, tick, normalized.error)
		last_spawn_results.append(normalized.snapshot())
	return last_spawn_results.duplicate(true)


## Spawn materialization remains available as a deterministic drain for callers
## that own a separate binding. Production SceneRuntime uses
## materialize_spawn_requests() so every request gets an ack.
func drain_spawn_requests() -> Array:
	var result := pending_spawn_requests.duplicate()
	pending_spawn_requests.clear()
	return result


func on_spawned(
	spawn_key: String,
	entity_key: String,
	tick: int,
	handle: SimEntityHandle = null,
	stable_key: int = 0,
	generation: int = 0,
	room_instance: String = "",
	revision: int = -1
) -> Dictionary:
	if not _accept_event_context(tick, room_instance, revision):
		return CoreResult.failure("stale_spawn_ack_context")
	var normalized_entity := entity_key.strip_edges()
	if normalized_entity.is_empty() or stable_key < 1 or generation < 1:
		return CoreResult.failure("invalid_spawn_ack_identity")
	if handle != null:
		if not handle.is_valid() or handle.generation != generation:
			return CoreResult.failure("spawn_ack_generation_mismatch")
		if _handle_to_entity.has(handle) and String(_handle_to_entity[handle]) != normalized_entity:
			return CoreResult.failure("entity_handle_already_registered")
	if _entity_to_binding.has(normalized_entity):
		return CoreResult.failure("entity_key_already_registered")
	var domain_result: Variant = encounter.notify_spawned(spawn_key, normalized_entity, tick) if encounter != null and encounter.has_method("notify_spawned") else null
	if domain_result is Dictionary and not bool(domain_result.get("ok", false)):
		return domain_result
	var binding := {
		"spawn_key": spawn_key,
		"entity_key": normalized_entity,
		"handle": handle,
		"stable_key": stable_key,
		"generation": generation,
		"room_instance_id": _room_instance_id,
		"world_revision": _world_revision,
	}
	_spawn_key_to_binding[spawn_key] = binding
	_entity_to_binding[normalized_entity] = binding
	if handle != null:
		_handle_to_entity[handle] = normalized_entity
	spawned_notifications.append({
		"spawn_key": spawn_key,
		"entity_key": normalized_entity,
		"stable_key": stable_key,
		"generation": generation,
		"handle": handle.encode() if handle != null else "",
		"room_instance_id": _room_instance_id,
		"world_revision": _world_revision,
		"tick": tick,
	})
	_last_tick = maxi(_last_tick, tick)
	return {"ok": true, "error": "", "snapshot": snapshot()}


func on_spawn_failed(spawn_key: String, tick: int, reason: String, room_instance: String = "", revision: int = -1) -> Dictionary:
	if not _accept_event_context(tick, room_instance, revision):
		return CoreResult.failure("stale_spawn_failure_context")
	var normalized_reason := reason.strip_edges()
	if normalized_reason.is_empty():
		return CoreResult.failure("invalid_spawn_failure_reason")
	var domain_result: Variant = encounter.notify_spawn_failed(spawn_key, tick, normalized_reason) if encounter != null and encounter.has_method("notify_spawn_failed") else null
	if domain_result is Dictionary and not bool(domain_result.get("ok", false)):
		return domain_result
	failed_spawn_notifications.append({
		"spawn_key": spawn_key,
		"reason": normalized_reason,
		"room_instance_id": _room_instance_id,
		"world_revision": _world_revision,
		"tick": tick,
	})
	_last_tick = maxi(_last_tick, tick)
	return {"ok": true, "error": "", "snapshot": snapshot()}


func on_death(entity_view: SimEntityView, ctx: SimTickContext) -> void:
	if entity_view == null or not _accept_context(ctx):
		return
	if entity_view.room_instance_id != ctx.room_instance_id or entity_view.world_revision != ctx.world_revision:
		_reject(ctx.tick, "stale_death_entity_context")
		return
	var entity_key := String(_handle_to_entity.get(entity_view.handle, "actor/%d" % entity_view.stable_key))
	var binding: Dictionary = _entity_to_binding.get(entity_key, {})
	_record_death(entity_key, ctx.tick, String(binding.get("spawn_key", "")), ctx.room_instance_id, ctx.world_revision)


func on_death_settlement(notification: Variant, ctx: SimTickContext) -> void:
	if not _accept_context(ctx):
		return
	if notification == null or not notification is DeathSettlementNotificationScript or not bool(notification.is_valid()):
		_reject(ctx.tick, "invalid_death_notification")
		return
	var entity_key: String = String(notification.entity_key).strip_edges()
	var tick: int = int(notification.tick)
	var room_instance: String = String(notification.room_id).strip_edges()
	var revision: int = int(notification.world_revision)
	if entity_key.is_empty() or room_instance != ctx.room_instance_id or revision != ctx.world_revision:
		_reject(tick, "stale_death_notification_context")
		return
	var binding: Dictionary = _entity_to_binding.get(entity_key, {})
	var spawn_key: String = String(notification.spawn_key) if not String(notification.spawn_key).is_empty() else String(binding.get("spawn_key", ""))
	var result := _record_death(entity_key, tick, spawn_key, room_instance, revision)
	if bool(result.get("ok", false)) and bool(result.get("changed", false)):
		received_typed_death_notifications.append(notification)


## Typed terminal observation boundary.  Main may submit facts, but the
## detached RoomEncounter remains the only owner of victory/defeat phase.
func observe_terminal(observation: RoomTerminalObservation) -> RoomTerminalResult:
	if observation == null or not observation.is_valid():
		return _terminal_failure("invalid_terminal_observation")
	if _shutdown or not _bound or encounter == null:
		return _terminal_failure("encounter_port_unavailable")
	if observation.room_instance_id != _room_instance_id or observation.world_revision != _world_revision:
		_reject(observation.tick, "stale_terminal_observation_context")
		return _terminal_failure("stale_terminal_observation_context")
	if not _accept_tick(observation.tick):
		return _terminal_failure("stale_terminal_observation_tick")
	if not encounter.has_method("observe_terminal"):
		return _terminal_failure("terminal_authority_unavailable")
	var result: Variant = encounter.observe_terminal(observation)
	if result == null or not result is TerminalResultScript:
		_reject(observation.tick, "invalid_terminal_result")
		return _terminal_failure("invalid_terminal_result")
	last_terminal_result = result
	_last_tick = maxi(_last_tick, observation.tick)
	if not result.ok:
		_reject(observation.tick, result.error)
	return result


func shutdown() -> void:
	encounter = null
	_spawn_binding = null
	_room_instance_id = ""
	_world_revision = -1
	_bound = false
	_shutdown = true
	_last_tick = -1
	_handle_to_entity.clear()
	_spawn_key_to_binding.clear()
	_entity_to_binding.clear()
	_dead_entities.clear()
	pending_spawn_requests.clear()
	last_step = {}
	last_spawn_results.clear()
	spawned_notifications.clear()
	failed_spawn_notifications.clear()
	received_death_notifications.clear()
	received_typed_death_notifications.clear()
	rejected_notifications.clear()
	last_terminal_result = null


func snapshot() -> Dictionary:
	return {
		"room_instance_id": _room_instance_id,
		"world_revision": _world_revision,
		"bound": _bound and not _shutdown,
		"encounter": encounter.snapshot() if encounter != null and encounter.has_method("snapshot") else {},
		"last_step": last_step.duplicate(true),
		"pending_spawn_requests": _request_snapshots(pending_spawn_requests),
		"spawned_notifications": spawned_notifications.duplicate(true),
		"failed_spawn_notifications": failed_spawn_notifications.duplicate(true),
		"received_death_notifications": received_death_notifications.duplicate(true),
		"rejected_notifications": rejected_notifications.duplicate(true),
		"terminal_result": last_terminal_result.snapshot() if last_terminal_result != null else {},
		"terminal": _terminal_snapshot(),
	}


func _record_death(entity_key: String, tick: int, spawn_key: String, room_instance: String, revision: int) -> Dictionary:
	if tick < 0 or tick < _last_tick:
		_reject(tick, "stale_death_notification_tick")
		return CoreResult.failure("stale_death_notification_tick")
	if room_instance != _room_instance_id or revision != _world_revision:
		_reject(tick, "stale_death_notification_context")
		return CoreResult.failure("stale_death_notification_context")
	if not _entity_to_binding.has(entity_key):
		# A legacy actor may still exist in EncounterDirector while its wave has
		# not been adopted.  Such a death is a protocol violation, not an
		# implicit domain transition; preserve the rejection as typed telemetry.
		_reject(tick, "unknown_entity_key")
		return CoreResult.failure("unknown_entity_key")
	if _dead_entities.has(entity_key):
		return {"ok": true, "error": "", "changed": false, "duplicate": true}
	var domain_result: Variant = encounter.notify_death(entity_key, tick) if encounter != null else null
	if domain_result is Dictionary and not bool(domain_result.get("ok", false)):
		return domain_result
	var binding: Dictionary = _entity_to_binding.get(entity_key, {})
	_dead_entities[entity_key] = true
	received_death_notifications.append({
		"entity_key": entity_key,
		"spawn_key": spawn_key if not spawn_key.is_empty() else String(binding.get("spawn_key", "")),
		"stable_key": int(binding.get("stable_key", 0)),
		"generation": int(binding.get("generation", 0)),
		"room_instance_id": _room_instance_id,
		"world_revision": _world_revision,
		"tick": tick,
	})
	_last_tick = maxi(_last_tick, tick)
	return {"ok": true, "error": "", "changed": true}


func _accept_context(ctx: SimTickContext) -> bool:
	if ctx == null or _shutdown or not _bound:
		return false
	if _room_instance_id.is_empty():
		_room_instance_id = ctx.room_instance_id
	if _world_revision < 0:
		_world_revision = ctx.world_revision
	if ctx.room_instance_id != _room_instance_id or ctx.world_revision != _world_revision:
		_reject(ctx.tick, "stale_room_context")
		return false
	return _accept_tick(ctx.tick)


func _accept_tick(tick: int) -> bool:
	if _shutdown or not _bound or tick < 0 or tick < _last_tick:
		_reject(tick, "stale_encounter_tick")
		return false
	return true


func _accept_event_context(tick: int, room_instance: String, revision: int) -> bool:
	if not _accept_tick(tick):
		return false
	if not room_instance.is_empty() and room_instance != _room_instance_id:
		_reject(tick, "stale_room_context")
		return false
	if revision >= 0 and revision != _world_revision:
		_reject(tick, "stale_room_context")
		return false
	return true


func _request_matches_context(request: EncounterSpawnRequest) -> bool:
	return request.room_instance_id == _room_instance_id and request.world_revision == _world_revision


func _invoke_spawn_port(binding: RoomEncounterSpawnPort, request: EncounterSpawnRequest, tick: int) -> Variant:
	if binding == null:
		return SpawnResultScript.failed(request, "encounter_spawn_binding_unavailable")
	var context := {
		"tick": tick,
		"room_instance_id": _room_instance_id,
		"world_revision": _world_revision,
		"request": request,
	}
	return binding.spawn(request, context)


func _normalize_spawn_result(raw: Variant, request: EncounterSpawnRequest) -> Variant:
	if raw is RefCounted and raw.get_script() == SpawnResultScript:
		return raw
	if raw is Dictionary:
		var data: Dictionary = raw
		if not bool(data.get("ok", false)) or String(data.get("kind", "")) == SpawnResultScript.KIND_FAILED:
			return SpawnResultScript.failed(request, String(data.get("error", "encounter_spawn_failed")))
		var handle: SimEntityHandle = data.get("handle", null) if data.get("handle", null) is SimEntityHandle else null
		var stable_key := int(data.get("stable_key", 0))
		var generation := int(data.get("generation", handle.generation if handle != null else 0))
		var entity_key := String(data.get("entity_key", ""))
		if entity_key.is_empty() and stable_key > 0:
			entity_key = "actor/%d" % stable_key
		return SpawnResultScript.spawned(
			request,
			handle,
			entity_key,
			stable_key,
			generation,
			String(data.get("room_instance_id", _room_instance_id)),
			int(data.get("world_revision", _world_revision))
		)
	return SpawnResultScript.failed(request, "invalid_encounter_spawn_result")


func _terminal_snapshot() -> Dictionary:
	var encounter_state := _encounter_snapshot()
	var phase := String(encounter_state.get("phase", ""))
	return {
		"phase": phase,
		"victory": phase == "victory",
		"defeat": phase == "defeat",
		"reason": String(encounter_state.get("terminal_reason", "")),
	}


func _terminal_failure(error_code: String) -> RoomTerminalResult:
	return TerminalResultScript.failure(error_code)


func _encounter_snapshot() -> Dictionary:
	return encounter.snapshot() if encounter != null and encounter.has_method("snapshot") else {}


func _request_snapshots(requests: Array) -> Array[Dictionary]:
	var snapshots: Array[Dictionary] = []
	for request: Variant in requests:
		if request is SpawnRequestScript:
			snapshots.append(request.snapshot())
	return snapshots


func _reject(tick: int, reason: String) -> void:
	rejected_notifications.append({
		"tick": tick,
		"reason": reason,
		"room_instance_id": _room_instance_id,
		"world_revision": _world_revision,
	})

