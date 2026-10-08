#!/usr/bin/env python3
"""Repack the packaged Chinese UI font for Make It Big (2026-09-14).

Why this exists
---------------
ShellTheme.create() must not depend on a SystemFont / on fonts installed on the
player machine. The production font therefore ships inside the project.

The locally installed redistributable source is Debian's fonts-noto-cjk package
(/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc). That file is a *TrueType
collection*: it carries ten faces and Godot 4.7 FontFile exposes no face_index
property, so Godot would always resolve a .ttc to face 0, which is
"Noto Sans CJK JP" - the wrong regional face for Simplified Chinese UI text.

So the Simplified Chinese face (index 2, "Noto Sans CJK SC" Regular) is repacked
into a standalone single-face OTF. Coverage is *complete*: the charset is the
face's own whole cmap, read from the source font, not a hand-picked character
list. Nothing is narrowed, so no glyph that the source face could draw is lost.

No download and no fontTools: subsetting goes through the libharfbuzz-subset
library that is already installed on this host, driven via ctypes.

Usage
-----
    python3 tools/art_pipeline/repack_ui_font.py
    python3 tools/art_pipeline/repack_ui_font.py --check

--check re-derives the output in memory and compares it byte-for-byte with the
shipped file instead of writing anything.

An optional --charset-file narrows coverage to a UTF-8 charset file. It is not
used for the shipped font; the shipped artifact is the complete SC face.
"""

from __future__ import annotations

import argparse
import ctypes
import hashlib
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
SOURCE_TTC = Path("/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc")
SOURCE_FACE_INDEX = 2  # fc-scan: 2 = "Noto Sans CJK SC" Regular
DEFAULT_OUT = REPO / "art" / "fonts" / "NotoSansCJKsc-Regular.mib-repack.otf"

HB_SET = ctypes.c_void_p
HB_FACE = ctypes.c_void_p
HB_BLOB = ctypes.c_void_p
HB_SUBSET_INPUT = ctypes.c_void_p


def _load() -> tuple[ctypes.CDLL, ctypes.CDLL]:
    hb = ctypes.CDLL("libharfbuzz.so.0")
    hbsub = ctypes.CDLL("libharfbuzz-subset.so.0")
    return hb, hbsub


def _bind(hb: ctypes.CDLL, hbsub: ctypes.CDLL) -> None:
    hb.hb_blob_create_from_file_or_fail.argtypes = [ctypes.c_char_p]
    hb.hb_blob_create_from_file_or_fail.restype = HB_BLOB
    hb.hb_blob_get_data.argtypes = [HB_BLOB, ctypes.POINTER(ctypes.c_uint)]
    hb.hb_blob_get_data.restype = ctypes.POINTER(ctypes.c_char)
    hb.hb_blob_get_length.argtypes = [HB_BLOB]
    hb.hb_blob_get_length.restype = ctypes.c_uint
    hb.hb_blob_destroy.argtypes = [HB_BLOB]
    hb.hb_face_create.argtypes = [HB_BLOB, ctypes.c_uint]
    hb.hb_face_create.restype = HB_FACE
    hb.hb_face_destroy.argtypes = [HB_FACE]
    hb.hb_face_reference_blob.argtypes = [HB_FACE]
    hb.hb_face_reference_blob.restype = HB_BLOB
    hb.hb_face_get_glyph_count.argtypes = [HB_FACE]
    hb.hb_face_get_glyph_count.restype = ctypes.c_uint
    hb.hb_face_collect_unicodes.argtypes = [HB_FACE, HB_SET]
    hb.hb_set_create.restype = HB_SET
    hb.hb_set_clear.argtypes = [HB_SET]
    hb.hb_set_union.argtypes = [HB_SET, HB_SET]
    hb.hb_set_add.argtypes = [HB_SET, ctypes.c_uint32]
    hb.hb_set_get_population.argtypes = [HB_SET]
    hb.hb_set_get_population.restype = ctypes.c_uint
    hb.hb_set_destroy.argtypes = [HB_SET]
    # hb_language_t is an opaque interned pointer, not a numeric tag.
    hb.hb_language_from_string.argtypes = [ctypes.c_char_p, ctypes.c_int]
    hb.hb_language_from_string.restype = ctypes.c_void_p
    hb.hb_ot_name_get_utf8.argtypes = [
        HB_FACE, ctypes.c_uint, ctypes.c_void_p, ctypes.POINTER(ctypes.c_uint), ctypes.c_char_p
    ]
    hb.hb_ot_name_get_utf8.restype = ctypes.c_uint
    hbsub.hb_subset_input_create_or_fail.restype = HB_SUBSET_INPUT
    hbsub.hb_subset_input_destroy.argtypes = [HB_SUBSET_INPUT]
    hbsub.hb_subset_input_unicode_set.argtypes = [HB_SUBSET_INPUT]
    hbsub.hb_subset_input_unicode_set.restype = HB_SET
    hbsub.hb_subset_input_set_flags.argtypes = [HB_SUBSET_INPUT, ctypes.c_uint]
    hbsub.hb_subset_or_fail.argtypes = [HB_FACE, HB_SUBSET_INPUT]
    hbsub.hb_subset_or_fail.restype = HB_FACE


