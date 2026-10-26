"""Helpers shared by the art pipelines.

Pipelines run as scripts (``python3 tools/art_pipeline/<name>/build.py``), so each
one makes this module importable with the same two lines before its other
imports::

    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
    import common  # noqa: E402

Every helper keeps the behaviour of the per-pipeline copies it replaced. Where
the copies differed (error type, JSON escaping), the difference is an explicit
parameter so generated files stay byte-identical.
"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any, Callable, Iterable

_CHUNK_BYTES = 1024 * 1024


def sha256_file(path: Path) -> str:
    """Hex SHA-256 of a file, read in 1 MiB blocks."""
    digest = hashlib.sha256()
    with Path(path).open("rb") as handle:
        for block in iter(lambda: handle.read(_CHUNK_BYTES), b""):
            digest.update(block)
    return digest.hexdigest()


def display_path(path: Path, root: Path) -> str:
    """Resolved path relative to ``root``, or the resolved absolute path outside it."""
    try:
        return str(path.resolve().relative_to(root.resolve()))
    except ValueError:
        return str(path.resolve())


def load_json(path: Path, label: str = "JSON", error: type[Exception] = ValueError) -> dict[str, Any]:
    """Read a JSON object, raising ``error`` for unreadable, invalid or non-object files."""
    try:
        value = json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise error(f"cannot read {label} {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise error(f"{label} root must be an object")
    return value


def write_json(path: Path, value: Any, *, ensure_ascii: bool = False, sort_keys: bool = True) -> None:
    """Write indented JSON with a trailing newline (UTF-8)."""
    text = json.dumps(value, ensure_ascii=ensure_ascii, indent=2, sort_keys=sort_keys) + "\n"
    Path(path).write_text(text, encoding="utf-8")


def guard_generated_output(
    output: Path,
    replace_generated: bool,
    previous_artifact_paths: Callable[[Path], Iterable[Path]],
    error: type[Exception],
    extra_allowed: Iterable[Path] = (),
) -> None:
    """Refuse to write into an output directory unless every entry is manifest-owned.

    A missing or empty directory is fine. A non-empty one needs
    ``replace_generated`` and may then contain only the paths returned by
    ``previous_artifact_paths(output)`` plus ``extra_allowed``, none of them symlinks.
    """
    if not output.exists():
        return
    if not output.is_dir():
        raise error(f"output exists and is not a directory: {output}")
    existing = list(output.iterdir())
    if not existing:
        return
    if not replace_generated:
        raise error(
            f"output directory is not empty: {output}; pass --replace-generated to replace only "
            "manifest-owned files"
        )
    allowed = {path.resolve() for path in previous_artifact_paths(output)}
    allowed.update(Path(path).resolve() for path in extra_allowed)
    for item in existing:
        if item.resolve() not in allowed:
            raise error(f"refusing to replace unmanaged output entry: {item}")
        if item.is_symlink():
            raise error(f"refusing to replace symlinked output entry: {item}")


# Checkout roots that earlier host layouts baked into recipes and manifests as
# absolute paths. The first entry is the root those files were last rewritten to;
# the later ones are roots that appear only in recorded hashes.
LEGACY_ROOTS = ("/data/paseo-makeitbig/project", "/data/repo/makeitbig")
REPO_ROOT = Path(__file__).resolve().parents[2]


def rebase_legacy_path(value: Any) -> Path:
    """Map a path recorded under a retired checkout root onto this checkout.

    Paths outside the legacy roots (including relative ones) are returned
    unchanged, so a recipe written for the current checkout keeps working.
    """
    text = str(value)
    for legacy in LEGACY_ROOTS:
        if text == legacy or text.startswith(legacy + "/"):
            return REPO_ROOT / text[len(legacy):].lstrip("/")
    return Path(text)


def config_hash_matches(recorded: Any, config_path: Path) -> bool:
    """True when ``recorded`` is the SHA-256 of the recipe as it was built.

    A recipe whose absolute paths were later rewritten from one legacy root to
    another no longer hashes to the recorded value. Reversing exactly that
    textual rewrite reproduces the original bytes, so the match stays an exact
    byte-for-byte proof rather than a relaxed comparison.
    """
    if not isinstance(recorded, str):
        return False
    if sha256_file(config_path) == recorded:
        return True
    data = Path(config_path).read_bytes()
    current = LEGACY_ROOTS[0].encode()
    for legacy in LEGACY_ROOTS[1:]:
        if hashlib.sha256(data.replace(current, legacy.encode())).hexdigest() == recorded:
            return True
    return False
