#!/usr/bin/env python3
"""Deterministically generate the Act I v0.3 pixel-art production package."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Iterable

from PIL import Image, ImageDraw, ImageFont, ImageOps


ROOT = Path(__file__).resolve().parents[3]
SOURCE_ATLAS = ROOT / "art" / "early" / "actors_atlas_v0.2.png"
OUTPUT_DIR = ROOT / "art" / "early" / "v0.3"
REVIEW_DIR = ROOT / "docs" / "art-concepts" / "v0.3" / "review"
ITEMS_JSON = ROOT / "content" / "early_items.json"
CAMPAIGN_JSON = ROOT / "content" / "early_campaign.json"
MANIFEST_PATH = OUTPUT_DIR / "asset_manifest.json"

SOURCE_ATLAS_SHA256 = (
    "d113a824311b6ecd97178f3c9257a298fc0e5b2723b59542e52488d130b9ded1"
)

PALETTE_HEX = [
    "#07080B", "#12151B", "#252A31", "#59606B", "#E6E0D2",
    "#E3A447", "#9E3036", "#D95149", "#41B7AE", "#7450A6",
]


def rgba(color: str, alpha: int = 255) -> tuple[int, int, int, int]:
    value = color.lstrip("#")
    return (
        int(value[0:2], 16), int(value[2:4], 16),
        int(value[4:6], 16), alpha,
    )


INK, DEEP, STONE, NEUTRAL = PALETTE_HEX[:4]
BONE, AMBER, BLOOD, WARNING, TEAL, PURPLE = PALETTE_HEX[4:]
PALETTE_RGB = {rgba(color)[:3] for color in PALETTE_HEX}
TRANSPARENT = (0, 0, 0, 0)


def font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    path = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf"
    try:
        return ImageFont.truetype(path, size)
    except OSError:
        return ImageFont.load_default()


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(65536), b""):
            digest.update(chunk)
    return digest.hexdigest()


def new_sprite(size: tuple[int, int] = (32, 32)) -> Image.Image:
    return Image.new("RGBA", size, TRANSPARENT)


def paste(atlas: Image.Image, sprite: Image.Image, col: int, row: int) -> None:
    atlas.alpha_composite(sprite, (col * 32, row * 32))


def points(draw: ImageDraw.ImageDraw, pixels: Iterable[tuple[int, int]], color: str) -> None:
    draw.point(list(pixels), fill=rgba(color))


def frame_rect(cell: tuple[int, int] = (32, 32), inset: int = 2) -> tuple[int, int, int, int]:
    return inset, inset, cell[0] - inset - 1, cell[1] - inset - 1


# ---------------------------------------------------------------------------
# Actors


def set_pixels(atlas: Image.Image, pixels: Iterable[tuple[int, int]], color: str) -> None:
    for x, y in pixels:
        if atlas.getpixel((x, y))[3] == 255:
            atlas.putpixel((x, y), rgba(color))


def facing_index(facing: str) -> int:
    return ("north", "east", "south", "west").index(facing)


# Fixed coordinates on the validated v0.2 atlas. The pass clarifies equipment
# without replacing the mature hood/cloak and boss-gate silhouettes.
RANGER_QUIVER_TIPS = ((18, 11), (18, 12), (20, 11))
RANGER_QUIVER_SHAFTS = (
    ((18, 15),),
)
RANGER_BELTS = {
    "north": (),
    "east": ((17, 20), (18, 20), (19, 20)),
    "south": ((13, 20), (14, 20), (15, 20), (16, 20), (17, 20), (18, 20)),
    "west": ((12, 20), (13, 20), (14, 20)),
}
RANGER_BUSY_STEPS = {"north", "east"}
RANGER_SKIP_COORDS = {
    "north": ((14, 20), (15, 20), (16, 20), (17, 20)),
    "east": ((17, 20), (18, 20), (19, 20)),
    "south": ((13, 20), (14, 20), (15, 20), (16, 20), (17, 20), (18, 20)),
    "west": ((12, 20), (13, 20), (14, 20)),
}
RANGER_WRIST_PIXELS = {
    "north": (),
    "east": ((9, 18), (10, 18), (22, 17)),
    "south": ((7, 18), (8, 18), (23, 18), (24, 18)),
    "west": ((7, 18), (8, 18), (21, 17), (22, 18)),
}
RANGER_BOW_ARCS = {
    "north": (),
    "east": ((24, 14), (25, 15), (25, 16), (24, 20)),
    "south": ((6, 14), (5, 15), (5, 16), (5, 17), (5, 18), (5, 19), (6, 20)),
    "west": ((8, 14), (7, 15), (7, 16), (7, 17), (7, 18), (7, 19), (8, 20)),
}
RANGER_BOOT_PIXELS = {
    "north": (),
    "east": ((11, 26), (20, 26)),
    "south": ((10, 26), (21, 26), (22, 27)),
    "west": ((11, 26), (12, 27), (20, 26), (21, 27)),
}
RANGER_STEP_PIXELS = {
    (0, 1): (),
    (1, 1): ((10, 27), (11, 27), (20, 26), (21, 26)),
    (2, 1): ((9, 27), (21, 26), (22, 26)),
    (3, 1): ((10, 27), (11, 27), (20, 26), (21, 26)),
}


def occupied_ranger_pixels(atlas: Image.Image, facing: str) -> set[tuple[int, int]]:
    x0 = facing_index(facing) * 32
    return {
        (x, y)
        for x, y in RANGER_SKIP_COORDS[facing]
        if atlas.getpixel((x0 + x, y))[3] != 255
    }


def enrich_ranger(atlas: Image.Image, col: int, facing: str, step: bool) -> None:
    x0 = col * 32
    skip = occupied_ranger_pixels(atlas, facing)
    for x, y in RANGER_QUIVER_TIPS:
        # The north/east step sources already use all five allowed colors; use
        # the amber equipment channel there so the quiver stays in-budget.
        set_pixels(atlas, ((x0 + x, y),), AMBER if step and facing in RANGER_BUSY_STEPS else BONE)
    for shaft in RANGER_QUIVER_SHAFTS:
        for x, y in shaft:
            atlas.putpixel((x0 + x, y), rgba(AMBER))
    set_pixels(atlas, ((x0 + x, y) for x, y in RANGER_BELTS[facing] if (x, y) not in skip), AMBER)
    if step and facing in RANGER_BUSY_STEPS:
        return
    set_pixels(atlas, ((x0 + x, y) for x, y in RANGER_WRIST_PIXELS[facing] if (x, y) not in skip), STONE)
    set_pixels(atlas, ((x0 + x, y) for x, y in RANGER_BOW_ARCS[facing] if (x, y) not in skip), AMBER)
    boots = RANGER_STEP_PIXELS[(facing_index(facing), 1)] if step else RANGER_BOOT_PIXELS[facing]
    set_pixels(atlas, ((x0 + x, y) for x, y in boots if (x, y) not in skip), STONE)


def draw_melee_pursuer(action: bool) -> Image.Image:
    image = new_sprite()
    draw = ImageDraw.Draw(image)
    y_shift = 1 if action else 0
    draw.polygon([
        (3, 22), (5, 17), (8, 15), (13, 13), (20, 13), (25, 16), (28, 19),
        (28, 24), (24, 25), (21, 27), (16, 27), (12, 25), (7, 27), (3, 26),
    ], fill=rgba(INK))
    draw.polygon([(5, 22), (8, 18), (13, 16), (20, 16), (24, 18), (25, 22), (20, 23), (8, 23)], fill=rgba(DEEP))
    draw.polygon([(8, 19), (13, 17), (17, 17), (16, 21), (10, 21)], fill=rgba(NEUTRAL))
    draw.polygon([(19, 17), (23, 19), (22, 22), (18, 21)], fill=rgba(STONE))
    draw.rectangle((22, 18, 25, 21), fill=rgba(BLOOD))
    for x in (6, 12, 18, 23):
        draw.rectangle((x, 23 - y_shift, x + 2, 26 - y_shift), fill=rgba(INK))
    draw.line((9, 19, 12, 18), fill=rgba(BLOOD), width=1)
    return image


def draw_charging_raider(action: bool) -> Image.Image:
    image = new_sprite()
    draw = ImageDraw.Draw(image)
    front = 2 if action else 0
    draw.polygon([
        (2, 21), (5 + front, 15), (11 + front, 12), (20 + front, 13),
        (25, 17), (29, 19), (29, 24), (24, 26), (18, 25), (11, 26), (4, 25),
    ], fill=rgba(INK))
    draw.polygon([(5, 21), (8 + front, 17), (18 + front, 15), (23, 19), (22, 23), (8, 23)], fill=rgba(DEEP))
    draw.polygon([(8 + front, 18), (14 + front, 16), (18 + front, 18), (16 + front, 22), (10, 22)], fill=rgba(STONE))
    draw.rectangle((11 + front, 19, 16 + front, 20), fill=rgba(STONE))
    draw.polygon([(23, 18), (28, 20), (27, 23), (22, 22)], fill=rgba(BLOOD))
    draw.rectangle((25, 20, 27, 21), fill=rgba(WARNING))
    draw.rectangle((5, 23, 8, 26), fill=rgba(INK))
    draw.rectangle((14, 23, 17, 26), fill=rgba(INK))
    draw.rectangle((21, 23, 24, 26), fill=rgba(INK))
    if action:
        draw.line((3, 18, 7, 16), fill=rgba(WARNING), width=1)
    return image


def draw_fan_ranged(action: bool) -> Image.Image:
    image = new_sprite()
    draw = ImageDraw.Draw(image)
    draw.polygon([
        (15, 3), (21, 9), (21, 15), (18, 18), (18, 23), (20, 26),
        (22, 29), (17, 29), (15, 25), (14, 25), (10, 29), (7, 29),
        (10, 26), (13, 23), (13, 18), (9, 15), (9, 9),
    ], fill=rgba(INK))
    draw.polygon([(15, 5), (19, 10), (19, 14), (15, 16), (11, 14), (11, 10)], fill=rgba(DEEP))
    draw.polygon([(15, 8), (18, 11), (15, 15), (12, 11)], fill=rgba(BLOOD))
    draw.line((15, 8, 15, 13), fill=rgba(WARNING), width=1)
    draw.rectangle((14, 17, 17, 23), fill=rgba(STONE))
    draw.rectangle((12, 19, 13, 22), fill=rgba(STONE))
    draw.rectangle((18, 19, 19, 22), fill=rgba(STONE))
    draw.polygon([(11, 25), (14, 25), (12, 29), (8, 29)], fill=rgba(INK))
    draw.polygon([(17, 25), (19, 25), (22, 29), (17, 29)], fill=rgba(INK))
    if action:
        draw.polygon([(20, 9), (25, 7), (27, 12), (22, 15)], fill=rgba(INK))
        draw.polygon([(21, 10), (24, 9), (25, 11), (22, 13)], fill=rgba(STONE))
        draw.line((23, 10, 25, 11), fill=rgba(WARNING), width=1)
    return image


# These fixed-coordinate refinements add plate seams, rivets, and core layers
# while retaining the v0.2 gate's asymmetric stone mass and bone-white axis.
BOSS_PLATE_SEAMS = (
    (11, 99), (11, 105), (51, 99), (51, 105),
)
BOSS_RIVETS = (
    (15, 113),
)
BOSS_CORE_SHIELD_SEAMS = ((40, 111), (42, 111))
BOSS_HAND_SEAMS = ((75, 119), (105, 114))
BOSS_CORE_LAYERS = {
    "closed": ((148, 81), (146, 86), (148, 86)),
    "open": ((180, 81), (180, 86)),
}


def enrich_boss(atlas: Image.Image) -> None:
    set_pixels(atlas, BOSS_PLATE_SEAMS, DEEP)
    set_pixels(atlas, BOSS_RIVETS, BONE)
    set_pixels(atlas, BOSS_CORE_SHIELD_SEAMS, DEEP)
    set_pixels(atlas, BOSS_HAND_SEAMS, DEEP)
    set_pixels(atlas, BOSS_CORE_LAYERS["closed"], WARNING)
    set_pixels(atlas, BOSS_CORE_LAYERS["open"], WARNING)


ACTOR_RECORDS = [
    {"id": f"ranger_idle_{facing}", "category": "actor/ranger", "row": 0, "col": col,
     "frame_role": f"idle_{facing}", "color_role": "player", "campaign_access": "required"}
    for col, facing in enumerate(("north", "east", "south", "west"))
] + [
    {"id": f"ranger_step_{facing}", "category": "actor/ranger", "row": 0, "col": col + 4,
     "frame_role": f"step_{facing}", "color_role": "player", "campaign_access": "required"}
    for col, facing in enumerate(("north", "east", "south", "west"))
] + [
    {"id": "melee_pursuer_idle", "category": "actor/enemy", "row": 1, "col": 0, "frame_role": "idle", "color_role": "hostile", "campaign_access": "required"},
    {"id": "melee_pursuer_step", "category": "actor/enemy", "row": 1, "col": 1, "frame_role": "step", "color_role": "hostile", "campaign_access": "required"},
    {"id": "charging_raider_idle", "category": "actor/enemy", "row": 1, "col": 2, "frame_role": "idle", "color_role": "hostile", "campaign_access": "required"},
    {"id": "charging_raider_action", "category": "actor/enemy", "row": 1, "col": 3, "frame_role": "charge_windup_or_active", "color_role": "hostile", "campaign_access": "required"},
    {"id": "fan_ranged_idle", "category": "actor/enemy", "row": 1, "col": 4, "frame_role": "idle", "color_role": "hostile", "campaign_access": "required"},
    {"id": "fan_ranged_action", "category": "actor/enemy", "row": 1, "col": 5, "frame_role": "fan_windup_or_active", "color_role": "hostile", "campaign_access": "required"},
    {"id": "threshold_colossus_body", "category": "actor/boss_part", "row": 2, "col": 0, "rect": [0, 64, 64, 64], "frame_role": "gate_body", "color_role": "hostile", "campaign_access": "required"},
    {"id": "threshold_colossus_body_occupied_r3c0", "category": "actor/boss_part_occupied", "row": 3, "col": 0, "rect": [0, 64, 0, 0], "frame_role": "covered_by_64x64_body", "color_role": "hostile", "campaign_access": "reference_or_reserved"},
    {"id": "threshold_colossus_body_occupied_r3c1", "category": "actor/boss_part_occupied", "row": 3, "col": 1, "rect": [32, 64, 0, 0], "frame_role": "covered_by_64x64_body", "color_role": "hostile", "campaign_access": "reference_or_reserved"},
    {"id": "threshold_colossus_body_occupied_r2c1", "category": "actor/boss_part_occupied", "row": 2, "col": 1, "rect": [32, 64, 0, 0], "frame_role": "covered_by_64x64_body", "color_role": "hostile", "campaign_access": "reference_or_reserved"},
    {"id": "threshold_colossus_left_hand", "category": "actor/boss_part", "row": 2, "col": 2, "frame_role": "left_hand", "color_role": "hostile", "campaign_access": "required"},
    {"id": "threshold_colossus_right_hand", "category": "actor/boss_part", "row": 2, "col": 3, "frame_role": "right_hand", "color_role": "hostile", "campaign_access": "required"},
    {"id": "threshold_colossus_core_closed", "category": "actor/boss_part", "row": 2, "col": 4, "frame_role": "phase1_closed_core", "color_role": "hostile", "campaign_access": "required"},
    {"id": "threshold_colossus_core_open", "category": "actor/boss_part", "row": 2, "col": 5, "frame_role": "phase2_open_core", "color_role": "anomaly", "campaign_access": "required"},
]


def reserve_remaining(records: list[dict], rows: int, cols: int, prefix: str) -> list[dict]:
    occupied = {(record["row"], record["col"]) for record in records}
    reserved = []
    for row in range(rows):
        for col in range(cols):
            if (row, col) not in occupied:
                reserved.append({
                    "id": f"{prefix}_r{row}c{col}", "category": "reserved",
                    "row": row, "col": col, "rect": [col * 32, row * 32, 32, 32],
                    "frame_role": "intentionally_empty", "color_role": "transparent",
                    "campaign_access": "reference_or_reserved",
                })
    return records + reserved


ACTOR_RECORDS = reserve_remaining(ACTOR_RECORDS, 4, 8, "actors_reserved")


def build_actor_atlas(source: Image.Image) -> Image.Image:
    atlas = source.copy()
    for facing in ("north", "east", "south", "west"):
        enrich_ranger(atlas, facing_index(facing), facing, False)
        enrich_ranger(atlas, facing_index(facing) + 4, facing, True)
    enrich_boss(atlas)
    return atlas


# ---------------------------------------------------------------------------
# Icons and FX


def icon_base(draw: ImageDraw.ImageDraw, color: str = STONE) -> None:
    draw.rectangle((4, 4, 27, 27), fill=rgba(DEEP), outline=rgba(color), width=2)


def draw_icon(record_id: str) -> Image.Image:
    image = new_sprite()
    draw = ImageDraw.Draw(image)
    icon_base(draw)

    if record_id == "piercing_arrow":
        draw.line((7, 25, 24, 8), fill=rgba(BONE), width=3)
        draw.polygon([(24, 4), (28, 8), (23, 11)], fill=rgba(AMBER))
        points(draw, [(9, 20), (12, 23), (7, 25)], INK)
    elif record_id == "hunter_mark":
        draw.ellipse((9, 9, 22, 22), outline=rgba(AMBER), width=3)
        draw.line((15, 5, 15, 11), fill=rgba(BONE), width=2)
        draw.line((15, 20, 15, 26), fill=rgba(BONE), width=2)
    elif record_id == "dash":
        draw.line((7, 20, 12, 15), fill=rgba(TEAL), width=3)
        draw.line((13, 18, 20, 11), fill=rgba(TEAL), width=3)
        draw.polygon([(20, 7), (25, 10), (21, 14)], fill=rgba(BONE))
    elif record_id == "dodge":
        draw.line((8, 18, 18, 18), fill=rgba(TEAL), width=3)
        draw.polygon([(18, 10), (25, 18), (18, 26)], fill=rgba(BONE))
    elif record_id == "breeding_split":
        draw.line((9, 23, 15, 12), fill=rgba(AMBER), width=2)
        draw.line((15, 12, 21, 7), fill=rgba(AMBER), width=2)
        draw.line((15, 12, 22, 16), fill=rgba(AMBER), width=2)
        draw.polygon([(20, 4), (24, 8), (20, 10)], fill=rgba(BONE))
        draw.polygon([(21, 13), (25, 18), (20, 18)], fill=rgba(BONE))
    elif record_id == "branch_scale":
        draw.line((16, 24, 16, 8), fill=rgba(AMBER), width=2)
        draw.line((16, 17, 8, 10), fill=rgba(AMBER), width=2)
        draw.line((16, 13, 24, 7), fill=rgba(AMBER), width=2)
        draw.rectangle((8, 20, 23, 23), fill=rgba(BONE))
    elif record_id == "afterimage_extension":
        draw.rectangle((8, 10, 13, 23), fill=rgba(TEAL))
        draw.rectangle((15, 8, 20, 23), fill=rgba(BONE))
        draw.line((22, 10, 25, 10), fill=rgba(TEAL), width=2)
        draw.line((22, 16, 26, 16), fill=rgba(TEAL), width=2)
    elif record_id == "pack_hunt_mark":
        draw.polygon([(8, 18), (16, 7), (24, 18)], outline=rgba(PURPLE), width=2)
        draw.ellipse((12, 16, 20, 24), outline=rgba(BONE), width=2)
        points(draw, [(15, 19), (17, 19), (16, 21)], PURPLE)
    elif record_id.startswith(("ashwood", "swift")):
        draw.arc((6, 7, 23, 24), 270, 90, fill=rgba(AMBER), width=3)
        draw.line((15, 6, 15, 25), fill=rgba(BONE), width=2)
        if record_id.startswith("swift"):
            draw.line((10, 11, 21, 11), fill=rgba(TEAL), width=2)
        else:
            draw.rectangle((12, 14, 18, 17), fill=rgba(STONE))
    elif record_id.endswith("quiver"):
        draw.polygon([(10, 6), (20, 6), (22, 25), (15, 28), (8, 25)], fill=rgba(STONE))
        draw.line((12, 6, 12, 22), fill=rgba(AMBER), width=2)
        draw.line((18, 6, 18, 22), fill=rgba(AMBER), width=2)
        if record_id.startswith("lineage"):
            draw.line((10, 16, 20, 16), fill=rgba(BONE), width=2)
        else:
            draw.line((12, 10, 18, 14), fill=rgba(TEAL), width=2)
    elif record_id.endswith("gloves"):
        draw.rectangle((8, 11, 22, 23), fill=rgba(STONE))
        draw.rectangle((11, 7, 19, 11), fill=rgba(DEEP))
        draw.rectangle((11, 16, 19, 18), fill=rgba(AMBER))
        if record_id.startswith("turnfeather"):
            draw.line((7, 13, 12, 8), fill=rgba(TEAL), width=2)
        else:
            draw.line((13, 20, 17, 20), fill=rgba(BONE), width=2)
    elif record_id.endswith("ring"):
        draw.ellipse((8, 8, 23, 23), outline=rgba(BONE), width=3)
        if record_id.startswith("hawk"):
            draw.polygon([(15, 11), (19, 16), (15, 21), (11, 16)], fill=rgba(AMBER))
        else:
            draw.rectangle((13, 14, 18, 18), fill=rgba(BLOOD))
    elif record_id in {"piercing_continuation", "projectile_lifetime", "projectile_speed", "seeking_distance", "turn_response", "carrier_power", "critical_chance", "maximum_health"}:
        draw.rectangle((8, 18, 23, 23), fill=rgba(NEUTRAL))
        if record_id == "piercing_continuation":
            draw.line((8, 13, 23, 13), fill=rgba(AMBER), width=2)
            draw.polygon([(19, 9), (25, 13), (19, 17)], fill=rgba(BONE))
        elif record_id == "projectile_lifetime":
            draw.line((10, 8, 10, 15), fill=rgba(AMBER), width=2)
            draw.line((15, 8, 15, 15), fill=rgba(AMBER), width=2)
            draw.line((20, 8, 20, 15), fill=rgba(AMBER), width=2)
        elif record_id == "projectile_speed":
            draw.line((8, 10, 19, 10), fill=rgba(TEAL), width=2)
            draw.line((11, 14, 23, 14), fill=rgba(TEAL), width=2)
        elif record_id == "seeking_distance":
            draw.ellipse((10, 8, 18, 16), outline=rgba(AMBER), width=2)
            draw.line((17, 15, 23, 21), fill=rgba(BONE), width=2)
        elif record_id == "turn_response":
            draw.line((10, 14, 18, 14), fill=rgba(TEAL), width=2)
            draw.line((18, 9, 23, 14), fill=rgba(TEAL), width=2)
            draw.line((18, 19, 23, 14), fill=rgba(TEAL), width=2)
        elif record_id == "carrier_power":
            draw.rectangle((11, 8, 14, 15), fill=rgba(AMBER))
            draw.rectangle((17, 8, 20, 15), fill=rgba(AMBER))
        elif record_id == "critical_chance":
            draw.line((12, 8, 12, 15), fill=rgba(BONE), width=2)
            draw.line((18, 8, 18, 15), fill=rgba(BONE), width=2)
        else:
            draw.rectangle((12, 8, 19, 13), fill=rgba(BLOOD))
    elif record_id in {"near_enemy_horizon", "direct_gait", "single_key_execution", "short_trace_memory"}:
        draw.ellipse((7, 8, 24, 25), outline=rgba(BONE), width=2)
        if record_id == "near_enemy_horizon":
            draw.rectangle((12, 13, 19, 20), fill=rgba(NEUTRAL))
        elif record_id == "direct_gait":
            draw.line((10, 20, 22, 12), fill=rgba(NEUTRAL), width=2)
        elif record_id == "single_key_execution":
            draw.rectangle((14, 11, 17, 22), fill=rgba(NEUTRAL))
        else:
            draw.line((10, 17, 14, 13), fill=rgba(NEUTRAL), width=2)
            draw.line((17, 17, 21, 13), fill=rgba(NEUTRAL), width=2)
    elif record_id.endswith("_dice"):
        draw.polygon([(10, 8), (22, 8), (25, 16), (16, 24), (7, 16)], fill=rgba(STONE))
        draw.polygon([(13, 11), (19, 11), (21, 16), (16, 20), (11, 16)], fill=rgba(DEEP))
        if record_id == "add_dice":
            points(draw, [(15, 13), (17, 13), (16, 15), (18, 15), (14, 15), (16, 17), (15, 16), (17, 16)], AMBER)
        elif record_id == "rewrite_dice":
            draw.line((13, 15, 19, 15), fill=rgba(PURPLE), width=2)
        else:
            draw.rectangle((14, 13, 18, 18), outline=rgba(TEAL), width=2)
    elif record_id == "clear":
        draw.rectangle((8, 12, 23, 23), outline=rgba(BONE), width=2)
        draw.line((11, 15, 20, 20), fill=rgba(AMBER), width=2)
        draw.line((20, 15, 11, 20), fill=rgba(AMBER), width=2)
    elif record_id == "hunt_elite":
        draw.polygon([(10, 18), (16, 8), (22, 18)], fill=rgba(AMBER))
        draw.rectangle((13, 20, 19, 24), fill=rgba(BLOOD))
    elif record_id == "timed_break":
        draw.ellipse((9, 8, 22, 21), outline=rgba(BONE), width=2)
        draw.line((16, 12, 16, 17), fill=rgba(AMBER), width=2)
        draw.line((16, 12, 20, 14), fill=rgba(AMBER), width=2)
    elif record_id == "exposed_ground_zone":
        draw.rectangle((7, 15, 24, 23), outline=rgba(WARNING), width=2)
        draw.line((9, 18, 22, 18), fill=rgba(BLOOD), width=2)
    elif record_id == "moving_fireline":
        draw.line((8, 20, 23, 20), fill=rgba(WARNING), width=3)
        draw.polygon([(8, 10), (13, 18), (8, 18)], fill=rgba(BLOOD))
        draw.polygon([(17, 8), (23, 18), (15, 18)], fill=rgba(BLOOD))
    elif record_id == "periodic_barrier":
        draw.ellipse((8, 9, 23, 24), outline=rgba(TEAL), width=2)
        draw.line((10, 16, 21, 16), fill=rgba(BONE), width=2)
        draw.line((16, 10, 16, 22), fill=rgba(BONE), width=2)
    elif record_id == "summon_reinforcements":
        draw.rectangle((14, 7, 17, 16), fill=rgba(PURPLE))
        draw.rectangle((8, 18, 13, 23), fill=rgba(NEUTRAL))
        draw.rectangle((18, 18, 23, 23), fill=rgba(NEUTRAL))
    elif record_id == "threshold_transition":
        draw.rectangle((8, 7, 23, 24), fill=rgba(STONE))
        draw.rectangle((12, 11, 19, 20), fill=rgba(BLOOD))
        draw.line((12, 15, 19, 15), fill=rgba(WARNING), width=2)
    elif record_id == "slam":
        draw.rectangle((8, 10, 23, 18), fill=rgba(BLOOD))
        draw.line((8, 21, 23, 21), fill=rgba(WARNING), width=3)
    elif record_id == "sweep":
        draw.arc((7, 8, 24, 25), 200, 340, fill=rgba(WARNING), width=3)
        draw.line((10, 22, 22, 10), fill=rgba(BONE), width=3)
    elif record_id == "lane":
        draw.rectangle((8, 11, 12, 21), fill=rgba(BLOOD))
        draw.rectangle((19, 11, 23, 21), fill=rgba(BLOOD))
        draw.line((14, 11, 17, 21), fill=rgba(WARNING), width=2)
    elif record_id == "melee_pursuer":
        draw.polygon([(7, 20), (12, 12), (20, 12), (24, 17), (24, 23), (8, 23)], fill=rgba(NEUTRAL))
        draw.rectangle((20, 16, 23, 19), fill=rgba(BLOOD))
    elif record_id == "charging_raider":
        draw.polygon([(6, 19), (12, 12), (23, 14), (25, 19), (20, 23), (9, 23)], fill=rgba(NEUTRAL))
        draw.rectangle((20, 16, 24, 19), fill=rgba(WARNING))
    elif record_id == "fan_ranged":
        draw.polygon([(13, 6), (20, 13), (16, 18), (11, 13)], fill=rgba(NEUTRAL))
        draw.line((9, 20, 6, 25), fill=rgba(NEUTRAL), width=2)
        draw.line((18, 20, 23, 25), fill=rgba(NEUTRAL), width=2)
        draw.rectangle((14, 10, 17, 14), fill=rgba(BLOOD))
    elif record_id == "threshold_colossus":
        draw.rectangle((7, 7, 24, 24), fill=rgba(STONE))
        draw.rectangle((13, 10, 18, 22), fill=rgba(BONE))
        draw.rectangle((15, 14, 16, 18), fill=rgba(BLOOD))
    else:
        raise ValueError(f"unexpected nonreserved icon: {record_id}")
    return image


ICON_IDS = [
    "piercing_arrow", "hunter_mark", "dash", "dodge",
    "breeding_split", "branch_scale", "afterimage_extension", "pack_hunt_mark",
    "ashwood_longbow", "swift_recurve_bow", "lineage_quiver", "farwatch_quiver",
    "turnfeather_gloves", "piercer_gloves", "hawk_eye_ring", "vitality_ring",
    "piercing_continuation", "projectile_lifetime", "projectile_speed", "seeking_distance",
    "turn_response", "carrier_power", "critical_chance", "maximum_health",
    "near_enemy_horizon", "direct_gait", "single_key_execution", "short_trace_memory",
    "add_dice", "rewrite_dice", "refine_dice", "clear",
    "hunt_elite", "timed_break", "exposed_ground_zone", "moving_fireline",
    "periodic_barrier", "summon_reinforcements", "threshold_transition", "slam",
    "sweep", "lane", "melee_pursuer", "charging_raider",
    "fan_ranged", "threshold_colossus", None, None,
] + [None] * 16


ICON_ACCESS = {
    "required": {
        "piercing_arrow", "hunter_mark", "dash", "dodge", "pack_hunt_mark",
        "near_enemy_horizon", "direct_gait", "single_key_execution", "short_trace_memory",
        "clear", "hunt_elite", "timed_break", "exposed_ground_zone", "moving_fireline",
        "periodic_barrier", "summon_reinforcements", "threshold_transition", "slam",
        "sweep", "lane", "melee_pursuer", "charging_raider", "fan_ranged", "threshold_colossus",
    },
    "reachable_defined": {
        "breeding_split", "ashwood_longbow", "swift_recurve_bow", "lineage_quiver",
        "farwatch_quiver", "turnfeather_gloves", "piercer_gloves", "hawk_eye_ring",
        "vitality_ring", "piercing_continuation", "projectile_lifetime", "projectile_speed",
        "seeking_distance", "turn_response", "carrier_power", "critical_chance",
        "maximum_health", "add_dice", "rewrite_dice", "refine_dice",
    },
}

ICON_CATEGORIES = {
    "skill": {"piercing_arrow", "hunter_mark", "dash", "dodge"},
    "rune": {"breeding_split", "branch_scale", "afterimage_extension"},
    "law": {"pack_hunt_mark"},
    "equipment": {
        "ashwood_longbow", "swift_recurve_bow", "lineage_quiver", "farwatch_quiver",
        "turnfeather_gloves", "piercer_gloves", "hawk_eye_ring", "vitality_ring",
    },
    "affix": {
        "piercing_continuation", "projectile_lifetime", "projectile_speed",
        "seeking_distance", "turn_response", "carrier_power", "critical_chance",
        "maximum_health",
    },
    "proxy_core": {
        "near_enemy_horizon", "direct_gait", "single_key_execution", "short_trace_memory",
    },
    "forge_currency": {"add_dice", "rewrite_dice", "refine_dice"},
    "objective": {"clear", "hunt_elite", "timed_break"},
    "hazard": {"exposed_ground_zone", "moving_fireline"},
    "elite_rule": {"periodic_barrier", "summon_reinforcements"},
    "boss_telegraph": {"threshold_transition", "slam", "sweep", "lane"},
    "codex_enemy": {"melee_pursuer", "charging_raider", "fan_ranged", "threshold_colossus"},
}


def icon_category(record_id: str) -> str:
    matches = [category for category, ids in ICON_CATEGORIES.items() if record_id in ids]
    assert len(matches) == 1, record_id
    return f"icon/{matches[0]}"


def icon_color_role(record_id: str) -> str:
    if record_id in {"dash", "dodge", "afterimage_extension", "refine_dice", "periodic_barrier"}:
        return "mobility_or_system_teal"
    if record_id in {"pack_hunt_mark", "rewrite_dice", "summon_reinforcements"}:
        return "law_or_anomaly_purple"
    if record_id in ICON_CATEGORIES["proxy_core"]:
        return "common_core_bone"
    if record_id in ICON_CATEGORIES["hazard"] | ICON_CATEGORIES["boss_telegraph"] | ICON_CATEGORIES["codex_enemy"]:
        return "hostile_or_warning_red"
    if record_id in ICON_CATEGORIES["equipment"]:
        return "equipment_material_identity"
    if record_id in ICON_CATEGORIES["affix"]:
        return "parameter_shape_then_accent"
    return "player_or_objective_amber"


def icon_access(record_id: str) -> str:
    if record_id in ICON_ACCESS["required"]:
        return "required"
    if record_id in ICON_ACCESS["reachable_defined"]:
        return "reachable_defined"
    return "reference_or_reserved"


def build_icon_records() -> list[dict]:
    records = []
    for index, record_id in enumerate(ICON_IDS):
        row, col = divmod(index, 8)
        records.append({
            "id": record_id or f"icons_reserved_r{row}c{col}",
            "category": "reserved" if record_id is None else icon_category(record_id),
            "row": row, "col": col, "rect": [col * 32, row * 32, 32, 32],
            "frame_role": "intentionally_empty" if record_id is None else "static_icon",
            "color_role": "transparent" if record_id is None else icon_color_role(record_id),
            "campaign_access": icon_access(record_id or ""),
            "first_act_reward": "not_applicable" if record_id is None else (
                "reachable" if record_id in {"breeding_split", "pack_hunt_mark"} else
                "not_reachable" if record_id in {"branch_scale", "afterimage_extension"} else "pool_or_system"
            ),
        })
    return records


ICON_RECORDS = build_icon_records()


def build_icon_atlas() -> Image.Image:
    atlas = Image.new("RGBA", (256, 256), TRANSPARENT)
    for record in ICON_RECORDS:
        if not record["id"].startswith("icons_reserved"):
            paste(atlas, draw_icon(record["id"]), record["col"], record["row"])
    return atlas


FX_SPECS: list[tuple[str, str, str, str]] = [
    ("arrow_straight", "arrow", "flight_body", "player"),
    ("arrow_trail_early", "arrow", "flight_trail_early", "player"),
    ("arrow_trail_mid", "arrow", "flight_trail_mid", "player"),
    ("arrow_trail_late", "arrow", "flight_trail_late", "player"),
    ("hit_spark_windup", "hit_spark", "impact_windup", "hostile_feedback"),
    ("hit_spark_impact", "hit_spark", "impact_active", "hostile_feedback"),
    ("hit_spark_split", "hit_spark", "impact_split", "player"),
    ("hit_spark_recover", "hit_spark", "impact_recover", "player"),
    ("hunter_mark_pending", "mark", "pending", "player"),
    ("hunter_mark_active", "mark", "active", "player"),
    ("hunter_mark_branch", "mark", "branch_history", "law"),
    ("dash_afterimage_early", "afterimage", "dash_early", "mobility"),
    ("dash_afterimage_mid", "afterimage", "dash_mid", "mobility"),
    ("dash_afterimage_late", "afterimage", "dash_late", "mobility"),
    ("dodge_afterimage_early", "afterimage", "dodge_early", "mobility"),
    ("dodge_afterimage_mid", "afterimage", "dodge_mid", "mobility"),
    ("dodge_afterimage_late", "afterimage", "dodge_late", "mobility"),
    ("barrier_off", "barrier", "inactive", "system"),
    ("barrier_windup", "barrier", "windup", "system"),
    ("barrier_active", "barrier", "active", "system"),
    ("summon_pulse_inner", "summon_pulse", "inner_ring", "anomaly"),
    ("summon_pulse_outer", "summon_pulse", "outer_ring", "anomaly"),
    ("summon_pulse_settle", "summon_pulse", "settle", "anomaly"),
    ("boss_core_closed", "boss_core", "phase1", "hostile"),
    ("boss_core_cracking", "boss_core", "transition_start", "anomaly"),
    ("boss_core_open", "boss_core", "phase2", "anomaly"),
    ("boss_core_flare", "boss_core", "attack_synchronizer", "anomaly"),
    ("loot_pickup_spawn", "loot", "spawn", "common"),
    ("loot_pickup_rise", "loot", "rise", "common"),
    ("loot_pickup_collect", "loot", "collect", "common"),
    ("loot_pickup_settle", "loot", "settle", "common"),
    ("fx_reserved_r3c7", "reserved", "intentionally_empty", "transparent"),
]


def draw_fx(record_id: str, family: str) -> Image.Image:
    image = new_sprite()
    draw = ImageDraw.Draw(image)
    if family == "arrow":
        if record_id == "arrow_straight":
            draw.line((5, 16, 23, 16), fill=rgba(BONE), width=2)
            draw.polygon([(24, 12), (28, 16), (24, 20)], fill=rgba(AMBER))
            points(draw, [(6, 13), (8, 19), (5, 19)], AMBER)
        else:
            lengths = {"early": 12, "mid": 8, "late": 5}
            length = lengths[record_id.rsplit("_", 1)[1]]
            draw.line((24 - length, 16, 23, 16), fill=rgba(AMBER), width=2)
            draw.line((20 - length, 14, 23 - length, 14), fill=rgba(BONE), width=1)
            draw.line((20 - length, 18, 23 - length, 18), fill=rgba(BONE), width=1)
    elif family == "hit_spark":
        if record_id.endswith("windup"):
            points(draw, [(15, 10), (16, 10), (10, 15), (10, 16), (21, 15), (21, 16), (15, 21), (16, 21)], WARNING)
        elif record_id.endswith("impact"):
            draw.line((7, 16, 13, 16), fill=rgba(WARNING), width=2)
            draw.line((18, 16, 24, 16), fill=rgba(WARNING), width=2)
            draw.line((15, 8, 15, 13), fill=rgba(BONE), width=2)
            draw.line((16, 18, 16, 23), fill=rgba(BONE), width=2)
        elif record_id.endswith("split"):
            draw.line((8, 22, 14, 14), fill=rgba(BONE), width=2)
            draw.line((17, 13, 23, 8), fill=rgba(BONE), width=2)
            draw.line((17, 17, (23), 22), fill=rgba(BONE), width=2)
            points(draw, [(14, 14), (17, 13), (17, 17)], AMBER)
        else:
            points(draw, [(14, 13), (17, 13), (14, 18), (17, 18)], NEUTRAL)
    elif family == "mark":
        if record_id.endswith("pending"):
            draw.ellipse((10, 10, 21, 21), outline=rgba(AMBER), width=2)
        elif record_id.endswith("active"):
            draw.ellipse((8, 8, 23, 23), outline=rgba(AMBER), width=3)
            draw.line((15, 12, 15, 19), fill=rgba(BONE), width=2)
        else:
            draw.ellipse((8, 8, 23, 23), outline=rgba(PURPLE), width=2)
            draw.line((12, 16, 20, 16), fill=rgba(BONE), width=2)
            draw.line((16, 12, 16, 20), fill=rgba(BONE), width=2)
    elif family == "afterimage":
        opacity = {"early": BONE, "mid": TEAL, "late": STONE}[record_id.rsplit("_", 1)[1]]
        if record_id.startswith("dash"):
            draw.line((8, 19, 17, 10), fill=rgba(opacity), width=4)
            draw.polygon([(18, 7), (23, 9), (19, 14)], fill=rgba(TEAL))
        else:
            draw.arc((8, 8, 22, 22), 240, 300, fill=rgba(opacity), width=4)
            draw.line((20, 15, 25, 15), fill=rgba(TEAL), width=2)
    elif family == "barrier":
        if record_id.endswith("off"):
            draw.ellipse((11, 11, 20, 20), outline=rgba(STONE), width=2)
        elif record_id.endswith("windup"):
            draw.ellipse((9, 9, 22, 22), outline=rgba(TEAL), width=2)
            points(draw, [(8, 16), (23, 16)], BONE)
        else:
            draw.ellipse((7, 7, 24, 24), outline=rgba(TEAL), width=3)
            draw.line((11, 16, 20, 16), fill=rgba(BONE), width=2)
    elif family == "summon_pulse":
        if record_id.endswith("inner"):
            draw.ellipse((10, 10, 21, 21), outline=rgba(PURPLE), width=3)
        elif record_id.endswith("outer"):
            draw.ellipse((7, 7, 24, 24), outline=rgba(PURPLE), width=2)
            points(draw, [(15, 4), (16, 4), (15, 27), (16, 27)], BONE)
        else:
            points(draw, [(11, 16), (20, 16), (16, 11), (16, 20)], NEUTRAL)
    elif family == "boss_core":
        draw.polygon([(8, 8), (23, 8), (23, 23), (8, 23)], outline=rgba(STONE), width=2)
        if record_id.endswith("closed"):
            draw.line((14, 12, 17, 19), fill=rgba(BLOOD), width=2)
        elif record_id.endswith("cracking"):
            draw.line((12, 12, 19, 19), fill=rgba(WARNING), width=2)
            draw.line((19, 12, (12), 19), fill=rgba(WARNING), width=2)
        elif record_id.endswith("open"):
            draw.rectangle((13, 11, 18, 20), fill=rgba(WARNING))
            draw.rectangle((15, 13, 16, 18), fill=rgba(PURPLE))
        else:
            draw.rectangle((13, 11, 18, 20), fill=rgba(PURPLE))
            points(draw, [(10, 15), (21, 15), (15, 10), (15, 21)], WARNING)
    elif family == "loot":
        if record_id.endswith("spawn"):
            draw.rectangle((12, 15, 19, 20), fill=rgba(BONE))
        elif record_id.endswith("rise"):
            draw.rectangle((12, 12, 19, 17), fill=rgba(BONE))
            draw.line((15, 20, 15, 23), fill=rgba(AMBER), width=2)
        elif record_id.endswith("collect"):
            draw.polygon([(11, 17), (16, 8), (21, 17)], fill=rgba(AMBER))
            draw.rectangle((13, 19, 19, 22), fill=rgba(BONE))
        else:
            points(draw, [(13, 18), (18, 18), (13, 22), (18, 22)], NEUTRAL)
    return image


def build_fx_records() -> list[dict]:
    records = []
    for index, (record_id, category, role, color_role) in enumerate(FX_SPECS):
        row, col = divmod(index, 8)
        records.append({
            "id": record_id, "category": category if category == "reserved" else f"fx/{category}",
            "row": row, "col": col,
            "rect": [col * 32, row * 32, 32, 32], "frame_role": role,
            "color_role": color_role,
            "campaign_access": "reference_or_reserved" if category == "reserved" else "required",
        })
    return records


FX_RECORDS = build_fx_records()


def build_fx_atlas() -> Image.Image:
    atlas = Image.new("RGBA", (256, 128), TRANSPARENT)
    for record in FX_RECORDS:
        if record["category"] != "reserved":
            paste(atlas, draw_fx(record["id"], record["category"][3:]), record["col"], record["row"])
    return atlas


# ---------------------------------------------------------------------------
# Review boards


def label_pair(label: str) -> tuple[str, str]:
    if "_" not in label:
        return label, ""
    parts = label.split("_")
    middle = len(parts) // 2
    return "_".join(parts[:middle]), "_".join(parts[middle:])


def crop_rect(image: Image.Image, rect: tuple[int, int, int, int]) -> Image.Image:
    x, y, width, height = rect
    return image.crop((x, y, x + width, y + height))


def board_base(title: str, subtitle: str) -> tuple[Image.Image, ImageDraw.ImageDraw]:
    canvas = Image.new("RGBA", (1280, 720), rgba(INK))
    draw = ImageDraw.Draw(canvas)
    draw.rectangle((16, 16, 1263, 703), outline=rgba(STONE), width=2)
    draw.text((48, 36), title, font=font(24), fill=rgba(BONE))
    draw.text((48, 68), subtitle, font=font(14), fill=rgba(NEUTRAL))
    return canvas, draw


ACTOR_BOARD_RANGER_REGIONS = [
    (58 + index * 146, 104, 133, 173) for index in range(8)
]
ACTOR_BOARD_ENEMY_REGIONS = [
    (70 + index * 132, 348, 120, 153) for index in range(6)
]
ACTOR_BOARD_BOSS_REGION = (884, 366, 240, 270)
ACTOR_BOARD_PART_REGIONS = [
    (1128 + (index % 2) * 66, 374 + (index // 2) * 138, 64, 90)
    for index in range(4)
]


def make_actor_board(atlas: Image.Image) -> Image.Image:
    canvas, draw = board_base("ACT I ACTORS / 100%", "v0.3 / 32px cells / boss body 64x64")
    for index in range(8):
        sprite = atlas.crop((index * 32, 0, index * 32 + 32, 32)).resize((128, 128), Image.Resampling.NEAREST)
        canvas.alpha_composite(sprite, (66 + index * 146, 112))
        draw.rectangle((58 + index * 146, 104, 190 + index * 146, 248), outline=rgba(STONE), width=1)
        label = f"{'N' if index % 4 == 0 else 'E' if index % 4 == 1 else 'S' if index % 4 == 2 else 'W'}-{'IDLE' if index < 4 else 'STEP'}"
        draw.text((86 + index * 146, 254), label, font=font(14), fill=rgba(NEUTRAL))
    for index in range(6):
        col = index % 6
        sprite = atlas.crop((col * 32, 32, col * 32 + 32, 64)).resize((112, 112), Image.Resampling.NEAREST)
        box_x = 70 + col * 132
        canvas.alpha_composite(sprite, (box_x + 4, 356))
        draw.rectangle((box_x, 348, box_x + 120, 476), outline=rgba(STONE), width=1)
        draw.text((box_x + 8, 482), ["MELEE-I", "MELEE-A", "CHARGE-I", "CHARGE-A", "RANGED-I", "RANGED-A"][index], font=font(12), fill=rgba(NEUTRAL))
    body = atlas.crop((0, 64, 64, 128)).resize((240, 240), Image.Resampling.NEAREST)
    canvas.alpha_composite(body, ACTOR_BOARD_BOSS_REGION[:2])
    left = atlas.crop((64, 64, 96, 96))
    right = atlas.crop((96, 64, 128, 96))
    closed = atlas.crop((128, 64, 160, 96))
    opened = atlas.crop((160, 64, 192, 96))
    draw.text((880, 616), "BOSS", font=font(14), fill=rgba(BONE))
    for region, sprite, label in zip(
        ACTOR_BOARD_PART_REGIONS,
        (left, right, closed, opened),
        ("L", "R", "CLOSED", "OPEN"),
    ):
        x, y, _, _ = region
        compact = sprite.resize((64, 64), Image.Resampling.NEAREST)
        canvas.alpha_composite(compact, (x, y))
        label_width = draw.textbbox((0, 0), label, font=font(12))[2]
        draw.text((x + 32 - label_width // 2, y + 68), label, font=font(12), fill=rgba(NEUTRAL))
    return canvas


def make_grid_board(atlas: Image.Image, records: list[dict], title: str, subtitle: str) -> Image.Image:
    canvas, draw = board_base(title, subtitle)
    cell_w, cell_h = 144, 76
    for record in records:
        board_x = 34 + record["col"] * cell_w
        board_y = 86 + record["row"] * cell_h
        sprite = crop_rect(atlas, tuple(record["rect"])).resize((64, 64), Image.Resampling.NEAREST)
        canvas.alpha_composite(sprite, (board_x + 8, board_y + 4))
        if record["frame_role"] == "intentionally_empty":
            draw.text((board_x + 78, board_y + 28), "R", font=font(12), fill=rgba(STONE))
        else:
            first, second = label_pair(record["id"])
            draw.text((board_x + 78, board_y + 20), first[:11], font=font(9), fill=rgba(BONE))
            draw.text((board_x + 78, board_y + 34), second[:11], font=font(9), fill=rgba(NEUTRAL))
    return canvas


def save_review_variants(board: Image.Image, stem: str) -> None:
    full_path = REVIEW_DIR / f"{stem}_100.png"
    quarter_path = REVIEW_DIR / f"{stem}_25.png"
    gray_path = REVIEW_DIR / f"{stem}_25_gray.png"
    board.save(full_path)
    quarter = board.resize((320, 180), Image.Resampling.NEAREST)
    quarter.save(quarter_path)
    ImageOps.grayscale(quarter.convert("RGB")).convert("RGB").save(gray_path)


# ---------------------------------------------------------------------------
# Validation and generation


def load_json(path: Path) -> dict:
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def validate_content(items: dict, campaign: dict) -> None:
    assert [item["id"] for item in items["base_items"]] == [
        "ashwood_longbow", "swift_recurve_bow", "lineage_quiver", "farwatch_quiver",
        "turnfeather_gloves", "piercer_gloves", "hawk_eye_ring", "vitality_ring",
    ]
    assert [item["id"] for item in items["affix_families"]] == [
        "piercing_continuation", "projectile_lifetime", "projectile_speed",
        "seeking_distance", "turn_response", "carrier_power", "critical_chance", "maximum_health",
    ]
    assert [item["id"] for item in items["runes"]] == ["breeding_split", "branch_scale", "afterimage_extension"]
    assert [item["id"] for item in items["laws"]] == ["pack_hunt_mark"]
    assert [item["id"] for item in campaign["normal_enemies"]] == ["melee_pursuer", "charging_raider", "fan_ranged"]
    assert [item["id"] for item in campaign["hazards"]] == ["exposed_ground_zone", "moving_fireline"]
    assert [item["id"] for item in campaign["elite_rules"]] == ["periodic_barrier", "summon_reinforcements"]
    assert [boss["id"] for boss in campaign["bosses"]] == ["threshold_colossus"]


def cell_stats(image: Image.Image, rect: tuple[int, int, int, int]) -> tuple[int, set[tuple[int, int, int]], bool]:
    x, y, width, height = rect
    crop = image.crop((x, y, x + width, y + height))
    pixels = crop.get_flattened_data()
    alphas = {pixel[3] for pixel in pixels}
    opaque_colors = {pixel[:3] for pixel in pixels if pixel[3] == 255}
    nonempty = any(pixel[3] == 255 for pixel in pixels)
    return alphas, opaque_colors, nonempty


def transparent_border(image: Image.Image, rect: tuple[int, int, int, int], inset: int = 2) -> bool:
    x, y, w, h = rect
    if w <= inset * 2 or h <= inset * 2:
        return False
    for x0, y0, x1, y1 in (
        (x, y, x + w, y + inset), (x, y + h - inset, x + w, y + h),
        (x, y, x + inset, y + h), (x + w - inset, y, x + w, y + h),
    ):
        if any(pixel[3] != 0 for pixel in image.crop((x0, y0, x1, y1)).get_flattened_data()):
            return False
    return True


def validate_atlas(
    atlas: Image.Image, records: list[dict], size: tuple[int, int], rows: int, cols: int,
    require_border: bool = True,
) -> None:
    assert atlas.size == size and atlas.mode == "RGBA"
    assert len(records) == rows * cols
    assert len({(r["row"], r["col"]) for r in records}) == rows * cols
    for pixel in atlas.get_flattened_data():
        assert pixel[3] in {0, 255}
        if pixel[3] == 255:
            assert pixel[:3] in PALETTE_RGB
    for record in records:
        rect = record.get("rect") or [record["col"] * 32, record["row"] * 32, 32, 32]
        alphas, colors, nonempty = cell_stats(atlas, tuple(rect))
        if record["category"] == "reserved":
            assert not nonempty
        elif record["category"] != "actor/boss_part_occupied":
            assert nonempty
        assert alphas.issubset({0, 255})
        assert colors.issubset(PALETTE_RGB)
        if nonempty and rect[2] == 32 and rect[3] == 32:
            assert len(colors) <= 5
            if require_border:
                assert transparent_border(atlas, tuple(rect), 2)
        assert 0 <= record["row"] < rows
        assert 0 <= record["col"] < cols
        if record["category"] != "actor/boss_part_occupied":
            assert record["rect"][0:2] == [record["col"] * 32, record["row"] * 32]
        assert tuple(record["rect"][2:]) in ((32, 32), (64, 64), (0, 0))


def validate_record_ids(records: list[dict], kind: str) -> None:
    ids = [record["id"] for record in records]
    assert len(ids) == len(set(ids)), kind


def validate_reviews() -> None:
    for stem in ("actors", "icons", "fx"):
        full = Image.open(REVIEW_DIR / f"{stem}_100.png").convert("RGBA")
        quarter = Image.open(REVIEW_DIR / f"{stem}_25.png").convert("RGBA")
        gray = Image.open(REVIEW_DIR / f"{stem}_25_gray.png").convert("RGB")
        assert full.size == (1280, 720)
        assert quarter.size == (320, 180)
        assert gray.size == (320, 180)
        assert list(quarter.get_flattened_data()) == list(
            full.resize((320, 180), Image.Resampling.NEAREST).get_flattened_data()
        )
        expected_gray = ImageOps.grayscale(full.convert("RGB").resize((320, 180), Image.Resampling.NEAREST)).convert("RGB")
        assert list(gray.get_flattened_data()) == list(expected_gray.get_flattened_data())


def normalize_records(records: list[dict]) -> list[dict]:
    normalized = []
    for record in records:
        rect = record.get("rect") or [record["col"] * 32, record["row"] * 32, 32, 32]
        normalized.append({**record, "rect": rect})
    return normalized


def rectangles_intersect(
    first: tuple[int, int, int, int], second: tuple[int, int, int, int],
) -> bool:
    return (
        first[0] < second[0] + second[2]
        and second[0] < first[0] + first[2]
        and first[1] < second[1] + second[3]
        and second[1] < first[1] + first[3]
    )


def actor_board_regions() -> list[tuple[str, tuple[int, int, int, int]]]:
    regions: list[tuple[str, tuple[int, int, int, int]]] = [
        (f"ranger-{index}", region)
        for index, region in enumerate(ACTOR_BOARD_RANGER_REGIONS)
    ]
    enemy_labels = ("melee", "charge", "ranged")
    regions.extend(
        (f"enemy-{family}-{state}", region)
        for region, (family, state) in zip(
            ACTOR_BOARD_ENEMY_REGIONS,
            [(family, state) for family in enemy_labels for state in ("idle", "active")],
        )
    )
    regions.append(("boss-body", ACTOR_BOARD_BOSS_REGION))
    regions.extend(
        (f"boss-{label.lower()}", region)
        for label, region in zip(("L", "R", "CLOSED", "OPEN"), ACTOR_BOARD_PART_REGIONS)
    )
    return regions


def validate_actor_specifics(source: Image.Image, actors: Image.Image, records: list[dict]) -> None:
    assert actors.tobytes() != source.tobytes()
    used = [
        record for record in records
        if record["category"] not in {"reserved", "actor/boss_part_occupied"}
    ]
    assert all(
        crop_rect(actors, tuple(record["rect"])).getbbox() for record in used
    )

    regions = actor_board_regions()
    for _, (x, y, width, height) in regions:
        assert 16 <= x and 16 <= y
        assert x + width <= 1264 and y + height <= 704
    for first in range(len(regions)):
        for second in range(first + 1, len(regions)):
            assert not rectangles_intersect(regions[first][1], regions[second][1]), (
                regions[first][0], regions[second][0]
            )

    # Preserve all v0.2 silhouettes outside the fixed-coordinate enrichment.
    ranger_cols = {
        facing_index(facing) * 32 + offset
        for facing in ("north", "east", "south", "west")
        for offset in range(256)
    }
    allowed_changed = {
        *((x, y) for x in ranger_cols for y in range(3, 31)),
        *((x, y) for x in range(0, 64) for y in range(64, 128)),
        *((x, y) for x in range(64, 256) for y in range(64, 96)),
    }
    changed = {
        (x, y) for y in range(128) for x in range(256)
        if actors.getpixel((x, y)) != source.getpixel((x, y))
    }
    assert changed
    assert all((x, y) in allowed_changed for x, y in changed)
    assert all(source.getpixel((x, y))[3] == 255 for x, y in changed)


def generate() -> None:
    assert sha256(SOURCE_ATLAS) == SOURCE_ATLAS_SHA256
    source = Image.open(SOURCE_ATLAS).convert("RGBA")
    assert source.size == (256, 128) and source.mode == "RGBA"
    assert any(source.getpixel((x, y))[3] == 255 for x in range(256) for y in range(128))

    items = load_json(ITEMS_JSON)
    campaign = load_json(CAMPAIGN_JSON)
    validate_content(items, campaign)

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    REVIEW_DIR.mkdir(parents=True, exist_ok=True)

    actor_records = normalize_records(ACTOR_RECORDS)
    icon_records = normalize_records(ICON_RECORDS)
    fx_records = normalize_records(FX_RECORDS)
    actors = build_actor_atlas(source)
    icons = build_icon_atlas()
    fx = build_fx_atlas()

    validate_atlas(actors, actor_records, (256, 128), 4, 8, require_border=False)
    validate_atlas(icons, icon_records, (256, 256), 8, 8)
    validate_atlas(fx, fx_records, (256, 128), 4, 8)
    validate_record_ids(actor_records, "actors")
    validate_record_ids(icon_records, "icons")
    validate_record_ids(fx_records, "fx")
    validate_actor_specifics(source, actors, actor_records)

    actor_path = OUTPUT_DIR / "actors_atlas.png"
    icon_path = OUTPUT_DIR / "act1_icons_atlas.png"
    fx_path = OUTPUT_DIR / "combat_fx_atlas.png"
    actors.save(actor_path)
    icons.save(icon_path)
    fx.save(fx_path)

    save_review_variants(make_actor_board(actors), "actors")
    save_review_variants(make_grid_board(icons, icon_records, "ACT I ICONS / 100%", "8x8 / 32px cells / R = reserved"), "icons")
    save_review_variants(make_grid_board(fx, fx_records, "ACT I COMBAT FX / 100%", "8x4 / 32px cells / R = reserved"), "fx")
    validate_reviews()

    manifest = {
        "version": "0.3.0",
        "palette": PALETTE_HEX,
        "atlases": {
            "actors_atlas.png": {"dimensions": [256, 128], "cell_size": [32, 32], "grid": [8, 4], "records": actor_records},
            "act1_icons_atlas.png": {"dimensions": [256, 256], "cell_size": [32, 32], "grid": [8, 8], "records": icon_records},
            "combat_fx_atlas.png": {"dimensions": [256, 128], "cell_size": [32, 32], "grid": [8, 4], "records": fx_records},
        },
        "validation": {
            "source_v02_sha256": SOURCE_ATLAS_SHA256,
            "source_usage": "versioned_baseline_copy_followed_by_deterministic_pixel_enrichment",
            "alpha_values": [0, 255],
            "rgb_palette_only": True,
            "review_100_dimensions": [1280, 720],
            "review_25_dimensions": [320, 180],
            "review_resampling": "NEAREST",
            "review_grayscale": "PIL.ImageOps.grayscale_after_nearest_25",
            "artifact_sha256": {
                "actors_atlas.png": sha256(actor_path),
                "act1_icons_atlas.png": sha256(icon_path),
                "combat_fx_atlas.png": sha256(fx_path),
                "review/actors_100.png": sha256(REVIEW_DIR / "actors_100.png"),
                "review/actors_25.png": sha256(REVIEW_DIR / "actors_25.png"),
                "review/actors_25_gray.png": sha256(REVIEW_DIR / "actors_25_gray.png"),
                "review/icons_100.png": sha256(REVIEW_DIR / "icons_100.png"),
                "review/icons_25.png": sha256(REVIEW_DIR / "icons_25.png"),
                "review/icons_25_gray.png": sha256(REVIEW_DIR / "icons_25_gray.png"),
                "review/fx_100.png": sha256(REVIEW_DIR / "fx_100.png"),
                "review/fx_25.png": sha256(REVIEW_DIR / "fx_25.png"),
                "review/fx_25_gray.png": sha256(REVIEW_DIR / "fx_25_gray.png"),
            },
        },
    }
    with MANIFEST_PATH.open("w", encoding="utf-8") as handle:
        json.dump(manifest, handle, ensure_ascii=False, indent=2, sort_keys=True)
        handle.write("\n")

    print(f"actors_sha256={manifest['validation']['artifact_sha256']['actors_atlas.png']}")
    print(f"icons_sha256={manifest['validation']['artifact_sha256']['act1_icons_atlas.png']}")
    print(f"fx_sha256={manifest['validation']['artifact_sha256']['combat_fx_atlas.png']}")
    print("review_variants=exact_nearest_and_grayscale")
    print("ACT1_V03_ART_VALIDATION_PASS")


if __name__ == "__main__":
    generate()
