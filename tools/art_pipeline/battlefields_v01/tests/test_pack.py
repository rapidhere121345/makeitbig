"""Production battlefield package integrity and reproducibility checks."""
import hashlib
import importlib.util
import json
from pathlib import Path
import unittest

from PIL import Image

ROOT = Path(__file__).resolve().parents[4]
CONFIG = ROOT / "tools/art_pipeline/battlefields_v01/packing_config.json"
PACKER = ROOT / "tools/art_pipeline/world_expansion_v01/pack.py"
spec = importlib.util.spec_from_file_location("battlefield_shared_pack", PACKER)
pack = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pack)


class BattlefieldPackageTests(unittest.TestCase):
    def test_sources_outputs_and_rebuild(self):
        config = pack.load_config(CONFIG)
        floors = {"snowbound_road", "river_crossing", "ruined_village", "quarry_pass",
                  "colossus_approach"}
        expected = floors | {name + "_extension" for name in floors} | {"river_water", "slate_cliff"}
        self.assertEqual(set(config["grounds"]), expected)
        self.assertEqual(set(config["assets"]), {"shoreline_stones"})
        output = ROOT / config["output_dir"]
        manifest = json.loads((output / "assets.json").read_text())
        self.assertEqual(manifest["pending"], [])
        self.assertEqual(set(manifest["assets"]), expected | {"shoreline_stones"})
        hashes = set()
        for asset_id, recipe in config["grounds"].items():
            with self.subTest(asset=asset_id):
                source = ROOT / config["source_dir"] / recipe["source"]
                digest = hashlib.sha256(source.read_bytes()).hexdigest()
                self.assertEqual(recipe["source_sha256"], digest)
                entry = manifest["assets"][asset_id]
                self.assertEqual(entry["raw_sha256"], digest)
                self.assertEqual(entry["status"], "packed")
                image_path = output / f"{asset_id}.png"
                with Image.open(image_path) as image:
                    if asset_id.endswith("_extension"):
                        expected_size = (1536, 1024)
                    elif asset_id in {"river_water", "slate_cliff"}:
                        expected_size = (1024, 1024)
                    else:
                        expected_size = (1024, 640)
                    self.assertEqual(image.size, expected_size)
                    self.assertEqual(image.convert("RGBA").getchannel("A").getextrema(), (255, 255))
                image_hash = hashlib.sha256(image_path.read_bytes()).hexdigest()
                self.assertEqual(entry["sha256"], image_hash)
                self.assertNotIn(image_hash, hashes, "duplicate output")
                hashes.add(image_hash)
                self.assertIn("process/fix_alpha_border=false", image_path.with_suffix(".png.import").read_text())
        recipe = config["assets"]["shoreline_stones"]
        source = ROOT / config["source_dir"] / "shoreline_stones_raw.png"
        digest = hashlib.sha256(source.read_bytes()).hexdigest()
        self.assertEqual(recipe["source_sha256"], digest)
        entry = manifest["assets"]["shoreline_stones"]
        self.assertEqual(entry["raw_sha256"], digest)
        self.assertEqual(entry["status"], "packed")
        self.assertEqual(entry["canvas"], [160, 72])
        self.assertEqual(entry["anchor"], [80, 64])
        self.assertFalse(entry["reveal"])
        opaque_path = output / "shoreline_stones_opaque.png"
        transparent_path = output / "shoreline_stones_transparent.png"
        for path, hash_key in ((opaque_path, "sha256"), (transparent_path, "transparent_sha256")):
            self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(), entry[hash_key])
            self.assertIn("process/fix_alpha_border=false", path.with_suffix(".png.import").read_text())
        with Image.open(opaque_path) as opaque, Image.open(transparent_path) as transparent:
            self.assertEqual(opaque.size, (160, 72))
            self.assertEqual(transparent.size, opaque.size)
            opaque_bytes = opaque.convert("RGBA").tobytes()
            transparent_bytes = transparent.convert("RGBA").tobytes()
            opaque_pixels = [opaque_bytes[i:i + 4] for i in range(0, len(opaque_bytes), 4)]
            transparent_pixels = [transparent_bytes[i:i + 4] for i in range(0, len(transparent_bytes), 4)]
        self.assertEqual({p[3] for p in opaque_pixels}, {0, 255})
        self.assertEqual({p[3] for p in transparent_pixels}, {0, 128})
        for op, tr in zip(opaque_pixels, transparent_pixels):
            self.assertEqual(op[:3], tr[:3])
            self.assertEqual(tr[3], 128 if op[3] else 0)
        self.assertEqual(pack.verify_pack(ROOT, config), [])


if __name__ == "__main__":
    unittest.main()
