extends RefCounted
## Ankle-height ground dressing only. No registry, collision, sorting, input or
## simulation authority. Drawn below actors, telegraphs and authored scenery.
const Definition := preload("res://src/runtime/world/environment_object_definition.gd")
const Grounding := preload("res://src/presentation/grounding_effects.gd")
const ASSETS := "res://art/production/p1/world_polish_v01/assets.json"
const PLACEMENTS := "res://content/presentation/world_dressing.json"
const FAMILIES := ["fern", "mushrooms", "votives", "relic"]
var pending_reason := ""
var _assets: Dictionary = {}
var _textures: Dictionary = {}
var _scenes: Dictionary = {}

class GroundLayer extends Node2D:
	var pack: RefCounted
	var scene_id := "town"
	func _draw() -> void:
		if pack != null:
			pack.draw_floor(self, scene_id, Rect2(0, 0, 1536, 960))

func load_assets() -> bool:
	pending_reason = ""
	_assets.clear()
	_textures.clear()
	_scenes.clear()
	for path: String in [ASSETS, PLACEMENTS]:
		if not FileAccess.file_exists(path):
			return _fail("missing " + path)
	var asset_data: Variant = JSON.parse_string(FileAccess.get_file_as_string(ASSETS))
	var placement_data: Variant = JSON.parse_string(FileAccess.get_file_as_string(PLACEMENTS))
	if not asset_data is Dictionary or not placement_data is Dictionary:
		return _fail("invalid manifest")
	if int(asset_data.get("schema_version", 0)) != 1 or int(placement_data.get("schema_version", 0)) != 1:
		return _fail("unsupported manifest version")
	var entries: Dictionary = asset_data.get("assets", {})
	for family: String in FAMILIES:
		var entry: Dictionary = entries.get(family, {})
		var texture: Texture2D = Definition.read_texture(String(entry.get("path", "")))
		var size: Array = entry.get("canvas", [])
		var anchor: Array = entry.get("anchor", [])
		if texture == null or size.size() != 2 or anchor.size() != 2:
			return _fail("invalid asset " + family)
		if texture.get_size() != Vector2(float(size[0]), float(size[1])):
			return _fail("canvas mismatch " + family)
		_assets[family] = entry
		_textures[family] = texture
	var scenes: Dictionary = placement_data.get("scenes", {})
	for scene_id: String in ["town", "arena"]:
		var rows: Array = scenes.get(scene_id, [])
		if rows.is_empty() or rows.size() > 64:
			return _fail("invalid placement count " + scene_id)
		var ids := {}
		var bounds := Rect2(0, 0, 1536, 960) if scene_id == "town" else Rect2(0, 0, 1024, 640)
		for row: Dictionary in rows:
			var id := String(row.get("id", ""))
			var family := String(row.get("family", ""))
			var feet: Array = row.get("feet", [])
			if id.is_empty() or ids.has(id) or not _assets.has(family) or feet.size() != 2:
				return _fail("invalid placement " + id)
			ids[id] = true
			var entry: Dictionary = _assets[family]
			var cell := Rect2(Vector2(float(feet[0]), float(feet[1])) - Vector2(float(entry.anchor[0]), float(entry.anchor[1])), Vector2(float(entry.canvas[0]), float(entry.canvas[1])))
			if not bounds.encloses(cell):
				return _fail("placement outside ground " + id)
		_scenes[scene_id] = rows.duplicate(true)
	return true

func _fail(reason: String) -> bool:
	pending_reason = "ASSETS PENDING: world dressing " + reason
	_assets.clear()
	_textures.clear()
	_scenes.clear()
	return false

func create_town_layer() -> Node2D:
	var layer := GroundLayer.new()
	layer.name = "WorldDressing"
	layer.pack = self
	layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return layer

func draw_floor(canvas: CanvasItem, scene_id: String, region: Rect2) -> void:
	for row: Dictionary in _scenes.get(scene_id, []):
		var family := String(row.family)
		var entry: Dictionary = _assets[family]
		var top_left := Vector2(float(row.feet[0]), float(row.feet[1])) - Vector2(float(entry.anchor[0]), float(entry.anchor[1]))
		var texture: Texture2D = _textures[family]
		if region.intersects(Rect2(top_left, texture.get_size())):
			Grounding.draw_dressing(canvas, texture, Vector2(float(entry.anchor[0]), float(entry.anchor[1])), Vector2(float(row.feet[0]), float(row.feet[1])), family)

func report(scene_id: String) -> Dictionary:
	return {"ready": pending_reason.is_empty() and not _scenes.is_empty(),
		"count": (_scenes.get(scene_id, []) as Array).size(), "layer": "ground",
		"collision_bodies": 0, "placements": (_scenes.get(scene_id, []) as Array).duplicate(true)}
