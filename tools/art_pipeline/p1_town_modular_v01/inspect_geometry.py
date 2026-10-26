#!/usr/bin/env python3
"""Read-only geometry inspection for the p1-town-modular-v01 base candidates.

Measures the actual feature geometry (alpha row/column profiles, connected
components, quantized color blocks) needed to choose a packing transform.
Every threshold is named explicitly. Writes nothing unless --json-out is
given; never edits a source pixel.

Reproduce from the repository root in the approved portable environment:

    source /data/claude/workspace/.tools/make-it-big/portable-cpu/env.sh
    source scripts/project_env.sh
    python3 -I tools/art_pipeline/p1_town_modular_v01/inspect_geometry.py \
        --source docs/art-production/p1-town-modular-v01/sources/loadout_common_candidate_01.png
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import Counter, deque
from pathlib import Path

from PIL import Image

ALPHA_THRESHOLD = 128  # opaque-content threshold; matches the calibration pipeline
LOGICAL = (256.0, 224.0)  # sample-spec logical canvas
QUANT_SHIFT = 5  # 8 levels/channel color families for the block map
BLOCK = 20  # source px per block-map cell (~1/4 logical px at 5.2x oversample)


def _components(mask: list[list[bool]], width: int, height: int) -> list[dict]:
    """4-connected components of the boolean mask, largest first."""
    seen = bytearray(width * height)
    found: list[dict] = []
    for start in range(width * height):
        if seen[start] or not mask[start // width][start % width]:
            continue
        queue = deque([start])
        seen[start] = 1
        size = 0
        min_x = max_x = start % width
        min_y = max_y = start // width
        while queue:
            offset = queue.popleft()
            x, y = offset % width, offset // width
            size += 1
            min_x, max_x = min(min_x, x), max(max_x, x)
            min_y, max_y = min(min_y, y), max(max_y, y)
            for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                if 0 <= nx < width and 0 <= ny < height:
                    n = ny * width + nx
                    if not seen[n] and mask[ny][nx]:
                        seen[n] = 1
                        queue.append(n)
        found.append({"size": size, "bbox": [min_x, min_y, max_x, max_y]})
    found.sort(key=lambda item: -item["size"])
    return found


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--json-out", type=Path, default=None)
    args = parser.parse_args(argv)

    image = Image.open(args.source).convert("RGBA")
    width, height = image.size
    pixels = image.load()
    sx, sy = width / LOGICAL[0], height / LOGICAL[1]
    print(f"source {args.source}  {width}x{height}  logical scale sx={sx:.4f} sy={sy:.4f}")
    print(f"thresholds: alpha>={ALPHA_THRESHOLD} opaque; color quant >>({QUANT_SHIFT}) ; block {BLOCK}px")

    mask = [[pixels[x, y][3] >= ALPHA_THRESHOLD for x in range(width)] for y in range(height)]

    # Row profile: opaque count + content edges per source row.
    print("\nrow profile (every row with any opaque px, decimated to >=4px logical steps):")
    rows: list[dict] = []
    last_printed = -10
    for y in range(height):
        xs = [x for x in range(width) if mask[y][x]]
        if not xs:
            continue
        entry = {"y": y, "count": len(xs), "min_x": min(xs), "max_x": max(xs)}
        rows.append(entry)
        if y - last_printed >= max(1, int(sy * 4)):
            print(
                "  y=%4d (log %6.2f) count=%4d x %4d..%4d (log %6.2f..%6.2f)"
                % (y, y / sy, entry["count"], entry["min_x"], entry["max_x"], entry["min_x"] / sx, entry["max_x"] / sx)
            )
            last_printed = y

    # Column profile inside the widest band only (rows spanning >= 80% of peak width).
    peak = max(entry["count"] for entry in rows)
    band_rows = [entry["y"] for entry in rows if entry["count"] >= peak * 0.8]
    print(f"\ncolumn profile over wide rows y {min(band_rows)}..{max(band_rows)} (count>={int(peak*0.8)}):")
    cols: list[dict] = []
    last_printed = -10
    for x in range(width):
        n = sum(1 for y in band_rows if mask[y][x])
        if n == 0:
            continue
        entry = {"x": x, "count": n}
        cols.append(entry)
        if x - last_printed >= max(1, int(sx * 8)) and (x < min(cols, key=lambda c: c["x"])["x"] + int(sx * 16) or x > max(cols, key=lambda c: c["x"])["x"] - int(sx * 16)):
            print("  x=%4d (log %6.2f) count=%4d" % (x, x / sx, n))
            last_printed = x
    if cols:
        span = [min(c["x"] for c in cols), max(c["x"] for c in cols)]
        print("  band columns span x %d..%d (log %.2f..%.2f)" % (span[0], span[1], span[0] / sx, span[1] / sx))

    components = _components(mask, width, height)
    print(f"\nconnected components at alpha>={ALPHA_THRESHOLD} (4-conn): {len(components)} total")
    for index, item in enumerate(components[:12]):
        bx0, by0, bx1, by1 = item["bbox"]
        print(
            "  #%02d size=%7d bbox px(%4d,%4d)-(%4d,%4d) log x %.2f..%.2f y %.2f..%.2f"
            % (index, item["size"], bx0, by0, bx1, by1, bx0 / sx, bx1 / sx, by0 / sy, by1 / sy)
        )
    if len(components) > 12:
        rest = sum(item["size"] for item in components[12:])
        print(f"  ... {len(components) - 12} more components, {rest} px total")

    # Dominant quantized color per block over opaque pixels: structure map.
    print(f"\nblock map ({BLOCK}px blocks, dominant quantized color family; '.' = no opaque px):")
    families: Counter[str] = Counter()
    map_lines: list[str] = []
    legend: dict[str, tuple[int, int, int]] = {}
    for by in range(0, height, BLOCK):
        line = []
        for bx in range(0, width, BLOCK):
            counts: Counter[str] = Counter()
            for y in range(by, min(by + BLOCK, height)):
                for x in range(bx, min(bx + BLOCK, width)):
                    r, g, b, a = pixels[x, y]
                    if a >= ALPHA_THRESHOLD:
                        counts["%02x%02x%02x" % (r >> QUANT_SHIFT, g >> QUANT_SHIFT, b >> QUANT_SHIFT)] += 1
            if not counts:
                line.append(".")
                continue
            family = counts.most_common(1)[0][0]
            families[family] += sum(counts.values())
            if family not in legend:
                legend[family] = (
                    int(family[0:2], 16) << QUANT_SHIFT,
                    int(family[2:4], 16) << QUANT_SHIFT,
                    int(family[4:6], 16) << QUANT_SHIFT,
                )
                if len(legend) <= 9:
                    line.append(str(len(legend)))
            else:
                code = list(legend).index(family)
                line.append(str(code) if code <= 9 else "?")
        map_lines.append("".join(line))
        print("  %s" % map_lines[-1])
    print("  legend (first 10 families):")
    for index, (family, rgb) in enumerate(legend.items()):
        if index > 9:
            break
        print("   %d = #%02x%02x%02x-ish  (%d px)" % (index, rgb[0] | (1 << QUANT_SHIFT >> 1), rgb[1] | (1 << QUANT_SHIFT >> 1), rgb[2] | (1 << QUANT_SHIFT >> 1), families[family]))

    if args.json_out:
        payload = {
            "source": str(args.source),
            "alpha_threshold": ALPHA_THRESHOLD,
            "size": [width, height],
            "rows": rows,
            "band_rows": [min(band_rows), max(band_rows)] if band_rows else [],
            "band_columns_span": span if cols else [],
            "components": components,
            "families": {family: families[family] for family in families},
        }
        args.json_out.parent.mkdir(parents=True, exist_ok=True)
        args.json_out.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        print(f"\nwrote {args.json_out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
