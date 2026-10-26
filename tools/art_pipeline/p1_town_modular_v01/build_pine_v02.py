#!/usr/bin/env python3
"""Compact-base (common v02) pack, accepted install, and review sheets.

The parent executed request C (root imagegen edit of the v02 base guide)
and ACCEPTED the assembly AS DRAWN (2026-10-22) for the rendered sample
stage - static art scope only, not engine/native acceptance. This tool
packs the retained raw with the SAME whole-canvas uniform nearest
transform as every pine candidate (scale exactly 32/3, origin (0,0) ->
(0,0), alpha binarization at 250), re-measures the recorded calibration,
then INSTALLS the accepted layers at the runtime art paths with their
reviewed hashes pinned:

- art/production/p1/town_modular_v01/pine_common_v02.png  (the C base)
- art/production/p1/town_modular_v01/pine_canopy_v02.png  (the B upper
  region cut at its measured crown bottom row y96; B's trunk rows are
  discarded wholesale - an explicit redesign cut, never a silent transfer
  of the tall v01 common, which stays installed and untouched)
- art/production/p1/town_modular_v01/pine_shadow_v02.png  (small
  CODE-AUTHORED contact shadow: flat cold slab RGB (26,32,46), one alpha
  level 56 plus a contact dither at 104, mirroring the accepted Loadout
  shadow family; no generator involved)

Review sheets (ignored directory): the C base isolated (1x/4x), the
assembly at full and 25% canopy alpha over gray/white/black plus a flat
opaque sample ground (1x/2x), and hero-readability composites using the
EXISTING actual ranger sprite (combat_style_r13/v03 north idle cell,
hash-pinned) at legal feet just outside the movement envelope plus the
ACTUAL hero radius 6: the preview layout (authored envelope r14, distance
20+epsilon) and a separately labelled native-layout proposal (existing
native circle r8.5, distance 14.5+epsilon) - visual positioning only,
NOT collider authorization. Pure visual composites - NOT engine evidence.

Run from the repository root in the approved portable environment:

    python3 -I tools/art_pipeline/p1_town_modular_v01/build_pine_v02.py
"""

from __future__ import annotations

import hashlib
import importlib.util
import json
import sys
from collections import deque
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

REPO_ROOT = Path(__file__).resolve().parents[3]
TOOL_DIR = Path(__file__).resolve().parent
REVIEW_DIR = REPO_ROOT / "build/current/p1-town-modular-v01/pine-checkpoint-1"

