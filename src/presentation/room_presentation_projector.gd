class_name RoomPresentationProjector
extends RefCounted

## Detached adapter from one authoritative SimSnapshot to one PresentationFrame.
##
## The projector is the seam between the fixed-tick simulation and the
## presentation-only occlusion stack. It binds exactly one typed
## RoomActorAccess and explicit RoomPresentationBinding values. Per tick it
## projects every live actor's stable id, authoritative feet anchor, authored
## rank and REAL art box into frame entries, plus every static authored
## foreground piece. Binding art boxes are authored bottom-center relative to
## their own feet (art_bottom_center, the manifest convention); the projector
## anchors them on the projected feet anchor, so frame and plan geometry is
## always world-space. It reads simulation state only through detached
## snapshot dictionaries; it exposes no write path and never mutates the
## snapshot.
##
## Rejection rules (fail closed, no fallbacks):
## - an actor without a binding is a projection error, never a footprint box;
## - a binding without a real art box cannot exist (rejected at construction);
## - an actor missing from the snapshot rows, dead in the rows, or with feet
##   disagreeing between the row payload and the access snapshot is rejected;
## - room identity or world revision mismatch is rejected.

const FrameScript := preload("res://src/presentation/presentation_frame.gd")
const BindingScript := preload("res://src/presentation/room_presentation_binding.gd")
const AccessScript := preload("res://src/runtime/world/room_actor_access.gd")
const SnapshotScript := preload("res://src/runtime/simulation/sim_snapshot.gd")

var _access: Variant = null
var _actor_bindings: Dictionary = {}
var _static_bindings: Array = []


func bind_access(access: Variant) -> Dictionary:
	if access == null or access.get_script() != AccessScript:
		return {"ok": false, "error": "invalid_room_actor_access"}
	if _access != null:
		return {"ok": false, "error": "room_actor_access_already_bound"}
	_access = access
	return {"ok": true, "error": ""}


func bind_actor_visual(binding: Variant) -> Dictionary:
	var checked := _check_binding(binding, true)
	if not checked.ok:
		return {"ok": false, "error": checked.error}
	if _actor_bindings.has(checked.value.stable_id) or _has_static_id(checked.value.stable_id):
		return {"ok": false, "error": "duplicate_presentation_binding:%s" % checked.value.stable_id}
	_actor_bindings[checked.value.stable_id] = checked.value
	return {"ok": true, "error": ""}


func bind_static_visual(binding: Variant) -> Dictionary:
	var checked := _check_binding(binding, false)
	if not checked.ok:
		return {"ok": false, "error": checked.error}
	if _has_static_id(checked.value.stable_id) or _actor_bindings.has(checked.value.stable_id):
		return {"ok": false, "error": "duplicate_presentation_binding:%s" % checked.value.stable_id}
	_static_bindings.append(checked.value)
	return {"ok": true, "error": ""}


func actor_binding(stable_id: String) -> Variant:
	return _actor_bindings.get(stable_id, null)


func static_binding(stable_id: String) -> Variant:
	for binding: Variant in _static_bindings:
		if String(binding.stable_id) == stable_id:
			return binding
	return null


func static_binding_ids() -> Array[String]:
	var ids: Array[String] = []
	for binding: Variant in _static_bindings:
		ids.append(String(binding.stable_id))
	ids.sort()
	return ids


func static_binding_count() -> int:
	return _static_bindings.size()


