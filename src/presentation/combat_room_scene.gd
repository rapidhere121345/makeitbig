extends RefCounted
## Per-room combat place presentation: original floor plate, code-native edge
## trim, entry threshold, sealed exit ward and a small ground dress list.
##
## Presentation only. Every edge, entry and exit is derived from the authored
## room manifest (movement boundary, spawn socket and static blockers), so
## painted floor art never defines collision and no doorway can claim a
## transition the room does not implement. Room advance stays with room
## settlement and the HUD Leave action; the exit ward only shows whether the
## room is still contested ("sealed") or cleared ("wards_down"), and the gate
## or boundary behind it remains non-walkable in both states.
##
## Fail closed: a missing or malformed pack, scene list, manifest or dress asset
## clears every record and reports ASSETS PENDING. The floor pack is optional
## only for the explicit historical-fixture seam (require_ground == false).

const PaletteScript = preload("res://src/presentation/combat_palette.gd")
const GroundingScript = preload("res://src/presentation/grounding_effects.gd")
const Definition := preload("res://src/runtime/world/environment_object_definition.gd")
const JsonIO := preload("res://src/core/json_io.gd")

const PACK_PATH := "res://art/production/p1/world_expansion_v01/assets.json"
const SCENES_PATH := "res://content/presentation/combat_room_scenes.json"
const CATALOG_PATH := "res://content/rooms/combat/room_catalog.json"
const DRESS_ASSETS_PATH := "res://art/production/p1/world_polish_v01/assets.json"
const BOUNDARY_BINDING := "combat/movement-boundary"
const LAYOUT_BOUNDARY_TYPES := {"rectangle_arena": "rect", "corridor": "corridor", "ring": "ring"}
const LAYOUT_EDGE_STYLES := {"rectangle_arena": "court", "corridor": "causeway", "ring": "ritual"}
const GROUND_IDS: Array[String] = ["court_ground", "causeway_ground", "ritual_ground"]
const DRESS_FAMILIES: Array[String] = ["fern", "mushrooms", "votives", "relic"]
const GROUND_SIZE := Vector2(1024.0, 640.0)
const MAX_DRESSING := 12
## World-pixel keep-out around the entry threshold and exit ward for dressing.
const ROUTE_CLEARANCE_WORLD := 40.0
## Gameplay units: the arrival threshold sits next to the real spawn socket and
## well away from the exit.
const MAX_ENTRY_DISTANCE := 200.0
const MIN_ENTRY_EXIT_GAP := 200.0
const ROUTE_SAMPLE_STEP := 2.0
## Entry slabs straddle the authoritative edge, stepping inward so the arrival
## threshold stays inside the spawn framing (outward normal offsets, world px).
const ENTRY_SLAB_OFFSETS: Array[float] = [1.0, -4.0, -9.0]
const ENTRY_GAP_WORLD := 30.0
## Flat approach inlay from the edge threshold back along the checked
## spawn->entry segment, stopping short of the spawn (world px).
const RUNNER_SPAWN_GAP_WORLD := 24.0
const RUNNER_MAX_WORLD := 80.0
## A structure exit closer than this to a court edge opens a curb gap there.
const EXIT_GAP_EDGE_DISTANCE := 48.0
const EXIT_GAP_PAD_WORLD := 4.0
const STATE_SEALED := "sealed"
const STATE_WARDS_DOWN := "wards_down"
const SIDE_NORMALS := {"east": Vector2.RIGHT, "west": Vector2.LEFT, "north": Vector2.UP, "south": Vector2.DOWN}

## Fixture seams. Production always uses the constants above.
var pack_path := PACK_PATH
var scenes_path := SCENES_PATH
var catalog_path := CATALOG_PATH
var dress_assets_path := DRESS_ASSETS_PATH

var pending_reason := ""
var _rooms: Dictionary = {}
var _grounds: Dictionary = {}
var _dress_assets: Dictionary = {}
var _dress_textures: Dictionary = {}


static func exit_state(cleared: bool) -> String:
	return STATE_WARDS_DOWN if cleared else STATE_SEALED


func is_ready() -> bool:
	return pending_reason.is_empty() and _rooms.size() == LAYOUT_BOUNDARY_TYPES.size()


func has_grounds() -> bool:
	return not _grounds.is_empty()


func has_room(layout_id: String) -> bool:
	return _rooms.has(layout_id)


func ground_texture(layout_id: String) -> Texture2D:
	var room: Dictionary = _rooms.get(layout_id, {})
	var ground: Dictionary = _grounds.get(String(room.get("ground_id", "")), {})
	return ground.get("texture", null) as Texture2D


