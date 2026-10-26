#!/usr/bin/env python3
"""Deterministic whole-object packer for generated-world-v02 image sources.

Packs freshly generated raw sprites under
``docs/art-production/generated-world-v02/sources/`` into runtime art at
``art/production/p1/generated_world_v02/``. Every object asset produces an
aligned pair on one shared canvas and anchor:

- ``<id>_opaque.png``      occupied alpha 255, outside alpha 0
- ``<id>_transparent.png`` configured occupied alpha, identical RGB/canvas/geometry

Objects are whole entities; nothing is split into roof/base parts and no
shadow is added. The raw alpha contract is "object 250..254, background wash
below 240", so occupancy is decided by an explicit threshold (default 240,
overridable per asset via ``alpha_threshold`` in the config). Only raw
transparent padding is trimmed; the scaled object is mapped onto the full
configured canvas, bottom-aligned to the anchor.

Transform contract (integer arithmetic only, no resampling library calls):

- one uniform rational scale ``s = p/q`` (destination px per source px) shared
  by both axes: ``s = min(max_w / src_w, max_h / src_h)`` where
  ``max_w = canvas_w - 2*margin`` and ``max_h = anchor_y - margin``;
- destination size ``dw = ceil(src_w * s)``, ``dh = ceil(src_h * s)`` so the
  whole occupied source extent is always covered by the sampling window;
- nearest-neighbour sampling uses one rational step ``num/den = 1/s`` for
  both axes: ``src_i = ((2*i + 1) * num) // (2 * den)`` clamped to the source
  extent (centre-of-pixel sampling, the same formula the retired town modular pipeline used);
- placement ``dx = anchor_x - dw // 2``, ``dy = anchor_y - dh``: the occupied
  bottom bound (exclusive) sits at ``anchor_y`` and the window is centred on
  ``anchor_x`` (half-pixel left bias for odd widths).

The ground plate is a separate code path: fixed ``src_rect`` crop, no
resizing, fully opaque output.

The exported ``assets.json`` is rebuilt on every run. ``--available`` packs
every configured asset whose raw source exists; ``--asset NAME`` packs only
the named asset and carries over still-valid previous entries (raw hash,
output files and recorded output hashes all verified). Missing raws are
reported as ``pending`` and never claimed complete; a previously packed entry
whose raw or outputs changed is reported ``stale`` with its fields retained.

Run from the repository root in the approved portable environment:

    source /data/claude/workspace/.tools/make-it-big/portable-cpu/env.sh
    source scripts/project_env.sh
    python3 -I -m unittest discover -s tools/art_pipeline/generated_world_v02/tests
    python3 -I tools/art_pipeline/generated_world_v02/pack.py --available
"""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import sys
from collections import deque
from fractions import Fraction
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))  # art_pipeline/common.py
import common  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parents[3]
DEFAULT_CONFIG = Path(__file__).resolve().parent / "packing_config.json"
MANIFEST_NAME = "assets.json"

PNG_SAVE_ARGS = {"format": "PNG", "optimize": False}


class BuildError(ValueError):
    """Raised when the source, transform, or output contract is violated."""


# ---------------------------------------------------------------------------
# Small deterministic helpers


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


sha256_file = common.sha256_file
display_path = common.display_path


def res_path(output_dir: str, filename: str) -> str:
    return f"res://{output_dir}/{filename}"


def png_bytes(image: Image.Image) -> bytes:
    """Deterministic PNG encoding: fixed encoder args, no metadata chunks."""
    handle = io.BytesIO()
    image.save(handle, **PNG_SAVE_ARGS)
    return handle.getvalue()


