#!/usr/bin/env python3
"""Technical packing only: alpha threshold, uniform nearest sampling, padding.

Original generated pixels and prompts remain in docs/art-production. No old
sprite pixels or programmatically painted artwork are used. --verify computes
outputs in memory and compares without mutating production files.
"""
from pathlib import Path
from fractions import Fraction
import hashlib
import importlib.util
import io
import json
import sys
from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / 'docs/art-production/world-polish-20261025'
OUT = ROOT / 'art/production/p1/world_polish_v01'
SIZES = {'fern': (48, 32), 'mushrooms': (32, 24), 'votives': (32, 24),
         'relic': (48, 32), 'piercing_arrow': (32, 32),
         'hunter_mark': (32, 32), 'dash': (32, 32), 'basic_dodge': (32, 32)}
ICONS = ['piercing_arrow', 'hunter_mark', 'dash', 'basic_dodge']


def json_bytes(value):
    return (json.dumps(value, indent=2, sort_keys=True) + '\n').encode()


def compile_pack():
    outputs, entries = {}, {}
    for name, (w, h) in SIZES.items():
        path = SOURCE / 'sources' / (name + '_raw.png')
        raw = Image.open(path).convert('RGBA')
        alpha = raw.getchannel('A').point(lambda a: 255 if a >= 240 else 0)
        box = alpha.getbbox()
        if box is None:
            raise ValueError(name + ': no occupied pixels')
        raw.putalpha(alpha)
        cropped = raw.crop(box)
        scale = min(Fraction(w - 4, cropped.width), Fraction(h - 4, cropped.height))
        dw = max(1, (cropped.width * scale.numerator + scale.denominator - 1) // scale.denominator)
        dh = max(1, (cropped.height * scale.numerator + scale.denominator - 1) // scale.denominator)
        # Both axes use the SAME rational scale; no aspect-changing resize.
        sampled = Image.new('RGBA', (dw, dh))
        for y in range(dh):
            sy = min(cropped.height - 1, (2*y+1)*scale.denominator // (2*scale.numerator))
            for x in range(dw):
                sx = min(cropped.width - 1, (2*x+1)*scale.denominator // (2*scale.numerator))
                pixel = cropped.getpixel((sx, sy))
                sampled.putpixel((x, y), pixel if pixel[3] else (0, 0, 0, 0))
        canvas = Image.new('RGBA', (w, h))
        top = (h-dh)//2 if name in ICONS else h-2-dh
        left = (w-dw)//2
        canvas.paste(sampled, (left, top))
        occupied = canvas.getchannel('A').getbbox()
        assert occupied and occupied[0] >= 2 and occupied[1] >= 2
        assert occupied[2] <= w-2 and occupied[3] <= h-2
        buf = io.BytesIO()
        canvas.save(buf, format='PNG', optimize=False)
        outputs[name + '.png'] = buf.getvalue()
        entries[name] = {'path': 'res://art/production/p1/world_polish_v01/' + name + '.png',
                         'canvas': [w, h], 'anchor': [w//2, h//2 if name in ICONS else h-2],
                         'occupied_rect': [occupied[0], occupied[1], occupied[2]-occupied[0], occupied[3]-occupied[1]],
                         'source_sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
                         'prompt_sha256': hashlib.sha256((SOURCE/'prompts'/(name+'.txt')).read_bytes()).hexdigest(),
                         'source_box': list(box), 'scale': [scale.numerator, scale.denominator]}
    outputs['assets.json'] = json_bytes({'schema_version': 1, 'generator': 'built-in image_gen; original assets',
                                       'packing': 'alpha>=240; uniform rational nearest; no alpha border fix',
                                       'assets': entries})
    outputs['combat_atlas.json'] = json_bytes({'schema_version': 1, 'sprites': [
        {'id': 'action.'+name, 'type': 'ui_icon', 'texture': name+'.png',
         'rect': [0, 0, 32, 32], 'anchor': [16, 16]} for name in ICONS]})
    return outputs


def main():
    outputs = compile_pack()
    if '--verify' in sys.argv:
        for name, data in outputs.items():
            assert (OUT/name).read_bytes() == data, name + ': stale output'
        print('WORLD_POLISH_PACK_VERIFY_PASS: 8 original assets; byte-identical')
        return
    OUT.mkdir(parents=True, exist_ok=True)
    spec = importlib.util.spec_from_file_location('actor_import_recipe', ROOT/'tools/art_pipeline/actors_v02/build.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    for name, data in outputs.items():
        path = OUT/name
        path.write_bytes(data)
        if path.suffix == '.png':
            module.sidecar(path)  # shared proven UID-preserving import recipe
    print('WORLD_POLISH_PACK_PASS: 8 original assets')


if __name__ == '__main__':
    main()
