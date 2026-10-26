"""Synthetic-bitmap tests for the generated-world-v02 whole-object packer.

No production art is read or written; every test builds tiny synthetic images
and configs in a temporary directory.
"""

from __future__ import annotations

import importlib.util
import json
import sys
import tempfile
import unittest
from fractions import Fraction
from pathlib import Path

from PIL import Image

TOOL_DIR = Path(__file__).resolve().parents[1]


def load_module(name: str):
    if name in sys.modules:
        return sys.modules[name]
    spec = importlib.util.spec_from_file_location(name, TOOL_DIR / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    sys.modules[name] = module
    return module


pack = load_module("pack")


def make_raw(size, boxes, wash_alpha=0) -> Image.Image:
    """Synthetic generated raw: opaque-ish object boxes plus a low-alpha wash."""
    img = Image.new("RGBA", size, (10, 20, 30, wash_alpha))
    px = img.load()
    for (x0, y0, x1, y1, color) in boxes:
        for y in range(y0, y1):
            for x in range(x0, x1):
                px[x, y] = color
    return img


def make_config(tmp: Path, assets: dict, grounds: dict | None = None) -> dict:
    return {
        "schema_version": 1,
        "package": "test_world",
        "source_dir": "sources",
        "output_dir": "art",
        "report_dir": "report",
        "default_alpha_threshold": 240,
        "margin": 8,
        "occlusion_grow": 8,
        "transparent_alpha": 64,
        "primary_ground": "town_ground",
        "grounds": grounds or {
            "town_ground": {
                "source": "ground_raw.png",
                "src_rect": [0, 0, 12, 8],
                "canvas": [12, 8],
                "anchor": [0, 0],
            },
        },
        "assets": assets,
    }


def write_raw(root: Path, config: dict, name: str, image: Image.Image) -> Path:
    src_dir = root / config["source_dir"]
    src_dir.mkdir(parents=True, exist_ok=True)
    path = src_dir / name
    image.save(path, format="PNG")
    return path


def write_config(root: Path, config: dict) -> str:
    path = root / "packing_config.json"
    path.write_text(json.dumps(config, indent=2, sort_keys=True), encoding="utf-8")
    return pack.sha256_file(path)


ASSET = {"canvas": [32, 32], "anchor": [16, 28]}
RAW = make_raw((16, 16), [(4, 2, 12, 14, (200, 100, 50, 252))], wash_alpha=30)


class IndexMathTests(unittest.TestCase):
    def test_identity_step(self):
        for dst in range(6):
            self.assertEqual(pack.source_index(dst, 1, 1), dst)

    def test_downscale_covers_last_source_pixel(self):
        # step 5/4 src per dst px: dst 7 -> src 9 covers a 10 px source.
        self.assertEqual(pack.source_index(7, 5, 4), 9)
        self.assertEqual(pack.source_index(0, 5, 4), 0)

    def test_compute_fit_uniform_rational(self):
        fit = pack.compute_fit(10, 7, 8, 8)
        self.assertEqual(fit["scale"], Fraction(4, 5))
        self.assertEqual((fit["dst_w"], fit["dst_h"]), (8, 6))
        self.assertEqual((fit["step_num"], fit["step_den"]), (5, 4))

    def test_compute_fit_height_bound(self):
        fit = pack.compute_fit(10, 10, 80, 9)
        self.assertEqual(fit["scale"], Fraction(9, 10))
        self.assertEqual((fit["dst_w"], fit["dst_h"]), (9, 9))

    def test_compute_fit_upscale(self):
        fit = pack.compute_fit(4, 4, 10, 10)
        self.assertEqual(fit["scale"], Fraction(5, 2))
        self.assertEqual((fit["dst_w"], fit["dst_h"]), (10, 10))


class PackObjectTests(unittest.TestCase):
    def test_anchor_bottom_and_centering(self):
        canvas, info = pack.pack_object(
            RAW, ASSET, {"margin": 8, "alpha_threshold": 240}
        )
        self.assertEqual(canvas.size, (32, 32))
        t = info["transform"]
        # src occupied 8x12 -> max_w=16, max_h=20 -> s=16/8=2 -> dst 16x24? no:
        # s=min(16/8, 20/12)=5/3 -> dst 14x20.
        self.assertEqual(t["scale"], "5/3")
        dst_w, dst_h = 14, 20
        self.assertEqual(t["dst_rect"], [16 - dst_w // 2, 28 - dst_h, dst_w, dst_h])
        self.assertEqual(t["src_rect"], [4, 2, 8, 12])

    def test_binary_alpha_and_rgb(self):
        canvas, _ = pack.pack_object(
            RAW, ASSET, {"margin": 8, "alpha_threshold": 240}
        )
        px = canvas.load()
        alphas = set()
        for y in range(32):
            for x in range(32):
                r, g, b, a = px[x, y]
                alphas.add(a)
                if a:
                    self.assertEqual((r, g, b), (200, 100, 50))
                else:
                    self.assertEqual((r, g, b), (0, 0, 0))
        self.assertEqual(alphas, {0, 255})

    def test_occupied_within_margin_and_anchor(self):
        canvas, _ = pack.pack_object(
            RAW, ASSET, {"margin": 8, "alpha_threshold": 240}
        )
        occ = pack.occupied_rect(canvas)
        self.assertIsNotNone(occ)
        x, y, w, h = occ
        self.assertGreaterEqual(x, 8)
        self.assertGreaterEqual(y, 8)
        self.assertLessEqual(x + w, 32 - 8)
        self.assertLessEqual(y + h, 28)

    def test_transparent_pair_contract(self):
        canvas, _ = pack.pack_object(
            RAW, ASSET, {"margin": 8, "alpha_threshold": 240}
        )
        pair = pack.transparent_pair(canvas, 64)
        pack.assert_pair_contract(canvas, pair, 64)
        pp = pair.load()
        alphas = {pp[x, y][3] for y in range(pair.height) for x in range(pair.width)}
        self.assertEqual(alphas, {0, 64})

    def test_half_opaque_pair_preserves_rgb_and_geometry(self):
        canvas, _ = pack.pack_object(RAW, ASSET, {"margin": 8, "alpha_threshold": 240})
        pair = pack.transparent_pair(canvas, 128)
        pack.assert_pair_contract(canvas, pair, 128)
        self.assertEqual({pair.getpixel((x, y))[3] for y in range(pair.height)
                          for x in range(pair.width)}, {0, 128})
        self.assertEqual(canvas.convert("RGB").tobytes(), pair.convert("RGB").tobytes())

    def test_empty_object_rejected(self):
        empty = make_raw((16, 16), [], wash_alpha=40)
        with self.assertRaises(pack.BuildError):
            pack.pack_object(empty, ASSET, {"margin": 8, "alpha_threshold": 240})

    def test_threshold_override(self):
        # alpha 235 is below the default 240 but above the 200 override.
        faint = make_raw((16, 16), [(4, 2, 12, 14, (1, 2, 3, 235))])
        with self.assertRaises(pack.BuildError):
            pack.pack_object(faint, ASSET, {"margin": 8, "alpha_threshold": 240})
        cfg = dict(ASSET) | {"alpha_threshold": 200}
        canvas, _ = pack.pack_object(faint, cfg, {"margin": 8, "alpha_threshold": 240})
        self.assertIsNotNone(pack.occupied_rect(canvas))

    def test_fringe_report(self):
        _, info = pack.pack_object(
            RAW, ASSET, {"margin": 8, "alpha_threshold": 240}
        )
        stats = info["raw_stats"]
        self.assertEqual(stats["occupied_bbox"], [4, 2, 8, 12])
        self.assertEqual(stats["occupied_pixels"], 96)
        self.assertEqual(stats["occupied_components"], 1)
        self.assertEqual(stats["fringe_pixels"], 16 * 16 - 96)
        self.assertEqual(stats["fringe_alpha_histogram"], {"30": 160})

    def test_margin_violation_rejected(self):
        # Fitted 16 px wide window centred on anchor x 10 leaves dx=2 < margin.
        wide = make_raw((64, 16), [(0, 0, 64, 16, (9, 9, 9, 252))])
        cfg = {"canvas": [32, 32], "anchor": [10, 28]}
        with self.assertRaises(pack.BuildError):
            pack.pack_object(wide, cfg, {"margin": 8, "alpha_threshold": 240})


class GroundTests(unittest.TestCase):
    def test_crop_opaque(self):
        raw = Image.new("RGBA", (20, 20), (1, 2, 3, 255))
        cfg = {"src_rect": [2, 4, 12, 8], "canvas": [12, 8]}
        canvas, info = pack.pack_ground(raw, cfg)
        self.assertEqual(canvas.size, (12, 8))
        self.assertEqual(canvas.getchannel("A").getextrema(), (255, 255))
        self.assertEqual(info["transform"]["src_rect"], [2, 4, 12, 8])

    def test_transparent_raw_rejected(self):
        raw = Image.new("RGBA", (20, 20), (1, 2, 3, 255))
        raw.putpixel((5, 5), (1, 2, 3, 200))
        cfg = {"src_rect": [0, 0, 12, 8], "canvas": [12, 8]}
        with self.assertRaises(pack.BuildError):
            pack.pack_ground(raw, cfg)

    def test_fit_width_crop_height(self):
        # 30x21 raw -> s=2/3 -> scaled 20x14 -> centre crop to 20x10, residue 4.
        raw = Image.new("RGBA", (30, 21), (3, 4, 5, 255))
        cfg = {"mode": "fit_width_crop_height", "fit_width": 20, "canvas": [20, 10]}
        canvas, info = pack.pack_ground(raw, cfg)
        self.assertEqual(canvas.size, (20, 10))
        self.assertEqual(canvas.getchannel("A").getextrema(), (255, 255))
        t = info["transform"]
        self.assertEqual(t["scale"], "2/3")
        self.assertEqual(t["scaled_size"], [20, 14])
        self.assertEqual(t["crop_origin"], [0, 2])
        self.assertEqual(t["residue_px"], 4)

    def test_fit_cover_failure(self):
        # 30x9 raw -> scaled 20x6 < canvas height 10: fails closed.
        raw = Image.new("RGBA", (30, 9), (3, 4, 5, 255))
        cfg = {"mode": "fit_width_crop_height", "fit_width": 20, "canvas": [20, 10]}
        with self.assertRaises(pack.BuildError):
            pack.pack_ground(raw, cfg)

    def test_fit_mode_values_match_reference_mapping(self):
        # 6x4 -> s=1/2 -> scaled 3x2: dst px i samples src index
        # (2i+1)*2//(2*1) = 2i+1, the centre of each 2x2 block.
        raw = Image.new("RGBA", (6, 4))
        px = raw.load()
        for y in range(4):
            for x in range(6):
                px[x, y] = (x * 40, y * 60, 0, 255)
        cfg = {"mode": "fit_width_crop_height", "fit_width": 3, "canvas": [3, 2]}
        canvas, _ = pack.pack_ground(raw, cfg)
        out = canvas.load()
        self.assertEqual(out[0, 0], px[1, 1])
        self.assertEqual(out[2, 1], px[5, 3])


class IncrementalRunTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.config = make_config(self.root, {
            "alpha_one": dict(ASSET),
            "beta_two": dict(ASSET),
        })
        write_raw(self.root, self.config, "alpha_one_raw.png", RAW)
        write_raw(self.root, self.config, "beta_two_raw.png", RAW)
        write_raw(self.root, self.config, "ground_raw.png",
                  Image.new("RGBA", (12, 8), (7, 7, 7, 255)))
        self.config_sha = write_config(self.root, self.config)

    def tearDown(self):
        self.tmp.cleanup()

    def test_available_packs_and_manifest(self):
        manifest, report = pack.run_pack(self.root, self.config, self.config_sha, None)
        self.assertTrue(manifest["complete"])
        self.assertEqual(manifest["pending"], [])
        for aid in ("alpha_one", "beta_two"):
            entry = manifest["assets"][aid]
            self.assertEqual(entry["status"], "packed")
            self.assertEqual(entry["canvas"], [32, 32])
            self.assertEqual(entry["anchor"], [16, 28])
            self.assertIsNotNone(entry["occupied_rect"])
            occl = entry["occlusion_rect"]
            self.assertIsNotNone(occl)
            occ = entry["occupied_rect"]
            # full occupied+8 on every side, never clipped
            self.assertEqual(occl, [occ[0] - 8, occ[1] - 8,
                                    occ[2] + 16, occ[3] + 16])
            # occupied reaches the anchor at y=28, so grow8 overflows the
            # 32 px canvas bottom and the entry is flagged, not clipped.
            self.assertTrue(entry.get("occlusion_overflow"))
        ground = manifest["ground"]
        self.assertEqual(ground["status"], "packed")
        self.assertEqual(ground["canvas"], [12, 8])
        self.assertIsNone(ground["transparent_path"])
        out = self.root / "art"
        self.assertTrue((out / "alpha_one_opaque.png").is_file())
        self.assertTrue((out / "alpha_one_transparent.png").is_file())
        self.assertTrue((out / "town_ground_opaque.png").is_file())
        self.assertTrue((out / "assets.json").is_file())

    def test_deterministic_rebuild(self):
        pack.run_pack(self.root, self.config, self.config_sha, None)
        out = self.root / "art"
        first = {p.name: p.read_bytes() for p in sorted(out.iterdir())}
        pack.run_pack(self.root, self.config, self.config_sha, None)
        second = {p.name: p.read_bytes() for p in sorted(out.iterdir())}
        self.assertEqual(first, second)

    def test_incremental_pending_and_carryover(self):
        pack.run_pack(self.root, self.config, self.config_sha, {"alpha_one"})
        manifest = json.loads((self.root / "art" / "assets.json").read_text())
        self.assertEqual(manifest["assets"]["alpha_one"]["status"], "packed")
        beta = manifest["assets"]["beta_two"]
        self.assertEqual(beta["status"], "pending")
        self.assertEqual(beta["pending_reason"], "not_requested")
        self.assertIsNone(beta["opaque_path"])
        self.assertFalse(manifest["complete"])
        # Second run packs beta and the ground; alpha's entry carries over
        # byte-identical and the manifest is complete.
        first_alpha = manifest["assets"]["alpha_one"]
        pack.run_pack(self.root, self.config, self.config_sha,
                      {"beta_two", "town_ground"})
        manifest = json.loads((self.root / "art" / "assets.json").read_text())
        self.assertEqual(manifest["assets"]["alpha_one"], first_alpha)
        self.assertTrue(manifest["complete"])

    def test_missing_raw_pending(self):
        (self.root / "sources" / "beta_two_raw.png").unlink()
        manifest, _ = pack.run_pack(self.root, self.config, self.config_sha, None)
        self.assertEqual(manifest["assets"]["beta_two"]["status"], "pending")
        self.assertEqual(
            manifest["assets"]["beta_two"]["pending_reason"], "raw_missing")
        self.assertFalse(manifest["complete"])

    def test_stale_on_raw_change(self):
        pack.run_pack(self.root, self.config, self.config_sha, None)
        changed = make_raw((16, 16), [(4, 2, 12, 14, (1, 1, 1, 252))])
        write_raw(self.root, self.config, "beta_two_raw.png", changed)
        manifest, _ = pack.run_pack(
            self.root, self.config, self.config_sha, {"alpha_one"})
        self.assertEqual(manifest["assets"]["beta_two"]["status"], "stale")
        self.assertEqual(
            manifest["assets"]["beta_two"]["stale_reason"], "raw_changed")
        self.assertFalse(manifest["complete"])

    def test_explicit_missing_raw_fails(self):
        (self.root / "sources" / "beta_two_raw.png").unlink()
        with self.assertRaises(pack.BuildError):
            pack.run_pack(self.root, self.config, self.config_sha, {"beta_two"})

    def test_guard_output_refuses_strays(self):
        pack.run_pack(self.root, self.config, self.config_sha, None)
        (self.root / "art" / "stray.txt").write_text("x")
        with self.assertRaises(pack.BuildError):
            pack.run_pack(self.root, self.config, self.config_sha, None)

    def test_detection_override_enlarges_without_changing_art(self):
        before, _ = pack.run_pack(self.root, self.config, self.config_sha, None)
        self.config["assets"]["alpha_one"]["occlusion_grow"] = 11
        after, _ = pack.run_pack(self.root, self.config, self.config_sha, None)
        a, b = before["assets"]["alpha_one"], after["assets"]["alpha_one"]
        self.assertEqual(a["opaque_sha256"], b["opaque_sha256"])
        self.assertEqual(b["occlusion_rect"], pack.grow_rect(b["occupied_rect"], 11))
        self.config["assets"]["alpha_one"]["occlusion_grow"] = 7
        with self.assertRaises(pack.BuildError):
            pack.run_pack(self.root, self.config, self.config_sha, None)

    def test_repack_preserves_import_options_and_separate_residents(self):
        pack.run_pack(self.root, self.config, self.config_sha, None)
        sidecar = self.root / "art" / "alpha_one_opaque.png.import"
        sidecar.write_text("process/fix_alpha_border=false\n")
        residents = self.root / "art" / "residents"
        residents.mkdir()
        sheet = residents / "owned-by-npc-packer.txt"
        sheet.write_bytes(b"preserved")
        self.config["preserved_subdirs"] = ["residents"]
        pack.run_pack(self.root, self.config, self.config_sha, None)
        self.assertEqual(sidecar.read_text(), "process/fix_alpha_border=false\n")
        self.assertEqual(sheet.read_bytes(), b"preserved")
        (self.root / "art" / "unknown.png.import").write_text("stray")
        with self.assertRaises(pack.BuildError):
            pack.run_pack(self.root, self.config, self.config_sha, None)

    def test_pinned_source_sha(self):
        config = make_config(self.root, {"alpha_one": dict(ASSET) | {
            "source_sha256": "0" * 64}})
        write_raw(self.root, config, "alpha_one_raw.png", RAW)
        write_raw(self.root, config, "ground_raw.png",
                  Image.new("RGBA", (12, 8), (7, 7, 7, 255)))
        sha = write_config(self.root, config)
        with self.assertRaises(pack.BuildError):
            pack.run_pack(self.root, config, sha, None)

    def test_verify_roundtrip(self):
        pack.run_pack(self.root, self.config, self.config_sha, None)
        results = pack.run_verify(self.root, self.config)
        self.assertEqual(len(results), 3)  # two assets + ground

    def test_sections_complete_independently(self):
        config = make_config(self.root, {
            "alpha_one": dict(ASSET) | {"section": "town"},
            "beta_two": dict(ASSET) | {"section": "arena"},
        }, grounds={
            "town_ground": {
                "source": "ground_raw.png",
                "src_rect": [0, 0, 12, 8],
                "canvas": [12, 8],
                "anchor": [0, 0],
                "section": "town",
            },
            "arena_ground": {
                "source": "arena_ground_raw.png",
                "mode": "fit_width_crop_height",
                "fit_width": 12,
                "canvas": [12, 8],
                "anchor": [0, 0],
                "section": "arena",
            },
        })
        write_raw(self.root, config, "alpha_one_raw.png", RAW)
        write_raw(self.root, config, "ground_raw.png",
                  Image.new("RGBA", (12, 8), (7, 7, 7, 255)))
        # The arena object raw never arrives; the arena ground raw neither.
        (self.root / "sources" / "beta_two_raw.png").unlink()
        sha = write_config(self.root, config)
        manifest, _ = pack.run_pack(self.root, config, sha, None)
        self.assertTrue(manifest["sections"]["town"]["complete"])
        self.assertFalse(manifest["sections"]["arena"]["complete"])
        self.assertEqual(
            manifest["sections"]["arena"]["pending"],
            ["beta_two", "arena_ground"],
        )
        self.assertFalse(manifest["complete"])
        # The primary town ground is still mirrored on the legacy key.
        self.assertEqual(manifest["ground"]["status"], "packed")
        self.assertEqual(manifest["grounds"]["arena_ground"]["status"], "pending")


if __name__ == "__main__":
    unittest.main()