## Derives static visual binding inputs from the mounted native scene. Every
## manifest occlusion-channel binding must resolve to exactly one real art
## node that carries the same metadata binding_id; the art box is measured on
## that node's actual drawn rectangle, never on collision or debug geometry.
## A missing, unresolvable, or empty piece is a load error: there is no
## placeholder fallback for authored foreground art.
static func derive_static_bindings(native_scene_root: Node, occlusion_bindings: Variant) -> Dictionary:
	if native_scene_root == null or not native_scene_root is Node:
		return {"ok": false, "error": "invalid_native_scene_root"}
	if not occlusion_bindings is Array:
		return {"ok": false, "error": "invalid_occlusion_bindings"}
	var bindings: Array = []
	var errors: Array[String] = []
	for source: Variant in occlusion_bindings as Array:
		if not source is Dictionary:
			errors.append("invalid_occlusion_binding_entry")
			continue
		var stable_id := String((source as Dictionary).get("binding_id", "")).strip_edges()
		if stable_id.is_empty():
			errors.append("occlusion_binding_missing_id")
			continue
		var node: Variant = _find_binding_node(native_scene_root as Node, stable_id)
		if node == null:
			errors.append("presentation_static_art_missing:%s" % stable_id)
			continue
		var measured: Dictionary = _static_art_box(native_scene_root as Node, node as Node2D)
		if measured.is_empty():
			errors.append("presentation_static_art_unresolvable:%s" % stable_id)
			continue
		var art_box: Rect2 = measured["art_box"]
		if art_box.size.x <= 0.0 or art_box.size.y <= 0.0:
			errors.append("presentation_static_art_empty:%s" % stable_id)
			continue
		var feet: Vector2 = measured["sort_anchor"]
		bindings.append({
			"stable_id": stable_id,
			"visual_id": stable_id,
			"rank": 0,
			"art_box": Rect2(art_box.position - feet, art_box.size),
			"feet_anchor": feet,
		})
	if not errors.is_empty():
		return {"ok": false, "error": errors[0], "errors": errors}
	return {"ok": true, "error": "", "value": bindings}


## Depth-first search for the authored art node of one manifest binding id.
static func _find_binding_node(scene_root: Node, binding_id: String) -> Variant:
	if scene_root.has_meta("binding_id") and String(scene_root.get_meta("binding_id")) == binding_id:
		return scene_root
	for child: Node in scene_root.get_children():
		var found: Variant = _find_binding_node(child, binding_id)
		if found != null:
			return found
	return null


## The real drawn rectangle of one authored piece, in the mounted scene's
## gameplay coordinate domain, plus its native Y-sort anchor. Only drawn art
## nodes qualify: a Sprite2D contributes its actual texture rectangle.
static func _static_art_box(scene_root: Node, node: Node2D) -> Dictionary:
	if not node is Sprite2D:
		return {}
	var relative: Variant = _relative_transform(scene_root, node)
	if relative == null:
		return {}
	var to_scene: Transform2D = relative
	var rect: Rect2 = _aabb_of((node as Sprite2D).get_rect(), to_scene)
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return {}
	# Native Y-sort keys on the node origin, so the occlusion baseline is the
	# origin's scene-space y with the box centered on it horizontally.
	var origin := to_scene * Vector2.ZERO
	return {"art_box": rect, "sort_anchor": Vector2(rect.get_center().x, origin.y)}


static func _relative_transform(scene_root: Node, node: Node2D) -> Variant:
	var chain: Array[Node2D] = []
	var current: Node = node
	while current != null and current != scene_root:
		if not current is Node2D:
			return null
		chain.append(current as Node2D)
		current = current.get_parent()
	if current != scene_root:
		return null
	var result := Transform2D.IDENTITY
	for index: int in range(chain.size() - 1, -1, -1):
		result = result * (chain[index] as Node2D).transform
	return result


static func _aabb_of(rect: Rect2, transform: Transform2D) -> Rect2:
	var points := PackedVector2Array([
		transform * rect.position,
		transform * (rect.position + Vector2(rect.size.x, 0.0)),
		transform * (rect.position + Vector2(0.0, rect.size.y)),
		transform * rect.end,
	])
	var first := points[0]
	var min_corner := Vector2(first.x, first.y)
	var max_corner := min_corner
	for point: Vector2 in points:
		min_corner = Vector2(minf(min_corner.x, point.x), minf(min_corner.y, point.y))
		max_corner = Vector2(maxf(max_corner.x, point.x), maxf(max_corner.y, point.y))
	return Rect2(min_corner, max_corner - min_corner)


## Room setup may reuse the mounted SceneRuntime after a room restart. Clear
## only dynamic actor bindings at that boundary; static authored bindings remain
## owned by this projector.
func clear_actor_bindings() -> void:
	_actor_bindings.clear()


