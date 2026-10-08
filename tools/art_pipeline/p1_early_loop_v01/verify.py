#!/usr/bin/env python3
"""Verify the P1 early-loop atlas contract and every recorded provenance hash."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

from PIL import Image

import build
from contract import ALL_IDS, ANCHOR, CELL_SIZE, ENTRIES, GROUPS, MAX_COLORS, MAX_VISIBLE, PADDING


QA_DIMENSIONS = {
    "contact_native.png": [256, 160],
    "contact_2x.png": [512, 320],
    "contact_25pct.png": [64, 40],
    "contact_gray.png": [256, 160],
    "contact_silhouettes.png": [256, 160],
}


def _read(path: Path, label: str, errors: list[str]) -> dict[str, Any] | None:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        errors.append(f"cannot read {label}: {exc}")
        return None
    if not isinstance(value, dict):
        errors.append(f"{label} root must be an object")
        return None
    return value


def _verify_rgba_cell(cell: Image.Image, sprite_id: str, errors: list[str]) -> None:
    rgba = cell.convert("RGBA")
    data = list(rgba.getdata())
    alpha = {pixel[3] for pixel in data}
    if not alpha.issubset({0, 255}):
        errors.append(f"sprite {sprite_id} has non-binary alpha")
    if any(pixel[:3] != (0, 0, 0) for pixel in data if pixel[3] == 0):
        errors.append(f"sprite {sprite_id} has non-zero transparent RGB")
    bbox = rgba.getchannel("A").getbbox()
    if bbox is None:
        errors.append(f"sprite {sprite_id} is empty")
        return
    left, top, right, bottom = bbox
    if left < PADDING or top < PADDING or right > CELL_SIZE - PADDING or bottom > CELL_SIZE - PADDING:
        errors.append(f"sprite {sprite_id} violates {PADDING}px four-edge padding")
    if right - left > MAX_VISIBLE or bottom - top > MAX_VISIBLE:
        errors.append(f"sprite {sprite_id} exceeds {MAX_VISIBLE}x{MAX_VISIBLE} visible bounds")
    colors = {pixel[:3] for pixel in data if pixel[3] == 255}
    if len(colors) > MAX_COLORS:
        errors.append(f"sprite {sprite_id} uses {len(colors)} visible colors (max {MAX_COLORS})")


def verify_output(output: Path) -> list[str]:
    output = output.resolve()
    errors: list[str] = []
    if not output.is_dir() or output.is_symlink():
        return [f"output is not a real directory: {output}"]
    manifest = _read(output / "manifest.json", "manifest", errors)
    atlas = _read(output / "atlas.json", "atlas", errors)
    if manifest is None or atlas is None:
        return errors
    if manifest.get("schema_version") != 1:
        errors.append("manifest schema_version must be 1")
    inputs = manifest.get("inputs")
    catalog: dict[str, Any] | None = None
    recipe: dict[str, Any] | None = None
    normalized: list[dict[str, Any]] = []
    if not isinstance(inputs, dict):
        errors.append("manifest inputs must be an object")
    else:
        for key in ("catalog", "recipe"):
            record = inputs.get(key)
            if not isinstance(record, dict) or set(record) != {"path", "sha256"}:
                errors.append(f"manifest input {key} is invalid")
                continue
            path = Path(record["path"])
            if not path.is_file():
                errors.append(f"manifest input {key} is missing: {path}")
                continue
            if build.sha256_file(path) != record["sha256"]:
                errors.append(f"manifest input {key} hash mismatch")
            loaded = _read(path, key, errors)
            if key == "catalog":
                catalog = loaded
            else:
                recipe = loaded
        if catalog is not None:
            try:
                build.validate_catalog(catalog)
            except build.ContractError as exc:
                errors.append(f"catalog contract: {exc}")
        if catalog is not None and recipe is not None:
            try:
                normalized = build.validate_recipe(recipe, Path(inputs["recipe"]["path"]), catalog)
            except (build.ContractError, KeyError) as exc:
                errors.append(f"recipe contract: {exc}")
        sources = inputs.get("sources")
        if not isinstance(sources, list) or len(sources) != len(GROUPS):
            errors.append("manifest must record five sources")
        else:
            for record, (group_id, _, _) in zip(sources, GROUPS, strict=True):
                if not isinstance(record, dict) or set(record) != {"group", "path", "sha256", "dimensions"}:
                    errors.append(f"manifest source record for {group_id} is invalid")
                    continue
                if record["group"] != group_id:
                    errors.append(f"manifest source group mismatch: expected {group_id}")
                path = Path(record["path"])
                if not path.is_file():
                    errors.append(f"source is missing: {path}")
                    continue
                if build.sha256_file(path) != record["sha256"]:
                    errors.append(f"source hash mismatch: {group_id}")
                try:
                    with Image.open(path) as image:
                        if list(image.size) != record["dimensions"]:
                            errors.append(f"source dimensions mismatch: {group_id}")
                except OSError as exc:
                    errors.append(f"cannot open source {group_id}: {exc}")

    expected_artifacts = [texture for _, texture, _ in GROUPS] + ["atlas.json", *QA_DIMENSIONS]
    records = manifest.get("artifacts")
    record_map: dict[str, dict[str, Any]] = {}
    if not isinstance(records, list):
        errors.append("manifest artifacts must be an array")
    else:
        for record in records:
            if not isinstance(record, dict) or not isinstance(record.get("file"), str):
                errors.append("manifest contains an invalid artifact record")
                continue
            name = record["file"]
            if name in record_map:
                errors.append(f"duplicate manifest artifact: {name}")
            record_map[name] = record
        if set(record_map) != set(expected_artifacts):
            errors.append("manifest artifact set does not match the fixed output contract")
        for name in expected_artifacts:
            path = output / name
            record = record_map.get(name)
            if not path.is_file() or path.is_symlink():
                errors.append(f"missing or symlinked artifact: {name}")
                continue
            if record is None:
                continue
            if record.get("sha256") != build.sha256_file(path):
                errors.append(f"artifact hash mismatch: {name}")
            if record.get("bytes") != path.stat().st_size:
                errors.append(f"artifact byte-size mismatch: {name}")
            if path.suffix == ".png":
                try:
                    with Image.open(path) as image:
                        if record.get("dimensions") != list(image.size):
                            errors.append(f"artifact dimensions mismatch: {name}")
                except OSError as exc:
                    errors.append(f"cannot open artifact {name}: {exc}")
    actual_entries = {path.name for path in output.iterdir()}
    if actual_entries != set(expected_artifacts) | {"manifest.json"}:
        errors.append("output directory contains missing or unmanaged files")

    expected_contact = {"native": "contact_native.png", "2x": "contact_2x.png", "25pct": "contact_25pct.png", "gray": "contact_gray.png", "silhouettes": "contact_silhouettes.png"}
    if manifest.get("contact_qa") != expected_contact:
        errors.append("manifest contact_qa mapping is invalid")
    expected_technical = {"cell": [32, 32], "padding": 2, "max_visible": [28, 28], "anchor": [16, 16], "max_colors": 12, "alpha": "binary", "transparent_rgb": [0, 0, 0]}
    if manifest.get("technical_contract") != expected_technical:
        errors.append("manifest technical_contract is invalid")
    for name, dimensions in QA_DIMENSIONS.items():
        path = output / name
        if path.is_file():
            try:
                with Image.open(path) as image:
                    if list(image.size) != dimensions:
                        errors.append(f"QA dimensions mismatch: {name}")
                    if name != "contact_2x.png" and name != "contact_25pct.png":
                        alpha = set(image.convert("RGBA").getchannel("A").getdata())
                        if not alpha.issubset({0, 255}):
                            errors.append(f"QA image has non-binary alpha: {name}")
            except OSError:
                pass

    if atlas.get("schema_version") != 1:
        errors.append("atlas schema_version must be 1")
    expected_textures = [
        {"id": group_id, "file": texture, "dimensions": [len(ENTRIES[group_id]) * CELL_SIZE, CELL_SIZE]}
        for group_id, texture, _ in GROUPS
    ]
    if atlas.get("textures") != expected_textures:
        errors.append("atlas texture metadata does not match the five fixed atlases")
    sprite_records = atlas.get("sprites")
    sprite_map: dict[str, dict[str, Any]] = {}
    if not isinstance(sprite_records, list):
        errors.append("atlas sprites must be an array")
        sprite_records = []
    for index, record in enumerate(sprite_records):
        if not isinstance(record, dict) or not isinstance(record.get("id"), str):
            errors.append(f"atlas sprite[{index}] is invalid")
            continue
        sprite_id = record["id"]
        if sprite_id in sprite_map:
            errors.append(f"duplicate atlas sprite id: {sprite_id}")
            continue
        sprite_map[sprite_id] = record
    if set(sprite_map) != set(ALL_IDS) or len(sprite_records) != len(ALL_IDS):
        errors.append("atlas sprite ID set does not match the frozen 24-icon contract")
    loaded_atlases: dict[str, Image.Image] = {}
    for group_id, texture, _ in GROUPS:
        path = output / texture
        if not path.is_file():
            continue
        try:
            image = Image.open(path).convert("RGBA")
            expected_size = (len(ENTRIES[group_id]) * CELL_SIZE, CELL_SIZE)
            if image.size != expected_size:
                errors.append(f"atlas dimensions mismatch: {texture}")
            loaded_atlases[texture] = image
        except OSError as exc:
            errors.append(f"cannot open atlas {texture}: {exc}")
    for group_id, texture, _ in GROUPS:
        for index, frozen in enumerate(ENTRIES[group_id]):
            sprite_id, canonical_id, _, _, _, _ = frozen
            expected_record = {
                "id": sprite_id,
                "canonical_id": canonical_id,
                "texture": texture,
                "rect": [index * CELL_SIZE, 0, CELL_SIZE, CELL_SIZE],
                "anchor": ANCHOR,
                "type": "ui_icon",
            }
            if sprite_map.get(sprite_id) != expected_record:
                errors.append(f"atlas sprite metadata mismatch: {sprite_id}")
                continue
            image = loaded_atlases.get(texture)
            if image is not None:
                left = index * CELL_SIZE
                _verify_rgba_cell(image.crop((left, 0, left + CELL_SIZE, CELL_SIZE)), sprite_id, errors)
    for image in loaded_atlases.values():
        image.close()
    if normalized and len(normalized) != len(GROUPS):
        errors.append("normalized recipe group count mismatch")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    errors = verify_output(args.output)
    if errors:
        for error in errors:
            print(f"ERROR: {error}")
        return 1
    print("PASS: verified 24 mappings, pixels, dimensions, uniqueness, and provenance hashes")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
