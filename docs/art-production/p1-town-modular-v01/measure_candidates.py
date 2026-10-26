#!/usr/bin/env python3
"""Read-only alpha/geometry measurements for the p1-town-modular-v01 candidates.

Reproduce with the approved portable environment:

    source /data/claude/workspace/.tools/make-it-big/portable-cpu/env.sh
    source scripts/project_env.sh
    python3 -I docs/art-production/p1-town-modular-v01/measure_candidates.py

Run from the repository root. Every threshold is named explicitly; the script
writes nothing and edits no pixels.
"""
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
FILES = [
    str(HERE / "sources/loadout_common_candidate_01.png"),
    str(HERE / "sources/loadout_common_candidate_02.png"),
]
LOGICAL = (256.0, 224.0)
TARGET = (128.0, 48.0)  # spec facade rectangle, logical px


def bucket(hist, lo, hi):
    return sum(n for a, n in hist.items() if lo <= a <= hi)


for rel in FILES:
    im = Image.open(rel).convert("RGBA")
    width, height = im.size
    px = im.load()
    sx = width / LOGICAL[0]
    sy = height / LOGICAL[1]
    hist = {}
    xs128 = []
    ys128 = []
    xspos = []
    ypos = []
    for y in range(height):
        for x in range(width):
            alpha = px[x, y][3]
            hist[alpha] = hist.get(alpha, 0) + 1
            if alpha >= 128:
                xs128.append(x)
                ys128.append(y)
            if alpha > 0:
                xspos.append(x)
                ypos.append(y)
    total = width * height
    print("== %s  %dx%d  logical scale sx=%.4f sy=%.4f"
          % (Path(rel).relative_to(HERE), width, height, sx, sy))
    for name, lo, hi in [("a=0", 0, 0), ("1..127", 1, 127),
                         ("128..249", 128, 249), ("250..254", 250, 254),
                         ("a=255", 255, 255)]:
        count = bucket(hist, lo, hi)
        print("  alpha %-8s %8d  %9.4f%%" % (name, count, 100.0 * count / total))
    bx0, by0, bx1, by1 = min(xs128), min(ys128), max(xs128), max(ys128)
    lw = (bx1 - bx0 + 1) / sx
    lh = (by1 - by0 + 1) / sy
    print("  bbox a>=128 px=(%d,%d,%d,%d) logical x %.2f..%.2f y %.2f..%.2f (w %.2f h %.2f)"
          % (bx0, by0, bx1, by1, bx0 / sx, bx1 / sx, by0 / sy, by1 / sy, lw, lh))
    print("  bbox a>0    px=(%d,%d,%d,%d)"
          % (min(xspos), min(ypos), max(xspos), max(ypos)))
    rw = TARGET[0] / lw
    rh = TARGET[1] / lh
    print("  uniform-fit ratios from a>=128: width %.4f height %.4f "
          "relative spread %.1f%% (|h-w|/w)"
          % (rw, rh, abs(rh - rw) / rw * 100.0))
