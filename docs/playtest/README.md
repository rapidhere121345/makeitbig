# Acceptance Records

The retained records describe historical runs, not the current checkout's test
status. Consult logs and run fresh checks before making a new acceptance claim.

- [Town responsiveness and street layout](TOWN_PERFORMANCE_LAYOUT_20261026.md): CPU optimizations, road-facing facilities, clearer bridge landings and joined east walls; 27 captures and frozen full gate passed, build `20261026-081845-5f4edd733ff5` packaged.
- [Ground contact and local lighting](GROUNDING_LIGHT_20261025.md): final visual/full-build acceptance and published build `20261026-043825-5f4edd733ff5`; actor contact shadows, object base seams and restrained local light.
- [World expansion and modern displays](WORLD_EXPANSION_20261025.md): winding river, two bridge orientations, perimeter scenery, varied houses, distinct combat rooms and display settings; 16 rendered captures and frozen full gate passed. Local release `20261025-190800-5f4edd733ff5` preserves all prior builds.
- [World and UI polish](WORLD_UI_POLISH_20261025.md): 50 ground details, original skill icons/effects and full UI review; 330 UI checks, 148 required arena checks, frozen build/export/smoke PASS. Local release `20261025-105508-5f4edd733ff5`.
- [Actor redraw](ACTOR_REDRAW_20261024.md): new Ranger, residents, enemy families and articulated boss; actor and mounted-combat rendered acceptance passed. Frozen gate and local release `20261025-054740-5f4edd733ff5` passed.
- [Angled-world demo](ANGLED_WORLD_DEMO_20261024.md): certified angled scenery and ground footprints; previous published build `20261024-172341-5f4edd733ff5`.
- [Coarse dark scenery polish](SCENERY_POLISH_20261024.md): 810 town and 129 required arena render checks passed; user rejected the art perspective/style, and the full gate failed. Publication held for angled-view art correction and regression resolution.
- [2.5D world traversal](TOWN_2P5D_TRAVERSAL_20261024.md): ground footprints across town and battlefield scenery; 810 town and 129 required arena render checks, frozen full gate and local release `20261024-153604-5f4edd733ff5` passed.
- [Generated world v02 acceptance](GENERATED_WORLD_V02_ACCEPTANCE_20261023.md): new whole-object art, town/battlefield rendered checks, conservative collision, frozen full gate PASS and local publication `20261023-195126-5f4edd733ff5`.
- [Town and battlefield visual-quality pass](VISUAL_QUALITY_PASS_20261023.md):
  bounded mounted visual acceptance, 600/600 encounter matrix, frozen full
  build/export/smoke PASS and local publication `20261023-141101-5f4edd733ff5`.

- [Devbox migration](DEVBOX_MIGRATION_20261022.md): actual target full gate,
  English UI captures, export hashes, local packaging, and environment boundaries.
- [Modular town foundation](TOWN_MODULAR_FOUNDATION_20261022.md): authored
  objects/reveal implementation, greybox review, and unfinished production art.
- [Loadout sample acceptance](TOWN_LOADOUT_SAMPLE_ACCEPTANCE_20261023.md):
  first production building's rendered-sample preview acceptance (63/63 checks,
  all 15 frames reviewed), kept separate from the failing silhouette fixture;
  shipped-town integration pending.
- [Native fade acceptance](TOWN_NATIVE_FADE_ACCEPTANCE_20261023.md): partial
  native primitive-fade acceptance in two regions (Loadout, tree_south) from
  real town runs; C5/B8 closed by corrected continuation runs, B9 closed as
  continuous-geometry classification (not contact), E/F/G evidence recorded
  with the initial selector failure retained; shore contact proven on one leg
  only, NW corner unreachable (no claim); legacy elsewhere — no whole-town
  migration claim or town PASS; the full gate now passes
  ([final gate](NATIVE_FADE_FINAL_GATE_20261023.md)).
- [Native fade final gate](NATIVE_FADE_FINAL_GATE_20261023.md): fresh
  full-gate PASS 104409Z, root-accepted — 600/600 victories over 33894
  ticks, replay-locked automation at 30/60/144 Hz and presentation-off,
  smoke green, both fresh export hashes, freeze-verified 1334-entry
  manifest; failed launcher attempts 103125Z/103351Z preserved; published
  locally as the single build 20261023-105532-5f4edd733ff5 with provenance
  sidecars and the dirty tree disclosed — operator tailnet verification of
  the endpoint outstanding, Windows native execution untested.
