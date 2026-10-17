"""Import only this pack, keeping editor writes out of the shared project."""
import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
from pathlib import Path


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--evidence-dir", required=True)
    parser.add_argument("--godot", default=os.environ.get("GODOT_BIN", "/data/paseo-makeitbig/bin/godot"))
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[3]
    relative = Path("art/production/p1/combat_style_r13/v03")
    production = repo / relative
    evidence = Path(args.evidence_dir).resolve()
    if not str(evidence).startswith("/data/tmp/mib-r13-combat-style-20261007-"):
        raise SystemExit("evidence directory must use the task prefix")
    isolated = evidence / "import_project"
    isolated.mkdir(parents=True, exist_ok=False)
    target = isolated / relative
    target.mkdir(parents=True)
    pngs = sorted(production.glob("*.png"))
    if len(pngs) != 11:
        raise SystemExit("expected exactly 11 production PNGs")
    for png in pngs:
        shutil.copy2(png, target / png.name)
    (isolated / "project.godot").write_text(
        'config_version=5\n\n[application]\nconfig/name="R13 isolated texture import"\n\n'
        '[rendering]\nrenderer/rendering_method="gl_compatibility"\n'
        'textures/canvas_textures/default_texture_filter=0\n'
    )
    result = subprocess.run([args.godot, "--headless", "--editor", "--path", str(isolated), "--import"], check=False)
    if result.returncode:
        raise SystemExit(result.returncode)
    # Preserve every authored visible RGBA byte. Godot's alpha-border repair
    # also changes some nonzero-alpha edge colours in the generated scenery.
    for metadata in target.glob("*.png.import"):
        metadata.write_text(metadata.read_text().replace(
            "process/fix_alpha_border=true", "process/fix_alpha_border=false"))
    result = subprocess.run([args.godot, "--headless", "--editor", "--path", str(isolated), "--import"], check=False)
    if result.returncode:
        raise SystemExit(result.returncode)
    receipt = []
    for png in pngs:
        metadata = target / (png.name + ".import")
        text = metadata.read_text()
        match = re.search(r'^path="(res://\.godot/imported/[^"]+\.ctex)"', text, re.MULTILINE)
        if not match:
            raise SystemExit("missing native CTEX remap: " + str(metadata))
        cache_path = match[1]
        cache = isolated / cache_path.removeprefix("res://")
        destination = repo / cache_path.removeprefix("res://")
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(cache, destination)
        md5 = cache.with_suffix(".md5")
        if md5.exists():
            shutil.copy2(md5, destination.with_suffix(".md5"))
        published_metadata = production / (png.name + ".import")
        if published_metadata.exists():
            shutil.copy2(published_metadata, evidence / (png.name + ".pre_import"))
        published_metadata.write_text(text)
        receipt.append({
            "source_png": "res://" + str(png.relative_to(repo)),
            "source_sha256": sha(png),
            "godot_import_metadata": "res://" + str(published_metadata.relative_to(repo)),
            "imported_texture": cache_path,
            "imported_sha256": sha(destination),
            "isolated_editor_import": str(metadata),
            "compression": "lossless, no mipmaps, alpha-border repair disabled; original visible RGBA retained",
        })
    (production / "TEXTURE_IMPORTS.json").write_text(json.dumps({
        "status": "pass", "operation": "Godot native import in isolated project; publish standard .import remaps and rebuildable .godot cache",
        "shared_editor_import": False, "pngs_overwritten": False, "textures": receipt,
    }, indent=2) + "\n")
    print("COMBAT_STYLE_R13_TEXTURE_IMPORT_PASS textures=11")


if __name__ == "__main__":
    main()