def ceil_fraction(value: Fraction) -> int:
    return -(-value.numerator // value.denominator)


def source_index(dst: int, num: int, den: int) -> int:
    """Exact integer nearest-neighbour index of a destination pixel.

    ``num/den`` is the rational step in source px per destination px (the
    inverse of the uniform scale). The unclamped centre-of-pixel index is
    ``(2*dst + 1) * num // (2*den)``; callers clamp to the source extent.
    """
    return ((2 * dst + 1) * num) // (2 * den)


def compute_fit(src_w: int, src_h: int, max_w: int, max_h: int) -> dict:
    """Uniform rational scale and destination size for one occupied extent.

    Returns the scale as an exact Fraction plus integer destination size that
    covers the entire source extent (ceil) and never exceeds the bounds.
    """
    if src_w <= 0 or src_h <= 0:
        raise BuildError(f"empty occupied extent {src_w}x{src_h}")
    if max_w <= 0 or max_h <= 0:
        raise BuildError(f"non-positive fit bounds {max_w}x{max_h}")
    scale = min(Fraction(max_w, src_w), Fraction(max_h, src_h))
    dst_w = ceil_fraction(src_w * scale)
    dst_h = ceil_fraction(src_h * scale)
    if dst_w > max_w or dst_h > max_h:
        raise BuildError(
            f"fit overflow: {dst_w}x{dst_h} exceeds {max_w}x{max_h} "
            f"for source {src_w}x{src_h} at scale {scale}"
        )
    step = 1 / scale
    return {
        "scale": scale,
        "step_num": step.numerator,
        "step_den": step.denominator,
        "dst_w": dst_w,
        "dst_h": dst_h,
    }


# ---------------------------------------------------------------------------
# Raw source analysis


def alpha_histogram(alpha: Image.Image) -> list[int]:
    """256-bucket histogram of an L-mode alpha channel."""
    return alpha.histogram()


def mask_bbox(mask: Image.Image) -> list[int] | None:
    """[x, y, w, h] bbox of nonzero pixels in an L-mode mask, or None."""
    box = mask.getbbox()
    if box is None:
        return None
    return [box[0], box[1], box[2] - box[0], box[3] - box[1]]


def component_count(mask: Image.Image, bbox: list[int]) -> int:
    """Number of 4-connected occupied components inside the occupied bbox."""
    x0, y0, w, h = bbox
    region = mask.crop((x0, y0, x0 + w, y0 + h)).tobytes()
    seen = bytearray(w * h)
    count = 0
    for start in range(w * h):
        if seen[start] or region[start] == 0:
            continue
        count += 1
        queue = deque([start])
        seen[start] = 1
        while queue:
            pos = queue.popleft()
            px, py = pos % w, pos // w
            for nx, ny in ((px - 1, py), (px + 1, py), (px, py - 1), (px, py + 1)):
                if 0 <= nx < w and 0 <= ny < h:
                    npos = ny * w + nx
                    if not seen[npos] and region[npos] != 0:
                        seen[npos] = 1
                        queue.append(npos)
    return count


def analyse_raw(raw: Image.Image, threshold: int) -> dict:
    """Occupancy statistics for a raw generated sprite.

    Occupied pixels are alpha >= threshold; discarded fringe pixels are
    0 < alpha < threshold (the low-alpha background wash the generator leaves
    around the object). Returns the occupied bbox, pixel counts, both alpha
    histograms, the fringe bbox, and the occupied component count.
    """
    alpha = raw.getchannel("A")
    hist = alpha_histogram(alpha)
    occupied_mask = alpha.point(lambda a: 255 if a >= threshold else 0)
    fringe_mask = alpha.point(lambda a: 255 if 0 < a < threshold else 0)
    occupied_bbox = mask_bbox(occupied_mask)
    fringe_bbox = mask_bbox(fringe_mask)
    occupied_hist = {str(a): c for a, c in enumerate(hist[threshold:], start=threshold) if c}
    fringe_hist = {str(a): c for a, c in enumerate(hist[1:threshold], start=1) if c}
    return {
        "occupied_bbox": occupied_bbox,
        "occupied_pixels": sum(hist[threshold:]),
        "occupied_alpha_histogram": occupied_hist,
        "occupied_components": (
            component_count(occupied_mask, occupied_bbox) if occupied_bbox else 0
        ),
        "fringe_bbox": fringe_bbox,
        "fringe_pixels": sum(hist[1:threshold]),
        "fringe_alpha_histogram": fringe_hist,
        "zero_alpha_pixels": hist[0],
    }


def load_raw(root: Path, config: dict, asset_cfg: dict, asset_id: str) -> tuple[Image.Image, str, Path]:
    source_name = asset_cfg.get("source", f"{asset_id}_raw.png")
    path = root / config["source_dir"] / source_name
    if not path.is_file():
        raise BuildError(f"raw source missing: {display_path(path, root)}")
    actual = sha256_file(path)
    pinned = asset_cfg.get("source_sha256")
    if pinned and pinned != actual:
        raise BuildError(
            f"raw hash mismatch for {asset_id}: config pins {pinned}, file is {actual}"
        )
    return Image.open(path).convert("RGBA"), actual, path


# ---------------------------------------------------------------------------
# Packing


def pack_object(raw: Image.Image, asset_cfg: dict, defaults: dict) -> tuple[Image.Image, dict]:
    """Pack one whole-object raw sprite onto its configured canvas.

    Returns the opaque canvas (RGBA, binary alpha 0/255) and a transform
    record. Only the threshold occupancy decides geometry; all occupied source
    pixels - including disconnected parts of the same object - are mapped
    together by the single uniform transform.
    """
    canvas_w, canvas_h = asset_cfg["canvas"]
    anchor_x, anchor_y = asset_cfg["anchor"]
    margin = defaults["margin"]
    threshold = asset_cfg.get("alpha_threshold", defaults["alpha_threshold"])
    stats = analyse_raw(raw, threshold)
    if stats["occupied_bbox"] is None:
        raise BuildError(
            f"no occupied pixels at threshold {threshold}; refusing to pack an empty object"
        )
    src_rect = stats["occupied_bbox"]  # trim raw transparent padding only
    sx, sy, src_w, src_h = src_rect

    max_w = canvas_w - 2 * margin
    max_h = anchor_y - margin
    fit = compute_fit(src_w, src_h, max_w, max_h)
    dst_w, dst_h = fit["dst_w"], fit["dst_h"]
    dx = anchor_x - dst_w // 2
    dy = anchor_y - dst_h
    if dx < margin or dx + dst_w > canvas_w - margin:
        raise BuildError(
            f"placement violates the {margin} px horizontal margin: "
            f"dst x {dx}..{dx + dst_w - 1} on {canvas_w} px canvas"
        )
    if dy < margin:
        raise BuildError(
            f"placement violates the {margin} px top margin: dst top {dy}"
        )
    if dy + dst_h > canvas_h:
        raise BuildError("destination window exceeds canvas bottom")

    crop = raw.crop((sx, sy, sx + src_w, sy + src_h))
    src_px = crop.load()
    canvas = Image.new("RGBA", (canvas_w, canvas_h), (0, 0, 0, 0))
    out = canvas.load()
    x_index = [min(src_w - 1, source_index(i, fit["step_num"], fit["step_den"])) for i in range(dst_w)]
    y_index = [min(src_h - 1, source_index(i, fit["step_num"], fit["step_den"])) for i in range(dst_h)]
    for iy, syi in enumerate(y_index):
        for ix, sxi in enumerate(x_index):
            r, g, b, a = src_px[sxi, syi]
            out[dx + ix, dy + iy] = (r, g, b, 255) if a >= threshold else (0, 0, 0, 0)

    transform = {
        "kind": "object",
        "alpha_threshold": threshold,
        "src_rect": src_rect,
        "dst_rect": [dx, dy, dst_w, dst_h],
        "scale": f"{fit['scale'].numerator}/{fit['scale'].denominator}",
        "step": f"{fit['step_num']}/{fit['step_den']}",
        "margin": margin,
        "anchor_rule": "window bottom bound (exclusive) == anchor y; window centred on anchor x",
        "outside": "fully transparent black; source RGB preserved only on occupied pixels",
    }
    return canvas, {"transform": transform, "raw_stats": stats}


def pack_ground_crop(raw: Image.Image, ground_cfg: dict) -> tuple[Image.Image, dict]:
    """Crop the ground plate to its fixed rect with no resizing.

    The plate is a complete opaque underplate: every output pixel must be
    fully opaque, so an alpha-bearing raw with any alpha < 255 is rejected.
    """
    sx, sy, w, h = ground_cfg["src_rect"]
    if raw.width < sx + w or raw.height < sy + h:
        raise BuildError(
            f"ground src_rect {ground_cfg['src_rect']} exceeds raw {raw.width}x{raw.height}"
        )
    canvas = raw.crop((sx, sy, sx + w, sy + h))
    assert_opaque(canvas, "ground")
    if list(canvas.size) != list(ground_cfg["canvas"]):
        raise BuildError(
            f"ground canvas {list(canvas.size)} != configured {ground_cfg['canvas']}"
        )
    transform = {
        "kind": "ground",
        "mode": "crop",
        "src_rect": [sx, sy, w, h],
        "dst_rect": [0, 0, w, h],
        "scale": "1/1",
        "step": "1/1",
    }
    return canvas, {"transform": transform, "raw_stats": None}


def pack_ground_fit(raw: Image.Image, ground_cfg: dict) -> tuple[Image.Image, dict]:
    """Uniform-fit a ground plate to ``fit_width`` then centre-crop height.

    One rational scale ``s = fit_width / raw_w`` is applied to both axes
    through the same integer nearest-neighbour step (never anisotropic).
    The scaled plate is ``fit_width x round(raw_h * s)``; a centre band of
    ``canvas[1]`` rows is then cut out, leaving a recorded symmetric residue
    of ``scaled_h - canvas_h`` rows. Fails closed when the scaled plate does
    not cover the canvas height, and when any pixel is not fully opaque.
    """
    fit_w = ground_cfg["fit_width"]
    canvas_w, canvas_h = ground_cfg["canvas"]
    if fit_w != canvas_w:
        raise BuildError(
            f"ground fit_width {fit_w} must equal canvas width {canvas_w}"
        )
    scale = Fraction(fit_w, raw.width)
    scaled_h = (2 * raw.height * scale.numerator + scale.denominator) // (
        2 * scale.denominator
    )
    if scaled_h < canvas_h:
        raise BuildError(
            f"scaled ground {fit_w}x{scaled_h} does not cover canvas height {canvas_h}"
        )
    step = 1 / scale
    x_index = [
        min(raw.width - 1, source_index(i, step.numerator, step.denominator))
        for i in range(fit_w)
    ]
    y_index = [
        min(raw.height - 1, source_index(i, step.numerator, step.denominator))
        for i in range(scaled_h)
    ]
    src = raw.load()
    scaled = Image.new("RGBA", (fit_w, scaled_h), (0, 0, 0, 0))
    out = scaled.load()
    for dy, sy in enumerate(y_index):
        for dx, sx in enumerate(x_index):
            out[dx, dy] = src[sx, sy]
    assert_opaque(scaled, "ground")
    crop_y = (scaled_h - canvas_h) // 2
    canvas = scaled.crop((0, crop_y, fit_w, crop_y + canvas_h))
    transform = {
        "kind": "ground",
        "mode": "fit_width_crop_height",
        "scale": f"{scale.numerator}/{scale.denominator}",
        "step": f"{step.numerator}/{step.denominator}",
        "scaled_size": [fit_w, scaled_h],
        "crop_origin": [0, crop_y],
        "residue_px": scaled_h - canvas_h,
        "src_rect": [0, 0, raw.width, raw.height],
        "dst_rect": [0, 0, canvas_w, canvas_h],
    }
    return canvas, {"transform": transform, "raw_stats": None}


