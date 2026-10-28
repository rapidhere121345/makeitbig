# GitHub Release Migration — 2026-10-28

Status: packaging/static checks and the frozen local gate passed. Tagged CI
publication is pending. Evidence is under ignored
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

The first release is planned as `v0.1.0`, matching the current Mac application
version and Ranger Chapter One demo. It will include Windows/Linux archives,
the exact Universal Mac ZIP verified by native jobs, `SHA256SUMS`, `build.json`,
and `RELEASE_NOTES.md`. Actual tag/commit, CI run, asset hashes, and release URL
will be recorded after publication. No publication claim is made yet.

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
tagged CI will rebuild all platforms and run native checks before publication.
All 29 old publication files stayed unchanged during the gate and were then
archived with matching hashes. Archive-location documentation was updated after
the gate; runtime/content and packaging code were unchanged.
