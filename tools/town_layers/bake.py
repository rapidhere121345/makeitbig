#!/usr/bin/env python3
"""Reproducible native town layers; no invented pixels or collision inference."""
from __future__ import annotations
import argparse
import hashlib
import json
import tempfile
from pathlib import Path
from PIL import Image, ImageDraw, ImageChops

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'art/production/p1/hamlet_town/town.png'
LAYOUT = ROOT / 'art/production/p1/hamlet_town/layout.json'
OUT = ROOT / 'content/rooms/town/layers'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def save_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + '\n')


def bake(output: Path):
    output.mkdir(parents=True, exist_ok=True)
    layout = json.loads(LAYOUT.read_text())
    original = Image.open(SOURCE).convert('RGBA')
    size = tuple(layout['world'])
    normalized = original.resize(size, Image.Resampling.NEAREST)
    owner = Image.new("L", size)
    ordered = sorted(layout['foreground'], key=lambda e: (e['feet_uv'][1], e['id']))
    masks = []
    for index, entry in enumerate(ordered, 1):
        mask = Image.new('1', size)
        ImageDraw.Draw(mask).polygon([(p[0]*size[0], p[1]*size[1]) for p in entry['points_uv']], fill=1)
        owner.paste(index, (0, 0), mask)  # later feet/id owns every overlap, once
        masks.append(entry)
    ground = Image.new("RGBA", size)
    ground_mask = owner.point(lambda value: 255 if value == 0 else 0, "L")
    ground.paste(normalized, (0, 0), ground_mask)
    ground.save(output / "ground.png", compress_level=9)
    records = []
    for index, entry in enumerate(masks, 1):
        owned = owner.point(lambda value: 255 if value == index else 0, "L")
        bounds = owned.getbbox()
        if bounds is None:
            raise ValueError('empty native ownership: ' + entry['id'])
        x, y, right, bottom = bounds
        native = Image.new("RGBA", (right-x, bottom-y))
        native.paste(normalized.crop(bounds), (0, 0), owned.crop(bounds))
        filename = entry['id'] + '.png'
        native.save(output / filename, compress_level=9)
        records.append({'id': entry['id'], 'path': 'res://content/rooms/town/layers/' + filename,
            'sha256': digest(output / filename), 'crop': [x, y, right-x, bottom-y],
            'feet': [entry['feet_uv'][0]*size[0], entry['feet_uv'][1]*size[1]],
            'interaction': entry.get('interaction', ''), 'owned_pixels': owned.histogram()[255]})
    manifest = {'schema_version': 1, 'source': 'res://art/production/p1/hamlet_town/town.png',
        'source_sha256': digest(SOURCE), 'layout_source': 'res://art/production/p1/hamlet_town/layout.json',
        'layout_sha256': digest(LAYOUT), 'source_size': list(original.size), 'world_size': list(size),
        'conversion': 'nearest_once_to_layout_world', 'ownership_order': 'feet_y_then_stable_id_last_wins',
        'unknown_underplate': 'transparent', 'supports_cutaway': False, 'supports_fade': False,
        'ground': {'path': 'res://content/rooms/town/layers/ground.png', 'sha256': digest(output/'ground.png'),
                   'owned_pixels': ground_mask.histogram()[255]}, 'native': records}
    save_json(output / 'manifest.json', manifest)
    return manifest


