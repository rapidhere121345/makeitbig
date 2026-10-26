extends RefCounted
## Read-only reader for the three production art packages the facility pages
## draw: the approved 24-icon base batch (early_loop_v01), the six-cell
## readability overlay (equipment_readability_v02) and the hamlet facility marks
## (hamlet_concept_v02). Nothing is generated here: every texture is one integer
## rect of a published sheet, addressed by the canonical id that the package
## catalog names, never by position or by resemblance.
##
## Contract:
##   icon(canonical_id) -> AtlasTexture over the 32x32 cell, or null.
##   mark(facility_id)  -> AtlasTexture over the published facility cell, or null.
## A null never has a substitute drawn in its place; the caller keeps its own
## text and reports the missing id, so a wrong mapping can never masquerade as
## another object. Quality, lock state and equipped state are never baked into
## an icon: they stay layout and copy owned by the screen.
##
## Priority is one bounded layer deep: the overlay repaints exactly the six ids
## it pins and nothing else, so a reshuffled or padded package cannot reach an id
## the pin does not name. A package that is missing, short, reordered, moved or
## otherwise off-contract keeps the whole module unready and serves no icon at
## all instead of drawing the superseded cell: the superseded pixels are not a
## valid substitute.

const ICON_ATLAS_PATH: String = "res://art/production/p1/early_loop_v01/atlas.json"
const TextureLoader := preload("res://src/presentation/art/texture_loader.gd")
const ICON_ATLAS_DIRECTORY: String = "res://art/production/p1/early_loop_v01"
const MARK_ATLAS_PATH: String = "res://art/production/p1/hamlet_style_r13/atlas.json"

## Native cell contract of the icon batch, and the one display scale this module
## permits. 2x is an integer step, so a 32px cell reaches 64 display pixels with
## no resampling; the facility marks are drawn at their published size.
const ICON_NATIVE_SIZE := Vector2i(32, 32)
const ICON_DISPLAY_SIZE := Vector2i(64, 64)
const ICON_DISPLAY_SCALE: int = 2

## The bounded overlay package: six reviewed equipment-readability cells. Its
## directory, canvas, texture name, cell order and anchor are pinned here, and
## the atlas on disk has to agree with every one of them.
const OVERRIDE_DIRECTORY: String = "res://art/production/p1/equipment_readability_v02"
const OVERRIDE_ATLAS_FILE: String = "atlas.json"
const OVERRIDE_TEXTURE_ID: String = "overrides"
const OVERRIDE_TEXTURE_FILE: String = "overrides.png"
const OVERRIDE_CANVAS := Vector2i(96, 64)
const OVERRIDE_ANCHOR := Vector2i(16, 16)
## The one published order. `id` is the prefixed key the icon table already uses,
## `canonical_id` is the bare item/slot id the runtime names, and `cell` is the
## top-left corner of that id's 32x32 cell on the overrides canvas.
const OVERRIDE_ENTRIES: Array[Dictionary] = [
	{"id": "equipment.lineage_quiver", "canonical_id": "lineage_quiver", "cell": Vector2i(0, 0)},
	{"id": "equipment.farwatch_quiver", "canonical_id": "farwatch_quiver", "cell": Vector2i(32, 0)},
	{"id": "equipment.turnfeather_gloves", "canonical_id": "turnfeather_gloves", "cell": Vector2i(64, 0)},
	{"id": "equipment.piercer_gloves", "canonical_id": "piercer_gloves", "cell": Vector2i(0, 32)},
	{"id": "equipment_slot.off_hand", "canonical_id": "off_hand", "cell": Vector2i(32, 32)},
	{"id": "equipment_slot.gloves", "canonical_id": "gloves", "cell": Vector2i(64, 32)},
]

## id prefix per entry group. Equipment slots and item bases carry their
## canonical id on its own; runes, laws and proxy cores are prefixed.
const ENTRY_PREFIXES: Dictionary = {
	"equipment_slot": "equipment_slot.%s",
	"equipment_base": "equipment.%s",
	"rune": "rune.%s",
	"law": "law.%s",
	"proxy_core": "core.%s",
}

