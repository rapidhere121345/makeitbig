# GitHub Release Migration — 2026-10-28

Status: PASS. The frozen local gate, tagged CI, all native platform checks, and
GitHub publication completed successfully. Evidence is under ignored
`build/current/github-release-migration-20261028/`.

## Migration

The operator confirmed the old HTTP server was already stopped. No host service,
networking, container boundary, or agent lifecycle operation is part of this work.
The page templates, staging/server helpers, and host exposure example are removed.
The legacy validation command remains as a compatibility check for removal of
those sources and presence of the new GitHub publisher.

Downloads move to versioned GitHub Releases. New tags publish only after the full
Linux gate and native Windows, ARM64 Mac, and Intel Mac smoke/replay checks pass.
The publisher uploads all six files to a draft, then publishes; a failed upload
does not publish a partial release. Existing releases/packages are never replaced
or automatically pruned. The release job alone receives `contents: write` through
the ephemeral Actions token.

## Local Evidence

- Nine package/publisher regressions pass: all platforms, intact Mac ZIP, Linux
  execute mode, complete checksums, tampering, missing platforms, invalid tags,
  overwrite refusal, and safe draft/upload/publication sequencing.
- `package.log` records real Linux/Windows/Mac packaging and checksum/archive
  verification in an isolated local output root.
- `static.log` records shell/Python/Godot parsing, language policy, and authored
  manifest freshness checks. Workflow YAML parsing and the retired-page
  compatibility validator also pass.
- The full gate and legacy archive hash comparisons are recorded in `RESULT.json`.
  Runtime/content and build sources are frozen throughout that gate.

## Publication and Archive

[Release v0.1.0](https://github.com/rapidhere121345/makeitbig/releases/tag/v0.1.0)
was published at 2026-10-28T17:44:07Z. The GitHub API confirms a published stable
release with all six expected assets, nonzero sizes, and SHA256 digests. It includes
Windows/Linux archives, the exact Universal Mac ZIP verified by native jobs,
`SHA256SUMS`, `build.json`, and `RELEASE_NOTES.md`. `PUBLISHED.json` retains the
API response and completed job results; `ci-publisher.log` records package
verification followed by successful upload and publication.

The old publication directory was moved to
`build/archive/release-online-20261028/`. All 29 files match the complete
pre-move SHA256 manifest (`ARCHIVE.json`); the former root is absent. Binary
history was preserved without pruning. Historical acceptance records continue
to describe the former page as it existed at the time.

## Frozen Local Gate

`RESULT.json` records PASS from 2026-10-28T17:06:49Z to 2026-10-28T17:20:18Z.
All 1482 frozen inputs stayed unchanged. The complete 216-step suite,
600 encounters, replay hashes, Linux/Windows exports, and empty-directory Linux
smoke passed. The existing Universal Mac ZIP also passed real package verification;
tagged CI subsequently rebuilt all platforms and passed native checks before
publication.
All 29 old publication files stayed unchanged during the gate and were then
archived with matching hashes. Archive-location documentation was updated after
the gate; runtime/content and packaging code were unchanged.

## Tagged Source

Tag `v0.1.0` was pushed at source commit `240cf7709e5f6fbcc8ef3bad53633c728ce6321f`.
[Tagged desktop-build run 40734945204](https://github.com/rapidhere121345/makeitbig/actions/runs/40734945204)
passed all six jobs: build, macOS package, Intel macOS smoke, ARM64 macOS smoke,
Windows smoke, and GitHub release publication. The hosted full gate passed
216 steps with zero failures. The Linux export and native Windows, ARM64 Mac,
and Intel Mac replays matched the pinned state hash:
`b98adeadd44d9fb428f1cb762304f8e09c252b2f00ce00583efb40bc8147200b`.
Both native Mac jobs verified the Universal architectures and strict ad-hoc
signature before startup and replay. These headless checks do not establish
GPU performance or a new graphical play-through.

Following branch commits only record validation and use `[skip ci]` to avoid
duplicate branch builds of the same runtime. Release source remains the tag above.

## Published Assets

These sizes and SHA256 values are reported by GitHub for the uploaded assets.
The publisher verified archive structure and all package checksums before upload.

| Asset | Bytes | SHA256 |
| --- | ---: | --- |
| `build.json` | 732 | `8656e2fc7f9eb4e1cb6d4f6f0f297665423c86170f6bbac6ba6c4341b2b7f721` |
| `make-it-big-linux-x86_64.tar.gz` | 81155357 | `1c35d11b078cea118b75f005df29ea908167c3c9f956bb961e5dbb25194a46a6` |
| `make-it-big-macos-universal.zip` | 113314370 | `211f2c2e27c3e710d32d826d06322c3549620a4ae8569cfd931430afb04a7fea` |
| `make-it-big-windows-x86_64.zip` | 90866215 | `77e9c6a13928d10d565591f50cdd8190031a4626c6c33cecaf119109c5f69ffe` |
| `RELEASE_NOTES.md` | 881 | `757b9bbecba7992238097bf6a4c2a25d250ae73ed5999bfdcc2be7e38820ed6b` |
| `SHA256SUMS` | 453 | `b135300d9d47503b3efe34568290c983e97768c44617e49b0512d3525dd43214` |
