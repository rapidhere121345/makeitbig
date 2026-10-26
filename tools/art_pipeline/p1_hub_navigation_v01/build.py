#!/usr/bin/env python3
"""Package the five reviewed hub-navigation icons into one deterministic atlas.

This tool performs packaging only. It crops the reviewed source sheet exactly as
the recipe declares, applies the declared colour key, normalises alpha,
nearest-neighbour downscales each icon into the published visible bound, maps the
result onto the declared seven-colour palette, and places the five cells at
fixed positions. It never draws, completes, repairs, re-authors or substitutes
bitmap art, it never fills a cell with fallback art, and it never writes to a
source image.

The per-sprite preparation and the per-cell gate are the reviewed early-loop
implementations, reached through :mod:`bridge`, so the published pixels follow
the already-accepted pipeline behaviour instead of a parallel reimplementation.

Usage:
    python3 build.py --recipe RECIPE.json --output NEW_DIRECTORY [--review NEW_DIRECTORY]

``--output`` must not exist or must be an empty directory: an existing pack is
never overwritten. ``--review`` is optional and, when given, must be a second
separate new directory; the review derivatives are never written into the pack.
"""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path
from typing import Any

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))  # art_pipeline/common.py
import common  # noqa: E402
if __name__ == "__main__":  # -P / PYTHONSAFEPATH leaves the script directory off sys.path
    sys.path.insert(0, str(Path(__file__).resolve().parent))
import contract
import review
from bridge import contract_error_type, prepare_sprite

ContractError = contract_error_type()

RECIPE_KEYS = frozenset(
    {"schema_version", "source", "palette", "colorkey", "key_scope", "tolerance", "sprites"}
)
SPRITE_KEYS = frozenset({"id", "source_rect"})
MANIFEST_SCHEMA_VERSION = 1
TECHNICAL_CONTRACT = {
    "cell": [contract.CELL_SIZE, contract.CELL_SIZE],
    "padding": contract.PADDING,
    "max_visible": [contract.MAX_VISIBLE, contract.MAX_VISIBLE],
    "anchor": list(contract.ANCHOR),
    "max_colors": contract.MAX_COLORS,
    "alpha": "binary",
    "transparent_rgb": [0, 0, 0],
}


sha256_file = common.sha256_file
write_json = common.write_json


def load_json(path: Path, label: str) -> dict[str, Any]:
    return common.load_json(path, label, ContractError)


def write_png(image: Image.Image, path: Path) -> None:
    image.save(path, format="PNG")


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
        raise ContractError(f"{label} needs a non-negative origin and a positive size")
    return x, y, width, height


def parse_palette(value: Any, label: str) -> tuple[tuple[int, int, int], ...]:
    if not isinstance(value, list) or not 1 <= len(value) <= contract.MAX_COLORS:
        raise ContractError(f"{label} must contain 1..{contract.MAX_COLORS} colours")
    colors = tuple(parse_color(item, f"{label}[{index}]") for index, item in enumerate(value))
    if len(set(colors)) != len(colors):
        raise ContractError(f"{label} contains duplicate colours")
    return colors


def resolve_source(recipe_path: Path, value: Any) -> Path:
    if not isinstance(value, str) or not value:
        raise ContractError("recipe source must be a non-empty path")
    candidate = Path(value)
    return (candidate if candidate.is_absolute() else recipe_path.parent / candidate).resolve()


