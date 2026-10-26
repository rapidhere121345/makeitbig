#!/usr/bin/env python3
"""Build the tree_south backing plate art asset from root's generated candidate.

Deterministic promotion path (no engine, no runtime). Inputs are read-only and
hash-pinned; the only art output is the NEW asset
art/production/p1/town_modular_v01/tree_south_backing_v01.png covering the
exact inner world rect (735,643)-(871,795), fully opaque; review evidence is
written to the ignored build/current/p1-town-modular-v01/tree-backing-v01/.

Sources of truth (all verified, fail closed on mismatch):
- content/rooms/town/layers/manifest.json — tree_south slice rect, owned
  pixel count, ground sha256. Ownership = ground alpha<255 inside the slice
  rect (verified equal to owned_pixels; ONLY those pixels are filled).
- docs/art-production/p1-town-modular-v01/sources/tree_south_backing_candidate_01.png
  — root's generated plate, sha256-pinned.

Transform — ONE uniform rational scale, explicitly NOT an anisotropic resize:
scale = candidate_height / context_crop_height (1313/184 for the pinned raw),
applied to both axes by an integer nearest sampler
src = (x*num)//den, (y*num)//den with origin locked at (0,0) (the generation
request locked the whole canvas). Canvas residue is documented, not hidden:
source columns above the last sampled index and rows below it are never read.
Registration: exhaustive +-4 px offset fit of the transformed candidate
against the original opaque ring of the context crop.

Invariants asserted on every run:
- filled pixels == manifest owned_pixels (tree_south ownership only);
- every original opaque context pixel byte-identical in the packed crop;
- asset is exactly the patch rect, fully opaque, and its original-opaque
  pixels byte-identical to ground.

Run from the repository root in the approved portable environment:

    python3 -I tools/art_pipeline/p1_town_modular_v01/build_tree_backing.py
"""

from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

