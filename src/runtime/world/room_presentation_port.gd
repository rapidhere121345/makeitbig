class_name RoomPresentationPort
extends SimPresentationPort

## Snapshot sink.  It stores the detached authoritative snapshot; visual
## entries are projected by the typed presentation binding projector once
## the composition root binds it.  Without a projector the port keeps the
## detached header-only frame; it never synthesizes actor visuals from
## gameplay geometry.

const PresentationFrameScript := preload("res://src/presentation/presentation_frame.gd")
const ProjectorScript := preload("res://src/presentation/room_presentation_projector.gd")

var latest_snapshot: SimSnapshot = null
var latest_frame: Variant = null
var last_projection_errors: Array[String] = []

var _projector: Variant = null


## Binds the detached typed presentation projector.  The projector is a
## presentation object: it only reads detached snapshots and only writes
## detached frames, so binding it cannot open a path back into simulation.
func bind_projector(projector: Variant) -> Dictionary:
	if projector == null or projector.get_script() != ProjectorScript:
		return {"ok": false, "error": "invalid_presentation_projector"}
	if _projector != null:
		return {"ok": false, "error": "presentation_projector_already_bound"}
	_projector = projector
	return {"ok": true, "error": ""}


## Replaces the projector at a room restart boundary. The caller supplies a
## projector already bound to the new RoomActorAccess, so the old access object
## cannot remain reachable through this port.
func replace_projector(projector: Variant) -> Dictionary:
	if projector == null or projector.get_script() != ProjectorScript:
		return {"ok": false, "error": "invalid_presentation_projector"}
	_projector = projector
	# The replacement owns a new room identity: stale frames and projection
	# errors from the retired projector must not survive the boundary.
	latest_frame = null
	last_projection_errors = []
	return {"ok": true, "error": ""}


func clear_projector() -> void:
	_projector = null


func has_projector() -> bool:
	return _projector != null


func on_snapshot(snapshot: SimSnapshot) -> void:
	latest_snapshot = snapshot
	last_projection_errors = []
	if _projector == null:
		# Composition root has not wired the typed binding projector yet.
		# Keep the detached header-only frame; no actor entry is invented.
		var unbound: Dictionary = PresentationFrameScript.build(snapshot.tick, snapshot.world_revision, [])
		latest_frame = unbound.value if bool(unbound.get("ok", false)) else null
		return
	var projected: Dictionary = _projector.project(snapshot)
	if not bool(projected.get("ok", false)):
		latest_frame = null
		for message: Variant in projected.get("errors", []):
			last_projection_errors.append(String(message))
		if last_projection_errors.is_empty():
			last_projection_errors.append(String(projected.get("error", "presentation_projection_failed")))
		return
	latest_frame = projected.value


## Detached occlusion plan for the latest frame, ready for the
## presentation-only OcclusionController.  Fails closed with the recorded
## projection errors when no valid frame exists.
func latest_occlusion_plan() -> Dictionary:
	if latest_frame == null:
		var errors := last_projection_errors.duplicate()
		if errors.is_empty():
			errors.append("no_presentation_frame")
		return {"ok": false, "errors": errors}
	return latest_frame.occlusion_plan()


## Detached diagnostic snapshot for SceneRuntime reports.  It exposes the
## latest authoritative header and projected frame only; no presentation value
## is an input to the simulation.
func snapshot() -> Dictionary:
	return {
		"latest_snapshot": {
			"tick": latest_snapshot.tick,
			"world_revision": latest_snapshot.world_revision,
			"room_instance_id": latest_snapshot.room_instance_id,
			"entity_count": latest_snapshot.entity_count(),
		} if latest_snapshot != null else {},
		"latest_frame": latest_frame.snapshot() if latest_frame != null and latest_frame.has_method("snapshot") else {},
		"last_projection_errors": last_projection_errors.duplicate(),
		"projector_bound": _projector != null,
	}
