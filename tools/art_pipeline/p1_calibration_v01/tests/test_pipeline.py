import json
import sys
import tempfile
import os
import shutil
import unittest
from pathlib import Path

from PIL import Image


PIPELINE_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PIPELINE_DIR))

import build  # noqa: E402
import verify  # noqa: E402


PALETTE = ["#101820", "#304050", "#d0d8e0", "#802020"]
PARSED_PALETTE = {build.parse_hex_color(color, "palette") for color in PALETTE}


def _write_source(path, size=(128, 128), foreground=(16, 24, 32, 255), background=(0, 0, 0, 0), box=(40, 48, 88, 80)):
    image = Image.new("RGBA", size, background)
    for y in range(box[1], box[3]):
        for x in range(box[0], box[2]):
            image.putpixel((x, y), foreground)
    image.save(path, format="PNG")


def _recipe(source, **overrides):
    sprite = {
        "id": "sprite_a",
        "source": "source_a",
        "cell": [0, 0],
        "atlas": "atlas_a",
        "anchor": [24, 24],
        "fit": [32, 32],
    }
    sprite.update(overrides.get("sprite", {}))
    value = {
        "schema_version": 1,
        "resource_prefix": "res://art/production/p1/calibration_v01_test",
        "native_view": [640, 360],
        "palette": PALETTE,
        "sources": {
            "source_a": {
                "path": str(source),
                "grid": [1, 1],
                "background": {"mode": "alpha", "colors": [], "tolerance": 0.0},
            }
        },
        "atlases": {"atlas_a": {"cell_size": [48, 48], "columns": 8, "padding": 2}},
        "sprites": [sprite],
        "animations": {"anim_a": {"frames": ["sprite_a"], "fps": 2, "loop": True}},
    }
    value.update(overrides.get("recipe", {}))
    return value