NAME_FAMILY = 1
SUBSET_FLAGS = 8  # HB_SUBSET_FLAGS_NAME_LEGACY: keep the original name-table entries


def _blob_bytes(hb: ctypes.CDLL, blob: HB_BLOB) -> bytes:
    length = ctypes.c_uint(0)
    data = hb.hb_blob_get_data(blob, ctypes.byref(length))
    return ctypes.string_at(data, length.value)


def _family_name(hb: ctypes.CDLL, face: HB_FACE) -> str:
    """Read name ID 1. A NULL language means "any"; that is what the source TTC needs."""
    for language in (None, hb.hb_language_from_string(b"en", -1)):
        buf = ctypes.create_string_buffer(1024)
        size = ctypes.c_uint(len(buf))
        hb.hb_ot_name_get_utf8(face, NAME_FAMILY, language, ctypes.byref(size), buf)
        if size.value:
            return buf.raw[: size.value].decode("utf-8", "replace")
    return ""


def _face_facts(hb: ctypes.CDLL, blob: HB_BLOB, index: int) -> dict:
    face = hb.hb_face_create(blob, index)
    if not face:
        raise SystemExit("harfbuzz could not create a face from the source blob")
    uncodes = hb.hb_set_create()
    hb.hb_face_collect_unicodes(face, uncodes)
    facts = {
        "family": _family_name(hb, face),
        "glyphs": int(hb.hb_face_get_glyph_count(face)),
        "unicodes": int(hb.hb_set_get_population(uncodes)),
        "_face": face,
        "_unicodes": uncodes,
    }
    return facts


