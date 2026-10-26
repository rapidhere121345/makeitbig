#!/usr/bin/env python3
"""Deterministic compiler for world_expansion_v01 generated raws.

Reuses the generated_world_v02 primitives (rational nearest sampling, whole-object
packing, opaque/transparent pairs) so the two packages share one transform contract.

Outputs (art/production/p1/world_expansion_v01/):
  * ground  ``<id>.png``: combat grounds are fit to the configured width with one
    uniform rational scale and centre-cropped in height (never stretched); the town
    ground is a fixed crop of the raw with no resize. Fully opaque, anchor [0, 0].
  * object  ``<id>_opaque.png`` / ``<id>_transparent.png``: whole object on the
    configured canvas at the configured anchor; the transparent pair has the same RGB
    and geometry with alpha 128. ``occlusion_rect`` is the occupied rect plus 8 px.
  * ``assets.json`` (schema_version 1, the canonical manifest the runtime consumes): ``assets`` maps id -> path, canvas, anchor,
    sha256 of the PNG bytes, raw sha256 and the exact transform. Objects add
    transparent_path/transparent_sha256. Every ``.png`` gets a Godot ``.import``
    sidecar whose uid is preserved across repacks (actors_v02 recipe).

``manifest.json`` is an obsolete pending-only file from the first draft; it is no longer
written or read, and verify ignores it (it is left for the owner to remove).

Missing raws are ``pending`` and never claimed complete. Without ``--available`` any
pending asset fails the run and nothing is written. Raw sources named in
``rejected_sources`` are refused. Sources are never edited and files outside the output
directory are never written.

    python3 -I tools/art_pipeline/world_expansion_v01/pack.py --available
    python3 -I tools/art_pipeline/world_expansion_v01/pack.py --verify
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import re
import sys
from pathlib import Path

from PIL import Image

TOOL_DIR = Path(__file__).resolve().parent
REPO_ROOT = TOOL_DIR.parents[2]
DEFAULT_CONFIG = TOOL_DIR / "packing_config.json"
MANIFEST_NAME = "assets.json"
OBSOLETE_NAMES = {"manifest.json"}


def _load(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


gw = _load("_gw_v02_pack", TOOL_DIR.parent / "generated_world_v02" / "pack.py")
BuildError = gw.BuildError


def load_config(path: Path) -> dict:
    config = json.loads(path.read_text())
    if config.get("schema_version") != 1:
        raise BuildError("config schema_version must be 1")
    out = Path(config["output_dir"])
    if out.is_absolute() or ".." in out.parts:
        raise BuildError("output_dir must be repo-relative")
    ids = list(config["grounds"]) + list(config["assets"])
    if len(ids) != len(set(ids)):
        raise BuildError("ground and object ids must be unique")
    for cfg in list(config["grounds"].values()) + list(config["assets"].values()):
        src = cfg.get("source")
        if src in config.get("rejected_sources", []):
            raise BuildError(f"source {src} is rejected and must not be packed")
    return config


def sidecar_text(root: Path, png: Path, prior: str | None) -> str:
    """actors_v02 recipe: omit uid on first generation, keep the prior uid for the
    same source_file so repacks are byte-stable."""
    rel = png.resolve().relative_to(root.resolve()).as_posix()
    uid_line = ""
    if prior and f'source_file="res://{rel}"' in prior:
        m = re.search(r'^uid="(uid://[A-Za-z0-9]+)"$', prior, re.M)
        if m:
            uid_line = f'uid="{m.group(1)}"\n'
    dest = "res://.godot/imported/%s-%s.ctex" % (png.name, hashlib.md5(("res://" + rel).encode()).hexdigest())
    return (
        "[remap]\n\nimporter=\"texture\"\ntype=\"CompressedTexture2D\"\n"
        "%spath=\"%s\"\nmetadata={\n\"vram_texture\": false\n}\n\n[deps]\n\n"
        "source_file=\"res://%s\"\ndest_files=[\"%s\"]\n\n[params]\n\n"
        "compress/mode=0\ncompress/high_quality=false\ncompress/lossy_quality=0.7\n"
        "compress/uastc_level=0\ncompress/rdo_quality_loss=0.0\ncompress/hdr_compression=1\n"
        "compress/normal_map=0\ncompress/channel_pack=0\nmipmaps/generate=false\n"
        "mipmaps/limit=-1\nroughness/mode=0\nroughness/src_normal=\"\"\n"
        "process/channel_remap/red=0\nprocess/channel_remap/green=1\n"
        "process/channel_remap/blue=2\nprocess/channel_remap/alpha=3\n"
        "process/fix_alpha_border=false\nprocess/premult_alpha=false\n"
        "process/normal_map_invert_y=false\nprocess/hdr_as_srgb=false\n"
        "process/hdr_clamp_exposure=false\nprocess/size_limit=0\n"
        "detect_3d/compress_to=1\n" % (uid_line, dest, rel, dest))


def _pending(kind: str, cfg: dict, config: dict, files: dict, reason: str) -> dict:
    return {"status": "pending", "kind": kind, "reason": reason, "section": cfg.get("section"),
            "source": f"{config['source_dir']}/{cfg['source']}" if "source" in cfg else None,
            "canvas": list(cfg["canvas"]), "anchor": list(cfg["anchor"]), "path": files["path"]}


def _occlusion_override(aid: str, value, computed: list, canvas: list) -> list:
    """Optional config ``occlusion_rect``: may only grow the automatic rect, inside the canvas."""
    ok = (isinstance(value, list) and len(value) == 4
          and all(isinstance(v, int) and not isinstance(v, bool) for v in value))
    if not ok:
        raise BuildError(f"{aid}: occlusion_rect override must be four integers [x, y, w, h]")
    x, y, w, h = value
    if w <= 0 or h <= 0:
        raise BuildError(f"{aid}: occlusion_rect override must have positive size")
    if x < 0 or y < 0 or x + w > canvas[0] or y + h > canvas[1]:
        raise BuildError(f"{aid}: occlusion_rect override {value} leaves the canvas")
    cx, cy, cw, ch = computed
    if x > cx or y > cy or x + w < cx + cw or y + h < cy + ch:
        raise BuildError(f"{aid}: occlusion_rect override {value} must contain the computed rect {computed}")
    return [x, y, w, h]


def _load_raw(root: Path, config: dict, asset_id: str, cfg: dict):
    cfg = {"source": f"{asset_id}_raw.png"} | cfg
    return gw.load_raw(root, config, cfg, asset_id), cfg["source"]


def compile_pack(root: Path, config: dict) -> tuple[dict, dict[str, bytes]]:
    """Returns (manifest dict, {filename: bytes}) without touching the disk."""
    out_dir = config["output_dir"]
    defaults = {"margin": config["margin"], "alpha_threshold": config["default_alpha_threshold"]}
    entries: dict[str, dict] = {}
    files: dict[str, bytes] = {}
    for gid, cfg in sorted(config["grounds"].items()):
        name = f"{gid}.png"
        path = gw.res_path(out_dir, name)
        raw_path = root / config["source_dir"] / cfg["source"]
        if not raw_path.is_file():
            entries[gid] = _pending("ground", cfg, config, {"path": path}, "raw source missing")
            continue
        (raw, sha, _), _ = _load_raw(root, config, gid, cfg)
        if "raw_width" in cfg and raw.width != cfg["raw_width"]:
            raise BuildError(f"{gid}: raw width {raw.width} != required {cfg['raw_width']}")
        canvas, info = gw.pack_ground(raw, cfg)
        png = gw.png_bytes(canvas)
        files[name] = png
        entries[gid] = {
            "status": "packed", "kind": "ground", "section": cfg.get("section"), "path": path,
            "canvas": list(cfg["canvas"]), "anchor": list(cfg["anchor"]), "sha256": gw.sha256_bytes(png),
            "raw_sha256": sha, "raw_size": [raw.width, raw.height],
            "transform": info["transform"] | {"source": f"{config['source_dir']}/{cfg['source']}"},
        }
    for aid, cfg in sorted(config["assets"].items()):
        o_name, t_name = f"{aid}_opaque.png", f"{aid}_transparent.png"
        path = gw.res_path(out_dir, o_name)
        raw_path = root / config["source_dir"] / cfg.get("source", f"{aid}_raw.png")
        if not raw_path.is_file():
            entries[aid] = _pending("object", cfg | {"source": raw_path.name}, config, {"path": path}, "raw source missing")
            continue
        (raw, sha, _), src_name = _load_raw(root, config, aid, cfg)
        canvas, info = gw.pack_object(raw, cfg, defaults)
        entry, opaque, transparent = gw.object_manifest_entry(aid, cfg, canvas, info["transform"], sha, src_name, config)
        if entry.get("occlusion_overflow"):
            raise BuildError(f"{aid}: occlusion rect {entry['occlusion_rect']} leaves the canvas")
        if "occlusion_rect" in cfg:
            entry["occlusion_rect"] = _occlusion_override(aid, cfg["occlusion_rect"], entry["occlusion_rect"], cfg["canvas"])
        files[o_name], files[t_name] = opaque, transparent
        entries[aid] = {
            "status": "packed", "kind": "object", "section": cfg.get("section"), "reveal": cfg.get("reveal", True),
            "path": entry["opaque_path"], "transparent_path": entry["transparent_path"],
            "canvas": entry["canvas"], "anchor": entry["anchor"],
            "sha256": entry["opaque_sha256"], "transparent_sha256": entry["transparent_sha256"],
            "occupied_rect": entry["occupied_rect"], "occlusion_rect": entry["occlusion_rect"],
            "raw_sha256": sha, "raw_size": [raw.width, raw.height], "transform": entry["transform"],
        }
    manifest = {
        "schema_version": 1, "package": config["package"], "output_dir": out_dir,
        "transparent_alpha": config["transparent_alpha"], "occlusion_grow": config["occlusion_grow"],
        "assets": entries, "pending": sorted(k for k, v in entries.items() if v["status"] == "pending"),
    }
    return manifest, files


def manifest_bytes(manifest: dict) -> bytes:
    return (json.dumps(manifest, indent=2, sort_keys=True) + "\n").encode()


def write_pack(root: Path, config: dict, manifest: dict, files: dict[str, bytes]) -> None:
    out = root / config["output_dir"]
    out.mkdir(parents=True, exist_ok=True)
    for name, data in files.items():
        target = out / name
        if target.resolve().parent != out.resolve():
            raise BuildError(f"refusing to write outside the output directory: {name}")
        target.write_bytes(data)
        side = target.with_suffix(".png.import")
        side.write_text(sidecar_text(root, target, side.read_text() if side.exists() else None))
    (out / MANIFEST_NAME).write_bytes(manifest_bytes(manifest))


def verify_pack(root: Path, config: dict) -> list[str]:
    """Rebuild in memory and byte-compare against what is on disk. Returns problems."""
    problems: list[str] = []
    out = root / config["output_dir"]
    manifest, files = compile_pack(root, config)
    on_disk = out / MANIFEST_NAME
    if not on_disk.is_file():
        return [f"missing {MANIFEST_NAME}"]
    if on_disk.read_bytes() != manifest_bytes(manifest):
        problems.append(f"{MANIFEST_NAME} differs from a fresh compile")
    for name, data in files.items():
        target = out / name
        if not target.is_file():
            problems.append(f"missing {name}")
            continue
        if target.read_bytes() != data:
            problems.append(f"{name} differs from a fresh compile")
        side = target.with_suffix(".png.import")
        if not side.is_file():
            problems.append(f"missing sidecar for {name}")
        elif side.read_text() != sidecar_text(root, target, side.read_text()):
            problems.append(f"sidecar for {name} is not canonical")
    expected = set(files) | {n + ".import" for n in files} | {MANIFEST_NAME}
    for stray in sorted(p.name for p in out.iterdir() if p.name not in expected | OBSOLETE_NAMES):
        problems.append(f"unexpected file {stray}")
    return problems


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--config", type=Path, default=DEFAULT_CONFIG)
    ap.add_argument("--root", type=Path, default=REPO_ROOT)
    mode = ap.add_mutually_exclusive_group()
    mode.add_argument("--available", action="store_true", help="pack what exists; the rest stays pending")
    mode.add_argument("--verify", action="store_true", help="byte-compare a fresh compile with disk")
    args = ap.parse_args(argv)
    root = args.root.resolve()
    try:
        config = load_config(args.config)
        if args.verify:
            problems = verify_pack(root, config)
            for p in problems:
                print("VERIFY FAIL:", p, file=sys.stderr)
            if not problems:
                print("VERIFY OK: deterministic rebuild byte-identical")
            return 1 if problems else 0
        manifest, files = compile_pack(root, config)
        if manifest["pending"] and not args.available:
            print("PENDING (nothing written): " + ", ".join(manifest["pending"]), file=sys.stderr)
            return 2
        write_pack(root, config, manifest, files)
    except BuildError as exc:
        print(f"BUILD ERROR: {exc}", file=sys.stderr)
        return 1
    print(json.dumps({"packed": sorted(k for k, v in manifest["assets"].items() if v["status"] == "packed"),
                      "pending": manifest["pending"]}, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