## world = focus - arena.size * scale / 2 + (gameplay - arena.position) * scale,
## the same invertible mapping ArenaWorldView.begin_frame() uses.
func load_assets(require_ground: bool, world_focus: Vector2, gameplay_scale: float) -> bool:
	pending_reason = ""
	_rooms.clear()
	_grounds.clear()
	_dress_assets.clear()
	_dress_textures.clear()
	if require_ground and not _load_grounds():
		return false
	if not _load_dress_assets():
		return false
	var scenes := _read_json(scenes_path)
	var catalog := _read_json(catalog_path)
	if scenes.is_empty() or catalog.is_empty():
		return false
	if int(scenes.get("schema_version", 0)) != 1 or not scenes.get("rooms", null) is Dictionary:
		return _fail("unsupported scene list")
	var rooms: Dictionary = scenes.rooms
	if rooms.size() != LAYOUT_BOUNDARY_TYPES.size():
		return _fail("scene list must describe exactly the three combat layouts")
	var used_grounds := {}
	var dress_signatures := {}
	for layout_id: String in LAYOUT_BOUNDARY_TYPES:
		if not rooms.get(layout_id, null) is Dictionary:
			return _fail("missing room " + layout_id)
		var record := _resolve_room(layout_id, rooms[layout_id], catalog, world_focus, gameplay_scale)
		if record.is_empty():
			return false
		var ground_id := String(record.ground_id)
		if used_grounds.has(ground_id):
			return _fail("ground %s reused by %s" % [ground_id, layout_id])
		used_grounds[ground_id] = true
		var signature := str(record.dressing)
		if dress_signatures.has(signature):
			return _fail("dress list of %s repeats another room" % layout_id)
		dress_signatures[signature] = true
		_rooms[layout_id] = record
	return true


func _fail(reason: String) -> bool:
	pending_reason = "ASSETS PENDING: combat room scenes " + reason
	_rooms.clear()
	_grounds.clear()
	_dress_assets.clear()
	_dress_textures.clear()
	return false


func _read_json(path: String) -> Dictionary:
	var read := JsonIO.read_object_status(path)
	match String(read.status):
		JsonIO.STATUS_MISSING:
			_fail("missing " + path)
		JsonIO.STATUS_UNREADABLE, JsonIO.STATUS_INVALID:
			_fail("invalid JSON " + path)
	return read.data


func _load_grounds() -> bool:
	var pack := _read_json(pack_path)
	if pack.is_empty():
		return false
	if int(pack.get("schema_version", 0)) != 1 or not pack.get("assets", null) is Dictionary:
		return _fail("unsupported floor pack")
	var assets: Dictionary = pack.assets
	var paths := {}
	var hashes := {}
	for ground_id: String in GROUND_IDS:
		var entry: Variant = assets.get(ground_id, null)
		if not entry is Dictionary:
			return _fail("floor pack lacks " + ground_id)
		if String((entry as Dictionary).get("status", "")) != "packed":
			return _fail("floor %s is not packed" % ground_id)
		var path := String((entry as Dictionary).get("path", ""))
		var sha := String((entry as Dictionary).get("sha256", "")).to_lower()
		if not (path.begins_with("res://") or path.begins_with("user://")) or sha.length() != 64 or not sha.is_valid_hex_number():
			return _fail("malformed floor record " + ground_id)
		if _point((entry as Dictionary).get("canvas", [])) != GROUND_SIZE or _point((entry as Dictionary).get("anchor", [])) != Vector2.ZERO or not _is_pair((entry as Dictionary).get("anchor", [])):
			return _fail("floor %s must be a 1024x640 plate anchored at 0,0" % ground_id)
		if paths.has(path) or hashes.has(sha):
			return _fail("floor %s is not an original per-room plate" % ground_id)
		paths[path] = true
		hashes[sha] = true
		if FileAccess.file_exists(path) and FileAccess.get_sha256(path) != sha:
			return _fail("floor %s hash mismatch" % ground_id)
		var texture := Definition.read_texture(path)
		if texture == null or texture.get_size() != GROUND_SIZE:
			return _fail("floor %s texture missing or wrong size" % ground_id)
		_grounds[ground_id] = {"texture": texture, "path": path, "sha256": sha}
	return true


func _load_dress_assets() -> bool:
	var data := _read_json(dress_assets_path)
	if data.is_empty():
		return false
	if int(data.get("schema_version", 0)) != 1 or not data.get("assets", null) is Dictionary:
		return _fail("unsupported dress assets")
	for family: String in DRESS_FAMILIES:
		var entry: Variant = (data.assets as Dictionary).get(family, null)
		if not entry is Dictionary:
			return _fail("missing dress asset " + family)
		var canvas := _point((entry as Dictionary).get("canvas", []))
		var anchor := _point((entry as Dictionary).get("anchor", []))
		var texture := Definition.read_texture(String((entry as Dictionary).get("path", "")))
		if texture == null or canvas.x <= 0.0 or canvas.y <= 0.0 or texture.get_size() != canvas or not _is_pair((entry as Dictionary).get("anchor", [])):
			return _fail("invalid dress asset " + family)
		_dress_assets[family] = {"canvas": canvas, "anchor": anchor}
		_dress_textures[family] = texture
	return true


