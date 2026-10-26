#!/usr/bin/env python3
"""Deterministic upper-layer pack for the Loadout building sample (checkpoint 2).

Normalizes the two retained generation-stage guide-edit raws (roof `full` and
roof-off `revealed`) into 256x224 production layers with ONE shared uniform
nearest-neighbour transform, and authors the separate `shadow.contact` ground
layer in code. The accepted `common` layer is only read (hash-pinned) so it
stays byte-identical; the edited facades baked into both raws are discarded at
the seam cut and never replace it.

Generation-stage normalization (both raws, no independent per-state fitting):
- both raws share the same 1341x1173 canvas (5.23828x / 5.23661x of 256x224);
- uniform scale s = 419/80 = 5.2375 source px per destination px, derived from
  content anchors (raw ridge row 249 -> y48, raw eaves/plane-bottom row 668 ->
  y128: 419 raw px over 80 native rows) and cross-checked against both canvas
  ratios (within 0.04%);
- src origin (209, 668) -> dst origin (41, 129): the raw left roof-plane corner
  column and the raw eaves/plane-bottom row anchor the seam at native
  y 128..130 (first sampled index per axis is origin + s/2, i.e. 211 / 670);
- for destination pixel (dx, dy):
    src_x = 209 + ((2*(dx - 41) + 1) * 419) // 160
    src_y = 668 + ((2*(dy - 129) + 1) * 419) // 160
  out-of-canvas source indices stay transparent (the wide empty margins).
- alpha >= 128 keeps the source RGB with alpha forced to 255; anything else
  becomes transparent black. No palette quantization, no per-pixel color edits,
  no nonuniform stretching, no per-state refitting.

Seam cut (authored calibration, recorded for parent review): both layers keep
native rows <= 130 only (the spec seam band y 128..130). For `full` this
discards the generator's hanging eaves-snow overhang below the seam (raw rows
~681..695, about 3 native rows) together with the edited facade; for
`revealed` it trims the post bottoms where they meet the edited plate so the
posts end standing on the accepted common's lip/plate at y<=130.

Invariants asserted at build time:
- canvas exactly 256x224, binary alpha on both upper layers;
- no content above y=48 (roof ridge) or below y=130, none inside the 8 px
  margin;
- revealed content confined to the two stub bands (central bay transparent);
- shadow uses only its two authored alpha levels (collision never comes from
  alpha; the shadow is a GroundEffects visual only).

Run from the repository root in the approved portable environment:

    source /data/claude/workspace/.tools/make-it-big/portable-cpu/env.sh
    source scripts/project_env.sh
    python3 -I tools/art_pipeline/p1_town_modular_v01/build_upper.py
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw

TOOL_DIR = Path(__file__).resolve().parent


def _load(name: str):
    # Reuse an already-loaded sibling (e.g. the test harness's copy) so class
    # identities like BuildError stay shared instead of being duplicated.
    if name in sys.modules:
        return sys.modules[name]
    spec = importlib.util.spec_from_file_location(name, TOOL_DIR / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    sys.modules[name] = module
    return module


build_common = _load("build_common")
make_guides = _load("make_guides")

REPO_ROOT = build_common.REPO_ROOT
source_index = build_common.source_index
sha256_file = build_common.sha256_file
display_path = build_common.display_path
BuildError = build_common.BuildError

ART_DIR = REPO_ROOT / "art/production/p1/town_modular_v01"
REVIEW_DIR = REPO_ROOT / "build/current/p1-town-modular-v01/checkpoint-2"

# The accepted checkpoint-1 common layer is read for review compositing only;
# its hash is pinned so any accidental change fails the build.
COMMON = {
    "path": "art/production/p1/town_modular_v01/loadout_common.png",
    "sha256": "8e734c20497e306110c53b05469059e64780d68e1f65701637cc148ceb95af78",
}

RECIPE = {
    "stage": "generation_guide_edit_normalization",
    "full_source": "docs/art-production/p1-town-modular-v01/sources/loadout_upper_candidate_01.png",
    "full_source_sha256": "1d1711572c66901d190c1f1d0920e0199e20c198a1d9e0eebdc99526fc8a3f14",
    "revealed_source": "docs/art-production/p1-town-modular-v01/sources/loadout_upper_candidate_02.png",
    "revealed_source_sha256": "c10d04f299048b915ce6d081dc74f9d589046c69b26bebe200575102d75bf382",
    "reference_guides": [
        "build/current/p1-town-modular-v01/checkpoint-1/loadout_roof_guide_256x224.png",
        "build/current/p1-town-modular-v01/checkpoint-1/loadout_stubs_guide_256x224.png",
    ],
    "source_canvas": [1341, 1173],
    "canvas": [256, 224],
    "scale": [419, 80],          # uniform, source px per destination px
    "src_origin": [209, 668],    # raw left roof-plane corner / eaves plane-bottom row
    "dst_origin": [41, 129],     # native anchors: polygon corner zone / seam band
    "alpha_threshold": 128,
    "seam_cut_last_row": 130,    # spec seam y 128..130; rows above the seam stay common-only
    "roof_top_row": 48,          # nothing above the ridge line
    "margin": 8,
    # Spec stub zones x 62..72 / 184..194, tolerance +/-2 for the generator.
    "stub_bands": [[60, 74], [182, 196]],
}

SHADOW = {
    "canvas": [256, 224],
    "color": [26, 32, 46],        # cold slate-blue, matches the roof shadow family
    "outer_rect": [68, 176, 128, 8],  # footprint 64..192 offset +4 lower-right
    "outer_alpha": 56,
    "core_rect": [70, 177, 122, 5],
    "core_alpha": 104,            # two alpha levels: one base plus one dither step
}

# The art directory is shared with build_common.py; both builders tolerate the
# union of artifacts (build_common.ALLOWED_ARTIFACTS is the same set).
ARTIFACTS = (
    "loadout_common.png",
    "manifest.json",
    "loadout_upper_full.png",
    "loadout_upper_revealed.png",
    "loadout_shadow.png",
    "manifest_upper.json",
)
REVIEW_OUTPUTS = (
    "loadout_assembled_review_4x.png",
    "loadout_upper_isolated_4x.png",
    "loadout_roof_outline_compare_4x.png",
)

OUTLINE_ROWS = (48, 60, 80, 100, 120, 127, 128, 129, 130)
MEASURED_COLOR = (0, 255, 255, 255)    # cyan: packed full-layer opaque edge
SPEC_COLOR = (255, 0, 255, 255)        # magenta: authoritative silhouette polygon
BOTH_COLOR = (255, 255, 255, 255)      # white: edges coincide
NEUTRAL = (128, 128, 128, 255)
REVIEW_BACKGROUNDS = ((128, 128, 128, 255), (255, 255, 255, 255), (0, 0, 0, 255))
REVIEW_SCALE = 4
SHADOW_BACKGROUND = (202, 206, 214, 255)


def load_pinned(recipe_key: str, hash_key: str) -> Image.Image:
    path = REPO_ROOT / RECIPE[recipe_key]
    if not path.is_file():
        raise BuildError(f"source PNG does not exist: {path}")
    actual = sha256_file(path)
    if actual != RECIPE[hash_key]:
        raise BuildError(f"source hash mismatch for {path.name}: expected {RECIPE[hash_key]}, got {actual}")
    image = Image.open(path).convert("RGBA")
    if list(image.size) != RECIPE["source_canvas"]:
        raise BuildError(
            f"source canvas {image.size} differs from the locked {RECIPE['source_canvas']}; "
            "the shared normalization assumes both raws share one canvas"
        )
    return image


def normalize(source: Image.Image) -> Image.Image:
    """Apply the shared uniform nearest-neighbour transform to the full canvas."""
    (num, den), (sx0, sy0), (dx0, dy0) = recipe_window()
    canvas = Image.new("RGBA", tuple(RECIPE["canvas"]), (0, 0, 0, 0))
    out = canvas.load()
    src = source.load()
    threshold = RECIPE["alpha_threshold"]
    for dy in range(canvas.height):
        sy = source_index(dy, dy0, sy0, num, den)
        if not 0 <= sy < source.height:
            continue
        for dx in range(canvas.width):
            sx = source_index(dx, dx0, sx0, num, den)
            if not 0 <= sx < source.width:
                continue
            r, g, b, a = src[sx, sy]
            out[dx, dy] = (r, g, b, 255) if a >= threshold else (0, 0, 0, 0)
    return canvas


def recipe_window() -> tuple[tuple[int, int], tuple[int, int], tuple[int, int]]:
    return tuple(RECIPE["scale"]), tuple(RECIPE["src_origin"]), tuple(RECIPE["dst_origin"])


def gate_seam(canvas: Image.Image) -> Image.Image:
    """Keep native rows up to the seam cut; everything below is common-only."""
    layered = canvas.copy()
    draw = ImageDraw.Draw(layered)
    draw.rectangle((0, RECIPE["seam_cut_last_row"] + 1, canvas.width - 1, canvas.height - 1), fill=(0, 0, 0, 0))
    return layered


def row_span(canvas: Image.Image, y: int) -> tuple[int, int] | None:
    if not 0 <= y < canvas.height:
        return None
    pixels = canvas.load()
    span: tuple[int, int] | None = None
    for x in range(canvas.width):
        if pixels[x, y][3] == 255:
            span = (x, x) if span is None else (span[0], x)
    return span


def measure_upper(canvas: Image.Image, layer: str) -> dict:
    """Mechanical measurements plus the layer-specific invariant assertions."""
    width, height = canvas.size
    if (width, height) != tuple(RECIPE["canvas"]):
        raise BuildError(f"{layer}: canvas is {width}x{height}, expected {RECIPE['canvas']}")
    pixels = canvas.load()
    opaque = 0
    min_x = min_y = max_x = max_y = None
    previous = -1
    for y in range(height):
        row_opaque = 0
        for x in range(width):
            r, g, b, a = pixels[x, y]
            if a == 0:
                continue
            if a != 255:
                raise BuildError(f"{layer}: non-binary alpha {a} at ({x},{y})")
            opaque += 1
            row_opaque += 1
            min_x = x if min_x is None else min(min_x, x)
            max_x = x if max_x is None else max(max_x, x)
            if min_y is None:
                min_y = y
            max_y = y
        if row_opaque and previous >= 0 and y > previous + 1:
            raise BuildError(f"{layer}: empty row {previous + 1} inside the content band")
        if row_opaque:
            previous = y
    if min_x is None:
        raise BuildError(f"{layer}: layer is empty")
    margin = RECIPE["margin"]
    if min_x < margin or min_y < margin or max_x >= width - margin or max_y >= height - margin:
        raise BuildError(f"{layer}: content violates the {margin} px margin: bbox ({min_x},{min_y})-({max_x},{max_y})")
    if min_y < RECIPE["roof_top_row"]:
        raise BuildError(f"{layer}: content above y={RECIPE['roof_top_row']}: top row {min_y}")
    if max_y > RECIPE["seam_cut_last_row"]:
        raise BuildError(f"{layer}: content below the seam cut y={RECIPE['seam_cut_last_row']}: bottom row {max_y}")
    stats: dict = {
        "occupied_bbox": [min_x, min_y, max_x, max_y],
        "opaque_pixels": opaque,
        "alpha_values": [0, 255],
    }
    if layer == "revealed":
        bands = [tuple(band) for band in RECIPE["stub_bands"]]
        outside = [(x, y) for y in range(height) for x in range(width)
                   if pixels[x, y][3] == 255 and not any(lo <= x <= hi for lo, hi in bands)]
        if outside:
            raise BuildError(
                f"revealed: {len(outside)} opaque px outside the stub bands "
                f"{bands} (central bay must stay transparent); first at {outside[0]}"
            )
        measured_bands = []
        for lo, hi in bands:
            xs = [x for y in range(height) for x in range(lo, hi + 1) if pixels[x, y][3] == 255]
            ys = [y for y in range(height) for x in range(lo, hi + 1) if pixels[x, y][3] == 255]
            if not xs:
                raise BuildError(f"revealed: stub band x {lo}..{hi} is empty")
            measured_bands.append({"band_x": [lo, hi], "occupied": [min(xs), min(ys), max(xs), max(ys)]})
        stats["stub_bands"] = measured_bands
    return stats


def rect_xy(rect: tuple[int, int, int, int]) -> tuple[int, int, int, int]:
    """(x, y, width, height) as authored -> ImageDraw corner coordinates."""
    x, y, w, h = rect
    return (x, y, x + w - 1, y + h - 1)


def author_shadow() -> Image.Image:
    """Code-authored flat contact shadow: two cold alpha levels, no alpha-derived collision."""
    canvas = Image.new("RGBA", tuple(SHADOW["canvas"]), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)
    color = tuple(SHADOW["color"]) + (SHADOW["outer_alpha"],)
    draw.rectangle(rect_xy(SHADOW["outer_rect"]), fill=color)
    color = tuple(SHADOW["color"]) + (SHADOW["core_alpha"],)
    draw.rectangle(rect_xy(SHADOW["core_rect"]), fill=color)
    return canvas


def measure_shadow(canvas: Image.Image) -> dict:
    width, height = canvas.size
    if (width, height) != tuple(SHADOW["canvas"]):
        raise BuildError(f"shadow: canvas is {width}x{height}, expected {SHADOW['canvas']}")
    pixels = canvas.load()
    allowed = {0, SHADOW["outer_alpha"], SHADOW["core_alpha"]}
    counts = {alpha: 0 for alpha in allowed}
    min_x = min_y = max_x = max_y = None
    for y in range(height):
        for x in range(width):
            a = pixels[x, y][3]
            if a not in allowed:
                raise BuildError(f"shadow: unexpected alpha {a} at ({x},{y})")
            counts[a] += 1
            if a:
                min_x = x if min_x is None else min(min_x, x)
                max_x = x if max_x is None else max(max_x, x)
                min_y = y if min_y is None else min(min_y, y)
                max_y = y if max_y is None else max(max_y, y)
    ox, oy, ow, oh = SHADOW["outer_rect"]
    cx, cy, cw, ch = SHADOW["core_rect"]
    expected_outer = ow * oh - cw * ch
    if counts[SHADOW["outer_alpha"]] != expected_outer or counts[SHADOW["core_alpha"]] != cw * ch:
        raise BuildError("shadow: pixel counts do not match the authored rects")
    margin = RECIPE["margin"]
    if min_x < margin or min_y < margin or max_x >= width - margin or max_y >= height - margin:
        raise BuildError(f"shadow: content violates the {margin} px margin: bbox ({min_x},{min_y})-({max_x},{max_y})")
    return {
        "occupied_bbox": [min_x, min_y, max_x, max_y],
        "alpha_levels": [SHADOW["outer_alpha"], SHADOW["core_alpha"]],
        "alpha_pixels": {str(a): n for a, n in counts.items() if a},
        "authored_rects": {"outer": SHADOW["outer_rect"] + [SHADOW["outer_alpha"]],
                           "core": SHADOW["core_rect"] + [SHADOW["core_alpha"]]},
    }


def load_common() -> Image.Image:
    path = REPO_ROOT / COMMON["path"]
    if not path.is_file():
        raise BuildError(f"accepted common layer missing: {path} (run build_common.py first)")
    actual = sha256_file(path)
    if actual != COMMON["sha256"]:
        raise BuildError(f"common layer hash changed: expected {COMMON['sha256']}, got {actual}")
    image = Image.open(path).convert("RGBA")
    if image.size != tuple(RECIPE["canvas"]):
        raise BuildError(f"common layer is {image.size}, expected {RECIPE['canvas']}")
    return image


def outline_comparison(full: Image.Image) -> tuple[Image.Image, list[dict]]:
    """Overlay the packed full-layer outline on the authoritative polygon."""
    compare = Image.new("RGBA", tuple(RECIPE["canvas"]), (0, 0, 0, 0))
    pixels = compare.load()
    rows: list[dict] = []
    for y in range(RECIPE["roof_top_row"], RECIPE["seam_cut_last_row"] + 3):
        measured = row_span(full, y)
        spec = make_guides.silhouette_row_span(y, make_guides.SILHOUETTE)
        if measured:
            for column in measured:
                pixels[column, y] = MEASURED_COLOR
        if spec:
            for column in spec:
                if not 0 <= column < compare.width:
                    continue
                pixels[column, y] = BOTH_COLOR if pixels[column, y] == MEASURED_COLOR else SPEC_COLOR
        if y in OUTLINE_ROWS:
            rows.append({"row": y, "polygon_span": list(spec) if spec else None,
                         "measured_span": list(measured) if measured else None})
    return compare, rows


def panel(image: Image.Image, background: tuple[int, int, int, int]) -> Image.Image:
    base = Image.new("RGBA", image.size, background)
    base.alpha_composite(image)
    return base


def enlarged(image: Image.Image) -> Image.Image:
    return image.resize((image.width * REVIEW_SCALE, image.height * REVIEW_SCALE), Image.NEAREST)


def make_reviews(full: Image.Image, revealed: Image.Image, shadow: Image.Image, common: Image.Image,
                 review_output: Path) -> dict[str, str]:
    # Assembled sheet: full composite, revealed composite, mask, shadow.
    full_composite = panel(Image.alpha_composite(common, full), NEUTRAL)
    revealed_composite = panel(Image.alpha_composite(common, revealed), NEUTRAL)
    mask = Image.new("RGBA", full.size, (0, 0, 0, 255))
    mask_pixels = mask.load()
    full_pixels = full.load()
    for y in range(full.height):
        for x in range(full.width):
            if full_pixels[x, y][3] == 255:
                mask_pixels[x, y] = (255, 255, 255, 255)
    shadow_panel = panel(shadow, SHADOW_BACKGROUND)
    sheet = Image.new("RGBA", (full.width * REVIEW_SCALE * 4, full.height * REVIEW_SCALE), NEUTRAL)
    for index, part in enumerate((full_composite, revealed_composite, mask, shadow_panel)):
        sheet.alpha_composite(enlarged(part), (index * full.width * REVIEW_SCALE, 0))
    assembled_path = review_output / "loadout_assembled_review_4x.png"
    sheet.save(assembled_path, format="PNG", optimize=False)

    # Isolated sheet: both layers over gray/white/black for fringe checks.
    isolated = Image.new("RGBA", (full.width * REVIEW_SCALE * 3, full.height * REVIEW_SCALE * 2), NEUTRAL)
    for row, layer in enumerate((full, revealed)):
        for column, background in enumerate(REVIEW_BACKGROUNDS):
            isolated.alpha_composite(enlarged(panel(layer, background)),
                                     (column * full.width * REVIEW_SCALE, row * full.height * REVIEW_SCALE))
    isolated_path = review_output / "loadout_upper_isolated_4x.png"
    isolated.save(isolated_path, format="PNG", optimize=False)

    compare, rows = outline_comparison(full)
    compare_path = review_output / "loadout_roof_outline_compare_4x.png"
    enlarged(compare).save(compare_path, format="PNG", optimize=False)
    return {
        "assembled": sha256_file(assembled_path),
        "isolated": sha256_file(isolated_path),
        "outline_compare": sha256_file(compare_path),
        "outline_rows": rows,
    }


def guard_output(output: Path, allowed: tuple[str, ...]) -> None:
    if not output.exists():
        return
    if not output.is_dir():
        raise BuildError(f"output exists and is not a directory: {output}")
    unexpected = [item.name for item in output.iterdir() if item.name not in allowed]
    if unexpected:
        raise BuildError(f"refusing to write into {output}: unexpected entries {sorted(unexpected)}")


def build(art_output: Path, review_output: Path) -> dict:
    full = gate_seam(normalize(load_pinned("full_source", "full_source_sha256")))
    revealed = gate_seam(normalize(load_pinned("revealed_source", "revealed_source_sha256")))
    full_stats = measure_upper(full, "full")
    revealed_stats = measure_upper(revealed, "revealed")
    shadow = author_shadow()
    shadow_stats = measure_shadow(shadow)
    common = load_common()

    guard_output(art_output, ARTIFACTS)
    guard_output(review_output, REVIEW_OUTPUTS)
    art_output.mkdir(parents=True, exist_ok=True)
    review_output.mkdir(parents=True, exist_ok=True)

    artifacts = []
    for name, image, part_id in (
        ("loadout_upper_full.png", full, "upper"),
        ("loadout_upper_revealed.png", revealed, "upper.revealed"),
        ("loadout_shadow.png", shadow, "shadow.contact"),
    ):
        path = art_output / name
        image.save(path, format="PNG", optimize=False)
        artifacts.append({"kind": "layer", "part_id": part_id, "path": display_path(path),
                          "sha256": sha256_file(path), "bytes": path.stat().st_size})
    reviews = make_reviews(full, revealed, shadow, common, review_output)

    manifest = {
        "schema_version": 1,
        "asset_package": "p1.town_modular_v01",
        "layers": ["upper_full", "upper_revealed", "shadow_contact"],
        "status": "checkpoint_2_unaccepted",
        "recipe": RECIPE,
        "shadow_recipe": SHADOW,
        "common_reference": {"path": COMMON["path"], "sha256": COMMON["sha256"],
                             "note": "read-only for review compositing; byte-identical, never repacked"},
        "artifacts": artifacts,
        "measurements": {"upper_full": full_stats, "upper_revealed": revealed_stats,
                         "shadow": shadow_stats},
        "review_outputs": {name: sha256_file(review_output / name) for name in REVIEW_OUTPUTS},
        "outline_rows": reviews["outline_rows"],
        "technical_verification": {
            "status": "mechanical_invariants_passed",
            "scope": "shared uniform normalization, binary alpha, seam cut at y<=130, "
                     "ridge/margin bounds, revealed bay transparency, authored shadow levels; "
                     "visual acceptance and runtime integration are pending",
        },
    }
    manifest_path = art_output / "manifest_upper.json"
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return manifest


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--art-output", type=Path, default=ART_DIR,
                        help="production layer output directory")
    parser.add_argument("--review-output", type=Path, default=REVIEW_DIR,
                        help="review sheet output directory")
    args = parser.parse_args(argv)
    try:
        manifest = build(args.art_output, args.review_output)
    except (BuildError, OSError, ValueError) as exc:
        print(f"BUILD FAILED: {exc}", file=sys.stderr)
        return 1
    summary = {item["path"]: item["sha256"] for item in manifest["artifacts"]}
    summary["measurements"] = manifest["measurements"]
    print(json.dumps(summary, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
