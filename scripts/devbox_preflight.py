#!/usr/bin/env python3
"""Read-only prerequisites audit, not a substitute for game acceptance."""

import argparse
import ctypes.util
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys


GODOT_VERSION = "4.7.2"
GODOT_SHA256 = "8d106cbe6144c2dc7e881d61d2429c1a8a76e6b22ef48bd5e48dcf934953f71e"
RELEASE_TEMPLATES = ("linux_release.x86_64", "windows_release_x86_64.exe")


def run(command):
    try:
        result = subprocess.run(
            command, capture_output=True, text=True, timeout=15, check=False
        )
        return result.returncode, (result.stdout + result.stderr).strip()
    except (OSError, subprocess.TimeoutExpired) as error:
        return 1, str(error)


def executable(candidate):
    if not candidate:
        return None
    resolved = shutil.which(str(candidate))
    if resolved:
        return Path(resolved)
    path = Path(candidate)
    return path if path.is_file() and os.access(path, os.X_OK) else None


def find_godot(root, override):
    if override:
        return executable(override)
    for candidate in (
        os.environ.get("GODOT_BIN"),
        os.environ.get("MIB_GODOT_FALLBACK"), root.parent / "bin/godot",
        "godot", "godot4",
    ):
        found = executable(candidate)
        if found:
            return found
    return None


def find_templates(root, override):
    if override:
        path = Path(override)
        return path if (path / "version.txt").is_file() else None
    xdg_root = Path(os.environ.get("MIB_XDG_ROOT", root / "build/host-xdg"))
    data = Path(os.environ.get("XDG_DATA_HOME", xdg_root / "data"))
    candidates = [
        os.environ.get("MIB_GODOT_TEMPLATE_DIR"),
        data / "godot/export_templates" / (GODOT_VERSION + ".stable"),
        os.environ.get("MIB_GODOT_TEMPLATE_FALLBACK"),
        Path.home() / ".local/share/godot/export_templates" / (GODOT_VERSION + ".stable"),
    ]
    for candidate in candidates:
        if candidate and (Path(candidate) / "version.txt").is_file():
            return Path(candidate)
    return None