RAW = {
    "path": "docs/art-production/p1-town-modular-v01/sources/pine_common_v02_candidate_01.png",
    "sha256": "e2fd870180d40b514d1558bd5949ff7efae991add5e664dc7d76cb71d5d3aadf",
}
B_PACK = {
    "path": "build/current/p1-town-modular-v01/pine-checkpoint-1/pine_upper_candidate_packed_96x144.png",
    "sha256": "e32faebbb0dd41d7a2403ff2d8091b19c07ffe4e54e30ef87c9e2e5dfefb43cd",
}
RANGER = {
    "path": "art/production/p1/combat_style_r13/v03/ranger.png",
    "sha256": "9db9f18771f6ca1c2f14ab0f051deb674f2cc9c3b8e57c2ea9e8f7f8b22af4a0",
    "cell": (48, 192, 48, 48),   # ranger.north.idle.0 (ranger_atlas.json)
    "anchor": (24, 44),          # cell-space feet anchor
}
RECIPE = {
    "stage": "pine_common_v02_candidate_01_pack_accepted",
    "source_canvas": [1024, 1536],
    "canvas": [96, 144],
    "scale": [32, 3],
    "src_origin": [0, 0],
    "dst_origin": [0, 0],
    "alpha_threshold": 250,
}
EXPECTED = {
    "top": 94, "bottom": 135, "left": 33, "right": 63,
    "design_px": 653, "components": 1,
    "trunk_center_col": 47.5, "trunk_center_row": 112,
    "content_above_90": 0,
}
CROWN_CUT = 96            # B's measured crown bottom (build_pine_upper EXPECTED crown_bottom_run)
CANOPY_ALPHA = 64         # 25% of 255 - the faded-state preview
GROUND = (144, 168, 192, 255)   # flat opaque sample ground, snow family #90a8c0
BACKGROUNDS = ("gray", "white", "black", "ground")
BG_COLORS = {
    "gray": (128, 128, 128, 255), "white": (255, 255, 255, 255),
    "black": (0, 0, 0, 255), "ground": GROUND,
}
# Hero readability scene: tree canvas pasted at offset, anchor -> (80,144).
SCENE = (160, 176)
TREE_OFFSET = (32, 16)
HERO_RADIUS = 6           # ACTUAL hero collision radius (parent-corrected 2026-10-22)
# Two separately labelled layouts. Legal feet distance = envelope radius +
# hero radius + 1 px epsilon (the resolver adds the hero radius exactly once,
# to the envelope, so a visual position epsilon keeps the composites legal).
# Visual positioning only - NOT collider authorization. The native row uses
# the EXISTING native circle r8.5; preserving native movement is preferred
# (replacing it with the preview r14 contract would block T26).
LAYOUTS = {
    "preview r14": {
        "envelope_radius": 14.0, "distance": 21,          # 14 + 6 + 1
        "placements": {"north": (80, 123), "diagonal": (95, 129)},  # 21 * 0.7071 -> 15
    },
    "native r8.5": {
        "envelope_radius": 8.5, "distance": 15,           # 8.5 + 6 + 0.5
        "placements": {"north": (80, 129), "diagonal": (91, 133)},  # 15 * 0.7071 -> 11
    },
}
LABEL_FONT = ImageFont.load_default()
LABEL_PLACEMENTS = {"north": "north", "diagonal": "diag"}
# Accepted install targets (reviewed bytes; hashes pinned, verified on write).
ACCEPTED = {
    "common_v02": {
        "path": "art/production/p1/town_modular_v01/pine_common_v02.png",
        "sha256": "815160150d4142c138ac0a789d68564d07e7565290d0fd4f995854fec8083392",
    },
    "canopy_v02": {
        "path": "art/production/p1/town_modular_v01/pine_canopy_v02.png",
        "sha256": "93833b1f79bcc5d4609f9078d15e0486a2190d9c7de07ff73fa7f41cd27947c0",
    },
}
# Code-authored contact shadow (no generator involved): flat cold slab in the
# accepted loadout_shadow family (RGB 26,32,46; observed alpha levels 56/104),
# offset lower-right of the feet like the loadout shadow, corners chamfered.
SHADOW = {
    "path": "art/production/p1/town_modular_v01/pine_shadow_v02.png",
    "rgb": (26, 32, 46),
    "alpha_slab": 56,
    "alpha_contact": 104,
    "slab": (36, 133, 68, 139),   # x36..x68, y133..y139 (feet line is y135)
    "contact_rows": (133, 135),   # trunk-contact dither rows
    "contact_cols": (41, 58),     # every second column in those rows
}
EXPECTED_SHADOW = {"total_px": 227, "contact_px": 27, "slab_px": 200}  # 33x7 - 4 chamfered corners
OUTPUTS = (
    "pine_v02_common_candidate_96x144.png",
    "pine_v02_canopy_candidate_96x144.png",
    "pine_v02_common_review_1x.png",
    "pine_v02_common_review_4x.png",
    "pine_v02_assembly_review_1x.png",
    "pine_v02_assembly_review_2x.png",
    "pine_v02_hero_readability_1x.png",
    "pine_v02_hero_readability_2x.png",
    "pine_v02_manifest_candidate.json",
)


class PackError(ValueError):
    """Raised when an input or output contract is violated."""


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


def load_pinned(entry: dict) -> Image.Image:
    path = REPO_ROOT / entry["path"]
    if not path.is_file():
        raise PackError(f"pinned input missing: {path}")
    digest = sha256_file(path)
    if digest != entry["sha256"]:
        raise PackError(f"{path.name} sha256 {digest} != pinned {entry['sha256']}")
    return Image.open(path).convert("RGBA")


