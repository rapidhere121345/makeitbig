#!/usr/bin/env python3
"""Generate the versioned P0 enemy atlas and deterministic art review boards."""

from __future__ import annotations

import hashlib
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, ImageOps


ROOT = Path(__file__).resolve().parents[3]
ART_DIR = ROOT / "art" / "early"
BASE_ATLAS_PATH = ART_DIR / "actors_atlas.png"
OUTPUT_ATLAS_PATH = ART_DIR / "actors_atlas_v0.2.png"
REVIEW_DIR = ART_DIR / "review"

INK = "#07080B"
DEEP = "#12151B"
GROUND = "#252A31"
NEUTRAL = "#59606B"
BONE = "#E6E0D2"
AMBER = "#E3A447"
BLOOD = "#9E3036"
WARNING = "#D95149"
TEAL = "#41B7AE"
PURPLE = "#7450A6"
TRANSPARENT = (0, 0, 0, 0)


def rgba(hex_color: str, alpha: int = 255) -> tuple[int, int, int, int]:
    value = hex_color.lstrip("#")
    return (
        int(value[0:2], 16),
        int(value[2:4], 16),
        int(value[4:6], 16),
        alpha,
    )


def font(size: int) -> ImageFont.ImageFont:
    path = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf"
    try:
        return ImageFont.truetype(path, size)
    except OSError:
        return ImageFont.load_default()


def new_cell() -> Image.Image:
    return Image.new("RGBA", (32, 32), TRANSPARENT)


def draw_charger(attack: bool) -> Image.Image:
    image = new_cell()
    draw = ImageDraw.Draw(image)

    if not attack:
        outline = [
            (2, 23), (4, 20), (6, 19), (7, 16), (11, 13), (17, 12),
            (21, 13), (24, 15), (26, 16), (29, 17), (29, 23),
            (27, 23), (25, 26), (22, 26), (21, 28), (17, 28),
            (16, 25), (11, 25), (9, 28), (5, 28), (4, 26), (2, 26),
        ]
        inner = [
            (5, 22), (7, 18), (11, 15), (17, 14), (21, 15),
            (24, 17), (26, 19), (26, 22), (23, 24), (8, 24),
        ]
        draw.polygon(outline, fill=INK)
        draw.polygon(inner, fill=DEEP)
        draw.polygon([(9, 17), (13, 14), (16, 14), (16, 18), (12, 20)], fill=NEUTRAL)
        draw.polygon([(17, 14), (21, 15), (23, 18), (19, 18)], fill=NEUTRAL)
        draw.rectangle((7, 22, 12, 24), fill=NEUTRAL)
        draw.polygon([(25, 17), (29, 18), (29, 22), (26, 23), (27, 20)], fill=BLOOD)
        draw.rectangle((5, 26, 8, 28), fill=INK)
        draw.rectangle((18, 25, 21, 28), fill=INK)
    else:
        outline = [
            (2, 22), (4, 19), (8, 18), (10, 16), (17, 15),
            (22, 16), (25, 18), (29, 18), (29, 22), (26, 23),
            (24, 25), (21, 25), (20, 28), (16, 28), (15, 25),
            (10, 25), (8, 28), (4, 28), (5, 25), (2, 25),
        ]
        inner = [
            (5, 22), (8, 20), (11, 18), (17, 17), (21, 18),
            (24, 20), (25, 22), (22, 24), (8, 24),
        ]
        draw.polygon(outline, fill=INK)
        draw.polygon(inner, fill=DEEP)
        draw.polygon([(8, 20), (12, 17), (17, 17), (16, 21), (11, 22)], fill=NEUTRAL)
        draw.polygon([(18, 17), (22, 18), (24, 20), (20, 21)], fill=NEUTRAL)
        draw.polygon([(24, 19), (29, 18), (29, 22), (25, 23), (27, 21)], fill=BLOOD)
        draw.rectangle((5, 25, 8, 28), fill=INK)
        draw.rectangle((16, 25, 19, 28), fill=INK)

    return image


