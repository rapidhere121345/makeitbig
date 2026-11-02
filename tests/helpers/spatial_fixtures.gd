class_name SpatialFixtures
extends RefCounted

## Deterministic sample worlds for the spatial kernel tests.

const Channels := preload("res://src/runtime/spatial/spatial_channels.gd")
const StaticSpatialIndexScript := preload("res://src/runtime/spatial/static_spatial_index.gd")


static func surface(id: String, rect: Rect2, channels: Array, extra: Dictionary = {}) -> Dictionary:
	var entry := {
		"id": id,
		"shape": {"kind": "rect", "rect": rect},
		"channels": channels,
	}
	for key: Variant in extra.keys():
		entry[key] = extra[key]
	return entry


static func body(
	entity_id: String,
	position: Vector2,
	radius: float,
	channels: Array,
	collision_class: StringName,
	generation: int = 1
) -> Dictionary:
	return {
		"entity_id": entity_id,
		"generation": generation,
		"position": position,
		"radius": radius,
		"channels": channels,
		"collision_class": collision_class,
	}


static func wall_world() -> Dictionary:
	return {
		"schema_version": StaticSpatialIndexScript.SCHEMA_VERSION,
		"asset_id": "fixture/wall_room",
		"surfaces": [
			surface("wall", Rect2(100.0, 0.0, 6.0, 120.0), [Channels.MOVEMENT, Channels.PROJECTILE]),
		],
		"movement_boundary": {"kind": "rect", "rect": Rect2(0.0, 0.0, 200.0, 120.0)},
	}


static func open_world() -> Dictionary:
	return {
		"schema_version": StaticSpatialIndexScript.SCHEMA_VERSION,
		"asset_id": "fixture/open_room",
		"surfaces": [],
		"movement_boundary": {"kind": "rect", "rect": Rect2(0.0, 0.0, 200.0, 120.0)},
	}


static func thin_wall_world() -> Dictionary:
	return {
		"schema_version": StaticSpatialIndexScript.SCHEMA_VERSION,
		"asset_id": "fixture/thin_wall_room",
		"surfaces": [
			surface("thin_wall", Rect2(100.0, 0.0, 2.0, 120.0), [Channels.MOVEMENT, Channels.PROJECTILE]),
		],
		"movement_boundary": {"kind": "rect", "rect": Rect2(0.0, 0.0, 200.0, 120.0)},
	}


static func ring_world() -> Dictionary:
	return {
		"schema_version": StaticSpatialIndexScript.SCHEMA_VERSION,
		"asset_id": "fixture/ring_arena",
		"surfaces": [],
		"movement_boundary": {
			"kind": "ring",
			"center": Vector2(100.0, 100.0),
			"inner_radius": 30.0,
			"outer_radius": 90.0,
		},
	}


static func doorway_world(gap_top: float, gap_bottom: float) -> Dictionary:
	return {
		"schema_version": StaticSpatialIndexScript.SCHEMA_VERSION,
		"asset_id": "fixture/concave_passage",
		"surfaces": [
			surface("wall_top", Rect2(100.0, 0.0, 6.0, gap_top), [Channels.MOVEMENT, Channels.PROJECTILE]),
			surface("wall_bottom", Rect2(100.0, gap_bottom, 6.0, 120.0 - gap_bottom), [Channels.MOVEMENT, Channels.PROJECTILE]),
		],
		"movement_boundary": {"kind": "rect", "rect": Rect2(0.0, 0.0, 200.0, 120.0)},
	}


static func pillar_world() -> Dictionary:
	return {
		"schema_version": StaticSpatialIndexScript.SCHEMA_VERSION,
		"asset_id": "fixture/pillar_room",
		"surfaces": [
			surface("pillar", Rect2(97.0, 54.0, 6.0, 12.0), [Channels.MOVEMENT]),
		],
		"movement_boundary": {"kind": "rect", "rect": Rect2(0.0, 0.0, 200.0, 120.0)},
	}


static func tie_world() -> Dictionary:
	return {
		"schema_version": StaticSpatialIndexScript.SCHEMA_VERSION,
		"asset_id": "fixture/tie_room",
		"surfaces": [
			surface("shield", Rect2(100.0, 0.0, 6.0, 120.0), [Channels.PROJECTILE]),
		],
		"movement_boundary": {"kind": "rect", "rect": Rect2(0.0, 0.0, 200.0, 120.0)},
	}


static func build(asset: Dictionary):
	return StaticSpatialIndexScript.build(asset)
