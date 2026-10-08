"""Geometry-pure unit tests for the P1 ranger action packing tool.

Every fixture is a tiny synthetic image built inside a temporary directory.
No game art is read, no bitmap art is produced, and nothing outside the
temporary directories is written.
"""

from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

from PIL import Image

PIPELINE_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PIPELINE_DIR))

import build  # noqa: E402
import review  # noqa: E402
import verify  # noqa: E402

PALETTE = ["#101820", "#304050", "#d0d8e0", "#802020"]
PARSED_PALETTE = tuple(build.parse_hex_color(color, "palette") for color in PALETTE)
BODY_COLOR = (16, 24, 32, 255)
KEY_NAME = "#00ff00ff"
FROZEN_RANGER_TEXTURE_SHA256 = "c0bd20d7767899db9a8319aca6dca68f034a47eb84c9d5016543a131802f888b"
FROZEN_RANGER_ATLAS_SHA256 = "5f5aa176fd862ce896dd1c8b92141af6003bf3d37cde7dd5ba094e9bc0c5ed41"


def nearest_palette(color):
    return min(PARSED_PALETTE, key=lambda item: build.color_distance(color, item))


def write_source(path, *, size=(96, 96), poses=(), details=(), background=(0, 0, 0, 0)):
    """Draw flat synthetic poses. poses are vertical bars with a chosen foot point."""
    path.parent.mkdir(parents=True, exist_ok=True)
    image = Image.new("RGBA", size, background)
    for pose in poses:
        foot_x, foot_y = pose["foot"]
        height = pose.get("height", 20)
        half = pose.get("half", 3)
        color = tuple(pose.get("color", BODY_COLOR))
        for yy in range(foot_y - height, foot_y):
            for xx in range(foot_x - half, foot_x + half):
                image.putpixel((xx, yy), color)
    for detail in details:
        x, y, width, height = detail["rect"]
        for yy in range(y, y + height):
            for xx in range(x, x + width):
                image.putpixel((xx, yy), tuple(detail["color"]))
    image.save(path, format="PNG")
    return image


def frame(**overrides):
    value = {
        "id": "ranger.south.idle.0",
        "source": "raw",
        "crop": [0, 0, 48, 48],
        "source_anchor": [24, 44],
        "scale": 1,
        "action": "idle",
        "facing": "south",
    }
    value.update(overrides)
    return value


def recipe(sources, frames, animations, **overrides):
    value = {
        "schema_version": 1,
        "resource_prefix": "res://art/production/p1/ranger_actions_v01",
        "native_view": [640, 360],
        "palette": PALETTE,
        "sources": {key: str(path) for key, path in sources.items()},
        "cell_size": [48, 48],
        "anchor": [24, 44],
        "columns": 4,
        "frames": frames,
        "animations": animations,
    }
    value.update(overrides)
    return value


class PipelineTestCase(unittest.TestCase):
    def setUp(self):
        self._temp = tempfile.TemporaryDirectory(prefix="p1_ranger_actions_test_")
        self.root = Path(self._temp.name)
        self.source = self.root / "raw_source.png"
        self.out = self.root / "out"

    def tearDown(self):
        self._temp.cleanup()

    def build(self, recipe_value, *, output=None, replace=False, name="recipe.json"):
        path = self.root / name
        path.write_text(json.dumps(recipe_value, indent=2), encoding="utf-8")
        return build.build_artifacts(path, output or self.out, replace_generated=replace)

    def write_recipe(self, recipe_value, name="recipe.json"):
        path = self.root / name
        path.write_text(json.dumps(recipe_value, indent=2), encoding="utf-8")
        return path

    def assert_fails(self, recipe_value, *, contains):
        with self.assertRaises(build.ConfigError) as caught:
            self.build(recipe_value)
        self.assertIn(contains, str(caught.exception))
        return str(caught.exception)