def assert_opaque(canvas: Image.Image, label: str) -> None:
    extrema = canvas.getchannel("A").getextrema()
    if extrema != (255, 255):
        raise BuildError(
            f"{label} plate is not fully opaque: alpha extrema {extrema}"
        )


def pack_ground(raw: Image.Image, ground_cfg: dict) -> tuple[Image.Image, dict]:
    mode = ground_cfg.get("mode", "crop")
    if mode == "crop":
        return pack_ground_crop(raw, ground_cfg)
    if mode == "fit_width_crop_height":
        return pack_ground_fit(raw, ground_cfg)
    raise BuildError(f"unknown ground mode: {mode}")


def occupied_rect(canvas: Image.Image) -> list[int] | None:
    alpha = canvas.getchannel("A")
    return mask_bbox(alpha.point(lambda a: 255 if a else 0))


def grow_rect(rect: list[int], grow: int) -> list[int]:
    """Occupied AABB grown by ``grow`` px on every side, never clipped.

    The margin contract keeps occupied content at least ``grow`` px from the
    side/top edges and the anchor keeps the bottom inside the canvas, so the
    full grown rect already lies within the canvas for conforming assets;
    ``rect_within_canvas`` reports any violation instead of clipping.
    """
    x, y, w, h = rect
    return [x - grow, y - grow, w + 2 * grow, h + 2 * grow]


