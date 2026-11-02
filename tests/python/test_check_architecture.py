"""Layer and string-dispatch guardrail tests on small synthetic trees."""

import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("architecture_check", ROOT / "scripts/check_architecture.py")
checker = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(checker)


class ArchitectureCheckTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="mib-architecture-check-")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.write("src/core/value.gd", "class_name CoreValue\nextends RefCounted\n")
        self.write("src/runtime/room.gd", "class_name RuntimeRoom\nextends RefCounted\n")
        self.write("src/presentation/view.gd", "class_name PresentationView\nextends Node\n")

    def write(self, name, text):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")

    def baseline(self, data):
        path = self.root / "scripts/architecture_baseline.json"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(data), encoding="utf-8")

    def run_check(self, *extra):
        return checker.main(["--root", str(self.root), *extra])

    def test_allowed_dependencies_pass(self):
        self.write("src/runtime/user.gd", 'const V := preload("res://src/core/value.gd")\nvar room: RuntimeRoom\n')
        self.write("src/presentation/user.gd", "var room: RuntimeRoom\nvar value: CoreValue\n")
        self.assertEqual(self.run_check(), 0)

    def test_path_import_into_higher_layer_fails(self):
        self.write("src/runtime/bad.gd", 'const View := preload("res://src/presentation/view.gd")\n')
        violations, _ = checker.scan(self.root)
        self.assertEqual(violations, {"src/runtime/bad.gd": ["presentation"]})
        self.assertEqual(self.run_check(), 1)

    def test_class_name_reference_counts_but_comments_and_strings_do_not(self):
        self.write("src/core/typed.gd", "var room: RuntimeRoom\n")
        self.write("src/core/quiet.gd", '# PresentationView in a comment\nvar label := "RuntimeRoom"\n')
        violations, _ = checker.scan(self.root)
        self.assertEqual(violations, {"src/core/typed.gd": ["runtime"]})

    def test_baseline_exception_passes_and_stale_exception_fails(self):
        self.write("src/runtime/bad.gd", "var view: PresentationView\n")
        self.baseline({"layer_exceptions": {"src/runtime/bad.gd": ["presentation"]}})
        self.assertEqual(self.run_check(), 0)
        self.write("src/runtime/bad.gd", "var room: RuntimeRoom\n")
        self.assertEqual(self.run_check(), 1)

    def test_string_dispatch_is_ratcheted(self):
        self.write("src/presentation/calls.gd", 'func f(x):\n\tif x.has_method("a"):\n\t\tx.call("a")\n')
        self.baseline({"string_dispatch": {"src/presentation/calls.gd": 2}})
        self.assertEqual(self.run_check(), 0)
        self.write("src/presentation/calls.gd", 'func f(x):\n\tx.call("a")\n\tx.call_deferred("b")\n\tx.callv("c", [])\n')
        self.assertEqual(self.run_check(), 1)
        self.write("src/presentation/calls.gd", 'func f(x):\n\tx.a()\n\tx.call(name)\n')
        self.assertEqual(self.run_check(), 1, "a lower count must be recorded in the baseline")

    def test_private_reach_ins_are_ratcheted(self):
        self.write("src/game/helper.gd", "func f():\n\t_root._status = 1\n\t_root.transition()\n\t_main._tick()\n")
        _, counts = checker.scan(self.root)
        self.assertEqual(counts["private_reach_ins"], {"src/game/helper.gd": 2})
        self.baseline({"private_reach_ins": {"src/game/helper.gd": 2}})
        self.assertEqual(self.run_check(), 0)
        self.write("src/game/helper.gd", "func f():\n\t_root._status = 1\n\t_root._a()\n\t_main._tick()\n")
        self.assertEqual(self.run_check(), 1)

    def test_update_baseline_records_reductions_but_refuses_growth(self):
        self.write("src/presentation/calls.gd", 'func f(x):\n\tx.call("a")\n')
        self.baseline({"string_dispatch": {"src/presentation/calls.gd": 3}})
        self.assertEqual(self.run_check("--update-baseline"), 0)
        recorded = json.loads((self.root / "scripts/architecture_baseline.json").read_text())
        self.assertEqual(recorded["string_dispatch"], {"src/presentation/calls.gd": 1})
        self.write("src/core/bad.gd", "var room: RuntimeRoom\n")
        self.assertEqual(self.run_check("--update-baseline"), 1)


if __name__ == "__main__":
    unittest.main()
