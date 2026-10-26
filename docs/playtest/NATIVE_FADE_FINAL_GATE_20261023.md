# Native Fade Final Gate - PASS - 2026-10-23

Status: **the final gate PASSES (run `20261023T104409Z`), root accepted it
independently, and `ce1` completed the local publication (single build
`20261023-105532-5f4edd733ff5`). The operator subsequently reported access
fixed and supplied a replacement publish URL; no new endpoint check was requested.** Windows native execution is untested (the
export is hash-verified, never executed), and no global clean-log claim is
made below.

## Verified from the run artifacts (read-only)

`build/current/native-fade-final-gate-prep/runs/20261023T104409Z`:
`RESULT.json` `result: PASS`, exit 0; stage-1-check exit 0 (2 s) and
stage-2-container-build exit 0 (497 s), both completed with 0 leftover
processes. Freeze
`2eeabdac3b3dee8df8084abcad3e92b0fafad4eeb2a603915392a963797676eb`
before == after, `freeze.diff` empty, `freeze_drift: false`; the manifest
holds **1334 entries on both sides** (counted from the TSVs).

From `stage-2-container-build.log`:

- `test_repeatable_encounter_matrix.gd`: rooms 600, seeds 0..99, outcomes
  `{"victory": 600}`, **33894 ticks**.
- Full automation replay matched at 30/60/144 Hz **and** presentation-off
  60 Hz, state hash
  `b98adeadd44d9fb428f1cb762304f8e09c252b2f00ce00583efb40bc8147200b`.
- Smoke: `test_smoke_input_driver.gd` PASS; `GAME_FLOW_SMOKE_PASS`
  (title → tutorial → base/loadout/training → repeated contract/arena
  cycles → ending → base); `AUTO_SMOKE_PASS` (2 framework settlements,
  boss_ticks 1693, auto_ticks 50, early_game_complete); `SCENE_SMOKE_PASS`.
- Fresh export hashes: Linux `make-it-big.x86_64`
  `148ccc532f97f799fa298cc9c2f0405ee51d154dc4d5f83310f0ecff51c8bae5`
  (124263648 B); Windows `make-it-big.exe`
  `790fb02ea4f1dc3d3350cb2712b1f76e2138b99535407e3bd79b3648201cc742`
  (159871920 B). The stale preexisting exports were archived under the
  run (`preexisting-exports/`), not reused.

## Log honesty (no global clean claim)

The build log carries 47 `ERROR` lines: 44 cached-resource exit warnings
("N resources still in use at exit") and 3 negative-path diagnostics from
`tests/test_encounter_director.gd` (rejected fixture registration, invalid
quantize/collision results at test lines 209/225). The passing gate does
not treat them as failures; this record does not claim a clean log.

## Failed attempts preserved (no history rewrite)

- `103125Z`: `result: FAIL`, exit 1, **`stages: []`** — no engine stage
  ran; the aggregate step redirected a file onto itself
  (`manifest.final.err`). An ignored-runner repair was authorized (no
  runtime drift) and the gate was relaunched.
- `103351Z`: both stages passed (check exit 0; build exit 0, 507 s) but
  `freeze_drift: true` (`4bc015b8…` → `2eeabdac…`). `freeze.diff` is
  exactly 13 generated-metadata additions — 10 `town_modular_v01`
  `.png.import` sidecars and 3 `.uid` files (including
  `primitive_fade_controller.gd.uid`); no source or content file changed,
  so no substantive runtime drift. The final run retained this metadata
  baseline: its `freeze_before` equals this attempt's `freeze_after`.

## Publication (local complete; live access NOT verified)

`ce1` published locally, non-pruning: exactly one new build,
`20261023-105532-5f4edd733ff5`, under `release-online/` — nothing pruned or
deleted (the final-evidence log lists the full resulting tree; one build
present, `keep_builds` 20). `release-online/index.json` records it with the
gate's exact export hashes and sizes (`148ccc53…` / `790fb02e…`), git
revision `5f4edd733ff5`, and a note that **explicitly discloses the dirty
working tree** (uncommitted town R2/R3 occlusion + modular art sources), its
certification by gate run 20261023T104409Z, and freeze `2eeabdac…`
before == after. The build carries provenance sidecars (`gate-RESULT.json`,
`gate-exports.json`, `manifest.freeze.tsv`/`.aggregate`, `README.md`,
`SHA256SUMS`). Evidence logs, all passing, under
`build/current/native-fade-final-gate-publication/`: 01 pre-package
reconfirmation (both export hashes and the freeze re-hashed, all matching),
02 package, 03 index + site + `verify --deep` + `deploy/tailscale` static
validation + `stage_release_page.sh --check`, 04 final evidence (page embeds
the build id; packaged and provenance SHA256SUMS recorded). Root
independently re-hashed the packaged Linux/Windows binaries and the
provenance manifest.

The current publish URL is `http://192.0.2.10:18080/`, supplied by the
operator after reporting the access issue fixed. It replaces the former
HTTPS endpoint. The operator explicitly requested no endpoint check.
The earlier TLS failure (`SSL_ERROR_SYSCALL` after `CONNECT 200`) applied
to the former endpoint, not this URL. Local publication is complete;
access resolution is operator-reported, not independently verified here.

## Not accepted by this record

Independent verification of online availability (operator-reported resolution,
per the section above); Windows native execution; any whole-town art-migration
claim (the town stays two-region native with legacy elsewhere,
[native fade acceptance](TOWN_NATIVE_FADE_ACCEPTANCE_20261023.md)).
Crosslinks: [prior cleanup-era gate](CLEANUP_LAUNCHER_ACCEPTANCE_20261022.md),
[README](README.md).

<!-- Historical host identifiers in this document are sanitized examples; current service access comes from the approved directory or operator configuration. -->
