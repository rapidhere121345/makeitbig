#!/usr/bin/env python3
"""Build the frozen 24-icon P1 early-loop atlases from reviewed source sheets."""

from __future__ import annotations

import argparse
import math
import os
import sys
import tempfile
from collections import deque
from pathlib import Path
from typing import Any

from PIL import Image, ImageOps

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))  # art_pipeline/common.py
import common  # noqa: E402
if __name__ == "__main__":  # -P / PYTHONSAFEPATH leaves the script directory off sys.path
    sys.path.insert(0, str(Path(__file__).resolve().parent))
from contract import ALL_IDS, ANCHOR, CELL_SIZE, ENTRIES, GROUPS, MAX_COLORS, MAX_VISIBLE, PADDING


class ContractError(ValueError):
    """Raised when inputs would make asset processing ambiguous or unsafe."""


sha256_file = common.sha256_file


def load_json(path: Path, label: str) -> dict[str, Any]:
    return common.load_json(path, label, ContractError)


def parse_color(value: Any, label: str) -> tuple[int, int, int]:
    if not isinstance(value, str) or len(value) != 7 or not value.startswith("#"):
        raise ContractError(f"{label} must be #RRGGBB")
    try:
        raw = bytes.fromhex(value[1:])
    except ValueError as exc:
        raise ContractError(f"{label} must be #RRGGBB") from exc
    return raw[0], raw[1], raw[2]


def require_rect(value: Any, label: str) -> tuple[int, int, int, int]:
    if not isinstance(value, list) or len(value) != 4:
        raise ContractError(f"{label} must be [x,y,w,h]")
    if any(isinstance(item, bool) or not isinstance(item, int) for item in value):
        raise ContractError(f"{label} entries must be integers")
    x, y, width, height = value
    if x < 0 or y < 0 or width < 1 or height < 1:
        raise ContractError(f"{label} needs non-negative origin and positive size")
    return x, y, width, height


def validate_catalog(catalog: dict[str, Any]) -> None:
    if set(catalog) != {"schema_version", "groups"} or catalog["schema_version"] != 1:
        raise ContractError("catalog must contain schema_version 1 and groups only")
    groups = catalog.get("groups")
    if not isinstance(groups, list) or len(groups) != len(GROUPS):
        raise ContractError("catalog must contain the five frozen groups")
    seen: set[str] = set()
    for raw, (group_id, texture, _) in zip(groups, GROUPS, strict=True):
        if not isinstance(raw, dict) or set(raw) != {"id", "texture", "entries"}:
            raise ContractError(f"catalog group {group_id} fields do not match the contract")
        if raw["id"] != group_id or raw["texture"] != texture:
            raise ContractError(f"catalog group mismatch: expected {group_id}/{texture}")
        expected = ENTRIES[group_id]
        entries = raw.get("entries")
        if not isinstance(entries, list) or len(entries) != len(expected):
            raise ContractError(f"catalog group {group_id} must contain {len(expected)} entries")
        for index, (entry, frozen) in enumerate(zip(entries, expected, strict=True)):
            if not isinstance(entry, dict):
                raise ContractError(f"catalog {group_id}[{index}] must be an object")
            keys = {"id", "canonical_id", "canonical_source", "label", "role", "type"}
            if set(entry) != keys or tuple(entry[key] for key in keys) != tuple(frozen[{"id": 0, "canonical_id": 1, "canonical_source": 2, "label": 3, "role": 4, "type": 5}[key]] for key in keys):
                expected_entry = dict(zip(("id", "canonical_id", "canonical_source", "label", "role", "type"), frozen, strict=True))
                if entry != expected_entry:
                    raise ContractError(f"catalog mapping mismatch for {frozen[0]}")
            if entry["id"] in seen:
                raise ContractError(f"duplicate catalog id: {entry['id']}")
            seen.add(entry["id"])
    if tuple(seen) and seen != set(ALL_IDS):
        raise ContractError("catalog ID set does not match the frozen 24-icon contract")


