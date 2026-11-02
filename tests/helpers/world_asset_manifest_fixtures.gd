extends RefCounted

## Shared payloads for the world asset pipeline test.  All fixtures are
## plain JSON-safe dictionaries; no native scene is required to build them.

const COORDINATE_CONVENTION: Dictionary = {"units": "design_pixel", "up": "negative_y", "scale": 1.0}


## A valid authoring manifest: explicit seven-channel mapping, movement
## and attack collision truth, one pure-presentation art piece with a
## feet-anchored art box, and fully authored collections.
static func authoring_payload() -> Dictionary:
	return {
		"coordinate_convention": COORDINATE_CONVENTION.duplicate(true),
		"stable_bindings": [
			{
				"binding_id": "combat/movement-boundary",
				"source": "arena.geometry.v1",
				"channels": {
					"movement": true, "navigation": true, "vision": true,
					"projectile": true, "attack": false, "hurtbox": false, "occlusion": false,
				},
				"geometry": {"type": "rect", "rect": [0.0, 0.0, 200.0, 200.0]},
			},
			{
				"binding_id": "art.rack",
				"source": "arena.geometry.v1",
				"channels": {"attack": true, "hurtbox": true},
				"geometry": {"type": "rect", "rect": [40.0, 80.0, 40.0, 40.0]},
				"feet_anchor": {"mode": "art_bottom_center"},
				"art_box": [-30.0, -60.0, 60.0, 60.0],
			},
			{
				"binding_id": "art.sign",
				"source": "art.box.v1",
				"channels": {"occlusion": true},
				"feet_anchor": {"mode": "art_bottom_center"},
				"art_box": [-20.0, -40.0, 40.0, 40.0],
			},
		],
		"traversal_profiles": [{"profile_id": "standard", "radius": 14.0}],
		"regions_and_portals": [{"region_id": "combat", "portals": []}],
		"spawn_interaction_exit_sockets": [
			{"socket_id": "combat/spawn", "kind": "spawn", "position": [60.0, 170.0]},
			{"socket_id": "combat/exit", "kind": "exit", "position": [180.0, 100.0]},
		],
		"gameplay_spatial_metadata": {"room_kind": "combat", "layout_id": "fixture"},
	}


static func overlay_entries() -> Array:
	return [
		{
			"overlay_id": "gate.east",
			"kind": "gate",
			"channels": {"movement": true, "projectile": true},
			"geometry": {"type": "rect", "rect": [90.0, 0.0, 20.0, 60.0]},
		},
	]


## Plan entries ordered by baseline then rank then id; all art boxes are
## bottom-center anchored on their own feet.
static func plan_entries() -> Array:
	return [
		{"stable_id": "hero", "baseline_y": 300.0, "rank": 1, "feet_anchor": Vector2(120.0, 300.0), "art_box": Rect2(100.0, 250.0, 40.0, 50.0)},
		{"stable_id": "rack", "baseline_y": 280.0, "rank": 1, "feet_anchor": Vector2(120.0, 280.0), "art_box": Rect2(105.0, 230.0, 30.0, 50.0)},
		{"stable_id": "sign", "baseline_y": 300.0, "rank": 1, "feet_anchor": Vector2(150.0, 300.0), "art_box": Rect2(130.0, 260.0, 40.0, 40.0)},
		{"stable_id": "pillar", "baseline_y": 260.0, "rank": 1, "feet_anchor": Vector2(40.0, 260.0), "art_box": Rect2(20.0, 210.0, 40.0, 50.0)},
	]