def src_index(dst: int) -> int:
    num, den = RECIPE["scale"]
    return RECIPE["src_origin"][0] + ((2 * (dst - RECIPE["dst_origin"][0]) + 1) * num) // (2 * den)


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


def alpha_buckets(image: Image.Image) -> dict:
    hist = image.getchannel("A").histogram()
    return {
        "0": hist[0], "1..31": sum(hist[1:32]), "32..127": sum(hist[32:128]),
        "128..199": sum(hist[128:200]), "200..249": sum(hist[200:250]),
        "250..254": sum(hist[250:255]), "255": hist[255],
    }


def opaque(packed: Image.Image) -> dict[tuple[int, int], tuple[int, int, int]]:
    pixels = packed.load()
    return {(x, y): pixels[x, y][:3] for y in range(packed.height) for x in range(packed.width) if pixels[x, y][3] == 255}


def components(grid: dict[tuple[int, int], tuple[int, int, int]]) -> list[int]:
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
    grid = opaque(packed)
    rows = {y: sorted(x for (x, yy) in grid if yy == y) for y in range(packed.height)}
    rows = {y: xs for y, xs in rows.items() if xs}
    sizes = components(grid)
    trunk_row = EXPECTED["trunk_center_row"]
    span = (min(rows[trunk_row]), max(rows[trunk_row])) if trunk_row in rows else None
    flare = [x for y in range(130, 136) for x in rows.get(y, [])]
    return {
        "top": min(rows), "bottom": max(rows),
        "left": min(xs[0] for xs in rows.values()), "right": max(xs[-1] for xs in rows.values()),
        "design_px": sum(len(xs) for xs in rows.values()),
        "components": len(sizes), "component_sizes": sizes,
        "content_above_90": sum(1 for (_, y) in grid if y <= 90),
        "trunk_row_span": span,
        "trunk_center_col": (span[0] + span[1]) / 2 if span else None,
        "flare_cols": [min(flare), max(flare)] if flare else None,
        "margins_rows_above": min(rows), "margins_rows_below": packed.height - 1 - max(rows),
    }


def cut_canopy(b_pack: Image.Image) -> Image.Image:
    """B upper region only: rows y <= CROWN_CUT; B's trunk is discarded."""
    canopy = Image.new("RGBA", RECIPE["canvas"], (0, 0, 0, 0))
    src = b_pack.load()
    dst = canopy.load()
    for y in range(0, CROWN_CUT + 1):
        for x in range(RECIPE["canvas"][0]):
            if src[x, y][3] == 255:
                dst[x, y] = src[x, y]
    return canopy


def composite(base: Image.Image, canopy: Image.Image, canopy_alpha: int) -> Image.Image:
    result = base.copy()
    if canopy_alpha == 255:
        result.alpha_composite(canopy)
        return result
    faded = canopy.copy()
    pixels = faded.load()
    for y in range(faded.height):
        for x in range(faded.width):
            r, g, b, a = pixels[x, y]
            if a:
                pixels[x, y] = (r, g, b, canopy_alpha)
    result.alpha_composite(faded)
    return result


def on_background(image: Image.Image, background: tuple[int, int, int, int], scale: int) -> Image.Image:
    big = image.resize((image.width * scale, image.height * scale), Image.Resampling.NEAREST)
    panel = Image.new("RGBA", big.size, background)
    panel.alpha_composite(big)
    return panel


def assembly_sheet(base: Image.Image, canopy: Image.Image, scale: int) -> Image.Image:
    width, height = RECIPE["canvas"][0] * scale, RECIPE["canvas"][1] * scale
    sheet = Image.new("RGBA", (width * len(BACKGROUNDS), height * 2), BG_COLORS["gray"])
    for row, alpha in ((0, 255), (1, CANOPY_ALPHA)):
        assembled = composite(base, canopy, alpha)
        for column, name in enumerate(BACKGROUNDS):
            sheet.paste(on_background(assembled, BG_COLORS[name], scale), (column * width, row * height))
    return sheet