def draw_fan_shooter(attack: bool) -> Image.Image:
    image = new_cell()
    draw = ImageDraw.Draw(image)

    if not attack:
        outline = [
            (15, 2), (22, 9), (22, 14), (18, 18), (18, 23),
            (20, 26), (22, 29), (18, 29), (16, 25), (15, 25),
            (13, 29), (9, 29), (11, 26), (13, 23), (13, 18),
            (9, 14), (9, 9),
        ]
        draw.polygon(outline, fill=INK)
        draw.polygon([(15, 4), (20, 9), (20, 13), (17, 16), (15, 15)], fill=NEUTRAL)
        draw.polygon([(15, 4), (15, 15), (11, 13), (11, 9)], fill=DEEP)
        draw.polygon([(15, 8), (18, 11), (15, 15), (12, 11)], fill=BLOOD)
        draw.rectangle((14, 17, 17, 24), fill=DEEP)
        draw.rectangle((12, 19, 13, 23), fill=NEUTRAL)
        draw.rectangle((18, 19, 19, 23), fill=NEUTRAL)
        draw.polygon([(12, 25), (14, 25), (13, 29), (9, 29)], fill=INK)
        draw.polygon([(17, 25), (19, 25), (22, 29), (18, 29)], fill=INK)
    else:
        outline = [
            (14, 2), (20, 8), (20, 9), (23, 10), (23, 14),
            (20, 15), (17, 17), (17, 23), (20, 26), (21, 29),
            (17, 29), (15, 25), (13, 25), (11, 29), (8, 29),
            (10, 26), (12, 23), (12, 17), (8, 13), (8, 8),
        ]
        draw.polygon(outline, fill=INK)
        draw.polygon([(14, 4), (18, 8), (18, 13), (15, 16), (14, 15)], fill=NEUTRAL)
        draw.polygon([(14, 4), (14, 15), (10, 12), (10, 8)], fill=DEEP)
        draw.polygon([(14, 7), (17, 11), (14, 15), (11, 11)], fill=BLOOD)
        draw.polygon([(20, 10), (23, 11), (23, 13), (19, 15)], fill=NEUTRAL)
        draw.rectangle((13, 17, 16, 24), fill=DEEP)
        draw.polygon([(17, 18), (22, 16), (23, 18), (18, 21)], fill=NEUTRAL)
        draw.polygon([(11, 25), (14, 25), (12, 29), (8, 29)], fill=INK)
        draw.polygon([(16, 25), (18, 25), (21, 29), (17, 29)], fill=INK)

    return image


def paste_cell(atlas: Image.Image, cell: Image.Image, col: int, row: int) -> None:
    atlas.alpha_composite(cell, (col * 32, row * 32))


def sprite(atlas: Image.Image, rect: tuple[int, int, int, int], scale: int = 1) -> Image.Image:
    x, y, w, h = rect
    crop = atlas.crop((x, y, x + w, y + h))
    if scale != 1:
        crop = crop.resize((w * scale, h * scale), Image.Resampling.NEAREST)
    return crop


