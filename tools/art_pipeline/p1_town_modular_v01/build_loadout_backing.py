#!/usr/bin/env python3
"""Build the loadout backing plate art asset from root's generated candidate.

Deterministic promotion path (no engine, no runtime). Inputs are read-only and
hash-pinned; the only art output is the NEW asset
art/production/p1/town_modular_v01/loadout_backing_v01.png covering the
approved outer world rect (478,18)-(805,271) (== slice rect +/- 12 px),
opaque everywhere except the preserved tree_wood-owned transparent corner;
review evidence is written to the ignored
build/current/p1-town-modular-v01/loadout-backing-v01/.

Sources of truth (all verified, fail closed on mismatch):
- content/rooms/town/layers/manifest.json — loadout slice rect, owned pixel
  count, ground sha256. Ownership = ground alpha<255 inside the slice rect
  (verified equal to owned_pixels).
- docs/art-production/p1-town-modular-v01/sources/loadout_backing_candidate_01.png
  — root's generated plate, sha256-pinned.

Transform — ONE uniform rational scale, explicitly NOT an anisotropic resize:
scale = candidate_height / context_crop_height (1117/285 for the pinned raw),
applied to both axes by an integer nearest sampler
src = (x*num)//den, (y*num)//den with origin locked at (0,0) (the generation
request locked the whole canvas). Canvas residue is documented, not hidden:
source columns 1401..1407 and rows 1114..1116 are never sampled.
Registration: exhaustive +-4 px offset fit against the original opaque ring
EXCLUDING the replacement mask (the interior is legitimately repainted, so it
must not participate in the fit).

Replacement mask (parent-approved, this is NOT a fill-only pack):
- the loadout ownership hole (ground alpha<255 inside the slice rect,
  asserted == manifest owned_pixels 42,294), PLUS
- the obsolete interior rect world (620,125)-(793,259): the old building's
  ground-painted workbench/crates/wall props, which root authorized to repaint
  because the old building is removed. Verified against the candidate: the
  model's repaint blob bbox (627,137)-(753,255) lies fully inside this rect,
  and the candidate shows plain ground there.
So this pack deliberately does NOT preserve all original opaque pixels: every
pixel OUTSIDE the mask (west forest/fence/barrel band, south scenery, the 38
tree_wood-owned transparent corner px rows 267..270) stays byte-identical
INCLUDING its transparency; pixels inside the mask come from the candidate.

Invariants asserted on every run:
- hole count == manifest owned_pixels; interior opaque count == pinned 12,735;
- every non-mask pixel of the context crop byte-identical in the packed crop;
- asset exactly 327x253 == approved outer rect; every replaced pixel opaque;
- asset preserves ground transparency outside the mask (pinned 38 px).

Run from the repository root in the approved portable environment:

    python3 -I tools/art_pipeline/p1_town_modular_v01/build_loadout_backing.py
"""

from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

REPO_ROOT = Path(__file__).resolve().parents[3]
LAYERS = REPO_ROOT / "content/rooms/town/layers"
CANDIDATE = REPO_ROOT / "docs/art-production/p1-town-modular-v01/sources/loadout_backing_candidate_01.png"
CANDIDATE_SHA = "816adb239478fc2aaf60efda091671817e763c31729b791876a2b2c6ea916a56"
CANDIDATE_SIZE = (1408, 1117)
ASSET_OUT = REPO_ROOT / "art/production/p1/town_modular_v01/loadout_backing_v01.png"
EVIDENCE = REPO_ROOT / "build/current/p1-town-modular-v01/loadout-backing-v01"
SLICE_ID = "loadout"
MARGIN = 28        # context ring around the slice rect (matches inspect_regions.py)
PATCH_PAD = 12     # asset rect = slice rect grown by this pad on all sides
APPROVED_OUTER = (478, 18, 805, 271)   # parent-approved outer extent (world)
INTERIOR_RECT = (620, 125, 793, 259)   # obsolete interior props region (world)
INTERIOR_OPAQUE_EXPECTED = 12_735      # measured against the pinned ground
TREE_WOOD_PRESERVED = 38               # transparent px kept inside the asset rect
MAX_OFFSET = 4
# Review-only v01 placement (d19 acceptance): position (583, 56.0625), canvas 256x224.
V01_POS = (583, 56.0625)
V01_CANVAS = (256, 224)
V01_COMMON = REPO_ROOT / "art/production/p1/town_modular_v01/loadout_common.png"
V01_UPPER = REPO_ROOT / "art/production/p1/town_modular_v01/loadout_upper_full.png"
T11 = (666.5657, 257.2501)
TAREN = (719.4, 255.0)
FACILITY = (711, 284.0625)
ENVELOPE = (641, 184.06, 781, 240.06)
FOOTPRINT = (647, 190.06, 775, 234.06)
WHITE, YELLOW, CYAN, MAGENTA, RED, GREEN = ((255, 255, 255, 255), (255, 210, 0, 255), (0, 255, 255, 255),
                                            (255, 0, 255, 255), (255, 70, 70, 255), (90, 255, 90, 255))