def marked_common(packed: Image.Image) -> Image.Image:
    guides = _load("make_pine_guides")
    result = on_background(packed, BG_COLORS["gray"], 4)
    guides.draw_marks(result)
    draw = ImageDraw.Draw(result)
    grid = opaque(packed)
    left = min(x for (x, _) in grid)
    right = max(x for (x, _) in grid)
    top = min(y for (_, y) in grid)
    bottom = max(y for (_, y) in grid)
    draw.rectangle((left * 4, top * 4, right * 4 + 3, bottom * 4 + 3), outline=(0, 255, 255, 255), width=1)
    for row, color in ((top, (255, 160, 0, 255)), (CROWN_CUT, (255, 0, 0, 255))):
        draw.line((0, row * 4, result.width, row * 4), fill=color, width=1)
    return result


def hero_scene(base: Image.Image, canopy: Image.Image, canopy_alpha: int, feet: tuple[int, int], ranger_cell: Image.Image) -> Image.Image:
    scene = Image.new("RGBA", SCENE, GROUND)
    ax, ay = RANGER["anchor"]
    cell = ranger_cell.copy()
    scene.alpha_composite(cell, (feet[0] - ax, feet[1] - ay))
    tree = composite(base, canopy, canopy_alpha)
    scene.alpha_composite(tree, TREE_OFFSET)
    return scene


def label_panel(panel: Image.Image, text: str) -> Image.Image:
    """Opaque ASCII label bar inside the panel's top edge (self-describing sheets)."""
    draw = ImageDraw.Draw(panel)
    draw.rectangle((0, 0, panel.width - 1, 13), fill=(0, 0, 0, 255))
    draw.text((4, 2), text, fill=(255, 255, 255, 255), font=LABEL_FONT)
    return panel


def hero_sheet(base: Image.Image, canopy: Image.Image, ranger_cell: Image.Image, scale: int) -> Image.Image:
    """One labelled row per (layout, placement); columns = canopy full / 25%."""
    panel_w, panel_h = SCENE[0] * scale, SCENE[1] * scale
    rows = [(layout, placement) for layout in LAYOUTS for placement in ("north", "diagonal")]
    sheet = Image.new("RGBA", (panel_w * 2, panel_h * len(rows)), BG_COLORS["gray"])
    for row, (layout_name, placement) in enumerate(rows):
        feet = LAYOUTS[layout_name]["placements"][placement]
        for column, alpha in enumerate((255, CANOPY_ALPHA)):
            scene = hero_scene(base, canopy, alpha, feet, ranger_cell)
            panel = on_background(scene, GROUND, scale)
            state = "full" if alpha == 255 else "25%"
            label_panel(panel, f"{layout_name} {LABEL_PLACEMENTS[placement]} {state}")
            sheet.paste(panel, (column * panel_w, row * panel_h))
    return sheet


def author_shadow() -> tuple[Image.Image, dict]:
    """Deterministic code-authored contact shadow; no generator involved."""
    x0, y0, x1, y1 = SHADOW["slab"]
    r, g, b = SHADOW["rgb"]
    image = Image.new("RGBA", RECIPE["canvas"], (0, 0, 0, 0))
    pixels = image.load()
    counts = {"total": 0, "contact": 0}
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            if (x in (x0, x1)) and (y in (y0, y1)):
                continue  # chamfered corners
            contact = (
                SHADOW["contact_rows"][0] <= y <= SHADOW["contact_rows"][1]
                and SHADOW["contact_cols"][0] <= x <= SHADOW["contact_cols"][1]
                and (x - SHADOW["contact_cols"][0]) % 2 == 0
            )
            alpha = SHADOW["alpha_contact"] if contact else SHADOW["alpha_slab"]
            pixels[x, y] = (r, g, b, alpha)
            counts["total"] += 1
            counts["contact"] += int(contact)
    return image, counts