def paste_centered(canvas: Image.Image, item: Image.Image, x: int, y: int) -> None:
    canvas.alpha_composite(item, (x - item.width // 2, y - item.height // 2))


def draw_checker_floor(draw: ImageDraw.ImageDraw, box: tuple[int, int, int, int], step: int = 32) -> None:
    x0, y0, x1, y1 = box
    draw.rectangle(box, fill=GROUND, outline=NEUTRAL, width=2)
    grid = rgba(DEEP)
    for x in range(x0 + step, x1, step):
        draw.line((x, y0, x, y1), fill=grid, width=1)
    for y in range(y0 + step, y1, step):
        draw.line((x0, y, x1, y), fill=grid, width=1)


def make_enemy_review(atlas: Image.Image) -> Image.Image:
    canvas = Image.new("RGBA", (1280, 720), rgba(INK))
    draw = ImageDraw.Draw(canvas)
    draw_checker_floor(draw, (48, 48, 1232, 672), 64)
    title_font = font(22)
    small_font = font(14)
    draw.text((72, 68), "ROLE SILHOUETTES", font=title_font, fill=rgba(BONE))
    draw.text((72, 100), "shape first / palette locked / 32 px cells", font=small_font, fill=rgba(NEUTRAL))

    entries = [
        ("RANGER", (64, 0, 32, 32), (224, 300)),
        ("PURSUER", (0, 32, 32, 32), (474, 300)),
        ("CHARGER", (64, 32, 32, 32), (724, 300)),
        ("SHOOTER", (128, 32, 32, 32), (974, 300)),
    ]
    for label, rect, center in entries:
        draw.rectangle(
            (center[0] - 94, 178, center[0] + 94, 412),
            fill=rgba(DEEP),
            outline=rgba(NEUTRAL),
            width=2,
        )
        paste_centered(canvas, sprite(atlas, rect, 4), center[0], center[1])
        text_box = draw.textbbox((0, 0), label, font=small_font)
        text_w = text_box[2] - text_box[0]
        draw.text((center[0] - text_w // 2, 392), label, font=small_font, fill=rgba(BONE))

    draw.text((72, 462), "ACTION SILHOUETTES", font=title_font, fill=rgba(BONE))
    action_entries = [
        ((32, 32, 32, 32), 474),
        ((96, 32, 32, 32), 724),
        ((160, 32, 32, 32), 974),
    ]
    for rect, center_x in action_entries:
        draw.rectangle(
            (center_x - 94, 500, center_x + 94, 634),
            fill=rgba(DEEP),
            outline=rgba(NEUTRAL),
            width=2,
        )
        paste_centered(canvas, sprite(atlas, rect, 3), center_x, 565)
    draw.line((142, 650, 1138, 650), fill=rgba(BONE), width=2)
    return canvas


def draw_brackets(draw: ImageDraw.ImageDraw, box: tuple[int, int, int, int], color: tuple[int, int, int, int]) -> None:
    x0, y0, x1, y1 = box
    length = max(5, min(x1 - x0, y1 - y0) // 4)
    segments = [
        (x0, y0, x0 + length, y0), (x0, y0, x0, y0 + length),
        (x1, y0, x1 - length, y0), (x1, y0, x1, y0 + length),
        (x0, y1, x0 + length, y1), (x0, y1, x0, y1 - length),
        (x1, y1, x1 - length, y1), (x1, y1, x1, y1 - length),
    ]
    for segment in segments:
        draw.line(segment, fill=color, width=2)


def draw_hatching(draw: ImageDraw.ImageDraw, box: tuple[int, int, int, int]) -> None:
    x0, y0, x1, y1 = box
    for x in range(x0 - (y1 - y0), x1, 12):
        start_x = max(x0, x)
        start_y = y0 + max(0, x0 - x)
        end_x = min(x1, x + (y1 - y0))
        end_y = y0 + (end_x - x)
        draw.line((start_x, start_y, end_x, min(end_y, y1)), fill=rgba(BLOOD), width=3)


def paste_boss(
    canvas: Image.Image,
    atlas: Image.Image,
    center_x: int,
    body_y: int,
    scale: int,
    open_core: bool,
    left_offset: tuple[int, int] = (-46, 50),
    right_offset: tuple[int, int] = (46, 50),
) -> None:
    body = sprite(atlas, (0, 64, 64, 64), scale)
    hand_l = sprite(atlas, (64, 64, 32, 32), scale)
    hand_r = sprite(atlas, (96, 64, 32, 32), scale)
    core_x = 160 if open_core else 128
    core = sprite(atlas, (core_x, 64, 32, 32), scale)
    canvas.alpha_composite(body, (center_x - body.width // 2, body_y))
    paste_centered(canvas, hand_l, center_x + left_offset[0] * scale, body_y + left_offset[1] * scale)
    paste_centered(canvas, hand_r, center_x + right_offset[0] * scale, body_y + right_offset[1] * scale)
    canvas.alpha_composite(core, (center_x - core.width // 2, body_y + 16 * scale))


def boss_state_panel(
    atlas: Image.Image,
    size: tuple[int, int],
    attack_index: int,
    state: str,
) -> Image.Image:
    width, height = size
    panel = Image.new("RGBA", size, rgba(DEEP))
    draw = ImageDraw.Draw(panel)
    draw_checker_floor(draw, (2, 2, width - 3, height - 3), 24)
    # The lower matrix demonstrates all three attacks in phase 2. Core state is
    # deliberately independent from attack_id; the phase strip above owns that
    # distinction.
    open_core = True
    body_y = 18
    boss_x = width // 2

    if attack_index == 1:
        target = (boss_x - 52, height - 50, boss_x + 52, height - 14)
        if state == "windup":
            draw_brackets(draw, target, rgba(WARNING))
            draw_hatching(draw, target)
            offsets = ((-42, 48), (42, 12))
        elif state == "active":
            draw.rectangle(target, fill=rgba(BLOOD), outline=rgba(BONE), width=3)
            draw.line((target[0], target[1], target[2], target[3]), fill=rgba(BONE), width=2)
            draw.line((target[2], target[1], target[0], target[3]), fill=rgba(BONE), width=2)
            offsets = ((-42, 48), (10, 90))
        else:
            offsets = ((-42, 48), (18, 82))
            draw.line((boss_x - 42, height - 17, boss_x + 38, height - 17), fill=rgba(NEUTRAL), width=2)
        paste_boss(panel, atlas, boss_x, body_y, 1, open_core, *offsets)

    elif attack_index == 2:
        origin = (boss_x + 18, body_y + 58)
        fan_box = (boss_x - 80, body_y + 20, boss_x + 116, height + 52)
        if state == "windup":
            draw.arc(fan_box, 52, 128, fill=rgba(WARNING), width=3)
            for angle in (52, 76, 102, 128):
                radius = 62
                point = (
                    int(origin[0] + math.cos(math.radians(angle)) * radius),
                    int(origin[1] + math.sin(math.radians(angle)) * radius),
                )
                draw.line((origin, point), fill=rgba(WARNING), width=2)
            offsets = ((-52, 36), (60, 38))
        elif state == "active":
            arc_points = []
            for angle in range(52, 129, 8):
                arc_points.append(
                    (
                        int(origin[0] + math.cos(math.radians(angle)) * 62),
                        int(origin[1] + math.sin(math.radians(angle)) * 62),
                    )
                )
            draw.polygon([origin, *arc_points], fill=rgba(BLOOD))
            draw.line(arc_points, fill=rgba(BONE), width=3, joint="curve")
            offsets = ((-52, 42), (70, 64))
        else:
            offsets = ((-52, 48), (72, 74))
            draw.line((boss_x + 28, height - 20, boss_x + 106, height - 13), fill=rgba(NEUTRAL), width=2)
        paste_boss(panel, atlas, boss_x, body_y, 1, open_core, *offsets)

    else:
        lane = (boss_x - 34, body_y + 62, boss_x + 34, height - 12)
        if state == "windup":
            draw.line((lane[0], lane[1], lane[0], lane[3]), fill=rgba(WARNING), width=3)
            draw.line((lane[2], lane[1], lane[2], lane[3]), fill=rgba(WARNING), width=3)
            for y in range(lane[1] + 8, lane[3], 14):
                draw.line((lane[0], y, lane[0] + 8, y), fill=rgba(WARNING), width=2)
                draw.line((lane[2] - 8, y, lane[2], y), fill=rgba(WARNING), width=2)
        elif state == "active":
            draw.rectangle(lane, fill=rgba(BLOOD))
            draw.line((lane[0], lane[3], lane[2], lane[3]), fill=rgba(BONE), width=3)
        else:
            short_lane = (boss_x - 18, body_y + 62, boss_x + 18, body_y + 91)
            draw.line((short_lane[0], short_lane[1], short_lane[0], short_lane[3]), fill=rgba(NEUTRAL), width=2)
            draw.line((short_lane[2], short_lane[1], short_lane[2], short_lane[3]), fill=rgba(NEUTRAL), width=2)
        paste_boss(panel, atlas, boss_x, body_y, 1, open_core, (-42, 48), (42, 48))

    player = sprite(atlas, (64, 0, 32, 32), 1)
    panel.alpha_composite(player, (20, height - 48))
    return panel


def make_boss_review(atlas: Image.Image) -> Image.Image:
    canvas = Image.new("RGBA", (1280, 720), rgba(INK))
    draw = ImageDraw.Draw(canvas)
    title_font = font(18)
    label_font = font(13)

    top_y = 18
    top_h = 210
    phase_w = 388
    phase_xs = (28, 446, 864)
    labels = ("PHASE 1 / CLOSED", "TRANSITION / NO ATTACK HIT", "PHASE 2 / OPEN")
    for x, label in zip(phase_xs, labels):
        draw_checker_floor(draw, (x, top_y, x + phase_w, top_y + top_h), 32)
        draw.text((x + 14, top_y + 12), label, font=title_font, fill=rgba(BONE))

    paste_boss(canvas, atlas, phase_xs[0] + phase_w // 2, top_y + 42, 2, False, (-44, 48), (44, 48))
    transition_center = phase_xs[1] + phase_w // 2
    for index, inset in enumerate((72, 49, 28)):
        color = rgba((NEUTRAL, BONE, BONE)[index])
        draw.rectangle(
            (
                transition_center - inset,
                top_y + 58 + index * 4,
                transition_center + inset,
                top_y + 180 - index * 4,
            ),
            outline=color,
            width=3,
        )
    paste_boss(canvas, atlas, phase_xs[2] + phase_w // 2, top_y + 42, 2, True, (-54, 42), (50, 58))

    states = ("WINDUP", "ACTIVE", "RECOVERY")
    attacks = ("P2 ATTACK 01 / SLAM", "P2 ATTACK 02 / SWEEP", "P2 ATTACK 03 / LANE")
    panel_w = 388
    panel_h = 144
    x_positions = (28, 446, 864)
    y_positions = (246, 398, 550)
    for row, (attack_label, y) in enumerate(zip(attacks, y_positions), start=1):
        for state, x in zip(states, x_positions):
            panel = boss_state_panel(atlas, (panel_w, panel_h), row, state.lower())
            canvas.alpha_composite(panel, (x, y))
            draw.text((x + panel_w - 92, y + 8), state, font=label_font, fill=rgba(NEUTRAL))
        draw.text((34, y + 8), attack_label, font=label_font, fill=rgba(BONE))
    return canvas


def save_review_variants(image: Image.Image, stem: str) -> None:
    image.save(REVIEW_DIR / f"{stem}_100.png", optimize=True)
    quarter = image.resize((320, 180), Image.Resampling.NEAREST)
    quarter.save(REVIEW_DIR / f"{stem}_25.png", optimize=True)
    gray = ImageOps.grayscale(quarter.convert("RGB")).convert("RGB")
    gray.save(REVIEW_DIR / f"{stem}_25_gray.png", optimize=True)


def validate(base: Image.Image, candidate: Image.Image) -> None:
    assert base.size == (256, 128)
    assert candidate.size == (256, 128)
    assert candidate.mode == "RGBA"
    allowed_box = (64, 32, 192, 64)
    assert base.crop(allowed_box).getchannel("A").getbbox() is None, (
        "reserved atlas cells are no longer transparent",
        allowed_box,
    )

    alpha_values = {pixel[3] for pixel in candidate.get_flattened_data()}
    assert alpha_values <= {0, 255}, alpha_values

    for y in range(128):
        for x in range(256):
            inside = allowed_box[0] <= x < allowed_box[2] and allowed_box[1] <= y < allowed_box[3]
            if not inside:
                assert candidate.getpixel((x, y)) == base.getpixel((x, y)), (x, y)

    specs = {
        "charger_idle": (2, 1),
        "charger_attack": (3, 1),
        "fan_shooter_idle": (4, 1),
        "fan_shooter_attack": (5, 1),
    }
    for name, (col, row) in specs.items():
        cell = candidate.crop((col * 32, row * 32, col * 32 + 32, row * 32 + 32))
        alpha = cell.getchannel("A")
        bbox = alpha.getbbox()
        assert bbox is not None, name
        assert bbox[0] >= 2 and bbox[1] >= 2 and bbox[2] <= 30 and bbox[3] <= 30, (name, bbox)
        colors = {
            "#{:02X}{:02X}{:02X}".format(r, g, b)
            for r, g, b, a in cell.get_flattened_data()
            if a
        }
        assert colors <= {INK, DEEP, NEUTRAL, BLOOD}, (name, colors)
        assert len(colors) <= 4, (name, colors)
        print(f"{name}: bbox={bbox} colors={sorted(colors)}")

    for stem in ("enemy_roles", "threshold_colossus_grammar"):
        full_path = REVIEW_DIR / f"{stem}_100.png"
        quarter_path = REVIEW_DIR / f"{stem}_25.png"
        gray_path = REVIEW_DIR / f"{stem}_25_gray.png"
        full = Image.open(full_path).convert("RGBA")
        quarter = Image.open(quarter_path).convert("RGBA")
        gray = Image.open(gray_path).convert("RGB")
        assert full.size == (1280, 720), full_path
        assert quarter.size == (320, 180), quarter_path
        assert gray.size == (320, 180), gray_path
        expected_quarter = full.resize((320, 180), Image.Resampling.NEAREST)
        assert quarter.tobytes() == expected_quarter.tobytes(), quarter_path
        expected_gray = ImageOps.grayscale(quarter.convert("RGB")).convert("RGB")
        assert gray.tobytes() == expected_gray.tobytes(), gray_path

    print("review_variants=exact_nearest_and_grayscale")

    print(f"base_sha256={hashlib.sha256(BASE_ATLAS_PATH.read_bytes()).hexdigest()}")
    print(f"candidate_sha256={hashlib.sha256(OUTPUT_ATLAS_PATH.read_bytes()).hexdigest()}")
    print("P0_ART_VALIDATION_PASS")


def main() -> None:
    REVIEW_DIR.mkdir(parents=True, exist_ok=True)
    base = Image.open(BASE_ATLAS_PATH).convert("RGBA")
    atlas = base.copy()
    paste_cell(atlas, draw_charger(False), 2, 1)
    paste_cell(atlas, draw_charger(True), 3, 1)
    paste_cell(atlas, draw_fan_shooter(False), 4, 1)
    paste_cell(atlas, draw_fan_shooter(True), 5, 1)
    atlas.save(OUTPUT_ATLAS_PATH, optimize=True)

    save_review_variants(make_enemy_review(atlas), "enemy_roles")
    save_review_variants(make_boss_review(atlas), "threshold_colossus_grammar")
    validate(base, atlas)


if __name__ == "__main__":
    main()