class PipelineTest(unittest.TestCase):
    def setUp(self):
        self._temp = tempfile.TemporaryDirectory(prefix="makeitbig-p1-calibration-", dir="/tmp")
        self.root = Path(self._temp.name)
        self.source = self.root / "source.png"
        _write_source(self.source)

    def tearDown(self):
        self._temp.cleanup()

    def _run(self, config, output):
        config_path = self.root / "recipe.json"
        with config_path.open("w", encoding="utf-8") as handle:
            json.dump(config, handle)
        build.build_artifacts(config_path, output)
        return verify.verify_output(output, config_path)[0]

    def test_alpha_build_and_verify(self):
        output = self.root / "out"
        self.assertEqual(self._run(_recipe(self.source), output), [])
        contract = json.loads((output / "atlas.json").read_text(encoding="utf-8"))
        rect = contract["sprites"]["sprite_a"]["rect"]
        self.assertEqual(rect, [0, 0, 48, 48])
        with Image.open(output / "atlas_a.png") as atlas:
            pixels = set(atlas.getdata())
        self.assertTrue(pixels <= {(0, 0, 0, 0), (16, 24, 32, 255)})

    def test_edge_colors_do_not_remove_enclosed_key(self):
        image = Image.new("RGBA", (64, 64), (208, 216, 224, 255))
        for y in range(20, 30):
            for x in range(20, 30):
                image.putpixel((x, y), (48, 64, 80, 255))
        for y in range(40, 46):
            for x in range(40, 46):
                image.putpixel((x, y), (128, 32, 32, 255))
        image.save(self.source, format="PNG")
        config = _recipe(self.source)
        config["sources"]["source_a"]["background"] = {
            "mode": "edge_colors",
            "colors": ["#d0d8e0"],
            "tolerance": 0.0,
        }
        config["sprites"][0]["anchor"] = [24, 40]
        output = self.root / "out"
        self.assertEqual(self._run(config, output), [])
        contract = json.loads((output / "atlas.json").read_text(encoding="utf-8"))
        rect = contract["sprites"]["sprite_a"]["rect"]
        self.assertEqual(rect, [0, 0, 48, 48])

    def test_color_key_removes_contained_hole(self):
        _write_source(self.source, foreground=(16, 24, 32, 255), background=(208, 216, 224, 255))
        config = _recipe(self.source)
        config["sources"]["source_a"]["background"] = {
            "mode": "color_key",
            "colors": ["#d0d8e0"],
            "tolerance": 0.0,
        }
        output = self.root / "out"
        self.assertEqual(self._run(config, output), [])
        with Image.open(output / "atlas_a.png") as atlas:
            self.assertIn((0, 0, 0, 0), set(atlas.getdata()))

    def test_color_key_rgb_distance_threshold(self):
        image = Image.new("RGB", (32, 32), (0, 255, 0))
        image.putpixel((16, 16), (50, 210, 50))
        image.putpixel((17, 16), (150, 120, 20))
        image.save(self.source, format="PNG")
        cleaned = build._remove_color_key(
            image.convert("RGBA"),
            (build.parse_hex_color("#00ff00", "key"),),
            100.0,
        )
        self.assertEqual(cleaned.getpixel((0, 0))[3], 0)
        self.assertEqual(cleaned.getpixel((16, 16))[3], 0)
        self.assertEqual(cleaned.getpixel((17, 16))[3], 255)

    def test_keep_rows_applies_after_fit(self):
        image = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
        for y in range(8, 56):
            for x in range(20, 44):
                image.putpixel((x, y), (16, 24, 32, 255))
        image.save(self.source, format="PNG")
        config = _recipe(self.source, sprite={"fit": [32, 32], "keep_rows": [8, 23], "anchor": [24, 40]})
        output = self.root / "out"
        self.assertEqual(self._run(config, output), [])
        contract = json.loads((output / "atlas.json").read_text(encoding="utf-8"))
        self.assertEqual(contract["sprites"]["sprite_a"]["rect"][3], 48)
        with Image.open(output / "atlas_a.png") as atlas:
            self.assertEqual(atlas.getchannel("A").getbbox(), (16, 8, 32, 23))

    def test_scale_group_uses_one_factor(self):
        source_b = self.root / "source_b.png"
        _write_source(source_b, size=(64, 64), foreground=(48, 64, 80, 255), box=(10, 10, 54, 38))
        config = _recipe(self.source)
        config["sources"]["source_b"] = {
            "path": str(source_b),
            "grid": [1, 1],
            "background": {"mode": "alpha", "colors": [], "tolerance": 0.0},
        }
        config["sprites"].append(
            {
                "id": "sprite_b",
                "source": "source_b",
                "cell": [0, 0],
                "atlas": "atlas_a",
                "anchor": [24, 40],
                "fit": [32, 32],
                "scale_group": "group",
            }
        )
        config["sprites"][0]["scale_group"] = "group"
        config["sprites"][0]["anchor"] = [24, 40]
        config["animations"]["anim_a"]["frames"] = ["sprite_a", "sprite_b"]
        output = self.root / "out"
        self.assertEqual(self._run(config, output), [])
        contract = json.loads((output / "atlas.json").read_text(encoding="utf-8"))
        self.assertEqual(contract["sprites"]["sprite_a"]["rect"], [0, 0, 48, 48])
        self.assertEqual(contract["sprites"]["sprite_b"]["rect"], [48, 0, 48, 48])
        with Image.open(output / "atlas_a.png") as atlas:
            self.assertEqual(atlas.crop((0, 0, 48, 48)).getchannel("A").getbbox(), (8, 19, 40, 40))
            self.assertEqual(atlas.crop((48, 0, 96, 48)).getchannel("A").getbbox(), (10, 22, 39, 40))

    def test_nonzero_crop_and_grid_cells(self):
        _write_source(self.source, size=(128, 128), box=(84, 80, 108, 96))
        for explicit in (False, True):
            config = _recipe(self.source)
            config["sources"]["source_a"]["grid"] = [2, 2]
            config["sprites"][0]["cell"] = [1, 1]
            if explicit:
                config["sprites"][0]["crop"] = [64, 64, 64, 64]
            self.assertEqual(self._run(config, self.root / str(explicit)), [])

    def test_layers_preserve_full_cell_origin_and_reconstruct(self):
        config = _recipe(self.source, sprite={"id": "z_full", "anchor": [24, 40]})
        config["animations"] = {}
        for name, rows in (("a_upper", [0, 30]), ("b_base", [30, 48])):
            config["sprites"].append(dict(config["sprites"][0], id=name, keep_rows=rows))
        output = self.root / "out"
        self.assertEqual(self._run(config, output), [])
        contract = json.loads((output / "atlas.json").read_text())
        self.assertEqual(contract["sprites"]["z_full"]["rect"], [0, 0, 48, 48])
        with Image.open(output / "atlas_a.png") as atlas:
            self.assertEqual(atlas.size, (384, 48))
            full = atlas.crop((0, 0, 48, 48))
            upper = atlas.crop((48, 0, 96, 48))
            base = atlas.crop((96, 0, 144, 48))
            self.assertEqual(Image.alpha_composite(base, upper).tobytes(), full.tobytes())

    def test_layer_metadata_must_exactly_cover_cell_rows(self):
        # Each interval is individually valid and matches its recipe. Reject
        # the relationship itself, not an unrelated hash or out-of-range row.
        for problem, upper_rows in (("gap", [0, 23]), ("overlap", [0, 25])):
            with self.subTest(problem=problem):
                config = _recipe(self.source, sprite={"id": "upper", "anchor": [24, 40], "keep_rows": upper_rows})
                config["sprites"].append(dict(config["sprites"][0], id="base", keep_rows=[24, 48]))
                config["animations"] = {}
                errors = self._run(config, self.root / f"out-{problem}")
                self.assertEqual(len(errors), 1, errors)
                self.assertIn(f"keep_rows has a {problem}", errors[0])

    def test_layer_metadata_requires_declared_mask(self):
        config = _recipe(self.source, sprite={"id": "upper", "anchor": [24, 40], "keep_rows": [0, 24]})
        config["sprites"].append(dict(config["sprites"][0], id="base", keep_rows=[24, 48]))
        config["animations"] = {}
        output = self.root / "out"
        self.assertEqual(self._run(config, output), [])
        path = output / "atlas.json"
        original = json.loads(path.read_text())
        for value in (None, [0, 23], [0, 24.5], [0, True]):
            with self.subTest(value=value):
                data = json.loads(json.dumps(original))
                if value is None:
                    del data["sprites"]["upper"]["keep_rows"]
                else:
                    data["sprites"]["upper"]["keep_rows"] = value
                path.write_text(json.dumps(data))
                errors = verify.verify_output(output)[0]
                self.assertIn("sprite upper keep_rows mismatch", errors)

    def test_valid_slot_and_texture_must_match_recipe(self):
        config = _recipe(self.source, sprite={"id": "sprite_a", "anchor": [24, 40]})
        config["animations"] = {}
        config["sprites"].append(dict(config["sprites"][0], id="sprite_b"))
        config["atlases"]["atlas_b"] = {"cell_size": [48, 48], "columns": 1, "padding": 2}
        output = self.root / "out"
        self.assertEqual(self._run(config, output), [])
        path = output / "atlas.json"
        data = json.loads(path.read_text())
        data["sprites"]["sprite_a"]["rect"] = [48, 0, 48, 48]
        data["sprites"]["sprite_b"]["texture"] = "atlas_b"
        path.write_text(json.dumps(data))
        errors = verify.verify_output(output)[0]
        self.assertTrue(any("configured aligned full cell" in error for error in errors))

    def test_short_hex_colors(self):
        self.assertEqual(build.parse_hex_color("#abc", "color"), (170, 187, 204, 255))
        self.assertEqual(build.parse_hex_color("#abcd", "color"), (170, 187, 204, 221))

    def test_relative_output_paths_round_trip(self):
        previous = Path.cwd()
        try:
            os.chdir(self.root)
            self.assertEqual(self._run(_recipe(self.source), Path('relative_output')), [])
            build.build_artifacts(self.root / 'recipe.json', Path('relative_output'), replace_generated=True)
            self.assertEqual(verify.verify_output(Path('relative_output'))[0], [])
        finally:
            os.chdir(previous)

    def test_invalid_cell_and_anchor_are_rejected(self):
        output = self.root / 'out'
        self.assertEqual(self._run(_recipe(self.source), output), [])
        path = output / 'atlas.json'
        data = json.loads(path.read_text())
        data['sprites']['sprite_a']['rect'] = [1, 1, 32, 32]
        data['sprites']['sprite_a']['anchor'] = [100, 100]
        path.write_text(json.dumps(data))
        errors = verify.verify_output(output)[0]
        self.assertTrue(any('aligned full cell' in error for error in errors))
        self.assertTrue(any('cell-local anchor' in error for error in errors))

    def test_opaque_exact_tiles_and_zero_padding(self):
        image = Image.new("RGBA", (128, 128), (16, 24, 32, 255))
        image.save(self.source, format="PNG")
        config = _recipe(self.source, sprite={"fit": [64, 64], "anchor": [32, 64]})
        config["sources"]["source_a"]["background"] = {"mode": "opaque", "colors": [], "tolerance": 0.0}
        config["atlases"]["atlas_a"] = {"cell_size": [64, 64], "columns": 1, "padding": 0}
        output = self.root / "out"
        self.assertEqual(self._run(config, output), [])
        with Image.open(output / "atlas_a.png") as atlas:
            self.assertEqual(atlas.size, (64, 64))
            self.assertTrue(set(atlas.getdata()) <= {(16, 24, 32, 255)})

    def test_clipping_is_an_error(self):
        _write_source(self.source, foreground=(16, 24, 32, 255), box=(0, 0, 64, 64))
        output = self.root / "out"
        config = _recipe(self.source, sprite={"anchor": [24, 40]})
        errors = self._run(config, output)
        self.assertTrue(any(error.startswith("clipping:") for error in errors))

    def test_replacement_requires_manifest_owned_exact_paths(self):
        output = self.root / "out"
        self.assertEqual(self._run(_recipe(self.source), output), [])
        unmanaged = output / "unmanaged.txt"
        unmanaged.write_text("keep me", encoding="utf-8")
        config_path = self.root / "recipe.json"
        with self.assertRaises(build.ConfigError):
            build.build_artifacts(config_path, output, replace_generated=True)
        self.assertEqual(unmanaged.read_text(encoding="utf-8"), "keep me")

    def test_replacement_rejects_artifact_symlinks(self):
        output = self.root / "out"
        self.assertEqual(self._run(_recipe(self.source), output), [])
        target = output / "target.png"
        shutil.copyfile(self.source, target)
        artifact = output / "atlas_a.png"
        artifact.unlink()
        artifact.symlink_to(target)
        target_bytes = target.read_bytes()
        with self.assertRaises(build.ConfigError):
            build.build_artifacts(self.root / "recipe.json", output, replace_generated=True)
        self.assertEqual(target.read_bytes(), target_bytes)


if __name__ == "__main__":
    unittest.main()
