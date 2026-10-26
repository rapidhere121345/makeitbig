"""Synthetic tests for the world_expansion_v01 compiler. No production art is read or written."""
from __future__ import annotations

import contextlib
import copy
import hashlib
import importlib.util
import io
import json
import tempfile
import unittest
from pathlib import Path

from PIL import Image

TOOL_DIR = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("we_pack", TOOL_DIR / "pack.py")
pack = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pack)

REAL = json.loads((TOOL_DIR / "packing_config.json").read_text())


def gradient(size, opaque=True):
    img = Image.new("RGBA", size)
    px = img.load()
    for y in range(size[1]):
        for x in range(size[0]):
            px[x, y] = ((x * 7) % 256, (y * 3) % 256, (x + y) % 256, 255)
    return img


def sprite(size=(300, 260), box=(40, 30, 260, 230)):
    img = Image.new("RGBA", size, (9, 9, 9, 100))
    px = img.load()
    for y in range(box[1], box[3]):
        for x in range(box[0], box[2]):
            px[x, y] = ((x * 5) % 256, (y * 11) % 256, 77, 250)
    return img


class Case(unittest.TestCase):
    def setUp(self):
        self._td = tempfile.TemporaryDirectory()
        self.addCleanup(self._td.cleanup)
        self.root = Path(self._td.name)
        self.config = copy.deepcopy(REAL)
        # Synthetic pixels have their own provenance; production pins must not
        # pre-empt transform/alpha assertions with an unrelated hash failure.
        for cfg in list(self.config["grounds"].values()) + list(self.config["assets"].values()):
            cfg.pop("source_sha256", None)
        self.src = self.root / self.config["source_dir"]
        self.src.mkdir(parents=True)
        self.out = self.root / self.config["output_dir"]
        self.cfg_path = self.root / "config.json"
        self.write_config()

    def write_config(self):
        self.cfg_path.write_text(json.dumps(self.config))

    def run_main(self, *args):
        err = io.StringIO()
        with contextlib.redirect_stderr(err), contextlib.redirect_stdout(io.StringIO()):
            code = pack.main(["--root", str(self.root), "--config", str(self.cfg_path), *args])
        return code, err.getvalue()

    def manifest(self):
        return json.loads((self.out / "assets.json").read_text())

    def add_all_raws(self):
        for gid in ("court_ground", "causeway_ground", "ritual_ground"):
            gradient((1536, 1024)).save(self.src / f"{gid}_raw.png")
        gradient((1536, 1024)).save(self.src / "town_ground_winding_raw.png")
        for aid in self.config["assets"]:
            sprite().save(self.src / f"{aid}_raw.png")


