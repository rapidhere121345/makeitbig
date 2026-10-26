#!/usr/bin/env python3
"""Read-only feature-cluster measurement for the p1-town-modular-v01 candidates.

Measures the exact wall band (rows/columns dominated by timber), then finds
connected clusters of door-dark, window-blue, and amber-warm pixels inside it,
so the packing transform and the decorative-geometry deviation report are
grounded in measured features rather than the whole-object bbox. Read-only.

Run from the repository root in the approved portable environment:

    python3 -I tools/art_pipeline/p1_town_modular_v01/measure_features.py \
        --source docs/art-production/p1-town-modular-v01/sources/loadout_common_candidate_01.png
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import deque
from pathlib import Path

from PIL import Image

ALPHA_THRESHOLD = 128
LOGICAL = (256.0, 224.0)
TIMBER_ROW_FRACTION = 0.60   # row counts as wall when timber >= this share of opaque
WALL_COLUMN_FRACTION = 0.50  # column belongs to the wall when covered over wall rows
DOOR_MAX_CHANNEL = 10        # near-pure-black: all channels <= this
WINDOW_BLUE_MARGIN = 14      # b >= r + margin and 50 <= max <= 185
AMBER_MARGIN = 22            # r >= b + margin and max >= 80
MIN_CLUSTER = 120            # ignore specks below this many source px


def family_of(r: int, g: int, b: int) -> str:
    top = max(r, g, b)
    if r <= DOOR_MAX_CHANNEL and g <= DOOR_MAX_CHANNEL and b <= DOOR_MAX_CHANNEL:
        return "door_black"
    if b >= r + WINDOW_BLUE_MARGIN and 50 <= top <= 185:
        return "window_blue"
    if r >= b + AMBER_MARGIN and top >= 80:
        return "amber_warm"
    if top >= 170 and top - min(r, g, b) <= 45:
        return "snow_bright"  # lip/drift rows are not wall rows
    return None


def clusters(grid: list[list[str | None]], width: int, height: int, want: str) -> list[dict]:
    seen = bytearray(width * height)
    found: list[dict] = []
    for start in range(width * height):
        if seen[start]:
            continue
        y0, x0 = start // width, start % width
        if grid[y0][x0] != want:
            continue
        queue = deque([(x0, y0)])
        seen[start] = 1
        size = 0
        min_x = max_x = x0
        min_y = max_y = y0
        while queue:
            x, y = queue.popleft()
            size += 1
            min_x, max_x = min(min_x, x), max(max_x, x)
            min_y, max_y = min(min_y, y), max(max_y, y)
            for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                if 0 <= nx < width and 0 <= ny < height and not seen[ny * width + nx] and grid[ny][nx] == want:
                    seen[ny * width + nx] = 1
                    queue.append((nx, ny))
        found.append({"size": size, "bbox": [min_x, min_y, max_x, max_y]})
    found.sort(key=lambda item: -item["size"])
    return [item for item in found if item["size"] >= MIN_CLUSTER]


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

    grid: list[list[str | None]] = [[None] * width for _ in range(height)]
    opaque = [[False] * width for _ in range(height)]
    for y in range(height):
        for x in range(width):
            r, g, b, a = pixels[x, y]
            if a >= ALPHA_THRESHOLD:
                opaque[y][x] = True
                grid[y][x] = family_of(r, g, b)

    # Wall band: rows whose timber share (opaque minus door/window/amber/snow
    # families) crosses TIMBER_ROW_FRACTION. Dark lintel/sill rows and the
    # footing band dip below the fraction, so every contiguous qualifying run
    # is reported; the authoritative band structure is the row-family
    # composition from measure_families.py, not a single run here.
    row_wall: list[float] = []
    for y in range(height):
        n_op = sum(1 for x in range(width) if opaque[y][x])
        n_special = sum(1 for x in range(width) if grid[y][x] is not None)
        row_wall.append(((n_op - n_special) / n_op) if n_op else 0.0)
    wall_rows = [y for y in range(height) if row_wall[y] >= TIMBER_ROW_FRACTION]
    runs: list[list[int]] = []
    for y in wall_rows:
        if runs and y - runs[-1][-1] <= 1:
            runs[-1].append(y)
        else:
            runs.append([y])
    kept_runs = [run for run in runs if len(run) >= 20]
    print(f"\ntimber runs (share>={int(TIMBER_ROW_FRACTION*100)}%, runs >= 20 px): "
          + "; ".join("y %d..%d (%d px, %.2f logical)" % (run[0], run[-1], len(run), len(run) / sy) for run in kept_runs))
    if not kept_runs:
        raise SystemExit("no qualifying timber runs; check thresholds")
    top, bottom = kept_runs[0][0], kept_runs[-1][-1]

    wall_columns = []
    for x in range(width):
        covered = sum(1 for y in range(top, bottom + 1) if opaque[y][x])
        if covered >= (bottom - top + 1) * WALL_COLUMN_FRACTION:
            wall_columns.append(x)
    left, right = min(wall_columns), max(wall_columns)
    print(f"wall columns (>={int(WALL_COLUMN_FRACTION*100)}% of wall rows opaque): x {left}..{right} "
          f"({right - left + 1} px, {(right - left + 1) / sx:.2f} logical)")

    # Base band below the wall: composition and extent, to classify footing/snow.
    base_rows = [y for y in range(bottom + 1, height) if any(opaque[y])]
    if base_rows:
        bl = min(x for y in base_rows for x in range(width) if opaque[y][x])
        br = max(x for y in base_rows for x in range(width) if opaque[y][x])
        print(f"base band rows: y {min(base_rows)}..{max(base_rows)} "
              f"({(max(base_rows) - min(base_rows) + 1) / sy:.2f} logical) extent x {bl}..{br} "
              f"(log {bl / sx:.2f}..{br / sx:.2f})")
    lip_rows = [y for y in range(height) if y < top and any(opaque[y])]
    if lip_rows:
        ll = min(x for y in lip_rows for x in range(width) if opaque[y][x])
        lr = max(x for y in lip_rows for x in range(width) if opaque[y][x])
        print(f"lip rows above wall: y {min(lip_rows)}..{max(lip_rows)} "
              f"({(max(lip_rows) - min(lip_rows) + 1) / sy:.2f} logical) extent x {ll}..{lr} "
              f"(log {ll / sx:.2f}..{lr / sx:.2f})")

    print(f"\nclusters (4-conn, >= {MIN_CLUSTER} px):")
    report: dict[str, list] = {}
    for want in ("door_black", "window_blue", "amber_warm"):
        found = clusters(grid, width, height, want)
        report[want] = found
        print(f"  {want}: {len(found)} kept")
        for item in found[:8]:
            x0, y0, x1, y1 = item["bbox"]
            print(
                "    size=%6d px(%4d,%4d)-(%4d,%4d)  log x %6.2f..%6.2f y %6.2f..%6.2f"
                % (item["size"], x0, y0, x1, y1, x0 / sx, x1 / sx, y0 / sy, y1 / sy)
            )

    if args.json_out:
        args.json_out.parent.mkdir(parents=True, exist_ok=True)
        payload = {
            "source": str(args.source),
            "alpha_threshold": ALPHA_THRESHOLD,
            "wall_band_rows": [top, bottom],
            "wall_columns": [left, right],
            "base_band_rows": [min(base_rows), max(base_rows)] if base_rows else [],
            "lip_rows": [min(lip_rows), max(lip_rows)] if lip_rows else [],
            "clusters": report,
        }
        args.json_out.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        print(f"\nwrote {args.json_out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
