class_name PrimitiveFadeController
extends RefCounted

## Roof/canopy-only physical transparency for pieces that explicitly opt in
## with authored occlusion volumes (circles and convex polygons, rectangles
## authored as 4-point polygons) in placement-translated world space. The
## opted-in upper part's Sprite2D eases its own modulate.a down to
## FADED_ALPHA while its base, every non-opted piece and every actor stay
## fully opaque. No texture-alpha masks, no actor samplers, no per-pixel
## shaders: the only inputs are the detached plan entries (for the shared
## deterministic front/back ordering) and the protected actors' fixed
## head/torso readability boxes. Presentation-only; nothing here writes the
## simulation, the scene, or any other piece.

const SortRelation := preload("res://src/presentation/occlusion_query.gd")

const POLICY := "primitive_fade"
## Tunable fade contract: the settled roof opacity over a protected actor and
## the full open/close transition duration.
const FADED_ALPHA := 0.25
const TRANSITION_SECONDS := 0.18
## Hysteresis over the readability-box coverage: open on a real overlap,
## close only once the box has left the volumes almost entirely. The signal
## is the MAX coverage over the piece's volumes — deliberately no union
## solver, so two volumes that happen to overlap are simply both counted.
const ENTER_BOX_COVERAGE := 0.08
const EXIT_BOX_COVERAGE := 0.02

var _pieces: Dictionary = {}


func has_piece(stable_id: String) -> bool:
	return _pieces.has(stable_id)


## Registers one opted-in piece. The volumes arrive placement-translated in
## world space from the author source (baker meta for modular pieces, scene
## meta for native pieces) and are validated here with the same circle and
## convex-polygon conventions the definition uses — malformed, non-finite,
## degenerate or absent volumes fail closed instead of guessing geometry.
func register_piece(stable_id: String, sprite: Sprite2D, volumes: Variant) -> Dictionary:
	if stable_id.is_empty() or sprite == null:
		return {"ok": false, "error": "primitive_fade_missing_target:" + stable_id}
	if not volumes is Array or (volumes as Array).is_empty():
		return {"ok": false, "error": "primitive_fade_missing_volumes:" + stable_id}
	var checked: Array = []
	for volume: Variant in volumes:
		var error := _validate_volume(volume)
		if not error.is_empty():
			return {"ok": false, "error": error + ":" + stable_id}
		checked.append(volume)
	_pieces[stable_id] = {"sprite": weakref(sprite), "volumes": checked,
		"open": false, "weight": 0.0, "coverage": 0.0, "actors": {}}
	sprite.modulate.a = 1.0
	return {"ok": true, "error": ""}


## subjects carry stable_id, baseline_y, rank and a world-space readability_box
## (the same protected-actor rows the authored reveal consumes). A piece only
## fades while a protected actor's box intersects one of its volumes AND the
## piece is ordered in front of that actor by the shared sort relation; the
## weight then eases on this controller's own clock, independent of any
## window tier, and drives nothing but the piece's own modulate.a.
func update(entries: Array, subjects: Array, delta: float) -> void:
	var by_id := {}
	for entry: Dictionary in entries:
		by_id[String(entry.stable_id)] = entry
	for stable_id: String in _pieces.keys():
		var state: Dictionary = _pieces[stable_id]
		var sprite: Variant = (state.sprite as WeakRef).get_ref()
		if sprite == null:
			_pieces.erase(stable_id)
			continue
		var next := advance_state(state.volumes, by_id.get(stable_id, {}), subjects, state, delta)
		for key: String in next:
			state[key] = next[key]
		(sprite as Sprite2D).modulate.a = float(next.alpha)


## Shared state transition for Sprite2D targets and immediate-mode combat
## draw commands. Call once per committed presentation frame, never per draw.
static func advance_state(volumes: Array, part: Dictionary, subjects: Array, previous: Dictionary, delta: float) -> Dictionary:
	var maximum := 0.0
	var contributors := {}
	if not part.is_empty():
		for subject: Dictionary in subjects:
			if not SortRelation.is_front(part, subject):
				continue
			var coverage := box_coverage(volumes, subject.readability_box)
			if coverage > 0.0:
				contributors[String(subject.stable_id)] = coverage
				maximum = maxf(maximum, coverage)
	var opened := maximum >= (EXIT_BOX_COVERAGE if bool(previous.get("open", false)) else ENTER_BOX_COVERAGE)
	var weight := move_toward(float(previous.get("weight", 0.0)), 1.0 if opened else 0.0,
		maxf(delta, 0.0) / TRANSITION_SECONDS)
	return {"open": opened, "weight": weight, "coverage": maximum, "actors": contributors,
		"alpha": lerpf(1.0, FADED_ALPHA, weight), "target_alpha": FADED_ALPHA if opened else 1.0}



## Max coverage over the piece's volumes (no union): the fraction of one
## readability box a volume covers. Polygons measure the exact convex
## intersection; a circle measures its axis-aligned bounds — conservative,
## deterministic, and only ever an overestimate of the true circle share.
static func box_coverage(volumes: Array, box: Rect2) -> float:
	if not box.has_area():
		return 0.0
	var maximum := 0.0
	for volume: Dictionary in volumes:
		maximum = maxf(maximum, volume_coverage(volume, box))
	return clampf(maximum, 0.0, 1.0)