def validate(packed: Image.Image, stats: dict, canopy: Image.Image, b_pack: Image.Image) -> list[str]:
    checks: list[str] = []
    if packed.size != tuple(RECIPE["canvas"]):
        raise PackError(f"packed size {packed.size} != {RECIPE['canvas']}")
    if sum(packed.getchannel("A").histogram()[1:255]) != 0:
        raise PackError("packed base must have binary alpha")
    for key in ("top", "bottom", "left", "right", "design_px", "components", "content_above_90"):
        if stats[key] != EXPECTED[key]:
            raise PackError(f"measured {key}={stats[key]} != recorded calibration {EXPECTED[key]}")
    if stats["trunk_center_col"] != EXPECTED["trunk_center_col"]:
        raise PackError(f"trunk center column {stats['trunk_center_col']} != {EXPECTED['trunk_center_col']}")
    upper = _load("build_pine_upper")
    if CROWN_CUT != upper.EXPECTED["crown_bottom_run"]:
        raise PackError(f"CROWN_CUT {CROWN_CUT} != build_pine_upper crown_bottom_run {upper.EXPECTED['crown_bottom_run']}")
    canopy_grid = opaque(canopy)
    if any(y > CROWN_CUT for (_, y) in canopy_grid):
        raise PackError("canopy carries content below the crown cut")
    if not any(y > CROWN_CUT for (_, y) in opaque(b_pack)):
        raise PackError("B pack lost its base rows - pin mismatch")
    base_grid = opaque(packed)
    overlap_rows = sorted({y for (_, y) in canopy_grid} & {y for (_, y) in base_grid})
    if not overlap_rows:
        raise PackError("seam gap: no row where canopy and base both have content")
    assembled = composite(packed, canopy, 255)
    below = opaque(assembled)
    base_below = {(x, y): c for (x, y), c in base_grid.items() if y > CROWN_CUT}
    wrong = [(x, y) for (x, y), c in base_below.items() if below.get((x, y)) != c]
    if wrong:
        raise PackError(f"composite altered base rows below the cut at {wrong[:8]}")
    checks.append(
        f"PASS compact base rows y{stats['top']}..y{stats['bottom']}, cols x{stats['left']}..x{stats['right']}, "
        f"{stats['design_px']} px, 1 component, {stats['content_above_90']} px at or above y90"
    )
    checks.append(
        f"PASS seam: base top y{stats['top']} overlaps the crown cut y{CROWN_CUT} on rows {overlap_rows[0]}..{overlap_rows[-1]}; "
        f"rows y{CROWN_CUT + 1}+ are base-only by construction (no duplicate trunk from B)"
    )
    checks.append(
        f"PASS trunk center col {stats['trunk_center_col']:.1f} at y{EXPECTED['trunk_center_row']} "
        f"(span x{stats['trunk_row_span'][0]}..x{stats['trunk_row_span'][1]}), flare x{stats['flare_cols'][0]}..x{stats['flare_cols'][1]}, "
        f"feet y{stats['bottom']} (B was y137; 2 px drift reported, not forced)"
    )
    return checks


