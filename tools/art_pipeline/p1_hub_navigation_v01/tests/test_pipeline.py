"""Unit tests for the P1 hub-navigation packaging pipeline.

The fixtures are synthetic: a magenta 1536x1024 sheet holding one distinctly
shaped blob per 512x512 tile, drawn in colours that are deliberately not part of
the declared palette so the palette mapping is exercised. Every test drives the
real ``build.py`` and ``verify.py`` entry points, never a stub of them.
"""

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
import contract  # noqa: E402
import review  # noqa: E402
import verify  # noqa: E402
from bridge import prepare_sprite, verify_rgba_cell  # noqa: E402

MAGENTA = (255, 0, 255, 255)
PALETTE = ["#273036", "#59656a", "#899396", "#e0e2dc", "#5b4036", "#896043", "#ad7950"]
# Deliberately off-palette blob colours, one per tile.
BLOB_COLORS = [
    (10, 20, 30, 255),
    (200, 120, 60, 255),
    (90, 95, 100, 255),
    (140, 150, 160, 255),
    (70, 80, 90, 255),
]
SOURCE_RECTS = [
    [0, 0, 512, 512],
    [512, 0, 512, 512],
    [1024, 0, 512, 512],
    [0, 512, 512, 512],
    [512, 512, 512, 512],
]


def make_source(path: Path) -> Path:
    """Write a 1536x1024 sheet with one distinct magenta-keyed blob per tile."""
    image = Image.new("RGBA", contract.SOURCE_LAYOUT, MAGENTA)
    for index, (x, y, width, height) in enumerate(SOURCE_RECTS):
        color = BLOB_COLORS[index]
        inset = 60 + index * 12
        for row in range(y + inset, y + height - inset):
            for column in range(x + inset, x + width - inset):
                # A per-tile notch keeps every alpha mask distinct.
                if row < y + inset + 40 and column < x + inset + 40 + index * 30:
                    continue
                image.putpixel((column, row), color)
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path)
    return path


