#!/usr/bin/env python3
"""Mechanical previews of a packed P1 ranger action atlas.

Only mechanical operations are used: nearest-neighbor 1x/2x/25% sheets, a true
grayscale copy, and per-animation GIF export. Nothing is repainted, retouched or
composed into a scene. Every sheet states in its header that it is a preview and
not an in-game rendering.

Previews are written to a separate directory (a temporary one by default) so the
version directory keeps exactly the files the build recorded.
"""

from __future__ import annotations

import argparse
import json
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

if __name__ == "__main__":  # -P / PYTHONSAFEPATH leaves the script directory off sys.path
    sys.path.insert(0, str(Path(__file__).resolve().parent))
import build

CHECKER_DARK = (42, 47, 54, 255)
CHECKER_LIGHT = (52, 58, 66, 255)
CELL_BORDER = (90, 100, 112, 255)
TEXT_COLOR = (211, 203, 181, 255)
ANCHOR_COLOR = (255, 95, 135, 255)
BACKGROUND = (17, 24, 32, 255)
HEADER = "PREVIEW: mechanical nearest-neighbor sheet, not an in-game rendering"
SCALE_NAMES = {1.0: "native", 2.0: "2x", 0.25: "25pct"}


def _font() -> ImageFont.ImageFont:
    return ImageFont.load_default()


