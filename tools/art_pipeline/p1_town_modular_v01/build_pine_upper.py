#!/usr/bin/env python3
"""Uniform pack proposal for the pine upper candidate (request B, 2026-10-22).

Packs the retained raw full-tree candidate with the SAME whole-canvas
uniform nearest transform as the accepted common (scale exactly 32/3,
origin (0,0) -> (0,0); the raw canvas is again exactly 1024x1536 = 2:3) and
alpha binarization at the named threshold 250 (no alpha-255 exists; the
opaque band is 250..254 and the fringe/halo below is discarded wholesale).

Everything lands under the IGNORED review directory only: no runtime asset
is written or overwritten (the accepted common
`art/production/p1/town_modular_v01/pine_common.png` stays pinned at
7aa70586... and untouched), no repartition is implemented, and no
definition is authored. This is a review proposal under the new policy
direction recorded in PINE_SPEC.md: the canopy becomes the fading layer,
a compact solid base keeps the trunk/roots, and the crown meets the base
around y96..102 - head readability over pixel-exact matting.

Measured calibration (deterministic for the pinned raw):
- full-tree content rows y8..y137, cols x9..x90, 4695 design px;
- crown top y8 (single-px peak at x48), widest rows x10..x88 (inside the
  reserved disc x5..x90 with margin; the crown bottom y96..y98 sits 6..8 px
  BELOW the disc bottom y90 - that is the intended redesign meet band, not
  a spec violation);
- seam: continuous crown mass through y96 (28-px contiguous run), fringe
  fragments y97..y98, clean trunk from y99 (x41..x53, then x40..x54);
- base zone y99..y137: trunk center column 47.0 at y112, 47.5 over the y100..125 band (v01
  measured 48.0), feet y137 (v01 138) - a full repaint, NOT the v01
  pixels: 0 of 1843 v01-opaque pixels are identical, 1683 recolored, 160
  now transparent (same repaint behavior as the Loadout uppers);
- 5 components: 1 main mass + 4 tiny fringe specks (each <= 6 px) at the
  crown's lower edge - measured and reported, not silently removed.

Run from the repository root in the approved portable environment:

    python3 -I tools/art_pipeline/p1_town_modular_v01/build_pine_upper.py
"""

from __future__ import annotations

import hashlib
import importlib.util
import json
import sys
from collections import deque
from pathlib import Path

from PIL import Image, ImageDraw

REPO_ROOT = Path(__file__).resolve().parents[3]
TOOL_DIR = Path(__file__).resolve().parent
REVIEW_DIR = REPO_ROOT / "build/current/p1-town-modular-v01/pine-checkpoint-1"
V01_COMMON = REPO_ROOT / "art/production/p1/town_modular_v01/pine_common.png"

RAW = {
    "path": "docs/art-production/p1-town-modular-v01/sources/pine_upper_candidate_01.png",
    "sha256": "f1bd90ecaca3c23d2c38efc2933d61dbf84fbe9a395fafae2d7bdb7a16199ce9",
}
RECIPE = {
    "stage": "pine_upper_candidate_01_pack_proposal",
    "source_canvas": [1024, 1536],
    "canvas": [96, 144],
    "scale": [32, 3],            # source px per design px, uniform
    "src_origin": [0, 0],
    "dst_origin": [0, 0],
    "alpha_threshold": 250,      # generator opaque band is 250..254; no 255 exists
}
EXPECTED = {  # deterministic measurements of THIS raw under THIS recipe
    "top": 8, "bottom": 137, "left": 9, "right": 90,
    "design_px": 4695, "components": 5,
    "trunk_center_col": 47.0, "trunk_center_row": 112,
    "crown_bottom_run": 96,      # lowest row with a contiguous run >= CROWN_RUN_MIN
}
CROWN_RUN_MIN = 24               # contiguous px; clearly wider than the 13-16 px trunk
BASE_ZONE_TOP = 99               # first clean trunk row; crown-bottom search stays above it
SPECK_MAX_PX = 6                 # each disconnected fringe speck stays tiny
DISC_ALLOW = 3                   # crown silhouette tolerance vs the reserved disc
OUTPUTS = (
    "pine_upper_candidate_packed_96x144.png",
    "pine_upper_candidate_review_1x.png",
    "pine_upper_candidate_review_4x.png",
    "pine_upper_manifest_candidate.json",
)
BACKGROUNDS = ((128, 128, 128, 255), (255, 255, 255, 255), (0, 0, 0, 255))
GUIDE_MARK = (255, 0, 255, 255)     # v01 guide rects (magenta)
CONTENT_MARK = (0, 255, 255, 255)   # measured content bbox (cyan)
CROWN_BOTTOM_MARK = (255, 160, 0, 255)  # measured crown bottom row (orange)


