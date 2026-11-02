#!/usr/bin/env python3
"""Author chapter-one terrain battlefields using retained production structures.

Scenes are the runtime source; bake their spatial manifests after authoring.
Terrain contacts come from the reviewed, checksum-pinned environment plates.
Structure footprints use the retained source-canvas recipe.
"""
import argparse
from copy import deepcopy
import hashlib
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
# All complete plates cover the whole 1024x640 world. Keep authored legacy
# design positions readable while projecting them onto that complete image.
BOUNDS = [-71.125, 25.5625, 1422.25, 888.875]
DESIGN_Y_OFFSET = 55.5625
# Every field has open ground around its landmarks. These are terrain features,
# never a small enclosing arena or an annular movement constraint.
FIELDS = {'snowbound_road': {'spawn': [280, 640],
                    'structures': [('ruin.wall_corner', 330, 290),
                                   ('ruin.low_pier', 920, 640),
                                   ('ruin.broken_wall', 1050, 300),
                                   ('ruin.gate', 1040, 180),
                                   ('tower', 170, 350)]},
 'river_crossing': {'spawn': [300, 610],
                    'origin': [640, 420],
                    'structures': [('ruin.low_pier', 435, 340),
                                   ('ruin.low_pier', 805, 595),
                                   ('ruin.wall_corner', 1070, 280),
                                   ('ruin.gate', 1050, 190),
                                   ('tower', 160, 270)]},
 'ruined_village': {'spawn': [270, 660],
                    'structures': [('ruin.wall_corner', 370, 350),
                                   ('ruin.broken_wall', 900, 610),
                                   ('ruin.low_pier', 750, 280),
                                   ('ruin.low_pier', 480, 720),
                                   ('ruin.broken_wall', 1060, 330),
                                   ('ruin.gate', 1050, 190),
                                   ('tower', 170, 270)]},
 'quarry_pass': {'spawn': [250, 670],
                 'structures': [('ruin.broken_wall', 590, 310),
                                ('ruin.low_pier', 780, 680),
                                ('ruin.wall_corner', 1080, 300),
                                ('ruin.gate', 1070, 200),
                                ('tower', 190, 420)]},
 'colossus_approach': {'spawn': [330, 660],
                       'structures': [('ruin.wall_corner', 330, 280),
                                      ('ruin.wall_corner', 1010, 280),
                                      ('ruin.low_pier', 280, 590),
                                      ('ruin.low_pier', 1030, 640),
                                      ('ruin.gate', 930, 190),
                                      ('tower', 175, 390)]}}


def world_to_gameplay(x, y):
    return [round((640 + (x - 512) / 0.72) * 16) / 16,
            round((470 + (y - 320) / 0.72) * 16) / 16]


def reviewed_record(path, root):
    """Read contacts only when their reviewed plate still matches its digest."""
    record = json.loads(path.read_text(encoding='utf-8'))
    specs = record.get('battlefields', {'river_crossing': record})
    for layout, spec in specs.items():
        plate = root / spec['source_plate'].removeprefix('res://')
        if hashlib.sha256(plate.read_bytes()).hexdigest() != spec['source_sha256']:
            raise ValueError(f'{layout}: plate changed; review terrain contacts again')
    return record


def load_fields(root=ROOT):
    """Build fresh field definitions without modifying the authored placements."""
    fields = deepcopy(FIELDS)
    apply_reviewed_environment_contacts(fields, root)
    apply_reviewed_river_banks(fields, root)
    return fields


def apply_reviewed_environment_contacts(fields, root):
    record = reviewed_record(root / 'docs/art-production/battlefields-20261028/environment_contacts.json', root)
    for layout, spec in record['battlefields'].items():
        fields[layout]['terrain'] = [(entry['binding'], [world_to_gameplay(x, y) for x, y in entry['points']]) for entry in spec['polygons']]


def apply_reviewed_river_banks(fields, root):
    """Author convex water bands against the complete painted river/bridge plate."""
    record = reviewed_record(root / 'docs/art-production/battlefields-20261028/river_banks.json', root)
    water = []
    for section in ['north', 'south']:
        rows = record[section]
        for index, (a, b) in enumerate(zip(rows, rows[1:])):
            ay, al, ar = a
            by, bl, br = b
            water.append((f'water/{section}_{index}', [world_to_gameplay(al, ay), world_to_gameplay(ar, ay), world_to_gameplay(br, by), world_to_gameplay(bl, by)]))
    spec = fields['river_crossing']
    spec['terrain'] = water + [(name, points) for name, points in spec['terrain'] if not name.startswith('water/')]


