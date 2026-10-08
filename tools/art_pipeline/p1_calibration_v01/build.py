#!/usr/bin/env python3
"""Build the P1 calibration art atlases from configured absolute PNG sources."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import sys
from collections import deque
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable

from PIL import Image


REQUIRED_TOP_LEVEL = (
    "schema_version",
    "resource_prefix",
    "native_view",
    "palette",
    "sources",
    "atlases",
    "sprites",
    "animations",
)
BACKGROUND_MODES = {"alpha", "edge_colors", "color_key", "opaque"}
ALPHA_THRESHOLD = 128


class ConfigError(ValueError):
    """Raised when a recipe or source cannot be processed unambiguously."""


@dataclass(frozen=True)
class SourceSpec:
    key: str
    path: Path
    grid: tuple[int, int]
    mode: str
    colors: tuple[tuple[int, int, int, int], ...]
    tolerance: float
    sha256: str
    width: int
    height: int


@dataclass(frozen=True)
class SpriteSpec:
    id: str
    source: str
    cell: tuple[int, int]
    atlas: str
    anchor: tuple[int, int]
    fit: tuple[int, int]
    crop: tuple[int, int, int, int] | None
    facing: str | None
    state: str | None
    palette: tuple[tuple[int, int, int, int], ...] | None
    scale_group: str | None
    keep_rows: tuple[int, int] | None

    @property
    def sort_key(self) -> tuple[str, str]:
        return (self.atlas, self.id)


@dataclass
class PreparedSprite:
    spec: SpriteSpec
    image: Image.Image
    scale_factor: float


@dataclass
class PlacedSprite:
    spec: SpriteSpec
    rect: tuple[int, int, int, int]


def _require_int_pair(value: Any, name: str, *, minimum: int = 1) -> tuple[int, int]:
    if not isinstance(value, list) or len(value) != 2:
        raise ConfigError(f"{name} must be [x,y]")
    if any(isinstance(item, bool) or not isinstance(item, int) for item in value):
        raise ConfigError(f"{name} entries must be integers")
    if any(item < minimum for item in value):
        raise ConfigError(f"{name} entries must be >= {minimum}")
    return value[0], value[1]


def _optional_int_pair(
    value: Any, name: str, *, minimum: int = 0
) -> tuple[int, int] | None:
    return None if value is None else _require_int_pair(value, name, minimum=minimum)


def _require_rect(value: Any, name: str) -> tuple[int, int, int, int]:
    if not isinstance(value, list) or len(value) != 4:
        raise ConfigError(f"{name} must be [x,y,w,h]")
    if any(isinstance(item, bool) or not isinstance(item, int) for item in value):
        raise ConfigError(f"{name} entries must be integers")
    x, y, width, height = value
    if width <= 0 or height <= 0 or x < 0 or y < 0:
        raise ConfigError(f"{name} must have non-negative origin and positive size")
    return x, y, width, height


def parse_hex_color(value: Any, name: str) -> tuple[int, int, int, int]:
    if not isinstance(value, str):
        raise ConfigError(f"{name} must be a hex string")
    cleaned = value.strip()
    lengths = {4, 5, 7, 9}
    if len(cleaned) not in lengths or cleaned[0] != "#":
        raise ConfigError(f"{name} must be #RGB, #RGBA, #RRGGBB, or #RRGGBBAA")
    try:
        hex_digits = cleaned[1:]
        if len(hex_digits) in (3, 4):
            hex_digits = ''.join(char * 2 for char in hex_digits)
        digits = bytes.fromhex(hex_digits)
    except ValueError as exc:
        raise ConfigError(f"{name} is not valid hex") from exc
    if len(digits) == 1:
        return digits[0], digits[0], digits[0], 255
    if len(digits) == 2:
        return digits[0], digits[0], digits[0], digits[1]
    if len(digits) == 3:
        return digits[0], digits[1], digits[2], 255
    return digits[0], digits[1], digits[2], digits[3]


def _color_distance(left: tuple[int, int, int, int], right: tuple[int, int, int, int]) -> float:
    channels = zip(left, right)
    squared = sum((a - b) * (a - b) for a, b in channels)
    return math.sqrt(squared / 4.0)


def _background_distance(left: tuple[int, int, int, int], right: tuple[int, int, int, int]) -> float:
    return math.sqrt(sum((a - b) * (a - b) for a, b in zip(left[:3], right[:3])))


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _load_json(path: Path) -> dict[str, Any]:
    try:
        with path.open("r", encoding="utf-8") as handle:
            value = json.load(handle)
    except (OSError, json.JSONDecodeError) as exc:
        raise ConfigError(f"cannot read config {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise ConfigError("config root must be an object")
    return value


def validate_config(config: dict[str, Any]) -> None:
    missing = [key for key in REQUIRED_TOP_LEVEL if key not in config]
    if missing:
        raise ConfigError(f"missing config keys: {', '.join(missing)}")
    if config["schema_version"] != 1:
        raise ConfigError("schema_version must be 1")
    native = _require_int_pair(config["native_view"], "native_view")
    if native != (640, 360):
        raise ConfigError("native_view must be [640,360] for this pipeline version")
    if not isinstance(config["resource_prefix"], str) or not config["resource_prefix"].startswith("res://"):
        raise ConfigError("resource_prefix must be a res:// path")
    if not isinstance(config["palette"], list) or not config["palette"]:
        raise ConfigError("palette must be a non-empty array")
    global_palette = {parse_hex_color(item, f"palette[{index}]") for index, item in enumerate(config["palette"])}
    if len(global_palette) != len(config["palette"]):
        raise ConfigError("palette contains duplicate colors")

    if not isinstance(config["sources"], dict) or not config["sources"]:
        raise ConfigError("sources must be a non-empty object")
    for key, raw in config["sources"].items():
        if not isinstance(raw, dict):
            raise ConfigError(f"sources.{key} must be an object")
        source_path = raw.get("path")
        if not isinstance(source_path, str) or not Path(source_path).is_absolute():
            raise ConfigError(f"sources.{key}.path must be an absolute path")
        _require_int_pair(raw.get("grid"), f"sources.{key}.grid")
        background = raw.get("background")
        if not isinstance(background, dict):
            raise ConfigError(f"sources.{key}.background must be an object")
        mode = background.get("mode")
        if mode not in BACKGROUND_MODES:
            raise ConfigError(f"sources.{key}.background.mode is unsupported: {mode}")
        colors = background.get("colors", [])
        if not isinstance(colors, list):
            raise ConfigError(f"sources.{key}.background.colors must be an array")
        if mode == "color_key" and not colors:
            raise ConfigError(f"sources.{key}.background.colors is required for color_key")
        for index, color in enumerate(colors):
            parse_hex_color(color, f"sources.{key}.background.colors[{index}]")
        tolerance = background.get("tolerance", 0.0)
        if isinstance(tolerance, bool) or not isinstance(tolerance, (int, float)):
            raise ConfigError(f"sources.{key}.background.tolerance must be numeric")
        if not 0 <= float(tolerance) <= 255:
            raise ConfigError(f"sources.{key}.background.tolerance must be in [0,255]")

    if not isinstance(config["atlases"], dict) or not config["atlases"]:
        raise ConfigError("atlases must be a non-empty object")
    for key, raw in config["atlases"].items():
        if not isinstance(raw, dict):
            raise ConfigError(f"atlases.{key} must be an object")
        _require_int_pair(raw.get("cell_size"), f"atlases.{key}.cell_size")
        columns = raw.get("columns")
        if isinstance(columns, bool) or not isinstance(columns, int) or columns < 1:
            raise ConfigError(f"atlases.{key}.columns must be a positive integer")
        padding = raw.get("padding", 2)
        if isinstance(padding, bool) or not isinstance(padding, int) or padding < 0:
            raise ConfigError(f"atlases.{key}.padding must be an integer >= 0")

    if not isinstance(config["sprites"], list) or not config["sprites"]:
        raise ConfigError("sprites must be a non-empty array")
    seen_sprites: set[str] = set()
    for index, raw in enumerate(config["sprites"]):
        name = f"sprites[{index}]"
        if not isinstance(raw, dict):
            raise ConfigError(f"{name} must be an object")
        sprite_id = raw.get("id")
        if not isinstance(sprite_id, str) or not sprite_id:
            raise ConfigError(f"{name}.id must be a non-empty string")
        if sprite_id in seen_sprites:
            raise ConfigError(f"duplicate sprite id: {sprite_id}")
        seen_sprites.add(sprite_id)
        source = raw.get("source")
        if source not in config["sources"]:
            raise ConfigError(f"{name}.source is not defined: {source}")
        atlas = raw.get("atlas")
        if atlas not in config["atlases"]:
            raise ConfigError(f"{name}.atlas is not defined: {atlas}")
        _require_int_pair(raw.get("cell"), f"{name}.cell", minimum=0)
        _optional_int_pair(raw.get("anchor"), f"{name}.anchor", minimum=0)
        _require_int_pair(raw.get("fit"), f"{name}.fit")
        if raw.get("crop") is not None:
            _require_rect(raw.get("crop"), f"{name}.crop")
        palette = raw.get("palette")
        if palette is not None:
            if not isinstance(palette, list) or not palette:
                raise ConfigError(f"{name}.palette must be a non-empty array when present")
            parsed = {parse_hex_color(item, f"{name}.palette[{pos}]") for pos, item in enumerate(palette)}
            if not parsed.issubset(global_palette):
                raise ConfigError(f"{name}.palette must be a subset of the global palette")
        keep_rows = raw.get("keep_rows")
        if keep_rows is not None:
            pair = _optional_int_pair(keep_rows, f"{name}.keep_rows", minimum=0)
            assert pair is not None
            if pair[0] > pair[1]:
                raise ConfigError(f"{name}.keep_rows must be ordered [minY,maxY]")

    if not isinstance(config["animations"], dict):
        raise ConfigError("animations must be an object")
    for animation_id, raw in config["animations"].items():
        if not isinstance(raw, dict):
            raise ConfigError(f"animations.{animation_id} must be an object")
        frames = raw.get("frames")
        if not isinstance(frames, list) or not frames:
            raise ConfigError(f"animations.{animation_id}.frames must be a non-empty array")
        for frame in frames:
            if frame not in seen_sprites:
                raise ConfigError(f"animations.{animation_id} references unknown sprite: {frame}")
        fps = raw.get("fps")
        if isinstance(fps, bool) or not isinstance(fps, int) or fps < 1:
            raise ConfigError(f"animations.{animation_id}.fps must be a positive integer")
        if not isinstance(raw.get("loop"), bool):
            raise ConfigError(f"animations.{animation_id}.loop must be boolean")


def _load_sources(config: dict[str, Any]) -> dict[str, SourceSpec]:
    result: dict[str, SourceSpec] = {}
    for key, raw in config["sources"].items():
        path = Path(raw["path"])
        if not path.is_file():
            raise ConfigError(f"source PNG does not exist: {path}")
        try:
            with Image.open(path) as image:
                image.load()
                width, height = image.size
        except (OSError, ValueError) as exc:
            raise ConfigError(f"cannot open source PNG {path}: {exc}") from exc
        colors = tuple(
            parse_hex_color(item, f"sources.{key}.background.colors[{index}]")
            for index, item in enumerate(raw.get("background", {}).get("colors", []))
        )
        tolerance = float(raw.get("background", {}).get("tolerance", 0.0))
        result[key] = SourceSpec(
            key=key,
            path=path,
            grid=tuple(raw["grid"]),
            mode=raw["background"]["mode"],
            colors=colors,
            tolerance=tolerance,
            sha256=_sha256_file(path),
            width=width,
            height=height,
        )
    return result


def _cell_bounds(source: SourceSpec, cell: tuple[int, int], crop: tuple[int, int, int, int] | None) -> tuple[int, int, int, int]:
    if crop is not None:
        x, y, width, height = crop
    else:
        columns, rows = source.grid
        cell_x, cell_y = cell
        if cell_x >= columns or cell_y >= rows:
            raise ConfigError(
                f"cell {cell} is outside source {source.key} grid {source.grid}"
            )
        width = source.width // columns
        height = source.height // rows
        x = cell_x * width
        y = cell_y * height
    if x + width > source.width or y + height > source.height:
        raise ConfigError(f"cell or crop is outside source {source.key} image bounds")
    if width <= 0 or height <= 0:
        raise ConfigError(f"source {source.key} produced an empty cell")
    return x, y, width, height


def _near_any(
    pixel: tuple[int, int, int, int], colors: Iterable[tuple[int, int, int, int]], tolerance: float
) -> bool:
    return any(_background_distance(pixel, color) <= tolerance for color in colors)


def _remove_alpha(image: Image.Image) -> Image.Image:
    alpha = image.getchannel("A")
    mask = alpha.point(lambda value: 0 if value < ALPHA_THRESHOLD else 255)
    result = image.copy()
    result.putalpha(mask)
    return result


def _remove_color_key(
    image: Image.Image, colors: tuple[tuple[int, int, int, int], ...], tolerance: float
) -> Image.Image:
    result = image.copy()
    pixels = result.load()
    width, height = result.size
    for y in range(height):
        for x in range(width):
            if _near_any(pixels[x, y], colors, tolerance):
                pixel = pixels[x, y]
                pixels[x, y] = (pixel[0], pixel[1], pixel[2], 0)
    return _remove_alpha(result)


def _remove_edge_colors(
    image: Image.Image, colors: tuple[tuple[int, int, int, int], ...], tolerance: float
) -> Image.Image:
    width, height = image.size
    pixels = image.load()
    visited = bytearray(width * height)
    queue: deque[tuple[int, int]] = deque()

    def push(x: int, y: int) -> None:
        offset = y * width + x
        if visited[offset]:
            return
        visited[offset] = 1
        if pixels[x, y][3] < ALPHA_THRESHOLD or _near_any(pixels[x, y], colors, tolerance):
            queue.append((x, y))

    for x in range(width):
        push(x, 0)
        push(x, height - 1)
    for y in range(height):
        push(0, y)
        push(width - 1, y)

    result = image.copy()
    output = result.load()
    while queue:
        x, y = queue.popleft()
        pixel = output[x, y]
        output[x, y] = (pixel[0], pixel[1], pixel[2], 0)
        for next_x, next_y in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            if 0 <= next_x < width and 0 <= next_y < height:
                offset = next_y * width + next_x
                if not visited[offset]:
                    push(next_x, next_y)

    # A second alpha threshold pass guarantees binary output even if the source
    # had semi-transparent foreground pixels away from the flooded border.
    return _remove_alpha(result)


def _clean_background(source: SourceSpec, image: Image.Image) -> Image.Image:
    if source.mode == "alpha":
        return _remove_alpha(image)
    if source.mode == "color_key":
        return _remove_color_key(image, source.colors, source.tolerance)
    if source.mode == "edge_colors":
        return _remove_edge_colors(image, source.colors, source.tolerance)
    return image.copy()


def _alpha_bbox(image: Image.Image) -> tuple[int, int, int, int] | None:
    alpha = image.getchannel("A")
    mask = alpha.point(lambda value: 255 if value >= ALPHA_THRESHOLD else 0)
    return mask.getbbox()


def _apply_palette(
    image: Image.Image, palette: tuple[tuple[int, int, int, int], ...]
) -> Image.Image:
    result = image.copy()
    pixels = result.load()
    width, height = result.size
    for y in range(height):
        for x in range(width):
            pixel = pixels[x, y]
            if pixel[3] < ALPHA_THRESHOLD:
                continue
            if pixel not in palette:
                nearest = min(palette, key=lambda color: _color_distance(pixel, color))
                pixels[x, y] = nearest
    return result


def _keep_native_rows(image: Image.Image, rows: tuple[int, int]) -> Image.Image:
    _, height = image.size
    top = min(max(rows[0], 0), height)
    bottom = min(max(rows[1], top), height)
    result = Image.new("RGBA", image.size, (0, 0, 0, 0))
    result.paste(image.crop((0, top, image.width, bottom)), (0, top))
    return result


def _nearest_resize(image: Image.Image, factor: float) -> Image.Image:
    if factor == 1.0:
        return image.copy()
    width = max(1, int(image.width / factor))
    height = max(1, int(image.height / factor))
    return image.resize((width, height), Image.Resampling.NEAREST)


def _prepare_sprites(config: dict[str, Any], sources: dict[str, SourceSpec]) -> list[PreparedSprite]:
    global_palette = tuple(dict.fromkeys(parse_hex_color(item, f"palette[{i}]") for i, item in enumerate(config["palette"])))
    staged: list[tuple[SpriteSpec, Image.Image]] = []
    for index, raw in enumerate(config["sprites"]):
        source = sources[raw["source"]]
        bounds = _cell_bounds(source, tuple(raw["cell"]), raw.get("crop"))
        with Image.open(source.path) as source_image:
            source_image.load()
            x, y, width, height = bounds
            cell_image = source_image.convert("RGBA").crop((x, y, x + width, y + height))
        cleaned = _clean_background(source, cell_image)
        palette = tuple(parse_hex_color(item, f"sprites[{index}].palette[{pos}]") for pos, item in enumerate(raw.get("palette", config["palette"])))
        if source.mode == "opaque":
            trimmed = cleaned
        else:
            bbox = _alpha_bbox(cleaned)
            if bbox is None:
                raise ConfigError(f"sprite {raw['id']} is empty after background cleanup")
            trimmed = cleaned.crop(bbox)
        staged.append(
            (
                SpriteSpec(
                    id=raw["id"],
                    source=raw["source"],
                    cell=tuple(raw["cell"]),
                    atlas=raw["atlas"],
                    anchor=tuple(raw["anchor"]),
                    fit=tuple(raw["fit"]),
                    crop=raw.get("crop"),
                    facing=raw.get("facing"),
                    state=raw.get("state"),
                    palette=palette,
                    scale_group=raw.get("scale_group"),
                    keep_rows=tuple(raw["keep_rows"]) if raw.get("keep_rows") is not None else None,
                ),
                trimmed,
            )
        )

    factors: dict[str, float] = {}
    groups: dict[str, list[tuple[SpriteSpec, Image.Image]]] = {}
    for spec, image in staged:
        if spec.scale_group is None:
            continue
        groups.setdefault(spec.scale_group, []).append((spec, image))
    for group, members in groups.items():
        factor = max(
            max(image.width / spec.fit[0], image.height / spec.fit[1])
            for spec, image in members
        )
        factors[group] = factor

    prepared: list[PreparedSprite] = []
    for spec, image in staged:
        factor = factors.get(
            spec.scale_group,
            max(image.width / spec.fit[0], image.height / spec.fit[1]),
        )
        fitted = _apply_palette(_nearest_resize(image, factor), spec.palette or global_palette)
        prepared.append(PreparedSprite(spec, fitted, factor))
    return prepared


def _atlas_geometry(config: dict[str, Any], key: str, count: int) -> tuple[int, int, int, int, int]:
    spec = config["atlases"][key]
    cell_width, cell_height = spec["cell_size"]
    columns = spec["columns"]
    padding = spec.get("padding", 2)
    rows = math.ceil(count / columns)
    return cell_width, cell_height, columns, rows, padding


def _compose_atlases(
    config: dict[str, Any], prepared: list[PreparedSprite]
) -> tuple[dict[str, Image.Image], dict[str, dict[str, PlacedSprite]]]:
    grouped: dict[str, list[PreparedSprite]] = {}
    for item in prepared:
        grouped.setdefault(item.spec.atlas, []).append(item)

    images: dict[str, Image.Image] = {}
    placements: dict[str, dict[str, PlacedSprite]] = {}
    for atlas_key in config["atlases"]:
        members = grouped.get(atlas_key, [])
        cell_width, cell_height, columns, _, padding = _atlas_geometry(config, atlas_key, len(members))
        rows = math.ceil(len(members) / columns) if members else 1
        width = columns * cell_width
        height = rows * cell_height
        canvas = Image.new("RGBA", (width, height), (0, 0, 0, 0))
        placed: dict[str, PlacedSprite] = {}
        for index, item in enumerate(members):
            row, column = divmod(index, columns)
            sprite = item.image
            if sprite.width > cell_width or sprite.height > cell_height:
                raise ConfigError(
                    f"sprite {item.spec.id} is {sprite.width}x{sprite.height}, exceeding atlas cell {cell_width}x{cell_height}"
                )
            cell_x = column * cell_width
            cell_y = row * cell_height
            anchor_x, anchor_y = item.spec.anchor
            x = cell_x + anchor_x - sprite.width // 2
            y = cell_y + anchor_y - sprite.height
            if (
                x < cell_x + padding
                or y < cell_y + padding
                or x + sprite.width > cell_x + cell_width - padding
                or y + sprite.height > cell_y + cell_height - padding
            ):
                raise ConfigError(
                    f"sprite {item.spec.id} placed at anchor {item.spec.anchor} does not fit its atlas cell"
                )
            cell_image = Image.new("RGBA", (cell_width, cell_height), (0, 0, 0, 0))
            cell_image.alpha_composite(sprite, (x - cell_x, y - cell_y))
            if item.spec.keep_rows is not None:
                cell_image = _keep_native_rows(cell_image, item.spec.keep_rows)
            canvas.alpha_composite(cell_image, (cell_x, cell_y))
            placed[item.spec.id] = PlacedSprite(item.spec, (cell_x, cell_y, cell_width, cell_height))
        images[atlas_key] = canvas
        placements[atlas_key] = placed
    return images, placements


def _contact_sheet(
    atlases: dict[str, Image.Image], grayscale: bool = True, preview_scale: float = 1.0
) -> Image.Image:
    ordered = [atlases[key] for key in sorted(atlases)]
    max_width = max(image.width for image in ordered)
    total_height = sum(image.height for image in ordered)
    canvas = Image.new("RGBA", (max_width * 2, total_height), (128, 128, 128, 255))
    y = 0
    for image in ordered:
        canvas.alpha_composite(image, (0, y))
        if grayscale:
            gray = image.convert("LA").convert("RGBA")
            gray.putalpha(image.getchannel("A"))
            canvas.alpha_composite(gray, (max_width, y))
        y += image.height
    if preview_scale and preview_scale > 0 and preview_scale < 1:
        canvas = canvas.resize(
            (max(1, int(canvas.width * preview_scale)), max(1, int(canvas.height * preview_scale))),
            Image.Resampling.NEAREST,
        )
    return canvas


def _json_write(path: Path, value: Any) -> None:
    with path.open("w", encoding="utf-8") as handle:
        json.dump(value, handle, ensure_ascii=False, indent=2, sort_keys=True)
        handle.write("\n")


def _build_atlas_contract(
    config: dict[str, Any], images: dict[str, Image.Image], placements: dict[str, dict[str, PlacedSprite]]
) -> dict[str, Any]:
    textures = {
        key: {"path": f"{config['resource_prefix'].rstrip('/')}/{key}.png", "width": image.width, "height": image.height}
        for key, image in images.items()
    }
    sprites: dict[str, Any] = {}
    for atlas_key, placed in placements.items():
        for sprite_id, placement in placed.items():
            spec = placement.spec
            entry: dict[str, Any] = {
                "texture": atlas_key,
                "rect": list(placement.rect),
                "anchor": list(spec.anchor),
            }
            if spec.facing is not None:
                entry["facing"] = spec.facing
            if spec.state is not None:
                entry["state"] = spec.state
            if spec.keep_rows is not None:
                entry["keep_rows"] = list(spec.keep_rows)
            sprites[sprite_id] = entry
    animations = {
        key: {"frames": list(raw["frames"]), "fps": raw["fps"], "loop": raw["loop"]}
        for key, raw in config["animations"].items()
    }
    return {
        "schema_version": 1,
        "native_view": list(config["native_view"]),
        "textures": textures,
        "sprites": sprites,
        "animations": animations,
    }


def _previous_artifact_paths(output: Path) -> list[Path]:
    manifest_path = output / "manifest.json"
    if not manifest_path.is_file():
        return []
    try:
        manifest = _load_json(manifest_path)
    except ConfigError as exc:
        raise ConfigError(f"cannot safely replace existing manifest: {exc}") from exc
    artifacts = manifest.get("artifacts")
    if not isinstance(artifacts, list):
        raise ConfigError("existing manifest has no valid artifacts array")
    paths: list[Path] = []
    output = output.resolve()
    for item in artifacts:
        if not isinstance(item, dict) or not isinstance(item.get("path"), str):
            raise ConfigError("existing manifest artifact entry has no path")
        candidate = Path(item["path"])
        if not candidate.is_absolute():
            candidate = output / candidate
        try:
            resolved = candidate.resolve()
        except OSError as exc:
            raise ConfigError(f"cannot resolve existing artifact path: {candidate}") from exc
        if resolved.parent != output:
            raise ConfigError(f"existing artifact escapes output directory: {item['path']}")
        paths.append(resolved)
    paths.extend([output / "manifest.json", output / "atlas.json", output / "contact_sheet.png"])
    return list(dict.fromkeys(paths))


def _guard_output(output: Path, replace_generated: bool) -> None:
    if not output.exists():
        return
    if not output.is_dir():
        raise ConfigError(f"output exists and is not a directory: {output}")
    existing = [item for item in output.iterdir()]
    if not existing:
        return
    if not replace_generated:
        raise ConfigError(f"output directory is not empty: {output}; use --replace-generated for manifest-owned paths only")
    allowed = {path.resolve() for path in _previous_artifact_paths(output)}
    for item in existing:
        resolved = item.resolve()
        if resolved not in allowed:
            raise ConfigError(f"refusing to replace unmanaged output entry: {item}")
        if item.is_symlink():
            raise ConfigError(f"refusing to replace symlinked output entry: {item}")


def build_artifacts(config_path: Path, output: Path, *, replace_generated: bool = False) -> dict[str, Any]:
    config_path = config_path.resolve()
    output = output.resolve()
    config = _load_json(config_path)
    validate_config(config)
    sources = _load_sources(config)
    prepared = _prepare_sprites(config, sources)
    images, placements = _compose_atlases(config, prepared)
    _guard_output(output, replace_generated)
    output.mkdir(parents=True, exist_ok=True)

    texture_artifacts: list[dict[str, Any]] = []
    for key in sorted(images):
        artifact = output / f"{key}.png"
        images[key].save(artifact, format="PNG", optimize=False)
        texture_artifacts.append(
            {
                "kind": "texture",
                "atlas": key,
                "path": str(artifact),
                "sha256": _sha256_file(artifact),
                "bytes": artifact.stat().st_size,
            }
        )

    atlas_path = output / "atlas.json"
    atlas_contract = _build_atlas_contract(config, images, placements)
    _json_write(atlas_path, atlas_contract)
    contact_path = output / "contact_sheet.png"
    _contact_sheet(images).save(contact_path, format="PNG", optimize=False)

    artifacts = [
        *texture_artifacts,
        {
            "kind": "atlas_contract",
            "path": str(atlas_path),
            "sha256": _sha256_file(atlas_path),
            "bytes": atlas_path.stat().st_size,
        },
        {
            "kind": "contact_sheet",
            "path": str(contact_path),
            "sha256": _sha256_file(contact_path),
            "bytes": contact_path.stat().st_size,
        },
    ]
    manifest = {
        "schema_version": 1,
        "config_path": str(config_path.resolve()),
        "config_sha256": _sha256_file(config_path),
        "resource_prefix": config["resource_prefix"],
        "sources": {
            key: {
                "path": str(source.path),
                "sha256": source.sha256,
                "width": source.width,
                "height": source.height,
                "grid": list(source.grid),
                "background": {
                    "mode": source.mode,
                    "colors": [f"#{value[0]:02x}{value[1]:02x}{value[2]:02x}{value[3]:02x}" for value in source.colors],
                    "tolerance": source.tolerance,
                },
            }
            for key, source in sources.items()
        },
        "artifacts": artifacts,
        "technical_verification": {
            "status": "pending_external_verify",
            "scope": "mechanical output properties only; not visual approval",
        },
    }
    manifest_path = output / "manifest.json"
    _json_write(manifest_path, manifest)
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
    print(json.dumps({"output": str(args.output), "artifacts": len(manifest["artifacts"])}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
