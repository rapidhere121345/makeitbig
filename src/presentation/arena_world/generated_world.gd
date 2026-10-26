extends RefCounted
## Generated world pack loading extracted from ArenaWorldView. Whole-object
## generated world pack: each family sprite is ONE opaque texture plus its baked
## transparent variant on the same canvas/anchor, with one authored detection
## rect (occupied AABB grown by DETECTION_GROW) in local canvas coordinates. The
## pack is required: a missing or incomplete pack fails the load. The view owns
## the sprite/texture tables and pending_reason the loader fills.

const PairedReveal := preload("res://src/presentation/occlusion/paired_reveal_controller.gd")

const GENERATED_WORLD_PATH := "res://art/production/p1/generated_world_v02/assets.json"
const GENERATED_GROUND_ID := "arena_ground"
## Pack asset id -> live arena sprite id. The whole-object entries replace
## the scene atlas cells; sections.arena.complete must be true.
const GENERATED_SPRITE_IDS := {
	"ruin_wall_corner": "ruin.wall_corner",
	"ruin_gate": "ruin.gate",
	"ruin_low_pier": "ruin.low_pier",
	"ruin_broken_wall": "ruin.broken_wall",
	"tower": "tower",
}

## sprite_id -> {texture_key, opaque, variant, canvas, anchor, occupied_rect,
## occlusion_rect(canvas-local), variant_max_alpha}.
var sprites: Dictionary = {}


## The world-space detection rect of one whole-object generated piece: its
## authored canvas-local rect translated by the same feet-anchor mapping the
## draw pass uses, so detection matches the sort domain exactly.
func detection_rect_world(sprite_id: String, feet: Vector2) -> Rect2:
	var record: Variant = sprites.get(sprite_id, null)
	if record == null:
		return Rect2()
	var local: Rect2 = record.occlusion_rect
	return Rect2(feet - (record.anchor as Vector2) + local.position, local.size)


## Generated world pack: whole-object opaque/transparent pairs. The pack is
## required — a missing file, an incomplete arena section, or any family
## sprite that is not "packed" and valid fails the whole load closed (never a
## silent half-new scene and never a silent fallback).
func load_pack(view: ArenaWorldProjection) -> bool:
	sprites.clear()
	view._fades.clear_materials()
	var pack := view._read_json(view.generated_world_path)
	if pack.is_empty():
		return false
	var grounds: Variant = pack.get("grounds", null)
	var ground_entry: Variant = (grounds as Dictionary).get(GENERATED_GROUND_ID, null) if grounds is Dictionary else null
	if not ground_entry is Dictionary or String((ground_entry as Dictionary).get("status", "")) != "packed":
		view.pending_reason = "ASSETS PENDING: generated arena ground is not packed"
		return false
	if ground_entry is Dictionary and String((ground_entry as Dictionary).get("status", "")) == "packed":
		var ground := view._load_texture(String((ground_entry as Dictionary).get("opaque_path", "")))
		if ground == null:
			return false
		if ground.get_size() != view.WORLD_SIZE:
			view.pending_reason = "ASSETS PENDING: generated ground must be %dx%d" % [int(view.WORLD_SIZE.x), int(view.WORLD_SIZE.y)]
			return false
		view._textures[view.APPROVED_GROUND_KEY] = ground
	var sections: Variant = pack.get("sections", null)
	var arena_section: Variant = (sections as Dictionary).get("arena", {}) if sections is Dictionary else {}
	if not arena_section is Dictionary or not bool((arena_section as Dictionary).get("complete", false)):
		view.pending_reason = "ASSETS PENDING: generated pack present but arena section is not complete"
		return false
	var assets: Variant = pack.get("assets", null)
	if not assets is Dictionary:
		view.pending_reason = "ASSETS PENDING: generated pack lacks assets"
		return false
	for asset_id: String in GENERATED_SPRITE_IDS.keys():
		var raw: Variant = (assets as Dictionary).get(asset_id, null)
		if not raw is Dictionary or String((raw as Dictionary).get("status", "")) != "packed":
			view.pending_reason = "ASSETS PENDING: generated asset %s is not packed" % asset_id
			return false
		var sprite_id := String(GENERATED_SPRITE_IDS[asset_id])
		var record := _normalize_generated_sprite(view, sprite_id, raw as Dictionary)
		if record.is_empty():
			return false
		sprites[sprite_id] = record
		view._textures[record.texture_key] = record.opaque
		view._sprites[sprite_id] = {"texture": record.texture_key,
			"rect": Rect2(Vector2.ZERO, record.canvas), "anchor": record.anchor}
	return true


## One generated sprite entry: canvas/anchor/rects plus the opaque and
## transparent texture pair. The detection rect must contain the opaque
## texture's MEASURED occupied bounds grown by DETECTION_GROW — the pack's
## own declared occupied_rect is metadata; the texture is the truth.
func _normalize_generated_sprite(view: ArenaWorldProjection, sprite_id: String, raw: Dictionary) -> Dictionary:
	var canvas := view._point(raw.get("canvas", []))
	var anchor := view._point(raw.get("anchor", []))
	var occupied := _rect_of(raw.get("occupied_rect", []))
	var occlusion := _rect_of(raw.get("occlusion_rect", []))
	if canvas.x <= 0.0 or canvas.y <= 0.0 or not anchor.is_finite():
		view.pending_reason = "ASSETS PENDING: %s malformed canvas or anchor" % sprite_id
		return {}
	var opaque := view._load_texture(String(raw.get("opaque_path", "")))
	var variant := view._load_texture(String(raw.get("transparent_path", "")))
	if opaque == null or variant == null:
		return {}
	if opaque.get_size() != canvas or variant.get_size() != canvas:
		view.pending_reason = "ASSETS PENDING: %s pair must share the authored canvas" % sprite_id
		return {}
	if PairedReveal.detection_rect_error(occlusion, opaque.get_image()) != "":
		view.pending_reason = "ASSETS PENDING: %s detection rect must contain occupied.grow(%d)" % [sprite_id, int(PairedReveal.DETECTION_GROW)]
		return {}
	var variant_image := variant.get_image()
	var variant_max_alpha := 0.0
	for y: int in variant_image.get_height():
		for x: int in variant_image.get_width():
			variant_max_alpha = maxf(variant_max_alpha, variant_image.get_pixel(x, y).a)
	return {"texture_key": "generated/" + sprite_id, "opaque": opaque, "variant": variant,
		"canvas": canvas, "anchor": anchor, "occupied_rect": occupied, "occlusion_rect": occlusion,
		"variant_max_alpha": variant_max_alpha}


func _rect_of(value: Variant) -> Rect2:
	if value is Rect2:
		return value
	if not value is Array or (value as Array).size() != 4:
		return Rect2()
	var array: Array = value
	for component: Variant in array:
		if not (component is float or component is int) or not is_finite(float(component)):
			return Rect2()
	return Rect2(float(array[0]), float(array[1]), float(array[2]), float(array[3]))


func geometry(sprite_id: String, feet: Vector2) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if sprites.has(sprite_id):
		var record: Dictionary = sprites[sprite_id]
		result.append({"part": "whole", "source": Rect2(Vector2.ZERO, record.canvas),
			"dest": Rect2((feet - (record.anchor as Vector2)).round(), record.canvas),
			"alpha": 1.0, "texture": String(record.texture_key)})
	return result
