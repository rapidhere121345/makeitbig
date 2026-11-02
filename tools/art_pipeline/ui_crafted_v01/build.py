#!/usr/bin/env python3
"""Pack approved UI sources using nearest-neighbour sampling; --verify is read-only."""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import io
import json
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
SRC = ROOT / 'docs/art-production/ui-crafted-20261101/sources'
OUT = ROOT / 'art/production/p1/ui_crafted_v01'
RECIPE = ROOT / 'docs/art-production/ui-crafted-20261101/recipe.json'
SPEC = importlib.util.spec_from_file_location('world_expansion_pack', ROOT / 'tools/art_pipeline/world_expansion_v01/pack.py')
WORLD = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(WORLD)


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def encode(image: Image.Image) -> bytes:
    stream = io.BytesIO()
    image.save(stream, format='PNG', optimize=False)
    return stream.getvalue()


def compile_outputs() -> dict[str, bytes]:
    recipe = json.loads(RECIPE.read_text())
    result = {}
    records = {}
    for name, cfg in recipe['assets'].items():
        source_path = SRC / cfg['source']
        data = source_path.read_bytes()
        if digest(data) != cfg['sha256']:
            raise ValueError(f'{name}: source hash mismatch')
        image = Image.open(io.BytesIO(data))
        image.load()
        if list(image.size) != cfg['source_size'] or image.mode != cfg['source_mode']:
            raise ValueError(f'{name}: source image contract changed')
        if name == 'workshop':
            # A centered exact 16:9 crop preserves the source aspect ratio.
            crop = (4, 2, 1668, 938)
            output = image.crop(crop).resize((1280, 720), Image.Resampling.NEAREST)
            transform = {'crop_xyxy': list(crop), 'scaled_size': [1280, 720], 'canvas': [1280, 720], 'offset': [0, 0]}
        else:
            alpha = image.getchannel('A')
            threshold = cfg.get('crop_alpha_greater_than', 0)
            crop = alpha.point(lambda value: 255 if value > threshold else 0).getbbox()
            if crop is None:
                raise ValueError(f'{name}: empty alpha')
            cut = image.crop(crop)
            if name == 'action':
                target = (512, (cut.height * 512 + cut.width // 2) // cut.width)
                output = cut.resize(target, Image.Resampling.NEAREST)
                offset = (0, 0)
            else:
                target = ((cut.width * 144 + max(cut.size) // 2) // max(cut.size),
                          (cut.height * 144 + max(cut.size) // 2) // max(cut.size))
                resized = cut.resize(target, Image.Resampling.NEAREST)
                output = Image.new('RGBA', (160, 160), (0, 0, 0, 0))
                offset = ((160 - target[0]) // 2, (160 - target[1]) // 2)
                output.paste(resized, offset)
            transform = {'crop_xyxy': list(crop), 'scaled_size': list(target), 'canvas': list(output.size), 'offset': list(offset)}
            if 'crop_alpha_greater_than' in cfg:
                transform['crop_alpha_greater_than'] = threshold
            if output.getchannel('A').getextrema()[0] != 0 or output.getchannel('A').getextrema()[1] == 0:
                raise ValueError(f'{name}: expected transparent and visible pixels')
        encoded = encode(output)
        filename = name + '.png'
        result[filename] = encoded
        side = OUT / (filename + '.import')
        prior = side.read_text() if side.exists() else None
        result[side.name] = WORLD.sidecar_text(ROOT, OUT / filename, prior).encode()
        records[name] = {'source': f'docs/art-production/ui-crafted-20261101/sources/{cfg["source"]}',
                         'source_sha256': digest(data), 'source_size': list(image.size),
                         'source_mode': image.mode, 'transform': transform,
                         'path': f'res://art/production/p1/ui_crafted_v01/{filename}',
                         'sha256': digest(encoded), 'output_mode': output.mode,
                         'alpha_bounds_xyxy': list(output.getchannel('A').getbbox()) if output.mode == 'RGBA' else None}
    manifest = {'schema_version': 1, 'recipe': 'docs/art-production/ui-crafted-20261101/recipe.json',
                'recipe_sha256': digest(RECIPE.read_bytes()), 'sampling': 'nearest-neighbor', 'assets': records}
    result['manifest.json'] = (json.dumps(manifest, indent=2, sort_keys=True) + '\n').encode()
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--verify', action='store_true')
    args = parser.parse_args()
    outputs = compile_outputs()
    if args.verify:
        mismatches = [name for name, data in outputs.items() if not (OUT / name).is_file() or (OUT / name).read_bytes() != data]
        if mismatches:
            raise ValueError('missing or different outputs: ' + ', '.join(mismatches))
        print('PASS ui_crafted_v01: sources, pixels, sidecars and manifest match')
    else:
        OUT.mkdir(parents=True, exist_ok=True)
        for name, data in outputs.items():
            (OUT / name).write_bytes(data)
        print('built ui_crafted_v01:', ', '.join(outputs))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
