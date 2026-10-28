#!/usr/bin/env python3
"""Check a distributable Universal 2 ZIP without claiming a native macOS run."""
import argparse
import hashlib
import plistlib
import stat
import struct
import zipfile
from pathlib import PurePosixPath


def require(condition, message):
    if not condition:
        raise ValueError(message)


def verify_macho(binary):
    require(binary[:4] == b"\xca\xfe\xba\xbe", "executable is not a universal Mach-O")
    count = struct.unpack_from(">I", binary, 4)[0]
    require(count == 2, "expected exactly ARM64 and x86_64 slices")
    architectures = set()
    for index in range(count):
        cpu, _, offset, size, _ = struct.unpack_from(">5I", binary, 8 + index * 20)
        require(offset >= 48 and offset + size <= len(binary), "invalid Mach-O slice bounds")
        image = binary[offset:offset + size]
        require(image[:4] == b"\xcf\xfa\xed\xfe", "slice is not a 64-bit Mach-O")
        require(struct.unpack_from("<I", image, 4)[0] == cpu, "slice CPU does not match fat header")
        architectures.add(cpu)
        commands, commands_size = struct.unpack_from("<2I", image, 16)
        require(32 + commands_size <= len(image), "invalid Mach-O load commands")
        cursor, signature = 32, None
        for _ in range(commands):
            command, length = struct.unpack_from("<2I", image, cursor)
            require(length >= 8 and cursor + length <= 32 + commands_size, "invalid Mach-O command")
            if command == 0x1D:  # LC_CODE_SIGNATURE
                require(length >= 16, "truncated signature command")
                signature = struct.unpack_from("<2I", image, cursor + 8)
            cursor += length
        require(signature is not None, "missing code signature")
        start, length = signature
        require(start + length <= len(image), "signature extends beyond slice")
        blob = image[start:start + length]
        magic, blob_length, slots = struct.unpack_from(">3I", blob)
        require(magic == 0xFADE0CC0 and blob_length <= len(blob), "invalid signature blob")
        verified = False
        for slot in range(slots):
            kind, location = struct.unpack_from(">2I", blob, 12 + slot * 8)
            if kind != 0:  # Primary CodeDirectory
                continue
            directory = blob[location:]
            magic, size, _, flags, hashes, _, _, pages, limit = struct.unpack_from(">9I", directory)
            require(magic == 0xFADE0C02 and size <= len(directory), "invalid code directory")
            require(flags & 2, "expected an ad-hoc signature")
            hash_size, hash_type, _, page_power = directory[36:40]
            require(hash_type in (1, 2, 3, 4) and 0 < page_power <= 20, "unsupported code hash")
            algorithm = {1: "sha1", 2: "sha256", 3: "sha256", 4: "sha384"}[hash_type]
            require(hash_size == {1: 20, 2: 32, 3: 20, 4: 48}[hash_type], "invalid code hash size")
            page_size = 1 << page_power
            require(limit == start and pages == (limit + page_size - 1) // page_size,
                    "code signature does not cover the executable")
            require(hashes + pages * hash_size <= size, "truncated code hashes")
            for page in range(pages):
                data = image[page * page_size:min((page + 1) * page_size, limit)]
                digest = hashlib.new(algorithm, data).digest()[:hash_size]
                expected = directory[hashes + page * hash_size:hashes + (page + 1) * hash_size]
                require(digest == expected, "executable code signature hash mismatch")
            verified = True
        require(verified, "missing primary code directory")
    require(architectures == {0x01000007, 0x0100000C}, "missing ARM64 or x86_64 architecture")
    return ["arm64", "x86_64"]


def verify(path):
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        require(len(names) == len(set(names)), "duplicate ZIP members")
        for name in names:
            parts = PurePosixPath(name)
            require(not parts.is_absolute() and ".." not in parts.parts and "\\" not in name,
                    "unsafe ZIP member")
        require(archive.testzip() is None, "ZIP CRC failure")
        root = "Make It Big.app/Contents/"
        info_bytes = archive.read(root + "Info.plist")
        info = plistlib.loads(info_bytes)
        require(info.get("CFBundleIdentifier") == "com.rapidhere121345.makeitbig", "wrong bundle ID")
        require(info.get("CFBundlePackageType") == "APPL", "invalid app bundle type")
        require(info.get("NSHighResolutionCapable") is True, "Retina support is disabled")
        executable = info.get("CFBundleExecutable", "")
        require(executable and "/" not in executable, "invalid executable name")
        entry = archive.getinfo(root + "MacOS/" + executable)
        require((entry.external_attr >> 16) & stat.S_IXUSR, "executable permission was lost")
        architectures = verify_macho(archive.read(entry))
        packs = [name for name in names if name.startswith(root + "Resources/") and name.endswith(".pck")]
        require(len(packs) == 1, "expected one game resource pack")
        with archive.open(packs[0]) as pack:
            require(pack.read(4) == b"GDPC", "invalid game resource pack")
        resources = plistlib.loads(archive.read(root + "_CodeSignature/CodeResources"))
        # Verify the signed resource manifest covers the actual resource bytes.
        files = resources.get("files2", {})
        pack_key = packs[0].removeprefix(root)
        require(pack_key in files and "hash2" in files[pack_key], "game pack is absent from signature")
        for relative, metadata in files.items():
            if not isinstance(metadata, dict) or "hash2" not in metadata:
                continue
            require(".." not in PurePosixPath(relative).parts, "unsafe signed resource path")
            actual = hashlib.sha256(archive.read(root + relative)).digest()
            require(actual == metadata["hash2"], "signed resource hash mismatch: " + relative)
    return {"architectures": architectures, "signing": "ad-hoc", "retina": True}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive")
    args = parser.parse_args()
    try:
        result = verify(args.archive)
    except (ValueError, KeyError, OSError, zipfile.BadZipFile, struct.error) as error:
        parser.exit(1, "MACOS_EXPORT_FAIL: " + str(error) + "\n")
    print("MACOS_EXPORT_PASS", result)


if __name__ == "__main__":
    main()