class GroundTests(Case):
    def test_combat_ground_uniform_fit_then_centered_crop(self):
        raw = gradient((1536, 1024))
        raw.save(self.src / "court_ground_raw.png")
        self.assertEqual(self.run_main("--available")[0], 0)
        out = Image.open(self.out / "court_ground.png")
        self.assertEqual(out.size, (1024, 640))
        m = self.manifest()["assets"]["court_ground"]
        self.assertEqual(m["transform"]["scale"], "2/3")
        self.assertEqual(m["transform"]["scaled_size"], [1024, 683])
        self.assertEqual(m["transform"]["crop_origin"], [0, 21])
        # Independent nearest formula: src = ((2*i+1)*3)//4 for both axes (step 3/2).
        for (x, y) in [(0, 0), (1, 1), (500, 300), (1023, 639)]:
            sx, sy = ((2 * x + 1) * 3) // 4, ((2 * (y + 21) + 1) * 3) // 4
            self.assertEqual(out.getpixel((x, y)), raw.getpixel((sx, min(sy, 1023))))
        self.assertEqual(out.getchannel("A").getextrema(), (255, 255))
        self.assertEqual((m["anchor"], m["canvas"]), ([0, 0], [1024, 640]))

    def test_manifest_hash_is_of_png_bytes(self):
        gradient((1536, 1024)).save(self.src / "ritual_ground_raw.png")
        self.run_main("--available")
        m = self.manifest()["assets"]["ritual_ground"]
        self.assertEqual(m["sha256"], hashlib.sha256((self.out / "ritual_ground.png").read_bytes()).hexdigest())
        self.assertEqual(m["path"], "res://art/production/p1/world_expansion_v01/ritual_ground.png")

    def test_ground_too_short_fails_closed(self):
        gradient((1536, 900)).save(self.src / "court_ground_raw.png")  # scaled 600 < 640
        code, err = self.run_main("--available")
        self.assertEqual(code, 1)
        self.assertIn("does not cover", err)
        self.assertFalse(self.out.exists())

    def test_town_ground_is_top_crop_without_resize(self):
        raw = gradient((1536, 1024))
        raw.save(self.src / "town_ground_winding_raw.png")
        self.assertEqual(self.run_main("--available")[0], 0)
        out = Image.open(self.out / "town_ground.png")
        self.assertEqual(out.size, (1536, 960))
        self.assertEqual(out.tobytes(), raw.crop((0, 0, 1536, 960)).tobytes())
        t = self.manifest()["assets"]["town_ground"]
        self.assertEqual((t["transform"]["scale"], t["raw_size"]), ("1/1", [1536, 1024]))

    def test_town_ground_wrong_width_or_alpha_rejected(self):
        gradient((1600, 1024)).save(self.src / "town_ground_winding_raw.png")
        self.assertEqual(self.run_main("--available")[0], 1)
        translucent = gradient((1536, 1024))
        translucent.putpixel((10, 10), (0, 0, 0, 200))
        translucent.save(self.src / "town_ground_winding_raw.png")
        self.assertEqual(self.run_main("--available")[0], 1)

    def test_rejected_straight_town_raw_is_never_packed(self):
        gradient((1536, 1024)).save(self.src / "town_ground_raw.png")
        self.run_main("--available")
        self.assertFalse((self.out / "town_ground.png").exists())
        self.assertEqual(self.manifest()["assets"]["town_ground"]["status"], "pending")
        self.config["grounds"]["town_ground"]["source"] = "town_ground_raw.png"
        self.write_config()
        code, err = self.run_main("--available")
        self.assertEqual(code, 1)
        self.assertIn("rejected", err)
        self.assertNotIn("town_ground_raw.png", [g["source"] for g in REAL["grounds"].values()])


