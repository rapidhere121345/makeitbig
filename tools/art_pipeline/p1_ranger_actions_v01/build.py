#!/usr/bin/env python3
"""Pack P1 ranger action frames into a mechanical 48x48 fixed-anchor atlas.

Only bounded mechanical transforms are performed: an explicit recipe crop, one
unified nearest-neighbor scale per source, explicitly declared background
handling, exact palette limiting, and fixed-anchor placement on 48x48 cells.
The tool never draws, repairs, or substitutes bitmap art, and it never writes
to a source image. Frames are never fitted per frame, so an outstretched bow or
arm cannot move the feet and poses cannot change apparent size.

Background policy: alpha is preserved by default. A source that is fully
opaque fails the build; the permitted remedy is an explicitly declared
color key with an explicit tolerance (plus an optional removal scope). A
checkerboard or any other accidental background is never removed
automatically and is never disguised.
"""

from __future__ import annotations

import argparse
import collections
import hashlib
import json
import math
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))  # art_pipeline/common.py
import common  # noqa: E402

PIPELINE = "p1_ranger_actions_v01"
SCHEMA_VERSION = 1
NATIVE_VIEW = (640, 360)
CELL_SIZE = (48, 48)
ANCHOR = (24, 44)
# Backward-compatible default texture identity: a recipe that omits
# ``texture_key`` keeps producing exactly the accepted ranger.png contract.
TEXTURE_ID = "ranger"
TEXTURE_FILENAME = "ranger.png"
TEXTURE_KEY_PATTERN = r"[A-Za-z][A-Za-z0-9_-]{0,63}"
TEXTURE_KEY_RE = re.compile(rf"\A{TEXTURE_KEY_PATTERN}\Z")
ALPHA_THRESHOLD = 128
BACKGROUND_MODES = ("alpha", "color_key")
COLOR_KEY_SCOPES = ("all", "border")
REQUIRED_TOP_LEVEL = (
    "schema_version",
    "resource_prefix",
    "native_view",
    "palette",
    "sources",
    "cell_size",
    "anchor",
    "columns",
    "frames",
    "animations",
)
OPTIONAL_TOP_LEVEL = ("texture_key", "background", "disclosure")
FRAME_KEYS = ("id", "source", "crop", "source_anchor", "scale", "action", "facing")


def texture_key_from_config(config: dict[str, Any]) -> str:
    """Resolve the recipe's texture key, defaulting to the ranger contract."""
    raw = config.get("texture_key", TEXTURE_ID)
    if not isinstance(raw, str) or not TEXTURE_KEY_RE.match(raw):
        raise ConfigError(
            "texture_key must be a plain identifier matching "
            f"{TEXTURE_KEY_PATTERN}; the texture file is <texture_key>.png inside the output "
            "directory, so path separators, dots, dot segments and empty keys are not allowed "
            f"(got {raw!r})"
        )
    return raw


def texture_name_for_key(texture_key: str) -> str:
    """Return the texture filename for a validated texture key."""
    if not isinstance(texture_key, str) or not TEXTURE_KEY_RE.match(texture_key):
        raise ConfigError(f"invalid texture key {texture_key!r}")
    return f"{texture_key}.png"


def texture_spec(config: dict[str, Any]) -> tuple[str, str]:
    """Return ``(texture_id, texture_filename)`` for a validated recipe."""
    texture_key = texture_key_from_config(config)
    return texture_key, texture_name_for_key(texture_key)


class ConfigError(ValueError):
    """Raised when a recipe or source cannot be processed unambiguously."""


@dataclass(frozen=True)
class SourceSpec:
    key: str
    path: Path
    mode: str
    colors: tuple[tuple[int, int, int, int], ...]
    tolerance: float
    scope: str
    sha256: str
    width: int
    height: int
    transparent_pixels: int


@dataclass(frozen=True)
class FrameSpec:
    id: str
    source: str
    crop: tuple[int, int, int, int]
    source_anchor: tuple[int, int]
    scale: float
    action: str
    facing: str


@dataclass(frozen=True)
class AnimationSpec:
    id: str
    frames: tuple[str, ...]
    fps: int
    loop: bool


def _require_int_pair(value: Any, name: str, *, minimum: int = 1) -> tuple[int, int]:
    if not isinstance(value, list) or len(value) != 2:
        raise ConfigError(f"{name} must be [x,y]")
    if any(isinstance(item, bool) or not isinstance(item, int) for item in value):
        raise ConfigError(f"{name} entries must be integers")
    if any(item < minimum for item in value):
        raise ConfigError(f"{name} entries must be >= {minimum}")
    return value[0], value[1]


