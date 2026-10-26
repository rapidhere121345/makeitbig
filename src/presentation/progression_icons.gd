class_name ProgressionIcons
extends RefCounted
## R13 presentation reader: approved talent/law silhouettes on generated cloth.
##
## The pack is deliberately bounded: fifteen Ranger talent cells in content order,
## and the three law-token cells in the forge operation order. A missing or
## malformed package leaves every icon null and reports one explicit reason; this
## reader never generates, substitutes, or interprets art.

const ATLAS_DIRECTORY := "res://art/production/p1/ui_style_r13"
const TextureLoader := preload("res://src/presentation/art/texture_loader.gd")
const ATLAS_PATH := "res://art/production/p1/ui_style_r13/atlas.json"
const SCHEMA_VERSION := 1
const NATIVE_ICON_SIZE := Vector2i(32, 32)
const ICON_ANCHOR := Vector2i(16, 16)
const TALENT_TEXTURE_FILE := "ranger_talents.png"
const TALENT_TEXTURE_SIZE := Vector2i(480, 32)
const LAW_TEXTURE_FILE := "law_tokens.png"
const LAW_TEXTURE_SIZE := Vector2i(96, 32)
const FORGE_OPERATION_ORDER: Array[String] = ["inscribe", "rewrite", "refine"]

var pending_reason := ""

var _entries: Dictionary = {}
var _textures: Dictionary = {}
var _ready := false
var _icons: Dictionary = {}
static var _texture_cache: Dictionary = {}


func is_ready() -> bool:
	return _ready


func icon(canonical_id: String) -> Texture2D:
	if not _ready:
		return null
	if _icons.has(canonical_id):
		return _icons[canonical_id]
	var entry: Dictionary = _entries.get(canonical_id, {})
	if entry.is_empty():
		return null
	var texture_path := ATLAS_DIRECTORY.path_join(String(entry.get("texture", "")))
	var texture: Texture2D = _textures.get(texture_path, null)
	if texture == null:
		return null
	var rect: Array = entry.get("rect", [])
	if rect.size() != 4:
		return null
	var atlas := AtlasTexture.new()
	atlas.atlas = texture
	atlas.region = Rect2(float(rect[0]), float(rect[1]), float(rect[2]), float(rect[3]))
	_icons[canonical_id] = atlas
	return atlas


func load_icons() -> bool:
	pending_reason = ""
	_entries.clear()
	_textures.clear()
	_icons.clear()
	_ready = false
	var atlas := _parse_atlas(ATLAS_PATH)
	if atlas.is_empty():
		return false
	var sprites_value: Variant = atlas.get("sprites", {})
	if not sprites_value is Dictionary:
		pending_reason = "ASSETS PENDING: %s sprites must resolve to an id table" % ATLAS_PATH
		return false
	var sprites: Dictionary = sprites_value
	var required_ids := _required_ids()
	for entry_id in required_ids:
		var entry: Dictionary = sprites.get(entry_id, {})
		if entry.is_empty():
			pending_reason = "ASSETS PENDING: ui_style_r13 lacks %s" % entry_id
			return false
		if not _accept_entry(entry_id, entry):
			return false
		_entries[entry_id] = entry
	_ready = true
	return true


