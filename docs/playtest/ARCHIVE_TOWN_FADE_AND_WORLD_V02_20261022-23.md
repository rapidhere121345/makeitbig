# Archive: Town Fade and Generated World v02 Records (2026-10-22 to 2026-10-24)

These ten reports were consolidated on 2026-10-26 because the work they describe
was superseded: the town is now modular-only with whole-object paired reveal,
angled generated scenery and the world-expansion/town-order art. Each entry keeps
the date, scope, outcome, build id (if any) and the superseding work. They are
historical records, not the current checkout's test status. The full original
texts remain in Git at `0711df8` under `docs/playtest/`; use
`git show 0711df8:docs/playtest/<FILE>.md` when exact evidence is needed. Ignored
`build/current/` evidence directories named below may no longer exist.

Still-valid procedures extracted from these reports now live in
[GRAPHICAL_VALIDATION.md](../GRAPHICAL_VALIDATION.md) (rendered-run evidence
hygiene) and
[generated-world-v02/README.md](../art-production/generated-world-v02/README.md)
(Godot import identity).

## Modular town foundation and calibration (2026-10-22)

### TOWN_MODULAR_FOUNDATION_20261022

- Scope: the authored-object contract (`EnvironmentObjectDefinition`,
  `Placement`, `Baker`), shader double-sampling fix, unified actor/native sort
  rank, authored reveal controller, and a labeled greybox preview
  (`tools/modular_town_preview.gd`) mounted through the real town runtime.
- Outcome: technical foundation accepted on GPU (RTX 4080 SUPER) over four
  mounted greybox rounds (R2 and R3 rejected on visual review, R4 accepted as
  greybox only, 60 checks, 14 frames). Frozen full build passed independently
  (600/600 victories, 33894 ticks, both exports, smoke). Production town art and
  whole-town migration were explicitly incomplete.
- Build id: none.
- Superseded by: the modular-only native town (`town_scene_root.gd`), the
  world-expansion and town-order art, and the
  [world expansion](WORLD_EXPANSION_20261025.md) and
  [town performance and layout](TOWN_PERFORMANCE_LAYOUT_20261026.md) records.
  The preview tool, the town_modular_v01 sample art and its object definitions
  were deleted on 2026-10-26; the EnvironmentObject system is tested with
  synthetic fixtures.

### TOWN_MODULAR_CALIBRATION_20261022

- Scope: one real windowed CPU (llvmpipe) run of the unmodified greybox preview
  to close plan step 2.
- Outcome: accepted as greybox technical calibration only: 60 checks, 0 failed,
  14 frames; building envelope stop, camera pan bound and gate round-trip at
  30/120 fps all matched; nine frames reviewed. Not production-art acceptance.
- Build id: none.
- Superseded by: the Loadout sample record below and then the native town work
  listed above.

## Loadout sample, silhouette fixture and primitive fade (2026-10-23)

### TOWN_LOADOUT_SAMPLE_ACCEPTANCE_20261023

- Scope: first production building (Loadout) rendered over greybox ground in the
  preview harness (`town_loadout_v01.tres`).
- Outcome: sample preview accepted (63/63 checks, 15 frames reviewed; default
  run 60/60). Shipped-town integration was pending. The same harness session's
  silhouette fixture failed because of a `CanvasShaderGLES3` compile error
  (sampler arrays indexed by a non-constant expression); the harness's
  `*_shader_errors` counter read 0 because it counted only literal `SHADER ERROR`.
- Build id: none.
- Superseded by: native Loadout art in the shipped town and the later paired
  whole-object scenery; the harness-counter lesson is kept in GRAPHICAL_VALIDATION.md.

### TOWN_SILHOUETTE_ACCEPTANCE_20261023

- Scope: the silhouette reveal fixture (`tests/test_scene_atmosphere.gd`, GPU
  mode) and its static visual states.
- Outcome: fixture passed on attempt 4 (38 hash-chained captures; headless
  cross-check passed) and static states were visually accepted. Attempts 1-3
  failed and were kept. Two fixture fixes: wait one authority tick after each
  placement; add an independent gray-Mira contrast check. Not completed R3,
  full-town silhouette behavior, migration or publication.
- Build id: none.
- Superseded by: the native silhouette/paired reveal controllers and the
  whole-object reveal in generated world v02.

### TOWN_PRIMITIVE_FADE_SAMPLE_ACCEPTANCE_20261023

- Scope: mixed-sample primitive roof and canopy fade in the preview harness
  (`town_loadout_fade_v01.tres`, `town_pine_v02.tres`).
- Outcome: accepted as a mixed sample: five runs passed (60/60, 63/63, 88/88,
  108/108, 135/135 checks), 83 frames hash-verified by a verifier gate, seven
  malformed-definition probes rejected. Invalid hollow passes (attempts 02/03,
  runtime `SCRIPT ERROR` after exit 0) were recorded and never counted. Not
  native-town acceptance, a full gate or publication.
