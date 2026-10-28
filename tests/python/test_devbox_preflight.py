"""Prerequisite-checker regression tests; no Docker or network access."""

import hashlib
import importlib.util
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("preflight", ROOT / "scripts/devbox_preflight.py")
preflight = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(preflight)
ORIGINAL_PIN = preflight.GODOT_SHA256


class PreflightTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="mib-preflight-")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.binary = self.root / "godot"
        self.binary.write_bytes(b"test fixture, never executed")
        self.binary.chmod(0o755)
        self.templates = self.root / "templates"
        self.templates.mkdir()
        (self.templates / "version.txt").write_text("4.7.2.stable\n")
        for name in preflight.RELEASE_TEMPLATES:
            (self.templates / name).write_bytes(b"fixture")
        self.digest = hashlib.sha256(self.binary.read_bytes()).hexdigest()
        for mock in (
            patch.dict(os.environ, {"MIB_GODOT_BINARY_PATH": ""}),
            patch.object(preflight.os, "geteuid", return_value=1000, create=True),
            patch.object(preflight.platform, "system", return_value="Linux"),
            patch.object(preflight.platform, "machine", return_value="x86_64"),
            patch.object(preflight.shutil, "which", side_effect=lambda name:
                         str(name) if os.path.isabs(name) else "/usr/bin/" + name),
            patch.object(preflight, "run", return_value=(0, "4.7.2.stable.official.ed1daf0bf")),
            patch.object(preflight, "GODOT_SHA256", self.digest),
        ):
            mock.start()
            self.addCleanup(mock.stop)

    def audit(self, profile="release", **kwargs):
        return preflight.audit(self.root, profile, str(self.binary), str(self.templates), **kwargs)

    @staticmethod
    def failures(report):
        return {check["check"] for check in report["checks"] if check["status"] == "fail"}

    def test_ready_prerequisites_do_not_modify_checkout(self):
        before = {p.relative_to(self.root): p.read_bytes()
                  for p in self.root.rglob("*") if p.is_file()}
        report = self.audit()
        after = {p.relative_to(self.root): p.read_bytes()
                 for p in self.root.rglob("*") if p.is_file()}
        self.assertEqual(report["status"], "ready")
        self.assertEqual(report["scope"], "prerequisites_only")
        self.assertEqual(before, after)

    def test_missing_windows_template_blocks_release(self):
        (self.templates / "windows_release_x86_64.exe").unlink()
        self.assertIn("template_windows_release_x86_64.exe", self.failures(self.audit()))

    def test_missing_macos_template_blocks_release(self):
        (self.templates / "macos.zip").unlink()
        self.assertIn("template_macos.zip", self.failures(self.audit()))

    def test_wrong_template_version_blocks_release(self):
        (self.templates / "version.txt").write_text("4.6.stable")
        self.assertIn("template_version", self.failures(self.audit()))

    def test_version_and_hash_are_independent(self):
        with patch.object(preflight, "run", return_value=(0, "4.6.stable.official")):
            self.assertIn("godot_version", self.failures(self.audit("headless")))
        with patch.object(preflight, "GODOT_SHA256", "0" * 64):
            self.assertIn("godot_sha256", self.failures(self.audit("headless")))

    def test_explicit_missing_path_does_not_silently_fallback(self):
        with patch.object(preflight, "executable", return_value=None):
            self.assertIsNone(preflight.find_godot(self.root, "/missing/requested-godot"))
        self.assertIsNone(preflight.find_templates(self.root, self.root / "missing-templates"))

    def test_root_is_rejected(self):
        with patch.object(preflight.os, "geteuid", return_value=0):
            self.assertIn("non_root", self.failures(self.audit("headless")))

    def test_software_gpu_is_not_hardware_acceptance(self):
        def result(command):
            if Path(command[0]).name == "glxinfo":
                return 0, "OpenGL renderer string: llvmpipe (LLVM)"
            return 0, "4.7.2.stable.official.ed1daf0bf"
        with patch.dict(os.environ, {"DISPLAY": ":99"}), patch.object(preflight, "run", side_effect=result):
            self.assertIn("gl_renderer", self.failures(self.audit("visual")))
            self.assertNotIn("gl_renderer", self.failures(self.audit("visual", software_ok=True)))

    def test_graphics_is_not_required_for_headless(self):
        with patch.dict(os.environ, {}, clear=True):
            self.assertNotIn("x11_display", self.failures(self.audit("headless")))
            self.assertIn("x11_display", self.failures(self.audit("visual")))

    def test_pins_match_environment_script(self):
        text = (ROOT / "scripts/project_env.sh").read_text()
        self.assertIn(":-" + preflight.GODOT_VERSION + "}", text)
        self.assertIn(":-" + ORIGINAL_PIN + "}", text)

    def test_scoped_launcher_hashes_raw_engine_not_wrapper(self):
        launcher = self.root / "mib-godot"
        launcher.write_text("#!/bin/sh\nexec verified-engine \"$@\"\n")
        launcher.chmod(0o755)
        report = preflight.audit(self.root, "headless", str(launcher),
                                 engine_binary=str(self.binary))
        self.assertNotIn("godot_sha256", self.failures(report))
        self.assertIn("godot_sha256", self.failures(
            preflight.audit(self.root, "headless", str(launcher))))


if __name__ == "__main__":
    unittest.main()
