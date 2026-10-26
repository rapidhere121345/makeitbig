#!/usr/bin/env python3
"""Checkpoint-1 review and imagegen guide outputs for the Loadout sample.

Produces three FIXED-format outputs from the packed common layer (no source
art is edited; guide geometry is author-defined spec geometry rasterized in
code, never substitute generated artwork):

1. loadout_common_review_4x.png — the common layer enlarged 4x by
   nearest-neighbour and composited over neutral gray, white, and black
   panels, for fringe/contamination review (brief section 6).
2. loadout_roof_guide_256x224.png — the exact 256x224 canvas with the packed
   common layer plus the greybox upper silhouette polygon
   [(40,128),(76,48),(180,48),(216,128)] rasterized with the greybox plank
   banding. This is the calibration guide the parent edits with imagegen to
   produce the roof (upper) layer.
3. loadout_stubs_guide_256x224.png — the same canvas with the common layer
   plus only the low corner stubs (greybox revealed-state geometry +32),
   marking where the roof-off structure sits for the later revealed edit.

Guide geometry (sample spec / greybox +32, tools/modular_town_preview.gd):
- silhouette rows y 48..127, banding: (y-32) % 12 > 1 -> #81584e else #a0775d;
- stub caps  rect (62,114,10,4) and (184,114,10,4), color #a0775d;
- stub posts rect (64,116,6,14) and (186,116,6,14), color #887052.

Run from the repository root in the approved portable environment:

    python3 -I tools/art_pipeline/p1_town_modular_v01/make_guides.py \
        --common art/production/p1/town_modular_v01/loadout_common.png \
        --output build/current/p1-town-modular-v01/checkpoint-1
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

from PIL import Image

REPO_ROOT = Path(__file__).resolve().parents[3]

CANVAS = (256, 224)
REVIEW_SCALE = 4
REVIEW_BACKGROUNDS = ((128, 128, 128, 255), (255, 255, 255, 255), (0, 0, 0, 255))
SILHOUETTE = [(40, 128), (76, 48), (180, 48), (216, 128)]  # greybox + (32, 32)
PLANK_DARK = (129, 88, 78, 255)   # #81584e
PLANK_LIGHT = (160, 119, 93, 255) # #a0775d
STUB_POST = (136, 112, 82, 255)   # #887052
STUB_CAPS = ((62, 114, 10, 4), (184, 114, 10, 4))
STUB_POSTS = ((64, 116, 6, 14), (186, 116, 6, 14))
OUTPUTS = ("loadout_common_review_4x.png", "loadout_roof_guide_256x224.png", "loadout_stubs_guide_256x224.png")


class GuideError(ValueError):
    """Raised when the common layer or output contract is violated."""


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


def load_common(path: Path) -> Image.Image:
    if not path.is_file():
        raise GuideError(f"common layer does not exist: {path} (run build_common.py first)")
    image = Image.open(path).convert("RGBA")
    if image.size != CANVAS:
        raise GuideError(f"common layer is {image.size}, expected {CANVAS}")
    return image


def silhouette_row_span(y: int, polygon: list[tuple[int, int]]) -> tuple[int, int] | None:
    """Even-odd scanline fill at pixel-center height y+0.5. Returns the filled
    x span [first, last] or None. The polygon is x-monotone (trapezoid), so the
    filled span per row is one interval."""
    cy = y + 0.5
    crossings: list[float] = []
    count = len(polygon)
    for index in range(count):
        x0, y0 = polygon[index]
        x1, y1 = polygon[(index + 1) % count]
        if y0 == y1:
            continue  # horizontal edges produce no crossing at interior centers
        low, high = (y0, y1) if y0 < y1 else (y1, y0)
        if not low <= cy < high:
            continue
        t = (cy - y0) / (y1 - y0)
        crossings.append(x0 + t * (x1 - x0))
    if len(crossings) < 2:
        return None
    crossings.sort()
    left = int(crossings[0] + 0.5)   # nearest pixel column to the crossing
    right = int(crossings[-1] + 0.5)
    return (left, right) if right >= left else None


def draw_silhouette(canvas: Image.Image) -> None:
    pixels = canvas.load()
    min_y = min(y for _, y in SILHOUETTE)
    max_y = max(y for _, y in SILHOUETTE)
    for y in range(min_y, max_y + 1):
        span = silhouette_row_span(y, SILHOUETTE)
        if span is None:
            continue
        color = PLANK_DARK if (y - 32) % 12 > 1 else PLANK_LIGHT
        for x in range(span[0], span[1] + 1):
            if 0 <= x < CANVAS[0]:
                pixels[x, y] = color


def draw_stubs(canvas: Image.Image) -> None:
    pixels = canvas.load()
    for x, y, w, h in STUB_CAPS:
        for cy in range(y, y + h):
            for cx in range(x, x + w):
                pixels[cx, cy] = PLANK_LIGHT
    for x, y, w, h in STUB_POSTS:
        for cy in range(y, y + h):
            for cx in range(x, x + w):
                pixels[cx, cy] = STUB_POST


def make_roof_guide(common: Image.Image) -> Image.Image:
    guide = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    draw_silhouette(guide)          # author-defined silhouette underneath
    guide.alpha_composite(common)   # real packed art wins where it has alpha
    return guide


def make_stubs_guide(common: Image.Image) -> Image.Image:
    guide = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    guide.alpha_composite(common)
    draw_stubs(guide)               # stubs on top as distinct guide marks
    return guide


def make_review_sheet(common: Image.Image) -> Image.Image:
    big = common.resize((CANVAS[0] * REVIEW_SCALE, CANVAS[1] * REVIEW_SCALE), Image.Resampling.NEAREST)
    width = big.width * len(REVIEW_BACKGROUNDS)
    sheet = Image.new("RGBA", (width, big.height), REVIEW_BACKGROUNDS[0])
    for index, background in enumerate(REVIEW_BACKGROUNDS):
        panel = Image.new("RGBA", big.size, background)
        panel.alpha_composite(big)
        sheet.paste(panel, (index * big.width, 0))
    return sheet


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--common", type=Path, default=REPO_ROOT / "art/production/p1/town_modular_v01/loadout_common.png")
    parser.add_argument("--output", type=Path, default=REPO_ROOT / "build/current/p1-town-modular-v01/checkpoint-1")
    args = parser.parse_args(argv)
    try:
        common = load_common(args.common)
        outputs = {
            "loadout_common_review_4x.png": make_review_sheet(common),
            "loadout_roof_guide_256x224.png": make_roof_guide(common),
            "loadout_stubs_guide_256x224.png": make_stubs_guide(common),
        }
        args.output.mkdir(parents=True, exist_ok=True)
        report = []
        for name, image in outputs.items():
            path = args.output / name
            image.save(path, format="PNG", optimize=False)
            report.append({"path": display_path(path), "sha256": sha256_file(path), "bytes": path.stat().st_size, "size": list(image.size)})
        print(json.dumps({"common_sha256": sha256_file(args.common), "outputs": report}, sort_keys=True))
    except (GuideError, OSError, ValueError) as exc:
        print(f"GUIDES FAILED: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