def rect_within_canvas(rect: list[int], canvas: list[int]) -> bool:
    x, y, w, h = rect
    return x >= 0 and y >= 0 and x + w <= canvas[0] and y + h <= canvas[1]


def transparent_pair(canvas: Image.Image, transparent_alpha: int) -> Image.Image:
    """Same RGB/canvas/geometry with the configured occupied alpha."""
    pair = canvas.copy()
    px = pair.load()
    src = canvas.load()
    for y in range(canvas.height):
        for x in range(canvas.width):
            r, g, b, a = src[x, y]
            px[x, y] = (r, g, b, transparent_alpha) if a else (0, 0, 0, 0)
    return pair


def assert_pair_contract(opaque: Image.Image, transparent: Image.Image, transparent_alpha: int) -> None:
    """Both states must share RGB, canvas and occupied geometry exactly."""
    if opaque.size != transparent.size:
        raise BuildError("opaque/transparent canvases differ")
    op, tp = opaque.load(), transparent.load()
    for y in range(opaque.height):
        for x in range(opaque.width):
            or_, og, ob, oa = op[x, y]
            tr, tg, tb, ta = tp[x, y]
            if (or_, og, ob) != (tr, tg, tb):
                raise BuildError(f"RGB mismatch at ({x},{y})")
            if oa == 255:
                if ta != transparent_alpha:
                    raise BuildError(f"transparent alpha {ta} != {transparent_alpha} at ({x},{y})")
            elif oa == 0:
                if ta != 0:
                    raise BuildError(f"transparent alpha {ta} outside geometry at ({x},{y})")
            else:
                raise BuildError(f"non-binary opaque alpha {oa} at ({x},{y})")


def margin_check(rect: list[int], canvas: list[int], margin: int, asset_id: str) -> None:
    """Side and top margins hold the 8 px clear band; the bottom is governed
    by the anchor, not the canvas margin."""
    x, y, w, h = rect
    if x < margin or y < margin or x + w > canvas[0] - margin or y + h > canvas[1]:
        raise BuildError(
            f"{asset_id}: occupied rect {rect} violates the {margin} px canvas margin"
        )


# ---------------------------------------------------------------------------
# Manifest entries


def object_manifest_entry(
    asset_id: str,
    asset_cfg: dict,
    canvas: Image.Image,
    transform: dict,
    raw_sha: str,
    source_name: str,
    config: dict,
) -> tuple[dict, bytes, bytes]:
    occ = occupied_rect(canvas)
    if occ is None:
        raise BuildError(f"{asset_id}: packed canvas is empty")
    margin_check(occ, list(asset_cfg["canvas"]), config["margin"], asset_id)
    detection_grow = asset_cfg.get("occlusion_grow", config["occlusion_grow"])
    if not isinstance(detection_grow, int) or detection_grow < config["occlusion_grow"]:
        raise BuildError(f"{asset_id}: detection padding cannot shrink the default")
    occl = grow_rect(occ, detection_grow)
    transparent = transparent_pair(canvas, config["transparent_alpha"])
    assert_pair_contract(canvas, transparent, config["transparent_alpha"])
    opaque_bytes = png_bytes(canvas)
    transparent_bytes = png_bytes(transparent)
    opaque_name = f"{asset_id}_opaque.png"
    transparent_name = f"{asset_id}_transparent.png"
    entry = {
        "status": "packed",
        "kind": "object",
        "section": asset_cfg.get("section", "town"),
        "canvas": list(asset_cfg["canvas"]),
        "anchor": list(asset_cfg["anchor"]),
        "occupied_rect": occ,
        "occlusion_rect": occl,
        "opaque_path": res_path(config["output_dir"], opaque_name),
        "transparent_path": res_path(config["output_dir"], transparent_name),
        "raw_sha256": raw_sha,
        "opaque_sha256": sha256_bytes(opaque_bytes),
        "transparent_sha256": sha256_bytes(transparent_bytes),
        "transform": transform | {"source": f"{config['source_dir']}/{source_name}"},
    }
    if not rect_within_canvas(occl, list(asset_cfg["canvas"])):
        entry["occlusion_overflow"] = True
    return entry, opaque_bytes, transparent_bytes


