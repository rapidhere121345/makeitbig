"""Unit tests for the P1 equipment-readability overrides packaging tool.

Fixtures are synthetic 64x64 PNGs written into a temporary directory: magenta
keyed sheets, hard-alpha sheets, a fully opaque sheet and an alpha-less RGB
sheet. Their band colours are deliberately off-palette, so the palette mapping
is exercised. They are fixtures only: no test here reads, writes or stands in
for production art, and every output lands in a fresh temporary directory.

Every test drives the real build entry point and the reviewed routines the tool
is required to reuse; nothing is stubbed, and the tool is loaded by explicit
file path so this suite never binds a bare ``build`` module name that a sibling
pipeline also uses.

Run either (this tests directory is deliberately left without ``__init__.py``, so
the batch adds no file beyond its tool and this suite):
    python3 tools/art_pipeline/p1_equipment_readability_v02/tests/test_build.py
    python3 -m unittest discover -s tools/art_pipeline/p1_equipment_readability_v02/tests
"""

from __future__ import annotations

import hashlib
import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path

from PIL import Image

PIPELINE = Path(__file__).resolve().parents[1]
MODULE_NAME = "p1_equipment_readability_v02_build_under_test"
KEY = "#ff00ff"
MAGENTA = (255, 0, 255, 255)
PALETTE = ["#1b2733", "#3f5d75", "#8fb8d8", "#e8eef5"]
PALETTE_RGB = {(0x1B, 0x27, 0x33), (0x3F, 0x5D, 0x75), (0x8F, 0xB8, 0xD8), (0xE8, 0xEE, 0xF5)}
# Deliberately off-palette band colours, all far from the key colour.
BANDS = [
    ((10, 20, 30, 255), (60, 140, 90, 255)),
    ((200, 120, 60, 255), (70, 80, 90, 255)),
    ((90, 95, 100, 255), (140, 150, 160, 255)),
    ((30, 60, 120, 255), (210, 190, 40, 255)),
    ((120, 40, 60, 255), (40, 110, 130, 255)),
    ((15, 120, 40, 255), (230, 90, 20, 255)),
]
BACKGROUNDS = {"keyed-all": MAGENTA, "keyed-edge": MAGENTA, "alpha": (0, 0, 0, 0), "opaque": (30, 30, 30, 255)}
MODES = ("keyed-all", "keyed-edge", "alpha", "keyed-all", "keyed-edge", "alpha")
SOURCE_RECT = [0, 0, 64, 64]
SOURCE_SIZE = (64, 64)


def load_build_module():
    """Load this pipeline build module by explicit path, never as bare `build`."""
    spec = importlib.util.spec_from_file_location(MODULE_NAME, PIPELINE / "build.py")
    if spec is None or spec.loader is None:  # pragma: no cover - unreadable checkout
        raise RuntimeError(f"cannot load {PIPELINE / 'build.py'}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[MODULE_NAME] = module
    spec.loader.exec_module(module)
    return module


build = load_build_module()


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def draw_source(path: Path, background, bands, notch: int = 0, mode: str = "RGBA") -> Path:
    """One synthetic source: a two-band blob whose silhouette varies by notch."""
    image = Image.new(mode, SOURCE_SIZE, background)
    for y in range(12, 52):
        inset = 10 if y >= 32 else 10 + notch * 3
        for x in range(inset + (y % 3), 54):
            image.putpixel((x, y), bands[0] if y < 32 else bands[1])
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path)
    return path


def alpha_mask(cell: Image.Image) -> bytes:
    return bytes(1 if pixel[3] == 255 else 0 for pixel in cell.convert("RGBA").get_flattened_data())