class PackError(ValueError):
    """Raised when the raw or the packed proposal violates the contract."""


def _load(name: str):
    path = TOOL_DIR / f"{name}.py"
    if name in sys.modules:
        return sys.modules[name]
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def display_path(path: Path) -> str:
    try:
        return str(path.resolve().relative_to(REPO_ROOT))
    except ValueError:
        return str(path.resolve())


def load_raw() -> Image.Image:
    path = REPO_ROOT / RAW["path"]
    if not path.is_file():
        raise PackError(f"raw candidate missing: {path}")
    digest = sha256_file(path)
    if digest != RAW["sha256"]:
        raise PackError(f"raw candidate sha256 {digest} != pinned {RAW['sha256']}")
    image = Image.open(path).convert("RGBA")
    if image.size != tuple(RECIPE["source_canvas"]):
        raise PackError(f"raw candidate canvas {image.size} != {RECIPE['source_canvas']}")
    return image


def src_index(dst: int) -> int:
    """Integer-exact nearest source index for one design coordinate."""
    num, den = RECIPE["scale"]
    shifted = dst - RECIPE["dst_origin"][0]
    return RECIPE["src_origin"][0] + ((2 * shifted + 1) * num) // (2 * den)


def pack(raw: Image.Image) -> Image.Image:
    width, height = RECIPE["canvas"]
    source = raw.load()
    packed = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    pixels = packed.load()
    threshold = RECIPE["alpha_threshold"]
    for y in range(height):
        sy = src_index(y)
        for x in range(width):
            sx = src_index(x)
            if not (0 <= sx < raw.width and 0 <= sy < raw.height):
                continue
            r, g, b, a = source[sx, sy]
            if a >= threshold:
                pixels[x, y] = (r, g, b, 255)
    return packed


def _components(grid: dict[tuple[int, int], tuple[int, int, int]]) -> list[int]:
    seen: set[tuple[int, int]] = set()
    sizes: list[int] = []
    for start in grid:
        if start in seen:
            continue
        size = 0
        queue = deque([start])
        seen.add(start)
        while queue:
            x, y = queue.popleft()
            size += 1
            for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                if (nx, ny) in grid and (nx, ny) not in seen:
                    seen.add((nx, ny))
                    queue.append((nx, ny))
        sizes.append(size)
    return sorted(sizes, reverse=True)


def measure(packed: Image.Image) -> dict:
    width, height = packed.size
    pixels = packed.load()
    grid = {(x, y): pixels[x, y][:3] for y in range(height) for x in range(width) if pixels[x, y][3] == 255}
    rows = {y: sorted(x for (x, yy) in grid if yy == y) for y in range(height)}
    rows = {y: xs for y, xs in rows.items() if xs}
    top, bottom = min(rows), max(rows)
    left = min(xs[0] for xs in rows.values())
    right = max(xs[-1] for xs in rows.values())
    design_px = sum(len(xs) for xs in rows.values())

    def longest_run(xs: list[int]) -> int:
        best = run = 1
        for a, b in zip(xs, xs[1:]):
            run = run + 1 if b == a + 1 else 1
            best = max(best, run)
        return best

    crown_bottom_run = max(y for y, xs in rows.items() if y < BASE_ZONE_TOP and longest_run(xs) >= CROWN_RUN_MIN)
    trunk_row = EXPECTED["trunk_center_row"]
    trunk_span = (min(rows[trunk_row]), max(rows[trunk_row]))
    trunk_center = (trunk_span[0] + trunk_span[1]) / 2
    base_cols = {x for (x, y) in grid if 100 <= y <= 125}
    sizes = _components(grid)
    return {
        "top": top, "bottom": bottom, "left": left, "right": right,
        "design_px": design_px, "component_sizes": sizes,
        "components": len(sizes),
        "trunk_center_col": trunk_center, "trunk_row_span": trunk_span,
        "base_zone_cols": [min(base_cols), max(base_cols)],
        "crown_bottom_run": crown_bottom_run,
    }