def _validated_palette(value: Any, label: str) -> tuple[tuple[int, int, int], ...] | None:
    if value is None:
        return None
    if not isinstance(value, list) or not 1 <= len(value) <= MAX_COLORS:
        raise ContractError(f"{label} must contain 1..{MAX_COLORS} colors")
    colors = tuple(parse_color(item, f"{label}[{index}]") for index, item in enumerate(value))
    if len(set(colors)) != len(colors):
        raise ContractError(f"{label} contains duplicate colors")
    return colors


def _validated_tolerance(value: Any, label: str, *, has_key: bool) -> float:
    if value is None:
        return 80.0 if has_key else 0.0
    if not has_key:
        raise ContractError(f"{label} requires an explicit colorkey")
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not 60 <= float(value) <= 100:
        raise ContractError(f"{label} must be in [60,100]")
    return float(value)


def resolve_source(recipe_path: Path, value: Any, label: str) -> Path:
    if not isinstance(value, str) or not value:
        raise ContractError(f"{label} must be a non-empty path")
    path = Path(value)
    return (path if path.is_absolute() else recipe_path.parent / path).resolve()


def validate_recipe(recipe: dict[str, Any], recipe_path: Path, catalog: dict[str, Any]) -> list[dict[str, Any]]:
    if set(recipe) != {"schema_version", "groups"} or recipe.get("schema_version") != 1:
        raise ContractError("recipe must contain schema_version 1 and groups only")
    groups = recipe.get("groups")
    if not isinstance(groups, list) or len(groups) != len(GROUPS):
        raise ContractError("recipe must contain exactly five groups")
    normalized: list[dict[str, Any]] = []
    seen_ids: set[str] = set()
    for raw, catalog_group, (group_id, _, expected_layout) in zip(groups, catalog["groups"], GROUPS, strict=True):
        if not isinstance(raw, dict):
            raise ContractError(f"recipe group {group_id} must be an object")
        allowed = {"id", "source", "layout", "palette", "palette_quantization", "colorkey", "key_scope", "tolerance", "sprites"}
        extra = set(raw) - allowed
        if extra:
            raise ContractError(f"recipe group {group_id} has unsupported keys: {sorted(extra)}")
        if raw.get("id") != group_id:
            raise ContractError(f"recipe group order/id mismatch: expected {group_id}")
        layout = raw.get("layout")
        if not isinstance(layout, dict) or set(layout) != {"rows", "cols"}:
            raise ContractError(f"recipe {group_id}.layout must contain rows and cols")
        actual_layout = (layout["rows"], layout["cols"])
        if actual_layout != expected_layout:
            raise ContractError(f"recipe {group_id}.layout must be rows={expected_layout[0]}, cols={expected_layout[1]}")
        source = resolve_source(recipe_path, raw.get("source"), f"recipe {group_id}.source")
        if not source.is_file():
            raise ContractError(f"source PNG does not exist: {source}")
        try:
            with Image.open(source) as image:
                image.load()
                source_size = image.size
        except (OSError, ValueError) as exc:
            raise ContractError(f"cannot open source PNG {source}: {exc}") from exc
        rows, cols = expected_layout
        group_key = parse_color(raw["colorkey"], f"recipe {group_id}.colorkey") if raw.get("colorkey") is not None else None
        group_key_scope = raw.get("key_scope", "edge_connected")
        if group_key_scope not in {"edge_connected", "all"}:
            raise ContractError(f"recipe {group_id}.key_scope must be edge_connected or all")
        if raw.get("key_scope") is not None and group_key is None:
            raise ContractError(f"recipe {group_id}.key_scope requires an explicit colorkey")
        group_tolerance = _validated_tolerance(raw.get("tolerance"), f"recipe {group_id}.tolerance", has_key=group_key is not None)
        group_palette = _validated_palette(raw.get("palette"), f"recipe {group_id}.palette")
        quantization = raw.get("palette_quantization", MAX_COLORS)
        if isinstance(quantization, bool) or not isinstance(quantization, int) or not 1 <= quantization <= MAX_COLORS:
            raise ContractError(f"recipe {group_id}.palette_quantization must be 1..{MAX_COLORS}")
        sprites = raw.get("sprites")
        expected_entries = catalog_group["entries"]
        if not isinstance(sprites, list) or len(sprites) != len(expected_entries):
            raise ContractError(f"recipe {group_id} must contain {len(expected_entries)} sprites")
        source_rects: list[tuple[int, int, int, int]] = []
        normalized_sprites: list[dict[str, Any]] = []
        for index, (sprite, entry) in enumerate(zip(sprites, expected_entries, strict=True)):
            if not isinstance(sprite, dict):
                raise ContractError(f"recipe {group_id}.sprites[{index}] must be an object")
            allowed_sprite = {"id", "source_rect", "visible_bbox", "palette", "palette_quantization", "colorkey", "key_scope", "tolerance"}
            extra_sprite = set(sprite) - allowed_sprite
            if extra_sprite:
                raise ContractError(f"recipe sprite {entry['id']} has unsupported keys: {sorted(extra_sprite)}")
            if sprite.get("id") != entry["id"]:
                raise ContractError(f"recipe sprite order/id mismatch: expected {entry['id']}")
            if entry["id"] in seen_ids:
                raise ContractError(f"duplicate recipe sprite id: {entry['id']}")
            seen_ids.add(entry["id"])
            rect = require_rect(sprite.get("source_rect"), f"recipe sprite {entry['id']}.source_rect")
            x, y, width, height = rect
            if x + width > source_size[0] or y + height > source_size[1]:
                raise ContractError(f"recipe sprite {entry['id']} source_rect is outside the source")
            for other_index, (ox, oy, ow, oh) in enumerate(source_rects):
                overlaps = x < ox + ow and ox < x + width and y < oy + oh and oy < y + height
                if overlaps:
                    raise ContractError(
                        f"source_rect collision in {group_id}: {entry['id']} overlaps "
                        f"{expected_entries[other_index]['id']}"
                    )
            source_rects.append(rect)
            visible_bbox = None
            if sprite.get("visible_bbox") is not None:
                visible_bbox = require_rect(sprite["visible_bbox"], f"recipe sprite {entry['id']}.visible_bbox")
                bx, by, bw, bh = visible_bbox
                if bx + bw > width or by + bh > height:
                    raise ContractError(f"recipe sprite {entry['id']}.visible_bbox exceeds source_rect")
            key_value = sprite.get("colorkey", raw.get("colorkey"))
            key = parse_color(key_value, f"recipe sprite {entry['id']}.colorkey") if key_value is not None else None
            key_scope = sprite.get("key_scope", group_key_scope)
            if key_scope not in {"edge_connected", "all"}:
                raise ContractError(f"recipe sprite {entry['id']}.key_scope must be edge_connected or all")
            if sprite.get("key_scope") is not None and key is None:
                raise ContractError(f"recipe sprite {entry['id']}.key_scope requires an explicit colorkey")
            tolerance_value = sprite.get("tolerance", raw.get("tolerance"))
            tolerance = _validated_tolerance(tolerance_value, f"recipe sprite {entry['id']}.tolerance", has_key=key is not None)
            palette = _validated_palette(sprite.get("palette"), f"recipe sprite {entry['id']}.palette") or group_palette
            colors = sprite.get("palette_quantization", quantization)
            if isinstance(colors, bool) or not isinstance(colors, int) or not 1 <= colors <= MAX_COLORS:
                raise ContractError(f"recipe sprite {entry['id']}.palette_quantization must be 1..{MAX_COLORS}")
            normalized_sprites.append({"entry": entry, "source_rect": rect, "visible_bbox": visible_bbox, "colorkey": key, "key_scope": key_scope, "tolerance": tolerance, "palette": palette, "colors": colors})
        centers = [(x + width / 2.0, y + height / 2.0) for x, y, width, height in source_rects]
        for row in range(rows):
            row_centers = centers[row * cols:(row + 1) * cols]
            if any(left[0] >= right[0] for left, right in zip(row_centers, row_centers[1:])):
                raise ContractError(f"recipe {group_id} source_rect centers must read left-to-right within row {row}")
        for row in range(rows - 1):
            upper = centers[row * cols:(row + 1) * cols]
            lower = centers[(row + 1) * cols:(row + 2) * cols]
            if max(center[1] for center in upper) >= min(center[1] for center in lower):
                raise ContractError(f"recipe {group_id} source_rect centers must read top-to-bottom across rows")
        normalized.append({"id": group_id, "source": source, "source_size": source_size, "sprites": normalized_sprites})
    if seen_ids != set(ALL_IDS):
        raise ContractError("recipe sprite IDs do not match the frozen 24-icon contract")
    return normalized