def audit(root, profile, godot=None, templates=None, software_ok=False, engine_binary=None):
    checks = []

    def record(name, status, detail):
        checks.append({"check": name, "status": status, "detail": str(detail)})

    def require(name, condition, detail):
        record(name, "pass" if condition else "fail", detail)

    require("platform", platform.system() == "Linux" and platform.machine() == "x86_64",
            platform.system() + " " + platform.machine() + "; Linux x86_64 required")
    require("non_root", hasattr(os, "geteuid") and os.geteuid() != 0,
            "Godot tests must run as a non-root user")
    require("workspace", root.is_dir() and os.access(root, os.W_OK),
            str(root) + "; writable checkout required")
    record("checkout", "pass" if (root / "project.godot").is_file() else "warn",
           "project.godot present" if (root / "project.godot").is_file()
           else "checkout is not here yet; only infrastructure prerequisites can be checked")
    if root.is_dir():
        free = shutil.disk_usage(root).free
        require("disk_space", free >= 4 * 1024**3,
                f"{free / 1024**3:.1f} GiB free; at least 4 GiB recommended")
    for name in ("bash", "python3", "git", "timeout", "sha256sum"):
        path = shutil.which(name)
        require("tool_" + name, path is not None, path or "not on PATH")

    binary = find_godot(root, godot)
    require("godot_binary", binary is not None, binary or "set GODOT_BIN")
    if binary:
        code, version = run([str(binary), "--version"])
        require("godot_version", code == 0 and version.startswith(GODOT_VERSION + ".stable."),
                version or "version probe failed")
        verified = Path(engine_binary or os.environ.get("MIB_GODOT_BINARY_PATH") or binary)
        require("godot_engine_path", verified.is_file() and os.access(verified, os.X_OK), verified)
        try:
            with verified.open("rb") as handle:
                hasher = hashlib.sha256()
                for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                    hasher.update(chunk)
                digest = hasher.hexdigest()
            require("godot_sha256", digest == GODOT_SHA256, digest)
        except OSError as error:
            record("godot_sha256", "fail", error)

    if profile in ("release", "all"):
        directory = find_templates(root, templates)
        require("export_templates", directory is not None,
                directory or "set MIB_GODOT_TEMPLATE_FALLBACK")
        if directory:
            try:
                version = (directory / "version.txt").read_text().strip()
                require("template_version", version == GODOT_VERSION + ".stable", version)
            except (OSError, UnicodeError) as error:
                record("template_version", "fail", error)
            for name in RELEASE_TEMPLATES:
                require("template_" + name, (directory / name).is_file(), directory / name)
        for name in ("cp", "date", "mktemp"):
            require("tool_" + name, shutil.which(name) is not None, name + " required")
        record("publication", "warn",
               "Packaging is local. Signing, hosting, ACLs and deployment need operator review.")
        record("native_windows", "warn",
               "Linux exports do not prove native Windows behavior; run Windows CI smoke/replay.")

    if profile in ("visual", "all"):
        display = os.environ.get("DISPLAY")
        require("x11_display", bool(display), display or "DISPLAY is unset")
        require("tool_xdpyinfo", shutil.which("xdpyinfo") is not None, "xdpyinfo required")
        probe = shutil.which("glxinfo") or shutil.which("mib-gl-probe")
        require("gl_probe", probe is not None,
                probe or "glxinfo or the explicitly labeled portable mib-gl-probe required")
        if display and shutil.which("xdpyinfo"):
            code, output = run(["xdpyinfo", "-display", display])
            require("display_connection", code == 0, "connected" if code == 0 else output)
        if display and probe:
            code, output = run([probe, "-B"])
            match = re.search(r"OpenGL renderer string:\s*(.+)", output)
            renderer = match.group(1) if match else output
            software = any(word in renderer.lower()
                           for word in ("llvmpipe", "softpipe", "swrast", "software rasterizer"))
            require("gl_renderer", code == 0 and match is not None and (software_ok or not software),
                    renderer)
        for name in ("GL", "Xcursor", "Xinerama", "Xi", "Xrandr", "fontconfig"):
            library = ctypes.util.find_library(name)
            record("library_" + name, "pass" if library else "warn", library or "not found")
        record("graphical_acceptance", "warn",
               "Record Godot's actual renderer/GPU and inspect screenshots after moving; "
               "glxinfo alone is not game acceptance.")

    record("art_pipeline", "pass" if importlib.util.find_spec("PIL") else "warn",
           "Pillow is needed for offline image baking/validation, not the game runtime.")
    return {
        "scope": "prerequisites_only",
        "profile": profile,
        "project_root": str(root),
        "status": "blocked" if any(c["status"] == "fail" for c in checks) else "ready",
        "checks": checks,
        "note": "No installations, migrations, project tests, exports, or deployments performed.",
    }


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", choices=("headless", "visual", "release", "all"), default="all")
    parser.add_argument("--project-root", type=Path, default=Path(__file__).resolve().parent.parent)
    parser.add_argument("--godot")
    parser.add_argument("--templates")
    parser.add_argument("--engine-binary",
                        help="Pinned raw engine to hash when --godot is a scoped launcher")
    parser.add_argument("--software-ok", action="store_true",
                        help="Allow software rendering for UI-only checks, not GPU acceptance")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args(argv)
    report = audit(args.project_root.resolve(), args.profile, args.godot,
                   args.templates, args.software_ok, args.engine_binary)
    if args.json:
        print(json.dumps(report, indent=2))
    else:
        print("Devbox prerequisites:", report["status"])
        for check in report["checks"]:
            print(f"{check['status'].upper():4} {check['check']}: {check['detail']}")
        print(report["note"])
    return 1 if report["status"] == "blocked" else 0


if __name__ == "__main__":
    sys.exit(main())
