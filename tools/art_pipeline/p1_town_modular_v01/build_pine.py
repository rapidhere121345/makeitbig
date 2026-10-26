#!/usr/bin/env python3
"""Deterministic pack of the pine common layer (candidate 01, ACCEPTED).

Reads the retained raw pine common candidate and packs the parent-accepted
common layer (accepted as drawn 2026-10-22, scoped to the common layer) to
the runtime art path `art/production/p1/town_modular_v01/pine_common.png`,
pinning the accepted SHA-256. Review sheets and the manifest stay under the
ignored review directory. No .tres is authored here. The raw is never
edited; binarization happens on the packed copy only.

Recipe (recorded calibration, measured on the pinned raw):
- Source space: the whole 1024x1536 generator canvas maps to the 96x144
  design canvas with ONE uniform nearest transform, scale exactly 32/3
  source px per design px (the generator kept the canvas grid exactly this
  time: 1024/96 == 1536/144 == 32/3; no content-anchor refit is needed and
  none is applied), window origin (0,0) -> (0,0).
- Binarization: the raw contains NO alpha-255 pixel; its opaque band is
  250..254. alpha >= 250 becomes 255 (RGB kept); everything below is the
  fringe/halo the parent saw and is discarded wholesale rather than kept as
  contamination (a 200..249 edge ring ~0.4 design px thick plus a broad
  <=31 wash spanning most of the canvas).

Measured result vs the guide contract (deviations reported, never forced):
- content rows y47..y138, cols x27..x68, 1843 design px, ONE component;
- trunk top y47 vs spec y56 (+9 px upward; fully behind the reserved
  canopy disc, which covers through y90);
- feet bottom y138 vs spec y140 (2 px high; root contact ~y130..138);
- widest stub rows 1 px wider on the left (x27/x33 vs x28/x34);
- trunk center column 48 at y80/y120 (anchor contract (48,128) holds);
- stub bands merge with the trunk into continuous unions matching the
  guide unions exactly (upper x33..62 ~ spec x34..62, lower x27..68 ~ spec
  x28..68).

Run from the repository root in the approved portable environment:

    python3 -I tools/art_pipeline/p1_town_modular_v01/build_pine.py
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
ART_PATH = REPO_ROOT / "art/production/p1/town_modular_v01/pine_common.png"
# The parent-accepted pack (2026-10-22, "accepted as drawn"); every build
# must reproduce exactly these bytes or it fails loudly.
PINNED_ART_SHA256 = "7aa70586ccd908d50ce97451534ff8f1f37c433ba3b9e72e13a7c2f8f50333a2"

RAW = {
    "path": "docs/art-production/p1-town-modular-v01/sources/pine_common_candidate_01.png",
    "sha256": "b23b9675357c8e305d8a7e7ad4fb00885c432f0f53cf21bdf9dffa3856dde5fb",
}
RECIPE = {
    "stage": "pine_common_candidate_01_pack",
    "source_canvas": [1024, 1536],
    "canvas": [96, 144],
    "scale": [32, 3],            # source px per design px, uniform
    "src_origin": [0, 0],
    "dst_origin": [0, 0],
    "alpha_threshold": 250,      # generator opaque band is 250..254; no 255 exists
}
EXPECTED = {  # deterministic measurements of THIS raw under THIS recipe
    "top": 47, "bottom": 138, "left": 27, "right": 68,
    "design_px": 1843, "components": 1,
    "trunk_center_col": 48, "trunk_center_row": 80,
    "root_widening_ratio_min": 1.8,
}
OUTPUTS = (
    "pine_common_candidate_packed_96x144.png",
    "pine_common_candidate_review_1x.png",
    "pine_common_candidate_review_4x.png",
    "pine_manifest_candidate.json",
)
BACKGROUNDS = ((128, 128, 128, 255), (255, 255, 255, 255), (0, 0, 0, 255))
GUIDE_MARK = (255, 0, 255, 255)     # guide rects (magenta)
DISC_MARK = (255, 255, 255, 255)    # reserved canopy disc (white)
CONTENT_MARK = (0, 255, 255, 255)   # measured content bbox (cyan)


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


def measure(packed: Image.Image) -> dict:
    width, height = packed.size
    pixels = packed.load()
    grid = [[pixels[x, y][3] == 255 for x in range(width)] for y in range(height)]
    rows = {y: [x for x in range(width) if grid[y][x]] for y in range(height)}
    rows = {y: xs for y, xs in rows.items() if xs}
    top, bottom = min(rows), max(rows)
    left = min(xs[0] for xs in rows.values())
    right = max(xs[-1] for xs in rows.values())
    design_px = sum(len(xs) for xs in rows.values())
    seen = [[False] * width for _ in range(height)]
    components = 0
    for y0 in range(height):
        for x0 in range(width):
            if grid[y0][x0] and not seen[y0][x0]:
                components += 1
                queue = deque([(x0, y0)])
                seen[y0][x0] = True
                while queue:
                    x, y = queue.popleft()
                    for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                        if 0 <= nx < width and 0 <= ny < height and grid[ny][nx] and not seen[ny][nx]:
                            seen[ny][nx] = True
                            queue.append((nx, ny))
    trunk_row = EXPECTED["trunk_center_row"]
    trunk_span = (min(rows[trunk_row]), max(rows[trunk_row])) if trunk_row in rows else None
    trunk_center = (trunk_span[0] + trunk_span[1]) / 2 if trunk_span else None
    def band_cols(y0: int, y1: int) -> set[int]:
        return {x for y in range(y0, y1 + 1) if y in rows for x in rows[y]}
    trunk_cols = band_cols(100, 125)
    root_cols = band_cols(131, bottom)
    return {
        "top": top, "bottom": bottom, "left": left, "right": right,
        "design_px": design_px, "components": components,
        "trunk_center_col": trunk_center, "trunk_row_span": trunk_span,
        "trunk_band_cols": len(trunk_cols), "root_band_cols": len(root_cols),
    }


def panel(packed: Image.Image, background: tuple[int, int, int, int], scale: int) -> Image.Image:
    big = packed.resize((packed.width * scale, packed.height * scale), Image.Resampling.NEAREST)
    result = Image.new("RGBA", big.size, background)
    result.alpha_composite(big)
    return result


def marked_panel(packed: Image.Image) -> Image.Image:
    guides = _load("make_pine_guides")
    result = panel(packed, BACKGROUNDS[0], 4)
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
    cx, cy = guides.CANOPY_DISC["center"]
    r = guides.CANOPY_DISC["radius"] * scale
    draw.ellipse((cx * scale - r, cy * scale - r, cx * scale + r, cy * scale + r), outline=DISC_MARK, width=1)
    pixels = packed.load()
    left = min(x for y in range(packed.height) for x in range(packed.width) if pixels[x, y][3] == 255)
    right = max(x for y in range(packed.height) for x in range(packed.width) if pixels[x, y][3] == 255)
    top = min(y for y in range(packed.height) for x in range(packed.width) if pixels[x, y][3] == 255)
    bottom = max(y for y in range(packed.height) for x in range(packed.width) if pixels[x, y][3] == 255)
    draw.rectangle((left * scale, top * scale, right * scale + 3, bottom * scale + 3), outline=CONTENT_MARK, width=1)
    return result


def review_1x(packed: Image.Image) -> Image.Image:
    sheet = Image.new("RGBA", (packed.width * len(BACKGROUNDS), packed.height), BACKGROUNDS[0])
    for index, background in enumerate(BACKGROUNDS):
        sheet.paste(panel(packed, background, 1), (index * packed.width, 0))
    return sheet


def review_4x(packed: Image.Image) -> Image.Image:
    width = packed.width * 4
    height = packed.height * 4
    sheet = Image.new("RGBA", (width * 4, height), BACKGROUNDS[0])
    for index, background in enumerate(BACKGROUNDS):
        sheet.paste(panel(packed, background, 4), (index * width, 0))
    sheet.paste(marked_panel(packed), (3 * width, 0))
    return sheet


def validate(packed: Image.Image, stats: dict) -> list[str]:
    checks: list[str] = []
    if packed.size != tuple(RECIPE["canvas"]):
        raise PackError(f"packed size {packed.size} != {RECIPE['canvas']}")
    if sum(packed.getchannel("A").histogram()[1:255]) != 0:
        raise PackError("packed proposal must have binary alpha")
    for key in ("top", "bottom", "left", "right", "design_px", "components"):
        if stats[key] != EXPECTED[key]:
            raise PackError(f"measured {key}={stats[key]} != recorded calibration {EXPECTED[key]}")
    if stats["trunk_center_col"] != EXPECTED["trunk_center_col"]:
        raise PackError(f"trunk center column {stats['trunk_center_col']} != {EXPECTED['trunk_center_col']}")
    if stats["root_band_cols"] < stats["trunk_band_cols"] * EXPECTED["root_widening_ratio_min"]:
        raise PackError("root flare does not separate from the trunk band")
    checks.append(
        f"PASS single component {stats['design_px']} px, bbox x{stats['left']}..x{stats['right']} y{stats['top']}..y{stats['bottom']}"
    )
    checks.append(
        f"PASS trunk center col {stats['trunk_center_col']:.1f} at y{EXPECTED['trunk_center_row']} (span x{stats['trunk_row_span'][0]}..x{stats['trunk_row_span'][1]}), "
        f"trunk cols {stats['trunk_band_cols']} vs root cols {stats['root_band_cols']}"
    )
    checks.append(
        "PASS deviations vs guide: top %+d px (behind canopy disc), feet %+d px, widest rows 1 px left; reported, not forced"
        % (stats["top"] - 56, stats["bottom"] - 140)
    )
    return checks


def main() -> int:
    try:
        raw = load_raw()
        packed = pack(raw)
        stats = measure(packed)
        checks = validate(packed, stats)
        REVIEW_DIR.mkdir(parents=True, exist_ok=True)
        outputs = {
            "pine_common_candidate_packed_96x144.png": packed,
            "pine_common_candidate_review_1x.png": review_1x(packed),
            "pine_common_candidate_review_4x.png": review_4x(packed),
        }
        report = []
        for name, image in outputs.items():
            path = REVIEW_DIR / name
            image.save(path, format="PNG", optimize=False)
            report.append({"path": display_path(path), "sha256": sha256_file(path), "bytes": path.stat().st_size, "size": list(image.size)})
        ART_PATH.parent.mkdir(parents=True, exist_ok=True)
        packed.save(ART_PATH, format="PNG", optimize=False)
        art_sha = sha256_file(ART_PATH)
        if art_sha != PINNED_ART_SHA256:
            raise PackError(f"installed pine common sha256 {art_sha} != accepted {PINNED_ART_SHA256}")
        installed = {"path": display_path(ART_PATH), "sha256": art_sha, "bytes": ART_PATH.stat().st_size, "size": list(packed.size)}
        manifest = {
            "recipe": RECIPE,
            "raw": dict(RAW, canvas=list(Image.open(REPO_ROOT / RAW["path"]).size)),
            "expected_calibration": EXPECTED,
            "measured": stats,
            "installed": dict(installed, pinned_sha256=PINNED_ART_SHA256, accepted="2026-10-22 parent review, common layer only, as drawn"),
            "outputs": report,
        }
        manifest_path = REVIEW_DIR / "pine_manifest_candidate.json"
        manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
        print(json.dumps({"installed": installed, "outputs": report + [{"path": display_path(manifest_path)}], "checks": checks}, sort_keys=True))
        for line in checks:
            print(line)
        print(f"PINE COMMON PACK OK (installed {display_path(ART_PATH)}, sha256 {art_sha} == accepted)")
    except (PackError, OSError, ValueError) as exc:
        print(f"PINE PACK FAILED: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
