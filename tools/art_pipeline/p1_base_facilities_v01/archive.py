#!/usr/bin/env python3
"""Capture and compare a read-only hash baseline of protected repository paths.

``snapshot`` records SHA-256/size/mtime for every protected file into a new
``BOUNDARY_HASHES.json`` and refuses to overwrite an existing baseline.
``compare`` re-hashes the protected paths later and reports unchanged / missing
/ changed / added entries.  This tool never reverts, deletes, or edits any
captured file; it only reads repository content and writes the one baseline
document it was asked to create.

The baseline itself and every artifact of a new art batch are excluded so a
capture can never claim ownership of the batch it is protecting.
"""

from __future__ import annotations

import argparse
import fnmatch
import hashlib
import json
import sys
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable


TOOL_NAME = "p1_base_facilities_v01/archive.py"
BASELINE_FILENAME = "BOUNDARY_HASHES.json"

#: Relative-path globs that must be captured byte-for-byte before a new batch.
DEFAULT_PROTECTED: tuple[str, ...] = (
    "src/**",
    "content/**",
    "project.godot",
    "art/early/**",
    "art/production/**",
    "tools/art_preview/**",
    "tools/art_pipeline/**",
    "docs/art-production/**",
)

#: Relative-path globs deliberately outside the boundary.  ``art/production/**``
#: is protected only for paths that already exist; the entries below are the
#: planned additions of the current batch (its atlas, its docs, its tooling and
#: its preview harness) plus the baseline document itself.  Everything else,
#: including the older calibration graphics/qa drops, stays protected.
DEFAULT_EXCLUDES: tuple[str, ...] = (
    "art/production/p1/base_facilities_v01/**",
    "art/production/p1/base_facilities_v01",
    "docs/art-production/p1-base-facilities-v01/**",
    "docs/art-production/p1-base-facilities-v01",
    "docs/art-production/VISUAL_BASELINE.md",
    "tools/art_preview/p1_base_facilities_v01/**",
    "tools/art_preview/p1_base_facilities_v01",
    "tools/art_pipeline/p1_base_facilities_v01/**",
    "tools/art_pipeline/p1_base_facilities_v01",
    "tools/art_pipeline/**/__pycache__/**",
    "tools/art_pipeline/**/__pycache__",
    "tools/art_preview/**/__pycache__/**",
    "tools/art_preview/**/__pycache__",
)


class SnapshotError(RuntimeError):
    """Raised when a protected path cannot be captured unambiguously."""