func _parse_atlas(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		pending_reason = "ASSETS PENDING: %s" % path
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		pending_reason = "ASSETS PENDING: cannot open %s" % path
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		pending_reason = "ASSETS PENDING: %s must be a JSON object" % path
		return {}
	var atlas: Dictionary = parsed
	if int(atlas.get("schema_version", 0)) != SCHEMA_VERSION:
		pending_reason = "ASSETS PENDING: %s must be a schema_version %d atlas" % [path, SCHEMA_VERSION]
		return {}
	var sprites: Variant = atlas.get("sprites", null)
	if not sprites is Array:
		pending_reason = "ASSETS PENDING: %s sprites must be an array" % path
		return {}
	var by_id := {}
	for raw_entry in sprites as Array:
		if not raw_entry is Dictionary:
			pending_reason = "ASSETS PENDING: %s sprites must contain objects" % path
			return {}
		var entry: Dictionary = raw_entry
		var entry_id := String(entry.get("id", ""))
		if entry_id.is_empty():
			pending_reason = "ASSETS PENDING: %s contains an unnamed sprite" % path
			return {}
		if by_id.has(entry_id):
			pending_reason = "ASSETS PENDING: %s publishes %s twice" % [path, entry_id]
			return {}
		by_id[entry_id] = entry
	atlas["sprites"] = by_id
	return atlas


func _required_ids() -> Array[String]:
	var registry := _new_talent_registry()
	var ids: Array[String] = []
	for tree_value in registry.catalog().trees:
		var tree: Dictionary = tree_value
		if String(tree.get("class_id", "")) != "ranger":
			continue
		for node_value in tree.get("nodes", []):
			ids.append("talent.%s" % String((node_value as Dictionary).get("id", "")))
	for operation in FORGE_OPERATION_ORDER:
		ids.append("law_token.%s" % operation)
	return ids


func _new_talent_registry() -> RefCounted:
	var registry: RefCounted = load("res://src/content/talent_registry.gd").new()
	return registry


func _accept_entry(entry_id: String, entry: Dictionary) -> bool:
	if String(entry.get("type", "")) != "ui_icon":
		pending_reason = "ASSETS PENDING: %s must be a ui_icon" % entry_id
		return false
	var is_law := entry_id.begins_with("law_token.")
	var expected_texture := LAW_TEXTURE_FILE if is_law else TALENT_TEXTURE_FILE
	var texture_name := String(entry.get("texture", ""))
	if texture_name != expected_texture:
		pending_reason = "ASSETS PENDING: %s must be cut from %s" % [entry_id, expected_texture]
		return false
	var rect: Variant = entry.get("rect", [])
	var anchor: Variant = entry.get("anchor", [])
	if not rect is Array or (rect as Array).size() != 4 or not anchor is Array or (anchor as Array).size() != 2:
		pending_reason = "ASSETS PENDING: %s requires integer rect[4]/anchor[2]" % entry_id
		return false
	if not _all_integers(rect as Array) or not _all_integers(anchor as Array):
		pending_reason = "ASSETS PENDING: %s requires integer rect[4]/anchor[2]" % entry_id
		return false
	var cell := Rect2i(int(rect[0]), int(rect[1]), int(rect[2]), int(rect[3]))
	if cell.size != NATIVE_ICON_SIZE or Vector2i(int(anchor[0]), int(anchor[1])) != ICON_ANCHOR:
		pending_reason = "ASSETS PENDING: %s violates the 32x32 / (16,16) icon contract" % entry_id
		return false
	var required_ids := _required_ids()
	var index := required_ids.find(entry_id)
	if is_law:
		index -= required_ids.size() - FORGE_OPERATION_ORDER.size()
	var expected_position := Vector2i(32 * index, 0)
	if cell.position != expected_position:
		pending_reason = "ASSETS PENDING: %s must occupy cell %s" % [entry_id, str(expected_position)]
		return false
	var texture_path := ATLAS_DIRECTORY.path_join(texture_name)
	if not _textures.has(texture_path):
		var texture := _load_texture(texture_path)
		if texture == null:
			return false
		_textures[texture_path] = texture
	var texture: Texture2D = _textures[texture_path]
	var expected_sheet := LAW_TEXTURE_SIZE if is_law else TALENT_TEXTURE_SIZE
	if texture.get_size() != Vector2(expected_sheet):
		pending_reason = "ASSETS PENDING: %s must be a %s sheet" % [texture_path, str(expected_sheet)]
		return false
	if cell.position.x < 0 or cell.position.y < 0 or cell.position.x + cell.size.x > expected_sheet.x or cell.position.y + cell.size.y > expected_sheet.y:
		pending_reason = "ASSETS PENDING: %s lies outside %s" % [entry_id, texture_name]
		return false
	return true


func _load_texture(path: String) -> Texture2D:
	if _texture_cache.has(path):
		return _texture_cache[path]
	# Source PNG is preferred during development; the imported resource keeps the
	# same cell readable in an exported package.
	var texture := TextureLoader.load_png_first(path)
	if texture == null:
		pending_reason = "ASSETS PENDING: missing %s" % path
		return null
	_texture_cache[path] = texture
	return texture


func _all_integers(values: Array) -> bool:
	for value in values:
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)) or float(value) != roundf(float(value)):
			return false
	return true