const FACILITY_KEYS: Dictionary = {
	"contract": "contract",
	"loadout": "loadout",
	"forge": "forge",
	"training": "training",
	"proxy": "proxy",
}

var pending_reason: String = ""

## The package directory the overlay pin is read from; it defaults to the
## published path. Pointing it elsewhere is how a caller proves that a missing or
## off-contract package leaves this module unready instead of falling back.
var override_directory: String = OVERRIDE_DIRECTORY

var _entries: Dictionary = {}
var _marks: Dictionary = {}
var _textures: Dictionary = {}
var _missing_ids: Array[String] = []
var _ready := false


func is_ready() -> bool:
	return _ready


## Canonical ids the load-time contract requires; every one must resolve or the
## module stays unready instead of drawing a partial set.
func required_ids() -> Array[String]:
	var ids: Array[String] = []
	for kind in ENTRY_PREFIXES:
		var table := _canonical_table(String(kind))
		for id: String in table:
			ids.append(String(table[id]))
	return ids


## Published facility keys this module can mark. A facility page outside this
## list keeps its text header and draws no mark.
func mark_keys() -> Array[String]:
	return FACILITY_KEYS.keys()


## Every canonical id that was asked for and is not in the published package,
## in first-request order, with duplicates removed.
func missing_ids() -> Array[String]:
	return _missing_ids.duplicate()


func canonical_id(kind: String, local_id: String) -> String:
	var template := String(ENTRY_PREFIXES.get(kind, "%s"))
	var normalized := local_id.strip_edges()
	if normalized.is_empty():
		return ""
	if template == "%s":
		return normalized
	return template % normalized


## The 32x32 cell for a canonical id, or null when nothing is published under it.
## A pinned id resolves through the overlay, every other id through the base
## batch: there is no third source and no positional fallback.
func icon(canonical: String) -> Texture2D:
	var normalized := canonical.strip_edges()
	if normalized.is_empty():
		return null
	if not _entries.has(normalized):
		_note_missing(normalized)
		return null
	return _region(_entries[normalized])


## The published facility cell for a page id (`contract`, `forge`, or a screen
## title such as "forge / destiny forge"). Unknown pages return null.
func mark(facility_id: String) -> Texture2D:
	var key := facility_key(facility_id)
	if key.is_empty() or not _marks.has(key):
		return null
	return _region(_marks[key])


func mark_size(facility_id: String) -> Vector2i:
	var key := facility_key(facility_id)
	if key.is_empty() or not _marks.has(key):
		return Vector2i.ZERO
	var rect: Array = _marks[key].get("rect", [])
	if rect.size() != 4:
		return Vector2i.ZERO
	return Vector2i(int(rect[2]), int(rect[3]))


## Accepts both the route id and a screen title, so the caller never has to keep
## a second copy of the route list in sync with this module.
func facility_key(facility_id: String) -> String:
	var normalized := facility_id.strip_edges().to_lower()
	if normalized.is_empty():
		return ""
	if FACILITY_KEYS.has(normalized):
		return normalized
	for segment in normalized.split("/", false):
		var token := String(segment).strip_edges()
		if FACILITY_KEYS.has(token):
			return token
	return ""


func load_art() -> bool:
	pending_reason = ""
	_reset()
	# One layered read: base batch, then the bounded overlay, then the marks. A
	# failure anywhere serves nothing at all - no partial set, no superseded cell
	# - so a broken package can never masquerade as published art.
	if not (_load_icon_atlas() and _load_override_atlas() and _load_mark_atlas() and _verify_required_ids()):
		_reset()
		return false
	_ready = true
	return true


## A load publishes the complete set or nothing: the caches are emptied on the
## way in and on the way out, so no lookup can ever read a stale record.
func _reset() -> void:
	_entries.clear()
	_marks.clear()
	_textures.clear()
	_missing_ids.clear()
	_ready = false


