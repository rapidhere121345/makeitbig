# Cleanup and Launcher Fix — Final Acceptance

Date: 2026-10-22. Status: **PASS**. Final full gate after the docs/tests
cleanup and the `check.sh` `MIB_TEST_PYTHON` launcher fix, closing this pass.
Evidence: `build/current/validation-final-20261022T224827Z/` (RESULT.md,
exit files, logs, freeze manifests, export hashes), HEAD
`1d7e013537097c248afde886333eb0d285e350e5`, UID 1000, portable environment.
The gate was validation-only: no tracked edits, commits, releases, or
infrastructure changes.

## Gate result (verified against the exit files and logs)

- `./scripts/check.sh` exit **0**; `./scripts/container_build.sh` exit **0**.
- Test gate: exit 0 with **0 `SCRIPT ERROR:` lines**.
- Repeatable-encounter matrix: `rooms=600 seeds=0..99
  outcomes={"victory":600} ticks=33894`.
- Replay golden `b98adeadd44d9fb428f1cb762304f8e09c252b2f00ce00583efb40bc8147200b`
  matched at 30, 60, and 144 Hz and presentation-off 60 Hz.
- Exports rebuilt: Linux `make-it-big.x86_64` `6ee26db7…bc7f` (123996232 B)
  and Windows `make-it-big.exe` `43f1e5aa…7f9` (159604504 B). Windows is
  export validation only, not native execution.
- Empty-directory Linux smoke: `SCENE_SMOKE_PASS framework=routes,builds,
  contract,persistence route=title`; final line `host build flow passed`.
- Freeze equality: `freeze-before.sha256` == `freeze-after.sha256`, identical
  **1204 files** across `src/ content/ art/production/p1/ project.godot
  export_presets.cfg scripts/ tests/`, manifest SHA256
  `edde10f058e639c45c8b7dadd8dd294a6498e64afd57a4af7b1b4c35f64f06b3`.
- Error inspection beyond exit codes: `ERROR:`/`WARNING:` lines match the
  accepted baseline in kind and count — known negative-fixture markers and
  Godot shutdown diagnostics only; nothing new.

## Pass checklist

- Docs/tests cleanup: done (superseded reports removed from the working tree,
  originals recoverable from `1d7e013`; [index](README.md) retained).
- `check.sh` Python launcher contract: done, bounded check verified.
- Modular greybox calibration (plan step 2): done —
  [calibration record](ARCHIVE_TOWN_FADE_AND_WORLD_V02_20261022-23.md#town_modular_calibration_20261022).
- Two raw Loadout base candidates: generation review done — verbatim
  [requests](../art-production/p1-town-modular-v01/PROMPTS.md), matching
  source/copy hashes and [provenance](../art-production/p1-town-modular-v01/PROVENANCE.md),
  corrected measurements exit 0
  ([review](../art-production/p1-town-modular-v01/CANDIDATE_REVIEW.md)). **Neither
  candidate is accepted for runtime**: candidate 02 improved pixel density
  but drifted in composition, and both need alpha/density/alignment
  correction next. No further generation or runtime integration in this pass.
- Final full gate: done, PASS (above).

## Still pending

The whole modular asset package and town migration (plan steps 3–6) remain
pending; this pass closed only the cleanup, launcher, calibration, candidate
review, and full-gate items. Future changes require their own fresh full gate
before delivery claims. Limits stand: fixture-based validation, not a human
playthrough; no native Windows execution; no performance or memory claims.