class PackingTests(PipelineTestCase):
    def test_happy_path_atlas_contract(self):
        write_source(self.source, poses=[{"foot": (24, 44)}, {"foot": (72, 44)}])
        value = recipe(
            {"raw": self.source},
            [
                frame(id="ranger.south.idle.0", crop=[0, 0, 48, 48]),
                frame(id="ranger.south.idle.1", crop=[48, 0, 48, 48], action="walk"),
            ],
            {"ranger.south.idle": {"frames": ["ranger.south.idle.0"], "fps": 4, "loop": True}},
        )
        manifest = self.build(value)
        atlas = json.loads((self.out / "atlas.json").read_text(encoding="utf-8"))
        self.assertEqual(atlas["schema_version"], 1)
        self.assertEqual(atlas["native_view"], [640, 360])
        self.assertEqual(atlas["cell_size"], [48, 48])
        self.assertEqual(
            atlas["textures"]["ranger"]["path"],
            "res://art/production/p1/ranger_actions_v01/ranger.png",
        )
        self.assertEqual(atlas["textures"]["ranger"]["width"], 192)
        self.assertEqual(atlas["textures"]["ranger"]["height"], 48)
        self.assertEqual(atlas["sprites"]["ranger.south.idle.0"]["rect"], [0, 0, 48, 48])
        self.assertEqual(atlas["sprites"]["ranger.south.idle.1"]["rect"], [48, 0, 48, 48])
        self.assertEqual(atlas["sprites"]["ranger.south.idle.0"]["anchor"], [24, 44])
        self.assertEqual(atlas["sprites"]["ranger.south.idle.0"]["texture"], "ranger")
        self.assertEqual(
            manifest["sources"]["raw"]["sha256"], build.sha256_file(self.source)
        )
        self.assertEqual(manifest["scale_by_source"], {"raw": 1.0})
        self.assertEqual(manifest["frames"][0]["bbox"], [21, 24, 6, 20])
        self.assertEqual(manifest["frames"][0]["foreground_pixels"], 120)
        self.assertEqual(manifest["frames"][0]["border_touches"], {"crop": [], "cell": []})
        errors, _infos, _summary = verify.verify_output(self.out, None, False)
        self.assertEqual(errors, [])

    def test_foot_point_stays_on_the_anchor_without_per_frame_fitting(self):
        write_source(
            self.source,
            poses=[{"foot": (24, 44)}, {"foot": (72, 44), "height": 21}],
        )
        value = recipe(
            {"raw": self.source},
            [
                frame(id="a.0", crop=[0, 0, 48, 48], action="walk", facing="south"),
                frame(id="a.1", crop=[48, 0, 48, 48], action="walk", facing="south"),
            ],
            {"ranger.south.walk": {"frames": ["a.0", "a.1"], "fps": 6, "loop": True}},
        )
        manifest = self.build(value)
        for entry in manifest["frames"]:
            assert entry["bbox"] is not None
            bottom = entry["bbox"][1] + entry["bbox"][3]
            self.assertEqual(bottom, 44, "feet must stay on the fixed anchor row")
            self.assertEqual(entry["bbox"][0] + entry["bbox"][2] // 2, 24)

    def test_outstretched_prop_does_not_move_the_feet(self):
        write_source(
            self.source,
            poses=[{"foot": (24, 44)}],
            details=[{"rect": [27, 26, 21, 2], "color": BODY_COLOR}],
        )
        value = recipe(
            {"raw": self.source},
            [frame(id="ranger.south.draw.0", crop=[0, 0, 48, 48], action="draw")],
            {"ranger.south.draw": {"frames": ["ranger.south.draw.0"], "fps": 4, "loop": False}},
        )
        manifest = self.build(value)
        entry = manifest["frames"][0]
        self.assertEqual(entry["bbox"][1] + entry["bbox"][3], 44)
        self.assertEqual(entry["bbox"], [21, 24, 27, 20])
        self.assertIn("right", entry["border_touches"]["crop"])
        errors, _infos, _summary = verify.verify_output(self.out, None, False)
        self.assertEqual(errors, [])

    def test_scale_two_keeps_the_anchor_point_exact(self):
        write_source(self.source, poses=[{"foot": (12, 22)}])
        value = recipe(
            {"raw": self.source},
            [frame(id="a.0", crop=[0, 0, 24, 24], source_anchor=[12, 22], scale=2, action="walk")],
            {"ranger.south.walk": {"frames": ["a.0"], "fps": 4, "loop": True}},
        )
        manifest = self.build(value)
        entry = manifest["frames"][0]
        self.assertEqual(entry["scaled_crop_size"], [48, 48])
        self.assertEqual(entry["paste"], [0, 0])
        self.assertEqual(entry["bbox"], [18, 4, 12, 40])
        self.assertEqual(entry["bbox"][1] + entry["bbox"][3], 44)

    def test_crop_outside_source_is_rejected(self):
        write_source(self.source, poses=[{"foot": (24, 44)}])
        value = recipe(
            {"raw": self.source},
            [frame(id="a.0", crop=[80, 0, 48, 48])],
            {"ranger.south.idle": {"frames": ["a.0"], "fps": 4, "loop": True}},
        )
        self.assert_fails(value, contains="outside source")

    def test_scaled_crop_that_cannot_fit_the_cell_is_rejected(self):
        write_source(self.source, poses=[{"foot": (24, 46)}])
        value = recipe(
            {"raw": self.source},
            [frame(id="a.0", crop=[0, 0, 48, 48], source_anchor=[24, 46])],
            {"ranger.south.idle": {"frames": ["a.0"], "fps": 4, "loop": True}},
        )
        self.assert_fails(value, contains="cannot be placed")

    def test_one_unified_scale_per_source_is_enforced(self):
        write_source(self.source, poses=[{"foot": (24, 44)}])
        value = recipe(
            {"raw": self.source},
            [
                frame(id="a.0", crop=[0, 0, 48, 48], action="idle", facing="south"),
                frame(id="a.1", crop=[0, 0, 24, 24], source_anchor=[12, 22], scale=2, action="walk", facing="south"),
            ],
            {"ranger.south.idle": {"frames": ["a.0"], "fps": 4, "loop": True}},
        )
        self.assert_fails(value, contains="unified scale")

    def test_empty_crop_is_rejected(self):
        write_source(self.source, poses=[{"foot": (24, 44)}])
        value = recipe(
            {"raw": self.source},
            [frame(id="a.0", crop=[48, 48, 24, 24], source_anchor=[12, 22])],
            {"ranger.south.idle": {"frames": ["a.0"], "fps": 4, "loop": True}},
        )
        self.assert_fails(value, contains="empty after background handling")

    def test_duplicate_frames_in_one_animation_are_rejected(self):
        write_source(self.source, poses=[{"foot": (24, 44)}, {"foot": (72, 44)}])
        value = recipe(
            {"raw": self.source},
            [
                frame(id="a.0", crop=[0, 0, 48, 48], action="walk", facing="south"),
                frame(id="a.1", crop=[48, 0, 48, 48], action="walk", facing="south"),
            ],
            {"ranger.south.walk": {"frames": ["a.0", "a.1"], "fps": 6, "loop": True}},
        )
        self.assert_fails(value, contains="pixel-identical")

    def test_unknown_frame_key_is_rejected(self):
        write_source(self.source, poses=[{"foot": (24, 44)}])
        bad = frame(id="a.0")
        bad["anchor"] = [24, 44]
        value = recipe(
            {"raw": self.source},
            [bad],
            {"ranger.south.idle": {"frames": ["a.0"], "fps": 4, "loop": True}},
        )
        self.assert_fails(value, contains="unknown keys")

    def test_animation_id_must_carry_facing_and_action(self):
        write_source(self.source, poses=[{"foot": (24, 44)}])
        value = recipe(
            {"raw": self.source},
            [frame(id="a.0", action="idle", facing="south")],
            {"ranger.south.walk": {"frames": ["a.0"], "fps": 4, "loop": True}},
        )
        self.assert_fails(value, contains="<facing>.<action>")

    def test_missing_animation_is_rejected(self):
        write_source(self.source, poses=[{"foot": (24, 44)}])
        value = recipe({"raw": self.source}, [frame(id="a.0")], {})
        self.assert_fails(value, contains="animations must be a non-empty object")


class BackgroundPolicyTests(PipelineTestCase):
    def test_fully_opaque_source_is_rejected_without_an_explicit_key(self):
        write_source(self.source, size=(48, 48), poses=[{"foot": (24, 44)}], background=(0, 255, 0, 255))
        value = recipe(
            {"raw": self.source},
            [frame(id="a.0")],
            {"ranger.south.idle": {"frames": ["a.0"], "fps": 4, "loop": True}},
        )
        message = self.assert_fails(value, contains="fully opaque")
        self.assertIn("color_key", message)

    def test_a_checkerboard_is_never_masked_automatically(self):
        image = Image.new("RGBA", (48, 48), (0, 255, 0, 255))
        for y in range(48):
            for x in range(48):
                if ((x // 8) + (y // 8)) % 2 == 0:
                    image.putpixel((x, y), (255, 0, 255, 255))
        image.putpixel((24, 44), (16, 24, 32, 255))
        self.source.parent.mkdir(parents=True, exist_ok=True)
        image.save(self.source, format="PNG")
        value = recipe(
            {"raw": self.source},
            [frame(id="a.0")],
            {"ranger.south.idle": {"frames": ["a.0"], "fps": 4, "loop": True}},
        )
        self.assert_fails(value, contains="fully opaque")
        value_with_key = recipe(
            {"raw": self.source},
            [frame(id="a.0")],
            {"ranger.south.idle": {"frames": ["a.0"], "fps": 4, "loop": True}},
            background={"raw": {"mode": "color_key", "colors": ["#ff0000"], "tolerance": 40}},
        )
        self.assert_fails(value_with_key, contains="matches no pixel")

    def test_color_key_requires_explicit_tolerance(self):
        write_source(self.source, size=(48, 48), poses=[{"foot": (24, 44)}], background=(0, 255, 0, 255))
        value = recipe(
            {"raw": self.source},
            [frame(id="a.0")],
            {"ranger.south.idle": {"frames": ["a.0"], "fps": 4, "loop": True}},
            background={"raw": {"mode": "color_key", "colors": [KEY_NAME]}},
        )
        self.assert_fails(value, contains="tolerance must be chosen explicitly")

    def test_explicit_color_key_removes_the_key_and_reports_enclosed_removals(self):
        write_source(
            self.source,
            size=(48, 48),
            poses=[{"foot": (24, 44)}],
            details=[{"rect": [22, 30, 2, 2], "color": (0, 255, 0, 255)}],
            background=(0, 255, 0, 255),
        )
        value = recipe(
            {"raw": self.source},
            [frame(id="a.0")],
            {"ranger.south.idle": {"frames": ["a.0"], "fps": 4, "loop": True}},
            background={"raw": {"mode": "color_key", "colors": [KEY_NAME], "tolerance": 0}},
        )
        manifest = self.build(value)
        entry = manifest["frames"][0]
        body_pixels = 6 * 20
        self.assertEqual(entry["background_removed_pixels"], 48 * 48 - (body_pixels - 4))
        self.assertEqual(entry["background_removed_enclosed_pixels"], 4)
        self.assertEqual(entry["foreground_pixels"], body_pixels - 4)
        matched_ratio = round((48 * 48 - (body_pixels - 4)) / (48 * 48), 4)
        self.assertEqual(manifest["sources"]["raw"]["background"]["matched_ratio"], matched_ratio)

    def test_border_scope_keeps_enclosed_interior_green(self):
        write_source(
            self.source,
            size=(48, 48),
            poses=[{"foot": (24, 44)}],
            details=[{"rect": [22, 30, 2, 2], "color": (0, 255, 0, 255)}],
            background=(0, 255, 0, 255),
        )
        value = recipe(
            {"raw": self.source},
            [frame(id="a.0")],
            {"ranger.south.idle": {"frames": ["a.0"], "fps": 4, "loop": True}},
            background={
                "raw": {"mode": "color_key", "colors": [KEY_NAME], "tolerance": 0, "scope": "border"}
            },
        )
        manifest = self.build(value)
        entry = manifest["frames"][0]
        self.assertEqual(entry["background_removed_enclosed_pixels"], 0)
        self.assertEqual(entry["foreground_pixels"], 120)
        with Image.open(self.out / "ranger.png") as handle:
            texture = handle.convert("RGBA")
        kept = texture.getpixel((22, 30))
        expected = nearest_palette((0, 255, 0, 255))
        self.assertEqual(kept[3], 255)
        self.assertEqual(kept, expected)
        self.assertEqual(texture.getpixel((0, 0))[3], 0)

    def test_tight_tolerance_keeps_distant_interior_colors(self):
        detail_color = (0, 176, 80, 255)
        self.assertGreater(build.key_distance(detail_color, (0, 255, 0, 255)), 60)
        write_source(
            self.source,
            size=(48, 48),
            poses=[{"foot": (24, 44)}],
            details=[{"rect": [22, 30, 2, 2], "color": detail_color}],
            background=(0, 255, 0, 255),
        )
        value = recipe(
            {"raw": self.source},
            [frame(id="a.0")],
            {"ranger.south.idle": {"frames": ["a.0"], "fps": 4, "loop": True}},
            background={"raw": {"mode": "color_key", "colors": [KEY_NAME], "tolerance": 60}},
        )
        self.build(value)
        with Image.open(self.out / "ranger.png") as handle:
            texture = handle.convert("RGBA")
        self.assertEqual(texture.getpixel((22, 30)), nearest_palette(detail_color))
        self.assertEqual(texture.getpixel((47, 47))[3], 0)


class DisclosureTests(PipelineTestCase):
    def test_external_source_must_be_disclosed(self):
        elsewhere = self.root / "elsewhere"
        external_source = elsewhere / "legacy_idle.png"
        write_source(external_source, poses=[{"foot": (24, 44)}])
        recipes = self.root / "recipes"
        recipes.mkdir()
        value = recipe(
            {"legacy_idle": external_source},
            [frame(id="ranger.south.idle.0", source="legacy_idle")],
            {"ranger.south.idle": {"frames": ["ranger.south.idle.0"], "fps": 4, "loop": True}},
        )
        path = self.write_recipe(value, name="recipes/recipe.json")
        with self.assertRaises(build.ConfigError) as caught:
            build.build_artifacts(path, self.out)
        self.assertIn("must be disclosed", str(caught.exception))
        value["disclosure"] = {"legacy_idle": "reused verbatim from the accepted scene_rework_v01 idle"}
        self.write_recipe(value, name="recipes/recipe.json")
        manifest = build.build_artifacts(path, self.out)
        self.assertEqual(manifest["external_sources"], ["legacy_idle"])
        self.assertEqual(list(manifest["disclosure"]), ["legacy_idle"])
        errors, _infos, _summary = verify.verify_output(self.out, None, False)
        self.assertEqual(errors, [])


class OutputGuardTests(PipelineTestCase):
    def recipe_with_one_frame(self):
        write_source(self.source, poses=[{"foot": (24, 44)}])
        return recipe(
            {"raw": self.source},
            [frame(id="a.0")],
            {"ranger.south.idle": {"frames": ["a.0"], "fps": 4, "loop": True}},
        )

    def test_non_empty_output_is_refused(self):
        value = self.recipe_with_one_frame()
        self.out.mkdir(parents=True)
        (self.out / "stray.png").write_bytes(b"not mine")
        self.assert_fails(value, contains="not empty")

    def test_empty_output_directory_is_accepted(self):
        value = self.recipe_with_one_frame()
        self.out.mkdir(parents=True)
        self.build(value)
        self.assertTrue((self.out / build.TEXTURE_FILENAME).is_file())

    def test_replace_generated_only_touches_manifest_owned_files(self):
        value = self.recipe_with_one_frame()
        self.build(value)
        (self.out / "notes.txt").write_text("user file", encoding="utf-8")
        path = self.write_recipe(value)
        with self.assertRaises(build.ConfigError) as caught:
            build.build_artifacts(path, self.out, replace_generated=True)
        self.assertIn("unmanaged", str(caught.exception))
        (self.out / "notes.txt").unlink()
        self.build(value, replace=True)
        self.assertTrue((self.out / build.TEXTURE_FILENAME).is_file())

    def test_symlinked_artifact_is_refused(self):
        value = self.recipe_with_one_frame()
        self.build(value)
        texture = self.out / build.TEXTURE_FILENAME
        target = self.out / "atlas.json"
        texture.unlink()
        texture.symlink_to(target)
        with self.assertRaises(build.ConfigError) as caught:
            self.build(value, replace=True)
        self.assertIn("symlink", str(caught.exception))

class VerifyTests(PipelineTestCase):
    def build_pair(self):
        write_source(self.source, poses=[{"foot": (24, 44)}, {"foot": (72, 44), "height": 21}])
        value = recipe(
            {"raw": self.source},
            [
                frame(id="a.0", crop=[0, 0, 48, 48], action="walk", facing="south"),
                frame(id="a.1", crop=[48, 0, 48, 48], action="walk", facing="south"),
            ],
            {"ranger.south.walk": {"frames": ["a.0", "a.1"], "fps": 6, "loop": True}},
        )
        self.build(value)
        return value

    def test_clean_build_verifies_and_updates_manifest(self):
        self.build_pair()
        errors, _infos, _summary = verify.verify_output(self.out, None, True)
        self.assertEqual(errors, [])
        manifest = json.loads((self.out / "manifest.json").read_text(encoding="utf-8"))
        self.assertEqual(manifest["technical_verification"]["status"], "verified_mechanical_only")

    def test_neighbor_cell_leakage_is_rejected(self):
        self.build_pair()
        texture_path = self.out / build.TEXTURE_FILENAME
        with Image.open(texture_path) as handle:
            texture = handle.convert("RGBA")
        texture.putpixel((48, 10), (16, 24, 32, 255))
        texture.save(texture_path, format="PNG")
        errors, _infos, _summary = verify.verify_output(self.out, None, False)
        self.assertTrue(
            any("does not match the recipe-derived frame" in line for line in errors), errors
        )
        self.assertTrue(any("neighbor-cell leakage" in line for line in errors), errors)

    def test_non_binary_alpha_is_rejected(self):
        self.build_pair()
        texture_path = self.out / build.TEXTURE_FILENAME
        with Image.open(texture_path) as handle:
            texture = handle.convert("RGBA")
        texture.putpixel((24, 43), (16, 24, 32, 200))
        texture.save(texture_path, format="PNG")
        errors, _infos, _summary = verify.verify_output(self.out, None, False)
        self.assertTrue(any("non-binary alpha" in line for line in errors), errors)

    def test_non_palette_color_is_rejected(self):
        self.build_pair()
        texture_path = self.out / build.TEXTURE_FILENAME
        with Image.open(texture_path) as handle:
            texture = handle.convert("RGBA")
        texture.putpixel((24, 43), (1, 2, 3, 255))
        texture.save(texture_path, format="PNG")
        errors, _infos, _summary = verify.verify_output(self.out, None, False)
        self.assertTrue(any("non-palette color" in line for line in errors), errors)

    def test_missing_animation_is_rejected(self):
        self.build_pair()
        atlas_path = self.out / "atlas.json"
        atlas = json.loads(atlas_path.read_text(encoding="utf-8"))
        del atlas["animations"]["ranger.south.walk"]
        atlas_path.write_text(json.dumps(atlas), encoding="utf-8")
        errors, _infos, _summary = verify.verify_output(self.out, None, False)
        self.assertTrue(any("missing animation" in line for line in errors), errors)

    def test_duplicate_frames_are_rejected(self):
        self.build_pair()
        texture_path = self.out / build.TEXTURE_FILENAME
        with Image.open(texture_path) as handle:
            texture = handle.convert("RGBA")
        first = texture.crop((0, 0, 48, 48))
        texture.paste(first, (48, 0))
        texture.save(texture_path, format="PNG")
        errors, _infos, _summary = verify.verify_output(self.out, None, False)
        self.assertTrue(any("repeats identical frames" in line for line in errors), errors)

    def test_changed_source_is_detected(self):
        self.build_pair()
        write_source(self.source, poses=[{"foot": (24, 45)}, {"foot": (72, 44), "height": 21}])
        errors, _infos, _summary = verify.verify_output(self.out, None, False)
        self.assertTrue(any("content changed since the build" in line for line in errors), errors)


class TextureKeyTests(PipelineTestCase):
    """Optional recipe texture_key; the default must stay the ranger contract."""

    def enemy_recipe(self, name="enemies.json"):
        write_source(self.source, poses=[{"foot": (24, 44)}, {"foot": (72, 44), "height": 21}])
        value = recipe(
            {"raw": self.source},
            [
                frame(id="melee.south.attack.0", crop=[0, 0, 48, 48], action="attack", facing="south"),
                frame(id="melee.south.attack.1", crop=[48, 0, 48, 48], action="attack", facing="south"),
            ],
            {"melee.south.attack": {"frames": ["melee.south.attack.0", "melee.south.attack.1"], "fps": 6, "loop": False}},
            texture_key="enemies",
            resource_prefix="res://art/production/p1/enemy_actions_v01",
        )
        return self.write_recipe(value, name=name)

    def test_default_texture_key_keeps_the_ranger_contract(self):
        write_source(self.source, poses=[{"foot": (24, 44)}])
        value = recipe(
            {"raw": self.source},
            [frame(id="ranger.south.idle.0")],
            {"ranger.south.idle": {"frames": ["ranger.south.idle.0"], "fps": 4, "loop": True}},
        )
        manifest = self.build(value)
        self.assertEqual(build.texture_spec(value), ("ranger", "ranger.png"))
        self.assertTrue((self.out / "ranger.png").is_file())
        self.assertFalse((self.out / "enemies.png").exists())
        self.assertEqual(manifest["texture"]["id"], "ranger")
        self.assertEqual(
            manifest["texture"]["path"], "res://art/production/p1/ranger_actions_v01/ranger.png"
        )
        atlas = json.loads((self.out / "atlas.json").read_text(encoding="utf-8"))
        self.assertEqual(list(atlas["textures"]), ["ranger"])
        self.assertEqual(atlas["sprites"]["ranger.south.idle.0"]["texture"], "ranger")

    def test_enemies_texture_key_builds_an_enemies_atlas_end_to_end(self):
        path = self.enemy_recipe()
        manifest = build.build_artifacts(path, self.out)
        self.assertTrue((self.out / "enemies.png").is_file())
        self.assertFalse((self.out / "ranger.png").exists())
        self.assertEqual(manifest["texture"]["id"], "enemies")
        self.assertEqual(
            manifest["texture"]["path"], "res://art/production/p1/enemy_actions_v01/enemies.png"
        )
        self.assertEqual(
            [item["kind"] for item in manifest["artifacts"]], ["texture", "atlas_contract"]
        )
        self.assertEqual(Path(manifest["artifacts"][0]["path"]).name, "enemies.png")
        self.assertEqual(manifest["artifacts"][0]["texture"], "enemies")
        self.assertEqual(
            manifest["artifacts"][0]["sha256"], build.sha256_file(self.out / "enemies.png")
        )
        atlas = json.loads((self.out / "atlas.json").read_text(encoding="utf-8"))
        self.assertEqual(list(atlas["textures"]), ["enemies"])
        self.assertEqual(atlas["sprites"]["melee.south.attack.0"]["texture"], "enemies")
        self.assertEqual(
            atlas["textures"]["enemies"]["path"],
            "res://art/production/p1/enemy_actions_v01/enemies.png",
        )
        errors, _infos, _summary = verify.verify_output(self.out, path, False)
        self.assertEqual(errors, [])
        previews = self.root / "enemy_previews"
        code = review.main(["--output", str(self.out), "--out", str(previews), "--gif"])
        self.assertEqual(code, 0)
        self.assertTrue((previews / "contact_native.png").is_file())
        self.assertTrue((previews / "gif" / "melee.south.attack.gif").is_file())

    def test_viewer_style_enemy_animation_names_are_accepted(self):
        write_source(self.source, poses=[{"foot": (24, 44)}, {"foot": (72, 44), "height": 21}], details=[{"rect": [70, 26, 21, 2], "color": BODY_COLOR}])
        value = recipe(
            {"raw": self.source},
            [
                frame(id="charger.east.charge.0", crop=[0, 0, 48, 48], action="charge", facing="east"),
                frame(id="charger.east.charge.1", crop=[48, 0, 48, 48], action="charge", facing="east"),
                frame(id="ranged.north.shoot.0", crop=[0, 0, 48, 48], source_anchor=[24, 44], action="shoot", facing="north"),
            ],
            {
                "charger.east.charge": {"frames": ["charger.east.charge.0", "charger.east.charge.1"], "fps": 5, "loop": False},
                "ranged.north.shoot": {"frames": ["ranged.north.shoot.0"], "fps": 4, "loop": True},
            },
            texture_key="enemies",
            resource_prefix="res://art/production/p1/enemy_actions_v01",
        )
        manifest = self.build(value)
        self.assertEqual(sorted(manifest["animations"]), ["charger.east.charge", "ranged.north.shoot"])
        atlas = json.loads((self.out / "atlas.json").read_text(encoding="utf-8"))
        for frame_id in ("charger.east.charge.0", "ranged.north.shoot.0"):
            self.assertEqual(atlas["sprites"][frame_id]["anchor"], [24, 44])
            self.assertEqual(atlas["sprites"][frame_id]["rect"][2:], [48, 48])
        errors, _infos, _summary = verify.verify_output(self.out, None, False)
        self.assertEqual(errors, [])

    def test_hostile_texture_keys_are_rejected_before_any_write(self):
        write_source(self.source, poses=[{"foot": (24, 44)}])
        animations = {"ranger.south.idle": {"frames": ["a.0"], "fps": 4, "loop": True}}
        for bad in (
            "enemies/../../etc/passwd",
            "../enemies",
            "/abs/enemies",
            "enemies.png",
            ".",
            "..",
            "",
            "1enemies",
            "enemies ",
            "enem ies",
        ):
            value = recipe({"raw": self.source}, [frame(id="a.0")], animations, texture_key=bad)
            self.assert_fails(value, contains="texture_key")
            self.assertFalse(self.out.exists())

    def test_non_string_texture_key_is_rejected(self):
        write_source(self.source, poses=[{"foot": (24, 44)}])
        animations = {"ranger.south.idle": {"frames": ["a.0"], "fps": 4, "loop": True}}
        value = recipe({"raw": self.source}, [frame(id="a.0")], animations, texture_key=["enemies"])
        self.assert_fails(value, contains="texture_key")

    def test_unknown_top_level_key_is_still_rejected(self):
        write_source(self.source, poses=[{"foot": (24, 44)}])
        animations = {"ranger.south.idle": {"frames": ["a.0"], "fps": 4, "loop": True}}
        value = recipe({"raw": self.source}, [frame(id="a.0")], animations, texture_id="enemies")
        self.assert_fails(value, contains="unknown config keys")

    def test_verify_rejects_a_recipe_texture_key_that_does_not_match_the_atlas(self):
        path = self.enemy_recipe(name="enemies_original.json")
        build.build_artifacts(path, self.out)
        changed = json.loads(path.read_text(encoding="utf-8"))
        changed["texture_key"] = "minions"
        other = self.write_recipe(changed, name="enemies_changed.json")
        errors, _infos, _summary = verify.verify_output(self.out, other, False)
        self.assertTrue(any("recipe file changed since the build" in line for line in errors), errors)
        self.assertTrue(any("atlas textures.minions is missing" in line for line in errors), errors)
        self.assertTrue(any("manifest texture id is 'enemies'" in line for line in errors), errors)

    def test_verify_rejects_a_vanished_texture_file(self):
        path = self.enemy_recipe()
        build.build_artifacts(path, self.out)
        (self.out / "enemies.png").unlink()
        errors, _infos, _summary = verify.verify_output(self.out, path, False)
        self.assertTrue(any("artifact is missing" in line for line in errors), errors)
        self.assertTrue(any("texture is missing" in line for line in errors), errors)

    def test_replace_generated_switches_texture_key_without_prewriting(self):
        path = self.enemy_recipe()
        build.build_artifacts(path, self.out)
        ranger_recipe = json.loads(path.read_text(encoding="utf-8"))
        del ranger_recipe["texture_key"]
        for index, entry in enumerate(ranger_recipe["frames"]):
            entry["id"] = f"ranger.south.attack.{index}"
            entry["action"] = "attack"
            entry["facing"] = "south"
        ranger_recipe["animations"] = {
            "ranger.south.attack": {"frames": [entry["id"] for entry in ranger_recipe["frames"]], "fps": 6, "loop": False}
        }
        ranger_recipe["resource_prefix"] = "res://art/production/p1/ranger_actions_v01"
        other = self.write_recipe(ranger_recipe, name="ranger_again.json")
        with self.assertRaises(build.ConfigError) as caught:
            build.build_artifacts(other, self.out)
        self.assertIn("not empty", str(caught.exception))
        manifest = build.build_artifacts(other, self.out, replace_generated=True)
        self.assertEqual(manifest["texture"]["id"], "ranger")
        self.assertTrue((self.out / "ranger.png").is_file())
        self.assertTrue((self.out / "enemies.png").is_file())
        errors, _infos, _summary = verify.verify_output(self.out, other, False)
        self.assertEqual(errors, [])

    def test_texture_filename_cannot_escape_the_output_directory(self):
        self.out.mkdir(parents=True)
        with self.assertRaises(build.ConfigError) as caught:
            build.guard_output(self.out, True, "../enemies.png")
        self.assertIn("inside the output directory", str(caught.exception))


class FrozenRangerArtifactTests(unittest.TestCase):
    """Read-only regression over the accepted ranger batch already on disk."""

    REPO_ROOT = Path(__file__).resolve().parents[4]
    OUTPUT = REPO_ROOT / "art" / "production" / "p1" / "ranger_actions_v01"
    RECIPE = REPO_ROOT / "docs" / "art-production" / "p1-ranger-actions-v01" / "recipe.final.json"

    def setUp(self):
        if not self.RECIPE.is_file() or not (self.OUTPUT / "manifest.json").is_file():
            self.skipTest("the accepted ranger batch is not present in this checkout")

    def test_default_texture_key_keeps_the_frozen_ranger_hashes(self):
        recipe_value = json.loads(self.RECIPE.read_text(encoding="utf-8"))
        self.assertNotIn("texture_key", recipe_value)
        self.assertEqual(build.texture_spec(recipe_value), ("ranger", "ranger.png"))
        self.assertEqual(
            build.sha256_file(self.OUTPUT / "ranger.png"), FROZEN_RANGER_TEXTURE_SHA256
        )
        self.assertEqual(build.sha256_file(self.OUTPUT / "atlas.json"), FROZEN_RANGER_ATLAS_SHA256)
        manifest = json.loads((self.OUTPUT / "manifest.json").read_text(encoding="utf-8"))
        self.assertEqual(manifest["texture"]["id"], "ranger")
        self.assertEqual(manifest["texture"]["path"], "res://art/production/p1/ranger_actions_v01/ranger.png")

    def test_frozen_batch_still_verifies_read_only(self):
        before = {
            name: (self.OUTPUT / name).stat().st_mtime_ns
            for name in ("manifest.json", "atlas.json", "ranger.png")
        }
        errors, infos, _summary = verify.verify_output(self.OUTPUT, self.RECIPE, False)
        self.assertEqual(errors, [])
        after = {
            name: (self.OUTPUT / name).stat().st_mtime_ns
            for name in ("manifest.json", "atlas.json", "ranger.png")
        }
        self.assertEqual(before, after, "verification must not write to the batch directory")
        self.assertEqual(
            build.sha256_file(self.OUTPUT / "ranger.png"), FROZEN_RANGER_TEXTURE_SHA256
        )
        self.assertEqual(build.sha256_file(self.OUTPUT / "atlas.json"), FROZEN_RANGER_ATLAS_SHA256)
        self.assertTrue(
            any("unmanaged entry" in line for line in infos), infos
        )


class ReviewTests(PipelineTestCase):
    def test_review_writes_previews_outside_the_version_directory(self):
        write_source(self.source, poses=[{"foot": (24, 44)}, {"foot": (72, 44), "height": 21}])
        value = recipe(
            {"raw": self.source},
            [
                frame(id="a.0", crop=[0, 0, 48, 48], action="walk", facing="south"),
                frame(id="a.1", crop=[48, 0, 48, 48], action="walk", facing="south"),
            ],
            {"ranger.south.walk": {"frames": ["a.0", "a.1"], "fps": 6, "loop": True}},
        )
        self.build(value)
        previews = self.root / "previews"
        code = review.main(
            ["--output", str(self.out), "--out", str(previews), "--scale", "2", "--gray", "--gif"]
        )
        self.assertEqual(code, 0)
        self.assertTrue((previews / "contact_2x.png").is_file())
        self.assertTrue((previews / "contact_2x_gray.png").is_file())
        self.assertTrue((previews / "gif" / "ranger.south.walk.gif").is_file())
        with Image.open(previews / "contact_2x_gray.png") as sheet:
            gray = sheet.convert("RGB")
        body_pixel = gray.getpixel((48, 90))
        self.assertEqual(body_pixel[0], body_pixel[1])
        self.assertEqual(body_pixel[1], body_pixel[2])

    def test_review_refuses_to_write_into_the_version_directory(self):
        write_source(self.source, poses=[{"foot": (24, 44)}])
        value = recipe(
            {"raw": self.source},
            [frame(id="a.0")],
            {"ranger.south.idle": {"frames": ["a.0"], "fps": 4, "loop": True}},
        )
        self.build(value)
        code = review.main(["--output", str(self.out), "--out", str(self.out)])
        self.assertEqual(code, 1)


if __name__ == "__main__":
    unittest.main()
