#!/usr/bin/env python3
"""Author the world_expansion_v01 town layout into the native Hearthside scene.

The native scene stays the gameplay authority; the reviewed recipe
docs/art-production/world-expansion-20261025/town_layout.json declares only
expansion-owned content. Every block this tool writes carries
``metadata/expansion_owner`` (or is a recipe-named route) and is regenerated in
place, so --write is idempotent and never rewrites old natives, sockets or
routes other than disclosed recipe moves/route replacements.

Terrain collision is traced deterministically from the pinned, packed ground:
water = pixels with b > r + water_b and g > r + water_g, closed/opened with the
recipe filter sizes, largest component, then each column's top..bottom span.
The bank curves are Douglas-Peucker simplified with a vertical tolerance and
pushed outward by that tolerance, so the collision covers every traced water
column. Bridge decks are cut out exactly along their measured deck polygons.
Mountain cliffs use the same column (top band) / row (left band) rule on the
cool-grey stone mask. The hero radius is added by the motor, never here.

--check: exit 1 if the scene or layout checks are stale/failing (no writes).
--write: rewrite content/rooms/town/hearthside.tscn (requires status ready).
--output PATH: write a preview scene elsewhere; --report writes a JSON report
and a preview PNG to build/current/world-expansion-v01/town-layout/.
Run tools/town_layers/bake_spatial.gd after --write.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
import author_ground_footprints as old_footprints  # noqa: E402

SCENE = ROOT / 'content/rooms/town/hearthside.tscn'
RECIPE = ROOT / 'docs/art-production/world-expansion-20261025/town_layout.json'
OLD_ASSETS = ROOT / 'art/production/p1/generated_world_v02/assets.json'
OLD_RECIPE = old_footprints.RECIPE
REPORT_DIR = ROOT / 'build/current/world-expansion-v01/town-layout'
OWNER = 'world_expansion_v01'
OWNER_LINE = f'metadata/expansion_owner = "{OWNER}"'
OVERRIDE_KEY = 'metadata/expansion_override = '
WORLD = (1536, 960)
ANCHORS = {
    'Ground': '[node name="GroundEffects"',
    'SortRoot': '[node name="Foreground"',
    'GeometrySources/Static': '[node name="Routes" type="Node2D" parent="GeometrySources"]',
    'GeometrySources/Routes': '[node name="Sockets" type="Node2D" parent="."]',
    'Sockets': None,
}


class AuthorError(Exception):
    pass


def require(ok, message):
    if not ok:
        raise AuthorError(message)


def num(value):
    value = float(value)
    return format(value, '.12g') if value != int(value) else str(int(value))


def vec(point):
    return f'Vector2({num(point[0])}, {num(point[1])})'


def floats(text):
    return [float(v) for v in text.split(',')]


def res_path(path):
    return ROOT / path.removeprefix('res://')


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


# ---------------------------------------------------------------- geometry

def polygon_area(points):
    return sum(a[0]*b[1] - b[0]*a[1] for a, b in zip(points, points[1:] + points[:1])) / 2


def segments_cross(p, q, r, s):
    def orient(a, b, c):
        return (b[0]-a[0])*(c[1]-a[1]) - (b[1]-a[1])*(c[0]-a[0])
    d1, d2, d3, d4 = orient(r, s, p), orient(r, s, q), orient(p, q, r), orient(p, q, s)
    return d1*d2 < 0 and d3*d4 < 0


def polygon_is_simple(points):
    edges = list(zip(points, points[1:] + points[:1]))
    for i, (p, q) in enumerate(edges):
        for j in range(i+2, len(edges)):
            if i == 0 and j == len(edges)-1:
                continue
            if segments_cross(p, q, *edges[j]):
                return False
    return len({tuple(p) for p in points}) == len(points)


def point_in_polygon(point, poly):
    x, y = point
    inside = False
    for (ax, ay), (bx, by) in zip(poly, poly[1:] + poly[:1]):
        if (ay > y) != (by > y) and x < ax + (y-ay)*(bx-ax)/(by-ay):
            inside = not inside
    return inside


def segment_distance(p, a, b):
    dx, dy = b[0]-a[0], b[1]-a[1]
    length = dx*dx + dy*dy
    t = 0 if length == 0 else max(0, min(1, ((p[0]-a[0])*dx + (p[1]-a[1])*dy)/length))
    return math.hypot(p[0]-a[0]-t*dx, p[1]-a[1]-t*dy)


def polygon_distance(point, poly):
    edge = min(segment_distance(point, a, b) for a, b in zip(poly, poly[1:] + poly[:1]))
    return -edge if point_in_polygon(point, poly) else edge


def bbox(poly):
    xs, ys = [p[0] for p in poly], [p[1] for p in poly]
    return min(xs), min(ys), max(xs), max(ys)


def simplify(points, tolerance):
    """Douglas-Peucker on a function y(x) using vertical deviation."""
    if len(points) < 3:
        return points
    a, b = points[0], points[-1]
    worst, index = -1, 0
    for i in range(1, len(points)-1):
        x, y = points[i]
        t = (x-a[0])/(b[0]-a[0]) if b[0] != a[0] else 0
        deviation = abs(y - (a[1] + t*(b[1]-a[1])))
        if deviation > worst:
            worst, index = deviation, i
    if worst <= tolerance:
        return [a, b]
    return simplify(points[:index+1], tolerance)[:-1] + simplify(points[index:], tolerance)


def interpolate(curve, x):
    for (ax, ay), (bx, by) in zip(curve, curve[1:]):
        if ax <= x <= bx:
            return ay if bx == ax else ay + (x-ax)/(bx-ax)*(by-ay)
    raise AuthorError(f'curve does not span x={x}')


# ------------------------------------------------------------- terrain trace

def masks(ground_path, trace):
    from PIL import Image, ImageFilter
    image = Image.open(ground_path).convert('RGB')
    require(image.size == WORLD, f'ground size {image.size} != {WORLD}')
    pixels = image.load()
    water_rule, stone_rule = trace['water'], trace['stone']
    water = Image.new('L', WORLD, 0)
    stone = Image.new('L', WORLD, 0)
    wp, sp = water.load(), stone.load()
    for y in range(WORLD[1]):
        for x in range(WORLD[0]):
            r, g, b = pixels[x, y]
            is_water = b > r + water_rule['b_over_r'] and g > r + water_rule['g_over_r']
            if is_water and y >= water_rule['min_y']:
                wp[x, y] = 255
            elif not is_water and b >= r - stone_rule['b_floor'] and abs(r-g) < stone_rule['rg_spread']:
                sp[x, y] = 255
    for size in water_rule['close']:
        water = water.filter(ImageFilter.MaxFilter(size)).filter(ImageFilter.MinFilter(size))
    for size in water_rule['open']:
        water = water.filter(ImageFilter.MinFilter(size)).filter(ImageFilter.MaxFilter(size))
    for size in stone_rule['close']:
        stone = stone.filter(ImageFilter.MaxFilter(size)).filter(ImageFilter.MinFilter(size))
    return largest_component(water), stone


def largest_component(mask):
    from PIL import Image
    width, height = mask.size
    data = bytearray(mask.tobytes())
    seen = bytearray(width*height)
    best = []
    for start in range(width*height):
        if not data[start] or seen[start]:
            continue
        seen[start] = 1
        stack, component = [start], []
        while stack:
            index = stack.pop()
            component.append(index)
            x, y = index % width, index // width
            for n, ok in ((index-1, x > 0), (index+1, x < width-1), (index-width, y > 0), (index+width, y < height-1)):
                if ok and data[n] and not seen[n]:
                    seen[n] = 1
                    stack.append(n)
        if len(component) > len(best):
            best = component
    out = bytearray(width*height)
    for index in best:
        out[index] = 255
    return Image.frombytes('L', mask.size, bytes(out))


def column_spans(mask):
    width, height = mask.size
    data = mask.tobytes()
    spans = {}
    for x in range(width):
        ys = [y for y in range(height) if data[y*width + x]]
        if ys:
            spans[x] = (min(ys), max(ys) + 1)
    return spans


def bank_curves(spans, tolerance):
    width = WORLD[0]
    require(all(x in spans for x in range(width)), 'traced river does not cross the whole world width')
    top = simplify([(x, spans[x][0]) for x in range(width)] + [(width, spans[width-1][0])], tolerance)
    bottom = simplify([(x, spans[x][1]) for x in range(width)] + [(width, spans[width-1][1])], tolerance)
    top = [(x, y - tolerance) for x, y in top]
    bottom = [(x, y + tolerance) for x, y in bottom]
    for x in range(width):
        require(interpolate(top, x) <= spans[x][0] and interpolate(bottom, x) >= spans[x][1], f'bank cover failed at x={x}')
    return top, bottom


def band_crossing(polyline, top, bottom):
    """Points where a north-to-south deck side enters and leaves the band."""
    samples = []
    for a, b in zip(polyline, polyline[1:]):
        steps = max(1, math.ceil(math.dist(a, b)*4))
        samples += [(a[0]+(b[0]-a[0])*i/steps, a[1]+(b[1]-a[1])*i/steps) for i in range(steps)]
    samples.append(polyline[-1])
    def inside(p):
        return 0 <= p[0] <= WORLD[0] and interpolate(top, p[0]) <= p[1] <= interpolate(bottom, p[0])
    flags = [inside(p) for p in samples]
    require(not flags[0] and not flags[-1], 'bridge deck side does not reach dry land at both ends')
    first, last = flags.index(True), len(flags) - 1 - flags[::-1].index(True)
    require(all(flags[first:last+1]), 'bridge deck side leaves and re-enters the water')
    def refine(outside, inner, curve):
        for _ in range(40):
            mid = ((outside[0]+inner[0])/2, (outside[1]+inner[1])/2)
            if inside(mid):
                inner = mid
            else:
                outside = mid
        return (round(inner[0], 4), round(inner[1], 4))
    entry = refine(samples[first-1], samples[first], top)
    exit_ = refine(samples[last+1], samples[last], bottom)
    interior = [p for p in polyline if inside(p)]
    return entry, interior, exit_


def water_pieces(top, bottom, cuts):
    """Split the band by bridge deck sides; cuts are ordered west->east pairs."""
    edges = [((0, top[0][1]), [], (0, bottom[0][1]))]
    for west_side, east_side in cuts:
        edges += [band_crossing(west_side, top, bottom), band_crossing(east_side, top, bottom)]
    edges.append(((WORLD[0], top[-1][1]), [], (WORLD[0], bottom[-1][1])))
    pieces = []
    for left, right in zip(edges[0::2], edges[1::2]):
        lt, li, lb = left
        rt, ri, rb = right
        poly = [lt] + [p for p in top if lt[0] < p[0] < rt[0]] + [rt] + ri + [rb]
        poly += [p for p in reversed(bottom) if lb[0] < p[0] < rb[0]] + [lb] + list(reversed(li))
        pieces.append([(round(x, 4), round(y, 4)) for x, y in poly])
    return pieces


def smooth(edge, window):
    """Running median of the cliff depth: isolated boulders touching the
    mountain foot stay walkable ground dressing instead of spiking collision."""
    half = window // 2
    depths = [d for _, d in edge]
    return [(k, sorted(depths[max(0, i-half):i+half+1])[len(depths[max(0, i-half):i+half+1])//2])
            for i, (k, _) in enumerate(edge)]


def cliff_polygons(stone, cliffs):
    width, height = stone.size
    data = stone.tobytes()
    result = []
    for cliff in cliffs:
        tolerance = cliff['tolerance']
        if cliff['axis'] == 'columns':
            x0, x1, limit = cliff['from'], cliff['to'], cliff['limit']
            edge = []
            for x in range(x0, x1):
                y = 0
                while y < limit and data[y*width + x]:
                    y += 1
                edge.append((x, y))
            edge = smooth(edge, cliff['median'])
            edge.append((x1, edge[-1][1]))
            curve = [(x, y + tolerance) for x, y in simplify(edge, tolerance)]
            for x, y in edge:
                require(interpolate(curve, x) >= y, f'{cliff["id"]} cover failed')
            poly = [(x0, 0), (x1, 0)] + list(reversed(curve))
        else:
            y0, y1, limit = cliff['from'], cliff['to'], cliff['limit']
            edge = []
            for y in range(y0, y1):
                x = 0
                while x < limit and data[y*width + x]:
                    x += 1
                edge.append((y, x))
            edge = smooth(edge, cliff['median'])
            edge.append((y1, edge[-1][1]))
            curve = [(y, x + tolerance) for y, x in simplify(edge, tolerance)]
            for y, x in edge:
                require(interpolate(curve, y) >= x, f'{cliff["id"]} cover failed')
            poly = [(0, y0)] + [(x, y) for y, x in curve] + [(0, y1)]
        poly = [p for i, p in enumerate(poly) if p != poly[i-1]]
        result.append({'id': cliff['id'], 'kind': 'cliff', 'polygon': poly, 'reason': cliff['reason']})
    return result


# --------------------------------------------------------------- recipe load

def load_inputs():
    recipe = json.loads(RECIPE.read_text())
    require(recipe.get('schema_version') == 1, 'unknown town_layout schema')
    manifest = json.loads((ROOT / recipe['assets_manifest']).read_text())
    assets = manifest['assets']
    for pack, path in recipe.get('packs', {}).items():
        for key, record in json.loads((ROOT / path).read_text())['assets'].items():
            assets[f'{pack}/{key}'] = record
    old_assets = json.loads(OLD_ASSETS.read_text())['assets']
    return recipe, assets, old_assets


def world_points(points, feet, anchor):
    return [(feet[0] - anchor[0] + x, feet[1] - anchor[1] + y) for x, y in points]


def footprint_shapes(family, record, footprint, pad):
    shapes = []
    for rect in footprint.get('rects', []):
        x, y, w, h = rect
        require(0 <= x < x+w <= record['canvas'][0] and 0 <= y < y+h <= record['canvas'][1], f'{family} rect leaves canvas')
        shapes.append([(x-pad, y-pad), (x+w+pad, y-pad), (x+w+pad, y+h+pad), (x-pad, y+h+pad)])
    for poly in footprint.get('polygons', []):
        poly = [tuple(p) for p in poly]
        require(polygon_is_simple(poly) and abs(polygon_area(poly)) > 1, f'{family} footprint polygon is not simple')
        shapes.append(outset(poly, pad))
    return shapes


def outset(poly, pad):
    """Miter outset of a convex raw plinth outline by the shared pad, so rect
    and polygon footprints get the same contact envelope."""
    sign = 1 if polygon_area(poly) > 0 else -1
    n = len(poly)
    for i in range(n):
        a, b, c = poly[i-1], poly[i], poly[(i+1) % n]
        require(sign*((b[0]-a[0])*(c[1]-b[1]) - (b[1]-a[1])*(c[0]-b[0])) > 0, 'footprint polygon must be convex')
    lines = []
    for i in range(n):
        a, b = poly[i], poly[(i+1) % n]
        dx, dy = b[0]-a[0], b[1]-a[1]
        length = math.hypot(dx, dy)
        nx, ny = sign*dy/length, -sign*dx/length
        lines.append(((a[0]+nx*pad, a[1]+ny*pad), (dx, dy)))
    result = []
    for i in range(n):
        (p, d), (q, e) = lines[i-1], lines[i]
        t = ((q[0]-p[0])*e[1] - (q[1]-p[1])*e[0]) / (d[0]*e[1] - d[1]*e[0])
        result.append((round(p[0]+d[0]*t, 4), round(p[1]+d[1]*t, 4)))
    return result


def validate(recipe, assets, old_assets):
    ready = recipe['status'] == 'ready'
    names = set()
    for item in recipe['placements']:
        family = item['family']
        require(item['name'] not in names and re.fullmatch(r'[a-z0-9_]+', item['name']), f'bad placement name {item["name"]}')
        names.add(item['name'])
        record = assets.get(family) if not family.startswith('generated_world_v02/') else old_assets.get(family.split('/', 1)[1])
        require(record is not None and record.get('status') == 'packed', f'{item["name"]}: family {family} is not packed')
        require(item.get('reason'), f'{item["name"]}: placement needs a reason')
        for key in ('path', 'opaque_path', 'transparent_path'):
            if record.get(key):
                require(res_path(record[key]).exists(), f'{family}: missing {record[key]}')
        if family in assets:
            require(sha256(res_path(record['path'])) == record['sha256'], f'{family}: opaque bytes differ from pack')
            if record.get('transparent_path'):
                require(sha256(res_path(record['transparent_path'])) == record['transparent_sha256'], f'{family}: transparent bytes differ')
    ground = assets.get(recipe['ground']['asset'], {})
    if ready:
        require(ground.get('status') == 'packed', 'town ground is not packed')
        source = ground['transform']['source']
        require(Path(source).name == recipe['ground']['source'], f'ground source {source} is not the approved winding raw')
        require(Path(source).name not in recipe['ground']['rejected_sources'], 'rejected straight-river ground')
        require(ground['raw_sha256'] == recipe['ground']['raw_sha256'] == sha256(ROOT / source), 'ground raw pin mismatch')
        require(sha256(res_path(ground['path'])) == ground['sha256'], 'ground bytes differ from pack')
    return ready, ground


# ------------------------------------------------------------ scene editing

def split_blocks(text):
    return re.split(r'(?=\[node )', text)


def header(block):
    match = re.match(r'\[node name="([^"]+)" type="([^"]+)"(?: parent="([^"]*)")?', block)
    return (match[1], match[2], match[3]) if match else (None, None, None)


def node_block(name, kind, parent, lines):
    return '\n\n'.join([f'[node name="{name}" type="{kind}" parent="{parent}"]'] + lines) + '\n\n'


def sprite_block(name, family_id, record, feet, group):
    anchor = record['anchor']
    path = record.get('path') or record.get('opaque_path')
    lines = ['position = ' + vec(feet), 'centered = false', 'offset = ' + vec([-anchor[0], -anchor[1]])]
    if group == 'Ground':
        lines += [f'metadata/binding_id = "town/ground/{name}"', f'metadata/environment_asset_id = "{family_id}"',
                  'metadata/reveal_policy = "none"', f'metadata/texture_path = "{path}"']
    else:
        rect = record['occlusion_rect']
        world = [feet[0]-anchor[0]+rect[0], feet[1]-anchor[1]+rect[1], rect[2], rect[3]]
        lines += [f'metadata/binding_id = "town/native/{name}"', 'metadata/interaction = ""',
                  f'metadata/environment_asset_id = "{family_id}"', 'metadata/sort_rank = 0',
                  'metadata/reveal_policy = "paired_reveal"', f'metadata/texture_path = "{path}"',
                  f'metadata/reveal_full_path = "{path}"',
                  f'metadata/reveal_variant_path = "{record["transparent_path"]}"',
                  'metadata/occlusion_rect = Rect2(' + ', '.join(num(v) for v in world) + ')']
    return node_block(name, 'Sprite2D', group, lines + [OWNER_LINE])


def static_block(name, points, kind):
    flat = ', '.join(num(v) for p in points for v in p)
    return node_block(name, 'Polygon2D', 'GeometrySources/Static', [
        'visible = false', f'metadata/binding_id = "town/static/{name}"', f'metadata/collision_kind = "{kind}"',
        OWNER_LINE, f'polygon = PackedVector2Array({flat})'])


def route_blocks(name, points):
    text = node_block(name, 'Node2D', 'GeometrySources/Routes', [OWNER_LINE])
    for index, point in enumerate(points):
        text += node_block(f'Point{index}', 'Marker2D', f'GeometrySources/Routes/{name}', ['position = ' + vec(point)])
    return text


def socket_block(item):
    lines = ['position = ' + vec(item['position'])]
    for key in ('binding_id', 'kind', 'id', 'label', 'gateway_action'):
        lines.append(f'metadata/{key} = {json.dumps(item[key])}')
    if 'order' in item:
        lines.append(f'metadata/order = {float(item["order"])!r}')
    lines.append(f'metadata/radius = {float(item["radius"])!r}')
    return node_block(item['name'], 'Marker2D', 'Sockets', lines + [OWNER_LINE])


def block_key(block, owned_routes):
    name, _, parent = header(block)
    if parent is None:
        return None
    if parent == 'GeometrySources/Routes' and name in owned_routes:
        return ('route', name)
    if parent.startswith('GeometrySources/Routes/') and parent.rsplit('/', 1)[1] in owned_routes:
        return ('route', parent.rsplit('/', 1)[1])
    if OWNER_LINE in block:
        return ('node', parent, name)
    return None


def build_units(recipe, assets, old_assets, terrain):
    pad = recipe['padding_native_px']
    units, shapes = {}, []
    for item in recipe['placements']:
        family = item['family']
        if family.startswith('generated_world_v02/'):
            short = family.split('/', 1)[1]
            record, family_id = old_assets[short], family
            footprint = {'rects': [json.loads(OLD_RECIPE.read_text())['town'][short]['rect']]}
            pad_used = json.loads(OLD_RECIPE.read_text())['padding_native_px']
        else:
            record, family_id = assets[family], family if '/' in family else f'{OWNER}/{family}'
            footprint, pad_used = recipe['footprints'][family], pad
        group = 'Ground' if record.get('reveal', True) is False else 'SortRoot'
        units[('node', group, item['name'])] = (group, sprite_block(item['name'], family_id, record, item['feet'], group))
        for index, local in enumerate(footprint_shapes(family, record, footprint, pad_used)):
            poly = world_points(local, item['feet'], record['anchor'])
            sid = f'{item["name"]}_footprint_{index}'
            shapes.append({'id': sid, 'kind': 'footprint', 'polygon': poly})
    for shape in terrain:
        shapes.append(shape)
    for shape in shapes:
        poly = [tuple(p) for p in shape['polygon']]
        require(len(poly) >= 3 and polygon_is_simple(poly) and abs(polygon_area(poly)) > 1, f'{shape["id"]}: polygon not simple')
        require(all(-1e-6 <= x <= WORLD[0]+1e-6 and -1e-6 <= y <= WORLD[1]+1e-6 for x, y in poly), f'{shape["id"]}: leaves world')
        node = shape['id'] if shape['kind'] == 'footprint' else f'terrain_{shape["id"]}'
        units[('node', 'GeometrySources/Static', node)] = ('GeometrySources/Static', static_block(node, poly, shape['kind']))
    for name, points in recipe['routes'].items():
        require(len(points) >= 2, f'route {name} too short')
        units[('route', name)] = ('GeometrySources/Routes', route_blocks(name, points))
    for item in recipe.get('sockets', []):
        require(item['kind'] == 'exit' and float(item['radius']) == 48.0, f'socket {item["name"]}: unsupported')
        units[('node', 'Sockets', item['name'])] = ('Sockets', socket_block(item))
    return units


def apply_moves(blocks, recipe, old_assets):
    moved = []
    for index, block in enumerate(blocks):
        name, kind, parent = header(block)
        move = recipe['moves'].get(name) if parent == 'SortRoot' and kind == 'Sprite2D' else None
        if not move:
            continue
        require(OWNER_LINE not in block, f'move targets owned node {name}')
        require(re.search(r'metadata/interaction = ""', block), f'{name}: facility objects never move')
        family = re.search(r'environment_asset_id = "generated_world_v02/([^"]+)"', block)[1]
        record = old_assets[family]
        current = floats(re.search(r'^position = Vector2\(([^)]+)\)', block, re.M)[1])
        known = [move['from'], move['to']] + move.get('previous', [])
        require(current in known, f'{name}: scene position {current} is not a recorded from/previous/to position')
        feet = move['to']
        rect = record['occlusion_rect']
        world = [feet[0]-record['anchor'][0]+rect[0], feet[1]-record['anchor'][1]+rect[1], rect[2], rect[3]]
        block = re.sub(r'^position = Vector2\([^)]+\)', 'position = ' + vec(feet), block, count=1, flags=re.M)
        block = re.sub(r'metadata/occlusion_rect = Rect2\([^)]+\)', 'metadata/occlusion_rect = Rect2(' + ', '.join(num(v) for v in world) + ')', block)
        blocks[index] = block
        moved.append(name)
    require(sorted(moved) == sorted(recipe['moves']), f'moves not found: {sorted(set(recipe["moves"]) - set(moved))}')


def apply_overrides(blocks, recipe, assets, old_assets):
    """Swap an original native (facility) visual and envelope to a reviewed
    orientation variant in place: node name, feet, binding, interaction and
    sockets stay; art paths, detection rect and floor footprint follow the
    new packed art. Idempotent: rewritten from the recipe every run."""
    overrides = recipe.get('facility_overrides', {})
    pad = recipe['padding_native_px']
    done = set()
    for index, block in enumerate(blocks):
        name, kind, parent = header(block)
        target = name.removesuffix('_envelope') if parent == 'GeometrySources/Static' else name
        if target not in overrides or parent not in ('SortRoot', 'GeometrySources/Static'):
            continue
        family = overrides[target]['family']
        record = assets[family]
        sprite = next(b for b in blocks if header(b)[:3] == (target, 'Sprite2D', 'SortRoot'))
        feet = floats(re.search(r'^position = Vector2\(([^)]+)\)', sprite, re.M)[1])
        require(record['anchor'] == old_assets[overrides[target]['original']]['anchor'] and record['canvas'] == old_assets[overrides[target]['original']]['canvas'], f'{target}: override must keep the original canvas and anchor')
        line = f'{OVERRIDE_KEY}"{family}"'
        block = re.sub(r'\n' + re.escape(OVERRIDE_KEY) + r'[^\n]*\n', '\n', block)
        if parent == 'SortRoot':
            rect = record['occlusion_rect']
            world = [feet[0]-record['anchor'][0]+rect[0], feet[1]-record['anchor'][1]+rect[1], rect[2], rect[3]]
            for key, value in (('environment_asset_id', family), ('texture_path', record['path']),
                               ('reveal_full_path', record['path']), ('reveal_variant_path', record['transparent_path'])):
                block = re.sub(rf'metadata/{key} = "[^"]*"', f'metadata/{key} = "{value}"', block, count=1)
            block = re.sub(r'metadata/occlusion_rect = Rect2\([^)]+\)', 'metadata/occlusion_rect = Rect2(' + ', '.join(num(v) for v in world) + ')', block)
        else:
            shapes = footprint_shapes(family, record, recipe['footprints'][family], pad)
            require(len(shapes) == 1, f'{target}: override footprint must be one polygon')
            poly = world_points(shapes[0], feet, record['anchor'])
            block = re.sub(r'polygon = PackedVector2Array\([^\n]+\)', 'polygon = PackedVector2Array(' + ', '.join(num(v) for p in poly for v in p) + ')', block)
        blocks[index] = block.rstrip('\n') + '\n\n' + line + '\n\n'
        done.add((target, parent))
    require(len(done) == 2*len(overrides), f'facility overrides incomplete: {sorted(done)}')


def assemble(text, recipe, assets, old_assets, terrain, ground):
    blocks = split_blocks(text)
    apply_moves(blocks, recipe, old_assets)
    apply_overrides(blocks, recipe, assets, old_assets)
    units = build_units(recipe, assets, old_assets, terrain)
    owned_routes = set(recipe['routes']) | {header(b)[0] for b in blocks if header(b)[2] == 'GeometrySources/Routes' and OWNER_LINE in b}
    emitted, out = set(), []
    pending = {section: [key for key, (sec, _) in units.items() if sec == section] for section in ANCHORS}
    for block in blocks:
        for section, anchor in ANCHORS.items():
            if anchor and block.startswith(anchor):
                out += [units[key][1] for key in pending[section] if key not in emitted]
                emitted.update(pending[section])
        key = block_key(block, owned_routes)
        if key is None:
            out.append(block)
        elif key in units and key not in emitted:
            out.append(units[key][1])
            emitted.add(key)
    tail = [units[key][1] for key in pending['Sockets'] if key not in emitted]
    emitted.update(pending['Sockets'])
    require(emitted == set(units), f'unplaced units {set(units) - emitted}')
    result = ''.join(out)
    if tail:
        result = result.rstrip('\n') + '\n\n' + ''.join(tail)
    result = result.rstrip('\n') + '\n'
    if recipe['status'] == 'ready':
        path = ground['path']
        result = re.sub(r'^modular_underplate_path = "[^"]+"', f'modular_underplate_path = "{path}"', result, count=1, flags=re.M)
        result = re.sub(r'(\[node name="Surface" type="Sprite2D" parent="Ground"\][^\[]*?metadata/texture_path = )"[^"]+"',
                        lambda m: m[1] + f'"{path}"', result, count=1)
    old_recipe = json.loads(OLD_RECIPE.read_text())
    return old_footprints.patch_text(result, 'town', old_recipe, old_assets)


# ------------------------------------------------------------ layout checks

def scene_geometry(text):
    shapes, sockets, routes, sprites = [], [], {}, []
    for block in split_blocks(text):
        name, kind, parent = header(block)
        if parent == 'GeometrySources/Static':
            p = floats(re.search(r'PackedVector2Array\(([^)]*)\)', block)[1])
            shapes.append({'id': name, 'polygon': list(zip(p[0::2], p[1::2])), 'owned': OWNER_LINE in block})
        elif parent == 'Sockets':
            meta = dict(re.findall(r'^metadata/(\w+) = (.+)$', block, re.M))
            pos = floats(re.search(r'^position = Vector2\(([^)]+)\)', block, re.M)[1])
            sockets.append({'name': name, 'position': pos, **{k: json.loads(v) if v[0] in '"-0123456789tf' else v for k, v in meta.items()}})
        elif parent and parent.startswith('GeometrySources/Routes/'):
            routes.setdefault(parent.rsplit('/', 1)[1], []).append(floats(re.search(r'position = Vector2\(([^)]+)\)', block)[1]))
        elif parent in ('SortRoot', 'Ground') and kind == 'Sprite2D' and name != 'Surface':
            sprites.append((name, parent))
        elif name == 'MovementBoundary':
            boundary = floats(re.search(r'Rect2\(([^)]+)\)', block)[1])
    for shape in shapes:
        shape['bbox'] = bbox(shape['polygon'])
    return shapes, sockets, routes, sprites, boundary


def clearance(point, radius, shapes, boundary):
    x, y, w, h = boundary
    if not (x+radius <= point[0] <= x+w-radius and y+radius <= point[1] <= y+h-radius):
        return 'boundary'
    for shape in shapes:
        x0, y0, x1, y1 = shape['bbox']
        if x0-radius-1 <= point[0] <= x1+radius+1 and y0-radius-1 <= point[1] <= y1+radius+1:
            if polygon_distance(point, shape['polygon']) <= radius + 0.001:
                return shape['id']
    return None


def blocked_mask(shapes, sockets, boundary, radius, decks=()):
    from PIL import Image, ImageDraw, ImageFilter
    mask = Image.new('L', WORLD, 0)
    draw = ImageDraw.Draw(mask)
    for shape in shapes:
        draw.polygon([tuple(p) for p in shape['polygon']], fill=255)
    for deck in decks:
        draw.polygon([tuple(p) for p in deck], fill=255)
    for item in sockets:
        if item.get('kind') == 'resident':
            r = float(item['radius'])
            draw.ellipse([item['position'][0]-r, item['position'][1]-r, item['position'][0]+r, item['position'][1]+r], fill=255)
    size = 2*int(radius)+1
    mask = mask.filter(ImageFilter.MaxFilter(size))
    x, y, w, h = boundary
    edge = ImageDraw.Draw(mask)
    edge.rectangle([0, 0, WORLD[0], y+radius-1], fill=255)
    edge.rectangle([0, y+h-radius+1, WORLD[0], WORLD[1]], fill=255)
    edge.rectangle([0, 0, x+radius-1, WORLD[1]], fill=255)
    edge.rectangle([x+w-radius+1, 0, WORLD[0], WORLD[1]], fill=255)
    return mask


def reachable(mask, start):
    from PIL import ImageDraw
    filled = mask.copy()
    ImageDraw.floodfill(filled, (int(start[0]), int(start[1])), 128)
    return filled


def check_layout(text, recipe, assets, terrain_info):
    radius = recipe['hero_radius']
    shapes, sockets, routes, sprites, boundary = scene_geometry(text)
    failures = []
    def fail(kind, **data):
        failures.append({'check': kind, **data})
    facilities = [s for s in sockets if s.get('kind') == 'interaction']
    residents = [s for s in sockets if s.get('kind') == 'resident']
    gateways = [s for s in sockets if s.get('kind') == 'exit']
    if len(facilities) != 5 or any(float(f['radius']) != 48 for f in facilities):
        fail('facility_contract', count=len(facilities))
    resident_shapes = [{'id': 'resident:' + r['id'], 'polygon': [(r['position'][0] + 7*math.cos(a*math.pi/16), r['position'][1] + 7*math.sin(a*math.pi/16)) for a in range(32)]} for r in residents]
    for shape in resident_shapes:
        shape['bbox'] = bbox(shape['polygon'])
    everything = shapes + resident_shapes
    for item in facilities + gateways:
        if (blocker := clearance(item['position'], radius, everything, boundary)):
            fail('socket_blocked', socket=item['name'], blocker=blocker)
    for item in residents:
        if (blocker := clearance(item['position'], float(item['radius']), shapes, boundary)):
            fail('resident_blocked', socket=item['name'], blocker=blocker)
    samples = 0
    for name, points in routes.items():
        for a, b in zip(points, points[1:]):
            steps = max(1, math.ceil(math.dist(a, b)))
            for i in range(steps+1):
                p = (a[0]+(b[0]-a[0])*i/steps, a[1]+(b[1]-a[1])*i/steps)
                samples += 1
                if (blocker := clearance(p, radius, everything, boundary)):
                    fail('route_blocked', route=name, at=[round(p[0], 2), round(p[1], 2)], blocker=blocker)
                    break
    probes = recipe['probes']
    for point in probes['clear']:
        if (blocker := clearance(point, radius, everything, boundary)):
            fail('probe_not_clear', at=point, blocker=blocker)
    for point in probes['blocked']:
        if clearance(point, radius, everything, boundary) is None:
            fail('probe_not_blocked', at=point)
    for crossing in probes['crossings']:
        for a, b in zip(crossing['path'], crossing['path'][1:]):
            steps = max(1, math.ceil(math.dist(a, b)))
            for i in range(steps+1):
                p = (a[0]+(b[0]-a[0])*i/steps, a[1]+(b[1]-a[1])*i/steps)
                if (blocker := clearance(p, radius, everything, boundary)):
                    fail('crossing_blocked', crossing=crossing['id'], at=[round(p[0], 2), round(p[1], 2)], blocker=blocker)
                    break
    spawn = next(s for s in sockets if s.get('kind') == 'spawn')['position']
    if terrain_info:
        # Over-blocking (square dilation) proves reachability; under-blocking
        # (dilation radius-2) with decks filled proves the river is closed.
        over = reachable(blocked_mask(shapes, sockets, boundary, radius+2), spawn)
        under = reachable(blocked_mask(shapes, sockets, boundary, radius-2, terrain_info['decks']), spawn)
        for point in probes['south_bank'] + [f['position'] for f in facilities + gateways]:
            if over.getpixel((int(point[0]), int(point[1]))) != 128:
                fail('unreachable', at=point)
        for point in probes['south_bank']:
            if under.getpixel((int(point[0]), int(point[1]))) == 128:
                fail('river_leak_without_bridge', at=point)
        from PIL import Image, ImageDraw, ImageFilter
        coll = Image.new('L', WORLD, 0)
        draw = ImageDraw.Draw(coll)
        for shape in shapes:
            if shape['id'].startswith('terrain_water'):
                draw.polygon([tuple(p) for p in shape['polygon']], fill=255)
        near = coll.filter(ImageFilter.MaxFilter(2*(radius-2)+1))
        deck_mask = Image.new('L', WORLD, 0)
        for deck in terrain_info['decks']:
            ImageDraw.Draw(deck_mask).polygon([tuple(p) for p in deck], fill=255)
        water, nb, dk = terrain_info['water'].tobytes(), near.tobytes(), deck_mask.tobytes()
        uncovered = sum(1 for i in range(len(water)) if water[i] and not nb[i] and not dk[i])
        if uncovered:
            fail('water_not_covered', pixels=uncovered)
    return {'checks': samples, 'static_shapes': len(shapes), 'owned_shapes': sum(s['owned'] for s in shapes),
            'sprites': len(sprites), 'facilities': len(facilities), 'gateways': len(gateways),
            'failure_count': len(failures), 'failures': failures[:30]}


# ------------------------------------------------------------------- main

def terrain_for(recipe, assets):
    trace = recipe.get('trace')
    if recipe['status'] != 'ready' or not trace:
        return [], None
    ground_path = res_path(assets[recipe['ground']['asset']]['path'])
    water, stone = masks(ground_path, trace)
    top, bottom = bank_curves(column_spans(water), trace['water']['tolerance'])
    cuts, decks = [], []
    bridges = sorted((p for p in recipe['placements'] if p['family'] in recipe['footprints'] and recipe['footprints'][p['family']].get('deck')),
                     key=lambda p: p['feet'][0])
    for bridge in bridges:
        record = assets[bridge['family']]
        spec = recipe['footprints'][bridge['family']]
        deck = world_points(spec['deck'], bridge['feet'], record['anchor'])
        decks.append(deck)
        cuts.append((world_points(spec['deck_west_side'], bridge['feet'], record['anchor']),
                     world_points(spec['deck_east_side'], bridge['feet'], record['anchor'])))
    terrain = [{'id': f'water_{i}', 'kind': 'water', 'polygon': poly} for i, poly in enumerate(water_pieces(top, bottom, cuts))]
    terrain += cliff_polygons(stone, trace['cliffs'])
    return terrain, {'water': water, 'decks': decks, 'top': top, 'bottom': bottom}


def preview(text, info, path):
    from PIL import Image, ImageDraw
    recipe = json.loads(RECIPE.read_text())
    ground = Image.open(res_path(json.loads((ROOT / recipe['assets_manifest']).read_text())['assets']['town_ground']['path'])).convert('RGBA')
    draw = ImageDraw.Draw(ground)
    shapes, sockets, routes, _, _ = scene_geometry(text)
    for shape in shapes:
        draw.polygon([tuple(p) for p in shape['polygon']], outline=(0, 200, 255, 255) if shape['owned'] else (255, 0, 0, 255))
    for deck in (info or {}).get('decks', []):
        draw.polygon([tuple(p) for p in deck], outline=(0, 255, 0, 255))
    for points in routes.values():
        draw.line([tuple(p) for p in points], fill=(255, 255, 0, 255))
    for item in sockets:
        x, y = item['position']
        draw.ellipse([x-4, y-4, x+4, y+4], outline=(255, 255, 255, 255))
    ground.save(path)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--check', action='store_true')
    mode.add_argument('--write', action='store_true')
    mode.add_argument('--output', type=Path)
    parser.add_argument('--report', action='store_true')
    args = parser.parse_args()
    try:
        recipe, assets, old_assets = load_inputs()
        ready, ground = validate(recipe, assets, old_assets)
        if args.write:
            require(ready, f'recipe status is {recipe["status"]!r}; --write requires "ready"')
        terrain, info = terrain_for(recipe, assets)
        current = SCENE.read_text()
        result = assemble(current, recipe, assets, old_assets, terrain, ground)
        require(assemble(result, recipe, assets, old_assets, terrain, ground) == result, 'authoring is not idempotent')
        report = check_layout(result, recipe, assets, info)
    except AuthorError as error:
        print(json.dumps({'ok': False, 'error': str(error)}))
        return 2
    stale = result != current
    report.update({'status': recipe['status'], 'stale': stale})
    if args.report:
        REPORT_DIR.mkdir(parents=True, exist_ok=True)
        (REPORT_DIR / 'layout_report.json').write_text(json.dumps(report, indent=2) + '\n')
        preview(result, info, REPORT_DIR / 'layout_preview.png')
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(result)
    if args.write and stale and not report['failure_count']:
        SCENE.write_text(result)
    print(json.dumps(report))
    if report['failure_count']:
        return 1
    return 1 if args.check and stale else 0


if __name__ == '__main__':
    raise SystemExit(main())
