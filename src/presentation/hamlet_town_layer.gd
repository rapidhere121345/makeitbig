class_name HamletTownLayer
extends Node2D
## Presentation-only connective tissue for the published hamlet layout.
##
## The atlas sprites remain the authority for buildings, residents and the two
## existing animation layers. This floor-level layer only supplies the lived-in
## connective tissue between those authored placements: a central commons, worn
## district routes, arrival fences, lantern posts and subtle work traces. It owns
## no interaction points, movement bounds, simulation state or save data.

const INK := Color("0b1117")
const EARTH := Color("5d4a38")
const COBBLE := Color("b6b3a2")
const COBBLE_DARK := Color("42515a")
const COPPER := Color("bb713d")
const COPPER_DULL := Color("896043")
const TIMBER := Color("6f5640")
const WARM := Color("e8a85e")
const EMBER := Color("d86f36")
const COLD := Color("9ab2b8")

## Secondary anchors are copied from the published hamlet_framing_v03 layout.
## They describe arrivals and existing boundary pieces; no facility placement is
## re-authored here. Keeping them static also preserves the fixture contract when
## only the five interaction entries are passed to configure().
const ARRIVAL_POINTS := {
	"north_tree": Vector2(431.0, 239.0),
	"northeast_pier": Vector2(780.0, 287.0),
	"east_fence": Vector2(846.0, 364.0),
	"southeast_pier": Vector2(832.0, 552.0),
	"south_pier": Vector2(500.0, 579.0),
	"west_pier": Vector2(252.0, 497.0),
}
const BOUNDARY_POINTS := {
	"north_fence": Vector2(570.0, 209.0),
	"east_fence": Vector2(846.0, 364.0),
	"southeast_pier": Vector2(832.0, 552.0),
	"southwest_fence": Vector2(298.0, 564.0),
	"west_pier": Vector2(252.0, 497.0),
	"far_west_fence": Vector2(91.0, 169.0),
}
const PATH_FEATURE_IDS := ["contract", "loadout", "forge", "training", "proxy"]
const COMMONS_TEXTURE: Texture2D = preload("res://art/production/p1/hamlet_commons_r13/hearth.png")
const COMMONS_SIZE := Vector2(144.0, 108.0)
const LANTERN_TEXTURE: Texture2D = preload("res://art/production/p1/hamlet_style_r13/lantern.png")

var _feature_points: Dictionary = {}
var _world_size := Vector2(1024.0, 640.0)
var _time := 0.0
var _scene_texture: Texture2D
var _layout: Dictionary = {}
var _scene_life: Node2D


func configure(entries: Array, world_size: Vector2, layout: Dictionary = {}, scene_texture: Texture2D = null) -> void:
	_layout = layout
	_scene_texture = scene_texture
	if _scene_life == null:
		_scene_life = SceneLife.new()
		_scene_life.name = "SceneLife"
		_scene_life.z_as_relative = false
		_scene_life.z_index = 3
		add_child(_scene_life)
	_scene_life._layout = layout
	_scene_life._world_size = world_size
	_scene_life.visible = scene_texture != null
	_feature_points.clear()
	for value: Variant in entries:
		if not value is Dictionary:
			continue
		var entry := value as Dictionary
		var feature_id := String(entry.get("id", ""))
		var feet: Variant = entry.get("feet", null)
		if not feature_id.is_empty() and feet is Vector2:
			_feature_points[feature_id] = feet
	_world_size = world_size
	queue_redraw()


func town_report() -> Dictionary:
	return {
		"ready": not _feature_points.is_empty(),
		"world_size": _world_size,
		"commons": _commons_point(),
		"connected_features": _feature_points.keys(),
		"animated": true,
		"scene_texture": String(_layout.get("scene_texture", "")),
		"source_size": _scene_texture.get_size() if _scene_texture != null else Vector2.ZERO,
		"commons_texture": String(_layout.get("scene_texture", COMMONS_TEXTURE.resource_path)),
		"lantern_feet": [] if _scene_texture != null else _lantern_points(_commons_point()).map(func(point: Vector2) -> Vector2: return point + Vector2(1, 7)),
		"effects": ["embers", "chimney_smoke", "snow", "water_glints"] if _scene_texture != null else [],
	}


func _ready() -> void:
	set_process(true)


func _process(delta: float) -> void:
	_time += maxf(0.0, delta)
	if _scene_life != null:
		_scene_life._time = _time
		_scene_life.queue_redraw()
	queue_redraw()


func _draw() -> void:
	if _world_size.x <= 0.0 or _world_size.y <= 0.0:
		return
	if not String(_layout.get("scene_texture", "")).is_empty():
		if _scene_texture != null:
			draw_texture_rect(_scene_texture, Rect2(Vector2.ZERO, _world_size), false)
		return
	var commons := _commons_point()
	_draw_district_ground(commons)
	_draw_paths(commons)
	_draw_commons(commons)
	_draw_boundary()
	_draw_lanterns(commons)
	_draw_work_traces()
	_draw_working_smoke()
	_draw_snow_motes()


