#!/usr/bin/env python3
"""Pine sample guide outputs for the root image-generation stage.

Produces FIXED-format calibration guides and one review sheet for the first
independent pine package (PINE_SPEC.md). No source art is edited and nothing
here is generated artwork: guide geometry is author-defined spec geometry
rasterized in code, exactly like the Loadout roof/stubs guides in
make_guides.py. The generator is never assumed pixel-exact; every guide
region below is a calibration target that the later pack step measures and
records deviations against.

Stage 1 (always, no packed art needed):
1. pine_common_guide_96x144.png — the exact 96x144 transparent canvas with
   the flat guide flats for the common layer only: trunk column, root band,
   two low branch-stub pairs, and nothing above the upper stub pair (the
   canopy region stays fully transparent; it is a separate later layer).
   This is the reference for chained request A (common).
2. pine_canopy_silhouette_96x144.png — the reserved canopy region (disc
   center (48,48) radius 43) in one flat tone. Diagnostic input for the
   later canopy guide composition, never a request reference on its own.
3. pine_guide_review_4x.png — each produced layer enlarged 4x by
   nearest-neighbour over neutral/white/black plus a fourth marked panel
   overlaying envelope/footprint/anchor/reserved-disc positions.

Stage 2 (only once the packed pine common exists at --common):
4. pine_canopy_guide_96x144.png — the accepted common with the canopy
   silhouette composited ON TOP (the canopy owns its region, including the
   trunk top it covers). This is the reference for chained request B
   (upper/canopy); until the common exists the tool prints a deferral note
   and writes no canopy guide.

Stage 3 (only once the packed upper candidate exists at its pinned path):
5. pine_common_v02_guide_96x144.png — the redesign reference for the
   compact solid base (PINE_SPEC.md policy note): the pinned packed upper
   candidate with every opaque pixel at rows y <= 98 flattened to the
   canopy guide tone (that flat shape marks the crown mass to REMOVE) and
   everything from y99 down kept exactly as packed (the finished trunk,
   roots and feet the request must preserve). Reference for the proposed
   common-v02 edit (request C); until the packed candidate exists the tool
   prints a deferral note and writes no v02 guide.

Run from the repository root in the approved portable environment:

    python3 -I tools/art_pipeline/p1_town_modular_v01/make_pine_guides.py \
        --common art/production/p1/town_modular_v01/pine_common.png \
        --output build/current/p1-town-modular-v01/pine-checkpoint-1
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw

REPO_ROOT = Path(__file__).resolve().parents[3]

# The parent-accepted pine common (PINE_SPEC.md, 2026-10-22, "accepted as
# drawn"); stage 2 composites the canopy guide from exactly these bytes.
PINNED_COMMON_SHA256 = "7aa70586ccd908d50ce97451534ff8f1f37c433ba3b9e72e13a7c2f8f50333a2"
# The packed upper candidate proposal (build_pine_upper.py, review only);
# stage 3 derives the v02 base guide from exactly these bytes.
UPPER_PACK = {
    "path": "build/current/p1-town-modular-v01/pine-checkpoint-1/pine_upper_candidate_packed_96x144.png",
    "sha256": "e32faebbb0dd41d7a2403ff2d8091b19c07ffe4e54e30ef87c9e2e5dfefb43cd",
}
V02_BASE_TOP = 99  # first kept row; every opaque pixel at y <= 98 flattens

CANVAS = (96, 144)
REVIEW_SCALE = 4
REVIEW_BACKGROUNDS = ((128, 128, 128, 255), (255, 255, 255, 255), (0, 0, 0, 255))
# Geometry contract fixed by the parent delegation (greybox parity,
# tools/modular_town_preview.gd _tree()): canvas 96x144, anchors (48,128),
# footprint circle (48,128) r10, movement envelope circle (48,128) r14
# (final; the resolver adds the hero radius itself), placements (480,210)
# and (650,300). Art regions below are author-defined guide calibration.
ANCHOR = (48, 128)
FOOTPRINT = {"center": (48.0, 128.0), "radius": 10.0}
ENVELOPE = {"center": (48.0, 128.0), "radius": 14.0}
CANOPY_DISC = {"center": (48.0, 48.0), "radius": 43.0}
# Flat guide regions as (x, y, w, h); pixel extent x..x+w-1, y..y+h-1.
TRUNK_RECT = (42, 56, 13, 83)          # x42..54, y56..138, symmetric about x48
ROOT_RECT = (36, 130, 25, 11)          # x36..60, y130..140, feet contact band
STUB_PAIRS = (                         # both pairs fully behind the canopy disc
    ((34, 58, 11, 6), (52, 58, 11, 6)),    # upper short pair y58..63
    ((28, 68, 19, 6), (50, 68, 19, 6)),    # lower long pair y68..73
)
# Guide flats reuse the Loadout guide palette family (make_guides.py).
TRUNK_COLOR = (136, 112, 82, 255)      # #887052 timber structure
ROOT_COLOR = (160, 119, 93, 255)       # #a0775d light timber
STUB_COLOR = (129, 88, 78, 255)        # #81584e dark timber
CANOPY_COLOR = (79, 110, 90, 255)      # #4f6e5a greybox canopy tone
MARK_COLORS = {
    "envelope": (255, 0, 255, 255),    # magenta, r14 circle at the anchor
    "footprint": (0, 255, 255, 255),   # cyan, r10 circle at the anchor
    "anchor": (255, 255, 0, 255),      # yellow cross at (48,128)
    "disc": (255, 255, 255, 255),      # white, reserved canopy disc edge
}
OUTPUTS = (
    "pine_common_guide_96x144.png",
    "pine_canopy_silhouette_96x144.png",
    "pine_canopy_guide_96x144.png",
    "pine_common_v02_guide_96x144.png",
    "pine_guide_review_4x.png",
)


class GuideError(ValueError):
    """Raised when an input or output contract is violated."""


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


def fill_rect(canvas: Image.Image, rect: tuple[int, int, int, int], color: tuple[int, int, int, int]) -> None:
    x, y, w, h = rect
    pixels = canvas.load()
    for cy in range(y, y + h):
        for cx in range(x, x + w):
            if not (0 <= cx < CANVAS[0] and 0 <= cy < CANVAS[1]):
                raise GuideError(f"guide rect {rect} leaves the {CANVAS} canvas")
            pixels[cx, cy] = color


def fill_disc(canvas: Image.Image, center: tuple[float, float], radius: float, color: tuple[int, int, int, int]) -> None:
    """Pixel filled iff its center (x+0.5, y+0.5) lies within radius."""
    pixels = canvas.load()
    cx0, cy0 = center
    for y in range(int(cy0 - radius) - 1, int(cy0 + radius) + 2):
        for x in range(int(cx0 - radius) - 1, int(cx0 + radius) + 2):
            if not (0 <= x < CANVAS[0] and 0 <= y < CANVAS[1]):
                continue
            dx = x + 0.5 - cx0
            dy = y + 0.5 - cy0
            if dx * dx + dy * dy <= radius * radius:
                pixels[x, y] = color


def expected_common_pixels() -> dict[tuple[int, int], tuple[int, int, int, int]]:
    expected: dict[tuple[int, int], tuple[int, int, int, int]] = {}
    for x, y, w, h in [TRUNK_RECT, ROOT_RECT] + [rect for pair in STUB_PAIRS for rect in pair]:
        color = TRUNK_COLOR if (x, y, w, h) == TRUNK_RECT else ROOT_COLOR if (x, y, w, h) == ROOT_RECT else STUB_COLOR
        for cy in range(y, y + h):
            for cx in range(x, x + w):
                expected[(cx, cy)] = color
    return expected


def expected_disc_pixels() -> set[tuple[int, int]]:
    cx0, cy0 = CANOPY_DISC["center"]
    radius = CANOPY_DISC["radius"]
    pixels: set[tuple[int, int]] = set()
    for y in range(int(cy0 - radius) - 1, int(cy0 + radius) + 2):
        for x in range(int(cx0 - radius) - 1, int(cx0 + radius) + 2):
            if not (0 <= x < CANVAS[0] and 0 <= y < CANVAS[1]):
                continue
            dx = x + 0.5 - cx0
            dy = y + 0.5 - cy0
            if dx * dx + dy * dy <= radius * radius:
                pixels.add((x, y))
    return pixels


def make_common_guide() -> Image.Image:
    guide = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    fill_rect(guide, TRUNK_RECT, TRUNK_COLOR)
    fill_rect(guide, ROOT_RECT, ROOT_COLOR)
    for pair in STUB_PAIRS:
        for rect in pair:
            fill_rect(guide, rect, STUB_COLOR)
    return guide


def make_canopy_silhouette() -> Image.Image:
    silhouette = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    fill_disc(silhouette, CANOPY_DISC["center"], CANOPY_DISC["radius"], CANOPY_COLOR)
    return silhouette


def load_common(path: Path | None) -> Image.Image | None:
    if path is None or not path.is_file():
        return None
    digest = sha256_file(path)
    if digest != PINNED_COMMON_SHA256:
        raise GuideError(
            f"pine common layer sha256 {digest} != accepted {PINNED_COMMON_SHA256} "
            "(rebuild via build_pine.py or update the pin after a new acceptance)"
        )
    image = Image.open(path).convert("RGBA")
    if image.size != CANVAS:
        raise GuideError(f"pine common layer is {image.size}, expected {CANVAS}")
    histogram = image.getchannel("A").histogram()
    if sum(histogram[1:255]) != 0:
        raise GuideError("pine common layer must have binary alpha (run the pack step first)")
    return image


def make_canopy_guide(common: Image.Image, silhouette: Image.Image) -> Image.Image:
    guide = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    guide.alpha_composite(common)
    guide.alpha_composite(silhouette)  # the canopy guide region owns the trunk top it covers
    return guide


def load_upper_pack() -> Image.Image | None:
    path = REPO_ROOT / UPPER_PACK["path"]
    if not path.is_file():
        return None
    digest = sha256_file(path)
    if digest != UPPER_PACK["sha256"]:
        raise GuideError(
            f"packed upper candidate sha256 {digest} != pinned {UPPER_PACK['sha256']} "
            "(rebuild via build_pine_upper.py or update the pin after a new proposal)"
        )
    image = Image.open(path).convert("RGBA")
    if image.size != CANVAS:
        raise GuideError(f"packed upper candidate is {image.size}, expected {CANVAS}")
    if sum(image.getchannel("A").histogram()[1:255]) != 0:
        raise GuideError("packed upper candidate must have binary alpha (run build_pine_upper.py first)")
    return image


def make_v02_guide(upper_pack: Image.Image) -> Image.Image:
    """Compact-base redesign reference: flat crown mass above, kept art below."""
    guide = upper_pack.copy()
    pixels = guide.load()
    for y in range(0, V02_BASE_TOP):
        for x in range(CANVAS[0]):
            r, g, b, a = pixels[x, y]
            if a == 255:
                pixels[x, y] = CANOPY_COLOR
    return guide


def draw_marks(panel: Image.Image) -> None:
    """Overlay envelope/footprint/anchor/reserved-disc marks on one 4x panel."""
    draw = ImageDraw.Draw(panel)
    scale = REVIEW_SCALE

    def ring(center: tuple[float, float], radius: float, color: tuple[int, int, int, int]) -> None:
        cx = center[0] * scale
        cy = center[1] * scale
        r = radius * scale
        draw.ellipse((cx - r, cy - r, cx + r, cy + r), outline=color, width=2)

    ring(ENVELOPE["center"], ENVELOPE["radius"], MARK_COLORS["envelope"])
    ring(FOOTPRINT["center"], FOOTPRINT["radius"], MARK_COLORS["footprint"])
    ring(CANOPY_DISC["center"], CANOPY_DISC["radius"], MARK_COLORS["disc"])
    ax, ay = ANCHOR[0] * scale, ANCHOR[1] * scale
    color = MARK_COLORS["anchor"]
    draw.line((ax - 10, ay, ax + 10, ay), fill=color, width=2)
    draw.line((ax, ay - 10, ax, ay + 10), fill=color, width=2)


def make_review_sheet(layers: list[tuple[str, Image.Image]]) -> Image.Image:
    panel_w, panel_h = CANVAS[0] * REVIEW_SCALE, CANVAS[1] * REVIEW_SCALE
    sheet = Image.new("RGBA", (panel_w * 4, panel_h * len(layers)), REVIEW_BACKGROUNDS[0])
    for row, (_name, layer) in enumerate(layers):
        big = layer.resize((panel_w, panel_h), Image.Resampling.NEAREST)
        for column, background in enumerate(REVIEW_BACKGROUNDS):
            panel = Image.new("RGBA", big.size, background)
            panel.alpha_composite(big)
            sheet.paste(panel, (column * panel_w, row * panel_h))
        marked = Image.new("RGBA", big.size, REVIEW_BACKGROUNDS[0])
        marked.alpha_composite(big)
        draw_marks(marked)
        sheet.paste(marked, (3 * panel_w, row * panel_h))
    return sheet


def validate_common_guide(path: Path) -> str:
    image = Image.open(path).convert("RGBA")
    if image.size != CANVAS:
        raise GuideError(f"{path.name} is {image.size}, expected {CANVAS}")
    if sum(image.getchannel("A").histogram()[1:255]) != 0:
        raise GuideError(f"{path.name} must have binary alpha")
    pixels = image.load()
    expected = expected_common_pixels()
    drawn = {(x, y): pixels[x, y] for y in range(CANVAS[1]) for x in range(CANVAS[0]) if pixels[x, y][3] == 255}
    if drawn != expected:
        extra = sorted(set(drawn) - set(expected))[:8]
        missing = sorted(set(expected) - set(drawn))[:8]
        raise GuideError(f"{path.name} geometry mismatch: extra {extra}, missing {missing}")
    top = min(y for _, y in expected)
    bottom = max(y for _, y in expected)
    if top != TRUNK_RECT[1] or bottom != ROOT_RECT[1] + ROOT_RECT[3] - 1:
        raise GuideError(f"{path.name} vertical extent y{top}..y{bottom} outside the spec bands")
    return f"PASS common guide exact union of trunk/root/stub flats, extent y{top}..y{bottom}, nothing above y{top}"


def validate_disc_silhouette(path: Path) -> str:
    image = Image.open(path).convert("RGBA")
    if image.size != CANVAS:
        raise GuideError(f"{path.name} is {image.size}, expected {CANVAS}")
    pixels = image.load()
    drawn = {(x, y) for y in range(CANVAS[1]) for x in range(CANVAS[0]) if pixels[x, y][3] == 255}
    expected = expected_disc_pixels()
    if drawn != expected:
        extra = sorted(drawn - expected)[:8]
        missing = sorted(expected - drawn)[:8]
        raise GuideError(f"{path.name} disc mismatch: extra {extra}, missing {missing}")
    wrong_colors = {pixels[x, y] for x, y in drawn if pixels[x, y] != CANOPY_COLOR}
    if wrong_colors:
        raise GuideError(f"{path.name} carries non-guide colors: {sorted(wrong_colors)[:4]}")
    rows = [y for x, y in drawn]
    return f"PASS canopy silhouette exact disc rasterization rows y{min(rows)}..y{max(rows)}"


def validate_canopy_guide(path: Path, common: Image.Image, silhouette: Image.Image) -> str:
    image = Image.open(path).convert("RGBA")
    if image.size != CANVAS:
        raise GuideError(f"{path.name} is {image.size}, expected {CANVAS}")
    pixels = image.load()
    guide = make_canopy_guide(common, silhouette)
    guide_pixels = guide.load()
    mismatch = [(x, y) for y in range(CANVAS[1]) for x in range(CANVAS[0]) if pixels[x, y] != guide_pixels[x, y]]
    if mismatch:
        raise GuideError(f"{path.name} differs from common+silhouette composite at {mismatch[:8]}")
    return "PASS canopy guide equals accepted common with silhouette composited on top"


def validate_v02_guide(path: Path, upper_pack: Image.Image) -> str:
    image = Image.open(path).convert("RGBA")
    if image.size != CANVAS:
        raise GuideError(f"{path.name} is {image.size}, expected {CANVAS}")
    if sum(image.getchannel("A").histogram()[1:255]) != 0:
        raise GuideError(f"{path.name} must have binary alpha")
    pixels = image.load()
    pack_pixels = upper_pack.load()
    bad_flat = [
        (x, y)
        for y in range(0, V02_BASE_TOP) for x in range(CANVAS[0])
        if pixels[x, y][3] == 255 and pixels[x, y] != CANOPY_COLOR
    ]
    if bad_flat:
        raise GuideError(f"{path.name} carries non-flat pixels above the base top at {bad_flat[:8]}")
    changed_kept = [
        (x, y)
        for y in range(V02_BASE_TOP, CANVAS[1]) for x in range(CANVAS[0])
        if pixels[x, y] != pack_pixels[x, y]
    ]
    if changed_kept:
        raise GuideError(f"{path.name} altered the kept base rows at {changed_kept[:8]}")
    rows = [y for y in range(CANVAS[1]) for x in range(CANVAS[0]) if pixels[x, y][3] == 255]
    return (
        f"PASS v02 guide: rows y{V02_BASE_TOP}..y137 kept pixel-exact from the pinned pack, "
        f"rows y{min(rows)}..y{V02_BASE_TOP - 1} flattened to the crown guide tone, extent y{min(rows)}..y{max(rows)}"
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--common", type=Path, default=REPO_ROOT / "art/production/p1/town_modular_v01/pine_common.png")
    parser.add_argument("--output", type=Path, default=REPO_ROOT / "build/current/p1-town-modular-v01/pine-checkpoint-1")
    args = parser.parse_args(argv)
    try:
        common = load_common(args.common)
        silhouette = make_canopy_silhouette()
        layers: list[tuple[str, Image.Image]] = [("common guide", make_common_guide()), ("canopy silhouette", silhouette)]
        outputs: dict[str, Image.Image] = {
            "pine_common_guide_96x144.png": layers[0][1],
            "pine_canopy_silhouette_96x144.png": silhouette,
        }
        notes: list[str] = []
        if common is not None:
            canopy_guide = make_canopy_guide(common, silhouette)
            outputs["pine_canopy_guide_96x144.png"] = canopy_guide
            layers.append(("canopy guide", canopy_guide))
        else:
            notes.append(
                "canopy guide deferred: packed pine common not found at "
                f"{display_path(args.common)} (run and approve request A, then pack, then rerun)"
            )
        upper_pack = load_upper_pack()
        if upper_pack is not None:
            v02_guide = make_v02_guide(upper_pack)
            outputs["pine_common_v02_guide_96x144.png"] = v02_guide
            layers.append(("common v02 guide", v02_guide))
        else:
            notes.append(
                "v02 base guide deferred: packed upper candidate not found at "
                f"{display_path(REPO_ROOT / UPPER_PACK['path'])} (run build_pine_upper.py first)"
            )
        outputs["pine_guide_review_4x.png"] = make_review_sheet(layers)
        args.output.mkdir(parents=True, exist_ok=True)
        report = []
        for name, image in outputs.items():
            path = args.output / name
            image.save(path, format="PNG", optimize=False)
            report.append({"path": display_path(path), "sha256": sha256_file(path), "bytes": path.stat().st_size, "size": list(image.size)})
        checks = [
            validate_common_guide(args.output / "pine_common_guide_96x144.png"),
            validate_disc_silhouette(args.output / "pine_canopy_silhouette_96x144.png"),
        ]
        if common is not None:
            checks.append(validate_canopy_guide(args.output / "pine_canopy_guide_96x144.png", common, silhouette))
        if upper_pack is not None:
            checks.append(validate_v02_guide(args.output / "pine_common_v02_guide_96x144.png", upper_pack))
        print(json.dumps({
            "common_sha256": sha256_file(args.common) if common is not None else None,
            "upper_pack_sha256": sha256_file(REPO_ROOT / UPPER_PACK["path"]) if upper_pack is not None else None,
            "outputs": report,
            "checks": checks,
            "notes": notes,
        }, sort_keys=True))
        for line in checks:
            print(line)
        for line in notes:
            print(line)
        print("PINE GUIDES OK")
    except (GuideError, OSError, ValueError) as exc:
        print(f"PINE GUIDES FAILED: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