def verify(output: Path):
    manifest = json.loads((output/'manifest.json').read_text())
    if manifest['source_sha256'] != digest(SOURCE) or manifest['layout_sha256'] != digest(LAYOUT):
        raise ValueError('source/layout digest changed; rebake the native author source')
    expected = Image.open(SOURCE).convert('RGBA').resize(tuple(manifest['world_size']), Image.Resampling.NEAREST)
    composed = Image.open(output/'ground.png').convert('RGBA')
    ownership = bytearray(1 if alpha else 0 for alpha in composed.getchannel('A').tobytes())
    width = composed.width
    for entry in manifest['native']:
        path = output / Path(entry['path']).name
        if digest(path) != entry['sha256']:
            raise ValueError('native digest mismatch: ' + entry['id'])
        layer = Image.open(path).convert('RGBA')
        x,y,w,h = entry['crop']
        alpha = layer.getchannel('A')
        for index, value in enumerate(alpha.tobytes()):
            if value:
                ownership[(y + index//w)*width + x + index%w] += 1
        composed.paste(layer, (x,y), alpha)
    if composed.tobytes() != expected.tobytes():
        raise ValueError('native recomposition differs from normalized source')
    if any(value != 1 for value in ownership):
        raise ValueError('source pixels are duplicated or lost')
    if digest(output/'ground.png') != manifest['ground']['sha256']:
        raise ValueError('ground digest mismatch')
    with tempfile.TemporaryDirectory(prefix='mib-town-cold-') as directory:
        cold = Path(directory)
        bake(cold)
        if {p.name: digest(p) for p in cold.iterdir()} != {p.name: digest(p) for p in output.iterdir() if p.suffix in ['.png', '.json']}:
            raise ValueError('cold regeneration differs byte-for-byte')
    print(f'TOWN_LAYERS PASS native={len(manifest["native"])} pixels={len(ownership)} cold_bytes=identical recomposition=exact ownership=once underplate=transparent')


def author_scene(manifest):
    """One-time source conversion: runtime never consumes the legacy layout."""
    layout = json.loads(LAYOUT.read_text())
    w,h = layout['world']
    point = lambda uv: [uv[0]*w, uv[1]*h]
    vec = lambda xy: 'Vector2(%s, %s)' % tuple(format(float(v), '.12g') for v in xy)
    quoted = lambda value: json.dumps(value, ensure_ascii=False)
    lines = ['[gd_scene load_steps=2 format=3]',
      '[ext_resource type="Script" path="res://src/runtime/world/town_scene_root.gd" id="1_town"]',
      '[node name="HearthsideTown" type="Node2D"]', 'script = ExtResource("1_town")',
      'world_size = '+vec([w,h]), 'view_size = '+vec(layout['view_size']),
      'hero_screen_anchor = '+vec(layout['hero_screen_anchor']),
      '[node name="Ground" type="Node2D" parent="."]',
      '[node name="Surface" type="Sprite2D" parent="Ground"]',
      'centered = false', 'metadata/binding_id = "town/ground"',
      'metadata/texture_path = "res://content/rooms/town/layers/ground.png"',
      '[node name="GroundEffects" type="Node2D" parent="."]',
      '[node name="SortRoot" type="Node2D" parent="."]', 'y_sort_enabled = true']
    for entry in manifest['native']:
        x,y,cw,ch = entry['crop']
        lines += ['[node name='+quoted(entry['id'])+' type="Sprite2D" parent="SortRoot"]',
          'position = '+vec(entry['feet']), 'centered = false',
          'offset = '+vec([x-entry['feet'][0],y-entry['feet'][1]]),
          'metadata/binding_id = '+quoted('town/native/'+entry['id']),
          'metadata/interaction = '+quoted(entry['interaction']),
          'metadata/texture_path = '+quoted(entry['path'])]
    lines += ['[node name="Foreground" type="Node2D" parent="."]',
      '[node name="GeometrySources" type="Node2D" parent="."]',
      '[node name="MovementBoundary" type="Node2D" parent="GeometrySources"]',
      'metadata/binding_id = "town/movement-boundary"',
      'metadata/rect = Rect2(14, 14, %s, %s)' % (w-28,h-28),
      '[node name="Static" type="Node2D" parent="GeometrySources"]']
    for index, shape in enumerate(layout['collision']['world_uv']):
        lines += ['[node name='+quoted(shape['id'])+' type="Polygon2D" parent="GeometrySources/Static"]',
          'visible = false', 'metadata/binding_id = '+quoted('town/static/'+shape['id'])]
        if shape['kind'] == 'polygon':
            coords = [v for pair in shape['points'] for v in point(pair)]
            lines += ['polygon = PackedVector2Array('+', '.join(format(v,'.12g') for v in coords)+')']
        else:
            lines += ['position = '+vec(point(shape['center'])),
                      'metadata/radius = '+format(shape['radius']*min(w,h),'.12g')]
    lines += ['[node name="Routes" type="Node2D" parent="GeometrySources"]']
    for route, points in sorted(layout['routes_uv'].items()):
        lines += ['[node name='+quoted(route)+' type="Node2D" parent="GeometrySources/Routes"]']
        for index, uv in enumerate(points):
            lines += ['[node name="Point%02d" type="Marker2D" parent="GeometrySources/Routes/%s"]' % (index,route), 'position = '+vec(point(uv))]
    lines += ['[node name="Sockets" type="Node2D" parent="."]',
      '[node name="Spawn" type="Marker2D" parent="Sockets"]', 'position = '+vec(point(layout['hero_start_uv'])),
      'metadata/binding_id = "town/spawn"', 'metadata/kind = "spawn"']
    for index, placement in enumerate(layout['placements']):
        id = placement['id']
        kind = 'resident' if placement.get('layer') == 'npc' else 'interaction'
        lines += ['[node name='+quoted(id)+' type="Marker2D" parent="Sockets"]',
          'position = '+vec(point(placement['feet_uv'])), 'metadata/binding_id = '+quoted('town/'+kind+'/'+id),
          'metadata/kind = '+quoted(kind), 'metadata/id = '+quoted(id)]
        if kind == 'resident':
            lines += ['metadata/role = '+quoted(placement['role'])]
        else:
            lines += ['metadata/label = '+quoted(placement['label']), 'metadata/radius = '+str(placement['radius']),
                      'metadata/order = '+str(index), 'metadata/landmark_offset_y = -112.0', 'metadata/locked = '+('true' if id == 'proxy' else 'false')]
    (ROOT/'content/rooms/town/hearthside.tscn').write_text('\n\n'.join(lines)+'\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true', help='Read-only verification, including cold regeneration in /tmp')
    parser.add_argument('--author-scene', action='store_true', help='Convert the approved legacy authored geometry once to native scene source')
    args = parser.parse_args()
    if args.check:
        verify(OUT)
    else:
        manifest = bake(OUT)
        if args.author_scene:
            author_scene(manifest)
        verify(OUT)
