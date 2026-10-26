"""Tests for the helpers shared by the art pipelines."""

from __future__ import annotations

import hashlib
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import common  # noqa: E402


class CommonTests(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.tmp = Path(self._tmp.name)

    def test_sha256_file_matches_hashlib_across_block_boundaries(self):
        path = self.tmp / "blob.bin"
        data = bytes(range(256)) * (4 * 1024 + 3)  # a little over 1 MiB
        path.write_bytes(data)
        self.assertEqual(common.sha256_file(path), hashlib.sha256(data).hexdigest())
        empty = self.tmp / "empty.bin"
        empty.write_bytes(b"")
        self.assertEqual(common.sha256_file(empty), hashlib.sha256(b"").hexdigest())

    def test_display_path_is_relative_inside_root_and_absolute_outside(self):
        root = self.tmp / "root"
        (root / "sub").mkdir(parents=True)
        self.assertEqual(common.display_path(root / "sub" / ".." / "a.png", root), "a.png")
        outside = self.tmp / "elsewhere.png"
        self.assertEqual(common.display_path(outside, root), str(outside.resolve()))

    def test_write_json_bytes(self):
        path = self.tmp / "out.json"
        value = {"b": 1, "a": ["\u00e9"]}
        common.write_json(path, value)
        self.assertEqual(path.read_bytes(), '{\n  "a": [\n    "\u00e9"\n  ],\n  "b": 1\n}\n'.encode("utf-8"))
        common.write_json(path, value, ensure_ascii=True)
        self.assertEqual(path.read_text(encoding="ascii"), '{\n  "a": [\n    "\\u00e9"\n  ],\n  "b": 1\n}\n')
        common.write_json(path, {"b": 1, "a": 2}, sort_keys=False)
        self.assertTrue(path.read_text(encoding="ascii").startswith('{\n  "b"'))

    def test_load_json_reports_with_the_requested_error_and_label(self):
        class Boom(ValueError):
            pass

        good = self.tmp / "good.json"
        good.write_text('{"a": 1}', encoding="utf-8")
        self.assertEqual(common.load_json(good), {"a": 1})
        bad = self.tmp / "bad.json"
        bad.write_text("{", encoding="utf-8")
        with self.assertRaisesRegex(Boom, "cannot read recipe .*bad.json"):
            common.load_json(bad, "recipe", Boom)
        with self.assertRaisesRegex(Boom, "cannot read recipe .*missing.json"):
            common.load_json(self.tmp / "missing.json", "recipe", Boom)
        listy = self.tmp / "list.json"
        listy.write_text("[]", encoding="utf-8")
        with self.assertRaisesRegex(Boom, "recipe root must be an object"):
            common.load_json(listy, "recipe", Boom)

    def test_guard_generated_output(self):
        class Refused(RuntimeError):
            pass

        out = self.tmp / "out"

        def owned(directory: Path) -> list[Path]:
            return [directory / "manifest.json"]

        def guard(replace, extra=()):
            common.guard_generated_output(out, replace, owned, Refused, extra)

        guard(False)  # missing directory
        out.mkdir()
        guard(False)  # empty directory
        (out / "manifest.json").write_text("{}", encoding="utf-8")
        with self.assertRaisesRegex(Refused, "not empty"):
            guard(False)
        guard(True)
        (out / "stray.txt").write_text("x", encoding="utf-8")
        with self.assertRaisesRegex(Refused, "unmanaged"):
            guard(True)
        guard(True, extra=[out / "stray.txt"])
        (out / "stray.txt").unlink()
        (out / "stray.txt").symlink_to(out / "manifest.json")
        with self.assertRaisesRegex(Refused, "unmanaged|symlinked"):
            guard(True)
        file_output = self.tmp / "file"
        file_output.write_text("x", encoding="utf-8")
        with self.assertRaisesRegex(Refused, "not a directory"):
            common.guard_generated_output(file_output, True, owned, Refused)


if __name__ == "__main__":
    unittest.main()