- [Primitive fade sample acceptance](TOWN_PRIMITIVE_FADE_SAMPLE_ACCEPTANCE_20261023.md):
  mixed-sample primitive roof/canopy fade accepted in the preview harness
  (83 frames hash-verified, verifier-gated, failed attempts preserved);
  not native town acceptance, full gate, or publication.
- [Silhouette fixture acceptance](TOWN_SILHOUETTE_ACCEPTANCE_20261023.md):
  bounded static-visual acceptance of the silhouette reveal fixture (38
  captures, hash-chained, failed attempts preserved); not completed R3, full
  town, migration, gate, or publication.
- [Town Round-2 runs](TOWN_ROUND2_20261023.md): partial interactive evidence
  (reveal state facts, shore seal) with retained failures and driver-overlap
  provenance caveats; INCOMPLETE, no overall pass.
- [Modular town calibration](TOWN_MODULAR_CALIBRATION_20261022.md): fresh
  greybox CPU-render calibration of the unmodified modular preview through a
  real windowed run; plan step 2 closed with measured, numeric, and visual
  evidence.
- [Cleanup and launcher fix acceptance](CLEANUP_LAUNCHER_ACCEPTANCE_20261022.md):
  final post-fix full gate PASS (600/600 victories, replay matched at
  30/60/144 Hz, both exports, smoke, frozen 1204-file manifest) and this
  pass's closed checklist.

## Earlier Reviews

The October 18–22 incremental GPU, town collision, English-preparation, and
spatial-audit reports were consolidated during cleanup. Their original text is
retained in Git at `1d7e013`, under `docs/playtest/` and
`docs/rebuild/SPATIAL_AUDIT_20261019.md`. Use `git show <revision>:<path>` when
exact historical reproduction steps are needed. Ignored raw captures and failed
or interrupted logs were not deleted.

Those rounds recorded fixes for visible collider polygons, foreground lookup,
dialogue/Report focus, range messages, town fence/log trapping, bridge boundaries,
and cutout shader compilation. Later modular work fixed shader double sampling
and introduced authored reveal. Do not reintroduce earlier fading rules or treat
the original defect lists as current bugs. Those mechanism checks alone did not establish production-town acceptance;
the later world-expansion and town-layout records above document that work.

## Follow-ups to Recheck

These are historical gaps or observations, not newly reproduced defects:

- Pointer combat against close/moving targets, blank clicks, and rapid movement
  needs a continuous rendered playtest; earlier UI click-through fixes alone
  did not establish full mouse-combat acceptance.
- Review the expanded result report's last Next Step line, room completion
  indicators, positive Training verification, and Manual loot pickup timing.
  Earlier reports lacked positive coverage or recorded potentially stale UI
  findings; inspect current code before changing behavior.
- Check hero contrast on snow, close-contact friend/foe readability, wall-foot
  alignment, and training health/feedback indicators in the current art.
- Replay the south-shore route near `(790.58, 874.11)` during town acceptance.
  An old report recorded a trap; the current scene includes `south_bank_seal`.
  The old coordinates are a regression route, not proof the trap remains.
- Dummy-audio captures did not validate sound, mixing, or audiovisual sync.
  Shutdown resource warnings and an isolated unexplained exit did not establish
  a long-run memory/stability result. Native Windows execution and performance
  remain separate acceptance work.
- An early interactive review's backlog recorded no observed health loss while
  surrounded for 200+ ticks, with reproduction pending. Verify the intended
  surround damage cadence in current code and a rendered run instead of
  asserting a current gameplay bug.
- The old spatial audit suspected combat plan-alpha and the hero cutaway both
  process the same actor pair, leaving rear actors gray, and its 2026-10-20
  fix addendum did not mark that overlap resolved. Verify which pipeline owns
  pair dimming today before changing it.

Historical raw-evidence roots include `build/current/gpu-ux-review-20261018-*`,
`gpu-visual-r3-glm/`, `town-cutout-r4d/`, and `english-visual-20261024/` beneath
`build/current/`. Names are evidence identifiers; the last tag is not the actual
run date. Availability of these old local directories is not assumed after migration.
