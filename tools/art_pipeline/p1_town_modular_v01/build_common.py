#!/usr/bin/env python3
"""Deterministic common-layer pack for the Loadout building sample (checkpoint 1).

Packs the retained raw base candidate 01 into the 256x224 production `common`
layer with one locked uniform nearest-neighbour transform and binary alpha.
The recipe constants below are the single source of truth; the same input file
always yields byte-identical output (integer arithmetic only, no resampling
library calls, no timestamps in the manifest).

Transform (chosen from measured feature geometry, see
docs/art-production/p1-town-modular-v01/PROCESSING.md):
- uniform scale s = 155/24 (~6.4583) source px per destination px;
- source window origin (227, 715) -> destination origin (59, 128);
- destination window 138 x 50 px covers the whole alpha>=128 source extent;
- for destination pixel (dx, dy):
    src_x = 227 + ((2*(dx - 59) + 1) * 155) // 48
    src_y = 715 + ((2*(dy - 128) + 1) * 155) // 48
- alpha >= 128 keeps the source RGB with alpha forced to 255; anything else
  becomes fully transparent black. No palette quantization, no per-pixel color
  edits, no nonuniform stretching.

Invariants asserted at build time (sample spec alignment section):
- canvas exactly 256x224, every texture pixel binary alpha (0 or 255);
- no opaque content above y=128, below y=177, or inside the 8 px edge margin.

Run from the repository root in the approved portable environment:

    source /data/claude/workspace/.tools/make-it-big/portable-cpu/env.sh
    source scripts/project_env.sh
    python3 -I tools/art_pipeline/p1_town_modular_v01/build_common.py
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

from PIL import Image

REPO_ROOT = Path(__file__).resolve().parents[3]

RECIPE = {
    "source": "docs/art-production/p1-town-modular-v01/sources/loadout_common_candidate_01.png",
    "source_sha256": "2e7dd83a010e0be94ec17b504de075b69c71ca13050c0b14ae2ad2a504ed758a",
    "canvas": [256, 224],
    "scale": [155, 24],          # source px per destination px, exact rational
    "src_origin": [227, 715],    # source pixel coordinate at the window origin
    "dst_origin": [59, 128],     # destination window origin on the canvas
    "dst_size": [138, 50],       # destination window size
    "alpha_threshold": 128,
    "margin": 8,                 # sample spec: nothing inside the 8 px margin
    "max_lip_top": 128,          # common never has content above y=128
    "max_feet_row": 177,         # feet line is y=178; last content row is 177
}

ALLOWED_ARTIFACTS = {
    "loadout_common.png",
    "manifest.json",
    "loadout_upper_full.png",      # written by build_upper.py (checkpoint 2);
    "loadout_upper_revealed.png",  # the art directory is shared, so both
    "loadout_shadow.png",          # builders tolerate each other's outputs
    "manifest_upper.json",
}


class BuildError(ValueError):
    """Raised when the source, transform, or output contract is violated."""


def source_index(dst: int, dst_origin: int, src_origin: int, num: int, den: int) -> int:
    """Exact integer nearest-neighbour sampling index for a destination pixel."""
    return src_origin + ((2 * (dst - dst_origin) + 1) * num) // (2 * den)


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


def load_source(recipe: dict) -> Image.Image:
    path = REPO_ROOT / recipe["source"]
    if not path.is_file():
        raise BuildError(f"source PNG does not exist: {path}")
    actual = sha256_file(path)
    if actual != recipe["source_sha256"]:
        raise BuildError(
            f"source hash mismatch: expected {recipe['source_sha256']}, got {actual}"
        )
    return Image.open(path).convert("RGBA")


def pack_common(source: Image.Image, recipe: dict) -> Image.Image:
    """Apply the locked uniform nearest-neighbour transform and binarize alpha."""
    canvas_w, canvas_h = recipe["canvas"]
    (num, den), (sx0, sy0), (dx0, dy0) = recipe["scale"], recipe["src_origin"], recipe["dst_origin"]
    win_w, win_h = recipe["dst_size"]
    threshold = recipe["alpha_threshold"]
    if source.width <= sx0 or source.height <= sy0:
        raise BuildError("source window origin is outside the source image")
    if dx0 < 0 or dy0 < 0 or dx0 + win_w > canvas_w or dy0 + win_h > canvas_h:
        raise BuildError("destination window does not fit the canvas")

    canvas = Image.new("RGBA", (canvas_w, canvas_h), (0, 0, 0, 0))
    out = canvas.load()
    src = source.load()
    for dy in range(dy0, dy0 + win_h):
        sy = source_index(dy, dy0, sy0, num, den)
        if not 0 <= sy < source.height:
            continue
        for dx in range(dx0, dx0 + win_w):
            sx = source_index(dx, dx0, sx0, num, den)
            if not 0 <= sx < source.width:
                continue
            r, g, b, a = src[sx, sy]
            out[dx, dy] = (r, g, b, 255) if a >= threshold else (0, 0, 0, 0)
    return canvas


def measure(canvas: Image.Image, recipe: dict) -> dict:
    """Mechanical measurements plus the sample-spec invariant assertions."""
    width, height = canvas.size
    if (width, height) != tuple(recipe["canvas"]):
        raise BuildError(f"canvas is {width}x{height}, expected {recipe['canvas']}")
    pixels = canvas.load()
    opaque = 0
    alpha_values: set[int] = set()
    min_x = min_y = None
    max_x = max_y = None
    colors: set[tuple[int, int, int, int]] = set()
    for y in range(height):
        for x in range(width):
            r, g, b, a = pixels[x, y]
            alpha_values.add(a)
            if a == 0:
                continue
            if a != 255:
                raise BuildError(f"non-binary alpha {a} at ({x},{y})")
            opaque += 1
            colors.add((r, g, b, a))
            min_x = x if min_x is None else min(min_x, x)
            max_x = x if max_x is None else max(max_x, x)
            min_y = y if min_y is None else min(min_y, y)
            max_y = y if max_y is None else max(max_y, y)
    if min_x is None:
        raise BuildError("packed layer is empty")
    margin = recipe["margin"]
    if min_x < margin or min_y < margin or max_x >= width - margin or max_y >= height - margin:
        raise BuildError(
            f"content violates the {margin} px margin: bbox ({min_x},{min_y})-({max_x},{max_y})"
        )
    if min_y < recipe["max_lip_top"]:
        raise BuildError(f"content above y={recipe['max_lip_top']}: top row {min_y}")
    if max_y > recipe["max_feet_row"]:
        raise BuildError(f"content below feet row {recipe['max_feet_row']}: bottom row {max_y}")
    return {
        "occupied_bbox": [min_x, min_y, max_x, max_y],
        "opaque_pixels": opaque,
        "transparent_pixels": width * height - opaque,
        "alpha_values": sorted(alpha_values),
        "unique_rgba_colors": len(colors),
    }


def guard_output(output: Path) -> None:
    if not output.exists():
        return
    if not output.is_dir():
        raise BuildError(f"output exists and is not a directory: {output}")
    unexpected = [item.name for item in output.iterdir() if item.name not in ALLOWED_ARTIFACTS]
    if unexpected:
        raise BuildError(
            f"refusing to write into {output}: unexpected entries {sorted(unexpected)}"
        )


def build(output: Path) -> dict:
    recipe = dict(RECIPE)
    source = load_source(recipe)
    canvas = pack_common(source, recipe)
    stats = measure(canvas, recipe)
    guard_output(output)
    output.mkdir(parents=True, exist_ok=True)

    png_path = output / "loadout_common.png"
    canvas.save(png_path, format="PNG", optimize=False)
    artifacts = [
        {
            "kind": "common_layer",
            "part_id": "common",
            "path": display_path(png_path),
            "sha256": sha256_file(png_path),
            "bytes": png_path.stat().st_size,
        }
    ]
    manifest = {
        "schema_version": 1,
        "asset_package": "p1.town_modular_v01",
        "layer": "common",
        "status": "checkpoint_1_unaccepted",
        "recipe": recipe,
        "artifacts": artifacts,
        "measurements": stats,
        "technical_verification": {
            "status": "mechanical_invariants_passed",
            "scope": "deterministic transform, binary alpha, canvas/margin/lip/feet bounds; visual acceptance and runtime integration are pending",
        },
    }
    manifest_path = output / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return manifest


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output", type=Path, default=REPO_ROOT / "art/production/p1/town_modular_v01",
        help="output directory (default: art/production/p1/town_modular_v01)",
    )
    args = parser.parse_args(argv)
    try:
        manifest = build(args.output)
    except (BuildError, OSError, ValueError) as exc:
        print(f"BUILD FAILED: {exc}", file=sys.stderr)
        return 1
    print(json.dumps({"output": manifest["artifacts"][0]["path"], "sha256": manifest["artifacts"][0]["sha256"], "measurements": manifest["measurements"]}, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
