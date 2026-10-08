"""Synthetic, temporary-directory tests for the base_facilities_v01 verifier.

The fixture builds a complete synthetic 8-atlas / 41-sprite calibration recipe
plus the five-slot facilities atlas, so the shared generic verifier is also
exercised end to end.  Nothing is written outside a tempfile directory.
"""

from __future__ import annotations

import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path

from PIL import Image, ImageDraw


MODULE_PATH = Path(__file__).resolve().parents[1] / "verify.py"
SPEC = importlib.util.spec_from_file_location("base_facilities_verify", MODULE_PATH)
verify = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
sys.modules[SPEC.name] = verify
SPEC.loader.exec_module(verify)

ANCHORS: dict[str, tuple[int, int]] = {
    "ranger": (16, 44),
    "enemies": (24, 44),
    "boss_body": (48, 120),
    "boss_hands": (24, 56),
    "boss_core": (24, 104),
    "tower": (64, 184),
    "terrain": (32, 60),
    "ground": (32, 64),
}

SPRITE_IDS: dict[str, tuple[str, ...]] = {
    "ranger": (
        "ranger.south.idle", "ranger.south.walk_a", "ranger.south.walk_b", "ranger.south.shoot",
        "ranger.north.idle", "ranger.north.walk_a", "ranger.north.walk_b", "ranger.north.shoot",
        "ranger.west.idle", "ranger.west.walk_a", "ranger.west.walk_b", "ranger.west.shoot",
        "ranger.east.idle", "ranger.east.walk_a", "ranger.east.walk_b", "ranger.east.shoot",
    ),
    "enemies": (
        "enemy.melee.idle", "enemy.melee.windup", "enemy.melee.active", "enemy.melee.recover",
        "enemy.charger.idle", "enemy.charger.windup", "enemy.charger.active", "enemy.charger.recover",
        "enemy.ranged.idle", "enemy.ranged.windup", "enemy.ranged.active", "enemy.ranged.recover",
    ),
    "boss_body": ("boss.body_phase1", "boss.body_phase2"),
    "boss_hands": ("boss.hand_left", "boss.hand_right"),
    "boss_core": ("boss.core_phase1", "boss.core_phase2"),
    "tower": ("tower.base", "tower.upper"),
    "terrain": ("terrain.snow", "terrain.rubble", "terrain.wall", "terrain.fence"),
    "ground": ("terrain.ground",),
}

ATLAS_RECIPE: dict[str, dict] = {
    "ranger": {"cell_size": [32, 48], "columns": 4, "padding": 2},
    "enemies": {"cell_size": [48, 48], "columns": 4, "padding": 2},
    "boss_body": {"cell_size": [96, 128], "columns": 2, "padding": 2},
    "boss_hands": {"cell_size": [48, 64], "columns": 2, "padding": 2},
    "boss_core": {"cell_size": [48, 112], "columns": 2, "padding": 2},
    "tower": {"cell_size": [128, 192], "columns": 2, "padding": 2},
    "terrain": {"cell_size": [64, 64], "columns": 4, "padding": 2},
    "ground": {"cell_size": [64, 64], "columns": 1, "padding": 0},
    "facilities": {"cell_size": [128, 128], "columns": 5, "padding": 2},
}

ANIMATIONS: dict[str, dict] = {
    name: {
        "frames": [f"ranger.{name}.walk_a", f"ranger.{name}.idle", f"ranger.{name}.walk_b", f"ranger.{name}.idle"],
        "fps": 8,
        "loop": True,
    }
    for name in ("south", "north", "west", "east")
}

KEEP_ROWS = {"tower.base": [148, 192], "tower.upper": [0, 148]}

PALETTE = (
    "#111820", "#1d2731", "#2d3943", "#46515a", "#71808a", "#aaafab",
    "#d3cbb5", "#e9ddc3", "#7f94ad", "#b0c4d8", "#5b4036", "#896043",
    "#bb713d", "#eead56", "#70578d", "#b17cc4", "#bd4653", "#ed7370",
    "#61a6a5", "#729161", "#a2bc80", "#29343e", "#33404a", "#202a33",
    "#39262e", "#76402f",
)


