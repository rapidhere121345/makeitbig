extends RefCounted
## Original dark-fantasy skill silhouettes; four stable action bindings.
## It exposes the four real combat-action cells as 32x32 atlas regions that the
## arena HUD draws at an integer 2x (64 display pixels). No icon, frame or state
## is generated here, and no gameplay value is derived from the art.

const ATLAS_PATH: String = "res://art/production/p1/world_polish_v01/combat_atlas.json"
const TextureLoader := preload("res://src/presentation/art/texture_loader.gd")
const ATLAS_DIRECTORY: String = "res://art/production/p1/world_polish_v01"
const NATIVE_ICON_SIZE := Vector2i(32, 32)
const DISPLAY_ICON_SIZE := Vector2i(64, 64)
const DISPLAY_SCALE: int = 2
const SLOT_ICON_IDS := {
	"piercing_arrow": "action.piercing_arrow",
	"hunter_mark": "action.hunter_mark",
	"dash": "action.dash",
	"basic_dodge": "action.basic_dodge",
}

var pending_reason: String = ""

var _entries: Dictionary = {}
var _textures: Dictionary = {}
var _ready := false
var _icons: Dictionary = {}
static var _texture_cache: Dictionary = {}


func is_ready() -> bool:
	return _ready


func icon(slot_id: String) -> Texture2D:
	if not _ready:
		return null
	if _icons.has(slot_id):
		return _icons[slot_id]
	var entry: Dictionary = _entries.get(slot_id, {})
	if entry.is_empty():
		return null
	var texture: Texture2D = _textures.get(String(entry.get("texture", "")))
	if texture == null:
		return null
	var rect: Array = entry.get("rect", [])
	if rect.size() != 4:
		return null
	var atlas := AtlasTexture.new()
	atlas.atlas = texture
	atlas.region = Rect2(float(rect[0]), float(rect[1]), float(rect[2]), float(rect[3]))
	_icons[slot_id] = atlas
	return atlas


func load_icons() -> bool:
	pending_reason = ""
	_entries.clear()
	_textures.clear()
	_icons.clear()
	_ready = false
	if not FileAccess.file_exists(ATLAS_PATH):
		pending_reason = "ASSETS PENDING: %s" % ATLAS_PATH
		return false
	var file := FileAccess.open(ATLAS_PATH, FileAccess.READ)
	if file == null:
		pending_reason = "ASSETS PENDING: cannot open %s" % ATLAS_PATH
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary or int((parsed as Dictionary).get("schema_version", 0)) != 1:
		pending_reason = "ASSETS PENDING: %s must be a schema_version 1 object" % ATLAS_PATH
		return false
	var sprites: Variant = (parsed as Dictionary).get("sprites", [])
	if not sprites is Array:
		pending_reason = "ASSETS PENDING: %s sprites must be an array" % ATLAS_PATH
		return false
	var by_id := {}
	for raw_entry in sprites as Array:
		if raw_entry is Dictionary and String((raw_entry as Dictionary).get("type", "")) == "ui_icon":
			by_id[String((raw_entry as Dictionary).get("id", ""))] = (raw_entry as Dictionary).duplicate(true)
	for slot_id in SLOT_ICON_IDS.keys():
		var entry: Dictionary = by_id.get(String(SLOT_ICON_IDS[slot_id]), {})
		if entry.is_empty():
			pending_reason = "ASSETS PENDING: world_polish_v01 lacks %s" % String(SLOT_ICON_IDS[slot_id])
			return false
		if not _validate_entry(String(SLOT_ICON_IDS[slot_id]), entry):
			return false
		_entries[String(slot_id)] = entry
	_ready = true
	return true


func _validate_entry(entry_id: String, entry: Dictionary) -> bool:
	var rect: Variant = entry.get("rect", [])
	var anchor: Variant = entry.get("anchor", [])
	if not rect is Array or (rect as Array).size() != 4 or not anchor is Array or (anchor as Array).size() != 2:
		pending_reason = "ASSETS PENDING: %s requires integer rect[4]/anchor[2]" % entry_id
		return false
	var cell := Rect2i(int(rect[0]), int(rect[1]), int(rect[2]), int(rect[3]))
	if cell.size != NATIVE_ICON_SIZE or Vector2i(int(anchor[0]), int(anchor[1])) != Vector2i(16, 16):
		pending_reason = "ASSETS PENDING: %s violates the 32x32 / (16,16) icon contract" % entry_id
		return false
	var texture_key := String(entry.get("texture", ""))
	if texture_key.is_empty():
		pending_reason = "ASSETS PENDING: %s has no texture" % entry_id
		return false
	if not _textures.has(texture_key):
		var texture := _load_texture(ATLAS_DIRECTORY.path_join(texture_key))
		if texture == null:
			return false
		_textures[texture_key] = texture
	var texture: Texture2D = _textures[texture_key]
	if not Rect2i(Vector2i.ZERO, texture.get_size()).encloses(cell):
		pending_reason = "ASSETS PENDING: %s lies outside %s" % [entry_id, texture_key]
		return false
	return true


func _load_texture(path: String) -> Texture2D:
	if _texture_cache.has(path):
		return _texture_cache[path]
	# Prefer the approved icon PNG bytes; fall back to the imported resource for
	# exported builds.
	var texture := TextureLoader.load_png_first(path)
	if texture == null:
		pending_reason = "ASSETS PENDING: missing %s" % path
		return null
	_texture_cache[path] = texture
	return texture