func _resolve_room(layout_id: String, raw: Dictionary, catalog: Dictionary, world_focus: Vector2, gameplay_scale: float) -> Dictionary:
	var ground_id := String(raw.get("ground_id", ""))
	if not GROUND_IDS.has(ground_id):
		_fail("unknown ground for " + layout_id)
		return {}
	if String(raw.get("edge_style", "")) != String(LAYOUT_EDGE_STYLES[layout_id]):
		_fail("edge style does not match layout " + layout_id)
		return {}
	var manifest := _room_manifest(layout_id, catalog)
	if manifest.is_empty():
		return {}
	var arena := _rect(((manifest.get("gameplay_spatial_metadata", {}) as Dictionary).get("authored_arena_rect", [])))
	if arena.size.x <= 0.0 or arena.size.y <= 0.0:
		_fail("manifest arena rect invalid for " + layout_id)
		return {}
	var boundary := _boundary(manifest, String(LAYOUT_BOUNDARY_TYPES[layout_id]))
	if boundary.is_empty():
		_fail("movement boundary invalid for " + layout_id)
		return {}
	var blockers := _blockers(manifest)
	var radius := 0.0
	for profile: Variant in manifest.get("traversal_profiles", []):
		if profile is Dictionary and String((profile as Dictionary).get("profile_id", "")) == "standard":
			radius = float((profile as Dictionary).get("radius", 0.0))
	if radius <= 0.0:
		_fail("traversal radius missing for " + layout_id)
		return {}
	var entry_raw: Variant = raw.get("entry", null)
	if not entry_raw is Dictionary:
		_fail("entry missing for " + layout_id)
		return {}
	var socket_ref := String((entry_raw as Dictionary).get("socket_ref", ""))
	var socket := _socket(manifest, socket_ref)
	if socket_ref != "combat/spawn" or not socket.is_finite():
		_fail("entry must reference the authored combat/spawn socket in " + layout_id)
		return {}
	if not _inside_walkable(boundary, socket):
		_fail("spawn socket outside walkable geometry in " + layout_id)
		return {}
	var entry := _nearest_boundary(boundary, socket)
	if socket.distance_to(entry.point) > MAX_ENTRY_DISTANCE:
		_fail("entry threshold too far from the spawn socket in " + layout_id)
		return {}
	if not _route_clear(socket, entry.point, blockers, radius):
		_fail("entry route crosses an authored blocker in " + layout_id)
		return {}
	var exit := _resolve_exit(layout_id, raw.get("exit", null), boundary, blockers)
	if exit.is_empty():
		return {}
	if (exit.point as Vector2).distance_to(entry.point) < MIN_ENTRY_EXIT_GAP:
		_fail("entry and exit overlap in " + layout_id)
		return {}
	var anchor := world_focus - arena.size * gameplay_scale * 0.5
	var to_world := func(point: Vector2) -> Vector2: return anchor + (point - arena.position) * gameplay_scale
	var entry_world: Vector2 = to_world.call(entry.point)
	var exit_world: Vector2 = to_world.call(exit.point)
	var dressing := _resolve_dressing(layout_id, raw.get("dressing", null), [entry_world, exit_world])
	if dressing.is_empty():
		return {}
	return {
		"layout_id": layout_id,
		"ground_id": ground_id,
		"edge_style": String(raw.edge_style),
		"entry_style": String((entry_raw as Dictionary).get("style", "")),
		"boundary": boundary,
		"spawn_socket": socket,
		"entry_point": entry.point,
		"entry_normal": entry.normal,
		"exit_kind": exit.kind,
		"exit_binding": exit.binding,
		"exit_point": exit.point,
		"exit_normal": exit.normal,
		"exit_span": exit.span,
		"exit_style": exit.style,
		"dressing": dressing,
		"field_world": _boundary_world_rect(boundary, anchor, arena.position, gameplay_scale),
		"entry_world": entry_world,
		"exit_world": exit_world,
		"exit_span_world": float(exit.span) * gameplay_scale,
		"spawn_world": to_world.call(socket),
	}


func _room_manifest(layout_id: String, catalog: Dictionary) -> Dictionary:
	for entry: Variant in catalog.get("rooms", []):
		if entry is Dictionary and String((entry as Dictionary).get("layout_id", "")) == layout_id:
			return _read_json(String((entry as Dictionary).get("manifest_path", "")))
	_fail("catalog lacks " + layout_id)
	return {}


func _boundary(manifest: Dictionary, expected_type: String) -> Dictionary:
	for binding: Variant in manifest.get("stable_bindings", []):
		if not binding is Dictionary or String((binding as Dictionary).get("binding_id", "")) != BOUNDARY_BINDING:
			continue
		var geometry: Dictionary = (binding as Dictionary).get("geometry", {})
		if String(geometry.get("type", "")) != expected_type:
			return {}
		match expected_type:
			"rect":
				var rect := _rect(geometry.get("rect", []))
				return {"type": "rect", "rect": rect} if rect.size.x > 0.0 and rect.size.y > 0.0 else {}
			"corridor":
				var rect := _rect(geometry.get("rect", []))
				var half := float(geometry.get("half_height", 0.0))
				if String(geometry.get("axis", "")) != "horizontal" or rect.size.x <= 0.0 or half <= 0.0 or half * 2.0 > rect.size.y:
					return {}
				return {"type": "corridor", "rect": Rect2(rect.position.x, rect.get_center().y - half, rect.size.x, half * 2.0)}
			"ring":
				var center := _point(geometry.get("center", []))
				var inner := float(geometry.get("inner_radius", 0.0))
				var outer := float(geometry.get("outer_radius", 0.0))
				if not _is_pair(geometry.get("center", [])) or inner <= 0.0 or outer <= inner:
					return {}
				return {"type": "ring", "center": center, "inner": inner, "outer": outer}
	return {}