def ground_manifest_entry(
    ground_id: str,
    ground_cfg: dict,
    canvas: Image.Image,
    transform: dict,
    raw_sha: str,
    config: dict,
) -> tuple[dict, bytes]:
    opaque_bytes = png_bytes(canvas)
    name = f"{ground_id}_opaque.png"
    entry = {
        "status": "packed",
        "kind": "ground",
        "section": ground_cfg.get("section", "town"),
        "canvas": list(ground_cfg["canvas"]),
        "anchor": list(ground_cfg["anchor"]),
        "occupied_rect": [0, 0, canvas.width, canvas.height],
        "occlusion_rect": None,
        "opaque_path": res_path(config["output_dir"], name),
        "transparent_path": None,
        "raw_sha256": raw_sha,
        "opaque_sha256": sha256_bytes(opaque_bytes),
        "transparent_sha256": None,
        "transform": transform | {"source": f"{config['source_dir']}/{ground_cfg['source']}"},
    }
    return entry, opaque_bytes


def pending_entry(asset_id: str, asset_cfg: dict, reason: str, config: dict) -> dict:
    return {
        "status": "pending",
        "kind": "object",
        "section": asset_cfg.get("section", "town"),
        "pending_reason": reason,
        "canvas": list(asset_cfg["canvas"]),
        "anchor": list(asset_cfg["anchor"]),
        "occupied_rect": None,
        "occlusion_rect": None,
        "opaque_path": None,
        "transparent_path": None,
        "raw_sha256": None,
        "opaque_sha256": None,
        "transparent_sha256": None,
        "transform": {
            "kind": "object",
            "source": f"{config['source_dir']}/{asset_cfg.get('source', f'{asset_id}_raw.png')}",
        },
    }


def pending_ground_entry(ground_cfg: dict, reason: str, config: dict) -> dict:
    return {
        "status": "pending",
        "kind": "ground",
        "section": ground_cfg.get("section", "town"),
        "pending_reason": reason,
        "canvas": list(ground_cfg["canvas"]),
        "anchor": list(ground_cfg["anchor"]),
        "occupied_rect": None,
        "occlusion_rect": None,
        "opaque_path": None,
        "transparent_path": None,
        "raw_sha256": None,
        "opaque_sha256": None,
        "transparent_sha256": None,
        "transform": {
            "kind": "ground",
            "source": f"{config['source_dir']}/{ground_cfg['source']}",
        },
    }


# ---------------------------------------------------------------------------
# Incremental carry-over


def entry_still_valid(entry: dict, root: Path, config: dict) -> tuple[bool, str]:
    """Verify a previously packed entry against current raws and outputs."""
    if entry.get("status") != "packed":
        return False, "not_packed"
    raw_rel = entry.get("transform", {}).get("source")
    raw_path = (root / raw_rel) if raw_rel else None
    if raw_path is None or not raw_path.is_file():
        return False, "raw_missing"
    if sha256_file(raw_path) != entry.get("raw_sha256"):
        return False, "raw_changed"
    for field, sha_field in (
        ("opaque_path", "opaque_sha256"),
        ("transparent_path", "transparent_sha256"),
    ):
        rel = entry.get(field)
        expected = entry.get(sha_field)
        if rel is None:
            continue
        path = root / rel.removeprefix("res://")
        if not path.is_file():
            return False, "outputs_missing"
        if sha256_file(path) != expected:
            return False, "outputs_changed"
    return True, "packed"


def load_previous_manifest(out_dir: Path) -> dict:
    path = out_dir / MANIFEST_NAME
    if not path.is_file():
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}


def allowed_output_names(config: dict) -> set[str]:
    names = {MANIFEST_NAME}
    for ground_id in config["grounds"]:
        names.add(f"{ground_id}_opaque.png")
    for asset_id in config["assets"]:
        names.add(f"{asset_id}_opaque.png")
        names.add(f"{asset_id}_transparent.png")
    return names


def guard_output(out_dir: Path, config: dict) -> None:
    if not out_dir.exists():
        return
    if not out_dir.is_dir():
        raise BuildError(f"output exists and is not a directory: {out_dir}")
    allowed = allowed_output_names(config)
    # Godot sidecars carry strict texture-import options and must survive repacks.
    allowed |= {name + ".import" for name in allowed if name.endswith(".png")}
    preserved = config.get("preserved_subdirs", [])
    if any(not isinstance(name, str) or Path(name).name != name or name in (".", "..")
           for name in preserved):
        raise BuildError("preserved_subdirs must contain direct child directory names")
    unexpected = [p.name for p in out_dir.iterdir()
                  if p.name not in allowed and not (p.name in preserved and p.is_dir())]
    if unexpected:
        raise BuildError(
            f"refusing to write into {out_dir}: unexpected entries {sorted(unexpected)}"
        )


