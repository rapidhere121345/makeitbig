"""Publish native Godot imports for the five frozen R14 portraits.

The temporary project keeps editor scans away from concurrent test processes.
This changes import metadata/cache only; authored PNG bytes are never rewritten.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--godot", default="/data/tools/godot-4.7.2/Godot_v4.7.2-stable_linux.x86_64")
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[3]
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=False)
    frozen_path = repo / "docs/art-production/p1-story-portraits-r14/FROZEN.json"
    frozen = json.loads(frozen_path.read_text())
    entries = frozen["pngs"]
    assert frozen["status"] == "FROZEN" and len(entries) == 5
    isolated = out / "import_project"
    isolated.mkdir()
    (isolated / "project.godot").write_text(
        'config_version=5\n\n[application]\nconfig/name="R14 portrait import"\n\n'
        '[rendering]\nrenderer/rendering_method="gl_compatibility"\n'
        'textures/canvas_textures/default_texture_filter=0\n'
    )
    for entry in entries:
        source = repo / entry["path"]
        assert sha(source) == entry["sha256"], str(source)
        target = isolated / entry["path"]
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
    env = os.environ.copy()
    for key, suffix in (("XDG_DATA_HOME", "data"), ("XDG_CONFIG_HOME", "config"), ("XDG_CACHE_HOME", "cache")):
        env[key] = str(out / ("xdg-" + suffix))
    command = [args.godot, "--headless", "--editor", "--path", str(isolated), "--import"]
    processes = []
    for attempt in (1, 2):
        log = out / f"import-{attempt}.log"
        with log.open("w") as stream:
            result = subprocess.run(command, env=env, stdout=stream, stderr=subprocess.STDOUT, timeout=60)
        errors = re.findall(r"^.*(?:SCRIPT ERROR|Parse Error|ERROR:).*$", log.read_text(), re.M)
        processes.append({"command": command, "exit_code": result.returncode, "log": str(log), "errors": errors})
        (out / "PROCESS.json").write_text(json.dumps(processes, indent=2) + "\n")
        if result.returncode or errors:
            raise SystemExit("Godot import failed; see " + str(log))
        if attempt == 1:
            for entry in entries:
                metadata = isolated / (entry["path"] + ".import")
                metadata.write_text(metadata.read_text().replace("process/fix_alpha_border=true", "process/fix_alpha_border=false"))
    receipt = []
    for entry in entries:
        metadata = isolated / (entry["path"] + ".import")
        value = metadata.read_text()
        assert "process/fix_alpha_border=false" in value
        match = re.search(r'^path="(res://\.godot/imported/[^\"]+\.ctex)"', value, re.M)
        assert match, str(metadata)
        relative = Path(match[1].removeprefix("res://"))
        destination = repo / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(isolated / relative, destination)
        md5 = (isolated / relative).with_suffix(".md5")
        if md5.exists():
            shutil.copy2(md5, destination.with_suffix(".md5"))
        published_metadata = repo / (entry["path"] + ".import")
        if published_metadata.exists():
            shutil.copy2(published_metadata, out / (entry["id"] + ".previous.import"))
        published_metadata.write_text(value)
        assert sha(repo / entry["path"]) == entry["sha256"]
        receipt.append({**entry, "imported_texture": match[1], "imported_sha256": sha(destination),
                        "metadata_sha256": sha(published_metadata)})
    (out / "IMPORT.json").write_text(json.dumps({
        "status": "pass", "version": frozen["version"], "frozen_manifest_sha256": sha(frozen_path),
        "textures": receipt, "processes": processes, "shared_editor_import": False,
        "authored_pngs_changed": False, "alpha_border_repair": False,
    }, indent=2) + "\n")
    print("R14_PORTRAIT_IMPORT_PASS textures=5")


if __name__ == "__main__":
    main()