## The canonical id table as published by the package catalog: type keys are the
## package's own role/type words, and each one names the atlas id it resolves to.
func _canonical_table(kind: String) -> Dictionary:
	const SLOTS: Array[String] = ["main_hand", "off_hand", "gloves", "ring_1"]
	const BASES: Array[String] = [
		"ashwood_longbow", "swift_recurve_bow", "lineage_quiver", "farwatch_quiver",
		"turnfeather_gloves", "piercer_gloves", "hawk_eye_ring", "vitality_ring",
	]
	const RUNES: Array[String] = ["breeding_split", "branch_scale", "afterimage_extension"]
	const LAWS: Array[String] = ["pack_hunt_mark"]
	const CORES: Array[String] = [
		"near_enemy_horizon", "direct_gait", "single_key_execution", "short_trace_memory",
	]
	match kind:
		"equipment_slot":
			return _mapped("equipment_slot", SLOTS)
		"equipment_base":
			return _mapped("equipment", BASES)
		"rune":
			return _mapped("rune", RUNES)
		"law":
			return _mapped("law", LAWS)
		"proxy_core":
			return _mapped("core", CORES)
	return {}


func _mapped(prefix: String, local_ids: Array[String]) -> Dictionary:
	var table := {}
	for local_id in local_ids:
		table[local_id] = "%s.%s" % [prefix, local_id]
	return table


func _load_icon_atlas() -> bool:
	var atlas := _parse_atlas(ICON_ATLAS_PATH)
	if atlas.is_empty():
		return false
	var textures := _atlas_texture_paths(atlas, ICON_ATLAS_DIRECTORY, true)
	if textures.is_empty():
		pending_reason = "ASSETS PENDING: %s declares no texture table" % ICON_ATLAS_PATH
		return false
	var sprites: Variant = atlas.get("sprites", [])
	var listed: Array = sprites if sprites is Array else []
	for raw_entry in listed:
		if not raw_entry is Dictionary:
			continue
		var entry: Dictionary = raw_entry
		if String(entry.get("type", "")) != "ui_icon":
			continue
		# The published id is the prefixed map key (`equipment_slot.main_hand`);
		# `canonical_id` is only the bare content id and is null for a cell that
		# exists in art but has no canonical content counterpart yet.
		var canonical := str(entry.get("id", "")).strip_edges()
		if canonical.is_empty() or str(entry.get("canonical_id", null)).is_empty():
			continue
		var texture_key := str(entry.get("texture", ""))
		var texture_path := str(textures.get(texture_key, ""))
		if texture_path.is_empty():
			pending_reason = "ASSETS PENDING: %s names an undeclared texture '%s'" % [canonical, texture_key]
			return false
		var record := _accept_entry(canonical, entry, texture_path)
		if record.is_empty():
			return false
		_entries[canonical] = record
	return true


