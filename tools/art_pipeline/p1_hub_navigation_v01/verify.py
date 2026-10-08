#!/usr/bin/env python3
"""Verify a packaged P1 hub-navigation pack against its own provenance.

Verification is a re-derivation, not a re-run of the build: every recorded hash
is recomputed from the bytes on disk, the recipe is re-validated against the
contract, and the published pixels are re-gated. The per-cell gate is the
reviewed early-loop ``_verify_rgba_cell`` reached through :mod:`bridge`, so the
published pack is checked by the same code that gated the accepted early-loop
pack -- plus the two rules this batch adds: the seven-colour palette cap and the
requirement that no two cells share one alpha mask.

Usage:
    python3 verify.py --output PACK_DIRECTORY
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

from PIL import Image

import build
import contract
import review
from bridge import verify_rgba_cell


def read_json(path: Path, label: str, errors: list[str]) -> dict[str, Any] | None:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        errors.append(f"cannot read {label}: {exc}")
        return None
    if not isinstance(value, dict):
        errors.append(f"{label} root must be an object")
        return None
    return value


def open_rgba(path: Path, label: str, errors: list[str]) -> Image.Image | None:
    try:
        return Image.open(path).convert("RGBA")
    except (OSError, ValueError) as exc:
        errors.append(f"cannot open {label}: {exc}")
        return None


def check_record(
    record: Any,
    path: Path,
    label: str,
    errors: list[str],
    *,
    expect_dimensions: list[int] | None = None,
) -> None:
    """Re-hash one recorded artifact and compare bytes and dimensions."""
    if not isinstance(record, dict):
        errors.append(f"manifest record for {label} is invalid")
        return
    if not path.is_file() or path.is_symlink():
        errors.append(f"missing or symlinked artifact: {label}")
        return
    if record.get("sha256") != build.sha256_file(path):
        errors.append(f"hash mismatch: {label}")
    if record.get("bytes") != path.stat().st_size:
        errors.append(f"byte-size mismatch: {label}")
    if expect_dimensions is not None and record.get("dimensions") != expect_dimensions:
        errors.append(f"recorded dimensions mismatch: {label}")
    if path.suffix == ".png":
        image = open_rgba(path, label, errors)
        if image is not None:
            if expect_dimensions is not None and [image.width, image.height] != expect_dimensions:
                errors.append(f"dimensions mismatch: {label}")
            image.close()


def verify_atlas(atlas: dict[str, Any], icons: Image.Image, errors: list[str]) -> None:
    if atlas.get("schema_version") != contract.SCHEMA_VERSION:
        errors.append(f"atlas schema_version must be {contract.SCHEMA_VERSION}")

    expected_texture = {
        contract.TEXTURE_ID: {
            "path": contract.TEXTURE_PATH,
            "width": contract.TEXTURE_WIDTH,
            "height": contract.TEXTURE_HEIGHT,
        }
    }
    if atlas.get("textures") != expected_texture:
        errors.append("atlas texture metadata does not match the fixed pack contract")

    if icons.size != (contract.TEXTURE_WIDTH, contract.TEXTURE_HEIGHT):
        errors.append(
            f"icons.png must be {contract.TEXTURE_WIDTH}x{contract.TEXTURE_HEIGHT}, got {icons.width}x{icons.height}"
        )

    raw_sprites = atlas.get("sprites")
    if not isinstance(raw_sprites, list):
        errors.append("atlas sprites must be an array")
        return
    if len(raw_sprites) != len(contract.SPRITE_IDS):
        errors.append(f"atlas must publish exactly {len(contract.SPRITE_IDS)} sprites")

    seen: dict[str, int] = {}
    gate = verify_rgba_cell()
    masks: dict[bytes, str] = {}
    for index, record in enumerate(raw_sprites):
        if not isinstance(record, dict) or not isinstance(record.get("id"), str):
            errors.append(f"atlas sprite[{index}] is invalid")
            continue
        sprite_id = record["id"]
        if sprite_id in seen:
            errors.append(f"duplicate atlas sprite id: {sprite_id}")
            continue
        seen[sprite_id] = index
        if index >= len(contract.SPRITE_IDS) or sprite_id != contract.SPRITE_IDS[index]:
            errors.append(f"atlas sprite slot {index} must be {contract.SPRITE_IDS[index]}, got {sprite_id}")
            continue
        expected_record = {
            "id": sprite_id,
            "type": contract.SPRITE_TYPE,
            "texture": contract.TEXTURE_ID,
            "rect": [index * contract.CELL_SIZE, 0, contract.CELL_SIZE, contract.CELL_SIZE],
            "anchor": list(contract.ANCHOR),
        }
        if record != expected_record:
            errors.append(f"atlas sprite metadata mismatch: {sprite_id}")
            continue
        if icons.size != (contract.TEXTURE_WIDTH, contract.TEXTURE_HEIGHT):
            continue
        left = index * contract.CELL_SIZE
        cell = icons.crop((left, 0, left + contract.CELL_SIZE, contract.CELL_SIZE))
        gate(cell, sprite_id, errors)
        colors = build.visible_colors(cell)
        if len(colors) > contract.MAX_COLORS:
            errors.append(
                f"sprite {sprite_id} shows {len(colors)} colours, over the {contract.MAX_COLORS}-colour cap"
            )
        mask = build.alpha_mask(cell)
        if mask in masks:
            errors.append(f"sprites {masks[mask]} and {sprite_id} share one alpha mask")
        masks[mask] = sprite_id
        cell.close()
    if set(seen) != set(contract.SPRITE_IDS):
        missing = sorted(set(contract.SPRITE_IDS) - set(seen))
        errors.append(f"atlas is missing published sprite IDs: {missing}")


def verify_recipe_record(record: Any, errors: list[str]) -> None:
    """Re-hash the recorded recipe from its recorded directory and file name."""
    if not isinstance(record, dict):
        errors.append("manifest input recipe is invalid")
        return
    directory = record.get("directory")
    name = record.get("file")
    if not isinstance(directory, str) or not isinstance(name, str):
        errors.append("manifest input recipe is missing its recorded location")
        return
    check_record(record, Path(directory) / name, "recipe", errors)


def verify_review(
    record: Any,
    icons: Image.Image,
    errors: list[str],
) -> None:
    """When a pack records review derivatives, they must still be intact."""
    if record is None:
        return
    if not isinstance(record, dict):
        errors.append("manifest review record is invalid")
        return
    directory_raw = record.get("directory")
    derivatives = record.get("derivatives")
    if not isinstance(directory_raw, str) or not isinstance(derivatives, dict):
        errors.append("manifest review record is incomplete")
        return
    directory = Path(directory_raw)
    if not directory.is_dir() or directory.is_symlink():
        errors.append(f"review directory is missing: {directory}")
        return
    expected = review.derivative_dimensions(icons.size)
    labels = {name: label for label, name in review.DERIVATIVE_LABELS.items()}
    if set(derivatives) != set(labels.values()):
        errors.append("manifest review derivative set does not match the fixed review contract")
    for name, label in labels.items():
        check_record(derivatives.get(label), directory / name, f"review/{name}", errors, expect_dimensions=expected[name])
    managed = {name for name in contract.REVIEW_ORDER}
    extras = sorted(path.name for path in directory.iterdir() if path.name not in managed)
    if extras:
        errors.append(f"review directory contains unmanaged entries: {extras[0]}")


def verify_output(output: Path) -> list[str]:
    output = output.resolve()
    errors: list[str] = []
    if not output.is_dir() or output.is_symlink():
        return [f"output is not a real directory: {output}"]
    manifest = read_json(output / contract.MANIFEST_FILE, "manifest", errors)
    atlas = read_json(output / contract.ATLAS_FILE, "atlas", errors)
    if manifest is None or atlas is None:
        return errors
    if manifest.get("schema_version") != build.MANIFEST_SCHEMA_VERSION:
        errors.append(f"manifest schema_version must be {build.MANIFEST_SCHEMA_VERSION}")
    if manifest.get("pipeline") != "p1_hub_navigation_v01":
        errors.append("manifest pipeline name is invalid")
    if manifest.get("technical_contract") != build.TECHNICAL_CONTRACT:
        errors.append("manifest technical_contract is invalid")

    inputs = manifest.get("inputs")
    if not isinstance(inputs, dict):
        errors.append("manifest inputs must be an object")
    else:
        recipe_record = inputs.get("recipe")
        if not isinstance(recipe_record, dict) or not isinstance(recipe_record.get("file"), str):
            errors.append("manifest input recipe is invalid")
        elif not isinstance(recipe_record.get("directory"), str):
            errors.append("manifest input recipe is missing its recorded directory")
        source_record = inputs.get("source")
        if not isinstance(source_record, dict) or not isinstance(source_record.get("path"), str):
            errors.append("manifest input source is invalid")
        else:
            source_path = Path(source_record["path"])
            recorded_dimensions = source_record.get("dimensions")
            check_record(
                source_record,
                source_path,
                "source",
                errors,
                expect_dimensions=recorded_dimensions if isinstance(recorded_dimensions, list) else None,
            )

    icons_path = output / contract.TEXTURE_FILE
    outputs = manifest.get("outputs")
    if not isinstance(outputs, dict):
        errors.append("manifest outputs must be an object")
    else:
        artifacts = outputs.get("artifacts")
        record_map: dict[str, Any] = {}
        if not isinstance(artifacts, list):
            errors.append("manifest outputs.artifacts must be an array")
        else:
            for record in artifacts:
                if not isinstance(record, dict) or not isinstance(record.get("file"), str):
                    errors.append("manifest contains an invalid artifact record")
                    continue
                if record["file"] in record_map:
                    errors.append(f"duplicate manifest artifact: {record['file']}")
                record_map[record["file"]] = record
            if set(record_map) != {contract.TEXTURE_FILE, contract.ATLAS_FILE}:
                errors.append("manifest artifact set does not match the fixed pack contract")
        check_record(
            record_map.get(contract.TEXTURE_FILE),
            icons_path,
            contract.TEXTURE_FILE,
            errors,
            expect_dimensions=[contract.TEXTURE_WIDTH, contract.TEXTURE_HEIGHT],
        )
        atlas_path = output / contract.ATLAS_FILE
        check_record(record_map.get(contract.ATLAS_FILE), atlas_path, contract.ATLAS_FILE, errors)
        if atlas_path.is_file() and outputs.get("atlas_sha256") != build.sha256_file(atlas_path):
            errors.append("manifest atlas_sha256 mismatch")
        if outputs.get("sprite_ids") != list(contract.SPRITE_IDS):
            errors.append("manifest sprite_ids do not match the fixed contract")
        expected_texture_output = {
            "id": contract.TEXTURE_ID,
            "path": contract.TEXTURE_PATH,
            "dimensions": [contract.TEXTURE_WIDTH, contract.TEXTURE_HEIGHT],
        }
        if outputs.get("texture") != expected_texture_output:
            errors.append("manifest output texture metadata is invalid")

    icons = open_rgba(icons_path, contract.TEXTURE_FILE, errors)
    if icons is not None:
        verify_atlas(atlas, icons, errors)
        if isinstance(inputs, dict):
            verify_recipe_record(inputs.get("recipe"), errors)
        verify_review(manifest.get("review"), icons, errors)
        icons.close()

    # Godot writes its own import sidecar next to an imported PNG and rebuilds it
    # on demand, so the pack tolerates that one file. It carries no published
    # bytes: it is never hashed, measured or compared against the manifest, and
    # every other unmanaged file is still reported.
    expected_entries = {contract.TEXTURE_FILE, contract.ATLAS_FILE, contract.MANIFEST_FILE}
    allowed_sidecars = {f"{contract.TEXTURE_FILE}.import"}
    actual = {path.name for path in output.iterdir()}
    unexpected = actual - expected_entries - allowed_sidecars
    missing = expected_entries - actual
    if unexpected or missing:
        errors.append(
            f"output directory contains missing or unmanaged files: {sorted(unexpected | missing)}"
        )
    return errors


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Verify a packaged P1 hub-navigation pack.")
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args(argv)
    errors = verify_output(args.output)
    if errors:
        for error in errors:
            print(f"ERROR: {error}")
        return 1
    print(
        f"PASS: verified {len(contract.SPRITE_IDS)} sprites, pixels, palette cap, mask distinctness "
        "and provenance hashes"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