def paths_overlap(left: Path, right: Path) -> bool:
    left = left.resolve()
    right = right.resolve()
    return left == right or left in right.parents or right in left.parents


def validate_output_target(output: Path, inputs: list[Path]) -> None:
    output = output.resolve()
    if output.is_symlink():
        raise ContractError("output directory may not be a symlink")
    for input_path in inputs:
        if paths_overlap(output, input_path):
            raise ContractError(f"input/output paths overlap: {input_path} and {output}")
    if output.exists():
        if not output.is_dir():
            raise ContractError("output path exists and is not a directory")
        entries = list(output.iterdir())
        if entries:
            raise ContractError(f"output directory contains unmanaged entries: {entries[0].name}")


def _rgb_distance(left: tuple[int, int, int], right: tuple[int, int, int]) -> float:
    return math.sqrt(sum((a - b) ** 2 for a, b in zip(left, right, strict=True)))


def remove_edge_colorkey(image: Image.Image, key: tuple[int, int, int], tolerance: float) -> Image.Image:
    """Remove only key-like pixels connected to an edge of the reviewed crop."""
    result = image.convert("RGBA")
    pixels = result.load()
    width, height = result.size
    visited: set[tuple[int, int]] = set()
    queue: deque[tuple[int, int]] = deque()

    def push(x: int, y: int) -> None:
        point = (x, y)
        if point in visited:
            return
        visited.add(point)
        if _rgb_distance(pixels[x, y][:3], key) <= tolerance:
            queue.append(point)

    for x in range(width):
        push(x, 0)
        push(x, height - 1)
    for y in range(height):
        push(0, y)
        push(width - 1, y)
    while queue:
        x, y = queue.popleft()
        pixels[x, y] = (0, 0, 0, 0)
        for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            if 0 <= nx < width and 0 <= ny < height:
                push(nx, ny)
    return result