## The bounded priority layer. The six pinned ids are the only cells this package
## may repaint: each one exactly once, in the pinned order, on the pinned cell,
## with the bare canonical id and the canonical cell-centre anchor, cut from the
## one texture the table declares and the base batch already publishes. Anything
## else - an absent package, a different count, a renamed or extra id, a moved or
## resized cell, an undeclared texture, a sheet that is not the published canvas
## - records the reason and refuses the whole load, so the superseded cell can
## never quietly stand in for the reviewed one.
func _load_override_atlas() -> bool:
	var package := _override_package()
	var atlas_path := package.path_join(OVERRIDE_ATLAS_FILE)
	var atlas := _parse_atlas(atlas_path)
	if atlas.is_empty():
		return false
	var sprites: Variant = atlas.get("sprites", [])
	if not sprites is Array:
		pending_reason = "ASSETS PENDING: %s sprites must be an array" % atlas_path
		return false
	var listed: Array = sprites
	if listed.size() != OVERRIDE_ENTRIES.size():
		pending_reason = "ASSETS PENDING: %s publishes %d override cells instead of %d" % [atlas_path, listed.size(), OVERRIDE_ENTRIES.size()]
		return false
	var texture_path := package.path_join(OVERRIDE_TEXTURE_FILE)
	var texture_table: Variant = atlas.get("textures", [])
	if not texture_table is Array or texture_table.size() != 1:
		pending_reason = "ASSETS PENDING: %s must declare exactly one override texture" % atlas_path
		return false
	var declared := _atlas_texture_paths(atlas, package, true)
	if str(declared.get(OVERRIDE_TEXTURE_ID, "")) != texture_path or str(declared.get(OVERRIDE_TEXTURE_FILE, "")) != texture_path:
		pending_reason = "ASSETS PENDING: %s must declare texture '%s' as %s" % [atlas_path, OVERRIDE_TEXTURE_ID, OVERRIDE_TEXTURE_FILE]
		return false
	var sheet := _load_texture(texture_path)
	if sheet == null:
		return false
	if Vector2i(sheet.get_size()) != OVERRIDE_CANVAS:
		pending_reason = "ASSETS PENDING: %s is %s, not the published %s override canvas" % [texture_path, str(Vector2i(sheet.get_size())), str(OVERRIDE_CANVAS)]
		return false
	var served: Dictionary = {}
	for index in listed.size():
		var pin: Dictionary = OVERRIDE_ENTRIES[index]
		var entry_id := String(pin["id"])
		var entry_value: Variant = listed[index]
		if not entry_value is Dictionary:
			pending_reason = "ASSETS PENDING: %s cell %d must be an object" % [atlas_path, index]
			return false
		var entry: Dictionary = entry_value
		if str(entry.get("id", "")).strip_edges() != entry_id:
			pending_reason = "ASSETS PENDING: %s cell %d must be %s, not '%s'" % [atlas_path, index, entry_id, str(entry.get("id", ""))]
			return false
		if served.has(entry_id):
			pending_reason = "ASSETS PENDING: %s publishes %s twice" % [atlas_path, entry_id]
			return false
		if not _entries.has(entry_id):
			pending_reason = "ASSETS PENDING: %s overrides %s, which the base batch does not publish" % [atlas_path, entry_id]
			return false
		if String(entry.get("type", "")) != "ui_icon":
			pending_reason = "ASSETS PENDING: %s must be a ui_icon, not '%s'" % [entry_id, str(entry.get("type", ""))]
			return false
		var canonical := str(entry.get("canonical_id", "")).strip_edges()
		if canonical != String(pin["canonical_id"]) or canonical.contains("."):
			pending_reason = "ASSETS PENDING: %s must carry the bare canonical id '%s', not '%s'" % [entry_id, String(pin["canonical_id"]), canonical]
			return false
		if str(entry.get("texture", "")) != OVERRIDE_TEXTURE_FILE:
			pending_reason = "ASSETS PENDING: %s must be cut from %s, not '%s'" % [entry_id, OVERRIDE_TEXTURE_FILE, str(entry.get("texture", ""))]
			return false
		var cell: Vector2i = pin["cell"]
		if not Rect2i(Vector2i.ZERO, OVERRIDE_CANVAS).encloses(Rect2i(cell, ICON_NATIVE_SIZE)):
			pending_reason = "ASSETS PENDING: %s does not lie inside the published %s canvas" % [entry_id, str(OVERRIDE_CANVAS)]
			return false
		if not _rect_is_cell(entry.get("rect", null), cell):
			pending_reason = "ASSETS PENDING: %s must occupy the published cell %s" % [entry_id, str(cell)]
			return false
		if not _anchor_is_cell_centre(entry.get("anchor", null)):
			pending_reason = "ASSETS PENDING: %s must anchor at the canonical cell centre %s" % [entry_id, str(OVERRIDE_ANCHOR)]
			return false
		var record := _accept_entry(entry_id, entry, texture_path)
		if record.is_empty():
			return false
		record["override"] = true
		_entries[entry_id] = record
		served[entry_id] = true
	return true


## The published rect of one pinned cell: the pinned corner plus the native cell
## size, spelled the way the atlas spells it ([x, y, w, h]).
func _rect_is_cell(rect: Variant, cell: Vector2i) -> bool:
	if not rect is Array:
		return false
	var listed: Array = rect
	if listed.size() != 4:
		return false
	return _exact_coordinates(listed, [cell.x, cell.y, ICON_NATIVE_SIZE.x, ICON_NATIVE_SIZE.y])


## The anchor of a published cell is its centre, and the overlay may not move it:
## a cell cannot be re-anchored in the overlay and not in the base batch.
func _anchor_is_cell_centre(anchor: Variant) -> bool:
	if OVERRIDE_ANCHOR * 2 != ICON_NATIVE_SIZE:
		return false
	if not anchor is Array:
		return false
	var listed: Array = anchor
	return _exact_coordinates(listed, [OVERRIDE_ANCHOR.x, OVERRIDE_ANCHOR.y])