# ---------------------------------------------------------------------------
# Run


def load_config(path: Path) -> dict:
    data = json.loads(path.read_text(encoding="utf-8"))
    required = ("source_dir", "output_dir", "report_dir", "margin",
                "occlusion_grow", "transparent_alpha", "default_alpha_threshold",
                "primary_ground", "grounds", "assets")
    missing = [key for key in required if key not in data]
    if missing:
        raise BuildError(f"config missing keys: {missing}")
    if data["primary_ground"] not in data["grounds"]:
        raise BuildError("primary_ground is not a configured grounds id")
    return data


def build_manifest(config: dict, config_sha: str, entries: dict, grounds: dict) -> dict:
    pending = [aid for aid, e in entries.items() if e["status"] == "pending"]
    stale = [aid for aid, e in entries.items() if e["status"] == "stale"]
    ground_pending = [gid for gid, e in grounds.items() if e["status"] == "pending"]
    ground_stale = [gid for gid, e in grounds.items() if e["status"] == "stale"]

    sections: dict[str, dict] = {}
    for aid, asset_cfg in config["assets"].items():
        sec = asset_cfg.get("section", "town")
        bucket = sections.setdefault(
            sec, {"assets": [], "grounds": [], "pending": [], "stale": [], "complete": True}
        )
        bucket["assets"].append(aid)
        status = entries[aid]["status"]
        if status != "packed":
            bucket["complete"] = False
            bucket["pending" if status == "pending" else "stale"].append(aid)
    for gid, ground_cfg in config["grounds"].items():
        sec = ground_cfg.get("section", "town")
        bucket = sections.setdefault(
            sec, {"assets": [], "grounds": [], "pending": [], "stale": [], "complete": True}
        )
        bucket["grounds"].append(gid)
        status = grounds[gid]["status"]
        if status != "packed":
            bucket["complete"] = False
            bucket["pending" if status == "pending" else "stale"].append(gid)

    return {
        "schema_version": 1,
        "package": config["package"],
        "generator": "tools/art_pipeline/generated_world_v02/pack.py",
        "config_sha256": config_sha,
        "semantics": {
            "rect_format": "[x, y, width, height] in canvas pixels",
            "anchor": "object anchor: the mapped object window's bottom bound (exclusive) "
                      "sits at anchor[1]; the window is centred on anchor[0] (half-pixel "
                      "left bias on odd widths); ground anchor is the canvas origin",
            "occlusion_rect": "occupied_rect grown by occlusion_grow px on every side, "
                              "never clipped (margin contract keeps it inside the canvas; "
                              "occlusion_overflow flags any violation); null for grounds",
            "alpha": f"opaque states use binary alpha 0/255; transparent states binary 0/{config['transparent_alpha']} "
                     "on identical RGB, canvas and occupied geometry",
            "paths": "res:// paths relative to the Godot project root",
            "canvas": "full configured canvas always preserved; occupied content never "
                      "enters the 8 px margin",
            "sections": "independent completeness per section; 'ground' mirrors "
                        "grounds[primary_ground] for the original town contract",
        },
        "ground": grounds.get(config["primary_ground"]),
        "grounds": grounds,
        "sections": sections,
        "assets": entries,
        "pending": pending,
        "stale": stale,
        "complete": (
            not pending and not stale and not ground_pending and not ground_stale
        ),
    }


