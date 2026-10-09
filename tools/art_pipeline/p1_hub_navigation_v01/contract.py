"""Frozen contract for the P1 hub-navigation icon batch.

This module holds the numbers, the five facility IDs and the fixed pack names.
It performs no image work and imports nothing from the sibling pipelines, so it
can be imported by ``build``, ``verify``, ``review`` and the tests without any
module-name collision.

The published pack is a standalone 160x32 icon sheet: five 32x32 cells left
to right, one ``ui_icon`` per cell on a (16,16) anchor, plus ``atlas.json``
schema_version 1. The former runtime navigation component was retired; this
contract remains for production verification and future reuse. Only the
packaging is frozen here; the artwork itself is owned by the main thread.
"""

from __future__ import annotations

from typing import Final

SCHEMA_VERSION: Final = 1
SOURCE_KEY: Final = "icons"

CELL_SIZE: Final = 32
ANCHOR: Final = [16, 16]
# Safety inset around every cell; the reused sprite preparation already clamps
# the visible content to CELL_SIZE - 2 * PADDING on each axis.
PADDING: Final = 2
MAX_VISIBLE: Final = 28
# The batch palette cap: the published sheet may never show more than seven
# distinct opaque RGB values across all five cells.
MAX_COLORS: Final = 7
SPRITE_TYPE: Final = "ui_icon"

TEXTURE_ID: Final = "icons"
TEXTURE_FILE: Final = "icons.png"
TEXTURE_WIDTH: Final = CELL_SIZE * 5
TEXTURE_HEIGHT: Final = CELL_SIZE
RESOURCE_PREFIX: Final = "res://art/production/p1/hub_navigation_v01"
TEXTURE_PATH: Final = f"{RESOURCE_PREFIX}/{TEXTURE_FILE}"

# The five hub cards, in the one authoritative order shared with the runtime
# reader. The published sprite IDs are exactly the reviewed recipe's IDs; the
# recipe is the source of truth for identity, so this contract never renames one.
FACILITY_IDS: Final = ("contract", "loadout", "forge", "training", "proxy")
SPRITE_IDS: Final = FACILITY_IDS

# The reviewed generation is one 1536x1024 sheet holding a 3x2 grid of 512
# source tiles, read left to right, top to bottom.
SOURCE_GRID: Final = (3, 2)
SOURCE_CELL: Final = 512
SOURCE_LAYOUT: Final = (SOURCE_GRID[0] * SOURCE_CELL, SOURCE_GRID[1] * SOURCE_CELL)

# Reserved background keys, matching the reviewed generation prompts. Magenta
# is keyed at the reviewed ceiling tolerance and removed everywhere in the crop.
COLOR_KEY: Final = "#FF00FF"
COLOR_KEY_SCOPE: Final = "all"
COLOR_KEY_TOLERANCE: Final = 100

ATLAS_FILE: Final = "atlas.json"
MANIFEST_FILE: Final = "manifest.json"

# Review derivatives, written only into an explicitly requested, separate and
# new directory. None of them is ever part of the published pack.
REVIEW_NATIVE: Final = "icons_native.png"
REVIEW_2X: Final = "icons_2x.png"
REVIEW_25PCT: Final = "icons_25pct.png"
REVIEW_GRAY: Final = "icons_gray.png"
REVIEW_SILHOUETTE: Final = "icons_silhouette.png"
REVIEW_ORDER: Final = (
    REVIEW_NATIVE,
    REVIEW_2X,
    REVIEW_25PCT,
    REVIEW_GRAY,
    REVIEW_SILHOUETTE,
)