def v01_overlap(packed: Image.Image) -> dict:
    """Repaint check against the accepted v01 common (read-only)."""
    guides = _load("make_pine_guides")
    digest = sha256_file(V01_COMMON)
    if digest != guides.PINNED_COMMON_SHA256:
        raise PackError(f"v01 common sha256 {digest} != pinned {guides.PINNED_COMMON_SHA256}")
    v01 = Image.open(V01_COMMON).convert("RGBA").load()
    new = packed.load()
    identical = recolored = vanished = 0
    for y in range(packed.height):
        for x in range(packed.width):
            r, g, b, a = v01[x, y]
            if a != 255:
                continue
            n = new[x, y]
            if n[3] != 255:
                vanished += 1
            elif (n[0], n[1], n[2]) == (r, g, b):
                identical += 1
            else:
                recolored += 1
    return {"v01_opaque": identical + recolored + vanished, "identical": identical, "recolored": recolored, "now_transparent": vanished}


def panel(packed: Image.Image, background: tuple[int, int, int, int], scale: int) -> Image.Image:
    big = packed.resize((packed.width * scale, packed.height * scale), Image.Resampling.NEAREST)
    result = Image.new("RGBA", big.size, background)
    result.alpha_composite(big)
    return result


def marked_panel(packed: Image.Image, stats: dict) -> Image.Image:
    guides = _load("make_pine_guides")
    result = panel(packed, BACKGROUNDS[0], 4)
    guides.draw_marks(result)
    draw = ImageDraw.Draw(result)
    scale = 4

    def rect_outline(rect, color):
        x, y, w, h = rect
        draw.rectangle((x * scale, y * scale, (x + w - 1) * scale + 3, (y + h - 1) * scale + 3), outline=color, width=1)

    rect_outline(guides.TRUNK_RECT, GUIDE_MARK)
    rect_outline(guides.ROOT_RECT, GUIDE_MARK)
    for pair in guides.STUB_PAIRS:
        for rect in pair:
            rect_outline(rect, GUIDE_MARK)
    for row, label_y in ((stats["crown_bottom_run"], None),):
        y0 = row * scale
        draw.line((0, y0, result.width, y0), fill=CROWN_BOTTOM_MARK, width=1)
    draw.rectangle(
        (stats["left"] * scale, stats["top"] * scale, stats["right"] * scale + 3, stats["bottom"] * scale + 3),
        outline=CONTENT_MARK, width=1,
    )
    return result


def review_1x(packed: Image.Image) -> Image.Image:
    sheet = Image.new("RGBA", (packed.width * len(BACKGROUNDS), packed.height), BACKGROUNDS[0])
    for index, background in enumerate(BACKGROUNDS):
        sheet.paste(panel(packed, background, 1), (index * packed.width, 0))
    return sheet


def review_4x(packed: Image.Image, stats: dict) -> Image.Image:
    width = packed.width * 4
    height = packed.height * 4
    sheet = Image.new("RGBA", (width * 4, height), BACKGROUNDS[0])
    for index, background in enumerate(BACKGROUNDS):
        sheet.paste(panel(packed, background, 4), (index * width, 0))
    sheet.paste(marked_panel(packed, stats), (3 * width, 0))
    return sheet