def run_pack(root: Path, config: dict, config_sha: str, targets: set[str] | None,
             write: bool = True) -> tuple[dict, dict]:
    """Pack requested targets and (re)build the manifest.

    ``targets=None`` packs everything whose raw exists; otherwise only the
    named ids are packed and still-valid previous entries carry over.
    Returns (manifest, report).
    """
    out_dir = root / config["output_dir"]
    defaults = {
        "margin": config["margin"],
        "alpha_threshold": config["default_alpha_threshold"],
    }
    previous = load_previous_manifest(out_dir) if write else {}
    prev_assets = previous.get("assets", {})
    prev_ground = previous.get("ground")

    entries: dict[str, dict] = {}
    report_assets: dict[str, dict] = {}
    writes: dict[str, bytes] = {}

    def pack_one(asset_id: str, asset_cfg: dict) -> None:
        source_name = asset_cfg.get("source", f"{asset_id}_raw.png")
        raw, raw_sha, raw_path = load_raw(root, config, asset_cfg, asset_id)
        canvas, info = pack_object(raw, asset_cfg, defaults)
        entry, opaque_b, transparent_b = object_manifest_entry(
            asset_id, asset_cfg, canvas, info["transform"], raw_sha, source_name, config
        )
        entries[asset_id] = entry
        writes[f"{asset_id}_opaque.png"] = opaque_b
        writes[f"{asset_id}_transparent.png"] = transparent_b
        report_assets[asset_id] = {
            "action": "packed",
            "source": display_path(raw_path, root),
            "raw_sha256": raw_sha,
            "transform": entry["transform"],
            "occupied_rect": entry["occupied_rect"],
            "occlusion_rect": entry["occlusion_rect"],
            "raw_stats": info["raw_stats"],
        }

    for asset_id, asset_cfg in config["assets"].items():
        source_name = asset_cfg.get("source", f"{asset_id}_raw.png")
        raw_path = root / config["source_dir"] / source_name
        explicit = targets is not None and asset_id in targets
        if explicit and not raw_path.is_file():
            raise BuildError(
                f"--asset {asset_id} requested but raw is missing: "
                f"{display_path(raw_path, root)}"
            )
        if (targets is None or explicit) and raw_path.is_file():
            pack_one(asset_id, asset_cfg)
            continue
        prev = prev_assets.get(asset_id)
        if not raw_path.is_file():
            if prev and prev.get("status") == "packed":
                stale = dict(prev)
                stale["status"] = "stale"
                stale["stale_reason"] = "raw_missing"
                entries[asset_id] = stale
            else:
                entries[asset_id] = pending_entry(asset_id, asset_cfg, "raw_missing", config)
            report_assets[asset_id] = {"action": entries[asset_id]["status"],
                                       "reason": "raw_missing"}
            continue
        if prev:
            ok, reason = entry_still_valid(prev, root, config)
            if ok:
                entries[asset_id] = prev
                report_assets[asset_id] = {"action": "carried_over",
                                           "raw_sha256": prev.get("raw_sha256")}
            else:
                stale = dict(prev)
                stale["status"] = "stale"
                stale["stale_reason"] = reason
                entries[asset_id] = stale
                report_assets[asset_id] = {"action": "stale", "reason": reason}
        else:
            entries[asset_id] = pending_entry(asset_id, asset_cfg, "not_requested", config)
            report_assets[asset_id] = {"action": "pending", "reason": "not_requested"}

    # Ground plates
    grounds: dict[str, dict] = {}
    prev_grounds = previous.get("grounds", {})
    if prev_ground and config["primary_ground"] not in prev_grounds:
        prev_grounds[config["primary_ground"]] = prev_ground
    for ground_id, ground_cfg in config["grounds"].items():
        ground_raw_path = root / config["source_dir"] / ground_cfg["source"]
        explicit = targets is not None and (
            ground_id in targets
            or ("ground" in targets and ground_id == config["primary_ground"])
        )
        if explicit and not ground_raw_path.is_file():
            raise BuildError(
                f"ground {ground_id} requested but raw is missing: "
                f"{display_path(ground_raw_path, root)}"
            )
        if (targets is None or explicit) and ground_raw_path.is_file():
            raw, raw_sha, raw_path = load_raw(root, config, ground_cfg, ground_id)
            canvas, info = pack_ground(raw, ground_cfg)
            ground_entry, opaque_b = ground_manifest_entry(
                ground_id, ground_cfg, canvas, info["transform"], raw_sha, config
            )
            grounds[ground_id] = ground_entry
            writes[f"{ground_id}_opaque.png"] = opaque_b
            report_assets[ground_id] = {
                "action": "packed",
                "source": display_path(raw_path, root),
                "raw_sha256": raw_sha,
                "transform": ground_entry["transform"],
            }
            continue
        prev = prev_grounds.get(ground_id)
        if not ground_raw_path.is_file():
            if prev and prev.get("status") == "packed":
                stale_entry = dict(prev)
                stale_entry["status"] = "stale"
                stale_entry["stale_reason"] = "raw_missing"
                grounds[ground_id] = stale_entry
            else:
                grounds[ground_id] = pending_ground_entry(ground_cfg, "raw_missing", config)
            report_assets[ground_id] = {"action": grounds[ground_id]["status"],
                                        "reason": "raw_missing"}
        elif prev:
            ok, reason = entry_still_valid(prev, root, config)
            grounds[ground_id] = dict(prev)
            if not ok:
                grounds[ground_id]["status"] = "stale"
                grounds[ground_id]["stale_reason"] = reason
            report_assets[ground_id] = {
                "action": "carried_over" if ok else "stale", "reason": reason}
        else:
            grounds[ground_id] = pending_ground_entry(ground_cfg, "not_requested", config)
            report_assets[ground_id] = {"action": "pending", "reason": "not_requested"}

    manifest = build_manifest(config, config_sha, entries, grounds)

    if write:
        guard_output(out_dir, config)
        out_dir.mkdir(parents=True, exist_ok=True)
        for name, data in writes.items():
            (out_dir / name).write_bytes(data)
        manifest_path = out_dir / MANIFEST_NAME
        manifest_path.write_text(
            json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )

    report = {
        "generator": "tools/art_pipeline/generated_world_v02/pack.py",
        "config_sha256": config_sha,
        "mode": "available" if targets is None else "asset",
        "assets": report_assets,
        "manifest_complete": manifest["complete"],
        "manifest_pending": manifest["pending"],
        "manifest_stale": manifest["stale"],
    }
    return manifest, report


