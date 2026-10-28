"""Reject distribution mistakes before a macOS download is offered."""
import hashlib
import importlib.util
from pathlib import Path
import plistlib
import struct
import tempfile
import unittest
import zipfile


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("macos_export", ROOT / "scripts/verify_macos_export.py")
macos = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(macos)


def signed_slice(cpu):
    image = bytearray(4096)
    struct.pack_into("<8I", image, 0, 0xFEEDFACF, cpu, 0, 2, 1, 16, 0, 0)
    # One hashed page, with the signature immediately after it.
    struct.pack_into("<4I", image, 32, 0x1D, 16, 4096, 92)
    directory = struct.pack(">9I4B", 0xFADE0C02, 72, 0x20001, 2, 40, 0, 0, 1, 4096, 32, 2, 0, 12)
    directory += hashlib.sha256(image).digest()
    signature = struct.pack(">5I", 0xFADE0CC0, 92, 1, 0, 20) + directory
    return bytes(image) + signature


def universal(cpus=(0x01000007, 0x0100000C)):
    header = bytearray(struct.pack(">2I", 0xCAFEBABE, len(cpus)))
    offset, slices = 48, []
    for cpu in cpus:
        image = signed_slice(cpu)
        header += struct.pack(">5I", cpu, 0, offset, len(image), 0)
        slices.append(image)
        offset += len(image)
    return bytes(header) + b"".join(slices)


class MacOSExportTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="mib-macos-export-")
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name) / "game.zip"

    def package(self, binary=None, executable_mode=0o100755, pack=b"GDPCfixture", signed_pack=None):
        root = "Make It Big.app/Contents/"
        info = {"CFBundleIdentifier": "com.rapidhere121345.makeitbig", "CFBundlePackageType": "APPL",
                "CFBundleExecutable": "Make It Big", "NSHighResolutionCapable": True}
        files = {"Resources/Make It Big.pck": {"hash2": hashlib.sha256(pack if signed_pack is None else signed_pack).digest()}}
        with zipfile.ZipFile(self.path, "w") as archive:
            archive.writestr(root + "Info.plist", plistlib.dumps(info))
            executable = zipfile.ZipInfo(root + "MacOS/Make It Big")
            executable.create_system = 3
            executable.external_attr = executable_mode << 16
            archive.writestr(executable, universal() if binary is None else binary)
            archive.writestr(root + "Resources/Make It Big.pck", pack)
            archive.writestr(root + "_CodeSignature/CodeResources", plistlib.dumps({"files2": files}))

    def test_universal_signed_zip_passes(self):
        self.package()
        self.assertEqual(macos.verify(self.path)["architectures"], ["arm64", "x86_64"])

    def test_duplicate_intel_slice_is_not_arm_support(self):
        self.package(binary=universal((0x01000007, 0x01000007)))
        with self.assertRaisesRegex(ValueError, "missing ARM64"):
            macos.verify(self.path)

    def test_missing_executable_permission_fails(self):
        self.package(executable_mode=0o100644)
        with self.assertRaisesRegex(ValueError, "permission"):
            macos.verify(self.path)

    def test_tampered_executable_fails_signature(self):
        binary = bytearray(universal())
        binary[48 + 300] ^= 1
        self.package(binary=binary)
        with self.assertRaisesRegex(ValueError, "signature hash mismatch"):
            macos.verify(self.path)

    def test_tampered_pack_fails_signature(self):
        self.package(pack=b"GDPCmodified", signed_pack=b"GDPCoriginal")
        with self.assertRaisesRegex(ValueError, "resource hash mismatch"):
            macos.verify(self.path)

    def test_unsafe_archive_member_fails(self):
        self.package()
        with zipfile.ZipFile(self.path, "a") as archive:
            archive.writestr("../outside", b"unsafe")
        with self.assertRaisesRegex(ValueError, "unsafe ZIP"):
            macos.verify(self.path)


if __name__ == "__main__":
    unittest.main()