REPO_ROOT = Path(__file__).resolve().parents[3]
LAYERS = REPO_ROOT / "content/rooms/town/layers"
CANDIDATE = REPO_ROOT / "docs/art-production/p1-town-modular-v01/sources/tree_south_backing_candidate_01.png"
CANDIDATE_SHA = "89cce76f0f3120b238a1fa35f0ef5361546b5c02fa038af0d532f15ce4a39b3c"
CANDIDATE_SIZE = (1198, 1313)
ASSET_OUT = REPO_ROOT / "art/production/p1/town_modular_v01/tree_south_backing_v01.png"
EVIDENCE = REPO_ROOT / "build/current/p1-town-modular-v01/tree-backing-v01"
SLICE_ID = "tree_south"
MARGIN = 28      # context ring around the slice rect (matches inspect_regions.py)
PATCH_PAD = 12   # asset rect = slice rect grown by this pad on all sides
MAX_OFFSET = 4
WHITE, YELLOW, CYAN = (255, 255, 255, 255), (255, 210, 0, 255), (0, 255, 255, 255)


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
        opaque = [(x, y) for y in range(crop_size[1]) for x in range(crop_size[0]) if crop_px[x, y][3] == 255]
        best_offset, best_distance = None, None
        for dy in range(-MAX_OFFSET, MAX_OFFSET + 1):
            for dx in range(-MAX_OFFSET, MAX_OFFSET + 1):
                total = count = 0
                for x, y in opaque:
                    total += rgb_distance(sample(cand_px, candidate.size, num, den, dx, dy, x, y), crop_px[x, y][:3])
                    count += 1
                mean = total / max(1, count)
                if best_distance is None or mean < best_distance:
                    best_offset, best_distance = (dx, dy), mean
        dx, dy = best_offset
        # Ownership fill: ground-transparent pixels inside the slice rect only.
        fill = []
        for y in range(crop_size[1]):
            for x in range(crop_size[0]):
                world = (x + crop_origin[0], y + crop_origin[1])
                if crop_px[x, y][3] == 255:
                    continue
                if slice_rect[0] <= world[0] < slice_rect[2] and slice_rect[1] <= world[1] < slice_rect[3]:
                    fill.append((x, y))
        if len(fill) != entry["owned_pixels"]:
            raise BuildError(f"ownership count {len(fill)} != manifest owned_pixels {entry['owned_pixels']}")
        packed = crop.copy()
        packed_px = packed.load()
        for x, y in fill:
            r, g, b = sample(cand_px, candidate.size, num, den, dx, dy, x, y)
            packed_px[x, y] = (r, g, b, 255)
        changed = sum(1 for x, y in opaque if packed_px[x, y] != crop_px[x, y])
        if changed:
            raise BuildError(f"{changed} original opaque pixels changed")
        # Asset: exact patch rect, fully opaque, originals byte-identical.
        local = (patch_rect[0] - crop_origin[0], patch_rect[1] - crop_origin[1],
                 patch_rect[2] - crop_origin[0], patch_rect[3] - crop_origin[1])
        asset = packed.crop(local)
        asset_px = asset.load()
        if asset.size != (patch_rect[2] - patch_rect[0], patch_rect[3] - patch_rect[1]):
            raise BuildError(f"asset size {asset.size} != patch rect size")
        not_opaque = sum(1 for y in range(asset.height) for x in range(asset.width) if asset_px[x, y][3] < 255)
        if not_opaque:
            raise BuildError(f"asset not fully opaque: {not_opaque} px")
        asset_changed = 0
        for y in range(asset.height):
            for x in range(asset.width):
                world = (x + patch_rect[0], y + patch_rect[1])
                gpx = ground.getpixel(world)
                if gpx[3] == 255 and asset_px[x, y] != gpx:
                    asset_changed += 1
        if asset_changed:
            raise BuildError(f"{asset_changed} original opaque ground pixels changed inside the asset")
        ASSET_OUT.parent.mkdir(parents=True, exist_ok=True)
        asset.save(ASSET_OUT, format="PNG", optimize=False)
        # Review evidence: native + 2x sheets (before | packed | asset).
        EVIDENCE.mkdir(parents=True, exist_ok=True)
        for scale, suffix in ((1, "native"), (2, "2x")):
            width = crop.width * scale
            sheet = Image.new("RGBA", (width * 3 + 8 * scale, crop.height * scale + 18 * scale), (18, 18, 22, 255))
            parts = ((crop, "context ground (hole)"), (packed, "uniform-scale packed"), (asset, f"asset patch {asset.width}x{asset.height}"))
            for index, (part, label) in enumerate(parts):
                big = part.resize((part.width * scale, part.height * scale), Image.Resampling.NEAREST) if scale > 1 else part
                sheet.paste(big, (index * (width + 8 * scale), 18 * scale), big)
            draw = ImageDraw.Draw(sheet)
            for index, (_, label) in enumerate(parts):
                draw.text((index * (width + 8 * scale) + 4, 4 * scale), label, font=font(11), fill=WHITE)
            draw.text((4, sheet.height - 13 * scale),
                      f"scale {num}/{den} uniform, offset {best_offset}, fill {len(fill)} px, origin locked, residue: src cols >={(crop_size[0] - 1) * num // den + 1}, rows >={(crop_size[1] - 1) * num // den + 1} unsampled",
                      font=font(10), fill=YELLOW)
            sheet.save(EVIDENCE / f"review_sheet_{suffix}.png", format="PNG", optimize=False)
        report = {"slice": {"id": SLICE_ID, "world_rect(slice)": list(slice_rect), "owned_manifest": entry["owned_pixels"],
                            "asset_world_rect": list(patch_rect)},
                  "inputs": {"ground_sha256": ground_sha, "candidate_sha256": candidate_sha,
                             "candidate_size": list(candidate.size), "context_crop_origin": list(crop_origin),
                             "context_crop_size": list(crop_size)},
                  "transform": {"scale_rational": f"{num}/{den}", "scale_value": round(num / den, 6),
                                "axes": "both", "sampler": "integer nearest (x*num)//den",
                                "origin": [0, 0], "registration_offset": list(best_offset),
                                "ring_mean_rgb_distance": round(best_distance, 2), "ring_px": len(opaque),
                                "residue_unsampled_source_columns": [((crop_size[0] - 1) * num // den) + 1, candidate.width - 1],
                                "residue_unsampled_source_rows": [((crop_size[1] - 1) * num // den) + 1, candidate.height - 1]},
                  "fill": {"px": len(fill), "scope": "ground alpha<255 inside tree_south slice rect only"},
                  "invariants": {"original_opaque_changed_crop": changed, "asset_size": list(asset.size),
                                 "asset_fully_opaque": not_opaque == 0,
                                 "asset_original_opaque_changed": asset_changed,
                                 "fill_equals_manifest_owned": len(fill) == entry["owned_pixels"]},
                  "outputs": {"asset": str(ASSET_OUT.relative_to(REPO_ROOT)), "asset_sha256": sha256_file(ASSET_OUT),
                              "evidence_dir": str(EVIDENCE.relative_to(REPO_ROOT))}}
        (EVIDENCE / "report.json").write_text(json.dumps(report, indent=2, sort_keys=True))
        print(json.dumps({"asset": report["outputs"]["asset"], "asset_sha256": report["outputs"]["asset_sha256"],
                          "transform": report["transform"], "invariants": report["invariants"]}, sort_keys=True))
    except (OSError, ValueError, KeyError, StopIteration) as exc:
        import traceback
        traceback.print_exc()
        print(f"TREE BACKING FAILED: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