def remove_all_colorkey(image: Image.Image, key: tuple[int, int, int], tolerance: float) -> Image.Image:
    """Remove every key-like pixel in a crop whose source contract reserves the key color."""
    result = image.convert("RGBA")
    pixels = result.load()
    for y in range(result.height):
        for x in range(result.width):
            if _rgb_distance(pixels[x, y][:3], key) <= tolerance:
                pixels[x, y] = (0, 0, 0, 0)
    return result


def normalize_transparency(image: Image.Image) -> Image.Image:
    result = image.convert("RGBA")
    pixels = result.load()
    alpha_values: set[int] = set()
    for y in range(result.height):
        for x in range(result.width):
            alpha = pixels[x, y][3]
            alpha_values.add(alpha)
            if alpha == 0:
                pixels[x, y] = (0, 0, 0, 0)
    if not alpha_values.issubset({0, 255}):
        raise ContractError("source contains semi-transparent pixels; binary alpha is required")
    return result


def _map_palette(image: Image.Image, palette: tuple[tuple[int, int, int], ...]) -> Image.Image:
    result = image.copy()
    pixels = result.load()
    for y in range(result.height):
        for x in range(result.width):
            red, green, blue, alpha = pixels[x, y]
            if alpha:
                nearest = min(palette, key=lambda color: _rgb_distance((red, green, blue), color))
                pixels[x, y] = (*nearest, 255)
    return result


