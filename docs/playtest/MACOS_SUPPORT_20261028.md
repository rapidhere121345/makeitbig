# macOS Universal Support — 2026-10-28

Status: frozen local regression gate passed; macOS export and native checks pending CI.

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

The desktop workflow exports the Universal app on Linux, verifies ZIP CRCs,
Mach-O architecture slices, per-slice code signature hashes, signed resource
hashes, metadata, and executable permissions, and uploads the ZIP/checksums as
`make-it-big-macos-universal`.

The new matrix uses native `macos-15` ARM64 and `macos-15-intel` runners. Both
verify the app with Apple's `codesign`, then run headless smoke and the golden
automation replay from an empty directory. Actual run URLs/results must be
recorded before claiming native macOS acceptance. These headless checks do not
establish GUI, audio, Retina appearance, or sustained GPU performance.
