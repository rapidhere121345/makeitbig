#!/usr/bin/env python3
"""Deterministically generate the v0.3 base-art candidate package."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Iterable

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[3]
OUTPUT_DIR = ROOT / "art" / "early" / "v0.3" / "base"
REVIEW_DIR = ROOT / "docs" / "art-concepts" / "v0.3" / "review"
MANIFEST_PATH = OUTPUT_DIR / "base_manifest.json"


def rgba(color: str, alpha: int = 255) -> tuple[int, int, int, int]:
    value = color.lstrip("#")
    return (
        int(value[0:2], 16), int(value[2:4], 16),
        int(value[4:6], 16), alpha,
    )

PALETTE_HEX = (
    "#07080B", "#12151B", "#252A31", "#59606B", "#E6E0D2",
    "#E3A447", "#9E3036", "#D95149", "#41B7AE", "#7450A6",
)
INK, DEEP, STONE, NEUTRAL, BONE, AMBER, BLOOD, WARNING, TEAL, PURPLE = PALETTE_HEX
TRANSPARENT = (0, 0, 0, 0)

SOURCE_FILES = {
    "base_hub": ROOT / "art" / "early" / "base" / "base_hub.png",
    "contract_desk": ROOT / "art" / "early" / "base" / "stations" / "contract_desk.png",
    "destiny_forge": ROOT / "art" / "early" / "base" / "stations" / "destiny_forge.png",
    "equipment_rune_desk": ROOT / "art" / "early" / "base" / "stations" / "equipment_rune_desk.png",
    "training_report": ROOT / "art" / "early" / "base" / "stations" / "training_report.png",
}
SOURCE_SHA256 = {
    "base_hub": "db6bb06c38ff81b60004273bd51bcfb8c06aa7cded0d1bf42f449f16fb84b0cc",
    "contract_desk": "cf4a667ca32003bd7e4baff72d047580c1ccd0d0b8e7ec8d2d1dc3731cabedcf",
    "destiny_forge": "38421b3740b3483fcd2799c03a19533e07618ca90566ed049d6224e4284b8470",
    "equipment_rune_desk": "4ccf2d6272071679e070c85761d4950941df1030dc8d9584fc45ab8d90242525",
    "training_report": "ef67f722240b495ba37186b607187d381af26422774878e596e60298f4d1d8b1",
}

HOTSPOTS = {
    "contract": {
        "rect": (520, 116, 240, 128), "anchor": (640, 205), "radius": 72,
        "body": (138, 31, 182, 53),
    },
    "loadout": {
        "rect": (250, 174, 224, 136), "anchor": (392, 274), "radius": 72,
        "body": (77, 47, 102, 69),
    },
    "forge": {
        "rect": (806, 174, 224, 136), "anchor": (888, 274), "radius": 72,
        "body": (218, 47, 248, 69),
    },
    "proxy": {
        "rect": (238, 378, 220, 150), "anchor": (405, 483), "radius": 68,
        "body": (71, 99, 102, 124),
    },
    "immortality": {
        "rect": (520, 504, 240, 142), "anchor": (640, 566), "radius": 72,
        "body": (139, 128, 181, 153),
    },
    "training": {
        "rect": (822, 386, 224, 150), "anchor": (875, 491), "radius": 72,
        "body": (218, 99, 252, 125),
    },
}

STATION_OUTPUTS = (
    "contract_desk.png", "equipment_rune_desk.png",
    "destiny_forge.png", "training_report.png",
)
STATION_LABELS = {
    "contract_desk.png": "CONTRACT",
    "equipment_rune_desk.png": "EQUIPMENT",
    "destiny_forge.png": "FORGE",
    "training_report.png": "TRAINING",
}
STATION_FILENAMES = {
    "contract": "contract_desk.png",
    "loadout": "equipment_rune_desk.png",
    "forge": "destiny_forge.png",
    "training": "training_report.png",
}

CENTRAL_OPEN_AREA = (416, 234, 449, 253)
HERO_SAFE_AREA = (592, 362, 96, 96)
UI_SAFE_ZONES = {"top": (0, 0, 1280, 110), "bottom": (0, 650, 1280, 70)}
GROUND_RGB = {rgba(DEEP)[:3], rgba(STONE)[:3]}
DARK_RGB = {rgba(INK)[:3], rgba(DEEP)[:3]}
NEUTRAL_GROUND_RGB = {rgba(INK)[:3], rgba(DEEP)[:3], rgba(STONE)[:3]}
ACCENT_RGB = {rgba(color)[:3] for color in (BONE, AMBER, BLOOD, WARNING, TEAL, PURPLE)}
PALETTE_RGB = {rgba(color)[:3] for color in PALETTE_HEX}
EDGE_DENSITY_FLOOR = 0.050


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(65536), b""):
            digest.update(chunk)
    return digest.hexdigest()


def save_png(image: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, format="PNG", optimize=False, compress_level=9)


def font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    path = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf"
    try:
        return ImageFont.truetype(path, size)
    except OSError:
        return ImageFont.load_default()


def rect_box(rect: tuple[int, int, int, int]) -> tuple[int, int, int, int]:
    x, y, width, height = rect
    return x, y, x + width - 1, y + height - 1


def logical_rect(output_rect: tuple[int, int, int, int]) -> tuple[int, int, int, int]:
    x, y, width, height = output_rect
    return x // 4, y // 4, (x + width - 1) // 4, (y + height - 1) // 4


def logical_strip(output_rect: tuple[int, int, int, int]) -> tuple[int, int, int, int]:
    x, y, width, height = output_rect
    return x // 4, y // 4, (x + width - 1) // 4, (y + height - 1) // 4


def marker_strip(record: dict[str, tuple[int, ...]]) -> tuple[int, int, int, int]:
    x, y, width, height = record["rect"]
    return x, y + height - 28, width, 28


def rectangle(draw: ImageDraw.ImageDraw, box: tuple[int, int, int, int], color: str, width: int = 1) -> None:
    draw.rectangle(box, fill=None, outline=rgba(color), width=width)


def points(draw: ImageDraw.ImageDraw, coords: Iterable[tuple[int, int]], color: str) -> None:
    draw.point(list(coords), fill=rgba(color))


def edge_density(image: Image.Image) -> float:
    pixels = image.load()
    transitions = 0
    for y in range(image.height):
        for x in range(image.width):
            value = pixels[x, y]
            if x + 1 < image.width and pixels[x + 1, y] != value:
                transitions += 1
            if y + 1 < image.height and pixels[x, y + 1] != value:
                transitions += 1
    return transitions / (image.width * image.height)


def bright_accent_ratio(image: Image.Image) -> float:
    pixels = image.get_flattened_data()
    return sum(value[:3] in ACCENT_RGB for value in pixels) / (image.width * image.height)


def draw_hub() -> Image.Image:
    """Draw a 320x180 logical canvas, then nearest-upscale to 1280x720."""
    canvas = Image.new("RGB", (320, 180), rgba(DEEP)[:3])
    draw = ImageDraw.Draw(canvas)

    draw.rectangle((0, 0, 319, 27), fill=rgba(INK))
    draw.rectangle((0, 6, 319, 8), fill=rgba(DEEP))
    draw.rectangle((0, 17, 319, 19), fill=rgba(DEEP))
    draw.rectangle((0, 162, 319, 179), fill=rgba(INK))
    draw.rectangle((0, 167, 319, 169), fill=rgba(DEEP))

    # Broad stepped wings frame the plaza without filling its center.
    wings = (
        ((50, 29), (103, 29), (103, 78), (97, 78), (97, 81), (50, 81)),
        ((217, 29), (270, 29), (270, 81), (223, 81), (223, 78), (217, 78)),
        ((50, 87), (97, 87), (97, 90), (103, 90), (103, 151), (50, 151)),
        ((217, 90), (223, 90), (223, 87), (270, 87), (270, 151), (217, 151)),
    )
    for polygon in wings:
        draw.polygon(polygon, fill=rgba(STONE))
        draw.line((*polygon, polygon[0]), fill=rgba(NEUTRAL), width=1)
    for x0, y0, x1, y1 in (
        (54, 33, 99, 76), (221, 33, 266, 76),
        (54, 92, 99, 147), (221, 92, 266, 147),
    ):
        draw.rectangle((x0, y0, x1, y1), fill=rgba(DEEP))
        draw.rectangle((x0 + 3, y0 + 4, x1 - 3, y0 + 7), fill=rgba(STONE))
        draw.rectangle((x0 + 7, y0 + 5, x1 - 7, y0 + 6), fill=rgba(INK))
        draw.rectangle((x0 + 3, y1 - 9, x1 - 3, y1 - 6), fill=rgba(STONE))
        draw.rectangle((x0 + 7, y1 - 8, x1 - 7, y1 - 7), fill=rgba(INK))

    # Two-level galleries back the north and south stations.
    draw.polygon(
        [(104, 28), (216, 28), (216, 42), (210, 42), (210, 57),
         (110, 57), (110, 42), (104, 42)],
        fill=rgba(STONE),
    )
    draw.rectangle((108, 31, 212, 38), fill=rgba(DEEP))
    draw.rectangle((114, 43, 206, 54), fill=rgba(DEEP))
    draw.polygon(
        [(104, 124), (110, 124), (110, 128), (210, 128), (210, 124),
         (216, 124), (216, 161), (104, 161)],
        fill=rgba(STONE),
    )
    draw.rectangle((108, 132, 212, 157), fill=rgba(DEEP))
    draw.rectangle((116, 156, 204, 159), fill=rgba(INK))

    # Four coarse utility trunks connect the station wings.
    for box, inset in (
        ((51, 70, 269, 78), (55, 73, 265, 75)),
        ((51, 108, 269, 116), (55, 111, 265, 113)),
        ((156, 52, 164, 89), (159, 55, 161, 86)),
        ((156, 116, 164, 132), (159, 118, 161, 130)),
    ):
        draw.rectangle(box, fill=rgba(STONE))
        draw.rectangle(inset, fill=rgba(DEEP))
    for x in (68, 96, 124, 196, 224, 252):
        draw.rectangle((x, 70, x + 3, 78), fill=rgba(INK))
        draw.rectangle((x, 108, x + 3, 116), fill=rgba(INK))
    for x0, x1, y0, y1 in (
        (93, 108, 63, 73), (212, 227, 63, 73),
        (93, 108, 109, 122), (212, 227, 109, 122),
    ):
        draw.rectangle((x0, y0, x1, y1), fill=rgba(STONE))
        draw.rectangle((x0 + 3, y0 + 2, x1 - 3, y1 - 2), fill=rgba(DEEP))

    shelves = (
        (7, 34, 52, 78), (263, 36, 309, 80), (7, 93, 50, 137),
        (265, 95, 309, 139),
    )
    for x0, y0, x1, y1 in shelves:
        draw.rectangle((x0, y0, x1, y1), fill=rgba(STONE))
        rectangle(draw, (x0, y0, x1, y1), NEUTRAL)
        for y in range(y0 + 7, y1 - 5, 12):
            draw.rectangle((x0 + 3, y, x1 - 3, y + 4), fill=rgba(DEEP))
            draw.rectangle((x0 + 8, y + 1, x1 - 8, y + 2), fill=rgba(INK))
            draw.rectangle((x0 + 4, y + 1, x0 + 6, y + 3), fill=rgba(NEUTRAL))
            draw.rectangle((x1 - 6, y + 1, x1 - 4, y + 3), fill=rgba(NEUTRAL))
        spine_x = x1 - 6 if x0 < 100 else x0 + 4
        draw.rectangle((spine_x, y0 + 4, spine_x + 2, y1 - 4), fill=rgba(STONE))
        for x, y in ((x0 + 4, y0 + 4), (x1 - 6, y0 + 4), (x0 + 4, y1 - 7), (x1 - 6, y1 - 7)):
            draw.rectangle((x, y, x + 2, y + 2), fill=rgba(NEUTRAL))

    path_boxes = (
        (97, 68, 156, 76), (164, 68, 218, 76),
        (100, 111, 156, 119), (164, 111, 222, 119),
        (156, 55, 164, 119), (156, 102, 164, 139),
    )
    for box in path_boxes:
        draw.rectangle(box, fill=rgba(STONE))
        rectangle(draw, box, DEEP)
    for x in range(100, 154, 12):
        draw.rectangle((x, 71, x + 1, 73), fill=rgba(DEEP))
    for x in range(168, 216, 12):
        draw.rectangle((x, 71, x + 1, 73), fill=rgba(DEEP))
    for y in range(59, 101, 12):
        draw.rectangle((158, y, 159, y + 1), fill=rgba(DEEP))

    draw.polygon(
        [(139, 52), (139, 39), (143, 34), (148, 32), (160, 31),
         (172, 32), (177, 34), (181, 39), (181, 52)],
        fill=rgba(STONE), outline=rgba(BONE),
    )
    draw.rectangle((144, 42, 176, 52), fill=rgba(INK))
    draw.rectangle((148, 43, 172, 52), fill=rgba(DEEP))
    draw.line((149, 44, 171, 44), fill=rgba(STONE), width=1)
    draw.line((149, 48, 171, 48), fill=rgba(STONE), width=1)
    points(draw, ((149, 45), (171, 45), (149, 49), (171, 49)), NEUTRAL)
    draw.rectangle((158, 35, 161, 38), fill=rgba(AMBER))

    draw.rectangle((77, 61, 102, 69), fill=rgba(STONE))
    rectangle(draw, (77, 61, 102, 69), NEUTRAL)
    draw.rectangle((81, 63, 98, 67), fill=rgba(DEEP))
    draw.line((84, 49, 84, 60), fill=rgba(AMBER), width=1)
    draw.arc((80, 47, 88, 61), 270, 90, fill=rgba(AMBER), width=1)
    draw.line((82, 49, 86, 49), fill=rgba(BONE), width=1)
    draw.line((82, 59, 86, 59), fill=rgba(BONE), width=1)
    draw.rectangle((91, 48, 96, 60), fill=rgba(DEEP))
    rectangle(draw, (91, 48, 96, 60), BONE)
    for x in (92, 94):
        draw.line((x, 50, x, 58), fill=rgba(AMBER), width=1)
    points(draw, ((83, 53), (83, 56), (92, 63), (95, 63), (98, 65)), BONE)

    draw.rectangle((218, 52, 248, 69), fill=rgba(STONE))
    rectangle(draw, (218, 52, 248, 69), NEUTRAL)
    draw.rectangle((221, 61, 245, 67), fill=rgba(INK))
    for x0 in (222, 231, 240):
        draw.rectangle((x0, 53, x0 + 5, 59), fill=rgba(DEEP))
        rectangle(draw, (x0, 53, x0 + 5, 59), BONE)
        points(draw, ((x0 + 2, 55), (x0 + 2, 57)), AMBER)
    draw.rectangle((223, 63, 227, 66), fill=rgba(BLOOD))
    draw.rectangle((239, 63, 243, 66), fill=rgba(BLOOD))

    draw.polygon(
        [(71, 123), (71, 107), (77, 101), (86, 99), (95, 101), (101, 107), (101, 123)],
        fill=rgba(STONE), outline=rgba(NEUTRAL),
    )
    draw.polygon([(75, 120), (75, 109), (79, 104), (93, 104), (97, 109), (97, 120)], fill=rgba(INK))
    draw.line((75, 110, 97, 110), fill=rgba(DEEP), width=1)
    draw.line((75, 116, 97, 116), fill=rgba(DEEP), width=1)
    draw.rectangle((85, 103, 88, 107), fill=rgba(TEAL))
    points(draw, ((77, 122), (81, 122), (91, 122), (95, 122), (85, 116)), TEAL)

    draw.rectangle((139, 128, 181, 153), fill=rgba(INK))
    rectangle(draw, (139, 128, 181, 153), STONE)
    draw.rectangle((144, 132, 176, 149), fill=rgba(DEEP))
    draw.line((160, 132, 160, 149), fill=rgba(BLOOD), width=2)
    draw.line((144, 140, 176, 140), fill=rgba(BLOOD), width=1)
    draw.rectangle((157, 137, 163, 143), fill=rgba(BLOOD))
    draw.rectangle((158, 138, 162, 142), fill=rgba(WARNING))
    points(draw, ((146, 134), (174, 134), (146, 147), (174, 147)), BONE)

    draw.rectangle((218, 100, 252, 125), fill=rgba(STONE))
    rectangle(draw, (218, 100, 252, 125), NEUTRAL)
    draw.rectangle((222, 116, 248, 123), fill=rgba(INK))
    draw.rectangle((224, 118, 246, 121), fill=rgba(DEEP))
    draw.polygon([(229, 103), (241, 103), (238, 114), (232, 114)], fill=rgba(DEEP))
    rectangle(draw, (229, 103, 241, 114), BONE)
    draw.rectangle((233, 106, 237, 111), fill=rgba(BLOOD))
    draw.rectangle((235, 108, 236, 109), fill=rgba(WARNING))
    draw.line((225, 119, 244, 119), fill=rgba(BONE), width=1)
    draw.line((225, 121, 240, 121), fill=rgba(NEUTRAL), width=1)

    protect_ground(canvas, CENTRAL_OPEN_AREA)
    protect_ground(canvas, HERO_SAFE_AREA)
    hero_box = logical_rect(HERO_SAFE_AREA)
    draw.rectangle(hero_box, fill=rgba(DEEP))

    for record in HOTSPOTS.values():
        rect = record["rect"]
        marker = (rect[0], rect[1] + rect[3] - 28, rect[2], 28)
        box = logical_strip(marker)
        x0, y0, x1, y1 = box
        middle = (x0 + x1) // 2
        draw.rectangle(box, fill=rgba(DEEP))
        draw.rectangle((x0 + 3, y0 + 2, middle - 3, y1 - 1), fill=rgba(INK))
        draw.rectangle((middle + 3, y0 + 2, x1 - 3, y1 - 1), fill=rgba(INK))

    return canvas.resize((1280, 720), resample=Image.Resampling.NEAREST)


def protect_ground(canvas: Image.Image, output_rect: tuple[int, int, int, int]) -> None:
    """Remove non-ground construction from an exact protected output region."""
    x0, y0, x1, y1 = logical_rect(output_rect)
    deep = rgba(DEEP)[:3]
    stone = rgba(STONE)[:3]
    allowed = {deep, stone}
    source = canvas.copy()
    source_draw = ImageDraw.Draw(source)
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            if canvas.getpixel((x, y)) not in allowed:
                replacement = None
                for distance in range(1, 8):
                    candidates = (
                        (x - distance, y), (x + distance, y),
                        (x, y - distance), (x, y + distance),
                    )
                    for candidate in candidates:
                        if 0 <= candidate[0] < 320 and 0 <= candidate[1] < 180:
                            value = canvas.getpixel(candidate)
                            if value in allowed:
                                replacement = value
                                break
                    if replacement is not None:
                        break
                source_draw.point((x, y), fill=replacement if replacement is not None else deep)
    canvas.paste(source.crop((x0, y0, x1 + 1, y1 + 1)), (x0, y0))


def station_canvas() -> Image.Image:
    return Image.new("RGBA", (32, 32), TRANSPARENT)


def draw_contract_desk() -> Image.Image:
    image = station_canvas()
    draw = ImageDraw.Draw(image)
    draw.polygon(
        [(8, 26), (8, 15), (11, 11), (16, 10), (21, 11), (24, 15), (24, 26)],
        fill=rgba(STONE), outline=rgba(BONE),
    )
    draw.rectangle((11, 17, 21, 26), fill=rgba(INK))
    draw.rectangle((13, 18, 19, 26), fill=rgba(DEEP))
    draw.line((14, 20, 18, 20), fill=rgba(STONE), width=1)
    draw.line((14, 23, 18, 23), fill=rgba(STONE), width=1)
    draw.rectangle((15, 12, 17, 14), fill=rgba(AMBER))
    points(draw, ((9, 24), (23, 24), (14, 19), (18, 19)), BONE)
    return image


def draw_equipment_rune_desk() -> Image.Image:
    image = station_canvas()
    draw = ImageDraw.Draw(image)
    draw.rectangle((5, 23, 27, 28), fill=rgba(STONE))
    rectangle(draw, (5, 23, 27, 28), NEUTRAL)
    draw.rectangle((8, 25, 24, 27), fill=rgba(DEEP))
    draw.line((11, 8, 11, 23), fill=rgba(AMBER), width=1)
    draw.arc((8, 6, 14, 22), 270, 90, fill=rgba(AMBER), width=1)
    draw.line((9, 8, 13, 8), fill=rgba(BONE), width=1)
    draw.line((9, 21, 13, 21), fill=rgba(BONE), width=1)
    draw.rectangle((18, 7, 23, 22), fill=rgba(DEEP))
    rectangle(draw, (18, 7, 23, 22), BONE)
    for x in (19, 21):
        draw.line((x, 9, x, 20), fill=rgba(AMBER), width=1)
    points(draw, ((10, 13), (10, 17), (19, 25), (22, 25)), BONE)
    return image


def draw_destiny_forge() -> Image.Image:
    image = station_canvas()
    draw = ImageDraw.Draw(image)
    draw.rectangle((5, 17, 27, 27), fill=rgba(STONE))
    rectangle(draw, (5, 17, 27, 27), NEUTRAL)
    draw.rectangle((7, 23, 25, 26), fill=rgba(INK))
    for x0 in (7, 14, 21):
        draw.rectangle((x0, 8, x0 + 4, 14), fill=rgba(DEEP))
        rectangle(draw, (x0, 8, x0 + 4, 14), BONE)
        points(draw, ((x0 + 2, 10), (x0 + 2, 12)), AMBER)
    draw.rectangle((8, 24, 11, 25), fill=rgba(BLOOD))
    draw.rectangle((21, 24, 24, 25), fill=rgba(BLOOD))
    points(draw, ((6, 19), (26, 19), (12, 24), (17, 24)), BONE)
    return image


def draw_training_report() -> Image.Image:
    image = station_canvas()
    draw = ImageDraw.Draw(image)
    draw.rectangle((5, 5, 27, 27), fill=rgba(STONE))
    rectangle(draw, (5, 5, 27, 27), NEUTRAL)
    draw.rectangle((8, 21, 24, 25), fill=rgba(INK))
    draw.rectangle((10, 22, 22, 24), fill=rgba(DEEP))
    draw.polygon([(12, 8), (20, 8), (18, 18), (14, 18)], fill=rgba(DEEP))
    rectangle(draw, (12, 8, 20, 18), BONE)
    draw.rectangle((14, 10, 18, 16), fill=rgba(BLOOD))
    draw.rectangle((15, 12, 17, 14), fill=rgba(WARNING))
    draw.line((11, 23, 21, 23), fill=rgba(BONE), width=1)
    return image


def upscale_station(sprite: Image.Image) -> Image.Image:
    box = sprite.getbbox()
    if box is None:
        raise AssertionError("cannot center an empty station")
    width = box[2] - box[0]
    height = box[3] - box[1]
    centered = station_canvas()
    centered.paste(sprite.crop(box), ((32 - width) // 2, (32 - height) // 2))
    return centered.resize((128, 128), resample=Image.Resampling.NEAREST)


def draw_stations_board_1280() -> Image.Image:
    canvas = Image.new("RGB", (1280, 720), rgba(INK)[:3])
    draw = ImageDraw.Draw(canvas)
    sprites = {
        "contract_desk.png": draw_contract_desk(),
        "equipment_rune_desk.png": draw_equipment_rune_desk(),
        "destiny_forge.png": draw_destiny_forge(),
        "training_report.png": draw_training_report(),
    }
    draw.text((52, 36), "BASE STATION GRAMMAR REVIEW", font=font(30), fill=rgba(BONE))
    for index, filename in enumerate(STATION_OUTPUTS):
        x0 = index * 320
        draw.rectangle((x0 + 22, 92, x0 + 297, 622), fill=rgba(DEEP))
        rectangle(draw, (x0 + 22, 92, x0 + 297, 622), NEUTRAL, width=2)
        sprite = upscale_station(sprites[filename]).convert("RGB")
        canvas.paste(sprite, (x0 + 96, 176))
        label = STATION_LABELS[filename]
        label_box = draw.textbbox((0, 0), label, font=font(22))
        draw.text((x0 + 160 - (label_box[2] - label_box[0]) // 2, 394), label, font=font(22), fill=rgba(AMBER))
        draw.text((x0 + 38, 454), "32x32 LOGICAL", font=font(17), fill=rgba(NEUTRAL))
        draw.text((x0 + 38, 482), "NEAREST 4X", font=font(17), fill=rgba(NEUTRAL))
        draw.text((x0 + 38, 510), "PALETTE LOCKED", font=font(17), fill=rgba(NEUTRAL))
    return canvas


def draw_hotspot_overlay(hub: Image.Image) -> Image.Image:
    canvas = hub.copy()
    draw = ImageDraw.Draw(canvas)
    colors = {
        "contract": BONE, "loadout": AMBER, "forge": WARNING,
        "proxy": TEAL, "immortality": BLOOD, "training": NEUTRAL,
    }
    draw.rectangle((12, 18, 1267, 87), outline=rgba(BONE), width=2)
    draw.text((24, 30), "TOP UI SAFE", font=font(18), fill=rgba(BONE))
    draw.rectangle((12, 632, 1267, 708), outline=rgba(BONE), width=2)
    draw.text((24, 644), "BOTTOM UI SAFE", font=font(18), fill=rgba(BONE))
    draw.rectangle((416, 234, 864, 486), outline=rgba(NEUTRAL), width=2)
    draw.text((424, 240), "CENTRAL OPEN", font=font(16), fill=rgba(NEUTRAL))
    draw.rectangle((592, 362, 688, 458), outline=rgba(STONE), width=2)
    for name, record in HOTSPOTS.items():
        color = colors[name]
        draw.rectangle(rect_box(record["rect"]), outline=rgba(color), width=2)
        draw.rectangle(rect_box(marker_strip(record)), outline=rgba(color), width=1)
        ax, ay = record["anchor"]
        draw.line((ax - 10, ay, ax + 10, ay), fill=rgba(color), width=2)
        draw.line((ax, ay - 10, ax, ay + 10), fill=rgba(color), width=2)
        draw.ellipse((ax - 4, ay - 4, ax + 4, ay + 4), outline=rgba(color), width=2)
        draw.text((record["rect"][0] + 8, record["rect"][1] + 6), name.upper(), font=font(16), fill=rgba(color))
    return canvas


def check(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def image_rgb_values(image: Image.Image) -> set[tuple[int, int, int]]:
    return {value[:3] for value in image.get_flattened_data()}


def region_pixels(image: Image.Image, rect: tuple[int, int, int, int]) -> Iterable[tuple[int, int, tuple[int, int, int]]]:
    x, y, width, height = rect
    for yy in range(y, y + height):
        for xx in range(x, x + width):
            yield xx, yy, image.getpixel((xx, yy))[:3]


def validate_hub(image: Image.Image) -> None:
    check(image.size == (1280, 720), "base_hub dimensions")
    check(image.mode == "RGB", "base_hub mode")
    check(image_rgb_values(image) <= PALETTE_RGB, "base_hub palette")
    check(rgba(PURPLE)[:3] not in image_rgb_values(image), "base_hub contains purple")
    check(edge_density(image) >= EDGE_DENSITY_FLOOR, "base_hub edge density is too sparse")
    central_values = {value for _, _, value in region_pixels(image, CENTRAL_OPEN_AREA)}
    check(central_values <= NEUTRAL_GROUND_RGB, "central open area has non-neutral pixels")
    hero_values = {value for _, _, value in region_pixels(image, HERO_SAFE_AREA)}
    check(hero_values <= GROUND_RGB, "hero start safe area is not ground-only")

    for name, record in HOTSPOTS.items():
        pixels = list(region_pixels(image, record["rect"]))
        check(any(value not in DARK_RGB for _, _, value in pixels), f"{name} has no non-dark pixels")
        highlights = [(x, y) for x, y, value in pixels if value in ACCENT_RGB]
        check(highlights, f"{name} has no highlight pixels")
        bx0, by0, bx1, by1 = record["body"]
        body_output = (bx0 * 4, by0 * 4, (bx1 - bx0 + 1) * 4, (by1 - by0 + 1) * 4)
        check(
            all(x >= body_output[0] and x < body_output[0] + body_output[2] and
                y >= body_output[1] and y < body_output[1] + body_output[3] for x, y in highlights),
            f"{name} highlights escape body safe range",
        )
        marker_values = {value for _, _, value in region_pixels(image, marker_strip(record))}
        check(marker_values <= DARK_RGB, f"{name} marker strip is not dark")


def validate_station(image: Image.Image) -> None:
    check(image.size == (128, 128), "station dimensions")
    check(image.mode == "RGBA", "station mode")
    pixels = list(image.get_flattened_data())
    check({pixel[3] for pixel in pixels} <= {0, 255}, "station alpha is not binary")
    check({pixel[:3] for pixel in pixels if pixel[3] == 255} <= PALETTE_RGB, "station palette")
    box = image.getbbox()
    check(box is not None, "station is empty")
    x0, y0, x1, y1 = box
    check(x0 >= 12 and y0 >= 12 and x1 <= 115 and y1 <= 115, "station transparent padding")
    center_x = (x0 + x1 + 1) / 2
    center_y = (y0 + y1 + 1) / 2
    check(abs(center_x - 64) <= 4 and abs(center_y - 64) <= 4, "station is not centered")


def validate_review(hub: Image.Image, files: dict[str, Image.Image]) -> None:
    check(files["base_hub_100.png"].tobytes() == hub.tobytes(), "base_hub_100 is not the production image")
    expected_25 = hub.resize((320, 180), resample=Image.Resampling.NEAREST)
    check(files["base_hub_25.png"].tobytes() == expected_25.tobytes(), "base_hub_25 is not nearest")
    check(files["base_hub_25_gray.png"].tobytes() == expected_25.convert("L").tobytes(), "base_hub_25_gray mismatch")
    expected_stations_25 = files["base_stations_100.png"].resize((320, 180), resample=Image.Resampling.NEAREST)
    check(files["base_stations_25.png"].tobytes() == expected_stations_25.tobytes(), "base_stations_25 is not nearest")
    check(files["base_stations_25_gray.png"].tobytes() == expected_stations_25.convert("L").tobytes(), "base_stations gray mismatch")


def validate_manifest(manifest: dict[str, object]) -> None:
    production = manifest["production"]
    hub_record = production["base_hub"]
    check(Path(hub_record["path"]).name == "base_hub.png", "manifest hub path")
    check(hub_record["sha256"] == sha256(OUTPUT_DIR / "base_hub.png"), "hub hash")
    for filename, record in production["stations"].items():
        check(record["sha256"] == sha256(OUTPUT_DIR / filename), f"station hash: {filename}")
    for filename, record in manifest["review_images"].items():
        check(record["sha256"] == sha256(REVIEW_DIR / filename), f"review hash: {filename}")
    check(manifest["source_sha256"] == SOURCE_SHA256, "source hash record")


def file_record(path: Path, kind: str, alpha: str) -> dict[str, object]:
    image = Image.open(path)
    return {
        "path": str(path.relative_to(ROOT)), "kind": kind,
        "size": list(image.size), "mode": image.mode,
        "alpha": alpha, "sha256": sha256(path),
    }


def generate() -> None:
    for name, path in SOURCE_FILES.items():
        check(path.exists(), f"missing source: {path}")
        check(sha256(path) == SOURCE_SHA256[name], f"source SHA mismatch: {name}")

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    REVIEW_DIR.mkdir(parents=True, exist_ok=True)

    hub = draw_hub()
    save_png(hub, OUTPUT_DIR / "base_hub.png")
    stations = {
        "contract_desk.png": upscale_station(draw_contract_desk()),
        "equipment_rune_desk.png": upscale_station(draw_equipment_rune_desk()),
        "destiny_forge.png": upscale_station(draw_destiny_forge()),
        "training_report.png": upscale_station(draw_training_report()),
    }
    for filename, image in stations.items():
        save_png(image, OUTPUT_DIR / filename)

    hub_25 = hub.resize((320, 180), resample=Image.Resampling.NEAREST)
    stations_100 = draw_stations_board_1280()
    stations_25 = stations_100.resize((320, 180), resample=Image.Resampling.NEAREST)
    review = {
        "base_hub_100.png": hub.copy(),
        "base_hub_25.png": hub_25,
        "base_hub_25_gray.png": hub_25.convert("L"),
        "base_stations_100.png": stations_100,
        "base_stations_25.png": stations_25,
        "base_stations_25_gray.png": stations_25.convert("L"),
        "base_hotspots_100.png": draw_hotspot_overlay(hub),
    }
    for filename, image in review.items():
        save_png(image, REVIEW_DIR / filename)

    validate_hub(hub)
    for image in stations.values():
        validate_station(image)
    opened_review = {name: Image.open(REVIEW_DIR / name) for name in review}
    opened_hub = Image.open(OUTPUT_DIR / "base_hub.png")
    validate_review(opened_hub, opened_review)

    manifest = {
        "schema_version": 2,
        "package": "base_v03_candidate",
        "runtime_switched": False,
        "palette": {
            "colors": list(PALETTE_HEX), "alpha": "production stations use 0/255 only",
            "base_hub_forbidden_colors": [PURPLE],
        },
        "production": {
            "base_hub": file_record(OUTPUT_DIR / "base_hub.png", "base_hub", "opaque"),
            "stations": {
                name: file_record(OUTPUT_DIR / name, "station", "binary_true_transparency")
                for name in STATION_OUTPUTS
            },
        },
        "review_images": {
            name: file_record(REVIEW_DIR / name, "review", "opaque" if "gray" not in name else "grayscale")
            for name in review
        },
        "hotspots": {
            name: {
                "rect": record["rect"], "anchor": list(record["anchor"]),
                "radius": record["radius"], "marker_strip": list(marker_strip(record)),
                "station_asset": STATION_FILENAMES.get(name),
            }
            for name, record in HOTSPOTS.items()
        },
        "ui_safe_zones": {name: list(rect) for name, rect in UI_SAFE_ZONES.items()},
        "central_open_area": list(CENTRAL_OPEN_AREA),
        "hero_start_safe_area": list(HERO_SAFE_AREA),
        "generation": {
            "script": str((ROOT / "art" / "early" / "tools" / "generate_base_v03_assets.py").relative_to(ROOT)),
            "deterministic": True, "logical_canvas": [320, 180], "upscale": "4x NEAREST",
            "station_logical_canvas": [32, 32],
        },
        "visual_statistics": {
            "edge_density": round(edge_density(hub), 12),
            "minimum_edge_density": EDGE_DENSITY_FLOOR,
            "bright_accent_ratio": round(bright_accent_ratio(hub), 12),
            "source_old_edge_density": round(
                edge_density(Image.open(SOURCE_FILES["base_hub"]).convert("RGB")), 12
            ),
            "source_old_bright_accent_ratio": round(
                bright_accent_ratio(Image.open(SOURCE_FILES["base_hub"]).convert("RGB")), 12
            ),
        },
        "source_sha256": SOURCE_SHA256,
    }
    MANIFEST_PATH.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    validate_manifest(manifest)
    print("BASE_V03_ART_VALIDATION_PASS")


if __name__ == "__main__":
    generate()