def _require_rect(value: Any, name: str) -> tuple[int, int, int, int]:
    if not isinstance(value, list) or len(value) != 4:
        raise ConfigError(f"{name} must be [x,y,w,h]")
    if any(isinstance(item, bool) or not isinstance(item, int) for item in value):
        raise ConfigError(f"{name} entries must be integers")
    x, y, width, height = value
    if x < 0 or y < 0:
        raise ConfigError(f"{name} origin must be >= 0")
    if width <= 0 or height <= 0:
        raise ConfigError(f"{name} size must be positive")
    return x, y, width, height


def parse_hex_color(value: Any, name: str) -> tuple[int, int, int, int]:
    if not isinstance(value, str):
        raise ConfigError(f"{name} must be a hex string")
    cleaned = value.strip()
    if len(cleaned) not in (4, 5, 7, 9) or cleaned[0] != "#":
        raise ConfigError(f"{name} must be #RGB, #RGBA, #RRGGBB, or #RRGGBBAA")
    digits_text = cleaned[1:]
    if len(cleaned) in (4, 5):
        digits_text = "".join(char * 2 for char in digits_text)
    try:
        digits = bytes.fromhex(digits_text)
    except ValueError as exc:
        raise ConfigError(f"{name} is not valid hex") from exc
    if len(digits) == 1:
        return digits[0], digits[0], digits[0], 255
    if len(digits) == 2:
        return digits[0], digits[0], digits[0], digits[1]
    if len(digits) == 3:
        return digits[0], digits[1], digits[2], 255
    return digits[0], digits[1], digits[2], digits[3]


def hex_text(color: tuple[int, int, int, int]) -> str:
    return "#{:02x}{:02x}{:02x}{:02x}".format(*color)


sha256_file = common.sha256_file


def load_json(path: Path) -> dict[str, Any]:
    return common.load_json(path, "JSON", ConfigError)


def color_distance(left: tuple[int, int, int, int], right: tuple[int, int, int, int]) -> float:
    return math.sqrt(sum((a - b) * (a - b) for a, b in zip(left, right)) / 4.0)


def key_distance(pixel: tuple[int, int, int, int], color: tuple[int, int, int, int]) -> float:
    return math.sqrt(sum((a - b) * (a - b) for a, b in zip(pixel[:3], color[:3])))


def parse_palette(config: dict[str, Any]) -> tuple[tuple[int, int, int, int], ...]:
    raw = config.get("palette")
    if not isinstance(raw, list) or not raw:
        raise ConfigError("palette must be a non-empty array")
    parsed = tuple(parse_hex_color(item, f"palette[{index}]") for index, item in enumerate(raw))
    if len(set(parsed)) != len(parsed):
        raise ConfigError("palette contains duplicate colors")
    return parsed


def validate_config(config: dict[str, Any]) -> None:
    missing = [key for key in REQUIRED_TOP_LEVEL if key not in config]
    if missing:
        raise ConfigError("missing config keys: " + ", ".join(missing))
    unknown = [key for key in config if key not in REQUIRED_TOP_LEVEL + OPTIONAL_TOP_LEVEL]
    if unknown:
        raise ConfigError("unknown config keys: " + ", ".join(sorted(unknown)))
    if config["schema_version"] != SCHEMA_VERSION:
        raise ConfigError(f"schema_version must be {SCHEMA_VERSION}")
    if list(config["native_view"]) != list(NATIVE_VIEW):
        raise ConfigError(f"native_view must be {list(NATIVE_VIEW)} for this pipeline version")
    prefix = config["resource_prefix"]
    if not isinstance(prefix, str) or not prefix.startswith("res://"):
        raise ConfigError("resource_prefix must be a res:// path")
    texture_key_from_config(config)
    if list(config["cell_size"]) != list(CELL_SIZE):
        raise ConfigError(
            f"cell_size must be {list(CELL_SIZE)} for this pipeline version; per-frame fitting is not supported"
        )
    if list(config["anchor"]) != list(ANCHOR):
        raise ConfigError(f"anchor must be {list(ANCHOR)} for this pipeline version")
    columns = config["columns"]
    if isinstance(columns, bool) or not isinstance(columns, int) or columns < 1:
        raise ConfigError("columns must be a positive integer")
    parse_palette(config)

    sources = config["sources"]
    if not isinstance(sources, dict) or not sources:
        raise ConfigError("sources must be a non-empty object")
    for key, value in sources.items():
        if not isinstance(key, str) or not key:
            raise ConfigError("source ids must be non-empty strings")
        if not isinstance(value, str) or not Path(value).is_absolute():
            raise ConfigError(f"sources.{key} must be an absolute PNG path string")

    background = config.get("background", {})
    if not isinstance(background, dict):
        raise ConfigError("background must be an object keyed by source id")
    for key, raw in background.items():
        if key not in sources:
            raise ConfigError(f"background.{key} does not match any source")
        if not isinstance(raw, dict):
            raise ConfigError(f"background.{key} must be an object")
        unknown_keys = [item for item in raw if item not in ("mode", "colors", "tolerance", "scope")]
        if unknown_keys:
            raise ConfigError(f"background.{key} has unknown keys: " + ", ".join(sorted(unknown_keys)))
        mode = raw.get("mode")
        if mode not in BACKGROUND_MODES:
            raise ConfigError(f"background.{key}.mode must be one of {list(BACKGROUND_MODES)}")
        colors = raw.get("colors", [])
        if not isinstance(colors, list):
            raise ConfigError(f"background.{key}.colors must be an array")
        if mode == "color_key":
            if not colors:
                raise ConfigError(f"background.{key}.colors is required for color_key")
            if "tolerance" not in raw:
                raise ConfigError(
                    f"background.{key}.tolerance must be chosen explicitly for color_key; "
                    "a silent default could delete interior art"
                )
        for index, color in enumerate(colors):
            parse_hex_color(color, f"background.{key}.colors[{index}]")
        tolerance = raw.get("tolerance", 0.0)
        if isinstance(tolerance, bool) or not isinstance(tolerance, (int, float)):
            raise ConfigError(f"background.{key}.tolerance must be numeric")
        if not 0 <= float(tolerance) <= 255:
            raise ConfigError(f"background.{key}.tolerance must be in [0,255]")
        scope = raw.get("scope", "all")
        if scope not in COLOR_KEY_SCOPES:
            raise ConfigError(f"background.{key}.scope must be one of {list(COLOR_KEY_SCOPES)}")

    disclosure = config.get("disclosure", {})
    if not isinstance(disclosure, dict):
        raise ConfigError("disclosure must be an object keyed by source id")
    for key, text in disclosure.items():
        if key not in sources:
            raise ConfigError(f"disclosure.{key} does not match any source")
        if not isinstance(text, str) or not text.strip():
            raise ConfigError(f"disclosure.{key} must be a non-empty string")

    frames = validate_frames(config)
    validate_animations(config, frames)


