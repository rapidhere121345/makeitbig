#!/usr/bin/env python3
"""Mechanically verify generated P1 calibration atlas artifacts."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path
from typing import Any

from PIL import Image

import build


class VerificationFailed(RuntimeError):
    def __init__(self, errors: list[str]) -> None:
        self.errors = errors
        super().__init__("; ".join(errors[:3]))


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _load_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        value = json.load(handle)
    if not isinstance(value, dict):
        raise ValueError(f"{path} root is not an object")
    return value


def _safe_output_path(output: Path, value: str) -> Path:
    path = Path(value)
    if not path.is_absolute():
        path = output / path
    resolved = path.resolve()
    if resolved.parent != output.resolve():
        raise ValueError(f"artifact escapes output directory: {value}")
    return resolved


def _pixel(color: tuple[int, ...]) -> tuple[int, int, int, int]:
    if len(color) == 4:
        return color
    if len(color) == 3:
        return color[0], color[1], color[2], 255
    if len(color) == 2:
        return color[0], color[0], color[0], color[1]
    return color[0], color[0], color[0], 255


def _source_clipping(config: dict[str, Any], errors: list[str]) -> None:
    sources = build._load_sources(config)
    for raw in config["sprites"]:
        source = sources[raw["source"]]
        if source.mode == "opaque":
            continue
        bounds = build._cell_bounds(source, tuple(raw["cell"]), raw.get("crop"))
        with Image.open(source.path) as image:
            x, y, width, height = bounds
            cell = image.convert("RGBA").crop((x, y, x + width, y + height))
        cleaned = build._clean_background(source, cell)
        bbox = build._alpha_bbox(cleaned)
        if bbox is None:
            errors.append(f"clipping/empty: sprite {raw['id']} has no foreground pixels")
            continue
        x, y, right, bottom = bbox
        touched: list[str] = []
        if x == 0:
            touched.append("left")
        if y == 0:
            touched.append("top")
        if right == cleaned.width:
            touched.append("right")
        if bottom == cleaned.height:
            touched.append("bottom")
        if touched:
            errors.append(
                f"clipping: sprite {raw['id']} foreground touches cell edge ({','.join(touched)})"
            )


def _validate_layer_coverage(
    config: dict[str, Any], sprites: dict[str, Any], errors: list[str]
) -> None:
    families: dict[tuple[Any, ...], list[dict[str, Any]]] = {}
    for raw in config["sprites"]:
        family_key = (
            raw["source"],
            tuple(raw["cell"]),
            tuple(raw["crop"]) if raw.get("crop") is not None else None,
            raw["atlas"],
        )
        families.setdefault(family_key, []).append(raw)

    for family in families.values():
        layers: list[tuple[int, int, str]] = []
        for raw in family:
            metadata = sprites.get(raw["id"])
            if not isinstance(metadata, dict) or metadata.get("keep_rows") is None:
                continue
            rows = metadata["keep_rows"]
            if (
                not isinstance(rows, list)
                or len(rows) != 2
                or any(isinstance(value, bool) or not isinstance(value, int) for value in rows)
            ):
                errors.append(f"sprite {raw['id']} keep_rows is not an integer pair")
                continue
            layers.append((rows[0], rows[1], raw["id"]))
        if len(layers) < 2:
            continue
        cell_height = config["atlases"][family[0]["atlas"]]["cell_size"][1]
        intervals = sorted(layers)
        cursor = 0
        for start, end, sprite_id in intervals:
            if start != cursor:
                kind = "overlap" if start < cursor else "gap"
                errors.append(
                    f"sprite {sprite_id} keep_rows has a {kind} at native row {min(start, cursor)}"
                )
            if end < start or end > cell_height:
                errors.append(
                    f"sprite {sprite_id} keep_rows must stay within the output cell height"
                )
            cursor = max(cursor, end)
        if cursor != cell_height:
            errors.append(
                f"source cell layers for {family[0]['source']} do not cover rows through {cell_height}"
            )


def verify_output(output: Path, config_path: Path | None = None) -> tuple[list[str], dict[str, Any]]:
    errors: list[str] = []
    output = output.resolve()
    manifest_path = output / "manifest.json"
    atlas_path = output / "atlas.json"
    if not manifest_path.is_file():
        return [f"missing manifest: {manifest_path}"], {}
    try:
        manifest = _load_json(manifest_path)
        atlas = _load_json(atlas_path)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        return [f"cannot read JSON output: {exc}"], {}

    if config_path is None:
        recorded = manifest.get("config_path")
        if not isinstance(recorded, str):
            return ["manifest config_path is missing"], manifest
        config_path = Path(recorded)
    try:
        config = _load_json(config_path.resolve())
        build.validate_config(config)
    except (OSError, ValueError, build.ConfigError, json.JSONDecodeError) as exc:
        return [f"cannot load/validate config: {exc}"], manifest

    if manifest.get("schema_version") != 1:
        errors.append("manifest schema_version must be 1")
    if manifest.get("config_sha256") != _sha256_file(config_path.resolve()):
        errors.append("config hash does not match manifest")
    if atlas.get("schema_version") != 1:
        errors.append("atlas schema_version must be 1")
    if atlas.get("native_view") != config["native_view"]:
        errors.append("atlas native_view does not match config")

    recorded_sources = manifest.get("sources")
    if not isinstance(recorded_sources, dict) or set(recorded_sources) != set(config["sources"]):
        errors.append("manifest source keys do not match config")
        recorded_sources = recorded_sources if isinstance(recorded_sources, dict) else {}
    for key, raw in config["sources"].items():
        recorded = recorded_sources.get(key)
        if not isinstance(recorded, dict):
            continue
        source_path = Path(raw["path"])
        if recorded.get("path") != str(source_path):
            errors.append(f"source {key} path provenance mismatch")
        if not source_path.is_file():
            errors.append(f"source {key} PNG is missing: {source_path}")
            continue
        actual_hash = _sha256_file(source_path)
        if recorded.get("sha256") != actual_hash:
            errors.append(f"source {key} hash mismatch")
        try:
            with Image.open(source_path) as image:
                image.load()
                if (image.width, image.height) != (recorded.get("width"), recorded.get("height")):
                    errors.append(f"source {key} dimensions mismatch")
        except (OSError, ValueError) as exc:
            errors.append(f"source {key} cannot be opened: {exc}")

    textures = atlas.get("textures")
    sprites = atlas.get("sprites")
    animations = atlas.get("animations")
    if not isinstance(textures, dict) or not textures:
        errors.append("atlas textures must be a non-empty object")
        textures = {}
    if not isinstance(sprites, dict) or not sprites:
        errors.append("atlas sprites must be a non-empty object")
        sprites = {}
    if not isinstance(animations, dict):
        errors.append("atlas animations must be an object")
        animations = {}
    if set(textures) != set(config["atlases"]):
        errors.append("atlas texture keys do not match config")
    if set(sprites) != {item["id"] for item in config["sprites"]}:
        errors.append("atlas sprite keys do not match config")

    loaded_textures: dict[str, Image.Image] = {}
    for key in sorted(set(textures) & set(config["atlases"])):
        raw = textures[key]
        if not isinstance(raw, dict):
            errors.append(f"texture {key} contract is not an object")
            continue
        path_value = raw.get("path")
        expected = f"{config['resource_prefix'].rstrip('/')}/{key}.png"
        if path_value != expected:
            errors.append(f"texture {key} resource path mismatch")
        artifact_path = output / f"{key}.png"
        if not artifact_path.is_file():
            errors.append(f"texture {key} PNG is missing")
            continue
        try:
            with Image.open(artifact_path) as image:
                image.load()
                if image.mode != "RGBA":
                    errors.append(f"texture {key} is {image.mode}, expected RGBA")
                if (image.width, image.height) != (raw.get("width"), raw.get("height")):
                    errors.append(f"texture {key} dimensions mismatch")
                loaded_textures[key] = image.copy()
        except (OSError, ValueError) as exc:
            errors.append(f"texture {key} cannot be opened: {exc}")

    config_sprites = {item["id"]: item for item in config["sprites"]}
    expected_slots: dict[str, tuple[str, list[int]]] = {}
    cells_per_atlas: dict[str, int] = {}
    for raw_config in config["sprites"]:
        atlas_key = raw_config["atlas"]
        index = cells_per_atlas.get(atlas_key, 0)
        cells_per_atlas[atlas_key] = index + 1
        columns = config["atlases"][atlas_key]["columns"]
        cell_width, cell_height = config["atlases"][atlas_key]["cell_size"]
        row, column = divmod(index, columns)
        expected_slots[raw_config["id"]] = (
            atlas_key,
            [column * cell_width, row * cell_height, cell_width, cell_height],
        )
    global_palette = {
        build.parse_hex_color(item, f"palette[{index}]")
        for index, item in enumerate(config["palette"])
    }
    for sprite_id, raw_config in config_sprites.items():
        raw_atlas = sprites.get(sprite_id)
        if not isinstance(raw_atlas, dict):
            continue
        texture_key = raw_atlas.get("texture")
        texture = loaded_textures.get(texture_key)
        rect = raw_atlas.get("rect")
        anchor = raw_atlas.get("anchor")
        if texture is None or not isinstance(rect, list) or len(rect) != 4:
            errors.append(f"sprite {sprite_id} has invalid texture or rect")
            continue
        if any(isinstance(value, bool) or not isinstance(value, int) for value in rect):
            errors.append(f"sprite {sprite_id} rect is not integral")
            continue
        x, y, width, height = rect
        if width <= 0 or height <= 0:
            errors.append(f"sprite {sprite_id} rect is empty")
            continue
        if x < 0 or y < 0 or x + width > texture.width or y + height > texture.height:
            errors.append(f"sprite {sprite_id} rect is out of texture bounds")
            continue
        cell_size = config["atlases"][raw_config["atlas"]]["cell_size"]
        if [width, height] != cell_size or x % width or y % height:
            errors.append(f"sprite {sprite_id} rect is not an aligned full cell")
        expected_texture, expected_rect = expected_slots[sprite_id]
        if texture_key != expected_texture or rect != expected_rect:
            errors.append(
                f"sprite {sprite_id} texture/rect differs from its configured aligned full cell"
            )
        if anchor != raw_config["anchor"]:
            errors.append(f"sprite {sprite_id} anchor differs from configured cell-local anchor")
        if not isinstance(anchor, list) or len(anchor) != 2 or any(
            isinstance(value, bool) or not isinstance(value, int) for value in anchor
        ):
            errors.append(f"sprite {sprite_id} anchor is not integral")
        for optional in ("facing", "state", "keep_rows"):
            if (optional in raw_config or optional in raw_atlas) and raw_atlas.get(optional) != raw_config.get(optional):
                errors.append(f"sprite {sprite_id} {optional} mismatch")
        allowed = global_palette if raw_config.get("palette") is None else {
            build.parse_hex_color(item, f"sprites[{sprite_id}].palette[{index}]")
            for index, item in enumerate(raw_config["palette"])
        }
        x, y, width, height = rect
        cropped = texture.crop((x, y, x + width, y + height))
        bbox = cropped.getchannel("A").getbbox()
        if bbox:
            if bbox[2] - bbox[0] > raw_config["fit"][0] or bbox[3] - bbox[1] > raw_config["fit"][1]:
                errors.append(f"sprite {sprite_id} visible bounds exceed configured fit")
            padding = config["atlases"][raw_config["atlas"]].get("padding", 2)
            if bbox[0] < padding or bbox[1] < padding or bbox[2] > width - padding or bbox[3] > height - padding:
                errors.append(f"sprite {sprite_id} violates internal padding")
        nonempty = False
        for color in cropped.getdata():
            pixel = _pixel(color)
            if pixel[3] not in (0, 255):
                errors.append(f"sprite {sprite_id} has non-binary alpha")
                break
            if pixel[3] == 0:
                continue
            nonempty = True
            if pixel not in allowed:
                errors.append(f"sprite {sprite_id} has color outside its exact palette")
                break
        if not nonempty:
            errors.append(f"sprite {sprite_id} rect is empty after alpha cleanup")

    expected_animations = {
        key: {
            "frames": list(raw["frames"]),
            "fps": raw["fps"],
            "loop": raw["loop"],
        }
        for key, raw in config["animations"].items()
    }
    if animations != expected_animations:
        errors.append("atlas animations do not exactly match config")
    for animation_id, raw in config["animations"].items():
        for frame in raw["frames"]:
            if frame not in sprites:
                errors.append(f"animation {animation_id} references missing sprite {frame}")

    artifacts = manifest.get("artifacts")
    if not isinstance(artifacts, list):
        errors.append("manifest artifacts must be an array")
        artifacts = []
    by_path: dict[Path, dict[str, Any]] = {}
    for index, artifact in enumerate(artifacts):
        if not isinstance(artifact, dict) or not isinstance(artifact.get("path"), str):
            errors.append(f"manifest artifact[{index}] is invalid")
            continue
        try:
            artifact_path = _safe_output_path(output, artifact["path"])
        except ValueError as exc:
            errors.append(str(exc))
            continue
        by_path[artifact_path] = artifact
        if not artifact_path.is_file():
            errors.append(f"artifact is missing: {artifact_path.name}")
            continue
        if artifact.get("sha256") != _sha256_file(artifact_path):
            errors.append(f"artifact hash mismatch: {artifact_path.name}")
        if artifact.get("bytes") != artifact_path.stat().st_size:
            errors.append(f"artifact byte count mismatch: {artifact_path.name}")
    expected_artifacts = {
        *(output / f"{key}.png" for key in config["atlases"]),
        output / "atlas.json",
        output / "contact_sheet.png",
    }
    if set(by_path) != expected_artifacts:
        errors.append("manifest artifact list does not exactly match generated outputs")
    if (output / "contact_sheet.png").is_file():
        try:
            with Image.open(output / "contact_sheet.png") as sheet:
                sheet.load()
        except (OSError, ValueError) as exc:
            errors.append(f"contact sheet is not a valid PNG: {exc}")

    _source_clipping(config, errors)
    _validate_layer_coverage(config, sprites, errors)
    return errors, manifest


def _write_verification(manifest_path: Path, errors: list[str]) -> None:
    manifest = _load_json(manifest_path)
    manifest["technical_verification"] = {
        "status": "pass" if not errors else "fail",
        "error_count": len(errors),
        "errors": errors,
        "scope": "mechanical output properties only; not visual approval",
    }
    with manifest_path.open("w", encoding="utf-8") as handle:
        json.dump(manifest, handle, ensure_ascii=False, indent=2, sort_keys=True)
        handle.write("\n")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path, help="generated version directory")
    parser.add_argument("--config", type=Path, help="recipe JSON; defaults to manifest provenance")
    parser.add_argument("--update-manifest", action="store_true", help="record technical verification result")
    args = parser.parse_args(argv)
    try:
        errors, _ = verify_output(args.output, args.config)
        if args.update_manifest:
            _write_verification(args.output.resolve() / "manifest.json", errors)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        errors = [f"VERIFY FAILED: {exc}"]
    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        print(f"VERIFY FAIL: {len(errors)} error(s); mechanical only, not visual approval")
        return 1
    print("VERIFY PASS: mechanical only, not visual approval")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
