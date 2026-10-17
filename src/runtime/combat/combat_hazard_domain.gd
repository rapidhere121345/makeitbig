class_name CombatHazardDomain
extends "res://src/runtime/combat/combat_hazard_read_port.gd"

## Room-owned hazard domain for fixed-tick combat.
##
## This domain owns hazard lifecycle and contact suppression. It has no Node,
## SceneTree or damage-rule dependency. Contact resolution is delegated to the
## typed EncounterRoomPort and consumed later by RoomCombatPort.

const HazardScript := preload("res://src/runtime/combat/combat_hazard.gd")

var room_port: EncounterRoomPort = null
var arena_rect := Rect2()
var hazards: Array = []
var _configured := false


func configure(port: Variant, bounds: Rect2, authored_states: Array = []) -> Dictionary:
	if not port is EncounterRoomPort:
		return {"ok": false, "error": "hazard_room_port_unavailable"}
	if not bounds.position.is_finite() or not bounds.size.is_finite() or bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return {"ok": false, "error": "hazard_bounds_invalid"}
	room_port = port
	arena_rect = bounds
	hazards.clear()
	for raw: Variant in authored_states:
		if not raw is Dictionary:
			return {"ok": false, "error": "invalid_hazard_state"}
		var state: Dictionary = raw
		var hazard := HazardScript.new()
		var created := hazard.configure(String(state.get("id", "")), state.get("origin", Vector2.ZERO))
		if not bool(created.get("ok", false)):
			return created
		var imported := hazard.import_view(state)
		if not bool(imported.get("ok", false)):
			return imported
		hazards.append(hazard)
	_configured = true
	return {"ok": true, "error": "", "count": hazards.size()}


func configure_ids(port: Variant, bounds: Rect2, hazard_ids: Array, center: Vector2) -> Dictionary:
	if not port is EncounterRoomPort:
		return {"ok": false, "error": "hazard_room_port_unavailable"}
	var authored: Array[Dictionary] = []
	for raw_id: Variant in hazard_ids:
		var id := String(raw_id)
		var authored_origin := center + Vector2(70.0, 0.0) if id == "exposed_ground_zone" else center
		var state := {"id": id, "origin": authored_origin}
		authored.append(state)
	return configure(port, bounds, authored)


func is_configured() -> bool:
	return _configured and room_port != null


func refresh(at_tick: int) -> Dictionary:
	if not _configured or room_port == null:
		return {"ok": false, "error": "hazard_domain_unconfigured"}
	for hazard in hazards:
		var synced: Dictionary = hazard.sync_external_view()
		if not bool(synced.get("ok", false)):
			return synced
		var advanced: Dictionary = hazard.advance(at_tick, arena_rect, room_port)
		if not bool(advanced.get("ok", false)):
			return {"ok": false, "error": String(advanced.get("error", "hazard_advance_failed"))}
	return {"ok": true, "error": "", "tick": at_tick, "hazards": snapshots()}


func resolve(at_tick: int, player_position: Vector2) -> Dictionary:
	if not _configured or room_port == null:
		return {"ok": false, "error": "hazard_domain_unconfigured"}
	var contacts: Array[Dictionary] = []
	for hazard in hazards:
		var synced: Dictionary = hazard.sync_external_view()
		if not bool(synced.get("ok", false)):
			return synced
		var queued: Dictionary = hazard.queue_player_contact(at_tick, player_position, room_port)
		if not bool(queued.get("ok", false)):
			return {"ok": false, "error": String(queued.get("error", "hazard_contact_failed"))}
		if bool(queued.get("queued", false)):
			contacts.append(queued)
	return {"ok": true, "error": "", "tick": at_tick, "contacts": contacts, "hazards": snapshots()}


func snapshots() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for hazard in hazards:
		result.append(hazard.mutable_view())
	return result


func active_geometry() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for hazard in hazards:
		var synced: Dictionary = hazard.sync_external_view()
		if not bool(synced.get("ok", false)):
			continue
		var state: Dictionary = hazard.snapshot()
		var phase := String(state.get("phase", ""))
		if phase not in ["warning", "active"]:
			continue
		var shape: Dictionary
		if String(state.get("id", "")) == "moving_fireline":
			var origin: Vector2 = state.get("origin", Vector2.ZERO)
			shape = {"shape": "rect", "rect": Rect2(origin - Vector2(float(state.get("width", 0.0)) * 0.5, 0.0), Vector2(float(state.get("width", 0.0)), float(state.get("length", 0.0))))}
		else:
			shape = {"shape": "circle", "center": state.get("origin", Vector2.ZERO), "radius": float(state.get("radius", 0.0))}
		result.append({("active_geometry" if phase == "active" else "warning_geometry"): shape})
	return result
