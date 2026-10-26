#!/usr/bin/env python3
"""Package the six reviewed equipment-readability icons into one overrides atlas.

Packaging only: crop the declared rectangle, apply the declared colour key,
normalise alpha, nearest-neighbour downscale into the published visible bound,
map onto the declared palette and place the six cells in one fixed order. The
tool never draws, completes, repairs, re-authors or substitutes bitmap art,
never upscales a source, never fills a cell with fallback pixels, and never
writes to a source image.

The per-sprite preparation and the per-cell gate are the reviewed early-loop
implementations (``prepare_sprite`` and ``verify_rgba_cell``) reached through
the sibling hub bridge at an explicit file path, so no bare ``contract`` /
``build`` / ``verify`` module name can be shadowed and no second
implementation of the painting can drift from the reviewed one.

Usage:
    python3 build.py --recipe RECIPE.json --output NEW_DIR [--review NEW_DIR]

Both directories must be new paths that do not exist yet: an existing pack is
never overwritten, and only the leaf directory is created, so the parent must
already exist. Review derivatives are mechanically derived from the exact pack
bytes and are never written into the pack.
"""

from __future__ import annotations

import argparse
import importlib.util
import os
import shutil
import sys
import tempfile
from pathlib import Path
from types import ModuleType
from typing import Any, Final

from PIL import Image, ImageOps

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))  # art_pipeline/common.py
import common  # noqa: E402

PIPELINE: Final = "p1_equipment_readability_v02"
SCHEMA_VERSION: Final = 1

TEXTURE_ID: Final = "overrides"
TEXTURE_FILE: Final = "overrides.png"
ATLAS_FILE: Final = "atlas.json"
MANIFEST_FILE: Final = "manifest.json"
COLUMNS: Final = 3
ROWS: Final = 2

SPRITE_TYPE: Final = "ui_icon"
# The one allowed order. Every canonical ID is the bare item/slot ID the runtime
# already uses for that item or slot, pinned here rather than derived by string
# surgery on the dotted ID.
SPRITES: Final = (
    ("equipment.lineage_quiver", "lineage_quiver"),
    ("equipment.farwatch_quiver", "farwatch_quiver"),
    ("equipment.turnfeather_gloves", "turnfeather_gloves"),
    ("equipment.piercer_gloves", "piercer_gloves"),
    ("equipment_slot.off_hand", "off_hand"),
    ("equipment_slot.gloves", "gloves"),
)
SPRITE_IDS: Final = tuple(sprite_id for sprite_id, _ in SPRITES)
CANONICAL_BY_ID: Final = dict(SPRITES)

# Recipe vocabulary mapped onto the reviewed routine vocabulary.
KEY_SCOPES: Final = {"all": "all", "edge": "edge_connected"}
RECIPE_KEYS: Final = frozenset({"schema_version", "sprites"})
SPRITE_KEYS: Final = frozenset(
    {"id", "source", "source_rect", "palette", "colorkey", "key_scope", "tolerance"}
)
TOLERANCE_RANGE: Final = (60.0, 100.0)

# Review derivatives, written only into an explicitly requested, separate and
# new directory. None of them is ever part of the published pack.
REVIEW_FILES: Final = {
    "native": "overrides_native.png",
    "2x": "overrides_2x.png",
    "25pct": "overrides_25pct.png",
    "gray": "overrides_gray.png",
    "silhouette": "overrides_silhouette.png",
}

BRIDGE_PATH: Final = Path(__file__).resolve().parents[1] / "p1_hub_navigation_v01" / "bridge.py"
BRIDGE_MODULE: Final = "p1_hub_navigation_v01_bridge_for_equipment_readability_v02"


