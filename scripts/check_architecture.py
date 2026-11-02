#!/usr/bin/env python3
"""Architecture guardrails for src/: layer imports and string dispatch.

Layers may only depend on the layers listed in ALLOWED. A dependency is either
a `res://src/<layer>/` path (preload, load, extends) or a reference to another
layer's global `class_name`. String dispatch (`has_method("x")`, `.call("x")`,
`.call_deferred("x")`, `.callv("x")`) bypasses typed interfaces, so its count
per file may only go down.

Known debt lives in scripts/architecture_baseline.json and only shrinks: a new
violation fails, and so does an exception that is no longer needed. After
removing debt, run with --update-baseline to record the lower counts; that flag
never accepts new layer violations or higher dispatch counts.
"""

import argparse
import json
from pathlib import Path
import re
import sys


ROOT = Path(__file__).resolve().parents[1]
BASELINE = ROOT / "scripts/architecture_baseline.json"

# Target dependency direction (docs/rebuild/ARCHITECTURE.md, "Layers").
ALLOWED = {
    "core": set(),
    "localization": {"core"},
    "persistence": {"core"},
    "content": {"core"},
    "systems": {"core", "content"},
    "runtime": {"core", "content", "systems"},
    "presentation": {"core", "content", "localization", "systems", "runtime"},
    "game": {"core", "content", "localization", "persistence", "systems", "runtime", "presentation"},
}

PATH_REFERENCE = re.compile(r"res://src/(\w+)/")
CLASS_NAME = re.compile(r"^class_name\s+(\w+)", re.M)
STRING_LITERAL = re.compile(r'"(?:[^"\\\n]|\\.)*"')
COMMENT = re.compile(r"#.*")
IDENTIFIER = re.compile(r"\b([A-Z]\w+)\b")
STRING_DISPATCH = re.compile(r'(?:\bhas_method|\.call|\.call_deferred|\.callv)\(\s*&?"')


def layer_of(relative: Path) -> str:
    return relative.parts[1]


def code_only(text: str) -> str:
    """Drop string literals and comments so names in them do not count."""
    return COMMENT.sub("", STRING_LITERAL.sub('""', text))


def scan(root: Path):
    sources = sorted((root / "src").rglob("*.gd"))
    texts = {path.relative_to(root): path.read_text(encoding="utf-8") for path in sources}
    class_layers = {}
    for relative, text in texts.items():
        match = CLASS_NAME.search(text)
        if match:
            class_layers[match.group(1)] = layer_of(relative)
    violations = {}
    dispatch = {}
    for relative, text in texts.items():
        source_layer = layer_of(relative)
        if source_layer not in ALLOWED:
            raise SystemExit(f"unknown layer directory: src/{source_layer}")
        targets = set(PATH_REFERENCE.findall(text))
        targets.update(
            class_layers[name]
            for name in IDENTIFIER.findall(code_only(text))
            if name in class_layers
        )
        bad = sorted(t for t in targets if t != source_layer and t not in ALLOWED[source_layer])
        if bad:
            violations[relative.as_posix()] = bad
        count = len(STRING_DISPATCH.findall(text))
        if count:
            dispatch[relative.as_posix()] = count
    return violations, dispatch


def compare(violations, dispatch, baseline):
    errors = []
    allowed_layers = baseline.get("layer_exceptions", {})
    for path, targets in violations.items():
        new = sorted(set(targets) - set(allowed_layers.get(path, [])))
        if new:
            errors.append(f"{path}: imports {', '.join(new)} (not allowed for its layer)")
    for path, targets in allowed_layers.items():
        stale = sorted(set(targets) - set(violations.get(path, [])))
        if stale:
            errors.append(f"{path}: no longer imports {', '.join(stale)}; remove it from layer_exceptions")
    allowed_dispatch = baseline.get("string_dispatch", {})
    for path, count in dispatch.items():
        limit = allowed_dispatch.get(path, 0)
        if count > limit:
            errors.append(f"{path}: {count} string dispatch calls (baseline {limit}); use a typed interface")
    for path, limit in allowed_dispatch.items():
        count = dispatch.get(path, 0)
        if count < limit:
            errors.append(f"{path}: string dispatch fell to {count} (baseline {limit}); run --update-baseline")
    return errors


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--baseline", type=Path, default=None)
    parser.add_argument("--update-baseline", action="store_true",
                        help="record reduced debt; refuses new violations")
    args = parser.parse_args(argv)
    baseline_path = args.baseline or args.root / "scripts/architecture_baseline.json"
    baseline = json.loads(baseline_path.read_text(encoding="utf-8")) if baseline_path.exists() else {}
    violations, dispatch = scan(args.root)
    errors = compare(violations, dispatch, baseline)
    if args.update_baseline:
        growth = [e for e in errors if "no longer" not in e and "fell to" not in e]
        if growth:
            print("\n".join("FAIL  " + e for e in growth), file=sys.stderr)
            return 1
        updated = {"layer_exceptions": violations, "string_dispatch": dispatch}
        baseline_path.write_text(json.dumps(updated, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        print(f"ARCHITECTURE_BASELINE updated: {len(violations)} layer exceptions, "
              f"{sum(dispatch.values())} string dispatch calls")
        return 0
    if errors:
        print("\n".join("FAIL  " + e for e in errors), file=sys.stderr)
        return 1
    print(f"ARCHITECTURE_CHECK PASS layer_exceptions={len(violations)} "
          f"string_dispatch={sum(dispatch.values())}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