class BuildError(ValueError):
    """Raised when a pinned input or output invariant is violated."""


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def font(size: int):
    return ImageFont.load_default(size=size)


def rgb_distance(a, b) -> int:
    return abs(a[0] - b[0]) + abs(a[1] - b[1]) + abs(a[2] - b[2])


def sample(candidate_px, candidate_size: tuple[int, int], num: int, den: int, dx: int, dy: int, x: int, y: int):
    """Integer nearest sampling of ONE uniform scale num/den with offset."""
    sx = min(candidate_size[0] - 1, max(0, (x + dx) * num // den))
    sy = min(candidate_size[1] - 1, max(0, (y + dy) * num // den))
    return candidate_px[sx, sy]


def in_world(world, rect) -> bool:
    return rect[0] <= world[0] < rect[2] and rect[1] <= world[1] < rect[3]


def main() -> int:
    try:
        manifest = json.loads((LAYERS / "manifest.json").read_text())
        entry = next((e for e in manifest["native"] if e["id"] == SLICE_ID), None)
        if entry is None:
            raise BuildError(f"slice {SLICE_ID} missing from layers manifest")
        rect = entry["crop"]  # x, y, w, h (world)
        slice_rect = (rect[0], rect[1], rect[0] + rect[2], rect[1] + rect[3])
        patch_rect = (slice_rect[0] - PATCH_PAD, slice_rect[1] - PATCH_PAD,
                      slice_rect[2] + PATCH_PAD, slice_rect[3] + PATCH_PAD)
        if patch_rect != APPROVED_OUTER:
            raise BuildError(f"derived patch rect {patch_rect} != approved outer extent {APPROVED_OUTER}")
        crop_origin = (slice_rect[0] - MARGIN, slice_rect[1] - MARGIN)
        crop_size = (slice_rect[2] - slice_rect[0] + 2 * MARGIN, slice_rect[3] - slice_rect[1] + 2 * MARGIN)
        ground_path = REPO_ROOT / str(manifest["ground"]["path"]).removeprefix("res://")
        ground_sha = sha256_file(ground_path)
        if ground_sha != manifest["ground"]["sha256"]:
            raise BuildError("ground.png sha256 does not match the layers manifest")
        candidate_sha = sha256_file(CANDIDATE)
        if candidate_sha != CANDIDATE_SHA:
            raise BuildError(f"candidate sha256 {candidate_sha} != pinned {CANDIDATE_SHA}")
        ground = Image.open(ground_path).convert("RGBA")
        if ground.size != tuple(manifest["world_size"]):
            raise BuildError(f"ground size {ground.size} != manifest world {manifest['world_size']}")
        candidate = Image.open(CANDIDATE).convert("RGB")
        if candidate.size != CANDIDATE_SIZE:
            raise BuildError(f"candidate size {candidate.size} != pinned {CANDIDATE_SIZE}")
        # ONE uniform rational scale: candidate height / context crop height.
        num, den = candidate.height, crop_size[1]
        crop = ground.crop((crop_origin[0], crop_origin[1], crop_origin[0] + crop_size[0], crop_origin[1] + crop_size[1]))
        crop_px = crop.load()
        cand_px = candidate.load()
        # Replacement mask: ownership hole + obsolete interior rect (opaque px only).
        hole: list[tuple[int, int]] = []
        interior_opaque: list[tuple[int, int]] = []
        for y in range(crop_size[1]):
            for x in range(crop_size[0]):
                world = (x + crop_origin[0], y + crop_origin[1])
                if in_world(world, slice_rect) and crop_px[x, y][3] < 255:
                    hole.append((x, y))
                elif in_world(world, INTERIOR_RECT) and crop_px[x, y][3] == 255:
                    interior_opaque.append((x, y))
        if len(hole) != entry["owned_pixels"]:
            raise BuildError(f"hole count {len(hole)} != manifest owned_pixels {entry['owned_pixels']}")
        if len(interior_opaque) != INTERIOR_OPAQUE_EXPECTED:
            raise BuildError(f"interior opaque count {len(interior_opaque)} != pinned {INTERIOR_OPAQUE_EXPECTED}")
        mask = set(hole) | set(interior_opaque)
        # Registration ring: opaque context pixels OUTSIDE the replacement mask.
        ring = [(x, y) for y in range(crop_size[1]) for x in range(crop_size[0])
                if crop_px[x, y][3] == 255 and (x, y) not in mask]
        best_offset, best_distance = None, None
        for dy in range(-MAX_OFFSET, MAX_OFFSET + 1):
            for dx in range(-MAX_OFFSET, MAX_OFFSET + 1):
                total = 0
                for x, y in ring:
                    total += rgb_distance(sample(cand_px, candidate.size, num, den, dx, dy, x, y), crop_px[x, y][:3])
                mean = total / max(1, len(ring))
                if best_distance is None or mean < best_distance:
                    best_offset, best_distance = (dx, dy), mean
        dx, dy = best_offset
        # Pack: mask px from the candidate, everything else byte-identical.
        packed = crop.copy()
        packed_px = packed.load()
        for x, y in mask:
            r, g, b = sample(cand_px, candidate.size, num, den, dx, dy, x, y)
            packed_px[x, y] = (r, g, b, 255)
        changed_outside = sum(1 for y in range(crop_size[1]) for x in range(crop_size[0])
                              if (x, y) not in mask and packed_px[x, y] != crop_px[x, y])
        if changed_outside:
            raise BuildError(f"{changed_outside} pixels outside the replacement mask changed")
        # Seam rims: replaced px adjacent to a preserved opaque px (quality metric, not an invariant).
        rim: dict[str, list[int]] = {"hole": [], "interior": []}
        for x, y in mask:
            kind = "interior" if crop_px[x, y][3] == 255 else "hole"
            for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                if 0 <= nx < crop_size[0] and 0 <= ny < crop_size[1] and crop_px[nx, ny][3] == 255 and (nx, ny) not in mask:
                    rim[kind].append(rgb_distance(packed_px[x, y], crop_px[nx, ny]))
                    break
        # Asset: exact approved outer rect; replaced px opaque, preserved px byte-exact.
        local = (patch_rect[0] - crop_origin[0], patch_rect[1] - crop_origin[1],
                 patch_rect[2] - crop_origin[0], patch_rect[3] - crop_origin[1])
        asset = packed.crop(local)
        asset_px = asset.load()
        if asset.size != (patch_rect[2] - patch_rect[0], patch_rect[3] - patch_rect[1]):
            raise BuildError(f"asset size {asset.size} != patch rect size")
        replaced_not_opaque = asset_opaque = asset_transparent = 0
        asset_differs = transparent_kept = 0
        for y in range(asset.height):
            for x in range(asset.width):
                world = (x + patch_rect[0], y + patch_rect[1])
                gpx = ground.getpixel(world)
                local_crop = (x + local[0], y + local[1])
                if local_crop in mask:
                    replaced_not_opaque += asset_px[x, y][3] < 255
                else:
                    if asset_px[x, y] != gpx:
                        asset_differs += 1
                    if gpx[3] < 255:
                        transparent_kept += 1
                asset_transparent += asset_px[x, y][3] < 255
                asset_opaque += asset_px[x, y][3] == 255
        if replaced_not_opaque:
            raise BuildError(f"{replaced_not_opaque} replaced pixels not opaque")
        if asset_differs:
            raise BuildError(f"{asset_differs} preserved pixels differ from ground inside the asset")
        if asset_transparent != TREE_WOOD_PRESERVED:
            raise BuildError(f"asset transparent px {asset_transparent} != preserved expectation {TREE_WOOD_PRESERVED}")
        ASSET_OUT.parent.mkdir(parents=True, exist_ok=True)
        asset.save(ASSET_OUT, format="PNG", optimize=False)
        # --- Evidence -------------------------------------------------------
        EVIDENCE.mkdir(parents=True, exist_ok=True)
        for scale, suffix in ((1, "native"), (2, "2x")):
            width = crop.width * scale
            sheet = Image.new("RGBA", (width * 3 + 8 * scale, crop.height * scale + 18 * scale), (18, 18, 22, 255))
            parts = ((crop, "context ground (hole)"), (packed, "uniform-scale packed (mask replaced)"),
                     (asset, f"asset patch {asset.width}x{asset.height}"))
            for index, (part, label) in enumerate(parts):
                big = part.resize((part.width * scale, part.height * scale), Image.Resampling.NEAREST) if scale > 1 else part
                sheet.paste(big, (index * (width + 8 * scale), 18 * scale), big)
            draw = ImageDraw.Draw(sheet)
            for index, (_, label) in enumerate(parts):
                draw.text((index * (width + 8 * scale) + 4, 4 * scale), label, font=font(11), fill=WHITE)
            draw.text((4, sheet.height - 13 * scale),
                      f"scale {num}/{den} uniform, offset {best_offset}, mask {len(mask)} px "
                      f"(hole {len(hole)} + interior {len(interior_opaque)}), residue: src cols >={(crop_size[0] - 1) * num // den + 1}, rows >={(crop_size[1] - 1) * num // den + 1} unsampled",
                      font=font(10), fill=YELLOW)
            sheet.save(EVIDENCE / f"review_sheet_{suffix}.png", format="PNG", optimize=False)
        # Mask overlay at 2x: hole magenta, interior opaque cyan, rects outlined.
        overlay = crop.resize((crop.width * 2, crop.height * 2), Image.Resampling.NEAREST).convert("RGBA")
        op = overlay.load()
        for x, y in hole:
            r, g, b = op[x * 2, y * 2][:3]
            op[x * 2, y * 2] = ((r + 2 * MAGENTA[0]) // 3, (g + 2 * MAGENTA[1]) // 3, (b + 2 * MAGENTA[2]) // 3, 255)
        for x, y in interior_opaque:
            r, g, b = op[x * 2, y * 2][:3]
            op[x * 2, y * 2] = ((r + 2 * CYAN[0]) // 3, (g + 2 * CYAN[1]) // 3, (b + 2 * CYAN[2]) // 3, 255)
        draw = ImageDraw.Draw(overlay)
        def rect2x(wrect, color, width=2):
            draw.rectangle(((wrect[0] - crop_origin[0]) * 2, (wrect[1] - crop_origin[1]) * 2,
                            (wrect[2] - crop_origin[0]) * 2 - 1, (wrect[3] - crop_origin[1]) * 2 - 1),
                           outline=color, width=width)
        rect2x(slice_rect, WHITE, 1)
        rect2x(INTERIOR_RECT, CYAN, 2)
        rect2x(patch_rect, YELLOW, 2)
        draw.text((8, 8), "replacement mask 2x — magenta: ownership hole 42,294 px; cyan tint: obsolete interior props 12,735 px", font=font(13), fill=WHITE)
        draw.text((8, 28), f"white: slice rect; cyan: interior rect; yellow: asset rect {APPROVED_OUTER}", font=font(13), fill=WHITE)
        overlay.save(EVIDENCE / "mask_overlay_2x.png", format="PNG", optimize=False)
        # Composite review: window extended east so the v01 canvas is fully visible.
        win = (crop_origin[0], crop_origin[1], crop_origin[0] + crop_size[0] + 22, crop_origin[1] + crop_size[1])
        base = ground.crop(win).convert("RGBA")
        base.paste(packed, (0, 0), packed)
        common = Image.open(V01_COMMON).convert("RGBA")
        upper = Image.open(V01_UPPER).convert("RGBA")
        if common.size != V01_CANVAS or upper.size != V01_CANVAS:
            raise BuildError(f"v01 art canvas sizes {common.size}/{upper.size} != {V01_CANVAS}")
        paste_x = round(V01_POS[0] - win[0])
        paste_y = round(V01_POS[1] - win[1])  # 56.0625 -> 56, review-only rounding disclosed
        base.paste(common, (paste_x, paste_y), common)
        base.paste(upper, (paste_x, paste_y), upper)
        for scale, suffix in ((1, "native"), (2, "2x")):
            comp = base.resize((base.width * scale, base.height * scale), Image.Resampling.NEAREST) if scale > 1 else base.copy()
            draw = ImageDraw.Draw(comp)
            def pt(world):
                return ((world[0] - win[0]) * scale, (world[1] - win[1]) * scale)
            def wrect(wrect, color, width=1):
                x0, y0 = pt((wrect[0], wrect[1]))
                x1, y1 = pt((wrect[2], wrect[3]))
                draw.rectangle((x0, y0, x1 - 1, y1 - 1), outline=color, width=width)
            wrect(patch_rect, MAGENTA, 2)
            wrect(slice_rect, WHITE, 1)
            wrect(ENVELOPE, YELLOW, 1)
            wrect(FOOTPRINT, CYAN, 1)
            for world, color, label, dy_text in ((T11, RED, "T11 (666.57,257.25) legal+readable", -30),
                                                 (TAREN, GREEN, "Taren (719.4,255.0)", 14),
                                                 (FACILITY, YELLOW, "facility/socket (711,284.06)", 10)):
                cx, cy = pt(world)
                draw.line((cx - 7, cy, cx + 7, cy), fill=color, width=2)
                draw.line((cx, cy - 7, cx, cy + 7), fill=color, width=2)
                draw.ellipse((cx - 7, cy - 7, cx + 7, cy + 7), outline=color, width=1)
                draw.text((cx + 10, cy + dy_text), label, font=font(12 if scale > 1 else 10), fill=color)
            draw.text((8, 6), f"REVIEW ONLY composite — packed backing + v01 loadout pasted at {V01_POS} "
                              f"(paste rounded to int; magenta asset rect, white old slice, yellow envelope, cyan footprint)",
                      font=font(12 if scale > 1 else 10), fill=WHITE)
            comp.save(EVIDENCE / f"composite_v01_{suffix}.png", format="PNG", optimize=False)
        report = {"slice": {"id": SLICE_ID, "world_rect(slice)": list(slice_rect), "owned_manifest": entry["owned_pixels"],
                            "asset_world_rect": list(patch_rect), "approved_outer_match": True},
                  "inputs": {"ground_sha256": ground_sha, "candidate_sha256": candidate_sha,
                             "candidate_size": list(candidate.size), "context_crop_origin": list(crop_origin),
                             "context_crop_size": list(crop_size)},
                  "transform": {"scale_rational": f"{num}/{den}", "scale_value": round(num / den, 6),
                                "axes": "both", "sampler": "integer nearest (x*num)//den",
                                "origin": [0, 0], "registration_offset": list(best_offset),
                                "ring_mean_rgb_distance": round(best_distance, 2), "ring_px": len(ring),
                                "ring_scope": "opaque context px OUTSIDE replacement mask",
                                "residue_unsampled_source_columns": [((crop_size[0] - 1) * num // den) + 1, candidate.width - 1],
                                "residue_unsampled_source_rows": [((crop_size[1] - 1) * num // den) + 1, candidate.height - 1]},
                  "replacement_mask": {"hole_px": len(hole), "interior_opaque_px": len(interior_opaque),
                                       "interior_rect_world": list(INTERIOR_RECT), "total_px": len(mask),
                                       "authorization": "root: interior repaint allowed, old building removed"},
                  "seam": {kind: {"rim_px": len(v), "mean_rgb_distance": round(sum(v) / max(1, len(v)), 1),
                                 "max_rgb_distance": max(v, default=0)} for kind, v in rim.items()},
                  "invariants": {"outside_mask_changed_crop": changed_outside,
                                 "asset_size": list(asset.size), "asset_opaque_px": asset_opaque,
                                 "asset_transparent_px_preserved": asset_transparent,
                                 "asset_preserved_px_differ": asset_differs,
                                 "replaced_px_not_opaque": replaced_not_opaque,
                                 "hole_equals_manifest_owned": len(hole) == entry["owned_pixels"]},
                  "outputs": {"asset": str(ASSET_OUT.relative_to(REPO_ROOT)), "asset_sha256": sha256_file(ASSET_OUT),
                              "evidence_dir": str(EVIDENCE.relative_to(REPO_ROOT)),
                              "evidence": ["review_sheet_native.png", "review_sheet_2x.png", "mask_overlay_2x.png",
                                           "composite_v01_native.png", "composite_v01_2x.png"]}}
        (EVIDENCE / "report.json").write_text(json.dumps(report, indent=2, sort_keys=True))
        print(json.dumps({"asset": report["outputs"]["asset"], "asset_sha256": report["outputs"]["asset_sha256"],
                          "transform": report["transform"], "replacement_mask": report["replacement_mask"],
                          "invariants": report["invariants"]}, sort_keys=True))
    except (OSError, ValueError, KeyError, StopIteration) as exc:
        import traceback
        traceback.print_exc()
        print(f"LOADOUT BACKING FAILED: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