def run_verify(root: Path, config: dict) -> list[str]:
    """Recompute every packed manifest entry and compare hashes.

    Returns a list of human-readable check results; raises BuildError on the
    first mismatch. This is the rebuild-determinism check: identical raws
    must reproduce byte-identical outputs.
    """
    manifest_path = root / config["output_dir"] / MANIFEST_NAME
    if not manifest_path.is_file():
        raise BuildError("no manifest to verify; run a pack first")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    results = []
    defaults = {"margin": config["margin"],
                "alpha_threshold": config["default_alpha_threshold"]}
    for asset_id, entry in manifest.get("assets", {}).items():
        if entry.get("status") != "packed":
            continue
        asset_cfg = config["assets"].get(asset_id)
        if asset_cfg is None:
            raise BuildError(f"manifest asset {asset_id} not in config")
        source_name = asset_cfg.get("source", f"{asset_id}_raw.png")
        raw, raw_sha, _ = load_raw(root, config, asset_cfg, asset_id)
        if raw_sha != entry["raw_sha256"]:
            raise BuildError(f"{asset_id}: raw hash drifted since pack")
        canvas, info = pack_object(raw, asset_cfg, defaults)
        recomputed, opaque_b, transparent_b = object_manifest_entry(
            asset_id, asset_cfg, canvas, info["transform"], raw_sha, source_name, config
        )
        if recomputed != entry:
            raise BuildError(f"{asset_id}: manifest entry does not reproduce")
        for field, data in (("opaque_path", opaque_b), ("transparent_path", transparent_b)):
            path = root / entry[field].removeprefix("res://")
            if sha256_bytes(data) != sha256_file(path):
                raise BuildError(f"{asset_id}: {path.name} bytes do not reproduce")
        results.append(f"{asset_id}: outputs and entry reproduce exactly")
    for ground_id, ground_entry in manifest.get("grounds", {}).items():
        if ground_entry.get("status") != "packed":
            continue
        ground_cfg = config["grounds"].get(ground_id)
        if ground_cfg is None:
            raise BuildError(f"manifest ground {ground_id} not in config")
        raw, raw_sha, _ = load_raw(root, config, ground_cfg, ground_id)
        if raw_sha != ground_entry["raw_sha256"]:
            raise BuildError(f"{ground_id}: raw hash drifted since pack")
        canvas, info = pack_ground(raw, ground_cfg)
        recomputed, opaque_b = ground_manifest_entry(
            ground_id, ground_cfg, canvas, info["transform"], raw_sha, config
        )
        if recomputed != ground_entry:
            raise BuildError(f"{ground_id}: manifest entry does not reproduce")
        path = root / ground_entry["opaque_path"].removeprefix("res://")
        if sha256_bytes(opaque_b) != sha256_file(path):
            raise BuildError(f"{ground_id}: opaque bytes do not reproduce")
        results.append(f"{ground_id}: output and entry reproduce exactly")
    return results


def write_report(root: Path, config: dict, report: dict) -> Path:
    report_dir = root / config["report_dir"]
    report_dir.mkdir(parents=True, exist_ok=True)
    path = report_dir / "packing_report.json"
    path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n",
                    encoding="utf-8")
    return path


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--config", type=Path, default=DEFAULT_CONFIG,
                        help="packing config JSON (default: alongside this tool)")
    parser.add_argument("--root", type=Path, default=REPO_ROOT,
                        help="repository root for source/output paths")
    parser.add_argument("--available", action="store_true",
                        help="pack every configured asset whose raw exists (default)")
    parser.add_argument("--asset", action="append", default=[],
                        help="pack only the named asset id (repeatable; 'ground' alias)")
    parser.add_argument("--verify", action="store_true",
                        help="recompute packed entries and assert byte-identical outputs")
    parser.add_argument("--list", action="store_true",
                        help="print per-asset status from the manifest and exit")
    args = parser.parse_args(argv)

    root = args.root.resolve()
    try:
        config = load_config(args.config)
        config_sha = sha256_file(args.config)
        if args.list:
            manifest_path = root / config["output_dir"] / MANIFEST_NAME
            if not manifest_path.is_file():
                print("no manifest yet")
                return 0
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            for aid, entry in manifest["assets"].items():
                print(f"{aid}: {entry['status']}")
            for gid, entry in manifest.get("grounds", {}).items():
                print(f"{gid}: {entry['status']}")
            for sec, bucket in manifest.get("sections", {}).items():
                print(f"section {sec}: complete={bucket['complete']}")
            print(f"complete: {manifest['complete']}")
            return 0
        if args.verify:
            for line in run_verify(root, config):
                print(f"VERIFY OK {line}")
            return 0
        targets = set(args.asset) if args.asset else None
        if targets:
            unknown = targets - set(config["assets"]) - set(config["grounds"]) - {"ground"}
            if unknown:
                raise BuildError(f"unknown asset ids: {sorted(unknown)}")
        manifest, report = run_pack(root, config, config_sha, targets, write=True)
        report_path = write_report(root, config, report)
    except (BuildError, OSError, ValueError) as exc:
        print(f"PACK FAILED: {exc}", file=sys.stderr)
        return 1
    packed = [aid for aid, e in manifest["assets"].items() if e["status"] == "packed"]
    print(json.dumps({
        "packed": sorted(packed),
        "grounds": {gid: e["status"] for gid, e in manifest["grounds"].items()},
        "sections": {sec: b["complete"] for sec, b in manifest["sections"].items()},
        "pending": sorted(manifest["pending"]),
        "stale": sorted(manifest["stale"]),
        "complete": manifest["complete"],
        "report": display_path(report_path, root),
    }, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
