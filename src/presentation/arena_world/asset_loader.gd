extends RefCounted
## Atlas, texture and layout loading extracted from ArenaWorldView. Validates the
## scene/legacy atlases against the cell contracts and fills the view's sprite,
## texture and structure tables. The view owns those tables, the JSON/PNG
## readers and view.pending_reason, so each step takes it as its first argument.

const SCENE_ATLAS_PATH: String = "res://art/production/p1/actors_v02/scene_atlas.json"
const SCENE_LAYOUT_PATH: String = "res://art/production/p1/combat_style_r13/v03/layout.json"
const LEGACY_ATLAS_PATH: String = "res://art/production/p1/actors_v02/legacy_atlas.json"
const APPROVED_GROUND_KEY: String = "approved_ground"
const GROUND_SPRITE_ID: String = "scene.ground"
## Only these calibration_v01 sprites are reused read-only; the reworked atlas
## owns everything else, so a missing reworked sprite stays missing instead of
## silently falling back to an older drawing.
const LEGACY_SPRITE_IDS: Array[String] = [
	"tower.upper", "tower.base",
	"enemy.melee.idle", "enemy.melee.windup", "enemy.melee.active", "enemy.melee.recover",
	"enemy.charger.idle", "enemy.charger.windup", "enemy.charger.active", "enemy.charger.recover",
	"enemy.ranged.idle", "enemy.ranged.windup", "enemy.ranged.active", "enemy.ranged.recover",
]
const CELL_CONTRACTS := {
	"scene.ground": {"size": Vector2i(1024, 640)},
	"ground.snow_wedge": {"size": Vector2i(128, 96), "anchor": Vector2i(64, 90)},
	"ground.snow_strip": {"size": Vector2i(128, 96), "anchor": Vector2i(64, 90)},
	"ground.rubble_apron": {"size": Vector2i(128, 96), "anchor": Vector2i(64, 90)},
	"ground.foundation": {"size": Vector2i(128, 96), "anchor": Vector2i(64, 90)},
	"ruin.wall_corner": {"size": Vector2i(128, 128), "anchor": Vector2i(64, 120)},
	"ruin.gate": {"size": Vector2i(128, 128), "anchor": Vector2i(64, 120)},
	"ruin.low_pier": {"size": Vector2i(128, 128), "anchor": Vector2i(64, 120)},
	"ruin.broken_wall": {"size": Vector2i(128, 128), "anchor": Vector2i(64, 120)},
	"ranger.south.idle": {"size": Vector2i(32, 48), "anchor": Vector2i(16, 44)},
	"ranger.north.idle": {"size": Vector2i(32, 48), "anchor": Vector2i(16, 44)},
	"ranger.east.idle": {"size": Vector2i(32, 48), "anchor": Vector2i(16, 44)},
	"ranger.west.idle": {"size": Vector2i(32, 48), "anchor": Vector2i(16, 44)},
	"boss.body_phase1": {"size": Vector2i(128, 128), "anchor": Vector2i(64, 120)},
	"boss.body_phase2": {"size": Vector2i(128, 128), "anchor": Vector2i(64, 120)},
	"boss.hand_left": {"size": Vector2i(48, 64), "anchor": Vector2i(24, 56)},
	"boss.hand_right": {"size": Vector2i(48, 64), "anchor": Vector2i(24, 56)},
	"boss.core_phase1": {"size": Vector2i(32, 64), "anchor": Vector2i(16, 56)},
	"boss.core_phase2": {"size": Vector2i(32, 64), "anchor": Vector2i(16, 56)},
	"tower.upper": {"size": Vector2i(128, 192), "anchor": Vector2i(64, 184), "keep_rows": [0, 148]},
	"tower.base": {"size": Vector2i(128, 192), "anchor": Vector2i(64, 184), "keep_rows": [148, 192]},
	"enemy.melee.idle": {"size": Vector2i(48, 48), "anchor": Vector2i(24, 44)},
	"enemy.melee.windup": {"size": Vector2i(48, 48), "anchor": Vector2i(24, 44)},
	"enemy.melee.active": {"size": Vector2i(48, 48), "anchor": Vector2i(24, 44)},
	"enemy.melee.recover": {"size": Vector2i(48, 48), "anchor": Vector2i(24, 44)},
	"enemy.charger.idle": {"size": Vector2i(48, 48), "anchor": Vector2i(24, 44)},
	"enemy.charger.windup": {"size": Vector2i(48, 48), "anchor": Vector2i(24, 44)},
	"enemy.charger.active": {"size": Vector2i(48, 48), "anchor": Vector2i(24, 44)},
	"enemy.charger.recover": {"size": Vector2i(48, 48), "anchor": Vector2i(24, 44)},
	"enemy.ranged.idle": {"size": Vector2i(48, 48), "anchor": Vector2i(24, 44)},
	"enemy.ranged.windup": {"size": Vector2i(48, 48), "anchor": Vector2i(24, 44)},
	"enemy.ranged.active": {"size": Vector2i(48, 48), "anchor": Vector2i(24, 44)},
	"enemy.ranged.recover": {"size": Vector2i(48, 48), "anchor": Vector2i(24, 44)},
}


