"""Terrain authoring must preserve reviewed geometry and reject changed art."""

from copy import deepcopy
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import os


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "tools/world_manifest/author_battlegrounds.py"
SPEC = importlib.util.spec_from_file_location("author_battlegrounds", SCRIPT)
author = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(author)


class BattlefieldAuthoringTests(unittest.TestCase):
    def test_repeated_compilation_preserves_sources_and_native_scenes(self):
        placements = deepcopy(author.FIELDS)
        first = author.authored_scenes()
        self.assertEqual(first, author.authored_scenes())
        self.assertEqual(author.FIELDS, placements)
        for layout, text in first.items():
            with self.subTest(layout=layout):
                path = ROOT / f"content/rooms/combat/{layout}.tscn"
                self.assertEqual(text, path.read_text(encoding="utf-8"))

    def test_field_results_do_not_share_mutable_state(self):
        first = author.load_fields()
        second = author.load_fields()
        first["river_crossing"]["terrain"].clear()
        first["river_crossing"]["spawn"][0] = -999
        self.assertTrue(second["river_crossing"]["terrain"])
        self.assertEqual(second["river_crossing"]["spawn"], [300, 610])

    def test_changed_plates_are_rejected_in_both_record_formats(self):
        with tempfile.TemporaryDirectory(prefix="mib-terrain-") as directory:
            root = Path(directory)
            plate = root / "plate.png"
            plate.write_bytes(b"reviewed plate")
            entry = {"source_plate": "res://plate.png",
                     "source_sha256": hashlib.sha256(plate.read_bytes()).hexdigest()}
            for record in (entry, {"battlefields": {"snowbound_road": entry}}):
                with self.subTest(record=record):
                    path = root / "contacts.json"
                    path.write_text(json.dumps(record), encoding="utf-8")
                    plate.write_bytes(b"reviewed plate")
                    self.assertEqual(author.reviewed_record(path, root), record)
                    plate.write_bytes(b"changed plate")
                    with self.assertRaisesRegex(ValueError, "review terrain contacts"):
                        author.reviewed_record(path, root)
                    # Integrity validation must survive Python's -O flag.
                    result = subprocess.run(
                        [os.environ.get("MIB_TEST_PYTHON") or sys.executable, "-B", "-O", "-c",
                         "import runpy, pathlib, sys; "
                         "runpy.run_path(sys.argv[1])['reviewed_record']"
                         "(pathlib.Path(sys.argv[2]), pathlib.Path(sys.argv[3]))",
                         str(SCRIPT), str(path), str(root)],
                        capture_output=True, text=True, timeout=15, check=False,
                    )
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn("review terrain contacts", result.stderr)


if __name__ == "__main__":
    unittest.main()