def validate_frames(config: dict[str, Any]) -> list[FrameSpec]:
    sources = config["sources"]
    frames_raw = config["frames"]
    if not isinstance(frames_raw, list) or not frames_raw:
        raise ConfigError("frames must be a non-empty array")
    frames: list[FrameSpec] = []
    seen: set[str] = set()
    for index, raw in enumerate(frames_raw):
        name = f"frames[{index}]"
        if not isinstance(raw, dict):
            raise ConfigError(f"{name} must be an object")
        unknown = [key for key in raw if key not in FRAME_KEYS]
        if unknown:
            raise ConfigError(
                f"{name} has unknown keys: "
                + ", ".join(sorted(unknown))
                + "; allowed keys are "
                + ", ".join(FRAME_KEYS)
            )
        frame_id = raw.get("id")
        if not isinstance(frame_id, str) or not frame_id:
            raise ConfigError(f"{name}.id must be a non-empty string")
        if frame_id in seen:
            raise ConfigError(f"duplicate frame id: {frame_id}")
        seen.add(frame_id)
        source = raw.get("source")
        if source not in sources:
            raise ConfigError(f"{name}.source is not defined: {source}")
        crop = _require_rect(raw.get("crop"), f"{name}.crop")
        anchor = _require_int_pair(raw.get("source_anchor"), f"{name}.source_anchor", minimum=0)
        if anchor[0] > crop[2] or anchor[1] > crop[3]:
            raise ConfigError(f"{name}.source_anchor must be inside the crop {list(crop)}")
        scale = raw.get("scale")
        if isinstance(scale, bool) or not isinstance(scale, (int, float)):
            raise ConfigError(f"{name}.scale must be numeric")
        if not 0 < float(scale) <= 16:
            raise ConfigError(f"{name}.scale must be in (0,16]")
        action = raw.get("action")
        facing = raw.get("facing")
        for label, value in (("action", action), ("facing", facing)):
            if not isinstance(value, str) or not value or "." in value:
                raise ConfigError(f"{name}.{label} must be a non-empty token without dots")
        frames.append(
            FrameSpec(
                id=frame_id,
                source=source,
                crop=crop,
                source_anchor=anchor,
                scale=float(scale),
                action=action,
                facing=facing,
            )
        )
    by_source: dict[str, list[FrameSpec]] = {}
    for frame in frames:
        by_source.setdefault(frame.source, []).append(frame)
    for source_key, members in by_source.items():
        scales = sorted({member.scale for member in members})
        if len(scales) > 1:
            raise ConfigError(
                f"source {source_key} is used with different scales {scales}; one unified scale per source "
                "is required so poses cannot change apparent size"
            )
    return frames