def validate(packed: Image.Image, stats: dict) -> list[str]:
    checks: list[str] = []
    if packed.size != tuple(RECIPE["canvas"]):
        raise PackError(f"packed size {packed.size} != {RECIPE['canvas']}")
    if sum(packed.getchannel("A").histogram()[1:255]) != 0:
        raise PackError("packed proposal must have binary alpha")
    for key in ("top", "bottom", "left", "right", "design_px", "components", "crown_bottom_run"):
        if stats[key] != EXPECTED[key]:
            raise PackError(f"measured {key}={stats[key]} != recorded calibration {EXPECTED[key]}")
    if stats["trunk_center_col"] != EXPECTED["trunk_center_col"]:
        raise PackError(f"trunk center column {stats['trunk_center_col']} != {EXPECTED['trunk_center_col']}")
    specks = stats["component_sizes"][1:]
    if any(size > SPECK_MAX_PX for size in specks):
        raise PackError(f"fringe specks too large: {specks}")
    disc = _load("make_pine_guides").CANOPY_DISC
    if stats["left"] < disc["center"][0] - disc["radius"] - DISC_ALLOW or stats["right"] > disc["center"][0] + disc["radius"] + DISC_ALLOW:
        raise PackError("crown silhouette leaves the reserved disc tolerance horizontally")
    checks.append(
        f"PASS full-tree bbox x{stats['left']}..x{stats['right']} y{stats['top']}..y{stats['bottom']}, {stats['design_px']} px, "
        f"main mass {stats['component_sizes'][0]} px + {len(specks)} fringe specks {specks}"
    )
    checks.append(
        f"PASS crown inside disc horizontally (x{stats['left']}..x{stats['right']} vs disc x5..x90 +{DISC_ALLOW}); "
        f"crown bottom y{stats['crown_bottom_run']} sits below the disc bottom y90 - the intended redesign meet band y96..102, recorded not failed"
    )
    checks.append(
        f"PASS base zone y99..y{stats['bottom']}: trunk center col {stats['trunk_center_col']:.1f} at y{EXPECTED['trunk_center_row']} "
        f"(span x{stats['trunk_row_span'][0]}..x{stats['trunk_row_span'][1]}), base cols x{stats['base_zone_cols'][0]}..x{stats['base_zone_cols'][1]}; "
        "full repaint of v01 (not pixel-identical), reported not forced"
    )
    return checks


def main() -> int:
    try:
        raw = load_raw()
        packed = pack(raw)
        stats = measure(packed)
        checks = validate(packed, stats)
        overlap = v01_overlap(packed)
        REVIEW_DIR.mkdir(parents=True, exist_ok=True)
        outputs = {
            "pine_upper_candidate_packed_96x144.png": packed,
            "pine_upper_candidate_review_1x.png": review_1x(packed),
            "pine_upper_candidate_review_4x.png": review_4x(packed, stats),
        }
        report = []
        for name, image in outputs.items():
            path = REVIEW_DIR / name
            image.save(path, format="PNG", optimize=False)
            report.append({"path": display_path(path), "sha256": sha256_file(path), "bytes": path.stat().st_size, "size": list(image.size)})
        manifest = {
            "recipe": RECIPE,
            "raw": dict(RAW, canvas=list(Image.open(REPO_ROOT / RAW["path"]).size)),
            "expected_calibration": EXPECTED,
            "measured": stats,
            "v01_overlap": overlap,
            "policy_note": (
                "review proposal only: canopy becomes the fading layer, compact solid base keeps trunk/roots; "
                "crown meets the base around y96..102; no repartition implemented, no runtime asset touched"
            ),
            "outputs": report,
        }
        manifest_path = REVIEW_DIR / "pine_upper_manifest_candidate.json"
        manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
        print(json.dumps({"v01_overlap": overlap, "outputs": report + [{"path": display_path(manifest_path)}], "checks": checks}, sort_keys=True))
        for line in checks:
            print(line)
        print("PINE UPPER CANDIDATE PACK OK (review proposal only; no runtime asset written, v01 common untouched)")
    except (PackError, OSError, ValueError) as exc:
        print(f"PINE UPPER PACK FAILED: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