- Build id: none.
- Superseded by: native fade (next entry) and then by whole-object
  opaque/transparent pairs, which replaced primitive roof/canopy fades for new
  scenery.

## Native fade and its gate (2026-10-23)

### TOWN_NATIVE_FADE_ACCEPTANCE_20261023

- Scope: native primitive fade in two shipped-town regions (Loadout building,
  `tree_south`) through fixture-based windowed play runs (A through H phases).
- Outcome: partial native acceptance. Fade contract exact per piece (open weight
  1.0, alpha 0.25, 0.18 s transition; actor opaque; common layer excluded).
  Closed: C5 fence corner and B8 west-gate (corrected continuation runs), B9
  (classified untouchable by geometry, not a contact pass), E, F and G. Open
  limits: shore sustained contact proven on one leg only; NW corner unreachable
  (no claim); the rest of the town still ran legacy occlusion. Six initial runs
  failed or stopped and were kept.
- Build id: none (see the final gate below).
- Superseded by: the whole-object paired reveal in generated world v02 and the
  modular-only town.

### NATIVE_FADE_FINAL_GATE_20261023

- Scope: frozen full gate after the native fade work, plus local publication.
- Outcome: gate `20261023T104409Z` PASS (600/600 victories, 33894 ticks; replay
  matched at 30/60/144 Hz and presentation-off; smoke green; fresh export
  hashes; 1334-entry freeze manifest identical before and after). Failed
  launcher attempts `103125Z` and `103351Z` were kept. Operator tailnet
  verification of the endpoint and native Windows execution stayed outstanding.
- Build id: `20261023-105532-5f4edd733ff5` (dirty tree disclosed in its index
  note).
- Superseded by: later gates and builds; see
  [Generated world v02](#generated_world_v02_acceptance_20261023) and the
  current entries in [README.md](README.md).

## Town round 2 (2026-10-23)

### TOWN_ROUND2_20261023

- Scope: two interactive windowed sessions of the shipped town (Round-2).
- Outcome: INCOMPLETE, no overall pass. Run 1: 6 pass / 2 fail (including a
  lock-busy `DRIVER_ERROR` from overlapping drivers). Run 2: no summary;
  D1/D2 and the four `C3_tsouth_push*` checks failed (D1/D2 assertions were
  later judged invalid slide artifacts). Shore seal stopped at clearance 6.0 and
  the historic trap point (790.58, 874.11) was unreachable. Zero open occluder
  rows in the C4 pair frame, so no two-occluder claim.
- Build id: none.
- Superseded by: the native fade runs above (which closed the Board, Leia,
  Taren, shore and tree checks) and the later town records.

## Generated world v02 (2026-10-23) and the rejected polish (2026-10-24)

### GENERATED_WORLD_V02_ACCEPTANCE_20261023

- Scope: first fully regenerated town and battlefield scenery and grounds (24
  generated images, 35 whole paired sprites, 13 blockers per combat room),
  conservative collision, spawn/steering corrections, rendered town (118 checks)
  and arena (121 required checks) runs, frozen gate and local publication.
- Outcome: PASS. Gate `20261023T194229Z` (1479-entry freeze identical; 600
  victories, 28745 ticks). Key lesson: Godot's default alpha-border repair
  changed invisible RGB pixels and failed town fingerprints, so all generated
  texture `.import` sidecars pin `process/fix_alpha_border=false` and a
  post-import test requires exact RGBA8 identity.
- Build id: `20261023-195126-5f4edd733ff5` (alpha 64 faded state).
- Superseded by: the angled-world demo
  ([ANGLED_WORLD_DEMO_20261024.md](ANGLED_WORLD_DEMO_20261024.md)) after the user
  rejected the front-facing art. The front-facing raw sources were retired on
  2026-10-26; see the generated-world-v02 README.

### SCENERY_POLISH_20261024 (rejected work)

- Scope: coarse dark scenery pass: 17 families and two grounds regenerated in
  very coarse pixel clusters, ground footprint padding 3 to 5 native pixels,
  faded alpha 64 to 128.
- Outcome: targeted and rendered checks passed (town 810 checks, arena 129
  required checks) but the user rejected the art perspective and style as
  almost front-on and far coarser than the Ranger. The frozen gate
  `20261024T164129Z` failed (`test_authored_combat_room.gd`, elite did not
  summon a replacement or drop authored loot; cause not isolated in that
  record); an earlier attempt was interrupted. Nothing was published. The rejected
  drafts (`polish-20261024/`) were deleted on 2026-10-26. The padding of 5
  pixels, alpha 128 and enlarged detection regions were kept by later work.
- Build id: none published.
- Superseded by: [ANGLED_WORLD_DEMO_20261024.md](ANGLED_WORLD_DEMO_20261024.md),
  published as `20261024-172341-5f4edd733ff5`.
