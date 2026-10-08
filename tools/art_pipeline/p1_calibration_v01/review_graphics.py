#!/usr/bin/env python3
"""Make labeled 25% contact sheets from real Godot captures, preserving originals."""
import argparse
import json
import math
from pathlib import Path
from PIL import Image, ImageDraw


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--directory', type=Path, required=True)
args = parser.parse_args()
data = json.loads((args.directory / 'REPORT.json').read_text())
canvas = Image.new('RGB', (1280, math.ceil(len(data['captures'])/4)*204), '#111820')
draw = ImageDraw.Draw(canvas)
for index, capture in enumerate(data['captures']):
    image = Image.open(args.directory / capture['file']).convert('RGB')
    x, y, w, h = capture['world_display_rect']
    crop = image.crop((x,y,x+w,y+h))
    column, row = index % 4, index // 4
    canvas.paste(crop.resize((320,180),Image.Resampling.NEAREST),(column*320,row*204+24))
    draw.text((column*320+5,row*204+5),capture['file'],fill='#D3CBB5')
canvas.save(args.directory / 'review_25pct.png')
print(f"reviewed capture count: {len(data['captures'])}")
