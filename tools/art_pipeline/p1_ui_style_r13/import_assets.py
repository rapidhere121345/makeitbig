"""Import only this UI pack using a tiny isolated Godot project.

Avoid a whole shared-project editor/import scan during parallel art production.
Source .import sidecars stay inside this pack; .ctex/.md5 go to Godot's cache.
"""
from pathlib import Path
import os
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[3]
SCOPE = Path("/data/tmp/mib-r13-ui-style-20261007-import")
REL = Path("art/production/p1/ui_style_r13")
GODOT = "/data/tools/godot-4.7.2/Godot_v4.7.2-stable_linux.x86_64"


def main():
    staging = SCOPE / REL
    staging.mkdir(parents=True, exist_ok=True)
    for source in (ROOT / REL).glob("*.png"):
        shutil.copy2(source, staging / source.name)
    (SCOPE / "project.godot").write_text('config_version=5\n[application]\nconfig/name="R13 scoped import"\n')
    env = dict(os.environ, XDG_DATA_HOME=str(SCOPE / "xdg"))
    command = [GODOT, "--headless", "--path", str(SCOPE), "--editor", "--import"]
    result = subprocess.run(command, env=env, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, text=True, timeout=120)
    (SCOPE / "IMPORT.log").write_text(result.stdout)
    if result.returncode:
        raise SystemExit(result.returncode)
    for source in staging.glob("*.import"):
        shutil.copy2(source, ROOT / REL / source.name)
    cache = ROOT / ".godot/imported"
    cache.mkdir(parents=True, exist_ok=True)
    for extension in ["*.ctex", "*.md5"]:
        for source in (SCOPE / ".godot/imported").glob(extension):
            shutil.copy2(source, cache / source.name)
    print("Imported only", REL, "via", SCOPE)


if __name__ == "__main__":
    main()