class ObjectTests(Case):
    def test_pair_geometry_anchor_and_occlusion(self):
        raw = sprite()
        raw.save(self.src / "gateway_raw.png")
        self.assertEqual(self.run_main("--available")[0], 0)
        opq = Image.open(self.out / "gateway_opaque.png")
        tr = Image.open(self.out / "gateway_transparent.png")
        self.assertEqual(opq.size, (192, 224))
        self.assertEqual(tr.size, opq.size)
        m = self.manifest()["assets"]["gateway"]
        x, y, w, h = m["occupied_rect"]
        self.assertEqual(y + h, 208)  # bottom bound sits on the anchor y
        self.assertEqual(x, 96 - w // 2)
        self.assertEqual(m["occlusion_rect"], [x - 8, y - 8, w + 16, h + 16])
        op, tp = opq.load(), tr.load()
        for yy in range(opq.height):
            for xx in range(opq.width):
                a, b = op[xx, yy], tp[xx, yy]
                if a[3]:
                    self.assertEqual((a[3], b[3], a[:3]), (255, 128, b[:3]))
                else:
                    self.assertEqual(b, (0, 0, 0, 0))
        # The alpha-100 wash in the raw is not occupancy.
        self.assertEqual(m["transform"]["src_rect"], [40, 30, 220, 200])
        self.assertEqual(m["path"], "res://art/production/p1/world_expansion_v01/gateway_opaque.png")
        self.assertEqual(m["transparent_sha256"], hashlib.sha256((self.out / "gateway_transparent.png").read_bytes()).hexdigest())

    def _pack_gateway(self, override=None):
        sprite().save(self.src / "gateway_raw.png")
        if override is not None:
            self.config["assets"]["gateway"]["occlusion_rect"] = override
            self.write_config()
        return self.run_main("--available")

    def test_occlusion_override_expands_and_default_is_unchanged(self):
        self.assertEqual(self._pack_gateway()[0], 0)
        base = self.manifest()["assets"]["gateway"]
        x, y, w, h = base["occlusion_rect"]
        default_bytes = (self.out / "assets.json").read_bytes()
        grown = [x, y - 4, w, h + 8]  # the automatic rect already spans the canvas width
        self.assertEqual(self._pack_gateway(grown)[0], 0)
        m = self.manifest()["assets"]["gateway"]
        self.assertEqual(m["occlusion_rect"], grown)
        self.assertEqual((m["sha256"], m["occupied_rect"]), (base["sha256"], base["occupied_rect"]))
        self.assertEqual(self._pack_gateway(base["occlusion_rect"])[0], 0)
        self.assertEqual((self.out / "assets.json").read_bytes(), default_bytes)

    def test_occlusion_override_rejects_shrink_outside_and_bad_types(self):
        self.assertEqual(self._pack_gateway()[0], 0)
        x, y, w, h = self.manifest()["assets"]["gateway"]["occlusion_rect"]
        before = (self.out / "assets.json").read_bytes()
        cases = {
            "shrink": [x + 1, y, w - 1, h],
            "shrink_bottom": [x, y, w, h - 1],
            "outside": [-1, y, w + 1 + x, h],
            "past_canvas": [x, y, 192 - x + 1, h],
            "zero": [x, y, 0, h],
            "float": [float(x), y, w, h],
            "bool": [True, y, w, h],
            "string": "1,2,3,4",
            "short": [x, y, w],
        }
        for name, value in cases.items():
            with self.subTest(name):
                code, err = self._pack_gateway(value)
                self.assertEqual(code, 1)
                self.assertIn("occlusion_rect override", err)
                self.assertEqual((self.out / "assets.json").read_bytes(), before)

    def test_custom_source_is_the_existence_check(self):
        self.config["assets"]["wall"]["source"] = "wall_v2_raw.png"
        self.write_config()
        self.assertEqual(self.run_main("--available")[0], 0)
        self.assertEqual(self.manifest()["assets"]["wall"]["status"], "pending")
        sprite().save(self.src / "wall_raw.png")
        self.assertEqual(self.run_main("--available")[0], 0)
        self.assertEqual(self.manifest()["assets"]["wall"]["status"], "pending")
        sprite().save(self.src / "wall_v2_raw.png")
        self.assertEqual(self.run_main("--available")[0], 0)
        m = self.manifest()["assets"]["wall"]
        self.assertEqual(m["status"], "packed")
        self.assertTrue(m["transform"]["source"].endswith("wall_v2_raw.png"))

    def test_empty_object_refused(self):
        Image.new("RGBA", (64, 64), (0, 0, 0, 100)).save(self.src / "wall_raw.png")
        code, err = self.run_main("--available")
        self.assertEqual(code, 1)
        self.assertIn("no occupied pixels", err)

    def test_configured_canvases_and_anchors(self):
        a = REAL["assets"]
        for bridge in ("bridge", "bridge_ne"):
            self.assertEqual((a[bridge]["canvas"], a[bridge]["anchor"]), ([240, 220], [120, 200]))
        self.assertEqual((a["gateway"]["canvas"], a["gateway"]["anchor"]), ([192, 224], [96, 208]))
        for h in ("house_east", "house_west"):
            self.assertEqual((a[h]["canvas"], a[h]["anchor"]), ([224, 208], [112, 192]))
        self.assertEqual((a["wall"]["canvas"], a["wall"]["anchor"]), ([192, 112], [96, 104]))
        for g in ("court_ground", "causeway_ground", "ritual_ground"):
            self.assertEqual((REAL["grounds"][g]["canvas"], REAL["grounds"][g]["anchor"]), ([1024, 640], [0, 0]))


class PendingAndVerify(Case):
    def test_pinned_raw_drift_fails_without_replacing_outputs(self):
        raw = self.src / "wall_raw.png"
        sprite().save(raw)
        self.config["assets"]["wall"]["source_sha256"] = hashlib.sha256(raw.read_bytes()).hexdigest()
        self.write_config()
        self.assertEqual(self.run_main("--available")[0], 0)
        before = {p.name: p.read_bytes() for p in self.out.iterdir()}
        sprite(box=(60, 40, 240, 200)).save(raw)
        code, error = self.run_main("--available")
        self.assertEqual(code, 1)
        self.assertIn("raw hash mismatch", error)
        self.assertEqual(before, {p.name: p.read_bytes() for p in self.out.iterdir()})

    def test_missing_raws_fail_closed_without_flag(self):
        code, err = self.run_main()
        self.assertEqual(code, 2)
        self.assertIn("bridge", err)
        self.assertFalse(self.out.exists())

    def test_available_keeps_missing_entries_pending(self):
        sprite().save(self.src / "bridge_raw.png")
        self.assertEqual(self.run_main("--available")[0], 0)
        m = self.manifest()
        self.assertEqual(m["schema_version"], 1)
        self.assertEqual(m["assets"]["bridge"]["status"], "packed")
        for pid in ("court_ground", "town_ground", "wall"):
            self.assertEqual(m["assets"][pid]["status"], "pending")
            self.assertNotIn("sha256", m["assets"][pid])
        self.assertEqual(sorted(m["pending"]), sorted(set(m["assets"]) - {"bridge"}))
        self.assertFalse((self.out / "wall_opaque.png").exists())

    def test_obsolete_manifest_is_ignored_and_never_written(self):
        sprite().save(self.src / "bridge_raw.png")
        self.out.mkdir(parents=True)
        (self.out / "manifest.json").write_text("old")
        self.assertEqual(self.run_main("--available")[0], 0)
        self.assertEqual((self.out / "manifest.json").read_text(), "old")
        self.assertEqual(self.run_main("--verify")[0], 0)
        self.assertTrue((self.out / "assets.json").is_file())

    def test_full_pack_then_verify_and_repack_byte_identical(self):
        self.add_all_raws()
        self.assertEqual(self.run_main()[0], 0)
        self.assertEqual(self.manifest()["pending"], [])
        self.assertEqual(self.run_main("--verify")[0], 0)
        before = {p.name: p.read_bytes() for p in self.out.iterdir()}
        self.assertEqual(self.run_main()[0], 0)
        self.assertEqual(before, {p.name: p.read_bytes() for p in self.out.iterdir()})

    def test_verify_detects_tampering_stale_raw_and_strays(self):
        self.add_all_raws()
        self.run_main()
        png = self.out / "bridge_opaque.png"
        original = png.read_bytes()
        png.write_bytes(original + b"x")
        code, err = self.run_main("--verify")
        self.assertEqual(code, 1)
        self.assertIn("bridge_opaque.png differs", err)
        png.write_bytes(original)
        (self.out / "stray.png").write_bytes(b"")
        self.assertIn("unexpected file stray.png", self.run_main("--verify")[1])
        (self.out / "stray.png").unlink()
        sprite(box=(50, 30, 250, 230)).save(self.src / "bridge_raw.png")
        self.assertEqual(self.run_main("--verify")[0], 1)

    def test_verify_flags_raw_that_arrived_after_pending_pack(self):
        sprite().save(self.src / "bridge_raw.png")
        self.run_main("--available")
        sprite().save(self.src / "wall_raw.png")
        self.assertEqual(self.run_main("--verify")[0], 1)

    def test_sidecars_preserve_uid_and_match_actors_recipe(self):
        sprite().save(self.src / "bridge_raw.png")
        self.run_main("--available")
        side = self.out / "bridge_opaque.png.import"
        self.assertNotIn("uid=", side.read_text())
        side.write_text(side.read_text().replace(
            'type="CompressedTexture2D"\n', 'type="CompressedTexture2D"\nuid="uid://abc123"\n', 1))
        self.run_main("--available")
        self.assertIn('uid="uid://abc123"', side.read_text())
        self.assertEqual(self.run_main("--verify")[0], 0)
        spec2 = importlib.util.spec_from_file_location("av2", TOOL_DIR.parent / "actors_v02" / "build.py")
        av2 = importlib.util.module_from_spec(spec2)
        spec2.loader.exec_module(av2)
        av2.ROOT = self.root.resolve()
        probe = self.out / "bridge_opaque.png"
        before = side.read_text()
        av2.sidecar(probe)
        self.assertEqual(side.read_text(), before)

    def test_changed_raw_changes_recorded_hash(self):
        sprite().save(self.src / "wall_raw.png")
        self.run_main("--available")
        first = self.manifest()["assets"]["wall"]["raw_sha256"]
        sprite(box=(60, 40, 240, 200)).save(self.src / "wall_raw.png")
        self.run_main("--available")
        self.assertNotEqual(first, self.manifest()["assets"]["wall"]["raw_sha256"])


if __name__ == "__main__":
    unittest.main()