def main() -> int:
    try:
        raw = load_pinned(RAW)
        if raw.size != tuple(RECIPE["source_canvas"]) or raw.width * 3 != raw.height * 2:
            raise PackError(f"raw canvas {raw.size} is not the exact 2:3 1024x1536 grid; uniform 32/3 not applicable")
        b_pack = load_pinned(B_PACK)
        ranger = load_pinned(RANGER)
        ranger_cell = ranger.crop((RANGER["cell"][0], RANGER["cell"][1], RANGER["cell"][0] + RANGER["cell"][2], RANGER["cell"][1] + RANGER["cell"][3]))
        packed = pack(raw)
        stats = measure(packed)
        canopy = cut_canopy(b_pack)
        checks = validate(packed, stats, canopy, b_pack)
        REVIEW_DIR.mkdir(parents=True, exist_ok=True)
        outputs = {
            "pine_v02_common_candidate_96x144.png": packed,
            "pine_v02_canopy_candidate_96x144.png": canopy,
            "pine_v02_common_review_1x.png": assembly_row(packed),
            "pine_v02_common_review_4x.png": common_review_4x(packed),
            "pine_v02_assembly_review_1x.png": assembly_sheet(packed, canopy, 1),
            "pine_v02_assembly_review_2x.png": assembly_sheet(packed, canopy, 2),
            "pine_v02_hero_readability_1x.png": hero_sheet(packed, canopy, ranger_cell, 1),
            "pine_v02_hero_readability_2x.png": hero_sheet(packed, canopy, ranger_cell, 2),
        }
        report = []
        for name, image in outputs.items():
            path = REVIEW_DIR / name
            image.save(path, format="PNG", optimize=False)
            report.append({"path": display_path(path), "sha256": sha256_file(path), "bytes": path.stat().st_size, "size": list(image.size)})
        # Accepted install: the reviewed bytes land at the runtime art paths,
        # hash-pinned; the v01 runtime assets are never touched here.
        installed = []
        for key, image in (("common_v02", packed), ("canopy_v02", canopy)):
            entry = ACCEPTED[key]
            path = REPO_ROOT / entry["path"]
            image.save(path, format="PNG", optimize=False)
            digest = sha256_file(path)
            if digest != entry["sha256"]:
                raise PackError(f"installed {path.name} sha256 {digest} != accepted {entry['sha256']}")
            installed.append({
                "layer": key, "path": display_path(path), "sha256": digest,
                "bytes": path.stat().st_size, "size": RECIPE["canvas"],
                "accepted": "2026-10-22 parent review, as drawn (rendered sample stage, static art only)",
            })
        shadow, shadow_counts = author_shadow()
        shadow_path = REPO_ROOT / SHADOW["path"]
        shadow.save(shadow_path, format="PNG", optimize=False)
        shadow_hist = shadow.getchannel("A").histogram()
        shadow_levels = [level for level, count in enumerate(shadow_hist) if count]
        if shadow_levels != [0, SHADOW["alpha_slab"], SHADOW["alpha_contact"]]:
            raise PackError(f"shadow alpha levels {shadow_levels} != [0, {SHADOW['alpha_slab']}, {SHADOW['alpha_contact']}]")
        if shadow.getbbox() != (SHADOW["slab"][0], SHADOW["slab"][1], SHADOW["slab"][2] + 1, SHADOW["slab"][3] + 1):
            raise PackError(f"shadow bbox {shadow.getbbox()} != slab {SHADOW['slab']} (bbox is exclusive)")
        if (shadow_counts["total"], shadow_counts["contact"],
                shadow_counts["total"] - shadow_counts["contact"]) != (
                EXPECTED_SHADOW["total_px"], EXPECTED_SHADOW["contact_px"], EXPECTED_SHADOW["slab_px"]):
            raise PackError(f"shadow counts {shadow_counts} != {EXPECTED_SHADOW}")
        installed.append({
            "layer": "shadow_v02", "path": display_path(shadow_path), "sha256": sha256_file(shadow_path),
            "bytes": shadow_path.stat().st_size, "size": RECIPE["canvas"],
            "accepted": "code-authored contact shadow 2026-10-22, loadout_shadow family; no generator involved",
        })
        checks.append(
            f"PASS install: pine_common_v02.png and pine_canopy_v02.png written with accepted hashes; "
            f"pine_shadow_v02.png code-authored ({shadow_counts['total']} px, "
            f"{shadow_counts['contact']} contact + {shadow_counts['total'] - shadow_counts['contact']} slab)"
        )
        checks.append(
            "PASS hero readability: ACTUAL hero radius 6; preview r14 layout distance 21 (north (80,123), "
            "diagonal (95,129)); native r8.5 proposal distance 15 (north (80,129), diagonal (91,133)) - "
            "visual positioning only, NOT collider authorization"
        )
        manifest = {
            "recipe": RECIPE,
            "raw": dict(RAW, canvas=list(raw.size), alpha_buckets=alpha_buckets(raw)),
            "b_pack": dict(B_PACK, crown_cut=CROWN_CUT),
            "ranger": dict(RANGER, cell_bbox=list(ranger_cell.getbbox())),
            "expected_calibration": EXPECTED,
            "measured": stats,
            "canopy": {
                "source": "B upper region rows y<=96; B trunk rows discarded (explicit redesign cut, no v01 transfer)",
                "alpha_states": {"full": 255, "faded_preview": CANOPY_ALPHA},
                "opaque_px": len(opaque(canopy)),
            },
            "ground_sample": {"color": list(GROUND), "note": "flat opaque snow-family tone #90a8c0, sheet-only"},
            "hero_readability": {
                "sprite": RANGER["path"], "frame": "ranger.north.idle.0",
                "hero_radius_px": HERO_RADIUS,
                "tree_anchor_scene": [TREE_OFFSET[0] + 48, TREE_OFFSET[1] + 128],
                "layouts": {
                    name: {
                        "envelope_radius": layout["envelope_radius"],
                        "legal_distance": layout["distance"],
                        "placements": {key: list(value) for key, value in layout["placements"].items()},
                    }
                    for name, layout in LAYOUTS.items()
                },
                "note": (
                    "legal feet = envelope radius + hero radius + 1 px epsilon; pure visual composites, NOT "
                    "engine evidence; the native r8.5 row is a positioning proposal using the existing native "
                    "circle (preserving native movement is preferred; replacing it with r14 would block T26) - "
                    "NOT collider authorization"
                ),
            },
            "shadow": {
                "path": display_path(shadow_path), "rgb": list(SHADOW["rgb"]),
                "alpha_levels": [SHADOW["alpha_slab"], SHADOW["alpha_contact"]],
                "slab": list(SHADOW["slab"]), "counts": {**shadow_counts, "slab": shadow_counts["total"] - shadow_counts["contact"]},
                "provenance": (
                    "code-authored 2026-10-22 (deterministic constants in this tool); color family sampled "
                    "from the accepted loadout_shadow.png (RGB 26,32,46; alpha 56 and 104); no generator involved"
                ),
            },
            "installed": installed,
            "policy_note": (
                "primitive fade: the canopy layer's own alpha + occlusion volumes; mask/revealed pair "
                "superseded (historical). Definitions authored at content/environment_objects/town_pine_v02.tres "
                "and town_loadout_fade_v01.tres pending ca validation. v01 runtime assets and v01 definitions untouched"
            ),
            "outputs": report,
        }
        manifest_path = REVIEW_DIR / "pine_v02_manifest_candidate.json"
        manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
        print(json.dumps({"outputs": report + [{"path": display_path(manifest_path)}], "installed": installed, "checks": checks}, sort_keys=True))
        for line in checks:
            print(line)
        print("PINE V02 INSTALL OK (accepted as drawn: common_v02 + canopy_v02 + code-authored shadow_v02 at runtime art paths; v01 untouched)")
    except (PackError, OSError, ValueError) as exc:
        print(f"PINE V02 PROPOSAL FAILED: {exc}", file=sys.stderr)
        return 1
    return 0


def assembly_row(packed: Image.Image) -> Image.Image:
    """C base alone over gray/white/black at native scale."""
    sheet = Image.new("RGBA", (RECIPE["canvas"][0] * 3, RECIPE["canvas"][1]), BG_COLORS["gray"])
    for index, name in enumerate(("gray", "white", "black")):
        sheet.paste(on_background(packed, BG_COLORS[name], 1), (index * RECIPE["canvas"][0], 0))
    return sheet


def common_review_4x(packed: Image.Image) -> Image.Image:
    sheet = Image.new("RGBA", (RECIPE["canvas"][0] * 16, RECIPE["canvas"][1] * 4), BG_COLORS["gray"])
    for index, name in enumerate(("gray", "white", "black")):
        sheet.paste(on_background(packed, BG_COLORS[name], 4), (index * RECIPE["canvas"][0] * 4, 0))
    sheet.paste(marked_common(packed), (3 * RECIPE["canvas"][0] * 4, 0))
    return sheet


if __name__ == "__main__":
    sys.exit(main())