func _blockers(manifest: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for binding: Variant in manifest.get("stable_bindings", []):
		if not binding is Dictionary or String((binding as Dictionary).get("kind", "")) != "static_blocker":
			continue
		var points := PackedVector2Array()
		for pair: Variant in ((binding as Dictionary).get("geometry", {}) as Dictionary).get("points", []):
			points.append(_point(pair))
		if points.size() >= 3:
			result.append({
				"binding_id": String((binding as Dictionary).get("binding_id", "")),
				"movement": bool(((binding as Dictionary).get("channels", {}) as Dictionary).get("movement", false)),
				"points": points,
			})
	return result


func _socket(manifest: Dictionary, socket_id: String) -> Vector2:
	for socket: Variant in manifest.get("spawn_interaction_exit_sockets", []):
		if socket is Dictionary and String((socket as Dictionary).get("socket_id", "")) == socket_id and String((socket as Dictionary).get("kind", "")) == "spawn" and _is_pair((socket as Dictionary).get("position", [])):
			return _point((socket as Dictionary).position)
	return Vector2.INF


func _inside_walkable(boundary: Dictionary, point: Vector2) -> bool:
	if String(boundary.type) == "ring":
		var distance := point.distance_to(boundary.center)
		return distance > float(boundary.inner) and distance < float(boundary.outer)
	return (boundary.rect as Rect2).has_point(point)


## The arrival threshold is the authoritative boundary point nearest the real
## spawn socket. A ring is entered across its outer edge, never from the pit.
func _nearest_boundary(boundary: Dictionary, point: Vector2) -> Dictionary:
	if String(boundary.type) == "ring":
		var direction := (point - (boundary.center as Vector2)).normalized()
		return {"point": (boundary.center as Vector2) + direction * float(boundary.outer), "normal": direction}
	var rect: Rect2 = boundary.rect
	var options := [
		[point.x - rect.position.x, Vector2(rect.position.x, point.y), Vector2.LEFT],
		[rect.end.x - point.x, Vector2(rect.end.x, point.y), Vector2.RIGHT],
		[point.y - rect.position.y, Vector2(point.x, rect.position.y), Vector2.UP],
		[rect.end.y - point.y, Vector2(point.x, rect.end.y), Vector2.DOWN],
	]
	var best: Array = options[0]
	for option: Array in options:
		if float(option[0]) < float(best[0]):
			best = option
	return {"point": best[1], "normal": best[2]}


func _route_clear(from: Vector2, to: Vector2, blockers: Array[Dictionary], radius: float) -> bool:
	var steps := maxi(1, ceili(from.distance_to(to) / ROUTE_SAMPLE_STEP))
	for index: int in steps + 1:
		var sample := from.lerp(to, float(index) / float(steps))
		for blocker: Dictionary in blockers:
			if not bool(blocker.movement):
				continue
			var points: PackedVector2Array = blocker.points
			if Geometry2D.is_point_in_polygon(sample, points):
				return false
			for edge: int in points.size():
				var closest := Geometry2D.get_closest_point_to_segment(sample, points[edge], points[(edge + 1) % points.size()])
				if sample.distance_to(closest) < radius:
					return false
	return true


## An exit is either an existing movement-blocking structure (the ward sits on
## its sill) or an authoritative boundary end. Neither is ever walkable.
func _resolve_exit(layout_id: String, raw: Variant, boundary: Dictionary, blockers: Array[Dictionary]) -> Dictionary:
	if not raw is Dictionary:
		_fail("exit missing for " + layout_id)
		return {}
	var exit: Dictionary = raw
	var style := String(exit.get("style", ""))
	if exit.has("binding_ref") == exit.has("boundary_anchor"):
		_fail("exit must name exactly one of binding_ref or boundary_anchor in " + layout_id)
		return {}
	if exit.has("binding_ref"):
		if style != "gate_ward":
			_fail("structure exit style must be gate_ward in " + layout_id)
			return {}
		var binding_id := String(exit.binding_ref)
		for blocker: Dictionary in blockers:
			if String(blocker.binding_id) != binding_id:
				continue
			if not bool(blocker.movement) or not binding_id.contains("ruin.gate"):
				_fail("exit binding must be a movement-blocking gate in " + layout_id)
				return {}
			var points: PackedVector2Array = blocker.points
			var low := Vector2(INF, -INF)
			var high_x := -INF
			for point: Vector2 in points:
				low.x = minf(low.x, point.x)
				high_x = maxf(high_x, point.x)
				low.y = maxf(low.y, point.y)
			return {"kind": "structure", "binding": binding_id, "point": Vector2((low.x + high_x) * 0.5, low.y),
				"normal": Vector2.DOWN, "span": high_x - low.x, "style": style}
		_fail("exit binding %s is not authored in %s" % [binding_id, layout_id])
		return {}
	var side := String(exit.boundary_anchor)
	if style != "boundary_ward" or not SIDE_NORMALS.has(side) or String(boundary.type) == "ring":
		_fail("boundary exit must be a boundary_ward on a rect or corridor side in " + layout_id)
		return {}
	var rect: Rect2 = boundary.rect
	var normal: Vector2 = SIDE_NORMALS[side]
	var point := rect.get_center() + Vector2(normal.x * rect.size.x, normal.y * rect.size.y) * 0.5
	var span := rect.size.y if normal.x != 0.0 else rect.size.x
	return {"kind": "boundary", "binding": BOUNDARY_BINDING, "point": point, "normal": normal, "span": span, "style": style}


func _resolve_dressing(layout_id: String, raw: Variant, keep_out_world: Array) -> Array:
	if not raw is Array or (raw as Array).is_empty() or (raw as Array).size() > MAX_DRESSING:
		_fail("dress list for %s must hold 1..%d rows" % [layout_id, MAX_DRESSING])
		return []
	var ids := {}
	var rows: Array = []
	for row: Variant in raw:
		var id := String((row as Dictionary).get("id", "")) if row is Dictionary else ""
		var family := String((row as Dictionary).get("family", "")) if row is Dictionary else ""
		if id.is_empty() or ids.has(id) or not _dress_assets.has(family) or not _is_pair((row as Dictionary).get("feet", [])):
			_fail("invalid dress row in " + layout_id)
			return []
		ids[id] = true
		var feet := _point((row as Dictionary).feet)
		var asset: Dictionary = _dress_assets[family]
		var cell := Rect2(feet - (asset.anchor as Vector2), asset.canvas)
		if not Rect2(Vector2.ZERO, GROUND_SIZE).encloses(cell):
			_fail("dress row %s outside the floor" % id)
			return []
		for point: Vector2 in keep_out_world:
			if feet.distance_to(point) < ROUTE_CLEARANCE_WORLD:
				_fail("dress row %s blocks an entry or exit route" % id)
				return []
		rows.append({"id": id, "family": family, "feet": feet})
	return rows


## ------------------------------------------------------------------ reports

func room_report(layout_id: String, cleared: bool = false) -> Dictionary:
	var room: Dictionary = _rooms.get(layout_id, {})
	if room.is_empty():
		return {"ready": false, "layout_id": layout_id, "pending_reason": pending_reason}
	var ground: Dictionary = _grounds.get(String(room.ground_id), {})
	return {
		"ready": true,
		"layout_id": layout_id,
		"presentation_only": true,
		"ground_id": String(room.ground_id),
		"ground_path": String(ground.get("path", "")),
		"ground_sha256": String(ground.get("sha256", "")),
		"edge_style": String(room.edge_style),
		"spawn_socket": room.spawn_socket,
		"entry_point": room.entry_point,
		"entry_normal": room.entry_normal,
		"exit_kind": String(room.exit_kind),
		"exit_binding": String(room.exit_binding),
		"exit_point": room.exit_point,
		"exit_state": exit_state(cleared),
		"entry_world": room.entry_world,
		"exit_world": room.exit_world,
		"exit_span_world": room.exit_span_world,
		"field_world": room.field_world,
		"spawn_world": room.spawn_world,
		"runner_world": approach_runner(room.entry_world, room.spawn_world),
		"exit_walkable": false,
		"advance_authority": "room_settlement",
		"dressing": (room.dressing as Array).duplicate(true),
		"collision_bodies": 0,
	}


## Court curb blocks leave a gap at the entry threshold and where a structure
## exit meets an edge: the exit sill projected onto that edge, +/- half its span.
static func curb_block_skipped(center: Vector2, edge_start: Vector2, along: Vector2, entry_world: Vector2, exit_gaps: Array) -> bool:
	if center.distance_to(entry_world) <= ENTRY_GAP_WORLD:
		return true
	var normal := along.rotated(PI * 0.5)
	for gap: Dictionary in exit_gaps:
		var point: Vector2 = gap.point
		if absf((point - edge_start).dot(normal)) > EXIT_GAP_EDGE_DISTANCE:
			continue
		if absf((center - point).dot(along)) <= float(gap.half) + EXIT_GAP_PAD_WORLD:
			return true
	return false


## Inner and outer ends of the flat approach inlay; zero length when the spawn
## already stands next to its edge threshold.
static func approach_runner(entry_world: Vector2, spawn_world: Vector2) -> Dictionary:
	var length := clampf(entry_world.distance_to(spawn_world) - RUNNER_SPAWN_GAP_WORLD, 0.0, RUNNER_MAX_WORLD)
	return {"outer": entry_world, "inner": entry_world + (spawn_world - entry_world).normalized() * length, "length": length}


## World extent of each entry slab, for drawing and regression checks.
static func entry_slab_extents(point: Vector2, normal: Vector2) -> Array[Rect2]:
	var tangent := normal.rotated(PI * 0.5)
	var result: Array[Rect2] = []
	for index: int in ENTRY_SLAB_OFFSETS.size():
		var center := point + normal * ENTRY_SLAB_OFFSETS[index]
		var half_width := 20.0 + float(index) * 3.0
		var a := center - tangent * half_width - normal * 2.0
		var b := center + tangent * half_width + normal * 2.0
		result.append(Rect2(a, Vector2.ZERO).expand(b))
	return result


func _boundary_world_rect(boundary: Dictionary, anchor: Vector2, origin: Vector2, gameplay_scale: float) -> Rect2:
	if String(boundary.type) == "ring":
		var radius := float(boundary.outer)
		return Rect2(anchor + ((boundary.center as Vector2) - Vector2(radius, radius) - origin) * gameplay_scale, Vector2(radius, radius) * 2.0 * gameplay_scale)
	return Rect2(anchor + ((boundary.rect as Rect2).position - origin) * gameplay_scale, (boundary.rect as Rect2).size * gameplay_scale)


## ------------------------------------------------------------------ drawing
## All draw calls run under ArenaWorldView.world_transform(); to_world maps
## authoritative gameplay points into that native world space.

func draw_room(canvas: CanvasItem, layout_id: String, to_world: Callable, gameplay_scale: float, phase: float, cleared: bool) -> void:
	var room: Dictionary = _rooms.get(layout_id, {})
	if canvas == null or room.is_empty() or not to_world.is_valid():
		return
	var entry_world: Vector2 = to_world.call(room.entry_point)
	match String(room.edge_style):
		"court":
			var gaps: Array = [] if String(room.exit_kind) != "structure" else [{"point": to_world.call(room.exit_point), "half": float(room.exit_span) * gameplay_scale * 0.5}]
			_draw_court_edges(canvas, room.boundary, to_world, gameplay_scale, entry_world, gaps)
		"causeway":
			_draw_causeway_edges(canvas, room.boundary, to_world, gameplay_scale, entry_world)
		"ritual":
			_draw_ritual_edges(canvas, room.boundary, to_world, gameplay_scale, entry_world, phase)
	_draw_entry(canvas, entry_world, room.entry_normal, phase, to_world.call(room.spawn_socket))
	_draw_exit_ward(canvas, to_world.call(room.exit_point), room.exit_normal, float(room.exit_span) * gameplay_scale, String(room.exit_kind), phase, cleared)


func draw_dressing(canvas: CanvasItem, layout_id: String, region: Rect2) -> void:
	var room: Dictionary = _rooms.get(layout_id, {})
	for row: Dictionary in room.get("dressing", []):
		var asset: Dictionary = _dress_assets[row.family]
		var top_left: Vector2 = (row.feet as Vector2) - (asset.anchor as Vector2)
		if region.intersects(Rect2(top_left, asset.canvas)):
			GroundingScript.draw_dressing(canvas, _dress_textures[row.family], asset.anchor, (row.feet as Vector2).round(), String(row.family))


func _world_rect(rect: Rect2, to_world: Callable, gameplay_scale: float) -> Rect2:
	return Rect2(to_world.call(rect.position), rect.size * gameplay_scale)


func _shade_outside(canvas: CanvasItem, field: Rect2, alpha: float) -> void:
	var world := Rect2(Vector2.ZERO, GROUND_SIZE)
	var color := Color(PaletteScript.INK, alpha)
	canvas.draw_rect(Rect2(world.position, Vector2(world.size.x, field.position.y)), color, true)
	canvas.draw_rect(Rect2(Vector2(0.0, field.end.y), Vector2(world.size.x, world.end.y - field.end.y)), color, true)
	canvas.draw_rect(Rect2(Vector2(0.0, field.position.y), Vector2(field.position.x, field.size.y)), color, true)
	canvas.draw_rect(Rect2(Vector2(field.end.x, field.position.y), Vector2(world.end.x - field.end.x, field.size.y)), color, true)


## Broken curb stones just outside each authoritative edge of the forecourt,
## with a gap where the south steps meet the court.
func _draw_court_edges(canvas: CanvasItem, boundary: Dictionary, to_world: Callable, gameplay_scale: float, entry_world: Vector2, exit_gaps: Array = []) -> void:
	var field := _world_rect(boundary.rect, to_world, gameplay_scale)
	_shade_outside(canvas, field, 0.22)
	var edges := [
		[field.position, Vector2(field.end.x, field.position.y), Vector2.UP],
		[Vector2(field.position.x, field.end.y), field.end, Vector2.DOWN],
		[field.position, Vector2(field.position.x, field.end.y), Vector2.LEFT],
		[Vector2(field.end.x, field.position.y), field.end, Vector2.RIGHT],
	]
	for edge: Array in edges:
		var start: Vector2 = edge[0]
		var finish: Vector2 = edge[1]
		var outward: Vector2 = edge[2]
		var length := start.distance_to(finish)
		var along := (finish - start).normalized()
		var offset := 6.0
		var index := 0
		while offset < length - 6.0:
			var center := start + along * (offset + 7.0) + outward * 3.5
			if not curb_block_skipped(center, start, along, entry_world, exit_gaps) and index % 5 != 3:
				var size := Vector2(absf(along.x) * 14.0 + absf(outward.x) * 5.0, absf(along.y) * 14.0 + absf(outward.y) * 5.0)
				var block := Rect2((center - size * 0.5).round(), size)
				canvas.draw_rect(Rect2(block.position + Vector2(1.0, 2.0), block.size), Color(PaletteScript.INK, 0.55), true)
				canvas.draw_rect(block, Color(PaletteScript.SLATE_2, 0.92), true)
				canvas.draw_rect(Rect2(block.position, Vector2(block.size.x, 1.0)), Color(PaletteScript.SLATE_3, 0.45), true)
			offset += 20.0
			index += 1
	for corner: Vector2 in [field.position, Vector2(field.end.x, field.position.y), field.end, Vector2(field.position.x, field.end.y)]:
		var post := Rect2((corner - Vector2(5.0, 5.0)).round(), Vector2(10.0, 10.0))
		canvas.draw_rect(Rect2(post.position + Vector2(1.0, 2.0), post.size), Color(PaletteScript.INK, 0.6), true)
		canvas.draw_rect(post, PaletteScript.SLATE_2, true)
		canvas.draw_rect(Rect2(post.position, Vector2(post.size.x, 2.0)), Color(PaletteScript.COPPER_DULL, 0.75), true)


## Raised road: shaded lower terraces, curb lips on both authoritative band
## edges, low balustrade posts on the far side and kerb blocks on the near side.
func _draw_causeway_edges(canvas: CanvasItem, boundary: Dictionary, to_world: Callable, gameplay_scale: float, entry_world: Vector2) -> void:
	var band := _world_rect(boundary.rect, to_world, gameplay_scale)
	var color := Color(PaletteScript.INK, 0.28)
	canvas.draw_rect(Rect2(Vector2.ZERO, Vector2(GROUND_SIZE.x, band.position.y)), color, true)
	canvas.draw_rect(Rect2(Vector2(0.0, band.end.y), Vector2(GROUND_SIZE.x, GROUND_SIZE.y - band.end.y)), color, true)
	canvas.draw_rect(Rect2(Vector2(0.0, band.position.y), Vector2(band.position.x, band.size.y)), color, true)
	canvas.draw_rect(Rect2(Vector2(band.end.x, band.position.y), Vector2(GROUND_SIZE.x - band.end.x, band.size.y)), color, true)
	for y: float in [band.position.y, band.end.y]:
		canvas.draw_line(Vector2(band.position.x, y + 2.0), Vector2(band.end.x, y + 2.0), Color(PaletteScript.INK, 0.7), 4.0, false)
		canvas.draw_line(Vector2(band.position.x, y), Vector2(band.end.x, y), Color(PaletteScript.BONE_DIM, 0.32), 1.0, false)
	var x := band.position.x + 18.0
	while x < band.end.x - 10.0:
		var post := Rect2(Vector2(roundf(x) - 2.0, roundf(band.position.y) - 10.0), Vector2(4.0, 9.0))
		canvas.draw_rect(post, Color(PaletteScript.SLATE_2, 0.95), true)
		canvas.draw_rect(Rect2(post.position, Vector2(4.0, 1.0)), Color(PaletteScript.COPPER_DULL, 0.7), true)
		var kerb := Vector2(roundf(x), roundf(band.end.y) + 3.0)
		if kerb.distance_to(entry_world) > 30.0:
			canvas.draw_rect(Rect2(kerb - Vector2(3.0, 0.0), Vector2(6.0, 3.0)), Color(PaletteScript.SLATE_2, 0.9), true)
		x += 48.0


## Ritual ring: a sunken sigil well inside the inner edge, rune curb on both
## edges and low standing stones beyond the outer edge.
func _draw_ritual_edges(canvas: CanvasItem, boundary: Dictionary, to_world: Callable, gameplay_scale: float, entry_world: Vector2, phase: float) -> void:
	var center: Vector2 = to_world.call(boundary.center)
	var inner := float(boundary.inner) * gameplay_scale
	var outer := float(boundary.outer) * gameplay_scale
	canvas.draw_arc(center, outer + 48.0, 0.0, TAU, 96, Color(PaletteScript.INK, 0.24), 96.0, false)
	canvas.draw_circle(center, inner, Color(PaletteScript.INK, 0.58))
	canvas.draw_arc(center, inner - 7.0, 0.0, TAU, 64, Color(PaletteScript.PURPLE, 0.34), 2.0, false)
	for index: int in 12:
		var angle := TAU * float(index) / 12.0 + phase * 0.2
		var direction := Vector2.from_angle(angle)
		canvas.draw_line(center + direction * (inner - 12.0), center + direction * (inner - 3.0), Color(PaletteScript.PURPLE, 0.42), 2.0, false)
	for radius: float in [inner, outer]:
		canvas.draw_arc(center, radius + (1.5 if radius == outer else -1.5), 0.0, TAU, 96, Color(PaletteScript.INK, 0.65), 3.0, false)
		canvas.draw_arc(center, radius, 0.0, TAU, 96, Color(PaletteScript.BONE_DIM, 0.26), 1.0, false)
	var entry_angle := (entry_world - center).angle()
	for index: int in 16:
		var angle := TAU * float(index) / 16.0
		if absf(angle_difference(angle, entry_angle)) < deg_to_rad(14.0):
			continue
		var foot := (center + Vector2.from_angle(angle) * (outer + 12.0)).round()
		var stone := Rect2(foot - Vector2(3.0, 9.0), Vector2(6.0, 9.0))
		canvas.draw_rect(Rect2(stone.position + Vector2(1.0, 1.0), stone.size), Color(PaletteScript.INK, 0.6), true)
		canvas.draw_rect(stone, PaletteScript.SLATE_2, true)
		var glow := 0.22 + 0.12 * (0.5 + 0.5 * sin(phase * TAU + float(index) * 0.7))
		canvas.draw_rect(Rect2(foot - Vector2(1.0, 7.0), Vector2(2.0, 2.0)), Color(PaletteScript.COLD, glow), true)


## Ground-level arrival threshold: three stepped slabs leading out of the
## field along the authoritative outward normal, flanked by two low lamps. No
## arrow: the player already stands inside when the room begins.
func _draw_entry(canvas: CanvasItem, point: Vector2, normal: Vector2, phase: float, spawn_world: Vector2) -> void:
	var tangent := normal.rotated(PI * 0.5)
	var runner := approach_runner(point, spawn_world)
	var lamp_base: Vector2 = runner.inner if float(runner.length) > 0.0 else point - normal * 4.0
	if float(runner.length) > 0.0:
		var inward: Vector2 = ((runner.inner as Vector2) - point).normalized()
		var side := inward.rotated(PI * 0.5)
		canvas.draw_line(point, runner.inner, Color(PaletteScript.BONE_DIM, 0.16), 14.0, false)
		var step := 0.0
		while step <= float(runner.length) - 6.0:
			var stone := point + inward * (step + 6.0)
			canvas.draw_colored_polygon(PackedVector2Array([stone - side * 7.0 - inward * 3.0, stone + side * 7.0 - inward * 3.0,
				stone + side * 7.0 + inward * 3.0, stone - side * 7.0 + inward * 3.0]), Color(PaletteScript.SLATE_2, 0.85))
			canvas.draw_line(stone - side * 7.0 - inward * 3.0, stone + side * 7.0 - inward * 3.0, Color(PaletteScript.COLD, 0.45), 1.0, false)
			step += 14.0
	for index: int in 3:
		var center := point + normal * ENTRY_SLAB_OFFSETS[index]
		var half_width := 20.0 + float(index) * 3.0
		var slab := PackedVector2Array([
			center - tangent * half_width - normal * 2.0, center + tangent * half_width - normal * 2.0,
			center + tangent * half_width + normal * 2.0, center - tangent * half_width + normal * 2.0,
		])
		canvas.draw_colored_polygon(slab, Color(PaletteScript.SLATE_2, 0.9))
		canvas.draw_line(slab[0], slab[1], Color(PaletteScript.BONE_DIM, 0.3), 1.0, false)
	var lamp := 0.45 + 0.15 * (0.5 + 0.5 * sin(phase * TAU))
	for side: float in [-1.0, 1.0]:
		var foot := (lamp_base + tangent * side * 27.0).round()
		canvas.draw_rect(Rect2(foot - Vector2(2.0, 6.0), Vector2(4.0, 6.0)), PaletteScript.SLATE_2, true)
		canvas.draw_rect(Rect2(foot - Vector2(1.0, 7.0), Vector2(2.0, 2.0)), Color(PaletteScript.COLD, lamp), true)


## Exit ward across a sealed gate sill or boundary end. Sealed: a bright ward
## line with filled runes. Wards down: the line breaks into faint dashes and
## the runes go hollow with a warm ember — still a closed, non-walkable edge,
## because the room advances through settlement and the HUD Leave action.
func _draw_exit_ward(canvas: CanvasItem, point: Vector2, normal: Vector2, span: float, kind: String, phase: float, cleared: bool) -> void:
	var tangent := normal.rotated(PI * 0.5)
	var half := maxf(12.0, span * (0.4 if kind == "structure" else 0.5))
	var start := point - tangent * half
	var finish := point + tangent * half
	if kind == "boundary":
		for end: Vector2 in [start, finish]:
			var pillar := Rect2((end - Vector2(3.0, 12.0)).round(), Vector2(6.0, 12.0))
			canvas.draw_rect(Rect2(pillar.position + Vector2(1.0, 1.0), pillar.size), Color(PaletteScript.INK, 0.6), true)
			canvas.draw_rect(pillar, PaletteScript.SLATE_2, true)
	if cleared:
		var segments := 9
		for index: int in segments:
			if index % 2 == 0:
				canvas.draw_line(start.lerp(finish, float(index) / segments), start.lerp(finish, float(index + 1) / segments), Color(PaletteScript.BONE_DIM, 0.35), 1.0, false)
		canvas.draw_circle(point - Vector2(0.0, 6.0), half * 0.45, Color(PaletteScript.COPPER, 0.10))
	else:
		var pulse := 0.65 + 0.15 * (0.5 + 0.5 * sin(phase * TAU))
		canvas.draw_line(start, finish, Color(PaletteScript.INK, 0.8), 5.0, false)
		canvas.draw_line(start, finish, Color(PaletteScript.DANGER, pulse), 2.0, false)
	for index: int in 3:
		var rune := start.lerp(finish, float(index + 1) / 4.0)
		var diamond := PackedVector2Array([rune + Vector2(0.0, -4.0), rune + Vector2(4.0, 0.0), rune + Vector2(0.0, 4.0), rune + Vector2(-4.0, 0.0)])
		if cleared:
			diamond.append(diamond[0])
			canvas.draw_polyline(diamond, Color(PaletteScript.COPPER, 0.6), 1.0, false)
		else:
			canvas.draw_colored_polygon(diamond, Color(PaletteScript.PURPLE, 0.85))


static func _point(value: Variant) -> Vector2:
	if value is Vector2:
		return value
	if not value is Array or (value as Array).size() != 2:
		return Vector2.ZERO
	return Vector2(float((value as Array)[0]), float((value as Array)[1]))


static func _is_pair(value: Variant) -> bool:
	if not value is Array or (value as Array).size() != 2:
		return false
	for coordinate: Variant in value:
		if not (coordinate is float or coordinate is int) or not is_finite(float(coordinate)):
			return false
	return true


static func _rect(value: Variant) -> Rect2:
	if not value is Array or (value as Array).size() != 4:
		return Rect2()
	var array: Array = value
	return Rect2(float(array[0]), float(array[1]), float(array[2]), float(array[3]))