@dataclass
class WalkResult:
    files: dict[str, str] = field(default_factory=dict)
    warnings: list[str] = field(default_factory=list)


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _sha256_text(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def _normalise_patterns(values: Iterable[str], label: str) -> tuple[str, ...]:
    patterns: list[str] = []
    for raw in values:
        text = str(raw).strip().replace("\\", "/")
        if not text:
            raise SnapshotError(f"{label} contains an empty pattern")
        if text.startswith("/"):
            raise SnapshotError(f"{label} must use repository-relative paths: {text}")
        parts = [part for part in text.split("/") if part]
        if any(part == ".." for part in parts):
            raise SnapshotError(f"{label} must not contain '..': {text}")
        patterns.append("/".join(parts))
    return tuple(dict.fromkeys(patterns))


def _matches(relative: str, patterns: Iterable[str]) -> bool:
    return any(fnmatch.fnmatchcase(relative, pattern) for pattern in patterns)


def _iter_files(root: Path, protected: tuple[str, ...], excludes: tuple[str, ...]) -> WalkResult:
    result = WalkResult()
    for path in sorted(root.rglob("*")):
        try:
            relative = path.relative_to(root).as_posix()
        except ValueError:
            continue
        is_excluded = _matches(relative, excludes)
        is_protected = _matches(relative, protected)
        if is_excluded:
            if is_protected:
                result.warnings.append(f"excluded from the boundary: {relative}")
            continue
        if not is_protected:
            continue
        if path.is_symlink():
            raise SnapshotError(f"symlinked protected path is not supported: {relative}")
        if not path.is_file():
            continue
        key = str(path.relative_to(root))
        if key in result.files:
            raise SnapshotError(f"duplicate protected path: {key}")
        result.files[key] = _sha256(path)
    return result


def _warn_missing_globs(root: Path, protected: tuple[str, ...]) -> list[str]:
    warnings: list[str] = []
    prefixes = {pattern.split("*")[0].rstrip("/") for pattern in protected}
    for prefix in sorted(prefixes):
        if not prefix:
            continue
        candidate = root / prefix
        base = candidate if candidate.is_dir() else candidate.parent
        if not base.exists():
            warnings.append(f"protected location does not exist yet: {prefix}")
    return warnings


def _entry(path: Path, root: Path) -> dict[str, Any]:
    stat = path.stat()
    return {
        "sha256": _sha256(path),
        "size": stat.st_size,
        "mtime_ns": stat.st_mtime_ns,
    }


def _resolve_baseline(root: Path, destination: Path, filename: str = BASELINE_FILENAME) -> Path:
    target = destination if destination.suffix == ".json" else destination / filename
    resolved = target if target.is_absolute() else (root / target)
    resolved = resolved.resolve()
    try:
        resolved.relative_to(root.resolve())
    except ValueError as exc:
        raise SnapshotError(f"baseline must stay inside the repository root: {resolved}") from exc
    return resolved


def capture(
    root: Path,
    destination: Path,
    *,
    protected: Iterable[str] = DEFAULT_PROTECTED,
    excludes: Iterable[str] = DEFAULT_EXCLUDES,
    filename: str = BASELINE_FILENAME,
    force: bool = False,
    note: str | None = None,
) -> dict[str, Any]:
    """Write a new instant-boundary snapshot; never overwrite an existing one."""
    root = root.resolve()
    if not root.is_dir():
        raise SnapshotError(f"repository root is missing: {root}")
    protected_patterns = _normalise_patterns(protected, "protected")
    exclude_patterns = _normalise_patterns(excludes, "excludes")
    baseline_path = _resolve_baseline(root, destination, filename)
    if baseline_path.exists() and not force:
        raise SnapshotError(f"refusing to overwrite existing baseline: {baseline_path}")
    if baseline_path.exists() and (baseline_path.is_symlink() or not baseline_path.is_file()):
        raise SnapshotError(f"baseline target is not a regular file: {baseline_path}")
    baseline_path.parent.mkdir(parents=True, exist_ok=True)

    walk = _iter_files(root, protected_patterns, exclude_patterns)
    warnings = [*_warn_missing_globs(root, protected_patterns), *walk.warnings]
    files: dict[str, dict[str, Any]] = {}
    for relative in sorted(walk.files):
        files[relative] = _entry(root / relative, root)

    tool_path = Path(__file__).resolve()
    document = {
        "schema_version": 1,
        "kind": "mechanical_boundary_hash_snapshot_not_visual_approval",
        "captured_at": datetime.now(timezone.utc).isoformat(),
        "root": str(root),
        "note": note,
        "files": files,
        "summary": {
            "file_count": len(files),
            "total_bytes": sum(item["size"] for item in files.values()),
        },
        "boundary": {
            "protected": list(protected_patterns),
            "excluded": list(exclude_patterns),
        },
        "tool": {
            "name": TOOL_NAME,
            "sha256": _sha256(tool_path) if tool_path.is_file() else "",
        },
        "warnings": warnings,
    }
    baseline_path.write_text(
        json.dumps(document, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    return document


def compare(root: Path, baseline_path: Path) -> dict[str, Any]:
    """Re-hash protected paths and report drift; nothing is modified."""
    root = root.resolve()
    if not root.is_dir():
        raise SnapshotError(f"repository root is missing: {root}")
    resolved = baseline_path if baseline_path.is_absolute() else root / baseline_path
    resolved = resolved.resolve()
    if not resolved.is_file():
        raise SnapshotError(f"baseline is missing: {resolved}")
    try:
        baseline = json.loads(resolved.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise SnapshotError(f"cannot read baseline {resolved}: {exc}") from exc
    if not isinstance(baseline, dict) or not isinstance(baseline.get("files"), dict):
        raise SnapshotError("baseline document has no files map")

    boundary = baseline.get("boundary") if isinstance(baseline.get("boundary"), dict) else {}
    protected = _normalise_patterns(boundary.get("protected") or DEFAULT_PROTECTED, "protected")
    excludes = _normalise_patterns(boundary.get("excluded") or DEFAULT_EXCLUDES, "excludes")
    walk = _iter_files(root, protected, excludes)

    unchanged: list[str] = []
    changed: list[dict[str, Any]] = []
    missing: list[str] = []
    for relative, recorded in sorted(baseline["files"].items()):
        path = root / relative
        if not path.is_file():
            missing.append(relative)
            continue
        actual = _entry(path, root)
        if actual["sha256"] != recorded.get("sha256"):
            changed.append({"path": relative, "before": recorded.get("sha256"), "after": actual["sha256"]})
        else:
            unchanged.append(relative)
    added = sorted(set(walk.files) - set(baseline["files"]))
    return {
        "baseline": str(resolved),
        "captured_at": baseline.get("captured_at"),
        "unchanged": unchanged,
        "changed": changed,
        "missing": missing,
        "added": added,
        "summary": {
            "unchanged": len(unchanged),
            "changed": len(changed),
            "missing": len(missing),
            "added": len(added),
        },
        "warnings": walk.warnings,
    }


def _load_patterns(values: list[str] | None, fallback: tuple[str, ...], label: str) -> tuple[str, ...]:
    return _normalise_patterns(values, label) if values else fallback


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path.cwd(), help="repository root (default: cwd)")
    sub = parser.add_subparsers(dest="command", required=True)

    snapshot = sub.add_parser("snapshot", help="capture a new boundary baseline")
    snapshot.add_argument("--output", required=True, type=Path, help="baseline file or its new directory")
    snapshot.add_argument("--protected", action="append", help="extra protected glob (repeatable)")
    snapshot.add_argument("--exclude", action="append", help="extra excluded glob (repeatable)")
    snapshot.add_argument("--force", action="store_true", help="replace an existing baseline document")
    snapshot.add_argument(
        "--filename",
        default=BASELINE_FILENAME,
        help=f"baseline file name when --output is a directory (default: {BASELINE_FILENAME})",
    )
    snapshot.add_argument("--note", help="free-form note stored in the baseline")

    check = sub.add_parser("compare", help="report drift against a baseline")
    check.add_argument("--baseline", required=True, type=Path, help="existing BOUNDARY_HASHES.json")

    listing = sub.add_parser("list-paths", help="print the paths a capture would cover")
    listing.add_argument("--protected", action="append", help="extra protected glob (repeatable)")
    listing.add_argument("--exclude", action="append", help="extra excluded glob (repeatable)")

    args = parser.parse_args(argv)
    try:
        if args.command == "snapshot":
            protected = _load_patterns(args.protected, DEFAULT_PROTECTED, "protected")
            excludes = _load_patterns(args.exclude, DEFAULT_EXCLUDES, "excludes")
            document = capture(
                args.root,
                args.output,
                protected=protected,
                excludes=excludes,
                filename=args.filename,
                force=args.force,
                note=args.note,
            )
            target = _resolve_baseline(args.root.resolve(), args.output, args.filename)
            print(
                json.dumps(
                    {
                        "captured": str(target),
                        "file_count": document["summary"]["file_count"],
                        "total_bytes": document["summary"]["total_bytes"],
                        "warnings": len(document["warnings"]),
                    },
                    sort_keys=True,
                )
            )
            return 0
        if args.command == "compare":
            report = compare(args.root, args.baseline)
            print(json.dumps(report["summary"], sort_keys=True))
            for entry in report["changed"]:
                print(f"CHANGED: {entry['path']}")
            for name in report["missing"]:
                print(f"MISSING: {name}")
            for name in report["added"]:
                print(f"ADDED: {name}")
            for warning in report["warnings"]:
                print(f"WARNING: {warning}")
            drift = report["summary"]["changed"] + report["summary"]["missing"]
            print(f"COMPARE {'PASS' if not drift else 'FAIL'}: mechanical only, nothing reverted")
            return 0 if not drift else 1

        protected = _load_patterns(args.protected, DEFAULT_PROTECTED, "protected")
        excludes = _load_patterns(args.exclude, DEFAULT_EXCLUDES, "excludes")
        walk = _iter_files(args.root.resolve(), protected, excludes)
        print(json.dumps({"count": len(walk.files)}, sort_keys=True))
        for name in sorted(walk.files):
            print(name)
        for warning in walk.warnings:
            print(f"WARNING: {warning}", file=sys.stderr)
        return 0
    except SnapshotError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        print("SNAPSHOT/COMPARE FAIL: no files were modified")
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