def validate_recipe(recipe: dict[str, Any], recipe_path: Path) -> dict[str, Any]:
    """Validate the reviewed recipe shape and return its normalised form."""
    if recipe.get("schema_version") != contract.SCHEMA_VERSION:
        raise ContractError(f"recipe schema_version must be {contract.SCHEMA_VERSION}")
    extra = set(recipe) - RECIPE_KEYS
    if extra:
        raise ContractError(f"recipe has unsupported keys: {sorted(extra)}")
    missing = RECIPE_KEYS - set(recipe)
    if missing:
        raise ContractError(f"recipe is missing keys: {sorted(missing)}")

    if recipe.get("key_scope") != contract.COLOR_KEY_SCOPE:
        raise ContractError(f"recipe key_scope must be {contract.COLOR_KEY_SCOPE}")
    colorkey = parse_color(recipe["colorkey"], "recipe colorkey")
    expected_key = parse_color(contract.COLOR_KEY, "contract colorkey")
    if colorkey != expected_key:
        raise ContractError(f"recipe colorkey must be {contract.COLOR_KEY}")
    tolerance = recipe["tolerance"]
    if isinstance(tolerance, bool) or not isinstance(tolerance, (int, float)):
        raise ContractError("recipe tolerance must be a number")
    if float(tolerance) != float(contract.COLOR_KEY_TOLERANCE):
        raise ContractError(f"recipe tolerance must be {contract.COLOR_KEY_TOLERANCE}")
    palette = parse_palette(recipe["palette"], "recipe palette")

    source = resolve_source(recipe_path, recipe.get("source"))
    if not source.is_file():
        raise ContractError(f"source PNG does not exist: {source}")
    try:
        with Image.open(source) as image:
            image.load()
            source_size = (image.width, image.height)
    except (OSError, ValueError) as exc:
        raise ContractError(f"cannot open source PNG {source}: {exc}") from exc

    raw_sprites = recipe.get("sprites")
    if not isinstance(raw_sprites, list):
        raise ContractError("recipe sprites must be an array")
    if len(raw_sprites) != len(contract.SPRITE_IDS):
        raise ContractError(
            f"recipe must declare exactly {len(contract.SPRITE_IDS)} sprites, got {len(raw_sprites)}"
        )

    rects: list[tuple[int, int, int, int]] = []
    sprites: list[dict[str, Any]] = []
    for index, (raw_sprite, expected_id) in enumerate(zip(raw_sprites, contract.SPRITE_IDS, strict=True)):
        if not isinstance(raw_sprite, dict):
            raise ContractError(f"recipe sprites[{index}] must be an object")
        extra_sprite = set(raw_sprite) - SPRITE_KEYS
        if extra_sprite:
            raise ContractError(f"recipe sprite {expected_id} has unsupported keys: {sorted(extra_sprite)}")
        sprite_id = raw_sprite.get("id")
        if not isinstance(sprite_id, str) or not sprite_id:
            raise ContractError(f"recipe sprites[{index}].id must be a non-empty string")
        if sprite_id != expected_id:
            raise ContractError(f"recipe sprite {index} must be {expected_id}, got {sprite_id}")
        rect = require_rect(raw_sprite.get("source_rect"), f"recipe sprite {sprite_id}.source_rect")
        x, y, width, height = rect
        if x + width > source_size[0] or y + height > source_size[1]:
            raise ContractError(
                f"recipe sprite {sprite_id} source_rect is outside the {source_size[0]}x{source_size[1]} source"
            )
        for other_index, (ox, oy, ow, oh) in enumerate(rects):
            overlaps = x < ox + ow and ox < x + width and y < oy + oh and oy < y + height
            if overlaps:
                raise ContractError(
                    f"source_rect collision: {sprite_id} overlaps {contract.SPRITE_IDS[other_index]}"
                )
        rects.append(rect)
        sprites.append({"id": sprite_id, "source_rect": rect})

    return {
        "source": source,
        "source_size": source_size,
        "palette": palette,
        "colorkey": colorkey,
        "tolerance": float(tolerance),
        "key_scope": contract.COLOR_KEY_SCOPE,
        "sprites": sprites,
    }


def prepare_sprite_spec(sprite: dict[str, Any], normalized: dict[str, Any]) -> dict[str, Any]:
    """Translate a validated recipe sprite into the reviewed routine's spec.

    The reviewed routine consumes exactly the field names and the [x,y,w,h]
    rectangle semantics the reviewed recipe already uses, so this translation
    only renames nothing and merely fills the two knobs the hub recipe fixes:
    the declared visible bound and the colour cap.
    """
    return {
        "entry": {"id": sprite["id"]},
        "source_rect": [int(value) for value in sprite["source_rect"]],
        "visible_bbox": None,
        "colorkey": normalized["colorkey"],
        "key_scope": normalized["key_scope"],
        "tolerance": normalized["tolerance"],
        "palette": normalized["palette"],
        "colors": contract.MAX_COLORS,
    }