def validate_animations(config: dict[str, Any], frames: list[FrameSpec]) -> list[AnimationSpec]:
    raw_animations = config["animations"]
    if not isinstance(raw_animations, dict) or not raw_animations:
        raise ConfigError("animations must be a non-empty object")
    by_id = {frame.id: frame for frame in frames}
    animations: list[AnimationSpec] = []
    for animation_id, raw in raw_animations.items():
        name = f"animations.{animation_id}"
        if not isinstance(animation_id, str) or not animation_id:
            raise ConfigError("animation ids must be non-empty strings")
        if not isinstance(raw, dict):
            raise ConfigError(f"{name} must be an object")
        unknown = [key for key in raw if key not in ("frames", "fps", "loop")]
        if unknown:
            raise ConfigError(f"{name} has unknown keys: " + ", ".join(sorted(unknown)))
        members = raw.get("frames")
        if not isinstance(members, list) or not members:
            raise ConfigError(f"{name}.frames must be a non-empty array")
        if len(set(members)) != len(members):
            raise ConfigError(f"{name}.frames lists the same frame id twice")
        for member in members:
            if member not in by_id:
                raise ConfigError(f"{name} references unknown frame: {member}")
        fps = raw.get("fps")
        if isinstance(fps, bool) or not isinstance(fps, int) or fps < 1:
            raise ConfigError(f"{name}.fps must be a positive integer")
        loop = raw.get("loop")
        if not isinstance(loop, bool):
            raise ConfigError(f"{name}.loop must be boolean")
        actions = {by_id[member].action for member in members}
        facings = {by_id[member].facing for member in members}
        if len(actions) != 1 or len(facings) != 1:
            raise ConfigError(
                f"{name} mixes action/facing values {sorted(actions)} / {sorted(facings)}; "
                "one animation must describe one action and one facing"
            )
        action = next(iter(actions))
        facing = next(iter(facings))
        segments = animation_id.split(".")
        if len(segments) < 3 or set(segments[-2:]) != {action, facing}:
            raise ConfigError(
                f"{name} must end with <facing>.<action> (frame facing {facing!r}, frame action {action!r}); "
                f"expected for example 'ranger.{facing}.{action}'"
            )
        animations.append(AnimationSpec(id=animation_id, frames=tuple(members), fps=fps, loop=loop))
    return animations


def is_inside(path: Path, directory: Path) -> bool:
    try:
        return path.resolve().is_relative_to(directory.resolve())
    except OSError:
        return False


def _background_rule(config: dict[str, Any], key: str) -> dict[str, Any]:
    raw = config.get("background", {}).get(key, {})
    return {
        "mode": raw.get("mode", "alpha"),
        "colors": tuple(
            parse_hex_color(item, f"background.{key}.colors[{index}]")
            for index, item in enumerate(raw.get("colors", []))
        ),
        "tolerance": float(raw.get("tolerance", 0.0)),
        "scope": raw.get("scope", "all"),
    }


def load_sources(config: dict[str, Any]) -> dict[str, SourceSpec]:
    result: dict[str, SourceSpec] = {}
    for key, path_text in config["sources"].items():
        path = common.rebase_legacy_path(path_text)
        if not path.is_file():
            raise ConfigError(f"source PNG does not exist: {path}")
        rule = _background_rule(config, key)
        try:
            with Image.open(path) as image:
                image.load()
                width, height = image.size
                rgba = image.convert("RGBA")
        except (OSError, ValueError) as exc:
            raise ConfigError(f"cannot open source PNG {path}: {exc}") from exc
        transparent = sum(rgba.getchannel("A").histogram()[:ALPHA_THRESHOLD])
        spec = SourceSpec(
            key=key,
            path=path.resolve(),
            mode=rule["mode"],
            colors=rule["colors"],
            tolerance=rule["tolerance"],
            scope=rule["scope"],
            sha256=sha256_file(path),
            width=width,
            height=height,
            transparent_pixels=transparent,
        )
        if rule["mode"] == "alpha" and transparent == 0:
            raise ConfigError(
                f"source {key} is fully opaque (no transparent pixel at all); if imagegen transparency failed, "
                "declare an explicit color key for this source under background (mode color_key, colors, "
                "tolerance); a checkerboard or other accidental background is never removed automatically"
            )
        if rule["mode"] == "color_key" and key_match_count(spec) == 0:
            raise ConfigError(
                f"source {key}: the declared color key "
                + ", ".join(hex_text(color) for color in spec.colors)
                + f" with tolerance {spec.tolerance} matches no pixel"
            )
        result[key] = spec
    return result


def is_key(pixel: tuple[int, int, int, int], source: SourceSpec, cache: dict[Any, bool]) -> bool:
    cached = cache.get(pixel)
    if cached is not None:
        return cached
    match = any(key_distance(pixel, color) <= source.tolerance for color in source.colors)
    cache[pixel] = match
    return match


def key_match_count(source: SourceSpec) -> int:
    cache: dict[Any, bool] = {}
    total = 0
    with Image.open(source.path) as handle:
        rgba = handle.convert("RGBA")
        pixels = rgba.load()
        for y in range(rgba.height):
            for x in range(rgba.width):
                if is_key(pixels[x, y], source, cache):
                    total += 1
    return total