def _hex_to_rgba(value: str) -> tuple[int, int, int, int]:
    return int(value[1:3], 16), int(value[3:5], 16), int(value[5:7], 16), 255


def _sha(path: Path) -> str:
    return verify._sha256(path)


class BaseFacilitiesVerifyTests(unittest.TestCase):
    """Every fixture is written under tempfile and removed in tearDown."""

    def setUp(self) -> None:
        self._temporary = tempfile.TemporaryDirectory(prefix="base_facilities_verify_")
        self.root = Path(self._temporary.name)
        self.output = self.root / "output"
        self.output.mkdir(parents=True)
        self.recipe_path = self.root / "recipe.json"
        self.recipe = self._synthetic_recipe()
        self._build_fixture()

    def tearDown(self) -> None:
        self._temporary.cleanup()

    # -- fixture construction -------------------------------------------------

    def _synthetic_recipe(self) -> dict:
        sprites: list[dict] = []
        for atlas, ids in SPRITE_IDS.items():
            cell_width, cell_height = ATLAS_RECIPE[atlas]["cell_size"]
            for index, sprite_id in enumerate(ids):
                entry = {
                    "id": sprite_id,
                    "source": "source",
                    "cell": [index % ATLAS_RECIPE[atlas]["columns"], index // ATLAS_RECIPE[atlas]["columns"]],
                    "atlas": atlas,
                    "anchor": list(ANCHORS[atlas]),
                    "fit": [cell_width, cell_height],
                }
                if sprite_id in KEEP_ROWS:
                    entry["keep_rows"] = list(KEEP_ROWS[sprite_id])
                sprites.append(entry)
        for sprite_id in verify.FACILITY_IDS:
            index = verify.FACILITY_IDS.index(sprite_id)
            sprites.append(
                {
                    "id": sprite_id,
                    "source": "source",
                    "cell": [index, 0],
                    "atlas": "facilities",
                    "anchor": list(verify.FOOT_ANCHOR),
                    "fit": [120, 120],
                }
            )
        return {
            "schema_version": 1,
            "resource_prefix": "res://art/production/p1/base_facilities_v01",
            "native_view": [640, 360],
            "palette": list(PALETTE),
            "sources": {
                "source": {
                    "path": str(self.root / "source.png"),
                    "grid": [8, 8],
                    "background": {"mode": "alpha", "colors": [], "tolerance": 0.0},
                }
            },
            "atlases": {key: dict(value) for key, value in ATLAS_RECIPE.items()},
            "sprites": sprites,
            "animations": json.loads(json.dumps(ANIMATIONS)),
        }

    def _build_fixture(self) -> None:
        Image.new("RGBA", (16, 16), (255, 0, 255, 255)).save(self.root / "source.png")
        self._write_recipe()
        self._write_atlas()
        self._write_layout()
        Image.new("RGBA", (64, 32), (30, 30, 30, 255)).save(self.output / "contact_sheet.png")
        self._restamp_manifest()

    def _write_recipe(self) -> None:
        self.recipe_path.write_text(
            json.dumps(self.recipe, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )

    def _atlas_size(self, key: str) -> tuple[int, int]:
        spec = self.recipe["atlases"][key]
        count = sum(1 for raw in self.recipe["sprites"] if raw["atlas"] == key) or 1
        rows = -(-count // spec["columns"])
        return spec["columns"] * spec["cell_size"][0], rows * spec["cell_size"][1]

    def _atlas_contract(self) -> dict:
        textures = {
            key: {
                "path": f"{self.recipe['resource_prefix'].rstrip('/')}/{key}.png",
                "width": self._atlas_size(key)[0],
                "height": self._atlas_size(key)[1],
            }
            for key in self.recipe["atlases"]
        }
        sprites: dict[str, dict] = {}
        for raw in self.recipe["sprites"]:
            spec = self.recipe["atlases"][raw["atlas"]]
            cell = raw["cell"]
            cell_width, cell_height = spec["cell_size"]
            entry: dict = {
                "texture": raw["atlas"],
                "rect": [cell[0] * cell_width, cell[1] * cell_height, cell_width, cell_height],
                "anchor": list(raw["anchor"]),
            }
            if "keep_rows" in raw:
                entry["keep_rows"] = list(raw["keep_rows"])
            sprites[raw["id"]] = entry
        return {
            "schema_version": 1,
            "native_view": [640, 360],
            "textures": textures,
            "sprites": sprites,
            "animations": json.loads(json.dumps(self.recipe["animations"])),
        }

    def _layout(self) -> dict:
        plan = (
            ("contract", [160, 520]),
            ("loadout", [320, 520]),
            ("forge", [480, 560]),
            ("training", [640, 520]),
            ("proxy", [800, 560]),
        )
        return {
            "schema_version": 1,
            "world_size": [1024, 640],
            "hero_start": [512, 380],
            "tower_feet": [270, 348],
            "facilities": [
                {
                    "id": short,
                    "sprite": f"facility.{short}",
                    "feet": list(feet),
                    "footprint": [96, 48],
                    "split_row": 96,
                    "label": f"facility {index}",
                    "role": f"role {index}",
                }
                for index, (short, feet) in enumerate(plan)
            ],
            "decals": [
                {"id": "ground.snow_strip", "feet": [200 + index * 24, 300]}
                for index in range(11)
            ],
        }

    def _paint_atlas(self) -> None:
        """Facility glyphs are 24x24 pre-scale, clamped 2px inside each cell."""
        # The source is 16x4, so the build's 0.5x fit scale yields 12x12 glyphs.
        image = Image.new("RGBA", verify.ATLAS_SIZE, (0, 0, 0, 0))
        draw = ImageDraw.Draw(image)
        palette = [_hex_to_rgba(item) for item in PALETTE]
        cell_width = verify.CELL_SIZE[0]
        for index in range(len(verify.FACILITY_IDS)):
            origin = index * cell_width
            for offset in range(6):
                inset = offset * 2
                draw.rectangle(
                    (origin + 44 + inset, 88 + inset, origin + 84 - inset, 112 - inset),
                    outline=palette[offset],
                    width=1,
                )
        image.save(self.output / "facilities.png")
        for key in self.recipe["atlases"]:
            if key == "facilities":
                continue
            Image.new("RGBA", self._atlas_size(key), (0, 0, 0, 0)).save(self.output / f"{key}.png")

    def _write_atlas(self) -> None:
        self._paint_atlas()
        self._write_json(self.output / "atlas.json", self._atlas_contract())

    def _write_layout(self) -> None:
        self._write_json(self.output / "layout.json", self._layout())

    def _write_json(self, path: Path, value: dict) -> None:
        path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    def _artifacts(self) -> list[dict]:
        names = [f"{key}.png" for key in self.recipe["atlases"]] + ["atlas.json", "contact_sheet.png"]
        artifacts = []
        for name in names:
            path = self.output / name
            artifacts.append({"path": str(path), "sha256": _sha(path), "bytes": path.stat().st_size})
        return artifacts

    def _restamp_manifest(self) -> None:
        """Rebuild manifest provenance/artifact hashes from the current fixture."""
        source_path = Path(self.recipe["sources"]["source"]["path"])
        manifest = {
            "schema_version": 1,
            "config_path": str(self.recipe_path),
            "config_sha256": _sha(self.recipe_path),
            "resource_prefix": self.recipe["resource_prefix"],
            "sources": {
                "source": {
                    "path": str(source_path),
                    "sha256": _sha(source_path),
                    "width": 16,
                    "height": 16,
                    "grid": [8, 8],
                    "background": {"mode": "alpha", "colors": [], "tolerance": 0.0},
                }
            },
            "artifacts": self._artifacts(),
            "technical_verification": {
                "status": "pending_external_verify",
                "scope": "mechanical output properties only; not visual approval",
            },
        }
        self._write_json(self.output / "manifest.json", manifest)

    def _clone(self, name: str) -> Path:
        """Create an independent copy of the output directory with rewritten paths."""
        target = self.root / name
        if target.exists():
            raise AssertionError(f"clone target already exists: {name}")
        target.mkdir()
        for item in sorted(self.output.iterdir()):
            if item.is_file():
                target.joinpath(item.name).write_bytes(item.read_bytes())
        manifest_path = target / "manifest.json"
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        manifest["artifacts"] = [
            {
                "path": str(target / Path(artifact["path"]).name),
                "sha256": artifact["sha256"],
                "bytes": artifact["bytes"],
            }
            for artifact in manifest["artifacts"]
        ]
        manifest["resource_prefix"] = self.recipe["resource_prefix"]
        self._write_json(manifest_path, manifest)
        return target

    def _read_json(self, path: Path) -> dict:
        return json.loads(path.read_text(encoding="utf-8"))

    def _verify(self, output: Path | None = None, recipe: Path | None = None) -> list[str]:
        errors, _atlas, _images = verify.verify_output(
            output or self.output, recipe or self.recipe_path
        )
        return errors

    def _restamp_clone(self, target: Path) -> None:
        """Re-hash a mutated clone's own artifacts into its manifest."""
        manifest_path = target / "manifest.json"
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        manifest["artifacts"] = [
            {
                "path": str(target / Path(artifact["path"]).name),
                "sha256": _sha(target / Path(artifact["path"]).name),
                "bytes": (target / Path(artifact["path"]).name).stat().st_size,
            }
            for artifact in manifest["artifacts"]
        ]
        manifest["config_path"] = str(self.recipe_path)
        manifest["config_sha256"] = _sha(self.recipe_path)
        manifest["resource_prefix"] = self.recipe["resource_prefix"]
        self._write_json(manifest_path, manifest)

    # -- happy path -----------------------------------------------------------

    def test_valid_delivery_passes(self) -> None:
        self.assertEqual(self._verify(), [])

    def test_qa_conversions_are_pure_and_complete(self) -> None:
        _errors, atlas, images = verify.verify_output(self.output, self.recipe_path)
        qa = self.root / "qa"
        report = verify._write_mechanical_qa(self.output, atlas, images, qa)
        self.assertEqual(report["texture_count"], len(images))
        self.assertEqual(report["facility_sprite_count"], len(verify.FACILITY_IDS))
        self.assertEqual(report["operations"], ["native", "2x_nearest", "25pct_nearest", "grayscale", "alpha_silhouette"])
        self.assertTrue((qa / "atlas_facilities_native.png").is_file())
        with Image.open(qa / "atlas_facilities_native.png") as native:
            self.assertEqual(native.size, verify.ATLAS_SIZE)
            self.assertEqual(native.convert("RGBA").tobytes(), images["facilities"].tobytes())
        with Image.open(qa / "atlas_facilities_2x.png") as doubled:
            self.assertEqual(doubled.size, (verify.ATLAS_SIZE[0] * 2, verify.ATLAS_SIZE[1] * 2))
        with Image.open(qa / "atlas_facilities_25pct.png") as quarter:
            self.assertEqual(quarter.size, (verify.ATLAS_SIZE[0] // 4, verify.ATLAS_SIZE[1] // 4))
        with Image.open(qa / "atlas_facilities_silhouette.png") as silhouette:
            colors = set(silhouette.convert("RGBA").getdata())
        self.assertEqual(colors - {(0, 0, 0, 0)}, {(0, 0, 0, 255)})
        report_on_disk = self._read_json(qa / "QA_REPORT.json")
        self.assertEqual(report_on_disk["kind"], "mechanical_atlas_qa_conversion_not_visual_approval")

    # -- output/QA path safety -----------------------------------------------

    def test_missing_output_directory(self) -> None:
        self.assertTrue(any("output directory is missing" in error for error in self._verify(output=self.root / "absent")))

    def test_missing_files_are_reported(self) -> None:
        empty = self.root / "empty"
        empty.mkdir()
        errors = self._verify(output=empty)
        self.assertTrue(any("missing atlas contract" in error for error in errors), errors)
        self.assertTrue(any("missing layout file" in error for error in errors), errors)

    def test_qa_output_must_be_new_empty_and_outside(self) -> None:
        _errors, atlas, images = verify.verify_output(self.output, self.recipe_path)
        occupied = self.root / "occupied"
        occupied.mkdir()
        (occupied / "existing.txt").write_text("x", encoding="utf-8")
        with self.assertRaises(ValueError):
            verify._write_mechanical_qa(self.output, atlas, images, occupied)
        with self.assertRaises(ValueError):
            verify._write_mechanical_qa(self.output, atlas, images, self.output / "qa")

    # -- atlas contract -------------------------------------------------------

    def test_missing_slot_is_reported(self) -> None:
        target = self._clone("slots")
        atlas = self._read_json(target / "atlas.json")
        del atlas["sprites"]["facility.proxy"]
        self._write_json(target / "atlas.json", atlas)
        self._restamp_clone(target)
        errors = self._verify(output=target)
        self.assertTrue(any("must include the five facility slots" in error for error in errors), errors)

    def test_atlas_size_is_exactly_five_cells(self) -> None:
        target = self._clone("cells")
        with Image.open(target / "facilities.png") as opened:
            trimmed = opened.crop((0, 0, verify.ATLAS_SIZE[0] - 8, verify.ATLAS_SIZE[1]))
        trimmed.save(target / "facilities.png")
        atlas = self._read_json(target / "atlas.json")
        atlas["textures"]["facilities"]["width"] = verify.ATLAS_SIZE[0] - 8
        self._write_json(target / "atlas.json", atlas)
        self._restamp_clone(target)
        errors = self._verify(output=target)
        self.assertTrue(any("must be exactly 640x128" in error for error in errors), errors)

    def test_extra_animation_is_rejected(self) -> None:
        target = self._clone("anim")
        atlas = self._read_json(target / "atlas.json")
        atlas["animations"]["facility.forge.idle"] = {
            "frames": ["facility.forge"],
            "fps": 8,
            "loop": True,
        }
        self._write_json(target / "atlas.json", atlas)
        self._restamp_clone(target)
        errors = self._verify(output=target)
        self.assertTrue(any("animations must exactly match the recipe" in error for error in errors), errors)

    def test_anchor_and_fractional_rect(self) -> None:
        target = self._clone("anchor")
        atlas = self._read_json(target / "atlas.json")
        atlas["sprites"]["facility.forge"]["anchor"] = [63, 120]
        atlas["sprites"]["facility.loadout"]["rect"] = [1.5, 0, 128, 128]
        self._write_json(target / "atlas.json", atlas)
        errors = self._verify(output=target)
        self.assertTrue(any("facility.forge anchor must be [64, 120]" in error for error in errors), errors)
        self.assertTrue(any("facility.loadout rect must be an integer" in error for error in errors), errors)

    def test_non_binary_alpha(self) -> None:
        target = self._clone("pixels")
        with Image.open(target / "facilities.png") as opened:
            image = opened.copy()
        image.putpixel((4, 4), (45, 57, 67, 128))
        image.save(target / "facilities.png")
        self._restamp_clone(target)
        errors = self._verify(output=target)
        self.assertTrue(any("non-binary alpha" in error for error in errors), errors)

    def test_palette_must_be_exact(self) -> None:
        target = self._clone("palette")
        with Image.open(target / "facilities.png") as opened:
            image = opened.copy()
        # A colour outside the recipe palette: the atlas must stay inside the
        # exact palette, not merely inside the 8-colour per-sprite budget.
        image.putpixel((4, 4), (1, 2, 3, 255))
        image.save(target / "facilities.png")
        self._restamp_clone(target)
        errors = self._verify(output=target)
        self.assertTrue(any("outside its recipe palette" in error for error in errors), errors)

    def test_palette_budget_is_enforced(self) -> None:
        training = next(raw for raw in self.recipe["sprites"] if raw["id"] == "facility.training")
        training["palette"] = list(PALETTE[:4])
        self._write_recipe()
        self._restamp_manifest()
        errors = self._verify()
        self.assertTrue(
            any("facility.training" in error and "palette" in error for error in errors), errors
        )

        training.pop("palette")
        self.recipe["palette"] = list(PALETTE[:4])
        self._write_recipe()
        self._restamp_manifest()
        errors = self._verify()
        self.assertTrue(any("outside its recipe palette" in error for error in errors), errors)

    # -- layout contract ------------------------------------------------------

    def test_layout_fixed_world_values_and_unknown_fields(self) -> None:
        target = self._clone("world")
        layout = self._read_json(target / "layout.json")
        layout["world_size"] = [1024, 641]
        layout["hero_start"] = [512, 379]
        layout["tower_feet"] = [281, 348]
        layout["bounds"] = {"left": 0}
        self._write_json(target / "layout.json", layout)
        errors = self._verify(output=target)
        self.assertTrue(any("world_size must equal [1024, 640]" in error for error in errors), errors)
        self.assertTrue(any("hero_start must equal [512, 380]" in error for error in errors), errors)
        self.assertTrue(any("tower_feet must equal [270, 348]" in error for error in errors), errors)
        self.assertTrue(any("unknown field(s): ['bounds']" in error for error in errors), errors)

    def test_layout_identity_feet_footprint_and_split(self) -> None:
        target = self._clone("layout")
        layout = self._read_json(target / "layout.json")
        layout["facilities"][0]["id"] = "facility.unknown"
        layout["facilities"][1]["feet"] = [10, 10]
        layout["facilities"][2]["footprint"] = [0, 0]
        layout["facilities"][3]["split_row"] = 0
        layout["facilities"][4]["role"] = ""
        layout["facilities"].append(dict(layout["facilities"][0]))
        self._write_json(target / "layout.json", layout)
        errors = self._verify(output=target)
        self.assertTrue(any("must name one of the five facility slots" in error for error in errors), errors)
        self.assertTrue(any("must match its id" in error for error in errors), errors)
        self.assertTrue(any("lies outside the world" in error for error in errors), errors)
        self.assertTrue(any("positive width and height" in error for error in errors), errors)
        self.assertTrue(any("split_row must equal 96" in error for error in errors), errors)
        self.assertTrue(any("role must be a non-empty string" in error for error in errors), errors)
        self.assertTrue(any("must cover the five facility slots" in error for error in errors), errors)

    def test_layout_split_must_be_inside_visible_rows(self) -> None:
        # The fixture itself is a valid delivery before mutation.
        self.assertEqual(self._verify(), [])
        target = self._clone("highcell")
        fresh = Image.new("RGBA", verify.ATLAS_SIZE, (0, 0, 0, 0))
        for index in range(len(verify.FACILITY_IDS)):
            fresh.paste(
                Image.new("RGBA", (12, 12), _hex_to_rgba(PALETTE[0])),
                (index * 128 + 58, 24),
            )
        fresh.save(target / "facilities.png")
        self._restamp_clone(target)
        errors = self._verify(output=target)
        self.assertTrue(
            any("must fall strictly inside its visible rows" in error for error in errors), errors
        )

        # A facility's feet must anchor its own footprint box, and ground boxes
        # must not overlap; the 128px visual cell is deliberately not checked.
        target = self._clone("splitedge")
        layout = self._read_json(target / "layout.json")
        layout["facilities"][0]["split_row"] = 2
        self._write_json(target / "layout.json", layout)
        errors = self._verify(output=target)
        self.assertTrue(any("split_row must equal 96" in error for error in errors), errors)

        # A facility's feet must anchor its own footprint box, and ground boxes
        target = self._clone("footboxes")
        layout = self._read_json(target / "layout.json")
        layout["facilities"][0]["footprint"] = [200, 48]
        layout["facilities"][1]["feet"] = [500, 390]
        # A footprint taller than the floor under the feet would place its own
        # anchor outside the box; that is a contract error, not a warning.
        layout["facilities"][1]["footprint"] = [40, 400]
        layout["facilities"][2]["feet"] = [220, 500]
        layout["facilities"][2]["footprint"] = [96, 48]
        self._write_json(target / "layout.json", layout)
        errors = self._verify(output=target)
        self.assertTrue(any("footprint lies outside the world" in error for error in errors), errors)
        self.assertTrue(any("footprint box overlaps" in error for error in errors), errors)

    def test_split_layers_reproduce_whole_sprite(self) -> None:
        """The 96-row split must reproduce the whole sprite byte-for-byte."""
        upper_source = Image.new("RGBA", verify.CELL_SIZE, (0, 0, 0, 0))
        upper_source.paste(Image.new("RGBA", (4, 4), (45, 57, 67, 255)), (2, 94))
        lower_source = Image.new("RGBA", verify.CELL_SIZE, (0, 0, 0, 0))
        lower_source.paste(Image.new("RGBA", (4, 4), (70, 81, 90, 255)), (2, 96))
        cell = Image.alpha_composite(upper_source, lower_source)
        upper, lower = verify._cell_layers(cell, verify.LAYOUT_SPLIT_ROW)
        rebuilt = Image.alpha_composite(upper, lower)
        self.assertEqual(rebuilt.tobytes(), cell.tobytes())
        self.assertIsNone(upper.crop((0, verify.LAYOUT_SPLIT_ROW, *verify.CELL_SIZE)).getbbox())
        self.assertIsNone(lower.crop((0, 0, verify.CELL_SIZE[0], verify.LAYOUT_SPLIT_ROW)).getbbox())

    def test_decals_are_optional_but_bounds_checked(self) -> None:
        # The fixture ships 11 valid decals reusing existing scene sprite IDs.
        layout = self._read_json(self.output / "layout.json")
        self.assertEqual(len(layout["decals"]), 11)
        self.assertEqual(self._verify(), [])

        target = self._clone("decals")
        layout = self._read_json(target / "layout.json")
        layout["decals"][0]["feet"] = [1024, 640]
        layout["decals"][1]["feet"] = [10, "20"]
        layout["decals"][2]["id"] = ""
        layout["decals"][3]["feet"] = [12.5, 40]
        layout["decals"].append({"id": "ground.snow_strip", "feet": list(layout["decals"][4]["feet"])})
        self._write_json(target / "layout.json", layout)
        errors = self._verify(output=target)
        self.assertTrue(any("must sit inside the world rectangle" in error for error in errors), errors)
        self.assertTrue(any("must be an integer pair" in error for error in errors), errors)
        self.assertTrue(any("id must be a non-empty string" in error for error in errors), errors)
        self.assertTrue(any("duplicates decals[" in error for error in errors), errors)

        # Layout without decals stays valid: the field is optional.
        target = self._clone("nodecals")
        layout = self._read_json(target / "layout.json")
        layout.pop("decals")
        self._write_json(target / "layout.json", layout)
        self.assertEqual(self._verify(output=target), [])

    def test_decal_ids_can_be_checked_against_a_scene_atlas(self) -> None:
        target = self._clone("decatlas")
        scene = self.root / "scene_atlas.json"
        self._write_json(scene, {"sprites": {"ground.snow_strip": {}, "ruin.gate": {}}})
        errors, _atlas, _images = verify.verify_output(target, self.recipe_path, scene)
        self.assertEqual(errors, [])
        self._write_json(scene, {"sprites": {"ruin.gate": {}}})
        errors, _atlas, _images = verify.verify_output(target, self.recipe_path, scene)
        self.assertTrue(any("not a sprite id in the decal atlas" in error for error in errors), errors)

    # -- provenance -----------------------------------------------------------

    def test_source_png_corruption_is_reported(self) -> None:
        target = self._clone("source")
        (self.root / "source.png").write_bytes(b"not a real png")
        errors = self._verify(output=target)
        self.assertTrue(any("source" in error for error in errors), errors)

    def test_config_hash_drift_is_reported(self) -> None:
        target = self._clone("confeat")
        self.recipe["native_view"] = [640, 361]
        self._write_recipe()
        errors = self._verify(output=target)
        self.assertTrue(any("config hash" in error or "native_view" in error for error in errors), errors)


if __name__ == "__main__":
    unittest.main()
