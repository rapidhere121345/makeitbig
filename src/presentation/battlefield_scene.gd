class_name BattlefieldScene
extends RefCounted

## Terrain presentation reads the validated native scene's polygons and feet.
## The very same shapes bake into movement/projectile surfaces. Complete
## generated environment plates supply the visible terrain; native sources
## retain authority over collision and sockets. Reused structure sprites
## keep their production anchors; no painted shape becomes collision authority.
const Geometry := preload("res://src/core/geometry/arena_geometry.gd")
const JsonIO := preload("res://src/core/json_io.gd")
const ArtSets := preload("res://src/presentation/art/art_sets.gd")
const IDS: Array[String] = Geometry.BATTLEFIELDS
const MATERIAL_PACK := ArtSets.BATTLEFIELDS_V01 + "/assets.json"
var pending_reason := ""
var _fields: Dictionary = {}
var _textures: Dictionary = {}


func load_assets(catalog: RoomCatalog) -> bool:
	_fields.clear()
	_textures.clear()
	pending_reason = ""
	if catalog == null:
		return _fail("missing room catalog")
	if not _load_materials():
		return false
	for id: String in IDS:
		var resolved := catalog.resolve({"layout_id": id})
		if not bool(resolved.get("ok", false)):
			return _fail("missing layout " + id)
		var packed := load(String(resolved.world_scene_path)) as PackedScene
		if packed == null:
			return _fail("missing native scene " + id)
		var instance := packed.instantiate()
		var source := instance.get_node_or_null("RoomAsset") as RoomAssetRoot
		if source == null:
			instance.free()
			return _fail("missing room asset " + id)
		var checked := source.validate_contract({"layout_id": id})
		if not bool(checked.ok):
			instance.free()
			return _fail("invalid native scene " + id)
		var terrain: Array[Dictionary] = []
		var structures: Array[Dictionary] = []
		for node: Polygon2D in source.get_node("GeometrySources/Static").get_children():
			var binding := String(node.get_meta("binding_id", ""))
			if binding.begins_with("combat/terrain/"):
				var points := PackedVector2Array()
				for point: Vector2 in node.polygon:
					points.append(point + node.position)
				terrain.append({"binding_id": binding, "kind": binding.trim_prefix("combat/terrain/").get_slice("/", 0), "points": points})
			elif binding.begins_with("combat/structure/"):
				var sprite := binding.trim_prefix("combat/structure/").get_slice("#", 0)
				structures.append({"id": sprite, "feet": [node.position.x, node.position.y]})
		_fields[id] = {
			"bounds": source.arena_rect, "terrain": terrain, "structures": structures,
			"spawn": (source.get_node("Sockets/CombatSpawn") as Marker2D).position,
			"skin": id, "source_scene": String(resolved.world_scene_path),
		}
		instance.free()
	return true


func _load_materials() -> bool:
	_textures.clear()
	var read := JsonIO.read_result(MATERIAL_PACK, "battlefield_materials")
	if not bool(read.get("ok", false)):
		return _fail("missing material pack")
	var pack: Dictionary = read.data
	if not pack.get("assets", null) is Dictionary or not (pack.get("pending", []) as Array).is_empty():
		return _fail("incomplete material pack")
	var required: Array[String] = IDS.duplicate()
	for id: String in IDS:
		required.append(id + "_extension")
	for id: String in required:
		var entry: Dictionary = (pack.assets as Dictionary).get(id, {})
		var path := String(entry.get("path", ""))
		if String(entry.get("status", "")) != "packed" or not path.begins_with(ArtSets.BATTLEFIELDS_V01 + "/"):
			return _fail("unpacked material " + id)
		var expected := Vector2(1536, 1024) if id.ends_with("_extension") else Vector2(1024, 640)
		var texture := load(path) as Texture2D
		if texture == null or texture.get_size() != expected:
			return _fail("invalid material canvas " + id)
		if FileAccess.file_exists(path) and FileAccess.get_sha256(path) != String(entry.get("sha256", "")):
			return _fail("material hash mismatch " + id)
		_textures[id] = texture
	return true


func _fail(reason: String) -> bool:
	pending_reason = "ASSETS PENDING: battlefield " + reason
	_fields.clear()
	_textures.clear()
	return false


func has_layout(id: String) -> bool:
	return _fields.has(id)


func floor_texture(id: String) -> Texture2D:
	return _textures.get(id, null) as Texture2D


func extension_texture(id: String) -> Texture2D:
	return _textures.get(id + "_extension", null) as Texture2D


func report(id: String) -> Dictionary:
	return (_fields.get(id, {}) as Dictionary).duplicate(true)


func structures(id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Dictionary in (_fields.get(id, {}) as Dictionary).get("structures", []):
		if String(entry.id) != "tower":
			result.append(entry.duplicate(true))
	return result


func tower_feet(id: String) -> Vector2:
	for entry: Dictionary in (_fields.get(id, {}) as Dictionary).get("structures", []):
		if String(entry.id) == "tower":
			return Vector2(float(entry.feet[0]), float(entry.feet[1]))
	return Vector2.ZERO