def _quantize_visible(image: Image.Image, colors: int) -> Image.Image:
    visible = [pixel[:3] for pixel in image.getdata() if pixel[3] == 255]
    if len(set(visible)) <= colors:
        return image.copy()
    strip = Image.new("RGB", (len(visible), 1))
    strip.putdata(visible)
    quantized = strip.quantize(colors=colors, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGB")
    mapping: dict[tuple[int, int, int], tuple[int, int, int]] = {}
    for original, mapped in zip(visible, quantized.getdata(), strict=True):
        mapping.setdefault(original, mapped)
    result = image.copy()
    pixels = result.load()
    for y in range(result.height):
        for x in range(result.width):
            red, green, blue, alpha = pixels[x, y]
            if alpha:
                pixels[x, y] = (*mapping[(red, green, blue)], 255)
    return result


def prepare_sprite(source_image: Image.Image, spec: dict[str, Any]) -> Image.Image:
    x, y, width, height = spec["source_rect"]
    raw = source_image.crop((x, y, x + width, y + height))
    if spec["visible_bbox"] is not None:
        bx, by, bw, bh = spec["visible_bbox"]
        raw = raw.crop((bx, by, bx + bw, by + bh))
    has_alpha = "A" in raw.getbands()
    if spec["colorkey"] is None:
        if not has_alpha:
            raise ContractError(f"sprite {spec['entry']['id']} has no alpha and no explicit colorkey")
        rgba = raw.convert("RGBA")
        if rgba.getchannel("A").getextrema() == (255, 255):
            raise ContractError(f"sprite {spec['entry']['id']} is fully opaque and has no explicit colorkey")
    else:
        if spec["key_scope"] == "all":
            rgba = remove_all_colorkey(raw, spec["colorkey"], spec["tolerance"])
        else:
            rgba = remove_edge_colorkey(raw, spec["colorkey"], spec["tolerance"])
    rgba = normalize_transparency(rgba)
    bbox = rgba.getchannel("A").getbbox()
    if bbox is None:
        raise ContractError(f"sprite {spec['entry']['id']} is empty after alpha cleanup")
    trimmed = rgba.crop(bbox)
    scale = max(trimmed.width / MAX_VISIBLE, trimmed.height / MAX_VISIBLE, 1.0)
    if scale > 1.0:
        size = (max(1, math.floor(trimmed.width / scale)), max(1, math.floor(trimmed.height / scale)))
        trimmed = trimmed.resize(size, Image.Resampling.NEAREST)
    if spec["palette"] is not None:
        trimmed = _map_palette(trimmed, spec["palette"])
    else:
        trimmed = _quantize_visible(trimmed, spec["colors"])
    trimmed = normalize_transparency(trimmed)
    cell = Image.new("RGBA", (CELL_SIZE, CELL_SIZE), (0, 0, 0, 0))
    left = (CELL_SIZE - trimmed.width) // 2
    top = (CELL_SIZE - trimmed.height) // 2
    cell.alpha_composite(trimmed, (left, top))
    return cell


def _gray(image: Image.Image) -> Image.Image:
    alpha = image.getchannel("A")
    gray = ImageOps.grayscale(image.convert("RGB"))
    return Image.merge("RGBA", (gray, gray, gray, alpha))


def _silhouette(image: Image.Image) -> Image.Image:
    alpha = image.getchannel("A")
    white = Image.new("L", image.size, 255)
    return Image.merge("RGBA", (white, white, white, alpha))


def build(catalog_path: Path, recipe_path: Path, output: Path) -> Path:
    catalog_path = catalog_path.resolve()
    recipe_path = recipe_path.resolve()
    catalog = load_json(catalog_path, "catalog")
    validate_catalog(catalog)
    recipe = load_json(recipe_path, "recipe")
    groups = validate_recipe(recipe, recipe_path, catalog)
    output = output.resolve()
    source_paths = [group["source"] for group in groups]
    validate_output_target(output, [catalog_path, recipe_path, *source_paths])
    atlases: dict[str, Image.Image] = {}
    sprites: list[dict[str, Any]] = []
    for group, catalog_group in zip(groups, catalog["groups"], strict=True):
        with Image.open(group["source"]) as image:
            image.load()
            source_image = image.copy()
        atlas = Image.new("RGBA", (len(group["sprites"]) * CELL_SIZE, CELL_SIZE), (0, 0, 0, 0))
        for index, spec in enumerate(group["sprites"]):
            cell = prepare_sprite(source_image, spec)
            atlas.alpha_composite(cell, (index * CELL_SIZE, 0))
            entry = spec["entry"]
            sprites.append({
                "id": entry["id"],
                "canonical_id": entry["canonical_id"],
                "texture": catalog_group["texture"],
                "rect": [index * CELL_SIZE, 0, CELL_SIZE, CELL_SIZE],
                "anchor": ANCHOR,
                "type": "ui_icon",
            })
        atlases[group["id"]] = atlas

    max_width = max(image.width for image in atlases.values())
    native = Image.new("RGBA", (max_width, len(GROUPS) * CELL_SIZE), (0, 0, 0, 0))
    for row, (group_id, _, _) in enumerate(GROUPS):
        native.alpha_composite(atlases[group_id], (0, row * CELL_SIZE))
    qa = {
        "contact_native.png": native,
        "contact_2x.png": native.resize((native.width * 2, native.height * 2), Image.Resampling.NEAREST),
        "contact_25pct.png": native.resize((native.width // 4, native.height // 4), Image.Resampling.NEAREST),
        "contact_gray.png": _gray(native),
        "contact_silhouettes.png": _silhouette(native),
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".p1-early-loop-", dir=output.parent) as temporary:
        stage = Path(temporary)
        for group_id, texture, _ in GROUPS:
            atlases[group_id].save(stage / texture, format="PNG", optimize=False)
        for name, image in qa.items():
            image.save(stage / name, format="PNG", optimize=False)
        atlas = {
            "schema_version": 1,
            "textures": [
                {"id": group_id, "file": texture, "dimensions": [len(ENTRIES[group_id]) * CELL_SIZE, CELL_SIZE]}
                for group_id, texture, _ in GROUPS
            ],
            "sprites": sprites,
        }
        common.write_json(stage / "atlas.json", atlas)
        artifact_names = [texture for _, texture, _ in GROUPS] + ["atlas.json", *qa.keys()]
        artifacts = []
        for name in artifact_names:
            path = stage / name
            record: dict[str, Any] = {"file": name, "sha256": sha256_file(path), "bytes": path.stat().st_size}
            if path.suffix == ".png":
                with Image.open(path) as image:
                    record["dimensions"] = list(image.size)
            artifacts.append(record)
        manifest = {
            "schema_version": 1,
            "inputs": {
                "catalog": {"path": str(catalog_path), "sha256": sha256_file(catalog_path)},
                "recipe": {"path": str(recipe_path), "sha256": sha256_file(recipe_path)},
                "sources": [
                    {"group": group["id"], "path": str(group["source"]), "sha256": sha256_file(group["source"]), "dimensions": list(group["source_size"])}
                    for group in groups
                ],
            },
            "artifacts": artifacts,
            "contact_qa": {
                "native": "contact_native.png",
                "2x": "contact_2x.png",
                "25pct": "contact_25pct.png",
                "gray": "contact_gray.png",
                "silhouettes": "contact_silhouettes.png",
            },
            "technical_contract": {"cell": [CELL_SIZE, CELL_SIZE], "padding": PADDING, "max_visible": [MAX_VISIBLE, MAX_VISIBLE], "anchor": ANCHOR, "max_colors": MAX_COLORS, "alpha": "binary", "transparent_rgb": [0, 0, 0]},
        }
        common.write_json(stage / "manifest.json", manifest)
        if output.exists():
            output.rmdir()
        os.replace(stage, output)
    return output


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--catalog", required=True, type=Path)
    parser.add_argument("--recipe", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    try:
        build(args.catalog, args.recipe, args.output)
    except ContractError as exc:
        print(f"ERROR: {exc}")
        return 1
    print(f"PASS: built 24 icons in {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