## JSON numbers may decode as floats, but truncating a fraction, string or bool
## would accept a moved cell and then draw the untruncated value in _region().
func _exact_coordinates(values: Array, expected: Array) -> bool:
	if values.size() != expected.size():
		return false
	for index in values.size():
		if not (values[index] is int or values[index] is float):
			return false
		if values[index] != expected[index]:
			return false
	return true


func _override_package() -> String:
	var directory := override_directory.strip_edges()
	return OVERRIDE_DIRECTORY if directory.is_empty() else directory


func _load_mark_atlas() -> bool:
	var atlas := _parse_atlas(MARK_ATLAS_PATH)
	if atlas.is_empty():
		return false
	var textures := _atlas_texture_paths(atlas, "", false)
	var sprites: Variant = atlas.get("sprites", {})
	if not sprites is Dictionary:
		pending_reason = "ASSETS PENDING: %s facility sprites must be an object" % MARK_ATLAS_PATH
		return false
	var listed: Dictionary = sprites
	for key in listed:
		var atlas_id := String(key)
		if not atlas_id.begins_with("facility."):
			continue
		var facility_key_name := atlas_id.trim_prefix("facility.")
		if not FACILITY_KEYS.has(facility_key_name):
			continue
		var entry_value: Variant = listed[key]
		if not entry_value is Dictionary:
			pending_reason = "ASSETS PENDING: %s %s must be an object" % [MARK_ATLAS_PATH, atlas_id]
			return false
		var entry: Dictionary = entry_value
		var texture_key := str(entry.get("texture", ""))
		var texture_path := str(textures.get(texture_key, ""))
		if texture_path.is_empty():
			pending_reason = "ASSETS PENDING: %s names an undeclared texture '%s'" % [atlas_id, texture_key]
			return false
		var record := _accept_entry(facility_key_name, entry, texture_path)
		if record.is_empty():
			return false
		_entries[facility_key_name] = record
		_marks[facility_key_name] = record
	return true


## Atlas texture table in both published shapes: a keyed object whose values
## carry the file name, or an array of entries that do the same.
func _atlas_texture_paths(atlas: Dictionary, directory: String, join_directory: bool) -> Dictionary:
	var paths := {}
	var textures: Variant = atlas.get("textures", null)
	if textures is Dictionary:
		var listed: Dictionary = textures
		for key in listed:
			var meta: Variant = listed[key]
			if not meta is Dictionary:
				continue
			var file_name := str((meta as Dictionary).get("file", (meta as Dictionary).get("path", "")))
			if file_name.is_empty():
				continue
			var resolved := _join(directory, file_name) if join_directory else file_name
			paths[String(key)] = resolved
			paths[file_name] = resolved
	elif textures is Array:
		for raw_meta in textures as Array:
			if not raw_meta is Dictionary:
				continue
			var meta: Dictionary = raw_meta
			var texture_id := str(meta.get("id", ""))
			var file_name := str(meta.get("file", meta.get("path", "")))
			if texture_id.is_empty() or file_name.is_empty():
				continue
			var resolved := _join(directory, file_name) if join_directory else file_name
			paths[texture_id] = resolved
			# Sprites of this batch name their sheet by file name, the table names
			# it by id; both spellings must land on the same published file.
			paths[file_name] = resolved
	return paths


func _join(directory: String, file_name: String) -> String:
	if file_name.begins_with("res://"):
		return file_name
	if directory.is_empty():
		return file_name
	return directory.path_join(file_name)


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
	if int(atlas.get("schema_version", 0)) != 1:
		pending_reason = "ASSETS PENDING: %s must be a schema_version 1 atlas" % path
		return {}
	return atlas