func select_union(view: ArenaWorldProjection, scene_atlas: Dictionary, legacy_atlas: Dictionary) -> bool:
	var scene_sprites := scene_atlas.get("sprites", {}) as Dictionary
	var legacy_sprites := legacy_atlas.get("sprites", {}) as Dictionary
	for sprite_id in scene_sprites.keys():
		if LEGACY_SPRITE_IDS.has(String(sprite_id)):
			view.pending_reason = "ASSETS PENDING: reworked atlas must not override %s" % sprite_id
			return false
		var normalized := normalize_sprite(view, scene_sprites[sprite_id] as Dictionary)
		if normalized.is_empty():
			return false
		view._sprites[String(sprite_id)] = normalized
	for sprite_id in LEGACY_SPRITE_IDS:
		var raw: Variant = legacy_sprites.get(sprite_id, {})
		if not raw is Dictionary:
			view.pending_reason = "ASSETS PENDING: calibration atlas lacks %s" % sprite_id
			return false
		var normalized := normalize_sprite(view, raw as Dictionary)
		if normalized.is_empty():
			return false
		view._sprites[sprite_id] = normalized
	return true


func normalize_sprite(view: ArenaWorldProjection, raw: Dictionary) -> Dictionary:
	var rect: Array = raw.get("rect", [])
	var anchor: Array = raw.get("anchor", [])
	if rect.size() != 4 or anchor.size() != 2:
		view.pending_reason = "ASSETS PENDING: malformed rect/anchor for %s" % String(raw.get("texture", ""))
		return {}
	var normalized := {
		"texture": String(raw.get("texture", "")),
		"rect": Rect2(float(rect[0]), float(rect[1]), float(rect[2]), float(rect[3])),
		"anchor": Vector2(float(anchor[0]), float(anchor[1])),
	}
	if raw.has("keep_rows"):
		normalized["keep_rows"] = (raw.get("keep_rows") as Array).duplicate()
	return normalized


func load_textures(view: ArenaWorldProjection, scene_atlas: Dictionary, legacy_atlas: Dictionary) -> bool:
	var sources: Dictionary = (scene_atlas.get("textures", {}) as Dictionary).duplicate(true)
	var legacy_sources: Dictionary = legacy_atlas.get("textures", {})
	for sprite_id: String in LEGACY_SPRITE_IDS:
		var key := String(view._sprites[sprite_id].get("texture", ""))
		if not legacy_sources.has(key):
			view.pending_reason = "ASSETS PENDING: reused sprite %s has no texture metadata" % sprite_id
			return false
		if sources.has(key) and sources[key] != legacy_sources[key]:
			view.pending_reason = "ASSETS PENDING: conflicting texture key %s in composed atlas" % key
			return false
		sources[key] = legacy_sources[key]
	for texture_key in sources.keys():
		var metadata := sources[texture_key] as Dictionary
		var path := String(metadata.get("path", ""))
		var texture := view._load_texture(path)
		if texture == null:
			return false
		if texture.get_width() != int(metadata.get("width", 0)) or texture.get_height() != int(metadata.get("height", 0)):
			view.pending_reason = "ASSETS PENDING: %s size does not match its atlas entry" % path
			return false
		view._textures[String(texture_key)] = texture
	view._prime_alpha_visible_bounds()
	return true


