# macOS Download and Validation

The `macOS Universal` preset produces
`build/current/macos/make-it-big-macos-universal.zip`. It contains
`Make It Big.app` with ARM64 (Apple Silicon) and x86_64 (Intel) executable slices.
The template minimums are macOS 13 on Apple Silicon and macOS 11 on Intel.
Retina rendering, English/Simplified Chinese, and the saved display settings use
the same game resources as Linux and Windows.
The project imports both desktop S3TC/BPTC and ARM ETC2/ASTC texture families,
as required by Godot's Universal exporter.

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

A partial `build.sh linux windows` gate (see the environment workflow) does not validate or produce macOS.

`scripts/verify_macos_export.py` verifies the ZIP CRCs, ARM64/Intel Mach-O slices,
per-slice executable signature hashes, resource manifest hashes, app metadata,
Retina flag, game pack, and executable permissions. The export writes an adjacent
`SHA256SUMS`. These checks do not execute macOS code.

## Native Checks and Downloads

Native macOS CI checks, publication gates and download locations are described in
the [release workflow](RELEASE_WORKFLOW.md). Headless smoke and replay do not
establish GUI, audio, Retina, or sustained GPU performance.