## Validates one published cell, loads and caches the sheet it belongs to, and
## returns the record the atlas lookups resolve, or an empty dictionary when the
## cell violates the contract.
func _accept_entry(entry_id: String, entry: Dictionary, texture_path: String) -> Dictionary:
	var rect: Variant = entry.get("rect", [])
	if not rect is Array or (rect as Array).size() != 4:
		pending_reason = "ASSETS PENDING: %s requires an integer rect[4]" % entry_id
		return {}
	var cell := Rect2i(int(rect[0]), int(rect[1]), int(rect[2]), int(rect[3]))
	if cell.size.x <= 0 or cell.size.y <= 0:
		pending_reason = "ASSETS PENDING: %s has an empty cell" % entry_id
		return {}
	if not _textures.has(texture_path):
		var texture := _load_texture(texture_path)
		if texture == null:
			return {}
		_textures[texture_path] = texture
	var texture: Texture2D = _textures[texture_path]
	if not Rect2i(Vector2i.ZERO, texture.get_size()).encloses(cell):
		pending_reason = "ASSETS PENDING: %s lies outside %s" % [entry_id, texture_path]
		return {}
	var record := entry.duplicate(true)
	record["texture_path"] = texture_path
	return record


func _verify_required_ids() -> bool:
	for kind in ENTRY_PREFIXES:
		var table := _canonical_table(String(kind))
		for local_id: String in table:
			var canonical := String(table[local_id])
			var entry: Dictionary = _entries.get(canonical, {})
			if entry.is_empty():
				pending_reason = "ASSETS PENDING: early_loop_v01 lacks %s" % canonical
				return false
			var rect: Array = entry.get("rect", [])
			if Vector2i(int(rect[2]), int(rect[3])) != ICON_NATIVE_SIZE:
				pending_reason = "ASSETS PENDING: %s violates the 32x32 icon contract" % canonical
				return false
	for facility_key_name in FACILITY_KEYS:
		if not _marks.has(facility_key_name):
			pending_reason = "ASSETS PENDING: hamlet_concept_v02 lacks facility.%s" % facility_key_name
			return false
	# The overlay is bounded and it must have landed: each pinned id has to
	# resolve to its pinned cell on the overrides sheet, so a layer that silently
	# dropped cannot pass as a loaded package.
	var override_sheet := _override_package().path_join(OVERRIDE_TEXTURE_FILE)
	for index in OVERRIDE_ENTRIES.size():
		var pin: Dictionary = OVERRIDE_ENTRIES[index]
		var override_id := String(pin["id"])
		var served: Dictionary = _entries.get(override_id, {})
		var cell: Vector2i = pin["cell"]
		var rect: Array = served.get("rect", [])
		if rect.size() != 4 or int(rect[0]) != cell.x or int(rect[1]) != cell.y:
			pending_reason = "ASSETS PENDING: %s does not resolve to its published override cell" % override_id
			return false
		if str(served.get("texture_path", "")) != override_sheet:
			pending_reason = "ASSETS PENDING: %s is not served from %s" % [override_id, OVERRIDE_TEXTURE_FILE]
			return false
	return true


func _region(entry: Dictionary) -> Texture2D:
	var texture: Texture2D = _textures.get(str(entry.get("texture_path", "")), null)
	if texture == null:
		return null
	var rect: Array = entry.get("rect", [])
	if rect.size() != 4:
		return null
	var atlas := AtlasTexture.new()
	atlas.atlas = texture
	atlas.region = Rect2(float(rect[0]), float(rect[1]), float(rect[2]), float(rect[3]))
	# Provenance for independent verification: which published sheet this cell is
	# cut from. It is metadata only and changes nothing about the drawn pixels.
	atlas.set_meta("sheet_path", str(entry.get("texture_path", "")))
	return atlas


func _load_texture(path: String) -> Texture2D:
	var loaded := TextureLoader.load_imported_first(path)
	match String(loaded.error):
		TextureLoader.ERROR_MISSING:
			pending_reason = "ASSETS PENDING: missing %s" % path
		TextureLoader.ERROR_UNREADABLE:
			pending_reason = "ASSETS PENDING: cannot read %s" % path
		TextureLoader.ERROR_INVALID_PNG:
			pending_reason = "ASSETS PENDING: invalid PNG %s" % path
	return loaded.texture


func _note_missing(canonical: String) -> void:
	if canonical in _missing_ids:
		return
	_missing_ids.append(canonical)