func _commons_point() -> Vector2:
	if _layout.has("commons_uv"):
		return _uv_point(_layout.commons_uv)
	var hearth := _feature_point("hearth", Vector2(584.0, 402.0))
	return hearth + Vector2(0.0, 52.0)


func _uv_point(pair: Array) -> Vector2:
	return Vector2(float(pair[0]), float(pair[1])) * _world_size


func _feature_point(feature_id: String, fallback: Vector2) -> Vector2:
	var value: Variant = _feature_points.get(feature_id, fallback)
	return value as Vector2 if value is Vector2 else fallback


func _anchor_point(anchor_id: String) -> Vector2:
	var value: Variant = ARRIVAL_POINTS.get(anchor_id, BOUNDARY_POINTS.get(anchor_id, null))
	return value as Vector2 if value is Vector2 else _commons_point()


func _draw_district_ground(commons: Vector2) -> void:
	## Broad, low-opacity earth tones separate the inhabited middle basin from
	## the colder field without adding collision or hiding the authored ground.
	var west_district := (_feature_point("contract", commons)
		+ _feature_point("loadout", commons) + _feature_point("training", commons)) / 3.0
	var east_district := (_feature_point("forge", commons) + _feature_point("proxy", commons)) * 0.5
	_draw_soft_ellipse(commons + Vector2(-8.0, 4.0), Vector2(176.0, 108.0), Color(EARTH, 0.10))
	_draw_soft_ellipse(west_district, Vector2(146.0, 90.0), Color(EARTH, 0.08))
	_draw_soft_ellipse(east_district, Vector2(112.0, 78.0), Color(COBBLE_DARK, 0.07))


func _draw_paths(commons: Vector2) -> void:
	## Primary routes leave the commons in gaps left by the plaza stones. Secondary
	## lanes link neighbouring workplaces and the published arrivals, so the town
	## reads as districts rather than five spokes around one circle.
	for feature_id: String in PATH_FEATURE_IDS:
		_draw_worn_lane(commons, _feature_point(feature_id, commons), 1.0)
	_draw_worn_lane(_feature_point("contract", commons), _feature_point("loadout", commons), 0.62)
	_draw_worn_lane(_feature_point("loadout", commons), _feature_point("training", commons), 0.62)
	_draw_worn_lane(_feature_point("forge", commons), _feature_point("proxy", commons), 0.58)
	_draw_worn_lane(_feature_point("contract", commons), _anchor_point("north_tree"), 0.44)
	_draw_worn_lane(_feature_point("forge", commons), _anchor_point("northeast_pier"), 0.42)
	_draw_worn_lane(_feature_point("training", commons), _anchor_point("south_pier"), 0.44)
	_draw_worn_lane(_feature_point("loadout", commons), _anchor_point("west_pier"), 0.42)


func _draw_worn_lane(start: Vector2, finish: Vector2, strength: float) -> void:
	if start.is_equal_approx(finish):
		return
	var direction := (finish - start).normalized()
	var normal := direction.rotated(PI * 0.5)
	var bow := normal * clampf(start.distance_to(finish) * 0.07, 3.0, 11.0)
	var control_a := start + direction * 24.0 + bow
	var control_b := finish - direction * 24.0 + bow
	var segments := 5
	var previous := start
	for index in range(1, segments + 1):
		var point := start.bezier_interpolate(control_a, control_b, finish, float(index) / float(segments))
		draw_line(previous, point, Color(COBBLE_DARK, 0.08 * strength), 12.0 * strength, false)
		draw_line(previous + normal, point + normal, Color(EARTH, 0.04 * strength), 8.0 * strength, false)
		previous = point
	var stones := maxi(3, int(start.distance_to(finish) / 19.0))
	for index in range(1, stones):
		var point := start.bezier_interpolate(control_a, control_b, finish, float(index) / float(stones))
		var side := normal * (2.6 if index % 2 == 0 else -2.6)
		draw_line(point - normal * 4.2 + side, point + normal * 4.2 + side,
			Color(COBBLE, 0.10 + 0.06 * strength), 4.0, false)


