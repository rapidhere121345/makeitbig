# Primitive Roof/Canopy Fade - Mixed-Sample Acceptance - 2026-10-23

Status: **accepted MIXED SAMPLE primitive roof/canopy fade in the preview
harness** — not native town acceptance, not full-town art, not a full gate,
not publication. Evidence lives under ignored `build/current/preview-adaptation/`.

## Verified runs (all facts re-read from the artifacts)

| Run | Definition mounts | Checks | Frames | fade checks | Exit |
| --- | --- | --- | --- | --- | --- |
| attempt01 `01-default` | none (greybox default) | 60/60 | 14 | — | 0 pass |
| attempt01 `02-old-loadout` | `town_loadout_v01.tres` (authored variant) | 63/63 | 15 | — | 0 pass |
| attempt04 `03-fade-loadout` | `town_loadout_fade_v01.tres` | 88/88 | 17 | 21 | 0 pass |
| attempt04 `04-fade-pine` | `town_pine_v02.tres` (tree-west/east) | 108/108 | 17 | 37 | 0 pass |
| attempt04 `05-combined-fade` | both fade mounts | 135/135 | 20 | 57 | 0 pass |

83 captured frames total. Tool `tools/modular_town_preview.gd` SHA-256
`849427b797635da9f0ee0fa7c4df35e5f4324634df224fa4a567a2a5dd4a3463`. New
definitions: `town_loadout_fade_v01.tres` `e473a75d…d9eea52`,
`town_pine_v02.tres` `cd4d0bf3…3dae522a` (tree-west (480,210), tree-east
(650,300), `primitive_fade`; REPORT SHAs match fresh file hashes). The
compatibility runs keep the accepted authored-variant loadout green.

## Mechanical verification

`attempt04/verify.py` (raw SCRIPT/Parse/SHADER-error scan, positive fade
inventory, exact capture set, per-PNG sha256 vs REPORT) re-run for this
record: `VERIFY PASS`, exit 0, inventories 21/37/57, captures 2/3/5. It
covers the three fade runs; the compatibility runs' raw logs were separately
re-scanned here — 0 hits each. The parent re-hashed all 83 captured PNGs and
scanned all five raw logs before accepting.

## Actual live-check coverage (as implemented, not overstated)

- Building roof: live material alpha, actor covered, and **common live alpha
  at open and exit** (`fade_roof_behind_common_live_alpha`,
  `fade_roof_exit_common_live_alpha`) plus actor live alpha at open and exit —
  the d19-required open/exit common/actor checks are satisfied; front state:
  no actor coverage, same overlap solid.
- Pine west: open quarter, material, actor-covered, common and actor live
  alpha; hold rechecks the quarter and live actor alpha — **no separate
  common-live-alpha check at hold**; exit rechecks restored state, material,
  common, and actor live alpha.
- Pine east: open and exit checks including exit live alpha; **no dedicated
  east-exit capture PNG** — exit is verified by checks only.
- Common stays complete over the reveal area (`fade_bake_common_solid_*`);
  the roof is not aliased into authored reveal, no silhouette fallback.

## Malformed-reject matrix (7 probes, headless, exit 2, no output written)

Loader sample gate: `probe_upper_none`, `probe_common_variant`,
`probe_pine_envelope_id`; `validate()` gates: `probe_fade_with_variant`
(`primitive_fade_policy_conflict`), `probe_degenerate_volume`
(`invalid_environment_polygon`, collinear), `probe_missing_volumes`
(`missing_environment_occlusion_volumes`), `probe_unknown_policy`
(`invalid_environment_reveal_policy`). Logs: `reject-probe_*.log`.

## Failed history preserved (no rewrite)

- attempt01: fade runs failed `fade_bake_volumes_meta_*` only — the check
  compared sprite meta against untranslated definition-local volumes while
  the baker correctly carried translated world volumes; runtime correct,
  expectation wrong; compatibility passes stand untouched.
- attempt02/03: **INVALID hollow passes** — tool exit 0 but runtime
  `SCRIPT ERROR: Cannot convert argument 3 from Array to Dictionary` aborted
  the fade coroutine after its prologue (02: no runtime fade checks, no
  f-captures; 03: truncated at the world-volume checks). Never count these
  as passes.
- attempt04 wrapped the remaining bare-Array detail arguments and added the
  verifier gate (nonzero verifier exit fails an attempt regardless of tool
  exit code).

## Parent visual review

The parent inspected the old-loadout open/closed/default-pan frames, the
combined run's `03_open` (hero visible through the roof), and `f1..f5` (roof
behind faded / front solid, west pine fade and front, east pine fade), and
accepted the appearance: readable hero, solid base with complete actor
opacity, an ordinary quarter (25%) upper fade, complete sample-greybox ground.

## Environment and cleanup (actual records)

Renders as UID 1000 on owned private display `:199` (portable-kit Xauthority,
`-nolisten tcp`, `-noreset`, `-extension MIT-SHM`; a first custom-authority
try failed client auth and was restarted on the canonical path after lock
cleanup — `attempt01/commands.txt`). There is **no standalone cleanup file**
in this lane; lifecycle evidence is `attempt01/display.env`, `xvfb.pid`,
`logs/xvfb.log`; the recorded pid is no longer running and no `Xvfb :199`
process exists at record time. Renderer llvmpipe (LLVM 21.1.8) in all five
runs — CPU correctness evidence only, no performance claims.

## Native integration readiness (brief, not acceptance)

The fade definitions, validate() gates, and preview mounts above are the
scoped, frozen inputs a native integration would consume. A separate
delegated lane is running the authorized harness now; this record claims
nothing from it, and native visual acceptance is explicitly **not** granted
here. Background: [sample spec](../art-production/TOWN_LOADOUT_SAMPLE_SPEC.md),
[brief](../art-production/TOWN_MODULAR_ASSET_BRIEF.md), [processing
record](../art-production/p1-town-modular-v01/PROCESSING.md),
[foundation](TOWN_MODULAR_FOUNDATION_20261022.md), [sample
acceptance](TOWN_LOADOUT_SAMPLE_ACCEPTANCE_20261023.md); the authored-reveal
silhouette lane is separate
([record](TOWN_SILHOUETTE_ACCEPTANCE_20261023.md)).

## Not accepted by this record

Native/shipped-town fade behavior, full-town art, any full gate, publication
binaries — a fresh full gate remains required before publication (open town
work: [Round-2](TOWN_ROUND2_20261023.md)).