def scene_text(layout, spec, recipe, assets):
    text = '''[gd_scene load_steps=3 format=3]

[ext_resource path="res://src/game/main.gd" type="Script" id="1_main"]
[ext_resource path="res://src/runtime/world/room_asset_root.gd" type="Script" id="2_room_asset"]

[node name="Main" type="Node2D"]
script = ExtResource("1_main")

[node name="RoomAsset" type="Node2D" parent="."]
script = ExtResource("2_room_asset")
scene_id = "combat.LAYOUT"
layout_id = "LAYOUT"
gameplay_source = "LAYOUT.spatial.json"
presentation_source = "battlefield_scene"
arena_rect = Rect2(-71.125, 25.5625, 1422.25, 888.875)
traversal_radius = 14.0

[node name="Ground" type="Node2D" parent="RoomAsset"]
[node name="Surface" type="Node2D" parent="RoomAsset/Ground"]
metadata/binding_id = "ground.surface"
[node name="GroundEffects" type="Node2D" parent="RoomAsset"]
[node name="SortRoot" type="Node2D" parent="RoomAsset"]
y_sort_enabled = true
[node name="Foreground" type="Node2D" parent="RoomAsset"]
[node name="GeometrySources" type="Node2D" parent="RoomAsset"]
[node name="MovementBoundary" type="Node2D" parent="RoomAsset/GeometrySources"]
metadata/binding_id = "combat/movement-boundary"
metadata/source = "arena.geometry.v1"
metadata/channels = {"movement": true, "navigation": true, "vision": true, "projectile": true, "occlusion": false}
metadata/geometry = {"type": "rect", "rect": [-71.125, 25.5625, 1422.25, 888.875]}
[node name="Static" type="Node2D" parent="RoomAsset/GeometrySources"]
'''.replace('LAYOUT', layout)
    def polygon_node(name, binding, feet, points, projectile):
        flat = ', '.join(format(v, '.12g') for point in points for v in point)
        return f'''
[node name="{name}" type="Polygon2D" parent="RoomAsset/GeometrySources/Static"]
visible = false
position = Vector2({feet[0]}, {feet[1]})
polygon = PackedVector2Array({flat})
metadata/binding_id = "{binding}"
metadata/source = "arena.static.convex.v1"
metadata/channels = {{"movement": true, "navigation": false, "vision": false, "projectile": {str(projectile).lower()}, "occlusion": false}}
'''
    for i, (kind, points) in enumerate(spec['terrain']):
        text += polygon_node(f'Terrain{i}', 'combat/terrain/' + kind, [0, 0], points, kind.startswith('cliff/'))
    counts = {}
    for i, (sprite, x, y) in enumerate(spec['structures']):
        y += DESIGN_Y_OFFSET
        family = sprite.replace('.', '_')
        px, py, w, h = recipe['arena'][family]['rect']
        pad = recipe['padding_native_px']
        ax, ay = assets[family]['anchor']
        points = []
        for cx, cy in [(px-pad, py-pad), (px+w+pad, py-pad), (px+w+pad, py+h+pad), (px-pad, py+h+pad)]:
            absolute = [x + (cx-ax)/0.72, y + (cy-ay)/0.72]
            snapped = [math.copysign(math.floor(abs(v)*16+0.5), v)/16 for v in absolute]
            points.append([snapped[0]-x, snapped[1]-y])
        ordinal = counts.get(sprite, 0)
        counts[sprite] = ordinal + 1
        suffix = sprite if sprite == 'tower' else f'{sprite}#{ordinal}'
        text += polygon_node(f'Structure{i}', 'combat/structure/' + suffix, [x, y], points, sprite != 'ruin.low_pier')
    for name, binding, position in [('CombatSpawn', 'combat/spawn', spec['spawn']),
                                    ('EncounterOrigin', 'combat/encounter-origin', spec.get('origin', [640, 470]))]:
        if name == 'CombatSpawn':
            text += '\n[node name="Sockets" type="Node2D" parent="RoomAsset"]\n'
        text += f'''[node name="{name}" type="Marker2D" parent="RoomAsset/Sockets"]
position = Vector2({position[0]}, {position[1] + DESIGN_Y_OFFSET})
metadata/binding_id = "{binding}"
metadata/kind = "spawn"
'''
    return text


def authored_scenes(root=ROOT):
    """Compile all scenes in memory; validate every source before writing any."""
    fields = load_fields(root)
    recipe = json.loads((root / 'docs/art-production/generated-world-v02/ground_footprints.json').read_text(encoding='utf-8'))
    assets = json.loads((root / 'art/production/p1/generated_world_v02/assets.json').read_text(encoding='utf-8'))['assets']
    return {layout: scene_text(layout, spec, recipe, assets) for layout, spec in fields.items()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    scenes = authored_scenes()
    stale = []
    for layout, expected in scenes.items():
        path = ROOT / f'content/rooms/combat/{layout}.tscn'
        if not path.exists() or path.read_text() != expected:
            stale.append(layout)
            if not args.check:
                path.write_text(expected)
    print(json.dumps({'battlefields': len(scenes), 'changed': stale, 'check': args.check}))
    return int(args.check and bool(stale))


if __name__ == '__main__':
    raise SystemExit(main())