func _draw_commons(center: Vector2) -> void:
	## Authored stone, timber and fire replace the flat concentric-circle marker.
	## Draw on the native viewport with nearest sampling; the source alpha and
	## original image are preserved. This landmark owns no collision or input.
	var pulse := 0.5 + 0.5 * sin(_time * 2.2)
	_draw_soft_ellipse(center + Vector2(0.0, 16.0), Vector2(172.0, 84.0), Color(INK, 0.16))
	_draw_soft_ellipse(center, Vector2(144.0, 78.0), Color(WARM, 0.06 + pulse * 0.025))
	draw_texture_rect(COMMONS_TEXTURE, Rect2(center - Vector2(72.0, 68.0), COMMONS_SIZE), false)
	# Small embers and the pool of light carry a presentation clock without
	# stretching the masonry or pretending this single sprite is a frame atlas.
	for index in range(4):
		var phase := fmod(_time * 0.55 + float(index) * 0.23, 1.0)
		var ember := center + Vector2(-5.0 + float(index) * 3.0, -36.0 - phase * 20.0)
		draw_rect(Rect2(ember.round(), Vector2.ONE), Color(WARM, 0.65 * (1.0 - phase)))


func _draw_boundary() -> void:
	## Small palisade shadows extend the existing fence and pier sprites toward
	## the travelled edge. Openings are intentionally left at the four arrival
	## directions instead of drawing a hard world border.
	for anchor_id: String in BOUNDARY_POINTS.keys():
		var point: Vector2 = BOUNDARY_POINTS[anchor_id]
		var direction := Vector2.from_angle((point - _commons_point()).angle() + PI * 0.5)
		for index in range(-2, 3):
			var post := point + direction * float(index) * 15.0
			draw_line(post + Vector2(0.0, 8.0), post + Vector2(0.0, -5.0),
				Color(COPPER_DULL, 0.30), 2.0, false)
		draw_line(point - direction * 31.0, point + direction * 31.0, Color(TIMBER, 0.11), 2.0, false)


func _draw_lanterns(center: Vector2) -> void:
	var points := _lantern_points(center)
	for index in points.size():
		var post: Vector2 = points[index]
		var pulse := 0.5 + 0.5 * sin(_time * 1.7 + float(index) * 0.63)
		_draw_soft_ellipse(post + Vector2(4.0, -20.0), Vector2(30.0, 24.0), Color(WARM, 0.055 + pulse * 0.025))
		draw_texture(LANTERN_TEXTURE, (post - Vector2(10.0, 43.0)).round())


func _lantern_points(center: Vector2) -> Array[Vector2]:
	return [
		center + Vector2(-90.0, -12.0),
		center + Vector2(86.0, -10.0),
		center + Vector2(-60.0, 68.0),
		center + Vector2(46.0, 68.0),
		_feature_point("contract", center) + Vector2(18.0, -10.0),
		_feature_point("loadout", center) + Vector2(-18.0, -10.0),
		_feature_point("forge", center) + Vector2(-20.0, -11.0),
		_feature_point("training", center) + Vector2(20.0, -10.0),
		_anchor_point("north_tree") + Vector2(18.0, 16.0),
		_anchor_point("west_pier") + Vector2(17.0, -12.0),
		_anchor_point("south_pier") + Vector2(-18.0, -12.0),
	]


func _draw_work_traces() -> void:
	var forge := _feature_point("forge", Vector2(764.0, 446.0))
	_draw_soft_ellipse(forge + Vector2(-14.0, 10.0), Vector2(34.0, 20.0), Color(INK, 0.13))
	for index in 7:
		var phase := fmod(_time * 0.55 + float(index) * 0.47, 1.0)
		var angle := -PI * 0.5 + sin(_time * 2.1 + float(index)) * 0.55
		var spark := forge + Vector2(-6.0, -21.0) + Vector2.from_angle(angle) * (6.0 + phase * 18.0)
		draw_circle(spark, 0.8, Color(EMBER, 0.24 * (1.0 - phase)))

	var training := _feature_point("training", Vector2(404.0, 508.0))
	_draw_soft_ellipse(training + Vector2(-18.0, 13.0), Vector2(56.0, 31.0), Color(EARTH, 0.13))
	for index in 3:
		var angle := PI * 0.72 + float(index) * 0.19
		var arc_center := training + Vector2(-14.0, -4.0)
		draw_arc(arc_center, 18.0 + float(index) * 3.0, angle, angle + 0.55, 9,
			Color(COBBLE, 0.08), 2.0, false)

	var loadout := _feature_point("loadout", Vector2(332.0, 442.0))
	for index in 4:
		var offset := Vector2(-28.0 + float(index) * 17.0, 14.0 + float(index % 2) * 7.0)
		draw_line(loadout + offset, loadout + offset + Vector2(12.0, 0.0), Color(TIMBER, 0.14), 2.0, false)
		draw_line(loadout + offset + Vector2(1.0, -4.0), loadout + offset + Vector2(11.0, -4.0),
			Color(COBBLE, 0.10), 1.0, false)

	var contract := _feature_point("contract", Vector2(304.0, 337.0))
	for index in 5:
		var scrap := contract + Vector2(-20.0 + float(index) * 9.0, 20.0 + sin(float(index) * 1.7) * 3.0)
		draw_rect(Rect2(scrap.round(), Vector2(2.0, 3.0)), Color(COBBLE, 0.16))
	draw_line(contract + Vector2(-26.0, 12.0), contract + Vector2(-14.0, 17.0), Color(EARTH, 0.10), 2.0, false)

	var proxy := _feature_point("proxy", Vector2(716.0, 518.0))
	_draw_soft_ellipse(proxy + Vector2(0.0, 16.0), Vector2(44.0, 22.0), Color(COBBLE_DARK, 0.11))
	for index in 4:
		var ripple := fmod(_time * 0.24 + float(index) * 0.25, 1.0)
		draw_arc(proxy + Vector2(0.0, 8.0), 9.0 + ripple * 22.0, PI * 0.08, PI * 0.92, 14,
			Color(COLD, 0.07 * (1.0 - ripple)), 2.0, false)