def load_bridge() -> ModuleType:
    """Load the sibling bridge from its explicit file path, never by bare name."""
    if not BRIDGE_PATH.is_file():
        raise ModuleNotFoundError(f"reviewed bridge is missing: {BRIDGE_PATH}")
    spec = importlib.util.spec_from_file_location(BRIDGE_MODULE, BRIDGE_PATH)
    if spec is None or spec.loader is None:
        raise ModuleNotFoundError(f"reviewed bridge cannot be loaded: {BRIDGE_PATH}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[BRIDGE_MODULE] = module
    try:
        spec.loader.exec_module(module)
    except BaseException:
        if sys.modules.get(BRIDGE_MODULE) is module:
            del sys.modules[BRIDGE_MODULE]
        raise
    return module


BRIDGE = load_bridge()
ContractError = BRIDGE.contract_error_type()
prepare_sprite = BRIDGE.prepare_sprite()
verify_rgba_cell = BRIDGE.verify_rgba_cell()
# Reviewed elementary helpers from the same modules: the exact colour / rectangle
# parsing every P1 recipe already uses.
_REVIEWED = BRIDGE._modules()["build"]
_REVIEWED_CONTRACT = BRIDGE._modules()["contract"]
sha256_file = common.sha256_file
write_json = common.write_json
parse_color = _REVIEWED.parse_color
require_rect = _REVIEWED.require_rect

# Geometry comes from the reviewed gate itself instead of being restated, so a
# prepared cell can never disagree with the gate that checks it.
CELL_SIZE: Final = _REVIEWED_CONTRACT.CELL_SIZE
CELL_PADDING: Final = _REVIEWED_CONTRACT.PADDING
MAX_VISIBLE: Final = _REVIEWED_CONTRACT.MAX_VISIBLE
MAX_COLORS: Final = _REVIEWED_CONTRACT.MAX_COLORS
ANCHOR: Final = tuple(_REVIEWED_CONTRACT.ANCHOR)
TEXTURE_SIZE: Final = (COLUMNS * CELL_SIZE, ROWS * CELL_SIZE)

TECHNICAL_CONTRACT: Final = {
    "cell": [CELL_SIZE, CELL_SIZE],
    "canvas": list(TEXTURE_SIZE),
    "columns": COLUMNS,
    "rows": ROWS,
    "padding": CELL_PADDING,
    "max_visible": [MAX_VISIBLE, MAX_VISIBLE],
    "anchor": list(ANCHOR),
    "max_colors": MAX_COLORS,
    "alpha": "binary",
    "transparent_rgb": [0, 0, 0],
    "downscale": "nearest",
}


def load_json(path: Path, label: str) -> dict[str, Any]:
    return common.load_json(path, label, ContractError)


def hex_color(color: tuple[int, int, int]) -> str:
    return "#%02x%02x%02x" % color


def parse_palette(value: Any, label: str) -> tuple[tuple[int, int, int], ...]:
    palette = _REVIEWED._validated_palette(value, label)
    if palette is None:
        raise ContractError(f"{label} must be an explicit list of 1..{MAX_COLORS} colours")
    return palette


def resolve_source(recipe_path: Path, value: Any, label: str) -> Path:
    if not isinstance(value, str) or not value:
        raise ContractError(f"{label} must be a non-empty path")
    candidate = Path(value)
    return (candidate if candidate.is_absolute() else recipe_path.parent / candidate).resolve()


def validate_recipe(recipe: dict[str, Any], recipe_path: Path) -> list[dict[str, Any]]:
    """Validate the reviewed recipe shape and return its normalised sprites."""
    if recipe.get("schema_version") != SCHEMA_VERSION:
        raise ContractError(f"recipe schema_version must be {SCHEMA_VERSION}")
    extra = set(recipe) - RECIPE_KEYS
    if extra:
        raise ContractError(f"recipe has unsupported keys: {sorted(extra)}")
    missing = RECIPE_KEYS - set(recipe)
    if missing:
        raise ContractError(f"recipe is missing keys: {sorted(missing)}")

    raw_sprites = recipe["sprites"]
    if not isinstance(raw_sprites, list):
        raise ContractError("recipe sprites must be an array")
    if len(raw_sprites) != len(SPRITE_IDS):
        raise ContractError(
            f"recipe must declare exactly {len(SPRITE_IDS)} sprites, got {len(raw_sprites)}"
        )

    sizes: dict[Path, tuple[int, int]] = {}
    digests: dict[Path, str] = {}
    rects_by_source: dict[Path, list[tuple[str, tuple[int, int, int, int]]]] = {}
    sprites: list[dict[str, Any]] = []
    for index, (raw, expected_id) in enumerate(zip(raw_sprites, SPRITE_IDS, strict=True)):
        if not isinstance(raw, dict):
            raise ContractError(f"recipe sprites[{index}] must be an object")
        extra_sprite = set(raw) - SPRITE_KEYS
        if extra_sprite:
            raise ContractError(f"recipe sprite {expected_id} has unsupported keys: {sorted(extra_sprite)}")
        missing_sprite = SPRITE_KEYS - set(raw)
        if missing_sprite:
            raise ContractError(f"recipe sprite {expected_id} is missing keys: {sorted(missing_sprite)}")
        sprite_id = raw["id"]
        if not isinstance(sprite_id, str) or not sprite_id:
            raise ContractError(f"recipe sprites[{index}].id must be a non-empty string")
        if sprite_id != expected_id:
            raise ContractError(f"recipe sprite {index} must be {expected_id}, got {sprite_id}")

        source = resolve_source(recipe_path, raw["source"], f"recipe sprite {sprite_id}.source")
        if not source.is_file():
            raise ContractError(f"source PNG does not exist: {source}")
        if source not in sizes:
            try:
                with Image.open(source) as image:
                    image.load()
                    sizes[source] = (image.width, image.height)
            except (OSError, ValueError) as exc:
                raise ContractError(f"cannot open source PNG {source}: {exc}") from exc
            digests[source] = sha256_file(source)
        source_size = sizes[source]

        rect = require_rect(raw["source_rect"], f"recipe sprite {sprite_id}.source_rect")
        x, y, width, height = rect
        if x + width > source_size[0] or y + height > source_size[1]:
            raise ContractError(
                f"recipe sprite {sprite_id} source_rect is outside the "
                f"{source_size[0]}x{source_size[1]} source"
            )
        for other_id, other in rects_by_source.get(source, []):
            overlaps = (
                x < other[0] + other[2]
                and other[0] < x + width
                and y < other[1] + other[3]
                and other[1] < y + height
            )
            if overlaps:
                raise ContractError(f"source_rect collision in {source.name}: {sprite_id} overlaps {other_id}")
        rects_by_source.setdefault(source, []).append((sprite_id, rect))

        palette = parse_palette(raw["palette"], f"recipe sprite {sprite_id}.palette")
        key_value = raw["colorkey"]
        scope = raw["key_scope"]
        tolerance_value = raw["tolerance"]
        if key_value is None:
            # A keyless crop must carry real transparency: the reviewed routine
            # refuses a fully opaque or alpha-less crop instead of guessing a
            # checkerboard or a background colour.
            if scope is not None or tolerance_value is not None:
                raise ContractError(
                    f"recipe sprite {sprite_id} declares key_scope or tolerance without an explicit colorkey"
                )
            colorkey, key_scope, tolerance = None, None, 0.0
        else:
            colorkey = parse_color(key_value, f"recipe sprite {sprite_id}.colorkey")
            if not isinstance(scope, str) or scope not in KEY_SCOPES:
                raise ContractError(f"recipe sprite {sprite_id}.key_scope must be 'all' or 'edge'")
            if (
                isinstance(tolerance_value, bool)
                or not isinstance(tolerance_value, (int, float))
                or not TOLERANCE_RANGE[0] <= float(tolerance_value) <= TOLERANCE_RANGE[1]
            ):
                raise ContractError(
                    f"recipe sprite {sprite_id}.tolerance must be a number in "
                    f"[{TOLERANCE_RANGE[0]:.0f},{TOLERANCE_RANGE[1]:.0f}]"
                )
            key_scope, tolerance = scope, float(tolerance_value)

        sprites.append(
            {
                "id": sprite_id,
                "canonical_id": CANONICAL_BY_ID[sprite_id],
                "source": source,
                "source_size": source_size,
                "source_sha256": digests[source],
                "source_rect": rect,
                "palette": palette,
                "colorkey": colorkey,
                "key_scope": key_scope,
                "tolerance": tolerance,
            }
        )
    return sprites


def prepare_cell(source_image: Image.Image, sprite: dict[str, Any]) -> Image.Image:
    """Hand one sprite to the reviewed preparation routine, unchanged."""
    # key_scope and tolerance are read by the reviewed routine only when a
    # colour key is present; both stay None for a source with real transparency.
    scope = KEY_SCOPES[sprite["key_scope"]] if sprite["key_scope"] is not None else None
    return prepare_sprite(
        source_image,
        {
            "entry": {"id": sprite["id"]},
            "source_rect": list(sprite["source_rect"]),
            "visible_bbox": None,
            "colorkey": sprite["colorkey"],
            "key_scope": scope,
            "tolerance": sprite["tolerance"],
            "palette": sprite["palette"],
            "colors": MAX_COLORS,
        },
    )


def gate_cell(cell: Image.Image, sprite_id: str) -> None:
    """Run the reviewed cell gate and fail with its exact wording."""
    errors: list[str] = []
    verify_rgba_cell(cell, sprite_id, errors)
    if errors:
        raise ContractError("; ".join(errors))


def visible_colors(cell: Image.Image) -> set[tuple[int, int, int]]:
    return {
        (red, green, blue)
        for red, green, blue, alpha in cell.convert("RGBA").get_flattened_data()
        if alpha == 255
    }


def validate_new_target(target: Path, role: str, protected: tuple[Path, ...]) -> Path:
    """Refuse anything but a new leaf directory beside an existing parent."""
    target = target.resolve()
    if target.is_symlink() or os.path.lexists(target):
        raise ContractError(f"{role} directory must be a new path that does not exist: {target}")
    if not target.parent.is_dir():
        raise ContractError(f"{role} directory parent must already exist: {target.parent}")
    for guarded in protected:
        if guarded == target or guarded in target.parents or target in guarded.parents:
            raise ContractError(f"{role} directory overlaps a protected path: {guarded}")
    return target


def artifact_record(directory: Path, name: str, image: Image.Image | None = None) -> dict[str, Any]:
    path = directory / name
    record: dict[str, Any] = {"file": name, "sha256": sha256_file(path), "bytes": path.stat().st_size}
    if image is not None:
        record["dimensions"] = [image.width, image.height]
    return record


def review_images(atlas: Image.Image) -> dict[str, Image.Image]:
    """The derived review set; greyscale and silhouette touch RGB only."""
    width, height = atlas.size
    alpha = atlas.getchannel("A")
    gray = ImageOps.grayscale(atlas.convert("RGB"))
    white = Image.new("L", atlas.size, 255)
    return {
        REVIEW_FILES["native"]: atlas.copy(),
        REVIEW_FILES["2x"]: atlas.resize((width * 2, height * 2), Image.Resampling.NEAREST),
        REVIEW_FILES["25pct"]: atlas.resize((max(1, width // 4), max(1, height // 4)), Image.Resampling.NEAREST),
        REVIEW_FILES["gray"]: Image.merge("RGBA", (gray, gray, gray, alpha)),
        REVIEW_FILES["silhouette"]: Image.merge("RGBA", (white, white, white, alpha)),
    }


def build(recipe_path: Path, output: Path, review_directory: Path | None = None) -> dict[str, Path]:
    recipe_path = recipe_path.resolve()
    recipe = load_json(recipe_path, "recipe")
    sprites = validate_recipe(recipe, recipe_path)

    protected = (recipe_path, *sorted({sprite["source"] for sprite in sprites}))
    output = validate_new_target(output, "output", protected)
    review_directory = (
        validate_new_target(review_directory, "review", (*protected, output))
        if review_directory is not None
        else None
    )

    sources: dict[Path, Image.Image] = {}
    stages: list[Path] = []
    review_stage: Path | None = None
    try:
        atlas = Image.new("RGBA", TEXTURE_SIZE, (0, 0, 0, 0))
        records: list[dict[str, Any]] = []
        trace: list[dict[str, Any]] = []
        for index, sprite in enumerate(sprites):
            if sprite["source"] not in sources:
                with Image.open(sprite["source"]) as opened:
                    opened.load()
                    sources[sprite["source"]] = opened.copy()
            cell = prepare_cell(sources[sprite["source"]], sprite)
            if cell.size != (CELL_SIZE, CELL_SIZE):
                raise ContractError(
                    f"sprite {sprite['id']} prepared to {cell.size[0]}x{cell.size[1]} instead of "
                    f"{CELL_SIZE}x{CELL_SIZE}"
                )
            column, row = index % COLUMNS, index // COLUMNS
            rect = [column * CELL_SIZE, row * CELL_SIZE, CELL_SIZE, CELL_SIZE]
            atlas.alpha_composite(cell, (rect[0], rect[1]))
            # An atlas crop box is (left, upper, right, lower) while the published
            # rect is [x, y, w, h], so the far corner has to be added, not reused.
            placed = atlas.crop((rect[0], rect[1], rect[0] + rect[2], rect[1] + rect[3]))
            # Gate the pixels that were actually placed, so the reported rect,
            # the four-edge padding and the binary alpha are checked together.
            gate_cell(placed, sprite["id"])
            records.append(
                {
                    "id": sprite["id"],
                    "canonical_id": sprite["canonical_id"],
                    "type": SPRITE_TYPE,
                    "texture": TEXTURE_FILE,
                    "rect": rect,
                    "anchor": list(ANCHOR),
                }
            )
            trace.append(
                {
                    "id": sprite["id"],
                    "canonical_id": sprite["canonical_id"],
                    "source": str(sprite["source"]),
                    "source_sha256": sprite["source_sha256"],
                    "source_dimensions": list(sprite["source_size"]),
                    "source_rect": list(sprite["source_rect"]),
                    "colorkey": None if sprite["colorkey"] is None else hex_color(sprite["colorkey"]),
                    "key_scope": sprite["key_scope"],
                    "tolerance": None if sprite["colorkey"] is None else sprite["tolerance"],
                    "palette": [hex_color(color) for color in sprite["palette"]],
                    "rect": rect,
                    "anchor": list(ANCHOR),
                    "visible_bbox": list(placed.getchannel("A").getbbox()),
                    "visible_colors": len(visible_colors(placed)),
                }
            )

        pack_stage = Path(tempfile.mkdtemp(prefix=f".{PIPELINE}-pack-", dir=output.parent))
        stages.append(pack_stage)
        atlas.save(pack_stage / TEXTURE_FILE, format="PNG")
        write_json(
            pack_stage / ATLAS_FILE,
            {
                "schema_version": SCHEMA_VERSION,
                "textures": [{"id": TEXTURE_ID, "file": TEXTURE_FILE}],
                "sprites": records,
            },
        )

        review_record = None
        if review_directory is not None:
            review_stage = Path(tempfile.mkdtemp(prefix=f".{PIPELINE}-review-", dir=review_directory.parent))
            stages.append(review_stage)
            images = review_images(atlas)
            derivatives = []
            for label, name in REVIEW_FILES.items():
                image = images[name]
                image.save(review_stage / name, format="PNG")
                derivatives.append({"label": label, **artifact_record(review_stage, name, image)})
            review_record = {"directory": str(review_directory), "derivatives": derivatives}

        manifest: dict[str, Any] = {
            "schema_version": SCHEMA_VERSION,
            "pipeline": PIPELINE,
            "inputs": {
                "recipe": {"path": str(recipe_path), "sha256": sha256_file(recipe_path)},
                "sources": [
                    {
                        "id": sprite["id"],
                        "path": str(sprite["source"]),
                        "sha256": sprite["source_sha256"],
                        "dimensions": list(sprite["source_size"]),
                    }
                    for sprite in sprites
                ],
            },
            "outputs": {
                "atlas": ATLAS_FILE,
                "atlas_sha256": sha256_file(pack_stage / ATLAS_FILE),
                "texture": {"id": TEXTURE_ID, "file": TEXTURE_FILE, "dimensions": list(TEXTURE_SIZE)},
                "sprite_ids": list(SPRITE_IDS),
                "artifacts": [
                    artifact_record(pack_stage, TEXTURE_FILE, atlas),
                    artifact_record(pack_stage, ATLAS_FILE),
                ],
            },
            "sprites": trace,
            "technical_contract": TECHNICAL_CONTRACT,
        }
        if review_record is not None:
            manifest["review"] = review_record
        write_json(pack_stage / MANIFEST_FILE, manifest)

        # The review directory appears first: a pack whose manifest names review
        # files is only ever published once those bytes exist.
        if review_stage is not None:
            os.replace(review_stage, review_directory)
            stages.remove(review_stage)
        os.replace(pack_stage, output)
        stages.remove(pack_stage)
    finally:
        for stage in stages:
            shutil.rmtree(stage, ignore_errors=True)
        for image in sources.values():
            image.close()
    return {"output": output, "manifest": output / MANIFEST_FILE}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Package the P1 equipment-readability overrides atlas.")
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
    print(f"PASS: packaged {TEXTURE_FILE} {TEXTURE_SIZE[0]}x{TEXTURE_SIZE[1]} with {len(SPRITE_IDS)} sprites")
    if args.review is not None:
        print(f"PASS: review derivatives in {args.review.resolve()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
