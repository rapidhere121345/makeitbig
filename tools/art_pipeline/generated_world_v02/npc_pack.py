#!/usr/bin/env python3
"""Pack newly generated 2x2 resident work sheets; no old sprite pixels copied.

One uniform rational scale per resident across all four frames. Alignment uses
the centre of the bottom boot band and the occupied bottom, not moving hands.
The retained old JSON supplies animation IDs/cadences/cells only.
"""
from fractions import Fraction
from pathlib import Path
import hashlib
import json
import math
import sys
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))  # art_pipeline/common.py
import common  # noqa: E402

ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / 'docs/art-production/generated-world-v02/sources'
OUT = ROOT / 'art/production/p1/generated_world_v02/residents'
NAMES = ('mira', 'iven', 'taren', 'leia', 'oren')
THRESHOLD = 240


digest = common.sha256_file


def write_json(path, value):
    common.write_json(path, value, ensure_ascii=True)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    provenance = json.loads((SOURCE.parent / 'SOURCES.json').read_text())
    pins = {row['id']: row['source_sha256'] for row in provenance['records']}
    atlas = json.loads((ROOT / 'art/production/p1/hamlet_life_r13/atlas.json').read_text())
    life = json.loads((ROOT / 'art/production/p1/hamlet_life_r13/life.json').read_text())
    # Whole scenery already includes its fire and fittings; old socket overlays
    # belong to the retired illustration and must not float over the new art.
    life['effects'] = []
    sheet = Image.new('RGBA', (192, 240))
    report = {'generator': 'image_gen.imagegen', 'threshold': THRESHOLD, 'residents': {}}
    for name in NAMES:
        source = SOURCE / ('npc_' + name + '_raw.png')
        assert digest(source) == pins['npc_' + name], (name, 'source hash drift')
        raw = Image.open(source).convert('RGBA')
        frames = []
        for frame in range(4):
            col, row = frame % 2, frame // 2
            cell_rect = (col * raw.width // 2, row * raw.height // 2,
                         (col + 1) * raw.width // 2, (row + 1) * raw.height // 2)
            cell = raw.crop(cell_rect)
            mask = cell.getchannel('A').point(lambda a: 255 if a >= THRESHOLD else 0)
            box = mask.getbbox()
            assert box and box[0] > 0 and box[1] > 0 and box[2] < cell.width and box[3] < cell.height, (name, frame, 'clipped')
            x0, y0, x1, y1 = box
            boot_top = y1 - max(1, (y1 - y0) // 10)
            boot_box = mask.crop((0, boot_top, cell.width, y1)).getbbox()
            assert boot_box
            foot_x = Fraction(boot_box[0] + boot_box[2], 2)
            frames.append((cell, box, foot_x, cell_rect))
        height = max(box[3] - box[1] for _, box, _, _ in frames)
        half_width = max(max(foot - box[0], box[2] - foot) for _, box, foot, _ in frames)
        scale = min(Fraction(28, height), Fraction(14, 1) / half_width)
        hashes, details = [], []
        for frame, (cell, box, foot_x, cell_rect) in enumerate(frames):
            native = Image.new('RGBA', (48, 48))
            inp, out = cell.load(), native.load()
            # Inverse nearest sampling shares exactly the same rational scale
            # on both axes and all frames; source feet map to native (24,44).
            for y in range(48):
                sy = math.floor((Fraction(2 * y + 1, 2) - 44) / scale + box[3])
                if sy < 0 or sy >= cell.height:
                    continue
                for x in range(48):
                    sx = math.floor((Fraction(2 * x + 1, 2) - 24) / scale + foot_x)
                    if 0 <= sx < cell.width:
                        r, g, b, a = inp[sx, sy]
                        if a >= THRESHOLD:
                            out[x, y] = (r, g, b, 255)
            used = native.getchannel('A').getbbox()
            assert used and used[0] >= 1 and used[2] <= 47 and used[3] == 44, (name, frame, used)
            sid = f'{name}.south.work.{frame}'
            dest = atlas['sprites'][sid]['rect']
            sheet.paste(native, tuple(dest[:2]))
            hashes.append(hashlib.sha256(native.tobytes()).hexdigest())
            details.append({'source_cell': list(cell_rect), 'occupied_bbox': list(box),
                            'foot_x': str(foot_x), 'native_bbox': list(used), 'sha256_pixels': hashes[-1]})
        assert len(set(hashes)) == 4, (name, 'work poses must be distinct')
        report['residents'][name] = {'source': str(source.relative_to(ROOT)), 'raw_sha256': digest(source),
                                     'scale': str(scale), 'frames': details}
    sheet.save(OUT / 'residents.png', optimize=False)
    atlas['textures']['residents']['path'] = 'res://art/production/p1/generated_world_v02/residents/residents.png'
    write_json(OUT / 'atlas.json', atlas)
    write_json(OUT / 'life.json', life)
    report['outputs'] = {name: digest(OUT / name) for name in ('residents.png', 'atlas.json', 'life.json')}
    write_json(OUT / 'IMPORT.json', report)
    print('GENERATED_RESIDENTS_PACK_PASS 5 residents, 20 distinct whole frames')


if __name__ == '__main__':
    main()
