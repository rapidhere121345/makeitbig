#!/usr/bin/env python3
"""Offline QA of actual atlas pixels; these are NOT Godot screenshots.

Only technical composition, nearest-neighbor scaling and grayscale conversion.
No new sprites, painting, generated substitutes or gameplay changes.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image, ImageDraw


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def tower_upper_overlaps(atlas: dict, hero_feet: tuple[int, int], tower_feet: tuple[int, int]) -> bool:
    """Same full-cell, half-open overlap contract as the Godot preview.

    This tests canvas bounds, not collision or opaque-pixel hit testing.
    """
    hero = atlas['sprites']['ranger.south.idle']
    upper = atlas['sprites']['tower.upper']
    first, last = upper['keep_rows']
    hx, hy = (hero_feet[i] - hero['anchor'][i] for i in range(2))
    tx, ty = (tower_feet[i] - upper['anchor'][i] for i in range(2))
    return (hero_feet[1] < tower_feet[1]
            and hx < tx + upper['rect'][2] and hx + hero['rect'][2] > tx
            and hy < ty + last and hy + hero['rect'][3] > ty + first)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--atlas-dir', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    atlas_dir = args.atlas_dir.resolve()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    atlas = json.loads((atlas_dir / 'atlas.json').read_text())
    textures = {key: Image.open(atlas_dir / (key + '.png')).convert('RGBA') for key in atlas['textures']}
    report = {'kind': 'offline_atlas_composition_not_godot_screenshot', 'native_view': [640, 360],
              'world_size': [1024, 640], 'hero_lock': 'integer foot point at viewport center',
              'visual_approval': False, 'sprites': {}, 'artifacts': []}

    def sprite(key: str) -> Image.Image:
        meta = atlas['sprites'][key]
        x, y, w, h = meta['rect']
        return textures[meta['texture']].crop((x, y, x+w, y+h))

    def save(im: Image.Image, name: str) -> None:
        path = output / name
        im.save(path)
        report['artifacts'].append({'file': name, 'size': list(im.size), 'sha256': sha(path)})

    def gray(im: Image.Image) -> Image.Image:
        return im.convert('L').convert('RGB')

    def put(canvas: Image.Image, key: str, feet: tuple[int, int], alpha: int = 255) -> None:
        im = sprite(key)
        if alpha != 255:
            im.putalpha(im.getchannel('A').point(lambda v: v * alpha // 255))
        ax, ay = atlas['sprites'][key]['anchor']
        canvas.alpha_composite(im, (feet[0] - ax, feet[1] - ay))

    def scene(hero_world: tuple[int, int], phase: int = 1, enemy_state: str = 'idle') -> Image.Image:
        offset = (hero_world[0]-320, hero_world[1]-180)
        canvas = Image.new('RGBA', (640, 360), '#2D3943')
        ground = sprite('terrain.ground')
        for y in range(-(offset[1] % 64), 360, 64):
            for x in range(-(offset[0] % 64), 640, 64):
                canvas.alpha_composite(ground, (x, y))
        def screen(pos: tuple[int, int]) -> tuple[int, int]:
            return pos[0]-offset[0], pos[1]-offset[1]
        terrain = {
            'terrain.snow': [(80, 110), (390, 520), (720, 160), (910, 500)],
            'terrain.rubble': [(180, 310), (580, 500), (810, 340)],
            'terrain.wall': [(120, 430), (640, 250), (870, 590)],
            'terrain.fence': [(300, 170), (500, 570), (940, 230)],
        }
        actors = [('ranger.south.idle', hero_world),
                  ('enemy.melee.'+enemy_state, (260, 250)),
                  ('enemy.charger.'+enemy_state, (220, 500)),
                  ('enemy.ranged.'+enemy_state, (500, 235))]
        for key, positions in terrain.items():
            for pos in positions:
                if key in ('terrain.snow', 'terrain.rubble'):
                    put(canvas, key, screen(pos))
                else:
                    actors.append((key, pos))
        actors.extend([('assembled_boss', (470, 390)), ('assembled_tower', (580, 285))])
        for key, pos in sorted(actors, key=lambda a: a[1][1]):
            p = screen(pos)
            if key == 'assembled_boss':
                put(canvas, f'boss.core_phase{phase}', (p[0], p[1]-15))
                put(canvas, f'boss.body_phase{phase}', p)
                put(canvas, 'boss.hand_left', (p[0]-53, p[1]-8))
                put(canvas, 'boss.hand_right', (p[0]+53, p[1]-8))
            elif key == 'assembled_tower':
                put(canvas, 'tower.base', p)
                overlaps = tower_upper_overlaps(atlas, hero_world, pos)
                put(canvas, 'tower.upper', p, 133 if overlaps else 255)
            else:
                put(canvas, key, p)
        return canvas.convert('RGB')

    for key in atlas['sprites']:
        im = sprite(key)
        colors = {rgba for rgba in im.getdata() if rgba[3]}
        max_colors = 12 if key.startswith(('ranger.', 'boss.')) else 8
        if len(colors) > max_colors:
            raise ValueError(f'{key}: {len(colors)} colors exceeds {max_colors}')
        report['sprites'][key] = {'cell': list(im.size), 'alpha_bbox': im.getchannel('A').getbbox(),
                                  'opaque_colors': len(colors), 'budget': max_colors}
    native = scene((280, 368))
    save(native, 'world_native_640x360.png')
    save(native.resize((1280, 720), Image.Resampling.NEAREST), 'world_display_1280x720.png')
    save(native.resize((320, 180), Image.Resampling.NEAREST), 'world_display_25pct.png')
    save(gray(native), 'world_grayscale_640x360.png')
    sheet = Image.open(atlas_dir / 'contact_sheet.png').convert('RGB')
    save(sheet.resize((sheet.width*4, sheet.height*4), Image.Resampling.NEAREST), 'atlas_review_4x.png')
    save(sheet, 'atlas_review_4x_at_25pct.png')
    for family in ('ranger', 'enemies', 'tower'):
        source = textures[family]
        backdrop = Image.new('RGBA', source.size, '#2D3943')
        backdrop.alpha_composite(source)
        save(backdrop.resize((source.width*4, source.height*4), Image.Resampling.NEAREST), family+'_4x.png')
    occlusion = scene((580, 205))
    save(occlusion.resize((1280, 720), Image.Resampling.NEAREST), 'tower_occlusion_offline.png')
    # Actual frames plus text added outside cells, no raster-painted game objects.
    animation = []
    for pose in ('idle', 'walk_a', 'walk_b', 'shoot'):
        im = Image.new('RGBA', (360, 90), '#2D3943')
        draw = ImageDraw.Draw(im)
        draw.text((8, 4), 'OFFLINE POSE CHECK: '+pose, fill='#D3CBB5')
        for i, direction in enumerate(('south', 'north', 'west', 'east')):
            put(im, f'ranger.{direction}.{pose}', (44+i*88, 70))
        animation.append(im.convert('RGB').resize((1080, 270), Image.Resampling.NEAREST))
    animation[0].save(output / 'ranger_pose_check.gif', save_all=True, append_images=animation[1:],
                      duration=[400, 200, 200, 500], loop=0)
    report['artifacts'].append({'file': 'ranger_pose_check.gif', 'size': [1080, 270],
                              'sha256': sha(output / 'ranger_pose_check.gif'),
                              'scope': 'pose review timing, NOT runtime animation timing'})
    report['atlas_sha256'] = sha(atlas_dir / 'atlas.json')
    (output / 'QA_REPORT.json').write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n')
    print(json.dumps({'sprite_count': len(report['sprites']), 'qa_images': len(report['artifacts']),
                      'kind': report['kind']}))


if __name__ == '__main__':
    main()
