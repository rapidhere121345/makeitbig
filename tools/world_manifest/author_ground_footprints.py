#!/usr/bin/env python3
"""Apply reviewed 2.5D ground footprints to native scene polygons.

The native scenes remain runtime authority. The recipe describes floor contact
in source-canvas pixels, independently of projected artwork and reveal bounds.
This authoring step changes no artwork, sort anchors, channels or sockets.
Run the Godot manifest baker after --write; --check detects stale authoring.
"""
import argparse
import json
import math
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RECIPE = ROOT / 'docs/art-production/generated-world-v02/ground_footprints.json'
# Geometry written by author_town_expansion.py carries this owner and its own
# recipe; it is never re-derived here.
EXPANSION_OWNER = 'metadata/expansion_owner = '
# Original natives whose visual and footprint were replaced by a reviewed
# orientation variant keep their node, binding and contract slot, but their
# envelope is authored by author_town_expansion.py from the new art.
EXPANSION_OVERRIDE = 'metadata/expansion_override = '


def numbers(text):
    return [float(x.strip()) for x in text.split(',')]


def patch_scene(path, section, recipe, assets):
    return patch_text(path.read_text(), section, recipe, assets, path)


def patch_text(text, section, recipe, assets, path='<scene>'):
    blocks = re.split(r'(?=\[node )', text)
    sprites = {}
    for block in blocks:
        match = re.search(r'metadata/environment_asset_id = "generated_world_v02/([^"]+)"', block)
        if match:
            name = re.search(r'\[node name="([^"]+)"', block)[1]
            feet = numbers(re.search(r'position = Vector2\(([^)]+)\)', block)[1])
            sprites[name + '_envelope'] = (match[1], feet)
    count = 0
    for i, block in enumerate(blocks):
        if 'type="Polygon2D"' not in block or '/Static"' not in block or EXPANSION_OWNER in block:
            continue
        if EXPANSION_OVERRIDE in block:
            count += 1
            continue
        name = re.search(r'\[node name="([^"]+)"', block)[1]
        node_match = re.search(r'^position = Vector2\(([^)]+)\)', block, re.M)
        node = numbers(node_match[1]) if node_match else [0, 0]
        if section == 'town':
            family, feet = sprites[name]
            scale = 1.0
        else:
            binding = re.search(r'metadata/binding_id = "combat/structure/([^"]+)"', block)[1]
            family = binding.split('#')[0].replace('.', '_')
            feet, scale = node, 0.72
        entry = recipe[section][family]
        x, y, w, h = entry['rect']
        pad = recipe['padding_native_px']
        ax, ay = assets[family]['anchor']
        points = []
        for px, py in [(x-pad, y-pad), (x+w+pad, y-pad),
                       (x+w+pad, y+h+pad), (x-pad, y+h+pad)]:
            absolute = [feet[0] + (px-ax)/scale, feet[1] + (py-ay)/scale]
            if section == 'arena':
                # Godot roundf uses half away from zero, unlike Python round.
                absolute = [math.copysign(math.floor(abs(v)*16+0.5), v)/16
                            for v in absolute]
            points.extend([absolute[0]-node[0], absolute[1]-node[1]])
        polygon = 'polygon = PackedVector2Array(' + ', '.join(format(v, '.12g') for v in points) + ')'
        updated, replacements = re.subn(r'polygon = PackedVector2Array\([^\n]+\)', polygon, block)
        assert replacements == 1, (path, name)
        blocks[i] = updated
        count += 1
    assert count == (35 if section == 'town' else 13), (path, count)
    return ''.join(blocks)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--section', choices=['town', 'arena', 'all'], default='all')
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--write', action='store_true')
    mode.add_argument('--check', action='store_true')
    args = parser.parse_args()
    recipe = json.loads(RECIPE.read_text())
    assets = json.loads((ROOT/'art/production/p1/generated_world_v02/assets.json').read_text())['assets']
    assert recipe['schema_version'] == 1
    assert 0 <= recipe['padding_native_px'] <= 8
    for section in ['town', 'arena']:
        for family, entry in recipe[section].items():
            x, y, w, h = entry['rect']
            assert all(math.isfinite(v) for v in [x, y, w, h])
            cw, ch = assets[family]['canvas']
            assert 0 <= x < x+w <= cw and 0 <= y < y+h <= ch, family
            assert entry.get('reason'), family
    paths = []
    if args.section in ['all', 'town']:
        paths.append(('town', ROOT/'content/rooms/town/hearthside.tscn'))
    if args.section in ['all', 'arena']:
        paths.extend(('arena', ROOT/f'content/rooms/combat/{room}.tscn')
                     for room in ['rectangle_arena', 'corridor', 'ring'])
    stale = []
    for section, path in paths:
        result = patch_scene(path, section, recipe, assets)
        if result != path.read_text():
            stale.append(str(path.relative_to(ROOT)))
            if args.write:
                path.write_text(result)
    print(json.dumps({'mode': 'write' if args.write else 'check', 'changed': stale}))
    return 1 if args.check and stale else 0


if __name__ == '__main__':
    raise SystemExit(main())