def apply_background(source: SourceSpec, crop: Image.Image) -> tuple[Image.Image, dict[str, Any]]:
    """Apply only the declared rule, report what was removed, then binarize alpha."""
    result = crop.copy()
    stats: dict[str, Any] = {
        "mode": source.mode,
        "removed_pixels": 0,
        "removed_enclosed_pixels": 0,
    }
    if source.mode == "color_key":
        cache: dict[Any, bool] = {}
        pixels = result.load()
        key_mask = _key_pixels(result, source, cache)
        original_alpha = {point: pixels[point[0], point[1]][3] for point in key_mask}
        for x, y in key_mask:
            pixel = pixels[x, y]
            pixels[x, y] = (pixel[0], pixel[1], pixel[2], 0)
        reachable = _flood_transparent(result, start="border")
        if source.scope == "border":
            kept = key_mask - reachable
            for x, y in kept:
                pixel = pixels[x, y]
                pixels[x, y] = (pixel[0], pixel[1], pixel[2], original_alpha[(x, y)])
            removed = key_mask - kept
        else:
            removed = key_mask
            stats["removed_enclosed_pixels"] = len(key_mask - reachable)
        stats["removed_pixels"] = len(removed)
    mask = result.getchannel("A").point(lambda value: 0 if value < ALPHA_THRESHOLD else 255)
    result.putalpha(mask)
    return result, stats


def _key_pixels(
    image: Image.Image, source: SourceSpec, cache: dict[Any, bool]
) -> set[tuple[int, int]]:
    pixels = image.load()
    found: set[tuple[int, int]] = set()
    for y in range(image.height):
        for x in range(image.width):
            if pixels[x, y][3] and is_key(pixels[x, y], source, cache):
                found.add((x, y))
    return found


def _flood_transparent(image: Image.Image, *, start: str) -> set[tuple[int, int]]:
    """4-connected flood over transparent pixels from the frame border."""
    width, height = image.size
    alpha = image.getchannel("A").load()
    visited: set[tuple[int, int]] = set()
    queue: collections.deque[tuple[int, int]] = collections.deque()
    seeds: list[tuple[int, int]] = []
    if start == "border":
        for x in range(width):
            seeds.append((x, 0))
            seeds.append((x, height - 1))
        for y in range(height):
            seeds.append((0, y))
            seeds.append((width - 1, y))
    for seed in seeds:
        if alpha[seed[0], seed[1]] == 0 and seed not in visited:
            visited.add(seed)
            queue.append(seed)
    while queue:
        x, y = queue.popleft()
        for next_x, next_y in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            if 0 <= next_x < width and 0 <= next_y < height:
                point = (next_x, next_y)
                if point not in visited and alpha[next_x, next_y] == 0:
                    visited.add(point)
                    queue.append(point)
    return visited


def round_half_up(value: float) -> int:
    return int(math.floor(value + 0.5))


def scale_nearest(image: Image.Image, scale: float) -> Image.Image:
    if scale == 1.0:
        return image.copy()
    width = max(1, round_half_up(image.width * scale))
    height = max(1, round_half_up(image.height * scale))
    return image.resize((width, height), Image.Resampling.NEAREST)


def apply_palette(
    image: Image.Image,
    palette: tuple[tuple[int, int, int, int], ...],
    cache: dict[Any, tuple[int, int, int, int]],
) -> tuple[Image.Image, int]:
    result = image.copy()
    pixels = result.load()
    palette_set = set(palette)
    remapped = 0
    for y in range(result.height):
        for x in range(result.width):
            pixel = pixels[x, y]
            if pixel[3] == 0 or pixel in palette_set:
                continue
            nearest = cache.get(pixel)
            if nearest is None:
                nearest = min(palette, key=lambda color: color_distance(pixel, color))
                cache[pixel] = nearest
            pixels[x, y] = nearest
            remapped += 1
    return result, remapped


def alpha_bbox(image: Image.Image) -> tuple[int, int, int, int] | None:
    alpha = image.getchannel("A")
    return alpha.point(lambda value: 255 if value >= ALPHA_THRESHOLD else 0).getbbox()


def alpha_bbox_xywh(image: Image.Image) -> list[int] | None:
    box = alpha_bbox(image)
    if box is None:
        return None
    return [box[0], box[1], box[2] - box[0], box[3] - box[1]]


def foreground_pixels(image: Image.Image) -> int:
    return sum(image.getchannel("A").histogram()[ALPHA_THRESHOLD:])


def touched_sides(bbox: list[int] | None, size: tuple[int, int]) -> list[str]:
    if bbox is None:
        return []
    x, y, width, height = bbox
    touched: list[str] = []
    if x == 0:
        touched.append("left")
    if y == 0:
        touched.append("top")
    if x + width == size[0]:
        touched.append("right")
    if y + height == size[1]:
        touched.append("bottom")
    return touched


