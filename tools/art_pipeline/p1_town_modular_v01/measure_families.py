#!/usr/bin/env python3
"""Read-only color-family segmentation for the p1-town-modular-v01 candidates.

Identifies the real facade wall band, door, windows, lip, and footing edges by
classifying opaque pixels into named color families, so a uniform packing
transform can be chosen from measured geometry instead of the whole-object
bbox. Read-only; writes nothing unless --json-out is given.

Run from the repository root in the approved portable environment:

    python3 -I tools/art_pipeline/p1_town_modular_v01/measure_families.py \
        --source docs/art-production/p1-town-modular-v01/sources/loadout_common_candidate_01.png
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import Counter
from pathlib import Path

from PIL import Image

ALPHA_THRESHOLD = 128
LOGICAL = (256.0, 224.0)
BLOCK = 13  # ~2.5 logical px at 5.2x oversample; 103x91 blocks over the object


def family_of(r: int, g: int, b: int) -> str:
    """Deterministic, named color families. Rules fixed before looking at results."""
    top, low = max(r, g, b), min(r, g, b)
    sat = top - low
    if top >= 170 and sat <= 45:
        return "snow"           # off-white drifts, sills
    if top >= 140 and sat <= 45:
        return "snow_dim"       # shaded snow
    if b >= r + 18 and 55 <= top <= 175:
        return "window"         # cold gray-blue panes
    if r >= b + 25 and top >= 90:
        return "amber_wood"     # warm lit timber / amber seam
    if top <= 82 and sat <= 34:
        return "timber_dark"    # near-black planks, door shadow
    if top <= 120 and sat <= 40:
        return "timber_mid"     # dark brown planks
    if sat <= 42 and top <= 185:
        return "stone"          # gray footing/quoins
    return "other"


FAMILY_ORDER = [
    "snow", "snow_dim", "window", "amber_wood",
    "timber_dark", "timber_mid", "stone", "other",
]
FAMILY_CODE = {name: index for index, name in enumerate(FAMILY_ORDER)}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--json-out", type=Path, default=None)
    args = parser.parse_args(argv)

    image = Image.open(args.source).convert("RGBA")
    width, height = image.size
    pixels = image.load()
    sx, sy = width / LOGICAL[0], height / LOGICAL[1]
    print(f"source {args.source}  {width}x{height}  sx={sx:.4f} sy={sy:.4f}")

    exact: Counter[str] = Counter()
    fam_pixels: Counter[str] = Counter()
    fam_bbox: dict[str, list[int]] = {}
    grid_fam: list[list[int]] = [
        [-1] * ((width + BLOCK - 1) // BLOCK) for _ in range((height + BLOCK - 1) // BLOCK)
    ]
    for y in range(height):
        for x in range(width):
            r, g, b, a = pixels[x, y]
            if a < ALPHA_THRESHOLD:
                continue
            exact["#%02x%02x%02x" % (r, g, b)] += 1
            fam = family_of(r, g, b)
            fam_pixels[fam] += 1
            box = fam_bbox.setdefault(fam, [x, y, x, y])
            box[0], box[1] = min(box[0], x), min(box[1], y)
            box[2], box[3] = max(box[2], x), max(box[3], y)
            by, bx = y // BLOCK, x // BLOCK
            cell = grid_fam[by][bx]
            if cell < 0:
                grid_fam[by][bx] = FAMILY_CODE[fam]

    print("\nexact dominant colors (top 24):")
    for color, count in exact.most_common(24):
        print("  %s  %7d" % (color, count))

    print("\nfamily totals and bboxes (source px / logical):")
    for fam in FAMILY_ORDER:
        if fam not in fam_bbox:
            continue
        x0, y0, x1, y1 = fam_bbox[fam]
        print(
            "  %-11s %7d px   px(%4d,%4d)-(%4d,%4d)  log x %6.2f..%6.2f y %6.2f..%6.2f"
            % (fam, fam_pixels[fam], x0, y0, x1, y1, x0 / sx, x1 / sx, y0 / sy, y1 / sy)
        )

    print(f"\nfamily map ({BLOCK}px blocks, first family to touch the cell wins; '.'=transparent):")
    print("  codes: " + " ".join("%d=%s" % (FAMILY_CODE[f], f) for f in FAMILY_ORDER))
    for by, row in enumerate(grid_fam):
        line = "".join("." if cell < 0 else str(cell) for cell in row)
        if line.strip("."):
            print("  y%4d %s" % (by * BLOCK, line))

    # Row composition inside the object columns: fraction of each family per row,
    # decimated — locates lip / wall / footing transitions.
    print("\nrow family composition (rows with >=200 opaque px, every 5th):")
    rows_any = []
    for y in range(height):
        counts: Counter[str] = Counter()
        for x in range(width):
            r, g, b, a = pixels[x, y]
            if a >= ALPHA_THRESHOLD:
                counts[family_of(r, g, b)] += 1
        total = sum(counts.values())
        if total >= 200:
            rows_any.append((y, counts, total))
    for y, counts, total in rows_any[::5] or []:
        mix = " ".join("%s:%4.1f%%" % (fam[:6], 100.0 * counts[fam] / total) for fam in FAMILY_ORDER if counts[fam])
        print("  y=%4d n=%4d %s" % (y, total, mix))

    if args.json_out:
        args.json_out.parent.mkdir(parents=True, exist_ok=True)
        payload = {
            "source": str(args.source),
            "alpha_threshold": ALPHA_THRESHOLD,
            "families": {
                fam: {"count": fam_pixels[fam], "bbox": fam_bbox[fam]}
                for fam in fam_bbox
            },
            "top_colors": exact.most_common(40),
        }
        args.json_out.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        print(f"\nwrote {args.json_out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
