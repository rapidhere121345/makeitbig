#!/usr/bin/env python3
"""Package and verify the three GitHub Release downloads; never prune history."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import shutil
import tarfile
import zipfile

TAG = re.compile(r"v\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?\Z")
ASSETS = {"linux": "make-it-big-linux-x86_64.tar.gz",
          "windows": "make-it-big-windows-x86_64.zip",
          "macos": "make-it-big-macos-universal.zip"}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(path):
    with path.open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def package(output, tag, revision, sources, notes):
    require(TAG.fullmatch(tag), "tag must be vMAJOR.MINOR.PATCH (optional prerelease suffix)")
    require(re.fullmatch(r"[0-9a-f]{40}", revision), "revision must be a full Git commit SHA")
    for platform, source in sources.items():
        require(source.is_file(), "missing " + platform + " export: " + str(source))
    require(notes.is_file(), "release notes are missing")
    require(not output.exists(), "refusing to replace an existing release package: " + str(output))
    output.mkdir(parents=True)
    with tarfile.open(output / ASSETS["linux"], "w:gz") as archive:
        info = archive.gettarinfo(str(sources["linux"]), arcname="make-it-big.x86_64")
        info.mode, info.uid, info.gid, info.uname, info.gname = 0o755, 0, 0, "", ""
        with sources["linux"].open("rb") as binary:
            archive.addfile(info, binary)
    with zipfile.ZipFile(output / ASSETS["windows"], "w", zipfile.ZIP_DEFLATED) as archive:
        archive.write(sources["windows"], "make-it-big.exe")
    # Preserve exactly the ZIP verified by the native ARM64 and Intel jobs.
    shutil.copyfile(sources["macos"], output / ASSETS["macos"])
    metadata = {"schema": 2, "project": "make-it-big", "tag": tag, "git_revision": revision,
                "created_at": datetime.now(timezone.utc).isoformat(), "files": {}}
    for platform, name in ASSETS.items():
        path = output / name
        metadata["files"][platform] = {"name": name, "size": path.stat().st_size, "sha256": digest(path)}
    (output / "build.json").write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
    (output / "RELEASE_NOTES.md").write_text(
        "# Make It Big " + tag + "\n\n" + notes.read_text(encoding="utf-8").strip()
        + "\n\nSource commit: `" + revision + "`. Verify downloads against `SHA256SUMS`.\n", encoding="utf-8")
    files = sorted([*ASSETS.values(), "build.json", "RELEASE_NOTES.md"])
    (output / "SHA256SUMS").write_text(
        "".join(digest(output / name) + "  " + name + "\n" for name in files), encoding="utf-8")
    verify(output)


def verify(output):
    metadata = json.loads((output / "build.json").read_text(encoding="utf-8"))
    require(metadata.get("schema") == 2 and metadata.get("project") == "make-it-big", "invalid release metadata")
    require(TAG.fullmatch(metadata.get("tag", "")), "invalid release tag")
    require(re.fullmatch(r"[0-9a-f]{40}", metadata.get("git_revision", "")), "invalid source revision")
    require(set(metadata.get("files", {})) == set(ASSETS), "release requires Linux, Windows, and macOS")
    expected_names = set(ASSETS.values()) | {"build.json", "RELEASE_NOTES.md"}
    checksums = {}
    for line in (output / "SHA256SUMS").read_text(encoding="utf-8").splitlines():
        checksum, name = line.split("  ", 1)
        require(name in expected_names and name not in checksums, "invalid or duplicate checksum entry")
        require(re.fullmatch(r"[0-9a-f]{64}", checksum), "invalid SHA256")
        require(not (output / name).is_symlink(), "release assets must not be symlinks")
        require(digest(output / name) == checksum, "SHA256 mismatch: " + name)
        checksums[name] = checksum
    require(set(checksums) == expected_names, "incomplete SHA256SUMS")
    for platform, name in ASSETS.items():
        path = output / name
        info = metadata["files"][platform]
        require(info.get("name") == name and info.get("sha256") == checksums[name]
                and info.get("size") == path.stat().st_size, "asset metadata mismatch: " + platform)
    with tarfile.open(output / ASSETS["linux"], "r:gz") as archive:
        members = archive.getmembers()
        require(len(members) == 1 and members[0].name == "make-it-big.x86_64"
                and members[0].isfile() and members[0].mode & 0o111, "invalid Linux executable archive")
    with zipfile.ZipFile(output / ASSETS["windows"]) as archive:
        require(archive.namelist() == ["make-it-big.exe"] and archive.testzip() is None, "invalid Windows ZIP")
    with zipfile.ZipFile(output / ASSETS["macos"]) as archive:
        require(archive.testzip() is None and "Make It Big.app/Contents/Info.plist" in archive.namelist(),
                "invalid macOS ZIP")
    return metadata


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    build = commands.add_parser("package")
    build.add_argument("output", type=Path)
    build.add_argument("--tag", required=True)
    build.add_argument("--revision", required=True)
    for platform in ASSETS:
        build.add_argument("--" + platform, type=Path, required=True)
    build.add_argument("--notes", type=Path, required=True)
    check = commands.add_parser("verify")
    check.add_argument("output", type=Path)
    args = parser.parse_args()
    try:
        if args.command == "package":
            package(args.output, args.tag, args.revision,
                    {platform: getattr(args, platform) for platform in ASSETS}, args.notes)
        else:
            verify(args.output)
    except (ValueError, OSError, KeyError, tarfile.TarError, zipfile.BadZipFile) as error:
        parser.exit(1, "RELEASE_FAIL: " + str(error) + "\n")
    print("RELEASE_PASS", args.command, args.output)


if __name__ == "__main__":
    main()