def build(charset_file: Path | None) -> tuple[bytes, dict, dict]:
    hb, hbsub = _load()
    _bind(hb, hbsub)

    source_blob = hb.hb_blob_create_from_file_or_fail(str(SOURCE_TTC).encode())
    if not source_blob:
        raise SystemExit(f"cannot read {SOURCE_TTC}")

    source = _face_facts(hb, source_blob, SOURCE_FACE_INDEX)
    source_face = source["_face"]

    subset_input = hbsub.hb_subset_input_create_or_fail()
    if not subset_input:
        raise SystemExit("hb_subset_input_create_or_fail returned null")
    hbsub.hb_subset_input_set_flags(subset_input, SUBSET_FLAGS)

    target = hbsub.hb_subset_input_unicode_set(subset_input)
    hb.hb_set_clear(target)
    if charset_file is None:
        # Complete coverage: keep every codepoint the SC face can draw.
        hb.hb_set_union(target, source["_unicodes"])
        requested = int(hb.hb_set_get_population(target))
        charset_basis = "whole cmap of source face 2 (Noto Sans CJK SC), nothing removed"
    else:
        text = charset_file.read_text(encoding="utf-8")
        codepoints = {ord(ch) for ch in text}
        for codepoint in sorted(codepoints):
            hb.hb_set_add(target, codepoint)
        requested = len(codepoints)
        charset_basis = f"explicit charset file {charset_file} ({requested} codepoints)"

    subset_face = hbsub.hb_subset_or_fail(source_face, subset_input)
    if not subset_face:
        raise SystemExit("hb_subset_or_fail returned null")
    data = _blob_bytes(hb, hb.hb_face_reference_blob(subset_face))

    meta = {
        "source_ttc": str(SOURCE_TTC),
        "source_face_index": SOURCE_FACE_INDEX,
        "source_family": source["family"],
        "source_glyphs": source["glyphs"],
        "source_unicodes": source["unicodes"],
        "charset_basis": charset_basis,
        "requested_codepoints": requested,
        "subset_flags": SUBSET_FLAGS,
    }
    return data, meta, source


def verify(data: bytes, meta: dict, source: dict) -> list[str]:
    """Compare the repacked font against the source face, using harfbuzz itself."""
    hb, hbsub = _load()
    _bind(hb, hbsub)
    problems: list[str] = []

    tmp = Path("/data/tmp") / "mib-ui-font-verify.otf"
    tmp.parent.mkdir(parents=True, exist_ok=True)
    tmp.write_bytes(data)
    try:
        blob = hb.hb_blob_create_from_file_or_fail(str(tmp).encode())
        if not blob:
            return ["repacked font could not be reopened"]
        out = _face_facts(hb, blob, 0)
    finally:
        tmp.unlink(missing_ok=True)

    if out["unicodes"] != meta["requested_codepoints"]:
        problems.append(
            f"unicode coverage {out['unicodes']} != requested {meta['requested_codepoints']}"
        )
    if out["glyphs"] < 1:
        problems.append("repacked font has no glyphs")
    if not out["family"]:
        problems.append("repacked font lost its family name")

    print(f"  repacked family      : {out['family']}")
    print(f"  source family        : {source['family']}")
    print(f"  repacked glyphs      : {out['glyphs']}")
    print(f"  repacked unicodes    : {out['unicodes']}")
    print(f"  source glyphs        : {meta['source_glyphs']}")
    print(f"  source unicodes      : {meta['source_unicodes']}")
    return problems


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--charset-file", type=Path, default=None)
    parser.add_argument("--check", action="store_true", help="compare without writing")
    args = parser.parse_args()

    source_sha = hashlib.sha256(SOURCE_TTC.read_bytes()).hexdigest()
    print(f"source : {SOURCE_TTC}")
    print(f"sha256 : {source_sha}")

    data, meta, source = build(args.charset_file)
    digest = hashlib.sha256(data).hexdigest()
    print(f"charset: {meta['charset_basis']}")
    print(f"bytes  : {len(data)}")
    print(f"sha256 : {digest}")

    problems = verify(data, meta, source)

    if args.check:
        if not args.output.exists():
            problems.append(f"{args.output} does not exist")
        else:
            shipped = args.output.read_bytes()
            if shipped != data:
                problems.append(
                    f"{args.output.name} differs from a fresh repack "
                    f"(shipped {hashlib.sha256(shipped).hexdigest()})"
                )
            else:
                print("check  : shipped file is byte-identical to a fresh repack")
    else:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        tmp = args.output.with_suffix(args.output.suffix + ".tmp")
        tmp.write_bytes(data)
        tmp.replace(args.output)
        print(f"wrote  : {args.output}")

    if problems:
        for problem in problems:
            print(f"FAIL   : {problem}", file=sys.stderr)
        return 1
    print("PASS   : repack verified")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