def visible_colors(cell: Image.Image) -> set[tuple[int, int, int]]:
    rgba = cell.convert("RGBA")
    return {
        (red, green, blue)
        for red, green, blue, alpha in rgba.get_flattened_data()
        if alpha == 255
    }


def alpha_mask(cell: Image.Image) -> bytes:
    rgba = cell.convert("RGBA")
    return bytes(1 if alpha == 255 else 0 for _, _, _, alpha in rgba.get_flattened_data())


def protected_overlaps(target: Path, protected_file: Path) -> bool:
    """True when a new directory would sit on top of a reviewed file.

    Only the reviewed files themselves are protected. Sitting beside them is
    expected: a reviewed batch keeps its recipe, its sources and its review
    folder in one batch directory, so a new pack or review folder inside that
    batch is allowed. What is refused is targeting a path a reviewed file
    already occupies -- as the target itself or as a directory inside it,
    which a file cannot host -- because that is the one case that would put a
    pack on top of bytes that must stay exactly as reviewed.
    """
    target = target.resolve()
    protected_file = protected_file.resolve()
    if target == protected_file:
        return True
    return protected_file in target.parents


def validate_output_target(output: Path, protected: tuple[Path, ...] = ()) -> None:
    output = output.resolve()
    if output.is_symlink():
        raise ContractError(f"output directory may not be a symlink: {output}")
    if output.exists():
        if not output.is_dir():
            raise ContractError(f"output path exists and is not a directory: {output}")
        entries = sorted(path.name for path in output.iterdir())
        if entries:
            raise ContractError(
                f"refusing to overwrite: output directory already contains {entries[0]}"
            )
    for reviewed in protected:
        if protected_overlaps(output, reviewed):
            raise ContractError(f"output directory would overwrite a reviewed file: {reviewed}")