class PipelineTestCase(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        # The reviewed inputs live in their own directory, mirroring the
        # repository layout where a pack and a review folder are siblings of it.
        self.inputs = self.root / "art-production" / "p1-hub-navigation-v01"
        self.source = make_source(self.inputs / "sources" / "navigation_keyed.png")
        self.recipe_path = self.inputs / "recipe.json"
        self.recipe_data = self.make_recipe()
        self.write_json(self.recipe_path, self.recipe_data)
        self._case = 0

    def tearDown(self) -> None:
        self.temporary.cleanup()

    @staticmethod
    def write_json(path: Path, value: object) -> None:
        path.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding="utf-8")

    def make_recipe(self) -> dict:
        return {
            "schema_version": 1,
            "source": "sources/navigation_keyed.png",
            "palette": list(PALETTE),
            "colorkey": "#FF00FF",
            "tolerance": 100,
            "key_scope": "all",
            "sprites": [
                {"id": sprite_id, "source_rect": list(rect)}
                for sprite_id, rect in zip(contract.SPRITE_IDS, SOURCE_RECTS, strict=True)
            ],
        }

    def build_pack(
        self,
        recipe: dict | None = None,
        *,
        name: str = "out/pack",
        review_name: str | None = None,
    ) -> Path:
        if recipe is not None:
            self.write_json(self.recipe_path, recipe)
        output = self.root / name
        review_directory = self.root / review_name if review_name else None
        build.build(self.recipe_path, output, review_directory)
        return output

    def case_dir(self) -> Path:
        self._case += 1
        return self.root / "cases" / f"case-{self._case}"

    def assert_refused(self, pattern: str, recipe: dict | None = None) -> None:
        if recipe is not None:
            self.write_json(self.recipe_path, recipe)
        with self.assertRaisesRegex(build.ContractError, pattern):
            build.build(self.recipe_path, self.case_dir())

    # ------------------------------------------------------------------ happy path

    def test_build_and_verify_complete_contract(self):
        output = self.build_pack()
        self.assertEqual(verify.verify_output(output), [])
        atlas = json.loads((output / contract.ATLAS_FILE).read_text(encoding="utf-8"))
        self.assertEqual(atlas["schema_version"], 1)
        self.assertEqual([sprite["id"] for sprite in atlas["sprites"]], list(contract.SPRITE_IDS))
        self.assertEqual(
            [sprite["rect"] for sprite in atlas["sprites"]],
            [[index * 32, 0, 32, 32] for index in range(5)],
        )
        self.assertEqual([sprite["anchor"] for sprite in atlas["sprites"]], [[16, 16]] * 5)
        self.assertEqual({sprite["type"] for sprite in atlas["sprites"]}, {"ui_icon"})
        self.assertEqual({sprite["texture"] for sprite in atlas["sprites"]}, {"icons"})
        self.assertEqual(
            atlas["textures"],
            {
                "icons": {
                    "path": "res://art/production/p1/hub_navigation_v01/icons.png",
                    "width": 160,
                    "height": 32,
                }
            },
        )
        with Image.open(output / contract.TEXTURE_FILE) as image:
            self.assertEqual(image.size, (160, 32))

    def test_output_is_pack_bytes_only(self):
        output = self.build_pack(review_name="review")
        self.assertEqual(
            {path.name for path in output.iterdir()},
            {contract.TEXTURE_FILE, contract.ATLAS_FILE, contract.MANIFEST_FILE},
        )

    def test_review_derivatives_are_separate_and_sized(self):
        output = self.build_pack(review_name="review")
        review_directory = self.root / "review"
        self.assertEqual(
            {path.name for path in review_directory.iterdir()}, set(contract.REVIEW_ORDER)
        )
        expected = review.derivative_dimensions((160, 32))
        for name in contract.REVIEW_ORDER:
            with Image.open(review_directory / name) as image:
                self.assertEqual(list(image.size), expected[name], name)
        manifest = json.loads((output / contract.MANIFEST_FILE).read_text(encoding="utf-8"))
        self.assertEqual(set(manifest["review"]["derivatives"]), {"native", "2x", "25pct", "gray", "silhouette"})
        self.assertEqual(verify.verify_output(output), [])

    def test_review_is_optional(self):
        output = self.build_pack()
        manifest = json.loads((output / contract.MANIFEST_FILE).read_text(encoding="utf-8"))
        self.assertNotIn("review", manifest)
        self.assertEqual(verify.verify_output(output), [])

    def test_gray_and_silhouette_keep_alpha_exact(self):
        self.build_pack(review_name="review")
        review_directory = self.root / "review"
        with Image.open(self.root / "out" / "pack" / contract.TEXTURE_FILE) as opened:
            atlas_alpha = opened.convert("RGBA").getchannel("A").tobytes()
        for name in (contract.REVIEW_GRAY, contract.REVIEW_SILHOUETTE):
            with Image.open(review_directory / name) as image:
                self.assertEqual(image.convert("RGBA").getchannel("A").tobytes(), atlas_alpha, name)

    def test_published_sheet_satisfies_pipeline_gates(self):
        output = self.build_pack()
        with Image.open(output / contract.TEXTURE_FILE) as opened:
            atlas = opened.convert("RGBA")
        gate = verify_rgba_cell()
        for index, sprite_id in enumerate(contract.SPRITE_IDS):
            errors: list[str] = []
            cell = atlas.crop((index * 32, 0, index * 32 + 32, 32))
            gate(cell, sprite_id, errors)
            self.assertEqual(errors, [], sprite_id)
            self.assertLessEqual(len(build.visible_colors(cell)), contract.MAX_COLORS)
        masks = {
            build.alpha_mask(atlas.crop((index * 32, 0, index * 32 + 32, 32)))
            for index in range(5)
        }
        self.assertEqual(len(masks), 5)

    def test_atlas_pixels_are_palette_exact(self):
        output = self.build_pack()
        declared = {build.parse_color(color, "palette") for color in PALETTE}
        with Image.open(output / contract.TEXTURE_FILE) as opened:
            visible = build.visible_colors(opened.convert("RGBA"))
        self.assertTrue(visible)
        self.assertTrue(visible.issubset(declared), sorted(visible - declared))

    # ------------------------------------------------------------------ recipe rejection

    def test_source_rect_outside_source_is_rejected(self):
        recipe = copy.deepcopy(self.recipe_data)
        # 512 + 1024 = 1536, past the 1024-tall source.
        recipe["sprites"][2]["source_rect"] = [1024, 512, 512, 1024]
        self.assert_refused(r"source_rect is outside", recipe)

    def test_fractional_rect_entries_are_rejected(self):
        recipe = copy.deepcopy(self.recipe_data)
        recipe["sprites"][0]["source_rect"] = [0.0, 0, 512, 512]
        self.assert_refused(r"entries must be integers", recipe)

    def test_negative_and_zero_sized_rects_are_rejected(self):
        for rect in ([-1, 0, 512, 512], [0, 0, 0, 512], [512, 0, 512, -4]):
            with self.subTest(rect=rect):
                recipe = copy.deepcopy(self.recipe_data)
                recipe["sprites"][1]["source_rect"] = rect
                self.assert_refused(r"non-negative origin and a positive size", recipe)

    def test_rect_of_wrong_arity_is_rejected(self):
        recipe = copy.deepcopy(self.recipe_data)
        recipe["sprites"][0]["source_rect"] = [0, 0, 512, 512, 0]
        self.assert_refused(r"must be \[x,y,w,h\]", recipe)

    def test_overlapping_rects_are_rejected(self):
        recipe = copy.deepcopy(self.recipe_data)
        recipe["sprites"][1]["source_rect"] = [256, 0, 512, 512]
        self.assert_refused(r"source_rect collision", recipe)

    def test_id_order_is_enforced(self):
        recipe = copy.deepcopy(self.recipe_data)
        recipe["sprites"][0]["id"] = "forge"
        self.assert_refused(r"sprite 0 must be contract", recipe)

    def test_missing_sprite_is_rejected(self):
        recipe = copy.deepcopy(self.recipe_data)
        recipe["sprites"].pop()
        self.assert_refused(r"must declare exactly 5 sprites", recipe)

    def test_unknown_sprite_id_is_rejected(self):
        recipe = copy.deepcopy(self.recipe_data)
        recipe["sprites"][4]["id"] = "immortality"
        self.assert_refused(r"sprite 4 must be proxy", recipe)

    def test_unsupported_sprite_keys_are_rejected(self):
        recipe = copy.deepcopy(self.recipe_data)
        recipe["sprites"][0]["visible_bbox"] = [0, 0, 10, 10]
        self.assert_refused(r"unsupported keys", recipe)

    def test_duplicate_palette_colours_are_rejected(self):
        recipe = copy.deepcopy(self.recipe_data)
        recipe["palette"] = list(PALETTE[:3]) + [PALETTE[0]]
        self.assert_refused(r"duplicate colours", recipe)

    def test_palette_over_seven_colours_is_rejected(self):
        recipe = copy.deepcopy(self.recipe_data)
        recipe["palette"] = list(PALETTE) + ["#ffffff"]
        self.assert_refused(r"must contain 1..7 colours", recipe)

    def test_wrong_colour_key_is_rejected(self):
        recipe = copy.deepcopy(self.recipe_data)
        recipe["colorkey"] = "#00FF00"
        self.assert_refused(r"colorkey must be #FF00FF", recipe)

    def test_wrong_key_scope_is_rejected(self):
        recipe = copy.deepcopy(self.recipe_data)
        recipe["key_scope"] = "edge_connected"
        self.assert_refused(r"key_scope must be all", recipe)

    def test_missing_source_is_rejected(self):
        recipe = copy.deepcopy(self.recipe_data)
        recipe["source"] = "sources/absent.png"
        self.assert_refused(r"source PNG does not exist", recipe)

    def test_absolute_source_path_is_accepted(self):
        recipe = copy.deepcopy(self.recipe_data)
        recipe["source"] = str(self.source)
        output = self.build_pack(recipe)
        self.assertEqual(verify.verify_output(output), [])

    # ------------------------------------------------------------------ overwrite refusal

    def test_existing_pack_is_never_overwritten(self):
        output = self.build_pack()
        before = {path.name: path.read_bytes() for path in output.iterdir()}
        with self.assertRaisesRegex(build.ContractError, "refusing to overwrite"):
            build.build(self.recipe_path, output)
        self.assertEqual({path.name: path.read_bytes() for path in output.iterdir()}, before)

    def test_existing_review_directory_is_never_overwritten(self):
        self.build_pack(review_name="review")
        with self.assertRaisesRegex(build.ContractError, "refusing to overwrite"):
            build.build(self.recipe_path, self.root / "other", self.root / "review")
        self.assertFalse((self.root / "other").exists())

    def test_review_directory_inside_the_pack_is_refused(self):
        output = self.root / "out"
        with self.assertRaisesRegex(build.ContractError, "would overwrite a reviewed file"):
            build.build(self.recipe_path, output, output / "review")
        self.assertFalse(output.exists())

    def test_output_equal_to_review_directory_is_refused(self):
        target = self.root / "both"
        with self.assertRaisesRegex(build.ContractError, "would overwrite a reviewed file"):
            build.build(self.recipe_path, target, target)

    def test_output_that_is_a_file_is_refused(self):
        target = self.root / "file.out"
        target.write_text("not a directory", encoding="utf-8")
        with self.assertRaisesRegex(build.ContractError, "not a directory"):
            build.build(self.recipe_path, target)

    def test_pack_inside_a_reviewed_file_is_refused(self):
        """A file cannot host a pack, so that target must never be created."""
        with self.assertRaisesRegex(build.ContractError, "would overwrite a reviewed file"):
            build.build(self.recipe_path, self.recipe_path / "pack")
        self.assertTrue(self.recipe_path.is_file())

    def test_pack_beside_the_reviewed_inputs_is_allowed(self):
        """A batch directory holds the recipe, its sources and the pack together."""
        pack = self.inputs / "pack"
        build.build(self.recipe_path, pack)
        self.assertEqual(verify.verify_output(pack), [])

    def test_review_subdirectory_inside_the_batch_is_allowed(self):
        """The repository convention: a review folder inside the batch directory."""
        pack = self.inputs / "pack"
        review_directory = self.inputs / "icon_review"
        build.build(self.recipe_path, pack, review_directory)
        self.assertEqual(verify.verify_output(pack), [])
        self.assertEqual(
            {path.name for path in review_directory.iterdir()}, set(contract.REVIEW_ORDER)
        )

    def test_output_aimed_at_a_reviewed_file_is_refused(self):
        # A path a reviewed file already occupies can never become the pack.
        with self.assertRaisesRegex(build.ContractError, "not a directory|would overwrite a reviewed file"):
            build.build(self.recipe_path, self.recipe_path)
        self.assertEqual(
            json.loads(self.recipe_path.read_text(encoding="utf-8"))["schema_version"], 1
        )

    # ------------------------------------------------------------------ tamper detection

    def test_source_hash_tampering_is_detected(self):
        output = self.build_pack()
        with Image.open(self.source) as opened:
            image = opened.convert("RGBA")
        image.putpixel((10, 10), (1, 2, 3, 255))
        image.save(self.source)
        self.assertTrue(any("hash mismatch: source" == error for error in verify.verify_output(output)))

    def test_recipe_hash_tampering_is_detected(self):
        output = self.build_pack()
        recipe = copy.deepcopy(self.recipe_data)
        recipe["palette"][0] = "#273037"
        self.write_json(self.recipe_path, recipe)
        self.assertTrue(any("hash mismatch: recipe" == error for error in verify.verify_output(output)))

    def test_artifact_hash_tampering_is_detected(self):
        output = self.build_pack()
        icons = output / contract.TEXTURE_FILE
        icons.write_bytes(icons.read_bytes() + b"\x00")
        errors = verify.verify_output(output)
        self.assertTrue(any("mismatch: icons.png" in error for error in errors), errors)

    def test_atlas_tampering_is_detected(self):
        output = self.build_pack()
        atlas_path = output / contract.ATLAS_FILE
        atlas = json.loads(atlas_path.read_text(encoding="utf-8"))
        atlas["sprites"][3]["rect"] = [64, 0, 32, 32]
        self.write_json(atlas_path, atlas)
        errors = verify.verify_output(output)
        self.assertTrue(any("metadata mismatch: training" in error for error in errors), errors)

    def test_atlas_texture_metadata_tampering_is_detected(self):
        output = self.build_pack()
        atlas_path = output / contract.ATLAS_FILE
        atlas = json.loads(atlas_path.read_text(encoding="utf-8"))
        atlas["textures"]["icons"]["width"] = 128
        self.write_json(atlas_path, atlas)
        errors = verify.verify_output(output)
        self.assertTrue(any("texture metadata" in error for error in errors), errors)

    def test_manifest_technical_contract_tampering_is_detected(self):
        output = self.build_pack()
        manifest_path = output / contract.MANIFEST_FILE
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        manifest["technical_contract"]["max_colors"] = 12
        self.write_json(manifest_path, manifest)
        errors = verify.verify_output(output)
        self.assertTrue(any("technical_contract is invalid" in error for error in errors), errors)

    def test_verify_is_repairing_only_one_file_does_not_hide_pixel_tampering(self):
        """Re-hashing a tampered sheet is not enough: the pixels are re-gated."""
        output = self.build_pack()
        icons_path = output / contract.TEXTURE_FILE
        with Image.open(icons_path) as opened:
            atlas = opened.convert("RGBA")
        # A semi-transparent pixel is source damage the pipeline must never emit.
        atlas.putpixel((16, 16), (35, 48, 54, 128))
        atlas.save(icons_path)
        manifest_path = output / contract.MANIFEST_FILE
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        for record in manifest["outputs"]["artifacts"]:
            if record["file"] == contract.TEXTURE_FILE:
                record["sha256"] = build.sha256_file(icons_path)
                record["bytes"] = icons_path.stat().st_size
        self.write_json(manifest_path, manifest)
        errors = verify.verify_output(output)
        self.assertTrue(any("non-binary alpha" in error for error in errors), errors)

    def test_unmanaged_file_in_the_pack_is_reported(self):
        output = self.build_pack()
        (output / "contact_sheet.png").write_bytes(b"")
        errors = verify.verify_output(output)
        self.assertTrue(any("unmanaged files" in error for error in errors), errors)

    def test_godot_import_sidecar_is_tolerated(self):
        """Godot writes icons.png.import beside an imported pack texture."""
        output = self.build_pack()
        sidecar = output / f"{contract.TEXTURE_FILE}.import"
        sidecar.write_text("[remap]\nimporter=\"texture\"\n", encoding="utf-8")
        self.assertEqual(verify.verify_output(output), [])
        # It stays tolerated as-is: it is not a published, hashed artifact.
        sidecar.write_text("[remap]\nimporter=\"texture\"\nchanged=1\n", encoding="utf-8")
        self.assertEqual(verify.verify_output(output), [])

    def test_missing_review_directory_is_reported(self):
        output = self.build_pack(review_name="review")
        for path in sorted((self.root / "review").iterdir()):
            path.unlink()
        (self.root / "review").rmdir()
        errors = verify.verify_output(output)
        self.assertTrue(any("review directory is missing" in error for error in errors), errors)

    def test_editing_a_review_derivative_is_reported(self):
        output = self.build_pack(review_name="review")
        derivative = self.root / "review" / contract.REVIEW_GRAY
        derivative.write_bytes(derivative.read_bytes() + b"\x00")
        errors = verify.verify_output(output)
        self.assertTrue(any("mismatch: review/icons_gray.png" in error for error in errors), errors)

    # ------------------------------------------------------------------ pipeline gates

    def test_shared_alpha_mask_is_rejected_by_the_build(self):
        """Two cells with one silhouette are a copy-paste defect, not a pack."""
        recipe = copy.deepcopy(self.recipe_data)
        recipe["sprites"][1]["source_rect"] = list(SOURCE_RECTS[0])
        self.assert_refused(r"share one alpha mask|source_rect collision", recipe)

    def test_the_reused_cell_gate_flags_each_violation(self):
        gate = verify_rgba_cell()
        cases = {
            "empty": Image.new("RGBA", (32, 32), (0, 0, 0, 0)),
            "non-binary alpha": Image.new("RGBA", (32, 32), (10, 20, 30, 128)),
            "transparent rgb": Image.new("RGBA", (32, 32), (7, 7, 7, 0)),
        }
        for name, image in cases.items():
            with self.subTest(name=name):
                errors: list[str] = []
                gate(image, "probe", errors)
                self.assertTrue(errors, name)

    def test_the_reused_cell_gate_flags_oversized_art(self):
        gate = verify_rgba_cell()
        image = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
        for y in range(0, 32):
            for x in range(0, 32):
                image.putpixel((x, y), (10, 20, 30, 255))
        errors: list[str] = []
        gate(image, "probe", errors)
        self.assertTrue(any("padding" in error for error in errors), errors)

    def test_prepare_sprite_is_the_reviewed_implementation(self):
        """The packager must not carry a private copy of the reviewed routine."""
        self.assertTrue(prepare_sprite().__module__.endswith("p1_early_loop_reuse.build"))
        self.assertTrue(verify_rgba_cell().__module__.endswith("p1_early_loop_reuse.verify"))

    def test_sibling_contract_is_not_shadowed_by_this_package(self):
        from bridge import _modules

        sibling = _modules()["contract"]
        self.assertNotEqual(sibling, contract)
        self.assertEqual(sibling.CELL_SIZE, 32)
        self.assertEqual(getattr(sibling, "GROUPS"), sibling.GROUPS)

    def test_bare_module_names_are_not_left_staged(self):
        from bridge import _modules

        _modules()
        for name in ("contract", "build", "verify"):
            module = sys.modules.get(name)
            if module is not None:
                self.assertNotIn("p1_early_loop_reuse", getattr(module, "__name__", ""))

    def test_visible_colours_are_bounded_for_every_cell(self):
        output = self.build_pack()
        with Image.open(output / contract.TEXTURE_FILE) as opened:
            atlas = opened.convert("RGBA")
        for index in range(5):
            cell = atlas.crop((index * 32, 0, index * 32 + 32, 32))
            self.assertLessEqual(len(build.visible_colors(cell)), contract.MAX_COLORS)


if __name__ == "__main__":
    unittest.main()