def render_frame(
    source: SourceSpec,
    frame: FrameSpec,
    palette: tuple[tuple[int, int, int, int], ...],
    palette_cache: dict[Any, tuple[int, int, int, int]] | None = None,
) -> tuple[Image.Image, dict[str, Any]]:
    """Cut, clean, scale, limit and place one frame on its 48x48 cell."""
    x, y, width, height = frame.crop
    if x + width > source.width or y + height > source.height:
        raise ConfigError(
            f"frame {frame.id} crop {list(frame.crop)} is outside source "
            f"{source.key} ({source.width}x{source.height})"
        )
    with Image.open(source.path) as image:
        image.load()
        crop = image.convert("RGBA").crop((x, y, x + width, y + height))
    cleaned, stats = apply_background(source, crop)
    scaled = scale_nearest(cleaned, frame.scale)
    limited, remapped = apply_palette(scaled, palette, {} if palette_cache is None else palette_cache)

    anchor_x, anchor_y = frame.source_anchor
    placed_anchor = (round_half_up(anchor_x * frame.scale), round_half_up(anchor_y * frame.scale))
    paste = (ANCHOR[0] - placed_anchor[0], ANCHOR[1] - placed_anchor[1])
    if (
        paste[0] < 0
        or paste[1] < 0
        or paste[0] + limited.width > CELL_SIZE[0]
        or paste[1] + limited.height > CELL_SIZE[1]
    ):
        raise ConfigError(
            f"frame {frame.id}: the {limited.width}x{limited.height} scaled crop cannot be placed with its anchor "
            f"at {list(ANCHOR)} inside a {CELL_SIZE[0]}x{CELL_SIZE[1]} cell (paste origin {list(paste)}); "
            "adjust crop, source_anchor or scale"
        )

    cell = Image.new("RGBA", CELL_SIZE, (0, 0, 0, 0))
    cell.alpha_composite(limited, paste)
    foreground = foreground_pixels(cell)
    if foreground == 0:
        raise ConfigError(
            f"frame {frame.id} is empty after background handling "
            f"(crop {list(frame.crop)} of source {source.key})"
        )
    crop_bbox = alpha_bbox_xywh(limited)
    cell_bbox = alpha_bbox_xywh(cell)
    info: dict[str, Any] = {
        "paste": list(paste),
        "scaled_crop_size": [limited.width, limited.height],
        "placed_source_anchor": list(placed_anchor),
        "foreground_pixels": foreground,
        "bbox": cell_bbox,
        "crop_bbox": crop_bbox,
        "palette_remapped_pixels": remapped,
        "background_removed_pixels": stats["removed_pixels"],
        "background_removed_enclosed_pixels": stats["removed_enclosed_pixels"],
        "border_touches": {
            "crop": touched_sides(crop_bbox, (limited.width, limited.height)),
            "cell": touched_sides(cell_bbox, CELL_SIZE),
        },
        "opaque_crop": crop_bbox == [0, 0, limited.width, limited.height],
    }
    return cell, info


def _previous_artifact_paths(output: Path) -> list[Path]:
    """Paths the previous manifest owns in this output directory.

    The texture path is taken from the recorded artifact entries instead of a
    fixed filename, so a manifest built with a non-default ``texture_key``
    (for example ``enemies.png``) can still be replaced.
    """
    manifest_path = output / "manifest.json"
    if not manifest_path.is_file():
        return []
    manifest = load_json(manifest_path)
    artifacts = manifest.get("artifacts")
    if not isinstance(artifacts, list):
        raise ConfigError("existing manifest has no valid artifacts array")
    resolved_output = output.resolve()
    paths = [resolved_output / "manifest.json", resolved_output / "atlas.json"]
    if not any(
        isinstance(item, dict) and item.get("kind") == "texture" for item in artifacts
    ):
        # Older manifests without an explicit texture artifact keep the ranger
        # filename as the implied owner.
        paths.append(resolved_output / TEXTURE_FILENAME)
    for item in artifacts:
        if not isinstance(item, dict) or not isinstance(item.get("path"), str):
            raise ConfigError("existing manifest artifact entry has no path")
        candidate = Path(item["path"])
        if not candidate.is_absolute():
            candidate = resolved_output / candidate
        resolved = candidate.resolve()
        if resolved.parent != resolved_output:
            raise ConfigError(f"existing artifact escapes output directory: {item['path']}")
        paths.append(resolved)
    return list(dict.fromkeys(paths))


def guard_output(output: Path, replace_generated: bool, texture_filename: str = TEXTURE_FILENAME) -> None:
    if not isinstance(texture_filename, str) or Path(texture_filename).name != texture_filename:
        raise ConfigError(f"texture filename must stay inside the output directory: {texture_filename!r}")
    # The texture this build is about to write is owned by this build, even when
    # the previous manifest named it differently.
    common.guard_generated_output(
        output,
        replace_generated,
        _previous_artifact_paths,
        ConfigError,
        extra_allowed=[output.resolve() / texture_filename],
    )


