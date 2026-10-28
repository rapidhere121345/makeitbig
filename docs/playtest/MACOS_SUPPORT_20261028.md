# macOS Universal Support — 2026-10-28

Status: both frozen local regression gates, Universal macOS packaging, and
native ARM64/Intel signature, smoke, and replay checks passed.

## Delivery

The new macOS Universal preset targets Apple Silicon ARM64 and Intel x86_64 in
one ad-hoc signed ZIP, with Retina support and the existing bilingual resources.
The official 4.7.2 template minimums are macOS 13 for ARM64 and macOS 11 for
Intel. Apple Developer signing and notarization are not configured.

Exports default to Linux, Windows, and macOS; explicit target arguments support
partial environments. Release packaging, checksums, and the download page
recognize macOS while keeping older Windows/Linux-only builds usable.
No live release publication or retention pruning has been performed.

## Local Evidence

Evidence root: ignored `build/current/macos-support-20261028/`.

- Static shell/Python/Godot checks, JavaScript syntax, and Tailscale source
  validation pass.
- Six ZIP-validator tests reject missing ARM support, missing executable flags,
  executable/resource hash tampering, and unsafe archive paths.
- Eleven prerequisite tests include a required macOS-template check.
- The release integration fixture packages an older Windows/Linux build and a
  macOS-only build, indexes both, generates the page, and passes deep checksum
  verification without touching existing releases.
- `RESULT.json` records PASS for `build.sh linux windows`, 14:12:25Z–14:22:37Z:
  216 test steps passed, zero failed; 600/600 encounter victories; matching golden
  replays at 30/60/144 Hz and with presentation off; Linux/Windows exports; and
  empty-directory Linux smoke. All 1,486 frozen inputs remained unchanged.
  Existing scene-fixture shutdown resource warnings remain in the logs.
- Local Linux SHA256: `e395a892eb3305fe2b70d7114ab4ea2d4ac4c861daaf486acf533438445bffc4`.
- Local Windows SHA256: `8f9d43e6a92982b8a529b0b6e669053045d28112bfed6d82f852aa542ab800ca`.

The devbox template directory has only Linux/Windows files. Attempts to retrieve
Godot's matching template via the configured egress proxy failed during TLS
handshake. `local-macos-attempt.log` records the export's required-template error;
no macOS executable has been produced or executed in the devbox.

## CI Acceptance

The first hosted attempt, [40705437313](https://github.com/rapidhere121345/makeitbig/actions/runs/40705437313),
passed all 216 test steps and all golden replay checks, but rejected the Mac export
because ARM ETC2/ASTC texture imports were disabled. `ci-attempt1.log` preserves
the full output. Both the project import flag and the Universal preset's texture
format are now enabled. The second local gate (`astc-gate/`) freezes those final
settings. The independent Mac packaging job lets export errors and native tests
report without waiting for the hosted regression suite.

The desktop workflow exports the Universal app on Linux, verifies ZIP CRCs,
Mach-O architecture slices, per-slice code signature hashes, signed resource
hashes, metadata, and executable permissions, and uploads the ZIP/checksums as
`make-it-big-macos-universal`.

The new matrix uses native `macos-15` ARM64 and `macos-15-intel` runners. Both
verify the app with Apple's `codesign`, then run headless smoke and the golden
automation replay from an empty directory. Actual run URLs/results must be
recorded before claiming native macOS acceptance. These headless checks do not
establish GUI, audio, Retina appearance, or sustained GPU performance.

## Final Local Import Gate

`astc-gate/RESULT.json` records PASS from 2026-10-28T14:46:32Z to 2026-10-28T14:56:32Z. All 1486 frozen inputs remained unchanged.
The full 216-step suite, 600 encounters, golden replay checks, Linux/Windows
exports, and empty-directory Linux smoke passed with ARM texture imports enabled.
`texture-probe.log` confirms the effective Godot import flag and Universal preset.

- `build/current/linux/make-it-big.x86_64`: `bb0673360b6e3e82e5e720fe2ae82c03f8f31acfbfe2191fde95b72e47ac4e21`.
- `build/current/windows/make-it-big.exe`: `0367e8070f2526e8f80f5204965171aa4af1f6fde54b7cd384351c1a8f5da369`.

## Final Native macOS Acceptance

Source commit: `763057965efca4c8342c7e5b31b71eba0d40d5e1`.
[Run 40711416180](https://github.com/rapidhere121345/makeitbig/actions/runs/40711416180)
records successful `macos-package`, `macos-smoke (macos-15, arm64)`, and
`macos-smoke (macos-15-intel, x86_64)` jobs.

Both macOS 15 runners verified the two CPU slices and passed Apple's
`codesign --verify --deep --strict`, empty-directory startup, and full automation
replay. The replay reached Ending after the Colossus/Auto settlements and matched
`b98adeadd44d9fb428f1cb762304f8e09c252b2f00ce00583efb40bc8147200b`
on ARM64 and Intel. The complete hosted Linux regression job was still running
at this native acceptance; the frozen local 216-step gate had already passed
with the final runtime/import configuration. The last code change after that gate
only corrected the CI `lipo` argument order.

The preceding [run 40710980724](https://github.com/rapidhere121345/makeitbig/actions/runs/40710980724)
produced a valid ZIP, but both native jobs stopped before app launch because
`lipo` expects the executable before `-verify_arch`. Its package and failed
ARM check logs are retained as `ci-attempt2-package.log` and
`ci-attempt2-native-arm.log`. This was fixed without changing the app resources.

Final download: `build/current/macos/make-it-big-macos-universal.zip`,
113,310,977 bytes, SHA256
`f0199cd6b3a7a3c45615cbdc0ee714f0a4d549529d74439d9d6ace74201aba56`.
[GitHub artifact 12826526634](https://github.com/rapidhere121345/makeitbig/actions/runs/40711416180/artifacts/12826526634)
contains this ZIP, `SHA256SUMS`, and the replay reference hash.
The outer artifact ZIP SHA256 is
`c901edfa241641a333e7a410e57569fa3aca8bee6be391122e709af8a3047326`.
Both outer/inner hashes were verified on download; the package verifier also
passed again locally. The earlier ZIP was moved into `ci-attempt2-artifact/`
rather than deleted.

Evidence in `final/`: `macos-package.log`, `native-arm64.log`,
`native-intel.log`, `CI_RESULT.json`, and the downloaded ZIP/checksums.
`macos-pack-smoke.log` additionally records the earlier equivalent game pack
passing resource/route smoke through the Linux engine; this is not native Mac
execution evidence. Native proof is the two actual Mac jobs above.

No GUI, audio, Retina visual acceptance, or sustained GPU performance is claimed.
The app remains ad-hoc signed without Apple notarization; launch instructions
are in [macOS setup](../MACOS.md). No live page publication, deletion of old
release artifacts, host networking change, or agent restart was performed.
