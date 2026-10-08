from __future__ import annotations

import copy
import json
import sys
import tempfile
import unittest
from pathlib import Path

from PIL import Image


PIPELINE = Path(__file__).resolve().parents[1]
if str(PIPELINE) not in sys.path:
    sys.path.insert(0, str(PIPELINE))

import build  # noqa: E402
import verify  # noqa: E402
from contract import ENTRIES, GROUPS  # noqa: E402


MAGENTA = (255, 0, 255, 255)
PALETTE = ["#293136", "#59656a", "#899396", "#b8bebd", "#e0e2dc"]


class PipelineTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.sources = self.root / "sources"
        self.sources.mkdir()
        self.catalog = self.root / "catalog.json"
        repository_catalog = PIPELINE.parents[2] / "docs/art-production/p1-early-loop-v01/catalog.json"
        self.catalog.write_bytes(repository_catalog.read_bytes())
        self.recipe = self.root / "recipe.json"
        self.recipe_data = self._make_recipe()
        self._write_json(self.recipe, self.recipe_data)

    def tearDown(self) -> None:
        self.temporary.cleanup()

    @staticmethod
    def _write_json(path: Path, value: object) -> None:
        path.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding="utf-8")

    def _make_source(self, group_id: str, rows: int, cols: int) -> Path:
        cell = 40
        image = Image.new("RGBA", (cols * cell, rows * cell), MAGENTA)
        index = 0
        for row in range(rows):
            for col in range(cols):
                origin_x, origin_y = col * cell, row * cell
                color = (45 + index * 5, 60 + index * 4, 70 + index * 3, 255)
                for y in range(origin_y + 6, origin_y + 34):
                    for x in range(origin_x + 7, origin_x + 33):
                        image.putpixel((x, y), color)
                index += 1
        path = self.sources / f"{group_id}.png"
        image.save(path)
        return path

    def _make_recipe(self) -> dict:
        groups = []
        for group_id, _, (rows, cols) in GROUPS:
            source = self._make_source(group_id, rows, cols)
            sprites = []
            for index, frozen in enumerate(ENTRIES[group_id]):
                col, row = index % cols, index // cols
                sprites.append({"id": frozen[0], "source_rect": [col * 40, row * 40, 40, 40], "visible_bbox": None})
            group = {
                "id": group_id,
                "source": str(source),
                "layout": {"rows": rows, "cols": cols},
                "colorkey": "#ff00ff",
                "key_scope": "all",
                "tolerance": 80,
                "palette_quantization": 12,
                "sprites": sprites,
            }
            if group_id == "equipment_slots":
                group["palette"] = PALETTE
            groups.append(group)
        return {"schema_version": 1, "groups": groups}

    def _build(self, recipe: dict | None = None, output: Path | None = None) -> Path:
        if recipe is not None:
            self._write_json(self.recipe, recipe)
        destination = output or self.root / "out"
        build.build(self.catalog, self.recipe, destination)
        return destination

    def test_build_and_verify_complete_contract(self):
        output = self._build()
        self.assertEqual(verify.verify_output(output), [])
        atlas = json.loads((output / "atlas.json").read_text(encoding="utf-8"))
        self.assertIsInstance(atlas["sprites"], list)
        self.assertEqual(len(atlas["sprites"]), 24)
        sprites = {sprite["id"]: sprite for sprite in atlas["sprites"]}
        self.assertEqual(sprites["action.basic_dodge"]["canonical_id"], None)
        self.assertEqual(sprites["equipment_slot.main_hand"]["type"], "ui_icon")
        for group_id, texture, _ in GROUPS:
            with Image.open(output / texture) as image:
                self.assertEqual(image.size, (len(ENTRIES[group_id]) * 32, 32))

    def test_edge_connected_colorkey_cleanup_preserves_enclosed_same_color(self):
        image = Image.new("RGBA", (12, 12), MAGENTA)
        for y in range(2, 10):
            for x in range(2, 10):
                image.putpixel((x, y), (40, 50, 60, 255))
        image.putpixel((5, 5), MAGENTA)
        cleaned = build.remove_edge_colorkey(image, (255, 0, 255), 80)
        self.assertEqual(cleaned.getpixel((0, 0)), (0, 0, 0, 0))
        self.assertEqual(cleaned.getpixel((5, 5)), MAGENTA)

    def test_all_scope_makes_enclosed_ring_hole_transparent(self):
        image = Image.new("RGBA", (16, 16), MAGENTA)
        for y in range(3, 13):
            for x in range(3, 13):
                image.putpixel((x, y), (90, 100, 105, 255))
        for y in range(6, 10):
            for x in range(6, 10):
                image.putpixel((x, y), MAGENTA)
        cleaned = build.remove_all_colorkey(image, (255, 0, 255), 80)
        self.assertEqual(cleaned.getpixel((0, 0)), (0, 0, 0, 0))
        self.assertEqual(cleaned.getpixel((7, 7)), (0, 0, 0, 0))
        self.assertEqual(cleaned.getpixel((4, 4)), (90, 100, 105, 255))

    def test_all_scope_tolerance_cleans_enclosed_key_pollution(self):
        image = Image.new("RGBA", (5, 5), (40, 50, 60, 255))
        image.putpixel((2, 2), (230, 20, 230, 255))
        cleaned = build.remove_all_colorkey(image, (255, 0, 255), 80)
        self.assertEqual(cleaned.getpixel((2, 2)), (0, 0, 0, 0))
        self.assertEqual(cleaned.getpixel((1, 1)), (40, 50, 60, 255))

    def test_colorkey_tolerance_removes_connected_edge_pollution(self):
        image = Image.new("RGBA", (8, 8), MAGENTA)
        image.putpixel((0, 3), (230, 20, 230, 255))
        image.putpixel((1, 3), (220, 25, 220, 255))
        image.putpixel((2, 3), (40, 50, 60, 255))
        cleaned = build.remove_edge_colorkey(image, (255, 0, 255), 80)
        self.assertEqual(cleaned.getpixel((1, 3)), (0, 0, 0, 0))
        self.assertEqual(cleaned.getpixel((2, 3)), (40, 50, 60, 255))

    def test_fully_opaque_without_explicit_colorkey_is_rejected(self):
        recipe = copy.deepcopy(self.recipe_data)
        del recipe["groups"][0]["colorkey"]
        del recipe["groups"][0]["key_scope"]
        del recipe["groups"][0]["tolerance"]
        with self.assertRaisesRegex(build.ContractError, "fully opaque"):
            self._build(recipe)

    def test_no_alpha_without_explicit_colorkey_is_rejected(self):
        recipe = copy.deepcopy(self.recipe_data)
        source = Path(recipe["groups"][0]["source"])
        with Image.open(source) as image:
            image.convert("RGB").save(source)
        del recipe["groups"][0]["colorkey"]
        del recipe["groups"][0]["key_scope"]
        del recipe["groups"][0]["tolerance"]
        with self.assertRaisesRegex(build.ContractError, "no alpha"):
            self._build(recipe)

    def test_semitransparent_foreground_is_rejected(self):
        recipe = copy.deepcopy(self.recipe_data)
        source = Path(recipe["groups"][1]["source"])
        with Image.open(source) as image:
            rgba = image.convert("RGBA")
        rgba.putpixel((8, 8), (40, 50, 60, 128))
        rgba.save(source)
        with self.assertRaisesRegex(build.ContractError, "semi-transparent"):
            self._build(recipe)

    def test_missing_grid_cell_mapping_is_rejected(self):
        recipe = copy.deepcopy(self.recipe_data)
        recipe["groups"][0]["sprites"].pop()
        with self.assertRaisesRegex(build.ContractError, "must contain 4 sprites"):
            self._build(recipe)

    def test_source_cell_collision_is_rejected(self):
        recipe = copy.deepcopy(self.recipe_data)
        recipe["groups"][0]["sprites"][1]["source_rect"] = recipe["groups"][0]["sprites"][0]["source_rect"]
        with self.assertRaisesRegex(build.ContractError, "source_rect collision"):
            self._build(recipe)

    def test_odd_source_dimensions_and_nonuniform_manual_rects_are_accepted(self):
        recipe = copy.deepcopy(self.recipe_data)
        group = recipe["groups"][1]
        source = Path(group["source"])
        image = Image.new("RGBA", (1586, 992), MAGENTA)
        x_edges = [0, 396, 793, 1189, 1586]
        y_edges = [0, 520, 992]
        for row in range(2):
            for col in range(4):
                for y in range(y_edges[row] + 40, y_edges[row + 1] - 40):
                    for x in range(x_edges[col] + 40, x_edges[col + 1] - 40):
                        image.putpixel((x, y), (45 + col * 10, 60 + row * 10, 75, 255))
        image.save(source)
        for index, sprite in enumerate(group["sprites"]):
            col, row = index % 4, index // 4
            sprite["source_rect"] = [
                x_edges[col], y_edges[row],
                x_edges[col + 1] - x_edges[col], y_edges[row + 1] - y_edges[row],
            ]
        output = self._build(recipe)
        self.assertEqual(verify.verify_output(output), [])

    def test_manual_rect_reading_order_is_enforced(self):
        recipe = copy.deepcopy(self.recipe_data)
        first = recipe["groups"][0]["sprites"][0]["source_rect"]
        second = recipe["groups"][0]["sprites"][1]["source_rect"]
        recipe["groups"][0]["sprites"][0]["source_rect"] = second
        recipe["groups"][0]["sprites"][1]["source_rect"] = first
        with self.assertRaisesRegex(build.ContractError, "left-to-right"):
            self._build(recipe)

    def test_duplicate_catalog_id_is_rejected(self):
        catalog = json.loads(self.catalog.read_text(encoding="utf-8"))
        catalog["groups"][0]["entries"][1]["id"] = catalog["groups"][0]["entries"][0]["id"]
        self._write_json(self.catalog, catalog)
        with self.assertRaisesRegex(build.ContractError, "catalog mapping mismatch"):
            self._build()

    def test_input_output_overlap_is_rejected(self):
        source = Path(self.recipe_data["groups"][0]["source"])
        with self.assertRaisesRegex(build.ContractError, "input/output paths overlap"):
            self._build(output=source.parent)

    def test_nonempty_output_is_rejected_without_overwrite(self):
        output = self.root / "out"
        output.mkdir()
        marker = output / "unregistered.txt"
        marker.write_text("keep", encoding="utf-8")
        with self.assertRaisesRegex(build.ContractError, "unmanaged entries"):
            self._build(output=output)
        self.assertEqual(marker.read_text(encoding="utf-8"), "keep")

    def test_bad_edge_is_detected_by_verifier(self):
        output = self._build()
        texture = output / "equipment_slots.png"
        with Image.open(texture) as image:
            rgba = image.convert("RGBA")
        rgba.putpixel((0, 16), (40, 50, 60, 255))
        rgba.save(texture)
        manifest = json.loads((output / "manifest.json").read_text(encoding="utf-8"))
        for record in manifest["artifacts"]:
            if record["file"] == texture.name:
                record["sha256"] = build.sha256_file(texture)
                record["bytes"] = texture.stat().st_size
        self._write_json(output / "manifest.json", manifest)
        errors = verify.verify_output(output)
        self.assertTrue(any("four-edge padding" in error for error in errors), errors)

    def test_artifact_hash_tampering_is_detected(self):
        output = self._build()
        path = output / "atlas.json"
        path.write_text(path.read_text(encoding="utf-8") + " ", encoding="utf-8")
        self.assertIn("artifact hash mismatch: atlas.json", verify.verify_output(output))

    def test_duplicate_atlas_sprite_id_is_detected(self):
        output = self._build()
        path = output / "atlas.json"
        atlas = json.loads(path.read_text(encoding="utf-8"))
        atlas["sprites"][1]["id"] = atlas["sprites"][0]["id"]
        self._write_json(path, atlas)
        manifest = json.loads((output / "manifest.json").read_text(encoding="utf-8"))
        for record in manifest["artifacts"]:
            if record["file"] == "atlas.json":
                record["sha256"] = build.sha256_file(path)
                record["bytes"] = path.stat().st_size
        self._write_json(output / "manifest.json", manifest)
        errors = verify.verify_output(output)
        self.assertTrue(any(error.startswith("duplicate atlas sprite id:") for error in errors), errors)

    def test_source_hash_tampering_is_detected(self):
        output = self._build()
        source = Path(self.recipe_data["groups"][0]["source"])
        with Image.open(source) as image:
            rgba = image.convert("RGBA")
        rgba.putpixel((10, 10), (1, 2, 3, 255))
        rgba.save(source)
        errors = verify.verify_output(output)
        self.assertTrue(any("source hash mismatch: equipment_slots" == error for error in errors), errors)

    def test_transparent_rgb_is_normalized(self):
        output = self._build()
        with Image.open(output / "equipment_bases.png") as image:
            transparent = [pixel for pixel in image.convert("RGBA").getdata() if pixel[3] == 0]
        self.assertTrue(transparent)
        self.assertEqual(set(transparent), {(0, 0, 0, 0)})

    def test_slot_palette_is_exact_and_limited(self):
        output = self._build()
        expected = {build.parse_color(color, "palette") for color in PALETTE}
        with Image.open(output / "equipment_slots.png") as image:
            visible = {pixel[:3] for pixel in image.convert("RGBA").getdata() if pixel[3] == 255}
        self.assertTrue(visible.issubset(expected))
        self.assertLessEqual(len(visible), 5)

    def test_tolerance_outside_review_range_is_rejected(self):
        recipe = copy.deepcopy(self.recipe_data)
        recipe["groups"][0]["tolerance"] = 101
        with self.assertRaisesRegex(build.ContractError, r"must be in \[60,100\]"):
            self._build(recipe)


if __name__ == "__main__":
    unittest.main()