static func volume_coverage(volume: Dictionary, box: Rect2) -> float:
	if not box.has_area():
		return 0.0
	if volume.get("type") == "circle":
		var center: Vector2 = volume.center
		var radius := float(volume.radius)
		var closest := Vector2(clampf(center.x, box.position.x, box.end.x), clampf(center.y, box.position.y, box.end.y))
		if closest.distance_squared_to(center) > radius * radius:
			return 0.0
		var bounds := Rect2(center - Vector2(radius, radius), Vector2(radius, radius) * 2.0)
		return bounds.intersection(box).get_area() / box.get_area()
	var points: PackedVector2Array = volume.points
	var covered := 0.0
	for piece: PackedVector2Array in Geometry2D.intersect_polygons(_box_quad(box), points):
		covered += absf(_signed_area(piece))
	return clampf(covered / box.get_area(), 0.0, 1.0)


static func _box_quad(box: Rect2) -> PackedVector2Array:
	return PackedVector2Array([box.position, Vector2(box.end.x, box.position.y), box.end, Vector2(box.position.x, box.end.y)])


static func _signed_area(points: PackedVector2Array) -> float:
	var total := 0.0
	for index in points.size():
		var a: Vector2 = points[index]
		var b: Vector2 = points[(index + 1) % points.size()]
		total += a.x * b.y - b.x * a.y
	return total * 0.5


## Fail-closed and detach paths: every registration immediately returns its
## piece to full opacity; registrations survive a reset (the plan may return).
func reset() -> void:
	for state: Dictionary in _pieces.values():
		state["open"] = false
		state["weight"] = 0.0
		state["coverage"] = 0.0
		state["actors"] = {}
		var sprite: Variant = (state.sprite as WeakRef).get_ref()
		if sprite != null:
			(sprite as Sprite2D).modulate.a = 1.0


func clear() -> void:
	for state: Dictionary in _pieces.values():
		var sprite: Variant = (state.sprite as WeakRef).get_ref()
		if sprite != null:
			(sprite as Sprite2D).modulate.a = 1.0
	_pieces.clear()


## Honest per-piece audit: the policy actually operating, the live alpha of
## the piece (not a plan intention), the eased weight and its coverage, the
## protected actor ids that currently hold the fade open, and the exact
## placement-translated volumes. This is its own report field — never aliased
## as authored pixel-mask evidence.
func report() -> Dictionary:
	var result := {}
	for stable_id: String in _pieces.keys():
		var state: Dictionary = _pieces[stable_id]
		var sprite: Variant = (state.sprite as WeakRef).get_ref()
		result[stable_id] = {
			"policy": POLICY,
			"open": bool(state["open"]),
			"weight": float(state["weight"]),
			"coverage": float(state["coverage"]),
			"target_alpha": lerpf(1.0, FADED_ALPHA, 1.0 if bool(state["open"]) else 0.0),
			"piece_alpha": (sprite as Sprite2D).modulate.a if sprite != null else 1.0,
			"faded_alpha": FADED_ALPHA,
			"transition_seconds": TRANSITION_SECONDS,
			"actors": (state["actors"] as Dictionary).duplicate(true),
			"volumes": volumes_payload(state["volumes"]),
		}
	return result


## Deterministic plain-value payload of placement-translated volumes, shared
## by the presenter audit and the scene-root presentation fingerprint.
static func volumes_payload(volumes: Variant) -> Array:
	var payload: Array = []
	if not volumes is Array:
		return payload
	for volume: Variant in volumes:
		if not volume is Dictionary:
			continue
		var data: Dictionary = volume
		if data.get("type") == "circle":
			var center: Vector2 = data.get("center", Vector2.INF)
			payload.append({"type": "circle", "center": [center.x, center.y], "radius": float(data.get("radius", 0.0))})
		elif data.get("type") == "polygon":
			var points: Array = []
			for point: Vector2 in data.get("points", PackedVector2Array()):
				points.append([point.x, point.y])
			payload.append({"type": "polygon", "points": points})
	return payload


static func _validate_volume(volume: Variant) -> String:
	if not volume is Dictionary:
		return "primitive_fade_invalid_volume"
	var data: Dictionary = volume
	if data.get("type") == "circle":
		var center: Variant = data.get("center", null)
		if not center is Vector2 or not (center as Vector2).is_finite():
			return "primitive_fade_invalid_volume_center"
		if not _positive(data.get("radius", null)):
			return "primitive_fade_invalid_volume_radius"
		return ""
	if data.get("type") == "polygon":
		var points: Variant = data.get("points", null)
		if not points is PackedVector2Array:
			return "primitive_fade_invalid_volume_polygon"
		var packed: PackedVector2Array = points
		if packed.size() < 3:
			return "primitive_fade_invalid_volume_polygon"
		for point: Vector2 in packed:
			if not point.is_finite():
				return "primitive_fade_invalid_volume_polygon"
		## A collinear "polygon" still triangulates in this engine build,
		## so a near-zero signed area is the real degeneracy test.
		if Geometry2D.triangulate_polygon(packed).is_empty() or absf(_signed_area(packed)) <= 0.000001:
			return "primitive_fade_degenerate_volume_polygon"
		return ""
	return "primitive_fade_unknown_volume_type"


static func _positive(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) > 0.0
