"""English-only policy tests; fixture Han is constructed, not authored UI."""

import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parent.parent
SPEC = importlib.util.spec_from_file_location("english_check", ROOT / "scripts/check_english.py")
checker = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(checker)


class EnglishCheckTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="mib-english-check-")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)

    def write(self, name, text):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        return path

    def inspect(self, name):
        return checker.inspect_files(self.root, [name])

    def test_english_passes(self):
        self.write("README.md", "# English\nHearthside and the Threshold Colossus.\n")
        self.assertFalse(self.inspect("README.md")["errors"])

    def test_raw_han_fails(self):
        self.write("src/ui.gd", 'var label = "' + chr(0x4e2d) + '"')
        self.assertTrue(self.inspect("src/ui.gd")["errors"])

    def test_json_escapes_and_keys_cannot_hide_untranslated_copy(self):
        for value in ({"name": chr(0x4e2d)}, {chr(0x4e2d): "value"}):
            self.write("content/item.json", json.dumps(value, ensure_ascii=True))
            self.assertTrue(self.inspect("content/item.json")["errors"])

    def test_gdscript_escape_cannot_hide_ui_text(self):
        self.write("src/ui.gd", r'var label = "\u4e2d"')
        self.assertTrue(self.inspect("src/ui.gd")["errors"])

    def test_compatibility_alias_is_scoped_to_function(self):
        name = "src/systems/destiny_forge.gd"
        alias = r'    var legacy = "\u6dfb\u94f8"'
        self.write(name, "func _normalize_track():\n" + alias)
        self.assertFalse(self.inspect(name)["errors"])
        self.write(name, "func display_name():\n" + alias)
        self.assertTrue(self.inspect(name)["errors"])

    def test_original_record_must_remain_byte_identical(self):
        name = "source/ORIGINAL.json"
        path = self.write(name, json.dumps({"prompt": chr(0x4e2d)}, ensure_ascii=False))
        original = hashlib.sha256(path.read_bytes()).hexdigest()
        with patch.dict(checker.ORIGINAL_SHA256, {name: original}):
            self.assertEqual(self.inspect(name)["exceptions"], [name])
            path.write_text('{"prompt":"counterfeit rewritten original"}')
            self.assertTrue(self.inspect(name)["errors"])

    def test_invalid_json_is_reported(self):
        self.write("content/broken.json", "{invalid")
        self.assertTrue(self.inspect("content/broken.json")["errors"])


if __name__ == "__main__":
    unittest.main()
