#!/usr/bin/env python3
"""Mechanical verifier and QA converter for scene_rework_v01."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from PIL import Image


EXPECTED_NATIVE_VIEW = (640, 360)
EXPECTED_RESOURCE_PREFIX = "res://art/production/p1/scene_rework_v01"


@dataclass(frozen=True)
class AtlasContract:
    size: tuple[int, int]
    sprite_ids: tuple[str, ...]
    cell_size: tuple[int, int]
    anchors: tuple[tuple[int, int], ...]


ATLAS_CONTRACTS: dict[str, AtlasContract] = {
    "ground": AtlasContract((1024, 640), ("scene.ground",), (1024, 640), ((0, 0),)),
    "decals": AtlasContract(
        (512, 96),
        ("ground.snow_wedge", "ground.snow_strip", "ground.rubble_apron", "ground.foundation"),
        (128, 96),
        ((64, 90), (64, 90), (64, 90), (64, 90)),
    ),
    "ruins": AtlasContract(
        (512, 128),
        ("ruin.wall_corner", "ruin.gate", "ruin.low_pier", "ruin.broken_wall"),
        (128, 128),
        ((64, 120), (64, 120), (64, 120), (64, 120)),
    ),
    "ranger": AtlasContract(
        (128, 48),
        ("ranger.south.idle", "ranger.north.idle", "ranger.east.idle", "ranger.west.idle"),
        (32, 48),
        ((16, 44), (16, 44), (16, 44), (16, 44)),
    ),
    "boss_body": AtlasContract(
        (256, 128),
        ("boss.body_phase1", "boss.body_phase2"),
        (128, 128),
        ((64, 120), (64, 120)),
    ),
    "boss_hands": AtlasContract(
        (96, 64),
        ("boss.hand_left", "boss.hand_right"),
        (48, 64),
        ((24, 56), (24, 56)),
    ),
    "boss_core": AtlasContract(
        (64, 64),
        ("boss.core_phase1", "boss.core_phase2"),
        (32, 64),
        ((16, 56), (16, 56)),
    ),
}

EXPECTED_SPRITES = {
    sprite_id: atlas_key
    for atlas_key, contract in ATLAS_CONTRACTS.items()
    for sprite_id in contract.sprite_ids
}
EXPECTED_ARTIFACTS = (*(f"{key}.png" for key in ATLAS_CONTRACTS), "atlas.json", "contact_sheet.png")
LAYOUT_DECAL_IDS = set(ATLAS_CONTRACTS["decals"].sprite_ids)
LAYOUT_STRUCTURE_IDS = set(ATLAS_CONTRACTS["ruins"].sprite_ids)


def _load_json(path: Path) -> dict[str, Any]:
    try:
        with path.open("r", encoding="utf-8") as handle:
            value = json.load(handle)
    except (OSError, json.JSONDecodeError) as exc:
        raise ValueError(f"cannot read JSON {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise ValueError(f"JSON root is not an object: {path}")
    return value


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _integer_pair(value: Any, name: str, errors: list[str]) -> tuple[int, int] | None:
    if (
        not isinstance(value, list)
        or len(value) != 2
        or any(isinstance(item, bool) or not isinstance(item, int) for item in value)
    ):
        errors.append(f"{name} must be an integer pair")
        return None
    return value[0], value[1]


def _integer_rect(value: Any, name: str, errors: list[str]) -> tuple[int, int, int, int] | None:
    if (
        not isinstance(value, list)
        or len(value) != 4
        or any(isinstance(item, bool) or not isinstance(item, int) for item in value)
    ):
        errors.append(f"{name} must be an integer [x,y,w,h]")
        return None
    x, y, width, height = value
    if width <= 0 or height <= 0 or x < 0 or y < 0:
        errors.append(f"{name} has negative origin or empty size")
        return None
    return x, y, width, height


def _expected_rect(atlas_key: str, sprite_id: str) -> tuple[int, int, int, int]:
    """Return the build-generated slot from the recipe order encoded in the contract."""
    cell_width, cell_height = ATLAS_CONTRACTS[atlas_key].cell_size
    index = ATLAS_CONTRACTS[atlas_key].sprite_ids.index(sprite_id)
    return index * cell_width, 0, cell_width, cell_height


def _pixel_stats(cell: Image.Image) -> tuple[bool, set[tuple[int, int, int, int]]]:
    raw = cell.tobytes()
    opaque_colors: set[tuple[int, int, int, int]] = set()
    binary_alpha = True
    for offset in range(0, len(raw), 4):
        alpha = raw[offset + 3]
        if alpha not in (0, 255):
            binary_alpha = False
        if alpha != 0:
            opaque_colors.add((raw[offset], raw[offset + 1], raw[offset + 2], alpha))
    return binary_alpha, opaque_colors


def _load_images(output: Path, atlas: dict[str, Any], errors: list[str]) -> dict[str, Image.Image]:
    textures = atlas.get("textures")
    if not isinstance(textures, dict):
        errors.append("atlas textures must be an object")
        return {}
    loaded: dict[str, Image.Image] = {}
    for key in sorted(set(textures) & set(ATLAS_CONTRACTS)):
        try:
            with Image.open(output / f"{key}.png") as image:
                image.load()
                if image.mode != "RGBA":
                    errors.append(f"texture {key} is {image.mode}, expected RGBA")
                loaded[key] = image.copy()
        except (OSError, ValueError) as exc:
            errors.append(f"texture {key} cannot be opened: {exc}")
    return loaded


def _validate_atlas_contract(
    output: Path,
) -> tuple[list[str], dict[str, Any], dict[str, Image.Image], dict[str, Any]]:
    errors: list[str] = []
    try:
        atlas = _load_json(output / "atlas.json")
    except ValueError as exc:
        return [str(exc)], {}, {}, {}

    if atlas.get("schema_version") != 1:
        errors.append("atlas schema_version must be 1")
    if tuple(atlas.get("native_view", ())) != EXPECTED_NATIVE_VIEW:
        errors.append("atlas native_view must be [640,360]")

    textures = atlas.get("textures")
    sprites = atlas.get("sprites")
    animations = atlas.get("animations")
    if not isinstance(textures, dict):
        errors.append("atlas textures must be an object")
        textures = {}
    if not isinstance(sprites, dict):
        errors.append("atlas sprites must be an object")
        sprites = {}
    if not isinstance(animations, dict):
        errors.append("atlas animations must be an object")

    if set(textures) != set(ATLAS_CONTRACTS):
        errors.append("atlas texture keys must exactly match the 7-atlas contract")
    if set(sprites) != set(EXPECTED_SPRITES):
        missing = ",".join(sorted(set(EXPECTED_SPRITES) - set(sprites)))
        extra = ",".join(sorted(set(sprites) - set(EXPECTED_SPRITES)))
        errors.append(f"atlas sprite IDs must be exactly 19 (missing={missing}; extra={extra})")

    images = _load_images(output, atlas, errors)
    for key, contract in ATLAS_CONTRACTS.items():
        metadata = textures.get(key)
        if not isinstance(metadata, dict):
            continue
        expected_path = f"{EXPECTED_RESOURCE_PREFIX}/{key}.png"
        if metadata.get("path") != expected_path:
            errors.append(f"texture {key} path must be {expected_path}")
        if (metadata.get("width"), metadata.get("height")) != contract.size:
            errors.append(f"texture {key} metadata dimensions must be {contract.size[0]}x{contract.size[1]}")
        image = images.get(key)
        if image is not None and image.size != contract.size:
            errors.append(f"texture {key} PNG dimensions must be {contract.size[0]}x{contract.size[1]}")

    for atlas_key, contract in ATLAS_CONTRACTS.items():
        for index, sprite_id in enumerate(contract.sprite_ids):
            metadata = sprites.get(sprite_id)
            if not isinstance(metadata, dict):
                continue
            if metadata.get("texture") != atlas_key:
                errors.append(f"sprite {sprite_id} must reference texture {atlas_key}")
            rect = _integer_rect(metadata.get("rect"), f"sprite {sprite_id} rect", errors)
            anchor = _integer_pair(metadata.get("anchor"), f"sprite {sprite_id} anchor", errors)
            if rect is not None and rect != _expected_rect(atlas_key, sprite_id):
                errors.append(f"sprite {sprite_id} rect differs from its contract slot")
            if sprite_id == "scene.ground":
                # The recipe owns this full-frame origin anchor (currently [512,640]);
                # the consumer draws scene.ground at the world origin.
                pass
            elif anchor is not None and anchor != contract.anchors[index]:
                errors.append(f"sprite {sprite_id} anchor differs from its contract")

            image = images.get(atlas_key)
            if rect is None or image is None:
                continue
            x, y, width, height = rect
            if x < 0 or y < 0 or x + width > image.width or y + height > image.height:
                errors.append(f"sprite {sprite_id} rect lies outside its texture")
                continue
            cell = image.crop((x, y, x + width, y + height))
            alpha = cell.getchannel("A")
            binary_alpha, opaque_colors = _pixel_stats(cell)
            if not binary_alpha:
                errors.append(f"sprite {sprite_id} has non-binary alpha")
            if not opaque_colors:
                errors.append(f"sprite {sprite_id} rect is empty")

            budget = 12 if sprite_id.startswith(("ranger.", "boss.")) else 8
            if len(opaque_colors) > budget:
                errors.append(f"sprite {sprite_id} uses {len(opaque_colors)} opaque colors, budget {budget}")

            if sprite_id == "scene.ground":
                if alpha.getbbox() != (0, 0, width, height):
                    errors.append("scene.ground is not fully opaque")
                _validate_ground_not_obvious_tile(cell, errors)
            else:
                bbox = alpha.getbbox()
                if bbox is None:
                    errors.append(f"sprite {sprite_id} has no visible pixels")
                elif bbox[0] < 2 or bbox[1] < 2 or bbox[2] > width - 2 or bbox[3] > height - 2:
                    errors.append(f"sprite {sprite_id} violates the minimum 2px internal padding")

    for animation_id, raw in animations.items():
        if not isinstance(raw, dict):
            errors.append(f"animation {animation_id} must be an object")
            continue
        frames = raw.get("frames")
        if not isinstance(frames, list) or not frames:
            errors.append(f"animation {animation_id} frames must be a non-empty array")
            continue
        for frame in frames:
            if frame not in sprites:
                errors.append(f"animation {animation_id} references missing sprite {frame}")
    return errors, atlas, images, sprites


def _validate_ground_not_obvious_tile(ground: Image.Image, errors: list[str]) -> None:
    width, height = ground.size
    horizontal = (
        ground.crop((0, 0, width - 64, height)).tobytes()
        == ground.crop((64, 0, width, height)).tobytes()
    )
    vertical = (
        ground.crop((0, 0, width, height - 64)).tobytes()
        == ground.crop((0, 64, width, height)).tobytes()
    )
    if horizontal or vertical:
        errors.append("scene.ground is exactly repetitive at a 64px offset")


def _safe_artifact_path(output: Path, value: Any) -> Path | None:
    if not isinstance(value, str) or not value:
        return None
    path = Path(value)
    resolved = path.resolve() if path.is_absolute() else (output / path).resolve()
    if resolved.parent != output.resolve():
        raise ValueError(f"artifact escapes output directory: {value}")
    return resolved


def _validate_provenance(manifest: dict[str, Any], errors: list[str]) -> None:
    """Re-hash the recipe and every recorded source PNG from the old manifest fields."""
    config_path_value = manifest.get("config_path")
    if not isinstance(config_path_value, str) or not config_path_value:
        errors.append("manifest config_path is missing")
        config_path = None
    else:
        config_path = Path(config_path_value)
        if not config_path.is_absolute():
            errors.append("manifest config_path must be absolute")
            config_path = None
        elif not config_path.is_file():
            errors.append(f"manifest config is missing: {config_path}")
        elif manifest.get("config_sha256") != _sha256(config_path):
            errors.append("manifest config hash mismatch")

    sources = manifest.get("sources")
    if not isinstance(sources, dict) or not sources:
        errors.append("manifest sources must be a non-empty object")
        return
    for key, raw in sources.items():
        label = f"source {key}"
        if not isinstance(raw, dict):
            errors.append(f"manifest {label} must be an object")
            continue
        path_value = raw.get("path")
        if not isinstance(path_value, str) or not path_value:
            errors.append(f"manifest {label} path is missing")
            continue
        source_path = Path(path_value)
        if not source_path.is_absolute():
            errors.append(f"manifest {label} path must be absolute")
            continue
        if not source_path.is_file():
            errors.append(f"manifest {label} PNG is missing: {source_path}")
            continue
        if raw.get("sha256") != _sha256(source_path):
            errors.append(f"manifest {label} hash mismatch")
        try:
            with Image.open(source_path) as image:
                image.load()
                expected_size = (raw.get("width"), raw.get("height"))
                if image.size != expected_size:
                    errors.append(
                        f"manifest {label} dimensions are {image.size}, recorded {expected_size}"
                    )
        except (OSError, ValueError) as exc:
            errors.append(f"manifest {label} PNG cannot be opened: {exc}")


def _validate_manifest(output: Path) -> list[str]:
    errors: list[str] = []
    try:
        manifest = _load_json(output / "manifest.json")
    except ValueError as exc:
        return [str(exc)]
    if manifest.get("schema_version") != 1:
        errors.append("manifest schema_version must be 1")
    _validate_provenance(manifest, errors)
    artifacts = manifest.get("artifacts")
    if not isinstance(artifacts, list):
        errors.append("manifest artifacts must be an array")
        return errors

    recorded: dict[Path, dict[str, Any]] = {}
    for index, artifact in enumerate(artifacts):
        if not isinstance(artifact, dict):
            errors.append(f"manifest artifact[{index}] must be an object")
            continue
        try:
            artifact_path = _safe_artifact_path(output, artifact.get("path"))
        except ValueError as exc:
            errors.append(str(exc))
            continue
        if artifact_path is None:
            errors.append(f"manifest artifact[{index}] path is invalid")
            continue
        if artifact_path in recorded:
            errors.append(f"manifest artifact path is duplicated: {artifact_path.name}")
        recorded[artifact_path] = artifact
        if not artifact_path.is_file():
            errors.append(f"manifest artifact is missing: {artifact_path.name}")
            continue
        if artifact.get("sha256") != _sha256(artifact_path):
            errors.append(f"manifest artifact hash mismatch: {artifact_path.name}")
        if artifact.get("bytes") != artifact_path.stat().st_size:
            errors.append(f"manifest artifact byte count mismatch: {artifact_path.name}")

    expected = {output / name for name in EXPECTED_ARTIFACTS}
    if set(recorded) != expected:
        missing = sorted(path.name for path in expected - set(recorded))
        extra = sorted(path.name for path in set(recorded) - expected)
        errors.append(f"manifest artifact list is incomplete or has extras (missing={missing}; extra={extra})")

    contact = output / "contact_sheet.png"
    if contact.is_file():
        try:
            with Image.open(contact) as image:
                image.load()
        except (OSError, ValueError) as exc:
            errors.append(f"contact sheet is not a valid PNG: {exc}")
    return errors


def _layout_cell_inside(
    feet: tuple[int, int], anchor: tuple[int, int], size: tuple[int, int], world: tuple[int, int]
) -> bool:
    world_width, world_height = world
    left, top = feet[0] - anchor[0], feet[1] - anchor[1]
    return (
        0 <= feet[0] < world_width
        and 0 <= feet[1] < world_height
        and left >= 0
        and top >= 0
        and left + size[0] <= world_width
        and top + size[1] <= world_height
    )


def validate_layout(path: Path, sprites: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    try:
        layout = _load_json(path)
    except ValueError as exc:
        return [str(exc)]

    fixed_pairs = {
        "world_size": (1024, 640),
        "hero_start": (430, 360),
        "boss_feet": (625, 360),
        "tower_feet": (175, 405),
    }
    for field, expected in fixed_pairs.items():
        if _integer_pair(layout.get(field), f"layout {field}", errors) != expected:
            errors.append(f"layout {field} must equal {list(expected)}")

    enemies = layout.get("enemy_positions")
    expected_enemies = ((300, 290), (480, 470), (570, 235))
    if not isinstance(enemies, list) or len(enemies) != 3:
        errors.append("layout enemy_positions must contain exactly three points")
    else:
        for index, expected in enumerate(expected_enemies):
            if _integer_pair(enemies[index], f"layout enemy_positions[{index}]", errors) != expected:
                errors.append(f"layout enemy_positions[{index}] must equal {list(expected)}")

    for field, expected_ids in (("decals", LAYOUT_DECAL_IDS), ("structures", LAYOUT_STRUCTURE_IDS)):
        raw = layout.get(field)
        if not isinstance(raw, list) or not raw:
            errors.append(f"layout {field} must be a non-empty array")
            continue
        seen_pairs: set[tuple[str, int, int]] = set()
        ids: set[str] = set()
        for index, placement in enumerate(raw):
            label = f"layout {field}[{index}]"
            if not isinstance(placement, dict):
                errors.append(f"{label} must be an object")
                continue
            sprite_id = placement.get("id")
            if not isinstance(sprite_id, str) or not sprite_id:
                errors.append(f"{label} id must be a non-empty string")
                continue
            ids.add(sprite_id)
            feet = _integer_pair(placement.get("feet"), f"{label} feet", errors)
            if feet is not None:
                pair = (sprite_id, feet[0], feet[1])
                if pair in seen_pairs:
                    errors.append(
                        f"{label} duplicates placement {sprite_id} at feet {list(feet)}"
                    )
                seen_pairs.add(pair)
            metadata = sprites.get(sprite_id)
            if not isinstance(metadata, dict):
                errors.append(f"{label} references unknown sprite {sprite_id}")
                continue
            rect = _integer_rect(metadata.get("rect"), f"sprite {sprite_id} rect", errors)
            anchor = _integer_pair(metadata.get("anchor"), f"sprite {sprite_id} anchor", errors)
            if feet is None or rect is None or anchor is None:
                continue
            if not _layout_cell_inside(feet, anchor, (rect[2], rect[3]), (1024, 640)):
                errors.append(f"{label} anchored cell lies outside the world")
        unknown = ids - expected_ids
        if unknown:
            errors.append(
                f"layout {field} IDs must be from {sorted(expected_ids)} (unknown={sorted(unknown)})"
            )
    return errors


def _write_mechanical_qa(
    output: Path, atlas: dict[str, Any], images: dict[str, Image.Image], destination: Path
) -> None:
    if destination.resolve() == output.resolve() or output.resolve() in destination.resolve().parents:
        raise ValueError("QA output must be a separate directory outside the atlas output")
    if destination.exists():
        if not destination.is_dir():
            raise ValueError(f"QA output is not a directory: {destination}")
        if any(destination.iterdir()):
            raise ValueError(f"QA output directory is not empty: {destination}")
    else:
        destination.mkdir(parents=True)

    artifacts: list[dict[str, Any]] = []

    def save(image: Image.Image, name: str, operation: str) -> None:
        path = destination / name
        image.save(path)
        artifacts.append(
            {
                "file": name,
                "operation": operation,
                "width": image.width,
                "height": image.height,
                "sha256": _sha256(path),
            }
        )

    def conversions(image: Image.Image, stem: str) -> None:
        save(image.copy(), f"{stem}_100pct.png", "real_artifact_100pct")
        save(
            image.resize((image.width * 2, image.height * 2), Image.Resampling.NEAREST),
            f"{stem}_2x.png",
            "nearest_neighbor_2x",
        )
        save(
            image.resize((image.width // 4, image.height // 4), Image.Resampling.NEAREST),
            f"{stem}_25pct.png",
            "nearest_neighbor_25pct",
        )
        save(image.convert("L").convert("RGBA"), f"{stem}_grayscale.png", "grayscale")

    for key in sorted(images):
        conversions(images[key], f"atlas_{key}")
    with Image.open(output / "contact_sheet.png") as contact:
        contact.load()
        conversions(contact.copy(), "atlas_contact")

    report = {
        "kind": "mechanical_atlas_qa_conversion_not_visual_approval",
        "source_output": str(output),
        "atlas_sha256": _sha256(output / "atlas.json"),
        "texture_count": len(images),
        "sprite_count": len(atlas.get("sprites", {})),
        "operations": ["100pct", "2x_nearest", "25pct_nearest", "grayscale"],
        "artifacts": artifacts,
    }
    (destination / "QA_REPORT.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )


def verify_output(
    output: Path, layout_path: Path | None = None
) -> tuple[list[str], dict[str, Any], dict[str, Image.Image]]:
    output = output.resolve()
    if not output.is_dir():
        return [f"output directory is missing: {output}"], {}, {}
    errors, atlas, images, sprites = _validate_atlas_contract(output)
    errors.extend(_validate_manifest(output))
    if layout_path is None:
        candidate = output / "layout.json"
        layout_path = candidate if candidate.is_file() else None
    if layout_path is not None:
        errors.extend(validate_layout(layout_path.resolve(), sprites))
    return errors, atlas, images


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path, help="generated scene_rework_v01 directory")
    parser.add_argument("--layout", type=Path, help="layout.json; defaults to output/layout.json when present")
    parser.add_argument("--qa-output", type=Path, help="new empty directory for mechanical QA conversions")
    args = parser.parse_args(argv)

    try:
        errors, atlas, images = verify_output(args.output, args.layout)
        if args.qa_output is not None and not errors:
            _write_mechanical_qa(args.output.resolve(), atlas, images, args.qa_output.resolve())
    except (OSError, ValueError) as exc:
        errors = [f"VERIFY FAILED: {exc}"]

    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        print(f"VERIFY FAIL: {len(errors)} error(s); mechanical only, not visual approval")
        return 1
    layout_note = (
        "layout checked"
        if args.layout is not None or (args.output / "layout.json").is_file()
        else "layout not supplied"
    )
    qa_note = f"; QA written to {args.qa_output}" if args.qa_output is not None else ""
    print(f"VERIFY PASS: 7 atlases, 19 sprites, {layout_note}; mechanical only, not visual approval{qa_note}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