func _draw_soft_ellipse(center: Vector2, size: Vector2, color: Color) -> void:
	var steps := 40
	var previous := center + Vector2(size.x, 0.0)
	for index in range(1, steps + 1):
		var angle := TAU * float(index) / float(steps)
		var point := center + Vector2(cos(angle) * size.x, sin(angle) * size.y)
		draw_line(previous, point, color, 26.0, false)
		previous = point


func _draw_working_smoke() -> void:
	for record in [
		{"point": _feature_point("forge", Vector2(764.0, 446.0)) + Vector2(0.0, -42.0), "phase": 0.0},
		{"point": _feature_point("hearth", Vector2(584.0, 402.0)) + Vector2(0.0, -48.0), "phase": 1.8},
	]:
		var origin: Vector2 = record["point"]
		var phase: float = record["phase"]
		for index in 4:
			var progress := fmod(_time * 0.32 + phase + float(index) * 0.25, 1.0)
			var drift := sin(_time * 0.75 + phase + float(index)) * 5.0
			var position := origin + Vector2(drift, -progress * 30.0 - float(index) * 3.0)
			draw_circle(position, 1.1 + progress * 1.8, Color(COLD, 0.14 * (1.0 - progress)))


func _draw_snow_motes() -> void:
	var points: Array[Vector2] = [
		Vector2(128.0, 112.0), Vector2(278.0, 214.0), Vector2(816.0, 142.0),
		Vector2(892.0, 338.0), Vector2(174.0, 506.0), Vector2(744.0, 556.0),
	]
	for index in points.size():
		var base: Vector2 = points[index]
		var phase := fmod(_time * (0.18 + float(index % 3) * 0.04) + float(index) * 0.17, 1.0)
		var position := base + Vector2(sin(_time * 0.45 + float(index)) * 3.0, phase * 12.0)
		draw_rect(Rect2(position.round(), Vector2(2.0, 2.0)), Color(COLD, 0.20))


class SceneLife:
	extends Node2D
	var _layout: Dictionary = {}
	var _world_size := Vector2(1024, 640)
	var _time := 0.0

	func _uv_point(pair: Array) -> Vector2:
		return Vector2(float(pair[0]), float(pair[1])) * _world_size

	func _draw() -> void:
		# Only small movement over the authored image; no extra road, building,
		# lantern, masonry or flame sprite is layered over the continuous scene.
		var effects: Dictionary = _layout.get("effects", {})
		var hearth := _uv_point(effects.get("embers_uv", [0.5, 0.5]))
		for index in 5:
			var phase := fposmod(_time * 0.55 + index * 0.19, 1.0)
			var point := hearth + Vector2(sin(phase * 4.0 + index) * 5.0, -phase * 24.0)
			draw_rect(Rect2(point, Vector2.ONE), Color(WARM, (1.0 - phase) * 0.55))
		var chimney := _uv_point(effects.get("smoke_uv", [0.75, 0.06]))
		for index in 4:
			var phase := fposmod(_time * 0.13 + index * 0.25, 1.0)
			var point := chimney + Vector2(phase * 9.0 + sin(phase * 5.0) * 3.0, -phase * 28.0)
			draw_circle(point, 2.0 + phase * 5.0, Color(COLD, 0.09 * (1.0 - phase)))
		for index in 22:
			var point := Vector2(fposmod(index * 83.0 + _time * 2.5, _world_size.x), fposmod(index * 47.0 + _time * 6.0, _world_size.y))
			draw_rect(Rect2(point, Vector2.ONE), Color(COLD, 0.16))
		var water: Array = effects.get("water_uv", [])
		for index in water.size():
			var point := _uv_point(water[index])
			var alpha := 0.05 + 0.07 * (0.5 + 0.5 * sin(_time * 1.4 + index * 2.0))
			draw_line(point, point + Vector2(7.0, 0.0), Color(COLD, alpha), 1.0)