def _checker(width: int, height: int) -> Image.Image:
    tile = Image.new("RGBA", (width, height), CHECKER_DARK)
    draw = ImageDraw.Draw(tile)
    for y in range(0, height, 8):
        for x in range(0, width, 8):
            if ((x // 8) + (y // 8)) % 2 == 0:
                draw.rectangle((x, y, x + 7, y + 7), fill=CHECKER_LIGHT)
    return tile


def _cell(texture: Image.Image, rect: list[int]) -> Image.Image:
    x, y, width, height = rect
    return texture.crop((x, y, x + width, y + height))


def _nearest(image: Image.Image, scale: float) -> Image.Image:
    if scale == 1.0:
        return image
    width = max(1, int(round(image.width * scale)))
    height = max(1, int(round(image.height * scale)))
    return image.resize((width, height), Image.Resampling.NEAREST)


def _gray(image: Image.Image) -> Image.Image:
    result = image.convert("LA").convert("RGBA")
    result.putalpha(image.getchannel("A"))
    return result


def contact_sheet(
    atlas: dict, texture: Image.Image, animations: list[str], *, scale: float, grayscale: bool
) -> Image.Image:
    font = _font()
    cell_width = int(atlas["cell_size"][0] * scale)
    cell_height = int(atlas["cell_size"][1] * scale)
    header_text = HEADER + (" [grayscale]" if grayscale else "")
    probe = ImageDraw.Draw(Image.new("RGBA", (1, 1)))
    title_rows: list[str] = []
    for animation_id in animations:
        spec = atlas["animations"][animation_id]
        title_rows.append(
            f"{animation_id}  fps={spec['fps']} loop={spec['loop']} frames={len(spec['frames'])}"
        )
    grid_width = max(
        len(atlas["animations"][animation_id]["frames"]) * cell_width for animation_id in animations
    )
    width = max(grid_width, int(probe.textlength(header_text, font=font)) + 8, 200) + 8
    title_height = 14
    height = 18 + len(animations) * (title_height + cell_height + 4) + 6
    sheet = Image.new("RGBA", (width, height), BACKGROUND)
    draw = ImageDraw.Draw(sheet)
    draw.text((4, 4), header_text, fill=TEXT_COLOR, font=font)
    y = 18
    for animation_id in animations:
        spec = atlas["animations"][animation_id]
        draw.text((4, y + 2), title_rows[animations.index(animation_id)], fill=TEXT_COLOR, font=font)
        row_y = y + title_height
        checker = _checker(grid_width, cell_height)
        sheet.alpha_composite(checker, (4, row_y))
        for index, frame_id in enumerate(spec["frames"]):
            sprite = atlas["sprites"][frame_id]
            frame = _cell(texture, sprite["rect"])
            if grayscale:
                frame = _gray(frame)
            frame = _nearest(frame, scale)
            x = 4 + index * cell_width
            sheet.alpha_composite(frame, (x, row_y))
        for index in range(len(spec["frames"]) + 1):
            x = 4 + index * cell_width
            draw.line((x, row_y, x, row_y + cell_height - 1), fill=CELL_BORDER)
        draw.line((4, row_y, 4 + len(spec["frames"]) * cell_width - 1, row_y), fill=CELL_BORDER)
        draw.line(
            (4, row_y + cell_height - 1, 4 + len(spec["frames"]) * cell_width - 1, row_y + cell_height - 1),
            fill=CELL_BORDER,
        )
        if scale >= 1:
            anchor_x = 4 + int(atlas["sprites"][spec["frames"][0]]["anchor"][0] * scale)
            anchor_y = row_y + int(atlas["sprites"][spec["frames"][0]]["anchor"][1] * scale)
            draw.line((anchor_x - 2, anchor_y, anchor_x + 2, anchor_y), fill=ANCHOR_COLOR)
            draw.line((anchor_x, anchor_y - 2, anchor_x, anchor_y + 2), fill=ANCHOR_COLOR)
        y += title_height + cell_height + 4
    return sheet


def gif_frames(atlas: dict, texture: Image.Image, animation_id: str) -> list[Image.Image]:
    spec = atlas["animations"][animation_id]
    rect = atlas["sprites"][spec["frames"][0]]["rect"]
    checker = _checker(rect[2], rect[3]).convert("RGB")
    frames: list[Image.Image] = []
    for frame_id in spec["frames"]:
        sprite = atlas["sprites"][frame_id]
        composed = checker.copy()
        composed.paste(_cell(texture, sprite["rect"]).convert("RGB"), (0, 0), _cell(texture, sprite["rect"]).getchannel("A"))
        frames.append(composed)
    return frames


def color_listing(atlas: dict, texture: Image.Image) -> None:
    """Print the distinct visible colors of every packed frame (read-only)."""
    sprites = atlas["sprites"]
    order = sorted(sprites, key=lambda key: (sprites[key]["rect"][1], sprites[key]["rect"][0]))
    palette_seen: dict[tuple[int, int, int], int] = {}
    for frame_id in order:
        rect = sprites[frame_id]["rect"]
        cell = _cell(texture, rect).load()
        counts: dict[tuple[int, int, int, int], int] = {}
        for y in range(rect[3]):
            for x in range(rect[2]):
                pixel = cell[x, y]
                if pixel[3] == 0:
                    continue
                counts[pixel] = counts.get(pixel, 0) + 1
                palette_seen[pixel[:3]] = palette_seen.get(pixel[:3], 0) + 1
        described = " ".join(
            f"#{color[0]:02x}{color[1]:02x}{color[2]:02x}x{count}"
            for color, count in sorted(counts.items(), key=lambda item: (-item[1], item[0]))
        )
        print(f"colors {frame_id}: {len(counts)} -> {described}")
    print(f"colors union: {len(palette_seen)} distinct visible colors")
    print("suggested palette: " + ", ".join(f'"#{r:02x}{g:02x}{b:02x}"' for r, g, b in sorted(palette_seen)))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path, help="version output directory")
    parser.add_argument("--out", type=Path, default=None, help="preview directory (default: a new temp dir)")
    parser.add_argument("--scale", type=float, default=1.0, choices=[1.0, 2.0, 0.25])
    parser.add_argument("--gray", action="store_true", help="also write a true grayscale sheet")
    parser.add_argument("--gif", action="store_true", help="also write one GIF per animation")
    parser.add_argument("--anim", action="append", default=None, help="limit to this animation id (repeatable)")
    parser.add_argument("--colors", action="store_true", help="print the distinct visible colors per frame")
    args = parser.parse_args(argv)

    output = args.output.resolve()
    atlas_path = output / "atlas.json"
    if not atlas_path.is_file():
        print(f"REVIEW FAILED: {output} has no atlas.json", file=sys.stderr)
        return 1
    atlas = json.loads(atlas_path.read_text(encoding="utf-8"))
    # The texture is whatever file the atlas declares; review stays generic for
    # recipes that pack something other than ranger.png.
    textures = atlas.get("textures")
    if not isinstance(textures, dict) or len(textures) != 1:
        print("REVIEW FAILED: atlas.json must declare exactly one texture", file=sys.stderr)
        return 1
    texture_meta = next(iter(textures.values()))
    texture_name = Path(texture_meta.get("path", "")).name if isinstance(texture_meta, dict) else ""
    texture_path = output / texture_name
    if not texture_name or not texture_path.is_file():
        print(f"REVIEW FAILED: {output} has no {texture_name or 'declared texture'}", file=sys.stderr)
        return 1
    with Image.open(texture_path) as handle:
        texture = handle.convert("RGBA")

    animations = sorted(atlas["animations"])
    if args.anim:
        unknown = [item for item in args.anim if item not in atlas["animations"]]
        if unknown:
            print("REVIEW FAILED: unknown animation(s): " + ", ".join(unknown), file=sys.stderr)
            return 1
        animations = [item for item in animations if item in args.anim]

    out = args.out.resolve() if args.out else Path(tempfile.mkdtemp(prefix="p1_ranger_actions_review_"))
    if out == output or output.is_relative_to(out) or out.is_relative_to(output):
        print("REVIEW FAILED: previews must not be written into the version directory", file=sys.stderr)
        return 1
    out.mkdir(parents=True, exist_ok=True)

    written: list[str] = []
    scale_name = SCALE_NAMES[args.scale]
    sheet = contact_sheet(atlas, texture, animations, scale=args.scale, grayscale=False)
    sheet_path = out / f"contact_{scale_name}.png"
    sheet.save(sheet_path, format="PNG", optimize=False)
    written.append(sheet_path.name)
    if args.gray:
        gray_sheet = contact_sheet(atlas, texture, animations, scale=args.scale, grayscale=True)
        gray_path = out / f"contact_{scale_name}_gray.png"
        gray_sheet.save(gray_path, format="PNG", optimize=False)
        written.append(gray_path.name)
    if args.gif:
        gif_dir = out / "gif"
        gif_dir.mkdir(parents=True, exist_ok=True)
        for animation_id in animations:
            spec = atlas["animations"][animation_id]
            frames = gif_frames(atlas, texture, animation_id)
            palette_source = frames[0].quantize(colors=256)
            converted = [palette_source] + [
                frame.quantize(palette=palette_source, dither=Image.Dither.NONE) for frame in frames[1:]
            ]
            gif_path = gif_dir / f"{animation_id}.gif"
            converted[0].save(
                gif_path,
                format="GIF",
                save_all=True,
                append_images=converted[1:],
                duration=max(1, int(round(1000.0 / spec["fps"]))),
                loop=0,
                disposal=2,
            )
            written.append(f"gif/{gif_path.name}")
    print(f"preview_dir: {out}")
    for name in written:
        print(f"wrote: {name}")
    if args.colors:
        color_listing(atlas, texture)
    print("note: previews are mechanical contact sheets over a checkerboard; they are not in-game renders")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