json_write = common.write_json


def external_sources(
    config: dict[str, Any], sources: dict[str, SourceSpec], config_path: Path
) -> list[str]:
    directory = config_path.resolve().parent
    return [key for key, source in sources.items() if not is_inside(source.path, directory)]


def require_disclosure(config: dict[str, Any], external: Iterable[str]) -> None:
    disclosure = config.get("disclosure", {})
    missing = [key for key in external if key not in disclosure]
    if missing:
        raise ConfigError(
            "sources outside the recipe directory reuse pre-existing files and must be disclosed: "
            + ", ".join(missing)
            + "; add a disclosure entry for each of them, for example disclosure.{"
            + missing[0]
            + "} = \"pre-existing accepted art reused verbatim\""
        )


def animation_report(
    animations: list[AnimationSpec], cells: dict[str, Image.Image], frames: list[FrameSpec]
) -> tuple[dict[str, Any], list[list[str]]]:
    by_id = {frame.id: frame for frame in frames}
    digests = {
        frame_id: hashlib.sha256(cell.tobytes()).hexdigest() for frame_id, cell in cells.items()
    }
    report: dict[str, Any] = {}
    for animation in animations:
        seen: dict[str, str] = {}
        duplicates: list[list[str]] = []
        for frame_id in animation.frames:
            digest = digests[frame_id]
            if digest in seen:
                duplicates.append([seen[digest], frame_id])
            else:
                seen[digest] = frame_id
        if duplicates:
            raise ConfigError(
                f"animation {animation.id} contains pixel-identical frames: "
                + ", ".join(f"{pair[0]}={pair[1]}" for pair in duplicates)
                + " (a repeated frame is a fake animation)"
            )
        first = by_id[animation.frames[0]]
        report[animation.id] = {
            "frames": list(animation.frames),
            "fps": animation.fps,
            "loop": animation.loop,
            "action": first.action,
            "facing": first.facing,
            "frame_count": len(animation.frames),
            "distinct_pixel_frames": len(seen),
            "duplicate_pixel_frames": [],
        }
    groups: dict[str, list[str]] = {}
    for frame_id, digest in digests.items():
        groups.setdefault(digest, []).append(frame_id)
    cross_duplicates = [sorted(group) for group in groups.values() if len(group) > 1]
    return report, cross_duplicates


