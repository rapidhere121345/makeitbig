from __future__ import annotations

import hashlib
import importlib.util
import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

from PIL import Image, ImageDraw


MODULE_PATH = Path(__file__).resolve().parents[1] / "verify.py"
SPEC = importlib.util.spec_from_file_location("scene_rework_verify", MODULE_PATH)
verify = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
sys.modules[SPEC.name] = verify
SPEC.loader.exec_module(verify)


def _sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _make_ground() -> Image.Image:
    image = Image.new("RGBA", (1024, 640), "#202A33")
    draw = ImageDraw.Draw(image)
    rectangles = (
        (37, 83, 331, 292, "#2D3943"),
        (386, 41, 704, 217, "#39474F"),
        (746, 109, 983, 391, "#46535A"),
        (105, 341, 391, 583, "#586469"),
        (455, 283, 795, 451, "#6C7579"),
        (824, 458, 994, 598, "#808889"),
        (259, 498, 411, 606, "#98A0A0"),
        (608, 508, 782, 604, "#2D3943"),
    )
    for rectangle in rectangles:
        draw.rectangle(rectangle[:4], fill=rectangle[4])
    return image


def _make_cells(atlas_key: str) -> Image.Image:
    contract = verify.ATLAS_CONTRACTS[atlas_key]
    image = Image.new("RGBA", contract.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    colors = (
        (45, 57, 67, 255), (57, 71, 79, 255), (70, 83, 90, 255),
        (104, 117, 121, 255), (156, 166, 168, 255), (211, 203, 181, 255),
        (151, 83, 61, 255), (96, 116, 126, 255), (175, 125, 76, 255),
        (126, 145, 136, 255), (216, 171, 143, 255), (82, 97, 111, 255),
    )
    cell_width, cell_height = contract.cell_size
    for index in range(len(contract.sprite_ids)):
        x = index * cell_width
        for offset in range(4):
            color = colors[(index + offset) % len(colors)]
            draw.rectangle(
                (
                    x + 3 + offset * 4,
                    3 + offset * 5,
                    x + cell_width - 3 - offset * 4,
                    cell_height - 3 - offset * 5,
                ),
                outline=color,
                width=2,
            )
    return image


def _atlas_json() -> dict:
    textures: dict[str, dict] = {}
    sprites: dict[str, dict] = {}
    for atlas_key, contract in verify.ATLAS_CONTRACTS.items():
        textures[atlas_key] = {
            "path": f"{verify.EXPECTED_RESOURCE_PREFIX}/{atlas_key}.png",
            "width": contract.size[0],
            "height": contract.size[1],
        }
        for index, sprite_id in enumerate(contract.sprite_ids):
            x, y, width, height = verify._expected_rect(atlas_key, sprite_id)
            anchor = (
                [512, 640]
                if sprite_id == "scene.ground"
                else list(contract.anchors[index])
            )
            sprites[sprite_id] = {
                "texture": atlas_key,
                "rect": [x, y, width, height],
                "anchor": anchor,
            }
    return {
        "schema_version": 1,
        "native_view": [640, 360],
        "textures": textures,
        "sprites": sprites,
        "animations": {},
    }


def _layout() -> dict:
    return {
        "world_size": [1024, 640],
        "hero_start": [430, 360],
        "boss_feet": [625, 360],
        "tower_feet": [175, 405],
        "enemy_positions": [[300, 290], [480, 470], [570, 235]],
        "decals": [
            {"id": "ground.snow_wedge", "feet": [180, 180]},
            {"id": "ground.snow_wedge", "feet": [360, 210]},
            {"id": "ground.snow_strip", "feet": [390, 430]},
            {"id": "ground.snow_strip", "feet": [560, 300]},
            {"id": "ground.rubble_apron", "feet": [630, 260]},
            {"id": "ground.foundation", "feet": [850, 510]},
        ],
        "structures": [
            {"id": "ruin.wall_corner", "feet": [130, 420]},
            {"id": "ruin.wall_corner", "feet": [520, 390]},
            {"id": "ruin.gate", "feet": [420, 160]},
            {"id": "ruin.low_pier", "feet": [710, 470]},
            {"id": "ruin.broken_wall", "feet": [920, 230]},
        ],
    }


def _write_fixture(root: Path) -> Path:
    output = root / "output"
    output.mkdir()
    for atlas_key in verify.ATLAS_CONTRACTS:
        image = _make_ground() if atlas_key == "ground" else _make_cells(atlas_key)
        image.save(output / f"{atlas_key}.png")
    (output / "atlas.json").write_text(json.dumps(_atlas_json(), indent=2) + "\n", encoding="utf-8")
    (output / "layout.json").write_text(json.dumps(_layout(), indent=2) + "\n", encoding="utf-8")
    Image.new("RGBA", (256, 128), (0, 0, 0, 0)).save(output / "contact_sheet.png")
    config = root / "recipe.json"
    config.write_text(json.dumps({"schema_version": 1}) + "\n", encoding="utf-8")
    source = root / "source.png"
    Image.new("RGBA", (64, 64), (45, 57, 67, 255)).save(source)
    artifacts = []
    for name in verify.EXPECTED_ARTIFACTS:
        path = output / name
        artifacts.append({"path": str(path), "sha256": _sha(path), "bytes": path.stat().st_size})
    (output / "manifest.json").write_text(
        json.dumps(
            {
                "schema_version": 1,
                "config_path": str(config),
                "config_sha256": _sha(config),
                "sources": {
                    "ground": {
                        "path": str(source),
                        "sha256": _sha(source),
                        "width": 64,
                        "height": 64,
                    }
                },
                "artifacts": artifacts,
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    return output


def _clone_fixture(source: Path, name: str) -> Path:
    target = source.parent / name
    shutil.copytree(source, target)
    for filename in ("recipe.json", "source.png"):
        shutil.copy2(source.parent / filename, target / filename)
    manifest_path = target / "manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    for artifact in manifest["artifacts"]:
        artifact["path"] = str(target / Path(artifact["path"]).name)
    manifest["config_path"] = str(target / Path(manifest["config_path"]).name)
    for source in manifest["sources"].values():
        source["path"] = str(target / Path(source["path"]).name)
    manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
    return target


class SceneReworkVerifyTests(unittest.TestCase):
    def setUp(self) -> None:
        self._temporary = tempfile.TemporaryDirectory(prefix="scene_rework_verify_")
        self.root = Path(self._temporary.name)
        self.fixture = _write_fixture(self.root)

    def tearDown(self) -> None:
        self._temporary.cleanup()

    def test_valid_delivery_and_mechanical_qa(self) -> None:
        errors, atlas, images = verify.verify_output(self.fixture)
        self.assertEqual(errors, [])
        self.assertEqual(len(atlas["sprites"]), 19)
        self.assertEqual(len(images), 7)
        qa = self.root / "qa"
        verify._write_mechanical_qa(self.fixture, atlas, images, qa)
        report = json.loads((qa / "QA_REPORT.json").read_text(encoding="utf-8"))
        self.assertEqual(len(report["artifacts"]), 8 * 4)
        self.assertTrue((qa / "atlas_ground_25pct.png").is_file())

    def test_exact_sprite_and_atlas_contracts(self) -> None:
        output = _clone_fixture(self.fixture, "contracts")
        atlas = json.loads((output / "atlas.json").read_text(encoding="utf-8"))
        del atlas["sprites"]["boss.core_phase2"]
        atlas["textures"]["unexpected"] = atlas["textures"]["boss_core"]
        atlas["sprites"]["ranger.south.idle"]["rect"] = [1, 0, 32, 48]
        atlas["sprites"]["ruin.gate"]["anchor"] = [63, 120]
        (output / "atlas.json").write_text(json.dumps(atlas), encoding="utf-8")
        errors, _atlas, _images = verify.verify_output(output)
        self.assertTrue(any("exactly 19" in error for error in errors))
        self.assertTrue(any("7-atlas contract" in error for error in errors))
        self.assertTrue(any("ranger.south.idle rect differs" in error for error in errors))
        self.assertTrue(any("ruin.gate anchor differs" in error for error in errors))

    def test_alpha_padding_palette_and_ground(self) -> None:
        output = _clone_fixture(self.fixture, "pixels")
        with Image.open(output / "ranger.png") as opened:
            ranger = opened.copy()
        south_x = verify._expected_rect("ranger", "ranger.south.idle")[0]
        ranger.putpixel((south_x + 16, 0), (45, 57, 67, 128))
        ranger.save(output / "ranger.png")
        with Image.open(output / "decals.png") as opened:
            decals = opened.copy()
        wedge_x = verify._expected_rect("decals", "ground.snow_wedge")[0]
        strip_x = verify._expected_rect("decals", "ground.snow_strip")[0]
        decals.putpixel((wedge_x + 1, 2), (45, 57, 67, 255))
        for offset, color in enumerate(
            ((1, 2, 3, 255), (4, 5, 6, 255), (7, 8, 9, 255), (10, 11, 12, 255), (13, 14, 15, 255))
        ):
            decals.putpixel((strip_x + 10 + offset, 10), color)
        decals.save(output / "decals.png")
        errors, _atlas, _images = verify.verify_output(output)
        self.assertTrue(any("ranger.south.idle has non-binary alpha" in error for error in errors))
        self.assertTrue(any("ground.snow_wedge violates the minimum 2px" in error for error in errors))
        self.assertTrue(any("ground.snow_strip uses 9 opaque colors" in error for error in errors))

        tiled_output = _clone_fixture(self.fixture, "ground")
        tile = Image.new("RGBA", (64, 64), (45, 57, 67, 255))
        tiled = Image.new("RGBA", (1024, 640))
        for y in range(0, 640, 64):
            for x in range(0, 1024, 64):
                tiled.paste(tile, (x, y))
        tiled.save(tiled_output / "ground.png")
        tiled_errors, _tiled_atlas, _tiled_images = verify.verify_output(tiled_output)
        self.assertTrue(any("scene.ground is exactly repetitive" in error for error in tiled_errors))

    def test_manifest_hash_and_artifact_set(self) -> None:
        output = _clone_fixture(self.fixture, "manifest")
        (output / "decals.png").write_bytes((output / "decals.png").read_bytes() + b"tampered")
        manifest_path = output / "manifest.json"
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        for artifact in manifest["artifacts"]:
            if Path(artifact["path"]).name == "ruins.png":
                artifact["path"] = str(output / "not-real.png")
                break
        else:
            self.fail("fixture manifest has no ruins artifact")
        manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
        errors, _atlas, _images = verify.verify_output(output)
        self.assertTrue(any("hash mismatch: decals.png" in error for error in errors))
        self.assertTrue(any("missing: not-real.png" in error for error in errors))
        self.assertTrue(any("missing=['ruins.png']" in error for error in errors))

    def test_layout_bounds_reuse_and_duplicate(self) -> None:
        output = _clone_fixture(self.fixture, "layout")
        layout = _layout()
        layout["decals"][0]["feet"] = [10, 10]
        layout["decals"].append(dict(layout["decals"][1]))
        layout["structures"][0]["id"] = "ground.foundation"
        (output / "layout.json").write_text(json.dumps(layout), encoding="utf-8")
        errors, _atlas, _images = verify.verify_output(output)
        self.assertTrue(any("layout decals[0] anchored cell lies outside" in error for error in errors))
        self.assertTrue(any("duplicates placement ground.snow_wedge" in error for error in errors))
        self.assertTrue(any("layout structures IDs must be from" in error for error in errors))

    def test_recipe_and_source_provenance_hashes(self) -> None:
        output = _clone_fixture(self.fixture, "provenance")
        (output / "recipe.json").write_text("{\"schema_version\": 2}\n", encoding="utf-8")
        (output / "source.png").write_bytes(b"not a real source PNG")
        errors, _atlas, _images = verify.verify_output(output)
        self.assertTrue(any("config hash mismatch" in error for error in errors))
        self.assertTrue(any("source ground hash mismatch" in error for error in errors))
        self.assertTrue(any("source ground PNG cannot be opened" in error for error in errors))


if __name__ == "__main__":
    unittest.main()