class BuildTestCase(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.recipe_path = self.root / "recipe.json"

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def make_sources(self, modes=None) -> list[str]:
        """Write one synthetic source per sprite, plus an opaque and an RGB sheet."""
        modes = modes or MODES
        relative = []
        for index, sprite_id in enumerate(build.SPRITE_IDS):
            name = f"{index:02d}_{sprite_id.replace(chr(46), chr(95))}.png"
            draw_source(self.root / "sources" / name, BACKGROUNDS[modes[index]], BANDS[index], notch=index)
            relative.append(f"sources/{name}")
        draw_source(self.root / "sources" / "opaque.png", BACKGROUNDS["opaque"], BANDS[0])
        draw_source(self.root / "sources" / "rgb.png", (30, 30, 30), (BANDS[0][0][:3], BANDS[0][1][:3]), mode="RGB")
        return relative

    def make_recipe(self, sources=None, modes=None) -> dict:
        modes = modes or MODES
        sources = sources or self.make_sources(modes)
        sprites = []
        for index, sprite_id in enumerate(build.SPRITE_IDS):
            keyed = modes[index].startswith("keyed")
            sprites.append({
                "id": sprite_id,
                "source": sources[index],
                "source_rect": list(SOURCE_RECT),
                "palette": list(PALETTE),
                "colorkey": KEY if keyed else None,
                "key_scope": modes[index].split("-")[1] if keyed else None,
                "tolerance": 100 if keyed else None,
            })
        return {"schema_version": 1, "sprites": sprites}

    def write_recipe(self, recipe: dict) -> Path:
        self.recipe_path.write_text(json.dumps(recipe, indent=2), encoding="utf-8")
        return self.recipe_path

    def test_valid_six_sprites_package(self) -> None:
        out, review = self.root / "pack", self.root / "review"
        build.build(self.write_recipe(self.make_recipe()), out, review)
        self.assertEqual(sorted(p.name for p in out.iterdir()), ["atlas.json", "manifest.json", "overrides.png"])
        with Image.open(out / "overrides.png") as sheet:
            sheet.load()
            atlas = sheet.convert("RGBA")
        self.assertEqual(atlas.size, (96, 64))
        self.assertEqual((build.COLUMNS, build.ROWS, build.CELL_SIZE), (3, 2, 32))

        document = json.loads((out / "atlas.json").read_text(encoding="utf-8"))
        self.assertEqual(document["schema_version"], 1)
        self.assertEqual(document["textures"], [{"id": "overrides", "file": "overrides.png"}])
        sprites = document["sprites"]
        self.assertEqual([sprite["id"] for sprite in sprites], list(build.SPRITE_IDS))
        errors: list[str] = []
        masks = []
        for index, sprite in enumerate(sprites):
            self.assertEqual(sprite["canonical_id"], build.CANONICAL_BY_ID[sprite["id"]])
            self.assertEqual(sprite["type"], "ui_icon")
            self.assertEqual(sprite["texture"], "overrides.png")
            self.assertEqual(sprite["rect"], [(index % 3) * 32, (index // 3) * 32, 32, 32])
            self.assertEqual(sprite["anchor"], [16, 16])
            x, y, width, height = sprite["rect"]
            cell = atlas.crop((x, y, x + width, y + height))
            build.verify_rgba_cell(cell, sprite["id"], errors)
            left, top, right, bottom = cell.getchannel("A").getbbox()
            self.assertGreaterEqual(min(left, top, 32 - right, 32 - bottom), build.CELL_PADDING)
            self.assertLessEqual(build.visible_colors(cell), PALETTE_RGB)
            self.assertTrue(build.visible_colors(cell))
            masks.append(alpha_mask(cell))
        self.assertEqual(errors, [])
        self.assertEqual(len(set(masks)), len(build.SPRITE_IDS))

        pixels = list(atlas.get_flattened_data())
        self.assertLessEqual({pixel[3] for pixel in pixels}, {0, 255})
        self.assertTrue(all(pixel[:3] == (0, 0, 0) for pixel in pixels if pixel[3] == 0))

        manifest = json.loads((out / "manifest.json").read_text(encoding="utf-8"))
        self.assertEqual(manifest["schema_version"], 1)
        self.assertEqual(manifest["pipeline"], build.PIPELINE)
        self.assertEqual(manifest["inputs"]["recipe"]["sha256"], sha256_file(self.recipe_path))
        self.assertEqual(manifest["outputs"]["sprite_ids"], list(build.SPRITE_IDS))
        self.assertEqual(manifest["outputs"]["texture"]["dimensions"], [96, 64])
        self.assertEqual(manifest["outputs"]["atlas_sha256"], sha256_file(out / "atlas.json"))
        artifacts = {record["file"]: record for record in manifest["outputs"]["artifacts"]}
        self.assertEqual(sorted(artifacts), ["atlas.json", "overrides.png"])
        self.assertEqual(artifacts["overrides.png"]["sha256"], sha256_file(out / "overrides.png"))
        self.assertEqual(artifacts["overrides.png"]["dimensions"], [96, 64])
        traced = manifest["sprites"]
        self.assertEqual([entry["id"] for entry in traced], list(build.SPRITE_IDS))
        for index, entry in enumerate(traced):
            source = Path(entry["source"])
            keyed = MODES[index].startswith("keyed")
            self.assertEqual(entry["source_sha256"], sha256_file(source))
            self.assertEqual(entry["source_dimensions"], list(SOURCE_SIZE))
            self.assertEqual(entry["source_rect"], SOURCE_RECT)
            self.assertEqual(entry["palette"], PALETTE)
            self.assertEqual(entry["colorkey"], KEY if keyed else None)
            self.assertEqual(entry["key_scope"], MODES[index].split("-")[1] if keyed else None)
            self.assertEqual(entry["tolerance"], 100 if keyed else None)
            self.assertEqual(entry["rect"], [(index % 3) * 32, (index // 3) * 32, 32, 32])

        derivatives = sorted(p.name for p in review.iterdir())
        self.assertEqual(derivatives, sorted(["overrides_native.png", "overrides_2x.png",
                                              "overrides_25pct.png", "overrides_gray.png",
                                              "overrides_silhouette.png"]))
        with Image.open(review / "overrides_2x.png") as two_x:
            self.assertEqual(two_x.size, (192, 128))
        with Image.open(review / "overrides_25pct.png") as quarter:
            self.assertEqual(quarter.size, (24, 16))
        self.assertEqual(manifest["review"]["directory"], str(review.resolve()))

    def test_packaging_is_deterministic(self) -> None:
        recipe = self.write_recipe(self.make_recipe())
        first, second = self.root / "pack-a", self.root / "pack-b"
        build.build(recipe, first)
        build.build(recipe, second)
        self.assertEqual((first / "overrides.png").read_bytes(), (second / "overrides.png").read_bytes())
        self.assertEqual((first / "atlas.json").read_bytes(), (second / "atlas.json").read_bytes())

    def test_reviewed_routines_and_frozen_geometry(self) -> None:
        self.assertEqual(build.prepare_sprite.__module__, f"{build.BRIDGE.NAMESPACE}.build")
        self.assertEqual(build.verify_rgba_cell.__module__, f"{build.BRIDGE.NAMESPACE}.verify")
        self.assertEqual(build.BRIDGE_PATH.name, "bridge.py")
        self.assertEqual(build.BRIDGE_PATH.parent.name, "p1_hub_navigation_v01")
        self.assertEqual((build.CELL_SIZE, build.CELL_PADDING, build.MAX_VISIBLE, build.MAX_COLORS), (32, 2, 28, 12))
        self.assertEqual(build.ANCHOR, (16, 16))
        self.assertEqual((build.COLUMNS, build.ROWS, build.TEXTURE_SIZE), (3, 2, (96, 64)))
        self.assertEqual(build.SPRITE_IDS, (
            "equipment.lineage_quiver", "equipment.farwatch_quiver", "equipment.turnfeather_gloves",
            "equipment.piercer_gloves", "equipment_slot.off_hand", "equipment_slot.gloves"))
        self.assertEqual([build.CANONICAL_BY_ID[sprite_id] for sprite_id in build.SPRITE_IDS],
                         ["lineage_quiver", "farwatch_quiver", "turnfeather_gloves",
                          "piercer_gloves", "off_hand", "gloves"])
        for bands in BANDS:
            for band in bands:
                self.assertNotIn(band[:3], PALETTE_RGB)

    def test_missing_and_duplicate_ids_are_refused(self) -> None:
        recipe = self.make_recipe()
        short = {"schema_version": 1, "sprites": recipe["sprites"][:5]}
        with self.assertRaises(build.ContractError) as missing:
            build.build(self.write_recipe(short), self.root / "pack-missing")
        self.assertIn("exactly 6", str(missing.exception))
        recipe["sprites"][1]["id"] = recipe["sprites"][0]["id"]
        with self.assertRaises(build.ContractError) as duplicated:
            build.build(self.write_recipe(recipe), self.root / "pack-duplicate")
        self.assertIn(build.SPRITE_IDS[0], str(duplicated.exception))
        self.assertFalse((self.root / "pack-missing").exists())
        self.assertFalse((self.root / "pack-duplicate").exists())

    def test_crop_outside_source_and_overlapping_crops_are_refused(self) -> None:
        recipe = self.make_recipe()
        recipe["sprites"][0]["source_rect"] = [32, 32, 64, 64]
        with self.assertRaises(build.ContractError) as outside:
            build.build(self.write_recipe(recipe), self.root / "pack-outside")
        self.assertIn("outside the 64x64 source", str(outside.exception))
        recipe = self.make_recipe(modes=("alpha",) * 6)
        recipe["sprites"][1]["source"] = recipe["sprites"][0]["source"]
        with self.assertRaises(build.ContractError) as collision:
            build.build(self.write_recipe(recipe), self.root / "pack-collision")
        self.assertIn("collision", str(collision.exception))

    def test_keyless_sources_must_carry_real_transparency(self) -> None:
        recipe = self.make_recipe(modes=("opaque",) * 6)
        with self.assertRaises(build.ContractError) as opaque:
            build.build(self.write_recipe(recipe), self.root / "pack-opaque")
        self.assertIn("fully opaque", str(opaque.exception))
        for sprite in recipe["sprites"]:
            sprite.update({"colorkey": KEY, "key_scope": "all", "tolerance": 100})
        build.build(self.write_recipe(recipe), self.root / "pack-keyed")
        self.assertTrue((self.root / "pack-keyed" / "overrides.png").is_file())
        recipe = self.make_recipe(modes=("alpha",) * 6)
        recipe["sprites"][0]["source"] = "sources/rgb.png"
        with self.assertRaises(build.ContractError) as alpha_less:
            build.build(self.write_recipe(recipe), self.root / "pack-rgb")
        self.assertIn("no alpha", str(alpha_less.exception))

    def test_existing_targets_are_never_overwritten(self) -> None:
        recipe = self.write_recipe(self.make_recipe())
        stale = self.root / "pack"
        stale.mkdir()
        (stale / "overrides.png").write_bytes(b"stale-bytes")
        with self.assertRaises(build.ContractError) as existing:
            build.build(recipe, stale, self.root / "review")
        self.assertIn("must be a new path", str(existing.exception))
        self.assertEqual((stale / "overrides.png").read_bytes(), b"stale-bytes")
        self.assertFalse((self.root / "review").exists())
        empty = self.root / "empty"
        empty.mkdir()
        with self.assertRaises(build.ContractError):
            build.build(recipe, empty)
        with self.assertRaises(build.ContractError):
            build.build(recipe, self.root / "fresh", stale)
        self.assertFalse((self.root / "fresh").exists())
        self.assertEqual([p.name for p in self.root.iterdir() if p.name.startswith(".")], [])


if __name__ == "__main__":
    unittest.main(verbosity=2)