def build_artifacts(config_path: Path, output: Path, *, replace_generated: bool = False) -> dict[str, Any]:
    config_path = config_path.resolve()
    output = output.resolve()
    config = load_json(config_path)
    validate_config(config)
    texture_id, texture_filename = texture_spec(config)
    palette = parse_palette(config)
    frames = validate_frames(config)
    animations = validate_animations(config, frames)
    sources = load_sources(config)
    external = external_sources(config, sources, config_path)
    require_disclosure(config, external)

    columns = config["columns"]
    palette_cache: dict[Any, tuple[int, int, int, int]] = {}
    cells: dict[str, Image.Image] = {}
    frame_report: list[dict[str, Any]] = []
    for index, frame in enumerate(frames):
        cell, info = render_frame(sources[frame.source], frame, palette, palette_cache)
        cells[frame.id] = cell
        row, column = divmod(index, columns)
        entry: dict[str, Any] = {
            "id": frame.id,
            "source": frame.source,
            "crop": list(frame.crop),
            "source_anchor": list(frame.source_anchor),
            "scale": frame.scale,
            "action": frame.action,
            "facing": frame.facing,
            "cell": [column, row],
            "rect": [column * CELL_SIZE[0], row * CELL_SIZE[1], CELL_SIZE[0], CELL_SIZE[1]],
            "reused_source": frame.source in external,
        }
        entry.update(info)
        frame_report.append(entry)

    animation_stats, cross_duplicates = animation_report(animations, cells, frames)
    animation_index: dict[str, list[str]] = {}
    for animation in animations:
        for frame_id in animation.frames:
            animation_index.setdefault(frame_id, []).append(animation.id)
    for entry in frame_report:
        entry["animations"] = animation_index.get(entry["id"], [])

    rows = math.ceil(len(frames) / columns)
    width = columns * CELL_SIZE[0]
    height = rows * CELL_SIZE[1]
    canvas = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    for entry in frame_report:
        column, row = entry["cell"]
        canvas.alpha_composite(cells[entry["id"]], (column * CELL_SIZE[0], row * CELL_SIZE[1]))

    guard_output(output, replace_generated, texture_filename)
    output.mkdir(parents=True, exist_ok=True)
    texture_path = output / texture_filename
    canvas.save(texture_path, format="PNG", optimize=False)

    prefix = config["resource_prefix"].rstrip("/")
    atlas: dict[str, Any] = {
        "schema_version": SCHEMA_VERSION,
        "native_view": list(NATIVE_VIEW),
        "cell_size": list(CELL_SIZE),
        "sprites": {
            entry["id"]: {
                "texture": texture_id,
                "rect": list(entry["rect"]),
                "anchor": list(ANCHOR),
            }
            for entry in frame_report
        },
        "textures": {
            texture_id: {
                "path": f"{prefix}/{texture_filename}",
                "width": width,
                "height": height,
            }
        },
        "animations": {
            animation.id: {
                "frames": list(animation.frames),
                "fps": animation.fps,
                "loop": animation.loop,
            }
            for animation in animations
        },
        "action_semantics": {
            animation.id: {
                "action": animation_stats[animation.id]["action"],
                "facing": animation_stats[animation.id]["facing"],
                "fps": animation.fps,
                "loop": animation.loop,
                "frame_count": animation_stats[animation.id]["frame_count"],
                "distinct_pixel_frames": animation_stats[animation.id]["distinct_pixel_frames"],
                "cell_size": list(CELL_SIZE),
                "anchor": list(ANCHOR),
            }
            for animation in animations
        },
    }
    if config.get("disclosure"):
        atlas["source_disclosure"] = dict(config["disclosure"])
    atlas_path = output / "atlas.json"
    json_write(atlas_path, atlas)

    artifacts = [
        {
            "kind": "texture",
            "texture": texture_id,
            "path": str(texture_path),
            "sha256": sha256_file(texture_path),
            "bytes": texture_path.stat().st_size,
        },
        {
            "kind": "atlas_contract",
            "path": str(atlas_path),
            "sha256": sha256_file(atlas_path),
            "bytes": atlas_path.stat().st_size,
        },
    ]
    source_report: dict[str, Any] = {}
    for key, source in sources.items():
        entry = {
            "path": str(source.path),
            "sha256": source.sha256,
            "width": source.width,
            "height": source.height,
            "transparent_pixels": source.transparent_pixels,
            "background": {
                "mode": source.mode,
                "colors": [hex_text(color) for color in source.colors],
                "tolerance": source.tolerance,
                "scope": source.scope,
            },
            "external_to_recipe_dir": key in external,
        }
        if source.mode == "color_key":
            matches = key_match_count(source)
            entry["background"]["matched_pixels"] = matches
            entry["background"]["matched_ratio"] = round(
                matches / float(source.width * source.height), 4
            )
        source_report[key] = entry
    manifest = {
        "schema_version": SCHEMA_VERSION,
        "pipeline": PIPELINE,
        "config_path": str(config_path),
        "config_sha256": sha256_file(config_path),
        "resource_prefix": config["resource_prefix"],
        "native_view": list(NATIVE_VIEW),
        "cell_size": list(CELL_SIZE),
        "anchor": list(ANCHOR),
        "columns": columns,
        "palette": [hex_text(color) for color in palette],
        "sources": source_report,
        "external_sources": external,
        "disclosure": dict(config.get("disclosure", {})),
        "scale_by_source": {
            key: sorted({frame.scale for frame in frames if frame.source == key})[0] for key in sources
        },
        "texture": {
            "id": texture_id,
            "path": f"{prefix}/{texture_filename}",
            "width": width,
            "height": height,
            "columns": columns,
            "rows": rows,
        },
        "frames": frame_report,
        "animations": animation_stats,
        "orphan_frames": [frame.id for frame in frames if frame.id not in animation_index],
        "duplicate_pixel_frames": cross_duplicates,
        "artifacts": artifacts,
        "technical_verification": {
            "status": "pending_external_verify",
            "scope": "mechanical output properties only; not visual approval",
        },
    }
    json_write(output / "manifest.json", manifest)
    return manifest


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", required=True, type=Path, help="recipe JSON path")
    parser.add_argument("--output", required=True, type=Path, help="version output directory")
    parser.add_argument(
        "--replace-generated",
        action="store_true",
        help="replace only exact paths owned by the previous manifest",
    )
    args = parser.parse_args(argv)
    try:
        manifest = build_artifacts(args.config, args.output, replace_generated=args.replace_generated)
    except (ConfigError, OSError, ValueError) as exc:
        print(f"BUILD FAILED: {exc}", file=sys.stderr)
        return 1
    texture = manifest["texture"]
    print(
        json.dumps(
            {
                "output": str(args.output),
                "artifacts": len(manifest["artifacts"]),
                "animations": len(manifest["animations"]),
                "frames": len(manifest["frames"]),
                "texture": f"{texture['width']}x{texture['height']}",
            },
            sort_keys=True,
        )
    )
    remapped = [entry for entry in manifest["frames"] if entry["palette_remapped_pixels"]]
    if remapped:
        print(
            "warning: pixels were snapped to the nearest palette color, so those frames are not verbatim "
            "copies of their source: "
            + ", ".join(f"{entry['id']}({entry['palette_remapped_pixels']})" for entry in remapped),
            file=sys.stderr,
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
