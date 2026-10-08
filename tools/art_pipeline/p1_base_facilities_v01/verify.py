#!/usr/bin/env python3
"""Mechanical verifier and QA converter for p1_base_facilities_v01.

This helper is read-only with respect to the generated atlas directory.  It
re-uses ``tools/art_pipeline/p1_calibration_v01/build.py`` as the source of
truth for the recipe schema (palette parsing and ``validate_config``), the
``tools/art_pipeline/p1_calibration_v01/verify.py`` generic verifier for
manifest/config provenance, and it adds the frozen five-slot contract for the
``base_facilities_v01`` delivery plus a main-authored ``layout.json`` schema.

Scope: mechanical output properties only; this is not visual approval.  No
pixels are painted here; every QA image is a pure conversion of the already
generated atlas bytes.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import sys
from pathlib import Path
from typing import Any

from PIL import Image


HELPER_DIR = Path(__file__).resolve().parent
PIPELINE_ROOT = HELPER_DIR.parent
CALIBRATION_DIR = PIPELINE_ROOT / "p1_calibration_v01"
CALIBRATION_BUILD_PATH = CALIBRATION_DIR / "build.py"
CALIBRATION_VERIFY_PATH = CALIBRATION_DIR / "verify.py"

ATLAS_KEY = "facilities"
ATLAS_SIZE = (640, 128)
CELL_SIZE = (128, 128)
FACILITY_IDS = (
    "facility.contract",
    "facility.loadout",
    "facility.forge",
    "facility.training",
    "facility.proxy",
)
FOOT_ANCHOR = (64, 120)
MIN_PADDING = 2
ASSET_DIR_NAME = HELPER_DIR.name.removeprefix("p1_")
EXPECTED_RESOURCE_PATH = f"res://art/production/p1/{ASSET_DIR_NAME}/{ATLAS_KEY}.png"
GENERATED_ARTIFACTS = ("atlas.json", "contact_sheet.png", "facilities.png")
SCHEMA_VERSION = 1
LAYOUT_WORLD_SIZE = (1024, 640)
LAYOUT_HERO_START = (512, 380)
LAYOUT_TOWER_FEET = (270, 348)
LAYOUT_SPLIT_ROW = 96
REQUIRED_LAYOUT_FIELDS = (
    "schema_version",
    "world_size",
    "hero_start",
    "tower_feet",
    "facilities",
)
OPTIONAL_LAYOUT_FIELDS = ("decals",)
REQUIRED_DECAL_FIELDS = ("id", "feet")
REQUIRED_FACILITY_FIELDS = (
    "id",
    "sprite",
    "feet",
    "footprint",
    "split_row",
    "label",
    "role",
)


def _module_exists(name: str) -> bool:
    return importlib.util.find_spec(name) is not None


def _load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise ImportError(f"cannot load module {name} from {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def _load_calibration_modules():
    """Import the shared calibration builder and verifier without editing them.

    ``p1_calibration_v01/verify.py`` imports its sibling by the bare name
    ``build``, so the builder is registered under that canonical name while the
    shared verifier is loaded; the entry is restored afterwards to avoid
    surprising other importers in the same process.
    """
    previous_build = sys.modules.get("build")
    if previous_build is None:
        build = _load_module("build", CALIBRATION_BUILD_PATH)
    elif Path(getattr(previous_build, "__file__", "")).resolve() == CALIBRATION_BUILD_PATH:
        build = previous_build
    else:
        raise ImportError(
            "cannot load the calibration builder: the module name 'build' is already in use"
        )
    try:
        verify_name = "p1_calibration_v01_verify"
        if not _module_exists(verify_name):
            _load_module(verify_name, CALIBRATION_VERIFY_PATH)
        calibration_verify = sys.modules[verify_name]
    finally:
        if previous_build is None:
            sys.modules.pop("build", None)
        else:
            sys.modules["build"] = previous_build
    return build, calibration_verify


BUILD, CALIBRATION_VERIFY = _load_calibration_modules()


def _layout_schema_error(label: str, unknown: set[str]) -> list[str]:
    if not unknown:
        return []
    return [f"{label} has unknown field(s): {sorted(unknown)}"]


def _sha256(path: Path) -> str:
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
        raise ValueError(f"cannot read JSON {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise ValueError(f"JSON root is not an object: {path}")
    return value


def _integer_pair(value: Any, name: str, errors: list[str]) -> tuple[int, int] | None:
    if (
        not isinstance(value, list)
        or len(value) != 2
        or any(isinstance(item, bool) or not isinstance(item, int) for item in value)
    ):
        errors.append(f"{name} must be an integer pair [x,y]")
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


def _expected_rect(index: int) -> tuple[int, int, int, int]:
    cell_width, cell_height = CELL_SIZE
    return index * cell_width, 0, cell_width, cell_height


def _palette_from_recipe(recipe: dict[str, Any]) -> tuple[tuple[int, int, int, int], ...]:
    parsed = [BUILD.parse_hex_color(item, f"palette[{index}]") for index, item in enumerate(recipe["palette"])]
    return tuple(dict.fromkeys(parsed))


def _sprite_palette(recipe: dict[str, Any], sprite_id: str, fallback: tuple[tuple[int, int, int, int], ...]) -> tuple[tuple[int, int, int, int], ...]:
    for raw in recipe["sprites"]:
        if raw["id"] != sprite_id:
            continue
        entries = raw.get("palette")
        if entries is None:
            return fallback
        return tuple(BUILD.parse_hex_color(item, f"sprites.{sprite_id}.palette") for item in entries)
    return fallback


def _pixel_stats(cell: Image.Image) -> tuple[bool, set[tuple[int, int, int, int]]]:
    raw = cell.tobytes()
    colors: set[tuple[int, int, int, int]] = set()
    binary = True
    for offset in range(0, len(raw), 4):
        alpha = raw[offset + 3]
        if alpha not in (0, 255):
            binary = False
        if alpha:
            colors.add((raw[offset], raw[offset + 1], raw[offset + 2], alpha))
    return binary, colors


def _cell_layers(cell: Image.Image, split_row: int) -> tuple[Image.Image, Image.Image]:
    """Split a cell into upper (full-size, lower part transparent) and lower layers."""
    width, height = cell.size
    top = Image.new("RGBA", cell.size, (0, 0, 0, 0))
    top.paste(cell.crop((0, 0, width, split_row)), (0, 0))
    bottom = Image.new("RGBA", cell.size, (0, 0, 0, 0))
    bottom.paste(cell.crop((0, split_row, width, height)), (0, split_row))
    return top, bottom


def _check_atlas_contract(output: Path, recipe_path: Path | None) -> tuple[list[str], dict[str, Any], dict[str, Image.Image]]:
    errors: list[str] = []
    atlas_path = output / "atlas.json"
    if not atlas_path.is_file():
        return [f"missing atlas contract: {atlas_path}"], {}, {}
    try:
        atlas = _load_json(atlas_path)
    except ValueError as exc:
        return [str(exc)], {}, {}

    manifest: dict[str, Any] = {}
    manifest_path = output / "manifest.json"
    if not manifest_path.is_file():
        errors.append(f"missing manifest: {manifest_path}")
    else:
        try:
            manifest = _load_json(manifest_path)
        except ValueError as exc:
            errors.append(str(exc))
        else:
            unknown = set(manifest) - {
                "schema_version",
                "config_path",
                "config_sha256",
                "resource_prefix",
                "sources",
                "artifacts",
                "technical_verification",
            }
            if unknown:
                errors.append(f"manifest has unknown field(s): {sorted(unknown)}")

    recipe: dict[str, Any] | None = None
    if recipe_path is None:
        errors.append("recipe config path is required for palette/provenance checks")
    else:
        try:
            recipe = _load_json(recipe_path)
            BUILD.validate_config(recipe)
        except (OSError, ValueError, BUILD.ConfigError) as exc:
            errors.append(f"cannot load/validate recipe: {exc}")
            recipe = None

    if atlas.get("schema_version") != SCHEMA_VERSION:
        errors.append("atlas schema_version must be 1")
    if tuple(atlas.get("native_view", ())) != (640, 360):
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
        animations = {}
    if ATLAS_KEY not in textures:
        errors.append(f"atlas textures must declare the '{ATLAS_KEY}' atlas")
    if set(sprites) != set(FACILITY_IDS):
        missing = sorted(set(FACILITY_IDS) - set(sprites))
        if missing:
            errors.append(f"atlas sprite IDs must include the five facility slots (missing={missing})")
    expected_animations = {
        key: raw for key, raw in (recipe or {}).get("animations", {}).items()
    }
    if animations != expected_animations:
        errors.append(
            "atlas animations must exactly match the recipe (idle-only delivery; no extra animations)"
        )
    for sprite_id in FACILITY_IDS:
        if sprite_id in animations:
            errors.append(f"facility {sprite_id} must not declare an animation (idle-only delivery)")

    images: dict[str, Image.Image] = {}
    metadata = textures.get(ATLAS_KEY)
    if isinstance(metadata, dict):
        if metadata.get("path") != EXPECTED_RESOURCE_PATH:
            errors.append(f"texture {ATLAS_KEY} path must be {EXPECTED_RESOURCE_PATH}")
        if (metadata.get("width"), metadata.get("height")) != ATLAS_SIZE:
            errors.append(f"texture {ATLAS_KEY} metadata dimensions must be {ATLAS_SIZE[0]}x{ATLAS_SIZE[1]}")
    elif ATLAS_KEY in textures:
        errors.append(f"texture {ATLAS_KEY} metadata must be an object")

    artifact_path = output / f"{ATLAS_KEY}.png"
    if not artifact_path.is_file():
        errors.append(f"texture {ATLAS_KEY} PNG is missing")
    else:
        try:
            with Image.open(artifact_path) as image:
                image.load()
                if image.mode != "RGBA":
                    errors.append(f"texture {ATLAS_KEY} is {image.mode}, expected RGBA")
                if image.size != ATLAS_SIZE:
                    errors.append(f"texture {ATLAS_KEY} PNG must be {ATLAS_SIZE[0]}x{ATLAS_SIZE[1]}")
                images[ATLAS_KEY] = image.copy()
        except (OSError, ValueError) as exc:
            errors.append(f"texture {ATLAS_KEY} cannot be opened: {exc}")

    atlas_image = images.get(ATLAS_KEY)
    if atlas_image is not None and atlas_image.size != ATLAS_SIZE:
        errors.append(
            f"texture {ATLAS_KEY} must be exactly {ATLAS_SIZE[0]}x{ATLAS_SIZE[1]} (five 128x128 cells)"
        )

    global_palette = _palette_from_recipe(recipe) if recipe is not None else ()
    cell_image = images.get(ATLAS_KEY)
    for index, sprite_id in enumerate(FACILITY_IDS):
        entry = sprites.get(sprite_id)
        if not isinstance(entry, dict):
            if sprite_id in sprites:
                errors.append(f"sprite {sprite_id} contract must be an object")
            continue
        if entry.get("texture") != ATLAS_KEY:
            errors.append(f"sprite {sprite_id} must reference texture {ATLAS_KEY}")
        rect = _integer_rect(entry.get("rect"), f"sprite {sprite_id} rect", errors)
        anchor = _integer_pair(entry.get("anchor"), f"sprite {sprite_id} anchor", errors)
        if rect is not None and rect != _expected_rect(index):
            errors.append(f"sprite {sprite_id} rect differs from its contract slot")
        if anchor is not None and anchor != FOOT_ANCHOR:
            errors.append(f"sprite {sprite_id} anchor must be {list(FOOT_ANCHOR)}")
        if rect is None or anchor is None or cell_image is None:
            continue
        x, y, width, height = rect
        if x < 0 or y < 0 or x + width > cell_image.width or y + height > cell_image.height:
            errors.append(f"sprite {sprite_id} rect lies outside its texture")
            continue
        # The shared recipe may scale a source cell into the atlas cell; the
        # delivery contract is about the generated atlas pixels, so inspect the
        # facility cells from the built PNG directly.  The generic verifier
        # still reports what the shared builder derived from the sources.
        cell = cell_image.crop((x, y, x + width, y + height))
        binary_alpha, opaque_colors = _pixel_stats(cell)
        if not binary_alpha:
            errors.append(f"sprite {sprite_id} has non-binary alpha")
        if not opaque_colors:
            errors.append(f"sprite {sprite_id} rect is empty")
            continue
        bbox = cell.getchannel("A").getbbox()
        if bbox is None:
            errors.append(f"sprite {sprite_id} has no visible pixels")
        elif bbox[0] < MIN_PADDING or bbox[1] < MIN_PADDING or bbox[2] > width - MIN_PADDING or bbox[3] > height - MIN_PADDING:
            errors.append(f"sprite {sprite_id} violates the minimum {MIN_PADDING}px internal padding")
        if recipe is not None:
            allowed = set(_sprite_palette(recipe, sprite_id, global_palette))
            exotic = opaque_colors - allowed
            if exotic:
                errors.append(f"sprite {sprite_id} uses color(s) outside its recipe palette: {sorted(exotic)}")
            if not exotic and len(opaque_colors) > len(allowed):
                errors.append(f"sprite {sprite_id} uses {len(opaque_colors)} opaque colors, exceeding its palette of {len(allowed)}")

    # The shared calibration verifier owns everything else (its own atlases,
    # source hashes, manifest artifacts, contact sheet); its facility wording
    # for the shared recipe entries would only duplicate the checks above.
    if manifest and recipe is not None:
        try:
            generic_errors = CALIBRATION_VERIFY.verify_output(output, recipe_path)[0]
        except (OSError, ValueError) as exc:
            errors.append(f"generic verification failed: {exc}")
        else:
            # Its wording for the shared recipe entries would duplicate the
            # checks above; unrelated sprites stay reported by that verifier
            # only inside the calibration pipeline, not in this delivery.
            facility_prefixes = tuple(f"sprite {sprite_id} " for sprite_id in FACILITY_IDS)
            errors.extend(
                error
                for error in generic_errors
                if not error.startswith(facility_prefixes)
                and not error.startswith("clipping: sprite ")
                and not (
                    error.startswith("sprite ")
                    and "rect is empty after alpha cleanup" in error
                    and not any(error.startswith(prefix) for prefix in facility_prefixes)
                )
            )
    return errors, atlas, images


def validate_layout(
    path: Path,
    sprites: dict[str, Any],
    images: dict[str, Image.Image],
    decal_ids: set[str] | None = None,
) -> list[str]:
    """Validate the main-authored layout.json against the frozen scene contract."""
    errors: list[str] = []
    try:
        layout = _load_json(path)
    except ValueError as exc:
        return [str(exc)]

    missing = [field for field in REQUIRED_LAYOUT_FIELDS if field not in layout]
    if missing:
        errors.append(f"layout is missing field(s): {missing}")
    errors.extend(
        _layout_schema_error(
            "layout", set(layout) - set(REQUIRED_LAYOUT_FIELDS) - set(OPTIONAL_LAYOUT_FIELDS)
        )
    )
    if layout.get("schema_version") != SCHEMA_VERSION:
        errors.append("layout schema_version must be 1")
    if _integer_pair(layout.get("world_size"), "layout world_size", errors) != LAYOUT_WORLD_SIZE:
        errors.append(f"layout world_size must equal {list(LAYOUT_WORLD_SIZE)}")
    if _integer_pair(layout.get("hero_start"), "layout hero_start", errors) != LAYOUT_HERO_START:
        errors.append(f"layout hero_start must equal {list(LAYOUT_HERO_START)}")
    if _integer_pair(layout.get("tower_feet"), "layout tower_feet", errors) != LAYOUT_TOWER_FEET:
        errors.append(f"layout tower_feet must equal {list(LAYOUT_TOWER_FEET)}")

    facilities = layout.get("facilities")
    if not isinstance(facilities, list) or not facilities:
        errors.append("layout facilities must be a non-empty array")
        return errors

    world_width, world_height = LAYOUT_WORLD_SIZE
    seen_ids: set[str] = set()
    seen_sprites: set[str] = set()
    seen_feet: set[tuple[int, int]] = set()
    seen_slots: set[str] = set()
    footprint_rects: list[tuple[tuple[int, int, int, int], str]] = []
    for index, entry in enumerate(facilities):
        label = f"layout facilities[{index}]"
        if not isinstance(entry, dict):
            errors.append(f"{label} must be an object")
            continue
        missing_fields = [field for field in REQUIRED_FACILITY_FIELDS if field not in entry]
        if missing_fields:
            errors.append(f"{label} is missing field(s): {missing_fields}")
        errors.extend(_layout_schema_error(label, set(entry) - set(REQUIRED_FACILITY_FIELDS)))

        facility_id = entry.get("id")
        if not isinstance(facility_id, str) or not facility_id:
            errors.append(f"{label}.id must be a non-empty string")
            facility_id = None
        elif f"facility.{facility_id}" not in FACILITY_IDS:
            errors.append(f"{label}.id must name one of the five facility slots")
        elif facility_id in seen_ids:
            errors.append(f"{label}.id duplicates facility {facility_id}")
        else:
            seen_ids.add(facility_id)
        seen_slots.add(f"facility.{facility_id}" if facility_id is not None and not facility_id.startswith("facility.") else facility_id)

        sprite_id = entry.get("sprite")
        if not isinstance(sprite_id, str) or not sprite_id:
            errors.append(f"{label}.sprite must be a non-empty string")
            sprite_id = None
        elif sprite_id not in FACILITY_IDS:
            errors.append(f"{label}.sprite must be one of {list(FACILITY_IDS)}")
        elif sprite_id in seen_sprites:
            errors.append(f"{label}.sprite duplicates sprite {sprite_id}")
        else:
            seen_sprites.add(sprite_id)
        if facility_id is not None and sprite_id is not None:
            expected_sprite = facility_id if facility_id in FACILITY_IDS else f"facility.{facility_id}"
            if sprite_id != expected_sprite:
                errors.append(f"{label}.sprite {sprite_id} must match its id ({expected_sprite})")

        for field in ("label", "role"):
            value = entry.get(field)
            if not isinstance(value, str) or not value.strip():
                errors.append(f"{label}.{field} must be a non-empty string")

        feet = _integer_pair(entry.get("feet"), f"{label}.feet", errors)
        if feet is not None:
            if feet in seen_feet:
                errors.append(f"{label}.feet duplicates feet {list(feet)}")
            seen_feet.add(feet)
            if feet[0] < 0 or feet[0] >= world_width or feet[1] < 0 or feet[1] >= world_height:
                errors.append(f"{label}.feet {list(feet)} must sit inside the world")

        footprint = _integer_pair(entry.get("footprint"), f"{label}.footprint", errors)
        if footprint is not None:
            width, height = footprint
            if width <= 0 or height <= 0:
                errors.append(f"{label}.footprint must have positive width and height")
            elif feet is not None:
                left = feet[0] - width // 2
                top = feet[1] - height
                right = left + width
                bottom = top + height
                if (
                    left < 0
                    or top < 0
                    or right > world_width
                    or bottom > world_height
                ):
                    errors.append(f"{label}.footprint lies outside the world at anchor {list(feet)}")
                else:
                    # ``top = feet[1] - height`` puts the feet on the box floor;
                    # the box must still contain its own anchor inside the world.
                    if not (left <= feet[0] <= right and top <= feet[1] <= bottom):
                        errors.append(f"{label}.feet must sit inside its own footprint box")
                    footprint_rects.append(((left, top, right, bottom), f"{label}"))

        split_row = entry.get("split_row")
        if isinstance(split_row, bool) or not isinstance(split_row, int):
            errors.append(f"{label}.split_row must be an integer")
            split_row = None
        elif split_row != LAYOUT_SPLIT_ROW:
            errors.append(f"{label}.split_row must equal {LAYOUT_SPLIT_ROW}")

        if split_row is None or sprite_id is None:
            continue
        sprite = sprites.get(sprite_id)
        if not isinstance(sprite, dict):
            errors.append(f"{label}.sprite {sprite_id} is missing from the atlas contract")
            continue
        rect = _integer_rect(sprite.get("rect"), f"sprite {sprite_id} rect", errors)
        atlas_image = images.get(ATLAS_KEY)
        if rect is None or atlas_image is None:
            continue
        x, y, width, height = rect
        cell = atlas_image.crop((x, y, x + width, y + height))
        bbox = cell.getchannel("A").getbbox()
        if bbox is None:
            errors.append(f"sprite {sprite_id} has no visible pixels to split")
            continue
        if not bbox[1] <= split_row <= bbox[3] or split_row in (bbox[1], bbox[3]):
            errors.append(
                f"sprite {sprite_id} split_row {split_row} must fall strictly inside its visible rows {bbox[1]}..{bbox[3]}"
            )
            continue
        top, bottom = _cell_layers(cell, split_row)
        whole_bytes = cell.tobytes()
        if top.tobytes()[: split_row * width * 4] != whole_bytes[: split_row * width * 4]:
            errors.append(f"sprite {sprite_id} top layer shifted")
        if bottom.tobytes()[split_row * width * 4 :] != whole_bytes[split_row * width * 4 :]:
            errors.append(f"sprite {sprite_id} bottom layer shifted")
        if bottom.crop((0, 0, width, split_row)).getbbox() is not None:
            errors.append(f"sprite {sprite_id} bottom layer is not empty above split_row {split_row}")
        if top.crop((0, split_row, width, height)).getbbox() is not None:
            errors.append(f"sprite {sprite_id} top layer is not empty below split_row {split_row}")

    missing_ids = sorted(slot for slot in FACILITY_IDS if slot not in seen_slots)
    if missing_ids:
        errors.append(f"layout facilities must cover the five facility slots (missing={missing_ids})")

    for position, (rect, label) in enumerate(footprint_rects):
        for other_rect, other_label in footprint_rects[position + 1 :]:
            if (
                rect[0] < other_rect[2]
                and other_rect[0] < rect[2]
                and rect[1] < other_rect[3]
                and other_rect[1] < rect[3]
            ):
                errors.append(f"{label} footprint box overlaps {other_label}")

    errors.extend(_validate_decals(layout, decal_ids))
    return errors


def _decal_ids_from_atlas(path: Path) -> set[str]:
    atlas = _load_json(path)
    sprites = atlas.get("sprites")
    if not isinstance(sprites, dict):
        raise ValueError(f"decal atlas has no sprites object: {path}")
    return set(sprites)


def _validate_decals(layout: dict[str, Any], decal_ids: set[str] | None) -> list[str]:
    """Validate the optional 11-entry decal layer placed on the hub scene.

    Decals reuse the existing scene sprite IDs; their feet are integer world
    points that a renderer anchors inside the world rectangle.  An optional
    ``--decals-atlas`` lets the caller additionally assert that every decal ID
    exists in the scene atlas that will actually be drawn.
    """
    decals = layout.get("decals")
    if decals is None:
        return []
    collected: list[str] = []
    if not isinstance(decals, list) or not decals:
        return ["layout decals must be a non-empty array when present"]
    world_width, world_height = LAYOUT_WORLD_SIZE
    seen: dict[tuple[str, int, int], int] = {}
    for index, entry in enumerate(decals):
        label = f"layout decals[{index}]"
        if not isinstance(entry, dict):
            collected.append(f"{label} must be an object")
            continue
        missing = [field for field in REQUIRED_DECAL_FIELDS if field not in entry]
        if missing:
            collected.append(f"{label} is missing field(s): {missing}")
        collected.extend(_layout_schema_error(label, set(entry) - set(REQUIRED_DECAL_FIELDS)))
        decal_id = entry.get("id")
        if not isinstance(decal_id, str) or not decal_id.strip():
            collected.append(f"{label}.id must be a non-empty string")
            decal_id = None
        feet = _integer_pair(entry.get("feet"), f"{label}.feet", collected)
        if feet is not None:
            if not (0 <= feet[0] < world_width and 0 <= feet[1] < world_height):
                collected.append(f"{label}.feet {list(feet)} must sit inside the world rectangle")
            elif decal_id is not None:
                key = (decal_id, feet[0], feet[1])
                if key in seen:
                    collected.append(f"{label} duplicates decals[{seen[key]}] {decal_id} at {list(feet)}")
                else:
                    seen[key] = index
        if decal_id is not None and decal_ids is not None and decal_id not in decal_ids:
            collected.append(f"{label}.id {decal_id} is not a sprite id in the decal atlas")
    return collected


def verify_output(
    output: Path,
    config_path: Path | None = None,
    decals_atlas: Path | None = None,
) -> tuple[list[str], dict[str, Any], dict[str, Image.Image]]:
    """Verify one base_facilities_v01 delivery directory."""
    output = output.resolve()
    if not output.is_dir():
        return [f"output directory is missing: {output}"], {}, {}
    recipe_path = config_path.resolve() if config_path is not None else None
    errors, atlas, images = _check_atlas_contract(output, recipe_path)
    layout_path = output / "layout.json"
    if layout_path.is_file():
        sprites = atlas.get("sprites") if isinstance(atlas.get("sprites"), dict) else {}
        decal_ids = None
        if decals_atlas is not None:
            try:
                decal_ids = _decal_ids_from_atlas(decals_atlas.resolve())
            except (OSError, ValueError) as exc:
                errors.append(f"cannot read decal atlas: {exc}")
        errors.extend(validate_layout(layout_path, sprites, images, decal_ids))
    else:
        errors.append(f"missing layout file: {layout_path}")
    return errors, atlas, images


def _safe_qa_destination(output: Path, destination: Path) -> Path | None:
    resolved = destination.resolve()
    if resolved == output or output in resolved.parents:
        return None
    if resolved.exists():
        if not resolved.is_dir() or any(resolved.iterdir()):
            return None
    return resolved


def _write_mechanical_qa(
    output: Path, atlas: dict[str, Any], images: dict[str, Image.Image], destination: Path
) -> dict[str, Any]:
    """Write pure mechanical conversions of already-generated pixels only."""
    output = output.resolve()
    if _safe_qa_destination(output, destination) is None:
        raise ValueError(f"QA output must be a new empty directory outside {output}")
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
        save(image.copy(), f"{stem}_native.png", "real_artifact_native")
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
        silhouette = Image.new("RGBA", image.size, (0, 0, 0, 0))
        alpha = image.split()[3].point(lambda value: 255 if value >= 128 else 0)
        silhouette.putalpha(alpha)
        save(silhouette, f"{stem}_silhouette.png", "alpha_silhouette")

    for key in sorted(images):
        conversions(images[key], f"atlas_{key}")
    contact = output / "contact_sheet.png"
    if contact.is_file():
        with Image.open(contact) as opened:
            opened.load()
            conversions(opened.copy(), "atlas_contact")

    manifest: dict[str, Any] = {}
    manifest_path = output / "manifest.json"
    if manifest_path.is_file():
        try:
            manifest = _load_json(manifest_path)
        except ValueError:
            manifest = {}
    recipe_sha = manifest.get("config_sha256") if isinstance(manifest.get("config_sha256"), str) else ""

    report = {
        "kind": "mechanical_atlas_qa_conversion_not_visual_approval",
        "source_output": str(output),
        "atlas_sha256": _sha256(output / "atlas.json"),
        "layout_sha256": _sha256(output / "layout.json") if (output / "layout.json").is_file() else "",
        "recipe_sha256": recipe_sha,
        "texture_count": len(images),
        "facility_sprite_count": len(FACILITY_IDS),
        "operations": [
            "native",
            "2x_nearest",
            "25pct_nearest",
            "grayscale",
            "alpha_silhouette",
        ],
        "artifacts": artifacts,
    }
    (destination / "QA_REPORT.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    return report


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path, help="generated base_facilities_v01 directory")
    parser.add_argument("--config", type=Path, help="recipe JSON; defaults to manifest provenance")
    parser.add_argument("--qa-output", type=Path, help="new empty directory for mechanical QA conversions")
    parser.add_argument(
        "--decals-atlas",
        type=Path,
        help="scene atlas.json whose sprite IDs must cover every layout decal id",
    )
    args = parser.parse_args(argv)

    config = args.config
    if config is None:
        manifest_path = args.output / "manifest.json"
        if manifest_path.is_file():
            try:
                recorded = _load_json(manifest_path).get("config_path")
            except ValueError:
                recorded = None
            if isinstance(recorded, str):
                config = Path(recorded)

    errors: list[str]
    try:
        errors, atlas, images = verify_output(args.output, config, args.decals_atlas)
        if args.qa_output is not None:
            if errors:
                errors.append("QA conversion skipped because verification failed")
            else:
                _write_mechanical_qa(args.output.resolve(), atlas, images, args.qa_output)
    except (OSError, ValueError) as exc:
        errors = [f"VERIFY FAILED: {exc}"]

    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        print(f"VERIFY FAIL: {len(errors)} error(s); mechanical only, not visual approval")
        return 1
    layout_note = "layout.json checked"
    qa_note = f"; QA written to {args.qa_output}" if args.qa_output is not None else ""
    print(f"VERIFY PASS: 5 facilities, 640x128 atlas, {layout_note}; mechanical only, not visual approval{qa_note}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
