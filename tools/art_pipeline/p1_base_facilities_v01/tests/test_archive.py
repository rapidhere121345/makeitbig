"""Synthetic, temporary-directory tests for the boundary archive helper."""

from __future__ import annotations

import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).resolve().parents[1] / "archive.py"
SPEC = importlib.util.spec_from_file_location("base_facilities_archive", MODULE_PATH)
archive = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
sys.modules[SPEC.name] = archive
SPEC.loader.exec_module(archive)


class BoundaryArchiveTests(unittest.TestCase):
    """Every repository root is a temporary tree; nothing touches the real repo."""

    def setUp(self) -> None:
        self._temporary = tempfile.TemporaryDirectory(prefix="base_facilities_archive_")
        self.root = Path(self._temporary.name)
        self._make_tree()
        self.baseline = self.root / "docs" / "baseline" / "BOUNDARY_HASHES.json"

    def tearDown(self) -> None:
        self._temporary.cleanup()

    def _write(self, relative: str, content: str) -> Path:
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")
        return path

    def _make_tree(self) -> None:
        self._write("src/game/main.gd", "main")
        self._write("content/early_items.json", "{}")
        self._write("project.godot", "[application]")
        self._write("art/early/actors_atlas.png", "early")
        self._write("art/production/p1/calibration_v01/facilities.png", "old atlas")
        self._write("art/production/p1/base_facilities_v01/facilities.png", "new batch atlas")
        self._write("tools/art_preview/p1_scene_rework_v01/preview_scene.gd", "old preview")
        self._write("tools/art_preview/p1_base_facilities_v01/preview_scene.gd", "new preview")
        self._write("tools/art_pipeline/p1_calibration_v01/build.py", "old builder")
        self._write("docs/art-production/p1-calibration-v01/graphics_v02/world.png", "old drop")
        self._write("docs/art-production/p1-calibration-v01/qa/QA_REPORT.json", "{}")
        self._write("docs/art-production/p1-base-facilities-v01/recipe.json", "new recipe")
        self._write("docs/art-production/VISUAL_BASELINE.md", "baseline doc")
        self._write("tests/run_all.gd", "not protected")

    def _capture(self, filename: str = "BOUNDARY_HASHES.json") -> dict:
        return archive.capture(
            self.root,
            self.baseline.parent,
            filename=filename,
            note="test snapshot",
        )

    # -- capture ------------------------------------------------------------

    def test_capture_covers_protected_and_excludes_new_batch(self) -> None:
        document = self._capture()
        files = set(document["files"])
        for expected in (
            "src/game/main.gd",
            "content/early_items.json",
            "project.godot",
            "art/early/actors_atlas.png",
            "art/production/p1/calibration_v01/facilities.png",
            "tools/art_preview/p1_scene_rework_v01/preview_scene.gd",
            "tools/art_pipeline/p1_calibration_v01/build.py",
            "docs/art-production/p1-calibration-v01/graphics_v02/world.png",
            "docs/art-production/p1-calibration-v01/qa/QA_REPORT.json",
        ):
            self.assertIn(expected, files)
        for excluded in (
            "art/production/p1/base_facilities_v01/facilities.png",
            "tools/art_preview/p1_base_facilities_v01/preview_scene.gd",
            "docs/art-production/p1-base-facilities-v01/recipe.json",
            "docs/art-production/VISUAL_BASELINE.md",
            "tests/run_all.gd",
        ):
            self.assertNotIn(excluded, files)
        self.assertNotIn("docs/baseline/BOUNDARY_HASHES.json", files)
        self.assertTrue(all(isinstance(v["sha256"], str) for v in document["files"].values()))

    def test_capture_hashes_detect_file_content(self) -> None:
        document = self._capture()
        recorded = document["files"]["src/game/main.gd"]["sha256"]
        self.assertEqual(recorded, archive._sha256(self.root / "src/game/main.gd"))

    def test_capture_refuses_to_overwrite(self) -> None:
        self._capture()
        with self.assertRaises(archive.SnapshotError):
            self._capture()
        # An explicit replacement is the only overwrite path.
        archive.capture(
            self.root, self.baseline, filename="BOUNDARY_HASHES.json", force=True, note="forced"
        )
        self.assertEqual(
            json.loads(self.baseline.read_text(encoding="utf-8"))["note"], "forced"
        )

    def test_custom_filename_and_json_output(self) -> None:
        self._capture(filename="BOUNDARY_HASHES_v02.json")
        self.assertTrue((self.baseline.parent / "BOUNDARY_HASHES_v02.json").is_file())
        direct = self.root / "docs" / "direct.json"
        archive.capture(self.root, direct, note="direct")
        self.assertTrue(direct.is_file())

    # -- compare ------------------------------------------------------------

    def test_compare_reports_unchanged_missing_changed_added(self) -> None:
        self._capture()
        report = archive.compare(self.root, self.baseline)
        self.assertEqual(report["summary"], {"unchanged": 9, "changed": 0, "missing": 0, "added": 0})

        self._write("src/game/main.gd", "main changed")
        (self.root / "content/early_items.json").unlink()
        self._write("tools/art_pipeline/p1_calibration_v01/verify.py", "new old-pipeline file")
        report = archive.compare(self.root, self.baseline)
        self.assertEqual(report["summary"]["unchanged"], 7)
        self.assertEqual(report["summary"]["changed"], 1)
        self.assertEqual(report["changed"][0]["path"], "src/game/main.gd")
        self.assertEqual(report["summary"]["missing"], 1)
        self.assertEqual(report["missing"], ["content/early_items.json"])
        self.assertEqual(report["added"], ["tools/art_pipeline/p1_calibration_v01/verify.py"])

    def test_new_batch_files_are_never_reported_as_damage(self) -> None:
        self._capture()
        self._write("art/production/p1/base_facilities_v01/facilities.png", "newer batch bytes")
        self._write("tools/art_preview/p1_base_facilities_v01/self_test.gd", "new preview file")
        report = archive.compare(self.root, self.baseline)
        self.assertEqual(report["summary"]["missing"], 0)
        self.assertEqual(report["summary"]["changed"], 0)
        self.assertEqual(report["summary"]["added"], 0)

    def test_compare_requires_baseline(self) -> None:
        with self.assertRaises(archive.SnapshotError):
            archive.compare(self.root, self.root / "missing.json")

    # -- path safety --------------------------------------------------------

    def test_baseline_must_stay_inside_root(self) -> None:
        outside = tempfile.mkdtemp(prefix="base_facilities_outside_")
        with self.assertRaises(archive.SnapshotError):
            archive.capture(self.root, Path(outside), filename="BOUNDARY_HASHES.json")

    def test_patterns_reject_absolute_and_parent_escapes(self) -> None:
        for bad in ("/etc/passwd", "../secrets/**", "art/../../etc/**"):
            with self.assertRaises(archive.SnapshotError):
                archive.capture(self.root, self.baseline, protected=[bad])

    def test_symlinked_protected_file_is_rejected(self) -> None:
        link = self.root / "src" / "linked.gd"
        target = self.root / "outside.gd"
        target.write_text("outside", encoding="utf-8")
        link.symlink_to(target)
        with self.assertRaises(archive.SnapshotError):
            self._capture()

    def test_symlinked_baseline_target_is_rejected(self) -> None:
        real = self.root / "docs" / "real.json"
        real.write_text("{}\n", encoding="utf-8")
        link = self.root / "docs" / "link.json"
        link.symlink_to(real)
        with self.assertRaises(archive.SnapshotError):
            archive.capture(self.root, link, filename="BOUNDARY_HASHES.json")

    def test_protected_patterns_must_use_relative_globs(self) -> None:
        with self.assertRaises(archive.SnapshotError):
            archive.capture(self.root, self.baseline, protected=["/abs/**"])
        with self.assertRaises(archive.SnapshotError):
            archive.capture(self.root, self.baseline, excludes=["/abs/**"])


if __name__ == "__main__":
    unittest.main()
