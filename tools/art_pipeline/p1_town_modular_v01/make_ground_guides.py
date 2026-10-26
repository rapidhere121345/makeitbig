#!/usr/bin/env python3
"""Sample-ground guide and packing QC for the modular town preview (no engine).

The preview authors its greybox ground as a 960x640 opaque canvas with a
horizontal stone band Rect(12,352,936,88) and a vertical path Rect(568,12,
64,616) (tools/modular_town_preview.gd `_author_scene`). This tool rasterizes
that same layout contract as a deterministic COLD-SNOW guide image for the
root session's image generation pass:

1. ground_guide_960x640.png — exact preview canvas: complete opaque snowy
   ground, the two path bands at the exact preview rectangles joined smoothly
   (dithered edges that never cut through the crossing), and nothing else.
   The preview's debug grid, envelope/footprint outlines, tree discs and
   fence boxes are NOT drawn; no buildings, trees, fences, logs, lamps,
   characters, baked object shadows, water or cliff holes appear. The ground
   is complete everywhere so the all-uppers-off view never exposes a hole.
2. ground_guide_review_2x.png — 2x nearest-neighbour upscale for review,
   matching the preview's world scale.

Every pixel value comes from a fixed integer hash of its coordinates — no
RNG, no noise seed, byte-identical on every run.

`--check IMAGE` verifies a generated candidate against the packing contract:
exact 960x640, fully opaque, uniformly packed (not one flat fill), and the
two path bands still distinguishable from the snow field. It reports region
means for review; it cannot judge art quality.

Run from the repository root in the approved portable environment:

    python3 -I tools/art_pipeline/p1_town_modular_v01/make_ground_guides.py \
        --output build/current/p1-town-modular-v01/ground-checkpoint-1
    python3 -I tools/art_pipeline/p1_town_modular_v01/make_ground_guides.py \
        --check <generated.png>
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

from PIL import Image

REPO_ROOT = Path(__file__).resolve().parents[3]

CANVAS = (960, 640)
# Exact preview rectangles: Rect2i(x, y, width, height), half-open [x, x+w).
BAND_H = (12, 352, 936, 88)    # horizontal stone band, x 12..948, y 352..440
BAND_V = (568, 12, 64, 616)    # vertical path, x 568..632, y 12..628
EDGE_DITHER = 3                # band-edge blend depth in pixels
# Cold-snow and cold-stone ramps (asset brief: cold snow, dark wood/stone;
# amber light belongs to lamps/windows, not the ground plate).
SNOW_RAMP = ((233, 236, 241, 255), (224, 228, 235, 255), (214, 219, 228, 255), (203, 209, 221, 255))
STONE_RAMP = ((132, 126, 118, 255), (122, 116, 109, 255), (141, 135, 125, 255), (112, 107, 100, 255))
STONE_JOINT = (99, 95, 89, 255)
STONE_CELL = 8  # flagstone cell size for the coarse stone texture
OUTPUTS = ("ground_guide_960x640.png", "ground_guide_review_2x.png")
# QC sample windows (x0, y0, x1, y1), half-open, clear of both bands.
QC_SNOW = ((24, 24, 560, 340), (640, 24, 940, 340), (24, 450, 560, 630), (640, 450, 940, 630))
QC_BAND_H = ((40, 370, 540, 420),)
QC_BAND_V = ((575, 60, 625, 330), (575, 450, 625, 620))
QC_MIN_BAND_SNOW_DISTANCE = 12.0


class GuideError(ValueError):
    """Raised when the output or candidate contract is violated."""


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def display_path(path: Path) -> str:
    """Repo-relative when inside the checkout, absolute otherwise."""
    try:
        return str(path.resolve().relative_to(REPO_ROOT))
    except ValueError:
        return str(path.resolve())


def unit_hash(x: int, y: int, salt: int = 0) -> float:
    """Fixed [0,1) hash of integer coordinates; the only 'noise' source."""
    value = (x * 374761393 + y * 668265263 + salt * 2246822519) & 0xFFFFFFFF
    value = ((value ^ (value >> 13)) * 1274126177) & 0xFFFFFFFF
    return ((value ^ (value >> 16)) & 0xFFFF) / 0x10000


def ramp_pick(ramp: tuple[tuple[int, ...], ...], x: int, y: int, salt: int) -> tuple[int, ...]:
    return ramp[int(unit_hash(x, y, salt) * len(ramp))]


def in_rect(x: int, y: int, rect: tuple[int, int, int, int]) -> bool:
    rx, ry, rw, rh = rect
    return rx <= x < rx + rw and ry <= y < ry + rh


def rect_boundary_distance(x: int, y: int, rect: tuple[int, int, int, int]) -> int:
    """0 inside or on the rect rim, growing outward (Chebyshev)."""
    rx, ry, rw, rh = rect
    dx = max(rx - x, 0, x - (rx + rw - 1))
    dy = max(ry - y, 0, y - (ry + rh - 1))
    return max(dx, dy)


def snow_pixel(x: int, y: int) -> tuple[int, ...]:
    return ramp_pick(SNOW_RAMP, x, y, 1)


def stone_pixel(x: int, y: int) -> tuple[int, ...]:
    cell = ramp_pick(STONE_RAMP, x // STONE_CELL, y // STONE_CELL, 2)
    edge = x % STONE_CELL == 0 or y % STONE_CELL == 0
    if edge and unit_hash(x // STONE_CELL, y // STONE_CELL, 3) < 0.45:
        return STONE_JOINT
    base = list(cell)
    pick = unit_hash(x, y, 4)
    shift = 6 if pick < 0.5 else (-6 if pick > 0.9 else 0)
    return (max(0, min(255, base[0] + shift)), max(0, min(255, base[1] + shift)),
            max(0, min(255, base[2] + shift)), 255)


def make_guide() -> Image.Image:
    """Deterministic layout raster: snow field + two smoothly joined bands.

    Band cores are stone; a dithered EDGE_DITHER-pixel stone skirt fades each
    band into the snow OUTSIDE its rectangle, except that pixels inside either
    rectangle are always stone, so the crossing stays solid (joined smoothly,
    never cut) and the layout rectangles remain the exact contract.
    """
    width, height = CANVAS
    image = Image.new("RGBA", CANVAS, SNOW_RAMP[0])
    pixels = image.load()
    for y in range(height):
        for x in range(width):
            in_h = in_rect(x, y, BAND_H)
            in_v = in_rect(x, y, BAND_V)
            if in_h or in_v:
                pixels[x, y] = stone_pixel(x, y)
                continue
            distance = min(rect_boundary_distance(x, y, BAND_H), rect_boundary_distance(x, y, BAND_V))
            if distance <= EDGE_DITHER and unit_hash(x, y, 5) < (EDGE_DITHER + 1 - distance) / (EDGE_DITHER + 1):
                pixels[x, y] = stone_pixel(x, y)
            else:
                pixels[x, y] = snow_pixel(x, y)
    return image


def region_mean(image: Image.Image, window: tuple[int, int, int, int]) -> list[float]:
    x0, y0, x1, y1 = window
    pixels = image.load()
    count = max(1, (x1 - x0) * (y1 - y0))
    totals = [0, 0, 0]
    for y in range(y0, y1):
        for x in range(x0, x1):
            pixel = pixels[x, y]
            totals[0] += pixel[0]
            totals[1] += pixel[1]
            totals[2] += pixel[2]
    return [round(total / count, 2) for total in totals]


def mean_distance(left: list[float], right: list[float]) -> float:
    return round(sum((a - b) ** 2 for a, b in zip(left, right)) ** 0.5, 2)


def check_candidate(path: Path) -> dict:
    if not path.is_file():
        raise GuideError(f"candidate does not exist: {path}")
    image = Image.open(path).convert("RGBA")
    problems: list[str] = []
    if image.size != CANVAS:
        problems.append(f"size {image.size[0]}x{image.size[1]} != {CANVAS[0]}x{CANVAS[1]}")
    alpha = image.getchannel("A")
    if alpha.getextrema()[0] < 255:
        problems.append("not fully opaque (alpha below 255)")
    colors = image.convert("RGB").getcolors(maxcolors=1 << 24)
    if colors is None or len(colors) < 8:
        problems.append("uniformly flat fill; not a packed ground image")
    snow = [region_mean(image, window) for window in QC_SNOW]
    bands = [region_mean(image, window) for window in QC_BAND_H + QC_BAND_V]
    snow_mean = [sum(channel) / len(snow) for channel in zip(*snow)]
    contrast = [mean_distance(band, snow_mean) for band in bands]
    if bands and min(contrast) < QC_MIN_BAND_SNOW_DISTANCE:
        problems.append(f"path band too close to snow field color (min distance {min(contrast)})")
    return {"candidate": display_path(path), "sha256": sha256_file(path), "size": list(image.size),
            "opaque": alpha.getextrema()[0] >= 255, "distinct_colors": None if colors is None else len(colors),
            "snow_region_means": snow, "band_region_means": bands,
            "band_to_snow_distance": contrast, "problems": problems,
            "verdict": "pass" if not problems else "fail"}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=REPO_ROOT / "build/current/p1-town-modular-v01/ground-checkpoint-1")
    parser.add_argument("--check", type=Path, default=None, help="verify a generated candidate instead of writing guides")
    args = parser.parse_args(argv)
    try:
        if args.check is not None:
            report = check_candidate(args.check)
            print(json.dumps(report, sort_keys=True))
            return 0 if report["verdict"] == "pass" else 1
        guide = make_guide()
        review = guide.resize((CANVAS[0] * 2, CANVAS[1] * 2), Image.Resampling.NEAREST)
        args.output.mkdir(parents=True, exist_ok=True)
        outputs = {"ground_guide_960x640.png": guide, "ground_guide_review_2x.png": review}
        entries = []
        for name, image in outputs.items():
            path = args.output / name
            image.save(path, format="PNG", optimize=False)
            entries.append({"path": display_path(path), "sha256": sha256_file(path),
                            "bytes": path.stat().st_size, "size": list(image.size)})
        bands = {"band_h": list(BAND_H), "band_v": list(BAND_V), "edge_dither_px": EDGE_DITHER}
        print(json.dumps({"outputs": entries, "layout": bands}, sort_keys=True))
    except (GuideError, OSError, ValueError) as exc:
        print(f"GROUND GUIDES FAILED: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
