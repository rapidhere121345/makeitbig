# macOS Download and Validation

The `macOS Universal` preset produces
`build/current/macos/make-it-big-macos-universal.zip`. It contains
`Make It Big.app` with ARM64 (Apple Silicon) and x86_64 (Intel) executable slices.
The template minimums are macOS 13 on Apple Silicon and macOS 11 on Intel.
Retina rendering, English/Simplified Chinese, and the saved display settings use
the same game resources as Linux and Windows.

Unzip the download, drag `Make It Big.app` into Applications, and open it.
The app uses Godot's built-in ad-hoc signature and is not Apple-notarized. If
macOS blocks the first launch, open System Settings → Privacy & Security and
choose Open Anyway for Make It Big. Do not disable Gatekeeper globally.
See [Godot's macOS export guide](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_macos.html)
and [launch guidance](https://docs.godotengine.org/en/4.7/tutorials/export/running_on_macos.html).

## Building on Linux

Install the matching standard Godot 4.7.2 export templates, including `macos.zip`,
into the template directory described in [the environment workflow](HOST_WORKFLOW.md).
No Xcode, Apple SDK, or Developer ID is needed for the ad-hoc build.

```bash
./scripts/with_env.sh ./scripts/build.sh        # full gate, all desktop exports
./scripts/with_env.sh ./scripts/export.sh macos # macOS export only
```

Explicit targets also support `linux` and `windows`. For a partial environment
without the macOS template, `build.sh linux windows` runs the full test suite,
those two exports, and Linux smoke. It does not validate or produce macOS.
All-target exports fail if any required template is missing.

`scripts/verify_macos_export.py` verifies the ZIP CRCs, ARM64/Intel Mach-O slices,
per-slice executable signature hashes, resource manifest hashes, app metadata,
Retina flag, game pack, and executable permissions. The export writes an adjacent
`SHA256SUMS`. These checks do not execute macOS code.

## Native Checks and Downloads

The `desktop-build` GitHub workflow exports on Linux and uploads
`make-it-big-macos-universal` (the ZIP and checksums). It also verifies the app
with Apple's `codesign`, then runs headless boot and golden automation replay
from an empty directory on both `macos-15` ARM64 and `macos-15-intel` runners.
Review the actual run results before claiming native acceptance. Headless smoke
and replay do not establish GUI, audio, Retina, or sustained GPU performance.

Release packaging and the download page support the `macos` platform. Older
Windows/Linux-only builds remain readable and show macOS as unavailable. A new
export does not automatically publish or prune the live release history.
