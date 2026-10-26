# Silhouette Fixture Acceptance - 2026-10-23

Status: **bounded fixture/static-visual acceptance — the silhouette reveal
fixture passes and its captured static states were visually accepted.** This
is not completed R3, not full-town silhouette acceptance, not migration, not
a full gate, and not publication. The earlier failed lane record is preserved
in [TOWN_LOADOUT_SAMPLE_ACCEPTANCE_20261023.md](TOWN_LOADOUT_SAMPLE_ACCEPTANCE_20261023.md)
(scope separation there).

## Evidence read (ignored `build/current/` artifacts; this file is the durable record)

- `sil-run/run.attempt4.json` — harness run, `pass: true`; fixture verdict
  `status: pass, errors: []`, 38 captures with SHA-256 each.
  `sil-run/silhouette-engine.attempt4.log` — 31 lines, ends
  `SILHOUETTE_GPU pass`; no shader compile/bind/SCRIPT-error patterns.
- `silhouette-gpu-r3-attempt3/REPORT.json` — `status: pass`, `errors: []`,
  38 captures; fixture note: frozen-pose frame-matched references, exact
  texel identities, no animation exemptions, readability deltas reported for
  visual review and never excluded.
- `sil-headless/run.attempt3.json` — headless cross-check: check-only and
  normal exits 0, error hits 0, verdict pass, 1.8 s.
- Attempt 4's cleanup record is the `cleanup` block inside
  `run.attempt4.json` (no `cleanup.attempt4.json` exists): owned Xvfb reaped,
  Xauthority removed, xvfb exit 0, temporary override removed. The standalone
  `sil-run/cleanup.json` (pid 293815) belongs to the earlier lane run.
- Failed records preserved, no history rewrite: harness `run.attempt1.json`
  fail (stale clear survived reset; flipped-pair transparent gap at
  (385,186)); `run.attempt2.json` fail (no reveal row covers the hero and
  protected Mira together); `run.attempt3.json` fail (raster containment:
  piece cleared at (360,224) where no actor draws; piece changed at 1 pixel).
  Fixture dir `silhouette-gpu-r3-attempt2/REPORT.json` still records fail
  with 5 errors.

## Identity chain (verified, not assumed)

All 38 capture hashes in `run.attempt4.json` match the on-disk PNGs in
`silhouette-gpu-r3-attempt3/`, and those PNGs are byte-identical (hash
comparison, 38/38) to `silhouette-gpu-r3-attempt2/` — pixels unchanged
between the failed and passed fixture reports; only the oracle's
interpretation changed. The failed attempt-3 harness log and the passed
attempt-4 log show identical inside/identity counts; raster counts rose by
6/12/11/8 across the original/flipped/moved/unprotected stages
(666→672, 668→680, 491→502, 675→683), identifying additional color-similar
actor pixels. Three pixels had caused the earlier failures; the counts' rise
is not attributable to exactly those three texels.

## Two fixture fixes (runtime frozen)

1. Authority tick: the fixture waits one tick after each placement so the
   published plan snapshot is authoritative — the log shows snapshot ticks
   advancing 16→17, 17→18, 18→19 with `plan_feet` matching committed feet
   only after the tick.
2. A second independent contrast check detects gray Mira texels at 2/255
   without changing tolerances or coordinate exemptions.

Fixture SHA-256 `3bde2c4fd5509c63063395140f17aef66960309e145bfee11b1509d5073ede9b`
(= current `tests/test_scene_atmosphere.gd`), identical before and after the
headless run; `tracked_files_unchanged` true in both records — runtime
hashes verified frozen.

## Stage counts (parsed from the attempt-4 engine log)

| Stage | inside/outside | identity | overlap | other |
| --- | --- | --- | --- | --- |
| original | 552/0 | 558/0 | 9 | readability covered 558 |
| flipped | 563/0 | 569/0 | 5 | readability covered 569 |
| moved | 451/0 | 451/0 | 0 | retired 64, retired opaque 64, retired fails 0 |
| unprotected | 135/0 | 135/0 | 29 | resident closed 445/0, revealed overlap 29/0 |
| after reset | — | — | — | reset identity diff 0 |

## Readability and parent visual review

Localized partial alpha darkening is still measured: original stage
mean delta 0.0067, max 0.2471 — this record does **not** claim a complete
underplate and does **not** claim dynamic acceptance. The parent viewed the
original/moved/unprotected pair-crop ×2 and original cover/actors-front
images in the prior attempt-2 set (hash-identical to the accepted set) and
the flipped pair-crop ×2 in the passed attempt-3 set. Visual verdict on the
captured static states: Mira's head/torso/clothing/edges legible; no blanket
gray, no perforation; removing protection restores the foreground.

## Environment

Windowed run as UID 1000 on private authenticated display `:204`
(Xauthority mode 0600, `-nolisten tcp`, `-noreset`, `-extension MIT-SHM`);
temporary `override.cfg` (threading worker pool 2, SHA recorded) removed at
cleanup. Renderer llvmpipe (LLVM 21.1.8, 256 bits), Godot 4.7.2 — CPU
correctness evidence only, no performance claims. Raw log scanned broadly
(compilation failed / unable to bind / SCRIPT ERROR): clean; the earlier
lane's CanvasShaderGLES3 compile failure does not appear here.

## Not accepted by this record

Completed R3; full-town silhouette behavior; animation/dynamic reveal;
migration of any shipped art; the full gate; publication binaries (a fresh
gate is required before any publication, per the standing rule).

Crosslinks: [sample acceptance](TOWN_LOADOUT_SAMPLE_ACCEPTANCE_20261023.md),
[Round-2 runs](TOWN_ROUND2_20261023.md),
[modular foundation](TOWN_MODULAR_FOUNDATION_20261022.md).