## Projects one authoritative snapshot into one detached PresentationFrame.
## Returns {ok, value} with the frame, or {ok:false, errors:[...]}.
func project(snapshot: Variant) -> Dictionary:
	if _access == null:
		return {"ok": false, "errors": ["presentation_access_unbound"]}
	if snapshot == null or snapshot.get_script() != SnapshotScript:
		return {"ok": false, "errors": ["invalid_presentation_snapshot"]}
	var errors: Array[String] = []
	if String(_access.room_instance_id) != snapshot.room_instance_id:
		errors.append("presentation_room_mismatch")
	if int(_access.world_revision) != snapshot.world_revision:
		errors.append("presentation_revision_mismatch")
	var rows_by_key: Dictionary = {}
	for row: Variant in snapshot.rows:
		if row is Array and (row as Array).size() >= 7:
			rows_by_key[int(row[0])] = row
	var entries: Array = []
	for actor_id: String in _access.actor_ids():
		var entry_error := _project_actor(actor_id, rows_by_key, entries)
		if not entry_error.is_empty():
			errors.append(entry_error)
	for binding: Variant in _static_bindings:
		var feet: Vector2 = binding.static_feet_anchor
		entries.append({
			"stable_id": binding.stable_id,
			"visual_id": binding.visual_id,
			"feet_anchor": feet,
			"baseline_y": feet.y,
			"rank": binding.rank,
			"art_box": Rect2(feet + (binding.art_box as Rect2).position, (binding.art_box as Rect2).size),
		})
	if not errors.is_empty():
		return {"ok": false, "errors": errors}
	return FrameScript.build(snapshot.tick, snapshot.world_revision, entries)


func _project_actor(actor_id: String, rows_by_key: Dictionary, entries: Array) -> String:
	var binding: Variant = _actor_bindings.get(actor_id, null)
	if binding == null:
		return "missing_presentation_binding:%s" % actor_id
	var actor: Dictionary = _access.actor_snapshot(actor_id)
	if actor.is_empty():
		return "actor_access_lost:%s" % actor_id
	var stable_key := int(actor.get("stable_key", -1))
	var row: Variant = rows_by_key.get(stable_key, null)
	if row == null:
		return "actor_missing_from_snapshot:%s" % actor_id
	var row_array: Array = row
	if int(row_array[3]) != 1:
		return "actor_not_alive_in_snapshot:%s" % actor_id
	var payload: Variant = row_array[6]
	if not payload is Array or (payload as Array).size() < 2:
		return "invalid_snapshot_actor_payload:%s" % actor_id
	# ActorState.snapshot_payload layout: [0] feet x, [1] feet y. The
	# authoritative row is the projection source; the access snapshot must
	# agree with it or the seam is mis-wired.
	var row_feet := Vector2(float(payload[0]), float(payload[1]))
	var access_feet: Vector2 = actor.get("feet_position", Vector2.INF)
	if not row_feet.is_finite() or not access_feet.is_finite() or not row_feet.is_equal_approx(access_feet):
		return "snapshot_feet_mismatch:%s" % actor_id
	entries.append({
		"stable_id": actor_id,
		"visual_id": binding.visual_id,
		"feet_anchor": row_feet,
		"baseline_y": row_feet.y,
		"rank": binding.rank,
		"art_box": Rect2(row_feet + (binding.art_box as Rect2).position, (binding.art_box as Rect2).size),
	})
	return ""


func _has_static_id(stable_id: String) -> bool:
	for binding: Variant in _static_bindings:
		if String(binding.stable_id) == stable_id:
			return true
	return false


static func _check_binding(binding: Variant, expect_actor: bool) -> Dictionary:
	if binding == null or binding.get_script() != BindingScript:
		return {"ok": false, "error": "invalid_presentation_binding"}
	var is_actor: bool = binding.is_actor_binding()
	if is_actor != expect_actor:
		return {"ok": false, "error": "wrong_presentation_binding_kind"}
	return {"ok": true, "error": "", "value": binding}
