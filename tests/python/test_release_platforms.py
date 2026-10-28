"""Release metadata keeps old builds readable and supports a macOS-only ZIP."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class ReleasePlatformsTests(unittest.TestCase):
    def test_legacy_and_macos_downloads(self):
        with tempfile.TemporaryDirectory(prefix="mib-release-platforms-") as directory:
            root = Path(directory)
            env = dict(os.environ, MIB_RELEASE_ROOT=str(root / "site"), MIB_RELEASE_ALLOW_OUTSIDE="1",
                       MIB_RELEASE_KEEP_BUILDS="3")
            for platform, name in (("LINUX", "game.x86_64"), ("WINDOWS", "game.exe"), ("MACOS", "game.zip")):
                env["MIB_RELEASE_" + platform + "_SOURCE"] = str(root / name)

            def run(*arguments):
                result = subprocess.run(["bash", str(ROOT / "scripts/release.sh"), *arguments],
                                        env=env, capture_output=True, text=True, timeout=20)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

            (root / "game.x86_64").write_bytes(b"Linux fixture")
            (root / "game.exe").write_bytes(b"Windows fixture")
            old_id = "20261028-000001-abcdef0"
            run("package", "--id", old_id)
            # Switch fixture inputs without modifying any existing project build.
            env["MIB_RELEASE_LINUX_SOURCE"] = str(root / "absent-linux")
            env["MIB_RELEASE_WINDOWS_SOURCE"] = str(root / "absent-windows")
            (root / "game.zip").write_bytes(b"macOS ZIP fixture")
            new_id = "20261028-000002-abcdef0"
            run("package", "--id", new_id)
            run("index")
            run("site")
            run("verify", "--deep")
            index = json.loads((root / "site/index.json").read_text())
            self.assertEqual(set(index["builds"][0]["files"]), {"macos"})
            self.assertEqual(set(index["builds"][1]["files"]), {"linux", "windows"})
            sums = (root / "site/builds" / new_id / "SHA256SUMS").read_text()
            self.assertIn("macos/make-it-big-macos-universal.zip", sums)
            self.assertIn("macos", (root / "site/app.js").read_text())


if __name__ == "__main__":
    unittest.main()
