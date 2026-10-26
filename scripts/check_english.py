#!/usr/bin/env python3
"""Keep source copy English; validate localized catalogs and pinned originals."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys


HAN = re.compile(r"[\u3400-\u4dbf\u4e00-\u9fff\U00020000-\U0002fa1f]+")
ESCAPE = re.compile(r"\\u([0-9a-fA-F]{4})|\\U([0-9a-fA-F]{8})")
TEXT_SUFFIXES = {
    ".gd", ".gdshader", ".tscn", ".tres", ".json", ".py", ".sh", ".ps1",
    ".md", ".txt", ".html", ".css", ".js", ".yml", ".yaml", ".cfg", ".csv", ".svg",
}

# Original legal/source records are not rewritten to counterfeit English originals.
# English companions explain the provenance; no runtime localization reads these.
ORIGINAL_SHA256 = {
    "art/fonts/LICENSE-noto-cjk.txt":
        "849f4ea9c214fa4ac3593b770c699f387534b11ce671264c1b10d85bdcb5997b",
    "art/fonts/PROVENANCE.md":
        "0869d6a7d75bc5f980985e74c0a8c641a69661781b2ede22ad18e1e7085c17e3",
    "art/production/p1/hamlet_town/SOURCE.json":
        "063cb1c4503830446de46a01249d5b4b68c16eda8a5d2b086fa193066f205faf",
    "docs/art-production/p1-icon-expansion-v01/EXECUTED_PROMPTS.json":
        "60ade747a5f8f0198ce27d205102b33be8ac2f24d014afbed662c959eb2d5a04",
}

# Legacy inputs remain accepted, but these are never player-facing output strings.
COMPATIBILITY_WORDS = {
    "\u6dfb\u94f8", "\u6539\u5199", "\u7cbe\u70bc",
}
COMPATIBILITY_FUNCTIONS = {
    ("src/systems/destiny_forge.gd", "_normalize_track"),
    ("tests/test_systems.gd", "_test_legacy_forge_operation_inputs"),
}


def tracked_files(root):
    result = subprocess.run(
        ["git", "-C", str(root), "ls-files", "--cached", "--others",
         "--exclude-standard", "-z"],
        capture_output=True, check=True,
    )
    return sorted(set(result.stdout.decode("utf-8").strip("\0").split("\0")) - {""})


def json_strings(value, location="$"):
    if isinstance(value, str):
        yield location, value
    elif isinstance(value, dict):
        for key, item in value.items():
            yield location + ".<key>", key
            yield from json_strings(item, location + "." + key)
    elif isinstance(value, list):
        for index, item in enumerate(value):
            yield from json_strings(item, f"{location}[{index}]")


def validate_catalog(text):
    errors = []
    seen = set()

    def unique_pairs(rows):
        result = {}
        for key, value in rows:
            if key in seen:
                errors.append(f"duplicate source message: {key!r}")
            seen.add(key)
            result[key] = value
        return result

    try:
        data = json.loads(text, object_pairs_hook=unique_pairs)
    except json.JSONDecodeError as error:
        return [f"invalid JSON: {error}"]
    if not isinstance(data, dict) or not data:
        return ["catalog must be a nonempty source-to-translation object"]
    placeholders = re.compile(r"%(?:[-+0 #]*[0-9]*(?:\.[0-9]+)?)?[sdf]|%%")
    for source, target in data.items():
        if not isinstance(target, str) or not target.strip():
            errors.append(f"empty/non-string translation for {source!r}")
            continue
        if HAN.search(source):
            errors.append(f"source key must remain English: {source!r}")
        if placeholders.findall(source) != placeholders.findall(target):
            errors.append(f"format placeholders differ for {source!r}")
    return errors


def inspect_files(root, files):
    errors = []
    exceptions = []
    inspected = 0
    for name in files:
        path = root / name
        if not path.is_file() or path.suffix.lower() not in TEXT_SUFFIXES:
            continue
        try:
            raw = path.read_bytes()
            if name in ORIGINAL_SHA256:
                if hashlib.sha256(raw).hexdigest() != ORIGINAL_SHA256[name]:
                    errors.append(f"{name}: immutable provenance/license digest changed")
                else:
                    exceptions.append(name)
                continue
            text = raw.decode("utf-8")
        except (OSError, UnicodeError) as error:
            errors.append(f"{name}: cannot read UTF-8 text: {error}")
            continue
        inspected += 1
        if name == "content/localization/zh_CN.json":
            errors.extend(f"{name}: {error}" for error in validate_catalog(text))
            continue
        function = ""
        for line_no, line in enumerate(text.splitlines(), 1):
            declaration = re.match(r"^\s*(?:static\s+)?func\s+(\w+)\(", line)
            if declaration:
                function = declaration.group(1)
            if HAN.search(line):
                errors.append(f"{name}:{line_no}: untranslated Han text")
            if path.suffix in (".gd", ".tscn", ".tres") and ESCAPE.search(line):
                decoded = ESCAPE.sub(lambda m: chr(int(m.group(1) or m.group(2), 16)), line)
                words = set(HAN.findall(decoded))
                if words and not ((name, function) in COMPATIBILITY_FUNCTIONS
                                  and words <= COMPATIBILITY_WORDS):
                    errors.append(f"{name}:{line_no}: escaped untranslated Han text")
        if path.suffix == ".json":
            try:
                data = json.loads(text)
                for location, value in json_strings(data):
                    if HAN.search(value):
                        errors.append(f"{name}:{location}: untranslated decoded JSON string")
            except json.JSONDecodeError as error:
                errors.append(f"{name}: invalid JSON: {error}")
    return {"checked_files": inspected, "exceptions": exceptions, "errors": errors}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parent.parent)
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args(argv)
    root = args.root.resolve()
    try:
        report = inspect_files(root, tracked_files(root))
    except (OSError, subprocess.CalledProcessError) as error:
        print(f"ENGLISH_CHECK FAIL: cannot enumerate checkout: {error}", file=sys.stderr)
        return 1
    report["status"] = "fail" if report["errors"] else "pass"
    if args.json:
        print(json.dumps(report, indent=2))
    else:
        print("ENGLISH_CHECK", report["status"].upper(),
              f"files={report['checked_files']} pinned_originals={len(report['exceptions'])}")
        for error in report["errors"]:
            print(error)
    return 1 if report["errors"] else 0


if __name__ == "__main__":
    sys.exit(main())
