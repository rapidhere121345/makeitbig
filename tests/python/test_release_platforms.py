"""Release archives and draft publication must fail safely without touching history."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tarfile
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("release_package", ROOT / "scripts/package_release.py")
release = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(release)


class ReleasePlatformsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="mib-github-release-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.sources = {"linux": self.root / "linux", "windows": self.root / "windows", "macos": self.root / "macos.zip"}
        self.sources["linux"].write_bytes(b"Linux fixture")
        self.sources["windows"].write_bytes(b"Windows fixture")
        with zipfile.ZipFile(self.sources["macos"], "w") as archive:
            archive.writestr("Make It Big.app/Contents/Info.plist", b"fixture")
        self.notes = self.root / "notes.md"
        self.notes.write_text("Release fixture\n")
        self.output = self.root / "packages/v0.1.0"

    def package(self):
        release.package(self.output, "v0.1.0", "a" * 40, self.sources, self.notes)

    def test_three_downloads_and_exact_mac_zip(self):
        self.package()
        metadata = release.verify(self.output)
        self.assertEqual(set(metadata["files"]), {"linux", "windows", "macos"})
        self.assertEqual((self.output / release.ASSETS["macos"]).read_bytes(), self.sources["macos"].read_bytes())
        with tarfile.open(self.output / release.ASSETS["linux"]) as archive:
            self.assertEqual(archive.getmembers()[0].mode, 0o755)
        self.assertEqual(len((self.output / "SHA256SUMS").read_text().splitlines()), 5)

    def test_missing_platform_does_not_create_partial_output(self):
        self.sources["macos"] = self.root / "absent"
        with self.assertRaisesRegex(ValueError, "missing macos"):
            self.package()
        self.assertFalse(self.output.exists())

    def test_existing_release_is_not_replaced(self):
        self.package()
        before = (self.output / "build.json").read_bytes()
        with self.assertRaisesRegex(ValueError, "refusing to replace"):
            self.package()
        self.assertEqual((self.output / "build.json").read_bytes(), before)

    def test_modified_download_fails_checksum(self):
        self.package()
        (self.output / release.ASSETS["windows"]).write_bytes(b"modified")
        with self.assertRaisesRegex(ValueError, "SHA256 mismatch"):
            release.verify(self.output)

    def test_missing_metadata_checksum_fails(self):
        self.package()
        sums = self.output / "SHA256SUMS"
        sums.write_text("".join(line for line in sums.read_text().splitlines(True) if "build.json" not in line))
        with self.assertRaisesRegex(ValueError, "incomplete SHA256SUMS"):
            release.verify(self.output)

    def test_tag_cannot_escape_output_or_be_an_option(self):
        for tag in ("../../elsewhere", "--notes-file=oops", "master", "v0.1.0/extra"):
            with self.assertRaisesRegex(ValueError, "tag must"):
                release.package(self.output, tag, "a" * 40, self.sources, self.notes)

    def publish_fixture(self, fail_upload=False, existing=False):
        self.package()
        tools = self.root / "bin"
        tools.mkdir()
        git = tools / "git"
        git.write_text("#!/bin/sh\nprintf '%s\\n' " + "a" * 40 + "\n")
        git.chmod(0o755)
        gh = tools / "gh"
        gh.write_text("""#!/bin/bash
printf '%s\\0' "$@" >> "$MOCK_GH_LOG"
printf '\\n' >> "$MOCK_GH_LOG"
if [[ "$2" == view ]]; then exit "${MOCK_GH_EXISTS:-1}"; fi
if [[ "$2" == create ]]; then exit "${MOCK_GH_UPLOAD:-0}"; fi
exit 0
""")
        gh.chmod(0o755)
        env = dict(os.environ, PATH=str(tools) + os.pathsep + os.environ["PATH"],
                   MIB_RELEASE_ROOT=str(self.output.parent), MOCK_GH_LOG=str(self.root / "gh.log"),
                   MOCK_GH_UPLOAD="1" if fail_upload else "0", MOCK_GH_EXISTS="0" if existing else "1")
        result = subprocess.run(["bash", str(ROOT / "scripts/release.sh"), "publish", "v0.1.0"],
                                env=env, capture_output=True, text=True, timeout=20)
        return result, (self.root / "gh.log").read_bytes().decode().splitlines()

    def test_upload_draft_before_publication(self):
        result, calls = self.publish_fixture()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("create", calls[1])
        self.assertIn("--verify-tag", calls[1])
        self.assertIn("--draft", calls[1])
        self.assertIn("edit", calls[2])
        self.assertIn("--draft=false", calls[2])

    def test_failed_upload_is_not_published(self):
        result, calls = self.publish_fixture(fail_upload=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any("edit" in call for call in calls))

    def test_existing_published_release_is_not_overwritten(self):
        result, calls = self.publish_fixture(existing=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(len(calls), 1)


if __name__ == "__main__":
    unittest.main()