def build(recipe_path: Path, output: Path, review_directory: Path | None = None) -> dict[str, Path]:
    recipe_path = recipe_path.resolve()
    output = output.resolve()
    review_directory = review_directory.resolve() if review_directory is not None else None
    recipe = load_json(recipe_path, "recipe")
    normalized = validate_recipe(recipe, recipe_path)

    # Reviewed files are protected by identity, never by their directory: the
    # repository keeps a batch's recipe, its sources and its review folder in one
    # batch directory, so a pack or a review folder inside that batch is normal.
    # The pack and its review folder must stay separate from each other, though,
    # and neither may be aimed at a path a reviewed file already occupies.
    reviewed_files = (recipe_path, normalized["source"])
    validate_output_target(output, reviewed_files)
    if review_directory is not None:
        validate_output_target(review_directory, (*reviewed_files, output))
        validate_output_target(output, (*reviewed_files, review_directory))

    atlases: dict[str, Image.Image] = {}
    try:
        source_image = review.load_source(normalized["source"])
        atlas = Image.new("RGBA", (contract.TEXTURE_WIDTH, contract.TEXTURE_HEIGHT), (0, 0, 0, 0))
        sprite_records: list[dict[str, Any]] = []
        cells: list[Image.Image] = []
        for index, sprite in enumerate(normalized["sprites"]):
            spec = prepare_sprite_spec(sprite, normalized)
            cell = prepare_sprite()(source_image, spec)
            if cell.size != (contract.CELL_SIZE, contract.CELL_SIZE):
                raise ContractError(
                    f"sprite {sprite['id']} prepared to {cell.size[0]}x{cell.size[1]} instead of "
                    f"{contract.CELL_SIZE}x{contract.CELL_SIZE}"
                )
            colors = visible_colors(cell)
            if len(colors) > contract.MAX_COLORS:
                raise ContractError(
                    f"sprite {sprite['id']} shows {len(colors)} colours, over the {contract.MAX_COLORS}-colour cap"
                )
            cells.append(cell)
            atlas.alpha_composite(cell, (index * contract.CELL_SIZE, 0))
            sprite_records.append(
                {
                    "id": sprite["id"],
                    "type": contract.SPRITE_TYPE,
                    "texture": contract.TEXTURE_ID,
                    "rect": [index * contract.CELL_SIZE, 0, contract.CELL_SIZE, contract.CELL_SIZE],
                    "anchor": list(contract.ANCHOR),
                }
            )
        masks: dict[bytes, str] = {}
        for cell, sprite in zip(cells, normalized["sprites"], strict=True):
            mask = alpha_mask(cell)
            if mask in masks:
                raise ContractError(
                    f"sprites {masks[mask]} and {sprite['id']} share one alpha mask; cells must stay distinct"
                )
            masks[mask] = sprite["id"]
        atlases["icons"] = atlas

        try:
            output.mkdir(parents=True, exist_ok=False)
        except FileExistsError as exc:
            raise ContractError(f"refusing to overwrite: output directory appeared: {output}") from exc
        write_png(atlas, output / contract.TEXTURE_FILE)
        atlas_document = {
            "schema_version": contract.SCHEMA_VERSION,
            "sprites": sprite_records,
            "textures": {
                contract.TEXTURE_ID: {
                    "path": contract.TEXTURE_PATH,
                    "width": contract.TEXTURE_WIDTH,
                    "height": contract.TEXTURE_HEIGHT,
                }
            },
        }
        write_json(output / contract.ATLAS_FILE, atlas_document)

        artifacts = [
            artifact_record(output, contract.TEXTURE_FILE, atlas),
            artifact_record(output, contract.ATLAS_FILE),
        ]
        manifest: dict[str, Any] = {
            "schema_version": MANIFEST_SCHEMA_VERSION,
            "pipeline": "p1_hub_navigation_v01",
            "inputs": {
                "recipe": {
                    **artifact_record(recipe_path.parent, recipe_path.name),
                    "directory": str(recipe_path.parent),
                },
                "source": {
                    **artifact_record(normalized["source"].parent, normalized["source"].name),
                    "path": str(normalized["source"]),
                    "dimensions": list(normalized["source_size"]),
                },
            },
            "outputs": {
                "artifacts": artifacts,
                "atlas": contract.ATLAS_FILE,
                "atlas_sha256": sha256_file(output / contract.ATLAS_FILE),
                "sprite_ids": list(contract.SPRITE_IDS),
                "texture": {
                    "id": contract.TEXTURE_ID,
                    "path": contract.TEXTURE_PATH,
                    "dimensions": [contract.TEXTURE_WIDTH, contract.TEXTURE_HEIGHT],
                },
            },
            "technical_contract": TECHNICAL_CONTRACT,
        }
        if review_directory is not None:
            manifest["review"] = review.write_review(
                atlas,
                review_directory,
                write_png=write_png,
                sha256_file=sha256_file,
            )
        write_json(output / contract.MANIFEST_FILE, manifest)
    finally:
        for image in atlases.values():
            image.close()
    return {"output": output / contract.MANIFEST_FILE}


def relative_reference(base: Path, target: Path) -> str:
    return os.path.relpath(target, start=base).replace(os.sep, "/")


def artifact_record(directory: Path, name: str, image: Image.Image | None = None) -> dict[str, Any]:
    path = directory / name
    record: dict[str, Any] = {
        "file": name,
        "sha256": sha256_file(path),
        "bytes": path.stat().st_size,
    }
    if image is not None:
        record["dimensions"] = [image.width, image.height]
    elif path.suffix == ".png":
        with Image.open(path) as opened:
            record["dimensions"] = [opened.width, opened.height]
    return record


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Package the P1 hub-navigation icon atlas.")
    parser.add_argument("--recipe", required=True, type=Path, help="reviewed recipe JSON")
    parser.add_argument("--output", required=True, type=Path, help="new pack directory (never overwritten)")
    parser.add_argument(
        "--review",
        type=Path,
        default=None,
        help="optional separate new directory for review derivatives",
    )
    args = parser.parse_args(argv)
    try:
        build(args.recipe, args.output, args.review)
    except ContractError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    print(f"PASS: packaged {contract.TEXTURE_FILE} ({contract.TEXTURE_WIDTH}x{contract.TEXTURE_HEIGHT})")
    if args.review is not None:
        print(f"PASS: review derivatives in {args.review.resolve()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