func validate_cells(view: ArenaWorldProjection) -> bool:
	for sprite_id in CELL_CONTRACTS.keys():
		var metadata := view.sprite(String(sprite_id))
		if metadata.is_empty():
			view.pending_reason = "ASSETS PENDING: missing sprite %s" % sprite_id
			return false
		var contract: Dictionary = CELL_CONTRACTS[sprite_id]
		var rect: Rect2 = metadata.get("rect", Rect2())
		var expected_size: Vector2i = contract.get("size", Vector2i.ZERO)
		if Vector2i(rect.size) != expected_size:
			view.pending_reason = "ASSETS PENDING: %s violates its cell size contract" % sprite_id
			return false
		if contract.has("anchor"):
			var expected_anchor: Vector2i = contract.get("anchor", Vector2i.ZERO)
			if Vector2i(metadata.get("anchor", Vector2.ZERO)) != expected_anchor:
				view.pending_reason = "ASSETS PENDING: %s violates its anchor contract" % sprite_id
				return false
	if view._sprites.get(GROUND_SPRITE_ID, {}).get("texture", "") != "ground":
		view.pending_reason = "ASSETS PENDING: scene.ground must come from the ground texture"
		return false
	return true


func read_layout(view: ArenaWorldProjection, layout: Dictionary) -> bool:
	var world := view._point(layout.get("world_size", []))
	if world != view.WORLD_SIZE:
		view.pending_reason = "ASSETS PENDING: layout world_size must be 1024x640"
		return false
	view._tower_feet = view._point(layout.get("tower_feet", []))
	var overrides: Variant = layout.get("room_structure_overrides", {})
	if not overrides is Dictionary:
		view.pending_reason = "ASSETS PENDING: invalid room structure overrides"
		return false
	view._room_structure_overrides = (overrides as Dictionary).duplicate(true)
	for value in layout.get("structures", []) as Array:
		view._structures.append((value as Dictionary).duplicate(true))
	var valid_ids := {"tower": true}
	var occurrences := {}
	for placement: Dictionary in view._structures:
		var id := String(placement.id)
		var ordinal := int(occurrences.get(id, 0))
		occurrences[id] = ordinal + 1
		valid_ids[id + "#" + str(ordinal)] = true
	for room: Variant in view._room_structure_overrides:
		var values: Variant = view._room_structure_overrides[room]
		if room not in ["rectangle_arena", "corridor", "ring"] or not values is Dictionary:
			view.pending_reason = "ASSETS PENDING: unknown room structure override"
			return false
		for id: Variant in values:
			var point: Variant = values[id]
			if not valid_ids.has(id) or not point is Array or (point as Array).size() != 2:
				view.pending_reason = "ASSETS PENDING: invalid structure override identity or point"
				return false
			for coordinate: Variant in point:
				if not (coordinate is float or coordinate is int) or not is_finite(float(coordinate)):
					view.pending_reason = "ASSETS PENDING: nonfinite structure override"
					return false
	if view._structures.is_empty():
		view.pending_reason = "ASSETS PENDING: layout must place structures"
		return false
	for placement in view._structures:
		var metadata := view.sprite(String(placement.get("id", "")))
		if metadata.is_empty():
			view.pending_reason = "ASSETS PENDING: layout places %s without an atlas sprite" % String(placement.get("id", ""))
			return false
		var cell := Rect2(view.WORLD_FOCUS + (view._point(placement.get("feet", [])) - Vector2(640, 434)) * view.GAMEPLAY_TO_WORLD - (metadata.get("anchor", Vector2.ZERO) as Vector2), view._cell_size(metadata))
		if not Rect2(Vector2.ZERO, view.WORLD_SIZE).encloses(cell):
			view.pending_reason = "ASSETS PENDING: %s leaves the world" % String(placement.get("id", ""))
			return false
	return true
